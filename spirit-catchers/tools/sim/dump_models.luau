-- Выгрузка моделей духов для просмотра (tools/render_models.py): SCENARIO=tools/sim/dump_models.luau node tools/sim/run.mjs
local defs = __defs
local function folder(name, parent)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end
local function mod(cls, name, parent, key)
	local m = Instance.new(cls)
	m.Name = name
	rawset(m.__p, "__key", key)
	m.Parent = parent
	return m
end
local RS = game:GetService("ReplicatedStorage")
local shared = folder("Shared", RS)
mod("ModuleScript", "Catalog", shared, "shared/Catalog")
local spiritsMod = mod("ModuleScript", "Spirits", shared, "shared/Spirits")
local cfg = folder("Config", shared)
for _, n in { "Audio", "Economy", "Icons", "Monetization", "Progress", "Spirits", "Worlds", "Live" } do
	mod("ModuleScript", n, cfg, "shared/Config/" .. n)
end
local cache = {}
require = function(m)
	local key = m.__p.__key
	if cache[key] == nil then cache[key] = defs[key](m) end
	return cache[key]
end
local Spirits = require(spiritsMod)
local Catalog = require(shared.Catalog)
local only = {}
for _, k in Catalog.Order do
	local ok, m = pcall(Spirits.Builders[k])
	if ok and m then
		pcall(Spirits.animate, m, CFrame.new(), 0.3)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				local c = { p.CFrame:GetComponents() }
				local mesh = p:FindFirstChildOfClass("SpecialMesh")
				local shape = mesh and "Ball" or (p:IsA("WedgePart") and "Wedge" or tostring(p.Shape):gsub("Enum.PartType.", ""))
				local col = p.Color
				table.insert(SIM.log, ("P|%s|%s|%s|%.3f,%.3f,%.3f|%s|%d,%d,%d|%.2f|%s"):format(k, p.Name, shape, p.Size.X, p.Size.Y, p.Size.Z,
					table.concat((function() local t = {} for i = 1, 12 do t[i] = ("%.4f"):format(c[i]) end return t end)(), ","),
					math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), p.Transparency, tostring(p.Material):gsub("Enum.Material.", "")))
			end
		end
	else
		table.insert(SIM.errors, "модель " .. k .. ": " .. tostring(m))
	end
end
return SIM
