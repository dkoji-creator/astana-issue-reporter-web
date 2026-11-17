"""Черновик обложки: иконка 1024x1024 и превью 1920x1080. Ночной квартал, красная луна, фонари, бумажный лис, золотой карп."""
import math, random, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
random.seed(4)
INK = (24, 18, 36, 255)


def glow(base, draw_fn, radius, strength=1):
    layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
    draw_fn(ImageDraw.Draw(layer))
    g = layer.filter(ImageFilter.GaussianBlur(radius))
    for _ in range(strength):
        base.alpha_composite(g)
    base.alpha_composite(layer)


def sky(W, H):
    im = Image.new("RGBA", (W, H))
    d = ImageDraw.Draw(im)
    for y in range(H):
        t = y / H
        c = (int(30 + 40 * t), int(18 + 10 * t), int(70 - 20 * t))
        d.line((0, y, W, y), fill=c + (255,))
    for _ in range(int(W * H / 9000)):
        x, y = random.randrange(W), random.randrange(int(H * 0.6))
        r = random.choice([1, 1, 2])
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 255, 230, random.randrange(120, 255)))
    return im


def moon(im, cx, cy, r):
    glow(im, lambda d: d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=(235, 60, 70, 255)), r * 0.5, 2)
    d = ImageDraw.Draw(im)
    for _ in range(6):
        a, rr = random.random() * 6.28, random.uniform(0.1, 0.6) * r
        x, y, s = cx + math.cos(a) * rr, cy + math.sin(a) * rr, r * random.uniform(0.08, 0.18)
        d.ellipse((x - s, y - s, x + s, y + s), fill=(200, 40, 55, 255))


def roofs(im, W, H, base_y, scale, color):
    d = ImageDraw.Draw(im)
    x = -50
    while x < W + 50:
        w = random.randint(int(160 * scale), int(260 * scale))
        h = random.randint(int(140 * scale), int(260 * scale))
        top = base_y - h
        d.rectangle((x, top, x + w, H), fill=color)
        d.polygon([(x - 25 * scale, top), (x + w / 2, top - 70 * scale), (x + w + 25 * scale, top)], fill=tuple(max(0, c - 12) for c in color[:3]) + (255,))
        for wx in range(int(x + 25 * scale), int(x + w - 30 * scale), int(60 * scale)):
            wy = top + 40 * scale
            if random.random() < 0.6:
                glow(im, lambda dd, wx=wx, wy=wy: dd.rectangle((wx, wy, wx + 26 * scale, wy + 36 * scale), fill=(255, 170, 80, 255)), 10 * scale)
        x += w + random.randint(0, int(30 * scale))


def lanterns(im, W, y0, sag, n, size):
    d = ImageDraw.Draw(im)
    pts = [(i * W / (n - 1), y0 + sag * math.sin(math.pi * i / (n - 1))) for i in range(n)]
    d.line(pts, fill=(40, 25, 30, 255), width=max(2, int(size * 0.12)))
    for (x, y) in pts[1:-1]:
        def lamp(dd, x=x, y=y):
            dd.ellipse((x - size * 0.55, y, x + size * 0.55, y + size * 1.3), fill=(255, 120, 60, 255))
        glow(im, lamp, size * 0.7, 2)
        dd = ImageDraw.Draw(im)
        dd.line((x - size * 0.45, y + size * 0.65, x + size * 0.45, y + size * 0.65), fill=(170, 50, 30, 255), width=max(1, int(size * 0.1)))


def fox(im, cx, cy, s):
    d = ImageDraw.Draw(im)
    paper, red = (245, 236, 220, 255), (210, 45, 55, 255)
    glow(im, lambda dd: dd.ellipse((cx - 150 * s, cy - 120 * s, cx + 150 * s, cy + 150 * s), fill=(255, 220, 160, 90)), 60 * s)
    d = ImageDraw.Draw(im)
    # хвост
    d.polygon([(cx + 60 * s, cy + 40 * s), (cx + 210 * s, cy - 90 * s), (cx + 250 * s, cy - 10 * s), (cx + 120 * s, cy + 90 * s)], fill=paper, outline=INK, width=int(8 * s))
    d.polygon([(cx + 210 * s, cy - 90 * s), (cx + 250 * s, cy - 10 * s), (cx + 235 * s, cy - 60 * s)], fill=(255, 130, 120, 255))
    # тело
    d.polygon([(cx - 90 * s, cy + 140 * s), (cx - 60 * s, cy + 10 * s), (cx + 90 * s, cy + 20 * s), (cx + 110 * s, cy + 140 * s)], fill=paper, outline=INK, width=int(8 * s))
    # голова-ромб
    d.polygon([(cx - 110 * s, cy - 20 * s), (cx, cy - 120 * s), (cx + 110 * s, cy - 20 * s), (cx, cy + 70 * s)], fill=paper, outline=INK, width=int(8 * s))
    # уши
    for sx in (-1, 1):
        d.polygon([(cx + sx * 40 * s, cy - 90 * s), (cx + sx * 95 * s, cy - 200 * s), (cx + sx * 100 * s, cy - 50 * s)], fill=paper, outline=INK, width=int(8 * s))
        d.polygon([(cx + sx * 80 * s, cy - 160 * s), (cx + sx * 95 * s, cy - 200 * s), (cx + sx * 98 * s, cy - 140 * s)], fill=red)
        # глаза
        ex = cx + sx * 42 * s
        d.line((ex - 26 * s, cy - 32 * s, ex + 26 * s, cy - 32 * s + sx * -8 * s), fill=INK, width=int(9 * s))
        glow(im, lambda dd, ex=ex: dd.ellipse((ex - 13 * s, cy - 22 * s, ex + 13 * s, cy + 2 * s), fill=(255, 200, 60, 255)), 8 * s)
        d = ImageDraw.Draw(im)
        d.line((cx + sx * 60 * s, cy + 10 * s, cx + sx * 85 * s, cy + 6 * s), fill=red, width=int(7 * s))
    d.ellipse((cx - 12 * s, cy + 40 * s, cx + 12 * s, cy + 58 * s), fill=INK)


def carp(im, cx, cy, s, flip=False):
    layer = Image.new("RGBA", im.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    gold = (255, 190, 50, 255)
    pts = [(cx + i * 30 * s, cy + math.sin(i * 0.6) * 18 * s) for i in range(-5, 6)]
    for i, (x, y) in enumerate(pts):
        r = (60 - abs(i - 3) * 8) * s
        d.ellipse((x - r, y - r * 0.8, x + r, y + r * 0.8), fill=gold)
    hx, hy = pts[0]
    d.ellipse((hx - 18 * s, hy - 20 * s, hx + 4 * s, hy + 2 * s), fill=(255, 250, 235, 255))
    d.ellipse((hx - 12 * s, hy - 14 * s, hx, hy - 2 * s), fill=INK)
    tx, ty = pts[-1]
    d.polygon([(tx, ty), (tx + 120 * s, ty - 90 * s), (tx + 90 * s, ty), (tx + 130 * s, ty + 80 * s)], fill=(255, 235, 170, 150))
    for (x, y) in (pts[4], pts[6]):
        d.polygon([(x, y + 20 * s), (x - 30 * s, y + 110 * s), (x + 50 * s, y + 40 * s)], fill=(255, 235, 170, 130))
    if flip:
        layer = layer.transpose(Image.FLIP_LEFT_RIGHT)
    g = layer.filter(ImageFilter.GaussianBlur(22 * s))
    im.alpha_composite(g)
    im.alpha_composite(layer)


def title(im, text, sub, cx, y, size):
    f = ImageFont.truetype(FONT, size)
    fs = ImageFont.truetype(FONT, int(size * 0.42))
    d = ImageDraw.Draw(im)
    def t(dd):
        dd.text((cx, y), text, font=f, anchor="mm", fill=(255, 200, 70, 255), stroke_width=int(size * 0.09), stroke_fill=INK)
    glow(im, lambda dd: dd.text((cx, y), text, font=f, anchor="mm", fill=(255, 150, 60, 255)), size * 0.25)
    t(ImageDraw.Draw(im))
    d = ImageDraw.Draw(im)
    d.text((cx, y + size * 0.85), sub, font=fs, anchor="mm", fill=(255, 255, 255, 255), stroke_width=int(size * 0.05), stroke_fill=INK)


def make(W, H, out, icon):
    im = sky(W, H)
    moon(im, W * (0.78 if not icon else 0.74), H * 0.2, min(W, H) * 0.13)
    roofs(im, W, H, H * 0.62, H / 1080 * 1.1, (40, 30, 52, 255))
    lanterns(im, W, H * 0.30, H * 0.10, 9 if not icon else 6, H * 0.045)
    roofs(im, W, H, H * 0.86, H / 1080 * 1.5, (28, 22, 38, 255))
    d = ImageDraw.Draw(im)
    d.rectangle((0, H * 0.86, W, H), fill=(22, 30, 70, 255))
    for i in range(14):
        x = random.randrange(W)
        glow(im, lambda dd, x=x: dd.rectangle((x, H * 0.88, x + W * 0.012, H * 0.98), fill=random.choice([(255, 130, 70, 200), (120, 220, 255, 200), (255, 90, 150, 200)])), 8)
    if icon:
        carp(im, W * 0.30, H * 0.30, W / 1024 * 0.9)
        fox(im, W * 0.5, H * 0.60, W / 1024 * 1.3)
        title(im, "SPIRIT", "CATCHERS", W * 0.5, H * 0.88, int(W * 0.11))
    else:
        carp(im, W * 0.22, H * 0.36, H / 1080 * 1.2)
        fox(im, W * 0.72, H * 0.60, H / 1080 * 1.35)
        title(im, "SPIRIT CATCHERS", "ЛОВЦЫ ДУХОВ", W * 0.36, H * 0.72, int(H * 0.11))
    im.convert("RGB").save(out, quality=95)


make(1024, 1024, sys.argv[1] + "/icon.png", True)
make(1920, 1080, sys.argv[1] + "/thumbnail.png", False)
print("ok")
