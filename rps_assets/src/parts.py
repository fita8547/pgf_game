"""파츠 생성 헬퍼 + 팔레트. 모든 모델 파일이 여기서 import."""
import math

def _p(t, s, p, c, r=(0, 0, 0), n=None, a=None, m=None, o=None, parent=None, sc=None):
    d = {"t": t, "s": s, "p": [round(float(v), 5) for v in p], "r": [round(float(v), 3) for v in r], "c": c}
    if n: d["n"] = n
    if a is not None: d["a"] = a
    if m: d["m"] = m
    if o: d["o"] = [round(float(v), 5) for v in o]
    if parent: d["parent"] = parent
    if sc: d["sc"] = list(sc)
    return d

def box(s, p, c, **k): return _p("box", list(s), p, c, **k)
def rbox(s, p, c, b=None, bseg=2, **k): return _p("rbox", {"size": list(s), "b": b, "bseg": bseg}, p, c, **k)
def cyl(rt, rb, h, p, c, seg=20, bevel=None, **k):
    s = [rt, rb, h, seg] + ([bevel] if bevel is not None else [])
    return _p("cyl", s, p, c, **k)
def sph(r, p, c, ws=22, hs=14, **k): return _p("sph", [r, ws, hs], p, c, **k)
def cap(rad, l, p, c, r2=None, seg=18, **k): return _p("cap", {"r": rad, "l": l, "r2": r2, "seg": seg}, p, c, **k)
def lathe(prof, p, c, seg=20, smooth=None, **k): return _p("lathe", {"prof": [list(map(float, q)) for q in prof], "seg": seg, "smooth": smooth}, p, c, **k)
def ext(pts, w, p, c, ch=0.0, **k): return _p("ext", {"pts": [list(map(float, q)) for q in pts], "w": w, "c": ch}, p, c, **k)
def rock(s, p, c, seed=1, pts=18, j=0.25, **k): return _p("rock", {"size": list(s), "seed": seed, "n": pts, "j": j}, p, c, **k)
def empty(p, n, parent=None): return _p("empty", {}, p, "#000000", n=n, parent=parent)

Z = (90, 0, 0)    # Y축 형태를 Z축으로 눕힘 (위쪽 → +Z)
NZ = (-90, 0, 0)  # 위쪽 → -Z (총구 방향)

def ring(R, t, p, c, seg=12, plane="xz", a0=0, a1=360, w=None, n="ring", **k):
    out, span, w = [], a1 - a0, w or t
    L = 2 * R * math.sin(math.radians(span / seg) / 2) * 1.08
    for i in range(seg):
        d = a0 + span * (i + 0.5) / seg
        th = math.radians(d)
        cs, sn = R * math.cos(th), R * math.sin(th)
        if plane == "xz": q = box([t, w, L], (p[0] + cs, p[1], p[2] + sn), c, r=(0, -d, 0), n=f"{n}_{i}", **k)
        elif plane == "xy": q = box([t, L, w], (p[0] + cs, p[1] + sn, p[2]), c, r=(0, 0, d), n=f"{n}_{i}", **k)
        else: q = box([w, L, t], (p[0], p[1] + sn, p[2] + cs), c, r=(-d, 0, 0), n=f"{n}_{i}", **k)
        out.append(q)
    return out

def torus(R, t, p, c, plane="xz", seg=24, n="torus", **k):
    """얇은 링(원환): 회전체 대신 관 단면 근사 — 로우폴리 박스 링보다 매끈한 버전."""
    return ring(R, t, p, c, seg=seg, plane=plane, n=n, **k)

def dome(R, p, c, layers=6, seg=20, n="dome", **k):
    prof = [(R * math.cos(math.radians(90 * i / layers)), R * math.sin(math.radians(90 * i / layers))) for i in range(layers + 1)]
    prof = [(0, 0)] + prof
    prof[-1] = (0.0, R)
    return [lathe(prof, p, c, seg=seg, n=n, **k)]

def rail(length, p, c="#202328", teeth=None, n="rail", parent=None):
    """피카티니 레일: 베이스 + 톱니. p = 레일 중앙 바닥."""
    x, y, z = p
    out = [rbox([0.021, 0.006, length], (x, y + 0.003, z), c, b=0.0015, n=f"{n}_base", m="metal", parent=parent)]
    nt = teeth or max(2, int(length / 0.01))
    for i in range(nt):
        zz = z - length / 2 + length * (i + 0.5) / nt
        out.append(rbox([0.021, 0.004, length / nt * 0.55], (x, y + 0.008, zz), c, b=0.001, bseg=1, n=f"{n}_t{i}", m="metal", parent=parent))
    return out

def arc_pts(cx, cy, r, a0, a1, n=8):
    return [(cx + r * math.cos(math.radians(a0 + (a1 - a0) * i / n)), cy + r * math.sin(math.radians(a0 + (a1 - a0) * i / n))) for i in range(n + 1)]

# ---------------- 팔레트
GM, BK, SV, WD, GR, OR = "#3b4048", "#202328", "#b9bfc7", "#8b5a2b", "#5a6b3c", "#ff8a2a"
POLY, DARK, WD2, BRASS = "#2b2f35", "#121418", "#6b4423", "#d9b45a"
GLOW_R, GLOW_G, GLOW_W = "#ff4a3a", "#7cf0a0", "#f4f7ff"
STONE, STONE_D, LAVA, CRYSTAL = "#8d9096", "#4b4f55", "#ff5a1f", "#7fe0d0"
PAPER, FOLD, BLUE, INK, CARD = "#efe9dc", "#d3cbb9", "#4d8cf0", "#24407a", "#b98a55"
RED, RED_D, STEEL, THREAD = "#cf3a3a", "#5a1d22", "#c9ced6", "#f2c94c"
SMOKE, SKIN_D = "#9aa3b0", "#2a2d33"
