-- «Звёздная оранжерея»: сервер. Всё важное считается здесь: посадка, рост, мутации, продажи, магазин, события, сохранения.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local G = require(Shared:WaitForChild("Game"))
local Map = require(script.Parent:WaitForChild("Map"))
local StarsMod = require(script.Parent:WaitForChild("Stars"))

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
task.spawn(function()
	local PetLoader = require(script.Parent:WaitForChild("PetLoader"))
	print("PetLoader: детали питомцев", PetLoader.run())
end)

local lastGlobalAnn = 0 -- рассылка редких находок на другие сервера не чаще раза в 5 с
------------------------------------------------------------------ ремоуты
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local RX = {}
for _, n in { "Sync", "Notify", "Reveal", "Stock", "Event", "Announce", "Act", "Select", "Harvest", "Collected", "Strike", "Pollen", "Skydive", "SelectCan", "Settings", "PetFx", "Slots", "Raid", "RaidHit", "Boost", "Trade", "TradeRespond", "TradeOffer", "TradeReady", "TradeCancel", "Contest" } do
	local e = Instance.new("RemoteEvent")
	e.Name = n
	e.Parent = remotes
	RX[n] = e
end
for _, n in { "Buy", "Sell", "Upgrade", "BuyDecor", "Daily", "Redeem", "Fav", "Top", "Admin", "State", "ClaimQuest", "Travel", "Home", "PollenDone", "BuyCan", "Brew", "CannonStart", "CannonEnd", "FishCast", "FishResult", "BuyMystic", "RaceStart", "RaceFinish", "TpTo", "PetBuy", "PetEquip", "TradeRequest", "ContestVote", "ContestView" } do
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
		q = {}, planet = 1, cans = { c1 = 3, c2 = 0, c3 = 0, c4 = 0, c5 = 0 }, cd = { cannon = 0, chest = 0, race = 0 }, gardens = {}, bonusBeds = 0, settings = { m = 6, s = 8, h = 1, t = 1, c = 1, a = 1 }, slots = {}, bait = { n = 10, t = 0 }, race = { best = 0, runs = 0 }, pets = { owned = {}, eq = "" },
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
	-- цены планет выросли: уже открытые по старым порогам планеты сохраняются
	if not d.econ2 then
		local n = 0
		for i, need in G.PlanetUnlockOld do
			if (d.earned or 0) >= need then n = i end
		end
		d.reached, d.econ2 = math.max(d.reached or 0, n), true
	end
	-- трасса гонки стала длиннее (планеты x1.3): старые рекорды не сравнимы
	if (d.race.track or 1) < 2 then d.race.best, d.race.track = 0, 2 end
	if d.pets then
		for old, new in G.PetLegacy do
			if d.pets.owned[old] then
				d.pets.owned[new] = math.max(d.pets.owned[new] or 0, d.pets.owned[old])
				d.pets.owned[old] = nil
			end
			if d.pets.eq == old then d.pets.eq = new end
		end
	end
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
	-- планеты, открытые до подорожания, остаются открытыми
	return math.max(n, d.reached or 0)
end

-- сводка огородов по планетам для окна полёта: грядок, посажено, созрело
local function gardenSummary(d)
	local out = {}
	local t = now()
	for pi = 1, #G.Planets do
		local beds, count
		if pi == (d.planet or 1) then
			beds, count = d.beds, d.bedCount
		else
			local g = d.gardens[tostring(pi)]
			beds, count = g and g.beds or {}, g and g.bedCount or 0
		end
		local planted, ripe = 0, 0
		for _, b in beds do
			planted += 1
			if t >= b.ready then ripe += 1 end
		end
		out[pi] = { beds = count, planted = planted, ripe = ripe }
	end
	return out
end

local function snapshot(plr)
	local d = D[plr]
	local s = S[plr]
	local epoch = G.shopEpoch(now())
	return {
		coins = d.coins, earned = d.earned, seeds = d.seeds, fruits = d.fruits, upg = d.upg, decor = d.decor, idx = d.idx, mutSeen = d.mutSeen,
		perms = d.perms, potion = d.potion, bedCount = d.bedCount, plot = s.plot, bagCap = BAG_CAP, stats = d.stats, sel = s.sel,
		bought = s.bought and s.bought.epoch == epoch and s.bought.n or {},
		daily = { can = d.daily.last ~= math.floor(now() / 86400), streak = d.daily.streak,
			nextDay = (d.daily.last == math.floor(now() / 86400) - 1) and (d.daily.streak % 7 + 1) or ((d.daily.last == math.floor(now() / 86400)) and d.daily.streak or 1) },
		planets = unlockedPlanets(d), sold = soldNow.epoch == epoch and soldNow.sold or {}, q = d.q, planet = d.planet or 1, cans = d.cans, can = s.can or 0, cd = d.cd, gsum = gardenSummary(d), settings = d.settings, bait = d.bait, mystic = s.mystic or {}, race = d.race, pets = d.pets, slots = d.slots,
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
local function paintBed(plotId, i, b, locked)
	local plot = plotId and Map.plots[plotId]
	if not plot or not plot.beds[i] then return end
	local soil = plot.beds[i].soil
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
	Map.setBedLocked(plotId, i, locked)
end
local function refreshBed(plr, i)
	local s, d = S[plr], D[plr]
	paintBed(s.plot, i, d.beds[i], i > d.bedCount)
end
local function refreshAllBeds(plr)
	for i = 1, Map.MaxBeds do refreshBed(plr, i) end
end
-- огород на другой планете (хозяин не здесь): данные лежат в d.gardens
local function paintStash(plr, pi)
	local s, d = S[plr], D[plr]
	local g = d.gardens[tostring(pi)]
	local id = s.plots[pi]
	if not g or not id then return end
	for i = 1, Map.MaxBeds do paintBed(id, i, g.beds[tostring(i)], i > g.bedCount) end
end

-- у игрока свой огород на каждой планете; s.plots[планета] = id построенного участка, s.plot = огород там, где игрок сейчас
local function buildPlotOn(plr, pi)
	local s, d = S[plr], D[plr]
	if s.plots[pi] then return s.plots[pi] end
	for j = 1, Map.SlotsPerPlanet do
		local key = pi .. "_" .. j
		if not plotOwner[key] then
			plotOwner[key] = plr
			local plot = Map.buildPlot(pi, j)
			s.plots[pi] = plot.id
			plot.model:SetAttribute("OwnerId", plr.UserId)
			Map.setPlotSign(plot.id, plr.DisplayName, G.PlanetColors[math.clamp(unlockedPlanets(d), 1, 6)])
			for _, id in G.DecorOrder do
				if d.decor[id] then Map.placeDecor(plot.id, id) end
			end
			return plot.id
		end
	end
	return nil
end
local function claimPlot(plr)
	local s, d = S[plr], D[plr]
	local pi = math.clamp(d.planet or 1, 1, #G.Planets)
	s.plot = buildPlotOn(plr, pi)
	if s.plot then refreshAllBeds(plr) end
	return s.plot ~= nil
end
local function releaseOne(plr, pi)
	local s = S[plr]
	local id = s and s.plots[pi]
	if not id then return end
	plotOwner[id] = nil
	Map.destroyPlot(id)
	s.plots[pi] = nil
	if s.plot == id then s.plot = nil end
end
local function releasePlot(plr)
	local s = S[plr]
	if not s then return end
	for pi in table.clone(s.plots) do releaseOne(plr, pi) end
	s.plot = nil
end
-- огороды на других планетах, где что-то растёт, видны всем
local function buildStashPlots(plr)
	local d = D[plr]
	for key, g in d.gardens do
		local pi = tonumber(key)
		if pi and pi ~= d.planet and next(g.beds) then
			if buildPlotOn(plr, pi) then paintStash(plr, pi) end
		end
	end
end
-- переезд: текущий огород уходит «на хранение» (там растёт медленнее), огород новой планеты становится активным
local function switchGarden(plr, newPi)
	local s, d = S[plr], D[plr]
	local t = now()
	local old = d.planet or 1
	local stash = {}
	for i, b in d.beds do
		if b.ready > t then b.ready = t + (b.ready - t) / G.AwayGrowth end
		stash[tostring(i)] = b
	end
	d.gardens[tostring(old)] = { beds = stash, bedCount = d.bedCount }
	if next(stash) and s.plots[old] then
		s.plot = nil
		paintStash(plr, old)
	else
		releaseOne(plr, old)
	end
	s.plot = nil
	local g = d.gardens[tostring(newPi)] or { beds = {}, bedCount = G.GardenStartBeds + (d.bonusBeds or 0) }
	d.gardens[tostring(newPi)] = nil
	local beds = {}
	for k, b in g.beds do
		if b.ready > t then b.ready = t + (b.ready - t) * G.AwayGrowth end
		beds[tonumber(k)] = b
	end
	d.beds, d.bedCount = beds, g.bedCount
	d.planet = newPi
	claimPlot(plr)
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
local BOOST = { luck = 0, gold = 0 } -- до какого времени действуют админ-ивенты на всех серверах
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
	do
		local pe = d.pets.eq or ""
		local pl = pe ~= "" and d.pets.owned[pe]
		if pl then speed /= math.max(0.2, 1 - G.petGrow(pe, pl)) end
	end
	if G.PlanetIndex[plant.planet] == (d.planet or 1) then speed *= G.NativeBonus end
	local base = plant.grow * (regrow and plant.regrow > 0 and plant.regrow or 1)
	local t = now()
	local ready = t + math.max(3, base / speed)
	local ev, left = eventNow()
	if ev and ev.grow then ready = t + flareRemaining(ready - t, left) end
	local luck = G.upgradeValue("luck", d.upg.luck) * (G.PlanetLuck[d.planet or 1] or 1)
	local peq = d.pets.eq or ""
	local plv = peq ~= "" and d.pets.owned[peq]
	if plv then luck *= G.petLuck(peq, plv) end
	if now() < BOOST.luck then luck *= G.Boosts.luck.mult end
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
		RX.Announce:FireAllClients(plr.DisplayName, plant.name, G.mutTitle(b.m), chance, pl and pl.beds[i] and pl.beds[i].pos, false, plr.UserId)
		-- и в чат всех других серверов игры
		if now() - lastGlobalAnn >= 5 then
			lastGlobalAnn = now()
			local msg = { job = game.JobId, who = plr.DisplayName, plant = plant.name, title = G.mutTitle(b.m), chance = chance }
			task.spawn(function()
				pcall(function() game:GetService("MessagingService"):PublishAsync("SG_RareFind", msg) end)
			end)
		end
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
local function fruitPrice(f, d)
	local plant = G.Plants[f.id]
	local mm = G.marketMult(plant, G.marketEpoch(now()))
	local bonus = 1
	if d then
		local pe = d.pets.eq or ""
		local pl = pe ~= "" and d.pets.owned[pe]
		if pl then bonus += G.petSell(pe, pl) end
	end
	return G.fruitValue(f.id, f.m, f.w, mm, sellFactor() * bonus)
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

-- продажа и покупка семян только у киосков на площади своей планеты
local KIOSK_RADIUS = 14
local function nearKiosk(plr, id)
	local d = D[plr]
	local pos = d and Map.spots[id .. (d.planet or 1)]
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return pos ~= nil and root ~= nil and (root.Position - pos).Magnitude <= KIOSK_RADIUS
end
RX.TpTo.OnServerInvoke = function(plr, id)
	local d, s = D[plr], S[plr]
	if not d or s.traveling then return false end
	if id == "place" then
		-- занятие этой планеты: алхимия, гонка, пушка, рыбалка, паркур, телескоп
		local pi = d.planet or 1
		local pos = Map.spots[G.PlanetPlaceSpot[pi]]
		local ch = plr.Character
		if not pos or not ch then return false end
		local ctr = Map.planets[pi].center
		local toC = (ctr - pos) * Vector3.new(1, 0, 1)
		local target = G.PlanetPlaceSpot[pi] == "spiralStart" and pos + Vector3.new(0, 3, 0) or pos + (toC.Magnitude > 0.1 and toC.Unit * 8 or Vector3.zero) + Vector3.new(0, 4, 0)
		local flat = Vector3.new(pos.X, target.Y, pos.Z)
		ch:PivotTo((flat - target).Magnitude > 0.5 and CFrame.lookAt(target, flat) or CFrame.new(target))
		return true
	end
	if id ~= "shop" and id ~= "sell" and id ~= "market" and id ~= "upgrades" then return false end
	local pos = Map.spots[id .. (d.planet or 1)]
	local front = Map.spots[id .. "Front" .. (d.planet or 1)]
	local ch = plr.Character
	if not pos or not front or not ch then return false end
	ch:PivotTo(CFrame.lookAt(front + Vector3.new(0, 3, 0), pos + Vector3.new(0, 3, 0)))
	return true
end
RX.Sell.OnServerInvoke = function(plr, mode, uid)
	local d = D[plr]
	if not d then return false end
	if not nearKiosk(plr, "sell") then return false, "Продавать можно у золотого киоска «Продажа» на площади" end
	local total, count, keep = 0, 0, {}
	if mode == "all" then
		for _, f in d.fruits do
			if f.fav then
				table.insert(keep, f)
			else
				total += fruitPrice(f, d)
				count += 1
			end
		end
		d.fruits = keep
	elseif mode == "one" then
		for _, f in d.fruits do
			if f.uid == uid and count == 0 then
				total += fruitPrice(f, d)
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
	if not nearKiosk(plr, "shop") then return false, "Семена покупают у зелёного киоска «Семена» на площади" end
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
	local cost = key == "beds" and G.bedCost(level, d.planet or 1) or G.upgradeCost(key, level)
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
	local cal = G.Calendar[d.daily.streak]
	local rng = Random.new()
	local text
	if cal.kind == "coins" then
		local coins = G.starReward(pn, false) * 60 * cal.mult
		addCoins(plr, coins)
		text = ("+%s монет"):format(G.fmt(coins))
	elseif cal.kind == "seed" then
		local id = G.pickSeed(cal.rank, pn, rng)
		d.seeds[id] = (d.seeds[id] or 0) + cal.qty
		if not S[plr].sel then S[plr].sel = id end
		text = ("%s x%d"):format(G.Plants[id].name, cal.qty)
	elseif cal.kind == "cans" then
		d.cans["c" .. cal.tier] = (d.cans["c" .. cal.tier] or 0) + cal.qty
		text = ("%s x%d"):format(G.Cans[cal.tier].name, cal.qty)
	else
		local id = G.pickSeed(5, pn, rng)
		d.seeds[id] = (d.seeds[id] or 0) + 1
		d.cans.c5 = (d.cans.c5 or 0) + 5
		text = ("%s и 5 леек сверхновой"):format(G.Plants[id].name)
		RX.Reveal:FireClient(plr, { id = id, m = {}, w = G.Plants[id].kg, head = "7 ДНЕЙ ПОДРЯД!", sub = "Легендарное семя и 5 леек сверхновой", color = Color3.fromRGB(255, 205, 70), sfx = "chest" })
	end
	push(plr, "coins", "earned", "seeds", "daily", "sel", "planets", "cans")
	return true, text, d.daily.streak
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

------------------------------------------------------------------ таблица лидеров
-- в упорядоченных хранилищах только целые числа: богатство и редкость храним логарифмом
local LB = { rich = {}, heavy = {}, rare = {}, race = {}, at = 0 }
local nameCache = {}
local function nameOf(uid)
	if nameCache[uid] then return nameCache[uid] end
	local n = "Игрок"
	pcall(function() n = Players:GetNameFromUserIdAsync(uid) end)
	nameCache[uid] = n
	return n
end
local function lbWrite(plr)
	local d = D[plr]
	if not d or not S[plr] or not S[plr].canSave then return end
	pcall(function()
		if d.earned > 0 then
			DataStoreService:GetOrderedDataStore("SG_Rich"):SetAsync(tostring(plr.UserId), math.floor(math.log10(d.earned + 1) * 1e6))
		end
		if d.stats.bestChance < 1 then
			DataStoreService:GetOrderedDataStore("SG_Rare"):SetAsync(tostring(plr.UserId), math.floor(-math.log10(d.stats.bestChance) * 1e6))
		end
	end)
end
local function lbTop(store, decode, ascending)
	local out = {}
	pcall(function()
		local page = store:GetSortedAsync(ascending == true, 10):GetCurrentPage()
		for _, e in page do
			local uid = tonumber(e.key)
			table.insert(out, { id = uid, name = nameOf(uid), v = decode(e.value) })
		end
	end)
	return out
end
local function lbFill(rows, list, fmtv)
	for i, row in rows do
		local e = list[i]
		row.name.Text = e and e.name or (i == 1 and "пока пусто" or "")
		row.val.Text = e and fmtv(e.v) or ""
	end
end
local function lbRefresh()
	LB.rich = lbTop(DataStoreService:GetOrderedDataStore("SG_Rich"), function(v) return 10 ^ (v / 1e6) end)
	LB.rare = lbTop(DataStoreService:GetOrderedDataStore("SG_Rare"), function(v) return 10 ^ (-v / 1e6) end)
	LB.heavy = lbTop(DataStoreService:GetOrderedDataStore("StarGreenhouse_Heavy_" .. weekKey()), function(v) return v / 100 end)
	LB.race = lbTop(DataStoreService:GetOrderedDataStore("SG_MarsRace2"), function(v) return v / 1000 end, true)
	LB.at = now()
	for _, b in Map.leaderBoards do
		lbFill(b.rich, LB.rich, G.fmt)
		lbFill(b.heavy, LB.heavy, function(v) return ("%.1f кг"):format(v) end)
		lbFill(b.rare, LB.rare, G.fmtOdds)
	end
end
local function serverList()
	local out = {}
	for p, d in D do
		table.insert(out, { id = p.UserId, name = p.DisplayName, v = d.earned, planet = d.planet or 1, best = d.stats.bestChance })
	end
	table.sort(out, function(a, b) return a.v > b.v end)
	return out
end
RX.Top.OnServerInvoke = function(plr)
	return { rich = LB.rich, heavy = LB.heavy, rare = LB.rare, race = LB.race, server = serverList() }
end
-- строка в списке игроков Roblox
local function updateLeaderstats(plr)
	local d = D[plr]
	if not d then return end
	local ls = plr:FindFirstChild("leaderstats")
	if not ls then
		ls = Instance.new("Folder")
		ls.Name = "leaderstats"
		for _, n in { "Заработано", "Планета" } do
			local v = Instance.new("StringValue")
			v.Name = n
			v.Parent = ls
		end
		ls.Parent = plr
	end
	ls["Заработано"].Value = G.fmt(d.earned)
	ls["Планета"].Value = G.Planets[d.planet or 1].name
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
			return (ev ~= nil and ev.id == "meteor") or now() < BOOST.gold
		end,
		onCollect = function(plr, meteor, pos)
			local d = D[plr]
			if not d then return end
			local pn = math.max(1, unlockedPlanets(d))
			local coins = G.starReward(pn, meteor)
			if now() < BOOST.gold then coins *= G.Boosts.gold.mult end
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
RX.Settings.OnServerEvent:Connect(function(plr, m, sv, h, tk, ch, au)
	local d = D[plr]
	if not d then return end
	local function n(v, def) return math.clamp(math.floor(tonumber(v) or def), 0, 10) end
	d.settings = { m = n(m, 6), s = n(sv, 8), h = (h == 0) and 0 or 1, t = (tk == 2) and 2 or 1, c = (ch == 0) and 0 or 1, a = (au == 0) and 0 or 1 }
end)
-- 7 слотов семян внизу экрана: игрок сам ставит туда семена из сумки
RX.Slots.OnServerEvent:Connect(function(plr, list)
	local d = D[plr]
	if not d or type(list) ~= "table" then return end
	local out = {}
	for i = 1, G.SeedSlots do
		local id = list[i]
		out[i] = (type(id) == "string" and G.Plants[id]) and id or ""
	end
	d.slots = out
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
	switchGarden(plr, pi)
	push(plr, "plot", "planet", "bedCount", "gsum")
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

local grant -- покупки за Robux (объявлено ниже)
local applyPet -- питомец игрока (объявлено ниже)
local CONTEST = {} -- конкурс огородов (функции ниже)
local applyGlobal -- админ-ивент на этом сервере (ниже)
local RAID = { active = false, hp = 0, max = 0, ends = 0, hits = {}, last = {}, recent = {}, warned = false } -- рейд кометы (ниже)
RX.Admin.OnServerInvoke = function(plr, cmd, arg)
	if plr.UserId ~= ADMIN_ID then return false end
	local d, s = D[plr], S[plr]
	local ch = plr.Character
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if cmd == "coins" then
		addCoins(plr, 1000000)
	elseif cmd == "coinsB" then
		-- монеты x10 (минимум +1Qa): работает и при 7Dd на счету
		addCoins(plr, math.max(1e15, d.coins * 9))
	elseif cmd == "planets" then
		d.earned = math.max(d.earned, G.PlanetUnlock[6])
	elseif cmd == "contest" then
		return CONTEST.start(true)
	elseif cmd == "raid" then
		return RAID.start()
	elseif cmd == "contestEnd" then
		CONTEST.endNow()
	elseif cmd == "pets" then
		for _, id in G.PetOrder do d.pets.owned[id] = G.PetMaxLevel end
		d.pets.eq = d.pets.eq ~= "" and d.pets.eq or "bunny"
		applyPet(plr)
		push(plr, "pets")
	elseif cmd == "alldonate" then
		for _, key in G.ProductOrder do
			if G.Products[key] and grant then grant(plr, key) end
		end
	elseif cmd == "mystic" then
		ReplicatedStorage:SetAttribute("MysticForce", now() + G.Mystic.open)
	elseif cmd == "resetcd" then
		d.cd = { cannon = 0, chest = 0, race = 0 }
		d.bait = { n = G.Fishing.baitMax, t = now() }
		push(plr, "cd", "bait")
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
		applyGlobal("g_event", arg)
	elseif cmd:sub(1, 2) == "g_" then
		-- админ-ивент на всех серверах: этот сервер сразу, остальные через MessagingService
		applyGlobal(cmd, arg)
		task.spawn(function()
			pcall(function() game:GetService("MessagingService"):PublishAsync("SG_Admin", { job = game.JobId, cmd = cmd, arg = arg }) end)
		end)
		return true
	elseif cmd == "stopEvent" then
		forcedEvent = { G.Events[1], 0 }
	elseif cmd == "maxup" then
		for k, u in G.Upgrades do
			if k == "beds" then d.bedCount = u.max else d.upg[k] = u.max end
		end
		refreshAllBeds(plr)
	elseif cmd == "speed" then
		if hum then hum.WalkSpeed = hum.WalkSpeed > 30 and 22 or 48 end
		return true
	elseif cmd == "potion" then
		d.potion = { luck = 10, uses = 20 }
	elseif cmd == "showcase" then
		-- витрина для роликов: огромные созревшие растения с редчайшими мутациями
		local pool = {}
		for _, p in G.PlantList do
			if p.rarity == "mythic" or p.rarity == "legendary" or p.rarity == "epic" then table.insert(pool, p.id) end
		end
		-- в каждой грядке минимум одна высшая мутация (уровень 5–6) и пара красивых поменьше
		local top = { "starry", "plasma", "galactic", "blackhole", "supernova", "singularity" }
		local extra = { "rainbow", "golden", "neon", "crystal", "electric", "ghost" }
		d.bedCount = math.max(d.bedCount, 12)
		for i = 1, 12 do
			local id = pool[math.random(1, #pool)]
			local m = { top[(i - 1) % #top + 1] }
			if math.random() < 0.5 then
				local t2 = top[math.random(1, #top)]
				if not table.find(m, t2) then table.insert(m, t2) end
			end
			for _ = 1, math.random(1, 2) do
				local mid = extra[math.random(1, #extra)]
				if not table.find(m, mid) then table.insert(m, mid) end
			end
			local pl = G.Plants[id]
			d.beds[i] = { id = id, t0 = now() - 60, ready = now() - 1, m = m, w = math.floor(pl.kg * math.random(20, 300) * 100) / 100 }
		end
		refreshAllBeds(plr)
	elseif cmd == "revealShow" then
		-- для роликов: показать полную сцену сверхредкой находки только себе (данные не меняются)
		local pool = {}
		for _, p in G.PlantList do if p.rarity == "mythic" then table.insert(pool, p.id) end end
		local id = pool[math.random(1, #pool)]
		local m = { "singularity", ({ "supernova", "galactic", "plasma" })[math.random(1, 3)] }
		local chance = G.mutChance(m)
		local pl = s.plot and Map.plots[s.plot]
		local pos = pl and pl.beds[1] and pl.beds[1].pos or (plr.Character and plr.Character:GetPivot().Position)
		RX.Reveal:FireClient(plr, { id = id, m = m, w = math.floor(G.Plants[id].kg * 120 * 100) / 100, chance = chance })
		RX.Announce:FireClient(plr, plr.DisplayName, G.Plants[id].name, G.mutTitle(m), chance, pos, false, plr.UserId)
		return true
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
local function rewardReveal(plr, head, id, sub, color, snd)
	RX.Reveal:FireClient(plr, { id = id, m = {}, w = G.Plants[id].kg, head = head, sub = sub, color = color, sfx = snd })
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
	rewardReveal(plr, res.up and "АЛХИМИЯ: РЕДЧЕ!" or "АЛХИМИЯ!", res.id, sub, G.Rarity[plant.rarity].color, "brew")
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

-- мистический торговец
RX.BuyMystic.OnServerInvoke = function(plr, id)
	local d, s = D[plr], S[plr]
	if not d or type(id) ~= "string" then return false end
	local open, _, epoch = G.mysticOpen(now(), ReplicatedStorage:GetAttribute("MysticForce"))
	if not open then return false, "Торговец уже ушёл" end
	local pi = d.planet or 1
	if not nearSpot(plr, "mystic" .. pi, G.Mystic.radius) then return false, "Подойди к торговцу на площади" end
	local item
	for _, it in G.mysticStock(epoch, pi) do
		if it.id == id then item = it end
	end
	if not item then return false, "Этого семени у торговца нет" end
	s.mystic = s.mystic or {}
	local key = epoch .. ":" .. id
	if (s.mystic[key] or 0) >= item.limit then return false, "Лимит на этот визит исчерпан" end
	if d.coins < item.price then return false, "Не хватает монет" end
	d.coins -= item.price
	s.mystic[key] = (s.mystic[key] or 0) + 1
	d.seeds[id] = (d.seeds[id] or 0) + 1
	push(plr, "coins", "seeds", "mystic")
	return true
end
-- лавка торговца появляется и исчезает по расписанию
task.spawn(function()
	local was
	while true do
		local open = G.mysticOpen(now(), ReplicatedStorage:GetAttribute("MysticForce"))
		if open ~= was then
			was = open
			for pi, stall in Map.mysticStalls do
				stall.model.Parent = open and stall.parent or nil
			end
		end
		task.wait(1)
	end
end)

-- питомцы: покупка/улучшение, выбор; клиенты рисуют питомца по атрибутам игрока
function applyPet(plr)
	local d = D[plr]
	if not d then return end
	local eq = d.pets.eq or ""
	plr:SetAttribute("Pet", eq)
	plr:SetAttribute("PetLvl", eq ~= "" and (d.pets.owned[eq] or 0) or 0)
end
RX.PetBuy.OnServerInvoke = function(plr, id)
	local d = D[plr]
	if not d or type(id) ~= "string" or not G.Pets[id] then return false end
	local lvl = d.pets.owned[id] or 0
	if lvl >= G.PetMaxLevel then return false, "Максимальный уровень" end
	if G.Pets[id].planet > math.max(1, unlockedPlanets(d)) then return false, "Откроется вместе с планетой " .. G.Planets[G.Pets[id].planet].name end
	local price = G.petPrice(id, lvl + 1, math.max(1, unlockedPlanets(d)))
	if d.coins < price then return false, "Не хватает монет" end
	d.coins -= price
	d.pets.owned[id] = lvl + 1
	if (d.pets.eq or "") == "" or d.pets.eq == id then d.pets.eq = id end
	applyPet(plr)
	push(plr, "coins", "pets")
	return true, lvl + 1
end
RX.PetEquip.OnServerInvoke = function(plr, id)
	local d = D[plr]
	if not d or type(id) ~= "string" then return false end
	if id ~= "" and not d.pets.owned[id] then return false end
	d.pets.eq = id
	applyPet(plr)
	push(plr, "pets")
	return true
end
-- работа питомцев: светлячок собирает звёзды, поливобот поливает грядки
task.spawn(function()
	while true do
		task.wait(0.5)
		local t = now()
		for plr, d in D do
			local s = S[plr]
			local eq = d.pets.eq
			local lvl = eq and d.pets.owned[eq]
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if lvl and root and s then
				local sr = G.petStars(eq, lvl)
				if sr > 0 and StarsMod.tryCollect then StarsMod.tryCollect(plr, root.Position, sr) end
				if G.petWater(eq, lvl) > 0 and t >= (s.nextBot or 0) then
					local plot = s.plot and Map.plots[s.plot]
					if plot and (root.Position - plot.center).Magnitude < 90 then
						s.nextBot = t + G.petWater(eq, lvl)
						for i, b in d.beds do
							if t < b.ready and (not b.wt or t - b.wt >= G.WaterCooldown) and i <= d.bedCount then
								local pct = G.upgradeValue("water", d.upg.water) / 100
								b.ready = t + (b.ready - t) * (1 - pct)
								b.wt = t
								refreshBed(plr, i)
								questProgress(plr, "water", 1)
								RX.PetFx:FireClient(plr, "water", i)
								break
							end
						end
					end
				end
			end
		end
	end
end)

-- обмен плодами между игроками: запрос, предложения обеих сторон, «готов», обмен целиком на сервере
local trades, tradeReq = {}, {}
local TRADE_MAX = 6
local function fruitView(d, uids)
	local out = {}
	for _, u in uids do
		for _, f in d.fruits do
			if f.uid == u then table.insert(out, { uid = f.uid, id = f.id, m = f.m, w = f.w }) break end
		end
	end
	return out
end
local function tradeSend(T)
	for _, p in { T.a, T.b } do
		local o = p == T.a and T.b or T.a
		if D[p] and D[o] then
			RX.Trade:FireClient(p, { state = "open", partner = o.DisplayName, mine = fruitView(D[p], T.offer[p]), theirs = fruitView(D[o], T.offer[o]),
				myReady = T.ready[p] == true, theirReady = T.ready[o] == true })
		end
	end
end
local function tradeEnd(T, why, okText)
	trades[T.a], trades[T.b] = nil, nil
	for _, p in { T.a, T.b } do
		if p.Parent then RX.Trade:FireClient(p, { state = why, text = okText }) end
	end
end
RX.TradeRequest.OnServerInvoke = function(plr, uid)
	local target = type(uid) == "number" and Players:GetPlayerByUserId(uid)
	if not target or target == plr or not D[target] then return false, "Игрок не найден" end
	if trades[plr] or trades[target] then return false, "Игрок уже обменивается" end
	tradeReq[target] = { from = plr, t = now() }
	RX.Trade:FireClient(target, { state = "request", from = plr.DisplayName, fromId = plr.UserId })
	return true
end
RX.TradeRespond.OnServerEvent:Connect(function(plr, accept)
	local r = tradeReq[plr]
	tradeReq[plr] = nil
	if not r or not r.from.Parent or now() - r.t > 30 then return end
	if not accept then
		notify(r.from, plr.DisplayName .. " отказался от обмена", "bad")
		return
	end
	if trades[plr] or trades[r.from] then return end
	local T = { a = r.from, b = plr, offer = { [r.from] = {}, [plr] = {} }, ready = {} }
	trades[r.from], trades[plr] = T, T
	tradeSend(T)
end)
RX.TradeOffer.OnServerEvent:Connect(function(plr, uids)
	local T = trades[plr]
	local d = D[plr]
	if not T or not d or type(uids) ~= "table" then return end
	local clean, seen = {}, {}
	for _, u in uids do
		if type(u) == "number" and not seen[u] and #clean < TRADE_MAX then
			for _, f in d.fruits do
				if f.uid == u then table.insert(clean, u) seen[u] = true break end
			end
		end
	end
	T.offer[plr] = clean
	T.ready = {}
	tradeSend(T)
end)
RX.TradeReady.OnServerEvent:Connect(function(plr, flag)
	local T = trades[plr]
	if not T then return end
	T.ready[plr] = flag == true
	if not (T.ready[T.a] and T.ready[T.b]) then tradeSend(T) return end
	local da, db = D[T.a], D[T.b]
	if not da or not db then tradeEnd(T, "cancel", "Обмен отменён") return end
	local function take(d, uids)
		local want, got, keep = {}, {}, {}
		for _, u in uids do want[u] = true end
		for _, f in d.fruits do
			if want[f.uid] then table.insert(got, f) else table.insert(keep, f) end
		end
		return got, keep
	end
	local ga, ka = take(da, T.offer[T.a])
	local gb, kb = take(db, T.offer[T.b])
	if #ga ~= #T.offer[T.a] or #gb ~= #T.offer[T.b] then tradeEnd(T, "cancel", "Плоды изменились, обмен отменён") return end
	if #ka + #gb > BAG_CAP or #kb + #ga > BAG_CAP then tradeEnd(T, "cancel", "У кого-то полна сумка") return end
	for _, f in gb do
		da.uid += 1
		table.insert(ka, { uid = da.uid, id = f.id, m = f.m, w = f.w, t = now() })
	end
	for _, f in ga do
		db.uid += 1
		table.insert(kb, { uid = db.uid, id = f.id, m = f.m, w = f.w, t = now() })
	end
	da.fruits, db.fruits = ka, kb
	push(T.a, "fruits")
	push(T.b, "fruits")
	tradeEnd(T, "done", "Обмен завершён!")
end)
RX.TradeCancel.OnServerEvent:Connect(function(plr)
	local T = trades[plr]
	if T then tradeEnd(T, "cancel", plr.DisplayName .. " отменил обмен") end
	tradeReq[plr] = nil
end)
Players.PlayerRemoving:Connect(function(plr)
	local T = trades[plr]
	if T then tradeEnd(T, "cancel", "Игрок вышел, обмен отменён") end
	tradeReq[plr] = nil
end)

-- конкурс «Лучший огород»: голосование, корона над огородом победителя и награда
local contest, crownPlot, lastContest = nil, nil, 0
local function gardenStats(p)
	local d, s = D[p], S[p]
	local plants, kg, best = 0, 0, 1
	for _, b in d.beds do
		plants += 1
		kg += b.w
		if #b.m > 0 then best = math.min(best, G.mutChance(b.m)) end
	end
	return { id = p.UserId, name = p.DisplayName, planet = d.planet or 1, plants = plants, kg = math.floor(kg * 10) / 10, best = best, plot = s.plot }
end
local function contestStart(force)
	local cands = {}
	for p in D do
		if S[p] and S[p].plot then table.insert(cands, gardenStats(p)) end
	end
	if #cands < 2 and not force then return false end
	if #cands == 0 then return false end
	contest = { ends = now() + G.Contest.vote, votes = {}, cands = cands, force = force }
	lastContest = now()
	RX.Contest:FireAllClients({ state = "vote", ends = contest.ends, cands = cands })
	return true
end
local function contestFinish()
	local c = contest
	contest = nil
	local count = {}
	for _, uid in c.votes do count[uid] = (count[uid] or 0) + 1 end
	local bestId, bestN = nil, 0
	for _, cand in c.cands do
		local n = count[cand.id] or 0
		if n > bestN or (n == bestN and n > 0 and math.random() < 0.5) then bestId, bestN = cand.id, n end
	end
	if crownPlot then Map.setCrown(crownPlot, false) crownPlot = nil end
	local winner = bestId and Players:GetPlayerByUserId(bestId)
	if not winner or not D[winner] then
		RX.Contest:FireAllClients({ state = "result", name = nil })
		return
	end
	local s = S[winner]
	if s.plot then
		crownPlot = s.plot
		Map.setCrown(s.plot, true)
	end
	local d = D[winner]
	local pn = math.max(1, unlockedPlanets(d))
	local coins = G.starReward(pn, false) * 150
	addCoins(winner, coins)
	local id = G.pickSeed(5, pn, Random.new())
	d.seeds[id] = (d.seeds[id] or 0) + 1
	push(winner, "seeds")
	rewardReveal(winner, "ЛУЧШИЙ ОГОРОД!", id, ("Голосов: %d · +%s монет"):format(bestN, G.fmt(coins)), Color3.fromRGB(255, 205, 70), "chest")
	RX.Contest:FireAllClients({ state = "result", name = winner.DisplayName, votes = bestN, id = winner.UserId })
end
RX.ContestVote.OnServerInvoke = function(plr, uid)
	if not contest or now() >= contest.ends then return false, "Голосование закончилось" end
	if uid == plr.UserId and not (contest.force and #contest.cands == 1) then return false, "За свой огород голосовать нельзя" end
	for _, cand in contest.cands do
		if cand.id == uid then
			contest.votes[plr] = uid
			return true
		end
	end
	return false
end
RX.ContestView.OnServerInvoke = function(plr, uid)
	local target = type(uid) == "number" and Players:GetPlayerByUserId(uid)
	local s = target and S[target]
	local plot = s and s.plot and Map.plots[s.plot]
	local ch = plr.Character
	if not plot or not ch or (S[plr] and S[plr].traveling) then return false end
	ch:PivotTo(plot.entrance)
	return true
end
CONTEST.start = contestStart
CONTEST.endNow = function() if contest then contest.ends = now() end end
task.spawn(function()
	while true do
		task.wait(1)
		local t = now()
		if contest then
			if t >= contest.ends then contestFinish() end
		elseif t % G.Contest.period < 2 and t - lastContest > 60 then
			contestStart(false)
		end
	end
end)

-- гонка на Марсе: время считает сервер, клиент сообщает пройденные ворота
RX.RaceStart.OnServerInvoke = function(plr)
	local d, s = D[plr], S[plr]
	if not d then return false end
	if not nearSpot(plr, "raceStart", G.Race.radius) then return false, "Подойди к старту гонки на Марсе" end
	s.race = { t0 = os.clock() + 3, token = math.random(1, 1e9) }
	return true, { token = s.race.token, countdown = 3 }
end
RX.RaceFinish.OnServerInvoke = function(plr, token, passed)
	local d, s = D[plr], S[plr]
	local r = s and s.race
	if not d or not r or r.token ~= token then return false end
	s.race = nil
	if passed ~= #G.Race.gates then return false, "Гонка прервана" end
	local el = os.clock() - r.t0
	if el < G.Race.minTime or el > G.Race.limit + 5 then return false, "Время не засчитано" end
	if not nearSpot(plr, "raceStart", G.Race.radius + 10) then return false, "Финиш у стартовой арки" end
	el = math.floor(el * 10 + 0.5) / 10
	local medal = G.raceMedal(el)
	d.race.runs += 1
	local newBest = d.race.best == 0 or el < d.race.best
	if newBest then
		d.race.best = el
		if s.canSave then
			task.spawn(function()
				pcall(function() DataStoreService:GetOrderedDataStore("SG_MarsRace2"):SetAsync(tostring(plr.UserId), math.floor(el * 1000)) end)
			end)
		end
	end
	local out = { time = el, medal = medal, best = d.race.best, newBest = newBest }
	if now() >= (d.cd.race or 0) then
		d.cd.race = now() + G.Race.cooldown
		local res = G.raceReward(medal, math.max(1, unlockedPlanets(d)), Random.new())
		addCoins(plr, res.coins)
		d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty
		if res.elixir then giveElixir(d) end
		out.reward = res
		local m = G.Medals[medal]
		rewardReveal(plr, ("%s: %.1f с!"):format(string.upper(m.name), el), res.id,
			("+%s монет · семян: %d%s%s"):format(G.fmt(res.coins), res.qty, res.elixir and " · эликсир удачи" or "", newBest and " · НОВЫЙ РЕКОРД" or ""), m.color, "unlock")
	else
		out.cooldown = d.cd.race - now()
	end
	push(plr, "race", "cd", "seeds", "potion")
	return true, out
end

-- рыбалка: рыбу выбирает сервер при забросе, клиент только играет вываживание
RX.FishCast.OnServerInvoke = function(plr)
	local d, s = D[plr], S[plr]
	if not d then return false end
	if not nearSpot(plr, "fishing", G.Fishing.radius) then return false, "Подойди к лавовому озеру на Ио" end
	local n, t0 = G.baitNow(d.bait, now())
	if n <= 0 then
		return false, ("Наживка кончилась: новая через %d с"):format(math.ceil(t0 + G.Fishing.baitEvery - now()))
	end
	if n >= G.Fishing.baitMax then t0 = now() end
	d.bait = { n = n - 1, t = t0 }
	local rng = Random.new()
	local fi = G.pickFish(rng)
	local bite = rng:NextNumber(2, 5.5)
	s.fish = { fi = fi, t0 = os.clock(), bite = bite, token = rng:NextInteger(1, 1e9) }
	push(plr, "bait")
	return true, { fish = fi, diff = G.Fish[fi].diff, bite = bite, token = s.fish.token, bait = d.bait.n }
end
RX.FishResult.OnServerInvoke = function(plr, token, ok)
	local d, s = D[plr], S[plr]
	local f = s and s.fish
	if not d or not f or f.token ~= token then return false end
	s.fish = nil
	local el = os.clock() - f.t0
	if not ok or el < f.bite + 1.5 or el > 90 then return false end
	local fish = G.Fish[f.fi]
	local res = G.fishReward(f.fi, math.max(1, unlockedPlanets(d)), Random.new())
	d.stats.fish = (d.stats.fish or 0) + 1
	if res.coins then addCoins(plr, res.coins) end
	if res.id then
		d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty
		if res.elixir then giveElixir(d) end
		rewardReveal(plr, "УЛОВ: " .. string.upper(fish.name) .. "!", res.id, ("+%s монет%s"):format(G.fmt(res.coins or 0), res.elixir and " · эликсир удачи x25" or ""), fish.color, "chest")
	end
	push(plr, "seeds", "potion", "stats")
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
	rewardReveal(plr, "ЗВЁЗДНЫЙ СУНДУК!", res.id, ("+%s монет%s"):format(G.fmt(res.coins), res.elixir and " · эликсир удачи x25" or ""), Color3.fromRGB(255, 215, 120), "chest")
end)

------------------------------------------------------------------ покупки за Robux
function grant(plr, key)
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
		d.bonusBeds = (d.bonusBeds or 0) + 4
		for _, g in d.gardens do g.bedCount = math.min(Map.MaxBeds, g.bedCount + 4) end
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
	S[plr] = { loaded = false, canSave = false, sel = nil, plots = {} }
	local d, ok = load(plr.UserId)
	if not plr.Parent then return end
	D[plr] = d
	S[plr].canSave = ok
	S[plr].loaded = true
	S[plr].sel = next(d.seeds)
	ensureQuests(d)
	d.planet = math.clamp(d.planet or 1, 1, math.max(1, unlockedPlanets(d)))
	d.gardens[tostring(d.planet)] = nil
	claimPlot(plr)
	buildStashPlots(plr)
	applyPet(plr)
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
	lbWrite(plr)
	releasePlot(plr)
	D[plr], S[plr] = nil, nil
end)
for _, plr in Players:GetPlayers() do task.spawn(onJoin, plr) end
task.spawn(function()
	pcall(function()
		game:GetService("MessagingService"):SubscribeAsync("SG_RareFind", function(m)
			local d = m.Data
			if type(d) == "table" and d.job ~= game.JobId and type(d.chance) == "number" then
				RX.Announce:FireAllClients(tostring(d.who), tostring(d.plant), tostring(d.title or ""), d.chance, nil, true)
			end
		end)
	end)
end)
------------------------------------------------------------------ админ-ивенты на всех серверах
function applyGlobal(cmd, arg)
	if cmd == "g_luck" or cmd == "g_gold" then
		local key = cmd == "g_luck" and "luck" or "gold"
		BOOST[key] = now() + G.Boosts[key].time
		RX.Boost:FireAllClients(key, BOOST[key] - now())
	elseif cmd == "g_seeds" then
		for _, plr in Players:GetPlayers() do
			local d = D[plr]
			if d then
				local id = G.pickSeed(4, math.max(1, unlockedPlanets(d)), Random.new())
				d.seeds[id] = (d.seeds[id] or 0) + 1
				push(plr, "seeds")
				rewardReveal(plr, "ПОДАРОК ВСЕМ!", id, "Редкое семя каждому игроку на всех серверах", Color3.fromRGB(255, 215, 120), "chest")
			end
		end
	elseif cmd == "g_event" then
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
	elseif cmd == "g_raid" then
		RAID.start()
	end
end
task.spawn(function()
	pcall(function()
		game:GetService("MessagingService"):SubscribeAsync("SG_Admin", function(m)
			local d = m.Data
			if type(d) == "table" and d.job ~= game.JobId and type(d.cmd) == "string" then applyGlobal(d.cmd, d.arg) end
		end)
	end)
end)
Players.PlayerAdded:Connect(function(plr)
	task.delay(7, function()
		if not plr.Parent then return end
		for key, untilT in BOOST do
			if now() < untilT then RX.Boost:FireClient(plr, key, untilT - now()) end
		end
	end)
end)

------------------------------------------------------------------ рейд «Комета-пожиратель»: весь сервер вместе сбивает огромную комету
RAID.next = now() + G.Raid.first
local function raidCenter(plr)
	local ch = plr.Character
	local pos = ch and ch:GetPivot().Position
	local pi = pos and Map.planetAt(pos) or 1
	return Map.planets[pi] and Map.planets[pi].center or Vector3.zero
end
local function raidSend(plr)
	RX.Raid:FireClient(plr, "start", RAID.hp, RAID.max, RAID.ends - now(), raidCenter(plr))
end
function RAID.start()
	if RAID.active then return false end
	local n = #Players:GetPlayers()
	RAID.active = true
	RAID.max = G.Raid.hpBase + G.Raid.hpPerPlayer * math.max(1, n)
	RAID.hp = RAID.max
	RAID.ends = now() + G.Raid.duration
	RAID.hits, RAID.last, RAID.recent = {}, {}, {}
	RAID.warned = false
	for _, plr in Players:GetPlayers() do raidSend(plr) end
	return true
end
local function raidFinish(win)
	RAID.active = false
	RAID.next = now() + G.Raid.period
	if not win then
		RX.Raid:FireAllClients("fail")
		return
	end
	local list, total = {}, 0
	for plr, h in RAID.hits do
		if plr.Parent then
			total += h
			table.insert(list, { plr = plr, h = h })
		end
	end
	table.sort(list, function(a, b) return a.h > b.h end)
	local top = {}
	for i = 1, math.min(3, #list) do top[i] = { name = list[i].plr.DisplayName, h = list[i].h } end
	local got = {}
	for i, e in list do
		local plr, d = e.plr, D[e.plr]
		got[plr] = true
		if d and e.h >= G.Raid.minHits then
			local planets = math.max(1, unlockedPlanets(d))
			local share = e.h / math.max(1, total)
			local res = G.raidReward(planets, share, i, Random.new())
			addCoins(plr, res.coins)
			if res.id then d.seeds[res.id] = (d.seeds[res.id] or 0) + res.qty end
			if res.elixir then giveElixir(d) end
			d.stats.raids = (d.stats.raids or 0) + 1
			push(plr, "seeds", "potion", "stats")
			RX.Raid:FireClient(plr, "win", top, { coins = res.coins, id = res.id, qty = res.qty, elixir = res.elixir, rank = i, share = share, hits = e.h })
		else
			RX.Raid:FireClient(plr, "win", top, nil)
		end
	end
	for _, plr in Players:GetPlayers() do
		if not got[plr] then RX.Raid:FireClient(plr, "win", top, nil) end
	end
end
RX.RaidHit.OnServerEvent:Connect(function(plr)
	if not RAID.active or not D[plr] then return end
	local t = os.clock()
	if t - (RAID.last[plr] or 0) < 1 / G.Raid.maxRate then return end
	RAID.last[plr] = t
	RAID.hits[plr] = (RAID.hits[plr] or 0) + 1
	RAID.recent[plr.UserId] = true
	RAID.hp -= 1
	if RAID.hp <= 0 then
		RAID.hp = 0
		raidFinish(true)
	end
end)
Players.PlayerAdded:Connect(function(plr)
	task.delay(8, function()
		if RAID.active and plr.Parent then raidSend(plr) end
	end)
end)
task.spawn(function()
	local lastHp = -1
	while true do
		task.wait(0.25)
		local t = now()
		if RAID.active then
			if RAID.hp ~= lastHp then
				lastHp = RAID.hp
				local shooters = {}
				for uid in RAID.recent do table.insert(shooters, uid) end
				RAID.recent = {}
				RX.Raid:FireAllClients("hp", RAID.hp, RAID.max, shooters)
			end
			if t >= RAID.ends and RAID.active then raidFinish(false) end
		else
			lastHp = -1
			if #Players:GetPlayers() > 0 then
				if not RAID.warned and t >= RAID.next - G.Raid.warn then
					RAID.warned = true
					RX.Raid:FireAllClients("warn", RAID.next)
				end
				if t >= RAID.next then RAID.start() end
			end
		end
	end
end)

-- автосохранение раз в 2 минуты и таблица лидеров раз в 1.5 минуты
task.spawn(function()
	task.wait(5)
	lbRefresh()
	local last = now()
	while true do
		task.wait(2)
		for plr in D do pcall(updateLeaderstats, plr) end
		if now() - last >= 90 then
			last = now()
			for plr in D do
				save(plr)
				lbWrite(plr)
				task.wait(0.5)
			end
			lbRefresh()
		end
	end
end)
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
			if d.perms.auto and (d.settings and d.settings.a) ~= 0 then
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

