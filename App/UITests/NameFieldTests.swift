import XCTest

@MainActor
final class NameFieldTests: XCTestCase {
    override func setUp() async throws {
        continueAfterFailure = false
    }

    func testNameFieldStopsAt32Characters() {
        let app = XCUIApplication.launched()
        let field = app.textFields["playerName"]
        XCTAssertTrue(field.waitForExistence(timeout: 10), "name field not shown")
        field.tap()
        field.clearText()
        field.typeText("abcdefghijklmnopqrstuvwxyz123456")
        // One key at a time: a burst past the limit can outrun the truncation (#154).
        for key in "7890ABCD" { field.typeText(String(key)) }
        XCTAssertEqual(field.value as? String, "abcdefghijklmnopqrstuvwxyz123456")
    }
}
