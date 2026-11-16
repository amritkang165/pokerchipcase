import Foundation

/// First message of a client: who it is and, when reconnecting, its token.
public struct Hello: Codable, Equatable, Sendable {
    /// Display name for the player's seat.
    public var name: String
    /// Reconnect token from an earlier `welcome`.
    public var token: String?

    /// Creates a `hello`; pass the `token` of an earlier `welcome` to reconnect, nil to join as new.
    public init(name: String, token: String?) {
        self.name = name
        self.token = token
    }
}

/// The host's answer to a `hello`: the player's ID and a token to reconnect with.
public struct Welcome: Codable, Equatable, Sendable {
    /// ID the host assigned to this player.
    public var player: PlayerID
    /// Secret the client presents in `hello` to take this seat back after a disconnect.
    public var token: String

    /// Creates a `welcome` for a seated player.
    public init(player: PlayerID, token: String) {
        self.player = player
        self.token = token
    }
}

/// Outcome of a command: accepted, or rejected with a reason.
public enum AckResult: Codable, Equatable, Sendable {
    /// The host applied the command.
    case ok
    /// The host refused the command; the game is unchanged.
    case rejected(reason: Rejection)
}

/// The host's answer to one client message.
public struct Ack: Codable, Equatable, Sendable {
    /// `id` of the client message being answered.
    public var id: UUID
    /// Whether the host applied the command.
    public var result: AckResult

    /// Creates the answer to the client message with envelope `id`.
    public init(id: UUID, result: AckResult) {
        self.id = id
        self.result = result
    }
}

/// A command sent by a client, tagged with the state version it was based on.
public struct CommandRequest: Codable, Equatable, Sendable {
    /// The change the client asks for.
    public var command: Command
    /// `GameState.version` of the last `state` the client saw.
    public var stateVersion: Int

    /// Wraps a command with the state version the sender last saw.
    public init(command: Command, stateVersion: Int) {
        self.command = command
        self.stateVersion = stateVersion
    }
}

/// A message from a client to the host.
public enum ClientMessage: Equatable, Sendable {
    /// Introduces the client; must be the first message on a connection.
    case hello(Hello)
    /// Asks the host to change the game.
    case command(CommandRequest)
    /// Heartbeat; the host answers with ``ServerMessage/pong``.
    case ping
}

/// A message from the host to a client.
public enum ServerMessage: Equatable, Sendable {
    /// Accepts the `hello` and assigns the player.
    case welcome(Welcome)
    /// Says whether the host applied a command.
    case ack(Ack)
    /// The latest game state; sent on every change.
    case state(GameState)
    /// Reports a failure; the payload is a ``WireErrorCode`` raw value.
    case error(String)
    /// Answer to ``ClientMessage/ping``, with the ping's envelope `id`.
    case pong
}

/// Machine-readable codes sent as the payload of `ServerMessage.error`.
public enum WireErrorCode: String, Sendable {
    /// The client's `Wire.version` differs from the host's.
    case versionMismatch
    /// All ``maxSeats`` seats are taken.
    case tableFull
    /// A new player tried to join after the tournament started (no valid token for a seat).
    case gameInProgress
    /// A command arrived before the client's `hello`.
    case helloRequired
    /// The message could not be decoded, or a second `hello` arrived on a connection.
    case malformed
    /// The player lost their seat: removed by the host, or their join was undone; sent just before the connection closes.
    case removed
    /// The host closed the table.
    case tableClosed
    /// The same player reconnected from another connection, which took over the seat.
    case replaced
}

/// Why a wire message could not be decoded.
public enum WireError: Error, Equatable {
    /// The envelope's `v`, which differs from ``Wire/version``.
    case versionMismatch(Int)
    /// The envelope's `type`, which is not a message of this direction.
    case unknownType(String)
}

/// JSON envelope `{"v": 2, "type": "<case>", "id": "<UUID>", "payload": …}`, see the PokerNet protocol article.
public enum Wire {
    /// Protocol version in the envelope `v` field; a message with another value is refused.
    public static let version = 2
    /// Bonjour service type the host advertises and clients browse for.
    public static let serviceType = "_pokerchipcase._tcp"

    /// Encoder for envelopes: dates as milliseconds since 1970, keys sorted.
    public static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        e.outputFormatting = .sortedKeys
        return e
    }

    /// Decoder matching ``encoder``.
    public static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }

    /// Encodes a client message into an envelope with the given `id`.
    public static func encode(_ message: ClientMessage, id: UUID) throws -> Data {
        switch message {
        case let .hello(p): try envelope("hello", p, id)
        case let .command(p): try envelope("command", p, id)
        case .ping: try envelope("ping", Empty(), id)
        }
    }

    /// Encodes a server message into an envelope with the given `id`.
    public static func encode(_ message: ServerMessage, id: UUID) throws -> Data {
        switch message {
        case let .welcome(p): try envelope("welcome", p, id)
        case let .ack(p): try envelope("ack", p, id)
        case let .state(p): try envelope("state", p, id)
        case let .error(p): try envelope("error", p, id)
        case .pong: try envelope("pong", Empty(), id)
        }
    }

    /// Decodes a client message and its envelope `id`; throws ``WireError`` for a wrong version or unknown type, or a `DecodingError` when the JSON does not parse.
    public static func decodeClient(_ data: Data) throws -> (id: UUID, message: ClientMessage) {
        let h = try header(data)
        switch h.type {
        case "hello": return (h.id, .hello(try payload(data)))
        case "command": return (h.id, .command(try payload(data)))
        case "ping": return (h.id, .ping)
        default: throw WireError.unknownType(h.type)
        }
    }

    /// Decodes a server message and its envelope `id`; throws ``WireError`` for a wrong version or unknown type, or a `DecodingError` when the JSON does not parse.
    public static func decodeServer(_ data: Data) throws -> (id: UUID, message: ServerMessage) {
        let h = try header(data)
        switch h.type {
        case "welcome": return (h.id, .welcome(try payload(data)))
        case "ack": return (h.id, .ack(try payload(data)))
        case "state": return (h.id, .state(try payload(data)))
        case "error": return (h.id, .error(try payload(data)))
        case "pong": return (h.id, .pong)
        default: throw WireError.unknownType(h.type)
        }
    }

    /// The envelope `id` of a message, if its header can be read (even when the payload cannot).
    public static func envelopeID(_ data: Data) -> UUID? {
        try? decoder.decode(Header.self, from: data).id
    }

    private struct Envelope<P: Encodable>: Encodable {
        var v: Int
        var type: String
        var id: UUID
        var payload: P
    }

    /// Payload `{}` of messages without content.
    private struct Empty: Encodable {}

    private struct Header: Decodable {
        var v: Int
        var type: String
        var id: UUID
    }

    private struct Body<P: Decodable>: Decodable {
        var payload: P
    }

    private static func envelope(_ type: String, _ payload: some Encodable, _ id: UUID) throws -> Data {
        try encoder.encode(Envelope(v: version, type: type, id: id, payload: payload))
    }

    private static func header(_ data: Data) throws -> Header {
        let h = try decoder.decode(Header.self, from: data)
        guard h.v == version else { throw WireError.versionMismatch(h.v) }
        return h
    }

    private static func payload<P: Decodable>(_ data: Data) throws -> P {
        try decoder.decode(Body<P>.self, from: data).payload
    }
}
