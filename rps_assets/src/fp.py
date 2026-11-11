"""1인칭 뷰모델.
- 총별 FP 리그(fp_rig_<gun>.glb): fp_root → weapon(애니메이션) → 총 파츠 + grip_R + grip_L(애니메이션)
  애니메이션: idle, fire, reload, draw
- 캐릭터별 FP 팔(fp_arms_<char>.glb): arm_R / arm_L 루트(원점 = 손바닥 중심)
  → 엔진/뷰어에서 arm_R을 grip_R, arm_L을 grip_L의 자식으로 붙이면 어떤 총이든 동작.
카메라 기준: 원점 = 눈, 시선 -Z, Y 위.
"""
import math
import numpy as np
from parts import *

def look_euler(d):
    """로컬 +Y를 방향 d로 돌리는 XYZ 오일러(도)."""
    d = np.array(d, float); d /= np.linalg.norm(d)
    g = math.asin(max(-1, min(1, -d[0])))
    a = math.atan2(d[2], d[1])
    return (math.degrees(a), 0.0, math.degrees(g))

# 총별 사양: 들고 있는 위치, 왼손 위치(총 로컬), 반동, 탄창 노드, 장전 방식
GUN_FP = {
    "pistol":   dict(sight=(0.0, 0.0675, 0.026), ads_fov=58, eye=0.24, scope=False, hold=(0.105, -0.125, -0.33), L=(-0.004, -0.06, 0.02), L_style="support", kick=1.0, fd=0.22, mag=["mag_baseplate"], slide=["slide", "serration_0", "serration_1", "serration_2", "serration_3", "serration_4", "serration_5", "serration_6", "rear_sight_base", "rear_sight_L", "rear_sight_R", "front_sight", "front_dot", "ejection_port"]),
    "revolver": dict(sight=(0.0, 0.069, 0.014), ads_fov=56, eye=0.24, scope=False, hold=(0.105, -0.13, -0.33), L=(-0.004, -0.06, 0.03), L_style="support", kick=1.4, fd=0.3, mag=["cylinder", "cylinder_axle"] + [f"flute_{i}" for i in range(6)], reload_axis=(0.035, -0.01, 0), slide=[]),
    "smg":      dict(sight=(0.0, 0.1, 0.04), ads_fov=54, eye=0.16, scope=False, hold=(0.1, -0.13, -0.3), L=(0.0, 0.0, -0.235), L_style="under", kick=0.5, fd=0.09, mag=["magazine", "mag_baseplate"], slide=[]),
    "rifle":    dict(sight=(0.0, 0.135, 0.075), ads_fov=36, eye=0.09, scope=True, hold=(0.11, -0.14, -0.27), L=(0.0, -0.015, -0.35), L_style="under", kick=0.7, fd=0.12, mag=["magazine", "mag_baseplate"], slide=["charging_handle"]),
    "shotgun":  dict(sight=(0.0, 0.08, 0.05), ads_fov=60, eye=0.2, scope=False, hold=(0.11, -0.14, -0.29), L=(0.0, 0.002, -0.29), L_style="under", kick=2.0, fd=0.55, mag=[], pump=["pump"] + [f"pump_groove_{i}" for i in range(6)], slide=[]),
    "sniper":   dict(sight=(0.0, 0.13, 0.18), ads_fov=10, eye=0.08, scope=True, overlay=True, hold=(0.11, -0.15, -0.3), L=(0.0, -0.022, -0.33), L_style="under", kick=2.4, fd=1.1, mag=["magazine", "mag_baseplate"], bolt=["bolt_handle", "bolt_knob"], slide=[]),
    "launcher": dict(sight=(-0.075, 0.185, -0.205), ads_fov=48, eye=0.12, scope=True, hold=(0.15, -0.13, -0.22), L=(0.0, -0.035, -0.32), L_style="under", kick=3.0, fd=0.9, mag=["warhead"] + [f"warhead_fin_{i}" for i in range(4)], reload_axis=(0, 0, -0.25), slide=[]),
}
GRIP_R = (0.0, -0.04, 0.022)   # 총 로컬 좌표의 오른손 손바닥 위치

def fp_rig(gun_id, gun_parts):
    spec = GUN_FP[gun_id]
    hx, hy, hz = spec["hold"]
    P = [empty((0, 0, 0), "fp_root"), empty((hx, hy, hz), "weapon", parent="fp_root")]
    for q in gun_parts:
        q = dict(q); q["parent"] = "weapon"; q["local"] = True
        P.append(q)
    P.append(dict(empty(GRIP_R, "grip_R", parent="weapon"), local=True))
    P.append(dict(empty(spec["L"], "grip_L", parent="weapon"), local=True))
    P.append(dict(empty(spec["sight"], "ads_sight", parent="weapon"), local=True))   # 정조준 시 눈이 볼 지점
    from guns_hq import MUZZLE
    P.append(dict(empty(MUZZLE[gun_id], "muzzle", parent="weapon"), local=True))     # 총구 끝 (화염·탄 궤적 시작점)
    return P, fp_anims(gun_id, spec)

def _ch(node, path, times, values):
    return {"node": node, "path": path, "times": times, "values": values}

def fp_anims(gun_id, sp):
    k, fd = sp["kick"], sp["fd"]
    A = []
    # idle: 호흡 흔들림
    A.append({"name": "idle", "channels": [
        _ch("weapon", "translation", [0, 1.0, 2.0], [(0, 0, 0), (0.0015, 0.004, 0.002), (0, 0, 0)]),
        _ch("weapon", "rotation", [0, 1.0, 2.0], [(0, 0, 0), (0.6, 0.4, -0.3), (0, 0, 0)])]})
    # fire: 반동
    t1 = min(0.045, fd * 0.3)
    fire = [_ch("weapon", "translation", [0, t1, fd * 0.55, fd], [(0, 0, 0), (0, 0.006 * k, 0.028 * k), (0, 0.001 * k, 0.004 * k), (0, 0, 0)]),
            _ch("weapon", "rotation", [0, t1, fd * 0.55, fd], [(0, 0, 0), (4.5 * k, 0.6 * k, 0.8 * k), (0.6 * k, 0, 0), (0, 0, 0)])]
    for n in sp.get("slide", []):
        fire.append(_ch(n, "translation", [0, 0.03, min(0.09, fd * 0.8)], [(0, 0, 0), (0, 0, 0.026), (0, 0, 0)]))
    if sp.get("pump"):
        tp = [0, fd * 0.35, fd * 0.6, fd * 0.85]
        for n in sp["pump"]:
            fire.append(_ch(n, "translation", tp, [(0, 0, 0), (0, 0, 0), (0, 0, 0.07), (0, 0, 0)]))
        fire.append(_ch("grip_L", "translation", tp, [(0, 0, 0), (0, 0, 0), (0, 0, 0.07), (0, 0, 0)]))
    if sp.get("bolt"):
        tb = [0, fd * 0.3, fd * 0.45, fd * 0.6, fd * 0.75, fd * 0.9]
        for n in sp["bolt"]:
            fire.append(_ch(n, "translation", tb, [(0, 0, 0), (0, 0.012, 0), (0, 0.012, 0.06), (0, 0.012, 0.06), (0, 0.012, 0), (0, 0, 0)]))
    A.append({"name": "fire", "channels": fire})
    # reload
    tr = [0, 0.3, 0.55, 0.9, 1.25, 1.55, 1.85]
    rel = [_ch("weapon", "rotation", tr, [(0, 0, 0), (-6, 8, 22), (-8, 10, 26), (-8, 10, 26), (-6, 8, 22), (2, 0, 0), (0, 0, 0)]),
           _ch("weapon", "translation", tr, [(0, 0, 0), (-0.02, -0.03, 0.03), (-0.025, -0.035, 0.035), (-0.025, -0.035, 0.035), (-0.02, -0.03, 0.03), (0, 0.004, 0), (0, 0, 0)])]
    if sp.get("mag"):
        ax = np.array(sp.get("reload_axis", (0, -0.2, 0.0)))
        mv = [tuple(ax * f) for f in (0, 0, 1, 1, 0, 0, 0)]
        for n in sp["mag"]:
            rel.append(_ch(n, "translation", tr, mv))
        Lr = np.array(sp["L"])
        mag_spot = np.array((0.0, -0.09, -0.07)) - Lr if sp["L_style"] == "under" else np.array((0.0, -0.07, 0.0)) - Lr
        if "reload_axis" in sp:
            mag_spot = np.array(sp.get("reload_axis")) * 0.9 + np.array((0, 0.03, -0.1 if gun_id == "launcher" else 0.0)) - Lr * (0.0 if gun_id == "launcher" else 1)
        lm = [(0, 0, 0), tuple(mag_spot * 0.6), tuple(mag_spot + ax), tuple(mag_spot + ax * 0.2), tuple(mag_spot), tuple(mag_spot * 0.3), (0, 0, 0)]
        rel.append(_ch("grip_L", "translation", tr, lm))
    else:  # 샷건: 한 발씩 장전
        port = np.array((0.0, -0.01, -0.06)) - np.array(sp["L"])
        tt = [0, 0.25, 0.45, 0.65, 0.85, 1.05, 1.25, 1.45, 1.85]
        lm = [(0, 0, 0), tuple(port + (0, -0.04, 0)), tuple(port), tuple(port + (0, -0.04, 0)), tuple(port), tuple(port + (0, -0.04, 0)), tuple(port), tuple(port * 0.5), (0, 0, 0)]
        rel = [_ch("weapon", "rotation", [0, 0.25, 1.45, 1.85], [(0, 0, 0), (-4, -6, -24), (-4, -6, -24), (0, 0, 0)]),
               _ch("weapon", "translation", [0, 0.25, 1.45, 1.85], [(0, 0, 0), (-0.03, -0.02, 0.02), (-0.03, -0.02, 0.02), (0, 0, 0)]),
               _ch("grip_L", "translation", tt, lm)]
    A.append({"name": "reload", "channels": rel})
    # draw: 아래에서 올라오기
    A.append({"name": "draw", "channels": [
        _ch("weapon", "translation", [0, 0.25, 0.45], [(0.04, -0.22, 0.08), (0.0, 0.01, 0.0), (0, 0, 0)]),
        _ch("weapon", "rotation", [0, 0.25, 0.45], [(-45, 10, 25), (3, 0, -2), (0, 0, 0)])]})
    return A

def fp_arms(char_parts, char_id):
    """캐릭터 파츠에서 장갑/소매/팔찌 색을 읽어 1인칭 팔 생성."""
    by = {q.get("n"): q for q in char_parts}
    glove = by["hand_R"]["c"]; sleeve = by["forearm_R"]["c"]
    bracer = by.get("bracer_R"); trim = by.get("bracer_trim_R")
    blade = by.get("arm_blade_R")
    beast_fur = by["neck"]["c"] if "tail_0" in by or "tail" in by else None
    robot = char_id == "staple"
    P = []
    for side, s in (("R", 1), ("L", -1)):
        root = f"arm_{side}"
        P.append(empty((0, 0, 0), root))
        d = (0.27, -0.57, 0.77) if side == "R" else (-0.42, -0.45, 0.78)
        d = np.array(d) / np.linalg.norm(d)
        rot = look_euler(d)
        wrist = d * 0.055   # 손바닥 중심 → 손목
        if side == "R":   # 세로 손잡이를 감싼 손
            P += [rbox([0.03, 0.088, 0.08], (0.027, 0.0, 0.002), glove, b=0.012, n=f"palm_{side}", parent=root),
                  rbox([0.056, 0.07, 0.026], (0.001, -0.004, -0.038), glove, b=0.011, n=f"fingers_{side}", parent=root),
                  rbox([0.052, 0.018, 0.024], (0.001, -0.012, -0.05), glove, b=0.008, n=f"knuckles_{side}", parent=root),
                  cap(0.011, 0.04, (-0.022, 0.03, -0.006), glove, r=(70, 0, -30), n=f"thumb_{side}", parent=root),
                  cap(0.0095, 0.03, (0.012, 0.045, -0.035), glove, r=(85, 0, 0), n=f"trigger_finger_{side}", parent=root)]
        else:             # 아래에서 받치는 손
            P += [rbox([0.062, 0.026, 0.085], (0.0, -0.034, 0.0), glove, b=0.011, n=f"palm_{side}", parent=root),
                  rbox([0.022, 0.05, 0.078], (-0.034, -0.006, -0.004), glove, b=0.009, n=f"fingers_{side}", parent=root),
                  cap(0.011, 0.035, (0.034, -0.01, 0.01), glove, r=(70, 0, 0), n=f"thumb_{side}", parent=root)]
        if beast_fur:
            for i in range(3):
                P.append(cyl(0, 0.006, 0.018, (-0.047 if side == "L" else 0.001 + (i - 1) * 0.016, -0.01, -0.05 - (0.0 if side == "R" else 0)), "#f1ead6", seg=6,
                             r=(-90, 0, 0), n=f"claw_{side}_{i}", parent=root))
        L = 0.42
        P.append(cap(0.036 if not robot else 0.034, L, tuple(wrist), sleeve, r2=0.044, r=rot, o=(0, L / 2, 0), n=f"forearm_{side}", parent=root, m="metal" if robot else None))
        P.append(lathe([(0, 0), (0.04, 0), (0.046, 0.025), (0.0, 0.025)], tuple(wrist + d * 0.01), glove, r=rot, n=f"cuff_{side}", parent=root))
        if bracer:
            P.append(lathe([(0, 0), (0.045, 0), (0.052, 0.12), (0, 0.12)], tuple(wrist + d * 0.03), bracer["c"], r=rot, n=f"bracer_{side}", parent=root, m=bracer.get("m")))
            if trim:
                P.append(cyl(0.054, 0.054, 0.014, tuple(wrist + d * 0.155), trim["c"], r=rot, n=f"bracer_trim_{side}", parent=root, m=trim.get("m")))
        if robot:
            P.append(sph(0.03, tuple(wrist + d * 0.01), "#3a3f47", n=f"wrist_joint_{side}", parent=root, m="metal"))
            P.append(rbox([0.05, 0.012, 0.18], tuple(wrist + d * 0.15 + np.array((0, 0.04, 0))), RED, b=0.005, r=rot, n=f"arm_panel_{side}", parent=root))
        if blade:
            P.append(rbox([0.008, 0.3, 0.04], tuple(wrist + d * 0.15 + np.array((s * 0.045, 0, 0))), blade["c"], b=0.003, r=rot, n=f"arm_blade_{side}", parent=root, m="metal"))
    return P

# ------------------------------------------------------------------ 로비(전신) 대기 모션 + 무기 소켓
def lobby_extras(char_parts):
    from scipy.spatial.transform import Rotation
    by = {q.get("n"): q for q in char_parts}
    hand = by["hand_R"]
    S = hand["s"]["size"][1] / 0.075
    rot = Rotation.align_vectors([[0, -1, 0], [0, 0, 1]], [[0, 0, -1], [0, 1, 0]])[0]
    eul = rot.as_euler("XYZ", degrees=True)
    palm = np.array((0.0, -0.045 * S, 0.0))
    loc = palm - rot.apply(np.array(GRIP_R))
    sock = dict(empty(tuple(loc), "weapon_socket_R", parent="hand_R"), local=True)
    sock["r"] = [round(float(v), 3) for v in eul]
    extra = [sock]
    tr = [0, 1.6, 3.2]
    anim = {"name": "lobby_idle", "channels": [
        _ch("upper_arm_R", "rotation", tr, [(-18, 0, 4), (-20, 2, 4), (-18, 0, 4)]),
        _ch("forearm_R", "rotation", tr, [(-70, 0, 0), (-72, 0, 0), (-70, 0, 0)]),
        _ch("upper_arm_L", "rotation", tr, [(-32, 0, -28), (-34, 0, -29), (-32, 0, -28)]),
        _ch("forearm_L", "rotation", tr, [(-62, 0, -12), (-64, 0, -12), (-62, 0, -12)]),
        _ch("spine", "rotation", tr, [(0, 0, 0), (1.5, 0, 0), (0, 0, 0)]),
        _ch("chest", "rotation", tr, [(0, -6, 0), (1.2, -6, 0), (0, -6, 0)]),
        _ch("head", "rotation", [0, 1.6, 3.2, 4.8, 6.4], [(0, 6, 0), (-2, 14, 0), (0, 6, 0), (2, -4, 0), (0, 6, 0)]),
        _ch("hips", "rotation", tr, [(0, 6, 0), (0, 6, 1), (0, 6, 0)]),
        _ch("thigh_L", "rotation", tr, [(-4, 0, 3), (-4, 0, 3), (-4, 0, 3)]),
        _ch("thigh_R", "rotation", tr, [(3, 0, -2), (3, 0, -2), (3, 0, -2)]),
        _ch("shin_L", "rotation", tr, [(8, 0, 0), (8, 0, 0), (8, 0, 0)]),
    ]}
    return extra, anim
