"""RPS 확장판: 캐릭터 12명 + 스킬 48개 + 총기 7종.

출력: out/guns/*.glb, out/characters/*.glb, out/skills/<캐릭터>/<스킬>.glb, out/models.json
스킬 모델 원점: 바닥(y=0) 중앙. 투사체류는 진행 방향이 +Z.
"""
import json, math, os
from build_models import (box, cyl, sph, ring, dome, humanoid, write_glb, Z,
                          GUNS, CHARS, BK, GM, SV, OR, WD)

rnd = lambda i, k=1.0: ((math.sin(i * 12.9898 + k * 78.233) * 43758.5453) % 1.0)  # 고정 의사난수

# ---------- 진영 팔레트 ----------
STONE, STONE_D, LAVA, CRYSTAL = "#8d9096", "#4b4f55", "#ff5a1f", "#7fe0d0"
PAPER, FOLD, BLUE, INK, CARD = "#efe9dc", "#d3cbb9", "#4d8cf0", "#24407a", "#b98a55"
RED, RED_D, STEEL, THREAD = "#cf3a3a", "#5a1d22", "#c9ced6", "#f2c94c"
GLOW_G, SMOKE = "#7cf0a0", "#9aa3b0"

# =========================================================
# 신규 캐릭터 6명
# =========================================================
def gem():  # 바위 · 지원
    body, dark = "#5f8792", "#33474e"
    parts, hip, top = humanoid(body, dark, CRYSTAL, leg_h=0.6, leg_w=0.13, torso=(0.44, 0.5, 0.28),
                               arm_len=0.48, arm_w=0.11, hand_r=0.07)
    ty = hip + 0.14 + 0.25
    parts.insert(0, box([0.44, 0.5, 0.28], (0, ty, 0), body, n="torso"))
    parts += [
        cyl(0, 0.09, 0.22, (0, ty + 0.05, 0.15), CRYSTAL, r=(90, 0, 0), seg=4, n="core_crystal"),
        cyl(0, 0.06, 0.2, (0.27, top + 0.06, 0), CRYSTAL, seg=4, n="shoulder_crystal_L"),
        cyl(0, 0.06, 0.2, (-0.27, top + 0.06, 0), CRYSTAL, seg=4, n="shoulder_crystal_R"),
        sph(0.19, (0, top + 0.2, 0), CRYSTAL, ws=4, hs=2, n="head"),
        box([0.2, 0.04, 0.04], (0, top + 0.2, 0.13), OR, n="visor"),
    ]
    parts += ring(0.24, 0.025, (0, top + 0.44, 0), OR, seg=10, n="halo")
    return parts

def quake():  # 바위 · 전략가(설치형)
    body, dark = "#6e6a64", "#3d3a36"
    parts, hip, top = humanoid(body, dark, "#a8a39a", leg_h=0.55, leg_w=0.18, torso=(0.6, 0.52, 0.38),
                               arm_len=0.5, arm_w=0.16, hand_r=0.1)
    ty = hip + 0.14 + 0.26
    parts.insert(0, box([0.6, 0.52, 0.38], (0, ty, 0), body, n="torso"))
    parts += [
        box([0.62, 0.08, 0.4], (0, ty - 0.12, 0), OR, n="tool_belt"),
        box([0.3, 0.36, 0.14], (0, ty + 0.02, -0.26), dark, n="backpack"),
        cyl(0.04, 0.04, 0.9, (0.18, ty + 0.15, -0.36), WD, r=(0, 0, 30), seg=6, n="hammer_handle"),
        box([0.32, 0.16, 0.16], (0.4, ty + 0.54, -0.36), STONE_D, r=(0, 0, 30), n="hammer_head"),
        box([0.3, 0.27, 0.28], (0, top + 0.15, 0), "#a8a39a", n="head"),
        cyl(0.16, 0.2, 0.12, (0, top + 0.33, 0), OR, seg=10, n="hard_hat"),
        cyl(0.24, 0.24, 0.02, (0, top + 0.28, 0.02), OR, seg=10, n="hat_brim"),
        box([0.22, 0.05, 0.03], (0, top + 0.16, 0.145), BK, n="visor"),
    ]
    return parts

def cardboard():  # 보 · 탱커
    tape, dark = "#e8d9a8", "#7a5a36"
    parts, hip, top = humanoid(CARD, dark, CARD, leg_h=0.55, leg_w=0.2, torso=(0.74, 0.66, 0.5),
                               arm_len=0.55, arm_w=0.19, hand_r=0.12)
    ty = hip + 0.14 + 0.33
    parts.insert(0, box([0.74, 0.66, 0.5], (0, ty, 0), CARD, n="torso"))
    parts += [
        box([0.76, 0.08, 0.52], (0, ty + 0.12, 0), tape, n="tape_h"),
        box([0.08, 0.68, 0.52], (0, ty, 0.001), tape, n="tape_v"),
        box([0.36, 0.04, 0.3], (0.2, top + 0.02, 0), CARD, r=(0, 0, -25), n="flap_L"),
        box([0.36, 0.04, 0.3], (-0.2, top + 0.02, 0), CARD, r=(0, 0, 25), n="flap_R"),
        box([0.3, 0.26, 0.28], (0, top + 0.16, 0), CARD, n="head"),
        box([0.24, 0.06, 0.03], (0, top + 0.18, 0.145), BLUE, n="visor"),
        box([0.12, 0.12, 0.02], (0.2, ty - 0.1, 0.26), BLUE, r=(0, 0, 45), n="arrow_mark"),
    ]
    return parts

def inkwell():  # 보 · 전략가(연막)
    coat, dark = "#2f3b5c", "#1b2236"
    parts, hip, top = humanoid(coat, dark, PAPER, leg_h=0.62, leg_w=0.13, torso=(0.44, 0.52, 0.28),
                               arm_len=0.52, arm_w=0.11, hand_r=0.065)
    ty = hip + 0.14 + 0.26
    parts.insert(0, box([0.44, 0.52, 0.28], (0, ty, 0), coat, n="torso"))
    parts += [
        cyl(0.27, 0.34, 0.5, (0, hip + 0.05, 0), coat, seg=8, n="coat_skirt"),
        box([0.06, 0.5, 0.02], (0, ty, 0.145), PAPER, n="collar_line"),
        cyl(0.15, 0.15, 0.22, (0, top + 0.14, 0), "#1e2a44", seg=8, n="head"),
        cyl(0.09, 0.15, 0.06, (0, top + 0.28, 0), INK, seg=8, n="head_neck"),
        cyl(0.07, 0.07, 0.06, (0, top + 0.33, 0), BLUE, seg=8, n="head_cap"),
        box([0.22, 0.04, 0.03], (0, top + 0.15, 0.15), BLUE, n="visor"),
        box([0.05, 0.55, 0.02], (0.12, top + 0.15, -0.2), PAPER, r=(-20, 0, -15), n="quill"),
    ]
    return parts

def staple():  # 가위 · 전략가(덫)
    body, dark = "#8e959e", "#3a3f47"
    parts, hip, top = humanoid(body, dark, STEEL, leg_h=0.6, leg_w=0.15, torso=(0.5, 0.52, 0.32),
                               arm_len=0.5, arm_w=0.13, hand_r=0.075)
    ty = hip + 0.14 + 0.26
    parts.insert(0, box([0.5, 0.52, 0.32], (0, ty, 0), body, n="torso"))
    parts += [
        box([0.52, 0.18, 0.34], (0, ty + 0.12, 0), RED, n="chest_band"),
        box([0.26, 0.14, 0.38], (0, top + 0.1, 0), dark, n="head_base"),
        box([0.24, 0.1, 0.4], (0, top + 0.22, 0.01), RED, r=(-8, 0, 0), n="head_lid"),
        box([0.2, 0.04, 0.03], (0, top + 0.1, 0.195), THREAD, n="visor"),
    ]
    for side, x in (("L", 0.3), ("R", -0.3)):
        parts += [box([0.03, 0.14, 0.03], (x, top + 0.07, 0.06), STEEL, n=f"staple_{side}_a"),
                  box([0.03, 0.14, 0.03], (x, top + 0.07, -0.06), STEEL, n=f"staple_{side}_b"),
                  box([0.03, 0.03, 0.15], (x, top + 0.14, 0), STEEL, n=f"staple_{side}_c")]
    return parts

def needle():  # 가위 · 지원
    body, dark = "#b8343c", "#4a171c"
    parts, hip, top = humanoid(body, dark, STEEL, leg_h=0.62, leg_w=0.12, torso=(0.4, 0.5, 0.26),
                               arm_len=0.5, arm_w=0.1, hand_r=0.065)
    ty = hip + 0.14 + 0.25
    parts.insert(0, box([0.4, 0.5, 0.26], (0, ty, 0), body, n="torso"))
    parts += [
        box([0.42, 0.06, 0.28], (0, ty + 0.06, 0), THREAD, r=(0, 0, 30), n="sash"),
        cyl(0.09, 0.09, 0.12, (0.16, hip + 0.1, 0.15), THREAD, r=(0, 0, 90), seg=10, n="spool"),
        sph(0.15, (0, top + 0.15, 0), STEEL, ws=8, hs=6, n="head"),
        box([0.2, 0.045, 0.06], (0, top + 0.16, 0.12), GLOW_G, n="visor"),
        cyl(0.012, 0.012, 1.1, (-0.1, ty + 0.2, -0.18), STEEL, r=(0, 0, 18), seg=6, n="needle_staff"),
        cyl(0, 0.012, 0.12, (-0.27, ty + 0.78, -0.18), STEEL, r=(0, 0, 18), seg=6, n="needle_tip"),
    ]
    parts += ring(0.04, 0.012, (0.07, ty - 0.33, -0.18), STEEL, seg=8, plane="xy", n="needle_eye")
    return parts

NEW_CHARS = [
    ("gem",       "젬",     "바위", "지원",   gem),
    ("quake",     "퀘이크", "바위", "전략가", quake),
    ("cardboard", "카드보드", "보",  "탱커",   cardboard),
    ("inkwell",   "잉크웰", "보",   "전략가", inkwell),
    ("staple",    "스테이플", "가위", "전략가", staple),
    ("needle",    "니들",   "가위", "지원",   needle),
]
ROLE_FIX = {"boulder": "탱커", "pebble": "딜러", "origami": "딜러", "scroll": "지원", "shear": "탱커", "snip": "딜러"}

# =========================================================
# 스킬 모델 (48)
# =========================================================
# ---- 볼더 (바위 탱커)
def rock_bulwark():
    p = [box([1.6, 1.1, 0.12], (0, 0.75, 0), STONE, n="slab", a=0.85),
         box([1.7, 0.1, 0.18], (0, 1.32, 0), STONE_D, n="frame_top"),
         box([1.7, 0.1, 0.18], (0, 0.18, 0), STONE_D, n="frame_bottom"),
         box([0.12, 0.6, 0.2], (0, 0.75, -0.1), STONE_D, n="handle_mount"),
         box([0.5, 0.12, 0.14], (0, 0.75, 0.07), OR, n="emblem")]
    for i, x in enumerate((-0.55, 0.55)):
        p.append(box([0.08, 1.2, 0.2], (x, 0.75, 0), STONE_D, n=f"rib_{i}"))
    return p

def landslide_charge():
    p = [cyl(0, 0.35, 0.6, (0, 0.5, 0.35), STONE, r=Z, seg=6, n="ram_wedge"),
         box([0.8, 0.7, 0.3], (0, 0.5, -0.05), STONE_D, n="ram_body"),
         box([0.82, 0.12, 0.32], (0, 0.5, -0.05), OR, n="ram_band")]
    for i in range(5):
        p.append(box([0.6 - i * 0.1, 0.04, 0.3], (0, 0.15 + i * 0.18, -0.45 - i * 0.12), SMOKE, n=f"speed_line_{i}", a=0.5))
    return p

def magma_slug():
    p = [cyl(0, 0.16, 0.5, (0, 0.5, 0.25), LAVA, r=Z, seg=6, n="core"),
         cyl(0.16, 0.08, 0.4, (0, 0.5, -0.2), OR, r=Z, seg=6, n="tail")]
    for i in range(6):
        a = i * 60
        p.append(box([0.06, 0.06, 0.3], (0.2 * math.cos(math.radians(a)), 0.5 + 0.2 * math.sin(math.radians(a)), -0.35), LAVA, n=f"ember_{i}", a=0.7))
    return p

def earth_rift():
    p = []
    for i in range(9):
        ang = math.radians(-35 + i * 70 / 8)
        for j in range(3):
            d = 0.6 + j * 0.55
            h = 0.25 + 0.35 * rnd(i, j)
            p.append(cyl(0, 0.13, h, (d * math.sin(ang), h / 2, d * math.cos(ang)), STONE if (i + j) % 2 else STONE_D, seg=5, r=(rnd(j, i) * 20 - 10, 0, 0), n=f"spike_{i}_{j}"))
    p.append(box([0.16, 0.02, 2.0], (0, 0.01, 1.1), LAVA, n="fissure"))
    p.append(cyl(0.3, 0.3, 0.06, (0, 0.03, 0), OR, seg=8, n="impact"))
    return p

# ---- 페블 (바위 딜러)
def gravel_blink():
    p = []
    for i in range(3):
        z = i * 0.6
        p += ring(0.22, 0.03, (0, 0.03, z), OR, seg=8, n=f"pad_{i}", a=0.9 - i * 0.25)
        p.append(cyl(0.12, 0.12, 0.02, (0, 0.02, z), STONE, seg=8, n=f"pad_core_{i}", a=0.9 - i * 0.25))
    p.append(cyl(0, 0.12, 0.2, (0, 0.05, 1.55), OR, r=(90, 0, 0), seg=3, n="arrow"))
    return p

def rewind():
    return [cyl(0.2, 0.2, 0.04, (0, 0.02, 0), STONE_D, seg=8, n="base"),
            cyl(0.2, 0.2, 0.04, (0, 0.74, 0), STONE_D, seg=8, n="top"),
            cyl(0.02, 0.16, 0.34, (0, 0.21, 0), "#e8c98a", seg=8, n="glass_low", a=0.6),
            cyl(0.16, 0.02, 0.34, (0, 0.55, 0), "#e8c98a", seg=8, n="glass_high", a=0.6),
            cyl(0.1, 0.13, 0.1, (0, 0.09, 0), OR, seg=8, n="sand_pile"),
            cyl(0.015, 0.015, 0.7, (0.17, 0.38, 0), STONE, seg=6, n="post_a"),
            cyl(0.015, 0.015, 0.7, (-0.17, 0.38, 0), STONE, seg=6, n="post_b"),
            ] + ring(0.32, 0.025, (0, 0.38, 0), OR, seg=12, plane="xy", a0=30, a1=330, n="rewind_arc")

def recon_pebble():
    p = [cyl(0.012, 0.012, 0.7, (0, 0.4, 0), WD, r=Z, seg=6, n="shaft"),
         sph(0.06, (0, 0.4, 0.38), STONE, ws=6, hs=4, n="sensor_head"),
         box([0.12, 0.004, 0.08], (0, 0.4, -0.3), OR, n="fletch_h"),
         box([0.004, 0.12, 0.08], (0, 0.4, -0.3), OR, n="fletch_v")]
    p += ring(0.35, 0.015, (0, 0.4, 0.38), OR, seg=12, plane="xy", n="pulse_1", a=0.6)
    p += ring(0.55, 0.012, (0, 0.4, 0.38), OR, seg=16, plane="xy", n="pulse_2", a=0.3)
    return p

def sticky_charge():
    p = [sph(0.16, (0, 0.2, 0), STONE_D, ws=8, hs=6, n="shell"),
         cyl(0.04, 0.04, 0.06, (0, 0.38, 0), BK, seg=8, n="cap"),
         sph(0.035, (0, 0.43, 0), LAVA, ws=6, hs=4, n="blink")]
    for i in range(8):
        a = math.radians(i * 45)
        p.append(cyl(0, 0.035, 0.1, (0.17 * math.cos(a), 0.2, 0.17 * math.sin(a)), OR, r=(0, -i * 45, -90), seg=4, n=f"spike_{i}"))
    return p

# ---- 젬 (바위 지원)
def mend_crystal():
    p = [sph(0.18, (0, 0.7, 0), CRYSTAL, ws=4, hs=2, n="crystal"),
         cyl(0.04, 0.04, 0.03, (0, 0.02, 0), CRYSTAL, seg=8, n="shadow_marker", a=0.5)]
    p += ring(0.3, 0.02, (0, 0.7, 0), OR, seg=12, n="orbit")
    for i in range(3):
        a = math.radians(i * 120)
        p.append(sph(0.04, (0.3 * math.cos(a), 0.7, 0.3 * math.sin(a)), GLOW_G, ws=4, hs=2, n=f"spark_{i}"))
    return p

def amp_shard():
    p = [cyl(0.25, 0.3, 0.08, (0, 0.04, 0), STONE_D, seg=6, n="base")]
    spec = [(0, 0, 0.75, 0.09), (0.12, 0.06, 0.5, 0.06), (-0.1, 0.08, 0.45, 0.06), (0.04, -0.12, 0.55, 0.07), (-0.08, -0.08, 0.35, 0.05)]
    for i, (x, z, h, r) in enumerate(spec):
        p.append(cyl(0, r, h, (x, 0.08 + h / 2, z), CRYSTAL if i else "#ffb27a", seg=4, r=(z * 80, 0, -x * 80), n=f"shard_{i}"))
    p.append(cyl(0.015, 0.015, 0.8, (0, 1.2, 0), "#ffb27a", seg=6, n="amp_beam", a=0.6))
    return p

def cleanse_bell():
    return [cyl(0.02, 0.02, 0.2, (0, 0.82, 0), OR, seg=6, n="hanger"),
            cyl(0.08, 0.2, 0.3, (0, 0.57, 0), CRYSTAL, seg=8, n="bell"),
            cyl(0.21, 0.21, 0.04, (0, 0.41, 0), OR, seg=8, n="bell_rim"),
            sph(0.05, (0, 0.36, 0), STONE_D, ws=6, hs=4, n="clapper"),
            ] + ring(0.4, 0.015, (0, 0.5, 0), CRYSTAL, seg=14, n="chime_wave", a=0.5)

def crystal_sanctum():
    p = [cyl(0.12, 0.2, 1.4, (0, 0.7, 0), STONE_D, seg=6, n="trunk")]
    for i in range(7):
        a = math.radians(i * 360 / 7)
        r, h = 0.45 + 0.15 * rnd(i), 1.2 + 0.4 * rnd(i, 2)
        p.append(cyl(0, 0.12, 0.6, (r * math.cos(a), h, r * math.sin(a)), CRYSTAL, seg=4, r=(math.sin(a) * 25, 0, -math.cos(a) * 25), n=f"canopy_{i}"))
    p.append(sph(0.25, (0, 1.65, 0), CRYSTAL, ws=4, hs=2, n="crown"))
    p += ring(1.3, 0.05, (0, 0.02, 0), GLOW_G, seg=20, n="heal_zone", a=0.6)
    p.append(cyl(1.25, 1.25, 0.02, (0, 0.01, 0), GLOW_G, seg=20, n="heal_floor", a=0.2))
    return p

# ---- 퀘이크 (바위 전략가)
def rock_turret():
    p = [cyl(0.25, 0.32, 0.12, (0, 0.06, 0), STONE_D, seg=6, n="base"),
         cyl(0.07, 0.07, 0.3, (0, 0.27, 0), GM, seg=8, n="post"),
         box([0.32, 0.22, 0.34], (0, 0.5, 0), STONE, n="head"),
         box([0.24, 0.06, 0.04], (0, 0.53, 0.18), OR, n="eye"),
         cyl(0.035, 0.035, 0.32, (0.08, 0.48, 0.32), BK, r=Z, seg=8, n="barrel_L"),
         cyl(0.035, 0.035, 0.32, (-0.08, 0.48, 0.32), BK, r=Z, seg=8, n="barrel_R")]
    for i in range(3):
        a = i * 120
        p.append(box([0.06, 0.06, 0.4], (0.25 * math.sin(math.radians(a)), 0.05, 0.25 * math.cos(math.radians(a))), STONE_D, r=(0, a, 0), n=f"leg_{i}"))
    return p

def quake_trap():
    p = [cyl(0.24, 0.26, 0.04, (0, 0.02, 0), GM, seg=10, n="plate"),
         cyl(0.06, 0.06, 0.03, (0, 0.05, 0), OR, seg=8, n="trigger")]
    p += ring(0.24, 0.03, (0, 0.18, 0), SV, seg=8, plane="xy", a0=0, a1=180, n="jaw_a")
    p += ring(0.24, 0.03, (0, 0.18, 0), SV, seg=8, plane="yz", a0=-90, a1=90, n="jaw_b")
    for i in range(6):
        a = math.radians(15 + i * 30)
        p.append(cyl(0, 0.02, 0.06, (0.24 * math.cos(a), 0.18 + 0.24 * math.sin(a) - 0.04, 0), STEEL, r=(0, 0, 180), seg=4, n=f"tooth_{i}"))
    return p

def overheat():
    p = [box([0.42, 0.5, 0.3], (0, 0.3, 0), STONE_D, n="furnace"),
         box([0.3, 0.2, 0.02], (0, 0.3, 0.155), LAVA, n="grate_glow"),
         cyl(0.06, 0.06, 0.3, (0.1, 0.7, -0.05), GM, seg=8, n="chimney_a"),
         cyl(0.06, 0.06, 0.22, (-0.1, 0.66, -0.05), GM, seg=8, n="chimney_b")]
    for i in range(3):
        p.append(box([0.32, 0.03, 0.025], (0, 0.22 + i * 0.08, 0.17), BK, n=f"grate_bar_{i}"))
    for i in range(4):
        p.append(sph(0.07 + i * 0.02, (0.1 + 0.03 * i, 0.9 + i * 0.13, -0.05), SMOKE, ws=6, hs=4, n=f"heat_puff_{i}", a=0.5))
    return p

def lava_flow():
    p = [cyl(1.0, 1.05, 0.04, (0, 0.02, 0), LAVA, seg=10, n="pool", a=0.95),
         cyl(0.6, 0.7, 0.05, (0.25, 0.03, 0.15), OR, seg=8, n="hot_core")]
    for i in range(8):
        a = math.radians(i * 45 + 10)
        r = 0.85 + 0.2 * rnd(i)
        p.append(sph(0.1 + 0.08 * rnd(i, 3), (r * math.cos(a), 0.05, r * math.sin(a)), STONE_D, ws=5, hs=3, n=f"crust_{i}"))
    for i in range(5):
        p.append(sph(0.05, (0.6 * rnd(i, 5) - 0.3, 0.12 + 0.1 * i, 0.6 * rnd(i, 6) - 0.3), OR, ws=5, hs=3, n=f"bubble_{i}", a=0.8))
    return p

# ---- 오리가미 (보 딜러)
def paper_updraft():
    p = [cyl(0.4, 0.42, 0.03, (0, 0.015, 0), BLUE, seg=12, n="launch_pad", a=0.7)]
    for i in range(14):
        a = i * 50
        y = 0.15 + i * 0.12
        r = 0.25 + 0.05 * math.sin(i)
        p.append(box([0.18, 0.02, 0.1], (r * math.cos(math.radians(a)), y, r * math.sin(math.radians(a))), PAPER if i % 2 else FOLD, r=(15, -a, 25), n=f"strip_{i}"))
    return p

def paper_dash():
    p = []
    for i in range(4):
        z = -i * 0.35
        a = 0.95 - i * 0.2
        p.append(box([0.5, 0.03, 0.12], (0.18, 0.4, z), BLUE if i == 0 else PAPER, r=(0, 35, 0), n=f"chevron_{i}_L", a=a))
        p.append(box([0.5, 0.03, 0.12], (-0.18, 0.4, z), BLUE if i == 0 else PAPER, r=(0, -35, 0), n=f"chevron_{i}_R", a=a))
    return p

def crane_scout():
    return [box([0.3, 0.03, 0.25], (0.17, 0.62, 0), PAPER, r=(0, 0, 18), n="wing_L"),
            box([0.3, 0.03, 0.25], (-0.17, 0.62, 0), PAPER, r=(0, 0, -18), n="wing_R"),
            cyl(0, 0.07, 0.3, (0, 0.6, 0.2), FOLD, r=(90, 0, 0), seg=4, n="body_front"),
            cyl(0.07, 0, 0.3, (0, 0.6, -0.15), FOLD, r=(90, 0, 0), seg=4, n="body_back"),
            cyl(0, 0.025, 0.22, (0, 0.72, 0.36), PAPER, r=(40, 0, 0), seg=4, n="neck"),
            cyl(0, 0.025, 0.2, (0, 0.7, -0.33), PAPER, r=(-50, 0, 0), seg=4, n="tail"),
            sph(0.03, (0, 0.62, 0.36), BLUE, ws=6, hs=4, n="lens"),
            cyl(0, 0.35, 0.6, (0, 0.3, 0.6), BLUE, r=(-60, 0, 0), seg=8, n="scan_cone", a=0.18)]

def shuriken_storm():
    p = []
    for i in range(5):
        x = (i - 2) * 0.32
        y, z = 0.6 + 0.08 * abs(i - 2), -0.12 * abs(i - 2)
        for k in range(4):
            p.append(cyl(0, 0.05, 0.16, (x + 0.07 * math.cos(math.radians(k * 90)), y + 0.07 * math.sin(math.radians(k * 90)), z),
                         PAPER if k % 2 else BLUE, r=(0, 0, k * 90 - 90), seg=4, n=f"shuriken_{i}_blade_{k}"))
        p.append(cyl(0.03, 0.03, 0.02, (x, y, z), INK, r=Z, seg=6, n=f"shuriken_{i}_hub"))
    return p

# ---- 스크롤 (보 지원)
def mending_seal():
    p = [cyl(0.9, 0.9, 0.02, (0, 0.01, 0), GLOW_G, seg=16, n="field", a=0.25),
         box([0.6, 0.03, 0.16], (0, 0.03, 0), GLOW_G, n="cross_h"),
         box([0.16, 0.03, 0.6], (0, 0.03, 0), GLOW_G, n="cross_v")]
    p += ring(0.9, 0.05, (0, 0.03, 0), "#e8dcc0", seg=16, n="seal_rim")
    p += ring(0.6, 0.02, (0, 0.03, 0), INK, seg=12, n="ink_ring")
    return p

def ward_talisman():
    return [box([0.16, 0.5, 0.01], (0, 0.6, 0), "#e8dcc0", r=(0, 0, 8), n="paper_slip"),
            box([0.04, 0.3, 0.012], (0, 0.62, 0), INK, r=(0, 0, 8), n="ink_glyph"),
            box([0.1, 0.03, 0.012], (0, 0.7, 0), INK, r=(0, 0, 8), n="ink_bar"),
            sph(0.05, (0.04, 0.88, 0), "#c23b3b", ws=6, hs=4, n="seal_stamp"),
            ] + ring(0.25, 0.012, (0, 0.6, 0), GLOW_G, seg=12, plane="xy", n="glow", a=0.6)

def undying_lantern():
    return [cyl(0.03, 0.04, 1.0, (0, 0.5, 0), "#7a4e2c", seg=6, n="pole"),
            box([0.3, 0.03, 0.03], (0.1, 1.0, 0), "#7a4e2c", n="arm"),
            cyl(0.1, 0.12, 0.24, (0.22, 0.82, 0), "#e8dcc0", seg=8, n="lantern", a=0.85),
            sph(0.06, (0.22, 0.82, 0), GLOW_G, ws=6, hs=4, n="flame"),
            cyl(0.06, 0.12, 0.05, (0.22, 0.96, 0), INK, seg=8, n="lantern_cap"),
            cyl(0.25, 0.3, 0.06, (0, 0.03, 0), INK, seg=8, n="base"),
            ] + ring(1.0, 0.04, (0, 0.03, 0), GLOW_G, seg=18, n="zone", a=0.5)

def grand_scroll():
    roll = "#7a4e2c"
    return [cyl(0.08, 0.08, 1.4, (0, 1.5, 0), roll, r=(0, 0, 90), seg=10, n="roll_top"),
            cyl(0.1, 0.1, 1.5, (0, 0.1, 0.25), roll, r=(0, 0, 90), seg=10, n="roll_bottom"),
            box([1.3, 1.45, 0.01], (0, 0.8, 0.12), "#e8dcc0", r=(10, 0, 0), n="sheet", a=0.92),
            box([0.08, 0.9, 0.012], (-0.3, 0.85, 0.135), INK, r=(10, 0, 0), n="ink_stroke_1"),
            box([0.08, 0.6, 0.012], (0.0, 0.95, 0.12), INK, r=(10, 0, 0), n="ink_stroke_2"),
            box([0.08, 0.75, 0.012], (0.3, 0.88, 0.13), INK, r=(10, 0, 0), n="ink_stroke_3"),
            box([1.5, 1.6, 0.02], (0, 0.8, 0.4), BLUE, r=(10, 0, 0), n="team_shield", a=0.2)]

# ---- 카드보드 (보 탱커)
def box_fort():
    p = dome(1.2, (0, 0, 0), CARD, layers=4, seg=12, n="dome", a=0.45)
    p += ring(1.2, 0.08, (0, 0.04, 0), "#7a5a36", seg=16, n="base_ring")
    p.append(box([0.4, 0.4, 0.4], (0, 0.2, 0), CARD, n="emitter_box"))
    p.append(box([0.42, 0.06, 0.42], (0, 0.3, 0), "#e8d9a8", n="emitter_tape"))
    return p

def crate_roll():
    p = [sph(0.4, (0, 0.4, 0), CARD, ws=8, hs=6, n="ball"),
         box([0.84, 0.08, 0.08], (0, 0.4, 0), "#e8d9a8", n="tape_ring_x")]
    p += ring(0.41, 0.06, (0, 0.4, 0), "#e8d9a8", seg=12, plane="yz", n="tape_ring")
    for i in range(3):
        p.append(box([0.5 - i * 0.1, 0.03, 0.08], (0, 0.15 + i * 0.25, -0.6 - i * 0.1), SMOKE, n=f"speed_{i}", a=0.5))
    return p

def tape_hook():
    p = [box([0.08, 0.3, 0.05], (0, 0.55, 0.9), STEEL, n="hook_shank")]
    p += ring(0.12, 0.05, (0, 0.4, 0.9), STEEL, seg=6, plane="yz", a0=180, a1=360, n="hook_curve")
    p.append(cyl(0, 0.04, 0.1, (0, 0.5, 1.02), STEEL, r=(0, 0, 0), seg=4, n="hook_tip"))
    for i in range(7):
        z = 0.75 - i * 0.12
        p.append(box([0.06, 0.02, 0.1] if i % 2 else [0.02, 0.06, 0.1], (0, 0.7, z), "#e8d9a8", n=f"tape_link_{i}"))
    p.append(cyl(0.12, 0.12, 0.1, (0, 0.7, -0.1), CARD, r=(0, 0, 90), seg=10, n="tape_spool"))
    return p

def parcel_drop():
    p = []
    pts = [(0, 0), (0.7, 0.3), (-0.6, 0.5), (0.3, -0.7), (-0.4, -0.5), (0.9, -0.4), (-0.9, -0.1)]
    for i, (x, z) in enumerate(pts):
        p += [box([0.24, 0.16, 0.24], (x, 0.08, z), CARD, r=(0, 20 * i, 0), n=f"parcel_{i}"),
              box([0.25, 0.04, 0.25], (x, 0.12, z), "#e8d9a8", r=(0, 20 * i, 0), n=f"parcel_{i}_tape"),
              sph(0.035, (x, 0.18, z), "#ff4040", ws=6, hs=4, n=f"parcel_{i}_light")]
    p += ring(1.3, 0.03, (0, 0.01, 0), BLUE, seg=18, n="drop_zone", a=0.5)
    return p

# ---- 잉크웰 (보 전략가)
def ink_cloud():
    p = [cyl(0.08, 0.08, 0.22, (0, 0.11, 0), "#1e2a44", seg=8, n="canister"),
         cyl(0.085, 0.085, 0.04, (0, 0.2, 0), BLUE, seg=8, n="canister_band")]
    for i in range(9):
        a = math.radians(i * 40)
        r = 0.35 * rnd(i)
        p.append(sph(0.3 + 0.15 * rnd(i, 2), (r * math.cos(a), 0.55 + 0.35 * rnd(i, 4), r * math.sin(a)), INK, ws=6, hs=4, n=f"cloud_{i}", a=0.55))
    return p

def ink_puddle():
    p = [cyl(0.8, 0.85, 0.02, (0, 0.01, 0), INK, seg=10, n="puddle", a=0.9),
         cyl(0.35, 0.4, 0.025, (0.6, 0.012, 0.4), INK, seg=8, n="splash_a", a=0.9),
         cyl(0.25, 0.3, 0.025, (-0.55, 0.012, -0.5), INK, seg=8, n="splash_b", a=0.9)]
    for i in range(5):
        a = math.radians(i * 72)
        p.append(sph(0.05, (0.5 * math.cos(a), 0.06, 0.5 * math.sin(a)), BLUE, ws=5, hs=3, n=f"drip_{i}", a=0.7))
    return p

def ink_portal():
    p = ring(0.55, 0.08, (0, 0.65, 0), INK, seg=14, plane="xy", n="portal_ring")
    p.append(cyl(0.5, 0.5, 0.02, (0, 0.65, 0), "#1b2236", r=Z, seg=14, n="portal_void", a=0.85))
    p.append(cyl(0.3, 0.3, 0.025, (0, 0.65, 0), BLUE, r=Z, seg=14, n="portal_core", a=0.5))
    p.append(cyl(0.4, 0.45, 0.04, (0, 0.02, 0), INK, seg=10, n="base_puddle", a=0.8))
    return p

def brush_wall():
    p = []
    for i in range(10):
        x = (i - 4.5) * 0.3
        h = 1.4 + 0.25 * math.sin(i * 1.3)
        p.append(box([0.32, h, 0.12], (x, h / 2, 0.06 * math.sin(i)), INK, r=(0, 0, 3 * math.sin(i * 2)), n=f"stroke_{i}", a=0.85))
    p += [cyl(0.05, 0.05, 1.0, (1.75, 1.6, 0), "#7a4e2c", r=(0, 0, 35), seg=8, n="brush_handle"),
          cyl(0.1, 0.03, 0.3, (1.45, 1.17, 0), BK, r=(0, 0, 35), seg=8, n="brush_tip")]
    return p

# ---- 시어 (가위 탱커)
def spike_guard():
    p = [box([0.9, 1.0, 0.1], (0, 0.6, 0), STEEL, n="shield"),
         box([0.95, 0.1, 0.14], (0, 1.1, 0), RED, n="rim_top"),
         box([0.95, 0.1, 0.14], (0, 0.1, 0), RED, n="rim_bottom"),
         cyl(0.1, 0.1, 0.06, (0, 0.6, 0.07), RED_D, r=Z, seg=8, n="boss")]
    for i in range(3):
        for j in range(2):
            p.append(cyl(0, 0.04, 0.18, (-0.28 + i * 0.28, 0.4 + j * 0.4, 0.13), STEEL, r=Z, seg=4, n=f"spike_{i}_{j}"))
    return p

def cleave_leap():
    p = ring(0.75, 0.06, (0, 0.85, 0), STEEL, seg=10, plane="yz", a0=-30, a1=150, w=0.02, n="slash_arc")
    p += ring(0.65, 0.04, (0, 0.85, 0), RED, seg=10, plane="yz", a0=-20, a1=140, w=0.02, n="slash_trail", a=0.6)
    p.append(cyl(0.6, 0.6, 0.02, (0, 0.01, 0.3), RED, seg=12, n="impact", a=0.4))
    return p

def blade_fence():
    p = [box([2.2, 0.08, 0.2], (0, 0.04, 0), RED_D, n="rail")]
    for i in range(9):
        x = (i - 4) * 0.25
        p.append(box([0.05, 0.6, 0.02], (x, 0.36, 0), STEEL, r=(0, 0, 12 if i % 2 else -12), n=f"blade_{i}"))
    return p

def blade_rain():
    p = [cyl(1.4, 1.4, 0.02, (0, 0.01, 0), RED, seg=16, n="zone", a=0.25)]
    p += ring(1.4, 0.04, (0, 0.02, 0), RED, seg=18, n="zone_rim")
    for i in range(16):
        a = math.radians(i * 137.5)
        r = 1.25 * math.sqrt((i + 0.5) / 16)
        y = 0.2 + 1.1 * rnd(i)
        p.append(box([0.05, 0.35, 0.015], (r * math.cos(a), y, r * math.sin(a)), STEEL, r=(0, i * 30, 0), n=f"blade_{i}"))
        p.append(cyl(0, 0.03, 0.08, (r * math.cos(a), y - 0.21, r * math.sin(a)), STEEL, r=(180, 0, 0), seg=4, n=f"blade_{i}_tip"))
    return p

# ---- 스닙 (가위 딜러)
def gale_cut():
    p = [box([0.05, 0.08, 0.85], (0, 0.6, 0.1), STEEL, n="blade"),
         cyl(0, 0.03, 0.1, (0, 0.6, 0.57), STEEL, r=Z, seg=4, n="blade_tip"),
         box([0.15, 0.03, 0.04], (0, 0.6, -0.34), RED_D, n="guard"),
         cyl(0.025, 0.025, 0.2, (0, 0.6, -0.46), RED, r=Z, seg=6, n="handle")]
    for i in range(4):
        p.append(box([0.02, 0.3, 0.6 - i * 0.12], (0.12 + i * 0.1, 0.6, -0.2 - i * 0.1), RED, n=f"after_image_{i}", a=0.5 - i * 0.1))
    return p

def deflect():
    p = ring(0.45, 0.04, (0, 0.7, 0), STEEL, seg=12, plane="xy", w=0.02, n="deflect_ring")
    for i in range(4):
        p.append(box([0.06, 0.4, 0.015], (0, 0.7, 0), STEEL if i % 2 else RED, r=(0, 0, i * 45), n=f"spoke_{i}", a=0.8))
    p.append(cyl(0.06, 0.06, 0.04, (0, 0.7, 0), RED_D, r=Z, seg=8, n="hub"))
    p.append(cyl(0.02, 0.02, 0.3, (0.3, 0.9, 0.3), "#ffd166", r=(30, 0, -40), seg=6, n="bounced_bolt"))
    return p

def phase_beacon():
    p = [cyl(0.14, 0.16, 0.04, (0, 0.02, 0), RED_D, seg=10, n="disc"),
         cyl(0.06, 0.06, 0.05, (0, 0.06, 0), "#b26bff", seg=8, n="core"),
         cyl(0.18, 0.18, 0.8, (0, 0.45, 0), "#b26bff", seg=10, n="phase_beam", a=0.2)]
    p += ring(0.16, 0.02, (0, 0.04, 0), STEEL, seg=10, n="rim")
    return p

def twin_edge():
    p = []
    for side, s in (("L", 1), ("R", -1)):
        p += [box([0.06, 1.1, 0.02], (0.12 * s, 0.8, 0), STEEL, r=(0, 0, -22 * s), n=f"blade_{side}"),
              box([0.07, 1.1, 0.01], (0.135 * s, 0.8, 0.012), RED, r=(0, 0, -22 * s), n=f"edge_glow_{side}", a=0.6)]
        p += ring(0.1, 0.025, (-0.08 * s, 0.22, 0), RED_D, seg=8, plane="xy", n=f"handle_ring_{side}")
    p.append(cyl(0.05, 0.05, 0.05, (0, 0.38, 0), BK, r=Z, seg=8, n="pivot"))
    return p

# ---- 스테이플 (가위 전략가)
def staple_sentry():
    return [box([0.22, 0.3, 0.06], (0, 0.15, 0), GM, n="wall_plate"),
            box([0.18, 0.12, 0.2], (0, 0.22, 0.12), RED, n="housing"),
            sph(0.05, (0, 0.24, 0.23), "#7fdcff", ws=6, hs=4, n="lens"),
            box([0.06, 0.015, 0.12], (0.04, 0.3, 0.12), STEEL, n="staple_mag"),
            cyl(0, 0.3, 0.7, (0, 0.24, 0.6), "#7fdcff", r=(-90, 0, 0), seg=8, n="view_cone", a=0.15)]

def wire_snare():
    p = []
    for i, x in enumerate((-0.7, 0.7)):
        p += [cyl(0.04, 0.05, 0.35, (x, 0.175, 0), GM, seg=6, n=f"post_{i}"),
              sph(0.04, (x, 0.32, 0), RED, ws=6, hs=4, n=f"post_{i}_emitter")]
    p.append(box([1.4, 0.012, 0.012], (0, 0.3, 0), "#ff4060", n="wire", a=0.8))
    p.append(box([1.4, 0.06, 0.06], (0, 0.3, 0), "#ff4060", n="wire_glow", a=0.2))
    return p

def alarm_bot():
    return [sph(0.16, (0, 0.2, 0), STEEL, ws=8, hs=6, n="body"),
            box([0.2, 0.05, 0.05], (0, 0.24, 0.13), RED, n="eye_band"),
            cyl(0.012, 0.012, 0.22, (0, 0.46, 0), GM, seg=6, n="antenna"),
            sph(0.035, (0, 0.58, 0), "#ff4060", ws=6, hs=4, n="beacon"),
            cyl(0.04, 0.05, 0.06, (0.09, 0.03, 0.06), BK, seg=6, n="wheel_a"),
            cyl(0.04, 0.05, 0.06, (-0.09, 0.03, 0.06), BK, seg=6, n="wheel_b"),
            cyl(0.04, 0.05, 0.06, (0, 0.03, -0.1), BK, seg=6, n="wheel_c"),
            ] + ring(0.6, 0.02, (0, 0.02, 0), "#ff4060", seg=14, n="vuln_zone", a=0.5)

def steel_lockdown():
    p = [cyl(0.25, 0.3, 0.1, (0, 0.05, 0), GM, seg=8, n="base"),
         cyl(0.08, 0.1, 0.9, (0, 0.55, 0), STEEL, seg=8, n="spine"),
         sph(0.1, (0, 1.05, 0), RED, ws=8, hs=6, n="core")]
    for i, (y, R) in enumerate(((0.35, 0.22), (0.6, 0.18), (0.85, 0.14))):
        p += ring(R, 0.04, (0, y, 0), RED if i % 2 else STEEL, seg=10, n=f"coil_{i}")
    p += ring(1.6, 0.04, (0, 0.02, 0), RED, seg=22, n="lock_radius", a=0.5)
    return p

# ---- 니들 (가위 지원)
def thread_tether():
    p = [cyl(0.1, 0.1, 0.18, (0, 0.6, 0), THREAD, r=(0, 0, 90), seg=10, n="spool"),
         cyl(0.14, 0.14, 0.03, (0.105, 0.6, 0), "#7a4e2c", r=(0, 0, 90), seg=10, n="spool_cap_a"),
         cyl(0.14, 0.14, 0.03, (-0.105, 0.6, 0), "#7a4e2c", r=(0, 0, 90), seg=10, n="spool_cap_b")]
    for i in range(8):
        z = 0.2 + i * 0.15
        p.append(box([0.02, 0.02, 0.15], (0, 0.6 + 0.08 * math.sin(i * 0.9), z), GLOW_G if i % 2 else THREAD, n=f"beam_{i}"))
    return p

def sleep_dart():
    p = [cyl(0.015, 0.015, 0.5, (0, 0.5, 0), STEEL, r=Z, seg=6, n="needle"),
         cyl(0, 0.015, 0.08, (0, 0.5, 0.29), STEEL, r=Z, seg=6, n="needle_tip"),
         cyl(0.04, 0.04, 0.12, (0, 0.5, -0.2), "#9b7bff", r=Z, seg=8, n="vial", a=0.8),
         box([0.12, 0.005, 0.06], (0, 0.5, -0.3), THREAD, n="fin_h"),
         box([0.005, 0.12, 0.06], (0, 0.5, -0.3), THREAD, n="fin_v")]
    for i in range(3):
        p.append(sph(0.04 + i * 0.02, (0.1 + i * 0.06, 0.65 + i * 0.12, -0.1), "#9b7bff", ws=6, hs=4, n=f"zzz_{i}", a=0.5))
    return p

def stitch_grenade():
    p = [sph(0.13, (0, 0.13, 0), RED, ws=8, hs=6, n="shell"),
         cyl(0.04, 0.04, 0.06, (0, 0.28, 0), STEEL, seg=8, n="cap")]
    p += ring(0.135, 0.02, (0, 0.13, 0), THREAD, seg=10, n="stitch_band")
    p += ring(0.135, 0.02, (0, 0.13, 0), THREAD, seg=10, plane="yz", n="stitch_band_v")
    p += ring(0.7, 0.03, (0, 0.02, 0), GLOW_G, seg=14, n="ally_zone", a=0.5)
    return p

def nano_stitch():
    return [cyl(0.06, 0.06, 0.4, (0, 0.6, 0), "#d8f7e2", r=Z, seg=10, n="barrel", a=0.75),
            cyl(0.045, 0.045, 0.3, (0, 0.6, 0.01), GLOW_G, r=Z, seg=10, n="serum"),
            cyl(0.008, 0.008, 0.2, (0, 0.6, 0.3), STEEL, r=Z, seg=6, n="needle"),
            cyl(0.07, 0.07, 0.03, (0, 0.6, -0.21), RED, r=Z, seg=10, n="flange"),
            cyl(0.015, 0.015, 0.2, (0, 0.6, -0.32), STEEL, r=Z, seg=6, n="plunger"),
            cyl(0.05, 0.05, 0.02, (0, 0.6, -0.43), RED, r=Z, seg=10, n="plunger_cap"),
            ] + ring(0.25, 0.015, (0, 0.6, 0), THREAD, seg=12, plane="xy", n="boost_ring", a=0.7)

# ---------- 스킬 표 ----------
# (id, 키, 이름, 설명, 쿨타임, 모델 함수)
SKILLS = {
    "boulder": [
        ("rock_bulwark", "Q", "바위 방벽", "전방에 큰 돌 방벽을 세워 탄을 막는다. 사람은 통과할 수 있다. 내구도 1200.", "유지형", rock_bulwark),
        ("landslide_charge", "E", "산사태 돌진", "WASD 방향(대각선 포함)으로 질주하며 처음 닿은 적을 붙잡아 벽에 처박는다.", "8초", landslide_charge),
        ("magma_slug", "Shift", "용암 투척", "적을 관통하는 용암 덩어리를 던진다.", "6초", magma_slug),
        ("earth_rift", "궁", "대지 균열", "망치로 땅을 내리쳐 전방 부채꼴의 적을 쓰러뜨린다.", "궁극기", earth_rift),
    ],
    "pebble": [
        ("gravel_blink", "Q", "자갈 점멸", "이동 방향으로 짧게 순간이동한다. 3회 충전.", "3초/충전", gravel_blink),
        ("rewind", "E", "되감기", "3초 전 위치로 되돌아가고 체력이 가득 찬다.", "12초", rewind),
        ("recon_pebble", "Shift", "정찰 자갈", "꽂힌 곳 주변 적 위치를 팀에 공개하는 화살.", "25초", recon_pebble),
        ("sticky_charge", "궁", "점착 폭약", "적이나 벽에 붙는 폭탄을 던져 큰 폭발을 일으킨다.", "궁극기", sticky_charge),
    ],
    "gem": [
        ("mend_crystal", "Q", "치유 결정", "아군 머리 위에 붙어 지속 치유하는 결정.", "대상 전환", mend_crystal),
        ("amp_shard", "E", "증폭 파편", "설치한 파편 근처 아군의 공격력을 25% 올린다.", "14초", amp_shard),
        ("cleanse_bell", "Shift", "정화의 종", "아군 하나를 잠깐 무적으로 만들고 해로운 효과를 지운다.", "14초", cleanse_bell),
        ("crystal_sanctum", "궁", "수정 성소", "수정 나무를 세워 범위 아군을 크게 치유한다. 나무는 엄폐물 역할.", "궁극기", crystal_sanctum),
    ],
    "quake": [
        ("rock_turret", "Q", "바위 포탑", "적을 자동으로 쏘는 포탑을 설치한다.", "10초", rock_turret),
        ("quake_trap", "E", "지진 덫", "밟은 적을 1.5초 동안 묶는다.", "10초", quake_trap),
        ("overheat", "Shift", "과열 용광로", "잠시 방어력·공격 속도·이동 속도가 오른다.", "12초", overheat),
        ("lava_flow", "궁", "용암 분출", "주변에 용암 장판을 깔아 지속 피해를 준다.", "궁극기", lava_flow),
    ],
    "origami": [
        ("paper_updraft", "Q", "종이 상승", "종이 바람을 타고 높이 도약한다.", "8초", paper_updraft),
        ("paper_dash", "E", "접기 질주", "WASD 방향(대각선 포함)으로 짧게 대시한다. 처치 시 초기화.", "10초", paper_dash),
        ("crane_scout", "Shift", "종이학 정찰", "조종 가능한 종이학을 날려 맞춘 적을 표시한다.", "30초", crane_scout),
        ("shuriken_storm", "궁", "표창 폭풍", "정확한 종이 표창 5개를 얻는다. 처치하면 재충전.", "궁극기", shuriken_storm),
    ],
    "scroll": [
        ("mending_seal", "Q", "치유 인장", "바닥에 인장을 펼쳐 안에 있는 아군을 치유한다.", "12초", mending_seal),
        ("ward_talisman", "E", "수호 부적", "아군에게 붙어 일정량 피해를 대신 막는 부적.", "8초", ward_talisman),
        ("undying_lantern", "Shift", "불사의 등불", "등불 범위 안의 아군은 3초간 쓰러지지 않는다.", "22초", undying_lantern),
        ("grand_scroll", "궁", "대두루마리", "거대한 두루마리를 펼쳐 팀 전체에 보호막을 준다.", "궁극기", grand_scroll),
    ],
    "cardboard": [
        ("box_fort", "Q", "상자 요새", "주변을 감싸는 돔형 방벽을 던진다.", "12초", box_fort),
        ("crate_roll", "E", "상자 구르기", "공 형태로 변해 빠르게 굴러가며 적을 들이받는다. 구르는 중 점프 후 착지하면 주변 적에게 피해.", "전환", crate_roll),
        ("tape_hook", "Shift", "테이프 갈고리", "테이프 갈고리로 적을 끌어온다.", "8초", tape_hook),
        ("parcel_drop", "궁", "택배 폭격", "주변에 폭발하는 소포 지뢰를 넓게 뿌린다.", "궁극기", parcel_drop),
    ],
    "inkwell": [
        ("ink_cloud", "Q", "먹물 연막", "먹물탄을 던져 먹구름을 터뜨린다. 안에 있는 적은 시야가 어두워지고, 벗어나면 3초 뒤 돌아온다. 3회.", "충전형", ink_cloud),
        ("ink_puddle", "E", "먹물 웅덩이", "밟은 적을 느리게 하고 초당 10 피해를 주는 웅덩이.", "16초", ink_puddle),
        ("ink_portal", "Shift", "먹물 통로", "먼 지점에 먹물 문을 열고 순간이동한다.", "30초", ink_portal),
        ("brush_wall", "궁", "대붓 장벽", "맵을 가르는 먹물 벽. 탄과 소리를 막는다.", "궁극기", brush_wall),
    ],
    "shear": [
        ("spike_guard", "Q", "가시 방패", "등 뒤를 뺀 280°의 피해를 전부 막고 공격자에게 튕겨낸다. 가까이 있는 우리 팀도 튕긴 피해를 받는다.", "유지형", spike_guard),
        ("cleave_leap", "E", "절단 도약", "WASD 방향(대각선 포함)으로 도약한 뒤 착지 지점을 크게 벤다.", "7초", cleave_leap),
        ("blade_fence", "Shift", "칼날 울타리", "적을 밀쳐내는 칼날 벽을 세운다.", "12초", blade_fence),
        ("blade_rain", "궁", "칼날 폭우", "넓은 범위에 칼날을 쏟아 적을 묶는다.", "궁극기", blade_rain),
    ],
    "snip": [
        ("gale_cut", "Q", "질풍 절단", "WASD 방향(대각선 포함)으로 돌진하며 벤다. 처치 시 쿨타임 초기화.", "8초", gale_cut),
        ("deflect", "E", "튕겨내기", "4초간 칼날을 회전시켜 모든 방향의 피해를 막고 2배로 되돌려 준다. 투사체도 되돌린다. 총은 계속 쏠 수 있다.", "8초", deflect),
        ("phase_beacon", "Shift", "속박 비콘", "비콘을 던져 떨어진 곳 주변의 적을 2초간 속박한다.", "10초", phase_beacon),
        ("twin_edge", "궁", "쌍날 개방", "가위를 둘로 나눠 강력한 근접 공격 모드에 들어간다.", "궁극기", twin_edge),
    ],
    "staple": [
        ("staple_sentry", "Q", "철심 감시포", "벽에 붙여 지나가는 적을 느리게 하고 쏘는 소형 포탑. 스테이플이 죽으면 사라진다.", "충전형", staple_sentry),
        ("wire_snare", "E", "철사 덫", "건드린 적의 위치를 알리고 잠깐 묶는 철사.", "12초", wire_snare),
        ("alarm_bot", "Shift", "알람봇", "근처 적에게 받는 피해 증가 효과를 거는 로봇.", "재설치", alarm_bot),
        ("steel_lockdown", "궁", "강철 봉쇄", "넓은 범위를 감지해 일정 시간 후 안의 적을 모두 묶는다.", "궁극기", steel_lockdown),
    ],
    "needle": [
        ("thread_tether", "Q", "치유 실", "실을 연결한 아군을 계속 치유한다.", "유지형", thread_tether),
        ("sleep_dart", "E", "수면 침", "맞은 적을 몇 초 동안 잠재운다.", "12초", sleep_dart),
        ("stitch_grenade", "Shift", "봉합 수류탄", "아군 받는 치유 증가, 적 치유 차단.", "10초", stitch_grenade),
        ("nano_stitch", "궁", "나노 봉합", "아군 하나의 공격력을 높이고 받는 피해를 줄인다.", "궁극기", nano_stitch),
    ],
}

if __name__ == "__main__":
    base = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
    for d in ("guns", "characters", "skills"):
        os.makedirs(os.path.join(base, d), exist_ok=True)
    data = {"guns": [], "characters": []}
    for mid, label, cls, fn in GUNS:
        parts = fn(); write_glb(mid, parts, f"{base}/guns/{mid}.glb")
        data["guns"].append({"id": mid, "name": label, "class": cls, "parts": parts})
    all_chars = [(m, l, f, ROLE_FIX.get(m, r), fn) for m, l, f, r, fn in CHARS] + NEW_CHARS
    order = {"바위": 0, "보": 1, "가위": 2}
    roles = {"탱커": 0, "딜러": 1, "지원": 2, "전략가": 3}
    all_chars.sort(key=lambda c: (order[c[2]], roles[c[3]]))
    nskill = 0
    for mid, label, faction, role, fn in all_chars:
        parts = fn(); write_glb(mid, parts, f"{base}/characters/{mid}.glb")
        skills = []
        os.makedirs(f"{base}/skills/{mid}", exist_ok=True)
        for sid, keyname, sname, desc, cd, sfn in SKILLS[mid]:
            sp = sfn(); write_glb(sid, sp, f"{base}/skills/{mid}/{sid}.glb"); nskill += 1
            skills.append({"id": sid, "key": keyname, "name": sname, "desc": desc, "cd": cd, "parts": sp})
        data["characters"].append({"id": mid, "name": label, "faction": faction, "role": role, "parts": parts, "skills": skills})
    with open(f"{base}/models.json", "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("chars", len(data["characters"]), "skills", nskill, "guns", len(data["guns"]))
