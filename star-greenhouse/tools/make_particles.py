"""Текстуры частиц для аур мутаций: python3 tools/make_particles.py -> art/particles/*.png
Белые с альфой (цвет задаёт ParticleEmitter.Color):
  glow.png    — мягкое круглое сияние
  sparkle.png — четырёхлучевая звёздочка с ореолом
  ripple.png  — тонкое мягкое кольцо (расходящиеся круги по земле)
  wisp.png    — вытянутый мягкий мазок (завихрения)
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "particles")
os.makedirs(OUT, exist_ok=True)
N = 256
y, x = np.mgrid[0:N, 0:N].astype(float)
u = (x - N / 2 + 0.5) / (N / 2)
v = (y - N / 2 + 0.5) / (N / 2)
r = np.hypot(u, v)


def save(alpha, name):
    a = np.clip(alpha, 0, 1)
    a *= np.clip((1 - r) / 0.08, 0, 1) if name != "wisp.png" else 1
    rgba = np.stack([np.ones_like(a), np.ones_like(a), np.ones_like(a), a], -1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("ok", name)


save(np.exp(-(r / 0.42) ** 2) * 0.9 + np.exp(-(r / 0.15) ** 2) * 0.3, "glow.png")
ax = np.exp(-np.abs(u) / 0.035) * np.exp(-np.abs(v) / 0.55) + np.exp(-np.abs(v) / 0.035) * np.exp(-np.abs(u) / 0.55)
diag = (np.exp(-np.abs(u - v) / 0.04) + np.exp(-np.abs(u + v) / 0.04)) * np.exp(-r / 0.22) * 0.35
save(ax * 0.95 + diag + np.exp(-(r / 0.16) ** 2) * 0.8 + np.exp(-(r / 0.45) ** 2) * 0.18, "sparkle.png")
save(np.exp(-((r - 0.78) / 0.05) ** 2) * 0.95 + np.exp(-((r - 0.74) / 0.16) ** 2) * 0.25, "ripple.png")
save(np.exp(-(u / 0.75) ** 2 - (v / 0.16) ** 2) * (0.6 + 0.4 * np.exp(-((u + 0.3) / 0.35) ** 2)), "wisp.png")
