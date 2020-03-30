//
//  UsersController.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 21/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa


class UsersController: ConnectionObject {
    private var users:[UserInfo] = []
    
    
    
    public override init(_ connection: ServerConnection) {
        super.init(connection)
    }
    
    
    
    public func userJoin(message:P7Message) {
        let userInfo = UserInfo(message: message)
        
        if userInfo.userID == self.connection.userID {
            self.connection.userInfo = userInfo
        }
        
        self.users.append(userInfo)
    }
    
    
    
    public func userLeave(message:P7Message) {
        if let userID = message.uint32(forField: "wired.user.id") {
            if let index = users.index(where: {$0.userID == userID}) {
                self.users.remove(at: index)
            }
        }
    }
    
    
    
    public func updateStatus(message:P7Message) {
        guard let userID = message.uint32(forField: "wired.user.id") else {
            return
        }
        
        if let user = self.user(forID: userID) {
            user.update(withMessage: message)
        }
    }
    
    
    public func numberOfUsers() -> Int {
        return self.users.count
    }
    
    
    public func user(at index: Int) -> UserInfo? {
        return self.users[index]
    }
    
    
    public func removeAllUsers() {
        self.users = []
    }
    
    public func user(forID uid: UInt32) -> UserInfo? {
        for u in self.users {
            if u.userID == uid {
                return u
            }
        }
        return nil
    }
    
    public func user(withNick nick: String) -> UserInfo? {
        for u in self.users {
            if u.nick! == nick {
                return u
            }
        }
        return nil
    }
    
    public func getIcon(forUserID uid: UInt32) -> NSImage? {
        if let u = self.user(forID: uid) {
            if let base64ImageString = u.icon?.base64EncodedData() {
                if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                    return NSImage(data: data)
                }
            }
        }
        
        return nil
    }
    
    
    private func userInitials(_ user:UserInfo) -> String {
        let length = user.nick.count - 2
        return String(user.nick.dropLast(length))
    }
}
