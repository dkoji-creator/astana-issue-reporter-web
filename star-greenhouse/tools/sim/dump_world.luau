local defs = __defs
local function folder(name, parent) local f = Instance.new("Folder") f.Name = name f.Parent = parent return f end
local function mod(cls, name, parent, key) local m = Instance.new(cls) m.Name = name rawset(m.__p, "__key", key) m.Parent = parent return m end
local RS = game:GetService("ReplicatedStorage")
local shared = folder("Shared", RS)
mod("ModuleScript", "Game", shared, "shared/Game")
mod("ModuleScript", "PlantModels", shared, "shared/PlantModels")
local cfg = folder("Config", shared)
for _, n in { "Plants", "Mutations", "Icons", "Sky", "Planets" } do mod("ModuleScript", n, cfg, "shared/Config/" .. n) end
local srv = folder("Server", game:GetService("ServerScriptService"))
local mapMod = mod("ModuleScript", "Map", srv, "server/Map")
mod("ModuleScript", "WorldTerrain", srv, "server/WorldTerrain")
local cache = {}
require = function(m)
	local key = m.__p.__key
	if cache[key] == nil then cache[key] = defs[key](m) end
	return cache[key]
end
local Map = require(mapMod)
Map.build()
local G = require(shared.Game)
for i = 1, 3 do Map.placeDecor(1, G.DecorOrder[i]) end
for _, id in G.DecorOrder do Map.placeDecor(2, id) end
local n = 0
for _, p in workspace.World:GetDescendants() do
	if p:IsA("BasePart") and p.Transparency < 0.97 then
		local c = { p.CFrame:GetComponents() }
		local t = {}
		for i = 1, 12 do t[i] = ("%.3f"):format(c[i]) end
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		local shape = mesh and "Ball" or tostring(p.Shape):gsub("Enum.PartType.", "")
		local col = p.Color
		table.insert(SIM.log, ("P|world|%s|%s|%.2f,%.2f,%.2f|%s|%d,%d,%d|%.2f|%s"):format(p.Name, shape, p.Size.X, p.Size.Y, p.Size.Z, table.concat(t, ","),
			math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), p.Transparency, tostring(p.Material):gsub("Enum.Material.", "")))
		n += 1
	end
end
local MC = { Grass = { 64, 128, 122 }, LeafyGrass = { 98, 92, 160 }, Mud = { 62, 50, 62 }, Cobblestone = { 118, 112, 128 }, Basalt = { 58, 54, 72 }, Rock = { 92, 90, 108 }, Slate = { 66, 64, 82 }, Salt = { 150, 146, 168 }, Glacier = { 150, 186, 228 }, Ground = { 70, 60, 74 }, Limestone = { 120, 112, 140 } }
for _, op in SIM.terrain do
	local mat = tostring(op[#op]):gsub("Enum.Material.", "")
	local col = MC[mat]
	if col then
		local cf, size, shape
		if op[1] == "ball" then
			cf, size, shape = CFrame.new(op[2]), Vector3.new(op[3] * 2, op[3] * 2, op[3] * 2), "Ball"
		elseif op[1] == "cyl" then
			cf, size, shape = op[2] * CFrame.Angles(0, 0, math.pi / 2), Vector3.new(op[3], op[4] * 2, op[4] * 2), "Cylinder"
		end
		if cf then
			local c = { cf:GetComponents() }
			local t = {}
			for i = 1, 12 do t[i] = ("%.3f"):format(c[i]) end
			table.insert(SIM.log, ("P|world|T|%s|%.2f,%.2f,%.2f|%s|%d,%d,%d|0.00|Slate"):format(shape, size.X, size.Y, size.Z, table.concat(t, ","), col[1], col[2], col[3]))
		end
	end
end
table.insert(SIM.log, "# parts " .. n)
return SIM
