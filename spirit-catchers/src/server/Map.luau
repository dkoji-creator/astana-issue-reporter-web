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
	b.Size, b.StudsOffset, b.AlwaysOnTop, b.MaxDistance = UDim2.new(0, 170, 0, 30), offset or Vector3.new(0, 5, 0), false, 220
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
	light(f, color, 14, 0.8)
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
	block("StreetGround", Vector3.new(40, 1, 106), CFrame.new(0, 0, 83), Color3.fromRGB(66, 60, 62), Enum.Material.Cobblestone)
	block("StreetPath", Vector3.new(10, 0.1, 106), CFrame.new(0, 0.55, 83), Color3.fromRGB(96, 84, 76), Enum.Material.Cobblestone, { CanCollide = false })
	block("PlazaGround", Vector3.new(70, 1, 38), CFrame.new(0, 0, 11), Color3.fromRGB(82, 84, 96), Enum.Material.Slate)
	block("NorthBank", Vector3.new(124, 1, 12), CFrame.new(0, 0, -14), Color3.fromRGB(72, 76, 86), Enum.Material.Slate)
	block("SouthBank", Vector3.new(124, 1, 32), CFrame.new(0, 0, -56), Color3.fromRGB(72, 76, 86), Enum.Material.Slate)
	block("GardenGround", Vector3.new(92, 1, 80), CFrame.new(0, 0, -112), Color3.fromRGB(46, 92, 52), Enum.Material.Grass)
	block("GardenPath", Vector3.new(8, 0.1, 72), CFrame.new(0, 0.55, -112), Color3.fromRGB(175, 165, 140), Enum.Material.Pebble, { CanCollide = false })

	-- канал: вода, дно, стенки и светящаяся кромка, чтобы на телефоне было видно край
	block("Water", Vector3.new(124, 0.4, 20), CFrame.new(0, -2.5, -30), Color3.fromRGB(16, 38, 82), Enum.Material.Glass,
		{ Transparency = 0.15, Reflectance = 0.15, CanCollide = false, CanQuery = false })
	block("CanalBed", Vector3.new(124, 1, 20), CFrame.new(0, -8, -30), Color3.fromRGB(10, 20, 40))
	for _, z in { -19.6, -40.4 } do
		block("CanalWall", Vector3.new(124, 7, 0.8), CFrame.new(0, -4, z), Color3.fromRGB(70, 70, 80))
		deco("WaterEdge", Vector3.new(124, 0.12, 0.5), CFrame.new(0, 0.56, z + (z > -30 and -0.5 or 0.5)), TEAL, Enum.Material.Neon, { Transparency = 0.45 })
	end
	local refl = { WARM, Color3.fromRGB(255, 90, 150), TEAL, Color3.fromRGB(255, 210, 90), VIOLET }
	for i = 1, 22 do
		local x = -58 + (i - 1) * 5.5
		deco("Reflection", Vector3.new(0.9, 0.1, 3 + (i % 4) * 2.5), CFrame.new(x, -3.1, -30 + ((i * 7) % 13) - 6), refl[i % 5 + 1], Enum.Material.Neon, { Transparency = 0.3 })
	end

	---------------------------------------------------------------- границы
	for _, sx in { -1, 1 } do
		wall(Vector3.new(1, 80, 106), Vector3.new(sx * 35.5, 40, 83)) -- улица
		-- бока площади с проёмом z 4..16 под ворота рощи и рынка
		wall(Vector3.new(1, 80, 12), Vector3.new(sx * 35.5, 40, -2))
		wall(Vector3.new(1, 80, 14), Vector3.new(sx * 35.5, 40, 23))
		-- границы рощи (запад) и рынка (восток)
		wall(Vector3.new(1, 80, 82), Vector3.new(sx * 152.5, 40, 32))
		wall(Vector3.new(118, 80, 1), Vector3.new(sx * 94, 40, 72.5))
		wall(Vector3.new(91, 80, 1), Vector3.new(sx * 107.5, 40, -8.5))
	end
	wall(Vector3.new(80, 80, 1), Vector3.new(0, 40, 136.5))
	wall(Vector3.new(27, 80, 1), Vector3.new(49, 40, -8))
	wall(Vector3.new(27, 80, 1), Vector3.new(-49, 40, -8))
	wall(Vector3.new(1, 80, 64), Vector3.new(62.5, 40, -40))
	wall(Vector3.new(1, 80, 64), Vector3.new(-62.5, 40, -40))
	wall(Vector3.new(1, 80, 82), Vector3.new(46.5, 40, -112))
	wall(Vector3.new(1, 80, 82), Vector3.new(-46.5, 40, -112))
	wall(Vector3.new(96, 80, 1), Vector3.new(0, 40, -152.5))

	---------------------------------------------------------------- УЛИЦА БУМАЖНЫХ ФОНАРЕЙ (тёплый свет)
	-- деревянные дома: фасады из досок, тёмный каркас, двускатные крыши разной высоты
	local woods = { Color3.fromRGB(92, 62, 44), Color3.fromRGB(76, 52, 40), Color3.fromRGB(104, 72, 50) }
	for i, z in { 42, 64, 86, 108, 130 } do
		for _, side in { -1, 1 } do
			local h = 9 + ((i + (side > 0 and 1 or 0)) % 3) * 3.5
			local wood = woods[(i + (side > 0 and 1 or 0)) % 3 + 1]
			local cx, front = side * 27, side * 20
			block("House", Vector3.new(14, h, 18), CFrame.new(cx, h / 2, z), wood, Enum.Material.WoodPlanks)
			-- каркас фасада
			for _, dz in { -8.6, -3, 3, 8.6 } do
				deco("Beam", Vector3.new(0.5, h, 0.6), CFrame.new(front - side * 0.1, h / 2, z + dz), Color3.fromRGB(40, 28, 24), Enum.Material.Wood)
			end
			deco("Beam", Vector3.new(0.5, 0.5, 18), CFrame.new(front - side * 0.1, h * 0.55, z), Color3.fromRGB(40, 28, 24), Enum.Material.Wood)
			-- навес над входом
			block("Awning", Vector3.new(2.5, 0.3, 7), CFrame.new(front + side * 1.0, 4.4, z + 5) * CFrame.Angles(0, 0, math.rad(side * -12)), Color3.fromRGB(55, 45, 50), Enum.Material.Slate)
			-- тёплые окна (свет внутри, без лишнего блеска)
			deco("Window", Vector3.new(0.25, 2.2, 3.4), CFrame.new(front + side * 0.05, h * 0.55 + 2, z - 4.5), Color3.fromRGB(190, 115, 55), Enum.Material.Neon)
			deco("Shoji", Vector3.new(0.2, 2.2, 0.15), CFrame.new(front + side * 0.12, h * 0.55 + 2, z - 4.5), Color3.fromRGB(40, 28, 24))
			deco("Noren", Vector3.new(0.2, 2.2, 3.6), CFrame.new(front + side * 0.15, 3, z + 5), Color3.fromRGB(45, 60, 130), Enum.Material.Fabric)
			-- двускатная крыша из клиньев
			local rh = 3.5
			for _, rz in { -1, 1 } do
				local w = Instance.new("WedgePart")
				w.Name, w.Anchored, w.Material, w.Color = "Roof", true, Enum.Material.Slate, Color3.fromRGB(48, 44, 56)
				w.Size = Vector3.new(16, rh, 10.5)
				w.CFrame = CFrame.new(cx, h + rh / 2, z + rz * 5.25) * CFrame.Angles(0, rz > 0 and math.pi or 0, 0)
				w.Parent = world
			end
			deco("RoofRidge", Vector3.new(16.4, 0.5, 0.8), CFrame.new(cx, h + rh + 0.1, z), Color3.fromRGB(120, 35, 35), Enum.Material.Slate)
			block("Step", Vector3.new(4, h / 2, 4), CFrame.new(side * 18, h / 4, z + 7.5), Color3.fromRGB(80, 62, 46), Enum.Material.Wood)
		end
	end
	-- гирлянды бумажных фонарей: свет мягкий, источник света только в каждом третьем фонаре
	for z = 36, 128, 6 do
		for _, x in { -13, 13 } do
			local lantern = deco("PaperLantern", Vector3.new(1.3, 1.6, 1.3), CFrame.new(x, 9, z), Color3.fromRGB(215, 105, 50), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			if (z // 6) % 3 == 0 then light(lantern, WARM, 18, 0.7) end
		end
		deco("String", Vector3.new(26, 0.1, 0.1), CFrame.new(0, 9.9, z), Color3.fromRGB(40, 30, 30))
	end
	-- ориентир: Большой фонарь в конце улицы
	block("GreatLanternPole", Vector3.new(3, 28, 3), CFrame.new(0, 14, 128), Color3.fromRGB(120, 30, 30), Enum.Material.Wood)
	local great = deco("GreatLantern", Vector3.new(11, 13, 11), CFrame.new(0, 34, 128), Color3.fromRGB(215, 100, 45), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	light(great, WARM, 40, 1.4)
	billboard(great, "Улица фонарей", WARM, Vector3.new(0, 9, 0))

	---------------------------------------------------------------- ПЛОЩАДЬ И АЛТАРЬ (холодный свет, луч в небо)
	local altarPos = Vector3.new(0, 0.5, 12)
	local altar = block("Altar", Vector3.new(8, 3, 8), CFrame.new(altarPos + Vector3.new(0, 1.5, 0)), Color3.fromRGB(125, 130, 142), Enum.Material.Concrete, { Reflectance = 0 })
	block("AltarStep", Vector3.new(14, 0.6, 14), CFrame.new(altarPos + Vector3.new(0, 0.3, 0)), Color3.fromRGB(105, 110, 122), Enum.Material.Concrete)
	local orb = deco("AltarGlow", Vector3.new(3, 3, 3), CFrame.new(altarPos + Vector3.new(0, 5.5, 0)), COLD, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	light(orb, COLD, 26, 1.1)
	deco("AltarBeam", Vector3.new(1, 220, 1), CFrame.new(altarPos + Vector3.new(0, 115, 0)), COLD, Enum.Material.Neon, { Transparency = 0.6 })
	for _, x in { -6, 6 } do
		local pillar = deco("AltarPillar", Vector3.new(1, 10, 1), CFrame.new(x, 5.5, altarPos.Z), COLD, Enum.Material.Neon, { Transparency = 0.5 })
		light(pillar, COLD, 14, 0.5)
	end
	billboard(orb, "Алтарь", COLD, Vector3.new(0, 4, 0))
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
		block("MoonBridge", Vector3.new(9, 1, len), cf, Color3.fromRGB(140, 48, 42), Enum.Material.Wood, { Reflectance = 0 })
		for _, x in { -4.4, 4.4 } do
			block("MoonRail", Vector3.new(0.5, 2.4, len), cf * CFrame.new(x, 1.7, 0), Color3.fromRGB(160, 60, 50), Enum.Material.Wood, { Reflectance = 0 })
		end
	end
	for _, z in { -44, -16 } do
		for _, x in { -5, 5 } do
			block("BridgePost", Vector3.new(1, 6, 1), CFrame.new(x, 3.5, z), Color3.fromRGB(140, 48, 42), Enum.Material.Wood)
			local l = deco("BridgeLamp", Vector3.new(1.4, 1.6, 1.4), CFrame.new(x, 7.2, z), WARM, Enum.Material.Neon)
			light(l, WARM, 16, 0.8)
		end
	end
	billboard(world:FindFirstChild("BridgePost"), "Лунный мост", TEAL, Vector3.new(5, 8, 0))
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
			light(l, TEAL, 18, 0.7)
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
	local barrierText = sign(barrier, "ЗАКРЫТО: Храмовый сад\nСохрани 3 разных духа", Color3.new(1, 1, 1), Enum.NormalId.Back)
	sign(barrier, "Храмовый сад", Color3.new(1, 1, 1), Enum.NormalId.Front)
	-- пагода — ориентир сада
	for i = 0, 3 do
		local w = 16 - i * 3
		local y = 0.5 + i * 7
		block("Pagoda", Vector3.new(w - 4, 6, w - 4), CFrame.new(0, y + 3, -138), Color3.fromRGB(150, 50, 45), Enum.Material.Wood)
		block("PagodaRoof", Vector3.new(w + 2, 1, w + 2), CFrame.new(0, y + 6.5, -138), Color3.fromRGB(40, 70, 60), Enum.Material.Slate)
		local edge = deco("PagodaEdge", Vector3.new(w + 2.2, 0.25, w + 2.2), CFrame.new(0, y + 6, -138), VIOLET, Enum.Material.Neon)
		if i == 3 then light(edge, VIOLET, 40, 1.2) end
	end
	local spire = deco("PagodaSpire", Vector3.new(0.8, 8, 0.8), CFrame.new(0, 34, -138), Color3.fromRGB(230, 200, 90), Enum.Material.Neon)
	billboard(spire, "Храмовый сад", GARDEN, Vector3.new(0, 6, 0))
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

	---------------------------------------------------------------- БАМБУКОВАЯ РОЩА (запад, бирюзово-зелёный свет)
	local JADE = Color3.fromRGB(110, 240, 200)
	block("GroveGround", Vector3.new(117, 1, 80), CFrame.new(-94, 0, 32), Color3.fromRGB(52, 88, 60), Enum.Material.Grass)
	block("GrovePath", Vector3.new(104, 0.1, 7), CFrame.new(-88, 0.55, 10), Color3.fromRGB(110, 115, 100), Enum.Material.Slate, { CanCollide = false })
	block("GrovePond", Vector3.new(18, 0.3, 14), CFrame.new(-95, 0.4, 42), Color3.fromRGB(40, 110, 140), Enum.Material.Glass, { Transparency = 0.2, CanCollide = false })
	local rng = Random.new(11)
	for _ = 1, 90 do
		local x, z = rng:NextNumber(-148, -40), rng:NextNumber(-4, 68)
		local nearPath = math.abs(z - 10) < 6
		local nearPond = (Vector3.new(x, 0, z) - Vector3.new(-95, 0, 42)).Magnitude < 12
		if not nearPath and not nearPond then
			local h = rng:NextNumber(12, 22)
			local stalk = block("Bamboo", Vector3.new(h, 0.9, 0.9), CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80 + rng:NextInteger(0, 30), 150, 80), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
			stalk.CastShadow = false
			deco("BambooLeaves", Vector3.new(3, 1.2, 3), CFrame.new(x, h, z), Color3.fromRGB(70, 140, 80), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
		end
	end
	for x = -48, -140, -16 do
		stoneLantern(Vector3.new(x, 0.5, 4), JADE)
	end
	-- ориентир: лунные врата из камня
	for i = 0, 17 do
		local a = i / 18 * math.pi * 2
		block("MoonGate", Vector3.new(2, 2.4, 3), CFrame.new(-146, 9 + math.sin(a) * 8, 10 + math.cos(a) * 8) * CFrame.Angles(-a, 0, 0), Color3.fromRGB(150, 150, 155), Enum.Material.Concrete)
	end
	local groveMark = deco("GroveMark", Vector3.new(1, 1, 1), CFrame.new(-146, 19, 10), JADE, Enum.Material.Neon, { Transparency = 1 })
	billboard(groveMark, "Бамбуковая роща", JADE, Vector3.new(0, 2, 0))

	---------------------------------------------------------------- НОЧНОЙ РЫНОК (восток, розово-фиолетовый свет)
	local PINK = Color3.fromRGB(255, 120, 200)
	block("MarketGround", Vector3.new(117, 1, 80), CFrame.new(94, 0, 32), Color3.fromRGB(70, 58, 72), Enum.Material.Cobblestone)
	block("MarketPath", Vector3.new(104, 0.1, 9), CFrame.new(88, 0.55, 10), Color3.fromRGB(105, 90, 95), Enum.Material.Cobblestone, { CanCollide = false })
	local awnings = { Color3.fromRGB(220, 60, 80), Color3.fromRGB(70, 110, 210), Color3.fromRGB(240, 170, 50), Color3.fromRGB(150, 70, 200) }
	local n = 0
	for x = 52, 140, 16 do
		for _, z in { 30, 52 } do
			n += 1
			block("StallCounter", Vector3.new(8, 2.5, 3), CFrame.new(x, 1.75, z), Color3.fromRGB(110, 75, 50), Enum.Material.Wood)
			for _, px in { -3.8, 3.8 } do
				block("StallPost", Vector3.new(0.5, 7, 0.5), CFrame.new(x + px, 4, z - 1.6), Color3.fromRGB(80, 55, 40), Enum.Material.Wood)
			end
			block("Awning", Vector3.new(9, 0.4, 5), CFrame.new(x, 7.4, z - 1) * CFrame.Angles(math.rad(12), 0, 0), awnings[n % 4 + 1], Enum.Material.Fabric)
			local lamp = deco("StallLantern", Vector3.new(1.2, 1.5, 1.2), CFrame.new(x, 6, z - 3.4), n % 2 == 0 and PINK or Color3.fromRGB(255, 150, 70), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			if n % 2 == 0 then light(lamp, PINK, 16, 0.8) end
		end
	end
	for x = 44, 144, 8 do
		local l = deco("MarketGarland", Vector3.new(1, 1.2, 1), CFrame.new(x, 10, 10 + math.sin(x) * 0.5), x % 16 == 4 and PINK or Color3.fromRGB(180, 120, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
		if x % 24 == 4 then light(l, PINK, 18, 0.7) end
	end
	-- ориентир: башня с огромным розовым фонарём
	block("MarketTower", Vector3.new(3, 24, 3), CFrame.new(146, 12, 10), Color3.fromRGB(90, 40, 60), Enum.Material.Wood)
	local bigLamp = deco("MarketBigLantern", Vector3.new(8, 10, 8), CFrame.new(146, 28, 10), Color3.fromRGB(230, 90, 170), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	light(bigLamp, PINK, 40, 1.4)
	billboard(bigLamp, "Ночной рынок", PINK, Vector3.new(0, 7, 0))

	-- ворота в рощу и рынок (открываются по прогрессу игрока)
	local gates = {}
	for _, g in { { "GroveGate", -35.5, JADE, "Бамбуковая роща" }, { "MarketGate", 35.5, PINK, "Ночной рынок" } } do
		local barrier = block(g[1], Vector3.new(1, 13, 12), CFrame.new(g[2], 6.5, 10), g[3], Enum.Material.ForceField, { Transparency = 0.2, CanQuery = false })
		sign(barrier, g[4], Color3.new(1, 1, 1), Enum.NormalId.Right)
		sign(barrier, g[4], Color3.new(1, 1, 1), Enum.NormalId.Left)
		for _, z in { 3.5, 16.5 } do
			block("GatePost", Vector3.new(1.4, 14, 1.4), CFrame.new(g[2], 7, z), Color3.fromRGB(180, 50, 45), Enum.Material.Wood)
		end
		block("GateBeam", Vector3.new(1.8, 1.2, 16), CFrame.new(g[2], 14.4, 10), Color3.fromRGB(40, 30, 30), Enum.Material.Wood)
		gates[g[1]] = barrier
	end

	---------------------------------------------------------------- доска рекордов на площади
	local board = block("Leaderboard", Vector3.new(14, 9, 0.6), CFrame.new(-26, 6, 20) * CFrame.Angles(0, math.rad(-90), 0), Color3.fromRGB(40, 30, 45), Enum.Material.Wood)
	block("BoardPost", Vector3.new(0.8, 6, 0.8), CFrame.new(-26, 3, 14), Color3.fromRGB(80, 55, 40), Enum.Material.Wood)
	block("BoardPost", Vector3.new(0.8, 6, 0.8), CFrame.new(-26, 3, 26), Color3.fromRGB(80, 55, 40), Enum.Material.Wood)
	local boardGui = Instance.new("SurfaceGui")
	boardGui.Face = Enum.NormalId.Front
	boardGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	boardGui.PixelsPerStud = 30
	boardGui.Parent = board

	---------------------------------------------------------------- порталы на площади
	local portals = {}
	for _, p in { { -30, "grove", Color3.fromRGB(110, 240, 200) }, { -19, "garden", Color3.fromRGB(170, 255, 170) }, { 19, "canal", Color3.fromRGB(80, 230, 220) }, { 30, "market", Color3.fromRGB(255, 120, 200) } } do
		local x, col = p[1], p[3]
		for _, dx in { -3, 3 } do
			block("PortalPost", Vector3.new(1, 8, 1), CFrame.new(x + dx, 4.5, -4), Color3.fromRGB(60, 50, 70), Enum.Material.Slate)
		end
		block("PortalTop", Vector3.new(8, 1, 1.4), CFrame.new(x, 9, -4), Color3.fromRGB(60, 50, 70), Enum.Material.Slate)
		local swirl = deco("Portal", Vector3.new(0.3, 7, 5.2), CFrame.new(x, 4.6, -4) * CFrame.Angles(0, math.rad(90), 0), col, Enum.Material.Neon,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.35 })
		swirl:SetAttribute("District", p[2])
		local pe = Instance.new("ParticleEmitter")
		pe.Color, pe.LightEmission, pe.Rate = ColorSequence.new(col, Color3.new(1, 1, 1)), 1, 12
		pe.Lifetime, pe.Speed, pe.Size = NumberRange.new(0.8, 1.4), NumberRange.new(1, 2), NumberSequence.new(0.4, 0)
		pe.Parent = swirl
		light(swirl, col, 12, 0.8)
		table.insert(portals, swirl)
	end

	---------------------------------------------------------------- детали: бочки, ящики, лодки
	local props = Random.new(7)
	for _ = 1, 26 do
		local onMarket = props:NextNumber() < 0.4
		local x = onMarket and props:NextNumber(46, 146) or (props:NextInteger(0, 1) == 0 and props:NextNumber(-19, -16) or props:NextNumber(16, 19))
		local z = onMarket and (props:NextInteger(0, 1) == 0 and props:NextNumber(18, 24) or props:NextNumber(40, 46)) or props:NextNumber(36, 128)
		if props:NextNumber() < 0.5 then
			block("Barrel", Vector3.new(2.4, 1.8, 1.8), CFrame.new(x, 1.7, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 75, 45), Enum.Material.Wood, { Shape = Enum.PartType.Cylinder })
		else
			block("Crate", Vector3.new(2, 2, 2), CFrame.new(x, 1.5, z) * CFrame.Angles(0, props:NextNumber(0, 1), 0), Color3.fromRGB(140, 105, 65), Enum.Material.WoodPlanks)
		end
	end
	for _, b in { { -45, -26 }, { 46, -34 }, { -12, -36 } } do
		local hull = deco("Boat", Vector3.new(4, 1, 9), CFrame.new(b[1], -2.1, b[2]) * CFrame.Angles(0, 0.3, 0), Color3.fromRGB(120, 80, 50), Enum.Material.Wood)
		deco("BoatLamp", Vector3.new(0.8, 1, 0.8), hull.CFrame * CFrame.new(0, 1, 3.5), Color3.fromRGB(255, 160, 80), Enum.Material.Neon)
	end

	---------------------------------------------------------------- кусты-укрытия в саду и роще (за ними прячутся духи)
	local bush = Random.new(21)
	for _ = 1, 46 do
		local inGrove = bush:NextNumber() < 0.5
		local x = inGrove and bush:NextNumber(-146, -44) or bush:NextNumber(-40, 40)
		local z = inGrove and bush:NextNumber(-2, 66) or bush:NextNumber(-146, -78)
		if math.abs(z - 10) > 6 and math.abs(x) > 6 then
			local sz = bush:NextNumber(3, 5.5)
			deco("Bush", Vector3.new(sz, sz * 0.7, sz), CFrame.new(x, 0.5 + sz * 0.3, z), Color3.fromRGB(40 + bush:NextInteger(0, 20), 100 + bush:NextInteger(0, 30), 55), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
		end
	end
	for _, p in { Vector3.new(-120, 0.5, 50), Vector3.new(-70, 0.5, 58), Vector3.new(30, 0.5, -140), Vector3.new(-32, 0.5, -98) } do
		stoneLantern(p, Color3.fromRGB(150, 255, 200))
	end

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
		portals = portals,
		gates = gates,
		boardGui = boardGui,
		altar = altar,
		altarPos = altarPos,
		spawnCF = spawnCF,
		barrier = barrier,
		barrierText = barrierText,
		moon = moon,
	}
end

return Map
