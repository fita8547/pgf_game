"""캐릭터 12명 (정밀판). 발바닥 y=0, 정면 +Z, 캐릭터 왼쪽 = +X.
관절 계층: hips → spine → chest → neck → head / chest → upper_arm → forearm → hand / hips → thigh → shin → foot
모든 뼈 노드는 회전 0, 피벗이 관절 위치라 엔진에서 바로 회전 애니메이션 가능.
"""
import math
from parts import *

# ------------------------------------------------------------------ 바디
def body(sp):
    """sp: 체형/색 사양 dict → (parts, J)"""
    S = sp.get("scale", 1.0); B = sp.get("bulk", 1.0); F = sp.get("female", False)
    skin, top, top2 = sp["skin"], sp["top"], sp.get("top2", sp["top"])
    pants, boots, gloves = sp["pants"], sp["boots"], sp.get("gloves", sp["skin"])
    arm_skin = sp.get("arm_skin", top)       # 팔 소매 색 (반팔이면 skin)
    ankle, shin, thigh = 0.075 * S, 0.40 * S, 0.42 * S
    kneeY = ankle + shin; hipY = kneeY + thigh
    abdH, chestH = 0.19 * S, 0.27 * S
    spineY, chestY = hipY + 0.05 * S, hipY + 0.05 * S + abdH
    shY = chestY + chestH - 0.03 * S
    neckY = chestY + chestH
    neckH = 0.075 * S
    headY = neckY + neckH
    cw = (0.31 if F else 0.37) * B * S
    wd = (0.23 if F else 0.28) * B * S
    pw = (0.31 if F else 0.31) * B * S
    hx = (0.092 if F else 0.095) * B * S
    arm_r = (0.042 if F else 0.05) * B * S
    leg_r = (0.068 if F else 0.07) * B * S
    sx = cw / 2 + arm_r * 0.9
    upper, fore = 0.27 * S, 0.25 * S
    elbowY, wristY = shY - upper, shY - upper - fore
    J = dict(S=S, B=B, F=F, hipY=hipY, kneeY=kneeY, ankle=ankle, spineY=spineY, chestY=chestY, shY=shY,
             neckY=neckY, headY=headY, cw=cw, wd=wd, pw=pw, hx=hx, sx=sx, arm_r=arm_r, leg_r=leg_r,
             elbowY=elbowY, wristY=wristY, chestD=(0.2 if F else 0.22) * B * S)
    P = [
        rbox([pw, 0.15 * S, 0.19 * B * S], (0, hipY, 0), pants, b=0.04 * S, n="hips", o=(0, 0.01 * S, 0)),
        rbox([wd, abdH + 0.02, 0.17 * B * S], (0, spineY, 0), top, b=0.05 * S, n="spine", parent="hips", o=(0, abdH / 2, 0)),
        rbox([cw, chestH, J["chestD"]], (0, chestY, 0), top, b=(0.07 if F else 0.06) * S * B, bseg=3, n="chest", parent="spine", o=(0, chestH / 2, 0)),
        cyl(0.04 * S * (0.9 if F else 1.1), 0.045 * S * (0.9 if F else 1.15), neckH + 0.02, (0, neckY, 0), skin, n="neck", parent="chest", o=(0, neckH / 2, 0)),
        empty((0, headY, 0), "head", parent="neck"),
    ]
    if F:
        P.append(sph(0.105 * S * B, (0, chestY + chestH * 0.55, J["chestD"] * 0.28), top, n="chest_front", parent="chest", sc=(1.25, 0.62, 0.62)))
    else:
        P.append(rbox([cw * 0.78, chestH * 0.42, 0.04 * S], (0, chestY + chestH * 0.62, J["chestD"] / 2 - 0.006), top2, b=0.015 * S, n="chest_plate", parent="chest"))
    for side, s in (("L", 1), ("R", -1)):
        x = s * sx
        P += [
            sph(arm_r * 1.25, (x, shY, 0), top2, n=f"shoulder_{side}", parent="chest"),
            cap(arm_r * 0.86, upper - arm_r * 1.6, (x, shY, 0), arm_skin, r2=arm_r, n=f"upper_arm_{side}", parent="chest", o=(0, -upper / 2, 0)),
            cap(arm_r * 0.72, fore - arm_r * 1.4, (x, elbowY, 0), arm_skin if sp.get("long_sleeve", True) else skin, r2=arm_r * 0.86,
                n=f"forearm_{side}", parent=f"upper_arm_{side}", o=(0, -fore / 2, 0)),
            rbox([0.038 * S * B, 0.075 * S, 0.078 * S * B], (x, wristY, 0), gloves, b=0.015 * S, n=f"hand_{side}", parent=f"forearm_{side}", o=(0, -0.04 * S, 0)),
            rbox([0.034 * S * B, 0.05 * S, 0.07 * S * B], (x, wristY - 0.09 * S, 0.008 * S), gloves, b=0.013 * S, n=f"fingers_{side}", parent=f"hand_{side}", r=(12, 0, 0)),
            cap(0.012 * S, 0.035 * S, (x - s * 0.006 * S, wristY - 0.05 * S, 0.04 * S), gloves, r=(35, 0, 0), n=f"thumb_{side}", parent=f"hand_{side}"),
        ]
        lx = s * hx
        P += [
            cap(leg_r * 0.72, thigh - leg_r * 1.5, (lx, hipY, 0), pants, r2=leg_r, n=f"thigh_{side}", parent="hips", o=(0, -thigh / 2, 0)),
            cap(leg_r * 0.5, shin - leg_r * 1.1, (lx, kneeY, 0), pants, r2=leg_r * 0.74, n=f"shin_{side}", parent=f"thigh_{side}", o=(0, -shin / 2, 0)),
            lathe([(0, 0), (leg_r * 0.66, 0), (leg_r * 0.72, 0.12 * S), (leg_r * 0.82, 0.2 * S), (leg_r * 0.78, 0.215 * S), (0, 0.215 * S)],
                  (lx, ankle, 0), boots, seg=20, n=f"boot_shaft_{side}", parent=f"shin_{side}", o=(0, -0.02 * S, 0)),
            empty((lx, ankle, 0), f"foot_{side}", parent=f"shin_{side}"),
            rbox([0.1 * S * B, 0.085 * S, 0.22 * S], (lx, ankle, 0.035 * S), boots, b=0.03 * S, bseg=3, n=f"boot_{side}", parent=f"foot_{side}", o=(0, -0.035 * S, 0)),
            rbox([0.108 * S * B, 0.025 * S, 0.235 * S], (lx, 0.0125 * S, 0.035 * S), DARK, b=0.008 * S, n=f"sole_{side}", parent=f"foot_{side}", m="rubber"),
            sph(leg_r * 0.62, (lx, kneeY, 0.025 * S), sp.get("knee", pants), n=f"knee_{side}", parent=f"shin_{side}", sc=(1, 1.1, 0.75)),
        ]
    return P, J

# ------------------------------------------------------------------ 머리
def eyes(J, y, z, x=0.036, iris="#2a1e16", s=1.0, slit=False):
    S = J["S"]
    out = []
    for side, sx in (("L", 1), ("R", -1)):
        out += [sph(0.017 * S * s, (sx * x * S, y, z), "#f7f4ef", n=f"eye_white_{side}", parent="head", sc=(1, 0.9, 0.55)),
                sph(0.0105 * S * s, (sx * x * S, y, z + 0.007 * S), iris, n=f"iris_{side}", parent="head", sc=(0.7 if slit else 1, 1.05, 0.5), m="glow" if slit else None),
                sph(0.0035 * S * s, (sx * (x - 0.004) * S, y + 0.005 * S, z + 0.011 * S), "#ffffff", ws=8, hs=6, n=f"eye_glint_{side}")]
    return out

def human_head(J, skin, hair, style, iris="#2a1e16", lips=None, brows=None):
    S, F, H = J["S"], J["F"], J["headY"]
    brows = brows or hair
    P = [
        sph(0.104 * S, (0, H + 0.118 * S, -0.004 * S), skin, n="skull", parent="head", sc=(0.92, 1.08, 1.0)),
        rbox([0.142 * S if F else 0.158 * S, 0.075 * S, 0.135 * S], (0, H + 0.062 * S, 0.014 * S), skin, b=(0.035 if F else 0.026) * S, bseg=3, n="jaw", parent="head"),
        rbox([0.02 * S, 0.034 * S, 0.03 * S], (0, H + 0.098 * S, 0.098 * S), skin, b=0.009 * S, n="nose", parent="head", r=(-12, 0, 0)),
        sph(0.022 * S, (0.098 * S, H + 0.11 * S, -0.002 * S), skin, n="ear_L", parent="head", sc=(0.45, 1.1, 0.8)),
        sph(0.022 * S, (-0.098 * S, H + 0.11 * S, -0.002 * S), skin, n="ear_R", parent="head", sc=(0.45, 1.1, 0.8)),
        rbox([0.03 * S, 0.006 * S, 0.008 * S], (0.036 * S, H + 0.148 * S, 0.094 * S), brows, b=0.002 * S, n="brow_L", parent="head", r=(0, 0, -6 if F else -3)),
        rbox([0.03 * S, 0.006 * S, 0.008 * S], (-0.036 * S, H + 0.148 * S, 0.094 * S), brows, b=0.002 * S, n="brow_R", parent="head", r=(0, 0, 6 if F else 3)),
        rbox([0.034 * S, 0.006 * S, 0.008 * S], (0, H + 0.062 * S, 0.083 * S), lips or ("#b55a5a" if F else "#9a6458"), b=0.0025 * S, n="mouth", parent="head"),
    ] + eyes(J, H + 0.122 * S, 0.083 * S, iris=iris, s=1.1 if F else 1.0)
    P += hair_style(J, hair, style)
    return P

def hair_style(J, hair, style):
    S, H = J["S"], J["headY"]
    if style in (None, "bald"): return []
    P = [lathe([(0, 0.0), (0.112, 0.0), (0.114, 0.03), (0.104, 0.075), (0.075, 0.11), (0.03, 0.128), (0, 0.13)],
               (0, H + 0.125 * S, -0.008 * S), hair, seg=24, n="hair_cap", parent="head", sc=(S * 0.95, S, S * 1.05))]
    if style in ("short", "mohawk"):
        P.append(rbox([0.15 * S, 0.035 * S, 0.06 * S], (0, H + 0.19 * S, 0.06 * S), hair, b=0.015 * S, n="fringe", parent="head", r=(-25, 0, 0)))
    if style == "mohawk":
        P = [P[0]] + [rbox([0.03 * S, 0.06 * S, 0.2 * S], (0, H + 0.25 * S, -0.02 * S), hair, b=0.012 * S, n="mohawk", parent="head")]
    if style in ("ponytail", "bun", "long", "bob", "braid"):
        P.append(rbox([0.17 * S, 0.05 * S, 0.06 * S], (0, H + 0.185 * S, 0.07 * S), hair, b=0.02 * S, n="bangs", parent="head", r=(-30, 0, 0)))
    if style == "ponytail":
        P += [sph(0.028 * S, (0, H + 0.19 * S, -0.1 * S), hair, n="hair_tie", parent="head"),
              cap(0.035 * S, 0.17 * S, (0, H + 0.11 * S, -0.14 * S), hair, r2=0.025 * S, r=(25, 0, 0), n="ponytail", parent="head")]
    if style == "bun":
        P.append(sph(0.05 * S, (0, H + 0.24 * S, -0.06 * S), hair, n="hair_bun", parent="head"))
        P.append(cap(0.004 * S, 0.12 * S, (0.0, H + 0.25 * S, -0.06 * S), "#d9b45a", r=(0, 0, 80), n="hair_pin", parent="head"))
    if style == "long":
        P.append(rbox([0.2 * S, 0.26 * S, 0.06 * S], (0, H + 0.03 * S, -0.08 * S), hair, b=0.025 * S, n="hair_back", parent="head", r=(8, 0, 0)))
    if style == "bob":
        for side, s in (("L", 1), ("R", -1)):
            P.append(rbox([0.03 * S, 0.13 * S, 0.14 * S], (s * 0.1 * S, H + 0.09 * S, -0.01 * S), hair, b=0.014 * S, n=f"hair_side_{side}", parent="head"))
        P.append(rbox([0.2 * S, 0.13 * S, 0.05 * S], (0, H + 0.09 * S, -0.09 * S), hair, b=0.02 * S, n="hair_back", parent="head"))
    if style == "braid":
        for i in range(5):
            P.append(sph(0.032 * S * (1 - i * 0.08), (0, H + 0.13 * S - i * 0.06 * S, -0.12 * S - i * 0.008 * S), hair, n=f"braid_{i}", parent="head", sc=(1, 1.15, 1)))
    return P

def orc_head(J, skin, hair, style, female=False):
    S, H = J["S"], J["headY"]
    P = [
        sph(0.11 * S, (0, H + 0.12 * S, -0.01 * S), skin, n="skull", parent="head", sc=(0.98, 1.0, 1.0)),
        rbox([(0.17 if female else 0.19) * S, 0.09 * S, 0.15 * S], (0, H + 0.058 * S, 0.026 * S), skin, b=0.03 * S, bseg=3, n="jaw", parent="head"),
        rbox([0.16 * S, 0.026 * S, 0.04 * S], (0, H + 0.155 * S, 0.085 * S), skin, b=0.012 * S, n="brow_ridge", parent="head"),
        rbox([0.034 * S, 0.026 * S, 0.03 * S], (0, H + 0.11 * S, 0.11 * S), skin, b=0.01 * S, n="nose", parent="head"),
        rbox([0.06 * S, 0.006 * S, 0.008 * S], (0, H + 0.068 * S, 0.1 * S), "#3b2a24", b=0.0025 * S, n="mouth", parent="head"),
    ] + eyes(J, H + 0.13 * S, 0.092 * S, x=0.04, iris="#e8b430" if not female else "#d0502a", s=0.9, slit=False)
    tl = (0.03 if female else 0.045) * S
    for side, s in (("L", 1), ("R", -1)):
        P += [cyl(0, 0.011 * S, tl, (s * 0.045 * S, H + 0.072 * S + tl / 2, 0.096 * S), "#f1ead6", seg=10, r=(-10, 0, -s * 12), n=f"tusk_{side}"),
              cyl(0, 0.03 * S, 0.11 * S, (s * 0.13 * S, H + 0.13 * S, -0.01 * S), skin, seg=12, r=(0, 0, -s * 72), n=f"ear_{side}", parent="head", sc=(1, 1, 0.45))]
    P = [q if "parent" in q else {**q, "parent": "head"} for q in P]
    P += hair_style(J, hair, style)
    return P

BEASTS = {
    "wolf": dict(muzzle=0.11, ear="point", ear_h=0.11, tail="bushy"),
    "fox": dict(muzzle=0.095, ear="point", ear_h=0.12, tail="fluffy"),
    "cat": dict(muzzle=0.045, ear="point", ear_h=0.08, tail="thin"),
    "bear": dict(muzzle=0.075, ear="round", ear_h=0.05, tail="stub"),
}

def beast_head(J, kind, fur, muzzle_c, inner_ear, iris, hair=None, style=None):
    S, H, k = J["S"], J["headY"], BEASTS[kind]
    m = k["muzzle"] * S
    P = [
        sph(0.108 * S, (0, H + 0.12 * S, -0.01 * S), fur, n="skull", parent="head", sc=(1.0, 0.98, 1.0)),
        cap(0.05 * S, m, (0, H + 0.08 * S, 0.06 * S + m / 2), muzzle_c, r=(90 - (8 if kind != "cat" else 0), 0, 0), n="muzzle", parent="head",
            r2=0.042 * S if kind in ("wolf", "fox") else 0.05 * S),
        sph(0.018 * S, (0, H + 0.098 * S if kind != "cat" else H + 0.09 * S, 0.1 * S + m), "#1d1b1e", n="nose", parent="head", sc=(1.2, 0.85, 0.9)),
        rbox([0.05 * S, 0.006 * S, 0.008 * S], (0, H + 0.058 * S, 0.075 * S + m * 0.8), "#2a2228", b=0.0025 * S, n="mouth", parent="head"),
    ] + eyes(J, H + 0.135 * S, 0.088 * S, x=0.042, iris=iris, s=1.05, slit=kind in ("cat", "fox", "wolf"))
    for side, s in (("L", 1), ("R", -1)):
        if k["ear"] == "point":
            P += [cyl(0, 0.045 * S, k["ear_h"] * S, (s * 0.06 * S, H + 0.215 * S, -0.01 * S), fur, seg=4, r=(0, 45, -s * 14), n=f"ear_{side}", parent="head", sc=(1, 1, 0.55)),
                  cyl(0, 0.028 * S, k["ear_h"] * S * 0.7, (s * 0.058 * S, H + 0.21 * S, 0.006 * S), inner_ear, seg=4, r=(0, 45, -s * 14), n=f"ear_inner_{side}", parent="head", sc=(1, 1, 0.4))]
        else:
            P += [sph(0.035 * S, (s * 0.08 * S, H + 0.2 * S, -0.01 * S), fur, n=f"ear_{side}", parent="head", sc=(1, 1, 0.55)),
                  sph(0.022 * S, (s * 0.08 * S, H + 0.2 * S, 0.006 * S), inner_ear, n=f"ear_inner_{side}", parent="head", sc=(1, 1, 0.4))]
        if kind in ("wolf", "fox", "cat"):
            P.append(cyl(0, 0.03 * S, 0.06 * S, (s * 0.095 * S, H + 0.08 * S, 0.03 * S), fur, seg=4, r=(0, 0, -s * 100), n=f"cheek_fur_{side}", parent="head", sc=(1, 1, 0.5)))
    if hair:
        P += hair_style(J, hair, style)
    return P

def tail(J, kind, fur, tip):
    S, y = J["S"], J["hipY"] - 0.02 * J["S"]
    z = -0.1 * S
    out = []
    if kind == "stub":
        return [sph(0.05 * S, (0, y, z), fur, n="tail", parent="hips")]
    segs = {"bushy": (0.05, 0.065, 4), "fluffy": (0.06, 0.085, 4), "thin": (0.018, 0.02, 6)}[kind]
    r0, r1, n = segs
    for i in range(n):
        t = i / (n - 1)
        rr = r0 + (r1 - r0) * math.sin(math.pi * t * 0.8)
        zz = z - 0.08 * S * i
        yy = y - 0.1 * S * i + 0.012 * S * i * i
        col = tip if i == n - 1 and tip else fur
        out.append(sph(rr * S, (0, yy, zz), col, n=f"tail_{i}", parent="hips", sc=(1, 1, 1.4)))
    return out

# ------------------------------------------------------------------ 장비 헬퍼
def belt(J, c, buckle, n="belt"):
    S = J["S"]
    return [lathe([(0, 0), (J["pw"] * 0.55, 0), (J["pw"] * 0.56, 0.045 * S), (0, 0.045 * S)], (0, J["hipY"] + 0.035 * S, 0), c, seg=20, n=n, parent="hips", sc=(1, 1, 0.68)),
            rbox([0.05 * S, 0.04 * S, 0.012 * S], (0, J["hipY"] + 0.057 * S, J["pw"] * 0.39), buckle, b=0.006 * S, n=f"{n}_buckle", parent="hips", m="metal")]

def pouch(J, side, c, n):
    S, s = J["S"], (1 if side == "L" else -1)
    return [rbox([0.04 * S, 0.07 * S, 0.06 * S], (s * (J["hx"] + J["leg_r"] * 0.95), J["hipY"] - 0.12 * S, 0.01 * S), c, b=0.012 * S, n=n, parent=f"thigh_{side}")]

def skirt(J, c, length, flare=1.35, n="robe_skirt", seg=24):
    S, y = J["S"], J["hipY"] + 0.06 * J["S"]
    r0 = J["pw"] * 0.56
    return [lathe([(0, 0), (r0 * flare, -length), (r0 * flare * 1.02, -length - 0.01 * S), (r0 * 1.0, 0.02 * S), (0, 0.02 * S)][::-1][::-1],
                  (0, y, 0), c, seg=seg, n=n, parent="hips", sc=(1, 1, 0.75), smooth=True)]

def scarf(J, c, n="scarf", tail_len=0.22):
    S, y = J["S"], J["neckY"] + 0.005 * J["S"]
    return [lathe([(0, 0), (0.07 * S, 0), (0.082 * S, 0.02 * S), (0.075 * S, 0.06 * S), (0, 0.06 * S)], (0, y, 0), c, seg=20, n=n, parent="chest", sc=(1.15, 1, 1)),
            rbox([0.06 * S, tail_len * S, 0.02 * S], (0.06 * S, y - tail_len * S / 2, -0.09 * S), c, b=0.008 * S, r=(12, 0, 8), n=f"{n}_tail", parent="chest")]

def pauldron(J, side, c, kind="plate", trim=None, scale=1.0):
    S, s = J["S"], (1 if side == "L" else -1)
    x, y = s * J["sx"], J["shY"] + 0.02 * S
    if kind == "rock":
        return [rock([0.17 * S * scale, 0.13 * S * scale, 0.19 * S * scale], (x + s * 0.02 * S, y + 0.02 * S, 0), STONE, seed=7 if s > 0 else 11, n=f"pauldron_{side}", parent=f"upper_arm_{side}")]
    out = [rbox([0.14 * S * scale, 0.05 * S, 0.18 * S * scale], (x + s * 0.01 * S, y + 0.03 * S, 0), c, b=0.02 * S, r=(0, 0, -s * 20), n=f"pauldron_{side}", parent=f"upper_arm_{side}", m="metal" if c in (STEEL, SV) else None),
           rbox([0.12 * S * scale, 0.04 * S, 0.16 * S * scale], (x + s * 0.04 * S, y - 0.01 * S, 0), c, b=0.018 * S, r=(0, 0, -s * 35), n=f"pauldron_low_{side}", parent=f"upper_arm_{side}", m="metal" if c in (STEEL, SV) else None)]
    if trim:
        out.append(rbox([0.145 * S * scale, 0.012 * S, 0.185 * S * scale], (x + s * 0.012 * S, y + 0.056 * S, 0), trim, b=0.005 * S, r=(0, 0, -s * 20), n=f"pauldron_trim_{side}", parent=f"upper_arm_{side}"))
    return out

def bracer(J, side, c, trim=None):
    S, s = J["S"], (1 if side == "L" else -1)
    out = [lathe([(0, 0), (J["arm_r"] * 0.86, 0), (J["arm_r"] * 1.0, 0.13 * S), (0, 0.13 * S)], (s * J["sx"], J["wristY"] + 0.015 * S, 0), c, seg=18, n=f"bracer_{side}", parent=f"forearm_{side}")]
    if trim: out.append(cyl(J["arm_r"] * 1.03, J["arm_r"] * 1.03, 0.015 * S, (s * J["sx"], J["wristY"] + 0.14 * S, 0), trim, n=f"bracer_trim_{side}", parent=f"forearm_{side}"))
    return out

def backpack(J, c, size=(0.24, 0.3, 0.12), n="backpack"):
    S = J["S"]
    return [rbox([size[0] * S, size[1] * S, size[2] * S], (0, J["chestY"] + 0.13 * S, -J["chestD"] / 2 - size[2] * S / 2 + 0.01 * S), c, b=0.03 * S, n=n, parent="chest")]

# ------------------------------------------------------------------ 캐릭터
def boulder():  # 바위 · 탱커 · 오크 남
    skin = "#6f9a52"
    P, J = body(dict(scale=1.12, bulk=1.45, skin=skin, top=STONE_D, top2=STONE, pants="#3d3a36", boots="#2e2b28", gloves=skin, arm_skin=skin, long_sleeve=False, knee=STONE))
    S = J["S"]
    P += orc_head(J, skin, "#1b1b1b", "mohawk")
    P += [rbox([J["cw"] * 0.86, 0.2 * S, 0.05 * S], (0, J["chestY"] + 0.16 * S, J["chestD"] / 2), STONE, b=0.025 * S, n="stone_breastplate", parent="chest"),
          rbox([0.012 * S, 0.12 * S, 0.004 * S], (0, J["chestY"] + 0.16 * S, J["chestD"] / 2 + 0.026 * S), OR, b=0.003 * S, n="rune_glow", parent="chest", m="glow")]
    P += belt(J, "#5a3d26", OR)
    for side in ("L", "R"):
        P += pauldron(J, side, STONE, kind="rock", scale=1.25) + bracer(J, side, STONE_D, trim=OR)
    P += [cap(0.022 * S, 0.9 * S, (0.12 * S, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.05 * S), "#5a3d26", r=(0, 0, 32), n="maul_handle", parent="chest"),
          rock([0.3 * S, 0.2 * S, 0.22 * S], (-0.12 * S, J["chestY"] + 0.53 * S, -J["chestD"] / 2 - 0.05 * S), STONE, seed=21, n="maul_head", parent="chest")]
    return P

def pebble():  # 바위 · 딜러 · 인간 여 (정찰)
    P, J = body(dict(female=True, scale=0.96, bulk=0.9, skin="#e8b896", top="#6e7270", top2=STONE_D, pants="#4a4d48", boots="#3a2a20", gloves="#3a2a20", knee="#3a3c3a"))
    S = J["S"]
    P += human_head(J, "#e8b896", "#6b3e24", "ponytail", iris="#4a7a3a")
    P += [cyl(0.11 * S, 0.11 * S, 0.03 * S, (0, J["headY"] + 0.19 * S, 0.0), "#3a2a20", n="goggle_strap", parent="head", sc=(1, 1, 1.05)),
          cyl(0.026 * S, 0.026 * S, 0.03 * S, (0.04 * S, J["headY"] + 0.2 * S, 0.1 * S), OR, r=Z, n="goggle_L", parent="head", m="glass", a=0.7),
          cyl(0.026 * S, 0.026 * S, 0.03 * S, (-0.04 * S, J["headY"] + 0.2 * S, 0.1 * S), OR, r=Z, n="goggle_R", parent="head", m="glass", a=0.7)]
    P += scarf(J, OR) + belt(J, "#3a2a20", BRASS) + pouch(J, "L", "#3a2a20", "pouch_L") + pouch(J, "R", "#3a2a20", "pouch_R")
    P += [rbox([J["cw"] * 0.95, 0.03 * S, J["chestD"] * 1.02], (0, J["chestY"] + 0.06 * S, 0), "#3a2a20", b=0.01 * S, n="chest_strap", parent="chest", r=(0, 0, 25))]
    P += backpack(J, "#57483a", size=(0.18, 0.22, 0.09))
    for i in range(3):
        P.append(rock([0.05 * S, 0.04 * S, 0.05 * S], ((i - 1) * 0.055 * S, J["chestY"] + 0.27 * S, -J["chestD"] / 2 - 0.06 * S), STONE, seed=30 + i, n=f"pebble_{i}", parent="chest"))
    return P

def gem():  # 바위 · 지원 · 여우 수인 여
    fur, white = "#e07a2e", "#f4ede2"
    P, J = body(dict(female=True, scale=0.98, bulk=0.86, skin=fur, top="#3e6f78", top2=CRYSTAL, pants="#2c4c53", boots="#2a2420", gloves=white, knee="#2c4c53"))
    S = J["S"]
    P += beast_head(J, "fox", fur, white, "#f6c9b0", "#2fb5a8")
    P += tail(J, "fluffy", fur, white)
    P += skirt(J, "#3e6f78", 0.42 * S, flare=1.5)
    P += [rbox([J["cw"] * 0.4, 0.2 * S, 0.02 * S], (0, J["chestY"] + 0.12 * S, J["chestD"] / 2 + 0.01 * S), "#e9d9b5", b=0.008 * S, n="robe_panel", parent="chest")]
    for side, s in (("L", 1), ("R", -1)):
        for i, (dx, h) in enumerate(((0.0, 0.14), (0.03, 0.09), (-0.03, 0.08))):
            P.append(cyl(0, 0.025 * S, h * S, (s * (J["sx"] + dx * S), J["shY"] + 0.06 * S + h * S / 2, dx * S), CRYSTAL, seg=5, r=(dx * 300, 0, -s * 18), n=f"shoulder_crystal_{side}_{i}", parent=f"upper_arm_{side}", m="glow"))
    for i in range(7):
        a = math.radians(i * 360 / 7)
        P.append(cyl(0, 0.014 * S, 0.06 * S, (0.13 * S * math.cos(a), J["headY"] + 0.3 * S, 0.13 * S * math.sin(a)), CRYSTAL, seg=4, n=f"halo_shard_{i}", parent="head", m="glow"))
    P += belt(J, "#2a2420", CRYSTAL)
    return P

def quake():  # 바위 · 전략가 · 인간 남 (엔지니어)
    skin = "#c98e68"
    P, J = body(dict(scale=0.95, bulk=1.25, skin=skin, top="#7a5a3a", top2=OR, pants="#3d4450", boots="#3a2a20", gloves="#4a3a2c", knee="#2e3440"))
    S = J["S"]
    P += human_head(J, skin, "#4a2c1a", "short", iris="#3a2a1a")
    P += [rbox([0.15 * S, 0.07 * S, 0.06 * S], (0, J["headY"] + 0.05 * S, 0.07 * S), "#4a2c1a", b=0.025 * S, n="beard", parent="head"),
          rbox([0.08 * S, 0.012 * S, 0.02 * S], (0, J["headY"] + 0.083 * S, 0.1 * S), "#4a2c1a", b=0.005 * S, n="mustache", parent="head"),
          lathe([(0, 0), (0.13 * S, 0), (0.13 * S, 0.012 * S), (0.105 * S, 0.02 * S), (0.1 * S, 0.07 * S), (0.06 * S, 0.105 * S), (0, 0.11 * S)],
                (0, J["headY"] + 0.17 * S, 0.005 * S), OR, seg=24, n="hard_hat", parent="head"),
          rbox([0.02 * S, 0.02 * S, 0.2 * S], (0, J["headY"] + 0.27 * S, 0.0), "#e86a12", b=0.008 * S, n="hard_hat_ridge", parent="head")]
    P += [rbox([J["cw"] * 1.04, 0.22 * S, J["chestD"] * 1.08], (0, J["chestY"] + 0.13 * S, 0), OR, b=0.04 * S, n="safety_vest", parent="chest"),
          rbox([J["cw"] * 1.06, 0.022 * S, J["chestD"] * 1.1], (0, J["chestY"] + 0.1 * S, 0), "#e8eef2", b=0.006 * S, n="reflective_band", parent="chest")]
    P += belt(J, "#3a2a20", SV) + pouch(J, "L", "#5a4632", "tool_pouch_L") + pouch(J, "R", "#5a4632", "tool_pouch_R")
    P += [cap(0.016 * S, 0.12 * S, ((J["hx"] + J["leg_r"]) * 1.0, J["hipY"] - 0.03 * S, 0.04 * S), SV, n="wrench", parent="thigh_L", m="metal")]
    P += backpack(J, "#4b4f55", size=(0.28, 0.34, 0.14), n="generator_pack")
    P += [cyl(0.03 * S, 0.03 * S, 0.12 * S, (0.08 * S, J["chestY"] + 0.36 * S, -J["chestD"] / 2 - 0.08 * S), GM, n="exhaust", parent="chest", m="metal"),
          cap(0.018 * S, 0.7 * S, (-0.1 * S, J["chestY"] + 0.1 * S, -J["chestD"] / 2 - 0.17 * S), WD, r=(0, 0, -25), n="hammer_handle", parent="chest"),
          rbox([0.22 * S, 0.11 * S, 0.11 * S], (0.05 * S, J["chestY"] + 0.42 * S, -J["chestD"] / 2 - 0.17 * S), STONE_D, b=0.02 * S, r=(0, 0, -25), n="hammer_head", parent="chest", m="metal")]
    return P

def cardboard():  # 보 · 탱커 · 곰 수인 남
    fur, tape = "#7a5232", "#e8d9a8"
    P, J = body(dict(scale=1.15, bulk=1.5, skin=fur, top=CARD, top2=CARD, pants="#4a3a2c", boots="#3a2a20", gloves=fur, arm_skin=fur, long_sleeve=False, knee=CARD))
    S = J["S"]
    P += beast_head(J, "bear", fur, "#c49a6c", "#4a2f1c", "#2a1a10")
    P += tail(J, "stub", fur, None)
    P += [rbox([J["cw"] * 1.1, 0.3 * S, J["chestD"] * 1.25], (0, J["chestY"] + 0.15 * S, 0), CARD, b=0.012 * S, n="box_armor", parent="chest"),
          rbox([J["cw"] * 1.12, 0.05 * S, J["chestD"] * 1.27], (0, J["chestY"] + 0.2 * S, 0), tape, b=0.006 * S, n="tape_h", parent="chest"),
          rbox([0.05 * S, 0.31 * S, J["chestD"] * 1.27], (0.02 * S, J["chestY"] + 0.15 * S, 0), tape, b=0.006 * S, n="tape_v", parent="chest"),
          rbox([0.1 * S, 0.06 * S, 0.004 * S], (-0.12 * S, J["chestY"] + 0.08 * S, J["chestD"] * 0.63), "#f4f1e8", b=0.002 * S, n="shipping_label", parent="chest"),
          rbox([0.08 * S, 0.08 * S, 0.004 * S], (0.13 * S, J["chestY"] + 0.07 * S, J["chestD"] * 0.63), BLUE, b=0.002 * S, n="this_side_up", parent="chest", r=(0, 0, 45))]
    for side, s in (("L", 1), ("R", -1)):
        P += [rbox([0.2 * S, 0.16 * S, 0.2 * S], (s * (J["sx"] + 0.03 * S), J["shY"] + 0.02 * S, 0), CARD, b=0.01 * S, n=f"box_pauldron_{side}", parent=f"upper_arm_{side}", r=(0, 0, -s * 12)),
              rbox([0.205 * S, 0.035 * S, 0.205 * S], (s * (J["sx"] + 0.03 * S), J["shY"] + 0.02 * S, 0), tape, b=0.005 * S, n=f"box_pauldron_tape_{side}", parent=f"upper_arm_{side}", r=(0, 0, -s * 12))]
        P += bracer(J, side, CARD, trim=BLUE)
    P += [rbox([0.24 * S, 0.06 * S, 0.24 * S], (0, J["headY"] + 0.22 * S, -0.01 * S), CARD, b=0.008 * S, n="box_helmet", parent="head"),
          rbox([0.1 * S, 0.03 * S, 0.24 * S], (0.09 * S, J["headY"] + 0.26 * S, -0.01 * S), CARD, b=0.006 * S, n="box_flap_L", parent="head", r=(0, 0, 30)),
          rbox([0.1 * S, 0.03 * S, 0.24 * S], (-0.09 * S, J["headY"] + 0.26 * S, -0.01 * S), CARD, b=0.006 * S, n="box_flap_R", parent="head", r=(0, 0, -30))]
    P += belt(J, BLUE, SV)
    return P

def origami():  # 보 · 딜러 · 인간 여 (종이 닌자)
    skin = "#f0c8a8"
    P, J = body(dict(female=True, scale=1.0, bulk=0.85, skin=skin, top=PAPER, top2=FOLD, pants="#2a3550", boots="#1e2638", gloves=PAPER, knee=FOLD))
    S = J["S"]
    P += human_head(J, skin, "#15161c", "bun", iris="#1f3a7a")
    P += [rbox([0.15 * S, 0.06 * S, 0.11 * S], (0, J["headY"] + 0.06 * S, 0.035 * S), INK, b=0.02 * S, n="face_mask", parent="head")]
    P += [rbox([0.24 * S, 0.035 * S, 0.012 * S], (0, J["headY"] + 0.17 * S, 0.1 * S), BLUE, b=0.005 * S, n="headband", parent="head")]
    for i, (dx, dy, rz) in enumerate(((0.06, 0.18, -20), (-0.06, 0.18, 20), (0.0, 0.08, 0))):
        P.append(cyl(0, 0.06 * S, 0.12 * S, (dx * S, J["chestY"] + dy * S, J["chestD"] / 2 + 0.01 * S), FOLD if i % 2 else PAPER, seg=4, r=(90, 45, rz), n=f"fold_plate_{i}", parent="chest", sc=(1, 1, 0.25)))
    P += [rbox([J["cw"] * 0.9, 0.05 * S, J["chestD"] * 1.05], (0, J["chestY"] + 0.01 * S, 0), BLUE, b=0.012 * S, n="obi_sash", parent="chest")]
    for side, s in (("L", 1), ("R", -1)):
        for i, (ry, rz, L) in enumerate(((35, 20, 0.42), (50, 0, 0.36), (40, -20, 0.3))):
            P.append(rbox([L * S, 0.12 * S, 0.006 * S], (s * (0.1 + L * 0.42) * S, J["chestY"] + (0.22 + 0.04 * (1 - i)) * S, -J["chestD"] / 2 - 0.06 * S - 0.1 * L * S),
                          PAPER if i != 1 else FOLD, b=0.002 * S, r=(0, s * ry, s * rz), n=f"paper_wing_{side}_{i}", parent="chest"))
        P += bracer(J, side, FOLD, trim=BLUE)
        P.append(rbox([0.06 * S, 0.1 * S, 0.11 * S], (s * J["hx"], J["kneeY"] - 0.02 * S, 0.04 * S), FOLD, b=0.015 * S, n=f"shin_guard_{side}", parent=f"shin_{side}"))
    return P

def scroll():  # 보 · 지원 · 인간 남 (수도승)
    skin = "#b88462"
    P, J = body(dict(scale=1.0, bulk=1.05, skin=skin, top="#e8dcc0", top2="#d8c9a5", pants="#e8dcc0", boots="#5a3d26", gloves=skin, arm_skin="#e8dcc0", knee="#e8dcc0"))
    S = J["S"]
    P += human_head(J, skin, "#2a1c14", "bald", iris="#3a2a1a")
    P += [rbox([0.11 * S, 0.05 * S, 0.05 * S], (0, J["headY"] + 0.035 * S, 0.075 * S), "#2a1c14", b=0.02 * S, n="goatee", parent="head"),
          lathe([(0, 0), (0.25 * S, 0), (0.26 * S, 0.012 * S), (0.06 * S, 0.1 * S), (0, 0.11 * S)], (0, J["headY"] + 0.19 * S, 0), "#c9a66b", seg=28, n="straw_hat", parent="head")]
    P += skirt(J, "#e8dcc0", 0.62 * S, flare=1.4)
    P += [rbox([J["cw"] * 1.02, 0.05 * S, J["chestD"] * 1.05], (0, J["chestY"] + 0.015 * S, 0), "#7a4e2c", b=0.012 * S, n="sash", parent="chest"),
          rbox([0.04 * S, 0.34 * S, J["chestD"] * 1.06], (0.05 * S, J["chestY"] + 0.15 * S, 0), "#7a4e2c", b=0.01 * S, n="robe_strap", parent="chest", r=(0, 0, 32))]
    P += [cyl(0.075 * S, 0.075 * S, 0.62 * S, (0, J["chestY"] + 0.18 * S, -J["chestD"] / 2 - 0.08 * S), "#e8dcc0", r=(0, 0, 70), n="back_scroll", parent="chest"),
          cyl(0.085 * S, 0.085 * S, 0.06 * S, (0.29 * S, J["chestY"] + 0.074 * S, -J["chestD"] / 2 - 0.08 * S), "#7a4e2c", r=(0, 0, 70), n="back_scroll_cap_L", parent="chest"),
          cyl(0.085 * S, 0.085 * S, 0.06 * S, (-0.29 * S, J["chestY"] + 0.286 * S, -J["chestD"] / 2 - 0.08 * S), "#7a4e2c", r=(0, 0, 70), n="back_scroll_cap_R", parent="chest")]
    for i in range(10):
        a = math.radians(i * 36)
        P.append(sph(0.016 * S, (0.07 * S * math.cos(a), J["neckY"] - 0.06 * S - 0.04 * S * (1 + math.sin(a)) * 0.5, 0.11 * S + 0.02 * S * math.sin(a)), "#6b3a20", n=f"prayer_bead_{i}", parent="chest"))
    return P

def inkwell():  # 보 · 전략가 · 고양이 수인 여
    fur = "#2a2c36"
    P, J = body(dict(female=True, scale=0.98, bulk=0.88, skin=fur, top="#2f3b5c", top2=INK, pants="#1b2236", boots="#14181f", gloves="#e8e2d0", knee="#1b2236"))
    S = J["S"]
    P += beast_head(J, "cat", fur, "#3a3d4a", "#c98a9a", "#4dc3ff")
    P += tail(J, "thin", fur, BLUE)
    P += skirt(J, "#2f3b5c", 0.55 * S, flare=1.55, n="long_coat")
    P += [rbox([0.04 * S, 0.26 * S, 0.01 * S], (0, J["chestY"] + 0.13 * S, J["chestD"] / 2 + 0.004 * S), "#e8e2d0", b=0.004 * S, n="collar_line", parent="chest"),
          lathe([(0, 0), (0.14 * S, 0), (0.15 * S, 0.02 * S), (0.12 * S, 0.05 * S), (0, 0.055 * S)], (0.02 * S, J["headY"] + 0.205 * S, -0.02 * S), INK, seg=24, n="beret", parent="head", r=(0, 0, -12)),
          lathe([(0, 0), (0.04 * S, 0), (0.045 * S, 0.04 * S), (0.02 * S, 0.06 * S), (0.02 * S, 0.075 * S), (0, 0.075 * S)], (J["pw"] * 0.5, J["hipY"] + 0.0 * S, 0.05 * S), "#4dc3ff", seg=16, n="ink_pot", parent="hips", m="glass", a=0.75),
          cap(0.012 * S, 0.75 * S, (-0.08 * S, J["chestY"] + 0.12 * S, -J["chestD"] / 2 - 0.04 * S), "#7a4e2c", r=(0, 0, -30), n="brush_handle", parent="chest"),
          cyl(0.035 * S, 0.012 * S, 0.12 * S, (0.12 * S, J["chestY"] + 0.5 * S, -J["chestD"] / 2 - 0.04 * S), "#14181f", r=(0, 0, -30), n="brush_tip", parent="chest")]
    P += belt(J, "#14181f", BLUE)
    return P

def shear():  # 가위 · 탱커 · 오크 여 (기사)
    skin = "#7aa35a"
    P, J = body(dict(female=True, scale=1.06, bulk=1.25, skin=skin, top=RED, top2=STEEL, pants=RED_D, boots="#3a3f47", gloves="#3a3f47", knee=STEEL))
    S = J["S"]
    P += orc_head(J, skin, "#3a1f12", "braid", female=True)
    P += [rbox([J["cw"] * 0.95, 0.22 * S, 0.05 * S], (0, J["chestY"] + 0.15 * S, J["chestD"] / 2), STEEL, b=0.03 * S, n="breastplate", parent="chest", m="metal"),
          cyl(0.03 * S, 0.03 * S, 0.02 * S, (0, J["chestY"] + 0.15 * S, J["chestD"] / 2 + 0.03 * S), RED_D, r=Z, n="pivot_bolt", parent="chest")]
    for side, s in (("L", 1), ("R", -1)):
        P += pauldron(J, side, STEEL, trim=RED, scale=1.35) + bracer(J, side, STEEL, trim=RED)
        P.append(cyl(0, 0.03 * S, 0.16 * S, (s * (J["sx"] + 0.08 * S), J["shY"] + 0.09 * S, 0), STEEL, seg=4, r=(0, 0, -s * 50), n=f"pauldron_blade_{side}", parent=f"upper_arm_{side}", m="metal", sc=(1, 1, 0.3)))
        P.append(rbox([0.12 * S, 0.12 * S, 0.12 * S], (s * J["hx"], J["kneeY"] + 0.02 * S, 0.05 * S), STEEL, b=0.03 * S, n=f"knee_guard_{side}", parent=f"shin_{side}", m="metal"))
    P += skirt(J, RED_D, 0.24 * S, flare=1.3, n="tasset")
    for side, s in (("L", 1), ("R", -1)):
        bx, by, bz = s * 0.1 * S, J["chestY"] + 0.3 * S, -J["chestD"] / 2 - 0.05 * S
        P += [rbox([0.07 * S, 1.05 * S, 0.014 * S], (bx, by, bz), STEEL, b=0.005 * S, r=(0, 0, s * 14), n=f"greatblade_{side}", parent="chest", m="metal"),
              rbox([0.012 * S, 1.0 * S, 0.016 * S], (bx - s * 0.03 * S, by, bz), "#e9edf2", b=0.004 * S, r=(0, 0, s * 14), n=f"greatblade_edge_{side}", parent="chest", m="metal"),
              rbox([0.05 * S, 0.22 * S, 0.03 * S], (bx + s * 0.16 * S, by - 0.62 * S, bz), RED_D, b=0.012 * S, r=(0, 0, s * 14), n=f"greatblade_grip_{side}", parent="chest")]
    P += [cyl(0.05 * S, 0.05 * S, 0.06 * S, (0, J["chestY"] - 0.1 * S, -J["chestD"] / 2 - 0.05 * S), RED_D, r=Z, n="greatblade_pivot", parent="chest")]
    P += belt(J, "#3a3f47", RED)
    return P

def snip():  # 가위 · 딜러 · 늑대 수인 남 (암살자)
    fur = "#6d7480"
    P, J = body(dict(scale=1.02, bulk=0.95, skin=fur, top="#5a1d22", top2="#2e1418", pants="#1f1416", boots="#141012", gloves="#1f1416", knee="#2e1418"))
    S = J["S"]
    P += beast_head(J, "wolf", fur, "#c9ccd2", "#3a2a2a", "#ffcf3a")
    P += tail(J, "bushy", fur, "#c9ccd2")
    P += scarf(J, RED, n="scarf", tail_len=0.4)
    P += [rbox([J["cw"] * 0.95, 0.03 * S, J["chestD"] * 1.04], (0, J["chestY"] + 0.12 * S, 0), "#141012", b=0.01 * S, n="harness_strap", parent="chest", r=(0, 0, -30))]
    for i in range(3):
        P.append(cap(0.006 * S, 0.06 * S, (-0.06 * S + i * 0.03 * S, J["chestY"] + 0.15 * S + i * 0.02 * S, J["chestD"] / 2 + 0.02 * S), STEEL, n=f"throwing_knife_{i}", parent="chest", r=(0, 0, -30), m="metal"))
    for side, s in (("L", 1), ("R", -1)):
        P += bracer(J, side, "#2e1418", trim=STEEL)
        P.append(rbox([0.008 * S, 0.34 * S, 0.04 * S], (s * (J["sx"] + J["arm_r"] * 1.05), J["wristY"] - 0.02 * S, 0.0), STEEL, b=0.003 * S, n=f"arm_blade_{side}", parent=f"forearm_{side}", m="metal"))
        P.append(cyl(0, 0.02 * S, 0.06 * S, (s * (J["sx"] + J["arm_r"] * 1.05), J["wristY"] - 0.22 * S, 0.0), STEEL, seg=4, r=(180, 0, 0), n=f"arm_blade_tip_{side}", parent=f"forearm_{side}", m="metal", sc=(0.3, 1, 1)))
    P += belt(J, "#141012", STEEL)
    return P

def staple():  # 가위 · 전략가 · 로봇 (유일한 로봇)
    metal, joint = "#8e959e", "#3a3f47"
    P, J = body(dict(scale=1.0, bulk=1.05, skin=joint, top=metal, top2=RED, pants=joint, boots=joint, gloves=joint, arm_skin=metal, knee=RED))
    S = J["S"]
    H = J["headY"]
    P += [rbox([0.2 * S, 0.11 * S, 0.3 * S], (0, H + 0.07 * S, 0.0), joint, b=0.02 * S, n="head_base", parent="head", m="metal"),
          rbox([0.19 * S, 0.08 * S, 0.32 * S], (0, H + 0.16 * S, 0.01 * S), RED, b=0.025 * S, n="head_lid", parent="head", r=(-6, 0, 0)),
          rbox([0.16 * S, 0.03 * S, 0.01 * S], (0, H + 0.08 * S, 0.152 * S), "#ffcf3a", b=0.006 * S, n="visor", parent="head", m="glow"),
          cyl(0.02 * S, 0.02 * S, 0.22 * S, (0, H + 0.1 * S, -0.13 * S), SV, r=(0, 0, 90), n="hinge", parent="head", m="metal"),
          cap(0.006 * S, 0.12 * S, (0.06 * S, H + 0.27 * S, -0.08 * S), SV, n="antenna", parent="head", m="metal"),
          sph(0.015 * S, (0.06 * S, H + 0.34 * S, -0.08 * S), "#ff4060", n="antenna_light", parent="head", m="glow")]
    for side, s in (("L", 1), ("R", -1)):
        x = s * (J["sx"] + 0.02 * S)
        P += [rbox([0.025 * S, 0.12 * S, 0.025 * S], (x, J["shY"] + 0.08 * S, 0.06 * S), STEEL, b=0.006 * S, n=f"staple_{side}_a", parent=f"upper_arm_{side}", m="metal"),
              rbox([0.025 * S, 0.12 * S, 0.025 * S], (x, J["shY"] + 0.08 * S, -0.06 * S), STEEL, b=0.006 * S, n=f"staple_{side}_b", parent=f"upper_arm_{side}", m="metal"),
              rbox([0.025 * S, 0.025 * S, 0.145 * S], (x, J["shY"] + 0.14 * S, 0), STEEL, b=0.006 * S, n=f"staple_{side}_c", parent=f"upper_arm_{side}", m="metal")]
    P += [cyl(0.11 * S, 0.11 * S, 0.12 * S, (0, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.08 * S), "#c9a66b", r=(0, 0, 90), n="wire_spool", parent="chest"),
          cyl(0.13 * S, 0.13 * S, 0.02 * S, (0.07 * S, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.08 * S), RED, r=(0, 0, 90), n="spool_cap_L", parent="chest"),
          cyl(0.13 * S, 0.13 * S, 0.02 * S, (-0.07 * S, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.08 * S), RED, r=(0, 0, 90), n="spool_cap_R", parent="chest"),
          sph(0.04 * S, (0, J["chestY"] + 0.15 * S, J["chestD"] / 2 + 0.005 * S), "#7fdcff", n="core_light", parent="chest", m="glow", sc=(1, 1, 0.4))]
    P += belt(J, RED_D, SV)
    return P

def needle():  # 가위 · 지원 · 인간 여 (메딕)
    skin = "#8d5a3c"
    P, J = body(dict(female=True, scale=0.96, bulk=0.86, skin=skin, top="#b8343c", top2="#f4f1e8", pants="#2e2a30", boots="#3a2a20", gloves="#f4f1e8", knee="#2e2a30"))
    S = J["S"]
    P += human_head(J, skin, "#1a1210", "braid", iris="#3a2414", lips="#7a3a32")
    P += skirt(J, "#b8343c", 0.32 * S, flare=1.35, n="coat_tail")
    P += [rbox([J["cw"] * 1.02, 0.06 * S, J["chestD"] * 1.05], (0, J["chestY"] + 0.14 * S, 0), THREAD, b=0.012 * S, n="thread_sash", parent="chest", r=(0, 0, 28)),
          rbox([0.08 * S, 0.08 * S, 0.01 * S], (-0.08 * S, J["chestY"] + 0.19 * S, J["chestD"] / 2 + 0.006 * S), "#f4f1e8", b=0.006 * S, n="medic_patch", parent="chest"),
          cap(0.004 * S, 0.06 * S, (-0.08 * S, J["chestY"] + 0.19 * S, J["chestD"] / 2 + 0.014 * S), SV, r=(0, 0, 45), n="patch_needle_icon", parent="chest", m="metal"),
          rbox([0.14 * S, 0.1 * S, 0.07 * S], (J["pw"] * 0.42, J["hipY"] - 0.01 * S, 0.02 * S), "#f4f1e8", b=0.02 * S, n="medic_bag", parent="hips"),
          cyl(0.07 * S, 0.07 * S, 0.1 * S, (0, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.06 * S), THREAD, r=(0, 0, 90), n="thread_spool", parent="chest"),
          cyl(0.09 * S, 0.09 * S, 0.015 * S, (0.06 * S, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.06 * S), "#7a4e2c", r=(0, 0, 90), n="spool_cap_L", parent="chest"),
          cyl(0.09 * S, 0.09 * S, 0.015 * S, (-0.06 * S, J["chestY"] + 0.15 * S, -J["chestD"] / 2 - 0.06 * S), "#7a4e2c", r=(0, 0, 90), n="spool_cap_R", parent="chest"),
          cap(0.01 * S, 1.1 * S, (0.12 * S, J["chestY"] + 0.1 * S, -J["chestD"] / 2 - 0.13 * S), STEEL, r=(0, 0, 18), n="needle_staff", parent="chest", m="metal"),
          cyl(0, 0.01 * S, 0.14 * S, (-0.07 * S, J["chestY"] + 0.72 * S, -J["chestD"] / 2 - 0.13 * S), STEEL, r=(0, 0, 18), n="needle_tip", parent="chest", m="metal")]
    P += belt(J, "#3a2a20", BRASS)
    return P

CHARS = [
    # id, 이름, 진영, 역할, 종족, 성별, 함수
    ("boulder",   "볼더",     "바위", "탱커",   "오크",      "남", boulder),
    ("pebble",    "페블",     "바위", "딜러",   "인간",      "여", pebble),
    ("gem",       "젬",       "바위", "지원",   "여우 수인", "여", gem),
    ("quake",     "퀘이크",   "바위", "전략가", "인간",      "남", quake),
    ("cardboard", "카드보드", "보",   "탱커",   "곰 수인",   "남", cardboard),
    ("origami",   "오리가미", "보",   "딜러",   "인간",      "여", origami),
    ("scroll",    "스크롤",   "보",   "지원",   "인간",      "남", scroll),
    ("inkwell",   "잉크웰",   "보",   "전략가", "고양이 수인", "여", inkwell),
    ("shear",     "시어",     "가위", "탱커",   "오크",      "여", shear),
    ("snip",      "스닙",     "가위", "딜러",   "늑대 수인", "남", snip),
    ("needle",    "니들",     "가위", "지원",   "인간",      "여", needle),
    ("staple",    "스테이플", "가위", "전략가", "로봇",      "-",  staple),
]
