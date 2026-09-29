# Changelog

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
