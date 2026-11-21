-- Мир: пусковая площадка на холме и долина с пятью зонами (дальность растёт по оси +Z).
local Game = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Game"))
local Map = {}

local world
local function block(name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = mat or Enum.Material.SmoothPlastic
	for k, v in props or {} do p[k] = v end
	p.Parent = world
	return p
end
local function deco(name, size, cf, color, mat, props)
	props = props or {}
	props.CanCollide, props.CastShadow = false, false
	return block(name, size, cf, color, mat, props)
end
local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Parent = parent
	return l
end

function Map.build()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	local rng = Random.new(5)
	local WIDTH = 260

	---------------------------------------------------------------- пусковая площадка
	block("PadBase", Vector3.new(60, 4, 44), CFrame.new(0, -1, -4), Color3.fromRGB(210, 190, 160), Enum.Material.Cobblestone)
	block("PadTop", Vector3.new(40, 0.6, 28), CFrame.new(0, 1.3, -4), Color3.fromRGB(240, 225, 200), Enum.Material.Marble)
	-- каменный круг и руны
	deco("PadRing", Vector3.new(0.2, 24, 24), CFrame.new(0, 1.65, -4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 190, 110), Enum.Material.Neon,
		{ Shape = Enum.PartType.Cylinder, Transparency = 0.5 })
	deco("PadInner", Vector3.new(0.2, 17, 17), CFrame.new(0, 1.7, -4) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(245, 235, 215), Enum.Material.Marble,
		{ Shape = Enum.PartType.Cylinder })
	-- перила и столбы с фонариками
	for _, x in { -30, 30 } do
		block("Rail", Vector3.new(1, 3.5, 44), CFrame.new(x, 2, -4), Color3.fromRGB(150, 90, 70), Enum.Material.Wood)
	end
	block("RailBack", Vector3.new(60, 3.5, 1), CFrame.new(0, 2, -26), Color3.fromRGB(150, 90, 70), Enum.Material.Wood)
	for _, x in { -30, 30 } do
		for _, z in { -26, 18 } do
			block("Post", Vector3.new(1.6, 9, 1.6), CFrame.new(x, 4.5, z), Color3.fromRGB(190, 60, 55), Enum.Material.Wood)
			local l = deco("PostLamp", Vector3.new(2, 2.4, 2), CFrame.new(x, 10.2, z), Color3.fromRGB(255, 180, 90), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			light(l, Color3.fromRGB(255, 190, 120), 22, 0.8)
		end
	end
	-- большая тории-арка над стартом
	for _, x in { -12, 12 } do block("ToriiPillar", Vector3.new(2, 20, 2), CFrame.new(x, 11, 19), Color3.fromRGB(220, 60, 50), Enum.Material.SmoothPlastic) end
	block("ToriiBeam", Vector3.new(32, 2, 3), CFrame.new(0, 21.5, 19), Color3.fromRGB(40, 30, 30), Enum.Material.Wood)
	block("ToriiBeam2", Vector3.new(27, 1.4, 2), CFrame.new(0, 17.5, 19), Color3.fromRGB(220, 60, 50), Enum.Material.SmoothPlastic)
	-- гирлянда фонариков
	local cols = { Color3.fromRGB(230, 70, 60), Color3.fromRGB(255, 170, 70), Color3.fromRGB(255, 235, 200), Color3.fromRGB(240, 110, 160) }
	for x = -26, 26, 4 do
		local sag = 2 * (1 - (x / 26) ^ 2)
		deco("Garland", Vector3.new(1.3, 1.6, 1.3), CFrame.new(x, 13 - sag, 19), cols[(x // 4) % 4 + 1], Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	end
	-- табло дальности
	local board = block("Board", Vector3.new(16, 7, 0.6), CFrame.new(0, 6, -26.4), Color3.fromRGB(40, 30, 45), Enum.Material.Wood)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.Parent = board
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
	t.Text, t.TextColor3 = "ЗАПУСТИ ФОНАРИК\nчем дальше, тем реже дух", Color3.fromRGB(255, 215, 120)
	t.Parent = gui
	for _, s in { 1, -1 } do
		block("BoardPost", Vector3.new(1, 6, 1), CFrame.new(s * 6, 3, -26.4), Color3.fromRGB(100, 60, 40), Enum.Material.Wood)
	end

	---------------------------------------------------------------- долина: земля по зонам
	local zoneGround = {
		meadow = Enum.Material.Grass, forest = Enum.Material.Grass, lake = Enum.Material.Sand, peaks = Enum.Material.Rock, sky = Enum.Material.SmoothPlastic,
	}
	for _, z in Game.Zones do
		local len = z.to - z.from
		local mid = 20 + (z.from + z.to) / 2
		local ground = block("Ground_" .. z.id, Vector3.new(WIDTH, 2, len), CFrame.new(0, -2, mid), z.color:Lerp(Color3.new(0.2, 0.25, 0.2), 0.3), zoneGround[z.id])
		-- метка начала зоны: светящаяся арка поперёк долины
		local arch = deco("ZoneLine_" .. z.id, Vector3.new(WIDTH, 0.25, 2), CFrame.new(0, 0, 20 + z.from), z.color, Enum.Material.Neon, { Transparency = 0.35 })
		for _, side in { -1, 1 } do
			block("ZonePole", Vector3.new(2, 16, 2), CFrame.new(side * (WIDTH / 2 - 4), 8, 20 + z.from), z.color:Lerp(Color3.new(0, 0, 0), 0.4), Enum.Material.Wood)
			local l = deco("ZoneLamp", Vector3.new(3, 3, 3), CFrame.new(side * (WIDTH / 2 - 4), 17, 20 + z.from), z.color, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			light(l, z.color, 30, 1)
		end
		local sign = block("ZoneSign_" .. z.id, Vector3.new(34, 9, 1), CFrame.new(0, 24, 20 + z.from), Color3.fromRGB(35, 30, 50), Enum.Material.Wood)
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Back
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 24
		sg.Parent = sign
		local tl = Instance.new("TextLabel")
		tl.Size, tl.BackgroundTransparency, tl.TextScaled, tl.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
		tl.Text, tl.TextColor3 = ("%s\n%d м"):format(z.name, z.from), z.color
		tl.Parent = sg
		for _, side in { -1, 1 } do
			block("SignPost", Vector3.new(1.2, 20, 1.2), CFrame.new(side * 14, 10, 20 + z.from), Color3.fromRGB(70, 50, 40), Enum.Material.Wood)
		end
		_ = arch
		_ = ground
	end

	---------------------------------------------------------------- украшения зон
	-- луг: цветы и сакуры
	for _ = 1, 70 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 8, WIDTH / 2 - 8), rng:NextNumber(30, 165)
		deco("Flower", Vector3.new(1, 1, 1) * rng:NextNumber(0.8, 1.6), CFrame.new(x, -0.4, zz), ({ Color3.fromRGB(255, 120, 160), Color3.fromRGB(255, 225, 120), Color3.fromRGB(190, 150, 255) })[rng:NextInteger(1, 3)],
			Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	end
	for _ = 1, 10 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 15, WIDTH / 2 - 15), rng:NextNumber(40, 160)
		deco("Trunk", Vector3.new(2, 12, 2), CFrame.new(x, 5, zz), Color3.fromRGB(100, 65, 50), Enum.Material.Wood)
		deco("Blossom", Vector3.new(11, 8, 11), CFrame.new(x, 13, zz), Color3.fromRGB(255, 175, 215), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball })
	end
	-- лес: бамбук
	for _ = 1, 120 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 8, WIDTH / 2 - 8), rng:NextNumber(170, 360)
		local h = rng:NextNumber(18, 34)
		deco("Bamboo", Vector3.new(h, 1.4, 1.4), CFrame.new(x, h / 2 - 1, zz) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80 + rng:NextInteger(0, 30), 160, 90), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		deco("BambooLeaves", Vector3.new(6, 2, 6), CFrame.new(x, h - 1, zz), Color3.fromRGB(70, 150, 80), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
	end
	-- озеро: вода, кувшинки, фонарики на воде
	block("Water", Vector3.new(WIDTH - 20, 1, 240), CFrame.new(0, -0.4, 20 + 475), Color3.fromRGB(50, 120, 200), Enum.Material.Glass, { Transparency = 0.35, Reflectance = 0.2, CanCollide = false })
	for _ = 1, 50 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 20, WIDTH / 2 - 20), rng:NextNumber(380, 590)
		deco("LilyPad", Vector3.new(0.2, 4, 4), CFrame.new(x, 0.2, zz) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(70, 160, 95), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
		if rng:NextNumber() < 0.3 then
			local l = deco("WaterLantern", Vector3.new(1.4, 1.6, 1.4), CFrame.new(x + 2, 0.9, zz), Color3.fromRGB(255, 190, 110), Enum.Material.Neon, { Shape = Enum.PartType.Ball })
			light(l, Color3.fromRGB(255, 190, 110), 14, 0.6)
		end
	end
	-- горы: скалы и лунные кристаллы
	for _ = 1, 40 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 10, WIDTH / 2 - 10), rng:NextNumber(630, 900)
		local h = rng:NextNumber(14, 50)
		deco("Rock", Vector3.new(rng:NextNumber(10, 24), h, rng:NextNumber(10, 24)), CFrame.new(x, h / 2 - 2, zz) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), Color3.fromRGB(110 + rng:NextInteger(0, 30), 115 + rng:NextInteger(0, 30), 135), Enum.Material.Rock)
		if rng:NextNumber() < 0.5 then
			local c = deco("Crystal", Vector3.new(2, 8, 2), CFrame.new(x + 3, h + 3, zz) * CFrame.Angles(0.2, 0, 0.2), Color3.fromRGB(180, 210, 255), Enum.Material.Neon, { Transparency = 0.2 })
			light(c, Color3.fromRGB(180, 210, 255), 24, 0.9)
		end
	end
	-- небо: облака-острова
	for _ = 1, 70 do
		local x, zz = rng:NextNumber(-WIDTH / 2 + 10, WIDTH / 2 - 10), rng:NextNumber(930, 1320)
		local sz = rng:NextNumber(14, 34)
		deco("Cloud", Vector3.new(sz * 1.6, sz * 0.7, sz), CFrame.new(x, rng:NextNumber(-6, 10), zz), ({ Color3.fromRGB(255, 240, 245), Color3.fromRGB(255, 225, 215), Color3.fromRGB(240, 235, 255) })[rng:NextInteger(1, 3)],
			Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, Transparency = 0.1 })
	end

	---------------------------------------------------------------- границы
	local function wall(size, pos) block("Boundary", size, CFrame.new(pos), Color3.new(), nil, { Transparency = 1, CanQuery = false }) end
	wall(Vector3.new(2, 80, 70), Vector3.new(-32, 40, -6))
	wall(Vector3.new(2, 80, 70), Vector3.new(32, 40, -6))
	wall(Vector3.new(66, 80, 2), Vector3.new(0, 40, -28))
	wall(Vector3.new(66, 80, 2), Vector3.new(0, 40, 22))

	---------------------------------------------------------------- спавн на площадке
	local spawn = Instance.new("SpawnLocation")
	spawn.Size, spawn.CFrame, spawn.Anchored, spawn.Transparency, spawn.CanCollide = Vector3.new(6, 1, 6), CFrame.new(0, 2, -6) * CFrame.Angles(0, math.pi, 0), true, 1, false -- лицом к долине (+Z)
	spawn.Neutral, spawn.Duration = true, 0
	spawn.Parent = world

	return { launchPos = Vector3.new(0, 4, 10), zoneStart = 20 }
end

return Map
