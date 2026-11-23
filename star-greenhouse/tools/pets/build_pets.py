"""Питомцы планет: гладкие мультяшные модели из полей расстояний (SDF) + marching cubes.
Каждая модель делится на области цвета (тело, грудка, уши, глаза...), каждая область — отдельный меш
<pet>__<Область> в одном .glb (art/pets/pets.glb). Цвета и материалы задаёт игра (Config/PetLook.luau).
python3 tools/pets/build_pets.py [pet ...]   -> art/pets/pets.glb и превью art/pets/<pet>.png
"""
import os, sys
import numpy as np
from skimage import measure

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "mesh"))
from geom import Mesh  # noqa: E402
import render  # noqa: E402
from glb import write_glb  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "art", "pets")
os.makedirs(OUT, exist_ok=True)


# ---------------------------------------------------------------- поля расстояний
def rot(ax, ay, az):
    cx, sx, cy, sy, cz, sz = np.cos(ax), np.sin(ax), np.cos(ay), np.sin(ay), np.cos(az), np.sin(az)
    Rx = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    Ry = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    Rz = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return Rz @ Ry @ Rx


def sd_ell(P, c, r, R=None):
    q = P - np.asarray(c)
    if R is not None:
        q = q @ R  # в локальные оси
    r = np.asarray(r, dtype=float)
    k0 = np.linalg.norm(q / r, axis=1)
    k1 = np.linalg.norm(q / (r * r), axis=1)
    return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)


def sd_cone(P, a, b, ra, rb):
    """Скруглённый конус между точками a и b (радиусы ra, rb)."""
    a, b = np.asarray(a, float), np.asarray(b, float)
    ba = b - a
    l2 = ba @ ba
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / l2
    pa = P - a
    y = pa @ ba
    z = y - l2
    x2v = pa * l2 - np.outer(y, ba)
    x2 = (x2v * x2v).sum(1)
    y2 = y * y * l2
    z2 = z * z * l2
    k = np.sign(rr) * rr * rr * x2
    out = (np.sqrt(x2 * a2 * il2) + y * rr) * il2 - ra
    m1 = np.sign(z) * a2 * z2 > k
    m2 = np.sign(y) * a2 * y2 < k
    out = np.where(m1, np.sqrt(x2 + z2) * il2 - rb, out)
    out = np.where(m2 & ~m1, np.sqrt(x2 + y2) * il2 - ra, out)
    return out


def smin(a, b, k):
    h = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
    return b * (1 - h) + a * h - k * h * (1 - h)


class Creature:
    """Набор примитивов: (поле, область, мягкость слияния). Цвет вершины берётся у ближайшего примитива."""

    def __init__(self):
        self.smooth = 4
        self.prims = []
        self.extra = []  # отдельные меши (глаза, кольцо, кристаллы)

    def ell(self, region, c, r, R=None, k=0.12, bias=0.0):
        self.prims.append((lambda P, c=c, r=r, R=R: sd_ell(P, c, r, R), region, k, bias))

    def cone(self, region, a, b, ra, rb, k=0.12, bias=0.0):
        self.prims.append((lambda P, a=a, b=b, ra=ra, rb=rb: sd_cone(P, a, b, ra, rb), region, k, bias))

    def build(self, step=0.042, pad=0.25):
        # грубая оценка границ по выборке
        lo = np.array([-2.0, -0.6, -1.8])
        hi = np.array([2.0, 3.4, 2.6])
        xs = np.arange(lo[0], hi[0], step)
        ys = np.arange(lo[1], hi[1], step)
        zs = np.arange(lo[2], hi[2], step)
        G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1).reshape(-1, 3)
        F = None
        for f, region, k, bias in self.prims:
            d = f(G)
            F = d if F is None else smin(F, d, k)
        vol = F.reshape(len(xs), len(ys), len(zs))
        v, faces, normals, _ = measure.marching_cubes(vol, 0.0, spacing=(step, step, step))
        v = v + lo
        # области: у каждой вершины «счёт» каждой области = расстояние до её ближайшего примитива (со сдвигом bias)
        regions = [r for _, r, _, _ in self.prims]
        names = sorted(set(regions))
        S = np.full((len(v), len(names)), 1e9)
        for f, r, _, bias in self.prims:
            j = names.index(r)
            S[:, j] = np.minimum(S[:, j], f(v) - bias)
        # сглаживание счёта по соседям: границы цветов становятся плавными кривыми
        e = np.vstack([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
        e = np.vstack([e, e[:, ::-1]])
        deg = np.bincount(e[:, 0], minlength=len(v)).astype(float)[:, None]
        for _ in range(self.smooth * 2):
            acc = np.zeros_like(S)
            np.add.at(acc, e[:, 0], S[e[:, 1]])
            S = 0.5 * S + 0.5 * acc / np.maximum(deg, 1)
        lab = np.argmin(S, 1)
        # нормали из marching cubes смотрят внутрь поля (градиент), разворачиваем наружу
        n = -normals
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        fl = lab[faces]
        same = (fl[:, 0] == fl[:, 1]) & (fl[:, 1] == fl[:, 2])
        acc_v = {j: [] for j in range(len(names))}
        acc_n = {j: [] for j in range(len(names))}
        acc_i = {j: [] for j in range(len(names))}
        acc_c = {j: 0 for j in range(len(names))}
        # целые треугольники одной области
        for j in range(len(names)):
            sel = faces[same & (fl[:, 0] == j)]
            if len(sel) == 0:
                continue
            used, inv = np.unique(sel, return_inverse=True)
            acc_v[j].append(v[used]); acc_n[j].append(n[used]); acc_i[j].append(inv.reshape(-1, 3) + acc_c[j]); acc_c[j] += len(used)
        # смешанные треугольники режутся по линиям равенства счёта (как в marching triangles)
        for f3 in faces[~same]:
            present = sorted(set(lab[f3]))
            P = [(v[k], n[k], S[k, present]) for k in f3]
            for ai, j in enumerate(present):
                poly = P
                for bi in range(len(present)):
                    if bi == ai or len(poly) < 3:
                        continue
                    out = []
                    for q in range(len(poly)):
                        A, B = poly[q], poly[(q + 1) % len(poly)]
                        ga, gb = A[2][ai] - A[2][bi], B[2][ai] - B[2][bi]
                        if ga <= 0:
                            out.append(A)
                        if (ga <= 0) != (gb <= 0):
                            t = ga / (ga - gb)
                            out.append((A[0] + (B[0] - A[0]) * t, A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t))
                    poly = out
                if len(poly) < 3:
                    continue
                pv = np.array([q[0] for q in poly]); pn = np.array([q[1] for q in poly])
                pn /= np.maximum(np.linalg.norm(pn, axis=1, keepdims=True), 1e-9)
                base = acc_c[j]
                tri = np.array([[base, base + q, base + q + 1] for q in range(1, len(poly) - 1)])
                acc_v[j].append(pv); acc_n[j].append(pn); acc_i[j].append(tri); acc_c[j] += len(poly)
        out = {}
        for j, name in enumerate(names):
            if not acc_v[j]:
                continue
            V, N, I = np.vstack(acc_v[j]), np.vstack(acc_n[j]), np.vstack(acc_i[j])
            # дробные кусочки: склеить совпадающие вершины, выбросить вырожденные треугольники
            key = np.round(V / 1e-5).astype(np.int64)
            _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
            inv = inv.reshape(-1)
            I = inv[I]
            ok = (I[:, 0] != I[:, 1]) & (I[:, 1] != I[:, 2]) & (I[:, 0] != I[:, 2])
            I = I[ok]
            if len(I) == 0:
                continue
            out[name] = Mesh(V[first], N[first], I[:, ::-1])
        for name, m in self.extra:
            out[name] = out[name].add(m) if name in out else m
        return out


# ---------------------------------------------------------------- простые меши для деталей
def uv_sphere(c, r, R=None, seg=14, ring=10):
    vs, ns, idx = [], [], []
    for i in range(ring + 1):
        th = np.pi * i / ring
        for j in range(seg):
            ph = 2 * np.pi * j / seg
            nv = np.array([np.sin(th) * np.cos(ph), np.cos(th), np.sin(th) * np.sin(ph)])
            ns.append(nv)
            vs.append(nv * np.asarray(r))
    vs, ns = np.array(vs), np.array(ns)
    ns = ns / np.asarray(r)
    ns /= np.linalg.norm(ns, axis=1, keepdims=True)
    if R is not None:
        vs, ns = vs @ R.T, ns @ R.T
    for i in range(ring):
        for j in range(seg):
            a, b = i * seg + j, i * seg + (j + 1) % seg
            c2, d = a + seg, b + seg
            idx += [[a, c2, b], [b, c2, d]]
    return Mesh(vs + np.asarray(c), ns, np.array(idx))


def torus(c, R0, r, R=None, seg=40, ring=10):
    vs, ns, idx = [], [], []
    for i in range(seg):
        u = 2 * np.pi * i / seg
        cu, su = np.cos(u), np.sin(u)
        for j in range(ring):
            w = 2 * np.pi * j / ring
            n = np.array([cu * np.cos(w), np.sin(w), su * np.cos(w)])
            vs.append(np.array([cu * R0, 0, su * R0]) + n * r)
            ns.append(n)
    vs, ns = np.array(vs), np.array(ns)
    if R is not None:
        vs, ns = vs @ R.T, ns @ R.T
    for i in range(seg):
        for j in range(ring):
            a, b = i * ring + j, i * ring + (j + 1) % ring
            c2, d = ((i + 1) % seg) * ring + j, ((i + 1) % seg) * ring + (j + 1) % ring
            idx += [[a, b, c2], [b, d, c2]]
    return Mesh(vs + np.asarray(c), ns, np.array(idx))


def gem(c, s, R=None, stretch=1.4):
    """Кристалл-октаэдр с плоскими гранями."""
    P = np.array([[0, stretch, 0], [0, -stretch * 0.8, 0], [1, 0, 0], [-1, 0, 0], [0, 0, 1], [0, 0, -1]]) * s
    F = [[0, 2, 4], [0, 4, 3], [0, 3, 5], [0, 5, 2], [1, 4, 2], [1, 3, 4], [1, 5, 3], [1, 2, 5]]
    vs, ns, idx = [], [], []
    for f in F:
        a, b, cc = P[f[0]], P[f[1]], P[f[2]]
        n = np.cross(b - a, cc - a)
        n /= np.linalg.norm(n)
        base = len(vs)
        vs += [a, b, cc]
        ns += [n, n, n]
        idx.append([base, base + 2, base + 1])
    vs, ns = np.array(vs), np.array(ns)
    if R is not None:
        vs, ns = vs @ R.T, ns @ R.T
    return Mesh(vs + np.asarray(c), ns, np.array(idx))


def add_eyes(cr, x, y, z, rx, ry, tilt=0.0, pupil=True, shine=True):
    for s in (-1, 1):
        R = rot(0, s * 0.35, s * tilt)
        cr.extra.append(("Eye", uv_sphere((s * x, y, z), (rx, ry, rx * 0.55), R)))
        if pupil:
            cr.extra.append(("Pupil", uv_sphere((s * x * 1.02, y - ry * 0.12, z - rx * 0.42), (rx * 0.45, ry * 0.55, rx * 0.25), R)))
        if shine:
            cr.extra.append(("Shine", uv_sphere((s * x - rx * 0.25 * s, y + ry * 0.4, z - rx * 0.5), (rx * 0.22, rx * 0.22, rx * 0.12), R)))


def add_halo(cr, y, radius, z=0.0, tilt=0.15, gem_front=True):
    R = rot(tilt, 0, 0)
    cr.extra.append(("Halo", torus((0, y, z), radius, 0.045, R)))
    if gem_front:
        cr.extra.append(("Gem", gem((0, y + 0.02, z - radius - 0.02), 0.13, rot(0.2, 0.6, 0), 1.3)))


def add_crystals(cr, pts, s=0.11):
    for i, p in enumerate(pts):
        cr.extra.append(("Crystal%d" % (i + 1), gem(p, s * (0.8 + 0.25 * (i % 3)), rot(i * 0.7, i * 1.3, i * 0.4), 1.35)))


# ---------------------------------------------------------------- питомцы
def fox():
    """Марс: лисёнок-чиби с огромным хвостом, светящимися глазами и кольцом с кристаллом."""
    c = Creature()
    # голова: широкая, с щёчками-пухом
    c.ell("Fur", (0, 1.55, -0.15), (0.62, 0.55, 0.55), k=0.1)
    for s in (-1, 1):
        c.ell("Cheek", (s * 0.42, 1.38, -0.32), (0.26, 0.2, 0.22), rot(0, 0, s * 0.5), k=0.12, bias=0.01)
        c.cone("Cheek", (s * 0.5, 1.33, -0.3), (s * 0.78, 1.2, -0.25), 0.14, 0.02, k=0.1)
    c.ell("Muzzle", (0, 1.38, -0.62), (0.22, 0.16, 0.18), k=0.12, bias=0.02)
    # тёмные пятна вокруг глаз и на лбу
    for s in (-1, 1):
        c.ell("Mask", (s * 0.25, 1.58, -0.56), (0.17, 0.2, 0.12), rot(0, 0, s * -0.3), k=0.06, bias=0.012)
    c.ell("Mask", (0, 1.98, -0.38), (0.09, 0.07, 0.06), k=0.05, bias=0.01)
    # уши: большие, острые, слегка наружу
    for s in (-1, 1):
        c.cone("Ear", (s * 0.34, 1.9, -0.12), (s * 0.66, 2.75, 0.02), 0.27, 0.025, k=0.08)
        c.cone("EarIn", (s * 0.36, 1.96, -0.22), (s * 0.62, 2.6, -0.07), 0.17, 0.02, k=0.04, bias=0.03)
        c.cone("Ear", (s * 0.62, 2.55, 0.0), (s * 0.7, 2.85, 0.05), 0.07, 0.01, k=0.04)
    # тело: округлое, с пушистой грудкой
    c.ell("Fur", (0, 0.88, 0.2), (0.42, 0.4, 0.52), k=0.18)
    c.ell("Chest", (0, 1.0, -0.2), (0.3, 0.32, 0.22), k=0.14, bias=0.02)
    for i, (x, y) in enumerate([(-0.16, 0.82), (0.0, 0.76), (0.16, 0.82), (-0.08, 0.92), (0.08, 0.92)]):
        c.cone("Chest", (x, y + 0.12, -0.28), (x * 1.1, y - 0.08, -0.36), 0.1, 0.02, k=0.06, bias=0.015)
    # лапы: тёмные «чулочки» и светлые подушечки
    for s in (-1, 1):
        c.cone("Leg", (s * 0.2, 0.75, -0.1), (s * 0.22, 0.25, -0.2), 0.14, 0.11, k=0.08)
        c.ell("Paw", (s * 0.22, 0.2, -0.24), (0.12, 0.08, 0.14), k=0.05, bias=0.01)
        c.cone("Leg", (s * 0.24, 0.75, 0.45), (s * 0.26, 0.28, 0.5), 0.16, 0.11, k=0.08)
        c.ell("Paw", (s * 0.26, 0.22, 0.52), (0.12, 0.08, 0.14), k=0.05, bias=0.01)
    # хвост: огромный, изогнутый вверх, со светлым кончиком
    pts = [(0, 0.85, 0.6), (0.08, 0.95, 0.95), (0.18, 1.2, 1.25), (0.25, 1.55, 1.42), (0.28, 1.9, 1.42), (0.25, 2.15, 1.28)]
    rad = [0.18, 0.3, 0.42, 0.46, 0.4, 0.26]
    for i in range(len(pts) - 1):
        c.cone("Tail", pts[i], pts[i + 1], rad[i], rad[i + 1], k=0.12)
    c.cone("Tail", pts[1], (0.14, 1.05, 1.25), 0.25, 0.22, k=0.12)
    c.cone("TailStripe", (0.16, 1.2, 1.2), (0.25, 1.5, 1.45), 0.36, 0.4, k=0.05, bias=0.035)
    c.ell("TailTip", (0.25, 2.12, 1.3), (0.24, 0.2, 0.24), k=0.08, bias=0.05)
    # глаза, нос, кольцо и кристаллы
    add_eyes(c, 0.25, 1.6, -0.63, 0.13, 0.16, tilt=0.2)
    c.extra.append(("Nose", uv_sphere((0, 1.45, -0.8), (0.06, 0.045, 0.05))))
    add_halo(c, 1.12, 0.66, z=0.0, tilt=0.2)
    add_crystals(c, [(-0.9, 1.9, 0.3), (0.95, 1.4, -0.4), (-0.75, 0.9, -0.6), (0.85, 2.3, 0.7)])
    return c


def bunny():
    """Луна: кролик-чиби с длинными ушами, пушистой грудкой и голубым свечением."""
    c = Creature()
    c.ell("Fur", (0, 1.45, -0.1), (0.58, 0.54, 0.54), k=0.1)
    for s in (-1, 1):
        c.ell("Cheek", (s * 0.36, 1.28, -0.34), (0.22, 0.18, 0.2), k=0.12, bias=0.01)
        c.ell("Blush", (s * 0.34, 1.3, -0.5), (0.1, 0.06, 0.04), k=0.04, bias=0.02)
    c.ell("Muzzle", (0, 1.3, -0.56), (0.17, 0.12, 0.13), k=0.1, bias=0.02)
    # уши: длинные, чуть врозь, кончики назад
    for s in (-1, 1):
        c.cone("Ear", (s * 0.2, 1.85, -0.05), (s * 0.34, 2.55, 0.08), 0.17, 0.15, k=0.08)
        c.cone("Ear", (s * 0.34, 2.55, 0.08), (s * 0.4, 2.95, 0.22), 0.15, 0.08, k=0.08)
        c.cone("EarIn", (s * 0.21, 1.95, -0.14), (s * 0.36, 2.7, -0.0), 0.09, 0.07, k=0.03, bias=0.04)
    c.ell("Fur", (0, 0.8, 0.15), (0.42, 0.42, 0.48), k=0.18)
    c.ell("Chest", (0, 0.92, -0.2), (0.28, 0.3, 0.2), k=0.12, bias=0.02)
    for s in (-1, 1):
        c.ell("Paw", (s * 0.2, 0.22, -0.22), (0.15, 0.12, 0.2), k=0.08, bias=0.0)
        c.ell("Fur", (s * 0.3, 0.42, 0.35), (0.22, 0.25, 0.32), k=0.1)
        c.ell("Paw", (s * 0.3, 0.16, 0.25), (0.16, 0.09, 0.28), k=0.06, bias=0.01)
    c.ell("Tail", (0, 0.75, 0.68), (0.24, 0.24, 0.22), k=0.08)
    add_eyes(c, 0.22, 1.5, -0.56, 0.12, 0.15, tilt=0.1)
    c.extra.append(("Nose", uv_sphere((0, 1.36, -0.7), (0.05, 0.04, 0.04))))
    # полумесяц над головой и лунные камни
    c.extra.append(("Halo", torus((0, 3.2, 0.05), 0.32, 0.06, rot(1.35, 0, 0), seg=40)))
    add_crystals(c, [(-0.85, 1.7, 0.2), (0.9, 1.2, -0.3), (-0.7, 0.7, -0.6), (0.75, 2.2, 0.5)], s=0.1)
    return c


def penguin():
    """Европа: пингвин-чиби в короне из ледяных кристаллов."""
    c = Creature()
    c.ell("Fur", (0, 1.0, 0.05), (0.62, 0.78, 0.58), k=0.2)
    c.ell("Fur", (0, 1.72, 0.0), (0.5, 0.46, 0.48), k=0.25)
    c.ell("Belly", (0, 0.95, -0.28), (0.46, 0.6, 0.36), k=0.1, bias=0.02)
    c.ell("Face", (0, 1.7, -0.3), (0.36, 0.28, 0.2), k=0.12, bias=0.05)
    c.ell("Beak", (0, 1.6, -0.55), (0.12, 0.08, 0.16), k=0.04, bias=0.0)
    for s in (-1, 1):
        c.cone("Flipper", (s * 0.55, 1.25, 0.0), (s * 0.82, 0.75, -0.05), 0.15, 0.07, k=0.08)
        c.ell("Foot", (s * 0.22, 0.12, -0.25), (0.17, 0.07, 0.24), k=0.06)
    c.ell("Fur", (0, 0.55, 0.55), (0.18, 0.12, 0.16), k=0.1)
    c.ell("Scarf", (0, 1.38, 0.0), (0.52, 0.12, 0.5), k=0.05, bias=0.03)
    add_eyes(c, 0.18, 1.78, -0.42, 0.1, 0.12, tilt=0.05)
    for i in range(5):
        a = (i - 2) * 0.38
        c.extra.append(("Crown", gem((np.sin(a) * 0.3, 2.22 + (0.12 if i == 2 else 0), -0.05 + np.cos(a) * 0.08), 0.09 if i != 2 else 0.12, rot(0, a, -a * 0.4), 2.2)))
    add_halo(c, 1.38, 0.62, z=0.0, tilt=0.15, gem_front=True)
    add_crystals(c, [(-0.95, 1.9, 0.2), (0.95, 1.3, -0.3), (-0.8, 0.8, -0.5), (0.8, 2.3, 0.4)], s=0.1)
    return c


def salamander():
    """Ио: огненная саламандра-аксолотль со светящимися жабрами и лавовыми пятнами."""
    c = Creature()
    c.ell("Fur", (0, 1.05, -0.45), (0.52, 0.42, 0.46), k=0.12)
    c.ell("Belly", (0, 0.92, -0.72), (0.34, 0.2, 0.18), k=0.1, bias=0.02)
    body = [(0, 0.7, -0.05), (0, 0.65, 0.35), (0, 0.62, 0.7)]
    c.cone("Fur", body[0], body[2], 0.36, 0.3, k=0.2)
    c.ell("Belly", (0, 0.5, 0.25), (0.28, 0.12, 0.42), k=0.1, bias=0.02)
    tail = [(0, 0.62, 0.7), (0.15, 0.62, 1.15), (0.35, 0.72, 1.5), (0.45, 0.95, 1.75)]
    rad = [0.28, 0.2, 0.13, 0.05]
    for i in range(3):
        c.cone("Fur", tail[i], tail[i + 1], rad[i], rad[i + 1], k=0.1)
    c.cone("Fin", (0, 0.85, 0.1), (0.3, 0.95, 1.5), 0.06, 0.03, k=0.08, bias=0.02)
    for s in (-1, 1):
        for z, y in ((-0.05, 0.4), (0.55, 0.42)):
            c.cone("Leg", (s * 0.25, 0.6, z), (s * 0.42, 0.15, z - 0.05), 0.12, 0.08, k=0.08)
            c.ell("Toe", (s * 0.45, 0.1, z - 0.1), (0.11, 0.05, 0.12), k=0.04, bias=0.01)
        for i, (dy, dz) in enumerate(((0.32, 0.0), (0.08, 0.05), (-0.16, 0.08))):
            c.cone("Gill", (s * 0.42, 1.12 + dy * 0.5, -0.35), (s * 0.82, 1.2 + dy, -0.25 + dz), 0.07, 0.04, k=0.06)
            c.ell("Gill", (s * 0.85, 1.2 + dy, -0.24 + dz), (0.09, 0.09, 0.07), k=0.06)
    for i, (x, y, z) in enumerate([(0.0, 0.98, 0.0), (0.2, 0.9, 0.35), (-0.2, 0.88, 0.5), (0.18, 0.82, 0.85), (-0.1, 1.38, -0.4), (0.25, 1.32, -0.25)]):
        c.ell("Spot", (x, y, z), (0.12, 0.06, 0.12), k=0.03, bias=0.035)
    add_eyes(c, 0.26, 1.15, -0.78, 0.11, 0.13, tilt=0.15)
    c.ell("Mouth", (0, 0.92, -0.88), (0.12, 0.02, 0.04), k=0.02, bias=0.02)
    add_halo(c, 0.95, 0.62, z=-0.1, tilt=0.2)
    add_crystals(c, [(-0.95, 1.5, 0.3), (0.95, 1.1, -0.5), (-0.7, 0.6, -0.9), (0.8, 1.9, 0.8)], s=0.1)
    return c


def dragon():
    """Туманность: дракончик-чиби с рожками, крыльями и звёздными пятнами."""
    c = Creature()
    c.ell("Fur", (0, 1.55, -0.2), (0.55, 0.5, 0.52), k=0.1)
    c.ell("Snout", (0, 1.38, -0.62), (0.3, 0.22, 0.26), k=0.15, bias=0.02)
    for s in (-1, 1):
        c.ell("Snout", (s * 0.1, 1.42, -0.86), (0.05, 0.03, 0.03), k=0.02, bias=0.03)
        c.cone("Horn", (s * 0.28, 1.92, -0.1), (s * 0.45, 2.45, 0.25), 0.11, 0.03, k=0.05)
        c.cone("Horn", (s * 0.48, 1.68, -0.0), (s * 0.78, 1.85, 0.2), 0.07, 0.02, k=0.04)
    c.ell("Fur", (0, 0.85, 0.15), (0.45, 0.45, 0.55), k=0.18)
    c.ell("Belly", (0, 0.85, -0.25), (0.3, 0.38, 0.2), k=0.12, bias=0.02)
    for s in (-1, 1):
        c.cone("Leg", (s * 0.24, 0.65, -0.15), (s * 0.26, 0.18, -0.22), 0.14, 0.12, k=0.08)
        c.cone("Leg", (s * 0.28, 0.65, 0.45), (s * 0.3, 0.18, 0.48), 0.17, 0.13, k=0.08)
        c.ell("Claw", (s * 0.26, 0.12, -0.3), (0.12, 0.07, 0.12), k=0.04, bias=0.01)
        c.ell("Claw", (s * 0.3, 0.12, 0.42), (0.13, 0.07, 0.13), k=0.04, bias=0.01)
        # крылья: косточка и перепонка
        c.cone("WingBone", (s * 0.3, 1.15, 0.2), (s * 1.05, 1.75, 0.35), 0.06, 0.04, k=0.05)
        c.cone("WingBone", (s * 1.05, 1.75, 0.35), (s * 1.25, 1.2, 0.5), 0.04, 0.02, k=0.04)
        # перепонка — отдельный гладкий меш: тонкая форма в поле расстояний выходит рваной
        c.extra.append(("Wing", uv_sphere((s * 0.85, 1.35, 0.42), (0.44, 0.36, 0.045), rot(0, s * -0.3, s * 0.45), seg=36, ring=20)))
    tail = [(0, 0.75, 0.6), (0.1, 0.65, 1.0), (0.3, 0.7, 1.35), (0.45, 0.9, 1.6)]
    rad = [0.26, 0.18, 0.12, 0.06]
    for i in range(3):
        c.cone("Fur", tail[i], tail[i + 1], rad[i], rad[i + 1], k=0.1)
    for i in range(4):
        c.cone("Spike", (0, 2.0 - i * 0.28, 0.05 + i * 0.22), (0, 2.12 - i * 0.28, 0.12 + i * 0.22), 0.07, 0.02, k=0.04)
    for i, (x, y, z) in enumerate([(0.3, 1.0, 0.2), (-0.32, 0.95, 0.35), (0.2, 1.25, 0.45), (-0.15, 1.82, -0.45), (0.38, 1.7, -0.25)]):
        c.ell("Star", (x, y, z), (0.07, 0.07, 0.07), k=0.02, bias=0.04)
    add_eyes(c, 0.24, 1.62, -0.58, 0.12, 0.15, tilt=0.25)
    c.extra.append(("TailGem", gem((0.5, 1.0, 1.7), 0.14, rot(0.3, 0.4, 0), 1.5)))
    add_halo(c, 1.15, 0.6, z=0.0, tilt=0.2, gem_front=False)
    add_crystals(c, [(-1.0, 2.0, -0.2), (1.0, 2.1, -0.1), (-0.8, 0.7, -0.6), (0.85, 0.8, 0.9)], s=0.1)
    return c


def phoenix():
    """Ядро: феникс-чиби: золотой, с хохолком, огненными перьями и кольцом."""
    c = Creature()
    c.ell("Fur", (0, 1.15, 0.05), (0.52, 0.55, 0.58), k=0.2)
    c.ell("Fur", (0, 1.72, -0.15), (0.45, 0.42, 0.42), k=0.22)
    c.ell("Chest", (0, 1.05, -0.36), (0.36, 0.42, 0.2), k=0.12, bias=0.02)
    c.cone("Beak", (0, 1.66, -0.52), (0, 1.58, -0.78), 0.1, 0.02, k=0.04)
    for i, (dy, dz, h) in enumerate(((0.0, 0.0, 0.62), (-0.05, 0.16, 0.55), (-0.1, 0.32, 0.45))):
        c.cone("Crest", (0, 2.0 + dy, -0.12 + dz), (0, 2.0 + dy + h, 0.05 + dz + 0.25), 0.09, 0.02, k=0.06)
    for s in (-1, 1):
        for i in range(4):
            c.cone("Wing" if i < 2 else "WingTip", (s * 0.45, 1.3 - i * 0.06, 0.0 + i * 0.1), (s * (0.95 + i * 0.12), 1.45 - i * 0.25, 0.25 + i * 0.15), 0.13 - i * 0.015, 0.03, k=0.06)
        c.ell("Foot", (s * 0.2, 0.55, -0.05), (0.08, 0.06, 0.12), k=0.08)
        c.cone("Foot", (s * 0.2, 0.62, 0.0), (s * 0.2, 0.85, 0.05), 0.05, 0.05, k=0.06)
    for i, (dx, l) in enumerate(((-0.22, 1.3), (0.0, 1.55), (0.22, 1.3))):
        c.cone("TailFeather", (dx * 0.4, 0.95, 0.5), (dx * 1.6, 0.6, 0.6 + l), 0.12, 0.05, k=0.06)
        c.ell("TailTip", (dx * 1.6, 0.6, 0.62 + l), (0.13, 0.06, 0.2), k=0.06)
    add_eyes(c, 0.18, 1.78, -0.4, 0.1, 0.13, tilt=0.15)
    add_halo(c, 2.75, 0.4, z=0.05, tilt=0.35, gem_front=False)
    add_crystals(c, [(-0.95, 1.8, 0.3), (0.95, 1.6, -0.2), (-0.8, 0.8, -0.5), (0.85, 2.3, 0.6)], s=0.1)
    return c


PETS = {"bunny": bunny, "rover": fox, "penguin": penguin, "salamander": salamander, "dragon": dragon, "phoenix": phoenix}

# цвета и материалы для превью (в игре те же значения задаёт Config/PetLook.luau)
LOOK = {
    "bunny": {
        "Fur": ((226, 226, 244), 0), "Cheek": ((232, 232, 248), 0), "Blush": ((255, 170, 200), 0.2), "Muzzle": ((250, 248, 255), 0),
        "Ear": ((214, 214, 238), 0), "EarIn": ((150, 190, 255), 0.45), "Chest": ((255, 255, 255), 0), "Paw": ((246, 244, 255), 0),
        "Tail": ((255, 255, 255), 0), "Eye": ((120, 200, 255), 0.9), "Pupil": ((20, 26, 50), 0), "Shine": ((255, 255, 255), 1.0),
        "Nose": ((255, 150, 190), 0), "Halo": ((200, 225, 255), 1.0), "Crystal": ((180, 190, 230), 0.4),
    },
    "penguin": {
        "Fur": ((34, 44, 78), 0), "Belly": ((245, 250, 255), 0), "Face": ((245, 250, 255), 0), "Beak": ((255, 170, 70), 0), "Flipper": ((30, 38, 70), 0),
        "Foot": ((255, 160, 70), 0), "Scarf": ((90, 200, 255), 0.25), "Eye": ((110, 230, 255), 0.9), "Pupil": ((10, 20, 40), 0), "Shine": ((255, 255, 255), 1.0),
        "Crown": ((170, 230, 255), 0.6), "Halo": ((140, 220, 255), 1.0), "Gem": ((120, 210, 255), 0.7), "Crystal": ((170, 225, 255), 0.5),
    },
    "salamander": {
        "Fur": ((170, 40, 30), 0), "Belly": ((255, 170, 90), 0), "Fin": ((255, 110, 50), 0.4), "Leg": ((150, 35, 28), 0), "Toe": ((255, 160, 90), 0),
        "Gill": ((255, 120, 50), 0.75), "Spot": ((255, 190, 60), 0.85), "Mouth": ((60, 12, 10), 0), "Eye": ((255, 220, 90), 0.9), "Pupil": ((40, 10, 6), 0),
        "Shine": ((255, 255, 255), 1.0), "Halo": ((255, 150, 60), 1.0), "Gem": ((255, 90, 40), 0.7), "Crystal": ((255, 110, 50), 0.6),
    },
    "dragon": {
        "Fur": ((120, 70, 210), 0), "Snout": ((150, 100, 230), 0), "Horn": ((255, 230, 180), 0), "Belly": ((210, 180, 255), 0), "Leg": ((100, 56, 190), 0),
        "Claw": ((240, 220, 255), 0), "WingBone": ((90, 50, 170), 0), "Wing": ((180, 120, 255), 0.35), "Spike": ((120, 220, 255), 0.6),
        "Star": ((150, 230, 255), 0.9), "Eye": ((255, 225, 120), 0.9), "Pupil": ((30, 14, 50), 0), "Shine": ((255, 255, 255), 1.0),
        "TailGem": ((120, 220, 255), 0.8), "Halo": ((190, 140, 255), 1.0), "Crystal": ((170, 120, 255), 0.55),
    },
    "phoenix": {
        "Fur": ((255, 175, 60), 0), "Chest": ((255, 230, 150), 0.25), "Beak": ((255, 240, 210), 0), "Crest": ((255, 100, 40), 0.7), "Wing": ((255, 150, 50), 0.2),
        "WingTip": ((255, 80, 40), 0.7), "Foot": ((230, 140, 60), 0), "TailFeather": ((255, 120, 40), 0.6), "TailTip": ((255, 230, 120), 0.9),
        "Eye": ((255, 255, 210), 0.9), "Pupil": ((60, 20, 6), 0), "Shine": ((255, 255, 255), 1.0), "Halo": ((255, 210, 100), 1.0), "Crystal": ((255, 160, 60), 0.6),
    },
    "rover": {
        "Fur": ((205, 62, 45), 0), "Cheek": ((210, 70, 50), 0), "Muzzle": ((250, 225, 205), 0), "Mask": ((105, 26, 32), 0),
        "Ear": ((150, 38, 38), 0), "EarIn": ((255, 150, 95), 0.3), "Chest": ((252, 228, 210), 0), "Leg": ((110, 30, 34), 0),
        "Paw": ((250, 215, 190), 0), "Tail": ((200, 60, 44), 0), "TailStripe": ((120, 30, 36), 0), "TailTip": ((255, 140, 80), 0.35),
        "Eye": ((255, 165, 70), 0.9), "Pupil": ((50, 14, 14), 0), "Shine": ((255, 255, 255), 1.0), "Nose": ((50, 18, 20), 0),
        "Halo": ((255, 175, 90), 1.0), "Gem": ((235, 80, 55), 0.7), "Crystal": ((225, 75, 55), 0.55),
    },
}


def look_of(pet, region):
    L = LOOK[pet]
    key = region.rstrip("0123456789")
    return L.get(region) or L.get(key) or ((200, 200, 200), 0)


def preview(pet, parts, path):
    layers = []
    for region, m in parts.items():
        col, emi = look_of(pet, region)
        layers.append((m, dict(color=np.array(col) / 255.0, spec=0.25 if emi == 0 else 0.0, shin=24, emit=emi)))
    ims = [render.render(layers, size=420, ss=2, cam_dir=d) for d in [(-0.55, 0.3, -1.0), (0.9, 0.25, -0.35), (0.2, 0.35, 1.0)]]
    from PIL import Image
    sheet = Image.new("RGB", (420 * 3, 420))
    for i, im in enumerate(ims):
        sheet.paste(im, (420 * i, 0))
    sheet.save(path)


if __name__ == "__main__":
    want = sys.argv[1:] or list(PETS)
    all_meshes = []
    for pet in PETS:
        parts = PETS[pet]().build()
        tris = sum(len(m.i) for m in parts.values())
        print(pet, "областей", len(parts), "треугольников", tris, flush=True)
        if pet in want:
            preview(pet, parts, os.path.join(OUT, pet + ".png"))
        for region, m in parts.items():
            col, _ = look_of(pet, region)
            all_meshes.append(dict(name=f"{pet}__{region}", v=m.v, n=m.n, i=m.i, color=(col[0] / 255, col[1] / 255, col[2] / 255, 1)))
    write_glb(os.path.join(OUT, "pets.glb"), all_meshes)
    print("ok", len(all_meshes))
