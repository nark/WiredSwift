//
//  File.swift
//  WiredSwift
//
//  Created by Rafael Warnault on 19/02/2020.
//  Copyright © 2020 Read-Write. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let didLoadDirectory = Notification.Name("didLoadDirectory")
}


public class File: ConnectionObject, ConnectionDelegate {
    public enum FileType: Int {
        case file = 0
        case directory = 1
        case uploads = 2
        case dropbox = 3
    }
    
    public var children: [File] = []
    public var type: FileType!
    public var path: String!
    public var name: String!
    public var directoryCount:Int = 0
    
    public var dataSize:UInt64 = 0
    public var rsrcSize:UInt64 = 0

    public var uploadDataSize:UInt64 = 0
    public var uploadRsrcSize:UInt64 = 0
    public var dataTransferred:UInt64 = 0
    public var rsrcTransferred:UInt64 = 0
    
    init(_ path: String, connection: ServerConnection) {
        super.init(connection)
                
        self.path = path
        self.name = (self.path as NSString).lastPathComponent
        self.type = .directory
    }

    
    init(_ message: P7Message, connection: ServerConnection) {
        super.init(connection)
        
        if let p = message.string(forField: "wired.file.path") {
            self.path = p
            self.name = (self.path as NSString).lastPathComponent
        }
        if let t = message.enumeration(forField: "wired.file.type") {
            self.type = File.FileType(rawValue: Int(t))
        }
        if let s = message.uint64(forField: "wired.file.data_size") {
            self.dataSize = s
        }
        if let s = message.uint64(forField: "wired.file.rsrc_size") {
            self.rsrcSize = s
        }
        if let s = message.uint32(forField: "wired.file.directory_count") {
            self.directoryCount = Int(s)
        }
    }

    
    
    public func load(reload:Bool = false) {
        if self.type != .file && (self.children.count == 0 || reload == true) {
            if reload == true {
                children = []
            }
            
            connection.addDelegate(self)
            
            let message = P7Message(withName: "wired.file.list_directory", spec: self.connection.spec)
            message.addParameter(field: "wired.file.path", value: self.path)
            
            let _ = self.connection.send(message: message)
        }
    }
    
    
    public func icon() -> NSImage? {
        if self.type == .file {
            return NSWorkspace.shared.icon(forFileType: self.fileType())
        }
        return NSWorkspace.shared.icon(forFileType: NSFileTypeForHFSTypeCode(OSType(kGenericFolderIcon)))
    }
    
    
    public func fileType() -> String {
        if self.type == .file {
            let ext = (self.path as NSString).pathExtension as CFString
            if let uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext, nil) {
                if let r = UTTypeCopyDescription(uti.takeRetainedValue())?.takeRetainedValue() as String? {
                    return r
                }
            }
        }
        else if self.type == .directory {
            return "Directory"
        }
        else if self.type == .uploads {
            return "Uploads"
        }
        else if self.type == .dropbox {
            return "Dropbox"
        }
        
        return "Unknow"
    }
    
    
    public func isRoot() -> Bool {
        return self.path == "/"
    }
    
    
    
    public func isFolder() -> Bool {
        return self.type != .file
    }
    
    
    public func parentPath() -> String? {
        if self.isRoot() {
            return nil
        }
        
        let comps = self.path.split(separator: "/")
        
        if comps.count > 1 {
            return (self.path as NSString).deletingLastPathComponent
        }
        
        return "/"
    }
    
    
    
    public func connectionDidConnect(connection: Connection) {
        
    }
    
    public func connectionDidFailToConnect(connection: Connection, error: Error) {
        
    }
    
    public func connectionDisconnected(connection: Connection, error: Error?) {
        
    }
    
    public func connectionDidReceiveMessage(connection: Connection, message: P7Message) {
     
        if message.name == "wired.file.file_list" {
            let child = File(message, connection: self.connection)
            
            if child.parentPath() == self.path {
                children.append(File(message, connection: self.connection))
            }
        }
        else if message.name == "wired.file.file_list.done" {
            // send reload notification
            NotificationCenter.default.post(name: .didLoadDirectory, object: self)
            
            connection.removeDelegate(self)
        }
    }
    
    public func connectionDidReceiveError(connection: Connection, message: P7Message) {
        
    }
}
