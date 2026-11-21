"""Загружает art/sky/*.png как Image-ассеты и пишет src/shared/Config/Sky.luau."""
import json, os, subprocess, sys, time
USER = sys.argv[1]


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except Exception:
        print("bad response", out.stdout[:200], out.stderr[:200])
        return {}


ids = {}
for face in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
    req = json.dumps({"assetType": "Image", "displayName": "StarGreenhouse sky " + face, "description": "Nebula skybox face",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@art/sky/{face}.png;type=image/png"])
    path = op.get("path")
    if not path:
        print(face, "upload failed", op)
        continue
    for _ in range(40):
        r = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if r.get("done"):
            ids[face] = r["response"]["assetId"]
            break
        time.sleep(1.5)
    print(face, ids.get(face))
lines = ["-- Небо: 6 граней туманности (art/sky, загружены как Image). Создано tools/upload_sky.py", "return {"]
for k in ("Ft", "Bk", "Lf", "Rt", "Up", "Dn"):
    if k in ids:
        lines.append(f'\t{k} = "rbxassetid://{ids[k]}",')
lines.append("}")
open("src/shared/Config/Sky.luau", "w", encoding="utf8").write("\n".join(lines) + "\n")
