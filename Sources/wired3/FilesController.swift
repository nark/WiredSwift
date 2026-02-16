//
//  FilesController.swift
//  wired3
//
//  Created by Rafael Warnault on 25/03/2021.
//

import Foundation
import WiredSwift

public class FilesController {
    public var rootPath:String
    private let subscriptionsLock = NSLock()
    private var subscribedRealPathsByClient:[UInt32:Set<String>] = [:]
    private var subscribedVirtualPathsByClient:[UInt32:[String:String]] = [:]
    
    
    public init(rootPath:String) {
        self.rootPath = rootPath
        
        self.initFilesSystem()
    }
    
    
    // MARK: -
    public func real(path:String) -> String {
        return self.rootPath.stringByAppendingPathComponent(path: path)
    }
    
    public func virtual(path:String) -> String {
        return "/" + path.deletingPrefix(self.rootPath)
    }
    
    public func listDirectory(client:Client, message:P7Message) {
        var recursive = false
        
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: self.real(path: path)) {
            if !client.user!.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            // user privileges
            if !client.user!.hasPrivilege(name: "wired.account.file.list_files") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        if let r = message.bool(forField: "wired.file.recursive") {
            recursive = r
        }
        
        self.replyList(path, recursive, client, message)
    }
    
    public func createDirectory(client:Client, message:P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        if let privilege = FilePrivilege(path: self.real(path: path)) {
            if !client.user!.hasPermission(toRead: privilege) || !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            if !client.user!.hasPrivilege(name: "wired.account.file.create_directory") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        guard let type = message.enumeration(forField: "wired.file.type"),
              let fileType = File.FileType(rawValue: type) else {
            return
        }
        
        if createPath(path, type: fileType, user: client.user!, message: message) {
            self.notifyDirectoryChanged(path: path.stringByDeletingLastPathComponent)
            App.serverController.replyOK(client: client, message: message)
        }
    }
    
    
    
    
    public func delete(client:Client, message:P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        // file privileges
        if let privilege = FilePrivilege(path: self.real(path: path)) {
            if !client.user!.hasPermission(toRead: privilege) || !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            // user privileges
            if !client.user!.hasPrivilege(name: "wired.account.file.delete_files") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        if self.delete(path: path, client: client, message: message) {
            App.serverController.replyOK(client: client, message: message)
        }
    }
    
    
    
    private func delete(path:String, client:Client, message:P7Message) -> Bool {
        let realPath = self.real(path: path)
        let parentPath = path.stringByDeletingLastPathComponent
        let isDirectory = File.FileType.type(path: realPath) != .file
        
        do {
            try FileManager.default.removeItem(atPath: realPath)
            
            App.indexController.removeIndex(forPath: realPath)
        } catch let error {
            Logger.error("Cannot delete file \(realPath) \(error)")
            
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            
            return false
        }

        self.notifyDirectoryChanged(path: parentPath)

        if isDirectory {
            self.notifyDirectoryDeleted(path: path)
        }
        
        return true
    }
    
    
    private func replyList(_ path:String, _ recursive:Bool, _ client:Client, _ message:P7Message) {
        var realPath:String = path
        var isDir: ObjCBool = false
        
        DispatchQueue.global(qos: .default).async {
            if path == "/" {
                realPath = self.rootPath
            }
            else {
                realPath = self.real(path: path)
            }
                                     
            if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDir) {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }
            
            var files:[String]? = []
            
            do {
                files = try FileManager.default.contentsOfDirectory(atPath: realPath)
            } catch {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }
    
                                    
            for file in files! {
                // skip invisible file
                if file.hasPrefix(".") {
                    continue
                }
                
                let virtualPath = path.stringByAppendingPathComponent(path: file)
                let realFilePath = realPath.stringByAppendingPathComponent(path: file)
                
                let type = WiredSwift.File.FileType.type(path: realFilePath)
                let privileges = FilePrivilege(path: realFilePath)

                var datasize:UInt64 = 0
                var rsrcsize:UInt64 = 0
                var directorycount:UInt32 = 0

                var readable = false
                var writable = false

                if type == .dropbox {
                    if privileges != nil {
                        readable = client.user!.hasPermission(toRead: privileges!)
                        writable = client.user!.hasPermission(toWrite: privileges!)
                    }
                }

                // TODO: read comment

                switch(type) {
                case .file:
                  datasize = File.size(path: realFilePath)
                  rsrcsize = 0
                  directorycount = 0
                case .dropbox:
                  datasize = 0
                  rsrcsize = 0
                  directorycount = readable ? File.count(path: realFilePath) : 0
                case .directory:
                  datasize = 0
                  rsrcsize = 0
                  directorycount = File.count(path: realFilePath)
                case .uploads:
                  datasize = 0
                  rsrcsize = 0
                  directorycount = File.count(path: realFilePath)
                case .none:
                  datasize = 0
                  rsrcsize = 0
                  directorycount = 0
                }
                
                // TODO: read label
                // TODO: resolve alias or link if needed
                                                    
                let reply = P7Message(withName: "wired.file.file_list", spec: message.spec)
                reply.addParameter(field: "wired.file.path", value: virtualPath)

                if let type = File.FileType.type(path: realFilePath) {
                    if type == .file {
                        reply.addParameter(field: "wired.file.data_size", value: datasize)
                        reply.addParameter(field: "wired.file.rsrc_size", value: rsrcsize)
                    } else if type == .directory || type == .uploads || type == .dropbox {
                        reply.addParameter(field: "wired.file.directory_count", value: directorycount)
                    }
                    
                    reply.addParameter(field: "wired.file.type", value: type.rawValue)
                }
                                
                reply.addParameter(field: "wired.file.link", value: false)
                reply.addParameter(field: "wired.file.executable", value: false)
                reply.addParameter(field: "wired.file.label", value: File.FileLabel.LABEL_NONE.rawValue)
                reply.addParameter(field: "wired.file.volume", value: UInt32(0))
                
                if type == .dropbox {
//                    if let p = privileges {
//                        reply.addParameter(field: "wired.file.owner", value: p.owner)
//                        reply.addParameter(field: "wired.file.owner.read", value: p.mode?.contains(File.FilePermissions.ownerRead))
//                        reply.addParameter(field: "wired.file.owner.write", value: p.mode?.contains(File.FilePermissions.ownerWrite))
//
//                        reply.addParameter(field: "wired.file.group", value: p.owner)
//                        reply.addParameter(field: "wired.file.group.read", value: p.mode?.contains(File.FilePermissions.groupRead))
//                        reply.addParameter(field: "wired.file.group.write", value: p.mode?.contains(File.FilePermissions.groupWrite))
//
//                        reply.addParameter(field: "wired.file.everyone.read", value: p.mode?.contains(File.FilePermissions.everyoneRead))
//                        reply.addParameter(field: "wired.file.everyone.write", value: p.mode?.contains(File.FilePermissions.everyoneWrite))
//                    }
                    reply.addParameter(field: "wired.file.readable", value: readable)
                    reply.addParameter(field: "wired.file.writable", value: writable)
                }
                
                App.serverController.reply(client: client, reply: reply, message: message)
            }
            
            let reply = P7Message(withName: "wired.file.file_list.done", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: path)
            reply.addParameter(field: "wired.file.available", value: UInt64(1))
            App.serverController.reply(client: client, reply: reply, message: message)
        }
    }
    
    
    // MARK: -
    private func initFilesSystem() {
        if !FileManager.default.fileExists(atPath: rootPath) {
            try? FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
            
            let uploads = rootPath.stringByAppendingPathComponent(path: "Uploads")
            let dropboxes = rootPath.stringByAppendingPathComponent(path: "Drop Boxes")
            let uploadsWiredDir = uploads.stringByAppendingPathComponent(path: ".wired")
            let dropboxesWiredDir = dropboxes.stringByAppendingPathComponent(path: ".wired")
            
            try? FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.createDirectory(atPath: uploadsWiredDir, withIntermediateDirectories: true, attributes: nil)
            try? FileManager.default.createDirectory(atPath: dropboxesWiredDir, withIntermediateDirectories: true, attributes: nil)
            
            _ = File.FileType.set(type: .uploads, path: uploads)
            _ = File.FileType.set(type: .dropbox, path: dropboxes)
            
            let privilege = FilePrivilege(owner: "admin", group: "", mode: .ownerRead)
            _ = FilePrivilege.set(privileges: privilege, path: dropboxes)
        }
    }
    
    private func createPath(_ path: String, type: File.FileType, user: User, message: P7Message) -> Bool {
        let realPath = self.real(path: path)
        
        do {
            try FileManager.default.createDirectory(atPath: realPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0777])
        } catch {
            return false
        }
        
        return true
    }


    // MARK: - Directory subscriptions
    public func subscribeDirectory(client: Client, message: P7Message) {
        if !client.user!.hasPrivilege(name: "wired.account.file.list_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let virtualPath = message.string(forField: "wired.file.path") else {
            return
        }

        if !File.isValid(path: virtualPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedVirtualPath = NSString(string: virtualPath).standardizingPath
        let realPath = URL(fileURLWithPath: self.real(path: normalizedVirtualPath)).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        subscriptionsLock.lock()
        if subscribedRealPathsByClient[client.userID] == nil {
            subscribedRealPathsByClient[client.userID] = Set<String>()
        }
        subscribedRealPathsByClient[client.userID]?.insert(realPath)

        if subscribedVirtualPathsByClient[client.userID] == nil {
            subscribedVirtualPathsByClient[client.userID] = [:]
        }
        subscribedVirtualPathsByClient[client.userID]?[realPath] = normalizedVirtualPath
        subscriptionsLock.unlock()

        App.serverController.replyOK(client: client, message: message)
    }

    public func unsubscribeDirectory(client: Client, message: P7Message) {
        if !client.user!.hasPrivilege(name: "wired.account.file.list_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let virtualPath = message.string(forField: "wired.file.path") else {
            return
        }

        if !File.isValid(path: virtualPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedVirtualPath = NSString(string: virtualPath).standardizingPath
        let realPath = URL(fileURLWithPath: self.real(path: normalizedVirtualPath)).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        subscriptionsLock.lock()
        let isSubscribed = subscribedRealPathsByClient[client.userID]?.contains(realPath) ?? false

        if isSubscribed {
            subscribedRealPathsByClient[client.userID]?.remove(realPath)
            subscribedVirtualPathsByClient[client.userID]?[realPath] = nil
        }
        subscriptionsLock.unlock()

        if !isSubscribed {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
    }

    public func unsubscribeAll(client: Client) {
        subscriptionsLock.lock()
        subscribedRealPathsByClient[client.userID] = nil
        subscribedVirtualPathsByClient[client.userID] = nil
        subscriptionsLock.unlock()
    }

    public func notifyDirectoryChanged(path: String) {
        notify(path: path, messageName: "wired.file.directory_changed", removeSubscriptionAfterNotify: false)
    }

    public func notifyDirectoryDeleted(path: String) {
        notify(path: path, messageName: "wired.file.directory_deleted", removeSubscriptionAfterNotify: true)
    }

    private func notify(path: String, messageName: String, removeSubscriptionAfterNotify: Bool) {
        let realPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path
        var deliveries:[(Client, String)] = []

        subscriptionsLock.lock()
        for (userID, paths) in subscribedRealPathsByClient where paths.contains(realPath) {
            if let virtualPath = subscribedVirtualPathsByClient[userID]?[realPath],
               let client = App.clientsController.user(withID: userID),
               client.state == .LOGGED_IN {
                deliveries.append((client, virtualPath))
            }
        }

        if removeSubscriptionAfterNotify {
            for userID in subscribedRealPathsByClient.keys {
                subscribedRealPathsByClient[userID]?.remove(realPath)
                subscribedVirtualPathsByClient[userID]?[realPath] = nil
            }
        }
        subscriptionsLock.unlock()

        for (client, virtualPath) in deliveries {
            let reply = P7Message(withName: messageName, spec: client.socket.spec)
            reply.addParameter(field: "wired.file.path", value: virtualPath)
            _ = App.serverController.send(message: reply, client: client)
        }
    }
}
