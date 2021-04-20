//
//  Chat.swift
//  wired3
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
    
    public var clients:[UInt32:Client] = [:]
    
    public required init() { }
    
    public init(chatID:UInt32) {
        self.chatID = chatID
        self.creationTime   = Date()
        self.creationNick   = ""
        self.topic          = ""
        self.topicNick      = ""
        self.topicTime      = Date()
    }
    
    public init(chatID:UInt32, name:String, client:Client?) {
        self.chatID         = chatID
        self.name           = name
        self.creationTime   = Date()
        self.creationNick   = ""
        self.topic          = ""
        self.topicNick      = ""
        self.topicTime      = Date()
        
        if let nick = client?.nick {
            self.creationNick = nick
        }
    }
}



public class PrivateChat : Chat {
    private var invitedClients:[Client] = []
    
    public func addInvitation(client:Client) {
        self.invitedClients.append(client)
    }
    
    
    public func removeInvitation(client:Client) {
        self.invitedClients.removeAll { (c) -> Bool in
            c.userID == client.userID
        }
    }
    
    
    public func isInvited(client:Client) -> Bool {
        for c in self.invitedClients {
            if c.userID == client.userID {
                return true
            }
        }
        
        return false
    }
}
