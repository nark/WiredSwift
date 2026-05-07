import Foundation

let kHelperMachServiceName = "fr.read-write.WiredServer3.Helper"
let kHelperVersion = "1"

/// XPC protocol between WiredServerApp and WiredServerHelper.
/// All operations are specific and validated — the helper never executes arbitrary shell commands.
@objc protocol WiredHelperProtocol: NSObjectProtocol {

    /// Create /Library/Wired3 (or similar system path) owned by the given user.
    func createSystemDirectory(
        path: String,
        owner: String,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Run a pre-written FDA check shell script and return whether access was granted.
    func runFDACheck(
        scriptPath: String,
        outputPath: String,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Bootstrap and kickstart the LaunchDaemon. Optionally runs an FDA check script
    /// in the same root context to avoid a second auth prompt.
    /// Reply: (success, fdaGranted, errorMessage)
    func startDaemon(
        plistPath: String,
        label: String,
        fdaScriptPath: String,
        fdaOutputPath: String,
        withReply reply: @escaping (Bool, Bool, String) -> Void
    )

    /// Bootout the LaunchDaemon.
    func stopDaemon(
        label: String,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Create daemon user/group, set ownership, install LaunchDaemon plist.
    /// config keys: user, group, uid, gid, createUser, createGroup, dataPath, plistPath
    func activateDaemon(
        config: NSDictionary,
        plistData: Data,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Bootout daemon, restore ownership, remove plist, optionally delete user/group.
    /// config keys: user, group, label, plistPath, restoreUser, dataPath, deleteUser, deleteGroup
    func deactivateDaemon(
        config: NSDictionary,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Copy plist data to a LaunchDaemons path with correct ownership.
    func installPlist(
        data: Data,
        destinationPath: String,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Copy a binary to a destination and set it executable.
    func copyBinary(
        sourcePath: String,
        destinationPath: String,
        withReply reply: @escaping (Bool, String) -> Void
    )

    /// Returns kHelperVersion — used to detect when the helper needs updating.
    func getVersion(withReply reply: @escaping (String) -> Void)
}
