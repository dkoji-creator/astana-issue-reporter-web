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

def trace(parts, cam, fwd, w, h, fovdeg=40, bg=(0.12, 0.13, 0.2), ambient=0.35, fog=None):
    fwd = fwd / np.linalg.norm(fwd)
    right = np.cross(fwd, [0, 1, 0]); right /= np.linalg.norm(right)
    up = np.cross(right, fwd)
    aspect = w / h
    xs, ys = np.meshgrid(np.linspace(-1, 1, w), np.linspace(1, -1, h))
    fov = np.tan(np.radians(fovdeg / 2))
    dirs = fwd[None, None] + (xs[..., None] * right * aspect + ys[..., None] * up) * fov
    dirs /= np.linalg.norm(dirs, axis=2, keepdims=True)
    D = dirs.reshape(-1, 3)
    depth = np.full(len(D), np.inf)
    img = np.zeros((len(D), 3)) + np.array(bg)
    light = np.array([-0.4, 0.8, -0.5]); light /= np.linalg.norm(light)
    for p in parts:
        if p["tr"] > 0.85:
            continue
        R, half = p["R"], p["size"] / 2
        o = (cam - p["pos"]) @ R
        d = D @ R
        if "Ball" in p["shape"]:
            s_ = half
            oo, dd = o / s_, d / s_
            a_ = (dd * dd).sum(1); b_ = 2 * (oo * dd).sum(1); c_ = (oo * oo).sum() - 1
            disc = b_ * b_ - 4 * a_ * c_
            t = np.where(disc > 0, (-b_ - np.sqrt(np.maximum(disc, 0))) / (2 * a_), np.inf)
            hp = o + d * t[:, None]
            n_local = hp / (s_ * s_)
        elif "Cylinder" in p["shape"]:
            r = min(half[1], half[2])
            a_ = d[:, 1] ** 2 + d[:, 2] ** 2; b_ = 2 * (o[1] * d[:, 1] + o[2] * d[:, 2]); c_ = o[1] ** 2 + o[2] ** 2 - r * r
            disc = b_ * b_ - 4 * a_ * c_
            t = np.where(disc > 0, (-b_ - np.sqrt(np.maximum(disc, 0))) / (2 * np.maximum(a_, 1e-9)), np.inf)
            hp = o + d * t[:, None]
            t = np.where(np.abs(hp[:, 0]) <= half[0], t, np.inf)
            n_local = np.stack([np.zeros(len(D)), hp[:, 1], hp[:, 2]], 1)
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
            rel_n = None
            if "Wedge" in p["shape"]:
                hy, hz = half[1], half[2]
                fo = o[1] / hy - o[2] / hz
                fd = d[:, 1] / hy - d[:, 2] / hz
                with np.errstate(divide="ignore", invalid="ignore"):
                    tp = -fo / fd
                enter_plane = fd < 0
                rel_n = enter_plane & (tp > tmin)
                tmin2 = np.where(enter_plane, np.maximum(tmin, tp), tmin)
                tmax = np.where(~enter_plane, np.minimum(tmax, tp), tmax)
                tmin = np.where(np.abs(fd) < 1e-9, np.where(fo <= 0, tmin, np.inf), tmin2)
            hit = (tmax >= tmin) & (tmax > 0)
            t = np.where(hit, np.maximum(tmin, 0), np.inf)
            hp = o + d * t[:, None]
            rel = hp / np.maximum(half, 1e-6)
            ax = np.argmax(np.abs(rel), 1)
            n_local = np.zeros((len(D), 3)); n_local[np.arange(len(D)), ax] = np.sign(rel[np.arange(len(D)), ax])
            if rel_n is not None:
                pn = np.array([0, 1 / half[1], -1 / half[2]])
                n_local = np.where(rel_n[:, None], pn / np.linalg.norm(pn), n_local)
        t = np.where(t > 0, t, np.inf)
        closer = t < depth
        if not closer.any():
            continue
        with np.errstate(invalid="ignore"):
            n = n_local @ R.T
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-9)
        if p["neon"]:
            colr = np.broadcast_to(np.clip(p["col"] * 1.25, 0, 1), (len(D), 3))
        else:
            shade = np.clip(ambient + 0.7 * np.clip((n * light).sum(1), 0, 1), 0, 1.1)[:, None]
            colr = np.clip(p["col"] * shade, 0, 1)
        if fog is not None:
            f = np.clip(t / fog[0], 0, 1)[:, None]
            colr = colr * (1 - f) + np.array(fog[1]) * f
        alpha = 1 - p["tr"]
        img[closer] = img[closer] * (1 - alpha) + colr[closer] * alpha
        depth = np.where(closer & (alpha > 0.5), t, depth)
    return Image.fromarray((np.clip(img, 0, 1).reshape(h, w, 3) * 255).astype(np.uint8))

def render(parts, yaw=-0.6, pitch=0.25):
    pts = np.array([p["pos"] for p in parts])
    ext = max(np.max([np.max(p["size"]) for p in parts]), 1)
    center = (pts.min(0) + pts.max(0)) / 2
    radius = np.max(np.linalg.norm(pts - center, axis=1)) + ext * 0.6
    fwd = np.array([np.sin(yaw) * np.cos(pitch), -np.sin(pitch), np.cos(yaw) * np.cos(pitch)])
    cam = center - fwd * radius * 3.2
    return trace(parts, cam, fwd, W, H, fovdeg=40)

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
