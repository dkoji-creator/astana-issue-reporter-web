-- Spirit Catchers: сервер. Вылазка: лис → Красная луна → карп/они → алтарь.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Spirits = require(ReplicatedStorage.Shared.Spirits)

local TEST_PLACE_ID = 99980756426085
-- Закрытый тест: карп гарантированно приходит в первую Красную луну (Studio и тестовый плейс).
local FORCE_CARP = RunService:IsStudio() or game.PlaceId == TEST_PLACE_ID
local CARP_CHANCE = 0.35

local REVEAL_RANGE, CATCH_RANGE, ALTAR_RANGE = 30, 15, 16
local CATCH_TIME = { PaperFox = 1.5, GoldenCarp = 2.5 }
local MAX_FOXES = 4
local MOON_TIME, MOON_COOLDOWN = 75, 20
local ONI_RADIUS, ONI_WARN, SAFE_RADIUS = 8, 1.6, 24

------------------------------------------------------------------ remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
remotes.Parent = ReplicatedStorage
local function remote(name, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local RevealEv = remote("Reveal")
local CatchStartEv = remote("CatchStart")
local CatchFinishEv = remote("CatchFinish")
local EquipFn = remote("Equip", "RemoteFunction")
local StateEv = remote("State") -- {jar, jarKinds, saved, equipped} | {saveResult}
local CaughtEv = remote("Caught") -- kind, position
local MoonEv = remote("Moon") -- active
local HitEv = remote("Hit") -- lost count

------------------------------------------------------------------ свет
Lighting.ClockTime = 0
Lighting.Brightness = 1.2
Lighting.Ambient = Color3.fromRGB(70, 70, 110)
Lighting.OutdoorAmbient = Color3.fromRGB(80, 80, 125)
Lighting.EnvironmentDiffuseScale = 0.3
local cc = Instance.new("ColorCorrectionEffect")
cc.Name = "MoonTint"
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Intensity, bloom.Size, bloom.Threshold = 0.6, 24, 0.9
bloom.Parent = Lighting
local atm = Instance.new("Atmosphere")
atm.Density, atm.Haze, atm.Color, atm.Decay = 0.32, 1.2, Color3.fromRGB(80, 90, 150), Color3.fromRGB(40, 30, 80)
atm.Parent = Lighting

------------------------------------------------------------------ квартал
local world = Instance.new("Folder")
world.Name = "World"
world.Parent = workspace
local function block(name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.Material = mat or Enum.Material.Slate
	for k, v in props or {} do p[k] = v end
	p.Parent = world
	return p
end
local function light(parent, color, range, brightness, cls)
	local l = Instance.new(cls or "PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Parent = parent
	return l
end
local WARM = Color3.fromRGB(255, 160, 80)
local COLD = Color3.fromRGB(110, 200, 255)

local stone = Color3.fromRGB(70, 68, 82)
block("StreetN", Vector3.new(40, 1, 60), CFrame.new(0, 0, -42), stone, Enum.Material.Cobblestone)
block("StreetS", Vector3.new(40, 1, 80), CFrame.new(0, 0, 52), stone, Enum.Material.Cobblestone)
for _, x in { -20, 20 } do
	block("CanalWall", Vector3.new(1, 7, 24), CFrame.new(x, -3, 0), Color3.fromRGB(60, 55, 60))
end
block("CanalBed", Vector3.new(40, 1, 24), CFrame.new(0, -7, 0), Color3.fromRGB(10, 15, 30))
block("Water", Vector3.new(40, 0.4, 24), CFrame.new(0, -3, 0), Color3.fromRGB(25, 60, 110), Enum.Material.Glass,
	{ Transparency = 0.35, Reflectance = 0.35, CanCollide = false })
-- цветные «отражения» фонарей под водой
local refl = { WARM, Color3.fromRGB(255, 90, 140), COLD, Color3.fromRGB(255, 200, 90) }
for i = 1, 12 do
	local x = -18 + (i - 1) * 3.3
	block("Reflection", Vector3.new(0.8, 0.1, 4 + (i % 3) * 3), CFrame.new(x, -3.6, ((i * 7) % 13) - 6), refl[i % 4 + 1], Enum.Material.Neon,
		{ CanCollide = false, Transparency = 0.35 })
end
block("Bridge", Vector3.new(12, 1, 26), CFrame.new(0, 0.6, 0), Color3.fromRGB(150, 45, 40), Enum.Material.Wood)
for _, x in { -6, 6 } do
	block("Rail", Vector3.new(0.5, 2.5, 26), CFrame.new(x, 2.3, 0), Color3.fromRGB(190, 55, 45), Enum.Material.Wood)
	for _, z in { -12, 12 } do
		local post = block("BridgeLamp", Vector3.new(1.2, 1.6, 1.2), CFrame.new(x, 4.4, z), WARM, Enum.Material.Neon, { CanCollide = false })
		light(post, WARM, 18, 1.6)
	end
end
-- домики с крышами
for i = -3, 3 do
	if i ~= 0 then
		for _, side in { -1, 1 } do
			local h = 10 + (i % 3) * 4
			local z = i * 22
			block("House", Vector3.new(14, h, 18), CFrame.new(side * 27, h / 2, z), Color3.fromRGB(85, 70, 90), Enum.Material.Brick)
			block("Roof", Vector3.new(16, 1, 20), CFrame.new(side * 27, h + 0.5, z), Color3.fromRGB(110, 35, 40), Enum.Material.Slate)
			block("Window", Vector3.new(0.3, 3, 4), CFrame.new(side * 19.9, 6, z), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
			block("Step", Vector3.new(4, h / 2, 4), CFrame.new(side * 18, h / 4, z + 7), Color3.fromRGB(90, 75, 60), Enum.Material.Wood)
		end
	end
end
-- гирлянды тёплых бумажных фонарей ведут к мосту
for z = -50, 64, 6 do
	if math.abs(z) > 13 then
		for _, x in { -13, 13 } do
			local lantern = block("PaperLantern", Vector3.new(1.4, 1.8, 1.4), CFrame.new(x, 9, z), Color3.fromRGB(255, 140, 70), Enum.Material.Neon,
				{ CanCollide = false, Shape = Enum.PartType.Ball })
			if (z // 6) % 2 == 0 then light(lantern, WARM, 20, 1.3) end
		end
		block("String", Vector3.new(26, 0.1, 0.1), CFrame.new(0, 9.8, z), Color3.fromRGB(40, 30, 30), nil, { CanCollide = false })
	end
end
-- алтарь: холодный свет
local ALTAR_POS = Vector3.new(0, 1, 78)
local altar = block("Altar", Vector3.new(8, 3, 8), CFrame.new(ALTAR_POS + Vector3.new(0, 1, 0)), Color3.fromRGB(170, 185, 200), Enum.Material.Marble)
local altarGlow = block("AltarGlow", Vector3.new(3, 3, 3), CFrame.new(ALTAR_POS + Vector3.new(0, 5.5, 0)), COLD, Enum.Material.Neon,
	{ CanCollide = false, Shape = Enum.PartType.Ball })
light(altarGlow, COLD, 36, 3)
for _, x in { -6, 6 } do
	local pillar = block("AltarPillar", Vector3.new(1, 10, 1), CFrame.new(x, 5.5, ALTAR_POS.Z), COLD, Enum.Material.Neon, { Transparency = 0.2 })
	light(pillar, COLD, 18, 1.5)
end
local altarBill = Instance.new("BillboardGui")
altarBill.Size, altarBill.StudsOffset, altarBill.AlwaysOnTop = UDim2.new(0, 160, 0, 40), Vector3.new(0, 4, 0), true
altarBill.MaxDistance = 400
local altarText = Instance.new("TextLabel")
altarText.Size, altarText.BackgroundTransparency, altarText.TextScaled = UDim2.fromScale(1, 1), 1, true
altarText.Font, altarText.TextColor3, altarText.Text = Enum.Font.GothamBold, COLD, "⛩ Алтарь"
altarText.TextStrokeTransparency = 0.3
altarText.Parent = altarBill
altarBill.Parent = altarGlow

local SPAWN_CF = CFrame.new(0, 0.6, 68)
local spawn = Instance.new("SpawnLocation")
spawn.Size, spawn.CFrame, spawn.Anchored, spawn.Transparency, spawn.CanCollide = Vector3.new(6, 1, 6), SPAWN_CF, true, 1, false
spawn.Neutral = true
spawn.Parent = world

local savePrompt = Instance.new("ProximityPrompt")
savePrompt.ActionText, savePrompt.ObjectText = "Сохранить улов", "Алтарь"
savePrompt.HoldDuration, savePrompt.MaxActivationDistance = 0.3, ALTAR_RANGE
savePrompt.RequiresLineOfSight = false
savePrompt.Parent = altar

-- красная луна в небе (видна только во время события)
local moonPart = block("RedMoon", Vector3.new(60, 60, 60), CFrame.new(0, 160, -260), Color3.fromRGB(255, 50, 40), Enum.Material.Neon,
	{ Shape = Enum.PartType.Ball, CanCollide = false, Transparency = 1, CastShadow = false })

------------------------------------------------------------------ данные игроков
local store = nil
pcall(function() store = DataStoreService:GetDataStore("SpiritCatchers_v1") end)

type PData = { saved: { [string]: number }, equipped: string?, firstSaved: { [string]: boolean } }
local data: { [Player]: PData } = {}
local jars: { [Player]: { string } } = {}
local catching: { [Player]: { id: number, t: number } } = {}
local followers: { [Player]: Model } = {}

local function pushState(plr)
	local d = data[plr]
	if not d then return end
	StateEv:FireClient(plr, { jar = #jars[plr], jarKinds = jars[plr], saved = d.saved, equipped = d.equipped })
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		local total = 0
		for _, n in d.saved do total += n end
		ls.Saved.Value = total
	end
end

local function persist(plr)
	local d = data[plr]
	if not (store and d) then return false end
	local ok, err = pcall(function() store:SetAsync("u" .. plr.UserId, d) end)
	if not ok then warn("DataStore save failed:", err) end
	return ok
end

local function rootOf(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ спутник
local function setFollower(plr, kind)
	if followers[plr] then followers[plr]:Destroy() followers[plr] = nil end
	local build = kind and Spirits.Builders[kind]
	if not build then return end
	local m = build()
	Spirits.scale(m, kind == "GoldenCarp" and 0.3 or 0.45)
	m.Name = "Companion_" .. plr.Name
	m.Parent = workspace
	followers[plr] = m
end

------------------------------------------------------------------ духи
local spiritsFolder = Instance.new("Folder")
spiritsFolder.Name = "Spirits"
spiritsFolder.Parent = workspace

type Spirit = { id: number, kind: string, anchor: Part, model: Model?, revealed: boolean, path: { Vector3 }, t: number, pos: Vector3, dir: Vector3 }
local live: { [number]: Spirit } = {}
local nextId = 0
local moon = { active = false, endsAt = 0, cooldownUntil = 0, carp = nil :: Spirit?, oni = nil :: Model? }

local function foxPoint()
	local z = math.random(-48, 58)
	if math.abs(z) < 16 then z = 16 * (z < 0 and -1 or 1) end
	return Vector3.new(math.random(-14, 14), 0.6, z)
end

local function newSpirit(kind)
	nextId += 1
	local s: Spirit = { id = nextId, kind = kind, anchor = nil :: any, model = nil, revealed = false, path = { foxPoint(), foxPoint() }, t = 0,
		pos = Vector3.zero, dir = Vector3.new(0, 0, -1) }
	if kind == "GoldenCarp" then
		local a = Instance.new("Part")
		a.Name, a.Anchored, a.CanCollide, a.CanTouch, a.Transparency, a.Size = "Shadow", true, false, false, 1, Vector3.new(1, 1, 1)
		s.anchor = a
		s.revealed = true
		a:SetAttribute("Revealed", true)
		local m = Spirits.buildGoldenCarp()
		m:SetAttribute("SpiritId", s.id)
		m.Parent = spiritsFolder
		s.model = m
		local bill = Instance.new("BillboardGui")
		bill.Size, bill.StudsOffset, bill.AlwaysOnTop, bill.MaxDistance = UDim2.new(0, 200, 0, 36), Vector3.new(0, 7, 0), true, 400
		local t = Instance.new("TextLabel")
		t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
		t.Text, t.TextColor3, t.TextStrokeTransparency = "✦ Золотой карп ✦", Color3.fromRGB(255, 210, 90), 0.2
		t.Parent = bill
		bill.Parent = a
	else
		s.anchor = Spirits.buildShadow()
		s.pos = s.path[1]
	end
	s.anchor:SetAttribute("SpiritId", s.id)
	s.anchor:SetAttribute("Kind", kind)
	s.anchor:SetAttribute("CatchTime", CATCH_TIME[kind])
	s.anchor.Parent = spiritsFolder
	live[s.id] = s
	return s
end

local function foxCount()
	local n = 0
	for _, s in live do
		if s.kind == "PaperFox" then n += 1 end
	end
	return n
end

local function removeSpirit(s: Spirit)
	if live[s.id] ~= s then return end
	live[s.id] = nil
	s.anchor:Destroy()
	if s.model then s.model:Destroy() end
	if moon.carp == s then moon.carp = nil end
	if s.kind == "PaperFox" then
		task.delay(moon.active and math.random(2, 4) or math.random(4, 7), function()
			if foxCount() < MAX_FOXES + (moon.active and 2 or 0) then newSpirit("PaperFox") end
		end)
	end
end

for _ = 1, MAX_FOXES do newSpirit("PaperFox") end

------------------------------------------------------------------ Красная луна и они
local function tweenLight(red)
	local ti = TweenInfo.new(2)
	TweenService:Create(Lighting, ti, red and { Ambient = Color3.fromRGB(110, 50, 60), OutdoorAmbient = Color3.fromRGB(120, 55, 65) }
		or { Ambient = Color3.fromRGB(70, 70, 110), OutdoorAmbient = Color3.fromRGB(80, 80, 125) }):Play()
	TweenService:Create(cc, ti, red and { TintColor = Color3.fromRGB(255, 200, 200), Saturation = 0.1 } or { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	TweenService:Create(atm, ti, { Color = red and Color3.fromRGB(160, 60, 70) or Color3.fromRGB(80, 90, 150) }):Play()
	TweenService:Create(moonPart, ti, { Transparency = red and 0 or 1 }):Play()
end

local function hitPlayer(plr)
	local lost = #jars[plr]
	jars[plr] = {}
	catching[plr] = nil
	local c = plr.Character
	if c then c:PivotTo(SPAWN_CF + Vector3.new(0, 3, 0)) end
	HitEv:FireClient(plr, lost)
	pushState(plr)
end

local oniPos = Vector3.new(0, 0.5, -45)
local function oniLoop(oni: Model)
	local t0 = os.clock()
	local facing = Vector3.new(0, 0, 1)
	local swing = 0
	local function step(dt, speed)
		Spirits.animate(oni, CFrame.lookAt(oniPos, oniPos + facing), (os.clock() - t0) * 5 * speed / 10 + swing, 1)
	end
	while moon.active and oni.Parent do
		-- цель: ближайший игрок вне безопасной зоны алтаря (с уловом — в приоритете)
		local target, best = nil, math.huge
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r and (r.Position - ALTAR_POS).Magnitude > SAFE_RADIUS and r.Position.Z > -60 then
				local d = (r.Position - oniPos).Magnitude - (#(jars[plr] or {}) > 0 and 40 or 0)
				if d < best then target, best = r, d end
			end
		end
		if not target then
			-- бродит у моста
			local goal = Vector3.new(math.random(-12, 12), 0.5, math.random(-40, 30))
			for _ = 1, 40 do
				if not moon.active then break end
				local d = goal - oniPos
				if d.Magnitude < 1 then break end
				facing = d.Unit
				oniPos += facing * math.min(d.Magnitude, 0.4)
				step(0.05, 6)
				task.wait(0.05)
			end
		else
			-- подходит
			local tStart = os.clock()
			while moon.active and target.Parent and os.clock() - tStart < 3 do
				local d = Vector3.new(target.Position.X, 0.5, target.Position.Z) - oniPos
				if d.Magnitude < 10 then break end
				facing = d.Unit
				oniPos += facing * 0.55
				step(0.05, 11)
				task.wait(0.05)
			end
			if not (moon.active and target.Parent) then continue end
			-- метка удара на земле
			local center = Vector3.new(target.Position.X, target.Position.Y - 2.9, target.Position.Z)
			if (center - ALTAR_POS).Magnitude < SAFE_RADIUS then continue end
			facing = Vector3.new(center.X - oniPos.X, 0, center.Z - oniPos.Z)
			facing = facing.Magnitude > 0.1 and facing.Unit or Vector3.new(0, 0, 1)
			local ring = Instance.new("Part")
			ring.Shape, ring.Anchored, ring.CanCollide, ring.CanTouch = Enum.PartType.Cylinder, true, false, false
			ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 40, 40), 0.55
			ring.Size = Vector3.new(0.15, ONI_RADIUS * 2, ONI_RADIUS * 2)
			ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
			ring.Parent = workspace
			local fillDisc = ring:Clone()
			fillDisc.Transparency, fillDisc.Size, fillDisc.Color = 0.25, Vector3.new(0.2, 0.5, 0.5), Color3.fromRGB(255, 120, 60)
			fillDisc.Parent = workspace
			TweenService:Create(fillDisc, TweenInfo.new(ONI_WARN, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, ONI_RADIUS * 2, ONI_RADIUS * 2) }):Play()
			local w0 = os.clock()
			while os.clock() - w0 < ONI_WARN do
				swing = -math.pi / 2 -- замах
				step(0.05, 2)
				task.wait(0.05)
			end
			-- удар
			swing = math.pi / 2
			step(0, 0)
			for _, plr in Players:GetPlayers() do
				local r = rootOf(plr)
				if r then
					local d = r.Position - center
					if Vector3.new(d.X, 0, d.Z).Magnitude <= ONI_RADIUS and math.abs(d.Y) < 8 then hitPlayer(plr) end
				end
			end
			fillDisc:Destroy()
			ring.Color, ring.Transparency = Color3.fromRGB(255, 220, 180), 0.2
			TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.1, ONI_RADIUS * 2.6, ONI_RADIUS * 2.6) }):Play()
			task.delay(0.45, function() ring:Destroy() end)
			task.wait(1.2)
			swing = 0
		end
	end
end

local function endMoon()
	if not moon.active then return end
	moon.active = false
	moon.cooldownUntil = os.clock() + MOON_COOLDOWN
	tweenLight(false)
	if moon.oni then moon.oni:Destroy() moon.oni = nil end
	if moon.carp then removeSpirit(moon.carp) end
	MoonEv:FireAllClients(false)
end

local function startMoon()
	if moon.active or os.clock() < moon.cooldownUntil then return end
	moon.active = true
	moon.endsAt = os.clock() + MOON_TIME
	tweenLight(true)
	if FORCE_CARP or math.random() < CARP_CHANCE then
		moon.carp = newSpirit("GoldenCarp")
	end
	for _ = 1, 2 do newSpirit("PaperFox") end
	local oni = Spirits.buildOni()
	oni.Parent = workspace
	moon.oni = oni
	oniPos = Vector3.new(0, 0.5, -45)
	task.spawn(oniLoop, oni)
	MoonEv:FireAllClients(true, MOON_TIME)
	task.delay(MOON_TIME, function()
		if moon.active and os.clock() >= moon.endsAt - 0.1 then endMoon() end
	end)
end

------------------------------------------------------------------ движение и анимация
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for _, s in live do
		if s.kind == "GoldenCarp" then
			-- плывёт эллипсом над каналом, видно с моста и с улицы
			local a = now * 0.35
			s.pos = Vector3.new(math.cos(a) * 13, 4 + math.sin(now * 1.3) * 0.8, math.sin(a) * 6)
			s.dir = Vector3.new(-math.sin(a) * 13, 0, math.cos(a) * 6).Unit
		else
			local a, b = s.path[1], s.path[2]
			local speed = s.revealed and 3 or 6
			s.t += dt * speed / math.max((b - a).Magnitude, 1)
			if s.t >= 1 then
				s.path = { b, foxPoint() }
				s.t = 0
				a, b = s.path[1], s.path[2]
			end
			s.pos = a:Lerp(b, s.t)
			s.dir = (b - a).Magnitude > 0.1 and (b - a).Unit or s.dir
		end
		if s.kind == "GoldenCarp" then
			s.anchor.CFrame = CFrame.new(s.pos)
		else
			s.anchor.CFrame = CFrame.new(s.pos) * CFrame.Angles(0, 0, math.rad(90))
		end
		if s.model then
			local bob = s.kind == "PaperFox" and math.abs(math.sin(now * 6 + s.id)) * 0.5 or 0
			local base = s.kind == "PaperFox" and s.pos + Vector3.new(0, -0.1 + bob, 0) or s.pos
			Spirits.animate(s.model, CFrame.lookAt(base, base + s.dir), now * (s.kind == "PaperFox" and 9 or 3) + s.id)
		end
	end
	for plr, m in followers do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and m.Parent then
			local goal = root.CFrame * CFrame.new(3, 2.5 + math.sin(now * 2) * 0.4, 2)
			local cur = m:GetAttribute("Pivot") or goal
			cur = cur:Lerp(goal, 0.12)
			m:SetAttribute("Pivot", cur)
			Spirits.animate(m, cur, now * 6)
		end
	end
end)

------------------------------------------------------------------ проявление и ловля (проверки на сервере)
RevealEv.OnServerEvent:Connect(function(plr, id)
	local s = typeof(id) == "number" and live[id]
	local root = rootOf(plr)
	if not (s and root) or s.revealed then return end
	if (root.Position - s.pos).Magnitude > REVEAL_RANGE then return end
	s.revealed = true
	s.anchor.Transparency = 0.75
	s.anchor:SetAttribute("Revealed", true)
	local pe = s.anchor:FindFirstChildOfClass("ParticleEmitter")
	if pe then pe:Emit(30) pe.Rate = 4 end
	local m = Spirits.buildPaperFox()
	m:SetAttribute("SpiritId", s.id)
	m.Parent = spiritsFolder
	s.model = m
	task.delay(25, function()
		if live[s.id] == s then removeSpirit(s) end
	end)
end)

CatchStartEv.OnServerEvent:Connect(function(plr, id)
	if typeof(id) ~= "number" then catching[plr] = nil return end
	catching[plr] = { id = id, t = os.clock() }
end)

CatchFinishEv.OnServerEvent:Connect(function(plr, id)
	local c = catching[plr]
	catching[plr] = nil
	local s = typeof(id) == "number" and live[id]
	local root = rootOf(plr)
	if not (c and s and root and c.id == id and s.revealed and jars[plr]) then return end
	if os.clock() - c.t < CATCH_TIME[s.kind] - 0.2 then return end
	if (root.Position - s.pos).Magnitude > CATCH_RANGE + (s.kind == "GoldenCarp" and 4 or 0) then return end
	table.insert(jars[plr], s.kind)
	local at, kind = s.pos, s.kind
	removeSpirit(s)
	CaughtEv:FireClient(plr, kind, at)
	pushState(plr)
	-- первый улов запускает Красную луну
	if kind == "PaperFox" and not moon.active then
		task.delay(2, startMoon)
	end
end)

------------------------------------------------------------------ алтарь и экипировка
local function doSave(plr)
	local root = rootOf(plr)
	local d = data[plr]
	if not (root and d) then return { ok = false, msg = "Нет персонажа" } end
	if (root.Position - ALTAR_POS).Magnitude > ALTAR_RANGE + 4 then return { ok = false, msg = "Подойди к алтарю" } end
	local jar = jars[plr]
	if #jar == 0 then return { ok = false, msg = "Банка пуста" } end
	local firsts = {}
	for _, kind in jar do
		d.saved[kind] = (d.saved[kind] or 0) + 1
		if not d.firstSaved[kind] then
			d.firstSaved[kind] = true
			table.insert(firsts, kind)
		end
	end
	local kinds = table.clone(jar)
	jars[plr] = {}
	local persisted = persist(plr)
	pushState(plr)
	return { ok = true, count = #kinds, kinds = kinds, firsts = firsts, persisted = persisted }
end
savePrompt.Triggered:Connect(function(plr)
	StateEv:FireClient(plr, { saveResult = doSave(plr) })
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
	setFollower(plr, d.equipped)
	persist(plr)
	pushState(plr)
	return true
end

------------------------------------------------------------------ жизненный цикл игрока
Players.PlayerAdded:Connect(function(plr)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local v = Instance.new("IntValue")
	v.Name = "Saved"
	v.Parent = ls
	ls.Parent = plr

	local loaded = nil
	if store then
		local ok, res = pcall(function() return store:GetAsync("u" .. plr.UserId) end)
		if ok then loaded = res else warn("DataStore load failed:", res) end
	end
	data[plr] = {
		saved = (loaded and loaded.saved) or {},
		equipped = loaded and loaded.equipped,
		firstSaved = (loaded and loaded.firstSaved) or {},
	}
	jars[plr] = {}
	plr.CharacterAdded:Connect(function()
		task.wait(0.5)
		if data[plr] then setFollower(plr, data[plr].equipped) end
		pushState(plr)
	end)
	if plr.Character then setFollower(plr, data[plr].equipped) end
	pushState(plr)
	if moon.active then MoonEv:FireClient(plr, true, moon.endsAt - os.clock()) end
end)

Players.PlayerRemoving:Connect(function(plr)
	persist(plr)
	if followers[plr] then followers[plr]:Destroy() end
	data[plr], jars[plr], catching[plr], followers[plr] = nil, nil, nil, nil
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do persist(plr) end
end)
