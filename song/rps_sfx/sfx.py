"""효과음: 발소리(바닥 재질 6종 × 걷기/뛰기 × 4변형), 총 7종(발사·재장전·빈총·펌프/노리쇠·폭발),
킬/헤드샷 알림, 고양이·강아지 사망 효과음. 출력: out_audio/sfx/*.wav + *.mp3"""
import math, os, subprocess
import numpy as np
from scipy.io import wavfile
from music import SR, lp1, hp1, mixs, reverb, inst_bell

rng = np.random.default_rng(11)

def t_(dur): return np.arange(int(dur * SR)) / SR
def noise(dur): return rng.uniform(-1, 1, int(dur * SR))
def expenv(dur, tau, atk=0.0005):
    t = t_(dur); return np.exp(-t / tau) * np.clip(t / max(atk, 1e-5), 0, 1)
def bp(x, lo, hi): return lp1(hp1(x, lo), hi)
def sweep(f0, f1, dur, shape=1.0):
    t = t_(dur); f = f0 + (f1 - f0) * (t / t[-1]) ** shape
    return np.sin(2 * np.pi * np.cumsum(f) / SR)
def place(base, sig, at):
    p = int(at * SR); n = max(len(base), p + len(sig)); out = np.zeros(n); out[:len(base)] += base; out[p:p + len(sig)] += sig; return out
def norm(x, peak=0.9):
    x = x - np.mean(x[:64]) * 0
    m = np.abs(x).max() + 1e-9; return x / m * peak
def fade_out(x, tail=0.02):
    k = min(len(x), int(tail * SR)); x = x.copy(); x[-k:] *= np.linspace(1, 0, k); return x

# ------------------------------------------------------------------ 발소리
def step_concrete(v, run):
    thump = sweep(140, 60, 0.09) * expenv(0.09, 0.025)
    grit = bp(noise(0.12), 1500, 6000) * expenv(0.12, 0.018 if run else 0.025)
    heel = bp(noise(0.05), 400, 2500) * expenv(0.05, 0.008)
    return mixs(thump * 0.8, grit * 0.5, place(np.zeros(1), heel * 0.6, 0.035 + v * 0.004))
def step_sand(v, run):
    x = bp(noise(0.22), 300, 2500) * expenv(0.22, 0.06, atk=0.015)
    gr = np.zeros_like(x)
    for k in range(18):
        p = int(rng.uniform(0, 0.12) * SR); g = bp(noise(0.01), 1500, 5000) * expenv(0.01, 0.002)
        gr[p:p + len(g)] += g * rng.uniform(0.2, 0.6)
    return mixs(x * 0.6, gr * 0.5, sweep(110, 60, 0.07) * expenv(0.07, 0.02) * 0.4)
def step_snow(v, run):
    out = np.zeros(int(0.25 * SR))
    for k in range(30 if run else 24):
        p = int(rng.uniform(0.0, 0.16) * SR * (1 if k > 3 else 0.2))
        g = bp(noise(0.012), 1200, 4500) * expenv(0.012, 0.003)
        out[p:p + len(g)] += g * rng.uniform(0.3, 1.0)
    return mixs(out * 0.6, bp(noise(0.2), 200, 1200) * expenv(0.2, 0.05, atk=0.01) * 0.35)
def step_metal(v, run):
    t = t_(0.35)
    ring_ = sum(a * np.sin(2 * np.pi * f * (1 + 0.01 * v) * t) * np.exp(-t / d) for f, a, d in ((620, 0.5, 0.12), (1180, 0.35, 0.08), (1960, 0.25, 0.05), (3300, 0.15, 0.03)))
    return mixs(ring_ * 0.45, sweep(160, 70, 0.08) * expenv(0.08, 0.02) * 0.8, bp(noise(0.04), 2000, 8000) * expenv(0.04, 0.006) * 0.4)
def step_wood(v, run):
    t = t_(0.25)
    knock = (np.sin(2 * np.pi * 190 * t) * 0.8 + np.sin(2 * np.pi * 410 * t) * 0.4 + np.sin(2 * np.pi * 860 * t) * 0.15) * np.exp(-t / 0.05)
    creak = sweep(900, 700, 0.08) * expenv(0.08, 0.03) * 0.08 if v % 2 else np.zeros(1)
    return mixs(knock * 0.7, bp(noise(0.05), 800, 4000) * expenv(0.05, 0.008) * 0.4, place(np.zeros(1), creak, 0.05))
def step_grass(v, run):
    x = bp(noise(0.3), 1500, 7000) * expenv(0.3, 0.07, atk=0.03)
    return mixs(x * 0.5, sweep(100, 55, 0.08) * expenv(0.08, 0.02) * 0.5, bp(noise(0.15), 400, 1500) * expenv(0.15, 0.04, atk=0.01) * 0.3)

SURFACES = {"concrete": step_concrete, "sand": step_sand, "snow": step_snow, "metal": step_metal, "wood": step_wood, "grass": step_grass}

# ------------------------------------------------------------------ 총 레이어
def gun_shot(crack, body_lo, body_hi, body_tau, thump_f, thump_tau, tail, tail_mix, mech=0.3, dur=None):
    dur = dur or max(body_tau * 6, thump_tau * 6, 0.2)
    c = bp(noise(0.03), 2000, 12000) * expenv(0.03, 0.004) * crack
    b = bp(noise(dur), body_lo, body_hi) * expenv(dur, body_tau)
    th = sweep(thump_f * 2.2, thump_f, min(dur, 0.25), 0.4) * expenv(min(dur, 0.25), thump_tau)
    m = bp(noise(0.02), 3000, 9000) * expenv(0.02, 0.003) * mech
    x = mixs(c, b * 0.8, th * 0.9, place(np.zeros(1), m, 0.002))
    x = np.tanh(x * 2.2) * 0.8
    if tail:
        x = np.concatenate([x, np.zeros(int(tail * SR))])
        x = reverb(x, tail_mix, size=1.3)
    return fade_out(x, 0.05)

def click(f=4500, dur=0.03, tau=0.004, amp=1.0):
    return mixs(bp(noise(dur), f * 0.6, f * 1.6) * expenv(dur, tau), np.sin(2 * np.pi * f * 0.5 * t_(dur)) * expenv(dur, tau * 1.5) * 0.4) * amp
def clunk(f=300, dur=0.12, tau=0.03, amp=1.0):
    t = t_(dur)
    return mixs(np.sin(2 * np.pi * f * t) * np.exp(-t / tau), bp(noise(dur), 800, 4000) * expenv(dur, tau * 0.4) * 0.6) * amp
def slide(dur=0.15, lo=1500, hi=6000, amp=0.6):
    return bp(noise(dur), lo, hi) * np.sin(np.pi * np.clip(t_(dur) / dur, 0, 1)) * amp
def metal_ring(fs=(1800, 2900, 4100), tau=0.08, dur=0.25, amp=0.3):
    t = t_(dur); return sum(np.sin(2 * np.pi * f * t) * np.exp(-t / tau) for f in fs) * amp / len(fs)
def shell_drop(at=0.0):
    x = np.zeros(1)
    for k, dt in enumerate((0.0, 0.11, 0.18, 0.22)):
        x = place(x, metal_ring((3200 + k * 300, 5100, 6900), tau=0.03, dur=0.08, amp=0.25 / (k + 1)), at + dt)
    return x

def seq(events, total=None):
    x = np.zeros(1)
    for at, sig in events: x = place(x, sig, at)
    if total: x = np.concatenate([x, np.zeros(max(0, int(total * SR) - len(x)))])
    return fade_out(x)

GUN_SOUNDS = {
    "pistol": dict(
        fire=lambda: gun_shot(1.0, 900, 5000, 0.035, 110, 0.04, 0.5, 0.18, mech=0.6),
        reload=lambda: seq([(0.45, click(3800)), (0.55, slide(0.12, 800, 3000, 0.4)), (1.2, clunk(420, amp=0.9)), (1.25, click(5000, amp=0.7)),
                            (1.5, slide(0.08, 1500, 7000, 0.6)), (1.58, click(4200, amp=0.9))], 1.85)),
    "revolver": dict(
        fire=lambda: mixs(gun_shot(1.0, 500, 4000, 0.06, 80, 0.07, 0.8, 0.22, mech=0.4), metal_ring((1500, 2400), 0.12, 0.4, 0.15)),
        reload=lambda: seq([(0.35, click(3000)), (0.45, metal_ring((900, 1700, 2600), 0.1, 0.3, 0.4)), (0.6, shell_drop()),
                            (1.0, click(5200, amp=0.5)), (1.08, click(5200, amp=0.5)), (1.16, click(5200, amp=0.5)), (1.4, clunk(520, amp=0.8)), (1.43, metal_ring((1200, 2100), 0.06, 0.2, 0.3))], 1.85)),
    "smg": dict(
        fire=lambda: gun_shot(0.8, 1200, 6000, 0.02, 140, 0.025, 0.25, 0.12, mech=0.7, dur=0.13),
        reload=lambda: seq([(0.4, click(3500)), (0.55, slide(0.1, 600, 2500, 0.4)), (1.15, clunk(380)), (1.2, click(4800, amp=0.8)),
                            (1.48, slide(0.1, 1500, 6000, 0.5)), (1.56, click(3600))], 1.85)),
    "rifle": dict(
        fire=lambda: gun_shot(1.2, 700, 6000, 0.04, 95, 0.05, 0.6, 0.2, mech=0.5),
        reload=lambda: seq([(0.42, click(3200)), (0.55, slide(0.14, 500, 2200, 0.45)), (1.18, clunk(330)), (1.24, click(4600, amp=0.8)),
                            (1.46, slide(0.12, 1200, 5000, 0.55)), (1.56, clunk(600, 0.06, 0.012, 0.8))], 1.85)),
    "shotgun": dict(
        fire=lambda: gun_shot(1.0, 250, 3000, 0.09, 60, 0.11, 0.9, 0.25, mech=0.3, dur=0.6),
        pump=lambda: seq([(0.0, mixs(slide(0.09, 600, 3000, 0.5), clunk(260, 0.08, 0.02, 0.8))), (0.14, mixs(slide(0.07, 900, 4000, 0.5), clunk(380, 0.08, 0.015, 0.9)))], 0.3),
        reload=lambda: seq([(0.45, mixs(click(4000, amp=0.6), clunk(500, 0.06, 0.015, 0.6))), (0.85, mixs(click(4000, amp=0.6), clunk(500, 0.06, 0.015, 0.6))),
                            (1.25, mixs(click(4000, amp=0.6), clunk(500, 0.06, 0.015, 0.6))), (1.55, slide(0.08, 600, 3000, 0.5)), (1.68, clunk(380, 0.08, 0.015, 0.9))], 1.85)),
    "sniper": dict(
        fire=lambda: gun_shot(1.4, 400, 7000, 0.07, 70, 0.1, 1.6, 0.3, mech=0.4, dur=0.5),
        bolt=lambda: seq([(0.0, click(2600)), (0.06, slide(0.12, 700, 3000, 0.5)), (0.2, shell_drop()), (0.33, slide(0.1, 900, 3500, 0.5)), (0.44, clunk(450, 0.08, 0.015))], 0.8),
        reload=lambda: seq([(0.4, click(3000)), (0.55, slide(0.12, 500, 2000, 0.4)), (1.2, clunk(300)), (1.26, click(4500, amp=0.8)), (1.5, click(2600)), (1.6, clunk(450, 0.08, 0.015))], 1.85)),
    "launcher": dict(
        fire=lambda: mixs(gun_shot(0.6, 150, 2500, 0.15, 50, 0.15, 0.8, 0.25, mech=0.2, dur=0.6),
                          bp(noise(1.0), 800, 5000) * np.clip(t_(1.0) / 0.05, 0, 1) * np.exp(-t_(1.0) / 0.35) * 0.4),
        explosion=lambda: fade_out(reverb(np.concatenate([np.tanh(mixs(sweep(120, 35, 0.8, 0.5) * expenv(0.8, 0.25), lp1(noise(1.5), 1800) * expenv(1.5, 0.35) * 1.2,
                                                                          bp(noise(0.08), 2000, 9000) * expenv(0.08, 0.01) * 0.8) * 2.0), np.zeros(int(0.8 * SR))]), 0.3, 1.4), 0.2),
        reload=lambda: seq([(0.45, slide(0.3, 300, 1500, 0.4)), (0.95, slide(0.25, 400, 1800, 0.4)), (1.22, clunk(220, 0.15, 0.04)), (1.3, click(3000)), (1.55, click(4200, amp=0.8))], 1.85)),
}
COMMON = {
    "dry_fire": lambda: mixs(click(5000, amp=0.9), metal_ring((2600, 4300), 0.02, 0.06, 0.2)),
    "kill_ding": lambda: fade_out(mixs(inst_bell(1568, 0.08, 0.9, decay=0.35), place(np.zeros(1), inst_bell(2093, 0.1, 0.8, decay=0.45), 0.07))),
    "headshot_ding": lambda: fade_out(mixs(inst_bell(2093, 0.06, 0.8, decay=0.3), place(np.zeros(1), inst_bell(2637, 0.06, 0.8, decay=0.3), 0.06),
                                           place(np.zeros(1), inst_bell(3136, 0.08, 0.9, decay=0.5), 0.12), click(6000, amp=0.3))),
}

def meow(f0=620, dur=0.7):
    """만화풍 '야옹': 피치 곡선 + 포먼트 이동 (모음 i→a→u)."""
    t = t_(dur); u = t / dur
    f = f0 * (1 + 0.35 * np.sin(np.pi * np.clip(u * 1.2, 0, 1))) * (1 - 0.25 * u)
    src = (2 * ((np.cumsum(f) / SR) % 1) - 1)
    out = np.zeros_like(t)
    for (a, b), amp in (((2300, 1100), 1.0), ((3000, 2400), 0.5)):
        fc = a + (b - a) * u
        out += bp(src, 1, 1) * 0  # placeholder
        out += lp1(hp1(src, fc * 0.8), fc * 1.25) * amp
    return out * np.sin(np.pi * np.clip(u, 0, 1)) ** 0.6 * 0.8
def awoo(f0=380, dur=1.0):
    t = t_(dur); u = t / dur
    f = f0 * (1 + 0.5 * np.sin(np.pi * np.clip(u * 0.9, 0, 1))) * (1 + 0.01 * np.sin(2 * np.pi * 6 * t))
    src = np.sin(2 * np.pi * np.cumsum(f) / SR) + 0.3 * np.sin(4 * np.pi * np.cumsum(f) / SR)
    return lp1(src, 1500 + 800 * np.sin(np.pi * u)) * np.sin(np.pi * u) ** 0.7 * 0.7
def harp_up(start=0.0):
    x = np.zeros(1)
    for k, m in enumerate((72, 76, 79, 83, 84, 88, 91, 96)):
        x = place(x, inst_bell(440 * 2 ** ((m - 69) / 12), 0.1, 0.5, decay=0.8), start + k * 0.07)
    return x
COMMON["death_cat"] = lambda: fade_out(reverb(np.concatenate([mixs(meow(700, 0.55), place(np.zeros(1), meow(520, 0.7), 0.5), harp_up(1.1)), np.zeros(int(0.6 * SR))]), 0.22), 0.2)
COMMON["death_dog"] = lambda: fade_out(reverb(np.concatenate([mixs(awoo(330, 1.2), harp_up(1.0)), np.zeros(int(0.6 * SR))]), 0.22), 0.2)

MAP_SURFACE = {"rps_arena": "concrete", "desert_ruins": "sand", "frost_harbor": "snow", "neon_rooftops": "metal", "jungle_temple": "grass"}

def write(path_noext, x, peak=0.9):
    x = norm(np.asarray(x, float), peak)
    wavfile.write(path_noext + ".wav", SR, (x * 32767).astype(np.int16))
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", path_noext + ".wav", "-codec:a", "libmp3lame", "-b:a", "128k", path_noext + ".mp3"], check=True)

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out_audio", "sfx")
    os.makedirs(out, exist_ok=True)
    files = []
    for s, fn in SURFACES.items():
        for run in (False, True):
            for v in range(4):
                x = fn(v, run) * (1.0 if run else 0.7)
                write(f"{out}/step_{s}_{'run' if run else 'walk'}_{v + 1}", x, 0.8 if run else 0.6); files.append(1)
    for g, d in GUN_SOUNDS.items():
        for k, fn in d.items():
            write(f"{out}/gun_{g}_{k}", fn(), 0.95 if k in ("fire", "explosion") else 0.75); files.append(1)
    for k, fn in COMMON.items():
        write(f"{out}/{k}", fn(), 0.8); files.append(1)
    print("sfx files", len(files))
