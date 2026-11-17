-- Квартал из трёх районов: улица бумажных фонарей (север), площадь алтаря,
-- канал с мостами и храмовый сад (юг, за воротами-тории).
local Map = {}

local WARM = Color3.fromRGB(255, 160, 80)
local COLD = Color3.fromRGB(110, 210, 255)
local TEAL = Color3.fromRGB(80, 230, 220)
local GARDEN = Color3.fromRGB(170, 255, 170)
local VIOLET = Color3.fromRGB(190, 130, 255)

local world
local function block(name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = mat or Enum.Material.Slate
	for k, v in props or {} do p[k] = v end
	p.Parent = world
	return p
end
local function deco(name, size, cf, color, mat, props)
	props = props or {}
	props.CanCollide = false
	props.CastShadow = false
	return block(name, size, cf, color, mat, props)
end
local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Parent = parent
	return l
end
local function wall(size, pos)
	block("Boundary", size, CFrame.new(pos), Color3.new(), nil, { Transparency = 1, CanQuery = false })
end
local function sign(parent, text, color, face)
	local g = Instance.new("SurfaceGui")
	g.Face = face or Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 20
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
	t.Text, t.TextColor3, t.TextStrokeTransparency = text, color, 0.3
	t.Parent = g
	g.Parent = parent
	return t
end
local function billboard(parent, text, color, offset)
	local b = Instance.new("BillboardGui")
	b.Size, b.StudsOffset, b.AlwaysOnTop, b.MaxDistance = UDim2.new(0, 190, 0, 34), offset or Vector3.new(0, 5, 0), true, 600
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBold
	t.Text, t.TextColor3, t.TextStrokeTransparency = text, color, 0.25
	t.Parent = b
	b.Parent = parent
end
local function sakura(pos, s)
	s = s or 1
	deco("Trunk", Vector3.new(1.2, 7, 1.2) * s, CFrame.new(pos + Vector3.new(0, 3.5 * s, 0)), Color3.fromRGB(90, 55, 45), Enum.Material.Wood, { CanCollide = true })
	for i, o in { Vector3.new(0, 8, 0), Vector3.new(2, 7, 1), Vector3.new(-2, 7.3, -1), Vector3.new(0.5, 7, -2) } do
		local c = deco("Blossom", Vector3.new(5, 4, 5) * s, CFrame.new(pos + o * s), Color3.fromRGB(255, 170 + i * 8, 210), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
		if i == 1 then light(c, Color3.fromRGB(255, 180, 220), 12, 0.6) end
	end
end
local function stoneLantern(pos, color)
	block("StoneLantern", Vector3.new(1.4, 2.4, 1.4), CFrame.new(pos + Vector3.new(0, 1.2, 0)), Color3.fromRGB(130, 130, 135), Enum.Material.Concrete)
	local f = deco("LanternFire", Vector3.new(1.2, 1, 1.2), CFrame.new(pos + Vector3.new(0, 2.9, 0)), color, Enum.Material.Neon)
	block("LanternRoof", Vector3.new(2.2, 0.5, 2.2), CFrame.new(pos + Vector3.new(0, 3.6, 0)), Color3.fromRGB(110, 110, 115), Enum.Material.Concrete)
	light(f, color, 16, 1.4)
end
local function torii(z, x, w, h, color)
	for _, sx in { -1, 1 } do
		block("ToriiPillar", Vector3.new(1.4, h, 1.4), CFrame.new(x + sx * w / 2, h / 2, z), color, Enum.Material.SmoothPlastic)
	end
	block("ToriiBeam", Vector3.new(w + 5, 1.2, 1.8), CFrame.new(x, h + 0.6, z), Color3.fromRGB(40, 30, 30))
	block("ToriiBeam2", Vector3.new(w + 2, 0.8, 1.2), CFrame.new(x, h - 2, z), color)
end

function Map.build()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace

	---------------------------------------------------------------- земля (дорога светлая, вода — яркая)
	block("StreetGround", Vector3.new(40, 1, 106), CFrame.new(0, 0, 83), Color3.fromRGB(115, 100, 92), Enum.Material.Cobblestone)
	block("StreetPath", Vector3.new(10, 0.1, 106), CFrame.new(0, 0.55, 83), Color3.fromRGB(165, 145, 120), Enum.Material.Cobblestone, { CanCollide = false })
	block("PlazaGround", Vector3.new(70, 1, 38), CFrame.new(0, 0, 11), Color3.fromRGB(135, 135, 150), Enum.Material.Slate)
	block("NorthBank", Vector3.new(124, 1, 12), CFrame.new(0, 0, -14), Color3.fromRGB(110, 115, 125), Enum.Material.Slate)
	block("SouthBank", Vector3.new(124, 1, 32), CFrame.new(0, 0, -56), Color3.fromRGB(110, 115, 125), Enum.Material.Slate)
	block("GardenGround", Vector3.new(92, 1, 80), CFrame.new(0, 0, -112), Color3.fromRGB(70, 125, 70), Enum.Material.Grass)
	block("GardenPath", Vector3.new(8, 0.1, 72), CFrame.new(0, 0.55, -112), Color3.fromRGB(175, 165, 140), Enum.Material.Pebble, { CanCollide = false })

	-- канал: вода, дно, стенки и светящаяся кромка, чтобы на телефоне было видно край
	block("Water", Vector3.new(124, 0.4, 20), CFrame.new(0, -2.5, -30), Color3.fromRGB(40, 120, 210), Enum.Material.Glass,
		{ Transparency = 0.25, Reflectance = 0.3, CanCollide = false, CanQuery = false })
	block("CanalBed", Vector3.new(124, 1, 20), CFrame.new(0, -8, -30), Color3.fromRGB(10, 20, 40))
	for _, z in { -19.6, -40.4 } do
		block("CanalWall", Vector3.new(124, 7, 0.8), CFrame.new(0, -4, z), Color3.fromRGB(70, 70, 80))
		deco("WaterEdge", Vector3.new(124, 0.12, 0.5), CFrame.new(0, 0.56, z + (z > -30 and -0.5 or 0.5)), TEAL, Enum.Material.Neon)
	end
	local refl = { WARM, Color3.fromRGB(255, 90, 150), TEAL, Color3.fromRGB(255, 210, 90), VIOLET }
	for i = 1, 22 do
		local x = -58 + (i - 1) * 5.5
		deco("Reflection", Vector3.new(0.9, 0.1, 3 + (i % 4) * 2.5), CFrame.new(x, -3.1, -30 + ((i * 7) % 13) - 6), refl[i % 5 + 1], Enum.Material.Neon, { Transparency = 0.3 })
	end

	---------------------------------------------------------------- границы
	wall(Vector3.new(1, 80, 144), Vector3.new(35.5, 40, 64)) -- улица+площадь
	wall(Vector3.new(1, 80, 144), Vector3.new(-35.5, 40, 64))
	wall(Vector3.new(80, 80, 1), Vector3.new(0, 40, 136.5))
	wall(Vector3.new(27, 80, 1), Vector3.new(49, 40, -8))
	wall(Vector3.new(27, 80, 1), Vector3.new(-49, 40, -8))
	wall(Vector3.new(1, 80, 64), Vector3.new(62.5, 40, -40))
	wall(Vector3.new(1, 80, 64), Vector3.new(-62.5, 40, -40))
	wall(Vector3.new(1, 80, 82), Vector3.new(46.5, 40, -112))
	wall(Vector3.new(1, 80, 82), Vector3.new(-46.5, 40, -112))
	wall(Vector3.new(96, 80, 1), Vector3.new(0, 40, -152.5))

	---------------------------------------------------------------- УЛИЦА БУМАЖНЫХ ФОНАРЕЙ (тёплый свет)
	for z = 42, 130, 22 do
		for _, side in { -1, 1 } do
			local h = 11 + ((z // 22) % 3) * 4
			block("House", Vector3.new(14, h, 18), CFrame.new(side * 27, h / 2, z), Color3.fromRGB(105, 80, 85), Enum.Material.Brick)
			block("Roof", Vector3.new(16, 1, 20), CFrame.new(side * 27, h + 0.5, z), Color3.fromRGB(130, 40, 45), Enum.Material.Slate)
			deco("Window", Vector3.new(0.3, 3, 5), CFrame.new(side * 19.9, 6, z), Color3.fromRGB(255, 200, 120), Enum.Material.Neon)
			deco("Noren", Vector3.new(0.2, 2.5, 4), CFrame.new(side * 19.8, 3, z + 5), Color3.fromRGB(60, 70, 160), Enum.Material.Fabric)
			block("Step", Vector3.new(4, h / 2, 4), CFrame.new(side * 18, h / 4, z + 7.5), Color3.fromRGB(110, 85, 60), Enum.Material.Wood)
		end
	end
	for z = 36, 128, 6 do
		for _, x in { -13, 13 } do
			local lantern = deco("PaperLantern", Vector3.new(1.6, 2, 1.6), CFrame.new(x, 9, z), Color3.fromRGB(255, 140, 70), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			if (z // 6) % 2 == 0 then light(lantern, WARM, 22, 1.5) end
		end
		deco("String", Vector3.new(26, 0.1, 0.1), CFrame.new(0, 9.9, z), Color3.fromRGB(40, 30, 30))
	end
	-- ориентир: Большой фонарь в конце улицы
	block("GreatLanternPole", Vector3.new(3, 28, 3), CFrame.new(0, 14, 128), Color3.fromRGB(120, 30, 30), Enum.Material.Wood)
	local great = deco("GreatLantern", Vector3.new(11, 13, 11), CFrame.new(0, 34, 128), Color3.fromRGB(255, 130, 60), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	light(great, WARM, 60, 3)
	billboard(great, "🏮 Улица фонарей", WARM, Vector3.new(0, 9, 0))

	---------------------------------------------------------------- ПЛОЩАДЬ И АЛТАРЬ (холодный свет, луч в небо)
	local altarPos = Vector3.new(0, 0.5, 12)
	local altar = block("Altar", Vector3.new(8, 3, 8), CFrame.new(altarPos + Vector3.new(0, 1.5, 0)), Color3.fromRGB(180, 195, 210), Enum.Material.Marble)
	block("AltarStep", Vector3.new(14, 0.6, 14), CFrame.new(altarPos + Vector3.new(0, 0.3, 0)), Color3.fromRGB(150, 160, 175), Enum.Material.Marble)
	local orb = deco("AltarGlow", Vector3.new(3, 3, 3), CFrame.new(altarPos + Vector3.new(0, 5.5, 0)), COLD, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	light(orb, COLD, 40, 3)
	deco("AltarBeam", Vector3.new(1.6, 220, 1.6), CFrame.new(altarPos + Vector3.new(0, 115, 0)), COLD, Enum.Material.Neon, { Transparency = 0.35 })
	for _, x in { -6, 6 } do
		local pillar = deco("AltarPillar", Vector3.new(1, 10, 1), CFrame.new(x, 5.5, altarPos.Z), COLD, Enum.Material.Neon, { Transparency = 0.2 })
		light(pillar, COLD, 18, 1.5)
	end
	billboard(orb, "⛩ Алтарь", COLD, Vector3.new(0, 4, 0))
	for _, p in { Vector3.new(-25, 0.5, 24), Vector3.new(25, 0.5, 24), Vector3.new(-25, 0.5, -2), Vector3.new(25, 0.5, -2) } do
		stoneLantern(p, COLD)
	end

	---------------------------------------------------------------- КАНАЛ С МОСТАМИ (бирюзовый свет)
	-- лунный мост — ориентир района (арка, по которой можно пройти)
	local z0, L, N, H = -43, 26, 10, 4
	for i = 1, N do
		local za, zb = z0 + (i - 1) * L / N, z0 + i * L / N
		local ya, yb = H * math.sin(math.pi * (za - z0) / L), H * math.sin(math.pi * (zb - z0) / L)
		local ang = math.atan2(yb - ya, zb - za)
		local len = math.sqrt((zb - za) ^ 2 + (yb - ya) ^ 2) + 0.4
		local cf = CFrame.new(0, (ya + yb) / 2, (za + zb) / 2) * CFrame.Angles(-ang, 0, 0)
		block("MoonBridge", Vector3.new(9, 1, len), cf, Color3.fromRGB(200, 50, 45), Enum.Material.Wood)
		for _, x in { -4.4, 4.4 } do
			block("MoonRail", Vector3.new(0.5, 2.4, len), cf * CFrame.new(x, 1.7, 0), Color3.fromRGB(230, 70, 55), Enum.Material.Wood)
		end
	end
	for _, z in { -44, -16 } do
		for _, x in { -5, 5 } do
			block("BridgePost", Vector3.new(1, 6, 1), CFrame.new(x, 3.5, z), Color3.fromRGB(200, 50, 45), Enum.Material.Wood)
			local l = deco("BridgeLamp", Vector3.new(1.4, 1.6, 1.4), CFrame.new(x, 7.2, z), WARM, Enum.Material.Neon)
			light(l, WARM, 18, 1.5)
		end
	end
	billboard(world:FindFirstChild("BridgePost"), "🌉 Лунный мост", TEAL, Vector3.new(5, 8, 0))
	for _, x in { -32, 32 } do
		block("Bridge", Vector3.new(8, 1, 24), CFrame.new(x, 0, -30), Color3.fromRGB(130, 100, 70), Enum.Material.WoodPlanks)
		for _, sx in { -3.8, 3.8 } do
			block("Rail", Vector3.new(0.4, 2, 24), CFrame.new(x + sx, 1.5, -30), Color3.fromRGB(90, 70, 50), Enum.Material.Wood)
		end
	end
	for x = -56, 56, 16 do
		for _, z in { -19, -41 } do
			block("LampPost", Vector3.new(0.6, 7, 0.6), CFrame.new(x, 3.5, z), Color3.fromRGB(40, 50, 60), Enum.Material.Metal)
			local l = deco("LampHead", Vector3.new(1.2, 1.2, 1.2), CFrame.new(x, 7.3, z), TEAL, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			light(l, TEAL, 20, 1.3)
		end
	end
	-- ивы у воды
	for _, p in { Vector3.new(-48, 0.5, -12), Vector3.new(46, 0.5, -12), Vector3.new(-45, 0.5, -50), Vector3.new(48, 0.5, -52) } do
		deco("WillowTrunk", Vector3.new(1.2, 8, 1.2), CFrame.new(p + Vector3.new(0, 4, 0)), Color3.fromRGB(70, 55, 45), Enum.Material.Wood, { CanCollide = true })
		deco("Willow", Vector3.new(7, 7, 7), CFrame.new(p + Vector3.new(0, 8.5, 0)), Color3.fromRGB(70, 140, 120), Enum.Material.Grass, { Shape = Enum.PartType.Ball, Transparency = 0.1 })
	end

	---------------------------------------------------------------- ХРАМОВЫЙ САД (зелёный и фиолетовый свет)
	torii(-72, 0, 14, 13, Color3.fromRGB(220, 60, 50))
	block("GardenFence", Vector3.new(54, 8, 1.5), CFrame.new(35, 4, -72), Color3.fromRGB(120, 110, 100), Enum.Material.Brick)
	block("GardenFence", Vector3.new(54, 8, 1.5), CFrame.new(-35, 4, -72), Color3.fromRGB(120, 110, 100), Enum.Material.Brick)
	local barrier = block("GardenBarrier", Vector3.new(14.2, 13, 1), CFrame.new(0, 6.5, -72), VIOLET, Enum.Material.ForceField,
		{ Transparency = 0.2, CanQuery = false })
	local barrierText = sign(barrier, "🔒 Храмовый сад\nСохрани 3 разных духа", Color3.new(1, 1, 1), Enum.NormalId.Back)
	sign(barrier, "Храмовый сад", Color3.new(1, 1, 1), Enum.NormalId.Front)
	-- пагода — ориентир сада
	for i = 0, 3 do
		local w = 16 - i * 3
		local y = 0.5 + i * 7
		block("Pagoda", Vector3.new(w - 4, 6, w - 4), CFrame.new(0, y + 3, -138), Color3.fromRGB(150, 50, 45), Enum.Material.Wood)
		block("PagodaRoof", Vector3.new(w + 2, 1, w + 2), CFrame.new(0, y + 6.5, -138), Color3.fromRGB(40, 70, 60), Enum.Material.Slate)
		local edge = deco("PagodaEdge", Vector3.new(w + 2.2, 0.25, w + 2.2), CFrame.new(0, y + 6, -138), VIOLET, Enum.Material.Neon)
		if i == 3 then light(edge, VIOLET, 50, 2.5) end
	end
	local spire = deco("PagodaSpire", Vector3.new(0.8, 8, 0.8), CFrame.new(0, 34, -138), Color3.fromRGB(230, 200, 90), Enum.Material.Neon)
	billboard(spire, "🏯 Храмовый сад", GARDEN, Vector3.new(0, 6, 0))
	for _, p in { Vector3.new(-25, 0.5, -90), Vector3.new(26, 0.5, -96), Vector3.new(-30, 0.5, -125), Vector3.new(30, 0.5, -130), Vector3.new(-12, 0.5, -108), Vector3.new(16, 0.5, -118) } do
		sakura(p, 1)
	end
	for z = -82, -128, -12 do
		for _, x in { -6, 6 } do
			stoneLantern(Vector3.new(x, 0.5, z), (z // 12) % 2 == 0 and GARDEN or VIOLET)
		end
	end
	block("Pond", Vector3.new(16, 0.3, 12), CFrame.new(-22, 0.4, -110), Color3.fromRGB(60, 140, 200), Enum.Material.Glass, { Transparency = 0.2, CanCollide = false })
	for i = 1, 5 do
		deco("LilyPad", Vector3.new(0.1, 1.6, 1.6), CFrame.new(-28 + i * 2.4, 0.6, -112 + (i % 2) * 3) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 170, 90), nil, { Shape = Enum.PartType.Cylinder })
	end
	local glowArea = deco("GardenFireflies", Vector3.new(80, 1, 70), CFrame.new(0, 4, -112), Color3.new(), nil, { Transparency = 1 })
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 255, 140))
	pe.LightEmission, pe.Rate, pe.Lifetime = 1, 18, NumberRange.new(3, 5)
	pe.Speed, pe.SpreadAngle = NumberRange.new(0.5, 1.5), Vector2.new(180, 180)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 0) })
	pe.Parent = glowArea

	---------------------------------------------------------------- точка появления
	local spawnCF = CFrame.new(0, 0.6, 24)
	local spawn = Instance.new("SpawnLocation")
	spawn.Size, spawn.CFrame, spawn.Anchored, spawn.Transparency, spawn.CanCollide = Vector3.new(6, 1, 6), spawnCF, true, 1, false
	spawn.Neutral, spawn.Duration = true, 0
	spawn.Parent = world

	-- красная луна (видна во время события)
	local moon = deco("RedMoon", Vector3.new(70, 70, 70), CFrame.new(0, 190, -300), Color3.fromRGB(255, 50, 40), Enum.Material.Neon,
		{ Shape = Enum.PartType.Ball, Transparency = 1 })

	return {
		altar = altar,
		altarPos = altarPos,
		spawnCF = spawnCF,
		barrier = barrier,
		barrierText = barrierText,
		moon = moon,
	}
end

return Map
