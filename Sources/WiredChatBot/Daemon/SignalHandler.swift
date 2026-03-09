// WiredChatBot — SignalHandler.swift
// Uses DispatchSource for signal handling on both Linux and macOS.
// DispatchSource is available via swift-corelibs-dispatch on Linux.

import Foundation

#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum SignalHandler {
    public static var onTerminate: (() -> Void)?
    public static var onReload:    (() -> Void)?

    // Strong references so DispatchSources are not released prematurely
    private static var sources: [DispatchSourceSignal] = []

    public static func setup() {
        // Let DispatchSource intercept these signals instead of default handlers
        signal(SIGPIPE, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGINT,  SIG_IGN)
        signal(SIGHUP,  SIG_IGN)

        let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigterm.setEventHandler {
            BotLogger.info("SIGTERM — shutting down…")
            SignalHandler.onTerminate?()
        }
        sigterm.resume()
        sources.append(sigterm)

        let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigint.setEventHandler {
            BotLogger.info("SIGINT — shutting down…")
            SignalHandler.onTerminate?()
        }
        sigint.resume()
        sources.append(sigint)

        let sighup = DispatchSource.makeSignalSource(signal: SIGHUP, queue: .main)
        sighup.setEventHandler {
            BotLogger.info("SIGHUP — reloading config…")
            SignalHandler.onReload?()
        }
        sighup.resume()
        sources.append(sighup)
    }
}
