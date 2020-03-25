//
//  ChatController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa
import MessageKit_macOS

class ChatViewController: ConnectionViewController, ConnectionDelegate, NSTextFieldDelegate {
    @IBOutlet var chatInput: NSTextField!
    @IBOutlet weak var sendButton: NSButton!
    
    weak var conversationViewController: ConversationViewController!
    var textDidEndEditingTimer:Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.chatInput.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(linkConnectionDidClose(_:)), name: .linkConnectionDidClose, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(linkConnectionDidReconnect(_:)), name: .linkConnectionDidReconnect, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(controlTextDidChange(_:)), name: NSTextView.didChangeSelectionNotification, object: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserNick", options: NSKeyValueObservingOptions.new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserStatus", options: NSKeyValueObservingOptions.new, context: nil)
        UserDefaults.standard.addObserver(self, forKeyPath: "WSUserIcon", options: NSKeyValueObservingOptions.new, context: nil)
    }
    
    
    override func viewDidAppear() {
        super.viewDidAppear()
        
        if self.connection != nil {
            chatInput.becomeFirstResponder()
            
            AppDelegate.resetChatUnread(forKey: "WSUnreadChatMessages", forConnection: connection)
        }
    }
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? ServerConnection {
                self.connection = c
                
                self.conversationViewController.connection = self.connection
                
                c.delegates.append(self)
            }
        }
    }
    
    // MARK: -
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        //print("observeValue: \(keyPath) -> \(change?[NSKeyValueChangeKey.newKey])")
        if keyPath == "WSUserNick" {
            if let nick = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setNickMessage(nick) {
                  _ = self.connection.send(message: m)
                }
            }
        }
        else if keyPath == "WSUserStatus" {
            if let status = change?[NSKeyValueChangeKey.newKey] as? String {
                if let m = self.setStatusMessage(status) {
                  _ = self.connection.send(message: m)
                }
            }
        }
        else if keyPath == "WSUserIcon" {
            if let icon = change?[NSKeyValueChangeKey.newKey] as? Data {
                // NOTE : this one was a hell
                if let image = try! NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: icon) {
                    let b64String = image.tiffRepresentation(using: NSBitmapImageRep.TIFFCompression.none, factor: 0)!.base64EncodedString()
                    if let b64Data = Data(base64Encoded: b64String, options: .ignoreUnknownCharacters) {
                        if let m = self.setIconMessage(b64Data) {
                            _ = self.connection.send(message: m)
                        }
                    }
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
    
    
    // MARK: -
    @objc func linkConnectionDidClose(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            conversationViewController.addEventMessage(message: "<< Disconnected from \(self.connection.serverInfo.serverName!) >>")
        }
    }
    
    @objc func linkConnectionDidReconnect(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            conversationViewController.addEventMessage(message: "<< Reconnected to \(self.connection.serverInfo.serverName!) >>")
        }
    }
    
    
    
    
    // MARK: -
    
    @objc func controlTextDidChange(_ n: Notification) {
        if (n.object as? NSTextField) == self.chatInput {
            self.chatInputDidEndEditing()
        }
    }
    
    private func chatInputDidEndEditing() {
        if self.chatInput.stringValue.count > 3 {
            if textDidEndEditingTimer != nil {
                textDidEndEditingTimer.invalidate()
                textDidEndEditingTimer = nil
            }
            
            if UserDefaults.standard.bool(forKey: "WSEmojiSubstitutionsEnabled") {
                textDidEndEditingTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: false) { (timer) in
                    self.substituteEmojis()
                }
            }

        }
    }
    
    private func substituteEmojis() {
        if UserDefaults.standard.bool(forKey: "WSEmojiSubstitutionsEnabled") {
            if let lastWord = self.chatInput.stringValue.split(separator: " ").last {
                if let emoji = AppDelegate.emoji(forKey: String(lastWord)) {
                    let string = (self.chatInput.stringValue as NSString).replacingOccurrences(of: String(lastWord), with: emoji)
                    self.chatInput.stringValue = string
                }
            }
        }
    }
    
    
    
    // MARK: -
    
    private func setNickMessage(_ nick:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_nick", spec: self.connection.spec)
        message.addParameter(field: "wired.user.nick", value: nick)
        
        if UserDefaults.standard.string(forKey: "WSUserNick") == nick {
            UserDefaults.standard.set(nick, forKey: "WSUserNick")
        }
        
        return message
    }
    
    
    private func setStatusMessage(_ status:String) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_status", spec: self.connection.spec)
        message.addParameter(field: "wired.user.status", value: status)
        
        if UserDefaults.standard.string(forKey: "WSUserStatus") == status {
            UserDefaults.standard.set(status, forKey: "WSUserStatus")
        }
        
        
        return message
    }
    
    
    private func setIconMessage(_ icon:Data) -> P7Message? {
        let message = P7Message(withName: "wired.user.set_icon", spec: self.connection.spec)
        
        message.addParameter(field: "wired.user.icon", value: icon)
        
//        if UserDefaults.standard.string(forKey: "WSUserStatus") == status {
//            UserDefaults.standard.set(status, forKey: "WSUserStatus")
//        }
        
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
                self.substituteEmojis()
                
                message = P7Message(withName: "wired.chat.send_say", spec: self.connection.spec)
                
                message!.addParameter(field: "wired.chat.id", value: UInt32(1))
                message!.addParameter(field: "wired.chat.say", value: textField.stringValue)
            }
            
            if self.connection.isConnected() {
                if let m = message, self.connection.send(message: m) {
                    textField.stringValue = ""
                }
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
                    if self.chatInput.currentEditor() == nil || NSApp.isActive == false || self.view.window?.isKeyWindow == false {
                        AppDelegate.incrementChatUnread(forConnection: connection)
                        AppDelegate.notify(identifier: "chatMessage", title: "New Chat Message", subtitle: userInfo.nick!, text: sayString, connection: connection)
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
                        AppDelegate.incrementChatUnread(forConnection: connection)
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
