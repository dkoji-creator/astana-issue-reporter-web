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
for _, n in { "Audio", "Economy", "Icons", "Monetization", "Progress", "Spirits", "Worlds", "Live" } do
	mod("ModuleScript", n, cfg, "shared/Config/" .. n)
end
local srv = folder("Server", game:GetService("ServerScriptService"))
local mainScript = mod("Script", "Main", srv, "server/Main.server")
mod("ModuleScript", "Map", srv, "server/Map")
mod("ModuleScript", "Social", srv, "server/Social")
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

stage("спутник, сезон, испытания, модификаторы")
inv("Equip", "PaperFox")
local fr = inv("FeedCompanion")
if not (fr and fr.ok) then table.insert(SIM.errors, "кормление спутника: " .. tostring(fr and fr.msg)) end
for _ = 1, 7 do inv("Admin", "mod") frames(2) end
inv("Admin", "season")
local sr = inv("ClaimSeason", 1)
if not (sr and sr.ok) then table.insert(SIM.errors, "награда сезона: " .. tostring(sr and sr.msg)) end
inv("ClaimSeason", 5)
inv("SetTitle", "")
inv("Admin", "raid")
frames(5)
if not workspace:GetAttribute("RaidActive") then table.insert(SIM.errors, "рейд не начался") end
do
	local g = workspace:FindFirstChild("RaidGiant")
	if g and g.PrimaryPart then
		-- встать перед духом и смотреть на него
		local gp = g.PrimaryPart.Position
		local from = gp + Vector3.new(0, -10, 20)
		plr.Character.HumanoidRootPart.CFrame = CFrame.lookAt(from, Vector3.new(gp.X, from.Y, gp.Z))
		for _ = 1, 40 do
			remotes.RaidHit:FireServer()
			frames(5)
		end
		if (workspace:GetAttribute("RaidLit") or 0) <= 0 and workspace:GetAttribute("RaidActive") then table.insert(SIM.errors, "рейд: удары не засчитаны") end
	else
		table.insert(SIM.errors, "нет Великого фонарного духа")
	end
end
frames(2200) -- рейд заканчивается по времени
if workspace:GetAttribute("RaidActive") then table.insert(SIM.errors, "рейд не закончился") end
frames(20)
for round = 1, 1 do
	for _, d in hud:GetDescendants() do
		if d:IsA("TextButton") then
			local lbl = d:FindFirstChildOfClass("TextLabel")
			local text = lbl and lbl.Text or ""
			if not skip[text] then
				d.Activated:Fire()
				frames(1)
			end
		end
	end
end

stage("двор, обмен, клуб")
do
	local yards = workspace:FindFirstChild("Yards")
	if not yards then table.insert(SIM.errors, "нет дворов") end
	local v = inv("VisitYard", plr.UserId)
	if not (v and v.ok) then table.insert(SIM.errors, "свой двор: " .. tostring(v and v.msg)) end
	frames(10)
	-- второй игрок (без клиента): обмен и лайк
	local p2 = SIM.makePlayer(222, "Friend")
	Players.PlayerAdded:Fire(p2)
	frames(5)
	SIM.makeCharacter(p2)
	frames(20)
	local srvTrade = remotes.Trade.OnServerInvoke
	local r1 = inv("Trade", "request", 222)
	if not (r1 and r1.ok) then table.insert(SIM.errors, "запрос обмена: " .. tostring(r1 and r1.msg)) end
	local r2 = srvTrade(p2, "respond", true)
	if not (r2 and r2.ok) then table.insert(SIM.errors, "принять обмен: " .. tostring(r2 and r2.msg)) end
	frames(2)
	local give
	for _, k in { "PaperFox", "Umbrella", "Firefly", "Kodama" } do give = give or k end
	local before = 0
	inv("Admin", "allSpirits")
	inv("Admin", "allSpirits")
	inv("Trade", "add", "PaperFox")
	inv("Trade", "ready", true)
	srvTrade(p2, "ready", true)
	frames(80)
	local p2saved = nil
	-- проверяем через состояние: обмен закрыт
	local r3 = inv("Trade", "cancel")
	if r3 and r3.ok then table.insert(SIM.errors, "обмен не завершился") end
	-- лайк двора первого игрока
	for _, plot in yards:GetChildren() do
		if plot:IsA("Folder") and plot:GetAttribute("Owner") == plr.UserId then
			local sign = plot:FindFirstChild("Sign")
			local pp = sign and sign:FindFirstChildOfClass("ProximityPrompt")
			if pp then pp.Triggered:Fire(p2) else table.insert(SIM.errors, "нет кнопки лайка") end
		end
	end
	-- клуб
	local c1 = inv("Club", "create", "Ночные ловцы")
	if not (c1 and c1.ok) then table.insert(SIM.errors, "клуб: " .. tostring(c1 and c1.msg)) end
	frames(10)
	local code = c1 and c1.msg and string.match(c1.msg, "(%w%w%w%w%w)$")
	local srvClub = remotes.Club.OnServerInvoke
	local j = srvClub(p2, "join", code or "")
	if not (j and j.ok) then table.insert(SIM.errors, "вступить в клуб: " .. tostring(j and j.msg)) end
	frames(10)
	Players.PlayerRemoving:Fire(p2)
	p2.Parent = nil
	frames(10)
end

stage("зеркальное озеро")
do
	for _ = 1, 25 do inv("Admin", "level") end
	local t = inv("Teleport", "mirror")
	if not (t and t.ok) then table.insert(SIM.errors, "телепорт на озеро: " .. tostring(t and t.msg)) end
	frames(10)
	for _, k in { "EchoFirefly", "LilyFrog", "MirrorKoi", "GlassHeron", "TwinMoon" } do
		local root2 = plr.Character.HumanoidRootPart
		inv("Admin", "spawn", k)
		frames(3)
	end
	frames(60)
	local n = 0
	for _, a in workspace.Spirits:GetChildren() do
		if Catalog and false then end
		local kind = a:GetAttribute("Kind")
		if kind == "GlassHeron" or kind == "EchoFirefly" then n += 1 end
	end
	if n == 0 then table.insert(SIM.errors, "духи озера не появились") end
	local hidden = 0
	for _, a in workspace.Spirits:GetChildren() do
		if a.Position.X < -300 and not a:GetAttribute("Revealed") then hidden += 1 end
	end
	stage("на озере скрытых духов: " .. hidden)
	inv("Redeem", "MIRROR")
	for _ = 1, 12 do inv("Admin", "allSpirits") end
	local ev = inv("Evolve", "PaperFox")
	if not (ev and (ev.ok or string.find(tostring(ev.msg), "Уже"))) then table.insert(SIM.errors, "пробуждение: " .. tostring(ev and ev.msg)) end
	for _ = 1, 5 do inv("Admin", "coins") end
	local bf = inv("BuyFurniture", "torii")
	if not (bf and (bf.ok or string.find(tostring(bf.msg), "Уже"))) then table.insert(SIM.errors, "мебель: " .. tostring(bf and bf.msg)) end
	inv("BuyFurniture", "fountain")
	inv("BuyFurniture", "garland")
	local pr = inv("ClaimSeason", 3, true)
	if not (pr and (pr.ok or string.find(tostring(pr.msg), "Уже"))) then table.insert(SIM.errors, "премиум сезона: " .. tostring(pr and pr.msg)) end
	frames(30)
end

stage("небесный рынок и праздник")
do
	for _ = 1, 10 do inv("Admin", "level") end
	local t = inv("Teleport", "skymarket")
	if not (t and t.ok) then table.insert(SIM.errors, "телепорт на небесный рынок: " .. tostring(t and t.msg)) end
	inv("Admin", "holiday")
	frames(200)
	local hidden = 0
	for _, a in workspace.Spirits:GetChildren() do
		if a.Position.X > 300 and not a:GetAttribute("Revealed") then hidden += 1 end
	end
	stage("на небесном рынке скрытых духов: " .. hidden)
	if hidden == 0 then table.insert(SIM.errors, "на небесном рынке нет духов") end
	-- падение с крыши возвращает на рынок
	plr.Character.HumanoidRootPart.CFrame = CFrame.new(265 * 1.6 + 29, -10, 30 * 1.6)
	frames(10)
	if plr.Character.HumanoidRootPart.Position.Y < -3 then table.insert(SIM.errors, "после падения не вернуло на крышу") end
end

stage("сюжет и ночной страж")
do
	local keeper = workspace:FindFirstChild("AltarKeeper")
	if not keeper then table.insert(SIM.errors, "нет Хранителя алтаря") end
	local pp = keeper and keeper:FindFirstChild("Robe") and keeper.Robe:FindFirstChildOfClass("ProximityPrompt")
	if pp then pp.Triggered:Fire(plr) end
	frames(5)
	inv("Story", "claim")
	inv("Admin", "boss", "street")
	frames(5)
	local a = workspace:FindFirstChild("NightBoss")
	if not a then
		table.insert(SIM.errors, "ночной страж не появился")
	else
		local from = a.Position + Vector3.new(0, 0, 15)
		plr.Character.HumanoidRootPart.CFrame = CFrame.lookAt(from, Vector3.new(a.Position.X, from.Y, a.Position.Z))
		for _ = 1, 30 do
			plr.Character.HumanoidRootPart.CFrame = CFrame.lookAt(a.Position + Vector3.new(0, 0, 15), a.Position)
			remotes.BossHit:FireServer()
			frames(5)
		end
		local hp = a.Parent and a:GetAttribute("HP") or 0
		if a.Parent and hp >= a:GetAttribute("MaxHP") then table.insert(SIM.errors, "страж: удары не засчитаны") end
		frames(2500)
		if workspace:FindFirstChild("NightBoss") then table.insert(SIM.errors, "страж не ушёл") end
	end
end

stage("достижения")
for _, id in { "first", "c50", "k10", "kall", "golden", "lvl25", "reborn", "legend" } do inv("ClaimAchievement", id) end
frames(20)

stage("долгий прогон 4 мин (луна → туманная ночь)")
local sawFog = false
for _ = 1, 4800 do
	frames(1)
	if workspace:GetAttribute("FogActive") then sawFog = true end
end
if not sawFog then table.insert(SIM.errors, "туманная ночь не наступила") end
stage("конец")
return SIM
