"""RPS 게임용 로우폴리 모델 정의 + GLB 내보내기.

좌표계: Y-up, 미터 단위.
- 총: 총구가 -Z 방향, 원점은 손잡이 윗부분(쥐는 위치).
- 캐릭터: 발바닥 y=0, 정면 +Z, 키 약 1.4~1.75m.
회전값은 도(degree), 오일러 순서 XYZ (Three.js 기본값과 동일).
"""
import json, math, struct, os
import numpy as np

# ---------- 프리미티브 헬퍼 ----------
def _part(t, s, p, c, r, n, a, sc):
    d = {"t": t, "s": list(s), "p": [round(v, 5) for v in p], "r": [round(v, 3) for v in r], "c": c}
    if n: d["n"] = n
    if a is not None: d["a"] = a          # 투명도 (0~1)
    if sc: d["sc"] = list(sc)             # 비균등 스케일
    return d

def box(s, p, c, r=(0, 0, 0), n=None, a=None, sc=None):
    return _part("box", s, p, c, r, n, a, sc)

def cyl(rt, rb, h, p, c, r=(0, 0, 0), seg=12, n=None, a=None, sc=None):
    return _part("cyl", [rt, rb, h, seg], p, c, r, n, a, sc)

def sph(rad, p, c, ws=10, hs=7, r=(0, 0, 0), n=None, a=None, sc=None):
    return _part("sph", [rad, ws, hs], p, c, r, n, a, sc)

def ring(R, t, p, c, seg=12, plane="xz", a0=0, a1=360, w=None, n="ring", a=None):
    """박스 조각으로 만든 고리/호. plane: xz(바닥에 누움), xy(정면을 봄), yz(옆을 봄)."""
    out, span, w = [], a1 - a0, w or t
    L = 2 * R * math.sin(math.radians(span / seg) / 2) * 1.08
    for i in range(seg):
        d = a0 + span * (i + 0.5) / seg
        th = math.radians(d)
        cs, sn = R * math.cos(th), R * math.sin(th)
        if plane == "xz": q = box([t, w, L], (p[0] + cs, p[1], p[2] + sn), c, r=(0, -d, 0), n=f"{n}_{i}", a=a)
        elif plane == "xy": q = box([t, L, w], (p[0] + cs, p[1] + sn, p[2]), c, r=(0, 0, d), n=f"{n}_{i}", a=a)
        else: q = box([w, L, t], (p[0], p[1] + sn, p[2] + cs), c, r=(-d, 0, 0), n=f"{n}_{i}", a=a)
        out.append(q)
    return out

def dome(R, p, c, layers=4, seg=12, n="dome", a=None):
    """원뿔대를 쌓은 로우폴리 반구."""
    out = []
    for k in range(layers):
        t0, t1 = math.radians(90 * k / layers), math.radians(90 * (k + 1) / layers)
        rb, rt = R * math.cos(t0), R * math.cos(t1) if k < layers - 1 else 0.0
        y0, y1 = R * math.sin(t0), R * math.sin(t1)
        out.append(cyl(rt, rb, y1 - y0, (p[0], p[1] + (y0 + y1) / 2, p[2]), c, seg=seg, n=f"{n}_{k}", a=a))
    return out

Z = (90, 0, 0)  # Y축 실린더를 Z축으로 눕힘 (윗면 → +Z)

# ---------- 팔레트 ----------
GM, BK, SV, WD, GR, OR = "#3b4048", "#202328", "#b9bfc7", "#8b5a2b", "#5a6b3c", "#ff8a2a"
METALS = {GM, BK, SV, "#c9ced6", "#8e959e"}

# ---------- 총기 ----------
def pistol():
    return [
        box([0.032, 0.034, 0.19], (0, 0.045, -0.055), BK, n="slide"),
        box([0.034, 0.008, 0.05], (0, 0.045, 0.012), OR, n="stripe"),
        box([0.03, 0.025, 0.17], (0, 0.016, -0.045), GM, n="frame"),
        box([0.03, 0.11, 0.045], (0, -0.045, 0.02), GM, r=(-12, 0, 0), n="grip"),
        cyl(0.008, 0.008, 0.02, (0, 0.045, -0.155), BK, r=Z, n="muzzle"),
        box([0.006, 0.006, 0.045], (0, -0.006, -0.035), GM, n="trigger_guard"),
        box([0.004, 0.018, 0.006], (0, 0.0, -0.028), BK, n="trigger"),
        box([0.006, 0.007, 0.008], (0, 0.065, -0.14), BK, n="front_sight"),
        box([0.018, 0.007, 0.008], (0, 0.065, 0.03), BK, n="rear_sight"),
    ]

def revolver():
    return [
        box([0.03, 0.045, 0.085], (0, 0.03, -0.02), SV, n="frame"),
        cyl(0.023, 0.023, 0.042, (0, 0.03, -0.02), GM, r=Z, seg=6, n="cylinder"),
        cyl(0.009, 0.009, 0.16, (0, 0.045, -0.14), SV, r=Z, n="barrel"),
        box([0.014, 0.012, 0.14], (0, 0.031, -0.13), SV, n="underlug"),
        box([0.03, 0.10, 0.04], (0, -0.035, 0.04), WD, r=(-18, 0, 0), n="grip"),
        box([0.008, 0.02, 0.012], (0, 0.06, 0.025), GM, n="hammer"),
        box([0.006, 0.006, 0.04], (0, -0.005, -0.01), SV, n="trigger_guard"),
        box([0.004, 0.012, 0.012], (0, 0.072, -0.21), OR, n="front_sight"),
    ]

def smg():
    return [
        box([0.045, 0.07, 0.28], (0, 0.04, -0.05), BK, n="receiver"),
        box([0.047, 0.012, 0.09], (0, 0.03, -0.02), OR, n="stripe"),
        cyl(0.018, 0.018, 0.10, (0, 0.045, -0.24), GM, r=Z, n="shroud"),
        cyl(0.009, 0.009, 0.04, (0, 0.045, -0.31), BK, r=Z, n="muzzle"),
        box([0.035, 0.11, 0.045], (0, -0.04, 0.035), BK, r=(-10, 0, 0), n="grip"),
        box([0.025, 0.16, 0.035], (0, -0.07, -0.10), GM, n="magazine"),
        box([0.02, 0.012, 0.13], (0, 0.081, -0.05), GM, n="rail"),
        box([0.018, 0.03, 0.17], (0, 0.045, 0.17), GM, n="stock_bar"),
        box([0.04, 0.085, 0.016], (0, 0.025, 0.255), BK, n="buttplate"),
        box([0.006, 0.006, 0.04], (0, -0.002, -0.005), GM, n="trigger_guard"),
    ]

def rifle():
    return [
        box([0.05, 0.08, 0.36], (0, 0.04, -0.05), GR, n="receiver"),
        box([0.055, 0.06, 0.28], (0, 0.045, -0.37), BK, n="handguard"),
        box([0.057, 0.062, 0.03], (0, 0.045, -0.47), OR, n="band"),
        cyl(0.01, 0.01, 0.18, (0, 0.05, -0.60), BK, r=Z, n="barrel"),
        cyl(0.016, 0.016, 0.05, (0, 0.05, -0.71), GM, r=Z, seg=8, n="muzzle"),
        box([0.03, 0.17, 0.06], (0, -0.07, -0.13), GM, r=(15, 0, 0), n="magazine"),
        box([0.035, 0.11, 0.045], (0, -0.04, 0.06), BK, r=(-15, 0, 0), n="grip"),
        box([0.045, 0.09, 0.24], (0, 0.02, 0.24), GR, n="stock"),
        box([0.047, 0.11, 0.02], (0, 0.01, 0.37), BK, n="buttpad"),
        box([0.025, 0.012, 0.30], (0, 0.086, -0.10), BK, n="rail"),
        cyl(0.018, 0.018, 0.16, (0, 0.118, -0.06), BK, r=Z, n="scope"),
        cyl(0.022, 0.022, 0.02, (0, 0.118, -0.145), OR, r=Z, n="scope_lens"),
        box([0.012, 0.02, 0.012], (0, 0.097, -0.11), BK, n="mount_f"),
        box([0.012, 0.02, 0.012], (0, 0.097, -0.01), BK, n="mount_r"),
        box([0.006, 0.006, 0.045], (0, -0.006, 0.025), BK, n="trigger_guard"),
    ]

def shotgun():
    return [
        box([0.05, 0.07, 0.22], (0, 0.04, 0.0), GM, n="receiver"),
        cyl(0.014, 0.014, 0.50, (0, 0.06, -0.36), BK, r=Z, n="barrel"),
        cyl(0.012, 0.012, 0.42, (0, 0.025, -0.32), BK, r=Z, n="tube_mag"),
        box([0.056, 0.045, 0.14], (0, 0.025, -0.28), WD, n="pump"),
        box([0.058, 0.01, 0.02], (0, 0.025, -0.33), OR, n="pump_grip_line"),
        box([0.05, 0.10, 0.30], (0, -0.015, 0.25), WD, r=(8, 0, 0), n="stock"),
        box([0.052, 0.115, 0.02], (0, -0.035, 0.40), BK, r=(8, 0, 0), n="buttpad"),
        box([0.006, 0.006, 0.05], (0, -0.002, 0.02), GM, n="trigger_guard"),
        sph(0.005, (0, 0.077, -0.6), OR, ws=6, hs=4, n="bead_sight"),
    ]

def sniper():
    return [
        box([0.05, 0.07, 0.30], (0, 0.04, 0.0), GM, n="receiver"),
        box([0.06, 0.05, 0.40], (0, 0.01, -0.32), GR, n="forestock"),
        cyl(0.011, 0.011, 0.50, (0, 0.05, -0.62), BK, r=Z, n="barrel"),
        box([0.036, 0.03, 0.06], (0, 0.05, -0.89), BK, n="muzzle_brake"),
        box([0.05, 0.12, 0.32], (0, 0.0, 0.31), GR, n="stock"),
        box([0.04, 0.025, 0.14], (0, 0.072, 0.30), BK, n="cheek_rest"),
        box([0.052, 0.14, 0.02], (0, -0.005, 0.48), BK, n="buttpad"),
        box([0.035, 0.10, 0.045], (0, -0.05, 0.13), BK, r=(-15, 0, 0), n="grip"),
        box([0.03, 0.06, 0.08], (0, -0.02, 0.02), GM, n="magazine"),
        cyl(0.022, 0.022, 0.30, (0, 0.125, -0.02), BK, r=Z, n="scope"),
        cyl(0.032, 0.032, 0.06, (0, 0.125, -0.19), BK, r=Z, n="scope_objective"),
        cyl(0.03, 0.03, 0.006, (0, 0.125, -0.222), OR, r=Z, n="scope_lens"),
        cyl(0.026, 0.026, 0.05, (0, 0.125, 0.15), BK, r=Z, n="scope_eyepiece"),
        box([0.014, 0.04, 0.016], (0, 0.09, -0.09), GM, n="mount_f"),
        box([0.014, 0.04, 0.016], (0, 0.09, 0.06), GM, n="mount_r"),
        cyl(0.005, 0.005, 0.05, (0.045, 0.045, 0.08), SV, r=(0, 0, 90), n="bolt"),
        sph(0.011, (0.072, 0.045, 0.08), SV, ws=8, hs=6, n="bolt_knob"),
        cyl(0.006, 0.006, 0.22, (-0.045, -0.09, -0.45), GM, r=(0, 0, -12), seg=6, n="bipod_L"),
        cyl(0.006, 0.006, 0.22, (0.045, -0.09, -0.45), GM, r=(0, 0, 12), seg=6, n="bipod_R"),
    ]

def launcher():
    return [
        cyl(0.055, 0.055, 1.0, (0, 0.08, -0.2), GR, r=Z, seg=16, n="tube"),
        cyl(0.060, 0.076, 0.08, (0, 0.08, -0.72), BK, r=Z, seg=16, n="front_bell"),
        cyl(0.076, 0.060, 0.08, (0, 0.08, 0.32), BK, r=Z, seg=16, n="rear_bell"),
        cyl(0.0, 0.05, 0.14, (0, 0.08, -0.80), OR, r=(-90, 0, 0), seg=12, n="warhead"),
        cyl(0.057, 0.057, 0.04, (0, 0.08, -0.5), OR, r=Z, seg=16, n="band_f"),
        cyl(0.057, 0.057, 0.04, (0, 0.08, 0.1), OR, r=Z, seg=16, n="band_r"),
        box([0.035, 0.11, 0.045], (0, -0.03, 0.0), BK, r=(-10, 0, 0), n="grip"),
        box([0.035, 0.10, 0.045], (0, -0.02, -0.32), BK, n="front_grip"),
        box([0.02, 0.07, 0.06], (-0.07, 0.13, -0.25), GM, n="sight_mount"),
        box([0.03, 0.035, 0.08], (-0.07, 0.17, -0.25), OR, n="sight"),
        box([0.006, 0.006, 0.05], (0, 0.02, -0.03), GM, n="trigger_guard"),
    ]

GUNS = [
    ("pistol",   "피스톨 P9",       "권총",     pistol),
    ("revolver", "리볼버 R6",       "권총",     revolver),
    ("smg",      "SMG 버즈",        "기관단총", smg),
    ("rifle",    "돌격소총 AR-K",   "소총",     rifle),
    ("shotgun",  "펌프 샷건 M12",   "산탄총",   shotgun),
    ("sniper",   "저격소총 LR-50",  "저격총",   sniper),
    ("launcher", "로켓 런처 RX",    "중화기",   launcher),
]

# ---------- 캐릭터 ----------
def humanoid(body, dark, skin, leg_h=0.6, leg_w=0.16, torso=(0.5, 0.55, 0.32),
             arm_len=0.5, arm_w=0.13, hand_r=0.08):
    tw, th, td = torso
    parts = []
    for side, sx in (("L", 1), ("R", -1)):
        x = sx * (tw * 0.24)
        parts += [
            box([leg_w, leg_h, leg_w + 0.02], (x, leg_h / 2, 0), dark, n=f"leg_{side}"),
            box([leg_w + 0.02, 0.08, leg_w + 0.1], (x, 0.04, 0.04), dark, n=f"foot_{side}"),
        ]
    hip = leg_h
    parts.append(box([tw * 0.9, 0.14, td * 0.9], (0, hip + 0.07, 0), dark, n="pelvis"))
    top = hip + 0.14 + th
    for side, sx in (("L", 1), ("R", -1)):
        ax = sx * (tw / 2 + arm_w / 2 + 0.01)
        parts += [
            box([arm_w, arm_len, arm_w + 0.01], (ax, top - arm_len / 2 - 0.02, 0), body, n=f"arm_{side}"),
            sph(hand_r, (ax, top - arm_len - 0.02 - hand_r * 0.6, 0), skin, ws=8, hs=6, n=f"hand_{side}"),
        ]
    return parts, hip, top

def boulder():
    body, dark, stone = "#7d8288", "#4b4f55", "#9a9c98"
    parts, hip, top = humanoid(body, dark, stone, leg_h=0.55, leg_w=0.22, torso=(0.7, 0.6, 0.45),
                               arm_len=0.55, arm_w=0.2, hand_r=0.13)
    torso_y = hip + 0.14 + 0.3
    parts.insert(0, box([0.7, 0.6, 0.45], (0, torso_y, 0), body, n="torso"))
    parts += [
        box([0.4, 0.3, 0.04], (0, torso_y + 0.05, 0.23), OR, n="chest_plate"),
        box([0.28, 0.12, 0.34], (0.42, top - 0.02, 0), dark, r=(0, 0, -15), n="pauldron_L"),
        box([0.28, 0.12, 0.34], (-0.42, top - 0.02, 0), dark, r=(0, 0, 15), n="pauldron_R"),
        sph(0.21, (0, top + 0.17, 0), stone, ws=6, hs=4, n="head"),
        box([0.28, 0.06, 0.05], (0, top + 0.19, 0.17), OR, n="visor"),
    ]
    return parts

def pebble():
    body, dark, stone = "#a3a49c", "#5d5f5a", "#b8b8b0"
    parts, hip, top = humanoid(body, dark, stone, leg_h=0.5, leg_w=0.14, torso=(0.42, 0.46, 0.3),
                               arm_len=0.44, arm_w=0.11, hand_r=0.075)
    torso_y = hip + 0.14 + 0.23
    parts.insert(0, box([0.42, 0.46, 0.3], (0, torso_y, 0), body, n="torso"))
    parts += [
        box([0.44, 0.08, 0.32], (0, top - 0.05, 0), OR, n="scarf"),
        box([0.1, 0.25, 0.03], (0.12, top - 0.2, 0.17), OR, r=(0, 0, 8), n="scarf_tail"),
        box([0.3, 0.06, 0.32], (0, hip + 0.2, 0), dark, n="belt"),
        sph(0.17, (0, top + 0.15, 0), stone, ws=7, hs=5, n="head"),
        cyl(0.045, 0.045, 0.05, (0.06, top + 0.17, 0.15), BK, r=Z, seg=8, n="goggle_L"),
        cyl(0.045, 0.045, 0.05, (-0.06, top + 0.17, 0.15), BK, r=Z, seg=8, n="goggle_R"),
        box([0.33, 0.025, 0.2], (0, top + 0.17, 0.02), "#2b2d2a", n="goggle_strap"),
    ]
    return parts

def origami():
    paper, fold, blue = "#efe9dc", "#d3cbb9", "#2f6fd6"
    parts, hip, top = humanoid(paper, fold, paper, leg_h=0.62, leg_w=0.13, torso=(0.44, 0.52, 0.28),
                               arm_len=0.5, arm_w=0.1, hand_r=0.06)
    torso_y = hip + 0.14 + 0.26
    parts.insert(0, cyl(0.24, 0.16, 0.52, (0, torso_y, 0), paper, seg=4, r=(0, 45, 0), n="torso"))
    parts += [
        box([0.02, 0.4, 0.02], (0, torso_y, 0.2), blue, r=(0, 45, 0), n="fold_line"),
        box([0.6, 0.02, 0.3], (0.25, top - 0.15, -0.2), fold, r=(20, 0, -25), n="wing_L"),
        box([0.6, 0.02, 0.3], (-0.25, top - 0.15, -0.2), fold, r=(20, 0, 25), n="wing_R"),
        cyl(0.0, 0.2, 0.34, (0, top + 0.19, 0), paper, seg=4, r=(0, 45, 0), n="head"),
        box([0.18, 0.04, 0.03], (0, top + 0.12, 0.11), blue, n="eye_slit"),
    ]
    return parts

def scroll():
    paper, roll, ink = "#e8dcc0", "#7a4e2c", "#24407a"
    parts, hip, top = humanoid(paper, roll, paper, leg_h=0.55, leg_w=0.17, torso=(0.6, 0.6, 0.6),
                               arm_len=0.5, arm_w=0.14, hand_r=0.085)
    torso_y = hip + 0.14 + 0.3
    parts.insert(0, cyl(0.3, 0.3, 0.6, (0, torso_y, 0), paper, seg=14, n="torso"))
    parts += [
        cyl(0.33, 0.33, 0.07, (0, torso_y + 0.32, 0), roll, seg=14, n="roll_top"),
        cyl(0.33, 0.33, 0.07, (0, torso_y - 0.32, 0), roll, seg=14, n="roll_bottom"),
        box([0.3, 0.04, 0.02], (0, torso_y + 0.1, 0.3), ink, n="ink_line_1"),
        box([0.22, 0.04, 0.02], (0, torso_y - 0.02, 0.3), ink, n="ink_line_2"),
        box([0.34, 0.28, 0.28], (0, top + 0.18, 0), paper, n="head"),
        box([0.28, 0.07, 0.03], (0, top + 0.2, 0.145), ink, n="visor"),
        cyl(0.03, 0.03, 0.3, (0, top + 0.34, 0), roll, r=(0, 0, 90), seg=8, n="head_rod"),
    ]
    return parts

def shear():
    red, dark, steel = "#cf3a3a", "#5a1d22", "#c9ced6"
    parts, hip, top = humanoid(red, dark, steel, leg_h=0.6, leg_w=0.15, torso=(0.52, 0.56, 0.32),
                               arm_len=0.52, arm_w=0.12, hand_r=0.075)
    torso_y = hip + 0.14 + 0.28
    parts.insert(0, box([0.52, 0.56, 0.32], (0, torso_y, 0), red, n="torso"))
    parts += [
        box([0.3, 0.3, 0.04], (0, torso_y + 0.04, 0.17), steel, r=(0, 0, 45), n="chest_x"),
        cyl(0.07, 0.07, 0.04, (0, torso_y + 0.04, 0.19), BK, r=Z, seg=8, n="pivot"),
        box([0.28, 0.26, 0.28], (0, top + 0.15, 0), steel, n="head"),
        box([0.22, 0.05, 0.03], (0, top + 0.17, 0.145), red, n="visor"),
        box([0.04, 0.38, 0.015], (0.07, top + 0.42, 0), steel, r=(0, 0, -16), n="blade_L"),
        box([0.04, 0.38, 0.015], (-0.07, top + 0.42, 0), steel, r=(0, 0, 16), n="blade_R"),
        cyl(0.09, 0.09, 0.05, (0.33, top - 0.02, 0), dark, r=(0, 0, 90), seg=10, n="shoulder_ring_L"),
        cyl(0.09, 0.09, 0.05, (-0.33, top - 0.02, 0), dark, r=(0, 0, 90), seg=10, n="shoulder_ring_R"),
    ]
    return parts

def snip():
    red, dark, steel = "#8f2430", "#2e1418", "#c9ced6"
    parts, hip, top = humanoid(red, dark, steel, leg_h=0.65, leg_w=0.12, torso=(0.4, 0.48, 0.26),
                               arm_len=0.5, arm_w=0.1, hand_r=0.065)
    torso_y = hip + 0.14 + 0.24
    parts.insert(0, box([0.4, 0.48, 0.26], (0, torso_y, 0), red, n="torso"))
    parts += [
        box([0.06, 0.4, 0.03], (0, torso_y, 0.135), steel, n="chest_stripe"),
        sph(0.15, (0, top + 0.15, 0), steel, ws=8, hs=6, n="head"),
        box([0.22, 0.045, 0.06], (0, top + 0.16, 0.12), OR, n="visor"),
        box([0.025, 0.12, 0.36], (0, top + 0.3, -0.03), "#8e959e", n="blade_crest"),
        box([0.02, 0.32, 0.05], (0.29, top - 0.38, 0.06), steel, r=(-10, 0, 0), n="arm_blade_L"),
        box([0.02, 0.32, 0.05], (-0.29, top - 0.38, 0.06), steel, r=(-10, 0, 0), n="arm_blade_R"),
    ]
    return parts

CHARS = [
    ("boulder", "볼더",   "바위", "탱커", boulder),
    ("pebble",  "페블",   "바위", "정찰", pebble),
    ("origami", "오리가미", "보",  "기동", origami),
    ("scroll",  "스크롤", "보",   "지원", scroll),
    ("shear",   "시어",   "가위", "근접", shear),
    ("snip",    "스닙",   "가위", "암살", snip),
]

# ---------- 메시 생성 (플랫 셰이딩, 비인덱스) ----------
def polys(part):
    t, s = part["t"], part["s"]
    if t == "box":
        w, h, d = [v / 2 for v in s]
        v = np.array([[x, y, z] for x in (-w, w) for y in (-h, h) for z in (-d, d)])
        faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
        return [[v[i] for i in f] for f in faces]
    if t == "cyl":
        rt, rb, h, seg = s
        seg = int(seg)
        out, top, bot = [], [], []
        for i in range(seg):
            a0, a1 = 2 * math.pi * i / seg, 2 * math.pi * (i + 1) / seg
            p = lambda r, a, y: np.array([r * math.sin(a), y, r * math.cos(a)])
            quad = [p(rb, a0, -h / 2), p(rb, a1, -h / 2), p(rt, a1, h / 2), p(rt, a0, h / 2)]
            out.append(quad[:3] if rt == 0 else quad)
            top.append(p(rt, a0, h / 2)); bot.append(p(rb, a0, -h / 2))
        if rt > 0: out.append(top)
        if rb > 0: out.append(bot)
        return out
    if t == "sph":
        r, ws, hs = s
        ws, hs = int(ws), int(hs)
        P = lambda i, j: np.array([-r * math.cos(2 * math.pi * i / ws) * math.sin(math.pi * j / hs),
                                   r * math.cos(math.pi * j / hs),
                                   r * math.sin(2 * math.pi * i / ws) * math.sin(math.pi * j / hs)])
        out = []
        for j in range(hs):
            for i in range(ws):
                a, b, c, d = P(i, j), P(i + 1, j), P(i + 1, j + 1), P(i, j + 1)
                if j == 0: out.append([a, c, d])
                elif j == hs - 1: out.append([a, b, c])
                else: out.append([a, b, c, d])
        return out
    raise ValueError(t)

def tris(part):
    pos, nor = [], []
    for poly in polys(part):
        c = np.mean(poly, axis=0)
        for k in range(1, len(poly) - 1):
            a, b, cc = poly[0], poly[k], poly[k + 1]
            nrm = np.cross(b - a, cc - a)
            L = np.linalg.norm(nrm)
            if L < 1e-12: continue
            nrm /= L
            if np.dot(nrm, c) < 0:  # 볼록 도형: 바깥쪽으로 향하게
                b, cc, nrm = cc, b, -nrm
            pos += [a, b, cc]; nor += [nrm] * 3
    return np.array(pos, np.float32), np.array(nor, np.float32)

def quat(r):
    x, y, z = [math.radians(v) / 2 for v in r]
    qx = (math.sin(x), 0, 0, math.cos(x)); qy = (0, math.sin(y), 0, math.cos(y)); qz = (0, 0, math.sin(z), math.cos(z))
    def mul(a, b):
        ax, ay, az, aw = a; bx, by, bz, bw = b
        return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)
    return list(mul(mul(qx, qy), qz))  # XYZ 순서 = Rx·Ry·Rz

def srgb_lin(hexc):
    v = [int(hexc[i:i + 2], 16) / 255 for i in (1, 3, 5)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in v] + [1.0]

def write_glb(name, parts, path):
    gl = {"asset": {"version": "2.0", "generator": "rps-models"}, "scene": 0,
          "scenes": [{"nodes": [0]}], "nodes": [{"name": name, "children": []}],
          "meshes": [], "materials": [], "accessors": [], "bufferViews": [], "buffers": []}
    blob, mats = bytearray(), {}
    for i, part in enumerate(parts):
        c, alpha = part["c"], part.get("a")
        mk = (c, alpha)
        if mk not in mats:
            mats[mk] = len(gl["materials"])
            col = srgb_lin(c)
            mat = {"name": c + (f"_a{alpha}" if alpha is not None else ""), "pbrMetallicRoughness": {
                "baseColorFactor": col, "metallicFactor": 0.45 if c in METALS else 0.0,
                "roughnessFactor": 0.55 if c in METALS else 0.8}}
            if alpha is not None:
                col[3] = alpha; mat["alphaMode"] = "BLEND"; mat["doubleSided"] = True
            gl["materials"].append(mat)
        c = mk
        pos, nor = tris(part)
        acc = []
        for arr, kind in ((pos, "POSITION"), (nor, "NORMAL")):
            while len(blob) % 4: blob.append(0)
            off = len(blob); blob += arr.tobytes()
            gl["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes, "target": 34962})
            a = {"bufferView": len(gl["bufferViews"]) - 1, "componentType": 5126, "count": len(arr), "type": "VEC3"}
            if kind == "POSITION": a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
            gl["accessors"].append(a); acc.append(len(gl["accessors"]) - 1)
        gl["meshes"].append({"primitives": [{"attributes": {"POSITION": acc[0], "NORMAL": acc[1]}, "material": mats[c]}]})
        node = {"name": part.get("n", f"part_{i}"), "mesh": len(gl["meshes"]) - 1, "translation": part["p"]}
        if any(part["r"]): node["rotation"] = quat(part["r"])
        if part.get("sc"): node["scale"] = part["sc"]
        gl["nodes"].append(node); gl["nodes"][0]["children"].append(len(gl["nodes"]) - 1)
    while len(blob) % 4: blob.append(0)
    gl["buffers"].append({"byteLength": len(blob)})
    js = json.dumps(gl, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "out")
    os.makedirs(os.path.join(out, "guns"), exist_ok=True)
    os.makedirs(os.path.join(out, "characters"), exist_ok=True)
    data = {"guns": [], "characters": []}
    for mid, label, cls, fn in GUNS:
        parts = fn(); write_glb(mid, parts, f"{out}/guns/{mid}.glb")
        data["guns"].append({"id": mid, "name": label, "class": cls, "parts": parts})
    for mid, label, faction, role, fn in CHARS:
        parts = fn(); write_glb(mid, parts, f"{out}/characters/{mid}.glb")
        data["characters"].append({"id": mid, "name": label, "faction": faction, "role": role, "parts": parts})
    with open(f"{out}/models.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("ok", sum(len(m["parts"]) for m in data["guns"] + data["characters"]), "parts")
