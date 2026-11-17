-- Spirit Catchers: сервер. Появление, ловля, потеря и сохранение улова — только здесь.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local Map = require(script.Parent:WaitForChild("Map"))
local map = Map.build()

local TEST_PLACE_ID = 99980756426085
-- Закрытый тест: редкие духи луны гарантированы (Studio и тестовый плейс)
local IS_TEST = RunService:IsStudio() or game.PlaceId == TEST_PLACE_ID
local FIRST_MOON, NORMAL_TIME, MOON_TIME = 100, 150, 70
local ALTAR_RANGE, SAFE_RADIUS = 16, 26
local ONI_RADIUS, ONI_WARN = 8, 1.6
-- веса появления собираются из Config/Spirits (district → kind → вес)
local WEIGHTS = { normal = {}, moon = {} }
for kind, info in Catalog.Kinds do
	for district, w in info.spawn do
		WEIGHTS.normal[district] = WEIGHTS.normal[district] or {}
		WEIGHTS.moon[district] = WEIGHTS.moon[district] or {}
		if (w.w or 0) > 0 then WEIGHTS.normal[district][kind] = w.w end
		if (w.moon or 0) > 0 then WEIGHTS.moon[district][kind] = w.moon end
	end
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
local RevealEv = remote("Reveal")
local CatchHoldEv = remote("CatchHold")
local EquipFn = remote("Equip", "RemoteFunction")
local UpgradeFn = remote("Upgrade", "RemoteFunction")
local TutorialEv = remote("TutorialDone")
local StateEv = remote("State")
local SaveResultEv = remote("SaveResult")
local CaughtEv = remote("Caught")
local HitEv = remote("Hit")
local NoticeEv = remote("Notice")
local SettingsEv = remote("SetSettings")
local DailyFn = remote("ClaimDaily", "RemoteFunction")
local SkinFn = remote("Skin", "RemoteFunction")
local MilestoneFn = remote("ClaimMilestone", "RemoteFunction")
local RewardEv = remote("Reward") -- всплывающие награды: { coins, dust, xp, levelUp }
remotes.Parent = ReplicatedStorage

------------------------------------------------------------------ свет
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.ExposureCompensation = -0.3
Lighting.Ambient = Color3.fromRGB(52, 52, 82)
Lighting.OutdoorAmbient = Color3.fromRGB(58, 60, 92)
Lighting.EnvironmentDiffuseScale = 0.3
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "Bloom"
bloom.Intensity, bloom.Size, bloom.Threshold = 0.2, 14, 1.6
bloom.Parent = Lighting
local atm = Instance.new("Atmosphere")
atm.Density, atm.Haze, atm.Color, atm.Decay = 0.3, 1.1, Color3.fromRGB(80, 90, 150), Color3.fromRGB(40, 30, 80)
atm.Parent = Lighting

------------------------------------------------------------------ профили (версия 4; v2 и v3 переносятся)
local store = nil
pcall(function() store = DataStoreService:GetDataStore("SpiritCatchers_v1") end)

type Profile = {
	version: number, saved: { [string]: number }, firstSaved: { [string]: boolean }, equipped: string?,
	coins: number, dust: number, levels: { [string]: number }, tutorialDone: boolean,
	orders: { any }, settings: { music: number, sfx: number, reduced: boolean, diag: boolean },
	xp: number, level: number, daily: { last: number, streak: number }, skins: { [string]: boolean }, skin: string,
	milestones: { [string]: boolean }, loadFailed: boolean?,
}
local data: { [Player]: Profile } = {}
local jars: { [Player]: { string } } = {}
local holds: { [Player]: number } = {}

local function clampLvl(v)
	return typeof(v) == "number" and math.clamp(math.floor(v), 1, Catalog.MaxLevel) or 1
end
local function num(v, lo, hi, def)
	return typeof(v) == "number" and v == v and math.clamp(v, lo, hi) or def
end

local function distinct(d: Profile)
	local n = 0
	for _, v in d.saved do
		if v > 0 then n += 1 end
	end
	return n
end
local function gardenOpen(d: Profile) return distinct(d) >= Catalog.GardenNeed end
local function cap(d: Profile) return Catalog.upgradeValue("jar", d.levels.jar) end
local function power(d: Profile) return Catalog.upgradeValue("power", d.levels.power) end
local function range(d: Profile) return Catalog.upgradeValue("range", d.levels.range) end

------------------------------------------------------------------ заказы алтаря
local function onlyGarden(kind)
	for district in Catalog.Kinds[kind].spawn do
		if district ~= "garden" then return false end
	end
	return next(Catalog.Kinds[kind].spawn) ~= nil
end

local function newOrder(d: Profile, avoid: string?)
	local pool = {}
	for _, kind in Catalog.Order do
		local info = Catalog.Kinds[kind]
		if not info.moonOnly and kind ~= avoid and (gardenOpen(d) or not onlyGarden(kind)) then
			table.insert(pool, kind)
		end
	end
	if math.random() < 0.6 and #pool > 0 then
		local kind = pool[math.random(#pool)]
		local rar = Catalog.Rarity[Catalog.Kinds[kind].rarity]
		local need = Catalog.Kinds[kind].rarity == "common" and 2 or 1
		return { type = "kind", kind = kind, need = need, have = 0, coins = rar.coins * need * 3 + 15, dust = rar.dust }
	end
	local rarity = math.random() < 0.65 and "common" or "uncommon"
	local need = rarity == "common" and math.random(3, 4) or 2
	local rar = Catalog.Rarity[rarity]
	return { type = "rarity", rarity = rarity, need = need, have = 0, coins = rar.coins * need * 2 + 10, dust = rar.dust * 2 }
end

local function fillOrders(d: Profile)
	local valid = {}
	for _, o in d.orders do
		if typeof(o) == "table" and (o.type == "kind" and Catalog.Kinds[o.kind] or o.type == "rarity" and Catalog.Rarity[o.rarity]) then
			table.insert(valid, o)
		end
	end
	d.orders = valid
	while #d.orders < Catalog.OrderSlots do
		table.insert(d.orders, newOrder(d, d.orders[1] and d.orders[1].kind))
	end
end

local function migrate(raw): Profile
	local d: Profile = {
		version = 5, saved = {}, firstSaved = {}, equipped = nil, coins = 0, dust = 0,
		levels = { jar = 1, range = 1, power = 1 }, tutorialDone = false, orders = {},
		settings = { music = 0.6, sfx = 0.8, reduced = false, diag = false },
		xp = 0, level = 1, daily = { last = 0, streak = 0 }, skins = { classic = true }, skin = "classic", milestones = {},
	}
	if typeof(raw) == "table" then
		-- v2+: коллекция
		if typeof(raw.saved) == "table" then
			for k, v in raw.saved do
				if Catalog.Kinds[k] and typeof(v) == "number" and v > 0 then
					d.saved[k] = math.floor(v)
					d.firstSaved[k] = true
				end
			end
		end
		if typeof(raw.firstSaved) == "table" then
			for k, v in raw.firstSaved do
				if Catalog.Kinds[k] and v == true then d.firstSaved[k] = true end
			end
		end
		if typeof(raw.equipped) == "string" and (d.saved[raw.equipped] or 0) > 0 then d.equipped = raw.equipped end
		if raw.version == 3 then
			-- материал → пыль духов; фонарь v3 → ширина луча и сила света; стартовые монеты за коллекцию
			d.dust = math.floor(num(raw.materials, 0, 1e9, 0))
			d.levels.range = clampLvl(raw.lanternLvl)
			d.levels.power = clampLvl(raw.lanternLvl)
			d.levels.jar = clampLvl(raw.jarLvl)
			d.tutorialDone = raw.tutorialDone == true
			d.coins = 20 * distinct(d)
		elseif raw.version == 4 or raw.version == 5 then
			d.coins = math.floor(num(raw.coins, 0, 1e9, 0))
			d.dust = math.floor(num(raw.dust, 0, 1e9, 0))
			if typeof(raw.levels) == "table" then
				for _, k in Catalog.UpgradeOrder do d.levels[k] = clampLvl(raw.levels[k]) end
			end
			d.tutorialDone = raw.tutorialDone == true
			if typeof(raw.orders) == "table" then d.orders = raw.orders end
			if typeof(raw.settings) == "table" then
				d.settings.music = num(raw.settings.music, 0, 1, 0.6)
				d.settings.sfx = num(raw.settings.sfx, 0, 1, 0.8)
				d.settings.reduced = raw.settings.reduced == true
				d.settings.diag = raw.settings.diag == true
			end
			if raw.version == 5 then
				d.xp = math.floor(num(raw.xp, 0, 1e9, 0))
				d.level = math.floor(num(raw.level, 1, 999, 1))
				if typeof(raw.daily) == "table" then
					d.daily.last = math.floor(num(raw.daily.last, 0, 1e7, 0))
					d.daily.streak = math.floor(num(raw.daily.streak, 0, 7, 0))
				end
				if typeof(raw.skins) == "table" then
					for k, v in raw.skins do
						if Catalog.Progress.Skins[k] and v == true then d.skins[k] = true end
					end
				end
				if typeof(raw.skin) == "string" and d.skins[raw.skin] then d.skin = raw.skin end
				if typeof(raw.milestones) == "table" then
					for k, v in raw.milestones do
						if typeof(k) == "string" and v == true then d.milestones[k] = true end
					end
				end
			end
		elseif typeof(raw.saved) == "table" and next(d.saved) then
			d.coins = 20 * distinct(d) -- v2
		end
	end
	fillOrders(d)
	return d
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

local function today() return math.floor(os.time() / 86400) end
local function dailyReady(d: Profile) return d.daily.last < today() end

local function pushState(plr)
	local d = data[plr]
	if not d then return end
	plr:SetAttribute("RangeLvl", d.levels.range)
	plr:SetAttribute("PowerLvl", d.levels.power)
	plr:SetAttribute("GardenOpen", gardenOpen(d))
	plr:SetAttribute("Companion", d.equipped or "")
	StateEv:FireClient(plr, {
		jar = jars[plr], cap = cap(d), saved = d.saved, equipped = d.equipped, coins = d.coins, dust = d.dust,
		levels = d.levels, tutorialDone = d.tutorialDone, orders = d.orders, settings = d.settings,
		gardenOpen = gardenOpen(d), distinct = distinct(d), persistent = store ~= nil and not d.loadFailed,
		xp = d.xp, level = d.level, xpNext = Catalog.Progress.xpToNext(d.level), daily = d.daily, dailyReady = dailyReady(d),
		skins = d.skins, skin = d.skin, milestones = d.milestones,
	})
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		ls["Духи"].Value = distinct(d)
		ls["Уровень"].Value = d.level
	end
end

local function rootOf(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ фонарь игрока (виден всем)
local function giveLantern(plr, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	local p = Instance.new("Part")
	p.Name = "Lantern"
	local skin = Catalog.Progress.Skins[data[plr] and data[plr].skin or "classic"] or Catalog.Progress.Skins.classic
	p.Size, p.Material, p.Color = Vector3.new(0.6, 0.8, 0.6), Enum.Material.Neon, skin.lamp
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = root.CFrame * CFrame.new(0.9, 0.3, -0.9)
	local w = Instance.new("Weld")
	w.Name, w.Part0, w.Part1, w.C0 = "Weld", root, p, CFrame.new(0.9, 0.3, -0.9)
	w.Parent = p
	local sl = Instance.new("SpotLight")
	sl.Name, sl.Face, sl.Angle, sl.Brightness = "Beam", Enum.NormalId.Front, 40, 3
	sl.Range = data[plr] and range(data[plr]) or 30
	sl.Color = skin.beam
	sl.Parent = p
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 8, 0.8, Color3.fromRGB(255, 220, 160)
	pl.Parent = p
	local att = Instance.new("Attachment")
	att.Name = "BeamAtt"
	att.Parent = p
	p.Parent = char
end

------------------------------------------------------------------ духи
local spiritsFolder = Instance.new("Folder")
spiritsFolder.Name = "Spirits"
spiritsFolder.Parent = workspace

type Spirit = {
	id: number, kind: string, district: string, anchor: Part, revealed: boolean, revealedAt: number,
	born: number, pos: Vector3, dir: Vector3, goal: Vector3, progress: number, tut: boolean,
}
local live: { [number]: Spirit } = {}
local nextId = 0
local moon = { active = false }

local function rnd(a, b) return a + math.random() * (b - a) end

local function zonePoint(district, near: Vector3?, tut: boolean?, kind: string?)
	if tut then
		return Vector3.new(rnd(-14, 14), 0.5, rnd(34, 62))
	end
	local info = kind and Catalog.Kinds[kind]
	if info and info.spots then
		-- любимые места вида (мосты, пруд)
		local spot = info.spots[math.random(#info.spots)]
		if Catalog.district(spot.Z) == district then
			return spot + Vector3.new(rnd(-6, 6), 0, rnd(-3, 3))
		end
	end
	local zones = Catalog.Districts[district].zones
	local zone = zones[math.random(#zones)]
	if near and #zones > 1 then
		-- остаётся на своём берегу
		for _, z in zones do
			if near.Z >= z.z[1] - 1 and near.Z <= z.z[2] + 1 then zone = z end
		end
	end
	return Vector3.new(rnd(zone.x[1], zone.x[2]), 0.5, rnd(zone.z[1], zone.z[2]))
end

local function lift(kind, p: Vector3)
	return Vector3.new(p.X, 0.5 + Catalog.Kinds[kind].height, p.Z)
end

local function newSpirit(kind, district, tut: boolean?)
	nextId += 1
	local info = Catalog.Kinds[kind]
	local a = Instance.new("Part")
	a.Name = "Spirit"
	a.Size, a.Transparency = Vector3.new(1, 1, 1), 1
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	local att = Instance.new("Attachment")
	att.Name = "Att"
	att.Parent = a
	local start = lift(kind, zonePoint(district, nil, tut, kind))
	local s: Spirit = {
		id = nextId, kind = kind, district = district, anchor = a, revealed = info.move == "swim", revealedAt = os.clock(),
		born = os.clock(), pos = start, dir = Vector3.new(0, 0, -1), goal = lift(kind, zonePoint(district, start, tut, kind)),
		progress = 0, tut = tut == true,
	}
	if info.move == "swim" then
		s.pos = Catalog.Districts[district].swim.center
	end
	a.CFrame = CFrame.new(s.pos)
	a:SetAttribute("SpiritId", s.id)
	a:SetAttribute("Kind", kind)
	a:SetAttribute("Revealed", s.revealed)
	a:SetAttribute("Progress", 0)
	a:SetAttribute("Holders", 0)
	a.Parent = spiritsFolder
	live[s.id] = s
	return s
end

local function stopHold(plr)
	local id = holds[plr]
	holds[plr] = nil
	local s = id and live[id]
	if s then
		local b = s.anchor:FindFirstChild("Beam_" .. plr.UserId)
		if b then b:Destroy() end
	end
end

local function removeSpirit(s: Spirit)
	if live[s.id] ~= s then return end
	for plr, id in holds do
		if id == s.id then stopHold(plr) end
	end
	live[s.id] = nil
	s.anchor:Destroy()
end

local function pickKind(district)
	local tbl = WEIGHTS[moon.active and "moon" or "normal"][district]
	if not tbl or next(tbl) == nil then return nil end
	local total = 0
	for _, w in tbl do total += w end
	local r = math.random() * total
	for k, w in tbl do
		r -= w
		if r <= 0 then return k end
	end
	return next(tbl)
end

------------------------------------------------------------------ движение
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	-- группы ловцов: несколько игроков на одном духе ловят быстрее, каждый получает свой экземпляр
	local groups: { [number]: { Player } } = {}
	for plr, id in holds do
		local s = live[id]
		local root = rootOf(plr)
		local d = data[plr]
		if not (s and root and d and jars[plr]) or #jars[plr] >= cap(d)
			or (root.Position - s.pos).Magnitude > Catalog.catchRange(s.kind) + 4 then
			if d and jars[plr] and #jars[plr] >= cap(d) then NoticeEv:FireClient(plr, "Банка полна — отнеси улов к алтарю") end
			stopHold(plr)
		else
			groups[id] = groups[id] or {}
			table.insert(groups[id], plr)
		end
	end

	for id, s in live do
		local info = Catalog.Kinds[s.kind]
		local g = groups[id]
		if info.move == "swim" then
			local sw = Catalog.Districts[s.district].swim
			local a = now * sw.speed
			s.pos = sw.center + Vector3.new(math.cos(a) * sw.rx, 0, math.sin(a) * sw.rz)
			s.dir = Vector3.new(-math.sin(a) * sw.rx, 0, math.cos(a) * sw.rz).Unit
		else
			local speed = info.speed * (s.revealed and 0.55 or 1) * (g and 0.3 or 1)
			local to = s.goal - s.pos
			if to.Magnitude < 1 then
				s.goal = lift(s.kind, zonePoint(s.district, s.pos, s.tut, s.kind))
			else
				s.dir = Vector3.new(to.X, 0, to.Z).Magnitude > 0.05 and Vector3.new(to.X, 0, to.Z).Unit or s.dir
				s.pos += to.Unit * math.min(speed * dt, to.Magnitude)
			end
		end
		s.anchor.CFrame = CFrame.lookAt(s.pos, s.pos + s.dir)

		if g then
			local speed = 0
			for _, p in g do speed += power(data[p]) end
			s.progress += dt * speed / Catalog.Rarity[info.rarity].catchTime
		elseif s.progress > 0 then
			s.progress = math.max(0, s.progress - dt * 0.4)
		end
		local shown = s.anchor:GetAttribute("Progress")
		if math.abs(shown - s.progress) > 0.02 or (s.progress == 0 and shown ~= 0) then
			s.anchor:SetAttribute("Progress", math.min(s.progress, 1))
		end
		local n = g and #g or 0
		if s.anchor:GetAttribute("Holders") ~= n then s.anchor:SetAttribute("Holders", n) end

		if g and s.progress >= 1 then
			for _, plr in g do
				table.insert(jars[plr], s.kind)
				CaughtEv:FireClient(plr, s.kind, s.pos, #g)
				local d = data[plr]
				local xp = Catalog.Progress.XP[info.rarity] or 4
				d.xp += xp
				local levelUp = nil
				while d.xp >= Catalog.Progress.xpToNext(d.level) do
					d.xp -= Catalog.Progress.xpToNext(d.level)
					d.level += 1
					local bonus = Catalog.Progress.levelReward(d.level)
					d.coins += bonus
					levelUp = { level = d.level, coins = bonus }
				end
				RewardEv:FireClient(plr, { xp = xp, levelUp = levelUp })
				pushState(plr)
			end
			removeSpirit(s)
		end
	end
end)

------------------------------------------------------------------ проявление и удержание
RevealEv.OnServerEvent:Connect(function(plr, id)
	local s = typeof(id) == "number" and live[id]
	local root = rootOf(plr)
	local d = data[plr]
	if not (s and root and d) or s.revealed then return end
	if s.district == "garden" and not gardenOpen(d) then return end
	if (root.Position - s.pos).Magnitude > range(d) + 3 then return end
	s.revealed = true
	s.revealedAt = os.clock()
	s.anchor:SetAttribute("Revealed", true)
end)

CatchHoldEv.OnServerEvent:Connect(function(plr, id)
	stopHold(plr)
	if typeof(id) ~= "number" then return end
	local s = live[id]
	local root = rootOf(plr)
	local d = data[plr]
	if not (s and root and d and s.revealed) then return end
	if #jars[plr] >= cap(d) then
		NoticeEv:FireClient(plr, "Банка полна — отнеси улов к алтарю")
		return
	end
	if (root.Position - s.pos).Magnitude > Catalog.catchRange(s.kind) + 2 then return end
	holds[plr] = id
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	local att = lantern and lantern:FindFirstChild("BeamAtt")
	if att then
		local b = Instance.new("Beam")
		b.Name = "Beam_" .. plr.UserId
		b.Attachment0, b.Attachment1 = att, s.anchor.Att
		b.Width0, b.Width1, b.LightEmission, b.FaceCamera = 0.4, 1.6, 1, true
		b.Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Catalog.Rarity[Catalog.Kinds[s.kind].rarity].color)
		b.Transparency = NumberSequence.new(0.2, 0.5)
		b.Parent = s.anchor
	end
end)

------------------------------------------------------------------ появление и исчезновение
local function districtCount(d)
	local n, tutN = 0, 0
	for _, s in live do
		if s.district == d then
			n += 1
			if s.tut and not s.revealed then tutN += 1 end
		end
	end
	return n, tutN
end

newSpirit("PaperFox", "street", true)
newSpirit("PaperFox", "street", true)

task.spawn(function()
	while true do
		local now = os.clock()
		for _, s in live do
			local held = s.anchor:GetAttribute("Holders") > 0
			if not held and not Catalog.Kinds[s.kind].moonOnly then
				if (not s.revealed and now - s.born > 110) or (s.revealed and now - s.revealedAt > 35) then removeSpirit(s) end
			end
		end
		for district, dc in Catalog.Districts do
			local max = dc.max
			local n, tutN = districtCount(district)
			if district == "street" and tutN < 2 then
				newSpirit("PaperFox", "street", true) -- рядом с алтарём всегда есть лис для обучения
			elseif max > 0 and n < max + (moon.active and 2 or 0) then
				local kind = pickKind(district)
				if kind then newSpirit(kind, district) end
			end
		end
		task.wait(1.5)
	end
end)

------------------------------------------------------------------ Красная луна и они
local function tweenLight(red)
	local ti = TweenInfo.new(2.5)
	TweenService:Create(Lighting, ti, red and { Ambient = Color3.fromRGB(70, 52, 66), OutdoorAmbient = Color3.fromRGB(78, 56, 72) }
		or { Ambient = Color3.fromRGB(52, 52, 82), OutdoorAmbient = Color3.fromRGB(58, 60, 92) }):Play()
	TweenService:Create(cc, ti, red and { TintColor = Color3.fromRGB(255, 232, 232), Saturation = 0 } or { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	TweenService:Create(atm, ti, { Color = red and Color3.fromRGB(190, 45, 55) or Color3.fromRGB(80, 90, 150), Decay = red and Color3.fromRGB(120, 20, 40) or Color3.fromRGB(40, 30, 80) }):Play()
	TweenService:Create(map.moon, ti, { Transparency = red and 0 or 1 }):Play()
end

local function hitPlayer(plr)
	local lost = jars[plr] and #jars[plr] or 0
	jars[plr] = {}
	stopHold(plr)
	local c = plr.Character
	if c then c:PivotTo(map.spawnCF + Vector3.new(0, 3, 0)) end
	HitEv:FireClient(plr, lost)
	pushState(plr)
end

local oniAnchor: Part? = nil
local oniPos = Vector3.new(0, 0.5, 118)
local function oniLoop(a: Part)
	local facing = Vector3.new(0, 0, -1)
	local function place() a.CFrame = CFrame.lookAt(oniPos, oniPos + facing) end
	local function walkTo(goal: Vector3, speed, maxT)
		local t0 = os.clock()
		a:SetAttribute("State", "walk")
		while moon.active and a.Parent and os.clock() - t0 < maxT do
			local d = Vector3.new(goal.X, 0.5, goal.Z) - oniPos
			if d.Magnitude < 1.5 then break end
			facing = d.Unit
			oniPos += facing * math.min(speed * 0.05, d.Magnitude)
			place()
			task.wait(0.05)
		end
	end
	while moon.active and a.Parent do
		local target, best = nil, math.huge
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r and (r.Position - map.altarPos).Magnitude > SAFE_RADIUS and r.Position.Z > -72 and r.Position.Y > -2 then
				local d = (r.Position - oniPos).Magnitude - ((jars[plr] and #jars[plr] > 0) and 40 or 0)
				if d < best then target, best = r, d end
			end
		end
		if not target then
			walkTo(Vector3.new(rnd(-12, 12), 0.5, rnd(40, 120)), 7, 4)
			continue
		end
		-- подходит к игроку
		local tStart = os.clock()
		a:SetAttribute("State", "walk")
		while moon.active and target.Parent and os.clock() - tStart < 3.5 do
			local d = Vector3.new(target.Position.X, 0.5, target.Position.Z) - oniPos
			if d.Magnitude < 10 then break end
			facing = d.Unit
			oniPos += facing * 0.6
			place()
			task.wait(0.05)
		end
		if not (moon.active and target.Parent) then continue end
		local center = Vector3.new(target.Position.X, target.Position.Y - 2.9, target.Position.Z)
		if (center - map.altarPos).Magnitude < SAFE_RADIUS or center.Z < -72 then continue end
		local f = Vector3.new(center.X - oniPos.X, 0, center.Z - oniPos.Z)
		if f.Magnitude > 0.1 then facing = f.Unit end
		place()
		-- круг удара заранее
		a:SetAttribute("State", "windup")
		local ring = Instance.new("Part")
		ring.Name = "OniWarning"
		ring.Shape, ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = Enum.PartType.Cylinder, true, false, false, false
		ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 25, 25), 0.3
		ring.Size = Vector3.new(0.15, ONI_RADIUS * 2, ONI_RADIUS * 2)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		-- белая кромка: круг читается и при красном свете луны
		local edge = ring:Clone()
		edge.Name, edge.Color, edge.Transparency = "OniWarningEdge", Color3.new(1, 1, 1), 0.1
		edge.Size = Vector3.new(0.12, ONI_RADIUS * 2 + 0.8, ONI_RADIUS * 2 + 0.8)
		edge.CFrame = ring.CFrame * CFrame.new(-0.02, 0, 0)
		edge.Parent = workspace
		task.delay(ONI_WARN + 0.05, function() edge:Destroy() end)
		local fill = ring:Clone()
		fill.Transparency, fill.Size, fill.Color = 0.2, Vector3.new(0.2, 0.5, 0.5), Color3.fromRGB(255, 140, 60)
		fill.Parent = workspace
		TweenService:Create(fill, TweenInfo.new(ONI_WARN, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, ONI_RADIUS * 2, ONI_RADIUS * 2) }):Play()
		task.wait(ONI_WARN)
		a:SetAttribute("State", "strike")
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r then
				local d = r.Position - center
				if Vector3.new(d.X, 0, d.Z).Magnitude <= ONI_RADIUS and math.abs(d.Y) < 8 then hitPlayer(plr) end
			end
		end
		fill:Destroy()
		ring.Color, ring.Transparency = Color3.fromRGB(255, 220, 180), 0.2
		TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.1, ONI_RADIUS * 2.6, ONI_RADIUS * 2.6) }):Play()
		task.delay(0.45, function() ring:Destroy() end)
		task.wait(1.3)
	end
end

local function setPhase(active, secs)
	moon.active = active
	workspace:SetAttribute("MoonActive", active)
	workspace:SetAttribute("PhaseEnds", workspace:GetServerTimeNow() + secs)
end

local function startMoon()
	setPhase(true, MOON_TIME)
	tweenLight(true)
	if IS_TEST or math.random() < 0.35 then newSpirit("GoldenCarp", "canal") end
	if IS_TEST or math.random() < 0.5 then newSpirit("MoonRabbit", "street") end
	if IS_TEST or math.random() < 0.5 then newSpirit("FoxFire", "canal") end
	newSpirit("Crane", "garden")
	local a = Instance.new("Part")
	a.Name = "Oni"
	a.Size, a.Transparency = Vector3.new(1, 1, 1), 1
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	oniPos = Vector3.new(0, 0.5, 118)
	a.CFrame = CFrame.new(oniPos)
	a:SetAttribute("State", "walk")
	a.Parent = workspace
	oniAnchor = a
	task.spawn(oniLoop, a)
end

local function endMoon()
	setPhase(false, NORMAL_TIME)
	tweenLight(false)
	if oniAnchor then oniAnchor:Destroy() oniAnchor = nil end
	for _, s in live do
		if Catalog.Kinds[s.kind].moonOnly then removeSpirit(s) end
	end
end

task.spawn(function()
	setPhase(false, FIRST_MOON)
	task.wait(FIRST_MOON)
	while true do
		startMoon()
		task.wait(MOON_TIME)
		endMoon()
		task.wait(NORMAL_TIME)
	end
end)

------------------------------------------------------------------ алтарь
local savePrompt = Instance.new("ProximityPrompt")
savePrompt.ActionText, savePrompt.ObjectText = "Сохранить улов", "Алтарь"
savePrompt.HoldDuration, savePrompt.MaxActivationDistance = 0.25, ALTAR_RANGE
savePrompt.RequiresLineOfSight = false
savePrompt.Parent = map.altar

local function doSave(plr)
	local root = rootOf(plr)
	local d = data[plr]
	if not (root and d) then return { ok = false, msg = "Нет персонажа" } end
	if (root.Position - map.altarPos).Magnitude > ALTAR_RANGE + 6 then return { ok = false, msg = "Подойди к алтарю" } end
	local jar = jars[plr]
	if #jar == 0 then return { ok = false, msg = "Банка пуста — сначала поймай духа" } end
	local wasOpen = gardenOpen(d)
	local firsts, dust, coins = {}, 0, 0
	for _, kind in jar do
		local rar = Catalog.Rarity[Catalog.Kinds[kind].rarity]
		coins += rar.coins
		if (d.saved[kind] or 0) > 0 then
			dust += rar.dust -- дубликат → пыль духов
		end
		d.saved[kind] = (d.saved[kind] or 0) + 1
		if not d.firstSaved[kind] then
			d.firstSaved[kind] = true
			table.insert(firsts, kind)
		end
		-- заказы
		for _, o in d.orders do
			if o.have < o.need and ((o.type == "kind" and o.kind == kind) or (o.type == "rarity" and o.rarity == Catalog.Kinds[kind].rarity)) then
				o.have += 1
				break
			end
		end
	end
	local done = {}
	for i = #d.orders, 1, -1 do
		local o = d.orders[i]
		if o.have >= o.need then
			coins += o.coins
			dust += o.dust
			table.insert(done, o)
			table.remove(d.orders, i)
		end
	end
	fillOrders(d)
	d.coins += coins
	d.dust += dust
	local kinds = table.clone(jar)
	jars[plr] = {}
	local persisted = persist(plr)
	pushState(plr)
	return { ok = true, kinds = kinds, firsts = firsts, coins = coins, dust = dust, orders = done,
		gardenOpened = not wasOpen and gardenOpen(d), persisted = persisted }
end
savePrompt.Triggered:Connect(function(plr)
	SaveResultEv:FireClient(plr, doSave(plr))
end)

UpgradeFn.OnServerInvoke = function(plr, which)
	local d = data[plr]
	local root = rootOf(plr)
	if not (d and root) then return { ok = false, msg = "Нет персонажа" } end
	local up = typeof(which) == "string" and Catalog.Upgrades[which]
	if not up then return { ok = false } end
	local lvl = d.levels[which]
	if lvl >= Catalog.MaxLevel then return { ok = false, msg = "Максимальный уровень" } end
	local c, du = up.coins[lvl], up.dust[lvl]
	if d.coins < c or d.dust < du then return { ok = false, msg = ("Нужно: %d монет и %d пыли"):format(c, du) } end
	d.coins -= c
	d.dust -= du
	d.levels[which] = lvl + 1
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	if lantern and lantern:FindFirstChild("Beam") then
		lantern.Beam.Range = range(d)
		lantern.Beam.Angle = 36 + d.levels.range * 4
	end
	persist(plr)
	pushState(plr)
	return { ok = true }
end

local function grant(d: Profile, r)
	d.coins += r.coins or 0
	d.dust += r.dust or 0
	if r.skin then d.skins[r.skin] = true end
end

DailyFn.OnServerInvoke = function(plr)
	local d = data[plr]
	if not d then return { ok = false } end
	if not dailyReady(d) then return { ok = false, msg = "Подарок уже получен, приходи завтра" } end
	local streak = (d.daily.last == today() - 1) and (d.daily.streak % #Catalog.Progress.Daily) + 1 or 1
	d.daily = { last = today(), streak = streak }
	local r = Catalog.Progress.Daily[streak]
	grant(d, r)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = r.coins, dust = r.dust, skin = r.skin })
	return { ok = true, day = streak }
end

MilestoneFn.OnServerInvoke = function(plr, i)
	local d = data[plr]
	local m = typeof(i) == "number" and Catalog.Progress.Milestones[i]
	if not (d and m) then return { ok = false } end
	local key = tostring(i)
	if d.milestones[key] then return { ok = false, msg = "Уже получено" } end
	if distinct(d) < m.need then return { ok = false, msg = ("Нужно видов: %d"):format(m.need) } end
	d.milestones[key] = true
	grant(d, m)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = m.coins, dust = m.dust, skin = m.skin })
	return { ok = true }
end

local function applySkin(plr)
	local d = data[plr]
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	local skin = d and Catalog.Progress.Skins[d.skin]
	if lantern and skin then
		lantern.Color = skin.lamp
		if lantern:FindFirstChild("Beam") then lantern.Beam.Color = skin.beam end
	end
end

SkinFn.OnServerInvoke = function(plr, action, key)
	local d = data[plr]
	local skin = typeof(key) == "string" and Catalog.Progress.Skins[key]
	if not (d and skin) then return { ok = false } end
	if action == "buy" then
		if d.skins[key] then return { ok = false, msg = "Уже куплено" } end
		if not skin.price then return { ok = false, msg = "Получи: " .. (skin.source or "") } end
		local du = skin.dust or 0
		if d.coins < skin.price or d.dust < du then return { ok = false, msg = "Не хватает монет или пыли" } end
		d.coins -= skin.price
		d.dust -= du
		d.skins[key] = true
		d.skin = key
	elseif action == "equip" then
		if not d.skins[key] then return { ok = false, msg = "Облик не открыт" } end
		d.skin = key
	else
		return { ok = false }
	end
	applySkin(plr)
	persist(plr)
	pushState(plr)
	return { ok = true }
end

SettingsEv.OnServerEvent:Connect(function(plr, t)
	local d = data[plr]
	if not (d and typeof(t) == "table") then return end
	d.settings.music = num(t.music, 0, 1, d.settings.music)
	d.settings.sfx = num(t.sfx, 0, 1, d.settings.sfx)
	if typeof(t.reduced) == "boolean" then d.settings.reduced = t.reduced end
	if typeof(t.diag) == "boolean" then d.settings.diag = t.diag end
end)

EquipFn.OnServerInvoke = function(plr, kind)
	local d = data[plr]
	if not d then return false end
	if kind == nil then
		d.equipped = nil
	elseif typeof(kind) == "string" and (d.saved[kind] or 0) > 0 then
		d.equipped = kind
	else
		return false
	end
	persist(plr)
	pushState(plr)
	return true
end

TutorialEv.OnServerEvent:Connect(function(plr)
	local d = data[plr]
	if d and not d.tutorialDone then
		d.tutorialDone = true
		persist(plr)
		pushState(plr)
	end
end)

------------------------------------------------------------------ сторож: сад и вода
task.spawn(function()
	while true do
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			local d = data[plr]
			if r and d then
				local p = r.Position
				if p.Y < -3.5 then
					-- упал в канал: на ближайший берег
					plr.Character:PivotTo(CFrame.new(math.clamp(p.X, -55, 55), 4, p.Z > -30 and -14 or -46))
				elseif p.Z < -73 and not gardenOpen(d) then
					plr.Character:PivotTo(CFrame.new(math.clamp(p.X, -10, 10), 4, -64))
					NoticeEv:FireClient(plr, ("Сад откроется, когда сохранишь 3 разных духа (%d/3)"):format(distinct(d)))
				end
			end
		end
		task.wait(0.3)
	end
end)

------------------------------------------------------------------ игроки
Players.PlayerAdded:Connect(function(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local v = Instance.new("IntValue")
	v.Name = "Духи"
	v.Parent = ls
	local lv = Instance.new("IntValue")
	lv.Name = "Уровень"
	lv.Parent = ls
	ls.Parent = plr

	local raw, failed = nil, false
	if store then
		failed = true
		for attempt = 1, 3 do
			local ok, res = pcall(function() return store:GetAsync("u" .. plr.UserId) end)
			if ok then
				raw, failed = res, false
				break
			end
			warn("DataStore load failed:", res)
			task.wait(attempt)
		end
	end
	if not plr.Parent then return end
	local d = migrate(raw)
	d.loadFailed = failed or nil
	data[plr] = d
	jars[plr] = {}
	plr.CharacterAdded:Connect(function(char)
		giveLantern(plr, char)
		task.wait(0.3)
		pushState(plr)
	end)
	if plr.Character then giveLantern(plr, plr.Character) end
	pushState(plr)
	if failed then NoticeEv:FireClient(plr, "Не удалось загрузить сохранение — прогресс этой сессии не запишется") end
end)

Players.PlayerRemoving:Connect(function(plr)
	stopHold(plr)
	persist(plr)
	data[plr], jars[plr] = nil, nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do persist(plr) end
	end
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do persist(plr) end
end)
