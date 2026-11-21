"""Загружает art/planets/{gas,earth,moon}.png как Image-ассеты и пишет src/shared/Config/Planets.luau."""
import json, subprocess, sys, time
USER = sys.argv[1]


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except Exception:
        print("bad response", out.stdout[:200])
        return {}


ids = {}
for name in ("gas", "earth", "moon"):
    req = json.dumps({"assetType": "Image", "displayName": "StarGreenhouse planet " + name, "description": "Backdrop planet",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@art/planets/{name}.png;type=image/png"])
    path = op.get("path")
    if not path:
        print(name, "failed", op)
        continue
    for _ in range(40):
        r = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if r.get("done"):
            ids[name] = r["response"]["assetId"]
            break
        time.sleep(1.5)
    print(name, ids.get(name))
lines = ["-- Планеты фона (art/planets, Image-ассеты). Создано tools/upload_planets.py", "return {"]
for k in ("gas", "earth", "moon"):
    if k in ids:
        lines.append(f'\t{k} = "rbxassetid://{ids[k]}",')
lines.append("}")
open("src/shared/Config/Planets.luau", "w", encoding="utf8").write("\n".join(lines) + "\n")
