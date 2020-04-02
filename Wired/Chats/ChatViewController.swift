//
//  ChatController.swift
//  Wired 3
//
//  Created by Rafael Warnault on 19/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Cocoa

class ChatViewController: ConnectionViewController, ConnectionDelegate, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    @IBOutlet var chatInput: NSTextField!
    @IBOutlet weak var sendButton: NSButton!
    @IBOutlet weak var messagesTableView: NSTableView!
    
    var messages:[Any] = []
    var sentMessages:[P7Message] = []
    var receivedMessages:[P7Message] = []
    
    //weak var conversationViewController: ConversationViewController!
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
                
                //self.conversationViewController.connection = self.connection
                
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

    }
    
    
    
    
    
    // MARK: -
    
    @objc func controlTextDidChange(_ n: Notification) {
        if (n.object as? NSTextField) == self.chatInput {
            self.chatInputDidEndEditing()
        }
    }
    
    private func chatInputDidEndEditing() {
        if self.chatInput.stringValue.count >= 2 {
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
            
            UserDefaults.standard.set(value, forKey: "WSUserNick")
            
            return self.setNickMessage(value)
        }
            
        else if comps[0] == "/status" {
            let value = command.deletingPrefix(comps[0]+" ")
            
            UserDefaults.standard.set(value, forKey: "WSUserStatus")
            
            return self.setStatusMessage(value)
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
        if self.connection != nil && self.connection.isConnected() {
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
    }
    
    
    
    // MARK: -
    @objc func linkConnectionDidClose(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            self.chatInput.isEditable = false
            let disconnected = NSLocalizedString("Disconnected...", comment: "")
            self.chatInput.placeholderString = disconnected
            let disconnectedfrom = NSLocalizedString("Disconnected from", comment: "")
            self.addMessage("<< " + disconnectedfrom + " " + "\(self.connection.serverInfo.serverName!) >>")
            
            if UserDefaults.standard.bool(forKey: "WSAutoReconnect") {
                if !self.connection.connectionWindowController!.manualyDisconnected {
                    let autoreconnecting = NSLocalizedString("Auto-reconnecting...", comment: "")
                    self.addMessage("<< " + autoreconnecting + " ⏱ >>")
                }
            }
        }
    }
    
    @objc func linkConnectionDidReconnect(_ n: Notification) {
        if let c = n.object as? Connection, c == self.connection {
            self.chatInput.isEditable = true
            self.chatInput.placeholderString = "Type message here"
            let reconnectedto = NSLocalizedString("Auto-reconnecting to", comment: "")
            self.addMessage("<< " + reconnectedto + " \(self.connection.serverInfo.serverName!) >>")
        }
    }
    
    
    // MARK: -
    
    func connectionDidConnect(connection: Connection) {
        self.chatInput.isEditable = true
        let disconnected = NSLocalizedString("Disconnected...", comment: "")
        self.chatInput.placeholderString = disconnected
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        if let specError = spec.error(forMessage: message), let message = specError.name {
            let alert = NSAlert()
            let wiredalert = NSLocalizedString("Wired Alert", comment: "")
            alert.messageText = wiredalert
            let wirederror = NSLocalizedString("Wired Error:", comment: "")
            alert.informativeText = wirederror + " \(message)"
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
                self.addMessage(message, sent: userID == self.connection.userID)
                
                // add unread
                if userInfo.userID != self.connection.userID {
                    if self.chatInput.currentEditor() == nil || NSApp.isActive == false || self.view.window?.isKeyWindow == false {
                        AppDelegate.incrementChatUnread(forConnection: connection)
                        let newchatmessage = NSLocalizedString("New Chat Message", comment: "")
                        AppDelegate.notify(identifier: "chatMessage", title: newchatmessage, subtitle: userInfo.nick!, text: sayString, connection: connection)
                    }
                }
            }
        }
        else if message.name == "wired.chat.me" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            if let userInfo = uc.user(forID: userID) {
                self.addMessage(message, sent: userID == self.connection.userID)
                
                // add unread
                if userInfo.userID != self.connection.userID {
                    if NSApp.isActive == false || self.view.window?.isKeyWindow == false {
                        AppDelegate.incrementChatUnread(forConnection: connection)
                    }
                }
            }
        }
        else if message.name == "wired.chat.topic" {
            self.addMessage(message, sent: false)
        }
        else if  message.name == "wired.chat.user_list" {

        }
        else if  message.name == "wired.chat.user_status" {

        }
        else if message.name == "wired.chat.user_join" {
            let userInfo = UserInfo(message: message)
            
            self.addMessage(message)
            
            NotificationCenter.default.post(name: NSNotification.Name("UserJoinedPublicChat"), object: [self.connection, userInfo])
        }
        else if message.name == "wired.chat.user_leave" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            let uc = ConnectionsController.shared.usersController(forConnection: self.connection)
            
            if let u = uc.user(forID: userID) {
                message.addParameter(field: "wired.user.nick", value: u.nick!)
                
                self.addMessage(message)

                uc.userLeave(message: message)
                
                NotificationCenter.default.post(name: NSNotification.Name("UserLeftPublicChat"), object: self.connection)
            }
        }
        
    }
    
    
    // MARK: -
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return self.messages.count
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: MessageCellView?
        
        view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "EventCell"), owner: self) as? MessageCellView
        
        if let message = messages[row] as? P7Message {
            let uc = ConnectionsController.shared.usersController(forConnection: self.connection)
            
            if message.name == "wired.chat.say" || message.name == "wired.chat.me" {
                let sentOrReceived = self.receivedMessages.contains(message
                    ) ? "ReceivedMessageCell" : "SentMessageCell"
                        
                view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: sentOrReceived), owner: self) as? MessageCellView
                
                if let userID = message.uint32(forField: "wired.user.id") {
                    if let userInfo = uc.user(forID: userID) {
                        if let attrString = message.string(forField: "wired.chat.say")?.substituteURL() {
                            view?.textField?.attributedStringValue = attrString
                        }
                        
                        if let string = message.string(forField: "wired.chat.me") {
                            view?.textField?.stringValue = " Nark \(string)"
                        }
                        
                        if let base64ImageString = userInfo.icon?.base64EncodedData() {
                            if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                                view?.imageView?.image = NSImage(data: data)
                            }
                        }
                        
                        view?.nickLabel.stringValue = userInfo.nick
                    }
                }
                
            }
            else if message.name == "wired.chat.topic" {
                if  let userNick = message.string(forField: "wired.user.nick"),
                    let chatTopic = message.string(forField: "wired.chat.topic.topic") {
                    let topicstring = NSLocalizedString("Topic:", comment: "")
                    let bystring = NSLocalizedString("by", comment: "")
                    view?.textField?.stringValue = "<< " + topicstring + " \(chatTopic) " + bystring + " \(userNick) >>"
                }
                
            }
            else if message.name == "wired.chat.user_join" {
                let userInfo = UserInfo(message: message)
                let joinedthechat = NSLocalizedString("joined the chat", comment: "")
                view?.textField?.stringValue = "<< \(userInfo.nick!) " + joinedthechat + " >>"
            }
            else if message.name == "wired.chat.user_leave" {
                if let nick = message.string(forField: "wired.user.nick") {
                    let leftthechat = NSLocalizedString("left the chat", comment: "")
                    view?.textField?.stringValue = "<< \(nick) " + leftthechat + " >>"
                }
            }
        } else if let string = messages[row] as? String {
            view?.textField?.stringValue = string
        }
        
        return view
    }
    
    
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 80 // minimum row size
    }

    
    // MARK: -

    private func addMessage(_ message:Any, sent: Bool = false) {
        self.messages.append(message)
        
        if let m = message as? P7Message {
            if sent {
                self.sentMessages.append(m)
            } else {
                self.receivedMessages.append(m)
            }
        }
        
        self.messagesTableView.beginUpdates()
        self.messagesTableView.insertRows(at: [self.messages.count - 1], withAnimation: NSTableView.AnimationOptions.effectFade)
        self.messagesTableView.endUpdates()
        self.messagesTableView.noteNumberOfRowsChanged()
        
        self.messagesTableView.scrollToVisible(self.messagesTableView.rect(ofRow: self.messages.count - 1))
    }
    
}
