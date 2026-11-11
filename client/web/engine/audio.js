// Part of the RPS engine (see rps_engine.js).
// Web Audio: sfx (with simple positional pan/attenuation) and looping music.
// BASE is the folder the game assets are served from.
const BASE = 'game/';

export class Audio {
  constructor() {
    this.ctx = null;
    this.buffers = new Map();
    this.sfxVolume = 0.8;
    this.musicVolume = 0.35;
    this.music = null;
    this.listener = { x: 0, y: 0, z: 0, yaw: 0 };
    // Browsers only start audio from a user gesture. Sounds are triggered by
    // the game loop, never directly by a click, so unlock on every gesture.
    const unlock = () => this.ensure();
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

  async playMusic(mapId) {
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
  }

  setVolumes(sfx, music) {
    this.sfxVolume = sfx;
    this.musicVolume = music;
    if (this.ctx) {
      this.sfxGain.gain.value = sfx;
      this.musicGain.gain.value = music;
    }
  }
}
