// Part of the RPS engine (see rps_engine.js).
// Web Audio: sfx (with simple positional pan/attenuation) and music: a
// shuffled BGM playlist (music/bgm/list.json) when there is one, otherwise the
// map's own looping track.
// BASE is the folder the game assets are served from.
const BASE = 'game/';

export class Audio {
  constructor() {
    this.ctx = null;
    this.buffers = new Map();
    this.sfxVolume = 0.8;
    this.musicVolume = 0.35;
    this.voiceVolume = 0.9;
    this.music = null;
    // Agent voice lines (voice/voice_lines.json + voice/<agent>/<id>.mp3).
    this.voiceData = null; // Promise<json|null>
    this.voiceActive = 0; // lines playing right now
    this.voiceBusy = new Map(); // speaker key -> true while that speaker talks
    this.voiceLast = new Map(); // agent/event -> last line id (no repeats)
    this.caption = ''; // "seq|agent|text" of the latest line started
    this.voiceLang = 'ko'; // 'ko' or 'en' (voice/en/<agent>/<id>.mp3, line.en)
    this.captionSeq = 0;
    this.playlist = null; // Promise<[{file, title}]>
    this.bgm = null; // { el, order, i } while the playlist plays
    this.listener = { x: 0, y: 0, z: 0, yaw: 0 };
    // Browsers only start audio from a user gesture. Sounds are triggered by
    // the game loop, never directly by a click, so unlock on every gesture.
    const unlock = () => {
      this.ensure();
      // Autoplay may have refused the playlist before the first gesture.
      if (this.bgm && this.bgm.el.paused && this.bgm.wanted) this.bgm.el.play().catch(() => {});
    };
    for (const ev of ['pointerdown', 'mousedown', 'keydown', 'touchstart']) {
      window.addEventListener(ev, unlock, { capture: true, passive: true });
    }
    // Soft click for menu interaction (not while playing with a locked mouse).
    window.addEventListener('pointerup', () => {
      if (document.pointerLockElement == null) this.play('ui_click', 0.35);
    }, { capture: true, passive: true });
  }

  ensure() {
    if (!this.ctx) {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      this.sfxGain = this.ctx.createGain();
      this.sfxGain.gain.value = this.sfxVolume;
      this.sfxGain.connect(this.ctx.destination);
      this.musicGain = this.ctx.createGain();
      this.musicGain.gain.value = this.musicVolume;
      this.musicGain.connect(this.ctx.destination);
      this.voiceGain = this.ctx.createGain();
      this.voiceGain.gain.value = this.voiceVolume;
      this.voiceGain.connect(this.ctx.destination);
    }
    if (this.ctx.state === 'suspended') this.ctx.resume();
    return this.ctx;
  }

  async buffer(path) {
    if (!this.buffers.has(path)) {
      const ctx = this.ensure();
      this.buffers.set(path, fetch(BASE + path)
        .then((r) => { if (!r.ok) throw new Error(path); return r.arrayBuffer(); })
        .then((b) => ctx.decodeAudioData(b))
        .catch((e) => { console.warn('audio', path, e); return null; }));
    }
    return this.buffers.get(path);
  }

  preload(names) { for (const n of names) this.buffer(`sfx/${n}.mp3`); }

  // Positional when pos is given: distance attenuation + stereo pan.
  async play(name, vol = 1, rate = 1, pos = null) {
    const ctx = this.ensure();
    const buf = await this.buffer(`sfx/${name}.mp3`);
    if (!buf) return;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.playbackRate.value = rate;
    const g = ctx.createGain();
    let node = g;
    if (pos) {
      const l = this.listener;
      const dx = pos[0] - l.x, dy = pos[1] - l.y, dz = pos[2] - l.z;
      const d = Math.hypot(dx, dy, dz);
      vol *= 1 / (1 + Math.max(0, d - 2) * 0.12);
      // Right vector of the listener: (cos yaw, 0, sin yaw).
      const pan = d < 0.01 ? 0 : (dx * Math.cos(l.yaw) + dz * Math.sin(l.yaw)) / d;
      const p = ctx.createStereoPanner();
      p.pan.value = Math.max(-1, Math.min(1, pan * 0.8));
      g.connect(p);
      node = p;
    }
    g.gain.value = vol;
    src.connect(g);
    node.connect(this.sfxGain);
    src.start();
  }

  loadPlaylist() {
    if (!this.playlist) {
      this.playlist = fetch(BASE + 'music/bgm/list.json')
        .then((r) => (r.ok ? r.json() : []))
        .then((l) => (Array.isArray(l) ? l.filter((t) => t && t.file) : []))
        .catch(() => []);
    }
    return this.playlist;
  }

  // Plays the BGM playlist (shuffled, one song after another). Keeps playing
  // across screens: calling it again while it plays changes nothing.
  async playMusic(mapId) {
    const list = await this.loadPlaylist();
    if (list.length) {
      if (this.bgm) {
        this.bgm.wanted = true;
        if (this.bgm.el.paused) this.bgm.el.play().catch(() => {});
        return;
      }
      this.stopMusic();
      this.startPlaylist(list);
      return;
    }
    this.playMapLoop(mapId);
  }

  startPlaylist(list) {
    const ctx = this.ensure();
    const order = [...list.keys()];
    for (let i = order.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [order[i], order[j]] = [order[j], order[i]];
    }
    // Streamed (not decoded into memory): full songs are several MB each.
    const el = new window.Audio();
    el.preload = 'auto';
    ctx.createMediaElementSource(el).connect(this.musicGain);
    const bgm = { el, order, i: 0, wanted: true };
    const load = () => {
      el.src = BASE + 'music/' + list[order[bgm.i % order.length]].file;
      el.play().catch(() => {}); // retried on the next user gesture
    };
    el.addEventListener('ended', () => { bgm.i++; load(); });
    el.addEventListener('error', () => { if (order.length > 1) { bgm.i++; setTimeout(load, 500); } });
    this.bgm = bgm;
    load();
  }

  async playMapLoop(mapId) {
    this.stopMusic();
    const ctx = this.ensure();
    const ogg = document.createElement('audio').canPlayType('audio/ogg; codecs="vorbis"');
    const buf = await this.buffer(`music/${mapId}.${ogg ? 'ogg' : 'mp3'}`);
    if (!buf) return;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    src.loop = true;
    src.connect(this.musicGain);
    src.start();
    this.music = src;
  }

  stopMusic() {
    if (this.music) { try { this.music.stop(); } catch (_) { /* already stopped */ } }
    this.music = null;
    if (this.bgm) { this.bgm.wanted = false; this.bgm.el.pause(); }
  }

  setVolumes(sfx, music, voice) {
    this.sfxVolume = sfx;
    this.musicVolume = music;
    if (voice !== undefined && voice !== null) this.voiceVolume = voice;
    if (this.ctx) {
      this.sfxGain.gain.value = sfx;
      this.musicGain.gain.value = music;
      this.voiceGain.gain.value = this.voiceVolume;
    }
  }

  // ------------------------------------------------------------ voice --
  loadVoices() {
    if (!this.voiceData) {
      this.voiceData = fetch(BASE + 'voice/voice_lines.json')
        .then((r) => (r.ok ? r.json() : null))
        .catch(() => null);
    }
    return this.voiceData;
  }

  // Says a random line of [agent] for [event] (voice_lines.json). [speaker]
  // keys one talker (a player id): a speaker never talks over themselves.
  // [important] lines (ult, match start, results) play even when two other
  // lines are already going; the rest are dropped then. [pos]: positional.
  async voice(agent, event, speaker, important, pos) {
    const data = await this.loadVoices();
    const lines = data && data.agents && data.agents[agent] && data.agents[agent].lines[event];
    if (!lines || !lines.length) return;
    const key = String(speaker);
    if (this.voiceBusy.get(key)) return;
    if (!important && this.voiceActive >= 2) return;
    const lastKey = agent + '/' + event;
    let pick = lines[Math.floor(Math.random() * lines.length)];
    if (lines.length > 1 && pick.id === this.voiceLast.get(lastKey)) {
      pick = lines[(lines.indexOf(pick) + 1) % lines.length];
    }
    this.voiceLast.set(lastKey, pick.id);
    await this.sayLine(agent, pick, key, pos);
  }

  // Two-agent banter (voice_lines.json interactions): plays one whose agents
  // are all in [agentsCsv], line after line. Returns true when one started.
  async voiceTalk(agentsCsv) {
    const data = await this.loadVoices();
    const have = new Set(String(agentsCsv).split(','));
    const all = ((data && data.interactions) || []).filter((it) => it.agents.every((a) => have.has(a)));
    if (!all.length) return false;
    const it = all[Math.floor(Math.random() * all.length)];
    for (const l of it.lines) {
      await this.sayLine(l.agent, l, 'talk:' + l.agent, null);
      await new Promise((r) => setTimeout(r, 250));
    }
    return true;
  }

  setVoiceLang(lang) { this.voiceLang = lang === 'en' ? 'en' : 'ko'; }

  // Plays one line file; resolves when it ends.
  async sayLine(agent, line, key, pos) {
    const ctx = this.ensure();
    const en = this.voiceLang === 'en' && line.en;
    const buf = await this.buffer(`voice/${en ? 'en/' : ''}${agent}/${line.id}.mp3`);
    if (!buf) return;
    const src = ctx.createBufferSource();
    src.buffer = buf;
    const g = ctx.createGain();
    let node = g;
    let vol = 1;
    if (pos) {
      const l = this.listener;
      const dx = pos[0] - l.x, dy = pos[1] - l.y, dz = pos[2] - l.z;
      const d = Math.hypot(dx, dy, dz);
      vol = 1 / (1 + Math.max(0, d - 4) * 0.08);
      const pan = d < 0.01 ? 0 : (dx * Math.cos(l.yaw) + dz * Math.sin(l.yaw)) / d;
      const p = ctx.createStereoPanner();
      p.pan.value = Math.max(-1, Math.min(1, pan * 0.6));
      g.connect(p);
      node = p;
    }
    g.gain.value = vol;
    src.connect(g);
    node.connect(this.voiceGain);
    this.voiceBusy.set(key, true);
    this.voiceActive++;
    this.captionSeq++;
    this.caption = `${this.captionSeq}|${agent}|${en ? line.en : line.text}`;
    await new Promise((resolve) => {
      src.onended = resolve;
      src.start();
    });
    this.voiceActive--;
    this.voiceBusy.delete(key);
  }

  // Latest line started, "seq|agent|text" (empty before the first one).
  voiceCaption() { return this.caption; }
}
