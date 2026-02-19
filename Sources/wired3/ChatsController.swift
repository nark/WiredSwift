//
//  ChatsController.swift
//  wired3
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

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
    
    
    private func nextChatID() -> UInt32 {
        lastChatID += 1
        return lastChatID
    }
    
    
    private func receiveChat(string:String, _ client:Client, _ message:P7Message, isSay:Bool) {
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
        if !client.user!.hasPrivilege(name: "wired.account.chat.create_public_chats") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                
            return
        }
        
        guard let name = message.string(forField: "wired.chat.name") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
                
            return
        }
        
        do {
            let newChat = Chat(chatID: self.nextChatID(), name: name, client: client)
            
            try newChat.create(on: databaseController.pool).wait()
            
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
        if !client.user!.hasPrivilege(name: "wired.account.chat.delete_public_chats") {
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
              
        do {
            let reply = P7Message(withName: "wired.chat.public_chat_deleted", spec: message.spec)
            
            reply.addParameter(field: "wired.chat.id", value: publicChat.chatID)
            
            App.clientsController.broadcast(message: reply)
            
            self.remove(chat: publicChat)
            
            try publicChat.delete(on: databaseController.pool).wait()

        } catch let error {
            Logger.error("Cannot delete public chat: \(error)")
            
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }
    
    
    public func createPrivateChat(message:P7Message, client:Client) {
        if !client.user!.hasPrivilege(name: "wired.account.chat.create_chats") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
        
            return
        }
                
        let newPrivateChat = PrivateChat(chatID: self.nextChatID())
        // add invitation for initiator user
        newPrivateChat.addInvitation(client: client)
        
        self.add(chat: newPrivateChat)
        
        let reply = P7Message(withName: "wired.chat.chat_created", spec: message.spec)
        reply.addParameter(field: "wired.chat.id", value: newPrivateChat.chatID!)
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
        for (chatID, chat) in self.chats {
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
        guard let say = message.string(forField: "wired.chat.say") else {
            return
        }
        
        self.receiveChat(string: say, client, message, isSay: true)
    }
    
    
    public func receiveChatMe(_ client:Client, _ message:P7Message) {
        guard let say = message.string(forField: "wired.chat.me") else {
            return
        }
        
        self.receiveChat(string: say, client, message, isSay: false)
    }
    
    
    
    public func setTopic(message: P7Message, client:Client) {
        if !client.user!.hasPrivilege(name: "wired.account.chat.set_topic") {
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
            chat.topicNick = client.nick!
            chat.topicTime = Date()
            
            try chat.update(on: self.databaseController.pool).wait()
            
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
    
    
    public override func createTables() {
        do {
            try self.databaseController.pool
                    .schema("chats")
                    .id()
                    .field("chatID", .uint32, .required)
                    .field("name", .string, .required)
                    .field("topic", .string, .required)
                    .field("topicNick", .string, .required)
                    .field("topicTime", .datetime, .required)
                    .field("creationNick", .string, .required)
                    .field("creationTime", .datetime, .required)
                    .create().wait()
            
            // init main public chat
            self.publicChat = Chat(chatID: UInt32(1), name: "Public Chat", client: nil)
            
            try self.publicChat.create(on: self.databaseController.pool).wait()
            
            self.add(chat: self.publicChat)
            
        } catch let error {
            Logger.error("Cannot create tables")
            Logger.error("\(error)")
        }
    }
    
    
    
    public func loadChats() {
        do {
            let chats = try Chat.query(on: databaseController.pool).all().wait()

            for chat in chats {
                self.add(chat: chat)

                // ref the public chat
                if chat.chatID == 1 {
                    self.publicChat = chat
                }

                lastChatID = chat.chatID
            }
        } catch {  }
    }
}
