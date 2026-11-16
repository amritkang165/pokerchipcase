import Foundation
import PokerCore
import Testing
@testable import PokerNet

@Suite(.timeLimit(.minutes(1)))
struct HostCardsTests {
    @Test func clientsReceiveOnlyTheirOwnCards() async throws {
        let t = try await Table.open(snapshot: testSnapshot(digital: true))
        let ben = t.benWelcome.player
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        let seenByAnna = try await t.anna.state { $0.phase == .betting }
        let seenByBen = try await t.ben.state { $0.phase == .betting }
        let full = await t.host.snapshot.game.state
        #expect(full.deck.count == 48)
        #expect(seenByAnna.deck.isEmpty && seenByBen.deck.isEmpty)
        #expect(seenByAnna.seat(t.hostID)?.holeCards == full.seat(t.hostID)?.holeCards)
        #expect(seenByAnna.seat(ben)?.holeCards == [])
        #expect(seenByBen.seat(ben)?.holeCards == full.seat(ben)?.holeCards)
        #expect(seenByBen.seat(t.hostID)?.holeCards == [])
        await t.host.stop()
    }

    @Test func reconnectGetsOwnCardsAgain() async throws {
        let t = try await Table.open(snapshot: testSnapshot(digital: true))
        t.anna.send(t.command(.startTournament(button: t.hostID)))
        _ = try await t.ben.state { $0.phase == .betting }
        let again = try await RawClient.connect(t.port)
        again.send(hello("Ben", token: t.benWelcome.token))
        let seen = try await again.state { $0.phase == .betting }
        let full = await t.host.snapshot.game.state
        #expect(seen.seat(t.benWelcome.player)?.holeCards == full.seat(t.benWelcome.player)?.holeCards)
        #expect(full.seat(t.benWelcome.player)?.holeCards.count == 2)
        #expect(seen.seat(t.hostID)?.holeCards == [] && seen.deck.isEmpty)
        await t.host.stop()
    }
}
