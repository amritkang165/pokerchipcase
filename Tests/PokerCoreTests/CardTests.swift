import Foundation
import Testing

@testable import PokerCore

@Test func cardStringRoundTrips() throws {
    #expect(Card("Ah") == Card(rank: 14, suit: .hearts))  // memberwise init is internal
    #expect(Card("Tc")?.rank == 10 && Card("2s")?.suit == .spades)
    #expect(Card("Ah")?.description == "Ah")
    let data = try Wire.encoder.encode(cards("Ah Tc 2s"))
    #expect(String(decoding: data, as: UTF8.self) == #"["Ah","Tc","2s"]"#)
    #expect(try Wire.decoder.decode([Card].self, from: data) == cards("Ah Tc 2s"))
}

@Test func invalidCardStringsAreRefused() {
    for text in ["1x", "A", "Ahh", "ah", "AH", ""] { #expect(Card(text) == nil, "\(text)") }
    #expect(throws: DecodingError.self) { try Wire.decoder.decode([Card].self, from: Data(#"["1x"]"#.utf8)) }
}

@Test func fullDeckHas52DistinctCards() {
    #expect(Card.fullDeck.count == 52 && Set(Card.fullDeck).count == 52)
}
