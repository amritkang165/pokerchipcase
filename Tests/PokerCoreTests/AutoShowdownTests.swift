import Foundation
import Testing
@testable import PokerCore

private let rags = "3s 8d Jc 4h 9s"

@Test func bestHandIsPaidAtOnce() throws {
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    #expect(g.state.phase == .handComplete && g.state.board == cards(rags))
    #expect(g.state.seats.map(\.stack) == [1040, 980, 980])
    #expect(g.state.seats.allSatisfy(g.state.isRevealed))
    #expect(g.state.handValue(of: g.state.seats[0])?.name == "Pair")
}

@Test func sidePotGoesToTheBestEligibleHand() throws {
    var g = try Game.started(["A": 1000, "B": 300, "C": 1000], digital: true)
    g.rig(["A": "7c 2d", "B": "Ah Ad", "C": "Kh Kd"], board: rags)
    try g.act(.allIn); try g.act(.call); try g.act(.call)
    #expect(g.state.seat("B")?.stack == 900 && g.state.seat("C")?.stack == 1400)
    #expect(g.state.seat("A")?.eliminatedRank == 3 && g.state.board.count == 5)
}

@Test func tiedHandsSplitAndFoldedHandsDoNotCount() throws {
    var g = try Game.started(levels: [BlindLevel(smallBlind: 5, bigBlind: 10, duration: 600)], digital: true)
    g.rig(["A": "Ah 2c", "B": "7c 7d", "C": "Ad 2s"], board: "Kh Qd Jc 9s 4h")
    try g.act(.call); try g.act(.fold); try g.checkDown()
    #expect(g.state.seat("A")?.stack == 1002 && g.state.seat("C")?.stack == 1003)
    #expect(!g.state.isRevealed(g.state.seat("B")!))
}

@Test func foldWinRevealsNothing() throws {
    var g = try Game.started(digital: true)
    try g.act(.fold); try g.act(.fold)
    #expect(g.state.phase == .handComplete && !g.state.seats.contains(where: g.state.isRevealed))
}

@Test func undoAfterThePayoutReturnsToTheShowdown() throws {
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown && g.state.pots == [Pot(amount: 60, eligible: ["A", "B", "C"])])
    #expect(g.state.seats.allSatisfy(g.state.isRevealed))
    try g.apply(.resolveShowdown(winners: [["C"]]), by: "A", at: t0)
    #expect(g.state.phase == .handComplete && g.state.seat("C")?.stack == 1040)
}

@Test func secondUndoReturnsToBettingAndTheHandPaysOutAgain() throws {   // Review Focus 5
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.call); try g.act(.call); try g.checkDown()
    try g.apply(.undo, by: "A", at: t0); try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .betting && g.state.street == .river && g.state.board == cards(rags))
    try g.checkDown()
    #expect(g.state.phase == .handComplete && g.state.seat("A")?.stack == 1040)
}

@Test func payoutThatEndsTheTournamentCanBeUndone() throws {
    var g = try Game.started(["A": 1000, "B": 1000], digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd"], board: rags)
    try g.act(.allIn); try g.act(.call)
    #expect(g.state.phase == .finished && g.state.seat("A")?.stack == 2000)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown)
}

@Test func bustedSeatHoldsNoCardsInLaterHands() throws {              // Review Focus 3
    var g = try Game.started(digital: true)
    g.rig(["A": "Ah Ad", "B": "Kh Kd", "C": "7c 2d"], board: rags)
    try g.act(.allIn); try g.act(.call); try g.act(.fold)
    try g.apply(.startNextHand, by: "A", at: t0)
    #expect(g.state.seat("B")?.isEliminated == true && g.state.seat("B")?.holeCards == [])
    #expect(g.state.seat("A")?.holeCards.count == 2 && g.state.seat("C")?.holeCards.count == 2)
}

@Test func allInFromTheBlindsIsPaidInsideTheStartCommand() throws {     // Review Focus 1
    var g = try Game.started(["A": 10, "B": 1000], digital: true)
    #expect(g.state.phase == .handComplete || g.state.phase == .finished)
    #expect(g.state.board.count == 5 && g.state.seats.map(\.stack).reduce(0, +) == 1010)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.phase == .showdown && g.state.pots == [Pot(amount: 20, eligible: ["A", "B"])])
}
