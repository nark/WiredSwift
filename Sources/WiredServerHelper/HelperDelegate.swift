import Foundation

final class HelperDelegate: NSObject, WiredHelperProtocol {

    // MARK: - Version

    func getVersion(withReply reply: @escaping (String) -> Void) {
        reply(kHelperVersion)
    }

    // MARK: - System directory

    func createSystemDirectory(path: String, owner: String,
                               withReply reply: @escaping (Bool, String) -> Void) {
        guard path.hasPrefix("/Library/"), !path.contains(".."), isValidAccount(owner) else {
            return reply(false, "Invalid parameters")
        }
        do {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
            run("/bin/chmod", ["755", path])
            run("/usr/sbin/chown", ["\(owner):staff", path])
            reply(true, "")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - FDA check

    func runFDACheck(scriptPath: String, outputPath: String,
                     withReply reply: @escaping (Bool, String) -> Void) {
        guard isAbsolutePath(scriptPath), isAbsolutePath(outputPath) else {
            return reply(false, "Invalid path")
        }
        run("/bin/sh", [scriptPath])
        let raw = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? "0"
        reply(raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1", "")
    }

    // MARK: - Daemon lifecycle

    func startDaemon(plistPath: String, label: String,
                     fdaScriptPath: String, fdaOutputPath: String,
                     withReply reply: @escaping (Bool, Bool, String) -> Void) {
        guard plistPath.hasPrefix("/Library/LaunchDaemons/"), isValidLabel(label) else {
            return reply(false, false, "Invalid parameters")
        }
        // bootstrap is a no-op if already registered; kickstart forces immediate start
        run("/bin/launchctl", ["bootstrap", "system", plistPath])
        let kickStatus = run("/bin/launchctl", ["kickstart", "system/\(label)"])

        var fdaGranted = false
        if !fdaScriptPath.isEmpty {
            run("/bin/sh", [fdaScriptPath])
            let raw = (try? String(contentsOfFile: fdaOutputPath, encoding: .utf8)) ?? "0"
            fdaGranted = raw.trimmingCharacters(in: .whitespacesAndNewlines) == "1"
        }

        if kickStatus == 0 {
            reply(true, fdaGranted, "")
        } else {
            reply(false, false, "launchctl kickstart exited \(kickStatus)")
        }
    }

    func stopDaemon(label: String, withReply reply: @escaping (Bool, String) -> Void) {
        guard isValidLabel(label) else { return reply(false, "Invalid label") }
        let status = run("/bin/launchctl", ["bootout", "system/\(label)"])
        // bootout exit 36 (ESRCH) means the service wasn't loaded — treat as success.
        if status == 0 || status == 36 {
            reply(true, "")
        } else {
            reply(false, "launchctl bootout exited \(status)")
        }
    }

    // MARK: - Daemon activation / deactivation

    func activateDaemon(config: NSDictionary, plistData: Data,
                        withReply reply: @escaping (Bool, String) -> Void) {
        guard
            let user      = config["user"]        as? String, isValidAccount(user),
            let group     = config["group"]       as? String, isValidAccount(group),
            let uid       = config["uid"]         as? Int,
            let gid       = config["gid"]         as? Int,
            let createUser  = config["createUser"]  as? Bool,
            let createGroup = config["createGroup"] as? Bool,
            let dataPath  = config["dataPath"]    as? String, dataPath.hasPrefix("/Library/"),
            let plistPath = config["plistPath"]   as? String, plistPath.hasPrefix("/Library/LaunchDaemons/")
        else { return reply(false, "Invalid configuration") }

        if createGroup {
            guard
                run("/usr/bin/dscl", [".", "-create", "/Groups/\(group)"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Groups/\(group)", "PrimaryGroupID", "\(gid)"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Groups/\(group)", "Password", "*"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Groups/\(group)", "RealName", "Wired Server"]) == 0
            else { return reply(false, "Failed to create group \(group)") }
        }

        if createUser {
            guard
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "UserShell", "/usr/bin/false"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "RealName", "Wired Server"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "UniqueID", "\(uid)"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "PrimaryGroupID", "\(gid)"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "NFSHomeDirectory", "/var/empty"]) == 0,
                run("/usr/bin/dscl", [".", "-create", "/Users/\(user)", "IsHidden", "1"]) == 0
            else { return reply(false, "Failed to create user \(user)") }
        }

        // Ownership & permissions
        run("/usr/sbin/chown", ["-R", "\(user):\(group)", dataPath])
        run("/usr/sbin/chown", ["\(user):staff", "\(dataPath)/bin"])
        run("/bin/chmod", ["775", "\(dataPath)/bin"])
        run("/bin/rm", ["-rf", "\(dataPath)/bin/.updates"])
        run("/bin/chmod", ["755", "\(dataPath)/bin/wired3"])   // ignore failure (file may not exist)
        run("/usr/sbin/chown", ["\(user):staff", "\(dataPath)/etc"])
        run("/bin/chmod", ["775", "\(dataPath)/etc"])
        run("/usr/sbin/chown", ["\(user):staff", "\(dataPath)/etc/config.ini"])
        run("/bin/chmod", ["664", "\(dataPath)/etc/config.ini"])

        // Install plist
        guard writePlist(plistData, to: plistPath) else {
            return reply(false, "Failed to install LaunchDaemon plist")
        }

        reply(true, "")
    }

    func deactivateDaemon(config: NSDictionary,
                          withReply reply: @escaping (Bool, String) -> Void) {
        guard
            let user        = config["user"]        as? String, isValidAccount(user),
            let group       = config["group"]       as? String, isValidAccount(group),
            let label       = config["label"]       as? String, isValidLabel(label),
            let plistPath   = config["plistPath"]   as? String, plistPath.hasPrefix("/Library/LaunchDaemons/"),
            let restoreUser = config["restoreUser"] as? String, isValidAccount(restoreUser),
            let dataPath    = config["dataPath"]    as? String, dataPath.hasPrefix("/Library/"),
            let deleteUser  = config["deleteUser"]  as? Bool,
            let deleteGroup = config["deleteGroup"] as? Bool
        else { return reply(false, "Invalid configuration") }

        run("/bin/launchctl", ["bootout", "system/\(label)"])
        Thread.sleep(forTimeInterval: 1.0)    // let daemon flush WAL before chown
        try? FileManager.default.removeItem(atPath: plistPath)
        run("/usr/sbin/chown", ["-R", "\(restoreUser):staff", dataPath])
        run("/bin/chmod", ["755", "\(dataPath)/bin"])
        run("/bin/chmod", ["755", "\(dataPath)/etc"])
        run("/bin/chmod", ["644", "\(dataPath)/etc/config.ini"])

        if deleteUser {
            run("/usr/bin/pkill", ["-u", user])
            Thread.sleep(forTimeInterval: 0.3)
            run("/usr/bin/dscl", [".", "-delete", "/Users/\(user)"])
        }
        if deleteGroup {
            run("/usr/bin/dscl", [".", "-delete", "/Groups/\(group)"])
        }

        reply(true, "")
    }

    // MARK: - Plist / binary install

    func installPlist(data: Data, destinationPath: String,
                      withReply reply: @escaping (Bool, String) -> Void) {
        guard destinationPath.hasPrefix("/Library/LaunchDaemons/") else {
            return reply(false, "Invalid destination path")
        }
        guard writePlist(data, to: destinationPath) else {
            return reply(false, "Failed to install plist")
        }
        reply(true, "")
    }

    func copyBinary(sourcePath: String, destinationPath: String,
                    withReply reply: @escaping (Bool, String) -> Void) {
        guard isAbsolutePath(sourcePath), isAbsolutePath(destinationPath),
              !sourcePath.contains(".."), !destinationPath.contains("..") else {
            return reply(false, "Invalid path")
        }
        do {
            if FileManager.default.fileExists(atPath: destinationPath) {
                try FileManager.default.removeItem(atPath: destinationPath)
            }
            try FileManager.default.copyItem(atPath: sourcePath, toPath: destinationPath)
            run("/bin/chmod", ["755", destinationPath])
            reply(true, "")
        } catch {
            reply(false, error.localizedDescription)
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError  = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    private func writePlist(_ data: Data, to path: String) -> Bool {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("wired3-helper-\(UUID().uuidString).plist")
        do {
            try data.write(to: tmp)
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
            try FileManager.default.copyItem(at: tmp, to: URL(fileURLWithPath: path))
            try FileManager.default.removeItem(at: tmp)
            run("/bin/chmod", ["644", path])
            run("/usr/sbin/chown", ["root:wheel", path])
            return true
        } catch {
            return false
        }
    }

    private func isValidAccount(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 32 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func isValidLabel(_ label: String) -> Bool {
        guard !label.isEmpty, label.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return label.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private func isAbsolutePath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.contains("..")
    }
}
