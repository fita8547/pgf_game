"""Dev tool: open a page in headless Chrome, wait in real time, run optional
JS, save screenshots and print console output. Python stdlib only.

  python tool/cdp_shot.py URL OUT.png [--wait 12] [--js "code"] [--at 5:"code"] [--shots 3]

--at T:"code"  runs code T seconds after load (repeatable)
--shots N      saves N screenshots evenly over the wait (OUT_1.png ...)
"""
import argparse, base64, json, os, socket, struct, subprocess, sys, tempfile, time, urllib.request

CHROME = r"C:\Program Files\Google\Chrome\Application\chrome.exe"


class WS:
    def __init__(self, url):
        host, path = url[len("ws://"):].split("/", 1)
        h, p = host.split(":")
        self.s = socket.create_connection((h, int(p)))
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.send((f"GET /{path} HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                     f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n").encode())
        buf = b""
        while b"\r\n\r\n" not in buf:
            buf += self.s.recv(4096)
        self.rest = buf.split(b"\r\n\r\n", 1)[1]
        self.id = 0
        self.events = []

    def _recv(self, n):
        while len(self.rest) < n:
            chunk = self.s.recv(1 << 20)
            if not chunk:
                raise EOFError
            self.rest += chunk
        out, self.rest = self.rest[:n], self.rest[n:]
        return out

    def recv(self):
        data = b""
        while True:
            b0, b1 = self._recv(2)
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._recv(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._recv(8))[0]
            data += self._recv(n)
            if b0 & 0x80:
                return json.loads(data)

    def send(self, method, **params):
        self.id += 1
        payload = json.dumps({"id": self.id, "method": method, "params": params}).encode()
        hdr = bytes([0x81])
        n = len(payload)
        if n < 126:
            hdr += bytes([0x80 | n])
        elif n < 65536:
            hdr += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            hdr += bytes([0x80 | 127]) + struct.pack(">Q", n)
        mask = os.urandom(4)
        self.s.send(hdr + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
        want = self.id
        while True:
            m = self.recv()
            if m.get("id") == want:
                return m.get("result", m)
            self.events.append(m)

    def pump(self, seconds):
        self.s.settimeout(0.05)
        end = time.time() + seconds
        while time.time() < end:
            try:
                self.events.append(self.recv())
            except (socket.timeout, TimeoutError):
                pass
        self.s.settimeout(None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("out")
    ap.add_argument("--wait", type=float, default=12)
    ap.add_argument("--js", default=None)
    ap.add_argument("--at", action="append", default=[])
    ap.add_argument("--shots", type=int, default=1)
    ap.add_argument("--click", action="append", default=[], help="T:x,y  real mouse click at T seconds")
    ap.add_argument("--size", default="1600,900")
    ap.add_argument("--touch", action="store_true", help="emulate a phone (touch, mobile viewport)")
    ap.add_argument("--throttle", type=float, default=0, help="limit download to N KB/s (to see loading screens)")
    ap.add_argument("--tap", action="append", default=[], help="T:x,y[,x2,y2]  touch tap or drag at T seconds")
    a = ap.parse_args()

    prof = tempfile.mkdtemp(prefix="rps-cdp-")
    port = 9333
    proc = subprocess.Popen([CHROME, "--headless=new", f"--remote-debugging-port={port}", f"--user-data-dir={prof}",
                             f"--window-size={a.size}", "--autoplay-policy=no-user-gesture-required",
                             "--use-angle=d3d11", "--enable-gpu", "--ignore-gpu-blocklist", "about:blank"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(50):
            try:
                tabs = json.load(urllib.request.urlopen(f"http://127.0.0.1:{port}/json"))
                break
            except OSError:
                time.sleep(0.2)
        page = next(t for t in tabs if t["type"] == "page")
        ws = WS(page["webSocketDebuggerUrl"])
        ws.send("Runtime.enable")
        ws.send("Page.enable")
        if a.touch:
            w, h = (int(v) for v in a.size.split(","))
            ws.send("Emulation.setDeviceMetricsOverride", width=w, height=h, deviceScaleFactor=2, mobile=True)
            ws.send("Emulation.setTouchEmulationEnabled", enabled=True, maxTouchPoints=5)
            ws.send("Emulation.setEmitTouchEventsForMouse", enabled=True)
        if a.throttle:
            ws.send("Network.enable")
            ws.send("Network.emulateNetworkConditions", offline=False, latency=40,
                    downloadThroughput=a.throttle * 1024, uploadThroughput=-1)
        ws.send("Page.navigate", url=a.url)
        at = sorted([(float(x.split(":", 1)[0]), x.split(":", 1)[1]) for x in a.at] +
                    [(float(x.split(":", 1)[0]), "CLICK:" + x.split(":", 1)[1]) for x in a.click] +
                    [(float(x.split(":", 1)[0]), "TAP:" + x.split(":", 1)[1]) for x in a.tap])
        start = time.time()
        shots = [a.wait * (i + 1) / a.shots for i in range(a.shots)]
        base, ext = os.path.splitext(a.out)
        while shots:
            now = time.time() - start
            nxt = min([t for t, _ in at] + [shots[0]])
            if nxt > now:
                ws.pump(nxt - now)
            now = time.time() - start
            while at and at[0][0] <= now:
                code = at.pop(0)[1]
                if code.startswith("TAP:"):
                    v = [float(t) for t in code[4:].split(",")]
                    x, y = v[0], v[1]
                    x2, y2 = (v[2], v[3]) if len(v) >= 4 else (x, y)
                    ws.send("Input.dispatchTouchEvent", type="touchStart", touchPoints=[{"x": x, "y": y}])
                    for k in range(1, 9):
                        ws.pump(0.03)
                        ws.send("Input.dispatchTouchEvent", type="touchMove",
                                touchPoints=[{"x": x + (x2 - x) * k / 8, "y": y + (y2 - y) * k / 8}])
                    ws.send("Input.dispatchTouchEvent", type="touchEnd", touchPoints=[])
                    print("[tap]", v)
                    continue
                if code.startswith("CLICK:"):
                    x, y = (float(v) for v in code[6:].split(","))
                    for t in ("mousePressed", "mouseReleased"):
                        ws.send("Input.dispatchMouseEvent", type=t, x=x, y=y, button="left", clickCount=1)
                    print("[click]", x, y)
                    continue
                r = ws.send("Runtime.evaluate", expression=code, returnByValue=True, awaitPromise=True)
                print("[js]", json.dumps(r.get("result", {}).get("value"), ensure_ascii=False)[:500])
            if shots and shots[0] <= now:
                shots.pop(0)
                if a.js:
                    r = ws.send("Runtime.evaluate", expression=a.js, returnByValue=True)
                    print("[js]", json.dumps(r.get("result", {}).get("value"), ensure_ascii=False)[:500])
                img = ws.send("Page.captureScreenshot", format="png")
                name = a.out if a.shots == 1 else f"{base}_{a.shots - len(shots)}{ext}"
                open(name, "wb").write(base64.b64decode(img["data"]))
                print("saved", name, f"t={now:.1f}s")
        for e in ws.events:
            if e.get("method") == "Runtime.consoleAPICalled":
                args = " ".join(str(x.get("value", x.get("description", ""))) for x in e["params"]["args"])
                if "GL Driver" not in args:
                    print(f"[console.{e['params']['type']}]", args[:400])
            elif e.get("method") == "Runtime.exceptionThrown":
                print("[exception]", json.dumps(e["params"]["exceptionDetails"], ensure_ascii=False)[:600])
    finally:
        proc.kill()


if __name__ == "__main__":
    main()
