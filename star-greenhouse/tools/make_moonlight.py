"""Фортепианная обработка в духе 1-й части «Лунной сонаты» Бетховена (произведение в общественном достоянии):
python3 tools/make_moonlight.py -> art/audio/music_moonlight.ogg

Начало (такты 1-5) по нотам оригинала: триоли до-диез минора, басовые октавы, мелодия соль-диез.
Дальше продолжение в том же характере, которое возвращается к началу: бесшовная петля 16 тактов.
Синтез рояля: неидеальные обертоны, два слегка расстроенных струнных хора, удар молоточка, педаль по гармониям.
"""
import os, subprocess
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "audio")
rng = np.random.default_rng(1801)
BEAT = 60 / 54          # четверть (группа триолей)
BAR = BEAT * 4
BARS = 16
LOOP = BARS * BAR
TAIL = 6.0
N = int((LOOP + TAIL) * SR)
L = np.zeros(N)
R = np.zeros(N)


def hz(m):
    return 440 * 2 ** ((m - 69) / 12)


def filt(x, lo=None, hi=None, order=2):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / (1 + (f / hi) ** order)
    if lo:
        g *= 1 - 1 / (1 + (f / lo) ** order)
    return np.fft.irfft(X * g, len(x))


def piano(m, dur, vel):
    """Нота рояля длиной dur (до снятия педали), громкость vel 0..1."""
    f0 = hz(m)
    ring = dur + 0.25
    n = int(ring * SR)
    t = np.arange(n) / SR
    out = np.zeros(n)
    B = 0.00035 * (f0 / 261) ** 0.5
    bright = 0.55 + 0.6 * vel
    for k in range(1, 15):
        fk = f0 * k * np.sqrt(1 + B * k * k)
        if fk > 9000:
            break
        amp = (1 / k ** (1.35 - 0.35 * bright)) * (1 if k > 1 else 0.9)
        dec = (0.55 + 0.32 * k) * (f0 / 261) ** 0.45
        for det in (-0.0007, 0.0007):
            out += amp * np.sin(2 * np.pi * fk * (1 + det) * t + rng.uniform(0, 6.28)) * np.exp(-t * dec) * 0.5
    # двухступенчатое затухание: быстрое начало и долгий звон
    out *= 0.6 + 0.4 * np.exp(-t * 3.0)
    att = min(n, int(0.004 * SR))
    out[:att] *= np.linspace(0, 1, att)
    # молоточек
    hn = min(n, int(0.03 * SR))
    hammer = filt(rng.standard_normal(hn), 1200, 5000) * np.exp(-np.arange(hn) / SR * 160) * 0.05 * vel
    out[:hn] += hammer
    # снятие педали
    rel = int(0.22 * SR)
    end = int(dur * SR)
    if end < n:
        e = np.ones(n)
        e[end:min(n, end + rel)] = np.linspace(1, 0, min(n, end + rel) - end)
        e[min(n, end + rel):] = 0
        out *= e
    return out * vel


def put(x, at, pan):
    o = int(at * SR)
    if o >= N:
        return
    x = x[:N - o]
    L[o:o + len(x)] += x * np.sqrt(0.5 * (1 - pan))
    R[o:o + len(x)] += x * np.sqrt(0.5 * (1 + pan))


# ноты: до-диез4 = 61; арпеджио — тройки нот на каждую долю, бас — октавы, мелодия — (доля, длительность в долях, нота)
CSm, CSm_B = (56, 61, 64), (56, 61, 64)
A_, D_FS = (57, 61, 64), (57, 62, 66)
FSm = (57, 61, 66)
G7a, G7b, G7c, G7d = (56, 60, 66), (56, 61, 64), (56, 61, 63), (54, 60, 63)
E_B, B7 = (56, 59, 64), (57, 59, 63)
SCORE = [
    # (арпеджио на 4 доли, бас [(доля, длит, нота)], мелодия)
    ([CSm] * 4, [(0, 4, 37)], []),
    ([CSm_B] * 4, [(0, 4, 35)], []),
    ([A_, A_, D_FS, D_FS], [(0, 2, 33), (2, 2, 30)], []),
    ([G7a, G7b, G7c, G7d], [(0, 2, 32), (2, 2, 32)], []),
    ([CSm] * 4, [(0, 4, 37)], [(3, 0.75, 68), (3.75, 0.25, 68)]),
    ([FSm, FSm, G7a, G7a], [(0, 4, 37)], [(0, 3, 68), (3, 0.75, 68), (3.75, 0.25, 68)]),
    ([CSm, CSm, FSm, FSm], [(0, 2, 37), (2, 2, 42)], [(0, 2, 68), (2, 2, 69)]),
    ([G7a, G7a, G7d, G7d], [(0, 4, 32)], [(0, 2, 68), (2, 2, 66)]),
    ([E_B] * 4, [(0, 4, 35)], [(0, 3, 71), (3, 0.75, 71), (3.75, 0.25, 71)]),
    ([B7] * 4, [(0, 4, 35)], [(0, 2, 71), (2, 2, 69)]),
    ([E_B] * 4, [(0, 4, 40)], [(0, 3, 68), (3, 0.75, 68), (3.75, 0.25, 68)]),
    ([CSm, CSm, A_, A_], [(0, 2, 37), (2, 2, 33)], [(0, 2, 68), (2, 2, 69)]),
    ([FSm, FSm, G7a, G7a], [(0, 2, 30), (2, 2, 32)], [(0, 2, 69), (2, 2, 68)]),
    ([CSm] * 4, [(0, 4, 37)], [(0, 3, 64), (3, 0.75, 68), (3.75, 0.25, 68)]),
    ([A_, A_, D_FS, D_FS], [(0, 2, 33), (2, 2, 30)], [(0, 2, 69), (2, 2, 66)]),
    ([G7a, G7b, G7c, G7d], [(0, 2, 32), (2, 2, 32)], [(0, 2, 68), (2, 2, 63)]),
]
assert len(SCORE) == BARS

for b, (arps, bass, mel) in enumerate(SCORE):
    t0 = b * BAR
    # педаль меняется вместе с гармонией: нота арпеджио звучит до следующей смены аккорда
    for q in range(4):
        chord = arps[q]
        change = q + 1
        while change < 4 and arps[change] == chord:
            change += 1
        for i, m in enumerate(chord):
            at_beat = q + i / 3
            dur = (change - at_beat) * BEAT
            sw = 1.0 + 0.04 * np.sin(b * 1.7 + q)  # дыхание фразы
            vel = (0.30 + 0.05 * (i == 0)) * sw
            put(piano(m, dur, vel), t0 + at_beat * BEAT + rng.uniform(-0.006, 0.006), -0.25 + 0.2 * i)
    for beat, dur, m in bass:
        for oct_, v in ((0, 0.42), (12, 0.38)):
            put(piano(m + oct_, dur * BEAT, v), t0 + beat * BEAT, -0.4)
    for beat, dur, m in mel:
        put(piano(m, dur * BEAT + 0.15, 0.62), t0 + beat * BEAT + 0.01, 0.15)


def reverb(x, sec=3.0, wet=0.32):
    n = int(sec * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5.5 / sec)
    ir = filt(ir, 250, 5500)
    ir /= np.sqrt((ir ** 2).sum())
    size = 1 << int(np.ceil(np.log2(len(x) + n)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return x * (1 - wet) + y * wet


L, R = reverb(L), reverb(R)
nl = int(LOOP * SR)
for ch in (L, R):
    ch[:N - nl] += ch[nl:]
L, R = L[:nl], R[:nl]
# телефон: убрать гул ниже 90 Гц, чуть поднять середину, где живёт рояль
L, R = filt(L, 90, None, 2), filt(R, 90, None, 2)
st = np.stack([L, R], 1)
rms = np.sqrt((st ** 2).mean())
st = st * (10 ** (-17 / 20) / rms)
st = np.tanh(st * 1.1) / np.tanh(1.1) * 0.95
raw = os.path.join(OUT, "music_moonlight.raw")
(np.clip(st, -1, 1) * 32767).astype("<i2").tofile(raw)
out = os.path.join(OUT, "music_moonlight.ogg")
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", raw, "-c:a", "libvorbis", "-q:a", "5", out], check=True)
os.remove(raw)
print("ok music_moonlight", round(LOOP, 2), "s")
