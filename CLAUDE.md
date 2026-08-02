# CLAUDE.md

> Scaffold — written for real in the docs pass (Phase 5).

Guidance for Claude Code sessions working in this repo.

## Build and run

```bash
./build.sh && open build/Headroom.app
```

## Hard rules

- Zero third-party dependencies. AppKit, Foundation, UserNotifications, ServiceManagement only.
- Never print, log, or commit the OAuth token or the contents of the credentials file.
- All parsing of the usage endpoint must be defensive — it is undocumented and may drift. Missing
  or unexpected fields render `–`; they never crash.
- `build.sh` signs ad-hoc only. Notarization is a manual maintainer step (docs/RELEASING.md).
