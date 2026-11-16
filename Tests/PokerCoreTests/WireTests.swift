import Foundation
import Testing
@testable import PokerCore

private let id1 = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private func json(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }

@Test func commandGoldenJSON() throws {
    let request = CommandRequest(command: .act(player: "B", action: .raiseTo(amount: 60)), stateVersion: 7)
    let data = try Wire.encode(ClientMessage.command(request), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"command":{"act":{"action":{"raiseTo":{"amount":60}},"player":"B"}},"stateVersion":7},"type":"command","v":3}"#)
}

@Test func ackGoldenJSON() throws {
    let data = try Wire.encode(ServerMessage.ack(Ack(id: id1, result: .rejected(reason: .notYourTurn))), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"id":"00000000-0000-0000-0000-000000000001","result":{"rejected":{"reason":"notYourTurn"}}},"type":"ack","v":3}"#)
}

@Test func helloGoldenJSON() throws {
    let data = try Wire.encode(ClientMessage.hello(Hello(name: "Anna", token: nil)), id: id1)
    #expect(json(data) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Anna"},"type":"hello","v":3}"#)
}

@Test func legacyHelloWithProtocolVersionDecodes() throws {
    let data = Data(#"{"id":"00000000-0000-0000-0000-000000000001","payload":{"name":"Anna","protocolVersion":1},"type":"hello","v":3}"#.utf8)
    #expect(try Wire.decodeClient(data).message == .hello(Hello(name: "Anna", token: nil)))
}

@Test func pingAndPongGoldenJSON() throws {
    #expect(json(try Wire.encode(ClientMessage.ping, id: id1)) == #"{"id":"00000000-0000-0000-0000-000000000001","payload":{},"type":"ping","v":3}"#)
    #expect(json(try Wire.encode(ServerMessage.pong, id: id1)) == #"{"id":"00000000-0000-0000-0000-000000000001","payload":{},"type":"pong","v":3}"#)
}

@Test func clientRoundTrip() throws {
    for message: ClientMessage in [
        .hello(Hello(name: "Ben", token: "t")),
        .command(CommandRequest(command: .resolveShowdown(winners: [["A", "B"]]), stateVersion: 3)),
        .command(CommandRequest(command: .undo, stateVersion: 0)),
        .ping,
    ] {
        let decoded = try Wire.decodeClient(Wire.encode(message, id: id1))
        #expect(decoded.id == id1 && decoded.message == message)
    }
}

@Test func serverRoundTrip() throws {
    var g = try Game.started()
    try g.apply(.pauseClock, by: "A", at: t0 + 1.5)
    for message: ServerMessage in [
        .state(g.state),
        .state(try Game.started(digital: true).state),
        .welcome(Welcome(player: "B", token: "secret")),
        .ack(Ack(id: id1, result: .ok)),
        .error("broken"),
        .pong,
        .handover(Handover(game: g, tokens: ["secret": "B"])),
    ] {
        let decoded = try Wire.decodeServer(Wire.encode(message, id: id1))
        #expect(decoded.id == id1 && decoded.message == message)
    }
}

@Test func versionMismatchRejected() {
    let data = Data(#"{"v":2,"type":"hello","id":"00000000-0000-0000-0000-000000000001","payload":{}}"#.utf8)
    #expect(throws: WireError.versionMismatch(2)) { try Wire.decodeClient(data) }
}

@Test func unknownTypeRejected() {
    let data = Data(#"{"v":3,"type":"bogus","id":"00000000-0000-0000-0000-000000000001","payload":{}}"#.utf8)
    #expect(throws: WireError.unknownType("bogus")) { try Wire.decodeClient(data) }
}

@Test func seatWithCardsGoldenJSON() throws {
    var seat = Seat(id: "A", name: "A", stack: 1000)
    seat.holeCards = cards("Ah Tc")
    #expect(json(try Wire.encoder.encode(seat)) ==
        #"{"acted":false,"allIn":false,"folded":false,"handBet":0,"holeCards":["Ah","Tc"],"id":"A","mayRaise":true,"name":"A","roundBet":0,"stack":1000,"stackAtHandStart":0}"#)
    let state = json(try Wire.encoder.encode(try Game.started().state))
    for field in [#""board":[]"#, #""deck":[]"#, #""digitalCards":false"#] { #expect(state.contains(field)) }
}

@Test func transferHostGoldenJSON() throws {
    let request = CommandRequest(command: .transferHost(to: "B"), stateVersion: 7)
    #expect(json(try Wire.encode(ClientMessage.command(request), id: id1)) ==
        #"{"id":"00000000-0000-0000-0000-000000000001","payload":{"command":{"transferHost":{"to":"B"}},"stateVersion":7},"type":"command","v":3}"#)
}

@Test func handoverPayloadHasGameAndTokens() throws {
    let g = try Game.started()
    let data = try Wire.encode(ServerMessage.handover(Handover(game: g, tokens: ["secret": "B"])), id: id1)
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let payload = try #require(object["payload"] as? [String: Any])
    let game = try #require(payload["game"] as? [String: Any])
    #expect(object["type"] as? String == "handover")
    #expect(payload["tokens"] as? [String: String] == ["secret": "B"])
    #expect(game["state"] != nil && (game["history"] as? [Any])?.count == g.history.count)
}

/// 1 MiB is `MessageChannel.maxMessageSize`: a longer line makes the receiver drop the connection.
@Test func handoverWithFiftyUndoStepsFitsOneMessage() throws {
    var g = try Game.started(
        ["A": 1000, "B": 1000, "C": 1000, "D": 1000, "E": 1000, "F": 1000, "G": 1000, "H": 1000, "I": 1000, "J": 1000],
        digital: true)
    for _ in 0..<3 {
        try g.checkDown()
        try g.apply(.startNextHand, by: "A", at: t0)
    }
    #expect(g.history.count > 50)
    g.keepHistory(last: 50)
    let data = try Wire.encode(ServerMessage.handover(Handover(game: g, tokens: [:])), id: id1)
    #expect(data.count < 1_048_576)
}
