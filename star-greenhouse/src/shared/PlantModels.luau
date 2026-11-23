-- Процедурные модели растений: 22 формы x цвета каталога + визуальные эффекты мутаций.
-- Модель строится в локальных координатах, корень (Root) в точке почвы. Все детали Anchored, без коллизий.
-- Имена деталей: F* — мякоть плода (перекрашивается мутацией), G* — светящиеся, L* — листья, S* — стебли.
local G = require(script.Parent:WaitForChild("Game"))

local PM = {}
local V3, CF, A = Vector3.new, CFrame.new, CFrame.Angles
local PI = math.pi
local sin, cos = math.sin, math.cos

local Material = Enum.Material
local MATS = {
	Ice = Material.Ice, Slate = Material.Slate, Neon = Material.Neon, Glass = Material.Glass, ForceField = Material.ForceField,
	Metal = Material.Metal, Grass = Material.Grass, SmoothPlastic = Material.SmoothPlastic, Rock = Material.Rock, Wood = Material.Wood,
}

------------------------------------------------------------------ детали
local function base(model, name, size, cf, color, mat, tr)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
	p.Size, p.CFrame, p.Color = size, cf, color
	p.Material = mat or Material.SmoothPlastic
	p.Transparency = tr or 0
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = model
	return p
end
local function ell(model, name, cf, size, color, mat, tr)
	local p = base(model, name, size, cf, color, mat, tr)
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end
local function ball(model, name, pos, d, color, mat, tr)
	local p = base(model, name, V3(d, d, d), CF(pos), color, mat, tr)
	p.Shape = Enum.PartType.Ball
	return p
end
local function blk(model, name, cf, size, color, mat, tr)
	return base(model, name, size, cf, color, mat, tr)
end
-- цилиндр: ось вдоль локального Y заданного cf
local function cyl(model, name, cf, h, d, color, mat, tr)
	local p = base(model, name, V3(h, d, d), cf * A(0, 0, PI / 2), color, mat, tr)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- отрезок между двумя точками
local function seg(model, name, a, b, d, color, mat, tr)
	local len = (b - a).Magnitude
	local p = base(model, name, V3(len, d, d), CFrame.lookAt((a + b) / 2, b) * A(0, PI / 2, 0), color, mat, tr)
	p.Shape = Enum.PartType.Cylinder
	return p
end
-- вытянутый эллипсоид вдоль направления (лист, лепесток)
local function blade(model, name, from, dir, len, w, th, color, mat, tr)
	local to = from + dir.Unit * len
	return ell(model, name, CFrame.lookAt((from + to) / 2, to), V3(w, th, len), color, mat, tr)
end

local function leafColor(plant)
	return plant.c1:Lerp(Color3.fromRGB(70, 150, 80), 0.6)
end
local function stemColor(plant)
	return plant.c1:Lerp(Color3.fromRGB(60, 110, 70), 0.55)
end

------------------------------------------------------------------ формы
local F = {}

F.orb = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 1.1, 0), 0.17, sc, Material.Grass)
	for i = 1, 4 do
		local a = i * 1.57 + 0.4
		local tip = V3(cos(a) * 0.95, 1.75 + 0.18 * (i % 2), sin(a) * 0.95)
		seg(m, "S2", V3(0, 1.0, 0), tip, 0.1, sc, Material.Grass)
		ball(m, "F1", tip + V3(0, -0.25, 0), 0.72, pl.c1, Material.SmoothPlastic)
		ball(m, "F2", tip + V3(cos(a) * 0.38, -0.5, sin(a) * 0.38), 0.46, pl.c1:Lerp(pl.c2, 0.4), Material.SmoothPlastic)
		ball(m, "GH", tip + V3(-0.12, -0.05, 0.12), 0.16, Color3.new(1, 1, 1), Material.Neon, 0.35)
		blade(m, "L", V3(0, 0.45 + i * 0.12, 0), V3(cos(a + 0.8), 0.5, sin(a + 0.8)), 0.9, 0.5, 0.07, lc, Material.Grass)
	end
	ball(m, "G1", V3(0, 1.25, 0), 0.34, pl.c2, Material.Neon)
end

F.flower = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	seg(m, "S1", V3(0, 0, 0), V3(0.1, 1.85, 0), 0.15, sc, Material.Grass)
	local hc = V3(0.1, 1.95, 0)
	for ring = 1, 2 do
		local n, rad, sz = ring == 1 and 9 or 7, ring == 1 and 0.66 or 0.4, ring == 1 and 0.95 or 0.7
		for i = 1, n do
			local a = i / n * PI * 2 + ring * 0.35
			ell(m, "F" .. ring, CF(hc + V3(cos(a) * rad, ring * 0.08, sin(a) * rad)) * A(0, -a, 0.18 * ring), V3(sz, 0.12, 0.4),
				ring == 1 and pl.c1 or pl.c1:Lerp(pl.c2, 0.5), Material.SmoothPlastic)
		end
	end
	ball(m, "G1", hc + V3(0, 0.16, 0), 0.52, pl.c2, Material.Neon)
	for i = 1, 8 do
		local a = i / 8 * PI * 2
		ball(m, "G2", hc + V3(cos(a) * 0.3, 0.3, sin(a) * 0.3), 0.1, Color3.new(1, 1, 1), Material.Neon)
	end
	blade(m, "L", V3(0.02, 0.35, 0), V3(1, 0.5, 0.2), 1.0, 0.55, 0.07, lc, Material.Grass)
	blade(m, "L", V3(0.02, 0.6, 0), V3(-1, 0.55, -0.3), 0.95, 0.5, 0.07, lc, Material.Grass)
end

F.mushroom = function(m, pl)
	local cream = pl.c2:Lerp(Color3.new(1, 1, 1), 0.55)
	ell(m, "S1", CF(0, 0.3, 0), V3(0.95, 0.7, 0.95), cream, Material.SmoothPlastic)
	cyl(m, "S2", CF(0, 0.95, 0), 1.3, 0.55, cream, Material.SmoothPlastic)
	cyl(m, "S3", CF(0, 1.38, 0), 0.08, 1.15, cream:Lerp(pl.c1, 0.4), Material.SmoothPlastic)
	ell(m, "F1", CF(0, 1.75, 0), V3(2.5, 1.35, 2.5), pl.c1, Material.SmoothPlastic)
	cyl(m, "L", CF(0, 1.5, 0), 0.07, 2.2, pl.c1:Lerp(Color3.new(0, 0, 0), 0.6), Material.SmoothPlastic)
	for i = 1, 7 do
		local a, r = i * 2.4, 0.35 + (i % 3) * 0.3
		local y = 1.75 + 0.67 * math.sqrt(math.max(0, 1 - (r / 1.25) ^ 2)) - 0.04
		ball(m, "GS", V3(cos(a) * r, y, sin(a) * r), 0.3 + (i % 2) * 0.08, pl.c2:Lerp(Color3.new(1, 1, 1), 0.5), Material.SmoothPlastic)
	end
	for k = 1, 2 do
		local ox, oz = k == 1 and 1.1 or -0.9, k == 1 and 0.5 or -0.7
		cyl(m, "S4", CF(ox, 0.25, oz), 0.5, 0.2, cream, Material.SmoothPlastic)
		ell(m, "F3", CF(ox, 0.58, oz), V3(0.7, 0.4, 0.7), pl.c1, Material.SmoothPlastic)
	end
end

F.bulb = function(m, pl)
	local lc = leafColor(pl)
	ell(m, "F1", CF(0, 0.85, 0), V3(1.55, 1.7, 1.55), pl.c1, Material.SmoothPlastic)
	ell(m, "F2", CF(0.35, 0.95, 0.25), V3(0.5, 1.2, 0.4), pl.c1:Lerp(Color3.new(1, 1, 1), 0.25), Material.SmoothPlastic, 0.25)
	ell(m, "S1", CF(0, 0.05, 0), V3(0.2, 0.5, 0.2), pl.c1:Lerp(pl.c2, 0.5), Material.SmoothPlastic)
	for i = 1, 7 do
		local a = i / 7 * PI * 2
		blade(m, "L", V3(0, 1.6, 0), V3(cos(a) * 0.6, 1, sin(a) * 0.6), 1.7 + (i % 2) * 0.4, 0.38, 0.08, i % 2 == 0 and lc or lc:Lerp(pl.c2, 0.3), Material.Grass)
	end
	ball(m, "G1", V3(0, 1.65, 0), 0.25, pl.c2, Material.Neon)
end

F.tulip = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 2.0, 0), 0.15, sc, Material.Grass)
	for i = 1, 6 do
		local a = i / 6 * PI * 2
		local layer = i % 2
		ell(m, "F1", CF(cos(a) * 0.34, 2.55 + layer * 0.08, sin(a) * 0.34) * A(0, -a, 0.3), V3(0.6, 1.35 - layer * 0.15, 0.34),
			layer == 0 and pl.c1 or pl.c1:Lerp(pl.c2, 0.35), Material.SmoothPlastic)
	end
	ball(m, "G1", V3(0, 2.4, 0), 0.5, pl.c2, Material.Neon, 0.1)
	blade(m, "L", V3(0, 0.3, 0), V3(0.9, 1.3, 0.2), 1.9, 0.5, 0.08, lc, Material.Grass)
	blade(m, "L", V3(0, 0.3, 0), V3(-0.8, 1.2, -0.3), 1.7, 0.5, 0.08, lc, Material.Grass)
end

F.vine = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	local prev = V3(0.5, 0, 0)
	local n = 18
	for i = 1, n do
		local t = i / n
		local a = t * PI * 5
		local r = 0.55 * (1 - 0.3 * t)
		local p = V3(cos(a) * r, t * 3.4, sin(a) * r)
		seg(m, "S1", prev, p, 0.15 * (1.1 - 0.5 * t), sc, Material.Grass)
		if i % 2 == 0 then
			blade(m, "L", p, V3(cos(a), 0.2, sin(a)), 0.75, 0.55, 0.07, lc, Material.Grass)
		end
		if i == 6 or i == 10 or i == 14 then
			local o = V3(cos(a) * (r + 0.4), t * 3.4 - 0.3, sin(a) * (r + 0.4))
			seg(m, "S2", p, o + V3(0, 0.25, 0), 0.07, sc, Material.Grass)
			ball(m, "F1", o, 0.52, pl.c1, Material.SmoothPlastic)
			ball(m, "GH", o + V3(-0.1, 0.12, 0.1), 0.12, Color3.new(1, 1, 1), Material.Neon, 0.3)
		end
		prev = p
	end
	ball(m, "G1", prev + V3(0, 0.2, 0), 0.42, pl.c2, Material.Neon)
end

F.coral = function(m, pl)
	seg(m, "F0", V3(0, 0, 0), V3(0, 1.2, 0), 0.42, pl.c1, Material.SmoothPlastic)
	for i = 1, 5 do
		local a = i / 5 * PI * 2
		local d1 = V3(cos(a) * 0.85, 1.0, sin(a) * 0.85)
		local p1 = V3(0, 1.1, 0) + d1
		seg(m, "F1", V3(0, 1.1, 0), p1, 0.3, pl.c1, Material.SmoothPlastic)
		for k = -1, 1, 2 do
			local a2 = a + k * 0.5
			local p2 = p1 + V3(cos(a2) * 0.55, 0.85, sin(a2) * 0.55)
			seg(m, "F2", p1, p2, 0.2, pl.c1:Lerp(pl.c2, 0.4), Material.SmoothPlastic)
			ball(m, "G1", p2, 0.32, pl.c2, Material.Neon)
		end
	end
end

F.gourd = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	for i = 0, 5 do
		ell(m, "F1", CF(0, 1.0, 0) * A(0, i * PI / 6, 0), V3(2.5, 1.95, 1.0), pl.c1:Lerp(pl.c2, (i % 2) * 0.2), Material.SmoothPlastic)
	end
	cyl(m, "S1", CF(0.05, 2.12, 0) * A(0, 0, 0.2), 0.5, 0.3, sc, Material.Grass)
	ball(m, "S2", V3(0.15, 2.4, 0), 0.22, sc, Material.Grass)
	for i = 1, 6 do
		local a = i * 0.9
		ball(m, "S3", V3(1.5 + cos(a) * 0.25, 0.3 + i * 0.08, sin(a) * 0.25), 0.1, sc, Material.Grass)
	end
	blade(m, "L", V3(0.1, 2.1, 0), V3(1, 0.1, 0.4), 1.3, 0.9, 0.07, lc, Material.Grass)
	ball(m, "G1", V3(0, 1.0, 1.0), 0.18, pl.c2, Material.Neon, 0.2)
end

F.tree = function(m, pl)
	local trunk = pl.c1:Lerp(Color3.fromRGB(70, 50, 40), 0.7)
	seg(m, "S1", V3(0, 0, 0), V3(0.1, 1.5, 0), 0.5, trunk, Material.Wood)
	seg(m, "S2", V3(0.1, 1.4, 0), V3(-0.15, 2.5, 0.1), 0.32, trunk, Material.Wood)
	local tips = { V3(0.95, 3.0, 0.2), V3(-1.0, 2.9, 0.4), V3(0.05, 3.2, -0.9), V3(-0.1, 3.7, 0.15) }
	for _, t in tips do
		seg(m, "S3", V3(-0.15, 2.4, 0.1), t, 0.16, trunk, Material.Wood)
	end
	local sizes = { 1.7, 1.5, 1.6, 1.9 }
	for i, t in tips do
		ball(m, "F" .. i, t + V3(0, 0.45, 0), sizes[i], pl.c1:Lerp(Color3.fromRGB(80, 170, 90), 0.2 + 0.1 * (i % 2)), Material.SmoothPlastic)
	end
	for i = 1, 8 do
		local a = i * 2.1
		local c = tips[(i - 1) % 4 + 1]
		ball(m, "G1", c + V3(cos(a) * 0.75, 0.3 + sin(a * 2) * 0.35, sin(a) * 0.75), 0.28, pl.c2, Material.Neon)
	end
	for i = 1, 4 do
		local a = i * 1.57
		seg(m, "S4", V3(0.1, 0.3, 0), V3(cos(a) * 0.7, -0.05, sin(a) * 0.7), 0.14, trunk, Material.Wood)
	end
end

F.crystal = function(m, pl)
	local glass = Material.Glass
	local cfgs = {
		{ 0, 0, 3.0, 0.8, 0 }, { 0.55, 0.3, 2.2, 0.6, 0.3 }, { -0.5, 0.35, 2.4, 0.62, -0.28 }, { 0.2, -0.6, 1.7, 0.5, 0.22 },
		{ -0.3, -0.5, 1.5, 0.46, -0.3 }, { 0.75, -0.35, 1.2, 0.4, 0.4 }, { -0.8, -0.1, 1.1, 0.38, -0.42 },
	}
	for i, c in cfgs do
		local x, z, h, w, tilt = c[1], c[2], c[3], c[4], c[5]
		local cf = CF(x, 0, z) * A(0, i * 0.7, tilt) * CF(0, h * 0.4, 0)
		blk(m, "F1", cf, V3(w, h * 0.8, w), pl.c1:Lerp(pl.c2, (i % 3) * 0.25), glass, 0.12)
		ell(m, "F2", cf * CF(0, h * 0.4, 0), V3(w * 1.02, h * 0.55, w * 1.02), pl.c1:Lerp(pl.c2, 0.3 + (i % 3) * 0.2), glass, 0.1)
		ell(m, "G1", cf * CF(0, h * 0.05, 0), V3(w * 0.4, h * 0.6, w * 0.4), pl.c2, Material.Neon, 0.35)
	end
	ball(m, "G2", V3(0, 0.15, 0), 0.5, pl.c2, Material.Neon, 0.3)
end

F.spiral = function(m, pl)
	cyl(m, "S1", CF(0, 1.7, 0), 3.4, 0.12, pl.c2, Material.Neon, 0.4)
	local n = 22
	for i = 1, n do
		local t = i / n
		local a = t * PI * 4.2
		local r = 0.95 - 0.7 * t
		ball(m, "F1", V3(cos(a) * r, 0.2 + t * 3.1, sin(a) * r), 0.75 - 0.5 * t, pl.c1:Lerp(pl.c2, t), Material.SmoothPlastic)
	end
	ball(m, "G1", V3(0, 3.55, 0), 0.5, pl.c2, Material.Neon)
	ell(m, "S2", CF(0, 0.08, 0), V3(1.6, 0.3, 1.6), pl.c1:Lerp(Color3.new(0, 0, 0), 0.5), Material.Slate)
end

F.star = function(m, pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 1.45, 0), 0.12, stemColor(pl), Material.Grass)
	local c = V3(0, 2.2, 0)
	ball(m, "G1", c, 0.95, pl.c2, Material.Neon)
	ball(m, "F0", c, 0.7, pl.c1, Material.SmoothPlastic)
	for i = 0, 4 do
		local a = i / 5 * PI * 2
		blade(m, "F1", c, V3(sin(a), cos(a), 0), 1.55, 0.34, 0.34, pl.c1, Material.SmoothPlastic)
		blade(m, "G2", c, V3(sin(a + PI / 5), cos(a + PI / 5), 0), 0.9, 0.2, 0.2, pl.c2, Material.Neon)
	end
	for i = 1, 3 do
		local a = i * 2.1
		ball(m, "G3", c + V3(cos(a) * 1.25, sin(a * 1.3) * 0.3, sin(a) * 1.25), 0.14, Color3.new(1, 1, 1), Material.Neon)
	end
end

F.jelly = function(m, pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 1.5, 0), 0.1, pl.c2, Material.Glass, 0.35)
	ell(m, "F1", CF(0, 2.35, 0), V3(2.1, 1.3, 2.1), pl.c1, Material.Glass, 0.35)
	ell(m, "F2", CF(0, 2.15, 0), V3(1.5, 0.8, 1.5), pl.c1:Lerp(pl.c2, 0.5), Material.Neon, 0.55)
	ball(m, "G1", V3(0, 2.2, 0), 0.75, pl.c2, Material.Neon, 0.1)
	for i = 1, 8 do
		local a = i / 8 * PI * 2
		local prev = V3(cos(a) * 0.8, 1.9, sin(a) * 0.8)
		for k = 1, 4 do
			local p = prev + V3(cos(a + k) * 0.12, -0.38, sin(a + k) * 0.12)
			seg(m, "F3", prev, p, 0.12 * (1.1 - k * 0.15), pl.c1, Material.Glass, 0.3)
			prev = p
		end
		ball(m, "G2", prev, 0.14, pl.c2, Material.Neon)
	end
end

F.heart = function(m, pl)
	cyl(m, "R1", CF(0, 0.15, 0), 0.3, 1.8, pl.c1:Lerp(Color3.new(0, 0, 0), 0.65), Material.Slate)
	cyl(m, "R2", CF(0, 0.5, 0), 0.5, 0.9, pl.c1:Lerp(Color3.new(0, 0, 0), 0.5), Material.Slate)
	ell(m, "F1", CF(0, 1.95, 0) * A(0, 0, PI / 4), V3(1.55, 1.55, 1.0), pl.c1, Material.SmoothPlastic)
	ell(m, "F2", CF(-0.45, 2.45, 0), V3(1.15, 1.2, 1.0), pl.c1, Material.SmoothPlastic)
	ell(m, "F3", CF(0.45, 2.45, 0), V3(1.15, 1.2, 1.0), pl.c1, Material.SmoothPlastic)
	ball(m, "G1", V3(0, 2.15, 0), 0.9, pl.c2, Material.Neon, 0.25)
	for i = 1, 6 do
		local a = i / 6 * PI * 2
		ball(m, "G2", V3(cos(a) * 1.35, 2.1 + sin(a * 2) * 0.25, sin(a) * 1.35), 0.14, pl.c2, Material.Neon)
	end
end

F.crown = function(m, pl)
	local gold = pl.c1:Lerp(Color3.fromRGB(255, 215, 120), 0.35)
	cyl(m, "R1", CF(0, 0.15, 0), 0.3, 1.7, gold:Lerp(Color3.new(0, 0, 0), 0.5), Material.Metal)
	cyl(m, "S1", CF(0, 0.8, 0), 1.0, 0.45, gold:Lerp(Color3.new(0, 0, 0), 0.3), Material.Metal)
	cyl(m, "F1", CF(0, 1.55, 0), 0.5, 1.85, gold, Material.Metal)
	cyl(m, "F2", CF(0, 1.55, 0), 0.52, 1.6, pl.c1:Lerp(Color3.new(0, 0, 0), 0.4), Material.Metal)
	for i = 1, 7 do
		local a = i / 7 * PI * 2
		local x, z = cos(a) * 0.82, sin(a) * 0.82
		blade(m, "F3", V3(x, 1.7, z), V3(cos(a) * 0.25, 1, sin(a) * 0.25), 1.15, 0.3, 0.3, gold, Material.Metal)
		ball(m, "G1", V3(cos(a) * 0.95, 2.95, sin(a) * 0.95), 0.3, pl.c2, Material.Neon)
	end
	ball(m, "G2", V3(0, 2.5, 0), 0.8, pl.c2, Material.Neon, 0.15)
end

F.geode = function(m, pl)
	local rock = pl.c1:Lerp(Color3.fromRGB(50, 50, 60), 0.75)
	ell(m, "R1", CF(0, 0.5, 0) * A(0.1, 0.4, 0.1), V3(2.3, 1.3, 2.0), rock, Material.Slate)
	ell(m, "R2", CF(0.8, 0.35, 0.5) * A(0, 1, 0.2), V3(1.3, 0.8, 1.1), rock:Lerp(Color3.new(1, 1, 1), 0.1), Material.Slate)
	ell(m, "R3", CF(-0.8, 0.35, -0.4) * A(0.2, 2, 0), V3(1.2, 0.9, 1.0), rock, Material.Slate)
	ball(m, "G1", V3(0, 1.05, 0), 1.1, pl.c2, Material.Neon, 0.3)
	for i = 1, 8 do
		local a = i * 0.9
		local r = 0.2 + (i % 3) * 0.3
		local h = 1.1 + (i % 4) * 0.35
		local cf = CF(cos(a) * r, 1.0, sin(a) * r) * A(0, a, (i % 2 == 0 and 1 or -1) * (0.15 + 0.1 * (i % 3))) * CF(0, h * 0.5, 0)
		ell(m, "F1", cf, V3(0.4, h, 0.4), pl.c1:Lerp(pl.c2, (i % 3) * 0.3), Material.Glass, 0.12)
	end
end

F.grass = function(m, pl)
	local lc = leafColor(pl)
	for i = 1, 11 do
		local a = i * 0.57
		local lean = 0.25 + (i % 4) * 0.12
		local len = 1.9 + (i % 3) * 0.55
		local dir = V3(cos(a) * lean, 1, sin(a) * lean)
		local from = V3(cos(a) * 0.15, 0, sin(a) * 0.15)
		blade(m, "L", from, dir, len, 0.17, 0.05, i % 2 == 0 and lc or lc:Lerp(pl.c1, 0.5), Material.Grass)
		if i % 2 == 0 then
			local tip = from + dir.Unit * len
			ball(m, "F1", tip, 0.32, pl.c1, Material.SmoothPlastic)
			ball(m, "G1", tip + V3(0, 0.12, 0), 0.14, pl.c2, Material.Neon)
		end
	end
end

F.pod = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 2.2, 0), 0.2, sc, Material.Grass)
	for i = 1, 3 do
		local a = i / 3 * PI * 2 + 0.5
		local b = V3(cos(a) * 0.75, 2.4, sin(a) * 0.75)
		seg(m, "S2", V3(0, 2.0, 0), b, 0.1, sc, Material.Grass)
		ball(m, "S3", b, 0.3, lc, Material.Grass)
		ell(m, "F1", CF(b + V3(cos(a) * 0.05, -0.5, sin(a) * 0.05)), V3(0.6, 0.95, 0.6), pl.c1, Material.SmoothPlastic)
		ell(m, "F2", CF(b + V3(cos(a) * 0.14, -1.15, sin(a) * 0.14)), V3(0.46, 0.8, 0.46), pl.c1:Lerp(pl.c2, 0.4), Material.SmoothPlastic)
		ell(m, "F3", CF(b + V3(cos(a) * 0.3, -1.7, sin(a) * 0.3)), V3(0.28, 0.6, 0.28), pl.c2, Material.SmoothPlastic)
		ball(m, "GH", b + V3(-0.12, -0.35, 0.1), 0.13, Color3.new(1, 1, 1), Material.Neon, 0.4)
		blade(m, "L", V3(0, 0.8 + i * 0.4, 0), V3(cos(a + 1.2), 0.4, sin(a + 1.2)), 1.0, 0.55, 0.07, lc, Material.Grass)
	end
end

F.cactus = function(m, pl)
	local body = pl.c1
	cyl(m, "F1", CF(0, 1.35, 0), 2.7, 1.25, body, Material.SmoothPlastic)
	ball(m, "F2", V3(0, 2.7, 0), 1.25, body, Material.SmoothPlastic)
	for i = 1, 4 do
		local a = i / 4 * PI * 2 + 0.4
		cyl(m, "F3", CF(cos(a) * 0.62, 1.35, sin(a) * 0.62), 2.6, 0.12, body:Lerp(Color3.new(0, 0, 0), 0.25), Material.SmoothPlastic)
	end
	cyl(m, "F4", CF(0.95, 1.4, 0) * A(0, 0, PI / 2), 0.9, 0.55, body, Material.SmoothPlastic)
	cyl(m, "F5", CF(1.4, 1.95, 0), 1.2, 0.55, body, Material.SmoothPlastic)
	ball(m, "F6", V3(1.4, 2.55, 0), 0.55, body, Material.SmoothPlastic)
	cyl(m, "F7", CF(-0.9, 1.0, 0) * A(0, 0, PI / 2), 0.75, 0.48, body, Material.SmoothPlastic)
	cyl(m, "F8", CF(-1.3, 1.45, 0), 0.95, 0.48, body, Material.SmoothPlastic)
	ball(m, "F9", V3(-1.3, 1.95, 0), 0.48, body, Material.SmoothPlastic)
	for i = 1, 8 do
		local a, y = i * 1.3, 0.6 + (i % 5) * 0.45
		ball(m, "GS", V3(cos(a) * 0.62, y, sin(a) * 0.62), 0.09, Color3.new(1, 1, 1), Material.Neon)
	end
	for i = 1, 5 do
		local a = i / 5 * PI * 2
		ell(m, "G1", CF(cos(a) * 0.3, 3.3, sin(a) * 0.3) * A(0, -a, 0.5), V3(0.5, 0.1, 0.25), pl.c2, Material.Neon)
	end
	ball(m, "G2", V3(0, 3.3, 0), 0.26, Color3.fromRGB(255, 235, 150), Material.Neon)
end

F.comet = function(m, pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 2.0, 0), 0.1, stemColor(pl), Material.Grass)
	local head = V3(0, 2.6, 0)
	ball(m, "G1", head, 1.25, pl.c1, Material.Neon)
	ball(m, "F1", head, 0.9, pl.c2, Material.SmoothPlastic)
	for i = 1, 10 do
		local t = i / 10
		ball(m, "G2", head + V3(0.7 + i * 0.5, 0.25 + i * 0.28, 0), 1.0 * (1 - t * 0.85), pl.c1:Lerp(pl.c2, t), Material.Neon, 0.15 + t * 0.55)
	end
end

F.sprout = function(m, pl)
	local lc, sc = leafColor(pl), stemColor(pl)
	seg(m, "S1", V3(0, 0, 0), V3(0, 1.5, 0), 0.2, sc, Material.Grass)
	blade(m, "L", V3(0, 1.0, 0), V3(1, 0.5, 0), 1.7, 0.95, 0.08, lc, Material.Grass)
	blade(m, "L", V3(0, 1.2, 0), V3(-1, 0.55, 0.3), 1.6, 0.9, 0.08, lc, Material.Grass)
	ball(m, "F1", V3(0, 1.85, 0), 0.9, pl.c1, Material.SmoothPlastic)
	ball(m, "G1", V3(0, 1.85, 0), 0.55, pl.c2, Material.Neon)
	for i = 1, 6 do
		local a = i / 6 * PI * 2
		blade(m, "G2", V3(0, 1.85, 0), V3(cos(a), 0.4, sin(a)), 1.1, 0.12, 0.12, pl.c2, Material.Neon, 0.2)
	end
end

F.seedcore = function(m, pl)
	cyl(m, "R1", CF(0, 0.15, 0), 0.3, 1.6, pl.c1:Lerp(Color3.new(0, 0, 0), 0.6), Material.Slate)
	ell(m, "F1", CF(0, 2.0, 0), V3(1.7, 2.2, 1.7), pl.c1, Material.SmoothPlastic)
	ell(m, "G1", CF(0, 2.0, 0), V3(1.78, 0.14, 1.78), pl.c2, Material.Neon)
	ell(m, "G1", CF(0, 2.0, 0) * A(0, 0, 1.0), V3(1.78, 0.14, 1.78), pl.c2, Material.Neon)
	ell(m, "G1", CF(0, 2.0, 0) * A(0, 0, -1.0), V3(1.78, 0.14, 1.78), pl.c2, Material.Neon)
	ball(m, "G2", V3(0, 2.0, 0), 0.9, pl.c2, Material.Neon, 0.4)
	for i = 1, 6 do
		local a = i / 6 * PI * 2
		ball(m, "G3", V3(cos(a) * 1.5, 2.0 + sin(a * 3) * 0.3, sin(a) * 1.5), 0.2, Color3.new(1, 1, 1), Material.Neon)
	end
	blade(m, "L", V3(0, 3.0, 0), V3(1, 0.7, 0), 0.9, 0.45, 0.07, leafColor(pl), Material.Grass)
	blade(m, "L", V3(0, 3.0, 0), V3(-1, 0.7, 0), 0.9, 0.45, 0.07, leafColor(pl), Material.Grass)
end

------------------------------------------------------------------ сборка из загруженных мешей
local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- материал и прозрачность ролей по форме: F плод, A акцент, L листья, G свечение, R камень
local MESH_STYLE = {
	crystal = { F = { Material.Glass, 0.2 } },
	geode = { F = { Material.Glass, 0.22 } },
	jelly = { F = { Material.Glass, 0.42 }, A = { Material.Glass, 0.3 } },
	crown = { F = { Material.Metal, 0 } },
}
local function meshTemplate(id)
	if not ReplicatedStorage:GetAttribute("MeshesReady") then return nil end
	local root = ReplicatedStorage:FindFirstChild("PlantMeshes")
	local f = root and root:FindFirstChild(id)
	if f and f:FindFirstChildWhichIsA("BasePart") then return f end
	return nil
end
function PM.hasMeshes(id) return meshTemplate(id) ~= nil end

local function meshModel(model, plant, tpl)
	local c1, c2 = plant.c1, plant.c2
	local roles = {
		F = c1, A = c2, L = plant.c1:Lerp(Color3.fromRGB(70, 150, 80), 0.6),
		G = c2:Lerp(Color3.new(1, 1, 1), 0.1), R = c1:Lerp(Color3.fromRGB(40, 38, 50), 0.75),
	}
	local style = MESH_STYLE[plant.form] or {}
	for _, src in tpl:GetChildren() do
		if src:IsA("BasePart") then
			local role = src.Name
			local p = src:Clone()
			p.Name = role .. "M"
			p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery = true, false, false, false
			p.Color = roles[role] or c1
			local st = style[role]
			if role == "G" then
				p.Material = Material.Neon
			elseif role == "L" then
				p.Material = Material.SmoothPlastic
			elseif role == "R" then
				p.Material = Material.Slate
			elseif st then
				p.Material = st[1]
				p.Transparency = st[2]
			else
				p.Material = Material.SmoothPlastic
			end
			p.Parent = model
		end
	end
end

------------------------------------------------------------------ сборка
local function rootPart(model)
	local r = base(model, "Root", V3(0.2, 0.2, 0.2), CF(), Color3.new(1, 1, 1), Material.SmoothPlastic, 1)
	model.PrimaryPart = r
	return r
end

-- масштаб всех деталей относительно корня (до первой постановки в мир)
local function scaleAll(model, k)
	if math.abs(k - 1) < 1e-3 then return end
	for _, p in model:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local pos = p.Position
			local rot = CF(pos):Inverse() * p.CFrame
			p.Size = p.Size * k
			p.CFrame = CF(pos * k) * rot
		end
	end
end

function PM.sproutModel(plant)
	local m = Instance.new("Model")
	m.Name = "Sprout"
	rootPart(m)
	local lc = leafColor(plant)
	seg(m, "S1", V3(0, 0, 0), V3(0, 0.7, 0), 0.11, stemColor(plant), Material.Grass)
	blade(m, "L", V3(0, 0.45, 0), V3(1, 0.5, 0), 0.75, 0.42, 0.06, lc, Material.Grass)
	blade(m, "L", V3(0, 0.5, 0), V3(-1, 0.55, 0.2), 0.7, 0.4, 0.06, lc, Material.Grass)
	ball(m, "G1", V3(0, 0.78, 0), 0.2, plant.c1, Material.Neon, 0.1)
	return m
end

-- чем редче мутация, тем крупнее растение: редкие — настоящие гиганты
local TIER_SIZE = { 1.08, 1.22, 1.45, 1.75, 2.1, 2.6 }
function PM.sizeOf(muts)
	local k = 1
	local top = 0
	for _, id in muts or {} do
		local mt = G.Mut[id]
		if mt then
			if mt.size then k *= mt.size end
			top = math.max(top, mt.tier)
		end
	end
	return k * (TIER_SIZE[top] or 1)
end

-- mutations — список id; без мутаций обычный плод
function PM.build(plantId: string, muts: { string }?): Model
	local plant = G.Plants[plantId]
	local m = Instance.new("Model")
	m.Name = plant.name
	rootPart(m)
	local tpl = meshTemplate(plantId)
	local k = plant.scale
	if tpl then
		meshModel(m, plant, tpl)
		k = 1 -- размер уже заложен в модели
	else
		F[plant.form](m, plant)
	end
	local rarest = nil
	if muts and #muts > 0 then
		rarest = G.rarestMut(muts)
		k *= PM.sizeOf(muts)
	end
	scaleAll(m, k)
	if muts and #muts > 0 then PM.applyMutations(m, plant, muts, rarest, k) end
	-- общее свечение сорта: мягкий свет
	if plant.glow >= 0.4 and not m:FindFirstChildOfClass("PointLight") then
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness = plant.c2, 4 + 4 * plant.glow, 0.25 + 0.5 * plant.glow
		l.Parent = m.PrimaryPart
	end
	return m
end

-- цвет свечения: насыщенный и не слишком яркий, чтобы блум не выжигал его в белое пятно
local function glowOf(mt)
	if mt.glow then return mt.glow end
	local h, sat, v = mt.color:ToHSV()
	return Color3.fromHSV(h, math.max(sat, 0.5), math.min(v, 0.88))
end
PM.glowOf = glowOf
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function sparkles(parent, color, tier)
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.8
	e.Rate = 2 + tier * 2
	e.Lifetime = NumberRange.new(1.2, 2.2)
	e.Speed = NumberRange.new(0.4, 1.4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Size = NumberSequence.new(0.14 + 0.04 * tier, 0)
	e.Transparency = NumberSequence.new(0.15, 1)
	e.Parent = parent
	return e
end
-- мягкая цветная дымка вокруг растения вместо твёрдого шара-ореола
local function aura(parent, color, height, tier)
	local e = Instance.new("ParticleEmitter")
	e.Texture = SMOKE
	e.Color = ColorSequence.new(color)
	e.LightEmission = 0.45
	e.Rate = 1.5 + (tier - 4)
	e.Lifetime = NumberRange.new(3, 4.5)
	e.Speed = NumberRange.new(0.2, 0.6)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, height * 0.35), NumberSequenceKeypoint.new(1, height * 0.7) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.35, 0.86), NumberSequenceKeypoint.new(1, 1) })
	e.Parent = parent
	return e
end

function PM.applyMutations(m, plant, muts, rarest, k)
	local mt = G.Mut[rarest]
	local tier = mt.tier
	local col = mt.color
	local glow = glowOf(mt)
	local matName = mt.material
	local mat = matName and MATS[matName]
	local neonType = mat == Material.Neon
	local isRainbow = table.find(muts, "rainbow") ~= nil
	local isGold = table.find(muts, "golden") ~= nil
	local isGhost = table.find(muts, "ghost") ~= nil
	local isDark = table.find(muts, "blackhole") ~= nil
	local isLava = table.find(muts, "lava") ~= nil
	for _, p in m:GetChildren() do
		if p:IsA("BasePart") and p.Name ~= "Root" then
			local n = p.Name:sub(1, 1)
			if n == "F" or n == "A" then
				local base = p.Color
				if isRainbow then
					p.Color = Color3.fromHSV((p.Position.Y * 0.18 + p.Position.X * 0.1) % 1, 0.65, 0.92)
				elseif isDark then
					p.Color = Color3.fromRGB(26, 12, 48)
				elseif isGold then
					p.Color = Color3.fromRGB(240, 190, 70)
				else
					p.Color = base:Lerp(glow, tier <= 2 and 0.45 or 0.7)
				end
				if n == "A" and (neonType or isLava) then
					-- светятся только мелкие детали, и цветом, а не белым
					p.Material = Material.Neon
					p.Color = isRainbow and p.Color:Lerp(Color3.new(0, 0, 0), 0.15) or glow:Lerp(Color3.new(0, 0, 0), 0.12)
				elseif neonType then
					-- сам плод глянцевый и цветной, без пересвета
					p.Material = Material.Glass
					p.Reflectance = 0.12
					p.Transparency = math.max(p.Transparency, 0.08)
				elseif mat then
					p.Material = mat
					if isGold then p.Reflectance = 0.35 end
				end
				if isGhost then p.Transparency = math.max(p.Transparency, 0.55) end
			elseif n == "G" and tier >= 3 then
				p.Color = p.Color:Lerp(glow, 0.6):Lerp(Color3.new(0, 0, 0), 0.1)
			end
		end
	end
	-- у редких мутаций меняется весь облик: листья и стебли тоже окрашиваются
	if tier >= 4 then
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") and (p.Name:sub(1, 1) == "L" or p.Name:sub(1, 1) == "S") then
				p.Color = isDark and p.Color:Lerp(Color3.fromRGB(30, 16, 50), 0.7) or p.Color:Lerp(glow, 0.35)
			end
		end
	end
	local root = m.PrimaryPart
	local height = 3.5 * k
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = glow, 6 + tier * 3, 0.5 + tier * 0.25
	l.Parent = root
	local att = Instance.new("Attachment")
	att.Name = "MutFx"
	att.Position = V3(0, height * 0.55, 0)
	att.Parent = root
	sparkles(att, glow, tier)
	-- светящийся круг на земле (с редкости 2): пульсирует (клиент, атрибут Pulse)
	if tier >= 2 then
		local disc = Instance.new("Part")
		disc.Name = "MutRing"
		disc.Shape = Enum.PartType.Cylinder
		disc.Size = V3(0.06, 2.4 * k + tier * 0.4, 2.4 * k + tier * 0.4)
		disc.CFrame = CF(0, 0.05, 0) * CFrame.Angles(0, 0, math.pi / 2)
		disc.Color, disc.Material, disc.Transparency = glow, Material.Neon, 0.55
		disc.Anchored, disc.CanCollide, disc.CanQuery, disc.CanTouch, disc.CastShadow = true, false, false, false, false
		disc:SetAttribute("MutPulse", tier)
		disc.Parent = m
	end
	if tier >= 3 then aura(att, glow, height, tier) end
	-- с редкости 4: контур-свечение всего растения, столб света и поднимающиеся огоньки
	if tier >= 4 then
		local hl = Instance.new("Highlight")
		hl.Name = "MutGlow"
		hl.FillColor = isDark and Color3.fromRGB(20, 8, 40) or glow
		hl.OutlineColor = isDark and Color3.fromRGB(190, 120, 255) or glow:Lerp(Color3.new(1, 1, 1), 0.25)
		hl.FillTransparency = isDark and 0.45 or (tier >= 6 and 0.7 or 0.82)
		hl.OutlineTransparency = tier >= 5 and 0 or 0.25
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = m
		local a0 = Instance.new("Attachment")
		a0.Name = "PillarBottom"
		a0.Position = V3(0, 0.2, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name = "PillarTop"
		a1.Position = V3(0, height * (tier >= 6 and 5 or tier == 5 and 3.8 or 2.6), 0)
		a1.Parent = root
		local beam = Instance.new("Beam")
		beam.Name = "MutPillar"
		beam.Attachment0, beam.Attachment1 = a0, a1
		beam.Color = ColorSequence.new(glow)
		beam.LightEmission, beam.LightInfluence = 1, 0
		beam.Width0, beam.Width1 = (1.4 + tier * 0.25) * k, 0.2 * k
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.6, 0.8), NumberSequenceKeypoint.new(1, 1) })
		beam.Parent = root
		local rise = Instance.new("ParticleEmitter")
		rise.Name = "MutRise"
		rise.Color = ColorSequence.new(glow, Color3.new(1, 1, 1))
		rise.LightEmission, rise.LightInfluence = 1, 0
		rise.Rate = 4 + tier * 2
		rise.Lifetime = NumberRange.new(1.5, 2.5)
		rise.Speed = NumberRange.new(1.5, 3)
		rise.SpreadAngle = Vector2.new(12, 12)
		rise.EmissionDirection = Enum.NormalId.Top
		rise.Size = NumberSequence.new(0.22 + 0.05 * tier, 0)
		rise.Transparency = NumberSequence.new(0, 1)
		rise.Parent = a0
	end
	-- маленькие кометы с хвостами вокруг растения
	if tier >= 5 then
		local n = tier == 5 and 3 or 5
		for j = 1, n do
			local o = ball(m, "Orbit", V3(0, 0, 0), 0.24 * k, glow, Material.Neon)
			o.CastShadow = false
			o:SetAttribute("R", (1.4 + (j % 2) * 0.45) * k)
			o:SetAttribute("H", height * (0.25 + 0.14 * j))
			o:SetAttribute("S", 1.1 + 0.25 * j)
			o:SetAttribute("P", j * 6.283 / n)
			local a0 = Instance.new("Attachment")
			a0.Position = V3(0, 0.09 * k, 0)
			a0.Parent = o
			local a1 = Instance.new("Attachment")
			a1.Position = V3(0, -0.09 * k, 0)
			a1.Parent = o
			local tr = Instance.new("Trail")
			tr.Attachment0, tr.Attachment1 = a0, a1
			tr.Color = ColorSequence.new(glow)
			tr.LightEmission = 1
			tr.Lifetime = 0.7
			tr.Transparency = NumberSequence.new(0.2, 1)
			tr.FaceCamera = true
			tr.Parent = o
		end
	end
	-- высшая редкость: воронка частиц, которые затягивает внутрь (у чёрной дыры тёмные)
	if tier >= 6 then
		local vort = Instance.new("ParticleEmitter")
		vort.Name = "MutVortex"
		vort.Color = ColorSequence.new(isDark and Color3.fromRGB(170, 110, 255) or glow, Color3.new(1, 1, 1))
		vort.LightEmission, vort.LightInfluence = 1, 0
		vort.Rate = 30
		vort.Lifetime = NumberRange.new(0.8, 1.2)
		vort.Speed = NumberRange.new(2.5, 4)
		vort.Size = NumberSequence.new(0.3, 0.05)
		vort.Transparency = NumberSequence.new(0.1, 1)
		vort.Shape = Enum.ParticleEmitterShape.Sphere
		vort.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		vort.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		vort.RotSpeed = NumberRange.new(-180, 180)
		vort.Parent = att
		-- светящееся кольцо-ореол над растением из коротких сегментов (клиент вращает)
		local R, n = 0.85 * k, 20
		for j = 1, n do
			local a = j / n * math.pi * 2
			local sp = Instance.new("Part")
			sp.Name = "MutHaloSeg"
			sp.Size = V3(0.14 * k, 0.14 * k, 2 * math.pi * R / n * 1.08)
			sp.Color, sp.Material, sp.Transparency = isDark and Color3.fromRGB(190, 120, 255) or glow, Material.Neon, 0.15
			sp.Anchored, sp.CanCollide, sp.CanQuery, sp.CanTouch, sp.CastShadow = true, false, false, false, false
			sp:SetAttribute("A", a)
			sp:SetAttribute("R", R)
			sp:SetAttribute("H", height * 1.12)
			sp.CFrame = CF(math.cos(a) * R, height * 1.12, math.sin(a) * R) * CFrame.Angles(0, -a, 0)
			sp.Parent = m
		end
	end
end

-- вращение «орбит» вокруг растения (вызывает клиент для ближних моделей)
function PM.animate(m, t: number)
	local root = m.PrimaryPart
	if not root then return end
	local rc = root.CFrame
	local okS, sc = pcall(function() return m:GetScale() end)
	if not okS or type(sc) ~= "number" then sc = 1 end
	for _, p in m:GetChildren() do
		if p.Name == "MutRing" then
			p.Transparency = 0.45 + 0.25 * (math.sin(t * 2.2 + p:GetAttribute("MutPulse")) + 1) / 2
		elseif p.Name == "MutHaloSeg" then
			local a = p:GetAttribute("A") + t * 0.6
			local r = p:GetAttribute("R") * sc
			p.CFrame = rc * CF(0, p:GetAttribute("H") * sc + math.sin(t * 1.5) * 0.15, 0) * CFrame.Angles(0.18 * math.sin(t * 0.8), 0, 0) * CF(math.cos(a) * r, 0, math.sin(a) * r) * CFrame.Angles(0, -a, 0)
		elseif p.Name == "Orbit" then
			local a = t * p:GetAttribute("S") + p:GetAttribute("P")
			local r = p:GetAttribute("R") * sc
			p.CFrame = rc * CF(cos(a) * r, p:GetAttribute("H") * sc + sin(a * 1.7) * 0.15, sin(a) * r)
		end
	end
end

PM.Forms = F
return PM
