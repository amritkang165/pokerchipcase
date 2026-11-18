import XCTest

@MainActor
final class TableTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testHiddenHoleCardsReadAsHidden() {
        let app = XCUIApplication.launched(debugTable: true, stop: "turn", digitalCards: true)
        app.waitForTableStop("turn")
        let cards = app.descendants(matching: .any)["holeCards"]
        XCTAssertTrue(cards.waitForExistence(timeout: 10), "hole cards not shown")
        XCTAssertEqual(cards.label, "Your cards, hidden")
    }

    func testChipCountsUseTheEnglishFormat() {
        let app = XCUIApplication.launched(debugTable: true, stop: "turn")
        app.waitForTableStop("turn")
        let count = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "1,000")).firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10), "no chip count reads 1,000")
    }
}
