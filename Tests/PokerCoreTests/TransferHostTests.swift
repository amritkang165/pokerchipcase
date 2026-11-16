import Foundation
import Testing
@testable import PokerCore

@Test func transferHostMovesTheHostRights() throws {
    var g = try Game.started()
    let version = g.state.version
    try g.apply(.transferHost(to: "B"), by: "A", at: t0)
    #expect(g.state.hostID == "B" && g.state.version == version + 1)
    #expect(throws: Rejection.notHost) { try g.apply(.pauseClock, by: "A", at: t0) }
    try g.apply(.pauseClock, by: "B", at: t0)
    try g.apply(.removePlayer(player: "A"), by: "B", at: t0)
}

@Test func transferHostGuards() throws {
    var g = try Game.started()
    #expect(throws: Rejection.notHost) { try g.apply(.transferHost(to: "C"), by: "B", at: t0) }
    #expect(throws: Rejection.unknownPlayer) { try g.apply(.transferHost(to: "X"), by: "A", at: t0) }
    #expect(throws: Rejection.illegalAction) { try g.apply(.transferHost(to: "A"), by: "A", at: t0) }
    g.state.phase = .finished
    #expect(throws: Rejection.invalidPhase) { try g.apply(.transferHost(to: "B"), by: "A", at: t0) }
    var lobby = Game(hostID: "A", hostName: "A", config: TournamentConfig(startingStack: 1000, levels: tenTwenty))
    try lobby.apply(.join(player: "B", name: "B"), by: "A", at: t0)
    #expect(throws: Rejection.invalidPhase) { try lobby.apply(.transferHost(to: "B"), by: "A", at: t0) }
    #expect(g.state.hostID == "A" && lobby.state.hostID == "A")
}

@Test func transferHostIsNotAnUndoStepAndSurvivesUndo() throws {
    var g = try Game.started()
    try g.act(.fold)  // A folds; B is next
    let steps = g.history.count
    try g.apply(.transferHost(to: "B"), by: "A", at: t0)
    #expect(g.history.count == steps)
    try g.apply(.undo, by: "B", at: t0)
    #expect(g.state.hostID == "B" && g.toAct == "A")
}

@Test func keepHistoryDropsTheOldestSteps() throws {
    var g = try Game.started()
    try g.act(.call)
    try g.act(.call)
    let newest = g.history.last
    g.keepHistory(last: 1)
    #expect(g.history.count == 1 && g.history.last == newest)
    g.keepHistory(last: 5)
    #expect(g.history.count == 1)
}
