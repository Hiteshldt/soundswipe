#!/bin/bash
# Package an existing app. Run again after stapling a notarization ticket.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/dist/SoundSwipe.app"
if [[ ! -x "$APP/Contents/MacOS/SoundSwipe" ]]; then
    printf 'Build SoundSwipe first with ./scripts/build.sh --universal\n' >&2
    exit 1
fi
codesign --verify --strict "$APP"
STAGING=$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/SoundSwipe.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Read Me.txt" <<'EOF'
SoundSwipe — a little more control over your Mac's audio.

INSTALL
1. Quit SoundSwipe if it is already running.
2. Drag SoundSwipe.app onto the Applications folder beside it.
3. Eject this disk and open SoundSwipe from Applications.
4. Look for the waveform icon in the menu bar; there is no Dock window.

PREVIEW BUILDS
Some preview builds are not notarized. If macOS blocks it, first try opening
the app, then use System Settings > Privacy & Security > Open Anyway
if you trust this download. Do not disable Gatekeeper.

FIRST USE
Play audio in an app, click the waveform, and adjust that app's slider.
Allow system audio access when prompted. Turn off Mix to restore
normal playback. No audio is recorded or uploaded.

HELP AND SOURCE
https://github.com/Hiteshldt/soundswipe
EOF
ditto -c -k --keepParent "$APP" dist/SoundSwipe.zip
hdiutil create -quiet -ov -volname SoundSwipe -srcfolder "$STAGING" -format UDZO -fs HFS+ dist/SoundSwipe.dmg
hdiutil verify -quiet dist/SoundSwipe.dmg
TABS="$STAGING/extension/SoundSwipe-Tabs"
mkdir -p "$TABS"
ditto browser-extension "$TABS"
cp LICENSE "$TABS/LICENSE"
ditto -c -k --keepParent "$TABS" dist/SoundSwipe-Tabs.zip
(
    cd dist
    shasum -a 256 SoundSwipe.dmg > SoundSwipe.dmg.sha256
    shasum -a 256 SoundSwipe.zip > SoundSwipe.zip.sha256
    shasum -a 256 SoundSwipe-Tabs.zip > SoundSwipe-Tabs.zip.sha256
)
printf 'Packaged app DMG, app ZIP, and Chrome companion ZIP with SHA-256 checksums.\n'
