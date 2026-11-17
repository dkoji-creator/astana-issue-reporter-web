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

-- облики фонаря: цвет фонаря и луча + спецэффекты (частицы, шлейф, ореол), видны всем игрокам.
-- price = монеты (dust = пыль); source = где получить; tier = ценность облика (подпись в магазине)
-- fx: tex = sparkles | fire | smoke, colors = цвета частиц, rate/size/life/speed, up = подъём (+) или падение (-),
--     trail = цвета шлейфа при беге, aura = большой мягкий свет вокруг игрока, burst = вспышка при поимке духа
P.SkinOrder = { "classic", "sakura", "moon", "jade", "sea", "ember", "autumn", "maple", "golden", "fog", "ghost", "harvest", "dragon", "aurora", "vip" }
local rgb = Color3.fromRGB
P.SkinTiers = {
	common = { name = "Обычный", color = rgb(190, 195, 215) },
	rare = { name = "Редкий", color = rgb(90, 170, 255) },
	epic = { name = "Эпический", color = rgb(190, 110, 255) },
	legendary = { name = "Легендарный", color = rgb(255, 190, 60) },
	mythic = { name = "Мифический", color = rgb(255, 80, 110) },
	vip = { name = "VIP", color = rgb(255, 120, 220) },
}
P.Skins = {
	classic = { name = "Классический", tier = "common", lamp = rgb(255, 225, 160), beam = rgb(255, 240, 200), price = 0,
		desc = "Тёплые искорки",
		fx = { tex = "sparkles", colors = { rgb(255, 220, 150) }, rate = 3, size = 0.25, life = 1.2, speed = 0.5, up = 1 } },
	sakura = { name = "Сакура", tier = "rare", lamp = rgb(255, 150, 200), beam = rgb(255, 200, 230), source = "Подарок 6-го дня",
		desc = "Кружатся лепестки, розовый шлейф",
		fx = { tex = "sparkles", colors = { rgb(255, 170, 210), rgb(255, 230, 240) }, rate = 9, size = 0.45, life = 2.5, speed = 1, up = -1.5,
			trail = { rgb(255, 150, 200), rgb(255, 230, 240) } } },
	moon = { name = "Лунный", tier = "rare", lamp = rgb(170, 210, 255), beam = rgb(200, 225, 255), price = 600,
		desc = "Лунная пыль и серебристый шлейф",
		fx = { tex = "sparkles", colors = { rgb(190, 220, 255), rgb(255, 255, 255) }, rate = 10, size = 0.35, life = 1.8, speed = 0.8, up = 0.5,
			trail = { rgb(170, 210, 255), rgb(255, 255, 255) } } },
	jade = { name = "Нефритовый", tier = "epic", lamp = rgb(110, 240, 170), beam = rgb(170, 255, 210), source = "6 видов в Атласе",
		desc = "Зелёные огоньки поднимаются вверх",
		fx = { tex = "sparkles", colors = { rgb(110, 255, 170), rgb(220, 255, 230) }, rate = 14, size = 0.4, life = 2, speed = 1.5, up = 3,
			trail = { rgb(110, 240, 170), rgb(40, 120, 80) } } },
	sea = { name = "Морской", tier = "epic", lamp = rgb(90, 220, 230), beam = rgb(170, 240, 255), source = "Достижение: 10 видов",
		desc = "Пузырьки и морская волна за спиной",
		fx = { tex = "sparkles", colors = { rgb(120, 230, 255), rgb(220, 250, 255) }, rate = 12, size = 0.5, life = 2.2, speed = 1, up = 2.5,
			trail = { rgb(60, 200, 230), rgb(20, 80, 160) } } },
	ember = { name = "Угольный", tier = "epic", lamp = rgb(255, 110, 60), beam = rgb(255, 170, 120), price = 1200, dust = 20,
		desc = "Живой огонь и летящие угольки",
		fx = { tex = "fire", colors = { rgb(255, 200, 80), rgb(255, 70, 30) }, rate = 18, size = 0.6, life = 0.9, speed = 1.5, up = 4,
			trail = { rgb(255, 150, 50), rgb(160, 30, 20) } } },
	golden = { name = "Золотой", tier = "legendary", lamp = rgb(255, 200, 60), beam = rgb(255, 225, 130), source = "12 видов в Атласе",
		desc = "Золотой дождь, ореол и вспышка при поимке",
		fx = { tex = "sparkles", colors = { rgb(255, 225, 100), rgb(255, 170, 30) }, rate = 22, size = 0.5, life = 1.6, speed = 2, up = -2,
			trail = { rgb(255, 215, 80), rgb(200, 120, 20) }, aura = true, burst = true } },
	fog = { name = "Туманный", tier = "legendary", lamp = rgb(200, 210, 230), beam = rgb(230, 235, 245), source = "Достижение: 1000 духов",
		desc = "Тянет за собой клубы тумана",
		fx = { tex = "smoke", colors = { rgb(210, 220, 235), rgb(150, 160, 190) }, rate = 8, size = 1.6, life = 3, speed = 0.6, up = 0.4,
			trail = { rgb(220, 225, 240), rgb(120, 130, 160) }, aura = true } },
	ghost = { name = "Призрачный", tier = "legendary", lamp = rgb(90, 255, 230), beam = rgb(150, 255, 240), price = 4000, dust = 80,
		desc = "Бирюзовое призрачное пламя и ореол",
		fx = { tex = "fire", colors = { rgb(120, 255, 240), rgb(40, 120, 255) }, rate = 20, size = 0.7, life = 1.1, speed = 1.2, up = 3,
			trail = { rgb(90, 255, 230), rgb(40, 60, 200) }, aura = true, burst = true } },
	dragon = { name = "Драконий", tier = "mythic", lamp = rgb(255, 60, 60), beam = rgb(255, 140, 90), source = "Достижение: Новая жизнь",
		desc = "Огненный шлейф дракона и снопы искр",
		fx = { tex = "fire", colors = { rgb(255, 230, 120), rgb(255, 40, 40) }, rate = 30, size = 0.9, life = 1, speed = 2.5, up = 5,
			trail = { rgb(255, 200, 60), rgb(200, 20, 30) }, aura = true, burst = true } },
	autumn = { name = "Осенний", tier = "rare", lamp = rgb(255, 160, 70), beam = rgb(255, 210, 150), source = "Сезон 1, уровень 5",
		desc = "Падают оранжевые листья",
		fx = { tex = "sparkles", colors = { rgb(255, 150, 50), rgb(220, 90, 40) }, rate = 10, size = 0.5, life = 2.6, speed = 0.8, up = -1.8,
			trail = { rgb(255, 160, 70), rgb(160, 70, 30) } } },
	maple = { name = "Кленовый", tier = "epic", lamp = rgb(230, 60, 50), beam = rgb(255, 150, 120), source = "Сезон 1, уровень 15",
		desc = "Вихрь красных кленовых листьев",
		fx = { tex = "sparkles", colors = { rgb(240, 60, 50), rgb(255, 170, 60) }, rate = 18, size = 0.6, life = 2.2, speed = 2.2, up = -1,
			trail = { rgb(230, 60, 50), rgb(255, 170, 60) } } },
	harvest = { name = "Урожайная луна", tier = "legendary", lamp = rgb(255, 190, 90), beam = rgb(255, 230, 170), source = "Сезон 1, уровень 25",
		desc = "Огромный ореол полной луны и золотые искры",
		fx = { tex = "sparkles", colors = { rgb(255, 230, 150), rgb(255, 160, 60) }, rate = 24, size = 0.55, life = 1.8, speed = 1.6, up = 1.5,
			trail = { rgb(255, 210, 120), rgb(200, 110, 30) }, aura = true, burst = true } },
	aurora = { name = "Северное сияние", tier = "mythic", lamp = rgb(120, 255, 200), beam = rgb(170, 220, 255), source = "Сезон 1, уровень 30",
		desc = "Переливы сияния: зелёный, бирюзовый, фиолетовый",
		fx = { tex = "sparkles", colors = { rgb(90, 255, 160), rgb(80, 200, 255), rgb(190, 110, 255) }, rate = 30, size = 0.6, life = 2.2, speed = 2, up = 2,
			trail = { rgb(90, 255, 160), rgb(80, 200, 255), rgb(190, 110, 255) }, aura = true, burst = true } },
	vip = { name = "Радужный VIP", tier = "vip", lamp = rgb(255, 120, 220), beam = rgb(200, 220, 255), source = "VIP-ловец", rainbow = true,
		desc = "Радужные звёзды, радужный шлейф, ореол и салют при поимке",
		fx = { tex = "sparkles", colors = { rgb(255, 80, 80), rgb(255, 200, 60), rgb(80, 255, 120), rgb(80, 160, 255), rgb(220, 90, 255) },
			rate = 35, size = 0.6, life = 2, speed = 3, up = 1.5,
			trail = { rgb(255, 80, 80), rgb(255, 220, 60), rgb(80, 255, 120), rgb(80, 160, 255), rgb(220, 90, 255) }, aura = true, burst = true } },
}

-- гифткоды (регистр не важен, каждый активируется один раз на аккаунт)
P.Codes = {
	BETA = { coins = 500, dust = 25, text = "Спасибо за бета-тест! +500 монет и +25 пыли" },
	WELCOME = { coins = 250, skin = "moon", text = "Добро пожаловать! +250 монет и Лунный фонарь" },
	UPDATE3 = { coins = 1000, dust = 30, text = "Обновление 3! +1000 монет и +30 пыли" },
}

-- окно «Что нового»: показывается один раз после выхода обновления
P.NewsVersion = 3
P.News = {
	title = "Обновление 3: Туманный порт",
	lines = {
		"Районы открываются по уровню: Канал 3, Рынок 6, Роща 10, Сад 15, Порт 20",
		"Чем дальше район, тем реже духи и выше удача района (до x3)",
		"Новый район Туманный порт: пирсы, маяк, Бумажный кит и Туманный кракен",
		"Духи живут в логовах: у фонарей, у воды, в кустах, у прилавков",
		"Событие «Туманная ночь» чередуется с Красной луной",
		"Ранги ловца, 14 достижений, сундук каждые 5 уровней, 2 новых таланта",
		"Код UPDATE3 (Опции)",
	},
}

-- таланты: очко за каждый уровень, у каждого таланта 10 ступеней
P.TalentMax = 10
P.TalentOrder = { "swift", "sense", "grip", "fortune", "greed", "stealth", "collector" }
P.Talents = {
	swift = { name = "Быстрые ноги", desc = "+1 к скорости бега", icon = "paw", color = Color3.fromRGB(90, 200, 255) },
	sense = { name = "Чутьё", desc = "Тени проявляются на 8% быстрее", icon = "target", color = Color3.fromRGB(170, 120, 255) },
	grip = { name = "Хватка", desc = "Зона в мини-игре больше на 4%", icon = "jar", color = Color3.fromRGB(110, 220, 140) },
	fortune = { name = "Фортуна", desc = "Удача +5%", icon = "luck", color = Color3.fromRGB(90, 230, 120) },
	greed = { name = "Жадность", desc = "Монеты +6%", icon = "coin", color = Color3.fromRGB(255, 200, 60) },
	stealth = { name = "Тихий шаг", desc = "Проявленные духи подпускают ближе", icon = "paw", color = Color3.fromRGB(150, 150, 200) },
	collector = { name = "Сборщик", desc = "Пыль за дубликаты +10%", icon = "dust", color = Color3.fromRGB(190, 130, 255) },
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

-- ранги ловца по уровню (видны над головой)
P.Ranks = {
	{ level = 1, name = "Новичок", color = Color3.fromRGB(200, 205, 220) },
	{ level = 5, name = "Следопыт", color = Color3.fromRGB(120, 220, 140) },
	{ level = 10, name = "Ловец духов", color = Color3.fromRGB(110, 190, 255) },
	{ level = 15, name = "Мастер фонаря", color = Color3.fromRGB(190, 130, 255) },
	{ level = 20, name = "Хранитель квартала", color = Color3.fromRGB(255, 190, 70) },
	{ level = 30, name = "Легенда тумана", color = Color3.fromRGB(255, 110, 140) },
}
function P.rankOf(level: number)
	local r = P.Ranks[1]
	for _, x in P.Ranks do
		if level >= x.level then r = x end
	end
	return r
end

-- сундук за каждый 5-й уровень
P.ChestEvery = 5
function P.chest(level: number) return { coins = level * 25, dust = math.floor(level / 2) } end

-- достижения: type = total | distinct | level | rebirths | variant | rarity
P.AchievementOrder = { "first", "c50", "c300", "c1000", "k10", "kall", "golden", "rainbow", "infinity", "legend", "mythic", "secret", "lvl25", "reborn" }
P.Achievements = {
	first = { name = "Первый улов", desc = "Сдай первого духа", type = "total", need = 1, coins = 30 },
	c50 = { name = "Ловец", desc = "Сдай 50 духов", type = "total", need = 50, coins = 250 },
	c300 = { name = "Опытный ловец", desc = "Сдай 300 духов", type = "total", need = 300, coins = 900, dust = 20 },
	c1000 = { name = "Тысяча духов", desc = "Сдай 1000 духов", type = "total", need = 1000, skin = "fog", coins = 2000 },
	k10 = { name = "Коллекционер", desc = "Собери 10 видов", type = "distinct", need = 10, skin = "sea" },
	kall = { name = "Весь квартал", desc = "Собери все виды духов", type = "distinct", need = 22, coins = 5000, dust = 120 },
	golden = { name = "Золотая находка", desc = "Поймай Золотую разновидность", type = "variant", key = "golden", need = 1, coins = 400 },
	rainbow = { name = "Радуга", desc = "Поймай Радужную разновидность", type = "variant", key = "rainbow", need = 1, coins = 1500 },
	infinity = { name = "Бесконечность", desc = "Поймай Бесконечную разновидность", type = "variant", key = "infinity", need = 1, coins = 10000, dust = 200 },
	legend = { name = "Легенда", desc = "Сдай легендарного духа", type = "rarity", key = "legendary", need = 1, coins = 600 },
	mythic = { name = "Миф", desc = "Сдай мифического духа", type = "rarity", key = "mythic", need = 1, coins = 1500 },
	secret = { name = "Тайна", desc = "Сдай секретного духа", type = "rarity", key = "secret", need = 1, coins = 4000 },
	lvl25 = { name = "Ветеран", desc = "Достигни 25 уровня", type = "level", need = 25, coins = 1200 },
	reborn = { name = "Новая жизнь", desc = "Переродись первый раз", type = "rebirths", need = 1, dust = 60, skin = "dragon" },
}

return P
