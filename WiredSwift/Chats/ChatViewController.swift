//
//  ChatController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import MessageKit_macOS


class ChatViewController: ConnectionViewController, ConnectionDelegate {
    @IBOutlet var chatInput: GrowingTextField!
    @IBOutlet weak var sendButton: NSButton!
    
    weak var conversationViewController: ConversationViewController!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserNick", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        if self.connection != nil {
            chatInput.becomeFirstResponder()
            
            AppDelegate.resetUnread(forKey: "WSUnreadChatMessages", forConnection: connection)
        }
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                
                self.conversationViewController.connection = self.connection
                
                c.delegates.append(self)
            }
        }
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //print("observeValue: \(keyPath) -> \(change?[NSKeyValueChangeKey.newKey])")
        if keyPath == "WSUserNick" {
            if let nick = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setNickMessage(nick) {
                  _ = self.connection.send(message: m)
                }
            }
        }
    }
    
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {        
        if let conversationViewController = segue.destinationController as? ConversationViewController {
            self.conversationViewController = conversationViewController
            self.conversationViewController.connection = self.connection
        }
    }
    
    
    private func setNickMessage(_ nick:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.connection.spec)
        message.addParameter(field: "wired.user.nick", value: nick)
        
        if UserDefaults.standard.string(forKey: "WSUserNick") == nick {
            UserDefaults.standard.set(nick, forKey: "WSUserNick")
        }
        
        return message
    }
    

    private func chatCommand(_ command: String) -> P7Message? {
        let comps = command.split(separator: " ")
        
        if comps[0] == "/me" {
            let message = P7Message(withName: "wired.chat.send_me", spec: self.connection.spec)
            let value = command.deletingPrefix(comps[0]+" ")
            
            message.addParameter(field: "wired.chat.id", value: UInt32(1))
            message.addParameter(field: "wired.chat.me", value: value)
            
            return message
        }
        
        else if comps[0] == "/nick" {
            let value = command.deletingPrefix(comps[0]+" ")
            return self.setNickMessage(value)
        }
            
        else if comps[0] == "/status" {
            let message = P7Message(withName: "wired.user.set_status", spec: self.connection.spec)
            let value = command.deletingPrefix(comps[0]+" ")
            
            message.addParameter(field: "wired.user.status", value: value)
            
            UserDefaults.standard.set(value, forKey: "WSUserStatus")
            
            return message
        }
        
        else if comps[0] == "/topic" {
            let message = P7Message(withName: "wired.chat.set_topic", spec: self.connection.spec)
            let value = command.deletingPrefix(comps[0]+" ")
            
            message.addParameter(field: "wired.chat.id", value: UInt32(1))
            message.addParameter(field: "wired.chat.topic.topic", value: value)
            
            return message
        }
        
        return nil
    }
    
    
    @IBAction func showEmojis(_ sender: Any) {
        NSApp.orderFrontCharacterPalette(self.chatInput)
    }
    
    
    
    @IBAction func chatAction(_ sender: Any) {
        if let textField = sender as? NSTextField, textField.stringValue.count > 0 {
            var message:P7Message? = nil
            
            if textField.stringValue.starts(with: "/") {
                message = self.chatCommand(textField.stringValue)
            }
            else {
                message = P7Message(withName: "wired.chat.send_say", spec: self.connection.spec)
                
                message!.addParameter(field: "wired.chat.id", value: UInt32(1))
                message!.addParameter(field: "wired.chat.say", value: textField.stringValue)
            }
            
            if let m = message, self.connection.send(message: m) {
                textField.stringValue = ""
            }
        }
    }
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        if let specError = spec.error(forMessage: message), let message = specError.name {
            let alert = NSAlert()
            alert.messageText = "Wired Alert"
            alert.informativeText = "Wired Error: \(message)"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
            alert.runModal()
        }
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        let uc = ConnectionsController.shared.usersController(forConnection: self.connection)
        
        if message.name == "wired.chat.say" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            guard let sayString = message.string(forField: "wired.chat.say") else {
                return
            }
            
            if let userInfo = uc.user(forID: userID) {
                conversationViewController.addChatMessage(message: sayString, fromUser: userInfo, me: (userInfo.userID == self.connection.userID))
                
                // add unread
                if userInfo.userID != self.connection.userID {
                    if self.chatInput.currentEditor() == nil || self.view.window?.isKeyWindow == false {
                        AppDelegate.incrementUnread(forKey: "WSUnreadChatMessages", forConnection: connection)
                    }
                }
            }
        }
        else if message.name == "wired.chat.me" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            guard let sayString = message.string(forField: "wired.chat.me") else {
                return
            }
            
            if let userInfo = uc.user(forID: userID) {
                conversationViewController.addChatMessage(message: "→ \(userInfo.nick!) \(sayString)", fromUser: userInfo, me: (userInfo.userID == self.connection.userID))
                
                // add unread
                if userInfo.userID != self.connection.userID {
                    if NSApp.isActive == false || self.view.window?.isKeyWindow == false {
                        AppDelegate.incrementUnread(forKey: "WSUnreadChatMessages", forConnection: connection)
                    }
                }
            }
        }
        else if message.name == "wired.chat.topic" {
            guard let userNick = message.string(forField: "wired.user.nick") else {
                return
            }
            
            guard let chatTopic = message.string(forField: "wired.chat.topic.topic") else {
                return
            }
            
            conversationViewController.addEventMessage(message: "<< Topic: \(chatTopic) by \(userNick) >>")
        }
        else if  message.name == "wired.chat.user_list" {

        }
        else if  message.name == "wired.chat.user_status" {

        }
        else if message.name == "wired.chat.user_join" {
            let userInfo = UserInfo(message: message)
            conversationViewController.addEventMessage(message: "<< \(userInfo.nick!) joined the chat >>")
            
            NotificationCenter.default.post(name: NSNotification.Name("UserJoinedPublicChat"), object: [self.connection, userInfo])
        }
        else if message.name == "wired.chat.user_leave" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            let uc = ConnectionsController.shared.usersController(forConnection: self.connection)
            if let u = uc.user(forID: userID) {
                conversationViewController.addEventMessage(message: "<< \(u.nick!) left the chat >>")
                uc.userLeave(message: message)
                
                NotificationCenter.default.post(name: NSNotification.Name("UserLeftPublicChat"), object: self.connection)
            }
        }
        
    }
}