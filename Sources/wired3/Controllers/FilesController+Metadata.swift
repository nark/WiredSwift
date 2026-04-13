import Foundation
import WiredSwift

extension FilesController {
    public func createDefaultDirectoryIfMissing(
        path: String,
        type: File.FileType,
        privileges: FilePrivilege?
    ) {
        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
            try? FileManager.default.createDirectory(
                atPath: path,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.posixPermissions: 0o755]
            )
        } else if !isDirectory.boolValue {
            return
        }

        _ = File.FileType.set(type: type, path: path)

        if let privileges {
            _ = FilePrivilege.set(privileges: privileges, path: path)
        }
    }

    func createPath(_ path: String, type: File.FileType, user: User, message: P7Message) -> Bool {
        let realPath = resolvedVirtualPathByResolvingParent(for: path).resolvedRealPath

        do {
            try FileManager.default.createDirectory(
                atPath: realPath,
                withIntermediateDirectories: false,
                attributes: [FileAttributeKey.posixPermissions: 0o755]
            )
        } catch {
            return false
        }

        if !File.FileType.set(type: type, path: realPath) {
            return false
        }

        return true
    }

    func privilegesFromMessage(_ message: P7Message) -> FilePrivilege {
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

    func syncPolicyFromMessage(_ message: P7Message) -> SyncPolicy? {
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

    func setType(path: String, type: File.FileType, client: Client, message: P7Message) -> Bool {
        let canonicalPath = resolvedVirtualPath(for: path).resolvedRealPath

        var isDirectory: ObjCBool = false
        if !FileManager.default.fileExists(atPath: canonicalPath, isDirectory: &isDirectory)
            || !isDirectory.boolValue {
            App.serverController.replyError(
                client: client,
                error: "wired.error.file_not_found",
                message: message
            )
            return false
        }

        if !File.FileType.set(type: type, path: canonicalPath) {
            App.serverController.replyError(
                client: client,
                error: "wired.error.internal_error",
                message: message
            )
            return false
        }

        if type == .sync {
            _ = SyncPolicy.save(
                SyncPolicy.load(path: canonicalPath) ?? defaultSyncPolicy(),
                path: canonicalPath
            )
        }

        return true
    }

    func containsDisallowedDescendantForSync(inRealPath path: String) -> Bool {
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

    func isSyncPath(_ path: String) -> Bool {
        syncRealPath(inVirtualPath: path) != nil
    }

    func isValidTypePlacementForCreate(targetPath: String, targetType: File.FileType) -> Bool {
        if isSyncPath(targetPath)
            && (targetType == .uploads || targetType == .dropbox || targetType == .sync) {
            return false
        }

        return true
    }

    func isValidTypePlacementForSetType(path: String, targetType: File.FileType) -> Bool {
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

    func isValidMovePlacement(from sourcePath: String, to destinationPath: String) -> Bool {
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

        return FilePrivilege(owner: "", group: "", mode: .everyoneWrite)
    }

    func managedRealPath(inVirtualPath path: String) -> String? {
        let normalized = normalizeVirtualPath(path)
        let components = normalized.split(separator: "/").map(String.init)

        var current = resolvedVirtualPath(for: "/").resolvedRealPath
        for component in components {
            if component.isEmpty {
                continue
            }

            current = resolveAliasesAndSymlinks(
                in: current.stringByAppendingPathComponent(path: component)
            )
            if isManagedDirectoryType(File.FileType.type(path: current)) {
                return current
            }
        }

        return nil
    }

    func syncRealPath(inVirtualPath path: String) -> String? {
        let normalized = normalizeVirtualPath(path)
        let components = normalized.split(separator: "/").map(String.init)

        var current = resolvedVirtualPath(for: "/").resolvedRealPath
        for component in components {
            if component.isEmpty {
                continue
            }

            current = resolveAliasesAndSymlinks(
                in: current.stringByAppendingPathComponent(path: component)
            )
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
        syncRealPath(inVirtualPath: path) != nil
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

        return true
    }

    // MARK: - Directory subscriptions
    public func subscribeDirectory(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.file.list_files") {
            App.serverController.replyError(
                client: client,
                error: "wired.error.permission_denied",
                message: message
            )
            return
        }

        guard let virtualPath = message.string(forField: "wired.file.path") else {
            return
        }

        if !File.isValid(path: virtualPath) {
            App.serverController.replyError(
                client: client,
                error: "wired.error.file_not_found",
                message: message
            )
            return
        }

        let normalizedVirtualPath = normalizeVirtualPath(virtualPath)
        let realPath = resolvedVirtualPath(for: normalizedVirtualPath).resolvedRealPath
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) {
            App.serverController.replyError(
                client: client,
                error: "wired.error.file_not_found",
                message: message
            )
            return
        }

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
            App.serverController.replyError(
                client: client,
                error: "wired.error.internal_error",
                message: message
            )
            return
        }

        App.serverController.replyOK(client: client, message: message)
    }

    public func unsubscribeDirectory(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.file.list_files") {
            App.serverController.replyError(
                client: client,
                error: "wired.error.permission_denied",
                message: message
            )
            return
        }

        guard let virtualPath = message.string(forField: "wired.file.path") else {
            return
        }

        if !File.isValid(path: virtualPath) {
            App.serverController.replyError(
                client: client,
                error: "wired.error.file_not_found",
                message: message
            )
            return
        }

        let normalizedVirtualPath = normalizeVirtualPath(virtualPath)
        let realPath = resolvedVirtualPath(for: normalizedVirtualPath).resolvedRealPath
        var isDirectory: ObjCBool = false

        if !FileManager.default.fileExists(atPath: realPath, isDirectory: &isDirectory) {
            App.serverController.replyError(
                client: client,
                error: "wired.error.file_not_found",
                message: message
            )
            return
        }

        let isSubscribed = subscriptionsQueue.sync { () -> Bool in
            let subscribed = subscribedVirtualPathsByClient[client.userID]?[realPath]?
                .contains(normalizedVirtualPath) ?? false
            if subscribed {
                subscribedVirtualPathsByClient[client.userID]?[realPath]?
                    .remove(normalizedVirtualPath)
                if subscribedVirtualPathsByClient[client.userID]?[realPath]?.isEmpty == true {
                    subscribedVirtualPathsByClient[client.userID]?[realPath] = nil
                    subscribedRealPathsByClient[client.userID]?.remove(realPath)
                }
            }
            return subscribed
        }

        if !isSubscribed {
            App.serverController.replyError(
                client: client,
                error: "wired.error.not_subscribed",
                message: message
            )
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

    func notify(path: String, messageName: String, removeSubscriptionAfterNotify: Bool) {
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

    func removeMetadata(forPath path: String) {
        do {
            try metadataStore.removeComment(forPath: path)
        } catch {
            Logger.warning("Could not remove comment metadata for \(path): \(error)")
        }

        do {
            try metadataStore.removeLabel(forPath: path)
        } catch {
            Logger.warning("Could not remove label metadata for \(path): \(error)")
        }
    }

    func moveMetadata(from source: String, to destination: String) {
        do {
            try metadataStore.moveComment(from: source, to: destination)
        } catch {
            Logger.warning("Could not move comment metadata \(source) -> \(destination): \(error)")
        }

        do {
            try metadataStore.moveLabel(from: source, to: destination)
        } catch {
            Logger.warning("Could not move label metadata \(source) -> \(destination): \(error)")
        }
    }
}
