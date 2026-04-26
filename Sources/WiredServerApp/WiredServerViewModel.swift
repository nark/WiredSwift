// swiftlint:disable file_length type_body_length
// TODO: Split WiredServerViewModel into focused sub-view-models
import AppKit
import Foundation
import Network
import ServiceManagement
#if os(Linux)
import CSQLite
#else
import SQLite3
#endif
import WiredSwift

@MainActor
@available(macOS 12.0, *)
final class WiredServerViewModel: ObservableObject {
    @Published var workingDirectory: String
    @Published var binaryPath: String = ""

    @Published var isInstalled: Bool = false
    @Published var installedServerVersion: String = "-"
    @Published var p7ProtocolVersion: String = "-"
    @Published var wiredProtocolName: String = "-"
    @Published var wiredProtocolVersion: String = "-"
    @Published var isRunning: Bool = false
    @Published var launchAtLogin: Bool = false
    @Published var launchServerAtAppStart: Bool = false

    @Published var serverPort: Int = 4871
    @Published var portStatus: PortStatus = .unknown

    @Published var filesDirectory: String = ""
    @Published var filesReindexInterval: Int = 3600
    @Published var databaseSnapshotInterval: Int = 86400
    @Published var eventRetentionPolicy: String = "never"

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

    // SECURITY (A_009): TOFU settings
    @Published var strictIdentity: Bool = true
    /// Human-readable fingerprint of the server's persistent identity key, or empty if not loaded.
    @Published var identityFingerprint: String = ""

    @Published var adminStatus: String = L("advanced.admin.status.unknown")
    @Published var hasAdminPassword: Bool = false
    @Published var newAdminPassword: String = ""

    @Published var logsText: String = ""
    @Published var dashboardServerPID: String = "-"
    @Published var dashboardServerUptime: String = "-"
    @Published var dashboardServerCPU: String = "-"
    @Published var dashboardServerMemory: String = "-"
    @Published var dashboardHostUptime: String = "-"
    @Published var dashboardConnectedUsers: Int = 0
    @Published var dashboardDatabaseSizeBytes: Int64 = 0
    @Published var dashboardFilesSizeBytes: Int64 = 0
    @Published var dashboardSnapshotSizeBytes: Int64 = 0
    @Published var dashboardDiskFreeBytes: Int64 = 0
    @Published var dashboardDiskTotalBytes: Int64 = 0
    @Published var dashboardLastSnapshotDate: Date?
    @Published var dashboardLastErrorLine: String = ""
    @Published var dashboardAccountsCount: Int = 0
    @Published var dashboardGroupsCount: Int = 0
    @Published var dashboardEventsCount: Int = 0
    @Published var dashboardBoardsCount: Int = 0
    @Published var dashboardDatabaseInitialized: Bool = false
    @Published var dashboardFilesDirectoryExists: Bool = false

    @Published var isBusy: Bool = false
    @Published var statusMessage: String = ""

    @Published var showErrorAlert: Bool = false
    @Published var lastErrorMessage: String = ""

    @Published var showRestartAfterUpdateAlert: Bool = false
    @Published var showInitialPasswordAlert: Bool = false
    @Published var initialAdminPassword: String = ""

    @Published var migrationSourcePath: String = ""
    @Published var isMigrating: Bool = false
    @Published var migrationOutput: String = ""
    @Published var migrationOverwrite: Bool = false

    private let fileManager = FileManager.default
    private var pollTimer: Timer?
    private var process: Process?

    private let userDefaults = UserDefaults.standard
    private let launchAtAppStartKey = "wiredswift.server.launchAtAppStart"
    private let workingDirectoryKey = "wired3WorkingDirectory"
    private let installModeKey = "wired3InstallMode"
    private let daemonUserNameKey = "wired3DaemonUserName"
    private let daemonGroupNameKey = "wired3DaemonGroupName"
    private let daemonStartAtBootKey = "wired3DaemonStartAtBoot"
    private let launchAgentLabel = "fr.read-write.wired3.server"
    private let launchDaemonPlistPath = "/Library/LaunchDaemons/fr.read-write.wired3.server.plist"
    private let embeddedBinarySHAKey = "Wired3EmbeddedSHA256"

    static let systemDataDirectory = "/Library/Wired3"

    @Published var isSystemMigrating: Bool = false
    @Published var systemMigrationStatus: String = ""

    @Published var installMode: ServerInstallMode = .launchAgent
    @Published var daemonUserName: String = "_wired"
    @Published var daemonGroupName: String = "daemon"
    @Published var daemonStartAtBoot: Bool = false
    @Published var isSwitchingMode: Bool = false
    @Published var modeSwitchStatus: String = ""
    @Published var isDaemonRunning: Bool = false
    @Published var isDaemonUserExists: Bool = false
    @Published var isDaemonGroupExists: Bool = false

    var isServerActive: Bool {
        installMode == .launchDaemon ? isDaemonRunning : isRunning
    }

    private var lastDashboardLightRefresh = Date.distantPast
    private var lastDashboardHeavyRefresh = Date.distantPast

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

    let eventRetentionOptions: [AdvancedOption] = [
        .init(id: "never", title: L("database.events.retention.never")),
        .init(id: "daily", title: L("database.events.retention.daily")),
        .init(id: "weekly", title: L("database.events.retention.weekly")),
        .init(id: "monthly", title: L("database.events.retention.monthly")),
        .init(id: "yearly", title: L("database.events.retention.yearly"))
    ]

    var legacyDataDirectory: String {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Wired3", isDirectory: true).path
    }

    var isUsingSystemDirectory: Bool {
        workingDirectory == Self.systemDataDirectory
    }

    var systemMigrationAvailable: Bool {
        !isUsingSystemDirectory && fileManager.fileExists(atPath: workingDirectory)
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let defaultDirectory = appSupport.appendingPathComponent("Wired3", isDirectory: true).path
        self.workingDirectory = UserDefaults.standard.string(forKey: "wired3WorkingDirectory") ?? defaultDirectory
        self.launchServerAtAppStart = UserDefaults.standard.bool(forKey: launchAtAppStartKey)

        let savedMode = UserDefaults.standard.string(forKey: "wired3InstallMode")
        self.installMode = ServerInstallMode(rawValue: savedMode ?? "") ?? .launchAgent
        self.daemonUserName = UserDefaults.standard.string(forKey: "wired3DaemonUserName") ?? "_wired"
        self.daemonGroupName = UserDefaults.standard.string(forKey: "wired3DaemonGroupName") ?? "daemon"
        self.daemonStartAtBoot = UserDefaults.standard.bool(forKey: "wired3DaemonStartAtBoot")

        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.unregister()
        }
        self.launchAtLogin = isLaunchAtLoginEnabled()

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

    var snapshotPath: String {
        databasePath + ".bak"
    }

    var serverRootPathDisplay: String {
        currentServerRootPath()
    }

    func startPolling() {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
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
        // Quick pgrep check to get a fresh isDaemonRunning before the auto-update guard.
        // pgrep works without root; launchctl print system/... can return non-zero for
        // non-root users even when the daemon is running, causing false negatives.
        if installMode == .launchDaemon {
            isDaemonRunning = runProcess("/usr/bin/pgrep", ["-f", "/Library/Wired3/bin/wired3"]).status == 0
        }
        var binaryWasUpdated = false
        // In LaunchDaemon mode: skip auto-update when daemon is running (launchd
        // kills the process on binary replacement) and only attempt when we have
        // write access to the bin directory.
        let binDir = URL(fileURLWithPath: installedBinaryPath).deletingLastPathComponent().path
        let canWrite = fileManager.isWritableFile(atPath: binDir)
        let canAutoUpdate = (installMode == .launchAgent || !isDaemonRunning) && canWrite
        if canAutoUpdate {
            do {
                binaryWasUpdated = try synchronizeInstalledBinaryIfNeeded(allowInstallIfMissing: false)
            } catch {
                publishError("\(L("error.install_failed")): \(error.localizedDescription)")
            }
        }
        refreshInstallStatus()
        // Skip version check when daemon is running: avoids launching wired3 --version
        // concurrently with the daemon process (potential interference + main thread blocking).
        if !isDaemonRunning {
            refreshInstalledVersion()
        }
        launchAtLogin = isLaunchAtLoginEnabled()
        loadConfig()
        refreshRunningStatus()
        refreshAdminStatus()
        refreshLogText()
        refreshDashboard(force: true)
        checkPort()

        if binaryWasUpdated && isRunning {
            showRestartAfterUpdateAlert = true
        }
    }

    func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("common.choose")

        if panel.runModal() == .OK, let selected = panel.url?.path {
            workingDirectory = selected
            binaryPath = installedBinaryPath
            refreshAll()
            if launchAtLogin {
                do {
                    try configureLaunchAtLogin(enabled: true)
                } catch {
                    publishError("\(L("error.launch_at_login_update_failed")): \(error.localizedDescription)")
                    launchAtLogin = isLaunchAtLoginEnabled()
                }
            }
        }
    }

    func chooseFilesDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("common.choose")

        if panel.runModal() == .OK, let selected = panel.url?.path {
            filesDirectory = selected
            saveFilesSettings()
        }
    }

    // MARK: - System Data Directory Migration

    func persistWorkingDirectory() {
        userDefaults.set(workingDirectory, forKey: workingDirectoryKey)
    }

    func migrateToSystemDirectory() async {
        guard !isSystemMigrating, systemMigrationAvailable else { return }
        isSystemMigrating = true
        systemMigrationStatus = "Preparing..."

        let source = workingDirectory

        do {
            if isRunning {
                systemMigrationStatus = "Stopping server..."
                stopServer()
                try await Task.sleep(for: .seconds(2))
            }

            systemMigrationStatus = "Creating system directory (admin required)..."
            try createSystemDataDirectory()

            systemMigrationStatus = "Copying data..."
            try copyDirectoryContents(from: source, to: Self.systemDataDirectory)

            systemMigrationStatus = "Verifying database integrity..."
            let newDBPath = URL(fileURLWithPath: Self.systemDataDirectory)
                .appendingPathComponent("wired3.db").path
            if fileManager.fileExists(atPath: newDBPath) {
                try verifySystemDatabaseIntegrity(at: newDBPath)
            }

            systemMigrationStatus = "Switching to system directory..."
            workingDirectory = Self.systemDataDirectory
            persistWorkingDirectory()
            binaryPath = installedBinaryPath

            if launchAtLogin {
                try configureLaunchAtLogin(enabled: true)
            }

            systemMigrationStatus = "Done. Backup preserved at: \(source)"
            refreshAll()
        } catch {
            systemMigrationStatus = "Migration failed: \(error.localizedDescription)"
            publishError("Data migration failed: \(error.localizedDescription)")
        }

        isSystemMigrating = false
    }

    private func createSystemDataDirectory() throws {
        let username = NSUserName()
        let script = """
        do shell script "mkdir -p /Library/Wired3 && chown \(username):staff /Library/Wired3 && chmod 755 /Library/Wired3" with administrator privileges
        """
        var errorInfo: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            throw WiredServerError.systemDirectoryCreationFailed(msg)
        }
        guard fileManager.fileExists(atPath: Self.systemDataDirectory) else {
            throw WiredServerError.systemDirectoryCreationFailed("Directory missing after creation")
        }
    }

    private func copyDirectoryContents(from source: String, to destination: String) throws {
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)
        let items = try fileManager.contentsOfDirectory(at: sourceURL, includingPropertiesForKeys: nil)
        for item in items {
            let dest = destURL.appendingPathComponent(item.lastPathComponent)
            if fileManager.fileExists(atPath: dest.path) {
                try fileManager.removeItem(at: dest)
            }
            try fileManager.copyItem(at: item, to: dest)
        }
    }

    private func verifySystemDatabaseIntegrity(at path: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw WiredServerError.systemMigrationFailed("Cannot open database for verification")
        }
        defer { sqlite3_close(db) }
        var stmt: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        if sqlite3_step(stmt) == SQLITE_ROW,
           let result = sqlite3_column_text(stmt, 0),
           String(cString: result) == "ok" { return }
        throw WiredServerError.systemMigrationFailed("Database integrity check failed")
    }

    // MARK: - LaunchDaemon / LaunchAgent Mode Switching

    func refreshDaemonStatus() {
        // pgrep works without root and is faster/more reliable than launchctl print for
        // detecting whether the daemon process is actually running.
        isDaemonRunning = runProcess("/usr/bin/pgrep", ["-f", "/Library/Wired3/bin/wired3"]).status == 0
        isDaemonUserExists = runProcess("/usr/bin/dscl", [".", "-read", "/Users/\(daemonUserName)"]).status == 0
        isDaemonGroupExists = runProcess("/usr/bin/dscl", [".", "-read", "/Groups/\(daemonGroupName)"]).status == 0
    }

    // MARK: - External Volume / FDA

    var filesDirectoryIsOnExternalVolume: Bool {
        let path = currentServerRootPath()
        return path.hasPrefix("/Volumes/")
    }

    // Checks whether wired3 has FDA by asking launchd to probe the TCC database
    // on its behalf. The app itself may not have FDA, so we probe via sqlite3 run
    // as the daemon user, falling back to a direct TCC.db read if possible.
    var wired3HasFullDiskAccess: Bool {
        let tcc = "/Library/Application Support/com.apple.TCC/TCC.db"
        let binaryPath = installedBinaryPath
        let query = "SELECT allowed FROM access WHERE service='kTCCServiceSystemPolicyAllFiles' AND client='\(binaryPath)' LIMIT 1"

        // Try reading TCC.db directly (works if this app has FDA).
        if FileManager.default.isReadableFile(atPath: tcc) {
            let output = runCommand("/usr/bin/sqlite3", [tcc, query])
            if output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" { return true }
        }

        // Fallback: run sqlite3 as the daemon user so it can read the system TCC.db.
        let result = runProcess("/usr/bin/sudo", ["-u", daemonUserName, "-n",
            "/usr/bin/sqlite3", tcc, query])
        if result.output.trimmingCharacters(in: .whitespacesAndNewlines) == "1" { return true }

        // Last resort: try to open a file in a protected location as a live FDA probe.
        // If the daemon can read /Library/Application Support/com.apple.TCC/ the grant is active.
        return FileManager.default.isReadableFile(atPath: tcc)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    var launchDaemonInstalled: Bool {
        fileManager.fileExists(atPath: launchDaemonPlistPath)
    }

    func saveDaemonSettings() {
        userDefaults.set(daemonUserName, forKey: daemonUserNameKey)
        userDefaults.set(daemonGroupName, forKey: daemonGroupNameKey)
        userDefaults.set(daemonStartAtBoot, forKey: daemonStartAtBootKey)
    }

    func switchInstallMode(to mode: ServerInstallMode) async {
        guard mode != installMode, !isSwitchingMode else { return }
        guard isUsingSystemDirectory else {
            publishError("Please migrate data to /Library/Wired3/ before switching to LaunchDaemon mode.")
            return
        }
        isSwitchingMode = true
        modeSwitchStatus = "Preparing..."
        refreshDaemonStatus()

        do {
            if isRunning {
                modeSwitchStatus = "Stopping server..."
                stopServer()
                try await Task.sleep(for: .seconds(2))
            }

            switch mode {
            case .launchDaemon:
                if launchAtLogin {
                    try configureLaunchAtLogin(enabled: false)
                    launchAtLogin = false
                }
                modeSwitchStatus = "Activating LaunchDaemon (one admin dialog)..."
                try activateLaunchDaemon(name: daemonUserName, createUser: !isDaemonUserExists)

            case .launchAgent:
                modeSwitchStatus = "Deactivating LaunchDaemon (one admin dialog)..."
                try deactivateLaunchDaemon(restoreUser: NSUserName())
            }

            installMode = mode
            userDefaults.set(mode.rawValue, forKey: installModeKey)
            modeSwitchStatus = "Done."
        } catch {
            modeSwitchStatus = "Failed: \(error.localizedDescription)"
            publishError("Mode switch failed: \(error.localizedDescription)")
        }

        isSwitchingMode = false
        refreshAll()
    }

    func toggleDaemonStartAtBoot(_ enabled: Bool) {
        daemonStartAtBoot = enabled
        userDefaults.set(enabled, forKey: daemonStartAtBootKey)
        guard launchDaemonInstalled else { return }
        do {
            try reinstallDaemonPlist()
        } catch {
            publishError("Failed to update LaunchDaemon: \(error.localizedDescription)")
        }
    }

    func startDaemon() {
        // Kill any stale LaunchAgent wired3 process (running from user home, not /Library/Wired3/).
        // This can happen when switching from LaunchAgent to LaunchDaemon mode while a server
        // is still running, or if stopServer() was skipped. Without this the daemon cannot
        // bind port 4871.
        let pgrepOut = runProcess("/usr/bin/pgrep", ["-x", "wired3"]).output
        let allWiredPIDs = pgrepOut.split(separator: "\n").compactMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let staleAgentPIDs = allWiredPIDs.filter { pid in
            let args = runProcess("/bin/ps", ["-p", "\(pid)", "-o", "args="]).output.trimmingCharacters(in: .whitespacesAndNewlines)
            return !args.hasPrefix("/Library/Wired3/bin/wired3")
        }
        for pid in staleAgentPIDs {
            kill(pid, SIGTERM)
        }
        if !staleAgentPIDs.isEmpty {
            Thread.sleep(forTimeInterval: 0.5)
        }

        // bootstrap registers the service (no-op if already registered).
        // kickstart starts it regardless of RunAtLoad value.
        let cmd = "launchctl bootstrap system '\(launchDaemonPlistPath)' 2>/dev/null; launchctl kickstart system/\(launchAgentLabel) 2>/dev/null; true"
        do {
            try runPrivileged(cmd, error: .launchDaemonInstallFailed("start"))
        } catch {
            publishError("Failed to start daemon: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshDaemonStatus()
        }
    }

    func stopDaemon() {
        do {
            try runPrivileged("launchctl bootout system/\(launchAgentLabel) 2>/dev/null; true",
                              error: .launchDaemonRemoveFailed("stop"))
        } catch {
            publishError("Failed to stop daemon: \(error.localizedDescription)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.refreshDaemonStatus()
        }
    }

    // One admin dialog: create group (optional) + create user (optional) + chown + install plist
    private func activateLaunchDaemon(name: String, createUser: Bool) throws {
        let tempURL = try writeDaemonPlistToTemp()
        let group = daemonGroupName
        let createGroup = runProcess("/usr/bin/dscl", [".", "-read", "/Groups/\(daemonGroupName)"]).status != 0

        var cmds: [String] = []

        if createGroup {
            let gid = findFreeSystemGID()
            cmds += [
                "dscl . -create /Groups/\(group)",
                "dscl . -create /Groups/\(group) PrimaryGroupID \(gid)",
                "dscl . -create /Groups/\(group) Password '*'",
                "dscl . -create /Groups/\(group) RealName 'Wired Server'"
            ]
        }

        if createUser {
            let uid = findFreeSystemUID()
            let gid = groupGID(for: group)
            cmds += [
                "dscl . -create /Users/\(name)",
                "dscl . -create /Users/\(name) UserShell /usr/bin/false",
                "dscl . -create /Users/\(name) RealName 'Wired Server'",
                "dscl . -create /Users/\(name) UniqueID \(uid)",
                "dscl . -create /Users/\(name) PrimaryGroupID \(gid)",
                "dscl . -create /Users/\(name) NFSHomeDirectory /var/empty",
                "dscl . -create /Users/\(name) IsHidden 1"
            ]
        }

        cmds += [
            "chown -R \(name):\(group) /Library/Wired3",
            // bin/ uses staff group so the admin user can write the binary (admin is not in daemon group)
            "chown \(name):staff /Library/Wired3/bin",
            "chmod 775 /Library/Wired3/bin",
            // Remove stale .updates dir: chown -R would have set it to _wired:daemon,
            // preventing admin (not in daemon group) from writing inside it.
            "rm -rf '/Library/Wired3/bin/.updates'",
            "chmod 755 /Library/Wired3/bin/wired3 2>/dev/null || true",
            // etc/ uses staff group so the admin user can write config.ini
            "chown \(name):staff /Library/Wired3/etc",
            "chmod 775 /Library/Wired3/etc",
            "chown \(name):staff /Library/Wired3/etc/config.ini 2>/dev/null || true",
            "chmod 664 /Library/Wired3/etc/config.ini 2>/dev/null || true",
            "cp '\(tempURL.path)' '\(launchDaemonPlistPath)'",
            "chmod 644 '\(launchDaemonPlistPath)'",
            "chown root:wheel '\(launchDaemonPlistPath)'"
        ]

        try runPrivileged(cmds.joined(separator: " && "),
                          error: WiredServerError.launchDaemonInstallFailed(""))
    }

    // One admin dialog: bootout + remove plist + chown back to current user
    private func deactivateLaunchDaemon(restoreUser: String) throws {
        let cmds = [
            "launchctl bootout system/\(launchAgentLabel) 2>/dev/null",
            "rm -f '\(launchDaemonPlistPath)'",
            "chown -R \(restoreUser):staff /Library/Wired3"  // back to staff for LaunchAgent
        ].joined(separator: "; ")

        try runPrivileged(cmds, error: WiredServerError.launchDaemonRemoveFailed(""))
    }

    // Used by toggleDaemonStartAtBoot — updates existing plist with one admin dialog
    private func reinstallDaemonPlist() throws {
        let tempURL = try writeDaemonPlistToTemp()
        let cmds = [
            "cp '\(tempURL.path)' '\(launchDaemonPlistPath)'",
            "chmod 644 '\(launchDaemonPlistPath)'",
            "chown root:wheel '\(launchDaemonPlistPath)'"
        ].joined(separator: " && ")
        try runPrivileged(cmds, error: WiredServerError.launchDaemonInstallFailed(""))
    }

    private func writeDaemonPlistToTemp() throws -> URL {
        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                installedBinaryPath,
                "--working-directory", workingDirectory,
                "--db", databasePath,
                "--config", configPath,
                "--root", currentServerRootPath()
            ],
            "UserName": daemonUserName,
            "WorkingDirectory": workingDirectory,
            "RunAtLoad": daemonStartAtBoot,
            "KeepAlive": false,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("fr.read-write.wired3.server.plist")
        guard (plist as NSDictionary).write(to: tempURL, atomically: true) else {
            throw WiredServerError.launchDaemonWriteFailed
        }
        return tempURL
    }

    private func runPrivileged(_ shellScript: String, error fallbackError: WiredServerError) throws {
        let appleScript = "do shell script \"\(shellScript)\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: appleScript)?.executeAndReturnError(&errorInfo)
        if let err = errorInfo {
            let msg = (err[NSAppleScript.errorMessage] as? String) ?? "Unknown error"
            // Re-throw with the actual message by matching the error type
            switch fallbackError {
            case .launchDaemonInstallFailed: throw WiredServerError.launchDaemonInstallFailed(msg)
            case .launchDaemonRemoveFailed:  throw WiredServerError.launchDaemonRemoveFailed(msg)
            default:                         throw fallbackError
            }
        }
    }

    private func findFreeSystemUID() -> Int {
        let output = runCommand("/usr/bin/dscl", [".", "-list", "/Users", "UniqueID"])
        let used = Set(output.components(separatedBy: .newlines).compactMap { line -> Int? in
            let parts = line.split(separator: " ").map(String.init)
            return parts.count >= 2 ? Int(parts.last ?? "") : nil
        })
        for uid in 400...499 where !used.contains(uid) { return uid }
        return 489
    }

    private func findFreeSystemGID() -> Int {
        let output = runCommand("/usr/bin/dscl", [".", "-list", "/Groups", "PrimaryGroupID"])
        let used = Set(output.components(separatedBy: .newlines).compactMap { line -> Int? in
            let parts = line.split(separator: " ").map(String.init)
            return parts.count >= 2 ? Int(parts.last ?? "") : nil
        })
        for gid in 400...499 where !used.contains(gid) { return gid }
        return 488
    }

    private func groupGID(for group: String) -> Int {
        let output = runCommand("/usr/bin/dscl", [".", "-read", "/Groups/\(group)", "PrimaryGroupID"])
        for line in output.components(separatedBy: .newlines) {
            let parts = line.split(separator: " ").map(String.init)
            if parts.first == "PrimaryGroupID:", let gid = Int(parts.last ?? "") {
                return gid
            }
        }
        return 20  // fall back to staff GID
    }

    // MARK: - Wired 2.5 Migration

    func chooseMigrationSource() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("common.choose")
        panel.title = L("database.migration.source")
        if panel.runModal() == .OK, let selected = panel.url?.path {
            migrationSourcePath = selected
            migrationOutput = ""
        }
    }

    func runMigration() async {
        guard !isMigrating else { return }
        guard !migrationSourcePath.isEmpty else {
            publishError(L("error.migration_no_source"))
            return
        }
        guard !isRunning else {
            publishError(L("error.migration_server_running"))
            return
        }

        let executable = fileManager.isExecutableFile(atPath: installedBinaryPath) ? installedBinaryPath : binaryPath
        guard fileManager.isExecutableFile(atPath: executable) else {
            publishError(L("error.wired3_binary_missing"))
            return
        }

        isMigrating = true

        var args: [String] = [
            "--working-directory", workingDirectory,
            "--db", databasePath,
            "--migrate-from", migrationSourcePath
        ]
        if migrationOverwrite {
            args.append("--overwrite")
        }

        migrationOutput = ""

        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
        task.arguments = args

        // Write subprocess output to a temp file to avoid pipe-buffering race conditions.
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("wired3-migration-\(Int(Date().timeIntervalSince1970)).log")
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil)
        guard let writeHandle = FileHandle(forWritingAtPath: tmpURL.path) else {
            isMigrating = false
            publishError(L("error.migration_failed"))
            return
        }
        task.standardOutput = writeHandle
        task.standardError = writeHandle

        do {
            try task.run()
        } catch {
            writeHandle.closeFile()
            isMigrating = false
            publishError("\(L("error.migration_failed")): \(error.localizedDescription)")
            return
        }

        // Wait for the process using structured concurrency; cap at 5 minutes so
        // isMigrating can never be stuck true forever if the subprocess hangs.
        let didTimeout = await withTaskGroup(of: Bool.self) { group -> Bool in
            group.addTask {
                await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .utility).async {
                        task.waitUntilExit()
                        cont.resume(returning: false)
                    }
                }
            }
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 5 * 60 * 1_000_000_000)
                    task.terminate()
                    return true
                } catch {
                    return false
                }
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        writeHandle.closeFile()
        let data = (try? Data(contentsOf: tmpURL)) ?? Data()
        let output = String(data: data, encoding: .utf8) ?? "(no output)"
        try? FileManager.default.removeItem(at: tmpURL)

        migrationOutput = didTimeout
            ? (output.isEmpty ? "" : output + "\n") + L("error.migration_timed_out")
            : output
        isMigrating = false
    }

    func chooseBinaryPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = L("common.select")

        if panel.runModal() == .OK, let selected = panel.url?.path {
            binaryPath = selected
            refreshInstallStatus()
        }
    }

    func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            try configureLaunchAtLogin(enabled: enabled)
            launchAtLogin = enabled
        } catch {
            publishError("\(L("error.launch_at_login_change_failed")): \(error.localizedDescription)")
            launchAtLogin = isLaunchAtLoginEnabled()
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
            statusMessage = L("status.installing")

            let source = try await resolveInstallSourceBinary()
            try installBinary(from: source)

            refreshInstallStatus()
            statusMessage = L("status.server_installed")
        } catch {
            publishError("\(L("error.install_failed")): \(error.localizedDescription)")
        }
    }

    func uninstallServer() {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        stopServer()
        try? configureLaunchAtLogin(enabled: false)
        launchAtLogin = false

        do {
            if fileManager.fileExists(atPath: workingDirectory) {
                try fileManager.removeItem(atPath: workingDirectory)
            }
            statusMessage = L("status.server_uninstalled")
            refreshAll()
        } catch {
            publishError("\(L("error.uninstall_failed")): \(error.localizedDescription)")
        }
    }

    func startServer() async {
        // LaunchDaemon is managed by launchd — never start a local process in that mode.
        guard installMode == .launchAgent else { return }
        refreshRunningStatus()
        guard !isRunning else { return }

        do {
            bootstrapRuntimeIfNeeded()
            _ = try synchronizeInstalledBinaryIfNeeded()
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
                Task { @MainActor [weak self] in
                    self?.appendLog(line)
                }
            }

            try task.run()
            process = task
            isRunning = true
            statusMessage = L("status.server_started")

            task.terminationHandler = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.isRunning = false
                    self?.statusMessage = L("status.server_stopped")
                }
            }
        } catch {
            publishError("\(L("error.start_failed")): \(error.localizedDescription)")
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
            statusMessage = L("status.server_stopped")
        }
    }

    func restartServer() async {
        stopServer()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startServer()
    }

    func saveNetworkSettings() {
        serverPort = max(1, min(serverPort, 65_535))

        withConfig { config in
            config["server", "port"] = String(serverPort)
        }

        if isRunning {
            statusMessage = L("status.port_saved_restart_required")
        } else {
            statusMessage = L("status.port_saved")
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
        // In daemon mode the --root path is baked into the LaunchDaemon plist;
        // regenerate it whenever the files directory changes.
        if installMode == .launchDaemon && launchDaemonInstalled {
            do {
                try reinstallDaemonPlist()
            } catch {
                publishError("Failed to update LaunchDaemon plist: \(error.localizedDescription)")
            }
        }
        if launchAtLogin {
            do {
                try configureLaunchAtLogin(enabled: true)
            } catch {
                publishError("\(L("error.launch_at_login_update_failed")): \(error.localizedDescription)")
                launchAtLogin = isLaunchAtLoginEnabled()
            }
        }
        if reloadServerIfPossible() {
            statusMessage = L("status.files_settings_saved_reloaded")
        } else {
            statusMessage = L("status.files_settings_saved")
        }
    }

    func saveDatabaseSettings() {
        databaseSnapshotInterval = max(0, databaseSnapshotInterval)
        if !eventRetentionOptions.contains(where: { $0.id == eventRetentionPolicy }) {
            eventRetentionPolicy = "never"
        }

        withConfig { config in
            config["database", "snapshot_interval"] = String(databaseSnapshotInterval)
            config["database", "event_retention"] = eventRetentionPolicy
        }

        if reloadServerIfPossible() {
            statusMessage = L("status.database_settings_saved_reloaded")
        } else {
            statusMessage = L("status.database_settings_saved")
        }
    }

    func saveEventRetentionSetting() {
        if !eventRetentionOptions.contains(where: { $0.id == eventRetentionPolicy }) {
            eventRetentionPolicy = "never"
        }

        withConfig { config in
            config["database", "event_retention"] = eventRetentionPolicy
        }

        if reloadServerIfPossible() {
            statusMessage = L("status.database_settings_saved_reloaded")
        } else {
            statusMessage = L("status.database_settings_saved")
        }
    }

    func reindexNow() async {
        guard isRunning else {
            statusMessage = L("status.reindex_on_next_start")
            return
        }

        if sendIndexSignal() {
            statusMessage = L("status.reindex_triggered")
        } else {
            // PID file not found or signal failed — fall back to a server restart
            // so the reindex always happens even in degraded environments.
            stopServer()
            try? await Task.sleep(nanoseconds: 700_000_000)
            await startServer()
            statusMessage = L("status.server_restarted_reindex")
        }
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

            // SECURITY (A_009): persist strict_identity
            config["security", "strict_identity"] = strictIdentity ? "yes" : "no"
        }

        if reloadServerIfPossible() {
            statusMessage = L("status.advanced_saved_reloaded")
        } else {
            statusMessage = L("status.advanced_saved")
        }
    }

    func setStrictIdentity(_ enabled: Bool) {
        strictIdentity = enabled

        withConfig { config in
            config["security", "strict_identity"] = enabled ? "yes" : "no"
        }

        if reloadServerIfPossible() {
            statusMessage = L("status.advanced_saved_reloaded")
        } else {
            statusMessage = L("status.advanced_saved")
        }
    }

    func setAdminPassword() {
        let password = newAdminPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !password.isEmpty else {
            publishError(L("error.admin_password_empty"))
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
            statusMessage = L("status.admin_password_updated")
        } catch {
            publishError("\(L("error.admin_password_set_failed")): \(error.localizedDescription)")
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
                        // swiftlint:disable:next line_length
                        "INSERT INTO users (username, password, full_name, identity, creation_time, modification_time, color, `group`) VALUES (?, ?, 'Administrator', 'admin', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP, '1', 'admin');",
                        values: ["admin", hash]
                    )
                }
            }

            refreshAdminStatus()
            statusMessage = L("status.admin_user_created")
        } catch {
            publishError("\(L("error.admin_user_create_failed")): \(error.localizedDescription)")
        }
    }

    func openLogsInFinder() {
        let url = URL(fileURLWithPath: logPath)
        NSWorkspace.shared.open(url)
    }

    private func pollState() {
        refreshRunningStatus()
        if installMode == .launchDaemon {
            refreshDaemonStatus()
        }
        refreshLogText()
        refreshDashboard()
    }

    private func refreshInstallStatus() {
        isInstalled = fileManager.isExecutableFile(atPath: installedBinaryPath) || fileManager.isExecutableFile(atPath: binaryPath)
    }

    private func refreshInstalledVersion() {
        let executableCandidates = [installedBinaryPath, binaryPath]
        guard let executable = executableCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            installedServerVersion = "-"
            return
        }

        let output = runCommand(executable, ["--version"])
        let versionLine = output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }

        installedServerVersion = versionLine ?? "-"
        refreshSpecVersions()
    }

    private func refreshSpecVersions() {
        let wiredXmlPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("wired.xml").path

        let spec = P7Spec(withPath: fileManager.fileExists(atPath: wiredXmlPath) ? wiredXmlPath : nil)
        p7ProtocolVersion    = spec.builtinProtocolVersion ?? "-"
        wiredProtocolName    = spec.protocolName    ?? "-"
        wiredProtocolVersion = spec.protocolVersion ?? "-"
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

    private var launchAgentPlistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(launchAgentLabel).plist", isDirectory: false)
    }

    private var launchctlDomain: String {
        "gui/\(getuid())"
    }

    private var launchctlService: String {
        "\(launchctlDomain)/\(launchAgentLabel)"
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        guard fileManager.fileExists(atPath: launchAgentPlistURL.path) else {
            return false
        }

        let result = runProcess("/bin/launchctl", ["print", launchctlService])
        return result.status == 0
    }

    private func configureLaunchAtLogin(enabled: Bool) throws {
        if enabled {
            try writeLaunchAgentPlist()
            _ = runProcess("/bin/launchctl", ["bootout", launchctlService])
            _ = runProcess("/bin/launchctl", ["bootout", launchctlDomain, launchAgentPlistURL.path])

            let bootstrap = runProcess("/bin/launchctl", ["bootstrap", launchctlDomain, launchAgentPlistURL.path])
            guard bootstrap.status == 0 else {
                throw WiredServerError.launchAgentCommandFailed(bootstrap.errorOutput.isEmpty ? bootstrap.output : bootstrap.errorOutput)
            }
        } else {
            _ = runProcess("/bin/launchctl", ["bootout", launchctlService])
            _ = runProcess("/bin/launchctl", ["bootout", launchctlDomain, launchAgentPlistURL.path])
            if fileManager.fileExists(atPath: launchAgentPlistURL.path) {
                try fileManager.removeItem(at: launchAgentPlistURL)
            }
        }
    }

    private func writeLaunchAgentPlist() throws {
        bootstrapRuntimeIfNeeded()
        _ = try synchronizeInstalledBinaryIfNeeded(allowInstallIfMissing: false)

        let executableCandidates = [installedBinaryPath, binaryPath]
        guard let executable = executableCandidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw WiredServerError.missingBinary
        }

        let launchAgentsDirectory = launchAgentPlistURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: launchAgentsDirectory, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "Label": launchAgentLabel,
            "ProgramArguments": [
                executable,
                "--working-directory", workingDirectory,
                "--db", databasePath,
                "--config", configPath,
                "--root", currentServerRootPath()
            ],
            "WorkingDirectory": workingDirectory,
            "RunAtLoad": true,
            "KeepAlive": false,
            "StandardOutPath": logPath,
            "StandardErrorPath": logPath
        ]

        guard (plist as NSDictionary).write(to: launchAgentPlistURL, atomically: true) else {
            throw WiredServerError.launchAgentWriteFailed
        }
    }

    private func currentServerRootPath() -> String {
        let trimmed = filesDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? runtimeFilesPath : trimmed
    }

    private func runProcess(_ launchPath: String, _ arguments: [String]) -> ProcessResult {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: launchPath)
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ProcessResult(status: 1, output: "", errorOutput: error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
        return ProcessResult(
            status: task.terminationStatus,
            output: output,
            errorOutput: errorOutput
        )
    }

    private func runCommand(_ launchPath: String, _ arguments: [String]) -> String {
        runProcess(launchPath, arguments).output
    }

    private func refreshAdminStatus() {
        do {
            try openDatabase { db in
                let passwordHash = try querySingleString(db, "SELECT password FROM users WHERE username = 'admin' LIMIT 1;")
                if let hash = passwordHash {
                    let emptyHash = sha256("")
                    hasAdminPassword = !(hash.isEmpty || hash == emptyHash)
                    adminStatus = hasAdminPassword ? L("advanced.admin.status.secured") : L("advanced.admin.status.no_password")
                } else {
                    hasAdminPassword = false
                    adminStatus = L("advanced.admin.status.missing")
                }
            }
        } catch let error as WiredServerError where error == .databaseNotInitialized {
            hasAdminPassword = false
            adminStatus = L("advanced.admin.status.db_not_initialized")
        } catch {
            hasAdminPassword = false
            adminStatus = L("advanced.admin.status.unavailable")
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
        databaseSnapshotInterval = max(0, intValue(config["database", "snapshot_interval"], default: 86400))

        let rawRetentionPolicy = stringValue(config["database", "event_retention"], default: "never")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        eventRetentionPolicy = eventRetentionOptions.contains(where: { $0.id == rawRetentionPolicy })
            ? rawRetentionPolicy
            : (rawRetentionPolicy == "none" ? "never" : "never")

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

        // SECURITY (A_009): load strict_identity and compute identity fingerprint
        strictIdentity = boolValue(config["security", "strict_identity"], default: true)
        refreshIdentityFingerprint()

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

    // MARK: - TOFU / Identity

    /// Reload the identity fingerprint from the key file on disk.
    func refreshIdentityFingerprint() {
        let keyPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("wired-identity.key").path
        identityFingerprint = ServerIdentity.fingerprintFromKeyFile(at: keyPath) ?? ""
    }

    /// Opens a save panel so the admin can export the server's identity public key.
    func exportIdentityKey() {
        let keyPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("wired-identity.key").path
        guard let exportData = ServerIdentity.publicKeyBase64FromKeyFile(at: keyPath) else {
            publishError("Cannot read identity key from \(keyPath)")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "wired-identity-public.b64"
        panel.title = "Export Server Identity Public Key"
        panel.message = "Save the server's persistent identity public key for out-of-band distribution to clients."
        panel.allowedContentTypes = [.plainText]
        if panel.runModal() == .OK, let url = panel.url {
            do {
                try exportData.write(to: url)
                statusMessage = "Identity key exported to \(url.lastPathComponent)"
            } catch {
                publishError("Failed to export identity key: \(error.localizedDescription)")
            }
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

        // Detect initial admin password generated on first launch
        if initialAdminPassword.isEmpty, text.contains("INITIAL ADMIN PASSWORD") {
            // Extract password between "INITIAL ADMIN PASSWORD: " and " ==="
            if let range = text.range(of: "INITIAL ADMIN PASSWORD: "),
               let endRange = text[range.upperBound...].range(of: " ===") {
                let password = String(text[range.upperBound..<endRange.lowerBound])
                if !password.isEmpty {
                    initialAdminPassword = password
                    showInitialPasswordAlert = true
                }
            }
        }

        refreshDashboard()
    }

    private func bootstrapRuntimeIfNeeded() {
        do {
            try fileManager.createDirectory(atPath: workingDirectory, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                atPath: URL(fileURLWithPath: workingDirectory)
                    .appendingPathComponent("etc")
                    .path,
                withIntermediateDirectories: true
            )
            try fileManager.createDirectory(atPath: runtimeFilesPath, withIntermediateDirectories: true)
            try fileManager.createDirectory(
                atPath: URL(fileURLWithPath: workingDirectory)
                    .appendingPathComponent("bin")
                    .path,
                withIntermediateDirectories: true
            )

            if !fileManager.fileExists(atPath: configPath) {
                try defaultConfig().write(to: URL(fileURLWithPath: configPath), atomically: true, encoding: .utf8)
            }

            _ = ConfigFileDefaults.ensureStrictIdentitySetting(at: configPath)

            if !fileManager.fileExists(atPath: logPath) {
                fileManager.createFile(atPath: logPath, contents: Data())
            }

            copyBundledRuntimeAssetsIfNeeded()
        } catch {
            publishError("\(L("error.runtime_prepare_failed")): \(error.localizedDescription)")
        }
    }

    private func installServerIfNeeded() async throws {
        guard !fileManager.isExecutableFile(atPath: installedBinaryPath) else { return }
        let source = try await resolveInstallSourceBinary()
        try installBinary(from: source)
    }

    private func resolveInstallSourceBinary() async throws -> String {
        let candidates = [
            bundledServerBinaryPath(),
            binaryPath,
            "/opt/homebrew/bin/wired3",
            "/usr/local/bin/wired3"
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }

        if let first = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return first
        }

        throw WiredServerError.missingBinary
    }

    private func installBinary(from sourcePath: String) throws {
        let expectedSHA256 = try normalizedSHA256ForFile(at: sourcePath)
        appendRuntimeLog("binary-update: manual install requested from \(sourcePath)")
        try installBinaryWithStagingRollback(from: sourcePath, expectedSHA256: expectedSHA256)
        appendRuntimeLog("binary-update: manual install completed")
    }

    @discardableResult
    private func synchronizeInstalledBinaryIfNeeded(allowInstallIfMissing: Bool = true) throws -> Bool {
        // Never replace the binary while the daemon is running — launchd detects the
        // replacement and kills the process. Check here as a last-resort guard regardless
        // of which call path reaches this function.
        if installMode == .launchDaemon {
            let daemonLive = runProcess("/usr/bin/pgrep", ["-f", "/Library/Wired3/bin/wired3"]).status == 0
            if daemonLive {
                appendRuntimeLog("binary-update: daemon is running, skipping binary replacement")
                return false
            }
        }

        guard let bundledBinary = bundledServerBinaryPath() else {
            appendRuntimeLog("binary-update: no bundled wired3 found, skipping synchronization")
            return false
        }

        let bundledSHA256 = try normalizedSHA256ForFile(at: bundledBinary)
        let metadataSHA256 = bundledBinaryExpectedSHA256()
        let expectedSHA256 = (metadataSHA256 == bundledSHA256 ? metadataSHA256 : nil) ?? bundledSHA256

        if fileManager.isExecutableFile(atPath: installedBinaryPath) {
            let installedSHA256 = try normalizedSHA256ForFile(at: installedBinaryPath)
            if installedSHA256 == expectedSHA256 {
                binaryPath = installedBinaryPath
                appendRuntimeLog("binary-update: up-to-date (\(expectedSHA256.prefix(8)))")
                return false
            }
            appendRuntimeLog("binary-update: update required (installed: \(installedSHA256.prefix(8)), expected: \(expectedSHA256.prefix(8)))")
        } else {
            appendRuntimeLog("binary-update: no installed binary found, provisioning from bundle")
            if !allowInstallIfMissing {
                appendRuntimeLog("binary-update: auto-install disabled for this flow, skipping")
                return false
            }
        }

        try installBinaryWithStagingRollback(from: bundledBinary, expectedSHA256: expectedSHA256)
        return true
    }

    private func installBinaryWithStagingRollback(from sourcePath: String, expectedSHA256: String) throws {
        let destinationURL = URL(fileURLWithPath: installedBinaryPath)
        let destinationDirectory = destinationURL.deletingLastPathComponent()
        let updatesDirectory = destinationDirectory.appendingPathComponent(".updates", isDirectory: true)
        let token = UUID().uuidString.lowercased()
        let stagingURL = updatesDirectory.appendingPathComponent("wired3.staged.\(token)", isDirectory: false)
        let backupURL = updatesDirectory.appendingPathComponent("wired3.backup.\(token)", isDirectory: false)

        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: updatesDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: stagingURL.path) {
            try fileManager.removeItem(at: stagingURL)
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: stagingURL.path)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: stagingURL.path)

        let stagedHash = try normalizedSHA256ForFile(at: stagingURL.path)
        guard stagedHash == expectedSHA256 else {
            try? fileManager.removeItem(at: stagingURL)
            appendRuntimeLog("binary-update: staging hash mismatch, aborting update")
            throw WiredServerError.binaryIntegrityCheckFailed("staging hash mismatch")
        }

        if fileManager.fileExists(atPath: backupURL.path) {
            try? fileManager.removeItem(at: backupURL)
        }

        let destinationExists = fileManager.fileExists(atPath: destinationURL.path)

        do {
            if destinationExists {
                try fileManager.moveItem(at: destinationURL, to: backupURL)
            }
            try fileManager.moveItem(at: stagingURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)

            let installedHash = try normalizedSHA256ForFile(at: destinationURL.path)
            guard installedHash == expectedSHA256 else {
                appendRuntimeLog("binary-update: post-install hash mismatch, rolling back")
                throw WiredServerError.binaryIntegrityCheckFailed("installed hash mismatch")
            }

            if fileManager.fileExists(atPath: backupURL.path) {
                try? fileManager.removeItem(at: backupURL)
            }

            binaryPath = destinationURL.path
            appendRuntimeLog("binary-update: updated successfully (\(expectedSHA256.prefix(8)))")
        } catch {
            appendRuntimeLog("binary-update: update failed (\(error.localizedDescription)), attempting rollback")
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }

            if fileManager.fileExists(atPath: backupURL.path) {
                do {
                    try fileManager.moveItem(at: backupURL, to: destinationURL)
                    appendRuntimeLog("binary-update: rollback restored previous binary")
                } catch {
                    appendRuntimeLog("binary-update: rollback failed (\(error.localizedDescription))")
                    throw WiredServerError.binaryRollbackFailed(error.localizedDescription)
                }
            }

            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    private func bundledBinaryExpectedSHA256() -> String? {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: embeddedBinarySHAKey) as? String else {
            return nil
        }

        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256Hex(normalized) else {
            appendRuntimeLog("binary-update: invalid embedded SHA-256 metadata format")
            return nil
        }

        return normalized
    }

    private func normalizedSHA256ForFile(at path: String) throws -> String {
        let result = runProcess("/usr/bin/shasum", ["-a", "256", path])
        guard result.status == 0 else {
            let message = result.errorOutput.isEmpty ? result.output : result.errorOutput
            throw WiredServerError.binaryHashFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        guard let hashToken = result.output.split(separator: " ", omittingEmptySubsequences: true).first else {
            throw WiredServerError.binaryHashFailed("missing SHA-256 output")
        }

        let normalized = String(hashToken).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isValidSHA256Hex(normalized) else {
            throw WiredServerError.binaryHashFailed("invalid SHA-256 output format")
        }

        return normalized
    }

    private func isValidSHA256Hex(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
    }

    private func appendRuntimeLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [WiredServerApp] \(message)\n"
        let data = Data(line.utf8)

        if !fileManager.fileExists(atPath: logPath) {
            fileManager.createFile(atPath: logPath, contents: Data())
        }

        do {
            let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: logPath))
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            return
        }

        appendLog(line)
    }

    private func refreshDashboard(force: Bool = false) {
        let now = Date()

        if force || now.timeIntervalSince(lastDashboardLightRefresh) >= 2 {
            refreshDashboardLightweight()
            lastDashboardLightRefresh = now
        }

        if force || now.timeIntervalSince(lastDashboardHeavyRefresh) >= 20 {
            refreshDashboardHeavyweight()
            lastDashboardHeavyRefresh = now
        }
    }

    private func refreshDashboardLightweight() {
        dashboardHostUptime = formattedDuration(ProcessInfo.processInfo.systemUptime)

        let activePIDs = activeServerPIDs()
        if let pid = activePIDs.first {
            dashboardServerPID = String(pid)
            let metrics = processMetrics(for: pid)
            dashboardServerUptime = metrics.uptime
            dashboardServerCPU = metrics.cpu
            dashboardServerMemory = metrics.memory
            dashboardConnectedUsers = connectedUsersCount(for: pid)
        } else {
            dashboardServerPID = "-"
            dashboardServerUptime = "-"
            dashboardServerCPU = "-"
            dashboardServerMemory = "-"
            dashboardConnectedUsers = 0
        }

        dashboardLastErrorLine = extractLastErrorLine(from: logsText)
    }

    private func refreshDashboardHeavyweight() {
        dashboardFilesDirectoryExists = fileManager.fileExists(atPath: currentServerRootPath())
        dashboardDatabaseSizeBytes = fileSize(atPath: databasePath) + fileSize(atPath: databasePath + "-wal") + fileSize(atPath: databasePath + "-shm")
        dashboardFilesSizeBytes = directorySize(atPath: currentServerRootPath())
        dashboardSnapshotSizeBytes = fileSize(atPath: snapshotPath)
        dashboardLastSnapshotDate = modificationDate(atPath: snapshotPath)

        if let attributes = try? fileManager.attributesOfFileSystem(forPath: workingDirectory) {
            dashboardDiskFreeBytes = int64Value(attributes[.systemFreeSize])
            dashboardDiskTotalBytes = int64Value(attributes[.systemSize])
        } else {
            dashboardDiskFreeBytes = 0
            dashboardDiskTotalBytes = 0
        }

        do {
            let stats = try openRawDatabaseReturning { db -> DashboardDatabaseStats in
                let initialized = try tableExists(db, table: "users")
                guard initialized else {
                    return DashboardDatabaseStats(
                        isInitialized: false,
                        accountsCount: 0,
                        groupsCount: 0,
                        eventsCount: 0,
                        boardsCount: 0
                    )
                }
                return DashboardDatabaseStats(
                    isInitialized: true,
                    accountsCount: try queryCount(db, "SELECT COUNT(*) FROM users;"),
                    groupsCount: try queryCount(db, "SELECT COUNT(*) FROM `groups`;"),
                    eventsCount: try queryCount(db, "SELECT COUNT(*) FROM events;"),
                    boardsCount: try queryCount(db, "SELECT COUNT(*) FROM boards;")
                )
            }

            dashboardDatabaseInitialized = stats.isInitialized
            dashboardAccountsCount = stats.accountsCount
            dashboardGroupsCount = stats.groupsCount
            dashboardEventsCount = stats.eventsCount
            dashboardBoardsCount = stats.boardsCount
        } catch {
            dashboardDatabaseInitialized = false
            dashboardAccountsCount = 0
            dashboardGroupsCount = 0
            dashboardEventsCount = 0
            dashboardBoardsCount = 0
        }
    }

    private func processMetrics(for pid: Int32) -> DashboardProcessMetrics {
        let result = runProcess("/bin/ps", ["-p", String(pid), "-o", "%cpu=", "-o", "rss=", "-o", "etime="])
        guard result.status == 0 else {
            return .empty
        }

        let lines = result.output
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line = lines.first else { return .empty }

        let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count >= 3 else { return .empty }

        let cpu = parts[0].replacingOccurrences(of: ",", with: ".")
        let memoryKB = Int64(parts[1]) ?? 0
        return DashboardProcessMetrics(
            uptime: parts[2],
            cpu: cpu.isEmpty ? "-" : "\(cpu)%",
            memory: memoryKB > 0
                ? byteCountFormatter.string(fromByteCount: memoryKB * 1024)
                : "-"
        )
    }

    private func connectedUsersCount(for pid: Int32) -> Int {
        let result = runProcess("/usr/sbin/lsof", ["-a", "-p", String(pid), "-nP", "-iTCP:\(serverPort)", "-sTCP:ESTABLISHED"])
        guard result.status == 0 else { return 0 }
        let lines = result.output.split(separator: "\n", omittingEmptySubsequences: true)
        return max(0, lines.count - 1)
    }

    private func extractLastErrorLine(from text: String) -> String {
        let lines = text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)

        for line in lines.reversed() {
            let lowercased = line.lowercased()
            if lowercased.contains("error") || lowercased.contains("fatal") {
                return line.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return ""
    }

    private func fileSize(atPath path: String) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path),
              let rawSize = attributes[.size] else {
            return 0
        }
        return int64Value(rawSize)
    }

    private func directorySize(atPath path: String) -> Int64 {
        guard fileManager.fileExists(atPath: path) else { return 0 }

        let result = runProcess("/usr/bin/du", ["-sk", path])
        guard result.status == 0,
              let first = result.output.split(separator: "\t").first,
              let kilobytes = Int64(first.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return 0
        }
        return kilobytes * 1024
    }

    private func modificationDate(atPath path: String) -> Date? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else {
            return nil
        }
        return attributes[.modificationDate] as? Date
    }

    private func int64Value(_ any: Any?) -> Int64 {
        if let value = any as? NSNumber { return value.int64Value }
        if let value = any as? Int64 { return value }
        if let value = any as? Int { return Int64(value) }
        if let value = any as? UInt64 { return Int64(clamping: value) }
        return 0
    }

    private func formattedDuration(_ interval: TimeInterval) -> String {
        let total = Int(interval)
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h \(minutes)m" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    @discardableResult
    private func sendReloadSignal() -> Bool {
        sendSignal(SIGHUP)
    }

    @discardableResult
    private func reloadServerIfPossible() -> Bool {
        refreshRunningStatus()
        let didReload = sendReloadSignal()
        if !didReload, isRunning {
            appendRuntimeLog("reload: failed to send SIGHUP despite running-state detection")
        }
        return didReload
    }

    /// Send SIGUSR1 to the running wired3 process to trigger a full file reindex
    /// (cancels any rebuild in progress and starts a fresh one immediately).
    @discardableResult
    private func sendIndexSignal() -> Bool {
        sendSignal(SIGUSR1)
    }

    /// Read the PID file and send `signal` to the running wired3 process.
    @discardableResult
    private func sendSignal(_ signal: Int32) -> Bool {
        let pidPath = URL(fileURLWithPath: workingDirectory)
            .appendingPathComponent("wired3.pid").path
        guard let pidString = try? String(contentsOfFile: pidPath, encoding: .utf8) else {
            return false
        }
        let trimmed = pidString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pid = pid_t(trimmed) else { return false }
        return kill(pid, signal) == 0
    }

    private func withConfig(_ body: (Config) -> Void) {
        let config = Config(withPath: configPath)
        guard config.load() else {
            publishError(L("error.config_read_failed"))
            return
        }

        body(config)
    }

    private func bundledServerBinaryPath() -> String? {
        if let explicit = Bundle.main.path(forResource: "wired3", ofType: nil),
           fileManager.isExecutableFile(atPath: explicit) {
            return explicit
        }

        let fallback = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/wired3")
            .path
        if fileManager.isExecutableFile(atPath: fallback) {
            return fallback
        }

        return nil
    }

    private func copyBundledRuntimeAssetsIfNeeded() {
        syncBundledSpec(named: "wired.xml", to: URL(fileURLWithPath: workingDirectory).appendingPathComponent("wired.xml").path)
        copyBundledFileIfMissing(named: "banner.png", to: URL(fileURLWithPath: workingDirectory).appendingPathComponent("banner.png").path)
    }

    /// Syncs wired.xml from the app bundle to the working directory.
    /// Unlike banner.png, the spec is not user-editable — it is a protocol definition
    /// shipped with the binary. Always overwrite when the bundled version differs.
    private func syncBundledSpec(named fileName: String, to destinationPath: String) {
        guard fileName == "wired.xml",
              let source = WiredProtocolSpec.bundledSpecURL()?.path,
              fileManager.fileExists(atPath: source) else {
            return
        }

        let destinationDir = (destinationPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)

        if !fileManager.fileExists(atPath: destinationPath) {
            try? fileManager.copyItem(atPath: source, toPath: destinationPath)
            appendRuntimeLog("spec-update: bootstrapped \(fileName)")
            return
        }

        guard
            let bundledData = fileManager.contents(atPath: source),
            let installedData = fileManager.contents(atPath: destinationPath)
        else { return }

        guard bundledData != installedData else { return }

        try? fileManager.removeItem(atPath: destinationPath)
        try? fileManager.copyItem(atPath: source, toPath: destinationPath)
        appendRuntimeLog("spec-update: \(fileName) updated from bundle (content changed)")
    }

    private func copyBundledFileIfMissing(named fileName: String, to destinationPath: String) {
        guard !fileManager.fileExists(atPath: destinationPath) else { return }

        let sourceCandidates = [
            Bundle.main.path(forResource: fileName, ofType: nil),
            Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/\(fileName)").path
        ].compactMap { $0 }

        guard let source = sourceCandidates.first(where: { fileManager.fileExists(atPath: $0) }) else {
            return
        }

        let destinationDir = (destinationPath as NSString).deletingLastPathComponent
        try? fileManager.createDirectory(atPath: destinationDir, withIntermediateDirectories: true)
        try? fileManager.copyItem(atPath: source, toPath: destinationPath)
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

[database]
snapshot_interval = 86400
event_retention = never

[advanced]
compression = ALL
cipher = SECURE_ONLY
checksum = SECURE_ONLY

[security]
strict_identity = yes
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
        statusMessage = L("status.partial_db_reinitialized")
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

    private func queryCount(_ db: OpaquePointer, _ sql: String) throws -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw WiredServerError.databaseStatementFailed(sql)
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(statement, 0))
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
                // swiftlint:disable:next line_length
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
        if let intValue = UInt32(raw), intValue > 0,
           let normalized = normalizedCipherMode(rawValue: intValue) {
            return normalized
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
        if let intValue = UInt32(raw), intValue > 0,
           let normalized = normalizedChecksumMode(rawValue: intValue) {
            return normalized
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

    private func normalizedCipherMode(rawValue: UInt32) -> String? {
        switch P7Socket.CipherType(rawValue: rawValue) {
        case .ALL:
            return P7Socket.CipherType.ALL.description
        case .SECURE_ONLY:
            return P7Socket.CipherType.SECURE_ONLY.description
        case .NONE:
            return P7Socket.CipherType.NONE.description
        case .ECDH_AES256_SHA256:
            return P7Socket.CipherType.ECDH_AES256_SHA256.description
        case .ECDH_AES128_GCM:
            return P7Socket.CipherType.ECDH_AES128_GCM.description
        case .ECDH_AES256_GCM:
            return P7Socket.CipherType.ECDH_AES256_GCM.description
        case .ECDH_CHACHA20_POLY1305:
            return P7Socket.CipherType.ECDH_CHACHA20_POLY1305.description
        case .ECDH_XCHACHA20_POLY1305:
            return P7Socket.CipherType.ECDH_XCHACHA20_POLY1305.description
        default:
            return nil
        }
    }

    private func normalizedChecksumMode(rawValue: UInt32) -> String? {
        switch P7Socket.Checksum(rawValue: rawValue) {
        case .ALL:
            return P7Socket.Checksum.ALL.description
        case .SECURE_ONLY:
            return P7Socket.Checksum.SECURE_ONLY.description
        case .NONE:
            return P7Socket.Checksum.NONE.description
        case .SHA2_256:
            return P7Socket.Checksum.SHA2_256.description
        case .SHA2_384:
            return P7Socket.Checksum.SHA2_384.description
        case .SHA3_256:
            return P7Socket.Checksum.SHA3_256.description
        case .SHA3_384:
            return P7Socket.Checksum.SHA3_384.description
        case .HMAC_256:
            return P7Socket.Checksum.HMAC_256.description
        case .HMAC_384:
            return P7Socket.Checksum.HMAC_384.description
        default:
            return nil
        }
    }

    private func publishError(_ message: String) {
        lastErrorMessage = message
        showErrorAlert = true
        statusMessage = message
    }

    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter
    }

    private var dateTimeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }

    private var relativeDateFormatter: RelativeDateTimeFormatter {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }

    var dashboardDatabaseSize: String {
        dashboardDatabaseSizeBytes > 0 ? byteCountFormatter.string(fromByteCount: dashboardDatabaseSizeBytes) : "-"
    }

    var dashboardFilesSize: String {
        dashboardFilesSizeBytes > 0 ? byteCountFormatter.string(fromByteCount: dashboardFilesSizeBytes) : "-"
    }

    var dashboardSnapshotSize: String {
        dashboardSnapshotSizeBytes > 0 ? byteCountFormatter.string(fromByteCount: dashboardSnapshotSizeBytes) : "-"
    }

    var dashboardDiskFree: String {
        dashboardDiskFreeBytes > 0 ? byteCountFormatter.string(fromByteCount: dashboardDiskFreeBytes) : "-"
    }

    var dashboardDiskTotal: String {
        dashboardDiskTotalBytes > 0 ? byteCountFormatter.string(fromByteCount: dashboardDiskTotalBytes) : "-"
    }

    var dashboardDiskDetail: String? {
        dashboardDiskTotal == "-" ? nil : "\(L("dashboard.metric.disk_total")): \(dashboardDiskTotal)"
    }

    var dashboardSnapshotSummary: String {
        if databaseSnapshotInterval == 0 {
            return L("dashboard.snapshot.disabled")
        }

        guard let date = dashboardLastSnapshotDate else {
            return L("dashboard.snapshot.pending")
        }

        let relative = relativeDateFormatter.localizedString(for: date, relativeTo: Date())
        return "\(dateTimeFormatter.string(from: date)) (\(relative))"
    }

    var dashboardLastErrorSummary: String {
        dashboardLastErrorLine.isEmpty ? L("dashboard.errors.none") : dashboardLastErrorLine
    }

    var dashboardDiskFreeRatio: Double {
        guard dashboardDiskTotalBytes > 0 else { return 0 }
        return Double(dashboardDiskFreeBytes) / Double(dashboardDiskTotalBytes)
    }

    var dashboardServerHealth: DashboardHealthSummary {
        if !isInstalled {
            return .init(level: .critical, title: L("dashboard.health.critical"), detail: L("dashboard.health.server.not_installed"))
        }
        if !isRunning {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.server.stopped"))
        }
        if portStatus == .closed {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.server.port_closed"))
        }
        if !hasAdminPassword {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.server.admin_unsecured"))
        }
        if !dashboardLastErrorLine.isEmpty {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.server.recent_error"))
        }
        return .init(level: .good, title: L("dashboard.health.good"), detail: L("dashboard.health.server.ok"))
    }

    var dashboardHostHealth: DashboardHealthSummary {
        if dashboardDiskTotalBytes == 0 {
            return .init(level: .neutral, title: L("dashboard.health.unknown"), detail: L("dashboard.health.host.unknown"))
        }
        if dashboardDiskFreeRatio < 0.05 {
            return .init(level: .critical, title: L("dashboard.health.critical"), detail: L("dashboard.health.host.disk_critical"))
        }
        if dashboardDiskFreeRatio < 0.10 {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.host.disk_warning"))
        }
        return .init(level: .good, title: L("dashboard.health.good"), detail: L("dashboard.health.host.ok"))
    }

    var dashboardDatabaseHealth: DashboardHealthSummary {
        if !dashboardDatabaseInitialized {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.database.not_initialized"))
        }
        if databaseSnapshotInterval > 0 && dashboardLastSnapshotDate == nil {
            return .init(level: .warning, title: L("dashboard.health.warning"), detail: L("dashboard.health.database.snapshot_pending"))
        }
        return .init(level: .good, title: L("dashboard.health.good"), detail: L("dashboard.health.database.ok"))
    }

    var dashboardFilesHealth: DashboardHealthSummary {
        if !dashboardFilesDirectoryExists {
            return .init(level: .critical, title: L("dashboard.health.critical"), detail: L("dashboard.health.files.missing"))
        }
        return .init(level: .good, title: L("dashboard.health.good"), detail: L("dashboard.health.files.ok"))
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

struct DashboardHealthSummary {
    let level: DashboardHealthLevel
    let title: String
    let detail: String
}

private struct ProcessResult {
    let status: Int32
    let output: String
    let errorOutput: String
}

private struct DashboardDatabaseStats {
    let isInitialized: Bool
    let accountsCount: Int
    let groupsCount: Int
    let eventsCount: Int
    let boardsCount: Int
}

private struct DashboardProcessMetrics {
    let uptime: String
    let cpu: String
    let memory: String

    static let empty = DashboardProcessMetrics(uptime: "-", cpu: "-", memory: "-")
}

enum ServerInstallMode: String {
    case launchAgent
    case launchDaemon

    var displayName: String {
        switch self {
        case .launchAgent: return "LaunchAgent (current user, starts at login)"
        case .launchDaemon: return "LaunchDaemon (system service, starts at boot)"
        }
    }
}

enum DashboardHealthLevel {
    case good
    case warning
    case critical
    case neutral
}

enum PortStatus {
    case unknown
    case open
    case closed

    var description: String {
        switch self {
        case .unknown:
            return L("network.port_status.unknown")
        case .open:
            return L("network.port_status.open")
        case .closed:
            return L("network.port_status.closed")
        }
    }
}

enum WiredServerError: LocalizedError, Equatable {
    case missingBinary
    case launchAgentWriteFailed
    case launchAgentCommandFailed(String)
    case binaryHashFailed(String)
    case binaryIntegrityCheckFailed(String)
    case binaryRollbackFailed(String)
    case databaseOpenFailed
    case databaseNotInitialized
    case databaseStatementFailed(String)
    case databaseExecutionFailed(String)
    case systemDirectoryCreationFailed(String)
    case systemMigrationFailed(String)
    case systemDirectoryOwnershipFailed(String)
    case daemonUserCreationFailed(String)
    case launchDaemonWriteFailed
    case launchDaemonInstallFailed(String)
    case launchDaemonRemoveFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            return L("error.wired3_binary_missing")
        case .launchAgentWriteFailed:
            return L("error.launch_agent_write_failed")
        case .launchAgentCommandFailed(let message):
            return "\(L("error.launchctl_failed")): \(message)"
        case .binaryHashFailed(let message):
            return "Unable to compute wired3 binary hash: \(message)"
        case .binaryIntegrityCheckFailed(let message):
            return "wired3 binary integrity check failed: \(message)"
        case .binaryRollbackFailed(let message):
            return "wired3 binary rollback failed: \(message)"
        case .databaseOpenFailed:
            return L("error.database_open_failed")
        case .databaseNotInitialized:
            return L("error.database_not_initialized")
        case .databaseStatementFailed(let sql):
            return "\(L("error.sql_prepare_failed")): \(sql)"
        case .databaseExecutionFailed(let sql):
            return "\(L("error.sql_execution_failed")): \(sql)"
        case .systemDirectoryCreationFailed(let msg):
            return "Failed to create system data directory: \(msg)"
        case .systemMigrationFailed(let msg):
            return "Data migration failed: \(msg)"
        case .systemDirectoryOwnershipFailed(let msg):
            return "Failed to set directory ownership: \(msg)"
        case .daemonUserCreationFailed(let msg):
            return "Failed to create daemon user: \(msg)"
        case .launchDaemonWriteFailed:
            return "Failed to write LaunchDaemon plist"
        case .launchDaemonInstallFailed(let msg):
            return "Failed to install LaunchDaemon: \(msg)"
        case .launchDaemonRemoveFailed(let msg):
            return "Failed to remove LaunchDaemon: \(msg)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
