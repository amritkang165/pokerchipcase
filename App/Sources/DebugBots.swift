#if DEBUG
import Network
import PokerCore
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

    /// Joins up to `count` bots into free seats, with names not yet seated.
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
