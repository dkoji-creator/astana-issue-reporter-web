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

------------------------------------------------------------------ ремоуты
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local RX = {}
for _, n in { "Sync", "Notify", "Reveal", "Stock", "Event", "Announce", "Act", "Select", "Harvest" } do
	local e = Instance.new("RemoteEvent")
	e.Name = n
	e.Parent = remotes
	RX[n] = e
end
for _, n in { "Buy", "Sell", "Upgrade", "BuyDecor", "Daily", "Redeem", "Fav", "Top", "Admin", "State" } do
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
		stats = { harvests = 0, sold = 0, bestChance = 1 }, weekBest = { w = 0, kg = 0 }, lastSeen = now(),
	}
end

local function mergeDefaults(d)
	local base = newProfile()
	for k, v in base do
		if d[k] == nil then d[k] = v end
	end
	for k, v in base.upg do if d.upg[k] == nil then d.upg[k] = v end end
	for k, v in base.stats do if d.stats[k] == nil then d.stats[k] = v end end
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
		planets = unlockedPlanets(d), sold = soldNow.epoch == epoch and soldNow.sold or {},
	}
end
local function push(plr, ...)
	local snap = snapshot(plr)
	local patch = {}
	for _, k in { ... } do patch[k] = snap[k] end
	RX.Sync:FireClient(plr, patch)
end

------------------------------------------------------------------ участки и грядки
local plotOwner = {} -- индекс участка -> игрок
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
		soil:SetAttribute("Wa", b.wa == true)
		soil:SetAttribute("Sp", b.sp == true)
		soil:SetAttribute("Muts", table.concat(b.m, ","))
		soil:SetAttribute("Kg", b.w)
	else
		for _, k in { "Plant", "T0", "Ready", "Wa", "Sp", "Muts", "Kg" } do soil:SetAttribute(k, nil) end
	end
	Map.setBedLocked(s.plot, i, i > d.bedCount)
end
local function refreshAllBeds(plr)
	for i = 1, Map.MaxBeds do refreshBed(plr, i) end
end

local function claimPlot(plr)
	local s = S[plr]
	if s.plot then return true end
	for i = 1, Map.PlotCount do
		if not plotOwner[i] then
			plotOwner[i] = plr
			s.plot = i
			local plot = Map.plots[i]
			plot.model:SetAttribute("OwnerId", plr.UserId)
			Map.setPlotSign(i, plr.DisplayName, G.PlanetColors[math.clamp(unlockedPlanets(D[plr]), 1, 6)])
			for _, id in G.DecorOrder do
				if D[plr].decor[id] then Map.placeDecor(i, id) end
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
	local i = s.plot
	local plot = Map.plots[i]
	plotOwner[i] = nil
	plot.model:SetAttribute("OwnerId", nil)
	Map.setPlotSign(i, "Свободный участок", Color3.fromRGB(70, 220, 255))
	Map.clearDecor(i)
	for bi = 1, Map.MaxBeds do
		local soil = plot.beds[bi].soil
		for _, k in { "Plant", "T0", "Ready", "Wa", "Sp", "Muts", "Kg" } do soil:SetAttribute(k, nil) end
		Map.setBedLocked(i, bi, bi > G.StartBeds)
	end
	s.plot = nil
	-- очередь ожидающих
	for _, other in Players:GetPlayers() do
		if other ~= plr and S[other] and not S[other].plot and S[other].loaded then
			if claimPlot(other) then
				push(other, "plot")
				local ch = other.Character
				if ch then ch:PivotTo(Map.plots[S[other].plot].entrance) end
				notify(other, "Освободился участок, он твой", "ok")
			end
		end
	end
end

local function teleportToPlot(plr)
	local s = S[plr]
	local ch = plr.Character
	if ch and s and s.plot then
		task.defer(function() ch:PivotTo(Map.plots[s.plot].entrance) end)
	end
end

------------------------------------------------------------------ события по часам
local activeEvent = nil
local function eventNow()
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
	local base = plant.grow * (regrow and plant.regrow > 0 and plant.regrow or 1)
	local t = now()
	local ready = t + math.max(3, base / speed)
	local ev, left = eventNow()
	if ev and ev.grow then ready = t + flareRemaining(ready - t, left) end
	local luck = G.upgradeValue("luck", d.upg.luck)
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
	local bed = { id = plantId, t0 = t, ready = ready, m = muts, w = G.rollWeight(plant, rng, muts) }
	local sp = d.upg.sprinkler
	if sp > 0 then
		local pct = math.min(0.6, (G.upgradeValue("water", d.upg.water) + 5 * sp) / 100)
		bed.ready = t + (bed.ready - t) * (1 - pct)
		bed.sp = true
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
end

local function waterBed(plr, i)
	local d = D[plr]
	local b = d.beds[i]
	local t = now()
	if b.wa then notify(plr, "Уже полито, осталось " .. G.fmtTime(b.ready - t), "info") return end
	local pct = G.upgradeValue("water", d.upg.water) / 100
	b.ready = t + (b.ready - t) * (1 - pct)
	b.wa = true
	refreshBed(plr, i)
	notify(plr, ("Полито: рост быстрее на %d%%"):format(math.floor(pct * 100 + 0.5)), "ok")
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
		RX.Announce:FireAllClients(plr.DisplayName, plant.name, G.mutTitle(b.m), chance)
	end
	push(plr, "fruits", "idx", "mutSeen", "stats")
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
		notify(plr, "Открыта планета: " .. pl.name .. "!", "ok")
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

RX.State.OnServerInvoke = function(plr)
	if not D[plr] then return nil end
	return snapshot(plr)
end

------------------------------------------------------------------ админ (для съёмок и проверки)
RX.Admin.OnServerInvoke = function(plr, cmd, arg)
	if plr.UserId ~= ADMIN_ID then return false end
	local d, s = D[plr], S[plr]
	if cmd == "coins" then
		addCoins(plr, 1000000)
	elseif cmd == "planets" then
		d.earned = G.PlanetUnlock[6]
	elseif cmd == "seeds" then
		for _, p in G.PlantList do d.seeds[p.id] = (d.seeds[p.id] or 0) + 3 end
		s.sel = s.sel or "moon_01"
	elseif cmd == "mut" then
		if G.Mut[arg] then s.forceMut = arg end
	elseif cmd == "ripe" then
		for _, b in d.beds do b.ready = now() end
		refreshAllBeds(plr)
	elseif cmd == "event" then
		return true
	else
		return false
	end
	push(plr, "coins", "earned", "seeds", "sel", "planets")
	return true
end

------------------------------------------------------------------ покупки за Robux
local function grant(plr, key)
	local d = D[plr]
	local prod = G.Products[key]
	if key == "small" or key == "big" then
		local po = G.Potions[key]
		if d.potion.luck == po.luck then d.potion.uses += po.uses else d.potion = { luck = po.luck, uses = po.uses } end
	elseif key == "growth2x" or key == "auto" then
		d.perms[key] = true
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
			elseif ev.luck then
				-- метеорит задевает грядки: дополнительный бросок мутаций
				for plr, d in D do
					local hit = 0
					for i, b in d.beds do
						local extra = G.rollMutations(G.upgradeValue("luck", d.upg.luck) * ev.luck, Random.new())
						for _, mid in extra do
							if not table.find(b.m, mid) then
								table.insert(b.m, mid)
								hit += 1
							end
						end
						if #extra > 0 then b.w = G.rollWeight(G.Plants[b.id], Random.new(), b.m) end
					end
					if S[plr].plot then refreshAllBeds(plr) end
					if hit > 0 then notify(plr, ("Метеориты задели грядки: новые мутации: %d"):format(hit), "ok") end
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
		if Map.boardLabel and t - lastBoard >= 10 then
			lastBoard = t
			local epoch = G.marketEpoch(t)
			local lines = { "<b>ГОРЯЧИЙ СПРОС x3</b>" }
			for id in G.hotPlants(epoch) do table.insert(lines, G.Plants[id].name) end
			table.insert(lines, "Обновление через " .. G.fmtTime(G.marketTimeLeft(t)))
			Map.boardLabel.Text = table.concat(lines, "\n")
		end
	end
end)

