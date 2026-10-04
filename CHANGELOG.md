# Changelog

## 0.5.0 — Preview

- Per-app boost up to 400%, with 1× / 2× / 3× / 4× presets in the app output menu and a correctly positioned 100% marker.
- Independent microphone and speaker mute restore levels on duplex devices; hardware mute now remembers the prior level too.
- Clamp restored volume, balance, and legacy EQ values to supported ranges.
- Bypass EQ bands at or above the device’s Nyquist frequency instead of moving their boost into lower frequencies.
- Reject surround output layouts after a live format change so the controller can stop mixing and restore original playback.
- Cancel shortcut recording when switching Settings tabs or leaving the window, restoring global shortcuts.
- Build universal previews with Command Line Tools as well as Xcode, without requiring `xcbuild`.
- Handle missing snapshot option values without indexing beyond the arguments array.
- Add Ko-fi to About, the README, and GitHub funding configuration.
- Expand DSP and settings regression coverage; document the FineTune-inspired feature roadmap.

## 0.4.0 — Preview

- New Output Devices list: every output with one-click switching, its own volume slider and mute, and device icons (AirPods, headphones, speakers, TV, AirPlay).
- Compact one-line app rows: slider with a 100% marker, segmented level meter, and an output picker showing the device icon.
- Per-app 10-band graphic EQ (32 Hz–16 kHz) with an on/off switch, vertical faders, and 16 presets; center-filled balance slider. Settings from 0.3.x convert automatically.
- Siri's always-on wake-word listener is no longer reported as microphone use.
- About adds ayuvam.com. Snapshot tooling renders active-state screenshots from a throwaway settings store.

## 0.3.1 — Preview

- Separately running copies of the same app (for example a second Chrome instance or profile) now get their own rows and are controlled independently.
- Fixed: WebKit media processes serving different apps (Safari, Mail, other web views) were merged into one row, so adjusting one could affect another.
- Command-line audio tools show their executable name; duplicate names are numbered.
- `--diagnostics` lists detected app rows. Session-only settings for past instances are cleaned up at launch.

## 0.3.0 — Preview

- The Apps list now shows only apps that are playing sound or using the microphone (previously every app that had ever opened audio), with live *Playing* / *Mic* status. Apps stay listed for 30 seconds after going quiet.
- Helper processes are grouped under their parent app (for example Chrome's audio helper shows as Google Chrome).
- Microphone "In use by …" indicator, microphone mute button, right-click menu item, and a new global shortcut.
- Per-app 3-band EQ (bass, mid, treble) with presets, and per-app left/right balance.
- Adjusting an app turns mixing on automatically; saved settings are dimmed while mixing is off.
- Fixed: device and output menus rendered their labels out of order (chevron before the name, oversized text).
- Fixed: invisible direction marks in some app names (for example WhatsApp) affected text layout.
- The popover now resizes to its content; Settings reorganized with descriptions; About shows the app icon and issue link.

## 0.2.0 — Preview

- Per-app volume up to 200% with a soft limiter; unity and lower gain stay bit-transparent.
- Live post-gain level meters for adjusted apps, active only while the panel is open.
- Scroll on the menu bar icon to change output volume; muted icon state; right-click quick menu with output devices, mute, and Mix apps.
- Optional "Turn on Mix apps when SoundSwipe opens"; mixing resumes automatically after sleep.
- About shows developer and source links; version is read from the bundle.
- Fixed: test suite did not compile; tests now run with Xcode or the Command Line Tools.
- Fixed: app icons rendered at twice their intended pixel size (smaller app); release ZIP no longer contains `__MACOSX` files.

## 0.1.0 — Preview

- Initial menu bar app: output/input selection and volume, per-app volume, mute and routing via Core Audio process taps, global shortcuts, launch at login.
