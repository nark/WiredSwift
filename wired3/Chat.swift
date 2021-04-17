//
//  Chat.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import GRDB

public class Chat: Record {
    public var id:Int64?
    public var chatID:UInt32!
    public var name:String = ""
    public var topic:String = ""
    public var topicNick:String = ""
    public var topicTime:Date = Date()
    public var creationNick:String = ""
    public var creationTime:Date = Date()
    
    public var users:[UInt32:User] = [:]
    
    public init(chatID:UInt32) {
        self.chatID = chatID
        self.topic = ""
        self.topicNick = ""
        self.topicTime = Date()
        
        super.init()
    }
    
    public init(chatID:UInt32, name:String, user:User?) {
        self.chatID         = chatID
        self.name           = name
        self.creationTime   = Date()
        self.topic          = ""
        self.topicNick      = ""
        self.topicTime      = Date()
        
        if let nick = user?.nick {
            self.creationNick = nick
        }
        
        super.init()
    }
    
    /// Creates a record from a database row
    public required init(row: Row) {
        self.id             = row[Columns.id]
        self.chatID         = row[Columns.chat_id]
        self.name           = row[Columns.name]
        self.topic          = row[Columns.topic]
        self.topicNick      = row[Columns.topic_by]
        self.topicTime      = row[Columns.topic_at]
        self.creationNick   = row[Columns.created_by]
        self.creationTime   = row[Columns.created_at]
        
        super.init(row: row)
    }
    
    // MARK: - Record
    /// The table name
    public override class var databaseTableName: String { "chats" }

    /// The table columns
    enum Columns: String, ColumnExpression {
        case id, chat_id, name, topic, topic_by, topic_at, created_by, created_at
    }
    

    /// The values persisted in the database
    public override func encode(to container: inout PersistenceContainer) {
        container[Columns.id]           = id
        container[Columns.chat_id]      = chatID
        container[Columns.name]         = name
        container[Columns.topic]        = topic
        container[Columns.topic_by]     = topicNick
        container[Columns.topic_at]     = topicTime
        container[Columns.created_by]   = creationNick
        container[Columns.created_at]   = creationTime
    }

    // Update auto-incremented id upon successful insertion
    public override func didInsert(with rowID: Int64, for column: String?) {
        id = rowID
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
