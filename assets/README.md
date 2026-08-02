Screenshots and the hero GIF (menu bar + open dropdown) live here, referenced from the root README.

The app icon's sources live here too:

- `Headroom.icon` — the Icon Composer document, and **the source of truth**. Edit this one.
- `icon-1024.png` — a committed *render* of that document, not a hand-made export. `build.sh`
  downscales it into the `.icns`, and on the Command-Line-Tools-only path it is the only icon input —
  `Headroom.icon` is never read there, because compiling it needs Xcode.
- `render-icon.sh` — regenerates the PNG from the document. Run it after any change to
  `Headroom.icon` and commit both, or the two build tiers will disagree about what the icon looks
  like.

`render-icon.sh` needs Xcode, which costs nothing extra: Icon Composer ships with Xcode, so anyone
able to edit the document can already run it.

See "The app icon" in `CLAUDE.md` for why the render comes from `actool` rather than Icon Composer's
own export, and why `build.sh` must not inset the result a second time.
