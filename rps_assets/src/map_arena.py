"""대전 맵: RPS 아레나 (64m × 48m, 3라인).
A팀(주황) 스폰 z=+21, B팀(파랑) 스폰 z=-21. 바닥 y=0, 단위 m.
노드 그룹: perimeter, spawn_A, spawn_B, plaza, lane_left(창고), lane_right(고가 다리), lane_mid, cover
"""
import math
from parts import *

CONC, CONC_D, FLOOR, FLOOR2 = "#a3a8ad", "#7b8187", "#5f656b", "#6c737a"
TA, TB, METAL_D = "#ff8a2a", "#4d8cf0", "#4a5058"
ROOF = "#565c63"

def wall(x0, z0, x1, z1, h, g, c=CONC, t=0.5, y0=0.0, n="wall"):
    cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
    L = math.hypot(x1 - x0, z1 - z0)
    ang = math.degrees(math.atan2(x1 - x0, z1 - z0))
    return rbox([t, h, L + t], (cx, y0 + h / 2, cz), c, b=0.06, r=(0, ang, 0), n=n, parent=g)

def crate(x, z, g, s=1.2, c="#8a6a45", k=0, y=0.0, rot=0):
    return [rbox([s, s, s], (x, y + s / 2, z), c, b=0.06, r=(0, rot, 0), n=f"crate_{k}", parent=g),
            rbox([s + 0.02, 0.12, s + 0.02], (x, y + s * 0.82, z), "#5b452d", b=0.03, r=(0, rot, 0), n=f"crate_{k}_band", parent=g),
            rbox([s + 0.02, 0.12, s + 0.02], (x, y + s * 0.18, z), "#5b452d", b=0.03, r=(0, rot, 0), n=f"crate_{k}_band2", parent=g)]

def barrier(x, z, g, rot=0, k=0, c=CONC):
    return [ext([(-1.0, 0), (1.0, 0), (0.75, 0.25), (0.18, 0.4), (0.18, 1.05), (-0.18, 1.05), (-0.18, 0.4), (-0.75, 0.25)], 2.2, (x, 0, z), c, ch=0.05, r=(0, rot + 90, 0), n=f"barrier_{k}", parent=g)]

def barrel(x, z, g, k=0, c="#b84a2a"):
    return [cyl(0.32, 0.32, 0.95, (x, 0.475, z), c, seg=20, n=f"barrel_{k}", parent=g),
            cyl(0.335, 0.335, 0.05, (x, 0.3, z), METAL_D, seg=20, n=f"barrel_{k}_ring1", parent=g, m="metal"),
            cyl(0.335, 0.335, 0.05, (x, 0.68, z), METAL_D, seg=20, n=f"barrel_{k}_ring2", parent=g, m="metal")]

def sandbags(x, z, g, rot=0, k=0, n=4):
    out = []
    ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
    for row in range(2):
        for i in range(n - row):
            off = (i - (n - row - 1) / 2) * 0.62
            out.append(cap(0.17, 0.32, (x + off * ca, 0.17 + row * 0.3, z - off * sa), "#b5a27a", r=(0, rot, 90), n=f"sandbag_{k}_{row}_{i}", parent=g))
    return out

def column(x, z, h, g, k=0, c=CONC):
    return [lathe([(0, 0), (0.55, 0), (0.55, 0.25), (0.42, 0.35), (0.38, h - 0.35), (0.48, h - 0.25), (0.55, h - 0.2), (0.55, h), (0, h)], (x, 0, z), c, seg=16, n=f"column_{k}", parent=g)]

def build():
    P = [empty((0, 0, 0), g) for g in ("perimeter", "spawn_A", "spawn_B", "plaza", "lane_left", "lane_right", "lane_mid", "cover")]
    W, D = 64, 48
    g = "perimeter"
    P += [rbox([W + 2, 0.4, D + 2], (0, -0.2, 0), FLOOR, b=0.1, n="ground", parent=g, m="rubber")]
    for i, x in enumerate((-12, 0, 12)):
        P.append(rbox([3.0, 0.02, 30], (x * 0 + (-22, 0, 22)[i], 0.011, 0), FLOOR2, b=0.005, n=f"lane_strip_{i}", parent=g))
    P += [wall(-W / 2, -D / 2, W / 2, -D / 2, 6, g, n="wall_north"), wall(-W / 2, D / 2, W / 2, D / 2, 6, g, n="wall_south"),
          wall(-W / 2, -D / 2, -W / 2, D / 2, 6, g, n="wall_west"), wall(W / 2, -D / 2, W / 2, D / 2, 6, g, n="wall_east")]
    for i in range(9):
        x = -W / 2 + 4 + i * 7
        for zz, nm in ((-D / 2 + 0.4, "n"), (D / 2 - 0.4, "s")):
            P.append(rbox([0.9, 6.4, 0.9], (x, 3.2, zz), CONC_D, b=0.08, n=f"buttress_{nm}_{i}", parent=g))
    # --- 스폰 (양 팀)
    for team, sz, col in (("A", 1, TA), ("B", -1, TB)):
        g = f"spawn_{team}"
        z0 = sz * (D / 2)          # 바깥벽
        z1 = sz * (D / 2 - 7)      # 스폰 앞벽
        P += [rbox([18, 0.3, 7], (0, 0.15, sz * (D / 2 - 3.5)), FLOOR2, b=0.05, n=f"spawn_{team}_floor", parent=g),
              rbox([18.4, 0.4, 7.4], (0, 4.7, sz * (D / 2 - 3.5)), ROOF, b=0.08, n=f"spawn_{team}_roof", parent=g),
              wall(-9, z0, -9, z1, 4.5, g, n=f"spawn_{team}_side_L"), wall(9, z0, 9, z1, 4.5, g, n=f"spawn_{team}_side_R"),
              wall(-9, z1, -2.5, z1, 4.5, g, n=f"spawn_{team}_front_L"), wall(2.5, z1, 9, z1, 4.5, g, n=f"spawn_{team}_front_R"),
              rbox([5.4, 1.4, 0.5], (0, 3.8, z1), CONC, b=0.06, n=f"spawn_{team}_lintel", parent=g),
              rbox([5.0, 0.18, 0.08], (0, 3.05, z1 - sz * 0.27), col, b=0.03, n=f"spawn_{team}_door_light", parent=g, m="glow")]
        for i, x in enumerate((-5, 0, 5)):
            P += [cyl(1.1, 1.15, 0.12, (x, 0.36, sz * (D / 2 - 3.2)), col, seg=24, n=f"spawn_{team}_pad_{i}", parent=g, m="glow", a=0.85),
                  cyl(1.25, 1.25, 0.1, (x, 0.32, sz * (D / 2 - 3.2)), METAL_D, seg=24, n=f"spawn_{team}_pad_rim_{i}", parent=g, m="metal")]
        P += [rbox([2.6, 2.6, 0.12], (0, 2.7, z0 - sz * 0.32), col, b=0.05, n=f"spawn_{team}_banner", parent=g)]
        # 스폰 앞 엄폐
        P += barrier(-5, sz * (D / 2 - 10), g, k=f"{team}1") + barrier(5, sz * (D / 2 - 10), g, k=f"{team}2")
        for x in (-12, 12):
            P += crate(x, sz * (D / 2 - 4), g, k=f"{team}{x}") + crate(x + (0.6 if x > 0 else -0.6), sz * (D / 2 - 4), g, s=0.8, y=1.2, k=f"{team}{x}t", rot=20)
    # --- 중앙 광장 + RPS 기념비
    g = "plaza"
    P += [cyl(9.0, 9.4, 0.3, (0, 0.15, 0), CONC, seg=40, n="plaza_platform", parent=g),
          cyl(8.2, 8.2, 0.02, (0, 0.31, 0), FLOOR2, seg=40, n="plaza_inlay", parent=g)]
    P += ring(8.6, 0.12, (0, 0.32, 0), "#d9b45a", seg=40, n="plaza_ring", parent=g, m="metal")
    for i in range(3):
        a = math.radians(90 + i * 120)
        P.append(rbox([0.3, 0.02, 7.6], (4.2 * math.cos(a), 0.322, 4.2 * math.sin(a)), "#d9b45a", b=0.01, r=(0, -math.degrees(a) + 90, 0), n=f"plaza_spoke_{i}", parent=g, m="metal"))
    # 바위 기념비
    P += [rock([3.4, 3.0, 3.2], (-4.8, 1.8, -2.6), STONE, seed=5, pts=26, n="monument_rock", parent=g),
          rock([1.4, 1.1, 1.3], (-3.4, 0.8, -1.4), STONE_D, seed=9, n="monument_rock_small", parent=g)]
    # 보 기념비: 두루마리 아치
    P += [cyl(0.45, 0.45, 4.2, (4.8, 3.8, -2.6), "#7a4e2c", r=(0, 30, 90), n="monument_scroll_top", parent=g),
          rbox([3.6, 3.4, 0.08], (4.8, 2.05, -2.6), PAPER, b=0.02, r=(0, 30, 0), n="monument_paper", parent=g),
          cyl(0.5, 0.5, 4.2, (4.8, 0.5, -2.6), "#7a4e2c", r=(0, 30, 90), n="monument_scroll_bottom", parent=g),
          rbox([0.35, 2.4, 0.09], (4.3, 2.2, -2.32), INK, b=0.02, r=(0, 30, 0), n="monument_ink", parent=g)]
    # 가위 기념비
    P += [rbox([0.5, 5.2, 0.12], (-0.45, 2.9, 5.2), STEEL, b=0.04, r=(0, 0, -16), n="monument_blade_L", parent=g, m="metal"),
          rbox([0.5, 5.2, 0.12], (0.45, 2.9, 5.0), STEEL, b=0.04, r=(0, 0, 16), n="monument_blade_R", parent=g, m="metal"),
          cyl(0.32, 0.32, 0.5, (0, 1.6, 5.1), RED_D, r=Z, n="monument_pivot", parent=g)]
    P += ring(0.6, 0.18, (-0.9, 0.7, 5.1), RED, seg=14, plane="xy", n="monument_handle_L", parent=g)
    P += ring(0.6, 0.18, (0.9, 0.7, 5.1), RED, seg=14, plane="xy", n="monument_handle_R", parent=g)
    for i, (x, z) in enumerate(((6.5, 4.5), (-6.5, 4.5), (0, -6.8))):
        P += column(x, z, 4.2, g, k=i)
    # --- 왼쪽 라인: 창고 건물
    g = "lane_left"
    x0, x1, zA, zB, H = -30, -15, -9, 9, 4.6
    P += [rbox([15, 0.3, 18], (-22.5, 0.15, 0), "#6a6258", b=0.05, n="warehouse_floor", parent=g),
          rbox([15.6, 0.35, 18.6], (-22.5, H + 0.17, 0), ROOF, b=0.08, n="warehouse_roof", parent=g)]
    P += [wall(x1, zA, x1, -3, H, g, n="wh_east_1"), wall(x1, 3, x1, zB, H, g, n="wh_east_2"),
          rbox([0.5, 1.4, 6], (x1, H - 0.7, 0), CONC, b=0.06, n="wh_east_lintel", parent=g),
          wall(x0 + 2, zA, -25, zA, H, g, n="wh_north_1"), wall(-20, zA, x1, zA, H, g, n="wh_north_2"),
          wall(x0 + 2, zB, -25, zB, H, g, n="wh_south_1"), wall(-20, zB, x1, zB, H, g, n="wh_south_2"),
          rbox([5.5, 1.6, 0.5], (-22.5, H - 0.8, zA), CONC, b=0.06, n="wh_north_lintel", parent=g),
          rbox([5.5, 1.6, 0.5], (-22.5, H - 0.8, zB), CONC, b=0.06, n="wh_south_lintel", parent=g)]
    for i, z in enumerate((-6, 6)):
        P.append(rbox([0.55, 1.0, 2.4], (x1, 2.1, z), "#9fd8ff", b=0.03, n=f"wh_window_{i}", parent=g, m="glass", a=0.35))
    P += crate(-25, -4, g, k="w1") + crate(-24, -4.3, g, s=0.9, y=1.2, k="w2", rot=15) + crate(-19, 3, g, k="w3") + crate(-26, 5, g, s=1.5, k="w4")
    # 드럼통 w1·w2: 계단 입구를 막지 않도록 동쪽 벽 쪽으로 이동
    P += barrel(-17.2, -5.2, g, k="w1") + barrel(-16.6, -5.8, g, k="w2") + barrel(-27, 0, g, k="w3", c="#3f6b4a")
    P += [rbox([6, 0.2, 2.5], (-27, 2.4, -1), METAL_D, b=0.04, n="wh_mezzanine", parent=g, m="metal")]
    for i, (x, z) in enumerate(((-29.6, -2.1), (-24.4, -2.1), (-29.6, 0.1), (-24.4, 0.1))):
        P.append(cyl(0.08, 0.08, 2.4, (x, 1.2, z), METAL_D, seg=10, n=f"wh_mezz_post_{i}", parent=g, m="metal"))
    # 계단: 동쪽(x=-21.4)에서 서쪽으로 올라가 메자닌 끝(x=-24, 윗면 y=2.5)에 닿음.
    # 바닥 윗면 0.3 + 단 높이 0.275 × 8 = 2.5 (마지막 단 다음 높이 = 메자닌 윗면)
    for i in range(7):
        top = 0.3 + 0.275 * (i + 1)
        P.append(rbox([0.4, 0.15, 2.5], (-21.4 - i * 0.4, top - 0.075, -1), METAL_D, b=0.02, n=f"wh_stair_{i}", parent=g, m="metal"))
    for s_ in (-1, 1):   # 계단 옆판(스트링거)
        P.append(rbox([3.56, 0.18, 0.06], (-22.6, 1.27, -1 + s_ * 1.28), METAL_D, b=0.01, r=(0, 0, -38.2), n=f"wh_stair_rail_{'N' if s_ < 0 else 'S'}", parent=g, m="metal"))
    for i in range(4):
        P.append(rbox([0.12, 0.12, 18], (-28 + i * 4, H - 0.15, 0), "#3a3f45", b=0.02, n=f"wh_beam_{i}", parent=g, m="metal"))
        P.append(rbox([1.2, 0.06, 0.3], (-28 + i * 4, H - 0.3, 0), GLOW_W, b=0.02, n=f"wh_light_{i}", parent=g, m="glow"))
    # --- 오른쪽 라인: 고가 다리
    g = "lane_right"
    bx, bw, by = 22.5, 6.0, 3.0
    P += [rbox([bw, 0.4, 22], (bx, by, 0), CONC, b=0.08, n="bridge_deck", parent=g)]
    for s in (-1, 1):
        P += [rbox([bw, 0.4, 7.6], (bx, by / 2, s * 14.4), CONC, b=0.08, r=(s * 23.3, 0, 0), n=f"bridge_ramp_{'N' if s < 0 else 'S'}", parent=g),
              rbox([0.12, 1.0, 22], (bx + s * (bw / 2 - 0.1), by + 0.7, 0), METAL_D, b=0.03, n=f"bridge_rail_{'E' if s > 0 else 'W'}", parent=g, m="metal")]
    for i in range(5):
        z = -9 + i * 4.5
        for s in (-1, 1):
            P.append(lathe([(0, 0), (0.45, 0), (0.42, 0.2), (0.32, 0.3), (0.32, by - 0.2), (0.45, by - 0.05), (0, by - 0.05)], (bx + s * 2.2, 0, z), CONC_D, seg=14, n=f"bridge_pillar_{i}_{s}", parent=g))
        P.append(rbox([0.4, 0.04, 0.4], (bx, by + 0.215, z), TA if i < 2 else (TB if i > 2 else GLOW_W), b=0.01, n=f"bridge_light_{i}", parent=g, m="glow"))
    P += sandbags(bx, -3.5, g, k="b1") + sandbags(bx, 3.5, g, k="b2")
    for k_, z in enumerate((-6, 6)):
        P += [rbox([2.4, 1.1, 0.3], (bx - 0.6, by + 0.75, z), CONC, b=0.05, n=f"bridge_cover_{k_}", parent=g)]
    P += crate(20, 0, g, k="r1") + crate(25, -1.5, g, k="r2", s=1.5) + barrel(19.5, -4, g, k="r1")
    # --- 중앙 라인 엄폐 + 연결 통로
    g = "lane_mid"
    for s, team in ((1, "A"), (-1, "B")):
        P += [wall(-12, s * 13, -6, s * 13, 2.2, g, n=f"mid_wall_{team}_L"), wall(6, s * 13, 12, s * 13, 2.2, g, n=f"mid_wall_{team}_R"),
              wall(-15, s * 9.5, -12, s * 9.5, 3.5, g, n=f"conn_wall_{team}_W"), wall(12, s * 9.5, 15, s * 9.5, 3.5, g, n=f"conn_wall_{team}_E")]
        P += barrier(0, s * 13.5, g, rot=90, k=f"m{team}")
        P += sandbags(-9, s * 11.5, g, k=f"m{team}1", rot=0) + sandbags(9, s * 11.5, g, k=f"m{team}2", rot=0)
    g = "cover"
    pts = [(-12, 4), (12, -4), (-10, -6), (10, 6), (-16, 0), (16, 0)]
    for i, (x, z) in enumerate(pts):
        P += crate(x, z, g, k=f"c{i}", rot=i * 17)
    for i, (x, z) in enumerate(((-13, -14), (13, 14), (-17, 15), (17, -15))):
        P += barrel(x, z, g, k=f"c{i}", c="#3f6b4a" if i % 2 else "#b84a2a")
    return P
