import Foundation
@testable import PokerCore

let t0 = Date(timeIntervalSince1970: 0)
let tenTwenty = [BlindLevel(smallBlind: 10, bigBlind: 20, duration: 600)]

extension Game {
    /// Host = first player. Stacks are set in the lobby, then startTournament(button:) at t0.
    static func started(
        _ stacks: KeyValuePairs<PlayerID, Chips> = ["A": 1000, "B": 1000, "C": 1000],
        levels: [BlindLevel] = tenTwenty,
        button: PlayerID = "A",
        digital: Bool = false
    ) throws -> Game {
        let host = stacks.first!.key
        let config = TournamentConfig(startingStack: 1000, levels: levels, digitalCards: digital)
        var g = Game(hostID: host, hostName: host, config: config)
        for (id, _) in stacks.dropFirst() {
            try g.apply(.join(player: id, name: id), by: host, at: t0)
        }
        for (id, stack) in stacks {
            g.state.seats[g.state.index(of: id)!].stack = stack
        }
        try g.apply(.startTournament(button: button), by: host, at: t0)
        return g
    }

    /// Sets the hole cards of the given seats and the deck the board is drawn from; call it right after `started`.
    mutating func rig(_ holes: KeyValuePairs<PlayerID, String>, board: String) {
        for (id, text) in holes { state.seats[state.index(of: id)!].holeCards = cards(text) }
        state.deck = cards(board)
    }

    var toAct: PlayerID? { state.toActIndex.map { state.seats[$0].id } }

    /// Checks or calls until no betting round is running.
    mutating func checkDown() throws(Rejection) {
        while state.phase == .betting, let p = toAct {
            try act(state.legalActions(for: p)!.canCheck ? .check : .call)
        }
    }

    /// Applies act(player: toAct, action:).
    mutating func act(_ action: Action, at now: Date = t0) throws(Rejection) {
        guard let p = toAct else { throw .notYourTurn }
        try apply(.act(player: p, action: action), by: p, at: now)
    }
}

/// Parses space-separated cards such as "Ah Tc 2s".
func cards(_ text: String) -> [Card] { text.split(separator: " ").map { Card(String($0))! } }

/// SplitMix64: deterministic randomness for reproducible tournaments.
struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
