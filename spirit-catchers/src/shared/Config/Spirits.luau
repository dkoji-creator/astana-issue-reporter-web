-- Виды духов. Чтобы добавить вид: запись здесь + модель в shared/Spirits.luau (Builders и Pose).
-- spawn[district] = { w = вес в обычную ночь, moon = вес в Красную луну }
-- condition: "any" | "moon" (только в Красную луну) | "moonBoost" (чаще в Красную луну)
-- move: walk | float | fly | swim; height — над землёй
-- trail: след, по которому духа можно выследить (shape: print | dot | scrap | ripple | feather | ink | flame)
local S = {}

S.Order = {
	"PaperFox", "Umbrella", "Firefly", "PaperMoth",
	"LanternSpirit", "Kodama", "BellTanuki",
	"Crane", "InkSnake",
	"MoonRabbit", "FoxFire",
	"GoldenCarp",
}

S.Kinds = {
	PaperFox = {
		name = "Бумажный лис", short = "Лис", rarity = "common", world = "lantern", main = true,
		move = "walk", speed = 6, height = 0, follow = 0.45, animSpeed = 9, condition = "any",
		spawn = { street = { w = 50, moon = 30 }, canal = { w = 20, moon = 15 } },
		hint = "Улица фонарей и берега канала",
		habit = "Перебегает от фонаря к фонарю и замирает, когда на него светят.",
		trail = { shape = "print", color = Color3.fromRGB(240, 235, 220), text = "Бумажные отпечатки лап" },
		yard = "Спит под фонарём",
	},
	Umbrella = {
		name = "Зонтик-каса", short = "Зонт", rarity = "common", world = "lantern", main = true,
		move = "walk", speed = 5, height = 0, follow = 0.5, animSpeed = 6, condition = "any",
		spawn = { canal = { w = 45, moon = 35 } },
		hint = "Берега канала",
		habit = "Скачет на одной ноге у воды и крутится, когда радуется.",
		trail = { shape = "ripple", color = Color3.fromRGB(120, 180, 255), text = "Мокрые следы гэта" },
		yard = "Стоит у входа и ловит дождь",
	},
	Firefly = {
		name = "Светлячок", short = "Свет", rarity = "common", world = "lantern",
		move = "float", speed = 4, height = 2.5, follow = 0.8, animSpeed = 8, condition = "any",
		spawn = { garden = { w = 40, moon = 25 } },
		hint = "Храмовый сад",
		habit = "Кружит над травой и гаснет, если подойти слишком резко.",
		trail = { shape = "dot", color = Color3.fromRGB(200, 255, 120), text = "Тающие зелёные искры" },
		yard = "Мерцает над травой",
	},
	PaperMoth = {
		name = "Мотылёк-оригами", short = "Мотылёк", rarity = "common", world = "lantern",
		move = "fly", speed = 6, height = 6, follow = 0.6, animSpeed = 10, condition = "any",
		spawn = { street = { w = 30, moon = 20 } },
		hint = "Улица фонарей, у гирлянд",
		habit = "Летит на свет и садится на бумажные фонари.",
		trail = { shape = "scrap", color = Color3.fromRGB(255, 220, 190), text = "Обрывки цветной бумаги" },
		yard = "Сидит на фонаре",
	},
	LanternSpirit = {
		name = "Дух-фонарь", short = "Фонарь", rarity = "uncommon", world = "lantern",
		move = "float", speed = 4, height = 1, follow = 0.5, animSpeed = 5, condition = "any",
		spawn = { street = { w = 22, moon = 22 }, canal = { w = 8, moon = 10 } },
		hint = "Улица фонарей, танцует под гирляндами",
		habit = "Танцует и машет лентами, а от сильного света прячет глаз.",
		trail = { shape = "dot", color = Color3.fromRGB(255, 170, 90), text = "Капли тёплого воска" },
		yard = "Освещает двор ночью",
	},
	Kodama = {
		name = "Моховичок", short = "Мох", rarity = "uncommon", world = "lantern",
		move = "walk", speed = 3, height = 0, follow = 0.6, animSpeed = 4, condition = "any",
		spawn = { garden = { w = 30, moon = 25 } },
		hint = "Храмовый сад, у деревьев",
		habit = "Медленно бродит между сакурами и наклоняет голову на звук.",
		trail = { shape = "dot", color = Color3.fromRGB(110, 200, 110), text = "Ростки мха" },
		yard = "Растит мох у пруда",
	},
	BellTanuki = {
		name = "Тануки-колокольчик", short = "Тануки", rarity = "uncommon", world = "lantern",
		move = "walk", speed = 4, height = 0, follow = 0.55, animSpeed = 6, condition = "any",
		spawn = { canal = { w = 18, moon = 15 } },
		spots = { Vector3.new(-32, 0.5, -15), Vector3.new(32, 0.5, -15), Vector3.new(-32, 0.5, -45), Vector3.new(32, 0.5, -45), Vector3.new(0, 0.5, -46) },
		hint = "Канал, у мостов",
		habit = "Переваливается у мостов, а колокольчик выдаёт его за углом.",
		trail = { shape = "print", color = Color3.fromRGB(150, 110, 70), text = "Листья и звон колокольчика" },
		yard = "Дремлет у ворот",
	},
	Crane = {
		name = "Бумажный журавлик", short = "Журавль", rarity = "rare", world = "lantern",
		move = "fly", speed = 8, height = 6, follow = 0.5, animSpeed = 5, condition = "moonBoost",
		spawn = { garden = { w = 10, moon = 22 }, street = { w = 3, moon = 0 } },
		hint = "Храмовый сад, чаще в Красную луну",
		habit = "Кружит над пагодой, на глади пруда видно его тень.",
		trail = { shape = "feather", color = Color3.fromRGB(250, 250, 255), text = "Бумажные перья" },
		yard = "Садится на ворота",
	},
	InkSnake = {
		name = "Чернильный уж", short = "Уж", rarity = "rare", world = "lantern",
		move = "walk", speed = 4, height = 0.2, follow = 0.45, animSpeed = 5, condition = "any",
		spawn = { garden = { w = 8, moon = 10 } },
		spots = { Vector3.new(-22, 0.5, -110), Vector3.new(0, 0.5, -132) },
		hint = "Храмовый сад, у пруда и пагоды",
		habit = "Скользит по траве, оставляя чернильную строчку.",
		trail = { shape = "ink", color = Color3.fromRGB(30, 40, 90), text = "Чернильные кляксы" },
		yard = "Пишет иероглифы на камнях",
	},
	MoonRabbit = {
		name = "Лунный кролик", short = "Кролик", rarity = "epic", world = "lantern",
		move = "walk", speed = 7, height = 0, follow = 0.5, animSpeed = 6, condition = "moon", moonOnly = true,
		spawn = { street = { w = 0, moon = 14 }, garden = { w = 0, moon = 8 } },
		hint = "Только в Красную луну: улица и сад",
		habit = "Высоко прыгает и оставляет серебряные отпечатки.",
		trail = { shape = "print", color = Color3.fromRGB(230, 230, 255), text = "Серебряные отпечатки" },
		yard = "Толчёт рисовые лепёшки",
	},
	FoxFire = {
		name = "Лисий огонь", short = "Огонь", rarity = "epic", world = "lantern",
		move = "float", speed = 6, height = 3, follow = 0.6, animSpeed = 6, condition = "moon", moonOnly = true,
		spawn = { street = { w = 0, moon = 8 }, canal = { w = 0, moon = 10 } },
		hint = "Только в Красную луну: улица и канал",
		habit = "Три голубых огонька водят хоровод и разбегаются от луча.",
		trail = { shape = "flame", color = Color3.fromRGB(110, 200, 255), text = "Голубые искры" },
		yard = "Освещает пруд голубым",
	},
	GoldenCarp = {
		name = "Золотой карп", short = "Карп", rarity = "legendary", world = "lantern", main = true,
		move = "swim", speed = 0, height = 0, follow = 0.3, animSpeed = 3, condition = "moon", moonOnly = true,
		spawn = {}, -- появляется по событию Красной луны (см. Main.server)
		hint = "Только в Красную луну: над каналом",
		habit = "Плывёт по воздуху над каналом, сначала его выдаёт плеск.",
		trail = { shape = "ripple", color = Color3.fromRGB(255, 200, 80), text = "Золотые круги на воде" },
		yard = "Плавает в пруду",
	},
}

S.ConditionText = {
	any = "В любую ночь",
	moon = "Только в Красную луну",
	moonBoost = "Чаще в Красную луну",
}

return S
