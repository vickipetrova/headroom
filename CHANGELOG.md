# Changelog

All notable changes to Headroom are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows
[Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-08-02

First release.

### Added

- **Menu bar title** — `✻ 42% · 67%`: session (5-hour) and weekly utilization, colour-coded green
  under 50%, yellow to 80%, red above. Monospaced digits so the title doesn't shuffle as numbers
  change.
- **Dropdown** with each limit window's percentage, reset time, and a live countdown. Countdowns
  refresh in place while the menu is open.
- **Zero-setup authentication.** Reads the OAuth token Claude Code already holds, from
  `~/.claude/.credentials.json` or the login Keychain. Nothing to paste, no cookies, no DevTools.
- **Per-model weekly limits.** The usage endpoint's `limits` array reports model-scoped windows
  that name their own model, so the third row reads "THIS WEEK (Opus)" or "THIS WEEK (Fable)"
  according to what your plan actually reports. Falls back to the older `five_hour` /
  `seven_day` / `seven_day_opus` keys per field if the array is absent.
- **Colors setting** — *Alerts only* (default) keeps the menu bar and panel calm, colouring only
  once usage passes 50% and again at 80%, so colour carries information instead of being permanently
  on. *System* is fully monochrome and renders the spark as a template image, so the item adapts like
  a built-in menu bar control.
- **Settings submenu** — refresh every 1/5/15 minutes, alert above 50/80/90% or off, colours, launch
  at login. Launch at login delegates to `SMAppService`, so revoking it in System Settings is
  reflected back in the checkmark.
- **Threshold alerts**, at most one per limit window per reset period. Lowering the threshold
  mid-window counts as a new crossing.
- **Honest failure states.** No login found, expired token, and unreachable network each say what
  happened; a failed refresh keeps the last known numbers on screen and timestamps them rather than
  blanking the title.
- **Refresh on wake** from sleep, since timers are unreliable across it.
- `./build.sh` produces a universal (arm64 + x86_64) ad-hoc signed bundle with no Xcode project and
  no third-party dependencies; `--dmg` packages an installer image.

- **The dropdown is a panel, not a greyed-out menu.** Each limit gets a small-caps heading with its
  reset time, the percentage alongside a countdown, and a slim progress bar in Anthropic orange.
  Previously every informational row was a *disabled* menu item, which macOS draws dimmed — so the
  whole panel read as unavailable. Those rows are now custom views, which macOS renders at full
  strength, while the menu itself still supplies the native material, dismissal and ⌘R/⌘Q.
  **Refresh Now** says how old the numbers are — "updated just now", "updated 5m ago" — instead of
  a separate Updated line, so freshness sits next to the thing that acts on it.
- **Tests.** `swift test --disable-xctest` covers endpoint parsing, formatting, alert de-duplication, preference
  validation, credential parsing, and the dropdown's view model. The project builds through SwiftPM (`Package.swift`, no
  third-party dependencies); `build.sh` still produces the universal, ad-hoc-signed `.app`.

### Fixed

Found in a pre-release code review, before first release:

- **Alerts fired on every poll instead of once per window.** The usage endpoint re-stamps
  `resets_at` on every request — three polls twenty seconds apart returned the same reset instant
  with fractional seconds `.516073`, `.880178`, `.202674`. Because the alert marker was keyed on that
  exact timestamp, every poll looked like a fresh period, so anyone over their threshold would have
  been notified twelve times an hour, forever. The period is now quantized to the minute.
- **A leftover credentials file could permanently shadow your live login.** Headroom picked the first
  store that had *anything* in it, so a stale `~/.claude/.credentials.json` — from an older Claude
  Code, a restored backup, or synced dotfiles — hid the Keychain token Claude Code was actively
  refreshing. Every poll failed and the menu advised opening a Claude Code session, which could never
  fix it. Headroom now compares expiry timestamps and uses whichever credential lives longest.
- **"Access denied" was reported as "you've never signed in."** Claude Code's Keychain item only
  trusts the app that created it, so Headroom is prompted for access; declining produced advice that
  couldn't help. It now says what actually happened, and asks once rather than on every poll.
- **The Keychain read could freeze the menu bar.** It ran on the main thread, and it can put a modal
  permission dialog on screen.
- **The bearer token could have followed a redirect to another host.** The connection now refuses
  redirects outright, so "one network destination" is enforced rather than merely documented.
- **A slow refresh could overwrite newer data with older**, timestamped as if it were current.
- **Numbers froze in a dropdown left open.** Percentages and the "Updated" line never changed while
  the menu was on screen, and a countdown would keep running toward a reset time that had already
  been replaced — reaching "now" and staying pinned there until the menu was closed and reopened.
- **A model name reported by the server flowed unbounded into the menu, notifications and stored
  preferences.** It is now trimmed, length-capped, and an empty one no longer renders "THIS WEEK ()".
- **The documented release procedure discarded its own notarization.** It rebuilt the app after
  signing and stapling, replacing both with an ad-hoc signature before packaging the DMG. `build.sh`
  gained `--dmg-only` for that step.
- Tagging a release no longer skips the test suite, and a tag that disagrees with the version in
  `build.sh` now fails the release build instead of shipping a mislabeled app.
- A failed ad-hoc signature is no longer swallowed by the build script — on Apple Silicon that
  produced an app that died at launch with the real error discarded.

Found while building the test suite:

- **A single unrecognized entry in the endpoint's `limits` array discarded every other entry.**
  Casting to an array of a concrete element type checks all elements and yields nothing if one
  fails — so one new field shape would have emptied the whole menu instead of dropping one row.
  This was the likeliest way a real endpoint change would have broken the app.
- **A JSON boolean was read as a number.** `{"percent": true}` showed as 1%, and
  `{"resets_at": false}` as 1 January 1970, because booleans bridge to `NSNumber` and satisfy
  `as? Double`.
- **A huge or non-finite percentage crashed the menu bar.** Converting to `Int` for display traps on
  infinity or anything past `Int`'s range; values are now clamped and checked.
- **Raising the alert threshold re-fired an alert already delivered.** Since changing any setting
  re-polls, clicking around the Settings submenu could produce the same alert several times. Lowering
  the threshold still alerts, as intended.
- **A limit window with no reset time was announced once and then never again**, across relaunches,
  instead of once per period.
- **79.6% displayed as "80%" but didn't trigger the 80% alert.** The alert now compares the same
  rounded number the menu bar shows.
- **The clock and the countdown disagreed at exactly 24 hours**, so the dropdown could read
  "Resets 9:00 AM — in 1d 0h" without the weekday that removes the ambiguity.
- **Reset times kept their old format after a system locale change**, because the date formatters
  were built once at launch.

### Known limitations

- Pro and Max plans only. Metered API-key accounts have no session or weekly quota, and Headroom
  says so instead of showing zeroes.

[0.1.0]: https://github.com/vickipetrova/headroom/releases/tag/v0.1.0
