import Foundation
import Network
import PokerCore
import PokerNet

/// A JSON file holding one value. Plain JSONEncoder/JSONDecoder, so dates round-trip exactly.
public struct SaveFile<Value: Codable & Sendable>: Sendable {
    /// Location of the file.
    public let url: URL

    /// Creates a handle; the file is not touched until used.
    public init(url: URL) { self.url = url }

    /// nil if missing or unreadable.
    public func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    /// Creates the directory, writes atomically.
    public func save(_ value: Value) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
    }

    /// No error if missing.
    public func delete() throws {
        do { try FileManager.default.removeItem(at: url) } catch CocoaError.fileNoSuchFile {
            // Already gone: nothing to delete.
        }
    }
}

extension SaveFile where Value == HostSnapshot {
    /// The host's resumable table, in Application Support.
    public static var host: Self { .init(url: .applicationSupportDirectory.appending(path: "host.json")) }
}

extension SaveFile where Value == SeatTicket {
    /// A guest's seat ticket, in Application Support.
    public static var seat: Self { .init(url: .applicationSupportDirectory.appending(path: "seat.json")) }
}

/// What a guest needs to take its seat back after the app was killed.
public struct SeatTicket: Codable, Equatable, Sendable {
    /// Bonjour name of the table.
    public var tableName: String
    /// Code of the table.
    public var code: TableCode
    /// Name the guest joined with.
    public var name: String
    /// Reconnect token from the table's `welcome`.
    public var token: String

    /// The table's Bonjour service, resolved anew on every connect.
    public var endpoint: NWEndpoint {
        .service(name: tableName, type: Wire.serviceType, domain: "local.", interface: nil)
    }
}

extension HostSnapshot {
    /// The save can be resumed: the host has a token and the tournament is not finished.
    public var isResumable: Bool {
        hostToken != nil && game.state.phase != .finished
    }
}
