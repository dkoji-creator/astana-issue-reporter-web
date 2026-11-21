-- Рельеф астероида из Terrain: плоская зона станции, кратеры и холмы вокруг, кольцо гор по краю (за ними не видно края мира).
-- groundY(x, z) повторяет операции заливки и даёт высоту поверхности, чтобы ставить объекты точно на землю.
local WT = {}
WT.ops = {}
WT.StationRadius = 135
WT.PlayRadius = 198
WT.BaseRadius = 262

local V3 = Vector3.new
local Mat = Enum.Material

local function terrain() return workspace:FindFirstChildOfClass("Terrain") end

local function fill(x, y, z, r, mat)
	local t = terrain()
	if t then t:FillBall(V3(x, y, z), r, mat) end
	table.insert(WT.ops, { 0, x, y, z, r })
end
local function carve(x, y, z, r)
	local t = terrain()
	if t then t:FillBall(V3(x, y, z), r, Mat.Air) end
	table.insert(WT.ops, { 1, x, y, z, r })
end
local function patch(x, z, r, mat)
	-- тонкое пятно другого материала на поверхности (форма не меняется)
	local t = terrain()
	if t then t:FillCylinder(CFrame.new(x, -1.5, z), 3, r, mat) end
end

WT.patch = function(x, z, r, mat) local t = terrain() if t then t:FillCylinder(CFrame.new(x, -1.5, z), 3, r, mat) end end

function WT.groundY(x: number, z: number): number
	local d0 = math.sqrt(x * x + z * z)
	local h = d0 <= WT.BaseRadius and 0 or -60
	for _, op in WT.ops do
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

local function polar(r, a) return math.cos(a) * r, math.sin(a) * r end

function WT.build()
	table.clear(WT.ops)
	local t = terrain()
	if t then
		t:Clear()
		pcall(function()
			t:SetMaterialColor(Mat.Basalt, Color3.fromRGB(58, 54, 72))
			t:SetMaterialColor(Mat.Rock, Color3.fromRGB(92, 90, 108))
			t:SetMaterialColor(Mat.Slate, Color3.fromRGB(66, 64, 82))
			t:SetMaterialColor(Mat.Salt, Color3.fromRGB(150, 146, 168))
			t:SetMaterialColor(Mat.Glacier, Color3.fromRGB(150, 186, 228))
			t:SetMaterialColor(Mat.Ground, Color3.fromRGB(70, 60, 74))
			t:SetMaterialColor(Mat.Limestone, Color3.fromRGB(120, 112, 140))
			t:SetMaterialColor(Mat.Grass, Color3.fromRGB(64, 128, 122))
			t:SetMaterialColor(Mat.LeafyGrass, Color3.fromRGB(98, 92, 160))
			t:SetMaterialColor(Mat.Mud, Color3.fromRGB(62, 50, 62))
			t.Decoration = true -- колышущиеся травинки на траве
		end)
		-- основание: толстый диск, верх на y = 0
		t:FillCylinder(CFrame.new(0, -16, 0), 32, WT.BaseRadius, Mat.Basalt)
		-- зона станции: тёмный сланец
		t:FillCylinder(CFrame.new(0, -1.5, 0), 3, WT.StationRadius, Mat.Slate)
	end
	local rng = Random.new(77)
	-- живая земля станции: трава, почва, песок и камень пятнами разного размера
	for i = 1, 70 do
		local x, z = polar(rng:NextNumber(36, 132), rng:NextNumber(0, math.pi * 2))
		local k = i % 7
		local mat = (k <= 2) and Mat.Grass or (k == 3 and Mat.LeafyGrass or (k == 4 and Mat.Ground or (k == 5 and Mat.Salt or Mat.Mud)))
		patch(x, z, rng:NextNumber(4, 13), mat)
	end
	-- кольцо травы вокруг площади
	for i = 1, 24 do
		local x, z = polar(rng:NextNumber(37, 44), i / 24 * math.pi * 2)
		patch(x, z, rng:NextNumber(5, 8), i % 3 == 0 and Mat.LeafyGrass or Mat.Grass)
	end
	-- внешняя зона: тоже не однотонная
	for i = 1, 40 do
		local x, z = polar(rng:NextNumber(WT.StationRadius, WT.PlayRadius), rng:NextNumber(0, math.pi * 2))
		local k = i % 5
		patch(x, z, rng:NextNumber(6, 16), ({ Mat.Ground, Mat.Salt, Mat.Rock, Mat.Grass, Mat.Mud })[k + 1])
	end
	-- холмы во внешней зоне
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(WT.StationRadius + 12, WT.PlayRadius - 8)
		local rad = rng:NextNumber(8, 20)
		local x, z = polar(r, a)
		fill(x, -rad * 0.62, z, rad, i % 3 == 0 and Mat.Rock or Mat.Basalt)
	end
	-- кратеры с валами
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local r = rng:NextNumber(WT.StationRadius + 18, WT.PlayRadius - 18)
		local rad = rng:NextNumber(8, 16)
		local x, z = polar(r, a)
		for k = 1, 10 do
			local ka = k / 10 * math.pi * 2
			fill(x + math.cos(ka) * rad * 0.95, -1.2, z + math.sin(ka) * rad * 0.95, rad * 0.32, Mat.Rock)
		end
		carve(x, rad * 0.62, z, rad)
		patch(x, z, rad * 0.55, Mat.Salt)
	end
	-- предгорья и кольцо гор
	for i = 1, 46 do
		local a = i / 46 * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
		local x, z = polar(rng:NextNumber(WT.PlayRadius - 6, WT.PlayRadius + 8), a)
		local rad = rng:NextNumber(9, 16)
		fill(x, -rad * 0.3, z, rad, Mat.Rock)
	end
	for i = 1, 64 do
		local a = i / 64 * math.pi * 2 + rng:NextNumber(-0.04, 0.04)
		local r = rng:NextNumber(WT.PlayRadius + 18, WT.BaseRadius - 18)
		local rad = rng:NextNumber(22, 46)
		local y = rng:NextNumber(-8, 26)
		local x, z = polar(r, a)
		fill(x, y, z, rad, ({ Mat.Rock, Mat.Basalt, Mat.Slate, Mat.Limestone })[i % 4 + 1])
		if rad + y > 50 then
			fill(x, y + rad * 0.82, z, rad * 0.32, Mat.Glacier)
		end
	end
end

return WT
