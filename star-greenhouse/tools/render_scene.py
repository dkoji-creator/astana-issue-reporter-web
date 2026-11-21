"""Вид карты глазами игрока: python3 tools/render_scene.py world.txt out.png camX,camY,camZ tgtX,tgtY,tgtZ"""
import sys, numpy as np
sys.path.insert(0, __file__.rsplit("/", 1)[0])
from render_models import load, trace
parts = load(sys.argv[1])["world"]
cam = np.array([float(v) for v in sys.argv[3].split(",")])
tgt = np.array([float(v) for v in sys.argv[4].split(",")])
near = [p for p in parts if np.linalg.norm(p["pos"] - cam) - np.max(p["size"]) < (float(sys.argv[5]) if len(sys.argv) > 5 else 700)]
img = trace(near, cam, tgt - cam, 480, 270, fovdeg=70, bg=(0.05, 0.06, 0.12), ambient=0.3, fog=(max(900, float(sys.argv[5]) if len(sys.argv) > 5 else 700), (0.12, 0.13, 0.25)))
img.save(sys.argv[2])
print("ok", len(near))
