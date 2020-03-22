//
//  MessagesViewController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class PrivateMessagesViewController: ConnectionViewController, ConnectionDelegate {
    @IBOutlet var chatInput: GrowingTextField!
    @IBOutlet weak var sendButton: NSButton!
    @IBOutlet weak var emojiButton: NSButton!
    
    weak var conversationViewController: ConversationViewController!
    var conversation:Conversation!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        
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
        
        self.updateView()
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
                    self.conversationViewController.addPrivateMessage(
                        message: cdMessage.body!, cdMessage: cdMessage, me: false)
                }
            }
        }
    }
    
    @objc func userJoinedPublicChat(_ n:Notification) {
        if let array = n.object as? [Any] {
            if  let connection = array.first as? Connection,
                let userInfo = array.last as? UserInfo,
                self.conversation != nil,
                self.conversation.nick == userInfo.nick {

                self.connection = connection
                self.conversation.connection = connection
                self.conversationViewController.connection = connection

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
            self.conversationViewController.connection = nil

            self.updateView()
        }
    }
    
    @objc func selectedConversationDidChange(_ n:Notification) {
        self.conversationViewController.cleanAllMessages()
        
        if n.object == nil {
            if self.connection != nil {
                self.connection.removeDelegate(self)
            }

            if self.conversation != nil {
                self.conversation.connection = nil
            }

            self.connection = nil
            self.conversationViewController.connection = nil

            self.conversation = nil
        }
        else if let conversation = n.object as? Conversation {
            self.conversation = conversation
            
            if conversation.connection != nil {
                self.connection = conversation.connection
                self.conversationViewController.connection = self.connection
                
                self.connection.removeDelegate(self)
                self.connection.delegates.append(self)
                
            }
            
            self.conversationViewController.loadMessages(from: conversation)
        }

        self.updateView()
    }
    
    
    
    // MARK: -
    
    private func updateView() {
        self.chatInput.isEnabled = false
        self.sendButton.isEnabled = false
        self.emojiButton.isEnabled = false
        
        print("update self.conversation : \(self.conversation)")
        
        if let conversation = self.conversation {
            if conversation.connection != nil && conversation.connection.isConnected() {
                self.chatInput.isEnabled = true
                self.sendButton.isEnabled = true
                self.emojiButton.isEnabled = true
                
                self.chatInput.becomeFirstResponder()
            }
            print("will load messages")
        }
    }
    
    
    
    // MARK: -
    
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if let conversationViewController = segue.destinationController as? ConversationViewController {
            self.conversationViewController = conversationViewController
            self.conversationViewController.connection = self.connection
        }
    }
    
    
    
    
    // MARK: -
    
    @IBAction func showEmojis(_ sender: Any) {
        NSApp.orderFrontCharacterPalette(self.chatInput)
    }
    
    
    
    @IBAction func chatAction(_ sender: Any) {
        if let textField = sender as? NSTextField, textField.stringValue.count > 0 {
            
            let message = P7Message(withName: "wired.message.send_message", spec: self.connection.spec)
            message.addParameter(field: "wired.user.id", value: self.conversation.userID)
            message.addParameter(field: "wired.message.message", value: textField.stringValue)
            
            if self.connection.send(message: message) {
                let context = AppDelegate.shared.persistentContainer.viewContext
                if let cdObject = NSEntityDescription.insertNewObject(forEntityName: "Message", into: context) as? Message {
                    cdObject.body = textField.stringValue
                    cdObject.nick = self.connection.userInfo!.nick
                    cdObject.userID = Int32(self.connection.userID)
                    cdObject.me = true
                    cdObject.read = true
                        
                    self.conversation.addToMessages(cdObject)
                    self.conversationViewController.addPrivateMessage(
                        message: textField.stringValue, cdMessage: cdObject)
                }
                
                textField.stringValue = ""
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
    
}
