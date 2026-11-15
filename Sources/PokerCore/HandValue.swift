/// The strength of a poker hand. Hands compare by ``category``, then by ``ranks``.
public struct HandValue: Comparable, Sendable {
    /// The hand categories, weakest first.
    public enum Category: Int, Comparable, CaseIterable, Sendable {
        /// No combination.
        case highCard
        /// Two cards of one rank.
        case pair
        /// Two pairs.
        case twoPair
        /// Three cards of one rank.
        case threeOfAKind
        /// Five consecutive ranks.
        case straight
        /// Five cards of one suit.
        case flush
        /// Three of one rank and two of another.
        case fullHouse
        /// Four cards of one rank.
        case fourOfAKind
        /// Five consecutive ranks of one suit.
        case straightFlush

        public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The hand's category.
    public let category: Category
    /// Tie-break ranks, most significant first. Straights and straight flushes only hold the top
    /// rank (5 for the wheel); otherwise the distinct ranks ordered by count, then rank, descending.
    public let ranks: [Int]

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.category != rhs.category ? lhs.category < rhs.category : lhs.ranks.lexicographicallyPrecedes(rhs.ranks)
    }

    /// The hand's English name; "Royal flush" for an ace-high straight flush.
    public var name: String {
        switch category {
        case .highCard: "High card"
        case .pair: "Pair"
        case .twoPair: "Two pair"
        case .threeOfAKind: "Three of a kind"
        case .straight: "Straight"
        case .flush: "Flush"
        case .fullHouse: "Full house"
        case .fourOfAKind: "Four of a kind"
        case .straightFlush: ranks == [14] ? "Royal flush" : "Straight flush"
        }
    }
}

/// The best five-card hand among 5 to 7 cards.
public func evaluate(_ cards: [Card]) -> HandValue {
    precondition((5...7).contains(cards.count), "evaluate needs 5 to 7 cards")
    // ponytail: checks all 21 five-card hands of 7 cards; a lookup-table evaluator if this ever shows in a profile
    var best: HandValue?
    var pick: [Card] = []
    func visit(_ from: Int) {
        if pick.count == 5 {
            let v = rank(pick)
            if best == nil || v > best! { best = v }
            return
        }
        guard from < cards.count, pick.count + cards.count - from >= 5 else { return }
        pick.append(cards[from])
        visit(from + 1)
        pick.removeLast()
        visit(from + 1)
    }
    visit(0)
    return best!
}

private func rank(_ hand: [Card]) -> HandValue {
    var counts: [Int: Int] = [:]
    for c in hand { counts[c.rank, default: 0] += 1 }
    let grouped = counts.sorted { ($0.value, $0.key) > ($1.value, $1.key) }
    let ranks = grouped.map(\.key)
    let shape = grouped.map(\.value)
    let flush = Set(hand.map(\.suit)).count == 1
    var straightTop: Int?
    if ranks.count == 5 {
        if ranks[0] - ranks[4] == 4 {
            straightTop = ranks[0]
        } else if ranks == [14, 5, 4, 3, 2] {
            straightTop = 5
        }
    }
    switch (straightTop, flush, shape) {
    case (let top?, true, _): return HandValue(category: .straightFlush, ranks: [top])
    case (_, _, [4, 1]): return HandValue(category: .fourOfAKind, ranks: ranks)
    case (_, _, [3, 2]): return HandValue(category: .fullHouse, ranks: ranks)
    case (_, true, _): return HandValue(category: .flush, ranks: ranks)
    case (let top?, _, _): return HandValue(category: .straight, ranks: [top])
    case (_, _, [3, 1, 1]): return HandValue(category: .threeOfAKind, ranks: ranks)
    case (_, _, [2, 2, 1]): return HandValue(category: .twoPair, ranks: ranks)
    case (_, _, [2, 1, 1, 1]): return HandValue(category: .pair, ranks: ranks)
    default: return HandValue(category: .highCard, ranks: ranks)
    }
}
