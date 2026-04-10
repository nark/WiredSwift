import Foundation
import WiredSwift
import CryptoSwift
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif
#if canImport(ImageIO)
import ImageIO
#endif

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public struct AttachmentDescriptor: Codable, Equatable {
    public let id: String
    public let name: String
    public let mediaType: String
    public let size: UInt64
    public let sha256: String
    public let inlinePreview: Bool
    public let width: UInt32?
    public let height: UInt32?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case mediaType = "media_type"
        case size
        case sha256
        case inlinePreview = "inline_preview"
        case width
        case height
    }
}

enum AttachmentScopeKind: String {
    case chat
    case directMessage = "direct_message"
    case board
    case thread
    case post
}

struct AttachmentTarget {
    let kind: AttachmentScopeKind
    let chatID: UInt32?
    let recipientID: UInt32?
    let boardPath: String?
    let threadUUID: String?
    let postUUID: String?
}

private enum AttachmentState {
    case staging
    case completed
    case linked
}

private struct StagedAttachment {
    var id: String
    var ownerLogin: String
    var ownerUserID: UInt32
    var target: AttachmentTarget
    var name: String
    var mediaType: String
    var expectedSize: UInt64
    var expectedSha256: String
    var width: UInt32?
    var height: UInt32?
    var filePath: String
    var receivedBytes: UInt64
    var createdAt: Date
    var expiresAt: Date
    var state: AttachmentState
}

private struct EphemeralAttachment {
    var descriptor: AttachmentDescriptor
    var ownerLogin: String
    var ownerUserID: UInt32
    var target: AttachmentTarget
    var filePath: String
    var createdAt: Date
    var expiresAt: Date
}

public final class AttachmentsController {
    static let maxAttachmentSizeBytes: UInt64 = 16 * 1_024 * 1_024
    static let maxPreviewSizeBytes: UInt64 = 1 * 1_024 * 1_024
    static let maxAttachmentsPerMessage = 8
    static let maxTotalAttachmentBytesPerMessage: UInt64 = 32 * 1_024 * 1_024
    static let maxPersistentBoardBytes: UInt64 = 512 * 1_024 * 1_024
    static let chunkSizeLimitBytes = 256 * 1_024
    static let stagingTTL: TimeInterval = 10 * 60
    static let chatEphemeralTTL: TimeInterval = 10 * 60
    static let directMessageEphemeralTTL: TimeInterval = 30 * 24 * 60 * 60

    private let workingDirectoryPath: String
    private let databasePath: String
    private let fileManager: FileManager

    private let stagingDirectory: String
    private let ephemeralDirectory: String
    private let persistentDirectory: String

    private let stateLock = NSLock()
    private var stagedAttachments: [String: StagedAttachment] = [:]
    private var ephemeralAttachments: [String: EphemeralAttachment] = [:]

    private var cleanupTimer: DispatchSourceTimer?
    private let cleanupQueue = DispatchQueue(label: "wired.attachments.cleanup")

    public init(workingDirectoryPath: String, databasePath: String, fileManager: FileManager = .default) {
        self.workingDirectoryPath = workingDirectoryPath
        self.databasePath = databasePath
        self.fileManager = fileManager
        let attachmentsBase = workingDirectoryPath.stringByAppendingPathComponent(path: "attachments")
        self.stagingDirectory = attachmentsBase.stringByAppendingPathComponent(path: "staging")
        self.ephemeralDirectory = attachmentsBase.stringByAppendingPathComponent(path: "ephemeral")
        self.persistentDirectory = attachmentsBase.stringByAppendingPathComponent(path: "store")
        prepareStorageDirectories()
        createTablesIfNeeded()
        startCleanupTimer()
    }

    deinit {
        cleanupTimer?.cancel()
    }

    public func createAttachment(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.attachment.upload") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let name = message.string(forField: "wired.attachment.name"),
            let mediaType = message.string(forField: "wired.attachment.media_type"),
            let size = message.uint64(forField: "wired.attachment.size"),
            let sha256 = message.string(forField: "wired.attachment.sha256"),
            !name.isEmpty,
            !mediaType.isEmpty,
            !sha256.isEmpty,
            size > 0,
            size <= Self.maxAttachmentSizeBytes
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard isHexSHA256(sha256) else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let target = resolveTarget(client: client, message: message, forCreate: true) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let id = UUID().uuidString.uppercased()
        let filePath = stagingDirectory.stringByAppendingPathComponent(path: "\(id).bin")
        fileManager.createFile(atPath: filePath, contents: Data())

        let staged = StagedAttachment(
            id: id,
            ownerLogin: user.username ?? "",
            ownerUserID: client.userID,
            target: target,
            name: name,
            mediaType: mediaType,
            expectedSize: size,
            expectedSha256: sha256.lowercased(),
            width: message.uint32(forField: "wired.attachment.width"),
            height: message.uint32(forField: "wired.attachment.height"),
            filePath: filePath,
            receivedBytes: 0,
            createdAt: Date(),
            expiresAt: Date().addingTimeInterval(Self.stagingTTL),
            state: .staging
        )

        stateLock.lock()
        stagedAttachments[id.lowercased()] = staged
        stateLock.unlock()

        let reply = P7Message(withName: "wired.attachment.created", spec: message.spec)
        reply.addParameter(field: "wired.attachment.id", value: id)
        reply.addParameter(field: "wired.attachment.offset", value: UInt64(0))
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    public func uploadAttachment(client: Client, message: P7Message) {
        guard client.user != nil else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let id = message.uuid(forField: "wired.attachment.id")?.lowercased(),
            let offset = message.uint64(forField: "wired.attachment.offset"),
            let data = message.data(forField: "wired.attachment.data"),
            !data.isEmpty,
            data.count <= Self.chunkSizeLimitBytes
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard var staged = lookupOwnedStagedAttachment(id: id, client: client), staged.state == .staging else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard offset == staged.receivedBytes else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        let newSize = staged.receivedBytes + UInt64(data.count)
        guard newSize <= staged.expectedSize else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard append(data: data, toPath: staged.filePath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        staged.receivedBytes = newSize
        staged.expiresAt = Date().addingTimeInterval(Self.stagingTTL)

        stateLock.lock()
        stagedAttachments[id] = staged
        stateLock.unlock()

        App.serverController.replyOK(client: client, message: message)
    }

    public func completeAttachment(client: Client, message: P7Message) {
        guard client.user != nil else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let id = message.uuid(forField: "wired.attachment.id")?.lowercased() else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard var staged = lookupOwnedStagedAttachment(id: id, client: client), staged.state == .staging else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard staged.receivedBytes == staged.expectedSize,
              let data = fileManager.contents(atPath: staged.filePath),
              UInt64(data.count) == staged.expectedSize
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let actualSha256 = data.sha256().toHexString()
        guard actualSha256.lowercased() == staged.expectedSha256 else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let derived = deriveInlinePreviewMetadata(data: data, mediaType: staged.mediaType)
        if staged.width == nil { staged.width = derived.width }
        if staged.height == nil { staged.height = derived.height }
        staged.state = .completed
        staged.expiresAt = Date().addingTimeInterval(Self.stagingTTL)

        switch staged.target.kind {
        case .chat, .directMessage:
            let finalPath = ephemeralDirectory.stringByAppendingPathComponent(path: "\(staged.id).bin")
            do {
                if fileManager.fileExists(atPath: finalPath) {
                    try fileManager.removeItem(atPath: finalPath)
                }
                try fileManager.moveItem(atPath: staged.filePath, toPath: finalPath)
            } catch {
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                return
            }

            let descriptor = AttachmentDescriptor(
                id: staged.id,
                name: staged.name,
                mediaType: staged.mediaType,
                size: staged.expectedSize,
                sha256: staged.expectedSha256,
                inlinePreview: derived.inlinePreview,
                width: staged.width,
                height: staged.height
            )

            switch staged.target.kind {
            case .chat:
                let ephemeral = EphemeralAttachment(
                    descriptor: descriptor,
                    ownerLogin: staged.ownerLogin,
                    ownerUserID: staged.ownerUserID,
                    target: staged.target,
                    filePath: finalPath,
                    createdAt: staged.createdAt,
                    expiresAt: Date().addingTimeInterval(Self.ephemeralTTL(for: staged.target))
                )

                stateLock.lock()
                stagedAttachments.removeValue(forKey: id)
                ephemeralAttachments[id] = ephemeral
                stateLock.unlock()

            case .directMessage:
                guard let recipientID = staged.target.recipientID,
                      let recipientLogin = App.clientsController.user(withID: recipientID)?.user?.username,
                      !recipientLogin.isEmpty,
                      upsertMessageAttachmentRow(
                        descriptor: descriptor,
                        ownerUserID: staged.ownerUserID,
                        recipientID: recipientID,
                        ownerLogin: staged.ownerLogin,
                        recipientLogin: recipientLogin,
                        createdAt: staged.createdAt,
                        expiresAt: Date().addingTimeInterval(Self.ephemeralTTL(for: staged.target))
                      )
                else {
                    App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                    return
                }

                stateLock.lock()
                stagedAttachments.removeValue(forKey: id)
                ephemeralAttachments.removeValue(forKey: id)
                stateLock.unlock()

            case .board, .thread, .post:
                break
            }

        case .board, .thread, .post:
            stateLock.lock()
            stagedAttachments[id] = staged
            stateLock.unlock()
        }

        let reply = P7Message(withName: "wired.attachment.completed", spec: message.spec)
        reply.addParameter(field: "wired.attachment.id", value: staged.id)
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    public func abortAttachment(client: Client, message: P7Message) {
        guard client.user != nil else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let id = message.uuid(forField: "wired.attachment.id")?.lowercased() else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        stateLock.lock()
        let staged = stagedAttachments.removeValue(forKey: id)
        let ephemeral = ephemeralAttachments[id]
        stateLock.unlock()

        guard let staged else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard staged.ownerUserID == client.userID, ephemeral == nil else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        try? fileManager.removeItem(atPath: staged.filePath)
        App.serverController.replyOK(client: client, message: message)
    }

    public func getPreview(client: Client, message: P7Message) {
        guard client.user != nil else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let descriptor = resolveReadableDescriptor(client: client, message: message),
              descriptor.inlinePreview,
              descriptor.size <= Self.maxPreviewSizeBytes
        else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        guard let data = readAttachmentData(id: descriptor.id),
              let derived = deriveInlinePreviewData(data: data, mediaType: descriptor.mediaType)
        else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let reply = P7Message(withName: "wired.attachment.preview", spec: message.spec)
        reply.addParameter(field: "wired.attachment.id", value: descriptor.id)
        reply.addParameter(field: "wired.attachment.data", value: derived)
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    public func getData(client: Client, message: P7Message) {
        guard client.user != nil else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let id = message.uuid(forField: "wired.attachment.id"),
            let offset = message.uint64(forField: "wired.attachment.offset")
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let requestedLength = message.uint32(forField: "wired.attachment.length").map { Int($0) } ?? Self.chunkSizeLimitBytes
        let clampedLength = min(max(1, requestedLength), Self.chunkSizeLimitBytes)

        guard resolveReadableDescriptor(id: id, client: client) != nil,
              let data = readAttachmentData(id: id),
              offset <= UInt64(data.count)
        else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        let start = Int(offset)
        let end = min(data.count, start + clampedLength)
        let chunk = data.subdata(in: start..<end)
        let reply = P7Message(withName: "wired.attachment.data", spec: message.spec)
        reply.addParameter(field: "wired.attachment.id", value: id.uppercased())
        reply.addParameter(field: "wired.attachment.offset", value: offset)
        reply.addParameter(field: "wired.attachment.data", value: chunk)
        reply.addParameter(field: "wired.attachment.complete", value: end >= data.count)
        App.serverController.reply(client: client, reply: reply, message: message)
    }

    public func attachmentIDsFromMessage(_ message: P7Message) -> [String]? {
        guard message.parameterKeys.contains("wired.attachment.ids") else { return nil }
        return (message.stringList(forField: "wired.attachment.ids") ?? []).map { $0.uppercased() }
    }

    public func descriptorsForMessageAttachmentIDs(_ ids: [String],
                                                  client: Client,
                                                  chatID: UInt32? = nil,
                                                  recipientID: UInt32? = nil,
                                                  boardPath: String? = nil,
                                                  threadUUID: String? = nil,
                                                  postUUID: String? = nil) -> [AttachmentDescriptor]? {
        guard ids.count <= Self.maxAttachmentsPerMessage else { return nil }

        var descriptors: [AttachmentDescriptor] = []
        var totalSize: UInt64 = 0
        var seen = Set<String>()

        for rawID in ids {
            let id = rawID.lowercased()
            guard !seen.contains(id) else { return nil }
            seen.insert(id)

            if let ephemeral = lookupOwnedOrReadableEphemeral(id: id, client: client) {
                guard matches(target: ephemeral.target, chatID: chatID, recipientID: recipientID, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID) else {
                    return nil
                }
                totalSize += ephemeral.descriptor.size
                descriptors.append(ephemeral.descriptor)
                continue
            }

            if let messageDescriptor = messageAttachmentDescriptor(id: id, client: client) {
                guard recipientID != nil else { return nil }
                totalSize += messageDescriptor.size
                descriptors.append(messageDescriptor)
                continue
            }

            if let persistent = boardAttachmentDescriptor(id: id) {
                guard matchesPersistentBoardAttachment(id: id, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID, client: client) else {
                    return nil
                }
                totalSize += persistent.size
                descriptors.append(persistent)
                continue
            }

            guard let staged = lookupOwnedStagedAttachment(id: id, client: client), staged.state == .completed else {
                return nil
            }
            guard matches(target: staged.target, chatID: chatID, recipientID: recipientID, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID) else {
                return nil
            }
            let derived = deriveInlinePreviewMetadata(path: staged.filePath, mediaType: staged.mediaType)
            let descriptor = AttachmentDescriptor(
                id: staged.id,
                name: staged.name,
                mediaType: staged.mediaType,
                size: staged.expectedSize,
                sha256: staged.expectedSha256,
                inlinePreview: derived.inlinePreview,
                width: staged.width ?? derived.width,
                height: staged.height ?? derived.height
            )
            totalSize += descriptor.size
            descriptors.append(descriptor)
        }

        guard totalSize <= Self.maxTotalAttachmentBytesPerMessage else { return nil }
        return descriptors
    }

    public func descriptorStrings(_ descriptors: [AttachmentDescriptor]) -> [String] {
        descriptors.compactMap { descriptor in
            guard let data = try? JSONEncoder().encode(descriptor),
                  let string = String(data: data, encoding: .utf8) else { return nil }
            return string
        }
    }

    public func linkBoardThreadAttachments(ids: [String], boardPath: String, threadUUID: String, ownerLogin: String) -> Bool {
        let existing = boardAttachmentIDsForThread(threadUUID)
        return replaceBoardAttachments(existingIDs: existing, newIDs: ids, boardPath: boardPath, threadUUID: threadUUID, postUUID: nil, ownerLogin: ownerLogin)
    }

    public func linkBoardPostAttachments(ids: [String], boardPath: String, threadUUID: String, postUUID: String, ownerLogin: String) -> Bool {
        let existing = boardAttachmentIDsForPost(postUUID)
        return replaceBoardAttachments(existingIDs: existing, newIDs: ids, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID, ownerLogin: ownerLogin)
    }

    public func descriptorsForBoardThread(_ threadUUID: String) -> [AttachmentDescriptor] {
        boardAttachmentDescriptors(where: "thread_uuid = ? AND post_uuid IS NULL", arguments: [threadUUID])
    }

    public func descriptorsForBoardPost(_ postUUID: String) -> [AttachmentDescriptor] {
        boardAttachmentDescriptors(where: "post_uuid = ?", arguments: [postUUID])
    }

    public func deleteBoardAttachments(forThread threadUUID: String) {
        let ids = boardAttachmentIDsForThreadIncludingPosts(threadUUID)
        deleteBoardAttachmentRows(ids: ids)
        purgeUnreferencedStoredBlobs()
    }

    public func deleteBoardAttachments(forPost postUUID: String) {
        let ids = boardAttachmentIDsForPost(postUUID)
        deleteBoardAttachmentRows(ids: ids)
        purgeUnreferencedStoredBlobs()
    }

    public func refreshEphemeralAttachmentLifetime(ids: [String]) {
        stateLock.lock()
        for rawID in ids {
            let id = rawID.lowercased()
            if var ephemeral = ephemeralAttachments[id] {
                ephemeral.expiresAt = Date().addingTimeInterval(Self.ephemeralTTL(for: ephemeral.target))
                ephemeralAttachments[id] = ephemeral
            }
            _ = refreshMessageAttachmentLifetime(id: id)
        }
        stateLock.unlock()
    }

    private func prepareStorageDirectories() {
        for path in [stagingDirectory, ephemeralDirectory, persistentDirectory] {
            try? fileManager.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
    }

    private func startCleanupTimer() {
        let timer = DispatchSource.makeTimerSource(queue: cleanupQueue)
        timer.schedule(deadline: .now() + 30, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.cleanupExpiredAttachments()
        }
        cleanupTimer = timer
        timer.resume()
    }

    private func cleanupExpiredAttachments() {
        let now = Date()
        var stagedToDelete: [String] = []
        var ephemeralToDelete: [String] = []
        var stagedIDsToRemove: [String] = []
        var ephemeralIDsToRemove: [String] = []

        stateLock.lock()
        for (id, staged) in stagedAttachments where staged.expiresAt <= now {
            stagedToDelete.append(staged.filePath)
            stagedIDsToRemove.append(id)
        }
        for (id, ephemeral) in ephemeralAttachments where ephemeral.expiresAt <= now {
            ephemeralToDelete.append(ephemeral.filePath)
            ephemeralIDsToRemove.append(id)
        }
        for id in stagedIDsToRemove {
            stagedAttachments.removeValue(forKey: id)
        }
        for id in ephemeralIDsToRemove {
            ephemeralAttachments.removeValue(forKey: id)
        }
        stateLock.unlock()

        for path in stagedToDelete + ephemeralToDelete {
            try? fileManager.removeItem(atPath: path)
        }

        cleanupExpiredMessageAttachments(now: now)
    }

    private func createTablesIfNeeded() {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }

        let statements = [
            """
            CREATE TABLE IF NOT EXISTS board_attachments (
              id TEXT PRIMARY KEY,
              board_path TEXT NOT NULL,
              thread_uuid TEXT,
              post_uuid TEXT,
              name TEXT NOT NULL,
              media_type TEXT NOT NULL,
              size INTEGER NOT NULL,
              sha256 TEXT NOT NULL,
              inline_preview INTEGER NOT NULL,
              width INTEGER,
              height INTEGER,
              owner_login TEXT NOT NULL,
              created_at REAL NOT NULL
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_board_attachments_thread ON board_attachments(thread_uuid);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_board_attachments_post ON board_attachments(post_uuid);
            """,
            """
            CREATE TABLE IF NOT EXISTS message_attachments (
              id TEXT PRIMARY KEY,
              owner_user_id INTEGER NOT NULL,
              recipient_id INTEGER NOT NULL,
              owner_login TEXT,
              recipient_login TEXT,
              name TEXT NOT NULL,
              media_type TEXT NOT NULL,
              size INTEGER NOT NULL,
              sha256 TEXT NOT NULL,
              inline_preview INTEGER NOT NULL,
              width INTEGER,
              height INTEGER,
              created_at REAL NOT NULL,
              expires_at REAL NOT NULL
            );
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_message_attachments_recipient ON message_attachments(recipient_id);
            """,
            """
            CREATE INDEX IF NOT EXISTS idx_message_attachments_expires ON message_attachments(expires_at);
            """
        ]

        for sql in statements {
            sqlite3_exec(db, sql, nil, nil, nil)
        }

        let alterStatements = [
            "ALTER TABLE message_attachments ADD COLUMN owner_login TEXT;",
            "ALTER TABLE message_attachments ADD COLUMN recipient_login TEXT;"
        ]

        for sql in alterStatements {
            sqlite3_exec(db, sql, nil, nil, nil)
        }
    }

    private func lookupOwnedStagedAttachment(id: String, client: Client) -> StagedAttachment? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let staged = stagedAttachments[id], staged.ownerUserID == client.userID else { return nil }
        return staged
    }

    private func lookupOwnedOrReadableEphemeral(id: String, client: Client) -> EphemeralAttachment? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let ephemeral = ephemeralAttachments[id], canRead(ephemeral: ephemeral, client: client) else { return nil }
        return ephemeral
    }

    private func canRead(ephemeral: EphemeralAttachment, client: Client) -> Bool {
        switch ephemeral.target.kind {
        case .chat:
            guard let chatID = ephemeral.target.chatID,
                  let chat = App.chatsController.chat(withID: chatID) else { return false }
            return chat.client(withID: client.userID) != nil
        case .directMessage:
            guard let recipientID = ephemeral.target.recipientID else { return false }
            return client.userID == ephemeral.ownerUserID || client.userID == recipientID
        case .board, .thread, .post:
            return false
        }
    }

    private func resolveTarget(client: Client, message: P7Message, forCreate _: Bool) -> AttachmentTarget? {
        guard let user = client.user else { return nil }

        if let chatID = message.uint32(forField: "wired.chat.id") {
            guard let chat = App.chatsController.chat(withID: chatID), chat.client(withID: client.userID) != nil else { return nil }
            return AttachmentTarget(kind: .chat, chatID: chatID, recipientID: nil, boardPath: nil, threadUUID: nil, postUUID: nil)
        }

        if let recipientID = message.uint32(forField: "wired.user.id") {
            guard user.hasPrivilege(name: "wired.account.message.send_messages"),
                  App.clientsController.user(withID: recipientID) != nil
            else { return nil }
            return AttachmentTarget(kind: .directMessage, chatID: nil, recipientID: recipientID, boardPath: nil, threadUUID: nil, postUUID: nil)
        }

        if let postUUID = message.uuid(forField: "wired.board.post"), !postUUID.isEmpty,
           let existing = App.boardsController.posts[postUUID.lowercased()],
           let thread = App.boardsController.getThread(uuid: existing.thread),
           let board = App.boardsController.getBoardInfo(path: thread.board),
           board.canWrite(user: user.username ?? "", group: user.group ?? "") {
            return AttachmentTarget(kind: .post, chatID: nil, recipientID: nil, boardPath: board.path, threadUUID: thread.uuid, postUUID: postUUID)
        }

        if let threadUUID = message.uuid(forField: "wired.board.thread"), !threadUUID.isEmpty,
           let thread = App.boardsController.getThread(uuid: threadUUID),
           let board = App.boardsController.getBoardInfo(path: thread.board),
           board.canWrite(user: user.username ?? "", group: user.group ?? "") {
            return AttachmentTarget(kind: .thread, chatID: nil, recipientID: nil, boardPath: board.path, threadUUID: threadUUID, postUUID: nil)
        }

        if let boardPath = message.string(forField: "wired.board.board"),
           let board = App.boardsController.getBoardInfo(path: boardPath),
           board.canWrite(user: user.username ?? "", group: user.group ?? "") {
            return AttachmentTarget(kind: .board, chatID: nil, recipientID: nil, boardPath: boardPath, threadUUID: nil, postUUID: nil)
        }

        return nil
    }

    private func matches(target: AttachmentTarget,
                         chatID: UInt32?,
                         recipientID: UInt32?,
                         boardPath: String?,
                         threadUUID: String?,
                         postUUID: String?) -> Bool {
        switch target.kind {
        case .chat:
            return target.chatID == chatID
        case .directMessage:
            return target.recipientID == recipientID
        case .board:
            return target.boardPath == boardPath
        case .thread:
            return target.threadUUID == threadUUID
        case .post:
            return target.postUUID == postUUID
        }
    }

    private static func ephemeralTTL(for target: AttachmentTarget) -> TimeInterval {
        switch target.kind {
        case .chat:
            return Self.chatEphemeralTTL
        case .directMessage:
            return Self.directMessageEphemeralTTL
        case .board, .thread, .post:
            return Self.chatEphemeralTTL
        }
    }

    private func append(data: Data, toPath path: String) -> Bool {
        guard let handle = FileHandle(forWritingAtPath: path) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            handle.write(data)
            return true
        } catch {
            return false
        }
    }

    private func deriveInlinePreviewMetadata(data: Data, mediaType: String) -> (inlinePreview: Bool, width: UInt32?, height: UInt32?) {
        guard mediaType.lowercased().hasPrefix("image/"),
              UInt64(data.count) <= Self.maxPreviewSizeBytes
        else {
            return (false, nil, nil)
        }
        return imageDimensions(data: data).map { (true, $0.width, $0.height) } ?? (true, nil, nil)
    }

    private func deriveInlinePreviewMetadata(path: String, mediaType: String) -> (inlinePreview: Bool, width: UInt32?, height: UInt32?) {
        guard let data = fileManager.contents(atPath: path) else {
            return (false, nil, nil)
        }
        return deriveInlinePreviewMetadata(data: data, mediaType: mediaType)
    }

    private func deriveInlinePreviewData(data: Data, mediaType: String) -> Data? {
        guard mediaType.lowercased().hasPrefix("image/"),
              UInt64(data.count) <= Self.maxPreviewSizeBytes else { return nil }
        return data
    }

    private func imageDimensions(data: Data) -> (width: UInt32, height: UInt32)? {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        return (UInt32(width.uint32Value), UInt32(height.uint32Value))
        #else
        return nil
        #endif
    }

    private func isHexSHA256(_ string: String) -> Bool {
        string.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
    }

    private func resolveReadableDescriptor(client: Client, message: P7Message) -> AttachmentDescriptor? {
        guard let id = message.uuid(forField: "wired.attachment.id") else { return nil }
        return resolveReadableDescriptor(id: id, client: client)
    }

    private func resolveReadableDescriptor(id: String, client: Client) -> AttachmentDescriptor? {
        if let ephemeral = lookupOwnedOrReadableEphemeral(id: id.lowercased(), client: client) {
            return ephemeral.descriptor
        }
        if let descriptor = messageAttachmentDescriptor(id: id.lowercased(), client: client) {
            return descriptor
        }
        guard let descriptor = boardAttachmentDescriptor(id: id.lowercased()),
              matchesPersistentBoardAttachment(id: id.lowercased(), boardPath: nil, threadUUID: nil, postUUID: nil, client: client) else {
            return nil
        }
        return descriptor
    }

    private func readAttachmentData(id: String) -> Data? {
        let normalized = id.lowercased()
        stateLock.lock()
        let ephemeral = ephemeralAttachments[normalized]
        stateLock.unlock()
        if let ephemeral {
            return fileManager.contents(atPath: ephemeral.filePath)
        }
        if let path = messageAttachmentPath(id: normalized) {
            return fileManager.contents(atPath: path)
        }
        if let descriptor = boardAttachmentDescriptor(id: normalized) {
            let path = persistentPath(forSHA256: descriptor.sha256)
            return fileManager.contents(atPath: path)
        }
        return nil
    }

    private func persistentPath(forSHA256 sha256: String) -> String {
        let prefix = String(sha256.prefix(2))
        let dir = persistentDirectory.stringByAppendingPathComponent(path: prefix)
        try? fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        return dir.stringByAppendingPathComponent(path: sha256.lowercased())
    }

    private func messageAttachmentFilePath(for id: String) -> String {
        ephemeralDirectory.stringByAppendingPathComponent(path: "\(id.uppercased()).bin")
    }

    private func messageAttachmentPath(id: String) -> String? {
        let path = messageAttachmentFilePath(for: id)
        return fileManager.fileExists(atPath: path) ? path : nil
    }

    private func messageAttachmentDescriptor(id: String, client: Client) -> AttachmentDescriptor? {
        guard let login = client.user?.username, !login.isEmpty else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, name, media_type, size, sha256, inline_preview, width, height
        FROM message_attachments
        WHERE lower(id) = lower(?)
          AND expires_at > ?
          AND (
            lower(owner_login) = lower(?)
            OR lower(recipient_login) = lower(?)
            OR owner_user_id = ?
            OR recipient_id = ?
          )
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, login, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 4, login, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 5, sqlite3_int64(client.userID))
        sqlite3_bind_int64(statement, 6, sqlite3_int64(client.userID))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return AttachmentDescriptor(
            id: String(cString: sqlite3_column_text(statement, 0)),
            name: String(cString: sqlite3_column_text(statement, 1)),
            mediaType: String(cString: sqlite3_column_text(statement, 2)),
            size: UInt64(sqlite3_column_int64(statement, 3)),
            sha256: String(cString: sqlite3_column_text(statement, 4)),
            inlinePreview: sqlite3_column_int(statement, 5) == 1,
            width: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 6)),
            height: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 7))
        )
    }

    private func boardAttachmentDescriptor(id: String) -> AttachmentDescriptor? {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return nil }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, name, media_type, size, sha256, inline_preview, width, height
        FROM board_attachments WHERE lower(id) = lower(?)
        LIMIT 1;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return AttachmentDescriptor(
            id: String(cString: sqlite3_column_text(statement, 0)),
            name: String(cString: sqlite3_column_text(statement, 1)),
            mediaType: String(cString: sqlite3_column_text(statement, 2)),
            size: UInt64(sqlite3_column_int64(statement, 3)),
            sha256: String(cString: sqlite3_column_text(statement, 4)),
            inlinePreview: sqlite3_column_int(statement, 5) == 1,
            width: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 6)),
            height: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 7))
        )
    }

    private func boardAttachmentDescriptors(where clause: String, arguments: [String]) -> [AttachmentDescriptor] {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        let sql = """
        SELECT id, name, media_type, size, sha256, inline_preview, width, height
        FROM board_attachments
        WHERE \(clause)
        ORDER BY created_at ASC;
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, SQLITE_TRANSIENT)
        }

        var result: [AttachmentDescriptor] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            result.append(
                AttachmentDescriptor(
                    id: String(cString: sqlite3_column_text(statement, 0)),
                    name: String(cString: sqlite3_column_text(statement, 1)),
                    mediaType: String(cString: sqlite3_column_text(statement, 2)),
                    size: UInt64(sqlite3_column_int64(statement, 3)),
                    sha256: String(cString: sqlite3_column_text(statement, 4)),
                    inlinePreview: sqlite3_column_int(statement, 5) == 1,
                    width: sqlite3_column_type(statement, 6) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 6)),
                    height: sqlite3_column_type(statement, 7) == SQLITE_NULL ? nil : UInt32(sqlite3_column_int64(statement, 7))
                )
            )
        }
        return result
    }

    private func upsertMessageAttachmentRow(
        descriptor: AttachmentDescriptor,
        ownerUserID: UInt32,
        recipientID: UInt32,
        ownerLogin: String,
        recipientLogin: String,
        createdAt: Date,
        expiresAt: Date
    ) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return false }
        defer { sqlite3_close(db) }

        let sql = """
        INSERT OR REPLACE INTO message_attachments
        (id, owner_user_id, recipient_id, owner_login, recipient_login, name, media_type, size, sha256, inline_preview, width, height, created_at, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, descriptor.id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 2, sqlite3_int64(ownerUserID))
        sqlite3_bind_int64(statement, 3, sqlite3_int64(recipientID))
        sqlite3_bind_text(statement, 4, ownerLogin, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 5, recipientLogin, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, descriptor.name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 7, descriptor.mediaType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 8, sqlite3_int64(descriptor.size))
        sqlite3_bind_text(statement, 9, descriptor.sha256, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 10, descriptor.inlinePreview ? 1 : 0)
        if let width = descriptor.width {
            sqlite3_bind_int64(statement, 11, sqlite3_int64(width))
        } else {
            sqlite3_bind_null(statement, 11)
        }
        if let height = descriptor.height {
            sqlite3_bind_int64(statement, 12, sqlite3_int64(height))
        } else {
            sqlite3_bind_null(statement, 12)
        }
        sqlite3_bind_double(statement, 13, createdAt.timeIntervalSince1970)
        sqlite3_bind_double(statement, 14, expiresAt.timeIntervalSince1970)

        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func refreshMessageAttachmentLifetime(id: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return false }
        defer { sqlite3_close(db) }

        let sql = """
        UPDATE message_attachments
        SET expires_at = ?
        WHERE lower(id) = lower(?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, Date().addingTimeInterval(Self.directMessageEphemeralTTL).timeIntervalSince1970)
        sqlite3_bind_text(statement, 2, id, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func cleanupExpiredMessageAttachments(now: Date) {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }

        let selectSQL = "SELECT id FROM message_attachments WHERE expires_at <= ?;"
        var selectStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, selectSQL, -1, &selectStatement, nil) == SQLITE_OK, let selectStatement else { return }
        sqlite3_bind_double(selectStatement, 1, now.timeIntervalSince1970)

        var ids: [String] = []
        while sqlite3_step(selectStatement) == SQLITE_ROW, let text = sqlite3_column_text(selectStatement, 0) {
            ids.append(String(cString: text))
        }
        sqlite3_finalize(selectStatement)

        for id in ids {
            try? fileManager.removeItem(atPath: messageAttachmentFilePath(for: id))
        }

        let deleteSQL = "DELETE FROM message_attachments WHERE expires_at <= ?;"
        var deleteStatement: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &deleteStatement, nil) == SQLITE_OK, let deleteStatement else { return }
        defer { sqlite3_finalize(deleteStatement) }
        sqlite3_bind_double(deleteStatement, 1, now.timeIntervalSince1970)
        sqlite3_step(deleteStatement)
    }

    private func boardAttachmentIDsForThread(_ threadUUID: String) -> [String] {
        boardAttachmentIDs(where: "thread_uuid = ? AND post_uuid IS NULL", arguments: [threadUUID])
    }

    private func boardAttachmentIDsForThreadIncludingPosts(_ threadUUID: String) -> [String] {
        boardAttachmentIDs(where: "thread_uuid = ?", arguments: [threadUUID])
    }

    private func boardAttachmentIDsForPost(_ postUUID: String) -> [String] {
        boardAttachmentIDs(where: "post_uuid = ?", arguments: [postUUID])
    }

    private func boardAttachmentIDs(where clause: String, arguments: [String]) -> [String] {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return [] }
        defer { sqlite3_close(db) }

        let sql = "SELECT id FROM board_attachments WHERE \(clause);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return [] }
        defer { sqlite3_finalize(statement) }
        for (index, arg) in arguments.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), arg, -1, SQLITE_TRANSIENT)
        }
        var ids: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) {
            ids.append(String(cString: text))
        }
        return ids
    }

    private func replaceBoardAttachments(existingIDs: [String],
                                         newIDs: [String],
                                         boardPath: String,
                                         threadUUID: String,
                                         postUUID: String?,
                                         ownerLogin: String) -> Bool {
        var keep = Set(newIDs.map { $0.lowercased() })
        let toDelete = existingIDs.filter { !keep.contains($0.lowercased()) }
        if !toDelete.isEmpty {
            deleteBoardAttachmentRows(ids: toDelete)
        }

        for rawID in newIDs {
            let id = rawID.lowercased()
            if existingIDs.map({ $0.lowercased() }).contains(id) {
                keep.remove(id)
                continue
            }

            guard var staged = stagingAttachmentForBoardLink(id: id, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID) else {
                return false
            }

            let path = persistentPath(forSHA256: staged.expectedSha256)
            if !fileManager.fileExists(atPath: path) {
                do {
                    try fileManager.createDirectory(atPath: path.stringByDeletingLastPathComponent, withIntermediateDirectories: true)
                    try fileManager.moveItem(atPath: staged.filePath, toPath: path)
                } catch {
                    return false
                }
            } else {
                try? fileManager.removeItem(atPath: staged.filePath)
            }

            guard boardStorageAfterAdding(size: staged.expectedSize) <= Self.maxPersistentBoardBytes else {
                return false
            }

            let metadata = deriveInlinePreviewMetadata(path: path, mediaType: staged.mediaType)
            if !insertBoardAttachmentRow(id: staged.id,
                                         boardPath: boardPath,
                                         threadUUID: threadUUID,
                                         postUUID: postUUID,
                                         name: staged.name,
                                         mediaType: staged.mediaType,
                                         size: staged.expectedSize,
                                         sha256: staged.expectedSha256,
                                         inlinePreview: metadata.inlinePreview,
                                         width: staged.width ?? metadata.width,
                                         height: staged.height ?? metadata.height,
                                         ownerLogin: ownerLogin) {
                return false
            }

            staged.state = .linked
            stateLock.lock()
            stagedAttachments.removeValue(forKey: id)
            stateLock.unlock()
        }

        purgeUnreferencedStoredBlobs()
        return true
    }

    private func stagingAttachmentForBoardLink(id: String, boardPath: String, threadUUID: String, postUUID: String?) -> StagedAttachment? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard let staged = stagedAttachments[id], staged.state == .completed else { return nil }
        guard matches(target: staged.target, chatID: nil, recipientID: nil, boardPath: boardPath, threadUUID: threadUUID, postUUID: postUUID) ||
                (staged.target.kind == .board && staged.target.boardPath == boardPath)
        else { return nil }
        return staged
    }

    private func boardStorageAfterAdding(size: UInt64) -> UInt64 {
        totalBoardAttachmentBytes() + size
    }

    private func totalBoardAttachmentBytes() -> UInt64 {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return 0 }
        defer { sqlite3_close(db) }
        let sql = "SELECT COALESCE(SUM(size), 0) FROM board_attachments;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return 0 }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return UInt64(sqlite3_column_int64(statement, 0))
    }

    private func insertBoardAttachmentRow(id: String,
                                          boardPath: String,
                                          threadUUID: String,
                                          postUUID: String?,
                                          name: String,
                                          mediaType: String,
                                          size: UInt64,
                                          sha256: String,
                                          inlinePreview: Bool,
                                          width: UInt32?,
                                          height: UInt32?,
                                          ownerLogin: String) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return false }
        defer { sqlite3_close(db) }

        let sql = """
        INSERT OR REPLACE INTO board_attachments
        (id, board_path, thread_uuid, post_uuid, name, media_type, size, sha256, inline_preview, width, height, owner_login, created_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 2, boardPath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 3, threadUUID, -1, SQLITE_TRANSIENT)
        if let postUUID {
            sqlite3_bind_text(statement, 4, postUUID, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_text(statement, 5, name, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(statement, 6, mediaType, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(statement, 7, sqlite3_int64(size))
        sqlite3_bind_text(statement, 8, sha256, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(statement, 9, inlinePreview ? 1 : 0)
        if let width {
            sqlite3_bind_int64(statement, 10, sqlite3_int64(width))
        } else {
            sqlite3_bind_null(statement, 10)
        }
        if let height {
            sqlite3_bind_int64(statement, 11, sqlite3_int64(height))
        } else {
            sqlite3_bind_null(statement, 11)
        }
        sqlite3_bind_text(statement, 12, ownerLogin, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(statement, 13, Date().timeIntervalSince1970)
        return sqlite3_step(statement) == SQLITE_DONE
    }

    private func deleteBoardAttachmentRows(ids: [String]) {
        guard !ids.isEmpty else { return }
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }

        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let sql = "DELETE FROM board_attachments WHERE lower(id) IN (\(placeholders));"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), id.lowercased(), -1, SQLITE_TRANSIENT)
        }
        sqlite3_step(statement)
    }

    private func purgeUnreferencedStoredBlobs() {
        var referenced = Set<String>()
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return }
        defer { sqlite3_close(db) }

        let sql = "SELECT DISTINCT sha256 FROM board_attachments;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return }
        defer { sqlite3_finalize(statement) }

        while sqlite3_step(statement) == SQLITE_ROW, let sha = sqlite3_column_text(statement, 0) {
            referenced.insert(String(cString: sha).lowercased())
        }

        guard let prefixes = try? fileManager.contentsOfDirectory(atPath: persistentDirectory) else { return }
        for prefix in prefixes {
            let directory = persistentDirectory.stringByAppendingPathComponent(path: prefix)
            guard let names = try? fileManager.contentsOfDirectory(atPath: directory) else { continue }
            for name in names where !referenced.contains(name.lowercased()) {
                try? fileManager.removeItem(atPath: directory.stringByAppendingPathComponent(path: name))
            }
        }
    }

    private func matchesPersistentBoardAttachment(id: String,
                                                 boardPath: String?,
                                                 threadUUID: String?,
                                                 postUUID: String?,
                                                 client: Client) -> Bool {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else { return false }
        defer { sqlite3_close(db) }

        let sql = "SELECT board_path, thread_uuid, post_uuid FROM board_attachments WHERE lower(id) = lower(?) LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { return false }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(statement) == SQLITE_ROW else { return false }

        let recordBoardPath = String(cString: sqlite3_column_text(statement, 0))
        let recordThread = sqlite3_column_type(statement, 1) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 1))
        let recordPost = sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 2))

        guard let user = client.user,
              let board = App.boardsController.getBoardInfo(path: recordBoardPath),
              board.canRead(user: user.username ?? "", group: user.group ?? "")
        else { return false }

        if let boardPath {
            return recordBoardPath == boardPath && recordThread == threadUUID && recordPost == postUUID
        }

        return true
    }
}
