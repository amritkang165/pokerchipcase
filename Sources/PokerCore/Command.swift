/// What a player does on their turn.
public enum Action: Codable, Equatable, Sendable {
    /// Gives up the hand.
    case fold
    /// Passes without betting; only legal when nothing is owed.
    case check
    /// Matches the current bet, or goes all-in for less.
    case call
    /// Raises the player's total bet in this betting round to `amount` (a bet if nobody has bet yet).
    case raiseTo(amount: Chips)
    /// Bets the whole stack.
    case allIn
}

/// A request to change the game, applied with ``Game/apply(_:by:at:expectedVersion:)``.
public enum Command: Codable, Equatable, Sendable {
    /// Seats a new player; host only, in the lobby.
    case join(player: PlayerID, name: String)
    /// Takes a player out; the host may remove anyone but themselves in the lobby, during betting or between hands, a player only themselves in the lobby.
    case removePlayer(player: PlayerID)
    /// Sets the seat order to `order`, which must list every seated player once; host only, in the lobby.
    case arrangeSeats(order: [PlayerID])
    /// Deals the first hand with `button` as dealer; host only, needs at least two players.
    case startTournament(button: PlayerID)
    /// Plays `action` for `player`; the host may only fold or check for someone else.
    case act(player: PlayerID, action: Action)
    /// Winners per pot, in the order of `GameState.pots`.
    case resolveShowdown(winners: [[PlayerID]])
    /// Deals the next hand after a payout; dealer or host.
    case startNextHand
    /// Stops the blind clock; host only.
    case pauseClock
    /// Restarts a paused blind clock; host only.
    case resumeClock
    /// Reverts the last command other than a clock pause or resume; host only. The clock itself is not rolled back.
    /// In a digital game the first undo after a showdown returns to the showdown before the automatic payout.
    case undo
}

/// Why a command was refused; the game stays unchanged.
public enum Rejection: String, Error, Codable, Equatable, Sendable {
    /// Only the host may send this command.
    case notHost
    /// Only the dealer or the host may send this command.
    case notDealer
    /// The player is not the one to act, or the sender may not act for them.
    case notYourTurn
    /// The command is not allowed in the current ``Phase`` (or clock state).
    case invalidPhase
    /// The action does not fit the situation, for example checking when a bet is open.
    case illegalAction
    /// A raise is below the minimum or above the player's stack.
    case invalidAmount
    /// The player is not seated or already eliminated, or `arrangeSeats` does not list every seated player exactly once.
    case unknownPlayer
    /// A player with this ID is already seated.
    case duplicatePlayer
    /// All ``maxSeats`` seats are taken.
    case tableFull
    /// The tournament needs at least two players.
    case tooFewPlayers
    /// The tournament config has no levels, a non-positive stack or duration, or a small blind outside `1...bigBlind`.
    case invalidConfig
    /// The winners do not match the pots, or a winner is not eligible for a pot.
    case invalidShowdown
    /// There is no earlier state to return to.
    case nothingToUndo
    /// The command was based on an outdated state.
    case staleState
}
