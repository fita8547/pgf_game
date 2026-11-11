// Part of the RPS engine (see rps_engine.js).
// On-screen touch controls for phones/tablets. They feed the same Input
// state the keyboard and mouse do, so the Dart side barely changes:
//  - left half: floating joystick (analog move -> Input.jx/jy)
//  - right half: drag to look (-> Input.dx/dy)
//  - buttons: fire (also drags to look), ADS/crouch toggles, jump, reload,
//    weapon swap, Q/E/C/V skills, shop, scoreboard, menu.
// Enabled on coarse-pointer devices, or forced with ?touch.

const FORCE = new URLSearchParams(location.search).has('touch');

export function isTouchDevice() {
  if (FORCE) return true;
  const coarse = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
  return !!coarse && (navigator.maxTouchPoints || 0) > 0;
}

const LOOK_SCALE = 1.7; // touch px -> mouse px equivalent

const CSS = `
#rps-touch{position:fixed;inset:0;z-index:50;display:none;touch-action:none;user-select:none;-webkit-user-select:none;
  font-family:'Noto Sans KR',sans-serif}
#rps-touch .b{position:absolute;display:flex;align-items:center;justify-content:center;border-radius:50%;
  background:rgba(20,28,48,.42);border:2px solid rgba(255,240,210,.45);color:#fff3dc;font-weight:800;
  font-size:14px;text-shadow:0 1px 2px #000;box-sizing:border-box}
#rps-touch .b.on{background:rgba(232,180,60,.55);border-color:#ffd56b}
#rps-touch .b.big{font-size:17px}
#rps-touch .sq{border-radius:10px}
#rps-touch .joy{position:absolute;width:130px;height:130px;margin:-65px 0 0 -65px;border-radius:50%;
  background:rgba(20,28,48,.3);border:2px solid rgba(255,240,210,.35);display:none;pointer-events:none}
#rps-touch .knob{position:absolute;left:50%;top:50%;width:56px;height:56px;margin:-28px 0 0 -28px;border-radius:50%;
  background:rgba(255,240,210,.55)}
#rps-touch .hint{position:absolute;left:8%;bottom:14%;color:rgba(255,240,210,.35);font-size:13px;pointer-events:none}
`;

// [id, label, kind, css position, key code | special]
// kind: 'hold' key held while pressed, 'toggle' key latched, 'fire', 'ads'
const BUTTONS = [
  ['fire', '발사', 'fire', 'right:24px;bottom:110px;width:92px;height:92px', null, 'big'],
  ['fire2', '발사', 'fire', 'left:16px;top:42%;width:64px;height:64px', null],
  ['ads', '조준', 'ads', 'right:128px;bottom:126px;width:60px;height:60px', null],
  ['jump', '점프', 'hold', 'right:34px;bottom:212px;width:62px;height:62px', 'Space'],
  ['crouch', '앉기', 'toggle', 'right:108px;bottom:200px;width:54px;height:54px', 'ShiftLeft'],
  ['reload', '장전', 'hold', 'right:222px;bottom:24px;width:52px;height:52px', 'KeyR'],
  ['swap', '무기', 'wheel', 'right:284px;bottom:24px;width:52px;height:52px', null],
  ['q', 'Q', 'hold', 'right:202px;bottom:150px;width:54px;height:54px', 'KeyQ'],
  ['e', 'E', 'hold', 'right:182px;bottom:218px;width:54px;height:54px', 'KeyE'],
  ['c', 'C', 'hold', 'right:118px;bottom:262px;width:54px;height:54px', 'KeyC'],
  ['v', '궁', 'hold', 'right:44px;bottom:282px;width:58px;height:58px', 'KeyV'],
  ['menu', '☰', 'menu', 'left:12px;top:10px;width:48px;height:38px', null, 'sq'],
  ['shop', '상점', 'hold', 'left:68px;top:10px;width:56px;height:38px', 'KeyB', 'sq'],
  ['score', '점수', 'hold', 'left:132px;top:10px;width:56px;height:38px', 'Tab', 'sq'],
];

const LABELS_EN = {
  fire: 'FIRE', fire2: 'FIRE', ads: 'ADS', jump: 'JUMP', crouch: 'DUCK', reload: 'R',
  swap: 'SWAP', v: 'ULT', shop: 'SHOP', score: 'SCORE',
};

export class TouchControls {
  constructor(input) {
    this.input = input;
    this.visible = false;
    this.toggles = new Set();
    this.look = new Map(); // touch id -> {x, y}
    this.joyId = null;
    this.joyX = 0;
    this.joyY = 0;
    this.fireTouches = new Set();
    this.adsOn = false;

    const style = document.createElement('style');
    style.textContent = CSS;
    document.head.appendChild(style);
    const root = (this.root = document.createElement('div'));
    root.id = 'rps-touch';
    this.joy = document.createElement('div');
    this.joy.className = 'joy';
    this.knob = document.createElement('div');
    this.knob.className = 'knob';
    this.joy.appendChild(this.knob);
    root.appendChild(this.joy);
    this.btn = {};
    for (const [id, label, kind, pos, code, extra] of BUTTONS) {
      const b = document.createElement('div');
      b.className = 'b' + (extra ? ' ' + extra : '');
      b.style.cssText = pos;
      b.textContent = label;
      b.dataset.id = id;
      root.appendChild(b);
      this.btn[id] = { el: b, kind, code, ko: label };
    }
    document.body.appendChild(root);

    const opt = { passive: false };
    root.addEventListener('touchstart', (e) => this._start(e), opt);
    root.addEventListener('touchmove', (e) => this._move(e), opt);
    root.addEventListener('touchend', (e) => this._end(e), opt);
    root.addEventListener('touchcancel', (e) => this._end(e), opt);
    // Synthetic mouse events from taps must not become clicks/fire.
    root.addEventListener('mousedown', (e) => { e.preventDefault(); e.stopPropagation(); }, true);
  }

  setVisible(v) {
    if (v === this.visible) return;
    this.visible = v;
    if (v) this._labels();
    this.root.style.display = v ? 'block' : 'none';
    if (!v) this.reset();
  }

  // Button text follows the game's language setting (localStorage rps.lang).
  _labels() {
    let en = false;
    try { en = localStorage.getItem('rps.lang') === 'en'; } catch (_) {}
    for (const id in this.btn) {
      const l = LABELS_EN[id];
      if (l) this.btn[id].el.textContent = en ? l : this.btn[id].ko;
    }
  }

  reset() {
    for (const code of this.toggles) this.input.keys.delete(code);
    this.toggles.clear();
    for (const id in this.btn) this.btn[id].el.classList.remove('on');
    for (const b of Object.values(this.btn)) if (b.code) this.input.keys.delete(b.code);
    this.look.clear();
    this.fireTouches.clear();
    this.adsOn = false;
    this.input.buttons = 0;
    this._joyEnd();
  }

  _buttonAt(t) {
    const el = document.elementFromPoint(t.clientX, t.clientY);
    return el && el.dataset && el.dataset.id ? el.dataset.id : null;
  }

  _start(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      const id = this._buttonAt(t);
      if (id) {
        this._press(id, t);
        continue;
      }
      if (t.clientX < window.innerWidth * 0.4 && this.joyId === null) {
        this.joyId = t.identifier;
        this.joyCx = t.clientX;
        this.joyCy = t.clientY;
        this.joy.style.left = `${t.clientX}px`;
        this.joy.style.top = `${t.clientY}px`;
        this.joy.style.display = 'block';
        this._joyMove(t);
      } else {
        this.look.set(t.identifier, { x: t.clientX, y: t.clientY });
      }
    }
  }

  _press(id, t) {
    const b = this.btn[id];
    const inp = this.input;
    switch (b.kind) {
      case 'fire':
        this.fireTouches.add(t.identifier);
        this.look.set(t.identifier, { x: t.clientX, y: t.clientY, fire: id });
        inp.buttons |= 1;
        b.el.classList.add('on');
        break;
      case 'ads':
        this.adsOn = !this.adsOn;
        if (this.adsOn) inp.buttons |= 4; else inp.buttons &= ~4;
        b.el.classList.toggle('on', this.adsOn);
        break;
      case 'toggle':
        if (this.toggles.has(b.code)) {
          this.toggles.delete(b.code);
          inp.keys.delete(b.code);
          b.el.classList.remove('on');
        } else {
          this.toggles.add(b.code);
          inp.keys.add(b.code);
          inp.pressedQueue.push(b.code);
          b.el.classList.add('on');
        }
        break;
      case 'wheel':
        inp.wheel += 1;
        this._flash(b.el);
        break;
      case 'menu':
        this.reset();
        inp.unlock();
        break;
      default: // hold
        if (!inp.keys.has(b.code)) inp.pressedQueue.push(b.code);
        inp.keys.add(b.code);
        b.el.classList.add('on');
        (this.holds ??= new Map()).set(t.identifier, id);
    }
  }

  _flash(el) {
    el.classList.add('on');
    setTimeout(() => el.classList.remove('on'), 120);
  }

  _move(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      if (t.identifier === this.joyId) {
        this._joyMove(t);
        continue;
      }
      const l = this.look.get(t.identifier);
      if (l) {
        this.input.dx += (t.clientX - l.x) * LOOK_SCALE;
        this.input.dy += (t.clientY - l.y) * LOOK_SCALE;
        l.x = t.clientX;
        l.y = t.clientY;
      }
    }
  }

  _end(e) {
    e.preventDefault();
    for (const t of e.changedTouches) {
      if (t.identifier === this.joyId) this._joyEnd();
      const l = this.look.get(t.identifier);
      this.look.delete(t.identifier);
      if (this.fireTouches.delete(t.identifier)) {
        if (l && l.fire) this.btn[l.fire].el.classList.remove('on');
        if (this.fireTouches.size === 0) this.input.buttons &= ~1;
      }
      const hold = this.holds && this.holds.get(t.identifier);
      if (hold) {
        this.holds.delete(t.identifier);
        const b = this.btn[hold];
        const stillHeld = [...this.holds.values()].includes(hold);
        if (!stillHeld) {
          this.input.keys.delete(b.code);
          b.el.classList.remove('on');
        }
      }
    }
  }

  _joyMove(t) {
    const R = 55;
    let x = t.clientX - this.joyCx, y = t.clientY - this.joyCy;
    const d = Math.hypot(x, y);
    if (d > R) { x *= R / d; y *= R / d; }
    this.knob.style.transform = `translate(${x}px, ${y}px)`;
    // Small dead zone, then full speed near the rim.
    const m = Math.min(1, d / R);
    const s = m < 0.15 ? 0 : Math.min(1, (m - 0.15) / 0.7) / (m || 1);
    this.joyX = x / R * s;
    this.joyY = -y / R * s;
  }

  _joyEnd() {
    this.joyId = null;
    this.joyX = this.joyY = 0;
    this.joy.style.display = 'none';
    this.knob.style.transform = '';
  }
}
