-- Сценарий смоук-теста «Запусти фонарик»: сервер + клиент в одной VM, один игрок (владелец).
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
mod("ModuleScript", "Spirits", shared, "shared/Spirits")
local cfg = folder("Config", shared)
for _, n in { "Audio", "Economy", "Icons", "Spirits" } do mod("ModuleScript", n, cfg, "shared/Config/" .. n) end
local srv = folder("Server", game:GetService("ServerScriptService"))
local mainScript = mod("Script", "Main", srv, "server/Main.server")
mod("ModuleScript", "Map", srv, "server/Map")
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

stage("сервер")
SIM.runThread("Main", defs["server/Main.server"], mainScript)
frames(10)
assert(workspace:FindFirstChild("World"), "карта не построена")

stage("вход игрока")
local plr = SIM.makePlayer(8432365972, "Damirchekke")
rawset(Players.__p, "LocalPlayer", plr)
SIM.player = plr
stage("клиент")
SIM.runThread("Client", defs["client/Client.client"], clientScript)
Players.PlayerAdded:Fire(plr)
frames(5)
SIM.makeCharacter(plr)
frames(40)

local pg = plr.PlayerGui
local hud = pg:FindFirstChild("LaunchHUD")
if not hud then
	table.insert(SIM.errors, "нет LaunchHUD")
	return SIM
end
local remotes = RS:FindFirstChild("Remotes")
local function inv(name, ...) return remotes:FindFirstChild(name):InvokeServer(...) end
local Game = require(shared.Game)

stage("запуск кнопкой: зажать, подождать, отпустить")
local lb = hud:FindFirstChild("LaunchBtn", true)
if not lb then table.insert(SIM.errors, "нет кнопки ЗАПУСК") else
	lb.InputBegan:Fire({ UserInputType = Enum.UserInputType.Touch })
	frames(18) -- 0.9 с: полоска у верха
	lb.InputEnded:Fire({ UserInputType = Enum.UserInputType.Touch })
	frames(120)
end

stage("запуски напрямую: 40 штук с разной точностью")
local kinds, bestDist = {}, 0
for i = 1, 40 do
	remotes.Charge:FireServer()
	frames(i % 16 + 4) -- разное время зажатия
	local r = inv("Throw")
	if r and r.ok then
		for _, x in r.results do
			kinds[x.kind] = true
			bestDist = math.max(bestDist, x.dist)
			if x.dist < 0 or x.dist > Game.MaxDistance then table.insert(SIM.errors, "дальность вне границ: " .. x.dist) end
			if x.coins < 1 then table.insert(SIM.errors, "награда меньше 1") end
		end
	end
	frames(50) -- перезарядка
end
local n = 0
for _ in kinds do n += 1 end
stage(("видов получено: %d, лучшая дальность %d"):format(n, bestDist))
if n < 3 then table.insert(SIM.errors, "слишком мало разных духов за 40 запусков: " .. n) end

stage("запуск без зажатия отклоняется")
local bad = inv("Throw")
if bad and bad.ok then table.insert(SIM.errors, "запуск без зажатия прошёл") end

stage("админка и улучшения")
for _, cmd in { "coins", "coins", "coins", "maxPower", "perfect" } do
	local r = inv("Admin", cmd)
	if not (r and r.ok) then table.insert(SIM.errors, "Admin " .. cmd .. ": " .. tostring(r and r.msg)) end
	frames(5)
end
for _, key in Game.UpgradeOrder do
	for _ = 1, 3 do inv("Upgrade", key) end
end
inv("Admin", "allUpgrades")
inv("SetAuto", true)
frames(200) -- авто-запуск работает сам
local sum0 = 0
frames(10)
local ad = inv("Admin", "showcase")
frames(120)

stage("подарок и коды")
local d1 = inv("ClaimDaily")
if not (d1 and d1.ok) then table.insert(SIM.errors, "подарок: " .. tostring(d1 and d1.msg)) end
local d2 = inv("ClaimDaily")
if d2 and d2.ok then table.insert(SIM.errors, "подарок выдан дважды") end
local c1 = inv("Redeem", "launch")
if not (c1 and c1.ok) then table.insert(SIM.errors, "код: " .. tostring(c1 and c1.msg)) end
local c2 = inv("Redeem", "launch")
if c2 and c2.ok then table.insert(SIM.errors, "код сработал дважды") end
inv("Redeem", "nope")

stage("донат: чек")
local MPS = game:GetService("MarketplaceService")
local pr = MPS.ProcessReceipt
if pr then
	local r = pr({ PlayerId = plr.UserId, ProductId = 99999, PurchaseId = "x1" })
	if r == Enum.ProductPurchaseDecision.PurchaseGranted then table.insert(SIM.errors, "чек с чужим товаром принят") end
end

stage("клики по всем кнопкам интерфейса")
local function allButtons()
	local list = hud:GetDescendants()
	local wl = pg:FindFirstChild("SpiritWindows")
	if wl then
		for _, d in wl:GetDescendants() do table.insert(list, d) end
	end
	return list
end
for round = 1, 2 do
	for _, d in allButtons() do
		if d:IsA("TextButton") and d.Name ~= "LaunchBtn" then
			local lbl = d:FindFirstChildOfClass("TextLabel")
			if not (lbl and lbl.Text == "Сброс") then
				d.Activated:Fire()
				frames(1)
			end
		end
	end
	frames(20)
end

stage("долгий прогон 3 мин с авто-запуском")
inv("SetAuto", true)
local objBefore = #workspace:GetDescendants()
for _ = 1, 3600 do frames(1) end
local objAfter = #workspace:GetDescendants()
stage(("объектов в мире: %d -> %d"):format(objBefore, objAfter))
if objAfter > objBefore * 1.5 + 400 then table.insert(SIM.errors, "утечка объектов в мире") end

stage("нет моделей духов в центре стартовой площадки")
local stuck = {}
for _, m in workspace:GetDescendants() do
	if m:IsA("Model") and m.PrimaryPart then
		local p = m.PrimaryPart.Position
		if math.abs(p.X) < 15 and p.Z > -20 and p.Z < 18 and p.Y > 1 and p.Y < 12 then table.insert(stuck, m.Name) end
	end
end
if #stuck > 0 then table.insert(SIM.errors, "модели застряли на площадке: " .. table.concat(stuck, ", ")) end
stage("конец")
return SIM
