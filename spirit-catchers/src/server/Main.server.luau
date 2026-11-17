-- Spirit Catchers: серверная логика прототипа (лис: найти → поймать → сохранить → экипировать).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Spirits = require(ReplicatedStorage.Shared.Spirits)

local REVEAL_RANGE, CATCH_RANGE, ALTAR_RANGE = 28, 14, 16
local CATCH_TIME = 1.5
local MAX_SPIRITS = 4

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
local SaveFn = remote("Save", "RemoteFunction")
local EquipFn = remote("Equip", "RemoteFunction")
local StateEv = remote("State") -- сервер → клиент: {jar, saved, equipped}
local CaughtEv = remote("Caught") -- сервер → клиент: эффект ловли

------------------------------------------------------------------ мир
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

block("Canal", Vector3.new(40, 0.5, 24), CFrame.new(0, -3, 0), Color3.fromRGB(20, 50, 90), Enum.Material.Glass,
	{ Transparency = 0.3, CanCollide = false })
-- улица разрезана каналом: две половины + мост
block("StreetN", Vector3.new(40, 1, 98), CFrame.new(0, 0, -61), Color3.fromRGB(45, 45, 55), Enum.Material.Cobblestone)
block("StreetS", Vector3.new(40, 1, 98), CFrame.new(0, 0, 61), Color3.fromRGB(45, 45, 55), Enum.Material.Cobblestone)
block("CanalBed", Vector3.new(40, 1, 24), CFrame.new(0, -6, 0), Color3.fromRGB(15, 25, 40))
block("Bridge", Vector3.new(12, 1, 26), CFrame.new(0, 0.6, 0), Color3.fromRGB(120, 40, 35), Enum.Material.Wood)
for _, x in { -6, 6 } do
	block("Rail", Vector3.new(0.5, 2, 26), CFrame.new(x, 1.8, 0), Color3.fromRGB(170, 50, 40), Enum.Material.Wood)
end
-- дома с плоскими крышами (на крыши можно запрыгнуть по ступеням)
for i = -4, 4 do
	if i ~= 0 then
		for _, side in { -1, 1 } do
			local h = 10 + (i % 3) * 4
			block("House", Vector3.new(14, h, 20), CFrame.new(side * 27, h / 2, i * 24), Color3.fromRGB(60, 50, 70), Enum.Material.Brick)
			block("Roof", Vector3.new(15, 1, 21), CFrame.new(side * 27, h + 0.5, i * 24), Color3.fromRGB(90, 30, 35), Enum.Material.Slate)
			block("Step", Vector3.new(4, h / 2, 4), CFrame.new(side * 18, h / 4, i * 24 + 8), Color3.fromRGB(80, 70, 60), Enum.Material.Wood)
			local lamp = block("Lantern", Vector3.new(1, 1.4, 1), CFrame.new(side * 19, 6, i * 24), Color3.fromRGB(255, 150, 70), Enum.Material.Neon,
				{ CanCollide = false })
			local l = Instance.new("PointLight")
			l.Range, l.Brightness, l.Color = 14, 0.8, Color3.fromRGB(255, 150, 80)
			l.Parent = lamp
		end
	end
end
-- алтарь в южном конце
local ALTAR_POS = Vector3.new(0, 1, 95)
local altar = block("Altar", Vector3.new(8, 3, 8), CFrame.new(ALTAR_POS + Vector3.new(0, 1, 0)), Color3.fromRGB(140, 140, 150), Enum.Material.Marble)
local altarGlow = block("AltarGlow", Vector3.new(3, 3, 3), CFrame.new(ALTAR_POS + Vector3.new(0, 5, 0)), Color3.fromRGB(120, 200, 255), Enum.Material.Neon,
	{ CanCollide = false, Shape = Enum.PartType.Ball })
local glow = Instance.new("PointLight")
glow.Range, glow.Brightness, glow.Color = 24, 2, Color3.fromRGB(120, 200, 255)
glow.Parent = altarGlow
local spawn = Instance.new("SpawnLocation")
spawn.Size, spawn.CFrame, spawn.Anchored, spawn.Transparency, spawn.CanCollide = Vector3.new(6, 1, 6), CFrame.new(0, 0.6, 84), true, 1, false
spawn.Neutral = true
spawn.Parent = world

local savePrompt = Instance.new("ProximityPrompt")
savePrompt.ActionText, savePrompt.ObjectText = "Сохранить улов", "Алтарь"
savePrompt.HoldDuration, savePrompt.MaxActivationDistance = 0.3, ALTAR_RANGE
savePrompt.RequiresLineOfSight = false
savePrompt.Parent = altar

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
	StateEv:FireClient(plr, { jar = #jars[plr], saved = d.saved, equipped = d.equipped })
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
	local ok, err = pcall(function()
		store:SetAsync("u" .. plr.UserId, d)
	end)
	if not ok then warn("DataStore save failed:", err) end
	return ok
end

------------------------------------------------------------------ спутник
local function setFollower(plr, kind)
	if followers[plr] then followers[plr]:Destroy() followers[plr] = nil end
	if kind ~= "PaperFox" then return end
	local m = Spirits.buildPaperFox()
	m.Name = "Companion_" .. plr.Name
	m:ScaleTo(0.6)
	m.Parent = workspace
	followers[plr] = m
end

RunService.Heartbeat:Connect(function()
	local t = os.clock()
	for plr, m in followers do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root and m.Parent then
			local target = root.CFrame * CFrame.new(2.5, 2 + math.sin(t * 2) * 0.4, 1.5)
			m:PivotTo(m:GetPivot():Lerp(target, 0.15))
		end
	end
end)

------------------------------------------------------------------ духи
local spiritsFolder = Instance.new("Folder")
spiritsFolder.Name = "Spirits"
spiritsFolder.Parent = workspace

type Spirit = { id: number, kind: string, shadow: Part, model: Model?, revealed: boolean, path: { Vector3 }, seg: number, t: number }
local live: { [number]: Spirit } = {}
local nextId = 0

local function randomStreetPoint()
	local z = math.random(-100, 80)
	if math.abs(z) < 14 then z = 14 * (z < 0 and -1 or 1) end
	return Vector3.new(math.random(-15, 15), 0.6, z)
end

local function spawnSpirit()
	nextId += 1
	local s: Spirit = { id = nextId, kind = "PaperFox", shadow = Spirits.buildShadow(), model = nil, revealed = false,
		path = { randomStreetPoint(), randomStreetPoint() }, seg = 1, t = 0 }
	-- шансы появления выбираются только на сервере
	s.shadow.CFrame = CFrame.new(s.path[1]) * CFrame.Angles(0, 0, math.rad(90))
	s.shadow:SetAttribute("SpiritId", s.id)
	s.shadow.Parent = spiritsFolder
	live[s.id] = s
end

local function despawn(s: Spirit)
	live[s.id] = nil
	s.shadow:Destroy()
	if s.model then s.model:Destroy() end
	task.delay(math.random(4, 8), spawnSpirit)
end

for _ = 1, MAX_SPIRITS do spawnSpirit() end

RunService.Heartbeat:Connect(function(dt)
	for _, s in live do
		local a, b = s.path[1], s.path[2]
		local speed = s.revealed and 2 or 5
		s.t += dt * speed / math.max((b - a).Magnitude, 1)
		if s.t >= 1 then
			s.path = { b, randomStreetPoint() }
			s.t = 0
			a, b = s.path[1], s.path[2]
		end
		local pos = a:Lerp(b, s.t)
		s.shadow.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
		if s.model then
			local bob = math.sin(os.clock() * 3 + s.id) * 0.3
			s.model:PivotTo(CFrame.lookAt(pos + Vector3.new(0, 1.5 + bob, 0), pos + (b - a).Unit + Vector3.new(0, 1.5 + bob, 0)))
		end
	end
end)

local function rootOf(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart")
end

RevealEv.OnServerEvent:Connect(function(plr, id)
	local s = typeof(id) == "number" and live[id]
	local root = rootOf(plr)
	if not (s and root) or s.revealed then return end
	if (root.Position - s.shadow.Position).Magnitude > REVEAL_RANGE then return end
	s.revealed = true
	s.shadow.Transparency = 0.7
	local m = Spirits.buildPaperFox()
	m:SetAttribute("SpiritId", s.id)
	m.Parent = spiritsFolder
	s.model = m
	s.shadow:SetAttribute("Revealed", true)
	-- проявленный дух исчезает, если его не поймали
	task.delay(20, function()
		if live[s.id] == s then despawn(s) end
	end)
end)

CatchStartEv.OnServerEvent:Connect(function(plr, id)
	if typeof(id) ~= "number" then catching[plr] = nil return end
	catching[plr] = { id = id, t = os.clock() }
end)

CatchFinishEv.OnServerEvent:Connect(function(plr, id)
	local c = catching[plr]
	catching[plr] = nil
	local s = live[id]
	local root = rootOf(plr)
	if not (c and s and root and c.id == id and s.revealed) then return end
	if os.clock() - c.t < CATCH_TIME - 0.15 then return end
	if (root.Position - s.shadow.Position).Magnitude > CATCH_RANGE then return end
	table.insert(jars[plr], s.kind)
	local at = s.shadow.Position
	despawn(s)
	CaughtEv:FireClient(plr, s.kind, at)
	pushState(plr)
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
	local count = #jar
	jars[plr] = {}
	local persisted = persist(plr)
	pushState(plr)
	return { ok = true, count = count, firsts = firsts, persisted = persisted }
end
SaveFn.OnServerInvoke = doSave
savePrompt.Triggered:Connect(function(plr)
	local r = doSave(plr)
	remotes.State:FireClient(plr, { saveResult = r })
end)

EquipFn.OnServerInvoke = function(plr, kind)
	local d = data[plr]
	if not d then return false end
	if kind == nil or d.equipped == kind then
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
		setFollower(plr, data[plr] and data[plr].equipped)
		pushState(plr)
	end)
	if plr.Character then setFollower(plr, data[plr].equipped) end
	pushState(plr)
end)

Players.PlayerRemoving:Connect(function(plr)
	persist(plr)
	if followers[plr] then followers[plr]:Destroy() end
	data[plr], jars[plr], catching[plr], followers[plr] = nil, nil, nil, nil
end)

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do persist(plr) end
end)
