"""Объёмные формы для аур и спецэффектов: python3 tools/fx/build_fx.py -> art/fx/fx.glb (+ превью art/fx/fx.png)
Меши fx__<Имя>; в игре FxLoader кладёт их в ReplicatedStorage.FxMeshes, клиент клонирует и красит.
  Ring      тонкое кольцо-тор (орбиты, гироскоп)
  RingBold  толстое кольцо (ореолы)
  Gem       гранёный кристалл-бипирамида
  Shard     осколок: шестигранная призма с острыми концами
  Star      четырёхлучевая звезда-искра (объёмная)
  Helix     спираль-трубка в 2.5 витка (энергетическая спираль)
  Shock     плоское кольцо ударной волны
  Crown     зубчатая корона-ореол
"""
import os, sys
import numpy as np

HERE = os.path.dirname(__file__)
sys.path.insert(0, os.path.join(HERE, "..", "mesh"))
from glb import write_glb  # noqa: E402
import render  # noqa: E402
from geom import Mesh  # noqa: E402

OUT = os.path.join(HERE, "..", "..", "art", "fx")
os.makedirs(OUT, exist_ok=True)


def flat(verts, faces):
    """Гранёный меш: у каждой грани свои вершины и нормаль."""
    V = np.asarray(verts, dtype=np.float64)
    F = np.asarray(faces, dtype=np.int64)
    a, b, c = V[F[:, 0]], V[F[:, 1]], V[F[:, 2]]
    n = np.cross(b - a, c - a)
    n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    # нормаль наружу (от центра)
    ctr = V.mean(0)
    flip = ((a + b + c) / 3 - ctr) * n
    sgn = np.where(flip.sum(1) < 0, -1.0, 1.0)[:, None]
    n *= sgn
    v = np.stack([a, b, c], 1).reshape(-1, 3)
    nn = np.repeat(n, 3, axis=0)
    idx = np.arange(len(v)).reshape(-1, 3)
    idx = np.where(sgn < 0, idx[:, ::-1], idx)
    return Mesh(v, nn, idx)


def torus(R, r, seg=72, ring=12):
    vs, ns, ii = [], [], []
    for i in range(seg):
        u = 2 * np.pi * i / seg
        cu, su = np.cos(u), np.sin(u)
        for j in range(ring):
            w = 2 * np.pi * j / ring
            cw, sw = np.cos(w), np.sin(w)
            vs.append([(R + r * cw) * cu, r * sw, (R + r * cw) * su])
            ns.append([cw * cu, sw, cw * su])
    for i in range(seg):
        for j in range(ring):
            a = i * ring + j
            b = ((i + 1) % seg) * ring + j
            c = ((i + 1) % seg) * ring + (j + 1) % ring
            d = i * ring + (j + 1) % ring
            ii += [[a, b, c], [a, c, d]]
    return Mesh(np.array(vs), np.array(ns), np.array(ii))


def gem(h=1.0, r=0.55, sides=6):
    verts = [[0, h, 0], [0, -h, 0]]
    for k in range(sides):
        a = 2 * np.pi * k / sides
        verts.append([np.cos(a) * r, 0.18 * h, np.sin(a) * r])
    faces = []
    for k in range(sides):
        p, q = 2 + k, 2 + (k + 1) % sides
        faces += [[0, q, p], [1, p, q]]
    return flat(verts, faces)


def shard(r=0.22, h=0.7, tip=0.55, sides=6):
    verts = [[0, h + tip, 0], [0, -h - tip * 0.5, 0]]
    for k in range(sides):
        a = 2 * np.pi * k / sides + 0.2
        verts.append([np.cos(a) * r, h, np.sin(a) * r])
    for k in range(sides):
        a = 2 * np.pi * k / sides + 0.2
        verts.append([np.cos(a) * r * 0.92, -h, np.sin(a) * r * 0.92])
    faces = []
    for k in range(sides):
        t0, t1 = 2 + k, 2 + (k + 1) % sides
        b0, b1 = 2 + sides + k, 2 + sides + (k + 1) % sides
        faces += [[0, t1, t0], [t0, t1, b1], [t0, b1, b0], [1, b0, b1]]
    return flat(verts, faces)


def star4(outer=1.0, inner=0.24, th=0.16):
    pts = []
    for k in range(8):
        a = np.pi / 2 + k * np.pi / 4
        rr = outer if k % 2 == 0 else inner
        pts.append([np.cos(a) * rr, np.sin(a) * rr])
    verts = [[0, 0, th], [0, 0, -th]] + [[x, y, 0] for x, y in pts]
    faces = []
    for k in range(8):
        p, q = 2 + k, 2 + (k + 1) % 8
        faces += [[0, p, q], [1, q, p]]
    return flat(verts, faces)


def helix(R=1.0, H=2.4, turns=2.5, r=0.055, n=220, sides=10):
    t = np.linspace(0, 1, n)
    a = t * turns * 2 * np.pi
    c = np.stack([np.cos(a) * R, (t - 0.5) * H, np.sin(a) * R], 1)
    tang = np.gradient(c, axis=0)
    tang /= np.linalg.norm(tang, axis=1, keepdims=True)
    vs, ns, ii = [], [], []
    for i in range(n):
        T = tang[i]
        N = np.cross(T, [0, 1, 0])
        N /= max(np.linalg.norm(N), 1e-9)
        B = np.cross(T, N)
        rr = r * (0.35 + 0.65 * np.sin(np.pi * t[i]) ** 0.5)  # концы тоньше
        for j in range(sides):
            w = 2 * np.pi * j / sides
            d = N * np.cos(w) + B * np.sin(w)
            vs.append(c[i] + d * rr)
            ns.append(d)
    for i in range(n - 1):
        for j in range(sides):
            a0 = i * sides + j
            b0 = (i + 1) * sides + j
            c0 = (i + 1) * sides + (j + 1) % sides
            d0 = i * sides + (j + 1) % sides
            ii += [[a0, c0, b0], [a0, d0, c0]]
    return Mesh(np.array(vs), np.array(ns), np.array(ii))


def shock(inner=0.82, outer=1.0, th=0.03, seg=96):
    vs, ns, ii = [], [], []
    for i in range(seg):
        a = 2 * np.pi * i / seg
        ca, sa = np.cos(a), np.sin(a)
        for rr, y, nrm in ((inner, th, (0, 1, 0)), (outer, th, (0, 1, 0)), (inner, -th, (0, -1, 0)), (outer, -th, (0, -1, 0))):
            vs.append([ca * rr, y, sa * rr])
            ns.append(nrm)
    for i in range(seg):
        j = (i + 1) % seg
        a, b, c, d = i * 4, i * 4 + 1, j * 4 + 1, j * 4
        ii += [[a, c, b], [a, d, c]]
        a, b, c, d = i * 4 + 2, i * 4 + 3, j * 4 + 3, j * 4 + 2
        ii += [[a, b, c], [a, c, d]]
    return Mesh(np.array(vs), np.array(ns), np.array(ii))


def crown(R=1.0, spikes=12, base=0.12, spike=0.42, th=0.06):
    """Ореол-корона: кольцо с острыми зубцами вверх."""
    m = torus(R, th, seg=96, ring=8)
    for k in range(spikes):
        a = 2 * np.pi * k / spikes
        cx, cz = np.cos(a) * R, np.sin(a) * R
        tx, tz = -np.sin(a), np.cos(a)
        w = 0.11
        verts = [[cx - tx * w, 0, cz - tz * w], [cx + tx * w, 0, cz + tz * w], [cx, spike * (1.25 if k % 2 == 0 else 0.8), cz],
                 [cx + np.cos(a) * 0.05, 0.02, cz + np.sin(a) * 0.05]]
        m.add(flat(verts, [[0, 1, 2], [1, 3, 2], [3, 0, 2]]))
    return m


SHAPES = {
    "Ring": torus(1.0, 0.035),
    "RingBold": torus(1.0, 0.09, ring=14),
    "Gem": gem(),
    "Shard": shard(),
    "Star": star4(),
    "Helix": helix(),
    "Shock": shock(),
    "Crown": crown(),
}

if __name__ == "__main__":
    meshes = [dict(name="fx__" + k, v=m.v, n=m.n, i=m.i) for k, m in SHAPES.items()]
    write_glb(os.path.join(OUT, "fx.glb"), meshes)
    ims, labs = [], []
    for k, m in SHAPES.items():
        ims.append(render.render([(m, dict(color=np.array([0.7, 0.85, 1.0]), spec=0.6, shin=60))], size=200, ss=2))
        labs.append(f"{k} {len(m.i)}t")
    render.sheet(ims, labs, cols=4, tile=200).save(os.path.join(OUT, "fx.png"))
    print("ok", len(meshes), sum(len(m.i) for m in SHAPES.values()), "tris")
