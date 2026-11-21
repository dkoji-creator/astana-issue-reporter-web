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
    """Небо без видимых швов при любой ориентации граней в Roblox:
    общая подсветка зависит только от высоты над горизонтом, облака туманности живут внутри грани и гаснут к её краям."""
    d = face_dirs(face, n)
    elev = np.arcsin(np.clip(d[..., 1], -1, 1))
    # координаты внутри грани
    u = (np.arange(n) + 0.5) / n * 2 - 1
    uu, vv = np.meshgrid(u, -u)
    edge = np.minimum(1 - np.abs(uu), 1 - np.abs(vv))
    fade = smooth(0.04, 0.42, edge)
    seed = {"Ft": 1, "Bk": 2, "Lf": 3, "Rt": 4, "Up": 5, "Dn": 6}[face]
    base = np.array([0.010, 0.012, 0.030])
    col = np.zeros(d.shape) + base
    # общая полоса над горизонтом (одинакова на всех боковых гранях)
    band = np.exp(-((elev - 0.12) / 0.32) ** 2)
    glow = np.exp(-((elev + 0.05) / 0.5) ** 2)
    col += band[..., None] * np.array([0.10, 0.07, 0.18]) * 0.9
    col += glow[..., None] * np.array([0.03, 0.05, 0.09])
    # облака туманности внутри грани
    p2 = np.stack([uu * 1.6 + seed * 13.1, vv * 1.6 - seed * 7.3, np.full_like(uu, seed * 3.7)], -1)
    warp = np.stack([fbm(p2 * 1.1 + o, 40 + seed + i, 4) for i, o in enumerate((0, 17.0, 33.0))], -1) - 0.5
    q = p2 + warp * 1.5
    a1 = fbm(q, 100 + seed, 6)
    a2 = fbm(q * 1.4 + 9, 200 + seed, 6)
    dust = fbm(q * 2.2 - 4, 300 + seed, 5)
    pal = [(np.array([0.70, 0.20, 0.55]), np.array([0.12, 0.45, 0.70])),
           (np.array([0.30, 0.22, 0.75]), np.array([0.85, 0.45, 0.25])),
           (np.array([0.15, 0.50, 0.65]), np.array([0.60, 0.25, 0.70]))][seed % 3]
    neb = smooth(0.45, 0.8, a1) * fade
    neb2 = smooth(0.5, 0.82, a2) * fade
    if face in ("Up", "Dn"):
        neb *= 0.45
        neb2 *= 0.45
    col += neb[..., None] * pal[0] * 0.55
    col += neb2[..., None] * pal[1] * 0.45
    col *= (1 - 0.6 * smooth(0.52, 0.78, dust) * fade)[..., None]
    # звёзды
    st = stars(d, 70, 0.22, 11, n) * 0.9 + stars(d, 36, 0.10, 23, n) * 1.2 + stars(d, 16, 0.05, 37, n) * 1.8
    col += st * (0.8 + 0.6 * band)[..., None]
    col = 1 - np.exp(-col * 1.3)
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
