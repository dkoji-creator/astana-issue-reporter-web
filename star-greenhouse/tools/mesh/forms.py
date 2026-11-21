"""Формы растений. Каждая функция возвращает {роль: Mesh}.
Роли: F — плод/лепестки (цвет c1), A — акцент (c2), L — листья и стебли, G — светящиеся детали, R — камень/тёмное основание."""
import numpy as np
from geom import *


def put(d, role, m):
    if m is not None and len(m.v):
        d.setdefault(role, Mesh()).add(m)


def V(*a):
    return np.array(a, dtype=np.float64)


def ang_dir(a, elev):
    return V(np.cos(a) * np.cos(elev), np.sin(elev), np.sin(a) * np.cos(elev))


def small_leaf(base, axis, size, bend=0.5, up=(0, 1, 0)):
    return leaf(base, axis, size, size * 0.42, bend=bend, fold=0.3, up=up, nu=7, nv=3, thick=0.02)


def stem_tube(pts, r0, r1, sides=7, n=22):
    c = curve(pts, n)
    return tube(c, lambda t: r0 + (r1 - r0) * t, sides)


# ------------------------------------------------------------------ цветок
def flower(rng, lvl=0.0):
    d = {}
    H = 2.3 + rng.random() * 0.9
    lean = V(rng.uniform(-0.5, 0.5), 0, rng.uniform(-0.5, 0.5))
    pts = [V(0, 0, 0), V(lean[0] * 0.3, H * 0.45, lean[2] * 0.3), V(lean[0] * 0.7, H * 0.8, lean[2] * 0.7), V(lean[0], H, lean[2])]
    stem = curve(pts, 26)
    put(d, "L", tube(stem, lambda t: 0.085 - 0.03 * t, 8))
    hc = stem[-1]
    axis = unit(stem[-1] - stem[-4] + V(0, 0.9, 0))
    X = frame(axis)[:, 0]
    Z = frame(axis)[:, 2]
    style = int(rng.integers(0, 4))
    if style == 0:  # роза
        n1 = int(rng.integers(9, 15)); plen = 0.95 + rng.random() * 0.4; pw = 0.34 + rng.random() * 0.14
        layers = [(n1, plen, pw, 0.15, "F", 0.55, 0.55), (n1 - 2, plen * 0.82, pw * 0.9, 0.55, "F", 0.6, 0.5), (max(5, n1 - 5), plen * 0.55, pw * 0.8, 1.0, "A", 0.7, 0.4)]
    elif style == 1:  # ромашка: много узких плоских лепестков
        n1 = int(rng.integers(16, 22)); plen = 1.1 + rng.random() * 0.3; pw = 0.2
        layers = [(n1, plen, pw, 0.05, "F", 0.15, 0.25), (n1 - 4, plen * 0.8, pw, 0.2, "F", 0.15, 0.3)]
    elif style == 2:  # лотос: высокие чашей лепестки в три яруса
        n1 = int(rng.integers(8, 11)); plen = 1.15 + rng.random() * 0.3; pw = 0.5
        layers = [(n1, plen, pw, 0.55, "F", 0.5, 0.3), (n1 - 2, plen * 0.85, pw * 0.9, 0.85, "F", 0.6, 0.25), (6, plen * 0.65, pw * 0.8, 1.15, "A", 0.7, 0.2)]
    else:  # мак: несколько крупных широких лепестков
        n1 = int(rng.integers(5, 7)); plen = 1.0 + rng.random() * 0.2; pw = 0.78
        layers = [(n1, plen, pw, 0.3, "F", 0.9, 0.6), (n1, plen * 0.7, pw * 0.8, 0.7, "A", 0.9, 0.5)]
    for layer, (cnt, ln, wd, elev, role, cup, curl) in enumerate(layers):
        off = layer * 0.5 * 2 * np.pi / cnt + rng.random() * 0.2
        for k in range(cnt):
            a = off + k * 2 * np.pi / cnt
            radial = np.cos(a) * X + np.sin(a) * Z
            dirv = unit(radial * np.cos(elev) + axis * np.sin(elev))
            base = hc + radial * 0.12 + axis * (0.02 * layer)
            put(d, role, petal(base, dirv, ln, wd, cup=cup, curl=curl, up=axis, nu=6, nv=4))
    # серединка
    put(d, "A", ellipsoid((0.3, 0.14, 0.3), hc + axis * 0.1, frame(axis), 14, 8))
    put(d, "G", sphere(0.15, 12, 8).xform(None, hc + axis * 0.27))
    for k in range(11):
        a = k * 2.4
        radial = np.cos(a) * X + np.sin(a) * Z
        tip = hc + axis * (0.38 + 0.05 * (k % 3)) + radial * (0.16 + 0.08 * (k % 2))
        put(d, "G", tube(np.array([hc + axis * 0.15 + radial * 0.05, tip]), [0.015, 0.012], 5))
        put(d, "G", sphere(0.04, 8, 5).xform(None, tip))
    # чашелистики и листья
    for k in range(5):
        a = k * 1.26
        radial = np.cos(a) * X + np.sin(a) * Z
        put(d, "L", leaf(hc - axis * 0.05, unit(radial * 0.8 - axis * 0.3), 0.5, 0.17, bend=-0.4, up=axis, nu=6, nv=3))
    for k in range(3):
        a = rng.uniform(0, 2 * np.pi) + k * 2.1
        put(d, "L", leaf(V(0, 0.18 + 0.08 * k, 0), unit(V(np.cos(a), 0.9 + 0.2 * k, np.sin(a))), 1.2 + rng.random() * 0.5, 0.4, bend=0.9, fold=0.3, nu=8, nv=3))
    return d


# ------------------------------------------------------------------ гриб
def _mushroom(rng, hs, rc, spots, d, scale=1.0, off=V(0, 0, 0)):
    s = scale

    def tr(m):
        return m.xform(None, off, s)

    prof = [(0.01, 0), (0.62, 0.02), (0.56, 0.16), (0.4, 0.45), (0.3, hs * 0.55), (0.3, hs * 0.85), (0.38, hs - 0.05), (0.2, hs)]
    put(d, "A", tr(displace(lathe(prof, 22), 0.05, 2.5, int(rng.integers(0, 99)))))
    ring_y = hs * 0.62
    put(d, "A", tr(lathe([(0.3, ring_y + 0.08), (0.62, ring_y - 0.1), (0.7, ring_y - 0.2), (0.34, ring_y - 0.14)], 26)))
    capH = rc * 0.55
    prof = [(0.02, hs - 0.1), (rc * 0.55, hs - 0.2), (rc * 0.93, hs - 0.18), (rc * 1.0, hs - 0.06)]
    for t in np.linspace(0.12, np.pi / 2, 14):
        prof.append((rc * np.cos(t) * 0.99 + 0.01, hs - 0.02 + capH * np.sin(t) ** 0.9))
    prof[-1] = (0.01, prof[-1][1])
    put(d, "F", tr(displace(lathe(prof, 26), 0.045, 2.2, int(rng.integers(0, 99)))))
    # тёмная нижняя сторона с пластинками
    put(d, "R", tr(lathe_fn(lambda a, y: (rc * 0.98) * (1 - (y - (hs - 0.18)) * 2.0) * (1 + 0.04 * np.cos(a * 40)) + 0.02, np.linspace(hs - 0.18, hs - 0.1, 3), 48)))
    for k in range(spots):
        th = rng.uniform(0, 2 * np.pi)
        t = rng.uniform(0.25, 1.3)
        r = rc * np.cos(t) * 0.98
        y = hs - 0.02 + capH * np.sin(t) ** 0.9
        p = V(np.cos(th) * r, y, np.sin(th) * r)
        nrm = unit(V(np.cos(th) * np.cos(t), np.sin(t) * 1.4, np.sin(th) * np.cos(t)))
        sz = rng.uniform(0.1, 0.24) * rc
        put(d, "A", tr(ellipsoid((sz, sz * 0.32, sz), p + nrm * 0.015, frame(nrm), 8, 4)))


def mushroom(rng, lvl=0.0):
    d = {}
    hs = 1.2 + rng.random() * 0.7
    rc = 1.1 + rng.random() * 0.45
    _mushroom(rng, hs, rc, int(rng.integers(8, 15)), d)
    for k in range(2):
        a = rng.uniform(0, 2 * np.pi)
        r = rng.uniform(1.0, 1.5)
        sc = rng.uniform(0.22, 0.4)
        _mushroom(rng, 1.0 + rng.random() * 0.4, 0.8, 3, d, sc, V(np.cos(a) * r, 0, np.sin(a) * r))
    for k in range(5):
        a = rng.uniform(0, 2 * np.pi)
        r = rng.uniform(0.7, 1.2)
        put(d, "L", blob((0.3, 0.1, 0.25), V(np.cos(a) * r, 0.04, np.sin(a) * r), None, 0.2, 2.0, k, 10, 6))
    for k in range(int(5 + 6 * lvl)):
        a = rng.uniform(0, 2 * np.pi)
        r = rng.uniform(0.2, rc * 0.9)
        put(d, "G", sphere(0.045, 8, 5).xform(None, V(np.cos(a) * r, hs + rng.uniform(0.0, 1.1), np.sin(a) * r)))
    return d


# ------------------------------------------------------------------ кристаллы
def crystal(rng, lvl=0.0):
    d = {}
    put(d, "R", blob((1.0, 0.42, 0.9), V(0, 0.08, 0), None, 0.25, 1.5, int(rng.integers(0, 99)), 22, 12))
    n = int(rng.integers(6, 10))
    specs = [(V(0, 0.2, 0), 2.8 + rng.random() * 0.6, 0.42, 0.0, 0.0)]
    for k in range(n - 1):
        a = k / (n - 1) * 2 * np.pi + rng.random() * 0.5
        r = rng.uniform(0.45, 1.05)
        h = rng.uniform(1.0, 2.3) * (1.1 - r * 0.3)
        specs.append((V(np.cos(a) * r, 0.15, np.sin(a) * r), h, rng.uniform(0.25, 0.4), a, rng.uniform(0.15, 0.45)))
    for pos, h, rad, a, tilt in specs:
        axis = unit(V(np.cos(a) * np.sin(tilt), np.cos(tilt), np.sin(a) * np.sin(tilt)))
        put(d, "F", prism(pos, axis, h, rad, 6, 0.28, 0.9, rng.random()))
        put(d, "G", prism(pos + axis * 0.08, axis, h * 0.8, rad * 0.35, 6, 0.3, 0.85))
    for k in range(5):
        a = rng.uniform(0, 2 * np.pi)
        r = rng.uniform(1.0, 1.5)
        put(d, "F", prism(V(np.cos(a) * r, 0.04, np.sin(a) * r), unit(V(np.cos(a) * 0.5, 1, np.sin(a) * 0.5)), rng.uniform(0.3, 0.6), 0.1, 6, 0.3))
    return d


# ------------------------------------------------------------------ медуза
def jelly(rng, lvl=0.0):
    d = {}
    R = 1.0 + rng.random() * 0.25
    yb = 1.5
    ytop = yb + R * 0.95
    wob = rng.uniform(8, 13)

    def rf(a, y):
        h = (y - yb) / (ytop - yb)
        return R * np.sqrt(np.clip(1 - h * h, 0, 1)) * (1 + 0.07 * np.cos(wob * a) * (1 - h) ** 2) + 0.02

    put(d, "F", lathe_fn(rf, np.linspace(yb, ytop, 16), 48))
    put(d, "G", blob((0.45, 0.35, 0.45), V(0, yb + 0.5, 0), None, 0.12, 2, 3, 16, 10))
    for k in range(4):
        a = k * np.pi / 2 + rng.random() * 0.3
        put(d, "G", tube(curve([V(np.cos(a) * 0.25, yb + 0.8, np.sin(a) * 0.25), V(np.cos(a) * 0.6, yb + 0.6, np.sin(a) * 0.6), V(np.cos(a) * 0.5, yb + 0.25, np.sin(a) * 0.5)], 12), 0.035, 6))
    # щупальца
    nt = int(rng.integers(10, 15))
    for k in range(nt):
        a = k / nt * 2 * np.pi
        L = rng.uniform(1.3, 2.1)
        ph = rng.uniform(0, 6.28)
        pts = []
        for s in np.linspace(0, 1, 9):
            pts.append(V(np.cos(a) * (R * 0.92 - 0.05 * s * R) + 0.14 * np.sin(s * 6 + ph), yb - s * L, np.sin(a) * (R * 0.92 - 0.05 * s * R) + 0.14 * np.cos(s * 5 + ph)))
        put(d, "A", tube(curve(pts, 22), lambda t: 0.05 * (1 - t * 0.8) + 0.01, 6))
        put(d, "G", sphere(0.05, 8, 5).xform(None, pts[-1]))
    # ротовые лопасти
    for k in range(4):
        a = k * np.pi / 2 + 0.4
        pts = [V(np.cos(a) * 0.15, yb + 0.1, np.sin(a) * 0.15), V(np.cos(a) * 0.3, yb - 0.5, np.sin(a) * 0.3), V(np.cos(a) * 0.2 + 0.2, yb - 1.1, np.sin(a) * 0.2), V(np.cos(a) * 0.3 - 0.1, yb - 1.7, np.sin(a) * 0.3 + 0.1)]
        put(d, "A", ribbon(curve(pts, 16), np.linspace(0.18, 0.04, 16), V(0, 0, 1) if k % 2 else V(1, 0, 0), 4))
    # поводок к земле
    put(d, "L", stem_tube([V(0, 0, 0), V(0.1, 0.5, 0.05), V(-0.05, 1.0, 0)], 0.07, 0.04, 6))
    put(d, "R", blob((0.5, 0.2, 0.5), V(0, 0.08, 0), None, 0.2, 2, 5, 14, 8))
    return d


# ------------------------------------------------------------------ ягодный куст
def orb(rng, lvl=0.0):
    d = {}
    nb = int(rng.integers(4, 7))
    for k in range(nb):
        a = k / nb * 2 * np.pi + rng.uniform(-0.3, 0.3)
        reach = rng.uniform(0.9, 1.35)
        top = rng.uniform(1.5, 2.1)
        pts = [V(0, 0, 0), V(np.cos(a) * 0.25, 0.8, np.sin(a) * 0.25), V(np.cos(a) * reach * 0.7, top * 0.85, np.sin(a) * reach * 0.7), V(np.cos(a) * reach, top, np.sin(a) * reach)]
        c = curve(pts, 20)
        put(d, "L", tube(c, lambda t: 0.075 - 0.04 * t, 6))
        tip = c[-1]
        for j, t in enumerate([0.35, 0.55, 0.75]):
            p = c[int(t * 19)]
            aa = a + (1.2 if j % 2 else -1.2)
            put(d, "L", leaf(p, unit(V(np.cos(aa), 0.35, np.sin(aa))), 0.8, 0.34, bend=0.6, fold=0.3, nu=6, nv=2))
        nbry = int(rng.integers(3, 5))
        for j in range(nbry):
            aj = j / nbry * 2 * np.pi + a
            r = rng.uniform(0.16, 0.3)
            bp = tip + V(np.cos(aj) * 0.22, -0.18 - 0.3 * rng.random(), np.sin(aj) * 0.22)
            put(d, "L", tube(np.array([tip + V(0, 0.02, 0), bp + V(0, r * 0.9, 0)]), 0.02, 5))
            put(d, "F", blob((r, r * 0.95, r), bp, None, 0.04, 3, int(rng.integers(0, 99)), 10, 7))
            put(d, "L", leaf(bp + V(0, r * 0.85, 0), V(0.3, 0.2, 0), r * 0.9, r * 0.3, bend=-0.3, nu=4, nv=2))
            put(d, "G", sphere(r * 0.2, 8, 5).xform(None, bp + V(-r * 0.4, r * 0.4, r * 0.5)))
    for k in range(3):
        a = rng.uniform(0, 6.28)
        put(d, "A", blob((0.14, 0.14, 0.14), V(np.cos(a) * 0.5, 1.2 + k * 0.2, np.sin(a) * 0.5), None, 0.03, 3, k, 10, 6))
    put(d, "G", sphere(0.18, 12, 8).xform(None, V(0, 1.9, 0)))
    return d


# ------------------------------------------------------------------ тюльпан
def tulip(rng, lvl=0.0):
    d = {}
    H = 2.3 + rng.random() * 0.6
    lean = V(rng.uniform(-0.3, 0.3), 0, rng.uniform(-0.3, 0.3))
    pts = [V(0, 0, 0), V(lean[0] * 0.4, H * 0.5, lean[2] * 0.4), V(lean[0], H, lean[2])]
    s = curve(pts, 20)
    put(d, "L", tube(s, lambda t: 0.08 - 0.02 * t, 7))
    hc = s[-1]
    for layer in range(2):
        cnt = 3 if layer == 0 else 3
        for k in range(cnt):
            a = k / cnt * 2 * np.pi + layer * np.pi / 3
            radial = V(np.cos(a), 0, np.sin(a))
            axis = unit(radial * (0.38 - 0.1 * layer) + V(0, 1, 0))
            put(d, "F" if layer == 0 else "A", petal(hc + radial * 0.06, axis, 1.15 - 0.15 * layer, 0.46 - 0.04 * layer, cup=0.95, curl=-0.35, up=-radial, nu=10, nv=6))
    put(d, "G", sphere(0.14, 10, 6).xform(None, hc + V(0, 0.45, 0)))
    for k in range(6):
        a = k * 1.05
        base = hc + V(0, 0.1, 0)
        tip = hc + V(np.cos(a) * 0.12, 0.62, np.sin(a) * 0.12)
        put(d, "G", tube(np.array([base, tip]), [0.018, 0.012], 5))
    for k in range(2):
        a = k * np.pi + rng.uniform(-0.5, 0.5)
        put(d, "L", leaf(V(0, 0.06, 0), unit(V(np.cos(a) * 0.6, 1, np.sin(a) * 0.6)), 1.9 + rng.random() * 0.3, 0.5, bend=1.1, fold=0.35, nu=10, nv=4))
    return d


# ------------------------------------------------------------------ лиана
def vine(rng, lvl=0.0):
    d = {}
    turns = 3 + rng.random() * 1.2
    H = 3.0 + rng.random() * 0.8
    n = 70
    P = twist_pts((0, 0, 0), lambda t: 0.55 * (1 - 0.35 * t) + 0.05, lambda t: t * H, turns, n, rng.uniform(0, 6))
    put(d, "L", tube(P, lambda t: 0.09 * (1 - t * 0.6), 7, False))
    fr = set(int(x) for x in rng.choice(np.arange(18, 62), 3, replace=False))
    for i in range(6, n - 4, 5):
        out = unit(V(P[i][0], 0, P[i][2]))
        side = V(-out[2], 0, out[0])
        put(d, "L", leaf(P[i], unit(out + V(0, 0.35, 0) + side * 0.3), 0.8, 0.5, bend=0.55, fold=0.35, nu=8, nv=5))
        if i % 10 == 1:
            sp = P[i] + out * 0.12
            sp2 = sp + out * 0.3 + side * 0.15
            sp3 = sp2 + V(0, -0.1, 0) + side * 0.05
            tr = twist_pts((0, 0, 0), lambda t: 0.1 * (1 - t) + 0.01, lambda t: 0 * t, 2.2, 14)
            put(d, "L", tube(np.array([sp + t for t in tr[:, :]]) * 0 + (tr + sp2), 0.012, 5))
    for i in sorted(fr):
        out = unit(V(P[i][0], 0, P[i][2]))
        top = P[i] + out * 0.12
        pos = top + out * 0.35 + V(0, -0.6, 0)
        put(d, "L", tube(curve([P[i], top + out * 0.15 + V(0, 0.05, 0), pos + V(0, 0.28, 0)], 10), 0.025, 5))
        put(d, "F", blob((0.22, 0.28, 0.22), pos, None, 0.03, 3, i, 14, 9))
        put(d, "A", sphere(0.05, 6, 4).xform(None, pos + V(0, -0.27, 0)))
        put(d, "G", sphere(0.06, 8, 5).xform(None, pos + V(-0.1, 0.1, 0.15)))
    top = P[-1]
    for k in range(6):
        a = k * 1.05
        put(d, "A", petal(top, unit(V(np.cos(a) * 0.6, 1, np.sin(a) * 0.6)), 0.4, 0.14, cup=0.5, curl=0.3, up=V(0, 1, 0), nu=6, nv=4))
    put(d, "G", sphere(0.12, 10, 6).xform(None, top + V(0, 0.1, 0)))
    return d


# ------------------------------------------------------------------ коралл
def coral(rng, lvl=0.0):
    d = {}
    put(d, "R", blob((1.0, 0.3, 0.9), V(0, 0.05, 0), None, 0.2, 1.8, int(rng.integers(0, 99)), 18, 10))

    def branch(p, dr, ln, r, depth):
        dr = unit(dr)
        nxt = p + dr * ln
        mid = p + dr * ln * 0.5 + V(rng.uniform(-0.1, 0.1), 0, rng.uniform(-0.1, 0.1)) * ln
        c = curve([p, mid, nxt], 6)
        put(d, "F", tube(c, lambda t: r * (1 - 0.3 * t), 7, depth == 0))
        if depth == 0:
            put(d, "A", blob((r * 1.6, r * 1.9, r * 1.6), nxt + dr * r * 0.5, frame(dr), 0.12, 3, int(rng.integers(0, 99)), 9, 6))
            put(d, "G", sphere(r * 0.7, 6, 4).xform(None, nxt + dr * r * 1.8))
            return
        nc = int(rng.integers(2, 4))
        for k in range(nc):
            a = k / nc * 2 * np.pi + rng.uniform(0, 1)
            side = unit(np.cross(dr, V(0.3, 1, 0.2)))
            side2 = np.cross(dr, side)
            nd = dr * 0.7 + (side * np.cos(a) + side2 * np.sin(a)) * rng.uniform(0.5, 0.8)
            branch(nxt, nd, ln * rng.uniform(0.62, 0.78), r * 0.68, depth - 1)
        for k in range(2):
            t = rng.uniform(0.2, 0.9)
            pp = p + (nxt - p) * t
            put(d, "A", sphere(r * 0.45, 6, 4).xform(None, pp + V(np.cos(k * 2.1), 0, np.sin(k * 2.1)) * r * 0.9))

    nt = int(rng.integers(3, 5))
    for k in range(nt):
        a = k / nt * 2 * np.pi + rng.uniform(0, 1)
        branch(V(np.cos(a) * 0.35, 0.15, np.sin(a) * 0.35), V(np.cos(a) * 0.45, 1, np.sin(a) * 0.45), rng.uniform(0.9, 1.2), 0.2, 2)
    return d


# ------------------------------------------------------------------ тыква
def gourd(rng, lvl=0.0):
    d = {}
    ribs = int(rng.choice([7, 8, 9, 10]))
    R = 1.15 + rng.random() * 0.2
    Hh = 0.95 + rng.random() * 0.25
    yc = Hh + 0.05
    depth = rng.uniform(0.09, 0.15)

    def rf(a, y):
        h = np.clip((y - yc) / Hh, -1, 1)
        base = R * np.sqrt(np.clip(1 - h * h, 0, 1))
        return base * (1 + depth * np.cos(ribs * a) * (1 - 0.5 * h * h)) + 0.01

    hs = np.concatenate([[yc - Hh], yc + Hh * np.sin(np.linspace(-np.pi / 2 + 0.05, np.pi / 2 - 0.05, 22)), [yc + Hh]])
    put(d, "F", lathe_fn(rf, hs, 56))
    # стебель
    pts = [V(0, yc + Hh - 0.15, 0), V(0.05, yc + Hh + 0.2, 0.02), V(0.2, yc + Hh + 0.5, 0.05), V(0.45, yc + Hh + 0.62, 0.1)]
    put(d, "L", tube(curve(pts, 14), lambda t: 0.14 - 0.05 * t, 8))
    put(d, "L", blob((0.3, 0.07, 0.3), V(0, yc + Hh - 0.12, 0), None, 0.15, 3, 2, 12, 6))
    # лист и усик
    put(d, "L", leaf(V(0.1, yc + Hh - 0.1, 0.1), V(1, 0.35, 0.3), 1.3, 0.85, bend=0.5, fold=0.2, nu=9, nv=7))
    tr = twist_pts((0, 0, 0), lambda t: 0.12 * (1 - t * 0.8) + 0.01, lambda t: t * 0.55, 3, 22)
    put(d, "L", tube(tr + V(0.5, yc + Hh - 0.35, -0.2), 0.012, 5, False))
    put(d, "G", sphere(0.1, 8, 5).xform(None, V(0.45, yc + Hh + 0.7, 0.1)))
    for k in range(3):
        a = k * 2.1 + 0.5
        put(d, "A", blob((0.12, 0.05, 0.12), V(np.cos(a) * 1.05, 0.12, np.sin(a) * 1.05), None, 0.1, 3, k, 8, 5))
    return d


# ------------------------------------------------------------------ дерево
def tree(rng, lvl=0.0):
    d = {}
    H = 2.6 + rng.random() * 0.5
    lean = V(rng.uniform(-0.25, 0.25), 0, rng.uniform(-0.25, 0.25))
    pts = [V(0, 0, 0), V(lean[0] * 0.3, H * 0.35, lean[2] * 0.3), V(lean[0] * 0.8, H * 0.7, lean[2] * 0.8), V(lean[0], H, lean[2])]
    c = curve(pts, 28)
    put(d, "R", tube(c, lambda t: 0.36 * (1 - t) ** 0.8 + 0.12, 10))
    for k in range(5):
        a = k / 5 * 2 * np.pi + rng.uniform(0, 0.5)
        put(d, "R", tube(curve([V(np.cos(a) * 0.15, 0.55, np.sin(a) * 0.15), V(np.cos(a) * 0.5, 0.18, np.sin(a) * 0.5), V(np.cos(a) * 0.95, 0.0, np.sin(a) * 0.95)], 10), lambda t: 0.16 * (1 - t) + 0.03, 6))
    ends = []
    nb = int(rng.integers(4, 7))
    for k in range(nb):
        a = k / nb * 2 * np.pi + rng.uniform(0, 0.8)
        h0 = rng.uniform(0.55, 0.85)
        start = c[int(h0 * 27)]
        e = V(lean[0] + np.cos(a) * rng.uniform(0.9, 1.4), H + rng.uniform(-0.2, 0.6), lean[2] + np.sin(a) * rng.uniform(0.9, 1.4))
        put(d, "R", tube(curve([start, (start + e) / 2 + V(0, 0.2, 0), e], 12), lambda t: 0.1 * (1 - t) + 0.03, 6))
        ends.append(e)
    ends.append(c[-1] + V(0, 0.5, 0))
    fruit_pos = []
    for e in ends:
        rr = rng.uniform(0.7, 1.0)
        put(d, "F", blob((rr, rr * 0.8, rr), e + V(0, 0.2, 0), None, 0.22, 1.8, int(rng.integers(0, 99)), 14, 9))
        for j in range(2):
            a = rng.uniform(0, 6.28)
            s = rng.uniform(0.35, 0.55)
            put(d, "F", blob((s, s * 0.8, s), e + V(np.cos(a) * rr * 0.75, 0.05 + rng.uniform(0, 0.3), np.sin(a) * rr * 0.75), None, 0.18, 2.2, j, 10, 7))
        fruit_pos.append((e, rr))
    for k in range(int(6 + 4 * lvl)):
        e, rr = fruit_pos[k % len(fruit_pos)]
        a = rng.uniform(0, 6.28)
        p = e + V(np.cos(a) * rr * 0.72, -0.4 - rng.random() * 0.2, np.sin(a) * rr * 0.72)
        put(d, "L", tube(np.array([p + V(0, 0.22, 0), p + V(0, 0.08, 0)]), 0.012, 4))
        put(d, "A", blob((0.17, 0.2, 0.17), p, None, 0.03, 3, k, 10, 7))
        put(d, "G", sphere(0.07, 8, 5).xform(None, p + V(0, -0.02, 0)))
    return d


# ------------------------------------------------------------------ спираль
def spiral(rng, lvl=0.0):
    d = {}
    turns = 2.4 + rng.random() * 0.8
    H = 3.2 + rng.random() * 0.4
    n = 90
    P = twist_pts((0, 0, 0), lambda t: 0.95 - 0.7 * t, lambda t: 0.2 + t * H, turns, n)
    wid = np.linspace(0.36, 0.09, n)
    put(d, "F", ribbon(P, wid, V(0, 1, 0), 4, 0.07))
    put(d, "G", tube(P + V(0, 0.06, 0), lambda t: 0.04 * (1 - t) + 0.015, 6, False))
    for i in range(6, n, 8):
        put(d, "A", blob((0.09, 0.09, 0.09) if i % 16 else (0.13, 0.13, 0.13), P[i] + V(0, 0.1, 0), None, 0.02, 3, i, 9, 6))
    put(d, "G", tube(np.array([V(0, 0.15, 0), V(0, 0.2 + H, 0)]), lambda t: 0.05 * (1 - t) + 0.02, 6))
    put(d, "G", sphere(0.22, 12, 8).xform(None, V(0, 0.38 + H, 0)))
    put(d, "R", blob((0.9, 0.25, 0.9), V(0, 0.05, 0), None, 0.2, 2, int(rng.integers(0, 99)), 18, 10))
    return d


# ------------------------------------------------------------------ звезда
def star(rng, lvl=0.0):
    d = {}
    pts = int(rng.choice([5, 5, 6, 7]))
    outer = 1.15
    o = star_outline(pts, outer, outer * rng.uniform(0.42, 0.55))
    st = pillow(o, 0.4, 8)
    Mx = rotx(np.pi / 2) @ roty(rng.uniform(-0.3, 0.3))
    # звезда стоит вертикально, лицом к камере
    st = st.xform(rotx(0) @ roty(0.0), V(0, 2.2, 0))
    put(d, "F", st)
    inner = pillow(o * 0.55, 0.44, 7).xform(None, V(0, 2.2, 0))
    put(d, "G", inner)
    put(d, "G", sphere(0.2, 10, 6).xform(None, V(0, 2.2, 0.38)))
    for k in range(pts):
        a = np.pi / 2 + k / pts * 2 * np.pi
        put(d, "G", sphere(0.07, 8, 5).xform(None, V(np.cos(a) * outer * 0.93, 2.2 + np.sin(a) * outer * 0.93, 0.03)))
    ring = np.array([V(np.cos(t) * 1.7, 2.2 + np.sin(t) * 0.35, np.sin(t) * 1.7) for t in np.linspace(0, 2 * np.pi, 48)])
    put(d, "A", tube(ring, 0.03, 6))
    for k in range(3):
        t = k * 2.1 + 0.5
        put(d, "G", sphere(0.1, 8, 5).xform(None, V(np.cos(t) * 1.7, 2.2 + np.sin(t) * 0.35, np.sin(t) * 1.7)))
    put(d, "L", stem_tube([V(0, 0, 0), V(0.06, 0.7, 0.03), V(0, 1.3, 0)], 0.07, 0.04, 6))
    put(d, "R", blob((0.5, 0.2, 0.5), V(0, 0.08, 0), None, 0.2, 2, 4, 14, 8))
    return d


# ------------------------------------------------------------------ сердце
def heart(rng, lvl=0.0):
    d = {}
    ho = heart_outline(56, 0.055)
    put(d, "F", pillow(ho, 0.55, 9).xform(None, V(0, 2.1, 0)))
    put(d, "G", pillow(ho * 0.6, 0.6, 8).xform(None, V(0, 2.1, 0)))
    put(d, "R", lathe([(1e-3, 0), (1.1, 0), (1.05, 0.2), (0.7, 0.35), (0.5, 0.7), (0.55, 1.0), (0.4, 1.15), (1e-3, 1.15)], 20))
    for k in range(7):
        a = k / 7 * 2 * np.pi
        pts = [V(np.cos(a) * 0.9, 0.2, np.sin(a) * 0.9), V(np.cos(a + 0.3) * 0.7, 0.8, np.sin(a + 0.3) * 0.7), V(np.cos(a + 0.6) * 0.45, 1.25, np.sin(a + 0.6) * 0.45)]
        put(d, "L", tube(curve(pts, 12), 0.03, 5))
    for k in range(7):
        a = k / 7 * 2 * np.pi
        put(d, "G", sphere(0.07, 8, 5).xform(None, V(np.cos(a) * 1.5, 2.0 + np.sin(a * 2) * 0.35, np.sin(a) * 1.5)))
    return d


# ------------------------------------------------------------------ корона
def crown(rng, lvl=0.0):
    d = {}
    put(d, "R", lathe([(1e-3, 0), (1.0, 0), (0.95, 0.18), (0.45, 0.3), (0.4, 0.6), (0.6, 0.85), (1e-3, 0.85)], 22))
    gold = lambda m: m
    band = lathe([(0.78, 1.15), (0.9, 1.2), (0.92, 1.55), (0.84, 1.7), (0.8, 1.7), (0.8, 1.15)], 40)
    put(d, "F", band)
    put(d, "A", lathe([(0.8, 1.2), (0.78, 1.65), (0.5, 1.2)], 32))
    n = int(rng.integers(6, 9))
    for k in range(n):
        a = k / n * 2 * np.pi
        base = V(np.cos(a) * 0.86, 1.62, np.sin(a) * 0.86)
        axis = unit(V(np.cos(a) * 0.18, 1, np.sin(a) * 0.18))
        h = 0.95 + 0.3 * (k % 2)
        put(d, "F", cone(0.2, h, 14, base, frame(axis), 0.02))
        put(d, "G", prism(base + axis * h, axis, 0.25, 0.1, 8, 0.5, 0.9))
        # камни по ободу
        put(d, "G", sphere(0.07, 8, 5).xform(None, V(np.cos(a + np.pi / n) * 0.93, 1.38, np.sin(a + np.pi / n) * 0.93)))
    put(d, "G", prism(V(0, 1.7, 0), V(0, 1, 0), 0.7, 0.28, 8, 0.5, 0.95))
    put(d, "G", prism(V(0, 1.7, 0), V(0, -1, 0), 0.25, 0.28, 8, 0.5, 0.95).xform(None, V(0, 0, 0)))
    return d


# ------------------------------------------------------------------ жеода
def geode(rng, lvl=0.0):
    d = {}
    put(d, "R", blob((1.2, 0.8, 1.1), V(0, 0.6, 0), None, 0.35, 1.4, int(rng.integers(0, 99)), 26, 16))
    put(d, "R", blob((0.7, 0.4, 0.65), V(0.95, 0.25, 0.5), None, 0.25, 2, 3, 16, 10))
    put(d, "R", blob((0.6, 0.35, 0.55), V(-0.9, 0.2, -0.5), None, 0.25, 2, 5, 16, 10))
    put(d, "A", lathe([(0.78, 1.18), (0.9, 1.1), (0.95, 1.0), (0.7, 1.12), (0.45, 1.2)], 36))
    put(d, "G", blob((0.55, 0.3, 0.5), V(0, 1.3, 0), None, 0.06, 3, 7, 14, 8))
    n = int(rng.integers(8, 12))
    for k in range(n):
        a = k / n * 2 * np.pi + rng.random() * 0.4
        r = rng.uniform(0.1, 0.7)
        h = rng.uniform(0.9, 2.1)
        tilt = rng.uniform(0.1, 0.5) * (r + 0.3)
        axis = unit(V(np.cos(a) * np.sin(tilt), np.cos(tilt), np.sin(a) * np.sin(tilt)))
        pos = V(np.cos(a) * r, 1.15, np.sin(a) * r)
        put(d, "F", prism(pos, axis, h, rng.uniform(0.18, 0.3), 6, 0.3, 0.9, rng.random()))
        put(d, "G", prism(pos + axis * 0.05, axis, h * 0.75, 0.08, 6, 0.3, 0.9))
    return d


# ------------------------------------------------------------------ трава
def grass(rng, lvl=0.0):
    d = {}
    nb = int(rng.integers(15, 22))
    ears = set(int(x) for x in rng.choice(nb, 5, replace=False))
    for k in range(nb):
        a = rng.uniform(0, 2 * np.pi)
        rr = rng.uniform(0.05, 0.4)
        lean = rng.uniform(0.15, 0.55)
        axis = unit(V(np.cos(a) * lean, 1, np.sin(a) * lean))
        ln = rng.uniform(1.7, 2.9)
        base = V(np.cos(a) * rr, 0, np.sin(a) * rr)
        role = "A" if k % 5 == 0 else "L"
        put(d, role, leaf(base, axis, ln, rng.uniform(0.13, 0.2), bend=rng.uniform(0.6, 1.3), fold=0.3, up=V(0, 1, 0), nu=12, nv=3, thick=0.02, tipshape=0.55))
        if k in ears:
            # колос: зёрна по спирали на конце
            p = base + axis * ln * 0.78
            for j in range(9):
                t = j / 8
                aa = j * 2.2
                pos = p + axis * t * 0.5 + V(np.cos(aa), 0, np.sin(aa)) * 0.07 * (1 - t * 0.5)
                put(d, "F", ellipsoid((0.06, 0.12, 0.06), pos, frame(unit(axis + V(np.cos(aa), 0, np.sin(aa)) * 0.5)), 8, 5))
            put(d, "G", sphere(0.05, 8, 5).xform(None, p + axis * 0.58))
    return d


# ------------------------------------------------------------------ перец
def pod(rng, lvl=0.0):
    d = {}
    pts = [V(0, 0, 0), V(0.1, 1.0, 0.05), V(0.0, 1.9, 0.0), V(0.1, 2.5, 0.05)]
    put(d, "L", tube(curve(pts, 20), lambda t: 0.1 * (1 - 0.5 * t), 7))
    for k in range(8):
        a = k * 2.0 + rng.uniform(0, 1)
        y = 0.7 + k * 0.22
        put(d, "L", leaf(V(0.05, y, 0), unit(V(np.cos(a), 0.4, np.sin(a))), 0.85, 0.42, bend=0.6, fold=0.3, nu=8, nv=4))
    n = int(rng.integers(3, 5))
    for k in range(n):
        a = k / n * 2 * np.pi + 0.4
        br = V(np.cos(a) * 0.85, 2.1 + 0.1 * (k % 2), np.sin(a) * 0.85)
        put(d, "L", tube(curve([V(0.05, 1.8 + 0.1 * k, 0), (V(0.05, 1.9, 0) + br) / 2 + V(0, 0.2, 0), br], 10), 0.04, 5))
        L = rng.uniform(1.2, 1.7)
        curl = rng.uniform(0.3, 0.6)
        path = []
        for s in np.linspace(0, 1, 16):
            path.append(br + V(np.cos(a) * curl * s * s, -L * s, np.sin(a) * curl * s * s) + V(0, -0.0, 0))
        rad = lambda t: 0.3 * np.sin(np.pi * np.clip(t * 0.9 + 0.1, 0, 1) ** 0.7) * (1 - 0.15 * t) + 0.02
        put(d, "F", tube(np.array(path), rad, 12, False))
        put(d, "A", blob((0.12, 0.12, 0.12), path[-1] + V(0, -0.02, 0), None, 0.03, 3, k, 8, 5))
        put(d, "L", blob((0.24, 0.1, 0.24), br + V(0, -0.02, 0), None, 0.1, 3, k, 10, 6))
        put(d, "G", sphere(0.06, 8, 5).xform(None, path[3] + V(-0.15, 0, 0.12)))
    return d


# ------------------------------------------------------------------ кактус
def cactus(rng, lvl=0.0):
    d = {}
    ribs = int(rng.choice([8, 9, 10, 12]))
    Hh = 2.5 + rng.random() * 0.7
    R = 0.62 + rng.random() * 0.15

    def rf(a, y):
        t = y / Hh
        base = R * (0.85 + 0.15 * np.sin(np.clip(t, 0, 1) * np.pi * 0.5 + 0.2)) * (1.12 if t < 0.1 else 1.0)
        if t > 0.85:
            base *= np.sqrt(np.clip(1 - ((t - 0.85) / 0.15) ** 2, 0, 1))
        return base * (1 + 0.1 * np.cos(ribs * a)) + 0.005

    hs = np.linspace(0.0, Hh, 36)
    put(d, "F", lathe_fn(rf, hs, ribs * 4 + 8))
    # колючки
    for k in range(ribs):
        a = k / ribs * 2 * np.pi
        for j in range(8):
            y = 0.3 + j * (Hh - 0.7) / 7
            r = rf(np.array([a]), y)[0] * 1.0
            p = V(np.cos(a) * r, y, np.sin(a) * r)
            out = V(np.cos(a), 0.25, np.sin(a))
            put(d, "A", cone(0.025, 0.2, 5, p, frame(out), 0.0))
    # руки
    for sgn, hh in ((1, rng.uniform(0.9, 1.3)), (-1, rng.uniform(0.7, 1.1))):
        a = rng.uniform(0, np.pi) if sgn == 1 else rng.uniform(np.pi, 2 * np.pi)
        o = V(np.cos(a), 0, np.sin(a))
        pts = [o * 0.4 + V(0, hh, 0), o * 0.95 + V(0, hh + 0.05, 0), o * 1.2 + V(0, hh + 0.6, 0), o * 1.2 + V(0, hh + 1.15, 0)]
        put(d, "F", tube(curve(pts, 16), 0.26, 12, False))
        put(d, "F", sphere(0.26, 12, 8).xform(None, pts[-1]))
        for j in range(5):
            put(d, "A", cone(0.022, 0.18, 5, pts[-1] + V(np.cos(j * 1.3), 0.0, np.sin(j * 1.3)) * 0.25 + V(0, -0.1 * j, 0), frame(V(np.cos(j * 1.3), 0.3, np.sin(j * 1.3))), 0.0))
    top = V(0, Hh * 0.99, 0)
    for k in range(9):
        a = k / 9 * 2 * np.pi
        radial = V(np.cos(a), 0, np.sin(a))
        put(d, "A", petal(top + radial * 0.08, unit(radial * 0.6 + V(0, 1, 0)), 0.5, 0.16, cup=0.5, curl=0.4, up=V(0, 1, 0), nu=6, nv=4))
    put(d, "G", sphere(0.14, 10, 6).xform(None, top + V(0, 0.1, 0)))
    return d


# ------------------------------------------------------------------ комета
def comet(rng, lvl=0.0):
    d = {}
    put(d, "L", stem_tube([V(0, 0, 0), V(0.1, 0.9, 0.05), V(0, 1.7, 0)], 0.06, 0.04, 6))
    head = V(0, 2.5, 0)
    put(d, "F", blob((0.62, 0.62, 0.62), head, None, 0.22, 2.2, int(rng.integers(0, 99)), 24, 14))
    put(d, "G", blob((0.82, 0.82, 0.82), head, None, 0.1, 2, 4, 20, 12))
    dr = unit(V(1, 0.65, 0.2))
    P = [head + dr * s + V(0, -0.15 * s * s * 0.1, 0) for s in np.linspace(0.3, 4.3, 24)]
    put(d, "G", tube(np.array(P), lambda t: 0.62 * (1 - t) ** 1.2 + 0.01, 12, False))
    for k in range(4):
        a = k * 1.6
        off = V(0, np.cos(a), np.sin(a)) * 0.35
        Q = [head + dr * s + off * (0.3 + s * 0.15) for s in np.linspace(0.4, 4.0, 20)]
        put(d, "A", ribbon(np.array(Q), np.linspace(0.22, 0.02, 20), V(0, 0, 1), 3, 0.03))
    for k in range(10):
        s = rng.uniform(0.7, 4.0)
        off = V(0, rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5))
        put(d, "G", sphere(rng.uniform(0.03, 0.08), 6, 4).xform(None, head + dr * s + off))
    return d


# ------------------------------------------------------------------ росток
def sprout(rng, lvl=0.0):
    d = {}
    put(d, "L", stem_tube([V(0, 0, 0), V(0.05, 0.8, 0.03), V(0, 1.55, 0)], 0.12, 0.07, 8))
    put(d, "L", leaf(V(0, 0.65, 0), V(1, 0.45, 0.1), 1.6, 0.8, bend=0.7, fold=0.3, nu=10, nv=6))
    put(d, "L", leaf(V(0, 0.85, 0), V(-1, 0.5, 0.3), 1.5, 0.75, bend=0.7, fold=0.3, nu=10, nv=6))
    c = V(0, 1.75, 0)
    for k in range(7):
        a = k / 7 * 2 * np.pi
        radial = V(np.cos(a), 0, np.sin(a))
        put(d, "F", petal(c + radial * 0.04, unit(radial * 0.35 + V(0, 1, 0)), 0.9, 0.38, cup=0.9, curl=-0.2, up=-radial, nu=8, nv=5))
    put(d, "G", sphere(0.3, 14, 9).xform(None, c + V(0, 0.4, 0)))
    for k in range(14):
        a = k * 2.4
        dirv = unit(V(np.cos(a) * 0.9, 0.5 + 0.3 * (k % 3), np.sin(a) * 0.9))
        tip = c + V(0, 0.4, 0) + dirv * rng.uniform(0.7, 1.1)
        put(d, "G", tube(np.array([c + V(0, 0.4, 0), tip]), [0.022, 0.008], 5))
        put(d, "A", sphere(0.05, 6, 4).xform(None, tip))
    return d


# ------------------------------------------------------------------ семя вселенной
def seedcore(rng, lvl=0.0):
    d = {}
    put(d, "R", lathe([(1e-3, 0), (1.0, 0), (0.95, 0.18), (0.55, 0.32), (0.5, 0.55), (1e-3, 0.55)], 20))

    def rf(a, y):
        h = (y - 1.9) / 1.35
        base = 0.95 * np.sqrt(np.clip(1 - h * h, 0, 1)) * (1 - 0.25 * np.clip(h, 0, 1))
        return base * (1 + 0.05 * np.cos(6 * a)) + 0.01

    put(d, "F", lathe_fn(rf, np.linspace(0.55, 3.25, 36), 48))
    for k in range(6):
        a = k / 6 * 2 * np.pi
        pts = []
        for y in np.linspace(0.75, 3.1, 24):
            pts.append(V(np.cos(a + (y - 1.9) * 0.4) * (rf(np.array([a]), y)[0] + 0.015), y, np.sin(a + (y - 1.9) * 0.4) * (rf(np.array([a]), y)[0] + 0.015)))
        put(d, "G", tube(np.array(pts), 0.03, 6, False))
    put(d, "G", blob((0.5, 0.7, 0.5), V(0, 1.9, 0), None, 0.05, 2, 1, 14, 9))
    for k in range(8):
        a = k / 8 * 2 * np.pi
        put(d, "G", sphere(0.1 + 0.03 * (k % 2), 8, 5).xform(None, V(np.cos(a) * 1.5, 1.9 + np.sin(a * 3) * 0.4, np.sin(a) * 1.5)))
    put(d, "L", leaf(V(0, 3.1, 0), V(1, 0.9, 0), 0.9, 0.4, bend=0.6, nu=7, nv=4))
    put(d, "L", leaf(V(0, 3.1, 0), V(-1, 0.9, 0.2), 0.8, 0.36, bend=0.6, nu=7, nv=4))
    return d


# ------------------------------------------------------------------ корнеплод
def bulb(rng, lvl=0.0):
    d = {}
    R = 0.8 + rng.random() * 0.2
    prof = [(1e-3, -0.35), (0.04, -0.3), (0.16, 0.05), (R * 0.7, 0.3), (R, 0.75), (R * 0.88, 1.2), (R * 0.45, 1.55), (0.2, 1.7), (1e-3, 1.72)]
    put(d, "F", displace(lathe(prof, 28), 0.04, 3, int(rng.integers(0, 99))))
    put(d, "A", lathe([(R * 0.5, 1.5), (R * 0.9, 1.15), (R * 0.97, 0.85), (R * 0.95, 0.9), (R * 0.5, 1.55)], 28))
    for k in range(6):
        a = k * 1.0
        pts = [V(np.cos(a) * 0.1, -0.2, np.sin(a) * 0.1), V(np.cos(a) * 0.35, -0.5, np.sin(a) * 0.35)]
        put(d, "A", tube(np.array(pts), [0.025, 0.006], 4))
    nl = int(rng.integers(8, 12))
    for k in range(nl):
        a = k / nl * 2 * np.pi + rng.uniform(0, 0.4)
        put(d, "L", leaf(V(np.cos(a) * 0.1, 1.6, np.sin(a) * 0.1), unit(V(np.cos(a) * 0.7, 1, np.sin(a) * 0.7)), rng.uniform(1.5, 2.3), 0.46, bend=0.9, fold=0.4, nu=11, nv=4))
    put(d, "G", sphere(0.14, 10, 6).xform(None, V(0, 1.75, 0)))
    return d


FORMS = {n: globals()[n] for n in ["flower", "mushroom", "crystal", "jelly", "orb", "tulip", "vine", "coral", "gourd", "tree", "spiral", "star", "heart", "crown", "geode", "grass", "pod", "cactus", "comet", "sprout", "seedcore", "bulb"]}
STYLE = {
    "crystal": {"F": dict(alpha=0.72, spec=0.9, shin=120)},
    "jelly": {"F": dict(alpha=0.6, spec=0.9, shin=90), "A": dict(alpha=0.7)},
    "geode": {"F": dict(alpha=0.78, spec=0.9, shin=120)},
    "crown": {"F": dict(spec=0.9, shin=90)},
}
