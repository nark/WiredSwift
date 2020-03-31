//
//  MessagesViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class PrivateMessagesViewController: ConnectionViewController, ConnectionDelegate, NSTextFieldDelegate, NSTableViewDelegate, NSTableViewDataSource {
    @IBOutlet weak var messagesTableView: NSTableView!
    @IBOutlet weak var chatInput: NSTextField!
    @IBOutlet weak var sendButton: NSButton!
    @IBOutlet weak var emojiButton: NSButton!
    
    //weak var conversationViewController: ConversationViewController!
    var conversation:Conversation!
    var textDidEndEditingTimer:Timer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(controlTextDidChange(_:)),
            name: NSTextView.didChangeSelectionNotification, object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(selectedConversationDidChange(_:)),
            name: .selectedConversationDidChange, object: nil)
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(receivedPrivateMessage(_:)),
        name: NSNotification.Name("ReceivedPrivateMessage"), object: nil)
        
        NotificationCenter.default.addObserver(
        self, selector: #selector(userJoinedPublicChat(_:)),
        name: NSNotification.Name("UserJoinedPublicChat"), object: nil)
        
        NotificationCenter.default.addObserver(
            self, selector: #selector(userLeftPublicChat(_:)),
            name: NSNotification.Name("UserLeftPublicChat"), object: nil)
        
        self.chatInput.delegate = self
        self.updateView()
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
    @objc func receivedPrivateMessage(_ n:Notification) {
        if let array = n.object as? [Any] {
            if  let connection = array.first as? Connection,
                let cdMessage = array.last as? Message,
                self.conversation != nil,
                self.conversation.connection != nil,
                connection == self.conversation.connection {
                
                DispatchQueue.main.async {
                   self.conversation.addToMessages(cdMessage)
                   
                   self.messagesTableView.beginUpdates()
                   self.messagesTableView.insertRows(at: [self.messagesTableView.numberOfRows], withAnimation: NSTableView.AnimationOptions.effectFade)
                   self.messagesTableView.endUpdates()
                   self.messagesTableView.noteNumberOfRowsChanged()
                   
                   self.messagesTableView.scrollToVisible(self.messagesTableView.rect(ofRow: self.messagesTableView.numberOfRows - 1))
                }
            }
        }
    }
    
    @objc func userJoinedPublicChat(_ n:Notification) {
        if let array = n.object as? [Any] {
            if  let connection = array.first as? ServerConnection,
                let userInfo = array.last as? UserInfo,
                self.conversation != nil,
                self.conversation.nick == userInfo.nick {

                self.connection = connection
                self.conversation.connection = connection

                self.connection.removeDelegate(self)
                self.connection.delegates.append(self)

                self.updateView()
            }
        }
    }
    
    @objc func userLeftPublicChat(_ n:Notification) {
        if let connection = n.object as? Connection, self.connection == connection {
            if self.connection != nil {
                self.connection.removeDelegate(self)
            }
            
            if self.conversation != nil {
                self.conversation.connection = nil
            }

            self.connection = nil

            self.updateView()
        }
    }
    
    @objc func selectedConversationDidChange(_ n:Notification) {
        // CLEAR CONVERSATION MESSAGES
        // self.conversationViewController.cleanAllMessages()
        
        if n.object == nil {
            if self.connection != nil {
                self.connection.removeDelegate(self)
            }

            if self.conversation != nil {
                self.conversation.connection = nil
            }

            self.connection = nil

            self.conversation = nil
        }
        else if let conversation = n.object as? Conversation {
            self.conversation = conversation
            
            if self.conversation.connection == nil {
                self.conversation.connection = self.connection
            }
            
            if conversation.connection != nil {
                self.connection = conversation.connection
                
                self.connection.removeDelegate(self)
                self.connection.delegates.append(self)
                
            }
            
            // LOAD ALL CONVERSATION MESSAGES
            // self.conversationViewController.loadMessages(from: conversation)
        }

        self.updateView()
    }
    
    
    
    
    // MARK: -
    
    private func updateView() {
        self.chatInput.isEditable = false
        self.emojiButton.isEnabled = false
        self.chatInput.placeholderString = "Unavailable"
                
        if let conversation = self.conversation {

            if conversation.connection != nil && conversation.connection.isConnected() {
                let uc = ConnectionsController.shared.usersController(forConnection: conversation.connection)
                if conversation.userID != -1 && uc.user(forID: UInt32(conversation.userID)) != nil {
                    self.chatInput.isEditable = true
                    self.emojiButton.isEnabled = true
                    self.chatInput.placeholderString = "Type message here"
                    self.chatInput.becomeFirstResponder()
                }
                AppDelegate.updateUnreadMessages(forConnection: conversation.connection)
            }
        }
        
        self.messagesTableView.reloadData()
        
        self.perform(#selector(self.scrollToBottom), with:nil, afterDelay: 0.3)
        self.perform(#selector(self.scrollToBottom), with:nil, afterDelay: 0.4)
    }
    
    
    @objc private func scrollToBottom() {
        self.messagesTableView.scrollToVisible(self.messagesTableView.rect(ofRow: self.messagesTableView.numberOfRows - 1))
    }
    
    
    // MARK: -
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {

    }
    
    
    
    
    // MARK: -
    
    @IBAction func showEmojis(_ sender: Any) {
        NSApp.orderFrontCharacterPalette(self.chatInput)
    }
    
    
    
    @IBAction func chatAction(_ sender: Any) {
        if self.connection != nil && self.connection.isConnected() {
            if let textField = sender as? NSTextField, textField.stringValue.count > 0 {
                self.substituteEmojis()
                
                let message = P7Message(withName: "wired.message.send_message", spec: self.connection.spec)
                message.addParameter(field: "wired.user.id", value: UInt32(self.conversation.userID))
                message.addParameter(field: "wired.message.message", value: textField.stringValue)
                
                if self.connection.isConnected() {
                    if self.connection.send(message: message) {
                        let context = AppDelegate.shared.persistentContainer.viewContext
                        if let cdObject = NSEntityDescription.insertNewObject(forEntityName: "Message", into: context) as? Message {
                            cdObject.body = textField.stringValue
                            cdObject.nick = self.connection.userInfo!.nick
                            cdObject.userID = Int32(self.connection.userID)
                            cdObject.date = Date()
                            cdObject.me = true
                            cdObject.read = true
                                
                            self.conversation.addToMessages(cdObject)
                            
                            self.messagesTableView.beginUpdates()
                            self.messagesTableView.insertRows(at: [self.messagesTableView.numberOfRows], withAnimation: NSTableView.AnimationOptions.effectFade)
                            self.messagesTableView.endUpdates()
                            self.messagesTableView.noteNumberOfRowsChanged()
                            
                            self.perform(#selector(self.scrollToBottom), with:nil, afterDelay: 0.3)
                            self.perform(#selector(self.scrollToBottom), with:nil, afterDelay: 0.4)
                        }
                        
                        textField.stringValue = ""
                    }
                }
            }
        }
    }
    

    
    
    // MARK: -
    
    func connectionDidConnect(connection: Connection) {
        
    }
    
    func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {

    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
    
    
    // MARK: -
    
    
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 80
    }
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        if self.conversation == nil {
            return 0
        }
        
        return self.conversation.messages?.count ?? 0
    }
    
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        var view: MessageCellView?
        
        if let message = self.conversation.messages?.array[row] as? Message {
            let sentOrReceived = !message.me ? "ReceivedMessageCell" : "SentMessageCell"
            
            view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: sentOrReceived), owner: self) as? MessageCellView
            
            view?.nickLabel.stringValue = message.nick ?? ""
            view?.textField?.attributedStringValue = message.body?.substituteURL() ?? NSAttributedString(string: "")
                        
            if message.me {
                if let data = UserDefaults.standard.data(forKey: "WSUserIcon") {
                    if let image = try! NSKeyedUnarchiver.unarchivedObject(ofClass: NSImage.self, from: data) {
                        view?.imageView?.image = image
                    }
                }
            } else {
                if conversation.connection != nil {
                    let uc = ConnectionsController.shared.usersController(forConnection: conversation.connection)

                    if let icon = uc.getIcon(forUserID: UInt32(message.userID)) {
                        view?.imageView?.image = icon
                    }
                }
            }
            
        }
        
        return view
    }
    


}
