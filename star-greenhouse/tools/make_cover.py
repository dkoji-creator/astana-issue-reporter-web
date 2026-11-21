"""Обложка (1920x1080) и иконка (512x512) игры: python3 tools/make_cover.py -> art/cover/{thumbnail,icon}.png"""
import os, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "mesh"))
import build_all, forms, render, preview

ROOT = os.path.join(os.path.dirname(__file__), "..")
OUT = os.path.join(ROOT, "art", "cover")
os.makedirs(OUT, exist_ok=True)
plants = {p["id"]: p for p in build_all.parse_plants()}


def plant_img(pid, size, cam=(-0.45, 0.35, 1.0), zoom=1.0):
    p = plants[pid]
    parts = build_all.build(p)
    return render.render(preview.layers_for(parts, p["c1"], p["c2"], forms.STYLE.get(p["form"])), size=size, ss=2, rgba=True, cam_dir=cam, zoom=zoom)


def font(path, size):
    return ImageFont.truetype(path, size)


FB = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
for cand in ("/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf", "/usr/share/fonts/truetype/noto/NotoSansDisplay-Bold.ttf"):
    if os.path.exists(cand):
        FB = cand
        break


def glow_text(img, xy, text, f, fill, glow, anchor="mm", radius=18):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.text(xy, text, font=f, fill=glow, anchor=anchor)
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius)))
    d2 = ImageDraw.Draw(img)
    d2.text((xy[0], xy[1] + 4), text, font=f, fill=(0, 0, 0, 160), anchor=anchor)
    d2.text(xy, text, font=f, fill=fill, anchor=anchor)


def background(w, h, seed_face="Ft"):
    sky = Image.open(os.path.join(ROOT, "art/sky", seed_face + ".png")).convert("RGBA")
    sc = max(w / sky.width, h / sky.height) * 1.15
    sky = sky.resize((int(sky.width * sc), int(sky.height * sc)), Image.LANCZOS)
    bg = sky.crop(((sky.width - w) // 2, (sky.height - h) // 2, (sky.width - w) // 2 + w, (sky.height - h) // 2 + h))
    return bg


def thumbnail():
    W, H = 1920, 1080
    bg = background(W, H, "Rt")
    gas = Image.open(os.path.join(ROOT, "art/planets/gas.png")).convert("RGBA")
    g = gas.resize((1500, 1500), Image.LANCZOS)
    bg.alpha_composite(g, (820, -430))
    earth = Image.open(os.path.join(ROOT, "art/planets/earth.png")).convert("RGBA").resize((330, 330), Image.LANCZOS)
    bg.alpha_composite(earth, (40, 30))
    # поверхность астероида внизу
    ground = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gd = ImageDraw.Draw(ground)
    gd.ellipse([-500, 860, W + 500, 1700], fill=(34, 32, 48, 255))
    gd.ellipse([-300, 880, W + 300, 1700], fill=(48, 46, 66, 255))
    rim = ground.filter(ImageFilter.GaussianBlur(2))
    bg.alpha_composite(rim)
    glowline = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(glowline).ellipse([-300, 878, W + 300, 1700], outline=(120, 190, 255, 120), width=3)
    bg.alpha_composite(glowline.filter(ImageFilter.GaussianBlur(3)))
    # растения на переднем плане
    spec = [("moon_16", 640, 330, 640, 1.0), ("core_19", 560, 800, 700, 1.0), ("nebula_17", 600, 1230, 700, 1.0), ("core_09", 520, 1620, 750, 1.0),
            ("io_13", 420, 1010, 880, 1.0)]
    for pid, size, x, y, z in sorted(spec, key=lambda t: t[3]):
        im = plant_img(pid, size, zoom=z)
        bg.alpha_composite(im, (x - size // 2, y - size // 2))
    # затемнение сверху для читаемости названия
    shade = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shade)
    for y in range(0, 520):
        sd.line([(0, y), (W, y)], fill=(4, 6, 16, int(150 * (1 - y / 520))))
    bg.alpha_composite(shade)
    f1 = font(FB, 118)
    glow_text(bg, (W // 2, 150), "ЗВЁЗДНАЯ ОРАНЖЕРЕЯ", f1, (250, 232, 190, 255), (255, 190, 90, 255), radius=26)
    f2 = font(FB, 46)
    glow_text(bg, (W // 2, 260), "Космические растения · мутации 1 к 1 000 000 000", f2, (214, 226, 250, 255), (90, 150, 255, 255), radius=12)
    bg.convert("RGB").save(os.path.join(OUT, "thumbnail.png"))


def icon():
    S = 512
    bg = background(S, S, "Lf")
    gas = Image.open(os.path.join(ROOT, "art/planets/gas.png")).convert("RGBA").resize((330, 330), Image.LANCZOS)
    bg.alpha_composite(gas, (190, -50))
    gd = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(gd).ellipse([-250, 430, S + 250, 1000], fill=(40, 38, 58, 255))
    bg.alpha_composite(gd)
    im = plant_img("nebula_17", 500, cam=(-0.4, 0.3, 1.0), zoom=1.12)
    bg.alpha_composite(im, (6, 40))
    bg.convert("RGB").save(os.path.join(OUT, "icon.png"))


if __name__ == "__main__":
    thumbnail()
    icon()
    print("ok")
