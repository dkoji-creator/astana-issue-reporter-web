"""Фоновая музыка «Звёздной оранжереи»: python3 tools/make_music.py -> art/audio/music_main.ogg

Спокойный мелодичный «космический лоу-фай»: пэд, арпеджио колокольчиков, мелодия, мягкие барабаны.
Слышно на телефоне: основная энергия в полосе 200-4000 Гц, бас дан гармониками.
Бесшовная петля: хвост реверберации переносится в начало.
"""
import os, subprocess
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "audio")
rng = np.random.default_rng(11)
BPM = 76
BEAT = 60 / BPM
BAR = BEAT * 4
BARS = 16
LOOP = BARS * BAR
TAIL = 4.0
N = int((LOOP + TAIL) * SR)
L = np.zeros(N)
R = np.zeros(N)


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


def t_(d):
    return np.arange(int(d * SR)) / SR


def filt(x, lo=None, hi=None, order=4):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / (1 + (f / hi) ** order)
    if lo:
        g *= 1 - 1 / (1 + (f / lo) ** order)
    return np.fft.irfft(X * g, len(x))


def put(x, at, pan=0.0, gain=1.0):
    o = int(at * SR)
    if o >= N:
        return
    x = x[:N - o] * gain
    L[o:o + len(x)] += x * np.sqrt(0.5 * (1 - pan))
    R[o:o + len(x)] += x * np.sqrt(0.5 * (1 + pan))


def adsr(n, a, d, s, r):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = min(na, n)
    e[:na] = np.linspace(0, 1, na)
    if na + nd < n:
        e[na:na + nd] = np.linspace(1, s, nd)
    if nr > 0 and nr < n:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, d, harm=10, detune=0.0):
    t = t_(d)
    out = np.zeros(len(t))
    for k in range(1, harm + 1):
        out += np.sin(2 * np.pi * f * (1 + detune) * k * t + k * 0.7) / k
    return out


def bell(f, d, decay=2.5):
    t = t_(d)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 1.4 * np.exp(-t * 5)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay)
    s += 0.25 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * decay * 1.5)
    return s * np.minimum(1, t / 0.003)


def lead(f, d):
    t = t_(d)
    vib = np.sin(2 * np.pi * 5.2 * t) * 0.004 * np.minimum(1, t / 0.4)
    ph = 2 * np.pi * f * np.cumsum(1 + vib) / SR
    s = np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.18 * np.sin(3 * ph) + 0.08 * np.sin(4 * ph)
    return s * adsr(len(t), 0.06, 0.2, 0.75, min(0.35, d * 0.5))


# аккорды: Fmaj7 | Em7 | Am9 | G6, мелодия в до мажоре / ля миноре
CHORDS = [
    ([53, 57, 60, 64], 41),   # F A C E, бас F
    ([52, 55, 59, 62], 40),   # E G B D, бас E
    ([57, 60, 64, 67, 71], 45),  # A C E G B, бас A
    ([55, 59, 62, 64], 43),   # G B D E, бас G
]

# пэд
for b in range(BARS):
    notes, _ = CHORDS[b % 4]
    d = BAR + 0.6
    for i, m in enumerate(notes):
        for det, pan in ((-0.0025, -0.5), (0.0025, 0.5)):
            v = filt(saw(midi(m), d, 12, det), None, 1800, 2) * adsr(int(d * SR), 0.7, 0.4, 0.8, 0.7)
            put(v, b * BAR, pan, 0.045)

# бас: корень, половинные ноты, с гармониками (чтобы было слышно на телефоне)
for b in range(BARS):
    _, root = CHORDS[b % 4]
    for h in range(2):
        d = BAR / 2 * 0.95
        t = t_(d)
        f = midi(root + 12)
        x = np.tanh(2.2 * np.sin(2 * np.pi * f * t)) + 0.3 * np.sin(2 * np.pi * f * 2 * t)
        put(x * adsr(len(t), 0.01, 0.3, 0.6, 0.15), b * BAR + h * BAR / 2, 0, 0.11 if b >= 2 else 0.0)

# арпеджио колокольчиков восьмыми с эхом
pattern = [0, 1, 2, 3, 2, 1, 2, 3]
for b in range(BARS):
    notes, _ = CHORDS[b % 4]
    up = [m + 12 for m in notes[:4]]
    for k in range(8):
        if b < 1 and k % 2 == 1:
            continue
        m = up[pattern[k] % len(up)] + (12 if (b % 4 == 3 and k >= 6) else 0)
        at = b * BAR + k * BEAT / 2 + (0.03 if k % 2 == 1 else 0)  # лёгкий свинг
        x = bell(midi(m), 1.4)
        pan = -0.35 if k % 2 == 0 else 0.35
        put(x, at, pan, 0.07)
        put(filt(x, 400, 5000), at + BEAT * 0.75, -pan, 0.03)  # эхо
        put(filt(x, 500, 4000), at + BEAT * 1.5, pan, 0.014)

# мелодия (с 5-го такта): простой запоминающийся мотив
MEL = [
    [(0, 76, 1.5), (1.5, 74, 0.5), (2, 72, 1), (3, 69, 1)],
    [(0, 71, 2), (2, 67, 1), (3, 69, 1)],
    [(0, 72, 1.5), (1.5, 76, 0.5), (2, 79, 1.5), (3.5, 77, 0.5)],
    [(0, 76, 3), (3, 74, 1)],
    [(0, 76, 1.5), (1.5, 74, 0.5), (2, 72, 1), (3, 74, 1)],
    [(0, 71, 1.5), (1.5, 72, 0.5), (2, 74, 2)],
    [(0, 81, 1.5), (1.5, 79, 0.5), (2, 76, 1), (3, 72, 1)],
    [(0, 74, 2.5), (2.5, 71, 1.5)],
]
for b in range(4, BARS):
    phrase = MEL[(b - 4) % len(MEL)]
    for beat, m, dur in phrase:
        d = dur * BEAT
        x = lead(midi(m), d + 0.25)
        put(filt(x, 250, 4500), b * BAR + beat * BEAT, 0.1, 0.06)
        put(filt(x, 400, 3500), b * BAR + beat * BEAT + BEAT * 0.75, -0.4, 0.018)

# барабаны: мягкая бочка со щелчком, хлопок на 2 и 4, шейкер
def kick():
    d = 0.35
    t = t_(d)
    f = 150 * np.exp(-t * 18) + 55
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9)
    click = filt(rng.standard_normal(len(t)), 1500, 6000) * np.exp(-t * 120) * 0.5
    return np.tanh(body * 1.6) * 0.8 + click


def snap():
    d = 0.25
    t = t_(d)
    return filt(rng.standard_normal(len(t)), 900, 5000) * np.exp(-t * 22) + np.sin(2 * np.pi * 330 * t) * np.exp(-t * 30) * 0.4


def shaker():
    d = 0.08
    t = t_(d)
    return filt(rng.standard_normal(len(t)), 5000, 11000) * np.minimum(1, t / 0.01) * np.exp(-t * 50)


K, S = kick(), snap()
for b in range(2, BARS):
    for q in range(4):
        at = b * BAR + q * BEAT
        if q in (0, 2):
            put(K, at, 0, 0.16)
        if q in (1, 3):
            put(S, at, 0.05, 0.05)
    for e in range(8):
        put(shaker(), b * BAR + e * BEAT / 2 + (0.035 if e % 2 else 0), 0.3 if e % 2 else -0.3, 0.025 if e % 2 else 0.04)

# переходный «взмах» каждые 4 такта
for b in (3, 7, 11, 15):
    d = BAR * 0.5
    x = filt(rng.standard_normal(int(d * SR)), 2000, 9000) * np.linspace(0, 1, int(d * SR)) ** 2
    put(x, b * BAR + BAR * 0.5, 0, 0.03)


# реверберация (общая шина)
def reverb(x, sec=2.6, wet=0.28):
    n = int(sec * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5 / sec)
    ir = filt(ir, 300, 6000)
    ir /= np.sqrt((ir ** 2).sum())
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return x * (1 - wet) + y * wet


L = reverb(L)
R = reverb(R)
# бесшовная петля: хвост после конца петли добавляется в начало
nl = int(LOOP * SR)
for ch in (L, R):
    ch[:N - nl] += ch[nl:]
L, R = L[:nl], R[:nl]
st = np.stack([L, R], 1)
st = filt(st[:, 0], 90, None, 2), filt(st[:, 1], 90, None, 2)
st = np.stack(st, 1)
rms = np.sqrt((st ** 2).mean())
st = st * (10 ** (-16 / 20) / rms)
st = np.tanh(st * 1.1) / np.tanh(1.1) * 0.95
raw = os.path.join(OUT, "music_main.raw")
(np.clip(st, -1, 1) * 32767).astype("<i2").tofile(raw)
out = os.path.join(OUT, "music_main.ogg")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", raw, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
os.remove(raw)
print("ok music_main", round(LOOP, 2), "s")
