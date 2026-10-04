// Optional integration check: real popup, worker, offscreen document and Web Audio.
// Capture/toolbar authorization is substituted with generated test streams;
// actual Chrome permission prompts and source capture still require a manual check.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
async function until(check, label) {
  for (let i = 0; i < 60; i++) { const result = await check(); if (result) return result; await delay(100); }
  throw new Error(`Timed out: ${label}`);
}
async function connect(target) {
  const ws = new WebSocket(target.webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.addEventListener('open', resolve, { once: true }); ws.addEventListener('error', reject, { once: true }); });
  let nextId = 1;
  const pending = new Map();
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    const result = pending.get(message.id);
    if (!result) return;
    pending.delete(message.id);
    if (message.error || message.result?.exceptionDetails) result.reject(new Error(JSON.stringify(message.error || message.result.exceptionDetails)));
    else result.resolve(message.result);
  });
  return {
    call(method, params = {}) { return new Promise((resolve, reject) => { const id = nextId++; pending.set(id, { resolve, reject }); ws.send(JSON.stringify({ id, method, params })); }); },
    async evaluate(expression) {
      const result = await this.call('Runtime.evaluate', { expression, awaitPromise: true, returnByValue: true, userGesture: true });
      return result.result.value;
    },
    close() { ws.close(); }
  };
}
(async () => {
  const server = http.createServer((request, response) => {
    response.setHeader('Content-Type', 'text/html');
    response.end(`<!doctype html><title>Test tab ${request.url === '/a' ? 'A' : 'B'}</title><p>Local test page</p>`);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const profile = fs.mkdtempSync(path.join(os.tmpdir(), 'soundswipe-browser.'));
  let context;
  const sockets = [];
  try {
    const extension = path.resolve(__dirname, '../../browser-extension');
    const executablePath = process.env.SOUNDSWIPE_TEST_BROWSER;
    context = await chromium.launchPersistentContext(profile, {
      ...(executablePath ? { executablePath } : { channel: 'chromium' }), headless: true,
      args: [`--disable-extensions-except=${extension}`, `--load-extension=${extension}`, '--remote-debugging-port=0', '--autoplay-policy=no-user-gesture-required']
    });
    const worker = context.serviceWorkers()[0] || await context.waitForEvent('serviceworker');
    const extensionId = worker.url().split('/')[2];
    const pageA = await context.newPage();
    await pageA.goto(`http://127.0.0.1:${server.address().port}/a`);
    await worker.evaluate(async () => {
      // Only the test process replaces this API; the shipped worker is unchanged.
      chrome.tabCapture.getMediaStreamId = async ({ targetTabId }) => `test-stream-${targetTabId}`;
      await chrome.offscreen.createDocument({ url: 'offscreen.html', reasons: ['USER_MEDIA'], justification: 'Synthetic-stream integration test.' });
    });
    const port = fs.readFileSync(path.join(profile, 'DevToolsActivePort'), 'utf8').split('\n')[0];
    const targets = async () => (await fetch(`http://127.0.0.1:${port}/json/list`)).json();
    const findTarget = suffix => until(async () => (await targets()).find(target => target.url === `chrome-extension://${extensionId}/${suffix}`), suffix);
    const offscreen = await connect(await findTarget('offscreen.html')); sockets.push(offscreen);
    await offscreen.evaluate(`(async () => {
      navigator.mediaDevices.getUserMedia = async () => {
        const context = new AudioContext();
        const oscillator = context.createOscillator();
        oscillator.frequency.value = 220;
        const amplitude = context.createGain(); amplitude.gain.value = 0.4;
        const destination = context.createMediaStreamDestination();
        oscillator.connect(amplitude); amplitude.connect(destination); oscillator.start();
        await context.resume();
        return destination.stream;
      };
      const { TabAudioEngine } = await import('./audio-engine.js');
      const original = TabAudioEngine.prototype.start;
      TabAudioEngine.prototype.start = function(...args) { window.testEngine = this; return original.apply(this, args); };
    })()`);
    async function popup() {
      await worker.evaluate(() => chrome.action.openPopup());
      const socket = await connect(await findTarget('popup.html')); sockets.push(socket);
      await until(() => socket.evaluate('document.querySelector("#start").textContent === "Control this tab" || document.querySelector("#start").textContent === "This tab is controlled"'), 'popup ready');
      return socket;
    }
    const state = () => offscreen.evaluate('window.testEngine?.snapshot() || []');
    let view = await popup();
    await view.evaluate('document.querySelector("#start").click()');
    await until(async () => (await state()).length === 1, 'first tab starts');
    await view.evaluate('window.close()');
    const pageB = await context.newPage();
    await pageB.goto(`http://127.0.0.1:${server.address().port}/b`);
    view = await popup();
    await view.evaluate('document.querySelector("#start").click()');
    await until(async () => (await state()).length === 2, 'second tab starts');
    await until(() => view.evaluate('document.querySelectorAll(".tab").length === 2'), 'two rows');
    await view.evaluate(`(() => {
      const sliders = document.querySelectorAll('input[type=range]');
      sliders[0].value = '20'; sliders[0].dispatchEvent(new Event('input', { bubbles: true }));
      sliders[1].value = '80'; sliders[1].dispatchEvent(new Event('input', { bubbles: true }));
    })()`);
    await until(async () => { const sessions = await state(); return sessions[0]?.volume === .2 && sessions[1]?.volume === .8; }, 'independent slider values');
    await offscreen.evaluate(`(() => {
      window.testAnalysers = [...testEngine.sessions.values()].map(session => {
        const analyser = session.context.createAnalyser(); analyser.fftSize = 2048;
        const sink = session.context.createGain(); sink.gain.value = 0;
        session.gain.connect(analyser); analyser.connect(sink); sink.connect(session.context.destination);
        return analyser;
      });
    })()`);
    const levels = () => offscreen.evaluate(`testAnalysers.map(analyser => {
      const samples = new Float32Array(analyser.fftSize); analyser.getFloatTimeDomainData(samples);
      return Math.sqrt(samples.reduce((sum, value) => sum + value * value, 0) / samples.length);
    })`);
    const rms = await until(async () => { const values = await levels(); return values[0] > .01 && values[1] / values[0] > 3.7 && values[1] / values[0] < 4.3 ? values : false; }, '20%/80% audio signal ratio');
    const image = await view.call('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(path.join(os.tmpdir(), 'soundswipe-tabs-preview.png'), Buffer.from(image.data, 'base64'));
    await view.evaluate('document.querySelector(".tab .controls button").click()');
    await until(async () => { const sessions = await state(); return sessions[0]?.muted && !sessions[1]?.muted; }, 'mute only first tab');
    await until(async () => { const values = await levels(); return values[0] < .001 && values[1] > .1; }, 'only first output is silent');
    await view.evaluate('window.close()');
    assert.equal((await state()).length, 2);
    assert.equal(await offscreen.evaluate('[...testEngine.sessions.values()].every(session => session.context.state === "running")'), true);
    view = await popup();
    await until(() => view.evaluate('document.querySelectorAll(".tab").length === 2'), 'rows after reopen');
    await view.evaluate('document.querySelector(".tab .stop").click()');
    await until(async () => (await state()).length === 1, 'restore one tab');
    await view.evaluate('window.close()');
    await pageB.close();
    await until(async () => (await state()).length === 0, 'tab close cleans up');
    console.log(`Browser integration passed: separate 20%/80% signals (RMS ${rms.map(value => value.toFixed(4)).join(', ')}), mute, popup persistence, restore, and tab-close cleanup.`);
    console.log('Capture/toolbar permission was substituted with synthetic test streams; real permission flow still needs manual validation.');
  } finally {
    sockets.forEach(socket => socket.close());
    if (context) await context.close();
    await new Promise(resolve => server.close(resolve));
    fs.rmSync(profile, { recursive: true, force: true });
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
