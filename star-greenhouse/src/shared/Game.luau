-- «Звёздная оранжерея»: правила игры, одинаковые для сервера и клиента.
-- Всё, что зависит от времени (рынок, события, ассортимент магазина), считается чистыми функциями от os.time():
-- клиент показывает то же самое, что решит сервер, без лишних запросов.
local Config = script.Parent:WaitForChild("Config")
local PlantCfg = require(Config:WaitForChild("Plants"))
local MutCfg = require(Config:WaitForChild("Mutations"))

local G = {}
local rgb = Color3.fromRGB

G.PlantList, G.Plants, G.Planets = PlantCfg.List, PlantCfg.ById, PlantCfg.Planets
G.Mut, G.MutOrder = MutCfg.List, MutCfg.Order
G.PlanetIndex = {}
for i, p in G.Planets do G.PlanetIndex[p.id] = i end

G.RarityOrder = { "common", "uncommon", "rare", "epic", "legendary", "mythic" }
G.Rarity = {
	common = { name = "Обычное", color = rgb(190, 195, 210), rank = 1, shop = 1, limit = 5, stock = 20 },
	uncommon = { name = "Необычное", color = rgb(110, 220, 130), rank = 2, shop = 0.6, limit = 3, stock = 12 },
	rare = { name = "Редкое", color = rgb(90, 160, 255), rank = 3, shop = 0.25, limit = 2, stock = 8 },
	epic = { name = "Эпическое", color = rgb(190, 110, 255), rank = 4, shop = 0.08, limit = 1, stock = 4 },
	legendary = { name = "Легендарное", color = rgb(255, 190, 60), rank = 5, shop = 0.02, limit = 1, stock = 2 },
	mythic = { name = "Мифическое", color = rgb(255, 90, 150), rank = 6, shop = 0.005, limit = 1, stock = 1 },
}

-- планеты открываются по сумме заработанных монет
G.PlanetUnlock = { 0, 3000, 30000, 300000, 3000000, 30000000 }
G.PlanetColors = { rgb(190, 205, 235), rgb(220, 120, 80), rgb(140, 210, 255), rgb(255, 160, 60), rgb(220, 90, 255), rgb(255, 225, 120) }

------------------------------------------------------------------ детерминированный хеш (одинаков на всех устройствах)
local function h32(x)
	x = bit32.bxor(x, bit32.rshift(x, 16))
	x = (x * 40503) % 4294967296
	x = bit32.bxor(x, bit32.rshift(x, 13))
	x = (x * 40503 + 12345) % 4294967296
	return bit32.bxor(x, bit32.rshift(x, 16))
end
function G.hash01(a: number, b: number): number
	return h32(((a % 4294967296) * 73856093 + (b % 4294967296) * 19349663) % 4294967296) / 4294967296
end

------------------------------------------------------------------ форматирование
local SUFFIX = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc" }
function G.fmt(n: number): string
	n = math.floor(n + 0.5)
	if n < 1000 then return tostring(n) end
	local i = 1
	local v = n
	while v >= 1000 and i < #SUFFIX do
		v /= 1000
		i += 1
	end
	local s = v >= 100 and ("%d"):format(math.floor(v)) or v >= 10 and ("%.1f"):format(v) or ("%.2f"):format(v)
	s = s:gsub("%.?0+$", "")
	return s .. SUFFIX[i]
end
function G.fmtInt(n: number): string -- 12 345 678
	local s = ("%d"):format(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
	return (out:gsub("^ ", ""))
end
function G.fmtOdds(chance: number): string
	return "1 к " .. G.fmtInt(1 / chance)
end
function G.fmtTime(sec: number): string
	sec = math.max(0, math.ceil(sec))
	if sec >= 3600 then return ("%d:%02d:%02d"):format(sec // 3600, sec % 3600 // 60, sec % 60) end
	return ("%d:%02d"):format(sec // 60, sec % 60)
end

------------------------------------------------------------------ мутации и вес
-- luck умножает шанс каждой мутации (но не выше 40%); forced — мутация, которая точно выпадает
function G.rollMutations(luck: number, rng: Random, forced: string?): { string }
	local out = {}
	for _, id in G.MutOrder do
		local m = G.Mut[id]
		if id == forced or rng:NextNumber() < math.min(0.4, m.chance * luck) then
			table.insert(out, id)
		end
	end
	return out
end
function G.mutMult(list: { string }): number
	local m = 1
	for _, id in list do m *= G.Mut[id].mult end
	return m
end
-- шанс именно такого набора мутаций (произведение шансов)
function G.mutChance(list: { string }): number
	local c = 1
	for _, id in list do c *= G.Mut[id].chance end
	return c
end
function G.mutTitle(list: { string }): string
	if #list == 0 then return "" end
	local names = {}
	for i = #list, 1, -1 do table.insert(names, G.Mut[list[i]].name) end -- редкие первыми
	if #names > 3 then names = { names[1], names[2], "+" .. (#names - 2) } end
	return table.concat(names, " ")
end
-- самая редкая мутация набора (для эффектов и подписи)
function G.rarestMut(list: { string }): string?
	local best, bc = nil, 2
	for _, id in list do
		if G.Mut[id].chance < bc then best, bc = id, G.Mut[id].chance end
	end
	return best
end
-- вес плода, кг: логнормальный разброс, редко очень тяжёлый
function G.rollWeight(plant, rng: Random, mutList: { string }?): number
	local u1, u2 = math.max(rng:NextNumber(), 1e-6), rng:NextNumber()
	local gauss = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
	local f = math.exp(0.28 * gauss)
	if rng:NextNumber() < 0.005 then f *= 1.8 + rng:NextNumber() * 2 end
	f = math.clamp(f, 0.45, 7)
	for _, id in mutList or {} do f *= G.Mut[id].weight or 1 end
	return math.floor(plant.kg * f * 100 + 0.5) / 100
end

------------------------------------------------------------------ рынок: цены меняются каждые 10 минут
G.MarketPeriod = 600
function G.marketEpoch(t: number): number return math.floor(t / G.MarketPeriod) end
function G.marketTimeLeft(t: number): number return G.MarketPeriod - t % G.MarketPeriod end
-- «горячий спрос»: 3 растения продаются втрое дороже
function G.hotPlants(epoch: number): { [string]: boolean }
	local hot, n, k = {}, 0, 0
	while n < 3 and k < 30 do
		k += 1
		local p = G.PlantList[math.floor(G.hash01(epoch, 700 + k) * #G.PlantList) + 1]
		if p and not hot[p.id] then hot[p.id] = true n += 1 end
	end
	return hot
end
function G.marketMult(plant, epoch: number): (number, boolean)
	if G.hotPlants(epoch)[plant.id] then return 3, true end
	return 0.7 + 0.7 * G.hash01(epoch, plant.index), false
end

function G.fruitValue(plantId: string, muts: { string }, kg: number, market: number?, extra: number?): number
	local p = G.Plants[plantId]
	local wf = math.clamp(kg / p.kg, 0.3, 40)
	return math.max(1, math.floor(p.sell * G.mutMult(muts) * wf * (market or 1) * (extra or 1)))
end

------------------------------------------------------------------ магазин семян: новый ассортимент каждые 5 минут
G.ShopPeriod = 300
function G.shopEpoch(t: number): number return math.floor(t / G.ShopPeriod) end
function G.shopTimeLeft(t: number): number return G.ShopPeriod - t % G.ShopPeriod end
local PLANET_CHANCE = { 1, 0.9, 0.8, 0.7, 0.6, 0.5 }
-- seed — число сервера (одинаковое для всех игроков сервера); результат: { [plantId] = количество в запасе }
function G.shopStock(seed: number, epoch: number): { [string]: number }
	local stock = {}
	for i, p in G.PlantList do
		local r = G.Rarity[p.rarity]
		local pi = G.PlanetIndex[p.planet]
		local chance = r.shop * PLANET_CHANCE[pi]
		if p.rarity == "common" then chance = 0.85 end
		if G.hash01(seed * 131 + epoch, i) < chance then
			stock[p.id] = math.max(1, math.floor(r.stock * (0.5 + G.hash01(epoch, i + 5000))))
		end
	end
	return stock
end
G.SeedPriceMult = 1

------------------------------------------------------------------ события по часам: каждые 30 минут на 4 минуты
G.EventPeriod, G.EventLength = 1800, 240
G.Events = {
	{ id = "meteor", name = "Метеоритный дождь", desc = "Шанс мутаций x3", color = rgb(255, 150, 70), luck = 3 },
	{ id = "flare", name = "Солнечная вспышка", desc = "Растения растут вдвое быстрее", color = rgb(255, 225, 90), grow = 2 },
	{ id = "nebula", name = "Туманность", desc = "Цены продажи x1.5", color = rgb(210, 110, 255), sell = 1.5 },
}
-- возвращает событие, оставшееся время действия (>0 если идёт сейчас) или время до начала следующего
function G.eventAt(t: number)
	local slot = math.floor(t / G.EventPeriod)
	local into = t - slot * G.EventPeriod
	local ev = G.Events[math.floor(G.hash01(slot, 99) * #G.Events) + 1]
	if into < G.EventLength then return ev, G.EventLength - into, true end
	local nextSlot = slot + 1
	local nxt = G.Events[math.floor(G.hash01(nextSlot, 99) * #G.Events) + 1]
	return nxt, nextSlot * G.EventPeriod - t, false
end

------------------------------------------------------------------ улучшения станции
G.UpgradeOrder = { "beds", "luck", "speed", "water", "sprinkler" }
G.Upgrades = {
	beds = { name = "Грядки", desc = "Больше мест для растений", icon = "bed", min = 6, max = 30, fmt = "%d шт.",
		value = function(l) return l end, cost = function(l) return math.floor(100 * 1.45 ^ (l - 6)) end },
	luck = { name = "Удобрение удачи", desc = "Мутации выпадают чаще", icon = "luck", min = 1, max = 20, fmt = "x%.2f",
		value = function(l) return 1 + 0.1 * (l - 1) end, cost = function(l) return math.floor(500 * 1.5 ^ (l - 1)) end },
	speed = { name = "Ускоритель роста", desc = "Растения созревают быстрее", icon = "speed", min = 1, max = 15, fmt = "x%.2f",
		value = function(l) return 1 + 0.06 * (l - 1) end, cost = function(l) return math.floor(400 * 1.55 ^ (l - 1)) end },
	water = { name = "Лейка", desc = "Полив сокращает время роста сильнее", icon = "water", min = 1, max = 11, fmt = "-%d%%",
		value = function(l) return math.floor((0.15 + 0.02 * (l - 1)) * 100 + 0.5) end, cost = function(l) return math.floor(300 * 1.5 ^ (l - 1)) end },
	sprinkler = { name = "Спринклеры", desc = "Поливают сами при посадке", icon = "sprinkler", min = 0, max = 5, fmt = "ур. %d", off = "нет",
		value = function(l) return l end, cost = function(l) return ({ 2000, 20000, 200000, 2000000, 20000000 })[l + 1] or 0 end },
}
function G.upgradeValue(key: string, level: number)
	local u = G.Upgrades[key]
	return u.value(math.clamp(level, u.min, u.max))
end
function G.upgradeCost(key: string, level: number): number?
	local u = G.Upgrades[key]
	if level >= u.max then return nil end
	return u.cost(level)
end

------------------------------------------------------------------ украшения станции
G.DecorOrder = { "bench", "banner", "lamps", "fountain", "telescope", "globe", "rocket", "starpond" }
G.Decor = {
	bench = { name = "Скамейка", cost = 800, desc = "Посидеть под звёздами" },
	banner = { name = "Флаги станции", cost = 1500, desc = "Яркие вымпелы вдоль дорожки" },
	lamps = { name = "Фонари", cost = 3000, desc = "Тёплый свет вдоль грядок" },
	fountain = { name = "Фонтан", cost = 12000, desc = "Светящаяся вода в невесомости" },
	telescope = { name = "Телескоп", cost = 40000, desc = "Смотрит прямо на туманность" },
	globe = { name = "Голо-глобус", cost = 150000, desc = "Вращающаяся голограмма планеты" },
	rocket = { name = "Ракета", cost = 800000, desc = "Припаркована у станции" },
	starpond = { name = "Звёздный пруд", cost = 5000000, desc = "Внутри пруда целая галактика" },
}

------------------------------------------------------------------ ежедневный подарок, коды, потион
G.Daily = { coins = { 300, 500, 800, 1200, 2000, 3500, 6000 }, scale = 1 }
G.Codes = {
	STAR = { coins = 1500, text = "Добро пожаловать на станцию! +1500 монет" },
	TIKTOK = { coins = 3000, text = "Привет из TikTok! +3000 монет" },
}
G.Potions = {
	small = { name = "Зелье мутаций", luck = 4, uses = 5, price = 25, desc = "Мутации x4 на 5 посадок" },
	big = { name = "Большое зелье", luck = 10, uses = 10, price = 49, desc = "Мутации x10 на 10 посадок" },
}

-- донаты (id = 0: ещё не создан, кнопка скрыта). price в Robux
G.Products = {
	small = { id = 3734146114, price = 25, name = "Зелье мутаций", desc = "Мутации x4 на 5 посадок" },
	big = { id = 3734146134, price = 49, name = "Большое зелье", desc = "Мутации x10 на 10 посадок" },
	growth2x = { id = 3734146135, price = 149, name = "Рост x2", desc = "Все растения растут вдвое быстрее навсегда", permanent = true },
	auto = { id = 3734146140, price = 99, name = "Авто-сбор", desc = "Спелые плоды собираются сами", permanent = true },
	beds = { id = 3734146141, price = 79, name = "+4 грядки", desc = "Четыре дополнительные грядки навсегда" },
}
G.ProductOrder = { "small", "big", "growth2x", "auto", "beds" }

------------------------------------------------------------------ рост
-- оставшееся время роста в секундах при данных множителях скорости
function G.growSeconds(plant, speed: number): number
	return plant.grow / math.max(0.1, speed)
end

G.StartCoins = 60

------------------------------------------------------------------ полив: можно повторять раз в WaterCooldown секунд, каждый раз рост быстрее
G.WaterCooldown = 20

------------------------------------------------------------------ падающие звёзды по карте
G.Stars = { max = 22, meteorMax = 50, every = 5, life = 120, meteorChance = 0.04 }
-- награда за звезду зависит от самой дальней открытой планеты
function G.starReward(planets: number, meteor: boolean): number
	local mult = G.Planets[math.clamp(planets, 1, #G.Planets)].mult
	return math.floor((meteor and 120 or 9) * mult)
end

------------------------------------------------------------------ задания: всегда три, за выполнение монеты
G.QuestOrder = { "stars", "water", "harvest", "sell", "plant", "mutation" }
G.Quests = {
	stars = { text = "Собери звёзд: %d", min = 4, max = 9, unit = 14 },
	water = { text = "Полей грядки: %d раз", min = 6, max = 14, unit = 7 },
	harvest = { text = "Собери урожай: %d раз", min = 3, max = 8, unit = 22 },
	sell = { text = "Продай плодов: %d", min = 5, max = 14, unit = 12 },
	plant = { text = "Посади семян: %d", min = 3, max = 8, unit = 10 },
	mutation = { text = "Мутаций в урожае: %d", min = 1, max = 3, unit = 90 },
}
function G.questReward(kind: string, need: number, planets: number): number
	local mult = G.Planets[math.clamp(planets, 1, #G.Planets)].mult
	return math.floor(G.Quests[kind].unit * need * mult * 1.5)
end
G.StartBeds = 6
return G
