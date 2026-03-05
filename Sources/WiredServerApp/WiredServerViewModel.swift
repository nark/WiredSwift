import AppKit
import Foundation
import Network
import ServiceManagement
import SQLite3
import WiredSwift

@MainActor
@available(macOS 12.0, *)
final class WiredServerViewModel: ObservableObject {
    @Published var workingDirectory: String
    @Published var binaryPath: String = ""

    @Published var isInstalled: Bool = false
    @Published var isRunning: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var launchServerAtAppStart: Bool = false

    @Published var serverPort: Int = 4871
    @Published var portStatus: PortStatus = .unknown

    @Published var filesDirectory: String = ""
    @Published var filesReindexInterval: Int = 3600

    @Published var serverName: String = "Wired Server"
    @Published var serverDescription: String = "Welcome to Wired Server"
    @Published var transferDownloads: Int = 10
    @Published var transferUploads: Int = 10
    @Published var downloadSpeed: Int = 0
    @Published var uploadSpeed: Int = 0
    @Published var registerWithTrackers: Bool = false
    @Published var trackers: String = "wired.read-write.fr"
    @Published var compressionMode: String = P7Socket.Compression.ALL.description
    @Published var cipherMode: String = P7Socket.CipherType.SECURE_ONLY.description
    @Published var checksumMode: String = P7Socket.Checksum.SECURE_ONLY.description

    @Published var adminStatus: String = "Inconnu"
    @Published var hasAdminPassword: Bool = false
    @Published var newAdminPassword: String = ""

    @Published var logsText: String = ""

    @Published var isBusy: Bool = false
    @Published var statusMessage: String = ""

    @Published var showErrorAlert: Bool = false
    @Published var lastErrorMessage: String = ""

    private let fileManager = FileManager.default
    private var pollTimer: Timer?
    private var process: Process?

    private let userDefaults = UserDefaults.standard
    private let launchAtLoginKey = "wiredswift.server.launchAtLogin"
    private let launchAtAppStartKey = "wiredswift.server.launchAtAppStart"

    struct AdvancedOption: Identifiable, Hashable {
        let id: String
        let title: String
    }

    let compressionOptions: [AdvancedOption] = [
        .init(id: P7Socket.Compression.ALL.description, title: P7Socket.Compression.ALL.description),
        .init(id: P7Socket.Compression.COMPRESSION_ONLY.description, title: P7Socket.Compression.COMPRESSION_ONLY.description),
        .init(id: P7Socket.Compression.NONE.description, title: P7Socket.Compression.NONE.description),
        .init(id: P7Socket.Compression.DEFLATE.description, title: P7Socket.Compression.DEFLATE.description),
        .init(id: P7Socket.Compression.LZFSE.description, title: P7Socket.Compression.LZFSE.description),
        .init(id: P7Socket.Compression.LZ4.description, title: P7Socket.Compression.LZ4.description)
    ]

    let cipherOptions: [AdvancedOption] = [
        .init(id: P7Socket.CipherType.ALL.description, title: P7Socket.CipherType.ALL.description),
        .init(id: P7Socket.CipherType.SECURE_ONLY.description, title: P7Socket.CipherType.SECURE_ONLY.description),
        .init(id: P7Socket.CipherType.NONE.description, title: P7Socket.CipherType.NONE.description),
        .init(id: P7Socket.CipherType.ECDH_AES256_SHA256.description, title: P7Socket.CipherType.ECDH_AES256_SHA256.description),
        .init(id: P7Socket.CipherType.ECDH_AES128_GCM.description, title: P7Socket.CipherType.ECDH_AES128_GCM.description),
        .init(id: P7Socket.CipherType.ECDH_AES256_GCM.description, title: P7Socket.CipherType.ECDH_AES256_GCM.description),
        .init(id: P7Socket.CipherType.ECDH_CHACHA20_POLY1305.description, title: P7Socket.CipherType.ECDH_CHACHA20_POLY1305.description),
        .init(id: P7Socket.CipherType.ECDH_XCHACHA20_POLY1305.description, title: P7Socket.CipherType.ECDH_XCHACHA20_POLY1305.description)
    ]

    let checksumOptions: [AdvancedOption] = [
        .init(id: P7Socket.Checksum.ALL.description, title: P7Socket.Checksum.ALL.description),
        .init(id: P7Socket.Checksum.SECURE_ONLY.description, title: P7Socket.Checksum.SECURE_ONLY.description),
        .init(id: P7Socket.Checksum.NONE.description, title: P7Socket.Checksum.NONE.description),
        .init(id: P7Socket.Checksum.SHA2_256.description, title: P7Socket.Checksum.SHA2_256.description),
        .init(id: P7Socket.Checksum.SHA2_384.description, title: P7Socket.Checksum.SHA2_384.description),
        .init(id: P7Socket.Checksum.SHA3_256.description, title: P7Socket.Checksum.SHA3_256.description),
        .init(id: P7Socket.Checksum.SHA3_384.description, title: P7Socket.Checksum.SHA3_384.description),
        .init(id: P7Socket.Checksum.HMAC_256.description, title: P7Socket.Checksum.HMAC_256.description),
        .init(id: P7Socket.Checksum.HMAC_384.description, title: P7Socket.Checksum.HMAC_384.description)
    ]

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        self.workingDirectory = appSupport.appendingPathComponent("Wired3", isDirectory: true).path
        self.launchServerAtAppStart = userDefaults.bool(forKey: launchAtAppStartKey)

        if #available(macOS 13.0, *) {
            self.launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            self.launchAtLogin = userDefaults.bool(forKey: launchAtLoginKey)
        }

        self.binaryPath = installedBinaryPath

        if launchServerAtAppStart {
            Task {
                await startServer()
            }
        }
    }

    var configPath: String {
        URL(fileURLWithPath: workingDirectory).appendingPathComponent("etc/config.ini").path
    }

    var logPath: String {
        URL(fileURLWithPath: workingDirectory).appendingPathComponent("wired.log").path
    }

    var databasePath: String {
        URL(fileURLWithPath: workingDirectory).appendingPathComponent("wired3.db").path
    }

    var runtimeFilesPath: String {
        URL(fileURLWithPath: workingDirectory).appendingPathComponent("files").path
    }

    var installedBinaryPath: String {
        URL(fileURLWithPath: workingDirectory).appendingPathComponent("bin/wired3").path
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollState()
            }
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func refreshAll() {
        bootstrapRuntimeIfNeeded()
        refreshInstallStatus()
        loadConfig()
        refreshRunningStatus()
        refreshAdminStatus()
        refreshLogText()
        checkPort()
    }

    func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"

        if panel.runModal() == .OK, let selected = panel.url?.path {
            workingDirectory = selected
            binaryPath = installedBinaryPath
            refreshAll()
        }
    }

    func chooseFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choisir"

        if panel.runModal() == .OK, let selected = panel.url?.path {
            filesDirectory = selected
            saveFilesSettings()
        }
    }

    func chooseBinaryPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Selectionner"

        if panel.runModal() == .OK, let selected = panel.url?.path {
            binaryPath = selected
            refreshInstallStatus()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
                launchAtLogin = enabled
            } catch {
                publishError("Impossible de changer l'ouverture a la connexion: \(error.localizedDescription)")
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        } else {
            userDefaults.set(enabled, forKey: launchAtLoginKey)
            launchAtLogin = enabled
        }
    }

    func toggleLaunchAtAppStart(_ enabled: Bool) {
        launchServerAtAppStart = enabled
        userDefaults.set(enabled, forKey: launchAtAppStartKey)
    }

    func installServer() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        do {
            bootstrapRuntimeIfNeeded()
            statusMessage = "Installation en cours..."

            let source = try await resolveInstallSourceBinary()
            try installBinary(from: source)

            refreshInstallStatus()
            statusMessage = "Serveur installe"
        } catch {
            publishError("Installation impossible: \(error.localizedDescription)")
        }
    }

    func uninstallServer() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        stopServer()

        do {
            if fileManager.fileExists(atPath: workingDirectory) {
                try fileManager.removeItem(atPath: workingDirectory)
            }
            statusMessage = "Serveur desinstalle"
            refreshAll()
        } catch {
            publishError("Desinstallation impossible: \(error.localizedDescription)")
        }
    }

    func startServer() async {
        refreshRunningStatus()
        guard !isRunning else { return }

        do {
            bootstrapRuntimeIfNeeded()
            try repairPartiallyInitializedDatabaseIfNeeded()
            if !fileManager.isExecutableFile(atPath: installedBinaryPath) {
                try await installServerIfNeeded()
            }

            let executable = fileManager.isExecutableFile(atPath: installedBinaryPath) ? installedBinaryPath : binaryPath
            guard fileManager.isExecutableFile(atPath: executable) else {
                throw WiredServerError.missingBinary
            }

            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
            task.arguments = [
                "--working-directory", workingDirectory,
                "--db", databasePath,
                "--config", configPath,
                "--root", (filesDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? runtimeFilesPath : filesDirectory)
            ]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in
                    self?.appendLog(line)
                }
            }

            try task.run()
            process = task
            isRunning = true
            statusMessage = "Serveur demarre"

            task.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    self?.isRunning = false
                    self?.statusMessage = "Serveur arrete"
                }
            }
        } catch {
            publishError("Demarrage impossible: \(error.localizedDescription)")
        }
    }

    func stopServer() {
        if let task = process {
            if task.isRunning {
                task.terminate()
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.5) {
                    if task.isRunning {
                        task.interrupt()
                    }
                }
            }

            process = nil
        }

        let externalPIDs = activeServerPIDs()
        for pid in externalPIDs {
            kill(pid, SIGTERM)
        }
        if !externalPIDs.isEmpty {
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                for pid in externalPIDs {
                    kill(pid, SIGKILL)
                }
            }
        }

        refreshRunningStatus()
        if !isRunning {
            statusMessage = "Serveur arrete"
        }
    }

    func saveNetworkSettings() {
        withConfig { config in
            config["server", "port"] = String(serverPort)
        }

        if isRunning {
            statusMessage = "Port enregistre. Redemarrage requis."
        } else {
            statusMessage = "Port enregistre"
        }
    }

    func checkPort() {
        let port = serverPort
        portStatus = .unknown

        Task.detached {
            let status = await Self.probePort(port: port)
            await MainActor.run {
                self.portStatus = status
            }
        }
    }

    func saveFilesSettings() {
        withConfig { config in
            config["server", "files"] = filesDirectory
            config["settings", "reindex_interval"] = String(filesReindexInterval)
        }
        statusMessage = "Configuration fichiers enregistree"
    }

    func reindexNow() async {
        guard isRunning else {
            statusMessage = "La reindexation sera faite au prochain demarrage"
            return
        }

        stopServer()
        try? await Task.sleep(nanoseconds: 700_000_000)
        await startServer()
        statusMessage = "Serveur redemarre, reindexation relancee"
    }

    func saveAdvancedSettings() {
        withConfig { config in
            config["server", "name"] = serverName
            config["server", "description"] = serverDescription

            config["transfers", "downloads"] = String(transferDownloads)
            config["transfers", "uploads"] = String(transferUploads)
            config["transfers", "downloadSpeed"] = String(downloadSpeed)
            config["transfers", "uploadSpeed"] = String(uploadSpeed)

            config["settings", "register_with_trackers"] = registerWithTrackers ? "yes" : "no"
            config["settings", "trackers"] = serializeTrackers(trackers)

            config["advanced", "compression"] = compressionMode
            config["advanced", "cipher"] = cipherMode
            config["advanced", "checksum"] = checksumMode
        }

        statusMessage = "Parametres avances enregistres"
    }

    func setAdminPassword() {
        let password = newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            publishError("Le mot de passe ne peut pas etre vide")
            return
        }

        do {
            try ensureAdminAccountExists()
            try openDatabase { db in
                let hash = sha256(password)
                try executeSQL(db, "UPDATE users SET password = ?, modification_time = CURRENT_TIMESTAMP WHERE username = 'admin';", values: [hash])
            }
            newAdminPassword = ""
            refreshAdminStatus()
            statusMessage = "Mot de passe admin mis a jour"
        } catch {
            publishError("Impossible de definir le mot de passe admin: \(error.localizedDescription)")
        }
    }

    func createAdminUser() {
        do {
            try openDatabase { db in
                let existing = try querySingleString(db, "SELECT username FROM users WHERE username = 'admin' LIMIT 1;")
                if existing == nil {
                    let hash = sha256(newAdminPassword.isEmpty ? "admin" : newAdminPassword)
                    try executeSQL(
                        db,
                        "INSERT INTO users (username, password, full_name, identity, creation_time, modification_time, color, `group`) VALUES (?, ?, 'Administrator', 'admin', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '1', 'admin');",
                        values: ["admin", hash]
                    )
                }
            }

            refreshAdminStatus()
            statusMessage = "Compte admin cree"
        } catch {
            publishError("Creation du compte admin impossible: \(error.localizedDescription)")
        }
    }

    func openLogsInFinder() {
        let url = URL(fileURLWithPath: logPath)
        NSWorkspace.shared.open(url)
    }

    private func pollState() {
        refreshRunningStatus()
        refreshLogText()
    }

    private func refreshInstallStatus() {
        isInstalled = fileManager.isExecutableFile(atPath: installedBinaryPath) || fileManager.isExecutableFile(atPath: binaryPath)
    }

    private func refreshRunningStatus() {
        if let task = process {
            isRunning = task.isRunning
        } else {
            isRunning = !activeServerPIDs().isEmpty
        }
    }

    private func activeServerPIDs() -> [Int32] {
        let output = runCommand("/usr/sbin/lsof", ["-t", databasePath])
        guard !output.isEmpty else { return [] }

        let pids = output
            .split(separator: "\n")
            .compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }

        return pids.filter { pid in
            let command = runCommand("/bin/ps", ["-p", String(pid), "-o", "command="]).lowercased()
            return command.contains("/wired3") || command.hasSuffix("wired3")
        }
    }

    private func runCommand(_ launchPath: String, _ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }

    private func refreshAdminStatus() {
        do {
            try openDatabase { db in
                let passwordHash = try querySingleString(db, "SELECT password FROM users WHERE username = 'admin' LIMIT 1;")
                if let hash = passwordHash {
                    let emptyHash = sha256("")
                    hasAdminPassword = !(hash.isEmpty || hash == emptyHash)
                    adminStatus = hasAdminPassword ? "Compte admin securise" : "Compte admin sans mot de passe"
                } else {
                    hasAdminPassword = false
                    adminStatus = "Compte admin absent"
                }
            }
        } catch let error as WiredServerError where error == .databaseNotInitialized {
            hasAdminPassword = false
            adminStatus = "Base non initialisee (demarre le serveur une fois)"
        } catch {
            hasAdminPassword = false
            adminStatus = "Compte admin indisponible"
        }
    }

    private func loadConfig() {
        let config = Config(withPath: configPath)
        guard config.load() else {
            return
        }

        serverPort = intValue(config["server", "port"], default: 4871)

        filesDirectory = stringValue(config["server", "files"], default: runtimeFilesPath)
        filesReindexInterval = intValue(config["settings", "reindex_interval"], default: 3600)

        serverName = stringValue(config["server", "name"], default: "Wired Server")
        serverDescription = stringValue(config["server", "description"], default: "Welcome to Wired Server")

        transferDownloads = intValue(config["transfers", "downloads"], default: 10)
        transferUploads = intValue(config["transfers", "uploads"], default: 10)
        downloadSpeed = intValue(config["transfers", "downloadSpeed"], default: 0)
        uploadSpeed = intValue(config["transfers", "uploadSpeed"], default: 0)

        registerWithTrackers = boolValue(config["settings", "register_with_trackers"], default: false)
        trackers = parseTrackers(stringValue(config["settings", "trackers"], default: "wired.read-write.fr"))

        let rawCompression = stringValue(config["advanced", "compression"], default: P7Socket.Compression.ALL.description)
        let rawCipher = stringValue(config["advanced", "cipher"], default: P7Socket.CipherType.SECURE_ONLY.description)
        let rawChecksum = stringValue(config["advanced", "checksum"], default: P7Socket.Checksum.SECURE_ONLY.description)

        compressionMode = normalizedCompressionMode(rawCompression)
        cipherMode = normalizedCipherMode(rawCipher)
        checksumMode = normalizedChecksumMode(rawChecksum)

        migrateAdvancedConfigIfNeeded(config: config, rawCompression: rawCompression, rawCipher: rawCipher, rawChecksum: rawChecksum)
    }

    private func migrateAdvancedConfigIfNeeded(
        config: Config,
        rawCompression: String,
        rawCipher: String,
        rawChecksum: String
    ) {
        if rawCompression.trimmingCharacters(in: .whitespacesAndNewlines) != compressionMode {
            config["advanced", "compression"] = compressionMode
        }
        if rawCipher.trimmingCharacters(in: .whitespacesAndNewlines) != cipherMode {
            config["advanced", "cipher"] = cipherMode
        }
        if rawChecksum.trimmingCharacters(in: .whitespacesAndNewlines) != checksumMode {
            config["advanced", "checksum"] = checksumMode
        }
    }

    private func refreshLogText() {
        guard fileManager.fileExists(atPath: logPath) else {
            logsText = ""
            return
        }

        if let content = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
            logsText = lines.suffix(400).joined(separator: "\n")
        }
    }

    private func appendLog(_ text: String) {
        guard !text.isEmpty else { return }
        let current = logsText + text
        let lines = current.split(separator: "\n", omittingEmptySubsequences: false)
        logsText = lines.suffix(400).joined(separator: "\n")
    }

    private func bootstrapRuntimeIfNeeded() {
        do {
            try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: URL(fileURLWithPath: workingDirectory).appendingPathComponent("etc").path, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: runtimeFilesPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(atPath: URL(fileURLWithPath: workingDirectory).appendingPathComponent("bin").path, withIntermediateDirectories: true)

            if !fileManager.fileExists(atPath: configPath) {
                try defaultConfig().write(to: URL(fileURLWithPath: configPath), atomically: true, encoding: .utf8)
            }

            if !fileManager.fileExists(atPath: logPath) {
                fileManager.createFile(atPath: logPath, contents: Data())
            }
        } catch {
            publishError("Preparation runtime impossible: \(error.localizedDescription)")
        }
    }

    private func installServerIfNeeded() async throws {
        guard !fileManager.isExecutableFile(atPath: installedBinaryPath) else { return }
        let source = try await resolveInstallSourceBinary()
        try installBinary(from: source)
    }

    private func resolveInstallSourceBinary() async throws -> String {
        let candidates = [
            binaryPath,
            packageRoot().appendingPathComponent(".build/release/wired3").path,
            packageRoot().appendingPathComponent(".build/debug/wired3").path,
            "/opt/homebrew/bin/wired3",
            "/usr/local/bin/wired3"
        ].filter { !$0.isEmpty }

        if let first = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return first
        }

        return try await buildReleaseBinary()
    }

    private func buildReleaseBinary() async throws -> String {
        statusMessage = "Compilation du binaire wired3..."

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.currentDirectoryURL = packageRoot()
        process.arguments = ["swift", "build", "-c", "release", "--product", "wired3"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        if let output = String(data: data, encoding: .utf8), !output.isEmpty {
            appendLog(output)
        }

        guard process.terminationStatus == 0 else {
            throw WiredServerError.installBuildFailed
        }

        let builtBinary = packageRoot().appendingPathComponent(".build/release/wired3").path
        guard fileManager.isExecutableFile(atPath: builtBinary) else {
            throw WiredServerError.missingBinary
        }

        return builtBinary
    }

    private func installBinary(from sourcePath: String) throws {
        let destination = installedBinaryPath
        let destinationDir = URL(fileURLWithPath: destination).deletingLastPathComponent().path
        try fileManager.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination) {
            try fileManager.removeItem(atPath: destination)
        }

        try fileManager.copyItem(atPath: sourcePath, toPath: destination)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)

        binaryPath = destination
    }

    private func withConfig(_ body: (Config) -> Void) {
        let config = Config(withPath: configPath)
        guard config.load() else {
            publishError("Impossible de lire la configuration")
            return
        }

        body(config)
    }

    private func packageRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func parseTrackers(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return json.joined(separator: ", ")
        }

        return trimmed
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "[]\"")) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    private func serializeTrackers(_ value: String) -> String {
        let list = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if list.isEmpty { return "[]" }

        if let data = try? JSONSerialization.data(withJSONObject: list, options: []),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return "[\"wired.read-write.fr\"]"
    }

    private func defaultConfig() -> String {
        let filesDefault = runtimeFilesPath.replacingOccurrences(of: "\\", with: "\\\\")

        return """
[transfers]
downloads = 10
downloadSpeed = 0
uploadSpeed = 0
uploads = 10

[server]
banner = banner.png
files = \(filesDefault)
name = Wired Server
description = Welcome to Wired Server
port = 4871

[settings]
trackers = [\"wired.read-write.fr\"]
register_with_trackers = no

[advanced]
compression = ALL
cipher = SECURE_ONLY
checksum = SECURE_ONLY
"""
    }

    private func openDatabase(_ body: (OpaquePointer) throws -> Void) throws {
        bootstrapRuntimeIfNeeded()
        guard fileManager.fileExists(atPath: databasePath) else {
            throw WiredServerError.databaseNotInitialized
        }

        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else {
            throw WiredServerError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        guard try tableExists(db, table: "users") else {
            throw WiredServerError.databaseNotInitialized
        }
        try body(db)
    }

    private func repairPartiallyInitializedDatabaseIfNeeded() throws {
        let requiredCoreTables = ["users", "groups", "chats", "index"]
        guard fileManager.fileExists(atPath: databasePath) else { return }

        let existingTables = try openRawDatabaseReturning { db in
            var found: [String] = []
            for table in requiredCoreTables where (try tableExists(db, table: table)) {
                found.append(table)
            }
            return found
        }

        guard !existingTables.isEmpty, existingTables.count < requiredCoreTables.count else {
            return
        }

        try removeDatabaseFiles()
        statusMessage = "Base partielle detectee puis reinitialisee (bootstrap propre au prochain demarrage)"
    }

    private func removeDatabaseFiles() throws {
        let candidates = [
            databasePath,
            databasePath + "-shm",
            databasePath + "-wal"
        ]

        for path in candidates where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    private func openRawDatabaseReturning<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        var db: OpaquePointer?
        guard sqlite3_open(databasePath, &db) == SQLITE_OK, let db else {
            throw WiredServerError.databaseOpenFailed
        }
        defer { sqlite3_close(db) }

        return try body(db)
    }

    private func tableExists(_ db: OpaquePointer, table: String) throws -> Bool {
        var statement: OpaquePointer?
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1;"

        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw WiredServerError.databaseStatementFailed(sql)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, table, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    private func ensureAdminAccountExists() throws {
        try openDatabase { db in
            let existing = try querySingleString(db, "SELECT username FROM users WHERE username = 'admin' LIMIT 1;")
            guard existing == nil else { return }

            let defaultPassword = sha256("admin")
            try executeSQL(
                db,
                "INSERT INTO users (username, password, full_name, identity, creation_time, modification_time, color, `group`) VALUES (?, ?, 'Administrator', 'admin', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '1', 'admin');",
                values: ["admin", defaultPassword]
            )
        }
    }

    private func executeSQL(_ db: OpaquePointer, _ sql: String, values: [String] = []) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw WiredServerError.databaseStatementFailed(sql)
        }
        defer { sqlite3_finalize(statement) }

        for (index, value) in values.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), value, -1, SQLITE_TRANSIENT)
        }

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WiredServerError.databaseExecutionFailed(sql)
        }
    }

    private func querySingleString(_ db: OpaquePointer, _ sql: String) throws -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw WiredServerError.databaseStatementFailed(sql)
        }
        defer { sqlite3_finalize(statement) }

        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else { return nil }
        guard let value = sqlite3_column_text(statement, 0) else { return nil }

        return String(cString: value)
    }

    private func sha256(_ string: String) -> String {
        return string.sha256()
    }

    private func intValue(_ any: Any?, default defaultValue: Int) -> Int {
        if let int = any as? Int {
            return int
        }
        if let value = any as? String {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? defaultValue
        }
        return defaultValue
    }

    private func stringValue(_ any: Any?, default defaultValue: String) -> String {
        if let string = any as? String {
            return string
        }
        return defaultValue
    }

    private func boolValue(_ any: Any?, default defaultValue: Bool) -> Bool {
        if let bool = any as? Bool {
            return bool
        }
        if let string = any as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes", "on":
                return true
            case "0", "false", "no", "off":
                return false
            default:
                break
            }
        }
        return defaultValue
    }

    private func normalizeToken(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let mapped = trimmed.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(String(scalar).uppercased())
            }
            return "_"
        }

        return String(mapped)
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private func normalizedCompressionMode(_ any: Any?) -> String {
        let raw = stringValue(any, default: P7Socket.Compression.ALL.description)
        if let intValue = UInt32(raw), intValue > 0 {
            let parsed = P7Socket.Compression(rawValue: intValue)
            switch parsed {
            case .ALL: return P7Socket.Compression.ALL.description
            case .COMPRESSION_ONLY: return P7Socket.Compression.COMPRESSION_ONLY.description
            case .NONE: return P7Socket.Compression.NONE.description
            case .DEFLATE: return P7Socket.Compression.DEFLATE.description
            case .LZFSE: return P7Socket.Compression.LZFSE.description
            case .LZ4: return P7Socket.Compression.LZ4.description
            default: return P7Socket.Compression.ALL.description
            }
        }

        switch normalizeToken(raw) {
        case "ALL":
            return P7Socket.Compression.ALL.description
        case "COMPRESSION_ONLY":
            return P7Socket.Compression.COMPRESSION_ONLY.description
        case "NONE":
            return P7Socket.Compression.NONE.description
        case "DEFLATE":
            return P7Socket.Compression.DEFLATE.description
        case "LZFSE":
            return P7Socket.Compression.LZFSE.description
        case "LZ4":
            return P7Socket.Compression.LZ4.description
        default:
            return P7Socket.Compression.ALL.description
        }
    }

    private func normalizedCipherMode(_ any: Any?) -> String {
        let raw = stringValue(any, default: P7Socket.CipherType.SECURE_ONLY.description)
        if let intValue = UInt32(raw), intValue > 0 {
            let parsed = P7Socket.CipherType(rawValue: intValue)
            switch parsed {
            case .ALL: return P7Socket.CipherType.ALL.description
            case .SECURE_ONLY: return P7Socket.CipherType.SECURE_ONLY.description
            case .NONE: return P7Socket.CipherType.NONE.description
            case .ECDH_AES256_SHA256: return P7Socket.CipherType.ECDH_AES256_SHA256.description
            case .ECDH_AES128_GCM: return P7Socket.CipherType.ECDH_AES128_GCM.description
            case .ECDH_AES256_GCM: return P7Socket.CipherType.ECDH_AES256_GCM.description
            case .ECDH_CHACHA20_POLY1305: return P7Socket.CipherType.ECDH_CHACHA20_POLY1305.description
            case .ECDH_XCHACHA20_POLY1305: return P7Socket.CipherType.ECDH_XCHACHA20_POLY1305.description
            default: return P7Socket.CipherType.SECURE_ONLY.description
            }
        }

        switch normalizeToken(raw) {
        case "ALL":
            return P7Socket.CipherType.ALL.description
        case "SECURE_ONLY":
            return P7Socket.CipherType.SECURE_ONLY.description
        case "NONE":
            return P7Socket.CipherType.NONE.description
        case "ECDH_AES256_SHA256", "ECDHE_ECDSA_AES256_SHA256":
            return P7Socket.CipherType.ECDH_AES256_SHA256.description
        case "ECDH_AES128_GCM", "ECDHE_ECDSA_AES128_GCM":
            return P7Socket.CipherType.ECDH_AES128_GCM.description
        case "ECDH_AES256_GCM", "ECDHE_ECDSA_AES256_GCM":
            return P7Socket.CipherType.ECDH_AES256_GCM.description
        case "ECDH_CHACHA20_POLY1305", "ECDHE_ECDSA_CHACHA20_POLY1305":
            return P7Socket.CipherType.ECDH_CHACHA20_POLY1305.description
        case "ECDH_XCHACHA20_POLY1305", "ECDHE_ECDSA_XCHACHA20_POLY1305":
            return P7Socket.CipherType.ECDH_XCHACHA20_POLY1305.description
        default:
            return P7Socket.CipherType.SECURE_ONLY.description
        }
    }

    private func normalizedChecksumMode(_ any: Any?) -> String {
        let raw = stringValue(any, default: P7Socket.Checksum.SECURE_ONLY.description)
        if let intValue = UInt32(raw), intValue > 0 {
            let parsed = P7Socket.Checksum(rawValue: intValue)
            switch parsed {
            case .ALL: return P7Socket.Checksum.ALL.description
            case .SECURE_ONLY: return P7Socket.Checksum.SECURE_ONLY.description
            case .NONE: return P7Socket.Checksum.NONE.description
            case .SHA2_256: return P7Socket.Checksum.SHA2_256.description
            case .SHA2_384: return P7Socket.Checksum.SHA2_384.description
            case .SHA3_256: return P7Socket.Checksum.SHA3_256.description
            case .SHA3_384: return P7Socket.Checksum.SHA3_384.description
            case .HMAC_256: return P7Socket.Checksum.HMAC_256.description
            case .HMAC_384: return P7Socket.Checksum.HMAC_384.description
            default: return P7Socket.Checksum.SECURE_ONLY.description
            }
        }

        switch normalizeToken(raw) {
        case "ALL":
            return P7Socket.Checksum.ALL.description
        case "SECURE_ONLY":
            return P7Socket.Checksum.SECURE_ONLY.description
        case "NONE":
            return P7Socket.Checksum.NONE.description
        case "SHA2_256":
            return P7Socket.Checksum.SHA2_256.description
        case "SHA2_384":
            return P7Socket.Checksum.SHA2_384.description
        case "SHA3_256":
            return P7Socket.Checksum.SHA3_256.description
        case "SHA3_384":
            return P7Socket.Checksum.SHA3_384.description
        case "HMAC_256":
            return P7Socket.Checksum.HMAC_256.description
        case "HMAC_384":
            return P7Socket.Checksum.HMAC_384.description
        default:
            return P7Socket.Checksum.SECURE_ONLY.description
        }
    }

    private func publishError(_ message: String) {
        lastErrorMessage = message
        showErrorAlert = true
        statusMessage = message
    }

    private static func probePort(port: Int) async -> PortStatus {
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(max(0, min(port, 65_535)))) else {
            return .closed
        }

        return await withCheckedContinuation { continuation in
            let connection = NWConnection(host: .ipv4(.loopback), port: nwPort, using: .tcp)
            let queue = DispatchQueue(label: "wired.server.port.check")
            final class ResolutionState: @unchecked Sendable {
                let lock = NSLock()
                var resolved = false
            }
            let state = ResolutionState()

            @Sendable func finish(_ status: PortStatus) {
                state.lock.lock()
                if state.resolved {
                    state.lock.unlock()
                    return
                }
                state.resolved = true
                state.lock.unlock()
                connection.cancel()
                continuation.resume(returning: status)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(.open)
                case .failed, .waiting, .cancelled:
                    finish(.closed)
                default:
                    break
                }
            }

            queue.asyncAfter(deadline: .now() + 1.5) {
                finish(.closed)
            }

            connection.start(queue: queue)
        }
    }
}

enum PortStatus {
    case unknown
    case open
    case closed

    var description: String {
        switch self {
        case .unknown:
            return "Inconnu"
        case .open:
            return "Ouvert"
        case .closed:
            return "Ferme"
        }
    }
}

enum WiredServerError: LocalizedError, Equatable {
    case missingBinary
    case installBuildFailed
    case databaseOpenFailed
    case databaseNotInitialized
    case databaseStatementFailed(String)
    case databaseExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return "Binaire wired3 introuvable"
        case .installBuildFailed:
            return "La compilation du binaire wired3 a echoue"
        case .databaseOpenFailed:
            return "Impossible d'ouvrir la base de donnees"
        case .databaseNotInitialized:
            return "Base de donnees non initialisee: demarre le serveur une premiere fois"
        case .databaseStatementFailed(let sql):
            return "Erreur SQL prepare: \(sql)"
        case .databaseExecutionFailed(let sql):
            return "Erreur SQL execution: \(sql)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
