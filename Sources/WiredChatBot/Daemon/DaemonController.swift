// WiredChatBot — DaemonController.swift
// POSIX daemon management: fork, setsid, PID file, log file setup.

import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public final class DaemonController {
    private let config: DaemonConfig

    public init(config: DaemonConfig) {
        self.config = config
    }

    // MARK: - Daemonize (Linux / POSIX)

    public func daemonize() {
        #if os(Linux)
        // First fork
        let pid1 = fork()
        guard pid1 >= 0 else { perror("fork"); exit(EXIT_FAILURE) }
        if pid1 > 0 { exit(EXIT_SUCCESS) }   // parent exits

        // New session leader
        guard setsid() >= 0 else { perror("setsid"); exit(EXIT_FAILURE) }

        // Second fork — prevent re-acquiring a controlling terminal
        let pid2 = fork()
        guard pid2 >= 0 else { perror("fork2"); exit(EXIT_FAILURE) }
        if pid2 > 0 { exit(EXIT_SUCCESS) }

        // Reset umask, chdir to root
        umask(0)
        chdir("/")

        // Redirect stdin/stdout/stderr to /dev/null
        let devNull = open("/dev/null", O_RDWR)
        if devNull >= 0 {
            dup2(devNull, STDIN_FILENO)
            dup2(devNull, STDOUT_FILENO)
            dup2(devNull, STDERR_FILENO)
            if devNull > STDERR_FILENO { close(devNull) }
        }
        #else
        BotLogger.warning("Daemon mode is Linux-only. Running in foreground.")
        #endif
    }

    // MARK: - PID file

    public func writePIDFile() {
        let pid = ProcessInfo.processInfo.processIdentifier
        do {
            try "\(pid)\n".write(toFile: config.pidFile, atomically: true, encoding: .utf8)
            BotLogger.info("PID \(pid) written to \(config.pidFile)")
        } catch {
            BotLogger.warning("Cannot write PID file '\(config.pidFile)': \(error)")
        }
    }

    public func removePIDFile() {
        try? FileManager.default.removeItem(atPath: config.pidFile)
    }

    // MARK: - Logging setup (call BEFORE daemonizing)

    public func configureLogging(verbose: Bool) {
        let level = verbose ? "DEBUG" : config.logLevel
        BotLogger.configure(level: level, filePath: config.logFile)
    }
}
