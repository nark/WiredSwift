//
//  ChatsController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift
import GRDB

private extension ChatsController {
    // MARK: - Privates
    
    private func add(chat:Chat) {
        self.chatsLock.exclusivelyWrite {
            self.chats[chat.chatID] = chat
            
            if let privateChat = chat as? PrivateChat {
                self.privateChats.append(privateChat)
            } else {
                self.publicChats.append(chat)
            }
        }
    }
    
    
    
    private func remove(chat:Chat) {
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
    
    
    
    private func chat(withID chatID:UInt32) -> Chat? {
        return self.chatsLock.concurrentlyRead {
            self.chats[chatID]
        }
    }
    
    
    // SECURITY (FINDING_C_009): Protect lastChatID increment with lock to prevent duplicate IDs
    private func nextChatID() -> UInt32 {
        var newID: UInt32 = 0
        self.chatsLock.exclusivelyWrite {
            self.lastChatID += 1
            newID = self.lastChatID
        }
        return newID
    }
    
    
    private func receiveChat(string:String, _ client:Client, _ message:P7Message, isSay:Bool) {
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

        chat.withClients { toClient in
            let messageName = isSay ? "wired.chat.say" : "wired.chat.me"
            let reply = P7Message(withName: messageName, spec: toClient.socket.spec)
            reply.addParameter(field: "wired.chat.id", value: chatID)
            reply.addParameter(field: "wired.user.id", value: client.userID)
            reply.addParameter(field: messageName, value: string)
            App.serverController.reply(client: toClient, reply: reply, message: message)
        }
    }
}




public class ChatsController : TableController {
    var chats:[UInt32:Chat] = [:]
    var publicChats:[Chat] = []
    var privateChats:[Chat] = []
    var chatsLock:Lock = Lock()
    var publicChat:Chat!

    private var lastChatID:UInt32 = 1

    // SECURITY (FINDING_C_006): Rate limiting for chat messages per client
    private static let chatRateLimitPerSecond: Int = 10
    private var chatMessageTimestamps: [UInt32: [Date]] = [:]
    private let chatRateLock = NSLock()
    
    public override init(databaseController: DatabaseController) {
        super.init(databaseController: databaseController)
    }

    
    public func getChats(message:P7Message, client:Client) {
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
    
    
    public func createPublicChat(message:P7Message, client:Client) {
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
            
            let reply = P7Message(withName: "wired.chat.public_chat_created", spec: message.spec)
            reply.addParameter(field: "wired.chat.id", value: newChat.chatID)
            reply.addParameter(field: "wired.chat.name", value: newChat.name)
            
            App.clientsController.broadcast(message: reply)
        } catch let error {
            Logger.error("Cannot create public chat")
            Logger.error("\(error)")
            
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }
    
    
    
    public func deletePublicChat(message:P7Message, client:Client) {
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

        let reply = P7Message(withName: "wired.chat.public_chat_deleted", spec: message.spec)
        reply.addParameter(field: "wired.chat.id", value: publicChat.chatID)
        App.clientsController.broadcast(message: reply)
    }
    
    
    // SECURITY (FINDING_C_008): Maximum private chats per user
    private static let maxPrivateChatsPerUser: Int = 50

    public func createPrivateChat(message:P7Message, client:Client) {
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
    
    
    public func inviteUser(message:P7Message, client:Client) {
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
        
        let reply = P7Message(withName: "wired.chat.invitation", spec: message.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        App.serverController.reply(client: peer, reply: reply, message: message)
        
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

        guard let inviter = App.clientsController.user(withID: userID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        privateChat.removeInvitation(client: client)

        let reply = P7Message(withName: "wired.chat.user_decline_invitation", spec: message.spec)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        reply.addParameter(field: "wired.user.id", value: client.userID)

        privateChat.withClients { toClient in
            App.serverController.reply(client: toClient, reply: reply, message: message)
        }

        App.serverController.reply(client: inviter, reply: reply, message: message)
        App.serverController.replyOK(client: client, message: message)
    }
    
    
    public func userJoin(message: P7Message, client:Client) {
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
                
                App.serverController.reply(client: chatClient, reply: reply, message: message)
            }
        }
    }
    
    
    public func userLeave(client:Client) {
        let snapshot = self.chatsLock.concurrentlyRead { self.chats }
        for (chatID, chat) in snapshot {
            if let c = chat.client(withID: client.userID) {
                userLeave(chatID: chatID, client: c)
            }
        }
    }
    
    
    public func userLeave(message:P7Message, client:Client) {
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
    
        userLeave(chatID: chatID, client: client)
        App.serverController.replyOK(client: client, message: message)
    }
    
    
    private func userLeave(chatID:UInt32, client:Client) {
        if let chat = self.chat(withID: chatID) {
            chat.removeClient(client.userID)
            
            chat.withClients { chatClient in
                let reply = P7Message(withName: "wired.chat.user_leave", spec: client.socket.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.id", value: client.userID)
                App.serverController.send(message: reply, client: chatClient)
            }
        }
    }
    
    public func receiveChatSay(_ client:Client, _ message:P7Message) {
        guard let say = message.string(forField: "wired.chat.say"),
              // SECURITY (FINDING_C_002): Reject empty or whitespace-only chat messages
              !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        self.receiveChat(string: say, client, message, isSay: true)
    }


    public func receiveChatMe(_ client:Client, _ message:P7Message) {
        guard let say = message.string(forField: "wired.chat.me"),
              // SECURITY (FINDING_C_002): Reject empty or whitespace-only chat messages
              !say.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        self.receiveChat(string: say, client, message, isSay: false)
    }
    
    
    
    public func setTopic(message: P7Message, client:Client) {
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

            try databaseController.dbQueue.write { db in try chat.update(db) }
            
            // reply okay msg
            App.serverController.replyOK(client: client, message: message)
            
            // broadcast topic update
            chat.withClients { toClient in
                let reply = P7Message(withName: "wired.chat.topic", spec: message.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.nick", value: client.nick)
                reply.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
                reply.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)
                
                App.serverController.reply(client: toClient, reply: reply, message: message)
            }
            
        } catch let error {
            Logger.error("Database error: \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            
            return
        }
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
        let chats = (try? databaseController.dbQueue.read { db in try Chat.fetchAll(db) }) ?? []
        for chat in chats {
            self.add(chat: chat)
            if chat.chatID == 1 { self.publicChat = chat }
            lastChatID = chat.chatID
        }
    }
}
