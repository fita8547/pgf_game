"""추가 효과음 (mp3). sfx.py 의 합성 도구를 그대로 사용.
적중 hit_tick / 피격 hurt / 스킬 공통 dash, heal_loop(이음매 없는 루프), shield_up, deploy, trap_trigger, explosion_small
거점·궁극기 point_captured, point_lost, ult_ready / UI ui_click / 게임 종료 match_victory, match_defeat
다시 만들기: python3 sfx_new.py  → out_audio/sfx_new/*.mp3"""
import math, os
import numpy as np
from music import SR, lp1, hp1, mixs, reverb, inst_bell, inst_pluck, inst_saw, inst_tri, inst_pad, d_kick, d_crash, d_snare, mtof
from sfx import t_, noise, expenv, bp, sweep, place, norm, fade_out, write, rng

def tone(f, dur, tau, harm=((1, 1.0),), atk=0.002):
    t = t_(dur)
    return sum(a * np.sin(2 * np.pi * f * h * t) for h, a in harm) * np.exp(-t / tau) * np.clip(t / atk, 0, 1)

def arp(notes, step, dur=0.25, vel=0.6, inst=None, start=0.0):
    x = np.zeros(1)
    for k, m in enumerate(notes):
        s = (inst or (lambda f, d, v: inst_bell(f, d, v, decay=0.6)))(mtof(m), dur, vel)
        x = place(x, s, start + k * step)
    return x

S = {}
# 적중: 짧고 높은 '틱' (연사해도 귀가 안 아프게 얇게)
S["hit_tick"] = lambda: fade_out(mixs(tone(2400, 0.06, 0.012, ((1, 1), (2.01, 0.3))) * 0.9, bp(noise(0.02), 3000, 9000) * expenv(0.02, 0.003) * 0.3), 0.01)
# 피격: 둔탁한 퍽 + 낮은 신음 같은 저음
S["hurt"] = lambda: fade_out(mixs(sweep(180, 70, 0.18) * expenv(0.18, 0.05) * 0.9, bp(noise(0.12), 300, 2200) * expenv(0.12, 0.03) * 0.6,
                                  lp1(sweep(320, 220, 0.25), 900) * expenv(0.25, 0.08, atk=0.01) * 0.25), 0.03)
# 대시: 바람 휙
def dash():
    dur = 0.38; t = t_(dur); u = t / t[-1]
    w = noise(dur)
    lo, mid, hi = bp(w, 300, 1200), bp(w, 1200, 3500), bp(w, 3500, 8000)
    peak = np.sin(np.pi * u)
    return fade_out((lo * (1 - u) * 0.8 + mid * peak * 1.0 + hi * u ** 2 * 0.5) * peak ** 1.4, 0.03)
S["dash"] = dash
# 치유 루프: 부드러운 화음 + 반짝임. 길이 2초, 처음과 끝이 이어지도록 주기 맞춤
def heal_loop():
    dur = 2.0; t = t_(dur)
    base = sum(a * np.sin(2 * np.pi * f * t) for f, a in ((440, 0.25), (554, 0.18), (659, 0.18), (880, 0.08)))   # 2초에 정수 주기
    trem = 0.75 + 0.25 * np.sin(2 * np.pi * 2.0 * t)
    sp = np.zeros(len(t))
    for k in range(8):
        at = k * 0.25 + 0.06
        s = tone(mtof([88, 91, 95, 93, 88, 96, 91, 93][k]), 0.25, 0.07, ((1, 1), (2, 0.2)))
        p = int(at * SR); n = min(len(s), len(sp) - p); sp[p:p + n] += s[:n] * 0.18
        if n < len(s): sp[:len(s) - n] += s[n:] * 0.18      # 끝을 넘친 꼬리는 앞으로 감음
    return base * trem + sp
S["heal_loop"] = heal_loop
# 방패 올림: 금속 '징' + 위로 쓸어올림
S["shield_up"] = lambda: fade_out(reverb(mixs(tone(520, 0.6, 0.18, ((1, 1), (2.76, 0.4), (5.4, 0.2))) * 0.6, sweep(200, 900, 0.2, 0.6) * expenv(0.2, 0.08, atk=0.01) * 0.4,
                                              bp(noise(0.06), 1500, 6000) * expenv(0.06, 0.01) * 0.3), 0.15), 0.08)
# 설치: 툭 놓고 기계음 2번 '삑삑'
S["deploy"] = lambda: fade_out(mixs(sweep(160, 60, 0.12) * expenv(0.12, 0.03) * 0.9, bp(noise(0.05), 500, 3000) * expenv(0.05, 0.01) * 0.5,
                                    place(np.zeros(1), tone(1320, 0.07, 0.03) * 0.35, 0.16), place(np.zeros(1), tone(1760, 0.09, 0.04) * 0.35, 0.26)), 0.03)
# 덫 발동: 철컥 + 짧은 전기 지직
def trap():
    snap = mixs(bp(noise(0.03), 2000, 8000) * expenv(0.03, 0.004), tone(900, 0.12, 0.02, ((1, 1), (2.3, 0.5))) * 0.6)
    t = t_(0.35); buzz = np.sign(np.sin(2 * np.pi * 110 * t)) * (0.6 + 0.4 * rng.uniform(-1, 1, len(t))) * np.exp(-t / 0.12)
    return fade_out(mixs(snap, place(np.zeros(1), lp1(buzz, 3000) * 0.35, 0.03)), 0.04)
S["trap_trigger"] = trap
# 작은 폭발
S["explosion_small"] = lambda: fade_out(reverb(mixs(sweep(110, 35, 0.5) * expenv(0.5, 0.15) * 1.0, lp1(noise(0.7), 1800) * expenv(0.7, 0.18, atk=0.003) * 0.8,
                                                    bp(noise(0.1), 2000, 7000) * expenv(0.1, 0.02) * 0.4), 0.12), 0.1)
# 거점 점령: 밝은 상승 팡파레 / 상실: 하강 단조
S["point_captured"] = lambda: fade_out(reverb(mixs(arp([72, 76, 79, 84], 0.09, 0.5, 0.7), place(np.zeros(1), inst_bell(mtof(88), 0.9, 0.6, decay=1.0), 0.36),
                                                   place(np.zeros(1), d_kick(0.6), 0.0)), 0.25), 0.15)
S["point_lost"] = lambda: fade_out(reverb(mixs(arp([76, 72, 68, 63], 0.12, 0.45, 0.6, inst=lambda f, d, v: inst_saw(f, d, v * 0.5, cut0=2500, cut1=600)),
                                               place(np.zeros(1), lp1(sweep(300, 120, 0.6), 800) * expenv(0.6, 0.25) * 0.3, 0.3)), 0.25), 0.15)
# 궁극기 준비: 차오르는 쓸어올림 + 반짝 화음
S["ult_ready"] = lambda: fade_out(reverb(mixs(sweep(300, 1400, 0.45, 2.0) * expenv(0.45, 0.5, atk=0.3) * 0.3,
                                              place(np.zeros(1), mixs(*[inst_bell(mtof(m), 0.8, 0.5, decay=0.9) for m in (84, 88, 91, 96)]), 0.42)), 0.3), 0.15)
# UI 클릭
S["ui_click"] = lambda: fade_out(mixs(tone(1800, 0.04, 0.008) * 0.7, bp(noise(0.015), 2500, 8000) * expenv(0.015, 0.002) * 0.4), 0.005)
# 게임 종료 (glb/fx/match_victory, match_defeat 와 함께)
S["match_victory"] = lambda: fade_out(reverb(mixs(arp([67, 72, 76, 79], 0.12, 0.6, 0.7, inst=lambda f, d, v: inst_saw(f, d, v * 0.6, cut0=5000, cut1=1500)),
                                                  place(np.zeros(1), mixs(*[inst_bell(mtof(m), 1.6, 0.55, decay=1.4) for m in (72, 76, 79, 84)]), 0.5),
                                                  place(np.zeros(1), d_crash(0.6), 0.5), place(np.zeros(1), d_kick(0.8), 0.5)), 0.3), 0.3)
S["match_defeat"] = lambda: fade_out(reverb(mixs(arp([67, 63, 60, 55], 0.28, 0.9, 0.55, inst=lambda f, d, v: inst_tri(f, d, v)),
                                                 place(np.zeros(1), inst_pad(mtof(48), 1.6, 0.4, cut=900), 1.0)), 0.3), 0.4)

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out_audio", "sfx_new")
    os.makedirs(out, exist_ok=True)
    for k, fn in S.items():
        x = np.asarray(fn(), float)
        write(f"{out}/{k}", x, 0.6 if k in ("hit_tick", "ui_click", "heal_loop") else 0.85)
        print(k, round(len(x) / SR, 2), "s")
