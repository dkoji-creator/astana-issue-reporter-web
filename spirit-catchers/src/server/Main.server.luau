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
local DISTRICT_MAX = { street = 6, canal = 6, garden = 7 }
local WEIGHTS = {
	normal = {
		street = { PaperFox = 60, LanternSpirit = 35, Crane = 5 },
		canal = { PaperFox = 30, Umbrella = 55, LanternSpirit = 15 },
		garden = { Firefly = 50, Kodama = 38, Crane = 12 },
	},
	moon = {
		street = { PaperFox = 40, LanternSpirit = 35, MoonRabbit = 25 },
		canal = { PaperFox = 25, Umbrella = 45, LanternSpirit = 20, Crane = 10 },
		garden = { Firefly = 35, Kodama = 30, Crane = 25, MoonRabbit = 10 },
	},
}

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
remotes.Parent = ReplicatedStorage

------------------------------------------------------------------ свет
Lighting.ClockTime = 0
Lighting.Brightness = 1.3
Lighting.Ambient = Color3.fromRGB(75, 75, 115)
Lighting.OutdoorAmbient = Color3.fromRGB(90, 90, 135)
Lighting.EnvironmentDiffuseScale = 0.3
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity, bloom.Size, bloom.Threshold = 0.6, 24, 0.9
bloom.Parent = Lighting
local atm = Instance.new("Atmosphere")
atm.Density, atm.Haze, atm.Color, atm.Decay = 0.3, 1.1, Color3.fromRGB(80, 90, 150), Color3.fromRGB(40, 30, 80)
atm.Parent = Lighting

------------------------------------------------------------------ профили (версия 3; сохранения версии 2 переносятся)
local store = nil
pcall(function() store = DataStoreService:GetDataStore("SpiritCatchers_v1") end)

type Profile = {
	version: number, saved: { [string]: number }, firstSaved: { [string]: boolean }, equipped: string?,
	materials: number, lanternLvl: number, jarLvl: number, tutorialDone: boolean, loadFailed: boolean?,
}
local data: { [Player]: Profile } = {}
local jars: { [Player]: { string } } = {}
local holds: { [Player]: number } = {}

local function clampLvl(v)
	return typeof(v) == "number" and math.clamp(math.floor(v), 1, Catalog.MaxLevel) or 1
end

local function migrate(raw): Profile
	local d: Profile = { version = 3, saved = {}, firstSaved = {}, equipped = nil, materials = 0, lanternLvl = 1, jarLvl = 1, tutorialDone = false }
	if typeof(raw) ~= "table" then return d end
	-- v2: { saved, equipped, firstSaved }
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
		d.materials = typeof(raw.materials) == "number" and math.max(0, math.floor(raw.materials)) or 0
		d.lanternLvl = clampLvl(raw.lanternLvl)
		d.jarLvl = clampLvl(raw.jarLvl)
		d.tutorialDone = raw.tutorialDone == true
	end
	return d
end

local function distinct(d: Profile)
	local n = 0
	for _, v in d.saved do
		if v > 0 then n += 1 end
	end
	return n
end
local function gardenOpen(d: Profile) return distinct(d) >= Catalog.GardenNeed end
local function cap(d: Profile) return Catalog.JarCap[d.jarLvl] end

local function persist(plr)
	local d = data[plr]
	if not (store and d) or d.loadFailed then return false end
	local copy = table.clone(d)
	copy.loadFailed = nil
	local ok, err = pcall(function() store:SetAsync("u" .. plr.UserId, copy) end)
	if not ok then warn("DataStore save failed:", err) end
	return ok
end

local function pushState(plr)
	local d = data[plr]
	if not d then return end
	plr:SetAttribute("LanternLvl", d.lanternLvl)
	plr:SetAttribute("GardenOpen", gardenOpen(d))
	plr:SetAttribute("Companion", d.equipped or "")
	StateEv:FireClient(plr, {
		jar = jars[plr], cap = cap(d), saved = d.saved, equipped = d.equipped, materials = d.materials,
		lanternLvl = d.lanternLvl, jarLvl = d.jarLvl, tutorialDone = d.tutorialDone,
		gardenOpen = gardenOpen(d), distinct = distinct(d), persistent = store ~= nil and not d.loadFailed,
	})
	local ls = plr:FindFirstChild("leaderstats")
	if ls then ls.Spirits.Value = distinct(d) end
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
	p.Size, p.Material, p.Color = Vector3.new(0.6, 0.8, 0.6), Enum.Material.Neon, Color3.fromRGB(255, 225, 160)
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = root.CFrame * CFrame.new(0.9, 0.3, -0.9)
	local w = Instance.new("Weld")
	w.Name, w.Part0, w.Part1, w.C0 = "Weld", root, p, CFrame.new(0.9, 0.3, -0.9)
	w.Parent = p
	local sl = Instance.new("SpotLight")
	sl.Name, sl.Face, sl.Angle, sl.Brightness = "Beam", Enum.NormalId.Front, 40, 6
	sl.Range = Catalog.LanternRange[data[plr] and data[plr].lanternLvl or 1]
	sl.Color = Color3.fromRGB(255, 240, 200)
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

local function zonePoint(district, near: Vector3?, tut: boolean?)
	if district == "street" then
		return Vector3.new(rnd(-14, 14), 0.5, tut and rnd(34, 62) or rnd(34, 124))
	elseif district == "canal" then
		local north = if near then near.Z > -30 else math.random() < 0.5
		return Vector3.new(rnd(-56, 56), 0.5, north and rnd(-18, -11) or rnd(-49, -42))
	end
	return Vector3.new(rnd(-38, 38), 0.5, rnd(-144, -80))
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
	local start = lift(kind, zonePoint(district, nil, tut))
	local s: Spirit = {
		id = nextId, kind = kind, district = district, anchor = a, revealed = info.move == "swim", revealedAt = os.clock(),
		born = os.clock(), pos = start, dir = Vector3.new(0, 0, -1), goal = lift(kind, zonePoint(district, start, tut)),
		progress = 0, tut = tut == true,
	}
	if info.move == "swim" then
		s.pos = Vector3.new(0, 1.5, -30)
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
			local a = now * 0.3
			s.pos = Vector3.new(math.cos(a) * 22, 1.5, -30 + math.sin(a) * 6)
			s.dir = Vector3.new(-math.sin(a) * 22, 0, math.cos(a) * 6).Unit
		else
			local speed = info.speed * (s.revealed and 0.55 or 1) * (g and 0.3 or 1)
			local to = s.goal - s.pos
			if to.Magnitude < 1 then
				s.goal = lift(s.kind, zonePoint(s.district, s.pos, s.tut))
			else
				s.dir = Vector3.new(to.X, 0, to.Z).Magnitude > 0.05 and Vector3.new(to.X, 0, to.Z).Unit or s.dir
				s.pos += to.Unit * math.min(speed * dt, to.Magnitude)
			end
		end
		s.anchor.CFrame = CFrame.lookAt(s.pos, s.pos + s.dir)

		if g then
			local speed = 0
			for _, p in g do speed += Catalog.LanternSpeed[data[p].lanternLvl] end
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
	if (root.Position - s.pos).Magnitude > Catalog.LanternRange[d.lanternLvl] + 3 then return end
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
		for district, max in DISTRICT_MAX do
			local n, tutN = districtCount(district)
			if district == "street" and tutN < 2 then
				newSpirit("PaperFox", "street", true) -- рядом с алтарём всегда есть лис для обучения
			elseif n < max + (moon.active and 2 or 0) then
				newSpirit(pickKind(district), district)
			end
		end
		task.wait(1.5)
	end
end)

------------------------------------------------------------------ Красная луна и они
local function tweenLight(red)
	local ti = TweenInfo.new(2.5)
	TweenService:Create(Lighting, ti, red and { Ambient = Color3.fromRGB(115, 55, 65), OutdoorAmbient = Color3.fromRGB(130, 60, 70) }
		or { Ambient = Color3.fromRGB(75, 75, 115), OutdoorAmbient = Color3.fromRGB(90, 90, 135) }):Play()
	TweenService:Create(cc, ti, red and { TintColor = Color3.fromRGB(255, 205, 205), Saturation = 0.1 } or { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	TweenService:Create(atm, ti, { Color = red and Color3.fromRGB(160, 60, 70) or Color3.fromRGB(80, 90, 150) }):Play()
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
		ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 30, 30), 0.5
		ring.Size = Vector3.new(0.15, ONI_RADIUS * 2, ONI_RADIUS * 2)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
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
	local firsts, gained = {}, 0
	for _, kind in jar do
		if (d.saved[kind] or 0) > 0 then
			gained += Catalog.Rarity[Catalog.Kinds[kind].rarity].material -- дубликат → материал
		end
		d.saved[kind] = (d.saved[kind] or 0) + 1
		if not d.firstSaved[kind] then
			d.firstSaved[kind] = true
			table.insert(firsts, kind)
		end
	end
	d.materials += gained
	local kinds = table.clone(jar)
	jars[plr] = {}
	local persisted = persist(plr)
	pushState(plr)
	return { ok = true, kinds = kinds, firsts = firsts, gained = gained, gardenOpened = not wasOpen and gardenOpen(d), persisted = persisted }
end
savePrompt.Triggered:Connect(function(plr)
	SaveResultEv:FireClient(plr, doSave(plr))
end)

UpgradeFn.OnServerInvoke = function(plr, which)
	local d = data[plr]
	local root = rootOf(plr)
	if not (d and root) then return { ok = false, msg = "Нет персонажа" } end
	if (root.Position - map.altarPos).Magnitude > 30 then return { ok = false, msg = "Улучшения — у алтаря" } end
	local key = which == "lantern" and "lanternLvl" or which == "jar" and "jarLvl" or nil
	if not key then return { ok = false } end
	local lvl = d[key]
	if lvl >= Catalog.MaxLevel then return { ok = false, msg = "Максимальный уровень" } end
	local cost = Catalog.UpgradeCost[lvl]
	if d.materials < cost then return { ok = false, msg = ("Нужно ✦%d материала"):format(cost) } end
	d.materials -= cost
	d[key] = lvl + 1
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	if lantern and lantern:FindFirstChild("Beam") then lantern.Beam.Range = Catalog.LanternRange[d.lanternLvl] end
	persist(plr)
	pushState(plr)
	return { ok = true }
end

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
	v.Name = "Spirits"
	v.Parent = ls
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
