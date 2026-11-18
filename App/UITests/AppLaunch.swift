import XCTest

extension XCUIApplication {
    /// Launches the app in English with the given debug launch arguments.
    @discardableResult
    static func launched(
        debugTable: Bool = false,
        stop: String? = nil,
        digitalCards: Bool = false,
        fourColorDeck: Bool = false,
        playerName: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var args = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if debugTable { args.append("-debugTable") }
        if let stop { args += ["-debugStop", stop] }
        if digitalCards { args += ["-digitalCards", "YES"] }
        if fourColorDeck { args += ["-fourColorDeck", "YES"] }
        if let playerName { args += ["-playerName", playerName] }
        app.launchArguments = args
        app.launch()
        return app
    }
}

extension XCUIElement {
    /// Deletes the current text value, if any.
    func clearText() {
        guard let value = value as? String, !value.isEmpty else { return }
        typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
    }
}
