//
//  Chat.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation

public class Chat {
    public var chatID:UInt32!
    public var users:[UInt32:User] = [:]
    
    public var topic:String = ""
    public var topicNick:String = ""
    public var topicTime:Date = Date()
    
    public init(withID id:UInt32) {
        self.chatID = id
        self.topic = "Empty topic"
        self.topicNick = "Nobody"
    }
}
