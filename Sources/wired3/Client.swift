//
//  Client.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 24/04/2021.
//

import Foundation
import WiredSwift

public class Client {
    public enum State:UInt32 {
        case CONNECTED          = 0
        case GAVE_CLIENT_INFO
        case LOGGED_IN
        case DISCONNECTED
    }
    
    public var ip:String?
    public var host:String?
    public var nick:String?
    public var status:String?
    public var icon:Data?
    public var state:State = .DISCONNECTED
    
    public var userID:UInt32
    public var user:User?
    public var socket:P7Socket!
    public var transfer:Transfer?
    
    public init(userID:UInt32, socket: P7Socket) {
        self.userID = userID
        self.socket = socket
    }
}
