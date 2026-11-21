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
local WT = require(script.Parent:WaitForChild("WorldTerrain"))

local Map = {}
Map.SlotsPerPlanet = 8
Map.PlotRing = 100
Map.MaxBeds = 30
Map.BedCols, Map.BedStep = 6, 9.6
Map.planets = {}
Map.plots = {}
Map.boardLabels = {}

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

-- деревянный приподнятый ящик-грядка
local function bedBox(parent, bcf, i, plotId)
	local bed = Instance.new("Model")
	bed.Name = "Bed" .. i
	bed.Parent = parent
	local w = 7.6
	for _, s in { -1, 1 } do
		part(bed, "Plank", V3(w, 1.0, 0.5), bcf * CF(0, 0.5, s * (w / 2 - 0.25)), COL.wood, Mat.WoodPlanks)
		part(bed, "Plank", V3(0.5, 1.0, w - 1), bcf * CF(s * (w / 2 - 0.25), 0.5, 0), COL.wood, Mat.WoodPlanks)
	end
	local soil = part(bed, "Soil", V3(w - 1, 0.4, w - 1), bcf * CF(0, 0.82, 0), COL.soil, Mat.Ground, { CanCollide = false })
	soil:SetAttribute("Idx", i)
	soil:SetAttribute("Plot", plotId)
	local cover = part(bed, "Cover", V3(w - 0.6, 0.25, w - 0.6), bcf * CF(0, 1.12, 0), c(30, 32, 42), Mat.Metal, { CanCollide = false })
	local lockOrb = ball(bed, "LockOrb", (bcf * CF(0, 1.7, 0)).Position, 0.6, c(255, 110, 100), Mat.Neon)
	return { soil = soil, cover = cover, lockOrb = lockOrb, model = bed, pos = (bcf * CF(0, 1.02, 0)).Position, cf = bcf * CF(0, 1.02, 0) }
end

function Map.buildPlot(pi, j)
	local id = ("%d_%d"):format(pi, j)
	if Map.plots[id] then return Map.plots[id] end
	local cf, ang = slotCF(pi, j)
	local P = Map.planets[pi]
	if P.markers[j] then P.markers[j].Parent = nil end
	local pm = Instance.new("Model")
	pm.Name = "Plot" .. id
	pm:SetAttribute("Center", cf.Position)
	pm:SetAttribute("Planet", pi)
	local plot = { id = id, planet = pi, slot = j, cf = cf, model = pm, beds = {}, ang = ang }
	-- земля огорода: тёмная почва
	-- земля огорода: тонкий слой почвы поверх рельефа (рельеф не трогаем, чтобы не засыпать грядки)
	part(pm, "Ground", V3(62, 0.2, 54), cf * CF(0, 0.08, 0), c(70, 52, 42), Mat.Ground)
	-- низкий деревянный забор с проходом спереди
	local function rail(a, b)
		seg(pm, "Rail", a, b, 0.22, COL.wood2, Mat.Wood)
	end
	local W2, D2 = 30, 25.5
	local corners = { V3(-W2, 0, -D2), V3(W2, 0, -D2), V3(W2, 0, D2), V3(-W2, 0, D2) }
	for k = 1, 4 do
		local a, b = corners[k], corners[k % 4 + 1]
		local len = (b - a).Magnitude
		local n = math.floor(len / 6)
		for q = 0, n do
			local p = a + (b - a) * (q / n)
			if not (k == 1 and math.abs(p.X) < 4) then
				part(pm, "Post", V3(0.4, 1.6, 0.4), cf * CF(p + V3(0, 0.8, 0)), COL.wood, Mat.Wood)
			end
		end
		if k == 1 then
			rail(cf:PointToWorldSpace(a + V3(0, 1.2, 0)), cf:PointToWorldSpace(V3(-4, 1.2, -D2)))
			rail(cf:PointToWorldSpace(V3(4, 1.2, -D2)), cf:PointToWorldSpace(b + V3(0, 1.2, 0)))
		else
			rail(cf:PointToWorldSpace(a + V3(0, 1.2, 0)), cf:PointToWorldSpace(b + V3(0, 1.2, 0)))
			rail(cf:PointToWorldSpace(a + V3(0, 0.6, 0)), cf:PointToWorldSpace(b + V3(0, 0.6, 0)))
		end
	end
	-- дорожка от входа
	part(pm, "EntryPath", V3(5, 0.2, 6), cf * CF(0, 0.1, -D2 - 1), c(120, 112, 104), Mat.Cobblestone, { CanCollide = false })
	-- фонари по углам
	for _, p in corners do
		local base = cf:PointToWorldSpace(p * 1.04)
		seg(pm, "LampPole", base, base + V3(0, 6, 0), 0.25, COL.plate, Mat.Metal)
		local b = ball(pm, "LampBulb", base + V3(0, 6.3, 0), 0.8, COL.warm, Mat.Neon)
		light(b, c(255, 226, 190), 22, 0.8)
	end
	-- табличка с именем
	local board = part(pm, "Sign", V3(8, 2.4, 0.3), cf * CF(-9, 3, -D2 - 0.5) * A(0, PI, 0), COL.wood2, Mat.WoodPlanks, { CanCollide = false })
	plot.signFront = surfaceText(board, Enum.NormalId.Front, "Огород", COL.gold, 34)
	plot.signBack = surfaceText(board, Enum.NormalId.Back, "Огород", COL.gold, 34)
	for _, sx in { -3.6, 3.6 } do part(pm, "SignPost", V3(0.35, 3.4, 0.35), cf * CF(-9 + sx, 1.7, -D2 - 0.5), COL.wood, Mat.Wood, { CanCollide = false }) end
	-- грядки
	local beds = Instance.new("Folder")
	beds.Name = "Beds"
	beds.Parent = pm
	for bi = 1, Map.MaxBeds do
		local lp = Map.bedLocalPos(bi)
		plot.beds[bi] = bedBox(beds, cf * CF(lp), bi, id)
	end
	plot.entrance = cf * CF(0, 3, -D2 - 5) * A(0, PI, 0)
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
	{ id = "shop", ang = 0, col = COL.green, title = "СЕМЕНА", prompt = "Магазин семян" },
	{ id = "sell", ang = 90, col = COL.gold, title = "ПРОДАЖА", prompt = "Продать урожай" },
	{ id = "market", ang = 180, col = COL.mag, title = "РЫНОК", prompt = "Рынок и спрос" },
	{ id = "upgrades", ang = 270, col = COL.cyan, title = "МАСТЕРСКАЯ", prompt = "Улучшения" },
}
local function buildHub(pi, parent)
	local ctr = WT.Centers[pi]
	local name = Game.Planets[pi].name
	local f = Instance.new("Folder")
	f.Name = "Hub"
	f.Parent = parent
	cyl(f, "Plaza", CF(ctr + V3(0, 0.2, 0)), 0.5, 58, PLAZA[pi], Mat.Concrete)
	dcyl(f, "PlazaRing", CF(ctr + V3(0, 0.46, 0)), 0.06, 58.4, COL.trim, Mat.Metal)
	dcyl(f, "PlazaInner", CF(ctr + V3(0, 0.47, 0)), 0.06, 57.6, PLAZA[pi], Mat.Concrete)
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
		local pos = ctr + V3(cos(a) * 19, 0.45, sin(a) * 19)
		local kcf = CFrame.lookAt(pos, ctr + V3(0, 0.45, 0))
		local m = kiosk(f, "Kiosk_" .. k.id, kcf, k.col, k.title)
		if k.id == "market" then
			local scr = part(m, "Screen", V3(9, 5.2, 0.4), kcf * CF(0, 4.2, 2.8), c(8, 10, 20), Mat.SmoothPlastic, { CanCollide = false })
			local lbl = surfaceText(scr, Enum.NormalId.Front, "Рынок загружается", COL.mag, 30)
			lbl.TextScaled = false
			lbl.TextSize = 22
			lbl.RichText = true
			table.insert(Map.boardLabels, lbl)
		end
		local t2 = part(m, "PromptPart", V3(5, 3, 3), kcf * CF(0, 2.2, 1.6), COL.dark, Mat.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false })
		local p2 = prompt(t2, k.prompt, "", 12, "Open_" .. k.id)
		p2:SetAttribute("Window", k.id)
	end
	-- дорожки к огородам
	for j = 1, Map.SlotsPerPlanet do
		local _, ang = slotCF(pi, j)
		local dirv = V3(cos(ang), 0, sin(ang))
		local r0, r1 = 29, Map.PlotRing - 31
		local len = r1 - r0
		local mid = ctr + dirv * ((r0 + r1) / 2)
		local wcf = CFrame.lookAt(V3(mid.X, ctr.Y + 0.2, mid.Z), V3(mid.X, ctr.Y + 0.2, mid.Z) - dirv)
		part(f, "Walkway", V3(7, 0.4, len), wcf, PLAZA[pi]:Lerp(c(60, 60, 70), 0.35), Mat.Cobblestone)
		for _, s in { -1, 1 } do
			local pos = (wcf * CF(s * 4.6, 0, 0)).Position
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


local function free(pi, x, z)
	local ctr = WT.Centers[pi]
	local dx, dz = x - ctr.X, z - ctr.Z
	local r = math.sqrt(dx * dx + dz * dz)
	if r < 34 or r > WT.PlayRadius - 4 then return false end
	for j = 1, Map.SlotsPerPlanet do
		local cf = slotCF(pi, j)
		local lp = cf:PointToObjectSpace(V3(x, ctr.Y, z))
		if math.abs(lp.X) < 40 and lp.Z > -34 and lp.Z < 44 then return false end
		-- дорожка к огороду
		local ang = select(2, slotCF(pi, j))
		local along = dx * cos(ang) + dz * sin(ang)
		local across = math.abs(-dx * sin(ang) + dz * cos(ang))
		if along > 20 and along < 75 and across < 7 then return false end
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
		while placed < 26 and tries < 400 do
			tries += 1
			local a = rng:NextNumber(0, PI * 2)
			local r = rng:NextNumber(34, WT.PlayRadius - 6)
			local x, z = ctr.X + cos(a) * r, ctr.Z + sin(a) * r
			if free(pi, x, z) then
				local id = mine[rng:NextInteger(1, #mine)]
				bigPlant(fl, id, V3(x, WT.groundY(x, z, pi), z), rng:NextNumber(2.2, 5.5), rng:NextNumber(0, PI * 2))
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
	for _ = 1, 200 do
		if n >= 26 then break end
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

function Map.padCF(pi)
	local ctr = WT.Centers[pi]
	return CF(ctr + V3(0, 3, 12)) * A(0, PI, 0)
end
Map.planetAt = WT.planetAt

------------------------------------------------------------------ фон
local function billboard(parent, name, image, pos, size)
	-- картинка планеты на невидимой плоскости, повёрнутой к центру станции (SurfaceGui не зависит от прозрачности детали)
	local p = part(parent, name, V3(size, size, 0.2), CFrame.lookAt(pos, V3(0, 0, 0)), c(255, 255, 255), Mat.SmoothPlastic,
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
	cc.Contrast, cc.Saturation, cc.Brightness = 0.08, 0.06, 0
	cc.TintColor = c(245, 240, 255)
	cc.Parent = Lighting
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
		for j = 1, Map.SlotsPerPlanet do
			P.markers[j] = slotMarker(pi, j, slots)
		end
		local rocks = Instance.new("Folder")
		rocks.Name = "Rocks"
		rocks.Parent = pf
		buildRocks(pi, rocks)
		local bar = Instance.new("Folder")
		bar.Name = "Barrier"
		bar.Parent = pf
		buildBarrier(pi, bar)
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
