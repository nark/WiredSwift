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
    static let maxPreviewSizeBytes: UInt64 = 10 * 1_024 * 1_024

    public var rootPath: String
    let metadataStore = FileMetadataStore()
    private let subscriptionsQueue = DispatchQueue(label: "wired3.files.subscriptions")
    private var subscribedRealPathsByClient: [UInt32: Set<String>] = [:]
    private var subscribedVirtualPathsByClient: [UInt32: [String: Set<String>]] = [:]

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
        reply.addParameter(field: "wired.file.sync.max_file_size_bytes", value: policy.maxFileSizeBytes)
        reply.addParameter(field: "wired.file.sync.max_tree_size_bytes", value: policy.maxTreeSizeBytes)
        if !policy.excludePatterns.isEmpty {
            reply.addParameter(field: "wired.file.sync.exclude_patterns", value: policy.excludePatterns)
        }
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
        if path == self.rootPath {
            return "/"
        }

        let virtualPath = path.deletingPrefix(self.rootPath)
        return virtualPath.hasPrefix("/") ? virtualPath : "/" + virtualPath
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

        let normalizedPath = normalizeVirtualPath(path)

        // file privileges (dropbox inherited in path)
        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let managedType = File.FileType.type(path: resolvedVirtualPath(for: normalizedPath).resolvedRealPath)
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

        let resolvedPath = resolvedVirtualPath(for: path)
        let normalizedPath = resolvedPath.normalizedVirtualPath
        let realPath = resolvedPath.resolvedRealPath

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

        reply.addParameter(field: "wired.file.link", value: resolvedPath.linkKind != .none)
        reply.addParameter(field: "wired.file.executable", value: false)
        reply.addParameter(field: "wired.file.label", value: metadataStore.label(forPath: realPath).rawValue)
        reply.addParameter(field: "wired.file.volume", value: UInt32(0))
        reply.addParameter(field: "wired.file.comment", value: wiredFileComment(forRealPath: realPath))

        if type == .file {
            reply.addParameter(field: "wired.file.data_size", value: File.size(path: realPath))
            reply.addParameter(field: "wired.file.rsrc_size", value: UInt64(0))
        } else if isManagedDirectoryType(type),
                  let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            let access = managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege)
            reply.addParameter(
                field: "wired.file.directory_count",
                value: access.readable ? File.count(path: realPath) : 0
            )
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

    public func previewFile(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.transfer.download_files") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let resolvedPath = resolvedVirtualPath(for: path)
        let normalizedPath = resolvedPath.normalizedVirtualPath
        let realPath = resolvedPath.resolvedRealPath

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard !isDirectory.boolValue else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath),
           !managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege).readable {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let previewData: Data
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: realPath)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard fileSize <= Self.maxPreviewSizeBytes else {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }

            previewData = try Data(contentsOf: URL(fileURLWithPath: realPath), options: .mappedIfSafe)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let reply = P7Message(withName: "wired.file.preview", spec: message.spec)
        reply.addParameter(field: "wired.file.path", value: normalizedPath)
        reply.addParameter(field: "wired.file.preview", value: previewData)
        App.serverController.reply(client: client, reply: reply, message: message)
        App.serverController.recordEvent(.filePreviewedFile, client: client, parameters: [normalizedPath])
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

        let resolvedPath = resolvedVirtualPathByResolvingParent(for: path)
        let normalizedPath = resolvedPath.normalizedVirtualPath
        let realPath = resolvedPath.resolvedRealPath

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

    public func setComment(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        guard let rawPath = message.string(forField: "wired.file.path"),
              let comment = message.string(forField: "wired.file.comment") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: rawPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let resolved = resolvedVirtualPath(for: rawPath)
        let normalizedPath = resolved.normalizedVirtualPath
        let realPath = resolved.resolvedRealPath

        guard FileManager.default.fileExists(atPath: realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.set_comment") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            if comment.isEmpty {
                try metadataStore.removeComment(forPath: realPath)
            } else {
                try metadataStore.setComment(comment, forPath: realPath)
            }
        } catch {
            Logger.error("Cannot set file comment for \(realPath): \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
        App.serverController.replyOK(client: client, message: message)
        App.serverController.recordEvent(.fileSetComment, client: client, parameters: [normalizedPath])
    }

    public func setLabel(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        guard let rawPath = message.string(forField: "wired.file.path"),
              let rawLabel = message.enumeration(forField: "wired.file.label"),
              let label = File.FileLabel(rawValue: rawLabel) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if !File.isValid(path: rawPath) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let resolved = resolvedVirtualPath(for: rawPath)
        let normalizedPath = resolved.normalizedVirtualPath
        let realPath = resolved.resolvedRealPath

        guard FileManager.default.fileExists(atPath: realPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !managedAccess(forVirtualPath: normalizedPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.set_label") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            if label == .LABEL_NONE {
                try metadataStore.removeLabel(forPath: realPath)
            } else {
                try metadataStore.setLabel(label, forPath: realPath)
            }
        } catch {
            Logger.error("Cannot set file label for \(realPath): \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
        App.serverController.replyOK(client: client, message: message)
        App.serverController.recordEvent(.fileSetLabel, client: client, parameters: [normalizedPath])
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

        let resolvedPath = resolvedVirtualPath(for: path)
        let normalizedPath = resolvedPath.normalizedVirtualPath
        let realPath = resolvedPath.resolvedRealPath

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

        let finalPath = resolveAliasesAndSymlinks(in: realPath)

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

        let resolvedPath = resolvedVirtualPath(for: path)
        let normalizedPath = resolvedPath.normalizedVirtualPath
        let realPath = resolvedPath.resolvedRealPath

        guard File.FileType.type(path: realPath) == .sync else {
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
        if let v = message.uint64(forField: "wired.file.sync.max_file_size_bytes") { policy.maxFileSizeBytes = v }
        if let v = message.uint64(forField: "wired.file.sync.max_tree_size_bytes") { policy.maxTreeSizeBytes = v }
        if let v = message.string(forField: "wired.file.sync.exclude_patterns") { policy.excludePatterns = v }

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

    public func link(client: Client, message: P7Message) {
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

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedFromPath) {
            if !managedAccess(forVirtualPath: normalizedFromPath, user: user, privilege: privilege).readable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.create_links") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let privilege = dropBoxPrivileges(forVirtualPath: normalizedToPath) {
            if !managedAccess(forVirtualPath: normalizedToPath, user: user, privilege: privilege).writable {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        } else if !user.hasPrivilege(name: "wired.account.file.create_links") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !isValidMovePlacement(from: normalizedFromPath, to: normalizedToPath) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if link(from: normalizedFromPath, to: normalizedToPath, client: client, message: message) {
            App.serverController.replyOK(client: client, message: message)
            App.serverController.recordEvent(.fileLinked, client: client, parameters: [normalizedFromPath, normalizedToPath])
        }
    }

    private func delete(path: String, client: Client, message: P7Message) -> Bool {
        let realPath = resolvedVirtualPathByResolvingParent(for: path).resolvedRealPath
        let parentPath = path.stringByDeletingLastPathComponent
        let isDirectory = File.FileType.type(path: realPath) != .file
        let finalPath = resolvedVirtualPathByResolvingParent(for: path).resolvedRealPath

        do {
            try FileManager.default.removeItem(atPath: finalPath)

            App.indexController.removeIndex(forPath: finalPath)
        } catch let error {
            Logger.error("Cannot delete file \(finalPath) \(error)")

            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)

            return false
        }

        removeMetadata(forPath: finalPath)

        self.notifyDirectoryChanged(path: parentPath)

        if isDirectory {
            self.notifyDirectoryDeleted(path: path)
        }

        return true
    }

    private func move(from sourcePath: String, to destinationPath: String, client: Client, message: P7Message) -> Bool {
        let sourceParentPath = sourcePath.stringByDeletingLastPathComponent
        let destinationParentPath = destinationPath.stringByDeletingLastPathComponent
        let finalSource = resolvedVirtualPathByResolvingParent(for: sourcePath).resolvedRealPath
        let finalDestination = resolvedVirtualPathByResolvingParent(for: destinationPath).resolvedRealPath

        do {
            try FileManager.default.moveItem(atPath: finalSource, toPath: finalDestination)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        moveMetadata(from: finalSource, to: finalDestination)

        App.indexController.removeIndex(forPath: finalSource)
        App.indexController.addIndex(forPath: finalDestination)
        self.notifyDirectoryChanged(path: sourceParentPath)
        if sourceParentPath != destinationParentPath {
            self.notifyDirectoryChanged(path: destinationParentPath)
        }

        return true
    }

    private func link(from sourcePath: String, to destinationPath: String, client: Client, message: P7Message) -> Bool {
        let destinationParentPath = destinationPath.stringByDeletingLastPathComponent
        let finalSource = resolvedVirtualPathByResolvingParent(for: sourcePath).resolvedRealPath
        let resolvedSource = URL(fileURLWithPath: finalSource).resolvingSymlinksInPath().path
        let finalDestination = resolvedVirtualPathByResolvingParent(for: destinationPath).resolvedRealPath

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: finalSource, isDirectory: &isDirectory) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return false
        }

        if FileManager.default.fileExists(atPath: finalDestination) {
            App.serverController.replyError(client: client, error: "wired.error.file_exists", message: message)
            return false
        }

        do {
            try FileManager.default.createSymbolicLink(atPath: finalDestination, withDestinationPath: resolvedSource)
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        App.indexController.addIndex(forPath: finalDestination)
        self.notifyDirectoryChanged(path: destinationParentPath)

        return true
    }

    private func replyList(_ path: String, _ recursive: Bool, _ client: Client, _ message: P7Message) {
        DispatchQueue.global(qos: .default).async {
            let realPath = self.resolvedVirtualPath(for: path).resolvedRealPath

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
            let childJoinedPath = realPath.stringByAppendingPathComponent(path: file)
            let childRealPath = self.resolveAliasesAndSymlinks(in: childJoinedPath)
            let linkKind = self.exactLinkKind(atPath: childJoinedPath)
            let type = WiredSwift.File.FileType.type(path: childRealPath)

            var datasize: UInt64 = 0
            var rsrcsize: UInt64 = 0
            var directorycount: UInt32 = 0

            var readable = false
            var writable = false
            var managedPrivileges: FilePrivilege?

            if isManagedDirectoryType(type), let privileges = dropBoxPrivileges(forVirtualPath: childVirtualPath) {
                let access = managedAccess(forVirtualPath: childVirtualPath, user: user, privilege: privileges)
                readable = access.readable
                writable = access.writable
                managedPrivileges = privileges
            }

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
                directorycount = readable ? File.count(path: childRealPath) : 0
            case .none:
                datasize = 0
                rsrcsize = 0
                directorycount = 0
            }

            let reply = P7Message(withName: "wired.file.file_list", spec: message.spec)
            reply.addParameter(field: "wired.file.path", value: childVirtualPath)
            let attributes = try? FileManager.default.attributesOfItem(atPath: childRealPath)

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

            if let type = File.FileType.type(path: childRealPath) {
                if type == .file {
                    reply.addParameter(field: "wired.file.data_size", value: datasize)
                    reply.addParameter(field: "wired.file.rsrc_size", value: rsrcsize)
                } else if isDirectoryType(type) {
                    reply.addParameter(field: "wired.file.directory_count", value: directorycount)
                }

                reply.addParameter(field: "wired.file.type", value: type.rawValue)
            }

            reply.addParameter(field: "wired.file.link", value: linkKind != .none)
            reply.addParameter(field: "wired.file.executable", value: false)
            reply.addParameter(field: "wired.file.label", value: metadataStore.label(forPath: childRealPath).rawValue)
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
        let realPath = resolvedVirtualPathByResolvingParent(for: path).resolvedRealPath

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
        let canonicalPath = resolvedVirtualPath(for: path).resolvedRealPath

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
            let realPath = resolvedVirtualPath(for: path).resolvedRealPath
            if containsDisallowedDescendantForSync(inRealPath: realPath) {
                return false
            }
        }

        return true
    }

    private func isValidMovePlacement(from sourcePath: String, to destinationPath: String) -> Bool {
        let sourceRealPath = resolvedVirtualPath(for: sourcePath).resolvedRealPath
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
        let normalized = normalizeVirtualPath(path)
        let components = normalized.split(separator: "/").map(String.init)

        var current = resolvedVirtualPath(for: "/").resolvedRealPath

        for component in components {
            if component.isEmpty {
                continue
            }

            current = resolveAliasesAndSymlinks(in: current.stringByAppendingPathComponent(path: component))
            if isManagedDirectoryType(File.FileType.type(path: current)) {
                return current
            }
        }

        return nil
    }

    private func syncRealPath(inVirtualPath path: String) -> String? {
        let normalized = normalizeVirtualPath(path)
        let components = normalized.split(separator: "/").map(String.init)

        var current = resolvedVirtualPath(for: "/").resolvedRealPath

        for component in components {
            if component.isEmpty {
                continue
            }

            current = resolveAliasesAndSymlinks(in: current.stringByAppendingPathComponent(path: component))
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
                    if entry.hasPrefix(".wired") { continue }
                    let fullPath = syncPath.stringByAppendingPathComponent(path: entry)
                    currentSize += File.size(path: fullPath)
                }
            }
            if currentSize + incomingDataSize > policy.maxTreeSizeBytes {
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

        let normalizedVirtualPath = normalizeVirtualPath(virtualPath)
        let realPath = resolvedVirtualPath(for: normalizedVirtualPath).resolvedRealPath
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
            var aliases = virtualPaths[realPath] ?? []
            aliases.insert(normalizedVirtualPath)
            virtualPaths[realPath] = aliases
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

        let normalizedVirtualPath = normalizeVirtualPath(virtualPath)
        let realPath = resolvedVirtualPath(for: normalizedVirtualPath).resolvedRealPath
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let isSubscribed = subscriptionsQueue.sync { () -> Bool in
            let subscribed = subscribedVirtualPathsByClient[client.userID]?[realPath]?.contains(normalizedVirtualPath) ?? false
            if subscribed {
                subscribedVirtualPathsByClient[client.userID]?[realPath]?.remove(normalizedVirtualPath)
                if subscribedVirtualPathsByClient[client.userID]?[realPath]?.isEmpty == true {
                    subscribedVirtualPathsByClient[client.userID]?[realPath] = nil
                    subscribedRealPathsByClient[client.userID]?.remove(realPath)
                }
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
        let realPath = resolvedVirtualPath(for: path).resolvedRealPath
        let targets: [(UInt32, String)] = subscriptionsQueue.sync {
            var snapshot: [(UInt32, String)] = []
            for (userID, paths) in subscribedRealPathsByClient where paths.contains(realPath) {
                if let virtualPaths = subscribedVirtualPathsByClient[userID]?[realPath] {
                    snapshot.append(contentsOf: virtualPaths.map { (userID, $0) })
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

    func wiredFileComment(forRealPath path: String) -> String {
        metadataStore.comment(forPath: path) ?? ""
    }

    private func removeMetadata(forPath path: String) {
        do { try metadataStore.removeComment(forPath: path) } catch { Logger.warning("Could not remove comment metadata for \(path): \(error)") }
        do { try metadataStore.removeLabel(forPath: path) } catch { Logger.warning("Could not remove label metadata for \(path): \(error)") }
    }

    private func moveMetadata(from source: String, to destination: String) {
        do { try metadataStore.moveComment(from: source, to: destination) } catch { Logger.warning("Could not move comment metadata \(source) -> \(destination): \(error)") }
        do { try metadataStore.moveLabel(from: source, to: destination) } catch { Logger.warning("Could not move label metadata \(source) -> \(destination): \(error)") }
    }
}
