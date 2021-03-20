//
//  ChatsController.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

public class ChatsController {
    var chats:[UInt32:Chat] = [:]
    var publicChat:Chat!
    
    
    public init() {
        self.publicChat = Chat(withID: 1)
        self.chats[1] = self.publicChat
    }
    
    
    public func userJoin(chatID:UInt32, user:User, transactionID:UInt32? = nil) {
        if let chat = chats[chatID] {
            chat.users[user.userID] = user
            
            for (userID, user) in chat.users {
                let response = P7Message(withName: "wired.chat.user_list", spec: user.socket!.spec)
                response.addParameter(field: "wired.chat.id", value: chatID)
                response.addParameter(field: "wired.user.id", value: userID)
                response.addParameter(field: "wired.user.idle", value: false)
                response.addParameter(field: "wired.user.nick", value: user.nick)
                response.addParameter(field: "wired.user.status", value: user.status)
                response.addParameter(field: "wired.user.icon", value: user.icon)
                
                if let t = transactionID {
                    response.addParameter(field: "wired.transaction", value: t)
                }
                
                _ = user.socket?.write(response)
            }
            
            let response = P7Message(withName: "wired.chat.user_list.done", spec: user.socket!.spec)
            response.addParameter(field: "wired.chat.id", value: chatID)
            
            if let t = transactionID {
                response.addParameter(field: "wired.transaction", value: t)
            }
            
            _ = user.socket?.write(response)
            
            let topicMessage = P7Message(withName: "wired.chat.topic", spec: user.socket!.spec)
            topicMessage.addParameter(field: "wired.chat.id", value: chatID)
            topicMessage.addParameter(field: "wired.user.nick", value: chat.topicNick)
            topicMessage.addParameter(field: "wired.chat.topic.topic", value: chat.topic)
            topicMessage.addParameter(field: "wired.chat.topic.time", value: chat.topicTime)
            
            _ = user.socket?.write(topicMessage)
        }
    }
    
    
    public func userLeave(chatID:UInt32, user:User) {
        if let chat = chats[chatID] {
            chat.users[user.userID] = nil
        }
    }
}
