import Foundation
import PokerCore
import Testing
@testable import PokerNet

@Suite(.timeLimit(.minutes(1)))
struct HostCommandTests {
    @Test func commandAckedAndBroadcast() async throws {
        let t = try await Table.open()
        let id = UUID()
        t.anna.send(t.command(.startTournament(button: t.hostID)), id: id)
        #expect(try await t.anna.ack() == Ack(id: id, result: .ok))
        _ = try await t.ben.state { $0.phase == .betting }
        await t.host.stop()
    }

    @Test func rejectedCommandAckedToSenderOnly() async throws {
        let t = try await Table.open()
        t.ben.send(t.command(.startTournament(button: t.hostID)))
        #expect(try await t.ben.ack().result == .rejected(reason: .notHost))
        #expect(await t.host.snapshot.game.state.phase == .lobby)
        await t.host.stop()
    }

    @Test func staleVersionRejected() async throws {
        let t = try await Table.open()
        t.anna.send(t.command(.startTournament(button: t.hostID), version: t.version - 1))
        #expect(try await t.anna.ack().result == .rejected(reason: .staleState))
        await t.host.stop()
    }

    @Test func commandBeforeHelloRejected() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(t.command(.startNextHand))
        #expect(try await cem.error() == WireErrorCode.helloRequired.rawValue)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        await t.host.stop()
    }

    @Test func malformedMessageGetsErrorAndConnectionStays() async throws {
        let t = try await Table.open()
        t.ben.sendRaw(Data("broken".utf8))
        #expect(try await t.ben.error() == WireErrorCode.malformed.rawValue)
        t.ben.send(t.command(.startNextHand))
        #expect(try await t.ben.ack().result == .rejected(reason: .invalidPhase))
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.anna.state { $0.phase == .betting }
        await t.host.stop()
    }

    @Test func removedPlayerRejoinsUnderTheOldID() async throws {
        let t = try await Table.open()
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player)))
        #expect(try await t.ben.error() == WireErrorCode.removed.rawValue)
        try await t.ben.waitForClose()
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        #expect(try await again.welcome() == t.benWelcome)
        #expect(await t.host.snapshot.tokens.count == 2)
        await t.host.stop()
    }

    @Test func undoAfterALobbyRejoinLeavesNoGhost() async throws {
        let t = try await Table.open()
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player)))
        try await t.ben.waitForClose()
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        let ticket = try await again.welcome()  // the app overwrites its seat ticket with this
        let rejoined = try await t.anna.state { $0.seats.count == 2 }
        t.anna.send(t.command(.undo, version: rejoined.version))
        #expect(try await again.error() == WireErrorCode.removed.rawValue)
        let undone = try await t.anna.state { $0.version > rejoined.version }
        t.anna.send(t.command(.undo, version: undone.version))
        let restored = try await t.anna.state { $0.version > undone.version }
        #expect(restored.seats.map(\.id) == [t.hostID, t.benWelcome.player])
        let back = try await RawClient.connect(t.port)
        back.send(hello("Ben", token: ticket.token))
        #expect(try await back.welcome().player == t.benWelcome.player)
        await t.host.stop()
    }

    @Test func seatlessTokenCannotJoinARunningGame() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        let three = try await t.anna.state { $0.seats.count == 3 }
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: three.version))
        let two = try await t.anna.state { $0.seats.count == 2 }
        t.anna.send(t.command(.startTournament(button: t.hostID), version: two.version))
        _ = try await t.anna.state { $0.phase == .betting }
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        #expect(try await again.error() == WireErrorCode.gameInProgress.rawValue)
        #expect(await t.host.snapshot.tokens.count == 3)
        await t.host.stop()
    }

    @Test func removedMidGameIsDisconnectedAndKeepsTheToken() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        let state = try await t.anna.state { $0.seats.count == 3 }
        t.anna.send(t.command(.startTournament(button: t.hostID), version: state.version))
        let running = try await t.anna.state { $0.phase == .betting }
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: running.version))
        #expect(try await t.ben.error() == WireErrorCode.removed.rawValue)
        try await t.ben.waitForClose()
        #expect(await t.host.snapshot.tokens[t.benWelcome.token] == t.benWelcome.player)
        #expect(await t.host.snapshot.game.state.seat(t.benWelcome.player) != nil)  // seat kept mid-game
        await t.host.stop()
    }

    @Test func undoneRemovalLetsThePlayerReconnect() async throws {
        let t = try await Table.open()
        let cem = try await RawClient.connect(t.port)
        cem.send(hello("Cem"))
        _ = try await cem.welcome()
        let state = try await t.anna.state { $0.seats.count == 3 }
        t.anna.send(t.command(.startTournament(button: t.hostID), version: state.version))
        let running = try await t.anna.state { $0.phase == .betting }
        t.anna.send(t.command(.removePlayer(player: t.benWelcome.player), version: running.version))
        try await t.ben.waitForClose()
        let removed = try await t.anna.state { $0.version > running.version }
        t.anna.send(t.command(.undo, version: removed.version))
        _ = try await t.anna.state { $0.version > removed.version }
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        #expect(try await again.welcome().player == t.benWelcome.player)
        #expect(try await again.state().seat(t.benWelcome.player)?.stack ?? 0 > 0)
        await t.host.stop()
    }

    @Test func errorReplyCarriesRequestID() async throws {
        let t = try await Table.open()
        let id = UUID()
        let raw = #"{"id":"\#(id.uuidString)","payload":{"command":{"bogus":{}},"stateVersion":0},"type":"command","v":3}"#
        t.ben.sendRaw(Data(raw.utf8))
        let reply = try await t.ben.nextEnvelope { $0.error != nil }
        #expect(reply.message.error == WireErrorCode.malformed.rawValue && reply.id == id)
        await t.host.stop()
    }

    @Test func ensureListeningRestartsAfterListenerFailure() async throws {
        let (host, port) = try await startHost()
        await host.simulateListenerFailure()
        try await eventually { await !host.isListening }
        try await host.ensureListening()
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    @Test func ensureListeningRestartsBeforeTheStoppedCallback() async throws {
        let (host, port) = try await startHost()
        await host.simulateListenerFailure(callbackLost: true)
        try await eventually { await !host.isListening }
        try await host.ensureListening()
        #expect(await host.isListening)
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    /// A start still waiting behind the previous one when the table stops must not listen again (#107).
    @Test func stopCancelsAStartThatIsStillWaiting() async throws {
        let (host, _) = try await startHost()
        let (entered, enter) = AsyncStream<Void>.makeStream()
        let (release, open) = AsyncStream<Void>.makeStream()
        await host.setBeforeBind {
            enter.yield()
            for await _ in release {
                // Only waits for the stream to end.
            }
        }
        let start = Task { try await host.start() }
        for await _ in entered { break }
        await host.stop()
        open.finish()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(await !host.isListening)
    }

    @Test func restartOnTheSamePortWhileListening() async throws {
        let (host, port) = try await startHost()
        #expect(try await host.start(port: port) == port)
        let ben = try await RawClient.connect(port)
        ben.send(hello("Ben"))
        _ = try await ben.welcome()
        await host.stop()
    }

    /// A new listener can get the old one's address; its late stopped callback must not clear the new one.
    @Test func manySamePortRestartsKeepTheHostReachable() async throws {
        let (host, port) = try await startHost()
        let token = await host.snapshot.hostToken
        for _ in 0..<50 {
            #expect(try await host.start(port: port) == port)
            let anna = try await RawClient.connect(port)
            anna.send(hello("Anna", token: token))
            _ = try await anna.welcome()
            anna.close()
        }
        await host.stop()
    }

    @Test func onChangeAfterCommand() async throws {
        let inbox = Inbox()
        let t = try await Table.open(onChange: { s in Task { await inbox.put(s) } })
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.anna.ack()
        try await eventually { await inbox.last?.game.state.phase == .betting }
        await t.host.stop()
    }

    @Test func secondStartStopsTheFirstListener() async throws {
        let (host, first) = try await startHost()
        _ = try await host.start()
        // Host still running, so only a closed first listener (not the accept guard) can end this stream.
        let channel = MessageChannel(to: loopback(first), code: code4711)
        let rec = EventRecorder(channel.events)
        channel.start()
        #expect(try await rec.waitForEnd() != nil)
        await host.stop()
    }
}

extension TableHost {
    func setBeforeBind(_ hook: @escaping @Sendable () async -> Void) { beforeBind = hook }
}
