import test from 'node:test';
import assert from 'node:assert/strict';
import { TabAudioEngine } from '../../browser-extension/audio-engine.js';

class Track {
  stopped = false; readyState = 'live';
  addEventListener(_, callback) { this.ended = callback; }
  stop() { this.stopped = true; this.readyState = 'ended'; }
}
class Context {
  static instances = [];
  state = 'suspended'; currentTime = 0; destination = {};
  constructor() { Context.instances.push(this); }
  createMediaStreamSource() { return { connect() {}, disconnect() {} }; }
  createGain() {
    const node = { gain: { value: 1, setTargetAtTime(value) { this.value = value; } }, connect() {}, disconnect() {} };
    this.gain = node; return node;
  }
  async resume() { this.state = 'running'; }
  async close() { this.state = 'closed'; }
}
function fixture(options = {}) {
  const streams = [];
  const engine = new TabAudioEngine({
    AudioContext: Context,
    getUserMedia: async constraints => {
      assert.equal(constraints.video, false);
      assert.equal(constraints.audio.mandatory.chromeMediaSource, 'tab');
      const track = new Track(); const stream = { getTracks: () => [track], getAudioTracks: () => [track] };
      streams.push({ stream, track }); return stream;
    }, ...options
  });
  return { engine, streams };
}

test('two tabs have independent gains and mute states', async () => {
  const { engine } = fixture();
  await engine.start(1, 'one', 'Music'); await engine.start(2, 'two', 'Video');
  engine.setVolume(1, .25); engine.setMuted(2, true);
  assert.equal(engine.sessions.get(1).gain.gain.value, .25);
  assert.equal(engine.sessions.get(2).gain.gain.value, 0);
  assert.equal(engine.snapshot()[1].volume, 1);
  engine.setMuted(2, false);
  assert.equal(engine.sessions.get(2).gain.gain.value, 1);
  assert.equal(engine.sessions.get(1).gain.gain.value, .25);
  await engine.stop(1); await engine.stop(2);
});

test('restoring one tab releases its stream without touching the other', async () => {
  const { engine, streams } = fixture();
  await engine.start(1, 'one', 'Music'); await engine.start(2, 'two', 'Video');
  engine.setVolume(2, .6);
  const context = engine.sessions.get(1).context;
  await engine.stop(1);
  assert.equal(streams[0].track.stopped, true);
  assert.equal(context.state, 'closed');
  assert.equal(streams[1].track.stopped, false);
  assert.equal(engine.sessions.get(2).gain.gain.value, .6);
  await engine.stop(2);
});

test('concurrent starts of one tab create just one stream', async () => {
  const { engine, streams } = fixture();
  await Promise.all([engine.start(1, 'one', 'Tab'), engine.start(1, 'two', 'Tab')]);
  assert.equal(streams.length, 1); assert.equal(engine.snapshot().length, 1);
  await engine.stop(1);
});

test('capture failure leaves no session and can be retried', async () => {
  const { engine } = fixture({ getUserMedia: async () => { throw new Error('Denied'); } });
  await assert.rejects(engine.start(1, 'one', 'Tab'), /Denied/);
  assert.deepEqual(engine.snapshot(), []); assert.equal(engine.pending.size, 0);
});

test('playback failure releases capture and closes its context', async () => {
  class FailingContext extends Context { async resume() { throw new Error('Playback unavailable'); } }
  const { engine, streams } = fixture({ AudioContext: FailingContext });
  await assert.rejects(engine.start(1, 'one', 'Tab'), /Playback unavailable/);
  assert.equal(streams[0].track.stopped, true);
  assert.equal(Context.instances.at(-1).state, 'closed');
  assert.deepEqual(engine.snapshot(), []);
});

test('a stop during capture setup cannot leave a route behind', async () => {
  let release;
  const track = new Track();
  const { engine } = fixture({ getUserMedia: () => new Promise(resolve => { release = resolve; }) });
  const starting = engine.start(1, 'one', 'Tab');
  const stopping = engine.stop(1);
  release({ getTracks: () => [track], getAudioTracks: () => [track] });
  await assert.rejects(starting, /cancelled/); await stopping;
  assert.equal(track.stopped, true); assert.deepEqual(engine.snapshot(), []);
});

test('an ended stream removes the tab; stale end events cannot stop a new route', async () => {
  const { engine, streams } = fixture();
  await engine.start(1, 'one', 'Tab'); const oldTrack = streams[0].track;
  oldTrack.ended(); await new Promise(resolve => setImmediate(resolve));
  assert.deepEqual(engine.snapshot(), []);
  await engine.start(1, 'two', 'Tab'); oldTrack.ended();
  assert.equal(engine.snapshot().length, 1); await engine.stop(1);
});

test('invalid volume does not corrupt gain; raising volume unmutes', async () => {
  const { engine } = fixture();
  await engine.start(1, 'one', 'Tab'); engine.setVolume(1, .4); engine.setMuted(1, true);
  assert.throws(() => engine.setVolume(1, NaN), /valid volume/);
  assert.equal(engine.sessions.get(1).gain.gain.value, 0);
  engine.setVolume(1, .2);
  assert.equal(engine.snapshot()[0].muted, false);
  assert.equal(engine.sessions.get(1).gain.gain.value, .2);
  engine.setVolume(1, 8); assert.equal(engine.snapshot()[0].volume, 1);
  engine.setVolume(1, -2); assert.equal(engine.snapshot()[0].volume, 0);
  await engine.stop(1);
});


test('capture that has already ended cannot publish a silent route', async () => {
  const track = new Track(); track.readyState = 'ended';
  const { engine } = fixture({ getUserMedia: async () => ({ getTracks: () => [track], getAudioTracks: () => [track] }) });
  await assert.rejects(engine.start(1, 'one', 'Tab'), /audio.*ended/i);
  assert.equal(track.stopped, true); assert.deepEqual(engine.snapshot(), []);
  assert.equal(engine.pending.size, 0);
});

test('capture ending during playback startup releases all resources', async () => {
  let finishResume, markResuming;
  const resuming = new Promise(resolve => { markResuming = resolve; });
  class DelayedContext extends Context {
    async resume() { await new Promise(resolve => { finishResume = resolve; markResuming(); }); this.state = 'running'; }
  }
  const { engine, streams } = fixture({ AudioContext: DelayedContext });
  const starting = engine.start(1, 'one', 'Tab');
  await resuming; streams[0].track.readyState = 'ended'; finishResume();
  await assert.rejects(starting, /audio.*ended/i);
  assert.equal(streams[0].track.stopped, true);
  assert.equal(Context.instances.at(-1).state, 'closed');
  assert.deepEqual(engine.snapshot(), []); assert.equal(engine.pending.size, 0);
});

test('a stream without an audio track cannot start playback', async () => {
  const { engine } = fixture({ getUserMedia: async () => ({ getTracks: () => [], getAudioTracks: () => [] }) });
  await assert.rejects(engine.start(1, 'one', 'Tab'), /audio/i);
  assert.deepEqual(engine.snapshot(), []); assert.equal(engine.pending.size, 0);
});
