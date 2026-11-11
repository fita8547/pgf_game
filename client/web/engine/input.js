// Part of the RPS engine (see rps_engine.js).
// Raw keyboard/mouse state; Dart polls it once per frame.
// FAKE_LOCK (dev, ?fakelock) behaves as if the pointer were locked.
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
  locked() { return FAKE_LOCK || document.pointerLockElement != null; }

  lock() {
    const el = document.body;
    if (!this.locked() && el.requestPointerLock) {
      const p = el.requestPointerLock({ unadjustedMovement: true });
      if (p && p.catch) p.catch(() => el.requestPointerLock());
    }
  }

  unlock() { if (this.locked()) document.exitPointerLock(); }

  poll() {
    const out = {
      dx: this.dx, dy: this.dy, wheel: this.wheel, buttons: this.buttons,
      keys: [...this.keys].join(','), pressed: this.pressedQueue.join(','), locked: this.locked(),
    };
    this.dx = this.dy = this.wheel = 0;
    this.pressedQueue.length = 0;
    return out;
  }
}
