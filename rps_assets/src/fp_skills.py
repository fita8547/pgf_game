"""1인칭 스킬 동작 리그 (glb/fp_skills/).
구조는 fp_rigs와 같음: fp_root → grip_R / grip_L (애니메이션)
→ 엔진에서 fp_arms/<캐릭터>.glb 의 arm_R 을 grip_R, arm_L 을 grip_L 자식으로 붙이면(로컬 위치 0) 캐릭터 팔이 그대로 따라감.
카메라 기준: 원점 = 눈, 시선 -Z, Y 위. 화면 밖으로 숨길 때는 손을 아래(-Y)로 내림.

- throw.glb      : throw (0.5초). grip_R/item_socket 에 수류탄·비콘·자갈 등 스킬 모델을 붙임. 0.27초에 손에서 놓음(extras.release).
- place.glb      : place (0.7초). 두 손 사이 item_socket 에 포탑·덫·방벽 모델을 붙임. 0.45초에 바닥에 내려놓음.
- shuriken.glb   : idle (루프 1.6초) / throw (0.35초). 종이 표창 포함.
- twin_blade.glb : idle (루프 1.6초) / slash_L / slash_R (각 0.4초). 스닙 쌍날 포함.
- shield.glb     : raise (0.3초) / hold (루프 1.6초). 시어 가시 방패 포함, 오른손은 화면 밖.
"""
import math
from parts import *

def _ch(node, path, times, values):
    return {"node": node, "path": path, "times": times, "values": values}

R_REST = (0.12, -0.13, -0.34)      # 총을 쥔 오른손 위치 (fp_rigs 와 비슷)
L_REST = (-0.12, -0.16, -0.42)
HIDE_R = (0.26, -0.62, -0.25)      # 화면 밖 (아래)
HIDE_L = (-0.26, -0.62, -0.25)

def base(rpos=R_REST, lpos=L_REST):
    return [empty((0, 0, 0), "fp_root"), empty(rpos, "grip_R", parent="fp_root"), empty(lpos, "grip_L", parent="fp_root")]

def off(a, b):
    """애니메이션 translation 은 레스트 위치에 더하는 오프셋 → 절대 위치 a 를 레스트 b 기준으로."""
    return tuple(round(a[i] - b[i], 4) for i in range(3))

def track(node, rest, keys):
    """keys: [(t, 위치, 회전)] → translation + rotation 채널."""
    ts = [k[0] for k in keys]
    return [_ch(node, "translation", ts, [off(k[1], rest) for k in keys]),
            _ch(node, "rotation", ts, [k[2] for k in keys])]

# ------------------------------------------------------------------ 던지기 (공용)
def throw():
    rr, lr = (0.16, -0.24, -0.36), (-0.15, -0.26, -0.42)
    P = base(rr, lr)
    P.append(dict(empty((0.0, 0.03, -0.035), "item_socket", parent="grip_R"), local=True))   # 손바닥 앞 (스킬 모델 원점)
    keys_R = [(0.00, rr, (0, 0, 0)),
              (0.12, (0.22, 0.00, -0.18), (35, -10, 15)),        # 귀 옆으로 들어올림 (팔꿈치 아래)
              (0.20, (0.17, 0.04, -0.28), (15, -5, 8)),
              (0.27, (0.09, 0.00, -0.50), (-12, 0, 0)),          # 앞으로 뻗으며 놓는 순간
              (0.36, (0.02, -0.22, -0.48), (25, 10, -15)),       # 팔로스루
              (0.50, (0.12, -0.58, -0.30), (40, 0, 0))]          # 화면 아래로
    keys_L = [(0.00, lr, (0, 0, 0)),
              (0.12, (-0.16, -0.10, -0.46), (-20, 10, -10)),     # 왼팔 앞으로 (균형)
              (0.27, (-0.20, -0.22, -0.36), (10, 15, -20)),
              (0.50, (-0.24, -0.60, -0.26), (30, 0, 0))]
    A = {"name": "throw", "channels": track("grip_R", rr, keys_R) + track("grip_L", lr, keys_L)}
    return P, [A], {"release": 0.27}

# ------------------------------------------------------------------ 설치 (공용)
def place():
    rr, lr = (0.12, -0.17, -0.42), (-0.12, -0.17, -0.42)
    rest_item = (0, -0.17, -0.47)
    P = base(rr, lr)
    P.append(empty(rest_item, "item_socket", parent="fp_root"))   # 두 손 사이 (스킬 모델 원점 = 바닥 중앙)
    t = [0.0, 0.15, 0.30, 0.45, 0.55, 0.70]
    R_ = [(0.22, -0.60, -0.30), (0.12, -0.17, -0.42), (0.12, -0.21, -0.46), (0.12, -0.60, -0.62), (0.14, -0.58, -0.55), (0.22, -0.64, -0.30)]
    L_ = [(-0.22, -0.60, -0.30), (-0.12, -0.17, -0.42), (-0.12, -0.21, -0.46), (-0.12, -0.60, -0.62), (-0.14, -0.58, -0.55), (-0.22, -0.64, -0.30)]
    rotR = [(30, 0, 0), (0, 0, 70), (10, 0, 70), (45, 0, 70), (40, 0, 60), (30, 0, 0)]       # 손바닥이 물건 옆면을 감쌈
    rotL = [(30, 0, 0), (0, 0, -20), (10, 0, -20), (45, 0, -20), (40, 0, -15), (30, 0, 0)]
    item = [(0, -0.60, -0.32), (0, -0.17, -0.47), (0, -0.21, -0.50), (0, -0.64, -0.66), (0, -0.64, -0.66), (0, -0.64, -0.66)]
    ch = track("grip_R", rr, list(zip(t, R_, rotR))) + track("grip_L", lr, list(zip(t, L_, rotL)))
    ch += [_ch("item_socket", "translation", t, [off(p, rest_item) for p in item]),
           _ch("item_socket", "scale", [0, 0.44, 0.45, 0.7], [(1, 1, 1), (1, 1, 1), (0.001, 0.001, 0.001), (0.001, 0.001, 0.001)])]
    return P, [{"name": "place", "channels": ch}], {"release": 0.45}

# ------------------------------------------------------------------ 오리가미 표창
def shuriken_model(parent, n="shuriken", s=1.0):
    out = [dict(empty((0.0, 0.035, -0.045), n, parent=parent), local=True)]
    out[0]["r"] = [62, 0, 0]          # 화면 쪽으로 눕혀 별 모양이 보이게
    for k in range(4):
        a = math.radians(k * 90)
        out.append(dict(cyl(0, 0.022 * s, 0.075 * s, (0.032 * s * math.cos(a), 0, 0.032 * s * math.sin(a)), PAPER if k % 2 else BLUE,
                            r=(0, -k * 90, -90), seg=4, n=f"{n}_blade_{k}", parent=n), local=True))
    out.append(dict(cyl(0.014 * s, 0.014 * s, 0.01, (0, 0, 0), INK, seg=6, n=f"{n}_hub", parent=n), local=True))
    return out

def shuriken():
    rr, lr = (0.14, -0.15, -0.36), (-0.15, -0.22, -0.44)
    P = base(rr, lr)
    P += shuriken_model("grip_R", "shuriken")
    for i in range(2):   # 왼손에 부채꼴로 든 여분 2장
        P += shuriken_model("grip_L", f"spare_{i}", s=0.9)
        P[-6]["p"] = [0.01 + i * 0.02, 0.0, -0.03 - i * 0.012]
    idle = {"name": "idle", "channels": track("grip_R", rr, [(0, rr, (0, 0, -8)), (0.8, (0.142, -0.146, -0.36), (1.5, 1, -7)), (1.6, rr, (0, 0, -8))]) +
            track("grip_L", lr, [(0, lr, (0, 0, 6)), (0.8, (-0.151, -0.217, -0.44), (1, 0, 7)), (1.6, lr, (0, 0, 6))]) +
            [_ch("shuriken", "rotation", [0, 0.8, 1.6], [(62, 0, 0), (62, 4, 0), (62, 0, 0)])]}
    tt = [0, 0.07, 0.14, 0.22, 0.35]
    thr = {"name": "throw", "channels": track("grip_R", rr, [(0, rr, (0, 0, -8)), (0.07, (0.06, -0.10, -0.30), (-10, 40, 30)),   # 손목을 안쪽으로 감음
                                                                (0.14, (0.16, -0.12, -0.48), (5, -35, -25)),                  # 바깥으로 튕김
                                                                (0.22, (0.18, -0.18, -0.42), (10, -20, -15)), (0.35, rr, (0, 0, -8))]) +
           track("grip_L", lr, [(0, lr, (0, 0, 6)), (0.14, (-0.16, -0.24, -0.43), (4, 0, 8)), (0.35, lr, (0, 0, 6))]) +
           [_ch("shuriken", "translation", tt, [(0, 0, 0), (0, 0, 0), (0.15, 0.06, -1.6), (0.15, 0.06, -1.6), (0, 0, 0)]),
            _ch("shuriken", "rotation", tt, [(62, 0, 0), (62, 0, 0), (10, 300, 0), (10, 300, 0), (62, 0, 0)]),
            _ch("shuriken", "scale", [0, 0.15, 0.16, 0.30, 0.35], [(1, 1, 1), (1, 1, 1), (0.001, 0.001, 0.001), (0.001, 0.001, 0.001), (1, 1, 1)])]}
    return P, [idle, thr], {"release": 0.13}

# ------------------------------------------------------------------ 스닙 쌍날
def blade(parent, side):
    s = 1 if side == "R" else -1
    n = f"blade_{side}"
    hp = (0.0, 0.01, 0.0) if side == "R" else (0.0, -0.01, 0.0)
    out = [dict(empty(hp, n, parent=parent), local=True)]
    # 손잡이 고리(손을 감쌈) → 날은 손에서 위·앞으로
    out += [dict(q, local=True) for q in ring(0.05, 0.016, (0, 0, 0), RED_D, seg=10, plane="yz" if side == "R" else "xz", n=f"{n}_ring", parent=n)]
    out += [dict(rbox([0.014, 0.44, 0.065], (0, 0.25, -0.11), STEEL, b=0.004, r=(-28, 0, 0), n=f"{n}_steel", parent=n, m="metal"), local=True),
            dict(rbox([0.008, 0.42, 0.014], (0, 0.25, -0.15), RED, b=0.002, r=(-28, 0, 0), n=f"{n}_edge", parent=n, m="glow"), local=True),
            dict(cyl(0, 0.022, 0.06, (0, 0.445, -0.215), STEEL, r=(-28, 0, 0), seg=4, n=f"{n}_tip", parent=n, sc=(0.4, 1, 1)), local=True),
            dict(cyl(0.018, 0.018, 0.02, (0, 0.05, -0.02), BK, r=Z, seg=8, n=f"{n}_pivot", parent=n), local=True)]
    if side == "L":   # 왼손은 손바닥이 위를 보는 받침 손 → 날을 세워 쥔 것처럼 손잡이 기준 회전
        out[0]["r"] = [0, 0, 90]
    return out

def twin_blade():
    rr, lr = (0.17, -0.20, -0.40), (-0.17, -0.20, -0.40)
    P = base(rr, lr) + blade("grip_R", "R") + blade("grip_L", "L")
    idleR = (0, 40, 14); idleL = (0, -40, -100)    # 날 면이 화면 쪽으로 보이게 비틈
    idle = {"name": "idle", "channels": track("grip_R", rr, [(0, rr, idleR), (0.8, (0.172, -0.195, -0.40), (2, 0, 15)), (1.6, rr, idleR)]) +
            track("grip_L", lr, [(0, lr, idleL), (0.8, (-0.172, -0.196, -0.40), (2, 0, -101)), (1.6, lr, idleL)])}
    def slash(side):
        s = 1 if side == "R" else -1
        g, rest, idl = (("grip_R", rr, idleR) if side == "R" else ("grip_L", lr, idleL))
        other, orest, oid = (("grip_L", lr, idleL) if side == "R" else ("grip_R", rr, idleR))
        tt = [0, 0.08, 0.18, 0.28, 0.4]
        k = [(0, rest, idl),
             (0.08, (0.24 * s, -0.02, -0.34), (idl[0] - 35, idl[1] + 25 * s, idl[2] + 30 * s)),      # 바깥 위로 들어올림
             (0.18, (-0.10 * s, -0.30, -0.50), (idl[0] + 55, idl[1] - 30 * s, idl[2] - 45 * s)),     # 대각선 아래 안쪽으로 벰
             (0.28, (-0.06 * s, -0.36, -0.44), (idl[0] + 45, idl[1] - 25 * s, idl[2] - 40 * s)),
             (0.4, rest, idl)]
        ok = [(0, orest, oid), (0.18, (orest[0] - 0.02 * s, orest[1] - 0.04, orest[2] + 0.04), oid), (0.4, orest, oid)]
        return {"name": f"slash_{side}", "channels": track(g, rest, k) + track(other, orest, ok)}
    return P, [idle, slash("L"), slash("R")], {}

# ------------------------------------------------------------------ 시어 가시 방패
def shield():
    lr = (-0.20, -0.14, -0.48)
    P = base(HIDE_R, lr)
    P.append(dict(empty((0.04, 0.02, -0.06), "shield", parent="grip_L"), local=True))
    sh = "shield"
    S = 0.62   # 스킬 모델(0.9×1.0 m)의 1인칭용 축소판
    loc = lambda q: dict(q, local=True)
    P += [loc(rbox([0.9 * S, 1.0 * S, 0.06], (0.0, 0.0, 0.0), STEEL, b=0.02, n="shield_plate", parent=sh, m="metal")),
          loc(rbox([0.95 * S, 0.06, 0.09], (0.0, 0.5 * S, 0.0), RED, b=0.015, n="shield_rim_top", parent=sh)),
          loc(rbox([0.95 * S, 0.06, 0.09], (0.0, -0.5 * S, 0.0), RED, b=0.015, n="shield_rim_bottom", parent=sh)),
          loc(rbox([0.05, 1.0 * S, 0.08], (0.45 * S, 0, 0.0), RED, b=0.012, n="shield_rim_R", parent=sh)),
          loc(rbox([0.05, 1.0 * S, 0.08], (-0.45 * S, 0, 0.0), RED, b=0.012, n="shield_rim_L", parent=sh)),
          loc(cyl(0.07, 0.07, 0.04, (0, 0, -0.05), RED_D, r=Z, seg=10, n="shield_boss", parent=sh)),
          loc(rbox([0.1, 0.08, 0.05], (0, 0, 0.055), BK, b=0.01, n="shield_handle", parent=sh))]       # 안쪽 손잡이 (손바닥 쪽)
    for i in range(3):
        for j in range(2):
            P.append(loc(cyl(0, 0.03, 0.12, ((-0.28 + i * 0.28) * S, (-0.2 + j * 0.4) * S, -0.09), STEEL, r=NZ, seg=4, n=f"shield_spike_{i}_{j}", parent=sh, m="metal")))
    shr = (0, 18, 0)   # 방패를 살짝 안쪽으로 돌려 오른쪽 시야를 남김
    raise_ = {"name": "raise", "channels": track("grip_L", lr, [(0, (-0.30, -0.70, -0.32), (40, 30, 0)), (0.18, (-0.21, -0.12, -0.47), (-6, 16, 0)), (0.3, lr, shr)])}
    hold = {"name": "hold", "channels": track("grip_L", lr, [(0, lr, shr), (0.8, (-0.201, -0.135, -0.48), (1, 18.5, 0.5)), (1.6, lr, shr)])}
    return P, [raise_, hold], {}

FP_SKILLS = [("throw", throw), ("place", place), ("shuriken", shuriken), ("twin_blade", twin_blade), ("shield", shield)]
