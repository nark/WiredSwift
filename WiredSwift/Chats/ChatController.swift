//
//  ChatController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa


extension NSTextView {
    func appendString(string:String) {
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key.foregroundColor : NSColor.controlTextColor,
            .font : NSFont(name: "Courier", size: 14) as Any
        ]
        
        self.textStorage?.append(NSAttributedString(string: string + "\n", attributes: attrs))
        self.scrollRangeToVisible(NSRange(location:self.string.count, length: 0))
    }
}


class ChatController: ConnectionController, ConnectionDelegate {
    @IBOutlet var chatTextView: NSTextView!
    @IBOutlet var chatInput: NSTextField!
    
    private var users:[UserInfo] = []
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
                        
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserNick", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        chatInput.becomeFirstResponder()
    }
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                
                c.delegates.append(self)
            }
        }
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        print("observeValue: \(keyPath) -> \(change?[NSKeyValueChangeKey.newKey])")
        if keyPath == "WSUserNick" {
            if let nick = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setNickMessage(nick) {
                  self.connection.send(message: m)
                }
            }
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
        if message.name == "wired.chat.say" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            guard let sayString = message.string(forField: "wired.chat.say") else {
                return
            }
            
            if let userNick = self.user(forID: userID)?.nick {
                self.chatTextView.appendString(string: "\(userNick): \(sayString)")
            }
        }
        else if message.name == "wired.chat.me" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            guard let sayString = message.string(forField: "wired.chat.me") else {
                return
            }
            
            if let userNick = self.user(forID: userID)?.nick {
                self.chatTextView.appendString(string: "*** \(userNick) \(sayString)")
            }
        }
        else if message.name == "wired.chat.topic" {
            guard let userNick = message.string(forField: "wired.user.nick") else {
                return
            }
            
            guard let chatTopic = message.string(forField: "wired.chat.topic.topic") else {
                return
            }
            
            self.chatTextView.appendString(string: "<< Topic: \(chatTopic) by \(userNick) >>")
        }
        else if  message.name == "wired.chat.user_list" {
            let userInfo = UserInfo(message: message)
            
            self.users.append(userInfo)
        }
        else if  message.name == "wired.chat.user_status" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            if let user = self.user(forID: userID) {
                user.update(withMessage: message)
            }
        }
        else if message.name == "wired.chat.user_join" {
            let userInfo = UserInfo(message: message)
            
            self.chatTextView.appendString(string: "<< \(userInfo.nick!) joined the chat >>")
            
            self.users.append(userInfo)
        }
        else if message.name == "wired.chat.user_leave" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            if let user = self.user(forID: userID) {
                self.chatTextView.appendString(string: "<< \(user.nick!) left the chat >>")
            }
            
            if let index = users.index(where: {$0.userID == userID}) {
                users.remove(at: index)
            }
        }
    }
    
    
    private func user(forID uid: UInt32) -> UserInfo? {
        for u in users {
            if u.userID == uid {
                return u
            }
        }
        return nil
    }
}
