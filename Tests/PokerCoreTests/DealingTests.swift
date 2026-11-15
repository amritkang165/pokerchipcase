import Foundation
import Testing
@testable import PokerCore

private func allCards(_ s: GameState) -> [Card] { s.seats.flatMap(\.holeCards) + s.board + s.deck }

@Test func realCardGamesHoldNoCards() throws {
    var g = try Game.started()
    try g.act(.call); try g.act(.call); try g.checkDown()
    #expect(allCards(g.state).isEmpty && g.state.phase == .showdown)
}

@Test func everySeatGetsTwoCardsAndTheBoardGrowsByStreet() throws {
    var g = try Game.started(digital: true)
    #expect(g.state.seats.allSatisfy { $0.holeCards.count == 2 } && g.state.board.isEmpty)
    try g.act(.call); try g.act(.call); try g.act(.check)
    #expect(g.state.street == .flop && g.state.board.count == 3)
    try g.act(.check); try g.act(.check); try g.act(.check)
    #expect(g.state.street == .turn && g.state.board.count == 4)
    try g.act(.check); try g.act(.check); try g.act(.check)
    #expect(g.state.street == .river && g.state.board.count == 5)
    #expect(allCards(g.state).count == 52 && Set(allCards(g.state)).count == 52)
}

@Test func sameSeedDealsTheSameCards() throws {
    func deal(seed: UInt64) throws -> GameState {
        var rng = SeededRNG(state: seed)
        var g = Game(hostID: "A", hostName: "A",
                     config: TournamentConfig(startingStack: 1000, levels: tenTwenty, digitalCards: true))
        try g.apply(.join(player: "B", name: "B"), by: "A", at: t0)
        try g.apply(.startTournament(button: "A"), by: "A", at: t0, using: &rng)
        return g.state
    }
    #expect(try deal(seed: 1) == deal(seed: 1))
    #expect(try deal(seed: 1).seats.map(\.holeCards) != deal(seed: 2).seats.map(\.holeCards))
}

@Test func undoMidHandKeepsTheCards() throws {       // Review Focus 4
    var g = try Game.started(digital: true)
    try g.act(.call); try g.act(.call)
    let before = g.state
    try g.act(.check)
    try g.apply(.undo, by: "A", at: t0)
    #expect(g.state.seats.map(\.holeCards) == before.seats.map(\.holeCards))
    #expect(g.state.board == before.board && g.state.deck == before.deck)
}
