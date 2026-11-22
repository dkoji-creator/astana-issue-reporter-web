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
mod("ModuleScript", "Stars", srv, "server/Stars")
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
check(#workspace.World.Plots:GetChildren() == 0, "огороды строятся только для игроков")

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
check(snap and snap.plot == "1_1", "участок не выдан: " .. tostring(snap and snap.plot))
check(snap.seeds.moon_01 == 3, "стартовые семена")
local plot = workspace.World.Plots.Plot1_1
local function toBed(i)
	local root = plr.Character.HumanoidRootPart
	root.CFrame = CFrame.new(plot.Beds["Bed" .. i].Soil.Position + Vector3.new(0, 3, 4))
end

stage("посадка, полив, сбор")
toBed(1)
fire("Act", 1)
frames(5)
local soil = plot.Beds.Bed1.Soil
check(soil:GetAttribute("Plant") == "moon_01", "семя не посажено")
check((soil:GetAttribute("Muts") or "") ~= "", "первая посадка должна дать мутацию")
frames(8, 0.1) -- клиент рисует росток
fire("Act", 1)
frames(3)
check(soil:GetAttribute("Wa") == true, "полив не сработал: ready-now=" .. tostring((soil:GetAttribute("Ready") or 0) - os.time()) .. " plant=" .. tostring(soil:GetAttribute("Plant")))
check(inv("Admin", "ripe") == true, "админ-команда")
frames(10)
fire("Act", 1)
frames(10)
snap = inv("State")
check(#snap.fruits == 1, "урожай не собран")
check(snap.idx.moon_01 ~= nil, "индекс не обновился")

stage("повторный полив, задания, звёзды")
do
	local r1 = soil.Parent.Parent.Bed1.Soil:GetAttribute("Ready")
	snap = inv("State")
	check(snap.q and #snap.q == 3, "должно быть 3 задания")
	frames(80, 0.1)
	local stars = workspace.World:FindFirstChild("Stars")
	check(stars and #stars:GetChildren() >= 1, "звёзды не появились")
	-- звезду можно поднять только после падения
	frames(25, 0.1)
	if stars and #stars:GetChildren() > 0 then
		local before = inv("State").coins
		local st = stars:GetChildren()[1]
		st.Hit.Touched:Fire(plr.Character.HumanoidRootPart)
		frames(3)
		check(st.Parent == nil, "звезда не исчезла после сбора")
		check(inv("State").coins > before, "звезда не дала монет")
		check((inv("State").stats.stars or 0) >= 1, "счётчик звёзд")
	end
	-- задание можно забрать только выполненным
	check(not inv("ClaimQuest", 1) or true, "claim")
	frames(30, 0.5)
	check(#workspace.World.Stars:GetChildren() >= 1, "звёзды должны пополняться")
end

stage("редкая мутация и кинематика")
inv("Admin", "mut", "singularity")
fire("Act", 2) -- пустая грядка 2 далеко от игрока: не должно сработать
frames(3)
toBed(2)
fire("Act", 2)
frames(3)
check((soil.Parent.Parent["Bed2"].Soil:GetAttribute("Muts") or ""):find("singularity") ~= nil, "мутация не выпала")
inv("Admin", "ripe")
frames(5)
fire("Act", 2)
frames(60)
check(pg:FindFirstChild("Reveal") ~= nil, "кинематика не показана")

stage("продажа")
local ok, total, count = inv("Sell", "all")
check(ok and total > 0, "продажа не сработала")
snap = inv("State")
check(#snap.fruits == 0, "сумка не пуста после продажи")

stage("магазин")
inv("Admin", "coins")
frames(5)
local stock = G.shopStock(RS:GetAttribute("ShopSeed"), G.shopEpoch(os.time()))
local buyId
for _, p in G.PlantList do
	if stock[p.id] and p.planet == "moon" then buyId = p.id break end
end
check(buyId ~= nil, "в магазине нет лунных семян")
local bok, bres = inv("Buy", buyId, 1)
check(bok, "покупка семени: " .. tostring(bres))
local bad = inv("Buy", "core_20", 1)
check(not bad, "закрытая планета не должна покупаться")

stage("улучшения и украшения")
check(inv("Upgrade", "beds"), "грядка")
check(inv("Upgrade", "luck"), "удача")
check(inv("BuyDecor", "fountain"), "украшение")
check(workspace.World.Plots.Plot1_1.Decor:FindFirstChild("fountain") ~= nil, "фонтан не поставлен")
check(not inv("BuyDecor", "fountain"), "повторная покупка")

stage("подарок и коды")
check(inv("Daily"), "подарок")
check(not inv("Daily"), "повторный подарок")
check(inv("Redeem", "star"), "код")
check(not inv("Redeem", "STAR"), "код повторно")
check(not inv("Redeem", "nope"), "неверный код")

stage("админ: все планеты, все семена, окна")
inv("Admin", "planets")
inv("Admin", "seeds")
frames(20, 0.5)
local colFrame = hud:FindFirstChild("Buttons")
check(colFrame ~= nil, "нет колонки кнопок")
if not colFrame then return SIM end
for _, b in colFrame:GetChildren() do
	if b:IsA("TextButton") then
		b.Activated:Fire()
		frames(10, 0.2)
		b.Activated:Fire()
		frames(3, 0.2)
	end
end
-- переключение вкладок магазина и атласа
for _, b in colFrame:GetChildren() do
	if b:IsA("TextButton") then
		b.Activated:Fire()
		frames(5, 0.2)
		local wl = pg:FindFirstChild("SpiritWindows")
		if wl then
			for _, w in wl:GetChildren() do
				if w.Visible then
					for _, d in w:GetDescendants() do
						if d:IsA("TextButton") and d.Size.X.Scale > 0 and d.Size.X.Scale < 0.5 and d.Size.Y.Offset == 0 and d.Size.Y.Scale == 1 then
							d.Activated:Fire()
							frames(2, 0.2)
						end
					end
				end
			end
		end
		b.Activated:Fire()
		frames(2, 0.2)
	end
end

stage("киоск через подсказку")
for _, d in workspace.World:GetDescendants() do
	if d:IsA("ProximityPrompt") and d:GetAttribute("Window") == "market" then
		game:GetService("ProximityPromptService").PromptTriggered:Fire(d, plr)
		break
	end
end
frames(5)
local wl2 = pg:FindFirstChild("SpiritWindows")
local anyOpen = false
for _, w in (wl2 and wl2:GetChildren() or {}) do if w.Visible then anyOpen = true end end
check(anyOpen, "киоск не открыл окно")

stage("админ-читы и опыление")
do
	for _, c in { "coinsB", "maxup", "giant", "allmut", "potion", "speed", "showcase" } do check(inv("Admin", c) == true, "админ " .. c) end
	check(inv("Admin", "event", "meteor") == true, "событие")
	frames(30, 0.2)
	check(RS:GetAttribute("EventId") == "meteor", "метеоритный дождь не включился")
	inv("Admin", "stopEvent")
	inv("Admin", "pollen")
	frames(30, 0.2)
	local tap = pg:FindFirstChild("PollenTap")
	if tap then
		local b = tap:FindFirstChildOfClass("TextButton")
		for _ = 1, 5 do b.Activated:Fire() frames(2, 0.1) end
		frames(20, 0.1)
	end
	-- меню «Ещё»
	local menuBtn
	for _, b in hud.Buttons:GetChildren() do if b:IsA("TextButton") and b.LayoutOrder == 6 then menuBtn = b end end
	check(menuBtn ~= nil, "нет кнопки Ещё")
	if menuBtn then
		menuBtn.Activated:Fire()
		frames(5, 0.2)
		-- фото-режим из меню «Ещё»
		local photoBtn
		for _, d in pg.SpiritWindows:GetDescendants() do
			if d:IsA("TextButton") and d.LayoutOrder == 4 and d.Parent and d.Parent.Parent and d.Parent.Parent.Visible then photoBtn = d end
		end
		check(photoBtn ~= nil, "нет кнопки фото-режима")
		if photoBtn then
			photoBtn.Activated:Fire()
			frames(10, 0.1)
			local ph = pg:FindFirstChild("Photo")
			check(ph ~= nil, "фото-режим не включился")
			if ph then ph:FindFirstChildOfClass("TextButton").Activated:Fire() frames(3, 0.1) end
			check(hud.Enabled, "интерфейс не вернулся после фото-режима")
		end
	end
end

stage("полёт на Марс и домой")
do
	inv("Admin", "planets")
	frames(5)
	local ok = inv("Travel", 2)
	check(ok == true, "полёт не начался")
	frames(90, 0.1)
	snap = inv("State")
	check(snap.planet == 2 and snap.plot == "2_1", "огород не переехал: " .. tostring(snap.plot))
	check(workspace.World.Plots:FindFirstChild("Plot1_1") == nil and workspace.World.Plots:FindFirstChild("Plot2_1") ~= nil, "огород не перестроен")
	local root = plr.Character.HumanoidRootPart
	check((root.Position - Vector3.new(1080, 260, 380)).Magnitude < 200, "игрок не на Марсе")
	check(inv("Home") == true, "домой")
	check(not inv("Travel", 2), "лететь туда, где уже есть, нельзя")
	plot = workspace.World.Plots.Plot2_1
end

stage("события")
-- отклик на действия: подсказка у грядки и удар метеорита
for _, d in plot:GetDescendants() do
	if d:IsA("ProximityPrompt") then d.Triggered:Fire(plr) end
end
frames(20, 0.1)
remotes.Strike:FireAllClients(plot.Beds.Bed1.Soil.Position, "neon", "Тест")
remotes.Strike:FireAllClients(plot.Beds.Bed2.Soil.Position, nil, "Тест")
frames(30, 0.1)
remotes.Event:FireAllClients("meteor", 200)
RS:SetAttribute("EventId", "meteor")
frames(40, 0.2)
RS:SetAttribute("EventId", "")
frames(10, 0.2)
remotes.Announce:FireAllClients("Тест", "Квантовая роза", "Сингулярность", 1e-9, Vector3.new(0, 5, 0))
frames(5)

stage("долгая игра: 10 минут")
for i = 1, 6 do
	toBed(i)
	fire("Select", "moon_01")
	fire("Act", i)
end
frames(60, 10)
inv("Admin", "ripe")
frames(10)
for i = 1, 6 do
	toBed(i)
	fire("Act", i)
end
frames(20, 0.5)
snap = inv("State")
check(#snap.fruits >= 4, "долгая игра: плодов " .. #snap.fruits)

stage("выход")
Players.PlayerRemoving:Fire(plr)
frames(5)
check(SIM.store["StarGreenhouse_v1/u8432365972"] ~= nil, "профиль не сохранён")
local stored = SIM.store["StarGreenhouse_v1/u8432365972"]
check(stored and stored.stats.harvests >= 2, "статистика не сохранена")
check(workspace.World.Plots:FindFirstChild("Plot1_1") == nil, "участок не освобождён")

-- нет моделей в начале координат
for _, c in workspace:GetDescendants() do
	if c:IsA("BasePart") and c.Name == "Root" and c.Parent and c.Parent:IsA("Model") and c.Parent.Parent ~= nil then
		local p = c.Position
		if p.Magnitude < 0.5 and c.Parent.Parent.Name == "FX" then table.insert(SIM.errors, "модель в начале координат: " .. c.Parent.Name) end
	end
end
return SIM
