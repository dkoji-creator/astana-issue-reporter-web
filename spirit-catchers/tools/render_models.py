"""Простой трассировщик лучей для просмотра моделей духов без Roblox Studio.
Вход: строки P|kind|name|shape|sx,sy,sz|x,y,z,R00..R22|r,g,b|transparency|material (из tools/sim/dump_models.luau).
Выход: PNG-лист с моделями. Запуск: python3 tools/render_models.py models.txt out.png [kind1,kind2]"""
import sys, numpy as np
from PIL import Image, ImageDraw

W = H = 220

def load(path, only=None):
    models = {}
    for line in open(path, encoding="utf8"):
        if not line.startswith("P|"):
            continue
        _, kind, name, shape, size, cf, col, tr, mat = line.strip().split("|")
        if only and kind not in only:
            continue
        c = [float(v) for v in cf.split(",")]
        models.setdefault(kind, []).append(dict(
            shape=shape, size=np.array([float(v) for v in size.split(",")]), pos=np.array(c[:3]),
            R=np.array(c[3:]).reshape(3, 3), col=np.array([int(v) for v in col.split(",")]) / 255.0,
            tr=float(tr), neon=mat == "Neon", name=name))
    return models

def render(parts, yaw=-0.6, pitch=0.25):
    pts = np.array([p["pos"] for p in parts])
    ext = max(np.max([np.max(p["size"]) for p in parts]), 1)
    center = (pts.min(0) + pts.max(0)) / 2
    radius = np.max(np.linalg.norm(pts - center, axis=1)) + ext * 0.6
    # камера спереди-сбоку (духи смотрят в -Z)
    fwd = np.array([np.sin(yaw) * np.cos(pitch), -np.sin(pitch), np.cos(yaw) * np.cos(pitch)])
    cam = center - fwd * radius * 3.2
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    xs, ys = np.meshgrid(np.linspace(-1, 1, W), np.linspace(1, -1, H))
    fov = np.tan(np.radians(20))
    dirs = fwd[None, None] + (xs[..., None] * right + ys[..., None] * up) * fov
    dirs /= np.linalg.norm(dirs, axis=2, keepdims=True)
    D = dirs.reshape(-1, 3)
    depth = np.full(len(D), np.inf)
    img = np.zeros((len(D), 3)) + np.array([0.12, 0.13, 0.2])
    light = np.array([-0.4, 0.8, -0.5]); light /= np.linalg.norm(light)
    for p in parts:
        if p["tr"] > 0.85:
            continue
        R, half = p["R"], p["size"] / 2
        o = (cam - p["pos"]) @ R  # в локальные координаты детали
        d = D @ R
        n_local = None
        if "Ball" in p["shape"]:
            s = half
            oo, dd = o / s, d / s
            a = (dd * dd).sum(1); b = 2 * (oo * dd).sum(1); c = (oo * oo).sum() - 1
            disc = b * b - 4 * a * c
            hit = disc > 0
            t = np.where(hit, (-b - np.sqrt(np.maximum(disc, 0))) / (2 * a), np.inf)
            hp = o + d * t[:, None]
            n_local = hp / (s * s)
        elif "Cylinder" in p["shape"]:
            r = min(half[1], half[2])
            a = d[:, 1] ** 2 + d[:, 2] ** 2; b = 2 * (o[1] * d[:, 1] + o[2] * d[:, 2]); c = o[1] ** 2 + o[2] ** 2 - r * r
            disc = b * b - 4 * a * c
            t = np.where(disc > 0, (-b - np.sqrt(np.maximum(disc, 0))) / (2 * np.maximum(a, 1e-9)), np.inf)
            hp = o + d * t[:, None]
            inside = np.abs(hp[:, 0]) <= half[0]
            t = np.where(inside, t, np.inf)
            n_local = np.stack([np.zeros(len(D)), hp[:, 1], hp[:, 2]], 1)
            # торцы
            with np.errstate(divide="ignore", invalid="ignore"):
                for sgn in (-1, 1):
                    tc = (sgn * half[0] - o[0]) / d[:, 0]
                    hc = o + d * tc[:, None]
                    ok = (tc > 0) & (hc[:, 1] ** 2 + hc[:, 2] ** 2 <= r * r) & (tc < t)
                    t = np.where(ok, tc, t)
                    n_local = np.where(ok[:, None], np.array([sgn, 0, 0]), n_local)
        else:
            with np.errstate(divide="ignore", invalid="ignore"):
                t1 = (-half - o) / d; t2 = (half - o) / d
            tmin = np.nanmax(np.minimum(t1, t2), 1); tmax = np.nanmin(np.maximum(t1, t2), 1)
            hit = (tmax >= tmin) & (tmax > 0)
            rel_n = None
            if "Wedge" in p["shape"]:
                # клин Roblox: тело там, где y/hy <= z/hz (наклонная грань смотрит вверх-вперёд)
                hy, hz = half[1], half[2]
                fo = o[1] / hy - o[2] / hz
                fd = d[:, 1] / hy - d[:, 2] / hz
                with np.errstate(divide="ignore", invalid="ignore"):
                    tp = -fo / fd
                enter_plane = fd < 0  # снаружи -> внутрь по t
                new_min = np.where(enter_plane, np.maximum(tmin, tp), tmin)
                new_max = np.where(~enter_plane, np.minimum(tmax, tp), tmax)
                inside0 = fo <= 0
                new_min = np.where(np.abs(fd) < 1e-9, np.where(inside0, tmin, np.inf), new_min)
                plane_hit = enter_plane & (tp > tmin)
                tmin, tmax = new_min, new_max
                hit = (tmax >= tmin) & (tmax > 0)
                rel_n = plane_hit
            t = np.where(hit, tmin, np.inf)
            hp = o + d * t[:, None]
            rel = hp / half
            ax = np.argmax(np.abs(rel), 1)
            n_local = np.zeros((len(D), 3)); n_local[np.arange(len(D)), ax] = np.sign(rel[np.arange(len(D)), ax])
            if rel_n is not None:
                pn = np.array([0, 1 / half[1], -1 / half[2]])
                n_local = np.where(rel_n[:, None], pn / np.linalg.norm(pn), n_local)
        t = np.where(t > 0, t, np.inf)
        closer = t < depth
        if not closer.any():
            continue
        n = n_local @ R.T
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        shade = 1.0 if p["neon"] else np.clip(0.35 + 0.75 * np.clip((n * light).sum(1), 0, 1), 0, 1.1)[:, None]
        colr = np.clip(p["col"] * shade * (1.25 if p["neon"] else 1), 0, 1)
        colr = colr if np.ndim(colr) == 2 else np.broadcast_to(colr, (len(D), 3))
        alpha = 1 - p["tr"]
        img[closer] = img[closer] * (1 - alpha) + colr[closer] * alpha
        depth = np.where(closer & (alpha > 0.5), t, depth)
    return Image.fromarray((img.reshape(H, W, 3) * 255).astype(np.uint8))

if __name__ == "__main__":
    only = sys.argv[3].split(",") if len(sys.argv) > 3 else None
    models = load(sys.argv[1], only)
    kinds = list(models)
    cols = 6
    rows = (len(kinds) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * W, rows * (H + 18)), (20, 20, 30))
    dr = ImageDraw.Draw(sheet)
    for i, k in enumerate(kinds):
        im = render(models[k])
        x, y = (i % cols) * W, (i // cols) * (H + 18)
        sheet.paste(im, (x, y + 18))
        dr.text((x + 4, y + 3), k, fill=(255, 255, 255))
    sheet.save(sys.argv[2])
    print("ok", len(kinds))
