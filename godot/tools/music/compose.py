"""Фоновая музыка «Козырной Арены» (синтез на numpy, без чужих сэмплов).

Две бесшовные петли в ре миноре на общей гармонии и общей теме:
  menu.ogg — главное меню: медленно (76 BPM), мягкий пэд, арфа, тема на колокольчиках, редкий барабан;
  game.ogg — партия: чуть быстрее (92 BPM), та же гармония, лютня-остинато, рамочный барабан и шейкер, тема на лютне.
Запуск: python compose.py <папка вывода>   (нужны numpy и ffmpeg с libvorbis)
"""
import sys, os, subprocess, wave
import numpy as np

SR = 44100
rng = np.random.default_rng(42)

def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)

NOTE = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}
def m(name):
    """'D4', 'Bb3', 'F#4' → номер MIDI"""
    p = NOTE[name[0]]
    i = 1
    while i < len(name) and name[i] in 'b#':
        p += -1 if name[i] == 'b' else 1
        i += 1
    return 12 * (int(name[i:]) + 1) + p

# ---------- инструменты ----------
def env_adsr(n, a, d, s, r, total):
    e = np.ones(total)
    ai, di, ri = int(a * SR), int(d * SR), int(r * SR)
    hold = max(0, n - ai - di)
    seg = np.concatenate([np.linspace(0, 1, max(ai, 1)), np.linspace(1, s, max(di, 1)), np.full(hold, s), np.linspace(s, 0, max(ri, 1))])
    out = np.zeros(total)
    out[:min(total, len(seg))] = seg[:total]
    return out

def pad(freq, dur, vel=0.5):
    total = int((dur + 2.0) * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for det in (-0.12, 0.0, 0.11):
        f = freq * 2 ** (det / 12)
        vib = 1 + 0.002 * np.sin(2 * np.pi * 4.5 * t + rng.uniform(0, 6))
        ph = 2 * np.pi * np.cumsum(f * vib) / SR
        for h in range(1, 10):
            sig += np.sin(h * ph + rng.uniform(0, 6)) / (h ** 1.7)
    sig /= 6
    e = env_adsr(int(dur * SR), 1.1, 0.6, 0.75, 1.8, total)
    return sig * e * vel

def harp(freq, vel=0.5, dur=2.6):
    total = int(dur * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for h in range(1, 9):
        sig += np.sin(2 * np.pi * freq * h * t) * np.exp(-t * (1.6 + h * 1.3)) / h ** 1.1
    att = np.minimum(1, t / 0.004)
    return sig * att * vel * 0.5

def lute(freq, vel=0.5, dur=1.4):
    total = int(dur * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for h in range(1, 12):
        amp = (1 / h) * (1.0 if h % 2 else 0.7)
        sig += np.sin(2 * np.pi * freq * h * t * (1 + 0.0008 * h)) * np.exp(-t * (3.0 + h * 1.9)) * amp
    att = np.minimum(1, t / 0.002)
    return sig * att * vel * 0.45

def bell(freq, vel=0.5, dur=3.5):
    total = int(dur * SR)
    t = np.arange(total) / SR
    sig = np.zeros(total)
    for ratio, amp, dec in ((1, 1, 1.2), (2.0, 0.5, 1.8), (2.76, 0.35, 2.6), (5.4, 0.15, 4.0), (8.93, 0.07, 6.0)):
        sig += np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t * dec) * amp
    return sig * np.minimum(1, t / 0.003) * vel * 0.35

def drum(vel=0.6, low=True):
    dur = 0.9
    total = int(dur * SR)
    t = np.arange(total) / SR
    f = (92 if low else 150) * np.exp(-t * 7) + (48 if low else 90)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * (6 if low else 10))
    noise = rng.uniform(-1, 1, total)
    k = np.ones(40) / 40
    noise = np.convolve(noise, np.ones(160) / 160, 'same') * np.exp(-t * 35) * 2.0
    return (body + noise) * vel

def shaker(vel=0.2):
    total = int(0.12 * SR)
    t = np.arange(total) / SR
    noise = rng.uniform(-1, 1, total)
    # полоса ~3–7 кГц: мягкий «шорох», без резкого шипения
    noise = np.convolve(noise, np.ones(3) / 3, 'same') - np.convolve(noise, np.ones(9) / 9, 'same')
    return noise * np.exp(-t * 55) * np.minimum(1, t / 0.01) * vel

# ---------- микшер ----------
class Track:
    def __init__(self, seconds):
        self.n = int(seconds * SR)
        self.buf = np.zeros((2, self.n + SR * 6))
    def add(self, sig, at, pan=0.0, gain=1.0):
        i = int(at * SR)
        l = np.cos((pan + 1) * np.pi / 4) * gain
        r = np.sin((pan + 1) * np.pi / 4) * gain
        end = min(self.buf.shape[1], i + len(sig))
        self.buf[0, i:end] += sig[:end - i] * l
        self.buf[1, i:end] += sig[:end - i] * r
    def loop_audio(self):
        # хвост после конца петли переносим в начало — петля бесшовная
        out = self.buf[:, :self.n].copy()
        tail = self.buf[:, self.n:]
        out[:, :tail.shape[1]] += tail[:, :self.n]
        return out

def reverb(x, seconds=2.6, mix=0.28):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(x)
    L = x.shape[1]
    size = 1
    while size < L + n:
        size *= 2
    for ch in range(2):
        ir = rng.uniform(-1, 1, n) * np.exp(-t * 3.2)
        ir[:int(0.012 * SR)] = 0
        ir /= np.sqrt(np.sum(ir ** 2))
        y = np.fft.irfft(np.fft.rfft(x[ch], size) * np.fft.rfft(ir, size), size)
        wet = y[:L].copy()
        wet[:L] += 0   # хвост реверба после петли переносим в начало
        tail = y[L:L + n]
        wet[:len(tail)] += tail[:L]
        out[ch] = x[ch] * (1 - mix) + wet * mix
    return out

def master(x):
    x = x / (np.max(np.abs(x)) + 1e-9) * 0.82
    return np.tanh(x * 1.15) / np.tanh(1.15)

def save_ogg(x, path):
    wav = path[:-4] + '.wav'
    pcm = (np.clip(x, -1, 1) * 32000).astype('<i2').T.copy()
    with wave.open(wav, 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', wav, '-c:a', 'libvorbis', '-q:a', '4', path], check=True)
    os.remove(wav)

# ---------- гармония и тема (общие для обеих петель) ----------
# 16 тактов: i–VI–VII–V (с ля мажором для «старинной» тяжести), затем i–III–VII–V
CHORDS = [['D3', 'A3', 'D4', 'F4'], ['Bb2', 'F3', 'Bb3', 'D4'], ['C3', 'G3', 'C4', 'E4'], ['A2', 'E3', 'A3', 'C#4'],
          ['D3', 'A3', 'D4', 'F4'], ['F2', 'C3', 'F3', 'A3'], ['C3', 'G3', 'C4', 'E4'], ['A2', 'E3', 'A3', 'C#4']] * 2
# тема: (такт, доля, нота, длительность в долях)
THEME = [(0, 0, 'D5', 1), (0, 1, 'F5', 1), (0, 2, 'E5', 1), (0, 3, 'D5', 1),
         (1, 0, 'C5', 1.5), (1, 1.5, 'D5', 0.5), (1, 2, 'Bb4', 2),
         (2, 0, 'C5', 1), (2, 1, 'E5', 1), (2, 2, 'G5', 1), (2, 3, 'F5', 1),
         (3, 0, 'E5', 2), (3, 2, 'C#5', 2)]

def compose(kind):
    bpm = 76 if kind == 'menu' else 92
    beat = 60 / bpm
    bars = 16
    tr = Track(bars * 4 * beat)
    for b, ch in enumerate(CHORDS):
        t0 = b * 4 * beat
        # пэд — в меню громче, в партии тише
        for k, nn in enumerate(ch):
            tr.add(pad(midi(m(nn)), 4 * beat * 0.98, 0.33 if kind == 'menu' else 0.22), t0, pan=(-0.4 + k * 0.27))
        root = midi(m(ch[0]))
        if kind == 'menu':
            # арфа: медленное восходящее арпеджио восьмыми
            arp = [ch[0], ch[1], ch[2], ch[3], ch[2], ch[1], ch[2], ch[3]]
            for i, nn in enumerate(arp):
                tr.add(harp(midi(m(nn) + 12), 0.32 + 0.08 * (i == 0)), t0 + i * beat / 2, pan=0.25)
            if b % 2 == 0:
                tr.add(drum(0.35), t0, pan=0.0)
        else:
            # лютня: остинато «бас — квинта — октава» восьмыми
            pat = [ch[0], ch[1], ch[2], ch[1], ch[0], ch[1], ch[3], ch[1]]
            for i, nn in enumerate(pat):
                tr.add(lute(midi(m(nn) + 12), 0.36 if i % 2 == 0 else 0.26), t0 + i * beat / 2, pan=-0.2)
            # рамочный барабан: 1, «и» второй, 3, 4 ; шейкер — шестнадцатыми
            for pos, v, low in ((0, 0.55, True), (1.5, 0.3, False), (2, 0.42, True), (3, 0.3, False), (3.5, 0.22, False)):
                tr.add(drum(v, low), t0 + pos * beat, pan=0.05)
            for i in range(8):
                tr.add(shaker(0.05 if i % 2 else 0.035), t0 + i * beat / 2, pan=0.35)
            tr.add(pad(root / 2, 4 * beat * 0.95, 0.2), t0)   # низкий бас
    # тема: в меню — колокольчики в тактах 4–7 и 12–15; в партии — лютня в тактах 8–15
    starts = (4, 12) if kind == 'menu' else (8, 12)
    for s in starts:
        for bb, pos, nn, ln in THEME:
            at = (s + bb) * 4 * beat + pos * beat
            if kind == 'menu':
                tr.add(bell(midi(m(nn)), 0.42), at, pan=0.1)
            else:
                tr.add(lute(midi(m(nn)), 0.5, dur=max(1.0, ln * beat * 1.6)), at, pan=0.15)
                tr.add(bell(midi(m(nn) + 12), 0.08), at, pan=0.3)
    x = tr.loop_audio()
    x = reverb(x, 3.0 if kind == 'menu' else 2.2, 0.34 if kind == 'menu' else 0.24)
    return master(x)

if __name__ == '__main__':
    out = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(out, exist_ok=True)
    for kind in ('menu', 'game'):
        save_ogg(compose(kind), os.path.join(out, kind + '.ogg'))
        print('ok', kind)
