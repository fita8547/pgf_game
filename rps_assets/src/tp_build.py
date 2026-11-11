"""third_person.glb 클립 12개 생성.
클립: idle_gun, walk, run, strafe_L, strafe_R, back, crouch_idle, crouch_walk, jump, fire, reload, hit
- 이동 클립(walk/run/strafe/back/crouch_walk)은 루프. 끝 키 = 첫 키.
- fire / reload / hit 은 상체(spine 위) 동작 위주지만 하체도 기본 서기 자세로 채움 → 단독 재생도 됨.
  하체 이동과 겹쳐 쓰려면 이 세 클립에서 hips/thigh/shin/foot 트랙을 빼고 재생 (README 참고).
"""
import math, json, os, sys
import numpy as np
import meshlib as M
import tp_anim as T
from tp_anim import REF, SK, BONES, E, I3, R, solve_leg, solve_right, solve_left, clip, ref_parts

SKELS = list(SK.values())
ANK = REF.ankle_h
HIPS_REST = REF.wp["hips"].copy()
LEG_X = {"L": REF.wp["thigh_L"][0], "R": REF.wp["thigh_R"][0]}
GUN_FWD = E(0, 180, 0)          # 총구 -Z → 월드 +Z
CHEST0 = E(0, -24, 0)           # 기본 가슴 월드 회전 (왼어깨를 앞으로 → 왼손이 총 앞을 받칠 수 있음)

# ------------------------------------------------------------------ 몸통
def torso(pose, hips_rot, chest_w, spine_share=0.5, head_w=None):
    """hips 회전이 주어졌을 때 가슴 월드 회전이 chest_w가 되도록 spine/chest 로컬을 나눠 채움."""
    pose["hips"] = hips_rot
    need = hips_rot.inv() * chest_w                     # spine*chest 로컬 합
    rv = need.as_rotvec()
    pose["spine"] = R.from_rotvec(rv * spine_share)
    pose["chest"] = pose["spine"].inv() * need
    hw = head_w or E(0, 0, 0)
    nw = R.from_rotvec((chest_w.as_rotvec() + hw.as_rotvec()) / 2)
    pose["neck"] = chest_w.inv() * nw
    pose["head"] = nw.inv() * hw

# ------------------------------------------------------------------ 팔 (캐시)
_ARM = {}
GRIP_CHEST = None
def base_grip():
    """기본 조준: 손잡이 월드 (-0.06, 어깨 높이 -0.01, 0.30) → 가슴 기준 좌표로 저장."""
    global GRIP_CHEST
    p = {b: I3 for b in BONES}; torso(p, I3, CHEST0)
    W = REF.fk(p)
    g = np.array([-0.06, REF.wp["upper_arm_R"][1] - 0.01, 0.30])
    cp, cr = W["chest"]
    GRIP_CHEST = cr.inv().apply(g - cp)
base_grip()

def support_target(sk, W):
    gp, gr = sk.gun(W); return gp + gr.apply(T.GUN_SUPPORT)

def arms(pose, hips_off, grip_dchest=(0, 0, 0), gun_rot=GUN_FWD, left=None, key=None):
    """grip_dchest: 기본 손잡이 위치에서 가슴 기준 이동량, gun_rot: 총 월드 회전,
    left: None=총 받침 / (target_fn, palm_dir)"""
    ck = key
    if ck and ck in _ARM:
        pose.update(_ARM[ck]); return
    W = REF.fk(pose, hips_off)
    cp, cr = W["chest"]
    grip_w = cp + cr.apply(GRIP_CHEST + np.array(grip_dchest))
    vr, fr = solve_right(REF, pose, hips_off, grip_w, gun_rot)
    tf, pd = left if left else (support_target, ([0, 1, 0], [-0.4, 0, 1]))
    vl, fl = solve_left(SKELS, pose, hips_off, tf, pd, x0=_ARM.get("_x0L"))
    _ARM["_x0L"] = vl
    print(f"  arms {ck}: right err {math.sqrt(fr/1e4)*100:.1f}cm, left {fl:.1f}", file=sys.stderr)
    if ck: _ARM[ck] = {k: pose[k] for k in ("upper_arm_R", "forearm_R", "hand_R", "upper_arm_L", "forearm_L", "hand_L")}

# ------------------------------------------------------------------ 다리
_legx0 = {"L": None, "R": None}
def legs(pose, hips_off, ank_L, ank_R, pitch=(0, 0)):
    for side, a, pt in (("L", ank_L, pitch[0]), ("R", ank_R, pitch[1])):
        v, f = solve_leg(REF, pose, hips_off, side, np.array(a, float), foot_pitch=pt, x0=_legx0[side])
        _legx0[side] = v
        if f > 1.0: print(f"  leg {side} err {math.sqrt(f/1e4)*100:.1f}cm at {a}", file=sys.stderr)

def foot_path(p, stride, lift, sf=0.6):
    """p: 0~1 위상 → (앞뒤 오프셋, 들림, 발끝 각도). 지지 sf 동안 앞→뒤, 나머지 공중에서 뒤→앞."""
    p %= 1.0
    if p < sf:
        q = p / sf
        off = stride / 2 - stride * q
        heel = max(0, (q - 0.8) / 0.2)          # 지지 끝: 뒤꿈치 들림
        return off, 0.035 * heel, 18 * heel
    q = (p - sf) / (1 - sf)
    s = q * q * (3 - 2 * q)
    return -stride / 2 + stride * s, lift * math.sin(math.pi * q), 10 * (1 - q) - 12 * math.sin(math.pi * q) * (q > 0.5)

def ankle(side, fwd=0.0, lat=0.0, up=0.0, base=None):
    bx, bz = base[side] if base else (LEG_X[side] * 1.15, 0.0)
    return (bx + lat, ANK + up, bz + fwd)

# ------------------------------------------------------------------ 클립들
def make_loco(name, T_, n, stride, lift, sf, bob, hips_y, axis="z", reverse=False, lean=0.0, yaw_amp=4.0, base=None, chest_w=None, arm_key="base"):
    keys = []
    chest_w = chest_w or CHEST0
    for i in range(n + 1):
        ph = (i % n) / n
        t = T_ * i / n
        pp = (1 - ph) % 1.0 if reverse else ph
        pose = {}
        hy = hips_y - bob * (0.5 + 0.5 * math.cos(4 * math.pi * pp))
        hx = 0.018 * math.sin(2 * math.pi * pp) * (1 if axis == "z" else 0.3)
        hips_rot = E(lean * 0.4, yaw_amp * math.sin(2 * math.pi * pp) * (1 if axis == "z" else 0.4), 0)
        off = (hx, hy, 0.0)
        torso(pose, hips_rot, chest_w * E(lean, 0, 0) if lean else chest_w)
        a = {}
        for side, ph0 in (("L", 0.0), ("R", 0.5)):
            fo, up, pitch = foot_path(pp + ph0, stride, lift, sf)
            if reverse: pitch = 0
            if axis == "z": a[side] = (ankle(side, fwd=fo, up=up, base=base), pitch)
            else: a[side] = (ankle(side, lat=fo, up=up, base=base), 0)
        legs(pose, off, a["L"][0], a["R"][0], (a["L"][1], a["R"][1]))
        arms(pose, off, key=arm_key)
        keys.append((t, pose, HIPS_REST + np.array(off) - HIPS_REST))
    return clip(name, keys)

def stand_pose(hips_y=-0.03, chest_w=None, base=None):
    pose = {}
    off = (0.0, hips_y, 0.0)
    torso(pose, E(0, -8, 0), chest_w or CHEST0)
    b = base or STANCE
    legs(pose, off, ankle("L", base=b), ankle("R", base=b))
    return pose, off

STANCE = {"L": (0.15, 0.10), "R": (-0.13, -0.08)}       # 기본 서기: 왼발 앞, 오른발 뒤
CROUCH = {"L": (0.17, 0.22), "R": (-0.14, -0.20)}

def idle_gun():
    keys = []
    for t, br in ((0, 0), (1.2, 1), (2.4, 0)):
        pose, off = stand_pose(hips_y=-0.03 - 0.006 * br)
        torso(pose, E(0, -8, 0), CHEST0 * E(1.2 * br, 0, 0))
        arms(pose, off, key="base")
        keys.append((t, pose, np.array(off)))
    return clip("idle_gun", keys)

def crouch_idle():
    keys = []
    for t, br in ((0, 0), (1.4, 1), (2.8, 0)):
        pose = {}; off = (0.0, -0.38 - 0.008 * br, 0.0)
        torso(pose, E(4, -8, 0), CHEST0 * E(1.0 * br, 0, 0))
        legs(pose, off, ankle("L", base=CROUCH), ankle("R", base=CROUCH), (0, 0))
        arms(pose, off, key="base")
        keys.append((t, pose, np.array(off)))
    return clip("crouch_idle", keys)

def jump():
    # (시간, hips y 오프셋, 발목 들림 L/R, 앞뒤 L/R, 발끝 각도)
    seq = [(0.00, -0.03, 0.00, 0.00, 0.10, -0.08, 0),
           (0.10, -0.16, 0.00, 0.00, 0.10, -0.08, 0),      # 웅크림 (도약 준비)
           (0.20, 0.02, 0.03, 0.02, 0.05, -0.05, 25),      # 박차기 (발끝 아래)
           (0.36, 0.00, 0.30, 0.22, 0.12, -0.05, -5),      # 공중: 무릎 당김
           (0.56, 0.00, 0.30, 0.24, 0.10, -0.02, -5),
           (0.74, 0.00, 0.08, 0.06, 0.12, -0.06, -8),      # 착지 준비: 다리 뻗음
           (0.82, -0.17, 0.00, 0.00, 0.12, -0.08, 0),      # 착지 충격
           (1.00, -0.03, 0.00, 0.00, 0.10, -0.08, 0)]
    keys = []
    for t, hy, uL, uR, zL, zR, pt in seq:
        pose = {}; off = (0.0, hy, 0.0)
        torso(pose, E(6 if hy < -0.1 else 0, -8, 0), CHEST0 * E(4 if hy < -0.1 else (-3 if uL > 0.1 else 0), 0, 0))
        legs(pose, off, ankle("L", up=uL, base={"L": (0.15, zL), "R": (-0.13, zR)}), ankle("R", up=uR, base={"L": (0.15, zL), "R": (-0.13, zR)}), (pt, pt))
        arms(pose, off, key="base")
        keys.append((t, pose, np.array(off)))
    return clip("jump", keys)

def upper(name, seq):
    """seq: (시간, 가슴 추가 회전, 머리 추가, 손잡이 이동, 총 추가 회전(총 로컬), 왼손 설정)"""
    keys = []
    for t, dch, dhead, dgrip, dgun, left in seq:
        pose, off = stand_pose()
        cw = CHEST0 * dch
        torso(pose, E(0, -8, 0), cw, head_w=dhead)
        arms(pose, off, grip_dchest=dgrip, gun_rot=GUN_FWD * dgun, left=left, key=f"{name}_{t}")
        keys.append((t, pose, np.array(off)))
    return clip(name, keys)

def fire():
    Z = (0, 0, 0)
    return upper("fire", [(0.0, I3, None, Z, I3, None),
                          (0.04, E(-3.5, 1.5, 0), E(-2, 0, 0), (0, 0.012, -0.035), E(7, 0, 1.5), None),
                          (0.12, E(-1.2, 0.5, 0), None, (0, 0.004, -0.012), E(2.5, 0, 0.5), None),
                          (0.25, I3, None, Z, I3, None)])

def hit():
    Z = (0, 0, 0)
    return upper("hit", [(0.0, I3, None, Z, I3, None),
                         (0.07, E(-11, 9, -4), E(-14, 10, 0), (0.02, 0.03, -0.05), E(9, -6, 6), None),
                         (0.18, E(-5, 4, -2), E(-6, 4, 0), (0.01, 0.012, -0.02), E(4, -2, 2), None),
                         (0.35, I3, None, Z, I3, None)])

def reload():
    Z = (0, 0, 0)
    tilt = E(-14, 0, 24)          # 총 로컬: 총구 아래 + 왼쪽으로 눕힘
    gd = (0.05, -0.07, -0.05)     # 손잡이를 몸 쪽·아래로
    def at_gun(pt, extra=(0, 0, 0)):
        return lambda sk, W: sk.gun(W)[0] + sk.gun(W)[1].apply(pt) + np.array(extra)
    def at_body(dx, dy, dz):     # 허리 파우치 (hips 기준)
        return lambda sk, W: W["hips"][0] + W["hips"][1].apply(np.array([dx, dy, dz]) * sk.S)
    mag = (at_gun(T.GUN_MAG), ([0.4, 0.9, 0.2], [-0.3, 0.2, 1]))
    mag_out = (at_gun(T.GUN_MAG, (0.02, -0.16, -0.02)), ([0.4, 0.9, 0.2], [-0.3, 0.2, 1]))
    pouch = (at_body(0.17, 0.02, 0.10), ([-1, 0, 0.2], [0, -1, 0.3]))
    slap = (at_gun(np.array([0.025, 0.07, -0.02])), ([-0.8, -0.5, 0], [0, 0.3, 1]))
    return upper("reload", [(0.0, I3, None, Z, I3, None),
                            (0.3, E(2, 4, 0), E(6, 6, 0), gd, tilt, mag),
                            (0.55, E(3, 5, 0), E(10, 8, 0), gd, tilt, mag_out),
                            (0.9, E(3, 8, 0), E(12, 10, 0), gd, tilt, pouch),
                            (1.25, E(3, 5, 0), E(10, 8, 0), gd, tilt, mag),
                            (1.55, E(1, 3, 0), E(4, 4, 0), (0.03, -0.04, -0.03), E(-6, 0, 12), slap),
                            (1.85, I3, None, Z, I3, None)])

def build(out_path):
    clips = []
    print("idle_gun", file=sys.stderr); clips.append(idle_gun())
    print("walk", file=sys.stderr)
    clips.append(make_loco("walk", 1.0, 16, 0.52, 0.10, 0.6, 0.022, -0.035, base=None))
    print("run", file=sys.stderr)
    clips.append(make_loco("run", 0.64, 16, 0.95, 0.20, 0.42, 0.04, -0.07, lean=9.0, yaw_amp=7.0, arm_key="run"))
    print("strafe", file=sys.stderr)
    SB = {"L": (0.15, 0.02), "R": (-0.15, -0.02)}
    clips.append(make_loco("strafe_L", 0.9, 16, 0.22, 0.08, 0.6, 0.015, -0.035, axis="x", base=SB))
    clips.append(make_loco("strafe_R", 0.9, 16, 0.22, 0.08, 0.6, 0.015, -0.035, axis="x", reverse=True, base=SB))
    print("back", file=sys.stderr)
    clips.append(make_loco("back", 1.1, 16, 0.42, 0.09, 0.62, 0.02, -0.04, reverse=True))
    print("crouch", file=sys.stderr)
    clips.append(crouch_idle())
    clips.append(make_loco("crouch_walk", 1.15, 16, 0.38, 0.07, 0.62, 0.012, -0.38, yaw_amp=3.0, base={"L": (0.17, 0.05), "R": (-0.15, -0.03)}))
    print("jump", file=sys.stderr); clips.append(jump())
    print("fire", file=sys.stderr); clips.append(fire())
    print("reload", file=sys.stderr); clips.append(reload())
    print("hit", file=sys.stderr); clips.append(hit())
    # hips 위치 값은 기준 골격 레스트 + 오프셋 (write_glb가 레스트를 더함)
    M.write_glb("third_person", ref_parts(), out_path, animations=clips)
    # 엔진용 메타 (asset.extras) 추가
    import struct
    data = open(out_path, "rb").read()
    jl = struct.unpack("<I", data[12:16])[0]
    js = json.loads(data[20:20 + jl])
    js["asset"]["extras"] = {"ref_skeleton": T.REF_ID, "hips_rest": [round(float(v), 5) for v in HIPS_REST],
                             "note": "hips.position = own_rest + (value - hips_rest) * (own_rest.y / hips_rest.y). Rotation tracks are shared as-is."}
    js_b = json.dumps(js, separators=(",", ":")).encode()
    while len(js_b) % 4: js_b += b" "
    bin_ = data[20 + jl:]
    with open(out_path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js_b) + len(bin_)))
        f.write(struct.pack("<II", len(js_b), 0x4E4F534A)); f.write(js_b); f.write(bin_)
    return [c["name"] for c in clips]

if __name__ == "__main__":
    print(build(sys.argv[1] if len(sys.argv) > 1 else "third_person.glb"))
