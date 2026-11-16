import Foundation
import Network
import PokerCore
import Testing
@testable import PokerNet

/// Host IDs of every snapshot passed to `onChange`.
private actor SavedHosts {
    var ids: Set<PlayerID> = []
    func add(_ id: PlayerID) { ids.insert(id) }
}

@Suite(.timeLimit(.minutes(1)))
struct HostHandoverTests {
    /// Starts the tournament and returns the version both clients have seen.
    private func start(_ t: Table) async throws -> Int {
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        let version = try await t.anna.state { $0.phase == .betting }.version
        #expect(try await t.anna.ack().result == .ok)
        _ = try await t.ben.state { $0.phase == .betting }
        return version
    }

    @Test func handoverGoesToTheTargetAndTheHostStops() async throws {
        let saved = SavedHosts()
        let t = try await Table.open(onChange: { s in Task { await saved.add(s.game.state.hostID) } })
        let version = try await start(t)
        let ben = t.benWelcome.player
        let id = UUID()
        t.anna.send(t.command(.transferHost(to: ben), version: version), id: id)
        #expect(try await t.anna.ack() == Ack(id: id, result: .ok))
        let handover = try #require(try await t.ben.next { $0.handover != nil }.handover)
        #expect(handover.game.state.hostID == ben && handover.game.state.version == version + 1)
        #expect(handover.game.history.count <= TableHost.handoverHistory)
        #expect(handover.tokens.count == 2 && handover.tokens[t.benWelcome.token] == ben)
        try await t.ben.waitForClose()
        try await t.anna.waitForClose()
        #expect(await t.host.handedOver)
        #expect(await !t.host.isListening)
        // No save names the new host, so the old host can resume if the target fails.
        try await Task.sleep(for: .milliseconds(200))
        #expect(await saved.ids == [t.hostID])
    }

    @Test func disconnectedTargetIsRejected() async throws {
        let t = try await Table.open()
        let version = try await start(t)
        t.ben.close()
        try await eventually { await !t.host.connectedPlayers.contains(t.benWelcome.player) }
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .rejected(reason: .playerOffline))
        #expect(await t.host.isListening)
        #expect(await t.host.snapshot.game.state.hostID == t.hostID)
        #expect(await !t.host.handedOver)
        await t.host.stop()
    }

    /// A suspended app keeps its TCP connection but sends nothing.
    @Test func silentTargetIsRejectedUntilItPings() async throws {
        let t = try await Table.open(liveWindow: .milliseconds(500))
        let version = try await start(t)
        try await Task.sleep(for: .milliseconds(700))
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .rejected(reason: .playerOffline))
        t.ben.send(.ping)
        _ = try await t.ben.next { $0 == .pong }
        t.anna.send(t.command(.transferHost(to: t.benWelcome.player), version: version))
        #expect(try await t.anna.ack().result == .ok)
        _ = try await t.ben.next { $0.handover != nil }
    }

    @Test func tableClientReportsTheHandover() async throws {
        let (host, port) = try await startHost()
        let anna = try await RawClient.connect(port)
        anna.send(hello("Anna", token: await host.snapshot.hostToken))
        let hostID = try await anna.welcome().player
        let ben = TableClient(endpoint: loopback(port), code: code4711, name: "Ben")
        let events = EventRecorder(ben.events)
        await ben.connect()
        let welcome = try #require(try await events.first { $0.welcome != nil }.welcome)
        let lobby = try await anna.state { $0.seats.count == 2 }
        anna.send(.command(CommandRequest(command: .startTournament(button: hostID), stateVersion: lobby.version)))
        let version = try await anna.state { $0.phase == .betting }.version
        anna.send(.command(CommandRequest(command: .transferHost(to: welcome.player), stateVersion: version)))
        let handover = try #require(try await events.first { $0.handover != nil }.handover)
        #expect(handover.game.state.hostID == welcome.player)
        await ben.disconnect()
    }
}
