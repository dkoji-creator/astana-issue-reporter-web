"""Рисует иконки интерфейса (линейный стиль, мягкие акценты): art/icons/*.png 256x256."""
import math, os
from PIL import Image, ImageDraw, ImageFilter

S = 1024  # рисуем крупно, потом уменьшаем (сглаживание)
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "icons")
os.makedirs(OUT, exist_ok=True)
W = (236, 240, 250, 255)
TEAL = (90, 210, 200, 255)
GOLD = (236, 196, 116, 255)
PINK = (226, 130, 186, 255)
BLUE = (110, 168, 240, 255)
GREEN = (110, 210, 150, 255)
LW = 52


def new():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def finish(img, name, glow=None):
    # мягкое свечение под иконкой
    a = img.split()[3]
    g = Image.new("RGBA", (S, S), glow or (120, 180, 255, 0))
    halo = a.filter(ImageFilter.GaussianBlur(28)).point(lambda v: int(v * 0.35))
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    if glow:
        base.paste(Image.new("RGBA", (S, S), glow[:3] + (255,)), (0, 0), halo)
    base.alpha_composite(img)
    base.resize((256, 256), Image.LANCZOS).save(os.path.join(OUT, name + ".png"))


def P(x, y):
    return (x * S, y * S)


def line(d, pts, col=W, w=LW):
    d.line([P(*p) for p in pts], fill=col, width=w, joint="curve")
    for p in (pts[0], pts[-1]):
        x, y = P(*p)
        d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=col)


def circle(d, cx, cy, r, outline=W, fill=None, w=LW):
    d.ellipse([P(cx - r, cy - r), P(cx + r, cy + r)], outline=outline, fill=fill, width=w)


def rrect(d, x0, y0, x1, y1, r, outline=W, fill=None, w=LW):
    d.rounded_rectangle([P(x0, y0), P(x1, y1)], radius=r * S, outline=outline, fill=fill, width=w)


def leaf(d, cx, cy, ang, ln, wd, col):
    pts = []
    for t in [i / 30 for i in range(31)]:
        x = t * ln
        y = math.sin(math.pi * t) * wd
        pts.append((x, y))
    for t in [i / 30 for i in range(30, -1, -1)]:
        x = t * ln
        y = -math.sin(math.pi * t) * wd * 0.35
        pts.append((x, y))
    c, s = math.cos(ang), math.sin(ang)
    d.polygon([P(cx + x * c - y * s, cy + x * s + y * c) for x, y in pts], fill=col)


def star_poly(cx, cy, r1, r2, n=4, rot=-math.pi / 2):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = rot + i * math.pi / n
        pts.append(P(cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def gear(d, cx, cy, r, teeth=8, col=W, w=LW):
    pts = []
    for i in range(teeth * 4):
        a = i / (teeth * 4) * 2 * math.pi
        rr = r * (1.0 if (i % 4) in (0, 1) else 0.78)
        pts.append(P(cx + math.cos(a) * rr, cy + math.sin(a) * rr))
    d.polygon(pts, outline=col, width=w)
    circle(d, cx, cy, r * 0.32, col, None, w)


icons = {}


def icon(name, glow=None):
    def deco(fn):
        icons[name] = (fn, glow)
        return fn
    return deco


@icon("coin", GOLD)
def _(d):
    circle(d, 0.5, 0.5, 0.38, (190, 140, 60, 255), GOLD, 30)
    circle(d, 0.5, 0.5, 0.29, (255, 236, 180, 255), None, 22)
    d.polygon(star_poly(0.5, 0.5, 0.18, 0.075, 5), fill=(255, 248, 225, 255))


@icon("shop", TEAL)  # семена: росток
def _(d):
    line(d, [(0.5, 0.86), (0.5, 0.5)], W)
    leaf(d, 0.5, 0.56, -0.6, 0.34, 0.15, TEAL)
    leaf(d, 0.5, 0.5, math.pi + 0.7, 0.3, 0.13, GREEN)
    d.arc([P(0.22, 0.78), P(0.78, 0.98)], 180, 360, fill=W, width=LW)


@icon("jar", GOLD)  # сумка
def _(d):
    rrect(d, 0.16, 0.34, 0.84, 0.86, 0.09)
    d.arc([P(0.32, 0.12), P(0.68, 0.52)], 180, 360, fill=W, width=LW)
    rrect(d, 0.16, 0.34, 0.84, 0.52, 0.06, W, None)
    rrect(d, 0.43, 0.46, 0.57, 0.6, 0.03, GOLD, GOLD, 8)


@icon("atlas", BLUE)
def _(d):
    d.polygon([P(0.5, 0.26), P(0.12, 0.18), P(0.12, 0.8), P(0.5, 0.88)], outline=W, width=LW)
    d.polygon([P(0.5, 0.26), P(0.88, 0.18), P(0.88, 0.8), P(0.5, 0.88)], outline=W, width=LW)
    d.polygon(star_poly(0.7, 0.5, 0.12, 0.04, 4), fill=BLUE)


@icon("news", PINK)  # рынок: график
def _(d):
    line(d, [(0.14, 0.86), (0.86, 0.86)], W)
    for i, h in enumerate([0.25, 0.4, 0.32, 0.55]):
        x = 0.22 + i * 0.17
        rrect(d, x, 0.82 - h, x + 0.1, 0.82, 0.02, None, (226, 130, 186, 120), 0)
    line(d, [(0.18, 0.6), (0.38, 0.44), (0.54, 0.52), (0.82, 0.22)], PINK)
    d.polygon([P(0.86, 0.16), P(0.86, 0.34), P(0.7, 0.2)], fill=PINK)


@icon("upgrade", TEAL)  # мастерская: шестерня и ключ
def _(d):
    gear(d, 0.4, 0.42, 0.26, 8, W, 40)
    line(d, [(0.56, 0.58), (0.84, 0.86)], TEAL, 70)
    circle(d, 0.53, 0.55, 0.07, TEAL, None, 36)


@icon("gift", GOLD)
def _(d):
    rrect(d, 0.16, 0.42, 0.84, 0.86, 0.05)
    rrect(d, 0.12, 0.3, 0.88, 0.44, 0.04)
    line(d, [(0.5, 0.3), (0.5, 0.86)], GOLD, 44)
    d.ellipse([P(0.3, 0.12), P(0.5, 0.32)], outline=GOLD, width=36)
    d.ellipse([P(0.5, 0.12), P(0.7, 0.32)], outline=GOLD, width=36)


@icon("admin", PINK)
def _(d):
    d.polygon([P(0.5, 0.1), P(0.84, 0.24), P(0.78, 0.6), P(0.5, 0.9), P(0.22, 0.6), P(0.16, 0.24)], outline=W, width=LW)
    d.polygon(star_poly(0.5, 0.48, 0.16, 0.06, 4), fill=PINK)


@icon("luck", GREEN)
def _(d):
    d.polygon(star_poly(0.5, 0.5, 0.4, 0.1, 4), fill=GREEN)
    d.polygon(star_poly(0.78, 0.22, 0.12, 0.035, 4), fill=W)
    d.polygon(star_poly(0.22, 0.78, 0.09, 0.03, 4), fill=W)


@icon("potion", PINK)
def _(d):
    rrect(d, 0.4, 0.1, 0.6, 0.3, 0.03)
    d.ellipse([P(0.2, 0.32), P(0.8, 0.9)], outline=W, width=LW)
    d.chord([P(0.25, 0.37), P(0.75, 0.85)], 10, 170, fill=(226, 130, 186, 220))
    circle(d, 0.42, 0.66, 0.04, None, W, 0)


@icon("lock", W)
def _(d):
    rrect(d, 0.2, 0.44, 0.8, 0.88, 0.07)
    d.arc([P(0.3, 0.14), P(0.7, 0.6)], 180, 360, fill=W, width=LW)
    line(d, [(0.3, 0.37), (0.3, 0.46)])
    line(d, [(0.7, 0.37), (0.7, 0.46)])
    circle(d, 0.5, 0.64, 0.05, None, W, 0)


@icon("code", GOLD)
def _(d):
    d.polygon([P(0.1, 0.3), P(0.9, 0.3), P(0.9, 0.42), P(0.84, 0.5), P(0.9, 0.58), P(0.9, 0.7), P(0.1, 0.7), P(0.1, 0.58), P(0.16, 0.5), P(0.1, 0.42)], outline=W, width=44)
    for i in range(4):
        line(d, [(0.62, 0.35 + i * 0.1), (0.62, 0.38 + i * 0.1)], GOLD, 30)
    d.polygon(star_poly(0.36, 0.5, 0.1, 0.035, 4), fill=GOLD)


@icon("trophy", GOLD)
def _(d):
    d.polygon([P(0.28, 0.14), P(0.72, 0.14), P(0.68, 0.46), P(0.5, 0.6), P(0.32, 0.46)], outline=W, width=LW)
    d.arc([P(0.1, 0.18), P(0.36, 0.46)], 90, 270, fill=W, width=40)
    d.arc([P(0.64, 0.18), P(0.9, 0.46)], 270, 90, fill=W, width=40)
    line(d, [(0.5, 0.62), (0.5, 0.78)])
    line(d, [(0.32, 0.84), (0.68, 0.84)], GOLD, 60)


@icon("bed", GREEN)  # грядка
def _(d):
    rrect(d, 0.12, 0.6, 0.88, 0.86, 0.05)
    d.rectangle([P(0.18, 0.64), P(0.82, 0.72)], fill=(150, 110, 90, 255))
    line(d, [(0.5, 0.62), (0.5, 0.38)])
    leaf(d, 0.5, 0.44, -0.5, 0.24, 0.1, GREEN)
    leaf(d, 0.5, 0.4, math.pi + 0.6, 0.22, 0.09, TEAL)


@icon("speed", TEAL)  # ускоритель роста
def _(d):
    circle(d, 0.5, 0.56, 0.32)
    line(d, [(0.42, 0.12), (0.58, 0.12)])
    line(d, [(0.5, 0.56), (0.62, 0.38)], TEAL, 50)
    d.arc([P(0.18, 0.24), P(0.82, 0.88)], 300, 360, fill=TEAL, width=LW)


@icon("water", BLUE)  # лейка
def _(d):
    rrect(d, 0.22, 0.38, 0.66, 0.82, 0.08)
    line(d, [(0.66, 0.5), (0.88, 0.3)])
    d.arc([P(0.06, 0.4), P(0.34, 0.7)], 90, 270, fill=W, width=40)
    for i, (x, y) in enumerate([(0.9, 0.42), (0.84, 0.54), (0.94, 0.56)]):
        circle(d, x, y, 0.035, None, BLUE, 0)


@icon("sprinkler", BLUE)
def _(d):
    line(d, [(0.5, 0.9), (0.5, 0.56)])
    rrect(d, 0.38, 0.46, 0.62, 0.58, 0.03)
    for a in range(-60, 61, 30):
        r = math.radians(a - 90)
        for k in (0.2, 0.3, 0.4):
            circle(d, 0.5 + math.cos(r) * k, 0.5 + math.sin(r) * k, 0.025, None, BLUE, 0)


@icon("settings", W)
def _(d):
    gear(d, 0.5, 0.5, 0.36, 8, W, 44)


@icon("seed", TEAL)
def _(d):
    d.ellipse([P(0.3, 0.2), P(0.7, 0.84)], outline=W, width=LW)
    d.arc([P(0.38, 0.3), P(0.62, 0.74)], 200, 340, fill=TEAL, width=36)


@icon("rocket", PINK)
def _(d):
    d.polygon([P(0.5, 0.08), P(0.64, 0.3), P(0.64, 0.66), P(0.36, 0.66), P(0.36, 0.3)], outline=W, width=46)
    d.polygon([P(0.36, 0.48), P(0.2, 0.7), P(0.36, 0.66)], fill=W)
    d.polygon([P(0.64, 0.48), P(0.8, 0.7), P(0.64, 0.66)], fill=W)
    circle(d, 0.5, 0.36, 0.06, PINK, None, 30)
    d.polygon([P(0.42, 0.7), P(0.58, 0.7), P(0.5, 0.94)], fill=GOLD)


@icon("home", GOLD)
def _(d):
    d.polygon([P(0.5, 0.14), P(0.88, 0.48), P(0.12, 0.48)], outline=W, width=LW)
    rrect(d, 0.22, 0.46, 0.78, 0.86, 0.03)
    rrect(d, 0.43, 0.62, 0.57, 0.86, 0.02, GOLD, GOLD, 10)


if __name__ == "__main__":
    for name, (fn, glow) in icons.items():
        img = new()
        fn(ImageDraw.Draw(img))
        finish(img, name, glow)
    # контрольный лист
    names = list(icons)
    sheet = Image.new("RGBA", (len(names) * 96, 110), (14, 18, 32, 255))
    for i, n in enumerate(names):
        im = Image.open(os.path.join(OUT, n + ".png")).resize((88, 88), Image.LANCZOS)
        sheet.alpha_composite(im, (i * 96 + 4, 4))
    sheet.save(os.path.join(OUT, "_sheet.png"))
    print("ok", len(names))
