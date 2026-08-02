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
- **Settings submenu** — refresh every 1/5/15 minutes, alert above 50/80/90% or off, launch at
  login. Launch at login delegates to `SMAppService`, so revoking it in System Settings is
  reflected back in the checkmark.
- **Threshold alerts**, at most one per limit window per reset period. Lowering the threshold
  mid-window counts as a new crossing.
- **Honest failure states.** No login found, expired token, and unreachable network each say what
  happened; a failed refresh keeps the last known numbers on screen and timestamps them rather than
  blanking the title.
- **Refresh on wake** from sleep, since timers are unreliable across it.
- `./build.sh` produces a universal (arm64 + x86_64) ad-hoc signed bundle with no Xcode project and
  no third-party dependencies; `--dmg` packages an installer image.

- **Tests.** `swift test` covers endpoint parsing, formatting, alert de-duplication, preference
  validation, and credential parsing. The project builds through SwiftPM (`Package.swift`, no
  third-party dependencies); `build.sh` still produces the universal, ad-hoc-signed `.app`.

### Fixed

Found while building the test suite, before first release:

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
