# CLAUDE.md

Notes for Claude Code sessions working in this repo.

## Build, run, test

```bash
swift test --disable-xctest       # the whole suite, ~0.05s
./build.sh                        # -> build/Headroom.app (universal, ad-hoc signed)
./build.sh --dmg                  # also -> build/Headroom.dmg
open build/Headroom.app
pkill -f "MacOS/Headroom"         # stop it (menu bar app; there's no window to close)
```

`swift run` does not work and is not meant to — it produces a bare binary with no `Info.plist`, so
`LSUIElement`, `SMAppService.mainApp`, and notification registration all misbehave.

There is no Xcode project. SwiftPM compiles the sources and `build.sh` wraps the result in a bundle.

## Architecture

| File | Responsibility |
|---|---|
| `Sources/Headroom/main.swift` | Six lines of top-level code. Top-level code can't live in a library target, so this is all the executable target holds |
| `Sources/HeadroomCore/AppDelegate.swift` | Wires provider → menu, owns the poll timer and the 60s countdown tick, refreshes on wake. The **only** public symbol in the module |
| `Sources/HeadroomCore/MenuController.swift` | The status item: menu bar title, dropdown, Settings submenu. Knows nothing about where usage comes from |
| `Sources/HeadroomCore/UsageAPI.swift` | `LimitWindow` model, `UsageProvider` protocol, `ClaudeProvider` (endpoint client + all response parsing) |
| `Sources/HeadroomCore/Credentials.swift` | Token discovery: credentials file, then login Keychain |
| `Sources/HeadroomCore/Format.swift` | Percentages, countdowns, locale-aware clock times, the colour ramp |
| `Sources/HeadroomCore/Settings.swift` | UserDefaults-backed preferences; launch-at-login proxies `SMAppService` |
| `Sources/HeadroomCore/Notifier.swift` | Threshold alerts, deduplicated per window per reset period |

Everything lives in `HeadroomCore` so the test target can reach it with `@testable`, keeping the
public API to `AppDelegate` alone. `MenuController` renders `[LimitWindow]` and nothing else — that's
what makes adding a second provider one new file, so don't put Claude-specific strings in it.

`Package.swift` pins `swiftLanguageModes: [.v5]`. Swift 6 mode rejects the static mutable state in
`Notifier`; moving to `.v6` means annotating those, not just flipping the line. `platforms:
[.macOS(.v13)]` is load-bearing — it, not the triple, is what pins the deployment target.

## Hard rules

1. **Never print, log, or commit the OAuth token**, or the contents of the credentials file. Not in
   debug output, not in error messages, not in CI. `.github/workflows/build.yml` greps for this.
2. **Zero third-party dependencies.** AppKit, Foundation, Security, UserNotifications,
   ServiceManagement. `Package.swift` has no `dependencies:` array and never should. Tests use
   swift-testing, which ships with the toolchain — **not XCTest**, which is absent from the Command
   Line Tools and would break the CLT-only build contract.
3. **All parsing of the usage endpoint must be defensive.** It is undocumented and it drifts.
   Missing, null, or wrong-typed fields drop that *one* row and render `–`. Never force-unwrap a
   field from the response; never throw on a shape you didn't expect.
4. **`build.sh` signs ad-hoc only.** It must never handle a Developer ID, an app-specific password,
   or notarization credentials. Releasing is a manual maintainer step — see `docs/RELEASING.md`.
5. **One network destination:** `api.anthropic.com`. No analytics, no update checks.

## The response shape

The endpoint returns two overlapping shapes, and `ClaudeProvider.windows(in:)` reads both:

- **Preferred:** a `limits` array of `{kind, percent, resets_at, scope}` where `kind` is `session`,
  `weekly_all`, or `weekly_scoped`. Scoped entries name their own model in
  `scope.model.display_name`, which is why the third row says "THIS WEEK (Fable)" rather than
  hardcoding Opus.
- **Legacy:** top-level `five_hour`, `seven_day`, `seven_day_opus` with `utilization` / `resets_at`.
  Used to fill in anything the array didn't provide, **per field**.

Three traps, each with a regression test — don't "simplify" any of them:

- **Cast `limits` to `[Any]` and filter, never to `[[String: Any]]`.** A conditional cast to an array
  of a concrete element type checks every element and yields nil if one fails, so a single
  unrecognized entry would discard the whole array instead of itself.
- **JSON booleans bridge to `NSNumber`.** `as? Double` on `true` succeeds and gives 1.0, so
  `{"percent": true}` reads as 1% unless the CoreFoundation type id is checked. `as? Bool` is not a
  substitute: `NSNumber(42) as? Bool` also succeeds.
- **Two ISO8601 formatters are required.** Timestamps arrive as
  `2026-08-02T16:39:59.408408+00:00`; `ISO8601DateFormatter` needs `.withFractionalSeconds` for
  those and returns nil without it, and returns nil *with* it for timestamps that lack them.

Values are also clamped to 0–100 and checked for finiteness, because `Fmt.pct` converts to `Int` and
that traps on infinity or anything past `Int`'s range.

## Testing

`swift test --disable-xctest`. Suites live in `Tests/HeadroomCoreTests/`.

Parsing tests feed **JSON text** through `JSONSerialization`, not Swift dictionary literals — values
have to arrive as the `NSNumber`s the real response produces, or the boolean and integer bridging
paths above go untested.

`NotifierTests` and `SettingsTests` reassign `Settings.defaults` / `Notifier.defaults` to a scratch
`UserDefaults` suite, so they sit under one `@Suite(.serialized)` parent. Two things to know before
editing them:

- **No `deinit`.** swift-testing releases the previous suite instance while constructing the next
  one, so a `deinit` restoring those statics overlaps the next `init` writing them and trips Swift's
  exclusivity checking with a `SIGABRT`. Setup happens in `init`, which wipes the scratch domain.
- **`Notifier.deliver` is injected.** `UNUserNotificationCenter.current()` raises an ObjC exception
  in a process with no app bundle — every `swift test` run — and that's an abort, not a catchable
  error, so one stray call kills the whole run with no attribution.

### Never called from a test

Enforced by a CI grep, and worth understanding rather than working around:

- `Credentials.accessToken()` / `tokenFromFile()` / `tokenFromKeychain()` — read the real Keychain
  item and a live OAuth token, and `#expect` prints compared values into CI logs on failure. Only
  `token(in:)` with synthetic bytes is in scope.
- `Settings.launchAtLogin` — the setter registers a real login item pointing at the test binary.
- `ClaudeProvider.fetch` — real network, real token.
- `Notifier.requestAuthorizationIfNeeded()` / `post` — reach `UNUserNotificationCenter`.
- Constructing `MenuController` or `AppDelegate` — `MenuController` creates a real `NSStatusBar`
  status item in a stored-property initializer, so merely existing needs a GUI session.

### Checking the live app

Reading the menu without screenshots:

```bash
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to get name of every menu item of menu 1 of menu bar item 1 of menu bar 1'
```

For error states that the unit tests can't reach (the real 401 path, a dead network with stale data
on screen), copy `Sources/` to a scratch directory, patch the copy, and build a throwaway bundle from
it. **Never delete or rename the `Claude Code-credentials` Keychain item** — that is Claude Code's
live login, not test data.

## Releasing

Bump `VERSION` in `build.sh`, add the entry to `CHANGELOG.md`, tag `vX.Y.Z`. See
`docs/RELEASING.md` for the manual signing and notarization steps.
