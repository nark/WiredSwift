//
//  ConversationsController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class ConversationsController {
    public static let shared = ConversationsController()
    
    private var _conversations: [Conversation] = []
    
    
    private init() {
        self.reload()
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(userleftPublicChat),
        name: NSNotification.Name("UserLeftPublicChat"), object: nil)
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(userJoinedPublicChat),
        name: NSNotification.Name("UserJoinedPublicChat"), object: nil)
    }
    
    
    @objc func userJoinedPublicChat(_ n:Notification) {
        self.reload(really: false)
    }
    
    @objc func userleftPublicChat(_ n:Notification) {
        self.reload(really: false)
    }
    
    public func reload(really:Bool = true) {
        if really == true {
            self._conversations = ConnectionsController.shared.conversations()
        }
                
        for conversation in self._conversations {
            for connection in ConnectionsController.shared.connections {
                if conversation.uri == connection.URI {
                    let uc = ConnectionsController.shared.usersController(forConnection: connection)
                                        
                    if let user = uc.user(withNick: conversation.nick!) {
                        conversation.userID = user.userID
                        conversation.connection = connection
                    } else {
                        conversation.connection = nil
                        conversation.userID = nil
                    }
                }
            }
        }
    }
    
    public func conversations() -> [Conversation] {
        return self._conversations
    }
    
    
    
    public func openConversation(onConnection connection:Connection, withUser user: UserInfo) -> Conversation? {
        var conversation = ConnectionsController.shared.conversation(withNick: user.nick!, onConnection: connection)
        let context = AppDelegate.shared.persistentContainer.viewContext
        
        if conversation == nil {
            conversation = NSEntityDescription.insertNewObject(
                forEntityName: "Conversation", into: context) as? Conversation

            conversation!.nick = user.nick!
            conversation!.icon = user.icon
            conversation!.uri = connection.URI
            conversation?.userID = connection.userID
            
            conversation?.connection = connection
            
            AppDelegate.shared.saveAction(self as AnyObject)
        }
        
        AppDelegate.shared.showMessages(self)
        NotificationCenter.default.post(name: NSNotification.Name("ShouldSelectConversation"), object: conversation)
        
        return conversation
    }
}
