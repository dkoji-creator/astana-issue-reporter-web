-- Уровни, ежедневные награды, награды за коллекцию и облики фонаря.
local P = {}

-- опыт за пойманного духа по редкости
P.XP = { common = 4, uncommon = 8, rare = 16, epic = 30, legendary = 60, mythic = 120, secret = 250 }
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
	{ need = 15, coins = 2500, dust = 40 },
	{ need = 18, coins = 6000, dust = 100 },
}

-- облики фонаря: цвет фонаря, цвет луча; price = монеты; source = где получить
P.SkinOrder = { "classic", "sakura", "moon", "jade", "ember", "golden", "vip" }
P.Skins = {
	classic = { name = "Классический", lamp = Color3.fromRGB(255, 225, 160), beam = Color3.fromRGB(255, 240, 200), price = 0 },
	sakura = { name = "Сакура", lamp = Color3.fromRGB(255, 150, 200), beam = Color3.fromRGB(255, 200, 230), source = "Подарок 6-го дня" },
	moon = { name = "Лунный", lamp = Color3.fromRGB(170, 210, 255), beam = Color3.fromRGB(200, 225, 255), price = 600 },
	jade = { name = "Нефритовый", lamp = Color3.fromRGB(110, 240, 170), beam = Color3.fromRGB(170, 255, 210), source = "6 видов в Атласе" },
	ember = { name = "Угольный", lamp = Color3.fromRGB(255, 110, 60), beam = Color3.fromRGB(255, 170, 120), price = 1200, dust = 20 },
	golden = { name = "Золотой", lamp = Color3.fromRGB(255, 200, 60), beam = Color3.fromRGB(255, 225, 130), source = "12 видов в Атласе" },
	vip = { name = "Радужный VIP", lamp = Color3.fromRGB(255, 120, 220), beam = Color3.fromRGB(200, 220, 255), source = "VIP-ловец", rainbow = true },
}

-- гифткоды (регистр не важен, каждый активируется один раз на аккаунт)
P.Codes = {
	BETA = { coins = 500, dust = 25, text = "Спасибо за бета-тест! +500 монет и +25 пыли" },
	WELCOME = { coins = 250, skin = "moon", text = "Добро пожаловать! +250 монет и Лунный фонарь" },
}

-- окно «Что нового»: показывается один раз после выхода обновления
P.NewsVersion = 2
P.News = {
	title = "Обновление 2: Сила ловца",
	lines = {
		"Таланты: очко за каждый уровень (кнопка «Сила»)",
		"Перерождение с 15 уровня: монеты +30% и удача +15% навсегда",
		"Удача: зелья, Красная луна, рулетка и разновидность «Бесконечный» 1 к 5000",
		"Духов стало меньше, они прячутся и появляются вдали от тебя",
		"Тень проявляется только узким лучом: свети и иди по следам",
		"Кусты-укрытия в роще и саду, ночь стала темнее",
		"Коды: BETA и WELCOME (Опции)",
	},
}

-- таланты: очко за каждый уровень, у каждого таланта 10 ступеней
P.TalentMax = 10
P.TalentOrder = { "swift", "sense", "grip", "fortune", "greed" }
P.Talents = {
	swift = { name = "Быстрые ноги", desc = "+1 к скорости бега", icon = "paw", color = Color3.fromRGB(90, 200, 255) },
	sense = { name = "Чутьё", desc = "Тени проявляются на 8% быстрее", icon = "target", color = Color3.fromRGB(170, 120, 255) },
	grip = { name = "Хватка", desc = "Зона в мини-игре больше на 4%", icon = "jar", color = Color3.fromRGB(110, 220, 140) },
	fortune = { name = "Фортуна", desc = "Удача +5%", icon = "luck", color = Color3.fromRGB(90, 230, 120) },
	greed = { name = "Жадность", desc = "Монеты +6%", icon = "coin", color = Color3.fromRGB(255, 200, 60) },
}
P.TalentResetDust = 100

-- перерождение: сброс уровня, монет, улучшений и талантов ради вечных множителей
P.Rebirth = {
	baseLevel = 15, stepLevel = 5, -- нужно уровня: 15, 20, 25...
	coins = 0.3, luck = 0.15, -- за каждое перерождение: монеты +30%, удача +15%
}
function P.rebirthLevel(n: number): number
	return P.Rebirth.baseLevel + n * P.Rebirth.stepLevel
end

return P
