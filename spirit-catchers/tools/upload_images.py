"""Загружает art/icons/*.png как Image-ассеты и пишет src/shared/Config/Icons.luau."""
import json, os, subprocess, sys, time
USER = sys.argv[1]


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    return json.loads(out.stdout or "{}")


ids = {}
for fn in sorted(os.listdir("art/icons")):
    name = fn[:-4]
    req = json.dumps({"assetType": "Image", "displayName": "SpiritCatchers icon " + name, "description": "Spirit Catchers UI icon",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@art/icons/{fn};type=image/png"])
    path = op["path"]
    for _ in range(30):
        r = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if r.get("done"):
            ids[name] = r["response"]["assetId"]
            break
        time.sleep(1.5)
    print(name, ids.get(name))
lines = ["-- Иконки интерфейса (art/icons, загружены как Image-ассеты). Создано tools/upload_images.py", "return {"]
for k in sorted(ids):
    lines.append(f'\t{k} = "rbxassetid://{ids[k]}",')
lines.append("}")
open("src/shared/Config/Icons.luau", "w", encoding="utf8").write("\n".join(lines) + "\n")
