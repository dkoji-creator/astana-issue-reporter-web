-- Редкости, валюта, улучшения и заказы.
local E = {}

E.Rarity = {
	common = { name = "Обычный", color = Color3.fromRGB(215, 215, 225), coins = 5, dust = 1, catchTime = 1.5, revealTime = 0.35, shadow = Color3.fromRGB(70, 30, 120) },
	uncommon = { name = "Необычный", color = Color3.fromRGB(110, 200, 255), coins = 12, dust = 2, catchTime = 2.0, revealTime = 0.5, shadow = Color3.fromRGB(30, 70, 160) },
	rare = { name = "Редкий", color = Color3.fromRGB(120, 255, 170), coins = 30, dust = 4, catchTime = 2.6, revealTime = 0.7, shadow = Color3.fromRGB(15, 110, 90) },
	epic = { name = "Эпический", color = Color3.fromRGB(255, 120, 220), coins = 70, dust = 8, catchTime = 3.0, revealTime = 0.8, shadow = Color3.fromRGB(140, 25, 115) },
	legendary = { name = "Легендарный", color = Color3.fromRGB(255, 200, 80), coins = 200, dust = 15, catchTime = 3.5, revealTime = 0, shadow = Color3.fromRGB(160, 115, 15) },
}
E.RarityOrder = { "common", "uncommon", "rare", "epic", "legendary" }

E.MaxLevel = 5
E.Upgrades = {
	jar = {
		name = "Банка", desc = "Больше духов за вылазку",
		values = { 3, 5, 7, 10, 14 }, coins = { 40, 120, 300, 700 }, dust = { 0, 5, 15, 30 },
		fmt = "%d духов",
	},
	range = {
		name = "Ширина луча", desc = "Дальше и шире светит фонарь",
		values = { 30, 36, 42, 50, 58 }, coins = { 30, 100, 250, 600 }, dust = { 0, 4, 12, 25 },
		fmt = "%d м",
	},
	power = {
		name = "Сила света", desc = "Быстрее проявляет тени и ловит",
		values = { 1, 1.2, 1.4, 1.65, 1.9 }, coins = { 30, 100, 250, 600 }, dust = { 0, 4, 12, 25 },
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
