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
    private let subscriptionsQueue = DispatchQueue(label: "wired3.files.subscriptions")
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
        
        let normalizedPath = NSString(string: path).standardizingPath

        // file privileges (dropbox inherited in path)
        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
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
        
        self.replyList(normalizedPath, recursive, client, message)
    }

    public func getInfo(client: Client, message: P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = URL(fileURLWithPath: self.real(path: normalizedPath)).resolvingSymlinksInPath().path

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard client.user!.hasPrivilege(name: "wired.account.file.get_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !client.user!.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        guard let type = File.FileType.type(path: realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let reply = P7Message(withName: "wired.file.info", spec: message.spec)
        reply.addParameter(field: "wired.file.path", value: normalizedPath)
        reply.addParameter(field: "wired.file.type", value: type.rawValue)

        let attributes = try? FileManager.default.attributesOfItem(atPath: realPath)
        if let creationDate = attributes?[.creationDate] as? Date {
            reply.addParameter(field: "wired.file.creation_time", value: creationDate)
        } else {
            reply.addParameter(field: "wired.file.creation_time", value: Date(timeIntervalSince1970: 0))
        }
        if let modificationDate = attributes?[.modificationDate] as? Date {
            reply.addParameter(field: "wired.file.modification_time", value: modificationDate)
        } else {
            reply.addParameter(field: "wired.file.modification_time", value: Date(timeIntervalSince1970: 0))
        }

        reply.addParameter(field: "wired.file.link", value: false)
        reply.addParameter(field: "wired.file.executable", value: false)
        reply.addParameter(field: "wired.file.label", value: File.FileLabel.LABEL_NONE.rawValue)
        reply.addParameter(field: "wired.file.volume", value: UInt32(0))
        reply.addParameter(field: "wired.file.comment", value: "")

        if type == .file {
            reply.addParameter(field: "wired.file.data_size", value: File.size(path: realPath))
            reply.addParameter(field: "wired.file.rsrc_size", value: UInt64(0))
        } else {
            reply.addParameter(field: "wired.file.directory_count", value: File.count(path: realPath))
        }

        if type == .dropbox, let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let mode = privilege.mode ?? []
            reply.addParameter(field: "wired.file.owner", value: privilege.owner ?? "")
            reply.addParameter(field: "wired.file.group", value: privilege.group ?? "")
            reply.addParameter(field: "wired.file.owner.read", value: mode.contains(File.FilePermissions.ownerRead))
            reply.addParameter(field: "wired.file.owner.write", value: mode.contains(File.FilePermissions.ownerWrite))
            reply.addParameter(field: "wired.file.group.read", value: mode.contains(File.FilePermissions.groupRead))
            reply.addParameter(field: "wired.file.group.write", value: mode.contains(File.FilePermissions.groupWrite))
            reply.addParameter(field: "wired.file.everyone.read", value: mode.contains(File.FilePermissions.everyoneRead))
            reply.addParameter(field: "wired.file.everyone.write", value: mode.contains(File.FilePermissions.everyoneWrite))
            reply.addParameter(field: "wired.file.readable", value: client.user!.hasPermission(toRead: privilege))
            reply.addParameter(field: "wired.file.writable", value: client.user!.hasPermission(toWrite: privilege))
        }

        App.serverController.reply(client: client, reply: reply, message: message)
    }
    
    public func createDirectory(client:Client, message:P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = self.real(path: normalizedPath)

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            if !client.user!.hasPrivilege(name: "wired.account.file.create_directories") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        let fileType: File.FileType = {
            guard let type = message.enumeration(forField: "wired.file.type"),
                  let fileType = File.FileType(rawValue: type),
                  fileType != .file else {
                return .directory
            }
            return fileType
        }()

        if FileManager.default.fileExists(atPath: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
            return
        }

        if createPath(normalizedPath, type: fileType, user: client.user!, message: message) {
            if fileType == .dropbox, client.user!.hasPrivilege(name: "wired.account.file.set_permissions") {
                let privileges = privilegesFromMessage(message)

                if !FilePrivilege.set(privileges: privileges, path: realPath) {
                    try? FileManager.default.removeItem(atPath: realPath)
                    App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                    return
                }
            }

            App.indexController.addIndex(forPath: realPath)
            self.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
            App.serverController.replyOK(client: client, message: message)
        } else if (path as NSString).lastPathComponent.isEmpty {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
        } else if FileManager.default.fileExists(atPath: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    public func setType(client: Client, message: P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let privileges = dropBoxPrivileges(forVirtualPath: normalizedPath)

        if let privileges {
            if !client.user!.hasPermission(toWrite: privileges) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !client.user!.hasPrivilege(name: "wired.account.file.set_type") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let typeValue = message.enumeration(forField: "wired.file.type"),
              let fileType = File.FileType(rawValue: typeValue),
              fileType != .file else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if setType(path: normalizedPath, type: fileType, client: client, message: message) {
            // Keep parent listing and directory subscriptions in sync with type updates.
            self.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
            self.notifyDirectoryChanged(path: normalizedPath)
            App.serverController.replyOK(client: client, message: message)
        }
    }

    public func setPermissions(client: Client, message: P7Message) {
        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedPath = NSString(string: path).standardizingPath
        let realPath = URL(fileURLWithPath: self.real(path: normalizedPath)).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privileges = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !client.user!.hasPermission(toWrite: privileges) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !client.user!.hasPrivilege(name: "wired.account.file.set_permissions") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let owner = message.string(forField: "wired.file.owner"),
              let group = message.string(forField: "wired.file.group"),
              let ownerRead = message.bool(forField: "wired.file.owner.read"),
              let ownerWrite = message.bool(forField: "wired.file.owner.write"),
              let groupRead = message.bool(forField: "wired.file.group.read"),
              let groupWrite = message.bool(forField: "wired.file.group.write"),
              let everyoneRead = message.bool(forField: "wired.file.everyone.read"),
              let everyoneWrite = message.bool(forField: "wired.file.everyone.write") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        var mode: File.FilePermissions = []
        if ownerRead { mode.insert(.ownerRead) }
        if ownerWrite { mode.insert(.ownerWrite) }
        if groupRead { mode.insert(.groupRead) }
        if groupWrite { mode.insert(.groupWrite) }
        if everyoneRead { mode.insert(.everyoneRead) }
        if everyoneWrite { mode.insert(.everyoneWrite) }

        let wiredMetaPath = realPath.stringByAppendingPathComponent(path: ".wired")
        do {
            try FileManager.default.createDirectory(atPath: wiredMetaPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let newPrivileges = FilePrivilege(owner: owner, group: group, mode: mode)
        if !FilePrivilege.set(privileges: newPrivileges, path: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
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
        
        let normalizedPath = NSString(string: path).standardizingPath

        // file privileges
        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
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
        
        if self.delete(path: normalizedPath, client: client, message: message) {
            App.serverController.replyOK(client: client, message: message)
        }
    }

    public func move(client: Client, message: P7Message) {
        guard let fromPath = message.string(forField: "wired.file.path"),
              let toPath = message.string(forField: "wired.file.new_path") else {
            return
        }

        if !File.isValid(path: fromPath) || !File.isValid(path: toPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let normalizedFromPath = NSString(string: fromPath).standardizingPath
        let normalizedToPath = NSString(string: toPath).standardizingPath
        let fromDirectory = normalizedFromPath.stringByDeletingLastPathComponent
        let toDirectory = normalizedToPath.stringByDeletingLastPathComponent
        let isRenameOnly = fromDirectory == toDirectory

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedFromPath) {
            if !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !client.user!.hasPrivilege(name: "wired.account.file.move_files") &&
                    (!client.user!.hasPrivilege(name: "wired.account.file.rename_files") || !isRenameOnly) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedToPath) {
            if !client.user!.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !client.user!.hasPrivilege(name: "wired.account.file.move_files") &&
                    (!client.user!.hasPrivilege(name: "wired.account.file.rename_files") || !isRenameOnly) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if move(from: normalizedFromPath, to: normalizedToPath, client: client, message: message) {
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

    private func move(from sourcePath: String, to destinationPath: String, client: Client, message: P7Message) -> Bool {
        let sourceRealPath = URL(fileURLWithPath: self.real(path: sourcePath)).resolvingSymlinksInPath().path
        let destinationRealPath = URL(fileURLWithPath: self.real(path: destinationPath)).resolvingSymlinksInPath().path
        let sourceParentPath = sourcePath.stringByDeletingLastPathComponent
        let destinationParentPath = destinationPath.stringByDeletingLastPathComponent

        do {
            try FileManager.default.moveItem(atPath: sourceRealPath, toPath: destinationRealPath)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        App.indexController.removeIndex(forPath: sourceRealPath)
        App.indexController.addIndex(forPath: destinationRealPath)
        self.notifyDirectoryChanged(path: sourceParentPath)
        if sourceParentPath != destinationParentPath {
            self.notifyDirectoryChanged(path: destinationParentPath)
        }

        return true
    }
    
    
    private func replyList(_ path:String, _ recursive:Bool, _ client:Client, _ message:P7Message) {
        DispatchQueue.global(qos: .default).async {
            let realPath: String = (path == "/") ? self.rootPath : self.real(path: path)
            var isDir: ObjCBool = false

            if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDir) || !isDir.boolValue {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }

            var visited: Set<String> = []
            if !self.replyListRecursive(realPath: realPath, virtualPath: path, recursive: recursive, visited: &visited, client: client, message: message) {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }
            
            let reply = P7Message(withName: "wired.file.file_list.done", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: path)
            reply.addParameter(field: "wired.file.available", value: UInt64(1))
            App.serverController.reply(client: client, reply: reply, message: message)
        }
    }

    private func replyListRecursive(
        realPath: String,
        virtualPath: String,
        recursive: Bool,
        visited: inout Set<String>,
        client: Client,
        message: P7Message
    ) -> Bool {
        let fm = FileManager.default
        let canonicalPath = URL(fileURLWithPath: realPath).resolvingSymlinksInPath().standardized.path

        if visited.contains(canonicalPath) {
            return true
        }
        visited.insert(canonicalPath)

        let files: [String]
        do {
            files = try fm.contentsOfDirectory(atPath: realPath).sorted()
        } catch {
            return false
        }

        for file in files {
            // skip invisible file
            if file.hasPrefix(".") {
                continue
            }

            let childVirtualPath = virtualPath.stringByAppendingPathComponent(path: file)
            let childRealPath = realPath.stringByAppendingPathComponent(path: file)

            let type = WiredSwift.File.FileType.type(path: childRealPath)

            var datasize: UInt64 = 0
            var rsrcsize: UInt64 = 0
            var directorycount: UInt32 = 0

            var readable = false
            var writable = false

            if type == .dropbox, let privileges = dropBoxPrivileges(forVirtualPath: childVirtualPath) {
                readable = client.user!.hasPermission(toRead: privileges)
                writable = client.user!.hasPermission(toWrite: privileges)
            }

            // TODO: read comment
            switch type {
            case .file:
                datasize = File.size(path: childRealPath)
                rsrcsize = 0
                directorycount = 0
            case .dropbox:
                datasize = 0
                rsrcsize = 0
                directorycount = readable ? File.count(path: childRealPath) : 0
            case .directory:
                datasize = 0
                rsrcsize = 0
                directorycount = File.count(path: childRealPath)
            case .uploads:
                datasize = 0
                rsrcsize = 0
                directorycount = File.count(path: childRealPath)
            case .none:
                datasize = 0
                rsrcsize = 0
                directorycount = 0
            }

            // TODO: read label
            // TODO: resolve alias or link if needed
            let reply = P7Message(withName: "wired.file.file_list", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: childVirtualPath)

            if let type = File.FileType.type(path: childRealPath) {
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
                reply.addParameter(field: "wired.file.readable", value: readable)
                reply.addParameter(field: "wired.file.writable", value: writable)
            }

            App.serverController.reply(client: client, reply: reply, message: message)

            if recursive && (type == .directory || type == .uploads || type == .dropbox) {
                if !self.replyListRecursive(
                    realPath: childRealPath,
                    virtualPath: childVirtualPath,
                    recursive: true,
                    visited: &visited,
                    client: client,
                    message: message
                ) {
                    return false
                }
            }
        }

        return true
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
            try FileManager.default.createDirectory(atPath: realPath, withIntermediateDirectories: false, attributes: [FileAttributeKey.posixPermissions: 0o777])
        } catch {
            return false
        }

        if !File.FileType.set(type: type, path: realPath) {
            return false
        }
        
        return true
    }

    private func privilegesFromMessage(_ message: P7Message) -> FilePrivilege {
        let owner = message.string(forField: "wired.file.owner") ?? ""
        let group = message.string(forField: "wired.file.group") ?? ""

        var mode: File.FilePermissions = []
        if message.bool(forField: "wired.file.owner.read") ?? false { mode.insert(.ownerRead) }
        if message.bool(forField: "wired.file.owner.write") ?? false { mode.insert(.ownerWrite) }
        if message.bool(forField: "wired.file.group.read") ?? false { mode.insert(.groupRead) }
        if message.bool(forField: "wired.file.group.write") ?? false { mode.insert(.groupWrite) }
        if message.bool(forField: "wired.file.everyone.read") ?? false { mode.insert(.everyoneRead) }
        if message.bool(forField: "wired.file.everyone.write") ?? false { mode.insert(.everyoneWrite) }

        return FilePrivilege(owner: owner, group: group, mode: mode)
    }

    private func setType(path: String, type: File.FileType, client: Client, message: P7Message) -> Bool {
        let canonicalPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }

        if !File.FileType.set(type: type, path: canonicalPath) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        return true
    }

    func dropBoxPrivileges(forVirtualPath path: String) -> FilePrivilege? {
        guard let dropBoxPath = dropBoxRealPath(inVirtualPath: path) else {
            return nil
        }

        if let privileges = FilePrivilege(path: dropBoxPath) {
            return privileges
        }

        // Same default as legacy wired: writable by everyone when no permissions file exists.
        return FilePrivilege(owner: "", group: "", mode: .everyoneWrite)
    }

    private func dropBoxRealPath(inVirtualPath path: String) -> String? {
        let normalized = NSString(string: path).standardizingPath
        let components = normalized.split(separator: "/").map(String.init)

        var current = URL(fileURLWithPath: self.real(path: "/")).resolvingSymlinksInPath().path

        for component in components {
            if component.isEmpty {
                continue
            }

            current = current.stringByAppendingPathComponent(path: component)
            if File.FileType.type(path: current) == .dropbox {
                return current
            }
        }

        return nil
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

        subscriptionsQueue.sync {
            var realPaths = subscribedRealPathsByClient[client.userID] ?? Set<String>()
            realPaths.insert(realPath)
            subscribedRealPathsByClient[client.userID] = realPaths

            var virtualPaths = subscribedVirtualPathsByClient[client.userID] ?? [:]
            virtualPaths[realPath] = normalizedVirtualPath
            subscribedVirtualPathsByClient[client.userID] = virtualPaths
        }

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

        let isSubscribed = subscriptionsQueue.sync { () -> Bool in
            let subscribed = subscribedRealPathsByClient[client.userID]?.contains(realPath) ?? false
            if subscribed {
                subscribedRealPathsByClient[client.userID]?.remove(realPath)
                subscribedVirtualPathsByClient[client.userID]?[realPath] = nil
            }
            return subscribed
        }

        if !isSubscribed {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
    }

    public func unsubscribeAll(client: Client) {
        subscriptionsQueue.sync {
            subscribedRealPathsByClient.removeValue(forKey: client.userID)
            subscribedVirtualPathsByClient.removeValue(forKey: client.userID)
        }
    }

    public func notifyDirectoryChanged(path: String) {
        notify(path: path, messageName: "wired.file.directory_changed", removeSubscriptionAfterNotify: false)
    }

    public func notifyDirectoryDeleted(path: String) {
        notify(path: path, messageName: "wired.file.directory_deleted", removeSubscriptionAfterNotify: true)
    }

    private func notify(path: String, messageName: String, removeSubscriptionAfterNotify: Bool) {
        let realPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path
        let targets: [(UInt32, String)] = subscriptionsQueue.sync {
            var snapshot: [(UInt32, String)] = []
            for (userID, paths) in subscribedRealPathsByClient where paths.contains(realPath) {
                if let virtualPath = subscribedVirtualPathsByClient[userID]?[realPath] {
                    snapshot.append((userID, virtualPath))
                }
            }

            if removeSubscriptionAfterNotify {
                let userIDs = Array(subscribedRealPathsByClient.keys)
                for userID in userIDs {
                    subscribedRealPathsByClient[userID]?.remove(realPath)
                    subscribedVirtualPathsByClient[userID]?[realPath] = nil
                    
                    if subscribedRealPathsByClient[userID]?.isEmpty == true {
                        subscribedRealPathsByClient.removeValue(forKey: userID)
                    }
                    if subscribedVirtualPathsByClient[userID]?.isEmpty == true {
                        subscribedVirtualPathsByClient.removeValue(forKey: userID)
                    }
                }
            }
            return snapshot
        }

        for (userID, virtualPath) in targets {
            guard let client = App.clientsController.user(withID: userID),
                  client.state == .LOGGED_IN else {
                continue
            }
            let reply = P7Message(withName: messageName, spec: client.socket.spec)
            reply.addParameter(field: "wired.file.path", value: virtualPath)
            _ = App.serverController.send(message: reply, client: client)
        }
    }
}
