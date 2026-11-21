"""Рисует планеты для фона (RGBA, прозрачный фон): газовый гигант с кольцами, голубая планета, луна.
Запуск: python3 tools/make_planets.py -> art/planets/{gas,earth,moon}.png"""
import os
import numpy as np
from PIL import Image

N = 1024
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "planets")
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(7)


def noise2(shape, scale, seed, octaves=5):
    r = np.random.default_rng(seed)
    out = np.zeros(shape)
    amp, tot = 1.0, 0
    for o in range(octaves):
        s = max(2, int(scale * 2 ** o))
        g = r.random((s + 1, s + 1))
        im = Image.fromarray((g * 255).astype(np.uint8)).resize((shape[1], shape[0]), Image.BICUBIC)
        out += amp * np.asarray(im, dtype=np.float64) / 255
        tot += amp
        amp *= 0.5
    return out / tot


def smooth(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def palette(t, stops):
    t = np.clip(t, 0, 1) * (len(stops) - 1)
    i = np.clip(np.floor(t).astype(int), 0, len(stops) - 2)
    f = (t - i)[..., None]
    st = np.array(stops, dtype=np.float64)
    return st[i] * (1 - f) + st[i + 1] * f


def sphere(cx, cy, R, yy, xx):
    x = (xx - cx) / R
    y = (yy - cy) / R
    r2 = x * x + y * y
    inside = r2 < 1
    z = np.sqrt(np.clip(1 - r2, 0, 1))
    return x, y, z, inside, np.sqrt(r2)


def lighting(x, y, z, light=(-0.55, -0.45, 0.7), amb=0.06):
    l = np.array(light) / np.linalg.norm(light)
    d = np.clip(x * l[0] + y * l[1] + z * l[2], 0, 1)
    return amb + (1 - amb) * d ** 0.85


def to_img(rgb, a):
    out = np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])
    return Image.fromarray((out * 255).astype(np.uint8), "RGBA")


def gas():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    cx, cy, R = N / 2, N / 2 + 10, 212
    tilt = np.radians(-17)
    # ring: координаты в плоскости кольца
    dx, dy = xx - cx, yy - cy
    rx = dx * np.cos(tilt) + dy * np.sin(tilt)
    ry = -dx * np.sin(tilt) + dy * np.cos(tilt)
    sint = 0.22
    rr = np.sqrt(rx ** 2 + (ry / sint) ** 2) / R
    n1 = noise2((N, N), 60, 11, 3)
    ring_a = np.zeros_like(rr)
    bands = [(1.28, 1.42, 0.35), (1.46, 1.75, 0.85), (1.78, 1.84, 0.2), (1.88, 2.15, 0.65), (2.2, 2.3, 0.25)]
    for a, b, o in bands:
        ring_a += o * smooth(a, a + 0.02, rr) * (1 - smooth(b - 0.02, b, rr))
    ring_a *= 0.75 + 0.5 * np.sin(rr * 90 + n1 * 8) * 0.3 + 0.2
    ring_col = palette((rr - 1.2) / 1.2, [(0.72, 0.62, 0.5), (0.85, 0.75, 0.6), (0.62, 0.52, 0.42), (0.8, 0.7, 0.58), (0.55, 0.47, 0.4)])
    # тень планеты на кольце
    shadow = smooth(R * 0.9, R * 1.05, np.abs(ry)) * 0 + 1
    behind = ry < 0
    front = ~behind
    # планета
    x, y, z, inside, rdist = sphere(cx, cy, R, yy, xx)
    lat = y * 1.0
    warp = noise2((N, N), 6, 21, 4) - 0.5
    t = 0.5 + 0.5 * np.sin((lat * 7.5 + warp * 1.6 + noise2((N, N), 3, 33, 3) * 0.6) * np.pi)
    col = palette(t * 0.8 + noise2((N, N), 14, 5, 4) * 0.25, [(0.93, 0.78, 0.55), (0.82, 0.55, 0.32), (0.96, 0.86, 0.68), (0.70, 0.42, 0.26), (0.88, 0.68, 0.46)])
    # большое пятно-шторм
    sx, sy = 0.25, 0.28
    storm = np.exp(-(((x - sx) / 0.2) ** 2 + ((y - sy) / 0.1) ** 2))
    col = col * (1 - storm[..., None] * 0.7) + np.array([0.75, 0.3, 0.2]) * storm[..., None] * 0.7
    lit = lighting(x, y, z)
    limb = (0.45 + 0.55 * z ** 0.5)
    pl = col * (lit * limb)[..., None]
    # тень кольца на планете (полоса вдоль экватора)
    ring_shadow = np.exp(-(((ry / R) + 0.05) / 0.07) ** 2) * (rx > -R) * 0.45
    pl = pl * (1 - ring_shadow[..., None] * inside[..., None])
    atm = np.exp(-((rdist - 1.0) / 0.035) ** 2) * lighting(np.clip(x, -1, 1), np.clip(y, -1, 1), np.sqrt(np.clip(1 - np.clip(x * x + y * y, 0, 1), 0, 1)))
    glow = np.exp(-np.clip(rdist - 1, 0, 9) / 0.05) * (rdist >= 1) * 0.0
    pl = pl + (atm[..., None] * np.array([0.9, 0.75, 0.55])) * 0.35
    pl_alpha = inside.astype(np.float64) * smooth(1.0, 0.992, rdist)
    # ring lighting: тёмное в тени планеты
    in_shadow = (np.abs(ry / sint) < R * 1.0) & (rx > 0) & (rx < R * 2.6) & behind
    rl = np.where(in_shadow, 0.35, 1.0)
    ring_rgb = ring_col * (0.85 * rl)[..., None]
    out_rgb = np.zeros((N, N, 3))
    out_a = np.zeros((N, N))
    # слой 1: кольцо за планетой
    a1 = ring_a * behind
    out_rgb = ring_rgb * a1[..., None]
    out_a = a1
    # слой 2: планета
    out_rgb = out_rgb * (1 - pl_alpha[..., None]) + pl * pl_alpha[..., None]
    out_a = out_a * (1 - pl_alpha) + pl_alpha
    # слой 3: кольцо перед планетой
    a3 = ring_a * front
    out_rgb = out_rgb * (1 - a3[..., None]) + ring_rgb * a3[..., None]
    out_a = out_a * (1 - a3) + a3
    # мягкое свечение вокруг
    halo = np.exp(-np.clip(rdist - 1, 0, 9) / 0.12) * (rdist >= 1) * 0.12
    out_rgb = out_rgb + (halo * (1 - out_a))[..., None] * np.array([0.95, 0.7, 0.45])
    out_a = np.clip(out_a + halo * 0.5, 0, 1)
    return to_img(out_rgb / np.maximum(out_a[..., None], 1e-3) * out_a[..., None] if False else out_rgb, out_a)


def earth():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    cx, cy, R = N / 2, N / 2, 440
    x, y, z, inside, rdist = sphere(cx, cy, R, yy, xx)
    # координаты на сфере -> шум без полюсных искажений
    lon = np.arctan2(x, z + 1e-6)
    lat = np.arcsin(np.clip(y, -1, 1))
    u = (lon / np.pi * 0.5 + 0.5)
    v = (lat / np.pi + 0.5)
    uv = np.stack([u, v])
    cont = noise2((N, N), 5, 41, 6) * 0.6 + noise2((N, N), 2, 42, 4) * 0.4
    # шум зависит от пикселя, но на сфере искажён — приемлемо для фона
    land = smooth(0.52, 0.56, cont)
    ocean = palette(smooth(0.3, 0.52, cont), [(0.02, 0.1, 0.28), (0.04, 0.25, 0.5), (0.1, 0.42, 0.65)])
    green = palette(noise2((N, N), 9, 43, 4), [(0.18, 0.4, 0.15), (0.35, 0.5, 0.2), (0.6, 0.52, 0.3)])
    polar = smooth(0.82, 0.92, np.abs(y))
    land_col = green * (1 - polar[..., None]) + np.array([0.9, 0.93, 0.97]) * polar[..., None]
    col = ocean * (1 - land[..., None]) + land_col * land[..., None]
    clouds = smooth(0.5, 0.7, noise2((N, N), 7, 44, 6) * 0.7 + noise2((N, N), 18, 45, 4) * 0.3)
    col = col * (1 - 0.85 * clouds[..., None]) + np.array([0.97, 0.98, 1.0]) * 0.85 * clouds[..., None]
    lit = lighting(x, y, z, light=(0.6, -0.35, 0.7))
    spec = (1 - land) * np.clip(lit - 0.75, 0, 1) * 1.2 * (1 - clouds)
    pl = col * (lit * (0.55 + 0.45 * z ** 0.4))[..., None] + spec[..., None] * 0.35
    atm = np.exp(-((rdist - 0.99) / 0.05) ** 2)
    pl = pl + atm[..., None] * np.array([0.3, 0.55, 1.0]) * (0.25 + 0.75 * lit[..., None])
    alpha = inside.astype(np.float64) * smooth(1.0, 0.99, rdist)
    halo = np.exp(-np.clip(rdist - 1, 0, 9) / 0.045) * (rdist >= 1) * 0.55 * (0.3 + 0.7 * lighting(np.clip(x, -1.2, 1.2) / np.maximum(rdist, 1), np.clip(y, -1.2, 1.2) / np.maximum(rdist, 1), np.zeros_like(x) + 0.35, light=(0.6, -0.35, 0.7)))
    rgb = pl * alpha[..., None] + halo[..., None] * np.array([0.35, 0.6, 1.0])
    return to_img(rgb, np.clip(alpha + halo, 0, 1))


def moon():
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float64)
    cx, cy, R = N / 2, N / 2, 450
    x, y, z, inside, rdist = sphere(cx, cy, R, yy, xx)
    base = 0.55 + 0.3 * noise2((N, N), 6, 51, 6)
    maria = smooth(0.52, 0.6, noise2((N, N), 3, 52, 4))
    tone = base * (1 - 0.35 * maria)
    h = np.zeros((N, N))
    r = np.random.default_rng(53)
    for _ in range(260):
        px, py = r.uniform(-0.95, 0.95, 2)
        if px * px + py * py > 0.95:
            continue
        rad = r.uniform(0.012, 0.09) ** 1.0
        d = np.sqrt((x - px) ** 2 + (y - py) ** 2) / rad
        h += -0.22 * np.exp(-d ** 2 * 1.1) * (d < 1.1) + 0.3 * np.exp(-((d - 1.0) / 0.18) ** 2) * (d < 1.6)
    nx = np.gradient(h, axis=1) * 25
    ny = np.gradient(h, axis=0) * 25
    lit = lighting(x - nx * 0.05, y - ny * 0.05, z, light=(-0.6, -0.4, 0.65), amb=0.04)
    shade = tone * (0.85 + h * 0.5)
    col = np.dstack([shade * 1.02, shade * 1.0, shade * 0.96])
    rgb = col * (lit * (0.5 + 0.5 * z ** 0.4))[..., None]
    alpha = inside.astype(np.float64) * smooth(1.0, 0.99, rdist)
    return to_img(rgb * alpha[..., None], alpha)


if __name__ == "__main__":
    for name, fn in (("gas", gas), ("earth", earth), ("moon", moon)):
        im = fn()
        im.save(os.path.join(OUT, name + ".png"))
        print("ok", name)
    sheet = Image.new("RGBA", (N * 3 // 2, N // 2), (8, 8, 20, 255))
    for i, name in enumerate(("gas", "earth", "moon")):
        im = Image.open(os.path.join(OUT, name + ".png")).resize((N // 2, N // 2))
        sheet.alpha_composite(im, (i * N // 2, 0))
    sheet.convert("RGB").save(os.path.join(OUT, "_sheet.png"))
