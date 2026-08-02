# Contributing

Thanks for looking. Headroom does one thing — show Claude Code plan usage in the menu bar — and
the goal is to keep it small enough that one person can read the whole thing in an afternoon.

## Building

macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). Nothing else.

```bash
./build.sh          # -> build/Headroom.app
./build.sh --dmg    # also -> build/Headroom.dmg
open build/Headroom.app
```

Build from the latest `main` so you're not fixing something that already changed.

## What's welcome

Bug fixes. Compatibility fixes across macOS versions and architectures. Better handling when the
usage endpoint drifts. Anything on the [Roadmap](README.md#roadmap) — those are filed as
`good first issue` and are genuinely up for grabs, especially additional providers behind the
existing `UsageProvider` protocol.

## What won't be merged

- **New dependencies.** AppKit, Foundation, Security, UserNotifications, ServiceManagement. The
  zero-dependency, `swiftc`-only build is a feature, not an accident.
- **Anything that logs, caches, or writes the OAuth token.** See below.
- **A second network destination.** No analytics, no telemetry, no update checks, no crash
  reporting. One request, to `api.anthropic.com`.
- **Cost dashboards, historical databases, spend estimation.** Other projects do this well and the
  README links them.
- **Anything requiring an API key or costing money to run.**
- **An Xcode project.** It would make `build.sh` a lie.

## Ground rules for code

1. **Never print, log, or commit the token.** CI greps for it, but the grep is a backstop, not the
   rule.
2. **Parse defensively.** The usage endpoint is undocumented and community-discovered; it has
   already changed shape once. A field that's missing, null, or the wrong type must drop one row
   and render `–`. It must never crash and never throw.
3. **Keep `MenuController` provider-agnostic.** It renders `[LimitWindow]`. Claude-specific
   strings belong in `ClaudeProvider`.
4. **Match the surrounding style.** Comments explain *why*, not *what*.

`CLAUDE.md` has the architecture map and recipes for exercising each error state without touching
your real credentials — useful whether or not you use Claude Code.

## Testing

Run it. "Builds clean" isn't testing.

For anything visual, attach a screenshot of the menu bar title and the open dropdown. Say which
macOS version and which Mac (Apple Silicon or Intel). If you changed parsing, say what you fed it.

Two things are easy to break and easy to check:

- The menu bar title still updates while the dropdown is open (that's why timers are scheduled in
  `.common` run loop mode).
- Countdowns are still right after the Mac wakes from sleep.

## Pull requests

One change per PR. If you're planning something large, open an issue first — I'd rather talk about
the shape before you spend a weekend on it.

## Commits

[Conventional Commits](https://www.conventionalcommits.org/): `feat`, `fix`, `docs`, `chore`,
`refactor`, `perf`. Branches: `type/kebab-case-description`.

## Conduct

Be decent. Critique code, not people; assume the other person is trying to help. That's the whole
policy.

## License

MIT. By contributing you agree your contributions are licensed under it.
