# CLAUDE.md

Notes for Claude Code sessions working in this repo.

## Build, run, test

```bash
swift test --disable-xctest       # the whole suite, ~0.05s
./build.sh                        # -> build/Headroom.app (universal, ad-hoc signed)
./build.sh --dmg                  # also -> build/Headroom.dmg
./build.sh --dmg-only             # DMG around the existing app, without rebuilding it
open build/Headroom.app
pkill -f "MacOS/Headroom"         # stop it (menu bar app; there's no window to close)
```

`--dmg-only` is what the release procedure uses: the app is signed with a Developer ID, notarized and
stapled before it goes into the image, and rebuilding at that point would throw all of that away.

`swift run` does not work and is not meant to — it produces a bare binary with no `Info.plist`, so
`LSUIElement`, `SMAppService.mainApp`, and notification registration all misbehave.

There is no Xcode project. SwiftPM compiles the sources and `build.sh` wraps the result in a bundle.

## Architecture

| File | Responsibility |
|---|---|
| `Sources/Headroom/main.swift` | Six lines of top-level code. Top-level code can't live in a library target, so this is all the executable target holds |
| `Sources/HeadroomCore/AppDelegate.swift` | Wires provider → menu, owns the poll timer and the 60s countdown tick, refreshes on wake. The **only** public symbol in the module |
| `Sources/HeadroomCore/MenuController.swift` | The status item: menu bar title, dropdown, Settings submenu. Knows nothing about where usage comes from |
| `Sources/HeadroomCore/UsagePanel.swift` | The dropdown's SwiftUI rows, and the pure `UsageRow` view model behind them. Which limits reach the *menu bar title* is `TitleSelection`, in MenuController.swift |
| `Sources/HeadroomCore/UsageAPI.swift` | `LimitWindow` model, `UsageProvider` protocol, `ClaudeProvider` (endpoint client + all response parsing) |
| `Sources/HeadroomCore/Credentials.swift` | Token discovery across the login Keychain and the credentials file, ranked rather than first-wins |
| `Sources/HeadroomCore/Format.swift` | Percentages, countdowns, locale-aware clock times, the colour modes, the menu bar spark image |
| `Sources/HeadroomCore/Settings.swift` | UserDefaults-backed preferences; launch-at-login proxies `SMAppService` |
| `Sources/HeadroomCore/Notifier.swift` | Threshold alerts, deduplicated per window per reset period |
| `assets/Headroom.icon` | Icon Composer document — the icon's source of truth. Two gauge tracks, orange fills, cream gradient |
| `assets/icon-1024.png` | A committed *render* of that document, and the only icon input on the CLT-only path |
| `assets/render-icon.sh` | Regenerates the PNG from the document. Run it after editing the icon, commit both |

Everything lives in `HeadroomCore` so the test target can reach it with `@testable`, keeping the
public API to `AppDelegate` alone. `MenuController` renders `[LimitWindow]` and nothing else — that's
what makes adding a second provider one new file, so don't put Claude-specific strings in it.

`Package.swift` pins `swiftLanguageModes: [.v5]`. Swift 6 mode rejects the static mutable state in
`Notifier`; moving to `.v6` means annotating those, not just flipping the line. `platforms:
[.macOS(.v13)]` is load-bearing — it, not the triple, is what pins the deployment target.

## Hard rules

1. **Never print, log, or commit the OAuth token**, or the contents of the credentials file. Not in
   debug output, not in error messages, not in CI. `.github/workflows/build.yml` greps for this.
2. **Zero third-party dependencies.** AppKit, SwiftUI, Foundation, Security, UserNotifications,
   ServiceManagement. `Package.swift` has no `dependencies:` array and never should. Tests use
   swift-testing, which ships with the toolchain — **not XCTest**, which is absent from the Command
   Line Tools and would break the CLT-only build contract.
3. **All parsing of the usage endpoint must be defensive.** It is undocumented and it drifts.
   Missing, null, or wrong-typed fields drop that *one* row and render `–`. Never force-unwrap a
   field from the response; never throw on a shape you didn't expect.
4. **No secrets in the repo, and no notarization machinery in `build.sh`.** It signs ad-hoc by
   default and may use `$HEADROOM_SIGN_ID` — an identity name, resolved from the developer's own
   Keychain — but it must never contain or handle a certificate, an app-specific password, or
   anything notarization needs. Releasing stays a manual maintainer step (`docs/RELEASING.md`), and
   CI signs ad-hoc and drafts the release for a signed build to replace.
5. **One network destination:** `api.anthropic.com`. No analytics, no update checks.

## The response shape

The endpoint returns two overlapping shapes, and `ClaudeProvider.windows(in:)` reads both:

- **Preferred:** a `limits` array of `{kind, percent, resets_at, scope}` where `kind` is `session`,
  `weekly_all`, or `weekly_scoped`. Scoped entries name their own model in
  `scope.model.display_name`, which is why the third row says "WEEKLY · FABLE" rather than
  hardcoding Opus.
- **Legacy:** top-level `five_hour`, `seven_day`, `seven_day_opus` with `utilization` / `resets_at`.
  Used to fill in anything the array didn't provide, **per field**.

Four traps, each with a regression test — don't "simplify" any of them:

- **`resets_at` is re-stamped on every request.** Three polls twenty seconds apart came back with
  fractional seconds `.516073`, `.880178`, `.202674` for the same reset. `Notifier.periodID`
  therefore quantizes to a rounded minute; keyed on the raw timestamp, every poll looked like a new
  period and alerts fired on every single poll. Windows are ≥5 hours apart, so the bucket can never
  merge two real periods.

- **Cast `limits` to `[Any]` and filter, never to `[[String: Any]]`.** A conditional cast to an array
  of a concrete element type checks every element and yields nil if one fails, so a single
  unrecognized entry would discard the whole array instead of itself.
- **JSON booleans bridge to `NSNumber`.** `as? Double` on `true` succeeds and gives 1.0, so
  `{"percent": true}` reads as 1% unless the CoreFoundation type id is checked. `as? Bool` is not a
  substitute: `NSNumber(42) as? Bool` also succeeds. The shared `isJSONBoolean` guard is used by the
  usage parser *and* by `Credentials` when reading `expiresAt`.
- **Two ISO8601 formatters are required.** Timestamps arrive as
  `2026-08-02T16:39:59.408408+00:00`; `ISO8601DateFormatter` needs `.withFractionalSeconds` for
  those and returns nil without it, and returns nil *with* it for timestamps that lack them.

Values are also clamped to 0–100 and checked for finiteness, because `Fmt.pct` converts to `Int` and
that traps on infinity or anything past `Int`'s range. `scope.model.display_name` is server-controlled
and lands in a menu label, a notification title *and* a `UserDefaults` key, so it is trimmed,
flattened, length-capped, and rejected when empty.

## Why the dropdown's rows are custom views

A menu item that isn't a command has to be disabled, and macOS draws disabled items dimmed — which is
why the panel used to look washed out. The informational rows are therefore SwiftUI views in
`NSMenuItem.view`, which AppKit does *not* dim, while `NSMenu` still supplies the material, the
dismissal behaviour and key equivalents for the real commands.

Four things were measured before committing to this, and each would have sunk it:

- **SwiftUI does repaint while a menu is tracking.** Reassigning `NSHostingView.rootView` updates the
  row on screen mid-tracking, which is what lets `refreshLiveRows` keep working. If it had deferred
  until tracking ended, held-open menus would have silently frozen again.
- **`isEnabled = false` does not dim a custom view** — only the item's own drawing. So these rows can
  be inert without going grey.
- **`title` still reaches AppleScript and VoiceOver on a view-backed item**, so `NSMenuItem.hosting`
  sets it and the `osascript` recipe below still works. Set it on every view-backed row.
- **Sizing** needs `hostingView.frame.size = hostingView.fittingSize`, or the item lays out at zero
  height on first display. The SwiftUI frame is `minWidth`/`maxWidth: .infinity`, not a fixed width,
  and the hosting view carries `autoresizingMask = [.width]`: AppKit sizes the menu from the widest
  item and adds ~65pt of its own chrome, but lays the view out at x=0 without stretching it, so a
  fixed-width row leaves that chrome as dead space and the separators visibly overrun the text.

`NSApp.appearance` does **not** drive menu rendering, so dark mode can only be checked by switching
the system appearance — a forced-appearance probe will render light regardless and mislead you.

Section headings inside the *Settings submenu* are deliberately still plain dimmed items: a greyed
heading is the conventional look inside a menu, and the rows it labels are commands, not data.

**Commands stay plain `NSMenuItem`s**, and this is not a style preference — two things were measured
on a view-backed version of Refresh Now. A hosting view swallows the mouse event, so
`NSMenuItem.action` never fires and the row has to reimplement its own selection and dismissal. And
`keyEquivalent` stops working outright: ⌘Q on a plain item kept working while ⌘R on the view-backed
row did nothing, and `NSMenuDelegate.menuHasKeyEquivalent` — the documented hook for reclaiming it —
is not consulted for status-item menus. A custom command row costs the shortcut, the native
highlight, and AppKit's click routing; that is why Refresh Now shows its age as plain text rather
than as a badge.

## The open dropdown

`rebuild()` refuses to run while the menu is open, and rows are updated in place instead through
`liveRows`. Three reasons rebuilding mid-tracking is wrong: it can delete the parent of an open
Settings submenu, it re-targets a click already in flight (aim at "Refresh Now", hit "Quit
Headroom"), and it destroys highlight and keyboard state. `menuNeedsUpdate` also fires during ⌘R/⌘Q
key-equivalent matching, so this is reachable without the menu ever being clicked.

Live rows close over the window's **`id`** and look it up in current state, never over a
`LimitWindow` value. Capturing the value made a held-open menu keep counting down to a reset the poll
had already replaced, reach "now", and stay pinned there until the menu was reopened.

Measured, not assumed: an open `NSMenu` **does re-layout** when a row's text grows — it does not clip
to its open-time width. A held-open menu was observed resizing 253 → 293 → 640 points mid-tracking
(gaining a weekday at the 24h threshold, then an error footer), growing leftward to keep its right
edge anchored, and landing on exactly the width a from-scratch rebuild produces. So don't reserve or
pad widths. The real limit is *row count*: in-place updates can't add or remove rows, so a window
appearing or disappearing waits for the next open. The menu bar title stays correct meanwhile.

One trap when checking this by hand: querying menu item names over `osascript` on a **closed** menu
triggers `menuNeedsUpdate` and therefore a rebuild, so it reports fresh text whether or not in-place
refresh works. It only proves something about live updates when paired with evidence the menu is
actually tracking.

## Credentials

Two stores, and choosing between them on *presence* was a real bug: a stale
`~/.claude/.credentials.json` shadowed the live Keychain token forever, every poll 401'd, and the
menu advised opening a Claude Code session — which could never help, because the copy Claude Code
refreshes was the one being ignored. `resolve(file:keychain:)` ranks instead:

1. a bare token (Claude Code never writes that shape, so it's a deliberate human override)
2. whichever `expiresAt` is later
3. the Keychain, matching Claude Code's own precedence

`expiresAt` is **milliseconds** — Claude Code writes `Date.now() + expires_in * 1000`, so a real
value has 13 digits. It is kept as a raw `Double` and never converted to a `Date`; read as seconds it
lands in the year 58,000.

`.absent` and `.accessDenied` are distinct on purpose. Claude Code creates its Keychain item without
`-A`/`-T`, so its ACL trusts only the creating binary and Headroom gets a permission prompt; reporting
a denial as "you've never signed in" is wrong advice on the one path every Keychain-only user takes.
A denial also latches, or a user who clicks Deny would be re-prompted on every poll. The lookup runs
on a serial background queue because that prompt is modal and every `refresh()` caller is the main
thread.

## The app icon

Headroom is `LSUIElement`: no Dock tile, no window. The bundle icon is what Finder, the DMG, the
notification banner, Login Items and the Keychain permission prompt show — that is its whole surface
area, which is why `build.sh` renders one rather than shipping the generic placeholder.

`build.sh` builds it in two tiers, and **the boundary between them is additive on purpose**:

- **Tier 1, always.** `sips` and `iconutil` — both in `/usr/bin` — turn `assets/icon-1024.png` into
  `Contents/Resources/Headroom.icns`, and the plist gets `CFBundleIconFile`. No Xcode.
- **Tier 2, when `xcrun --find actool` succeeds.** `actool` compiles `assets/Headroom.icon` into
  `Assets.car` and the plist also gets `CFBundleIconName`, so macOS 26+ renders the layered icon with
  its own material and specular treatment instead of a flat bitmap. Skipped silently otherwise, and
  never fatal — a future `actool` that rejects the document must cost the layered icon, not the build.

The `.icns` is therefore byte-identical whether or not Xcode is installed (verified by `shasum` across
both paths), so a CLT-only contributor and CI ship the same icon and "it looks different on my
machine" cannot happen.

### Editing the icon

`assets/Headroom.icon` is the source of truth, and **`assets/icon-1024.png` is a committed render of
it**, not a hand-exported picture. Change the document, then run `./assets/render-icon.sh` and commit
both. The script needs Xcode, which is not a new burden — Icon Composer, the only thing that edits the
document, ships with Xcode too.

It renders through `actool` rather than Icon Composer's *File ▸ Export* on purpose. The export is
full-bleed, because on macOS 26 the system supplies the mask and the shadow; `actool` instead renders
the icon the way macOS composites it, already on Apple's 824-of-1024 grid and with the shadow baked
in. Committing the on-grid render means `build.sh` only has to downscale. **Do not add an inset step
to `build.sh`** — the source is already inset, and doing it twice makes the icon visibly small.

### Traps, each measured

- **The `.icns` geometry only matters on macOS 13–15.** Those draw the `.icns` as authored, so a
  full-bleed source really does render about a quarter larger than every other app. macOS 26 does
  **not**: it re-masks legacy `.icns` content into the system tile, and inset, full-bleed and
  deliberately over-inset bundles all render to an identical 83.59% bounding box there, the same as
  Calculator's. So this regression is invisible on a current Mac, which is exactly why CI asserts the
  artwork spans ~80% of its tile. Don't "verify" the inset by looking at your own Dock.
- **`sips` reports success on input it never read.** It exits 0 when the file does not exist (printing
  only a warning) *and* on a truncated PNG, rendering partial data at the requested size. Neither
  shows up in an exit status or in the output's dimensions. `build.sh` therefore validates the source
  up front: it exists, its last 8 bytes are the PNG `IEND` chunk and its constant CRC
  (`49454e44ae426082` — truncation is what that catches), and it is 1024 wide.
- **`actool` exits 0 when it renders nothing, so `Assets.car` is not the signal.** If `--app-icon`
  names an asset the document doesn't contain — rename `Headroom.icon`, or change `APP_NAME`, and it
  will — `actool` still writes an `Assets.car` full of layers with no icon in it, and an *empty*
  partial plist. Guarding on the file's existence passes there and sets `CFBundleIconName` pointing at
  nothing. The guard is `plutil -extract CFBundleIconName` on the partial plist, and the value written
  into `Info.plist` is the one `actool` reports rather than an assumed `$APP_NAME`.
- **`actool` must compile to a staging directory.** It also writes its own `Headroom.icns`, so
  compiling straight into `Contents/Resources` would overwrite the complete ten-size family with a
  four-size subset. `--standalone-icon-behavior` does not turn that output off — `none` still emits
  it, only smaller. Only `Assets.car` is copied out. Taking `actool`'s `.icns` instead would also make
  the bundle differ by build machine: its `Assets.car` is not even reproducible between two runs on
  one machine, since it embeds a fresh timestamp and fresh rendition UUIDs each time. The `.icns`
  determinism claim above is about the `.icns` alone.
- **The DMG volume icon needs the flag, not just the file.** `.VolumeIcon.icns` at the volume root
  does nothing on its own; the root also needs Finder's custom-icon bit. `SetFile -a C` on the
  *staging folder* sets it there, but `hdiutil create -srcfolder` builds a fresh filesystem and does
  not carry that FinderInfo onto the volume, so it is silently lost — `GetFileInfo -a` on the mounted
  result comes back all-lowercase. It has to be set on the mounted image, which is why the DMG is
  built read-write, flagged, then converted to UDZO.
- **Bash-only word splitting was removed, not documented around.** The size table used `set -- $SPEC`,
  which splits under bash but *not* under zsh — pasting that loop into a shell silently writes one
  file named `.png`. It is now `while read -r SIZE NAME`, which also stops clobbering the script's own
  positional parameters.

Intermediates land in `build/`, which `.gitignore` already covers.

Cost, since it is a large fraction of a small app: the binary is ~579 KB, the `.icns` ~607 KB and
`Assets.car` ~1.4 MB, so the icon is roughly three quarters of a ~2.6 MB bundle. That is inherent to a
soft gradient render, not a packaging mistake.

To check what macOS actually resolves rather than what is merely on disk, ask the icon services —
`NSWorkspace.shared.icon(forFile:)` on the built bundle, in a scratch script. A bundle with no icon
still returns an image (the generic placeholder), so compare against
`NSWorkspace.shared.icon(for: .application)` instead of null-checking. `open build/Headroom.app` is the
by-eye version: the icon then shows up in Login Items and on any notification. Don't reach for
`qlmanage -t` — it hangs indefinitely from a non-GUI session rather than returning.

On macOS 26 a bundle containing `Assets.car` renders the *layered* icon, so the `.icns` fallback is
only exercised by a CLT-only build. `DEVELOPER_DIR=/Library/Developer/CommandLineTools ./build.sh`
produces one without uninstalling anything, and is how both tiers get tested on one machine.

### Light and dark

`icon.json` declares no dark or tinted variant and does not need to: `"fill": {"automatic-gradient":
…}` is the feature that derives them. `assetutil --info` on the compiled car shows all three
appearances registered, with Aqua and Tintable referencing the declared cream gradient while
**DarkAqua references a two-stop grey ramp 0.192 → 0.078 that `actool` generated itself**. The two SVG
layer groups are shared byte-for-byte across all three.

What you cannot conclude from that is how it looks on screen, and the obvious checks don't work.
`NSWorkspace.shared.icon(forFile:)` returns the default rendition no matter the appearance — verified
against Notes, Reminders and System Settings, which come back byte-identical with
`NSApp.appearance` genuinely flipped, so a headless script cannot observe the switch at all. A `.icns`
has no appearance variants in the first place, so on macOS 13–25 the icon is necessarily the same in
both modes.

## Testing

`swift test --disable-xctest`. Suites live in `Tests/HeadroomCoreTests/`.

Parsing tests feed **JSON text** through `JSONSerialization`, not Swift dictionary literals — values
have to arrive as the `NSNumber`s the real response produces, or the boolean and integer bridging
paths above go untested.

`NotifierTests` and `SettingsTests` reassign `Settings.defaults` / `Notifier.defaults` to a scratch
`UserDefaults` suite, so they sit under one `@Suite(.serialized)` parent. Two things to know before
editing them:

- **No `deinit`.** swift-testing releases the previous suite instance while constructing the next
  one, so a `deinit` restoring those statics overlaps the next `init` writing them and trips Swift's
  exclusivity checking with a `SIGABRT`. Setup happens in `init`, which wipes the scratch domain.
- **`Notifier.deliver` is injected.** `UNUserNotificationCenter.current()` raises an ObjC exception
  in a process with no app bundle — every `swift test` run — and that's an abort, not a catchable
  error, so one stray call kills the whole run with no attribution.

### Never called from a test

Enforced by a CI grep, and worth understanding rather than working around:

- `Credentials.accessToken()` / `tokenFromFile()` / `tokenFromKeychain()` — read the real Keychain
  item and a live OAuth token, and `#expect` prints compared values into CI logs on failure. Only
  `token(in:)` with synthetic bytes is in scope.
- `Settings.launchAtLogin` — the setter registers a real login item pointing at the test binary.
- `ClaudeProvider.fetch` — real network, real token.
- `Notifier.requestAuthorizationIfNeeded()` / `post` — reach `UNUserNotificationCenter`.
- Constructing `MenuController` or `AppDelegate` — `MenuController` creates a real `NSStatusBar`
  status item in a stored-property initializer, so merely existing needs a GUI session.

### Checking the live app

Reading the menu without screenshots:

```bash
osascript -e 'tell application "System Events" to tell process "Headroom" \
  to get name of every menu item of menu 1 of menu bar item 1 of menu bar 1'
```

For error states that the unit tests can't reach (the real 401 path, a dead network with stale data
on screen), copy `Sources/` to a scratch directory, patch the copy, and build a throwaway bundle from
it. **Never delete or rename the `Claude Code-credentials` Keychain item** — that is Claude Code's
live login, not test data.

## Releasing

Bump `VERSION` in `build.sh`, add the entry to `CHANGELOG.md`, tag `vX.Y.Z`. See
`docs/RELEASING.md` for the manual signing and notarization steps.
