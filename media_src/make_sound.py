"""Synthesises the "report sent" notification chime. Own work, no samples used.
Output: media_src/notify.wav (master, 16-bit 44.1 kHz) and static/media/notify.mp3
"""
import math
import struct
import subprocess
import wave
from pathlib import Path

BASE = Path(__file__).parent.parent
WAV = BASE / "media_src" / "notify.wav"
MP3 = BASE / "static" / "media" / "notify.mp3"
RATE = 44100

# two soft bell tones going up: E5 then A5
notes = [(659.25, 0.00), (880.00, 0.14)]
length = 0.9
samples = []
for i in range(int(RATE * length)):
    t = i / RATE
    value = 0.0
    for freq, start in notes:
        if t >= start:
            u = t - start
            envelope = math.exp(-u * 6) * min(1.0, u * 200)
            value += envelope * (math.sin(2 * math.pi * freq * u) + 0.3 * math.sin(4 * math.pi * freq * u))
    samples.append(int(max(-1.0, min(1.0, value * 0.35)) * 32767))

with wave.open(str(WAV), "wb") as f:
    f.setnchannels(1)
    f.setsampwidth(2)
    f.setframerate(RATE)
    f.writeframes(struct.pack("<" + "h" * len(samples), *samples))

MP3.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(WAV),
                "-codec:a", "libmp3lame", "-b:a", "64k", str(MP3)], check=True)
print("sound done")
