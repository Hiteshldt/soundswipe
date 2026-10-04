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

## 0.5.1 packaging and format checks

Automated tests cover planar stereo-to-interleaved channel separation and rejection of padded PCM strides, big-endian float, and invalid sample rates. All snapshot runs use isolated preferences. Process grouping excludes other SoundSwipe copies from both app controls and microphone-use indicators. Route format comparisons detect a layout change even when the device and stream IDs stay the same.

Verify the DMG with `hdiutil verify dist/SoundSwipe.dmg`, mount it read-only, check the Applications link and bundled version, and verify the mounted app signature. Copy the app to a temporary folder and run `--diagnostics` from that copy. Confirm both architecture slices with `lipo -verify_arch arm64 x86_64`.

On hardware, change the physical device sample rate and switch a Bluetooth device into and out of its call profile. The route must rebuild or stop with an unsupported-format error. Perform the full manual matrix before claiming stable audio support.

## 0.5.2 permission recovery and Chrome companion

After denying audio capture or encountering an unsupported route, drag the app slider again: SoundSwipe must save the level without repeatedly requesting capture. Grant access in Privacy & Security and click Retry or explicitly turn Mix on. A successful route should keep playing while its slider moves, including dragging through 100% and back; its existing tap must remain until Mix is turned off. Test permission renewal after an app update separately; preview signatures are ad-hoc and do not establish a stable Developer ID identity. Verify Donate in the popup opens https://ko-fi.com/hiteshgupta.

Run `node --test Tests/browser-extension/audio-engine.test.mjs` (Node 20+) for independent tab gain/mute, capture failures, cancellation, and teardown. Install the companion following [its README](../browser-extension/README.md) and perform the real toolbar/capture checks there. Verify `SoundSwipe-Tabs.zip` contains a top-level SoundSwipe-Tabs folder with manifest.json, scripts, icons, README, and LICENSE. Check its SHA-256 file.

An optional integration check uses Node 22+, Playwright, and an isolated Chromium profile:

```sh
node Tests/browser-extension/browser-smoke.cjs
```

Install Playwright and its Chromium browser separately, or point PLAYWRIGHT_MODULE at the installed module and SOUNDSWIPE_TEST_BROWSER at a compatible Chromium executable. The test measures generated audio through the real popup, worker, offscreen document, and Web Audio graph: independent 20%/80% levels, mute, popup persistence, restore, and closed-tab cleanup. It substitutes Chrome capture authorization and sources; it does **not** validate real toolbar grants, source capture, protected media, or physical output. No user browser profile is used.
