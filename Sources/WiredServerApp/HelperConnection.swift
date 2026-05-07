import Foundation
import ServiceManagement

enum HelperError: LocalizedError {
    case connectionFailed
    case operationFailed(String)
    case installFailed(String)
    /// SMJobBless returned kSMErrorJobMustBeEnabled (8): helper is installed but disabled.
    /// The user must approve it in System Settings → Privacy & Security → Login Items.
    case mustBeEnabled

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return L("error.helper.connection_failed")
        case .operationFailed(let msg):
            return msg.isEmpty ? L("error.helper.operation_failed") : msg
        case .installFailed(let msg):
            return "\(L("error.helper.install_failed_prefix")): \(msg)"
        case .mustBeEnabled:
            return L("alert.helper_setup.message")
        }
    }
}

/// Manages the XPC connection to WiredServerHelper and installs it via SMJobBless when needed.
///
/// Requires Developer ID signing: both the app (SMPrivilegedExecutables in Info.plist) and
/// the helper (SMAuthorizedClients in its embedded Info.plist) must satisfy each other's
/// code-signing requirements. See Sources/WiredServerHelper/Info.plist for the requirement strings.
final class HelperConnection {
    static let shared = HelperConnection()
    private init() {}

    private var _connection: NSXPCConnection?

    private var connection: NSXPCConnection {
        if let c = _connection { return c }
        let c = NSXPCConnection(machServiceName: kHelperMachServiceName, options: .privileged)
        c.remoteObjectInterface = NSXPCInterface(with: WiredHelperProtocol.self)
        c.invalidationHandler = { [weak self] in self?._connection = nil }
        c.resume()
        _connection = c
        return c
    }

    // MARK: - Installation

    /// Ensures the privileged helper is installed and running in launchd's system domain.
    ///
    /// Uses SMAppService.daemon (macOS 13+ replacement for SMJobBless). The daemon plist
    /// bundled in Contents/Library/LaunchDaemons/ is registered with the system. On first
    /// registration a notification prompts the user to approve in System Settings → General →
    /// Login Items. After approval launchd demand-starts the helper on first XPC connection.
    func installIfNeeded() throws {
        let service = SMAppService.daemon(plistName: "\(kHelperMachServiceName).plist")
        switch service.status {
        case .enabled:
            // SMAppService thinks it's enabled. Verify launchd actually has it.
            // If not (e.g. $APP_BUNDLE not resolved in old registration, or manual bootout),
            // force a fresh registration so BTM picks up the current plist with the absolute path.
            if !isHelperRegistered() {
                try? service.unregister()
                do {
                    try service.register()
                } catch {
                    throw HelperError.installFailed(error.localizedDescription)
                }
                if service.status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                    throw HelperError.mustBeEnabled
                }
            }
            return
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            throw HelperError.mustBeEnabled
        case .notRegistered, .notFound:
            do {
                try service.register()
            } catch {
                throw HelperError.installFailed(error.localizedDescription)
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                throw HelperError.mustBeEnabled
            }
        @unknown default:
            break
        }
    }


    /// Returns true if the helper mach service is registered in launchd's system domain.
    /// Uses `launchctl print system/<label>` which works without root and correctly
    /// distinguishes "registered but idle" from "not registered at all".
    func isHelperRegistered() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["print", "system/\(kHelperMachServiceName)"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    // MARK: - Version

    func getVersion() async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            guard let p = xpcProxy(onError: { cont.resume(throwing: $0) }) else { return }
            p.getVersion { version in cont.resume(returning: version) }
        }
    }

    // MARK: - Operations

    func createSystemDirectory(path: String, owner: String) async throws {
        try await boolReply { p, cont in
            p.createSystemDirectory(path: path, owner: owner, withReply: cont)
        }
    }

    func runFDACheck(scriptPath: String, outputPath: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            guard let p = xpcProxy(onError: { cont.resume(throwing: $0) }) else { return }
            p.runFDACheck(scriptPath: scriptPath, outputPath: outputPath) { granted, message in
                if message.isEmpty {
                    cont.resume(returning: granted)
                } else {
                    cont.resume(throwing: HelperError.operationFailed(message))
                }
            }
        }
    }

    /// Returns fdaGranted flag.
    func startDaemon(plistPath: String, label: String,
                     fdaScriptPath: String, fdaOutputPath: String) async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            guard let p = xpcProxy(onError: { cont.resume(throwing: $0) }) else { return }
            p.startDaemon(plistPath: plistPath, label: label,
                          fdaScriptPath: fdaScriptPath, fdaOutputPath: fdaOutputPath) { success, fdaGranted, message in
                if success {
                    cont.resume(returning: fdaGranted)
                } else {
                    cont.resume(throwing: HelperError.operationFailed(message))
                }
            }
        }
    }

    func stopDaemon(label: String) async throws {
        try await boolReply { p, cont in
            p.stopDaemon(label: label, withReply: cont)
        }
    }

    func activateDaemon(config: NSDictionary, plistData: Data) async throws {
        try await boolReply { p, cont in
            p.activateDaemon(config: config, plistData: plistData, withReply: cont)
        }
    }

    func deactivateDaemon(config: NSDictionary) async throws {
        try await boolReply { p, cont in
            p.deactivateDaemon(config: config, withReply: cont)
        }
    }

    func installPlist(data: Data, destinationPath: String) async throws {
        try await boolReply { p, cont in
            p.installPlist(data: data, destinationPath: destinationPath, withReply: cont)
        }
    }

    func copyBinary(sourcePath: String, destinationPath: String) async throws {
        try await boolReply { p, cont in
            p.copyBinary(sourcePath: sourcePath, destinationPath: destinationPath, withReply: cont)
        }
    }

    // MARK: - Private

    /// Returns a typed XPC proxy whose connection errors are forwarded to `onError` instead of
    /// being silently dropped. If the cast fails, `onError` is called and nil is returned so the
    /// caller can simply guard-return without leaving the continuation dangling.
    private func xpcProxy(onError: @escaping (Error) -> Void) -> WiredHelperProtocol? {
        let raw = connection.remoteObjectProxyWithErrorHandler { error in
            NSLog("[HelperConnection] XPC error: %@", error as NSError)
            onError(HelperError.operationFailed("XPC: \(error.localizedDescription)"))
        }
        guard let p = raw as? WiredHelperProtocol else {
            onError(HelperError.connectionFailed)
            return nil
        }
        return p
    }

    private func boolReply(
        _ body: @escaping (WiredHelperProtocol, @escaping (Bool, String) -> Void) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            guard let p = xpcProxy(onError: { cont.resume(throwing: $0) }) else { return }
            body(p) { success, message in
                if success { cont.resume() }
                else { cont.resume(throwing: HelperError.operationFailed(message)) }
            }
        }
    }
}
