"""Просмотр: python3 preview.py out.png form1,form2,... [seed]"""
import sys, numpy as np
sys.path.insert(0, ".")
import forms, render
from PIL import Image

def col(h): return np.array(h)/255.0
STYLE = {
    "F": dict(spec=0.55, shin=60), "A": dict(spec=0.35, shin=40), "L": dict(spec=0.2, shin=18, wrap=0.6),
    "G": dict(spec=0.0, shin=10, emit=1.0), "R": dict(spec=0.05, shin=8), "C": dict(spec=0.0, shin=10, emit=1.0),
}
def layers_for(parts, c1, c2, style_over=None):
    leafc = c1*0.4 + np.array([70,150,80])/255*0.6
    colors = {"F": c1, "A": c2, "L": leafc, "G": np.minimum(1, c2*1.15 + 0.1), "R": c1*0.25 + np.array([40,38,50])/255*0.6,
              "C": np.minimum(1, c2 * 0.8 + 0.25)}
    out = []
    for role, m in parts.items():
        pr = dict(STYLE[role]); pr["color"] = colors[role]
        if style_over and role in style_over: pr.update(style_over[role])
        if role == "F" and "C" in parts: pr.update(alpha=0.55, spec=0.9, shin=90)
        out.append((m, pr))
    return out

if __name__ == "__main__":
    names = sys.argv[2].split(",")
    seed = int(sys.argv[3]) if len(sys.argv) > 3 else 1
    pal = [((107,159,237),(165,143,255)),((200,70,80),(250,150,120)),((90,190,120),(160,230,150)),((230,170,60),(255,230,140)),((70,200,220),(160,240,255)),((210,90,220),(250,170,255))]
    ims, labs = [], []
    for k, nme in enumerate(names):
        rng = np.random.default_rng(seed + k)
        parts = getattr(forms, nme)(rng, 0.5)
        tris = sum(m.tris() for m in parts.values())
        c1, c2 = pal[k % len(pal)]
        so = forms.STYLE.get(nme) if hasattr(forms, "STYLE") else None
        ims.append(render.render(layers_for(parts, col(c1), col(c2), so), size=300, ss=2))
        labs.append(f"{nme} {tris} tris")
    render.sheet(ims, labs, cols=3, tile=300).save(sys.argv[1])
    print("ok")
