-- Мутации плодов. Каждая выпадает независимо при сборе и складывается с другими (множители перемножаются).
-- chance: вероятность (1 к N), mult: множитель цены, tier: сила эффекта (1-6), color: цвет свечения и подписи.
local C = Color3.fromRGB
local M = {}
M.Order = {
	"giant", "frost", "lava", "neon", "electric", "crystal", "ghost", "rainbow", "golden", "starry", "plasma", "galactic", "blackhole", "supernova", "singularity",
}
M.List = {
	giant = { name = "Гигантская", chance = 1 / 50, mult = 3, tier = 1, color = C(120, 220, 120), size = 1.8, weight = 2.5, desc = "Плод вырос огромным" },
	frost = { name = "Ледяная", chance = 1 / 8, mult = 2, tier = 1, color = C(150, 220, 255), material = "Ice", desc = "Покрыта инеем" },
	lava = { name = "Лавовая", chance = 1 / 15, mult = 3, tier = 1, color = C(255, 110, 40), material = "Slate", desc = "Внутри течёт магма" },
	neon = { name = "Неоновая", chance = 1 / 40, mult = 5, tier = 2, color = C(60, 255, 200), material = "Neon", desc = "Светится как неон" },
	electric = { name = "Электрическая", chance = 1 / 100, mult = 8, tier = 2, color = C(255, 240, 80), material = "Neon", desc = "По плоду бегут разряды" },
	crystal = { name = "Кристальная", chance = 1 / 300, mult = 12, tier = 3, color = C(190, 150, 255), material = "Glass", desc = "Прозрачная, как стекло" },
	ghost = { name = "Призрачная", chance = 1 / 500, mult = 18, tier = 3, color = C(210, 225, 255), material = "ForceField", desc = "Просвечивает насквозь" },
	rainbow = { name = "Радужная", chance = 1 / 1000, mult = 25, tier = 4, color = C(255, 120, 200), material = "Neon", desc = "Переливается всеми цветами" },
	golden = { name = "Золотая", chance = 1 / 5000, mult = 50, tier = 4, color = C(255, 205, 60), material = "Metal", desc = "Отлита из чистого золота" },
	starry = { name = "Звёздная", chance = 1 / 25000, mult = 120, tier = 5, color = C(255, 245, 200), material = "Neon", desc = "Внутри плода целое небо" },
	plasma = { name = "Плазменная", chance = 1 / 80000, mult = 250, tier = 5, color = C(255, 60, 200), material = "Neon", desc = "Раскалённая плазма" },
	galactic = { name = "Галактическая", chance = 1 / 200000, mult = 400, tier = 6, color = C(150, 120, 255), material = "Neon", desc = "Внутри вращается галактика" },
	blackhole = { name = "Чёрная дыра", chance = 1 / 2000000, mult = 1500, tier = 6, color = C(90, 40, 160), material = "Glass", desc = "Всё вокруг тянется к ней" },
	supernova = { name = "Сверхновая", chance = 1 / 50000000, mult = 8000, tier = 6, color = C(255, 255, 255), material = "Neon", desc = "Рождение и смерть звезды" },
	singularity = { name = "Сингулярность", chance = 1 / 1000000000, mult = 100000, tier = 6, color = C(255, 255, 255), material = "Neon", desc = "Один шанс на миллиард" },
}
return M
