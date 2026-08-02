# Security

> Scaffold — written for real in the docs pass (Phase 5).

**What Headroom reads.** Your Claude Code OAuth token, from `~/.claude/.credentials.json` or the
macOS login Keychain item `Claude Code-credentials`. It is held in memory for the duration of a
request and never written anywhere.

**Where it goes.** `https://api.anthropic.com/api/oauth/usage`, and nowhere else. That is the app's
only network destination. No telemetry, no analytics, no update checks.

**Reporting.** Open a GitHub issue for anything non-sensitive. For something you'd rather not post
publicly, use GitHub's private vulnerability reporting on this repo. Never include your token or
credentials file in a report.
