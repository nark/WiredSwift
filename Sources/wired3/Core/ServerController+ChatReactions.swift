//
//  ServerController+ChatReactions.swift
//  wired3
//
//  Handles wired.chat.add_reaction, wired.chat.remove_reaction,
//  wired.chat.get_reactions and stamps server-assigned message IDs
//  on outgoing wired.chat.say / wired.chat.me broadcasts.
//
//  State lives in ChatReactionsStore — an in-memory ring buffer per
//  public chat. When a message scrolls off the buffer, its reactions
//  are dropped; this is consistent with the "chat is a stream" model
//  and is documented in the 3.2 spec.
//

import Foundation
import WiredSwift

/// In-memory ring buffer of recent chat messages, plus the per-message
/// reaction state. One instance per public chat, owned by ChatsController.
public final class ChatReactionsStore {
    /// Default size negotiated for 3.2.
    public static let defaultBufferSize = 500

    private struct Entry {
        let messageID: String
        var reactions: [String: String]   // login -> emoji
        var nicks: [String: String]       // login -> nick (snapshot)
    }

    private let lock = NSLock()
    private var buffer: [Entry] = []
    private var index: [String: Int] = [:]   // messageID -> position in buffer
    private let capacity: Int

    public init(capacity: Int = ChatReactionsStore.defaultBufferSize) {
        self.capacity = capacity
    }

    /// Stamp a new message id into the buffer. Evicts the oldest entry when
    /// the ring is full.
    public func register(messageID: String) {
        lock.lock(); defer { lock.unlock() }
        if buffer.count >= capacity {
            let evicted = buffer.removeFirst()
            index.removeValue(forKey: evicted.messageID)
            // Indices shift by one; rebuild lazily — only entries kept.
            for i in 0..<buffer.count { index[buffer[i].messageID] = i }
        }
        buffer.append(Entry(messageID: messageID, reactions: [:], nicks: [:]))
        index[messageID] = buffer.count - 1
    }

    public struct ToggleResult {
        public let added: Bool
        public let count: Int
        public let removedEmoji: String?
        public let removedCount: Int
    }

    /// Add a reaction. If the same login already reacted with a different
    /// emoji on this message, the old reaction is replaced (single reaction
    /// per user per message — same model as boards).
    public func add(messageID: String, emoji: String, login: String, nick: String) -> ToggleResult? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = index[messageID] else { return nil }
        var entry = buffer[idx]
        let removedEmoji = entry.reactions[login]
        entry.reactions[login] = emoji
        entry.nicks[login] = nick
        buffer[idx] = entry

        let count = entry.reactions.values.filter { $0 == emoji }.count
        let removedCount: Int
        if let old = removedEmoji, old != emoji {
            removedCount = entry.reactions.values.filter { $0 == old }.count
        } else {
            removedCount = 0
        }
        return ToggleResult(
            added: true,
            count: count,
            removedEmoji: (removedEmoji != emoji) ? removedEmoji : nil,
            removedCount: removedCount
        )
    }

    /// Remove the caller's reaction. Returns nil when the message id is
    /// unknown (evicted) or when the caller had no matching reaction.
    public func remove(messageID: String, emoji: String, login: String) -> ToggleResult? {
        lock.lock(); defer { lock.unlock() }
        guard let idx = index[messageID] else { return nil }
        var entry = buffer[idx]
        guard entry.reactions[login] == emoji else { return nil }
        entry.reactions.removeValue(forKey: login)
        entry.nicks.removeValue(forKey: login)
        buffer[idx] = entry
        let count = entry.reactions.values.filter { $0 == emoji }.count
        return ToggleResult(added: false, count: count, removedEmoji: nil, removedCount: 0)
    }

    public struct Summary {
        public let emoji: String
        public let count: Int
        public let isOwn: Bool
        public let nicks: [String]
    }

    /// Build the per-emoji summaries for a message, with `isOwn` resolved
    /// against `currentLogin`. Returns an empty array when the message id
    /// is unknown (evicted from the buffer).
    public func summaries(messageID: String, currentLogin: String) -> [Summary] {
        lock.lock(); defer { lock.unlock() }
        guard let idx = index[messageID] else { return [] }
        let entry = buffer[idx]
        var byEmoji: [String: (count: Int, isOwn: Bool, nicks: [String])] = [:]
        // Stable order: iterate logins sorted to keep nicks deterministic.
        for login in entry.reactions.keys.sorted() {
            let emoji = entry.reactions[login]!
            let nick = entry.nicks[login] ?? login
            var slot = byEmoji[emoji] ?? (count: 0, isOwn: false, nicks: [])
            slot.count += 1
            if login == currentLogin { slot.isOwn = true }
            slot.nicks.append(nick)
            byEmoji[emoji] = slot
        }
        return byEmoji
            .map { Summary(emoji: $0.key, count: $0.value.count, isOwn: $0.value.isOwn, nicks: $0.value.nicks) }
            .sorted { $0.emoji < $1.emoji }
    }

    /// Whether the buffer currently knows about this message id.
    public func contains(messageID: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return index[messageID] != nil
    }
}

extension ChatsController {
    /// Returns (or lazily creates) the reactions store for a public chat.
    /// Private chats get nil — reactions on private messages are out of
    /// scope for 3.2 per the issue.
    public func reactionsStore(for chat: Chat) -> ChatReactionsStore? {
        if chat is PrivateChat { return nil }
        return chatReactionStores.exclusivelyWrite {
            if let existing = self._chatReactionStores[chat.chatID] { return existing }
            let store = ChatReactionsStore()
            self._chatReactionStores[chat.chatID] = store
            return store
        }
    }
}

extension ServerController {

    // MARK: - Reaction handlers

    func receiveChatAddReaction(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.chat.add_reactions") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        guard let chatID = message.uint32(forField: "wired.chat.id"),
              let messageID = message.string(forField: "wired.chat.message.id"), !messageID.isEmpty,
              let emoji = message.string(forField: "wired.chat.reaction.emoji"), !emoji.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        guard let chat = App.chatsController.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        guard chat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }
        guard let store = App.chatsController.reactionsStore(for: chat) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let nick = client.nick ?? user.username ?? ""
        let login = user.username ?? ""
        guard let result = store.add(messageID: messageID, emoji: emoji, login: login, nick: nick) else {
            // Unknown message id — likely evicted from the ring buffer.
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        App.serverController.replyOK(client: client, message: message)

        if let oldEmoji = result.removedEmoji {
            broadcastChatReaction(chat: chat, messageID: messageID, emoji: oldEmoji,
                                  count: result.removedCount, nick: nick, added: false)
        }
        broadcastChatReaction(chat: chat, messageID: messageID, emoji: emoji,
                              count: result.count, nick: nick, added: true)
    }

    func receiveChatRemoveReaction(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.chat.add_reactions") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        guard let chatID = message.uint32(forField: "wired.chat.id"),
              let messageID = message.string(forField: "wired.chat.message.id"), !messageID.isEmpty,
              let emoji = message.string(forField: "wired.chat.reaction.emoji"), !emoji.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        guard let chat = App.chatsController.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        guard chat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }
        guard let store = App.chatsController.reactionsStore(for: chat) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let login = user.username ?? ""
        let nick = client.nick ?? login
        guard let result = store.remove(messageID: messageID, emoji: emoji, login: login) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        App.serverController.replyOK(client: client, message: message)
        broadcastChatReaction(chat: chat, messageID: messageID, emoji: emoji,
                              count: result.count, nick: nick, added: false)
    }

    func receiveChatGetReactions(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard let chatID = message.uint32(forField: "wired.chat.id"),
              let messageID = message.string(forField: "wired.chat.message.id"), !messageID.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        guard let chat = App.chatsController.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        guard chat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }
        guard let store = App.chatsController.reactionsStore(for: chat) else {
            App.serverController.replyOK(client: client, message: message)
            return
        }
        let login = user.username ?? ""
        for summary in store.summaries(messageID: messageID, currentLogin: login) {
            let reply = P7Message(withName: "wired.chat.reaction_list", spec: self.spec)
            reply.addParameter(field: "wired.chat.id", value: chatID)
            reply.addParameter(field: "wired.chat.message.id", value: messageID)
            reply.addParameter(field: "wired.chat.reaction.emoji", value: summary.emoji)
            reply.addParameter(field: "wired.chat.reaction.count", value: UInt32(summary.count))
            reply.addParameter(field: "wired.chat.reaction.is_own", value: summary.isOwn)
            if !summary.nicks.isEmpty {
                reply.addParameter(field: "wired.chat.reaction.nicks", value: summary.nicks.joined(separator: "|"))
            }
            self.reply(client: client, reply: reply, message: message)
        }
        App.serverController.replyOK(client: client, message: message)
    }

    // MARK: - Broadcast

    private func broadcastChatReaction(chat: Chat, messageID: String, emoji: String,
                                       count: Int, nick: String, added: Bool) {
        let messageName = added ? "wired.chat.reaction_added" : "wired.chat.reaction_removed"
        chat.withClients { toClient in
            // Skip clients on a pre-3.2 spec — they don't know the message
            // and would log an unknown-message warning. The compatibility
            // diff machinery would also drop the whole frame, so this is
            // belt-and-braces.
            guard toClient.socket.peerKnows(messageNamed: messageName) else { return }
            let broadcast = P7Message(withName: messageName, spec: toClient.socket.spec)
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.chat.message.id", value: messageID)
            broadcast.addParameter(field: "wired.chat.reaction.emoji", value: emoji)
            broadcast.addParameter(field: "wired.chat.reaction.count", value: UInt32(count))
            if added {
                broadcast.addParameter(field: "wired.chat.reaction.nick", value: nick)
            }
            App.serverController.send(message: broadcast, client: toClient)
        }
    }
}
