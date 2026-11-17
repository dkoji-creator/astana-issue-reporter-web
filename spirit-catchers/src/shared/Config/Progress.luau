-- Уровни, ежедневные награды, награды за коллекцию и облики фонаря.
local P = {}

-- опыт за пойманного духа по редкости
P.XP = { common = 4, uncommon = 8, rare = 16, epic = 30, legendary = 60 }
function P.xpToNext(level: number): number
	return 20 + level * 15
end
function P.levelReward(level: number): number
	return 20 + level * 10
end

-- ежедневный подарок: серия из 7 дней, потом заново
P.Daily = {
	{ coins = 30 },
	{ dust = 3 },
	{ coins = 60 },
	{ dust = 6 },
	{ coins = 120 },
	{ skin = "sakura", coins = 50 },
	{ coins = 250, dust = 12 },
}

-- награды за собранные виды (Атлас)
P.Milestones = {
	{ need = 3, coins = 50 },
	{ need = 6, coins = 150, skin = "jade" },
	{ need = 9, coins = 400, dust = 15 },
	{ need = 12, coins = 1000, skin = "golden" },
}

-- облики фонаря: цвет фонаря, цвет луча; price = монеты; source = где получить
P.SkinOrder = { "classic", "sakura", "moon", "jade", "ember", "golden" }
P.Skins = {
	classic = { name = "Классический", lamp = Color3.fromRGB(255, 225, 160), beam = Color3.fromRGB(255, 240, 200), price = 0 },
	sakura = { name = "Сакура", lamp = Color3.fromRGB(255, 150, 200), beam = Color3.fromRGB(255, 200, 230), source = "Подарок 6-го дня" },
	moon = { name = "Лунный", lamp = Color3.fromRGB(170, 210, 255), beam = Color3.fromRGB(200, 225, 255), price = 600 },
	jade = { name = "Нефритовый", lamp = Color3.fromRGB(110, 240, 170), beam = Color3.fromRGB(170, 255, 210), source = "6 видов в Атласе" },
	ember = { name = "Угольный", lamp = Color3.fromRGB(255, 110, 60), beam = Color3.fromRGB(255, 170, 120), price = 1200, dust = 20 },
	golden = { name = "Золотой", lamp = Color3.fromRGB(255, 200, 60), beam = Color3.fromRGB(255, 225, 130), source = "Все 12 видов" },
}

return P
