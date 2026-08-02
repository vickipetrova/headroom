# Releasing

Headroom's `build.sh` deliberately knows nothing about signing identities or Apple credentials — it
only ad-hoc signs. Producing a release that opens without a Gatekeeper warning is a manual step on
the maintainer's Mac, documented here.

## 1. Prepare

- Bump `VERSION` in `build.sh`.
- Add the release section to `CHANGELOG.md`.
- Commit, then tag and push:

```bash
git tag v0.1.0
git push origin main --tags
```

## 2. CI builds a draft

`.github/workflows/release.yml` runs on any `v*` tag: it builds the app and DMG on a
`macos-latest` runner and opens a **draft** GitHub Release with `Headroom.dmg` attached.

That asset is ad-hoc signed — CI never sees a Developer ID, by design. It is fine for testing and
wrong to publish. Replace it with a properly signed one below.

## 3. Sign and notarize locally

One-time setup on your Mac:

1. A **Developer ID Application** certificate in your Keychain (Xcode › Settings › Accounts ›
   Manage Certificates). Note: an *Apple Development* certificate is not enough for distribution.
2. A notarytool credential profile, using an
   [app-specific password](https://support.apple.com/en-us/102654) — not your Apple ID password:

```bash
xcrun notarytool store-credentials "headroom" \
  --apple-id you@example.com \
  --team-id YOURTEAMID \
  --password xxxx-xxxx-xxxx-xxxx
```

Then, per release:

```bash
./build.sh --dmg

SIGN_ID="Developer ID Application: Your Name (YOURTEAMID)"

# Sign and notarize the .app first, so a copy dragged out of the DMG carries its own ticket.
xattr -cr build/Headroom.app
codesign --force --options runtime --timestamp --sign "$SIGN_ID" build/Headroom.app
ditto -c -k --keepParent build/Headroom.app build/app-notarize.zip
xcrun notarytool submit build/app-notarize.zip --keychain-profile "headroom" --wait
xcrun stapler staple build/Headroom.app
rm build/app-notarize.zip

# Repackage the DMG around the now-signed app, then sign and notarize the image itself —
# that's the check a downloader actually hits.
./build.sh --dmg
codesign --force --timestamp --sign "$SIGN_ID" build/Headroom.dmg
xcrun notarytool submit build/Headroom.dmg --keychain-profile "headroom" --wait
xcrun stapler staple build/Headroom.dmg
```

Verify before publishing:

```bash
spctl -a -t open --context context:primary-signature -v build/Headroom.dmg   # expect: accepted
xcrun stapler validate build/Headroom.dmg                                     # expect: validated
```

## 4. Publish

Replace the draft release's asset with the notarized `build/Headroom.dmg`, paste the CHANGELOG
section as the release notes, and publish.

## Why notarization matters here

Beyond the Gatekeeper warning: recent macOS refuses to register ad-hoc signed apps for
notifications, so threshold alerts do not work in builds from source. A properly signed release
fixes that for everyone who installs the DMG. Build-from-source users see an "Alerts blocked" row
in the menu explaining why.
