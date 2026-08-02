# CLAUDE.md

Notes for Claude Code sessions working in this repo.

## Build and run

```bash
./build.sh                        # -> build/Headroom.app (universal, ad-hoc signed)
./build.sh --dmg                  # also -> build/Headroom.dmg
open build/Headroom.app
pkill -f "MacOS/Headroom"         # stop it (it's a menu bar app; there's no window to close)
```

There is no Xcode project and no package manager. `build.sh` compiles `Sources/*.swift` twice
(arm64 + x86_64), joins them with `lipo`, writes `Info.plist`, and ad-hoc signs the bundle.

## Architecture

| File | Responsibility |
|---|---|
| `Sources/main.swift` | `AppDelegate`: wires provider → menu, owns the poll timer and the 60s countdown tick, refreshes on wake from sleep |
| `Sources/MenuController.swift` | The status item: menu bar title, dropdown, Settings submenu. Knows nothing about where usage comes from |
| `Sources/UsageAPI.swift` | `LimitWindow` model, `UsageProvider` protocol, `ClaudeProvider` (endpoint client + all response parsing) |
| `Sources/Credentials.swift` | Token discovery: credentials file, then login Keychain |
| `Sources/Format.swift` | Percentages, countdowns, locale-aware clock times, the colour ramp |
| `Sources/Settings.swift` | UserDefaults-backed preferences; launch-at-login proxies `SMAppService` |
| `Sources/Notifier.swift` | Threshold alerts, deduplicated per window per reset period |

`MenuController` renders `[LimitWindow]` and nothing else. That's what makes adding a second
provider a matter of writing one file — don't put Claude-specific strings in it.

## Hard rules

1. **Never print, log, or commit the OAuth token**, or the contents of the credentials file. Not in
   debug output, not in error messages, not in CI. `.github/workflows/build.yml` greps for this.
2. **Zero third-party dependencies.** AppKit, Foundation, Security, UserNotifications,
   ServiceManagement. Nothing else, ever.
3. **All parsing of the usage endpoint must be defensive.** It is undocumented and it drifts.
   Missing, null, or wrong-typed fields drop that row and render `–`. Never force-unwrap a field
   from the response; never throw on a shape you didn't expect.
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
  Used to fill in anything the array didn't provide, per field.

Timestamps arrive as `2026-08-02T16:39:59.408408+00:00`. `ISO8601DateFormatter` needs
`.withFractionalSeconds` for those and returns nil without it, and returns nil *with* it for
timestamps that lack them — hence the two formatters. Don't collapse them into one.

## Testing error states

You can exercise every failure path without touching real credentials. **Never delete or rename
the `Claude Code-credentials` Keychain item** — that is Claude Code's live login, not test data.

Copy `Sources/` to a scratch directory, patch the copy, and build a throwaway bundle from it:

- **No credentials found** — point `credentialsPath` and `keychainService` in `Credentials.swift`
  at names that don't exist. Expect `✻ !` and "No Claude Code login found."
- **Expired token (401)** — make `Credentials.accessToken()` return a junk string. Expect `✻ !`
  and "Token expired — open a Claude Code session to refresh it."
- **Network failure with stale data** — let the first `fetch` run for real and fail every later
  one with `UsageError.network`. Expect the title and all rows to *stay*, plus "Can't reach
  api.anthropic.com. Showing data from HH:mm."
- **Odd payloads** — feed dictionaries straight to `ClaudeProvider.windows(in:)`; it's `static` and
  needs no network. Nulls, strings where numbers belong, and unknown `kind` values should each drop
  one row and never crash.

Reading the menu without screenshots:

```bash
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to get name of every menu item of menu 1 of menu bar item 1 of menu bar 1'
```

## Known constraint: notifications

macOS refuses notification registration for ad-hoc signed bundles —
`requestAuthorization` returns `UNErrorDomain` code 1, "Notifications are not allowed for this
application", and the app never appears in System Settings › Notifications. So threshold alerts
cannot be verified from a `./build.sh` build; the menu shows "Alerts blocked" instead. The
threshold logic itself is testable via the persisted markers in `UserDefaults`
(`notified.<window label>` = `<resetTimestamp>|<threshold>`).

## Releasing

Bump `VERSION` in `build.sh`, add the entry to `CHANGELOG.md`, tag `vX.Y.Z`. See
`docs/RELEASING.md` for the manual signing and notarization steps.
