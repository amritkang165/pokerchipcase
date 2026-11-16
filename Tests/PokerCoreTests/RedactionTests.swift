import Foundation
import Testing
@testable import PokerCore

@Test func otherHandsAndTheDeckAreHidden() throws {
    let g = try Game.started(digital: true)
    var expected = g.state
    expected.deck = []
    expected.seats[0].holeCards = []
    expected.seats[2].holeCards = []
    #expect(g.state.redacted(for: "B") == expected)
    #expect(expected.seats[1].holeCards.count == 2)
    #expect(g.state.redacted(for: nil).seats.allSatisfy { $0.holeCards.isEmpty })
    #expect(g.state.redacted(for: "nobody").seats.allSatisfy { $0.holeCards.isEmpty })
}

@Test func revealedHandsStayAndFoldedOnesDoNot() throws {
    var g = try Game.started(digital: true)
    try g.act(.call); try g.act(.fold); try g.checkDown()             // B folded; A and C show down
    let full = g.state
    for viewer in ["A", "B", "C", nil] as [PlayerID?] {
        let seen = full.redacted(for: viewer)
        #expect(seen.deck.isEmpty && seen.board == full.board)
        #expect(seen.seat("A")?.holeCards == full.seat("A")?.holeCards)
        #expect(seen.seat("C")?.holeCards == full.seat("C")?.holeCards)
        #expect(seen.seat("B")?.holeCards == (viewer == "B" ? full.seat("B")!.holeCards : []))
    }
}

@Test func removedPlayerIsNeverRevealed() throws {                    // Review Focus 2
    var g = try Game.started(["A": 1000, "B": 1000, "C": 1000, "D": 1000], digital: true)
    try g.apply(.removePlayer(player: "C"), by: "A", at: t0)
    try g.checkDown()
    #expect(g.state.phase == .handComplete && !g.state.isRevealed(g.state.seat("C")!))
    #expect(g.state.redacted(for: "A").seat("C")?.holeCards == [])
}
