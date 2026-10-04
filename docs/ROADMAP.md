# Roadmap

## Preview release gate

- Validate process-tap permissions, mixer output fidelity, latency, crash cleanup, and Bluetooth transitions on physical devices.
- Run the manual OS/hardware matrix, including Intel and Apple Silicon.
- Measure idle CPU, resident memory, energy impact, and per-app scaling.
- Sign and notarize release artifacts with a Developer ID.

## Planned features

- A Control Center / menu bar control (WidgetKit `ControlWidget`, macOS 26+) for mute and output switching. This needs an Xcode app-extension target and a signed team ID, so it will arrive with signed releases.

- Auto-pause/resume for supported music players, with explicit Automation consent and ownership tracking so manually paused music is never resumed unexpectedly.
- User-initiated system audio recording with visible recording state and explicit save destination.
- More channel layouts, device-specific sample-rate coverage, and audio profiles.

These features are not represented as working controls in the current interface.

## FineTune-inspired direction

SoundSwipe aims for the same convenient menu bar workflow, while keeping its own implementation and MIT license. This is a capability roadmap, not a claim of feature parity.

| Capability | SoundSwipe today | Next step |
| --- | --- | --- |
| Per-app volume and boost | 0–400%, mute, 1× / 2× / 3× / 4× presets | Hardware validation across supported outputs |
| EQ | 10 bands, 16 presets, balance, EQ bypass | Save and name custom presets |
| Routing | One output per app; fallback and reconnect | Simultaneous multi-device output with clock/drift handling |
| App visibility | Active/recent apps and adjusted running apps | Pin and ignore apps with explicit tap teardown |
| Devices | Output/input selection, hardware volume, microphone mute | Priority order, hidden devices, device inspector |
| Headphone correction | Not implemented | AutoEQ profile import and per-device processing |
| Keyboard | Recorded global shortcuts for system controls | Per-app hotkeys and full popup row navigation |
| Appearance | Native system light/dark appearance | Explicit theme, density, and menu bar icon choices |
| Distribution | Universal preview ZIP, ad-hoc signed | Developer ID signing, notarization, then stable release and Homebrew |

Prioritize audio reliability and distribution first, followed by app visibility, saved EQ presets, and keyboard navigation. Multi-device routing and AutoEQ need separate DSP design and hardware testing.
