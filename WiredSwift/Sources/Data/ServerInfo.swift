//
//  ServerInfo.swift
//  Wired 3
//
//  Created by Rafael Warnault on 20/08/2019.
//  Copyright © 2019 Read-Write. All rights reserved.
//

import Foundation


public class ServerInfo {
    public var applicationName: String!
    public var applicationVersion: String!
    public var applicationBuild: String!
    
    public var osName: String!
    public var osVersion: String!
    public var arch: String!
    
    public var supportRSRC: Bool!
    public var serverName: String!
    public var serverDescription: String!
    public var serverBanner: Data!
    
    private var message: P7Message!
    
    public init(message: P7Message) {
        self.message = message
        
        if let v = message.string(forField: "wired.info.application.name") {
            self.applicationName = v
        }
        
        if let v = message.string(forField: "wired.info.application.version") {
            self.applicationVersion = v
        }
        
        if let v = message.string(forField: "wired.info.application.build") {
            self.applicationBuild = v
        }
        
        if let v = message.string(forField: "wired.info.os.name") {
            self.osName = v
        }
        
        if let v = message.string(forField: "wired.info.os.version") {
            self.osVersion = v
        }
        
        if let v = message.string(forField: "wired.info.arch") {
            self.arch = v
        }
        
        if let v = message.bool(forField: "wired.info.supports_rsrc") {
            self.supportRSRC = v
        }
        
        if let v = message.string(forField: "wired.info.name") {
            self.serverName = v
        }
        
        if let v = message.string(forField: "wired.info.description") {
            self.serverDescription = v
        }
        
        if let v = message.data(forField: "wired.info.banner") {
            self.serverBanner = v
        }
    }
}
