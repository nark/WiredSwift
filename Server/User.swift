//
//  User.swift
//  Server
//
//  Created by Rafael Warnault on 20/03/2021.
//

import Foundation
import WiredSwift

public class User {
    public enum State:UInt32 {
        case CONNECTED           = 0
        case DISCONNECTED        = 1
    }
    
    public var userID:UInt32!
    public var username:String?
    public var socket:P7Socket?
    public var state:State = .DISCONNECTED
    public var ip:String?
    public var host:String?
    public var nick:String?
    public var status:String?
    public var icon:Data?
    
    public init(_ socket:P7Socket, userID: UInt32) {
        self.socket = socket
        self.state  = .CONNECTED
        self.userID = userID
        //self.ip = self.socket
    }
}
