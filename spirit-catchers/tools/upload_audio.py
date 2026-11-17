"""Загружает audio/*.ogg в Roblox (Open Cloud Assets API) и прописывает id в src/shared/Config/Audio.luau.
Нужен ключ с правами asset:read и asset:write (ключ подставляет сетевой прокси сессии).
Запуск из папки spirit-catchers: python3 tools/upload_audio.py <userId>
"""
import json, re, subprocess, sys, time

USER = sys.argv[1]
FILES = {
    "Music.lantern": "music_lantern", "Music.moonLayer": "music_moon_layer",
    "Sfx.reveal": "sfx_reveal", "Sfx.catch": "sfx_catch", "Sfx.catchRare": "sfx_catch_rare",
    "Sfx.save": "sfx_save", "Sfx.legendary": "sfx_legendary", "Sfx.oniWarn": "sfx_oni_warn",
    "Sfx.oniHit": "sfx_oni_hit", "Sfx.click": "sfx_click",
    "Spirit.BellTanuki": "spirit_tanuki", "Spirit.Crane": "spirit_crane", "Spirit.InkSnake": "spirit_ink",
    "Spirit.MoonRabbit": "spirit_rabbit", "Spirit.FoxFire": "spirit_foxfire", "Spirit.GoldenCarp": "spirit_carp",
}


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    return json.loads(out.stdout or "{}")


def upload(name):
    req = json.dumps({"assetType": "Audio", "displayName": "SpiritCatchers " + name,
                      "description": "Spirit Catchers original audio",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets",
               "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@audio/{name}.ogg;type=audio/ogg"])
    path = op.get("path")
    if not path:
        raise SystemExit(f"{name}: {op}")
    for _ in range(30):
        res = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if res.get("done"):
            return res["response"]["assetId"]
        time.sleep(2)
    raise SystemExit(f"{name}: timeout")


cfg = open("src/shared/Config/Audio.luau", encoding="utf8").read()
for key, name in FILES.items():
    section, field = key.split(".")
    aid = upload(name)
    print(key, aid)
    block = re.search(section + r" = \{.*?\n\t\}", cfg, re.S)
    new = re.sub(r"(\b" + field + r' = )""', r'\g<1>"rbxassetid://' + aid + '"', block.group(0), count=1)
    cfg = cfg.replace(block.group(0), new)
open("src/shared/Config/Audio.luau", "w", encoding="utf8").write(cfg)
print("done")
