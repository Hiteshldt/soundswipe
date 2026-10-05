# Releases and repository setup

Repository: https://github.com/Hiteshldt/soundswipe. Do not publish a stable release before completing the manual audio checks in TESTING.md.

## Repository

Suggested description: **Lightweight native macOS menu bar audio controller with per-app volume, routing, and keyboard shortcuts.**

Suggested topics: `macos`, `swift`, `swiftui`, `coreaudio`, `audio`, `menu-bar`, `volume-control`, `audio-routing`, `open-source`.

Upload `docs/images/social-preview.png` in **Settings → General → Social preview**. Add a Homebrew cask only after a stable, signed download exists. Keep the description and feature claims aligned with the actual release.

## Preview releases

Bump `CFBundleShortVersionString` and `CFBundleVersion` in `Resources/Info.plist`, add a CHANGELOG entry, then push a tag:

```sh
git tag v0.5.6 && git push origin v0.5.6
```

The release workflow runs tests, builds a universal ad-hoc-signed app, and publishes a GitHub pre-release with the app DMG, app ZIP, optional Chrome companion ZIP, and their SHA-256 checksums. The tag must match the version in Info.plist.

## Attribution

Developer links (`DeveloperGitHub`, `DeveloperTwitter`) and `RepositoryURL` live in Resources/Info.plist and appear in Settings → About.

## Signing and notarization

The local build uses an ad-hoc signature. To produce a distributable app with an existing Developer ID certificate:

```sh
SIGNING_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' ./scripts/build.sh --universal
xcrun notarytool submit dist/SoundSwipe.zip --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/SoundSwipe.app
xcrun stapler validate dist/SoundSwipe.app
spctl --assess --type execute --verbose dist/SoundSwipe.app
./scripts/package.sh
xcrun notarytool submit dist/SoundSwipe.dmg --keychain-profile YOUR_PROFILE --wait
xcrun stapler staple dist/SoundSwipe.dmg
xcrun stapler validate dist/SoundSwipe.dmg
(cd dist && shasum -a 256 SoundSwipe.dmg > SoundSwipe.dmg.sha256)
```

Use an existing securely stored notarization credential. Never commit signing certificates, passwords, API keys, provisioning material, or local keychain exports. Increment the version and build number in Info.plist for releases and keep UI/diagnostic versions consistent.

The CI workflow runs tests and uploads a preview artifact on every push. Tag builds are ad-hoc signed, not notarized, and are marked as pre-releases.
