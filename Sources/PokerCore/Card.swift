/// A playing card. Travels on the wire as two characters, e.g. `"Ah"`.
public struct Card: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The four suits; the raw value is the suit's character on the wire.
    public enum Suit: String, CaseIterable, Sendable {
        /// Clubs.
        case clubs = "c"
        /// Diamonds.
        case diamonds = "d"
        /// Hearts.
        case hearts = "h"
        /// Spades.
        case spades = "s"
    }

    /// 2 to 14, where 14 is the ace.
    public let rank: Int
    /// The card's suit.
    public let suit: Suit

    private static let ranks = Array("23456789TJQKA")

    /// All 52 cards, clubs to spades, each from deuce to ace.
    public static let fullDeck: [Card] = Suit.allCases.flatMap { suit in
        (2...14).map { Card(rank: $0, suit: suit) }
    }

    init(rank: Int, suit: Suit) {
        self.rank = rank
        self.suit = suit
    }

    /// Parses a rank character from `23456789TJQKA` followed by a suit character from `cdhs`; nil otherwise.
    public init?(_ text: String) {
        let chars = Array(text)
        guard chars.count == 2,
            let r = Self.ranks.firstIndex(of: chars[0]),
            let suit = Suit(rawValue: String(chars[1]))
        else { return nil }
        self.init(rank: r + 2, suit: suit)
    }

    /// The two-character form, e.g. `"Ah"`.
    public var description: String { "\(Self.ranks[rank - 2])\(suit.rawValue)" }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let card = Card(text) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not a card: \(text)"))
        }
        self = card
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(description)
    }
}
