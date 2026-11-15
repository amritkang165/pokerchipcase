import Foundation

/// An amount of play-money chips.
public typealias Chips = Int
/// Identifies a player at the table.
public typealias PlayerID = String

/// One step of the blind schedule; `duration` is in seconds.
public struct BlindLevel: Codable, Equatable, Sendable {
    /// Chips the small blind posts: the player left of the button, or the button itself heads-up.
    public var smallBlind: Chips
    /// Chips the big blind posts, the next player after the small blind; also the minimum bet.
    public var bigBlind: Chips
    /// How long the level lasts, in seconds.
    public var duration: TimeInterval

    /// Creates a level; `duration` is in seconds.
    public init(smallBlind: Chips, bigBlind: Chips, duration: TimeInterval) {
        self.smallBlind = smallBlind
        self.bigBlind = bigBlind
        self.duration = duration
    }
}

/// Starting stack and blind schedule of a tournament.
public struct TournamentConfig: Codable, Equatable, Sendable {
    /// Chips every player starts with.
    public var startingStack: Chips
    /// Blind levels in play order; the last one never ends.
    public var levels: [BlindLevel]
    /// True when the app deals the cards: hole cards, board and an automatic showdown.
    public var digitalCards: Bool

    /// Creates a config; ``Command/startTournament(button:)`` rejects it unless it is valid.
    public init(startingStack: Chips, levels: [BlindLevel], digitalCards: Bool = false) {
        self.startingStack = startingStack
        self.levels = levels
        self.digitalCards = digitalCards
    }

    /// At least one level, every level `0 < smallBlind <= bigBlind` with a positive duration, a positive stack.
    var isValid: Bool {
        startingStack > 0 && !levels.isEmpty
            && levels.allSatisfy { 0 < $0.smallBlind && $0.smallBlind <= $0.bigBlind && $0.duration > 0 }
    }

    private static let standardBlinds: [(Chips, Chips)] = [
        (10, 20), (15, 30), (25, 50), (50, 100), (75, 150),
        (100, 200), (150, 300), (200, 400), (300, 600), (500, 1000),
    ]

    private static func standard(levelDuration: TimeInterval) -> TournamentConfig {
        TournamentConfig(
            startingStack: 1000,
            levels: standardBlinds.map { BlindLevel(smallBlind: $0.0, bigBlind: $0.1, duration: levelDuration) }
        )
    }

    /// Ten levels of 20 minutes from 10/20 to 500/1000, starting stack 1000.
    public static let relaxed = standard(levelDuration: 1200)
    /// Same blinds as ``relaxed`` with 10-minute levels.
    public static let quick = standard(levelDuration: 600)
    /// Named configs for the host to choose from when creating a table.
    public static let presets: [(name: String, config: TournamentConfig)] = [
        ("Relaxed – 20 min", relaxed),
        ("Quick – 10 min", quick),
    ]
}

/// A player's seat: their stack, bets in the current hand and tournament status.
public struct Seat: Codable, Equatable, Sendable {
    /// Identifies the player; stays the same across reconnects.
    public var id: PlayerID
    /// Name shown at the table.
    public var name: String
    /// Chips not currently bet.
    public var stack: Chips
    /// Bet in the current betting round.
    public var roundBet: Chips = 0
    /// Bet in the whole hand.
    public var handBet: Chips = 0
    /// Stack when the current hand began; used to rank players who bust together.
    public var stackAtHandStart: Chips = 0
    /// True once the player folded or was removed in this hand; every hand starts with eliminated seats folded.
    public var folded = false
    /// True when the whole stack is bet and no further action is possible.
    public var allIn = false
    /// True once the player acted since the last raise in this betting round.
    public var acted = false
    /// False when an incomplete all-in raise did not reopen raising for this player.
    public var mayRaise = true
    /// Final rank; nil while the player is still in the tournament (and for the winner).
    public var eliminatedRank: Int?
    /// The player's two cards in a digital game; empty with real cards and for eliminated players.
    public var holeCards: [Card] = []

    /// Seats a player who has not bet yet.
    public init(id: PlayerID, name: String, stack: Chips) {
        self.id = id
        self.name = name
        self.stack = stack
    }

    /// True once the player has a final rank: busted at the end of a hand, or removed by the host (from the end of that hand on).
    public var isEliminated: Bool { eliminatedRank != nil }
}

/// Where the game is in its lifecycle.
public enum Phase: String, Codable, Equatable, Sendable {
    /// Players are joining and seats can be arranged; no hand has started.
    case lobby
    /// A hand is being played and ``GameState/toActIndex`` names the player to act.
    case betting
    /// Betting is over and the dealer reports the winner of each pot.
    case showdown
    /// The hand is paid out and waits for ``Command/startNextHand``.
    case handComplete
    /// One player holds all chips; the tournament is over.
    case finished
}

/// The betting round of a hand.
public enum Street: String, Codable, Equatable, Sendable {
    /// Before any community card; the blinds are posted.
    case preflop
    /// After the first three community cards.
    case flop
    /// After the fourth community card.
    case turn
    /// After the fifth and last community card.
    case river
}

/// A main or side pot and the players who can win it.
public struct Pot: Codable, Equatable, Sendable {
    /// Chips in this pot.
    public var amount: Chips
    /// Players still in the hand who can win this pot.
    public var eligible: [PlayerID]
}

/// Progress through the blind levels; `levelEndsAt` is nil while the clock is paused or not started.
public struct BlindClock: Codable, Equatable, Sendable {
    /// Index into ``TournamentConfig/levels`` of the current level.
    public var levelIndex = 0
    /// When the current level ends; nil while paused or before the tournament starts.
    public var levelEndsAt: Date?
    /// Seconds left in the level while paused; nil while running.
    public var pausedRemaining: TimeInterval?

    /// Creates a clock that has not started: level 0, no end time.
    public init() {}
}

/// The complete table state that the host sends to every client.
public struct GameState: Codable, Equatable, Sendable {
    /// Starting stack and blind schedule.
    public var config: TournamentConfig
    /// ID of the player who runs the table.
    public var hostID: PlayerID
    /// Players in seat order, eliminated ones included.
    public var seats: [Seat]
    /// Where the game is in its lifecycle.
    public var phase: Phase = .lobby
    /// Betting round of the current hand.
    public var street: Street = .preflop
    /// Index into `seats` of the dealer button; nil before the first hand.
    public var buttonIndex: Int?
    /// Number of the current hand, counted from 1; 0 in the lobby.
    public var handNumber = 0
    /// Highest bet in this betting round that others must match.
    public var currentBet: Chips = 0
    /// Size of the last full raise this round; a new raise must add at least this much.
    public var lastRaiseSize: Chips = 0
    /// Index into `seats` of the player to act; nil when nobody has to act.
    public var toActIndex: Int?
    /// Main pot first; filled when the hand reaches showdown, empty otherwise.
    public var pots: [Pot] = []
    /// Community cards dealt so far in a digital game; empty with real cards.
    public var board: [Card] = []
    /// Cards not yet dealt in a digital game, drawn from the front; empty with real cards.
    public var deck: [Card] = []
    /// Blind level timer.
    public var clock = BlindClock()
    /// Increases with every change (undo too); clients send it back so late double taps get rejected.
    public var version = 0

    /// Creates a lobby state with the given players seated.
    public init(config: TournamentConfig, hostID: PlayerID, seats: [Seat]) {
        self.config = config
        self.hostID = hostID
        self.seats = seats
    }

    /// The seat with this ID, nil if nobody is seated under it.
    public func seat(_ id: PlayerID) -> Seat? {
        seats.first { $0.id == id }
    }

    func index(of id: PlayerID) -> Int? {
        seats.firstIndex { $0.id == id }
    }
}
