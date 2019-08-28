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
        self.string += string
        self.scrollRangeToVisible(NSRange(location:self.string.count, length: 0))
    }
}


class ChatController: ConnectionController, ConnectionDelegate {
    @IBOutlet var chatTextView: NSTextView!
    
    private var users:[UserInfo] = []
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
    }
    
    
    override func viewDidDisappear() {
        if let c = self.connection {
            c.disconnect()
        }
        super.viewDidDisappear()
    }
    
    
    
    override var representedObject: Any? {
        didSet {
            if let c = self.representedObject as? Connection {
                self.connection = c
                
                c.delegates.append(self)
            }
        }
    }
    
    
    
    
    
    @IBAction func chatAction(_ sender: Any) {
        if let textField = sender as? NSTextField, textField.stringValue.count > 0 {
            let message = P7Message(withName: "wired.chat.send_say", spec: self.connection.spec)
            
            message.addParameter(field: "wired.chat.id", value: UInt32(1))
            message.addParameter(field: "wired.chat.say", value: textField.stringValue)
            
            if self.connection.socket.write(message) {
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
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if message.name == "wired.chat.say" {
            guard let userID = message.uint32(forField: "wired.user.id") else {
                return
            }
            
            guard let sayString = message.string(forField: "wired.chat.say") else {
                return
            }
            
            if let userNick = self.user(forID: userID)?.nick {
                self.chatTextView.appendString(string: "\(userNick): \(sayString)\n")
            }
        }
        if  message.name == "wired.chat.user_list" ||
            message.name == "wired.chat.user_join"  {
            let userInfo = UserInfo(message: message)
            
            self.users.append(userInfo)
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
