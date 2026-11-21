"""Простой растеризатор мешей с освещением, бликами, свечением и полупрозрачностью — для просмотра растений без Studio."""
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
from geom import Mesh, lathe, unit

LIGHT_KEY = unit((-0.45, 0.75, 0.55))
LIGHT_FILL = unit((0.7, 0.15, -0.5))


def _cam_basis(cam, target):
    f = unit(np.asarray(target) - np.asarray(cam))
    r = unit(np.cross(f, (0, 1, 0)))
    u = np.cross(r, f)
    return f, r, u


def rasterize(layers, cam, target, W, H, fov=32, transparent=False, zref=None):
    """layers: список (Mesh, props). Возвращает буферы глубины, альбедо, нормалей, позиций, свечения, блеска."""
    f, r, u = _cam_basis(cam, target)
    tanh = np.tan(np.radians(fov) / 2)
    aspect = W / H
    zbuf = np.full((H, W), np.inf)
    alb = np.zeros((H, W, 3))
    nor = np.zeros((H, W, 3))
    pos = np.zeros((H, W, 3))
    emi = np.zeros((H, W))
    spc = np.zeros((H, W, 3))
    alp = np.zeros((H, W))
    for mesh, pr in layers:
        v = mesh.v - cam
        x = v @ r
        y = v @ u
        z = v @ f
        z = np.maximum(z, 1e-3)
        sx = (x / (z * tanh * aspect) * 0.5 + 0.5) * W
        sy = (0.5 - y / (z * tanh) * 0.5) * H
        tri = mesh.i
        for t in tri:
            a, b, c = t
            xs = np.array([sx[a], sx[b], sx[c]])
            ys = np.array([sy[a], sy[b], sy[c]])
            x0, x1 = int(max(0, np.floor(xs.min()))), int(min(W - 1, np.ceil(xs.max())))
            y0, y1 = int(max(0, np.floor(ys.min()))), int(min(H - 1, np.ceil(ys.max())))
            if x1 < x0 or y1 < y0:
                continue
            den = (ys[1] - ys[2]) * (xs[0] - xs[2]) + (xs[2] - xs[1]) * (ys[0] - ys[2])
            if abs(den) < 1e-9:
                continue
            gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
            l0 = ((ys[1] - ys[2]) * (gx - xs[2]) + (xs[2] - xs[1]) * (gy - ys[2])) / den
            l1 = ((ys[2] - ys[0]) * (gx - xs[2]) + (xs[0] - xs[2]) * (gy - ys[2])) / den
            l2 = 1 - l0 - l1
            inside = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
            if not inside.any():
                continue
            iz = l0 / z[a] + l1 / z[b] + l2 / z[c]  # 1/z линейно
            depth = 1 / np.maximum(iz, 1e-9)
            sub = zbuf[y0:y1 + 1, x0:x1 + 1]
            ok = inside & (depth < sub)
            if zref is not None:
                ok &= depth < zref[y0:y1 + 1, x0:x1 + 1]
            if not ok.any():
                continue
            # перспективно-корректные барицентры
            w0, w1, w2 = l0 / z[a] * depth, l1 / z[b] * depth, l2 / z[c] * depth
            nrm = w0[..., None] * mesh.n[a] + w1[..., None] * mesh.n[b] + w2[..., None] * mesh.n[c]
            pp = w0[..., None] * mesh.v[a] + w1[..., None] * mesh.v[b] + w2[..., None] * mesh.v[c]
            sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
            zbuf[sl][ok] = depth[ok]
            nor[sl][ok] = nrm[ok]
            pos[sl][ok] = pp[ok]
            alb[sl][ok] = pr["color"]
            emi[sl][ok] = pr.get("emit", 0.0)
            spc[sl][ok] = (pr.get("spec", 0.3), pr.get("shin", 40), pr.get("wrap", 0.0))
            alp[sl][ok] = pr.get("alpha", 1.0)
    return zbuf, alb, nor, pos, emi, spc, alp


def shade(alb, nor, pos, emi, spc, cam, rim=(0.35, 0.55, 1.0)):
    nl = np.linalg.norm(nor, axis=2, keepdims=True)
    n = nor / np.maximum(nl, 1e-9)
    view = cam - pos
    view = view / np.maximum(np.linalg.norm(view, axis=2, keepdims=True), 1e-9)
    facing = (n * view).sum(2)
    n = np.where(facing[..., None] < 0, -n, n)
    nv = np.clip((n * view).sum(2), 0, 1)
    wrap = spc[..., 2]
    diff = np.clip(((n * LIGHT_KEY).sum(2) + wrap) / (1 + wrap), 0, 1)
    fill = np.clip((n * LIGHT_FILL).sum(2), 0, 1)
    sky = np.array([0.55, 0.55, 0.85])
    gnd = np.array([0.25, 0.18, 0.3])
    hemi = (0.5 + 0.5 * n[..., 1:2]) * sky + (0.5 - 0.5 * n[..., 1:2]) * gnd
    h = LIGHT_KEY + view
    h = h / np.maximum(np.linalg.norm(h, axis=2, keepdims=True), 1e-9)
    sp = np.clip((n * h).sum(2), 0, 1) ** spc[..., 1] * spc[..., 0]
    ao = 0.6 + 0.4 * np.clip(pos[..., 1] / 1.0, 0, 1)
    ao = ao[..., None]
    col = alb * (hemi * 0.55 * ao + diff[..., None] * np.array([1.0, 0.95, 0.85]) * 0.95 + fill[..., None] * np.array([0.3, 0.35, 0.6]) * 0.4)
    col = col + sp[..., None] * np.array([1, 0.97, 0.9]) * 0.9
    col = col + ((1 - nv) ** 3)[..., None] * np.array(rim) * 0.35
    col = col + alb * emi[..., None] * 1.2
    return col


def render(layers, size=260, ss=2, cam_dir=(-0.55, 0.42, 1.0), bg=True, fov=32, focus=None, dist=None, zoom=1.0, ground=True):
    W = H = size * ss
    pts = np.vstack([m.v for m, _ in layers])
    lo, hi = pts.min(0), pts.max(0)
    center = (lo + hi) / 2 if focus is None else np.asarray(focus)
    radius = np.linalg.norm(hi - lo) / 2
    d = unit(cam_dir)
    cam = center + d * (radius / np.tan(np.radians(fov) / 2) * 1.05 / zoom if dist is None else dist)
    if ground:
        ext = max(hi[0] - lo[0], hi[2] - lo[2], 2.0)
        gr = ext * 0.8
        disc = lathe([(1e-3, 0.0), (gr, 0.0), (gr * 1.04, -0.05)], 36)
        layers = [(disc, dict(color=np.array([0.11, 0.09, 0.13]), spec=0.1, shin=10))] + list(layers)
    opaque = [(m, p) for m, p in layers if p.get("alpha", 1.0) >= 0.999]
    trans = [(m, p) for m, p in layers if p.get("alpha", 1.0) < 0.999]
    zb, alb, nor, pos, emi, spc, _ = rasterize(opaque, cam, center, W, H, fov)
    img = np.zeros((H, W, 3))
    # фон
    yy, xx = np.mgrid[0:H, 0:W]
    rr = np.hypot((xx / W - 0.5) * 1.1, (yy / H - 0.45)) * 1.5
    bgc = np.array([0.075, 0.07, 0.15]) * (1 - np.clip(rr, 0, 1))[..., None] + np.array([0.02, 0.02, 0.05]) * np.clip(rr, 0, 1)[..., None]
    hit = np.isfinite(zb)
    col = shade(alb, nor, pos, emi, spc, cam)
    img = np.where(hit[..., None], col, bgc)
    glow = np.where(hit[..., None], alb * emi[..., None], 0.0)
    if trans:
        zt, albt, nort, post, emit, spct, alpt = rasterize(trans, cam, center, W, H, fov, zref=np.where(hit, zb, np.inf))
        th = np.isfinite(zt)
        colt = shade(albt, nort, post, emit, spct, cam)
        a = np.clip(alpt, 0, 1)[..., None]
        img = np.where(th[..., None], img * (1 - a) + colt * a, img)
        glow = glow + np.where(th[..., None], albt * emit[..., None] * a, 0.0)
    # свечение: размытие ярких эмиссивных пикселей
    gimg = Image.fromarray((np.clip(glow, 0, 1) * 255).astype(np.uint8))
    b1 = np.asarray(gimg.filter(ImageFilter.GaussianBlur(ss * 5)), dtype=np.float64) / 255
    b2 = np.asarray(gimg.filter(ImageFilter.GaussianBlur(ss * 16)), dtype=np.float64) / 255
    img = img + b1 * 0.9 + b2 * 0.8
    img = 1 - np.exp(-img * 1.35)
    img = np.clip(img, 0, 1) ** (1 / 1.08)
    out = Image.fromarray((img * 255).astype(np.uint8))
    if ss > 1:
        out = out.resize((size, size), Image.LANCZOS)
    return out


def sheet(images, labels, cols=6, tile=260):
    rows = (len(images) + cols - 1) // cols
    sh = Image.new("RGB", (cols * tile, rows * (tile + 18)), (14, 12, 24))
    dr = ImageDraw.Draw(sh)
    for i, (im, lb) in enumerate(zip(images, labels)):
        x, y = (i % cols) * tile, (i // cols) * (tile + 18)
        sh.paste(im, (x, y + 18))
        dr.text((x + 4, y + 3), lb, fill=(255, 255, 255))
    return sh
