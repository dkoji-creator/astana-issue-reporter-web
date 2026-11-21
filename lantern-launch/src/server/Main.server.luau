-- «Запусти фонарик»: сервер. Всё важное (сила броска, духи, шансы, монеты, сохранение) считается здесь.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local DataStoreService = game:GetService("DataStoreService")
local MarketplaceService = game:GetService("MarketplaceService")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

local Game = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"))
local Map = require(script.Parent:WaitForChild("Map"))

local ADMINS = { [8432365972] = true }
local function isAdmin(plr) return ADMINS[plr.UserId] == true or (game.CreatorType == Enum.CreatorType.User and plr.UserId == game.CreatorId) end

------------------------------------------------------------------ свет: тёплый рассвет
Lighting.ClockTime = 6.4
Lighting.Brightness = 2.2
Lighting.Ambient = Color3.fromRGB(140, 128, 150)
Lighting.OutdoorAmbient = Color3.fromRGB(150, 140, 165)
Lighting.ExposureCompensation = 0.1
do
	local atm = Instance.new("Atmosphere")
	atm.Density, atm.Haze, atm.Color, atm.Decay = 0.22, 0.6, Color3.fromRGB(255, 205, 200), Color3.fromRGB(255, 170, 160)
	atm.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.25, 14, 1.8
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation, cc.Contrast, cc.TintColor = 0.1, 0.05, Color3.fromRGB(255, 244, 238)
	cc.Parent = Lighting
end

------------------------------------------------------------------ remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local ChargeEv = remote("Charge") -- игрок зажал кнопку
local ThrowFn = remote("Throw", "RemoteFunction") -- игрок отпустил: возвращает результаты
local StateEv = remote("State")
local ResultEv = remote("AutoResult") -- результаты авто-запуска
local NoticeEv = remote("Notice")
local UpgradeFn = remote("Upgrade", "RemoteFunction")
local AutoFn = remote("SetAuto", "RemoteFunction")
local DailyFn = remote("ClaimDaily", "RemoteFunction")
local CodeFn = remote("Redeem", "RemoteFunction")
local AdminFn = remote("Admin", "RemoteFunction")
remotes.Parent = ReplicatedStorage

local map = Map.build()

------------------------------------------------------------------ данные игрока
local store
pcall(function() store = DataStoreService:GetDataStore("LanternLaunch_v1") end)
local data = {}

local function num(v, lo, hi, def)
	if typeof(v) ~= "number" or v ~= v then return def end
	return math.clamp(v, lo, hi)
end
local function newProfile()
	return {
		coins = 0, record = 0, total = 0,
		lv = { power = 1, luck = 1, coins = 1, speed = 1, multi = 1, auto = 1 },
		inv = {}, -- "Kind:variant" -> сколько
		variants = {}, -- Kind -> { variant = true }
		auto = false, daily = { last = 0, streak = 0 }, codes = {}, luckUntil = 0,
		milestones = {}, owned = {}, receipts = {},
	}
end
local function migrate(raw)
	local d = newProfile()
	if typeof(raw) ~= "table" then return d end
	d.coins = math.floor(num(raw.coins, 0, 1e15, 0))
	d.record = math.floor(num(raw.record, 0, Game.MaxDistance, 0))
	d.total = math.floor(num(raw.total, 0, 1e12, 0))
	if typeof(raw.lv) == "table" then
		for k in d.lv do d.lv[k] = math.floor(num(raw.lv[k], 1, Game.Upgrades[k].max, 1)) end
	end
	if typeof(raw.inv) == "table" then
		for key, n in raw.inv do
			local kind, variant = string.match(tostring(key), "([^:]+):(.+)")
			if kind and Game.Pool[kind] and Game.Variants[variant] then d.inv[key] = math.floor(num(n, 0, 1e9, 0)) end
		end
	end
	if typeof(raw.variants) == "table" then
		for kind, vs in raw.variants do
			if Game.Pool[kind] and typeof(vs) == "table" then
				d.variants[kind] = {}
				for v, on in vs do
					if Game.Variants[v] and on == true then d.variants[kind][v] = true end
				end
			end
		end
	end
	d.auto = raw.auto == true
	if typeof(raw.daily) == "table" then d.daily = { last = math.floor(num(raw.daily.last, 0, 1e7, 0)), streak = math.floor(num(raw.daily.streak, 0, 100, 0)) } end
	if typeof(raw.codes) == "table" then
		for k, v in raw.codes do
			if Game.Codes[k] and v == true then d.codes[k] = true end
		end
	end
	d.luckUntil = math.floor(num(raw.luckUntil, 0, 1e12, 0))
	if typeof(raw.milestones) == "table" then
		for k, v in raw.milestones do if v == true then d.milestones[tostring(k)] = true end end
	end
	if typeof(raw.owned) == "table" then
		for k, v in raw.owned do if Game.Products[k] and v == true then d.owned[k] = true end end
	end
	if typeof(raw.receipts) == "table" then
		for _, r in raw.receipts do
			if typeof(r) == "string" and #d.receipts < 50 then table.insert(d.receipts, r) end
		end
	end
	return d
end

local function seenCount(d)
	local n = 0
	for kind in d.variants do
		for _ in d.variants[kind] do n += 1 break end
	end
	return n
end
local function persist(plr)
	local d = data[plr]
	if not (store and d) or d.loadFailed then return false end
	local copy = table.clone(d)
	copy.loadFailed = nil
	local ok, err = pcall(function() store:SetAsync("u" .. plr.UserId, copy) end)
	if not ok then warn("DataStore save failed:", err) end
	return ok
end

------------------------------------------------------------------ расчёт значений
local function luckOf(d)
	local m = Game.upgradeValue("luck", d.lv.luck)
	if (d.luckUntil or 0) > os.time() then m *= Game.Potion.mult end
	return m
end
local function coinMultOf(d)
	local m = Game.upgradeValue("coins", d.lv.coins)
	if d.owned.coins2x then m *= 2 end
	return m
end
local function cooldownOf(d) return Game.upgradeValue("speed", d.lv.speed) end
local function autoPeriod(d)
	local p = Game.upgradeValue("auto", d.lv.auto)
	if p <= 0 then return 0 end
	return d.owned.autoPro and p / 2 or p
end

local function pushState(plr)
	local d = data[plr]
	if not d then return end
	StateEv:FireClient(plr, {
		coins = d.coins, record = d.record, total = d.total, lv = d.lv, inv = d.inv, variants = d.variants,
		auto = d.auto, autoPeriod = autoPeriod(d), daily = d.daily, dailyReady = d.daily.last < math.floor(os.time() / 86400),
		luck = luckOf(d), luckUntil = d.luckUntil, coinMult = coinMultOf(d), cooldown = cooldownOf(d),
		seen = seenCount(d), owned = d.owned, isAdmin = isAdmin(plr), milestones = d.milestones, now = os.time(),
	})
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		ls["Монеты"].Value = d.coins
		ls["Рекорд, м"].Value = d.record
		ls["Духи"].Value = seenCount(d)
	end
end

------------------------------------------------------------------ запуск фонарика
local rng = Random.new()
local charge, lastThrow, perfectStreak = {}, {}, {}

-- один фонарик: дальность -> зона -> дух -> разновидность -> награда. Применяется сразу, показывается по прилёту
local function launchOne(d, q: number, streakMult: number)
	local maxDist = Game.upgradeValue("power", d.lv.power)
	local dist = math.min(Game.MaxDistance - 1, Game.distance(maxDist, q))
	local zone = Game.zoneAt(dist)
	local luck = luckOf(d)
	local kind, pKind = Game.rollKind(zone, luck, rng)
	local variant, pVar = Game.rollVariant(luck, zone.luck, rng)
	local info = Game.Kinds[kind]
	local coins = Game.coinsFor(info.rarity, variant, coinMultOf(d) * streakMult)
	d.coins += coins
	d.total += 1
	if dist > d.record then d.record = math.floor(dist) end
	local key = kind .. ":" .. variant
	d.inv[key] = (d.inv[key] or 0) + 1
	d.variants[kind] = d.variants[kind] or {}
	local isNew = not d.variants[kind][variant]
	d.variants[kind][variant] = true
	local odds = math.max(1, math.floor(1 / (pKind * pVar) + 0.5))
	return { dist = math.floor(dist), x = rng:NextNumber(-60, 60), zone = zone.id, kind = kind, variant = variant, coins = coins, odds = odds, new = isNew }
end

local function checkMilestones(plr, d)
	local n = seenCount(d)
	for i, m in Game.Milestones do
		if n >= m.need and not d.milestones[tostring(i)] then
			d.milestones[tostring(i)] = true
			d.coins += m.coins
			NoticeEv:FireClient(plr, ("Коллекция %d видов! +%d монет"):format(m.need, m.coins))
		end
	end
end

-- общий путь для ручного и авто-запуска; q от 0 до 1
local function doLaunch(plr, q: number, streakMult: number?)
	local d = data[plr]
	if not d then return nil end
	local count = Game.upgradeValue("multi", d.lv.multi)
	local results, maxFlight = {}, 0
	for i = 1, count do
		local qi = i == 1 and q or math.clamp(q + rng:NextNumber(-0.15, 0.15), 0, 1)
		local r = launchOne(d, qi, streakMult or 1)
		r.delay = (i - 1) * 0.18
		maxFlight = math.max(maxFlight, r.delay + Game.flightTime(r.dist))
		table.insert(results, r)
		-- редкие находки видят все
		local vOdds = r.variant ~= "normal" and math.floor(1 / Game.Variants[r.variant].chance + 0.5) or 1
		if r.odds >= 1000 or vOdds >= 250 then
			task.delay(Game.flightTime(r.dist), function()
				for _, p in Players:GetPlayers() do
					NoticeEv:FireClient(p, ("%s запустил фонарик: %s%s (1 к %d)!"):format(plr.DisplayName,
						r.variant ~= "normal" and (Game.Variants[r.variant].name .. " ") or "", Game.Kinds[r.kind].name, r.odds))
				end
			end)
		end
	end
	checkMilestones(plr, d)
	lastThrow[plr] = os.clock()
	persist(plr)
	-- монеты на экране обновятся, когда фонарики долетят
	task.delay(maxFlight, function()
		if plr.Parent then pushState(plr) end
	end)
	return results
end

ChargeEv.OnServerEvent:Connect(function(plr)
	charge[plr] = os.clock()
end)

ThrowFn.OnServerInvoke = function(plr)
	local d = data[plr]
	local start = charge[plr]
	charge[plr] = nil
	if not (d and start) then return { ok = false } end
	local now = os.clock()
	if now - (lastThrow[plr] or -1e9) < cooldownOf(d) - 0.15 then return { ok = false } end
	local q = Game.meterAt(math.min(now - start, 6))
	-- серия идеальных: точный запуск поднимает множитель монет, слабый обрывает серию
	local streak = perfectStreak[plr] or 0
	if q >= 0.93 then streak += 1 elseif q < 0.78 then streak = 0 end
	perfectStreak[plr] = streak
	local results = doLaunch(plr, q, 1 + Game.StreakStep * math.min(streak, Game.StreakMax))
	if not results then return { ok = false } end
	return { ok = true, q = q, results = results, cd = cooldownOf(d), streak = streak, streakMult = 1 + Game.StreakStep * math.min(streak, Game.StreakMax) }
end

-- авто-запуск: сервер сам бросает с хорошей, но не идеальной точностью
task.spawn(function()
	local nextAuto = {}
	while true do
		task.wait(0.25)
		local now = os.clock()
		for plr, d in data do
			local period = autoPeriod(d)
			if d.auto and period > 0 and plr.Parent then
				if now >= (nextAuto[plr] or 0) and now - (lastThrow[plr] or -1e9) >= cooldownOf(d) then
					nextAuto[plr] = now + period
					local results = doLaunch(plr, 0.72 + rng:NextNumber() * 0.2)
					if results then ResultEv:FireClient(plr, { q = 0.8, results = results }) end
				end
			end
		end
	end
end)

------------------------------------------------------------------ улучшения, подарок, коды
UpgradeFn.OnServerInvoke = function(plr, key)
	local d = data[plr]
	local u = typeof(key) == "string" and Game.Upgrades[key]
	if not (d and u) then return { ok = false } end
	local cost = Game.upgradeCost(key, d.lv[key])
	if not cost then return { ok = false, msg = "Максимальный уровень" } end
	if d.coins < cost then return { ok = false, msg = ("Нужно %d монет"):format(cost) } end
	d.coins -= cost
	d.lv[key] += 1
	if key == "auto" and d.lv.auto == 2 then d.auto = true end
	persist(plr)
	pushState(plr)
	return { ok = true }
end
AutoFn.OnServerInvoke = function(plr, on)
	local d = data[plr]
	if not d or autoPeriod(d) <= 0 then return { ok = false, msg = "Сначала купи «Авто-запуск»" } end
	d.auto = on == true
	pushState(plr)
	return { ok = true }
end
DailyFn.OnServerInvoke = function(plr)
	local d = data[plr]
	if not d then return { ok = false } end
	local today = math.floor(os.time() / 86400)
	if d.daily.last >= today then return { ok = false, msg = "Подарок получен, приходи завтра" } end
	local streak = (d.daily.last == today - 1) and math.min(d.daily.streak + 1, Game.Daily.maxStreak) or 1
	d.daily = { last = today, streak = streak }
	local coins = (Game.Daily.coins + (streak - 1) * Game.Daily.perStreak) * math.max(1, Game.upgradeValue("coins", d.lv.coins))
	d.coins += math.floor(coins)
	d.luckUntil = math.max(d.luckUntil or 0, os.time()) + Game.Daily.potionSeconds
	persist(plr)
	pushState(plr)
	return { ok = true, streak = streak, coins = math.floor(coins) }
end
CodeFn.OnServerInvoke = function(plr, code)
	local d = data[plr]
	if not (d and typeof(code) == "string") then return { ok = false } end
	code = string.upper(string.gsub(code, "%s", ""))
	local c = Game.Codes[code]
	if not c then return { ok = false, msg = "Нет такого кода" } end
	if d.codes[code] then return { ok = false, msg = "Код уже использован" } end
	d.codes[code] = true
	d.coins += c.coins
	persist(plr)
	pushState(plr)
	return { ok = true, msg = c.text }
end

------------------------------------------------------------------ донаты
MarketplaceService.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	local d = plr and data[plr]
	if not d then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local id = tostring(info.PurchaseId)
	if table.find(d.receipts, id) then return Enum.ProductPurchaseDecision.PurchaseGranted end
	for key, p in Game.Products do
		if p.id ~= 0 and p.id == info.ProductId then
			if p.permanent then d.owned[key] = true else d.luckUntil = math.max(d.luckUntil or 0, os.time()) + Game.Potion.seconds end
			table.insert(d.receipts, id)
			while #d.receipts > 50 do table.remove(d.receipts, 1) end
			if not persist(plr) then return Enum.ProductPurchaseDecision.NotProcessedYet end
			pushState(plr)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

------------------------------------------------------------------ админ (для проверки и съёмки)
AdminFn.OnServerInvoke = function(plr, cmd)
	if not isAdmin(plr) then return { ok = false, msg = "Нет доступа" } end
	local d = data[plr]
	if not d then return { ok = false } end
	if cmd == "coins" then d.coins += 100000
	elseif cmd == "maxPower" then d.lv.power = Game.Upgrades.power.max
	elseif cmd == "allUpgrades" then
		for k, u in Game.Upgrades do d.lv[k] = u.max end
	elseif cmd == "perfect" then
		local results = doLaunch(plr, 1)
		if results then ResultEv:FireClient(plr, { q = 1, results = results }) end
	elseif cmd == "showcase" then
		-- пачка максимальных запусков подряд для съёмки
		task.spawn(function()
			for _ = 1, 3 do
				local results = doLaunch(plr, 1)
				if results then ResultEv:FireClient(plr, { q = 1, results = results }) end
				task.wait(0.4)
			end
		end)
	elseif cmd == "reset" then
		data[plr] = newProfile()
	else
		return { ok = false }
	end
	persist(plr)
	pushState(plr)
	return { ok = true }
end

------------------------------------------------------------------ вход и выход
local function onJoin(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, n in { "Монеты", "Рекорд, м", "Духи" } do
		local v = Instance.new("IntValue")
		v.Name = n
		v.Parent = ls
	end
	ls.Parent = plr
	local raw, failed = nil, false
	if store then
		failed = true
		for attempt = 1, 3 do
			local ok, res = pcall(function() return store:GetAsync("u" .. plr.UserId) end)
			if ok then raw, failed = res, false break end
			warn("DataStore load failed:", res)
			task.wait(attempt)
		end
	end
	if not plr.Parent then return end
	local d = migrate(raw)
	d.loadFailed = failed or nil
	data[plr] = d
	plr.CharacterAdded:Connect(function(char)
		local hum = char:WaitForChild("Humanoid", 10)
		if hum then hum.WalkSpeed = 18 end
	end)
	pushState(plr)
	if failed then NoticeEv:FireClient(plr, "Не удалось загрузить сохранение: прогресс этой сессии не запишется") end
end
Players.PlayerAdded:Connect(onJoin)
for _, p in Players:GetPlayers() do task.spawn(onJoin, p) end
Players.PlayerRemoving:Connect(function(plr)
	persist(plr)
	data[plr], charge[plr], lastThrow[plr], perfectStreak[plr] = nil, nil, nil, nil
end)
game:BindToClose(function()
	for _, plr in Players:GetPlayers() do persist(plr) end
end)
task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do persist(plr) end
	end
end)

-- упавших в пропасть возвращаем на площадку
task.spawn(function()
	while true do
		task.wait(1)
		for _, plr in Players:GetPlayers() do
			local c = plr.Character
			local r = c and c:FindFirstChild("HumanoidRootPart")
			if r and r.Position.Y < -50 then c:PivotTo(CFrame.new(0, 5, -6)) end
		end
	end
end)
