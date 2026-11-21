# Запусти фонарик (Lantern Launch) — состояние

Отдельная игра, не связанная со Spirit Catchers (тот в ../spirit-catchers). Использует те же модели духов (35 штук).

## Идея
Зажми кнопку ЗАПУСК, полоска силы ходит вверх-вниз, отпусти в нужный момент: фонарик летит вдаль и приманивает духа.
Чем дальше упал фонарик, тем реже дух (5 зон: Луг зари 0-150 м, Бамбуковый лес, Зеркальное озеро, Лунные горы, Небесный рынок до 1300 м).
Сервер сам считает силу по времени между Charge и Throw (клиент силу не присылает).

## Что внутри
- Улучшения за монеты: сила броска, удача, монеты, скорость, связка фонариков (до 6 за запуск), авто-запуск.
- Коллекция духов с разновидностями (до «Бесконечного» 1 к 5000), награды за 3/6/10/15/20/25/30 видов выдаются сами.
- Подарок дня (серия), коды LAUNCH и TIKTOK, зелье удачи (донат), админка владельца (UserId 8432365972).
- Кинематографичное раскрытие для легендарных и реже; столб света над находкой; объявление на весь сервер о редких находках.
- Сохранение: DataStore `LanternLaunch_v1`.

## Как собирать и публиковать
- Сборка: `/tmp/rojo/rojo build -o LanternLaunch.rbxlx` (в папке lantern-launch)
- Проверка (обязательна): `node tools/sim/run.mjs` (нужен symlink tools/sim/node_modules на luau-web), должно быть «0 ошибок»
- Публикация: `POST https://apis.roblox.com/universes/v1/<UNIVERSE>/places/<PLACE>/versions?versionType=Published` с `x-api-key` и телом `.rbxlx`, `Content-Type: application/xml`
- Просмотр без Studio: `SCENARIO=tools/sim/dump_world.luau node tools/sim/run.mjs > w.txt`, затем `python3 tools/render_scene.py w.txt out.png camX,Y,Z tgtX,Y,Z`

## Что осталось сделать
1. Создать опыт в Creator Hub, получить PLACE и UNIVERSE ID, добавить опыт в API-ключ (universe-places write, developer-products write).
2. Опубликовать, создать донат-товары и вписать их id в src/shared/Game.luau (`G.Products`, id = 0 скрывает кнопку).
3. Доступ к звукам: аудио 79093164547792 и звуки Spirit Catchers нужно разрешить для нового опыта (Creator Hub, Permissions), иначе звука не будет.
4. Название, иконка, обложка, возрастная анкета.
