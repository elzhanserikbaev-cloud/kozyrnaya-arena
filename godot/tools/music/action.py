"""«Боевая» петля партии: энергично, но без долбёжки (112 BPM, ре минор, тема как в меню).

Струнное спиккато шестнадцатыми, подвижный бас, синкопированные томы со сбивками в конце фраз,
акценты духовых на смене аккорда, форма A–B–C (остинато → тема → мост с iv и вариацией темы).
Запуск: python action.py <папка вывода>
"""
import os, sys
import numpy as np
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from compose import (SR, rng, midi, m, env_adsr, pad, lute, bell, shaker, Track, reverb, master, save_ogg, THEME)


def strings_stacc(freq, vel=0.3, dur=0.22):
    total = int(dur * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for h in range(1, 14):
        sig += np.sin(2 * np.pi * freq * h * t * (1 + 0.0006 * h) + rng.uniform(0, 6)) / h ** 1.25
    bow = np.convolve(rng.uniform(-1, 1, total), np.ones(4) / 4, 'same') * 0.05
    e = np.minimum(1, t / 0.008) * np.exp(-t * 16)
    return (sig * 0.35 + bow) * e * vel


def brass(freq, dur, vel=0.4):
    total = int((dur + 0.4) * SR)
    t = np.arange(total) / SR
    bright = np.minimum(1, t / 0.12)
    sig = np.zeros(total)
    for h in range(1, 16):
        amp = (1 / h ** 1.1) * (0.3 + 0.7 * bright ** (h / 4))
        sig += np.sin(2 * np.pi * freq * h * t) * amp
    e = env_adsr(int(dur * SR), 0.04, 0.25, 0.65, 0.35, total)
    return sig * e * vel * 0.18


def tom(pitch=110, vel=0.5):
    total = int(0.6 * SR)
    t = np.arange(total) / SR
    f = pitch * (1 + 0.6 * np.exp(-t * 25))
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    skin = np.convolve(rng.uniform(-1, 1, total), np.ones(30) / 30, 'same') * np.exp(-t * 40) * 1.5
    return (body + skin) * vel


def riser(dur, vel=0.12):
    total = int(dur * SR)
    t = np.arange(total) / SR
    lo = np.convolve(rng.uniform(-1, 1, total), np.ones(12) / 12, 'same')
    return lo * (t / dur) ** 2 * vel


def bass_pluck(freq, vel=0.5, dur=0.5):
    total = int(dur * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for h in range(1, 7):
        sig += np.sin(2 * np.pi * freq * h * t) * np.exp(-t * (5 + h * 3)) / h
    return sig * np.minimum(1, t / 0.003) * vel


Dm = ['D3', 'A3', 'D4', 'F4']; Bb = ['Bb2', 'F3', 'Bb3', 'D4']; C = ['C3', 'G3', 'C4', 'E4']
A = ['A2', 'E3', 'A3', 'C#4']; F = ['F2', 'C3', 'F3', 'A3']; Gm = ['G2', 'D3', 'G3', 'Bb3']
CHORDS = [Dm, Bb, C, A] * 2 + [Dm, F, C, A] * 2 + [Gm, Dm, Bb, A, Gm, Bb, C, A]
THEME_VAR = [(0, 0, 'G5', 1), (0, 1, 'F5', 0.5), (0, 1.5, 'E5', 0.5), (0, 2, 'D5', 2),
             (1, 0, 'A5', 1), (1, 1, 'F5', 1), (1, 2, 'D5', 2),
             (2, 0, 'F5', 1), (2, 1, 'E5', 0.5), (2, 1.5, 'D5', 0.5), (2, 2, 'C5', 1), (2, 3, 'D5', 1),
             (3, 0, 'E5', 3), (3, 3, 'C#5', 1)]


def compose_action():
    bpm = 112
    beat = 60 / bpm
    bars = len(CHORDS)
    tr = Track(bars * 4 * beat)
    for b, ch in enumerate(CHORDS):
        t0 = b * 4 * beat
        sec = 'A' if b < 8 else ('B' if b < 16 else 'C')
        root = m(ch[0])
        for k, nn in enumerate(ch):
            tr.add(pad(midi(m(nn)), 4 * beat * 0.98, 0.14), t0, pan=(-0.4 + k * 0.27))
        figure = [ch[1], ch[2], ch[3], ch[2]]
        for i in range(16):
            nn = m(figure[i % 4]) + (12 if sec == 'C' and i % 8 >= 4 else 0)
            acc = 0.42 if i % 4 == 0 else (0.32 if i % 2 == 0 else 0.22)
            tr.add(strings_stacc(midi(nn), acc), t0 + i * beat / 4, pan=0.3 if i % 2 else -0.15)
        nxt = m(CHORDS[(b + 1) % bars][0])
        line = [root, root, root + 12, root, root, root + 7, root + 12, nxt + (1 if nxt < root else -1)]
        for i, nn in enumerate(line):
            tr.add(bass_pluck(midi(nn - 12), 0.44 if i % 2 == 0 else 0.32), t0 + i * beat / 2)
        hits = [(0, 80, 0.42), (0.75, 115, 0.22), (1.5, 145, 0.3), (2.5, 80, 0.36), (3, 115, 0.3), (3.5, 145, 0.25)]
        if b < 4:
            hits = [(0, 72, 0.45), (2.5, 72, 0.35), (3.5, 140, 0.18)]
        for pos, ptc, v in hits:
            tr.add(tom(ptc, v), t0 + pos * beat, pan=(-0.2 if ptc > 100 else 0.05))
        if b % 4 == 3:
            for j, (pos, ptc) in enumerate([(3, 160), (3.25, 140), (3.5, 120), (3.75, 95)]):
                tr.add(tom(ptc, 0.28 + 0.05 * j), t0 + pos * beat, pan=0.3 - 0.2 * j)
        for i in range(4):
            tr.add(shaker(0.035), t0 + (i + 0.5) * beat, pan=0.4)
        if sec in ('B', 'C'):
            for nn in ch[1:]:
                tr.add(brass(midi(m(nn)), beat * (1.5 if sec == 'B' else 3.0), 0.5), t0, pan=-0.1)
        if b in (7, 15, 23):
            tr.add(riser(4 * beat, 0.1), t0)
    for s in (8, 12):
        for bb, pos, nn, ln in THEME:
            at = (s + bb) * 4 * beat + pos * beat
            tr.add(brass(midi(m(nn)), ln * beat * 0.95, 0.55), at, pan=0.15)
            tr.add(bell(midi(m(nn) + 12), 0.07), at, pan=0.3)
    for s in (16, 20):
        for bb, pos, nn, ln in THEME_VAR:
            at = (s + bb) * 4 * beat + pos * beat
            tr.add(lute(midi(m(nn)), 0.55, dur=max(0.8, ln * beat * 1.4)), at, pan=0.2)
            tr.add(brass(midi(m(nn) - 12), ln * beat * 0.9, 0.3), at, pan=-0.2)
    x = tr.loop_audio()
    x = reverb(x, 1.9, 0.2)
    return master(x)


if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    save_ogg(compose_action(), os.path.join(out, 'game.ogg'))
    print('ok game')
