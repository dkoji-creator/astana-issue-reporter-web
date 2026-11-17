-- Сценарий смоук-теста: сервер + клиент в одной VM, один игрок (владелец).
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
mod("ModuleScript", "Spirits", shared, "shared/Spirits")
local cfg = folder("Config", shared)
for _, n in { "Audio", "Economy", "Icons", "Monetization", "Progress", "Spirits", "Worlds" } do
	mod("ModuleScript", n, cfg, "shared/Config/" .. n)
end
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

------------------------------------------------------------------ сервер
stage("сервер")
SIM.runThread("Main", defs["server/Main.server"], mainScript)
frames(10)
assert(workspace:FindFirstChild("World"), "карта не построена")

stage("вход игрока")
local plr = SIM.makePlayer(8432365972, "Damirchekke")
rawset(Players.__p, "LocalPlayer", plr)
SIM.player = plr
-- клиент запускается раньше событий сервера, как в Roblox (события ставятся в очередь)
stage("клиент")
SIM.runThread("Client", defs["client/Client.client"], clientScript)
Players.PlayerAdded:Fire(plr)
frames(5)
SIM.makeCharacter(plr)
frames(40)

local pg = plr.PlayerGui
local intro = pg:FindFirstChild("Intro")
stage("заставка: " .. tostring(intro ~= nil))
if intro then
	for _, d in intro:GetDescendants() do
		if d:IsA("TextButton") then d.Activated:Fire() break end
	end
end
frames(30)
local hud = pg:FindFirstChild("SpiritHUD")
if not hud then
	table.insert(SIM.errors, "нет SpiritHUD")
	return SIM
end

local remotes = RS:FindFirstChild("Remotes")
local function inv(name, ...)
	local r = remotes:FindFirstChild(name)
	return r:InvokeServer(...)
end

stage("админка")
for _, cmd in { "coins", "dust", "level", "level", "level", "allSpirits", "maxUpgrades", "passes", "fillJar", "fast", "fast", "fireworks" } do
	local r = inv("Admin", cmd)
	if not (r and r.ok) then table.insert(SIM.errors, "Admin " .. cmd .. " -> " .. tostring(r and r.msg)) end
	frames(2)
end

stage("клики по всем кнопкам")
local skip = { ["Сброс прогресса"] = true, ["Переродиться"] = true, ["Сбросить"] = true }
for round = 1, 2 do
	for _, d in hud:GetDescendants() do
		if d:IsA("TextButton") then
			local lbl = d:FindFirstChildOfClass("TextLabel")
			local text = lbl and lbl.Text or ""
			if not skip[text] then
				d.MouseButton1Down:Fire()
				d.Activated:Fire()
				d.MouseButton1Up:Fire()
				frames(1)
			end
		end
	end
	frames(20)
end

stage("ловля")
do -- освободить банку: сдать у алтаря
	local altar0 = workspace.World:FindFirstChild("Altar")
	plr.Character.HumanoidRootPart.CFrame = CFrame.new(altar0.Position + Vector3.new(0, 3, 4))
	altar0:FindFirstChildOfClass("ProximityPrompt").Triggered:Fire(plr)
	frames(10)
end
inv("Admin", "spawn", "PaperFox", "golden")
frames(5)
local root = plr.Character.HumanoidRootPart
local spirits = workspace:FindFirstChild("Spirits")
local anchor
for _, a in spirits:GetChildren() do
	if a:GetAttribute("Kind") == "PaperFox" and a:GetAttribute("Variant") == "golden" then anchor = a end
end
if anchor then
	root.CFrame = CFrame.new(anchor.Position + Vector3.new(0, 2, 4))
	remotes.CatchHold:FireServer(anchor:GetAttribute("SpiritId"))
	remotes.CatchZone:FireServer(true)
	frames(120)
	if anchor.Parent then table.insert(SIM.errors, "дух не пойман за 6 с") end
else
	table.insert(SIM.errors, "админ-призыв не создал духа")
end

stage("сдача у алтаря")
local altar = workspace.World:FindFirstChild("Altar")
root.CFrame = CFrame.new(altar.Position + Vector3.new(0, 3, 4))
local prompt = altar:FindFirstChildOfClass("ProximityPrompt")
prompt.Triggered:Fire(plr)
frames(60)

stage("красная луна")
inv("Admin", "moon")
frames(200)
inv("Admin", "endMoon")
frames(40)

stage("телепорты, коды, таланты, зелье")
for _, d in { "plaza", "street", "canal", "garden", "grove", "market" } do inv("Teleport", d) frames(2) end
inv("Redeem", "beta")
inv("Redeem", "WELCOME")
inv("Redeem", "nope")
for _, t in { "swift", "sense", "grip", "fortune", "greed" } do inv("Talent", "up", t) end
inv("Talent", "reset")
inv("BuyPotion")
frames(40)
for _ = 1, 20 do inv("Admin", "level") end
local rb = inv("Rebirth")
if not (rb and rb.ok) then table.insert(SIM.errors, "перерождение не сработало: " .. tostring(rb and rb.msg)) end
frames(40)

stage("покупка (ProcessReceipt)")
local MPS = game:GetService("MarketplaceService")
local pr = MPS.ProcessReceipt
if pr then
	for _, id in { 3732892660, 3732892697, 3732895300, 3732892769 } do
		local r = pr({ PlayerId = plr.UserId, ProductId = id, PurchaseId = "p" .. id })
		if r ~= Enum.ProductPurchaseDecision.PurchaseGranted then table.insert(SIM.errors, "чек не выдан: " .. id) end
	end
end
frames(60)

stage("долгий прогон 60 с")
frames(1200)
stage("конец")
return SIM
