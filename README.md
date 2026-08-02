# Headroom

Your Claude Code plan usage, in the macOS menu bar:

```
✻ 42% · 67%
```

Session (5-hour window) on the left, this week on the right. Click for reset times, live
countdowns, and per-model weekly limits when your plan reports them.

<!-- Replace with the hero GIF (menu bar + open dropdown) once recorded. -->
<img src="assets/headroom.gif" alt="Headroom in the menu bar, with the dropdown open" width="420">

**Zero setup.** No cookies, no DevTools, nothing to paste. Headroom reads the OAuth token Claude
Code already has and asks Anthropic the same question `/usage` does.

## How it works

Every five minutes (configurable), Headroom sends one request:

```
GET https://api.anthropic.com/api/oauth/usage
Authorization: Bearer <your Claude Code token>
anthropic-beta: oauth-2025-04-20
```

The token comes from wherever Claude Code keeps it, in this order:

1. `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`
2. The macOS login Keychain, generic password, service `Claude Code-credentials`

Claude Code refreshes that token itself while you work, so there is nothing to maintain. If it has
gone stale because you haven't opened Claude Code in a while, the menu says so.

Because this is account-level data rather than session lifecycle, it keeps working when Claude Code
is closed.

> [!NOTE]
> **This endpoint is undocumented and community-discovered.** It is not a public API, and Anthropic
> can change or remove it without notice — it has already grown a second response shape alongside
> the original one. Headroom treats every field as optional: anything missing, null, or unexpected
> renders as `–` rather than crashing. If the numbers ever look wrong, check `/usage` inside Claude
> Code and [open an issue](../../issues) if they disagree.

## Install

### Build from source

```bash
git clone https://github.com/vickipetrova/headroom.git
cd headroom
./build.sh
cp -R build/Headroom.app /Applications/
open /Applications/Headroom.app
```

That's the whole toolchain: `swiftc` and the Xcode Command Line Tools. No Xcode project, no
package manager, no dependencies.

### DMG

Download the latest `Headroom.dmg` from [Releases](../../releases), open it, and drag Headroom into
Applications.

## Requirements

- **macOS 13+** (Ventura). Launch at login uses `SMAppService`, which is 13.0 and later.
- **A Claude Pro or Max plan.** Session and weekly windows are plan quotas. Metered API-key
  accounts don't have them, so there is nothing for Headroom to show — it says so plainly instead
  of showing zeroes.
- **Claude Code, signed in at least once**, so there's a token to read.

## Settings

Everything lives in the dropdown under **Settings**:

| Setting | Options | Default |
|---|---|---|
| Refresh every | 1 / 5 / 15 minutes | 5 minutes |
| Notify above | Off / 50% / 80% / 90% | 80% |
| Launch at Login | on / off | off |

Alerts fire at most once per window per reset period, so sitting at 85% doesn't produce an alert on
every poll. Lowering the threshold mid-window counts as a new crossing and will alert again.

> [!IMPORTANT]
> **Alerts need a signed build.** Recent macOS refuses notification registration for ad-hoc signed
> apps, which is what `./build.sh` produces. If you built from source, the menu will show
> *"Alerts blocked — open Notification settings"* and no alerts will arrive. Everything else works
> normally. Signed releases are not subject to this.

## Roadmap

Deliberately small for v0.1. Not planned by me, but very welcome as contributions — these are
filed as [good first issues](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22):

- Multiple accounts in one menu
- A historical sparkline of the session window
- Reading usage from Claude Code's statusline stdin instead of polling
- A configurable menu bar title format
- A model-scoped-only mode (show just the Opus/Fable weekly line)
- Graceful mode for non-Pro/Max accounts
- Additional providers — Cursor, Codex, Copilot — behind the existing `UsageProvider` protocol

Out of scope: cost dashboards, telemetry, anything needing an API key. See
[CONTRIBUTING.md](CONTRIBUTING.md).

## Other projects in this space

There are several good ones, and they solve different problems. If Headroom isn't the shape you
want, one of these probably is:

- **[ClaudeBar](https://github.com/tddworks/ClaudeBar)** — the big one. Tracks a dozen assistants
  (Claude, Codex, Gemini, Copilot, and more), themes, Homebrew cask.
- **[Claude Usage Bar](https://github.com/Blimp-Labs/claude-usage-bar)** — richer detail: usage
  history charts, per-model breakdown, extra-usage spend in USD.
- **[ClaudeUsageBar](https://github.com/Artzainnn/claudeusagebar)** — covers claude.ai usage too,
  not just Claude Code. Setup is copying a cookie out of DevTools.
- **[Claude Usage](https://github.com/richhickson/claudecodeusage)** — closest to Headroom in
  spirit: small, native, session and weekly at a glance.
- **[Claude Status Bar](https://github.com/m1ckc3s/claude-status-bar)** — a different question
  entirely: whether Claude Code is *currently* thinking, running a tool, or waiting on you. Pairs
  well with this one, and its repo is the template this one's build script follows.

Headroom's one distinguishing bet is that you shouldn't have to set anything up.

## Uninstall

```bash
rm -rf /Applications/Headroom.app
defaults delete com.vickipetrova.headroom
```

If you turned on Launch at Login, switch it off first (or remove Headroom from System Settings ›
General › Login Items). Headroom writes nothing else — no caches, no logs, no config files.

## Security

Headroom reads your OAuth token, holds it in memory for one request, and sends it to exactly one
place: `api.anthropic.com`. No telemetry, no analytics, no update checks. See
[SECURITY.md](SECURITY.md).

## Trademark / Not affiliated

This is an unofficial, open-source side project. **It is not affiliated with, endorsed by, or
sponsored by Anthropic.** "Claude" and the Claude spark are trademarks of Anthropic, used here
nominatively. The MIT license below covers this source code only and conveys no rights to
Anthropic's trademarks or brand.

## License

MIT © Victoria Petrova. See [LICENSE](LICENSE).
