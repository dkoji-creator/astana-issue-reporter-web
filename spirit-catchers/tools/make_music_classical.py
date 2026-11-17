"""Фоновая музыка: фортепианное переложение Прелюдии до мажор (И. С. Бах, BWV 846, общественное достояние).
Синтез: фортепианный тембр (гармоники с затуханием) + мягкая реверберация. Пишет audio/music_lantern.ogg."""
import numpy as np, subprocess, wave

SR = 44100
N = lambda n: {"C":0,"C#":1,"Db":1,"D":2,"D#":3,"Eb":3,"E":4,"F":5,"F#":6,"Gb":6,"G":7,"G#":8,"Ab":8,"A":9,"A#":10,"Bb":10,"B":11}[n[:-1]] + 12 * (int(n[-1]) + 1)
BARS = [
 "C4 E4 G4 C5 E5", "C4 D4 A4 D5 F5", "B3 D4 G4 D5 F5", "C4 E4 G4 C5 E5",
 "C4 E4 A4 E5 A5", "C4 D4 F#4 A4 D5", "B3 D4 G4 D5 G5", "B3 C4 E4 G4 C5",
 "A3 C4 E4 G4 C5", "D3 A3 D4 F#4 C5", "G3 B3 D4 G4 B4", "G3 Bb3 E4 G4 C#5",
 "F3 A3 D4 A4 D5", "F3 Ab3 D4 F4 B4", "E3 G3 C4 G4 C5", "E3 F3 A3 C4 F4",
 "D3 F3 A3 C4 F4", "G2 D3 G3 B3 F4", "C3 E3 G3 C4 E4", "C3 G3 Bb3 C4 E4",
 "F2 F3 A3 C4 E4", "F#2 C3 A3 C4 Eb4", "Ab2 F3 B3 C4 D4", "G2 F3 G3 B3 D4",
 "G2 E3 G3 C4 E4", "G2 D3 G3 C4 F4", "G2 D3 G3 B3 F4", "C3 E3 G3 C4 E4",
]
STEP = 60 / 64 / 4  # шестнадцатая при 64 ударах в минуту
total = (len(BARS) * 16 + 24) * STEP + 4
out = np.zeros(int(total * SR))

def note(m, t, dur, vel):
    f = 440 * 2 ** ((m - 69) / 12)
    n = int(dur * SR)
    tt = np.arange(n) / SR
    s = np.zeros(n)
    for h, a in [(1, 1), (2, 0.45), (3, 0.22), (4, 0.12), (5, 0.06), (6, 0.03)]:
        s += a * np.sin(2 * np.pi * f * h * (1 + 0.0004 * h * h) * tt) * np.exp(-tt * (1.1 + 0.9 * h) * (f / 400) ** 0.4)
    s *= np.minimum(1, tt / 0.004)
    rel = int(0.08 * SR)
    s[-rel:] *= np.linspace(1, 0, rel)
    i = int(t * SR)
    out[i:i + n] += vel * s[: len(out) - i]

t = 0.0
for b, bar in enumerate(BARS):
    ns = [N(x) for x in bar.split()]
    for half in range(2):
        h0 = t
        note(ns[0], h0, 8 * STEP + 0.6, 0.55)            # бас держится полтакта
        note(ns[1], h0 + STEP, 7 * STEP + 0.5, 0.42)
        for k in range(6):
            note(ns[2 + k % 3], h0 + (2 + k) * STEP, 2.2, 0.36 + 0.04 * (k % 3 == 2))
        t += 8 * STEP
# финальный аккорд
for i, m in enumerate([N("C2"), N("C3"), N("E3"), N("G3"), N("C4"), N("E4"), N("G4"), N("C5")]):
    note(m, t + i * 0.09, 6, 0.4)

# реверберация: несколько затухающих отражений
rev = np.zeros_like(out)
for d, g in [(0.031, 0.35), (0.047, 0.3), (0.071, 0.25), (0.113, 0.2), (0.173, 0.15), (0.29, 0.1), (0.41, 0.07)]:
    k = int(d * SR)
    rev[k:] += g * out[:-k]
mix = out + 0.6 * rev
mix /= np.abs(mix).max() / 0.8
pcm = (mix * 32767).astype(np.int16)
with wave.open("/tmp/claude-0/-home-user-astana-issue-reporter-web/74759eb8-67a2-521c-90ce-1ed8d33d554e/scratchpad/prelude.wav", "wb") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", "/tmp/claude-0/-home-user-astana-issue-reporter-web/74759eb8-67a2-521c-90ce-1ed8d33d554e/scratchpad/prelude.wav", "-c:a", "libvorbis", "-q:a", "5", "audio/music_lantern.ogg"], check=True)
print("ok", round(total, 1), "s")
