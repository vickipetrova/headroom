# Security

Headroom handles one sensitive thing: your Claude Code OAuth token. Here is exactly what happens
to it.

## What it reads

The access token Claude Code already stores, from either of:

- The macOS login Keychain, generic password, service `Claude Code-credentials`
- `~/.claude/.credentials.json` → `claudeAiOauth.accessToken`

When both exist Headroom compares their expiry timestamps and uses whichever lives longest, so a
stale leftover file can't shadow the login Claude Code is actively refreshing.

The Keychain read goes through `Security.framework` in-process (`SecItemCopyMatching`), not by
shelling out to `/usr/bin/security` — so the token never crosses a pipe or appears in any
subprocess's output.

Headroom reads the token fresh for each request and drops it. It never caches it, writes it to
disk, or copies it anywhere. Nothing in the source prints or logs it, and CI fails the build if a
`print`/`NSLog` mentioning a token appears in `Sources/`.

## Where it goes

One destination, one request:

```
GET https://api.anthropic.com/api/oauth/usage
```

That's the entire network surface. No telemetry, no analytics, no crash reporting, no update
checks, no third-party services. The URLSession is ephemeral, so no response is cached to disk, and
it refuses every redirect — the token cannot be forwarded to another host even if the endpoint
starts returning one.

## What it stores

In `UserDefaults` (`com.vickipetrova.headroom`) only:

- your refresh interval and alert threshold
- one marker per limit window recording the reset timestamp already alerted on, so you don't get
  the same alert twice

Launch at Login is stored by macOS, not by Headroom. No credentials, no usage history, no logs.

## Reporting a problem

For anything non-sensitive, [open an issue](../../issues). For a vulnerability, use GitHub's
private vulnerability reporting on this repository (Security › Report a vulnerability).

**Never include your token, your credentials file, or a screenshot showing them in a report.** If
you think your token has been exposed, sign out of Claude Code and sign back in — that rotates it.

## Scope note

Headroom is unofficial and reads an undocumented endpoint. It cannot change your plan, spend money,
or modify anything in your Claude Code setup; it only reads. But it is a side project maintained by
one person and audited by whoever reads the source — which is the point of keeping it this small.
