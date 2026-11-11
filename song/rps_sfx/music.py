"""맵 배경음악 5곡 — numpy 신시사이저 + 스텝 시퀀서로 작곡한 오리지널 곡.
각 곡은 끊김 없는 루프(리버브/딜레이 꼬리를 곡 앞부분에 겹쳐 넣음)."""
import math, os, subprocess
import numpy as np
from scipy.signal import lfilter
from scipy.io import wavfile

SR = 44100
rng = np.random.default_rng(7)

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)

# ------------------------------------------------------------------ 기본 파형/엔벨로프
def env_adsr(n, a, d, s, r, sr=SR):
    a, d, r = int(a * sr), int(d * sr), int(r * sr)
    e = np.full(n + r, s, float)
    a = max(a, 1); d = max(d, 1)
    e[:a] = np.linspace(0, 1, a, endpoint=False)[: n + r]
    if a < n + r:
        e[a:a + d] = np.linspace(1, s, d, endpoint=False)[: max(0, min(d, n + r - a))]
    rel_start = max(n, a)
    if rel_start < len(e):
        e[rel_start:] = np.linspace(e[min(rel_start, len(e) - 1)] if rel_start < len(e) else s, 0, len(e) - rel_start)
    return e

def phase(f, n, vib=0.0, vib_rate=5.5, delay=0.12):
    t = np.arange(n) / SR
    fm = f * (1 + vib * np.sin(2 * np.pi * vib_rate * t) * np.clip((t - delay) * 6, 0, 1))
    return np.cumsum(fm) / SR

def lp1(x, cutoff, block=128):
    """1극 로우패스. cutoff가 배열이면 블록 단위로 계수를 바꿔 가며 상태를 이어서 필터링."""
    x = np.asarray(x, float)
    if np.isscalar(cutoff):
        a = math.exp(-2 * math.pi * cutoff / SR)
        return lfilter([1 - a], [1, -a], x)
    y = np.empty_like(x); zi = np.zeros(1)
    cutoff = np.clip(cutoff, 20, SR / 2.2)
    for i in range(0, len(x), block):
        a = math.exp(-2 * math.pi * float(cutoff[i]) / SR)
        y[i:i + block], zi = lfilter([1 - a], [1, -a], x[i:i + block], zi=zi * 1.0 if i else np.zeros(1))
    return y

def hp1(x, cutoff):
    return x - lp1(x, cutoff)

# ------------------------------------------------------------------ 악기
def inst_square(f, dur, vel, pw=0.5, vib=0.004, bright=5000):
    n = int(dur * SR); e = env_adsr(n, 0.004, 0.09, 0.55, 0.07)
    p = phase(f, len(e), vib=vib) % 1.0
    x = np.where(p < pw, 1.0, -1.0)
    return lp1(x, bright) * e * vel * 0.5

def inst_saw(f, dur, vel, cut0=6000, cut1=900, dec=0.18, det=0.0, rel=0.06):
    n = int(dur * SR); e = env_adsr(n, 0.003, 0.12, 0.7, rel)
    x = 0
    for d in ((0,) if det == 0 else (-det, det)):
        p = phase(f * (1 + d), len(e)) % 1.0
        x = x + (2 * p - 1)
    t = np.arange(len(e)) / SR
    cut = cut1 + (cut0 - cut1) * np.exp(-t / dec)
    return lp1(x / (1 if det == 0 else 2), cut) * e * vel * 0.45

def inst_tri(f, dur, vel, rel=0.05):
    n = int(dur * SR); e = env_adsr(n, 0.004, 0.06, 0.8, rel)
    p = phase(f, len(e)) % 1.0
    return (2 * np.abs(2 * p - 1) - 1) * e * vel * 0.6

def inst_bass(f, dur, vel):
    n = int(dur * SR); e = env_adsr(n, 0.002, 0.08, 0.75, 0.04)
    p = phase(f, len(e)) % 1.0
    t = np.arange(len(e)) / SR
    x = 0.65 * (2 * p - 1) + 0.6 * np.sin(2 * np.pi * np.cumsum(np.full(len(e), f)) / SR)
    return lp1(x, 300 + 1600 * np.exp(-t / 0.06)) * e * vel * 0.7

def inst_pluck(f, dur, vel, damp=0.996, bright=0.5):
    """Karplus-Strong (오우드/기타 느낌) — 주기 단위 벡터 처리."""
    n = int((dur + 0.4) * SR); L = max(2, int(SR / f))
    b = lp1(rng.uniform(-1, 1, L) * vel, 2000 + 8000 * bright)
    blocks = []
    for _ in range(n // L + 1):
        blocks.append(b)
        b = damp * 0.5 * (b + np.roll(b, -1))
    out = np.concatenate(blocks)[:n]
    fade = np.ones(n); k = int(0.05 * SR); fade[-k:] = np.linspace(1, 0, k)
    return out * fade * 0.6

def inst_bell(f, dur, vel, decay=1.2):
    n = int((dur + decay) * SR); t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * f * t) * np.exp(-t / decay) + 0.45 * np.sin(2 * np.pi * f * 2.756 * t) * np.exp(-t / (decay * 0.45))
         + 0.22 * np.sin(2 * np.pi * f * 5.404 * t) * np.exp(-t / (decay * 0.25)))
    atk = np.clip(t / 0.002, 0, 1)
    return x * atk * vel * 0.35

def inst_marimba(f, dur, vel):
    n = int((dur + 0.5) * SR); t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.32) + 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / 0.05) + 0.12 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / 0.02)
    return x * np.clip(t / 0.001, 0, 1) * vel * 0.5

def inst_pad(f, dur, vel, cut=1800):
    n = int(dur * SR); e = env_adsr(n, 0.35, 0.3, 0.8, 0.6)
    x = 0
    for d in (-0.007, -0.0025, 0.0025, 0.007):
        p = phase(f * (1 + d), len(e)) % 1.0
        x = x + (2 * p - 1)
    return lp1(x / 4, cut) * e * vel * 0.35

def inst_organ(f, dur, vel):
    n = int(dur * SR); e = env_adsr(n, 0.01, 0.05, 0.85, 0.05)
    t = np.arange(len(e)) / SR
    x = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(4 * np.pi * f * t) + 0.25 * np.sin(6 * np.pi * f * t)
    return x * e * vel * 0.3

def mixs(*sigs):
    """길이가 다른 신호들을 더함."""
    n = max(len(x) for x in sigs); out = np.zeros(n)
    for x in sigs: out[:len(x)] += x
    return out

# ---- 드럼
def d_kick(vel=1.0, tune=1.0):
    n = int(0.35 * SR); t = np.arange(n) / SR
    f = (48 + 110 * np.exp(-t / 0.035)) * tune
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    click = rng.uniform(-1, 1, n) * np.exp(-t / 0.002) * 0.3
    return np.tanh((x + click) * 1.6) * vel * 0.9

def d_snare(vel=1.0, tone=190):
    n = int(0.25 * SR); t = np.arange(n) / SR
    nz = hp1(rng.uniform(-1, 1, n), 1200) * np.exp(-t / 0.07)
    tn = np.sin(2 * np.pi * tone * t) * np.exp(-t / 0.05)
    return (0.75 * nz + 0.5 * tn) * vel * 0.6

def d_clap(vel=1.0):
    n = int(0.3 * SR); t = np.arange(n) / SR
    nz = hp1(rng.uniform(-1, 1, n), 900)
    e = np.zeros(n)
    for o in (0, 0.011, 0.022):
        e += np.where(t >= o, np.exp(-(t - o) / 0.012), 0)
    e += np.where(t >= 0.03, np.exp(-(t - 0.03) / 0.12), 0) * 0.6
    return lp1(nz * e, 5000) * vel * 0.45

def d_hat(vel=1.0, open_=False):
    n = int((0.25 if open_ else 0.06) * SR); t = np.arange(n) / SR
    nz = hp1(rng.uniform(-1, 1, n), 7000)
    return nz * np.exp(-t / (0.08 if open_ else 0.018)) * vel * 0.32

def d_shaker(vel=1.0):
    n = int(0.09 * SR); t = np.arange(n) / SR
    nz = hp1(rng.uniform(-1, 1, n), 5000)
    return nz * np.sin(np.pi * np.clip(t / 0.09, 0, 1)) ** 2 * vel * 0.22

def d_bell_jingle(vel=1.0):
    n = int(0.25 * SR); t = np.arange(n) / SR
    x = sum(np.sin(2 * np.pi * f * t + rng.uniform(0, 6)) for f in (5200, 6300, 7400, 8900)) * np.exp(-t / 0.06)
    return mixs(x * vel * 0.06, d_shaker(vel) * 0.5)

def d_tom(vel=1.0, f0=140):
    n = int(0.4 * SR); t = np.arange(n) / SR
    f = f0 * (1 + 0.6 * np.exp(-t / 0.03))
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.16) * vel * 0.6

def d_bongo(vel=1.0, f0=420):
    n = int(0.22 * SR); t = np.arange(n) / SR
    f = f0 * (1 + 0.25 * np.exp(-t / 0.01))
    return (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.07) + rng.uniform(-1, 1, n) * np.exp(-t / 0.004) * 0.2) * vel * 0.5

def d_darbuka(vel=1.0, kind="dum"):
    if kind == "dum": return d_tom(vel, 95) * 1.1
    if kind == "tek": return mixs(d_bongo(vel, 650) * 0.6, d_hat(vel) * 1.4)
    return d_bongo(vel * 0.6, 520)

def d_wood(vel=1.0, f0=1800):
    n = int(0.06 * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * f0 * t) * np.exp(-t / 0.012) * vel * 0.4

def d_crash(vel=1.0):
    n = int(1.6 * SR); t = np.arange(n) / SR
    return hp1(rng.uniform(-1, 1, n), 4500) * np.exp(-t / 0.5) * vel * 0.2

# ------------------------------------------------------------------ 이펙트
def _comb(x, D, g):
    """y[n] = x[n] + g*y[n-D] (블록 재귀)."""
    y = x.astype(float).copy()
    for i in range(D, len(y), D):
        e = min(len(y), i + D); y[i:e] += g * y[i - D:e - D]
    return y

def _allpass(x, D, g):
    """y[n] = -g*x[n] + x[n-D] + g*y[n-D]."""
    xd = np.concatenate([np.zeros(D), x[:-D]])
    v = -g * x + xd
    return _comb(v, D, g)

def reverb(x, mix=0.18, size=1.0):
    y = np.zeros_like(x, dtype=float)
    for D, g in ((1557, 0.84), (1617, 0.83), (1491, 0.85), (1422, 0.86)):
        y += _comb(x, int(D * size), g)
    for D, g in ((225, 0.5), (556, 0.5)):
        y = _allpass(y, D, g)
    y = lp1(y / 4, 6000)
    return x * (1 - mix) + y * mix

def delay(x, t, fb=0.35, mix=0.25, cut=3500):
    D = int(t * SR); y = x.copy(); out = np.zeros(len(x) + D * 6)
    out[:len(x)] += x
    tap = x * mix
    for k in range(1, 6):
        tap = lp1(tap, cut)
        out[k * D:k * D + len(x)] += tap
        tap = tap * fb
    return out[:len(x)]

# ------------------------------------------------------------------ 시퀀서
class Song:
    def __init__(self, bpm, bars, swing=0.0):
        self.bpm, self.bars, self.swing = bpm, bars, swing
        self.step = 60 / bpm / 4
        self.len = int(bars * 16 * self.step * SR)
        self.tracks = {}
    def t(self, name):
        if name not in self.tracks: self.tracks[name] = np.zeros(self.len + 6 * SR)
        return self.tracks[name]
    def pos(self, bar, step):
        s = step + (self.swing if int(step) % 4 == 2 else 0)
        return int((bar * 16 + s) * self.step * SR)
    def add(self, name, bar, step, sig):
        buf = self.t(name); p = self.pos(bar, step)
        e = min(len(buf), p + len(sig)); buf[p:e] += sig[: e - p]
    def note(self, name, bar, step, midi, steps, vel, inst, **kw):
        self.add(name, bar, step, inst(mtof(midi), steps * self.step, vel, **kw))

def scale_note(root, scale, deg):
    o, i = divmod(deg, len(scale))
    return root + scale[i] + 12 * o

MAJ = [0, 2, 4, 5, 7, 9, 11]; MIN = [0, 2, 3, 5, 7, 8, 10]; PHRDOM = [0, 1, 4, 5, 7, 8, 10]; PENTA = [0, 2, 4, 7, 9]

def chord_tones(root, kind):
    return [root, root + (3 if kind == "m" else 4), root + 7] + ([root + 10] if kind == "7" else [])

def mix_song(song, spec, sidechain=None, out_name="x"):
    """spec: {track: (gain, pan, reverb_send, delay)}"""
    L = np.zeros(song.len + 6 * SR); R = np.zeros_like(L)
    kick = song.tracks.get("kick")
    duck = None
    if sidechain and kick is not None:
        env = np.abs(kick); env = lfilter([0.002], [1, -0.998], env); env = env / (env.max() + 1e-9)
        duck = 1 - sidechain * np.clip(env * 3, 0, 1)
    for name, buf in song.tracks.items():
        g, pan, rv, dl = spec.get(name, (0.8, 0.0, 0.1, None))
        x = buf * g
        if dl: x = x + delay(x, dl[0], dl[1], dl[2]) - x * 0  # 딜레이 합산
        if rv: x = reverb(x, rv)
        if duck is not None and name not in ("kick",): x = x * duck
        L += x * math.cos((pan + 1) * math.pi / 4) * 1.414 * 0.707
        R += x * math.sin((pan + 1) * math.pi / 4) * 1.414 * 0.707
    st = np.stack([L, R], 1)
    # 루프 이음: 곡 끝 이후의 꼬리를 앞부분에 겹침
    tail = st[song.len:]
    st = st[:song.len].copy(); st[: len(tail)] += tail
    st = np.tanh(st * 1.1) / np.tanh(1.1)
    st = st / (np.abs(st).max() + 1e-9) * 0.89
    # 곡 간 음량 맞추기: RMS -13 dBFS 목표 + 소프트 리미터
    rms = np.sqrt(np.mean(st ** 2)); st = st * (10 ** (-13 / 20) / (rms + 1e-9))
    st = np.tanh(st * 1.05) / np.tanh(1.05)
    st = st / max(1.0, np.abs(st).max() / 0.95)
    return st

# =================================================================== 곡 1: RPS 아레나 — 가위바위보 쇼다운
def song_arena():
    S = Song(128, 40)
    key = 48  # C
    progA = [(0, ""), (9, "m"), (5, ""), (7, "")]           # C Am F G
    progB = [(5, ""), (7, ""), (4, "m"), (9, "m")]          # F G Em Am
    form = ["I"] * 4 + ["A"] * 8 + ["B"] * 8 + ["A"] * 8 + ["K"] * 4 + ["B"] * 8
    leadA = [[(0, 7, 2), (2, 7, 1), (3, 9, 1), (4, 7, 2), (6, 4, 2), (8, 5, 3), (11, 4, 1), (12, 2, 4)],
             [(0, 4, 2), (2, 5, 2), (4, 7, 2), (6, 9, 2), (8, 7, 6), (14, 6, 2)],
             [(0, 5, 2), (2, 5, 1), (3, 7, 1), (4, 9, 2), (6, 8, 2), (8, 7, 4), (12, 5, 2), (14, 4, 2)],
             [(0, 4, 2), (2, 2, 2), (4, 4, 2), (6, 6, 2), (8, 7, 8)]]
    leadB = [[(0, 9, 3), (3, 8, 1), (4, 7, 2), (6, 5, 2), (8, 7, 2), (10, 9, 2), (12, 11, 4)],
             [(0, 11, 2), (2, 10, 2), (4, 9, 2), (6, 8, 2), (8, 7, 4), (12, 4, 4)],
             [(0, 6, 2), (2, 7, 2), (4, 9, 2), (6, 7, 2), (8, 6, 2), (10, 4, 2), (12, 6, 4)],
             [(0, 7, 3), (3, 9, 3), (6, 11, 2), (8, 12, 6), (14, 11, 1), (15, 12, 1)]]
    for bar, sec in enumerate(form):
        prog = progB if sec == "B" else progA
        r, kind = prog[bar % 4]; root = key + r
        # 드럼: 4온더플로어 + 펑키 하이햇
        if sec != "K" or bar % 4 >= 2:
            for st in (0, 4, 8, 12): S.add("kick", bar, st, d_kick(1.0))
        if sec != "I":
            for st in (4, 12): S.add("snare", bar, st, mixs(d_clap(1.0), d_snare(0.5)))
        for st in range(16):
            if st % 2 == 1 or sec in ("B",): S.add("hat", bar, st, d_hat(0.9 if st % 4 == 2 else 0.55, open_=(st % 8 == 6)))
        if bar % 8 == 7 and sec != "K":
            for k, st in enumerate((12, 13, 14, 15)): S.add("snare", bar, st, d_snare(0.5 + k * 0.15))
        if bar in (4, 12, 20, 32): S.add("crash", bar, 0, d_crash())
        # 베이스: 옥타브 펑크
        for st, oc, ln in ((0, 0, 2), (3, 12, 1), (4, 0, 2), (7, 12, 1), (8, 0, 1), (10, 7, 2), (12, 12, 1), (14, 0, 2)):
            S.note("bass", bar, st, root - 12 + oc, ln, 0.9, inst_bass)
        if sec == "I": continue
        # 코드 스탭 (오프비트)
        for st in (2, 6, 10, 14) if sec != "K" else (0,):
            for m in chord_tones(root + 12, kind):
                S.note("stab", bar, st, m, 1 if sec != "K" else 14, 0.35, inst_saw, cut0=4500, cut1=700, dec=0.08)
        # 아르페지오
        ct = chord_tones(root + 24, kind) + [root + 36]
        for st in range(0, 16, 2 if sec == "A" else 1):
            S.note("arp", bar, st, ct[(st // (2 if sec == "A" else 1)) % len(ct)], 1, 0.22, inst_square, pw=0.25, bright=7000)
        # 리드
        if sec in ("A", "B"):
            ph = (leadB if sec == "B" else leadA)[bar % 4]
            for st, deg, ln in ph:
                S.note("lead", bar, st, scale_note(key + 12, MAJ, deg), ln, 0.55, inst_square, pw=0.5, vib=0.006)
        if sec == "K":
            for st in (0, 3, 6, 10, 12):
                S.add("perc", bar, st, d_wood(0.8, 1400 + 200 * (st % 3)))
    return mix_song(S, {"kick": (1.0, 0, 0, None), "snare": (0.8, 0, 0.12, None), "hat": (0.55, 0.25, 0.05, None), "crash": (0.5, -0.2, 0.1, None),
                        "bass": (0.85, 0, 0, None), "stab": (0.45, -0.3, 0.15, None), "arp": (0.4, 0.35, 0.1, (S.step * 3, 0.35, 0.3)),
                        "lead": (0.62, 0, 0.16, (S.step * 3, 0.3, 0.22)), "perc": (0.5, 0.4, 0.1, None)}, sidechain=0.25)

# =================================================================== 곡 2: 사막 유적 — 모래 셔플
def song_desert():
    S = Song(112, 36, swing=0.35)
    key = 52  # E (프리지안 도미넌트)
    progA = [(0, ""), (1, ""), (0, ""), (-2, "m")]            # E F E Dm
    progB = [(5, "m"), (3, "m"), (1, ""), (0, "")]            # Am G#dim? → Am Gm F E (색채용)
    form = ["I"] * 4 + ["A"] * 8 + ["B"] * 8 + ["A"] * 8 + ["B"] * 8
    leadA = [[(0, 4, 2), (2, 5, 1), (3, 4, 1), (4, 3, 2), (6, 2, 2), (8, 1, 2), (10, 2, 2), (12, 0, 4)],
             [(0, 1, 2), (2, 2, 2), (4, 3, 1), (5, 4, 1), (6, 5, 2), (8, 4, 6), (14, 3, 2)],
             [(0, 4, 1), (1, 5, 1), (2, 6, 2), (4, 7, 2), (6, 6, 1), (7, 5, 1), (8, 4, 4), (12, 2, 2), (14, 1, 2)],
             [(0, 0, 2), (2, 1, 2), (4, 0, 2), (6, -1, 2), (8, 0, 8)]]
    leadB = [[(0, 7, 3), (3, 8, 1), (4, 7, 2), (6, 5, 2), (8, 4, 4), (12, 5, 2), (14, 4, 2)],
             [(0, 3, 2), (2, 4, 2), (4, 5, 4), (8, 4, 2), (10, 3, 2), (12, 1, 4)],
             [(0, 1, 1), (1, 2, 1), (2, 3, 1), (3, 4, 1), (4, 5, 2), (6, 4, 2), (8, 2, 2), (10, 1, 2), (12, 2, 4)],
             [(0, 1, 2), (2, 0, 2), (4, 1, 4), (8, 0, 8)]]
    for bar, sec in enumerate(form):
        prog = progB if sec == "B" else progA
        r, kind = prog[bar % 4]; root = key + r
        # 다르부카 리듬: 둠-텍-텍 둠-텍
        for st, k in ((0, "dum"), (3, "tek"), (4, "ka"), (6, "tek"), (8, "dum"), (10, "dum"), (12, "tek"), (14, "ka"), (15, "tek")):
            S.add("darbuka", bar, st, d_darbuka(0.9, k))
        if sec != "I":
            for st in (0, 8): S.add("kick", bar, st, d_kick(0.7, 0.9))
            for st in range(0, 16, 2): S.add("shaker", bar, st, d_shaker(0.8 if st % 4 == 0 else 0.5))
        # 베이스 (튀는 옥타브)
        for st, oc in ((0, 0), (3, 0), (6, 12), (8, 0), (11, 7), (14, 12)):
            S.note("bass", bar, st, root - 12 + oc, 2, 0.8, inst_bass)
        if sec == "I":
            S.note("drone", bar, 0, key - 12, 16, 0.3, inst_pad, cut=900)
            continue
        S.note("drone", bar, 0, key - 12, 16, 0.25, inst_pad, cut=900)
        S.note("drone", bar, 0, key - 5, 16, 0.18, inst_pad, cut=900)
        # 오우드 같은 플럭 리프 (뜯는 반주)
        ct = chord_tones(root + 12, kind)
        for st in (0, 2, 3, 6, 8, 10, 11, 14):
            S.note("oud", bar, st, ct[(st * 7) % 3] + (12 if st in (6, 14) else 0), 1, 0.7, inst_pluck, damp=0.993, bright=0.6)
        ph = (leadB if sec == "B" else leadA)[bar % 4]
        for st, deg, ln in ph:
            S.note("lead", bar, st, scale_note(key + 12, PHRDOM, deg), ln, 0.5, inst_saw, cut0=3000, cut1=1400, dec=0.3, det=0.004)
            S.note("lead2", bar, st, scale_note(key + 24, PHRDOM, deg), ln, 0.18, inst_organ)
        if bar % 8 == 7:
            for st in (12, 13, 14, 15): S.add("darbuka", bar, st, d_darbuka(1.0, "tek"))
    return mix_song(S, {"darbuka": (0.85, 0.15, 0.1, None), "kick": (0.7, 0, 0, None), "shaker": (0.5, -0.4, 0.05, None),
                        "bass": (0.75, 0, 0, None), "drone": (0.4, 0, 0.2, None), "oud": (0.6, -0.25, 0.12, None),
                        "lead": (0.5, 0.15, 0.2, (S.step * 3, 0.3, 0.25)), "lead2": (0.3, 0.3, 0.2, None)})

# =================================================================== 곡 3: 설원 항구 — 펭귄 순찰대
def song_harbor():
    S = Song(124, 36, swing=0.4)
    key = 53  # F
    progA = [(0, ""), (5, ""), (7, ""), (0, "")]              # F Bb C F
    progB = [(9, "m"), (5, ""), (2, "m"), (7, "7")]           # Dm Bb Gm C7
    form = ["I"] * 4 + ["A"] * 8 + ["B"] * 8 + ["A"] * 8 + ["B"] * 8
    leadA = [[(0, 4, 1), (2, 4, 1), (4, 5, 1), (6, 7, 2), (10, 4, 1), (12, 2, 2), (14, 0, 2)],
             [(0, 3, 1), (2, 3, 1), (4, 5, 1), (6, 8, 2), (10, 7, 1), (12, 5, 4)],
             [(0, 4, 1), (2, 6, 1), (4, 8, 1), (6, 7, 1), (8, 6, 1), (10, 4, 1), (12, 1, 2), (14, 2, 2)],
             [(0, 2, 1), (2, 4, 1), (4, 0, 2), (8, 7, 1), (10, 7, 1), (12, 7, 4)]]
    leadB = [[(0, 5, 2), (2, 7, 2), (4, 9, 2), (6, 8, 1), (8, 7, 3), (12, 5, 2), (14, 4, 2)],
             [(0, 3, 2), (2, 5, 2), (4, 7, 4), (8, 6, 1), (10, 5, 1), (12, 3, 4)],
             [(0, 1, 2), (2, 3, 2), (4, 5, 2), (6, 4, 1), (8, 3, 2), (10, 1, 2), (12, 4, 4)],
             [(0, 6, 1), (2, 6, 1), (4, 6, 1), (6, 5, 1), (8, 4, 1), (10, 3, 1), (12, 2, 2), (14, 1, 2)]]
    for bar, sec in enumerate(form):
        prog = progB if sec == "B" else progA
        r, kind = prog[bar % 4]; root = key + r
        # 경쾌한 투비트 (오컴파)
        for st in (0, 8): S.add("kick", bar, st, d_kick(0.8, 1.1))
        if sec != "I":
            for st in (4, 12): S.add("snare", bar, st, d_snare(0.7, 230))
        for st in range(0, 16, 2): S.add("jingle", bar, st, d_bell_jingle(0.9 if st % 4 == 2 else 0.5))
        # 툭툭 튀는 베이스 (루트-5도 왕복)
        for st, iv in ((0, 0), (4, 7), (8, 0), (12, 7)):
            S.note("bass", bar, st, root - 12 + iv, 1.5, 0.8, inst_bass)
        if sec == "I":
            for st in (14,): S.add("wood", bar, st, d_wood(0.9))
            continue
        # 피치카토 같은 오프비트 코드 (삼각파)
        for st in (2, 6, 10, 14):
            for m in chord_tones(root + 12, kind)[:3]:
                S.note("pizz", bar, st, m, 0.8, 0.35, inst_tri, rel=0.03)
        # 글로켄 리드
        ph = (leadB if sec == "B" else leadA)[bar % 4]
        for st, deg, ln in ph:
            S.note("glock", bar, st, scale_note(key + 24, MAJ, deg), ln, 0.7, inst_bell, decay=0.6)
            if sec == "B": S.note("flute", bar, st, scale_note(key + 12, MAJ, deg), ln, 0.35, inst_tri)
        # 펭귄 뒤뚱 효과음 (나무 블록)
        if bar % 2 == 1:
            for st in (13, 15): S.add("wood", bar, st, d_wood(0.7, 1200 if st == 13 else 900))
    return mix_song(S, {"kick": (0.8, 0, 0, None), "snare": (0.65, 0, 0.15, None), "jingle": (0.6, 0.35, 0.08, None),
                        "bass": (0.8, 0, 0, None), "pizz": (0.5, -0.3, 0.15, None), "glock": (0.65, 0.2, 0.22, (S.step * 3, 0.3, 0.2)),
                        "flute": (0.35, -0.15, 0.2, None), "wood": (0.6, 0.45, 0.1, None)})

# =================================================================== 곡 4: 네온 옥상 — 네온 홉
def song_neon():
    S = Song(118, 40)
    key = 45  # A minor
    progA = [(0, "m"), (8, ""), (3, ""), (10, "")]            # Am F C G
    progB = [(5, "m"), (0, "m"), (7, ""), (7, "")]            # Dm Am E E
    form = ["I"] * 4 + ["A"] * 8 + ["B"] * 8 + ["K"] * 4 + ["A"] * 8 + ["B"] * 8
    leadA = [[(0, 4, 3), (3, 4, 1), (4, 6, 2), (6, 7, 2), (8, 6, 4), (12, 4, 2), (14, 2, 2)],
             [(0, 2, 3), (3, 2, 1), (4, 4, 2), (6, 5, 2), (8, 4, 6), (14, 2, 2)],
             [(0, 2, 2), (2, 4, 2), (4, 7, 3), (7, 6, 1), (8, 4, 4), (12, 2, 2), (14, 1, 2)],
             [(0, 1, 3), (3, 2, 1), (4, 4, 4), (8, 1, 2), (10, 0, 6)]]
    leadB = [[(0, 3, 2), (2, 4, 2), (4, 5, 2), (6, 7, 2), (8, 8, 6), (14, 7, 2)],
             [(0, 7, 2), (2, 6, 2), (4, 4, 4), (8, 2, 2), (10, 4, 6)],
             [(0, 4, 2), (2, 6, 1), (3, 7, 1), (4, 8, 2), (6, 9, 2), (8, 11, 4), (12, 9, 4)],
             [(0, 8, 2), (2, 7, 2), (4, 6, 2), (6, 4, 2), (8, 6.5, 8)]]
    for bar, sec in enumerate(form):
        prog = progB if sec == "B" else progA
        r, kind = prog[bar % 4]; root = key + r
        if sec != "K":
            for st in (0, 4, 8, 12): S.add("kick", bar, st, d_kick(1.0, 0.95))
        if sec not in ("I", "K"):
            for st in (4, 12): S.add("snare", bar, st, mixs(d_snare(0.9, 180), d_clap(0.6)))
        for st in range(2, 16, 4): S.add("hat", bar, st, d_hat(0.8, open_=True))
        if sec in ("B",):
            for st in range(16): S.add("hat", bar, st, d_hat(0.35))
        # 펌핑 베이스 (8분 연타)
        for st in range(0, 16, 2):
            S.note("bass", bar, st + 1 if sec == "K" else st, root - 12, 1.5, 0.85, inst_saw, cut0=1500, cut1=300, dec=0.05)
        # 신스 패드
        for m in chord_tones(root + 12, kind):
            S.note("pad", bar, 0, m, 16, 0.4, inst_pad, cut=2200 if sec != "K" else 900)
        if sec == "I": continue
        # 16분 아르페지오 (위아래)
        ct = chord_tones(root + 24, kind); seq = ct + [ct[0] + 12] + ct[::-1][1:]
        for st in range(16):
            S.note("arp", bar, st, seq[st % len(seq)], 1, 0.3, inst_saw, cut0=5000 if sec == "B" else 2800, cut1=600, dec=0.06)
        if sec in ("A", "B"):
            ph = (leadB if sec == "B" else leadA)[bar % 4]
            for st, deg, ln in ph:
                if deg == 6.5: m = key + 12 + 11  # G# (이끔음)
                else: m = scale_note(key + 12, MIN, int(deg))
                S.note("lead", bar, st, m, ln, 0.5, inst_saw, cut0=4500, cut1=2200, dec=0.4, det=0.006, rel=0.12)
        if bar in (4, 12, 24, 32): S.add("crash", bar, 0, d_crash())
        if sec == "K" and bar % 4 == 3:
            for k in range(8): S.add("snare", bar, 8 + k, d_snare(0.3 + k * 0.08))
    return mix_song(S, {"kick": (1.0, 0, 0, None), "snare": (0.75, 0, 0.18, None), "hat": (0.45, 0.3, 0.05, None), "crash": (0.45, -0.25, 0.15, None),
                        "bass": (0.75, 0, 0, None), "pad": (0.45, 0, 0.3, None), "arp": (0.35, -0.35, 0.12, (S.step * 3, 0.4, 0.3)),
                        "lead": (0.6, 0.1, 0.25, (S.step * 6, 0.35, 0.25))}, sidechain=0.55)

# =================================================================== 곡 5: 정글 사원 — 원숭이 소동
def song_jungle():
    S = Song(104, 36, swing=0.45)
    key = 55  # G 펜타토닉
    progA = [(0, ""), (9, "m"), (5, ""), (7, "")]             # G Em C D
    progB = [(5, ""), (7, ""), (4, "m"), (9, "m")]            # C D Bm Em
    form = ["I"] * 4 + ["A"] * 8 + ["B"] * 8 + ["A"] * 8 + ["B"] * 8
    leadA = [[(0, 2, 1), (2, 3, 1), (3, 4, 1), (4, 5, 2), (6, 4, 2), (8, 2, 2), (10, 3, 2), (12, 2, 4)],
             [(0, 0, 1), (1, 1, 1), (2, 2, 2), (4, 4, 2), (6, 2, 2), (8, 1, 6), (14, 0, 2)],
             [(0, 5, 1), (2, 5, 1), (3, 6, 1), (4, 7, 2), (6, 6, 1), (7, 5, 1), (8, 4, 4), (12, 3, 2), (14, 2, 2)],
             [(0, 3, 2), (2, 1, 2), (4, 2, 2), (6, 1, 1), (7, 0, 1), (8, 0, 8)]]
    leadB = [[(0, 7, 2), (2, 6, 1), (3, 5, 1), (4, 6, 2), (6, 7, 2), (8, 8, 4), (12, 7, 4)],
             [(0, 6, 2), (2, 5, 2), (4, 4, 2), (6, 5, 2), (8, 6, 6), (14, 5, 2)],
             [(0, 4, 1), (1, 5, 1), (2, 6, 1), (3, 5, 1), (4, 4, 2), (6, 3, 2), (8, 2, 2), (10, 3, 2), (12, 4, 4)],
             [(0, 5, 1), (2, 5, 1), (4, 5, 1), (6, 6, 1), (8, 7, 4), (12, 5, 4)]]
    for bar, sec in enumerate(form):
        prog = progB if sec == "B" else progA
        r, kind = prog[bar % 4]; root = key + r
        # 봉고·콩가 패턴
        for st, f, v in ((0, 300, 1.0), (2, 420, 0.6), (3, 420, 0.7), (6, 300, 0.8), (8, 300, 1.0), (10, 420, 0.6), (11, 520, 0.7), (14, 420, 0.8)):
            S.add("bongo", bar, st, d_bongo(v, f))
        if sec != "I":
            for st in (0, 10): S.add("kick", bar, st, d_kick(0.75, 0.85))
            for st in (4, 12): S.add("snare", bar, st, d_snare(0.45, 260))
            for st in range(0, 16, 2): S.add("shaker", bar, st, d_shaker(0.7))
        # 통통 튀는 베이스
        for st, iv in ((0, 0), (3, 0), (6, 7), (8, 12), (10, 7), (14, 4 if kind != "m" else 3)):
            S.note("bass", bar, st, root - 12 + iv, 1.5, 0.8, inst_bass)
        if sec == "I":
            if bar % 2 == 1:
                for st in (12, 13, 14): S.add("wood", bar, st, d_wood(0.8, 2200 - st * 60))
            continue
        # 마림바 반주 (코드 분산)
        ct = chord_tones(root + 12, kind)
        for st in (0, 2, 4, 6, 8, 10, 12, 14):
            S.note("marimba", bar, st, ct[(st // 2) % 3] + (12 if st % 8 == 6 else 0), 1, 0.55, inst_marimba)
        ph = (leadB if sec == "B" else leadA)[bar % 4]
        for st, deg, ln in ph:
            S.note("lead", bar, st, scale_note(key + 12, PENTA, deg), ln, 0.65, inst_marimba)
            S.note("whistle", bar, st, scale_note(key + 24, PENTA, deg), ln, 0.2, inst_tri)
        # 원숭이 '우끼' 같은 짧은 상행 글리산도 (사인 스윕)
        if bar % 4 == 3:
            n = int(0.18 * SR); t = np.arange(n) / SR
            f = 700 + 900 * (t / t[-1]) ** 2
            S.add("monkey", bar, 14, np.sin(2 * np.pi * np.cumsum(f) / SR) * np.sin(np.pi * t / t[-1]) * 0.25)
    return mix_song(S, {"bongo": (0.7, -0.3, 0.1, None), "kick": (0.7, 0, 0, None), "snare": (0.5, 0.1, 0.15, None), "shaker": (0.45, 0.4, 0.05, None),
                        "bass": (0.8, 0, 0, None), "marimba": (0.55, -0.2, 0.18, None), "lead": (0.7, 0.2, 0.2, (S.step * 3, 0.3, 0.22)),
                        "whistle": (0.3, 0.3, 0.25, None), "wood": (0.5, 0.45, 0.1, None), "monkey": (0.5, 0.5, 0.2, None)})

SONGS = [
    ("rps_arena", "가위바위보 쇼다운", "칩튠 펑크 · 128 BPM · C장조", song_arena),
    ("desert_ruins", "모래 셔플", "이국적 셔플 · 112 BPM · E 프리지안 도미넌트", song_desert),
    ("frost_harbor", "펭귄 순찰대", "스윙 글로켄 · 124 BPM · F장조", song_harbor),
    ("neon_rooftops", "네온 홉", "신스웨이브 펌핑 · 118 BPM · A단조", song_neon),
    ("jungle_temple", "원숭이 소동", "마림바 정글 그루브 · 104 BPM · G 펜타토닉", song_jungle),
]

if __name__ == "__main__":
    import sys
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out_audio")
    os.makedirs(out, exist_ok=True)
    only = sys.argv[1:] or [s[0] for s in SONGS]
    for mid, title, desc, fn in SONGS:
        if mid not in only: continue
        st = fn()
        wav = f"{out}/{mid}.wav"
        wavfile.write(wav, SR, (st * 32767).astype(np.int16))
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-codec:a", "libmp3lame", "-b:a", "160k", f"{out}/{mid}.mp3"], check=True)
        print(mid, round(len(st) / SR, 1), "s")
