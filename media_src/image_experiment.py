"""Part A2: saves one screenshot of our prototype in several formats and compares them.
Usage: python3 media_src/image_experiment.py <screenshot.png> <output folder>
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

source, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(exist_ok=True)
img = Image.open(source).convert("RGB")

versions = [
    ("main_screen.png", "PNG (lossless)", dict(format="PNG", optimize=True)),
    ("main_screen_q80.jpg", "JPEG quality 80", dict(format="JPEG", quality=80)),
    ("main_screen_q40.jpg", "JPEG quality 40", dict(format="JPEG", quality=40)),
    ("main_screen_q80.webp", "WebP quality 80", dict(format="WEBP", quality=80, method=6)),
    ("main_screen_lossless.webp", "WebP lossless", dict(format="WEBP", lossless=True, method=6)),
]
crops = []
for name, label, options in versions:
    img.save(out / name, **options)
    size = (out / name).stat().st_size
    print(f"{name:28} {label:18} {img.width} x {img.height}  {size / 1024:8.1f} KB")
    # a 100% crop (no scaling) of the logo, a button and the map
    crops.append((label, size, Image.open(out / name).convert("RGB").crop((0, 20, 360, 900))))

font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 18)
sheet = Image.new("RGB", (len(crops) * 370 + 10, 950), "white")
draw = ImageDraw.Draw(sheet)
for i, (label, size, crop) in enumerate(crops):
    x = 10 + i * 370
    draw.text((x, 10), label, fill="black", font=font)
    draw.text((x, 34), f"{size / 1024:.0f} KB", fill="#555", font=font)
    sheet.paste(crop, (x, 62))
sheet.save(out / "side_by_side_100pct.png")
