// Part of the RPS engine (see rps_engine.js).
// Raw keyboard/mouse state; Dart polls it once per frame.
// FAKE_LOCK (dev, ?fakelock) behaves as if the pointer were locked.
import { TouchControls, isTouchDevice } from './touch.js';

const FAKE_LOCK = new URLSearchParams(location.search).has('fakelock');

export class Input {
  constructor(canvas) {
    this.keys = new Set();
    this.buttons = 0;
    this.dx = 0;
    this.dy = 0;
    this.wheel = 0;
    this.canvas = canvas;
    this.pressedQueue = [];
    // Touch devices have no pointer lock: "locked" = in-game controls shown.
    this.touch = isTouchDevice() ? new TouchControls(this) : null;
    this.vlock = false;
    window.addEventListener('keydown', (e) => {
      if (!this.keys.has(e.code)) this.pressedQueue.push(e.code);
      this.keys.add(e.code);
      if (this.locked() && ['Tab', 'Space', 'KeyF', 'Backquote'].includes(e.code)) e.preventDefault();
    }, true);
    window.addEventListener('keyup', (e) => this.keys.delete(e.code), true);
    window.addEventListener('blur', () => { this.keys.clear(); this.buttons = 0; });
    window.addEventListener('mousemove', (e) => {
      if (!this.locked()) return;
      this.dx += e.movementX;
      this.dy += e.movementY;
    });
    window.addEventListener('mousedown', (e) => { if (this.locked()) this.buttons |= 1 << e.button; }, true);
    window.addEventListener('mouseup', (e) => { this.buttons &= ~(1 << e.button); }, true);
    window.addEventListener('wheel', (e) => { if (this.locked()) this.wheel += Math.sign(e.deltaY); }, { passive: true });
    window.addEventListener('contextmenu', (e) => { if (this.locked()) e.preventDefault(); });
  }

  // ?fakelock (dev): behave as if the pointer were locked, for automated tests.
  locked() { return FAKE_LOCK || this.vlock || document.pointerLockElement != null; }

  isTouch() { return this.touch != null; }

  lock() {
    if (this.touch) {
      this.vlock = true;
      try {
        const d = document.documentElement;
        if (!document.fullscreenElement && d.requestFullscreen) {
          d.requestFullscreen({ navigationUI: 'hide' }).then(() => {
            try { screen.orientation.lock('landscape').catch(() => {}); } catch (_) {}
          }).catch(() => {});
        }
      } catch (_) {}
      return;
    }
    const el = document.body;
    if (!this.locked() && el.requestPointerLock) {
      const p = el.requestPointerLock({ unadjustedMovement: true });
      if (p && p.catch) p.catch(() => el.requestPointerLock());
    }
  }

  unlock() {
    if (this.touch) {
      this.vlock = false;
      this.touch.setVisible(false);
      return;
    }
    if (this.locked()) document.exitPointerLock();
  }

  poll() {
    // Poll is only called in a match, so show touch controls while locked.
    if (this.touch) this.touch.setVisible(this.vlock);
    const t = this.touch;
    const out = {
      jx: t ? t.joyX : 0, jy: t ? t.joyY : 0,
      dx: this.dx, dy: this.dy, wheel: this.wheel, buttons: this.buttons,
      keys: [...this.keys].join(','), pressed: this.pressedQueue.join(','), locked: this.locked(),
    };
    this.dx = this.dy = this.wheel = 0;
    this.pressedQueue.length = 0;
    return out;
  }
}
