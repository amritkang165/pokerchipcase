# AGENTS.md

iOS app that replaces the poker chip case for a home Texas Hold'em game, play money only. See [README.md](README.md) for the full description.

## Commands

Run the first four from the repo root before opening a PR; CI runs the same four. The UI tests are local only.

- Lint (`brew install pre-commit`): `pre-commit run --all-files`. CI runs it in the `lint` job.
- Package tests (macOS, no device needed): `swift test`
- Docs (macOS): `xcodebuild docbuild -scheme PokerChipCase-Package -destination 'generic/platform=macOS' -derivedDataPath .build/docs OTHER_DOCC_FLAGS=--warnings-as-errors -quiet`
- App build:

  ```sh
  brew install xcodegen
  xcodegen generate --spec App/project.yml
  xcodebuild build -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'generic/platform=iOS Simulator' -derivedDataPath .build/app CODE_SIGNING_ALLOWED=NO -quiet
  ```

- UI tests (local only, not in CI; run before a PR that touches `App/`), after the app build's `xcodegen generate`:

  ```sh
  xcrun simctl create "SE3 test" "iPhone SE (3rd generation)"  # once, if missing
  xcodebuild test -project App/PokerChipCase.xcodeproj -scheme PokerChipCase -destination 'platform=iOS Simulator,name=SE3 test' -derivedDataPath .build/uitests -resultBundlePath .build/uitests/UITests.xcresult -quiet
  ```

## Layout

- `Sources/PokerCore`: game rules, pots, commands, wire types.
- `Sources/PokerNet`: networking.
- `Sources/PokerSession`: session state and save file.
- `App/Sources`: SwiftUI app. It has no unit tests; `App/UITests` and manual checks in simulators cover it.
- `App/UITests`: XCUITest, run locally in the simulator. XCTest, not Swift Testing: Swift Testing cannot drive UI.
- `Sources/<Target>/<Target>.docc`: DocC catalogs.
- `Tests/<Target>Tests`: Swift Testing, one test target per library.
- `Sources/PokerNet/PokerNet.docc/Protocol.md`: the wire protocol. Update it in the same PR as any wire-format change.

## Rules

- Edit `App/project.yml` for project settings. `App/PokerChipCase.xcodeproj` and `App/Info.plist` are generated and gitignored.
- `App/Config/Local.xcconfig` holds per-developer signing settings and stays local.
- Keep Swift 6 language mode. Fix concurrency errors instead of silencing them.
- Write code, comments, docs, and commits in English.
- Commits follow Conventional Commits with an optional scope, e.g. `fix(app): …`, `refactor: …`, `docs: …`.

## Planning workflow

- Design specs go in `docs/superpowers/specs/YYYY-MM-DD-<topic>.md`.
- Implementation plans go in `docs/superpowers/plans/YYYY-MM-DD-<topic>.md` and are committed before implementation starts.
- `.superpowers/` holds local run state (ledgers, briefs) and stays local.
- An agent-made PR links its spec and plan, or puts the same content in the PR body. Typos, dependency bumps and single-file fixes need neither.
- Deferred review findings become GitHub issues labeled `deferred` plus one of `core`, `net`, `protocol`, `app`, `tooling`.

## Fork pull requests

Fork PRs run CI without secrets, so the SonarCloud scan and issue check are skipped. After review, move the PR to a branch in this repo so it is scanned before it reaches `main`:

```sh
gh pr checkout <N>
git push origin HEAD:contrib/<N>
gh pr create --head contrib/<N> --base main --title "<original title>" --body "Moved from #<N> for the SonarCloud scan."
```

Close the original PR with a link to the new one. The commits keep their author.

## Agent tooling

- `.claude/settings.json` enables the Superpowers and Ponytail plugins for Claude Code, each marketplace pinned to a release tag. Both are optional; install with `claude plugin install superpowers@superpowers-dev --scope project` and `claude plugin install ponytail@ponytail --scope project`.
- A `ponytail:` comment marks a deliberate simplification and names its ceiling and upgrade path. Carry it along when you edit that code; delete it when you do the upgrade.
