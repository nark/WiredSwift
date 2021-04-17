//
//  ChatsController.swift
//  Server
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
    
    
    private func receiveChat(string:String, _ user:User, _ message:P7Message, isSay:Bool) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            return
        }
                
        if let chat = chats[chatID] {
            for (_, toUser) in chat.users {
                let messageName = isSay ? "wired.chat.say" : "wired.chat.me"
                let reply = P7Message(withName: messageName, spec: toUser.socket!.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.id", value: user.userID)
                reply.addParameter(field: messageName, value: string)
                _ = toUser.socket?.write(reply)
            }
        } else {
            let reply = P7Message(withName: "wired.error", spec: user.socket!.spec)
            reply.addParameter(field: "wired.error.string", value: "Chat not found")
            reply.addParameter(field: "wired.error", value: 8)
            _ = user.socket?.write(reply)
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

    
    public func getChats(user:User) {
        for (chat) in self.publicChats {
            let response = P7Message(withName: "wired.chat.chat_list", spec: user.socket!.spec)
            response.addParameter(field: "wired.chat.id", value: chat.chatID)
            response.addParameter(field: "wired.chat.name", value: chat.name)
            _ = user.socket?.write(response)
        }
            
        let response = P7Message(withName: "wired.chat.chat_list.done", spec: user.socket!.spec)
        _ = user.socket?.write(response)
    }
    
    
    public func createPublicChat(message:P7Message, user:User) {
        if !user.hasPrivilege(name: "wired.account.chat.create_public_chats") {
            App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
                
            return
        }
        
        guard let name = message.string(forField: "wired.chat.name") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
                
            return
        }
        
        do {
            try databaseController.pool.write { db in
                let newChat = Chat(chatID: self.nextChatID(), name: name, user: user)
                
                try newChat.insert(db)
                
                self.add(chat: newChat)
                
                let reply = P7Message(withName: "wired.chat.public_chat_created", spec: message.spec)
                reply.addParameter(field: "wired.chat.id", value: newChat.chatID)
                reply.addParameter(field: "wired.chat.name", value: newChat.name)
                
                App.usersController.broadcast(message: reply)
            }
        } catch let error { 
            Logger.error("Cannot create public chat")
            Logger.error("\(error)")
            
            App.usersController.replyError(user: user, error: "wired.error.internal_error", message: message)
        }
    }
    
    
    public func createPrivateChat(message:P7Message, user:User) {
        if !user.hasPrivilege(name: "wired.account.chat.create_chats") {
            App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
        
            return
        }
                
        let newPrivateChat = PrivateChat(chatID: self.nextChatID())
        // add invitation for initiator user
        newPrivateChat.addInvitation(user: user)
        
        self.add(chat: newPrivateChat)
        
        let reply = P7Message(withName: "wired.chat.chat_created", spec: message.spec)
        reply.addParameter(field: "wired.chat.id", value: newPrivateChat.chatID!)
        App.usersController.reply(user: user, reply: reply, message: message)
    }
    
    
    public func inviteUser(message:P7Message, user:User) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let userID = message.uint32(forField: "wired.user.id") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let privateChat = self.chats[chatID] as? PrivateChat else {
            App.usersController.replyError(user: user, error: "wired.error.chat_not_found", message: message)
            return
        }
                
        guard let peer = App.usersController.connectedUsers[userID] else {
            App.usersController.replyError(user: user, error: "wired.error.user_not_found", message: message)
            return
        }
        
        // TODO: make it work
//        guard privateChat.users[user.userID] == nil else {
//            App.usersController.replyError(user: user, error: "wired.error.not_on_chat", message: message)
//            return
//        }
//
//        print("wired.error.not_on_chat OK")
//
//        guard privateChat.users[peer.userID] != nil else {
//            App.usersController.replyError(user: user, error: "wired.error.already_on_chat", message: message)
//            return
//        }
//
//        print("wired.error.already_on_chat OK")
        
        privateChat.addInvitation(user: peer)
        
        let reply = P7Message(withName: "wired.chat.invitation", spec: message.spec)
        reply.addParameter(field: "wired.user.id", value: user.userID)
        reply.addParameter(field: "wired.chat.id", value: chatID)
        _ = peer.socket?.write(reply)
        
        App.usersController.replyOK(user: user, message: message)
    }
    
    
    public func userJoin(message: P7Message, user:User) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let chat = chats[chatID] else {
            App.usersController.replyError(user: user, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.users[user.userID] != nil {
            App.usersController.replyError(user: user, error: "wired.error.already_on_chat", message: message)
            return
        }
        
        if let privateChat = chat as? PrivateChat {
            if !privateChat.isInvited(user: user) {
                App.usersController.replyError(user: user, error: "wired.error.not_invited_to_chat", message: message)
                return
            }
        }
        
        chat.users[user.userID] = user
        
        if let privateChat = chat as? PrivateChat {
            privateChat.removeInvitation(user: user)
        }
        
        // reply users
        for (userID, chat_user) in chat.users {
            let response = P7Message(withName: "wired.chat.user_list", spec: user.socket!.spec)
            response.addParameter(field: "wired.chat.id", value: chatID)
            response.addParameter(field: "wired.user.id", value: userID)
            response.addParameter(field: "wired.user.idle", value: false)
            response.addParameter(field: "wired.user.nick", value: chat_user.nick)
            response.addParameter(field: "wired.user.status", value: chat_user.status)
            response.addParameter(field: "wired.user.icon", value: chat_user.icon)
            response.addParameter(field: "wired.account.color", value: UInt32(0))
            
            _ = user.socket?.write(response)
        }
        
        let response = P7Message(withName: "wired.chat.user_list.done", spec: user.socket!.spec)
        response.addParameter(field: "wired.chat.id", value: chatID)
        
        _ = user.socket?.write(response)
        
        // reply topic
        let topicMessage = P7Message(withName: "wired.chat.topic", spec: user.socket!.spec)
        topicMessage.addParameter(field: "wired.chat.id", value: chatID)
        topicMessage.addParameter(field: "wired.user.nick", value: chat.topicNick)
        topicMessage.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
        topicMessage.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)
        
        _ = user.socket?.write(topicMessage)
        
        // broadcast to joined users
        for (userID, chat_user) in chat.users {
            if userID != user.userID {
                let reply = P7Message(withName: "wired.chat.user_join", spec: user.socket!.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.idle", value: false)
                reply.addParameter(field: "wired.user.id", value: user.userID)
                reply.addParameter(field: "wired.user.nick", value: user.nick)
                reply.addParameter(field: "wired.user.status", value: user.status)
                reply.addParameter(field: "wired.user.icon", value: user.icon)
                reply.addParameter(field: "wired.account.color", value: UInt32(0))
                
                _ = chat_user.socket?.write(reply)
            }
        }
    }
    
    
    public func userLeave(user:User) {
        for (chatID, chat) in chats {
            for (userID, _) in chat.users {
                if userID == user.userID {
                    userLeave(chatID: chatID, user: user)
                }
            }
        }
    }
    
    public func userLeave(message:P7Message, user:User) {
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let chat = chats[chatID] else {
            App.usersController.replyError(user: user, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.users[user.userID] == nil {
            App.usersController.replyError(user: user, error: "wired.error.not_on_chat", message: message)
            return
        }
        
        userLeave(chatID: chatID, user: user)
    }
    
    
    private func userLeave(chatID:UInt32, user:User) {
        if let chat = chats[chatID] {
            chat.users[user.userID] = nil
            
            for (_, chat_user) in chat.users {
                let reply = P7Message(withName: "wired.chat.user_leave", spec: user.socket!.spec)
                reply.addParameter(field: "wired.chat.id", value: chatID)
                reply.addParameter(field: "wired.user.id", value: user.userID)
                _ = chat_user.socket?.write(reply)
            }
        }
    }
    
    public func receiveChatSay(_ user:User, _ message:P7Message) {
        guard let say = message.string(forField: "wired.chat.say") else {
            return
        }
        
        self.receiveChat(string: say, user, message, isSay: true)
    }
    
    
    public func receiveChatMe(_ user:User, _ message:P7Message) {
        guard let say = message.string(forField: "wired.chat.me") else {
            return
        }
        
        self.receiveChat(string: say, user, message, isSay: false)
    }
    
    
    
    public func setTopic(message: P7Message, user:User) {
        if !user.hasPrivilege(name: "wired.account.chat.set_topic") {
            App.usersController.replyError(user: user, error: "wired.error.permission_denied", message: message)
            return
        }
        
        guard let chatID = message.uint32(forField: "wired.chat.id") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let topic = message.string(forField: "wired.chat.topic.topic") else {
            App.usersController.replyError(user: user, error: "wired.error.invalid_message", message: message)
            return
        }
        
        guard let chat = chats[chatID] else {
            App.usersController.replyError(user: user, error: "wired.error.chat_not_found", message: message)
            return
        }
        
        if chat.users[user.userID] == nil {
            App.usersController.replyError(user: user, error: "wired.error.not_on_chat", message: message)
            return
        }
        
        do {
            try self.databaseController.pool.write { db in
                chat.topic = topic
                chat.topicNick = user.nick!
                chat.topicTime = Date()
                
                try chat.update(db)
                
                // reply okay msg
                App.usersController.replyOK(user: user, message: message)
                
                // broadcast topic update
                for (_, toUser) in chat.users {
                    let reply = P7Message(withName: "wired.chat.topic", spec: toUser.socket!.spec)
                    reply.addParameter(field: "wired.chat.id", value: chatID)
                    reply.addParameter(field: "wired.user.nick", value: user.nick)
                    reply.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
                    reply.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)
                    
                    _ = toUser.socket?.write(reply)
                }
            }
            
        } catch let error {
            Logger.error("Database error: \(error)")
            App.usersController.replyError(user: user, error: "wired.error.internal_error", message: message)
            
            return
        }
    }
    
    
    public override func createTables() {
        do {
            try self.databaseController.pool.write { db in
                // create table
                try db.create(table: "chats") { t in
                    t.autoIncrementedPrimaryKey("id")
                    t.column("chat_id",     .integer).notNull()
                    t.column("name",        .text).notNull().unique()
                    t.column("topic",       .text).notNull()
                    t.column("topic_by",    .text).notNull()
                    t.column("topic_at",    .datetime).notNull()
                    t.column("created_by",  .text).notNull()
                    t.column("created_at",  .datetime).notNull()
                }
                
                // init main public chat
                self.publicChat = Chat(chatID: UInt32(1), name: "Public Chat", user: nil)
                
                try self.publicChat.insert(db)
                
                self.add(chat: self.publicChat)
            }
            
        } catch let error {
            Logger.error("Cannot create tables")
            Logger.error("\(error)")
        }
    }
    
    
    
    public func loadChats() {
        do {
            try databaseController.pool.read { db in
                let chats = try Chat.fetchAll(db)
                
                for chat in chats {
                    self.add(chat: chat)
                    
                    // ref the public chat
                    if chat.chatID == 1 {
                        self.publicChat = chat
                    }
                    
                    lastChatID = chat.chatID
                }
            }
        } catch {  }
    }
}
