"""추가 맵 4종. 모두 A팀(주황) z+, B팀(파랑) z- 대칭 구조. 단위 m, 바닥 y=0."""
import math
from parts import *
from map_arena import wall, crate, barrier, barrel, sandbags, column, TA, TB, METAL_D

def spawn(team, z_edge, w, depth, floor_c, wall_c, roof_c, g=None):
    """양 팀 공통 스폰 건물. z_edge: 바깥 벽 z (부호 = 팀 방향)."""
    s = 1 if z_edge > 0 else -1
    col = TA if team == "A" else TB
    g = g or f"spawn_{team}"
    z1 = z_edge - s * depth
    P = [rbox([w, 0.3, depth], (0, 0.15, z_edge - s * depth / 2), floor_c, b=0.05, n=f"spawn_{team}_floor", parent=g),
         rbox([w + 0.4, 0.4, depth + 0.4], (0, 4.7, z_edge - s * depth / 2), roof_c, b=0.08, n=f"spawn_{team}_roof", parent=g),
         wall(-w / 2, z_edge, -w / 2, z1, 4.5, g, c=wall_c, n=f"spawn_{team}_side_L"), wall(w / 2, z_edge, w / 2, z1, 4.5, g, c=wall_c, n=f"spawn_{team}_side_R"),
         wall(-w / 2, z1, -2.5, z1, 4.5, g, c=wall_c, n=f"spawn_{team}_front_L"), wall(2.5, z1, w / 2, z1, 4.5, g, c=wall_c, n=f"spawn_{team}_front_R"),
         rbox([5.4, 1.4, 0.5], (0, 3.8, z1), wall_c, b=0.06, n=f"spawn_{team}_lintel", parent=g),
         rbox([5.0, 0.18, 0.08], (0, 3.05, z1 - s * 0.27), col, b=0.03, n=f"spawn_{team}_door_light", parent=g, m="glow")]
    for i, x in enumerate((-w / 4, 0, w / 4)):
        P += [cyl(1.0, 1.05, 0.12, (x, 0.36, z_edge - s * depth / 2), col, seg=24, n=f"spawn_{team}_pad_{i}", parent=g, m="glow", a=0.85),
              cyl(1.15, 1.15, 0.1, (x, 0.32, z_edge - s * depth / 2), METAL_D, seg=24, n=f"spawn_{team}_pad_rim_{i}", parent=g, m="metal")]
    return P

def groups(*names):
    return [empty((0, 0, 0), g) for g in names]

def mirror(fn, *a):
    """z 대칭으로 양쪽에 같은 구조 배치. fn(sign) → parts."""
    return fn(1, *a) + fn(-1, *a)

# =====================================================================
# 1. 사막 유적
# =====================================================================
SAND, SAND_D, SANDSTONE, SANDSTONE_D, TERRA = "#d9b98a", "#c49c68", "#c9a26b", "#a37c4a", "#b9653a"

def desert():
    P = groups("terrain", "spawn_A", "spawn_B", "ziggurat", "ruins", "cover")
    W, D = 60, 50
    g = "terrain"
    P += [rbox([W + 2, 0.4, D + 2], (0, -0.2, 0), SAND, b=0.1, n="ground", parent=g, m="rubber")]
    for i, (x, z, sx, sz) in enumerate(((-24, 0, 10, 26), (24, 0, 10, 26), (-10, 18, 8, 5), (10, -18, 8, 5), (16, 14, 6, 4), (-16, -14, 6, 4))):
        P.append(sph(1.0, (x, -0.2, z), SAND_D, n=f"dune_{i}", parent=g, sc=(sx / 2, 1.6, sz / 2)))
    P += [wall(-W / 2, -D / 2, W / 2, -D / 2, 7, g, c=SANDSTONE_D, t=1.2, n="cliff_north"), wall(-W / 2, D / 2, W / 2, D / 2, 7, g, c=SANDSTONE_D, t=1.2, n="cliff_south"),
          wall(-W / 2, -D / 2, -W / 2, D / 2, 7, g, c=SANDSTONE_D, t=1.2, n="cliff_west"), wall(W / 2, -D / 2, W / 2, D / 2, 7, g, c=SANDSTONE_D, t=1.2, n="cliff_east")]
    for i in range(14):
        a = i / 14
        x = -W / 2 + 2 + a * (W - 4)
        P.append(rock([3.5, 5 + 2 * math.sin(i * 1.7), 3], (x, 2.2, D / 2 - 1.2 if i % 2 else -D / 2 + 1.2), SANDSTONE_D, seed=40 + i, n=f"cliff_rock_{i}", parent=g))
    P += spawn("A", D / 2, 16, 6, SANDSTONE, SANDSTONE, TERRA) + spawn("B", -D / 2, 16, 6, SANDSTONE, SANDSTONE, TERRA)
    # 중앙 지구라트
    g = "ziggurat"
    for k, (w, h) in enumerate(((16, 1.2), (12, 1.2), (8, 1.2), (4.5, 1.6))):
        y = sum(hh for _, hh in ((16, 1.2), (12, 1.2), (8, 1.2), (4.5, 1.6))[:k])
        P.append(rbox([w, h, w], (0, y + h / 2, 0), SANDSTONE if k % 2 == 0 else SANDSTONE_D, b=0.12, n=f"zig_tier_{k}", parent=g))
    for s in (1, -1):
        for i in range(6):
            P.append(rbox([3.0, 0.4, 0.6], (0, 0.2 + i * 0.6, s * (8.3 - i * 0.65)), SANDSTONE_D, b=0.05, n=f"zig_stair_{'S' if s > 0 else 'N'}_{i}", parent=g))
    P += [cyl(0.0, 1.2, 1.4, (0, 5.3, 0), TERRA, seg=4, r=(0, 45, 0), n="zig_capstone", parent=g),
          sph(0.5, (0, 6.3, 0), "#ffd27a", n="zig_relic", parent=g, m="glow")]
    for i, (x, z) in enumerate(((7.5, 7.5), (-7.5, 7.5), (7.5, -7.5), (-7.5, -7.5))):
        P.append(cyl(0.0, 0.6, 1.4, (x, 0.7, z), TERRA, seg=4, r=(0, 45, 0), n=f"zig_obelisk_{i}", parent=g))
    # 유적: 부서진 기둥 + 아치
    g = "ruins"
    def ruins_side(s):
        out = []
        for i, (x, z, h) in enumerate(((-14, 6, 4.5), (-12, 10, 2.2), (-17, 12, 3.6), (14, 6, 4.5), (12, 10, 1.6), (17, 12, 3.8))):
            out += [lathe([(0, 0), (0.7, 0), (0.7, 0.3), (0.5, 0.45), (0.45, h), (0, h)], (x, 0, s * z), SANDSTONE, seg=12, n=f"ruin_col_{s}_{i}", parent=g)]
            if h > 4: out.append(rbox([1.6, 0.5, 1.6], (x, h + 0.25, s * z), SANDSTONE_D, b=0.08, n=f"ruin_cap_{s}_{i}", parent=g))
        for side in (-1, 1):
            ax = side * 20
            out += [rbox([1.2, 4, 1.2], (ax - 2.2, 2, s * 3), SANDSTONE, b=0.08, n=f"arch_post_{s}_{side}_a", parent=g),
                    rbox([1.2, 4, 1.2], (ax + 2.2, 2, s * 3), SANDSTONE, b=0.08, n=f"arch_post_{s}_{side}_b", parent=g)]
            out += [lathe([(2.2, 0), (2.8, 0), (2.8, 1.2), (2.2, 1.2)], (ax, 4, s * 3), SANDSTONE_D, seg=10, n=f"arch_top_{s}_{side}", parent=g, r=(90, 0, 0), sc=(1, 1, 1))]
        out.append(rock([2.2, 1.0, 1.4], (-9, 0.4, s * 13), SANDSTONE_D, seed=60 + s, n=f"fallen_block_{s}", parent=g))
        out.append(cap(0.45, 3.4, (9, 0.45, s * 13), SANDSTONE, r=(0, 30 * s, 90), n=f"fallen_column_{s}", parent=g))
        return out
    P += mirror(ruins_side)
    g = "cover"
    for i, (x, z) in enumerate(((-6, 12), (6, -12), (-20, -8), (20, 8), (-4, -14), (4, 14))):
        P += crate(x, z, g, k=f"d{i}", c="#9a7a50", rot=i * 23)
    for i, (x, z) in enumerate(((-12, 0), (12, 0))):
        P += sandbags(x, z, g, k=f"d{i}", rot=90, n=5)
    for i in range(6):
        a = i * 60
        P.append(cyl(0.35, 0.45, 0.9, (22 * math.cos(math.radians(a)) * 0.6, 0.45, 18 * math.sin(math.radians(a)) * 0.6), TERRA, seg=14, n=f"clay_pot_{i}", parent=g))
    return P

# =====================================================================
# 2. 설원 항구
# =====================================================================
SNOW, SNOW_D, ICE, DOCK, WATER = "#eef3f7", "#cdd6de", "#a8d8ef", "#5b4a3a", "#2a4a66"
CONT = ["#c0392b", "#2e86c1", "#d4ac0d", "#27ae60", "#7d3c98", "#e67e22"]

def container(x, y, z, g, c, k, rot=0):
    out = [rbox([2.4, 2.6, 6.0], (x, y + 1.3, z), c, b=0.05, r=(0, rot, 0), n=f"container_{k}", parent=g, m="metal")]
    for i in range(5):
        zz = -2.4 + i * 1.2
        ca, sa = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        out.append(rbox([2.44, 2.4, 0.08], (x + zz * sa, y + 1.3, z + zz * ca), "#00000033"[:7] if False else SNOW_D if i == 4 else c, b=0.02, r=(0, rot, 0), n=f"container_{k}_rib_{i}", parent=g, m="metal"))
    out.append(rbox([2.42, 0.12, 6.02], (x, y + 2.62, z), SNOW, b=0.03, r=(0, rot, 0), n=f"container_{k}_snow", parent=g))
    return out

def harbor():
    P = groups("terrain", "spawn_A", "spawn_B", "dock", "containers", "crane", "cover")
    W, D = 64, 50
    g = "terrain"
    # 땅은 바다 경계(x = W/2-13 = 19)까지만. 그 바깥은 바다(물 + 해저)
    sea_x = W / 2 - 13
    P += [rbox([sea_x + W / 2 + 1, 0.4, D + 2], ((sea_x - W / 2 - 1) / 2, -0.2, 0), SNOW, b=0.1, n="ground", parent=g, m="rubber"),
          rbox([0.4, 1.3, D + 2], (sea_x - 0.2, -0.65, 0), "#5f6b78", b=0.05, n="quay_wall", parent=g),
          rbox([14, 0.1, D + 2], (W / 2 - 6, -0.6, 0), WATER, b=0.02, n="sea", parent=g, a=0.9),
          rbox([12, 1.2, D + 2], (W / 2 - 6, -1.3, 0), "#1c3348", b=0.02, n="sea_floor", parent=g)]
    for i in range(7):
        P.append(cyl(1.2 + 0.4 * (i % 3), 1.3 + 0.4 * (i % 3), 0.18, (W / 2 - 8 + (i % 2) * 4, -0.45, -18 + i * 6), ICE, seg=7, n=f"ice_floe_{i}", parent=g, a=0.9))
    P += [wall(-W / 2, -D / 2, W / 2 - 13, -D / 2, 5, g, c=SNOW_D, n="fence_north"), wall(-W / 2, D / 2, W / 2 - 13, D / 2, 5, g, c=SNOW_D, n="fence_south"),
          wall(-W / 2, -D / 2, -W / 2, D / 2, 5, g, c=SNOW_D, n="fence_west")]
    for i in range(10):
        P.append(sph(1.0, (-W / 2 + 2 + i * 5.5, 0, (D / 2 - 1) * (1 if i % 2 else -1)), SNOW, n=f"snow_drift_{i}", parent=g, sc=(2.2, 0.7, 1.2)))
    P += spawn("A", D / 2, 16, 6, SNOW_D, "#7b8794", "#4a5561") + spawn("B", -D / 2, 16, 6, SNOW_D, "#7b8794", "#4a5561")
    # 부두
    g = "dock"
    P += [rbox([6, 0.5, 40], (W / 2 - 13, 0.25, 0), DOCK, b=0.05, n="pier_deck", parent=g)]
    for i in range(8):
        P.append(cyl(0.25, 0.25, 2.4, (W / 2 - 10.2, -0.9, -17.5 + i * 5), "#3e3228", seg=10, n=f"pier_pile_{i}", parent=g))
        P.append(cyl(0.22, 0.25, 0.5, (W / 2 - 10.6, 0.75, -17.5 + i * 5), "#2b2f35", seg=12, n=f"bollard_{i}", parent=g, m="metal"))
    for i in range(20):
        P.append(rbox([6.02, 0.04, 0.12], (W / 2 - 13, 0.51, -19 + i * 2), "#4a3c2e", b=0.01, n=f"pier_plank_{i}", parent=g))
    P += [rbox([4.5, 1.4, 12], (W / 2 - 3, 0.2, 0), "#3d4a57", b=0.3, n="boat_hull", parent=g, m="metal"),
          rbox([3.2, 2.0, 4], (W / 2 - 3, 1.9, 2), SNOW_D, b=0.15, n="boat_cabin", parent=g),
          cyl(0.15, 0.15, 3.5, (W / 2 - 3, 3.6, -1), METAL_D, seg=10, n="boat_mast", parent=g, m="metal")]
    # 컨테이너 더미 (대칭)
    g = "containers"
    def stacks(s):
        out, k = [], 0
        layout = [(-18, 12, 0, 0), (-15.4, 12, 0, 0), (-16.7, 12, 2.6, 0), (-6, 16, 0, 90), (-6, 9, 0, 90),
                  (4, 11, 0, 0), (6.6, 11, 0, 0), (5.3, 11, 2.6, 0), (14, 15, 0, 90), (-22, 2, 0, 0), (-22, -2.5, 0, 0)]
        for i, (x, z, y, r) in enumerate(layout):
            if s < 0 and z < 3: continue
            out += container(x * (1 if s > 0 else -1) if False else x, y, s * z, g, CONT[(i + (s > 0)) % len(CONT)], f"{'A' if s > 0 else 'B'}{i}", rot=r)
        return out
    P += mirror(stacks)
    # 크레인
    g = "crane"
    cx = 14
    for dx in (-2.5, 2.5):
        for dz in (-2.5, 2.5):
            P.append(rbox([0.5, 12, 0.5], (cx + dx, 6, dz), "#d4ac0d", b=0.05, n=f"crane_leg_{dx}_{dz}", parent=g, m="metal"))
    for i in range(4):
        P.append(rbox([5.6, 0.25, 0.25], (cx, 2.5 + i * 3, 2.5), "#d4ac0d", b=0.03, n=f"crane_brace_S_{i}", parent=g, m="metal"))
        P.append(rbox([5.6, 0.25, 0.25], (cx, 2.5 + i * 3, -2.5), "#d4ac0d", b=0.03, n=f"crane_brace_N_{i}", parent=g, m="metal"))
    P += [rbox([22, 1.0, 1.4], (cx + 6, 12.5, 0), "#d4ac0d", b=0.08, n="crane_boom", parent=g, m="metal"),
          rbox([3.5, 2.6, 3], (cx - 2, 12.8, 0), "#4a5561", b=0.15, n="crane_cab", parent=g),
          rbox([3.6, 0.8, 2.4], (cx - 2, 12.8, 1.52), "#9fd8ff", b=0.05, n="crane_window", parent=g, m="glass", a=0.4),
          cyl(0.04, 0.04, 6, (cx + 12, 9.5, 0), "#202328", seg=6, n="crane_cable", parent=g, m="metal")]
    P += container(cx + 12, 4.0, 0, g, CONT[4], "hanging", rot=90)
    g = "cover"
    for i, (x, z) in enumerate(((-10, 4), (10, -4), (-2, 0), (2, 0), (-14, -6), (14, 6))):
        P += barrier(x, z, g, rot=(90 if i < 2 else 0), k=f"h{i}", c="#8d99a6")
    for i, (x, z) in enumerate(((-4, 6), (4, -6), (-25, 10), (-25, -10))):
        P += barrel(x, z, g, k=f"h{i}", c=CONT[i])
    return P

# =====================================================================
# 3. 네온 옥상
# =====================================================================
ROOF1, ROOF2, ROOF3, EDGE, NEON1, NEON2, NEON3 = "#3a3f4b", "#454b58", "#333845", "#262a33", "#ff3fa4", "#3fe0ff", "#b26bff"

def neon():
    P = groups("buildings", "spawn_A", "spawn_B", "bridges", "props", "signs")
    g = "buildings"
    P += [rbox([90, 0.2, 80], (0, -24, 0), "#14161c", b=0.05, n="street_far_below", parent=g)]
    # (x, z, w, d, 옥상 높이, 색)
    blds = [(0, 0, 18, 14, 0.0, ROOF1),
            (-20, 0, 14, 16, 2.0, ROOF2), (20, 0, 14, 16, 2.0, ROOF2),
            (-12, 17, 16, 12, -1.0, ROOF3), (12, -17, 16, 12, -1.0, ROOF3),
            (12, 17, 12, 12, 1.0, ROOF1), (-12, -17, 12, 12, 1.0, ROOF1),
            (0, 26, 20, 8, 0.0, ROOF2), (0, -26, 20, 8, 0.0, ROOF2)]
    # 다리 (x0, z0, y0, x1, z1, y1, 번호[, 이름]) — 6·7번은 4·5번 다리 위에서 만나는 T자 연결
    W_BR = 3.0
    spans = [(-9, 0, 0.1, -13, 0, 2.1, 0), (9, 0, 0.1, 13, 0, 2.1, 1),
             (-15, 11, -0.9, -15, 8, 2.1, 2), (15, -11, -0.9, 15, -8, 2.1, 3),   # 원래 x=±12: 위쪽 끝이 1·2번 건물 밖(허공)에 떨어져 있었음
             (0, 7, 0.1, 0, 22, 0.1, 4), (0, -7, 0.1, 0, -22, 0.1, 5),
             (-4, 17, -0.9, -W_BR / 2, 17, 0.1, 6), (W_BR / 2, 17, 0.1, 6, 17, 1.1, 6, "6b"),
             (4, -17, -0.9, W_BR / 2, -17, 0.1, 7), (-W_BR / 2, -17, 0.1, -6, -17, 1.1, 7, "7b"),
             (20, 8, 2.1, 14, 11, 1.1, 8), (-20, -8, 2.1, -14, -11, 1.1, 9)]
    # 난간 입구: 다리 끝이 닿는 옥상 가장자리마다 (건물, 변) → [(가장자리 위 좌표, 반폭)]
    gaps = {}
    for sp in spans:
        x0, z0, y0, x1, z1, y1 = sp[:6]
        L = math.hypot(x1 - x0, z1 - z0); ux, uz = (x1 - x0) / L, (z1 - z0) / L
        for (ex, ez, ey) in ((x0, z0, y0), (x1, z1, y1)):
            for i, (x, z, w, d, h, c) in enumerate(blds):
                if abs(ey - 0.1 - h) > 0.05: continue
                for side, on, along, cosv in (("E", abs(ex - (x + w / 2)) < 0.05 and abs(ez - z) <= d / 2, ez - z, abs(ux)),
                                              ("W", abs(ex - (x - w / 2)) < 0.05 and abs(ez - z) <= d / 2, ez - z, abs(ux)),
                                              ("S", abs(ez - (z + d / 2)) < 0.05 and abs(ex - x) <= w / 2, ex - x, abs(uz)),
                                              ("N", abs(ez - (z - d / 2)) < 0.05 and abs(ex - x) <= w / 2, ex - x, abs(uz))):
                    if on: gaps.setdefault((i, side), []).append((along, W_BR / 2 / max(cosv, 0.3) + 0.25))
    def segs(lo, hi, holes):
        """[lo, hi] 구간에서 holes(중심, 반폭)를 뺀 조각들."""
        out, cur = [], lo
        for cm, hw in sorted(holes):
            if cm - hw > cur + 0.05: out.append((cur, cm - hw))
            cur = max(cur, cm + hw)
        if hi > cur + 0.05: out.append((cur, hi))
        return out
    for i, (x, z, w, d, h, c) in enumerate(blds):
        P += [rbox([w, 24 + h, d], (x, (h - 24) / 2, z), "#1c2029", b=0.2, n=f"tower_{i}", parent=g),
              rbox([w + 0.1, 0.3, d + 0.1], (x, h - 0.15, z), c, b=0.05, n=f"roof_{i}", parent=g, m="rubber")]
        for s in (-1, 1):
            nm = 'S' if s > 0 else 'N'
            pieces = segs(-(w + 0.6) / 2, (w + 0.6) / 2, gaps.get((i, nm), []))
            for k, (a0, a1) in enumerate(pieces):
                P.append(rbox([a1 - a0, 1.0, 0.4], (x + (a0 + a1) / 2, h + 0.5, z + s * (d / 2 + 0.1)), EDGE, b=0.06,
                              n=f"parapet_{i}_{nm}" + (f"_{k}" if len(pieces) > 1 else ""), parent=g))
            nm = 'E' if s > 0 else 'W'
            pieces = segs(-(d + 0.6) / 2, (d + 0.6) / 2, gaps.get((i, nm), []))
            for k, (a0, a1) in enumerate(pieces):
                P.append(rbox([0.4, 1.0, a1 - a0], (x + s * (w / 2 + 0.1), h + 0.5, z + (a0 + a1) / 2), EDGE, b=0.06,
                              n=f"parapet_{i}_{nm}" + (f"_{k}" if len(pieces) > 1 else ""), parent=g))
        for k in range(int(w / 3)):
            for row in range(5):
                P.append(rbox([1.4, 1.0, 0.05], (x - w / 2 + 1.5 + k * 3, h - 3 - row * 3.5, z + d / 2 + 0.02), [NEON2, "#ffe08a", "#2a3140"][(k + row + i) % 3], b=0.02,
                              n=f"window_{i}_{k}_{row}", parent=g, m="glow" if (k + row + i) % 3 < 2 else None))
    P += spawn("A", 30, 16, 6, ROOF2, "#2c313c", "#1f232b") + spawn("B", -30, 16, 6, ROOF2, "#2c313c", "#1f232b")
    # 다리
    g = "bridges"
    def bridge(x0, z0, y0, x1, z1, y1, k, w=W_BR, name=None, rail_gaps=()):
        name = name if name is not None else str(k)
        L = math.hypot(x1 - x0, z1 - z0); ang = math.degrees(math.atan2(x1 - x0, z1 - z0))
        pitch = -math.degrees(math.atan2(y1 - y0, L))
        mid = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
        # 회전: 먼저 경사(로컬 X), 그다음 방향(Y). 노드 회전은 XYZ 오일러라 변환해서 넣음
        # (원래 r=(pitch, ang, 0)은 경사를 월드 X축에 걸어 가로 다리가 옆으로 기울었음)
        from scipy.spatial.transform import Rotation as _R
        rot = tuple(round(float(v), 4) for v in _R.from_euler("YX", [ang, pitch], degrees=True).as_euler("XYZ", degrees=True))
        SL = math.hypot(L, y1 - y0)          # 경사 길이 (평면 길이 L로 만들면 경사 다리가 짧아져 끝이 안 닿음)
        out = [rbox([w, 0.25, SL], mid, METAL_D, b=0.04, r=rot, n=f"bridge_{name}", parent=g, m="metal")]
        ux, uz = (x1 - x0) / L, (z1 - z0) / L
        for s in (-1, 1):
            ox, oz = math.cos(math.radians(ang)) * s * w / 2, -math.sin(math.radians(ang)) * s * w / 2
            # 난간: rail_gaps (다리 시작점부터의 거리, 반폭) 구간은 비움 — 옆 다리가 붙는 곳
            pieces = segs(0, L, [(c_, hw_) for c_, hw_, sd in rail_gaps if sd in (0, s)])
            for j, (t0, t1) in enumerate(pieces):
                tm = (t0 + t1) / 2
                cy = y0 + (y1 - y0) * tm / L
                out.append(rbox([0.08, 0.08, (t1 - t0) * SL / L], (x0 + ux * tm + ox, cy + 1.0, z0 + uz * tm + oz), NEON2 if k % 2 else NEON1, b=0.02, r=rot,
                                n=f"bridge_{name}_rail_{s}" + (f"_{j}" if len(pieces) > 1 else ""), parent=g, m="glow"))
        return out
    T_GAP = W_BR / 2 + 0.2      # 4·5번 다리 난간에서 6·7번이 붙는 곳의 반폭
    for sp in spans:
        x0, z0, y0, x1, z1, y1, k = sp[:7]
        rg = ()
        if k == 4: rg = ((17 - 7, T_GAP, 0),)       # z=17 (시작 z=7 기준 10 m)
        if k == 5: rg = ((17 - 7, T_GAP, 0),)
        P += bridge(x0, z0, y0, x1, z1, y1, k, name=sp[7] if len(sp) > 7 else None, rail_gaps=rg)
    # 소품: 실외기, 물탱크, 안테나, 환기구
    g = "props"
    def roof_props(s):
        out = []
        for i, (x, z) in enumerate(((-22, 4), (-18, -4), (18, 4), (22, -4))):
            out += [rbox([1.6, 1.2, 1.2], (x, 2.6, s * z), "#9aa3ad", b=0.08, n=f"ac_unit_{s}_{i}", parent=g, m="metal"),
                    cyl(0.45, 0.45, 0.05, (x, 3.23, s * z), "#202328", seg=16, n=f"ac_fan_{s}_{i}", parent=g, m="metal")]
        out += [cyl(1.4, 1.4, 2.4, (-15 * s, 2.2, s * 20), "#6b5a48", seg=16, n=f"water_tank_{s}", parent=g),
                cyl(0.0, 1.6, 1.0, (-15 * s, 3.9, s * 20), "#4a3e33", seg=16, n=f"water_tank_roof_{s}", parent=g)]
        for k in range(4):
            out.append(cyl(0.1, 0.1, 2.2, (-15 * s + 1.0 * math.cos(k * 1.57), 0.0, s * 20 + 1.0 * math.sin(k * 1.57)), METAL_D, seg=8, n=f"water_tank_leg_{s}_{k}", parent=g, m="metal"))
        out += [cap(0.05, 6, (5 * s, 3.5, s * 3), METAL_D, n=f"antenna_{s}", parent=g, m="metal"),
                sph(0.15, (5 * s, 6.6, s * 3), "#ff3b30", n=f"antenna_light_{s}", parent=g, m="glow")]
        out += crate(-4 * s, s * 4, g, k=f"n{s}a", c="#3a4250") + crate(4 * s, s * 2, g, k=f"n{s}b", c="#3a4250")
        # 방벽: 원래 (0, ±20) 4·5번 다리 위를 막고 있었음 → 다리 머리 옆 중앙 옥상으로 비킴
        out += barrier(4.5 * s, 5.2 * s, g, k=f"n{s}", c="#565d6b")
        return out
    P += mirror(roof_props)
    # 네온 간판
    g = "signs"
    for i, (x, z, ry, c, w) in enumerate(((-27, 0, 90, NEON1, 6), (27, 0, -90, NEON2, 6), (0, 9, 0, NEON3, 8), (0, -9, 180, NEON3, 8))):
        P += [rbox([w, 1.6, 0.25], (x, 5.0 if abs(x) > 20 else 3.6, z), "#151820", b=0.08, r=(0, ry, 0), n=f"sign_board_{i}", parent=g),
              rbox([w - 0.6, 0.18, 0.05], (x + (0.15 if ry == -90 else -0.15 if ry == 90 else 0), (5.0 if abs(x) > 20 else 3.6) + 0.35, z + (0.15 if ry == 0 else -0.15 if ry == 180 else 0)), c, b=0.02, r=(0, ry, 0), n=f"sign_neon_top_{i}", parent=g, m="glow"),
              rbox([w - 1.4, 0.18, 0.05], (x + (0.15 if ry == -90 else -0.15 if ry == 90 else 0), (5.0 if abs(x) > 20 else 3.6) - 0.3, z + (0.15 if ry == 0 else -0.15 if ry == 180 else 0)), c, b=0.02, r=(0, ry, 0), n=f"sign_neon_bottom_{i}", parent=g, m="glow")]
    return P

# =====================================================================
# 4. 정글 사원
# =====================================================================
JG, JG_D, MOSS, TEMPLE, TEMPLE_D, RIVER, BARK = "#4f7a3a", "#3a5c2a", "#6f8f4a", "#8f8a78", "#6e6a5b", "#3a8fa8", "#5a3e28"

def tree(x, z, g, k, h=6.0, r=2.4, seed=0):
    return [cap(0.32, h, (x, h / 2, z), BARK, r2=0.22, n=f"tree_{k}_trunk", parent=g),
            rock([r * 2, r * 1.3, r * 2], (x, h + 0.4, z), JG if seed % 2 else JG_D, seed=100 + seed, pts=22, j=0.3, n=f"tree_{k}_canopy", parent=g),
            rock([r * 1.3, r, r * 1.3], (x + 0.6, h + 1.4, z - 0.4), MOSS, seed=200 + seed, pts=16, n=f"tree_{k}_canopy_top", parent=g)]

def jungle():
    P = groups("terrain", "spawn_A", "spawn_B", "temple", "river", "trees", "cover")
    W, D = 60, 52
    g = "terrain"
    P += [rbox([W + 2, 0.4, D + 2], (0, -0.2, 0), "#5d6b3e", b=0.1, n="ground", parent=g, m="rubber")]
    P += [wall(-W / 2, -D / 2, W / 2, -D / 2, 6, g, c=TEMPLE_D, t=1.0, n="ruin_wall_north"), wall(-W / 2, D / 2, W / 2, D / 2, 6, g, c=TEMPLE_D, t=1.0, n="ruin_wall_south"),
          wall(-W / 2, -D / 2, -W / 2, D / 2, 6, g, c=TEMPLE_D, t=1.0, n="ruin_wall_west"), wall(W / 2, -D / 2, W / 2, D / 2, 6, g, c=TEMPLE_D, t=1.0, n="ruin_wall_east")]
    P += spawn("A", D / 2, 16, 6, TEMPLE, TEMPLE, "#5a6b44") + spawn("B", -D / 2, 16, 6, TEMPLE, TEMPLE, "#5a6b44")
    # 강 (x축 방향으로 맵을 가로지름) + 다리 3개
    g = "river"
    P += [rbox([W, 0.6, 6], (0, -0.35, 0), "#2c4a3a", b=0.05, n="riverbed", parent=g),
          rbox([W, 0.05, 6], (0, -0.15, 0), RIVER, b=0.02, n="river_water", parent=g, a=0.82)]
    for i in range(16):
        x = -W / 2 + 2 + i * 3.8
        for s in (-1, 1):
            P.append(rock([1.4, 0.6, 1.0], (x, 0.05, s * 3.2), "#7a7a6a", seed=300 + i * 2 + (s > 0), n=f"bank_rock_{i}_{s}", parent=g))
    for k, x in enumerate((-18, 0, 18)):
        wide = 5 if x == 0 else 3
        P += [rbox([wide, 0.35, 8], (x, 0.25, 0), TEMPLE if x == 0 else "#6b4a2e", b=0.05, n=f"bridge_{k}", parent=g)]
        if x != 0:
            for s in (-1, 1):
                P.append(cap(0.05, 7.6, (x + s * wide / 2, 1.0, 0), "#c9a66b", r=(90, 0, 0), n=f"bridge_{k}_rope_{s}", parent=g))
    # 계단식 사원 (중앙, 강 위에 걸친 구조 아님 → 양쪽에 작은 사당 + 중앙 대사원은 강 북쪽?) → 대칭 위해 강 위 플랫폼
    g = "temple"
    P += [rbox([14, 0.6, 14], (0, 0.3, 0), TEMPLE_D, b=0.08, n="temple_platform", parent=g)]
    for k, (w, h) in enumerate(((11, 1.4), (8, 1.4), (5, 1.6))):
        y = 0.6 + sum(hh for _, hh in ((11, 1.4), (8, 1.4), (5, 1.6))[:k])
        P.append(rbox([w, h, w], (0, y + h / 2, 0), TEMPLE if k % 2 == 0 else TEMPLE_D, b=0.1, n=f"temple_tier_{k}", parent=g))
        for s in (-1, 1):
            P.append(rbox([w + 0.1, 0.25, 0.25], (0, y + h - 0.12, s * (w / 2)), MOSS, b=0.05, n=f"temple_moss_{k}_{s}", parent=g))
    for s in (-1, 1):
        for i in range(7):
            P.append(rbox([2.6, 0.32, 0.5], (0, 0.76 + i * 0.6, s * (5.8 - i * 0.48)), TEMPLE_D, b=0.04, n=f"temple_stair_{s}_{i}", parent=g))
    P += [rbox([3.4, 2.6, 3.4], (0, 6.1, 0), TEMPLE, b=0.1, n="shrine", parent=g),
          rbox([1.4, 1.8, 0.2], (0, 5.6, 1.7), "#1d1f1a", b=0.05, n="shrine_door_S", parent=g),
          rbox([1.4, 1.8, 0.2], (0, 5.6, -1.7), "#1d1f1a", b=0.05, n="shrine_door_N", parent=g),
          cyl(0, 2.2, 1.4, (0, 8.1, 0), TEMPLE_D, seg=4, r=(0, 45, 0), n="shrine_roof", parent=g),
          sph(0.35, (0, 5.9, 1.8), "#7cf0a0", n="shrine_glow", parent=g, m="glow")]
    def shrines(s):
        out = []
        for side in (-1, 1):
            x, z = side * 17, s * 13
            out += [rbox([5, 0.5, 5], (x, 0.25, z), TEMPLE_D, b=0.06, n=f"altar_base_{s}_{side}", parent=g),
                    rbox([1.2, 3.0, 1.2], (x - 1.8, 2.0, z - 1.8), TEMPLE, b=0.06, n=f"altar_post_{s}_{side}_a", parent=g),
                    rbox([1.2, 3.0, 1.2], (x + 1.8, 2.0, z - 1.8), TEMPLE, b=0.06, n=f"altar_post_{s}_{side}_b", parent=g),
                    rbox([5, 0.7, 1.6], (x, 3.8, z - 1.8), TEMPLE_D, b=0.06, n=f"altar_lintel_{s}_{side}", parent=g),
                    rock([1.6, 1.8, 1.4], (x, 1.3, z + 0.8), TEMPLE, seed=400 + side + s * 3, n=f"idol_{s}_{side}", parent=g)]
        return out
    P += mirror(shrines)
    g = "trees"
    k = 0
    for s in (-1, 1):
        for i, (x, z) in enumerate(((-24, 8), (-25, 17), (-8, 9), (8, 9), (24, 8), (25, 17), (-14, 21), (14, 21), (-27, 3.8), (27, 3.8))):
            P += tree(x * (1 if s > 0 else -1), s * z, g, k, h=5 + (i % 3), r=2 + 0.4 * (i % 2), seed=k); k += 1
    g = "cover"
    for i, (x, z) in enumerate(((-6, 14), (6, -14), (-11, 6), (11, -6), (11, 6), (-11, -6))):
        P.append(rock([2.2, 1.3, 1.6], (x, 0.55, z), "#7a7a6a", seed=500 + i, n=f"boulder_{i}", parent=g))
    for i, (x, z) in enumerate(((-3, 18), (3, -18))):
        P += crate(x, z, g, k=f"j{i}", c="#7a5a36") + crate(x + 1.3, z, g, k=f"j{i}b", s=0.9, c="#7a5a36", rot=25)
    for i in range(10):
        a = i * 36
        P.append(cyl(0.0, 0.35, 0.9, (9 * math.cos(math.radians(a)), 0.45, 9 * math.sin(math.radians(a)) * 0.0 + (-9 if i < 5 else 9) * 0 + (i - 4.5) * 0.0), JG, seg=6, n=f"fern_{i}", parent=g) if False else
                 cyl(0.0, 0.45, 0.9, (-26 + i * 5.8, 0.45, 10.5 * (1 if i % 2 else -1)), JG, seg=6, n=f"fern_{i}", parent=g))
    return P

MAPS = [
    ("desert_ruins", "사막 유적", desert, "60 × 50 m", "가운데 지구라트를 차지하는 맵. 양옆 아치 회랑과 부서진 기둥 사이로 측면 돌파. 모래언덕이 낮은 엄폐를 만들어요.",
     dict(pos=(-3, 1.65, 19), look=(0, 2.5, 0))),
    ("frost_harbor", "설원 항구", harbor, "64 × 50 m", "컨테이너 미로와 얼어붙은 부두. 크레인 아래가 중앙 교전 지점이고, 부두 쪽은 길고 열린 저격 라인이에요.",
     dict(pos=(-4, 1.65, 19), look=(4, 2.0, 0))),
    ("neon_rooftops", "네온 옥상", neon, "높이가 다른 옥상 9개", "빌딩 옥상을 다리로 연결한 수직 맵. 높은 옥상이 사선을 잡고, 다리가 병목이에요.",
     dict(pos=(-2, 1.75, 25), look=(0, 1.0, 0))),
    ("jungle_temple", "정글 사원", jungle, "60 × 52 m", "맵을 가로지르는 강과 다리 3개. 강 위 계단식 사원이 고지대이고, 양옆 흔들다리는 빠른 우회로예요.",
     dict(pos=(-3, 1.65, 19), look=(0, 3.0, 0))),
]
