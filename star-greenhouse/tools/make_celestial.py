"""Небесные объекты для неба игры: python3 tools/make_celestial.py -> art/planets/sun.png, art/planets/blackhole.png

sun.png — звезда с мягкой короной без резких колец (прозрачный фон, для BillboardGui).
blackhole.png — чёрная дыра: чёрный силуэт, тонкое фотонное кольцо, линзированный задний диск над и под тенью
и наклонённый аккреционный диск спереди, горячий у центра и тёмно-оранжевый к краям.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "art", "planets")
N = 1024
y, x = np.mgrid[0:N, 0:N].astype(float)
u = (x - N / 2 + 0.5) / (N / 2)
v = (N / 2 - y - 0.5) / (N / 2)
rng = np.random.default_rng(7)


def blur(img, r):
    """Гауссово размытие через БПФ (по осям изображения)."""
    k = np.fft.fftfreq(N)
    g = np.exp(-2 * (np.pi * r) ** 2 * (k[:, None] ** 2 + k[None, :] ** 2))
    if img.ndim == 2:
        return np.real(np.fft.ifft2(np.fft.fft2(img) * g))
    return np.stack([blur(img[..., i], r) for i in range(img.shape[-1])], -1)


def save(rgb, alpha, name):
    rgba = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], -1)
    Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name))
    print("ok", name)


def tone(e):
    """Яркость -> цвет: тёмно-красный, оранжевый, персиковый, почти белый."""
    e = np.clip(e, 0, None)
    stops = np.array([[0.0, 0.0, 0.0], [0.45, 0.08, 0.02], [0.95, 0.42, 0.12], [1.0, 0.78, 0.52], [1.0, 0.96, 0.88], [1.0, 1.0, 1.0]])
    pos = np.array([0.0, 0.18, 0.42, 0.68, 0.9, 1.4])
    out = np.zeros(e.shape + (3,))
    for c in range(3):
        out[..., c] = np.interp(e, pos, stops[:, c])
    return out


# ------------------------------------------------------------------ солнце
r = np.hypot(u, v)
R0 = 0.2
core = np.clip((R0 - r) / 0.008, 0, 1)  # диск звезды
limb = np.clip(1 - (r / R0) ** 2, 0, 1) ** 0.4  # потемнение к краю
ang = np.arctan2(v, u)
# корона: плавный спад без колец + мягкие лучи разной длины
rays = np.zeros_like(r)
for k, (n, ph, w) in enumerate([(5, 0.3, 0.5), (8, 1.1, 0.35), (13, 2.0, 0.25)]):
    rays += w * np.clip(np.cos(ang * n + ph), 0, 1) ** 2
corona = np.exp(-((r - R0).clip(0)) / 0.05) * 0.75 + np.exp(-((r - R0).clip(0)) / 0.16) * 0.45 + np.exp(-r / 0.42) * 0.22
corona *= 1 + 0.22 * rays * np.exp(-((r - R0).clip(0)) / 0.3)
corona = blur(corona, 0.006)
e_sun = core * (0.82 + 0.18 * limb) + (1 - core) * corona
hot = np.stack([np.ones_like(r), 0.97 - 0.1 * (1 - limb), 0.86 - 0.3 * (1 - limb)], -1)
warm = np.stack([np.ones_like(r), 0.78 - 0.25 * np.clip((r - R0) / 0.6, 0, 1), 0.42 - 0.3 * np.clip((r - R0) / 0.6, 0, 1)], -1)
col = hot * core[..., None] + warm * (1 - core[..., None])
rgb = np.clip(col * np.clip(e_sun * 1.15, 0, 1)[..., None], 0, 1)
alpha = np.clip(np.maximum(core, e_sun ** 0.9), 0, 1) * np.clip((0.98 - r) / 0.25, 0, 1)
save(rgb, alpha, "sun.png")

# ------------------------------------------------------------------ чёрная дыра
S = 0.17  # радиус тени
tilt = np.radians(-11)
cu, su = np.cos(tilt), np.sin(tilt)
X = u * cu + v * su  # оси диска
Y = -u * su + v * cu
r = np.hypot(u, v)

# аккреционный диск спереди: сильно сплюснутый эллипс от 1.25S до 3.6, разрыв посередине — тень
flat = 0.1
rd = np.hypot(X, Y / flat)
band = np.clip((rd - S * 1.25) / 0.04, 0, 1) * np.exp(-((rd - S * 1.25).clip(0)) / 0.42)
band *= np.clip((0.97 - rd) / 0.35, 0, 1) * np.clip((0.97 - np.abs(X)) / 0.3, 0, 1)
angd = np.arctan2(Y / flat, X)
# завихрения вдоль орбиты
turb = np.zeros_like(rd)
for k in range(7):
    f = 40 + k * 37 + rng.uniform(0, 20)
    turb += np.sin(rd * f + angd * (k % 3 + 1) * 2 + rng.uniform(0, 6)) / (k + 2)
turb = 1 + 0.12 * turb
doppler = 1 + 0.45 * np.cos(angd + 0.25)  # левая сторона ярче (движется к нам)
disk = band * turb * doppler * 1.45
front = (Y < 0) | (r > S * 1.02)  # нижняя половина диска закрывает тень

# линзированный задний диск: светящаяся дуга вокруг тени, толще сверху и снизу
ring_r = np.hypot(u, v * 1.02)
lens = np.exp(-((ring_r - S * 1.32) / (0.05 + 0.03 * np.abs(v / (r + 1e-6))) ) ** 2) * (0.75 + 0.5 * np.abs(v / (r + 1e-6)) ** 1.5)
lens *= 1 + 0.35 * np.cos(np.arctan2(v, u) - np.pi * 0.9)
photon = np.exp(-((r - S * 1.06) / 0.006) ** 2) * 1.4  # тонкое фотонное кольцо

shadow = np.clip((S - r) / 0.004, 0, 1)
E = lens * 0.55 + photon * 0.8
E = E * (1 - shadow)
E = E + disk * np.where(front, 1, 0)
# свечение вокруг всего
halo = blur(E, 0.010) * 0.55 + blur(E, 0.035) * 0.35
E_all = E + halo
rgb = tone(E_all * 0.85)
# тень остаётся чёрной, только диск перед ней светится
cover = np.clip(disk * np.where(front, 1, 0) * 1.5, 0, 1)
rgb = rgb * (1 - shadow[..., None] * (1 - cover[..., None]))
alpha = np.clip(np.maximum(shadow, np.clip(E_all * 1.2, 0, 1) ** 0.85), 0, 1)
alpha *= np.clip((0.98 - np.maximum(np.abs(u), np.abs(v))) / 0.06, 0, 1)
save(rgb, alpha, "blackhole.png")

# превью на звёздном фоне
bg = np.zeros((N, N, 3)) + np.array([0.02, 0.02, 0.05])
st = rng.random((N, N)) > 0.9975
bg[st] = 0.8
for name in ("sun.png", "blackhole.png"):
    im = np.asarray(Image.open(os.path.join(OUT, name))).astype(float) / 255
    comp = bg * (1 - im[..., 3:]) + im[..., :3] * im[..., 3:]
    Image.fromarray((comp * 255).astype(np.uint8)).save(os.path.join(OUT, "_prev_" + name))
