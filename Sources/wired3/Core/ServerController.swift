//
//  ServerController.swift
//  wired3
//
//  Created by Rafael Warnault on 16/03/2021.
//
//  Orchestration and routing for the Wired 3 server.
//  Domain-specific handlers live in the ServerController+*.swift extensions.
//

// swiftlint:disable cyclomatic_complexity type_body_length
import Foundation
import WiredSwift
import SocketSwift
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif

public protocol ServerDelegate: class {
    func clientDisconnected(client: Client)
    func disconnectClient(client: Client)

    func receiveMessage(client: Client, message: P7Message)
}

public class ServerController: ServerDelegate {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning: Bool = false
    public var delegates: [ServerDelegate] = []

    public var serverName: String = "Wired Server 3.0"
    public var serverDescription: String = "Welcome to this new Wired server"
    public var downloads: UInt32 = 0
    public var uploads: UInt32 = 0
    public var downloadSpeed: UInt32 = 0
    public var uploadSpeed: UInt32 = 0
    public var registerWithTrackers: Bool = false
    public var trackers: [String] = []
    public var trackerEnabled: Bool = false
    public var trackerCategories: [String] = []
    public var serverCompression: P7Socket.Compression = .ALL
    public var serverCipher: P7Socket.CipherType = .ALL
    public var serverChecksum: P7Socket.Checksum = .ALL

    /// SECURITY (A_009): Persistent server identity for TOFU. Set by AppController at startup.
    public var serverIdentity: ServerIdentity?

    private var socket: Socket!
    private let ecdh = ECDH()
    private let group = DispatchGroup()

    // SECURITY (FUZZ_002): Limit concurrent connections (pending + authenticated) to prevent
    // GCD thread-pool exhaustion from a connection flood before any authentication occurs.
    private let maxConcurrentConnections = 100
    private var pendingConnectionCount: Int = 0
    private let pendingConnectionLock = NSLock()

    var startTime: Date?

    // FINDING_A_001: Rate limiting for login attempts per IP
    struct LoginAttemptRecord {
        var failureCount: Int
        var bannedUntil: Date?
    }
    var loginAttempts: [String: LoginAttemptRecord] = [:]
    let loginAttemptsLock = NSLock()
    let maxLoginAttempts = 5
    let loginBanDuration: TimeInterval = 60

    // SECURITY (FINDING_C_012): Rate limiting for broadcast messages per user
    static let broadcastRateLimitPerMinute: Int = 5
    var broadcastTimestamps: [UInt32: [Date]] = [:]
    let broadcastRateLock = NSLock()

    // MARK: - Config helpers (used by init and reloadConfig)

    private func resolvedConfigPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }

        return App.workingDirectoryPath.stringByAppendingPathComponent(path: expanded)
    }

    var bannerFilePath: String? {
        guard let bannerPath = App.config["server", "banner"] as? String else {
            return nil
        }

        return resolvedConfigPath(bannerPath)
    }

    func readFileData(atPath path: String) -> Data? {
        let fd = path.withCString { open($0, O_RDONLY) }
        guard fd >= 0 else {
            return nil
        }
        defer { close(fd) }

        var result = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)

        while true {
            let readCount: Int
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Darwin.read(fd, base, rawBuffer.count)
            }
            #else
            readCount = buffer.withUnsafeMutableBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return -1 }
                return Glibc.read(fd, base, rawBuffer.count)
            }
            #endif
            if readCount > 0 {
                result.append(contentsOf: buffer.prefix(readCount))
            } else if readCount == 0 {
                break
            } else {
                return nil
            }
        }

        return result
    }

    private func normalizedAdvancedToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let mappedScalars = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar).uppercased())
            }
            return "_"
        }

        let normalized = String(mappedScalars)
        return normalized
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func parseCompressionSetting(_ raw: String) -> P7Socket.Compression? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = UInt32(value), intValue > 0 {
            let parsed = P7Socket.Compression(rawValue: intValue)
            let allowedMask = P7Socket.Compression.ALL.rawValue
            return (parsed.rawValue & ~allowedMask) == 0 ? parsed : nil
        }

        let normalized = normalizedAdvancedToken(value)
        switch normalized {
        case "NONE":
            return .NONE
        case "DEFLATE":
            return .DEFLATE
        case "LZFSE":
            return .LZFSE
        case "LZ4":
            return .LZ4
        case "COMPRESSION_ONLY":
            return .COMPRESSION_ONLY
        case "ALL":
            return .ALL
        default:
            return nil
        }
    }

    private func parseCipherSetting(_ raw: String) -> P7Socket.CipherType? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = UInt32(value), intValue > 0 {
            let parsed = P7Socket.CipherType(rawValue: intValue)
            let allowedMask = P7Socket.CipherType.ALL.rawValue
            guard (parsed.rawValue & ~allowedMask) == 0 else { return nil }
            // SECURITY (FINDING_A_015): reject NONE cipher to prevent plaintext credentials
            let withoutNone = P7Socket.CipherType(rawValue: parsed.rawValue & ~P7Socket.CipherType.NONE.rawValue)
            if withoutNone.rawValue == 0 {
                Logger.warning("Cipher NONE rejected — credentials must be encrypted")
                return nil
            }
            return withoutNone
        }

        let normalized = normalizedAdvancedToken(value)
        switch normalized {
        // SECURITY (FINDING_A_015): reject NONE cipher to prevent plaintext credentials
        case "NONE":
            Logger.warning("Cipher NONE rejected — credentials must be encrypted")
            return nil
        case "ECDH_AES256_SHA256", "ECDHE_ECDSA_AES256_SHA256":
            return .ECDH_AES256_SHA256
        case "ECDH_AES128_GCM", "ECDHE_ECDSA_AES128_GCM":
            return .ECDH_AES128_GCM
        case "ECDH_AES256_GCM", "ECDHE_ECDSA_AES256_GCM":
            return .ECDH_AES256_GCM
        case "ECDH_CHACHA20_POLY1305", "ECDHE_ECDSA_CHACHA20_POLY1305":
            return .ECDH_CHACHA20_POLY1305
        case "ECDH_XCHACHA20_POLY1305", "ECDHE_ECDSA_XCHACHA20_POLY1305":
            return .ECDH_XCHACHA20_POLY1305
        case "SECURE_ONLY":
            return .SECURE_ONLY
        case "ALL":
            return .ALL
        default:
            return nil
        }
    }

    private func parseChecksumSetting(_ raw: String) -> P7Socket.Checksum? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let intValue = UInt32(value), intValue > 0 {
            let parsed = P7Socket.Checksum(rawValue: intValue)
            let allowedMask = P7Socket.Checksum.ALL.rawValue
            return (parsed.rawValue & ~allowedMask) == 0 ? parsed : nil
        }

        let normalized = normalizedAdvancedToken(value)
        switch normalized {
        case "NONE":
            return .NONE
        case "SHA2_256":
            return .SHA2_256
        case "SHA2_384":
            return .SHA2_384
        case "SHA3_256":
            return .SHA3_256
        case "SHA3_384":
            return .SHA3_384
        case "HMAC_256":
            return .HMAC_256
        case "HMAC_384":
            return .HMAC_384
        case "SECURE_ONLY":
            return .SECURE_ONLY
        case "ALL":
            return .ALL
        default:
            return nil
        }
    }

    private func configRawString(_ section: String, _ key: String) -> String? {
        if let value = App.config[section, key] as? String { return value }
        if let value = App.config[section, key] as? Int { return String(value) }
        if let value = App.config[section, key] as? UInt32 { return String(value) }
        return nil
    }

    private func configUInt32(_ section: String, _ key: String) -> UInt32? {
        if let value = App.config[section, key] as? UInt32 { return value }
        if let value = App.config[section, key] as? Int, value >= 0 { return UInt32(value) }
        if let s = configRawString(section, key),
           let value = UInt32(s.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        return nil
    }

    private func configBool(_ section: String, _ key: String) -> Bool? {
        if let value = App.config[section, key] as? Bool { return value }
        if let s = configRawString(section, key)?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if ["1", "true", "yes", "on"].contains(s) { return true }
            if ["0", "false", "no", "off"].contains(s) { return false }
        }
        return nil
    }

    private func configStringList(_ section: String, _ key: String) -> [String]? {
        if let value = App.config[section, key] as? [String] {
            return value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        }
        if let value = configRawString(section, key)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !value.isEmpty {
            if value.hasPrefix("["),
               let data = value.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [Any] {
                let parsed = json
                    .compactMap { $0 as? String }
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !parsed.isEmpty { return parsed }
            }
            return value
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "[]\"")) }
                .filter { !$0.isEmpty }
        }
        return nil
    }

    // MARK: - Init

    public init(port: Int, spec: P7Spec) {
        self.port = port
        self.spec = spec

        if let string = configRawString("server", "name") {
            self.serverName = string
        }

        if let string = configRawString("server", "description") {
            self.serverDescription = string
        }

        if let number = configUInt32("transfers", "downloads") {
            self.downloads = number
        }

        if let number = configUInt32("transfers", "uploads") {
            self.uploads = number
        }

        if let number = configUInt32("transfers", "downloadSpeed") {
            self.downloadSpeed = number
        }

        if let number = configUInt32("transfers", "uploadSpeed") {
            self.uploadSpeed = number
        }

        if let value = configBool("settings", "register_with_trackers") {
            self.registerWithTrackers = value
        }
        if let value = configStringList("settings", "trackers") {
            self.trackers = value
        }
        if let value = configBool("tracker", "tracker") {
            self.trackerEnabled = value
        }
        if let value = configStringList("tracker", "categories") {
            self.trackerCategories = value
        }

        let compressionString = configRawString("advanced", "compression") ?? P7Socket.Compression.ALL.description
        guard let parsedCompression = parseCompressionSetting(compressionString) else {
            Logger.fatal("Invalid advanced.compression value '\(compressionString)'. Accepted values: ALL, COMPRESSION_ONLY, None, DEFLATE, LZFSE, LZ4")
            exit(-1)
        }
        self.serverCompression = parsedCompression

        let cipherString = configRawString("advanced", "cipher") ?? P7Socket.CipherType.SECURE_ONLY.description
        guard let parsedCipher = parseCipherSetting(cipherString) else {
            Logger.fatal("Invalid advanced.cipher value '\(cipherString)'. Accepted values: ALL, SECURE_ONLY, None or cipher descriptions")
            exit(-1)
        }
        self.serverCipher = parsedCipher

        let checksumString = configRawString("advanced", "checksum") ?? P7Socket.Checksum.SECURE_ONLY.description
        guard let parsedChecksum = parseChecksumSetting(checksumString) else {
            Logger.fatal("Invalid advanced.checksum value '\(checksumString)'. Accepted values: ALL, SECURE_ONLY, None or checksum descriptions")
            exit(-1)
        }
        self.serverChecksum = parsedChecksum

        self.addDelegate(self)
    }

    // MARK: - Lifecycle

    public func listen() {
        self.startTime = Date()

        group.enter()

        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
            try self.socket.set(option: .reuseAddress, true)
            try self.socket.bind(port: Port(self.port), address: nil)

            DispatchQueue.global(qos: .default).async {
                self.isRunning = true

                self.listenThread()

                self.group.leave()
            }
        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }

        }

        group.wait()
    }

    public func stop() {
        guard self.isRunning else { return }

        self.isRunning = false

        for client in App.clientsController.connectedClientsSnapshot() {
            client.socket.disconnect()
        }

        // On Linux, a blocking accept() may not always be interrupted quickly by
        // close() alone. Shutdown first to actively wake the listener thread.
        if let listeningSocket = self.socket {
            _ = shutdown(listeningSocket.fileDescriptor, SHUT_RDWR)
        }
        self.socket?.close()
    }

    /// Reloads all hot-reloadable parameters from `App.config`.
    /// The server listening port is intentionally excluded — it requires a full restart.
    public func reloadConfig() {
        var changes: [String] = []

        func apply<T: Equatable>(_ label: String, current: inout T, new: T?) {
            guard let new = new, new != current else { return }
            Logger.info("  \(label): \(current) → \(new)")
            changes.append(label)
            current = new
        }

        apply("server.name", current: &serverName, new: configRawString("server", "name"))
        apply("server.description", current: &serverDescription, new: configRawString("server", "description"))
        apply("transfers.downloads", current: &downloads, new: configUInt32("transfers", "downloads"))
        apply("transfers.uploads", current: &uploads, new: configUInt32("transfers", "uploads"))
        apply("transfers.downloadSpeed", current: &downloadSpeed, new: configUInt32("transfers", "downloadSpeed"))
        apply("transfers.uploadSpeed", current: &uploadSpeed, new: configUInt32("transfers", "uploadSpeed"))
        apply("settings.register_with_trackers", current: &registerWithTrackers, new: configBool("settings", "register_with_trackers"))
        apply("settings.trackers", current: &trackers, new: configStringList("settings", "trackers"))
        apply("tracker.tracker", current: &trackerEnabled, new: configBool("tracker", "tracker"))
        apply("tracker.categories", current: &trackerCategories, new: configStringList("tracker", "categories"))

        let compressionString = configRawString("advanced", "compression") ?? P7Socket.Compression.ALL.description
        if let parsed = parseCompressionSetting(compressionString) {
            apply("advanced.compression", current: &serverCompression, new: parsed)
        } else {
            Logger.warning("  advanced.compression: invalid value '\(compressionString)', keeping current.")
        }

        let cipherString = configRawString("advanced", "cipher") ?? P7Socket.CipherType.SECURE_ONLY.description
        if let parsed = parseCipherSetting(cipherString) {
            apply("advanced.cipher", current: &serverCipher, new: parsed)
        } else {
            Logger.warning("  advanced.cipher: invalid value '\(cipherString)', keeping current.")
        }

        let checksumString = configRawString("advanced", "checksum") ?? P7Socket.Checksum.SECURE_ONLY.description
        if let parsed = parseChecksumSetting(checksumString) {
            apply("advanced.checksum", current: &serverChecksum, new: parsed)
        } else {
            Logger.warning("  advanced.checksum: invalid value '\(checksumString)', keeping current.")
        }

        // SECURITY (A_009): hot-reload strict_identity into the identity object
        if let identity = serverIdentity, let strict = configBool("security", "strict_identity") {
            if strict != identity.strictIdentity {
                Logger.info("  security.strict_identity: \(identity.strictIdentity) → \(strict)")
                identity.strictIdentity = strict
            }
        }

        // Warn if port was changed — it cannot be applied without restarting.
        if let newPort = configUInt32("server", "port"), Int(newPort) != self.port {
            Logger.warning("  server.port: \(self.port) → \(newPort) (requires restart to take effect)")
        }

        if changes.isEmpty {
            Logger.info("Configuration reloaded — no changes detected.")
        } else {
            Logger.info("Configuration reloaded — \(changes.count) value(s) updated.")
        }
    }

    public func addDelegate(_ delegate: ServerDelegate) {
        self.delegates.append(delegate)
    }

    public func removeDelegate(_ delegate: ServerDelegate) {
        if let index = self.delegates.firstIndex(where: { (d) -> Bool in
            d === delegate
        }) {
            self.delegates.remove(at: index)
        }
    }

    // MARK: - ServerDelegate

    public func clientDisconnected(client: Client) {
        self.disconnectClient(client: client)
    }

    public func disconnectClient(client: Client) {
        self.disconnectClient(client: client, broadcastLeaves: true)
    }

    func disconnectClient(client: Client, broadcastLeaves: Bool) {
        if client.state == .LOGGED_IN {
            let login = client.user?.username ?? "unknown"
            let ip = client.socket.getClientIP() ?? "unknown"
            Logger.info("Disconnect from '\(login)' (\(ip))")
            self.recordEvent(.userLoggedOut, client: client)
        }

        let app = App
        app?.filesController?.unsubscribeAll(client: client)
        client.isSubscribedToAccounts = false
        client.isSubscribedToBoards = false
        client.isSubscribedToEvents = false
        client.isSubscribedToLog = false
        app?.chatsController?.removeUserFromAllChats(client: client, broadcastLeaves: broadcastLeaves)
        client.state = .DISCONNECTED
        app?.clientsController?.removeClient(client: client)
    }

    public func receiveMessage(client: Client, message: P7Message) {
        if client.state == .CONNECTED {
            if message.name != "wired.client_info" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        } else if client.state == .GAVE_CLIENT_INFO {
            if  message.name != "wired.user.set_nick"   &&
                message.name != "wired.user.set_status" &&
                message.name != "wired.user.set_icon"   &&
                message.name != "wired.send_login" &&
                message.name != "wired.send_ping" {
                Logger.error("Could not process message \(message.name!): Out of sequence")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
        }

        self.handleMessage(client: client, message: message)

        // TODO: manage user idle time here
    }

    // MARK: - Message I/O helpers

    public func read(message: P7Message, client: Client) throws -> P7Message {
        return try client.socket.readMessage()
    }

    @discardableResult
    public func send(message: P7Message, client: Client) -> Bool {
        if client.transfer == nil {
            return client.socket.write(message) ?? false
        }

        return false
    }

    public func reply(client: Client, reply: P7Message, message: P7Message) {
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }

        _ = self.send(message: reply, client: client)
    }

    public func replyError(client: Client, error: String, message: P7Message?) {
        let reply = P7Message(withName: "wired.error", spec: client.socket.spec)

        if let message = message {
            if let errorEnumValue = message.spec.errorsByName[error] {
                reply.addParameter(field: "wired.error", value: UInt32(errorEnumValue.id))
                reply.addParameter(field: "wired.error.string", value: errorEnumValue.name)
            }

            self.reply(client: client, reply: reply, message: message)
        } else {
            _ = self.send(message: reply, client: client)
        }
    }

    public func replyOK(client: Client, message: P7Message) {
        let reply = P7Message(withName: "wired.okay", spec: client.socket.spec)

        self.reply(client: client, reply: reply, message: message)
    }

    // MARK: - Message routing

    private func handleMessage(client: Client, message: P7Message) {
        // make sure to broadcast idle status if needed
        if client.idle && message.name != "wired.user.set_nick" && message.name != "wired.user.set_status" && message.name != "wired.user.set_icon" && message.name != "wired.user.set_idle" {
            client.idle = false

            self.sendUserStatus(forClient: client)
        }

        if message.name == "wired.client_info" {
            self.receiveClientInfo(client, message)
        } else if message.name == "wired.user.set_nick" {
            self.receiveUserSetNick(client, message)
        } else if message.name == "wired.user.set_status" {
            self.receiveUserSetStatus(client, message)
        } else if message.name == "wired.user.set_icon" {
            self.receiveUserSetIcon(client, message)
        } else if message.name == "wired.user.set_idle" {
            self.receiveUserSetIdle(client, message)
        } else if message.name == "wired.send_login" {
            if client.state == .LOGGED_IN {
                Logger.error("Rejected wired.send_login: client \(client.userID) is already logged in")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
            if !self.receiveSendLogin(client, message) {
                self.disconnectClient(client: client)
            }
        } else if message.name == "wired.user.get_info" {
            self.receiveUserGetInfo(client, message)
        } else if message.name == "wired.user.disconnect_user" {
            self.receiveUserDisconnectUser(client: client, message: message)
        } else if message.name == "wired.user.ban_user" {
            self.receiveUserBanUser(client: client, message: message)
        } else if message.name == "wired.chat.get_chats" {
            App.chatsController.getChats(message: message, client: client)
        } else if message.name == "wired.chat.create_public_chat" {
            App.chatsController.createPublicChat(message: message, client: client)
        } else if message.name == "wired.chat.delete_public_chat" {
            App.chatsController.deletePublicChat(message: message, client: client)
        } else if message.name == "wired.chat.create_chat" {
            App.chatsController.createPrivateChat(message: message, client: client)
        } else if message.name == "wired.chat.invite_user" {
            App.chatsController.inviteUser(message: message, client: client)
        } else if message.name == "wired.chat.decline_invitation" {
            App.chatsController.declineInvitation(message: message, client: client)
        } else if message.name == "wired.chat.send_say" {
            App.chatsController.receiveChatSay(client, message)
        } else if message.name == "wired.chat.send_me" {
            App.chatsController.receiveChatMe(client, message)
        } else if message.name == "wired.chat.send_typing" {
            App.chatsController.receiveChatTyping(client: client, message: message)
        } else if message.name == "wired.chat.join_chat" {
            App.chatsController.userJoin(message: message, client: client)
        } else if message.name == "wired.chat.leave_chat" {
            App.chatsController.userLeave(message: message, client: client)
        } else if message.name == "wired.chat.set_topic" {
            App.chatsController.setTopic(message: message, client: client)
        } else if message.name == "wired.chat.kick_user" {
            App.chatsController.kickUser(message: message, client: client)
        } else if message.name == "wired.message.send_message" {
            self.receiveMessageSendMessage(client: client, message: message)
        } else if message.name == "wired.message.send_broadcast" {
            self.receiveMessageSendBroadcast(client: client, message: message)
        } else if message.name == "wired.board.get_boards" {
            self.receiveBoardGetBoards(client: client, message: message)
        } else if message.name == "wired.board.get_threads" {
            self.receiveBoardGetThreads(client: client, message: message)
        } else if message.name == "wired.board.get_thread" {
            self.receiveBoardGetThread(client: client, message: message)
        } else if message.name == "wired.board.search" {
            self.receiveBoardSearch(client: client, message: message)
        } else if message.name == "wired.board.add_board" {
            self.receiveBoardAddBoard(client: client, message: message)
        } else if message.name == "wired.board.delete_board" {
            self.receiveBoardDeleteBoard(client: client, message: message)
        } else if message.name == "wired.board.rename_board" {
            self.receiveBoardRenameBoard(client: client, message: message)
        } else if message.name == "wired.board.move_board" {
            self.receiveBoardMoveBoard(client: client, message: message)
        } else if message.name == "wired.board.get_board_info" {
            self.receiveBoardGetBoardInfo(client: client, message: message)
        } else if message.name == "wired.board.set_board_info" {
            self.receiveBoardSetBoardInfo(client: client, message: message)
        } else if message.name == "wired.board.add_thread" {
            self.receiveBoardAddThread(client: client, message: message)
        } else if message.name == "wired.board.edit_thread" {
            self.receiveBoardEditThread(client: client, message: message)
        } else if message.name == "wired.board.move_thread" {
            self.receiveBoardMoveThread(client: client, message: message)
        } else if message.name == "wired.board.delete_thread" {
            self.receiveBoardDeleteThread(client: client, message: message)
        } else if message.name == "wired.board.add_post" {
            self.receiveBoardAddPost(client: client, message: message)
        } else if message.name == "wired.board.edit_post" {
            self.receiveBoardEditPost(client: client, message: message)
        } else if message.name == "wired.board.delete_post" {
            self.receiveBoardDeletePost(client: client, message: message)
        } else if message.name == "wired.board.get_reactions" {
            self.receiveBoardGetReactions(client: client, message: message)
        } else if message.name == "wired.board.add_reaction" {
            self.receiveBoardAddReaction(client: client, message: message)
        } else if message.name == "wired.board.subscribe_boards" {
            self.receiveBoardSubscribeBoards(client: client, message: message)
        } else if message.name == "wired.board.unsubscribe_boards" {
            self.receiveBoardUnsubscribeBoards(client: client, message: message)
        } else if message.name == "wired.file.list_directory" {
            App.filesController.listDirectory(client: client, message: message)
        } else if message.name == "wired.file.get_info" {
            App.filesController.getInfo(client: client, message: message)
        } else if message.name == "wired.file.create_directory" {
            App.filesController.createDirectory(client: client, message: message)
        } else if message.name == "wired.file.delete" {
            App.filesController.delete(client: client, message: message)
        } else if message.name == "wired.file.move" {
            App.filesController.move(client: client, message: message)
        } else if message.name == "wired.file.set_type" {
            App.filesController.setType(client: client, message: message)
        } else if message.name == "wired.file.set_permissions" {
            App.filesController.setPermissions(client: client, message: message)
        } else if message.name == "wired.file.subscribe_directory" {
            App.filesController.subscribeDirectory(client: client, message: message)
        } else if message.name == "wired.file.unsubscribe_directory" {
            App.filesController.unsubscribeDirectory(client: client, message: message)
        } else if message.name == "wired.file.search" {
            guard let query = message.string(forField: "wired.file.query") else {
                self.replyError(client: client, error: "wired.error.invalid_message", message: message)
                return
            }
            App.indexController.search(query: query, client: client, message: message)
        } else if message.name == "wired.transfer.download_file" {
            self.receiveDownloadFile(client, message)
        } else if message.name == "wired.transfer.upload_file" {
            self.receiveUploadFile(client, message)
        } else if message.name == "wired.transfer.upload_directory" {
            self.receiveUploadDirectory(client, message)
        } else if message.name == "wired.settings.get_settings" {
            self.receiveGetSettings(client: client, message: message)
        } else if message.name == "wired.settings.set_settings" {
            self.receiveSetSettings(client: client, message: message)
        } else if message.name == "wired.banlist.get_bans" {
            self.receiveBanListGetBans(client: client, message: message)
        } else if message.name == "wired.banlist.add_ban" {
            self.receiveBanListAddBan(client: client, message: message)
        } else if message.name == "wired.banlist.delete_ban" {
            self.receiveBanListDeleteBan(client: client, message: message)
        } else if message.name == "wired.event.get_first_time" {
            self.receiveEventGetFirstTime(client: client, message: message)
        } else if message.name == "wired.event.get_events" {
            self.receiveEventGetEvents(client: client, message: message)
        } else if message.name == "wired.event.subscribe" {
            self.receiveEventSubscribe(client: client, message: message)
        } else if message.name == "wired.event.unsubscribe" {
            self.receiveEventUnsubscribe(client: client, message: message)
        } else if message.name == "wired.event.delete_events" {
            self.receiveEventDeleteEvents(client: client, message: message)
        } else if message.name == "wired.log.get_log" {
            App.logsController.getLog(client: client, message: message)
        } else if message.name == "wired.log.subscribe" {
            App.logsController.subscribe(client: client, message: message)
        } else if message.name == "wired.log.unsubscribe" {
            App.logsController.unsubscribe(client: client, message: message)
        } else if message.name == "wired.account.list_users" {
            self.receiveAccountListUsers(client: client, message: message)
        } else if message.name == "wired.account.list_groups" {
            self.receiveAccountListGroups(client: client, message: message)
        } else if message.name == "wired.account.read_user" {
            self.receiveAccountReadUser(client: client, message: message)
        } else if message.name == "wired.account.read_group" {
            self.receiveAccountReadGroup(client: client, message: message)
        } else if message.name == "wired.account.create_user" {
            self.receiveAccountCreateUser(client: client, message: message)
        } else if message.name == "wired.account.create_group" {
            self.receiveAccountCreateGroup(client: client, message: message)
        } else if message.name == "wired.account.change_password" {
            self.receiveAccountChangePassword(client: client, message: message)
        } else if message.name == "wired.account.edit_user" {
            self.receiveAccountEditUser(client: client, message: message)
        } else if message.name == "wired.account.edit_group" {
            self.receiveAccountEditGroup(client: client, message: message)
        } else if message.name == "wired.account.delete_user" {
            self.receiveAccountDeleteUser(client: client, message: message)
        } else if message.name == "wired.account.delete_group" {
            self.receiveAccountDeleteGroup(client: client, message: message)
        } else if message.name == "wired.account.subscribe_accounts" {
            self.receiveAccountSubscribeAccounts(client: client, message: message)
        } else if message.name == "wired.account.unsubscribe_accounts" {
            self.receiveAccountUnsubscribeAccounts(client: client, message: message)
        } else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }

    // MARK: - Server info message

    func serverInfoMessage() -> P7Message {
        let message = P7Message(withName: "wired.server_info", spec: self.spec)

        message.addParameter(field: "wired.info.application.name", value: "Wired Server 3")
        message.addParameter(field: "wired.info.application.version", value: WiredServerVersion.marketingVersion)
        message.addParameter(field: "wired.info.application.build", value: WiredServerVersion.buildNumber)

        #if os(iOS)
        message.addParameter(field: "wired.info.os.name", value: "iOS")
        #elseif os(macOS)
        message.addParameter(field: "wired.info.os.name", value: "macOS")
        #else
        message.addParameter(field: "wired.info.os.name", value: "Linux")
        #endif

        message.addParameter(field: "wired.info.os.version", value: ProcessInfo.processInfo.operatingSystemVersionString)

        #if os(iOS)
        message.addParameter(field: "wired.info.arch", value: "armv7")
        #elseif os(macOS)
        message.addParameter(field: "wired.info.arch", value: "x86_64")
        #else
        message.addParameter(field: "wired.info.arch", value: "x86_64")
        #endif

        message.addParameter(field: "wired.info.supports_rsrc", value: false)
        message.addParameter(field: "wired.info.name", value: self.serverName)
        message.addParameter(field: "wired.info.description", value: self.serverDescription)

        if let bannerPath = bannerFilePath {
            if let data = readFileData(atPath: bannerPath) {
                message.addParameter(field: "wired.info.banner", value: data)
            }
        }

        message.addParameter(field: "wired.info.downloads", value: self.downloads)
        message.addParameter(field: "wired.info.uploads", value: self.uploads)
        message.addParameter(field: "wired.info.download_speed", value: self.downloadSpeed)
        message.addParameter(field: "wired.info.upload_speed", value: self.uploadSpeed)
        message.addParameter(field: "wired.info.start_time", value: self.startTime)
        message.addParameter(field: "wired.info.files.count", value: App.indexController.totalFilesCount)
        message.addParameter(field: "wired.info.files.size", value: App.indexController.totalFilesSize)

        return message
    }

    // MARK: - Network threads

    private func listenThread() {
        do {
            Logger.info("Server listening on port \(self.port)...")
            try self.socket.listen()

            while self.isRunning {
                self.acceptThread()
            }

        } catch let error {
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error(error.localizedDescription)
            }
        }
    }

    private func acceptThread() {
        do {
            let socket = try self.socket.accept()
            if !self.isRunning {
                try? socket.close()
                return
            }

            // SECURITY (FUZZ_002): Reject connections that would exceed the concurrent limit
            let currentPending: Int = pendingConnectionLock.withLock {
                pendingConnectionCount
            }
            let currentConnected = App.clientsController.connectedClientsSnapshot().count
            if currentPending + currentConnected >= maxConcurrentConnections {
                Logger.warning("Connection limit reached (\(maxConcurrentConnections)), dropping new connection")
                try? socket.close()
                return
            }

            pendingConnectionLock.withLock { pendingConnectionCount += 1 }

            DispatchQueue.global(qos: .default).async {
                defer {
                    self.pendingConnectionLock.withLock { self.pendingConnectionCount -= 1 }
                }

                let p7Socket = P7Socket(socket: socket, spec: self.spec)

                p7Socket.ecdh = self.ecdh
                p7Socket.passwordProvider = App.usersController
                // SECURITY (A_009): Attach identity provider for TOFU
                p7Socket.identityProvider = self.serverIdentity

                let userID = App.usersController.nextUserID()
                let client = Client(userID: userID, socket: p7Socket)

                do {
                    try p7Socket.accept(
                        compression: self.serverCompression,
                        cipher: self.serverCipher,
                        checksum: self.serverChecksum
                    )

                    Logger.info("Connect from \(p7Socket.remoteAddress ?? "unknown")")

                    App.clientsController.addClient(client: client)

                    client.state = .CONNECTED

                    self.clientLoop(client)

                } catch {
                    p7Socket.disconnect()
                }
            }

        } catch let error {
            if !self.isRunning {
                return
            }
            if let socketError = error as? Socket.Error {
                Logger.error(socketError.description)
            } else {
                Logger.error("Socket accept error: \(error.localizedDescription)")
            }
        }
    }

    private func clientLoop(_ client: Client) {
        while self.isRunning {
            if client.socket.connected == false {
                client.state = .DISCONNECTED

                for delegate in delegates {
                    delegate.clientDisconnected(client: client)
                }
                break
            }

            if !client.socket.isInteractive() {
                break
            }

            Logger.debug("ClientLoop \(client.userID) before readMessage() interactive: \(client.socket.isInteractive())")

            do {
                let message = try client.socket.readMessage()

                for delegate in delegates {
                    delegate.receiveMessage(client: client, message: message)
                }
            } catch {
                for delegate in delegates {
                    delegate.clientDisconnected(client: client)
                }

                break
            }
        }
    }
}
