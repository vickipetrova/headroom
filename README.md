# Headroom

> Scaffold — the full README lands in the docs pass (Phase 5).

A tiny macOS menu bar app showing your Claude Code plan usage at a glance:

```
✻ 42% · 67%
```

Session (5-hour window) · Weekly (7-day). Click for reset times, countdowns, and model-scoped
weekly limits when your plan reports them.

Zero setup: it reads Claude Code's own OAuth token automatically (file or Keychain) and polls the
same endpoint behind `/usage`. No cookies, no DevTools, no pasting anything.

## Build

```bash
./build.sh && open build/Headroom.app
```

## Unofficial

Not affiliated with, endorsed by, or sponsored by Anthropic. "Claude" is a trademark of Anthropic.

## License

MIT © Victoria Petrova
