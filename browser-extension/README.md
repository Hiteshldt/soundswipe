# SoundSwipe Tabs

Separate volume and mute for the Chrome tabs you choose. The Mac app still controls Chrome’s overall audio; this companion adds controls inside Chrome for individual tabs.

## Install the preview

1. Download **SoundSwipe-Tabs.zip** from the [SoundSwipe release page](https://github.com/Hiteshldt/soundswipe/releases) and unzip it somewhere you can keep it.
2. Open `chrome://extensions` in Chrome 116 or newer.
3. Turn on **Developer mode**, click **Load unpacked**, and select the **SoundSwipe-Tabs** folder containing `manifest.json`.
4. Pin SoundSwipe Tabs using Chrome’s puzzle-piece menu.

This is an unpacked preview, not a Chrome Web Store release. Other Chromium browsers are not yet validated. Safari and Firefox are not supported by this package.

## Control two tabs

1. Open your first audio tab, click the extension icon, and choose **Control this tab**.
2. Open the second tab and do the same.
3. The extension popup now has a separate volume slider and mute button for each tab.

Controls keep working when you close the popup. **Restore normal audio** releases that tab’s capture and lets Chrome play it normally again. Closing a tab or ending capture removes its control, including from an open popup. Reloading/disabling the extension or restarting Chrome ends capture; controls must be enabled again.

You must invoke the extension from each tab you want to control. It cannot silently start capturing arbitrary tabs. Chrome displays its tab-capture indicator while a tab is controlled. Protected content and browser-internal pages may reject capture. If Chrome already mutes a site, unmute it before trying the controls. Tab title labels reflect the title when control starts.

The sliders run from 0–100%. Use the Mac app’s Chrome gain for overall boost if needed; it affects all Chrome audio together. This preview does not provide per-tab EQ, separate output devices, or tab rows in the Mac popup.

## Privacy

Audio is processed in memory and played back inside Chrome. Nothing is recorded, saved, or uploaded. The extension requests `activeTab`, `tabCapture`, and `offscreen`; it has no blanket website access, content scripts, microphone capture, or analytics.

Implementation follows Chrome’s [tabCapture API](https://developer.chrome.com/docs/extensions/reference/api/tabCapture) and [offscreen-document lifecycle](https://developer.chrome.com/docs/extensions/reference/api/offscreen).

## Validation

Run `node --test Tests/browser-extension/audio-engine.test.mjs` from the repository root (Node 20+).

An optional [browser integration check](../docs/TESTING.md#052-permission-recovery-and-chrome-companion) uses generated audio through the popup and Web Audio graph; capture permission is substituted.

Tests cover independent gains, mute restoration, teardown, duplicate starts, capture/playback failures, cancellation during setup, stale stream-end events, invalid volumes, and streams ending before playback starts. Real toolbar invocation and permission handling, navigation, protected content, and playback on physical hardware still need manual validation before a stable/Web Store release.

Manual check: play two tabs, control each from its toolbar popup, set one to 20% and the other to 80%, mute/unmute either, close the popup, navigate a controlled tab, close one tab, and restore normal audio for the other. Also stop a capture using Chrome’s indicator while the popup is open: its row should disappear, the other tab should keep playing, and its slider should retain keyboard focus. Re-enable the ended tab from its toolbar popup. No tab should go silent merely because the popup closes.

[MIT license](https://github.com/Hiteshldt/soundswipe/blob/main/LICENSE) · [Report a bug](https://github.com/Hiteshldt/soundswipe/issues)
