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
local sfx = {}
do
	local sfxGroup = make("SoundGroup", { Name = "Sfx", Volume = 0.7 }, SoundService)
	local musicGroup = make("SoundGroup", { Name = "Music", Volume = 0.32 }, SoundService)
	for k, id in Audio.Sfx do
		sfx[k] = make("Sound", { SoundId = id, SoundGroup = sfxGroup, Volume = 0.8 }, SoundService)
	end
	local music = make("Sound", { SoundId = Audio.Music.main, Looped = true, SoundGroup = musicGroup, Volume = 0.8 }, SoundService)
	task.spawn(function()
		task.wait(1)
		if not music.IsLoaded and Audio.Music.fallback then music.SoundId = Audio.Music.fallback end
		music:Play()
	end)
end
local function playSfx(name)
	local s = sfx[name]
	if s then
		s.TimePosition = 0
		s:Play()
	end
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

local toastHolder = make("Frame", { Name = "Toasts", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 84), Size = UDim2.fromOffset(400, 200), ZIndex = 20 }, hud)
listLayout(toastHolder, nil, 4, Enum.HorizontalAlignment.Center)
local function toast(text, kind, dur)
	local col = kind == "ok" and T.green or kind == "bad" and T.red or kind == "rare" and T.gold or T.sub
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
end

-- плашка события и подсказка
do
	local f = K.panel(hud, { Name = "Event", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(230, 46) })
	UI.eventFrame = f
	UI.eventTitle = K.text(f, "", { Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 4), MaxText = 15 })
	UI.eventSub = K.text(f, "", { Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 25), MaxText = 12, TextColor3 = T.sub, Medium = true })
	local hint = K.panel(hud, { Name = "Hint", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -104), Size = UDim2.fromOffset(420, 30) })
	K.stroke(hint, T.gold, 1, false, 0.4)
	UI.hintFrame = hint
	UI.hint = K.text(hint, "", { Size = UDim2.new(1, -16, 1, -8), Position = UDim2.fromOffset(8, 4), MaxText = 15, TextColor3 = T.gold, Medium = true })
end

------------------------------------------------------------------ окна: общий каркас
local windows = {}
local function openWindow(id)
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

------------------------------------------------------------------ окно: сумка и продажа
do
	local f, body = mkWindow("bag", "Сумка урожая", "jar", T.gold, 0.92, 0.84)
	local left = K.scroll(body, { Size = UDim2.new(0.55, -6, 1, -50) })
	listLayout(left, nil, 4)
	local right = K.panel(body, { Position = UDim2.new(0.55, 4, 0, 0), Size = UDim2.new(0.45, -4, 1, -50), BackgroundColor3 = T.panel2 })
	local vpHold = make("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(6, 6), Size = UDim2.new(1, -12, 0.5, 0) }, right)
	local info = K.text(right, "Выбери плод слева", { Position = UDim2.new(0, 6, 0.5, 10), Size = UDim2.new(1, -12, 0, 24), MaxText = 20 })
	local info2 = K.text(right, "", { Position = UDim2.new(0, 6, 0.5, 36), Size = UDim2.new(1, -12, 0, 18), MaxText = 15, TextColor3 = T.sub })
	local info3 = K.text(right, "", { Position = UDim2.new(0, 6, 0.5, 56), Size = UDim2.new(1, -12, 0, 20), MaxText = 18, TextColor3 = T.gold })
	local sellOne = K.button(right, "Продать этот", T.green, { Position = UDim2.new(0, 8, 1, -84), Size = UDim2.new(0.55, -10, 0, 34), MaxText = 16 })
	local favBtn = K.button(right, "Избранное", T.purple, { Position = UDim2.new(0.55, 2, 1, -84), Size = UDim2.new(0.45, -10, 0, 34), MaxText = 15 })
	local sellAll = K.button(body, "Продать всё", T.gold, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, 0), Size = UDim2.new(1, 0, 0, 42), MaxText = 22 })
	UI.bagInfo = K.text(right, "", { Position = UDim2.new(0, 6, 1, -44), Size = UDim2.new(1, -12, 0, 36), MaxText = 15, TextColor3 = T.sub })
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
	local top = K.button(body, "Рекорд недели", T.gold, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(150, 28), MaxText = 15 })
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
		if mode == "top" then
			label(scroll, "Самые тяжёлые плоды этой недели", { Size = UDim2.new(1, 0, 0, 24), TextColor3 = T.gold, MaxText = 18, LayoutOrder = 0 })
			local list = remotes.Top:InvokeServer() or {}
			for i, e in list do row(scroll, i, e.name, "место " .. i, ("%.2f кг"):format(e.kg), T.text, i == 1) end
			if #list == 0 then label(scroll, "Пока никто не собрал плоды на этой неделе", { Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 }) end
			return
		end
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
	top.Activated:Connect(function()
		mode = mode == "top" and "market" or "top"
		hooks.market()
	end)
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
			local cost = G.upgradeCost(key, level)
			local r = K.panel(scroll, { Size = UDim2.new(1, -8, 0, 56), LayoutOrder = i, BackgroundColor3 = T.panel2 })
			K.icon(r, u.icon, { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 6) })
			K.text(r, u.name, { Position = UDim2.fromOffset(56, 3), Size = UDim2.new(0.45, 0, 0, 22), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Left })
			local cur = G.upgradeValue(key, level)
			local curText = (u.off and level <= u.min) and u.off or u.fmt:format(cur)
			K.text(r, u.desc .. ". Сейчас: " .. curText, { Position = UDim2.fromOffset(56, 26), Size = UDim2.new(0.55, 0, 0, 26), MaxText = 12, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = T.sub })
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
		header("Особые предложения", 40, T.pink)
		for i, key in G.ProductOrder do
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

------------------------------------------------------------------ админ-панель (только владелец)
if plr.UserId == ADMIN_ID then
	local f, body = mkWindow("admin", "Админ", "admin", T.red, 0.5, 0.7)
	listLayout(body, nil, 6)
	local function btn(text, fn)
		local b = K.button(body, text, T.blue, { Size = UDim2.new(1, 0, 0, 36), MaxText = 18 })
		b.Activated:Connect(fn)
	end
	btn("+1 000 000 монет", function() remotes.Admin:InvokeServer("coins") end)
	btn("Открыть все планеты", function() remotes.Admin:InvokeServer("planets") end)
	btn("Все семена x3", function() remotes.Admin:InvokeServer("seeds") end)
	btn("Все растения созрели", function() remotes.Admin:InvokeServer("ripe") end)
	local mi = 1
	local mb
	mb = K.button(body, "Мутация на след. посадку: " .. G.Mut[G.MutOrder[1]].name, T.purple, { Size = UDim2.new(1, 0, 0, 36), MaxText = 16 })
	mb.Activated:Connect(function()
		remotes.Admin:InvokeServer("mut", G.MutOrder[mi])
		toast("След. посадка: " .. G.Mut[G.MutOrder[mi]].name, "ok")
		mi = mi % #G.MutOrder + 1
	end)
end

------------------------------------------------------------------ левая колонка кнопок и панель семян
do
	local col = make("Frame", { Name = "Buttons", BackgroundTransparency = 1, Position = UDim2.new(0, 10, 0, 58), Size = UDim2.fromOffset(56, 420) }, hud)
	listLayout(col, nil, 5)
	local defs = {
		{ "shop", "shop", "Семена", T.green }, { "bag", "jar", "Сумка", T.gold }, { "index", "atlas", "Атлас", T.purple },
		{ "market", "news", "Рынок", T.pink }, { "upgrades", "upgrade", "Мастерская", T.cold }, { "daily", "gift", "Подарок", T.orange },
	}
	if plr.UserId == ADMIN_ID then table.insert(defs, { "admin", "admin", "Админ", T.red }) end
	UI.buttons = {}
	for i, d in defs do
		local b = K.iconButton(col, d[2], d[3], d[4], 48)
		b.LayoutOrder = i
		b.Activated:Connect(function() openWindow(d[1]) end)
		UI.buttons[d[1]] = b
	end
	-- панель семян
	local bar = make("Frame", { Name = "Seeds", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(470, 80), BackgroundTransparency = 1 }, hud)
	local scroll = make("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.X,
		ScrollingDirection = Enum.ScrollingDirection.X, ScrollBarThickness = 4 }, bar)
	listLayout(scroll, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center)
	UI.seedBar = scroll
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
	if not ST.plot then return "Все участки заняты. Подожди, когда один освободится" end
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
		UI.coins.Text = G.fmt(ST.coins)
		local frac, txt = nextPlanetInfo()
		UI.planetFill.Size = UDim2.fromScale(frac, 1)
		UI.planetText.Text = txt
		local t = nowS()
		local ev, left, active = G.eventAt(t)
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
		UI.hint.Text = h
		UI.hintFrame.Visible = h ~= ""
		UI.shopTimer.Text = "Обновление ассортимента через " .. G.fmtTime(G.shopTimeLeft(t))
		UI.buttons.daily:FindFirstChild("Badge").Visible = ST.daily.can
		-- обновления окон
		if dirty.seeds or dirty.sel then hooks.seedbar() end
		if dirty.q or not UI.questsInit then UI.questsInit = true hooks.quests() end
		if windows.bag.Visible and (dirty.fruits or dirty.coins) then hooks.bag() end
		if windows.shop.Visible and (dirty.sold or dirty.bought or dirty.planets) then hooks.shop() end
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
local SHOW_DIST = 80

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
	local bb = make("BillboardGui", { Name = "Tag", Size = UDim2.fromOffset(210, 54), StudsOffset = Vector3.new(0, 6.2, 0), AlwaysOnTop = false, MaxDistance = 60 }, root)
	K.text(bb, text, { Size = UDim2.new(1, 0, 0.55, 0), MaxText = 24, TextColor3 = color })
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
		m:PivotTo(CFrame.new(soil.Position + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, yaw, 0))
		m.Parent = fxFolder
		e = { model = m, key = key, kind = kind, yaw = yaw, ready = false }
		cache[soil] = e
	end
	local s = kind == "sprout" and (0.55 + 0.45 * prog / 0.15) or (0.3 + 0.7 * ((prog - 0.15) / 0.85) ^ 0.7)
	if math.abs((e.scale or 0) - s) > 0.01 then
		e.scale = s
		e.model:ScaleTo(s)
	end
	-- таймер роста над своими растениями
	if not ready and soil:GetAttribute("Plot") == ST.plot then
		if not e.timer then
			local root = e.model.PrimaryPart
			if root then
				local bb = make("BillboardGui", { Name = "Timer", Size = UDim2.fromOffset(110, 34), StudsOffset = Vector3.new(0, 4.2, 0), MaxDistance = 45, LightInfluence = 0 }, root)
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
		local tag = addLabel(e.model, ("%s %.2f кг"):format(plant.name, kg), rar and G.Mut[rar].color or rarityColor(id))
		e.tag = tag
	elseif not ready and e.ready then
		e.ready = false
		if e.tag then e.tag:Destroy() end
	end
end

-- удалённые от камеры модели не держим
loop(0.4, function()
	local cam = workspace.CurrentCamera
	local cp = cam and cam.CFrame.Position or Vector3.zero
	for _, plot in plotsFolder:GetChildren() do
		local beds = plot:FindFirstChild("Beds")
		local center = plot:GetAttribute("Center")
		if beds and center then
			local near = (center - cp).Magnitude < SHOW_DIST + 30
			for _, bed in beds:GetChildren() do
				local soil = bed:FindFirstChild("Soil")
				if soil then
					if near and (soil.Position - cp).Magnitude < SHOW_DIST then refreshEntry(soil) else dropEntry(soil) end
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
			pr.Triggered:Connect(function() remotes.Act:FireServer(idx) end)
			prompts[soil] = pr
		end
	end
end
loop(0.4, function()
	do
		ensurePrompts()
		for soil, pr in prompts do
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
					if waitW > 0 then
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
remotes:WaitForChild("Harvest").OnClientEvent:Connect(function(bedIdx, id, muts, kg)
	local plot = ST.plot and plotsFolder:FindFirstChild("Plot" .. ST.plot)
	local bedsF = plot and plot:FindFirstChild("Beds")
	local bed = bedsF and bedsF:FindFirstChild("Bed" .. tostring(bedIdx))
	if bed and bed:FindFirstChild("Soil") then
		local rar = G.rarestMut(muts or {})
		burst(bed.Soil.Position + Vector3.new(0, 3, 0), rar and G.Mut[rar].color or rarityColor(id), 24 + (rar and 20 or 0))
	end
	local name = plantName(id)
	local title = G.mutTitle(muts or {})
	toast(("%s%s, %.2f кг"):format(title ~= "" and (title .. " ") or "", name, kg or 0), title ~= "" and "rare" or "ok")
	playSfx(title ~= "" and "harvestRare" or "harvest")
end)
remotes:WaitForChild("Announce").OnClientEvent:Connect(function(who, plant, title, chance)
	toast(("%s нашёл «%s %s» (%s)!"):format(who, title, plant, G.fmtOdds(chance)), "rare", 7)
end)

------------------------------------------------------------------ падающие звёзды: покачивание и сбор
remotes:WaitForChild("Collected").OnClientEvent:Connect(function(coins, seed, pos, meteor)
	local text = (meteor and "Метеорит! +" or "Звезда: +") .. G.fmt(coins) .. " монет"
	if seed then text ..= ", семя «" .. plantName(seed) .. "»" end
	toast(text, (meteor or seed) and "rare" or "ok", 3)
	playSfx(meteor and "harvestRare" or "coins")
	if typeof(pos) == "Vector3" then burst(pos, meteor and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 232, 160), meteor and 40 or 18) end
end)
RunService.RenderStepped:Connect(function()
	local starF = world:FindFirstChild("Stars")
	if not starF then return end
	local t = os.clock()
	for _, m in starF:GetChildren() do
		local core = m:FindFirstChild("Core")
		if core then
			local base = m:GetAttribute("BaseY")
			if not base then
				base = core.Position.Y
				m:SetAttribute("BaseY", base)
			end
			local p = core.Position
			core.CFrame = CFrame.new(p.X, base + math.sin(t * 2 + p.X) * 0.35, p.Z) * CFrame.Angles(0, t * 1.5, 0.3)
		end
	end
end)

------------------------------------------------------------------ показ редких мутаций (кинематика)
local revealQueue, revealing = {}, false
local function playReveal(info)
	local rarest = G.rarestMut(info.m)
	local mt = G.Mut[rarest]
	local col = mt.color
	playSfx(mt.tier >= 5 and "legendary" or "reveal")
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
	local head = K.text(back, "МУТАЦИЯ!", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.04), Size = UDim2.fromOffset(500, 56), MaxText = 52, TextColor3 = col })
	local title = G.mutTitle(info.m)
	K.text(back, title .. " " .. plantName(info.id), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.74), Size = UDim2.fromOffset(640, 40), MaxText = 34, TextColor3 = T.text })
	K.text(back, "Шанс " .. G.fmtOdds(info.chance) .. ", вес " .. ("%.2f"):format(info.w) .. " кг", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.82), Size = UDim2.fromOffset(560, 30), MaxText = 24, TextColor3 = T.gold })
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

------------------------------------------------------------------ анимации мира
local animated = {}
local function rescan()
	table.clear(animated)
	for _, d in world:GetDescendants() do
		if d:IsA("Model") and (d:GetAttribute("Spin") or d:GetAttribute("Drift")) then table.insert(animated, d) end
		if d:IsA("BasePart") and d:GetAttribute("Blink") then table.insert(animated, d) end
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
			if spin and pivot and (pivot - cp).Magnitude < 150 then
				o:PivotTo(CFrame.new(pivot) * CFrame.Angles(0, spin * dt, 0) * CFrame.new(-pivot) * o:GetPivot())
			elseif o:GetAttribute("Drift") and (o:GetPivot().Position - cp).Magnitude < 700 then
				o:PivotTo(o:GetPivot() * CFrame.Angles(0, o:GetAttribute("Drift") * dt, 0))
			end
		else
			local b = o:GetAttribute("Blink")
			o.Transparency = (t % b) < b * 0.5 and 0 or 0.75
		end
	end
	for soil, e in cache do
		if e.model and e.kind == "plant" then
			if (soil.Position - cp).Magnitude < 60 then PM.animate(e.model, t) end
			if e.ready then
				e.model:PivotTo(CFrame.new(soil.Position + Vector3.new(0, 0.1 + math.sin(t * 2 + soil.Position.X) * 0.06, 0)) * CFrame.Angles(0, e.yaw, 0))
			end
		end
	end
end)

if plr.Character == nil then plr.CharacterAdded:Wait() end
