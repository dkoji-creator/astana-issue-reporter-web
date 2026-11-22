"""Синтез звуковых эффектов «Звёздной оранжереи»: python3 tools/make_sfx.py -> art/audio/sfx_*.ogg"""
import os, subprocess
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a, d, curve=4.0):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) * curve / max(d, 1e-3))
    return e


def bell(f, d, bright=2.0, decay=3.0):
    t = t_(d)
    mod = np.sin(2 * np.pi * f * 3.01 * t) * bright * np.exp(-t * 6)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay)
    s += 0.25 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * decay * 1.6)
    return s * np.minimum(1, t / 0.002)


def noise(d):
    return rng.standard_normal(int(d * SR))


def lowpass(x, fc):
    # частотный фильтр через БПФ (мягкий срез)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / (1 + (f / max(fc, 1)) ** 4)
    return np.fft.irfft(X, len(x))


def bandpass(x, lo, hi):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= (1 / (1 + (f / hi) ** 4)) * (1 - 1 / (1 + (f / lo) ** 4))
    return np.fft.irfft(X, len(x))


def sweep(f0, f1, d):
    t = t_(d)
    f = f0 * (f1 / f0) ** (t / d)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def reverb(x, sec=1.2, wet=0.3):
    n = int(sec * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5 / sec)
    ir /= np.sqrt((ir ** 2).sum())
    m = len(x) + n
    size = 1 << int(np.ceil(np.log2(m)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:m]
    out = np.zeros(m)
    out[:len(x)] = x
    return out * (1 - wet) + y * wet


def mix(*parts):
    n = max(len(p) for _, p in parts)
    out = np.zeros(n)
    for off, p in parts:
        o = int(off * SR)
        out[o:o + len(p)] += p[:max(0, n - o)]
    return out


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


def save(name, x, gain=0.85):
    x = x / max(1e-6, np.abs(x).max()) * gain
    fade = int(0.01 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    raw = os.path.join(OUT, name + ".raw")
    (x * 32767).astype("<i2").tofile(raw)
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", raw, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    os.remove(raw)
    print("ok", name, round(len(x) / SR, 2), "s")


SFX = {}

# посадка: мягкий «чпок» и глухой удар земли
d = 0.35
pop = sweep(520, 160, 0.12) * env(int(0.12 * SR), 0.002, 0.08)
thud = lowpass(noise(0.2), 400) * env(int(0.2 * SR), 0.002, 0.12)
SFX["sfx_plant"] = reverb(mix((0, pop * 0.9), (0.02, thud * 0.8), (0.06, bell(midi(84), 0.25, 1, 9) * 0.25)), 0.4, 0.15)

# полив: всплеск и пузырьки
spl = bandpass(noise(0.5), 800, 5000) * env(int(0.5 * SR), 0.01, 0.3)
bub = sum(mix((0.05 + k * 0.06, sweep(600 + 200 * k, 1400 + 300 * k, 0.05) * env(int(0.05 * SR), 0.002, 0.04) * 0.3)) for k in range(5))
SFX["sfx_water"] = reverb(mix((0, spl), (0, bub)), 0.5, 0.2)

# сбор: два звонких колокольчика вверх
SFX["sfx_harvest"] = reverb(mix((0, bell(midi(79), 0.6)), (0.08, bell(midi(86), 0.8))), 0.8, 0.25)

# монеты: классический «дзынь-дзынь»
c1 = np.sin(2 * np.pi * midi(95) * t_(0.09)) * env(int(0.09 * SR), 0.001, 0.08)
c2 = np.sin(2 * np.pi * midi(100) * t_(0.35)) * env(int(0.35 * SR), 0.001, 0.25)
SFX["sfx_coin"] = reverb(mix((0, c1), (0.07, c2)), 0.5, 0.2)

# звезда: искристое восходящее арпеджио
SFX["sfx_star"] = reverb(mix(*[(k * 0.045, bell(midi(84 + s), 0.7, 1.5, 4) * (0.6 + 0.1 * k)) for k, s in enumerate([0, 4, 7, 12, 16])]), 1.0, 0.35)

# метеорит: свист падения и взрыв
wh = bandpass(noise(0.9), 300, 4000) * np.linspace(0.1, 1, int(0.9 * SR)) ** 2
wh *= (0.6 + 0.4 * sweep(3, 9, 0.9))
boom = lowpass(noise(1.4), 180) * env(int(1.4 * SR), 0.003, 0.6) * 2.5 + np.sin(2 * np.pi * np.cumsum(np.linspace(80, 30, int(1.4 * SR))) / SR) * env(int(1.4 * SR), 0.002, 0.5)
SFX["sfx_meteor"] = reverb(mix((0, wh * 0.5), (0.85, boom)), 1.2, 0.25)

# ракета: нарастающий гул и рёв
d = 3.6
rum = lowpass(noise(d), 260) * np.linspace(0.2, 1, int(d * SR)) * 2
roar = bandpass(noise(d), 300, 2500) * np.linspace(0, 1, int(d * SR)) ** 1.5
sub = np.sin(2 * np.pi * np.cumsum(np.linspace(45, 70, int(d * SR))) / SR) * np.linspace(0.3, 1, int(d * SR))
SFX["sfx_rocket"] = reverb(mix((0, rum), (0, roar * 0.5), (0, sub * 0.8)), 1.5, 0.3)

# открытие планеты: фанфара
fan = mix(*[(k * 0.11, bell(midi(m), 1.4, 2.5, 2.2)) for k, m in enumerate([72, 76, 79, 84])], (0.44, bell(midi(88), 1.8, 2.5, 1.6) * 1.2))
SFX["sfx_unlock"] = reverb(fan, 1.6, 0.35)

# тап по рою: короткий колокольчик (высота меняется в игре)
SFX["sfx_tap"] = reverb(bell(midi(81), 0.35, 1.2, 7), 0.4, 0.2)

# мутация: мерцающий подъём и аккорд
ris = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(midi(60 + k * 7), midi(72 + k * 7), int(1.0 * SR))) / SR) for k in range(3)) * np.linspace(0, 1, int(1.0 * SR)) ** 2 * 0.3
chord = sum(bell(midi(m), 1.6, 2, 2) for m in [76, 80, 83, 88])
SFX["sfx_mutation"] = reverb(mix((0, ris), (0.95, chord)), 1.5, 0.4)

# щелчок интерфейса: мягкий тик
SFX["sfx_click"] = np.sin(2 * np.pi * 1800 * t_(0.04)) * env(int(0.04 * SR), 0.001, 0.02) * 0.6 + lowpass(noise(0.03), 3000)[:int(0.04 * SR)].tolist().__len__() * 0 + 0

# легендарное: удар и большой аккорд
imp = lowpass(noise(1.2), 220) * env(int(1.2 * SR), 0.002, 0.5) * 2
big = sum(bell(midi(m), 2.6, 1.5, 1.2) for m in [60, 67, 72, 76, 79, 84])
SFX["sfx_legendary"] = reverb(mix((0, imp), (0.02, big)), 2.2, 0.45)

if __name__ == "__main__":
    for k, v in SFX.items():
        save(k, np.asarray(v, dtype=np.float64))
