"""Draws the schematic map of central Astana used as the map background.

Own work: the shapes are drawn by this script (no map tiles or photos are copied),
so the picture is a simplified illustration, not an exact city plan.
Output:
  media_src/map_original.png  - the full-size master (3360 x 3828 px)
  static/img/map-840.webp     - for phones with a 2x screen and for desktop
  static/img/map-420.webp     - for 1x screens
"""
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BASE = Path(__file__).parent.parent
SRC = BASE / "media_src"
OUT = BASE / "static" / "img"

# same rectangle as BOUNDS in index.html
LAT_MIN, LAT_MAX, LNG_MIN, LNG_MAX = 51.09, 51.19, 71.36, 71.50
W, H = 3360, 3828          # master size, aspect ratio 0.878 like #map
S = 2                       # draw 2x bigger, then shrink = smooth edges

LAND = (236, 239, 233)
BLOCK = (226, 230, 224)
PARK = (196, 222, 186)
TREE = (172, 206, 160)
WATER = (164, 203, 230)
MINOR = (255, 255, 255)
MAJOR = (255, 247, 214)
CASING = (214, 205, 170)


def xy(lat, lng):
    x = (lng - LNG_MIN) / (LNG_MAX - LNG_MIN) * W * S
    y = (LAT_MAX - lat) / (LAT_MAX - LAT_MIN) * H * S
    return x, y


def smooth(points, steps=12):
    """Catmull-Rom curve through the points, so the river has no sharp corners."""
    p = [points[0]] + points + [points[-1]]
    out = []
    for i in range(1, len(p) - 2):
        for k in range(steps):
            t = k / steps
            out.append(tuple(
                0.5 * (2 * p[i][j] + (-p[i - 1][j] + p[i + 1][j]) * t
                       + (2 * p[i - 1][j] - 5 * p[i][j] + 4 * p[i + 1][j] - p[i + 2][j]) * t * t
                       + (-p[i - 1][j] + 3 * p[i][j] - 3 * p[i + 1][j] + p[i + 2][j]) * t ** 3)
                for j in range(2)))
    return out + [points[-1]]


def line(draw, points, color, width):
    pts = [xy(*p) for p in points]
    draw.line(pts, fill=color, width=width * S, joint="curve")
    r = width * S / 2
    for x, y in pts:  # round line ends
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


rnd = random.Random(7)
img = Image.new("RGB", (W * S, H * S), LAND)
draw = ImageDraw.Draw(img)

# built-up districts: soft darker patches between the parks
for _ in range(90):
    x, y = rnd.uniform(0, W * S), rnd.uniform(0, H * S)
    w, h = rnd.uniform(120, 420) * S, rnd.uniform(120, 420) * S
    draw.rounded_rectangle([x, y, x + w, y + h], radius=30 * S, fill=BLOCK)

# parks with tree dots
parks = [
    [(51.128, 71.405), (51.128, 71.432), (51.118, 71.432), (51.118, 71.405)],   # central park, left bank
    [(51.168, 71.380), (51.172, 71.398), (51.160, 71.402), (51.157, 71.385)],
    [(51.104, 71.442), (51.108, 71.462), (51.097, 71.465), (51.094, 71.446)],
    [(51.150, 71.452), (51.154, 71.470), (51.145, 71.474), (51.142, 71.456)],
]
for park in parks:
    poly = [xy(*p) for p in park]
    draw.polygon(poly, fill=PARK)
    xs, ys = [p[0] for p in poly], [p[1] for p in poly]
    for _ in range(260):
        x, y = rnd.uniform(min(xs), max(xs)), rnd.uniform(min(ys), max(ys))
        r = rnd.randint(6, 13) * S
        if img.getpixel((int(x), int(y))) == PARK:
            draw.ellipse([x - r, y - r, x + r, y + r], fill=TREE)

# the Esil river, flowing from the south-east to the west
river = [(51.088, 71.488), (51.100, 71.470), (51.112, 71.452), (51.130, 71.444), (51.142, 71.432),
         (51.146, 71.415), (51.140, 71.398), (51.146, 71.380), (51.158, 71.368), (51.162, 71.356)]
line(draw, smooth(river), WATER, 80)

# minor streets
for lat in [51.104, 51.116, 51.140, 51.156, 51.180]:
    line(draw, [(lat, LNG_MIN - 0.01), (lat + 0.002, LNG_MAX + 0.01)], MINOR, 14)
for lng in [71.372, 71.420, 71.436, 71.450, 71.484, 71.494]:
    line(draw, [(LAT_MIN - 0.01, lng), (LAT_MAX + 0.01, lng - 0.003)], MINOR, 14)

# main avenues: a light casing under a yellow road
avenues = [
    [(51.193, 71.405), (51.150, 71.408), (51.120, 71.420), (51.086, 71.425)],
    [(51.130, 71.355), (51.128, 71.420), (51.122, 71.505)],
    [(51.170, 71.355), (51.165, 71.430), (51.172, 71.505)],
    [(51.193, 71.470), (51.140, 71.460), (51.086, 71.440)],
    [(51.086, 71.390), (51.150, 71.392), (51.193, 71.385)],
]
for road in avenues:
    line(draw, road, CASING, 46)
for road in avenues:
    line(draw, road, MAJOR, 34)

img = img.resize((W, H), Image.LANCZOS).filter(ImageFilter.SMOOTH)
SRC.mkdir(exist_ok=True)
OUT.mkdir(parents=True, exist_ok=True)
img.save(SRC / "map_original.png", optimize=True)
for width in (840, 420):
    small = img.resize((width, round(width * H / W)), Image.LANCZOS)
    small.save(OUT / f"map-{width}.webp", quality=80, method=6)
print("map done")
