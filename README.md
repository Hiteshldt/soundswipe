<p align="center">
  <img src="docs/images/icon.png" width="96" height="96" alt="SoundSwipe icon">
</p>

<h1 align="center">SoundSwipe</h1>

<p align="center"><b>A little more control over your Mac’s audio.</b><br>
Per-app volume, boost, and output routing — from a tiny native menu bar app.</p>

<p align="center">
  <a href="https://github.com/Hiteshldt/soundswipe/actions/workflows/ci.yml"><img src="https://github.com/Hiteshldt/soundswipe/actions/workflows/ci.yml/badge.svg" alt="Build"></a>
  <a href="https://github.com/Hiteshldt/soundswipe/releases"><img src="https://img.shields.io/github/v/release/Hiteshldt/soundswipe?include_prereleases&label=download" alt="Download"></a>
  <img src="https://img.shields.io/badge/macOS-14.2%2B-blue" alt="macOS 14.2+">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license"></a>
</p>

SoundSwipe is a free, open-source macOS menu bar app for output and input control, individual app volumes, volume boost, and per-app audio routing — an alternative in the spirit of [Background Music](https://github.com/kyleneideck/BackgroundMusic) and [SoundSource](https://rogueamoeba.com/soundsource/). It is built with SwiftUI, AppKit, Core Audio, and a tiny C audio kernel: a ~2 MB app with no Electron, package dependencies, account, telemetry, or network access.

> **Preview:** device controls and the interface are implemented and tested. Per-app mixing uses Apple’s Core Audio process taps and still needs wider validation across hardware and macOS releases. Preview builds are not yet notarized.

<p align="center"><img src="docs/images/panel.png" width="368" alt="SoundSwipe menu bar panel"></p>

## Features

- **Menu bar panel** with native materials, light/dark appearance, and VoiceOver labels.
- **Output and microphone switching**, output volume, mute, and input gain — with a clear message for fixed-volume devices.
- **Per-app volume from 0–200%.** Boost above 100% passes through a soft limiter so it never hard-clips; at or below 100% audio is untouched.
- **Per-app output routing** — send music to headphones while calls stay on speakers. No driver or kernel extension to install.
- **Live level meters** for every adjusted app (only while the panel is open).
- **Scroll on the menu bar icon** to change volume; the icon shows when output is muted. **Right-click** for a quick menu with output devices, mute, and Mix apps.
- **Global keyboard shortcuts** you record yourself: show panel, mute, volume up/down, next output. No Accessibility permission needed.
- **Remembers your mix** per app; disconnected routes fall back to the current output. Optionally turns mixing on at launch, and restores it after sleep.
- **Launch at login.**
- **Lightweight by design:** Core Audio notifications instead of polling, meters that stop when the panel closes, and routes only for apps you have changed.

## Install

1. Download `SoundSwipe.zip` from the [latest release](https://github.com/Hiteshldt/soundswipe/releases) and move **SoundSwipe.app** to Applications.
2. Preview builds are not notarized yet. On first launch macOS will block the app; open **System Settings → Privacy & Security** and click **Open Anyway**. Or build it yourself (below).

Requires **macOS 14.2 or newer**, Apple Silicon or Intel.

## Use

1. Click the waveform in the menu bar. Pick a speaker/headphone or microphone.
2. Turn on **Mix apps**. Play sound in an app, then drag its slider or choose an output from its row.
3. Allow system-audio access when macOS asks. Audio is processed locally and never saved or sent anywhere.
4. Open the gear for shortcuts, launch at login, and mix-at-launch.
5. Turn off Mix apps to hand every app back to normal macOS playback instantly.

System controls do not need any permission. Changing the system output changes the default device; apps with their own in-app route may keep using it.

## Build from source

```sh
git clone https://github.com/Hiteshldt/soundswipe.git
cd soundswipe
./scripts/test.sh
./scripts/build.sh            # or --universal for Intel + Apple Silicon
open dist/SoundSwipe.app
```

Needs Swift 5.10+ (Xcode 16+ or the Command Line Tools). You can also open `Package.swift` in Xcode. Run the **bundled app** from `dist/` to test permissions and login items; `swift run` lacks the bundle metadata macOS requires.

## Current limits

- Mixing handles stereo, 32-bit float PCM routes; other layouts stop mixing and report an error. No EQ or recording yet.
- Browser/helper audio processes may appear under the identity macOS reports; SoundSwipe does not guess process ownership.
- Some protected content cannot be captured, and conferencing apps or Bluetooth call profiles need more hardware testing.
- SoundSwipe is a menu bar app, not a Control Center module. No automatic updater yet.

See [architecture](docs/ARCHITECTURE.md), [validation](docs/TESTING.md), the [roadmap](docs/ROADMAP.md), and the [changelog](CHANGELOG.md).

## Contributing

Issues and pull requests are welcome — read [CONTRIBUTING.md](CONTRIBUTING.md). Report security issues privately as described in [SECURITY.md](SECURITY.md).

SoundSwipe is original code inspired by Background Music and SoundSource; it includes none of their code or assets and is not affiliated with either. Audio routing uses Apple’s [Core Audio process taps](https://developer.apple.com/documentation/coreaudio/capturing-system-audio-with-core-audio-taps).

## License

[MIT](LICENSE) · Made by Hitesh Gupta · [GitHub](https://github.com/Hiteshldt) · [X](https://x.com/hit3sh3d)
