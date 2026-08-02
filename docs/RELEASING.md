# Releasing

> Scaffold — written for real in the docs pass (Phase 5).

1. Update `VERSION` in `build.sh` and add the release entry to `CHANGELOG.md`.
2. Tag and push: `git tag v0.1.0 && git push origin v0.1.0`.
3. `.github/workflows/release.yml` builds an ad-hoc-signed DMG and opens a **draft** release.
4. Sign, notarize, and staple locally (requires an Apple Developer account — CI never sees these
   credentials), then replace the draft's asset and publish.

The notarization commands go here in Phase 5.
