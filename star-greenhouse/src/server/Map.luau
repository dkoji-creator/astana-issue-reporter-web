-- Мир «Звёздной оранжереи»: парящий астероид-станция, площадь с киосками, 8 стеклянных куполов с грядками, фон из планет.
-- Все координаты: платформа радиусом 100 с верхом на y = 0, центр в (0, 0, 0).
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Game"))
local PM = require(Shared:WaitForChild("PlantModels"))
local PlanetImg = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))
local SkyImg = require(Shared:WaitForChild("Config"):WaitForChild("Sky"))

local Map = {}
Map.PlotCount = 8
Map.PlotRadius = 58
Map.plots = {}
Map.RingBeds = { { r = 5.5, n = 6 }, { r = 10.5, n = 10 }, { r = 15.5, n = 14 } }
Map.MaxBeds = 30

local V3, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local PI, sin, cos = math.pi, math.sin, math.cos
local c = Color3.fromRGB
local Mat = Enum.Material

local COL = {
	hull = c(38, 44, 62), hull2 = c(58, 66, 90), dark = c(22, 26, 40), plate = c(84, 94, 120),
	cyan = c(70, 220, 255), mag = c(255, 90, 200), warm = c(255, 205, 140), gold = c(255, 200, 90), green = c(90, 235, 150),
	glass = c(150, 220, 255), soil = c(58, 40, 36),
}

local world, deco

local function part(parent, name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Material = mat or Mat.SmoothPlastic
	for k, v in props or {} do p[k] = v end
	p.Parent = parent
	return p
end
function deco(parent, name, size, cf, color, mat, props)
	props = props or {}
	props.CanCollide, props.CastShadow, props.CanTouch = false, false, false
	return part(parent, name, size, cf, color, mat, props)
end
local function ball(parent, name, pos, d, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	return deco(parent, name, V3(d, d, d), CF(pos), color, mat, props)
end
local function solidBall(parent, name, pos, d, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Ball
	return part(parent, name, V3(d, d, d), CF(pos), color, mat, props)
end
local function ell(parent, name, cf, size, color, mat, props)
	local p = part(parent, name, size, cf, color, mat, props)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end
-- цилиндр: ось вдоль локального Y
local function cyl(parent, name, cf, h, d, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	return part(parent, name, V3(h, d, d), cf * A(0, 0, PI / 2), color, mat, props)
end
local function dcyl(parent, name, cf, h, d, color, mat, props)
	props = props or {}
	props.CanCollide, props.CastShadow, props.CanTouch = false, false, false
	return cyl(parent, name, cf, h, d, color, mat, props)
end
local function seg(parent, name, a, b, d, color, mat, props)
	props = props or {}
	props.Shape = Enum.PartType.Cylinder
	props.CanCollide, props.CastShadow, props.CanTouch = false, false, false
	return part(parent, name, V3((b - a).Magnitude, d, d), CFrame.lookAt((a + b) / 2, b) * A(0, PI / 2, 0), color, mat, props)
end
-- кольцо из блоков вокруг центра (skip(angle) -> true пропускает сегмент)
local function ring(parent, name, center, radius, y, w, h, color, mat, n, skip, props)
	for i = 1, n do
		local a0, a1 = (i - 1) / n * PI * 2, i / n * PI * 2
		local am = (a0 + a1) / 2
		if not (skip and skip(am)) then
			local p0 = center + V3(cos(a0) * radius, y, sin(a0) * radius)
			local p1 = center + V3(cos(a1) * radius, y, sin(a1) * radius)
			local pr = props and table.clone(props) or {}
			pr.CanCollide, pr.CastShadow, pr.CanTouch = false, false, false
			part(parent, name, V3(w, h, (p1 - p0).Magnitude + 0.06), CFrame.lookAt((p0 + p1) / 2, p1), color, mat, pr)
		end
	end
end
local function light(parent, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = color, range, brightness
	l.Parent = parent
	return l
end
local function surfaceText(p, face, text, color, ppu)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppu or 40
	gui.LightInfluence = 0
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
	t.Text, t.TextColor3 = text, color
	t.Parent = gui
	return t
end
local function prompt(parent, text, objText, dist, name)
	local pr = Instance.new("ProximityPrompt")
	pr.Name = name or "Prompt"
	pr.ActionText, pr.ObjectText = text, objText or ""
	pr.MaxActivationDistance, pr.HoldDuration, pr.RequiresLineOfSight = dist or 10, 0, false
	pr.Parent = parent
	return pr
end

------------------------------------------------------------------ основание: платформа и скальный низ
local function buildHull()
	local f = Instance.new("Folder")
	f.Name = "Hull"
	f.Parent = world
	cyl(f, "Deck", CF(0, -1.5, 0), 3, 200, c(46, 52, 72), Mat.Slate)
	cyl(f, "DeckInner", CF(0, -0.05, 0), 0.2, 150, c(54, 62, 86), Mat.Metal, { Reflectance = 0.08 })
	cyl(f, "DeckEdge", CF(0, -2.2, 0), 1.5, 203, COL.hull2, Mat.Metal)
	dcyl(f, "RimGlow", CF(0, 0.06, 0), 0.12, 199, COL.cyan, Mat.Neon)
	dcyl(f, "RimCut", CF(0, 0.08, 0), 0.14, 197.6, c(46, 52, 72), Mat.Slate)
	-- скальный низ: стопка эллипсоидов
	local rock = { c(70, 64, 76), c(58, 54, 66), c(80, 72, 84), c(52, 48, 62) }
	local rng = Random.new(11)
	for i = 1, 9 do
		local k = 1 - i * 0.105
		ell(f, "Rock", CF(rng:NextNumber(-3, 3), -3.5 - i * 6.5, rng:NextNumber(-3, 3)) * A(0, i, 0), V3(190 * k, 16, 190 * k), rock[i % 4 + 1], Mat.Slate)
	end
	for i = 1, 26 do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(10, 82)
		local depth = 8 + (1 - r / 90) * 40
		local h = rng:NextNumber(9, 24)
		local col = i % 3 == 0 and COL.mag or (i % 3 == 1 and COL.cyan or c(160, 120, 255))
		ell(f, "Spike", CF(cos(a) * r, -depth - h * 0.3, sin(a) * r) * A(PI, a, rng:NextNumber(-0.2, 0.2)), V3(rng:NextNumber(2.5, 5), h, rng:NextNumber(2.5, 5)), col, Mat.Glass, { Transparency = 0.15, CanCollide = false })
		if i % 4 == 0 then
			local g = ball(f, "SpikeGlow", V3(cos(a) * r, -depth - h * 0.5, sin(a) * r), 3, col, Mat.Neon, { Transparency = 0.5 })
			light(g, col, 22, 0.8)
		end
	end
	-- двигатели под платформой
	for i = 1, 5 do
		local a = i / 5 * PI * 2
		local pod = V3(cos(a) * 38, -9, sin(a) * 38)
		cyl(f, "Engine", CF(pod), 6, 6, COL.hull2, Mat.Metal, { CanCollide = false })
		local g = ball(f, "EngineGlow", pod + V3(0, -3.5, 0), 5, COL.cyan, Mat.Neon, { Transparency = 0.25 })
		light(g, COL.cyan, 28, 1.2)
	end
	-- невидимая стена по краю: игроки не падают в космос
	local wall = Instance.new("Folder")
	wall.Name = "Barrier"
	wall.Parent = world
	for i = 1, 40 do
		local a0, a1 = (i - 1) / 40 * PI * 2, i / 40 * PI * 2
		local p0, p1 = V3(cos(a0) * 98.5, 25, sin(a0) * 98.5), V3(cos(a1) * 98.5, 25, sin(a1) * 98.5)
		part(wall, "Wall", V3(2, 70, (p1 - p0).Magnitude + 0.1), CFrame.lookAt((p0 + p1) / 2, p1), COL.hull, Mat.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end
end

------------------------------------------------------------------ центральная площадь
local function kiosk(parent, name, cf, color, title)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	cyl(m, "Base", cf * CF(0, 0.45, 0), 0.9, 12, COL.hull2, Mat.Metal)
	dcyl(m, "BaseGlow", cf * CF(0, 0.92, 0), 0.1, 12.2, color, Mat.Neon)
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local p = cf * CF(cos(a) * 4.6, 4.2, sin(a) * 4.6)
		part(m, "Pillar", V3(0.7, 7.2, 0.7), p, COL.plate, Mat.Metal)
		dcyl(m, "PillarGlow", p * CF(0, 0, 0), 7.0, 0.2, color, Mat.Neon, { Transparency = 0.2 })
	end
	cyl(m, "Roof", cf * CF(0, 8.1, 0), 0.7, 12.5, COL.hull, Mat.Metal)
	dcyl(m, "RoofGlow", cf * CF(0, 7.7, 0), 0.15, 12.7, color, Mat.Neon)
	ell(m, "RoofDome", cf * CF(0, 8.6, 0), V3(9, 2.4, 9), COL.hull2, Mat.Metal)
	local signPart = part(m, "Sign", V3(11, 3.2, 0.5), cf * CF(0, 11.2, 0) * A(0, PI, 0), COL.dark, Mat.SmoothPlastic, { CanCollide = false })
	surfaceText(signPart, Enum.NormalId.Front, title, color, 36)
	surfaceText(signPart, Enum.NormalId.Back, title, color, 36)
	for _, s in { -1, 1 } do
		part(m, "SignPost", V3(0.5, 3.4, 0.5), cf * CF(s * 4.5, 9.7, 0), COL.plate, Mat.Metal, { CanCollide = false })
	end
	return m
end

local function buildHub()
	local f = Instance.new("Folder")
	f.Name = "Hub"
	f.Parent = world
	cyl(f, "Plaza", CF(0, 0.15, 0), 0.4, 46, c(30, 34, 52), Mat.Metal, { Reflectance = 0.15 })
	for i, r in { 7.5, 13, 18.5, 22 } do
		dcyl(f, "PlazaRing", CF(0, 0.38, 0), 0.06, r * 2, i % 2 == 0 and COL.mag or COL.cyan, Mat.Neon, { Transparency = 0.15 })
		dcyl(f, "PlazaRingCut", CF(0, 0.4, 0), 0.07, r * 2 - 0.5, c(30, 34, 52), Mat.Metal)
	end
	-- радиальные лучи света на плазе
	for i = 1, 16 do
		local a = i / 16 * PI * 2
		deco(f, "PlazaRay", V3(0.35, 0.05, 11), CFrame.lookAt(V3(cos(a) * 13, 0.42, sin(a) * 13), V3(cos(a) * 24, 0.42, sin(a) * 24)), COL.cyan, Mat.Neon, { Transparency = 0.35 })
	end
	-- маяк в центре: башня и вращающиеся кольца
	cyl(f, "BeaconBase", CF(0, 1.2, 0), 2.4, 9, COL.hull2, Mat.Metal)
	cyl(f, "BeaconBase2", CF(0, 2.6, 0), 0.8, 6.4, COL.plate, Mat.Metal)
	dcyl(f, "BeaconGlow", CF(0, 3.05, 0), 0.12, 6.6, COL.cyan, Mat.Neon)
	cyl(f, "BeaconTower", CF(0, 9, 0), 12, 2.2, COL.hull, Mat.Metal)
	cyl(f, "BeaconTower2", CF(0, 17, 0), 6, 1.4, COL.plate, Mat.Metal)
	for k = 1, 4 do
		dcyl(f, "BeaconStripe", CF(0, 5 + k * 2.4, 0), 0.5, 2.35, COL.cyan, Mat.Neon, { Transparency = 0.1 })
	end
	local crystal = Instance.new("Model")
	crystal.Name = "BeaconCrystal"
	crystal.Parent = f
	crystal:SetAttribute("Spin", 0.5)
	crystal:SetAttribute("Pivot", V3(0, 23, 0))
	ell(crystal, "Gem", CF(0, 23, 0) * A(0, 0.5, 0), V3(5, 9, 5), COL.cyan, Mat.Glass, { Transparency = 0.2, CanCollide = false, CastShadow = false })
	ell(crystal, "GemCore", CF(0, 23, 0), V3(2.2, 5, 2.2), c(255, 255, 255), Mat.Neon, { CanCollide = false, CastShadow = false })
	for i = 1, 4 do
		local a = i / 4 * PI * 2
		ell(crystal, "GemShard", CF(cos(a) * 3.2, 23 + sin(a * 2) * 1.2, sin(a) * 3.2) * A(0.5, a, 0.3), V3(1.2, 4, 1.2), COL.mag, Mat.Glass, { Transparency = 0.25, CanCollide = false, CastShadow = false })
	end
	crystal.PrimaryPart = crystal:FindFirstChild("Gem")
	local lightPart = ball(f, "BeaconLight", V3(0, 23, 0), 1, COL.cyan, Mat.Neon, { Transparency = 1 })
	light(lightPart, COL.cyan, 60, 1.6)
	for i, spec in { { 7, 0.9, COL.cyan, 14 }, { 10, -0.6, COL.mag, 19 }, { 13, 0.4, COL.cyan, 24 } } do
		local sp = Instance.new("Model")
		sp.Name = "BeaconRing" .. i
		sp.Parent = f
		sp:SetAttribute("Spin", spec[2])
		sp:SetAttribute("Pivot", V3(0, spec[4], 0))
		local r, y = spec[1], spec[4]
		for k = 1, 28 do
			local a0, a1 = (k - 1) / 28 * PI * 2, k / 28 * PI * 2
			local p0, p1 = V3(cos(a0) * r, y, sin(a0) * r), V3(cos(a1) * r, y, sin(a1) * r)
			local s = part(sp, "RingSeg", V3(0.5, 0.5, (p1 - p0).Magnitude + 0.05), CFrame.lookAt((p0 + p1) / 2, p1), spec[3], Mat.Neon, { CanCollide = false, CastShadow = false, Transparency = 0.1 })
			if k == 1 then sp.PrimaryPart = s end
		end
		ball(sp, "RingOrb", V3(r, y, 0), 1.2, c(255, 255, 255), Mat.Neon)
	end

	-- киоски по сторонам света
	local kiosks = {
		{ id = "shop", ang = 0, col = COL.green, title = "СЕМЕНА", prompt = "Магазин семян" },
		{ id = "sell", ang = 90, col = COL.gold, title = "ПРОДАЖА", prompt = "Продать урожай" },
		{ id = "market", ang = 180, col = COL.mag, title = "РЫНОК", prompt = "Рынок и спрос" },
		{ id = "upgrades", ang = 270, col = COL.cyan, title = "МАСТЕРСКАЯ", prompt = "Улучшения станции" },
	}
	Map.kiosks = {}
	for _, k in kiosks do
		local a = math.rad(k.ang)
		local pos = V3(cos(a) * 15.5, 0.3, sin(a) * 15.5)
		local cf = CFrame.lookAt(pos, V3(0, 0.3, 0))
		local m = kiosk(f, "Kiosk_" .. k.id, cf, k.col, k.title)
		Map.kiosks[k.id] = m
		-- интерьер
		if k.id == "shop" then
			for s = -1, 1 do
				part(m, "Shelf", V3(0.6, 3.4, 4.2), cf * CF(s * 3.3, 2.8, 2.4) * A(0, s * 0.5, 0), COL.plate, Mat.Metal, { CanCollide = false })
			end
			for i = 1, 14 do
				local jar = ball(m, "Jar", (cf * CF(-3.6 + (i % 7) * 1.2, 1.8 + math.floor(i / 7) * 1.5, 3.2)).Position, 0.8, Game.PlanetColors[(i - 1) % 6 + 1], Mat.Neon, { Transparency = 0.1 })
				if i % 5 == 0 then light(jar, jar.Color, 8, 0.6) end
			end
		elseif k.id == "sell" then
			cyl(m, "Pad", cf * CF(0, 1.1, 1.0), 0.3, 6, COL.dark, Mat.Metal)
			dcyl(m, "PadRing", cf * CF(0, 1.3, 1.0), 0.06, 6, COL.gold, Mat.Neon)
			for i = 1, 3 do
				part(m, "Crate", V3(1.8, 1.6, 1.8), cf * CF(-3.5 + i * 0.4, 1.4 + (i - 1) * 1.6, 2.6) * A(0, i, 0), c(80, 90, 120), Mat.Metal, { CanCollide = false })
				dcyl(m, "CrateGlow", cf * CF(-3.5 + i * 0.4, 1.4 + (i - 1) * 1.6, 2.6) * A(0, i, 0), 1.7, 0.18, COL.gold, Mat.Neon)
			end
			ball(m, "Holo", (cf * CF(0, 5.5, 1.0)).Position, 2.4, COL.gold, Mat.Neon, { Transparency = 0.6 })
		elseif k.id == "market" then
			local scr = part(m, "Screen", V3(9, 5.2, 0.4), cf * CF(0, 4.2, 2.8), c(8, 10, 20), Mat.SmoothPlastic, { CanCollide = false })
			Map.boardLabel = surfaceText(scr, Enum.NormalId.Front, "Рынок загружается", COL.mag, 30)
			Map.boardLabel.TextScaled = false
			Map.boardLabel.TextSize = 22
			Map.boardLabel.RichText = true
			dcyl(m, "ScreenFrameT", cf * CF(0, 6.9, 2.8) * A(0, 0, PI / 2), 9.2, 0.25, COL.mag, Mat.Neon)
			dcyl(m, "ScreenFrameB", cf * CF(0, 1.5, 2.8) * A(0, 0, PI / 2), 9.2, 0.25, COL.mag, Mat.Neon)
		else
			part(m, "Desk", V3(6, 1.6, 2.2), cf * CF(0, 1.7, 2.4), COL.plate, Mat.Metal, { CanCollide = false })
			part(m, "Monitor", V3(4, 2.4, 0.3), cf * CF(0, 3.9, 3.1) * A(0.25, 0, 0), c(10, 14, 28), Mat.SmoothPlastic, { CanCollide = false })
			deco(m, "MonitorGlow", V3(3.6, 2.0, 0.1), cf * CF(0, 3.9, 2.9) * A(0.25, 0, 0), COL.cyan, Mat.Neon, { Transparency = 0.35 })
			local a1, a2, a3 = (cf * CF(-3.4, 1.6, 3.0)).Position, (cf * CF(-3.4, 4.8, 3.0)).Position, (cf * CF(-1.6, 6.0, 2.4)).Position
			seg(m, "ArmA", a1, a2, 0.5, COL.plate, Mat.Metal)
			seg(m, "ArmB", a2, a3, 0.4, COL.plate, Mat.Metal)
			ball(m, "ArmJoint", a2, 0.8, COL.cyan, Mat.Neon)
		end
		local trig = part(m, "PromptPart", V3(5, 3, 3), cf * CF(0, 2.2, 1.6), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local pr = prompt(trig, k.prompt, "", 12, "Open_" .. k.id)
		pr:SetAttribute("Window", k.id)
	end
end

------------------------------------------------------------------ участки игроков: купол, грядки, ворота
local function plotCF(i)
	local ang = (i - 1) / Map.PlotCount * PI * 2 + PI / Map.PlotCount
	local center = V3(cos(ang) * Map.PlotRadius, 0, sin(ang) * Map.PlotRadius)
	return CFrame.lookAt(center, V3(0, 0, 0)), ang
end
Map.plotCF = plotCF

function Map.bedLocalPos(index: number): Vector3
	local n = index
	for ri, rg in Map.RingBeds do
		if n <= rg.n then
			local a = -PI / 2 + (n - 0.5) / rg.n * PI * 2
			return V3(cos(a) * rg.r, 0, sin(a) * rg.r)
		end
		n -= rg.n
	end
	return V3()
end

local function buildPlot(i, parent)
	local cf, ang = plotCF(i)
	local pm = Instance.new("Model")
	pm.Name = "Plot" .. i
	pm.Parent = parent
	local plot = { cf = cf, model = pm, beds = {}, index = i, ang = ang }
	local function W(x, y, z) return cf:PointToWorldSpace(V3(x, y, z)) end
	local entrance = function(a) -- вход со стороны -Z локально (угол -pi/2 в локальных x,z)
		local d = (a - (-PI / 2)) % (PI * 2)
		return d < 0.36 or d > PI * 2 - 0.36
	end
	-- пол и подсветка
	cyl(pm, "Floor", cf * CF(0, 0.15, 0), 0.5, 39, c(30, 52, 60), Mat.Metal, { Reflectance = 0.1 })
	cyl(pm, "FloorInner", cf * CF(0, 0.42, 0), 0.08, 36, c(24, 40, 48), Mat.Slate)
	for _, r in { 8.2, 13.2, 17.8 } do
		dcyl(pm, "FloorRing", cf * CF(0, 0.47, 0), 0.05, r * 2, COL.cyan, Mat.Neon, { Transparency = 0.2 })
		dcyl(pm, "FloorRingCut", cf * CF(0, 0.48, 0), 0.06, r * 2 - 0.4, c(24, 40, 48), Mat.Slate)
	end
	dcyl(pm, "CenterDisk", cf * CF(0, 0.5, 0), 0.05, 6.2, c(18, 30, 36), Mat.Metal)
	-- бордюр по краю участка
	ring(pm, "Curb", V3(), 19.4, 0.55, 1.0, 1.1, COL.hull2, Mat.Metal, 36, entrance, nil)
	-- ring() считает от (0,0,0): перенесём бордюр в систему участка
	for _, p in pm:GetChildren() do
		if p.Name == "Curb" then
			local rel = p.CFrame
			p.CFrame = cf * rel
		end
	end
	-- купол: стекло и рёбра
	local glass = ball(pm, "Dome", W(0, 0, 0), 38, COL.glass, Mat.Glass, { Transparency = 0.93, Reflectance = 0.05 })
	glass.CanCollide = false
	local R = 18.8
	for k = 0, 3 do
		local az = k * PI / 4 + PI / 8
		local dx, dz = cos(az), sin(az)
		local prev
		for s = 0, 14 do
			local t = s / 14 * PI
			local x = cos(t) * R
			local p = W(dx * x, sin(t) * R, dz * x)
			if prev and not (entrance(math.atan2(dz * (cos(t)), dx * cos(t))) and sin(t) < 0.35) then
				seg(pm, "DomeRib", prev, p, 0.34, COL.hull2, Mat.Metal)
			end
			prev = p
		end
	end
	for _, lv in { { 0.38, 14 }, { 0.72, 18 }, { 0.93, 22 } } do
		local y = sin(lv[1] * PI / 2) * R * 0.98
		local rr = math.sqrt(R * R - y * y)
		for q = 1, lv[2] do
			local a0, a1 = (q - 1) / lv[2] * PI * 2, q / lv[2] * PI * 2
			if not (lv[1] < 0.5 and entrance((a0 + a1) / 2)) then
				seg(pm, "DomeRing", W(cos(a0) * rr, y, sin(a0) * rr), W(cos(a1) * rr, y, sin(a1) * rr), 0.28, COL.hull2, Mat.Metal)
			end
		end
	end
	ball(pm, "DomeTop", W(0, R + 0.4, 0), 1.6, COL.cyan, Mat.Neon)
	-- свет внутри купола
	local lamp = ball(pm, "DomeLight", W(0, 14, 0), 1, COL.warm, Mat.Neon, { Transparency = 1 })
	light(lamp, c(255, 235, 210), 40, 1.1)
	-- фонарные столбы по кругу
	for q = 1, 8 do
		local a = q / 8 * PI * 2 + PI / 8
		if not entrance(a) then
			local base = W(cos(a) * 17.6, 0.55, sin(a) * 17.6)
			seg(pm, "LampPole", base, base + V3(0, 4.6, 0), 0.22, COL.plate, Mat.Metal)
			local lb = ball(pm, "LampBulb", base + V3(0, 5, 0), 0.9, COL.warm, Mat.Neon)
			if q % 2 == 0 then light(lb, COL.warm, 15, 0.7) end
		end
	end
	-- ворота
	for _, s in { -1, 1 } do
		part(pm, "GatePillar", V3(1.4, 9, 1.4), cf * CF(s * 4.4, 4.5, -19.6), COL.hull2, Mat.Metal, { CanCollide = false })
		dcyl(pm, "GateGlow", cf * CF(s * 4.4, 4.5, -19.6), 8.8, 0.3, COL.cyan, Mat.Neon, { Transparency = 0.2 })
		ball(pm, "GateOrb", W(s * 4.4, 9.6, -19.6), 1.2, COL.cyan, Mat.Neon)
	end
	part(pm, "GateBeam", V3(10.6, 1.2, 1.2), cf * CF(0, 9.4, -19.6), COL.hull2, Mat.Metal, { CanCollide = false })
	local signP = part(pm, "Sign", V3(9, 2.6, 0.4), cf * CF(0, 11.4, -19.6) * A(0, PI, 0), COL.dark, Mat.SmoothPlastic, { CanCollide = false })
	plot.signFront = surfaceText(signP, Enum.NormalId.Front, "Свободный участок", COL.cyan, 40)
	plot.signBack = surfaceText(signP, Enum.NormalId.Back, "Свободный участок", COL.cyan, 40)
	plot.sign = signP
	-- грядки
	local beds = Instance.new("Folder")
	beds.Name = "Beds"
	beds.Parent = pm
	for bi = 1, Map.MaxBeds do
		local lp = Map.bedLocalPos(bi)
		local bcf = cf * CF(lp)
		local bed = Instance.new("Model")
		bed.Name = "Bed" .. bi
		bed.Parent = beds
		cyl(bed, "Rim", bcf * CF(0, 0.9, 0), 0.85, 4.7, COL.hull2, Mat.Metal)
		dcyl(bed, "RimGlow", bcf * CF(0, 1.34, 0), 0.06, 4.75, COL.cyan, Mat.Neon, { Transparency = 0.25 })
		local soil = cyl(bed, "Soil", bcf * CF(0, 1.3, 0), 0.12, 4.0, COL.soil, Mat.Ground, { CanCollide = false })
		-- мелкие камешки на почве
		for q = 1, 4 do
			local sa = q * 1.9 + bi
			ball(bed, "Pebble", (bcf * CF(cos(sa) * 1.5, 1.4, sin(sa) * 1.5)).Position, 0.22, c(95, 80, 74), Mat.Slate)
		end
		local cover = cyl(bed, "Cover", bcf * CF(0, 1.42, 0), 0.3, 4.2, c(20, 24, 34), Mat.Metal, { CanCollide = false })
		cover.Transparency = bi <= Game.StartBeds and 1 or 0
		local lockOrb = ball(bed, "LockOrb", (bcf * CF(0, 1.9, 0)).Position, 0.6, c(255, 90, 90), Mat.Neon, { Transparency = bi <= Game.StartBeds and 1 or 0.2 })
		soil:SetAttribute("Idx", bi)
		soil:SetAttribute("Plot", i)
		plot.beds[bi] = { soil = soil, cover = cover, lockOrb = lockOrb, model = bed, pos = (bcf * CF(0, 1.36, 0)).Position, cf = bcf * CF(0, 1.36, 0) }
	end
	-- точки появления игрока: перед воротами
	plot.entrance = cf * CF(0, 3, -24)
	plot.center = W(0, 0, 0)
	-- папка для украшений
	local d = Instance.new("Folder")
	d.Name = "Decor"
	d.Parent = pm
	plot.decor = d
	return plot
end

local function buildWalkways(parent)
	for i = 1, Map.PlotCount do
		local _, ang = plotCF(i)
		local dirv = V3(cos(ang), 0, sin(ang))
		local r0, r1 = 21.5, Map.PlotRadius - 19.4
		local len = r1 - r0
		local mid = dirv * ((r0 + r1) / 2)
		local wcf = CFrame.lookAt(V3(mid.X, 0.18, mid.Z), V3(mid.X, 0.18, mid.Z) - dirv)
		part(parent, "Walkway", V3(8, 0.5, len), wcf, c(36, 42, 62), Mat.Metal, { Reflectance = 0.1 })
		for _, s in { -1, 1 } do
			deco(parent, "WalkEdge", V3(0.25, 0.12, len), wcf * CF(s * 3.9, 0.3, 0), s == 1 and COL.cyan or COL.mag, Mat.Neon)
		end
		for q = 1, math.floor(len / 6) do
			deco(parent, "WalkDash", V3(0.5, 0.08, 2.4), wcf * CF(0, 0.28, -len / 2 + q * 6 - 3), COL.cyan, Mat.Neon, { Transparency = 0.3 })
		end
		for _, s in { -1, 1 } do
			for q = 1, math.floor(len / 8) do
				local pos = (wcf * CF(s * 4.4, 0, -len / 2 + q * 8 - 4)).Position
				seg(parent, "Pole", pos + V3(0, 0.4, 0), pos + V3(0, 4, 0), 0.2, COL.plate, Mat.Metal)
				local b = ball(parent, "Bulb", pos + V3(0, 4.3, 0), 0.8, s == 1 and COL.cyan or COL.mag, Mat.Neon)
				if q % 2 == 0 then light(b, b.Color, 14, 0.6) end
			end
		end
	end
end

------------------------------------------------------------------ украшения участка (покупаются за монеты)
local DECOR = {}
DECOR.bench = function(parent, cf)
	for _, sgn in { -1, 1 } do
		local base = cf * CF(sgn * 4, 0, 0)
		part(parent, "Seat", V3(3, 0.35, 1.1), base * CF(0, 1.3, 0), COL.plate, Mat.Metal, { CanCollide = false })
		part(parent, "Back", V3(3, 1.1, 0.25), base * CF(0, 2.0, 0.5) * A(-0.15, 0, 0), COL.plate, Mat.Metal, { CanCollide = false })
		deco(parent, "SeatGlow", V3(3.05, 0.07, 1.15), base * CF(0, 1.1, 0), COL.cyan, Mat.Neon)
		for _, lg in { -1.2, 1.2 } do part(parent, "Leg", V3(0.2, 1.1, 0.2), base * CF(lg, 0.7, 0), COL.hull, Mat.Metal, { CanCollide = false }) end
	end
end
DECOR.banner = function(parent, cf)
	for q = 1, 6 do
		local a = q / 6 * PI * 2 + 0.26
		local base = cf * CF(cos(a) * 18.6, 0, sin(a) * 18.6)
		if not (math.abs(sin(a) + 1) < 0.2) then
			local pos = base.Position
			seg(parent, "FlagPole", pos + V3(0, 0.5, 0), pos + V3(0, 7.5, 0), 0.22, COL.plate, Mat.Metal)
			local col = Game.PlanetColors[q]
			deco(parent, "Flag", V3(0.12, 2.2, 3), base * CF(0, 6.2, 1.7), col, Mat.Neon, { Transparency = 0.15 })
			ball(parent, "FlagTop", pos + V3(0, 7.7, 0), 0.5, col, Mat.Neon)
		end
	end
end
DECOR.lamps = function(parent, cf)
	for q = 1, 10 do
		local a = q / 10 * PI * 2
		local base = cf * CF(cos(a) * 8.4, 0, sin(a) * 8.4)
		local pos = base.Position
		seg(parent, "Stake", pos + V3(0, 0.5, 0), pos + V3(0, 2.2, 0), 0.14, COL.plate, Mat.Metal)
		local b = ball(parent, "StakeBulb", pos + V3(0, 2.5, 0), 0.7, Game.PlanetColors[q % 6 + 1], Mat.Neon)
		light(b, b.Color, 9, 0.5)
	end
end
DECOR.fountain = function(parent, cf)
	cyl(parent, "Basin", cf * CF(0, 0.9, 0), 0.7, 5.2, COL.hull2, Mat.Metal)
	cyl(parent, "Water", cf * CF(0, 1.2, 0), 0.15, 4.6, COL.cyan, Mat.Glass, { Transparency = 0.3, CanCollide = false })
	cyl(parent, "Pillar", cf * CF(0, 2.3, 0), 2.6, 0.7, COL.plate, Mat.Metal)
	local orbs = {}
	for q = 1, 12 do
		local a = q / 12 * PI * 2
		local h = 3.3 + (q % 3) * 0.9
		local o = ball(parent, "Drop", (cf * CF(cos(a) * (0.6 + (q % 3) * 0.5), h, sin(a) * (0.6 + (q % 3) * 0.5))).Position, 0.4 - (q % 3) * 0.06, COL.cyan, Mat.Neon, { Transparency = 0.2 })
		table.insert(orbs, o)
	end
	local top = ball(parent, "FountainTop", (cf * CF(0, 4.6, 0)).Position, 1.4, c(220, 250, 255), Mat.Neon)
	light(top, COL.cyan, 18, 0.9)
end
DECOR.telescope = function(parent, cf)
	cyl(parent, "TScopeBase", cf * CF(0, 0.7, 0), 0.4, 2.2, COL.hull2, Mat.Metal)
	cyl(parent, "TScopeStand", cf * CF(0, 1.6, 0), 1.6, 0.5, COL.plate, Mat.Metal)
	local tube = cyl(parent, "TScopeTube", cf * CF(0, 3.3, 0) * A(0.9, 0, 0), 4.0, 1.0, COL.hull, Mat.Metal)
	cyl(parent, "TScopeRing", cf * CF(0, 3.3, 0) * A(0.9, 0, 0) * CF(0, 1.4, 0), 0.25, 1.15, COL.cyan, Mat.Neon)
	ball(parent, "TScopeLens", (cf * CF(0, 3.3, 0) * A(0.9, 0, 0) * CF(0, 2.05, 0)).Position, 0.8, COL.cyan, Mat.Glass, { Transparency = 0.2 })
end
DECOR.globe = function(parent, cf)
	cyl(parent, "GlobeBase", cf * CF(0, 0.7, 0), 0.4, 2.8, COL.hull2, Mat.Metal)
	dcyl(parent, "GlobeBaseGlow", cf * CF(0, 0.92, 0), 0.06, 2.9, COL.cyan, Mat.Neon)
	local g = ball(parent, "Globe", (cf * CF(0, 3.2, 0)).Position, 3.2, COL.cyan, Mat.Neon, { Transparency = 0.45 })
	ball(parent, "GlobeCore", (cf * CF(0, 3.2, 0)).Position, 1.6, c(120, 255, 190), Mat.Neon, { Transparency = 0.15 })
	for q = 1, 3 do
		local sp = Instance.new("Model")
		sp.Name = "GlobeRing" .. q
		sp.Parent = parent
		sp:SetAttribute("Spin", 0.4 * q)
		for k = 1, 16 do
			local a0, a1 = (k - 1) / 16 * PI * 2, k / 16 * PI * 2
			local rr = 2.1
			local p0 = (cf * CF(0, 3.2, 0) * A(q * 0.9, 0, q * 0.5) * CF(cos(a0) * rr, 0, sin(a0) * rr)).Position
			local p1 = (cf * CF(0, 3.2, 0) * A(q * 0.9, 0, q * 0.5) * CF(cos(a1) * rr, 0, sin(a1) * rr)).Position
			local s = seg(sp, "GlobeSeg", p0, p1, 0.12, COL.mag, Mat.Neon)
			if k == 1 then sp.PrimaryPart = s end
		end
		sp:SetAttribute("Pivot", (cf * CF(0, 3.2, 0)).Position)
	end
	light(g, COL.cyan, 16, 0.9)
end
DECOR.rocket = function(parent, cf)
	cyl(parent, "Pad", cf * CF(0, 0.4, 0), 0.8, 12, COL.hull2, Mat.Metal)
	dcyl(parent, "PadRing", cf * CF(0, 0.82, 0), 0.06, 11, COL.gold, Mat.Neon)
	cyl(parent, "Body", cf * CF(0, 7.5, 0), 12, 4, c(235, 238, 248), Mat.Metal)
	ell(parent, "Nose", cf * CF(0, 14.5, 0), V3(4, 6, 4), c(235, 70, 80), Mat.Metal)
	for q = 1, 3 do
		local a = q / 3 * PI * 2
		local fin = cf * CF(cos(a) * 2.5, 2.8, sin(a) * 2.5) * A(0, -a, 0)
		ell(parent, "Fin", fin, V3(0.6, 4.5, 3), c(235, 70, 80), Mat.Metal)
	end
	for q = 1, 3 do
		ball(parent, "Window", (cf * CF(0, 6 + q * 2.6, -2.05)).Position, 1.1, COL.cyan, Mat.Neon)
	end
	local fl = ball(parent, "Flame", (cf * CF(0, 0.3, 0)).Position, 3, COL.warm, Mat.Neon, { Transparency = 0.4 })
	light(fl, COL.warm, 22, 1)
	dcyl(parent, "Stripe", cf * CF(0, 4.5, 0), 1.0, 4.05, c(235, 70, 80), Mat.Metal)
end
DECOR.starpond = function(parent, cf)
	cyl(parent, "PondRim", cf * CF(0, 0.5, 0), 1.0, 15, COL.hull2, Mat.Metal)
	cyl(parent, "PondFloor", cf * CF(0, 0.95, 0), 0.1, 13.4, c(8, 8, 28), Mat.Metal)
	local rng = Random.new(77)
	for q = 1, 40 do
		local a, r = rng:NextNumber(0, PI * 2), math.sqrt(rng:NextNumber()) * 6
		local col = ({ COL.cyan, COL.mag, c(255, 255, 255), c(160, 120, 255) })[q % 4 + 1]
		ball(parent, "PondStar", (cf * CF(cos(a) * r, 1.05, sin(a) * r)).Position, rng:NextNumber(0.2, 0.55), col, Mat.Neon)
	end
	ell(parent, "PondSwirl", cf * CF(0, 1.05, 0), V3(9, 0.15, 9), c(120, 60, 220), Mat.Neon, { Transparency = 0.55, CanCollide = false })
	local lb = ball(parent, "PondLight", (cf * CF(0, 2, 0)).Position, 1, COL.mag, Mat.Neon, { Transparency = 1 })
	light(lb, COL.mag, 26, 1)
end

local DECOR_ANCHOR = { -- локальные координаты участка
	bench = { CF(0, 0.55, 12.5) },
	banner = { CF() },
	lamps = { CF() },
	fountain = { CF(0, 0.5, 0) },
	telescope = { CF(14.2, 0.55, 8) * A(0, -0.8, 0) },
	globe = { CF(-14, 0.55, 8) },
	rocket = { CF(-9, 0, 30) },
	starpond = { CF(11, 0, 30) },
}
function Map.placeDecor(plotIdx: number, id: string)
	local plot = Map.plots[plotIdx]
	if not plot or plot.decor:FindFirstChild(id) then return end
	local m = Instance.new("Model")
	m.Name = id
	m.Parent = plot.decor
	local cf = plot.cf * DECOR_ANCHOR[id][1]
	DECOR[id](m, cf)
end
function Map.clearDecor(plotIdx: number)
	local plot = Map.plots[plotIdx]
	if plot then plot.decor:ClearAllChildren() end
end
function Map.setPlotSign(plotIdx: number, text: string, color)
	local plot = Map.plots[plotIdx]
	if not plot then return end
	plot.signFront.Text, plot.signBack.Text = text, text
	if color then plot.signFront.TextColor3, plot.signBack.TextColor3 = color, color end
end
function Map.setBedLocked(plotIdx: number, bedIdx: number, locked: boolean)
	local plot = Map.plots[plotIdx]
	local bed = plot and plot.beds[bedIdx]
	if not bed then return end
	bed.cover.Transparency = locked and 0 or 1
	bed.lockOrb.Transparency = locked and 0.2 or 1
end

------------------------------------------------------------------ окружение: оборудование, кристаллы, растения у кромки
local function buildScenery(parent)
	local rng = Random.new(2026)
	-- антенны и тарелки между участками
	for i = 1, Map.PlotCount do
		local a = (i - 1) / Map.PlotCount * PI * 2
		local base = V3(cos(a) * 84, 0, sin(a) * 84)
		if i % 2 == 1 then
			-- антенная мачта с огнями
			cyl(parent, "MastBase", CF(base + V3(0, 1, 0)), 2, 3.6, COL.hull2, Mat.Metal)
			local top = base + V3(0, 26, 0)
			seg(parent, "Mast", base + V3(0, 2, 0), top, 0.8, COL.plate, Mat.Metal)
			for q = 1, 4 do
				local h = 5 + q * 5
				seg(parent, "MastArm", base + V3(-2.2, h, 0), base + V3(2.2, h, 0), 0.22, COL.plate, Mat.Metal)
			end
			local b = ball(parent, "MastLight", top + V3(0, 1, 0), 1.2, c(255, 70, 70), Mat.Neon)
			light(b, c(255, 70, 70), 20, 0.8)
			b:SetAttribute("Blink", 1.2 + i * 0.1)
		else
			-- спутниковая тарелка
			cyl(parent, "DishBase", CF(base + V3(0, 1.2, 0)), 2.4, 3.2, COL.hull2, Mat.Metal)
			seg(parent, "DishArm", base + V3(0, 2, 0), base + V3(0, 7, 0), 0.9, COL.plate, Mat.Metal)
			local dcf = CF(base + V3(0, 8, 0)) * A(0, -a + PI, 0) * A(-0.7, 0, 0)
			ell(parent, "Dish", dcf, V3(12, 1.2, 12), c(205, 212, 232), Mat.Metal)
			seg(parent, "DishFeed", dcf.Position, (dcf * CF(0, 6, 0)).Position, 0.25, COL.plate, Mat.Metal)
			ball(parent, "DishTip", (dcf * CF(0, 6, 0)).Position, 0.8, COL.cyan, Mat.Neon)
		end
	end
	-- солнечные панели между мачтами
	for i = 1, 8 do
		local a = (i - 0.5) / 8 * PI * 2 + PI / 8
		local base = CF(cos(a) * 91, 0, sin(a) * 91) * A(0, -a, 0)
		for q = -1, 1 do
			local pcf = base * CF(q * 4.4, 2.3, 0) * A(0.5, 0, 0)
			part(parent, "Panel", V3(4, 0.25, 6), pcf, c(25, 60, 130), Mat.Glass, { CanCollide = false })
			for g = -1, 1 do deco(parent, "PanelLine", V3(0.08, 0.05, 6), pcf * CF(g * 1.3, 0.16, 0), c(150, 200, 255), Mat.Neon, { Transparency = 0.4 }) end
			seg(parent, "PanelLeg", (base * CF(q * 4.4, 0, 0)).Position, (base * CF(q * 4.4, 2.2, 0)).Position, 0.2, COL.plate, Mat.Metal)
		end
	end
	-- светящиеся кристаллы и грибы у кромки: берём модели растений
	local pool = { "moon_10", "mars_11", "europa_14", "io_14", "nebula_13", "core_15", "moon_04", "io_02", "nebula_02", "core_06", "europa_05", "mars_03" }
	for q = 1, 36 do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(88, 95)
		local id = pool[q % #pool + 1]
		local ok, m = pcall(PM.build, id, nil)
		if ok and m then
			local s = rng:NextNumber(1.2, 2.2)
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p.Name ~= "Root" then
					local pos = p.Position
					local rot = CF(pos):Inverse() * p.CFrame
					p.Size = p.Size * s
					p.CFrame = CF(pos * s) * rot
					p.CanCollide = false
				end
			end
			m:PivotTo(CF(cos(a) * r, 0, sin(a) * r) * A(0, rng:NextNumber(0, PI * 2), 0))
			m.Parent = parent
		end
	end
	-- камни
	for q = 1, 40 do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(24, 96)
		if not (r > 38 and r < 78 and false) then
			local sz = rng:NextNumber(1.2, 4)
			ell(parent, "Boulder", CF(cos(a) * r, sz * 0.2, sin(a) * r) * A(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0), V3(sz * 1.5, sz, sz * 1.3), c(70, 66, 82), Mat.Slate, { CanCollide = false })
		end
	end
	-- светящиеся ленты вдоль платформы
	for q = 1, 3 do
		local rr = 52 + q * 14
		for i = 1, 60 do
			local a = i / 60 * PI * 2
			if i % 2 == 0 then
				deco(parent, "Dash", V3(0.4, 0.05, 2.2), CFrame.lookAt(V3(cos(a) * rr, 0.12, sin(a) * rr), V3(cos(a + 0.05) * rr, 0.12, sin(a + 0.05) * rr)), q == 2 and COL.mag or COL.cyan, Mat.Neon, { Transparency = 0.45 })
			end
		end
	end
	-- светящиеся огни по краю платформы
	for i = 1, 40 do
		local a = i / 40 * PI * 2
		local pos = V3(cos(a) * 97, 0.4, sin(a) * 97)
		local b = ball(parent, "EdgeLamp", pos + V3(0, 1.2, 0), 1.1, i % 2 == 0 and COL.cyan or COL.mag, Mat.Neon)
		if i % 4 == 0 then light(b, b.Color, 16, 0.6) end
	end
end

------------------------------------------------------------------ фон: планеты, станция, астероиды
local function billboard(parent, name, image, pos, size)
	-- картинка планеты на невидимой плоскости, повёрнутой к центру станции (SurfaceGui не зависит от прозрачности детали)
	local p = part(parent, name, V3(size, size, 0.2), CFrame.lookAt(pos, V3(0, 0, 0)), c(255, 255, 255), Mat.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1024, 1024)
	gui.LightInfluence = 0
	gui.Parent = p
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = image
	img.Parent = gui
	return p
end

local function buildBackdrop(parent)
	billboard(parent, "GasGiant", PlanetImg.gas, V3(1500, 640, -2200), 3200)
	billboard(parent, "BlueWorld", PlanetImg.earth, V3(-2300, 380, -900), 1100)
	billboard(parent, "Moon", PlanetImg.moon, V3(1400, 520, 1900), 520)
	billboard(parent, "Moon2", PlanetImg.moon, V3(-1100, 650, 2300), 260)
	-- кольцевая станция
	local sc = CF(-650, 240, 900) * A(0.5, 0.4, 0.2)
	local segs = 44
	for i = 1, segs do
		local a0, a1 = (i - 1) / segs * PI * 2, i / segs * PI * 2
		local R = 190
		local p0, p1 = (sc * CF(cos(a0) * R, 0, sin(a0) * R)).Position, (sc * CF(cos(a1) * R, 0, sin(a1) * R)).Position
		local mid = (p0 + p1) / 2
		local look = CFrame.lookAt(mid, p1, (sc * CF(0, 1, 0)).Position - sc.Position)
		part(parent, "StationSeg", V3(26, 18, (p1 - p0).Magnitude + 0.5), look, i % 2 == 0 and c(150, 158, 178) or c(120, 128, 150), Mat.Metal, { CanCollide = false })
		if i % 2 == 0 then
			deco(parent, "StationWin", V3(26.5, 3, 7), look * CF(0, 2, 0), COL.warm, Mat.Neon, { Transparency = 0.1 })
		end
	end
	for k = 1, 4 do
		local a = k / 4 * PI * 2
		seg(parent, "StationSpoke", sc.Position, (sc * CF(cos(a) * 190, 0, sin(a) * 190)).Position, 5, c(130, 138, 160), Mat.Metal)
	end
	ball(parent, "StationHub", sc.Position, 46, c(170, 178, 198), Mat.Metal, { CanCollide = false })
	ball(parent, "StationHubGlow", sc.Position, 22, COL.cyan, Mat.Neon, { Transparency = 0.2 })
	-- астероиды вокруг
	local rng = Random.new(404)
	local fl = Instance.new("Folder")
	fl.Name = "Drift"
	fl.Parent = parent
	for i = 1, 44 do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(150, 520)
		local y = rng:NextNumber(-120, 160)
		local s = rng:NextNumber(5, 38)
		local col = ({ c(88, 80, 92), c(104, 92, 84), c(70, 74, 92), c(96, 84, 108) })[i % 4 + 1]
		local rock = Instance.new("Model")
		rock.Name = "Asteroid"
		rock.Parent = fl
		local main = ell(rock, "Main", CF(cos(a) * r, y, sin(a) * r) * A(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), V3(s * 1.4, s, s * 1.2), col, Mat.Slate, { CanCollide = false, CastShadow = false })
		for k = 1, 3 do
			ell(rock, "Lump", main.CFrame * CF(rng:NextNumber(-s, s) * 0.5, rng:NextNumber(-s, s) * 0.4, rng:NextNumber(-s, s) * 0.5), V3(s * 0.7, s * 0.6, s * 0.65), col:Lerp(c(120, 110, 120), 0.2), Mat.Slate, { CanCollide = false, CastShadow = false })
		end
		if i % 5 == 0 then
			local gc = i % 10 == 0 and COL.mag or COL.cyan
			local g = ell(rock, "Crystal", main.CFrame * CF(0, s * 0.5, 0) * A(0.3, 0, 0.3), V3(s * 0.25, s * 0.9, s * 0.25), gc, Mat.Glass, { Transparency = 0.1, CanCollide = false, CastShadow = false })
			light(g, gc, s * 3, 1)
		end
		rock.PrimaryPart = main
		rock:SetAttribute("Drift", rng:NextNumber(0.02, 0.08) * (i % 2 == 0 and 1 or -1))
	end
end

------------------------------------------------------------------ освещение и небо
local function buildLighting()
	for _, ch in Lighting:GetChildren() do
		if ch:IsA("Sky") or ch:IsA("BloomEffect") or ch:IsA("ColorCorrectionEffect") or ch:IsA("SunRaysEffect") or ch:IsA("Atmosphere") then ch:Destroy() end
	end
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 1.8
	Lighting.Ambient = c(70, 66, 110)
	Lighting.OutdoorAmbient = c(80, 78, 125)
	Lighting.ColorShift_Top = c(190, 170, 255)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0.1
	local sky = Instance.new("Sky")
	sky.SkyboxBk, sky.SkyboxDn, sky.SkyboxFt = SkyImg.Bk, SkyImg.Dn, SkyImg.Ft
	sky.SkyboxLf, sky.SkyboxRt, sky.SkyboxUp = SkyImg.Lf, SkyImg.Rt, SkyImg.Up
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.55, 28, 1.25
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast, cc.Saturation, cc.Brightness = 0.1, 0.18, 0
	cc.TintColor = c(245, 240, 255)
	cc.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity, rays.Spread = 0.06, 0.6
	rays.Parent = Lighting
end

function Map.build()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	workspace.Gravity = 120
	buildLighting()
	buildHull()
	buildHub()
	local plots = Instance.new("Folder")
	plots.Name = "Plots"
	plots.Parent = world
	for i = 1, Map.PlotCount do
		Map.plots[i] = buildPlot(i, plots)
	end
	local walk = Instance.new("Folder")
	walk.Name = "Walkways"
	walk.Parent = world
	buildWalkways(walk)
	local sc = Instance.new("Folder")
	sc.Name = "Scenery"
	sc.Parent = world
	buildScenery(sc)
	local bg = Instance.new("Folder")
	bg.Name = "Backdrop"
	bg.Parent = world
	buildBackdrop(bg)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size, spawn.CFrame, spawn.Anchored = V3(8, 1, 8), CF(0, 0.5, 30), true
	spawn.Transparency, spawn.CanCollide, spawn.Neutral = 1, false, true
	spawn.Parent = world
	Map.spawn = spawn
	return world
end

return Map
