let creating;
const starting = new Map();
const offscreenURL = chrome.runtime.getURL('offscreen.html');
async function hasAudioDocument() {
  return (await chrome.runtime.getContexts({ contextTypes: ['OFFSCREEN_DOCUMENT'], documentUrls: [offscreenURL] })).length > 0;
}
async function ensureAudioDocument() {
  if (await hasAudioDocument()) return;
  if (!creating) {
    creating = chrome.offscreen.createDocument({
      url: 'offscreen.html', reasons: ['USER_MEDIA'],
      justification: 'Keep user-selected tab audio playing through independent volume controls while the popup is closed.'
    }).finally(() => { creating = undefined; });
  }
  await creating;
}
async function audio(message) {
  const reply = await chrome.runtime.sendMessage({ ...message, target: 'offscreen' });
  if (!reply) throw new Error('Tab audio is unavailable. Try again.');
  if (reply.error) throw new Error(reply.error);
  return reply;
}
async function start(tabId) {
  if (starting.has(tabId)) return starting.get(tabId);
  const promise = (async () => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (!tab || tab.id !== tabId) throw new Error('Open that tab and click the extension there first.');
    await ensureAudioDocument();
    const existing = await audio({ action: 'list' });
    if (existing.sessions.some(session => session.tabId === tabId)) return existing;
    const streamId = await chrome.tabCapture.getMediaStreamId({ targetTabId: tabId });
    return audio({ action: 'start', tabId, streamId, title: tab.title || 'Tab' });
  })();
  starting.set(tabId, promise);
  try { return await promise; } finally { starting.delete(tabId); }
}
chrome.runtime.onMessage.addListener((message, sender, respond) => {
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('popup.html') || message.target !== 'worker') return;
  (async () => {
    if (message.action === 'start') return start(message.tabId);
    if (!(await hasAudioDocument())) {
      if (message.action === 'list' || message.action === 'stop') return { sessions: [] };
      throw new Error('Control this tab first.');
    }
    if (!['list', 'volume', 'mute', 'stop'].includes(message.action)) throw new Error('Unknown tab control.');
    return audio(message);
  })().then(respond, error => respond({ error: error.message }));
  return true;
});
chrome.tabs.onRemoved.addListener(tabId => {
  void (async () => {
    // Wait for any pending start, then stop it too if the tab closed mid-capture.
    if (starting.has(tabId)) await starting.get(tabId).catch(() => {});
    if (await hasAudioDocument()) await audio({ action: 'stop', tabId });
  })().catch(() => {});
});
