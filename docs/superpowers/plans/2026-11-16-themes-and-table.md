# Themes and Table Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Four themes (Felt, Neon, Rubin, Royal), each with a light and a dark palette picked by an independent brightness setting, and a table drawn with a wide rail, cushion, lit felt, betting line and shadow.

**Architecture:** `Theme` stays a value in the SwiftUI environment. It is now resolved from two stored settings, theme name and brightness, as `ThemeName.palette(for: ColorScheme)`. The table's ground is drawn by one new view, `TableSurface`, from tokens only, so a new theme is two palettes and no drawing code.

**Tech Stack:** SwiftUI, iOS 17, Swift 6 language mode. No assets, no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-16-themes-and-cards-design.md`. This plan covers its "PR 1: themes and table". "PR 2: cards" gets its own plan. Reference image: `docs/superpowers/specs/images/2026-11-16-themes.jpg`.

## Global Constraints

- App-only. `Sources/PokerCore`, `Sources/PokerNet`, `Sources/PokerSession` and the wire protocol are not touched.
- iOS 17 deployment target. Swift 6 language mode; fix concurrency errors, do not silence them.
- Everything is drawn in code. No image or texture assets.
- The table stays a circle. Its size rule in `RoundTable` (`max(height * 0.43, height - 338)`) and `seatPoint` do not change, except in Task 4, which changes 338 to 300.
- Chips keep their drawing. No animation changes.
- Settings are per device and never synced.
- All colors come from the palette tables in the spec, copied exactly. "Alpha in percent" there means `.opacity()`.
- Code, comments and commits in English. Conventional Commits, scope `app`.
- `App/project.yml` is the source of project settings; it globs `App/Sources`, so new files need `xcodegen generate --spec App/project.yml` and nothing else.
- Carry existing `ponytail:` comments along when editing the code they sit on.
- Work on branch `feat/themes-and-table`.

Build check used by every task:

```sh
xcodegen generate --spec App/project.yml
xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
```

Expected: no output, exit 0.

Screenshot check used by tasks 2 and 3 (simulators `SE3 test` and `iPhone 17 test` exist and stay; take the bundle id from `App/Config/App.xcconfig`):

```sh
xcrun simctl install "SE3 test" .build/app/Build/Products/Debug-iphonesimulator/PokerChipCase.app
xcrun simctl terminate "SE3 test" <bundle-id>
xcrun simctl launch "SE3 test" <bundle-id> -debugTable -debugStop turn -playerName Du -theme felt -appearance light
sleep 45
xcrun simctl io "SE3 test" screenshot <scratch>/felt-light-se.png
```

`-debugTable` seats 10 players. Read each screenshot before calling a step done.

## Review Focus

1. **Ten seats on an iPhone SE.** Seat labels now sit on a wide rail and the felt is smaller. Expected: no label overlaps a neighbor, the board or the pot. Pinned in Task 2, step 6.
2. **Upgrade from the old `appearance` values.** `felt`, `dark` and `system` are stored on real devices; `felt` is no longer a valid raw value. Expected: `felt` lands on Felt light, `dark` on Neon dark, `system` on Felt following the device, and a later choice is never overwritten. Pinned in Task 1, steps 1 and 2.
3. **Brightness on System changing while a table is open.** Expected: room, felt, seat labels and navigation bar switch together, with no screen left in the other palette. Pinned in Task 3, step 4.
4. **Muted text and system controls on the light grounds.** Until now every ground was dark and `themedScreen()` forced dark controls. Expected: section headers, "To call", pickers, text fields, alerts and dialogs are readable in all four light palettes. Pinned in Task 3, steps 2 and 3.
5. **A long name in a seat label on the rail.** Expected: it shrinks or truncates inside the label as today, in light and dark seat fills. Pinned in Task 2, step 6 (the debug bots include "Maximilian-Alexander").

## File Structure

- `App/Sources/Theme.swift` (modify): `ThemeName`, `Appearance`, the `Theme` struct, the migration, the view modifiers, `ThemeButtonStyle`.
- `App/Sources/ThemePalettes.swift` (create): the eight palettes and `ThemeName.palette(for:)`. Values only.
- `App/Sources/TableSurface.swift` (create): room background and the table's ground (shadow, rail, cushion, felt, line).
- `App/Sources/RoundTable.swift` (modify): use `TableSurface`, new seat tokens.
- `App/Sources/TableView.swift`, `TableScreen.swift`, `SettingsView.swift`, `PokerChipCaseApp.swift`, `DebugBots.swift`, `CardViews.swift` (modify): callers.
- `README.md`, `docs/images/table.png`, `docs/images/dark.png` → `docs/images/neon.png`.

---

### Task 1: Theme model, palettes, migration, settings

After this task the app builds and all eight palettes can be picked. The table still has its old shape, colored from the new tokens.

**Files:**

- Modify: `App/Sources/Theme.swift`
- Create: `App/Sources/ThemePalettes.swift`
- Modify: `App/Sources/PokerChipCaseApp.swift`, `App/Sources/SettingsView.swift`, `App/Sources/DebugBots.swift:31-32`, `App/Sources/CardViews.swift:183-203` (preview), `App/Sources/RoundTable.swift:39-40,218`, `App/Sources/TableView.swift:54-60`

**Interfaces:**

- Produces:

```swift
enum ThemeName: String, CaseIterable { case felt, neon, ruby, royal
    var label: String              // "Felt", "Neon", "Rubin", "Royal"
    func palette(for scheme: ColorScheme) -> Theme   // .dark gives the dark palette, anything else light
}

enum Appearance: String, CaseIterable { case light, dark, system
    var label: String              // "Light", "Dark", "System"
    var colorScheme: ColorScheme?  // .light, .dark, nil
    /// One-time move from the old "felt/dark/system" setting. Call before any @AppStorage read.
    static func migrate(in defaults: UserDefaults)
}

struct Rail: Sendable {
    enum Fill: Sendable { case angular([Color], start: Angle), linear([Color]) }
    var fill: Fill
    var edge: Color      // thin line on the rail's outer edge
    var glow: Color?     // Neon only
    var grain: Bool      // Felt only
}

struct Theme: Sendable {
    var room: [Color]          // 3 stops, inner to outer
    var background: Color      // room[1]; flat fills: nav bar, banner
    var screen: Color          // room[1]; forms and sheets
    var surface: [Color]       // felt, 3 stops
    var rail: Rail
    var cushion: Color
    var cushionWidth: CGFloat  // fraction of the table diameter: 0.01, Royal 0.025
    var line: Color            // betting line
    var seat: Color
    var seatBorder: Color
    var seatText: Color
    var text: Color            // "ink": text on the room
    var onTable: Color         // pot and bets
    var muted: Color
    var accent: Color
    var onAccent: Color
    var formTint: Color
    var fold: Color
    var onFold: Color
    var chips: [Color]
    var cardFrame: Color, cardFace: Color, cardText: Color, cardRed: Color
}
```

`rim` is removed. `Color(hex:)` becomes internal so `ThemePalettes.swift` can use it.

- [ ] **Step 1: Write the migration with its self-check**

`Appearance.migrate(in:)` in `Theme.swift`. Rules: return when `defaults.object(forKey: "theme") != nil`. Otherwise read `defaults.string(forKey: "appearance")`: `"felt"` writes `appearance = "light"` and `theme = "felt"`; `"dark"` writes `theme = "neon"`; anything else writes `theme = "felt"`.

The app target has no test target, so the check is a debug self-check next to the function, called once from `App.init` under `#if DEBUG`, on a scratch suite (`UserDefaults(suiteName:)`, removed afterwards with `removePersistentDomain`):

```swift
// stored appearance -> (appearance, theme) after migrate
for (old, appearance, theme) in [("felt", "light", "felt"), ("dark", "dark", "neon"), ("system", "system", "felt"), (nil, nil, "felt")] { … assert … }
// a stored theme is never overwritten
defaults.set("dark", forKey: "appearance"); defaults.set("royal", forKey: "theme")
Appearance.migrate(in: defaults); assert(defaults.string(forKey: "theme") == "royal")
```

- [ ] **Step 2: Call it at launch**

`PokerChipCaseApp.init()` calls `Appearance.migrate(in: .standard)` before anything else, then the self-check in debug builds. Add `@AppStorage("theme") private var themeName = ThemeName.felt`.

- [ ] **Step 3: Write the eight palettes**

`ThemePalettes.swift`: `ThemeName.palette(for:)` returning one of eight private static `Theme` values. Copy every value from the spec's tables "Felt", "Neon", "Rubin", "Royal" and from "Decisions made while writing" (`muted`, `chips`, `cardFrame`, `formTint`). Fixed choices the tables leave open:

- `background` and `screen`: the middle room stop.
- `onFold`: `ffffff`, except Neon light `1a2233`.
- Rubin light `fold`: `8e2f2a`.
- `muted`: `text.opacity(0.65)`.
- `formTint`: the accent; where the accent is a light color on a light stage or a dark one on a dark stage, the palette's `text`.
- Felt rail: `.angular([7a4820, b9793a, 6a3d1a, c58a45, 74441e, b17338, 7a4820], start: .degrees(20))`, edge `ffe1aa` at 55 %, `grain: true`.
- Neon rail: `.linear` with the two stops per stage, edge and glow per stage.
- Rubin rail: `.linear([2b2b2e, 0c0c0d, 2a2a2d])`, edge `e8c15a` at 85 %.
- Royal rail: `.angular` with the six stops per stage plus the first repeated, `start: .degrees(30)`, edge `ffffff` at 70 %.

- [ ] **Step 4: Resolve the theme at the root and stop forcing dark controls**

In `Theme.swift`: `Themed` reads `@AppStorage("theme")` and `@Environment(\.colorScheme)` and sets `themeName.palette(for: scheme)`. `ThemedScreen` loses `.toolbarColorScheme(.dark, …)` and `.environment(\.colorScheme, .dark)`. `ThemeButtonStyle` takes its label colors from `onAccent` and `onFold`. The default environment value is `ThemeName.felt.palette(for: .light)`.

- [ ] **Step 5: Fix the callers so it builds**

- `RoundTable.swift:39-40`: the stroke uses `theme.cushion` for now (Task 2 replaces both lines). Line 218: tag text uses `theme.onAccent`.
- `TableView.swift:57-60`: drop the "dark in both themes" comment and `.toolbarColorScheme(.dark, for: .navigationBar)`.
- `CardViews.swift` preview: iterate `ThemeName.felt.palette(for: .light)` and `ThemeName.neon.palette(for: .dark)`.
- `DebugBots.swift:32`: the comment reads "Combine with `-playerName Du`, `-theme felt|neon|ruby|royal` and `-appearance light|dark|system`."

- [ ] **Step 6: Settings rows**

`SettingsView`: replace the appearance picker with two rows in one section: `Picker("Theme", selection: $themeName)` over `ThemeName.allCases` (default menu style) and the segmented `Picker("Brightness", selection: $appearance)` over `Appearance.allCases`.

- [ ] **Step 7: Build**

Run the build check. Expected: no output, exit 0.

- [ ] **Step 8: Run once in a simulator**

Launch with `-debugTable -debugStop lobby -theme royal -appearance dark` on `SE3 test`. Expected: no assertion failure from the self-check, the lobby shows on the Royal dark ground.

- [ ] **Step 9: Commit**

```bash
git add App/Sources
git commit -m "feat(app): four themes with a separate brightness setting"
```

---

### Task 2: Table surface

**Files:**

- Create: `App/Sources/TableSurface.swift`
- Modify: `App/Sources/RoundTable.swift`, `App/Sources/TableView.swift:54-58`

**Interfaces:**

- Consumes: `Theme` and `Rail` from Task 1.
- Produces:

```swift
/// The table's ground: shadow, rail, cushion, felt and betting line. Fills the circle inscribed in its frame.
struct TableSurface: View { init() }

/// The room behind the table: the theme's radial gradient, centered above the middle.
struct RoomBackground: View { init() }
```

- [ ] **Step 1: Draw `TableSurface`**

All sizes from the frame's diameter `d`, outside in:

| Layer | Size | Look |
|---|---|---|
| Shadow | under the whole disk | black, about 60 % in dark palettes and 35 % in light ones, radius `0.07 d`, offset down `0.04 d` |
| Rail | ring, `0.105 d` wide | `rail.fill`; `.angular` is an `AngularGradient` with evenly spaced stops from `start`, `.linear` runs top-leading to bottom-trailing |
| Rail edge | 1 pt stroke on the outer edge | `rail.edge` |
| Rail glow | Neon only | `rail.glow` as a shadow of radius `0.07 d` around the disk |
| Rail grain | Felt only | concentric circles across the rail, `2a1204` at 20 %, 1 pt wide, about every `0.0175 d`; drop them when that spacing is under 2.5 pt |
| Rail relief | Felt, Rubin, Royal | a light highlight on the upper half of the rail and a dark shade on the lower half, so it reads as raised |
| Cushion | ring inside the rail, `theme.cushionWidth * d` | `theme.cushion` |
| Felt | the rest | `RadialGradient` of `theme.surface`, centered at 42 % of the height, plus a soft dark inner shadow along its edge |
| Betting line | circle, diameter `0.37 d`, 1.5 pt | `theme.line` |

The whole view is decoration: `.accessibilityHidden(true)`. Add a `#Preview` that shows all eight palettes in a grid.

- [ ] **Step 2: Draw `RoomBackground`**

`RadialGradient(colors: theme.room, center: UnitPoint(x: 0.5, y: 0.38), …)` reaching the screen's corners, `.ignoresSafeArea()`.

- [ ] **Step 3: Use them**

- `RoundTable.swift:38-41`: `TableSurface().padding(seatWidth(in: size) / 2 - 8)` replaces the filled, stroked circle. The padding is unchanged, so the outer edge stays where it was.
- `TableView.swift:55`: `.background { RoomBackground() }`. The navigation bar keeps `theme.background`.

- [ ] **Step 4: Seat labels and on-table text**

In `RoundTable`:

- `seatLabel`: text `theme.seatText`; the idle border (`.normal`, `.dimmed`) is `theme.seatBorder`, not `.clear`. Picked winner, selectable, folded opacity and the acting ring's pulse stay as they are. In palettes with a `rail.glow`, the acting ring also gets a shadow in `theme.accent`.
- Pot, bets on the felt and `winnerLines`: `theme.onTable`. A bet shown inside a seat label (digital games) keeps the seat text color.
- The side-pot line under the pot: `theme.onTable.opacity(0.7)`, not `theme.muted`, which is tuned for the room.
- `CardSlotView` (in `CardViews.swift`): stroke `theme.onTable.opacity(0.25)`.

- [ ] **Step 5: Build**

Run the build check. Expected: no output, exit 0.

- [ ] **Step 6: Check ten seats on the SE in all eight palettes**

Run the screenshot check on `SE3 test` for each of the eight `-theme`/`-appearance` pairs with `-debugStop turn`, and once more for Felt light with digital cards off if the debug table deals digital cards by default. Read every screenshot. Expected in each:

- no seat label overlaps a neighbor, the board or the pot;
- the long bot name stays inside its label;
- the rail matches the reference image in width and material;
- pot and board are readable on the felt.

If board or pot touch the rail, narrow the rail, to no less than `0.08 d`, and change nothing else.

- [ ] **Step 7: Check one tall phone**

Same for Felt light and Neon dark on `iPhone 17 test`. Expected: the larger table keeps the same proportions.

- [ ] **Step 8: Commit**

```bash
git add App/Sources
git commit -m "feat(app): table with rail, cushion, lit felt and betting line"
```

---

### Task 3: Other screens, README

**Files:**

- Modify: whichever of `App/Sources/StartView.swift`, `LobbyView.swift`, `RankingView.swift`, `ShowdownView.swift`, `ActionBar.swift`, `HostMenu.swift`, `TableScreen.swift`, `Theme.swift`, `ThemePalettes.swift` the checks below fail on
- Modify: `README.md:7-11,33`
- Replace: `docs/images/table.png`; delete `docs/images/dark.png`, create `docs/images/neon.png`

**Interfaces:**

- Consumes: everything from Tasks 1 and 2. Produces nothing new.

- [ ] **Step 1: Contrast of fixed pairs**

For all eight palettes, compute the WCAG contrast ratio of: `onAccent` on `accent`, `onFold` on `fold`, `muted` on `screen`, `text` on `screen`, `seatText` on `seat` over the rail's darkest and lightest stop. A throwaway script is fine; do not commit it. Expected: at least 4.5 for every pair. Where one fails, change the text-side value in `ThemePalettes.swift` (for `muted`, raise the opacity), not the accent or the ground.

- [ ] **Step 2: Forms in a light palette**

Launch on `SE3 test` without `-debugTable`, with `-theme felt -appearance light`, then `-theme neon -appearance light`. Screenshot the start screen and, after `-debugTable -debugStop lobby`, the lobby. Expected: section headers, row text, the name field, buttons and the navigation title are readable; rows are distinguishable from the ground. `themedRow()` uses `theme.seat`; if a light seat fill makes rows vanish or text unreadable there, fix it in `ThemedRow` or the palette, once, not per screen.

- [ ] **Step 3: Table-screen extras in a light and a dark palette**

With `-debugTable` and `-debugStop showdown`, then `payout`, for Rubin light and Royal dark: screenshot. Expected: the showdown bar, the ranking sheet, the dealer banner and the action bar's slider and quick picks are readable. Open the table menu's leave dialog by hand once in a light palette. Expected: the dialog's buttons are readable on the system material (`formTint`).

- [ ] **Step 4: Brightness on System, live**

Launch `-debugTable -debugStop turn -theme felt -appearance system`. Toggle with `xcrun simctl ui "SE3 test" appearance dark`, screenshot, then `light`, screenshot. Expected: room, felt, seat labels, navigation bar and status bar switch together both ways.

- [ ] **Step 5: README**

- `docs/images/table.png`: Felt light, `-debugStop turn`, `iPhone 17 test`. `docs/images/neon.png`: Neon dark with digital hole cards, replacing `dark.png`. Keep the existing image width and update both `alt` texts.
- Line 33 becomes: "Four themes (Felt, Neon, Rubin, Royal), each light or dark, and a choice of card backs".

- [ ] **Step 6: Full gate**

```sh
pre-commit run --all-files
swift test
xcodebuild docbuild -scheme PokerChipCase-Package -destination 'generic/platform=macOS' -derivedDataPath .build/docs OTHER_DOCC_FLAGS=--warnings-as-errors -quiet
```

plus the build check. Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add App/Sources README.md docs/images
git commit -m "feat(app): readable screens in every palette, new screenshots"
```

---

### Task 4: Larger table on small phones

Added after Tasks 1-3 were planned; see the spec section "Table size on small phones".

**Files:**

- Modify: `App/Sources/RoundTable.swift:70-76`, `App/Sources/TableView.swift:26-46`

**Interfaces:**

- Consumes: nothing new.

- [ ] **Step 1: Change the reserve**

`RoundTable.swift:76`: `max(height * 0.43, height - 300)`. Rewrite the comment above it: 300 points stay for the rest of the screen; on an iPhone SE the stack number shrinks while the dealer banner shows, so the table keeps its size.

- [ ] **Step 2: Find the tallest case on the SE**

Launch on `SE3 test` with `-debugTable -debugStop turn -playerName Du -digitalCards NO -theme felt -appearance light` (Du is the dealer at the first hand, so the dealer banner shows; it is Du's turn, so the raise slider shows). Screenshot and read it. Expected before the fix: the action bar or the quick picks are pushed below the screen or overlap the stack block.

- [ ] **Step 3: Fit it**

In `TableView`, while the dealer banner shows, the large stack number uses a smaller font. Pick the largest size that fits on the SE in step 2's case. If even 24 points do not fit, also make the banner a single compact line. The table must not change size between a hand with and without the banner: compare the table's position in two screenshots, one with `-digitalCards NO` (banner) and one with `-digitalCards YES` (no banner, hole cards).

- [ ] **Step 4: Check**

Build check, then on `SE3 test`: the step 2 case, the same with `-digitalCards YES`, and `-debugStop showdown`. Expected: nothing overlaps, nothing is cut off, ten seats do not overlap each other, the board or the pot. On `iPhone 17 test`: Felt light `-debugStop turn`. Expected: the table looks exactly as before this task.

- [ ] **Step 5: Commit**

```bash
git add App/Sources
git commit -m "feat(app): larger table on small phones"
```

---

## Pull request

Title: `feat(app): four themes with light and dark, table with a rail`. The body links the spec and this plan and carries these boxes. Automatic gates ticked once they pass; the manual ones stay unticked for the owner, who checks on a real iPhone:

- [ ] Each theme in Light and Dark at a real table looks like the reference image
- [ ] Brightness on System follows the iPhone
- [ ] Upgrade over an installed build keeps a sensible theme
- [ ] Start, lobby, ranking, settings and an alert are readable in a light palette
