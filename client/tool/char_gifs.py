"""Make looping animated GIFs of the 12 characters (for slides / README).

Renders each character with the real game engine (headless Chrome + three.js),
playing its lobby_idle animation with a gentle sway, on a flat background
(no pedestal, no gun). The animation time and the sway are driven per frame,
so the loop is seamless and does not depend on capture speed.

  python client/tool/char_gifs.py OUT_DIR [--url http://localhost:8090] [--bg F4EEE2] [--frames 24]

Needs a running RPS server serving the web build, and Pillow.
"""
import argparse
import base64
import io
import json
import math
import os
import subprocess
import sys
import tempfile
import time
import urllib.request

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), 'integration'))
from emulator_test import CDP  # noqa: E402  (stdlib DevTools client)

from PIL import Image  # noqa: E402

CHROME = r'C:\Program Files\Google\Chrome\Application\chrome.exe'
CHARS = ['boulder', 'cardboard', 'shear', 'origami', 'pebble', 'snip',
         'gem', 'needle', 'scroll', 'inkwell', 'quake', 'staple']


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('out')
    ap.add_argument('--url', default='http://localhost:8090')
    ap.add_argument('--bg', default='F4EEE2', help='background colour (hex, no #)')
    ap.add_argument('--frames', type=int, default=24)
    ap.add_argument('--size', default='420,520', help='viewport W,H in CSS px (rendered at 2x)')
    ap.add_argument('--only', default='')
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    w, h = (int(v) for v in a.size.split(','))
    chars = a.only.split(',') if a.only else CHARS

    prof = tempfile.mkdtemp(prefix='rps-gif-')
    port = 9335
    proc = subprocess.Popen([CHROME, '--headless=new', f'--remote-debugging-port={port}', f'--user-data-dir={prof}',
                             f'--window-size={w},{h}', '--force-device-scale-factor=2', '--use-angle=d3d11',
                             '--enable-gpu', '--ignore-gpu-blocklist', 'about:blank'],
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
        cdp.call('Emulation.setDeviceMetricsOverride', width=w, height=h, deviceScaleFactor=2, mobile=False)

        def ev(js):
            r = cdp.call('Runtime.evaluate', expression=js, returnByValue=True, awaitPromise=True, timeout=60)
            if 'exceptionDetails' in r:
                raise RuntimeError(json.dumps(r['exceptionDetails'])[:400])
            return r.get('result', {}).get('value')

        cdp.call('Page.navigate', url=f'{a.url}/?screen=lobby')
        for _ in range(120):
            time.sleep(0.25)
            try:
                if ev("!!(window.rpsEngine && rpsEngine.lobbyScene && rpsEngine.mode === 'lobby')"):
                    break
            except RuntimeError:
                pass
        time.sleep(1.0)
        # Only the 3D canvas, on a flat background; no pedestal.
        ev(f"""(() => {{
            document.getElementById('flutter-host').style.display = 'none';
            document.body.style.background = '#{a.bg}';
            const e = rpsEngine;
            for (const o of e.lobbyScene.children) if (o.isMesh) o.visible = false;
            e.setLobbyOffset(0);
            return true; }})()""")

        for cid in chars:
            ev(f"""(async () => {{
                const e = rpsEngine;
                await e.showLobby('{cid}', 'pistol');
                e.setLobbyOffset(0);
                // no gun: empty the weapon socket
                e.lobbyTurn.traverse((o) => {{ if (o.name === 'weapon_socket_R') o.clear(); }});
                // we drive the animation clock ourselves
                if (e.lobbyMixer) e.mixers.delete(e.lobbyMixer);
                return true; }})()""")
            dur = ev("""(() => { const m = rpsEngine.lobbyMixer; if (!m) return 0;
                const a = m._actions[0]; return a ? a.getClip().duration : 0; })()""") or 2.0
            frames = []
            for i in range(a.frames):
                ph = i / a.frames
                ev(f"""(() => {{ const e = rpsEngine;
                    if (e.lobbyMixer) e.lobbyMixer.setTime({ph * dur});
                    e.lobbyTurn.rotation.y = 0.35 + 0.45 * Math.sin({2 * math.pi * ph});
                    return new Promise((r) => requestAnimationFrame(() => requestAnimationFrame(() => r(true)))); }})()""")
                ev(f"(() => {{ rpsEngine.lobbyTurn.rotation.y = 0.35 + 0.45 * Math.sin({2 * math.pi * ph}); return true; }})()")
                png = base64.b64decode(cdp.call('Page.captureScreenshot', format='png')['data'])
                frames.append(Image.open(io.BytesIO(png)).convert('RGB'))
            # trim to the character (same box for all frames), with padding
            bg = tuple(int(a.bg[i:i + 2], 16) for i in (0, 2, 4))
            box = None
            for f in frames:
                diff = Image.eval(f, lambda v: v)  # copy
                mask = Image.new('L', f.size, 0)
                px = f.load()
                mp = mask.load()
                for y in range(0, f.size[1], 2):
                    for x in range(0, f.size[0], 2):
                        r, g, b = px[x, y]
                        if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 24:
                            mp[x, y] = 255
                bb = mask.getbbox()
                if bb:
                    box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]),
                                                  max(box[3], bb[3]))
            if box:
                pad = 24
                box = (max(0, box[0] - pad), max(0, box[1] - pad), min(frames[0].size[0], box[2] + pad),
                       min(frames[0].size[1], box[3] + pad))
                frames = [f.crop(box) for f in frames]
            out = os.path.join(a.out, f'{cid}.gif')
            pal = [f.convert('P', palette=Image.Palette.ADAPTIVE, colors=128) for f in frames]
            pal[0].save(out, save_all=True, append_images=pal[1:], duration=int(dur * 1000 / a.frames), loop=0,
                        optimize=True, disposal=1)
            frames[0].save(os.path.join(a.out, f'{cid}.png'))
            print(f'{cid}: {len(frames)} frames, clip {dur:.2f}s, {os.path.getsize(out) // 1024} KB, {frames[0].size}',
                  flush=True)
        cdp.close()
    finally:
        proc.kill()


if __name__ == '__main__':
    main()
