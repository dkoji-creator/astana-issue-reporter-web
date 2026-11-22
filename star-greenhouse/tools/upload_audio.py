"""Загружает art/audio/music_main.ogg и sfx_*.ogg как Audio-ассеты и пишет src/shared/Config/Audio.luau."""
import json, os, subprocess, sys, time
USER = sys.argv[1]


def curl(args):
    out = subprocess.run(["curl", "-sS", "-H", "x-api-key: proxy-injected", *args], capture_output=True, text=True)
    try:
        return json.loads(out.stdout or "{}")
    except Exception:
        return {"raw": out.stdout}


def upload(fn, title):
    req = json.dumps({"assetType": "Audio", "displayName": title, "description": "Star Greenhouse sound",
                      "creationContext": {"creator": {"userId": USER}}})
    op = curl(["-X", "POST", "https://apis.roblox.com/assets/v1/assets", "-F", f"request={req};type=application/json",
               "-F", f"fileContent=@art/audio/{fn};type=audio/ogg"])
    path = op.get("path")
    for _ in range(60):
        if not path:
            print("upload failed", fn, op)
            return None
        r = curl([f"https://apis.roblox.com/assets/v1/{path}"])
        if r.get("done"):
            return r.get("response", {}).get("assetId")
        time.sleep(2)
    return None


ids = {}
files = ["music_main.ogg"] + sorted(f for f in os.listdir("art/audio") if f.startswith("sfx_") and f.endswith(".ogg"))
for fn in files:
    ids[fn[:-4]] = upload(fn, "StarGreenhouse2 " + fn[:-4])
    print(fn, ids[fn[:-4]], flush=True)
SFX = {
    "reveal": "sfx_mutation", "harvest": "sfx_harvest", "harvestRare": "sfx_star", "coins": "sfx_coin", "legendary": "sfx_legendary",
    "click": "sfx_click", "plant": "sfx_plant", "water": "sfx_water", "star": "sfx_star", "meteor": "sfx_meteor", "rocket": "sfx_rocket",
    "unlock": "sfx_unlock", "tap": "sfx_tap", "mutation": "sfx_mutation", "pop": "sfx_pop", "error": "sfx_error", "boom": "sfx_boom",
    "laser": "sfx_laser", "beep": "sfx_beep", "go": "sfx_go", "whoosh": "sfx_whoosh", "chest": "sfx_chest", "brew": "sfx_brew",
}
lines = ["-- Звуки: музыка и эффекты (tools/make_music.py, tools/make_sfx.py; загружено tools/upload_audio.py).",
         "-- Всё рассчитано на динамик телефона: энергия в полосе 200-4000 Гц.", "return {", "\tMusic = {",
         f'\t\tmain = "rbxassetid://{ids["music_main"]}",', "\t},", "\tSfx = {"]
for k, v in SFX.items():
    lines.append(f'\t\t{k} = "rbxassetid://{ids.get(v) or ""}",')
lines += ["\t},", "}"]
open("src/shared/Config/Audio.luau", "w", encoding="utf8").write("\n".join(lines) + "\n")
print("written")
