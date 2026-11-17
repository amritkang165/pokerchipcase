#if DEBUG
import Network
import PokerCore
import PokerNet
import PokerSession
import SwiftUI

/// Debug builds only: fills the host's lobby with in-process guests that check, call or raise on their turn,
/// so a full table can be played on one simulator.
@MainActor enum DebugBots {
    /// Shuffled per fill, so every screenshot shows different, realistic names. The long one tests truncation.
    private static let names = [
        "Ace High", "Bluff Daddy", "Chip Chopper", "River Rat", "Lucky Lou", "Pocket Rocket", "Big Slick",
        "Nuts McGee", "Tilt Master", "All-In Annie", "Card Shark", "Fishy Fred", "The Professor", "Donk",
        "Royal Flush", "Snake Eyes", "Slow Roll", "Check Raise", "Full House Fritz", "Queen Bee", "Jackpot Jo",
        "King Kev", "Deuce Dora", "Trips Tina", "Gutshot Gus", "Kicker", "Muck Duck", "Short Stack",
        "Big Blind Bob", "Small Blind Sue", "Dealer Dan", "Button Betty", "Nit Wit", "Calling Station", "Whale",
        "Maverick", "Iceman", "Sundance", "Cool Hand", "The Grinder", "Mister Chips", "Lady Luck", "Wild Card",
        "Joker", "Poker Face", "Stone Cold", "Monte", "Vegas Vic", "Reno Rita", "Atlantic Al", "Felt Burner",
        "Chip Leader", "Rainbow", "Flopzilla", "Turn Burn", "Nine High", "Seven Deuce", "Hammer", "Cowboy", "Ladies",
        "Hooks", "Snowmen", "Ducks", "Fishhooks", "Pocket Kings", "Suited Connector", "Backdoor Barry", "Overbet Olga",
        "Min-Raise Max", "Limp Larry", "Straddle Steve", "Ante Up", "Bubble Boy", "Satellite Sam", "Final Table",
        "Heads Up", "Dead Money", "Busto", "Rebuy Rick", "Freeroll Franzi", "Bad Beat Bernd", "Cooler Carl",
        "Suckout Susi", "Rungood Rudi", "Variance Vera", "Equity Eddie", "Range Ronja", "Bluffmaster Flex", "Tellmann",
        "Sunglasses Sam", "Hoodie Hank", "Moneybags", "Cashout Chris", "Dolly Draw", "Stack Stu", "Fold Phil",
        "Fold Pre", "Snap Call", "Tank Tom", "Maximilian-Alexander",
    ]
    // ponytail: bots are never torn down; they idle after the table ends. Add cleanup if they get in the way.
    private static var bots: [(TableSession, Task<Void, Never>)] = []

    /// Launch argument `-debugTable`: create a table, fill it with bots and start, with no taps.
    /// Combine with `-playerName Du`, `-theme felt|neon|ruby|royal` and `-appearance light|dark|system`.
    static let auto = ProcessInfo.processInfo.arguments.contains("-debugTable")

    /// Launch argument `-debugStop lobby|turn|showdown|payout`, with `-debugTable`: where the host stops
    /// playing by itself, for screenshots. Without it the host starts the game and plays by hand.
    /// In a digital game the host pays out at once, so `showdown` and `payout` both stop at the first
    /// paid-out showdown.
    private static let stop = UserDefaults.standard.string(forKey: "debugStop")

    static func autoStart(_ host: TableSession) async {
        fill(host, count: maxSeats)
        for _ in 0..<60 where (host.state?.seats.count ?? 0) < maxSeats { try? await Task.sleep(for: .milliseconds(500)) }
        guard stop != "lobby", let me = host.me else { return }
        await host.send(.startTournament(button: me))
        guard stop == "showdown" || stop == "payout" else { return }
        // The host calls like a bot until the first showdown, then pays the first eligible player per pot.
        while let state = host.state, !stopsPlaying(state) {
            if let legal = host.legalActions, !host.isSending { await host.act(action(legal, style: .call)) }
            try? await Task.sleep(for: .milliseconds(200))
        }
        guard stop == "payout", host.state?.phase == .showdown, let pots = host.state?.pots else { return }
        await host.send(.resolveShowdown(winners: pots.map { [$0.eligible.contains(me) ? me : $0.eligible[0]] }))
    }

    /// The host's loop for `-debugStop showdown|payout` ends here; a digital game never rests in `showdown`.
    private static func stopsPlaying(_ state: GameState) -> Bool {
        state.phase == .showdown
            || state.config.digitalCards && (state.phase == .handComplete || state.phase == .finished)
    }

    /// What a bot does on its turn.
    static func action(_ legal: LegalActions, style: BotStyle) -> Action {
        if style == .raise, let to = legal.minRaiseTo { return .raiseTo(amount: to) }
        return legal.canCheck ? .check : .call
    }

    /// Launch argument `-debugLongGame`: build a 10-player tournament 200 hands in, time the save, then host it.
    static let long = ProcessInfo.processInfo.arguments.contains("-debugLongGame")
    /// Set once the long game ran, so StartView reappearing does not rebuild it.
    static var longRan = false

    /// A table with the host and 9 more players, played to `hands` with every hand going to showdown
    /// (worst case for the save file). The winner rotates so nobody goes broke early.
    static func longGame(hands: Int, hostName: String, tableName: String) throws -> HostSnapshot {
        var snapshot = HostSnapshot.newTable(hostName: hostName, tableName: tableName, config: .relaxed)
        let host = snapshot.game.state.hostID
        let now = Date()  // One date, so the blinds never rise.
        for name in names.shuffled().prefix(maxSeats - 1) { try snapshot.game.apply(.join(player: UUID().uuidString, name: name), by: host, at: now) }
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
    static func reportSaveTimes(_ snapshot: HostSnapshot) throws {
        let file = SaveFile<HostSnapshot>.host
        var failure: Error?
        let save = ContinuousClock().measure { do { try file.save(snapshot) } catch { failure = error } }
        if let failure { throw failure }
        let load = ContinuousClock().measure { _ = file.load() }
        let size = (try? file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        print("debugLongGame: history=\(snapshot.game.history.count) bytes=\(size) save=\(save) load=\(load)")
    }

    /// Joins up to `count` bots into free seats, with names not yet seated.
    // ponytail: names already launched but not yet seated (async join) are not excluded, so tapping "Add bots" twice quickly can reuse a name. Ceiling: a duplicate bot name in a debug build. Upgrade: a static pending-names set that fill inserts into and a failed join removes from.
    static func fill(_ host: TableSession, count: Int, speed: BotSpeed = .fast, style: BotStyle = .call) {
        let seated = host.state?.seats.map(\.name) ?? []
        let free = max(0, maxSeats - seated.count)
        for name in names.shuffled().filter({ !seated.contains($0) }).prefix(min(count, free)) {
            launch(host, name: name, speed: speed, style: style)
        }
    }

    /// After a saved table is resumed: reconnects a bot for every seat that has a bot ticket for this table.
    /// The tickets live in the temporary directory; if the system purged them, use the host menu instead.
    static func resume(_ host: TableSession, from snapshot: HostSnapshot) {
        for seat in snapshot.game.state.seats where seat.id != snapshot.game.state.hostID {
            guard let ticket = ticketFile(seat.name).load(), ticket.code == snapshot.code else { continue }
            launch(host, name: seat.name, token: ticket.token)
        }
    }

    private static func ticketFile(_ name: String) -> SaveFile<SeatTicket> {
        SaveFile(url: .temporaryDirectory.appending(path: "bot-\(name).json"))
    }

    /// Joins one bot, or with `token` takes its seat back, and plays its turns until the app quits.
    private static func launch(_ host: TableSession, name: String, token: String? = nil,
                               speed: BotSpeed = .fast, style: BotStyle = .call) {
        Task {
            // Loopback, like the host itself: on a device, resolving our own Bonjour service took
            // so long that the bots joined minutes late, all at once. Real guests still test Bonjour.
            // Its own ticket file, so the real seat ticket stays untouched and `resume` finds the seat again.
            let endpoint: NWEndpoint = host.port.map { .hostPort(host: "127.0.0.1", port: $0) }
                ?? .service(name: host.tableName, type: Wire.serviceType, domain: "local.", interface: nil)
            // ponytail: bots do not follow a `successor`, so handing over to a bot or away from the bots' host
            // stalls the debug table. Upgrade: let bots follow `successor`.
            // Their own save file, so a handover to a bot never touches the device's real host save.
            let botSave = SaveFile<HostSnapshot>(
                url: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "host.json"))
            let bot = await TableSession.join(
                endpoint: endpoint,
                tableName: host.tableName, code: host.code, name: name, token: token,
                ticketFile: ticketFile(name), saveFile: botSave)
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
