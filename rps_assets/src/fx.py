"""이펙트 모델: 사망(고양이·강아지 유령), 킬 배지(발바닥), 헤드샷 배지(고양이 얼굴).
모두 루트 노드 하나 아래에 있고 애니메이션 1개씩 포함."""
import math
from parts import *

GHOST, GHOST_D, HALO, PINK, XEYE = "#f4f8ff", "#cfdcf2", "#ffd84a", "#ffb3c7", "#3a3f4b"

def _ch(node, path, times, values):
    return {"node": node, "path": path, "times": times, "values": values}

def x_eye(x, y, z, k, parent, s=1.0):
    return [rbox([0.07 * s, 0.016 * s, 0.01], (x, y, z), XEYE, b=0.004 * s, r=(0, 0, 45), n=f"x_eye_{k}_a", parent=parent),
            rbox([0.07 * s, 0.016 * s, 0.01], (x, y, z), XEYE, b=0.004 * s, r=(0, 0, -45), n=f"x_eye_{k}_b", parent=parent)]

def ghost(kind):
    """kind: cat | dog. 원점 = 바닥, 유령은 y≈0.6에서 시작해 떠오름."""
    R = "ghost"
    P = [empty((0, 0, 0), "fx_root"), empty((0, 0.6, 0), R, parent="fx_root")]
    a = 0.82
    P += [sph(0.26, (0, 0.6, 0), GHOST, n="body", parent=R, sc=(1, 0.85, 1.15), a=a),
          cap(0.12, 0.25, (0, 0.38, -0.05), GHOST, r2=0.2, n="ghost_tail_wisp", parent=R, a=0.55),
          sph(0.2, (0, 0.94, 0.16), GHOST, n="head", parent=R, sc=(1.05, 0.92, 1.0), a=a)]
    if kind == "cat":
        for s in (-1, 1):
            P += [cyl(0, 0.07, 0.13, (s * 0.11, 1.12, 0.14), GHOST, seg=4, r=(0, 45, -s * 15), n=f"ear_{'L' if s > 0 else 'R'}", parent=R, sc=(1, 1, 0.6), a=a),
                  cyl(0, 0.04, 0.08, (s * 0.11, 1.11, 0.16), PINK, seg=4, r=(0, 45, -s * 15), n=f"ear_inner_{'L' if s > 0 else 'R'}", parent=R, sc=(1, 1, 0.5)),
                  rbox([0.12, 0.006, 0.006], (s * 0.15, 0.9, 0.32), XEYE, b=0.002, r=(0, 0, s * 8), n=f"whisker_{'L' if s > 0 else 'R'}_1", parent=R),
                  rbox([0.12, 0.006, 0.006], (s * 0.15, 0.87, 0.32), XEYE, b=0.002, r=(0, 0, -s * 4), n=f"whisker_{'L' if s > 0 else 'R'}_2", parent=R)]
        P.append(sph(0.022, (0, 0.9, 0.355), PINK, n="nose", parent=R))
        for i in range(4):
            P.append(sph(0.05 - i * 0.006, (0, 0.55 + i * 0.06, -0.3 - i * 0.07), GHOST, n=f"tail_{i}", parent=R, a=a))
    else:
        for s in (-1, 1):
            P += [cap(0.05, 0.14, (s * 0.19, 0.9, 0.12), "#e6d6c2", r=(0, 0, s * 20), n=f"ear_{'L' if s > 0 else 'R'}", parent=R, sc=(0.6, 1, 1))]
        P += [sph(0.09, (0, 0.88, 0.32), GHOST, n="snout", parent=R, sc=(1.1, 0.8, 1.0), a=a),
              sph(0.03, (0, 0.92, 0.41), XEYE, n="nose", parent=R, sc=(1.3, 1, 1)),
              cap(0.025, 0.04, (0.03, 0.81, 0.39), PINK, r=(20, 0, 0), n="tongue", parent=R)]
        P.append(cap(0.04, 0.12, (0, 0.62, -0.31), GHOST, r=(-40, 0, 0), n="tail", parent=R, a=a))
    P += x_eye(0.075, 0.97, 0.33, "L", R) + x_eye(-0.075, 0.97, 0.33, "R", R)
    for s in (-1, 1):
        nm = f"wing_{'L' if s > 0 else 'R'}"
        P.append(empty((s * 0.14, 0.72, -0.12), nm, parent=R))
        for i, (ry, L) in enumerate(((10, 0.34), (25, 0.28), (40, 0.22))):
            P.append(dict(rbox([L, 0.13 - i * 0.02, 0.025], (s * L / 2, 0.02 - i * 0.05, -0.02 * i), "#ffffff", b=0.012, r=(0, s * ry, s * 12), n=f"{nm}_feather_{i}", parent=nm, a=0.9), local=True))
    P.append(empty((0, 1.2, 0.12), "halo", parent=R))
    P += [dict(q, local=True) for q in ring(0.13, 0.03, (0, 0, 0), HALO, seg=18, n="halo_ring", parent="halo", m="glow")]
    for i, (x, z) in enumerate(((0.12, 0.12), (-0.12, 0.12), (0.12, -0.08), (-0.12, -0.08))):
        P.append(sph(0.05, (x, 0.42, z), GHOST, n=f"paw_{i}", parent=R, a=a))
    # 바닥의 발자국 흔적
    for i in range(4):
        x, z = (i % 2) * 0.18 - 0.09, -0.4 + i * 0.22
        P += [sph(0.045, (x, 0.005, z), GHOST_D, n=f"print_{i}_pad", parent="fx_root", sc=(1, 0.12, 1.1), a=0.6)]
    t = [0, 0.3, 0.8, 1.4, 2.0, 2.6]
    anim = {"name": "death", "channels": [
        _ch(R, "translation", t, [(0, -0.3, 0), (0, 0.0, 0), (0.05, 0.35, 0), (-0.05, 0.8, 0), (0.05, 1.3, 0), (0, 1.8, 0)]),
        _ch(R, "rotation", t, [(0, 0, 0), (0, 10, 6), (0, -10, -6), (0, 10, 6), (0, -10, -6), (0, 0, 0)]),
        _ch(R, "scale", [0, 0.3, 2.2, 2.6], [(0.2, 0.2, 0.2), (1.08, 1.08, 1.08), (1, 1, 1), (0.6, 0.6, 0.6)]),
        _ch("wing_L", "rotation", [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6], [(0, 0, a_) for a_ in (0, 30, -10, 30, -10, 30, -10, 30, -10, 30, -10, 30, -10, 0)]),
        _ch("wing_R", "rotation", [0, 0.2, 0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8, 2.0, 2.2, 2.4, 2.6], [(0, 0, -a_) for a_ in (0, 30, -10, 30, -10, 30, -10, 30, -10, 30, -10, 30, -10, 0)]),
        _ch("halo", "translation", [0, 0.6, 1.2, 1.8, 2.6], [(0, 0, 0), (0, 0.03, 0), (0, 0, 0), (0, 0.03, 0), (0, 0, 0)]),
        _ch("halo", "rotation", [0, 1.3, 2.6], [(0, 0, 0), (0, 180, 0), (0, 359, 0)]),
    ]}
    return P, anim

def kill_badge(kind):
    """kind: paw | headshot. 정면 +Z를 바라보는 지름 약 0.2m 배지."""
    R = "badge"
    P = [empty((0, 0, 0), R)]
    rim = HALO
    P += [lathe([(0, -0.012), (0.09, -0.012), (0.1, -0.004), (0.1, 0.004), (0.09, 0.012), (0, 0.012)], (0, 0, 0), "#1f232b", seg=32, r=Z, n="disc", parent=R),
          dict(lathe([(0.088, -0.016), (0.104, -0.016), (0.11, 0.0), (0.104, 0.016), (0.088, 0.016)], (0, 0, 0), rim, seg=32, r=Z, n="rim", parent=R, m="metal"), local=True)]
    P = [dict(q, local=True) if q.get("parent") else q for q in P]
    if kind == "paw":
        col = "#ff5a6e"
        P += [dict(sph(0.035, (0, -0.018, 0.012), col, n="paw_pad", parent=R, sc=(1.15, 0.95, 0.35), m="glow"), local=True)]
        for i, (x, y) in enumerate(((-0.042, 0.022), (-0.015, 0.045), (0.015, 0.045), (0.042, 0.022))):
            P.append(dict(sph(0.016, (x, y, 0.012), col, n=f"paw_toe_{i}", parent=R, sc=(1, 1.15, 0.35), m="glow"), local=True))
    else:
        col = "#ff3b30"
        P += [dict(sph(0.05, (0, -0.005, 0.012), "#f4f1e8", n="cat_face", parent=R, sc=(1.15, 0.95, 0.3)), local=True)]
        for s in (-1, 1):
            P += [dict(cyl(0, 0.022, 0.04, (s * 0.035, 0.045, 0.012), "#f4f1e8", seg=4, r=(0, 45, -s * 18), n=f"cat_ear_{s}", parent=R, sc=(1, 1, 0.4)), local=True)]
            P += [dict(q, local=True) for q in x_eye(s * 0.022, 0.0, 0.03, f"{s}", R, s=0.32)]
        P += [dict(q, local=True) for q in ring(0.075, 0.006, (0, 0, 0.016), col, seg=24, plane="xy", n="crosshair_ring", parent=R, m="glow")]
        for i, (x, y, w, h) in enumerate(((0, 0.085, 0.006, 0.03), (0, -0.085, 0.006, 0.03), (0.085, 0, 0.03, 0.006), (-0.085, 0, 0.03, 0.006))):
            P.append(dict(rbox([w, h, 0.006], (x, y, 0.016), col, b=0.002, n=f"crosshair_tick_{i}", parent=R, m="glow"), local=True))
    for i in range(6):
        a = math.radians(i * 60 + 30)
        P.append(dict(cyl(0, 0.012, 0.035, (0.14 * math.cos(a), 0.14 * math.sin(a), 0), rim, seg=4, r=(0, 0, i * 60 + 30 - 90), n=f"spark_{i}", parent=R, m="glow"), local=True))
    anim = {"name": "pop", "channels": [
        _ch(R, "scale", [0, 0.12, 0.22, 0.3, 1.0, 1.2], [(0.01, 0.01, 0.01), (1.3, 1.3, 1.3), (0.92, 0.92, 0.92), (1, 1, 1), (1, 1, 1), (0.01, 0.01, 0.01)]),
        _ch(R, "rotation", [0, 0.3, 1.2], [(0, -180, 0), (0, 0, 0), (0, 0, 0)]),
    ]}
    return P, anim

FX = [
    ("death_cat", "사망 · 고양이 유령", lambda: ghost("cat")),
    ("death_dog", "사망 · 강아지 유령", lambda: ghost("dog")),
    ("kill_paw", "킬 배지 · 발바닥", lambda: kill_badge("paw")),
    ("kill_headshot", "킬 배지 · 헤드샷", lambda: kill_badge("headshot")),
]
