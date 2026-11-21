"""Геометрия для процедурных растений: меши из треугольников с гладкими нормалями.
Оси как в Roblox: Y вверх, единица = 1 стад."""
import numpy as np

TAU = np.pi * 2


class Mesh:
    def __init__(self, v=None, n=None, i=None):
        self.v = np.zeros((0, 3)) if v is None else np.asarray(v, dtype=np.float64)
        self.n = np.zeros((0, 3)) if n is None else np.asarray(n, dtype=np.float64)
        self.i = np.zeros((0, 3), dtype=np.int64) if i is None else np.asarray(i, dtype=np.int64)

    def add(self, o):
        if o is None or len(o.v) == 0:
            return self
        off = len(self.v)
        self.v = np.vstack([self.v, o.v])
        self.n = np.vstack([self.n, o.n])
        self.i = np.vstack([self.i, o.i + off])
        return self

    def copy(self):
        return Mesh(self.v.copy(), self.n.copy(), self.i.copy())

    def xform(self, M=None, t=(0, 0, 0), s=1.0):
        """Применяет матрицу 3x3 (или None), затем масштаб и сдвиг. Нормали пересчитываются обратной транспонированной."""
        v = self.v
        n = self.n
        if M is not None:
            M = np.asarray(M, dtype=np.float64)
            v = v @ M.T
            try:
                Nm = np.linalg.inv(M).T
            except np.linalg.LinAlgError:
                Nm = M
            n = n @ Nm.T
            ln = np.linalg.norm(n, axis=1, keepdims=True)
            n = n / np.maximum(ln, 1e-9)
        s = np.asarray(s, dtype=np.float64)
        v = v * s
        if s.ndim > 0:  # неравномерный масштаб
            Nm = np.diag(1 / np.where(np.abs(s) < 1e-9, 1e-9, s))
            n = n @ Nm.T
            n = n / np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        v = v + np.asarray(t, dtype=np.float64)
        return Mesh(v, n, self.i.copy())

    def fix_winding(self):
        """Переворачивает треугольники, у которых геометрическая нормаль смотрит против нормалей вершин."""
        a, b, c = self.v[self.i[:, 0]], self.v[self.i[:, 1]], self.v[self.i[:, 2]]
        g = np.cross(b - a, c - a)
        avg = self.n[self.i[:, 0]] + self.n[self.i[:, 1]] + self.n[self.i[:, 2]]
        flip = (g * avg).sum(1) < 0
        self.i[flip] = self.i[flip][:, [0, 2, 1]]
        # вырожденные треугольники убираем
        area = np.linalg.norm(g, axis=1)
        self.i = self.i[area > 1e-10]
        return self

    def tris(self):
        return len(self.i)


def merge(*meshes):
    m = Mesh()
    for x in meshes:
        m.add(x)
    return m


# ---------------------------------------------------------------- повороты
def rotx(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def roty(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def rotz(a):
    c, s = np.cos(a), np.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def unit(v):
    v = np.asarray(v, dtype=np.float64)
    return v / max(np.linalg.norm(v), 1e-12)


def frame(axis, up=(0, 1, 0)):
    """Столбцы: lateral (X), axis (Y), normal (Z) — правая система, axis задан."""
    y = unit(axis)
    up = np.asarray(up, dtype=np.float64)
    x = np.cross(y, up)
    if np.linalg.norm(x) < 1e-6:
        x = np.cross(y, (1, 0, 0))
    x = unit(x)
    z = np.cross(x, y)
    return np.stack([x, y, z], axis=1)


# ---------------------------------------------------------------- шум
def _hash(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 2147483647 + seed * 1274126177) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h ^= h >> 16
    return (h & 0xFFFFFF) / float(0xFFFFFF)


def vnoise(p, seed=0):
    p = np.asarray(p, dtype=np.float64)
    x, y, z = p[..., 0], p[..., 1], p[..., 2]
    ix, iy, iz = np.floor(x).astype(np.int64), np.floor(y).astype(np.int64), np.floor(z).astype(np.int64)
    fx, fy, fz = x - ix, y - iy, z - iz
    fx, fy, fz = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy), fz * fz * (3 - 2 * fz)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (fx if dx else 1 - fx) * (fy if dy else 1 - fy) * (fz if dz else 1 - fz)
                out = out + w * _hash(ix + dx, iy + dy, iz + dz, seed)
    return out


def displace(m, amp, freq, seed=0, octaves=2):
    """Бугристость: смещает вершины вдоль нормали шумом (шов не рвётся, шум по позиции)."""
    d = 0
    a = 1.0
    for o in range(octaves):
        d = d + a * (vnoise(m.v * freq * (2 ** o), seed + o) - 0.5)
        a *= 0.5
    v = m.v + m.n * (d * amp)[:, None]
    out = Mesh(v, m.n.copy(), m.i.copy())
    return recompute_normals(out)


def recompute_normals(m):
    n = np.zeros_like(m.v)
    a, b, c = m.v[m.i[:, 0]], m.v[m.i[:, 1]], m.v[m.i[:, 2]]
    g = np.cross(b - a, c - a)
    for k in range(3):
        np.add.at(n, m.i[:, k], g)
    ln = np.linalg.norm(n, axis=1, keepdims=True)
    # там, где нет геометрических нормалей, оставляем прежние
    n = np.where(ln > 1e-12, n / np.maximum(ln, 1e-12), m.n)
    # знак по прежним нормалям
    flip = (n * m.n).sum(1) < 0
    n[flip] *= -1
    return Mesh(m.v, n, m.i)


# ---------------------------------------------------------------- поверхности вращения
def lathe(profile, seg=28, closed_bottom=False, closed_top=False):
    """profile: список (радиус, высота) снизу вверх. Нормали гладкие по профилю."""
    P = np.asarray(profile, dtype=np.float64)
    k = len(P)
    t = np.gradient(P, axis=0)
    nr = t[:, 1]
    ny = -t[:, 0]
    ln = np.maximum(np.hypot(nr, ny), 1e-12)
    nr, ny = nr / ln, ny / ln
    ang = np.linspace(0, TAU, seg + 1)
    ca, sa = np.cos(ang), np.sin(ang)
    V = np.zeros((k, seg + 1, 3))
    N = np.zeros((k, seg + 1, 3))
    V[:, :, 0] = P[:, 0:1] * ca
    V[:, :, 1] = P[:, 1:2]
    V[:, :, 2] = P[:, 0:1] * sa
    N[:, :, 0] = nr[:, None] * ca
    N[:, :, 1] = ny[:, None]
    N[:, :, 2] = nr[:, None] * sa
    idx = []
    for j in range(k - 1):
        for i in range(seg):
            a = j * (seg + 1) + i
            b = a + 1
            c = a + seg + 1
            d = c + 1
            idx += [[a, c, b], [b, c, d]]
    m = Mesh(V.reshape(-1, 3), N.reshape(-1, 3), idx)
    return m.fix_winding()


def lathe_fn(radius_fn, heights, seg=32, profile_smooth=True):
    """Поверхность вращения, где радиус зависит и от угла: radius_fn(theta, y) -> r. Для рёбер тыквы и кактуса."""
    H = np.asarray(heights, dtype=np.float64)
    ang = np.linspace(0, TAU, seg + 1)
    V = np.zeros((len(H), seg + 1, 3))
    for j, y in enumerate(H):
        r = radius_fn(ang, y)
        V[j, :, 0] = r * np.cos(ang)
        V[j, :, 1] = y
        V[j, :, 2] = r * np.sin(ang)
    idx = []
    for j in range(len(H) - 1):
        for i in range(seg):
            a = j * (seg + 1) + i
            idx += [[a, a + seg + 1, a + 1], [a + 1, a + seg + 1, a + seg + 2]]
    m = Mesh(V.reshape(-1, 3), np.zeros((V.size // 3, 3)), idx)
    # нормали из геометрии, ориентированные наружу от оси
    m = recompute_normals(_with_outward(m))
    return m.fix_winding()


def _with_outward(m):
    out = m.v.copy()
    out[:, 1] = 0
    n = out / np.maximum(np.linalg.norm(out, axis=1, keepdims=True), 1e-9)
    return Mesh(m.v, n, m.i)


def sphere(radius=1.0, seg=20, rings=12):
    prof = [(radius * np.sin(t), -radius * np.cos(t)) for t in np.linspace(0, np.pi, rings + 1)]
    prof[0] = (1e-4, prof[0][1])
    prof[-1] = (1e-4, prof[-1][1])
    return lathe(prof, seg)


def ellipsoid(radii, center=(0, 0, 0), M=None, seg=20, rings=12):
    s = sphere(1.0, seg, rings)
    return s.xform(M, center, np.asarray(radii, dtype=np.float64))


def blob(radii, center=(0, 0, 0), M=None, amp=0.08, freq=1.6, seed=0, seg=22, rings=14):
    s = displace(sphere(1.0, seg, rings), amp, freq, seed)
    return s.xform(M, center, np.asarray(radii, dtype=np.float64))


def cone(radius, height, seg=14, base=(0, 0, 0), M=None, round_tip=0.0):
    prof = [(1e-4, 0), (radius, 0), (radius * 0.0 + max(round_tip, 1e-4), height)]
    m = lathe(prof, seg)
    return m.xform(M, base)


# ---------------------------------------------------------------- трубки вдоль кривой
def curve(points, n=24):
    """Катмулл-Ром через контрольные точки -> n точек."""
    P = np.asarray(points, dtype=np.float64)
    if len(P) < 3:
        t = np.linspace(0, 1, n)[:, None]
        return P[0] * (1 - t) + P[-1] * t
    P2 = np.vstack([P[0] * 2 - P[1], P, P[-1] * 2 - P[-2]])
    out = []
    segs = len(P) - 1
    for k in range(n):
        u = k / (n - 1) * segs
        s = min(int(u), segs - 1)
        f = u - s
        p0, p1, p2, p3 = P2[s], P2[s + 1], P2[s + 2], P2[s + 3]
        out.append(0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3))
    return np.array(out)


def tube(points, radii, sides=8, caps=True, n=None):
    """Труба по ломаной/кривой с переменным радиусом (радиусы — массив длины len(points) или функция t->r)."""
    P = np.asarray(points, dtype=np.float64)
    k = len(P)
    R = np.asarray(radii(np.linspace(0, 1, k)) if callable(radii) else radii, dtype=np.float64)
    if R.ndim == 0 or len(R) != k:
        R = np.interp(np.linspace(0, 1, k), np.linspace(0, 1, len(np.atleast_1d(R))), np.atleast_1d(R))
    T = np.gradient(P, axis=0)
    T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
    # параллельный перенос системы координат
    up = np.array([0, 1, 0.0]) if abs(T[0][1]) < 0.9 else np.array([1, 0, 0.0])
    N0 = unit(np.cross(T[0], up))
    Ns, Bs = [], []
    for i in range(k):
        if i > 0:
            axis = np.cross(T[i - 1], T[i])
            la = np.linalg.norm(axis)
            if la > 1e-9:
                axis = axis / la
                ang = np.arctan2(la, np.dot(T[i - 1], T[i]))
                c, s = np.cos(ang), np.sin(ang)
                N0 = N0 * c + np.cross(axis, N0) * s + axis * np.dot(axis, N0) * (1 - c)
        N0 = unit(N0 - T[i] * np.dot(N0, T[i]))
        Ns.append(N0)
        Bs.append(np.cross(T[i], N0))
    Ns, Bs = np.array(Ns), np.array(Bs)
    ang = np.linspace(0, TAU, sides + 1)
    V = np.zeros((k, sides + 1, 3))
    Nn = np.zeros((k, sides + 1, 3))
    for a_i, a in enumerate(ang):
        d = Ns * np.cos(a) + Bs * np.sin(a)
        V[:, a_i] = P + d * R[:, None]
        Nn[:, a_i] = d
    idx = []
    for j in range(k - 1):
        for i in range(sides):
            a = j * (sides + 1) + i
            idx += [[a, a + sides + 1, a + 1], [a + 1, a + sides + 1, a + sides + 2]]
    m = Mesh(V.reshape(-1, 3), Nn.reshape(-1, 3), idx)
    if caps:
        for end, sgn in ((0, -1), (k - 1, 1)):
            if R[end] < 1e-3:
                continue
            ring = V[end]
            c = P[end]
            base = len(m.v)
            m.v = np.vstack([m.v, c[None], ring])
            nn = np.tile(T[end] * sgn, (len(ring) + 1, 1))
            m.n = np.vstack([m.n, nn])
            for i in range(sides):
                m.i = np.vstack([m.i, [[base, base + 1 + i, base + 2 + i]]])
    return m.fix_winding()


# ---------------------------------------------------------------- листья и лепестки (двусторонние листы)
def sheet(fn, nu=10, nv=6, thick=0.025):
    """fn(u, v) -> точка; u в [0,1], v в [-1,1]. Лист с двумя сторонами и небольшой толщиной."""
    us = np.linspace(0, 1, nu + 1)
    vs = np.linspace(-1, 1, nv + 1)
    U, Vv = np.meshgrid(us, vs, indexing="ij")
    pts = np.zeros((nu + 1, nv + 1, 3))
    for a in range(nu + 1):
        for b in range(nv + 1):
            pts[a, b] = fn(us[a], vs[b])
    du = np.gradient(pts, axis=0)
    dv = np.gradient(pts, axis=1)
    nrm = np.cross(du, dv)
    ln = np.linalg.norm(nrm, axis=2, keepdims=True)
    nrm = nrm / np.maximum(ln, 1e-12)
    # на кончике нормаль вырождается: берём соседнюю
    for a in range(nu + 1):
        if np.any(ln[a, :, 0] < 1e-9):
            nrm[a] = nrm[max(a - 1, 0)] if a > 0 else nrm[min(a + 1, nu)]
    idx = []
    W = nv + 1
    for a in range(nu):
        for b in range(nv):
            i0 = a * W + b
            idx += [[i0, i0 + W, i0 + 1], [i0 + 1, i0 + W, i0 + W + 1]]
    front = Mesh((pts + nrm * thick / 2).reshape(-1, 3), nrm.reshape(-1, 3), idx).fix_winding()
    back = Mesh((pts - nrm * thick / 2).reshape(-1, 3), (-nrm).reshape(-1, 3), idx).fix_winding()
    return merge(front, back)


def leaf(base, axis, length, width, bend=0.5, fold=0.25, up=(0, 1, 0), droop=0.0, tipshape=0.8, twist=0.0, nu=10, nv=4, thick=0.03, rib=0.0):
    """Лист от точки base в направлении axis. bend — изгиб (радианы), fold — V-складка по средней жилке."""
    Fm = frame(axis, up)

    def f(u, v):
        phi = bend * (u ** 1.4) + droop * u * u
        # осевая кривая в плоскости (ось, нормаль): интегрируем угол
        s = np.linspace(0, u, 9)
        ph = bend * (s ** 1.4) + droop * s * s
        ax = np.trapezoid(np.cos(ph), s) * length
        nz = np.trapezoid(np.sin(ph), s) * length
        w = width * (np.sin(np.pi * min(1, u ** tipshape)) ** 0.85) * (1 - 0.15 * u) + width * 0.04 * (1 - u)
        x = v * w
        z = fold * abs(v) * w - twist * v * u * width
        return Fm @ np.array([x, ax, nz + z]) + base

    return sheet(f, nu, nv, thick)


def petal(base, axis, length, width, cup=0.5, curl=0.3, up=(0, 1, 0), nu=10, nv=6, thick=0.025, tip=0.7):
    """Лепесток: узкое основание, широкая середина, заострённый конец; чашеобразный изгиб поперёк и загиб к концу."""
    Fm = frame(axis, up)

    def f(u, v):
        s = np.linspace(0, u, 9)
        ph = curl * (s ** 2)
        ax = np.trapezoid(np.cos(ph), s) * length
        nz = np.trapezoid(np.sin(ph), s) * length
        w = width * (0.3 + 0.7 * np.sin(min(u * 1.2, 1.0) * np.pi * 0.5)) * max(0.0, 1 - u ** 4) ** (0.55 + 0.5 * tip)
        x = v * w
        z = cup * (v * v) * w
        return Fm @ np.array([x, ax, nz + z]) + base

    return sheet(f, nu, nv, thick)


def ribbon(points, widths, normal_hint=(0, 1, 0), nv=2, thick=0.03):
    """Лента вдоль кривой: ширина задана по точкам."""
    P = np.asarray(points, dtype=np.float64)
    W = np.asarray(widths, dtype=np.float64)
    T = np.gradient(P, axis=0)
    T = T / np.maximum(np.linalg.norm(T, axis=1, keepdims=True), 1e-12)
    Sx = np.cross(T, np.asarray(normal_hint, dtype=np.float64))
    Sx = Sx / np.maximum(np.linalg.norm(Sx, axis=1, keepdims=True), 1e-12)
    k = len(P)

    def f(u, v):
        pos = u * (k - 1)
        a = min(int(pos), k - 2)
        fr = pos - a
        p = P[a] * (1 - fr) + P[a + 1] * fr
        s = Sx[a] * (1 - fr) + Sx[a + 1] * fr
        w = W[a] * (1 - fr) + W[a + 1] * fr
        return p + s * v * w

    return sheet(f, k - 1, nv, thick)


# ---------------------------------------------------------------- кристаллы и грани
def prism(base, axis, height, radius, sides=6, tip=0.35, taper=0.92, rot=0.0):
    """Гранёный кристалл: шестигранная призма с острой пирамидой сверху. Нормали плоские (острые грани)."""
    Fm = frame(axis, (0, 1, 0) if abs(axis[1]) < 0.95 else (1, 0, 0))
    ang = np.linspace(0, TAU, sides, endpoint=False) + rot
    ring0 = np.stack([np.cos(ang) * radius, np.zeros(sides), np.sin(ang) * radius], 1)
    hbody = height * (1 - tip)
    ring1 = np.stack([np.cos(ang) * radius * taper, np.full(sides, hbody), np.sin(ang) * radius * taper], 1)
    apex = np.array([0, height, 0.0])
    verts, norms, idx = [], [], []

    def quad(a, b, c, d):
        n = unit(np.cross(b - a, c - a))
        o = len(verts)
        verts.extend([a, b, c, d])
        norms.extend([n] * 4)
        idx.extend([[o, o + 1, o + 2], [o, o + 2, o + 3]])

    def tri(a, b, c):
        n = unit(np.cross(b - a, c - a))
        o = len(verts)
        verts.extend([a, b, c])
        norms.extend([n] * 3)
        idx.append([o, o + 1, o + 2])

    for i in range(sides):
        j = (i + 1) % sides
        quad(ring0[i], ring0[j], ring1[j], ring1[i])
        tri(ring1[i], ring1[j], apex)
    m = Mesh(np.array(verts), np.array(norms), idx)
    m = m.xform(Fm, base)
    # проверка ориентации наружу от оси
    c = m.v.mean(0)
    a, b, cc = m.v[m.i[:, 0]], m.v[m.i[:, 1]], m.v[m.i[:, 2]]
    g = np.cross(b - a, cc - a)
    mid = (a + b + cc) / 3 - (np.asarray(base) + np.asarray(axis) * height * 0.5)
    flip = (g * mid).sum(1) < 0
    m.i[flip] = m.i[flip][:, [0, 2, 1]]
    # нормали пересчитываем по треугольникам (плоские)
    v2, n2, i2 = [], [], []
    for t in m.i:
        a, b, cc = m.v[t[0]], m.v[t[1]], m.v[t[2]]
        n = unit(np.cross(b - a, cc - a))
        o = len(v2)
        v2.extend([a, b, cc])
        n2.extend([n, n, n])
        i2.append([o, o + 1, o + 2])
    return Mesh(np.array(v2), np.array(n2), i2)


def pillow(outline, height=0.5, rings=7, cx=(0, 0)):
    """Надутая фигура: контур (N,2) в плоскости XY, толщина по Z. Получается 'подушка' (звезда, сердце)."""
    O = np.asarray(outline, dtype=np.float64)
    n = len(O)
    cx = np.asarray(cx, dtype=np.float64)
    V = []
    for side in (1, -1):
        for r in range(rings + 1):
            phi = r / rings * np.pi / 2
            ring = cx + (O - cx) * np.cos(phi)
            z = side * height * np.sin(phi)
            for p in ring:
                V.append([p[0], p[1], z])
    V = np.array(V)
    idx = []
    for side in (0, 1):
        for r in range(rings):
            for i in range(n):
                j = (i + 1) % n
                a = side * (rings + 1) * n + r * n + i
                b = side * (rings + 1) * n + r * n + j
                idx += [[a, a + n, b], [b, a + n, b + n]]
    m = Mesh(V, np.zeros_like(V), idx)
    c0 = V.mean(0)
    nn = V - c0
    m.n = nn / np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-9)
    m = recompute_normals(m)
    return m.fix_winding()


def star_outline(points=5, outer=1.0, inner=0.45, rot=np.pi / 2):
    a = np.linspace(0, TAU, points * 2, endpoint=False) + rot
    r = np.where(np.arange(points * 2) % 2 == 0, outer, inner)
    return np.stack([np.cos(a) * r, np.sin(a) * r], 1)


def heart_outline(n=48, scale=0.06):
    t = np.linspace(0, TAU, n, endpoint=False)
    x = 16 * np.sin(t) ** 3
    y = 13 * np.cos(t) - 5 * np.cos(2 * t) - 2 * np.cos(3 * t) - np.cos(4 * t)
    return np.stack([x, y], 1) * scale


def twist_pts(center, radius_fn, height_fn, turns, n=40, phase=0.0):
    t = np.linspace(0, 1, n)
    a = t * turns * TAU + phase
    r = radius_fn(t)
    return np.stack([center[0] + r * np.cos(a), center[1] + height_fn(t), center[2] + r * np.sin(a)], 1)
