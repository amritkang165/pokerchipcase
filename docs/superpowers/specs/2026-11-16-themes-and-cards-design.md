# Themes and cards

Give the table depth and material, replace the two appearances with four themes that each have a light and a dark stage, and offer a choice of card faces and card backs. App-only: `PokerCore`, `PokerNet`, `PokerSession` and the wire protocol stay as they are.

## Why

The owner finds the app visually flat and has no Swift or design background, so the look was settled on mockups, not in words. Their complaints, in their words:

- Felt "looks like a leaf in the mud": a flat green circle on flat brown.
- Next to the new felt, the dark theme looks dated.
- The card design, face and back, gets boring quickly.
- There is nothing to personalize except the name.

This spec is stage 1 of four. Later stages, each with its own spec: animation (stage 2), personalization (stage 3), menus (stage 4).

## Reference images

The approved mockups, rendered from HTML. They are the target look; where this text and an image disagree on a color, the hex values here win, and where they disagree on proportions, the image wins.

- `images/2026-11-16-themes.jpg`: the four themes, each light (left) and dark (right).
- `images/2026-11-16-cards.jpg`: five card faces and six card back patterns.

The HTML sources are in `.superpowers/brainstorm/79585-1794858420/content/` (`themes-final.html`, `cards-final.html`), local and not committed.

## Goals

- Four themes: Felt, Neon, Rubin, Royal. Neon replaces today's dark theme.
- Brightness (Light, Dark, System) is its own setting, independent of the theme.
- The table has a wide raised rail, a shadow, lit felt and a betting line.
- Five card faces, six card back patterns in the existing five colors, and a four-color deck switch.
- A fifth theme later costs one set of color values and no new drawing code.

## Non-goals

- Animation, sound and haptics (stage 2).
- The chips. They stay the decorative dots they are today.
- A redesign of start, lobby, ranking and settings beyond what the new tokens force (stage 4). The settings screen gets the new pickers as plain form rows.
- Image or texture assets. Everything is drawn in code.
- Syncing any of these settings. They are per device, like `cardBack` today.
- Drawn court cards (jack, queen, king as figures): not legible at the board's card width.

## Anti-goals

The work has failed, even if it builds, when:

- the table is not a circle. The owner chose round so that a glance at a neighbor's phone shows the same table;
- the table grows or shrinks while a hand is played, or changes size on phones where it already fills the screen width;
- ten seats on an iPhone SE overlap each other, the board or the pot;
- a light stage glares. The light room grounds are mid-tones on purpose, not near-white;
- light and dark of one theme are hard to tell apart.

## Constraints

- iOS 17 deployment target, Swift 6 language mode.
- No unit tests exist for `App/Sources`; the app is checked manually. The owner checks on a real iPhone, with a simulator as second device.
- `-debugTable` fills a table with bots for these checks.

## Approaches

1. **Everything drawn in code** (chosen). Gradients, shadows, strokes and `Canvas`, as table and cards are drawn today. The mockups are built the same way, so the result matches what was approved. A theme is a set of values. Limit: stylized, not photorealistic.
2. **Image assets.** More realistic wood and felt, but it needs artwork for 4 themes × 2 stages × several materials plus 30 card backs, with a license fit for a public repo, and every new theme needs new artwork. Nobody on the project can supply that.
3. **Code plus one tiling grain texture.** Slightly more material feel. It can be added on top of approach 1 later without throwing anything away.

The owner approved approach 1 and left the how to the builder.

## Delivery

Two pull requests, in this order:

1. Themes and table.
2. Cards.

## PR 1: themes and table

### Settings model

- `@AppStorage("theme")`: `felt`, `neon`, `ruby`, `royal`. Default `felt`.
- `@AppStorage("appearance")` keeps its key and becomes the brightness: `light`, `dark`, `system`. Default `system`.
- Migration, once, at app start: a stored `appearance` of `felt` becomes `light`. A stored `dark` stays `dark` and sets `theme` to `neon` if no theme is stored, so people on today's dark theme land on its successor. (Builder's call how; it must not run again after the user picks something.)
- The app root keeps applying `.preferredColorScheme` from the brightness. The theme environment value is resolved from theme name and color scheme, so every theme has two palettes.
- Debug launch arguments: `-theme felt|neon|ruby|royal` and `-appearance light|dark|system`. Update the comment in `DebugBots.swift`.

### Tokens

`Theme` grows from flat colors to what the table needs. Names are the builder's; the values per palette are below.

- room: radial gradient behind the table, three stops, center above the middle.
- felt: radial gradient of the table surface, three stops.
- rail: the ring around the felt, plus its edge line and, for Neon, a glow.
- cushion: a band between felt and rail, color and width.
- line: the betting line on the felt.
- seat fill, seat border, seat text.
- ink: text on the room (header, stack, "To call").
- on-table text: pot and bets.
- accent, text on accent, fold, text on fold.
- card face, card black, card red (as today), used by PR 2.
- screen: the ground of forms and sheets. Use the middle stop of the room.

Today `themedScreen()` forces a dark color scheme for system controls because both grounds are dark. With light stages that is wrong: system controls follow the stage's color scheme.

### Table structure

Same for every theme. All sizes relative to the table diameter `d`, taken from the mockup:

- **Rail:** a ring about `0.105 d` wide, replacing today's 7-point stroke. The outer edge of the table stays where it is, so the felt gets smaller.
- **Seat labels sit on the rail**, at today's seat radius. The felt stays free for board and pot.
- **Felt:** radial gradient, lighter in the middle. An inner shadow where it meets the rail.
- **Cushion:** between felt and rail. `0.01 d` in the felt's darkest tone for Felt, Neon and Rubin; `0.025 d` in crimson for Royal.
- **Betting line:** a thin circle on the felt, diameter about `0.37 d`. Decorative; it may pass behind board and pot.
- **Shadow** under the whole table, toward the bottom.
- **Rail rule:** the rail keeps its material in light and dark. Only room, felt and seat labels change with brightness. The rail is what makes a theme recognizable.

Seat label content, dealer disk, all-in tag, acting ring, showdown marks, board, pot and bets keep their logic and position rules. With digital cards off, bets still sit halfway between seat and center.

### Palettes

Gradients list inner, middle and outer stop. Alpha in percent.

**Felt**: green felt, lacquered wood rail, gold.

| | Light | Dark |
|---|---|---|
| Room | `8fd0c6` `57a9a0` `36877f` | `14555a` `0a3136` `031518` |
| Felt | `5fcf86` `3aa862` `2b8a4e` | `2a8a4f` `145030` `0a2e1b` |
| Cushion | `2a8a50` | `072414` |
| Betting line | `e8c15a` 70 % | same |
| Seat fill / text | `fffcf4` 94 % / `1c2a22` | `020806` 86 % / `f3efe4` |
| Seat border | `3c280a` 25 % | `e8c15a` 30 % |
| Ink | `062522` | `e6f2ee` |
| On-table text | `fffdf6` | `f6f1e4` |
| Accent / on accent | `e8c15a` / `2a1a0c` | same |
| Fold | `c0483a` | `7a2a1f` |

Rail, both stages: an angular gradient through `7a4820` `b9793a` `6a3d1a` `c58a45` `74441e` `b17338` and back to `7a4820`, starting about 20° off the top, under fine concentric grain rings (dark brown, about 20 % alpha, roughly every 3.5 points at mockup scale). A light edge line outside, a highlight along the top inner edge and a shadow along the bottom inner edge make it read as raised.

**Neon**: graphite, glowing mint ring. Replaces the dark theme.

| | Light | Dark |
|---|---|---|
| Room | `c9d1dc` `a2adbe` `7f8ca1` | `141b29` `090c12` `020304` |
| Felt | `f4f6fa` `e3e8f0` `d0d7e2` | `252c3c` `12151e` `090b10` |
| Cushion | `aab3c2` | `05070a` |
| Rail (linear, top-left to bottom-right) | `4a5366` `262c3a` | `252b3a` `0c0e14` |
| Rail edge and glow | `1fd19f`, glow `12b88a` 50 % | `38e1b0`, glow `38e1b0` 65 % |
| Betting line | `12b88a` 55 % | `38e1b0` 45 % |
| Seat fill / text | `ffffff` 95 % / `1a2233` | `04060a` 88 % / `e8eaf0` |
| Seat border | `1a2233` 18 % | `38e1b0` 25 % |
| Ink and on-table text | `1a2233` | `e8eaf0` |
| Accent / on accent | `12b88a` / `ffffff` | `38e1b0` / `06110d` |
| Fold / on fold | `d5dbe6` / `1a2233` | `2a2e3a` / `ffffff` |
| Card face / black / red | `ffffff` / `16181d` / `d63b3b` | `232a3a` / `f1f3f8` / `ff6b6b` |

In Neon the acting seat's ring also glows in the accent.

**Rubin**: red felt, black leather rail with a gold edge.

| | Light | Dark |
|---|---|---|
| Room | `dcc8ad` `bfa684` `a08764` | `2a2c32` `131416` `040405` |
| Felt | `ee6f6a` `d04a4a` `b23638` | `a83236` `651519` `3a0a0e` |
| Cushion | `b23638` | `2a070a` |
| Betting line | `e8c15a` 75 % | same |
| Seat fill / text | `fffcf6` 94 % / `3a1c1c` | `080304` 88 % / `f3efe4` |
| Seat border | `782828` 25 % | `e8c15a` 30 % |
| Ink | `3a1c1c` | `f3efe6` |
| On-table text | `fffdf8` | `f6f1e4` |
| Accent / on accent | `e8c15a` / `2a1a0c` | same |
| Fold | see open points | `3c3f46` |

Rail, both stages: linear `2b2b2e` `0c0c0d` `2a2a2d`, gold edge line `e8c15a` about 85 %.

**Royal**: blue felt, chrome rail, crimson cushion, gold line.

| | Light | Dark |
|---|---|---|
| Room | `b9c9e1` `8ea5c7` `6b85ac` | `232a3c` `0f131c` `030407` |
| Felt | `86b6f7` `5b93e6` `3f78cf` | `2f69c4` `163c7c` `0b2149` |
| Cushion (`0.025 d`) | `b3243a` | `8e1b2e` |
| Rail (angular, alternating) | `9aa0aa` `e9ecf0` `888e98` `f4f6f8` `9298a2` `dde0e5` | `5d626b` `b9bdc4` `4e535b` `c6cad0` `585d66` `a9adb5` |
| Betting line | `f5d682` 90 % | `e8c15a` 70 % |
| Seat fill / text | `ffffff` 95 % / `14234a` | `030710` 88 % / `f3efe4` |
| Seat border | `14234a` 20 % | `ffffff` 22 % |
| Ink | `14234a` | `eef1f8` |
| On-table text | `ffffff` | `f6f1e4` |
| Accent / on accent | `1f4e9c` / `ffffff` | `f2f4f7` / `14234a` |
| Fold | `c0483a` | `6a2530` |

Royal's chrome is the one exception to the rail rule in value, not in material: the owner approved a dimmer chrome for the dark stage.

Felt, Rubin and Royal use the cream card face `f6efdf`, black `16181d` and red `c0392b` in both stages.

### Table size on small phones

Added after the owner compared four sizes on an iPhone SE and an iPhone 17 Pro Max (mockup `table-size-v3.html`, local) and picked a larger table on the SE, with seat labels that keep their share of the table.

- `RoundTable` reserves 300 points for the rest of the screen instead of 338: `max(height * 0.43, height - 300)`. The seat label width stays `0.215` of the table.
- On an iPhone SE this makes the table 303 instead of 265 points. Phones where the table already fills the screen width do not change.
- The 38 points came from the slack below "To call". The tallest rest of the screen, a real-cards hand with the dealer banner and the raise slider, must still fit on the SE without the table changing size: first shrink the large stack number while the dealer banner shows, then, if that is not enough, make the banner more compact. The builder measures this in the simulator.

### Theme settings

Two rows replace the "Felt / Dark / System" picker:

- Theme: the four themes.
- Brightness: a segmented "Light / Dark / System".

### Other places

- `README.md` names "Felt, Dark and System appearance" and shows `docs/images/table.png` and `dark.png`. Update the sentence and both screenshots.
- `RankingView` and every `themedScreen()` caller pick up the new tokens. They must stay readable in all eight palettes; nothing more is asked of them here.

## PR 2: cards

### Faces

`@AppStorage("cardFace")`, default `classic`. See `images/2026-11-16-cards.jpg`.

| Value | Look |
|---|---|
| `centered` | today's face: rank above suit, centered |
| `classic` | rank and small suit as an index top left, one large suit bottom right |
| `jumbo` | rank at about 0.56 of the card width top left, large suit bottom right, no small suit |
| `solid` | the whole card filled in the suit's color, white rank top left, the suit as a large pale mark bottom right, running off the card |

`@AppStorage("fourColorDeck")`, default off. On: diamonds blue (`1f5fbf`), clubs green (`1b7a40`). It applies to every face. Off: diamonds red, clubs black.

The `solid` fills are fixed in every theme: spades `3a3f4b`→`16181d`, hearts `e0584a`→`a82a1f`, diamonds `4a8be0`→`1f4e9c`, clubs `3fb06a`→`1b6f3c`, as diagonal gradients. With the four-color switch off, diamonds take the hearts fill and clubs the spades fill.

Faces must be readable at every width in use: 22 (settings), about 32 (board), 44 (ranking), 50 (hole cards). "10" is the widest rank. Cards get a soft drop shadow.

`CardsText` (inline `A♥ K♠`) follows the four-color switch and nothing else.

VoiceOver labels do not change.

### Backs

`@AppStorage("cardBackPattern")`, default `medallion`. The existing `@AppStorage("cardBack")` keeps the color (five colors, default red). Any pattern combines with any color.

| Value | Look |
|---|---|
| `lattice` | today's diamond lattice |
| `medallion` | a finer lattice, a ring and a spade in the center |
| `rays` | rays from the center, a small disk in the middle |
| `stripes` | diagonal stripes |
| `dots` | a staggered dot grid |
| `monogram` | a soft diagonal sheen, a gold inner frame and the first letter of the player's name in gold serif |

The monogram letter is the first character of `@AppStorage("playerName")`, trimmed and uppercased. With an empty name it shows a spade.

All patterns keep today's white inner frame, except `monogram` with its gold one.

### Card settings

Plain form rows with a live preview of two cards and a back:

- Card face (four values).
- Four-color deck (toggle).
- Card back pattern (six values).
- Card back color (five values, as today).

## Later

Chosen by the owner for a later stage, not part of PR 1 or PR 2:

- **Blind clock on large iPhones.** Where the screen leaves room below "To call" (an iPhone 17 Pro Max has about 90 points), show a bar with the time gone in the current level, the time left, and the next two levels. Phones without the room show the header as today. Mockup `big-phone-space-v3.html`, option C, local.
- **The area is configurable** (owner's request). A per-device setting picks what fills it: blind clock (default), best hand, or nothing. Best hand shows the viewer's best hand from hole cards and board with the five cards that make it (mockup option B); in a game without digital cards it falls back to the blind clock (confirmed by the owner). Phones without the room do not show the setting.

## Decisions made while writing

These are the author's calls, not the owner's. None was shown to the owner in a mockup.

- **No screen keeps a hard-dark ground.** Forms, sheets and the navigation bar use the stage's `screen` ground and the stage's color scheme. Remove the forced `.dark` in `ThemedScreen`.
- **Tokens the tables do not list:**
  - `muted`: the palette's ink at about 65 % alpha. It must reach WCAG AA on room and screen; raise the alpha where it does not.
  - `chips`: Felt, Rubin and Royal keep `c0392b` `2c3e50` `27ae60`. Neon keeps `38e1b0` `5b6cff` `ff9f68`.
  - `cardFrame`: white on card backs in every palette. Card faces lose their edge stroke in favor of the drop shadow, except Neon dark, which keeps `3a3f4d`. The empty board slot uses the on-table text color at 25 %.
  - `formTint`: the accent where it is readable on the system material of that color scheme, else a darker or lighter shade of it.
- **Geometry.** `d` is the diameter of the circle `RoundTable` draws today, after its padding. The rail lies inside that circle. Seat centers stay on today's radius; do not move them to center them on the rail. Where the text leaves a proportion open, measure the image.
- **Seat states.** A folded seat stays at 0.4 opacity, a picked winner keeps the accent fill at 0.35, and the acting ring keeps its pulse. Neon adds the glow on top.
- **Angular gradients** use evenly spaced stops. A visual pass against the image is the check.
- **Migration** runs in `App.init` on `UserDefaults.standard`, before any `@AppStorage` read. It runs when the `theme` key is absent and always writes `theme`, so that key is the marker. A stored `system` lands on Felt.
- **Suits are font glyphs**, clipped by the card shape.
- **Four-color deck on Neon dark's dark faces:** diamonds `6aa5ff`, clubs `4cc47a`.
- **Monogram** shows the device owner's own letter. Only the own hole cards are ever drawn face down, so nothing goes over the wire.
- **README screenshots:** the builder makes them in a simulator with `-debugTable`. `table.png` shows Felt light; `dark.png` is replaced by a Neon dark shot.

## Open points, the builder's call

- **Rubin light fold button.** The mockup's gray `8a8d95` looks disabled. Use a muted red that still reads as "fold" next to the gold accent, e.g. `8e2f2a`.
- **Neon light.** The table is lighter than the room there and the mint glow is weak. Approved as shown; if it looks washed out on a device, darken the room before touching the table.
- **Text on accent and on fold** must reach WCAG AA contrast in all eight palettes. Adjust the text color, not the accent, if one does not.
- **Betting line and felt size on a small phone with ten seats.** If board or pot touch the rail on an iPhone SE, narrow the rail down to no less than `0.08 d` before changing anything else.
- **Grain rings on the wood rail** may be dropped at sizes where they alias.
- **Theme and card pickers** may show a small swatch per row.

## Checks

Automated, as in `AGENTS.md`: `pre-commit run --all-files`, `swift test`, the docs build, the app build.

Manual, on an iPhone and an iPhone SE simulator, with `-debugTable`:

- All eight palettes at 2, 6 and 10 seats: nothing overlaps, every text is readable.
- Digital cards on and off.
- Brightness on System follows the device.
- Start, lobby, ranking, settings and a system alert are readable in all eight palettes.
- Upgrade from a build with `appearance` stored as `felt`, `dark` and `system`.
- Every face at board and hole-card size, four-color on and off, in a cream-card theme and in Neon dark.
- Every back pattern in every color; monogram with a name and with an empty name.
