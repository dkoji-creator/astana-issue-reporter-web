-- Выгрузка моделей растений для tools/render_models.py (по одной на форму + варианты мутаций).
local defs = __defs
local function folder(name, parent) local f = Instance.new("Folder") f.Name = name f.Parent = parent return f end
local function mod(cls, name, parent, key) local m = Instance.new(cls) m.Name = name rawset(m.__p, "__key", key) m.Parent = parent return m end
local RS = game:GetService("ReplicatedStorage")
local shared = folder("Shared", RS)
mod("ModuleScript", "Game", shared, "shared/Game")
mod("ModuleScript", "PlantModels", shared, "shared/PlantModels")
mod("ModuleScript", "Fx3D", shared, "shared/Fx3D")
local cfg = folder("Config", shared)
for _, n in { "Plants", "Mutations", "Icons", "Sky" } do mod("ModuleScript", n, cfg, "shared/Config/" .. n) end
local cache = {}
require = function(m)
	local key = m.__p.__key
	if cache[key] == nil then cache[key] = defs[key](m) end
	return cache[key]
end
local G = require(shared.Game)
local PM = require(shared.PlantModels)

local want = {}
local list = {}
local filter = _G.DUMP_FILTER
for _, p in G.PlantList do
	if not want[p.form] then want[p.form] = true table.insert(list, { kind = p.form, id = p.id, muts = {} }) end
end
table.insert(list, { kind = "m_frost_giant", id = "moon_06", muts = { "frost", "giant" } })
table.insert(list, { kind = "m_gold", id = "mars_02", muts = { "golden" } })
table.insert(list, { kind = "m_rainbow", id = "europa_03", muts = { "rainbow" } })
table.insert(list, { kind = "m_galactic", id = "io_03", muts = { "galactic" } })
table.insert(list, { kind = "m_singular", id = "nebula_20", muts = { "singularity", "neon" } })
table.insert(list, { kind = "m_ghost", id = "core_09", muts = { "ghost" } })
local count = 0
for _, e in list do
	local m = PM.build(e.id, e.muts)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") and p.Name ~= "Root" and p.Transparency < 0.97 then
			local c = { p.CFrame:GetComponents() }
			local t = {}
			for i = 1, 12 do t[i] = ("%.3f"):format(c[i]) end
			local mesh = p:FindFirstChildOfClass("SpecialMesh")
			local shape = mesh and "Ball" or tostring(p.Shape):gsub("Enum.PartType.", "")
			if shape == "Block" and not mesh then shape = "Block" end
			local col = p.Color
			table.insert(SIM.log, ("P|%s|%s|%s|%.2f,%.2f,%.2f|%s|%d,%d,%d|%.2f|%s"):format(e.kind, p.Name, shape, p.Size.X, p.Size.Y, p.Size.Z, table.concat(t, ","),
				math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), p.Transparency, tostring(p.Material):gsub("Enum.Material.", "")))
			count += 1
		end
	end
end
table.insert(SIM.log, "# parts " .. count)
return SIM
