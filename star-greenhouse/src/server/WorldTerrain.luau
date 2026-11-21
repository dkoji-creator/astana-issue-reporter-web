-- Рельеф: шесть парящих планет-островов, у каждой свой грунт. Острова висят на разной высоте и видны друг с друга.
-- groundY(x, z, planet) повторяет операции заливки и даёт высоту поверхности, чтобы ставить объекты точно на землю.
local WT = {}
WT.IslandRadius = 168
WT.PlayRadius = 156
WT.ops = {} -- [планета] = список операций

local V3 = Vector3.new
local Mat = Enum.Material
local rgb = Color3.fromRGB

-- центры планет (порядок как в Game.Planets): с каждой видно остальные над горизонтом или под краем
WT.Centers = {
	V3(0, 0, 0), -- Луна
	V3(1080, 260, 380), -- Марс
	V3(500, 620, -1080), -- Европа
	V3(-1040, 420, -470), -- Ио
	V3(-680, 860, 940), -- Туманность
	V3(280, 1250, 1210), -- Звёздное ядро
}

-- материалы рельефа: цвет материала общий на весь мир, поэтому у каждой планеты свои материалы
WT.Themes = {
	{ base = Mat.Slate, patch = { Mat.Salt, Mat.Rock }, rim = Mat.Rock, craters = true },
	{ base = Mat.Sand, patch = { Mat.Sandstone, Mat.Brick }, rim = Mat.Sandstone, craters = true },
	{ base = Mat.Glacier, patch = { Mat.Snow, Mat.Ice }, rim = Mat.Ice },
	{ base = Mat.Basalt, patch = { Mat.CrackedLava, Mat.Asphalt }, rim = Mat.Basalt },
	{ base = Mat.Grass, patch = { Mat.LeafyGrass, Mat.Mud }, rim = Mat.Mud },
	{ base = Mat.Limestone, patch = { Mat.Pavement, Mat.Cobblestone }, rim = Mat.Limestone },
}
WT.Colors = {
	[Mat.Slate] = rgb(104, 104, 118), [Mat.Salt] = rgb(190, 190, 204), [Mat.Rock] = rgb(84, 80, 96),
	[Mat.Sand] = rgb(196, 102, 64), [Mat.Sandstone] = rgb(152, 72, 50), [Mat.Brick] = rgb(122, 62, 50),
	[Mat.Glacier] = rgb(150, 200, 236), [Mat.Snow] = rgb(228, 236, 246), [Mat.Ice] = rgb(116, 166, 220),
	[Mat.Basalt] = rgb(44, 40, 46), [Mat.CrackedLava] = rgb(255, 120, 40), [Mat.Asphalt] = rgb(64, 54, 52),
	[Mat.Grass] = rgb(64, 128, 122), [Mat.LeafyGrass] = rgb(104, 92, 168), [Mat.Mud] = rgb(62, 50, 66),
	[Mat.Limestone] = rgb(212, 178, 104), [Mat.Pavement] = rgb(232, 212, 164), [Mat.Cobblestone] = rgb(170, 140, 92),
	[Mat.Ground] = rgb(74, 54, 44),
}

local function terrain() return workspace:FindFirstChildOfClass("Terrain") end

local function rec(pi, kind, x, y, z, r)
	WT.ops[pi] = WT.ops[pi] or {}
	table.insert(WT.ops[pi], { kind, x, y, z, r })
end
local function fill(pi, x, y, z, r, mat)
	local t = terrain()
	if t then t:FillBall(V3(x, y, z), r, mat) end
	rec(pi, 0, x, y, z, r)
end
local function carve(pi, x, y, z, r)
	local t = terrain()
	if t then t:FillBall(V3(x, y, z), r, Mat.Air) end
	rec(pi, 1, x, y, z, r)
end
-- тонкое пятно другого материала на поверхности (форма не меняется)
function WT.patch(x, y, z, r, mat)
	local t = terrain()
	if t then t:FillCylinder(CFrame.new(x, y - 1.5, z), 3, r, mat) end
end

function WT.planetAt(pos: Vector3): number
	local best, bd = 1, math.huge
	for i, c in WT.Centers do
		local d = (pos - c).Magnitude
		if d < bd then best, bd = i, d end
	end
	return best
end

function WT.groundY(x: number, z: number, pi: number?): number
	pi = pi or WT.planetAt(V3(x, 0, z))
	local c = WT.Centers[pi]
	local dx0, dz0 = x - c.X, z - c.Z
	local h = (dx0 * dx0 + dz0 * dz0) <= WT.IslandRadius ^ 2 and c.Y or c.Y - 60
	for _, op in WT.ops[pi] or {} do
		local dx, dz = x - op[2], z - op[4]
		local d2 = dx * dx + dz * dz
		local r = op[5]
		if d2 < r * r then
			local s = math.sqrt(r * r - d2)
			if op[1] == 0 then
				h = math.max(h, op[3] + s)
			else
				local top, bottom = op[3] + s, op[3] - s
				if h <= top and h >= bottom then h = bottom end
			end
		end
	end
	return h
end

local function polar(c, r, a) return c.X + math.cos(a) * r, c.Z + math.sin(a) * r end

local function buildIsland(pi)
	local c = WT.Centers[pi]
	local th = WT.Themes[pi]
	local t = terrain()
	local R = WT.IslandRadius
	local rng = Random.new(100 + pi)
	if t then
		t:FillCylinder(CFrame.new(c.X, c.Y - 13, c.Z), 26, R, th.base)
		-- низ острова: сужающиеся слои скалы
		local layers = { { 150, 20, -36 }, { 118, 20, -54 }, { 84, 20, -72 }, { 50, 18, -89 }, { 22, 16, -104 } }
		for _, L in layers do
			t:FillCylinder(CFrame.new(c.X, c.Y + L[3], c.Z), L[2], L[1], Mat.Rock)
		end
	end
	-- неровный низ: глыбы по краям слоёв
	for i = 1, 30 do
		local a = rng:NextNumber(0, math.pi * 2)
		local depth = rng:NextNumber(20, 95)
		local r = math.max(16, 150 - depth * 1.35)
		local x, z = polar(c, r, a)
		local t2 = terrain()
		if t2 then t2:FillBall(V3(x, c.Y - depth, z), rng:NextNumber(14, 26), Mat.Rock) end
	end
	-- холмы по краю: естественная кромка, но космос и другие планеты видны
	for i = 1, 40 do
		local a = i / 40 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local x, z = polar(c, rng:NextNumber(R - 22, R - 4), a)
		local rad = rng:NextNumber(8, 18)
		fill(pi, x, c.Y - rad * 0.45, z, rad, th.rim)
	end
	for i = 1, 6 do
		local a = rng:NextNumber(0, math.pi * 2)
		local x, z = polar(c, rng:NextNumber(R - 30, R - 14), a)
		local rad = rng:NextNumber(16, 26)
		fill(pi, x, c.Y - rad * 0.2, z, rad, th.rim)
	end
	-- пятна грунта
	for i = 1, 46 do
		local x, z = polar(c, rng:NextNumber(30, R - 10), rng:NextNumber(0, math.pi * 2))
		WT.patch(x, c.Y, z, rng:NextNumber(5, 15), th.patch[i % 2 + 1])
	end
	-- кратеры между участками и у края
	if th.craters then
		for i = 1, 6 do
			local a = (i - 0.5) / 6 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local x, z = polar(c, rng:NextNumber(130, 145), a)
			local rad = rng:NextNumber(6, 10)
			for k = 1, 8 do
				local ka = k / 8 * math.pi * 2
				fill(pi, x + math.cos(ka) * rad, c.Y - 1, z + math.sin(ka) * rad, rad * 0.32, th.rim)
			end
			carve(pi, x, c.Y + rad * 0.62, z, rad)
		end
	end
end

function WT.build()
	table.clear(WT.ops)
	local t = terrain()
	if t then
		t:Clear()
		pcall(function()
			for m, col in WT.Colors do t:SetMaterialColor(m, col) end
			t.Decoration = true -- колышущиеся травинки на траве
		end)
	end
	for pi = 1, #WT.Centers do buildIsland(pi) end
end

return WT
