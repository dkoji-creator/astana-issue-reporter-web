-- Spirit Catchers, клиент: визуал духов и следов, выслеживание цели из Атласа, ловля фонарём,
-- чистый мобильный интерфейс (банка, действие, таймер события), Атлас, настройки, звук, эффекты.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Spirits = require(Shared:WaitForChild("Spirits"))
local Audio = require(Shared:WaitForChild("Config"):WaitForChild("Audio"))
local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spiritsFolder = workspace:WaitForChild("Spirits")
local World = workspace:WaitForChild("World")
local Altar = World:WaitForChild("Altar")
local Barrier = World:WaitForChild("GardenBarrier")
local ALTAR_POS = Altar.Position
local IS_TEST = RunService:IsStudio() or game.PlaceId == 99980756426085

local GOLD = Color3.fromRGB(255, 200, 80)
local COLD = Color3.fromRGB(120, 210, 255)
local PANEL = Color3.fromRGB(18, 20, 38)
local ACCENT = Color3.fromRGB(235, 120, 70)

local function root()
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ состояние
local state = {
	jar = {}, cap = 3, saved = {}, coins = 0, dust = 0, levels = { jar = 1, range = 1, power = 1 },
	tutorialDone = true, gardenOpen = false, distinct = 0, orders = {},
	settings = { music = 0.6, sfx = 0.8, reduced = false, diag = false },
}
local trackKind: string? = nil -- цель охоты из Атласа

------------------------------------------------------------------ звук
local musicGroup = Instance.new("SoundGroup")
musicGroup.Name = "Music"
musicGroup.Parent = SoundService
local sfxGroup = Instance.new("SoundGroup")
sfxGroup.Name = "Sfx"
sfxGroup.Parent = SoundService
local function makeSound(id, group, looped, parent)
	if not id or id == "" then return nil end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = looped == true
	s.SoundGroup = group
	s.Parent = parent or SoundService
	return s
end
local music = makeSound(Audio.Music.lantern, musicGroup, true)
local moonLayer = makeSound(Audio.Music.moonLayer, musicGroup, true)
if music then music.Volume = 0.6 music:Play() end
if moonLayer then moonLayer.Volume = 0 moonLayer:Play() end
local sfx = {}
for k, id in Audio.Sfx do
	sfx[k] = makeSound(id, sfxGroup, false)
end
local function play(name)
	local s = sfx[name]
	if s then s:Play() end
end
local function applyAudio()
	musicGroup.Volume = state.settings.music
	sfxGroup.Volume = state.settings.sfx
end

------------------------------------------------------------------ UI-кит
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "SpiritHUD", false, true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = plr:WaitForChild("PlayerGui")

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 10)
	c.Parent = o
end
local function strokeOf(o, color, th)
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = color or Color3.fromRGB(255, 255, 255), th or 1.5, 0.6
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end
local function maxText(o, n)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = o
end
local function label(text, pos, size, parent, maxSize, bg)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = bg == false and 1 or 0.25
	l.TextColor3, l.Font, l.TextScaled = Color3.new(1, 1, 1), Enum.Font.GothamBold, true
	l.BackgroundColor3 = PANEL
	l.Text, l.Position, l.Size = text, pos, size
	corner(l)
	maxText(l, maxSize or 20)
	l.Parent = parent or gui
	return l
end
local function button(text, pos, size, color, parent, maxSize)
	local b = Instance.new("TextButton")
	b.Text, b.Position, b.Size = text, pos, size
	b.TextScaled, b.Font, b.TextColor3 = true, Enum.Font.GothamBold, Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	b.AutoButtonColor = true
	corner(b)
	maxText(b, maxSize or 20)
	b.Parent = parent or gui
	b.Activated:Connect(function() play("click") end)
	return b
end

local toastL
local function showToast(text, secs)
	toastL.Text, toastL.Visible = text, true
	task.delay(secs or 2.4, function()
		if toastL.Text == text then toastL.Visible = false end
	end)
end
local function punch(o)
	local s = o.Size
	o.Size = UDim2.new(s.X.Scale, s.X.Offset * 1.12, s.Y.Scale, s.Y.Offset * 1.12)
	TweenService:Create(o, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = s }):Play()
end

------------------------------------------------------------------ HUD: банка, валюта, таймер события, цель
local jarBox = Instance.new("Frame")
jarBox.Position, jarBox.Size = UDim2.new(0, 12, 0, 56), UDim2.new(0, 210, 0, 52)
jarBox.BackgroundColor3, jarBox.BackgroundTransparency = PANEL, 0.25
corner(jarBox)
jarBox.Parent = gui
local jarTitle = label("Банка 0/3", UDim2.new(0, 8, 0, 4), UDim2.new(1, -16, 0, 20), jarBox, 18, false)
jarTitle.TextXAlignment = Enum.TextXAlignment.Left
local jarBar = Instance.new("Frame")
jarBar.Position, jarBar.Size = UDim2.new(0, 8, 0, 26), UDim2.new(1, -16, 0, 6)
jarBar.BackgroundColor3 = Color3.fromRGB(50, 50, 70)
corner(jarBar, UDim.new(1, 0))
jarBar.Parent = jarBox
local jarFill = Instance.new("Frame")
jarFill.Size, jarFill.BackgroundColor3 = UDim2.new(0, 0, 1, 0), COLD
corner(jarFill, UDim.new(1, 0))
jarFill.Parent = jarBar
local jarItems = label("", UDim2.new(0, 8, 0, 34), UDim2.new(1, -16, 0, 15), jarBox, 13, false)
jarItems.TextXAlignment, jarItems.TextColor3, jarItems.Font = Enum.TextXAlignment.Left, Color3.fromRGB(200, 205, 230), Enum.Font.Gotham

local walletL = label("", UDim2.new(0, 12, 0, 112), UDim2.new(0, 210, 0, 22), nil, 15)
walletL.BackgroundTransparency = 0.45

local atlasBtn = button("Атлас", UDim2.new(0, 12, 0, 140), UDim2.new(0, 102, 0, 34), Color3.fromRGB(70, 80, 160))
local menuBtn = button("Настройки", UDim2.new(0, 120, 0, 140), UDim2.new(0, 102, 0, 34), Color3.fromRGB(60, 62, 84), nil, 16)

local trackBox = Instance.new("TextButton")
trackBox.Position, trackBox.Size = UDim2.new(0, 12, 0, 180), UDim2.new(0, 210, 0, 40)
trackBox.BackgroundColor3, trackBox.BackgroundTransparency, trackBox.Text = Color3.fromRGB(70, 45, 20), 0.15, ""
trackBox.Visible = false
corner(trackBox)
strokeOf(trackBox, ACCENT, 2)
trackBox.Parent = gui
local trackL = label("", UDim2.new(0, 8, 0, 2), UDim2.new(1, -16, 1, -4), trackBox, 15, false)
trackL.TextXAlignment = Enum.TextXAlignment.Left

local banner = label("", UDim2.new(0.5, -140, 0, 8), UDim2.new(0, 280, 0, 30), nil, 18)
toastL = label("", UDim2.new(0.5, -200, 0, 44), UDim2.new(0, 400, 0, 32), nil, 18)
toastL.Visible = false
local tutPanel = label("", UDim2.new(0.5, -210, 1, -96), UDim2.new(0, 420, 0, 52), nil, 18)
tutPanel.BackgroundColor3, tutPanel.Visible = Color3.fromRGB(30, 70, 110), false
local skipBtn = button("Пропустить", UDim2.new(1, -96, 0, -28), UDim2.new(0, 96, 0, 24), Color3.fromRGB(60, 60, 80), tutPanel, 14)
local districtTitle = label("", UDim2.new(0.5, -170, 0.3, 0), UDim2.new(0, 340, 0, 44), nil, 30, false)
districtTitle.TextStrokeTransparency, districtTitle.Visible = 0.3, false

-- кнопка ловли: компактная, слева от стандартной кнопки прыжка, появляется только рядом с доступным духом
local catchBtn = Instance.new("TextButton")
catchBtn.AnchorPoint = Vector2.new(1, 1)
catchBtn.Size, catchBtn.Position = UDim2.new(0, 92, 0, 92), UDim2.new(1, -190, 1, -150)
catchBtn.Text, catchBtn.TextScaled, catchBtn.Font = "ЛОВИТЬ", true, Enum.Font.GothamBlack
catchBtn.BackgroundColor3, catchBtn.TextColor3 = Color3.fromRGB(80, 200, 140), Color3.new(1, 1, 1)
catchBtn.AutoButtonColor, catchBtn.Visible = false, false
corner(catchBtn, UDim.new(1, 0))
local cpad = Instance.new("UIPadding")
cpad.PaddingLeft, cpad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
cpad.Parent = catchBtn
local cstroke = strokeOf(catchBtn, Color3.new(1, 1, 1), 3)
cstroke.Transparency = 0
catchBtn.Parent = gui
local fill = Instance.new("Frame")
fill.BackgroundColor3, fill.BackgroundTransparency = Color3.new(1, 1, 1), 0.45
fill.Size, fill.AnchorPoint, fill.Position, fill.ZIndex = UDim2.new(1, 0, 0, 0), Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), 0
corner(fill, UDim.new(1, 0))
fill.Parent = catchBtn

local vignette = Instance.new("Frame")
vignette.Size, vignette.BackgroundTransparency = UDim2.fromScale(1, 1), 1
vignette.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
vignette.Parent = gui

local hint = Instance.new("BillboardGui")
hint.Size, hint.AlwaysOnTop = UDim2.new(0, 170, 0, 32), true
local hintText = Instance.new("TextLabel")
hintText.Size, hintText.BackgroundTransparency, hintText.TextScaled, hintText.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
hintText.TextColor3, hintText.TextStrokeTransparency = Color3.new(1, 1, 1), 0.2
hintText.Parent = hint
hint.Parent = gui

------------------------------------------------------------------ окна
local windows = {}
local function window(title, w, h)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.53), UDim2.fromScale(w, h)
	f.BackgroundColor3, f.BackgroundTransparency, f.Visible = PANEL, 0.04, false
	f.ZIndex = 10
	corner(f, UDim.new(0, 14))
	strokeOf(f, Color3.fromRGB(120, 130, 200), 1.5)
	local t = label(title, UDim2.new(0, 14, 0, 6), UDim2.new(0.5, -190, 0, 30), f, 22, false)
	t.TextXAlignment = Enum.TextXAlignment.Left
	local close = button("Закрыть", UDim2.new(1, -96, 0, 6), UDim2.new(0, 88, 0, 30), Color3.fromRGB(150, 50, 60), f, 16)
	close.Activated:Connect(function() f.Visible = false end)
	f.Parent = gui
	table.insert(windows, f)
	return f
end
local function openOnly(f)
	for _, w in windows do
		if w ~= f then w.Visible = false end
	end
	f.Visible = not f.Visible
end

-- Атлас с вкладками
local atlasW = window("Атлас духов", 0.9, 0.82)
local tabs = {}
local pages = {}
local tabNames = { { "atlas", "Атлас" }, { "orders", "Заказы" }, { "upgrades", "Улучшения" }, { "worlds", "Миры" } }
local currentTab = "atlas"
local function showTab(key)
	currentTab = key
	for k, p in pages do p.Visible = k == key end
	for k, b in tabs do b.BackgroundColor3 = k == key and ACCENT or Color3.fromRGB(50, 52, 80) end
end
for i, t in tabNames do
	local b = button(t[2], UDim2.new(0.5, -170 + (i - 1) * 86, 0, 6), UDim2.new(0, 82, 0, 30), Color3.fromRGB(50, 52, 80), atlasW, 15)
	b.Activated:Connect(function() showTab(t[1]) end)
	tabs[t[1]] = b
	local p = Instance.new("ScrollingFrame")
	p.Position, p.Size = UDim2.new(0, 8, 0, 44), UDim2.new(1, -16, 1, -52)
	p.BackgroundTransparency, p.ScrollBarThickness = 1, 6
	p.AutomaticCanvasSize, p.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
	p.Visible = false
	p.Parent = atlasW
	pages[t[1]] = p
end
local grid = Instance.new("UIGridLayout")
grid.CellSize, grid.CellPadding = UDim2.new(0.25, -8, 0, 176), UDim2.new(0, 8, 0, 8)
grid.SortOrder = Enum.SortOrder.LayoutOrder
grid.Parent = pages.atlas
for _, k in { "orders", "upgrades", "worlds" } do
	local l = Instance.new("UIListLayout")
	l.Padding, l.SortOrder = UDim.new(0, 8), Enum.SortOrder.LayoutOrder
	l.Parent = pages[k]
end

-- Настройки
local setW = window("Настройки", 0.6, 0.7)
local setList = Instance.new("Frame")
setList.Position, setList.Size, setList.BackgroundTransparency = UDim2.new(0, 14, 0, 46), UDim2.new(1, -28, 1, -56), 1
setList.Parent = setW
local setLayout = Instance.new("UIListLayout")
setLayout.Padding = UDim.new(0, 8)
setLayout.Parent = setList

local function sendSettings()
	remotes.SetSettings:FireServer(state.settings)
end
local function volumeRow(title, key)
	local row = Instance.new("Frame")
	row.Size, row.BackgroundTransparency = UDim2.new(1, 0, 0, 36), 1
	row.Parent = setList
	local l = label("", UDim2.new(0, 0, 0, 0), UDim2.new(0.55, 0, 1, 0), row, 18, false)
	l.TextXAlignment = Enum.TextXAlignment.Left
	local minus = button("-", UDim2.new(0.58, 0, 0, 0), UDim2.new(0.2, -4, 1, 0), Color3.fromRGB(60, 62, 90), row, 22)
	local plus = button("+", UDim2.new(0.8, 0, 0, 0), UDim2.new(0.2, 0, 1, 0), Color3.fromRGB(60, 62, 90), row, 22)
	local function refresh() l.Text = ("%s: %d%%"):format(title, math.floor(state.settings[key] * 100 + 0.5)) end
	local function step(d)
		state.settings[key] = math.clamp(math.floor(state.settings[key] * 10 + 0.5 + d) / 10, 0, 1)
		refresh()
		applyAudio()
		sendSettings()
	end
	minus.Activated:Connect(function() step(-1) end)
	plus.Activated:Connect(function() step(1) end)
	return refresh
end
local function toggleRow(title, key, onChange)
	local b = button("", UDim2.new(), UDim2.new(1, 0, 0, 36), Color3.fromRGB(60, 62, 90), setList, 18)
	local function refresh()
		b.Text = title .. ": " .. (state.settings[key] and "вкл" or "выкл")
		b.BackgroundColor3 = state.settings[key] and Color3.fromRGB(60, 140, 100) or Color3.fromRGB(60, 62, 90)
	end
	b.Activated:Connect(function()
		state.settings[key] = not state.settings[key]
		refresh()
		sendSettings()
		if onChange then onChange() end
	end)
	return refresh
end
local refreshMusic = volumeRow("Музыка", "music")
local refreshSfx = volumeRow("Звуки", "sfx")
local applyReduced
local refreshReduced = toggleRow("Приглушённые эффекты", "reduced", function() applyReduced() end)
local refreshDiag
if IS_TEST then
	refreshDiag = toggleRow("Диагностика FPS (тест)", "diag", nil)
end
local soundNote = label("", UDim2.new(), UDim2.new(1, 0, 0, 40), setList, 14, false)
soundNote.TextColor3, soundNote.Font, soundNote.TextWrapped = Color3.fromRGB(180, 185, 210), Enum.Font.Gotham, true
soundNote.Text = (Audio.Music.lantern == "") and "Музыка и звуки появятся после загрузки аудио в Roblox." or "Камера: чувствительность меняется в меню Roblox."
local function refreshSettings()
	refreshMusic()
	refreshSfx()
	refreshReduced()
	if refreshDiag then refreshDiag() end
end

------------------------------------------------------------------ заполнение Атласа
local function trailText(info) return info.trail and info.trail.text or "" end
local cards = {}
local function setTrack(kind)
	trackKind = kind
	trackBox.Visible = kind ~= nil
	if kind then
		showToast("Цель охоты: " .. Catalog.Kinds[kind].name .. ". Ищи след: " .. trailText(Catalog.Kinds[kind]), 3)
	end
end
trackBox.Activated:Connect(function() setTrack(nil) end)

local function refreshAtlas()
	for i, kind in Catalog.Order do
		local info = Catalog.Kinds[kind]
		local rar = Catalog.Rarity[info.rarity]
		local c = cards[kind]
		if not c then
			c = {}
			local f = Instance.new("Frame")
			f.LayoutOrder, f.BackgroundColor3 = i, Color3.fromRGB(32, 34, 60)
			corner(f)
			local st = strokeOf(f, rar.color, 2)
			st.Transparency = 0.2
			c.name = label("", UDim2.new(0, 6, 0, 4), UDim2.new(1, -12, 0, 20), f, 15, false)
			c.rar = label(rar.name, UDim2.new(0, 6, 0, 24), UDim2.new(1, -12, 0, 14), f, 12, false)
			c.rar.TextColor3 = rar.color
			c.count = label("", UDim2.new(0, 6, 0, 38), UDim2.new(1, -12, 0, 14), f, 12, false)
			c.count.TextColor3 = Color3.fromRGB(200, 205, 230)
			c.info = label("", UDim2.new(0, 6, 0, 54), UDim2.new(1, -12, 0, 54), f, 12, false)
			c.info.TextColor3, c.info.Font, c.info.TextWrapped = Color3.fromRGB(205, 210, 230), Enum.Font.Gotham, true
			c.info.TextYAlignment = Enum.TextYAlignment.Top
			c.track = button("Выследить", UDim2.new(0, 6, 1, -64), UDim2.new(1, -12, 0, 28), ACCENT, f, 14)
			c.track.Activated:Connect(function()
				setTrack(trackKind ~= kind and kind or nil)
				atlasW.Visible = false
			end)
			c.equip = button("", UDim2.new(0, 6, 1, -32), UDim2.new(1, -12, 0, 26), Color3.fromRGB(200, 60, 70), f, 14)
			c.equip.Activated:Connect(function()
				remotes.Equip:InvokeServer(state.equipped ~= kind and kind or nil)
			end)
			f.Parent = pages.atlas
			cards[kind] = c
		end
		local n = state.saved[kind] or 0
		c.name.Text = info.name
		c.name.TextColor3 = n > 0 and Color3.new(1, 1, 1) or Color3.fromRGB(150, 150, 170)
		c.count.Text = n > 0 and ("Поймано: %d"):format(n) or "Не найден"
		local places = {}
		for _, d in Catalog.districtsOf(kind) do table.insert(places, Catalog.DistrictNames[d]) end
		c.info.Text = (n > 0 and info.habit or info.hint) .. "\n" .. Catalog.ConditionText[info.condition] .. ". След: " .. trailText(info)
		c.track.Text = trackKind == kind and "Цель выбрана" or "Выследить"
		c.track.BackgroundColor3 = trackKind == kind and Color3.fromRGB(90, 90, 110) or ACCENT
		c.equip.Visible = n > 0
		c.equip.Text = state.equipped == kind and "Снять спутника" or "Взять спутником"
	end
	local total = 0
	for _ in state.saved do total += 1 end
end

local orderRows = {}
local function orderText(o)
	if o.type == "kind" then
		return ("Принеси: %s  %d/%d"):format(Catalog.Kinds[o.kind].name, o.have, o.need)
	end
	return ("Принеси духов «%s»: %d/%d"):format(Catalog.Rarity[o.rarity].name, o.have, o.need)
end
local function refreshOrders()
	for i = 1, Catalog.OrderSlots do
		local o = state.orders[i]
		local r = orderRows[i]
		if not r then
			r = {}
			local f = Instance.new("Frame")
			f.Size, f.BackgroundColor3, f.LayoutOrder = UDim2.new(1, 0, 0, 64), Color3.fromRGB(32, 34, 60), i
			corner(f)
			r.title = label("", UDim2.new(0, 10, 0, 6), UDim2.new(0.7, -10, 0, 24), f, 18, false)
			r.title.TextXAlignment = Enum.TextXAlignment.Left
			r.reward = label("", UDim2.new(0, 10, 0, 34), UDim2.new(0.7, -10, 0, 20), f, 14, false)
			r.reward.TextXAlignment, r.reward.TextColor3 = Enum.TextXAlignment.Left, GOLD
			r.go = button("Выследить", UDim2.new(0.72, 0, 0, 14), UDim2.new(0.28, -10, 0, 36), ACCENT, f, 16)
			r.go.Activated:Connect(function()
				local ord = state.orders[i]
				if ord and ord.type == "kind" then
					setTrack(ord.kind)
					atlasW.Visible = false
				end
			end)
			f.Parent = pages.orders
			orderRows[i] = r
		end
		if o then
			r.title.Text = orderText(o)
			r.reward.Text = ("Награда: %d монет, %d пыли"):format(o.coins, o.dust)
			r.go.Visible = o.type == "kind"
		else
			r.title.Text, r.reward.Text, r.go.Visible = "Новый заказ появится после сдачи улова", "", false
		end
	end
	if not pages.orders:FindFirstChild("Note") then
		local note = label("Заказы засчитываются, когда сдаёшь банку у алтаря.", UDim2.new(), UDim2.new(1, 0, 0, 24), pages.orders, 14, false)
		note.Name, note.LayoutOrder, note.TextColor3 = "Note", 10, Color3.fromRGB(180, 185, 210)
	end
end

local upRows = {}
local function refreshUpgrades()
	for i, key in Catalog.UpgradeOrder do
		local up = Catalog.Upgrades[key]
		local r = upRows[key]
		if not r then
			r = {}
			local f = Instance.new("Frame")
			f.Size, f.BackgroundColor3, f.LayoutOrder = UDim2.new(1, 0, 0, 64), Color3.fromRGB(32, 34, 60), i
			corner(f)
			r.title = label("", UDim2.new(0, 10, 0, 6), UDim2.new(0.62, -10, 0, 24), f, 18, false)
			r.title.TextXAlignment = Enum.TextXAlignment.Left
			r.desc = label(up.desc, UDim2.new(0, 10, 0, 34), UDim2.new(0.62, -10, 0, 20), f, 14, false)
			r.desc.TextXAlignment, r.desc.TextColor3 = Enum.TextXAlignment.Left, Color3.fromRGB(190, 195, 220)
			r.buy = button("", UDim2.new(0.64, 0, 0, 12), UDim2.new(0.36, -10, 0, 40), Color3.fromRGB(70, 160, 100), f, 15)
			r.buy.Activated:Connect(function()
				local res = remotes.Upgrade:InvokeServer(key)
				if res and res.ok then
					showToast(up.name .. ": новый уровень!")
					play("save")
					punch(r.title)
				elseif res and res.msg then
					showToast(res.msg)
				end
			end)
			f.Parent = pages.upgrades
			upRows[key] = r
		end
		local lvl = state.levels[key] or 1
		local cur = up.fmt:format(up.values[lvl])
		if lvl >= Catalog.MaxLevel then
			r.title.Text = ("%s ур.%d: %s (макс.)"):format(up.name, lvl, cur)
			r.buy.Text, r.buy.BackgroundColor3 = "Максимум", Color3.fromRGB(80, 80, 90)
		else
			r.title.Text = ("%s ур.%d: %s -> %s"):format(up.name, lvl, cur, up.fmt:format(up.values[lvl + 1]))
			local c, d = up.coins[lvl], up.dust[lvl]
			r.buy.Text = d > 0 and ("%d монет + %d пыли"):format(c, d) or ("%d монет"):format(c)
			r.buy.BackgroundColor3 = (state.coins >= c and state.dust >= d) and Color3.fromRGB(70, 160, 100) or Color3.fromRGB(90, 90, 100)
		end
	end
	if not pages.upgrades:FindFirstChild("Note") then
		local note = label("Покупка — у алтаря. Монеты дают сданные духи и заказы, пыль — дубликаты.", UDim2.new(), UDim2.new(1, 0, 0, 30), pages.upgrades, 14, false)
		note.Name, note.LayoutOrder, note.TextColor3, note.TextWrapped = "Note", 10, Color3.fromRGB(180, 185, 210), true
	end
end

local function refreshWorlds()
	if pages.worlds:FindFirstChild("Built") then return end
	local marker = Instance.new("BoolValue")
	marker.Name = "Built"
	marker.Parent = pages.worlds
	for i, key in Catalog.Worlds.Order do
		local w = Catalog.Worlds.Worlds[key]
		local f = Instance.new("Frame")
		f.Size, f.BackgroundColor3, f.LayoutOrder = UDim2.new(1, 0, 0, 92), w.active and Color3.fromRGB(40, 50, 80) or Color3.fromRGB(30, 30, 44), i
		corner(f)
		local t = label(w.name .. (w.active and "  (открыт)" or "  (скоро)"), UDim2.new(0, 10, 0, 4), UDim2.new(1, -20, 0, 24), f, 18, false)
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = w.active and GOLD or Color3.fromRGB(170, 170, 190)
		local b = label(w.blurb .. "\nГлавная цель: " .. w.star, UDim2.new(0, 10, 0, 30), UDim2.new(1, -20, 0, 58), f, 14, false)
		b.TextXAlignment, b.TextYAlignment, b.TextWrapped = Enum.TextXAlignment.Left, Enum.TextYAlignment.Top, true
		b.Font, b.TextColor3 = Enum.Font.Gotham, Color3.fromRGB(205, 210, 230)
		f.Parent = pages.worlds
	end
end

local function refreshWindows()
	if atlasW.Visible then
		refreshAtlas()
		refreshOrders()
		refreshUpgrades()
		refreshWorlds()
	end
end
atlasBtn.Activated:Connect(function()
	openOnly(atlasW)
	refreshWindows()
	showTab(currentTab)
end)
menuBtn.Activated:Connect(function()
	openOnly(setW)
	refreshSettings()
end)

------------------------------------------------------------------ HUD и ворота сада
local function refreshHUD()
	local n = #state.jar
	jarTitle.Text = ("Банка %d/%d"):format(n, state.cap)
	jarFill.Size = UDim2.new(math.clamp(n / math.max(state.cap, 1), 0, 1), 0, 1, 0)
	jarFill.BackgroundColor3 = n >= state.cap and Color3.fromRGB(240, 120, 60) or COLD
	local names = {}
	for _, k in state.jar do table.insert(names, Catalog.Kinds[k].short) end
	jarItems.Text = n > 0 and table.concat(names, ", ") or "пусто"
	walletL.Text = ("Монеты %d   Пыль %d"):format(state.coins, state.dust)
	-- ворота сада и табличка показывают фактическое состояние
	Barrier.CanCollide = not state.gardenOpen
	Barrier.Transparency = state.gardenOpen and 0.9 or 0.2
	for _, g in Barrier:GetChildren() do
		local t = g:IsA("SurfaceGui") and g:FindFirstChildOfClass("TextLabel")
		if t then
			t.Text = state.gardenOpen and "Храмовый сад\nоткрыт"
				or ("Храмовый сад закрыт\nСохрани 3 разных духа: %d/%d"):format(math.min(state.distinct, Catalog.GardenNeed), Catalog.GardenNeed)
		end
	end
	refreshWindows()
end

------------------------------------------------------------------ эффекты
local reducedFx = false
applyReduced = function()
	reducedFx = state.settings.reduced
	local b = Lighting:FindFirstChild("Bloom")
	if b then b.Enabled = not reducedFx end
end

local function ring(pos, fromSize, toSize, color, secs, upright)
	local r = Instance.new("Part")
	r.Shape, r.Anchored, r.CanCollide, r.CanQuery, r.CastShadow = Enum.PartType.Cylinder, true, false, false, false
	r.Material, r.Color, r.Transparency = Enum.Material.Neon, color, reducedFx and 0.5 or 0.15
	r.Size = Vector3.new(0.15, fromSize, fromSize)
	r.CFrame = CFrame.new(pos) * (upright and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90)))
	r.Parent = workspace
	TweenService:Create(r, TweenInfo.new(secs, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, toSize, toSize), Transparency = 1 }):Play()
	task.delay(secs + 0.05, function() r:Destroy() end)
end

local function burst(pos, colors, n)
	if reducedFx then n = math.floor(n / 3) end
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.Transparency, a.Size, a.Position = true, false, false, 1, Vector3.one, pos
	a.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Color = colors
	pe.Rate, pe.Lifetime, pe.Speed = 0, NumberRange.new(0.6, 1.1), NumberRange.new(8, 16)
	pe.SpreadAngle, pe.RotSpeed = Vector2.new(180, 180), NumberRange.new(-200, 200)
	pe.Size = NumberSequence.new(0.5, 0.1)
	pe.LightEmission, pe.Acceleration = 0.3, Vector3.new(0, -14, 0)
	pe.Parent = a
	pe:Emit(n)
	task.delay(1.5, function() a:Destroy() end)
end

local streak, lastCatch = 0, 0
local function catchEffect(kind, at, coop)
	local r = root()
	if not r then return end
	local info = Catalog.Kinds[kind]
	local rar = Catalog.Rarity[info.rarity]
	streak = (os.clock() - lastCatch < 20) and streak + 1 or 1
	lastCatch = os.clock()
	local big = info.rarity ~= "common"
	play(big and "catchRare" or "catch")
	local m = Spirits.Builders[kind]()
	if kind == "GoldenCarp" then Spirits.scale(m, 0.6) end
	m.Parent = workspace
	local dur = big and 0.85 or 0.55
	ring(at + Vector3.new(0, 2, 0), big and 16 or 8, 2, rar.color, dur, true)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local p = math.min((os.clock() - t0) / dur, 1)
		local e = p * p
		local cr = root()
		local goal = cr and cr.Position + Vector3.new(0, -0.5, 0) or at
		local pos = at:Lerp(goal, e) + Vector3.new(0, math.sin(p * math.pi) * 4, 0)
		for _, part in m:GetChildren() do
			if part:IsA("BasePart") then part.Transparency = math.max(part.Transparency, e * 0.9) end
		end
		Spirits.animate(m, CFrame.new(pos) * CFrame.Angles(0, p * 12, 0), os.clock() * 15)
		if p >= 1 then
			conn:Disconnect()
			m:Destroy()
			burst(goal, ColorSequence.new(rar.color, Color3.new(1, 1, 1)), big and 50 or 22)
			ring(goal, 1, big and 12 or 6, rar.color, 0.35, false)
			punch(jarBox)
		end
	end)
	local text = info.name .. " в банке!"
	if coop > 1 then text ..= ("  Вместе x%d"):format(coop)
	elseif streak > 1 then text ..= "  Серия x" .. streak end
	if info.rarity == "legendary" then text = info.name .. "! Неси к алтарю" end
	if trackKind == kind then
		text ..= "  Цель поймана!"
		setTrack(nil)
	end
	showToast(text, 2.5)
end

-- раскрытие легендарного духа (~2 с): приглушённый алтарь, тёмный силуэт сбоку от игрока → пауза →
-- световое кольцо → модель в цвете целиком в кадре, плывёт и оставляет золотой след
local revealCC = Instance.new("ColorCorrectionEffect")
revealCC.Parent = Lighting
local function dimAltar(on)
	for _, p in World:GetChildren() do
		if p:IsA("BasePart") and (p.Name == "AltarGlow" or p.Name == "AltarPillar" or p.Name == "AltarBeam") then
			local base = p:GetAttribute("BaseT") or p.Transparency
			p:SetAttribute("BaseT", base)
			TweenService:Create(p, TweenInfo.new(0.25), { Transparency = on and math.max(base, 0.85) or base }):Play()
			local l = p:FindFirstChildOfClass("PointLight")
			if l then
				local b = l:GetAttribute("BaseB") or l.Brightness
				l:SetAttribute("BaseB", b)
				TweenService:Create(l, TweenInfo.new(0.25), { Brightness = on and b * 0.15 or b }):Play()
			end
		end
	end
end
local function flat(v)
	local f = Vector3.new(v.X, 0, v.Z)
	return f.Magnitude > 0.01 and f.Unit or Vector3.new(0, 0, -1)
end
local function revealLegendary(kind)
	local r = root()
	if not r then return end
	play("legendary")
	local cam = workspace.CurrentCamera
	local m = Spirits.Builders[kind]()
	Spirits.scale(m, 0.5)
	local orig = {}
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			orig[p] = { p.Color, p.Material, p.Transparency, p.Reflectance }
			if p.Name == "Fin" or p.Name == "Whisker" then
				p.Color, p.Material, p.Transparency = GOLD, Enum.Material.Neon, 0.35
			else
				p.Color, p.Material, p.Reflectance = Color3.fromRGB(8, 6, 12), Enum.Material.SmoothPlastic, 0
			end
		elseif p:IsA("Trail") or p:IsA("PointLight") then
			p.Enabled = false
		end
	end
	m.Parent = workspace
	dimAltar(true)
	TweenService:Create(revealCC, TweenInfo.new(0.2), { Brightness = -0.12, Saturation = -0.6 }):Play()
	local t0 = os.clock()
	local colored, ringed, restored = false, false, false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local cr = root() or r
		local right, fwd = flat(cam.CFrame.RightVector), flat(cam.CFrame.LookVector)
		local swim = t > 0.8 and (t - 0.8) * 2.2 or 0
		local pos = cr.Position + right * (7 - swim) + fwd * 3 + Vector3.new(0, 2.2 + math.sin(t * 3) * 0.25, 0)
		local pivot = CFrame.lookAt(pos, pos - right)
		Spirits.animate(m, pivot, t * (t > 0.8 and 5 or 1.5))
		if t > 0.5 and not ringed then
			ringed = true
			ring(pos, 2, 22, GOLD, 0.45, true)
		end
		if t > 0.7 and not colored then
			colored = true
			for p, o in orig do
				p.Material, p.Reflectance = o[2], o[4]
				TweenService:Create(p, TweenInfo.new(0.2), { Color = o[1], Transparency = o[3] }):Play()
			end
			for _, d in m:GetDescendants() do
				if d:IsA("Trail") or d:IsA("PointLight") then d.Enabled = true end
			end
			TweenService:Create(revealCC, TweenInfo.new(0.3), { Brightness = 0, Saturation = 0 }):Play()
		end
		if t > 1.75 and not restored then
			restored = true
			for p in orig do TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
			dimAltar(false)
		end
		if t > 2.05 then
			conn:Disconnect()
			m:Destroy()
		end
	end)
	showToast(Catalog.Kinds[kind].name .. " в коллекции!", 2.5)
end

------------------------------------------------------------------ обучение
local tut = { step = 0 }
local TUT_TEXT = {
	"1/4  Найди тень у площади и наведи на неё фонарь",
	"2/4  Подойди и удерживай ЛОВИТЬ, пока дух не окажется в банке",
	"3/4  Отнеси банку к алтарю (голубой луч) и сохрани улов",
	"4/4  Открой Атлас и возьми лиса спутником",
}
local arrowPart = Instance.new("Part")
arrowPart.Anchored, arrowPart.CanCollide, arrowPart.CanQuery, arrowPart.Transparency, arrowPart.Size = true, false, false, 1, Vector3.one
arrowPart.Parent = workspace
local arrowAtt = Instance.new("Attachment")
arrowAtt.Parent = arrowPart
local arrow = Instance.new("Beam")
arrow.Attachment1 = arrowAtt
arrow.Width0, arrow.Width1, arrow.FaceCamera, arrow.LightEmission = 0.6, 0.2, true, 1
arrow.Color = ColorSequence.new(Color3.fromRGB(140, 230, 255))
arrow.Transparency = NumberSequence.new(0.2, 0.6)
arrow.Enabled = false
arrow.Parent = arrowPart

local function setStep(n)
	tut.step = n
	if n >= 1 and n <= 4 then
		tutPanel.Text, tutPanel.Visible = TUT_TEXT[n], true
		punch(tutPanel)
	else
		tutPanel.Visible = false
	end
end
local function finishTutorial()
	if tut.step == 0 or tut.step == 5 then return end
	setStep(5)
	remotes.TutorialDone:FireServer()
	showToast("Обучение пройдено! Открой Атлас, выбери цель и выследи её", 4)
end
skipBtn.Activated:Connect(finishTutorial)

------------------------------------------------------------------ серверные события
local firstState = true
remotes.State.OnClientEvent:Connect(function(s)
	local keepSettings = not firstState and state.settings
	state = s
	if keepSettings then state.settings = keepSettings end
	if firstState then
		firstState = false
		applyAudio()
		applyReduced()
		if not s.tutorialDone then setStep(1) end
		if s.persistent == false then showToast("Сохранения недоступны в этом запуске", 3) end
	end
	refreshHUD()
	if tut.step == 4 and s.equipped then finishTutorial() end
end)

remotes.SaveResult.OnClientEvent:Connect(function(r)
	if not r.ok then
		showToast(r.msg)
		return
	end
	local legendary
	for _, k in r.firsts do
		if Catalog.Kinds[k].rarity == "legendary" then legendary = k end
	end
	if legendary then
		revealLegendary(legendary)
	else
		play("save")
		local cr = root()
		if cr then
			ring(cr.Position + Vector3.new(0, 5, 0), 12, 1, COLD, 0.5, false)
			burst(cr.Position + Vector3.new(0, 2, 0), ColorSequence.new(COLD, Color3.new(1, 1, 1)), 30)
		end
		local msg = ("Сдано духов: %d  +%d монет"):format(#r.kinds, r.coins)
		if r.dust > 0 then msg ..= (", +%d пыли"):format(r.dust) end
		if #r.firsts > 0 then msg ..= ("  Новых в Атласе: %d"):format(#r.firsts) end
		if not r.persisted then msg ..= " (без сохранения)" end
		showToast(msg, 3)
	end
	if #r.orders > 0 then
		task.delay(legendary and 2.3 or 1.6, function() showToast(("Заказ выполнен! (%d)"):format(#r.orders), 2.5) end)
	end
	if r.gardenOpened then
		task.delay(legendary and 4.6 or 3.2, function() showToast("Храмовый сад открыт! Иди на юг за канал", 4) end)
	end
	if tut.step == 3 then setStep(4) end
end)

remotes.Caught.OnClientEvent:Connect(function(kind, at, coop)
	catchEffect(kind, at, coop or 1)
	if tut.step == 2 or tut.step == 1 then setStep(3) end
end)

remotes.Hit.OnClientEvent:Connect(function(lost)
	play("oniHit")
	vignette.BackgroundTransparency = 0.55
	TweenService:Create(vignette, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	showToast(lost > 0 and ("Они разбил банку! Потеряно духов: " .. lost) or "Они попал! Банка была пуста", 3)
end)
remotes.Notice.OnClientEvent:Connect(function(text) showToast(text, 2.5) end)

------------------------------------------------------------------ визуал духов и следы
local visFolder = Instance.new("Folder")
visFolder.Name = "SpiritVisuals"
visFolder.Parent = workspace
local trailFolder = Instance.new("Folder")
trailFolder.Name = "Trails"
trailFolder.Parent = workspace
local visuals = {}

local TRAIL_SHAPE = {
	print = { size = Vector3.new(0.1, 0.7, 0.5), shape = Enum.PartType.Cylinder },
	dot = { size = Vector3.new(0.4, 0.4, 0.4), shape = Enum.PartType.Ball },
	scrap = { size = Vector3.new(0.6, 0.06, 0.4), shape = Enum.PartType.Block },
	ripple = { size = Vector3.new(0.08, 1.6, 1.6), shape = Enum.PartType.Cylinder },
	feather = { size = Vector3.new(0.25, 0.06, 0.9), shape = Enum.PartType.Block },
	ink = { size = Vector3.new(0.08, 1.0, 1.0), shape = Enum.PartType.Cylinder },
	flame = { size = Vector3.new(0.35, 0.35, 0.35), shape = Enum.PartType.Ball },
}
local function dropTrail(v, pos, dir)
	local tr = v.info.trail
	if not tr then return end
	local target = trackKind == v.kind
	if reducedFx and not target then return end
	local sh = TRAIL_SHAPE[tr.shape] or TRAIL_SHAPE.dot
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Shape, p.Size, p.Color = sh.shape, sh.size * (target and 1.6 or 1), tr.color
	p.Material = target and Enum.Material.Neon or Enum.Material.SmoothPlastic
	p.Transparency = target and 0.1 or 0.35
	local ground = Vector3.new(pos.X, 0.58, pos.Z)
	if sh.shape == Enum.PartType.Cylinder then
		p.CFrame = CFrame.new(ground) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), math.rad(90))
	elseif tr.shape == "dot" or tr.shape == "flame" then
		p.CFrame = CFrame.new(ground + Vector3.new(0, 0.3, 0))
	else
		p.CFrame = CFrame.new(ground) * CFrame.Angles(0, math.random() * 6.28, 0)
	end
	p.Parent = trailFolder
	local life = target and 14 or 8
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
	task.delay(life, function() p:Destroy() end)
end

local spiritSounds = {}
local function addAnchor(a)
	if not a:IsA("BasePart") then return end
	local kind = a:GetAttribute("Kind")
	local info = kind and Catalog.Kinds[kind]
	if not info then return end
	local v = { anchor = a, kind = kind, info = info, seed = math.random() * 10, lastDrop = 0, lastPos = a.Position }
	if info.move ~= "swim" then
		v.shadow = Spirits.buildShadow(Catalog.Rarity[info.rarity].shadow)
		v.shadow.Parent = visFolder
	end
	-- редкий дух слышен за углом
	local sid = Audio.Spirit[kind]
	if sid and sid ~= "" then
		local snd = makeSound(sid, sfxGroup, true, a)
		if snd then
			snd.RollOffMaxDistance, snd.RollOffMinDistance, snd.Volume = 60, 8, 0.7
			snd:Play()
			spiritSounds[a] = snd
		end
	end
	visuals[a] = v
end
local function removeAnchor(a)
	local v = visuals[a]
	if not v then return end
	visuals[a] = nil
	spiritSounds[a] = nil
	if v.shadow then v.shadow:Destroy() end
	if v.model then v.model:Destroy() end
end
spiritsFolder.ChildAdded:Connect(addAnchor)
spiritsFolder.ChildRemoved:Connect(removeAnchor)
for _, a in spiritsFolder:GetChildren() do addAnchor(a) end

-- спутники всех игроков
local followers = {}
local function updateFollowers(now)
	for _, p in Players:GetPlayers() do
		local kind = p:GetAttribute("Companion")
		local f = followers[p]
		if f and f.kind ~= kind then
			f.model:Destroy()
			followers[p], f = nil, nil
		end
		local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		if kind and kind ~= "" and Catalog.Kinds[kind] and r then
			if not f then
				local m = Spirits.Builders[kind]()
				Spirits.scale(m, Catalog.Kinds[kind].follow)
				m.Parent = visFolder
				f = { kind = kind, model = m, pivot = r.CFrame }
				followers[p] = f
			end
			local goal = r.CFrame * CFrame.new(3, 2.2 + math.sin(now * 2) * 0.4, 2)
			f.pivot = f.pivot:Lerp(goal, 0.1)
			Spirits.animate(f.model, f.pivot, now * Catalog.Kinds[kind].animSpeed * 0.6)
		elseif f then
			f.model:Destroy()
			followers[p] = nil
		end
	end
	for p, f in followers do
		if not p.Parent then
			f.model:Destroy()
			followers[p] = nil
		end
	end
end

-- они
local oniModel, oniT, oniWarned = nil, 0, false
local function updateOni(dt)
	local a = workspace:FindFirstChild("Oni")
	if not a then
		if oniModel then oniModel:Destroy() oniModel = nil end
		return
	end
	if not oniModel then
		oniModel = Spirits.buildOni()
		oniModel.Parent = visFolder
	end
	local st = a:GetAttribute("State")
	local pose = CFrame.new()
	if st == "walk" then
		oniT += dt * 6
		oniWarned = false
	elseif st == "windup" then
		pose = CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(math.sin(os.clock() * 40) * 0.15, 0, 0)
		oniT = math.pi / 2
		if not oniWarned then
			oniWarned = true
			play("oniWarn")
		end
	else
		pose = CFrame.new(0, 0, -1) * CFrame.Angles(math.rad(18), 0, 0)
		oniT = -math.pi / 2
	end
	Spirits.animate(oniModel, a.CFrame * pose, oniT)
end

------------------------------------------------------------------ фонарь, наведение, ловля
local highlight = Instance.new("Highlight")
highlight.FillTransparency, highlight.OutlineColor = 0.75, Color3.fromRGB(255, 230, 150)
highlight.Parent = visFolder

local target: BasePart? = nil
local aimTime, revealSent = 0, {}
local holding, holdId = false, nil

local function lanternRange()
	return Catalog.upgradeValue("range", plr:GetAttribute("RangeLvl") or 1)
end
local function lanternPower()
	return Catalog.upgradeValue("power", plr:GetAttribute("PowerLvl") or 1)
end

local function findTarget(r)
	local best, bestScore = nil, -math.huge
	local look = r.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local rng = lanternRange()
	local cone = math.cos(math.rad(40 + (plr:GetAttribute("RangeLvl") or 1) * 3))
	for a, v in visuals do
		local d = a.Position - r.Position
		local dist = d.Magnitude
		local lim = v.info.move == "swim" and rng + 8 or rng
		if dist < lim and (a.Position.Z > -73 or state.gardenOpen) then
			local fl = Vector3.new(d.X, 0, d.Z)
			local dot = fl.Magnitude > 0.5 and fl.Unit:Dot(flatLook) or 1
			if dot > cone or dist < 8 then
				local score = dot * 2 - dist / lim + (a:GetAttribute("Revealed") and 0.3 or 0) + (v.kind == trackKind and 0.8 or 0)
				if score > bestScore then best, bestScore = a, score end
			end
		end
	end
	return best
end

local function release()
	if holding then
		holding = false
		remotes.CatchHold:FireServer(nil)
	end
end

local currentDistrict = nil
local districtCC = Instance.new("ColorCorrectionEffect")
districtCC.Parent = Lighting
local wasMoon = false

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local r = root()

	-- таймер события и музыкальный слой Красной луны
	local moonActive = workspace:GetAttribute("MoonActive") == true
	local ends = workspace:GetAttribute("PhaseEnds")
	if ends then
		local left = math.max(0, math.floor(ends - workspace:GetServerTimeNow()))
		local timeStr = ("%d:%02d"):format(left // 60, left % 60)
		if moonActive then
			banner.Text = "КРАСНАЯ ЛУНА " .. timeStr
			banner.BackgroundColor3, banner.BackgroundTransparency = Color3.fromRGB(130, 15, 25), 0.1
		else
			banner.Text = "До Красной луны " .. timeStr
			banner.BackgroundColor3, banner.BackgroundTransparency = PANEL, 0.35
		end
	end
	if moonActive ~= wasMoon then
		wasMoon = moonActive
		if moonLayer then TweenService:Create(moonLayer, TweenInfo.new(3), { Volume = moonActive and 0.7 or 0 }):Play() end
		if moonActive then showToast("Красная луна! Редкие духи вышли, но по улицам ходит они", 3.5) end
	end

	-- духи: тени, модели, следы
	for a, v in visuals do
		local cf = a.CFrame
		local revealed = a:GetAttribute("Revealed")
		local dist = r and (cf.Position - r.Position).Magnitude or 0
		local near = dist < 170
		if v.shadow then
			v.shadow.CFrame = CFrame.new(cf.X, 0.62, cf.Z) * CFrame.Angles(0, now * 0.8, math.rad(90))
			v.shadow.Transparency = revealed and 0.88 or 0.3 + math.sin(now * 3 + v.seed) * 0.1
		end
		if revealed and not v.model then
			v.model = Spirits.Builders[v.kind]()
			v.model.Parent = visFolder
			play("reveal")
			ring(cf.Position + Vector3.new(0, 1, 0), 2, 10, Catalog.Rarity[v.info.rarity].color, 0.4, false)
			local pe = v.shadow and v.shadow:FindFirstChildOfClass("ParticleEmitter")
			if pe then pe:Emit(reducedFx and 6 or 20) pe.Rate = 3 end
		end
		if v.model and near then
			local t = now + v.seed
			Spirits.animate(v.model, cf * Spirits.Pose[v.kind](t), t * v.info.animSpeed)
		end
		if dist < 120 and now - v.lastDrop > 1.1 and (cf.Position - v.lastPos).Magnitude > 2 then
			dropTrail(v, cf.Position, cf.LookVector)
			v.lastDrop, v.lastPos = now, cf.Position
		end
	end
	updateFollowers(now)
	updateOni(dt)
	if not r then return end

	-- район: подпись и мягкий оттенок
	local d = Catalog.district(r.Position.Z)
	if d ~= currentDistrict then
		currentDistrict = d
		districtTitle.Text, districtTitle.Visible = Catalog.DistrictNames[d], true
		districtTitle.TextTransparency = 0
		TweenService:Create(districtTitle, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.6), { TextTransparency = 1 }):Play()
		TweenService:Create(districtCC, TweenInfo.new(1.5), { TintColor = Catalog.Districts[d].tint }):Play()
	end
	local atAltar = (r.Position - ALTAR_POS).Magnitude < 16

	-- выслеживание цели из Атласа
	local trackPos
	if trackKind then
		local best, bd = nil, math.huge
		for a, v in visuals do
			if v.kind == trackKind and (a.Position.Z > -73 or state.gardenOpen) then
				local dd = (a.Position - r.Position).Magnitude
				if dd < bd then best, bd = a, dd end
			end
		end
		local info = Catalog.Kinds[trackKind]
		if best then
			trackPos = best.Position
			trackL.Text = ("Цель: %s  %d м\nСлед: %s"):format(info.short, math.floor(bd), info.trail.text)
		else
			local places = Catalog.districtsOf(trackKind)
			local dc = places[1] and Catalog.Districts[places[1]]
			if info.moonOnly and not moonActive then
				trackL.Text = ("Цель: %s\nПоявится в Красную луну"):format(info.short)
			elseif dc and dc.locked and not state.gardenOpen then
				trackL.Text = ("Цель: %s\nСначала открой сад"):format(info.short)
			else
				trackL.Text = ("Цель: %s\nИщи: %s"):format(info.short, info.hint)
				trackPos = dc and dc.center
			end
		end
	end

	-- наведение фонаря
	local t = (holding and target and target.Parent) and target or findTarget(r)
	if t ~= target then target, aimTime = t, 0 end
	local lantern = plr.Character:FindFirstChild("Lantern")
	local weld = lantern and lantern:FindFirstChild("Weld")
	if weld then
		local goal = CFrame.new(0.9, 0.3, -0.9)
		if target and target.Parent then
			local localDir = r.CFrame:VectorToObjectSpace((target.Position - r.Position).Unit)
			goal = CFrame.lookAt(goal.Position, goal.Position + localDir)
		end
		weld.C0 = weld.C0:Lerp(goal, math.min(1, dt * 6))
	end

	highlight.Adornee, hint.Adornee = nil, nil
	local inRange = false
	if target and target.Parent and not atAltar then
		local v = visuals[target]
		local id = target:GetAttribute("SpiritId")
		local dist = (target.Position - r.Position).Magnitude
		local rar = v and Catalog.Rarity[v.info.rarity]
		if v and target:GetAttribute("Revealed") then
			highlight.Adornee = v.model
			highlight.OutlineColor = rar.color
			inRange = dist < Catalog.catchRange(v.kind)
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, 7, 0)
			local holders = target:GetAttribute("Holders") or 0
			if #state.jar >= state.cap then
				hintText.Text, hintText.TextColor3 = "Банка полна", Color3.fromRGB(255, 160, 120)
			elseif holders > 1 then
				hintText.Text, hintText.TextColor3 = ("Ловим вместе x%d"):format(holders), GOLD
			else
				hintText.Text = inRange and v.info.name or "Подойди ближе"
				hintText.TextColor3 = inRange and Color3.fromRGB(140, 255, 180) or Color3.new(1, 1, 1)
			end
			if tut.step == 1 then setStep(2) end
		elseif v then
			highlight.Adornee = v.shadow
			highlight.OutlineColor = rar.color
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, 3, 0)
			local need = rar.revealTime / lanternPower()
			aimTime += dt
			hintText.Text = "Свети" .. string.rep(".", math.clamp(math.floor(aimTime / need * 3), 0, 3))
			hintText.TextColor3 = Color3.fromRGB(200, 170, 255)
			if aimTime > need and not revealSent[id] then
				revealSent[id] = true
				remotes.Reveal:FireServer(id)
			end
		end
	end

	-- кнопка ловли (прогресс считает сервер)
	catchBtn.Visible = inRange or holding
	if holding then
		if not inRange or not target or target:GetAttribute("SpiritId") ~= holdId then
			release()
		else
			local p = target:GetAttribute("Progress") or 0
			fill.Size = UDim2.new(1, 0, math.clamp(p, 0, 1), 0)
			catchBtn.Rotation = reducedFx and 0 or math.sin(now * 40) * 4 * p
			local holders = target:GetAttribute("Holders") or 0
			catchBtn.Text = holders > 1 and ("x" .. holders) or "ЛОВИТЬ"
		end
	end
	if not holding then
		fill.Size = UDim2.new(1, 0, 0, 0)
		catchBtn.Rotation = 0
		catchBtn.Text = #state.jar >= state.cap and "ПОЛНА" or "ЛОВИТЬ"
	end

	-- указатель: обучение важнее цели охоты
	local goalPos
	if tut.step == 1 then
		local best, bd = nil, math.huge
		for a, v in visuals do
			if not a:GetAttribute("Revealed") and v.kind == "PaperFox" then
				local dd = (a.Position - r.Position).Magnitude
				if dd < bd then best, bd = a, dd end
			end
		end
		goalPos = best and best.Position
	elseif tut.step == 2 then
		goalPos = target and target.Parent and target.Position
	elseif tut.step == 3 or (#state.jar >= state.cap) then
		goalPos = ALTAR_POS + Vector3.new(0, 2, 0)
	elseif trackPos then
		goalPos = trackPos
	end
	local att = r:FindFirstChild("GuideAtt")
	if not att then
		att = Instance.new("Attachment")
		att.Name = "GuideAtt"
		att.Position = Vector3.new(0, -2, 0)
		att.Parent = r
	end
	arrow.Attachment0 = att
	arrow.Color = ColorSequence.new((tut.step >= 1 and tut.step <= 3 or #state.jar >= state.cap) and Color3.fromRGB(140, 230, 255) or ACCENT)
	arrow.Enabled = goalPos ~= nil and (goalPos - r.Position).Magnitude > 7
	if goalPos then arrowPart.Position = goalPos end
	if tut.step == 4 then
		atlasBtn.BackgroundColor3 = (math.floor(now * 3) % 2 == 0) and Color3.fromRGB(230, 160, 40) or Color3.fromRGB(70, 80, 160)
	else
		atlasBtn.BackgroundColor3 = Color3.fromRGB(70, 80, 160)
	end
end)

------------------------------------------------------------------ ввод
local function beginHold()
	local r = root()
	if not (r and target and target.Parent and target:GetAttribute("Revealed")) then return end
	if #state.jar >= state.cap then
		showToast("Банка полна — отнеси улов к алтарю")
		return
	end
	holding, holdId = true, target:GetAttribute("SpiritId")
	remotes.CatchHold:FireServer(holdId)
end
catchBtn.MouseButton1Down:Connect(beginHold)
catchBtn.MouseButton1Up:Connect(release)
catchBtn.MouseLeave:Connect(release)
remotes.Caught.OnClientEvent:Connect(function() holding = false end)
UserInputService.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.F then beginHold() end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.F then release() end
end)

------------------------------------------------------------------ диагностика (тест): FPS, время кадра на мосту, Bloom
if IS_TEST then
	local perf = label("", UDim2.new(1, -230, 0, 46), UDim2.new(0, 218, 0, 46), nil, 13)
	perf.BackgroundTransparency, perf.Visible = 0.4, false
	local bloomBtn = button("", UDim2.new(1, -230, 0, 96), UDim2.new(0, 218, 0, 26), Color3.fromRGB(60, 60, 80), nil, 14)
	bloomBtn.Visible = false
	local PRESETS = { 0, 0.1, 0.2, 0.35 }
	local bi = 3
	local function applyBloom()
		local b = Lighting:FindFirstChild("Bloom")
		if b then b.Enabled = PRESETS[bi] > 0 and not reducedFx b.Intensity = PRESETS[bi] end
		bloomBtn.Text = PRESETS[bi] > 0 and ("Bloom %.2f"):format(PRESETS[bi]) or "Bloom выкл"
	end
	bloomBtn.Activated:Connect(function()
		bi = bi % #PRESETS + 1
		applyBloom()
	end)
	local win, winN, winMax = 0, 0, 0
	local bridge = { night = { 0, 0, 0 }, moon = { 0, 0, 0 } }
	local function fmt(b)
		return b[2] > 30 and ("%.1f/%.0f"):format(b[1] / b[2] * 1000, b[3] * 1000) or "-"
	end
	RunService.Heartbeat:Connect(function(dt)
		local on = state.settings.diag == true
		perf.Visible, bloomBtn.Visible = on, on
		win += dt
		winN += 1
		winMax = math.max(winMax, dt)
		local r = root()
		if r and math.abs(r.Position.X) < 5 and r.Position.Z > -43 and r.Position.Z < -17 then
			local b = workspace:GetAttribute("MoonActive") and bridge.moon or bridge.night
			b[1] += dt
			b[2] += 1
			b[3] = math.max(b[3], dt)
		end
		if win >= 1 then
			if on then
				if bloomBtn.Text == "" then applyBloom() end
				perf.Text = ("Кадр %.1f мс (макс %.0f), %d FPS\nМост ср/макс: ночь %s | луна %s"):format(win / winN * 1000, winMax * 1000, winN, fmt(bridge.night), fmt(bridge.moon))
			end
			win, winN, winMax = 0, 0, 0
		end
	end)
end

showTab("atlas")
