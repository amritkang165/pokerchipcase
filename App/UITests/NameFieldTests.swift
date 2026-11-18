import XCTest

@MainActor
final class NameFieldTests: XCTestCase {
    func testNameFieldStopsAt32Characters() {
        let app = XCUIApplication.launched()
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field not shown")
        field.tap()
        field.clearText()
        field.typeText("abcdefghijklmnopqrstuvwxyz1234567890ABCD")
        XCTAssertEqual(field.value as? String, "abcdefghijklmnopqrstuvwxyz123456")
    }
}
