extension GameState {
    // The deck cannot run out: a hand uses at most 10 × 2 + 5 = 25 of 52 cards.
    /// Removes and returns the first `count` cards of `deck`.
    mutating func draw(_ count: Int) -> [Card] {
        let cards = Array(deck.prefix(count))
        deck.removeFirst(cards.count)
        return cards
    }
}

extension GameState {
    /// True when everyone may see the seat's hole cards: the hand reached a showdown and the seat is still in it.
    /// A hand won by everyone else folding reveals nothing.
    public func isRevealed(_ seat: Seat) -> Bool {
        [.showdown, .handComplete, .finished].contains(phase) && !seat.folded && seats.count { !$0.folded } >= 2
    }

    /// The best five-card hand of the seat's hole cards and the board; nil unless it holds 2 cards and the board 5.
    public func handValue(of seat: Seat) -> HandValue? {
        seat.holeCards.count == 2 && board.count == 5 ? evaluate(seat.holeCards + board) : nil
    }

    /// Per pot, the eligible players with the best hand, in `eligible` order.
    func showdownWinners() -> [[PlayerID]] {
        pots.map { pot in
            let values = pot.eligible.map { seat($0).flatMap(handValue(of:)) }
            let best = values.compactMap(\.self).max()
            return zip(pot.eligible, values).filter { $0.1 == best }.map(\.0)
        }
    }
}
