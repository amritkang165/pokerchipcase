extension GameState {
    // The deck cannot run out: a hand uses at most 10 × 2 + 5 = 25 of 52 cards.
    /// Removes and returns the first `count` cards of `deck`.
    mutating func draw(_ count: Int) -> [Card] {
        let cards = Array(deck.prefix(count))
        deck.removeFirst(cards.count)
        return cards
    }
}
