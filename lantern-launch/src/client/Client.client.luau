-- «Запусти фонарик»: клиент. Интерфейс, полоска силы, полёт фонарика, раскрытие духа, магазин и коллекция.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local MarketplaceService = game:GetService("MarketplaceService")

local plr = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Game = require(Shared:WaitForChild("Game"))
local Spirits = require(Shared:WaitForChild("Spirits"))
local Audio = require(Shared:WaitForChild("Config"):WaitForChild("Audio"))
local K = require(script.Parent:WaitForChild("UIKit"))
local T = K.T
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local RANK = {}
for i, k in Game.RarityOrder do RANK[k] = i end

local state = {
	coins = 0, record = 0, total = 0, lv = { power = 1, luck = 1, coins = 1, speed = 1, multi = 1, auto = 1 }, inv = {}, variants = {},
	auto = false, autoPeriod = 0, dailyReady = false, luck = 1, coinMult = 1, cooldown = 2.2, seen = 0, owned = {}, milestones = {},
}

------------------------------------------------------------------ звук
local play
do
	local sfxGroup = K.make("SoundGroup", { Name = "Sfx", Volume = 0.7 }, SoundService)
	local musicGroup = K.make("SoundGroup", { Name = "Music", Volume = 0.45 }, SoundService)
	local function sound(id, group, loop)
		if not id or id == "" then return nil end
		local s = K.make("Sound", { SoundId = id, Looped = loop or false, SoundGroup = group, Volume = 0.8 }, SoundService)
		return s
	end
	local cache = {}
	for k, id in Audio.Sfx do cache[k] = sound(id, sfxGroup) end
	play = function(name)
		local s = cache[name]
		if s then s:Play() end
	end
	K.onClick(function() play("click") end)
	task.spawn(function()
		local m = sound(Audio.Music.lantern, musicGroup, true)
		if not m then return end
		task.wait(2.5)
		if not m.IsLoaded and Audio.Music.fallback then m.SoundId = Audio.Music.fallback task.wait(1) end
		m:Play()
	end)
end

------------------------------------------------------------------ корень интерфейса
local gui, hud
do
	gui = K.make("ScreenGui", { Name = "LaunchHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, plr:WaitForChild("PlayerGui"))
	local scale = K.make("UIScale", {}, gui)
	local function rescale()
		local cam = workspace.CurrentCamera
		if cam then scale.Scale = math.clamp(cam.ViewportSize.Y / 420, 0.72, 1.3) end
	end
	rescale()
	if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale) end
	hud = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)
end

local showToast
do
	local toast = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(460, 40), BackgroundColor3 = T.panel, Visible = false, ZIndex = 20 }, hud)
	K.corner(toast, UDim.new(0, 12))
	K.stroke(toast, T.ink, 3)
	local lbl = K.text(toast, "", { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxText = 18, Font = Enum.Font.GothamBold, ZIndex = 20 })
	local seq = 0
	showToast = function(text, secs, color)
		seq += 1
		local my = seq
		lbl.Text = text
		toast.BackgroundColor3 = color or T.panel
		toast.Visible = true
		K.pop(toast)
		task.delay(secs or 2.6, function()
			if seq == my then toast.Visible = false end
		end)
	end
end

------------------------------------------------------------------ верх: монеты, удача, зона, рекорд
local coinL, luckL, zoneL, recordL, zoneFill
do
	local right = K.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(170, 100), BackgroundTransparency = 1 }, hud)
	K.make("UIListLayout", { Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right }, right)
	local cp
	cp, coinL = K.pill(right, "coin", Color3.fromRGB(230, 170, 30), 170)
	local lp
	lp, luckL = K.pill(right, "luck", Color3.fromRGB(70, 190, 110), 150)
	-- зона и рекорд по центру сверху
	local top = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14), Size = UDim2.fromOffset(300, 74), BackgroundTransparency = 1 }, hud)
	zoneL = K.text(top, "Луг зари", { Size = UDim2.new(1, 0, 0, 30), MaxText = 24, StrokeThickness = 3 })
	recordL = K.text(top, "Рекорд 0 м", { Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 32), MaxText = 17, Font = Enum.Font.GothamBold, TextColor3 = T.sub })
	local bar
	bar, zoneFill = K.bar(top, T.gold, { Size = UDim2.new(0.8, 0, 0, 10), Position = UDim2.new(0.1, 0, 0, 58) })
end

------------------------------------------------------------------ кнопки слева
local btnShop, btnIndex, btnGift, btnAdmin
do
	local col = K.make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 20), Size = UDim2.fromOffset(70, 240), BackgroundTransparency = 1 }, hud)
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, col)
	btnShop = K.iconButton(col, "shop", "Улучшения", T.red)
	btnIndex = K.iconButton(col, "atlas", "Духи", T.blue)
	btnGift = K.iconButton(col, "gift", "Подарок", T.green)
	btnAdmin = K.iconButton(col, "admin", "Админ", Color3.fromRGB(230, 160, 30))
	btnShop.LayoutOrder, btnIndex.LayoutOrder, btnGift.LayoutOrder, btnAdmin.LayoutOrder = 1, 2, 3, 4
	btnAdmin.Visible = false
end

------------------------------------------------------------------ окна: улучшения, духи, подарок, админ
local shopW, indexW, giftW, adminW, allWindows
local refreshShop, refreshIndex, refreshGift
local function toggleWindow(w, refresh)
	local willOpen = not w.Visible
	for _, x in allWindows do K.close(x) end
	if willOpen then
		if refresh then refresh() end
		K.open(w)
	end
end

do -- улучшения и донаты
	local body
	shopW, body = K.window(gui, "Улучшения", "shop", T.red, 0.8, 0.82)
	local tabs = K.make("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1 }, body)
	K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, tabs)
	local tabUp = K.button(tabs, "Улучшения", T.red, { Size = UDim2.fromOffset(160, 36), MaxText = 17 })
	local tabDon = K.button(tabs, "Донат", T.gold, { Size = UDim2.fromOffset(130, 36), MaxText = 17 })
	local upList = K.scroll(body, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44) })
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, upList)
	local donList = K.scroll(body, { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), Visible = false })
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, donList)
	local function page(showUp)
		upList.Visible, donList.Visible = showUp, not showUp
		K.recolor(tabUp, showUp and T.red or T.panel2)
		K.recolor(tabDon, showUp and T.panel2 or T.gold)
	end
	tabUp.Activated:Connect(function() page(true) end)
	tabDon.Activated:Connect(function() page(false) end)
	page(true)

	local rows = {}
	for i, key in Game.UpgradeOrder do
		local u = Game.Upgrades[key]
		local f = K.panel(upList, { Size = UDim2.new(1, -10, 0, 84), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.icon(f, u.icon, { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(8, 14) })
		local title = K.text(f, "", { Size = UDim2.new(0.6, -76, 0, 26), Position = UDim2.fromOffset(70, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19 })
		K.text(f, u.desc, { Size = UDim2.new(0.6, -76, 0, 38), Position = UDim2.fromOffset(70, 36), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(225, 228, 245), TextWrapped = true, StrokeThickness = 1 })
		local b, bl = K.button(f, "", T.green, { Size = UDim2.new(0.36, 0, 0, 52), Position = UDim2.new(0.62, 0, 0, 16), MaxText = 17 })
		b.Activated:Connect(function()
			local r = remotes.Upgrade:InvokeServer(key)
			if r and r.ok then
				play("save")
				showToast(u.name .. ": уровень выше!", 2, Color3.fromRGB(40, 120, 70))
			elseif r and r.msg then
				showToast(r.msg, 2.5)
			end
		end)
		rows[key] = { title = title, b = b, l = bl }
	end
	local function fmt(u, v)
		if u.off and v <= 0 then return u.off end
		return u.fmt:format(v)
	end
	-- донаты
	local donRows = {}
	for i, key in Game.ProductOrder do
		local p = Game.Products[key]
		local f = K.panel(donList, { Size = UDim2.new(1, -10, 0, 80), LayoutOrder = i, BackgroundColor3 = Color3.fromRGB(70, 56, 30) })
		K.text(f, p.name, { Size = UDim2.new(0.6, -20, 0, 26), Position = UDim2.fromOffset(12, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19, TextColor3 = T.gold })
		K.text(f, p.desc, { Size = UDim2.new(0.6, -20, 0, 34), Position = UDim2.fromOffset(12, 36), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14, Font = Enum.Font.GothamBold,
			TextColor3 = Color3.fromRGB(225, 228, 245), TextWrapped = true, StrokeThickness = 1 })
		local b, bl = K.button(f, ("%d R$"):format(p.price), T.gold, { Size = UDim2.new(0.34, 0, 0, 50), Position = UDim2.new(0.64, 0, 0, 15), MaxText = 18 })
		b.Activated:Connect(function()
			if p.id ~= 0 then pcall(function() MarketplaceService:PromptProductPurchase(plr, p.id) end) end
		end)
		donRows[key] = { f = f, l = bl }
	end
	refreshShop = function()
		for key, r in rows do
			local u = Game.Upgrades[key]
			local lvl = state.lv[key] or 1
			local cost = Game.upgradeCost(key, lvl)
			if cost then
				r.title.Text = ("%s: %s > %s"):format(u.name, fmt(u, Game.upgradeValue(key, lvl)), fmt(u, Game.upgradeValue(key, lvl + 1)))
				r.l.Text = ("%d"):format(cost)
				K.recolor(r.b, state.coins >= cost and T.green or Color3.fromRGB(90, 90, 105))
			else
				r.title.Text = ("%s: %s (макс.)"):format(u.name, fmt(u, Game.upgradeValue(key, lvl)))
				r.l.Text = "Максимум"
				K.recolor(r.b, Color3.fromRGB(80, 80, 95))
			end
		end
		local any = false
		for key, r in donRows do
			local p = Game.Products[key]
			r.f.Visible = p.id ~= 0
			if p.id ~= 0 then any = true end
			if p.permanent and state.owned[key] then r.l.Text = "Куплено" end
		end
		tabDon.Visible = any
	end
end

do -- коллекция духов
	local body
	indexW, body = K.window(gui, "Коллекция духов", "atlas", T.blue, 0.86, 0.86)
	local head = K.text(body, "", { Size = UDim2.new(0.5, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19 })
	local _, headFill = K.bar(body, T.gold, { Size = UDim2.new(0.5, 0, 0, 12), Position = UDim2.fromOffset(0, 28) })
	local hint = K.text(body, "Цвет кружков: какие разновидности уже находил", { Size = UDim2.new(0.5, -10, 0, 40), Position = UDim2.new(0.5, 10, 0, 0), MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextWrapped = true, StrokeThickness = 1 })
	local grid = K.scroll(body, { Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 1, -48) })
	K.make("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, 180), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	local cards = {}
	local function silhouette(m)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Color, p.Material = Color3.fromRGB(20, 18, 30), Enum.Material.SmoothPlastic
			elseif p:IsA("Light") or p:IsA("Trail") or p:IsA("ParticleEmitter") then
				p.Enabled = false
			end
		end
	end
	for i, kind in Game.PoolOrder do
		local info = Game.Kinds[kind]
		local rar = Game.Rarity[info.rarity]
		local f = K.panel(grid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
		f:FindFirstChildOfClass("UIStroke").Color = rar.color
		local holder = K.make("Frame", { Size = UDim2.new(1, -8, 0, 100), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1) }, f)
		K.corner(holder, UDim.new(0, 10))
		K.gradient(holder, K.darken(rar.color, 0.4), K.darken(rar.color, 0.8))
		local name = K.text(f, "???", { Size = UDim2.new(1, -10, 0, 26), Position = UDim2.fromOffset(5, 108), MaxText = 17, TextWrapped = true })
		local sub = K.text(f, rar.name, { Size = UDim2.new(1, -10, 0, 16), Position = UDim2.fromOffset(5, 134), MaxText = 13, TextColor3 = rar.color, Font = Enum.Font.GothamBold, StrokeThickness = 1 })
		local dots = K.make("Frame", { Size = UDim2.new(1, -12, 0, 14), Position = UDim2.fromOffset(8, 156), BackgroundTransparency = 1 }, f)
		K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center }, dots)
		local dotList = {}
		for _, vk in Game.VariantOrder do
			local d = K.make("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = T.ink }, dots)
			K.corner(d, UDim.new(1, 0))
			K.stroke(d, Color3.fromRGB(120, 120, 150), 1)
			dotList[vk] = d
		end
		cards[kind] = { holder = holder, name = name, sub = sub, dots = dotList, known = nil }
	end
	refreshIndex = function()
		head.Text = ("Собрано %d/%d видов"):format(state.seen, Game.PoolSize)
		headFill.Size = UDim2.fromScale(math.clamp(state.seen / Game.PoolSize, 0, 1), 1)
		for kind, c in cards do
			local got = state.variants[kind] or {}
			local known = next(got) ~= nil
			if c.known ~= known then
				c.known = known
				if c.vp then c.vp:Destroy() end
				local m = Spirits.Builders[kind]()
				if not known then silhouette(m) end
				c.vp = K.viewport(c.holder, m)
			end
			c.name.Text = known and Game.Kinds[kind].name or "???"
			c.name.TextColor3 = known and T.text or T.sub
			local n = 0
			for vk, d in c.dots do
				d.BackgroundColor3 = got[vk] and Game.Variants[vk].color or T.ink
				if got[vk] then n += 1 end
			end
			c.sub.Text = Game.Rarity[Game.Kinds[kind].rarity].name .. (known and ("  " .. n .. "/" .. #Game.VariantOrder) or "")
		end
	end
end

do -- подарок и коды
	local body
	giftW, body = K.window(gui, "Подарок и коды", "gift", T.green, 0.6, 0.7)
	local info = K.text(body, "", { Size = UDim2.new(1, 0, 0, 56), MaxText = 19, Font = Enum.Font.GothamBold, TextWrapped = true })
	local claim, claimL = K.button(body, "Забрать", T.green, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 66), Size = UDim2.fromOffset(260, 54), MaxText = 21 })
	claim.Activated:Connect(function()
		local r = remotes.ClaimDaily:InvokeServer()
		if r and r.ok then
			play("legendary")
			showToast(("Подарок %d дня: +%d монет и удача x2 на 10 минут"):format(r.streak, r.coins), 3.5, Color3.fromRGB(40, 120, 70))
		elseif r and r.msg then
			showToast(r.msg)
		end
	end)
	local box = K.make("TextBox", { Position = UDim2.new(0, 0, 0, 142), Size = UDim2.new(0.62, -8, 0, 46), BackgroundColor3 = T.ink, Text = "", PlaceholderText = "Введи код",
		TextColor3 = T.text, PlaceholderColor3 = T.sub, Font = Enum.Font.GothamBold, TextScaled = true, ClearTextOnFocus = false }, body)
	K.corner(box, UDim.new(0, 10))
	K.make("UITextSizeConstraint", { MaxTextSize = 20 }, box)
	local act = K.button(body, "Активировать", T.pink, { Position = UDim2.new(0.62, 0, 0, 142), Size = UDim2.new(0.38, 0, 0, 46), MaxText = 16 })
	act.Activated:Connect(function()
		local r = remotes.Redeem:InvokeServer(box.Text)
		if r and r.msg then showToast(r.msg, 3, r.ok and Color3.fromRGB(40, 120, 70) or nil) end
		if r and r.ok then box.Text = "" end
	end)
	K.text(body, "Серия подарков: чем больше дней подряд, тем больше монет", { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 200), MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextWrapped = true, StrokeThickness = 1 })
	refreshGift = function()
		local s = state.daily or { streak = 0 }
		info.Text = state.dailyReady and ("Подарок готов! Серия: %d дн."):format(s.streak or 0) or ("Подарок получен. Серия: %d дн. Завтра будет больше"):format(s.streak or 0)
		claimL.Text = state.dailyReady and "Забрать" or "Завтра"
		K.recolor(claim, state.dailyReady and T.green or Color3.fromRGB(80, 80, 95))
	end
end

do -- админка (только владелец)
	local body
	adminW, body = K.window(gui, "Админка", "admin", Color3.fromRGB(230, 160, 30), 0.6, 0.7)
	local grid = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, body)
	K.make("UIGridLayout", { CellSize = UDim2.new(0.5, -8, 0, 54), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i, b in { { "+100000 монет", "coins" }, { "Макс. сила", "maxPower" }, { "Все улучшения", "allUpgrades" }, { "Идеальный запуск", "perfect" }, { "Витрина (3 запуска)", "showcase" } } do
		local btn = K.button(grid, b[1], T.orange, { LayoutOrder = i, MaxText = 16 })
		btn.Activated:Connect(function()
			local r = remotes.Admin:InvokeServer(b[2])
			if r and r.msg then showToast(r.msg) end
		end)
	end
end
allWindows = { shopW, indexW, giftW, adminW }
btnShop.Activated:Connect(function() toggleWindow(shopW, refreshShop) end)
btnIndex.Activated:Connect(function() toggleWindow(indexW, refreshIndex) end)
btnGift.Activated:Connect(function() toggleWindow(giftW, refreshGift) end)
btnAdmin.Activated:Connect(function() toggleWindow(adminW) end)

------------------------------------------------------------------ эффекты
local function ring(pos, from, to, color, secs)
	local r = K.make("Part", { Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false, Material = Enum.Material.Neon,
		Color = color, Transparency = 0.15, Size = Vector3.new(0.2, from, from), CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)) }, workspace)
	TweenService:Create(r, TweenInfo.new(secs, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, to, to), Transparency = 1 }):Play()
	task.delay(secs + 0.05, function() r:Destroy() end)
end
local function burst(pos, color, n)
	local a = K.make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one, Position = pos }, workspace)
	local pe = K.make("ParticleEmitter", { Texture = "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(color, Color3.new(1, 1, 1)), LightEmission = 1,
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(10, 26), SpreadAngle = Vector2.new(180, 180), Rate = 0, Size = NumberSequence.new(1.6, 0) }, a)
	pe:Emit(n)
	task.delay(1.5, function() a:Destroy() end)
end

local flash = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, ZIndex = 40, Active = false }, gui)
local banner = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34), Size = UDim2.fromOffset(500, 120), BackgroundTransparency = 1, Visible = false, ZIndex = 41 }, gui)
local bannerTop = K.text(banner, "", { Size = UDim2.new(1, 0, 0, 64), MaxText = 58, ZIndex = 41, StrokeThickness = 4 })
local bannerSub = K.text(banner, "", { Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 66), MaxText = 28, ZIndex = 41, StrokeThickness = 3 })
local bannerSeq = 0
local WORD = { common = "Пойман", uncommon = "Необычный!", rare = "РЕДКИЙ!", epic = "ЭПИЧЕСКИЙ!", legendary = "ЛЕГЕНДАРНЫЙ!", mythic = "МИФИЧЕСКИЙ!", secret = "СЕКРЕТНЫЙ!" }

-- кинематографичное раскрытие для легендарных и реже: дух крупно, лучи, вспышка
local cine = K.make("TextButton", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(5, 4, 12), BackgroundTransparency = 1, Text = "", AutoButtonColor = false, Visible = false, ZIndex = 60 }, gui)
local cineVp = K.make("ViewportFrame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.62, 0.62), BackgroundTransparency = 1,
	Ambient = Color3.fromRGB(190, 190, 210), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -1, -1), ZIndex = 61 }, cine)
K.make("UIAspectRatioConstraint", { AspectRatio = 1 }, cineVp)
local cineCam = K.make("Camera", { FieldOfView = 30 }, cineVp)
cineVp.CurrentCamera = cineCam
local cineRays = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(10, 10), BackgroundTransparency = 1, ZIndex = 60 }, cine)
local rayList = {}
for i = 1, 10 do
	local r = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 520), Rotation = i * 36, BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.6, BorderSizePixel = 0, ZIndex = 60 }, cineRays)
	K.make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0, 1) }, r)
	rayList[i] = r
end
local cineTop = K.text(cine, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.72), Size = UDim2.new(0.9, 0, 0, 60), MaxText = 58, ZIndex = 62, StrokeThickness = 4 })
local cineSub = K.text(cine, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.72, 62), Size = UDim2.new(0.9, 0, 0, 34), MaxText = 30, ZIndex = 62, StrokeThickness = 3 })
local cineHint = K.text(cine, "коснись, чтобы продолжить", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(360, 22), MaxText = 15, ZIndex = 62,
	Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
local cineConn, cineBusy, cineT0 = nil, false, 0
local function cineClose()
	if cineConn then cineConn:Disconnect() cineConn = nil end
	for _, c in cineVp:GetChildren() do
		if not c:IsA("Camera") then c:Destroy() end
	end
	cine.Visible = false
	cineBusy = false
end
cine.Activated:Connect(function()
	if os.clock() - cineT0 > 1.2 then cineClose() end
end)
local function cinematic(r)
	if cineBusy then return false end
	local info = Game.Kinds[r.kind]
	local special = r.variant ~= "normal"
	local col = special and Game.Variants[r.variant].color or Game.Rarity[info.rarity].color
	local m = Spirits.Builders[r.kind]()
	pcall(Spirits.applyVariant, m, special and r.variant or nil)
	m.Parent = cineVp
	local cf, size = m:GetBoundingBox()
	local rad = math.max(size.X, size.Y, size.Z)
	local center = cf.Position
	local rel = CFrame.new(center):Inverse() * m:GetPivot()
	cineCam.CFrame = CFrame.lookAt(center + Vector3.new(0, rad * 0.15, -rad / math.tan(math.rad(15)) * 0.75), center)
	for _, ray in rayList do ray.BackgroundColor3 = col end
	cineBusy, cineT0 = true, os.clock()
	cineTop.Text = WORD[info.rarity] or (special and (Game.Variants[r.variant].name:upper() .. "!") or "РЕДКИЙ!")
	cineTop.TextColor3 = col
	cineSub.Text = (special and (Game.Variants[r.variant].name .. " ") or "") .. info.name .. ((r.odds > 1) and ("   1 к %d"):format(r.odds) or "")
	cine.BackgroundTransparency = 1
	cine.Visible = true
	TweenService:Create(cine, TweenInfo.new(0.35), { BackgroundTransparency = 0.2 }):Play()
	flash.BackgroundColor3, flash.BackgroundTransparency = Color3.new(1, 1, 1), 0.1
	TweenService:Create(flash, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	play("legendary")
	local sc = cineTop:FindFirstChild("Bounce") or K.make("UIScale", { Name = "Bounce" }, cineTop)
	sc.Scale = 0.3
	TweenService:Create(sc, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	cineConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - cineT0
		cineRays.Rotation = t * 25
		for _, ray in rayList do ray.BackgroundTransparency = 0.5 + math.sin(t * 4) * 0.1 end
		m:PivotTo(CFrame.new(center + Vector3.new(0, math.sin(t * 2) * rad * 0.04, 0)) * CFrame.Angles(0, t * 0.9, 0) * rel)
		if t > 4.2 then cineClose() end
	end)
	return true
end

-- показ результата одного фонарика: вспышка у места падения, дух, надпись
local function showResult(r, followed)
	local info = Game.Kinds[r.kind]
	local rar = Game.Rarity[info.rarity]
	local special = r.variant ~= "normal"
	local land = Vector3.new(r.x, 3, 20 + r.dist)
	local col = special and Game.Variants[r.variant].color or rar.color
	local big = RANK[info.rarity] >= 3 or special
	ring(land, 3, big and 40 or 16, col, 0.7)
	burst(land + Vector3.new(0, 2, 0), col, big and 70 or 28)
	play(big and "catchRare" or "catch")
	local m = Spirits.Builders[r.kind]()
	pcall(Spirits.applyVariant, m, special and r.variant or nil)
	m.Parent = workspace
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local k = math.min(1, t / 1.6)
		local y = 3 + (info.height or 0) + k * 6 + math.sin(t * 5) * 0.4
		local pos = Vector3.new(land.X, y, land.Z)
		Spirits.animate(m, CFrame.lookAt(pos, pos + Vector3.new(0, 0, -1)) * (Spirits.Pose[r.kind] and Spirits.Pose[r.kind](t) or CFrame.new()), t * (info.animSpeed or 4))
		for _, p in m:GetChildren() do
			if p:IsA("BasePart") and k > 0.6 then p.Transparency = math.max(p.Transparency, (k - 0.6) / 0.4) end
		end
		if k >= 1 then
			conn:Disconnect()
			m:Destroy()
		end
	end)
	task.delay(2.2, function() if m.Parent then m:Destroy() end end)
	-- столб света над легендарными и реже
	if RANK[info.rarity] >= 5 or (special and Game.Variants[r.variant].chance <= 1 / 80) then
		local beam = K.make("Part", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(160, 4, 4), Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = col, Transparency = 0.4, CFrame = CFrame.new(land.X, 80, land.Z) * CFrame.Angles(0, 0, math.rad(90)) }, workspace)
		TweenService:Create(beam, TweenInfo.new(2.2), { Transparency = 1 }):Play()
		task.delay(2.3, function() beam:Destroy() end)
	end
	-- надпись: кино для самых редких, иначе короткий баннер
	local cineWorthy = RANK[info.rarity] >= 5 or (special and Game.Variants[r.variant].chance <= 1 / 80)
	if cineWorthy and not followed and cinematic(r) then return end
	if cineWorthy and followed then
		task.delay(0.6, function() cinematic(r) end)
	end
	bannerSeq += 1
	local my = bannerSeq
	local word = special and (Game.Variants[r.variant].name:upper() .. "!") or (WORD[info.rarity] or "Пойман")
	bannerTop.Text = word
	bannerTop.TextColor3 = col
	bannerSub.Text = (special and (Game.Variants[r.variant].name .. " ") or "") .. info.name .. (r.odds >= 2 and ("   1 к %d"):format(r.odds) or "") .. ("   +%d"):format(r.coins)
	bannerSub.TextColor3 = Color3.new(1, 1, 1)
	banner.Visible = true
	local sc = banner:FindFirstChild("Bounce") or K.make("UIScale", { Name = "Bounce" }, banner)
	sc.Scale = 0.5
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = big and 1.1 or 0.8 }):Play()
	task.delay(big and 2.4 or 1.4, function()
		if bannerSeq == my then banner.Visible = false end
	end)
	if big then
		flash.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), 0.6)
		flash.BackgroundTransparency = 0.7
		TweenService:Create(flash, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
	end
end

------------------------------------------------------------------ полёт фонариков и камера
local camSeq = 0
local function startFlight(res, follow)
	local origin = Vector3.new(0, 5, 8)
	local char = plr.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if root then origin = root.Position + Vector3.new(0, 3, 4) end
	local latest, firstLand = 0, nil
	for i, r in res.results do
		local land = Vector3.new(r.x, 3, 20 + r.dist)
		local flight = Game.flightTime(r.dist)
		latest = math.max(latest, r.delay + flight)
		task.delay(r.delay, function()
			local p = K.make("Part", { Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false,
				Material = Enum.Material.Neon, Color = Color3.fromRGB(255, 190, 100) }, workspace)
			K.make("PointLight", { Range = 18, Brightness = 1.4, Color = Color3.fromRGB(255, 190, 110) }, p)
			local a0 = K.make("Attachment", { Position = Vector3.new(0, 0.5, 0) }, p)
			local a1 = K.make("Attachment", { Position = Vector3.new(0, -0.5, 0) }, p)
			K.make("Trail", { Attachment0 = a0, Attachment1 = a1, Lifetime = 0.7, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 60)),
				Transparency = NumberSequence.new(0.2, 1), WidthScale = NumberSequence.new(1.2, 0.2) }, p)
			local t0 = os.clock()
			local conn
			conn = RunService.RenderStepped:Connect(function()
				local k = math.min(1, (os.clock() - t0) / flight)
				local ease = 1 - (1 - k) ^ 1.6
				local pos = origin:Lerp(land, ease) + Vector3.new(0, math.sin(k * math.pi) * (10 + r.dist * 0.12), 0)
				p.CFrame = CFrame.new(pos)
				if i == 1 and follow and camSeq > 0 then
					local cam = workspace.CurrentCamera
					if cam and cam.CameraType == Enum.CameraType.Scriptable then
						cam.CFrame = CFrame.lookAt(pos + Vector3.new(0, 10, -22), pos)
					end
				end
				if k >= 1 then
					conn:Disconnect()
					p:Destroy()
					showResult(r, follow)
				end
			end)
			task.delay(flight + 1, function() if p.Parent then p:Destroy() end end)
		end)
	end
	if follow then
		camSeq += 1
		local my = camSeq
		local cam = workspace.CurrentCamera
		if cam then
			cam.CameraType = Enum.CameraType.Scriptable
			cam.CFrame = CFrame.lookAt(origin + Vector3.new(0, 10, -22), origin + Vector3.new(0, 4, 40))
		end
		task.delay(latest + 1.1, function()
			if camSeq == my and cam then
				cam.CameraType = Enum.CameraType.Custom
				camSeq = 0
			end
		end)
	end
end
remotes.AutoResult.OnClientEvent:Connect(function(res) startFlight(res, false) end)

------------------------------------------------------------------ главная кнопка запуска, полоска силы, авто
local launchB, launchL, meterFill, autoB, autoL, tutHint
do
	launchB = K.make("TextButton", { Name = "LaunchBtn", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(132, 132),
		BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false }, hud)
	K.corner(launchB, UDim.new(1, 0))
	K.stroke(launchB, T.ink, 5)
	local grad = K.gradient(launchB, Color3.fromRGB(255, 210, 100), Color3.fromRGB(235, 120, 40))
	K.icon(launchB, "luck", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(60, 60), Position = UDim2.new(0.5, 0, 0, 14) })
	launchL = K.text(launchB, "ЗАПУСК", { Size = UDim2.new(1, -12, 0, 32), Position = UDim2.new(0, 6, 1, -50), MaxText = 24 })
	-- полоска силы: растёт и падает, пока кнопка зажата
	local meter = K.make("Frame", { Name = "Meter", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0.5, 80, 1, -16), Size = UDim2.fromOffset(34, 170), BackgroundColor3 = T.ink, Visible = false }, hud)
	K.corner(meter, UDim.new(0, 12))
	K.stroke(meter, Color3.new(1, 1, 1), 3)
	local colorBar = K.make("Frame", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1) }, meter)
	K.corner(colorBar, UDim.new(0, 9))
	K.make("UIGradient", { Rotation = -90, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 60, 60)), ColorSequenceKeypoint.new(0.55, Color3.fromRGB(245, 205, 60)),
		ColorSequenceKeypoint.new(0.93, Color3.fromRGB(90, 235, 120)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)) }) }, colorBar)
	meterFill = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 18, 0, 8), Position = UDim2.fromScale(0.5, 1), BackgroundColor3 = Color3.new(1, 1, 1) }, meter)
	K.corner(meterFill, UDim.new(1, 0))
	K.stroke(meterFill, T.ink, 3)
	local qualL = K.text(hud, "", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -190), Size = UDim2.fromOffset(360, 44), MaxText = 34, Visible = false, StrokeThickness = 3 })
	tutHint = K.text(hud, "Зажми ЗАПУСК и отпусти, когда полоска наверху", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -158), Size = UDim2.fromOffset(440, 30), MaxText = 19,
		Font = Enum.Font.GothamBold, StrokeThickness = 3 })

	autoB, autoL = K.button(hud, "АВТО", T.purple, { Name = "AutoBtn", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(0.5, -86, 1, -28), Size = UDim2.fromOffset(100, 50), MaxText = 18, Visible = false })
	autoB.Activated:Connect(function()
		local r = remotes.SetAuto:InvokeServer(not state.auto)
		if r and not r.ok and r.msg then showToast(r.msg) end
	end)

	local holding, t0, power, readyAt = false, 0, 0, 0
	launchB.InputBegan:Connect(function(io)
		if io.UserInputType ~= Enum.UserInputType.Touch and io.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if os.clock() < readyAt or holding then return end
		holding, t0 = true, os.clock()
		remotes.Charge:FireServer()
		meter.Visible = true
		play("reveal")
	end)
	local function release()
		if not holding then return end
		holding = false
		meter.Visible = false
		local q = power
		task.spawn(function()
			local res = remotes.Throw:InvokeServer()
			if res and res.ok then
				readyAt = os.clock() + (res.cd or 2)
				play("click")
				qualL.Text = ("%s"):format(Game.qualityName(res.q))
				qualL.TextColor3 = res.q >= 0.93 and T.gold or (res.q >= 0.78 and T.green or Color3.new(1, 1, 1))
				qualL.Visible = true
				K.pop(qualL)
				task.delay(1.2, function() qualL.Visible = false end)
				tutHint.Visible = false
				startFlight(res, true)
			end
		end)
	end
	launchB.InputEnded:Connect(release)
	launchB.MouseButton1Up:Connect(release)
	RunService.RenderStepped:Connect(function()
		if holding then
			power = Game.meterAt(os.clock() - t0)
			meterFill.Position = UDim2.fromScale(0.5, 1 - power)
		end
		local cooling = os.clock() < readyAt
		launchL.Text = cooling and ("%.1f"):format(readyAt - os.clock()) or "ЗАПУСК"
		grad.Color = cooling and ColorSequence.new(Color3.fromRGB(150, 150, 160), Color3.fromRGB(100, 100, 115))
			or ColorSequence.new(Color3.fromRGB(255, 210, 100), Color3.fromRGB(235, 120, 40))
	end)
end

------------------------------------------------------------------ обновление интерфейса
local function refreshHUD()
	coinL.Text = tostring(state.coins)
	luckL.Text = ("Удача x%.2f"):format(state.luck or 1)
	recordL.Text = ("Рекорд %d м   Духов запущено: %d"):format(state.record, state.total)
	-- зона по рекорду и полоска до следующей
	local z = Game.zoneAt(state.record)
	zoneL.Text = z.name
	zoneL.TextColor3 = z.color:Lerp(Color3.new(1, 1, 1), 0.3)
	zoneFill.Size = UDim2.fromScale(math.clamp((state.record - z.from) / math.max(z.to - z.from, 1), 0, 1), 1)
	autoB.Visible = (state.autoPeriod or 0) > 0
	autoL.Text = state.auto and "АВТО: ВКЛ" or "АВТО: ВЫКЛ"
	K.recolor(autoB, state.auto and T.green or Color3.fromRGB(110, 110, 140))
	btnGift.Badge.Visible = state.dailyReady == true
	btnAdmin.Visible = state.isAdmin == true
	tutHint.Visible = (state.total or 0) == 0
	-- значок на «Улучшения», если хватает денег на дешёвое
	local afford = false
	for key in Game.Upgrades do
		local c = Game.upgradeCost(key, state.lv[key] or 1)
		if c and c <= state.coins and c <= math.max(100, state.coins) then afford = true end
	end
	btnShop.Badge.Visible = afford
	if shopW.Visible then refreshShop() end
	if indexW.Visible then refreshIndex() end
	if giftW.Visible then refreshGift() end
end
remotes.State.OnClientEvent:Connect(function(s)
	for k, v in s do state[k] = v end
	refreshHUD()
end)
remotes.Notice.OnClientEvent:Connect(function(text) showToast(text, 3) end)
refreshHUD()
