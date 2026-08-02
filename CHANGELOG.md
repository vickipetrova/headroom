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

### Known limitations

- Threshold alerts require a signed build. macOS refuses notification registration for the ad-hoc
  signed bundle `./build.sh` produces; the menu shows "Alerts blocked" in that case rather than
  silently never alerting.
- Pro and Max plans only. Metered API-key accounts have no session or weekly quota, and Headroom
  says so instead of showing zeroes.

[0.1.0]: https://github.com/vickipetrova/headroom/releases/tag/v0.1.0
