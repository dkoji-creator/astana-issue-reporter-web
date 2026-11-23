"""Строит меши всех растений из Config/Plants.luau: art/plants/<planet>.glb (по одному на планету) и листы превью.
python3 build_all.py [planet ...]"""
import os, re, sys, numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import forms, render, preview
from geom import Mesh as Mesh_
from glb import write_glb

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "art", "plants")
os.makedirs(OUT, exist_ok=True)
RANK = {"common": 0, "uncommon": 1, "rare": 2, "epic": 3, "legendary": 4, "mythic": 5}


def parse_plants():
    txt = open(os.path.join(ROOT, "src", "shared", "Config", "Plants.luau"), encoding="utf8").read()
    out = []
    for line in txt.splitlines():
        m = re.match(r'\s*\{ id = "(\w+)", name = "([^"]+)", planet = "(\w+)", rarity = "(\w+)", form = "(\w+)", c1 = Color3.fromRGB\((\d+), (\d+), (\d+)\), c2 = Color3.fromRGB\((\d+), (\d+), (\d+)\), glow = ([\d.]+), scale = ([\d.]+)', line)
        if m:
            g = m.groups()
            out.append(dict(id=g[0], name=g[1], planet=g[2], rarity=g[3], form=g[4], c1=np.array([int(g[5]), int(g[6]), int(g[7])]) / 255.0,
                            c2=np.array([int(g[8]), int(g[9]), int(g[10])]) / 255.0, glow=float(g[11]), scale=float(g[12]), index=len(out) + 1))
    return out


def components(m):
    """Связные куски меша (вершины на одном месте считаются общими): список массивов индексов треугольников."""
    key = np.round(m.v / 1e-4).astype(np.int64)
    _, uid = np.unique(key, axis=0, return_inverse=True)
    uid = uid.reshape(-1)
    parent = np.arange(uid.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for f in uid[m.i]:
        ra, rb, rc = find(f[0]), find(f[1]), find(f[2])
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(uid[f[0]]) for f in m.i])
    return [np.where(roots == r)[0] for r in np.unique(roots)]


def glow_core(m, k=0.62):
    """Светящаяся сердцевина: каждый объёмный плод уменьшается вокруг своего центра (плоские лепестки пропускаются)."""
    out = Mesh_()
    for faces in components(m):
        idx = np.unique(m.i[faces])
        pts = m.v[idx]
        ext = pts.max(0) - pts.min(0)
        if ext.min() < 0.3 * ext.max() or ext.max() < 0.05:
            continue
        c = pts.mean(0)
        remap = {int(o): j for j, o in enumerate(idx)}
        tri = np.vectorize(remap.get)(m.i[faces])
        out.add(Mesh_(c + (pts - c) * k, m.n[idx], tri))
    return out


def build(p):
    rng = np.random.default_rng(p["index"] * 977 + 13)
    lvl = RANK[p["rarity"]] / 5.0
    parts = forms.FORMS[p["form"]](rng, lvl)
    sc = p["scale"]
    out = {}
    for role, m in parts.items():
        m = m.copy()
        m.fix_winding()
        out[role] = m.xform(None, (0, 0, 0), sc)
    # редкие и выше: плоды-драгоценности — стеклянная оболочка и светящаяся сердцевина внутри (роль C)
    if RANK[p["rarity"]] >= 2 and "F" in out:
        core = glow_core(out["F"])
        if len(core.v):
            out["C"] = core
    return out


if __name__ == "__main__":
    want = sys.argv[1:]
    plants = parse_plants()
    planets = []
    for p in plants:
        if p["planet"] not in planets:
            planets.append(p["planet"])
    for pl in planets:
        if want and pl not in want:
            continue
        glb, ims, labs = [], [], []
        for p in [q for q in plants if q["planet"] == pl]:
            parts = build(p)
            for role, m in parts.items():
                glb.append(dict(name=f"{p['id']}__{role}", v=m.v, n=m.n, i=m.i))
            so = forms.STYLE.get(p["form"])
            ims.append(render.render(preview.layers_for(parts, p["c1"], p["c2"], so), size=220, ss=2))
            labs.append(f"{p['id']} {p['name']} {sum(m.tris() for m in parts.values())}t")
        write_glb(os.path.join(OUT, pl + ".glb"), glb)
        render.sheet(ims, labs, cols=5, tile=220).save(os.path.join(OUT, pl + ".png"))
        print(pl, "tris", sum(len(g["i"]) for g in glb), "size", os.path.getsize(os.path.join(OUT, pl + ".glb")) // 1024, "KB", flush=True)
