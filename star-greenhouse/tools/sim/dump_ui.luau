-- Смоук-тест «Звёздной оранжереи»: сервер + клиент в одной VM, один игрок (владелец).
local defs = __defs
local function folder(name, parent) local f = Instance.new("Folder") f.Name = name f.Parent = parent return f end
local function mod(cls, name, parent, key)
	local m = Instance.new(cls)
	m.Name = name
	rawset(m.__p, "__key", key)
	m.Parent = parent
	return m
end
local RS = game:GetService("ReplicatedStorage")
local shared = folder("Shared", RS)
mod("ModuleScript", "Game", shared, "shared/Game")
mod("ModuleScript", "PlantModels", shared, "shared/PlantModels")
local cfg = folder("Config", shared)
for _, n in { "Plants", "Mutations", "Icons", "Sky", "Planets", "Audio", "PlantMeshes" } do mod("ModuleScript", n, cfg, "shared/Config/" .. n) end
local srv = folder("Server", game:GetService("ServerScriptService"))
local mainScript = mod("Script", "Main", srv, "server/Main.server")
mod("ModuleScript", "Map", srv, "server/Map")
mod("ModuleScript", "WorldTerrain", srv, "server/WorldTerrain")
mod("ModuleScript", "PlantLoader", srv, "server/PlantLoader")
local sps = folder("StarterPlayerScripts", game:GetService("StarterPlayer"))
local cl = folder("Client", sps)
local clientScript = mod("LocalScript", "Client", cl, "client/Client.client")
mod("ModuleScript", "UIKit", cl, "client/UIKit")

local cache = {}
require = function(m)
	local key = m.__p.__key
	assert(key, "require: не модуль " .. tostring(m))
	if cache[key] == nil then
		local f = defs[key]
		assert(f, "нет исходника " .. key)
		cache[key] = f(m)
	end
	return cache[key]
end

-- InsertService:LoadAsset в эмуляторе: возвращает модель с мешами двух растений
do
	local ins = game:GetService("InsertService")
	rawset(ins.__p, "LoadAsset", function(self, id)
		local m = Instance.new("Model")
		for _, pid in { "moon_01", "mars_01" } do
			for _, role in { "F", "A", "L", "G", "R" } do
				local nm = Instance.new("Model")
				nm.Name = pid .. "__" .. role .. "_Node"
				nm.Parent = m
				local mp = Instance.new("MeshPart")
				mp.Name = pid .. "__" .. role
				mp.Size = Vector3.new(1, 2, 1)
				mp.CFrame = CFrame.new(0, 1, 0)
				mp.Parent = nm
			end
		end
		return m
	end)
end
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local function frames(n, dt)
	dt = dt or 1 / 20
	for _ = 1, n do
		RunService.Heartbeat:Fire(dt)
		RunService.RenderStepped:Fire(dt)
		SIM.step(dt)
	end
end
local function stage(name) table.insert(SIM.log, "== " .. name .. " (" .. #SIM.errors .. " ошибок)") end
local function check(cond, msg) if not cond then table.insert(SIM.errors, "ПРОВЕРКА: " .. msg) end end

local G = require(shared.Game)
local PM = require(shared.PlantModels)

stage("каталог")
check(#G.PlantList == 120, "растений должно быть 120, а их " .. #G.PlantList)
local seen = {}
for _, p in G.PlantList do
	check(not seen[p.id], "дубль id " .. p.id)
	seen[p.id] = true
	check(p.grow > 0 and p.sell > 0 and p.seed > 0 and p.kg > 0, "плохие числа у " .. p.id)
	check(p.seed < p.sell * 3 or p.rarity ~= "common", "цена семени слишком высока " .. p.id)
end
local mythic = 0
for _, p in G.PlantList do if p.rarity == "mythic" then mythic += 1 end end
check(mythic == 6, "мифических должно быть 6")
check(math.abs(G.Mut.singularity.chance - 1e-9) < 1e-12, "сингулярность должна быть 1 к миллиарду")
stage("модели всех растений и мутаций")
for _, p in G.PlantList do
	local m = PM.build(p.id, nil)
	check(m:FindFirstChild("Root") ~= nil, "нет Root у " .. p.id)
	check(#m:GetChildren() > 4, "слишком простая модель " .. p.id)
	PM.animate(m, 1)
end
for _, id in G.MutOrder do
	local m = PM.build("nebula_20", { id })
	check(m ~= nil, "мутация " .. id)
	PM.animate(m, 2)
end
-- математика
local r = Random.new(1)
local kg = G.rollWeight(G.Plants.moon_01, r, {})
check(kg > 0, "вес")
check(G.fmtOdds(1 / 1000000000) == "1 к 1 000 000 000", "fmtOdds " .. G.fmtOdds(1 / 1000000000))
check(G.fmt(1234567) == "1.23M", "fmt " .. G.fmt(1234567))
local st = G.shopStock(5, 100)
local cnt = 0
for _ in st do cnt += 1 end
check(cnt > 5, "ассортимент магазина пуст")
local ev, left = G.eventAt(os.time())
check(ev ~= nil and left > 0, "события")

stage("сервер")
SIM.runThread("Main", defs["server/Main.server"], mainScript)
frames(10)
check(workspace:FindFirstChild("World") ~= nil, "карта не построена")
check(#workspace.World.Plots:GetChildren() == 8, "участков должно быть 8")

stage("меши растений (поддельные шаблоны)")
do
	local root = RS:FindFirstChild("PlantMeshes")
	check(root ~= nil, "нет папки PlantMeshes")
	check(root:FindFirstChild("moon_01") ~= nil, "загрузчик не разложил шаблоны")
	check(RS:GetAttribute("MeshesReady") == true, "MeshesReady не выставлен")
	check(PM.hasMeshes("moon_01"), "шаблон не найден")
	local m = PM.build("moon_01", nil)
	check(m:FindFirstChild("FM") ~= nil and m:FindFirstChild("GM") ~= nil, "модель не собрана из мешей")
	check(m:FindFirstChild("GM").Material == Enum.Material.Neon, "свечение должно быть Neon")
	local m2 = PM.build("moon_01", { "golden", "giant" })
	check(m2:FindFirstChild("FM").Color.R > 0.9, "золотая мутация не перекрасила меш")
	check(not PM.hasMeshes("moon_02"), "для moon_02 шаблона быть не должно")
	check(PM.build("moon_02", nil) ~= nil, "запасная модель")
end

stage("вход игрока")
local plr = SIM.makePlayer(8432365972, "Damirchekke")
rawset(Players.__p, "LocalPlayer", plr)
SIM.player = plr
stage("клиент")
Players.PlayerAdded:Fire(plr)
frames(20)
SIM.makeCharacter(plr)
frames(30)
SIM.runThread("Client", defs["client/Client.client"], clientScript)
frames(40)

local pg = plr.PlayerGui
local hud = pg:FindFirstChild("StarHUD")
if not hud then
	table.insert(SIM.errors, "нет StarHUD")
	return SIM
end
local remotes = RS:FindFirstChild("Remotes")
local function inv(name, ...) return remotes:FindFirstChild(name):InvokeServer(...) end
local function fire(name, ...) remotes:FindFirstChild(name):FireServer(...) end

local snap = inv("State")
check(snap and snap.plot == 1, "участок не выдан")
check(snap.seeds.moon_01 == 3, "стартовые семена")
local plot = workspace.World.Plots.Plot1
local function toBed(i)
	local root = plr.Character.HumanoidRootPart
	root.CFrame = CFrame.new(plot.Beds["Bed" .. i].Soil.Position + Vector3.new(0, 3, 4))
end


-- ===== выгрузка дерева интерфейса для tools/render_ui.py =====
inv("Admin", "coins")
inv("Admin", "seeds")
frames(30, 0.2)
local PROPS = { "Size", "Position", "AnchorPoint", "Visible", "BackgroundColor3", "BackgroundTransparency", "ZIndex", "LayoutOrder", "Text", "TextColor3",
	"TextTransparency", "TextXAlignment", "TextYAlignment", "TextScaled", "TextSize", "TextWrapped", "Font", "Image", "ImageTransparency", "AutomaticSize",
	"FillDirection", "Padding", "HorizontalAlignment", "VerticalAlignment", "CellSize", "CellPadding", "PaddingTop", "PaddingBottom", "PaddingLeft",
	"PaddingRight", "CornerRadius", "Color", "Thickness", "Transparency", "Scale", "MaxTextSize", "MinTextSize", "MaxSize", "DisplayOrder", "ApplyStrokeMode", "Rotation", "CanvasPosition" }
local function enc(v)
	local t = type(v)
	if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "0" or ("%.4f"):format(v) end
	if t == "boolean" then return tostring(v) end
	if t == "string" then return '"' .. v:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub("\n", "\\n") .. '"' end
	if t == "table" then
		local mt = getmetatable(v)
		if mt == U2 then return ("[%s,%s,%s,%s]"):format(enc(v.X.Scale), enc(v.X.Offset), enc(v.Y.Scale), enc(v.Y.Offset)) end
		if mt == C3 then return ("[%s,%s,%s]"):format(enc(v[1]), enc(v[2]), enc(v[3])) end
		if mt == V2 then return ("[%s,%s]"):format(enc(v[1]), enc(v[2])) end
		if rawget(v, "__t") == "ColorSequence" then
			local a = v.a
			local c1 = a[1]
			local c2 = a[2] or a[1]
			if getmetatable(c1) ~= C3 then return "null" end
			return "[" .. enc(c1) .. "," .. enc(c2) .. "]"
		end
		if mt == V3 then return ("[%s,%s,%s]"):format(enc(v[1]), enc(v[2]), enc(v[3])) end
		if rawget(v, "Scale") ~= nil and rawget(v, "Offset") ~= nil then return ("[%s,%s]"):format(enc(v.Scale), enc(v.Offset)) end
		if rawget(v, "Name") and rawget(v, "EnumType") then return '"' .. v.Name .. '"' end
		return "null"
	end
	return "null"
end
local nid = 0
local function node(inst)
	nid += 1
	local p = rawget(inst, "__p")
	local parts = { '"c":' .. enc(p.ClassName), '"n":' .. enc(p.Name) }
	for _, k in PROPS do
		local v = rawget(p, k)
		if v ~= nil then table.insert(parts, '"' .. k .. '":' .. enc(v)) end
	end
	local kids = {}
	for _, ch in rawget(inst, "__c") do table.insert(kids, node(ch)) end
	table.insert(parts, '"k":[' .. table.concat(kids, ",") .. "]")
	return "{" .. table.concat(parts, ",") .. "}"
end
local function dumpState(name)
	local guis = {}
	for _, g in pg:GetChildren() do
		if g.ClassName == "ScreenGui" then table.insert(guis, node(g)) end
	end
	table.insert(SIM.log, "UI|" .. name .. "|[" .. table.concat(guis, ",") .. "]")
end
dumpState("hud")
local colFrame = hud:FindFirstChild("Buttons")
local names = { "shop", "bag", "index", "market", "upgrades", "daily", "admin" }
local i = 0
for _, b in colFrame:GetChildren() do
	if b:IsA("TextButton") then
		i += 1
		b.Activated:Fire()
		frames(10, 0.3)
		dumpState(names[i] or ("w" .. i))
		b.Activated:Fire()
		frames(3, 0.3)
	end
end
return SIM
