"""RPS end-to-end integration test on an Android emulator (or a phone over adb).

Drives the real Chrome on the device through the Chrome DevTools Protocol:
real touch events, real network, a real game server started by this script.

  python client/tool/integration/emulator_test.py [--port 8095] [--keep-server] [--only STEP,...]

Requirements: a running emulator/device visible to adb, Chrome installed on it,
the web client built (client/build/web), Dart SDK (path below or $DART).

Steps (each records PASS/FAIL, details and screenshots in the report):
  01 splash          splash screen shown with boot progress, then the title
  02 lobby_skeleton  title -> lobby; skeleton cards shown while icons load
  03 settings_save   dark mode off + text size "large"; saved on the server (B/E)
  04 restart_persist server restarted, local copy tampered -> server values still applied
  05 match_load      practice match; HUD skeleton while loading; spawn invulnerability
  06 touch_controls  touch overlay, shop -> armor, joystick move, look, fire, skill, reload
  07 leave_match     menu -> leave -> lobby
  08 offline_exit    network goes offline mid-session -> alert -> app closes
  09 startup_no_api  server API unreachable at startup -> alert -> app closes

Output: client/tool/integration/out/<timestamp>/report.md (+ report.json, PNGs).
Exit code 0 only if every step passed.
"""
import argparse
import base64
import datetime as dt
import json
import math
import os
import queue
import socket
import struct
import subprocess
import sys
import threading
import time
import traceback
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
SERVER_DIR = os.path.join(ROOT, 'server')
ADB = os.environ.get('ADB') or os.path.join(os.environ.get('LOCALAPPDATA', ''), 'Android', 'Sdk', 'platform-tools',
                                            'adb.exe')
DART = os.environ.get('DART') or os.path.join(os.path.expanduser('~'), 'Downloads', 'flutter', 'bin', 'cache',
                                              'dart-sdk', 'bin', 'dart.exe')
DEVTOOLS_PORT = 9334
HOST_FROM_EMULATOR = '10.0.2.2'  # the host machine as seen from the Android emulator


# ===================================================================== CDP ==
class CDP:
    """Minimal threaded Chrome DevTools Protocol client (stdlib only)."""

    def __init__(self, ws_url):
        host, path = ws_url[len('ws://'):].split('/', 1)
        h, p = host.split(':')
        self.sock = socket.create_connection((h, int(p)), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        self.sock.sendall((f'GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n'
                           f'Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n').encode())
        buf = b''
        while b'\r\n\r\n' not in buf:
            buf += self.sock.recv(4096)
        if b' 101 ' not in buf.split(b'\r\n', 1)[0]:
            raise RuntimeError('websocket upgrade failed: ' + buf[:200].decode(errors='replace'))
        self.buf = buf.split(b'\r\n\r\n', 1)[1]
        self.sock.settimeout(None)
        self.next_id = 0
        self.lock = threading.Lock()
        self.pending = {}
        self.events = queue.Queue()
        self.closed = False
        threading.Thread(target=self._reader, daemon=True).start()

    def _read(self, n):
        while len(self.buf) < n:
            chunk = self.sock.recv(1 << 20)
            if not chunk:
                raise EOFError
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def _reader(self):
        try:
            while True:
                data = b''
                while True:
                    b0, b1 = self._read(2)
                    n = b1 & 0x7F
                    if n == 126:
                        n = struct.unpack('>H', self._read(2))[0]
                    elif n == 127:
                        n = struct.unpack('>Q', self._read(8))[0]
                    data += self._read(n)
                    if b0 & 0x80:
                        break
                if (b0 & 0x0F) == 8:  # close frame
                    raise EOFError
                if (b0 & 0x0F) not in (1, 0):
                    continue
                msg = json.loads(data)
                if 'id' in msg:
                    slot = self.pending.get(msg['id'])
                    if slot:
                        slot['msg'] = msg
                        slot['ev'].set()
                else:
                    self.events.put(msg)
        except Exception:
            self.closed = True
            for slot in list(self.pending.values()):
                slot['ev'].set()

    def call(self, method, timeout=30, **params):
        with self.lock:
            self.next_id += 1
            mid = self.next_id
            slot = {'ev': threading.Event(), 'msg': None}
            self.pending[mid] = slot
            payload = json.dumps({'id': mid, 'method': method, 'params': params}).encode()
            hdr = bytes([0x81])
            n = len(payload)
            if n < 126:
                hdr += bytes([0x80 | n])
            elif n < 65536:
                hdr += bytes([0x80 | 126]) + struct.pack('>H', n)
            else:
                hdr += bytes([0x80 | 127]) + struct.pack('>Q', n)
            mask = os.urandom(4)
            self.sock.sendall(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        if not slot['ev'].wait(timeout):
            self.pending.pop(mid, None)
            raise TimeoutError(f'CDP {method} timed out')
        self.pending.pop(mid, None)
        msg = slot['msg']
        if msg is None:
            raise EOFError('CDP connection closed')
        if 'error' in msg:
            raise RuntimeError(f'CDP {method}: {msg["error"]}')
        return msg.get('result', {})

    def close(self):
        try:
            self.sock.close()
        except OSError:
            pass


# ================================================================ helpers ==
def run(cmd, check=True, timeout=60):
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f'{cmd[0]} failed: {r.stderr.strip() or r.stdout.strip()}')
    return r.stdout


def adb(*args, check=True):
    return run([ADB, *args], check=check)


def http_json(url, method='GET', body=None, timeout=5):
    req = urllib.request.Request(url, method=method, data=None if body is None else json.dumps(body).encode())
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode())


class StepFailed(AssertionError):
    pass


def check(cond, msg):
    if not cond:
        raise StepFailed(msg)


# ================================================================= server ==
class GameServer:
    """A private game server for the test (own port and settings file), so
    the player-facing server on 8090 is never touched."""

    def __init__(self, port, data_file, log_file):
        self.port, self.data_file, self.log_file = port, data_file, log_file
        self.proc = None

    def start(self):
        log = open(self.log_file, 'a', encoding='utf-8')
        self.proc = subprocess.Popen([DART, 'bin/server.dart', '--port', str(self.port), '--data', self.data_file],
                                     cwd=SERVER_DIR, stdout=log, stderr=subprocess.STDOUT)
        end = time.time() + 60
        while time.time() < end:
            try:
                if http_json(f'http://127.0.0.1:{self.port}/api/health', timeout=1).get('ok'):
                    return
            except OSError:
                pass
            if self.proc.poll() is not None:
                raise RuntimeError(f'server exited early, see {self.log_file}')
            time.sleep(0.5)
        raise RuntimeError('server did not come up in 60 s')

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()
        self.proc = None

    def api(self, path, method='GET', body=None):
        return http_json(f'http://127.0.0.1:{self.port}{path}', method, body)


# ================================================================= device ==
class Device:
    """Chrome on the Android device, through adb + DevTools."""

    def __init__(self, out_dir):
        self.out = out_dir
        self.cdp = None
        self.tab_id = None
        self.shots = []

    # ---- setup
    def prepare(self):
        devs = [l.split('\t')[0] for l in adb('devices').splitlines()[1:] if l.endswith('\tdevice')]
        check(devs, 'no Android device/emulator found by adb')
        self.serial = devs[0]
        # Chrome only opens its DevTools socket when developer options are on.
        if adb('shell', 'settings', 'get', 'global', 'development_settings_enabled').strip() != '1':
            adb('shell', 'settings', 'put', 'global', 'development_settings_enabled', '1')
            adb('shell', 'am', 'force-stop', 'com.android.chrome')
        # Landscape, like a player holding the phone sideways.
        adb('shell', 'settings', 'put', 'system', 'accelerometer_rotation', '0')
        adb('shell', 'settings', 'put', 'system', 'user_rotation', '1')
        if 'chrome_devtools_remote' not in adb('shell', 'cat', '/proc/net/unix'):
            adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', 'about:blank', 'com.android.chrome')
            for _ in range(30):
                time.sleep(0.5)
                if 'chrome_devtools_remote' in adb('shell', 'cat', '/proc/net/unix'):
                    break
        check('chrome_devtools_remote' in adb('shell', 'cat', '/proc/net/unix'), 'Chrome DevTools socket not found')
        adb('forward', f'tcp:{DEVTOOLS_PORT}', 'localabstract:chrome_devtools_remote')
        ver = http_json(f'http://127.0.0.1:{DEVTOOLS_PORT}/json/version')
        self.browser = ver.get('Browser', '?')
        self.android = adb('shell', 'getprop', 'ro.build.version.release').strip()
        self.model = adb('shell', 'getprop', 'ro.product.model').strip()

    def open_tab(self, url):
        tab = None
        try:
            req = urllib.request.Request(f'http://127.0.0.1:{DEVTOOLS_PORT}/json/new?{url}', method='PUT')
            with urllib.request.urlopen(req, timeout=10) as r:
                tab = json.loads(r.read().decode())
        except OSError:
            # Chrome on Android may refuse /json/new: open the page with an
            # intent instead and attach to that tab.
            before = {t['id'] for t in http_json(f'http://127.0.0.1:{DEVTOOLS_PORT}/json')}
            adb('shell', 'am', 'start', '-a', 'android.intent.action.VIEW', '-d', url, 'com.android.chrome')
            for _ in range(40):
                time.sleep(0.5)
                tabs = [t for t in http_json(f'http://127.0.0.1:{DEVTOOLS_PORT}/json') if t.get('type') == 'page']
                new = [t for t in tabs if t['id'] not in before] or [t for t in tabs if t.get('url', '').startswith(url)]
                if new:
                    tab = new[0]
                    break
        check(tab, 'could not open a Chrome tab on the device')
        self.tab_id = tab['id']
        self.cdp = CDP(tab['webSocketDebuggerUrl'].replace('localhost', '127.0.0.1'))
        self.cdp.call('Page.enable')
        self.cdp.call('Runtime.enable')
        self.cdp.call('Network.enable')
        # Bring it to the front so it renders at full speed.
        try:
            urllib.request.urlopen(f'http://127.0.0.1:{DEVTOOLS_PORT}/json/activate/{self.tab_id}', timeout=5)
        except OSError:
            pass

    def close(self):
        if self.cdp:
            try:
                self.cdp.call('Network.emulateNetworkConditions', offline=False, latency=0, downloadThroughput=-1,
                              uploadThroughput=-1)
                self.cdp.call('Network.setBlockedURLs', urls=[])
            except Exception:
                pass
            self.cdp.close()
        if self.tab_id:
            try:
                urllib.request.urlopen(f'http://127.0.0.1:{DEVTOOLS_PORT}/json/close/{self.tab_id}', timeout=5)
            except OSError:
                pass
        adb('forward', '--remove', f'tcp:{DEVTOOLS_PORT}', check=False)

    # ---- page
    def eval(self, js, timeout=20):
        r = self.cdp.call('Runtime.evaluate', timeout=timeout, expression=js, returnByValue=True, awaitPromise=True)
        if 'exceptionDetails' in r:
            raise RuntimeError('JS error: ' + json.dumps(r['exceptionDetails'])[:300])
        return r.get('result', {}).get('value')

    def navigate(self, url):
        self.cdp.call('Page.navigate', url=url)

    def state(self):
        raw = self.eval('window.rpsTest ? window.rpsTest.state() : null')
        return json.loads(raw) if raw else {}

    def wait(self, pred, timeout, what, poll=0.25):
        end = time.time() + timeout
        last = {}
        while time.time() < end:
            try:
                last = self.state()
                if pred(last):
                    return last
            except (RuntimeError, json.JSONDecodeError):
                pass
            time.sleep(poll)
        raise StepFailed(f'timed out after {timeout}s waiting for: {what}; last state: {json.dumps(last)[:400]}')

    def viewport(self):
        return self.eval('[innerWidth, innerHeight, devicePixelRatio]')

    def shot(self, name, caption):
        try:
            img = self.cdp.call('Page.captureScreenshot', timeout=30, format='png')
        except Exception as e:  # screenshots are evidence, not assertions
            return f'(screenshot failed: {e})'
        fn = f'{len(self.shots) + 1:02d}_{name}.png'
        with open(os.path.join(self.out, fn), 'wb') as f:
            f.write(base64.b64decode(img['data']))
        self.shots.append((fn, caption))
        return fn

    # ---- finding UI (Flutter semantics DOM, enabled by ?test)
    FIND_JS = r"""
    (function(text, exact) {
      const norm = s => (s || '').replace(/\s+/g, ' ').trim();
      const want = norm(text);
      let best = null;
      for (const el of document.querySelectorAll('flt-semantics, flt-semantics *, [role]')) {
        const label = norm(el.getAttribute('aria-label') || el.textContent);
        if (!label) continue;
        const hit = exact ? label === want : label.includes(want);
        if (!hit) continue;
        const r = el.getBoundingClientRect();
        if (r.width < 2 || r.height < 2 || r.right < 0 || r.bottom < 0 || r.left > innerWidth || r.top > innerHeight) continue;
        const area = r.width * r.height;
        if (!best || area < best.area) best = {x: r.left + r.width / 2, y: r.top + r.height / 2, area, label};
      }
      return best;
    })"""

    def find(self, text, exact=True, timeout=10):
        end = time.time() + timeout
        while time.time() < end:
            r = self.eval(f'{self.FIND_JS}({json.dumps(text)}, {str(exact).lower()})')
            if r:
                return r
            time.sleep(0.25)
        raise StepFailed(f'UI element "{text}" not found on screen')

    def dom_center(self, selector):
        r = self.eval(f"""(function(){{const e=document.querySelector({json.dumps(selector)});
            if(!e) return null; const r=e.getBoundingClientRect();
            return r.width>0 ? {{x:r.left+r.width/2, y:r.top+r.height/2}} : null;}})()""")
        check(r, f'{selector} not visible')
        return r

    # ---- touch input (real touch events through the browser's input pipeline)
    def touch(self, kind, points):
        self.cdp.call('Input.dispatchTouchEvent', type=kind,
                      touchPoints=[{'x': x, 'y': y, 'id': i, 'radiusX': 8, 'radiusY': 8, 'force': 1} for i, x, y in points])

    def tap(self, x, y):
        self.touch('touchStart', [(1, x, y)])
        time.sleep(0.08)
        self.touch('touchEnd', [])
        time.sleep(0.25)

    def tap_text(self, text, exact=True, timeout=10):
        r = self.find(text, exact, timeout)
        self.tap(r['x'], r['y'])
        return r

    def hold(self, x, y, seconds, dx=0.0, dy=0.0, tid=1):
        """Press at (x,y), slide by (dx,dy) over 0.3 s, keep holding."""
        self.touch('touchStart', [(tid, x, y)])
        steps = 6
        for i in range(1, steps + 1):
            time.sleep(0.05)
            self.touch('touchMove', [(tid, x + dx * i / steps, y + dy * i / steps)])
        end = time.time() + seconds
        while time.time() < end:  # keep the touch alive with tiny moves
            time.sleep(0.2)
            self.touch('touchMove', [(tid, x + dx, y + dy + (0.5 if int(time.time() * 5) % 2 else -0.5))])
        self.touch('touchEnd', [])
        time.sleep(0.2)


# =============================================================== recorder ==
class Recorder:
    """Records the device screen during the run (adb screenrecord, in
    170 s pieces because of its 3 minute limit), then joins the pieces into
    one MP4 with ffmpeg (from the imageio-ffmpeg package, if installed)."""

    def __init__(self, out_dir):
        self.out = out_dir
        self.parts = []
        self.stop_flag = threading.Event()
        self.thread = None

    def start(self):
        adb('shell', 'rm', '-f', '/sdcard/rps_rec_*.mp4', check=False)
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()
        time.sleep(1.0)

    def _loop(self):
        i = 0
        while not self.stop_flag.is_set():
            i += 1
            remote = f'/sdcard/rps_rec_{i:02d}.mp4'
            self.parts.append(remote)
            subprocess.run([ADB, 'shell', 'screenrecord', '--time-limit', '170', '--bit-rate', '8000000', remote],
                           capture_output=True)

    def stop(self):
        self.stop_flag.set()
        adb('shell', 'pkill', '-INT', 'screenrecord', check=False)
        if self.thread:
            self.thread.join(15)
        time.sleep(1.5)  # let the last file be finalised
        local = []
        for i, remote in enumerate(self.parts):
            dst = os.path.join(self.out, f'rec_{i + 1:02d}.mp4')
            if subprocess.run([ADB, 'pull', remote, dst], capture_output=True).returncode == 0 and os.path.getsize(dst) > 1000:
                local.append(dst)
        adb('shell', 'rm', '-f', '/sdcard/rps_rec_*.mp4', check=False)
        if not local:
            return None
        final = os.path.join(self.out, 'test_video.mp4')
        try:
            import imageio_ffmpeg
            ff = imageio_ffmpeg.get_ffmpeg_exe()
        except ImportError:
            return local[0] if len(local) == 1 else local
        lst = os.path.join(self.out, 'rec_list.txt')
        with open(lst, 'w', encoding='utf-8') as f:
            f.writelines(f"file '{os.path.basename(x)}'\n" for x in local)
        # Re-encode so the joined file plays everywhere (PowerPoint included).
        subprocess.run([ff, '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-c:v', 'libx264', '-preset', 'veryfast',
                        '-crf', '23', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', '-an', final],
                       cwd=self.out, capture_output=True)
        return final if os.path.exists(final) else local


# ================================================================= runner ==
class Runner:
    def __init__(self, args):
        stamp = dt.datetime.now().strftime('%Y%m%d-%H%M%S')
        self.out = os.path.join(HERE, 'out', stamp)
        os.makedirs(self.out, exist_ok=True)
        self.port = args.port
        self.server = GameServer(self.port, os.path.join(self.out, 'user_settings.json'),
                                 os.path.join(self.out, 'server.log'))
        self.dev = Device(self.out)
        self.url = f'http://{HOST_FROM_EMULATOR}:{self.port}/?test'
        self.results = []
        self.only = set(args.only.split(',')) if args.only else None
        self.keep_server = args.keep_server
        self.recorder = Recorder(self.out) if args.record else None
        self.ctx = {}

    def log(self, msg):
        line = f'[{dt.datetime.now().strftime("%H:%M:%S")}] {msg}'
        print(line, flush=True)
        with open(os.path.join(self.out, 'run.log'), 'a', encoding='utf-8') as f:
            f.write(line + '\n')

    def step(self, sid, title, fn):
        if self.only and sid not in self.only and sid.split('_')[0] not in self.only:
            return
        self.log(f'── {sid} {title}')
        first_shot = len(self.dev.shots)
        notes = []
        t0 = time.time()
        try:
            fn(notes)
            status = 'PASS'
        except StepFailed as e:
            status, notes = 'FAIL', notes + [f'실패: {e}']
        except Exception as e:
            status, notes = 'FAIL', notes + [f'오류: {e!r}', traceback.format_exc(limit=3)]
        if status == 'FAIL':
            self.dev.shot(f'{sid}_fail', '실패 시점 화면')
        dur = time.time() - t0
        self.results.append({'id': sid, 'title': title, 'status': status, 'seconds': round(dur, 1), 'notes': notes,
                             'shots': self.dev.shots[first_shot:]})
        self.log(f'   {status} ({dur:.1f}s) ' + ' / '.join(n for n in notes if '\n' not in n)[:300])

    # ----------------------------------------------------------- steps
    def fresh_load(self, extra_storage=None):
        """Load the app with clean storage (Korean UI, Pebble, low graphics)."""
        d = self.dev
        d.navigate(self.url)
        time.sleep(1.5)
        js = ("localStorage.clear();localStorage.setItem('rps.lang','ko');localStorage.setItem('rps.char','pebble');"
              "localStorage.setItem('rps.quality','0');localStorage.setItem('rps.map','rps_arena');")
        for k, v in (extra_storage or {}).items():
            js += f'localStorage.setItem({json.dumps(k)},{json.dumps(v)});'
        d.eval(js + 'true')
        d.navigate(self.url)

    def s01_splash(self, notes):
        d = self.dev
        self.fresh_load()
        seen, progress = [], []
        shot_taken = False
        end = time.time() + 40
        while time.time() < end:
            try:
                s = d.state()
            except Exception:
                s = {}
            sc = s.get('screen')
            if sc and (not seen or seen[-1] != sc):
                seen.append(sc)
            if sc == 'splash':
                progress.append(s.get('bootProgress', 0))
                if not shot_taken and s.get('bootProgress', 0) > 0:
                    d.shot('splash', f'스플래시 · {s.get("boot")}')
                    shot_taken = True
            if sc == 'title':
                break
            time.sleep(0.1)
        notes.append(f'화면 순서: {" → ".join(seen)}')
        notes.append(f'진행률 기록: {sorted(set(round(p, 2) for p in progress))}')
        check('splash' in seen, '스플래시 화면이 보이지 않음')
        check(seen[-1] == 'title', '스플래시 후 타이틀로 넘어가지 않음')
        check(max(progress or [0]) >= 0.4, '스플래시 진행률이 올라가지 않음')
        self.ctx['cid'] = d.state().get('cid')
        notes.append(f'client id: {self.ctx["cid"]}')
        d.shot('title', '타이틀 화면')

    def s02_lobby_skeleton(self, notes):
        d = self.dev
        before = d.state().get('shimmers', 0)
        d.tap_text('게임 시작')
        d.wait(lambda s: s.get('screen') == 'lobby', 15, 'lobby')
        time.sleep(1.0)
        s = d.state()
        notes.append(f'스켈레톤(shimmer) 생성 수: {before} → {s.get("shimmers")}')
        check(s.get('shimmers', 0) > before, '로비에서 스켈레톤 카드가 표시되지 않음')
        d.find('페블')  # real cards replaced the skeletons
        d.shot('lobby', '로비 (스켈레톤이 실제 카드로 바뀐 뒤)')

    def s03_settings_save(self, notes):
        d, srv = self.dev, self.server
        s0 = d.state()
        check(s0.get('dark') is True and abs(s0.get('fontScale', 0) - 1.0) < 1e-6, f'초기값이 기본값이 아님: {s0}')
        d.tap_text('설정')
        d.find('다크 모드 스위치')
        d.shot('settings_before', '설정 창 (변경 전, 다크)')
        d.tap_text('다크 모드 스위치')
        d.wait(lambda s: s.get('dark') is False, 5, 'dark=false')
        d.tap_text('크게')
        d.wait(lambda s: abs(s.get('fontScale', 0) - 1.15) < 1e-6, 5, 'fontScale=1.15')
        d.find('서버에 저장됨', timeout=8)
        on_server = srv.api(f'/api/settings?cid={self.ctx["cid"]}')
        notes.append(f'서버 API 조회: {on_server}')
        check(on_server == {'dark': False, 'fontScale': 1.15}, f'서버에 저장된 값이 다름: {on_server}')
        d.shot('settings_after', '설정 창 (라이트 + 글자 크게, "서버에 저장됨")')
        try:
            d.tap_text('닫기', timeout=2)
        except StepFailed:
            # Short phone screens push the button below the fold: tap outside the dialog.
            w, h, _ = d.viewport()
            d.tap(6, h * 0.5)
            notes.append('닫기 버튼이 화면 아래라 창 바깥을 눌러 닫음')
        time.sleep(0.5)
        d.shot('lobby_light', '로비 라이트 모드 · 큰 글자')

    def s04_restart_persist(self, notes):
        d, srv = self.dev, self.server
        time.sleep(1.0)  # let the debounced file write land
        srv.stop()
        with open(srv.data_file, encoding='utf-8') as f:
            on_disk = json.load(f).get(self.ctx['cid'])
        notes.append(f'서버 종료 후 파일 내용: {on_disk}')
        check(on_disk and on_disk.get('dark') is False and on_disk.get('fontScale') == 1.15, '파일에 저장되지 않음')
        srv.start()
        notes.append('서버 재시작 완료')
        # Tamper with the browser copy: the server value must win.
        d.eval("localStorage.setItem('rps.dark','true');localStorage.setItem('rps.font','1');true")
        d.navigate(self.url)
        s = d.wait(lambda s: s.get('screen') == 'title', 40, 'title after reload')
        notes.append(f'다시 켠 뒤 앱 상태: dark={s.get("dark")} fontScale={s.get("fontScale")}')
        check(s.get('dark') is False and abs(s.get('fontScale', 0) - 1.15) < 1e-6,
              '재시작 후 서버 설정이 적용되지 않음')
        d.shot('restart_title', '서버 재시작 + 브라우저 값 변조 후에도 라이트·큰 글자 유지')

    def s05_match_load(self, notes):
        d = self.dev
        if d.state().get('screen') == 'title':
            d.tap_text('게임 시작')
            d.wait(lambda s: s.get('screen') == 'lobby', 15, 'lobby')
        before = d.state().get('hudSkeletons', 0)
        d.tap_text('봇 연습')
        # catch the skeleton on screen while it loads
        end = time.time() + 10
        while time.time() < end:
            s = d.state()
            if s.get('game', {}).get('loading') and s.get('hudSkeletons', 0) > before:
                d.shot('hud_skeleton', '경기 로딩 중 HUD 스켈레톤')
                break
            if s.get('game') and not s['game'].get('loading'):
                break
            time.sleep(0.1)
        s = d.wait(lambda s: s.get('game') and not s['game'].get('loading') and 'pos' in s['game'], 90, 'match loaded')
        g = s['game']
        notes.append(f'HUD 스켈레톤 프레임: {s.get("hudSkeletons", 0) - before}')
        notes.append(f'캐릭터 {g.get("char")} · 체력 {g.get("hp")} · 부활 무적 {g.get("spawnProtect"):.1f}s · 스폰룸 {g.get("inSpawn")}')
        check(s.get('hudSkeletons', 0) > before, '경기 로딩 중 스켈레톤이 표시되지 않음')
        check(g.get('spawnProtect', 0) > 0, '부활 무적이 없음')
        check(g.get('inSpawn'), '스폰룸에서 시작하지 않음')
        d.shot('match_paused', '경기 화면 (터치 전 안내)')

    def s06_touch_controls(self, notes):
        d = self.dev
        # 1) tap the pause overlay -> game takes input, touch overlay appears
        w, h, dpr = d.viewport()
        notes.append(f'뷰포트 {w}x{h} CSS px · dpr {dpr}')
        if not d.state()['game']['locked']:
            d.tap(w * 0.5, h * 0.25)
        d.wait(lambda s: s['game'].get('locked'), 5, 'game locked (touch mode)')
        vis = d.eval("getComputedStyle(document.getElementById('rps-touch')).display")
        check(vis == 'block', f'터치 버튼이 보이지 않음 ({vis})')
        d.shot('touch_overlay', '터치 조작 버튼')

        # 2) shop -> light armor
        g0 = d.state()['game']
        b = d.dom_center('#rps-touch [data-id="shop"]')
        d.tap(b['x'], b['y'])
        d.wait(lambda s: s['game'].get('shopOpen'), 5, 'shop open')
        d.tap_text('경량 방어구', exact=False)
        g1 = d.wait(lambda s: s['game'].get('armor', 0) >= 40, 5, 'armor 40')['game']
        notes.append(f'방어구 구매: 방어 {g0["armor"]}→{g1["armor"]}, 크레딧 {g0["credits"]}→{g1["credits"]}')
        check(g0['credits'] - g1['credits'] == 400, '방어구 가격(400)이 빠지지 않음')
        d.shot('shop_armor', '상점에서 경량 방어구 구매')
        d.tap_text('닫기 (B)')
        d.wait(lambda s: not s['game'].get('shopOpen'), 5, 'shop closed')
        if not d.state()['game']['locked']:
            d.tap(w * 0.5, h * 0.25)
            d.wait(lambda s: s['game'].get('locked'), 5, 'relocked')

        # 3) wait for the match to start, then walk out of the spawn room:
        #    turn toward the capture point with a look-drag, then push the
        #    joystick; repeat (spawn points are not always facing the door).
        d.wait(lambda s: s['game'].get('phase') == 'live', 15, 'match live')
        p0 = d.state()['game']['pos']
        jx, jy = w * 0.18, h * 0.72
        RAD_PER_PX = 1.7 * 0.0022  # touch look scale x default sensitivity
        for _ in range(8):
            g = d.state()['game']
            if not g['inSpawn']:
                break
            x, z = g['pos'][0], g['pos'][2]
            want = math.atan2(-x, z)  # forward = (sin yaw, -cos yaw) -> face the origin
            delta = (want - g['yaw'] + math.pi) % (2 * math.pi) - math.pi
            if abs(delta) > 0.1:
                px = max(-300, min(300, delta / RAD_PER_PX))
                d.hold(w * 0.55, h * 0.45, 0.1, dx=px)
            d.hold(jx, jy, 3.0, dy=-60)
        g = d.state()['game']
        moved = ((g['pos'][0] - p0[0]) ** 2 + (g['pos'][2] - p0[2]) ** 2) ** 0.5
        notes.append(f'조이스틱 이동 거리 {moved:.1f} m · 스폰룸 밖: {not g["inSpawn"]}')
        check(moved > 3, '조이스틱으로 이동하지 않음')
        check(not g['inSpawn'], '스폰룸 밖으로 나가지 못함')
        d.shot('moved', '조이스틱으로 스폰룸 밖으로 이동')

        # 4) look: drag on the right half
        yaw0 = d.state()['game']['yaw']
        d.hold(w * 0.62, h * 0.45, 0.2, dx=140)
        yaw1 = d.state()['game']['yaw']
        notes.append(f'시점 회전 {yaw0:.2f} → {yaw1:.2f} rad')
        check(abs(yaw1 - yaw0) > 0.05, '드래그로 시점이 돌지 않음')

        # 5) fire (needs to be outside the spawn room)
        g = d.state()['game']
        if g['inSpawn']:
            notes.append('경고: 아직 스폰룸 안이라 사격 검사는 건너뜀')
        else:
            f = d.dom_center('#rps-touch [data-id="fire"]')
            d.hold(f['x'], f['y'], 1.2)
            g2 = d.state()['game']
            notes.append(f'사격: 발사 수 {g["shotSeq"]}→{g2["shotSeq"]}, 탄창 {g["mag"]}→{g2["mag"]}')
            check(g2['shotSeq'] > g['shotSeq'], '발사 버튼으로 총이 나가지 않음')
            d.shot('fire', '발사 버튼으로 사격')

        # 6) skill Q (Pebble: gravel blink, 3 charges)
        g = d.state()['game']
        q = d.dom_center('#rps-touch [data-id="q"]')
        d.tap(q['x'], q['y'])
        time.sleep(0.4)
        g2 = d.state()['game']
        notes.append(f'Q 스킬: 충전 {g["skillCharges"][0]}→{g2["skillCharges"][0]}')
        check(g2['skillCharges'][0] < g['skillCharges'][0] or not g2['alive'], 'Q 스킬이 써지지 않음')
        d.shot('skill_q', 'Q 스킬(자갈 점멸) 사용')

        # 7) reload
        r = d.dom_center('#rps-touch [data-id="reload"]')
        d.tap(r['x'], r['y'])
        time.sleep(0.5)

    def s07_leave_match(self, notes):
        d = self.dev
        m = d.dom_center('#rps-touch [data-id="menu"]')
        d.tap(m['x'], m['y'])
        d.wait(lambda s: s.get('game') and not s['game'].get('locked'), 5, 'menu open')
        d.shot('pause_menu', '메뉴 (계속 · 설정 · 나가기)')
        d.tap_text('나가기')
        d.wait(lambda s: s.get('screen') == 'lobby', 10, 'back to lobby')
        notes.append('메뉴 → 나가기 → 로비 복귀')
        d.shot('left_match', '경기에서 나가 로비로 복귀')

    def s08_offline_exit(self, notes):
        d = self.dev
        t0 = time.time()
        d.cdp.call('Network.emulateNetworkConditions', offline=True, latency=0, downloadThroughput=-1,
                   uploadThroughput=-1)
        try:
            d.wait(lambda s: s.get('dialog') == 'network', 35, 'network alert')
            notes.append(f'오프라인 전환 후 {time.time() - t0:.1f}초 만에 알림')
            d.shot('offline_alert', '네트워크 끊김 알림')
            d.tap_text('확인')
            d.wait(lambda s: s.get('screen') == 'exited', 5, 'app exited')
            d.shot('offline_exited', '확인 후 앱 종료 화면')
        finally:
            d.cdp.call('Network.emulateNetworkConditions', offline=False, latency=0, downloadThroughput=-1,
                       uploadThroughput=-1)

    def s09_startup_no_api(self, notes):
        d = self.dev
        d.cdp.call('Network.setBlockedURLs', urls=['*/api/*'])
        try:
            d.navigate(self.url)
            seen = []
            end = time.time() + 40
            while time.time() < end:
                try:
                    s = d.state()
                except Exception:
                    s = {}
                if s.get('screen') and (not seen or seen[-1] != s['screen']):
                    seen.append(s['screen'])
                if s.get('dialog') == 'network':
                    break
                time.sleep(0.2)
            notes.append(f'화면 순서: {" → ".join(seen)}')
            check(d.state().get('dialog') == 'network', '시작할 때 서버 연결 불가 알림이 뜨지 않음')
            check('title' not in seen, '서버 없이 타이틀로 넘어감')
            d.shot('startup_alert', '시작 시 서버 연결 불가 알림')
            d.tap_text('확인')
            d.wait(lambda s: s.get('screen') == 'exited', 5, 'app exited')
            d.shot('startup_exited', '앱 종료 화면')
        finally:
            d.cdp.call('Network.setBlockedURLs', urls=[])

    # ----------------------------------------------------------- main
    def run(self):
        self.log(f'출력 폴더: {self.out}')
        ok_setup = True
        try:
            self.log('준비: 테스트 서버 시작')
            self.server.start()
            self.log('준비: 에뮬레이터 Chrome 연결')
            self.dev.prepare()
            self.log(f'기기: {self.dev.model} · Android {self.dev.android} · {self.dev.browser}')
            self.dev.open_tab(self.url)
            if self.recorder:
                self.log('화면 녹화 시작')
                self.recorder.start()
        except Exception as e:
            ok_setup = False
            self.results.append({'id': '00_setup', 'title': '준비', 'status': 'FAIL', 'seconds': 0,
                                 'notes': [repr(e)], 'shots': []})
            self.log(f'준비 실패: {e!r}')
        if ok_setup:
            steps = [
                ('01_splash', '스플래시 페이지', self.s01_splash),
                ('02_lobby_skeleton', '로비 진입 · 스켈레톤 UI', self.s02_lobby_skeleton),
                ('03_settings_save', '다크 모드 · 글자 크기 → 서버 저장', self.s03_settings_save),
                ('04_restart_persist', '서버 재시작 후에도 설정 유지', self.s04_restart_persist),
                ('05_match_load', '경기 로딩 스켈레톤 · 부활 무적', self.s05_match_load),
                ('06_touch_controls', '터치로 플레이 (상점·이동·시점·사격·스킬)', self.s06_touch_controls),
                ('07_leave_match', '경기 나가기', self.s07_leave_match),
                ('08_offline_exit', '접속 중 네트워크 끊김 → 알림 후 종료', self.s08_offline_exit),
                ('09_startup_no_api', '시작 시 서버 연결 불가 → 알림 후 종료', self.s09_startup_no_api),
            ]
            for sid, title, fn in steps:
                self.step(sid, title, fn)
        if self.recorder:
            video = self.recorder.stop()
            self.video = video
            self.log(f'화면 녹화: {video}')
        self.dev.close()
        if not self.keep_server:
            self.server.stop()
        self.report()
        return all(r['status'] == 'PASS' for r in self.results)

    def report(self):
        passed = sum(r['status'] == 'PASS' for r in self.results)
        total = len(self.results)
        with open(os.path.join(self.out, 'report.json'), 'w', encoding='utf-8') as f:
            json.dump({'device': getattr(self.dev, 'model', '?'), 'android': getattr(self.dev, 'android', '?'),
                       'browser': getattr(self.dev, 'browser', '?'), 'url': self.url, 'passed': passed,
                       'total': total, 'results': self.results}, f, ensure_ascii=False, indent=1)
        lines = [f'# RPS 에뮬레이터 통합 테스트', '',
                 f'- 실행: {dt.datetime.now():%Y-%m-%d %H:%M:%S}',
                 f'- 기기: {getattr(self.dev, "model", "?")} · Android {getattr(self.dev, "android", "?")} · '
                 f'{getattr(self.dev, "browser", "?")}',
                 f'- 주소: `{self.url}` (테스트 전용 서버, 포트 {self.port})',
                 f'- 결과: **{passed} / {total} 통과**',
                 f'- 화면 녹화: {getattr(self, "video", None) or "없음"}', '',
                 '| 단계 | 내용 | 결과 | 시간 |', '|---|---|---|---|']
        for r in self.results:
            lines.append(f'| {r["id"]} | {r["title"]} | {"✅ PASS" if r["status"] == "PASS" else "❌ FAIL"} | {r["seconds"]}s |')
        for r in self.results:
            lines += ['', f'## {r["id"]} {r["title"]} — {r["status"]}', '']
            lines += [f'- {n}' if '\n' not in n else f'```\n{n}\n```' for n in r['notes']]
            for fn, cap in r['shots']:
                lines += ['', f'![{cap}]({fn})', f'*{cap}*']
        with open(os.path.join(self.out, 'report.md'), 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines) + '\n')
        self.log(f'결과: {passed}/{total} 통과 · 보고서 {os.path.join(self.out, "report.md")}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--port', type=int, default=8095, help='port for the private test server')
    ap.add_argument('--only', default='', help='comma separated step ids/numbers to run (setup always runs)')
    ap.add_argument('--keep-server', action='store_true', help='leave the test server running afterwards')
    ap.add_argument('--record', action='store_true', help='record the device screen to out/<run>/test_video.mp4')
    args = ap.parse_args()
    ok = Runner(args).run()
    sys.exit(0 if ok else 1)


if __name__ == '__main__':
    main()
