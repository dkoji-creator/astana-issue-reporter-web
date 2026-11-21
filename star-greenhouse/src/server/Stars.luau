-- Падающие звёзды: появляются по всей карте, светятся столбом света, их видно издалека.
-- Игрок подбегает и собирает (касание). Награду выдаёт Main через onCollect.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local G = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"))

local Stars = {}
local V3, CF = Vector3.new, CFrame.new

local function newStar(folder, pos, meteor)
	local m = Instance.new("Model")
	m.Name = meteor and "Meteor" or "Star"
	local col = meteor and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 232, 160)
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = meteor and V3(2.6, 2.6, 2.6) or V3(1.5, 1.5, 1.5)
	core.CFrame = CF(pos)
	core.Material = Enum.Material.Neon
	core.Color = col
	core.Anchored, core.CanCollide, core.CanQuery, core.CastShadow = true, false, false, false
	core.Parent = m
	-- зона подбора чуть больше самой звезды
	local hit = Instance.new("Part")
	hit.Name = "Hit"
	hit.Size = V3(6, 7, 6)
	hit.CFrame = CF(pos)
	hit.Transparency = 1
	hit.Anchored, hit.CanCollide, hit.CanQuery, hit.CastShadow = true, false, false, false
	hit.CanTouch = true
	hit.Parent = m
	-- столб света: виден с другого конца карты
	local pillar = Instance.new("Part")
	pillar.Name = "Pillar"
	pillar.Shape = Enum.PartType.Cylinder
	pillar.Size = V3(meteor and 60 or 36, 0.35, 0.35)
	pillar.CFrame = CF(pos + V3(0, (meteor and 60 or 36) / 2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	pillar.Material = Enum.Material.Neon
	pillar.Color = col
	pillar.Transparency = 0.6
	pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch, pillar.CastShadow = true, false, false, false, false
	pillar.Parent = m
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = col, meteor and 20 or 12, 1.2
	l.Parent = core
	m.PrimaryPart = core
	m:SetAttribute("Star", true)
	m:SetAttribute("Meteor", meteor == true)
	m:SetAttribute("Born", os.time())
	m.Parent = folder
	return m, hit
end

-- ctx: { parent, groundY(x,z), radiusMin, radiusMax, isMeteorEvent(), onCollect(plr, meteor, pos) }
function Stars.start(ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Stars"
	folder.Parent = ctx.parent
	local active = {}
	local rng = Random.new()

	local function spawnOne()
		local a = rng:NextNumber(0, math.pi * 2)
		local r = math.sqrt(rng:NextNumber(ctx.radiusMin ^ 2 / ctx.radiusMax ^ 2, 1)) * ctx.radiusMax
		local x, z = math.cos(a) * r, math.sin(a) * r
		local y = ctx.groundY(x, z) + 2
		local meteor = rng:NextNumber() < G.Stars.meteorChance * (ctx.isMeteorEvent() and 3 or 1)
		local m, hit = newStar(folder, V3(x, y, z), meteor)
		active[m] = true
		local taken = false
		hit.Touched:Connect(function(part)
			if taken then return end
			local plr = Players:GetPlayerFromCharacter(part.Parent)
			if not plr then return end
			taken = true
			active[m] = nil
			ctx.onCollect(plr, meteor, V3(x, y, z))
			m:Destroy()
		end)
	end

	task.spawn(function()
		while true do
			task.wait(G.Stars.every * (ctx.isMeteorEvent() and 0.35 or 1))
			local n = 0
			local now = os.time()
			for m in active do
				if not m.Parent or now - (m:GetAttribute("Born") or now) > G.Stars.life then
					active[m] = nil
					if m.Parent then m:Destroy() end
				else
					n += 1
				end
			end
			local cap = ctx.isMeteorEvent() and G.Stars.meteorMax or G.Stars.max
			if n < cap then spawnOne() end
		end
	end)
	-- сразу немного звёзд, чтобы карта не была пустой
	for _ = 1, 10 do spawnOne() end
	return folder
end

return Stars
