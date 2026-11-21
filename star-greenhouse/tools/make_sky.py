"""Рисует кубическое небо «Звёздной оранжереи»: туманность, пылевые полосы, звёзды.
Шум считается по 3D-направлению, поэтому швы между гранями сходятся.
Запуск: python3 tools/make_sky.py  ->  art/sky/{Ft,Bk,Lf,Rt,Up,Dn}.png"""
import os, sys
import numpy as np
from PIL import Image

SIZE = int(sys.argv[1]) if len(sys.argv) > 1 else 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "sky")
os.makedirs(OUT, exist_ok=True)


def hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(p, seed):
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                out = out + w * hash3(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(p, seed, octaves=6, lac=2.03, gain=0.5):
    total, amp, norm = 0, 1.0, 0
    q = p
    for o in range(octaves):
        total = total + amp * vnoise(q, seed + o * 17)
        norm += amp
        amp *= gain
        q = q * lac + 11.7
    return total / norm


def stars(d, scale, density, seed, size):
    p = d * scale
    ip = np.floor(p).astype(np.int64)
    f = p - ip
    on = hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed) < density
    sx = 0.2 + 0.6 * hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed + 1)
    sy = 0.2 + 0.6 * hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed + 2)
    sz = 0.2 + 0.6 * hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed + 3)
    dist2 = (f[..., 0] - sx) ** 2 + (f[..., 1] - sy) ** 2 + (f[..., 2] - sz) ** 2
    bright = 0.35 + 0.65 * hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed + 4) ** 2
    px_per_cell = (size / 2) / scale
    r = (1.0 + 0.5 * (60 / scale)) / px_per_cell  # радиус звезды в клетках: около 1-2 пикселей
    core = np.exp(-dist2 / (2 * r * r))
    t = hash3(ip[..., 0], ip[..., 1], ip[..., 2], seed + 5)
    tint = np.stack([1.0 - 0.35 * t, 0.9 + 0.1 * (1 - t), 0.7 + 0.3 * t], -1)  # от тёплых к голубым
    return (on * bright * core)[..., None] * tint


def face_dirs(face, n):
    u = (np.arange(n) + 0.5) / n * 2 - 1
    uu, vv = np.meshgrid(u, -u)  # v вверх
    one = np.ones_like(uu)
    # (forward, right, up) для каждой грани
    f = {
        "Ft": ((0, 0, -1), (1, 0, 0), (0, 1, 0)),
        "Bk": ((0, 0, 1), (-1, 0, 0), (0, 1, 0)),
        "Lf": ((-1, 0, 0), (0, 0, -1), (0, 1, 0)),
        "Rt": ((1, 0, 0), (0, 0, 1), (0, 1, 0)),
        "Up": ((0, 1, 0), (-1, 0, 0), (0, 0, -1)),
        "Dn": ((0, -1, 0), (1, 0, 0), (0, 0, -1)),
    }[face]
    fw, rt, up = (np.array(v, dtype=np.float64) for v in f)
    d = fw[None, None, :] * one[..., None] + rt[None, None, :] * uu[..., None] + up[None, None, :] * vv[..., None]
    return d / np.linalg.norm(d, axis=-1, keepdims=True)


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def render(face, n):
    d = face_dirs(face, n)
    # искажение потоком, чтобы облака выглядели как газ, а не как шум
    warp = np.stack([fbm(d * 1.7 + o, 5 + i, 4) for i, o in enumerate((0, 31.1, 77.7))], -1) - 0.5
    q = d * 1.6 + warp * 1.4
    a = fbm(q, 101, 6)
    b = fbm(q * 1.3 + 40, 202, 6)
    c = fbm(q * 0.8 - 25, 303, 5)
    dust = fbm(d * 2.6 + warp * 2.0 + 9, 404, 6)

    base = np.array([0.012, 0.014, 0.04])
    magenta = np.array([0.80, 0.18, 0.55])
    teal = np.array([0.10, 0.55, 0.78])
    violet = np.array([0.34, 0.20, 0.82])
    amber = np.array([1.00, 0.55, 0.20])

    # широкая светлая полоса Млечного пути вдоль наклонной плоскости
    band_n = np.array([0.25, 0.9, 0.35])
    band_n /= np.linalg.norm(band_n)
    h = d @ band_n
    band = np.exp(-(h / 0.30) ** 2)

    neb1 = smooth(0.42, 0.78, a) * (0.35 + 0.65 * band)
    neb2 = smooth(0.45, 0.80, b) * (0.30 + 0.70 * band)
    neb3 = smooth(0.55, 0.85, c)
    col = np.zeros(d.shape) + base
    col += neb1[..., None] * (magenta * 0.55 + violet * 0.45) * 0.85
    col += neb2[..., None] * (teal * 0.65 + violet * 0.35) * 0.80
    col += (neb3 * smooth(0.5, 0.8, a))[..., None] * amber * 0.55
    col += (band * smooth(0.35, 0.7, fbm(d * 5 + 3, 505, 5)))[..., None] * np.array([0.32, 0.30, 0.42]) * 0.55
    # пыль съедает свет
    dust_mask = smooth(0.50, 0.76, dust) * (0.45 + 0.55 * band)
    col *= (1 - 0.8 * dust_mask)[..., None]

    # звёзды: мелкие частые, средние, редкие яркие с ореолом
    st = stars(d, 70, 0.22, 11, n) * 1.0 + stars(d, 36, 0.10, 23, n) * 1.4 + stars(d, 16, 0.06, 37, n) * 2.2
    st *= (1 - 0.7 * dust_mask)[..., None] * (0.7 + 0.8 * band)[..., None]
    col += st
    # мягкая тоновая кривая
    col = 1 - np.exp(-col * 1.35)
    col = np.clip(col, 0, 1) ** (1 / 1.05)
    return Image.fromarray((col * 255).astype(np.uint8), "RGB")


if __name__ == "__main__":
    for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
        img = render(face, SIZE)
        img.save(os.path.join(OUT, face + ".png"))
        print("ok", face, img.size)
    # контрольный лист-развёртка
    sheet = Image.new("RGB", (4 * 256, 3 * 256))
    pos = {"Up": (1, 0), "Lf": (0, 1), "Ft": (1, 1), "Rt": (2, 1), "Bk": (3, 1), "Dn": (1, 2)}
    for face, (cx, cy) in pos.items():
        sheet.paste(Image.open(os.path.join(OUT, face + ".png")).resize((256, 256)), (cx * 256, cy * 256))
    sheet.save(os.path.join(OUT, "_sheet.png"))
