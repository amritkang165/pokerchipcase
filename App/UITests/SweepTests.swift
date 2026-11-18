import XCTest

@MainActor
final class SweepTests: XCTestCase {
    /// The table screens skip Dynamic Type and clipping until their fixed layout handles larger text (#153).
    private static let tableAudit = XCUIAccessibilityAuditType.all.subtracting([.dynamicType, .textClipped])

    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testStartScreenWithASavedGame() {
        let table = XCUIApplication.launched(debugTable: true, stop: "lobby")
        // The host save exists once the table screen is up.
        XCTAssertTrue(table.buttons["Table"].waitForExistence(timeout: 30), "table screen not shown")
        table.terminate()
        let app = XCUIApplication.launched()
        XCTAssertTrue(app.buttons["resumeGame"].waitForExistence(timeout: 10), "saved game not offered")
        audit(app, screen: "start")
        app.attachScreenshot("start-saved-game")
    }

    func testStartScreenSweep() {
        let app = XCUIApplication.launched()
        app.waitFor(app.buttons["Create table"], "isEnabled == %@", true, "start screen did not finish loading")
        // Discard every save an earlier test left (host game and seat ticket), so the sweep sees a clean start.
        let discards = app.buttons.matching(NSPredicate(format: "label == %@", "Discard"))
        while discards.count > 0 {
            let count = discards.count
            discards.firstMatch.tap()
            app.waitFor(discards, "count < %@", count, "saved game not discarded")
        }
        XCTAssertFalse(app.buttons["resumeGame"].exists, "saved game still offered")
        app.sweepThemes(screen: "start", auditsSettings: true) { app.navigationBars.buttons["Settings"].tap() }
    }

    func testTurnTableSweep() {
        let app = XCUIApplication.launched(debugTable: true, stop: "turn")
        app.waitForTableStop("turn")
        app.sweepThemes(screen: "table-turn", auditTypes: Self.tableAudit) { Self.openTableSettings(app) }
    }

    func testPayoutTableSweep() {
        let app = XCUIApplication.launched(debugTable: true, stop: "payout", digitalCards: true, fourColorDeck: true)
        app.waitForTableStop("payout")
        app.sweepThemes(screen: "table-payout", auditTypes: Self.tableAudit) { Self.openTableSettings(app) }
    }

    private static func openTableSettings(_ app: XCUIApplication) {
        app.buttons["Table"].tap()
        app.buttons["Settings"].tap()
    }
}
