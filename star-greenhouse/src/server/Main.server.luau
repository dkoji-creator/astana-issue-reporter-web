-- «Звёздная оранжерея»: сервер. Всё важное считается здесь: посадка, рост, мутации, продажи, магазин, события, сохранения.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local G = require(Shared:WaitForChild("Game"))
local Map = require(script.Parent:WaitForChild("Map"))

local ADMIN_ID = 8432365972
local STORE = DataStoreService:GetDataStore("StarGreenhouse_v1")
local BAG_CAP = 120
local MAX_PLOT_DIST = 22

Map.build()
task.spawn(function()
	local Loader = require(script.Parent:WaitForChild("PlantLoader"))
	local n = Loader.run()
	Map.buildFlora()
	print("PlantLoader: меши растений", n)
end)

------------------------------------------------------------------ ремоуты
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local RX = {}
for _, n in { "Sync", "Notify", "Reveal", "Stock", "Event", "Announce", "Act", "Select", "Harvest", "Collected", "Strike", "Pollen", "Skydive", "SelectCan" } do
	local e = Instance.new("RemoteEvent")
	e.Name = n
	e.Parent = remotes
	RX[n] = e
end
for _, n in { "Buy", "Sell", "Upgrade", "BuyDecor", "Daily", "Redeem", "Fav", "Top", "Admin", "State", "ClaimQuest", "Travel", "Home", "PollenDone", "BuyCan", "Brew", "CannonStart", "CannonEnd" } do
	local f = Instance.new("RemoteFunction")
	f.Name = n
	f.Parent = remotes
	RX[n] = f
end

------------------------------------------------------------------ данные
local D = {} -- профили
local S = {} -- сессии (в памяти)
local SERVER_SEED = math.random(1, 1000000)
ReplicatedStorage:SetAttribute("ShopSeed", SERVER_SEED)
local soldNow = { epoch = 0, sold = {} } -- сколько всего куплено в этом сервере за текущий ассортимент

local function now() return os.time() end

local function newProfile()
	return {
		v = 1, coins = G.StartCoins, earned = 0, seeds = { moon_01 = 3 }, fruits = {}, uid = 0,
		beds = {}, bedCount = G.StartBeds,
		upg = { luck = 1, speed = 1, water = 1, sprinkler = 0 },
		decor = {}, idx = {}, mutSeen = {}, perms = {},
		daily = { last = 0, streak = 0 }, potion = { luck = 1, uses = 0 },
		firstPlant = false, receipts = {}, redeemed = {},
		stats = { harvests = 0, sold = 0, bestChance = 1, stars = 0, brews = 0, meteors = 0, chests = 0 }, weekBest = { w = 0, kg = 0 }, lastSeen = now(),
		q = {}, planet = 1, cans = { c1 = 3, c2 = 0, c3 = 0, c4 = 0, c5 = 0 }, cd = { cannon = 0, chest = 0 },
	}
end

local function mergeDefaults(d)
	local base = newProfile()
	for k, v in base do
		if d[k] == nil then d[k] = v end
	end
	for k, v in base.upg do if d.upg[k] == nil then d.upg[k] = v end end
	for k, v in base.stats do if d.stats[k] == nil then d.stats[k] = v end end
	for k, v in base.cans do if d.cans[k] == nil then d.cans[k] = v end end
	for k, v in base.cd do if d.cd[k] == nil then d.cd[k] = v end end
	return d
end

-- DataStore не принимает массивы с пропусками: грядки хранятся с ключами-строками
local function unpackBeds(d)
	local beds = {}
	for k, b in d.beds do beds[tonumber(k)] = b end
	d.beds = beds
	return d
end
local function packed(d)
	local copy = table.clone(d)
	local beds = {}
	for i, b in d.beds do beds[tostring(i)] = b end
	copy.beds = beds
	return copy
end
local function load(userId)
	for attempt = 1, 4 do
		local ok, res = pcall(function() return STORE:GetAsync("u" .. userId) end)
		if ok then return res and unpackBeds(mergeDefaults(res)) or newProfile(), true end
		task.wait(1.5 * attempt)
	end
	return newProfile(), false
end
local function save(plr)
	local d = D[plr]
	if not d or not S[plr] or not S[plr].canSave then return end
	d.lastSeen = now()
	local ok, err = pcall(function() STORE:SetAsync("u" .. plr.UserId, packed(d)) end)
	if not ok then warn("save failed", err) end
end

------------------------------------------------------------------ уведомления и синхронизация
local function notify(plr, text, kind) RX.Notify:FireClient(plr, text, kind or "info") end

local function unlockedPlanets(d)
	local n = 0
	for i, need in G.PlanetUnlock do
		if d.earned >= need then n = i end
	end
	return n
end

local function snapshot(plr)
	local d = D[plr]
	local s = S[plr]
	local epoch = G.shopEpoch(now())
	return {
		coins = d.coins, earned = d.earned, seeds = d.seeds, fruits = d.fruits, upg = d.upg, decor = d.decor, idx = d.idx, mutSeen = d.mutSeen,
		perms = d.perms, potion = d.potion, bedCount = d.bedCount, plot = s.plot, bagCap = BAG_CAP, stats = d.stats, sel = s.sel,
		bought = s.bought and s.bought.epoch == epoch and s.bought.n or {},
		daily = { can = d.daily.last ~= math.floor(now() / 86400), streak = d.daily.streak },
		planets = unlockedPlanets(d), sold = soldNow.epoch == epoch and soldNow.sold or {}, q = d.q, planet = d.planet or 1, cans = d.cans, can = s.can or 0, cd = d.cd,
	}
end
local function push(plr, ...)
	local snap = snapshot(plr)
	local patch = {}
	for _, k in { ... } do patch[k] = snap[k] end
	RX.Sync:FireClient(plr, patch)
end

------------------------------------------------------------------ участки и грядки
local plotOwner = {} -- id огорода ("планета_место") -> игрок
local function refreshBed(plr, i)
	local s, d = S[plr], D[plr]
	local plot = s.plot and Map.plots[s.plot]
	if not plot then return end
	local soil = plot.beds[i].soil
	local b = d.beds[i]
	if b then
		soil:SetAttribute("Plant", b.id)
		soil:SetAttribute("T0", b.t0)
		soil:SetAttribute("Ready", b.ready)
		soil:SetAttribute("Wa", b.wt ~= nil)
		soil:SetAttribute("WaterAt", (b.wt or 0) + G.WaterCooldown)
		soil:SetAttribute("Sp", b.sp == true)
		soil:SetAttribute("Muts", table.concat(b.m, ","))
		soil:SetAttribute("Kg", b.w)
	else
		for _, k in { "Plant", "T0", "Ready", "Wa", "Sp", "Muts", "Kg", "WaterAt" } do soil:SetAttribute(k, nil) end
	end
	Map.setBedLocked(s.plot, i, i > d.bedCount)
end
local function refreshAllBeds(plr)
	for i = 1, Map.MaxBeds do refreshBed(plr, i) end
end

-- огород строится на той планете, где сейчас игрок (d.planet)
local function claimPlot(plr)
	local s, d = S[plr], D[plr]
	if s.plot then return true end
	local pi = math.clamp(d.planet or 1, 1, #G.Planets)
	for j = 1, Map.SlotsPerPlanet do
		local key = pi .. "_" .. j
		if not plotOwner[key] then
			plotOwner[key] = plr
			local plot = Map.buildPlot(pi, j)
			s.plot = plot.id
			plot.model:SetAttribute("OwnerId", plr.UserId)
			Map.setPlotSign(plot.id, plr.DisplayName, G.PlanetColors[math.clamp(unlockedPlanets(d), 1, 6)])
			for _, id in G.DecorOrder do
				if d.decor[id] then Map.placeDecor(plot.id, id) end
			end
			refreshAllBeds(plr)
			return true
		end
	end
	return false
end
local function releasePlot(plr)
	local s = S[plr]
	if not s or not s.plot then return end
	local id = s.plot
	plotOwner[id] = nil
	Map.destroyPlot(id)
	s.plot = nil
end
local function teleportToPlot(plr)
	local s = S[plr]
	local ch = plr.Character
	if ch and s and s.plot then
		task.defer(function() ch:PivotTo(Map.plots[s.plot].entrance) end)
	end
end

------------------------------------------------------------------ задания
local function ensureQuests(d)
	d.q = d.q or {}
	local have = {}
	for _, q in d.q do have[q.k] = true end
	local tries = 0
	while #d.q < 3 and tries < 30 do
		tries += 1
		local k = G.QuestOrder[math.random(1, #G.QuestOrder)]
		if not have[k] then
			local def = G.Quests[k]
			local need = math.random(def.min, def.max)
			table.insert(d.q, { k = k, need = need, have = 0, reward = G.questReward(k, need, math.max(1, unlockedPlanets(d))) })
			have[k] = true
		end
	end
end
local function questProgress(plr, kind, n)
	local d = D[plr]
	if not d then return end
	local changed = false
	for _, q in d.q do
		if q.k == kind and q.have < q.need then
			q.have = math.min(q.need, q.have + (n or 1))
			changed = true
		end
	end
	if changed then push(plr, "q") end
end

------------------------------------------------------------------ события по часам
local activeEvent = nil
local forcedEvent = nil -- { ev, untilTime } — включает админ
local function eventNow()
	if forcedEvent and now() < forcedEvent[2] then return forcedEvent[1], forcedEvent[2] - now() end
	local ev, left, active = G.eventAt(now())
	if active then return ev, left end
	return nil, 0
end

------------------------------------------------------------------ мутации и посадка
-- вспышка: рост вдвое быстрее ещё left секунд
local function flareRemaining(rem, left)
	local r = rem <= 2 * left and rem / 2 or rem - left
	return math.max(3, r)
end
local function newBed(plr, d, plantId, regrow)
	local plant = G.Plants[plantId]
	local speed = G.upgradeValue("speed", d.upg.speed) * (d.perms.growth2x and 2 or 1)
	if G.PlanetIndex[plant.planet] == (d.planet or 1) then speed *= G.NativeBonus end
	local base = plant.grow * (regrow and plant.regrow > 0 and plant.regrow or 1)
	local t = now()
	local ready = t + math.max(3, base / speed)
	local ev, left = eventNow()
	if ev and ev.grow then ready = t + flareRemaining(ready - t, left) end
	local luck = G.upgradeValue("luck", d.upg.luck) * (G.PlanetLuck[d.planet or 1] or 1)
	if d.potion.uses > 0 then
		luck *= d.potion.luck
		d.potion.uses -= 1
		if d.potion.uses <= 0 then d.potion = { luck = 1, uses = 0 } end
	end
	local rng = Random.new()
	local forced = S[plr].forceMut
	S[plr].forceMut = nil
	if not d.firstPlant then
		forced = forced or ({ "frost", "lava", "giant" })[math.random(1, 3)]
		d.firstPlant = true
	end
	local muts = G.rollMutations(luck, rng, forced)
	if S[plr].forceAll then
		muts = table.clone(G.MutOrder)
		S[plr].forceAll = nil
	end
	local bed = { id = plantId, t0 = t, ready = ready, m = muts, w = G.rollWeight(plant, rng, muts) }
	if S[plr].forceGiant then
		bed.w = math.floor(plant.kg * 300 * 100) / 100
		S[plr].forceGiant = nil
	end
	local sp = d.upg.sprinkler
	if sp > 0 then
		local pct = math.min(0.6, (G.upgradeValue("water", d.upg.water) + 5 * sp) / 100)
		bed.ready = t + (bed.ready - t) * (1 - pct)
		bed.sp = true
		bed.wt = t
	end
	return bed
end

local function plantSeed(plr, i)
	local d, s = D[plr], S[plr]
	local id = s.sel
	if not id or (d.seeds[id] or 0) <= 0 then
		notify(plr, "Выбери семя в панели внизу", "bad")
		return
	end
	d.seeds[id] -= 1
	if d.seeds[id] <= 0 then
		d.seeds[id] = nil
		-- выбрать следующее доступное семя
		s.sel = next(d.seeds)
	end
	d.beds[i] = newBed(plr, d, id)
	refreshBed(plr, i)
	push(plr, "seeds", "potion", "sel")
	questProgress(plr, "plant", 1)
end

local function waterBed(plr, i)
	local d = D[plr]
	local b = d.beds[i]
	local t = now()
	local s = S[plr]
	local tier = s.can or 0
	if tier > 0 and (d.cans["c" .. tier] or 0) > 0 then
		d.cans["c" .. tier] -= 1
		local cpct = G.Cans[tier].pct
		b.ready = t + (b.ready - t) * (1 - cpct)
		refreshBed(plr, i)
		if d.cans["c" .. tier] <= 0 then s.can = 0 end
		push(plr, "cans", "can")
		questProgress(plr, "water", 1)
		return
	end
	if b.wt and t - b.wt < G.WaterCooldown then
		notify(plr, ("Полить снова можно через %d с"):format(G.WaterCooldown - (t - b.wt)), "info")
		return
	end
	local pct = G.upgradeValue("water", d.upg.water) / 100
	b.ready = t + (b.ready - t) * (1 - pct)
	b.wt = t
	refreshBed(plr, i)
	questProgress(plr, "water", 1)
end

local function weekKey() return math.floor(now() / 604800) end

local function harvestBed(plr, i, silent)
	local d, s = D[plr], S[plr]
	local b = d.beds[i]
	if not b or now() < b.ready then return false end
	if #d.fruits >= BAG_CAP then
		if not silent then notify(plr, "Сумка полна: продай урожай", "bad") end
		return false
	end
	local plant = G.Plants[b.id]
	d.uid += 1
	local fruit = { uid = d.uid, id = b.id, m = b.m, w = b.w, t = now() }
	table.insert(d.fruits, fruit)
	-- индекс
	local e = d.idx[b.id] or { n = 0, best = 0 }
	e.n += 1
	if b.w > e.best then e.best = b.w end
	d.idx[b.id] = e
	for _, mid in b.m do d.mutSeen[mid] = true end
	d.stats.harvests += 1
	local chance = G.mutChance(b.m)
	if chance < d.stats.bestChance then d.stats.bestChance = chance end
	-- рекорд недели
	local w = weekKey()
	if d.weekBest.w ~= w then d.weekBest = { w = w, kg = 0 } end
	if b.w > d.weekBest.kg then
		d.weekBest.kg = b.w
		task.spawn(function()
			pcall(function()
				DataStoreService:GetOrderedDataStore("StarGreenhouse_Heavy_" .. w):SetAsync(tostring(plr.UserId), math.floor(b.w * 100))
			end)
		end)
	end
	-- грядка
	if plant.regrow > 0 then
		d.beds[i] = newBed(plr, d, b.id, true)
	else
		d.beds[i] = nil
	end
	refreshBed(plr, i)
	local rarest = G.rarestMut(b.m)
	local tier = rarest and G.Mut[rarest].tier or 0
	if not silent then
		RX.Harvest:FireClient(plr, i, fruit.id, fruit.m, fruit.w)
		if tier >= 3 or (rarest and chance <= 1 / 300) then
			RX.Reveal:FireClient(plr, { id = b.id, m = b.m, w = b.w, chance = chance })
		end
	end
	if chance <= 1 / 50000 then
		local pl = s.plot and Map.plots[s.plot]
		RX.Announce:FireAllClients(plr.DisplayName, plant.name, G.mutTitle(b.m), chance, pl and pl.beds[i] and pl.beds[i].pos)
	end
	push(plr, "fruits", "idx", "mutSeen", "stats")
	questProgress(plr, "harvest", 1)
	if #b.m > 0 then questProgress(plr, "mutation", 1) end
	return true
end

local function actOnBed(plr, i)
	local s, d = S[plr], D[plr]
	if not s or not d or not s.plot or typeof(i) ~= "number" then return end
	i = math.floor(i)
	local plot = Map.plots[s.plot]
	local bed = plot.beds[i]
	if not bed then return end
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root or (root.Position - bed.pos).Magnitude > MAX_PLOT_DIST then return end
	if i > d.bedCount then
		notify(plr, "Грядка закрыта: открой в Мастерской", "info")
		return
	end
	local b = d.beds[i]
	if not b then
		plantSeed(plr, i)
	elseif now() >= b.ready then
		harvestBed(plr, i)
	else
		waterBed(plr, i)
	end
end
RX.Act.OnServerEvent:Connect(actOnBed)
RX.Select.OnServerEvent:Connect(function(plr, id)
	local d, s = D[plr], S[plr]
	if d and s and (id == nil or (type(id) == "string" and (d.seeds[id] or 0) > 0)) then
		s.sel = id
	end
end)

------------------------------------------------------------------ продажа
local function sellFactor()
	local ev = eventNow()
	return ev and ev.sell or 1
end
local function fruitPrice(f)
	local plant = G.Plants[f.id]
	local mm = G.marketMult(plant, G.marketEpoch(now()))
	return G.fruitValue(f.id, f.m, f.w, mm, sellFactor())
end
local function addCoins(plr, amount)
	local d = D[plr]
	local before = unlockedPlanets(d)
	d.coins += amount
	d.earned += amount
	local after = unlockedPlanets(d)
	if after > before then
		local pl = G.Planets[after]
		notify(plr, "Открыта планета: " .. pl.name .. "! Лети на ракете в центре площади", "ok")
		if S[plr].plot then Map.setPlotSign(S[plr].plot, plr.DisplayName, G.PlanetColors[after]) end
	end
end

RX.Sell.OnServerInvoke = function(plr, mode, uid)
	local d = D[plr]
	if not d then return false end
	local total, count, keep = 0, 0, {}
	if mode == "all" then
		for _, f in d.fruits do
			if f.fav then
				table.insert(keep, f)
			else
				total += fruitPrice(f)
				count += 1
			end
		end
		d.fruits = keep
	elseif mode == "one" then
		for _, f in d.fruits do
			if f.uid == uid and count == 0 then
				total += fruitPrice(f)
				count += 1
			else
				table.insert(keep, f)
			end
		end
		d.fruits = keep
	else
		return false
	end
	if count == 0 then return false, "Нечего продавать" end
	addCoins(plr, total)
	d.stats.sold += count
	questProgress(plr, "sell", count)
	push(plr, "coins", "earned", "fruits", "planets", "stats")
	return true, total, count
end
RX.Fav.OnServerInvoke = function(plr, uid)
	local d = D[plr]
	if not d then return false end
	for _, f in d.fruits do
		if f.uid == uid then
			f.fav = not f.fav or nil
			push(plr, "fruits")
			return true
		end
	end
	return false
end

------------------------------------------------------------------ магазин семян
local function currentSold()
	local e = G.shopEpoch(now())
	if soldNow.epoch ~= e then soldNow = { epoch = e, sold = {} } RX.Stock:FireAllClients(e, {}) end
	return soldNow.sold
end
RX.Buy.OnServerInvoke = function(plr, id, qty)
	local d, s = D[plr], S[plr]
	local plant = type(id) == "string" and G.Plants[id]
	if not d or not plant then return false, "Нет такого семени" end
	qty = math.clamp(math.floor(tonumber(qty) or 1), 1, 50)
	local e = G.shopEpoch(now())
	local sold = currentSold()
	local stock = G.shopStock(SERVER_SEED, e)
	local left = (stock[id] or 0) - (sold[id] or 0)
	if left <= 0 then return false, "Распродано до обновления" end
	if unlockedPlanets(d) < G.PlanetIndex[plant.planet] then return false, "Планета ещё закрыта" end
	s.bought = (s.bought and s.bought.epoch == e) and s.bought or { epoch = e, n = {} }
	local lim = G.Rarity[plant.rarity].limit - (s.bought.n[id] or 0)
	if lim <= 0 then return false, "Лимит на это обновление" end
	qty = math.min(qty, left, lim)
	local price = plant.seed * qty
	if d.coins < price then return false, "Не хватает монет" end
	d.coins -= price
	d.seeds[id] = (d.seeds[id] or 0) + qty
	sold[id] = (sold[id] or 0) + qty
	s.bought.n[id] = (s.bought.n[id] or 0) + qty
	if not s.sel then s.sel = id end
	RX.Stock:FireAllClients(e, sold)
	push(plr, "coins", "seeds", "bought", "sel")
	return true, qty
end

------------------------------------------------------------------ улучшения и украшения
RX.Upgrade.OnServerInvoke = function(plr, key)
	local d = D[plr]
	local u = G.Upgrades[key]
	if not d or not u then return false end
	local level = key == "beds" and d.bedCount or d.upg[key]
	local cost = G.upgradeCost(key, level)
	if not cost then return false, "Максимум" end
	if d.coins < cost then return false, "Не хватает монет" end
	d.coins -= cost
	if key == "beds" then
		d.bedCount += 1
		if S[plr].plot then Map.setBedLocked(S[plr].plot, d.bedCount, false) end
	else
		d.upg[key] += 1
	end
	push(plr, "coins", "upg", "bedCount")
	return true
end
RX.BuyDecor.OnServerInvoke = function(plr, id)
	local d, s = D[plr], S[plr]
	local info = type(id) == "string" and G.Decor[id]
	if not d or not info then return false end
	if d.decor[id] then return false, "Уже куплено" end
	if d.coins < info.cost then return false, "Не хватает монет" end
	d.coins -= info.cost
	d.decor[id] = true
	if s.plot then Map.placeDecor(s.plot, id) end
	push(plr, "coins", "decor")
	return true
end

------------------------------------------------------------------ подарок, коды
RX.Daily.OnServerInvoke = function(plr)
	local d = D[plr]
	if not d then return false end
	local day = math.floor(now() / 86400)
	if d.daily.last == day then return false, "Уже получено сегодня" end
	d.daily.streak = (d.daily.last == day - 1) and (d.daily.streak % 7 + 1) or 1
	d.daily.last = day
	local pn = math.max(1, unlockedPlanets(d))
	local coins = G.Daily.coins[d.daily.streak] * (1 + (pn - 1) * 2)
	addCoins(plr, coins)
	-- в подарок ещё и семя с самой дальней планеты
	local pool = {}
	for _, p in G.PlantList do
		if p.rarity == "common" and G.PlanetIndex[p.planet] == pn then table.insert(pool, p.id) end
	end
	local seed = pool[math.random(1, #pool)]
	d.seeds[seed] = (d.seeds[seed] or 0) + 2
	if not S[plr].sel then S[plr].sel = seed end
	push(plr, "coins", "earned", "seeds", "daily", "sel", "planets")
	return true, coins, seed, d.daily.streak
end
RX.Redeem.OnServerInvoke = function(plr, code)
	local d = D[plr]
	code = type(code) == "string" and code:upper():gsub("%s", "") or ""
	local info = G.Codes[code]
	if not d or not info then return false, "Неверный код" end
	if d.redeemed[code] then return false, "Код уже использован" end
	d.redeemed[code] = true
	addCoins(plr, info.coins)
	push(plr, "coins", "earned", "planets")
	return true, info.text
end

------------------------------------------------------------------ рекорд недели
RX.Top.OnServerInvoke = function(plr)
	local out = {}
	local ok = pcall(function()
		local page = DataStoreService:GetOrderedDataStore("StarGreenhouse_Heavy_" .. weekKey()):GetSortedAsync(false, 10):GetCurrentPage()
		for _, e in page do
			local name = "Игрок"
			pcall(function() name = Players:GetNameFromUserIdAsync(tonumber(e.key)) end)
			table.insert(out, { name = name, kg = e.value / 100 })
		end
	end)
	return out
end

RX.ClaimQuest.OnServerInvoke = function(plr, i)
	local d = D[plr]
	local q = d and type(i) == "number" and d.q[i]
	if not q or q.have < q.need then return false end
	table.remove(d.q, i)
	addCoins(plr, q.reward)
	ensureQuests(d)
	push(plr, "coins", "earned", "planets", "q")
	return true, q.reward
end

-- падающие звёзды
do
	local Stars = require(script.Parent:WaitForChild("Stars"))
	local WT = require(script.Parent:WaitForChild("WorldTerrain"))
	Stars.start({
		parent = workspace:WaitForChild("World"),
		-- случайная точка на планете случайного игрока (звёзды падают там, где играют)
		pickSpot = function()
			local list = {}
			for plr, d in D do
				local ch = plr.Character
				if ch and ch.PrimaryPart then table.insert(list, d.planet or 1) end
			end
			if #list == 0 then return nil end
			local pi = list[math.random(1, #list)]
			local ctr = WT.Centers[pi]
			local a = math.random() * math.pi * 2
			local r = 26 + math.sqrt(math.random()) * (WT.PlayRadius - 34)
			local x, z = ctr.X + math.cos(a) * r, ctr.Z + math.sin(a) * r
			return Vector3.new(x, WT.groundY(x, z, pi), z)
		end,
		isMeteorEvent = function()
			local ev = eventNow()
			return ev ~= nil and ev.id == "meteor"
		end,
		onCollect = function(plr, meteor, pos)
			local d = D[plr]
			if not d then return end
			local pn = math.max(1, unlockedPlanets(d))
			local coins = G.starReward(pn, meteor)
			addCoins(plr, coins)
			d.stats.stars = (d.stats.stars or 0) + 1
			-- иногда звезда приносит семя
			local seed
			local roll = math.random()
			if meteor or roll < 0.08 then
				local pool = {}
				local want = (meteor and math.random() < 0.5) and "rare" or (roll < 0.015 and "rare" or (math.random() < 0.4 and "uncommon" or "common"))
				for _, p in G.PlantList do
					if p.rarity == want and G.PlanetIndex[p.planet] <= pn then table.insert(pool, p.id) end
				end
				seed = pool[math.random(1, math.max(1, #pool))]
				if seed then
					d.seeds[seed] = (d.seeds[seed] or 0) + 1
					if not S[plr].sel then S[plr].sel = seed end
				end
			end
			RX.Collected:FireClient(plr, coins, seed, pos, meteor)
			push(plr, "coins", "earned", "planets", "seeds", "sel", "stats")
			questProgress(plr, "stars", 1)
		end,
	})
end

RX.State.OnServerInvoke = function(plr)
	if not D[plr] then return nil end
	return snapshot(plr)
end

------------------------------------------------------------------ админ (для съёмок и проверки)
------------------------------------------------------------------ поливки
RX.SelectCan.OnServerEvent:Connect(function(plr, tier)
	local d, s = D[plr], S[plr]
	if not d or type(tier) ~= "number" then return end
	tier = math.floor(tier)
	if tier == 0 or (G.Cans[tier] and (d.cans["c" .. tier] or 0) > 0) then
		s.can = tier
		push(plr, "can")
	end
end)
RX.BuyCan.OnServerInvoke = function(plr, tier, qty)
	local d = D[plr]
	local can = type(tier) == "number" and G.Cans[tier]
	if not d or not can or can.robux then return false end
	qty = math.clamp(math.floor(tonumber(qty) or 1), 1, 10)
	local price = G.canPrice(tier, math.max(1, unlockedPlanets(d))) * qty
	if d.coins < price then return false, "Не хватает монет" end
	d.coins -= price
	d.cans["c" .. tier] = (d.cans["c" .. tier] or 0) + qty
	push(plr, "coins", "cans")
	return true
end

------------------------------------------------------------------ полёт на ракете и путь домой
RX.Travel.OnServerInvoke = function(plr, pi)
	local d, s = D[plr], S[plr]
	if not d or type(pi) ~= "number" then return false end
	pi = math.floor(pi)
	if pi < 1 or pi > #G.Planets then return false end
	if pi > unlockedPlanets(d) then return false, "Планета ещё закрыта" end
	if pi == (d.planet or 1) then return false, "Ты уже здесь" end
	if s.traveling then return false end
	s.traveling = true
	releasePlot(plr)
	d.planet = pi
	claimPlot(plr)
	push(plr, "plot", "planet")
	task.delay(G.TravelTime, function()
		s.traveling = false
		local ch = plr.Character
		if ch and plr.Parent then
			ch:PivotTo(Map.padCF(pi))
		end
	end)
	return true, G.TravelTime
end
RX.Home.OnServerInvoke = function(plr)
	local s = S[plr]
	local ch = plr.Character
	if s and s.plot and ch and Map.plots[s.plot] and not s.traveling then
		ch:PivotTo(Map.plots[s.plot].entrance)
		return true
	end
	return false
end

------------------------------------------------------------------ мини-игра «Опыление»
local POLLEN_MUTS = { "frost", "lava", "neon", "electric" }
RX.PollenDone.OnServerInvoke = function(plr, token)
	local d, s = D[plr], S[plr]
	local pl = s and s.pollen
	if not d or not pl or pl.token ~= token or now() > pl.expires then return false end
	s.pollen = nil
	local b = d.beds[pl.bed]
	local t = now()
	if not b or t >= b.ready then return false end
	b.ready = t + (b.ready - t) * 0.65
	local added
	if math.random() < 0.15 then
		local mid = POLLEN_MUTS[math.random(1, #POLLEN_MUTS)]
		if not table.find(b.m, mid) then
			table.insert(b.m, mid)
			added = mid
			b.w = G.rollWeight(G.Plants[b.id], Random.new(), b.m)
		end
	end
	refreshBed(plr, pl.bed)
	return true, added
end
local function pollenTick(t)
	for plr, d in D do
		local s = S[plr]
		local plot = s.plot and Map.plots[s.plot]
		local ch = plr.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if plot and root and (root.Position - plot.center).Magnitude < 75 then
			s.nextPollen = s.nextPollen or (t + 25)
			if t >= s.nextPollen and not (s.pollen and t < s.pollen.expires) then
				local growing = {}
				for i, b in d.beds do
					if t < b.ready then table.insert(growing, i) end
				end
				if #growing > 0 then
					local i = growing[math.random(1, #growing)]
					s.pollen = { token = math.random(1, 1e9), bed = i, expires = t + 16 }
					RX.Pollen:FireClient(plr, i, s.pollen.token)
				end
				s.nextPollen = t + math.random(40, 70)
			end
		end
	end
end

RX.Admin.OnServerInvoke = function(plr, cmd, arg)
	if plr.UserId ~= ADMIN_ID then return false end
	local d, s = D[plr], S[plr]
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if cmd == "coins" then
		addCoins(plr, 1000000)
	elseif cmd == "coinsB" then
		addCoins(plr, 1000000000)
	elseif cmd == "planets" then
		d.earned = math.max(d.earned, G.PlanetUnlock[6])
	elseif cmd == "resetcd" then
		d.cd = { cannon = 0, chest = 0 }
		push(plr, "cd")
	elseif cmd == "tp" then
		local pos = Map.spots[arg == "spiral" and "spiralStart" or arg]
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not pos or not root then return false end
		local off = arg == "chest" and Vector3.new(0, 4, 5) or Vector3.new(0, 4, 9)
		if arg == "spiral" then off = Vector3.new(0, 3, 0) end
		root.CFrame = CFrame.new(pos + off)
	elseif cmd == "seeds" then
		for _, p in G.PlantList do d.seeds[p.id] = (d.seeds[p.id] or 0) + 10 end
		s.sel = s.sel or "moon_01"
	elseif cmd == "mut" then
		if G.Mut[arg] then s.forceMut = arg end
	elseif cmd == "allmut" then
		s.forceAll = true
	elseif cmd == "giant" then
		s.forceGiant = true
	elseif cmd == "ripe" then
		for _, b in d.beds do b.ready = now() end
		refreshAllBeds(plr)
	elseif cmd == "event" then
		for _, ev in G.Events do
			if ev.id == arg then
				forcedEvent = { ev, now() + G.EventLength }
				RX.Event:FireAllClients(ev.id, G.EventLength)
				if ev.grow then
					for p2, d2 in D do
						for _, b in d2.beds do b.ready = now() + flareRemaining(b.ready - now(), G.EventLength) end
						if S[p2].plot then refreshAllBeds(p2) end
					end
				end
			end
		end
	elseif cmd == "stopEvent" then
		forcedEvent = { G.Events[1], 0 }
	elseif cmd == "maxup" then
		for k, u in G.Upgrades do
			if k == "beds" then d.bedCount = u.max else d.upg[k] = u.max end
		end
		refreshAllBeds(plr)
	elseif cmd == "speed" then
		if hum then hum.WalkSpeed = hum.WalkSpeed > 20 and 16 or 48 end
		return true
	elseif cmd == "potion" then
		d.potion = { luck = 10, uses = 20 }
	elseif cmd == "showcase" then
		-- витрина для роликов: огромные созревшие растения с редчайшими мутациями
		local pool = {}
		for _, p in G.PlantList do
			if p.rarity == "mythic" or p.rarity == "legendary" or p.rarity == "epic" then table.insert(pool, p.id) end
		end
		local rare = { "rainbow", "golden", "starry", "plasma", "galactic", "blackhole", "supernova", "singularity", "neon", "crystal" }
		d.bedCount = math.max(d.bedCount, 12)
		for i = 1, 12 do
			local id = pool[math.random(1, #pool)]
			local m = {}
			for _ = 1, math.random(2, 4) do
				local mid = rare[math.random(1, #rare)]
				if not table.find(m, mid) then table.insert(m, mid) end
			end
			local pl = G.Plants[id]
			d.beds[i] = { id = id, t0 = now() - 60, ready = now() - 1, m = m, w = math.floor(pl.kg * math.random(20, 300) * 100) / 100 }
		end
		refreshAllBeds(plr)
	elseif cmd == "pollen" then
		s.nextPollen = 0
		return true
	else
		return false
	end
	push(plr, "coins", "earned", "seeds", "sel", "planets", "upg", "bedCount", "potion")
	return true
end

------------------------------------------------------------------ алхимия, метеорная пушка, звёздный сундук
local function nearSpot(plr, key, radius)
	local pos = Map.spots[key]
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return pos ~= nil and root ~= nil and (root.Position - pos).Magnitude <= radius
end
local function giveElixir(d)
	local e = G.Elixir
	if d.potion.luck == e.luck then d.potion.uses += e.uses else d.potion = { luck = e.luck, uses = e.uses } end
end
local function rewardReveal(plr, head, id, sub, color)
	RX.Reveal:FireClient(plr, { id = id, m = {}, w = G.Plants[id].kg, head = head, sub = sub, color = color })
end

RX.Brew.OnServerInvoke = function(plr, uids)
	local d = D[plr]
	if not d or type(uids) ~= "table" or #uids ~= G.Alchemy.slots then return false, "Нужно 3 плода" end
	if not nearSpot(plr, "alchemy", G.Alchemy.radius) then return false, "Подойди к котлу на Луне" end
	local want, picked = {}, {}
	for _, u in uids do
		if type(u) ~= "number" or want[u] then return false, "Плоды должны быть разными" end
		want[u] = true
	end
	local keep = {}
	for _, f in d.fruits do
		if want[f.uid] then
			if f.fav then return false, "Избранные плоды не варятся" end
			table.insert(picked, f)
		else
			table.insert(keep, f)
		end
	end
	if #picked ~= G.Alchemy.slots then return false, "Плодов нет в сумке" end
	d.fruits = keep
	local res = G.brew(picked, math.max(1, unlockedPlanets(d)), Random.new())
	d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty
	if res.elixir then giveElixir(d) end
	d.stats.brews += 1
	push(plr, "fruits", "seeds", "potion", "stats")
	local plant = G.Plants[res.id]
	local sub = ("%s · семян: %d%s"):format(G.Rarity[plant.rarity].name, res.qty, res.elixir and " · + эликсир удачи x25" or "")
	rewardReveal(plr, res.up and "АЛХИМИЯ: РЕДЧЕ!" or "АЛХИМИЯ!", res.id, sub, G.Rarity[plant.rarity].color)
	return true, res
end

RX.CannonStart.OnServerInvoke = function(plr)
	local d, s = D[plr], S[plr]
	if not d then return false end
	local left = (d.cd.cannon or 0) - now()
	if left > 0 then return false, ("Пушка перезаряжается: %d:%02d"):format(left // 60, left % 60) end
	if not nearSpot(plr, "cannon", G.Cannon.radius) then return false, "Подойди к пушке на Европе" end
	s.cannon = os.clock()
	return true, G.Cannon.duration
end
RX.CannonEnd.OnServerInvoke = function(plr, hits)
	local d, s = D[plr], S[plr]
	if not d or not s.cannon then return false end
	local elapsed = os.clock() - s.cannon
	s.cannon = nil
	hits = math.clamp(math.floor(tonumber(hits) or 0), 0, math.min(G.Cannon.maxHits, math.floor(elapsed * 2.2)))
	d.cd.cannon = now() + G.Cannon.cooldown
	d.stats.meteors += hits
	local res = G.cannonReward(hits, math.max(1, unlockedPlanets(d)), Random.new())
	d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty
	addCoins(plr, res.coins)
	push(plr, "seeds", "cd", "stats")
	local plant = G.Plants[res.id]
	rewardReveal(plr, hits >= 20 and "МЕТКИЙ СТРЕЛОК!" or "МЕТЕОРИТЫ СБИТЫ!", res.id,
		("Сбито: %d · +%s монет · семян: %d"):format(hits, G.fmt(res.coins), res.qty), G.Rarity[plant.rarity].color)
	return true, res
end

game:GetService("ProximityPromptService").PromptTriggered:Connect(function(pr, plr)
	if pr:GetAttribute("Action") ~= "chest" then return end
	local d = D[plr]
	if not d or not nearSpot(plr, "chest", 16) then return end
	local left = (d.cd.chest or 0) - now()
	if left > 0 then
		notify(plr, ("Сундук снова наполнится через %d:%02d"):format(left // 60, left % 60), "bad")
		return
	end
	d.cd.chest = now() + G.Chest.cooldown
	d.stats.chests += 1
	local res = G.chestReward(math.max(1, unlockedPlanets(d)), Random.new())
	d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty
	if res.elixir then giveElixir(d) end
	addCoins(plr, res.coins)
	push(plr, "seeds", "cd", "potion", "stats")
	rewardReveal(plr, "ЗВЁЗДНЫЙ СУНДУК!", res.id, ("+%s монет%s"):format(G.fmt(res.coins), res.elixir and " · эликсир удачи x25" or ""), Color3.fromRGB(255, 215, 120))
end)

------------------------------------------------------------------ покупки за Robux
local function grant(plr, key)
	local d = D[plr]
	local prod = G.Products[key]
	if key == "small" or key == "big" then
		local po = G.Potions[key]
		if d.potion.luck == po.luck then d.potion.uses += po.uses else d.potion = { luck = po.luck, uses = po.uses } end
	elseif key == "growth2x" or key == "auto" then
		d.perms[key] = true
	elseif key == "cans5" then
		d.cans.c5 = (d.cans.c5 or 0) + 10
		push(plr, "cans")
	elseif key == "beds" then
		d.bedCount = math.min(Map.MaxBeds, d.bedCount + 4)
		refreshAllBeds(plr)
	end
	push(plr, "perms", "potion", "bedCount")
	notify(plr, "Покупка получена: " .. prod.name, "ok")
end
MarketplaceService.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	if not plr or not D[plr] then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local d = D[plr]
	local rid = tostring(info.PurchaseId)
	if d.receipts[rid] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	for key, prod in G.Products do
		if prod.id ~= 0 and prod.id == info.ProductId then
			d.receipts[rid] = true
			-- хранить только последние 60 чеков
			local n = 0
			for _ in d.receipts do n += 1 end
			if n > 60 then
				for k in d.receipts do d.receipts[k] = nil break end
			end
			grant(plr, key)
			save(plr)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

------------------------------------------------------------------ игроки
local function onJoin(plr)
	S[plr] = { loaded = false, canSave = false, sel = nil }
	local d, ok = load(plr.UserId)
	if not plr.Parent then return end
	D[plr] = d
	S[plr].canSave = ok
	S[plr].loaded = true
	S[plr].sel = next(d.seeds)
	ensureQuests(d)
	d.planet = math.clamp(d.planet or 1, 1, math.max(1, unlockedPlanets(d)))
	claimPlot(plr)
	-- что выросло, пока игрока не было
	local ripe = 0
	for _, b in d.beds do
		if b.ready > d.lastSeen and b.ready <= now() then ripe += 1 end
	end
	push(plr, "coins")
	RX.Sync:FireClient(plr, snapshot(plr))
	if ripe > 0 then
		task.delay(3, function() if plr.Parent then notify(plr, ("Пока тебя не было, созрело растений: %d"):format(ripe), "ok") end end)
	end
	if not ok then notify(plr, "Сохранение недоступно: прогресс этой сессии не запишется", "bad") end
	if plr.Character then teleportToPlot(plr) end
end

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function(ch)
		-- ждём загрузку профиля
		task.spawn(function()
			for _ = 1, 100 do
				if S[plr] and S[plr].loaded then break end
				task.wait(0.1)
			end
			teleportToPlot(plr)
		end)
	end)
	task.spawn(onJoin, plr)
end)
Players.PlayerRemoving:Connect(function(plr)
	save(plr)
	releasePlot(plr)
	D[plr], S[plr] = nil, nil
end)
for _, plr in Players:GetPlayers() do task.spawn(onJoin, plr) end
game:BindToClose(function()
	for _, plr in Players:GetPlayers() do save(plr) end
end)

------------------------------------------------------------------ фоновые циклы
-- автосохранение
task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do
			if D[plr] then task.spawn(save, plr) end
		end
	end
end)

-- события по часам, авто-сбор, табло рынка
local lastSlot = -1
local lastBoard = 0
task.spawn(function()
	while true do
		task.wait(1)
		local t = now()
		local slot = math.floor(t / G.EventPeriod)
		local ev, left = eventNow()
		ReplicatedStorage:SetAttribute("EventId", ev and ev.id or "")
		ReplicatedStorage:SetAttribute("EventEnd", ev and (t + left) or 0)
		if ev and slot ~= lastSlot then
			lastSlot = slot
			RX.Event:FireAllClients(ev.id, left)
			if ev.grow then
				for plr, d in D do
					for i, b in d.beds do b.ready = t + flareRemaining(b.ready - t, left) end
					if S[plr].plot then refreshAllBeds(plr) end
				end
			end
		end
		-- метеоритный дождь: метеориты по очереди бьют в растущие грядки и могут добавить мутацию
		if ev and ev.luck and math.random() < 0.3 then
			local cands = {}
			for plr, d in D do
				if S[plr].plot then
					for i, b in d.beds do
						if t < b.ready then table.insert(cands, { plr, d, i, b }) end
					end
				end
			end
			if #cands > 0 then
				local pick = cands[math.random(1, #cands)]
				local plr, d, i, b = pick[1], pick[2], pick[3], pick[4]
				local added
				for _, mid in G.rollMutations(G.upgradeValue("luck", d.upg.luck) * ev.luck, Random.new()) do
					if not table.find(b.m, mid) then
						table.insert(b.m, mid)
						added = added or mid
					end
				end
				if added then
					b.w = G.rollWeight(G.Plants[b.id], Random.new(), b.m)
					refreshBed(plr, i)
				end
				local plot = Map.plots[S[plr].plot]
				local pos = plot and plot.beds[i] and plot.beds[i].pos
				if pos then RX.Strike:FireAllClients(pos, added, plr.DisplayName) end
			end
		end
		pollenTick(t)
		-- упал с острова: свободное падение с неба на свою планету
		do
			local WT = require(script.Parent:WaitForChild("WorldTerrain"))
			for plr, d in D do
				local ch = plr.Character
				local root = ch and ch:FindFirstChild("HumanoidRootPart")
				if root and not S[plr].traveling then
					local near = WT.planetAt(root.Position)
					if root.Position.Y < WT.Centers[near].Y - 70 then
						local home = WT.Centers[d.planet or 1]
						local a = math.random() * math.pi * 2
						ch:PivotTo(CFrame.new(home + Vector3.new(math.cos(a) * 30, 190, math.sin(a) * 30)))
						root.AssemblyLinearVelocity = Vector3.new(0, -20, 0)
						RX.Skydive:FireClient(plr)
					end
				end
			end
		end
		-- авто-сбор
		for plr, d in D do
			if d.perms.auto then
				for i, b in d.beds do
					if t >= b.ready then harvestBed(plr, i, true) end
				end
			end
		end
		currentSold()
		-- табло рынка раз в 10 секунд
		if #Map.boardLabels > 0 and t - lastBoard >= 10 then
			lastBoard = t
			local epoch = G.marketEpoch(t)
			local lines = { "<b>ГОРЯЧИЙ СПРОС x3</b>" }
			for id in G.hotPlants(epoch) do table.insert(lines, G.Plants[id].name) end
			table.insert(lines, "Обновление через " .. G.fmtTime(G.marketTimeLeft(t)))
			for _, lbl in Map.boardLabels do lbl.Text = table.concat(lines, "\n") end
		end
	end
end)

