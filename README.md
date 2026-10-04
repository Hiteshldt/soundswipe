<p align="center">
  <img src="docs/images/icon.png" width="80" height="80" alt="SoundSwipe icon">
</p>

<h1 align="center">SoundSwipe</h1>

<p align="center">A little more control over your Mac’s audio.<br>
Per-app volume, EQ, and output routing from the menu bar.</p>

<p align="center">
  <a href="https://github.com/Hiteshldt/soundswipe/actions/workflows/ci.yml"><img src="https://github.com/Hiteshldt/soundswipe/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/Hiteshldt/soundswipe/releases"><img src="https://img.shields.io/github/v/release/Hiteshldt/soundswipe?include_prereleases&label=preview" alt="Preview release"></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-blue" alt="macOS 14.2 or newer">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

<p align="center"><a href="https://github.com/Hiteshldt/soundswipe/releases"><b>Download for macOS</b></a> · <a href="#install">Install</a> · <a href="https://ko-fi.com/hiteshgupta">Buy me a coffee</a></p>

<p align="center"><img src="docs/images/panel.png" width="520" alt="SoundSwipe showing device controls and per-app equalizer"></p>

Free and open source. Built with SwiftUI, AppKit, and Core Audio. No account, driver, analytics, or audio uploads.

> **Preview:** per-app mixing still needs wider testing across devices and macOS versions. Downloads are ad-hoc signed and not notarized yet.

## Install

Requires **macOS 14.2 or newer**, on Apple Silicon or Intel.

1. Download **SoundSwipe.dmg** from the [release page](https://github.com/Hiteshldt/soundswipe/releases).
2. Open it and drag **SoundSwipe.app** onto **Applications**.
3. Eject the disk, then open SoundSwipe from Applications.
4. Look for the **waveform icon in your menu bar**. There is no Dock window.

If macOS blocks this preview, try opening the app first, then go to **System Settings → Privacy & Security → Open Anyway** if you trust the download. See [Apple’s instructions](https://support.apple.com/en-us/102445). You do not need to disable Gatekeeper.

A ZIP is also available: unzip it and move the app to Applications. When updating, quit the existing app before replacing it. Your saved settings stay in place.

## First use

1. Play sound in an app and click SoundSwipe’s menu bar icon.
2. Adjust that app’s volume. Allow system-audio access when macOS asks.
3. Use its output menu to pick a device or a 1× / 2× / 3× / 4× boost preset.
4. Open the slider icon for EQ and balance.

Turn off **Mix** to restore normal app playback. Device volume and switching work without capture permission. Audio is processed locally and never recorded or uploaded.

## What it does

- **Per-app volume and mute**, from 0–400%, with a soft limiter for boost.
- **10-band EQ**, 16 presets, EQ bypass, and left/right balance for each app.
- **Output routing** to one device per app, with fallback when a device disconnects.
- **Speaker and microphone controls**, device switching, and microphone-use indicators.
- **Live level meters** while the panel is open.
- **Keyboard shortcuts** for showing the panel, system volume, mute, microphone mute, and next output.
- **Scroll over the menu bar icon** for volume; right-click for quick controls.
- **Saved mixes and launch at login**, configured from the gear button.

<p align="center">
  <img src="docs/images/panel-light.png" width="420" alt="SoundSwipe in light mode">
  <img src="docs/images/settings-1.png" width="360" alt="Keyboard shortcut settings">
</p>

## If something isn’t working

| What you see | What to try |
| --- | --- |
| No app window | Click the waveform in the menu bar. SoundSwipe runs there. |
| No apps listed | Start playing sound. Apps appear while playing or using the microphone, and stay briefly after stopping. |
| Per-app controls fail | Check SoundSwipe under **System Settings → Privacy & Security → Screen & System Audio Recording**. Permission labels vary by macOS version. Restart SoundSwipe after changing permission. |
| “Fixed volume” | That output doesn’t expose a volume control to macOS. Use its own controls. |
| Audio trouble after routing | Turn off **Mix** to restore normal playback, then report your device, macOS version, and the error shown. |
| Launch at login doesn’t work | Install in Applications first. Check **System Settings → General → Login Items** for approval. |

[Report a bug](https://github.com/Hiteshldt/soundswipe/issues/new/choose). Include your macOS version, audio device, and the steps that caused it.

## Current limits

Mixing supports stereo, tightly packed 32-bit float PCM routes. Unsupported formats stop mixing and show an error. Some protected sources cannot be captured; Bluetooth call profiles and conferencing apps still need hardware testing.

Browser tabs share their browser’s audio stream, so SoundSwipe controls the app rather than individual tabs. Microphone volume and mute apply to the input device, not individual apps. There is no recording, automatic updater, multi-device output, or AutoEQ yet.

See the [roadmap](docs/ROADMAP.md), [changelog](CHANGELOG.md), [architecture](docs/ARCHITECTURE.md), and [test checklist](docs/TESTING.md).

## Build from source

```sh
git clone https://github.com/Hiteshldt/soundswipe.git
cd soundswipe
./scripts/test.sh
./scripts/build.sh --universal
open dist/SoundSwipe.app
```

Requires Swift 5.10+ with Xcode 16+ or Command Line Tools. The build produces the app, a drag-to-Applications DMG, a ZIP, and SHA-256 checksums in `dist/`. Omit `--universal` to build for your current architecture.

Run the bundled app to test permissions and login items; `swift run` lacks its bundle metadata. See [release instructions](docs/RELEASING.md) for signing and notarization.

## Help out

Try it, [tell me what broke](https://github.com/Hiteshldt/soundswipe/issues), or read [CONTRIBUTING.md](CONTRIBUTING.md) if you’d like to change something. Security reports go through [SECURITY.md](SECURITY.md).

If it helps you, you can [buy me a coffee](https://ko-fi.com/hiteshgupta). Every feature stays free.

Original code inspired by [Background Music](https://github.com/kyleneideck/BackgroundMusic) and [SoundSource](https://rogueamoeba.com/soundsource/); no code or assets from either, and no affiliation.

[MIT license](LICENSE) · Made by Hitesh Gupta · [Website](https://hitesh.ayuvam.com)
