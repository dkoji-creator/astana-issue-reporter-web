-- Spirit Catchers, клиент.
-- Интерфейс в стиле популярных симуляторов: колонка кнопок слева, валюты и уровень справа, событие сверху,
-- банка снизу. Атлас с 3D-превью и наградами за коллекцию, задания, магазин, ежедневный подарок, настройки.
-- Игровая часть: визуал духов и следов, выслеживание, ловля фонарём, эффекты, обучение.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Spirits = require(Shared:WaitForChild("Spirits"))
local Audio = require(Shared:WaitForChild("Config"):WaitForChild("Audio"))
local K = require(script.Parent:WaitForChild("UIKit"))
local T = K.T
local Prog = Catalog.Progress

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

local function root()
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ состояние
local state, trackKind
do
	state = {
		jar = {}, cap = 3, saved = {}, coins = 0, dust = 0, levels = { jar = 1, range = 1, power = 1 },
		tutorialDone = true, gardenOpen = false, distinct = 0, orders = {},
		settings = { music = 0.6, sfx = 0.8, reduced = false, diag = false },
		xp = 0, level = 1, xpNext = 35, daily = { last = 0, streak = 0 }, dailyReady = false,
		skins = { classic = true }, skin = "classic", milestones = {},
	}
	trackKind = nil

end
------------------------------------------------------------------ звук
local sfxGroup, makeSound, moonLayer, play, applyAudio
do
	local musicGroup = K.make("SoundGroup", { Name = "Music", Volume = 0.6 }, SoundService)
	sfxGroup = K.make("SoundGroup", { Name = "Sfx", Volume = 0.8 }, SoundService)
	local allSounds = {}
	makeSound = function(id, group, looped, parent, volume)
		if not id or id == "" then return nil end
		local s = K.make("Sound", { SoundId = id, Looped = looped == true, SoundGroup = group, Volume = volume or 0.7 }, parent or SoundService)
		table.insert(allSounds, s)
		return s
	end
	local music = makeSound(Audio.Music.lantern, musicGroup, true, nil, 0.55)
	moonLayer = music -- в Красную луну та же прелюдия звучит медленнее и ниже
	local sfx = {}
	for k, id in Audio.Sfx do
		sfx[k] = makeSound(id, sfxGroup, false, nil, 0.8)
	end
	task.spawn(function()
		pcall(function() ContentProvider:PreloadAsync(allSounds) end)
		if music then music:Play() end
	end)
	play = function(name)
		local s = sfx[name]
		if s then s:Play() end
	end
	K.onClick(function() play("click") end)
	applyAudio = function()
		musicGroup.Volume = state.settings.music
		sfxGroup.Volume = state.settings.sfx
	end

end
------------------------------------------------------------------ корень интерфейса
local gui, uiScale, hud
do
	gui = K.make("ScreenGui", { Name = "SpiritHUD", ResetOnSpawn = false, IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, plr:WaitForChild("PlayerGui"))
	uiScale = K.make("UIScale", {}, gui)
	local function rescale()
		local cam = workspace.CurrentCamera
		if cam then uiScale.Scale = math.clamp(cam.ViewportSize.Y / 420, 0.72, 1.3) end
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	hud = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, gui)

end
------------------------------------------------------------------ HUD: левая колонка
local btnAtlas, btnQuests, btnShop, btnGift, btnTeleport, btnSettings, btnAdmin, btnPower
do
	local leftCol = K.make("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 10), Size = UDim2.fromOffset(136, 280), BackgroundTransparency = 1 }, hud)
	K.make("UIGridLayout", { CellSize = UDim2.fromOffset(62, 62), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }, leftCol)
	btnAtlas = K.iconButton(leftCol, "atlas", "Атлас", T.blue)
	btnQuests = K.iconButton(leftCol, "quests", "Задания", T.orange)
	btnShop = K.iconButton(leftCol, "shop", "Магазин", T.red)
	btnGift = K.iconButton(leftCol, "gift", "Подарок", T.green)
	btnTeleport = K.iconButton(leftCol, "portal", "Телепорт", T.purple)
	btnSettings = K.iconButton(leftCol, "settings", "Опции", Color3.fromRGB(120, 125, 150))
	btnAdmin = K.iconButton(leftCol, "admin", "Админ", Color3.fromRGB(230, 160, 30))
	btnPower = K.iconButton(leftCol, "level", "Сила", Color3.fromRGB(240, 180, 40))
	btnAdmin.Visible = false
	for i, b in { btnAtlas, btnPower, btnQuests, btnShop, btnGift, btnTeleport, btnSettings, btnAdmin } do b.LayoutOrder = i end

end
------------------------------------------------------------------ HUD: справа валюты и уровень
local coinPill, coinL, dustPill, dustL, luckPill, luckL, luckSub, levelPill
local levelL, _, xpFill
do
	local rightCol = K.make("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 58), Size = UDim2.fromOffset(170, 190), BackgroundTransparency = 1 }, hud)
	K.make("UIListLayout", { Padding = UDim.new(0, 10), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, rightCol)
	coinPill, coinL = K.pill(rightCol, "coin", Color3.fromRGB(230, 170, 30), 160)
	dustPill, dustL = K.pill(rightCol, "dust", T.purple, 160)
	coinPill.LayoutOrder, dustPill.LayoutOrder = 1, 2
	luckPill = K.make("TextButton", { Size = UDim2.fromOffset(160, 40), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, LayoutOrder = 4 }, rightCol)
	K.corner(luckPill, UDim.new(1, 0))
	K.stroke(luckPill, T.ink, 3)
	K.gradient(luckPill, Color3.fromRGB(110, 230, 130), Color3.fromRGB(40, 130, 70))
	K.icon(luckPill, "luck", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(-12, -4) })
	luckL = K.text(luckPill, "Удача x1", { Size = UDim2.new(1, -46, 0, 20), Position = UDim2.fromOffset(38, 2), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17 })
	luckSub = K.text(luckPill, "", { Size = UDim2.new(1, -46, 0, 14), Position = UDim2.fromOffset(38, 22), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 11, Font = Enum.Font.GothamBold, StrokeThickness = 1 })
	levelPill = K.make("Frame", { Size = UDim2.fromOffset(160, 40), BackgroundColor3 = T.panel, LayoutOrder = 3 }, rightCol)
	K.corner(levelPill, UDim.new(1, 0))
	K.stroke(levelPill, T.ink, 3)
	K.icon(levelPill, "level", { Size = UDim2.fromOffset(46, 46), Position = UDim2.fromOffset(-12, -4) })
	levelL = K.text(levelPill, "Ур. 1", { Size = UDim2.new(1, -46, 0, 18), Position = UDim2.fromOffset(38, 3), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16 })
	_, xpFill = K.bar(levelPill, T.gold, { Size = UDim2.new(1, -50, 0, 10), Position = UDim2.fromOffset(38, 24) })

end
------------------------------------------------------------------ HUD: событие, цель, уведомления
local eventPill, eventGrad, eventL, trackPill, trackL, showToast
do
	eventPill = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 10), Size = UDim2.fromOffset(250, 38), BackgroundColor3 = Color3.new(1, 1, 1) }, hud)
	K.corner(eventPill, UDim.new(1, 0))
	K.stroke(eventPill, T.ink, 3)
	eventGrad = K.gradient(eventPill, Color3.fromRGB(70, 70, 110), Color3.fromRGB(40, 40, 70))
	K.icon(eventPill, "moon", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(-10, -4) })
	eventL = K.text(eventPill, "", { Size = UDim2.new(1, -48, 1, -10), Position = UDim2.fromOffset(38, 5), MaxText = 20 })

	trackPill = K.make("TextButton", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(310, 46), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, Visible = false }, hud)
	K.corner(trackPill, UDim.new(0, 14))
	K.stroke(trackPill, T.ink, 3)
	K.gradient(trackPill, Color3.fromRGB(255, 160, 80), Color3.fromRGB(200, 90, 40))
	K.icon(trackPill, "target", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(4, 3) })
	trackL = K.text(trackPill, "", { Size = UDim2.new(1, -54, 1, -8), Position = UDim2.fromOffset(48, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 16, Font = Enum.Font.GothamBold })

	local toast = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108), Size = UDim2.fromOffset(440, 40), BackgroundColor3 = T.panel, Visible = false }, hud)
	K.corner(toast, UDim.new(0, 12))
	K.stroke(toast, T.ink, 3)
	local toastL = K.text(toast, "", { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxText = 18, Font = Enum.Font.GothamBold })
	local toastSeq = 0
	showToast = function(text, secs, color)
		toastSeq += 1
		local my = toastSeq
		toastL.Text = text
		toast.BackgroundColor3 = color or T.panel
		toast.Visible = true
		K.pop(toast)
		task.delay(secs or 2.4, function()
			if toastSeq == my then toast.Visible = false end
		end)
	end

	luckPill.Activated:Connect(function()
		K.bounce(luckPill)
		local parts = state.luckParts or {}
		showToast(#parts > 0 and ("Удача: " .. table.concat(parts, ", ")) or "Удача растёт с уровнем, от зелий, Удачи ловца и в Красную луну", 4, Color3.fromRGB(40, 110, 60))
	end)

end
------------------------------------------------------------------ HUD: банка снизу по центру
local jarPanel, jarL, jarNames, _, jarFill, tutPanel, tutL, skipBtn
local districtTitle, catchBtn, fill, catchL, mini, zoneF, markerF, markerStroke
local progFill, vignette, hint, hintText, floatReward
do
	jarPanel = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), Size = UDim2.fromOffset(320, 50), BackgroundColor3 = T.panel }, hud)
	K.corner(jarPanel, UDim.new(0, 14))
	K.stroke(jarPanel, T.ink, 3)
	K.icon(jarPanel, "jar", { Size = UDim2.fromOffset(56, 56), Position = UDim2.fromOffset(-14, -10) })
	jarL = K.text(jarPanel, "Банка 0/3", { Size = UDim2.new(0.5, -40, 0, 22), Position = UDim2.fromOffset(46, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
	jarNames = K.text(jarPanel, "пусто", { Size = UDim2.new(0.55, 0, 0, 18), Position = UDim2.new(0.42, 0, 0, 6), TextXAlignment = Enum.TextXAlignment.Right, MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub })
	_, jarFill = K.bar(jarPanel, T.cold, { Size = UDim2.new(1, -60, 0, 12), Position = UDim2.fromOffset(46, 30) })

	tutPanel = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -72), Size = UDim2.fromOffset(460, 52), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false }, hud)
	K.corner(tutPanel, UDim.new(0, 14))
	K.stroke(tutPanel, T.ink, 3)
	K.gradient(tutPanel, Color3.fromRGB(70, 140, 220), Color3.fromRGB(40, 80, 160))
	tutL = K.text(tutPanel, "", { Size = UDim2.new(1, -110, 1, -10), Position = UDim2.fromOffset(10, 5), MaxText = 17, Font = Enum.Font.GothamBold })
	skipBtn = K.button(tutPanel, "Пропуск", Color3.fromRGB(90, 90, 120), { Size = UDim2.fromOffset(90, 34), Position = UDim2.new(1, -98, 0, 9), MaxText = 14 })

	districtTitle = K.text(hud, "", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 52), Size = UDim2.fromOffset(320, 22), MaxText = 16, Font = Enum.Font.GothamBold, StrokeThickness = 2 })

	-- кнопка ловли: рядом со стандартной кнопкой прыжка, видна только рядом с доступным духом
	catchBtn = K.make("TextButton", { AnchorPoint = Vector2.new(1, 1), Size = UDim2.fromOffset(100, 100), Position = UDim2.new(1, -180, 1, -140), BackgroundColor3 = Color3.new(1, 1, 1), Text = "", AutoButtonColor = false, Visible = false }, gui)
	K.corner(catchBtn, UDim.new(1, 0))
	K.stroke(catchBtn, T.ink, 4)
	K.gradient(catchBtn, Color3.fromRGB(120, 240, 160), Color3.fromRGB(40, 170, 90))
	fill = K.make("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 0), AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1) }, catchBtn)
	K.corner(fill, UDim.new(1, 0))
	K.icon(catchBtn, "paw", { Size = UDim2.fromScale(0.5, 0.5), Position = UDim2.fromScale(0.25, 0.08) })
	catchL = K.text(catchBtn, "ЛОВИТЬ", { Size = UDim2.new(0.9, 0, 0.3, 0), Position = UDim2.fromScale(0.05, 0.6), MaxText = 18 })

	-- мини-игра ловли: держи кнопку, чтобы зелёная зона удерживала метку духа
	mini = K.make("Frame", { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -292, 1, -140), Size = UDim2.fromOffset(66, 230), BackgroundColor3 = T.panel, Visible = false }, gui)
	K.corner(mini, UDim.new(0, 14))
	K.stroke(mini, T.ink, 3)
	local track = K.make("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.new(0, 32, 1, -16), BackgroundColor3 = Color3.fromRGB(20, 28, 50) }, mini)
	K.corner(track, UDim.new(0, 10))
	zoneF = K.make("Frame", { Size = UDim2.fromScale(1, 0.3), Position = UDim2.fromScale(0, 0.4), BackgroundColor3 = Color3.fromRGB(120, 240, 160), BackgroundTransparency = 0.3 }, track)
	K.corner(zoneF, UDim.new(0, 8))
	K.stroke(zoneF, Color3.new(1, 1, 1), 2)
	markerF = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(30, 30), Position = UDim2.fromScale(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 3 }, track)
	K.corner(markerF, UDim.new(1, 0))
	markerStroke = K.stroke(markerF, T.ink, 3)
	K.icon(markerF, "paw", { Size = UDim2.fromScale(0.8, 0.8), Position = UDim2.fromScale(0.1, 0.1), ZIndex = 4 })
	local progBack = K.make("Frame", { Position = UDim2.new(1, -20, 0, 8), Size = UDim2.new(0, 12, 1, -16), BackgroundColor3 = T.ink }, mini)
	K.corner(progBack, UDim.new(1, 0))
	progFill = K.make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = T.gold }, progBack)
	K.corner(progFill, UDim.new(1, 0))

	vignette = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, BackgroundColor3 = Color3.fromRGB(200, 0, 0) }, gui)

	hint = K.make("BillboardGui", { Size = UDim2.fromOffset(180, 34), AlwaysOnTop = true }, gui)
	hintText = K.text(hint, "", { MaxText = 24 })

	-- всплывающие награды, летящие к валюте
	floatReward = function(iconKey, text, toPill)
		local f = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(160, 44), BackgroundTransparency = 1 }, gui)
		K.icon(f, iconKey, { Size = UDim2.fromOffset(44, 44) })
		local l = K.text(f, text, { Size = UDim2.new(1, -48, 1, 0), Position = UDim2.fromOffset(48, 0), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 28, TextColor3 = T.gold })
		local sc = K.make("UIScale", { Scale = 0.3 }, f)
		TweenService:Create(sc, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.1 }):Play()
		task.delay(0.7, function()
			local target = toPill and (toPill.AbsolutePosition + toPill.AbsoluteSize / 2) / uiScale.Scale or nil
			local tw = TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Position = target and UDim2.fromOffset(target.X, target.Y) or UDim2.fromScale(0.5, 0.3),
			})
			TweenService:Create(sc, TweenInfo.new(0.5), { Scale = 0.5 }):Play()
			TweenService:Create(l, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
			tw:Play()
			tw.Completed:Wait()
			if toPill then K.pop(toPill) end
			f:Destroy()
		end)
	end

end
------------------------------------------------------------------ окно: Атлас
local atlasW, atlasBody, _, collectFill, spiritGrid, cards, setTrack, refreshAtlas
do
	atlasW, atlasBody = K.window(gui, "Атлас духов", "atlas", T.blue)
	local atlasTop = K.make("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundTransparency = 1 }, atlasBody)
	local collectL = K.text(atlasTop, "", { Size = UDim2.new(0.46, 0, 0, 28), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 22 })
	_, collectFill = K.bar(atlasTop, T.gold, { Size = UDim2.new(0.46, 0, 0, 16), Position = UDim2.fromOffset(0, 36) })
	-- одна понятная карточка «следующая награда коллекции» вместо ряда одинаковых плашек
	local mileCard = K.panel(atlasTop, { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0.5, 0, 1, -4), BackgroundColor3 = Color3.fromRGB(58, 50, 34) })
	K.icon(mileCard, "trophy", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 7) })
	local mileTitle = K.text(mileCard, "", { Size = UDim2.new(0.62, -56, 0, 24), Position = UDim2.fromOffset(54, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, TextColor3 = T.gold })
	local mileSub = K.text(mileCard, "", { Size = UDim2.new(0.62, -56, 0, 20), Position = UDim2.fromOffset(54, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 15, Font = Enum.Font.GothamBold, StrokeThickness = 1 })
	local mileB, mileBL = K.button(mileCard, "", T.green, { Size = UDim2.new(0.38, -8, 1, -12), Position = UDim2.new(0.62, 2, 0, 6), MaxText = 16 })
	local mileIndex = nil
	mileB.Activated:Connect(function()
		if not mileIndex then return end
		local r = remotes.ClaimMilestone:InvokeServer(mileIndex)
		if r and not r.ok and r.msg then showToast(r.msg) end
	end)
	local atlasTabs = K.make("Frame", { Position = UDim2.fromOffset(0, 66), Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, atlasBody)
	K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, atlasTabs)
	local tabSpirits = K.button(atlasTabs, "Духи", T.blue, { Size = UDim2.fromOffset(120, 34), MaxText = 16 })
	local tabTiers = K.button(atlasTabs, "Тир-лист", T.panel2, { Size = UDim2.fromOffset(120, 34), MaxText = 16 })
	local tabAch = K.button(atlasTabs, "Достижения", T.panel2, { Size = UDim2.fromOffset(140, 34), MaxText = 16 })
	local tabWorlds = K.button(atlasTabs, "Миры", T.panel2, { Size = UDim2.fromOffset(120, 34), MaxText = 16, Visible = false })
	spiritGrid = K.scroll(atlasBody, { Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 1, -106) })
	K.make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 262), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, spiritGrid)
	K.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8) }, spiritGrid)
	local worldList = K.scroll(atlasBody, { Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 1, -106), Visible = false })
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, worldList)
	local tierList = K.scroll(atlasBody, { Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 1, -106), Visible = false })
	K.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, tierList)
	-- достижения
	local achList = K.scroll(atlasBody, { Position = UDim2.fromOffset(0, 106), Size = UDim2.new(1, 0, 1, -106), Visible = false })
	K.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, achList)
	local achRows = {}
	for i, id in Prog.AchievementOrder do
		local a = Prog.Achievements[id]
		local f = K.panel(achList, { Size = UDim2.new(1, -10, 0, 76), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.icon(f, "trophy", { Size = UDim2.fromOffset(50, 50), Position = UDim2.fromOffset(8, 12) })
		K.text(f, a.name, { Size = UDim2.new(0.6, -66, 0, 24), Position = UDim2.fromOffset(64, 4), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19 })
		local parts = {}
		if a.coins then table.insert(parts, a.coins .. " монет") end
		if a.dust then table.insert(parts, a.dust .. " пыли") end
		if a.skin then table.insert(parts, "фонарь «" .. Prog.Skins[a.skin].name .. "»") end
		K.text(f, a.desc .. "   Награда: " .. table.concat(parts, ", "), { Size = UDim2.new(0.6, -66, 0, 28), Position = UDim2.fromOffset(64, 28), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 228, 245), TextWrapped = true, StrokeThickness = 1 })
		local _, bar = K.bar(f, T.gold, { Size = UDim2.new(0.6, -66, 0, 10), Position = UDim2.fromOffset(64, 60) })
		local b, bl = K.button(f, "", T.green, { Size = UDim2.new(0.36, -8, 1, -18), Position = UDim2.new(0.62, 0, 0, 9), MaxText = 18 })
		b.Activated:Connect(function()
			local r = remotes.ClaimAchievement:InvokeServer(id)
			if r and r.ok then
				play("legendary")
				showToast("Достижение: " .. a.name .. "!", 2.5, Color3.fromRGB(150, 110, 20))
			elseif r and r.msg then
				showToast(r.msg)
			end
		end)
		achRows[id] = { bar = bar, b = b, bl = bl, need = a.need }
	end
	local function refreshAch()
		for id, r in achRows do
			local cur = (state.achCur and state.achCur[id]) or 0
			local done = state.achDone and state.achDone[id]
			r.bar.Size = UDim2.fromScale(math.clamp(cur / r.need, 0, 1), 1)
			if done then
				r.bl.Text = "Получено"
				K.recolor(r.b, Color3.fromRGB(80, 80, 95))
			elseif cur >= r.need then
				r.bl.Text = "Забрать!"
				K.recolor(r.b, T.green)
			else
				r.bl.Text = ("%d/%d"):format(math.floor(math.min(cur, r.need)), r.need)
				K.recolor(r.b, Color3.fromRGB(70, 70, 90))
			end
		end
	end
	local atlasPages = { { tabSpirits, spiritGrid }, { tabTiers, tierList }, { tabAch, achList }, { tabWorlds, worldList } }
	for _, pair in atlasPages do
		pair[1].Activated:Connect(function()
			for _, other in atlasPages do
				other[2].Visible = other == pair
				K.recolor(other[1], other == pair and T.blue or T.panel2)
			end
		end)
	end
	-- тир-лист: строка на каждую редкость, плашки видов (цветные — пойманы)
	local tierChips = {}
	for i = #Catalog.RarityOrder, 1, -1 do
		local rk = Catalog.RarityOrder[i]
		local rar = Catalog.Rarity[rk]
		local row = K.panel(tierList, { Size = UDim2.new(1, -10, 0, 66), LayoutOrder = #Catalog.RarityOrder - i, BackgroundColor3 = T.panel2 })
		local tag = K.make("Frame", { Size = UDim2.new(0, 120, 1, -10), Position = UDim2.fromOffset(5, 5), BackgroundColor3 = Color3.new(1, 1, 1) }, row)
		K.corner(tag, UDim.new(0, 10))
		K.gradient(tag, K.lighten(rar.color, 0.2), K.darken(rar.color, 0.25))
		K.text(tag, rar.name, { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), MaxText = 18 })
		local chips = K.make("Frame", { Size = UDim2.new(1, -140, 1, -10), Position = UDim2.fromOffset(132, 5), BackgroundTransparency = 1 }, row)
		K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center }, chips)
		for _, kind in Catalog.Order do
			if Catalog.Kinds[kind].rarity == rk then
				local chip = K.make("Frame", { Size = UDim2.new(0.25, -6, 1, 0), BackgroundColor3 = Color3.fromRGB(40, 38, 60) }, chips)
				K.corner(chip, UDim.new(0, 8))
				K.stroke(chip, rar.color, 2)
				local l = K.text(chip, Catalog.Kinds[kind].name, { Size = UDim2.new(1, -6, 0.58, 0), Position = UDim2.fromOffset(3, 2), MaxText = 15, StrokeThickness = 1 })
				local v = K.text(chip, "", { Size = UDim2.new(1, -6, 0.38, -2), Position = UDim2.new(0, 3, 0.6, 0), MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
				tierChips[kind] = { chip = chip, name = l, vars = v }
			end
		end
	end
	do
		local row = K.panel(tierList, { Size = UDim2.new(1, -10, 0, 54), LayoutOrder = -1, BackgroundColor3 = Color3.fromRGB(30, 40, 60) })
		K.text(row, "Шансы", { Size = UDim2.new(0, 110, 1, -10), Position = UDim2.fromOffset(8, 5), MaxText = 16, TextColor3 = T.gold })
		local chips = K.make("Frame", { Size = UDim2.new(1, -130, 1, -10), Position = UDim2.fromOffset(124, 5), BackgroundTransparency = 1 }, row)
		K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center }, chips)
		for i = 2, #Catalog.VariantOrder do
			local vc = Catalog.Variants[Catalog.VariantOrder[i]]
			local chip = K.make("Frame", { Size = UDim2.new(1 / (#Catalog.VariantOrder - 1), -4, 1, 0), BackgroundColor3 = K.darken(vc.color, 0.5) }, chips)
			K.corner(chip, UDim.new(0, 8))
			K.text(chip, vc.name, { Size = UDim2.new(1, -4, 0.55, 0), Position = UDim2.fromOffset(2, 1), MaxText = 11, StrokeThickness = 1 })
			K.text(chip, ("1 к %d"):format(math.floor(1 / vc.chance + 0.5)), { Size = UDim2.new(1, -4, 0.4, 0), Position = UDim2.new(0, 2, 0.58, 0), MaxText = 10, Font = Enum.Font.GothamBold, StrokeThickness = 1 })
		end
	end
	local function refreshTiers()
		for kind, t in tierChips do
			local n = state.saved[kind] or 0
			local got = 0
			for _ in (state.variants and state.variants[kind]) or {} do got += 1 end
			t.chip.BackgroundColor3 = n > 0 and K.darken(Catalog.Rarity[Catalog.Kinds[kind].rarity].color, 0.55) or Color3.fromRGB(40, 38, 60)
			t.name.TextColor3 = n > 0 and T.text or T.sub
			t.vars.Text = n > 0 and ("%d/%d вида"):format(got, #Catalog.VariantOrder) or "не найден"
		end
	end
	for i, key in Catalog.Worlds.Order do
		local w = Catalog.Worlds.Worlds[key]
		local f = K.panel(worldList, { Size = UDim2.new(1, -10, 0, 96), LayoutOrder = i, BackgroundColor3 = w.active and Color3.fromRGB(46, 58, 96) or Color3.fromRGB(36, 34, 54) })
		if not w.active then K.icon(f, "lock", { Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 8) }) end
		K.text(f, w.name .. (w.active and "  - открыт" or "  - скоро"), { Size = UDim2.new(1, -70, 0, 26), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, TextColor3 = w.active and T.gold or T.sub })
		K.text(f, w.blurb .. "\nГлавная цель: " .. w.star, { Size = UDim2.new(1, -24, 0, 56), Position = UDim2.fromOffset(12, 34), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextWrapped = true, StrokeThickness = 1 })
	end

	cards = {}
	setTrack = function(kind)
		trackKind = kind
		trackPill.Visible = kind ~= nil
		if kind then
			local info = Catalog.Kinds[kind]
			showToast("Цель: " .. info.name .. ". След: " .. info.trail.text, 3, Color3.fromRGB(150, 80, 30))
		end
	end
	trackPill.Activated:Connect(function()
		setTrack(nil)
		showToast("Охота отменена", 1.5)
	end)

	local function silhouette(m)
		for _, p in m:GetDescendants() do
			if p:IsA("BasePart") then
				p.Color, p.Material, p.Transparency = Color3.fromRGB(20, 18, 30), Enum.Material.SmoothPlastic, math.min(p.Transparency, 0.2)
			elseif p:IsA("Light") or p:IsA("Trail") then
				p.Enabled = false
			end
		end
	end

	local function buildCard(i, kind)
		local info = Catalog.Kinds[kind]
		local rar = Catalog.Rarity[info.rarity]
		local c = { kind = kind }
		local f = K.panel(spiritGrid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
		f:FindFirstChildOfClass("UIStroke").Color = rar.color
		c.frame = f
		local vpHolder = K.make("Frame", { Size = UDim2.new(1, -8, 0, 112), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1) }, f)
		K.corner(vpHolder, UDim.new(0, 10))
		K.gradient(vpHolder, K.darken(rar.color, 0.35), K.darken(rar.color, 0.75))
		c.vpHolder = vpHolder
		-- редкость — цветной ярлык поверх превью, количество — справа
		local rTag = K.make("Frame", { Size = UDim2.fromOffset(120, 24), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = rar.color, ZIndex = 3 }, vpHolder)
		K.corner(rTag, UDim.new(1, 0))
		K.stroke(rTag, T.ink, 2)
		c.rar = K.text(rTag, rar.name, { Size = UDim2.new(1, -10, 1, -4), Position = UDim2.fromOffset(5, 2), MaxText = 14, ZIndex = 3 })
		c.count = K.text(vpHolder, "", { Size = UDim2.fromOffset(60, 24), Position = UDim2.new(1, -66, 0, 6), MaxText = 18, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, TextColor3 = T.gold })
		c.name = K.text(f, info.name, { Size = UDim2.new(1, -12, 0, 26), Position = UDim2.fromOffset(6, 120), MaxText = 19 })
		c.info = K.text(f, "", { Size = UDim2.new(1, -14, 0, 44), Position = UDim2.fromOffset(7, 148), MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 228, 245), TextWrapped = true, StrokeThickness = 1 })
		-- разновидности: точки + понятная подпись
		local dots = K.make("Frame", { Size = UDim2.new(0.55, 0, 0, 14), Position = UDim2.fromOffset(8, 196), BackgroundTransparency = 1 }, f)
		K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), VerticalAlignment = Enum.VerticalAlignment.Center }, dots)
		c.dots = {}
		for _, vk in Catalog.VariantOrder do
			local d = K.make("Frame", { Size = UDim2.fromOffset(13, 13), BackgroundColor3 = T.ink }, dots)
			K.corner(d, UDim.new(1, 0))
			K.stroke(d, Color3.fromRGB(120, 120, 150), 1)
			c.dots[vk] = d
		end
		c.varL = K.text(f, "", { Size = UDim2.new(0.45, -10, 0, 16), Position = UDim2.new(0.55, 2, 0, 195), MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextXAlignment = Enum.TextXAlignment.Right, StrokeThickness = 1 })
		local trackB, trackBL = K.button(f, "Выследить", T.orange, { Size = UDim2.new(0.5, -7, 0, 38), Position = UDim2.new(0, 5, 1, -44), MaxText = 15 })
		local equipB, equipBL = K.button(f, "Спутник", T.pink, { Size = UDim2.new(0.5, -7, 0, 38), Position = UDim2.new(0.5, 2, 1, -44), MaxText = 15 })
		c.trackL, c.equip, c.equipL = trackBL, equipB, equipBL
		trackB.Activated:Connect(function()
			setTrack(trackKind ~= kind and kind or nil)
			K.close(atlasW)
		end)
		equipB.Activated:Connect(function()
			remotes.Equip:InvokeServer(state.equipped ~= kind and kind or nil)
		end)
		cards[kind] = c
	end
	for i, kind in Catalog.Order do buildCard(i, kind) end

	local function refreshCard(c)
		local info = Catalog.Kinds[c.kind]
		local n = state.saved[c.kind] or 0
		local known = n > 0
		if c.known ~= known then
			c.known = known
			if c.vp then c.vp:Destroy() end
			local m = Spirits.Builders[c.kind]()
			if not known then silhouette(m) end
			c.vp, c.setAngle = K.viewport(c.vpHolder, m)
		end
		c.name.TextColor3 = known and T.text or T.sub
		c.name.Text = known and info.name or "???"
		c.count.Text = known and ("x" .. n) or ""
		c.info.Text = known and info.habit or ("Где искать: " .. info.hint)
		c.trackL.Text = trackKind == c.kind and "Цель" or "Выследить"
		c.equip.Visible = known
		c.equipL.Text = state.equipped == c.kind and "Снять" or "Спутник"
		local got = (state.variants and state.variants[c.kind]) or {}
		local gotN = 0
		for vk, d in c.dots do
			d.BackgroundColor3 = got[vk] and Catalog.Variants[vk].color or T.ink
			if got[vk] then gotN += 1 end
		end
		c.varL.Text = known and ("%d/%d вида"):format(gotN, #Catalog.VariantOrder) or "не пойман"
	end

	refreshAtlas = function()
		for _, c in cards do refreshCard(c) end
		refreshTiers()
		refreshAch()
		local total = #Catalog.Order
		collectL.Text = ("Собрано %d/%d видов"):format(state.distinct, total)
		collectFill.Size = UDim2.fromScale(math.clamp(state.distinct / total, 0, 1), 1)
		mileIndex = nil
		for i, m in Prog.Milestones do
			if not state.milestones[tostring(i)] then mileIndex = i break end
		end
		if mileIndex then
			local m = Prog.Milestones[mileIndex]
			local parts = {}
			if m.coins then table.insert(parts, m.coins .. " монет") end
			if m.dust then table.insert(parts, m.dust .. " пыли") end
			if m.skin then table.insert(parts, "фонарь") end
			local ready = state.distinct >= m.need
			mileTitle.Text = ("Награда за %d видов"):format(m.need)
			mileSub.Text = table.concat(parts, " + ")
			mileBL.Text = ready and "Забрать!" or ("%d/%d"):format(state.distinct, m.need)
			K.recolor(mileB, ready and T.green or Color3.fromRGB(80, 80, 100))
		else
			mileTitle.Text = "Все награды получены"
			mileSub.Text = "Ищи редкие разновидности"
			mileBL.Text = "Готово"
			K.recolor(mileB, Color3.fromRGB(80, 80, 100))
		end
	end

end
------------------------------------------------------------------ окно: Задания
local questW, questBody, refreshQuests
do
	questW, questBody = K.window(gui, "Задания алтаря", "quests", T.orange, 0.7, 0.72)
	local questList = K.scroll(questBody)
	K.make("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, questList)
	local questRows = {}
	for i = 1, Catalog.OrderSlots do
		local f = K.panel(questList, { Size = UDim2.new(1, -10, 0, 92), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.icon(f, "quests", { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(8, 14) })
		local title = K.text(f, "", { Size = UDim2.new(0.6, -80, 0, 24), Position = UDim2.fromOffset(76, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		local _, bar = K.bar(f, T.green, { Size = UDim2.new(0.6, -80, 0, 14), Position = UDim2.fromOffset(76, 40) })
		local reward = K.text(f, "", { Size = UDim2.new(0.6, -80, 0, 18), Position = UDim2.fromOffset(76, 62), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14, TextColor3 = T.gold, Font = Enum.Font.GothamBold })
		local go = K.button(f, "Выследить", T.orange, { Size = UDim2.new(0.36, 0, 0, 46), Position = UDim2.new(0.62, 0, 0, 23), MaxText = 16 })
		go.Activated:Connect(function()
			local o = state.orders[i]
			if o and o.type == "kind" then
				setTrack(o.kind)
				K.close(questW)
			end
		end)
		questRows[i] = { title = title, bar = bar, reward = reward, go = go }
	end
	K.text(questList, "Задание засчитывается, когда сдаёшь банку у алтаря. Новое появляется сразу.", { Size = UDim2.new(1, -10, 0, 22), LayoutOrder = 10, MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
	refreshQuests = function()
		for i, r in questRows do
			local o = state.orders[i]
			if o then
				r.title.Text = o.type == "kind" and ("Принеси: %s"):format(Catalog.Kinds[o.kind].name) or ("Принеси духов: %s"):format(Catalog.Rarity[o.rarity].name)
				r.bar.Size = UDim2.fromScale(math.clamp(o.have / o.need, 0, 1), 1)
				r.reward.Text = ("%d/%d   Награда: %d монет, %d пыли"):format(o.have, o.need, o.coins, o.dust)
				r.go.Visible = o.type == "kind"
			end
		end
	end

end
------------------------------------------------------------------ окно: Магазин
local shopW, shopBody, refreshDonate, refreshUpgrades, refreshSkins
do
	shopW, shopBody = K.window(gui, "Магазин", "shop", T.red, 0.8, 0.8)
	local shopTabs = K.make("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, shopBody)
	K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, shopTabs)
	local tabUp = K.button(shopTabs, "Улучшения", T.red, { Size = UDim2.fromOffset(150, 34), MaxText = 16 })
	local tabSkins = K.button(shopTabs, "Фонари", T.panel2, { Size = UDim2.fromOffset(150, 34), MaxText = 16 })
	local tabDonate = K.button(shopTabs, "Донат", T.gold, { Size = UDim2.fromOffset(150, 34), MaxText = 16 })
	local upList = K.scroll(shopBody, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, upList)
	local skinGrid = K.scroll(shopBody, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), Visible = false })
	K.make("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 214), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }, skinGrid)
	local donateGrid = K.scroll(shopBody, { Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42), Visible = false })
	K.make("UIGridLayout", { CellSize = UDim2.new(0.333, -8, 0, 196), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, donateGrid)
	local shopPages = { { tabUp, upList, T.red }, { tabSkins, skinGrid, T.red }, { tabDonate, donateGrid, T.gold } }
	local function showShopPage(pair)
		for _, other in shopPages do
			other[2].Visible = other == pair
			K.recolor(other[1], other == pair and other[3] or T.panel2)
		end
	end
	for _, pair in shopPages do
		pair[1].Activated:Connect(function() showShopPage(pair) end)
	end
	showShopPage(shopPages[1])
	-- донат-карточки: геймпассы и товары
	local MarketplaceService = game:GetService("MarketplaceService")
	local Money = Catalog.Money
	local donateCards = {}
	local function donateCard(order, key, item, isPass)
		local f = K.panel(donateGrid, { LayoutOrder = order, BackgroundColor3 = T.panel2 })
		f:FindFirstChildOfClass("UIStroke").Color = item.color
		local bg = K.make("Frame", { Size = UDim2.new(1, -8, 0, 70), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1) }, f)
		K.corner(bg, UDim.new(0, 10))
		K.gradient(bg, K.lighten(item.color, 0.15), K.darken(item.color, 0.45))
		K.icon(bg, item.icon, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(62, 62) })
		K.text(f, item.name, { Size = UDim2.new(1, -10, 0, 22), Position = UDim2.fromOffset(5, 78), MaxText = 16 })
		K.text(f, item.desc, { Size = UDim2.new(1, -10, 0, 44), Position = UDim2.fromOffset(5, 100), MaxText = 12, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextWrapped = true, StrokeThickness = 1 })
		local b, bl = K.button(f, "", T.green, { Size = UDim2.new(1, -12, 0, 40), Position = UDim2.new(0, 6, 1, -46), MaxText = 16 })
		b.Activated:Connect(function()
			local owned = isPass and state.passes and state.passes[key]
			if owned then
				showToast("Уже куплено навсегда")
			elseif isPass and item.id ~= 0 then
				MarketplaceService:PromptGamePassPurchase(plr, item.id)
			elseif isPass and item.product then
				MarketplaceService:PromptProductPurchase(plr, item.product)
			elseif not isPass and item.id ~= 0 then
				MarketplaceService:PromptProductPurchase(plr, item.id)
			else
				showToast("Скоро в продаже")
			end
		end)
		donateCards[key] = { b = b, l = bl, item = item, isPass = isPass }
	end
	for i, key in Money.PassOrder do donateCard(i, key, Money.Passes[key], true) end
	for i, key in Money.ProductOrder do donateCard(10 + i, key, Money.Products[key], false) end
	refreshDonate = function()
		for key, c in donateCards do
			local owned = c.isPass and state.passes and state.passes[key]
			if c.item.id == 0 and not c.item.product then
				c.l.Text = "Скоро"
				K.recolor(c.b, Color3.fromRGB(90, 90, 105))
			elseif owned then
				c.l.Text = "Куплено"
				K.recolor(c.b, Color3.fromRGB(80, 80, 95))
			else
				c.l.Text = ("R$ %d"):format(c.item.price)
				K.recolor(c.b, T.green)
			end
		end
	end
	local UP_ICON = { jar = "jar", range = "target", power = "upgrade" }
	local upRows = {}
	for i, key in Catalog.UpgradeOrder do
		local up = Catalog.Upgrades[key]
		local f = K.panel(upList, { Size = UDim2.new(1, -10, 0, 84), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.icon(f, UP_ICON[key], { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(8, 12) })
		local title = K.text(f, "", { Size = UDim2.new(0.6, -80, 0, 24), Position = UDim2.fromOffset(76, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		K.text(f, up.desc, { Size = UDim2.new(0.6, -80, 0, 16), Position = UDim2.fromOffset(76, 34), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
		local dots = K.make("Frame", { Size = UDim2.new(0.5, -80, 0, 14), Position = UDim2.fromOffset(76, 58), BackgroundTransparency = 1 }, f)
		K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6) }, dots)
		local dotList = {}
		for d = 1, Catalog.MaxLevel do
			local dot = K.make("Frame", { Size = UDim2.fromOffset(24, 12), BackgroundColor3 = T.ink }, dots)
			K.corner(dot, UDim.new(1, 0))
			dotList[d] = dot
		end
		local buy, buyL = K.button(f, "", T.green, { Size = UDim2.new(0.36, 0, 0, 50), Position = UDim2.new(0.62, 0, 0, 17), MaxText = 16 })
		buy.Activated:Connect(function()
			local res = remotes.Upgrade:InvokeServer(key)
			if res and res.ok then
				play("save")
				showToast(up.name .. ": новый уровень!", 2, Color3.fromRGB(40, 120, 70))
			elseif res and res.msg then
				showToast(res.msg)
			end
		end)
		upRows[key] = { title = title, dots = dotList, buy = buy, buyL = buyL }
	end
	do
		local f = K.panel(upList, { Size = UDim2.new(1, -10, 0, 84), LayoutOrder = 9, BackgroundColor3 = Color3.fromRGB(40, 70, 50) })
		K.icon(f, "potion", { Size = UDim2.fromOffset(60, 60), Position = UDim2.fromOffset(8, 12) })
		K.text(f, "Зелье удачи x2", { Size = UDim2.new(0.6, -80, 0, 24), Position = UDim2.fromOffset(76, 8), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		K.text(f, ("Удача x2 на %d минут, время складывается"):format(Catalog.Luck.potionMinutes), { Size = UDim2.new(0.6, -80, 0, 16), Position = UDim2.fromOffset(76, 36), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
		local b = K.button(f, ("%d пыли"):format(Catalog.Luck.potionDust), T.green, { Size = UDim2.new(0.36, 0, 0, 50), Position = UDim2.new(0.62, 0, 0, 17), MaxText = 16 })
		b.Activated:Connect(function()
			local r = remotes.BuyPotion:InvokeServer()
			if r and r.ok then
				play("legendary")
				showToast("Зелье выпито: удача x2!", 2.5, Color3.fromRGB(40, 120, 60))
			elseif r and r.msg then
				showToast(r.msg)
			end
		end)
	end
	refreshUpgrades = function()
		for key, r in upRows do
			local up = Catalog.Upgrades[key]
			local lvl = state.levels[key] or 1
			for d, dot in r.dots do dot.BackgroundColor3 = d <= lvl and T.green or T.ink end
			if lvl >= Catalog.MaxLevel then
				r.title.Text = ("%s: %s (макс.)"):format(up.name, up.fmt:format(up.values[lvl]))
				r.buyL.Text = "Максимум"
				K.recolor(r.buy, Color3.fromRGB(80, 80, 95))
			else
				r.title.Text = ("%s: %s -> %s"):format(up.name, up.fmt:format(up.values[lvl]), up.fmt:format(up.values[lvl + 1]))
				local c, du = up.coins[lvl], up.dust[lvl]
				r.buyL.Text = du > 0 and ("%d монет + %d пыли"):format(c, du) or ("%d монет"):format(c)
				K.recolor(r.buy, (state.coins >= c and state.dust >= du) and T.green or Color3.fromRGB(90, 90, 105))
			end
		end
	end
	local skinCards = {}
	for i, key in Prog.SkinOrder do
		local sk = Prog.Skins[key]
		local tier = Prog.SkinTiers[sk.tier or "common"]
		local f = K.panel(skinGrid, { LayoutOrder = i, BackgroundColor3 = T.panel2 })
		f:FindFirstChildOfClass("UIStroke").Color = tier.color
		local stage = K.make("Frame", { Size = UDim2.new(1, -8, 0, 84), Position = UDim2.fromOffset(4, 4), BackgroundColor3 = Color3.new(1, 1, 1) }, f)
		K.corner(stage, UDim.new(0, 10))
		K.gradient(stage, K.darken(tier.color, 0.45), K.darken(sk.lamp, 0.85))
		-- превью: светящийся фонарь с ореолом и искрами цвета облика
		local halo = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(78, 78), BackgroundColor3 = sk.lamp, BackgroundTransparency = 0.75 }, stage)
		K.corner(halo, UDim.new(1, 0))
		local glow = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.55), Size = UDim2.fromOffset(46, 52), BackgroundColor3 = Color3.new(1, 1, 1) }, stage)
		K.corner(glow, UDim.new(0.45, 0))
		K.stroke(glow, T.ink, 3)
		K.gradient(glow, K.lighten(sk.lamp, 0.6), sk.lamp)
		for j, c in (sk.fx and sk.fx.colors) or {} do
			for k = 0, 1 do
				local dot = K.make("Frame", { Size = UDim2.fromOffset(7, 7), Position = UDim2.new(0.18 + ((j * 0.23 + k * 0.47) % 0.64), 0, 0.12 + ((j * 0.31 + k * 0.4) % 0.7), 0), BackgroundColor3 = c }, stage)
				K.corner(dot, UDim.new(1, 0))
			end
		end
		local tierTag = K.make("Frame", { Size = UDim2.fromOffset(104, 20), Position = UDim2.fromOffset(6, 6), BackgroundColor3 = tier.color }, stage)
		K.corner(tierTag, UDim.new(1, 0))
		K.stroke(tierTag, T.ink, 2)
		K.text(tierTag, tier.name, { Size = UDim2.new(1, -8, 1, -4), Position = UDim2.fromOffset(4, 2), MaxText = 13 })
		K.text(f, sk.name, { Size = UDim2.new(1, -10, 0, 24), Position = UDim2.fromOffset(5, 92), MaxText = 18 })
		K.text(f, sk.desc or "", { Size = UDim2.new(1, -12, 0, 40), Position = UDim2.fromOffset(6, 118), MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = Color3.fromRGB(225, 228, 245), TextWrapped = true, StrokeThickness = 1 })
		local b, bl = K.button(f, "", T.green, { Size = UDim2.new(1, -12, 0, 42), Position = UDim2.new(0, 6, 1, -48), MaxText = 15 })
		b.Activated:Connect(function()
			local owned = state.skins[key]
			local res = remotes.Skin:InvokeServer(owned and "equip" or "buy", key)
			if res and res.ok then
				play("save")
				showToast(owned and ("Фонарь: " .. sk.name) or ("Куплен фонарь: " .. sk.name), 2)
			elseif res and res.msg then
				showToast(res.msg)
			end
		end)
		skinCards[key] = { b = b, l = bl }
	end
	refreshSkins = function()
		for key, c in skinCards do
			local sk = Prog.Skins[key]
			if state.skin == key then
				c.l.Text = "Надет"
				K.recolor(c.b, Color3.fromRGB(80, 80, 95))
			elseif state.skins[key] then
				c.l.Text = "Надеть"
				K.recolor(c.b, T.blue)
			elseif sk.price then
				c.l.Text = sk.dust and ("%d + %d пыли"):format(sk.price, sk.dust) or ("%d монет"):format(sk.price)
				K.recolor(c.b, state.coins >= sk.price and T.green or Color3.fromRGB(90, 90, 105))
			else
				c.l.Text = sk.source or ""
				K.recolor(c.b, Color3.fromRGB(70, 70, 90))
			end
		end
	end

end
------------------------------------------------------------------ окно: Подарок дня
local giftW, giftBody, refreshGift
do
	giftW, giftBody = K.window(gui, "Ежедневный подарок", "gift", T.green, 0.8, 0.66)
	local dayRow = K.make("Frame", { Size = UDim2.new(1, 0, 0.62, 0), BackgroundTransparency = 1 }, giftBody)
	K.make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, dayRow)
	local dayTiles = {}
	for i, r in Prog.Daily do
		local f = K.panel(dayRow, { Size = UDim2.new(1 / 7, -6, 1, 0), BackgroundColor3 = T.panel2, LayoutOrder = i })
		K.text(f, "День " .. i, { Size = UDim2.new(1, -6, 0, 18), Position = UDim2.fromOffset(3, 4), MaxText = 14 })
		local ic = r.skin and "shop" or (r.coins and "coin" or "dust")
		K.icon(f, ic, { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0.5, 0, 0, 26) })
		local parts = {}
		if r.coins then table.insert(parts, r.coins .. " мон.") end
		if r.dust then table.insert(parts, r.dust .. " пыли") end
		if r.skin then table.insert(parts, "фонарь") end
		K.text(f, table.concat(parts, "\n"), { Size = UDim2.new(1, -6, 0, 34), Position = UDim2.new(0, 3, 1, -38), MaxText = 13, Font = Enum.Font.GothamBold, StrokeThickness = 1 })
		dayTiles[i] = f
	end
	local giftBtn, giftL = K.button(giftBody, "Забрать", T.green, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(260, 54), Position = UDim2.new(0.5, 0, 1, -4), MaxText = 22 })
	giftBtn.Activated:Connect(function()
		local r = remotes.ClaimDaily:InvokeServer()
		if r and r.ok then
			play("legendary")
			showToast(("Подарок дня %d получен!"):format(r.day), 2.5, Color3.fromRGB(40, 120, 70))
		elseif r and r.msg then
			showToast(r.msg)
		end
	end)
	refreshGift = function()
		local today = math.floor(workspace:GetServerTimeNow() / 86400)
		local nextDay
		if state.dailyReady then
			nextDay = (state.daily.last == today - 1) and (state.daily.streak % 7) + 1 or 1
		else
			nextDay = state.daily.streak
		end
		for i, f in dayTiles do
			local st = f:FindFirstChildOfClass("UIStroke")
			if i == nextDay and state.dailyReady then
				st.Color, st.Thickness = T.gold, 4
				f.BackgroundColor3 = Color3.fromRGB(70, 100, 60)
			else
				st.Color, st.Thickness = T.ink, 3
				f.BackgroundColor3 = (i < nextDay or (not state.dailyReady and i <= nextDay)) and Color3.fromRGB(36, 36, 50) or T.panel2
			end
		end
		giftL.Text = state.dailyReady and "Забрать" or "Новый подарок завтра"
		K.recolor(giftBtn, state.dailyReady and T.green or Color3.fromRGB(80, 80, 95))
	end

end
------------------------------------------------------------------ окно: Настройки
local setW, setBody, applyReduced, setRefreshers
do
	setW, setBody = K.window(gui, "Настройки", "settings", Color3.fromRGB(110, 115, 145), 0.6, 0.78)
	local setList = K.scroll(setBody)
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, setList)

	local function sendSettings() remotes.SetSettings:FireServer(state.settings) end
	setRefreshers = {}
	local function volumeRow(order, title, key)
		local f = K.panel(setList, { Size = UDim2.new(1, -10, 0, 50), LayoutOrder = order, BackgroundColor3 = T.panel2 })
		local l = K.text(f, "", { Size = UDim2.new(0.5, -10, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		local minus = K.button(f, "-", T.blue, { Size = UDim2.new(0.22, -6, 1, -12), Position = UDim2.new(0.52, 0, 0, 6), MaxText = 24 })
		local plus = K.button(f, "+", T.blue, { Size = UDim2.new(0.22, -6, 1, -12), Position = UDim2.new(0.76, 0, 0, 6), MaxText = 24 })
		local function refresh() l.Text = ("%s: %d%%"):format(title, math.floor(state.settings[key] * 100 + 0.5)) end
		local function step(d)
			state.settings[key] = math.clamp(math.floor(state.settings[key] * 10 + 0.5 + d) / 10, 0, 1)
			refresh()
			applyAudio()
			sendSettings()
		end
		minus.Activated:Connect(function() step(-1) end)
		plus.Activated:Connect(function() step(1) end)
		table.insert(setRefreshers, refresh)
	end
	local function toggleRow(order, title, key, onChange)
		local b, l = K.button(setList, "", T.panel2, { Size = UDim2.new(1, -10, 0, 46), LayoutOrder = order, MaxText = 18 })
		local function refresh()
			l.Text = title .. ": " .. (state.settings[key] and "ВКЛ" or "ВЫКЛ")
			K.recolor(b, state.settings[key] and T.green or T.panel2)
		end
		b.Activated:Connect(function()
			state.settings[key] = not state.settings[key]
			refresh()
			sendSettings()
			if onChange then onChange() end
		end)
		table.insert(setRefreshers, refresh)
	end
	volumeRow(1, "Музыка", "music")
	volumeRow(2, "Звуки", "sfx")
	toggleRow(3, "Приглушённые эффекты", "reduced", function() applyReduced() end)
	local codeRow = K.panel(setList, { Size = UDim2.new(1, -10, 0, 54), LayoutOrder = 6, BackgroundColor3 = T.panel2 })
	K.icon(codeRow, "code", { Size = UDim2.fromOffset(44, 44), Position = UDim2.fromOffset(6, 5) })
	local codeBox = K.make("TextBox", {
		Size = UDim2.new(0.6, -60, 1, -14), Position = UDim2.fromOffset(56, 7), BackgroundColor3 = T.ink, Text = "", PlaceholderText = "Введи код",
		TextColor3 = T.text, PlaceholderColor3 = T.sub, Font = Enum.Font.GothamBold, TextScaled = true, ClearTextOnFocus = false,
	}, codeRow)
	K.corner(codeBox, UDim.new(0, 10))
	K.make("UITextSizeConstraint", { MaxTextSize = 20 }, codeBox)
	local codeBtn = K.button(codeRow, "Активировать", T.pink, { Size = UDim2.new(0.4, -10, 1, -14), Position = UDim2.new(0.6, 2, 0, 7), MaxText = 16 })
	codeBtn.Activated:Connect(function()
		local r = remotes.Redeem:InvokeServer(codeBox.Text)
		if r and r.ok then
			codeBox.Text = ""
			play("legendary")
			showToast(r.msg, 3, Color3.fromRGB(150, 60, 110))
		elseif r and r.msg then
			showToast(r.msg)
		end
	end)
	K.text(setList, "Чувствительность камеры и графика — в меню Roblox (кнопка вверху слева).", { Size = UDim2.new(1, -10, 0, 34), LayoutOrder = 9, MaxText = 14, Font = Enum.Font.GothamBold, TextColor3 = T.sub, TextWrapped = true, StrokeThickness = 1 })

end
------------------------------------------------------------------ окно: Сила ловца (таланты и перерождение)
local powerW, refreshPower
do
	local body
	powerW, body = K.window(gui, "Сила ловца", "level", Color3.fromRGB(240, 170, 40), 0.82, 0.84)
	local pts = K.text(body, "", { Size = UDim2.new(1, 0, 0, 26), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 20, TextColor3 = T.gold })
	local list = K.scroll(body, { Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, list)
	local rows = {}
	for i, key in Prog.TalentOrder do
		local t = Prog.Talents[key]
		local f = K.panel(list, { Size = UDim2.new(1, -10, 0, 66), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		K.icon(f, t.icon, { Size = UDim2.fromOffset(48, 48), Position = UDim2.fromOffset(8, 9) })
		local title = K.text(f, "", { Size = UDim2.new(0.62, -70, 0, 24), Position = UDim2.fromOffset(64, 5), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		K.text(f, t.desc, { Size = UDim2.new(0.62, -70, 0, 16), Position = UDim2.fromOffset(64, 30), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 13, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
		local _, bar = K.bar(f, t.color, { Size = UDim2.new(0.62, -70, 0, 9), Position = UDim2.fromOffset(64, 50) })
		local b, bl = K.button(f, "+", T.green, { Size = UDim2.new(0.34, -10, 1, -16), Position = UDim2.new(0.64, 0, 0, 8), MaxText = 20 })
		b.Activated:Connect(function()
			local r = remotes.Talent:InvokeServer("up", key)
			if r and r.ok then
				play("save")
			elseif r and r.msg then
				showToast(r.msg)
			end
		end)
		rows[key] = { title = title, bar = bar, b = b, bl = bl }
	end
	local resetArmed = false
	local rf = K.panel(list, { Size = UDim2.new(1, -10, 0, 52), LayoutOrder = 20, BackgroundColor3 = Color3.fromRGB(40, 40, 60) })
	K.text(rf, ("Сбросить таланты и вернуть очки: %d пыли"):format(Prog.TalentResetDust), { Size = UDim2.new(0.62, -16, 1, -12), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 14, Font = Enum.Font.GothamBold, TextWrapped = true, StrokeThickness = 1 })
	local resetB = K.button(rf, "Сбросить", T.red, { Size = UDim2.new(0.34, -10, 1, -14), Position = UDim2.new(0.64, 0, 0, 7), MaxText = 16 })
	resetB.Activated:Connect(function()
		if not resetArmed then
			resetArmed = true
			showToast("Нажми «Сбросить» ещё раз", 2.5)
			task.delay(2.5, function() resetArmed = false end)
			return
		end
		resetArmed = false
		local r = remotes.Talent:InvokeServer("reset")
		if r and r.msg then showToast(r.msg) end
	end)
	local rbArmed = false
	local rbf = K.panel(list, { Size = UDim2.new(1, -10, 0, 118), LayoutOrder = 30, BackgroundColor3 = Color3.fromRGB(70, 40, 95) })
	rbf:FindFirstChildOfClass("UIStroke").Color = T.gold
	K.icon(rbf, "level", { Size = UDim2.fromOffset(64, 64), Position = UDim2.fromOffset(8, 10) })
	local rbTitle = K.text(rbf, "", { Size = UDim2.new(0.62, -84, 0, 26), Position = UDim2.fromOffset(80, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 19, TextColor3 = T.gold })
	K.text(rbf, ("Сбросит уровень, монеты, улучшения и таланты. Навсегда за каждое: монеты +%d%%, удача +%d%%. Коллекция, пыль, облики и донат останутся."):format(math.floor(Prog.Rebirth.coins * 100 + 0.5), math.floor(Prog.Rebirth.luck * 100 + 0.5)),
		{ Size = UDim2.new(0.62, -84, 0, 70), Position = UDim2.fromOffset(80, 36), TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, MaxText = 13, Font = Enum.Font.GothamBold, TextWrapped = true, StrokeThickness = 1 })
	local rbB, rbL = K.button(rbf, "", T.purple, { Size = UDim2.new(0.34, -10, 0, 60), Position = UDim2.new(0.64, 0, 0, 29), MaxText = 16 })
	rbB.Activated:Connect(function()
		if (state.level or 1) < (state.rebirthLevel or 15) then
			showToast(("Перерождение откроется на уровне %d"):format(state.rebirthLevel or 15))
			return
		end
		if not rbArmed then
			rbArmed = true
			showToast("Точно? Нажми ещё раз, чтобы переродиться", 3)
			task.delay(3, function() rbArmed = false end)
			return
		end
		rbArmed = false
		local r = remotes.Rebirth:InvokeServer()
		if r and r.ok then
			play("legendary")
			showToast(("Перерождение %d! Монеты и удача выросли навсегда"):format(r.rebirths), 4, Color3.fromRGB(120, 60, 150))
		elseif r and r.msg then
			showToast(r.msg)
		end
	end)
	refreshPower = function()
		local p = state.talentPoints or 0
		pts.Text = ("Очки талантов: %d   (1 очко за каждый новый уровень)"):format(p)
		for key, r in rows do
			local lvl = (state.talents and state.talents[key]) or 0
			r.title.Text = ("%s  %d/%d"):format(Prog.Talents[key].name, lvl, Prog.TalentMax)
			r.bar.Size = UDim2.fromScale(lvl / Prog.TalentMax, 1)
			local can = p > 0 and lvl < Prog.TalentMax
			r.bl.Text = lvl >= Prog.TalentMax and "Макс." or "+"
			K.recolor(r.b, can and T.green or Color3.fromRGB(80, 80, 95))
		end
		local need = state.rebirthLevel or 15
		rbTitle.Text = ("Перерождение   (сейчас: %d)   Ранг: %s"):format(state.rebirths or 0, state.rank or "Новичок")
		local ready = (state.level or 1) >= need
		rbL.Text = ready and "Переродиться" or ("Нужен ур. %d"):format(need)
		K.recolor(rbB, ready and T.purple or Color3.fromRGB(80, 80, 95))
	end
end

------------------------------------------------------------------ навигация по окнам
local newsW, newsBody, toggleWindow
do
	-- Телепорт
	local tpW, tpBody = K.window(gui, "Телепорт", "portal", T.purple, 0.62, 0.8)
	local tpList = K.scroll(tpBody)
	K.make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, tpList)
	local tpRows = {}
	for i, key in Catalog.Worlds.TeleportOrder do
		local dc = Catalog.Districts[key]
		local f = K.panel(tpList, { Size = UDim2.new(1, -10, 0, 58), LayoutOrder = i, BackgroundColor3 = T.panel2 })
		local sw = K.make("Frame", { Size = UDim2.fromOffset(40, 40), Position = UDim2.fromOffset(9, 9), BackgroundColor3 = dc.tint }, f)
		K.corner(sw, UDim.new(1, 0))
		K.stroke(sw, T.ink, 3)
		K.text(f, dc.name, { Size = UDim2.new(0.6, -64, 0, 24), Position = UDim2.fromOffset(58, 6), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 18 })
		local st = K.text(f, "", { Size = UDim2.new(0.6, -64, 0, 16), Position = UDim2.fromOffset(58, 34), TextXAlignment = Enum.TextXAlignment.Left, MaxText = 12, Font = Enum.Font.GothamBold, TextColor3 = T.sub, StrokeThickness = 1 })
		local b, bl = K.button(f, "Лететь", T.purple, { Size = UDim2.new(0.38, -10, 1, -14), Position = UDim2.new(0.62, 0, 0, 7), MaxText = 16 })
		b.Activated:Connect(function()
			local r = remotes.Teleport:InvokeServer(key)
			if r and r.ok then
				K.close(tpW)
				play("reveal")
			elseif r and r.msg then
				showToast(r.msg)
			end
		end)
		tpRows[key] = { st = st, b = b, bl = bl }
	end
	local function refreshTeleport()
		local stt = { distinct = state.distinct, level = state.level }
		for key, row in tpRows do
			local open = Catalog.unlocked(key, stt)
			local dl = Catalog.Districts[key].luck or 1
			row.st.Text = open and (dl > 1 and ("Открыт   удача района x%.1f"):format(dl) or "Открыт") or Catalog.unlockText(key, stt)
			row.bl.Text = open and "Лететь" or "Закрыт"
			K.recolor(row.b, open and T.purple or Color3.fromRGB(80, 80, 95))
		end
	end

	-- Что нового
	newsW, newsBody = K.window(gui, Prog.News.title, "news", T.red, 0.62, 0.8)
	local newsList = K.make("Frame", { Size = UDim2.new(1, 0, 1, -64), BackgroundTransparency = 1 }, newsBody)
	K.make("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, newsList)
	for i, line in Prog.News.lines do
		K.text(newsList, "•  " .. line, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left, MaxText = 17, Font = Enum.Font.GothamBold })
	end
	local newsOk = K.button(newsBody, "Погнали!", T.green, { AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(220, 50), Position = UDim2.new(0.5, 0, 1, 0), MaxText = 22 })
	newsOk.Activated:Connect(function()
		K.close(newsW)
		remotes.NewsSeen:FireServer()
	end)

	-- Админка (сервер проверяет доступ сам)
	local adminW, adminBody = K.window(gui, "Админка", "admin", Color3.fromRGB(230, 160, 30), 0.78, 0.82)
	local adminGrid = K.scroll(adminBody)
	K.make("UIGridLayout", { CellSize = UDim2.new(0.25, -8, 0, 52), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, adminGrid)
	local function adminCmd(cmd, a1, a2)
		local r = remotes.Admin:InvokeServer(cmd, a1, a2)
		if r and r.ok then showToast("Админ: готово", 1.2, Color3.fromRGB(150, 110, 20))
		elseif r and r.msg then showToast(r.msg) end
	end
	local adminButtons = {
		{ "+1000 монет", "coins" }, { "+100 пыли", "dust" }, { "+1 уровень", "level" }, { "Все духи", "allSpirits" },
		{ "Макс. улучшения", "maxUpgrades" }, { "Весь донат", "passes" }, { "Начать луну", "moon" }, { "Закончить луну", "endMoon" },
		{ "Фейерверк", "fireworks" }, { "Банка полная", "fillJar" }, { "Мгновенная ловля", "fast" }, { "Сброс прогресса", "reset" },
	}
	local resetArmed = false
	for i, bd in adminButtons do
		local b = K.button(adminGrid, bd[1], bd[2] == "reset" and T.red or T.orange, { LayoutOrder = i, MaxText = 15 })
		b.Activated:Connect(function()
			if bd[2] == "reset" and not resetArmed then
				resetArmed = true
				showToast("Нажми «Сброс прогресса» ещё раз для подтверждения", 3)
				task.delay(3, function() resetArmed = false end)
				return
			end
			resetArmed = false
			adminCmd(bd[2])
		end)
	end
	local spawnKind, spawnVar = 1, 1
	local kindB, kindL = K.button(adminGrid, "", T.blue, { LayoutOrder = 50, MaxText = 14 })
	local varB, varL = K.button(adminGrid, "", T.purple, { LayoutOrder = 51, MaxText = 14 })
	local spawnB = K.button(adminGrid, "Призвать духа", T.green, { LayoutOrder = 52, MaxText = 15 })
	local function refreshSpawnLabels()
		kindL.Text = Catalog.Kinds[Catalog.Order[spawnKind]].name
		varL.Text = Catalog.Variants[Catalog.VariantOrder[spawnVar]].name
	end
	refreshSpawnLabels()
	kindB.Activated:Connect(function()
		spawnKind = spawnKind % #Catalog.Order + 1
		refreshSpawnLabels()
	end)
	varB.Activated:Connect(function()
		spawnVar = spawnVar % #Catalog.VariantOrder + 1
		refreshSpawnLabels()
	end)
	spawnB.Activated:Connect(function()
		adminCmd("spawn", Catalog.Order[spawnKind], Catalog.VariantOrder[spawnVar])
		K.close(adminW)
	end)

	local allWindows = { atlasW, questW, shopW, giftW, setW, tpW, newsW, adminW, powerW }
	toggleWindow = function(w, refresh)
		local willOpen = not w.Visible
		for _, x in allWindows do K.close(x) end
		if willOpen then
			if refresh then refresh() end
			K.open(w)
		end
	end
	btnAtlas.Activated:Connect(function() toggleWindow(atlasW, refreshAtlas) end)
	btnQuests.Activated:Connect(function() toggleWindow(questW, refreshQuests) end)
	btnShop.Activated:Connect(function()
		toggleWindow(shopW, function()
			refreshUpgrades()
			refreshSkins()
			refreshDonate()
		end)
	end)
	btnGift.Activated:Connect(function() toggleWindow(giftW, refreshGift) end)
	btnTeleport.Activated:Connect(function() toggleWindow(tpW, refreshTeleport) end)
	btnPower.Activated:Connect(function() toggleWindow(powerW, refreshPower) end)
	btnAdmin.Activated:Connect(function() toggleWindow(adminW) end)
	btnSettings.Activated:Connect(function()
		toggleWindow(setW, function()
			for _, r in setRefreshers do r() end
		end)
	end)

end
------------------------------------------------------------------ HUD-обновление
local refreshHUD
do
	refreshHUD = function()
		local n = #state.jar
		jarL.Text = ("Банка %d/%d"):format(n, state.cap)
		jarFill.Size = UDim2.fromScale(math.clamp(n / math.max(state.cap, 1), 0, 1), 1)
		local names = {}
		for _, e in state.jar do
			local k = typeof(e) == "table" and e.k or e
			local v = typeof(e) == "table" and e.v or "normal"
			table.insert(names, (v ~= "normal" and (Catalog.Variants[v].name .. " ") or "") .. Catalog.Kinds[k].short)
		end
		jarNames.Text = n > 0 and table.concat(names, ", ") or "пусто"
		jarNames.TextColor3 = n >= state.cap and Color3.fromRGB(255, 160, 100) or T.sub
		coinL.Text = tostring(state.coins)
		dustL.Text = tostring(state.dust)
		levelL.Text = ("Ур. %d"):format(state.level)
		xpFill.Size = UDim2.fromScale(math.clamp(state.xp / math.max(state.xpNext, 1), 0, 1), 1)
		btnGift.Badge.Visible = state.dailyReady
		btnPower.Badge.Visible = (state.talentPoints or 0) > 0 or (state.level or 1) >= (state.rebirthLevel or 15)
		luckL.Text = ("Удача x%.2f"):format(state.luck or 1)
		luckL.Text = string.gsub(luckL.Text, "%.?0+$", "")
		local claimable = false
		for i, m in Prog.Milestones do
			if not state.milestones[tostring(i)] and state.distinct >= m.need then claimable = true end
		end
		for id, a in Prog.Achievements do
			if not (state.achDone and state.achDone[id]) and ((state.achCur and state.achCur[id]) or 0) >= a.need then claimable = true end
		end
		btnAtlas.Badge.Visible = claimable
		-- ворота районов и таблички показывают фактическое состояние
		local st = { distinct = state.distinct, level = state.level }
		for name, dc in Catalog.Districts do
			local gate = dc.gate and World:FindFirstChild(dc.gate)
			if gate then
				local open = Catalog.unlocked(name, st)
				gate.CanCollide = not open
				gate.Transparency = open and 1 or 0.2
				for _, g in gate:GetChildren() do
					local t = g:IsA("SurfaceGui") and g:FindFirstChildOfClass("TextLabel")
					if t then
						g.Enabled = not open -- открытые ворота без надписей: не загораживают экран
						t.Text = dc.name .. " закрыт\n" .. Catalog.unlockText(name, st)
					end
				end
			end
		end
		if atlasW.Visible then refreshAtlas() end
		if questW.Visible then refreshQuests() end
		if shopW.Visible then
			refreshUpgrades()
			refreshSkins()
			refreshDonate()
		end
		if giftW.Visible then refreshGift() end
		if powerW.Visible then refreshPower() end
	end

end
------------------------------------------------------------------ эффекты в мире
local reducedFx, ring, burst, catchEffect, revealLegendary
do
	reducedFx = false
	applyReduced = function()
		reducedFx = state.settings.reduced
		local b = Lighting:FindFirstChild("Bloom")
		if b then b.Enabled = not reducedFx end
	end

	ring = function(pos, fromSize, toSize, color, secs, upright)
		local r = K.make("Part", {
			Shape = Enum.PartType.Cylinder, Anchored = true, CanCollide = false, CanQuery = false, CastShadow = false,
			Material = Enum.Material.Neon, Color = color, Transparency = reducedFx and 0.5 or 0.15, Size = Vector3.new(0.15, fromSize, fromSize),
			CFrame = CFrame.new(pos) * (upright and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90))),
		}, workspace)
		TweenService:Create(r, TweenInfo.new(secs, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, toSize, toSize), Transparency = 1 }):Play()
		task.delay(secs + 0.05, function() r:Destroy() end)
	end

	burst = function(pos, colors, n)
		if reducedFx then n = math.floor(n / 3) end
		local a = K.make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one, Position = pos }, workspace)
		local pe = K.make("ParticleEmitter", {
			Color = colors, Rate = 0, Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(8, 16),
			SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-200, 200), Size = NumberSequence.new(0.5, 0.1),
			LightEmission = 0.3, Acceleration = Vector3.new(0, -14, 0),
		}, a)
		pe:Emit(n)
		task.delay(1.5, function() a:Destroy() end)
	end

	local streak, lastCatch = 0, 0
	catchEffect = function(kind, at, coop, variant)
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
				K.pop(jarPanel)
			end
		end)
		local vname = (variant and variant ~= "normal") and (Catalog.Variants[variant].name .. " ") or ""
		local text = vname .. info.name .. " в банке!"
		if coop > 1 then text ..= ("  Вместе x%d"):format(coop)
		elseif streak > 1 then text ..= "  Серия x" .. streak end
		if info.rarity == "legendary" then text = info.name .. "! Неси к алтарю" end
		if trackKind == kind then
			text ..= "  Цель поймана!"
			setTrack(nil)
		end
		showToast(text, 2.5, K.darken(rar.color, 0.55))
	end

	-- раскрытие легендарного духа (~2 с)
	local revealCC = K.make("ColorCorrectionEffect", {}, Lighting)
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
	revealLegendary = function(kind)
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
		showToast(Catalog.Kinds[kind].name .. " в коллекции!", 2.5, Color3.fromRGB(150, 110, 20))
	end

end
------------------------------------------------------------------ обучение
local tut, arrowPart, arrow, setStep, finishTutorial
do
	tut = { step = 0 }
	local TUT_TEXT = {
		"1/4  Найди тень рядом с площадью и наведи на неё фонарь",
		"2/4  Жми ЛОВИТЬ и держи кнопку: зелёная зона должна держать метку духа",
		"3/4  Неси банку к алтарю (голубой луч) и сохрани улов",
		"4/4  Открой Атлас и возьми лиса спутником",
	}
	arrowPart = K.make("Part", { Anchored = true, CanCollide = false, CanQuery = false, Transparency = 1, Size = Vector3.one }, workspace)
	local arrowAtt = K.make("Attachment", {}, arrowPart)
	arrow = K.make("Beam", {
		Attachment1 = arrowAtt, Width0 = 0.7, Width1 = 0.25, FaceCamera = true, LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(140, 230, 255)), Transparency = NumberSequence.new(0.15, 0.6), Enabled = false,
	}, arrowPart)

	setStep = function(n)
		tut.step = n
		if n >= 1 and n <= 4 then
			tutL.Text = TUT_TEXT[n]
			tutPanel.Visible = true
			K.pop(tutPanel)
		else
			tutPanel.Visible = false
			K.recolor(btnAtlas, T.blue)
		end
	end
	finishTutorial = function()
		if tut.step == 0 or tut.step == 5 then return end
		setStep(5)
		remotes.TutorialDone:FireServer()
		showToast("Обучение пройдено! Открой Атлас, выбери духа и выследи его", 4, Color3.fromRGB(40, 100, 160))
	end
	skipBtn.Activated:Connect(finishTutorial)

end
------------------------------------------------------------------ стартовый экран
local introAngle, introOpen
do
	local GuiService = game:GetService("GuiService")
	local introGui = K.make("ScreenGui", { Name = "Intro", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 100 }, plr:WaitForChild("PlayerGui"))
	K.make("UIScale", { Scale = uiScale.Scale }, introGui)
	local intro = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(10, 8, 24) }, introGui)
	local cover = K.make("ImageLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Image = K.Icons.cover or "", ScaleType = Enum.ScaleType.Crop }, intro)
	local shade = K.make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BorderSizePixel = 0 }, intro)
	K.make("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.55, 0.85), NumberSequenceKeypoint.new(1, 0.15) }) }, shade)
	local playBtn = K.button(intro, "ИГРАТЬ", T.green, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -40), Size = UDim2.fromOffset(300, 76), MaxText = 40 })
	local badge = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -126), Size = UDim2.fromOffset(330, 40), BackgroundColor3 = Color3.new(1, 1, 1) }, intro)
	K.corner(badge, UDim.new(1, 0))
	K.stroke(badge, T.ink, 3)
	K.gradient(badge, Color3.fromRGB(255, 110, 110), Color3.fromRGB(190, 40, 60))
	K.text(badge, Prog.News.title, { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxText = 18 })
	-- кнопка «дышит», пока ждёт нажатия
	task.spawn(function()
		local sc = playBtn:FindFirstChild("Bounce") or K.make("UIScale", { Name = "Bounce" }, playBtn)
		while playBtn.Parent do
			TweenService:Create(sc, TweenInfo.new(0.7, Enum.EasingStyle.Sine), { Scale = 1.06 }):Play()
			task.wait(0.7)
			TweenService:Create(sc, TweenInfo.new(0.7, Enum.EasingStyle.Sine), { Scale = 1 }):Play()
			task.wait(0.7)
		end
	end)
	pcall(function() GuiService.TouchControlsEnabled = false end)
	introAngle = nil
	hud.Visible = false
	introOpen = true
	playBtn.Activated:Connect(function()
		if not introOpen then return end
		introOpen = false
		pcall(function() GuiService.TouchControlsEnabled = true end)
		TweenService:Create(intro, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cover, TweenInfo.new(0.4), { ImageTransparency = 1 }):Play()
		for _, d in intro:GetDescendants() do
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
			if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
			if d:IsA("Frame") or d:IsA("TextButton") then TweenService:Create(d, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play() end
		end
		task.delay(0.42, function()
			introGui:Destroy()
			hud.Visible = true
			if not state.tutorialDone and tut.step == 0 then setStep(1) end
			if state.tutorialDone and (state.newsSeen or 0) < Prog.NewsVersion then
				task.delay(0.6, function() toggleWindow(newsW) end)
			elseif state.dailyReady then
				task.delay(1.2, function() toggleWindow(giftW, refreshGift) end)
			end
		end)
	end)

end
------------------------------------------------------------------ серверные события
local holding
do
	local firstState = true
	remotes.State.OnClientEvent:Connect(function(s)
		local keepSettings = not firstState and state.settings
		state = s
		if keepSettings then state.settings = keepSettings end
		if firstState then
			firstState = false
			applyAudio()
			applyReduced()
			if not s.tutorialDone and not introOpen then setStep(1) end
			if s.persistent == false then showToast("Сохранения недоступны в этом запуске", 3) end
		end
		btnAdmin.Visible = s.isAdmin == true
		refreshHUD()
		if tut.step == 4 and s.equipped then finishTutorial() end
	end)

	remotes.Reward.OnClientEvent:Connect(function(r)
		if r.coins and r.coins > 0 then floatReward("coin", "+" .. r.coins, coinPill) end
		if r.dust and r.dust > 0 then task.delay(0.15, function() floatReward("dust", "+" .. r.dust, dustPill) end) end
		if r.xp then K.pop(levelPill) end
		if r.skin then showToast("Новый облик фонаря: " .. Prog.Skins[r.skin].name, 3, Color3.fromRGB(120, 60, 120)) end
		if r.levelUp then
			play("legendary")
			task.delay(0.3, function()
				local chest = r.levelUp.chest
			showToast(chest and ("Уровень %d! Сундук: +%d монет, +%d пыли и очко таланта"):format(r.levelUp.level, r.levelUp.coins + chest.coins, chest.dust)
				or ("Новый уровень %d!  +%d монет и очко таланта (кнопка Сила)"):format(r.levelUp.level, r.levelUp.coins), 3.5, Color3.fromRGB(150, 110, 20))
				floatReward("level", "Ур. " .. r.levelUp.level, levelPill)
			end)
		end
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
			local msg = ("Сдано духов: %d"):format(#r.kinds)
			if #r.firsts > 0 then msg ..= ("  Новых в Атласе: %d"):format(#r.firsts) end
			for i, nv in r.newVariants or {} do
				task.delay(1.2 + i * 1.4, function()
					showToast(("Новая разновидность: %s %s!"):format(Catalog.Variants[nv.v].name, Catalog.Kinds[nv.k].name), 2.5, K.darken(Catalog.Variants[nv.v].color, 0.5))
				end)
			end
			if not r.persisted then msg ..= " (без сохранения)" end
			showToast(msg, 3, Color3.fromRGB(30, 90, 140))
		end
		if r.coins > 0 then floatReward("coin", "+" .. r.coins, coinPill) end
		if r.dust > 0 then task.delay(0.2, function() floatReward("dust", "+" .. r.dust, dustPill) end) end
		if #r.orders > 0 then
			task.delay(legendary and 2.3 or 1.6, function() showToast(("Задание выполнено! (%d)"):format(#r.orders), 2.5, Color3.fromRGB(150, 90, 30)) end)
		end
		if r.gardenOpened then
			task.delay(legendary and 4.6 or 3.2, function() showToast("Храмовый сад открыт! Иди на юг за канал", 4, Color3.fromRGB(40, 110, 60)) end)
		end
		if tut.step == 3 then setStep(4) end
	end)

	holding = false
	-- рулетка разновидности: имена мелькают, замедляются и останавливаются на выпавшей
	local rollGui = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromOffset(440, 130), BackgroundColor3 = T.panel, Visible = false, ZIndex = 20 }, gui)
	K.corner(rollGui, UDim.new(0, 18))
	local rollStroke = K.stroke(rollGui, T.gold, 4)
	local rollName = K.text(rollGui, "", { Size = UDim2.new(1, -20, 0, 54), Position = UDim2.fromOffset(10, 10), MaxText = 44, ZIndex = 21 })
	local rollSub = K.text(rollGui, "", { Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(10, 70), MaxText = 22, ZIndex = 21, Font = Enum.Font.GothamBold })
	local function playRoll(kind, variant)
		local vc = Catalog.Variants[variant]
		local odds = math.floor(1 / vc.chance + 0.5)
		rollGui.Visible = true
		K.pop(rollGui)
		local order = Catalog.VariantOrder
		local steps = 16
		for i = 1, steps do
			local vk = order[(i % #order) + 1]
			rollName.Text = Catalog.Variants[vk].name
			rollName.TextColor3 = Catalog.Variants[vk].color
			rollStroke.Color = Catalog.Variants[vk].color
			rollSub.Text = "Бросок удачи..."
			play("click")
			task.wait(0.03 + i * i * 0.0012)
		end
		rollName.Text = vc.name .. "!"
		rollName.TextColor3 = vc.color
		rollStroke.Color = vc.color
		rollSub.Text = ("%s   1 к %d"):format(Catalog.Kinds[kind].name, odds)
		K.pop(rollGui)
		play(odds >= 80 and "legendary" or "catchRare")
		task.wait(odds >= 80 and 2.4 or 1.4)
		rollGui.Visible = false
	end

	local annGui = K.make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 152), Size = UDim2.fromOffset(520, 44), BackgroundColor3 = Color3.new(1, 1, 1), Visible = false }, gui)
	K.corner(annGui, UDim.new(0, 14))
	K.stroke(annGui, T.ink, 3)
	local annGrad = K.gradient(annGui, Color3.fromRGB(255, 200, 80), Color3.fromRGB(200, 120, 20))
	local annL = K.text(annGui, "", { Size = UDim2.new(1, -20, 1, -10), Position = UDim2.fromOffset(10, 5), MaxText = 18 })
	local annSeq = 0
	remotes.Announce.OnClientEvent:Connect(function(a)
		local vc = Catalog.Variants[a.variant]
		if not vc then return end
		annSeq += 1
		local my = annSeq
		annL.Text = (a.global and "[Все сервера] " or "") .. ("%s поймал: %s %s (1 к %d)!"):format(a.name, vc.name, Catalog.Kinds[a.kind].name, a.odds)
		annGrad.Color = ColorSequence.new(K.lighten(vc.color, 0.2), K.darken(vc.color, 0.35))
		annGui.Visible = true
		K.pop(annGui)
		task.delay(5, function()
			if annSeq == my then annGui.Visible = false end
		end)
	end)

	remotes.Caught.OnClientEvent:Connect(function(kind, at, coop, variant, rolled)
		if variant and variant ~= "normal" and (rolled or Catalog.Variants[variant].chance <= 1 / 25) then
			task.spawn(playRoll, kind, variant)
		end
		holding = false
		catchEffect(kind, at, coop or 1, variant)
		if tut.step == 2 or tut.step == 1 then setStep(3) end
	end)

	remotes.Hit.OnClientEvent:Connect(function(lost)
		play("oniHit")
		vignette.BackgroundTransparency = 0.55
		TweenService:Create(vignette, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
		showToast(lost > 0 and ("Они разбил банку! Потеряно духов: " .. lost) or "Они попал! Банка была пуста", 3, Color3.fromRGB(140, 30, 40))
	end)
	remotes.Notice.OnClientEvent:Connect(function(text) showToast(text, 2.5) end)

end
------------------------------------------------------------------ визуал духов и следы
local visFolder, visuals, dropTrail, updateFollowers, updateOni
do
	visFolder = K.make("Folder", { Name = "SpiritVisuals" }, workspace)
	local trailFolder = K.make("Folder", { Name = "Trails" }, workspace)
	visuals = {}

	local TRAIL_SHAPE = {
		print = { size = Vector3.new(0.1, 0.7, 0.5), shape = Enum.PartType.Cylinder },
		dot = { size = Vector3.new(0.4, 0.4, 0.4), shape = Enum.PartType.Ball },
		scrap = { size = Vector3.new(0.6, 0.06, 0.4), shape = Enum.PartType.Block },
		ripple = { size = Vector3.new(0.08, 1.6, 1.6), shape = Enum.PartType.Cylinder },
		feather = { size = Vector3.new(0.25, 0.06, 0.9), shape = Enum.PartType.Block },
		ink = { size = Vector3.new(0.08, 1.0, 1.0), shape = Enum.PartType.Cylinder },
		flame = { size = Vector3.new(0.35, 0.35, 0.35), shape = Enum.PartType.Ball },
	}
	dropTrail = function(v, pos, dir)
		local tr = v.info.trail
		if not tr then return end
		local isTarget = trackKind == v.kind
		if reducedFx and not isTarget then return end
		local sh = TRAIL_SHAPE[tr.shape] or TRAIL_SHAPE.dot
		local ground = Vector3.new(pos.X, 0.58, pos.Z)
		local cf
		if sh.shape == Enum.PartType.Cylinder then
			cf = CFrame.new(ground) * CFrame.Angles(0, math.atan2(dir.X, dir.Z), math.rad(90))
		elseif tr.shape == "dot" or tr.shape == "flame" then
			cf = CFrame.new(ground + Vector3.new(0, 0.3, 0))
		else
			cf = CFrame.new(ground) * CFrame.Angles(0, math.random() * 6.28, 0)
		end
		local p = K.make("Part", {
			Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, CastShadow = false,
			Shape = sh.shape, Size = sh.size * (isTarget and 1.6 or 1), Color = tr.color, CFrame = cf,
			Material = isTarget and Enum.Material.Neon or Enum.Material.SmoothPlastic, Transparency = isTarget and 0.1 or 0.35,
		}, trailFolder)
		local life = isTarget and 14 or 8
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Linear), { Transparency = 1 }):Play()
		task.delay(life, function() p:Destroy() end)
	end

	local function addAnchor(a)
		if not a:IsA("BasePart") then return end
		local kind = a:GetAttribute("Kind")
		local info = kind and Catalog.Kinds[kind]
		if not info then return end
		local v = { anchor = a, kind = kind, info = info, seed = math.random() * 10, lastDrop = 0, lastPos = a.Position }
		if info.move ~= "swim" then
			v.shadow = Spirits.buildShadow(Catalog.Rarity[info.rarity].shadow)
			local variant = a:GetAttribute("Variant") or "normal"
			if variant ~= "normal" and variant ~= "giant" then
				local pe = v.shadow:FindFirstChildOfClass("ParticleEmitter")
				if pe then
					pe.Color = ColorSequence.new(Catalog.Variants[variant].color)
					pe.Rate = 24
				end
			end
			v.shadow.Parent = visFolder
		end
		local sid = Audio.Spirit[kind]
		if sid and sid ~= "" then
			local snd = makeSound(sid, sfxGroup, true, a, 0.7)
			if snd then
				snd.RollOffMaxDistance, snd.RollOffMinDistance = 60, 8
				snd:Play()
			end
		end
		visuals[a] = v
	end
	local function removeAnchor(a)
		local v = visuals[a]
		if not v then return end
		visuals[a] = nil
		if v.shadow then v.shadow:Destroy() end
		if v.model then v.model:Destroy() end
	end
	spiritsFolder.ChildAdded:Connect(addAnchor)
	spiritsFolder.ChildRemoved:Connect(removeAnchor)
	for _, a in spiritsFolder:GetChildren() do addAnchor(a) end

	local followers = {}
	updateFollowers = function(now)
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

	local oniModel, oniT, oniWarned = nil, 0, false
	updateOni = function(dt)
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

end
------------------------------------------------------------------ фонарь, наведение, ловля
local target, holdId, mg
do
	local highlight = K.make("Highlight", { FillTransparency = 0.75, OutlineColor = Color3.fromRGB(255, 230, 150) }, visFolder)
	target = nil
	local aimTime, revealSent = 0, {}
	holdId = nil

	local function isOpenAt(pos)
		return Catalog.unlocked(Catalog.district(pos), { distinct = state.distinct, level = state.level })
	end
	local function lanternRange() return Catalog.upgradeValue("range", plr:GetAttribute("RangeLvl") or 1) end
	local function lanternPower() return Catalog.upgradeValue("power", plr:GetAttribute("PowerLvl") or 1) end

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
			if dist < lim and isOpenAt(a.Position) then
				local fl = Vector3.new(d.X, 0, d.Z)
				local dot = fl.Magnitude > 0.5 and fl.Unit:Dot(flatLook) or 1
				-- непроявленную тень цепляет только узкий луч на средней дистанции
				local revealedA = a:GetAttribute("Revealed")
				local ok = revealedA and (dot > cone or dist < 8) or ((dot > 0.86 and dist < lim * 0.7) or dist < 5)
				if ok then
					local score = dot * 2 - dist / lim + (a:GetAttribute("Revealed") and 0.3 or 0) + (v.kind == trackKind and 0.8 or 0)
					if score > bestScore then best, bestScore = a, score end
				end
			end
		end
		return best
	end

	mg = { zone = 0.35, vel = 0, marker = 0.5, goal = 0.5, timer = 0, pressing = false, inZone = false }
	local function release()
		if holding then
			holding = false
			mg.pressing = false
			remotes.CatchHold:FireServer(nil)
		end
	end

	local currentDistrict = nil
	local districtCC = K.make("ColorCorrectionEffect", {}, Lighting)
	local wasMoon = false

	RunService.RenderStepped:Connect(function(dt)
		local now = os.clock()
		local r = root()
		if introOpen and introAngle then introAngle(now * 0.8) end
		if atlasW.Visible and spiritGrid.Visible then
			for _, c in cards do
				if c.setAngle then c.setAngle(now * 0.7 + c.frame.LayoutOrder) end
			end
		end

		-- удача: таймер зелья
		local potionLeft = math.floor((state.luckUntil or 0) - workspace:GetServerTimeNow())
		luckSub.Text = potionLeft > 0 and ("Зелье %d:%02d"):format(potionLeft // 60, potionLeft % 60) or ""

		-- событие
		local moonActive = workspace:GetAttribute("MoonActive") == true
		local ends = workspace:GetAttribute("PhaseEnds")
		if ends then
			local left = math.max(0, math.floor(ends - workspace:GetServerTimeNow()))
			local timeStr = ("%d:%02d"):format(left // 60, left % 60)
			local fogActive = workspace:GetAttribute("FogActive") == true
			local nextName = (workspace:GetAttribute("NextEvent") or "moon") == "fog" and "Туманная ночь" or "Красная луна"
			eventL.Text = moonActive and ("КРАСНАЯ ЛУНА  " .. timeStr) or (fogActive and ("ТУМАННАЯ НОЧЬ  " .. timeStr) or (nextName .. " через " .. timeStr))
			if fogActive then eventGrad.Color = ColorSequence.new(Color3.fromRGB(120, 160, 190), Color3.fromRGB(50, 80, 110)) end
		end
		if moonActive ~= wasMoon then
			wasMoon = moonActive
			eventGrad.Color = moonActive and ColorSequence.new(Color3.fromRGB(240, 70, 80), Color3.fromRGB(140, 20, 30)) or ColorSequence.new(Color3.fromRGB(70, 70, 110), Color3.fromRGB(40, 40, 70))
			K.pop(eventPill)
			if moonLayer then TweenService:Create(moonLayer, TweenInfo.new(3), { PlaybackSpeed = moonActive and 0.86 or 1 }):Play() end
			if moonActive then showToast("Красная луна! Редкие духи вышли, но по улицам ходит они", 3.5, Color3.fromRGB(140, 30, 40)) end
		end

		-- духи
		for a, v in visuals do
			local cf = a.CFrame
			local revealed = a:GetAttribute("Revealed")
			local dist = r and (cf.Position - r.Position).Magnitude or 0
			if v.shadow then
				v.shadow.CFrame = CFrame.new(cf.X, 0.62, cf.Z) * CFrame.Angles(0, now * 0.8, math.rad(90))
				-- тень видна только в луче фонаря или совсем рядом, иначе ищи по следам
				local lit = false
				if r and not revealed then
					local d = cf.Position - r.Position
					local fl = Vector3.new(d.X, 0, d.Z)
					local look = r.CFrame.LookVector
					lit = (dist < lanternRange() * 0.8 and fl.Magnitude > 0.1 and fl.Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit) > 0.8)
				end
				local goal = revealed and 0.95 or (lit and (0.35 + math.sin(now * 3 + v.seed) * 0.1) or 0.94)
				v.shadow.Transparency += (goal - v.shadow.Transparency) * math.min(1, dt * 5)
				local pe = v.shadow:FindFirstChildOfClass("ParticleEmitter")
				if pe and not revealed then
					local sparkle = v.anchor:GetAttribute("Variant")
					pe.Rate = lit and ((sparkle ~= "normal" and sparkle ~= "giant") and 24 or 8) or 0
				end
			end
			if revealed and not v.model then
				v.model = Spirits.Builders[v.kind]()
				local variant = a:GetAttribute("Variant") or "normal"
				Spirits.applyVariant(v.model, variant)
				local rk = v.info.rarity
				if not reducedFx and (rk ~= "common" and rk ~= "uncommon") then
					Spirits.aura(v.model, Catalog.Rarity[rk].color)
				end
				v.variant = variant
				v.model.Parent = visFolder
				if dist < 60 then play("reveal") end
				ring(cf.Position + Vector3.new(0, 1, 0), 2, 10, Catalog.Rarity[v.info.rarity].color, 0.4, false)
				local pe = v.shadow and v.shadow:FindFirstChildOfClass("ParticleEmitter")
				if pe then
					pe:Emit(reducedFx and 6 or 20)
					pe.Rate = 3
				end
			end
			if v.model and dist < 170 then
				local t = now + v.seed
				Spirits.animate(v.model, cf * Spirits.Pose[v.kind](t), t * v.info.animSpeed)
				if v.variant == "rainbow" and math.floor(now * 12) % 3 == 0 then Spirits.rainbowTick(v.model, now) end
			end
			if dist < 120 and now - v.lastDrop > 1.1 and (cf.Position - v.lastPos).Magnitude > 2 then
				dropTrail(v, cf.Position, cf.LookVector)
				v.lastDrop, v.lastPos = now, cf.Position
			end
		end
		updateFollowers(now)
		updateOni(dt)
		local beamPart = World:FindFirstChild("LighthouseBeam")
		if beamPart then
			local c = Vector3.new(166 * 1.6, 0.5 + 31.5 * 1.6, -66 * 1.6)
			beamPart.CFrame = CFrame.new(c) * CFrame.Angles(0, now * 0.6, 0) * CFrame.new(48, 0, 0)
		end
		if math.floor(now * 10) % 2 == 0 then
			for _, p in Players:GetPlayers() do
				if p:GetAttribute("Skin") == "vip" then
					local lamp = p.Character and p.Character:FindFirstChild("Lantern")
					if lamp then
						local c = Color3.fromHSV((now * 0.3) % 1, 0.6, 1)
						lamp.Color = c
						local beam = lamp:FindFirstChild("Beam")
						if beam then beam.Color = c end
					end
				end
			end
		end
		if not r then return end

		-- район
		local d = Catalog.district(r.Position)
		if d ~= currentDistrict then
			currentDistrict = d
			local dl = Catalog.Districts[d].luck or 1
			districtTitle.Text = Catalog.DistrictNames[d] .. (dl > 1 and ("   удача района x%.1f"):format(dl) or "")
			TweenService:Create(districtCC, TweenInfo.new(1.5), { TintColor = Catalog.Districts[d].tint }):Play()
		end
		local atAltar = (r.Position - ALTAR_POS).Magnitude < 16

		-- выслеживание
		local trackPos
		if trackKind then
			local best, bd = nil, math.huge
			for a, v in visuals do
				if v.kind == trackKind and isOpenAt(a.Position) then
					local dd = (a.Position - r.Position).Magnitude
					if dd < bd then best, bd = a, dd end
				end
			end
			local info = Catalog.Kinds[trackKind]
			if best then
				trackPos = best.Position
				trackL.Text = ("%s\nСлед: %s"):format(info.name, info.trail.text)
			else
				local places = Catalog.districtsOf(trackKind)
				local dc = places[1] and Catalog.Districts[places[1]]
				if info.moonOnly and not moonActive then
					trackL.Text = ("%s\nПоявится в Красную луну"):format(info.name)
				elseif dc and dc.unlock and not Catalog.unlocked(places[1], { distinct = state.distinct, level = state.level }) then
					trackL.Text = ("%s\nСначала открой сад"):format(info.name)
				else
					trackL.Text = ("%s\nИщи: %s"):format(info.name, info.hint)
					trackPos = dc and dc.center
				end
			end
		end

		-- наведение
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
					local vn = (v.variant and v.variant ~= "normal") and (Catalog.Variants[v.variant].name .. " ") or ""
					hintText.Text = inRange and (vn .. v.info.name) or (vn ~= "" and (vn .. v.info.name) or "")
					hintText.TextColor3 = inRange and rar.color or Color3.new(1, 1, 1)
				end
				if tut.step == 1 then setStep(2) end
			elseif v then
				local sense = state.talents and state.talents.sense or 0
				local need = rar.revealTime * 2.2 / (lanternPower() * (1 + 0.08 * sense))
				aimTime += dt
				-- контур и подсказка появляются, только когда луч держится на тени
				if aimTime > 0.3 then
					highlight.Adornee = v.shadow
					highlight.OutlineColor = rar.color
					hint.Adornee = target
					hint.StudsOffset = Vector3.new(0, 3, 0)
				end
				hintText.Text = "Свети" .. string.rep(".", math.clamp(math.floor(aimTime / need * 3), 0, 3))
				hintText.TextColor3 = Color3.fromRGB(200, 170, 255)
				if aimTime > need and not revealSent[id] then
					revealSent[id] = true
					remotes.Reveal:FireServer(id)
				end
			end
		end

		-- кнопка ловли и мини-игра
		catchBtn.Visible = (inRange or holding) and not introOpen
		mini.Visible = holding
		if holding then
			if not inRange or not target or target:GetAttribute("SpiritId") ~= holdId then
				release()
			else
				local v = visuals[target]
				local sg = Catalog.Struggle[v and v.info.rarity or "common"]
				local size = (0.27 + 0.03 * ((plr:GetAttribute("PowerLvl") or 1) - 1)) * (plr:GetAttribute("Pass_wideBeam") and Catalog.Money.WideBeamBonus or 1) * (1 + 0.04 * (state.talents and state.talents.grip or 0))
				-- зона: поднимается, пока кнопка зажата, и падает, когда отпущена
				mg.vel = math.clamp(mg.vel + (mg.pressing and 3.4 or -2.8) * dt, -1.3, 1.3)
				mg.zone += mg.vel * dt
				if mg.zone < 0 then mg.zone, mg.vel = 0, math.max(mg.vel, 0) * -0.2 end
				if mg.zone > 1 - size then mg.zone, mg.vel = 1 - size, math.min(mg.vel, 0) * -0.2 end
				-- метка духа: плавно рыскает и иногда дёргается
				mg.timer -= dt
				if mg.timer <= 0 or math.random() < sg.jitter * dt * 1.5 then
					mg.goal = math.random() * 0.9 + 0.05
					mg.timer = (0.5 + math.random()) / sg.speed
				end
				mg.marker += (mg.goal - mg.marker) * math.min(1, dt * 2.2 * sg.speed)
				local inside = mg.marker >= mg.zone and mg.marker <= mg.zone + size
				if inside ~= mg.inZone then
					mg.inZone = inside
					remotes.CatchZone:FireServer(inside)
				end
				zoneF.Size = UDim2.fromScale(1, size)
				zoneF.Position = UDim2.fromScale(0, 1 - mg.zone - size)
				zoneF.BackgroundColor3 = inside and Color3.fromRGB(120, 240, 160) or Color3.fromRGB(255, 150, 80)
				markerF.Position = UDim2.fromScale(0.5, 1 - mg.marker)
				markerStroke.Color = inside and T.ink or T.red
				local p = target:GetAttribute("Progress") or 0
				progFill.Size = UDim2.fromScale(1, math.clamp(p, 0, 1))
				fill.Size = UDim2.fromScale(1, math.clamp(p, 0, 1))
				catchBtn.Rotation = (reducedFx or inside) and 0 or math.sin(now * 40) * 4
				local holders = target:GetAttribute("Holders") or 0
				catchL.Text = holders > 1 and ("ВМЕСТЕ x" .. holders) or "ДЕРЖИ"
			end
		end
		if not holding then
			fill.Size = UDim2.fromScale(1, 0)
			catchBtn.Rotation = 0
			catchL.Text = #state.jar >= state.cap and "ПОЛНА" or "ЛОВИТЬ"
		end

		-- указатель: обучение > полная банка > цель охоты
		local goalPos
		local guideCold = true
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
		elseif tut.step == 3 or #state.jar >= state.cap then
			goalPos = ALTAR_POS + Vector3.new(0, 2, 0)
		end
		local att = r:FindFirstChild("GuideAtt")
		if not att then att = K.make("Attachment", { Name = "GuideAtt", Position = Vector3.new(0, -2, 0) }, r) end
		arrow.Attachment0 = att
		arrow.Color = ColorSequence.new(guideCold and Color3.fromRGB(140, 230, 255) or T.orange)
		arrow.Enabled = goalPos ~= nil and (goalPos - r.Position).Magnitude > 7 and not introOpen
		if goalPos then arrowPart.Position = goalPos end
		if tut.step == 4 then
			K.recolor(btnAtlas, (math.floor(now * 3) % 2 == 0) and T.gold or T.blue)
		end
	end)

end
------------------------------------------------------------------ ввод
do
	local function beginHold()
		local r = root()
		if not (r and target and target.Parent and target:GetAttribute("Revealed")) then return end
		if #state.jar >= state.cap then
			showToast("Банка полна — неси улов к алтарю")
			return
		end
		holding, holdId = true, target:GetAttribute("SpiritId")
		mg.zone, mg.vel, mg.marker, mg.goal, mg.timer, mg.inZone = 0.35, 0, 0.5, 0.5, 0, false
		K.bounce(catchBtn)
		remotes.CatchHold:FireServer(holdId)
	end
	-- первое нажатие начинает ловлю, дальше удержание поднимает зону
	local function press()
		if not holding then beginHold() end
		mg.pressing = holding
	end
	local function unpress() mg.pressing = false end
	catchBtn.MouseButton1Down:Connect(press)
	catchBtn.MouseButton1Up:Connect(unpress)
	catchBtn.MouseLeave:Connect(unpress)
	UserInputService.InputBegan:Connect(function(i, gp)
		if not gp and i.KeyCode == Enum.KeyCode.F then press() end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.KeyCode == Enum.KeyCode.F then unpress() end
	end)

end
