//
//  Chat.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import Fluent
import FluentSQLiteDriver

public class Chat: Model {
    public static var schema: String = "chats"
    
    @ID(key: .id)
    public var id:UUID?
    
    @Field(key: "chatID")
    public var chatID:UInt32!
    
    @Field(key: "name")
    public var name:String?
    
    @Field(key: "topic")
    public var topic:String
    
    @Field(key: "topicNick")
    public var topicNick:String
    
    @Field(key: "topicTime")
    public var topicTime:Date
    
    @Field(key: "creationNick")
    public var creationNick:String
    
    @Field(key: "creationTime")
    public var creationTime:Date
    
    public var users:[UInt32:User] = [:]
    
    public required init() { }
    
    public init(chatID:UInt32) {
        self.chatID = chatID
        self.creationTime   = Date()
        self.creationNick   = ""
        self.topic          = ""
        self.topicNick      = ""
        self.topicTime      = Date()
    }
    
    public init(chatID:UInt32, name:String, user:User?) {
        self.chatID         = chatID
        self.name           = name
        self.creationTime   = Date()
        self.creationNick   = ""
        self.topic          = ""
        self.topicNick      = ""
        self.topicTime      = Date()
        
        if let nick = user?.nick {
            self.creationNick = nick
        }
    }
}



public class PrivateChat : Chat {
    private var invitedUsers:[User] = []
    
    public func addInvitation(user:User) {
        self.invitedUsers.append(user)
    }
    
    
    public func removeInvitation(user:User) {
        self.invitedUsers.removeAll { (u) -> Bool in
            u.userID == user.userID
        }
    }
    
    
    public func isInvited(user:User) -> Bool {
        for u in self.invitedUsers {
            if u.userID == user.userID {
                return true
            }
        }
        
        return false
    }
}
