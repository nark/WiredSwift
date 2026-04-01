//
//  FilesController.swift
//  wired3
//
//  Created by Rafael Warnault on 25/03/2021.
//
// swiftlint:disable type_body_length
// TODO: Split FilesController into smaller focused types
import Foundation
import WiredSwift

public class FilesController {
    public var rootPath: String
    private let subscriptionsQueue = DispatchQueue(label: "wired3.files.subscriptions")
    private var subscribedRealPathsByClient: [UInt32: Set<String>] = [:]
    private var subscribedVirtualPathsByClient: [UInt32: [String: String]] = [:]

    public init(rootPath: String) {
        self.rootPath = rootPath

        self.initFilesSystem()
    }

    private func isManagedDirectoryType(_ type: File.FileType?) -> Bool {
        guard let type else { return false }
        return type == .dropbox || type == .sync
    }

    private func defaultSyncPolicy() -> SyncPolicy {
        SyncPolicy()
    }

    func managedAccess(forVirtualPath path: String, user: User, privilege: FilePrivilege) -> (readable: Bool, writable: Bool) {
        let allowBypass = syncRealPath(inVirtualPath: path) == nil
        return (
            readable: user.hasPermission(toRead: privilege, allowBypass: allowBypass),
            writable: user.hasPermission(toWrite: privilege, allowBypass: allowBypass)
        )
    }

    func effectiveSyncMode(
        forVirtualPath path: String,
        user: User,
        privilege: FilePrivilege? = nil,
        policy: SyncPolicy? = nil
    ) -> SyncPolicy.Mode? {
        guard let resolvedPolicy = policy ?? syncPolicy(forVirtualPath: path) else {
            return nil
        }

        let resolvedPrivilege = privilege ?? dropBoxPrivileges(forVirtualPath: path)

        if let owner = resolvedPrivilege?.owner,
           !owner.isEmpty,
           user.username == owner {
            return resolvedPolicy.userMode
        }

        if let group = resolvedPrivilege?.group,
           !group.isEmpty,
           user.hasGroup(string: group) {
            return resolvedPolicy.groupMode
        }

        return resolvedPolicy.everyoneMode
    }

    func mayInspectSyncRemoteMetadata(
        forVirtualPath path: String,
        user: User,
        privilege: FilePrivilege? = nil,
        policy: SyncPolicy? = nil
    ) -> Bool {
        guard user.hasPrivilege(name: "wired.account.file.sync.delete_remote") else {
            return false
        }

        guard let mode = effectiveSyncMode(forVirtualPath: path, user: user, privilege: privilege, policy: policy) else {
            return false
        }

        return mode == .clientToServer || mode == .bidirectional
    }

    private func canBrowseManagedDirectory(
        atVirtualPath path: String,
        user: User,
        privilege: FilePrivilege,
        type: File.FileType?
    ) -> Bool {
        let access = managedAccess(forVirtualPath: path, user: user, privilege: privilege)
        if access.readable {
            return true
        }
        if type == .sync {
            return mayInspectSyncRemoteMetadata(forVirtualPath: path, user: user, privilege: privilege)
        }
        return false
    }

    private func appendSyncPolicyInfo(
        to reply: P7Message,
        virtualPath: String,
        user: User,
        privilege: FilePrivilege
    ) {
        let policy = syncPolicy(forVirtualPath: virtualPath) ?? defaultSyncPolicy()
        reply.addParameter(field: "wired.file.sync.user_mode", value: policy.userMode.rawValue)
        reply.addParameter(field: "wired.file.sync.group_mode", value: policy.groupMode.rawValue)
        reply.addParameter(field: "wired.file.sync.everyone_mode", value: policy.everyoneMode.rawValue)
        reply.addParameter(
            field: "wired.file.sync.mode_effective",
            value: effectiveSyncMode(forVirtualPath: virtualPath, user: user, privilege: privilege, policy: policy)?.rawValue ?? SyncPolicy.Mode.disabled.rawValue
        )
    }

    private func isDirectoryType(_ type: File.FileType?) -> Bool {
        guard let type else { return false }
        return type == .directory || type == .uploads || type == .dropbox || type == .sync
    }

    // MARK: -
    public func real(path: String) -> String {
        // Keep path joins stable across platforms (Linux Foundation can keep
        // duplicate separators when appending absolute components).
        let relativePath = path.deletingPrefix("/")
        return URL(fileURLWithPath: self.rootPath)
            .appendingPathComponent(relativePath)
            .path
    }

    public func virtual(path: String) -> String {
        return "/" + path.deletingPrefix(self.rootPath)
    }

    /// Returns true if the resolved path is safely within the root jail.
    func isWithinJail(_ resolvedPath: String) -> Bool {
        let canonicalRoot = URL(fileURLWithPath: rootPath).resolvingSymlinksInPath().path
        let suffixed = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        return resolvedPath == canonicalRoot || resolvedPath.hasPrefix(suffixed)
    }

    public func listDirectory(client: Client, message: P7Message) {
        var recursive = false

        guard let user = client.user else { return }

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
            let managedType = File.FileType.type(path: real(path: normalizedPath))
            if !canBrowseManagedDirectory(atVirtualPath: normalizedPath, user: user, privilege: privilege, type: managedType) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            // user privileges
            if !user.hasPrivilege(name: "wired.account.file.list_files") {
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
        guard let user = client.user else { return }

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

        guard isWithinJail(realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard let type = File.FileType.type(path: realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.file.get_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege)
            let mayInspectManagedMetadata = type == .sync && user.hasPrivilege(name: "wired.account.file.set_permissions")
            let mayInspectSyncMetadata = type == .sync && mayInspectSyncRemoteMetadata(forVirtualPath: normalizedPath, user: user, privilege: privilege)
            if !access.readable && !mayInspectManagedMetadata && !mayInspectSyncMetadata {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
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

        if isManagedDirectoryType(type), let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege)
            let mode = privilege.mode ?? []
            reply.addParameter(field: "wired.file.owner", value: privilege.owner ?? "")
            reply.addParameter(field: "wired.file.group", value: privilege.group ?? "")
            reply.addParameter(field: "wired.file.owner.read", value: mode.contains(File.FilePermissions.ownerRead))
            reply.addParameter(field: "wired.file.owner.write", value: mode.contains(File.FilePermissions.ownerWrite))
            reply.addParameter(field: "wired.file.group.read", value: mode.contains(File.FilePermissions.groupRead))
            reply.addParameter(field: "wired.file.group.write", value: mode.contains(File.FilePermissions.groupWrite))
            reply.addParameter(field: "wired.file.everyone.read", value: mode.contains(File.FilePermissions.everyoneRead))
            reply.addParameter(field: "wired.file.everyone.write", value: mode.contains(File.FilePermissions.everyoneWrite))
            reply.addParameter(field: "wired.file.readable", value: access.readable)
            reply.addParameter(field: "wired.file.writable", value: access.writable)
            if type == .sync {
                appendSyncPolicyInfo(to: reply, virtualPath: normalizedPath, user: user, privilege: privilege)
            }
        }

        App.serverController.reply(client: client, reply: reply, message: message)
        App.serverController.recordEvent(.fileGotInfo, client: client, parameters: [normalizedPath])
    }

    public func createDirectory(client: Client, message: P7Message) {
        guard let user = client.user else { return }

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
        // Resolve parent symlinks for jail check (target dir does not exist yet)
        let rawRealPath = self.real(path: normalizedPath)
        let parentResolved = URL(fileURLWithPath: rawRealPath).deletingLastPathComponent().resolvingSymlinksInPath().path
        let realPath = parentResolved.stringByAppendingPathComponent(path: URL(fileURLWithPath: rawRealPath).lastPathComponent)

        guard isWithinJail(parentResolved) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            if !user.hasPrivilege(name: "wired.account.file.create_directories") {
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

        if !isValidTypePlacementForCreate(targetPath: normalizedPath, targetType: fileType) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if FileManager.default.fileExists(atPath: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
            return
        }

        if createPath(normalizedPath, type: fileType, user: user, message: message) {
            if fileType == .dropbox, user.hasPrivilege(name: "wired.account.file.set_permissions") {
                let privileges = privilegesFromMessage(message)

                if !FilePrivilege.set(privileges: privileges, path: realPath) {
                    try? FileManager.default.removeItem(atPath: realPath)
                    App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                    return
                }
            }

            if fileType == .sync {
                let policy = syncPolicyFromMessage(message) ?? defaultSyncPolicy()
                _ = SyncPolicy.save(policy, path: realPath)
            }

            App.indexController.addIndex(forPath: realPath)
            self.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
            App.serverController.replyOK(client: client, message: message)
            App.serverController.recordEvent(.fileCreatedDirectory, client: client, parameters: [normalizedPath])
        } else if (path as NSString).lastPathComponent.isEmpty {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
        } else if FileManager.default.fileExists(atPath: realPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    public func setType(client: Client, message: P7Message) {
        guard let user = client.user else { return }

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
            if !managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privileges).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.set_type") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let typeValue = message.enumeration(forField: "wired.file.type"),
              let fileType = File.FileType(rawValue: typeValue),
              fileType != .file else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !isValidTypePlacementForSetType(path: normalizedPath, targetType: fileType) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if setType(path: normalizedPath, type: fileType, client: client, message: message) {
            // Keep parent listing and directory subscriptions in sync with type updates.
            self.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
            self.notifyDirectoryChanged(path: normalizedPath)
            App.serverController.replyOK(client: client, message: message)
            App.serverController.recordEvent(.fileSetType, client: client, parameters: [normalizedPath])
        }
    }

    public func setPermissions(client: Client, message: P7Message) {
        guard let user = client.user else { return }

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

        guard isWithinJail(realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privileges = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privileges)
            let type = File.FileType.type(path: realPath)
            let mayManageSyncPermissions = type == .sync && user.hasPrivilege(name: "wired.account.file.set_permissions")
            if !access.writable && !mayManageSyncPermissions {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.set_permissions") {
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

        // SECURITY (F_016): Re-resolve immediately before writing to the filesystem to
        // close the TOCTOU window between the jail check above and the write operations.
        let finalPath = URL(fileURLWithPath: realPath).resolvingSymlinksInPath().path
        guard isWithinJail(finalPath) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let wiredMetaPath = finalPath.stringByAppendingPathComponent(path: ".wired")
        do {
            try FileManager.default.createDirectory(atPath: wiredMetaPath, withIntermediateDirectories: true, attributes: nil)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let newPrivileges = FilePrivilege(owner: owner, group: group, mode: mode)
        if !FilePrivilege.set(privileges: newPrivileges, path: finalPath) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        App.serverController.recordEvent(.fileSetPermissions, client: client, parameters: [normalizedPath])
    }

    public func setSyncPolicy(client: Client, message: P7Message) {
        guard let user = client.user else { return }

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

        guard isWithinJail(realPath),
              File.FileType.type(path: realPath) == .sync else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privileges = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privileges)
            if !access.writable && !user.hasPrivilege(name: "wired.account.file.set_permissions") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.set_permissions") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let userModeRaw = message.string(forField: "wired.file.sync.user_mode"),
              let groupModeRaw = message.string(forField: "wired.file.sync.group_mode"),
              let everyoneModeRaw = message.string(forField: "wired.file.sync.everyone_mode"),
              let userMode = SyncPolicy.Mode(rawValue: userModeRaw),
              let groupMode = SyncPolicy.Mode(rawValue: groupModeRaw),
              let everyoneMode = SyncPolicy.Mode(rawValue: everyoneModeRaw) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        var policy = SyncPolicy.load(path: realPath) ?? defaultSyncPolicy()
        policy.userMode = userMode
        policy.groupMode = groupMode
        policy.everyoneMode = everyoneMode

        guard SyncPolicy.save(policy, path: realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        App.serverController.recordEvent(.fileSetPermissions, client: client, parameters: [normalizedPath, "sync_policy"])
    }

    public func delete(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        guard let path = message.string(forField: "wired.file.path") else {
            return
        }

        // F_013: prevent deletion of root directory
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedPath.isEmpty || trimmedPath == "/" {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
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
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege)
            let canWrite = access.writable
            let canRead = access.readable
            let writeOnlyAllowed = syncRealPath(inVirtualPath: normalizedPath) != nil
            let allowed = writeOnlyAllowed ? canWrite : (canRead && canWrite)

            if !allowed {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else {
            // user privileges
            if !user.hasPrivilege(name: "wired.account.file.delete_files") {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        if self.delete(path: normalizedPath, client: client, message: message) {
            App.serverController.replyOK(client: client, message: message)
            App.serverController.recordEvent(.fileDeleted, client: client, parameters: [normalizedPath])
        }
    }

    public func move(client: Client, message: P7Message) {
        guard let user = client.user else { return }

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
            if !managedAccess(forVirtualPath: normalizedFromPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.move_files") &&
                    (!user.hasPrivilege(name: "wired.account.file.rename_files") || !isRenameOnly) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedToPath) {
            if !managedAccess(forVirtualPath: normalizedToPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.move_files") &&
                    (!user.hasPrivilege(name: "wired.account.file.rename_files") || !isRenameOnly) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !isValidMovePlacement(from: normalizedFromPath, to: normalizedToPath) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if move(from: normalizedFromPath, to: normalizedToPath, client: client, message: message) {
            App.serverController.replyOK(client: client, message: message)
            App.serverController.recordEvent(.fileMoved, client: client, parameters: [normalizedFromPath, normalizedToPath])
        }
    }

    private func delete(path: String, client: Client, message: P7Message) -> Bool {
        let realPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path
        let parentPath = path.stringByDeletingLastPathComponent

        guard isWithinJail(realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }
        let isDirectory = File.FileType.type(path: realPath) != .file

        // SECURITY (F_016): Re-resolve immediately before the destructive syscall to close
        // the TOCTOU window. A symlink swap between the jail check above and removeItem
        // could otherwise redirect the deletion outside the jail.
        let finalPath = URL(fileURLWithPath: realPath).resolvingSymlinksInPath().path
        guard isWithinJail(finalPath) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return false
        }

        do {
            try FileManager.default.removeItem(atPath: finalPath)

            App.indexController.removeIndex(forPath: finalPath)
        } catch let error {
            Logger.error("Cannot delete file \(finalPath) \(error)")

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

        guard isWithinJail(sourceRealPath), isWithinJail(destinationRealPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }

        // SECURITY (F_016): Re-resolve both paths immediately before moveItem to close the
        // TOCTOU window. A symlink swap between the jail check above and the syscall could
        // redirect the move source or destination outside the jail.
        let finalSource = URL(fileURLWithPath: sourceRealPath).resolvingSymlinksInPath().path
        let finalDestination = URL(fileURLWithPath: destinationRealPath).resolvingSymlinksInPath().path
        guard isWithinJail(finalSource), isWithinJail(finalDestination) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return false
        }

        do {
            try FileManager.default.moveItem(atPath: finalSource, toPath: finalDestination)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        App.indexController.removeIndex(forPath: finalSource)
        App.indexController.addIndex(forPath: finalDestination)
        self.notifyDirectoryChanged(path: sourceParentPath)
        if sourceParentPath != destinationParentPath {
            self.notifyDirectoryChanged(path: destinationParentPath)
        }

        return true
    }

    private func replyList(_ path: String, _ recursive: Bool, _ client: Client, _ message: P7Message) {
        DispatchQueue.global(qos: .default).async {
            let rawRealPath: String = (path == "/") ? self.rootPath : self.real(path: path)
            let realPath = URL(fileURLWithPath: rawRealPath).resolvingSymlinksInPath().path

            guard self.isWithinJail(realPath) else {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }

            var isDir: ObjCBool = false

            if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDir) || !isDir.boolValue {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }

            var visited: Set<String> = []
            var entryCount: Int = 0
            if !self.replyListRecursive(realPath: realPath, virtualPath: path, recursive: recursive, depth: 0, visited: &visited, entryCount: &entryCount, client: client, message: message) {
                App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
                return
            }

            let reply = P7Message(withName: "wired.file.file_list.done", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: path)
            reply.addParameter(field: "wired.file.available", value: UInt64(1))
            App.serverController.reply(client: client, reply: reply, message: message)
            App.serverController.recordEvent(.fileListedDirectory, client: client, parameters: [path])
        }
    }

    // SECURITY (FINDING_F_012): Limits to prevent DoS via deeply nested or huge directories
    private static let maxRecursiveDepth: Int = 16
    private static let maxRecursiveEntries: Int = 10_000

    private func replyListRecursive(
        realPath: String,
        virtualPath: String,
        recursive: Bool,
        depth: Int,
        visited: inout Set<String>,
        entryCount: inout Int,
        client: Client,
        message: P7Message
    ) -> Bool {
        guard let user = client.user else { return false }

        // SECURITY (FINDING_F_012): enforce depth limit
        guard depth <= Self.maxRecursiveDepth else {
            Logger.warning("Recursive listing exceeded max depth \(Self.maxRecursiveDepth)")
            return true
        }

        // SECURITY (FINDING_F_012): enforce entry count limit
        guard entryCount < Self.maxRecursiveEntries else {
            Logger.warning("Recursive listing exceeded max entries \(Self.maxRecursiveEntries)")
            return true
        }

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
            var mayBrowseManagedMetadata = false
            var managedPrivileges: FilePrivilege?

            if isManagedDirectoryType(type), let privileges = dropBoxPrivileges(forVirtualPath: childVirtualPath) {
                let access = managedAccess(forVirtualPath: childVirtualPath, user: user, privilege: privileges)
                readable = access.readable
                writable = access.writable
                mayBrowseManagedMetadata = canBrowseManagedDirectory(
                    atVirtualPath: childVirtualPath,
                    user: user,
                    privilege: privileges,
                    type: type
                )
                managedPrivileges = privileges
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
            case .sync:
                datasize = 0
                rsrcsize = 0
                directorycount = mayBrowseManagedMetadata ? File.count(path: childRealPath) : 0
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
                } else if isDirectoryType(type) {
                    reply.addParameter(field: "wired.file.directory_count", value: directorycount)
                }

                reply.addParameter(field: "wired.file.type", value: type.rawValue)
            }

            reply.addParameter(field: "wired.file.link", value: false)
            reply.addParameter(field: "wired.file.executable", value: false)
            reply.addParameter(field: "wired.file.label", value: File.FileLabel.LABEL_NONE.rawValue)
            reply.addParameter(field: "wired.file.volume", value: UInt32(0))

            if isManagedDirectoryType(type) {
                reply.addParameter(field: "wired.file.readable", value: readable)
                reply.addParameter(field: "wired.file.writable", value: writable)
                if type == .sync, let managedPrivileges {
                    appendSyncPolicyInfo(to: reply, virtualPath: childVirtualPath, user: user, privilege: managedPrivileges)
                }
            }

            App.serverController.reply(client: client, reply: reply, message: message)

            entryCount += 1
            // SECURITY (FINDING_F_012): stop if entry limit reached
            guard entryCount < Self.maxRecursiveEntries else {
                Logger.warning("Recursive listing exceeded max entries \(Self.maxRecursiveEntries)")
                return true
            }

            if recursive && isDirectoryType(type) {
                if !self.replyListRecursive(
                    realPath: childRealPath,
                    virtualPath: childVirtualPath,
                    recursive: true,
                    depth: depth + 1,
                    visited: &visited,
                    entryCount: &entryCount,
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
        try? FileManager.default.createDirectory(atPath: rootPath, withIntermediateDirectories: true, attributes: nil)
    }

    public func createDefaultDirectoryIfMissing(path: String,
                                                type: File.FileType,
                                                privileges: FilePrivilege?) {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
        } else if !isDirectory.boolValue {
            return
        }

        _ = File.FileType.set(type: type, path: path)

        if let privileges = privileges {
            _ = FilePrivilege.set(privileges: privileges, path: path)
        }
    }

    private func createPath(_ path: String, type: File.FileType, user: User, message: P7Message) -> Bool {
        // Resolve the parent directory's symlinks to check jail containment,
        // since the target directory does not exist yet.
        let rawRealPath = self.real(path: path)
        let parentDir = URL(fileURLWithPath: rawRealPath).deletingLastPathComponent().resolvingSymlinksInPath().path
        let realPath = parentDir.stringByAppendingPathComponent(path: URL(fileURLWithPath: rawRealPath).lastPathComponent)

        guard isWithinJail(parentDir) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(atPath: realPath, withIntermediateDirectories: false, attributes: [FileAttributeKey.posixPermissions: 0o755])
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

    private func syncPolicyFromMessage(_ message: P7Message) -> SyncPolicy? {
        guard let userModeRaw = message.string(forField: "wired.file.sync.user_mode"),
              let groupModeRaw = message.string(forField: "wired.file.sync.group_mode"),
              let everyoneModeRaw = message.string(forField: "wired.file.sync.everyone_mode"),
              let userMode = SyncPolicy.Mode(rawValue: userModeRaw),
              let groupMode = SyncPolicy.Mode(rawValue: groupModeRaw),
              let everyoneMode = SyncPolicy.Mode(rawValue: everyoneModeRaw) else {
            return nil
        }

        return SyncPolicy(
            userMode: userMode,
            groupMode: groupMode,
            everyoneMode: everyoneMode
        )
    }

    private func setType(path: String, type: File.FileType, client: Client, message: P7Message) -> Bool {
        let canonicalPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path

        guard isWithinJail(canonicalPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }

        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory) || !isDirectory.boolValue {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }

        if !File.FileType.set(type: type, path: canonicalPath) {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        if type == .sync {
            _ = SyncPolicy.save(SyncPolicy.load(path: canonicalPath) ?? defaultSyncPolicy(), path: canonicalPath)
        }

        return true
    }

    private func containsDisallowedDescendantForSync(inRealPath path: String) -> Bool {
        guard let enumerator = FileManager.default.enumerator(atPath: path) else {
            return false
        }

        while let entry = enumerator.nextObject() as? String {
            if entry.hasPrefix(".wired") {
                continue
            }

            let fullPath = path.stringByAppendingPathComponent(path: entry)
            switch File.FileType.type(path: fullPath) {
            case .uploads, .dropbox, .sync:
                return true
            default:
                break
            }
        }

        return false
    }

    private func isSyncPath(_ path: String) -> Bool {
        return syncRealPath(inVirtualPath: path) != nil
    }

    private func isValidTypePlacementForCreate(targetPath: String, targetType: File.FileType) -> Bool {
        if isSyncPath(targetPath) && (targetType == .uploads || targetType == .dropbox || targetType == .sync) {
            return false
        }
        return true
    }

    private func isValidTypePlacementForSetType(path: String, targetType: File.FileType) -> Bool {
        if targetType == .uploads || targetType == .dropbox || targetType == .sync {
            let parent = path.stringByDeletingLastPathComponent
            if isSyncPath(parent) {
                return false
            }
        }

        if targetType == .sync {
            let realPath = URL(fileURLWithPath: self.real(path: path)).resolvingSymlinksInPath().path
            if containsDisallowedDescendantForSync(inRealPath: realPath) {
                return false
            }
        }

        return true
    }

    private func isValidMovePlacement(from sourcePath: String, to destinationPath: String) -> Bool {
        let sourceRealPath = URL(fileURLWithPath: self.real(path: sourcePath)).resolvingSymlinksInPath().path
        let sourceType = File.FileType.type(path: sourceRealPath)
        let targetParentVirtual = destinationPath.stringByDeletingLastPathComponent

        if isSyncPath(targetParentVirtual) {
            if sourceType == .uploads || sourceType == .dropbox || sourceType == .sync {
                return false
            }
        }

        return true
    }

    func dropBoxPrivileges(forVirtualPath path: String) -> FilePrivilege? {
        guard let dropBoxPath = managedRealPath(inVirtualPath: path) else {
            return nil
        }

        if let privileges = FilePrivilege(path: dropBoxPath) {
            return privileges
        }

        // Same default as legacy wired: writable by everyone when no permissions file exists.
        return FilePrivilege(owner: "", group: "", mode: .everyoneWrite)
    }

    private func managedRealPath(inVirtualPath path: String) -> String? {
        let normalized = NSString(string: path).standardizingPath
        let components = normalized.split(separator: "/").map(String.init)

        var current = URL(fileURLWithPath: self.real(path: "/")).resolvingSymlinksInPath().path

        for component in components {
            if component.isEmpty {
                continue
            }

            current = current.stringByAppendingPathComponent(path: component)
            if isManagedDirectoryType(File.FileType.type(path: current)) {
                return current
            }
        }

        return nil
    }

    private func syncRealPath(inVirtualPath path: String) -> String? {
        let normalized = NSString(string: path).standardizingPath
        let components = normalized.split(separator: "/").map(String.init)

        var current = URL(fileURLWithPath: self.real(path: "/")).resolvingSymlinksInPath().path

        for component in components {
            if component.isEmpty {
                continue
            }

            current = current.stringByAppendingPathComponent(path: component)
            if File.FileType.type(path: current) == .sync {
                return current
            }
        }

        return nil
    }

    func syncPolicy(forVirtualPath path: String) -> SyncPolicy? {
        guard let syncPath = syncRealPath(inVirtualPath: path) else {
            return nil
        }
        return SyncPolicy.load(path: syncPath) ?? defaultSyncPolicy()
    }

    func isWithinSyncTree(virtualPath path: String) -> Bool {
        return syncRealPath(inVirtualPath: path) != nil
    }

    func validateSyncQuotaForUpload(path virtualPath: String, incomingDataSize: UInt64) -> Bool {
        guard let syncPath = syncRealPath(inVirtualPath: virtualPath),
              let policy = syncPolicy(forVirtualPath: virtualPath) else {
            return true
        }

        if policy.maxFileSizeBytes > 0 && incomingDataSize > policy.maxFileSizeBytes {
            return false
        }

        if policy.maxTreeSizeBytes > 0 {
            var currentSize: UInt64 = 0
            if let enumerator = FileManager.default.enumerator(atPath: syncPath) {
                while let entry = enumerator.nextObject() as? String {
                    if entry.hasPrefix(".wired") {
                        continue
                    }
                    let fullPath = syncPath.stringByAppendingPathComponent(path: entry)
                    currentSize += File.size(path: fullPath)
                }
            }

            if currentSize + incomingDataSize > policy.maxTreeSizeBytes {
                return false
            }
        }

        if policy.maxItems > 0 {
            var itemCount: UInt64 = 0
            if let enumerator = FileManager.default.enumerator(atPath: syncPath) {
                while let entry = enumerator.nextObject() as? String {
                    if entry.hasPrefix(".wired") {
                        continue
                    }
                    itemCount += 1
                }
            }

            if itemCount + 1 > policy.maxItems {
                return false
            }
        }

        return true
    }

    // MARK: - Directory subscriptions
    public func subscribeDirectory(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.file.list_files") {
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

        // SECURITY (FINDING_F_017): per-client subscription limit to prevent memory exhaustion
        let subscribed = subscriptionsQueue.sync { () -> Bool in
            let existing = subscribedRealPathsByClient[client.userID] ?? Set<String>()
            guard existing.count < 100 else { return false }

            var realPaths = existing
            realPaths.insert(realPath)
            subscribedRealPathsByClient[client.userID] = realPaths

            var virtualPaths = subscribedVirtualPathsByClient[client.userID] ?? [:]
            virtualPaths[realPath] = normalizedVirtualPath
            subscribedVirtualPathsByClient[client.userID] = virtualPaths
            return true
        }

        guard subscribed else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
    }

    public func unsubscribeDirectory(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.file.list_files") {
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
