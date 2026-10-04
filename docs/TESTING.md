# Validation

Run `./scripts/test.sh`. Tests exercise DSP gain smoothing, unity-gain transparency, boost limiting, silent output on rejected layouts, non-finite sample handling, peak reset, preferences persistence, and link validation. With only the Command Line Tools installed, `test.sh` adds the Swift Testing framework paths automatically. These tests do not open audio devices or trigger macOS permission prompts.

Read-only local diagnostic:

```sh
dist/SoundSwipe.app/Contents/MacOS/SoundSwipe --diagnostics
```

Render the real panel without Screen Recording permission:

```sh
dist/SoundSwipe.app/Contents/MacOS/SoundSwipe --snapshot /tmp/soundswipe.png
```

## Manual release matrix (must be performed before stable release)

Record actual OS version, machine architecture, device model, sample rate, and pass/fail. Start with built-in output, then wired/USB, HDMI fixed-volume, Bluetooth/AirPods, and a multi-channel interface. Test macOS 14.2+, each supported major release, and the latest stable release on both architectures where supported.

- Output/input lists match System Settings; volumes update after hardware-key and external changes.
- Fixed-volume devices show a clear limitation; their controls do not pretend to work.
- Mix two audible apps, mute one, adjust the other, route them separately. Compare unity-gain playback, clipping, channel separation, and sample counts.
- Play audio in two apps and join a call: only active apps are listed, with correct Playing/Mic status; they remain for ~30 s after stopping. Chrome/Electron helpers appear under their app. Two Chrome instances (`open -na "Google Chrome" --args --user-data-dir=/tmp/second`) and Safari plus another WebKit app appear as separate rows and are controlled independently. `--diagnostics` lists the detected rows.
- Apply each EQ preset, toggle EQ off/on, and set full balance to both sides; confirm no clicks when dragging EQ faders.
- Set each output device's volume from the Output Devices list, including non-default and fixed-volume devices; confirm device icons.
- Mute the microphone from the panel, the right-click menu, and the shortcut; confirm the call hears silence.
- Test 1× / 2× / 3× / 4× boost presets and the 400% slider with loud material: no audible hard clipping; meters turn orange near full scale.
- Scroll over the menu bar icon (trackpad and wheel, natural scrolling on and off); right-click menu output switching; muted icon state.
- First-run audio permission: allow, deny, revoke, then retry. Verify the error and recovery path.
- Close and reopen an app; start additional browser audio helpers while mixing.
- Unplug a routed device, change the default output externally, change sample rate, and switch Bluetooth between playback and call profiles.
- With mixing on, sleep and wake: mixing resumes. Enable "Turn on Mix apps when SoundSwipe opens" and relaunch. Disable mixing, quit normally, and force-quit. Confirm original audio remains usable and no private aggregate survives.
- Keyboard-only navigation, VoiceOver labels, light/dark appearance, reduced transparency, and increased contrast.
- Record conflicting shortcuts and duplicate shortcuts. Switch Settings tabs, switch to another app, and close Settings mid-recording; verify all registered shortcuts resume.
- Register/unregister launch at login from an installed app in Applications.
- Measure idle and active CPU, energy, resident memory, and latency for 0, 1, 5, and 10 adjusted apps. Do not publish unmeasured performance claims.

A successful compile is not an end-to-end audio test. Current results belong in release notes, including any untested combinations.

## 0.5.0 regression checks

Automated coverage includes separate duplex mute restore levels, out-of-range legacy preferences, incomplete snapshot arguments, 4× boost bounds, surround-output rejection, and disabling/re-enabling EQ bands across sample-rate changes.

On hardware, set different input/output levels on one USB interface, mute both, then unmute in either order. Each must restore its own level. With a hardware mute switch, also move volume to zero while muted before unmuting. Verify that the previous level is restored. These hardware writes and Settings focus transitions require manual validation; unit tests exercise the underlying state and DSP only.
