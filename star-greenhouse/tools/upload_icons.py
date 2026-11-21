"""Загружает art/icons/*.png как Image-ассеты и пишет src/shared/Config/Icons.luau."""
import json, os, subprocess, sys, time
USER = sys.argv[1]


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except Exception:
        return {}


ids = {}
for fn in sorted(os.listdir("art/icons")):
    if fn.startswith("_") or not fn.endswith(".png"):
        continue
    name = fn[:-4]
    req = json.dumps({"assetType": "Image", "displayName": "StarGreenhouse icon " + name, "description": "UI icon",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@art/icons/{fn};type=image/png"])
    path = op.get("path")
    for _ in range(40):
        if not path:
            break
        r = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if r.get("done"):
            ids[name] = r.get("response", {}).get("assetId")
            break
        time.sleep(1.5)
    print(name, ids.get(name), flush=True)
lines = ["-- Иконки интерфейса (art/icons, Image-ассеты). Создано tools/upload_icons.py", "return {"]
for k in sorted(ids):
    if ids[k]:
        lines.append(f'\t{k} = "rbxassetid://{ids[k]}",')
lines.append("}")
open("src/shared/Config/Icons.luau", "w", encoding="utf8").write("\n".join(lines) + "\n")
