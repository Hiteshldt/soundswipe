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
- Optional per-app EQ.
- Reliable browser helper grouping using verified process ancestry.
- More channel layouts, device-specific sample-rate coverage, and audio profiles.

These features are not represented as working controls in the current interface.
