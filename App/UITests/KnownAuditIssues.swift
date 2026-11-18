import XCTest

/// An accessibility audit finding that has a GitHub issue and is skipped until it is fixed.
struct KnownAuditIssue {
    let type: XCUIAccessibilityAuditType
    /// The element's accessibility identifier, or nil for a finding the audit reports without an element.
    let identifier: String?
    /// For a finding without an element: the audited screen it shows on.
    var screen: String?
    /// The GitHub issue that tracks the fix.
    let issue: Int
}

enum KnownAuditIssues {
    static let all: [KnownAuditIssue] = [
        // Settings sheet, audited in the start-screen sweep.
        KnownAuditIssue(type: .contrast, identifier: "fourColorDeck", issue: 142),
        KnownAuditIssue(type: .contrast, identifier: "backPattern", issue: 142),
        KnownAuditIssue(type: .contrast, identifier: nil, screen: "settings", issue: 142),
        KnownAuditIssue(type: .contrast, identifier: "settingsDone", issue: 143),
        KnownAuditIssue(type: .dynamicType, identifier: "settingsDone", issue: 144),
        KnownAuditIssue(type: .dynamicType, identifier: "fourColorDeck", issue: 144),
        KnownAuditIssue(type: .dynamicType, identifier: "backPattern", issue: 144),
        KnownAuditIssue(type: .dynamicType, identifier: "backColorHeader", issue: 144),
        KnownAuditIssue(type: .textClipped, identifier: nil, screen: "settings", issue: 145),
        // Start screen.
        KnownAuditIssue(type: .textClipped, identifier: "playerName", issue: 146),
        KnownAuditIssue(type: .contrast, identifier: "discardGame", issue: 155),
        KnownAuditIssue(type: .dynamicType, identifier: "discardGame", issue: 147),
        KnownAuditIssue(type: .dynamicType, identifier: "nearbyHeader", issue: 147),
        KnownAuditIssue(type: .dynamicType, identifier: "nearbyTable", issue: 147),
        // Shown instead of the rows when no table is nearby; a run without nearby tables fails without it.
        KnownAuditIssue(type: .dynamicType, identifier: "nearbySearching", issue: 147),
        // Table screens (contrast only, see SweepTests.tableAudit).
        KnownAuditIssue(type: .contrast, identifier: "seatName", issue: 148),
        KnownAuditIssue(type: .contrast, identifier: "seatBet", issue: 148),
        KnownAuditIssue(type: .contrast, identifier: "seatStack", issue: 148),
        KnownAuditIssue(type: .contrast, identifier: "nextLevel", issue: 149),
        KnownAuditIssue(type: .contrast, identifier: "stackLabel", issue: 149),
        KnownAuditIssue(type: .contrast, identifier: "toCall", issue: 149),
        KnownAuditIssue(type: .contrast, identifier: "pot", issue: 149),
        KnownAuditIssue(type: .contrast, identifier: "quickPick", issue: 150),
        KnownAuditIssue(type: .contrast, identifier: "cardGlyph", issue: 151),
        KnownAuditIssue(type: .contrast, identifier: "seatCards", issue: 151),
        KnownAuditIssue(type: .contrast, identifier: "winningHands", issue: 152),
        KnownAuditIssue(type: .contrast, identifier: "winners", issue: 152),
        KnownAuditIssue(type: .contrast, identifier: "seatDelta", issue: 152),
    ]

    /// True when `issue`, found on `screen`, is a known finding, so the audit does not fail on it.
    @MainActor
    static func ignores(_ issue: XCUIAccessibilityAuditIssue, on screen: String) -> Bool {
        guard let element = issue.element else {
            return all.contains { $0.type == issue.auditType && $0.identifier == nil && $0.screen == screen }
        }
        // One snapshot reads the identifier in one query; issues often number in the dozens per screen.
        // A failed snapshot of an element that is gone (a nearby table from another parallel test that stopped) is ignored; any other failed snapshot is not.
        guard let snapshot = try? element.snapshot() else { return !element.exists }
        return all.contains { $0.type == issue.auditType && $0.identifier == snapshot.identifier }
    }
}
