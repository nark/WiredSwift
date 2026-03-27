import Foundation
import GRDB
import WiredSwift

/// A server event log record stored in the `events` SQLite table.
///
/// Each row captures a single auditable server event (e.g. login, file transfer,
/// ban) with the originating user's identity and connection details. Multiple
/// event parameters are joined into `parametersText` using a unit-separator
/// character and split back on access via the `parameters` computed property.
public final class EventEntry: FetchableRecord, PersistableRecord {
    /// The GRDB table name for this model.
    public static let databaseTableName = "events"

    private static let parametersSeparator = "\u{1C}"

    /// Auto-assigned database row identifier; `nil` before the first INSERT.
    public var id: Int64?
    /// Numeric Wired event code identifying the type of event.
    public var eventCode: UInt32
    /// Raw storage for event parameters joined by the unit-separator character.
    public var parametersText: String?
    /// Timestamp when the event occurred.
    public var time: Date
    /// Display nick of the user who triggered the event.
    public var nick: String
    /// Login name of the user who triggered the event.
    public var login: String
    /// IP address of the client that triggered the event.
    public var ip: String

    enum Columns {
        static let id = Column("id")
        static let eventCode = Column("event_code")
        static let parametersText = Column("parameters_text")
        static let time = Column("time")
        static let nick = Column("nick")
        static let login = Column("login")
        static let ip = Column("ip")
    }

    /// Initialises an `EventEntry` from a GRDB database row.
    ///
    /// - Parameter row: The GRDB `Row` containing column values.
    public required init(row: Row) {
        id = row["id"]
        eventCode = row["event_code"]
        parametersText = row["parameters_text"]
        time = row["time"]
        nick = row["nick"]
        login = row["login"]
        ip = row["ip"]
    }

    /// Creates a new `EventEntry` from structured event data.
    ///
    /// The `parameters` array is joined with the internal unit-separator character
    /// and stored in `parametersText`. An empty array results in `nil`.
    ///
    /// - Parameters:
    ///   - eventCode: Numeric Wired event code.
    ///   - parameters: Ordered list of event-specific parameter strings.
    ///   - time: When the event occurred; defaults to the current date/time.
    ///   - nick: Display nick of the triggering user.
    ///   - login: Login name of the triggering user.
    ///   - ip: IP address of the triggering client.
    public init(
        eventCode: UInt32,
        parameters: [String],
        time: Date = Date(),
        nick: String,
        login: String,
        ip: String
    ) {
        self.eventCode = eventCode
        self.parametersText = parameters.isEmpty
            ? nil
            : parameters.joined(separator: Self.parametersSeparator)
        self.time = time
        self.nick = nick
        self.login = login
        self.ip = ip
    }

    /// The event's parameters decoded from `parametersText`.
    ///
    /// Returns an empty array when `parametersText` is `nil` or empty.
    public var parameters: [String] {
        guard let parametersText, !parametersText.isEmpty else { return [] }
        return parametersText.components(separatedBy: Self.parametersSeparator)
    }

    /// Converts this database entry into a `WiredServerEventRecord` value type
    /// suitable for use with the WiredSwift framework.
    public var record: WiredServerEventRecord {
        WiredServerEventRecord(
            eventCode: eventCode,
            time: time,
            parameters: parameters,
            nick: nick,
            login: login,
            ip: ip
        )
    }

    /// Encodes this event entry's fields into a GRDB `PersistenceContainer`.
    ///
    /// - Parameter container: The container to write column values into.
    /// - Throws: Never; declared `throws` to satisfy the protocol.
    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["event_code"] = eventCode
        container["parameters_text"] = parametersText
        container["time"] = time
        container["nick"] = nick
        container["login"] = login
        container["ip"] = ip
    }

    /// Called by GRDB after an INSERT; captures the auto-assigned row identifier.
    ///
    /// - Parameter inserted: GRDB insertion result containing the new `rowID`.
    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
