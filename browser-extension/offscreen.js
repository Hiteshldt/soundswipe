import { TabAudioEngine } from './audio-engine.js';
let knownTabs = new Set();
const engine = new TabAudioEngine({
  getUserMedia: constraints => navigator.mediaDevices.getUserMedia(constraints),
  AudioContext,
  onChanged: sessions => {
    const currentTabs = new Set(sessions.map(session => session.tabId));
    const endedTabs = [...knownTabs].filter(tabId => !currentTabs.has(tabId));
    knownTabs = currentTabs;
    if (endedTabs.length) {
      // Update an open popup when Chrome releases capture or a tab closes.
      // A closed popup is normal; capture must continue without a receiver.
      void chrome.runtime.sendMessage({ target: 'popup', action: 'tabsEnded', tabIds: endedTabs }).catch(() => {});
    }
  }
});
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || message.target !== 'offscreen') return;
  (async () => {
    switch (message.action) {
      case 'list': return engine.snapshot();
      case 'start': return engine.start(message.tabId, message.streamId, message.title);
      case 'volume': return engine.setVolume(message.tabId, message.value);
      case 'mute': return engine.setMuted(message.tabId, message.muted);
      case 'stop': return engine.stop(message.tabId);
      default: throw new Error('Unknown tab control.');
    }
  })().then(sessions => respond({ sessions }), error => respond({ error: error.message }));
  return true;
});
