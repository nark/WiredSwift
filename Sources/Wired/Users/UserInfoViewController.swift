//
//  UserInfoViewController.swift
//  Wired
//
//  Created by Rafael Warnault on 29/03/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

class UserInfoViewController: ConnectionViewController, ConnectionDelegate {
    @IBOutlet weak var iconView: NSImageView!
    @IBOutlet weak var nickLabel: NSTextField!
    @IBOutlet weak var statusLabel: NSTextField!
    
    @IBOutlet weak var loginLabel: NSTextField!
    @IBOutlet weak var ipLabel: NSTextField!
    @IBOutlet weak var hostnameLabel: NSTextField!
    @IBOutlet weak var versionlabel: NSTextField!
    @IBOutlet weak var cipherLabel: NSTextField!
    @IBOutlet weak var connectedLabel: NSTextField!
    @IBOutlet weak var idleLabel: NSTextField!
    
    public var user:UserInfo? {
        didSet {
            self.getUserInfo()
        }
    }
    
    
    // MARK: -
    
    func getUserInfo() {
        if self.connection != nil && self.connection.isConnected() {
            if let u = self.user {
                let message = P7Message(withName: "wired.user.get_info", spec: self.connection.spec)
                message.addParameter(field: "wired.user.id", value: u.userID)
                
                self.connection.addDelegate(self)
                
                _ = self.connection.send(message: message)
            }
        }
    }
    
    
    // MARK: -
    
    func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
        if self.connection == connection {
            if message.name == "wired.user.info" {                
                connection.removeDelegate(self)
                
                self.nickLabel.stringValue = self.user!.nick
                self.nickLabel.textColor = NSColor.color(forEnum: self.user!.color)
                self.statusLabel.stringValue = self.user!.status
                
                if let base64ImageString = self.user!.icon?.base64EncodedData() {
                    if let data = Data(base64Encoded: base64ImageString, options: .ignoreUnknownCharacters) {
                        self.iconView.image = NSImage(data: data)
                    }
                }
                
                if let string = message.string(forField: "wired.user.login") {
                    self.loginLabel.stringValue = string
                }
                
                if let string = message.string(forField: "wired.user.ip") {
                    self.ipLabel.stringValue = string
                }
                
                if let string = message.string(forField: "wired.user.host") {
                    self.hostnameLabel.stringValue = string
                }
                
                if  let applicationName = message.string(forField: "wired.info.application.name"),
                    let applicationVersion = message.string(forField: "wired.info.application.version"),
                    let applicationBuild = message.string(forField: "wired.info.application.build"),
                    let osName = message.string(forField: "wired.info.os.name"),
                    let osVersion = message.string(forField: "wired.info.os.version"),
                    let arch = message.string(forField: "wired.info.arch") {
                    self.versionlabel.stringValue = "\(applicationName) \(applicationVersion) (\(applicationBuild)) on \(osName) \(osVersion) (\(arch))"
                }
                
                if  let cipherName = message.string(forField: "wired.user.cipher.name"),
                    let cipherBits = message.uint32(forField: "wired.user.cipher.bits") {
                    self.cipherLabel.stringValue = "\(cipherName)/\(cipherBits) bits"
                }
                
                if let date = message.date(forField: "wired.user.login_time") {
                    self.connectedLabel.stringValue = AppDelegate.timeIntervalFormatter.string(from: date, to: Date()) ?? ""
                }
                
                if let date = message.date(forField: "wired.user.idle_time") {
                    self.idleLabel.stringValue = AppDelegate.timeIntervalFormatter.string(from: date, to: Date()) ?? ""
                }
            }
        }
    }
    
    func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}
