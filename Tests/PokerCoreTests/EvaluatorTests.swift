import Testing

@testable import PokerCore

private func value(_ text: String) -> HandValue { evaluate(cards(text)) }

@Test func categoriesRankInOrder() {
    let hands = [
        "Ah Kd 9c 7s 3h", "Ah Ad 9c 7s 3h", "Ah Ad 9c 9s 3h", "Ah Ad Ac 7s 3h", "5h 6d 7c 8s 9h",
        "Ah Jh 9h 7h 3h", "Ah Ad Ac 7s 7h", "Ah Ad Ac As 3h", "5h 6h 7h 8h 9h",
    ].map(value)
    #expect(hands.map(\.category) == HandValue.Category.allCases)
    for (lower, higher) in zip(hands, hands.dropFirst()) { #expect(lower < higher) }
}

@Test func kickersDecideWithinACategory() {
    #expect(value("Ah Ad Kc 7s 3h") > value("As Ac Qc 7d 3d"))  // pair: kicker
    #expect(value("Kh Kd 2c 3s 4h") > value("Qh Qd Ac Ks Jh"))  // pair rank before kicker
    #expect(value("Ah Ad 9c 9s Kh") > value("As Ac 9d 9h Qh"))  // two pair: kicker
    #expect(value("3h 3d 3c 2s 2h") > value("2d 2c 2h As Ah"))  // full house: trips first
    #expect(value("Ah Jh 9h 7h 3h") > value("Kd Qd Jd 9d 7d"))  // flush: highest card
    #expect(value("Ah Kd 9c 7s 3h") == value("As Kc 9d 7h 3d"))  // suits never break ties
}

@Test func aceIsLowOnlyInTheWheel() {
    let wheel = value("Ah 2d 3c 4s 5h")
    #expect(wheel.category == .straight && wheel.ranks == [5])
    #expect(wheel < value("2d 3c 4s 5h 6d"))
    #expect(value("Qh Kd Ac 2s 3h").category == .highCard)  // no wrap-around
}

@Test func bestFiveOfSevenIsFound() {
    let royal = value("Ah Kh 2c 3d Qh Jh Th")
    #expect(royal.category == .straightFlush && royal.name == "Royal flush")
    #expect(value("Ah Ad 7c 7d 7h 2s 2c") == value("7c 7d 7h Ah Ad"))
    #expect(value("9h 8h 7h 6h 5h").name == "Straight flush")
}

@Test func boardThatPlaysTies() {
    let board = "Ah Kh Qh Jh Th"
    #expect(evaluate(cards("2c 3d " + board)) == evaluate(cards("9s 9d " + board)))
}

@Test func sevenCardEdgeCases() {
    let fullHouse = value("Ah Ad Ac Kh Kd Kc 2s")
    #expect(fullHouse.category == .fullHouse && fullHouse.ranks == [14, 13])
    for text in ["Ah Ad Kh Kd Qh Qd Js", "Ah Ad Kh Kd Qh Qd 2s"] {
        let twoPair = value(text)
        #expect(twoPair.category == .twoPair && twoPair.ranks == [14, 13, 12])
    }
    let wheelFlush = value("Ah 2h 3h 4h 5h")
    #expect(wheelFlush.category == .straightFlush && wheelFlush.ranks == [5])
    #expect(wheelFlush < value("2h 3h 4h 5h 6h"))
    #expect(value("9h 8h 7h 6d 5c Ah 2h").category == .flush)
    let wheel = value("Ah 2d 3c 4s 5h 5d Kc")
    #expect(wheel.category == .straight && wheel.ranks == [5])
    let quads = value("9h 9d 9c 9s Ah Kd 2c")
    #expect(quads.category == .fourOfAKind && quads.ranks == [9, 14])
}
