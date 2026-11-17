-- Каталог духов, редкостей и прогресса. Общий для сервера и клиента.
local C = {}

C.Order = { "PaperFox", "Umbrella", "Firefly", "LanternSpirit", "Kodama", "Crane", "MoonRabbit", "GoldenCarp" }

C.Rarity = {
	common = { name = "Обычный", color = Color3.fromRGB(215, 215, 225), material = 1, catchTime = 1.5, revealTime = 0.35, shadow = Color3.fromRGB(80, 25, 140) },
	uncommon = { name = "Необычный", color = Color3.fromRGB(110, 200, 255), material = 2, catchTime = 2.0, revealTime = 0.5, shadow = Color3.fromRGB(25, 70, 170) },
	rare = { name = "Редкий", color = Color3.fromRGB(120, 255, 170), material = 4, catchTime = 2.6, revealTime = 0.7, shadow = Color3.fromRGB(10, 120, 95) },
	epic = { name = "Эпический", color = Color3.fromRGB(255, 120, 220), material = 8, catchTime = 3.0, revealTime = 0.8, shadow = Color3.fromRGB(150, 20, 120) },
	legendary = { name = "Легендарный", color = Color3.fromRGB(255, 200, 80), material = 15, catchTime = 3.5, revealTime = 0, shadow = Color3.fromRGB(170, 120, 10) },
}

-- move: walk | float | fly | swim; height — над землёй
C.Kinds = {
	PaperFox = { name = "Бумажный лис", icon = "🦊", rarity = "common", move = "walk", speed = 6, height = 0,
		hint = "Улица фонарей и берега канала", follow = 0.45, animSpeed = 9 },
	Umbrella = { name = "Зонтик-каса", icon = "☂️", rarity = "common", move = "walk", speed = 5, height = 0,
		hint = "Берега канала, прыгает у воды", follow = 0.5, animSpeed = 6 },
	Firefly = { name = "Светлячок", icon = "✨", rarity = "common", move = "float", speed = 4, height = 2.5,
		hint = "Храмовый сад", follow = 0.8, animSpeed = 8 },
	LanternSpirit = { name = "Дух-фонарь", icon = "🏮", rarity = "uncommon", move = "float", speed = 4, height = 1,
		hint = "Улица фонарей, танцует под гирляндами", follow = 0.5, animSpeed = 5 },
	Kodama = { name = "Моховичок", icon = "🌿", rarity = "uncommon", move = "walk", speed = 3, height = 0,
		hint = "Храмовый сад, у деревьев", follow = 0.6, animSpeed = 4 },
	Crane = { name = "Бумажный журавлик", icon = "🕊️", rarity = "rare", move = "fly", speed = 8, height = 6,
		hint = "Храмовый сад, чаще в Красную луну", follow = 0.5, animSpeed = 5 },
	MoonRabbit = { name = "Лунный кролик", icon = "🐇", rarity = "epic", move = "walk", speed = 7, height = 0,
		hint = "Только в Красную луну: улица и сад", follow = 0.5, animSpeed = 6, moonOnly = true },
	GoldenCarp = { name = "Золотой карп", icon = "🐟", rarity = "legendary", move = "swim", speed = 0, height = 0,
		hint = "Только в Красную луну: над каналом", follow = 0.3, animSpeed = 3, moonOnly = true },
}

C.JarCap = { 3, 5, 7, 10 }
C.LanternRange = { 30, 36, 42, 50 }
C.LanternSpeed = { 1, 1.2, 1.4, 1.65 }
C.UpgradeCost = { 5, 12, 25 }
C.MaxLevel = 4
C.GardenNeed = 3
C.CatchRange = 14
C.CarpCatchRange = 20

C.DistrictNames = {
	street = "Улица бумажных фонарей",
	plaza = "Площадь алтаря",
	canal = "Канал с мостами",
	garden = "Храмовый сад",
}

function C.district(z: number): string
	if z > 30 then
		return "street"
	elseif z > -8 then
		return "plaza"
	elseif z > -72 then
		return "canal"
	end
	return "garden"
end

function C.catchRange(kind: string): number
	return kind == "GoldenCarp" and C.CarpCatchRange or C.CatchRange
end

return C
