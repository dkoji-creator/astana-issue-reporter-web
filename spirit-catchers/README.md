# Spirit Catchers — прототип (бумажный лис)

Отдельный Roblox-проект (Rojo 7). Цикл: тень → посветить фонарём → удерживать «ЛОВИТЬ» рядом → алтарь (ProximityPrompt «Сохранить улов») → «Экипировать лиса».

Сборка: `rojo build default.project.json -o SpiritCatchers.rbxlx`
Публикация (Open Cloud): `POST https://apis.roblox.com/universes/v1/{universeId}/places/{placeId}/versions?versionType=Published`
с заголовком `x-api-key` и телом-файлом `.rbxlx` (`Content-Type: application/xml`).
