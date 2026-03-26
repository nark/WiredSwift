//
//  ServerController.swift
//  wired3
//
//  Created by Rafael Warnault on 16/03/2021.
//

import Foundation
import WiredSwift
import SocketSwift
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Darwin
#else
import Glibc
#endif



public protocol ServerDelegate: class {
    func clientDisconnected(client:Client)
    func disconnectClient(client:Client)
    
    func receiveMessage(client:Client, message:P7Message)
}


public class ServerController: ServerDelegate {
    public var port: Int = DEFAULT_PORT
    public var spec: P7Spec!
    public var isRunning:Bool = false
    public var delegates:[ServerDelegate] = []
    
    public var serverName:String = "Wired Server 3.0"
    public var serverDescription:String = "Welcome to this new Wired server"
    public var downloads:UInt32 = 0
    public var uploads:UInt32 = 0
    public var downloadSpeed:UInt32 = 0
    public var uploadSpeed:UInt32 = 0
    public var registerWithTrackers: Bool = false
    public var trackers: [String] = []
    public var trackerEnabled: Bool = false
    public var trackerCategories: [String] = []
    public var serverCompression: P7Socket.Compression = .ALL
    public var serverCipher: P7Socket.CipherType = .ALL
    public var serverChecksum: P7Socket.Checksum = .ALL

    /// SECURITY (A_009): Persistent server identity for TOFU. Set by AppController at startup.
    public var serverIdentity: ServerIdentity?

    private var socket:Socket!
    private let ecdh = ECDH()
    private let group = DispatchGroup()

    // SECURITY (FUZZ_002): Limit concurrent connections (pending + authenticated) to prevent
    // GCD thread-pool exhaustion from a connection flood before any authentication occurs.
    private let maxConcurrentConnections = 100
    private var pendingConnectionCount: Int = 0
    private let pendingConnectionLock = NSLock()
    
    var startTime:Date? = nil

    // FINDING_A_001: Rate limiting for login attempts per IP
    private struct LoginAttemptRecord {
        var failureCount: Int
        var bannedUntil: Date?
    }
    private var loginAttempts: [String: LoginAttemptRecord] = [:]
    private let loginAttemptsLock = NSLock()
    private let maxLoginAttempts = 5
    private let loginBanDuration: TimeInterval = 60

    // SECURITY (FINDING_C_012): Rate limiting for broadcast messages per user
    private static let broadcastRateLimitPerMinute: Int = 5
    private var broadcastTimestamps: [UInt32: [Date]] = [:]
    private let broadcastRateLock = NSLock()

    private func resolvedConfigPath(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if (expanded as NSString).isAbsolutePath {
            return expanded
        }

        return App.workingDirectoryPath.stringByAppendingPathComponent(path: expanded)
    }

    private var bannerFilePath: String? {
        guard let bannerPath = App.config["server", "banner"] as? String else {
            return nil
        }

        return resolvedConfigPath(bannerPath)
    }
    
    private func readFileData(atPath path: String) -> Data? {
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
    
    public func listen() {
        self.startTime = Date()

        group.enter()
        
        do {
            self.socket = try Socket(.inet, type: .stream, protocol: .tcp)
            try self.socket.set(option: .reuseAddress, true) // set SO_REUSEADDR to 1
            try self.socket.bind(port: Port(self.port), address: nil) // bind 'localhost:8090' address to the socket
            
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

        apply("server.name",        current: &serverName,           new: configRawString("server", "name"))
        apply("server.description", current: &serverDescription,    new: configRawString("server", "description"))
        apply("transfers.downloads",    current: &downloads,        new: configUInt32("transfers", "downloads"))
        apply("transfers.uploads",      current: &uploads,          new: configUInt32("transfers", "uploads"))
        apply("transfers.downloadSpeed", current: &downloadSpeed,   new: configUInt32("transfers", "downloadSpeed"))
        apply("transfers.uploadSpeed",   current: &uploadSpeed,     new: configUInt32("transfers", "uploadSpeed"))
        apply("settings.register_with_trackers", current: &registerWithTrackers, new: configBool("settings", "register_with_trackers"))
        apply("settings.trackers",      current: &trackers,         new: configStringList("settings", "trackers"))
        apply("tracker.tracker",        current: &trackerEnabled,   new: configBool("tracker", "tracker"))
        apply("tracker.categories",     current: &trackerCategories, new: configStringList("tracker", "categories"))

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

    public func addDelegate(_ delegate:ServerDelegate) {
        self.delegates.append(delegate)
    }
    
    
    public func removeDelegate(_ delegate:ServerDelegate) {
        if let index = self.delegates.firstIndex(where: { (d) -> Bool in
            d === delegate
        }) {
            self.delegates.remove(at: index)
        }
    }
    
    
    
    
    // MARK: - ServerDelegate
    public func clientDisconnected(client:Client) {
        self.disconnectClient(client: client)
    }
    
    
    public func disconnectClient(client: Client) {
        self.disconnectClient(client: client, broadcastLeaves: true)
    }

    private func disconnectClient(client: Client, broadcastLeaves: Bool) {
        if client.state == .LOGGED_IN {
            let login = client.user?.username ?? "unknown"
            let ip = client.socket.getClientIP() ?? "unknown"
            Logger.info("Disconnect from '\(login)' (\(ip))")
            self.recordEvent(.userLoggedOut, client: client)
        }

        // During test/runtime shutdown, global App or controllers can already be tearing down.
        // Avoid crashing disconnect paths on implicitly-unwrapped globals.
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
    
    
    
    public func receiveMessage(client:Client, message:P7Message) {
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
    
    
    
    // MARK: -
    public func read(message:P7Message, client: Client) throws -> P7Message {
        return try client.socket.readMessage()
    }
    
    @discardableResult
    public func send(message:P7Message, client: Client) -> Bool {
        if client.transfer == nil {
            return client.socket.write(message) ?? false
        }
        
        return false
    }
    
    
    
    // MARK: -
    public func reply(client: Client, reply:P7Message, message:P7Message) {
        if let t = message.uint32(forField: "wired.transaction") {
            reply.addParameter(field: "wired.transaction", value: t)
        }
        
        _ = self.send(message: reply, client: client)
    }
    
    
    public func replyError(client: Client, error:String, message:P7Message?) {
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
    
    public func replyOK(client: Client, message:P7Message) {
        let reply = P7Message(withName: "wired.okay", spec: client.socket.spec)
        
        self.reply(client: client, reply: reply, message: message)
    }
    

    
    // MARK: - Private
    private func handleMessage(client:Client, message:P7Message) {
        // make sure to broadcast idle status if needed
        if client.idle && message.name != "wired.user.set_nick" && message.name != "wired.user.set_status" && message.name != "wired.user.set_icon" && message.name != "wired.user.set_idle" {
            client.idle = false
            
            self.sendUserStatus(forClient: client)
        }
        
        if message.name == "wired.client_info" {
            self.receiveClientInfo(client, message)
        }
        else if message.name == "wired.user.set_nick" {
            self.receiveUserSetNick(client, message)
        }
        else if message.name == "wired.user.set_status" {
            self.receiveUserSetStatus(client, message)
        }
        else if message.name == "wired.user.set_icon" {
            self.receiveUserSetIcon(client, message)
        }
        else if message.name == "wired.user.set_idle" {
            self.receiveUserSetIdle(client, message)
        }
        else if message.name == "wired.send_login" {
            if client.state == .LOGGED_IN {
                Logger.error("Rejected wired.send_login: client \(client.userID) is already logged in")
                App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
                return
            }
            if !self.receiveSendLogin(client, message) {
                // login failed
                self.disconnectClient(client: client)
            }
        }
        else if message.name == "wired.user.get_info" {
            self.receiveUserGetInfo(client, message)
        }
        else if message.name == "wired.user.disconnect_user" {
            self.receiveUserDisconnectUser(client: client, message: message)
        }
        else if message.name == "wired.user.ban_user" {
            self.receiveUserBanUser(client: client, message: message)
        }
        else if message.name == "wired.chat.get_chats" {
            App.chatsController.getChats(message: message, client: client)
        }
        else if message.name == "wired.chat.create_public_chat" {
            App.chatsController.createPublicChat(message: message, client: client)
        }
        else if message.name == "wired.chat.delete_public_chat" {
            App.chatsController.deletePublicChat(message: message, client: client)
        }
        else if message.name == "wired.chat.create_chat" {
            App.chatsController.createPrivateChat(message: message, client: client)
        }
        else if message.name == "wired.chat.invite_user" {
            App.chatsController.inviteUser(message: message, client: client)
        }
        else if message.name == "wired.chat.decline_invitation" {
            App.chatsController.declineInvitation(message: message, client: client)
        }
        else if message.name == "wired.chat.send_say" {
            App.chatsController.receiveChatSay(client, message)
        }
        else if message.name == "wired.chat.send_me" {
            App.chatsController.receiveChatMe(client, message)
        }
        else if message.name == "wired.chat.send_typing" {
            App.chatsController.receiveChatTyping(client: client, message: message)
        }
        else if message.name == "wired.chat.join_chat" {
            App.chatsController.userJoin(message: message, client: client)
        }
        else if message.name == "wired.chat.leave_chat" {
            App.chatsController.userLeave(message: message, client: client)
        }
        else if message.name == "wired.chat.set_topic" {
            App.chatsController.setTopic(message: message, client: client)
        }
        else if message.name == "wired.chat.kick_user" {
            App.chatsController.kickUser(message: message, client: client)
        }
        else if message.name == "wired.message.send_message" {
            self.receiveMessageSendMessage(client: client, message: message)
        }
        else if message.name == "wired.message.send_broadcast" {
            self.receiveMessageSendBroadcast(client: client, message: message)
        }
        else if message.name == "wired.board.get_boards" {
            self.receiveBoardGetBoards(client: client, message: message)
        }
        else if message.name == "wired.board.get_threads" {
            self.receiveBoardGetThreads(client: client, message: message)
        }
        else if message.name == "wired.board.get_thread" {
            self.receiveBoardGetThread(client: client, message: message)
        }
        else if message.name == "wired.board.search" {
            self.receiveBoardSearch(client: client, message: message)
        }
        else if message.name == "wired.board.add_board" {
            self.receiveBoardAddBoard(client: client, message: message)
        }
        else if message.name == "wired.board.delete_board" {
            self.receiveBoardDeleteBoard(client: client, message: message)
        }
        else if message.name == "wired.board.rename_board" {
            self.receiveBoardRenameBoard(client: client, message: message)
        }
        else if message.name == "wired.board.move_board" {
            self.receiveBoardMoveBoard(client: client, message: message)
        }
        else if message.name == "wired.board.get_board_info" {
            self.receiveBoardGetBoardInfo(client: client, message: message)
        }
        else if message.name == "wired.board.set_board_info" {
            self.receiveBoardSetBoardInfo(client: client, message: message)
        }
        else if message.name == "wired.board.add_thread" {
            self.receiveBoardAddThread(client: client, message: message)
        }
        else if message.name == "wired.board.edit_thread" {
            self.receiveBoardEditThread(client: client, message: message)
        }
        else if message.name == "wired.board.move_thread" {
            self.receiveBoardMoveThread(client: client, message: message)
        }
        else if message.name == "wired.board.delete_thread" {
            self.receiveBoardDeleteThread(client: client, message: message)
        }
        else if message.name == "wired.board.add_post" {
            self.receiveBoardAddPost(client: client, message: message)
        }
        else if message.name == "wired.board.edit_post" {
            self.receiveBoardEditPost(client: client, message: message)
        }
        else if message.name == "wired.board.delete_post" {
            self.receiveBoardDeletePost(client: client, message: message)
        }
        else if message.name == "wired.board.get_reactions" {
            self.receiveBoardGetReactions(client: client, message: message)
        }
        else if message.name == "wired.board.add_reaction" {
            self.receiveBoardAddReaction(client: client, message: message)
        }
        else if message.name == "wired.board.subscribe_boards" {
            self.receiveBoardSubscribeBoards(client: client, message: message)
        }
        else if message.name == "wired.board.unsubscribe_boards" {
            self.receiveBoardUnsubscribeBoards(client: client, message: message)
        }
        else if message.name == "wired.file.list_directory" {
            App.filesController.listDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.get_info" {
            App.filesController.getInfo(client: client, message: message)
        }
        else if message.name == "wired.file.create_directory" {
            App.filesController.createDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.delete" {
            App.filesController.delete(client: client, message: message)
        }
        else if message.name == "wired.file.move" {
            App.filesController.move(client: client, message: message)
        }
        else if message.name == "wired.file.set_type" {
            App.filesController.setType(client: client, message: message)
        }
        else if message.name == "wired.file.set_permissions" {
            App.filesController.setPermissions(client: client, message: message)
        }
        else if message.name == "wired.file.subscribe_directory" {
            App.filesController.subscribeDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.unsubscribe_directory" {
            App.filesController.unsubscribeDirectory(client: client, message: message)
        }
        else if message.name == "wired.file.search" {
            guard let query = message.string(forField: "wired.file.query") else {
                self.replyError(client: client, error: "wired.error.invalid_message", message: message)
                return
            }
            App.indexController.search(query: query, client: client, message: message)
        }
        else if message.name == "wired.transfer.download_file" {
            self.receiveDownloadFile(client, message)
        }
        else if message.name == "wired.transfer.upload_file" {
            self.receiveUploadFile(client, message)
        }
        else if message.name == "wired.transfer.upload_directory" {
            self.receiveUploadDirectory(client, message)
        }
        else if message.name == "wired.settings.get_settings" {
            self.receiveGetSettings(client: client, message: message)
        }
        else if message.name == "wired.settings.set_settings" {
            self.receiveSetSettings(client: client, message: message)
        }
        else if message.name == "wired.banlist.get_bans" {
            self.receiveBanListGetBans(client: client, message: message)
        }
        else if message.name == "wired.banlist.add_ban" {
            self.receiveBanListAddBan(client: client, message: message)
        }
        else if message.name == "wired.banlist.delete_ban" {
            self.receiveBanListDeleteBan(client: client, message: message)
        }
        else if message.name == "wired.event.get_first_time" {
            self.receiveEventGetFirstTime(client: client, message: message)
        }
        else if message.name == "wired.event.get_events" {
            self.receiveEventGetEvents(client: client, message: message)
        }
        else if message.name == "wired.event.subscribe" {
            self.receiveEventSubscribe(client: client, message: message)
        }
        else if message.name == "wired.event.unsubscribe" {
            self.receiveEventUnsubscribe(client: client, message: message)
        }
        else if message.name == "wired.event.delete_events" {
            self.receiveEventDeleteEvents(client: client, message: message)
        }
        else if message.name == "wired.log.get_log" {
            App.logsController.getLog(client: client, message: message)
        }
        else if message.name == "wired.log.subscribe" {
            App.logsController.subscribe(client: client, message: message)
        }
        else if message.name == "wired.log.unsubscribe" {
            App.logsController.unsubscribe(client: client, message: message)
        }
        else if message.name == "wired.account.list_users" {
            self.receiveAccountListUsers(client: client, message: message)
        }
        else if message.name == "wired.account.list_groups" {
            self.receiveAccountListGroups(client: client, message: message)
        }
        else if message.name == "wired.account.read_user" {
            self.receiveAccountReadUser(client: client, message: message)
        }
        else if message.name == "wired.account.read_group" {
            self.receiveAccountReadGroup(client: client, message: message)
        }
        else if message.name == "wired.account.create_user" {
            self.receiveAccountCreateUser(client: client, message: message)
        }
        else if message.name == "wired.account.create_group" {
            self.receiveAccountCreateGroup(client: client, message: message)
        }
        else if message.name == "wired.account.change_password" {
            self.receiveAccountChangePassword(client: client, message: message)
        }
        else if message.name == "wired.account.edit_user" {
            self.receiveAccountEditUser(client: client, message: message)
        }
        else if message.name == "wired.account.edit_group" {
            self.receiveAccountEditGroup(client: client, message: message)
        }
        else if message.name == "wired.account.delete_user" {
            self.receiveAccountDeleteUser(client: client, message: message)
        }
        else if message.name == "wired.account.delete_group" {
            self.receiveAccountDeleteGroup(client: client, message: message)
        }
        else if message.name == "wired.account.subscribe_accounts" {
            self.receiveAccountSubscribeAccounts(client: client, message: message)
        }
        else if message.name == "wired.account.unsubscribe_accounts" {
            self.receiveAccountUnsubscribeAccounts(client: client, message: message)
        }
        else {
            WiredSwift.Logger.warning("Message \(message.name ?? "unknow message") not implemented")
        }
    }
    
    
    
    private func receiveClientInfo(_ client:Client, _ message:P7Message) {
        client.state = .GAVE_CLIENT_INFO
                
        if let applicationName = message.string(forField: "wired.info.application.name") {
            client.applicationName = applicationName
        }
        
        if let applicationVersion = message.string(forField: "wired.info.application.version") {
            client.applicationVersion = applicationVersion
        }
        
        if let applicationBuild = message.string(forField: "wired.info.application.build") {
            client.applicationBuild = applicationBuild
        }
        
        if let osName = message.string(forField: "wired.info.os.name") {
            client.osName = osName
        }
        
        if let osVersion = message.string(forField: "wired.info.os.version") {
            client.osVersion = osVersion
        }
        
        if let arch = message.string(forField: "wired.info.arch") {
            client.arch = arch
        }
        
        if let supportsRsrc = message.bool(forField: "wired.info.supports_rsrc") {
            client.supportsRsrc = supportsRsrc
        }
                
        App.serverController.reply(client: client,
                                   reply: self.serverInfoMessage(),
                                   message: message)
    }
    
    
    private func receiveUserSetNick(_ client:Client, _ message:P7Message) {
        let previousNick = client.nick ?? ""
        if let nick = message.string(forField: "wired.user.nick") {
            client.nick = nick
        }
                
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        
        App.serverController.reply(client: client, reply: response, message: message)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            let newNick = client.nick ?? ""
            if previousNick != newNick {
                self.recordEvent(.userChangedNick, client: client, parameters: [previousNick, newNick])
            }
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserSetStatus(_ client:Client, _ message:P7Message) {
        if let status = message.string(forField: "wired.user.status") {
            client.status = status
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN && client.user != nil {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserSetIcon(_ client:Client, _ message:P7Message) {
        if let icon = message.data(forField: "wired.user.icon") {
            client.icon = icon
        }
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }
    
    private func receiveUserSetIdle(_ client:Client, _ message:P7Message) {
        client.idle = true
        client.idleTime = Date()
        
        let response = P7Message(withName: "wired.okay", spec: self.spec)
        _ = self.send(message: response, client: client)
        
        // broadcast if already logged in
        if client.state == .LOGGED_IN {
            self.sendUserStatus(forClient: client)
        }
    }
    
    
    private func receiveUserGetInfo(_ fromClient:Client, _ message:P7Message) {
        guard let user = fromClient.user else { return }
        if !user.hasPrivilege(name: "wired.account.user.get_info") {
            App.serverController.replyError(client: fromClient, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let userID = message.uint32(forField: "wired.user.id") else { return }
        guard let client = App.clientsController.user(withID: userID) else { return }
        
        let response = P7Message(withName: "wired.user.info", spec: self.spec)
        
        response.addParameter(field: "wired.user.id", value: client.userID ?? "")
        response.addParameter(field: "wired.user.nick", value: client.nick ?? "")
        response.addParameter(field: "wired.user.status", value: client.status ?? "")
        response.addParameter(field: "wired.user.idle", value: client.idle)
        response.addParameter(field: "wired.user.icon", value: client.icon ?? "")
        
        response.addParameter(field: "wired.user.login", value: client.user?.username ?? "")
        response.addParameter(field: "wired.user.ip", value: client.socket.getClientIP() ?? "")
        response.addParameter(field: "wired.user.host", value: client.socket.getClientHostname() ?? "")
        response.addParameter(field: "wired.user.cipher.name", value: client.socket.cipherType.description)
        response.addParameter(field: "wired.user.cipher.bits", value: UInt32(client.socket.checksumLength(client.socket.digest.type)))
        
        if let loginTime = client.loginTime {
            response.addParameter(field: "wired.user.login_time", value: loginTime)
        }
        
        if let idleTime = client.idleTime {
            response.addParameter(field: "wired.user.idle_time", value: idleTime)
        }
        
        response.addParameter(field: "wired.info.application.name", value: client.applicationName)
        response.addParameter(field: "wired.info.application.version", value: client.applicationBuild)
        response.addParameter(field: "wired.info.application.build", value: client.applicationVersion)
        response.addParameter(field: "wired.info.os.name", value: client.osName)
        response.addParameter(field: "wired.info.os.version", value: client.osVersion)
        response.addParameter(field: "wired.info.arch", value: client.arch)
        response.addParameter(field: "wired.info.supports_rsrc", value: client.supportsRsrc)
        
        App.serverController.reply(client: fromClient,
                                   reply: response,
                                   message: message)
        self.recordEvent(.userGotInfo, client: fromClient, parameters: [client.nick ?? client.user?.username ?? ""])
    }

    private func receiveUserDisconnectUser(client: Client, message: P7Message) {
        guard let (_, target, disconnectMessage) = self.validateModerationTarget(
            client: client,
            message: message,
            requiredPrivilege: "wired.account.user.disconnect_users"
        ) else {
            return
        }

        let chats = App.chatsController.chats(containingUserID: target.userID)

        for chat in chats {
            let broadcast = P7Message(withName: "wired.chat.user_disconnect", spec: client.socket.spec)
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.disconnected_id", value: target.userID)
            broadcast.addParameter(field: "wired.user.disconnect_message", value: disconnectMessage)

            chat.withClients { chatClient in
                App.serverController.send(message: broadcast, client: chatClient)
            }
        }

        self.disconnectClient(client: target, broadcastLeaves: false)
        self.replyOK(client: client, message: message)
        self.recordEvent(.userDisconnectedUser, client: client, parameters: [target.nick ?? target.user?.username ?? ""])
    }

    private func receiveUserBanUser(client: Client, message: P7Message) {
        guard let (_, target, disconnectMessage) = self.validateModerationTarget(
            client: client,
            message: message,
            requiredPrivilege: "wired.account.user.ban_users"
        ) else {
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")
        let targetIP = target.socket.getClientIP()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        guard !targetIP.isEmpty else {
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        do {
            _ = try App.banListController.addBan(ipPattern: targetIP, expirationDate: expirationDate)
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
            return
        } catch {
            Logger.error("Failed to ban user \(target.userID) at IP \(targetIP): \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let chats = App.chatsController.chats(containingUserID: target.userID)

        for chat in chats {
            let broadcast = P7Message(withName: "wired.chat.user_ban", spec: client.socket.spec)
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.disconnected_id", value: target.userID)
            broadcast.addParameter(field: "wired.user.disconnect_message", value: disconnectMessage)

            chat.withClients { chatClient in
                App.serverController.send(message: broadcast, client: chatClient)
            }
        }

        self.disconnectClient(client: target, broadcastLeaves: false)
        self.replyOK(client: client, message: message)
        self.recordEvent(.userBannedUser, client: client, parameters: [target.nick ?? target.user?.username ?? ""])
    }

    private func validateModerationTarget(
        client: Client,
        message: P7Message,
        requiredPrivilege: String
    ) -> (User, Client, String)? {
        guard let actor = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return nil
        }

        guard actor.hasPrivilege(name: requiredPrivilege) else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return nil
        }

        guard let targetUserID = message.uint32(forField: "wired.user.id"),
              let disconnectMessage = message.string(forField: "wired.user.disconnect_message") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return nil
        }

        guard let target = App.clientsController.user(withID: targetUserID) else {
            self.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return nil
        }

        guard target.user?.hasPrivilege(name: "wired.account.user.cannot_be_disconnected") != true else {
            self.replyError(client: client, error: "wired.error.user_cannot_be_disconnected", message: message)
            return nil
        }

        return (actor, target, disconnectMessage)
    }

    private func receiveBanListGetBans(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.get_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            let bans = try App.banListController.listBans()

            for ban in bans {
                let reply = P7Message(withName: "wired.banlist.list", spec: client.socket.spec)
                reply.addParameter(field: "wired.banlist.ip", value: ban.ipPattern)
                if let expirationDate = ban.expirationDate {
                    reply.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
                }
                self.reply(client: client, reply: reply, message: message)
            }

            let done = P7Message(withName: "wired.banlist.list.done", spec: client.socket.spec)
            self.reply(client: client, reply: done, message: message)
            self.recordEvent(.banlistGotBans, client: client)
        } catch {
            Logger.error("Failed to list bans: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func receiveBanListAddBan(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.add_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let ipPattern = message.string(forField: "wired.banlist.ip") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")

        do {
            _ = try App.banListController.addBan(ipPattern: ipPattern, expirationDate: expirationDate)
            self.replyOK(client: client, message: message)
            self.recordEvent(.banlistAddedBan, client: client, parameters: [ipPattern])
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
        } catch {
            Logger.error("Failed to add ban '\(ipPattern)': \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func receiveBanListDeleteBans(client: Client, message: P7Message) {
        self.receiveBanListDeleteBan(client: client, message: message)
    }

    private func receiveBanListDeleteBan(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.banlist.delete_bans") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let ipPattern = message.string(forField: "wired.banlist.ip") else {
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let expirationDate = message.date(forField: "wired.banlist.expiration_date")

        do {
            try App.banListController.deleteBan(ipPattern: ipPattern, expirationDate: expirationDate)
            self.replyOK(client: client, message: message)
            self.recordEvent(.banlistDeletedBan, client: client, parameters: [ipPattern])
        } catch let error as BanListError {
            self.replyBanListError(client: client, message: message, error: error)
        } catch {
            Logger.error("Failed to delete ban '\(ipPattern)': \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func replyBanListError(client: Client, message: P7Message, error: BanListError) {
        switch error {
        case .invalidPattern, .invalidExpirationDate:
            self.replyError(client: client, error: "wired.error.invalid_message", message: message)
        case .alreadyExists:
            self.replyError(client: client, error: "wired.error.ban_exists", message: message)
        case .notFound:
            self.replyError(client: client, error: "wired.error.ban_not_found", message: message)
        }
    }

    private func receiveEventGetFirstTime(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            let reply = P7Message(withName: "wired.event.first_time", spec: client.socket.spec)
            reply.addParameter(
                field: "wired.event.first_time",
                value: try App.eventsController.firstEventDate() ?? Date(timeIntervalSince1970: 0)
            )
            self.reply(client: client, reply: reply, message: message)
        } catch {
            Logger.error("Failed to fetch first event time: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func receiveEventGetEvents(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let fromTime = message.date(forField: "wired.event.from_time")
        let numberOfDays = message.uint32(forField: "wired.event.number_of_days") ?? 0
        let lastEventCount = message.uint32(forField: "wired.event.last_event_count") ?? 0

        self.recordEvent(.eventsGotEvents, client: client)

        do {
            let entries = try App.eventsController.listEvents(
                from: fromTime,
                numberOfDays: numberOfDays,
                lastEventCount: lastEventCount
            )

            for entry in entries {
                self.reply(
                    client: client,
                    reply: self.eventMessage(for: entry, name: "wired.event.event_list"),
                    message: message
                )
            }

            let done = P7Message(withName: "wired.event.event_list.done", spec: client.socket.spec)
            self.reply(client: client, reply: done, message: message)
        } catch {
            Logger.error("Failed to list events: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func receiveEventSubscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToEvents {
            self.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToEvents = true
        self.replyOK(client: client, message: message)
    }

    private func receiveEventUnsubscribe(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToEvents {
            self.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToEvents = false
        self.replyOK(client: client, message: message)
    }

    private func receiveEventDeleteEvents(client: Client, message: P7Message) {
        guard let user = client.user else {
            self.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.events.view_events") else {
            self.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let fromTime = message.date(forField: "wired.event.from_time")
        let toTime = message.date(forField: "wired.event.to_time")

        do {
            try App.eventsController.deleteEvents(from: fromTime, to: toTime)
            self.replyOK(client: client, message: message)
        } catch {
            Logger.error("Failed to delete events: \(error)")
            self.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func eventMessage(for entry: EventEntry, name: String) -> P7Message {
        let reply = P7Message(withName: name, spec: self.spec)
        reply.addParameter(field: "wired.event.event", value: entry.eventCode)
        reply.addParameter(field: "wired.event.time", value: entry.time)
        if !entry.parameters.isEmpty {
            reply.addParameter(field: "wired.event.parameters", value: entry.parameters)
        }
        reply.addParameter(field: "wired.user.nick", value: entry.nick)
        reply.addParameter(field: "wired.user.login", value: entry.login)
        reply.addParameter(field: "wired.user.ip", value: entry.ip)
        return reply
    }

    func recordEvent(
        _ event: WiredServerEvent,
        client: Client,
        parameters: [String] = [],
        loginOverride: String? = nil,
        nickOverride: String? = nil
    ) {
        let nick = nickOverride ?? client.nick ?? ""
        let login = loginOverride ?? client.user?.username ?? ""
        let ip = client.socket.getClientIP() ?? client.ip ?? ""
        self.recordEvent(event, nick: nick, login: login, ip: ip, parameters: parameters)
    }

    func recordEvent(
        _ event: WiredServerEvent,
        nick: String?,
        login: String?,
        ip: String,
        parameters: [String] = []
    ) {
        do {
            let entry = try App.eventsController.addEvent(
                event,
                parameters: parameters,
                nick: nick ?? "",
                login: login ?? "",
                ip: ip
            )
            self.broadcastEvent(entry)
        } catch {
            Logger.error("Failed to record event \(event.protocolName): \(error)")
        }
    }

    private func broadcastEvent(_ entry: EventEntry) {
        let broadcast = self.eventMessage(for: entry, name: "wired.event.event")
        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToEvents else { continue }
            guard let connectedUser = connectedClient.user else { continue }

            if !connectedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
                continue
            }

            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func receiveMessageSendMessage(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.send_messages") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let recipientID = message.uint32(forField: "wired.user.id"),
              let recipient = App.clientsController.user(withID: recipientID) else {
            App.serverController.replyError(client: client, error: "wired.error.user_not_found", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.message"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let reply = P7Message(withName: "wired.message.message", spec: self.spec)
        reply.addParameter(field: "wired.user.id", value: client.userID)
        reply.addParameter(field: "wired.message.message", value: body)

        _ = self.send(message: reply, client: recipient)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.messageSent, client: client, parameters: [recipient.nick ?? recipient.user?.username ?? ""])
    }

    private func receiveMessageSendBroadcast(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.message.broadcast") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let body = message.string(forField: "wired.message.broadcast"),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        // SECURITY (FINDING_C_012): Rate limit broadcasts (max 5/min per user)
        let now = Date()
        let broadcastExceeded: Bool = {
            self.broadcastRateLock.lock()
            defer { self.broadcastRateLock.unlock() }
            var timestamps = self.broadcastTimestamps[client.userID] ?? []
            let cutoff = now.addingTimeInterval(-60.0)
            timestamps = timestamps.filter { $0 > cutoff }
            if timestamps.count >= Self.broadcastRateLimitPerMinute {
                return true
            }
            timestamps.append(now)
            self.broadcastTimestamps[client.userID] = timestamps
            return false
        }()
        if broadcastExceeded {
            Logger.warning("Broadcast rate limit exceeded for user \(client.userID)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        let broadcast = P7Message(withName: "wired.message.broadcast", spec: self.spec)
        broadcast.addParameter(field: "wired.user.id", value: client.userID)
        broadcast.addParameter(field: "wired.message.broadcast", value: body)

        App.clientsController.broadcast(message: broadcast)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.messageBroadcasted, client: client)
    }

    private func receiveBoardGetBoards(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        let boards = App.boardsController.getBoards(forUser: username, group: groupName)

        for board in boards {
            let reply = P7Message(withName: "wired.board.board_list", spec: self.spec)
            reply.addParameter(field: "wired.board.board", value: board.path)
            reply.addParameter(field: "wired.board.readable", value: board.canRead(user: username, group: groupName))
            reply.addParameter(field: "wired.board.writable", value: board.canWrite(user: username, group: groupName))
            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.board.board_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotBoards, client: client)
    }

    private func receiveBoardGetThreads(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""

        let threads: [Thread]
        if let boardPath = message.string(forField: "wired.board.board"), !boardPath.isEmpty {
            guard let board = App.boardsController.getBoardInfo(path: boardPath) else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }

            guard board.canRead(user: username, group: groupName) else {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }

            threads = App.boardsController.getThreads(forBoard: boardPath)
        } else {
            threads = App.boardsController
                .getBoards(forUser: username, group: groupName)
                .flatMap { App.boardsController.getThreads(forBoard: $0.path) }
        }

        for thread in threads {
            let reply = P7Message(withName: "wired.board.thread_list", spec: self.spec)
            reply.addParameter(field: "wired.board.board", value: thread.board)
            reply.addParameter(field: "wired.board.thread", value: thread.uuid)
            reply.addParameter(field: "wired.board.post_date", value: thread.postDate)
            reply.addParameter(field: "wired.board.own_thread", value: thread.login == username)
            reply.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            reply.addParameter(field: "wired.board.subject", value: thread.subject)
            reply.addParameter(field: "wired.user.nick", value: thread.nick)
            if let editDate = thread.editDate {
                reply.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            if let latestReply = thread.latestReplyUUID {
                reply.addParameter(field: "wired.board.latest_reply", value: latestReply)
            }
            if let latestReplyDate = thread.latestReplyDate {
                reply.addParameter(field: "wired.board.latest_reply_date", value: latestReplyDate)
            }
            let emojiSummary = App.boardsController.getThreadReactionEmojis(threadUUID: thread.uuid)
            if !emojiSummary.isEmpty {
                reply.addParameter(field: "wired.board.reaction.emojis", value: emojiSummary)
            }
            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.board.thread_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotThreads, client: client)
    }

    private func receiveBoardGetThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let threadID = message.uuid(forField: "wired.board.thread"), !threadID.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let thread = App.boardsController.getThread(uuid: threadID) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canRead(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let threadReply = P7Message(withName: "wired.board.thread", spec: self.spec)
        threadReply.addParameter(field: "wired.board.thread", value: thread.uuid)
        threadReply.addParameter(field: "wired.board.text", value: thread.text)
        threadReply.addParameter(field: "wired.user.icon", value: thread.icon ?? Data())
        self.reply(client: client, reply: threadReply, message: message)

        let posts = App.boardsController.getPosts(forThread: thread.uuid)
        for post in posts {
            let postReply = P7Message(withName: "wired.board.post_list", spec: self.spec)
            postReply.addParameter(field: "wired.board.thread", value: post.thread)
            postReply.addParameter(field: "wired.board.post", value: post.uuid)
            postReply.addParameter(field: "wired.board.post_date", value: post.postDate)
            postReply.addParameter(field: "wired.board.own_post", value: post.login == username)
            postReply.addParameter(field: "wired.board.text", value: post.text)
            postReply.addParameter(field: "wired.user.nick", value: post.nick)
            postReply.addParameter(field: "wired.user.icon", value: post.icon ?? Data())
            if let editDate = post.editDate {
                postReply.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            self.reply(client: client, reply: postReply, message: message)
        }

        let done = P7Message(withName: "wired.board.post_list.done", spec: self.spec)
        done.addParameter(field: "wired.board.thread", value: thread.uuid)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.boardGotThread, client: client, parameters: [thread.subject, thread.board])
    }

    private func receiveBoardSearch(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            user.hasPrivilege(name: "wired.account.board.read_boards"),
            user.hasPrivilege(name: "wired.account.board.search_boards")
        else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let query = message.string(forField: "wired.board.query") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        let readableBoardPaths = Set(
            App.boardsController
                .getBoards(forUser: username, group: groupName)
                .map(\.path)
        )

        let scopedBoardPaths: [String]
        if let scopedBoardPath = message.string(forField: "wired.board.board"), !scopedBoardPath.isEmpty {
            guard let board = App.boardsController.getBoardInfo(path: scopedBoardPath) else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }

            guard board.canRead(user: username, group: groupName) else {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }

            scopedBoardPaths = readableBoardPaths
                .filter { $0 == scopedBoardPath || $0.hasPrefix(scopedBoardPath + "/") }
                .sorted()
        } else {
            scopedBoardPaths = readableBoardPaths.sorted()
        }

        guard !scopedBoardPaths.isEmpty else {
            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            return
        }

        do {
            let results = try App.boardsController.search(query: trimmed, boardPaths: scopedBoardPaths, limit: 100)
            for result in results {
                let reply = P7Message(withName: "wired.board.search_list", spec: self.spec)
                reply.addParameter(field: "wired.board.board", value: result.boardPath)
                reply.addParameter(field: "wired.board.thread", value: result.threadUUID)
                reply.addParameter(field: "wired.board.subject", value: result.subject)
                reply.addParameter(field: "wired.user.nick", value: result.nick)
                reply.addParameter(field: "wired.board.post_date", value: result.postDate)
                reply.addParameter(field: "wired.board.snippet", value: result.snippet)
                if let postUUID = result.postUUID {
                    reply.addParameter(field: "wired.board.post", value: postUUID)
                }
                if let editDate = result.editDate {
                    reply.addParameter(field: "wired.board.edit_date", value: editDate)
                }
                self.reply(client: client, reply: reply, message: message)
            }

            let done = P7Message(withName: "wired.board.search_list.done", spec: self.spec)
            self.reply(client: client, reply: done, message: message)
            self.recordEvent(.boardSearched, client: client, parameters: [trimmed])
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }

    private func receiveBoardAddBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board")?.trimmingCharacters(in: .whitespacesAndNewlines),
            !path.isEmpty,
            let owner = message.string(forField: "wired.board.owner"),
            let ownerRead = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite = message.bool(forField: "wired.board.owner.write"),
            let group = message.string(forField: "wired.board.group"),
            let groupRead = message.bool(forField: "wired.board.group.read"),
            let groupWrite = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        let parentPath = (path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty && parentPath != "." {
            guard App.boardsController.getBoardInfo(path: parentPath) != nil else {
                App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
                return
            }
        }

        guard let board = App.boardsController.addBoard(
            path: path,
            owner: owner,
            group: group,
            ownerRead: ownerRead,
            ownerWrite: ownerWrite,
            groupRead: groupRead,
            groupWrite: groupWrite,
            everyoneRead: everyoneRead,
            everyoneWrite: everyoneWrite
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardAdded(board: board)
        self.recordEvent(.boardAddedBoard, client: client, parameters: [board.path])
    }

    private func receiveBoardDeleteBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.delete_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.board.board"), !path.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard App.boardsController.deleteBoard(path: path) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardDeleted(path: path)
        self.recordEvent(.boardDeletedBoard, client: client, parameters: [path])
    }

    private func receiveBoardRenameBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.rename_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board"),
            !path.isEmpty,
            !newPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        if App.boardsController.getBoardInfo(path: newPath) != nil {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        guard App.boardsController.renameBoard(path: path, newPath: newPath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardRenamed(path: path, newPath: newPath)
        self.recordEvent(.boardRenamedBoard, client: client, parameters: [path, newPath])
    }

    private func receiveBoardMoveBoard(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.move_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            let newPath = message.string(forField: "wired.board.new_board"),
            !path.isEmpty,
            !newPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        if App.boardsController.getBoardInfo(path: newPath) != nil {
            App.serverController.replyError(client: client, error: "wired.error.board_exists", message: message)
            return
        }

        guard App.boardsController.moveBoard(path: path, newPath: newPath) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastBoardMoved(path: path, newPath: newPath)
        self.recordEvent(.boardMovedBoard, client: client, parameters: [path, newPath])
    }

    private func receiveBoardGetBoardInfo(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.get_board_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let path = message.string(forField: "wired.board.board"), !path.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: path) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let reply = P7Message(withName: "wired.board.board_info", spec: self.spec)
        reply.addParameter(field: "wired.board.board", value: board.path)
        reply.addParameter(field: "wired.board.owner", value: board.owner)
        reply.addParameter(field: "wired.board.owner.read", value: board.ownerRead)
        reply.addParameter(field: "wired.board.owner.write", value: board.ownerWrite)
        reply.addParameter(field: "wired.board.group", value: board.group)
        reply.addParameter(field: "wired.board.group.read", value: board.groupRead)
        reply.addParameter(field: "wired.board.group.write", value: board.groupWrite)
        reply.addParameter(field: "wired.board.everyone.read", value: board.everyoneRead)
        reply.addParameter(field: "wired.board.everyone.write", value: board.everyoneWrite)
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.boardGotBoardInfo, client: client, parameters: [board.path])
    }

    private func receiveBoardSetBoardInfo(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.set_board_info") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let path = message.string(forField: "wired.board.board"),
            !path.isEmpty,
            let owner = message.string(forField: "wired.board.owner"),
            let ownerRead = message.bool(forField: "wired.board.owner.read"),
            let ownerWrite = message.bool(forField: "wired.board.owner.write"),
            let group = message.string(forField: "wired.board.group"),
            let groupRead = message.bool(forField: "wired.board.group.read"),
            let groupWrite = message.bool(forField: "wired.board.group.write"),
            let everyoneRead = message.bool(forField: "wired.board.everyone.read"),
            let everyoneWrite = message.bool(forField: "wired.board.everyone.write")
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: path) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard App.boardsController.setBoardInfo(
            path: path,
            owner: owner,
            group: group,
            ownerRead: ownerRead,
            ownerWrite: ownerWrite,
            groupRead: groupRead,
            groupWrite: groupWrite,
            everyoneRead: everyoneRead,
            everyoneWrite: everyoneWrite
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        if let board = App.boardsController.getBoardInfo(path: path) {
            broadcastBoardInfoChanged(board: board)
        }
        self.recordEvent(.boardSetBoardInfo, client: client, parameters: [path])
    }

    private func receiveBoardAddThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_threads") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let boardPath = message.string(forField: "wired.board.board"),
            let subject = message.string(forField: "wired.board.subject"),
            let text = message.string(forField: "wired.board.text"),
            !boardPath.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: boardPath) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canWrite(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let thread = App.boardsController.addThread(
            board: boardPath,
            subject: subject,
            text: text,
            nick: client.nick ?? username,
            login: username,
            icon: client.icon
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadAdded(thread: thread)
        self.recordEvent(.boardAddedThread, client: client, parameters: [thread.subject, thread.board])
    }

    private func receiveBoardEditThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.thread"),
            let subject = message.string(forField: "wired.board.subject"),
            let text = message.string(forField: "wired.board.text"),
            !uuid.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canEditOwn = user.hasPrivilege(name: "wired.account.board.edit_own_threads_and_posts")
        let canEditAll = user.hasPrivilege(name: "wired.account.board.edit_all_threads_and_posts")
        if !(canEditAll || (canEditOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let thread = App.boardsController.editThread(uuid: uuid, subject: subject, text: text) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadChanged(thread: thread)
        self.recordEvent(.boardEditedThread, client: client, parameters: [thread.subject, thread.board])
    }

    private func receiveBoardMoveThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.move_threads") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.thread"),
            let newBoard = message.string(forField: "wired.board.new_board"),
            !uuid.isEmpty,
            !newBoard.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard App.boardsController.getThread(uuid: uuid) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard App.boardsController.getBoardInfo(path: newBoard) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        guard let existingThread = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let thread = App.boardsController.moveThread(uuid: uuid, toBoard: newBoard) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadMoved(thread: thread)
        self.recordEvent(.boardMovedThread, client: client, parameters: [thread.subject, existingThread.board, newBoard])
    }

    private func receiveBoardDeleteThread(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let uuid = message.uuid(forField: "wired.board.thread"), !uuid.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.getThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canDeleteOwn = user.hasPrivilege(name: "wired.account.board.delete_own_threads_and_posts")
        let canDeleteAll = user.hasPrivilege(name: "wired.account.board.delete_all_threads_and_posts")
        if !(canDeleteAll || (canDeleteOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard App.boardsController.deleteThread(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadDeleted(uuid: uuid)
        self.recordEvent(.boardDeletedThread, client: client, parameters: [existing.subject, existing.board])
    }

    private func receiveBoardAddPost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard user.hasPrivilege(name: "wired.account.board.add_posts") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let threadUUID = message.uuid(forField: "wired.board.thread"),
            let text = message.string(forField: "wired.board.text"),
            !threadUUID.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let thread = App.boardsController.getThread(uuid: threadUUID) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }

        guard let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.board_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canWrite(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let post = App.boardsController.addPost(
            threadUUID: threadUUID,
            text: text,
            nick: client.nick ?? username,
            login: username,
            icon: client.icon
        ),
        let updatedThread = App.boardsController.getThread(uuid: threadUUID) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        broadcastThreadChanged(thread: updatedThread, appendedPost: post)
        self.recordEvent(.boardAddedPost, client: client, parameters: [updatedThread.subject, updatedThread.board])
    }

    private func receiveBoardEditPost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard
            let uuid = message.uuid(forField: "wired.board.post"),
            let text = message.string(forField: "wired.board.text"),
            !uuid.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.posts[uuid.lowercased()] else {
            App.serverController.replyError(client: client, error: "wired.error.post_not_found", message: message)
            return
        }
        let threadUUID = existing.thread

        let username = user.username ?? ""
        let canEditOwn = user.hasPrivilege(name: "wired.account.board.edit_own_threads_and_posts")
        let canEditAll = user.hasPrivilege(name: "wired.account.board.edit_all_threads_and_posts")
        if !(canEditAll || (canEditOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard App.boardsController.editPost(uuid: uuid, text: text) != nil else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        if let thread = App.boardsController.getThread(uuid: threadUUID) {
            broadcastThreadChanged(thread: thread)
            self.recordEvent(.boardEditedPost, client: client, parameters: [thread.subject, thread.board])
        }
    }

    private func receiveBoardDeletePost(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        guard let uuid = message.uuid(forField: "wired.board.post"), !uuid.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let existing = App.boardsController.posts[uuid.lowercased()] else {
            App.serverController.replyError(client: client, error: "wired.error.post_not_found", message: message)
            return
        }

        let username = user.username ?? ""
        let canDeleteOwn = user.hasPrivilege(name: "wired.account.board.delete_own_threads_and_posts")
        let canDeleteAll = user.hasPrivilege(name: "wired.account.board.delete_all_threads_and_posts")
        if !(canDeleteAll || (canDeleteOwn && existing.login == username)) {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let threadUUID = existing.thread
        guard App.boardsController.deletePost(uuid: uuid) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        if let thread = App.boardsController.getThread(uuid: threadUUID) {
            broadcastThreadChanged(thread: thread)
            self.recordEvent(.boardDeletedPost, client: client, parameters: [thread.subject, thread.board])
        }
    }

    private func receiveBoardSubscribeBoards(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.board.read_boards") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToBoards {
            App.serverController.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToBoards = true
        App.serverController.replyOK(client: client, message: message)
    }

    private func receiveBoardUnsubscribeBoards(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.board.read_boards") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToBoards {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToBoards = false
        App.serverController.replyOK(client: client, message: message)
    }

    // MARK: - Reaction handlers

    private func receiveBoardGetReactions(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.board.read_boards") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let threadUUID = message.uuid(forField: "wired.board.thread"), !threadUUID.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let postUUID = message.uuid(forField: "wired.board.post")

        guard let thread = App.boardsController.getThread(uuid: threadUUID),
              let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }
        let username = user.username ?? ""
        guard board.canRead(user: username, group: user.group ?? "") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let summaries = App.boardsController.getReactions(threadUUID: threadUUID,
                                                          postUUID: postUUID,
                                                          currentLogin: username)
        for summary in summaries {
            let reply = P7Message(withName: "wired.board.reaction_list", spec: self.spec)
            reply.addParameter(field: "wired.board.thread", value: threadUUID)
            if let postUUID {
                reply.addParameter(field: "wired.board.post", value: postUUID)
            }
            reply.addParameter(field: "wired.board.reaction.emoji",   value: summary.emoji)
            reply.addParameter(field: "wired.board.reaction.count",   value: UInt32(summary.count))
            reply.addParameter(field: "wired.board.reaction.is_own",  value: summary.isOwn)
            if !summary.nicks.isEmpty {
                reply.addParameter(field: "wired.board.reaction.nicks", value: summary.nicks.joined(separator: "|"))
            }
            self.reply(client: client, reply: reply, message: message)
        }
        App.serverController.replyOK(client: client, message: message)
    }

    private func receiveBoardAddReaction(client: Client, message: P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }
        guard user.hasPrivilege(name: "wired.account.board.add_reactions") else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard
            let threadUUID = message.uuid(forField: "wired.board.thread"), !threadUUID.isEmpty,
            let emoji = message.string(forField: "wired.board.reaction.emoji"), !emoji.isEmpty
        else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        let postUUID = message.uuid(forField: "wired.board.post")

        guard let thread = App.boardsController.getThread(uuid: threadUUID),
              let board = App.boardsController.getBoardInfo(path: thread.board) else {
            App.serverController.replyError(client: client, error: "wired.error.thread_not_found", message: message)
            return
        }
        let username  = user.username ?? ""
        let groupName = user.group ?? ""
        guard board.canRead(user: username, group: groupName) else {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let nick = client.nick ?? username
        guard let result = App.boardsController.toggleReaction(
            threadUUID: threadUUID, postUUID: postUUID,
            emoji: emoji, login: username, nick: nick
        ) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        // If the user replaced their previous emoji, broadcast its removal first.
        if let oldEmoji = result.replacedEmoji {
            broadcastReactionChanged(board: board.path, threadUUID: threadUUID, postUUID: postUUID,
                                     emoji: oldEmoji, count: result.replacedCount, nick: nick, added: false)
        }
        broadcastReactionChanged(board: board.path, threadUUID: threadUUID, postUUID: postUUID,
                                 emoji: emoji, count: result.count, nick: nick, added: result.added)
    }

    private func broadcastReactionChanged(board: String, threadUUID: String, postUUID: String?,
                                          emoji: String, count: Int, nick: String, added: Bool) {
        let messageName = added ? "wired.board.reaction_added" : "wired.board.reaction_removed"
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username  = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let boardInfo = App.boardsController.getBoardInfo(path: board),
                  boardInfo.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: messageName, spec: self.spec)
            broadcast.addParameter(field: "wired.board.board",          value: board)
            broadcast.addParameter(field: "wired.board.thread",         value: threadUUID)
            if let postUUID {
                broadcast.addParameter(field: "wired.board.post",       value: postUUID)
            }
            broadcast.addParameter(field: "wired.board.reaction.emoji", value: emoji)
            broadcast.addParameter(field: "wired.board.reaction.count", value: UInt32(count))
            if added {
                broadcast.addParameter(field: "wired.board.reaction.nick", value: nick)
            }
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardAdded(board: Board) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            let readable = board.canRead(user: username, group: groupName)
            let writable = board.canWrite(user: username, group: groupName)

            let broadcast = P7Message(withName: "wired.board.board_added", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: board.path)
            broadcast.addParameter(field: "wired.board.readable", value: readable)
            broadcast.addParameter(field: "wired.board.writable", value: writable)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardDeleted(path: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_deleted", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardRenamed(path: String, newPath: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_renamed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            broadcast.addParameter(field: "wired.board.new_board", value: newPath)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardMoved(path: String, newPath: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.board_moved", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: path)
            broadcast.addParameter(field: "wired.board.new_board", value: newPath)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastBoardInfoChanged(board: Board) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            let broadcast = P7Message(withName: "wired.board.board_info_changed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: board.path)
            broadcast.addParameter(field: "wired.board.readable", value: board.canRead(user: username, group: groupName))
            broadcast.addParameter(field: "wired.board.writable", value: board.canWrite(user: username, group: groupName))
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadAdded(thread: Thread) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_added", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: thread.board)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.post_date", value: thread.postDate)
            broadcast.addParameter(field: "wired.board.own_thread", value: thread.login == username)
            broadcast.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            broadcast.addParameter(field: "wired.board.subject", value: thread.subject)
            broadcast.addParameter(field: "wired.user.nick", value: thread.nick)
            broadcast.addParameter(field: "wired.user.icon", value: thread.icon ?? Data())
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadChanged(thread: Thread, appendedPost: Post? = nil) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_changed", spec: self.spec)
            broadcast.addParameter(field: "wired.board.board", value: thread.board)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.subject", value: thread.subject)
            broadcast.addParameter(field: "wired.board.replies", value: UInt32(thread.replies))
            if let editDate = thread.editDate {
                broadcast.addParameter(field: "wired.board.edit_date", value: editDate)
            }
            if let latestReply = thread.latestReplyUUID {
                broadcast.addParameter(field: "wired.board.latest_reply", value: latestReply)
            }
            if let latestReplyDate = thread.latestReplyDate {
                broadcast.addParameter(field: "wired.board.latest_reply_date", value: latestReplyDate)
            }
            if let appendedPost {
                broadcast.addParameter(field: "wired.board.post", value: appendedPost.uuid)
                broadcast.addParameter(field: "wired.board.text", value: appendedPost.text)
                broadcast.addParameter(field: "wired.user.nick", value: appendedPost.nick)
                broadcast.addParameter(field: "wired.user.icon", value: appendedPost.icon ?? Data())
                broadcast.addParameter(field: "wired.board.post_date", value: appendedPost.postDate)
                broadcast.addParameter(field: "wired.board.own_post", value: appendedPost.login == username)
                if let editDate = appendedPost.editDate {
                    broadcast.addParameter(field: "wired.board.edit_date", value: editDate)
                }
            }
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadMoved(thread: Thread) {
        forEachBoardSubscriber { connectedClient, connectedUser in
            let username = connectedUser.username ?? ""
            let groupName = connectedUser.group ?? ""
            guard let board = App.boardsController.getBoardInfo(path: thread.board),
                  board.canRead(user: username, group: groupName) else { return }

            let broadcast = P7Message(withName: "wired.board.thread_moved", spec: self.spec)
            broadcast.addParameter(field: "wired.board.thread", value: thread.uuid)
            broadcast.addParameter(field: "wired.board.new_board", value: thread.board)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func broadcastThreadDeleted(uuid: String) {
        forEachBoardSubscriber { connectedClient, _ in
            let broadcast = P7Message(withName: "wired.board.thread_deleted", spec: self.spec)
            broadcast.addParameter(field: "wired.board.thread", value: uuid)
            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func forEachBoardSubscriber(_ body: (Client, User) -> Void) {
        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToBoards else { continue }
            guard let connectedUser = connectedClient.user else { continue }

            if !connectedUser.hasPrivilege(name: "wired.account.board.read_boards") {
                connectedClient.isSubscribedToBoards = false
                continue
            }
            body(connectedClient, connectedUser)
        }
    }
    
    
    private func receiveSendLogin(_ client:Client, _ message:P7Message) -> Bool {
        let clientIP = client.socket.getClientIP() ?? "unknown"

        do {
            if let ban = try App.banListController.getBan(forIPAddress: clientIP) {
                let reply = P7Message(withName: "wired.banned", spec: message.spec)
                if let expirationDate = ban.expirationDate {
                    reply.addParameter(field: "wired.banlist.expiration_date", value: expirationDate)
                }
                App.serverController.reply(client: client, reply: reply, message: message)
                Logger.warning("Rejected login for banned IP '\(clientIP)'")
                return false
            }
        } catch {
            Logger.error("Failed to check banlist for IP '\(clientIP)': \(error)")
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return false
        }

        // FINDING_A_001: Check if IP is temporarily banned due to repeated failures
        loginAttemptsLock.lock()
        if let record = loginAttempts[clientIP], let bannedUntil = record.bannedUntil {
            if Date() < bannedUntil {
                loginAttemptsLock.unlock()
                let reply = P7Message(withName: "wired.error", spec: message.spec)
                reply.addParameter(field: "wired.error.string", value: "Too many login attempts")
                reply.addParameter(field: "wired.error", value: UInt32(4))
                App.serverController.reply(client: client, reply: reply, message: message)
                Logger.warning("Login rate-limited for IP '\(clientIP)'")
                return false
            }
        }
        loginAttemptsLock.unlock()

        guard let login = message.string(forField: "wired.user.login") else {
            return false
        }

        guard let password = message.string(forField: "wired.user.password") else {
            return false
        }

        guard let user = App.usersController.user(withUsername: login, password: password) else {
            // SECURITY (FINDING_A_014): Perform dummy SHA-256 to prevent username enumeration via timing
            let _ = (UUID().uuidString + password).sha256()

            let reply = P7Message(withName: "wired.error", spec: message.spec)
            reply.addParameter(field: "wired.error.string", value: "Login failed")
            reply.addParameter(field: "wired.error", value: UInt32(4
            ))
            App.serverController.reply(client: client, reply: reply, message: message)

            Logger.warning("Login from \(clientIP) failed for '\(login)': Wrong password")

            // FINDING_A_001: Track failed attempt and apply ban if threshold reached
            loginAttemptsLock.lock()
            var record = loginAttempts[clientIP] ?? LoginAttemptRecord(failureCount: 0, bannedUntil: nil)
            record.failureCount += 1
            if record.failureCount >= maxLoginAttempts {
                record.bannedUntil = Date().addingTimeInterval(loginBanDuration)
                Logger.warning("IP '\(clientIP)' banned for \(Int(loginBanDuration))s after \(record.failureCount) failed login attempts")
            }
            loginAttempts[clientIP] = record
            loginAttemptsLock.unlock()

            self.recordEvent(.userLoginFailed, nick: client.nick, login: login, ip: clientIP)

            return false
        }

        // FINDING_A_001: Reset failure counter on successful login
        loginAttemptsLock.lock()
        loginAttempts.removeValue(forKey: clientIP)
        loginAttemptsLock.unlock()

        client.user     = user
        client.state    = .LOGGED_IN

        let response = P7Message(withName: "wired.login", spec: self.spec)
        response.addParameter(field: "wired.user.id", value: client.userID)
        App.serverController.reply(client: client, reply: response, message: message)

        client.loginTime = Date()

        let clientInfo = [client.applicationName, client.applicationVersion]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        Logger.info("Login from \(clientIP) as '\(login)' succeeded using \(clientInfo.isEmpty ? "unknown client" : clientInfo)")

        App.serverController.reply(client: client, reply: accountPrivilegesMessage(for: user), message: message)
        self.recordEvent(
            .userLoggedIn,
            client: client,
            parameters: [client.applicationName, client.osName],
            loginOverride: login
        )
        
        return true
    }
    
    
    
    private func receiveDownloadFile(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.download_files") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        guard let path = message.string(forField: "wired.file.path") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }
        
        // sanitize checks
        if !File.isValid(path: path) {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        // Normalize path (consistent with other file handlers)
        let normalizedPath = NSString(string: path).standardizingPath

        // file privileges (use dropbox-aware lookup on normalized virtual path)
        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toRead: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        guard let dataOffset = message.uint64(forField: "wired.transfer.data_offset"),
              let rsrcOffset = message.uint64(forField: "wired.transfer.rsrc_offset") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if let transfer = App.transfersController.download(path: normalizedPath,
                                                           dataOffset: dataOffset,
                                                           rsrcOffset: rsrcOffset,
                                                           client: client, message: message) {
            client.transfer = transfer

            self.recordEvent(.transferStartedFileDownload, client: client, parameters: [normalizedPath])

            if(App.transfersController.run(transfer: transfer, client: client, message: message)) {
                self.recordEvent(
                    .transferCompletedFileDownload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
                client.state = .DISCONNECTED
            } else {
                self.recordEvent(
                    .transferStoppedFileDownload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
            }
            
            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }
    
    
    
    
    private func receiveUploadFile(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

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
        let realPath = App.filesController.real(path: normalizedPath)
        let parentPath = realPath.stringByDeletingLastPathComponent

        // file privileges
        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }
        
        // user privileges
        if let type = File.FileType.type(path: parentPath) {
            switch type {
            case .uploads, .dropbox:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_files") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            default:
                if !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
                    App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                    return
                }
            }
        } else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }
        
        let dataSize = message.uint64(forField: "wired.transfer.data_size") ?? UInt64(0)
        let rsrcSize = message.uint64(forField: "wired.transfer.rsrc_size") ?? UInt64(0)
        
        if let transfer = App.transfersController.upload(path: normalizedPath,
                                                         dataSize: dataSize,
                                                         rsrcSize: rsrcSize,
                                                         executable: false,
                                                         client: client, message: message) {
            client.transfer = transfer

            self.recordEvent(.transferStartedFileUpload, client: client, parameters: [normalizedPath])
            
            do {
                try client.socket.set(interactive: false)
            } catch {
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
                client.transfer = nil
                return
            }
                        
            if(!App.transfersController.run(transfer: transfer, client: client, message: message)) {
                self.recordEvent(
                    .transferStoppedFileUpload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
                App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
                client.state = .DISCONNECTED
            } else {
                self.recordEvent(
                    .transferCompletedFileUpload,
                    client: client,
                    parameters: [normalizedPath, String(transfer.actualTransferred ?? 0)]
                )
            }
            
            client.transfer = nil
        } else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
        }
    }


    private func receiveUploadDirectory(_ client:Client, _ message:P7Message) {
        guard let user = client.user else {
            App.serverController.replyError(client: client, error: "wired.error.message_out_of_sequence", message: message)
            return
        }

        if !user.hasPrivilege(name: "wired.account.transfer.upload_directories") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

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
        let realPath = App.filesController.real(path: normalizedPath)

        // file privileges
        if let privilege = App.filesController.dropBoxPrivileges(forVirtualPath: normalizedPath) {
            if !user.hasPermission(toWrite: privilege) {
                App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
                return
            }
        }

        let parentPath = realPath.stringByDeletingLastPathComponent

        guard let parentType = File.FileType.type(path: parentPath) else {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType == .directory && !user.hasPrivilege(name: "wired.account.transfer.upload_anywhere") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        do {
            try FileManager.default.createDirectory(atPath: realPath, withIntermediateDirectories: true, attributes: [FileAttributeKey.posixPermissions: 0o755])
        } catch {
            App.serverController.replyError(client: client, error: "wired.error.file_not_found", message: message)
            return
        }

        if parentType != .directory {
            _ = File.FileType.set(type: parentType, path: realPath)
        }

        App.indexController.addIndex(forPath: realPath)
        App.filesController.notifyDirectoryChanged(path: normalizedPath.stringByDeletingLastPathComponent)
        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.transferCompletedDirectoryUpload, client: client, parameters: [normalizedPath])
    }
    
    
    
    
    // MARK: -
    
    private func receiveGetSettings(client:Client, message:P7Message) {
        guard let user = client.user else { return }
        if !user.hasPrivilege(name: "wired.account.settings.get_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        let response = P7Message(withName: "wired.settings.settings", spec: message.spec)
        response.addParameter(field: "wired.info.name", value: self.serverName)
        response.addParameter(field: "wired.info.description", value: self.serverDescription)
        
        if let bannerPath = bannerFilePath {
            if let data = readFileData(atPath: bannerPath) {
                response.addParameter(field: "wired.info.banner", value: data)
            }
        }
        
        response.addParameter(field: "wired.info.downloads", value: self.downloads)
        response.addParameter(field: "wired.info.uploads", value: self.uploads)
        response.addParameter(field: "wired.info.download_speed", value: self.downloadSpeed)
        response.addParameter(field: "wired.info.upload_speed", value: self.uploadSpeed)
        response.addParameter(field: "wired.settings.register_with_trackers", value: self.registerWithTrackers)
        response.addParameter(field: "wired.settings.trackers", value: self.trackers)
        response.addParameter(field: "wired.tracker.tracker", value: self.trackerEnabled)
        response.addParameter(field: "wired.tracker.categories", value: self.trackerCategories)
        
        self.reply(client: client, reply: response, message: message)
        self.recordEvent(.settingsGotSettings, client: client)
    }
    
    
    private func receiveSetSettings(client:Client, message:P7Message) {
        var changed = false

        guard let user = client.user else { return }
        if !user.hasPrivilege(name: "wired.account.settings.set_settings") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            
            return
        }
        
        if let serverName = message.string(forField: "wired.info.name") {
            if self.serverName != serverName {
                self.serverName = serverName
                App.config["server", "name"] = serverName
                changed = true
            }
        }
        
        if let serverDescription = message.string(forField: "wired.info.description") {
            if self.serverDescription != serverDescription {
                self.serverDescription = serverDescription
                App.config["server", "description"] = serverDescription
                changed = true
            }
        }
        
        if let bannerPath = bannerFilePath {
            if let bannerData = message.data(forField: "wired.info.banner") {
                try? bannerData.write(to: URL(fileURLWithPath: bannerPath))
                changed = true
            }
        }

        if let downloads = message.uint32(forField: "wired.info.downloads"), self.downloads != downloads {
            self.downloads = downloads
            App.config["transfers", "downloads"] = downloads
            changed = true
        }

        if let uploads = message.uint32(forField: "wired.info.uploads"), self.uploads != uploads {
            self.uploads = uploads
            App.config["transfers", "uploads"] = uploads
            changed = true
        }

        if let downloadSpeed = message.uint32(forField: "wired.info.download_speed"), self.downloadSpeed != downloadSpeed {
            self.downloadSpeed = downloadSpeed
            App.config["transfers", "downloadSpeed"] = downloadSpeed
            changed = true
        }

        if let uploadSpeed = message.uint32(forField: "wired.info.upload_speed"), self.uploadSpeed != uploadSpeed {
            self.uploadSpeed = uploadSpeed
            App.config["transfers", "uploadSpeed"] = uploadSpeed
            changed = true
        }

        if let registerWithTrackers = message.bool(forField: "wired.settings.register_with_trackers"),
           self.registerWithTrackers != registerWithTrackers {
            self.registerWithTrackers = registerWithTrackers
            App.config["settings", "register_with_trackers"] = registerWithTrackers
            changed = true
        }

        if let trackers = message.stringList(forField: "wired.settings.trackers") {
            let normalized = trackers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if self.trackers != normalized {
                self.trackers = normalized
                App.config["settings", "trackers"] = normalized
                changed = true
            }
        }

        if let trackerEnabled = message.bool(forField: "wired.tracker.tracker"), self.trackerEnabled != trackerEnabled {
            self.trackerEnabled = trackerEnabled
            App.config["tracker", "tracker"] = trackerEnabled
            changed = true
        }

        if let categories = message.stringList(forField: "wired.tracker.categories") {
            let normalized = categories
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if self.trackerCategories != normalized {
                self.trackerCategories = normalized
                App.config["tracker", "categories"] = normalized
                changed = true
            }
        }
        
        if changed {
            App.clientsController.broadcast(message: self.serverInfoMessage())
        }

        App.serverController.replyOK(client: client, message: message)
        self.recordEvent(.settingsSetSettings, client: client)
    }

    private func receiveAccountListUsers(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let users = App.usersController.users()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedUser in users {
            guard let username = listedUser.username else { continue }

            let reply = P7Message(withName: "wired.account.user_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: username)
            reply.addParameter(field: "wired.account.full_name", value: listedUser.fullName ?? "")
            reply.addParameter(field: "wired.account.comment", value: listedUser.comment ?? "")
            reply.addParameter(field: "wired.account.creation_time", value: listedUser.creationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: listedUser.modificationTime ?? defaultDate)
            reply.addParameter(field: "wired.account.login_time", value: listedUser.loginTime ?? defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: listedUser.editedBy ?? "")
            let downloads = UInt32(clamping: Int(listedUser.downloads ?? 0))
            let downloadTransferred = UInt64(clamping: Int(listedUser.downloadTransferred ?? 0))
            let uploads = UInt32(clamping: Int(listedUser.uploads ?? 0))
            let uploadTransferred = UInt64(clamping: Int(listedUser.uploadTransferred ?? 0))

            reply.addParameter(field: "wired.account.downloads", value: downloads)
            reply.addParameter(field: "wired.account.download_transferred", value: downloadTransferred)
            reply.addParameter(field: "wired.account.uploads", value: uploads)
            reply.addParameter(field: "wired.account.upload_transferred", value: uploadTransferred)
            reply.addParameter(field: "wired.account.group", value: listedUser.group ?? "")
            reply.addParameter(field: "wired.account.groups", value: listedUser.groups?
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty } ?? [])
            // SECURITY: password hash intentionally omitted (FINDING_A_003)
            reply.addParameter(field: "wired.account.color", value: UInt32(listedUser.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.user_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.accountListedUsers, client: client)
    }

    private func receiveAccountListGroups(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let groups = App.usersController.groups()
        let defaultDate = Date(timeIntervalSince1970: 0)

        for listedGroup in groups {
            guard let groupName = listedGroup.name else { continue }

            let reply = P7Message(withName: "wired.account.group_list", spec: self.spec)
            reply.addParameter(field: "wired.account.name", value: groupName)
            reply.addParameter(field: "wired.account.comment", value: "")
            reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
            reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
            reply.addParameter(field: "wired.account.edited_by", value: "")
            reply.addParameter(field: "wired.account.color", value: UInt32(listedGroup.color ?? "") ?? 0)

            self.reply(client: client, reply: reply, message: message)
        }

        let done = P7Message(withName: "wired.account.group_list.done", spec: self.spec)
        self.reply(client: client, reply: done, message: message)
        self.recordEvent(.accountListedGroups, client: client)
    }

    private func receiveAccountCreateUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.create_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty,
              let password = message.string(forField: "wired.account.password"),
              !password.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if App.usersController.user(withUsername: name) != nil {
            App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
            return
        }

        let primaryGroup = message.string(forField: "wired.account.group") ?? ""
        let secondaryGroups = message.stringList(forField: "wired.account.groups") ?? []
        if !primaryGroup.isEmpty && App.usersController.group(withName: primaryGroup) == nil {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }
        if secondaryGroups.contains(where: { !$0.isEmpty && App.usersController.group(withName: $0) == nil }) {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let normalizedPassword = normalizedPasswordForStorage(password)
        let account = User(username: name, password: normalizedPassword.hash)
        account.passwordSalt = normalizedPassword.salt
        account.fullName = message.string(forField: "wired.account.full_name") ?? ""
        account.comment = message.string(forField: "wired.account.comment") ?? ""
        account.group = primaryGroup
        account.groups = secondaryGroups.joined(separator: ", ")
        account.files = message.string(forField: "wired.account.files")
        account.creationTime = Date()
        account.modificationTime = account.creationTime
        account.editedBy = requestingUser.username ?? ""

        if let identity = message.string(forField: "wired.account.identity")?.trimmingCharacters(in: .whitespacesAndNewlines),
           !identity.isEmpty {
            if !App.usersController.isIdentityAvailable(identity) {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.identity = identity
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        guard App.usersController.save(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        var privilegesSaved = true
        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            guard field.type == .bool else { continue }
            if let value = message.bool(forField: privilege) {
                if value && !requestingUser.hasPrivilege(name: privilege) {
                    privilegesSaved = false
                    continue
                }
                if !App.usersController.setUserPrivilege(privilege, value: value, for: account) {
                    privilegesSaved = false
                }
            }
        }

        if !privilegesSaved {
            _ = App.usersController.delete(user: account)
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountCreatedUser, client: client, parameters: [name])
    }

    private func receiveAccountCreateGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.create_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name")?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        if App.usersController.group(withName: name) != nil {
            App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
            return
        }

        let account = Group(name: name)
        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        guard App.usersController.save(group: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        var privilegesSaved = true
        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            guard field.type == .bool else { continue }
            if let value = message.bool(forField: privilege) {
                if value && !requestingUser.hasPrivilege(name: privilege) {
                    privilegesSaved = false
                    continue
                }
                if !App.usersController.setGroupPrivilege(privilege, value: value, for: account) {
                    privilegesSaved = false
                }
            }
        }

        if !privilegesSaved {
            _ = App.usersController.delete(group: account)
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountCreatedGroup, client: client, parameters: [name])
    }

    private func receiveAccountChangePassword(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.change_password") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let password = message.string(forField: "wired.account.password"), !password.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.user(withUsername: requestingUser.username ?? "") else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let result = normalizedPasswordForStorage(password)
        account.password = result.hash
        account.passwordSalt = result.salt

        guard App.usersController.save(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        Logger.info("Password changed for user '\(requestingUser.username ?? "")'")

        let reply = P7Message(withName: "wired.okay", spec: self.spec)
        App.serverController.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountChangedPassword, client: client)
    }

    private func receiveAccountReadUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountUserMessage(for: account, name: "wired.account.user")
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountReadUser, client: client, parameters: [name])
    }

    private func receiveAccountReadGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.read_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        let reply = accountGroupMessage(for: account, name: "wired.account.group")
        self.reply(client: client, reply: reply, message: message)
        self.recordEvent(.accountReadGroup, client: client, parameters: [name])
    }

    private func receiveAccountEditUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        // SECURITY (FINDING_F_006): Prevent non-admin users from editing the "admin" account
        if name == "admin" && requestingUser.username != "admin" {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.user(withUsername: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.username = newName
        }

        if let fullName = message.string(forField: "wired.account.full_name") {
            account.fullName = fullName
        }
        if let comment = message.string(forField: "wired.account.comment") {
            account.comment = comment
        }
        var passwordChanged = false
        if let password = message.string(forField: "wired.account.password"), !password.isEmpty {
            let result = normalizedPasswordForStorage(password)
            // Only update stored hash+salt when the derived hash actually changes.
            // The client always sends passwordForAccountEdit() — even for permissions-only edits
            // it sends SHA256("") — so we must compare against the current stored hash to avoid
            // unnecessary salt regeneration and spurious session disconnection.
            if result.hash != account.password {
                account.password = result.hash
                account.passwordSalt = result.salt
                passwordChanged = true
            }
        }
        if let group = message.string(forField: "wired.account.group") {
            account.group = group
        }
        if let secondaryGroups = message.stringList(forField: "wired.account.groups") {
            account.groups = secondaryGroups.joined(separator: ", ")
        }

        account.editedBy = requestingUser.username ?? ""
        account.modificationTime = Date()

        var privilegesSaved = true

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    // SECURITY (FINDING_F_006): Cannot grant a privilege the editing user does not possess
                    if value == true && !requestingUser.hasPrivilege(name: privilege) {
                        continue
                    }
                    if !App.usersController.setUserPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if !App.usersController.save(user: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.username ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.recordEvent(.accountEditedUser, client: client, parameters: [updatedName])

        // SECURITY (FINDING_A_016): Invalidate other sessions after password change
        if passwordChanged {
            let targetName = normalizedAccountIdentifier(updatedName)
            for connectedClient in App.clientsController.connectedClientsSnapshot() {
                guard connectedClient.state == .LOGGED_IN else { continue }
                guard connectedClient.userID != client.userID else { continue }
                guard let connectedUsername = connectedClient.user?.username else { continue }
                if normalizedAccountIdentifier(connectedUsername) == targetName {
                    self.disconnectClient(client: connectedClient)
                }
            }
        }

        self.reloadPrivilegesForLoggedInUsers(matchingAccountNames: [name, updatedName])
    }

    private func receiveAccountEditGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.edit_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if let newName = message.string(forField: "wired.account.new_name"), !newName.isEmpty, newName != name {
            if App.usersController.group(withName: newName) != nil {
                App.serverController.replyError(client: client, error: "wired.error.account_exists", message: message)
                return
            }
            account.name = newName
        }

        var privilegesSaved = true

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                if let value = message.bool(forField: privilege) {
                    if !App.usersController.setGroupPrivilege(privilege, value: value, for: account) {
                        privilegesSaved = false
                    }
                }
            case .enum32, .uint32:
                if privilege == "wired.account.color", let value = message.uint32(forField: privilege) {
                    account.color = String(value)
                }
            default:
                break
            }
        }

        if let color = message.enumeration(forField: "wired.account.color")
            ?? message.uint32(forField: "wired.account.color") {
            account.color = String(color)
        }

        if !privilegesSaved {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        if !App.usersController.save(group: account) {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)

        let updatedName = account.name ?? name
        if updatedName != name {
            self.broadcastAccountsChangedToSubscribers()
        }

        self.recordEvent(.accountEditedGroup, client: client, parameters: [updatedName])

        self.reloadPrivilegesForLoggedInUsers(affectedByGroups: [name, updatedName])
    }

    private func receiveAccountDeleteUser(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.delete_users") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty,
              let disconnectUsers = message.bool(forField: "wired.account.disconnect_users") else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.userWithPrivileges(withUsername: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        if name == "admin" && requestingUser.username != "admin" {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        let targetName = normalizedAccountIdentifier(name)
        let connectedClients = App.clientsController.connectedClientsSnapshot().filter { connectedClient in
            guard connectedClient.state == .LOGGED_IN else { return false }
            guard let connectedName = connectedClient.user?.username else { return false }
            return normalizedAccountIdentifier(connectedName) == targetName
        }

        if !disconnectUsers && !connectedClients.isEmpty {
            App.serverController.replyError(client: client, error: "wired.error.account_in_use", message: message)
            return
        }

        guard App.usersController.delete(user: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        for connectedClient in connectedClients {
            self.disconnectClient(client: connectedClient)
        }

        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountDeletedUser, client: client, parameters: [name])
    }

    private func receiveAccountDeleteGroup(client: Client, message: P7Message) {
        guard let requestingUser = client.user else { return }

        if !requestingUser.hasPrivilege(name: "wired.account.account.delete_groups") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        guard let name = message.string(forField: "wired.account.name"), !name.isEmpty else {
            App.serverController.replyError(client: client, error: "wired.error.invalid_message", message: message)
            return
        }

        guard let account = App.usersController.groupWithPrivileges(withName: name) else {
            App.serverController.replyError(client: client, error: "wired.error.account_not_found", message: message)
            return
        }

        guard App.usersController.delete(group: account) else {
            App.serverController.replyError(client: client, error: "wired.error.internal_error", message: message)
            return
        }

        App.serverController.replyOK(client: client, message: message)
        self.broadcastAccountsChangedToSubscribers()
        self.recordEvent(.accountDeletedGroup, client: client, parameters: [name])
        self.reloadPrivilegesForLoggedInUsers(affectedByGroups: [name])
    }

    private func receiveAccountSubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.already_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = true
        App.serverController.replyOK(client: client, message: message)
    }

    private func receiveAccountUnsubscribeAccounts(client: Client, message: P7Message) {
        guard let user = client.user else { return }

        if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
            App.serverController.replyError(client: client, error: "wired.error.permission_denied", message: message)
            return
        }

        if !client.isSubscribedToAccounts {
            App.serverController.replyError(client: client, error: "wired.error.not_subscribed", message: message)
            return
        }

        client.isSubscribedToAccounts = false
        App.serverController.replyOK(client: client, message: message)
    }

    private func accountUserMessage(for account: User, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.username ?? "")
        reply.addParameter(field: "wired.account.full_name", value: account.fullName ?? "")
        reply.addParameter(field: "wired.account.comment", value: account.comment ?? "")
        // Send stored hash so clients can echo it back unchanged on permissions-only edits.
        // The connection is already encrypted; admins can set any password via edit_user anyway.
        reply.addParameter(field: "wired.account.password", value: account.password ?? "")
        reply.addParameter(field: "wired.account.group", value: account.group ?? "")
        reply.addParameter(field: "wired.account.groups", value: account.groups?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? [])
        reply.addParameter(field: "wired.account.creation_time", value: account.creationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: account.modificationTime ?? defaultDate)
        reply.addParameter(field: "wired.account.login_time", value: account.loginTime ?? defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: account.editedBy ?? "")
        reply.addParameter(field: "wired.account.downloads", value: UInt32(clamping: Int(account.downloads ?? 0)))
        reply.addParameter(field: "wired.account.uploads", value: UInt32(clamping: Int(account.uploads ?? 0)))
        reply.addParameter(field: "wired.account.download_transferred", value: UInt64(clamping: Int(account.downloadTransferred ?? 0)))
        reply.addParameter(field: "wired.account.upload_transferred", value: UInt64(clamping: Int(account.uploadTransferred ?? 0)))

        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    // SECURITY (FINDING_A_004): Salted SHA-256 password storage
    // SECURITY (FINDING_A_004): Normalize password for storage and generate a fresh per-user salt.
    //
    // stored.password  = SHA256(plaintext) — the single hash the P7 v1.2 key exchange expects
    //                    on both client and server when computing base_hash.
    // stored.passwordSalt = random UUID, sent to the client via server_challenge so the
    //                    ECDSA proof is unique per session: base_hash = SHA256(salt || SHA256(plain)).
    //
    // Do NOT double-salt here: the key exchange already mixes the stored salt into the proof.
    // Salting stored.password would produce a mismatch because the server would feed
    // SHA256(salt||SHA256(plain)) back into the base_hash formula instead of SHA256(plain).
    private func normalizedPasswordForStorage(_ password: String) -> (hash: String, salt: String) {
        let isHexSHA256 = password.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil
        let hash = isHexSHA256 ? password.lowercased() : password.sha256()
        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        return (hash: hash, salt: salt)
    }

    private func accountPrivilegesMessage(for account: User) -> P7Message {
        let reply = P7Message(withName: "wired.account.privileges", spec: self.spec)
        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func broadcastAccountsChangedToSubscribers() {
        let broadcast = P7Message(withName: "wired.account.accounts_changed", spec: self.spec)

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard connectedClient.isSubscribedToAccounts else { continue }
            guard let user = connectedClient.user else { continue }

            if !user.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
                continue
            }

            _ = self.send(message: broadcast, client: connectedClient)
        }
    }

    private func reloadPrivilegesForLoggedInUsers(matchingAccountNames accountNames: [String]) {
        let normalizedNames = Set(accountNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentName = connectedClient.user?.username else { continue }
            let normalizedCurrentName = normalizedAccountIdentifier(currentName)
            guard normalizedNames.contains(normalizedCurrentName) else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: currentName) else { continue }

            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.log.view_log") {
                connectedClient.isSubscribedToLog = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)
        }
    }

    private func reloadPrivilegesForLoggedInUsers(affectedByGroups groupNames: [String]) {
        let normalizedNames = Set(groupNames.map { normalizedAccountIdentifier($0) }.filter { !$0.isEmpty })
        guard !normalizedNames.isEmpty else { return }

        for connectedClient in App.clientsController.connectedClientsSnapshot() {
            guard connectedClient.state == .LOGGED_IN else { continue }
            guard let currentUser = connectedClient.user else { continue }
            guard let username = currentUser.username else { continue }

            let currentGroups = normalizedGroupIdentifiers(for: currentUser)
            let wasInAffectedGroup = !currentGroups.isDisjoint(with: normalizedNames)
            guard wasInAffectedGroup else { continue }

            guard let refreshedUser = userWithPrivileges(matchingUsername: username) else { continue }
            connectedClient.user = refreshedUser

            if !refreshedUser.hasPrivilege(name: "wired.account.account.list_accounts") {
                connectedClient.isSubscribedToAccounts = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.events.view_events") {
                connectedClient.isSubscribedToEvents = false
            }

            if !refreshedUser.hasPrivilege(name: "wired.account.log.view_log") {
                connectedClient.isSubscribedToLog = false
            }

            _ = self.send(message: self.accountPrivilegesMessage(for: refreshedUser), client: connectedClient)
        }
    }

    private func normalizedAccountIdentifier(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizedGroupIdentifiers(for user: User) -> Set<String> {
        var groups = Set<String>()

        if let primary = user.group {
            let normalized = normalizedAccountIdentifier(primary)
            if !normalized.isEmpty {
                groups.insert(normalized)
            }
        }

        if let secondaryGroups = user.groups {
            for raw in secondaryGroups.split(separator: ",") {
                let normalized = normalizedAccountIdentifier(String(raw))
                if !normalized.isEmpty {
                    groups.insert(normalized)
                }
            }
        }

        return groups
    }

    private func userWithPrivileges(matchingUsername username: String) -> User? {
        if let exact = App.usersController.userWithPrivileges(withUsername: username) {
            return exact
        }

        let normalizedUsername = normalizedAccountIdentifier(username)
        guard !normalizedUsername.isEmpty else { return nil }

        for listedUser in App.usersController.users() {
            guard let listedUsername = listedUser.username else { continue }
            if normalizedAccountIdentifier(listedUsername) == normalizedUsername {
                return App.usersController.userWithPrivileges(withUsername: listedUsername)
            }
        }

        return nil
    }

    private func accountGroupMessage(for account: Group, name: String) -> P7Message {
        let defaultDate = Date(timeIntervalSince1970: 0)
        let reply = P7Message(withName: name, spec: self.spec)

        reply.addParameter(field: "wired.account.name", value: account.name ?? "")
        reply.addParameter(field: "wired.account.comment", value: "")
        reply.addParameter(field: "wired.account.creation_time", value: defaultDate)
        reply.addParameter(field: "wired.account.modification_time", value: defaultDate)
        reply.addParameter(field: "wired.account.edited_by", value: "")

        let privilegesByName = Dictionary(uniqueKeysWithValues: account.privileges.map { (($0.name ?? ""), $0.value ?? false) })

        for privilege in self.accountPrivilegesIncludingColor() {
            guard let field = spec?.fieldsByName[privilege] else { continue }
            switch field.type {
            case .bool:
                reply.addParameter(field: privilege, value: privilegesByName[privilege] ?? false)
            case .enum32, .uint32:
                if privilege == "wired.account.color" {
                    reply.addParameter(field: privilege, value: UInt32(account.color ?? "") ?? 0)
                } else {
                    reply.addParameter(field: privilege, value: UInt32(0))
                }
            default:
                break
            }
        }

        return reply
    }

    private func accountPrivilegesIncludingColor() -> [String] {
        var privileges = spec?.accountPrivileges ?? []

        if spec?.fieldsByName["wired.account.color"] != nil,
           !privileges.contains("wired.account.color") {
            privileges.append("wired.account.color")
        }

        return privileges
    }
    
    
    
    
    // MARK: -
    
    private func sendUserStatus(forClient client:Client) {
        for chat in App.chatsController.publicChats {
            let broadcast = P7Message(withName: "wired.chat.user_status", spec: self.spec)
            
            broadcast.addParameter(field: "wired.chat.id", value: chat.chatID)
            broadcast.addParameter(field: "wired.user.id", value: client.userID)
            broadcast.addParameter(field: "wired.user.idle", value: client.idle)
            broadcast.addParameter(field: "wired.user.nick", value: client.nick)
            broadcast.addParameter(field: "wired.user.status", value: client.status)
            broadcast.addParameter(field: "wired.user.icon", value: client.icon)
            broadcast.addParameter(field: "wired.account.color", value: client.accountColor)
            
            App.clientsController.broadcast(message: broadcast)
        }
    }
    
    
    private func serverInfoMessage() -> P7Message {
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
    
    
    
    
    // MARK: -
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

            // SECURITY (FUZZ_002): Reject connections that would exceed the concurrent limit
            // to prevent GCD thread-pool exhaustion from pre-auth connection floods.
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
                        cipher:      self.serverCipher,
                        checksum:    self.serverChecksum
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
    
    
    private func clientLoop(_ client:Client) {
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
