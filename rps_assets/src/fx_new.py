"""전투 이펙트 모델 (glb/fx/). 반투명은 BLEND. 모두 루트 노드 fx_root 아래.
- muzzle_flash : 총구 화염 약 0.3 m. 원점 = 총구, 불꽃은 -Z(총구 방향)로 뻗음. 매 발 Z축으로 무작위 회전해 쓰면 좋음.
- impact       : 탄착 불꽃. 원점 = 맞은 점, +Z = 표면 바깥(노멀) 방향.
- explosion    : 폭발. 클립 boom 0.6초. 최대 반경 약 1.6 m (코드에서 폭발 반경에 맞춰 스케일).
- smoke_cloud  : 먹물 연막. 반경 1 m 기준 (코드에서 늘림). 원점 = 바닥 중앙.
- ink_wall     : 먹물 벽. X축 1 m 길이 단위, 높이 3 m, 원점 = 바닥 중앙. X로 이어 붙여도 이음매가 맞음.
- heal_beam    : 치유 실·광선. 원점에서 +Z로 1 m (코드에서 Z 스케일로 늘림).
- match_victory: 게임 종료(승리). 트로피 + 섬광 + 색종이. 클립 victory 3초, 마지막 자세 유지. 카메라 앞 약 3 m에 두거나 결과 화면 3D 배경으로.
- match_defeat : 게임 종료(패배). 회색 트로피가 쓰러지고 먹구름에서 재가 떨어짐. 클립 defeat 3초.
- capture_flag : 거점 중앙 깃대 3.6 m + 깃발. 'team' 이 들어간 머티리얼(team_flag, team_glow, team_light)을 코드에서 팀 색으로 칠함. 클립 wave(루프 2초).
"""
import math
import numpy as np
from parts import *

FLASH_Y, FLASH_O, FLASH_W = "#fff2a8", "#ffb347", "#fffbe8"
SPARK, SPARK_O = "#ffe9a0", "#ff9a3c"
FIRE_Y, FIRE_O, FIRE_R, SMOKE_D = "#ffd36b", "#ff8a2a", "#d9431e", "#3b3a3f"
INKC, INK2 = "#1b2236", "#2a3552"
HEAL, HEAL_C = "#7cf0a0", "#e9fff0"

def _ch(node, path, times, values):
    return {"node": node, "path": path, "times": times, "values": values}

def root():
    return [empty((0, 0, 0), "fx_root")]

def muzzle_flash():
    P = root()
    # 중심 섬광 + 앞으로 뻗는 불꽃 + 십자 꽃잎 (모두 빛나는 반투명)
    P += [sph(0.035, (0, 0, -0.01), FLASH_W, ws=10, hs=8, n="core", parent="fx_root", m="glow", a=0.95),
          cyl(0, 0.045, 0.22, (0, 0, -0.12), FLASH_Y, seg=8, r=NZ, n="jet", parent="fx_root", m="glow", a=0.8),
          cyl(0, 0.03, 0.30, (0, 0, -0.16), FLASH_W, seg=6, r=NZ, n="jet_core", parent="fx_root", m="glow", a=0.9)]
    for k in range(4):
        a = k * 90 + 45
        x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
        P.append(cyl(0, 0.022, 0.11, (0.055 * x, 0.055 * y, -0.035), FLASH_O, seg=4, r=(0, 0, a - 90), n=f"petal_{k}", parent="fx_root", m="glow", a=0.85, sc=(1, 1, 0.35)))
    for k in range(3):
        a = k * 120
        x, y = math.cos(math.radians(a)), math.sin(math.radians(a))
        P.append(cyl(0, 0.014, 0.16, (0.03 * x, 0.03 * y, -0.09), FLASH_Y, seg=4, r=(0, 0, a - 90), n=f"spike_{k}", parent="fx_root", m="glow", a=0.8))
    return P, None

def impact():
    P = root()
    P += [sph(0.035, (0, 0, 0.01), FLASH_W, ws=10, hs=8, n="flash", parent="fx_root", m="glow", a=0.9, sc=(1, 1, 0.5)),
          cyl(0.06, 0.06, 0.004, (0, 0, 0.002), SPARK_O, seg=12, r=Z, n="scorch_glow", parent="fx_root", m="glow", a=0.45)]
    rng = np.random.default_rng(7)
    for k in range(9):
        th = rng.uniform(0, 360); el = rng.uniform(20, 70)
        d = np.array([math.cos(math.radians(el)) * math.cos(math.radians(th)), math.cos(math.radians(el)) * math.sin(math.radians(th)), math.sin(math.radians(el))])
        L = rng.uniform(0.06, 0.14)
        # 원통(+Y)을 방향 d로 눕힘
        rx = math.degrees(math.atan2(d[2], d[1])); rz = math.degrees(math.asin(max(-1, min(1, -d[0]))))
        P.append(cyl(0.003, 0.009, L, tuple(d * (0.02 + L / 2)), SPARK if k % 2 else SPARK_O, seg=4, r=(rx, 0, rz), n=f"spark_{k}", parent="fx_root", m="glow", a=0.9))
    return P, None

def explosion():
    P = root()
    P += [empty((0, 0, 0), "fireball", parent="fx_root"), empty((0, 0, 0), "smoke", parent="fx_root"),
          empty((0, 0, 0), "shock", parent="fx_root"), empty((0, 0, 0), "flash", parent="fx_root")]
    rng = np.random.default_rng(3)
    loc = lambda q: dict(q, local=True)
    P.append(loc(sph(0.6, (0, 0, 0), FIRE_Y, n="fire_core", parent="fireball", m="glow", a=0.9)))
    for k in range(9):
        v = rng.normal(size=3); v[1] = abs(v[1]) * 0.8; v /= np.linalg.norm(v)
        P.append(loc(rock([0.75, 0.75, 0.75], tuple(v * 0.45), FIRE_O if k % 3 else FIRE_R, seed=40 + k, pts=16, j=0.3, n=f"fire_puff_{k}", parent="fireball", m="glow", a=0.85)))
    for k in range(8):
        a = k * 45 + 20
        P.append(loc(rock([0.8, 0.6, 0.8], (0.7 * math.cos(math.radians(a)), 0.25 + 0.1 * (k % 2), 0.7 * math.sin(math.radians(a))), SMOKE_D, seed=60 + k, pts=16, j=0.3, n=f"smoke_puff_{k}", parent="smoke", a=0.7)))
    P += [loc(q) for q in ring(1.0, 0.06, (0, 0.05, 0), FIRE_O, seg=20, n="shock_ring", parent="shock", m="glow", a=0.6)]
    P.append(loc(sph(0.5, (0, 0, 0), FLASH_W, n="flash_ball", parent="flash", m="glow", a=0.8)))
    t = [0, 0.06, 0.18, 0.36, 0.6]
    anim = {"name": "boom", "channels": [
        _ch("flash", "scale", [0, 0.05, 0.12, 0.13, 0.6], [(0.3,) * 3, (2.6,) * 3, (0.8,) * 3, (0.001,) * 3, (0.001,) * 3]),
        _ch("fireball", "scale", t, [(0.2,) * 3, (1.4,) * 3, (1.9,) * 3, (1.2,) * 3, (0.001,) * 3]),
        _ch("fireball", "translation", t, [(0, 0.2, 0), (0, 0.45, 0), (0, 0.7, 0), (0, 1.0, 0), (0, 1.3, 0)]),
        _ch("fireball", "rotation", t, [(0, 0, 0), (0, 20, 0), (0, 50, 0), (0, 80, 0), (0, 100, 0)]),
        _ch("smoke", "scale", t, [(0.2,) * 3, (0.6,) * 3, (1.3,) * 3, (1.7,) * 3, (0.001,) * 3]),
        _ch("smoke", "translation", t, [(0, 0, 0), (0, 0.1, 0), (0, 0.35, 0), (0, 0.7, 0), (0, 1.1, 0)]),
        _ch("shock", "scale", [0, 0.25, 0.4, 0.6], [(0.2, 1, 0.2), (1.8, 1, 1.8), (2.2, 0.3, 2.2), (0.001,) * 3]),
    ]}
    return P, anim

def smoke_cloud():
    P = root()
    rng = np.random.default_rng(11)
    # 반경 1 m 반구 안을 덩어리로 채움 (먹물색, 반투명)
    for k in range(14):
        th = math.radians(k * 137.5); rr = 0.75 * math.sqrt((k + 0.5) / 14)
        y = 0.25 + 0.45 * rng.random()
        s = 0.9 - 0.25 * rr
        P.append(rock([s, s * 0.85, s], (rr * math.cos(th), y, rr * math.sin(th)), INKC if k % 3 else INK2, seed=80 + k, pts=18, j=0.28, n=f"puff_{k}", parent="fx_root", a=0.82))
    P.append(rock([1.0, 0.9, 1.0], (0, 0.75, 0), INK2, seed=99, pts=20, j=0.25, n="puff_top", parent="fx_root", a=0.82))
    return P, None

def ink_wall():
    """1 m 단위. 양 끝(x=±0.5) 단면이 같도록 덩어리를 x 주기로 배치."""
    P = root()
    H, Tk = 3.0, 0.32
    P.append(rbox([1.0, H * 0.92, Tk], (0, H * 0.46, 0), INKC, b=0.02, n="core", parent="fx_root", a=0.9))
    # 흘러내리는 먹물 줄기: x=-0.5, -1/6, 1/6, 0.5 (양 끝은 같은 모양 → 이어 붙이면 이음매가 맞음)
    for i, x in enumerate((-0.5, -1 / 6, 1 / 6, 0.5)):
        for side, sg in (("f", 1), ("b", -1)):
            top = H * (0.95 if (i + (side == "b")) % 2 else 0.8)
            P.append(cap(0.11, top - 0.5, (x, top / 2 + 0.05, sg * Tk * 0.42), INK2, r2=0.07, n=f"drip_{i}_{side}", parent="fx_root", a=0.9, sc=(1.25, 1, 0.5)))
            P.append(sph(0.13, (x + 0.04 * sg, 0.12, sg * Tk * 0.5), INKC, n=f"drip_foot_{i}_{side}", parent="fx_root", a=0.9, sc=(1.5, 0.6, 0.8)))
    # 위쪽 붓끝 모양 + 바닥 번짐
    for i, x in enumerate((-0.25, 0.25)):
        P.append(sph(0.3, (x, H * 0.93, 0), INKC, n=f"brush_top_{i}", parent="fx_root", a=0.9, sc=(0.95, 0.55, 0.6)))
    P.append(rbox([1.0, 0.04, Tk * 2.4], (0, 0.02, 0), INKC, b=0.015, n="spill", parent="fx_root", a=0.85))
    return P, None

def heal_beam():
    P = root()
    P += [cyl(0.018, 0.018, 1.0, (0, 0, 0.5), HEAL_C, seg=10, r=Z, n="core", parent="fx_root", m="glow", a=0.95),
          cyl(0.05, 0.05, 1.0, (0, 0, 0.5), HEAL, seg=14, r=Z, n="glow_tube", parent="fx_root", m="glow", a=0.35)]
    # 실 두 가닥 나선 (실·광선 겸용)
    n = 16
    for strand, ph in ((0, 0), (1, math.pi)):
        for k in range(n):
            z0, z1 = k / n, (k + 1) / n
            a0, a1 = ph + 2 * math.pi * 2 * z0, ph + 2 * math.pi * 2 * z1
            p0 = np.array([0.035 * math.cos(a0), 0.035 * math.sin(a0), z0]); p1 = np.array([0.035 * math.cos(a1), 0.035 * math.sin(a1), z1])
            m = (p0 + p1) / 2; d = p1 - p0; L = np.linalg.norm(d); d /= L
            rx = math.degrees(math.atan2(d[2], d[1])); rz = math.degrees(math.asin(max(-1, min(1, -d[0]))))
            P.append(cyl(0.006, 0.006, L * 1.05, tuple(m), THREAD if strand == 0 else HEAL, seg=5, r=(rx, 0, rz), n=f"thread_{strand}_{k}", parent="fx_root", m="glow"))
    return P, None

def capture_flag():
    P = root()
    H = 3.6
    P += [cyl(0.55, 0.65, 0.18, (0, 0.09, 0), "#4a5058", seg=20, n="base", parent="fx_root", m="metal"),
          cyl(0.42, 0.5, 0.12, (0, 0.24, 0), "#5f656b", seg=20, n="base_step", parent="fx_root", m="metal"),
          dict(cyl(0.57, 0.57, 0.04, (0, 0.2, 0), "#ffffff", seg=24, n="base_ring", parent="fx_root", m="glow"), mn="team_glow"),
          cyl(0.045, 0.055, H, (0, H / 2 + 0.3, 0), "#c9ced6", seg=14, n="pole", parent="fx_root", m="metal"),
          sph(0.09, (0, H + 0.36, 0), "#d9b45a", n="finial", parent="fx_root", m="metal"),
          dict(sph(0.06, (0, H + 0.5, 0), "#ffffff", ws=12, hs=8, n="top_light", parent="fx_root", m="glow"), mn="team_light")]
    # 깃발: 세로 띠 4개를 사슬로 연결 (각 띠가 조금씩 더 흔들려 물결)
    W, Hf, n = 1.3, 0.85, 4
    y0 = H + 0.3 - Hf / 2 - 0.05
    prev = "fx_root"
    x = 0.06
    for i in range(n):
        nm = f"flag_seg_{i}"
        P.append(dict(empty((x, y0, 0) if i == 0 else (W / n, 0, 0), nm, parent=prev), local=True))
        P.append(dict(dict(rbox([W / n + 0.01, Hf, 0.025], (W / n / 2, 0, 0), "#ffffff", b=0.008, n=f"flag_cloth_{i}", parent=nm), mn="team_flag"), local=True))
        prev = nm
    P.append(dict(rbox([0.02, Hf + 0.04, 0.035], (0.06, y0, 0), "#3b4048", b=0.006, n="flag_hoist", parent="fx_root", m="metal"), local=True))
    t = [0, 0.5, 1.0, 1.5, 2.0]
    ch = []
    for i in range(n):
        amp = 8 + i * 5
        ch.append(_ch(f"flag_seg_{i}", "rotation", t, [(0, amp * math.sin(2 * math.pi * k / 4 + i * 0.9), 0) for k in range(5)]))
    return P, {"name": "wave", "channels": ch}


# ------------------------------------------------------------------ 게임 종료
GOLD, GOLD_D, CONF = "#f2c94c", "#c9962a", ["#ff3fa4", "#3fe0ff", "#f2c94c", "#7cf0a0", "#ff8a2a", "#b26bff", "#ffffff"]

def trophy(parent, broken=False):
    loc = lambda q: dict(q, local=True)
    c, cd = ("#8e959e", "#5f656b") if broken else (GOLD, GOLD_D)
    P = [loc(cyl(0.22, 0.26, 0.08, (0, 0.04, 0), "#2b2f35", seg=16, n="trophy_base", parent=parent)),
         loc(cyl(0.16, 0.2, 0.1, (0, 0.13, 0), cd, seg=16, n="trophy_plinth", parent=parent, m="metal")),
         loc(cyl(0.035, 0.06, 0.22, (0, 0.29, 0), c, seg=12, n="trophy_stem", parent=parent, m="metal")),
         loc(lathe([(0, 0), (0.06, 0), (0.14, 0.05), (0.2, 0.16), (0.23, 0.34), (0.21, 0.36), (0.0, 0.2)], (0, 0.4, 0), c, seg=24, n="trophy_cup", parent=parent, m="metal"))]
    for sd in (-1, 1):
        P += [loc(q) for q in ring(0.09, 0.025, (sd * 0.24, 0.62, 0), c, seg=8, plane="xy", a0=-90 if sd > 0 else 90, a1=90 if sd > 0 else 270, n=f"trophy_handle_{'L' if sd > 0 else 'R'}", parent=parent, m="metal")]
    if not broken:   # 컵 위 종이 별 (오리가미 느낌)
        for k in range(5):
            a = math.radians(90 + k * 72)
            P.append(loc(cyl(0, 0.05, 0.13, (0.07 * math.cos(a), 0.92 + 0.07 * math.sin(a), 0), "#fff6d6", seg=4, r=(0, 0, k * 72), n=f"star_{k}", parent=parent, m="glow")))
        P.append(loc(dict(rbox([0.5, 0.09, 0.02], (0, 0.13, 0.205), "#ffffff", b=0.01, n="trophy_plate", parent=parent), mn="team_flag")))
    else:            # 깨진 조각
        for k in range(3):
            P.append(loc(rock([0.08, 0.05, 0.07], (0.25 + 0.08 * k, 0.03, 0.1 - 0.1 * k), c, seed=300 + k, pts=10, n=f"shard_{k}", parent="fx_root", m="metal")))
    return P

def victory():
    """승리: 트로피가 솟아오르며 회전, 섬광 링, 색종이 폭죽. 클립 victory 3초 (끝 자세 유지)."""
    P = root() + [empty((0, 0, 0), "trophy", parent="fx_root"), empty((0, 0.6, 0), "burst", parent="fx_root")]
    P += trophy("trophy")
    loc = lambda q: dict(q, local=True)
    P += [loc(q) for q in ring(0.6, 0.04, (0, 0, 0), "#fff6d6", seg=20, plane="xy", n="burst_ring", parent="burst", m="glow", a=0.8)]
    for k in range(8):   # 빛살
        a = k * 45
        P.append(loc(cyl(0, 0.05, 0.5, (0.75 * math.cos(math.radians(a)), 0.75 * math.sin(math.radians(a)), -0.05), GOLD, seg=4, r=(0, 0, a - 90), n=f"ray_{k}", parent="burst", m="glow", a=0.75, sc=(1, 1, 0.3))))
    rng = np.random.default_rng(21)
    ch = [_ch("trophy", "translation", [0, 0.35, 0.55, 0.7, 3.0], [(0, -0.6, 0), (0, 0.12, 0), (0, -0.03, 0), (0, 0, 0), (0, 0, 0)]),
          _ch("trophy", "scale", [0, 0.35, 0.55, 0.7], [(0.3,) * 3, (1.15,) * 3, (0.95,) * 3, (1,) * 3]),
          _ch("trophy", "rotation", [0, 0.7, 1.5, 2.25, 3.0], [(0, -180, 0), (0, 0, 0), (0, 15, 0), (0, -15, 0), (0, 0, 0)]),
          _ch("burst", "scale", [0, 0.3, 0.5, 1.2, 3.0], [(0.001,) * 3, (0.001,) * 3, (1.3,) * 3, (1.6,) * 3, (1.6,) * 3]),
          _ch("burst", "rotation", [0, 1.5, 3.0], [(0, 0, 0), (0, 0, 45), (0, 0, 90)])]
    T = [0, 0.3, 0.45, 1.0, 1.8, 2.6, 3.0]
    for k in range(36):
        nm = f"confetti_{k}"
        P.append(empty((0, 0.6, 0), nm, parent="fx_root"))
        P.append(loc(rbox([0.09, 0.05, 0.006], (0, 0, 0), CONF[k % len(CONF)], b=0.002, n=f"{nm}_paper", parent=nm, m="glow" if k % 3 == 0 else None)))
        th = rng.uniform(0, 2 * math.pi); sp = rng.uniform(1.8, 3.4); up = rng.uniform(2.0, 3.6)
        vx, vz = sp * math.cos(th), sp * math.sin(th) * 0.6
        pos = []
        for t in T:
            tt = max(0, t - 0.3)
            drag = (1 - math.exp(-2.2 * tt)) / 2.2
            pos.append((vx * drag, up * drag - 0.45 * tt * tt + (0 if t >= 0.3 else 0), vz * drag))
        sc = [(0.001,) * 3, (0.001,) * 3, (1, 1, 1), (1, 1, 1), (1, 1, 1), (1, 1, 1), (0.001,) * 3]
        rot = [(0, 0, 0)] + [(rng.uniform(0, 720), rng.uniform(0, 720), rng.uniform(0, 720)) for _ in T[1:]]
        ch += [_ch(nm, "translation", T, pos), _ch(nm, "scale", T, sc), _ch(nm, "rotation", T, rot)]
    return P, {"name": "victory", "channels": ch}

def defeat():
    """패배: 회색 트로피가 기울어 쓰러지고 먹구름에서 재가 떨어짐. 클립 defeat 3초 (끝 자세 유지)."""
    P = root() + [empty((0, 0, 0), "trophy", parent="fx_root"), empty((0, 1.6, 0), "cloud", parent="fx_root")]
    P += trophy("trophy", broken=True)
    loc = lambda q: dict(q, local=True)
    for k in range(6):
        P.append(loc(rock([0.5, 0.32, 0.4], (-0.45 + k * 0.18, 0.05 * (k % 2), 0.05 * ((k + 1) % 2)), "#4a4f5a" if k % 2 else "#3b3f48", seed=200 + k, pts=14, j=0.3, n=f"cloud_puff_{k}", parent="cloud", a=0.9)))
    rng = np.random.default_rng(5)
    ch = [_ch("trophy", "rotation", [0, 0.4, 0.9, 1.1, 1.25, 3.0], [(0, 0, 0), (0, 0, 0), (0, 0, -40), (0, 0, -95), (0, 0, -88), (0, 0, -90)]),
          _ch("trophy", "translation", [0, 0.9, 1.1, 1.25, 3.0], [(0, 0, 0), (0.05, 0, 0), (0.12, 0.2, 0), (0.12, 0.2, 0), (0.12, 0.2, 0)]),
          _ch("cloud", "scale", [0, 0.6, 1.0, 3.0], [(0.001,) * 3, (0.001,) * 3, (1, 1, 1), (1.1, 1.05, 1.1)]),
          _ch("cloud", "translation", [0, 1.0, 2.0, 3.0], [(0, 0.3, 0), (0, 0, 0), (0.05, -0.03, 0), (0, 0, 0)])]
    for k in range(18):   # 떨어지는 재 / 빗줄기
        nm = f"ash_{k}"
        x, z = rng.uniform(-0.55, 0.55), rng.uniform(-0.2, 0.2)
        P.append(empty((x, 1.45, z), nm, parent="fx_root"))
        P.append(loc(cap(0.008, 0.05, (0, 0, 0), "#9aa3b0", n=f"{nm}_drop", parent=nm, a=0.8)))
        t0 = 1.0 + rng.uniform(0, 0.6)
        T = [0, t0, t0 + 0.7, t0 + 0.71, 3.0]
        ch += [_ch(nm, "translation", T, [(0, 0, 0), (0, 0, 0), (0, -1.4, 0), (0, 0, 0), (0, -1.4 * (3.0 - t0 - 0.71) / 0.7 % 1.4, 0)]),
               _ch(nm, "scale", T, [(0.001,) * 3, (1, 1, 1), (1, 1, 1), (1, 1, 1), (1, 1, 1)])]
    return P, {"name": "defeat", "channels": ch}

FX_NEW = [("muzzle_flash", muzzle_flash), ("impact", impact), ("explosion", explosion), ("smoke_cloud", smoke_cloud),
          ("ink_wall", ink_wall), ("heal_beam", heal_beam), ("capture_flag", capture_flag),
          ("match_victory", victory), ("match_defeat", defeat)]
