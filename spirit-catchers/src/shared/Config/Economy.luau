-- Редкости, валюта, улучшения и заказы.
local E = {}

E.Rarity = {
	common = { name = "Обычный", color = Color3.fromRGB(215, 215, 225), coins = 5, dust = 1, catchTime = 1.5, revealTime = 0.35, shadow = Color3.fromRGB(70, 30, 120) },
	uncommon = { name = "Необычный", color = Color3.fromRGB(110, 200, 255), coins = 12, dust = 2, catchTime = 2.0, revealTime = 0.5, shadow = Color3.fromRGB(30, 70, 160) },
	rare = { name = "Редкий", color = Color3.fromRGB(120, 255, 170), coins = 30, dust = 4, catchTime = 2.6, revealTime = 0.7, shadow = Color3.fromRGB(15, 110, 90) },
	epic = { name = "Эпический", color = Color3.fromRGB(255, 120, 220), coins = 70, dust = 8, catchTime = 3.0, revealTime = 0.8, shadow = Color3.fromRGB(140, 25, 115) },
	legendary = { name = "Легендарный", color = Color3.fromRGB(255, 200, 80), coins = 200, dust = 15, catchTime = 3.5, revealTime = 0.9, shadow = Color3.fromRGB(160, 115, 15) },
	mythic = { name = "Мифический", color = Color3.fromRGB(255, 90, 70), coins = 400, dust = 25, catchTime = 4.0, revealTime = 1.0, shadow = Color3.fromRGB(150, 30, 20) },
	secret = { name = "Секретный", color = Color3.fromRGB(60, 255, 220), coins = 1000, dust = 50, catchTime = 4.5, revealTime = 1.2, shadow = Color3.fromRGB(10, 90, 90) },
}
E.RarityOrder = { "common", "uncommon", "rare", "epic", "legendary", "mythic", "secret" }
-- сложность мини-игры ловли: скорость и рывки метки духа
E.Struggle = {
	common = { speed = 0.55, jitter = 0.25 }, uncommon = { speed = 0.75, jitter = 0.35 }, rare = { speed = 0.95, jitter = 0.45 },
	epic = { speed = 1.15, jitter = 0.6 }, legendary = { speed = 1.3, jitter = 0.7 }, mythic = { speed = 1.5, jitter = 0.8 },
	secret = { speed = 1.7, jitter = 0.95 },
}

-- разновидности: выпадают при появлении духа, видны всем игрокам
E.VariantOrder = { "normal", "giant", "shiny", "shadow", "golden", "rainbow", "infinity" }
E.Variants = {
	normal = { name = "Обычный", chance = 0, mult = 1, color = Color3.fromRGB(200, 200, 210) },
	giant = { name = "Гигант", chance = 1 / 12, mult = 2, scale = 1.6, color = Color3.fromRGB(120, 200, 255) },
	shiny = { name = "Сияющий", chance = 1 / 25, mult = 3, color = Color3.fromRGB(255, 250, 180) },
	shadow = { name = "Теневой", chance = 1 / 30, mult = 5, moonOnly = true, color = Color3.fromRGB(150, 80, 255) },
	golden = { name = "Золотой", chance = 1 / 80, mult = 6, color = Color3.fromRGB(255, 200, 40) },
	rainbow = { name = "Радужный", chance = 1 / 250, mult = 15, color = Color3.fromRGB(255, 100, 200) },
	infinity = { name = "Бесконечный", chance = 1 / 5000, mult = 100, color = Color3.fromRGB(120, 230, 255) },
}

-- удача: умножает шанс редкой разновидности при поимке (бросок на сервере)
E.Luck = {
	perLevel = 0.02, levelCap = 1, -- +2% за уровень, максимум +100%
	pass = 1.5, -- «Удача ловца»
	potion = 2, potionMinutes = 15, potionDust = 40, -- зелье удачи
	moon = 1.5, -- Красная луна
	announceLocal = 80, -- объявить на сервере, если шанс 1 к 80 и реже
	announceGlobal = 250, -- объявить на всех серверах
}

E.MaxLevel = 12
E.Upgrades = {
	jar = {
		name = "Банка", desc = "Больше духов за вылазку",
		values = { 3, 5, 7, 10, 14, 17, 20, 24, 28, 32, 36, 40 },
		coins = { 40, 120, 300, 700, 2000, 5000, 12000, 30000, 70000, 150000, 300000 },
		dust = { 0, 5, 15, 30, 40, 55, 75, 100, 130, 170, 220 },
		fmt = "%d духов",
	},
	range = {
		name = "Ширина луча", desc = "Дальше и шире светит фонарь",
		values = { 30, 36, 42, 50, 58, 63, 68, 73, 78, 83, 88, 93 },
		coins = { 30, 100, 250, 600, 1800, 4500, 10000, 25000, 60000, 130000, 260000 },
		dust = { 0, 4, 12, 25, 35, 50, 70, 90, 120, 160, 200 },
		fmt = "%d м",
	},
	power = {
		name = "Сила света", desc = "Быстрее проявляет тени и ловит",
		values = { 1, 1.2, 1.4, 1.65, 1.9, 2.1, 2.3, 2.5, 2.7, 2.9, 3.1, 3.3 },
		coins = { 30, 100, 250, 600, 1800, 4500, 10000, 25000, 60000, 130000, 260000 },
		dust = { 0, 4, 12, 25, 35, 50, 70, 90, 120, 160, 200 },
		fmt = "x%.2g",
	},
}
E.UpgradeOrder = { "jar", "range", "power" }

E.GardenNeed = 3
E.CatchRange = 14
E.SwimCatchRange = 20

-- Заказы алтаря: два активных, обновляются после выполнения
E.OrderSlots = 2

return E
