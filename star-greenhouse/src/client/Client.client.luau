-- «Звёздная оранжерея»: клиент. Интерфейс, показ растений рядом с игроком, эффекты событий и показ редких мутаций.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local MarketplaceService = game:GetService("MarketplaceService")

local plr = Players.LocalPlayer
local pg = plr:WaitForChild("PlayerGui")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local G = require(Shared:WaitForChild("Game"))
local PM = require(Shared:WaitForChild("PlantModels"))
local K = require(script.Parent:WaitForChild("UIKit"))
local T = K.T
local make = K.make
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local world = workspace:WaitForChild("World")
local plotsFolder = world:WaitForChild("Plots")
local ADMIN_ID = 8432365972
plr.CameraMaxZoomDistance = 90
local SoundService = game:GetService("SoundService")
local Audio = require(Shared:WaitForChild("Config"):WaitForChild("Audio"))

-- звуки: музыка и эффекты (если ассет недоступен, игра просто молчит)
local FX = {} -- эффекты (заполняются ниже, вызываются раньше)
local sfx = {}
local AUDIO = { m = 6, s = 8, h = 1, t = 1 } -- t: 1 = классика, 2 = космос -- громкость музыки и звуков (0-10), подсказки вкл/выкл; приходят с сервера
local sfxGroup = make("SoundGroup", { Name = "Sfx", Volume = 0.8 }, SoundService)
local musicGroup = make("SoundGroup", { Name = "Music", Volume = 0.36 }, SoundService)
local function applyAudio()
	musicGroup.Volume = AUDIO.m / 10 * 0.6
	sfxGroup.Volume = AUDIO.s / 10
end
do
	local all = {}
	-- частые звуки держат несколько копий, чтобы накладываться друг на друга
	local MANY = { click = 3, tap = 4, laser = 4, boom = 4, coins = 3, beep = 2, plant = 3, water = 3, star = 3 }
	for k, id in Audio.Sfx do
		if id ~= "rbxassetid://" then
			local pool = {}
			for i = 1, MANY[k] or 2 do
				pool[i] = make("Sound", { Name = k .. i, SoundId = id, SoundGroup = sfxGroup, Volume = (Audio.Gain and Audio.Gain[k]) or 1 }, SoundService)
				table.insert(all, pool[i])
			end
			sfx[k] = { pool = pool, i = 0 }
		end
	end
	local music = make("Sound", { Name = "MusicMain", SoundId = Audio.Music.main, Looped = true, SoundGroup = musicGroup, Volume = 1 }, SoundService)
	local music2 = make("Sound", { Name = "MusicSpace", SoundId = Audio.Music.space or Audio.Music.main, Looped = true, SoundGroup = musicGroup, Volume = 1 }, SoundService)
	table.insert(all, music)
	table.insert(all, music2)
	-- проверка: сколько звуков реально загрузилось (видно в настройках)
	function FX.audioStatus()
		local ok, total = 0, 0
		for _, snd in all do
			total += 1
			if snd.IsLoaded and snd.TimeLength > 0 then ok += 1 end
		end
		return ok, total, music.IsLoaded and music.TimeLength > 0
	end
	-- встроенный звук клиента Roblox: играет всегда, если звук на устройстве вообще работает
	local builtin = make("Sound", { Name = "BuiltinPing", SoundId = "rbxasset://sounds/electronicpingshort.wav", Volume = 1 }, SoundService)
	function FX.testSound()
		builtin:Play()
		task.delay(0.6, function()
			local e = sfx.coins
			if e then e.pool[1].TimePosition = 0 e.pool[1]:Play() end
		end)
	end
	function FX.setTrack(tk)
		local on, off = music, music2
		if tk == 2 then on, off = music2, music end
		if off.IsPlaying then off:Stop() end
		if not on.IsPlaying then on:Play() end
	end
	applyAudio()
	task.spawn(function()
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(all) end)
	end)
	task.spawn(function()
		task.wait(1)
		FX.setTrack(AUDIO.t)
	end)
end
local function playSfx(name, pitch)
	local e = sfx[name]
	if not e then return end
	e.i = e.i % #e.pool + 1
	local snd = e.pool[e.i]
	snd.PlaybackSpeed = pitch or 1
	snd.TimePosition = 0
	snd:Play()
end
K.onClick(function() playSfx("click") end)

local function nowS() return workspace:GetServerTimeNow() end
-- фоновый цикл: ошибка в одной итерации не убивает цикл
local function loop(dt, fn)
	task.spawn(function()
		while true do
			task.wait(dt)
			local ok, err = pcall(fn)
			if not ok then warn("loop error", err) end
		end
	end)
end

------------------------------------------------------------------ состояние
local ST = {
	coins = 0, earned = 0, seeds = {}, fruits = {}, upg = { luck = 1, speed = 1, water = 1, sprinkler = 0 }, decor = {}, idx = {}, mutSeen = {},
	perms = {}, potion = { luck = 1, uses = 0 }, bedCount = 6, plot = nil, bagCap = 120, stats = {}, sel = nil, bought = {}, sold = {},
	daily = { can = false, streak = 0 }, planets = 1,
}
local UI = {} -- ссылки на элементы
local hooks = {} -- обновления окон
local dirty = {}

local function onSync(patch)
	for k, v in patch do
		ST[k] = v
		dirty[k] = true
	end
end
remotes:WaitForChild("Sync").OnClientEvent:Connect(onSync)
do
	local snap
	for _ = 1, 60 do
		snap = remotes:WaitForChild("State"):InvokeServer()
		if snap then break end
		task.wait(0.5)
	end
	if snap then onSync(snap) end
end

local function plantName(id) return G.Plants[id].name end
local function rarityColor(id) return G.Rarity[G.Plants[id].rarity].color end

------------------------------------------------------------------ вспомогательные элементы
local function listLayout(parent, dir, pad, hAlign)
	return make("UIListLayout", {
		FillDirection = dir or Enum.FillDirection.Vertical, Padding = UDim.new(0, pad or 6), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left,
	}, parent)
end
local function padding(parent, p)
	return make("UIPadding", { PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p), PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p) }, parent)
end
local function label(parent, text, props)
	local l = make("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = T.sub, Font = Enum.Font.GothamBold, TextScaled = true,
		Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in props or {} do
		if k ~= "MaxText" then l[k] = v end
	end
	make("UITextSizeConstraint", { MaxTextSize = (props and props.MaxText) or 18, MinTextSize = 8 }, l)
	return l
end
local function clear(frame)
	for _, c in frame:GetChildren() do
		if not c:IsA("UIListLayout") and not c:IsA("UIGridLayout") and not c:IsA("UIPadding") and not c:IsA("UISizeConstraint") then c:Destroy() end
	end
end

-- модель для окна: без света и частиц; silhouette — чёрный силуэт для ещё не найденных
local function cardModel(id, muts, silhouette)
	local m = PM.build(id, muts)
	for _, d in m:GetDescendants() do
		if d:IsA("Light") or d:IsA("ParticleEmitter") or d:IsA("Attachment") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			if d.Name == "Orbit" or d.Name == "H" then d:Destroy() end
		end
	end
	if silhouette then
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") then
				d.Color = Color3.fromRGB(14, 12, 24)
				d.Material = Enum.Material.SmoothPlastic
				d.Transparency = math.min(d.Transparency, 0.1)
			end
		end
	end
	return m
end

local function modelView(parent, id, muts, silhouette, props)
	local m = cardModel(id, muts, silhouette)
	local vp, setAngle = K.viewport(parent, m, props)
	return vp, setAngle
end

------------------------------------------------------------------ HUD
local hud = make("ScreenGui", { Name = "StarHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, pg)
local uiScale = make("UIScale", {}, hud)
local function fitScale()
	local cam = workspace.CurrentCamera
	local h = cam and cam.ViewportSize.Y or 720
	uiScale.Scale = math.clamp(h / 420, 0.72, 1.3)
end
fitScale()
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fitScale) end

local toastHolder = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 110), Size = UDim2.fromOffset(400, 200), ZIndex = 20 }, hud)
listLayout(toastHolder, nil, 4, Enum.HorizontalAlignment.Center)
local function toast(text, kind, dur)
	local col = kind == "ok" and T.green or kind == "bad" and T.red or kind == "rare" and T.gold or T.sub
	if kind == "bad" then playSfx("error") end
	local f = make("Frame", { Size = UDim2.fromOffset(380, 28), BackgroundColor3 = T.panel, BackgroundTransparency = 0.12, ZIndex = 21 }, toastHolder)
	K.corner(f, UDim.new(0, 9))
	K.stroke(f, col, 1, false, 0.35)
	K.text(f, text, { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), TextColor3 = col, MaxText = 15, ZIndex = 22 })
	task.delay(dur or 3.2, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			task.wait(0.4)
			f:Destroy()
		end
	end)
	local kids = {}
	for _, c in toastHolder:GetChildren() do
		if c:IsA("Frame") then table.insert(kids, c) end
	end
	while #kids > 4 do
		table.remove(kids, 1):Destroy()
	end
end
remotes:WaitForChild("Notify").OnClientEvent:Connect(toast)

-- монеты и прогресс планет
do
	local top = make("Frame", { Name = "Top", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(260, 70) }, hud)
	local pill, lbl = K.pill(top, "coin", T.gold, 190)
	pill.AnchorPoint = Vector2.new(0.5, 0)
	pill.Position = UDim2.new(0.5, 0, 0, 0)
	UI.coins = lbl
	local bar, fill = K.bar(top, T.cold, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 42), Size = UDim2.fromOffset(200, 5) })
	UI.planetFill = fill
	UI.planetText = K.text(top, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 50), Size = UDim2.fromOffset(260, 15), MaxText = 12, TextColor3 = T.sub, Medium = true })
	local tb = make("TextButton", { Name = "Leaders", AnchorPoint = Vector2.new(0, 0), Position = UDim2.new(0.5, 100, 0, 0), Size = UDim2.fromOffset(38, 38),
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false }, top)
	K.corner(tb, UDim.new(1, 0))
	K.stroke(tb, T.gold, 1.2, false, 0.3)
	K.icon(tb, "trophy", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(6, 6) })
	tb.Activated:Connect(function()
		K.bounce(tb)
		playSfx("click")
		if FX.openLeaders then FX.openLeaders() end
	end)
end

-- плашка события и подсказка
do
	local f = K.panel(hud, { Name = "Event", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(230, 46) })
	UI.eventFrame = f
	UI.eventTitle = K.text(f, "", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 4), MaxText = 15 })
	UI.eventSub = K.text(f, "", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 25), MaxText = 12, TextColor3 = T.sub, Medium = true })
	local hint = K.panel(hud, { Name = "Hint", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(380, 26) })
	K.stroke(hint, T.gold, 1, false, 0.4)
	UI.hintFrame = hint
	UI.hint = K.text(hint, "", { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxText = 15, TextColor3 = T.gold, Medium = true })
end

------------------------------------------------------------------ окна: общий каркас
local windows = {}
local function openWindow(id)
	playSfx("pop")
	for k, w in windows do
		if k ~= id and w.Visible then K.close(w) end
	end
	local w = windows[id]
	if not w then return end
	if w.Visible then
		K.close(w)
		return
	end
	if hooks[id] then hooks[id]() end
	K.open(w)
end
local function mkWindow(id, title, icon, color, w, h)
	local f, body = K.window(hud, title, icon, color, w, h)
	windows[id] = f
	return f, body
end
local function tabs(parent, items, onPick, height)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, height or 34) }, parent)
	listLayout(row, Enum.FillDirection.Horizontal, 6)
	local buttons = {}
	for i, it in items do
		local b = K.button(row, it.text, it.color or T.panel2, { Size = UDim2.new(1 / #items, -6, 1, 0), MaxText = 16, LayoutOrder = i })
		buttons[it.key] = b
		b.Activated:Connect(function() onPick(it.key) end)
	end
	return row, buttons
end
local function shade(buttons, active, items)
	for _, it in items do
		K.recolor(buttons[it.key], it.key == active and (it.color or T.blue) or T.panel2)
	end
end

------------------------------------------------------------------ окно: магазин семян
-- общий каркас «листа»: шапка (таймер/счётчик и вкладки) прокручивается вместе с карточками
local function sheetLayout(body, cell)
	local scroll = K.scroll(body, {})
	listLayout(scroll, nil, 8)
	local head = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 66), LayoutOrder = 0 }, scroll)
	local grid = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 1 }, scroll)
	local gl = make("UIGridLayout", { CellSize = cell, CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Left }, grid)
	return scroll, head, grid, gl
end
local function planetTabs(head, extra, onPick)
	local items = {}
	for i, p in G.Planets do table.insert(items, { key = i, text = p.name, color = G.PlanetColors[i] }) end
	if extra then table.insert(items, extra) end
	local row, btns = tabs(head, items, onPick, 30)
	row.Position = UDim2.fromOffset(0, 32)
	return items, btns
end
local function coinButton(parent, amount, can, props)
	local b = K.button(parent, G.fmt(amount), can and T.green or T.panel2, props)
	local lbl = b:FindFirstChildOfClass("TextLabel")
	if lbl then
		lbl.Position = UDim2.new(0, 26, 0, 4)
		lbl.Size = UDim2.new(1, -32, 1, -8)
	end
	K.icon(b, "coin", { Size = UDim2.fromOffset(18, 18), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0) })
	return b
end
do
	local f, body = mkWindow("shop", "Магазин семян", "shop", T.green, 0.92, 0.84)
	local scroll, head, grid = sheetLayout(body, UDim2.fromOffset(236, 92))
	UI.shopTimer = K.text(head, "", { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, TextColor3 = T.gold })
	UI.shopTab = 1
	local planetItems, tabBtns
	planetItems, tabBtns = planetTabs(head, nil, function(k) UI.shopTab = k hooks.shop() end)
	function hooks.shop()
		local epoch = G.shopEpoch(nowS())
		local stock = G.shopStock(ReplicatedStorage:GetAttribute("ShopSeed") or 0, epoch)
		local sold = ST.sold or {}
		shade(tabBtns, UI.shopTab, planetItems)
		clear(grid)
		local tab = UI.shopTab
		local unlocked = tab <= ST.planets
		local n = 0
		for i, p in G.PlantList do
			if G.PlanetIndex[p.planet] == tab and stock[p.id] then
				local left = stock[p.id] - (sold[p.id] or 0)
				n += 1
				local card = K.panel(grid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
				local rc = rarityColor(p.id)
				local strip = make("Frame", { Size = UDim2.new(0, 3, 1, -16), Position = UDim2.fromOffset(0, 8), BackgroundColor3 = rc, BorderSizePixel = 0 }, card)
				K.corner(strip, UDim.new(1, 0))
				local vpHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(78, 78) }, card)
				modelView(vpHolder, p.id, nil, false)
				K.text(card, p.name, { Position = UDim2.fromOffset(88, 6), Size = UDim2.new(1, -94, 0, 18), MaxText = 15, TextColor3 = rc, TextXAlignment = Enum.TextXAlignment.Left })
				K.text(card, G.Rarity[p.rarity].name .. "  ·  " .. G.fmtTime(p.grow), { Position = UDim2.fromOffset(88, 25), Size = UDim2.new(1, -94, 0, 14), MaxText = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Medium = true })
				local lim = G.Rarity[p.rarity].limit - ((ST.bought or {})[p.id] or 0)
				K.text(card, ("есть %d  ·  лимит %d"):format(math.max(0, left), math.max(0, lim)), { Position = UDim2.fromOffset(88, 40), Size = UDim2.new(1, -94, 0, 13), MaxText = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Medium = true })
				local can = unlocked and left > 0 and lim > 0
				local btn = coinButton(card, p.seed, can, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -7), Size = UDim2.new(1, -96, 0, 28), MaxText = 15 })
				btn.Activated:Connect(function()
					local ok, res = remotes.Buy:InvokeServer(p.id, 1)
					if ok then toast("Куплено: " .. p.name, "ok") playSfx("coins") else toast(res or "Не получилось", "bad") end
				end)
			end
		end
		if not unlocked then
			label(grid, "Планета откроется после " .. G.fmt(G.PlanetUnlock[tab]) .. " заработанных монет", { Size = UDim2.new(1, 0, 0, 40), TextColor3 = T.sub, MaxText = 18 })
		elseif n == 0 then
			label(grid, "Сейчас на этой планете пусто. Ассортимент скоро обновится", { Size = UDim2.new(1, 0, 0, 40), TextColor3 = T.sub, MaxText = 18 })
		end
	end
end

------------------------------------------------------------------ окно: мистический торговец
do
	local f, body = mkWindow("mystic", "Мистический торговец", "potion", T.purple, 0.92, 0.84)
	local scroll, head, grid = sheetLayout(body, UDim2.fromOffset(236, 92))
	UI.mysticTimer = K.text(head, "", { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, TextColor3 = T.purple })
	function hooks.mystic()
		local open, left, epoch = G.mysticOpen(nowS(), ReplicatedStorage:GetAttribute("MysticForce"))
		local pi = ST.planet or 1
		UI.mysticTimer.Text = open and ("Редкие травы планеты %s · уйдёт через %s"):format(G.Planets[pi].name, G.fmtTime(left)) or ("Торговец появится через " .. G.fmtTime(left))
		clear(grid)
		if not open then
			label(grid, "Торговец приходит на площадь каждой планеты раз в 10 минут на 3 минуты", { Size = UDim2.new(1, 0, 0, 40), TextColor3 = T.sub, MaxText = 16 })
			return
		end
		for i, it in G.mysticStock(epoch, pi) do
			local p = G.Plants[it.id]
			local bought = (ST.mystic or {})[epoch .. ":" .. it.id] or 0
			local leftN = it.limit - bought
			local card = K.panel(grid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
			local rc = rarityColor(p.id)
			K.stroke(card, rc, 1.2, false, 0.35)
			local vpHolder = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(78, 78) }, card)
			modelView(vpHolder, p.id, nil, false)
			K.text(card, p.name, { Position = UDim2.fromOffset(88, 6), Size = UDim2.new(1, -94, 0, 18), MaxText = 15, TextColor3 = rc, TextXAlignment = Enum.TextXAlignment.Left })
			K.text(card, G.Rarity[p.rarity].name .. "  ·  " .. G.fmtTime(p.grow), { Position = UDim2.fromOffset(88, 25), Size = UDim2.new(1, -94, 0, 14), MaxText = 12, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Medium = true })
			K.text(card, ("осталось %d"):format(math.max(0, leftN)), { Position = UDim2.fromOffset(88, 40), Size = UDim2.new(1, -94, 0, 13), MaxText = 11, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Left, Medium = true })
			local btn = coinButton(card, it.price, leftN > 0 and ST.coins >= it.price, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -8, 1, -7), Size = UDim2.new(1, -96, 0, 28), MaxText = 15 })
			btn.Activated:Connect(function()
				local ok, res = remotes.BuyMystic:InvokeServer(it.id)
				if ok then toast("Куплено: " .. p.name, "rare") playSfx("chest") else toast(res or "Не получилось", "bad") end
			end)
		end
	end
	loop(2, function()
		local track = world:FindFirstChild("Planet2") and world.Planet2:FindFirstChild("Landmark")
		local start = track and track:FindFirstChild("RaceTrack")
		if not start then return end
		for _, d in start:GetDescendants() do
			if d:IsA("BillboardGui") and d:GetAttribute("RaceBest") then
				local sub = d:FindFirstChild("Sub")
				local best = ST.race and ST.race.best or 0
				if sub then sub.Text = best > 0 and ("твой рекорд %.1f с · золото до %d с"):format(best, G.Race.gold) or ("13 ворот, успей за %d с на золото"):format(G.Race.gold) end
			end
		end
	end)
	-- появление торговца: уведомление со звуком и таймер над лавкой
	local wasOpen
	loop(1, function()
		local open, left = G.mysticOpen(nowS(), ReplicatedStorage:GetAttribute("MysticForce"))
		if wasOpen ~= nil and open and not wasOpen then
			toast("На площади появился мистический торговец: редкие травы, 3 минуты!", "rare", 5)
			playSfx("unlock")
		end
		wasOpen = open
		if open then
			for pi = 1, #G.Planets do
				local pf = world:FindFirstChild("Planet" .. pi)
				local stall = pf and pf:FindFirstChild("Hub") and pf.Hub:FindFirstChild("MysticStall")
				if stall then
					for _, d in stall:GetDescendants() do
						if d:IsA("BillboardGui") and d:GetAttribute("Mystic") then
							local sub = d:FindFirstChild("Sub")
							if sub then sub.Text = "уйдёт через " .. G.fmtTime(left) end
						end
					end
				end
			end
		end
		if windows.mystic.Visible then hooks.mystic() end
	end)
end

------------------------------------------------------------------ окно: сумка и продажа
do
	local f, body = mkWindow("bag", "Сумка урожая", "jar", T.gold, 0.92, 0.84)
	local left = K.scroll(body, { Size = UDim2.new(0.55, -6, 1, -50) })
	listLayout(left, nil, 4)
	local right = K.panel(body, { Position = UDim2.new(0.55, 4, 0, 0), Size = UDim2.new(0.45, -4, 1, -50), BackgroundColor3 = T.panel2 })
	-- снизу вверх: подсказка, кнопки, три строки описания; превью занимает всё остальное
	local vpHold = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 1, -150) }, right)
	local info = K.text(right, "Выбери плод слева", { Position = UDim2.new(0, 6, 1, -140), Size = UDim2.new(1, -12, 0, 20), MaxText = 17 })
	local info2 = K.text(right, "", { Position = UDim2.new(0, 6, 1, -118), Size = UDim2.new(1, -12, 0, 15), MaxText = 13, TextColor3 = T.sub, Medium = true })
	local info3 = K.text(right, "", { Position = UDim2.new(0, 6, 1, -101), Size = UDim2.new(1, -12, 0, 17), MaxText = 15, TextColor3 = T.gold })
	local sellOne = K.button(right, "Продать этот", T.green, { Position = UDim2.new(0, 8, 1, -78), Size = UDim2.new(0.55, -10, 0, 32), MaxText = 15 })
	local favBtn = K.button(right, "Избранное", T.purple, { Position = UDim2.new(0.55, 2, 1, -78), Size = UDim2.new(0.45, -10, 0, 32), MaxText = 14 })
	local sellAll = K.button(body, "Продать всё", T.gold, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 42), MaxText = 22 })
	UI.bagInfo = K.text(right, "", { Position = UDim2.new(0, 6, 1, -40), Size = UDim2.new(1, -12, 0, 32), MaxText = 12, TextColor3 = T.sub, TextWrapped = true, Medium = true })
	local selUid
	local previewVp
	local function priceOf(fr)
		local p = G.Plants[fr.id]
		local mm = G.marketMult(p, G.marketEpoch(nowS()))
		local ev, _, active = G.eventAt(nowS())
		return G.fruitValue(fr.id, fr.m, fr.w, mm, (active and ev.sell) or 1)
	end
	local function select(fr)
		selUid = fr and fr.uid
		if previewVp then previewVp:Destroy() previewVp = nil end
		if not fr then
			info.Text, info2.Text, info3.Text = "Выбери плод слева", "", ""
			return
		end
		previewVp = modelView(vpHold, fr.id, fr.m, false)
		info.Text = G.mutTitle(fr.m) ~= "" and (G.mutTitle(fr.m) .. " " .. plantName(fr.id)) or plantName(fr.id)
		info2.Text = ("Вес %.2f кг, шанс %s"):format(fr.w, #fr.m > 0 and G.fmtOdds(G.mutChance(fr.m)) or "обычный")
		info3.Text = "Цена сейчас: " .. G.fmtInt(priceOf(fr)) .. " монет"
		info.TextColor3 = #fr.m > 0 and G.Mut[G.rarestMut(fr.m)].color or T.text
	end
	function hooks.bag()
		clear(left)
		local list = table.clone(ST.fruits)
		table.sort(list, function(a, b)
			local ca, cb = G.mutChance(a.m), G.mutChance(b.m)
			if ca ~= cb then return ca < cb end
			return a.w > b.w
		end)
		UI.bagInfo.Text = ("Сумка: %d из %d. Избранное не продаётся кнопкой «Продать всё»"):format(#ST.fruits, ST.bagCap)
		for i, fr in list do
			if i > 80 then break end
			local row = make("TextButton", { Size = UDim2.new(1, -6, 0, 42), BackgroundColor3 = fr.uid == selUid and T.blue or T.panel2, Text = "", AutoButtonColor = false, LayoutOrder = i }, left)
			K.corner(row, UDim.new(0, 10))
			K.stroke(row, #fr.m > 0 and G.Mut[G.rarestMut(fr.m)].color or rarityColor(fr.id), 1, false, 0.35)
			local sw = make("Frame", { Size = UDim2.fromOffset(10, 30), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = G.Plants[fr.id].c1 }, row)
			K.corner(sw, UDim.new(0, 4))
			local title = plantName(fr.id)
			if #fr.m > 0 then title = G.mutTitle(fr.m) .. " " .. title end
			K.text(row, title .. (fr.fav and " (избр.)" or ""), { Position = UDim2.fromOffset(22, 2), Size = UDim2.new(1, -30, 0, 22), MaxText = 16, TextXAlignment = Enum.TextXAlignment.Left,
				TextColor3 = #fr.m > 0 and G.Mut[G.rarestMut(fr.m)].color or T.text })
			K.text(row, ("%.2f кг  %s"):format(fr.w, G.fmt(priceOf(fr))), { Position = UDim2.fromOffset(22, 22), Size = UDim2.new(1, -30, 0, 16), MaxText = 13, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
			row.Activated:Connect(function()
				select(fr)
				hooks.bag()
			end)
		end
		if #list == 0 then label(left, "Сумка пуста. Собери урожай на грядках", { Size = UDim2.new(1, 0, 0, 40), MaxText = 18 }) end
		local cur
		for _, fr in list do if fr.uid == selUid then cur = fr end end
		if not cur and selUid then select(nil) end
	end
	sellOne.Activated:Connect(function()
		if not selUid then toast("Выбери плод", "bad") return end
		local ok, total = remotes.Sell:InvokeServer("one", selUid)
		if ok then toast("+" .. G.fmtInt(total) .. " монет", "ok") playSfx("coins") selUid = nil select(nil) end
	end)
	favBtn.Activated:Connect(function()
		if selUid then remotes.Fav:InvokeServer(selUid) end
	end)
	sellAll.Activated:Connect(function()
		local ok, total, count = remotes.Sell:InvokeServer("all")
		if ok then toast(("Продано %d шт.: +%s монет"):format(count, G.fmtInt(total)), "ok") playSfx("coins") else toast(total or "Нечего продавать", "bad") end
	end)
end

------------------------------------------------------------------ окно: атлас
do
	local f, body = mkWindow("index", "Атлас растений", "atlas", T.purple, 0.92, 0.84)
	local scroll, head, grid, grid_l = sheetLayout(body, UDim2.fromOffset(104, 128))
	UI.idxCount = K.text(head, "", { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15, TextColor3 = T.gold })
	UI.idxTab = 1
	local items, btns
	items, btns = planetTabs(head, { key = "mut", text = "Мутации", color = T.pink }, function(k) UI.idxTab = k hooks.index() end)
	function hooks.index()
		shade(btns, UI.idxTab, items)
		clear(grid)
		local found, muts = 0, 0
		for _ in ST.idx do found += 1 end
		for _ in ST.mutSeen do muts += 1 end
		UI.idxCount.Text = ("Найдено растений %d из %d  ·  мутаций %d из %d"):format(found, #G.PlantList, muts, #G.MutOrder)
		if UI.idxTab == "mut" then
			grid_l.CellSize = UDim2.new(1, -4, 0, 46)
			for i, id in G.MutOrder do
				local m = G.Mut[id]
				local seen = ST.mutSeen[id]
				local row = K.panel(grid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
				local dot = make("Frame", { Size = UDim2.fromOffset(10, 10), Position = UDim2.fromOffset(10, 18), BackgroundColor3 = seen and m.color or T.panel }, row)
				K.corner(dot, UDim.new(1, 0))
				K.text(row, seen and m.name or "???", { Position = UDim2.fromOffset(28, 4), Size = UDim2.new(0.45, 0, 0, 20), MaxText = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = seen and m.color or T.sub })
				K.text(row, seen and m.desc or "Ещё не встречалась", { Position = UDim2.fromOffset(28, 24), Size = UDim2.new(0.5, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub, Medium = true })
				K.text(row, G.fmtOdds(m.chance), { Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0.48, 0, 0, 20), MaxText = 15, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.gold })
				K.text(row, "цена x" .. G.fmtInt(m.mult), { Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.new(0.48, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.sub, Medium = true })
			end
			return
		end
		grid_l.CellSize = UDim2.fromOffset(104, 128)
		for i, p in G.PlantList do
			if G.PlanetIndex[p.planet] == UI.idxTab then
				local e = ST.idx[p.id]
				local card = K.panel(grid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
				if e then K.stroke(card, rarityColor(p.id), 1, false, 0.35) end
				local h = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 0, 78) }, card)
				modelView(h, p.id, nil, not e)
				K.text(card, e and p.name or "???", { Position = UDim2.fromOffset(4, 84), Size = UDim2.new(1, -8, 0, 16), MaxText = 12, TextColor3 = e and rarityColor(p.id) or T.sub })
				K.text(card, e and ("рекорд %.2f кг"):format(e.best) or G.Rarity[p.rarity].name, { Position = UDim2.fromOffset(4, 102), Size = UDim2.new(1, -8, 0, 13), MaxText = 10, TextColor3 = T.sub, Medium = true })
			end
		end
	end
end

------------------------------------------------------------------ окно: рынок
do
	local f, body = mkWindow("market", "Рынок", "news", T.pink, 0.9, 0.84)
	UI.marketTimer = K.text(body, "", { Size = UDim2.new(0.6, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18, TextColor3 = T.gold })
	local top = K.button(body, "Лидеры", T.gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(150, 28), MaxText = 15 })
	local scroll = K.scroll(body, { Position = UDim2.fromOffset(0, 32), Size = UDim2.new(1, 0, 1, -32) })
	listLayout(scroll, nil, 5)
	local mode = "market"
	local function row(parent, order, name, sub, value, color, hot)
		local r = K.panel(parent, { Size = UDim2.new(1, -8, 0, 40), LayoutOrder = order, BackgroundColor3 = hot and Color3.fromRGB(70, 36, 80) or T.panel2 })
		K.stroke(r, hot and T.pink or T.line, 1, false, hot and 0.2 or 0.6)
		K.text(r, name, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.55, 0, 0, 22), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color })
		K.text(r, sub, { Position = UDim2.fromOffset(10, 22), Size = UDim2.new(0.55, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
		K.text(r, value, { Position = UDim2.new(0.55, 0, 0, 4), Size = UDim2.new(0.43, 0, 0, 32), MaxText = 20, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = hot and T.pink or T.text })
	end
	function hooks.market()
		clear(scroll)
		local t = nowS()
		local epoch = G.marketEpoch(t)
		UI.marketTimer.Text = "Цены меняются через " .. G.fmtTime(G.marketTimeLeft(t))
		local hot = G.hotPlants(epoch)
		local rows = {}
		for _, p in G.PlantList do
			local m, isHot = G.marketMult(p, epoch)
			table.insert(rows, { p = p, m = m, hot = isHot })
		end
		table.sort(rows, function(a, b) return a.m > b.m end)
		label(scroll, "Горячий спрос x3", { Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.pink, MaxText = 18, LayoutOrder = 0 })
		local n = 0
		for _, r in rows do
			if r.hot then n += 1 row(scroll, n, r.p.name, "базовая цена " .. G.fmt(r.p.sell), "x3.00", rarityColor(r.p.id), true) end
		end
		label(scroll, "Хорошо покупают", { Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.green, MaxText = 16, LayoutOrder = 10 })
		local k = 0
		for _, r in rows do
			if not r.hot and r.m >= 1.2 and k < 8 then k += 1 row(scroll, 10 + k, r.p.name, "базовая цена " .. G.fmt(r.p.sell), ("x%.2f"):format(r.m), rarityColor(r.p.id), false) end
		end
		label(scroll, "Спрос упал", { Size = UDim2.new(1, 0, 0, 22), TextColor3 = T.red, MaxText = 16, LayoutOrder = 30 })
		k = 0
		for i = #rows, 1, -1 do
			local r = rows[i]
			if k < 5 then k += 1 row(scroll, 30 + k, r.p.name, "базовая цена " .. G.fmt(r.p.sell), ("x%.2f"):format(r.m), T.sub, false) end
		end
	end
	top.Activated:Connect(function() openWindow("leaders") end)
end

------------------------------------------------------------------ окно: мастерская
do
	local f, body = mkWindow("upgrades", "Мастерская станции", "upgrade", T.cold, 0.92, 0.84)
	local scroll = K.scroll(body, {})
	listLayout(scroll, nil, 6)
	local function header(text, order, color)
		label(scroll, text, { Size = UDim2.new(1, 0, 0, 26), TextColor3 = color or T.gold, MaxText = 20, LayoutOrder = order })
	end
	function hooks.upgrades()
		clear(scroll)
		header("Улучшения", 0)
		for i, key in G.UpgradeOrder do
			local u = G.Upgrades[key]
			local level = key == "beds" and ST.bedCount or ST.upg[key]
			local cost = key == "beds" and G.bedCost(level, ST.planet or 1) or G.upgradeCost(key, level)
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i, BackgroundColor3 = T.panel2 })
			K.icon(r, u.icon, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 6) })
			K.text(r, u.name, { Position = UDim2.fromOffset(56, 3), Size = UDim2.new(0.45, 0, 0, 22), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left })
			local cur = G.upgradeValue(key, level)
			local curText = (u.off and level <= u.min) and u.off or u.fmt:format(cur)
			local desc = key == "beds" and ("Грядки огорода на планете " .. G.Planets[ST.planet or 1].name) or u.desc
			K.text(r, desc .. ". Сейчас: " .. curText, { Position = UDim2.fromOffset(56, 26), Size = UDim2.new(0.55, 0, 0, 26), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
			local b, bl
			if cost then
				b, bl = K.button(r, G.fmt(cost), ST.coins >= cost and T.green or T.panel, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(120, 40), MaxText = 18 })
				b.Activated:Connect(function()
					local ok, err = remotes.Upgrade:InvokeServer(key)
					if ok then toast(u.name .. ": улучшено", "ok") else toast(err or "Не получилось", "bad") end
				end)
			else
				K.text(r, "МАКС", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(100, 30), MaxText = 20, TextColor3 = T.gold })
			end
		end
		header("Украшения станции", 20, T.cold)
		for i, id in G.DecorOrder do
			local d = G.Decor[id]
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 46), LayoutOrder = 20 + i, BackgroundColor3 = T.panel2 })
			K.text(r, d.name, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.5, 0, 0, 22), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left })
			K.text(r, d.desc, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(0.55, 0, 0, 18), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
			if ST.decor[id] then
				K.text(r, "КУПЛЕНО", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 28), MaxText = 16, TextColor3 = T.green })
			else
				local b = K.button(r, G.fmt(d.cost), ST.coins >= d.cost and T.green or T.panel, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(120, 36), MaxText = 17 })
				b.Activated:Connect(function()
					local ok, err = remotes.BuyDecor:InvokeServer(id)
					if ok then toast("Украшение поставлено на участок", "ok") else toast(err or "Не получилось", "bad") end
				end)
			end
		end
		for i, key in {} do
			local pr = G.Products[key]
			if pr.id ~= 0 then
				local owned = pr.permanent and ST.perms[key]
				local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 48), LayoutOrder = 40 + i, BackgroundColor3 = T.panel2 })
				K.text(r, pr.name, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.5, 0, 0, 22), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left })
				K.text(r, pr.desc, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(0.6, 0, 0, 20), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
				if owned then
					K.text(r, "АКТИВНО", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 28), MaxText = 16, TextColor3 = T.green })
				else
					local b = K.button(r, tostring(pr.price) .. " R$", T.pink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 36), MaxText = 17 })
					b.Activated:Connect(function() MarketplaceService:PromptProductPurchase(plr, pr.id) end)
				end
			end
		end
		header("Промокод", 60, T.gold)
		local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 46), LayoutOrder = 61, BackgroundColor3 = T.panel2 })
		local box = make("TextBox", { Size = UDim2.new(1, -150, 0, 32), Position = UDim2.fromOffset(8, 7), BackgroundColor3 = T.ink, TextColor3 = T.text, PlaceholderText = "Введи код", Text = "", Font = Enum.Font.GothamBold, TextScaled = true, ClearTextOnFocus = false }, r)
		K.corner(box, UDim.new(0, 8))
		local ok = K.button(r, "Применить", T.gold, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(120, 34), MaxText = 15 })
		ok.Activated:Connect(function()
			local good, text = remotes.Redeem:InvokeServer(box.Text)
			toast(text or "Ошибка", good and "ok" or "bad")
		end)
	end
end

------------------------------------------------------------------ окно: магазин (поливки и донаты)
do
	local f, body = mkWindow("store", "Магазин", "coin", T.gold, 0.9, 0.84)
	local scroll = K.scroll(body, {})
	listLayout(scroll, nil, 6)
	function hooks.store()
		clear(scroll)
		label(scroll, "Поливки: сразу ускоряют рост грядки. Выбери лейку кнопкой у панели семян", { Size = UDim2.new(1, -8, 0, 22), TextColor3 = T.sub, MaxText = 14, LayoutOrder = 0 })
		for tier, can in G.Cans do
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 52), LayoutOrder = tier, BackgroundColor3 = T.panel2 })
			K.stroke(r, can.color, 1.2, false, 0.3)
			K.icon(r, "water", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(8, 6), ImageColor3 = can.color })
			K.text(r, ("%s  ·  ранг %d"):format(can.name, tier), { Position = UDim2.fromOffset(56, 4), Size = UDim2.new(0.5, 0, 0, 20), MaxText = 16, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = can.color })
			local have = (ST.cans and ST.cans["c" .. tier]) or 0
			K.text(r, ("рост быстрее на %d%%  ·  есть: %d"):format(math.floor(can.pct * 100), have), { Position = UDim2.fromOffset(56, 26), Size = UDim2.new(0.55, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub, Medium = true })
			if can.robux then
				local pr = G.Products[can.robux]
				local b = K.button(r, pr.price .. " R$ за 10", T.pink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(130, 36), MaxText = 15 })
				b.Activated:Connect(function() MarketplaceService:PromptProductPurchase(plr, pr.id) end)
			else
				local price = G.canPrice(tier, ST.planets or 1)
				for qi, qty in { 1, 10 } do
					local b = coinButton(r, price * qty, ST.coins >= price * qty, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8 - (2 - qi) * 116, 0.5, 0), Size = UDim2.fromOffset(110, 34), MaxText = 14 })
					b.Activated:Connect(function()
						local ok, err = remotes.BuyCan:InvokeServer(tier, qty)
						if ok then toast(("Куплено: %s x%d"):format(can.name, qty), "ok") playSfx("coins") else toast(err or "Не вышло", "bad") end
					end)
				end
			end
		end
		label(scroll, "Особые предложения", { Size = UDim2.new(1, -8, 0, 24), TextColor3 = T.pink, MaxText = 18, LayoutOrder = 20 })
		for i, key in G.ProductOrder do
			local pr = G.Products[key]
			if pr.id ~= 0 and key ~= "cans5" then
				local owned = pr.permanent and ST.perms[key]
				local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 48), LayoutOrder = 20 + i, BackgroundColor3 = T.panel2 })
				K.text(r, pr.name, { Position = UDim2.fromOffset(10, 2), Size = UDim2.new(0.5, 0, 0, 22), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left })
				K.text(r, pr.desc, { Position = UDim2.fromOffset(10, 24), Size = UDim2.new(0.6, 0, 0, 20), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub, Medium = true })
				if owned then
					K.text(r, "АКТИВНО", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 28), MaxText = 16, TextColor3 = T.green })
				else
					local b = K.button(r, pr.price .. " R$", T.pink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 36), MaxText = 16 })
					b.Activated:Connect(function() MarketplaceService:PromptProductPurchase(plr, pr.id) end)
				end
			end
		end
	end
end

------------------------------------------------------------------ окно: алхимия (котёл на Луне)
do
	local f, body = mkWindow("alchemy", "Алхимия", "potion", T.purple, 0.92, 0.86)
	local left = K.scroll(body, { Size = UDim2.new(0.56, -6, 1, 0) })
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 46), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, left)
	local right = K.panel(body, { Position = UDim2.new(0.56, 4, 0, 0), Size = UDim2.new(0.44, -4, 1, 0), BackgroundColor3 = T.panel2 })
	K.text(right, "Котёл: выбери 3 плода", { Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 0, 22), MaxText = 17, TextColor3 = T.purple })
	local slotL = {}
	for i = 1, G.Alchemy.slots do
		local sl = make("Frame", { Position = UDim2.new((i - 1) / 3, 5, 0, 30), Size = UDim2.new(1 / 3, -10, 0, 70), BackgroundColor3 = T.panel }, right)
		K.corner(sl, UDim.new(0, 10))
		slotL[i] = { stroke = K.stroke(sl, T.purple, 1, false, 0.4), lbl = K.text(sl, "пусто", { Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8), MaxText = 12, TextWrapped = true, Medium = true, TextColor3 = T.sub }) }
	end
	local chanceL = K.text(right, "", { Position = UDim2.new(0, 8, 0, 106), Size = UDim2.new(1, -16, 0, 20), MaxText = 15, TextColor3 = T.gold })
	K.text(right, "Чем реже плоды, тем реже семя. 3 одинаковых: +35% к шансу. Каждая мутация: +6%. Иногда выпадает эликсир удачи x25", { Position = UDim2.new(0, 8, 0, 128), Size = UDim2.new(1, -16, 1, -186), MaxText = 12, TextWrapped = true, Medium = true, TextColor3 = T.sub, TextYAlignment = Enum.TextYAlignment.Top })
	local brewBtn = K.button(right, "Сварить", T.purple, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 8, 1, -8), Size = UDim2.new(1, -16, 0, 44), MaxText = 22 })
	local picked = {}
	local function byUid(u)
		for _, fr in ST.fruits do if fr.uid == u then return fr end end
	end
	local function fruitTitle(fr)
		return plantName(fr.id) .. (#fr.m > 0 and ("\nмутаций: " .. #fr.m) or "")
	end
	function hooks.alchemy()
		for i = #picked, 1, -1 do if not byUid(picked[i]) then table.remove(picked, i) end end
		clear(left)
		local list = {}
		for _, fr in ST.fruits do if not fr.fav then table.insert(list, fr) end end
		table.sort(list, function(a, b)
			local ra, rb = G.Rarity[G.Plants[a.id].rarity].rank, G.Rarity[G.Plants[b.id].rarity].rank
			if ra ~= rb then return ra > rb end
			if #a.m ~= #b.m then return #a.m > #b.m end
			return a.id < b.id
		end)
		for i, fr in list do
			if i > 90 then break end
			local on = table.find(picked, fr.uid) ~= nil
			local b = make("TextButton", { BackgroundColor3 = on and T.purple or T.panel2, Text = "", AutoButtonColor = false, LayoutOrder = i }, left)
			K.corner(b, UDim.new(0, 10))
			K.stroke(b, rarityColor(fr.id), 1, false, 0.35)
			K.text(b, plantName(fr.id), { Position = UDim2.fromOffset(8, 2), Size = UDim2.new(1, -14, 0, 24), MaxText = 15, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = rarityColor(fr.id) })
			K.text(b, G.Rarity[G.Plants[fr.id].rarity].name .. (#fr.m > 0 and (" · мутаций: " .. #fr.m) or ""), { Position = UDim2.fromOffset(8, 24), Size = UDim2.new(1, -14, 0, 16), MaxText = 12,
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = #fr.m > 0 and G.Mut[G.rarestMut(fr.m)].color or T.sub, Medium = true })
			b.Activated:Connect(function()
				local k = table.find(picked, fr.uid)
				if k then table.remove(picked, k) elseif #picked < G.Alchemy.slots then table.insert(picked, fr.uid) playSfx("tap", 0.9 + #picked * 0.15) end
				hooks.alchemy()
			end)
		end
		if #list == 0 then label(left, "Сумка пуста: собери урожай и возвращайся", { Size = UDim2.new(1, 0, 0, 40), MaxText = 16 }) end
		local pf = {}
		for i = 1, G.Alchemy.slots do
			local fr = picked[i] and byUid(picked[i])
			slotL[i].lbl.Text = fr and fruitTitle(fr) or "пусто"
			slotL[i].lbl.TextColor3 = fr and rarityColor(fr.id) or T.sub
			slotL[i].stroke.Color = fr and rarityColor(fr.id) or T.purple
			if fr then table.insert(pf, fr) end
		end
		chanceL.Text = #pf == 3 and ("Шанс редкости выше: %d%%"):format(math.floor(G.brewChance(pf) * 100)) or ("Выбрано %d из 3"):format(#pf)
	end
	brewBtn.Activated:Connect(function()
		if #picked < G.Alchemy.slots then toast("Нужно 3 плода", "bad") return end
		local ok, res = remotes.Brew:InvokeServer(picked)
		if not ok then toast(res or "Не вышло", "bad") return end
		picked = {}
		playSfx("brew")
		local lab = world:FindFirstChild("AlchemyLab", true)
		local brew = lab and lab:FindFirstChild("Brew")
		if brew then
			FX.burst(brew.Position + Vector3.new(0, 1, 0), Color3.fromRGB(150, 255, 190), 60)
			FX.splash(brew.Position + Vector3.new(0, 1, 0), Color3.fromRGB(190, 130, 255), 40, 20)
		end
		hooks.alchemy()
	end)
end

------------------------------------------------------------------ окно: таблица лидеров
do
	local f, body = mkWindow("leaders", "Таблица лидеров", "trophy", T.gold, 0.9, 0.86)
	local mode = "rich"
	local ITEMS = {
		{ key = "rich", text = "Богачи", color = T.gold },
		{ key = "heavy", text = "Тяжесть", color = T.green },
		{ key = "rare", text = "Редкость", color = T.purple },
		{ key = "race", text = "Гонка", color = T.orange },
		{ key = "server", text = "Сервер", color = T.cold },
	}
	local scroll = K.scroll(body, { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -40) })
	listLayout(scroll, nil, 5)
	local data
	local _, buttons = tabs(body, ITEMS, function(k)
		mode = k
		hooks.leaders()
	end, 34)
	local TITLES = {
		rich = "Больше всех заработали за всё время",
		heavy = "Самые тяжёлые плоды этой недели",
		rare = "Самые редкие мутации в урожае",
		race = "Самые быстрые на Марсе (пыльная гонка)",
		server = "Игроки на этом сервере",
	}
	local function value(e)
		if mode == "rich" or mode == "server" then return G.fmt(e.v) .. " монет" end
		if mode == "heavy" then return ("%.2f кг"):format(e.v) end
		if mode == "race" then return ("%.1f с"):format(e.v) end
		return G.fmtOdds(e.v)
	end
	function hooks.leaders()
		shade(buttons, mode, ITEMS)
		clear(scroll)
		if not data or os.clock() - (UI.leadersAt or 0) > 20 then
			data = remotes.Top:InvokeServer() or {}
			UI.leadersAt = os.clock()
		end
		if mode == "rich" and #(data.rich or {}) == 0 then
			mode = "server"
			shade(buttons, mode, ITEMS)
		end
		label(scroll, TITLES[mode], { Size = UDim2.new(1, 0, 0, 24), TextColor3 = T.sub, MaxText = 16, LayoutOrder = 0 })
		local list = data[mode] or {}
		local medal = { T.gold, Color3.fromRGB(200, 210, 225), Color3.fromRGB(220, 150, 90) }
		for i, e in list do
			local me = e.id == plr.UserId
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 44), LayoutOrder = i, BackgroundColor3 = me and Color3.fromRGB(40, 60, 90) or T.panel2 })
			K.stroke(r, medal[i] or (me and T.cold) or T.line, 1, false, medal[i] and 0.2 or 0.6)
			K.text(r, "#" .. i, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(44, 44), MaxText = 20, TextColor3 = medal[i] or T.sub })
			local sub = mode == "server" and (G.Planets[e.planet or 1].name .. (e.best and e.best < 1 and (" · лучшая мутация " .. G.fmtOdds(e.best)) or "")) or (me and "это ты" or "")
			K.text(r, e.name, { Position = UDim2.fromOffset(56, sub ~= "" and 2 or 10), Size = UDim2.new(0.5, 0, 0, 24), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = me and T.cold or T.text })
			if sub ~= "" then K.text(r, sub, { Position = UDim2.fromOffset(56, 25), Size = UDim2.new(0.5, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub, Medium = true }) end
			K.text(r, value(e), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 6), Size = UDim2.new(0.4, 0, 0, 32), MaxText = 19, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = medal[i] or T.text })
		end
		if #list == 0 then label(scroll, "Пока пусто: таблица обновляется раз в полторы минуты", { Size = UDim2.new(1, 0, 0, 30), MaxText = 15, LayoutOrder = 1 }) end
	end
	function FX.openLeaders()
		data = nil
		openWindow("leaders")
	end
end

------------------------------------------------------------------ окно: подарок
do
	local f, body = mkWindow("daily", "Ежедневный подарок", "gift", T.orange, 0.62, 0.7)
	local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 90) }, body)
	listLayout(row, Enum.FillDirection.Horizontal, 6)
	UI.dailyCards = {}
	for i = 1, 7 do
		local c = K.panel(row, { Size = UDim2.new(1 / 7, -6, 1, 0), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.text(c, "День " .. i, { Position = UDim2.fromOffset(2, 4), Size = UDim2.new(1, -4, 0, 18), MaxText = 14 })
		K.icon(c, i == 7 and "gift" or "coin", { Position = UDim2.fromOffset(6, 24), Size = UDim2.new(1, -12, 0, 40) })
		UI.dailyCards[i] = K.text(c, G.fmt(G.Daily.coins[i]), { Position = UDim2.new(0, 2, 1, -22), Size = UDim2.new(1, -4, 0, 18), MaxText = 14, TextColor3 = T.gold })
	end
	UI.dailyBtn = K.button(body, "Забрать", T.green, { Position = UDim2.new(0.1, 0, 0, 110), Size = UDim2.new(0.8, 0, 0, 50), MaxText = 24 })
	UI.dailyNote = K.text(body, "Заходи каждый день: награда растёт, а множитель зависит от открытых планет", { Position = UDim2.new(0, 0, 0, 170), Size = UDim2.new(1, 0, 0, 40), MaxText = 15, TextColor3 = T.sub })
	UI.dailyBtn.Activated:Connect(function()
		local ok, coins, seed, streak = remotes.Daily:InvokeServer()
		if ok then
			toast(("Подарок: +%s монет и 2 семени «%s»"):format(G.fmtInt(coins), plantName(seed)), "ok", 5)
		else
			toast(coins or "Уже получено", "bad")
		end
	end)
	function hooks.daily()
		for i = 1, 7 do
			K.recolor(UI.dailyCards[i].Parent, (ST.daily.can and i == (ST.daily.streak % 7 + 1)) and T.green or ((not ST.daily.can and i <= ST.daily.streak) and T.blue or T.panel2))
		end
		K.recolor(UI.dailyBtn, ST.daily.can and T.green or T.panel)
	end
end

------------------------------------------------------------------ окно: полёт на ракете
local playLaunch -- кинематика, объявлена ниже
do
	local f, body = mkWindow("travel", "Полёт на другую планету", "rocket", T.pink, 0.8, 0.84)
	local scroll = K.scroll(body, {})
	listLayout(scroll, nil, 6)
	function hooks.travel()
		local fresh = remotes.State:InvokeServer()
		if fresh and fresh.gsum then ST.gsum = fresh.gsum end
		clear(scroll)
		label(scroll, "На каждой планете свой огород: новый с 3 грядками. Пока тебя нет, там растёт вдвое медленнее. Растения своей планеты растут на 25% быстрее", { Size = UDim2.new(1, -8, 0, 34), TextColor3 = T.sub, MaxText = 13, TextWrapped = true, LayoutOrder = 0 })
		for i, p in G.Planets do
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 48), LayoutOrder = i, BackgroundColor3 = T.panel2 })
			local dot = make("Frame", { Size = UDim2.fromOffset(26, 26), Position = UDim2.fromOffset(10, 11), BackgroundColor3 = G.PlanetColors[i] }, r)
			K.corner(dot, UDim.new(1, 0))
			K.text(r, p.name, { Position = UDim2.fromOffset(46, 5), Size = UDim2.new(0.5, 0, 0, 20), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = G.PlanetColors[i] })
			local here = (ST.planet or 1) == i
			local open = i <= (ST.planets or 1)
			local bonus = ("удача мутаций x%s"):format(tostring(G.PlanetLuck[i])) .. (G.PlanetFeature[i] ~= "" and (" · " .. G.PlanetFeature[i]) or "")
			local gs = ST.gsum and ST.gsum[i]
			local gtext = ""
			if gs and gs.beds > 0 then
				gtext = gs.planted > 0 and (("огород: %d/%d растёт, %d созрело · "):format(gs.planted, gs.beds, gs.ripe)) or (("огород: %d грядок · "):format(gs.beds))
			end
			local sub = here and ("Ты здесь · " .. gtext .. bonus) or (open and (gtext .. bonus) or ("Откроется после " .. G.fmt(G.PlanetUnlock[i]) .. " заработанных монет · " .. bonus))
			K.text(r, sub, { Position = UDim2.fromOffset(46, 26), Size = UDim2.new(0.62, 0, 0, 16), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub, Medium = true })
			if open and not here then
				local b = K.button(r, "Лететь", T.pink, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(110, 34), MaxText = 16 })
				b.Activated:Connect(function()
					local ok, err = remotes.Travel:InvokeServer(i)
					if ok then
						K.close(f)
						task.spawn(playLaunch, i)
					else
						toast(err or "Нельзя улететь", "bad")
					end
				end)
			end
		end
	end
end

------------------------------------------------------------------ админ-панель (только владелец)
if plr.UserId == ADMIN_ID then
	local f, body = mkWindow("admin", "Админ", "admin", T.red, 0.7, 0.8)
	local scroll = K.scroll(body, {})
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 38), CellPadding = UDim2.fromOffset(8, 6), SortOrder = Enum.SortOrder.LayoutOrder }, scroll)
	local order = 0
	local function btn(text, color, fn)
		order += 1
		local b = K.button(scroll, text, color or T.blue, { MaxText = 15, LayoutOrder = order })
		b.Activated:Connect(fn)
		return b
	end
	local function cmd(c, arg, msg) return function()
		local ok = remotes.Admin:InvokeServer(c, arg)
		toast(ok and (msg or "Готово") or "Не вышло", ok and "ok" or "bad")
	end end
	btn("+1M монет", T.gold, cmd("coins"))
	btn("+1B монет", T.gold, cmd("coinsB"))
	btn("Открыть все планеты", T.pink, cmd("planets"))
	btn("Все семена x10", T.green, cmd("seeds"))
	btn("Всё созрело", T.green, cmd("ripe"))
	btn("Макс. улучшения", T.cold, cmd("maxup"))
	btn("Гигант: след. посадка 900 кг", T.orange, cmd("giant", nil, "Следующая посадка вырастет гигантом"))
	btn("Все мутации: след. посадка", T.purple, cmd("allmut", nil, "Следующая посадка со всеми мутациями"))
	btn("Метеоритный дождь", T.orange, cmd("event", "meteor"))
	btn("Солнечная вспышка", T.gold, cmd("event", "flare"))
	btn("Туманность", T.purple, cmd("event", "nebula"))
	btn("Остановить событие", T.panel2, cmd("stopEvent"))
	btn("Зелье x10 на 20 посадок", T.pink, cmd("potion"))
	btn("Быстрый бег вкл/выкл", T.blue, cmd("speed"))
	btn("Опыление сейчас", T.green, cmd("pollen", nil, "Пыльца скоро прилетит"))
	btn("Витрина для ТикТока", T.gold, cmd("showcase", nil, "Огород заполнен гигантами"))
	btn("Все донаты: разблокировать", T.pink, cmd("alldonate", nil, "Все донаты выданы"))
	btn("Мистический торговец сейчас", T.purple, cmd("mystic", nil, "Торговец появился на всех площадях"))
	btn("Сброс перезарядок", T.cold, cmd("resetcd", nil, "Пушка, сундук и наживка готовы"))
	btn("ТП: алхимия (Луна)", T.purple, cmd("tp", "alchemy"))
	btn("ТП: пушка (Европа)", T.cold, cmd("tp", "cannon"))
	btn("ТП: паркур (Туманность)", T.pink, cmd("tp", "spiral"))
	btn("ТП: сундук на орбите", T.gold, cmd("tp", "chest"))
	btn("ТП: телескоп (Ядро)", T.orange, cmd("tp", "telescope"))
	btn("ТП: рыбалка (Ио)", T.red, cmd("tp", "fishing"))
	btn("ТП: гонка (Марс)", T.orange, cmd("tp", "raceStart"))
	local mi = 1
	local mb
	mb = btn("Мутация: " .. G.Mut[G.MutOrder[1]].name, T.purple, function()
		remotes.Admin:InvokeServer("mut", G.MutOrder[mi])
		toast("След. посадка: " .. G.Mut[G.MutOrder[mi]].name, "ok")
		mi = mi % #G.MutOrder + 1
		local l = mb:FindFirstChildOfClass("TextLabel")
		if l then l.Text = "Мутация: " .. G.Mut[G.MutOrder[mi]].name end
	end)
end

------------------------------------------------------------------ левая колонка кнопок и панель семян
do
	local col = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 56), Size = UDim2.fromOffset(50, 440) }, hud)
	listLayout(col, nil, 4)
	local defs = {
		{ "shop", "shop", "Семена", T.green }, { "bag", "jar", "Сумка", T.gold }, { "upgrades", "upgrade", "Улучшить", T.cold },
		{ "travel", "rocket", "Ракета", T.pink }, { "home", "home", "Домой", T.gold }, { "store", "coin", "Магазин", T.gold }, { "menu", "settings", "Ещё", T.purple },
	}
	UI.buttons = {}
	for i, d in defs do
		local b = K.iconButton(col, d[2], d[3], d[4], 46)
		b.LayoutOrder = i
		b.Activated:Connect(function()
			if d[1] == "home" then
				if not remotes.Home:InvokeServer() then toast("Сейчас нельзя", "bad") end
			else
				openWindow(d[1])
			end
		end)
		UI.buttons[d[1]] = b
	end
	-- панель семян
	local bar = make("Frame", { Name = "Seeds", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(470, 80), BackgroundTransparency = 1 }, hud)
	local scroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 4 }, bar)
	listLayout(scroll, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	UI.seedBar = scroll
	local canBtn = make("TextButton", { Name = "CanPick", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -244, 1, -10), Size = UDim2.fromOffset(78, 74),
		BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false }, hud)
	K.corner(canBtn, UDim.new(0, 12))
	local canStroke = K.stroke(canBtn, T.cold, 1.2, false, 0.3)
	local canIcon = K.icon(canBtn, "water", { Size = UDim2.fromOffset(38, 38), Position = UDim2.new(0.5, -19, 0, 4) })
	local canLbl = K.text(canBtn, "Полив", { Position = UDim2.new(0, 3, 1, -30), Size = UDim2.new(1, -6, 0, 26), MaxText = 11, TextWrapped = true, Medium = true })
	function hooks.canpick()
		local tier = ST.can or 0
		local can = G.Cans[tier]
		canIcon.ImageColor3 = can and can.color or Color3.new(1, 1, 1)
		canStroke.Color = can and can.color or T.cold
		canLbl.Text = can and (("Ранг %d · x%d"):format(tier, ST.cans["c" .. tier] or 0)) or "Обычный полив"
	end
	canBtn.Activated:Connect(function()
		K.bounce(canBtn)
		playSfx("click")
		local cur = ST.can or 0
		for step = 1, 6 do
			local nxt = (cur + step) % 6
			if nxt == 0 or ((ST.cans or {})["c" .. nxt] or 0) > 0 then
				ST.can = nxt
				remotes.SelectCan:FireServer(nxt)
				hooks.canpick()
				local can = G.Cans[nxt]
				toast(can and (can.name .. ": рост быстрее на " .. math.floor(can.pct * 100) .. "% сразу") or "Обычный полив: раз в 20 с", "info", 2)
				break
			end
		end
	end)
	function hooks.seedbar()
		clear(scroll)
		local ids = {}
		for id in ST.seeds do table.insert(ids, id) end
		table.sort(ids, function(a, b) return G.Plants[a].index < G.Plants[b].index end)
		for i, id in ids do
			local p = G.Plants[id]
			local card = make("TextButton", { Size = UDim2.fromOffset(64, 76), BackgroundColor3 = id == ST.sel and T.panel2 or T.panel, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = i }, scroll)
			K.corner(card, UDim.new(0, 10))
			K.stroke(card, id == ST.sel and T.gold or rarityColor(id), id == ST.sel and 1.6 or 1, false, id == ST.sel and 0 or 0.45)
			local h = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(3, 2), Size = UDim2.new(1, -6, 0, 46) }, card)
			modelView(h, id, nil, false)
			K.text(card, "x" .. ST.seeds[id], { Position = UDim2.new(1, -26, 0, 2), Size = UDim2.fromOffset(24, 14), MaxText = 12, TextColor3 = T.gold })
			K.text(card, p.name, { Position = UDim2.new(0, 2, 0, 50), Size = UDim2.new(1, -4, 0, 22), MaxText = 10, TextColor3 = rarityColor(id), TextWrapped = true, Medium = true })
			card.Activated:Connect(function()
				ST.sel = id
				remotes.Select:FireServer(id)
				hooks.seedbar()
			end)
		end
	end
end

-- счётчик монет плавно набегает
do
	local shown = ST.coins or 0
	RunService.RenderStepped:Connect(function(dt)
		local target = UI.coinTarget or ST.coins or 0
		if math.abs(target - shown) < 1 then
			shown = target
		else
			shown += (target - shown) * math.min(1, dt * 6)
		end
		if UI.coins then UI.coins.Text = G.fmt(shown) end
	end)
end

------------------------------------------------------------------ задания (справа под событием)
do
	local qp = K.panel(hud, { Name = "Quests", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 60), Size = UDim2.fromOffset(230, 112) })
	K.text(qp, "ЗАДАНИЯ", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 5), MaxText = 12, TextColor3 = T.gold, TextXAlignment = Enum.TextXAlignment.Left })
	UI.questRows = {}
	for i = 1, 3 do
		local row = make("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -12, 0, 28), Position = UDim2.fromOffset(6, 22 + (i - 1) * 29) }, qp)
		local txt = K.text(row, "", { Size = UDim2.new(1, -70, 0, 15), Position = UDim2.fromOffset(2, 0), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, Medium = true })
		local back, fill = K.bar(row, T.cold, { Size = UDim2.new(1, -70, 0, 4), Position = UDim2.fromOffset(2, 19) })
		local num = K.text(row, "", { Size = UDim2.fromOffset(62, 15), Position = UDim2.new(1, -64, 0, 0), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Right, TextColor3 = T.sub })
		local claim = K.button(row, "Забрать", T.gold, { Size = UDim2.fromOffset(64, 24), Position = UDim2.new(1, -64, 0, 1), MaxText = 12, Visible = false })
		claim.Activated:Connect(function()
			local ok, reward = remotes.ClaimQuest:InvokeServer(i)
			if ok then
				toast("Задание выполнено: +" .. G.fmt(reward) .. " монет", "ok")
				playSfx("coins")
			end
		end)
		UI.questRows[i] = { txt = txt, fill = fill, num = num, claim = claim, row = row }
	end
	function hooks.quests()
		for i, r in UI.questRows do
			local q = ST.q and ST.q[i]
			r.row.Visible = q ~= nil
			if q then
				r.txt.Text = G.Quests[q.k].text:format(q.need)
				r.fill.Size = UDim2.fromScale(math.clamp(q.have / q.need, 0, 1), 1)
				local done = q.have >= q.need
				r.num.Text = done and "" or (q.have .. "/" .. q.need)
				r.claim.Visible = done
				r.txt.TextColor3 = done and T.gold or T.text
			end
		end
	end
end

------------------------------------------------------------------ окно «Ещё»: всё второстепенное в одном месте
do
	local f, body = mkWindow("menu", "Ещё", "settings", T.purple, 0.6, 0.7)
	make("UIGridLayout", { CellSize = UDim2.new(0.5, -6, 0, 64), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local items = { { "index", "atlas", "Атлас растений", T.purple }, { "market", "news", "Рынок", T.pink }, { "daily", "gift", "Подарок дня", T.orange },
		{ "photo", "luck", "Фото-режим", T.cold }, { "settings", "settings", "Настройки", T.green } }
	if plr.UserId == ADMIN_ID then table.insert(items, { "admin", "admin", "Админ", T.red }) end
	for i, it in items do
		local b = make("TextButton", { BackgroundColor3 = T.panel2, BackgroundTransparency = 0.1, Text = "", AutoButtonColor = false, LayoutOrder = i }, body)
		K.corner(b, UDim.new(0, 12))
		K.stroke(b, it[4], 1.2, false, 0.35)
		K.icon(b, it[2], { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(12, 12) })
		K.text(b, it[3], { Position = UDim2.fromOffset(62, 0), Size = UDim2.new(1, -70, 1, 0), MaxText = 17, TextXAlignment = Enum.TextXAlignment.Left })
		if it[1] == "daily" then
			local badge = make("Frame", { Name = "Badge", Size = UDim2.fromOffset(12, 12), Position = UDim2.new(1, -16, 0, 6), BackgroundColor3 = T.gold, Visible = false }, b)
			K.corner(badge, UDim.new(1, 0))
			UI.dailyBadge2 = badge
		end
		b.Activated:Connect(function()
			K.bounce(b)
			playSfx("click")
			if it[1] == "photo" then
				K.close(f)
				if FX.photoMode then FX.photoMode() end
			else
				openWindow(it[1])
			end
		end)
	end
end

------------------------------------------------------------------ окно: настройки (громкость, подсказки)
do
	local f, body = mkWindow("settings", "Настройки", "settings", T.green, 0.7, 0.74)
	listLayout(body, nil, 5)
	local rows = {}
	local function send()
		remotes.Settings:FireServer(AUDIO.m, AUDIO.s, AUDIO.h, AUDIO.t)
	end
	local function stepper(order, title, key, onChange)
		local r = K.panel(body, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = order, BackgroundColor3 = T.panel2 })
		K.text(r, title, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.3, 0, 1, 0), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left })
		local minus = K.button(r, "−", T.panel, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.32, 0, 0.5, 0), Size = UDim2.fromOffset(44, 38), MaxText = 26 })
		local plus = K.button(r, "+", T.panel, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(44, 38), MaxText = 26 })
		local barBg = make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0.32, 54, 0.5, 0), Size = UDim2.new(0.68, -120, 0, 14), BackgroundColor3 = T.panel }, r)
		K.corner(barBg, UDim.new(1, 0))
		local fill = make("Frame", { Size = UDim2.fromScale(0.5, 1), BackgroundColor3 = T.green }, barBg)
		K.corner(fill, UDim.new(1, 0))
		local val = K.text(barBg, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(60, 22), MaxText = 14 })
		local function show()
			fill.Size = UDim2.fromScale(math.max(0.02, AUDIO[key] / 10), 1)
			val.Text = AUDIO[key] == 0 and "выкл" or tostring(AUDIO[key] * 10) .. "%"
		end
		local function change(dv)
			AUDIO[key] = math.clamp(AUDIO[key] + dv, 0, 10)
			show()
			applyAudio()
			if onChange then onChange() end
			send()
		end
		minus.Activated:Connect(function() change(-1) end)
		plus.Activated:Connect(function() change(1) end)
		rows[key] = show
		show()
	end
	stepper(1, "Музыка", "m")
	stepper(2, "Звуки", "s", function() playSfx("coins") end)
	local hr = K.panel(body, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 3, BackgroundColor3 = T.panel2 })
	K.text(hr, "Подсказки сверху", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.6, 0, 1, 0), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left })
	local hb, hl = K.button(hr, "", T.green, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38), MaxText = 18 })
	local function showH()
		hl.Text = AUDIO.h == 1 and "Вкл" or "Выкл"
		K.recolor(hb, AUDIO.h == 1 and T.green or T.panel)
	end
	hb.Activated:Connect(function()
		AUDIO.h = 1 - AUDIO.h
		showH()
		send()
	end)
	rows.h = showH
	showH()
	local tr = K.panel(body, { Size = UDim2.new(1, 0, 0, 48), LayoutOrder = 4, BackgroundColor3 = T.panel2 })
	K.text(tr, "Мелодия", { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.4, 0, 1, 0), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left })
	local tb, tl = K.button(tr, "", T.purple, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(220, 38), MaxText = 17 })
	local function showT() tl.Text = AUDIO.t == 2 and "Космос" or "Лунная соната" end
	tb.Activated:Connect(function()
		AUDIO.t = AUDIO.t == 2 and 1 or 2
		showT()
		FX.setTrack(AUDIO.t)
		send()
	end)
	rows.t = showT
	showT()
	function hooks.settings()
		for _, fn in rows do fn() end
	end
end

------------------------------------------------------------------ обновление HUD
local function nextPlanetInfo()
	local n = ST.planets
	if n >= #G.Planets then return 1, "Все планеты открыты" end
	local prev, need = G.PlanetUnlock[n], G.PlanetUnlock[n + 1]
	return math.clamp((ST.earned - prev) / (need - prev), 0, 1), ("До планеты %s: %s из %s"):format(G.Planets[n + 1].name, G.fmt(ST.earned), G.fmt(need))
end

local function hintText()
	local growing, ready = 0, 0
	local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local bedsF = plot and plot:FindFirstChild("Beds")
	if bedsF then
		for _, soil in bedsF:GetDescendants() do
			if soil.Name == "Soil" and soil:GetAttribute("Plant") then
				growing += 1
				if nowS() >= (soil:GetAttribute("Ready") or 0) then ready += 1 end
			end
		end
	end
	if not ST.plot then return "На этой планете все места заняты: улети на другую" end
	local np = ST.planets or 1
	if np > 1 and ST.gsum and ST.gsum[np] and ST.gsum[np].beds == 0 and (ST.planet or 1) ~= np and ready == 0 then return "Открыта новая планета: лети на ракете в центре площади" end
	if ready > 0 then return "Растение созрело. Подойди к грядке и нажми «Собрать»" end
	if #ST.fruits > 0 then return "Продай урожай у золотого киоска на площади" end
	if next(ST.seeds) == nil and growing == 0 then return "Купи семена в зелёном киоске на площади" end
	if next(ST.seeds) and growing == 0 then return "Выбери семя внизу и подойди к грядке" end
	if growing > 0 and (ST.stats.harvests or 0) < 3 then return "Поливай грядки раз в 20 с, а пока ждёшь, собирай падающие звёзды" end
	if growing > 0 and (ST.stats.stars or 0) < 3 then return "Видишь столбы света? Это звёзды: беги и собирай их" end
	return ""
end

loop(0.5, function()
	do
		UI.coinTarget = ST.coins
		local frac, txt = nextPlanetInfo()
		UI.planetFill.Size = UDim2.fromScale(frac, 1)
		UI.planetText.Text = txt
		local t = nowS()
		local ev, left, active = G.eventAt(t)
		local forcedId = ReplicatedStorage:GetAttribute("EventId") or ""
		if forcedId ~= "" then
			for _, e in G.Events do
				if e.id == forcedId then ev, left, active = e, (ReplicatedStorage:GetAttribute("EventEnd") or t) - t, true end
			end
		end
		if active then
			UI.eventTitle.Text = ev.name
			UI.eventTitle.TextColor3 = ev.color
			UI.eventSub.Text = ev.desc .. " " .. G.fmtTime(left)
		else
			UI.eventTitle.Text = "Скоро: " .. ev.name
			UI.eventTitle.TextColor3 = T.sub
			UI.eventSub.Text = "через " .. G.fmtTime(left)
		end
		local h = hintText()
		-- подсказка видна 8 секунд, повторяется не чаще раза в 2.5 минуты; в настройках можно выключить
		if AUDIO.h == 0 then h = "" end
		if h ~= "" then
			UI.hintSeen = UI.hintSeen or {}
			local c = os.clock()
			local seen = UI.hintSeen[h]
			if not seen or c - seen > 150 then
				UI.hintSeen[h] = c
			elseif c - seen > 8 then
				h = ""
			end
		end
		UI.hint.Text = h
		UI.hintFrame.Visible = h ~= ""
		UI.shopTimer.Text = "Обновление ассортимента через " .. G.fmtTime(G.shopTimeLeft(t))
		UI.buttons.menu:FindFirstChild("Badge").Visible = ST.daily.can
		if UI.dailyBadge2 then UI.dailyBadge2.Visible = ST.daily.can end
		-- обновления окон
		if dirty.settings and ST.settings then
			local oldT = AUDIO.t
			AUDIO.m, AUDIO.s, AUDIO.h, AUDIO.t = ST.settings.m or 6, ST.settings.s or 8, ST.settings.h or 1, ST.settings.t or 1
			applyAudio()
			if oldT ~= AUDIO.t and FX.setTrack then FX.setTrack(AUDIO.t) end
			if windows.settings.Visible then hooks.settings() end
		end
		if dirty.seeds or dirty.sel then hooks.seedbar() end
		if dirty.can or dirty.cans or not UI.canInit then UI.canInit = true hooks.canpick() end
		if windows.store.Visible and (dirty.coins or dirty.cans or dirty.perms) then hooks.store() end
		if windows.alchemy.Visible and dirty.fruits then hooks.alchemy() end
		if dirty.q or not UI.questsInit then UI.questsInit = true hooks.quests() end
		if windows.bag.Visible and (dirty.fruits or dirty.coins) then hooks.bag() end
		if windows.shop.Visible and (dirty.sold or dirty.bought or dirty.planets) then hooks.shop() end
		-- открыта новая планета: праздник
		if UI.lastPlanets and (ST.planets or 1) > UI.lastPlanets then
			local pl = G.Planets[ST.planets]
			playSfx("unlock")
			local banner = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.fromOffset(560, 90), BackgroundTransparency = 1 }, hud)
			K.text(banner, "НОВАЯ ПЛАНЕТА", { Size = UDim2.new(1, 0, 0.45, 0), MaxText = 30, TextColor3 = T.gold })
			K.text(banner, pl.name .. " · лети на ракете", { Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0.4, 0), MaxText = 24, TextColor3 = G.PlanetColors[ST.planets] })
			K.pop(banner)
			task.delay(4, function() banner:Destroy() end)
			local ch = plr.Character
			if ch and ch.PrimaryPart and FX.burst then
				for i = 1, 3 do task.delay(i * 0.25, function() FX.burst(ch.PrimaryPart.Position + Vector3.new(0, 3, 0), G.PlanetColors[ST.planets], 40) end) end
			end
		end
		UI.lastPlanets = ST.planets or 1
		if windows.index.Visible and (dirty.idx or dirty.mutSeen) then hooks.index() end
		if windows.upgrades.Visible and (dirty.coins or dirty.upg or dirty.decor or dirty.bedCount or dirty.perms) then hooks.upgrades() end
		if windows.daily.Visible and dirty.daily then hooks.daily() end
		if windows.market.Visible and nowS() % 5 < 0.5 then hooks.market() end
		table.clear(dirty)
	end
end)
hooks.seedbar()
ReplicatedStorage:GetAttributeChangedSignal("MeshesReady"):Connect(function() dirty.seeds = true end)
remotes:WaitForChild("Stock").OnClientEvent:Connect(function(epoch, sold)
	ST.sold = sold
	dirty.sold = true
end)

------------------------------------------------------------------ растения в мире
local cache = {} -- Soil -> { model, key, kind }
local fxFolder = make("Folder", { Name = "FX" }, workspace)
local SHOW_DIST = 110

local function bedKey(soil)
	return (soil:GetAttribute("Plant") or "") .. "|" .. (soil:GetAttribute("Muts") or "")
end
local function mutList(str)
	local out = {}
	for id in (str or ""):gmatch("[^,]+") do table.insert(out, id) end
	return out
end
local function progressOf(soil)
	local t0, ready = soil:GetAttribute("T0") or 0, soil:GetAttribute("Ready") or 0
	return math.clamp((nowS() - t0) / math.max(1, ready - t0), 0, 1)
end

local function dropEntry(soil)
	local e = cache[soil]
	if e then
		if e.model then e.model:Destroy() end
		cache[soil] = nil
	end
end

local function addLabel(model, text, color)
	local root = model.PrimaryPart
	if not root then return end
	local h = model:GetExtentsSize().Y
	local bb = make("BillboardGui", { Name = "Tag", Size = UDim2.fromOffset(120, 26), StudsOffset = Vector3.new(0, h * 0.6 + 1.5, 0), AlwaysOnTop = false, MaxDistance = 40 }, root)
	local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.panel, BackgroundTransparency = 0.3 }, bb)
	K.corner(bg, UDim.new(1, 0))
	K.text(bg, "Готово · " .. text, { Size = UDim2.new(1, -10, 1, -6), Position = UDim2.fromOffset(5, 3), MaxText = 13, TextColor3 = color })
	return bb
end

local function refreshEntry(soil)
	local id = soil:GetAttribute("Plant")
	if not id or id == "" then dropEntry(soil) return end
	local plant = G.Plants[id]
	if not plant then return end
	local prog = progressOf(soil)
	local ready = prog >= 1
	local kind = prog < 0.15 and "sprout" or "plant"
	local key = bedKey(soil) .. "|" .. kind .. "|" .. tostring(ReplicatedStorage:GetAttribute("MeshesReady") == true)
	local e = cache[soil]
	if e and e.key ~= key then dropEntry(soil) e = nil end
	if not e then
		local m
		if kind == "sprout" then m = PM.sproutModel(plant) else m = PM.build(id, mutList(soil:GetAttribute("Muts"))) end
		local yaw = (soil:GetAttribute("Idx") or 1) * 1.7
		if kind == "plant" and prog < 0.3 and soil:GetAttribute("Plot") == ST.plot and FX.burst then
			FX.burst(soil.Position + Vector3.new(0, 1.5, 0), plant.c2, 16)
		end
		m:PivotTo(CFrame.new(soil.Position + Vector3.new(0, soil.Size.Y / 2, 0)) * CFrame.Angles(0, yaw, 0))
		m.Parent = fxFolder
		e = { model = m, key = key, kind = kind, yaw = yaw, ready = false }
		cache[soil] = e
	end
	-- чем тяжелее плод, тем больше растение (900 кг — огромное)
	local wscale = math.clamp(((soil:GetAttribute("Kg") or plant.kg) / plant.kg) ^ (1 / 3), 0.8, 7)
	e.wscale = wscale
	local s = kind == "sprout" and (0.55 + 0.45 * prog / 0.15) or (0.3 + 0.7 * ((prog - 0.15) / 0.85) ^ 0.7) * wscale
	if math.abs((e.scale or 0) - s) > 0.01 then
		e.scale = s
		e.model:ScaleTo(s)
	end
	-- таймер роста над своими растениями
	if not ready and soil:GetAttribute("Plot") == ST.plot then
		if not e.timer then
			local root = e.model.PrimaryPart
			if root then
				local bb = make("BillboardGui", { Name = "Timer", Size = UDim2.fromOffset(110, 34), StudsOffset = Vector3.new(0, 2.5 + 3.5 * plant.scale * s, 0), MaxDistance = 60, LightInfluence = 0 }, root)
				local bg = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = T.panel, BackgroundTransparency = 0.25 }, bb)
				K.corner(bg, UDim.new(0, 8))
				e.timerText = K.text(bg, "", { Size = UDim2.new(1, -8, 0, 18), Position = UDim2.fromOffset(4, 2), MaxText = 14 })
				local back, fill = K.bar(bg, T.green, { Size = UDim2.new(1, -12, 0, 5), Position = UDim2.new(0, 6, 1, -10) })
				e.timerFill = fill
				e.timer = bb
			end
		end
		if e.timerText then
			local waitW = (soil:GetAttribute("WaterAt") or 0) - nowS()
			e.timerText.Text = G.fmtTime((soil:GetAttribute("Ready") or 0) - nowS()) .. (waitW <= 0 and "  · полей" or "")
			e.timerText.TextColor3 = waitW <= 0 and T.cold or T.text
			e.timerFill.Size = UDim2.fromScale(prog, 1)
		end
	elseif e.timer then
		e.timer:Destroy()
		e.timer = nil
		e.timerText = nil
	end
	if ready and not e.ready then
		e.ready = true
		local kg = soil:GetAttribute("Kg") or 0
		local rar = G.rarestMut(mutList(soil:GetAttribute("Muts")))
		if soil:GetAttribute("Plot") == ST.plot then
			e.tag = addLabel(e.model, ("%.2f кг"):format(kg), rar and G.Mut[rar].color or rarityColor(id))
		end
		-- созревшее растение сияет и искрится
		local root = e.model.PrimaryPart
		if root then
			local att = make("Attachment", { Name = "ReadyFx", Position = Vector3.new(0, 2.5 * plant.scale * (e.wscale or 1), 0) }, root)
			make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(255, 236, 160)), LightEmission = 1, Rate = 6, Lifetime = NumberRange.new(0.8, 1.6),
				Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.25, 0), Transparency = NumberSequence.new(0, 1) }, att)
			e.readyLight = make("PointLight", { Color = Color3.fromRGB(255, 228, 160), Range = 10, Brightness = 0.8 }, root)
			e.model:ScaleTo((e.scale or 1) * 1.08)
		end
	elseif not ready and e.ready then
		e.ready = false
		if e.tag then e.tag:Destroy() end
	end
end

-- дальний огонь: светящийся шар на месте большого или редкого растения (виден с других планет)
local far = {}
local function farGlow(soil)
	local id = soil:GetAttribute("Plant")
	local plant = id and G.Plants[id]
	local f = far[soil]
	if not plant then
		if f then f:Destroy() far[soil] = nil end
		return
	end
	local muts = mutList(soil:GetAttribute("Muts"))
	local rar = G.rarestMut(muts)
	local tier = rar and G.Mut[rar].tier or 0
	local wscale = math.clamp(((soil:GetAttribute("Kg") or plant.kg) / plant.kg) ^ (1 / 3), 0.8, 7)
	if tier < 3 and wscale < 1.8 then
		if f then f:Destroy() far[soil] = nil end
		return
	end
	local prog = progressOf(soil)
	local size = math.clamp(1.2 * plant.scale * wscale * (0.3 + 0.7 * prog), 1.2, 7)
	if not f then
		f = make("Part", { Name = "FarGlow", Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Transparency = 0.1 }, fxFolder)
		far[soil] = f
	end
	f.Color = rar and PM.glowOf(G.Mut[rar]) or plant.c2:Lerp(Color3.new(0, 0, 0), 0.15)
	f.Size = Vector3.new(size, size, size)
	f.CFrame = CFrame.new(soil.Position + Vector3.new(0, size * 0.7, 0))
end
local function dropFar(soil)
	if far[soil] then far[soil]:Destroy() far[soil] = nil end
end

-- рядом: настоящие модели; далеко: только огни больших и редких растений
loop(0.4, function()
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	for soil in far do
		if not soil.Parent then dropFar(soil) end
	end
	for soil in cache do
		if not soil.Parent then dropEntry(soil) end
	end
	for _, plot in plotsFolder:GetChildren() do
		local beds = plot:FindFirstChild("Beds")
		local center = plot:GetAttribute("Center")
		if beds and center then
			local dist = (center - cp).Magnitude
			-- рядом: настоящие модели (до 170); огоньки только у далёких огородов, рядом с игроком пятен нет
			local near = dist < 220
			for _, bed in beds:GetChildren() do
				local soil = bed:FindFirstChild("Soil")
				if soil then
					if near and (soil.Position - cp).Magnitude < 170 then
						dropFar(soil)
						refreshEntry(soil)
					elseif near then
						dropEntry(soil)
						dropFar(soil)
					else
						dropEntry(soil)
						if dist < 4000 then farGlow(soil) else dropFar(soil) end
					end
				end
			end
		end
	end
end)

------------------------------------------------------------------ подсказки у грядок своего участка
local prompts = {}
local function ensurePrompts()
	if not ST.plot then return end
	local plot = plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local beds = plot and plot:FindFirstChild("Beds")
	if not beds then return end
	for _, bed in beds:GetChildren() do
		local soil = bed:FindFirstChild("Soil")
		if soil and not prompts[soil] then
			local idx = soil:GetAttribute("Idx")
			local pr = make("ProximityPrompt", { Name = "BedPrompt", MaxActivationDistance = 11, HoldDuration = 0, RequiresLineOfSight = false, ActionText = "Посадить", ObjectText = "Грядка", UIOffset = Vector2.new(0, 0) }, soil)
			pr.Triggered:Connect(function()
				local id = soil:GetAttribute("Plant")
				local top = soil.Position + Vector3.new(0, 1, 0)
				if not id or id == "" then
					if ST.sel then
						FX.splash(top, Color3.fromRGB(110, 80, 60), 18, 14)
						FX.floatText(top + Vector3.new(0, 2, 0), "Посажено!", T.green, 18)
						playSfx("plant", 0.9 + math.random() * 0.2)
					end
				elseif nowS() < (soil:GetAttribute("Ready") or 0) and G.Cans[ST.can or 0] and ((ST.cans or {})["c" .. ST.can] or 0) > 0 then
					local can = G.Cans[ST.can]
					FX.splash(top + Vector3.new(0, 4, 0), can.color, 50, 14)
					FX.floatText(top + Vector3.new(0, 3, 0), ("%s −%d%%"):format(can.name, math.floor(can.pct * 100)), can.color, 22)
					playSfx("water", 1.2)
				elseif nowS() < (soil:GetAttribute("Ready") or 0) and nowS() >= (soil:GetAttribute("WaterAt") or 0) then
					FX.splash(top + Vector3.new(0, 4, 0), Color3.fromRGB(120, 190, 255), 30, 10)
					FX.floatText(top + Vector3.new(0, 2.5, 0), "Полито: быстрее", T.cold, 18)
					playSfx("water", 0.9 + math.random() * 0.2)
				end
				remotes.Act:FireServer(idx)
			end)
			prompts[soil] = pr
		end
	end
end
loop(0.4, function()
	do
		ensurePrompts()
		for soil, pr in prompts do
			if not soil.Parent then prompts[soil] = nil continue end
			local idx = soil:GetAttribute("Idx") or 0
			local id = soil:GetAttribute("Plant")
			if idx > ST.bedCount then
				pr.Enabled = false
			elseif not id or id == "" then
				pr.Enabled = true
				pr.ActionText = ST.sel and ("Посадить: " .. plantName(ST.sel)) or "Нет семян"
				pr.ObjectText = "Пустая грядка"
			else
				local ready = nowS() >= (soil:GetAttribute("Ready") or 0)
				pr.ObjectText = plantName(id)
				if ready then
					pr.Enabled = true
					pr.ActionText = "Собрать урожай"
				else
					pr.Enabled = true
					local waitW = (soil:GetAttribute("WaterAt") or 0) - nowS()
					local left = G.fmtTime((soil:GetAttribute("Ready") or 0) - nowS())
					local can = G.Cans[ST.can or 0]
					if can and ((ST.cans or {})["c" .. ST.can] or 0) > 0 then
						pr.ActionText = ("%s: −%d%% · %s"):format(can.name, math.floor(can.pct * 100), left)
					elseif waitW > 0 then
						pr.ActionText = ("Растёт %s · полив через %d с"):format(left, math.ceil(waitW))
					else
						pr.ActionText = ("Полить (быстрее) · %s"):format(left)
					end
				end
			end
		end
	end
end)
-- киоски открывают окна (срабатывает для любой подсказки с атрибутом Window)
game:GetService("ProximityPromptService").PromptTriggered:Connect(function(pr)
	local w = pr:GetAttribute("Window")
	if w == "sell" then w = "bag" end
	if w and windows[w] and not windows[w].Visible then openWindow(w) end
	local gm = pr:GetAttribute("Game")
	if gm == "cannon" and FX.cannon then task.spawn(FX.cannon) end
	if gm == "telescope" and FX.telescope then task.spawn(FX.telescope) end
	if gm == "fishing" and FX.fishing then task.spawn(FX.fishing) end
	if gm == "race" and FX.race then task.spawn(FX.race) end
end)

------------------------------------------------------------------ сбор: частицы и тост
local function burst(pos, color, n)
	local att = make("Part", { Anchored = true, CanCollide = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) }, fxFolder)
	local a = make("Attachment", {}, att)
	local e = make("ParticleEmitter", { Color = ColorSequence.new(color), LightEmission = 1, Rate = 0, Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(8, 18),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.6, 0) }, a)
	e:Emit(n or 24)
	task.delay(1.5, function() att:Destroy() end)
end
-- всплывающий текст в мире
local function floatText(pos, text, color, size)
	local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) }, fxFolder)
	local bb = make("BillboardGui", { Size = UDim2.fromOffset(220, 40), AlwaysOnTop = true, LightInfluence = 0, MaxDistance = 120 }, p)
	local l = K.text(bb, text, { MaxText = size or 22, TextColor3 = color or T.gold })
	K.pop(bb:FindFirstChildOfClass("TextLabel") or l)
	TweenService:Create(bb, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { StudsOffset = Vector3.new(0, 4, 0) }):Play()
	task.delay(0.8, function()
		if l.Parent then TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1 }):Play() end
	end)
	task.delay(1.5, function() p:Destroy() end)
end
-- плод летит к игроку по дуге
local function flyToPlayer(from, color, size)
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local b = make("Part", { Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = color, Size = Vector3.new(size, size, size), CFrame = CFrame.new(from) }, fxFolder)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / 0.55, 0, 1)
		local to = root.Position + Vector3.new(0, 1.5, 0)
		local p = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
		b.CFrame = CFrame.new(p)
		b.Size = Vector3.new(size, size, size) * (1 - 0.6 * k)
		if k >= 1 then
			conn:Disconnect()
			b:Destroy()
		end
	end)
end
local function splash(pos, color, n, speed)
	local att = make("Part", { Anchored = true, CanCollide = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos) }, fxFolder)
	local a = make("Attachment", {}, att)
	local e = make("ParticleEmitter", { Color = ColorSequence.new(color), LightEmission = 0.3, Rate = 0, Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(speed * 0.5, speed),
		SpreadAngle = Vector2.new(50, 50), Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new(0.35, 0.1) }, a)
	e:Emit(n)
	task.delay(1.2, function() att:Destroy() end)
end

FX.splash, FX.floatText, FX.burst = splash, floatText, burst

remotes:WaitForChild("Harvest").OnClientEvent:Connect(function(bedIdx, id, muts, kg)
	local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local bedsF = plot and plot:FindFirstChild("Beds")
	local bed = bedsF and bedsF:FindFirstChild("Bed" .. tostring(bedIdx))
	if bed and bed:FindFirstChild("Soil") then
		local rar = G.rarestMut(muts or {})
		local col = rar and G.Mut[rar].color or rarityColor(id)
		local top = bed.Soil.Position + Vector3.new(0, 3, 0)
		burst(top, col, 24 + (rar and 20 or 0))
		flyToPlayer(top, G.Plants[id].c1, 1.2)
		local ws = ((kg or 1) / G.Plants[id].kg) ^ (1 / 3)
		if ws >= 1.8 then
			floatText(top + Vector3.new(0, 4, 0), ("ГИГАНТ! %.1f кг"):format(kg), T.gold, 34)
			burst(top, T.gold, 70)
			local cam = workspace.CurrentCamera
			task.spawn(function()
				for i = 1, 12 do
					if cam then cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.6, 0) end
					task.wait(0.03)
				end
			end)
		else
			floatText(top + Vector3.new(0, 2, 0), ("+%.2f кг"):format(kg or 0), col, 24)
		end
	end
	local name = plantName(id)
	local title = G.mutTitle(muts or {})
	toast(("%s%s, %.2f кг"):format(title ~= "" and (title .. " ") or "", name, kg or 0), title ~= "" and "rare" or "ok")
	playSfx(title ~= "" and "harvestRare" or "harvest")
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(who, plant, title, chance, pos)
	toast(("%s нашёл «%s %s» (%s)!"):format(who, title, plant, G.fmtOdds(chance)), "rare", 7)
	-- сверхредкая находка: столб света виден со всех планет, вспышка и баннер
	if typeof(pos) == "Vector3" and chance <= 1 / 1000000 then
		playSfx("legendary")
		local col = Color3.fromRGB(255, 230, 150)
		local beam = make("Part", { Name = "LegendBeam", Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = col, Transparency = 0.3, Size = Vector3.new(3000, 8, 8), CFrame = CFrame.new(pos + Vector3.new(0, 1500, 0)) * CFrame.Angles(0, 0, math.pi / 2) }, fxFolder)
		make("PointLight", { Color = col, Range = 60, Brightness = 5 }, beam)
		TweenService:Create(beam, TweenInfo.new(20), { Transparency = 1, Size = Vector3.new(3000, 2, 2) }):Play()
		task.delay(20, function() beam:Destroy() end)
		local gui = make("ScreenGui", { Name = "Legend", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 55 }, pg)
		local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.1 }, gui)
		TweenService:Create(flash, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		local b = K.text(gui, title .. "!", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(700, 60), MaxText = 48, TextColor3 = T.gold })
		K.text(gui, who .. " · " .. plant .. " · " .. G.fmtOdds(chance), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(700, 30), MaxText = 22 })
		K.pop(b)
		task.delay(6, function() gui:Destroy() end)
	end
end)

------------------------------------------------------------------ падающие звёзды: покачивание и сбор
remotes:WaitForChild("Collected").OnClientEvent:Connect(function(coins, seed, pos, meteor)
	local text = (meteor and "Метеорит! +" or "Звезда: +") .. G.fmt(coins) .. " монет"
	if seed then text ..= ", семя «" .. plantName(seed) .. "»" end
	toast(text, (meteor or seed) and "rare" or "ok", 3)
	playSfx(meteor and "mutation" or "star", 0.95 + math.random() * 0.1)
	if typeof(pos) == "Vector3" then burst(pos, meteor and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 232, 160), meteor and 40 or 18) end
end)
-- звезда летит с неба (ярко, со шлейфом), после падения светится и постепенно гаснет
RunService.RenderStepped:Connect(function()
	local starF = world:FindFirstChild("Stars")
	if not starF then return end
	local t = nowS()
	local clock = os.clock()
	for _, m in starF:GetChildren() do
		local core = m:FindFirstChild("Core")
		local landAt = m:GetAttribute("LandAt")
		if core and landAt then
			local land = m:GetAttribute("LandPos")
			if not land then
				land = core.Position
				m:SetAttribute("LandPos", land)
				local a0 = make("Attachment", { Position = Vector3.new(0, 0.5, 0) }, core)
				local a1 = make("Attachment", { Position = Vector3.new(0, -0.5, 0) }, core)
				make("Trail", { Attachment0 = a0, Attachment1 = a1, Lifetime = 0.5, LightEmission = 1, Color = ColorSequence.new(core.Color),
					Transparency = NumberSequence.new(0.1, 1), WidthScale = NumberSequence.new(1, 0), FaceCamera = true }, core)
			end
			local glow = core:FindFirstChild("Glow")
			if t < landAt then
				local k = math.clamp((landAt - t) / G.Stars.fall, 0, 1)
				local a = m:GetAttribute("Angle") or 0
				local off = Vector3.new(math.cos(a) * 90, 190, math.sin(a) * 90) * k
				core.CFrame = CFrame.new(land + off)
				core.Transparency = 0
				if glow then glow.Brightness = 3 end
			else
				local k = math.clamp((t - landAt) / G.Stars.glow, 0, 1)
				if not m:GetAttribute("Landed") then
					m:SetAttribute("Landed", true)
					if (land - (workspace.CurrentCamera and workspace.CurrentCamera.CFrame.Position or land)).Magnitude < 220 then
						burst(land, core.Color, m:GetAttribute("Meteor") and 30 or 14)
					end
				end
				core.CFrame = CFrame.new(land + Vector3.new(0, math.sin(clock * 2 + land.X) * 0.25, 0)) * CFrame.Angles(0, clock * 1.5, 0.3)
				core.Transparency = 0.05 + 0.85 * k ^ 1.4
				if glow then glow.Brightness = 1.6 * (1 - k) end
				local tr = core:FindFirstChildOfClass("Trail")
				if tr then tr.Enabled = false end
			end
		end
	end
end)

------------------------------------------------------------------ полёт: ракета взлетает, экран светлеет, прилёт на новую планету
function playLaunch(target)
	local cam = workspace.CurrentCamera
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not cam or not root then return end
	hud.Enabled = false
	local function padOf(i)
		local pf = world:FindFirstChild("Planet" .. i)
		local pad = pf and pf:FindFirstChild("Hub") and pf.Hub:FindFirstChild("RocketPad")
		return pad and pad:GetPivot().Position
	end
	local here = root.Position
	local base, bd = here, math.huge
	for i = 1, #G.Planets do
		local p = padOf(i)
		if p and (p - here).Magnitude < bd then base, bd = p, (p - here).Magnitude end
	end
	local dest = padOf(target) or base + Vector3.new(0, 0, 800)
	-- местная ракета
	local rk = Instance.new("Model")
	rk.Name = "LaunchRocket"
	local function rp(size, color, mat, shape)
		local p = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Size = size, Color = color, Material = mat }, rk)
		if shape then p.Shape = shape end
		return p
	end
	local body = rp(Vector3.new(12, 4.2, 4.2), Color3.fromRGB(235, 238, 248), Enum.Material.Metal, Enum.PartType.Cylinder)
	local nose = rp(Vector3.new(4.2, 6, 4.2), Color3.fromRGB(235, 70, 80), Enum.Material.Metal)
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, nose)
	local flame = rp(Vector3.new(3.2, 7, 3.2), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
	make("SpecialMesh", { MeshType = Enum.MeshType.Sphere }, flame)
	make("PointLight", { Color = Color3.fromRGB(255, 190, 120), Range = 50, Brightness = 4 }, flame)
	local fa = make("Attachment", {}, flame)
	local smoke = make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(200, 196, 210)), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 9) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }), Lifetime = NumberRange.new(1.5, 2.5), Rate = 60,
		Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Bottom, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60) }, fa)
	local sparks = make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 90, 40)), Size = NumberSequence.new(0.6, 0), LightEmission = 1,
		Lifetime = NumberRange.new(0.3, 0.6), Rate = 120, Speed = NumberRange.new(20, 35), SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Bottom }, fa)
	local streak = make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(220, 235, 255)), Size = NumberSequence.new(0.25, 0.05), LightEmission = 1, Lifetime = NumberRange.new(0.25, 0.4),
		Rate = 0, Speed = NumberRange.new(150, 200), SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Bottom }, fa)
	local function place(pos, look)
		look = (look and look.Magnitude > 0.01) and look.Unit or Vector3.new(0, 1, 0)
		local cf = CFrame.lookAt(pos, pos + look) * CFrame.Angles(-math.pi / 2, 0, 0)
		body.CFrame = cf * CFrame.new(0, 7.5, 0) * CFrame.Angles(0, 0, math.pi / 2)
		nose.CFrame = cf * CFrame.new(0, 14.5, 0)
		flame.CFrame = cf * CFrame.new(0, -0.5, 0)
	end
	place(base, nil)
	rk.Parent = fxFolder
	local gui = make("ScreenGui", { Name = "Launch", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 60 }, pg)
	local fade = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 10, 24), BackgroundTransparency = 1 }, gui)
	local count = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(300, 110), MaxText = 96, TextColor3 = T.gold })
	local title = K.text(gui, "Полёт на планету " .. G.Planets[target].name, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.84), Size = UDim2.fromOffset(600, 36), MaxText = 28, TextColor3 = G.PlanetColors[target], TextTransparency = 1 })
	cam.CameraType = Enum.CameraType.Scriptable
	local T_COUNT, T_LIFT, T_CRUISE, T_LAND = 1.5, 1.9, 2.8, 1.3 -- сумма ≈ G.TravelTime
	local liftTop = base + Vector3.new(0, 140, 0)
	local destTop = dest + Vector3.new(0, 160, 0)
	local mid = (liftTop + destTop) / 2 + Vector3.new(0, 220, 0)
	local function bez(t) return liftTop:Lerp(mid, t):Lerp(mid:Lerp(destTop, t), t) end
	local t0 = os.clock()
	local lastCount = 0
	local played = false
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local pos, look, camPos, camAt
		if t < T_COUNT then
			local n = 3 - math.floor(t / (T_COUNT / 3))
			if n ~= lastCount and n >= 1 then lastCount = n count.Text = tostring(n) K.pop(count) playSfx("beep") end
			pos = base + Vector3.new((math.random() - 0.5) * 0.15 * t, 0, (math.random() - 0.5) * 0.15 * t)
			flame.Size = Vector3.new(2, 3 + t * 2, 2)
			camPos, camAt = base + Vector3.new(24, 6, 26), base + Vector3.new(0, 9, 0)
		elseif t < T_COUNT + T_LIFT then
			local k = (t - T_COUNT) / T_LIFT
			if not played then played = true count.Text = "ПУСК!" K.pop(count) playSfx("go") playSfx("rocket") end
			if k > 0.35 then count.Text = "" end
			pos = base:Lerp(liftTop, k * k)
			flame.Size = Vector3.new(3.4, 8 + math.sin(t * 40) * 1.5, 3.4)
			local shake = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * (1 - k) * 1.2
			camPos, camAt = base + Vector3.new(30, 8 + k * 70, 34) + shake, pos + Vector3.new(0, 8, 0)
			title.TextTransparency = 1 - k
		elseif t < T_COUNT + T_LIFT + T_CRUISE then
			local k = (t - T_COUNT - T_LIFT) / T_CRUISE
			local e = k * k * (3 - 2 * k)
			if not UI.cruiseSfx then UI.cruiseSfx = true playSfx("whoosh", 0.8) end
			pos = bez(e)
			look = bez(math.min(1, e + 0.02)) - pos
			streak.Rate = 120
			smoke.Rate = 10
			local back = look.Magnitude > 0.01 and -look.Unit or Vector3.new(0, -1, 0)
			camPos, camAt = pos + back * 40 + Vector3.new(0, 14, 0) + Vector3.new(math.sin(t) * 6, 0, math.cos(t) * 6), pos + (look.Magnitude > 0.01 and look.Unit * 30 or Vector3.zero)
		else
			local k = math.clamp((t - T_COUNT - T_LIFT - T_CRUISE) / T_LAND, 0, 1)
			local e = 1 - (1 - k) ^ 2
			if UI.cruiseSfx then UI.cruiseSfx = false playSfx("rocket", 1.25) end
			pos = destTop:Lerp(dest, e)
			look = Vector3.new(0, 1, 0)
			streak.Rate = 0
			smoke.Rate = 60
			flame.Size = Vector3.new(3, 6 * (1 - e) + 1, 3)
			camPos, camAt = dest + Vector3.new(28, 12, 30), pos + Vector3.new(0, 8, 0)
			title.TextTransparency = e
		end
		place(pos, look)
		cam.CFrame = CFrame.lookAt(camPos, camAt)
	end)
	task.wait(T_COUNT + T_LIFT + T_CRUISE + T_LAND)
	conn:Disconnect()
	if FX.burst then FX.burst(dest + Vector3.new(0, 1, 0), Color3.fromRGB(230, 220, 210), 40) end
	playSfx("boom", 1.3)
	playSfx("unlock")
	task.wait(0.4)
	rk:Destroy()
	cam.CameraType = Enum.CameraType.Custom
	if ch:FindFirstChild("Humanoid") then cam.CameraSubject = ch.Humanoid end
	gui:Destroy()
	hud.Enabled = true
	toast("Добро пожаловать на планету " .. G.Planets[target].name .. "! Огород ждёт тебя (кнопка «Домой»)", "rare", 5)
end

-- столб света над своим огородом: его видно издалека, легко вернуться
do
	local beacon = make("Part", { Name = "HomeBeacon", Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 214, 120), Transparency = 0.82, Size = Vector3.new(260, 1.2, 1.2) }, fxFolder)
	local tagPart = make("Part", { Name = "HomeTag", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(1, 1, 1) }, fxFolder)
	local bb = make("BillboardGui", { Size = UDim2.fromOffset(130, 28), AlwaysOnTop = false, LightInfluence = 0, MaxDistance = 2500 }, tagPart)
	local tag = K.text(bb, "ТВОЙ ОГОРОД", { MaxText = 13, TextColor3 = T.gold })
	loop(0.5, function()
		local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
		local center = plot and plot:GetAttribute("Center")
		if not center then
			beacon.Transparency, bb.Enabled = 1, false
			return
		end
		beacon.CFrame = CFrame.new(center + Vector3.new(0, 130, 0)) * CFrame.Angles(0, 0, math.pi / 2)
		tagPart.CFrame = CFrame.new(center + Vector3.new(0, 24, 0))
		local ch = plr.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local d = root and (root.Position - center).Magnitude or 0
		bb.Enabled = d > 45
		beacon.Transparency = d > 45 and 0.82 or 1
		tag.Text = ("ТВОЙ ОГОРОД  %d м"):format(math.floor(d))
	end)
end

-- оттенок картинки зависит от планеты, на которой стоишь
do
	local current = 0
	local PLANET_CENTERS = {}
	loop(1, function()
		if #PLANET_CENTERS == 0 then
			for i = 1, #G.Planets do
				local pf = world:FindFirstChild("Planet" .. i)
				local pad = pf and pf:FindFirstChild("Hub") and pf.Hub:FindFirstChild("RocketPad")
				if pad then PLANET_CENTERS[i] = pad:GetPivot().Position end
			end
		end
		local ch = plr.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then return end
		local best, bd = 1, math.huge
		for i, c in PLANET_CENTERS do
			local d = (c - root.Position).Magnitude
			if d < bd then best, bd = i, d end
		end
		if best ~= current then
			current = best
			if FX.setWeather then FX.setWeather(best) end
			local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
			if cc then
				TweenService:Create(cc, TweenInfo.new(2), { TintColor = Color3.new(1, 1, 1):Lerp(G.PlanetColors[best], 0.12) }):Play()
			end
		end
	end)
end

remotes:WaitForChild("Strike").OnClientEvent:Connect(function(pos, mut, who)
	local cam = workspace.CurrentCamera
	if not cam or (cam.CFrame.Position - pos).Magnitude > 400 then return end
	local from = pos + Vector3.new(60, 160, 30)
	local m = make("Part", { Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 160, 80), Size = Vector3.new(2.2, 2.2, 2.2), CFrame = CFrame.new(from) }, fxFolder)
	local a0 = make("Attachment", { Position = Vector3.new(0, 0.6, 0) }, m)
	local a1 = make("Attachment", { Position = Vector3.new(0, -0.6, 0) }, m)
	make("Trail", { Attachment0 = a0, Attachment1 = a1, Lifetime = 0.5, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 190, 110)), FaceCamera = true,
		Transparency = NumberSequence.new(0, 1), WidthScale = NumberSequence.new(1, 0) }, m)
	make("PointLight", { Color = Color3.fromRGB(255, 170, 90), Range = 30, Brightness = 3 }, m)
	local t0 = os.clock()
	playSfx("meteor")
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / 0.8, 0, 1)
		m.CFrame = CFrame.new(from:Lerp(pos, k * k))
		if k >= 1 then
			conn:Disconnect()
			m:Destroy()
			burst(pos + Vector3.new(0, 1, 0), Color3.fromRGB(255, 170, 90), 50)
			splash(pos, Color3.fromRGB(255, 140, 70), 30, 22)
			local flash = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)) }, fxFolder)
			local l = make("PointLight", { Color = Color3.fromRGB(255, 200, 140), Range = 40, Brightness = 8 }, flash)
			TweenService:Create(l, TweenInfo.new(0.8), { Brightness = 0 }):Play()
			task.delay(0.9, function() flash:Destroy() end)
			if mut then
				playSfx("mutation")
				floatText(pos + Vector3.new(0, 5, 0), "Метеорит! " .. G.Mut[mut].name, G.Mut[mut].color, 26)
			end
		end
	end)
end)

------------------------------------------------------------------ атмосфера планет: пыль, снег, искры, светлячки вокруг игрока
do
	local holder = make("Part", { Name = "Weather", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(90, 1, 90) }, fxFolder)
	local em = make("ParticleEmitter", { Rate = 0, LightEmission = 0.6, EmissionDirection = Enum.NormalId.Bottom, SpreadAngle = Vector2.new(25, 25) }, holder)
	local W = {
		{ col = Color3.fromRGB(200, 200, 215), rate = 18, speed = { 0.3, 1 }, size = { 0.12, 0.05 }, life = { 6, 9 }, acc = Vector3.new(0.4, -0.2, 0), light = 0.2 }, -- лунная пыль
		{ col = Color3.fromRGB(220, 120, 80), rate = 45, speed = { 6, 12 }, size = { 0.25, 0.1 }, life = { 3, 5 }, acc = Vector3.new(14, -1, 4), light = 0.1 }, -- пыльный ветер Марса
		{ col = Color3.fromRGB(240, 246, 255), rate = 60, speed = { 3, 5 }, size = { 0.22, 0.18 }, life = { 6, 9 }, acc = Vector3.new(1, -2, 0.5), light = 0.3 }, -- снег Европы
		{ col = Color3.fromRGB(255, 140, 50), rate = 30, speed = { 2, 5 }, size = { 0.18, 0 }, life = { 3, 5 }, acc = Vector3.new(0, 7, 0), light = 1 }, -- искры Ио
		{ col = Color3.fromRGB(150, 255, 210), rate = 22, speed = { 0.5, 1.5 }, size = { 0.2, 0 }, life = { 4, 7 }, acc = Vector3.new(0, 0.6, 0), light = 1 }, -- светлячки Туманности
		{ col = Color3.fromRGB(255, 220, 130), rate = 26, speed = { 0.5, 2 }, size = { 0.16, 0 }, life = { 4, 6 }, acc = Vector3.new(0, 1, 0), light = 1 }, -- золотые искры Ядра
	}
	function FX.setWeather(pi)
		local w = W[pi] or W[1]
		em.Color = ColorSequence.new(w.col)
		em.Rate = w.rate
		em.Speed = NumberRange.new(w.speed[1], w.speed[2])
		em.Size = NumberSequence.new(w.size[1], w.size[2])
		em.Lifetime = NumberRange.new(w.life[1], w.life[2])
		em.Acceleration = w.acc
		em.LightEmission = w.light
		em.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.2), NumberSequenceKeypoint.new(1, 1) })
	end
	FX.setWeather(1)
	RunService.RenderStepped:Connect(function()
		local cam = workspace.CurrentCamera
		if cam then holder.CFrame = CFrame.new(cam.CFrame.Position + Vector3.new(0, 18, 0)) end
	end)
end

------------------------------------------------------------------ мини-игра «Опыление»: поймай рой пыльцы 5 раз
remotes:WaitForChild("Pollen").OnClientEvent:Connect(function(bedIdx, token)
	local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local bedsF = plot and plot:FindFirstChild("Beds")
	local bed = bedsF and bedsF:FindFirstChild("Bed" .. tostring(bedIdx))
	local soil = bed and bed:FindFirstChild("Soil")
	if not soil then return end
	local center = soil.Position + Vector3.new(0, 4, 0)
	local swarm = make("Part", { Name = "Pollen", Shape = Enum.PartType.Ball, Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
		Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 230, 120), Size = Vector3.new(1.3, 1.3, 1.3), CFrame = CFrame.new(center) }, fxFolder)
	make("PointLight", { Color = Color3.fromRGB(255, 220, 120), Range = 14, Brightness = 2 }, swarm)
	local att = make("Attachment", {}, swarm)
	make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(255, 240, 150)), LightEmission = 1, Rate = 30, Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Size = NumberSequence.new(0.25, 0), Transparency = NumberSequence.new(0, 1) }, att)
	local bb = make("BillboardGui", { Name = "PollenTap", Adornee = swarm, Size = UDim2.fromOffset(96, 96), AlwaysOnTop = true, Active = true, LightInfluence = 0, ResetOnSpawn = false, MaxDistance = 120 }, pg)
	local btn = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, bb)
	local ringF = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.8, 0.8), BackgroundTransparency = 1 }, btn)
	K.corner(ringF, UDim.new(1, 0))
	K.stroke(ringF, T.gold, 3, false, 0)
	local cnt = K.text(btn, "0/5", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(80, 22), MaxText = 18, TextColor3 = T.gold })
	toast("Пыльца над грядкой! Тапни по рою 5 раз", "rare", 4)
	playSfx("tap", 0.8)
	local taps, done, t0, angle = 0, false, os.clock(), 0
	local conn = RunService.RenderStepped:Connect(function(dt)
		angle += dt * (1.6 + taps * 0.5)
		local r = 3 + math.sin(os.clock() * 2) * 0.8
		swarm.CFrame = CFrame.new(center + Vector3.new(math.cos(angle) * r, math.sin(os.clock() * 3) * 1.2, math.sin(angle) * r))
		local k = 1 + math.sin(os.clock() * 8) * 0.08
		ringF.Size = UDim2.fromScale(0.8 * k, 0.8 * k)
	end)
	btn.Activated:Connect(function()
		if done then return end
		taps += 1
		cnt.Text = taps .. "/5"
		playSfx("tap", 1 + taps * 0.12)
		burst(swarm.Position, Color3.fromRGB(255, 236, 140), 14)
		K.pop(btn)
		angle += math.pi * (0.6 + math.random())
		if taps >= 5 then
			done = true
			local ok, mut = remotes.PollenDone:InvokeServer(token)
			if ok then
				burst(soil.Position + Vector3.new(0, 3, 0), Color3.fromRGB(255, 236, 140), 50)
				FX.floatText(soil.Position + Vector3.new(0, 6, 0), mut and ("Опыление! " .. G.Mut[mut].name) or "Опыление! рост +35%", mut and G.Mut[mut].color or T.gold, 24)
				playSfx(mut and "harvestRare" or "coins")
			end
		end
	end)
	while not done and os.clock() - t0 < 13 do task.wait(0.1) end
	conn:Disconnect()
	bb:Destroy()
	TweenService:Create(swarm, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) }):Play()
	task.delay(0.5, function() swarm:Destroy() end)
end)

------------------------------------------------------------------ фото-режим: без интерфейса, камера медленно облетает огород
function FX.photoMode()
	local cam = workspace.CurrentCamera
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not cam or not root then return end
	local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local center = (plot and plot:GetAttribute("Center")) or root.Position
	if (center - root.Position).Magnitude > 60 then center = root.Position end
	local hidden = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "Photo" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
	local gui = make("ScreenGui", { Name = "Photo", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 80 }, pg)
	local exit = make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "" }, gui)
	local hintL = K.text(gui, "Коснись экрана, чтобы выйти", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(360, 22), MaxText = 15, TextColor3 = T.sub })
	task.delay(2.5, function() if hintL.Parent then TweenService:Create(hintL, TweenInfo.new(1), { TextTransparency = 1 }):Play() end end)
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local a = t * 0.12
		local r = 46 + math.sin(t * 0.2) * 8
		cam.CFrame = CFrame.lookAt(center + Vector3.new(math.cos(a) * r, 16 + math.sin(t * 0.3) * 6, math.sin(a) * r), center + Vector3.new(0, 4, 0))
	end)
	exit.Activated:Connect(function()
		conn:Disconnect()
		gui:Destroy()
		for _, g in hidden do g.Enabled = true end
		pcall(function() game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
		cam.CameraType = Enum.CameraType.Custom
		if ch:FindFirstChild("Humanoid") then cam.CameraSubject = ch.Humanoid end
	end)
end

------------------------------------------------------------------ свободное падение: ветер, полосы, приземление
remotes:WaitForChild("Skydive").OnClientEvent:Connect(function()
	toast("Свободное падение!", "rare", 3)
	playSfx("whoosh", 0.7)
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local att = make("Attachment", { Name = "SkyFx" }, root)
	local e = make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(220, 235, 255)), LightEmission = 0.5, Rate = 80, Lifetime = NumberRange.new(0.3, 0.5),
		Speed = NumberRange.new(60, 90), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new(0.15, 0.05),
		Transparency = NumberSequence.new(0.2, 1) }, att)
	local hum = ch:FindFirstChildOfClass("Humanoid")
	local t0 = os.clock()
	while os.clock() - t0 < 12 do
		task.wait(0.1)
		if hum and hum.FloorMaterial ~= Enum.Material.Air and os.clock() - t0 > 0.6 then break end
	end
	e.Enabled = false
	task.delay(1, function() att:Destroy() end)
	if FX.burst then FX.burst(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(255, 230, 170), 40) end
	if FX.splash then FX.splash(root.Position - Vector3.new(0, 2.5, 0), Color3.fromRGB(180, 170, 200), 30, 25) end
	playSfx("meteor", 1.3)
end)

------------------------------------------------------------------ показ редких мутаций (кинематика)
local revealQueue, revealing = {}, false
local function playReveal(info)
	local rarest = G.rarestMut(info.m)
	local mt = rarest and G.Mut[rarest]
	local col = info.color or (mt and mt.color) or T.gold
	if info.sfx then playSfx(info.sfx) end
	playSfx((info.head or (mt and mt.tier >= 5)) and "legendary" or "reveal")
	local gui = make("ScreenGui", { Name = "Reveal", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 50 }, pg)
	local back = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1 }, gui)
	TweenService:Create(back, TweenInfo.new(0.5), { BackgroundTransparency = 0.12 }):Play()
	-- лучи
	local rays = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1 }, back)
	for i = 1, 12 do
		local r = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(900, 14), BackgroundColor3 = col, BackgroundTransparency = 0.7, Rotation = i * 15, BorderSizePixel = 0 }, rays)
		K.gradient(r, col, col)
	end
	local holder = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromScale(0.1, 0.1), BackgroundTransparency = 1 }, back)
	local vp, setAngle = modelView(holder, info.id, info.m, false)
	TweenService:Create(holder, TweenInfo.new(0.9, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.fromScale(0.5, 0.58) }):Play()
	local head = K.text(back, info.head or "МУТАЦИЯ!", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromOffset(500, 56), MaxText = 52, TextColor3 = col })
	local title = G.mutTitle(info.m)
	K.text(back, (title ~= "" and (title .. " ") or "") .. plantName(info.id) .. (info.head and " (семя)" or ""), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(640, 40), MaxText = 34, TextColor3 = T.text })
	K.text(back, info.sub or ("Шанс " .. G.fmtOdds(info.chance) .. ", вес " .. ("%.2f"):format(info.w) .. " кг"), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromOffset(560, 30), MaxText = 24, TextColor3 = T.gold })
	local flash = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0 }, back)
	TweenService:Create(flash, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
	local ok = K.button(back, "Круто!", T.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(200, 48), MaxText = 24 })
	local done = false
	ok.Activated:Connect(function() done = true end)
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		rays.Rotation = t * 18
		setAngle(math.rad(-35) + t * 0.9)
		if t < 0.7 then
			back.Position = UDim2.fromOffset(math.random(-8, 8) * (1 - t / 0.7), math.random(-8, 8) * (1 - t / 0.7))
		else
			back.Position = UDim2.new()
		end
	end)
	for _ = 1, 160 do
		if done then break end
		task.wait(0.05)
	end
	conn:Disconnect()
	TweenService:Create(back, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()
	task.wait(0.4)
	gui:Destroy()
end
remotes:WaitForChild("Reveal").OnClientEvent:Connect(function(info)
	table.insert(revealQueue, info)
	if revealing then return end
	revealing = true
	task.spawn(function()
		while #revealQueue > 0 do
			playReveal(table.remove(revealQueue, 1))
			task.wait(0.3)
		end
		revealing = false
	end)
end)

------------------------------------------------------------------ события и атмосфера
local cc = Lighting:FindFirstChildOfClass("ColorCorrectionEffect")
local baseTint = cc and cc.TintColor or Color3.new(1, 1, 1)
local function tintTo(color)
	if cc then TweenService:Create(cc, TweenInfo.new(2), { TintColor = color }):Play() end
end
local function streak(color, size, dur)
	local a = Vector3.new(math.random(-260, 260), math.random(160, 320), math.random(-260, 260))
	local dir = Vector3.new(math.random(-60, 60), -math.random(110, 200), math.random(-60, 60))
	local p = make("Part", { Anchored = true, CanCollide = false, CastShadow = false, Material = Enum.Material.Neon, Color = color, Size = Vector3.new(size, size, size * 14) }, fxFolder)
	p.CFrame = CFrame.lookAt(a, a + dir)
	local light = make("PointLight", { Color = color, Range = 30, Brightness = 2 }, p)
	TweenService:Create(p, TweenInfo.new(dur, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(a + dir * 2.2, a + dir * 3), Transparency = 1 }):Play()
	task.delay(dur + 0.1, function() p:Destroy() end)
end
local lastEvent = ""
remotes:WaitForChild("Event").OnClientEvent:Connect(function(id, left)
	local ev
	for _, e in G.Events do if e.id == id then ev = e end end
	if not ev then return end
	toast(ev.name .. "! " .. ev.desc, "rare", 6)
	local title = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(560, 70), BackgroundTransparency = 1 }, hud)
	local lbl = K.text(title, ev.name, { MaxText = 56, TextColor3 = ev.color })
	K.pop(title)
	task.delay(3.5, function() title:Destroy() end)
end)
task.spawn(function()
	local nextStar = 0
	while true do
		task.wait(0.35)
		local id = ReplicatedStorage:GetAttribute("EventId") or ""
		if id ~= lastEvent then
			lastEvent = id
			if id == "flare" then tintTo(Color3.fromRGB(255, 232, 190))
			elseif id == "nebula" then tintTo(Color3.fromRGB(235, 205, 255))
			elseif id == "meteor" then tintTo(Color3.fromRGB(255, 225, 215))
			else tintTo(baseTint) end
		end
		if id == "meteor" then
			streak(Color3.fromRGB(255, 170, 90), 1.6, 1.4)
			if math.random() < 0.5 then streak(Color3.fromRGB(255, 230, 160), 1.1, 1.2) end
		elseif id == "nebula" and math.random() < 0.3 then
			streak(Color3.fromRGB(210, 130, 255), 0.9, 2)
		end
		if os.clock() > nextStar then
			nextStar = os.clock() + math.random(8, 20)
			streak(Color3.fromRGB(190, 230, 255), 0.5, 1.6)
		end
	end
end)

------------------------------------------------------------------ сцены со своей камерой: пушка и телескоп
local UIS = game:GetService("UserInputService")
function FX.scene(name)
	local hidden = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= name then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local gui = make("ScreenGui", { Name = name, ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 70 }, pg)
	local cam = workspace.CurrentCamera
	local fov0 = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	local ws0 = hum and hum.WalkSpeed
	if hum then hum.WalkSpeed = 0 end
	local function close()
		if not gui.Parent then return end
		gui:Destroy()
		for _, g in hidden do g.Enabled = true end
		cam.FieldOfView = fov0
		cam.CameraType = Enum.CameraType.Custom
		if hum then
			hum.WalkSpeed = ws0
			cam.CameraSubject = hum
		end
	end
	return gui, cam, close
end

-- Европа: метеорная пушка. Тапай по метеоритам, золотые стоят 3 очка
function FX.cannon()
	if FX.busy then return end
	local ok, dur = remotes.CannonStart:InvokeServer()
	if not ok then toast(dur or "Пушка недоступна", "bad") return end
	FX.busy = true
	local lab = world:FindFirstChild("MeteorCannon", true)
	local barrel = lab and lab:FindFirstChild("Barrel")
	local pivot = barrel and barrel:GetAttribute("Pivot")
	if not pivot then
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		pivot = CFrame.new(root and root.Position or Vector3.zero)
	end
	local barrel0 = barrel and barrel:GetPivot()
	local rel = barrel and (pivot * CFrame.Angles(math.rad(35), 0, 0)):ToObjectSpace(barrel0)
	local origin, out, right = pivot.Position, pivot.LookVector, pivot.RightVector
	local up = Vector3.yAxis
	local gui, cam, close = FX.scene("CannonGame")
	cam.FieldOfView = 70
	local signs = {}
	if lab then
		for _, d in lab:GetDescendants() do
			if d:IsA("BillboardGui") and d.Enabled then d.Enabled = false table.insert(signs, d) end
		end
	end
	local camPos = origin - out * 22 + up * 6
	cam.CFrame = CFrame.lookAt(camPos, origin + out * 80 + up * 42)
	local timeL = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(220, 40), MaxText = 34, TextColor3 = T.text })
	local hitL = K.text(gui, "Сбито: 0", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(260, 30), MaxText = 24, TextColor3 = T.gold })
	local hint = K.text(gui, "Целься точно в метеориты! Золотые = 3 очка, промах сбрасывает комбо", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -20), Size = UDim2.fromOffset(520, 30), MaxText = 22, TextColor3 = T.cold })
	task.delay(3, function() if hint.Parent then TweenService:Create(hint, TweenInfo.new(1), { TextTransparency = 1 }):Play() end end)
	local exitB = K.button(gui, "Выйти", T.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(110, 40), MaxText = 18 })
	local meteors, hits, combo, lastHit = {}, 0, 0, 0
	local running = true
	exitB.Activated:Connect(function() running = false end)
	local function spawnMeteor(t)
		local gold = math.random() < 0.12
		local d = gold and 5.5 or math.random(70, 110) / 10
		local pos = origin + out * math.random(170, 240) + right * math.random(-110, 110) + up * math.random(70, 130)
		local target = origin + out * math.random(20, 60) + right * math.random(-50, 50) + up * math.random(-25, 5)
		local speed = (gold and 1.4 or 1) * math.min(80, 38 + t * 1.3)
		local col = gold and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(255, 120, 50)
		local p = make("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(d, d, d), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Material = Enum.Material.Neon, Color = col, CFrame = CFrame.new(pos) }, fxFolder)
		make("Part", { Name = "Rock", Shape = Enum.PartType.Ball, Size = Vector3.new(d * 0.8, d * 0.8, d * 0.8), Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Material = Enum.Material.Basalt, Color = Color3.fromRGB(60, 45, 40), CFrame = CFrame.new(pos) }, p)
		local a = make("Attachment", {}, p)
		make("ParticleEmitter", { Color = ColorSequence.new(col, Color3.fromRGB(255, 60, 20)), LightEmission = 1, Rate = 60, Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(1, 3), Size = NumberSequence.new(d * 0.7, 0), Transparency = NumberSequence.new(0.1, 1), LockedToPart = false }, a)
		table.insert(meteors, { p = p, v = (target - pos).Unit * speed, gold = gold, life = 0, d = d })
	end
	local function laserTo(pos)
		local muzzle = barrel and barrel:FindFirstChild("Muzzle")
		local from = muzzle and muzzle.Position or origin
		local len = (pos - from).Magnitude
		local beam = make("Part", { Size = Vector3.new(0.7, 0.7, len), Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon,
			Color = Color3.fromRGB(120, 230, 255), CFrame = CFrame.lookAt((from + pos) / 2, pos) }, fxFolder)
		TweenService:Create(beam, TweenInfo.new(0.18), { Transparency = 1, Size = Vector3.new(0.1, 0.1, len) }):Play()
		task.delay(0.2, function() beam:Destroy() end)
		if barrel then barrel:PivotTo(CFrame.lookAt(origin, pos) * rel) end
		playSfx("laser", 0.95 + math.random() * 0.1)
	end
	local function boom(m, hit)
		local pos = m.p.Position
		FX.burst(pos, m.gold and Color3.fromRGB(255, 230, 120) or Color3.fromRGB(255, 150, 70), hit and 40 or 14)
		if hit then
			local fl = make("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon,
				Color = Color3.fromRGB(255, 240, 200), CFrame = CFrame.new(pos) }, fxFolder)
			TweenService:Create(fl, TweenInfo.new(0.35), { Size = Vector3.new(m.d * 4, m.d * 4, m.d * 4), Transparency = 1 }):Play()
			task.delay(0.4, function() fl:Destroy() end)
		end
		m.p:Destroy()
	end
	-- попадание только по самому метеориту (радиус по его размеру на экране), между выстрелами перезарядка
	local lastShot, misses = 0, 0
	local inputConn = UIS.InputBegan:Connect(function(input)
		if not running then return end
		if input.UserInputType ~= Enum.UserInputType.Touch and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		local nowc = os.clock()
		if nowc - lastShot < 0.32 then return end
		lastShot = nowc
		local vh = cam.ViewportSize.Y
		local tanHalf = math.tan(math.rad(cam.FieldOfView / 2))
		local best, bestD
		for _, m in meteors do
			local sp, onScreen = cam:WorldToScreenPoint(m.p.Position)
			if onScreen and sp.Z > 0 then
				local dd = (Vector2.new(sp.X, sp.Y) - Vector2.new(input.Position.X, input.Position.Y)).Magnitude
				local pxr = (m.d / 2) * (vh / 2) / (sp.Z * tanHalf)
				local rad = math.max(18, pxr * 1.3)
				if dd < rad and (not bestD or dd < bestD) then best, bestD = m, dd end
			end
		end
		local aim
		if best then
			aim = best.p.Position
		else
			local ray = cam:ScreenPointToRay(input.Position.X, input.Position.Y)
			aim = ray.Origin + ray.Direction * 180
		end
		laserTo(aim)
		if not best then
			misses += 1
			if combo >= 3 then FX.floatText(aim, "комбо сброшено", T.red, 18) end
			combo = 0
			hitL.Text = "Сбито: " .. hits .. "  · промахи: " .. misses
		end
		if best then
			table.remove(meteors, table.find(meteors, best))
			local now = os.clock()
			combo = (now - lastHit < 1.2) and combo + 1 or 1
			lastHit = now
			hits += best.gold and 3 or 1
			hitL.Text = "Сбито: " .. hits .. (combo >= 3 and ("  · комбо x" .. combo) or "")
			K.pop(hitL)
			playSfx("boom", 1 + math.min(combo, 10) * 0.04)
			playSfx("tap", 1 + math.min(combo, 10) * 0.08)
			FX.floatText(best.p.Position, best.gold and "+3" or "+1", best.gold and T.gold or T.text, 26)
			boom(best, true)
		end
	end)
	local t0, nextSpawn = os.clock(), 0
	while running do
		local dt = task.wait()
		local t = os.clock() - t0
		if t >= dur then break end
		timeL.Text = ("0:%02d"):format(math.ceil(dur - t))
		if t >= nextSpawn then
			spawnMeteor(t)
			if t > 8 and math.random() < 0.35 then spawnMeteor(t) end
			nextSpawn = t + math.max(0.32, 1.05 - t * 0.025)
		end
		for i = #meteors, 1, -1 do
			local m = meteors[i]
			m.life += dt
			local pos = m.p.Position + m.v * dt
			m.p.CFrame = CFrame.new(pos)
			local rock = m.p:FindFirstChild("Rock")
			if rock then rock.CFrame = CFrame.new(pos) * CFrame.Angles(m.life * 3, m.life * 2, 0) end
			if m.life > 6 or (pos - origin):Dot(out) < 15 then
				table.remove(meteors, i)
				boom(m, false)
			end
		end
		cam.CFrame = CFrame.lookAt(camPos, origin + out * 80 + up * 42) * CFrame.new(math.sin(t * 40) * 0.05 * math.max(0, 1 - (os.clock() - lastHit) * 4), 0, 0)
	end
	running = false
	inputConn:Disconnect()
	for _, m in meteors do m.p:Destroy() end
	if barrel and barrel0 then barrel:PivotTo(barrel0) end
	for _, d in signs do d.Enabled = true end
	close()
	FX.busy = false
	local ok2, err = remotes.CannonEnd:InvokeServer(hits)
	if not ok2 then toast(err or "Раунд не засчитан", "bad") end
end

-- Марс: гонка в пыльной буре. 13 ворот по порядку, ускорители, луч к следующим воротам, время считает сервер
function FX.race()
	if FX.busy then return end
	local track = world:FindFirstChild("RaceTrack", true)
	if not track then return end
	local ok, info = remotes.RaceStart:InvokeServer()
	if not ok then toast(info or "Гонка недоступна", "bad") return end
	FX.busy = true
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not root or not hum then FX.busy = false return end
	local gates = {}
	for i = 1, #G.Race.gates do
		local g = track:FindFirstChild("RaceGate" .. i)
		if g then gates[i] = g end
	end
	local function gatePos(g) return g:GetPivot().Position end
	local pads = {}
	for _, d in track:GetChildren() do if d:IsA("BasePart") and d:GetAttribute("Boost") then table.insert(pads, d) end end
	local gui = make("ScreenGui", { Name = "RaceGui", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 40 }, pg)
	local timeL = K.text(gui, "0.0", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 92), Size = UDim2.fromOffset(240, 44), MaxText = 38 })
	local gateL = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 136), Size = UDim2.fromOffset(320, 24), MaxText = 18, TextColor3 = T.orange })
	local big = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(420, 110), MaxText = 90, TextColor3 = T.gold })
	local quit = K.button(gui, "Сдаться", T.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 92), Size = UDim2.fromOffset(110, 38), MaxText = 16 })
	local running = true
	quit.Activated:Connect(function() running = false end)
	-- буря: рыжий оттенок, пыль вокруг игрока
	local storm = make("ColorCorrectionEffect", { Name = "StormCC", TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }, Lighting)
	TweenService:Create(storm, TweenInfo.new(1.5), { TintColor = Color3.fromRGB(255, 205, 165), Saturation = -0.1, Contrast = 0.05 }):Play()
	local dustA = make("Attachment", { Name = "StormDust", Position = Vector3.new(0, 4, 0) }, root)
	local dust = make("ParticleEmitter", { Color = ColorSequence.new(Color3.fromRGB(214, 140, 96)), LightInfluence = 1, Rate = 70, Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(30, 46), SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Right,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90) }, dustA)
	-- луч к следующим воротам
	local a0 = make("Attachment", { Name = "RaceBeam0", Position = Vector3.new(0, 1, 0) }, root)
	local tgtPart = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1, Size = Vector3.new(0.2, 0.2, 0.2) }, fxFolder)
	local a1 = make("Attachment", {}, tgtPart)
	local beam = make("Beam", { Attachment0 = a0, Attachment1 = a1, Color = ColorSequence.new(Color3.fromRGB(255, 190, 90)), LightEmission = 1, Width0 = 0.5, Width1 = 1.4,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0.2) }), FaceCamera = true, Segments = 1 }, a0)
	local function highlight(i)
		for j, g in gates do
			for _, d in g:GetDescendants() do
				if d:IsA("BasePart") and (d.Name == "GateGlow" or d.Name == "GateTop") then
					d.Color = j == i and Color3.fromRGB(120, 255, 170) or Color3.fromRGB(255, 140, 60)
					d.LocalTransparencyModifier = (j == i) and 0 or 0.5
				end
			end
		end
		if gates[i] then tgtPart.CFrame = CFrame.new(gatePos(gates[i]) + Vector3.new(0, 4, 0)) end
	end
	-- отсчёт
	local ws0 = hum.WalkSpeed
	hum.WalkSpeed = 0
	for n = info.countdown, 1, -1 do
		big.Text = tostring(n)
		K.pop(big)
		playSfx("beep")
		task.wait(1)
	end
	big.Text = "ВПЕРЁД!"
	K.pop(big)
	playSfx("go")
	playSfx("whoosh", 0.8)
	hum.WalkSpeed = ws0
	task.delay(0.8, function() if big.Parent then big.Text = "" end end)
	local nextGate, t0 = 1, os.clock()
	local boostUntil, lastPad = 0, nil
	highlight(1)
	local finished = false
	while running do
		task.wait()
		local t = os.clock() - t0
		if t > G.Race.limit then break end
		timeL.Text = ("%.1f"):format(t)
		timeL.TextColor3 = t <= G.Race.gold and T.gold or (t <= G.Race.silver and Color3.fromRGB(210, 220, 235) or (t <= G.Race.bronze and Color3.fromRGB(225, 150, 95) or T.text))
		gateL.Text = nextGate <= #gates and (nextGate == #gates and "Финиш у арки!" or ("Ворота %d из %d"):format(nextGate, #gates - 1)) or ""
		local g = gates[nextGate]
		if g then
			local gp = gatePos(g)
			local d = root.Position - gp
			if Vector3.new(d.X, 0, d.Z).Magnitude < G.Race.gateRadius and math.abs(d.Y) < 14 then
				nextGate += 1
				playSfx("tap", 0.9 + nextGate * 0.04)
				FX.burst(gp + Vector3.new(0, 4, 0), Color3.fromRGB(120, 255, 170), 30)
				if nextGate > #gates then finished = true break end
				highlight(nextGate)
			end
		end
		-- ускорители
		local now = os.clock()
		for _, pad in pads do
			local lp = pad.CFrame:PointToObjectSpace(root.Position)
			if math.abs(lp.X) < pad.Size.X / 2 + 0.5 and math.abs(lp.Z) < pad.Size.Z / 2 + 0.5 and lp.Y > -1 and lp.Y < 6 and (pad ~= lastPad or now > boostUntil) then
				lastPad = pad
				boostUntil = now + G.Race.boostTime
				hum.WalkSpeed = math.max(ws0, G.Race.boost)
				playSfx("whoosh", 1.2)
				FX.floatText(root.Position + Vector3.new(0, 4, 0), "УСКОРЕНИЕ!", T.orange, 20)
			end
		end
		if now > boostUntil and hum.WalkSpeed ~= ws0 then hum.WalkSpeed = ws0 end
	end
	hum.WalkSpeed = ws0
	local elapsed = os.clock() - t0
	beam:Destroy()
	a0:Destroy()
	tgtPart:Destroy()
	dust.Enabled = false
	task.delay(2, function() dustA:Destroy() end)
	TweenService:Create(storm, TweenInfo.new(1.5), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }):Play()
	task.delay(1.6, function() storm:Destroy() end)
	for _, gg in gates do
		for _, d in gg:GetDescendants() do
			if d:IsA("BasePart") then d.LocalTransparencyModifier = 0 if d.Name == "GateGlow" or d.Name == "GateTop" then d.Color = Color3.fromRGB(255, 140, 60) end end
		end
	end
	local okR, res = remotes.RaceFinish:InvokeServer(info.token, finished and #gates or -1)
	if finished and okR and res then
		local m = G.Medals[res.medal]
		big.Text = ("%.1f с"):format(res.time)
		big.TextColor3 = m.color
		K.pop(big)
		gateL.Text = m.name .. (res.newBest and " · новый рекорд!" or (" · рекорд %.1f с"):format(res.best))
		if res.cooldown then toast(("Награда снова через %d с, время засчитано"):format(math.ceil(res.cooldown)), "info", 4) end
		playSfx(res.medal == 1 and "legendary" or "unlock")
	elseif finished then
		toast(res or "Время не засчитано", "bad")
	else
		toast(elapsed > G.Race.limit and "Время вышло" or "Гонка прервана", "bad")
	end
	task.wait(finished and 3 or 0.5)
	gui:Destroy()
	FX.busy = false
end

-- Ио: рыбалка в лаве. Заброс, поклёвка (успей тапнуть), вываживание: держи палец, чтобы зелёная зона шла вверх
function FX.fishing()
	if FX.busy then return end
	local lakeP = world:FindFirstChild("LakeLava", true)
	local rodP = world:FindFirstChild("RodTip", true)
	if not lakeP or not rodP then return end
	FX.busy = true
	local gui, cam, close = FX.scene("Fishing")
	local lake, rod = lakeP.Position, rodP.Position
	local back = (rod - lake) * Vector3.new(1, 0, 1)
	back = back.Magnitude > 0.1 and back.Unit or Vector3.new(0, 0, 1)
	local camPos = rod + back * 9 + Vector3.new(0, 4, 0)
	cam.FieldOfView = 60
	cam.CFrame = CFrame.lookAt(camPos, lake + Vector3.new(0, 1, 0))
	local title = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(520, 36), MaxText = 28 })
	local sub = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(520, 22), MaxText = 16, TextColor3 = T.sub, Medium = true })
	local exitB = K.button(gui, "Выйти", T.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(110, 40), MaxText = 18 })
	-- полоска вываживания
	local barF = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.55, 0), Size = UDim2.fromOffset(46, 250), BackgroundColor3 = T.panel, BackgroundTransparency = 0.1, Visible = false }, gui)
	K.corner(barF, UDim.new(0, 12))
	K.stroke(barF, T.orange, 1.5, false, 0.2)
	local zone = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 4, 1, -4), Size = UDim2.new(1, -8, 0.3, 0), BackgroundColor3 = T.green, BackgroundTransparency = 0.25 }, barF)
	K.corner(zone, UDim.new(0, 8))
	local fishDot = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(30, 18), BackgroundColor3 = T.orange }, barF)
	K.corner(fishDot, UDim.new(1, 0))
	local progBg = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -96, 0.55, 0), Size = UDim2.fromOffset(12, 250), BackgroundColor3 = T.panel, Visible = false }, gui)
	K.corner(progBg, UDim.new(1, 0))
	local progFill = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.3), BackgroundColor3 = T.gold }, progBg)
	K.corner(progFill, UDim.new(1, 0))
	local running, holding, tapped = true, 0, false
	exitB.Activated:Connect(function() running = false end)
	local c1 = UIS.InputBegan:Connect(function(input, gp)
		if gp then return end
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			holding += 1
			tapped = true
		end
	end)
	local c2 = UIS.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then holding = math.max(0, holding - 1) end
	end)
	local bobber = make("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon,
		Color = Color3.fromRGB(120, 230, 255), Transparency = 1, CFrame = CFrame.new(rod) }, fxFolder)
	make("PointLight", { Color = Color3.fromRGB(120, 230, 255), Range = 8, Brightness = 1.2 }, bobber)
	local line = make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = Color3.fromRGB(230, 230, 240), Transparency = 1, Size = Vector3.new(0.06, 0.06, 1) }, fxFolder)
	local function drawLine(at)
		local len = (at - rod).Magnitude
		line.Size = Vector3.new(0.06, 0.06, len)
		line.CFrame = CFrame.lookAt((rod + at) / 2, at)
		line.Transparency = 0.3
	end
	local function waitFor(sec)
		local t0 = os.clock()
		while running and os.clock() - t0 < sec do task.wait() end
		return running
	end
	local function flyFish(fish)
		local body = make("Part", { Size = Vector3.new(1, 1, 1), Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = fish.color }, fxFolder)
		make("SpecialMesh", { MeshType = Enum.MeshType.Sphere, Scale = Vector3.new(1.4, 1.1, 3) }, body)
		local tail = make("Part", { Size = Vector3.new(0.3, 1.6, 1.4), Anchored = true, CanCollide = false, CanQuery = false, Material = Enum.Material.Neon, Color = fish.color:Lerp(Color3.new(1, 1, 1), 0.25) }, fxFolder)
		local from = bobber.Position
		local to = camPos + (lake - camPos).Unit * 7 + Vector3.new(0, 0.5, 0)
		FX.splash(from, Color3.fromRGB(255, 140, 50), 40, 20)
		playSfx("whoosh", 0.9)
		local t0 = os.clock()
		while os.clock() - t0 < 1.1 do
			local k = (os.clock() - t0) / 1.1
			local e = 1 - (1 - k) ^ 3
			local p = from:Lerp(to, e) + Vector3.new(0, math.sin(k * math.pi) * 6, 0)
			local cf = CFrame.new(p) * CFrame.Angles(0, os.clock() * 6, math.sin(os.clock() * 14) * 0.4)
			body.CFrame = cf
			tail.CFrame = cf * CFrame.new(0, 0, 1.9)
			task.wait()
		end
		FX.burst(to, fish.color, 40)
		task.delay(1.2, function() body:Destroy() tail:Destroy() end)
	end
	local function refreshTitle(bait)
		title.Text = "Тапни, чтобы забросить"
		sub.Text = ("Наживка: %d из %d"):format(bait or (ST.bait and ST.bait.n) or 0, G.Fishing.baitMax)
	end
	refreshTitle()
	while running do
		tapped = false
		while running and not tapped do task.wait() end
		if not running then break end
		local ok, info = remotes.FishCast:InvokeServer()
		if not ok then
			toast(info or "Не получилось", "bad")
			if not waitFor(1) then break end
			continue
		end
		local fish = G.Fish[info.fish]
		-- заброс
		title.Text = "Ждём поклёвку…"
		sub.Text = ("Наживка: %d из %d"):format(info.bait, G.Fishing.baitMax)
		playSfx("whoosh", 1.1)
		local landAt = lake + Vector3.new(math.random(-6, 6), 0.5, math.random(-6, 6))
		bobber.Transparency = 0
		local t0 = os.clock()
		while os.clock() - t0 < 0.6 do
			local k = (os.clock() - t0) / 0.6
			local p = rod:Lerp(landAt, k) + Vector3.new(0, math.sin(k * math.pi) * 5, 0)
			bobber.CFrame = CFrame.new(p)
			drawLine(p)
			task.wait()
		end
		FX.splash(landAt, Color3.fromRGB(255, 150, 60), 14, 8)
		playSfx("water", 0.8)
		-- ожидание: поплавок покачивается
		local w0 = os.clock()
		while running and os.clock() - w0 < info.bite - 0.6 do
			local p = landAt + Vector3.new(0, math.sin(os.clock() * 3) * 0.12, 0)
			bobber.CFrame = CFrame.new(p)
			drawLine(p)
			task.wait()
		end
		if not running then remotes.FishResult:InvokeServer(info.token, false) break end
		-- поклёвка: успей тапнуть
		title.Text = "КЛЮЁТ! ТАПНИ!"
		title.TextColor3 = T.orange
		K.pop(title)
		playSfx("beep", 1.3)
		FX.splash(landAt, Color3.fromRGB(255, 120, 40), 24, 14)
		tapped = false
		local b0 = os.clock()
		local hooked = false
		while running and os.clock() - b0 < 0.9 do
			bobber.CFrame = CFrame.new(landAt - Vector3.new(0, 0.5 + math.sin(os.clock() * 30) * 0.15, 0))
			if tapped then hooked = true break end
			task.wait()
		end
		title.TextColor3 = T.text
		local caught = false
		if hooked then
			-- вываживание
			title.Text = "Держи палец: зелёная зона вверх, отпусти: вниз"
			barF.Visible, progBg.Visible = true, true
			local zp, zv, fp, ftarget, nextT = 0.1, 0, 0.5, 0.5, 0
			local zsize = math.max(0.16, 0.3 - fish.diff * 0.025)
			local prog = 0.3
			local r0 = os.clock()
			local last = os.clock()
			while running and os.clock() - r0 < 25 do
				local now = os.clock()
				local dt = math.min(0.05, now - last)
				last = now
				zv += (holding > 0 and 2.8 or -2.4) * dt
				zv = math.clamp(zv, -1.4, 1.4)
				zp += zv * dt
				if zp < 0 then zp, zv = 0, 0 end
				if zp > 1 - zsize then zp, zv = 1 - zsize, 0 end
				if now >= nextT then
					ftarget = math.random() * 0.9 + 0.05
					nextT = now + (math.random() * 0.8 + 0.4) / (1 + fish.diff * 0.3)
				end
				fp += (ftarget - fp) * math.min(1, dt * (1.2 + fish.diff * 0.7))
				local inside = fp >= zp and fp <= zp + zsize
				prog += (inside and (0.32 - fish.diff * 0.025) or -0.22) * dt
				zone.Position = UDim2.new(0, 4, 1 - zp, -4)
				zone.Size = UDim2.new(1, -8, zsize, 0)
				zone.BackgroundColor3 = inside and T.green or T.cold
				fishDot.Position = UDim2.fromScale(0.5, 1 - fp)
				progFill.Size = UDim2.fromScale(1, math.clamp(prog, 0, 1))
				local p = landAt + Vector3.new(math.sin(now * 5) * 1.2, -0.3, math.cos(now * 4) * 1.2)
				bobber.CFrame = CFrame.new(p)
				drawLine(p)
				if inside and math.random() < 0.08 then playSfx("tap", 0.9 + prog * 0.6) end
				if prog >= 1 then caught = true break end
				if prog <= 0 then break end
				task.wait()
			end
			barF.Visible, progBg.Visible = false, false
		end
		local okR, res = remotes.FishResult:InvokeServer(info.token, caught)
		if caught and okR then
			flyFish(fish)
			if res and res.coins and not res.id then
				toast(("Поймано: %s! +%s монет"):format(fish.name, G.fmt(res.coins)), "rare", 3)
				playSfx("coins")
			end
		else
			toast(hooked and "Рыба сорвалась…" or "Не успел: рыба ушла", "bad", 2)
		end
		bobber.Transparency = 1
		line.Transparency = 1
		if not waitFor(1.2) then break end
		refreshTitle(info.bait)
	end
	c1:Disconnect()
	c2:Disconnect()
	bobber:Destroy()
	line:Destroy()
	close()
	FX.busy = false
end

-- Ядро: телескоп. Камера смотрит на нижние планеты с сильным приближением
function FX.telescope()
	if FX.busy then return end
	local eyeP = world:FindFirstChild("TelescopePrompt", true)
	if not eyeP then return end
	FX.busy = true
	local gui, cam, close = FX.scene("Telescope")
	local eye = eyeP.Position + Vector3.new(0, 2.5, 0)
	-- площадка, телескоп и сам игрок не должны загораживать вид вниз
	local hiddenParts = {}
	local over = eyeP.Parent
	for _, holder in { over, plr.Character } do
		if holder then
			for _, d in holder:GetDescendants() do
				if d:IsA("BasePart") then
					d.LocalTransparencyModifier = 1
					table.insert(hiddenParts, d)
				end
			end
		end
	end
	local hole = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(0.95, 0.95), BackgroundTransparency = 1 }, gui)
	make("UIAspectRatioConstraint", { AspectRatio = 1 }, hole)
	K.corner(hole, UDim.new(0.5, 0))
	make("UIStroke", { Thickness = 900, Color = Color3.new(0, 0, 0), Transparency = 0.02 }, hole)
	local ringF = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, hole)
	K.corner(ringF, UDim.new(0.5, 0))
	make("UIStroke", { Thickness = 3, Color = Color3.fromRGB(236, 196, 100), Transparency = 0.2 }, ringF)
	local nameL = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(420, 40), MaxText = 32 })
	local subL = K.text(gui, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 48), Size = UDim2.fromOffset(460, 24), MaxText = 16, TextColor3 = T.sub, Medium = true })
	local prevB = K.button(gui, "<", T.panel2, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(64, 64), MaxText = 30 })
	local nextB = K.button(gui, ">", T.panel2, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(64, 64), MaxText = 30 })
	local exitB = K.button(gui, "Выйти", T.panel2, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 12), Size = UDim2.fromOffset(110, 40), MaxText = 18 })
	local idx = math.clamp(ST.planet or 1, 1, 5)
	local look = (cam.CFrame.LookVector)
	local fov = 40
	local function target(pi)
		local pf = world:FindFirstChild("Planet" .. pi)
		local hub = pf and pf:FindFirstChild("Hub")
		local base = hub and hub:FindFirstChild("PlazaBase")
		return base and base.Position or eye
	end
	local function show()
		local p = G.Planets[idx]
		nameL.Text = string.upper(p.name)
		nameL.TextColor3 = G.PlanetColors[idx]
		local n = 0
		for _, pl in plotsFolder:GetChildren() do
			if string.sub(pl.Name, 1, 5) == ("Plot" .. idx) and string.sub(pl.Name, 6, 6) == "_" then n += 1 end
		end
		subL.Text = ("огородов: %d · удача x%s%s"):format(n, tostring(G.PlanetLuck[idx]), G.PlanetFeature[idx] ~= "" and (" · " .. G.PlanetFeature[idx]) or "")
		playSfx("whoosh", 1.2 + idx * 0.05)
	end
	show()
	prevB.Activated:Connect(function() idx = (idx - 2) % 5 + 1 show() end)
	nextB.Activated:Connect(function() idx = idx % 5 + 1 show() end)
	local running = true
	exitB.Activated:Connect(function() running = false end)
	local t0 = os.clock()
	while running and gui.Parent do
		local dt = task.wait()
		local tp = target(idx)
		local dist = (tp - eye).Magnitude
		local want = (tp - eye).Unit
		local k = math.min(1, dt * 3)
		look = (look:Lerp(want, k)).Unit
		fov += (math.clamp(math.deg(2 * math.atan(230 / math.max(dist, 1))), 4, 50) - fov) * k
		local t = os.clock() - t0
		cam.FieldOfView = fov
		cam.CFrame = CFrame.lookAt(eye, eye + look + Vector3.new(math.sin(t * 0.7), math.cos(t * 0.5), 0) * 0.0015)
	end
	for _, d in hiddenParts do
		if d.Parent then d.LocalTransparencyModifier = 0 end
	end
	close()
	FX.busy = false
end

-- трамплин «Прыжок в бездну» и таблички с перезарядкой
do
	local pads, cdSigns = {}, {}
	for _, d in world:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("Launch") then table.insert(pads, d) end
		if d:IsA("BillboardGui") and d:GetAttribute("Cooldown") then
			local sub = d:FindFirstChild("Sub")
			if sub then table.insert(cdSigns, { key = d:GetAttribute("Cooldown"), lbl = sub, def = sub.Text }) end
		end
	end
	local lastLaunch = 0
	loop(0.08, function()
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if not root or os.clock() - lastLaunch < 1.5 then return end
		for _, pad in pads do
			local lp = pad.CFrame:PointToObjectSpace(root.Position)
			if math.abs(lp.X) < pad.Size.X / 2 + 0.5 and math.abs(lp.Z) < pad.Size.Z / 2 + 0.5 and lp.Y > 0 and lp.Y < 5 then
				lastLaunch = os.clock()
				root.AssemblyLinearVelocity = pad:GetAttribute("Launch")
				playSfx("whoosh", 0.9)
				playSfx("boom", 1.5)
				FX.burst(pad.Position, Color3.fromRGB(255, 160, 90), 50)
				toast("Прыжок в бездну!", "rare", 3)
			end
		end
	end)
	loop(1, function()
		for _, c in cdSigns do
			local left = math.ceil(((ST.cd or {})[c.key] or 0) - nowS())
			c.lbl.Text = left > 0 and ("перезарядка %d:%02d"):format(left // 60, left % 60) or c.def
		end
	end)
end

------------------------------------------------------------------ анимации мира
local animated = {}
local function rescan()
	table.clear(animated)
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and (d:GetAttribute("Spin") or d:GetAttribute("Drift") or d:GetAttribute("OrbitR")) then table.insert(animated, d) end
		if d:IsA("BasePart") and (d:GetAttribute("Blink") or d:GetAttribute("Pulse")) then table.insert(animated, d) end
	end
end
rescan()
task.spawn(function()
	while true do
		task.wait(5)
		rescan()
	end
end)
RunService.RenderStepped:Connect(function(dt)
	local t = os.clock()
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	for _, o in animated do
		if o:IsA("Model") then
			local spin = o:GetAttribute("Spin")
			local pivot = o:GetAttribute("Pivot")
			local orbitR = o:GetAttribute("OrbitR")
			if orbitR then
				local oc = o:GetAttribute("OrbitCenter")
				if oc and (oc - cp).Magnitude < 1200 then
					local a = o:GetAttribute("OrbitPhase") + t * o:GetAttribute("OrbitSpeed")
					local pos = oc + Vector3.new(math.cos(a) * orbitR, o:GetAttribute("OrbitY") + math.sin(t * 0.4 + a) * 4, math.sin(a) * orbitR)
					o:PivotTo(CFrame.new(pos) * CFrame.Angles(0.25, -a, 0.15) * CFrame.Angles(0, 0, math.pi / 2))
				end
			elseif spin and pivot and (pivot - cp).Magnitude < 150 then
				o:PivotTo(CFrame.new(pivot) * CFrame.Angles(0, spin * dt, 0) * CFrame.new(-pivot) * o:GetPivot())
			elseif o:GetAttribute("Drift") and (o:GetPivot().Position - cp).Magnitude < 700 then
				o:PivotTo(o:GetPivot() * CFrame.Angles(0, o:GetAttribute("Drift") * dt, 0))
			end
		elseif o:GetAttribute("Pulse") then
			o.Transparency = 0.05 + 0.3 * (math.sin(t * 3 + o.Position.X) + 1) / 2
		else
			local b = o:GetAttribute("Blink")
			o.Transparency = (t % b) < b * 0.5 and 0 or 0.75
		end
	end
	for soil, e in cache do
		if e.model and e.kind == "plant" then
			local d = (soil.Position - cp).Magnitude
			if d < 60 then
				PM.animate(e.model, t)
				-- лёгкое покачивание, созревшие ещё и подпрыгивают
				local ph = soil.Position.X * 0.7 + soil.Position.Z
				local bob = e.ready and math.abs(math.sin(t * 2.2 + ph)) * 0.18 or 0
				e.model:PivotTo(CFrame.new(soil.Position + Vector3.new(0, soil.Size.Y / 2 + bob, 0)) * CFrame.Angles(math.sin(t * 1.3 + ph) * 0.035, e.yaw, math.cos(t * 1.1 + ph) * 0.03))
				if e.readyLight then e.readyLight.Brightness = 0.6 + 0.4 * math.sin(t * 3 + ph) end
			end
		end
	end
end)

if plr.Character == nil then plr.CharacterAdded:Wait() end
