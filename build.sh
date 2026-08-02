#!/bin/bash
# Builds build/Headroom.app. Optionally packages a DMG too:
#
#   ./build.sh              app only
#   ./build.sh --dmg        app, then DMG
#   ./build.sh --dmg-only   DMG around the existing app, without rebuilding it
#
# --dmg-only exists for the release procedure: the app has to be signed with a Developer ID,
# notarized and stapled *before* it goes into the image, and rebuilding at that point would discard
# the signature and the ticket. See docs/RELEASING.md.
#
# Requires the Xcode Command Line Tools (xcode-select --install). No Xcode project, no third-party
# dependencies. Compilation goes through SwiftPM so `swift test` works on the same sources.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Headroom"
VERSION="0.1.0"
BUNDLE_ID="com.vickipetrova.headroom"
MIN_MACOS="13.0"

MODE="${1:-}"
APP="build/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

if [[ "$MODE" == "--dmg-only" ]]; then
  [[ -d "$APP" ]] || { echo "error: $APP not found — run ./build.sh first." >&2; exit 1; }
  echo "Reusing the existing $APP (not rebuilding)."
else

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling universal binary (arm64 + x86_64)…"
# Universal so it runs natively on Apple Silicon and Intel without Rosetta. SwiftPM builds one arch
# per invocation, so this is two builds joined by lipo.
#
# --triple twice rather than `--arch arm64 --arch x86_64`: passing --arch more than once silently
# switches SwiftPM to the XCBuild backend, which lives inside Xcode.app and does not exist under the
# Command Line Tools. That would break the build for CLT-only contributors while still passing in CI.
#
# -debug-info-format none because `swift build -c release` compiles with -g by default, and the
# resulting debug map embeds absolute paths from this machine's .build directory into the shipped
# binary.
#
# The deployment target comes from `platforms:` in Package.swift, not from the triple — SwiftPM
# rewrites the version component on Darwin, so the build machine's OS cannot leak in.
SPM_FLAGS=(-c release -debug-info-format none)
SLICES=()
for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
  swift build "${SPM_FLAGS[@]}" --triple "$TRIPLE"
  # Ask SwiftPM where it put things rather than hardcoding a path. Note .build/release is a
  # compatibility symlink pointing at whichever triple built last — using it would lipo one slice
  # with itself. The flags must match the build exactly, hence the shared array.
  SLICES+=("$(swift build "${SPM_FLAGS[@]}" --triple "$TRIPLE" --show-bin-path)/$APP_NAME")
done
lipo -create "${SLICES[@]}" -output "$BIN"

# --- App icon ---------------------------------------------------------------------------------
#
# Headroom is LSUIElement, so it has no Dock tile and no window: the icon is seen in Finder, in the
# DMG, on notification banners, in Login Items, and on the Keychain permission prompt. Those are the
# whole surface area, which is why this is worth a build step rather than nothing.
#
# Two tiers, and the boundary between them is deliberately *additive*: the .icns is always the one
# built here from the flattened export, byte for byte, whether or not Xcode is installed. Xcode only
# ever adds the layered icon on top. A contributor with the Command Line Tools alone and CI therefore
# ship the same icon, so "it looks different on my machine" cannot happen.
ICON_PNG="assets/icon-1024.png"
ICON_DOC="assets/Headroom.icon"
ICONSET="build/$APP_NAME.iconset"
# Empty on the CLT-only path. Interpolated into the plist below, so the layered icon is only claimed
# when it is actually in the bundle — a CFBundleIconName pointing at an absent Assets.car makes
# macOS fall back with a console complaint rather than silently.
ICON_NAME_KEY=""

# Tier 1: the classic .icns, from sips and iconutil, both of which are in /usr/bin.
#
# The inset is the part that is not obvious. `assets/icon-1024.png` is an Icon Composer export, and
# those are full-bleed by design — measured, its squircle touches all four canvas edges (alpha 255 at
# the top edge centre, 0 only in the corners) because on macOS 26 the system supplies the mask and the
# shadow. Downscaling that straight into an iconset is the recipe everyone reaches for and it is
# wrong: the art fills the whole tile, so the icon renders about a quarter larger than every other app
# in Finder. Apple's grid puts the shape in 824 of 1024 with the rest as margin, which is also what
# actool's own render of this artwork does. So scale to 824 and pad back out to 1024 first; sips pads
# with transparency, verified, so no compositing tool is needed.
#
# Every size is then downscaled from that one inset master rather than inset individually, which is
# what keeps the margin proportional at 16px as well as at 1024.
echo "Rendering the app icon…"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 824 824 "$ICON_PNG" --out "build/icon-art.png" >/dev/null
sips --padToHeightWidth 1024 1024 "build/icon-art.png" --out "build/icon-master.png" >/dev/null
# Deliberately `set --` on an unquoted word: this file is bash, where that word-splits. It does not
# split under zsh, so this loop silently produces one file named ".png" if you paste it into a shell.
for SPEC in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
            "512 icon_512x512" "1024 icon_512x512@2x"; do
  set -- $SPEC
  sips -z "$1" "$1" "build/icon-master.png" --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns"

# Tier 2: the layered Icon Composer document, so macOS 26 and later can render it with the material
# and specular treatment instead of a flat bitmap. actool lives inside Xcode.app, not the Command Line
# Tools, so this is skipped silently when it is absent — the check is `xcrun --find`, which exits
# non-zero under a CLT-only DEVELOPER_DIR.
#
# It compiles into a staging directory and only Assets.car is taken. actool also writes its own
# Headroom.icns, and compiling straight into Contents/Resources would overwrite the complete one built
# above with a four-size subset: --standalone-icon-behavior does not turn that output off, only
# resizes it. Its render is arguably the nicer of the two — Apple's renderer, working from the layered
# source, and it bakes in a drop shadow this one has no way to reproduce — but taking it would make
# the bundle differ by build machine, which is the one thing this tier boundary exists to prevent.
if ACTOOL="$(xcrun --find actool 2>/dev/null)"; then
  ICON_STAGE="build/icon-actool"
  rm -rf "$ICON_STAGE"
  mkdir -p "$ICON_STAGE"
  # Not fatal. A future actool that rejects this document must cost the layered icon, not the build.
  if "$ACTOOL" "$ICON_DOC" \
       --compile "$ICON_STAGE" \
       --platform macosx \
       --minimum-deployment-target "$MIN_MACOS" \
       --app-icon "$APP_NAME" \
       --output-partial-info-plist "$ICON_STAGE/partial.plist" \
       --errors --warnings --notices >/dev/null 2>&1 && [[ -f "$ICON_STAGE/Assets.car" ]]; then
    cp "$ICON_STAGE/Assets.car" "$APP/Contents/Resources/"
    ICON_NAME_KEY="  <key>CFBundleIconName</key><string>$APP_NAME</string>"
    echo "Compiled the layered icon for macOS 26+ (Assets.car)."
  else
    echo "warning: actool could not compile $ICON_DOC — shipping the .icns only." >&2
  fi
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>$APP_NAME</string>
$ICON_NAME_KEY
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
</dict>
</plist>
PLIST

# Ad-hoc by default. Set HEADROOM_SIGN_ID to a signing identity in your Keychain to use that
# instead — no secret ever lives in this repo, and this script still knows nothing about
# notarization, which stays a manual maintainer step (docs/RELEASING.md).
#
# Worth doing while developing: an ad-hoc signature's designated requirement is the binary's own
# hash, so every code change makes Headroom a different app to macOS and the Keychain re-asks for
# permission to read your Claude Code login. A real identity gives a stable, identity-based
# requirement, so "Always Allow" sticks across rebuilds:
#
#   HEADROOM_SIGN_ID="Apple Development: Your Name (TEAMID)" ./build.sh
#
# xattr first: extended attributes (quarantine, Finder info) make codesign refuse the bundle, and
# that is the one benign failure this step used to swallow.
#
# Nothing else may be swallowed. Apple Silicon refuses to launch a binary carrying no signature at
# all, so hiding a codesign failure here does not produce an unsigned-but-working app — it produces
# a build that dies at launch as "Headroom is damaged", with the actual error discarded.
xattr -cr "$APP"
if [[ -n "${HEADROOM_SIGN_ID:-}" ]]; then
  echo "Signing with: $HEADROOM_SIGN_ID"
  codesign --force --options runtime --timestamp --sign "$HEADROOM_SIGN_ID" "$APP"
else
  codesign --force --sign - "$APP"
fi

echo "Built $APP"

fi  # end of the build-the-app branch

if [[ "$MODE" == "--dmg" || "$MODE" == "--dmg-only" ]]; then
  echo "Packaging DMG…"
  DMG="build/$APP_NAME.dmg"
  STAGE="build/dmg-stage"
  rm -rf "$STAGE" "$DMG"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"

  # Build straight from the folder rather than laying out a mounted read-write image: macOS's
  # fseventsd creates a hidden .fseventsd on any writable volume, and deleting it does not stick
  # (the deletion is itself an event, which recreates it). No mount, no stray hidden folders.
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  echo "Built $DMG"
fi

echo
echo "Run:      open $APP"
echo "Install:  cp -R $APP /Applications/"
