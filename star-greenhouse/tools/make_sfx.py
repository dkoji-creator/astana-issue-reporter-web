"""Синтез звуковых эффектов «Звёздной оранжереи»: python3 tools/make_sfx.py -> art/audio/sfx_*.ogg

Важно: телефонные динамики почти не воспроизводят частоты ниже 250 Гц, поэтому вся энергия звуков
лежит в полосе 300-6000 Гц, а «низ» (удары, гул) делается гармониками и хрустом, а не чистым басом.
Громкость выравнивается по среднеквадратичному уровню, пики мягко ограничиваются.
"""
import os, subprocess
import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "audio")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a, d, curve=4.0):
    t = np.arange(n) / SR
    return np.minimum(1, t / max(a, 1e-4)) * np.exp(-np.maximum(0, t - a) * curve / max(d, 1e-3))


def noise(d):
    return rng.standard_normal(int(d * SR))


def filt(x, lo=None, hi=None, order=4):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi:
        g *= 1 / (1 + (f / hi) ** order)
    if lo:
        g *= 1 - 1 / (1 + (f / lo) ** order)
    return np.fft.irfft(X * g, len(x))


def sweep(f0, f1, d, shape="exp"):
    t = t_(d)
    f = f0 * (f1 / f0) ** (t / d) if shape == "exp" else f0 + (f1 - f0) * t / d
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def bell(f, d, bright=2.0, decay=3.0):
    t = t_(d)
    mod = np.sin(2 * np.pi * f * 3.01 * t) * bright * np.exp(-t * 6)
    s = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * decay)
    s += 0.3 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t * decay * 1.6)
    s += 0.12 * np.sin(2 * np.pi * f * 4.2 * t) * np.exp(-t * decay * 3)
    return s * np.minimum(1, t / 0.002)


def pluck(f, d, decay=5.0):
    t = t_(d)
    s = sum(np.sin(2 * np.pi * f * k * t) / k * np.exp(-t * decay * (1 + 0.5 * k)) for k in range(1, 7))
    return s * np.minimum(1, t / 0.003)


def drive(x, k=3.0):
    return np.tanh(x * k) / np.tanh(k)


def reverb(x, sec=1.0, wet=0.25):
    n = int(sec * SR)
    ir = rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 5 / sec)
    ir = filt(ir, 300, 7000)
    ir /= np.sqrt((ir ** 2).sum())
    m = len(x) + n
    size = 1 << int(np.ceil(np.log2(m)))
    y = np.fft.irfft(np.fft.rfft(x, size) * np.fft.rfft(ir, size), size)[:m]
    out = np.zeros(m)
    out[:len(x)] = x
    return out * (1 - wet) + y * wet


def mix(*parts):
    n = max(int(off * SR) + len(p) for off, p in parts)
    out = np.zeros(n)
    for off, p in parts:
        o = int(off * SR)
        out[o:o + len(p)] += p
    return out


def midi(m):
    return 440 * 2 ** ((m - 69) / 12)


def save(name, x, rms_db=-15.0):
    x = np.asarray(x, dtype=np.float64)
    x = filt(x, 180, None, 2)  # всё, что ниже, телефон всё равно не сыграет
    rms = np.sqrt((x ** 2).mean()) + 1e-9
    x = x * (10 ** (rms_db / 20) / rms)
    x = np.tanh(x * 1.2) / np.tanh(1.2) * 0.95  # мягкий лимитер
    fade = int(0.008 * SR)
    x[:fade] *= np.linspace(0, 1, fade)
    x[-fade * 2:] *= np.linspace(1, 0, fade * 2)
    raw = os.path.join(OUT, name + ".raw")
    (np.clip(x, -1, 1) * 32767).astype("<i2").tofile(raw)
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", raw, "-c:a", "libvorbis", "-q:a", "6", out], check=True)
    os.remove(raw)
    print("ok", name, round(len(x) / SR, 2), "s")


SFX = {}

# щелчок интерфейса: мягкий деревянный тик
tick = (np.sin(2 * np.pi * 2300 * t_(0.05)) * 0.6 + np.sin(2 * np.pi * 950 * t_(0.05))) * env(int(0.05 * SR), 0.001, 0.018)
SFX["sfx_click"] = (mix((0, tick), (0, filt(noise(0.02), 2000, 7000) * env(int(0.02 * SR), 0.0005, 0.006) * 0.4)), -18)

# всплывающее окно: «поп» с воздухом
pop = sweep(500, 1400, 0.09) * env(int(0.09 * SR), 0.002, 0.06)
air = filt(noise(0.18), 1500, 6000) * env(int(0.18 * SR), 0.03, 0.1) * 0.3
SFX["sfx_pop"] = (reverb(mix((0, pop), (0, air)), 0.3, 0.15), -18)

# ошибка: два коротких «бу-бу» вниз
def buzz(f, d):
    t = t_(d)
    return drive(np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2 * t), 2) * env(len(t), 0.004, d * 0.7)
SFX["sfx_error"] = (mix((0, buzz(440, 0.12)), (0.13, buzz(330, 0.18))), -17)

# тап: короткий колокольчик (высота меняется в игре)
SFX["sfx_tap"] = (reverb(bell(midi(84), 0.35, 1.2, 7), 0.4, 0.2), -16)

# посадка: чпок, хруст земли и искорка
p1 = sweep(900, 260, 0.12) * env(int(0.12 * SR), 0.002, 0.08)
crunch = filt(noise(0.22), 900, 4500) * env(int(0.22 * SR), 0.002, 0.08) * 0.7
SFX["sfx_plant"] = (reverb(mix((0, p1), (0.01, crunch), (0.07, bell(midi(88), 0.3, 1, 9) * 0.35)), 0.4, 0.15), -15)

# полив: всплеск и пузырьки
spl = filt(noise(0.55), 900, 6000) * env(int(0.55 * SR), 0.01, 0.3)
bub = mix(*[(0.05 + k * 0.055, sweep(700 + 180 * k, 1600 + 260 * k, 0.05) * env(int(0.05 * SR), 0.002, 0.04) * 0.5) for k in range(6)])
SFX["sfx_water"] = (reverb(mix((0, spl), (0, bub)), 0.5, 0.2), -16)

# сбор: два звонких колокольчика вверх и шорох листьев
rust = filt(noise(0.3), 2000, 7000) * env(int(0.3 * SR), 0.02, 0.15) * 0.25
SFX["sfx_harvest"] = (reverb(mix((0, rust), (0.02, bell(midi(79), 0.6)), (0.1, bell(midi(86), 0.8))), 0.8, 0.25), -15)

# монеты: металлический «дзынь-дзынь»
def coin(f, d):
    t = t_(d)
    return (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 2.76 * t) + 0.3 * np.sin(2 * np.pi * f * 5.4 * t)) * env(len(t), 0.001, d * 0.6)
SFX["sfx_coin"] = (reverb(mix((0, coin(1580, 0.12)), (0.07, coin(2100, 0.45))), 0.5, 0.2), -16)

# звезда: искристое восходящее арпеджио
SFX["sfx_star"] = (reverb(mix(*[(k * 0.045, bell(midi(84 + s), 0.7, 1.5, 4) * (0.6 + 0.1 * k)) for k, s in enumerate([0, 4, 7, 12, 16])]), 1.0, 0.35), -16)

# взрыв метеорита: хруст, треск и «бум» гармониками
def boom(d=1.2, bright=3500):
    n = int(d * SR)
    burst = filt(noise(d), 250, bright) * env(n, 0.002, d * 0.35) * 1.4
    crack = filt(noise(d), 1500, 7000) * env(n, 0.001, 0.08) * 0.8
    thump = drive(np.sin(2 * np.pi * np.cumsum(np.linspace(260, 120, n)) / SR) * env(n, 0.002, 0.22) * 1.2, 4)
    debris = mix(*[(rng.uniform(0.08, d * 0.6), filt(noise(0.03), 1500, 6000) * env(int(0.03 * SR), 0.001, 0.01) * rng.uniform(0.2, 0.5)) for _ in range(14)])
    return mix((0, burst), (0, crack), (0, thump), (0, debris))
SFX["sfx_boom"] = (reverb(boom(1.1), 0.9, 0.25), -14)

# метеорит: свист падения и взрыв
whistle = sweep(2400, 600, 0.9) * np.linspace(0.2, 1, int(0.9 * SR)) * 0.5
wh = filt(noise(0.9), 600, 4500) * np.linspace(0.1, 1, int(0.9 * SR)) ** 2 * 0.6
SFX["sfx_meteor"] = (reverb(mix((0, whistle), (0, wh), (0.85, boom(1.3))), 1.1, 0.25), -14)

# лазер пушки: «пиу»
def laser():
    d = 0.22
    t = t_(d)
    f = 2600 * (380 / 2600) ** (t / d)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = drive(np.sin(ph) + 0.4 * np.sin(2 * ph + 0.3), 2.5) * env(len(t), 0.002, 0.16)
    return s + filt(noise(d), 3000, 8000) * env(len(t), 0.001, 0.03) * 0.3
SFX["sfx_laser"] = (reverb(laser(), 0.3, 0.15), -16)

# писк обратного отсчёта
def beep(f, d=0.16):
    t = t_(d)
    return (np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 3 * t)) * env(len(t), 0.004, d * 0.8)
SFX["sfx_beep"] = (beep(988), -16)
SFX["sfx_go"] = (reverb(mix((0, beep(1319, 0.35)), (0, beep(1976, 0.35) * 0.5)), 0.5, 0.2), -15)

# порыв воздуха: трамплин, открытие, полёт
def whoosh(d=0.7, lo=500, hi=3200):
    n = int(d * SR)
    x = noise(d)
    seg = 8
    out = np.zeros(n)
    for k in range(seg):
        a, b = k * n // seg, (k + 1) * n // seg
        c = lo + (hi - lo) * np.sin(np.pi * (k + 0.5) / seg)
        out[a:b] = filt(x, c * 0.6, c * 1.6)[a:b]
    return out * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
SFX["sfx_whoosh"] = (reverb(whoosh(0.7), 0.6, 0.2), -15)

# ракета: зажигание, треск и нарастающий рёв с воем турбины
def rocket(d=5.0):
    n = int(d * SR)
    up = np.linspace(0, 1, n)
    ign = boom(0.8, 4500)
    roar = filt(noise(d), 300, 1200 + 2200 * 1) * (0.25 + 0.75 * up ** 0.7)
    rumble = drive(filt(noise(d), 120, 600) * 2.5, 3) * (0.3 + 0.7 * up) * 0.6
    crackle = np.zeros(n)
    for _ in range(int(d * 90)):
        o = rng.integers(0, n - 800)
        crackle[o:o + 800] += filt(noise(800 / SR), 2000, 7000) * env(800, 0.0005, 0.004) * rng.uniform(0.2, 0.7)
    whine = sweep(380, 1250, d) * (0.15 + 0.35 * up) * 0.5
    tail = np.ones(n)
    tail[-int(0.8 * SR):] = np.linspace(1, 0, int(0.8 * SR))
    return mix((0, ign * 0.8), (0.15, (roar + rumble + crackle * 0.5 + whine) * tail))
SFX["sfx_rocket"] = (reverb(rocket(), 1.2, 0.25), -13)

# открытие планеты: фанфара
fan = mix(*[(k * 0.11, bell(midi(m), 1.4, 2.5, 2.2)) for k, m in enumerate([72, 76, 79, 84])], (0.44, bell(midi(88), 1.8, 2.5, 1.6) * 1.2))
SFX["sfx_unlock"] = (reverb(fan, 1.6, 0.35), -14)

# мутация: мерцающий подъём и аккорд
n1 = int(1.0 * SR)
ris = sum(np.sin(2 * np.pi * np.cumsum(np.linspace(midi(67 + k * 7), midi(79 + k * 7), n1)) / SR) for k in range(3)) * np.linspace(0, 1, n1) ** 2 * 0.3
chord = sum(bell(midi(m), 1.6, 2, 2) for m in [76, 80, 83, 88])
SFX["sfx_mutation"] = (reverb(mix((0, ris), (0.95, chord)), 1.5, 0.4), -14)

# легендарное: удар и большой аккорд
big = sum(bell(midi(m), 2.6, 1.5, 1.2) for m in [67, 72, 76, 79, 84, 88])
SFX["sfx_legendary"] = (reverb(mix((0, boom(1.0) * 0.8), (0.02, big)), 2.0, 0.45), -13)

# сундук: скрип крышки, звон монет, искры
creak = sum(np.sin(2 * np.pi * np.cumsum(np.full(int(0.5 * SR), f) + 40 * np.sin(np.linspace(0, 18, int(0.5 * SR)))) / SR) for f in (420, 655)) * env(int(0.5 * SR), 0.05, 0.35) * 0.4
cascade = mix(*[(0.45 + k * 0.05, coin(1500 + rng.uniform(-200, 600), 0.25) * 0.6) for k in range(9)])
SFX["sfx_chest"] = (reverb(mix((0, creak), (0, cascade), (0.5, bell(midi(91), 1.2, 2, 3) * 0.5)), 1.0, 0.3), -14)

# котёл алхимии: бульканье и волшебный перелив
bubbles = mix(*[(rng.uniform(0, 1.0), sweep(rng.uniform(300, 600), rng.uniform(800, 1400), 0.06) * env(int(0.06 * SR), 0.003, 0.04) * rng.uniform(0.3, 0.7)) for _ in range(22)])
magic = mix(*[(0.9 + k * 0.06, bell(midi(m), 0.9, 2.5, 3) * 0.6) for k, m in enumerate([76, 79, 83, 86, 91])])
SFX["sfx_brew"] = (reverb(mix((0, bubbles), (0, magic)), 1.2, 0.35), -14)

if __name__ == "__main__":
    for k, (v, db) in SFX.items():
        save(k, v, db)
