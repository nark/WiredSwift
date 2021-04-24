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
        self.chats[chat.chatID] = chat
        
        if let privateChat = chat as? PrivateChat {
            self.privateChats.append(privateChat)
        } else {
            self.publicChats.append(chat)
        }
    }
    
    
    private func nextChatID() -> UInt32 {
        lastChatID += 1
        return lastChatID
    }
    
    
    private func receiveChat(string:String, _ client:Client, _ message:P7Message, isSay:Bool) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            return
        }
                
        if let chat = chats[chatID] {
            for (_, toClient) in chat.clients {
                let messageName = isSay ? "wired.chat.say" : "wired.chat.me"
                let reply = P7Message(withName: messageName, spec: toClient.socket.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.id", value: client.userID)
                reply.addParameter(field: messageName, value: string)
                App.serverController.reply(client: toClient, reply: reply, message: message)
            }
        } else {
            let reply = P7Message(withName: "wired.error", spec: client.socket.spec)
            reply.addParameter(field: "wired.error.string", value: "Chat not found")
            reply.addParameter(field: "wired.error", value: 8)
            App.serverController.reply(client: client, reply: reply, message: message)
        }
    }
}




public class ChatsController : TableController {
    var chats:[UInt32:Chat] = [:]
    var publicChats:[Chat] = []
    var privateChats:[Chat] = []
    var publicChat:Chat!
    
    private var lastChatID:UInt32 = 1
    
    public override init(databaseController: DatabaseController) {
        super.init(databaseController: databaseController)
    }

    
    public func getChats(message:P7Message, client:Client) {
        for (chat) in self.publicChats {
            let response = P7Message(withName: "wired.chat.chat_list", spec: client.socket.spec)
            response.addParameter(field: "wired.chat.id", value: chat.chatID)
            response.addParameter(field: "wired.chat.name", value: chat.name)
            App.serverController.reply(client: client, reply: response, message: message)
            
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
        
        guard let privateChat = self.chats[chatID] as? PrivateChat else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
                
        guard let peer = App.clientsController.connectedClients[userID] else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }
        
        // TODO: make it work
//        guard privateChat.users[user.userID] == nil else {
//            App.serverController.replyError(user: user, error: "wired.error.not_on_chat", message: message)
//            return
//        }
//
//        print("wired.error.not_on_chat OK")
//
//        guard privateChat.users[peer.userID] != nil else {
//            App.serverController.replyError(user: user, error: "wired.error.already_on_chat", message: message)
//            return
//        }
//
//        print("wired.error.already_on_chat OK")
        
        privateChat.addInvitation(client: peer)
        
        let reply = P7Message(withName: "wired.chat.invitation", spec: message.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        App.serverController.reply(client: peer, reply: reply, message: message)
        
        App.serverController.replyOK(client: client, message: message)
    }
    
    
    public func userJoin(message: P7Message, client:Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let chat = chats[chatID] else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.clients[client.userID] != nil {
            App.serverController.replyError(client: client, error: "wired.error.already_on_chat", message: message)
            return
        }
        
        if let privateChat = chat as? PrivateChat {
            if !privateChat.isInvited(client: client) {
                App.serverController.replyError(client: client, error: "wired.error.not_invited_to_chat", message: message)
                return
            }
        }
        
        chat.clients[client.userID] = client
        
        if let privateChat = chat as? PrivateChat {
            privateChat.removeInvitation(client: client)
        }
        
        // reply users
        for (userID, chatClient) in chat.clients {
            let response = P7Message(withName: "wired.chat.user_list", spec: client.socket.spec)
            response.addParameter(field: "wired.chat.id", value: chatID)
            response.addParameter(field: "wired.user.id", value: userID)
            response.addParameter(field: "wired.user.idle", value: false)
            response.addParameter(field: "wired.user.nick", value: chatClient.nick)
            response.addParameter(field: "wired.user.status", value: chatClient.status)
            response.addParameter(field: "wired.user.icon", value: chatClient.icon)
            response.addParameter(field: "wired.account.color", value: UInt32(0))
            
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
        for (userID, chatClient) in chat.clients {
            if userID != client.userID {
                let reply = P7Message(withName: "wired.chat.user_join", spec: client.socket.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.idle", value: false)
                reply.addParameter(field: "wired.user.id", value: client.userID)
                reply.addParameter(field: "wired.user.nick", value: client.nick)
                reply.addParameter(field: "wired.user.status", value: client.status)
                reply.addParameter(field: "wired.user.icon", value: client.icon)
                reply.addParameter(field: "wired.account.color", value: UInt32(0))
                
                App.serverController.reply(client: chatClient, reply: reply, message: message)
            }
        }
    }
    
    
    public func userLeave(client:Client) {
        for (chatID, chat) in chats {
            for (userID, _) in chat.clients {
                if userID == client.userID {
                    userLeave(chatID: chatID, client: client)
                }
            }
        }
    }
    
    public func userLeave(message:P7Message, client:Client) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let chat = chats[chatID] else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.clients[client.userID] == nil {
            App.serverController.replyError(client: client, error: "wired.error.not_on_chat", message: message)
            return
        }
        
        userLeave(chatID: chatID, client: client)
    }
    
    
    private func userLeave(chatID:UInt32, client:Client) {
        if let chat = chats[chatID] {
            chat.clients[client.userID] = nil
            
            for (_, chat_user) in chat.clients {
                let reply = P7Message(withName: "wired.chat.user_leave", spec: client.socket.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.id", value: client.userID)
                App.serverController.send(message: reply, client: chat_user)
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
        
        guard let chat = chats[chatID] else {
            App.serverController.replyError(client: client, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.clients[client.userID] == nil {
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
            for (_, toClient) in chat.clients {
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
