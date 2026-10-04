import { TabAudioEngine } from './audio-engine.js';
const engine = new TabAudioEngine({
  getUserMedia: constraints => navigator.mediaDevices.getUserMedia(constraints),
  AudioContext
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
