-- Мир «Звёздной оранжереи»: шесть парящих планет-островов в одном космосе, видных друг с друга.
-- На каждой: площадь с ракетой и киосками, восемь мест под огороды игроков, своя флора.
-- Огород игрока строится на той планете, где он сейчас, и переезжает вместе с ним на ракете.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Game"))
local PM = require(Shared:WaitForChild("PlantModels"))
local PlanetImg = require(Shared:WaitForChild("Config"):WaitForChild("Planets"))
local SkyImg = require(Shared:WaitForChild("Config"):WaitForChild("Sky"))
local Icons = require(Shared:WaitForChild("Config"):WaitForChild("Icons"))
local WT = require(script.Parent:WaitForChild("WorldTerrain"))

local Map = {}
Map.SlotsPerPlanet = 8
Map.PlotRing = 130
Map.MaxBeds = 30
Map.BedCols, Map.BedStep = 6, 9.6
Map.planets = {}
Map.plots = {}
Map.boardLabels = {}
Map.leaderBoards = {}
Map.mysticStalls = {}

local V3, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local PI, sin, cos = math.pi, math.sin, math.cos
local c = Color3.fromRGB
local Mat = Enum.Material

local COL = {
	hull = c(38, 44, 62), hull2 = c(58, 66, 90), dark = c(22, 26, 40), plate = c(84, 94, 120),
	cyan = c(70, 175, 205), mag = c(190, 90, 165), warm = c(255, 196, 140), gold = c(225, 180, 100), green = c(90, 200, 140),
	trim = c(120, 140, 170), wood = c(124, 88, 62), wood2 = c(98, 68, 48), soil = c(64, 44, 36),
}
-- цвет камня площади на каждой планете
local PLAZA = { c(120, 118, 132), c(150, 90, 70), c(170, 200, 225), c(70, 62, 64), c(92, 80, 140), c(196, 168, 110) }

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

local function kiosk(parent, name, cf, color, title)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	cyl(m, "Base", cf * CF(0, 0.45, 0), 0.9, 12, COL.hull2, Mat.Metal)
	dcyl(m, "BaseGlow", cf * CF(0, 0.45, 0), 0.18, 12.15, color, Mat.Neon, { Transparency = 0.35 })
	for i = 0, 3 do
		local a = i * PI / 2 + PI / 4
		local p = cf * CF(cos(a) * 4.6, 4.2, sin(a) * 4.6)
		part(m, "Pillar", V3(0.7, 7.2, 0.7), p, COL.plate, Mat.Metal)
		dcyl(m, "PillarGlow", p * CF(0, 0, 0), 7.0, 0.2, color, Mat.Neon, { Transparency = 0.2 })
	end
	cyl(m, "Roof", cf * CF(0, 8.1, 0), 0.7, 12.5, COL.hull, Mat.Metal)
	dcyl(m, "RoofGlow", cf * CF(0, 8.1, 0), 0.18, 12.65, color, Mat.Neon, { Transparency = 0.35 })
	ell(m, "RoofDome", cf * CF(0, 8.6, 0), V3(9, 2.4, 9), COL.hull2, Mat.Metal)
	local signPart = part(m, "Sign", V3(11, 3.2, 0.5), cf * CF(0, 11.2, 0) * A(0, PI, 0), COL.dark, Mat.SmoothPlastic, { CanCollide = false })
	surfaceText(signPart, Enum.NormalId.Front, title, color, 36)
	surfaceText(signPart, Enum.NormalId.Back, title, color, 36)
	for _, s in { -1, 1 } do
		part(m, "SignPost", V3(0.5, 3.4, 0.5), cf * CF(s * 4.5, 9.7, 0), COL.plate, Mat.Metal, { CanCollide = false })
	end
	return m
end


------------------------------------------------------------------ настоящая высота рельефа (лучом), запасной вариант — расчёт
function Map.surfaceY(x, z, pi)
	local ctr = WT.Centers[pi]
	local terr = workspace:FindFirstChildOfClass("Terrain")
	local ok, res = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { terr }
		return workspace:Raycast(V3(x, ctr.Y + 120, z), V3(0, -240, 0), params)
	end)
	if ok and res then return res.Position.Y end
	return WT.groundY(x, z, pi)
end

------------------------------------------------------------------ места под огороды
local function slotCF(pi, j)
	local ctr = WT.Centers[pi]
	local ang = (j - 1) / Map.SlotsPerPlanet * PI * 2 + PI / Map.SlotsPerPlanet
	local pos = V3(ctr.X + cos(ang) * Map.PlotRing, ctr.Y, ctr.Z + sin(ang) * Map.PlotRing)
	return CFrame.lookAt(pos, V3(ctr.X, ctr.Y, ctr.Z)), ang
end
Map.slotCF = slotCF

function Map.bedLocalPos(index: number): Vector3
	local r = (index - 1) // Map.BedCols
	local k = (index - 1) % Map.BedCols
	return V3((k - (Map.BedCols - 1) / 2) * Map.BedStep, 0, -19.2 + r * Map.BedStep)
end

local function slotMarker(pi, j, parent)
	local cf = slotCF(pi, j)
	local m = Instance.new("Model")
	m.Name = ("Slot%d_%d"):format(pi, j)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			part(m, "Stake", V3(0.5, 1.6, 0.5), cf * CF(sx * 29, 0.8, sz * 24.5), COL.wood, Mat.Wood, { CanCollide = false })
		end
	end
	local board = part(m, "Board", V3(7, 2.2, 0.3), cf * CF(0, 2.4, -26) * A(0, PI, 0), COL.wood2, Mat.WoodPlanks, { CanCollide = false })
	surfaceText(board, Enum.NormalId.Front, "Свободный участок", c(230, 220, 200), 34)
	surfaceText(board, Enum.NormalId.Back, "Свободный участок", c(230, 220, 200), 34)
	part(m, "BoardPost", V3(0.35, 2.4, 0.35), cf * CF(0, 1.2, -26), COL.wood, Mat.Wood, { CanCollide = false })
	m.Parent = parent
	return m
end

-- галактическая грядка: тёмный металлический ящик с подсветкой цвета планеты
local function bedBox(parent, bcf, i, plotId, glow)
	local bed = Instance.new("Model")
	bed.Name = "Bed" .. i
	bed.Parent = parent
	local w = 7.6
	local frame = c(40, 44, 64)
	for _, sgn in { -1, 1 } do
		part(bed, "Plank", V3(w, 1.0, 0.5), bcf * CF(0, 0.5, sgn * (w / 2 - 0.25)), frame, Mat.Metal)
		part(bed, "Plank", V3(0.5, 1.0, w - 1), bcf * CF(sgn * (w / 2 - 0.25), 0.5, 0), frame, Mat.Metal)
		deco(bed, "Trim", V3(w + 0.04, 0.1, 0.54), bcf * CF(0, 1.02, sgn * (w / 2 - 0.25)), glow, Mat.Neon, { Transparency = 0.35 })
	end
	local soil = part(bed, "Soil", V3(w - 1, 0.4, w - 1), bcf * CF(0, 0.82, 0), c(52, 40, 56), Mat.Ground, { CanCollide = false })
	soil:SetAttribute("Idx", i)
	soil:SetAttribute("Plot", plotId)
	local cover = part(bed, "Cover", V3(w - 0.6, 0.25, w - 0.6), bcf * CF(0, 1.12, 0), c(26, 28, 40), Mat.Metal, { CanCollide = false })
	local lockOrb = ball(bed, "LockOrb", (bcf * CF(0, 1.7, 0)).Position, 0.6, c(255, 110, 100), Mat.Neon)
	return { soil = soil, cover = cover, lockOrb = lockOrb, model = bed, pos = (bcf * CF(0, 1.02, 0)).Position, cf = bcf * CF(0, 1.02, 0) }
end

-- кристаллический пилон со светом
local function pylon(parent, base, col, h)
	ell(parent, "PylonBase", CF(base + V3(0, 0.4, 0)), V3(2.2, 0.8, 2.2), c(30, 32, 46), Mat.Slate, { CanCollide = false })
	ell(parent, "Crystal", CF(base + V3(0, h * 0.5, 0)) * A(0.05, 0.4, 0.08), V3(0.9, h, 0.9), col, Mat.Glass, { Transparency = 0.25, CanCollide = false })
	ell(parent, "Crystal", CF(base + V3(0.55, h * 0.3, 0.2)) * A(0.2, 1, 0.35), V3(0.6, h * 0.55, 0.6), col, Mat.Glass, { Transparency = 0.25, CanCollide = false })
	ell(parent, "Crystal", CF(base + V3(-0.45, h * 0.25, -0.3)) * A(-0.3, 2, -0.3), V3(0.5, h * 0.45, 0.5), col, Mat.Glass, { Transparency = 0.25, CanCollide = false })
	local core = ell(parent, "CrystalCore", CF(base + V3(0, h * 0.5, 0)), V3(0.35, h * 0.8, 0.35), col:Lerp(Color3.new(1, 1, 1), 0.4), Mat.Neon, { CanCollide = false })
	light(core, col, 20, 1)
end

function Map.buildPlot(pi, j)
	local id = ("%d_%d"):format(pi, j)
	if Map.plots[id] then return Map.plots[id] end
	local cf, ang = slotCF(pi, j)
	-- выравниваем землю под огородом: уровень по медиане рельефа, холмы срезаются, ямы засыпаются
	local hs = {}
	for _, sx in { -28, 0, 28 } do
		for _, sz in { -24, 0, 24 } do
			local wp = cf:PointToWorldSpace(V3(sx, 0, sz))
			table.insert(hs, Map.surfaceY(wp.X, wp.Z, pi))
		end
	end
	table.sort(hs)
	local level = hs[5]
	local flat = CFrame.new(cf.X, level, cf.Z) * (cf - cf.Position)
	local terr = workspace:FindFirstChildOfClass("Terrain")
	-- ландшафт округляется блоками по 4 стада: землю делаем на 1.5 ниже, огород ставим на 2 выше уровня
	if terr then
		terr:FillBlock(flat * CF(0, 22.5, 4), V3(74, 48, 70), Mat.Air)
		terr:FillBlock(flat * CF(0, -8.5, 4), V3(74, 14, 70), WT.Themes[pi].base)
	end
	cf = cf + V3(0, (level + 2) - cf.Y, 0)
	local P = Map.planets[pi]
	if P.markers[j] then P.markers[j].Parent = nil end
	local pm = Instance.new("Model")
	pm.Name = "Plot" .. id
	pm:SetAttribute("Center", cf.Position)
	pm:SetAttribute("Planet", pi)
	local plot = { id = id, planet = pi, slot = j, cf = cf, model = pm, beds = {}, ang = ang }
	local glow = Game.PlanetColors[pi]
	local rng = Random.new(pi * 100 + j)
	local W2, D2 = 30, 25.5
	-- космический пол: глянцевая тьма со звёздной пылью
	part(pm, "Ground", V3(62, 5, 54), cf * CF(0, -2.35, 0), c(14, 14, 28), Mat.SmoothPlastic, { Reflectance = 0.18 })
	-- каменный цоколь под полом: не видно щелей, если земля вокруг ниже
	part(pm, "Plinth", V3(61.6, 9, 53.6), cf * CF(0, -9.3, 0), WT.Colors[WT.Themes[pi].base] or c(60, 56, 70), Mat.Slate)
	-- светящийся пояс по бокам платформы: огород видно издалека
	for _, sd in { { V3(0, -0.6, -27.05), V3(62.2, 0.35, 0.2) }, { V3(0, -0.6, 27.05), V3(62.2, 0.35, 0.2) }, { V3(-31.05, -0.6, 0), V3(0.2, 0.35, 54.2) }, { V3(31.05, -0.6, 0), V3(0.2, 0.35, 54.2) } } do
		deco(pm, "SideGlow", sd[2], cf * CF(sd[1]), glow, Mat.Neon, { Transparency = 0.1 })
	end
	-- ступени у входа
	for k = 1, 3 do
		part(pm, "Step", V3(8, 0.6, 1.6), cf * CF(0, -0.3 - (k - 1) * 0.6 - 0.3, -27 - k * 1.5 + 0.7), c(30, 30, 52), Mat.SmoothPlastic, { Reflectance = 0.15 })
	end
	for q = 1, 70 do
		local x, z = rng:NextNumber(-W2 + 1, W2 - 1), rng:NextNumber(-D2 + 1, D2 - 1)
		local sz = rng:NextNumber(0.1, 0.28)
		local col = q % 3 == 0 and glow or (q % 3 == 1 and c(255, 255, 255) or c(160, 190, 255))
		ball(pm, "Dust", (cf * CF(x, 0.27, z)).Position, sz, col, Mat.Neon)
	end
	-- светящаяся граница цвета планеты (проход спереди)
	local function edge(a, b)
		local p0, p1 = cf:PointToWorldSpace(a), cf:PointToWorldSpace(b)
		deco(pm, "Edge", V3(0.3, 0.14, (p1 - p0).Magnitude), CFrame.lookAt((p0 + p1) / 2, p1), glow, Mat.Neon, { Transparency = 0.15 })
	end
	local y = 0.3
	edge(V3(-W2, y, -D2), V3(-5, y, -D2))
	edge(V3(5, y, -D2), V3(W2, y, -D2))
	edge(V3(W2, y, -D2), V3(W2, y, D2))
	edge(V3(W2, y, D2), V3(-W2, y, D2))
	edge(V3(-W2, y, D2), V3(-W2, y, -D2))
	-- кристаллические пилоны по углам
	for _, p in { V3(-W2, 0, -D2), V3(W2, 0, -D2), V3(W2, 0, D2), V3(-W2, 0, D2) } do
		pylon(pm, cf:PointToWorldSpace(p * 1.03), glow, 7 + rng:NextNumber(0, 2))
	end
	-- арка-ворота с голограммой имени
	local gate = cf * CF(0, 0, -D2 - 1)
	for _, sx in { -5, 5 } do
		pylon(pm, gate:PointToWorldSpace(V3(sx, 0, 0)), glow, 5)
	end
	local prev
	for k = 0, 14 do
		local t = k / 14 * PI
		local p = gate:PointToWorldSpace(V3(cos(t) * 5, 5.5 + sin(t) * 4, 0))
		if prev then seg(pm, "Arch", prev, p, 0.28, glow, Mat.Neon) end
		prev = p
	end
	local board = part(pm, "Sign", V3(8, 1.8, 0.1), gate * CF(0, 7.4, 0) * A(0, PI, 0), c(10, 12, 24), Mat.Glass, { CanCollide = false, Transparency = 0.6 })
	plot.signFront = surfaceText(board, Enum.NormalId.Front, "Огород", glow, 40)
	plot.signBack = surfaceText(board, Enum.NormalId.Back, "Огород", glow, 40)
	part(pm, "EntryPath", V3(6, 0.2, 7), cf * CF(0, 0.12, -D2 - 1.5), c(30, 30, 52), Mat.SmoothPlastic, { CanCollide = false, Reflectance = 0.2 })
	-- северное сияние за огородом: полупрозрачные светящиеся ленты
	for k = 0, 13 do
		local x = -28 + k * 4.3
		local h = 12 + math.sin(k * 0.9) * 4 + rng:NextNumber(0, 3)
		local col = glow:Lerp(c(90, 230, 210), (math.sin(k * 0.6) + 1) / 2)
		deco(pm, "Aurora", V3(4.4, h, 0.1), cf * CF(x, h / 2 + 3 + math.sin(k * 0.7) * 1.5, D2 + 5 + math.sin(k * 1.3) * 1.5) * A(0, math.sin(k) * 0.2, 0), col, Mat.Neon, { Transparency = 0.86 })
	end
	-- мини-галактика над огородом (вращается на клиенте)
	local gal = Instance.new("Model")
	gal.Name = "MiniGalaxy"
	local gc = cf.Position + V3(0, 26, 0)
	local core = ball(gal, "GalaxyCore", gc, 2.2, c(255, 240, 210), Mat.Neon)
	light(core, glow, 40, 1.2)
	ball(gal, "GalaxyHalo", gc, 5, glow, Mat.Neon, { Transparency = 0.8 })
	for arm = 0, 1 do
		for q = 1, 22 do
			local t = q / 22
			local a = arm * PI + t * PI * 2.4
			local r = 2 + t * 11
			local p = gc + V3(cos(a) * r, (rng:NextNumber() - 0.5) * 0.8, sin(a) * r)
			local col = glow:Lerp(c(255, 255, 255), 1 - t)
			ball(gal, "GalaxyStar", p, 0.9 - t * 0.5, col, Mat.Neon, { Transparency = t * 0.3 })
		end
	end
	gal.PrimaryPart = core
	gal:SetAttribute("Spin", 0.25)
	gal:SetAttribute("Pivot", gc)
	gal.Parent = pm
	-- грядки
	local beds = Instance.new("Folder")
	beds.Name = "Beds"
	beds.Parent = pm
	for bi = 1, Map.MaxBeds do
		local lp = Map.bedLocalPos(bi)
		plot.beds[bi] = bedBox(beds, cf * CF(lp) * CF(0, 0.25, 0), bi, id, glow)
	end
	plot.entrance = cf * CF(0, 3, -D2 - 6) * A(0, PI, 0)
	plot.center = cf.Position
	local d = Instance.new("Folder")
	d.Name = "Decor"
	d.Parent = pm
	plot.decor = d
	pm.Parent = P.plotsFolder
	Map.plots[id] = plot
	return plot
end

function Map.destroyPlot(id)
	local plot = Map.plots[id]
	if not plot then return end
	plot.model:Destroy()
	Map.plots[id] = nil
	local P = Map.planets[plot.planet]
	if P.markers[plot.slot] then P.markers[plot.slot].Parent = P.slotFolder end
end

------------------------------------------------------------------ украшения огорода (покупаются за монеты)
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
	dcyl(parent, "GlobeBaseGlow", cf * CF(0, 0.7, 0), 0.1, 2.86, COL.cyan, Mat.Neon)
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
	dcyl(parent, "PadRing", cf * CF(0, 0.4, 0), 0.14, 12.1, COL.gold, Mat.Neon, { Transparency = 0.35 })
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


DECOR.banner = function(parent, cf)
	for q = 0, 5 do
		local base = cf * CF(-24 + q * 9.6, 0, 27.5)
		local pos = base.Position
		seg(parent, "FlagPole", pos + V3(0, 0.2, 0), pos + V3(0, 7.5, 0), 0.22, COL.plate, Mat.Metal)
		local col = Game.PlanetColors[q + 1]
		deco(parent, "Flag", V3(0.12, 2.2, 3), base * CF(0, 6.2, 1.7), col, Mat.SmoothPlastic)
		ball(parent, "FlagTop", pos + V3(0, 7.7, 0), 0.5, col, Mat.Neon)
	end
end
DECOR.lamps = function(parent, cf)
	for _, sx in { -32, 32 } do
		for q = 0, 4 do
			local pos = (cf * CF(sx, 0, -20 + q * 10)).Position
			seg(parent, "Stake", pos, pos + V3(0, 2.2, 0), 0.14, COL.plate, Mat.Metal)
			local b = ball(parent, "StakeBulb", pos + V3(0, 2.5, 0), 0.7, Game.PlanetColors[q % 6 + 1], Mat.Neon)
			if q % 2 == 0 then light(b, b.Color, 10, 0.5) end
		end
	end
end
local DECOR_ANCHOR = { -- координаты относительно огорода
	bench = { CF(0, 0, 30) },
	banner = { CF() },
	lamps = { CF() },
	fountain = { CF(-36, 0, -8) },
	telescope = { CF(36, 0, 10) * A(0, -0.8, 0) },
	globe = { CF(36, 0, -12) },
	rocket = { CF(-24, 0, 38) },
	starpond = { CF(20, 0, 38) },
}
function Map.placeDecor(id, decorId: string)
	local plot = Map.plots[id]
	if not plot or plot.decor:FindFirstChild(decorId) then return end
	local m = Instance.new("Model")
	m.Name = decorId
	m.Parent = plot.decor
	DECOR[decorId](m, plot.cf * DECOR_ANCHOR[decorId][1])
end
function Map.clearDecor(id)
	local plot = Map.plots[id]
	if plot then plot.decor:ClearAllChildren() end
end
function Map.setPlotSign(id, text: string, color)
	local plot = Map.plots[id]
	if not plot then return end
	plot.signFront.Text, plot.signBack.Text = text, text
	if color then plot.signFront.TextColor3, plot.signBack.TextColor3 = color, color end
end
function Map.setBedLocked(id, bedIdx: number, locked: boolean)
	local plot = Map.plots[id]
	local bed = plot and plot.beds[bedIdx]
	if not bed then return end
	bed.cover.Transparency = locked and 0 or 1
	bed.lockOrb.Transparency = locked and 0.2 or 1
end

------------------------------------------------------------------ площадь планеты: ракета, киоски, дорожки
local KIOSKS = {
	{ id = "shop", ang = 0, col = COL.green, title = "СЕМЕНА", prompt = "Купить семена", icon = "seed" },
	{ id = "sell", ang = 90, col = COL.gold, title = "ПРОДАЖА", prompt = "Продать урожай", icon = "coin" },
	{ id = "market", ang = 180, col = COL.mag, title = "РЫНОК", prompt = "Рынок и спрос", icon = "news" },
	{ id = "upgrades", ang = 270, col = COL.cyan, title = "МАСТЕРСКАЯ", prompt = "Улучшения", icon = "upgrade" },
}
local function emitter(parent, props)
	local e = Instance.new("ParticleEmitter")
	for k, v in props do e[k] = v end
	e.Parent = parent
	return e
end
local function anchorPart(parent, name, cf, size)
	return part(parent, name, size or V3(1, 1, 1), cf, c(0, 0, 0), Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
end
-- голографическая вывеска, видна издалека
local function holoSign(parent, pos, text, color, sub)
	local p = anchorPart(parent, "HoloSign", CF(pos), V3(1, 1, 1))
	local bb = Instance.new("BillboardGui")
	bb.Size, bb.AlwaysOnTop, bb.LightInfluence, bb.MaxDistance = UDim2.fromOffset(260, 70), false, 0, 420
	bb.Parent = p
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.new(1, 0, 0.62, 0), 1, true, Enum.Font.GothamBlack
	t.Text, t.TextColor3, t.TextStrokeTransparency, t.TextStrokeColor3 = text, color, 0.4, c(10, 10, 30)
	t.Parent = bb
	local t2 = Instance.new("TextLabel")
	t2.Name = "Sub"
	t2.Position, t2.Size, t2.BackgroundTransparency, t2.TextScaled, t2.Font = UDim2.fromScale(0, 0.62), UDim2.fromScale(1, 0.38), 1, true, Enum.Font.GothamBold
	t2.Text, t2.TextColor3, t2.TextStrokeTransparency = sub or "", c(235, 235, 255), 0.5
	t2.Parent = bb
	return p, t2
end

-- корона победителя конкурса над огородом
function Map.setCrown(id, on: boolean)
	local plot = Map.plots[id]
	if not plot then return end
	local old = plot.model:FindFirstChild("Crown")
	if old then old:Destroy() end
	if not on then return end
	local m = Instance.new("Model")
	m.Name = "Crown"
	local pos = plot.center + V3(0, 24, 0)
	local gold, gem = c(255, 205, 70), c(255, 90, 140)
	ring(m, "CrownBand", pos, 3.2, 0, 0.9, 1.4, gold, Mat.Neon, 20, nil, { Transparency = 0 })
	for k = 0, 4 do
		local a = k / 5 * PI * 2
		local p = pos + V3(cos(a) * 3.2, 1.6, sin(a) * 3.2)
		ell(m, "CrownSpike", CF(p), V3(1, 3, 1), gold, Mat.Neon, { CanCollide = false })
		ball(m, "CrownGem", p + V3(0, 1.8, 0), 0.8, gem, Mat.Neon)
	end
	local core = anchorPart(m, "CrownCore", CF(pos), V3(1, 1, 1))
	light(core, gold, 40, 2)
	emitter(core, { Color = ColorSequence.new(gold), Size = NumberSequence.new(0.5, 0), LightEmission = 1, Lifetime = NumberRange.new(1, 2), Rate = 20,
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180) })
	local bb = Instance.new("BillboardGui")
	bb.Size, bb.StudsOffset, bb.LightInfluence, bb.MaxDistance = UDim2.fromOffset(260, 40), V3(0, 5, 0), 0, 600
	bb.Parent = core
	local t = Instance.new("TextLabel")
	t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
	t.Text, t.TextColor3, t.TextStrokeTransparency = "ЛУЧШИЙ ОГОРОД", gold, 0.3
	t.Parent = bb
	m:SetAttribute("Spin", 0.8)
	m:SetAttribute("Pivot", pos)
	m.Parent = plot.model
end
-- киоски площади: единый стиль станции — полукруглая стеклянная стена, козырёк, изогнутый прилавок,
-- над прилавком вращающаяся голограмма своего товара, вывеска встроена в стену. Перед киоска (-Z) смотрит в центр
local function kioskSign(m, kcf, color, title, iconKey)
	local board = part(m, "Sign", V3(10.5, 2.4, 0.35), kcf * CF(0, 9.7, 5.4), c(12, 14, 26), Mat.SmoothPlastic, { CanCollide = false })
	deco(m, "SignRim", V3(11, 2.8, 0.2), kcf * CF(0, 9.7, 5.6), color, Mat.Neon, { Transparency = 0.3 })
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
		local gui = Instance.new("SurfaceGui")
		gui.Face, gui.SizingMode, gui.PixelsPerStud, gui.LightInfluence = face, Enum.SurfaceGuiSizingMode.PixelsPerStud, 40, 0
		gui.Parent = board
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency, img.Image, img.ImageColor3 = 1, Icons[iconKey] or "", color
		img.Position, img.Size = UDim2.new(0, 16, 0.5, -36), UDim2.fromOffset(72, 72)
		img.Parent = gui
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency, t.TextScaled, t.Font, t.Text, t.TextColor3 = 1, true, Enum.Font.GothamBold, title, Color3.fromRGB(240, 244, 255)
		t.Position, t.Size = UDim2.new(0, 100, 0.16, 0), UDim2.new(1, -120, 0.68, 0)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.Parent = gui
	end
end
local function kioskBase(m, kcf, color)
	local steel, glassC = c(52, 58, 76), c(120, 150, 200)
	cyl(m, "Base", kcf * CF(0, 0.3, 1.5), 0.6, 15, c(40, 44, 58), Mat.Metal)
	dcyl(m, "BaseGlow", kcf * CF(0, 0.62, 1.5), 0.04, 14.6, color, Mat.Neon, { Transparency = 0.45 })
	dcyl(m, "BaseInner", kcf * CF(0, 0.64, 1.5), 0.04, 14.2, c(40, 44, 58), Mat.Metal)
	-- полукруглая стена: стеклянные панели и металлические рёбра
	local R, n = 6.4, 8
	for q = 0, n - 1 do
		local a0 = math.rad(-72 + q * 144 / n)
		local a1 = math.rad(-72 + (q + 1) * 144 / n)
		local am = (a0 + a1) / 2
		local p0 = V3(math.sin(a0) * R, 0, math.cos(a0) * R)
		local p1 = V3(math.sin(a1) * R, 0, math.cos(a1) * R)
		local mid = (p0 + p1) / 2
		local w = (p1 - p0).Magnitude
		local pcf = kcf * CF(mid.X, 4.6, mid.Z + 1.5) * A(0, am, 0)
		part(m, "WallGlass", V3(w, 7.6, 0.25), pcf, glassC:Lerp(c(20, 26, 44), 0.55), Mat.Glass, { Transparency = 0.25 })
		local rib = kcf * CF(p0.X, 4.6, p0.Z + 1.5)
		part(m, "WallRib", V3(0.35, 8.2, 0.45), rib * A(0, a0, 0), steel, Mat.Metal)
		deco(m, "WallRibGlow", V3(0.08, 7.4, 0.08), rib * A(0, a0, 0) * CF(0, 0, -0.26), color, Mat.Neon, { Transparency = 0.2 })
	end
	local endRib = kcf * CF(math.sin(math.rad(72)) * R, 4.6, math.cos(math.rad(72)) * R + 1.5)
	part(m, "WallRib", V3(0.35, 8.2, 0.45), endRib * A(0, math.rad(72), 0), steel, Mat.Metal)
	-- козырёк со светящейся кромкой
	cyl(m, "Canopy", kcf * CF(0, 8.75, 1.5), 0.35, 15, c(30, 34, 48), Mat.Metal)
	dcyl(m, "CanopyGlow", kcf * CF(0, 8.55, 1.5), 0.12, 15.2, color, Mat.Neon, { Transparency = 0.15 })
	dcyl(m, "CanopyLight", kcf * CF(0, 8.5, 1.5), 0.05, 11, c(235, 240, 255), Mat.Neon, { Transparency = 0.55 })
	-- изогнутый прилавок
	local Rc = 4.2
	for q = 0, 5 do
		local a0 = math.rad(-55 + q * 110 / 6)
		local a1 = math.rad(-55 + (q + 1) * 110 / 6)
		local p0 = V3(math.sin(a0) * Rc, 0, -math.cos(a0) * Rc)
		local p1 = V3(math.sin(a1) * Rc, 0, -math.cos(a1) * Rc)
		local mid = (p0 + p1) / 2
		local w = (p1 - p0).Magnitude + 0.05
		local ccf = kcf * CF(mid.X, 1.85, mid.Z + 1.5) * A(0, -(a0 + a1) / 2, 0)
		part(m, "Counter", V3(w, 2.5, 0.9), ccf, c(225, 228, 236), Mat.SmoothPlastic)
		part(m, "CounterTop", V3(w + 0.05, 0.18, 1.2), ccf * CF(0, 1.32, 0.1), c(40, 44, 58), Mat.Metal)
		deco(m, "CounterGlow", V3(w + 0.05, 0.1, 0.06), ccf * CF(0, 1.2, -0.48), color, Mat.Neon)
	end
	-- проектор голограммы
	cyl(m, "Projector", kcf * CF(0, 3.45, 1.5), 0.3, 1.4, c(40, 44, 58), Mat.Metal)
	dcyl(m, "ProjectorGlow", kcf * CF(0, 3.62, 1.5), 0.05, 1.1, color, Mat.Neon)
	local beam = part(m, "HoloBeam", V3(2.4, 2.6, 2.4), kcf * CF(0, 4.9, 1.5), color, Mat.Neon, { CanCollide = false, Transparency = 0.88, Shape = Enum.PartType.Cylinder })
	beam.CFrame = kcf * CF(0, 4.9, 1.5) * A(0, 0, PI / 2)
	beam.Size = V3(2.6, 2.2, 2.2)
end
-- голограмма товара: модель, которую клиент вращает (атрибуты Spin и Pivot)
local function holo(m, kcf, build)
	local h = Instance.new("Model")
	h.Name = "Hologram"
	h.Parent = m
	local center = (kcf * CF(0, 5.2, 1.5)).Position
	build(h, center)
	h:SetAttribute("Spin", 0.9)
	h:SetAttribute("Pivot", center)
end
local KIOSK_BUILD = {}
KIOSK_BUILD.shop = function(m, kcf, color)
	holo(m, kcf, function(h, ctr)
		seg(h, "HoloStem", ctr - V3(0, 1.2, 0), ctr + V3(0, 0.6, 0), 0.18, color, Mat.Neon, { Transparency = 0.25 })
		for q = 0, 3 do
			local a = q * PI / 2 + 0.4
			ell(h, "HoloLeaf", CF(ctr + V3(cos(a) * 0.55, -0.2 + q * 0.25, sin(a) * 0.55)) * A(0, -a, 0.6), V3(1.1, 0.12, 0.5), color, Mat.Neon, { Transparency = 0.3, CanCollide = false })
		end
		ball(h, "HoloBud", ctr + V3(0, 0.85, 0), 0.5, c(200, 255, 220), Mat.Neon, { Transparency = 0.2 })
	end)
end
KIOSK_BUILD.sell = function(m, kcf, color)
	holo(m, kcf, function(h, ctr)
		local coinCF = CF(ctr) * A(PI / 2, 0, 0)
		part(h, "HoloCoin", V3(1.8, 0.25, 1.8), coinCF * A(0, 0, PI / 2), color, Mat.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.2, Size = V3(0.25, 1.8, 1.8) })
		part(h, "HoloCoinRim", V3(0.3, 2.05, 2.05), coinCF * A(0, 0, PI / 2), c(255, 240, 180), Mat.Neon, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.6 })
		ball(h, "HoloSpark", ctr + V3(0.9, 0.8, 0), 0.25, c(255, 250, 220), Mat.Neon)
	end)
end
KIOSK_BUILD.market = function(m, kcf, color)
	holo(m, kcf, function(h, ctr)
		for q = 0, 3 do
			local hgt = 0.5 + q * 0.4
			part(h, "HoloBar", V3(0.35, hgt, 0.35), CF(ctr + V3(-0.75 + q * 0.5, -1 + hgt / 2, 0)), color, Mat.Neon, { CanCollide = false, Transparency = 0.25 })
		end
		seg(h, "HoloTrend", ctr + V3(-0.8, -0.3, 0), ctr + V3(0.9, 1.0, 0), 0.1, c(255, 240, 255), Mat.Neon)
	end)
end
KIOSK_BUILD.upgrades = function(m, kcf, color)
	holo(m, kcf, function(h, ctr)
		local gcf = CF(ctr)
		cyl(h, "HoloGearDisc", gcf * A(PI / 2, 0, 0), 0.25, 1.5, color, Mat.Neon, { CanCollide = false, Transparency = 0.25 })
		for q = 0, 9 do
			local a = q / 10 * PI * 2
			part(h, "HoloGearTooth", V3(0.35, 0.4, 0.25), gcf * CF(cos(a) * 0.95, sin(a) * 0.95, 0) * A(0, 0, a), color, Mat.Neon, { CanCollide = false, Transparency = 0.25 })
		end
		ball(h, "HoloGearHub", ctr, 0.45, c(220, 255, 255), Mat.Neon)
	end)
end
local function buildKiosk(parent, k, kcf)
	local m = Instance.new("Model")
	m.Name = "Kiosk_" .. k.id
	m.Parent = parent
	kioskBase(m, kcf, k.col)
	KIOSK_BUILD[k.id](m, kcf, k.col)
	kioskSign(m, kcf, k.col, k.title, k.icon)
	m.WorldPivot = kcf
	return m
end

local function buildHub(pi, parent)
	local ctr = WT.Centers[pi]
	local name = Game.Planets[pi].name
	local f = Instance.new("Folder")
	f.Name = "Hub"
	f.Parent = parent
	local lift = math.max(0, Map.surfaceY(ctr.X, ctr.Z, pi) - ctr.Y)
	cyl(f, "PlazaBase", CF(ctr + V3(0, lift - 1.5, 0)), 4, 76, PLAZA[pi]:Lerp(c(30, 30, 40), 0.4), Mat.Concrete)
	cyl(f, "Plaza", CF(ctr + V3(0, lift + 0.2, 0)), 0.5, 76, PLAZA[pi], Mat.Concrete)
	dcyl(f, "PlazaRing", CF(ctr + V3(0, lift + 0.46, 0)), 0.06, 76.4, COL.trim, Mat.Metal)
	dcyl(f, "PlazaInner", CF(ctr + V3(0, lift + 0.47, 0)), 0.06, 75.6, PLAZA[pi], Mat.Concrete)
	-- узор площади: два светящихся кольца в цвет планеты и скамейки с фонарями
	local pc = Game.PlanetColors[pi]
	ring(f, "PlazaLine", ctr + V3(0, lift, 0), 16, 0.5, 0.35, 0.06, pc, Mat.Neon, 40, nil, { Transparency = 0.35 })
	ring(f, "PlazaLine", ctr + V3(0, lift, 0), 35.5, 0.5, 0.35, 0.06, pc, Mat.Neon, 80, nil, { Transparency = 0.35 })
	for _, deg in { 225, 315 } do
		local a = math.rad(deg)
		local bp = ctr + V3(cos(a) * 33, lift + 0.45, sin(a) * 33)
		local bcf = CFrame.lookAt(bp, V3(ctr.X, bp.Y, ctr.Z))
		part(f, "BenchSeat", V3(6, 0.4, 1.6), bcf * CF(0, 1.4, 0), COL.wood, Mat.Wood)
		part(f, "BenchBack", V3(6, 1.6, 0.3), bcf * CF(0, 2.4, 0.75) * A(-0.15, 0, 0), COL.wood, Mat.Wood)
		for _, sx in { -2.6, 2.6 } do part(f, "BenchLeg", V3(0.3, 1.2, 1.4), bcf * CF(sx, 0.7, 0), COL.plate, Mat.Metal) end
		local lpos = (bcf * CF(4, 0, 0.4)).Position
		seg(f, "LampPost", lpos, lpos + V3(0, 6, 0), 0.3, COL.plate, Mat.Metal)
		local bulb = ball(f, "LampBulb", lpos + V3(0, 6.3, 0), 0.9, COL.warm, Mat.Neon)
		light(bulb, COL.warm, 20, 0.9)
	end
	-- ракета в центре: на ней летают между планетами
	local pad = Instance.new("Model")
	pad.Name = "RocketPad"
	pad.Parent = f
	DECOR.rocket(pad, CF(ctr))
	local trig = part(pad, "PromptPart", V3(12, 4, 12), CF(ctr + V3(0, 2, 0)), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
	local pr = prompt(trig, "Полететь на другую планету", "Ракета", 14, "Open_travel")
	pr:SetAttribute("Window", "travel")
	-- табличка с названием планеты
	local sign = part(f, "PlanetSign", V3(14, 3.4, 0.4), CF(ctr + V3(0, 23, 0)), COL.dark, Mat.SmoothPlastic, { CanCollide = false })
	surfaceText(sign, Enum.NormalId.Front, string.upper(name), Game.PlanetColors[pi], 30)
	surfaceText(sign, Enum.NormalId.Back, string.upper(name), Game.PlanetColors[pi], 30)
	for i, k in KIOSKS do
		local a = math.rad(k.ang)
		local pos = ctr + V3(cos(a) * 25, lift + 0.45, sin(a) * 25)
		local kcf = CFrame.lookAt(pos, ctr + V3(0, lift + 0.45, 0))
		local m = buildKiosk(f, k, kcf)
		Map.spots[k.id .. pi] = pos
		Map.spots[k.id .. "Front" .. pi] = (kcf * CF(0, 0, -7)).Position
		if k.id == "market" then
			local scr = part(m, "Screen", V3(7.2, 4.6, 0.3), kcf * CF(0, 5.2, 7.2), c(8, 10, 20), Mat.SmoothPlastic, { CanCollide = false })
			local lbl = surfaceText(scr, Enum.NormalId.Front, "Рынок загружается", COL.mag, 30)
			lbl.TextScaled = false
			lbl.TextSize = 22
			lbl.RichText = true
			table.insert(Map.boardLabels, lbl)
		end
		local t2 = part(m, "PromptPart", V3(6, 3, 3), kcf * CF(0, 2.2, -4.5), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local p2 = prompt(t2, k.prompt, "", 12, "Open_" .. k.id)
		p2:SetAttribute("Window", k.id)
	end
	-- табло лидеров: три колонки (заголовок, 7 строк с медалями), строки заполняет сервер
	do
		local a = math.rad(45)
		local pos = ctr + V3(cos(a) * 33, lift, sin(a) * 33)
		local bcf = CFrame.lookAt(pos, V3(ctr.X, pos.Y, ctr.Z))
		local W, H = 25, 10.5
		for _, sx in { -W / 2 + 0.8, W / 2 - 0.8 } do
			cyl(f, "BoardPole", bcf * CF(sx, 3.2, 0.5), 6.4, 0.8, COL.plate, Mat.Metal)
		end
		local board = part(f, "LeaderBoard", V3(W, H, 0.5), bcf * CF(0, 6.4 + H / 2, 0), c(12, 14, 30), Mat.SmoothPlastic)
		deco(f, "LeaderBoardRim", V3(W + 0.6, H + 0.6, 0.3), bcf * CF(0, 6.4 + H / 2, 0.25), COL.gold, Mat.Neon, { Transparency = 0.35 })
		deco(f, "LeaderCrown", V3(4, 1.4, 0.3), bcf * CF(0, 6.4 + H + 0.9, 0), COL.gold, Mat.Neon)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 32
		gui.LightInfluence = 0
		gui.Parent = board
		local function lbl(parent, text, props)
			local t = Instance.new("TextLabel")
			t.BackgroundTransparency, t.Font, t.TextScaled, t.Text = 1, Enum.Font.GothamBold, true, text
			t.TextColor3 = c(235, 238, 255)
			for k, v in props do
				if k ~= "Max" then t[k] = v end
			end
			t.Parent = parent
			local lim = Instance.new("UITextSizeConstraint")
			lim.MaxTextSize = props.Max or 22
			lim.Parent = t
			return t
		end
		local DEFS = {
			{ key = "rich", title = "БОГАЧИ", sub = "заработано за всё время", col = c(255, 205, 90) },
			{ key = "heavy", title = "ТЯЖЕЛОВЕСЫ", sub = "самый тяжёлый плод недели", col = c(120, 230, 150) },
			{ key = "rare", title = "РЕДКОСТЬ", sub = "самая редкая мутация", col = c(200, 140, 255) },
		}
		local MEDAL = { c(255, 205, 90), c(210, 220, 235), c(225, 150, 95) }
		local cols = {}
		for k, def in DEFS do
			local col = Instance.new("Frame")
			col.Position, col.Size = UDim2.new((k - 1) / 3, 8, 0, 8), UDim2.new(1 / 3, -16, 1, -16)
			col.BackgroundColor3, col.BackgroundTransparency, col.BorderSizePixel = c(24, 28, 54), 0.15, 0
			col.Parent = gui
			local cr = Instance.new("UICorner")
			cr.CornerRadius = UDim.new(0, 14)
			cr.Parent = col
			local head = Instance.new("Frame")
			head.Size, head.BackgroundColor3, head.BorderSizePixel = UDim2.new(1, 0, 0, 58), def.col, 0
			head.BackgroundTransparency = 0.75
			head.Parent = col
			local hc = cr:Clone()
			hc.Parent = head
			lbl(head, def.title, { Position = UDim2.new(0, 10, 0, 4), Size = UDim2.new(1, -20, 0, 32), TextColor3 = def.col, Font = Enum.Font.GothamBlack, Max = 30 })
			lbl(head, def.sub, { Position = UDim2.new(0, 10, 0, 36), Size = UDim2.new(1, -20, 0, 18), TextColor3 = c(190, 195, 220), Max = 16 })
			local rows = {}
			for i = 1, 7 do
				local r = Instance.new("Frame")
				r.Position, r.Size = UDim2.new(0, 6, 0, 64 + (i - 1) * 37), UDim2.new(1, -12, 0, 33)
				r.BackgroundColor3, r.BackgroundTransparency, r.BorderSizePixel = c(255, 255, 255), i % 2 == 1 and 0.93 or 0.97, 0
				r.Parent = col
				local rc = Instance.new("UICorner")
				rc.CornerRadius = UDim.new(0, 8)
				rc.Parent = r
				local rank = lbl(r, tostring(i), { Position = UDim2.new(0, 4, 0, 3), Size = UDim2.new(0, 30, 1, -6), TextColor3 = MEDAL[i] or c(150, 155, 185), Font = Enum.Font.GothamBlack, Max = 22 })
				rank.TextXAlignment = Enum.TextXAlignment.Center
				local name = lbl(r, i == 1 and "пока пусто" or "", { Position = UDim2.new(0, 38, 0, 5), Size = UDim2.new(0.55, -38, 1, -10), TextColor3 = i <= 3 and c(255, 255, 255) or c(215, 220, 240), Max = 20 })
				name.TextXAlignment = Enum.TextXAlignment.Left
				name.TextScaled, name.TextSize = false, 19
				name.TextTruncate = Enum.TextTruncate.AtEnd
				local val = lbl(r, "", { Position = UDim2.new(0.55, 0, 0, 5), Size = UDim2.new(0.45, -8, 1, -10), TextColor3 = MEDAL[i] or def.col, Max = 20 })
				val.TextXAlignment = Enum.TextXAlignment.Right
				rows[i] = { name = name, val = val }
			end
			cols[def.key] = rows
		end
		table.insert(Map.leaderBoards, cols)
		local trig = part(f, "LeaderPrompt", V3(8, 4, 3), bcf * CF(0, 2, -2), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local pr = prompt(trig, "Таблица лидеров", "", 12, "Open_leaders")
		pr:SetAttribute("Window", "leaders")
	end
	-- мистический торговец: лавка собрана заранее, сервер показывает её по расписанию
	do
		local a = math.rad(135)
		local pos = ctr + V3(cos(a) * 31, lift + 0.45, sin(a) * 31)
		local scf = CFrame.lookAt(pos, V3(ctr.X, pos.Y, ctr.Z))
		local m = Instance.new("Model")
		m.Name = "MysticStall"
		local violet, deep, gold = c(170, 100, 255), c(40, 20, 70), c(240, 200, 110)
		cyl(m, "StallBase", scf * CF(0, 0.3, 0), 0.6, 12, c(34, 26, 52), Mat.Marble)
		dcyl(m, "StallRune", scf * CF(0, 0.62, 0), 0.04, 11.4, violet, Mat.Neon, { Transparency = 0.35 })
		dcyl(m, "StallRuneIn", scf * CF(0, 0.64, 0), 0.04, 10.8, c(34, 26, 52), Mat.Marble)
		-- шатёр: четыре золотые стойки и ступенчатая крыша-пагода
		for _, sx in { -4.2, 4.2 } do
			for _, sz in { -2.8, 2.8 } do
				cyl(m, "StallPole", scf * CF(sx, 3.7, sz), 6.6, 0.35, gold, Mat.Metal)
			end
		end
		local roofCol = c(74, 40, 130)
		for q, sz in { { 10.4, 7.4 }, { 8, 5.6 }, { 5.4, 3.8 }, { 2.8, 2 } } do
			local y = 7 + (q - 1) * 0.75
			part(m, "StallRoof", V3(sz[1], 0.5, sz[2]), scf * CF(0, y, 0), roofCol:Lerp(c(40, 20, 80), q * 0.12), Mat.SmoothPlastic)
			deco(m, "StallRoofTrim", V3(sz[1] + 0.2, 0.12, sz[2] + 0.2), scf * CF(0, y - 0.26, 0), gold, Mat.Metal)
		end
		ball(m, "StallRoofGem", (scf * CF(0, 10.2, 0)).Position, 0.9, violet, Mat.Neon)
		light(m.StallRoofGem, violet, 14, 1)
		-- прилавок с бархатом
		part(m, "StallCounter", V3(7.4, 2.2, 1.6), scf * CF(0, 1.7, -1.8), c(58, 34, 28), Mat.Wood)
		deco(m, "StallCloth", V3(7.6, 0.12, 1.9), scf * CF(0, 2.86, -1.8), c(96, 40, 140), Mat.SmoothPlastic)
		deco(m, "StallClothFront", V3(7.6, 1.2, 0.1), scf * CF(0, 2.3, -2.76), c(96, 40, 140), Mat.SmoothPlastic)
		deco(m, "StallClothTrim", V3(7.6, 0.12, 0.12), scf * CF(0, 1.7, -2.8), gold, Mat.Metal)
		cyl(m, "OrbStand", scf * CF(0, 3.15, -1.8), 0.5, 0.9, gold, Mat.Metal)
		local orb = ball(m, "CrystalOrb", (scf * CF(0, 3.95, -1.8)).Position, 1.4, c(210, 180, 255), Mat.Glass, { Transparency = 0.35 })
		ball(m, "OrbCore", (scf * CF(0, 3.95, -1.8)).Position, 0.5, violet, Mat.Neon)
		light(orb, violet, 16, 1.2)
		for q, col in { c(120, 255, 190), c(255, 140, 200), c(120, 200, 255) } do
			local pp = (scf * CF(-3.1 + q * 0.75, 3.2, -1.6)).Position
			ball(m, "Potion", pp, 0.5, col:Lerp(c(0, 0, 0), 0.1), Mat.Glass, { Transparency = 0.15 })
			seg(m, "PotionNeck", pp + V3(0, 0.2, 0), pp + V3(0, 0.6, 0), 0.18, c(230, 230, 240), Mat.Glass)
		end
		-- торговец: длинная мантия, капюшон с тенью вместо лица, светящиеся глаза, посох с кристаллом
		local robe = c(52, 28, 92)
		ell(m, "MerchantRobe", scf * CF(0, 2.5, 0.8), V3(2.6, 4.6, 2.2), robe, Mat.SmoothPlastic, { CanCollide = false })
		ell(m, "MerchantCape", scf * CF(0, 3.2, 1.2), V3(3, 4, 1.4), robe:Lerp(c(20, 10, 40), 0.3), Mat.SmoothPlastic, { CanCollide = false })
		deco(m, "MerchantBelt", V3(2.3, 0.25, 1.9), scf * CF(0, 2.9, 0.8), gold, Mat.Metal)
		ell(m, "MerchantHood", scf * CF(0, 5.2, 0.8), V3(1.9, 2, 1.9), robe:Lerp(c(90, 50, 150), 0.2), Mat.SmoothPlastic, { CanCollide = false })
		ell(m, "MerchantFace", scf * CF(0, 5.05, 0.25), V3(1.1, 1.1, 0.6), c(8, 6, 14), Mat.SmoothPlastic, { CanCollide = false })
		for _, ex in { -0.26, 0.26 } do
			ball(m, "MerchantEye", (scf * CF(ex, 5.1, -0.05)).Position, 0.18, c(255, 225, 130), Mat.Neon)
		end
		local staffB, staffT = (scf * CF(1.7, 0.7, 0.2)).Position, (scf * CF(1.7, 6.6, 0.2)).Position
		seg(m, "MerchantStaff", staffB, staffT, 0.22, c(90, 60, 40), Mat.Wood)
		ell(m, "StaffCrystal", CF(staffT + V3(0, 0.6, 0)), V3(0.5, 1.1, 0.5), c(170, 120, 255), Mat.Neon)
		-- портал за спиной: тонкое кольцо и переливающаяся плёнка
		local pcf = scf * CF(0, 4.4, 3.4)
		for q = 0, 23 do
			local a0, a1 = q / 24 * PI * 2, (q + 1) / 24 * PI * 2
			local p0 = (pcf * CF(cos(a0) * 3, sin(a0) * 3, 0)).Position
			local p1 = (pcf * CF(cos(a1) * 3, sin(a1) * 3, 0)).Position
			seg(m, "Portal", p0, p1, 0.3, violet, Mat.Neon)
		end
		cyl(m, "PortalFilm", pcf * A(PI / 2, 0, 0), 0.05, 5.8, c(150, 110, 255), Mat.ForceField, { CanCollide = false, Transparency = 0.2 })
		local pa = anchorPart(m, "PortalFx", pcf, V3(4, 4, 0.5))
		emitter(pa, { Color = ColorSequence.new(violet, c(120, 220, 255)), Size = NumberSequence.new(0.3, 0), LightEmission = 1, Lifetime = NumberRange.new(1.5, 3), Rate = 16,
			Speed = NumberRange.new(0.4, 1.5), SpreadAngle = Vector2.new(180, 180) })
		local trig = part(m, "MysticPrompt", V3(6, 4, 3), scf * CF(0, 2, -3.2), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local pr = prompt(trig, "Редкие травы", "Мистический торговец", 12, "Open_mystic")
		pr:SetAttribute("Window", "mystic")
		local _, sub = holoSign(m, pos + V3(0, 12, 0), "МИСТИЧЕСКИЙ ТОРГОВЕЦ", c(200, 150, 255), "редкие травы этой планеты")
		sub.Parent:SetAttribute("Mystic", true)
		Map.spots["mystic" .. pi] = (scf * CF(0, 2, -3.2)).Position
		Map.mysticStalls[pi] = { model = m, parent = f }
	end
	-- дорожки к огородам
	for j = 1, Map.SlotsPerPlanet do
		local _, ang = slotCF(pi, j)
		local dirv = V3(cos(ang), 0, sin(ang))
		local r0, r1 = 38, Map.PlotRing - 31
		local len = r1 - r0
		local mid = ctr + dirv * ((r0 + r1) / 2)
		local wcf = CFrame.lookAt(V3(mid.X, ctr.Y + 0.2, mid.Z), V3(mid.X, ctr.Y + 0.2, mid.Z) - dirv)
		part(f, "Walkway", V3(7, 0.4, len), wcf, PLAZA[pi]:Lerp(c(60, 60, 70), 0.35), Mat.Cobblestone)
		-- фонари у входа на участок (не в середине дорожки: на Туманности там спираль паркура)
		for _, s in { -1, 1 } do
			local pos = (wcf * CF(s * 4.6, 0, len / 2 - 3)).Position
			seg(f, "Pole", pos, pos + V3(0, 4.6, 0), 0.22, COL.plate, Mat.Metal)
			local b = ball(f, "Bulb", pos + V3(0, 4.9, 0), 0.6, COL.warm, Mat.Neon)
			if s == 1 then light(b, COL.warm, 16, 0.6) end
		end
	end
end

------------------------------------------------------------------ флора и камни планеты
local function bigPlant(parent, id, pos, s, yaw)
	local ok, m = pcall(PM.build, id, nil)
	if not ok or not m then return end
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local pp = p.Position
			local rot = CF(pp):Inverse() * p.CFrame
			p.Size = p.Size * s
			p.CFrame = CF(pp * s) * rot
			p.CanCollide = s > 2.5 and (p.Name:sub(1, 1) == "R" or p.Name:sub(1, 1) == "F") or false
		end
	end
	for _, l in m:GetDescendants() do
		if l:IsA("PointLight") then l:Destroy() end
	end
	m:PivotTo(CF(pos) * A(0, yaw, 0))
	m.Parent = parent
	return m
end


-- трасса гонки на Марсе должна быть свободна от камней и деревьев
local function onRacePath(pi, x, z)
	if pi ~= 2 then return false end
	local ctr = WT.Centers[pi]
	local function pt(g)
		local a = math.rad(g[1])
		return ctr.X + cos(a) * g[2], ctr.Z + sin(a) * g[2]
	end
	local px, pz = pt(Game.Race.start)
	for _, g in Game.Race.gates do
		local qx, qz = pt(g)
		local dx, dz = qx - px, qz - pz
		local len2 = dx * dx + dz * dz
		local t = len2 > 0 and math.clamp(((x - px) * dx + (z - pz) * dz) / len2, 0, 1) or 0
		local ex, ez = px + dx * t - x, pz + dz * t - z
		if ex * ex + ez * ez < 12 * 12 then return true end
		px, pz = qx, qz
	end
	return false
end
Map.onRacePath = onRacePath
local function free(pi, x, z)
	local ctr = WT.Centers[pi]
	if onRacePath(pi, x, z) then return false end
	local dx, dz = x - ctr.X, z - ctr.Z
	local r = math.sqrt(dx * dx + dz * dz)
	if r < 44 or r > WT.PlayRadius - 4 then return false end
	-- Туманность: под спиралью паркура и рядом с ней пусто, ничего не мешает прыжкам
	if pi == 5 and r < 64 then return false end
	for j = 1, Map.SlotsPerPlanet do
		local cf = slotCF(pi, j)
		local lp = cf:PointToObjectSpace(V3(x, ctr.Y, z))
		if math.abs(lp.X) < 40 and lp.Z > -34 and lp.Z < 44 then return false end
		-- дорожка к огороду
		local ang = select(2, slotCF(pi, j))
		local along = dx * cos(ang) + dz * sin(ang)
		local across = math.abs(-dx * sin(ang) + dz * cos(ang))
		if along > 20 and along < Map.PlotRing - 24 and across < 7 then return false end
	end
	return true
end

function Map.buildFlora()
	if world:FindFirstChild("Flora") then return end
	local fl = Instance.new("Folder")
	fl.Name = "Flora"
	fl.Parent = world
	local rng = Random.new(4242)
	for pi = 1, #WT.Centers do
		local ctr = WT.Centers[pi]
		local pid = Game.Planets[pi].id
		local mine = {}
		for _, p in Game.PlantList do
			if p.planet == pid then table.insert(mine, p.id) end
		end
		local placed, tries = 0, 0
		while placed < 58 and tries < 900 do
			tries += 1
			local a = rng:NextNumber(0, PI * 2)
			local r = rng:NextNumber(34, WT.PlayRadius - 6)
			local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
			if free(pi, x, z) then
				local id = mine[rng:NextInteger(1, #mine)]
				bigPlant(fl, id, V3(x, WT.groundY(x, z, pi), z), rng:NextNumber(1.5, 3.2), rng:NextNumber(0, PI * 2))
				placed += 1
			end
		end
	end
end

local function buildRocks(pi, parent)
	local ctr = WT.Centers[pi]
	local rng = Random.new(900 + pi)
	local col = WT.Colors[WT.Themes[pi].rim] or c(80, 76, 94)
	local n = 0
	for _ = 1, 400 do
		if n >= 52 then break end
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(34, WT.PlayRadius - 4)
		local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
		if free(pi, x, z) then
			n += 1
			local sz = rng:NextNumber(1.2, 5)
			local y = WT.groundY(x, z, pi)
			ell(parent, "Rock", CF(x, y + sz * 0.25, z) * A(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0), V3(sz * 1.6, sz, sz * 1.3), col, Mat.Slate, { CanCollide = sz > 2.5 })
		end
	end
end

local function buildBarrier(pi, parent)
	local ctr = WT.Centers[pi]
	local R = WT.PlayRadius
	for i = 1, 48 do
		local a0, a1 = (i - 1) / 48 * PI * 2, i / 48 * PI * 2
		local p0 = ctr + V3(cos(a0) * R, 40, sin(a0) * R)
		local p1 = ctr + V3(cos(a1) * R, 40, sin(a1) * R)
		part(parent, "Wall", V3(2, 120, (p1 - p0).Magnitude + 0.2), CFrame.lookAt((p0 + p1) / 2, p1), COL.hull, Mat.SmoothPlastic, { Transparency = 1, CanQuery = false })
	end
end

------------------------------------------------------------------ природа планет: кристаллы, скальные шпили, светящиеся стебли
-- палитра каждой планеты: стекло кристалла, свечение внутри, камень шпилей, жилы, стебли
local NATURE = {
	{ glass = c(196, 212, 255), core = c(150, 190, 255), rock = c(96, 96, 112), vein = c(170, 200, 255), stalk = c(200, 220, 255), stalks = true },
	{ glass = c(255, 130, 90), core = c(255, 170, 80), rock = c(70, 40, 36), vein = c(255, 120, 60), stalk = c(255, 160, 90), stalks = false },
	{ glass = c(170, 225, 255), core = c(110, 230, 255), rock = c(120, 160, 196), vein = c(140, 240, 255), stalk = c(160, 240, 255), stalks = false },
	{ glass = c(46, 30, 40), core = c(255, 110, 40), rock = c(36, 32, 38), vein = c(255, 120, 40), stalk = c(255, 140, 60), stalks = false },
	{ glass = c(200, 140, 255), core = c(255, 130, 220), rock = c(60, 48, 80), vein = c(190, 140, 255), stalk = c(140, 255, 220), stalks = true },
	{ glass = c(255, 232, 180), core = c(255, 210, 130), rock = c(150, 132, 104), vein = c(255, 220, 150), stalk = c(255, 230, 170), stalks = true },
}
-- кристалл: призма с заострённой верхушкой (два клина) и светящейся сердцевиной
local function crystal(parent, base, h, w, tilt, yaw, n)
	local cf = CF(base) * A(0, yaw, 0) * A(tilt, 0, 0)
	part(parent, "Crystal", V3(w, h, w), cf * CF(0, h / 2, 0), n.glass, Mat.Glass, { Transparency = 0.25, Reflectance = 0.15, CanCollide = h > 6 })
	local cap = cf * CF(0, h + w * 0.45, 0)
	for _, side in { 1, -1 } do
		local wp = Instance.new("WedgePart")
		wp.Name = "CrystalTip"
		wp.Size = V3(w, w * 0.9, w / 2)
		wp.CFrame = cap * A(0, side == 1 and 0 or PI, 0) * CF(0, 0, w / 4)
		wp.Color, wp.Material, wp.Transparency, wp.Reflectance = n.glass, Mat.Glass, 0.25, 0.15
		wp.Anchored, wp.CanCollide, wp.CastShadow, wp.CanTouch = true, false, false, false
		wp.Parent = parent
	end
	return deco(parent, "CrystalCore", V3(w * 0.32, h * 0.8, w * 0.32), cf * CF(0, h * 0.45, 0), n.core, Mat.Neon, { Transparency = 0.15 })
end
local function crystalCluster(parent, pos, s, rng, n)
	local m = Instance.new("Model")
	m.Name = "CrystalCluster"
	m.Parent = parent
	local k = rng:NextInteger(3, 6)
	local core
	for i = 1, k do
		local yaw = i / k * PI * 2 + rng:NextNumber(-0.3, 0.3)
		local big = i == 1
		local h = (big and rng:NextNumber(5, 8) or rng:NextNumber(2, 5)) * s
		local w = h * rng:NextNumber(0.22, 0.32)
		local off = big and V3() or V3(cos(yaw), 0, sin(yaw)) * w * 0.9
		local cc = crystal(m, pos + off - V3(0, 0.4, 0), h, w, big and rng:NextNumber(-0.1, 0.1) or rng:NextNumber(0.25, 0.6), yaw, n)
		core = core or cc
	end
	ell(m, "CrystalBase", CF(pos - V3(0, 0.2, 0)) * A(0, rng:NextNumber(0, 6), 0), V3(4.5 * s, 1.6 * s, 3.8 * s), n.rock, Mat.Slate, { CanCollide = false })
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness, glow.Shadows = n.core, 10 + 4 * s, 0.9, false
	glow.Parent = core
end
-- скальный шпиль из нескольких сужающихся блоков со светящимися жилами
local function spire(parent, pos, h, rng, n)
	local m = Instance.new("Model")
	m.Name = "RockSpire"
	m.Parent = parent
	local segs = rng:NextInteger(3, 5)
	local y, w = 0, h * 0.32
	local yaw = rng:NextNumber(0, PI * 2)
	local lean = V3(rng:NextNumber(-0.06, 0.06), 0, rng:NextNumber(-0.06, 0.06))
	for i = 1, segs do
		local sh = h / segs * rng:NextNumber(0.85, 1.15)
		local cf = CF(pos + V3(0, y + sh / 2, 0) + lean * y * 3) * A(rng:NextNumber(-0.06, 0.06), yaw + i * 0.35, rng:NextNumber(-0.06, 0.06))
		part(m, "Spire", V3(w, sh, w * 0.85), cf, n.rock:Lerp(c(20, 20, 26), i * 0.05), Mat.Slate)
		if i % 2 == 0 then
			deco(m, "SpireVein", V3(w * 1.02, 0.22, w * 0.87), cf * CF(0, sh * 0.2, 0), n.vein, Mat.Neon, { Transparency = 0.2 })
		end
		y += sh * 0.92
		w *= 0.74
	end
end
-- светящиеся стебли: тонкие изогнутые стволы с огоньком на конце
local function stalks(parent, pos, rng, n)
	local m = Instance.new("Model")
	m.Name = "GlowStalks"
	m.Parent = parent
	for _ = 1, rng:NextInteger(3, 6) do
		local a = rng:NextNumber(0, PI * 2)
		local p0 = pos + V3(cos(a), 0, sin(a)) * rng:NextNumber(0, 1.6)
		local h = rng:NextNumber(4, 9)
		local bend = V3(cos(a), 0, sin(a)) * rng:NextNumber(0.8, 2)
		local p1 = p0 + V3(0, h * 0.55, 0) + bend * 0.3
		local p2 = p0 + V3(0, h, 0) + bend
		seg(m, "Stalk", p0, p1, 0.22, n.rock:Lerp(n.stalk, 0.25), Mat.SmoothPlastic)
		seg(m, "Stalk", p1, p2, 0.16, n.rock:Lerp(n.stalk, 0.35), Mat.SmoothPlastic)
		ball(m, "StalkLight", p2, rng:NextNumber(0.5, 0.9), n.stalk, Mat.Neon)
	end
end
local function buildNature(pi, parent)
	local ctr = WT.Centers[pi]
	local n = NATURE[pi]
	local rng = Random.new(7300 + pi)
	local placed = { crystal = 0, spire = 0, stalk = 0 }
	local want = { crystal = 18, spire = 12, stalk = n.stalks and 14 or 0 }
	for _ = 1, 900 do
		local kind = placed.crystal < want.crystal and "crystal" or placed.spire < want.spire and "spire" or placed.stalk < want.stalk and "stalk" or nil
		if not kind then break end
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(50, WT.PlayRadius - 8)
		local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
		if free(pi, x, z) then
			local y = WT.groundY(x, z, pi)
			if kind == "crystal" then
				crystalCluster(parent, V3(x, y, z), rng:NextNumber(0.7, 1.5), rng, n)
			elseif kind == "spire" then
				spire(parent, V3(x, y - 0.5, z), rng:NextNumber(9, 20), rng, n)
			else
				stalks(parent, V3(x, y, z), rng, n)
			end
			placed[kind] += 1
		end
	end
end

function Map.padCF(pi)
	local ctr = WT.Centers[pi]
	return CF(ctr + V3(0, 3, 12)) * A(0, PI, 0)
end
Map.planetAt = WT.planetAt

------------------------------------------------------------------ чудо каждой планеты: чем дальше планета, тем зрелищнее
local function spot(pi, deg, r)
	r *= WT.Scale
	local ctr = WT.Centers[pi]
	local a = math.rad(deg)
	local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
	return V3(x, WT.groundY(x, z, pi), z)
end
local LANDMARK = {}

-- Луна: разбитый посадочный модуль с флагом
LANDMARK[1] = function(pi, f)
	local base = spot(pi, 90, 138)
	local cf = CF(base) * A(0.12, 0.6, 0.18)
	part(f, "LanderBody", V3(6, 4, 6), cf * CF(0, 4, 0), c(220, 180, 70), Mat.Foil)
	cyl(f, "LanderTop", cf * CF(0, 7, 0), 2.5, 4.5, c(200, 204, 214), Mat.Metal)
	for k = 0, 3 do
		local a = k * PI / 2 + PI / 4
		seg(f, "LanderLeg", (cf * CF(cos(a) * 2.6, 2.4, sin(a) * 2.6)).Position, (cf * CF(cos(a) * 5, 0, sin(a) * 5)).Position, 0.35, c(180, 184, 196), Mat.Metal)
		cyl(f, "LanderFoot", cf * CF(cos(a) * 5, 0.1, sin(a) * 5), 0.2, 1.4, c(180, 184, 196), Mat.Metal)
	end
	ell(f, "LanderDish", cf * CF(2.5, 9, 0) * A(0, 0, -0.6), V3(3.5, 0.5, 3.5), c(230, 232, 240), Mat.Metal)
	local flag = spot(pi, 96, 132)
	seg(f, "FlagPole", flag, flag + V3(0, 8, 0), 0.18, c(220, 220, 230), Mat.Metal)
	part(f, "Flag", V3(0.1, 2.2, 3.6), CF(flag + V3(0, 6.8, 1.8)), c(90, 140, 230), Mat.SmoothPlastic, { CanCollide = false })
end

-- Марс: каменные арки, марсоход и пыльные смерчи
LANDMARK[2] = function(pi, f)
	for k, deg in { 45, 180, 250 } do
		local base = spot(pi, deg, 140)
		local dir = A(0, math.rad(deg) + PI / 2, 0)
		local span, hgt = 14 + k * 3, 12 + k * 3
		for q = 0, 12 do
			local t = q / 12 * PI
			local p = base + (dir * CF(cos(t) * span, sin(t) * hgt, 0)).Position
			local sz = 4.5 - math.sin(t) * 1.2
			ell(f, "Arch", CF(p) * A(q, q * 0.7, 0), V3(sz * 1.3, sz, sz * 1.1), c(160 + q * 2, 80, 56), Mat.Sandstone)
		end
	end
	local rv = CF(spot(pi, 100, 132)) * A(0, 0.8, 0)
	part(f, "RoverBody", V3(5, 1.6, 3.4), rv * CF(0, 2.2, 0), c(220, 222, 230), Mat.Metal)
	part(f, "RoverPanel", V3(5.6, 0.2, 4.4), rv * CF(0, 3.2, 0), c(30, 50, 110), Mat.Glass)
	seg(f, "RoverMast", (rv * CF(1.8, 3, 0)).Position, (rv * CF(1.8, 5.5, 0)).Position, 0.25, c(200, 200, 210), Mat.Metal)
	part(f, "RoverCam", V3(0.8, 0.6, 1.2), rv * CF(1.8, 5.8, 0), c(40, 40, 50), Mat.Metal)
	for _, x in { -1.8, 0, 1.8 } do
		for _, z in { -1.9, 1.9 } do cyl(f, "Wheel", rv * CF(x, 0.8, z) * A(PI / 2, 0, 0), 0.6, 1.6, c(60, 56, 54), Mat.Rubber) end
	end
	for k, deg in { 20, 140, 250 } do
		local p = spot(pi, deg, 120)
		local dd = anchorPart(f, "DustDevil", CF(p + V3(0, 1, 0)), V3(6, 1, 6))
		emitter(dd, { Color = ColorSequence.new(c(214, 130, 90)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 6) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(2.5, 4), Rate = 40,
			Speed = NumberRange.new(10, 16), SpreadAngle = Vector2.new(8, 8), RotSpeed = NumberRange.new(-200, 200), Rotation = NumberRange.new(0, 360),
			EmissionDirection = Enum.NormalId.Top, Acceleration = V3(0, 2, 0), LightInfluence = 1 })
	end
end

-- Европа: ледяные шипы, бьющие гейзеры и огромное сияние в небе
LANDMARK[3] = function(pi, f)
	local rng = Random.new(33)
	for k = 1, 22 do
		local deg = (k - 1) * 360 / 22 + rng:NextNumber(-6, 6)
		local p = spot(pi, deg, rng:NextNumber(132, 150))
		if math.abs(deg - 225) < 16 then continue end
		local h = rng:NextNumber(8, 22)
		ell(f, "IceSpike", CF(p + V3(0, h * 0.42, 0)) * A(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)), V3(h * 0.22, h, h * 0.22),
			c(170, 220, 250), Mat.Glass, { Transparency = 0.2, CanCollide = false })
	end
	for k, deg in { 45, 165, 285 } do
		local p = spot(pi, deg, 128)
		cyl(f, "GeyserVent", CF(p + V3(0, 0.3, 0)), 0.6, 5, c(150, 190, 220), Mat.Ice)
		dcyl(f, "GeyserGlow", CF(p + V3(0, 0.62, 0)), 0.05, 3.6, c(120, 210, 255), Mat.Neon)
		local g = anchorPart(f, "Geyser", CF(p + V3(0, 1, 0)), V3(2, 1, 2))
		emitter(g, { Color = ColorSequence.new(c(235, 245, 255)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(2, 3), Rate = 60,
			Speed = NumberRange.new(30, 45), SpreadAngle = Vector2.new(6, 6), Acceleration = V3(0, -14, 0), EmissionDirection = Enum.NormalId.Top })
		light(g, c(140, 220, 255), 26, 1.2)
	end
	local ctr = WT.Centers[pi]
	for k = 0, 30 do
		local a = k / 30 * PI * 2
		local r = 120 * WT.Scale
		local h = 40 + math.sin(k * 0.8) * 12
		local col = c(90, 255, 190):Lerp(c(150, 120, 255), (math.sin(k * 0.5) + 1) / 2)
		deco(f, "SkyAurora", V3(26, h, 0.2), CFrame.lookAt(ctr + V3(cos(a) * r, 70 + h / 2, sin(a) * r), ctr + V3(0, 70 + h / 2, 0)) * A(0, PI / 2, 0), col, Mat.Neon, { Transparency = 0.84 })
	end
end

-- Ио: действующий вулкан с лавовым фонтаном и реками лавы
LANDMARK[4] = function(pi, f)
	-- конус из ландшафта: вогнутый профиль, рёбра-гребни, кратер с лавовым озером (на краю острова, чтобы не задеть огороды)
	local base = spot(pi, 0, 146)
	local t = workspace:FindFirstChildOfClass("Terrain")
	local H, R0, R1 = 40, 25, 8
	local function radiusAt(y) return R1 + (R0 - R1) * (1 - y / H) ^ 1.6 end
	local rng = Random.new(44)
	if t then
		for y = 0, H, 2 do
			t:FillCylinder(CF(base + V3(0, y + 1, 0)), 2.2, radiusAt(y), Mat.Basalt)
		end
		-- гребни по склонам
		for k = 0, 8 do
			local a = k / 9 * PI * 2 + rng:NextNumber(-0.2, 0.2)
			for q = 0, 8 do
				local y = H * (1 - q / 10) - 2
				local r = radiusAt(math.max(0, y)) - 1.5
				t:FillBall(base + V3(cos(a) * r, y, sin(a) * r), 2 + q * 0.3, k % 3 == 0 and Mat.Asphalt or Mat.Basalt)
			end
		end
		-- кратер и лава в нём
		t:FillBall(base + V3(0, H + 6, 0), R1 + 3.5, Mat.Air)
		t:FillCylinder(CF(base + V3(0, H - 1.5, 0)), 2, R1 + 1, Mat.CrackedLava)
		-- застывшие лавовые потоки
		for k = 0, 3 do
			local a = k * PI / 2 + 0.4
			for q = 1, 9 do
				local tq = q / 9
				local y = H * (1 - tq) - 0.5
				local r = radiusAt(math.max(0, y)) + 0.2
				t:FillBall(base + V3(cos(a + tq * 0.5) * r, y, sin(a + tq * 0.5) * r), 1.8 + tq, Mat.CrackedLava)
			end
		end
	end
	local y = H
	local top = base + V3(0, y, 0)
	ell(f, "LavaPool", CF(top - V3(0, 0.6, 0)), V3(R1 * 2 + 1, 1.2, R1 * 2 + 1), c(255, 110, 30), Mat.Neon, { CanCollide = false })
	local lp = anchorPart(f, "LavaFountain", CF(top + V3(0, 0.5, 0)), V3(4, 1, 4))
	emitter(lp, { Color = ColorSequence.new(c(255, 200, 80), c(255, 70, 20)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0.2) }),
		LightEmission = 1, Lifetime = NumberRange.new(1.5, 2.5), Rate = 70, Speed = NumberRange.new(25, 40), SpreadAngle = Vector2.new(25, 25), Acceleration = V3(0, -30, 0),
		EmissionDirection = Enum.NormalId.Top })
	emitter(lp, { Color = ColorSequence.new(c(60, 50, 50)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 14) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(5, 8), Rate = 6,
		Speed = NumberRange.new(6, 10), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top, Acceleration = V3(2, 1, 0) })
	light(lp, c(255, 120, 40), 60, 3)
	-- светящиеся ручьи лавы поверх застывших потоков
	for k = 0, 3 do
		local a = k * PI / 2 + 0.4
		local prev
		for q = 1, 9 do
			local tq = q / 9
			local yy = H * (1 - tq)
			local r = radiusAt(math.max(0, yy)) + 0.9
			local p = base + V3(cos(a + tq * 0.5) * r, yy + 0.4, sin(a + tq * 0.5) * r)
			if prev then seg(f, "LavaRiver", prev, p, 1.1 - tq * 0.4, c(255, 110 + tq * 40, 30), Mat.Neon) end
			prev = p
		end
	end
	for k, deg in { 120, 240 } do
		local p = spot(pi, deg, 136)
		ell(f, "LavaVent", CF(p + V3(0, 0.6, 0)), V3(7, 1.4, 7), c(40, 34, 36), Mat.Basalt)
		local v = anchorPart(f, "Embers", CF(p + V3(0, 1.4, 0)), V3(3, 1, 3))
		emitter(v, { Color = ColorSequence.new(c(255, 150, 60)), Size = NumberSequence.new(0.4, 0), LightEmission = 1, Lifetime = NumberRange.new(2, 3), Rate = 25,
			Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top })
		light(v, c(255, 120, 40), 24, 1.5)
	end
end

-- Туманность: парящие острова, светящиеся облака и сфера света
LANDMARK[5] = function(pi, f)
	local ctr = WT.Centers[pi]
	local rng = Random.new(55)
	for k = 1, 5 do
		local a = k / 5 * PI * 2 + 0.3
		local r = rng:NextNumber(60, 140) * WT.Scale
		local p = ctr + V3(cos(a) * r, rng:NextNumber(30, 55), sin(a) * r)
		local isl = Instance.new("Model")
		isl.Name = "FloatIsland"
		local s2 = rng:NextNumber(8, 14)
		local main = ell(isl, "Rock", CF(p), V3(s2 * 2, s2 * 0.8, s2 * 2), c(70, 60, 96), Mat.Slate, { CanCollide = false })
		ell(isl, "RockBottom", CF(p - V3(0, s2 * 0.6, 0)), V3(s2 * 1.2, s2 * 1.4, s2 * 1.2), c(60, 52, 84), Mat.Slate, { CanCollide = false })
		ell(isl, "Moss", CF(p + V3(0, s2 * 0.32, 0)), V3(s2 * 1.9, s2 * 0.25, s2 * 1.9), c(96, 220, 190), Mat.Grass, { CanCollide = false })
		local g = ball(isl, "Wisp", p + V3(0, s2 * 0.6 + 2, 0), 1.6, c(190, 140, 255), Mat.Neon)
		light(g, c(190, 140, 255), 24, 1.2)
		isl.PrimaryPart = main
		isl:SetAttribute("Drift", rng:NextNumber(0.03, 0.08))
		isl.Parent = f
	end
	for k = 1, 9 do
		local a = rng:NextNumber(0, PI * 2)
		local p = ctr + V3(cos(a) * rng:NextNumber(150, 290), rng:NextNumber(10, 90), sin(a) * rng:NextNumber(150, 290))
		ball(f, "NebulaCloud", p, rng:NextNumber(20, 45), ({ c(220, 110, 255), c(110, 200, 255), c(255, 120, 190) })[k % 3 + 1], Mat.Neon, { Transparency = 0.9 })
	end
	local orbP = spot(pi, 200, 138)
	ball(f, "LightOrb", orbP + V3(0, 14, 0), 9, c(230, 200, 255), Mat.Neon, { Transparency = 0.2 })
	ball(f, "LightOrbHalo", orbP + V3(0, 14, 0), 16, c(200, 140, 255), Mat.Neon, { Transparency = 0.85 })
	local lo = anchorPart(f, "OrbSparks", CF(orbP + V3(0, 14, 0)), V3(8, 8, 8))
	emitter(lo, { Color = ColorSequence.new(c(255, 220, 255)), Size = NumberSequence.new(0.5, 0), LightEmission = 1, Lifetime = NumberRange.new(2, 4), Rate = 30,
		Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180) })
	light(lo, c(220, 170, 255), 60, 2.5)
end

-- Звёздное ядро: золотой храм, огромная звезда рядом и кольца вокруг планеты
LANDMARK[6] = function(pi, f)
	local base = spot(pi, 90, 136)
	local gold = c(236, 196, 100)
	for i, sz in { 26, 20, 14 } do
		part(f, "TempleStep", V3(sz, 2.2, sz), CF(base + V3(0, (i - 0.5) * 2.2, 0)), gold:Lerp(c(120, 90, 50), 0.15 * i), Mat.Marble)
	end
	for k = 0, 7 do
		local a = k / 8 * PI * 2
		local p = base + V3(cos(a) * 9, 6.6, sin(a) * 9)
		cyl(f, "Column", CF(p + V3(0, 5, 0)), 10, 1.2, c(250, 236, 200), Mat.Marble)
		ball(f, "ColumnGem", p + V3(0, 10.6, 0), 1, gold, Mat.Neon)
	end
	part(f, "TempleRoof", V3(20, 1, 20), CF(base + V3(0, 17.3, 0)), gold, Mat.Metal)
	local gem = ell(f, "TempleGem", CF(base + V3(0, 22, 0)) * A(0, 0.4, 0), V3(4, 7, 4), c(255, 240, 180), Mat.Neon)
	light(gem, c(255, 220, 140), 50, 2.5)
	-- звезда-солнце рядом с планетой
	local ctr = WT.Centers[pi]
	local sun = ctr + V3(-380, 180, 260)
	-- звезда — картинка с мягкой короной, всегда повёрнута к игроку (вложенные прозрачные шары давали резкие кольца)
	local sp = anchorPart(f, "Star", CF(sun), V3(4, 4, 4))
	local bb = Instance.new("BillboardGui")
	bb.Name = "StarGlow"
	bb.Size = UDim2.new(520, 0, 520, 0)
	bb.LightInfluence = 0
	bb.Brightness = 1.6
	bb.AlwaysOnTop = false
	pcall(function() bb.MaxDistance = 1000000 end)
	bb.Parent = sp
	local im = Instance.new("ImageLabel")
	im.BackgroundTransparency = 1
	im.Size = UDim2.fromScale(1, 1)
	im.Image = PlanetImg.sun or ""
	im.Parent = bb
	-- кольца вокруг планеты
	for ri, R in { 205, 230 } do
		local tilt = A(0.22 * ri, 0.3, 0.1)
		for k = 1, 64 do
			local a0, a1 = (k - 1) / 64 * PI * 2, k / 64 * PI * 2
			local p0 = ctr + (tilt * CF(cos(a0) * R, 0, sin(a0) * R)).Position - V3(0, 20, 0)
			local p1 = ctr + (tilt * CF(cos(a1) * R, 0, sin(a1) * R)).Position - V3(0, 20, 0)
			deco(f, "Ring", V3(ri == 1 and 6 or 3, 0.3, (p1 - p0).Magnitude + 0.3), CFrame.lookAt((p0 + p1) / 2, p1), ri == 1 and c(255, 220, 150) or c(200, 170, 255), Mat.Neon, { Transparency = 0.55 })
		end
	end
end

------------------------------------------------------------------ места, ради которых возвращаются на старые планеты
Map.spots = {}
local FEATURE = {}
local function featureSpot(pi, deg, r)
	r *= WT.Scale
	local ctr = WT.Centers[pi]
	local a = math.rad(deg)
	local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
	return V3(x, Map.surfaceY(x, z, pi), z), V3(cos(a), 0, sin(a))
end
-- ровная площадка под постройкой: над уровнем пусто, под ним земля
local function clearPad(pi, pos, radius, height)
	local t = workspace:FindFirstChildOfClass("Terrain")
	if not t then return end
	t:FillCylinder(CF(pos + V3(0, height / 2 + 0.05, 0)), height, radius, Mat.Air)
	t:FillCylinder(CF(pos - V3(0, 5, 0)), 10, radius, WT.Themes[pi].base)
end

-- Луна: алхимическая лаборатория под стеклянным куполом с котлом
FEATURE[1] = function(pi, f)
	local base, out = featureSpot(pi, 0, 128)
	clearPad(pi, base, 18, 28)
	local m = Instance.new("Model")
	m.Name = "AlchemyLab"
	m.Parent = f
	local face = CFrame.lookAt(base, base - out)
	local purple, green = c(170, 100, 255), c(120, 255, 170)
	cyl(m, "Floor", face * CF(0, 0.6, 0), 1.6, 30, c(58, 54, 78), Mat.Slate)
	dcyl(m, "FloorGlow", face * CF(0, 1.42, 0), 0.06, 28.6, purple, Mat.Neon, { Transparency = 0.55 })
	dcyl(m, "FloorInner", face * CF(0, 1.44, 0), 0.06, 27.8, c(48, 44, 66), Mat.Slate)
	-- кристаллические колонны и парящий купол
	for k = 0, 7 do
		local a = k / 8 * PI * 2 + PI / 8
		local p0 = (face * CF(cos(a) * 13, 1.4, sin(a) * 13)).Position
		if k ~= 6 and k ~= 5 then
			part(m, "Pillar", V3(1.4, 12, 1.4), CF(p0 + V3(0, 6, 0)) * A(0, a, 0), c(80, 76, 110), Mat.Marble)
			ball(m, "PillarGem", p0 + V3(0, 12.6, 0), 1.3, k % 2 == 0 and purple or green, Mat.Neon)
		end
	end
	ell(m, "Dome", face * CF(0, 13, 0), V3(29, 14, 29), c(170, 140, 255), Mat.Glass, { Transparency = 0.78, CanCollide = false, CastShadow = false })
	ring(m, "DomeRing", face.Position, 13.8, 13.4, 0.8, 0.5, purple, Mat.Neon, 24)
	-- котёл
	local pot = face * CF(0, 1.4, 0)
	for k = 0, 2 do
		local a = k / 3 * PI * 2
		seg(m, "PotLeg", (pot * CF(cos(a) * 2.2, 2.2, sin(a) * 2.2)).Position, (pot * CF(cos(a) * 3.4, 0, sin(a) * 3.4)).Position, 0.5, c(40, 38, 50), Mat.Metal)
	end
	cyl(m, "Cauldron", pot * CF(0, 3.2, 0), 3.6, 7, c(36, 34, 46), Mat.Metal)
	ell(m, "CauldronBelly", pot * CF(0, 2.6, 0), V3(8, 4, 8), c(32, 30, 42), Mat.Metal)
	ring(m, "CauldronRim", pot.Position, 3.55, 5.05, 0.6, 0.5, c(200, 170, 90), Mat.Metal, 16)
	local brew = dcyl(m, "Brew", pot * CF(0, 4.9, 0), 0.2, 6.6, green, Mat.Neon)
	brew:SetAttribute("Pulse", 1)
	local bub = anchorPart(m, "Bubbles", pot * CF(0, 5.2, 0), V3(5, 0.4, 5))
	emitter(bub, { Color = ColorSequence.new(green, purple), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1.2) }), LightEmission = 1,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(1.2, 2.2), Rate = 26,
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top })
	emitter(bub, { Color = ColorSequence.new(c(200, 170, 255)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(3, 5), Rate = 5,
		Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top })
	light(bub, green, 30, 2.2)
	-- полки с колбами
	local rng = Random.new(11)
	for side = -1, 1, 2 do
		local shelf = face * CF(side * 9, 1.4, -6) * A(0, side * 0.6, 0)
		part(m, "Shelf", V3(6, 0.4, 2), shelf * CF(0, 2.4, 0), COL.wood, Mat.Wood)
		part(m, "Shelf", V3(6, 0.4, 2), shelf * CF(0, 4.6, 0), COL.wood, Mat.Wood)
		part(m, "ShelfSide", V3(0.4, 5, 2), shelf * CF(-3, 2.5, 0), COL.wood2, Mat.Wood)
		part(m, "ShelfSide", V3(0.4, 5, 2), shelf * CF(3, 2.5, 0), COL.wood2, Mat.Wood)
		for row = 0, 1 do
			for q = 0, 3 do
				local col = ({ purple, green, c(255, 140, 90), c(110, 200, 255) })[rng:NextInteger(1, 4)]
				local pp = (shelf * CF(-2.1 + q * 1.4, 3.1 + row * 2.2, 0)).Position
				ball(m, "Flask", pp, 0.9, col, Mat.Neon, { Transparency = 0.15 })
				seg(m, "FlaskNeck", pp + V3(0, 0.3, 0), pp + V3(0, 0.95, 0), 0.32, c(220, 230, 255), Mat.Glass, { Transparency = 0.4 })
			end
		end
	end
	-- руны на полу вокруг котла
	ring(m, "Runes", pot.Position, 6.5, 0.08, 0.35, 0.08, purple, Mat.Neon, 18, function(a) return math.floor(a * 3) % 2 == 0 end)
	local trig = anchorPart(m, "PromptPart", pot * CF(0, 3, 0), V3(8, 6, 8))
	local pr = prompt(trig, "Сварить из 3 плодов", "Алхимия", 12, "Open_alchemy")
	pr:SetAttribute("Window", "alchemy")
	holoSign(m, base + V3(0, 22, 0), "АЛХИМИЯ", c(200, 150, 255), "3 плода = редкое семя")
	Map.spots.alchemy = pot.Position
end

-- Марс: трасса гонки в пыльной буре: стартовая арка, 13 ворот и ускорители
FEATURE[2] = function(pi, f)
	local ctr = WT.Centers[pi]
	local m = Instance.new("Folder")
	m.Name = "RaceTrack"
	m.Parent = f
	local orange, sand = c(255, 140, 60), c(150, 80, 56)
	local function at(deg, r)
		local a = math.rad(deg)
		local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
		return V3(x, Map.surfaceY(x, z, pi), z)
	end
	local pts = {}
	for i, g in Game.Race.gates do pts[i] = at(g[1], g[2]) end
	local startP = at(Game.Race.start[1], Game.Race.start[2])
	for i, p in pts do
		local prev = i == 1 and startP or pts[i - 1]
		local dir = (p - prev) * V3(1, 0, 1)
		dir = dir.Magnitude > 0.1 and dir.Unit or V3(1, 0, 0)
		local gcf = CFrame.lookAt(p, p + dir)
		local g = Instance.new("Model")
		g.Name = "RaceGate" .. i
		g:SetAttribute("RaceGate", i)
		g.Parent = m
		if i == #pts then
			-- старт и финиш: большая арка с шахматным баннером
			for _, sx in { -9, 9 } do
				part(g, "GatePillar", V3(1.6, 14, 1.6), gcf * CF(sx, 7, 0), c(40, 36, 40), Mat.Metal)
				part(g, "GateGlow", V3(0.5, 13, 0.5), gcf * CF(sx, 7, -0.9), orange, Mat.Neon, { CanCollide = false })
			end
			for q = 0, 13 do
				for row = 0, 1 do
					part(g, "Checker", V3(1.4, 1.4, 0.6), gcf * CF(-9.1 + q * 1.4, 13.3 + row * 1.4, 0), (q + row) % 2 == 0 and c(20, 20, 24) or c(240, 240, 240), Mat.SmoothPlastic, { CanCollide = false })
				end
			end
			local ban = part(g, "Banner", V3(14, 2.4, 0.3), gcf * CF(0, 10.6, 0), c(40, 20, 16), Mat.SmoothPlastic, { CanCollide = false })
			surfaceText(ban, Enum.NormalId.Front, "ПЫЛЬНАЯ ГОНКА", orange, 30)
			surfaceText(ban, Enum.NormalId.Back, "ПЫЛЬНАЯ ГОНКА", orange, 30)
			deco(g, "StartLine", V3(18, 0.1, 1.2), gcf * CF(0, 0.08, 0), c(240, 240, 240), Mat.SmoothPlastic)
			local trig = anchorPart(g, "RacePrompt", gcf * CF(-12, 2, 3), V3(4, 4, 4))
			local pr = prompt(trig, "Начать гонку", "Пыльная гонка", 12, "Game_race")
			pr:SetAttribute("Game", "race")
			part(g, "RaceKiosk", V3(3, 3, 2), gcf * CF(-12, 1.5, 3), c(70, 40, 30), Mat.Metal)
			ball(g, "RaceKioskLamp", (gcf * CF(-12, 3.4, 3)).Position, 0.8, orange, Mat.Neon)
			local _, sub = holoSign(g, p + V3(0, 20, 0), "ПЫЛЬНАЯ ГОНКА", c(255, 170, 90), "13 ворот, золото до 45 с")
			sub.Parent:SetAttribute("RaceBest", true)
			Map.spots.raceStart = p
		else
			for _, sx in { -6, 6 } do
				part(g, "GatePillar", V3(1, 9, 1), gcf * CF(sx, 4.5, 0), c(60, 40, 36), Mat.Metal, { CanCollide = false })
				part(g, "GateGlow", V3(0.4, 8.6, 0.4), gcf * CF(sx, 4.5, -0.6), orange, Mat.Neon, { CanCollide = false, Transparency = 0.35 })
			end
			part(g, "GateTop", V3(13, 0.8, 0.8), gcf * CF(0, 9.2, 0), orange, Mat.Neon, { CanCollide = false, Transparency = 0.35 })
			local num = anchorPart(g, "GateNum", gcf * CF(0, 11.5, 0), V3(1, 1, 1))
			local bb = Instance.new("BillboardGui")
			bb.Size, bb.LightInfluence, bb.MaxDistance = UDim2.fromOffset(60, 40), 0, 260
			bb.Parent = num
			local t = Instance.new("TextLabel")
			t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
			t.Text, t.TextColor3, t.TextStrokeTransparency = tostring(i), orange, 0.3
			t.Parent = bb
		end
		-- опора модели: центр прохода на земле (после сборки, иначе Roblox пересчитает её по деталям)
		g.WorldPivot = gcf
	end
	-- ускорители на длинных прямых
	for _, leg in { 2, 3, 4, 6, 7, 8, 11, 12, 13 } do
		local a, b = pts[leg - 1], pts[leg]
		local mid = a:Lerp(b, 0.4)
		local y = Map.surfaceY(mid.X, mid.Z, pi)
		local dir = (b - a) * V3(1, 0, 1)
		local pcf = CFrame.lookAt(V3(mid.X, y + 0.2, mid.Z), V3(mid.X, y + 0.2, mid.Z) + dir.Unit)
		local cyan = c(80, 230, 255)
		part(m, "BoostBase", V3(9, 0.3, 11), pcf * CF(0, -0.05, 0), c(20, 40, 60), Mat.Metal, { CanCollide = false })
		local pad = part(m, "BoostPad", V3(8, 0.3, 10), pcf, cyan, Mat.Neon, { CanCollide = false, Transparency = 0.25 })
		pad:SetAttribute("Boost", true)
		for q = 0, 2 do
			deco(m, "BoostArrow", V3(4, 0.36, 0.7), pcf * CF(-1.4, 0.06, 3 - q * 3) * A(0, PI / 4, 0), c(240, 255, 255), Mat.Neon)
			deco(m, "BoostArrow", V3(4, 0.36, 0.7), pcf * CF(1.4, 0.06, 3 - q * 3) * A(0, -PI / 4, 0), c(240, 255, 255), Mat.Neon)
		end
		-- стоячие стрелки по бокам: видно издалека на бегу
		for _, sx in { -5.2, 5.2 } do
			part(m, "BoostPost", V3(0.4, 5, 0.4), pcf * CF(sx, 2.5, 0), c(40, 60, 80), Mat.Metal, { CanCollide = false })
			deco(m, "BoostFlag", V3(0.2, 1.6, 2.6), pcf * CF(sx, 4.6, 0), cyan, Mat.Neon)
		end
		local lp = anchorPart(m, "BoostLight", pcf * CF(0, 2, 0), V3(1, 1, 1))
		light(lp, cyan, 22, 1.6)
		local bb = Instance.new("BillboardGui")
		bb.Size, bb.StudsOffset, bb.LightInfluence, bb.MaxDistance = UDim2.fromOffset(140, 34), V3(0, 4, 0), 0, 180
		bb.Parent = lp
		local bt = Instance.new("TextLabel")
		bt.Size, bt.BackgroundTransparency, bt.TextScaled, bt.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
		bt.Text, bt.TextColor3, bt.TextStrokeTransparency = ">> УСКОРЕНИЕ >>", cyan, 0.3
		bt.Parent = bb
	end
	local _ = sand
end

-- Европа: метеорная пушка на краю ледяного острова
FEATURE[3] = function(pi, f)
	local base, out = featureSpot(pi, 225, 130)
	clearPad(pi, base, 16, 30)
	local m = Instance.new("Model")
	m.Name = "MeteorCannon"
	m.Parent = f
	local face = CFrame.lookAt(base, base + out)
	local ice, steel, cyan = c(170, 215, 240), c(70, 82, 110), c(90, 220, 255)
	cyl(m, "Base", face * CF(0, 0.7, 0), 1.8, 26, c(60, 72, 96), Mat.DiamondPlate)
	dcyl(m, "BaseGlow", face * CF(0, 1.62, 0), 0.06, 25.4, cyan, Mat.Neon, { Transparency = 0.45 })
	dcyl(m, "BaseInner", face * CF(0, 1.64, 0), 0.06, 24.6, c(60, 72, 96), Mat.DiamondPlate)
	cyl(m, "Turret", face * CF(0, 3.6, 0), 4.2, 12, steel, Mat.Metal)
	dcyl(m, "TurretRing", face * CF(0, 5.6, 0), 0.5, 12.4, cyan, Mat.Neon)
	for side = -1, 1, 2 do
		part(m, "Yoke", V3(1.2, 5, 3), face * CF(side * 3.6, 7.6, 0), steel:Lerp(c(0, 0, 0), 0.15), Mat.Metal)
	end
	-- ствол смотрит наружу, в космос, под углом вверх
	local pivot = face * CF(0, 8.4, 0)
	local barrel = Instance.new("Model")
	barrel.Name = "Barrel"
	barrel.Parent = m
	local bcf = pivot * A(math.rad(35), 0, 0)
	local tube = part(barrel, "Tube", V3(18, 4, 4), bcf * CF(0, 0, -7) * A(0, PI / 2, 0), steel, Mat.Metal, { Shape = Enum.PartType.Cylinder })
	for q = 0, 2 do
		dcyl(barrel, "TubeRing", bcf * CF(0, 0, -3 - q * 4.8) * A(PI / 2, 0, 0), 0.6, 4.7, cyan, Mat.Neon)
	end
	dcyl(barrel, "MuzzleRim", bcf * CF(0, 0, -16) * A(PI / 2, 0, 0), 1.2, 5.2, steel:Lerp(c(255, 255, 255), 0.2), Mat.Metal)
	ball(barrel, "Muzzle", (bcf * CF(0, 0, -16.4)).Position, 3.6, cyan, Mat.Neon, { Transparency = 0.2 })
	ell(barrel, "Breech", bcf * CF(0, 0, 2.2), V3(5.6, 5.6, 7), steel:Lerp(c(0, 0, 0), 0.2), Mat.Metal)
	barrel.PrimaryPart = tube
	barrel:SetAttribute("Pivot", pivot)
	-- ящики со снарядами и ледяные кристаллы
	for side = -1, 1, 2 do
		part(m, "AmmoBox", V3(3, 2, 2.2), face * CF(side * 8.5, 2.6, 4) * A(0, side * 0.3, 0), c(60, 70, 90), Mat.DiamondPlate)
		ball(m, "AmmoGlow", (face * CF(side * 8.5, 3.8, 4)).Position, 1, cyan, Mat.Neon)
		ell(m, "IceCrystal", face * CF(side * 11.5, 3, -4) * A(0.2 * side, 0, 0.3), V3(1.8, 7, 1.8), ice, Mat.Glass, { Transparency = 0.25, CanCollide = false })
	end
	local trig = anchorPart(m, "PromptPart", face * CF(0, 3, 7), V3(6, 4, 6))
	local pr = prompt(trig, "Сбивать метеориты", "Метеорная пушка", 12, "Game_cannon")
	pr:SetAttribute("Game", "cannon")
	local _, sub = holoSign(m, base + V3(0, 24, 0), "МЕТЕОРНАЯ ПУШКА", c(120, 220, 255), "сбивай метеориты = редкие семена")
	sub.Parent:SetAttribute("Cooldown", "cannon")
	Map.spots.cannon = (face * CF(0, 3, 0)).Position
	Map.spots.cannonDir = out
end

-- Ио: лавовое озеро с каменным причалом для рыбалки
FEATURE[4] = function(pi, f)
	local lakeC, out = featureSpot(pi, 180, 134)
	clearPad(pi, lakeC, 36, 70)
	local m = Instance.new("Model")
	m.Name = "LavaLake"
	m.Parent = f
	-- чаша над землёй: ландшафт округляется блоками по 4 стада и мог бы скрыть тонкую лаву
	local y = lakeC.Y + 2.6
	cyl(m, "LakeBowl", CF(lakeC.X, y - 1.6, lakeC.Z), 3.6, 15 * 2 + 5, c(48, 42, 46), Mat.Basalt)
	local R = 15
	local lava, crust, rock = c(255, 110, 30), c(70, 40, 34), c(52, 46, 50)
	-- чаша: каменный бортик из глыб и тёмная корка по краю
	local rng = Random.new(77)
	for k = 0, 17 do
		local a = k / 18 * PI * 2
		local r = R + 1.6
		local sz = rng:NextNumber(2.4, 4)
		ell(m, "LakeRim", CF(lakeC.X + cos(a) * r, y + sz * 0.2, lakeC.Z + sin(a) * r) * A(0, rng:NextNumber(0, 6), 0), V3(sz * 1.6, sz * 0.9, sz * 1.3), rock, Mat.Basalt)
	end
	cyl(m, "LakeCrust", CF(lakeC.X, y + 0.05, lakeC.Z), 0.3, R * 2 + 2, crust, Mat.CrackedLava, { CanCollide = false })
	local surf = cyl(m, "LakeLava", CF(lakeC.X, y + 0.25, lakeC.Z), 0.3, R * 2, lava, Mat.Neon, { CanCollide = false })
	surf:SetAttribute("Pulse", 1)
	for k = 1, 6 do
		local a = rng:NextNumber(0, PI * 2)
		local r = rng:NextNumber(2, R - 4)
		ell(m, "LavaCrustIsle", CF(lakeC.X + cos(a) * r, y + 0.45, lakeC.Z + sin(a) * r) * A(0, a, 0), V3(rng:NextNumber(2, 4), 0.4, rng:NextNumber(1.5, 3)), crust, Mat.CrackedLava, { CanCollide = false })
	end
	local bub = anchorPart(m, "LakeBubbles", CF(lakeC.X, y + 0.5, lakeC.Z), V3(R * 1.6, 0.4, R * 1.6))
	emitter(bub, { Color = ColorSequence.new(c(255, 200, 90), c(255, 80, 20)), Size = NumberSequence.new(0.6, 0), LightEmission = 1, Lifetime = NumberRange.new(0.8, 1.6),
		Rate = 18, Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(15, 15), Acceleration = V3(0, -14, 0), EmissionDirection = Enum.NormalId.Top })
	emitter(bub, { Color = ColorSequence.new(c(80, 60, 60)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 7) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(3, 5), Rate = 3,
		Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Top })
	light(bub, c(255, 120, 40), 50, 2.5)
	-- причал со стороны площади
	local inward = -out
	local pierStart = lakeC + inward * (R + 9)
	local face = CFrame.lookAt(V3(pierStart.X, y + 1.2, pierStart.Z), V3(lakeC.X, y + 1.2, lakeC.Z))
	part(m, "Pier", V3(6, 0.8, 16), face * CF(0, 0, -6), c(64, 56, 58), Mat.Slate)
	for k = 1, 4 do
		part(m, "PierStep", V3(6, 0.8, 2), face * CF(0, -k * 0.9, 1 + k * 1.8), c(64, 56, 58), Mat.Slate)
	end
	for side = -1, 1, 2 do
		for q = 0, 2 do
			cyl(m, "PierPost", face * CF(side * 2.6, -1.2, -1 - q * 5.5), 3.2, 0.8, c(40, 34, 36), Mat.Basalt)
			ball(m, "PierLamp", (face * CF(side * 2.6, 1.6, -1 - q * 5.5)).Position, 0.5, c(255, 170, 80), Mat.Neon)
		end
	end
	-- удочка на стойке на конце причала
	local tip = face * CF(1.4, 0.4, -12.5)
	part(m, "RodStand", V3(0.6, 1.6, 0.6), tip * CF(0, 0.8, 0), c(40, 34, 36), Mat.Metal)
	seg(m, "FishingRod", (tip * CF(0, 1.4, 0)).Position, (tip * CF(0, 6.5, -6)).Position, 0.25, c(120, 80, 50), Mat.Wood)
	ball(m, "RodTip", (tip * CF(0, 6.5, -6)).Position, 0.35, c(255, 200, 90), Mat.Neon)
	local trig = anchorPart(m, "FishPrompt", face * CF(0, 1.5, -10), V3(5, 3, 5))
	local pr = prompt(trig, "Рыбачить", "Лавовое озеро", 12, "Game_fishing")
	pr:SetAttribute("Game", "fishing")
	local _, sub = holoSign(m, lakeC + V3(0, 18, 0), "ЛАВОВАЯ РЫБАЛКА", c(255, 160, 80), "лови огненных рыб и редкие семена")
	sub.Parent.MaxDistance = 900
	-- столб света над озером: видно со всей планеты
	local beam = part(m, "LakeBeacon", V3(160, 2.2, 2.2), CF(lakeC.X, y + 80, lakeC.Z) * A(0, 0, PI / 2), c(255, 140, 50), Mat.Neon,
		{ Shape = Enum.PartType.Cylinder, CanCollide = false, CastShadow = false, Transparency = 0.55 })
	beam.CanQuery = false
	-- дорожка фонарей от площади к причалу
	local ctr = WT.Centers[pi]
	local from = ctr + (lakeC - ctr) * V3(1, 0, 1).Unit * 42
	local to = pierStart
	local dir = (to - from) * V3(1, 0, 1)
	local steps = math.floor(dir.Magnitude / 12)
	for q = 1, steps do
		local pp = from + dir * (q / (steps + 1))
		local gy = Map.surfaceY(pp.X, pp.Z, pi)
		local side = (q % 2 == 0) and 1 or -1
		local off = dir.Unit:Cross(V3(0, 1, 0)) * 4 * side
		local lp = V3(pp.X, gy, pp.Z) + off
		seg(m, "PathLampPost", lp, lp + V3(0, 3.6, 0), 0.25, c(50, 42, 44), Mat.Metal)
		local b = ball(m, "PathLamp", lp + V3(0, 3.9, 0), 0.7, c(255, 150, 70), Mat.Neon)
		if q % 2 == 0 then light(b, c(255, 140, 60), 14, 0.8) end
	end
	-- указатель на площади
	local sp = ctr + (lakeC - ctr) * V3(1, 0, 1).Unit * 41
	local sgy = Map.surfaceY(sp.X, sp.Z, pi)
	local scf = CFrame.lookAt(V3(sp.X, sgy, sp.Z), V3(lakeC.X, sgy, lakeC.Z)) * A(0, PI / 2, 0)
	part(m, "SignpostPole", V3(0.4, 5, 0.4), scf * CF(0, 2.5, 0), c(60, 50, 50), Mat.Wood)
	local arrow = part(m, "Signpost", V3(5, 1.2, 0.3), scf * CF(1.6, 4.4, 0), c(90, 50, 30), Mat.Wood, { CanCollide = false })
	surfaceText(arrow, Enum.NormalId.Front, "РЫБАЛКА →", c(255, 190, 120), 30)
	surfaceText(arrow, Enum.NormalId.Back, "← РЫБАЛКА", c(255, 190, 120), 30)
	Map.spots.fishing = (face * CF(0, 1.5, -10)).Position
	Map.spots.fishLake = V3(lakeC.X, y, lakeC.Z)
	Map.spots.fishRod = (tip * CF(0, 6.5, -6)).Position
end

-- Туманность: спутники над островом. По их спирали можно забраться к сундуку на орбитальной станции
local function satellite(parent, cf, d, walk, tint)
	local gold, panel = c(225, 190, 110), c(60, 90, 190)
	local top = cyl(parent, walk and "SatDeck" or "SatBody", cf, 1, d, c(205, 210, 225), Mat.Metal, walk and {} or { CanCollide = false })
	dcyl(parent, "SatDeckGlow", cf * CF(0, 0.52, 0), 0.04, d - 0.6, tint, Mat.Neon, { Transparency = 0.5 })
	dcyl(parent, "SatHull", cf * CF(0, -1.6, 0), 2.4, d * 0.55, gold, Mat.Foil)
	ell(parent, "SatDish", cf * CF(0, -3.2, 0) * A(PI, 0, 0), V3(d * 0.5, 0.8, d * 0.5), c(235, 238, 245), Mat.Metal, { CanCollide = false })
	for side = -1, 1, 2 do
		part(parent, walk and "SatWing" or "SatWingDeco", V3(d * 0.75, 0.3, d * 0.4), cf * CF(side * d * 0.85, -0.1, 0), panel, Mat.Glass,
			walk and { Reflectance = 0.2 } or { CanCollide = false, Reflectance = 0.2 })
		deco(parent, "SatWingEdge", V3(d * 0.75, 0.32, 0.18), cf * CF(side * d * 0.85, -0.1, d * 0.2), tint, Mat.Neon)
	end
	local blink = ball(parent, "SatBlink", (cf * CF(0, -3.6, 0)).Position, 0.6, tint, Mat.Neon)
	blink:SetAttribute("Blink", 1)
	return top
end
FEATURE[5] = function(pi, f)
	local ctr = WT.Centers[pi]
	local gy = Map.surfaceY(ctr.X, ctr.Z, pi)
	local m = Instance.new("Folder")
	m.Name = "SatelliteSpiral"
	m.Parent = f
	local tints = { c(120, 220, 255), c(220, 130, 255), c(255, 150, 200) }
	local R, steps, step, rise = 46, 32, 0.27, 3.6
	local a0 = math.rad(200)
	local lastY = gy
	for k = 1, steps do
		local a = a0 + k * step
		local x, z = ctr.X + cos(a) * R, ctr.Z + sin(a) * R
		local y = gy + 3.2 + (k - 1) * rise
		if k == 1 then y = math.max(y, Map.surfaceY(x, z, pi) + 3) end
		if k == 1 then Map.spots.spiralStart = V3(x, y, z) end
		local rest = k % 11 == 0
		local cf = CFrame.lookAt(V3(x, y, z), V3(ctr.X, y, ctr.Z))
		satellite(m, cf * A(0, PI / 2, 0), rest and 11 or 7.5, true, tints[(k // 11) % 3 + 1])
		if rest then
			ring(m, "Checkpoint", V3(x, y, z), 5.2, 2.6, 0.4, 0.4, c(140, 255, 200), Mat.Neon, 14, nil, { Transparency = 0.3 })
		end
		lastY = y
	end
	-- орбитальная станция с сундуком
	local aS = a0 + (steps + 1.6) * step
	local sp = V3(ctr.X + cos(aS) * (R - 6), lastY + 4.2, ctr.Z + sin(aS) * (R - 6))
	local scf = CFrame.lookAt(sp, V3(ctr.X, sp.Y, ctr.Z))
	cyl(m, "Station", scf, 1.2, 22, c(210, 214, 230), Mat.Metal)
	dcyl(m, "StationGlow", scf * CF(0, 0.62, 0), 0.05, 21.4, c(255, 210, 120), Mat.Neon, { Transparency = 0.4 })
	dcyl(m, "StationInner", scf * CF(0, 0.64, 0), 0.05, 20.4, c(200, 204, 222), Mat.Metal)
	dcyl(m, "StationHull", scf * CF(0, -2.5, 0), 4, 12, c(225, 190, 110), Mat.Foil)
	ring(m, "StationRing", sp - V3(0, 2.5, 0), 14, 0, 1.2, 1.2, c(180, 140, 255), Mat.Neon, 28, nil, { Transparency = 0.2 })
	for side = -1, 1, 2 do
		deco(m, "StationPanel", V3(18, 0.3, 6), scf * CF(side * 22, -2.5, 0), c(60, 90, 190), Mat.Glass, { Reflectance = 0.2 })
	end
	-- сундук
	local chest = Instance.new("Model")
	chest.Name = "StarChest"
	chest.Parent = m
	local ccf = scf * CF(0, 0.6, 0)
	part(chest, "ChestBase", V3(4.4, 2.4, 3), ccf * CF(0, 1.2, 0), c(90, 60, 140), Mat.Wood)
	part(chest, "ChestLid", V3(4.6, 1, 3.2), ccf * CF(0, 2.9, 0), c(110, 70, 170), Mat.Wood)
	for sx = -1, 1, 2 do part(chest, "ChestBand", V3(0.4, 3.6, 3.3), ccf * CF(sx * 1.5, 1.8, 0), c(240, 200, 100), Mat.Metal) end
	local glow = ball(chest, "ChestGem", (ccf * CF(0, 2.2, -1.65)).Position, 0.9, c(255, 220, 120), Mat.Neon)
	light(glow, c(255, 210, 120), 26, 2)
	local cs = anchorPart(chest, "ChestSparks", ccf * CF(0, 3.5, 0), V3(4, 1, 3))
	emitter(cs, { Color = ColorSequence.new(c(255, 230, 150)), Size = NumberSequence.new(0.5, 0), LightEmission = 1, Lifetime = NumberRange.new(1, 2), Rate = 14,
		Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top })
	local pr = prompt(chest.ChestBase, "Открыть", "Звёздный сундук", 10, "Chest")
	pr:SetAttribute("Action", "chest")
	local _, sub = holoSign(m, sp + V3(0, 9, 0), "ЗВЁЗДНЫЙ СУНДУК", c(255, 215, 120), "забирайся по спутникам")
	sub.Parent:SetAttribute("Cooldown", "chest")
	holoSign(m, V3(ctr.X + cos(a0 + step) * R, gy + 9, ctr.Z + sin(a0 + step) * R), "ПАРКУР", c(150, 230, 255), "к сундуку на орбите")
	Map.spots.chest = ccf.Position
	-- спутники, которые кружат над островом (двигает клиент)
	local rng = Random.new(5)
	for k = 1, 7 do
		local sm = Instance.new("Model")
		sm.Name = "OrbitSat"
		local cf = CF(ctr + V3(0, 90, 0))
		local top = satellite(sm, cf, rng:NextNumber(5, 9), false, tints[k % 3 + 1])
		sm.PrimaryPart = top
		sm:SetAttribute("OrbitR", rng:NextNumber(110, 175))
		sm:SetAttribute("OrbitY", rng:NextNumber(70, 140))
		sm:SetAttribute("OrbitSpeed", rng:NextNumber(0.04, 0.09) * (k % 2 == 0 and -1 or 1))
		sm:SetAttribute("OrbitPhase", k / 7 * PI * 2)
		sm:SetAttribute("OrbitCenter", ctr)
		sm.Parent = m
	end
end

-- Ядро: смотровая площадка над бездной с телескопом и трамплином
FEATURE[6] = function(pi, f)
	local base, out = featureSpot(pi, 270, 126)
	local m = Instance.new("Model")
	m.Name = "Overlook"
	m.Parent = f
	local y = base.Y + 0.4
	local face = CFrame.lookAt(V3(base.X, y, base.Z), V3(base.X, y, base.Z) + out)
	local gold, marble, glow = c(236, 196, 100), c(240, 230, 210), c(255, 220, 140)
	local L = 74
	-- проход сквозь холмы на краю: мост виден и с площади
	local t = workspace:FindFirstChildOfClass("Terrain")
	if t then t:FillBlock(face * CF(0, 22, -26), V3(18, 44, 56), Mat.Air) end
	part(m, "Bridge", V3(12, 1, L), face * CF(0, -0.5, -L / 2), marble, Mat.Marble)
	part(m, "BridgeGlass", V3(6, 1.02, L - 6), face * CF(0, -0.49, -L / 2 - 2), c(255, 230, 170), Mat.Glass, { Transparency = 0.45 })
	for side = -1, 1, 2 do
		deco(m, "BridgeEdge", V3(0.3, 0.3, L), face * CF(side * 6, 0.1, -L / 2), glow, Mat.Neon)
		for q = 0, 6 do
			local zz = -6 - q * 10
			part(m, "RailPost", V3(0.5, 1.6, 0.5), face * CF(side * 5.6, 0.8, zz), gold, Mat.Metal)
			ball(m, "RailLamp", (face * CF(side * 5.6, 1.8, zz)).Position, 0.6, glow, Mat.Neon)
		end
		part(m, "Rail", V3(0.3, 0.3, L - 8), face * CF(side * 5.6, 1.4, -L / 2 - 2), gold, Mat.Metal)
		-- подпорки уходят вниз под край острова
		seg(m, "Strut", (face * CF(side * 5, -1, -L + 8)).Position, (face * CF(side * 3, -26, -8)).Position, 1.2, gold, Mat.Metal)
	end
	-- круглая площадка на конце
	local endCF = face * CF(0, 0, -L - 6)
	cyl(m, "Deck", endCF * CF(0, -0.5, 0), 1, 20, marble, Mat.Marble)
	dcyl(m, "DeckGlow", endCF * CF(0, 0.02, 0), 0.05, 19.4, glow, Mat.Neon, { Transparency = 0.35 })
	dcyl(m, "DeckInner", endCF * CF(0, 0.04, 0), 0.05, 18.6, marble, Mat.Marble)
	ell(m, "DeckUnder", endCF * CF(0, -4, 0), V3(16, 8, 16), gold, Mat.Metal)
	local ul = anchorPart(m, "DeckLight", endCF * CF(0, -8, 0), V3(2, 1, 2))
	light(ul, glow, 40, 2)
	-- телескоп сбоку от трамплина
	local tcf = endCF * CF(-5.5, 0, 1) * A(0, PI * 0.15, 0)
	for k = 0, 2 do
		local a = k / 3 * PI * 2
		seg(m, "TripodLeg", (tcf * CF(0, 4.2, 0)).Position, (tcf * CF(cos(a) * 1.8, 0, sin(a) * 1.8)).Position, 0.25, c(80, 60, 40), Mat.Metal)
	end
	local tube = tcf * CF(0, 4.6, 0) * A(math.rad(-18), 0, 0)
	part(m, "TelescopeTube", V3(6, 1.4, 1.4), tube * CF(0, 0, -1) * A(0, PI / 2, 0), gold, Mat.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	part(m, "TelescopeLens", V3(0.3, 1.7, 1.7), tube * CF(0, 0, -4) * A(0, PI / 2, 0), c(150, 200, 255), Mat.Glass, { Shape = Enum.PartType.Cylinder, CanCollide = false, Transparency = 0.2 })
	part(m, "TelescopeEye", V3(1, 0.6, 0.6), tube * CF(0, 0, 2.3) * A(0, PI / 2, 0), c(60, 50, 40), Mat.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })
	local trig = anchorPart(m, "TelescopePrompt", tcf * CF(0, 3, 0), V3(3, 4, 3))
	local pr = prompt(trig, "Посмотреть на планеты", "Телескоп", 10, "Game_telescope")
	pr:SetAttribute("Game", "telescope")
	Map.spots.telescope = (tube * CF(0, 0.4, 2.6)).Position
	-- трамплин: короткий мостик и площадка-катапульта
	local board = endCF * CF(3, 0, -10)
	part(m, "DiveBoard", V3(4, 0.6, 9), board * CF(0, -0.3, 0), gold, Mat.Metal)
	local pad = part(m, "LaunchPad", V3(4, 0.3, 3), board * CF(0, 0.1, -3.2), c(255, 140, 80), Mat.Neon)
	pad:SetAttribute("Launch", out * 70 + V3(0, 110, 0))
	local sign = part(m, "DiveSign", V3(5, 1.6, 0.3), board * CF(-3.2, 2.2, 2) * A(0, PI, 0), c(30, 24, 40), Mat.SmoothPlastic, { CanCollide = false })
	surfaceText(sign, Enum.NormalId.Front, "ПРЫЖОК В БЕЗДНУ", glow, 30)
	surfaceText(sign, Enum.NormalId.Back, "ПРЫЖОК В БЕЗДНУ", glow, 30)
	holoSign(m, endCF.Position + V3(0, 16, 0), "СМОТРОВАЯ", c(255, 220, 140), "телескоп и прыжок вниз")
end

------------------------------------------------------------------ фон
local function billboard(parent, name, image, pos, size, faceTo)
	-- картинка планеты на невидимой плоскости, повёрнутой к центру станции (SurfaceGui не зависит от прозрачности детали)
	local p = part(parent, name, V3(size, size, 0.2), CFrame.lookAt(pos, faceTo or V3(0, 0, 0)), c(255, 255, 255), Mat.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	gui.CanvasSize = Vector2.new(1024, 1024)
	gui.LightInfluence = 0
	pcall(function() gui.MaxDistance = 1000000 end)
	gui.Parent = p
	local img = Instance.new("ImageLabel")
	img.BackgroundTransparency = 1
	img.Size = UDim2.fromScale(1, 1)
	img.Image = image
	img.Parent = gui
	return p
end


local function buildBackdrop(parent)
	billboard(parent, "GasGiant", PlanetImg.gas, V3(5200, 1800, -6400), 6400)
	billboard(parent, "BlueWorld", PlanetImg.earth, V3(-6200, 900, -3000), 1800)
	-- чёрная дыра высоко над краем карты: видна, если поднять камеру, с любой планеты
	if PlanetImg.blackhole then
		local bh = billboard(parent, "BlackHole", PlanetImg.blackhole, V3(300, 3600, -2600), 2600, V3(0, 700, 0))
		bh:SetAttribute("BlackHole", true)
	end
	local rng = Random.new(404)
	local fl = Instance.new("Folder")
	fl.Name = "Drift"
	fl.Parent = parent
	for i = 1, 34 do
		local p = V3(rng:NextNumber(-1400, 1400), rng:NextNumber(-200, 1500), rng:NextNumber(-1400, 1400))
		local near = false
		for _, ctr in WT.Centers do
			if (p - ctr).Magnitude < 320 then near = true end
		end
		if not near then
			local s = rng:NextNumber(8, 34)
			local rock = Instance.new("Model")
			rock.Name = "Asteroid"
			rock.Parent = fl
			local main = ell(rock, "Main", CF(p) * A(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0), V3(s * 1.4, s, s * 1.2), c(88, 82, 96), Mat.Slate, { CanCollide = false, CastShadow = false })
			rock.PrimaryPart = main
			rock:SetAttribute("Drift", rng:NextNumber(0.02, 0.07) * (i % 2 == 0 and 1 or -1))
		end
	end
end

------------------------------------------------------------------ освещение и небо
local function buildLighting()
	for _, ch in Lighting:GetChildren() do
		if ch:IsA("Sky") or ch:IsA("BloomEffect") or ch:IsA("ColorCorrectionEffect") or ch:IsA("SunRaysEffect") or ch:IsA("Atmosphere") then ch:Destroy() end
	end
	Lighting.ClockTime = 17.2
	Lighting.Brightness = 1.6
	Lighting.Ambient = c(70, 66, 110)
	Lighting.OutdoorAmbient = c(80, 78, 125)
	Lighting.ColorShift_Top = c(190, 170, 255)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.8
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = -0.1
	local sky = Instance.new("Sky")
	sky.SkyboxBk, sky.SkyboxDn, sky.SkyboxFt = SkyImg.Bk, SkyImg.Dn, SkyImg.Ft
	sky.SkyboxLf, sky.SkyboxRt, sky.SkyboxUp = SkyImg.Lf, SkyImg.Rt, SkyImg.Up
	sky.CelestialBodiesShown = false
	sky.StarCount = 0
	sky.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.22, 22, 2.2
	bloom.Parent = Lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Contrast, cc.Saturation, cc.Brightness = 0.12, -0.04, 0
	cc.TintColor = c(245, 240, 255)
	cc.Parent = Lighting
	-- лёгкая космическая дымка: глубина и кинематографичность вместо «пластика»
	local atm = Instance.new("Atmosphere")
	atm.Density, atm.Offset = 0.1, 0
	atm.Color, atm.Decay = c(96, 86, 150), c(40, 30, 80)
	atm.Glare, atm.Haze = 0.15, 0.6
	atm.Parent = Lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity, rays.Spread = 0.03, 0.5
	rays.Parent = Lighting
end


function Map.build()
	world = Instance.new("Folder")
	world.Name = "World"
	world.Parent = workspace
	workspace.Gravity = 120
	buildLighting()
	WT.build()
	local plotsFolder = Instance.new("Folder")
	plotsFolder.Name = "Plots"
	plotsFolder.Parent = world
	for pi = 1, #WT.Centers do
		local pf = Instance.new("Folder")
		pf.Name = "Planet" .. pi
		pf.Parent = world
		local slots = Instance.new("Folder")
		slots.Name = "Slots"
		slots.Parent = pf
		local P = { index = pi, center = WT.Centers[pi], markers = {}, plotsFolder = plotsFolder, slotFolder = slots }
		Map.planets[pi] = P
		buildHub(pi, pf)
		local lm = Instance.new("Folder")
		lm.Name = "Landmark"
		lm.Parent = pf
		if LANDMARK[pi] then LANDMARK[pi](pi, lm) end
		if FEATURE[pi] then FEATURE[pi](pi, lm) end
		for j = 1, Map.SlotsPerPlanet do
			P.markers[j] = slotMarker(pi, j, slots)
		end
		local rocks = Instance.new("Folder")
		rocks.Name = "Rocks"
		rocks.Parent = pf
		buildRocks(pi, rocks)
		buildNature(pi, rocks)
		-- стен по краю нет: с островов можно прыгать (падающих ловит сервер)
	end
	local bg = Instance.new("Folder")
	bg.Name = "Backdrop"
	bg.Parent = world
	buildBackdrop(bg)
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Spawn"
	spawn.Size, spawn.CFrame, spawn.Anchored = V3(8, 1, 8), Map.padCF(1) * CF(0, -2.5, 0), true
	spawn.Transparency, spawn.CanCollide, spawn.Neutral = 1, false, true
	spawn.Parent = world
	Map.spawn = spawn
	return world
end

return Map
