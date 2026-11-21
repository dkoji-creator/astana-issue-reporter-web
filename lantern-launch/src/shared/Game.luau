-- «Запусти фонарик»: правила игры, одинаковые для сервера и клиента.
-- Идея: держишь кнопку, полоска силы ходит, отпускаешь — фонарик летит вдаль и приманивает духа.
-- Чем дальше упал фонарик, тем реже дух. Всё считает сервер.
local Config = script.Parent:WaitForChild("Config")
local SpiritCfg = require(Config:WaitForChild("Spirits"))
local Eco = require(Config:WaitForChild("Economy"))

local G = {}
G.Kinds = SpiritCfg.Kinds
G.Rarity, G.RarityOrder = Eco.Rarity, Eco.RarityOrder
G.Variants, G.VariantOrder = Eco.Variants, Eco.VariantOrder

-- духи, которые можно получить запуском (без праздничных и секретных квестов)
G.Pool = {}
G.PoolOrder = {}
for _, kind in SpiritCfg.Order do
	local info = SpiritCfg.Kinds[kind]
	if info and not info.holiday and not info.secretQuest then
		G.Pool[kind] = true
		table.insert(G.PoolOrder, kind)
	end
end
G.PoolSize = #G.PoolOrder

local rgb = Color3.fromRGB
------------------------------------------------------------------ зоны по дальности
G.Zones = {
	{ id = "meadow", name = "Луг зари", from = 0, to = 150, luck = 1, color = rgb(120, 205, 110), weights = { common = 70, uncommon = 30 } },
	{ id = "forest", name = "Бамбуковый лес", from = 150, to = 350, luck = 1.2, color = rgb(70, 170, 120), weights = { common = 30, uncommon = 50, rare = 20 } },
	{ id = "lake", name = "Зеркальное озеро", from = 350, to = 600, luck = 1.5, color = rgb(90, 170, 230), weights = { uncommon = 30, rare = 50, epic = 20 } },
	{ id = "peaks", name = "Лунные горы", from = 600, to = 900, luck = 2, color = rgb(170, 175, 200), weights = { rare = 30, epic = 50, legendary = 20 } },
	{ id = "sky", name = "Небесный рынок", from = 900, to = 1300, luck = 3, color = rgb(255, 205, 220), weights = { epic = 25, legendary = 45, mythic = 25, secret = 5 } },
}
G.MaxDistance = 1300
function G.zoneAt(dist: number)
	for _, z in G.Zones do
		if dist < z.to then return z end
	end
	return G.Zones[#G.Zones]
end

------------------------------------------------------------------ полоска силы
G.MeterPeriod = 1.5 -- секунд на полный цикл вверх-вниз
function G.meterAt(t: number): number
	return 0.5 - 0.5 * math.cos(t * 2 * math.pi / G.MeterPeriod)
end
-- серия идеальных запусков: +20% монет за каждый подряд, максимум x3
G.StreakStep, G.StreakMax = 0.2, 10
function G.qualityName(q: number): string
	if q >= 0.93 then return "ИДЕАЛЬНО!" end
	if q >= 0.78 then return "Отлично!" end
	if q >= 0.5 then return "Хорошо" end
	return "Слабо"
end
-- расстояние полёта: от трети до полной дальности апгрейда
function G.distance(maxDist: number, q: number): number
	return maxDist * (0.3 + 0.7 * q)
end
function G.flightTime(dist: number): number
	return 1.1 + dist / 650
end

------------------------------------------------------------------ улучшения (за монеты)
G.UpgradeOrder = { "power", "luck", "coins", "speed", "multi", "auto" }
G.Upgrades = {
	power = { name = "Сила броска", desc = "Фонарик летит дальше: новые зоны и редкие духи", max = 30, icon = "target",
		value = function(l) return 200 + (l - 1) * 38 end, fmt = "до %d м", cost = function(l) return math.floor(40 * 1.3 ^ (l - 1)) end },
	luck = { name = "Удача", desc = "Чаще редкие духи и особые разновидности", max = 25, icon = "luck",
		value = function(l) return 1 + 0.15 * (l - 1) end, fmt = "x%.2f", cost = function(l) return math.floor(60 * 1.32 ^ (l - 1)) end },
	coins = { name = "Монеты", desc = "Больше монет за каждого духа", max = 25, icon = "coin",
		value = function(l) return 1 + 0.3 * (l - 1) end, fmt = "x%.2f", cost = function(l) return math.floor(50 * 1.32 ^ (l - 1)) end },
	speed = { name = "Скорость", desc = "Фонарики готовы быстрее", max = 10, icon = "upgrade",
		value = function(l) return math.max(0.5, 2.2 - 0.19 * (l - 1)) end, fmt = "%.1f с", cost = function(l) return math.floor(200 * 1.6 ^ (l - 1)) end },
	multi = { name = "Связка фонариков", desc = "Несколько фонариков за один запуск", max = 6, icon = "jar",
		value = function(l) return l end, fmt = "%d шт.", cost = function(l) return ({ 600, 6000, 60000, 600000, 6000000 })[l] or 0 end },
	auto = { name = "Авто-запуск", desc = "Фонарики летят сами, можно отдыхать", max = 6, icon = "gift",
		value = function(l) return ({ 0, 6, 4.5, 3.3, 2.4, 1.6 })[l] or 1.6 end, fmt = "раз в %.1f с", off = "нет", cost = function(l) return ({ 1500, 15000, 150000, 1500000, 15000000 })[l] or 0 end },
}
function G.upgradeValue(key: string, level: number)
	return G.Upgrades[key].value(math.clamp(level, 1, G.Upgrades[key].max))
end
function G.upgradeCost(key: string, level: number): number?
	local u = G.Upgrades[key]
	if level >= u.max then return nil end
	return u.cost(level)
end

------------------------------------------------------------------ награды коллекции (получаются сами)
G.Milestones = {
	{ need = 3, coins = 300 }, { need = 6, coins = 1500 }, { need = 10, coins = 6000 }, { need = 15, coins = 30000 },
	{ need = 20, coins = 150000 }, { need = 25, coins = 700000 }, { need = 30, coins = 3000000 },
}

------------------------------------------------------------------ ежедневная награда и коды
G.Daily = { coins = 250, perStreak = 150, maxStreak = 7, potionSeconds = 600 }
G.Codes = {
	LAUNCH = { coins = 1000, text = "Добро пожаловать! +1000 монет" },
	TIKTOK = { coins = 2500, text = "Привет из TikTok! +2500 монет" },
}
G.Potion = { mult = 2, seconds = 600 }

-- донаты (id = 0 — пока не создан, кнопка скрыта). price в Robux
G.Products = {
	potion = { id = 0, price = 25, name = "Зелье удачи x2", desc = "Удача x2 на 10 минут" },
	coins2x = { id = 0, price = 149, name = "x2 Монеты", desc = "Все монеты удваиваются навсегда", permanent = true },
	autoPro = { id = 0, price = 99, name = "Авто-запуск Pro", desc = "Авто-запуск работает вдвое быстрее навсегда", permanent = true },
}
G.ProductOrder = { "potion", "coins2x", "autoPro" }

------------------------------------------------------------------ расчёт запуска (общая логика, чтобы тест на сервере был честным)
-- вероятность вида выбирается по зоне; удача сдвигает вес в сторону редких
function G.rollKind(zone, luck: number, rng: Random)
	local rank = {}
	for i, k in G.RarityOrder do rank[k] = i end
	local weights, total = {}, 0
	for rar, w in zone.weights do
		local ww = w * (1 + (luck - 1) * 0.25 * (rank[rar] - 1))
		weights[rar] = ww
		total += ww
	end
	local r, picked = rng:NextNumber() * total, nil
	for rar, w in weights do
		r -= w
		if r <= 0 then picked = rar break end
	end
	picked = picked or next(weights)
	local pool = {}
	for _, kind in G.PoolOrder do
		if G.Kinds[kind].rarity == picked then table.insert(pool, kind) end
	end
	if #pool == 0 then pool = G.PoolOrder end
	local kind = pool[rng:NextInteger(1, #pool)]
	return kind, weights[picked] / total / #pool
end
function G.rollVariant(luck: number, zoneLuck: number, rng: Random)
	local mult = luck * zoneLuck
	for i = #G.VariantOrder, 2, -1 do
		local key = G.VariantOrder[i]
		local v = G.Variants[key]
		if not v.moonOnly and rng:NextNumber() < v.chance * mult then return key, v.chance end
	end
	return "normal", 1
end
function G.coinsFor(rarity: string, variant: string, coinMult: number): number
	return math.max(1, math.floor(G.Rarity[rarity].coins * G.Variants[variant].mult * coinMult))
end

return G
