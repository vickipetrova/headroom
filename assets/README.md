Screenshots and the hero GIF (menu bar + open dropdown) live here, referenced from the root README.

The app icon's sources live here too, and `build.sh` reads both on every build:

- `Headroom.icon` — the Icon Composer document, and **the source of truth**. Edit this one.
- `icon-1024.png` — its flattened export, which is what the `.icns` is rendered from. It does not
  update itself; re-export it from Icon Composer after changing the document, or the two will
  disagree about what the icon looks like.

See "The app icon" in `CLAUDE.md` for how each is used, and for why the export is inset onto Apple's
grid before it is downscaled.
