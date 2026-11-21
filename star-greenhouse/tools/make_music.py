"""Спокойный космический эмбиент для «Звёздной оранжереи»: пэды, колокольчики с эхом, глубокий бас, реверберация.
Петля без шва (рендерим два прохода и берём второй, чтобы хвост реверба перешёл в начало).
python3 tools/make_music.py -> art/audio/ambient.ogg"""
import os, subprocess
import numpy as np

SR = 32000
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


# аккорды (миди-ноты): D лидийский, мягкая прогрессия
CHORDS = [
    [50, 57, 62, 66, 69, 76],   # Dmaj9
    [47, 54, 59, 62, 66, 73],   # Bm11
    [43, 50, 55, 59, 62, 73],   # Gmaj7#11
    [45, 52, 57, 61, 64, 71],   # A(add9)
    [50, 57, 62, 64, 69, 74],   # Dadd9
    [42, 49, 54, 57, 61, 68],   # F#m7
    [43, 50, 55, 59, 66, 71],   # Gmaj7
    [45, 52, 57, 59, 64, 69],   # Asus
]
BAR = 8.0  # секунд на аккорд
LOOP = BAR * len(CHORDS)


def env(n, a, r, sus=1.0):
    t = np.arange(n) / SR
    e = np.minimum(1, t / a) * sus
    rel = np.clip((n / SR - t) / r, 0, 1)
    return e * rel


def lowpass(x, cutoff):
    a = np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    # однополюсный фильтр, два прохода для крутизны
    for _ in range(2):
        out = np.empty_like(x)
        acc = 0.0
        for i in range(0, len(x), 4096):
            seg = x[i:i + 4096]
            o = np.empty_like(seg)
            for j, v in enumerate(seg):
                acc = (1 - a) * v + a * acc
                o[j] = acc
            out[i:i + 4096] = o
        x = out
    return x


def pad_voice(freq, dur, detune):
    n = int(dur * SR)
    t = np.arange(n) / SR
    sig = np.zeros(n)
    for k, dt in enumerate((-detune, 0, detune)):
        f = freq * (1 + dt)
        ph = rng.uniform(0, 6.28)
        # мягкая «пила» из нескольких гармоник
        for h in range(1, 7):
            sig += np.sin(2 * np.pi * f * h * t + ph * h) / (h ** 1.6)
    lfo = 0.75 + 0.25 * np.sin(2 * np.pi * 0.07 * t + rng.uniform(0, 6))
    return sig * lfo / 3


def bell(freq, dur):
    n = int(dur * SR)
    t = np.arange(n) / SR
    mod = np.sin(2 * np.pi * freq * 3.5 * t) * 2.2 * np.exp(-t * 2.5)
    s = np.sin(2 * np.pi * freq * t + mod) * np.exp(-t * 1.6)
    s += 0.3 * np.sin(2 * np.pi * freq * 2 * t) * np.exp(-t * 3)
    return s * np.minimum(1, t / 0.004)


def render_pass():
    total = int(LOOP * 2 * SR)
    L = np.zeros(total)
    R = np.zeros(total)
    for rep in range(2):
        for ci, chord in enumerate(CHORDS):
            t0 = (rep * len(CHORDS) + ci) * BAR
            i0 = int(t0 * SR)
            dur = BAR + 3.0
            n = int(dur * SR)
            e = env(n, 2.5, 3.5)
            for k, note in enumerate(chord[1:]):
                v = pad_voice(midi(note), dur, 0.003 + 0.001 * k) * e * 0.05
                pan = 0.5 + 0.35 * np.sin(k * 1.7)
                end = min(total, i0 + n)
                L[i0:end] += v[:end - i0] * (1 - pan)
                R[i0:end] += v[:end - i0] * pan
            # бас
            tb = np.arange(n) / SR
            bass = np.sin(2 * np.pi * midi(chord[0] - 12) * tb) * e * 0.16
            end = min(total, i0 + n)
            L[i0:end] += bass[:end - i0]
            R[i0:end] += bass[:end - i0]
            # колокольчики: неспешный узор из нот аккорда
            pattern = [3, 4, 5, 4, 2, 5, 3, 4]
            for s in range(8):
                if rng.random() < 0.72:
                    note = chord[pattern[(s + ci) % 8]] + 12
                    bt = t0 + s * (BAR / 8) + rng.uniform(-0.02, 0.02)
                    b = bell(midi(note), 3.0) * (0.07 + 0.03 * rng.random())
                    bi = max(0, int(bt * SR))
                    if bi >= total:
                        continue
                    end = min(total, bi + len(b))
                    pan = rng.uniform(0.25, 0.75)
                    L[bi:end] += b[:end - bi] * (1 - pan)
                    R[bi:end] += b[:end - bi] * pan
            # редкие «звёздные» искры
            for s in range(3):
                if rng.random() < 0.5:
                    note = chord[rng.integers(2, 6)] + 24
                    b = bell(midi(note), 2.0) * 0.025
                    bi = int((t0 + rng.uniform(0, BAR)) * SR)
                    if bi >= total:
                        continue
                    end = min(total, bi + len(b))
                    L[bi:end] += b[:end - bi] * 0.7
                    R[bi:end] += b[:end - bi] * 0.3
    return L, R


def reverb(x, seconds=4.0, seed=1):
    n = int(seconds * SR)
    r = np.random.default_rng(seed)
    ir = r.standard_normal(n) * np.exp(-np.arange(n) / SR * 3.2 / seconds * 2.2)
    ir[:int(0.015 * SR)] *= np.linspace(0, 1, int(0.015 * SR))
    ir /= np.sqrt((ir ** 2).sum())
    m = len(x) + n
    size = 1 << int(np.ceil(np.log2(m)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:len(x)]
    return y


def echo(x, delay, fb, mix):
    d = int(delay * SR)
    y = x.copy()
    for k in range(1, 6):
        y[d * k:] += x[:-d * k] * (fb ** k) * mix
    return y


if __name__ == "__main__":
    L, R = render_pass()
    L = echo(L, 0.48, 0.45, 0.6)
    R = echo(R, 0.36, 0.45, 0.6)
    wetL, wetR = reverb(L, 4.5, 1), reverb(R, 4.5, 2)
    L = L * 0.55 + wetL * 0.9
    R = R * 0.55 + wetR * 0.9
    # тёплый фильтр сверху: убираем резкость
    k = int(LOOP * SR)
    L, R = L[k:2 * k], R[k:2 * k]
    peak = max(np.abs(L).max(), np.abs(R).max())
    L, R = L / peak * 0.8, R / peak * 0.8
    st = np.stack([L, R], 1)
    raw = os.path.join(OUT, "ambient.raw")
    (st * 32767).astype("<i2").tofile(raw)
    out = os.path.join(OUT, "ambient.ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "2", "-i", raw,
                    "-af", "lowpass=f=7000,highpass=f=35", "-c:a", "libvorbis", "-q:a", "5", out], check=True)
    os.remove(raw)
    print("ok", out, round(LOOP, 1), "s", os.path.getsize(out) // 1024, "KB")
