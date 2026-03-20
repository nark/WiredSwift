import Foundation
import GRDB
import WiredSwift

public final class EventEntry: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "events"

    private static let parametersSeparator = "\u{1C}"

    public var id: Int64?
    public var eventCode: UInt32
    public var parametersText: String?
    public var time: Date
    public var nick: String
    public var login: String
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

    public required init(row: Row) {
        id = row["id"]
        eventCode = row["event_code"]
        parametersText = row["parameters_text"]
        time = row["time"]
        nick = row["nick"]
        login = row["login"]
        ip = row["ip"]
    }

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

    public var parameters: [String] {
        guard let parametersText, !parametersText.isEmpty else { return [] }
        return parametersText.components(separatedBy: Self.parametersSeparator)
    }

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

    public func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["event_code"] = eventCode
        container["parameters_text"] = parametersText
        container["time"] = time
        container["nick"] = nick
        container["login"] = login
        container["ip"] = ip
    }

    public func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
