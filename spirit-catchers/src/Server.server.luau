-- Spirit Catchers prototype: server (world, spawns, catching, saving, equip)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local DSS = game:GetService("DataStoreService")
local Models = require(RS:WaitForChild("Models"))

local CATCH_TIME, CATCH_RANGE, REVEAL_RANGE, ALTAR_RANGE = 1.4, 14, 40, 16
local MAX_SPIRITS = 5

---------------- World ----------------
Lighting.ClockTime = 0; Lighting.Brightness = 1
Lighting.Ambient = Color3.fromRGB(40, 45, 80); Lighting.OutdoorAmbient = Color3.fromRGB(50, 55, 95)
Lighting.FogColor = Color3.fromRGB(20, 22, 45); Lighting.FogEnd = 260
local map = Instance.new("Folder"); map.Name = "Map"; map.Parent = workspace
local function block(size, pos, color, mat, name)
	local p = Instance.new("Part"); p.Anchored = true; p.Size = size; p.Position = pos
	p.Color = color; p.Material = mat or Enum.Material.Slate; p.Name = name or "Block"; p.Parent = map
	return p
end
local function lamp(pos, color)
	local post = block(Vector3.new(0.6, 9, 0.6), pos + Vector3.new(0, 4.5, 0), Color3.fromRGB(40, 30, 30), Enum.Material.Wood)
	local bulb = block(Vector3.new(1.6, 2, 1.6), pos + Vector3.new(0, 9.5, 0), color, Enum.Material.Neon)
	local l = Instance.new("PointLight"); l.Range = 22; l.Brightness = 1.5; l.Color = color; l.Parent = bulb
	return post
end
-- canal across street with bridge
local water = block(Vector3.new(60, 1, 24), Vector3.new(0, -3, 20), Color3.fromRGB(30, 70, 120), Enum.Material.Glass, "Canal")
water.Transparency = 0.3; water.CanCollide = false
block(Vector3.new(60, 4, 24), Vector3.new(0, -6, 20), Color3.fromRGB(20, 30, 50), Enum.Material.Slate, "CanalBed")
-- street in two halves around the canal
block(Vector3.new(60, 1, 118), Vector3.new(0, -0.5, -71), Color3.fromRGB(70, 70, 80), Enum.Material.Cobblestone, "Street")
block(Vector3.new(60, 1, 118), Vector3.new(0, -0.5, 91), Color3.fromRGB(70, 70, 80), Enum.Material.Cobblestone, "Street")
block(Vector3.new(14, 1, 26), Vector3.new(0, 0.5, 20), Color3.fromRGB(120, 50, 40), Enum.Material.Wood, "Bridge")
for _, x in ipairs({-7, 7}) do block(Vector3.new(0.6, 2.5, 26), Vector3.new(x, 2, 20), Color3.fromRGB(170, 40, 35), Enum.Material.Wood, "Rail") end
-- houses with flat walkable roofs + truss to climb
local rng = Random.new(7)
for side = -1, 1, 2 do
	for z = -120, 120, 26 do
		if math.abs(z - 20) > 16 then
			local h = rng:NextInteger(12, 20)
			block(Vector3.new(16, h, 22), Vector3.new(side * 38, h / 2, z), Color3.fromRGB(rng:NextInteger(60, 90), 50, 55), Enum.Material.Brick, "House")
			block(Vector3.new(18, 1, 24), Vector3.new(side * 38, h + 0.5, z), Color3.fromRGB(35, 35, 50), Enum.Material.Slate, "Roof")
			local t = Instance.new("TrussPart"); t.Anchored = true; t.Size = Vector3.new(2, h + 2, 2)
			t.Position = Vector3.new(side * 29, (h + 2) / 2, z + 8); t.Color = Color3.fromRGB(90, 60, 40); t.Parent = map
			lamp(Vector3.new(side * 24, 0, z), Color3.fromRGB(255, 170, 90))
		end
	end
end
-- altar
local ALTAR_POS = Vector3.new(0, 0, -110)
block(Vector3.new(14, 1.5, 14), ALTAR_POS + Vector3.new(0, 0.75, 0), Color3.fromRGB(150, 140, 130), Enum.Material.Marble, "AltarBase")
local altar = block(Vector3.new(4, 4, 4), ALTAR_POS + Vector3.new(0, 3.5, 0), Color3.fromRGB(120, 230, 255), Enum.Material.Neon, "Altar")
local al = Instance.new("PointLight"); al.Range = 30; al.Brightness = 2; al.Color = altar.Color; al.Parent = altar
for _, x in ipairs({-6, 6}) do block(Vector3.new(1.4, 14, 1.4), ALTAR_POS + Vector3.new(x, 7, 8), Color3.fromRGB(190, 40, 35), Enum.Material.Wood, "Torii") end
block(Vector3.new(16, 1.4, 2), ALTAR_POS + Vector3.new(0, 14, 8), Color3.fromRGB(190, 40, 35), Enum.Material.Wood, "Torii")
local spawn = Instance.new("SpawnLocation"); spawn.Anchored = true; spawn.Size = Vector3.new(6, 1, 6)
spawn.Position = ALTAR_POS + Vector3.new(0, 0.6, 14); spawn.Transparency = 1; spawn.CanCollide = false; spawn.Neutral = true; spawn.Parent = map
local altarTag = Instance.new("ObjectValue"); altarTag.Name = "AltarRef"; altarTag.Value = altar; altarTag.Parent = RS

---------------- Remotes ----------------
local function remote(cls, name) local r = Instance.new(cls); r.Name = name; r.Parent = RS; return r end
local RevealEv = remote("RemoteEvent", "Reveal")
local CatchEv = remote("RemoteEvent", "Catch")        -- client->server: (id or nil)
local CaughtEv = remote("RemoteEvent", "Caught")      -- server->client: (kind, position)
local SaveFn = remote("RemoteFunction", "Save")
local EquipFn = remote("RemoteFunction", "Equip")
local StateEv = remote("RemoteEvent", "State")        -- server->client: {jar, collection, equipped}

---------------- Data ----------------
local store do local ok, s = pcall(function() return DSS:GetDataStore("SpiritCatchers_v1") end); store = ok and s or nil end
local data = {}   -- [player] = {collection = {fox=n}, equipped = kind?, jar = {kind,...}, catching = {id,t}}
local function push(p)
	local d = data[p]; if not d then return end
	StateEv:FireClient(p, { jar = d.jar, collection = d.collection, equipped = d.equipped, stored = d.stored })
end
local function persist(p)
	local d = data[p]; if not (d and store) then return false end
	local ok = pcall(function()
		store:SetAsync("u" .. p.UserId, { collection = d.collection, equipped = d.equipped })
	end)
	return ok
end

---------------- Followers (equipped spirit, replicated to everyone) ----------------
local followers = {}
local function setFollower(p, kind)
	if followers[p] then followers[p]:Destroy(); followers[p] = nil end
	if not kind or not p.Character then return end
	local m = Models.Build[kind](0.6); m.Name = "Pet_" .. p.Name
	m.PrimaryPart.Anchored = true; m.Parent = workspace
	followers[p] = m
end

Players.PlayerAdded:Connect(function(p)
	local saved
	if store then pcall(function() saved = store:GetAsync("u" .. p.UserId) end) end
	data[p] = { collection = (saved and saved.collection) or {}, equipped = saved and saved.equipped, jar = {}, stored = store ~= nil }
	p.CharacterAdded:Connect(function()
		task.wait(0.5); setFollower(p, data[p] and data[p].equipped); push(p)
	end)
	push(p)
end)
Players.PlayerRemoving:Connect(function(p)
	persist(p); setFollower(p, nil); data[p] = nil
end)
game:BindToClose(function() for _, p in ipairs(Players:GetPlayers()) do persist(p) end end)

---------------- Spirits ----------------
local spiritFolder = Instance.new("Folder"); spiritFolder.Name = "Spirits"; spiritFolder.Parent = workspace
local spirits, nextId = {}, 0
local function randomPoint()
	local z; repeat z = rng:NextNumber(-95, 120) until math.abs(z - 20) > 14
	return Vector3.new(rng:NextNumber(-20, 20), 0, z)
end
local function rollKind() return "fox" end  -- server-side rarity roll (only fox in this prototype)
local function spawnSpirit()
	nextId += 1
	local kind = rollKind()
	local holder = Instance.new("Model"); holder.Name = "Spirit" .. nextId
	holder:SetAttribute("Id", nextId); holder:SetAttribute("Kind", kind); holder:SetAttribute("Revealed", false)
	local shadow = Instance.new("Part"); shadow.Name = "Shadow"; shadow.Shape = Enum.PartType.Cylinder
	shadow.Size = Vector3.new(0.2, 5, 3.5); shadow.Color = Color3.fromRGB(5, 5, 15); shadow.Transparency = 0.25
	shadow.Material = Enum.Material.SmoothPlastic; shadow.Anchored = true; shadow.CanCollide = false; shadow.Parent = holder
	local body = Models.Build[kind](1); body.Name = "Body"; body.PrimaryPart.Anchored = true; body.Parent = holder
	for _, d in ipairs(body:GetDescendants()) do if d:IsA("BasePart") then d.Transparency = 1 end end
	holder.PrimaryPart = shadow; holder.Parent = spiritFolder
	local pos = randomPoint()
	spirits[nextId] = { model = holder, body = body, kind = kind, pos = pos, target = randomPoint(), revealedUntil = 0, phase = rng:NextNumber(0, 6) }
end
local function setVisible(s, on)
	if s.model:GetAttribute("Revealed") == on then return end
	s.model:SetAttribute("Revealed", on)
	for _, d in ipairs(s.body:GetDescendants()) do
		if d:IsA("BasePart") then d.Transparency = on and 0 or 1 end
	end
	s.model.Shadow.Transparency = on and 0.7 or 0.25
end
for _ = 1, MAX_SPIRITS do spawnSpirit() end

local function hrp(p) local c = p.Character; return c and c:FindFirstChild("HumanoidRootPart") end

RevealEv.OnServerEvent:Connect(function(p, id)
	local s, r = spirits[id], hrp(p)
	if not (s and r) then return end
	local off = s.pos - r.Position
	if off.Magnitude > REVEAL_RANGE then return end
	local flat = Vector3.new(off.X, 0, off.Z)
	if flat.Magnitude > 3 and r.CFrame.LookVector:Dot(flat.Unit) < 0.4 then return end -- must face it
	s.revealedUntil = os.clock() + 6
end)

CatchEv.OnServerEvent:Connect(function(p, id)
	local d = data[p]; if not d then return end
	if typeof(id) == "number" and spirits[id] then d.catching = { id = id, t = os.clock() } else d.catching = nil end
end)

SaveFn.OnServerInvoke = function(p)
	local d, r = data[p], hrp(p)
	if not (d and r) or (r.Position - altar.Position).Magnitude > ALTAR_RANGE then return { ok = false, msg = "Подойди к алтарю" } end
	if #d.jar == 0 then return { ok = false, msg = "Банка пуста" } end
	local newKinds = {}
	for _, kind in ipairs(d.jar) do
		if (d.collection[kind] or 0) == 0 then newKinds[kind] = true end
		d.collection[kind] = (d.collection[kind] or 0) + 1
	end
	local saved = d.jar; d.jar = {}
	local ok = persist(p)
	push(p)
	return { ok = true, saved = saved, first = newKinds, persisted = ok }
end

EquipFn.OnServerInvoke = function(p, kind)
	local d = data[p]; if not d then return false end
	if kind ~= nil and (typeof(kind) ~= "string" or (d.collection[kind] or 0) < 1) then return false end
	d.equipped = (d.equipped ~= kind) and kind or nil
	setFollower(p, d.equipped); persist(p); push(p)
	return true
end

local function respawnLater() task.delay(4, spawnSpirit) end

RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	for id, s in pairs(spirits) do
		-- wander
		local to = s.target - s.pos
		if to.Magnitude < 2 then s.target = randomPoint() else s.pos += to.Unit * math.min(to.Magnitude, 6 * dt) end
		local facing = CFrame.lookAt(s.pos, s.pos + Vector3.new(to.X, 0, to.Z + 1e-3))
		s.model.Shadow.CFrame = CFrame.new(s.pos + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90))
		local hop = math.abs(math.sin(now * 5 + s.phase)) * 0.8
		s.body:PivotTo(facing * CFrame.new(0, 2 + hop, 0) * CFrame.Angles(math.rad(math.sin(now * 5 + s.phase) * 6), 0, 0))
		setVisible(s, now < s.revealedUntil)
	end
	for p, d in pairs(data) do
		local c, r = d.catching, hrp(p)
		if c then
			local s = spirits[c.id]
			if not (s and r) or not s.model:GetAttribute("Revealed") or (s.pos - r.Position).Magnitude > CATCH_RANGE then
				d.catching = nil
			elseif now - c.t >= CATCH_TIME then
				d.catching = nil
				spirits[c.id] = nil
				table.insert(d.jar, s.kind)
				CaughtEv:FireClient(p, s.kind, s.body:GetPivot().Position)
				s.model:Destroy(); push(p); respawnLater()
			end
		end
	end
	for p, m in pairs(followers) do
		local r = hrp(p)
		if r and m.Parent then
			local t = now * 2
			m:PivotTo(r.CFrame * CFrame.new(3, 1.5 + math.sin(t * 2) * 0.4, 2) * CFrame.Angles(0, math.pi + math.sin(t) * 0.3, 0))
		end
	end
end)
