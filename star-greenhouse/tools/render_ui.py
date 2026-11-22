"""Рисует интерфейс из выгрузки tools/sim/dump_ui.luau, как он выглядел бы на экране телефона.
python3 tools/render_ui.py ui.txt out_prefix [W H]"""
import json, os, re, sys
from PIL import Image, ImageDraw, ImageFont

W, H = (int(sys.argv[3]), int(sys.argv[4])) if len(sys.argv) > 4 else (844, 390)
SS = 2
ROOT = os.path.join(os.path.dirname(__file__), "..")
FONT_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FONT_M = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
ICONS = {}
for m in re.finditer(r'(\w+) = "rbxassetid://(\d+)"', open(os.path.join(ROOT, "src/shared/Config/Icons.luau"), encoding="utf8").read()):
    ICONS["rbxassetid://" + m.group(2)] = os.path.join(ROOT, "art/icons", m.group(1) + ".png")
_fonts = {}


def font(sz, medium=False):
    key = (int(sz), medium)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(FONT_M if medium else FONT_B, max(4, int(sz)))
    return _fonts[key]


def kid(node, cls):
    return [k for k in node["k"] if k["c"] == cls]


def first(node, cls):
    l = kid(node, cls)
    return l[0] if l else None


GUI = {"Frame", "TextLabel", "TextButton", "TextBox", "ImageLabel", "ImageButton", "ScrollingFrame", "ViewportFrame"}


def udim2(v, pw, ph):
    return v[0] * pw + v[1], v[2] * ph + v[3]


def col(c, t=0.0):
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(255 * (1 - t)))


class R:
    def __init__(self, x, y, w, h):
        self.x, self.y, self.w, self.h = x, y, w, h


def layout(node, rect, out, clip, z=0):
    """Расставляет детей узла; out получает (z-порядок, узел, прямоугольник, clip)."""
    pad = first(node, "UIPadding")
    cx, cy, cw, ch = rect.x, rect.y, rect.w, rect.h
    if pad:
        pt = pad.get("PaddingTop", [0, 0]); pb = pad.get("PaddingBottom", [0, 0]); pl = pad.get("PaddingLeft", [0, 0]); pr = pad.get("PaddingRight", [0, 0])
        cx += pl[0] * rect.w + pl[1]; cw -= (pl[0] + pr[0]) * rect.w + pl[1] + pr[1]
        cy += pt[0] * rect.h + pt[1]; ch -= (pt[0] + pb[0]) * rect.h + pt[1] + pb[1]
    kids = [k for k in node["k"] if k["c"] in GUI and k.get("Visible", True)]
    lst = first(node, "UIListLayout")
    grid = first(node, "UIGridLayout")
    rects = {}
    if lst or grid:
        kids_sorted = sorted(enumerate(kids), key=lambda e: (e[1].get("LayoutOrder", 0), e[0]))
        kids_sorted = [k for _, k in kids_sorted]
    if lst:
        horiz = lst.get("FillDirection") == "Horizontal"
        padv = lst.get("Padding", [0, 0])
        gap = padv[0] * (cw if horiz else ch) + padv[1]
        pos = 0
        sizes = []
        for k in kids_sorted:
            w, h = size_of(k, cw, ch)
            sizes.append((k, w, h))
        total = sum((w if horiz else h) for _, w, h in sizes) + gap * max(0, len(sizes) - 1)
        align = lst.get("HorizontalAlignment", "Left")
        start = 0
        if horiz and align == "Center":
            start = (cw - total) / 2
        for k, w, h in sizes:
            if horiz:
                rx, ry = cx + start + pos, cy
                pos += w + gap
            else:
                ox = 0 if align == "Left" else ((cw - w) / 2 if align == "Center" else cw - w)
                rx, ry = cx + ox, cy + pos
                pos += h + gap
            rects[id(k)] = R(rx, ry, w, h)
    elif grid:
        cs = grid.get("CellSize", [0, 100, 0, 100])
        cp = grid.get("CellPadding", [0, 5, 0, 5])
        w, h = cs[0] * cw + cs[1], cs[2] * ch + cs[3]
        gx, gy = cp[0] * cw + cp[1], cp[2] * ch + cp[3]
        per = max(1, int((cw + gx) // (w + gx)))
        align = grid.get("HorizontalAlignment", "Left")
        rowW = per * w + (per - 1) * gx
        ox = (cw - rowW) / 2 if align == "Center" else 0
        for i, k in enumerate(kids_sorted):
            r, c_ = divmod(i, per)
            rects[id(k)] = R(cx + ox + c_ * (w + gx), cy + r * (h + gy), w, h)
    for k in kids:
        if id(k) in rects:
            kr = rects[id(k)]
        else:
            w, h = size_of(k, cw, ch)
            px, py = udim2(k.get("Position", [0, 0, 0, 0]), cw, ch)
            ax, ay = k.get("AnchorPoint", [0, 0])
            kr = R(cx + px - ax * w, cy + py - ay * h, w, h)
        place(k, kr, out, clip, z)


def size_of(k, pw, ph):
    w, h = udim2(k.get("Size", [0, 0, 0, 0]), pw, ph)
    sc = first(k, "UISizeConstraint")
    if sc and "MaxSize" in sc:
        w, h = min(w, sc["MaxSize"][0]), min(h, sc["MaxSize"][1])
    auto = k.get("AutomaticSize", "None")
    if auto in ("Y", "XY"):
        h = max(h, content_extent(k, w, h)[1])
    return w, h


def content_extent(node, w, h):
    tmp = []
    layout(node, R(0, 0, w, h), tmp, None)
    mx = my = 0
    for _, n, r, _ in tmp:
        mx, my = max(mx, r.x + r.w), max(my, r.y + r.h)
    return mx, my


def place(node, rect, out, clip, z):
    out.append((z, node, rect, clip))
    newclip = clip
    if node["c"] == "ScrollingFrame":
        c = (rect.x, rect.y, rect.x + rect.w, rect.y + rect.h)
        newclip = c if clip is None else (max(c[0], clip[0]), max(c[1], clip[1]), min(c[2], clip[2]), min(c[3], clip[3]))
    layout(node, rect, out, newclip, z + 1)


def draw_node(img, node, r, clip):
    if r.w <= 0.5 or r.h <= 0.5:
        return
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    box = [r.x * SS, r.y * SS, (r.x + r.w) * SS, (r.y + r.h) * SS]
    corner = first(node, "UICorner")
    rad = 0
    if corner:
        cr = corner.get("CornerRadius", [0, 8])
        rad = (cr[0] * min(r.w, r.h) + cr[1]) * SS
        rad = min(rad, min(r.w, r.h) * SS / 2)
    bt = node.get("BackgroundTransparency", 0)
    cls = node["c"]
    if cls in ("Frame", "TextButton", "ScrollingFrame", "TextBox", "TextLabel", "ImageLabel", "ImageButton", "ViewportFrame") and bt < 0.99 and "BackgroundColor3" in node:
        fill = col(node["BackgroundColor3"], bt)
        grad = first(node, "UIGradient")
        if grad and isinstance(grad.get("Color"), list) and len(grad["Color"]) == 2:
            c1, c2 = grad["Color"]
            base = node["BackgroundColor3"]
            g = Image.new("RGBA", img.size, (0, 0, 0, 0))
            gd = ImageDraw.Draw(g)
            horiz = abs(grad.get("Rotation", 90)) < 45
            span = (box[2] - box[0]) if horiz else (box[3] - box[1])
            steps = max(2, int(span))
            for i in range(steps):
                t = i / (steps - 1)
                cc = [base[j] * (c1[j] * (1 - t) + c2[j] * t) for j in range(3)]
                if horiz:
                    gd.line([(box[0] + i, box[1]), (box[0] + i, box[3])], fill=col(cc, bt))
                else:
                    gd.line([(box[0], box[1] + i), (box[2], box[1] + i)], fill=col(cc, bt))
            m = Image.new("L", img.size, 0)
            ImageDraw.Draw(m).rounded_rectangle(box, radius=rad, fill=255)
            layer.paste(g, (0, 0), m)
        else:
            d.rounded_rectangle(box, radius=rad, fill=fill)
    stroke = [s for s in kid(node, "UIStroke") if s.get("ApplyStrokeMode") != "Contextual"]
    if stroke and cls != "TextLabel":
        s = stroke[0]
        th = max(1, s.get("Thickness", 1) * SS)
        d.rounded_rectangle(box, radius=rad, outline=col(s.get("Color", [0, 0, 0]), s.get("Transparency", 0)), width=int(round(th)))
    if cls == "ViewportFrame":
        cx, cy = (r.x + r.w / 2) * SS, (r.y + r.h / 2) * SS
        rr = min(r.w, r.h) * 0.32 * SS
        d.ellipse([cx - rr, cy - rr * 0.6, cx + rr, cy + rr * 1.0], fill=(110, 160, 140, 170))
        d.ellipse([cx - rr * 0.5, cy - rr * 1.1, cx + rr * 0.5, cy - rr * 0.1], fill=(200, 140, 200, 200))
    if cls in ("ImageLabel", "ImageButton") and node.get("Image") in ICONS:
        try:
            ic = Image.open(ICONS[node["Image"]]).convert("RGBA")
            s = int(min(r.w, r.h) * SS)
            if s > 0:
                ic = ic.resize((s, s), Image.LANCZOS)
                layer.alpha_composite(ic, (int(box[0] + (r.w * SS - s) / 2), int(box[1] + (r.h * SS - s) / 2)))
        except Exception:
            pass
    if cls in ("TextLabel", "TextButton", "TextBox") and node.get("Text"):
        txt = node["Text"].replace("<b>", "").replace("</b>", "")
        tc = col(node.get("TextColor3", [1, 1, 1]), node.get("TextTransparency", 0))
        medium = node.get("Font") in ("GothamMedium", "Gotham", "SourceSans")
        lim = first(node, "UITextSizeConstraint")
        maxs = lim.get("MaxTextSize", 100) if lim else 100
        size = node.get("TextSize", 14)
        lines = txt.split("\n")
        if node.get("TextScaled"):
            size = min(maxs, r.h / max(1, len(lines)) * 0.9)
            while size > 5:
                f = font(size * SS, medium)
                if all(f.getlength(l) <= r.w * SS for l in lines):
                    break
                size -= 0.5
        f = font(size * SS, medium)
        lh = size * SS * 1.15
        tot = lh * len(lines)
        ya = node.get("TextYAlignment", "Center")
        y0 = box[1] + ((r.h * SS - tot) / 2 if ya == "Center" else (0 if ya == "Top" else r.h * SS - tot))
        xa = node.get("TextXAlignment", "Center")
        hasStroke = any(s.get("ApplyStrokeMode") == "Contextual" for s in kid(node, "UIStroke"))
        for i, l in enumerate(lines):
            lw = f.getlength(l)
            x0 = box[0] + ((r.w * SS - lw) / 2 if xa == "Center" else (0 if xa == "Left" else r.w * SS - lw))
            if hasStroke:
                d.text((x0, y0 + i * lh), l, font=f, fill=tc, stroke_width=max(1, int(size * SS / 18)), stroke_fill=(6, 9, 18, 150))
            else:
                d.text((x0, y0 + i * lh), l, font=f, fill=tc)
    if clip is not None:
        mask = Image.new("L", img.size, 0)
        ImageDraw.Draw(mask).rectangle([clip[0] * SS, clip[1] * SS, clip[2] * SS, clip[3] * SS], fill=255)
        a = layer.split()[3]
        from PIL import ImageChops
        layer.putalpha(ImageChops.multiply(a, mask))
    img.alpha_composite(layer)


def render(guis, path):
    img = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 255))
    # фон: имитация космической сцены
    bg = ImageDraw.Draw(img)
    for y in range(H * SS):
        t = y / (H * SS)
        bg.line([(0, y), (W * SS, y)], fill=(int(20 + 30 * t), int(18 + 20 * t), int(40 + 25 * t), 255))
    guis = sorted(guis, key=lambda g: g.get("DisplayOrder", 0))
    for g in guis:
        if not g.get("Visible", True) or not g.get("Enabled", True):
            continue
        sc = first(g, "UIScale")
        s = sc.get("Scale", 1) if sc else 1
        out = []
        layout(g, R(0, 0, W / s, H / s), out, None)
        for z, n, r, clip in out:
            if s != 1:
                r = R(r.x * s, r.y * s, r.w * s, r.h * s)
                clip = None if clip is None else tuple(v * s for v in clip)
            draw_node(img, n, r, clip)
    img.convert("RGB").resize((W * SS // 2 * 2 // 2 * 1, H * SS // 2 * 2 // 2 * 1) if False else (W * 2, H * 2), Image.LANCZOS).save(path)


if __name__ == "__main__":
    pref = sys.argv[2]
    for line in open(sys.argv[1], encoding="utf8"):
        if line.startswith("UI|"):
            _, name, js = line.rstrip("\n").split("|", 2)
            guis = json.loads(js)
            render(guis, f"{pref}_{name}.png")
            print("ok", name)
