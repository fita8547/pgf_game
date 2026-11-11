"""3인칭 공용 애니메이션 (glb/anims/third_person.glb).

12명 모두 뼈 이름·계층이 같고 레스트 회전이 0이라 회전 키만으로 공용 사용.
위치 키는 hips 하나만 (값 = 기준 골격의 hips 레스트 위치 + 오프셋 → 엔진에서 '내 hips 레스트 - 기준 레스트'를 더해 씀).

포즈 계산 방식
- 다리: 발목 목표 위치(걸음 궤적)에서 2관절 IK → thigh / shin / foot 회전
- 팔: 총 목표(손잡이 위치 + 총 방향)에서 오른팔 IK, 왼손은 총 앞쪽 받침점으로 IK.
  왼손은 12명 골격 전체에 대해 오차 평균이 최소가 되도록 풂 (어깨 너비가 캐릭터마다 달라서).
총 기준: hand_R/weapon_socket_R에 붙은 총 (원점 = 손잡이, 총구 -Z).
"""
import math
import numpy as np
from scipy.optimize import minimize
from scipy.spatial.transform import Rotation as R
import chars_hq, fp

BONES = ["hips", "spine", "chest", "neck", "head", "upper_arm_L", "forearm_L", "hand_L", "upper_arm_R", "forearm_R", "hand_R",
         "thigh_L", "shin_L", "foot_L", "thigh_R", "shin_R", "foot_R"]
PARENT = {"spine": "hips", "chest": "spine", "neck": "chest", "head": "neck", "upper_arm_L": "chest", "forearm_L": "upper_arm_L",
          "hand_L": "forearm_L", "upper_arm_R": "chest", "forearm_R": "upper_arm_R", "hand_R": "forearm_R",
          "thigh_L": "hips", "shin_L": "thigh_L", "foot_L": "shin_L", "thigh_R": "hips", "shin_R": "thigh_R", "foot_R": "shin_R"}
REF_ID = "scroll"          # 기준 골격 (중간 체격 인간 남)
GUN_SUPPORT = np.array([0.0, -0.05, -0.23])   # 왼손바닥이 받칠 총 로컬 지점 (총 7종 절충: 소총·SMG·샷건 손잡이 앞)
GUN_MAG = np.array([0.0, -0.13, -0.07])       # 탄창 위치 (재장전 때 왼손)
I3 = R.identity()

class Skel:
    def __init__(self, cid, parts):
        by = {q.get("n"): q for q in parts}
        self.id = cid
        self.wp = {b: np.array(by[b]["p"], float) for b in BONES}
        self.loc = {b: self.wp[b] - (self.wp[PARENT[b]] if b in PARENT else 0) for b in BONES}
        sock = fp.lobby_extras(parts)[0][0]
        self.sock_t = np.array(sock["p"], float)
        self.sock_r = R.from_euler("XYZ", sock["r"], degrees=True)
        S = by["hand_R"]["s"]["size"][1] / 0.075
        self.palm_L = np.array([0.0, -0.045 * S, 0.0])     # hand_L 피벗(손목) → 손바닥 중심
        self.ankle_h = self.wp["foot_L"][1]
        self.S = S

    def fk(self, pose, hips_off=(0, 0, 0)):
        """pose: {뼈: Rotation} → {뼈: (월드 위치, 월드 회전)}"""
        W = {}
        for b in BONES:
            r = pose.get(b, I3)
            t = self.loc[b] + (np.array(hips_off) if b == "hips" else 0)
            if b in PARENT:
                pp, pr = W[PARENT[b]]
                W[b] = (pp + pr.apply(t), pr * r)
            else:
                W[b] = (t, r)
        return W

    def gun(self, W):
        hp, hr = W["hand_R"]
        return hp + hr.apply(self.sock_t), hr * self.sock_r     # 총 원점(손잡이), 총 회전

def load_skels():
    out = {}
    for c in chars_hq.CHARS:
        out[c[0]] = Skel(c[0], c[6]())
    return out

SK = load_skels()
REF = SK[REF_ID]

def E(x=0, y=0, z=0): return R.from_euler("XYZ", [x, y, z], degrees=True)

# ------------------------------------------------------------------ 다리 IK
def solve_leg(sk, pose, hips_off, side, ankle_target, foot_pitch=0.0, splay=0.0, x0=None):
    """발목 월드 목표 → thigh(x,z) + shin(x). foot은 발바닥이 수평(+foot_pitch)이 되게."""
    th, sh, ft = f"thigh_{side}", f"shin_{side}", f"foot_{side}"
    def f(v):
        p = dict(pose); p[th] = E(v[0], splay, v[1]); p[sh] = E(v[2])
        W = sk.fk(p, hips_off)
        err = W[ft][0] - ankle_target
        return 1e4 * err.dot(err) + 1e-4 * (v[1] ** 2) + (1e-2 * max(0, -v[2]) ** 2)   # 무릎은 앞으로만 굽힘
    x0 = x0 if x0 is not None else [-10, 0, 20]
    best = None
    for st in (x0, [-40, 0, 60], [10, 0, 10], [-70, 0, 110]):
        r = minimize(f, st, method="Nelder-Mead", options=dict(xatol=1e-4, fatol=1e-10, maxiter=4000))
        if best is None or r.fun < best.fun: best = r
    v = best.x
    pose[th] = E(v[0], splay, v[1]); pose[sh] = E(v[2])
    W = sk.fk(pose, hips_off)
    # 발: 월드에서 수평 → 로컬 = (부모 월드)^-1 * 원하는 월드 (요는 hips를 따라감)
    yaw = W["hips"][1].as_euler("YXZ", degrees=True)[0]
    want = R.from_euler("YXZ", [yaw, foot_pitch, 0], degrees=True)
    pose[ft] = W[sh][1].inv() * want
    return list(v), best.fun

# ------------------------------------------------------------------ 팔 IK
def gun_target(sk, W, grip_chest, gun_rot_world):
    """총 손잡이 위치는 가슴 기준(몸통과 같이 움직임), 방향은 월드 기준."""
    cp, cr = W["chest"]
    return cp + cr.apply(grip_chest), gun_rot_world

def solve_right(sk, pose, hips_off, grip_w, gun_rw, x0=None):
    """오른팔: upper(3) + forearm(x) 최적화, hand 회전은 총 방향을 맞추도록 계산."""
    def apply(v):
        p = dict(pose); p["upper_arm_R"] = E(v[0], v[1], v[2]); p["forearm_R"] = E(v[3], 0, 0)
        W = sk.fk(p)
        # hand 월드 회전 = gun_rw * sock_r^-1
        want_h = gun_rw * sk.sock_r.inv()
        p["hand_R"] = W["forearm_R"][1].inv() * want_h
        return p
    def f(v):
        p = apply(v); W = sk.fk(p, hips_off); gp, _ = sk.gun(W)
        e = gp - grip_w
        # 손목 꺾임이 너무 크면 벌점 (자연스러운 팔)
        bend = p["hand_R"].magnitude()
        return (1e4 * e.dot(e) + 0.02 * max(0, bend - math.radians(35)) ** 2 + 1e-5 * (v[1] ** 2)
                + 1.0 * max(0, v[3]) ** 2 + 0.2 * max(0, v[0] - 10) ** 2)
    best = None
    for st in ([x0] if x0 else []) + [[-50, 0, 15, -60], [-30, 20, 30, -80], [-70, -10, 10, -40]]:
        r = minimize(f, st, method="Nelder-Mead", options=dict(xatol=1e-4, fatol=1e-10, maxiter=6000))
        if best is None or r.fun < best.fun: best = r
    p = apply(best.x)
    pose.update({k: p[k] for k in ("upper_arm_R", "forearm_R", "hand_R")})
    return list(best.x), best.fun

def solve_left(skels, pose, hips_off, target_fn, palm_dir, x0=None):
    """왼팔: 모든 골격에서 왼손바닥이 target_fn(sk, W)에 오도록 평균 오차 최소.
    palm_dir: (손바닥 노멀 월드 방향, 손가락 월드 방향) — hand_L 회전으로 맞춤."""
    n_w, f_w = np.array(palm_dir[0], float), np.array(palm_dir[1], float)
    f_w = f_w - n_w * f_w.dot(n_w); f_w /= np.linalg.norm(f_w)
    # hand_L 로컬: 손가락 = -Y, 손바닥 노멀 = -X (왼손은 몸 쪽 = -X 가 손바닥)
    want_h = R.align_vectors([n_w, f_w], [[-1, 0, 0], [0, -1, 0]])[0]
    def apply(v):
        p = dict(pose); p["upper_arm_L"] = E(v[0], v[1], v[2]); p["forearm_L"] = E(v[3], 0, v[4])
        return p
    def f(v):
        p = apply(v); tot = 0
        for sk in skels:
            W = sk.fk(p, hips_off)
            p2 = dict(p); p2["hand_L"] = W["forearm_L"][1].inv() * want_h
            W = sk.fk(p2, hips_off)
            hp, hr = W["hand_L"]
            palm = hp + hr.apply(sk.palm_L)
            e = palm - target_fn(sk, W)
            tot += e.dot(e) * (3.0 if sk is REF else 1.0)
        bend = (W["forearm_L"][1].inv() * want_h).magnitude()
        # 팔꿈치는 앞(-X)으로만 굽힘, 위팔은 뒤로 젖히지 않음
        return (1e4 * tot / (len(skels) + 2) + 0.05 * max(0, bend - math.radians(45)) ** 2
                + 1.0 * max(0, v[3]) ** 2 + 0.2 * max(0, v[0] - 10) ** 2 + 2e-4 * v[4] ** 2)
    best = None
    for st in ([x0] if x0 else []) + [[-60, 0, -30, -40, 0], [-40, 20, -40, -70, 0], [-80, -20, -20, -20, 0], [-70, -30, -45, -50, 0]]:
        r = minimize(f, st, method="Nelder-Mead", options=dict(xatol=1e-4, fatol=1e-10, maxiter=8000))
        if best is None or r.fun < best.fun: best = r
    p = apply(best.x)
    W = REF.fk(p, hips_off)
    p["hand_L"] = W["forearm_L"][1].inv() * want_h
    pose.update({k: p[k] for k in ("upper_arm_L", "forearm_L", "hand_L")})
    return list(best.x), best.fun

# ------------------------------------------------------------------ 내보내기
def ref_parts():
    """기준 골격: 뼈 노드만 (빈 노드) + weapon_socket_R. 미리보기용 마네킹 메시는 넣지 않음."""
    from parts import empty
    by = {q.get("n"): q for q in chars_hq_ref()}
    P = []
    for b in BONES:
        q = empty(by[b]["p"], b, parent=PARENT.get(b))
        P.append(q)
    sock = fp.lobby_extras(chars_hq_ref())[0][0]
    P.append(sock)
    return P

_REF_PARTS = None
def chars_hq_ref():
    global _REF_PARTS
    if _REF_PARTS is None:
        _REF_PARTS = [c for c in chars_hq.CHARS if c[0] == REF_ID][0][6]()
    return _REF_PARTS

def clip(name, keys):
    """keys: [(시간, pose{뼈: Rotation}, hips_off)] → write_glb 애니메이션 dict.
    회전은 오일러(도)로 넘김(write_glb가 쿼터니언 변환 + 부호 연속 처리)."""
    times = [k[0] for k in keys]
    ch = []
    for b in BONES:
        vals = [list(k[1].get(b, I3).as_euler("XYZ", degrees=True)) for k in keys]
        if all(np.allclose(v, 0, atol=1e-3) for v in vals):
            vals = [[0, 0, 0]] * len(keys)      # 그래도 넣어 둠: 다른 클립에서 바뀐 값을 0으로 돌려놓기 위해
        ch.append({"node": b, "path": "rotation", "times": times, "values": [[round(x, 3) for x in v] for v in vals]})
    ch.append({"node": "hips", "path": "translation", "times": times, "values": [[round(float(x), 4) for x in k[2]] for k in keys]})
    return {"name": name, "channels": ch}
