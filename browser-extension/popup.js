const startButton = document.querySelector('#start');
const errorBox = document.querySelector('#error');
let activeTab;
let starting = false;
function updateControls() {
  const rows = [...document.querySelectorAll('.tab')];
  document.querySelector('#empty').hidden = rows.length > 0;
  const controlled = rows.some(row => Number(row.dataset.tabId) === activeTab?.id);
  startButton.textContent = starting ? 'Starting…' : controlled ? 'This tab is controlled' : 'Control this tab';
  startButton.disabled = starting || controlled || !activeTab;
}
chrome.runtime.onMessage.addListener((message, sender) => {
  if (sender.id !== chrome.runtime.id || sender.url !== chrome.runtime.getURL('offscreen.html') || message.target !== 'popup' || message.action !== 'tabsEnded' || !Array.isArray(message.tabIds)) return;
  for (const row of document.querySelectorAll('.tab')) {
    if (message.tabIds.includes(Number(row.dataset.tabId))) row.remove();
  }
  // Keep every remaining slider node and its keyboard/drag focus intact.
  updateControls();
});
function showError(error) { errorBox.textContent = error?.message || String(error); errorBox.hidden = false; }
async function request(action, data = {}) {
  const result = await chrome.runtime.sendMessage({ target: 'worker', action, ...data });
  if (!result) throw new Error('Tab audio is unavailable. Reopen the extension to retry.');
  if (result.error) throw new Error(result.error);
  return result.sessions;
}
function render(sessions) {
  const container = document.querySelector('#sessions');
  container.replaceChildren();
  for (const session of sessions) {
    const row = document.createElement('section'); row.className = 'tab'; row.dataset.tabId = String(session.tabId);
    const title = document.createElement('p'); title.className = 'title'; title.textContent = session.title; title.title = session.title;
    const controls = document.createElement('div'); controls.className = 'controls';
    const mute = document.createElement('button'); mute.textContent = session.muted ? 'Unmute' : 'Mute';
    mute.setAttribute('aria-label', `${mute.textContent} ${session.title}`);
    mute.setAttribute('aria-pressed', String(session.muted));
    mute.addEventListener('click', async () => {
      try { render(await request('mute', { tabId: session.tabId, muted: !session.muted })); } catch (error) { showError(error); }
    });
    const slider = document.createElement('input'); slider.type = 'range'; slider.min = '0'; slider.max = '100'; slider.step = '1'; slider.value = String(Math.round(session.volume * 100));
    slider.setAttribute('aria-label', `${session.title} volume`);
    const value = document.createElement('output'); value.textContent = `${session.muted ? 0 : slider.value}%`;
    slider.addEventListener('input', async () => {
      const volume = Number(slider.value) / 100; value.textContent = `${slider.value}%`;
      if (volume > 0) {
        session.muted = false; mute.textContent = 'Mute'; mute.setAttribute('aria-pressed', 'false');
        mute.setAttribute('aria-label', `Mute ${session.title}`);
      }
      try { await request('volume', { tabId: session.tabId, value: volume }); } catch (error) { showError(error); }
    });
    const stop = document.createElement('button'); stop.className = 'stop'; stop.textContent = 'Restore normal audio';
    stop.addEventListener('click', async () => {
      try { render(await request('stop', { tabId: session.tabId })); } catch (error) { showError(error); }
    });
    controls.append(mute, slider, value); row.append(title, controls, stop); container.append(row);
  }
  updateControls();
}
startButton.addEventListener('click', async () => {
  starting = true; updateControls(); errorBox.hidden = true;
  try { render(await request('start', { tabId: activeTab.id })); }
  catch (error) { showError(error); }
  finally { starting = false; updateControls(); }
});
(async () => {
  [activeTab] = await chrome.tabs.query({ active: true, currentWindow: true });
  document.querySelector('#active-title').textContent = activeTab?.title || 'Current tab';
  render(await request('list'));
})().catch(error => { showError(error); updateControls(); });
