import Foundation

/// Log severity levels matching the `wired.log.level` protocol enumeration.
///
/// Values correspond to the protocol spec:
///   0 = debug, 1 = info, 2 = warning, 3 = error
public enum WiredLogLevel: UInt32, CaseIterable, Sendable, Hashable, Comparable {
    case debug   = 0
    case info    = 1
    case warning = 2
    case error   = 3

    public static func < (lhs: WiredLogLevel, rhs: WiredLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var title: String {
        switch self {
        case .debug:   return "Debug"
        case .info:    return "Info"
        case .warning: return "Warning"
        case .error:   return "Error"
        }
    }

    public var systemImageName: String {
        switch self {
        case .debug:   return "ant"
        case .info:    return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error:   return "xmark.octagon"
        }
    }

    public var color: String {
        switch self {
        case .debug:   return "secondary"
        case .info:    return "primary"
        case .warning: return "yellow"
        case .error:   return "red"
        }
    }
}

/// A single server log entry received via `wired.log.list` or `wired.log.message`.
public struct WiredLogEntry: Identifiable, Hashable, Sendable {
    public let time: Date
    public let level: WiredLogLevel
    public let message: String

    public init(time: Date, level: WiredLogLevel, message: String) {
        self.time = time
        self.level = level
        self.message = message
    }

    /// Decode from a `wired.log.list` or `wired.log.message` P7Message.
    public init?(message: P7Message) {
        guard
            let time    = message.date(forField: "wired.log.time"),
            let rawLevel = message.enumeration(forField: "wired.log.level"),
            let level   = WiredLogLevel(rawValue: rawLevel),
            let text    = message.string(forField: "wired.log.message")
        else {
            return nil
        }

        self.init(time: time, level: level, message: text)
    }

    public var id: String {
        "\(time.timeIntervalSince1970)|\(level.rawValue)|\(message)"
    }
}
