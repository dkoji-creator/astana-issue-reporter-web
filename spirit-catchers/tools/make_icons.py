"""Рисует иконки интерфейса (256x256 PNG, мультяшный стиль: толстый контур, блик, тень)."""
import math, os, sys
from PIL import Image, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "art/icons"
S = 256
OUTLINE = (28, 22, 40, 255)


def canvas():
    return Image.new("RGBA", (S, S), (0, 0, 0, 0))


def finish(img, name):
    # мягкая тень под иконкой
    alpha = img.split()[3]
    sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    sh.putalpha(alpha.point(lambda a: int(a * 0.45)))
    sh = sh.filter(ImageFilter.GaussianBlur(6))
    base = canvas()
    base.alpha_composite(sh, (0, 8))
    base.alpha_composite(img)
    base.save(os.path.join(OUT, name + ".png"))


def shine(d, box):
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    d.ellipse((x0 + w * 0.22, y0 + h * 0.16, x0 + w * 0.40, y0 + h * 0.27), fill=(255, 255, 240, 255))


def star_pts(cx, cy, r1, r2, n=5, rot=-90):
    pts = []
    for i in range(n * 2):
        r = r1 if i % 2 == 0 else r2
        a = math.radians(rot + i * 180 / n)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts


def coin():
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((20, 20, 236, 236), fill=(255, 196, 40), outline=OUTLINE, width=12)
    d.ellipse((52, 52, 204, 204), outline=(214, 140, 20), width=10)
    d.polygon(star_pts(128, 132, 52, 22), fill=(255, 236, 140), outline=(200, 120, 10))
    shine(d, (20, 20, 236, 236)); finish(im, "coin")


def dust():
    im = canvas(); d = ImageDraw.Draw(im)
    for cx, cy, r, col in [(120, 132, 92, (190, 120, 255)), (196, 70, 40, (140, 220, 255)), (70, 206, 30, (255, 170, 240))]:
        pts = star_pts(cx, cy, r, r * 0.32, 4, -90)
        d.polygon(pts, fill=col, outline=OUTLINE, width=8)
    d.ellipse((92, 96, 128, 128), fill=(255, 255, 255, 255)); finish(im, "dust")


def jar():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle((48, 66, 208, 236), 46, fill=(150, 220, 255, 255), outline=OUTLINE, width=12)
    d.ellipse((92, 120, 164, 192), fill=(255, 240, 160), outline=(255, 200, 80), width=6)
    d.rounded_rectangle((70, 30, 186, 74), 14, fill=(200, 70, 60), outline=OUTLINE, width=12)
    d.rounded_rectangle((70, 90, 100, 200), 14, fill=(215, 242, 255, 255)); finish(im, "jar")


def book():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle((36, 30, 220, 226), 22, fill=(70, 90, 200), outline=OUTLINE, width=12)
    d.rectangle((48, 196, 214, 214), fill=(245, 235, 210))
    d.rounded_rectangle((36, 30, 70, 226), 14, fill=(50, 60, 150), outline=OUTLINE, width=10)
    # огонёк духа на обложке
    d.polygon([(140, 70), (176, 130), (160, 170), (120, 170), (104, 130)], fill=(140, 230, 255), outline=OUTLINE)
    d.ellipse((124, 120, 156, 152), fill=(255, 255, 255)); finish(im, "atlas")


def scroll():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle((54, 40, 202, 216), 16, fill=(250, 232, 190), outline=OUTLINE, width=12)
    for y in (84, 118, 152):
        d.rounded_rectangle((80, y, 176, y + 12), 6, fill=(170, 130, 90))
    d.rounded_rectangle((36, 24, 220, 60), 18, fill=(200, 70, 60), outline=OUTLINE, width=10)
    d.rounded_rectangle((36, 196, 220, 232), 18, fill=(200, 70, 60), outline=OUTLINE, width=10)
    d.ellipse((150, 150, 196, 196), fill=(230, 60, 60), outline=OUTLINE, width=6); finish(im, "quests")


def lantern():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rectangle((118, 8, 138, 40), fill=OUTLINE)
    d.ellipse((40, 40, 216, 224), fill=(240, 90, 60), outline=OUTLINE, width=12)
    for y in (90, 132, 174):
        w = 80 - abs(132 - y) * 0.6
        d.line((128 - w, y, 128 + w, y), fill=(150, 40, 30), width=8)
    d.rounded_rectangle((84, 30, 172, 56), 8, fill=(60, 40, 40), outline=OUTLINE, width=6)
    d.rounded_rectangle((84, 210, 172, 236), 8, fill=(60, 40, 40), outline=OUTLINE, width=6)
    d.ellipse((100, 100, 156, 160), fill=(255, 220, 140, 255)); finish(im, "shop")


def gift():
    im = canvas(); d = ImageDraw.Draw(im)
    d.rounded_rectangle((36, 104, 220, 232), 16, fill=(90, 200, 120), outline=OUTLINE, width=12)
    d.rounded_rectangle((24, 72, 232, 116), 14, fill=(110, 225, 140), outline=OUTLINE, width=12)
    d.rectangle((110, 76, 146, 228), fill=(255, 210, 60))
    d.ellipse((60, 20, 128, 84), outline=(255, 210, 60), width=16)
    d.ellipse((128, 20, 196, 84), outline=(255, 210, 60), width=16)
    d.rectangle((108, 72, 148, 112), outline=OUTLINE, width=6); finish(im, "gift")


def gear():
    im = canvas(); d = ImageDraw.Draw(im)
    pts = []
    for i in range(16):
        r = 112 if i % 2 == 0 else 86
        a = math.radians(i * 22.5)
        pts.append((128 + r * math.cos(a), 128 + r * math.sin(a)))
    d.polygon(pts, fill=(170, 180, 200), outline=OUTLINE, width=10)
    d.ellipse((84, 84, 172, 172), fill=(90, 100, 130), outline=OUTLINE, width=10); finish(im, "settings")


def upgrade():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(128, 18), (230, 130), (172, 130), (172, 236), (84, 236), (84, 130), (26, 130)], fill=(80, 220, 120), outline=OUTLINE, width=12)
    d.polygon([(128, 50), (190, 118), (150, 118)], fill=(200, 255, 210)); finish(im, "upgrade")


def star():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon(star_pts(128, 136, 118, 52), fill=(255, 210, 60), outline=OUTLINE, width=12)
    d.polygon(star_pts(118, 120, 40, 18), fill=(255, 245, 190)); finish(im, "level")


def lock():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((66, 20, 190, 150), 180, 360, fill=OUTLINE, width=34)
    d.arc((76, 30, 180, 140), 180, 360, fill=(170, 180, 200), width=14)
    d.rounded_rectangle((40, 100, 216, 236), 24, fill=(255, 190, 60), outline=OUTLINE, width=12)
    d.ellipse((112, 140, 144, 172), fill=OUTLINE); d.rectangle((122, 160, 134, 200), fill=OUTLINE); finish(im, "lock")


def moon():
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((22, 22, 234, 234), fill=(230, 50, 60), outline=OUTLINE, width=12)
    d.ellipse((96, 6, 260, 170), fill=(0, 0, 0, 0))
    m = Image.new("L", (S, S), 255); md = ImageDraw.Draw(m); md.ellipse((100, 0, 270, 170), fill=0)
    im.putalpha(Image.composite(im.split()[3], Image.new("L", (S, S), 0), m))
    d = ImageDraw.Draw(im); d.ellipse((60, 150, 90, 180), fill=(170, 30, 40)); finish(im, "moon")


def target():
    im = canvas(); d = ImageDraw.Draw(im)
    for r, col in [(110, (240, 120, 60)), (78, (255, 255, 255)), (46, (240, 120, 60))]:
        d.ellipse((128 - r, 128 - r, 128 + r, 128 + r), fill=col, outline=OUTLINE, width=10)
    d.ellipse((112, 112, 144, 144), fill=OUTLINE); finish(im, "target")


def paw():
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((60, 110, 196, 230), fill=(255, 240, 220), outline=OUTLINE, width=12)
    for cx, cy in [(56, 86), (104, 44), (152, 44), (200, 86)]:
        d.ellipse((cx - 28, cy - 30, cx + 28, cy + 30), fill=(255, 240, 220), outline=OUTLINE, width=10)
    finish(im, "paw")


def trophy():
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((14, 40, 90, 140), 90, 270, fill=OUTLINE, width=16)
    d.arc((166, 40, 242, 140), 270, 90, fill=OUTLINE, width=16)
    d.pieslice((52, -40, 204, 170), 0, 180, fill=(255, 196, 40), outline=OUTLINE, width=12)
    d.rectangle((52, 26, 204, 66), fill=(255, 196, 40))
    d.line((52, 26, 204, 26), fill=OUTLINE, width=12)
    d.rectangle((112, 168, 144, 200), fill=(220, 150, 20), outline=OUTLINE, width=8)
    d.rounded_rectangle((70, 196, 186, 236), 10, fill=(120, 80, 50), outline=OUTLINE, width=10); finish(im, "trophy")


def sound():
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(30, 96), (86, 96), (146, 40), (146, 216), (86, 160), (30, 160)], fill=(120, 200, 255), outline=OUTLINE, width=12)
    for r in (40, 70):
        d.arc((146 - r, 128 - r, 146 + r + 20, 128 + r), -50, 50, fill=OUTLINE, width=14)
    finish(im, "sound")


os.makedirs(OUT, exist_ok=True)
for f in (coin, dust, jar, book, scroll, lantern, gift, gear, upgrade, star, lock, moon, target, paw, trophy, sound):
    f()
print("icons:", sorted(os.listdir(OUT)))
