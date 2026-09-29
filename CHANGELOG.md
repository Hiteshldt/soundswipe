# Changelog

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
