import Foundation

func diagLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    guard let data = line.data(using: .utf8) else { return }
    let url = URL(fileURLWithPath: "/tmp/wiredhelper.log")
    if let fh = try? FileHandle(forWritingTo: url) {
        fh.seekToEndOfFile()
        fh.write(data)
        try? fh.close()
    } else {
        try? data.write(to: url)
    }
}

diagLog("=== WiredServerHelper starting ===")
diagLog("PID: \(ProcessInfo.processInfo.processIdentifier)")
diagLog("XPC_SERVICE_NAME: \(ProcessInfo.processInfo.environment["XPC_SERVICE_NAME"] ?? "(nil)")")
diagLog("Bundle: \(Bundle.main.bundlePath)")
diagLog("Argv[0]: \(CommandLine.arguments.first ?? "(nil)")")

let helper = HelperTool()
helper.run()

diagLog("run() returned — process will exit")
