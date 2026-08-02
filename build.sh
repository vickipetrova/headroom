#!/bin/bash
# Builds build/Headroom.app (and optionally build/Headroom.dmg with: ./build.sh --dmg).
# Requires the Xcode Command Line Tools (xcode-select --install). No Xcode project, no third-party
# dependencies. Compilation goes through SwiftPM so `swift test` works on the same sources.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Headroom"
VERSION="0.1.0"
BUNDLE_ID="com.vickipetrova.headroom"
MIN_MACOS="13.0"

APP="build/$APP_NAME.app"
BIN="$APP/Contents/MacOS/$APP_NAME"

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
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
</dict>
</plist>
PLIST

# Ad-hoc signing only — this repo never handles a Developer ID or notarization credentials.
# Signing and notarizing a release is a manual maintainer step: see docs/RELEASING.md.
# xattr first: extended attributes (quarantine, Finder info) make codesign refuse the bundle.
xattr -cr "$APP"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"

if [[ "${1:-}" == "--dmg" ]]; then
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
