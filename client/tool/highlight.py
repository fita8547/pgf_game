"""Record a short gameplay highlight video with the real game (no AI video).

Headless Chrome (real GPU) plays one practice match as a chosen character,
driven by a small script (move, look, skills, aim at the nearest visible
enemy, fire). Frames come from the DevTools screencast; ffmpeg joins them
and lays the map's background music under it.

  python client/tool/highlight.py OUT.mp4 [--char origami] [--map desert_ruins] [--seconds 32]

Needs the RPS server on http://localhost:8090 (web build with ?debug hooks),
Pillow not required, imageio-ffmpeg for ffmpeg.
"""
import argparse
import base64
import json
import math
import os
import queue
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'integration'))
from emulator_test import CDP  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
KEYS = {'KeyW': ('w', 87), 'KeyQ': ('q', 81), 'KeyE': ('e', 69), 'KeyC': ('c', 67), 'KeyV': ('v', 86),
        'Space': (' ', 32), 'KeyR': ('r', 82)}


class Recorder:
    def __init__(self, cdp, folder):
        self.cdp, self.folder = cdp, folder
        self.frames = []  # (timestamp, path)
        self.on = False
        threading.Thread(target=self._loop, daemon=True).start()

    def _loop(self):
        while True:
            try:
                m = self.cdp.events.get(timeout=0.5)
            except queue.Empty:
                if self.cdp.closed:
                    return
                continue
            if m.get('method') != 'Page.screencastFrame':
                continue
            p = m['params']
            if self.on:
                fn = os.path.join(self.folder, f'f{len(self.frames):05d}.jpg')
                with open(fn, 'wb') as f:
                    f.write(base64.b64decode(p['data']))
                self.frames.append((p['metadata']['timestamp'], fn))
            try:
                self.cdp.call('Page.screencastFrameAck', sessionId=p['sessionId'], timeout=5)
            except Exception:
                pass


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--char', default='origami')
    ap.add_argument('--map', default='desert_ruins')
    ap.add_argument('--seconds', type=float, default=32)
    ap.add_argument('--url', default='http://localhost:8090')
    a = ap.parse_args()
    import imageio_ffmpeg
    ff = imageio_ffmpeg.get_ffmpeg_exe()

    work = tempfile.mkdtemp(prefix='rps-hl-')
    prof = os.path.join(work, 'profile')
    port = 9336
    proc = subprocess.Popen([CHROME, '--headless=new', f'--remote-debugging-port={port}', f'--user-data-dir={prof}',
                             '--window-size=1280,720', '--use-angle=d3d11', '--enable-gpu', '--ignore-gpu-blocklist',
                             '--autoplay-policy=no-user-gesture-required', 'about:blank'],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                tabs = json.load(urllib.request.urlopen(f'http://127.0.0.1:{port}/json'))
                break
            except OSError:
                time.sleep(0.2)
        page = next(t for t in tabs if t['type'] == 'page')
        cdp = CDP(page['webSocketDebuggerUrl'])
        cdp.call('Page.enable')
        cdp.call('Emulation.setDeviceMetricsOverride', width=1280, height=720, deviceScaleFactor=1.5, mobile=False)

        def ev(js):
            r = cdp.call('Runtime.evaluate', expression=js, returnByValue=True, awaitPromise=True, timeout=30)
            return r.get('result', {}).get('value')

        def key(code, down):
            k, vk = KEYS[code]
            cdp.call('Input.dispatchKeyEvent', type='keyDown' if down else 'keyUp', code=code, key=k,
                     windowsVirtualKeyCode=vk)

        def tap(code):
            key(code, True)
            time.sleep(0.12)
            key(code, False)

        def mouse(down):
            cdp.call('Input.dispatchMouseEvent', type='mousePressed' if down else 'mouseReleased', x=640, y=360,
                     button='left', clickCount=1)

        rec = Recorder(cdp, work)
        cdp.call('Page.startScreencast', format='jpeg', quality=88, maxWidth=1920, maxHeight=1080, everyNthFrame=1)

        # --- clip 1: lobby with the character on the turntable
        cdp.call('Page.navigate', url=f'{a.url}/?screen=lobby')
        time.sleep(1.0)
        ev(f"localStorage.clear();localStorage.setItem('rps.lang','ko');localStorage.setItem('rps.char','{a.char}');"
           f"localStorage.setItem('rps.map','{a.map}');localStorage.setItem('rps.bot','0.15');"
           "localStorage.setItem('rps.quality','2');true")
        cdp.call('Page.navigate', url=f'{a.url}/?screen=lobby')
        for _ in range(80):
            time.sleep(0.25)
            if ev("!!(window.rpsEngine && rpsEngine.mode === 'lobby' && rpsEngine.lobbyTurn.children.length)"):
                break
        time.sleep(1.5)
        rec.on = True
        t_lobby0 = time.time()
        time.sleep(4.5)
        rec.on = False
        lobby_frames = len(rec.frames)

        # --- clip 2: the match
        cdp.call('Page.navigate', url=f'{a.url}/?screen=game&char={a.char}&map={a.map}&debug&fakelock&nopause=1')
        for _ in range(160):
            time.sleep(0.25)
            if ev("!!(window.rpsDebug && rpsDebug.me && rpsDebug.me()[4] === 1)"):
                break
        time.sleep(0.8)
        rec.on = True
        start = time.time()
        moving = False
        fired_ult = False
        used = set()
        fire_until = 0
        while time.time() - start < a.seconds:
            t = time.time() - start
            me = ev('rpsDebug.me()') or [0, 0, 0, 0, 0, 0]
            dist = ev('rpsDebug.aimNearest()') if t > 5.5 else -1
            if t < 5.5:  # pregame: slow look around the spawn
                ev(f'rpsDebug.look({math.atan2(-me[0], me[2]) + 0.9 * math.sin(t * 0.7)}, 0.05)')
            elif dist is not None and 0 < dist < 45 and me[4]:
                if moving:
                    key('KeyW', False)
                    moving = False
                if not fired_ult and t > 12:
                    ev('rpsDebug.ult()')
                    tap('KeyV')  # Shuriken Storm
                    fired_ult = True
                if time.time() > fire_until:
                    mouse(True)
                    time.sleep(0.15)
                    mouse(False)
                    fire_until = time.time() + 0.25
            else:
                if me[4]:
                    ev(f'rpsDebug.look({math.atan2(-me[0], me[2])}, 0.0)')  # head for the point
                    if not moving:
                        key('KeyW', True)
                        moving = True
                    if 'q' not in used and t > 7:
                        tap('KeyQ')  # Paper Updraft
                        used.add('q')
                    elif 'e' not in used and t > 9.5:
                        tap('KeyE')  # Paper Dash
                        used.add('e')
            time.sleep(0.08)
        if moving:
            key('KeyW', False)
        rec.on = False
        cdp.call('Page.stopScreencast')
        time.sleep(0.5)
        cdp.close()
    finally:
        proc.kill()

    # --- assemble: frame durations from screencast timestamps
    frames = rec.frames
    lst = os.path.join(work, 'frames.txt')
    with open(lst, 'w', encoding='utf-8') as f:
        for i, (ts, fn) in enumerate(frames):
            if i + 1 < len(frames) and i + 1 != lobby_frames:
                d = max(0.01, min(0.2, frames[i + 1][0] - ts))
            else:
                d = 1 / 30
            f.write(f"file '{fn.replace(os.sep, '/')}'\nduration {d:.4f}\n")
        f.write(f"file '{frames[-1][1].replace(os.sep, '/')}'\n")
    total = sum(min(0.2, max(0.01, frames[i + 1][0] - frames[i][0])) for i in range(len(frames) - 1))
    music = os.path.join(ROOT, 'song', 'rps_arena.mp3')
    subprocess.run([ff, '-y', '-f', 'concat', '-safe', '0', '-i', lst, '-i', music,
                    '-vf', 'fps=30,scale=1920:-2,format=yuv420p',
                    '-af', f'volume=0.55,afade=t=in:d=1,afade=t=out:st={max(0, total - 2.5):.2f}:d=2.5',
                    '-c:v', 'libx264', '-preset', 'medium', '-crf', '20', '-c:a', 'aac', '-b:a', '160k',
                    '-shortest', '-movflags', '+faststart', a.out], check=True, capture_output=True)
    shutil.rmtree(work, ignore_errors=True)
    print(f'saved {a.out}: {len(frames)} frames, ~{total:.1f}s (lobby {lobby_frames} frames)')


if __name__ == '__main__':
    main()
