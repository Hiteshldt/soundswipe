/** Audio-only, in-memory tab routes. Each tab owns its own gain and context. */
export class TabAudioEngine {
  constructor({ getUserMedia, AudioContext, onChanged = () => {} }) {
    this.getUserMedia = getUserMedia;
    this.AudioContext = AudioContext;
    this.onChanged = onChanged;
    this.sessions = new Map();
    this.pending = new Map();
  }

  snapshot() {
    return [...this.sessions.values()].map(({ tabId, title, volume, muted }) => ({ tabId, title, volume, muted }));
  }

  async start(tabId, streamId, title) {
    if (!Number.isInteger(tabId) || tabId < 0 || typeof streamId !== 'string' || !streamId) {
      throw new Error('Choose a tab to control.');
    }
    if (this.sessions.has(tabId)) return this.snapshot();
    if (this.pending.has(tabId)) return this.pending.get(tabId).promise;
    const token = { cancelled: false };
    this.pending.set(tabId, token);
    token.promise = this.create(tabId, streamId, title, token);
    return token.promise;
  }

  async create(tabId, streamId, title, token) {
    let stream, context, source, gain;
    try {
      stream = await this.getUserMedia({
        audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: streamId } },
        video: false
      });
      if (token.cancelled) throw new Error('Tab control was cancelled.');
      const tracks = stream.getAudioTracks();
      if (!tracks.length || tracks.some(track => track.readyState !== 'live')) {
        throw new Error('Tab audio has ended. Open the tab and try again.');
      }
      context = new this.AudioContext();
      source = context.createMediaStreamSource(stream);
      gain = context.createGain();
      gain.gain.value = 1;
      source.connect(gain);
      gain.connect(context.destination);
      let timer;
      try {
        await Promise.race([
          context.resume(),
          new Promise((_, reject) => { timer = setTimeout(() => reject(new Error('Audio could not start. Try controlling this tab again.')), 3000); })
        ]);
      } finally { clearTimeout(timer); }
      if (token.cancelled) throw new Error('Tab control was cancelled.');
      if (context.state !== 'running') throw new Error('Audio could not start. Try controlling this tab again.');
      // The tab can close or release capture while resume() is still pending.
      // An ended event from that interval will not fire again for new listeners.
      if (tracks.some(track => track.readyState !== 'live')) {
        throw new Error('Tab audio has ended. Open the tab and try again.');
      }
      const session = { tabId, title: String(title || 'Tab').slice(0, 160), volume: 1, muted: false, stream, context, source, gain };
      this.sessions.set(tabId, session);
      for (const track of stream.getTracks()) {
        track.addEventListener('ended', () => {
          // An old track must not tear down a newly created route for this tab.
          if (this.sessions.get(tabId) === session) void this.stop(tabId);
        }, { once: true });
      }
      this.onChanged(this.snapshot());
      return this.snapshot();
    } catch (error) {
      source?.disconnect(); gain?.disconnect();
      stream?.getTracks().forEach(track => track.stop());
      if (context) await context.close().catch(() => {});
      throw error;
    } finally {
      if (this.pending.get(tabId) === token) this.pending.delete(tabId);
    }
  }

  setVolume(tabId, value) {
    const session = this.sessions.get(tabId);
    if (!session) throw new Error('Control this tab first.');
    if (typeof value !== 'number' || !Number.isFinite(value)) throw new Error('Choose a valid volume.');
    session.volume = Math.min(1, Math.max(0, value));
    if (session.volume > 0) session.muted = false;
    this.apply(session);
    return this.snapshot();
  }

  setMuted(tabId, muted) {
    const session = this.sessions.get(tabId);
    if (!session) throw new Error('Control this tab first.');
    session.muted = Boolean(muted);
    this.apply(session);
    return this.snapshot();
  }

  apply(session) {
    session.gain.gain.setTargetAtTime(session.muted ? 0 : session.volume, session.context.currentTime, 0.02);
    this.onChanged(this.snapshot());
  }

  async stop(tabId) {
    const pending = this.pending.get(tabId);
    if (pending) { pending.cancelled = true; await pending.promise.catch(() => {}); }
    const session = this.sessions.get(tabId);
    if (!session) return this.snapshot();
    this.sessions.delete(tabId);
    session.source.disconnect(); session.gain.disconnect();
    session.stream.getTracks().forEach(track => track.stop());
    await session.context.close().catch(() => {});
    this.onChanged(this.snapshot());
    return this.snapshot();
  }
}
