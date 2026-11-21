local defs = __defs
local function folder(name, parent) local f = Instance.new("Folder") f.Name = name f.Parent = parent return f end
local function mod(cls, name, parent, key) local m = Instance.new(cls) m.Name = name rawset(m.__p, "__key", key) m.Parent = parent return m end
local RS = game:GetService("ReplicatedStorage")
local shared = folder("Shared", RS)
mod("ModuleScript", "Game", shared, "shared/Game")
local cfg = folder("Config", shared)
for _, n in { "Audio", "Economy", "Icons", "Spirits" } do mod("ModuleScript", n, cfg, "shared/Config/" .. n) end
local srv = folder("Server", game:GetService("ServerScriptService"))
local mapMod = mod("ModuleScript", "Map", srv, "server/Map")
local cache = {}
require = function(m)
	local key = m.__p.__key
	if cache[key] == nil then cache[key] = defs[key](m) end
	return cache[key]
end
require(mapMod).build()
for _, p in workspace.World:GetDescendants() do
	if p:IsA("BasePart") and p.Transparency < 0.95 then
		local c = { p.CFrame:GetComponents() }
		local t = {}
		for i = 1, 12 do t[i] = ("%.3f"):format(c[i]) end
		local mesh = p:FindFirstChildOfClass("SpecialMesh")
		local shape = mesh and "Ball" or (p:IsA("WedgePart") and "Wedge" or tostring(p.Shape):gsub("Enum.PartType.", ""))
		local col = p.Color
		table.insert(SIM.log, ("P|world|%s|%s|%.2f,%.2f,%.2f|%s|%d,%d,%d|%.2f|%s"):format(p.Name, shape, p.Size.X, p.Size.Y, p.Size.Z, table.concat(t, ","),
			math.floor(col.R * 255), math.floor(col.G * 255), math.floor(col.B * 255), p.Transparency, tostring(p.Material):gsub("Enum.Material.", "")))
	end
end
return SIM
