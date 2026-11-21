"""Загружает art/plants/<planet>.glb как Model-ассеты и пишет src/shared/Config/PlantMeshes.luau.
python3 tools/upload_meshes.py <userId> [planet ...]"""
import json, os, subprocess, sys, time
USER = sys.argv[1]
want = sys.argv[2:]
PLANETS = ["moon", "mars", "europa", "io", "nebula", "core"]
CFG = "src/shared/Config/PlantMeshes.luau"


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except Exception:
        print("bad response", out.stdout[:300])
        return {}


ids = {}
if os.path.exists(CFG):
    for line in open(CFG, encoding="utf8"):
        if "rbxassetid" in line or "=" in line and line.strip().startswith(tuple(PLANETS)):
            parts = line.strip().rstrip(",").split("=")
            if len(parts) == 2 and parts[0].strip() in PLANETS:
                ids[parts[0].strip()] = parts[1].strip()
for pl in PLANETS:
    if want and pl not in want:
        continue
    path = f"art/plants/{pl}.glb"
    req = json.dumps({"assetType": "Model", "displayName": f"StarGreenhouse plants {pl}", "description": "Procedural plant meshes",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@{path};type=model/gltf-binary"])
    p = op.get("path")
    if not p:
        print(pl, "upload failed", op)
        continue
    for _ in range(80):
        r = curl([f"https://apis.roblox.com/assets/v1/{p}"])
        if r.get("done"):
            if "response" in r:
                ids[pl] = r["response"]["assetId"]
            else:
                print(pl, "ERROR", r.get("error"))
            break
        time.sleep(2)
    print(pl, ids.get(pl), flush=True)
lines = ["-- Модели растений (по одной на планету), загружаются tools/upload_meshes.py", "return {"]
for pl in PLANETS:
    if pl in ids:
        lines.append(f"\t{pl} = {ids[pl]},")
lines.append("}")
open(CFG, "w", encoding="utf8").write("\n".join(lines) + "\n")
