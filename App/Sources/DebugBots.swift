#if DEBUG
import Network
import PokerCore
import PokerNet
import PokerSession
import SwiftUI

/// Debug builds only: fills the host's lobby with in-process guests that check or call on their turn,
/// so a full table can be played on one simulator.
@MainActor enum DebugBots {
    private static let names = ["foo", "bar", "baz", "qux", "quux", "corge", "grault", "Maximilian-Alexander", "garply"]
    // ponytail: bots are never torn down; they idle after the table ends. Add cleanup if they get in the way.
    private static var bots: [(TableSession, Task<Void, Never>)] = []

    /// Launch argument `-debugTable`: create a table, fill it with bots and start, with no taps.
    /// Combine with `-playerName Du` and `-appearance felt|dark`.
    static let auto = ProcessInfo.processInfo.arguments.contains("-debugTable")

    static func autoStart(_ host: TableSession) async {
        fill(host, count: maxSeats)
        for _ in 0..<60 where (host.state?.seats.count ?? 0) < maxSeats { try? await Task.sleep(for: .milliseconds(500)) }
        if let me = host.me { await host.send(.startTournament(button: me)) }
    }

    /// What a bot does on its turn.
    static func action(_ legal: LegalActions, style: BotStyle) -> Action {
        if style == .raise, let to = legal.minRaiseTo { return .raiseTo(amount: to) }
        return legal.canCheck ? .check : .call
    }

    /// Launch argument `-debugLongGame`: build a 10-player tournament 200 hands in, time the save, then host it.
    static let long = ProcessInfo.processInfo.arguments.contains("-debugLongGame")

    /// A table with the host and 9 more players, played to `hands` with every hand going to showdown
    /// (worst case for the save file). The winner rotates so nobody goes broke early.
    static func longGame(hands: Int, hostName: String, tableName: String) throws -> HostSnapshot {
        var snapshot = HostSnapshot.newTable(hostName: hostName, tableName: tableName, config: .relaxed)
        let host = snapshot.game.state.hostID
        let now = Date()  // One date, so the blinds never rise.
        for name in names { try snapshot.game.apply(.join(player: UUID().uuidString, name: name), by: host, at: now) }
        try snapshot.game.apply(.startTournament(button: host), by: host, at: now)
        while snapshot.game.state.handNumber <= hands, snapshot.game.state.phase != .finished {
            let state = snapshot.game.state
            switch state.phase {
            case .betting:
                guard let i = state.toActIndex, let legal = state.legalActions(for: state.seats[i].id) else { return snapshot }
                try snapshot.game.apply(.act(player: state.seats[i].id, action: action(legal, style: .call)), by: state.seats[i].id, at: now)
            case .showdown:
                let winners = state.pots.map { [$0.eligible[state.handNumber % $0.eligible.count]] }
                try snapshot.game.apply(.resolveShowdown(winners: winners), by: host, at: now)
            case .handComplete:
                try snapshot.game.apply(.startNextHand, by: host, at: now)
            default:
                return snapshot
            }
        }
        return snapshot
    }

    /// Prints the history length, file size and the time of one `SaveFile.host` save and load.
    static func reportSaveTimes(_ snapshot: HostSnapshot) {
        let file = SaveFile<HostSnapshot>.host
        let save = ContinuousClock().measure { try? file.save(snapshot) }
        let load = ContinuousClock().measure { _ = file.load() }
        let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("debugLongGame: history=\(snapshot.game.history.count) bytes=\(size) save=\(save) load=\(load)")
    }

    /// Joins up to `count` bots into free seats, with names not yet seated.
    // ponytail: names already launched but not yet seated (async join) are not excluded, so tapping "Add bots" twice quickly can reuse a name. Ceiling: a duplicate bot name in a debug build. Upgrade: a static pending-names set that fill inserts into and a failed join removes from.
    static func fill(_ host: TableSession, count: Int, speed: BotSpeed = .fast, style: BotStyle = .call) {
        let seated = host.state?.seats.map(\.name) ?? []
        let free = max(0, maxSeats - seated.count)
        for name in names.filter({ !seated.contains($0) }).prefix(min(count, free)) {
            Task {
                // Bonjour, like a real guest; a throwaway ticket file so the real seat ticket stays untouched.
                let bot = await TableSession.join(
                    endpoint: .service(name: host.tableName, type: Wire.serviceType, domain: "local.", interface: nil),
                    tableName: host.tableName, code: host.code, name: name,
                    ticketFile: SaveFile(url: .temporaryDirectory.appending(path: "bot-\(name).json")))
                let play = Task {
                    while !Task.isCancelled {
                        if bot.legalActions != nil, !bot.isSending {
                            try? await Task.sleep(for: speed.delay)
                            if let legal = bot.legalActions, !bot.isSending { await bot.act(action(legal, style: style)) }
                        }
                        try? await Task.sleep(for: .milliseconds(200))
                    }
                }
                bots.append((bot, play))
            }
        }
    }
}

/// How long a debug bot waits on its turn before acting.
enum BotSpeed: String, CaseIterable {
    case slow, fast
    var label: String { self == .slow ? "🐢 Slow" : "🐇 Fast" }
    var delay: Duration { self == .slow ? .seconds(5) : .milliseconds(800) }
}

/// What a debug bot does on its turn.
enum BotStyle: String, CaseIterable {
    case call, raise
    var label: String { self == .call ? "Call" : "Raise" }
}
#endif
