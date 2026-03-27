//
//  ChatsController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB

struct ChatTypingKey: Hashable {
    let chatID: UInt32
    let userID: UInt32
}

extension ChatsController {
    // MARK: - Privates

    func describe(chat: Chat) -> String {
        let kind = chat is PrivateChat ? "private" : "public"
        let name = chat.name ?? "Private Chat"
        return "kind=\(kind) chatID=\(chat.chatID) name='\(name)'"
    }

    func add(chat: Chat) {
        self.chatsLock.exclusivelyWrite {
            if let existing = self.chats[chat.chatID] {
                Logger.error("Replacing existing chat with duplicate ID: existing={\(self.describe(chat: existing))} incoming={\(self.describe(chat: chat))}")
            }

            self.publicChats.removeAll { $0.chatID == chat.chatID }
            self.privateChats.removeAll { $0.chatID == chat.chatID }
            self.chats[chat.chatID] = chat

            if let privateChat = chat as? PrivateChat {
                self.privateChats.append(privateChat)
            } else {
                self.publicChats.append(chat)
            }
        }
    }

    func remove(chat: Chat) {
        clearTypingState(forChatID: chat.chatID)

        self.chatsLock.exclusivelyWrite {
            self.chats[chat.chatID] = nil

            if let privateChat = chat as? PrivateChat {
                if let i = self.privateChats.firstIndex(where: { (inchat) -> Bool in privateChat.chatID == inchat.chatID }) {
                    self.privateChats.remove(at: i)
                }
            } else {
                if let i = self.publicChats.firstIndex(where: { (inchat) -> Bool in chat.chatID == inchat.chatID }) {
                   self.publicChats.remove(at: i)
               }
            }
        }
    }

    func chat(withID chatID: UInt32) -> Chat? {
        return self.chatsLock.concurrentlyRead {
            self.chats[chatID]
        }
    }

    // SECURITY (FINDING_C_009): Protect lastChatID increment with lock to prevent duplicate IDs
    func nextChatID() -> UInt32 {
        var newID: UInt32 = 0
        self.chatsLock.exclusivelyWrite {
            var candidate = self.lastChatID

            while candidate < UInt32.max {
                candidate += 1

                if self.chats[candidate] == nil {
                    self.lastChatID = candidate
                    newID = candidate
                    return
                }
            }

            Logger.fatal("Exhausted chat ID space while allocating a new chat ID")
        }
        return newID
    }

    func receiveChat(string: String, _ client: Client, _ message: P7Message, isSay: Bool) {
        // SECURITY (FINDING_C_006): Rate limit chat messages (max 10/s per client)
        let now = Date()
        let exceeded: Bool = {
            self.chatRateLock.lock()
            defer { self.chatRateLock.unlock() }
            var timestamps = self.chatMessageTimestamps[client.userID] ?? []
            let cutoff = now.addingTimeInterval(-1.0)
            timestamps = timestamps.filter { $0 > cutoff }
            if timestamps.count >= Self.chatRateLimitPerSecond {
                return true
            }
            timestamps.append(now)
            self.chatMessageTimestamps[client.userID] = timestamps
            return false
        }()
        if exceeded {
            Logger.warning("Chat rate limit exceeded for user \(client.userID)")
            return
        }

        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        guard chat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        chat.withClients { toClient in
            let messageName = isSay ? "wired.chat.say" : "wired.chat.me"
            let reply = P7Message(withName: messageName, spec: toClient.socket.spec)
            reply.addParameter(field: "wired.chat.id", value: chatID)
            reply.addParameter(field: "wired.user.id", value: client.userID)
            reply.addParameter(field: messageName, value: string)
            App.serverController.send(message: reply, client: toClient)
        }
    }

    func startTypingCleanupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: typingCleanupQueue)
        timer.schedule(deadline: .now() + Self.typingCleanupInterval, repeating: Self.typingCleanupInterval)
        timer.setEventHandler { [weak self] in
            self?.expireTypingStates()
        }
        typingCleanupTimer = timer
        timer.resume()
    }

    func expireTypingStates() {
        let now = Date()
        let expiredKeys = typingStateLock.exclusivelyWrite { () -> [ChatTypingKey] in
            let expired = typingStates.compactMap { key, expiresAt in
                expiresAt <= now ? key : nil
            }

            for key in expired {
                typingStates.removeValue(forKey: key)
                typingPulseTimestamps.removeValue(forKey: key)
            }

            return expired
        }

        for key in expiredKeys {
            broadcastTyping(chatID: key.chatID, userID: key.userID, isTyping: false, excludingUserID: key.userID)
        }
    }

    func broadcastTyping(chatID: UInt32, userID: UInt32, isTyping: Bool, excludingUserID: UInt32? = nil) {
        guard let chat = self.chat(withID: chatID) else { return }

        chat.withClients { toClient in
            if let excludingUserID, toClient.userID == excludingUserID {
                return
            }

            let reply = P7Message(withName: "wired.chat.typing", spec: toClient.socket.spec)
            reply.addParameter(field: "wired.chat.id", value: chatID)
            reply.addParameter(field: "wired.user.id", value: userID)
            reply.addParameter(field: "wired.chat.typing", value: isTyping)
            App.serverController.send(message: reply, client: toClient)
        }
    }

    func updateTypingState(chatID: UInt32, userID: UInt32, isTyping: Bool) -> Bool {
        let key = ChatTypingKey(chatID: chatID, userID: userID)

        return typingStateLock.exclusivelyWrite {
            if isTyping {
                typingStates[key] = Date().addingTimeInterval(Self.typingTimeout)
                return true
            }

            let removed = typingStates.removeValue(forKey: key) != nil
            typingPulseTimestamps.removeValue(forKey: key)
            return removed
        }
    }

    func clearTypingState(forUserID userID: UInt32, inChatID chatID: UInt32, broadcastStop: Bool) {
        let removed = updateTypingState(chatID: chatID, userID: userID, isTyping: false)

        if removed && broadcastStop {
            broadcastTyping(chatID: chatID, userID: userID, isTyping: false)
        }
    }

    func clearTypingState(forChatID chatID: UInt32) {
        typingStateLock.exclusivelyWrite {
            typingStates = typingStates.filter { $0.key.chatID != chatID }
            typingPulseTimestamps = typingPulseTimestamps.filter { $0.key.chatID != chatID }
        }
    }

    func shouldRateLimitTypingPulse(chatID: UInt32, userID: UInt32, now: Date) -> Bool {
        let key = ChatTypingKey(chatID: chatID, userID: userID)

        return typingStateLock.exclusivelyWrite {
            let cutoff = now.addingTimeInterval(-1.0)
            var timestamps = typingPulseTimestamps[key] ?? []
            timestamps = timestamps.filter { $0 > cutoff }

            if timestamps.count >= Self.typingRateLimitPerSecond {
                typingPulseTimestamps[key] = timestamps
                return true
            }

            timestamps.append(now)
            typingPulseTimestamps[key] = timestamps
            return false
        }
    }
}

public class ChatsController: TableController {
    var chats: [UInt32: Chat] = [:]
    var publicChats: [Chat] = []
    var privateChats: [Chat] = []
    var chatsLock: Lock = Lock()
    var publicChat: Chat!

    private var lastChatID: UInt32 = 1

    // SECURITY (FINDING_C_006): Rate limiting for chat messages per client
    private static let chatRateLimitPerSecond: Int = 10
    private var chatMessageTimestamps: [UInt32: [Date]] = [:]
    private let chatRateLock = NSLock()
    private static let typingTimeout: TimeInterval = 6.0
    private static let typingCleanupInterval: TimeInterval = 1.0
    private static let typingRateLimitPerSecond: Int = 4
    private var typingStates: [ChatTypingKey: Date] = [:]
    private var typingPulseTimestamps: [ChatTypingKey: [Date]] = [:]
    private let typingStateLock = Lock()
    private let typingCleanupQueue = DispatchQueue(label: "wired3.chats.typing-cleanup")
    private var typingCleanupTimer: DispatchSourceTimer?

    public override init(databaseController: DatabaseController) {
        super.init(databaseController: databaseController)
        startTypingCleanupTimer()
    }

    deinit {
        typingCleanupTimer?.cancel()
        typingCleanupTimer = nil
    }

    public func getChats(message: P7Message, client: Client) {
        self.chatsLock.concurrentlyRead {
            for (chat) in self.publicChats {
                let response = P7Message(withName: "wired.chat.chat_list", spec: client.socket.spec)
                response.addParameter(field: "wired.chat.id", value: chat.chatID)
                response.addParameter(field: "wired.chat.name", value: chat.name)
                App.serverController.reply(client: client, reply: response, message: message)

            }
        }

        let response = P7Message(withName: "wired.chat.chat_list.done", spec: client.socket.spec)
        App.serverController.reply(client: client, reply: response, message: message)
    }

    public func createPublicChat(message: P7Message, client: Client) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        if !user.hasPrivilege(name: "wired.account.chat.create_public_chats") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)

            return
        }

        guard let name = message.string(forField: "wired.chat.name"),
              // SECURITY (FINDING_C_013): Reject empty/whitespace-only or oversized chat names
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 255 else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)

            return
        }

        do {
            let newChat = Chat(chatID: self.nextChatID(), name: name, client: client)

            try databaseController.dbQueue.write { db in try newChat.insert(db) }

            self.add(chat: newChat)

            let broadcast = P7Message(withName: "wired.chat.public_chat_created", spec: message.spec)
            broadcast.addParameter(field: "wired.chat.id", value: newChat.chatID)
            broadcast.addParameter(field: "wired.chat.name", value: newChat.name)
            App.clientsController.broadcast(message: broadcast)

            App.serverController.replyOK(client: client, message: message)
        } catch let error {
            Logger.error("Cannot create public chat")
            Logger.error("\(error)")

            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    public func deletePublicChat(message: P7Message, client: Client) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        if !user.hasPrivilege(name: "wired.account.chat.delete_public_chats") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)

            return
        }

        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let publicChat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        if chatID == 1 {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            Logger.error("Cannot delete public chat with ID '1'")
            return
        }

        // SECURITY (FINDING_F_014): Perform DB delete first, then broadcast/remove from memory
        do {
            try databaseController.dbQueue.write { db in try publicChat.delete(db) }
        } catch let error {
            Logger.error("Cannot delete public chat: \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        self.remove(chat: publicChat)

        let broadcast = P7Message(withName: "wired.chat.public_chat_deleted", spec: message.spec)
        broadcast.addParameter(field: "wired.chat.id", value: publicChat.chatID)
        App.clientsController.broadcast(message: broadcast)

        App.serverController.replyOK(client: client, message: message)
    }

    // SECURITY (FINDING_C_008): Maximum private chats per user
    private static let maxPrivateChatsPerUser: Int = 50

    public func createPrivateChat(message: P7Message, client: Client) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        if !user.hasPrivilege(name: "wired.account.chat.create_chats") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)

            return
        }

        // SECURITY (FINDING_C_008): Enforce per-user private chat limit
        let userPrivateChatCount = self.chatsLock.concurrentlyRead {
            self.privateChats.filter { $0.client(withID: client.userID) != nil || ($0 as? PrivateChat)?.isInvited(client: client) == true }.count
        }
        if userPrivateChatCount >= Self.maxPrivateChatsPerUser {
            Logger.warning("User \(client.userID) exceeded private chat limit (\(Self.maxPrivateChatsPerUser))")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let newPrivateChat = PrivateChat(chatID: self.nextChatID())
        // add invitation for initiator user
        newPrivateChat.addInvitation(client: client)

        self.add(chat: newPrivateChat)

        let reply = P7Message(withName: "wired.chat.chat_created", spec: message.spec)
        reply.addParameter(field: "wired.chat.id", value: newPrivateChat.chatID)
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    public func inviteUser(message: P7Message, client: Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let userID = message.uint32(forField: "wired.user.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let privateChat = self.chat(withID: chatID) as? PrivateChat else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        guard let peer = App.clientsController.user(withID: userID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        guard privateChat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        guard privateChat.client(withID: peer.userID) == nil else {
            App.serverController.replyError(client: client, error: "wired.error.already_on_chat", message: message)
            return
        }

        privateChat.addInvitation(client: peer)

        let reply = P7Message(withName: "wired.chat.invitation", spec: peer.socket.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        App.serverController.send(message: reply, client: peer)

        App.serverController.replyOK(client: client, message: message)
    }

    public func declineInvitation(message: P7Message, client: Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let userID = message.uint32(forField: "wired.user.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let privateChat = self.chat(withID: chatID) as? PrivateChat else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        guard App.clientsController.user(withID: userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        privateChat.removeInvitation(client: client)

        let reply = P7Message(withName: "wired.chat.user_decline_invitation", spec: client.socket.spec)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        reply.addParameter(field: "wired.user.id", value: client.userID)

        privateChat.withClients { toClient in
            App.serverController.send(message: reply, client: toClient)
        }

        App.serverController.replyOK(client: client, message: message)
    }

    public func userJoin(message: P7Message, client: Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        if chat.client(withID: client.userID) != nil {
            App.serverController.replyError(client: client, error: "wired.error.already_on_chat", message: message)
            return
        }

        if let privateChat = chat as? PrivateChat {
            if !privateChat.isInvited(client: client) {
                App.serverController.replyError(client: client, error: "wired.error.not_invited_to_chat", message: message)
                return
            }
        }

        chat.addClient(client)

        if let privateChat = chat as? PrivateChat {
            privateChat.removeInvitation(client: client)
        }

        // reply users
        chat.withClients { chatClient in
            let response = P7Message(withName: "wired.chat.user_list", spec: client.socket.spec)
            response.addParameter(field: "wired.chat.id", value: chatID)
            response.addParameter(field: "wired.user.id", value: chatClient.userID)
            response.addParameter(field: "wired.user.idle", value: chatClient.idle)
            response.addParameter(field: "wired.user.nick", value: chatClient.nick)
            response.addParameter(field: "wired.user.status", value: chatClient.status)
            response.addParameter(field: "wired.user.icon", value: chatClient.icon)
            response.addParameter(field: "wired.account.color", value: chatClient.accountColor)

            App.serverController.reply(client: client, reply: response, message: message)

        }

        let response = P7Message(withName: "wired.chat.user_list.done", spec: client.socket.spec)
        response.addParameter(field: "wired.chat.id", value: chatID)

        App.serverController.reply(client: client, reply: response, message: message)

        // reply topic
        let topicMessage = P7Message(withName: "wired.chat.topic", spec: client.socket.spec)
        topicMessage.addParameter(field: "wired.chat.id", value: chatID)
        topicMessage.addParameter(field: "wired.user.nick", value: chat.topicNick)
        topicMessage.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
        topicMessage.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)

        App.serverController.reply(client: client, reply: topicMessage, message: message)

        // broadcast to joined users
        chat.withClients { chatClient in
            if chatClient.userID != client.userID {
                let reply = P7Message(withName: "wired.chat.user_join", spec: client.socket.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.idle", value: chatClient.idle)
                reply.addParameter(field: "wired.user.id", value: client.userID)
                reply.addParameter(field: "wired.user.nick", value: client.nick)
                reply.addParameter(field: "wired.user.status", value: client.status)
                reply.addParameter(field: "wired.user.icon", value: client.icon)
                reply.addParameter(field: "wired.account.color", value: client.accountColor)

                App.serverController.send(message: reply, client: chatClient)
            }
        }
    }

    public func userLeave(client: Client) {
        removeUserFromAllChats(client: client, broadcastLeaves: true)
    }

    public func removeUserFromAllChats(client: Client, broadcastLeaves: Bool) {
        let snapshot = self.chatsLock.concurrentlyRead { self.chats }
        for (chatID, chat) in snapshot {
            if let c = chat.client(withID: client.userID) {
                removeUser(chatID: chatID, client: c, broadcastLeave: broadcastLeaves)
            }
        }
    }

    public func userLeave(message: P7Message, client: Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        if chat.client(withID: client.userID) == nil {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        removeUser(chatID: chatID, client: client, broadcastLeave: true)
        App.serverController.replyOK(client: client, message: message)
    }

    private func removeUser(chatID: UInt32, client: Client, broadcastLeave: Bool) {
        if let chat = self.chat(withID: chatID) {
            chat.removeClient(client.userID)
            clearTypingState(forUserID: client.userID, inChatID: chatID, broadcastStop: true)

            if broadcastLeave {
                chat.withClients { chatClient in
                    let reply = P7Message(withName: "wired.chat.user_leave", spec: client.socket.spec)
                    reply.addParameter(field: "wired.chat.id", value: chatID)
                    reply.addParameter(field: "wired.user.id", value: client.userID)
                    App.serverController.send(message: reply, client: chatClient)
                }
            }
        }
    }

    public func receiveChatSay(_ client: Client, _ message: P7Message) {
        guard let say = message.string(forField: "wired.chat.say"),
              // SECURITY (FINDING_C_002): Reject empty or whitespace-only chat messages
              !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        self.receiveChat(string: say, client, message, isSay: true)
    }

    public func receiveChatMe(_ client: Client, _ message: P7Message) {
        guard let say = message.string(forField: "wired.chat.me"),
              // SECURITY (FINDING_C_002): Reject empty or whitespace-only chat messages
              !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        self.receiveChat(string: say, client, message, isSay: false)
    }

    public func receiveChatTyping(client: Client, message: P7Message) {
        guard let chatID = message.uint32(forField: "wired.chat.id"),
              let isTyping = message.bool(forField: "wired.chat.typing") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        guard chat.client(withID: client.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        let now = Date()
        if shouldRateLimitTypingPulse(chatID: chatID, userID: client.userID, now: now) {
            App.serverController.replyOK(client: client, message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        if isTyping {
            _ = updateTypingState(chatID: chatID, userID: client.userID, isTyping: true)
            broadcastTyping(chatID: chatID, userID: client.userID, isTyping: true, excludingUserID: client.userID)
        } else if updateTypingState(chatID: chatID, userID: client.userID, isTyping: false) {
            broadcastTyping(chatID: chatID, userID: client.userID, isTyping: false, excludingUserID: client.userID)
        }
    }

    public func setTopic(message: P7Message, client: Client) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }
        if !user.hasPrivilege(name: "wired.account.chat.set_topic") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let topic = message.string(forField: "wired.chat.topic.topic") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        if chat.client(withID: client.userID) == nil {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        do {
            chat.topic = topic
            chat.topicNick = client.nick ?? ""
            chat.topicTime = Date()

            if !(chat is PrivateChat) {
                try databaseController.dbQueue.write { db in try chat.update(db) }
            }

            // reply okay msg
            App.serverController.replyOK(client: client, message: message)

            // broadcast topic update
            chat.withClients { toClient in
                let reply = P7Message(withName: "wired.chat.topic", spec: message.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.nick", value: client.nick)
                reply.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
                reply.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)

                App.serverController.send(message: reply, client: toClient)
            }

        } catch let error {
            Logger.error("Database error: \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)

            return
        }
    }

    public func chats(containingUserID userID: UInt32) -> [Chat] {
        self.chatsLock.concurrentlyRead {
            self.chats.values.filter { $0.client(withID: userID) != nil }
        }
    }

    public func kickUser(message: P7Message, client: Client) {
        guard let actor = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let chatID = message.uint32(forField: "wired.chat.id"),
              let targetUserID = message.uint32(forField: "wired.user.id"),
              let disconnectMessage = message.string(forField: "wired.user.disconnect_message") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let target = App.clientsController.user(withID: targetUserID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        guard let chat = self.chat(withID: chatID) else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }

        guard chat.client(withID: client.userID) != nil,
              chat.client(withID: target.userID) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }

        if chat === self.publicChat && !actor.hasPrivilege(name: "wired.account.chat.kick_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let broadcast = P7Message(withName: "wired.chat.user_kick", spec: client.socket.spec)
        broadcast.addParameter(field: "wired.chat.id", value: chatID)
        broadcast.addParameter(field: "wired.user.id", value: client.userID)
        broadcast.addParameter(field: "wired.user.disconnected_id", value: target.userID)
        broadcast.addParameter(field: "wired.user.disconnect_message", value: disconnectMessage)

        chat.withClients { chatClient in
            App.serverController.send(message: broadcast, client: chatClient)
        }

        chat.removeClient(target.userID)
        clearTypingState(forUserID: target.userID, inChatID: chatID, broadcastStop: true)
        App.serverController.replyOK(client: client, message: message)
    }

    /// Seed le chat public si la table est vide (remplace createTables)
    public func seedDefaultDataIfNeeded() {
        do {
            let count = try databaseController.dbQueue.read { db in try Chat.fetchCount(db) }
            guard count == 0 else { return }

            let chat = Chat(chatID: 1, name: "Public Chat", client: nil)
            try databaseController.dbQueue.write { db in try chat.insert(db) }
            self.add(chat: chat)
            self.publicChat = chat
        } catch {
            Logger.error("Cannot seed default public chat: \(error)")
        }
    }

    public func loadChats() {
        self.chatsLock.exclusivelyWrite {
            self.chats.removeAll()
            self.publicChats.removeAll()
            self.privateChats.removeAll()
            self.lastChatID = 1
        }
        self.publicChat = nil

        let chats = (try? databaseController.dbQueue.read { db in try Chat.fetchAll(db) }) ?? []
        var seenChatIDs: Set<UInt32> = []
        var highestChatID = max(chats.map(\.chatID).max() ?? 1, 1)

        for chat in chats {
            if seenChatIDs.contains(chat.chatID) {
                let originalChatID = chat.chatID

                while highestChatID < UInt32.max {
                    highestChatID += 1

                    if !seenChatIDs.contains(highestChatID) {
                        chat.chatID = highestChatID
                        break
                    }
                }

                Logger.error("Duplicate persisted chatID detected, reassigning chat '\(chat.name ?? "Private Chat")' from \(originalChatID) to \(chat.chatID)")

                do {
                    try databaseController.dbQueue.write { db in
                        try chat.update(db)
                    }
                } catch {
                    Logger.error("Cannot repair duplicate chatID \(originalChatID): \(error)")
                }
            }

            seenChatIDs.insert(chat.chatID)
            self.add(chat: chat)
            if chat.chatID == 1 { self.publicChat = chat }
            self.lastChatID = max(self.lastChatID, chat.chatID)
        }

    }
}
