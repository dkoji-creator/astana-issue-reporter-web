-- Клиент: визуал духов и спутников, фонарь с мягким наведением, ловля, обучение, коллекция, улучшения, эффекты.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Catalog = require(Shared:WaitForChild("Catalog"))
local Spirits = require(Shared:WaitForChild("Spirits"))
local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spiritsFolder = workspace:WaitForChild("Spirits")
local World = workspace:WaitForChild("World")
local Altar = World:WaitForChild("Altar")
local Barrier = World:WaitForChild("GardenBarrier")
local ALTAR_POS = Altar.Position

local GOLD = Color3.fromRGB(255, 200, 80)
local COLD = Color3.fromRGB(120, 210, 255)

local function root()
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ UI-хелперы
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "SpiritHUD", false, true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = plr:WaitForChild("PlayerGui")

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 10)
	c.Parent = o
end
local function maxText(o, n)
	local c = Instance.new("UITextSizeConstraint")
	c.MaxTextSize = n
	c.Parent = o
end
local function label(text, pos, size, parent, maxSize)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency, l.TextColor3, l.Font, l.TextScaled = 0.3, Color3.new(1, 1, 1), Enum.Font.GothamBold, true
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	l.Text, l.Position, l.Size = text, pos, size
	corner(l)
	maxText(l, maxSize or 22)
	l.Parent = parent or gui
	return l
end
local function button(text, pos, size, color, parent)
	local b = Instance.new("TextButton")
	b.Text, b.Position, b.Size = text, pos, size
	b.TextScaled, b.Font, b.TextColor3 = true, Enum.Font.GothamBold, Color3.new(1, 1, 1)
	b.BackgroundColor3 = color
	corner(b)
	maxText(b, 22)
	b.Parent = parent or gui
	return b
end

------------------------------------------------------------------ HUD
local jarLabel = label("🫙 0/3", UDim2.new(0, 12, 0, 56), UDim2.new(0, 200, 0, 34))
local infoLabel = label("✦ 0   Сад: 0/3", UDim2.new(0, 12, 0, 94), UDim2.new(0, 200, 0, 26), nil, 18)
local collBtn = button("📖 Коллекция", UDim2.new(0, 12, 0, 126), UDim2.new(0, 200, 0, 38), Color3.fromRGB(70, 80, 160))
local upBtn = button("⬆ Улучшения", UDim2.new(0, 12, 0, 170), UDim2.new(0, 200, 0, 38), Color3.fromRGB(60, 140, 170))
upBtn.Visible = false
local toast = label("", UDim2.new(0.5, -190, 0, 150), UDim2.new(0, 380, 0, 38))
toast.Visible = false
local banner = label("", UDim2.new(0.5, -150, 0, 8), UDim2.new(0, 300, 0, 32), nil, 20)
local tutPanel = label("", UDim2.new(0.5, -210, 0, 46), UDim2.new(0, 420, 0, 56), nil, 20)
tutPanel.BackgroundColor3, tutPanel.Visible = Color3.fromRGB(30, 70, 110), false
local skipBtn = button("Пропустить", UDim2.new(1, -96, 1, 4), UDim2.new(0, 96, 0, 24), Color3.fromRGB(60, 60, 80), tutPanel)
local districtTitle = label("", UDim2.new(0.5, -170, 0.32, 0), UDim2.new(0, 340, 0, 46), nil, 30)
districtTitle.BackgroundTransparency, districtTitle.Visible = 1, false
districtTitle.TextStrokeTransparency = 0.3

-- компактная кнопка ловли слева от стандартной кнопки прыжка; видна только рядом с доступным духом
local catchBtn = Instance.new("TextButton")
catchBtn.AnchorPoint = Vector2.new(1, 1)
catchBtn.Size, catchBtn.Position = UDim2.new(0, 92, 0, 92), UDim2.new(1, -190, 1, -150)
catchBtn.Text, catchBtn.TextScaled, catchBtn.Font = "ЛОВИТЬ", true, Enum.Font.GothamBlack
catchBtn.BackgroundColor3, catchBtn.TextColor3 = Color3.fromRGB(80, 200, 140), Color3.new(1, 1, 1)
catchBtn.AutoButtonColor, catchBtn.Visible = false, false
corner(catchBtn, UDim.new(1, 0))
local pad = Instance.new("UIPadding")
pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
pad.Parent = catchBtn
local stroke = Instance.new("UIStroke")
stroke.Thickness, stroke.Color, stroke.ApplyStrokeMode = 3, Color3.new(1, 1, 1), Enum.ApplyStrokeMode.Border
stroke.Parent = catchBtn
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
hint.Size, hint.AlwaysOnTop = UDim2.new(0, 160, 0, 34), true
local hintText = Instance.new("TextLabel")
hintText.Size, hintText.BackgroundTransparency, hintText.TextScaled, hintText.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
hintText.TextColor3, hintText.TextStrokeTransparency = Color3.new(1, 1, 1), 0.2
hintText.Parent = hint
hint.Parent = gui

local function showToast(text, secs)
	toast.Text, toast.Visible = text, true
	task.delay(secs or 2.2, function()
		if toast.Text == text then toast.Visible = false end
	end)
end
local function punch(o)
	local s = o.Size
	o.Size = UDim2.new(s.X.Scale, s.X.Offset * 1.15, s.Y.Scale, s.Y.Offset * 1.15)
	TweenService:Create(o, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = s }):Play()
end

------------------------------------------------------------------ окна: коллекция и улучшения
local function modal(title)
	local f = Instance.new("Frame")
	f.AnchorPoint, f.Position, f.Size = Vector2.new(0.5, 0.5), UDim2.fromScale(0.5, 0.52), UDim2.fromScale(0.88, 0.8)
	f.BackgroundColor3, f.BackgroundTransparency, f.Visible = Color3.fromRGB(18, 18, 36), 0.05, false
	f.ZIndex = 10
	corner(f, UDim.new(0, 14))
	local t = label(title, UDim2.new(0, 12, 0, 6), UDim2.new(1, -70, 0, 32), f, 26)
	t.BackgroundTransparency, t.TextXAlignment = 1, Enum.TextXAlignment.Left
	local close = button("✕", UDim2.new(1, -48, 0, 6), UDim2.new(0, 40, 0, 34), Color3.fromRGB(160, 50, 60), f)
	close.Activated:Connect(function() f.Visible = false end)
	f.Parent = gui
	return f
end

local collFrame = modal("Коллекция духов")
local grid = Instance.new("ScrollingFrame")
grid.Position, grid.Size = UDim2.new(0, 8, 0, 44), UDim2.new(1, -16, 1, -52)
grid.BackgroundTransparency, grid.ScrollBarThickness = 1, 6
grid.AutomaticCanvasSize, grid.CanvasSize = Enum.AutomaticSize.Y, UDim2.new()
grid.Parent = collFrame
local layout = Instance.new("UIGridLayout")
layout.CellSize, layout.CellPadding = UDim2.new(0.25, -8, 0, 150), UDim2.new(0, 8, 0, 8)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = grid

local upFrame = modal("Улучшения у алтаря")
upFrame.Size = UDim2.fromScale(0.6, 0.62)
local upInfo = label("", UDim2.new(0, 12, 0, 44), UDim2.new(1, -24, 0, 26), upFrame, 18)
upInfo.BackgroundTransparency = 1
local function upRow(y)
	local l = label("", UDim2.new(0, 12, 0, y), UDim2.new(0.62, -12, 0, 56), upFrame, 18)
	local b = button("", UDim2.new(0.62, 8, 0, y), UDim2.new(0.38, -20, 0, 56), Color3.fromRGB(70, 160, 100), upFrame)
	return l, b
end
local lanternRow, lanternBtn = upRow(78)
local jarRow, jarBtn = upRow(142)

------------------------------------------------------------------ состояние игрока
local state = { jar = {}, cap = 3, saved = {}, materials = 0, lanternLvl = 1, jarLvl = 1, tutorialDone = true, gardenOpen = false, distinct = 0 }
local cards = {}

local function refreshCollection()
	for i, kind in Catalog.Order do
		local info = Catalog.Kinds[kind]
		local rar = Catalog.Rarity[info.rarity]
		local c = cards[kind]
		if not c then
			c = {}
			local f = Instance.new("Frame")
			f.LayoutOrder, f.BackgroundColor3 = i, Color3.fromRGB(35, 35, 60)
			corner(f)
			local st = Instance.new("UIStroke")
			st.Thickness, st.Color = 2, rar.color
			st.Parent = f
			c.icon = label("", UDim2.new(0, 4, 0, 4), UDim2.new(1, -8, 0, 40), f, 34)
			c.icon.BackgroundTransparency = 1
			c.name = label("", UDim2.new(0, 4, 0, 44), UDim2.new(1, -8, 0, 22), f, 16)
			c.name.BackgroundTransparency = 1
			c.rar = label(rar.name, UDim2.new(0, 4, 0, 64), UDim2.new(1, -8, 0, 16), f, 13)
			c.rar.BackgroundTransparency, c.rar.TextColor3 = 1, rar.color
			c.hint = label("", UDim2.new(0, 4, 0, 80), UDim2.new(1, -8, 0, 32), f, 12)
			c.hint.BackgroundTransparency, c.hint.TextColor3, c.hint.Font = 1, Color3.fromRGB(200, 200, 220), Enum.Font.Gotham
			c.equip = button("", UDim2.new(0, 6, 1, -34), UDim2.new(1, -12, 0, 28), Color3.fromRGB(200, 60, 70), f)
			c.equip.Activated:Connect(function()
				remotes.Equip:InvokeServer(state.equipped ~= kind and kind or nil)
			end)
			f.Parent = grid
			cards[kind] = c
		end
		local n = state.saved[kind] or 0
		c.icon.Text = n > 0 and info.icon or "❔"
		c.name.Text = n > 0 and (info.name .. "  ×" .. n) or "???"
		c.hint.Text = (n > 0 and "Где: " or "Ищи: ") .. info.hint
		c.equip.Visible = n > 0
		c.equip.Text = state.equipped == kind and "Снять" or "Экипировать"
		c.equip.BackgroundColor3 = state.equipped == kind and Color3.fromRGB(90, 90, 110) or Color3.fromRGB(200, 60, 70)
	end
end

local function refreshUpgrades()
	upInfo.Text = ("Материал: ✦%d   (дубликаты при сохранении дают материал)"):format(state.materials)
	local function row(lbl, btn, lvl, cur, nxt)
		if lvl >= Catalog.MaxLevel then
			lbl.Text = cur .. "  (макс.)"
			btn.Text, btn.AutoButtonColor, btn.BackgroundColor3 = "Готово", false, Color3.fromRGB(80, 80, 90)
		else
			local cost = Catalog.UpgradeCost[lvl]
			lbl.Text = cur .. "  →  " .. nxt
			btn.Text = ("Улучшить ✦%d"):format(cost)
			btn.BackgroundColor3 = state.materials >= cost and Color3.fromRGB(70, 160, 100) or Color3.fromRGB(90, 90, 100)
		end
	end
	local l = state.lanternLvl
	row(lanternRow, lanternBtn, l, ("🔦 Фонарь ур.%d: %d м, ловля ×%.2g"):format(l, Catalog.LanternRange[l], Catalog.LanternSpeed[l]),
		l < Catalog.MaxLevel and ("%d м, ×%.2g"):format(Catalog.LanternRange[l + 1], Catalog.LanternSpeed[l + 1]) or "")
	local j = state.jarLvl
	row(jarRow, jarBtn, j, ("🫙 Банка ур.%d: %d духа"):format(j, Catalog.JarCap[j]), j < Catalog.MaxLevel and ("%d"):format(Catalog.JarCap[j + 1]) or "")
end
local function doUpgrade(which)
	local r = remotes.Upgrade:InvokeServer(which)
	if r and r.ok then
		showToast(which == "lantern" and "Фонарь улучшен!" or "Банка стала вместительнее!")
		punch(which == "lantern" and lanternRow or jarRow)
	elseif r and r.msg then
		showToast(r.msg)
	end
end
lanternBtn.Activated:Connect(function() doUpgrade("lantern") end)
jarBtn.Activated:Connect(function() doUpgrade("jar") end)
collBtn.Activated:Connect(function()
	refreshCollection()
	collFrame.Visible = not collFrame.Visible
	upFrame.Visible = false
end)
upBtn.Activated:Connect(function()
	refreshUpgrades()
	upFrame.Visible = not upFrame.Visible
	collFrame.Visible = false
end)

local function refreshHUD()
	local icons = ""
	for _, k in state.jar do icons ..= Catalog.Kinds[k].icon end
	jarLabel.Text = ("🫙 %d/%d %s"):format(#state.jar, state.cap, icons)
	jarLabel.BackgroundColor3 = #state.jar >= state.cap and Color3.fromRGB(150, 60, 30) or Color3.fromRGB(20, 20, 40)
	infoLabel.Text = state.gardenOpen and ("✦ %d   Сад открыт"):format(state.materials)
		or ("✦ %d   Сад: %d/%d вида"):format(state.materials, math.min(state.distinct, Catalog.GardenNeed), Catalog.GardenNeed)
	-- ворота сада: открыты локально, сервер всё равно проверяет доступ
	Barrier.CanCollide = not state.gardenOpen
	Barrier.Transparency = state.gardenOpen and 0.85 or 0.2
	if collFrame.Visible then refreshCollection() end
	if upFrame.Visible then refreshUpgrades() end
end

------------------------------------------------------------------ эффекты
local function ring(pos, fromSize, toSize, color, secs, upright)
	local r = Instance.new("Part")
	r.Shape, r.Anchored, r.CanCollide, r.CanQuery, r.CastShadow = Enum.PartType.Cylinder, true, false, false, false
	r.Material, r.Color, r.Transparency = Enum.Material.Neon, color, 0.15
	r.Size = Vector3.new(0.15, fromSize, fromSize)
	r.CFrame = CFrame.new(pos) * (upright and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90)))
	r.Parent = workspace
	TweenService:Create(r, TweenInfo.new(secs, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, toSize, toSize), Transparency = 1 }):Play()
	task.delay(secs + 0.05, function() r:Destroy() end)
end

local function burst(pos, colors, n)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.Transparency, a.Size, a.Position = true, false, false, 1, Vector3.one, pos
	a.Parent = workspace
	local pe = Instance.new("ParticleEmitter")
	pe.Color = colors
	pe.Rate, pe.Lifetime, pe.Speed = 0, NumberRange.new(0.6, 1.1), NumberRange.new(8, 16)
	pe.SpreadAngle, pe.RotSpeed = Vector2.new(180, 180), NumberRange.new(-200, 200)
	pe.Size = NumberSequence.new(0.5, 0.1)
	pe.LightEmission, pe.Acceleration = 0.4, Vector3.new(0, -14, 0)
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
	local m = Spirits.Builders[kind]()
	if kind == "GoldenCarp" then Spirits.scale(m, 0.6) end
	m.Parent = workspace
	local big = info.rarity ~= "common"
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
			punch(jarLabel)
		end
	end)
	local text = info.icon .. " " .. info.name .. " в банке!"
	if coop > 1 then text ..= ("  Совместная ловля ×%d"):format(coop)
	elseif streak > 1 then text ..= "  Серия ×" .. streak end
	if info.rarity == "legendary" then text = "✦ " .. info.name .. "! Неси к алтарю ✦" end
	showToast(text, 2.5)
end

-- раскрытие легендарного духа (~2 с): силуэт → пауза → световое кольцо → цвет и облёт вокруг игрока
local revealCC = Instance.new("ColorCorrectionEffect")
revealCC.Parent = Lighting
local function revealLegendary(kind)
	local r = root()
	if not r then return end
	local m = Spirits.Builders[kind]()
	Spirits.scale(m, 0.55)
	local orig = {}
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			orig[p] = { p.Color, p.Material, p.Transparency, p.Reflectance }
			if p.Name == "Fin" or p.Name == "Whisker" then
				p.Color, p.Material, p.Transparency = GOLD, Enum.Material.Neon, 0.25
			else
				p.Color, p.Material, p.Reflectance = Color3.fromRGB(8, 6, 12), Enum.Material.SmoothPlastic, 0
			end
		elseif p:IsA("Trail") or p:IsA("PointLight") then
			p.Enabled = false
		end
	end
	m.Parent = workspace
	TweenService:Create(revealCC, TweenInfo.new(0.2), { Brightness = -0.18, Saturation = -0.7 }):Play()
	local t0 = os.clock()
	local colored, ringed = false, false
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local cr = root() or r
		local pivot
		if t < 0.9 then
			local front = cr.CFrame * CFrame.new(0, 2, -9)
			pivot = CFrame.lookAt(front.Position, front.Position + cr.CFrame.RightVector) * CFrame.new(0, math.sin(t * 3) * 0.2, 0)
		else
			local look = cr.CFrame.LookVector
			local a = (t - 0.9) * 5.2 + math.atan2(-look.X, -look.Z)
			local p = cr.Position + Vector3.new(math.sin(a) * 8, 2.5 + math.sin(t * 4) * 0.5, math.cos(a) * 8)
			pivot = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, -math.sin(a)))
		end
		Spirits.animate(m, pivot, t * 4)
		if t > 0.55 and not ringed then
			ringed = true
			ring(pivot.Position, 2, 26, GOLD, 0.45, true)
		end
		if t > 0.75 and not colored then
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
		if t > 1.8 then
			for p in orig do TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
		end
		if t > 2.1 then
			conn:Disconnect()
			m:Destroy()
		end
	end)
	showToast("✦ " .. Catalog.Kinds[kind].name .. " в коллекции! ✦", 2.5)
end

------------------------------------------------------------------ обучение (первая минута)
local tut = { step = 0 }
local TUT_TEXT = {
	"1/4  Найди фиолетовую тень у площади и наведи на неё фонарь",
	"2/4  Подойди и удерживай ЛОВИТЬ, пока дух не окажется в банке",
	"3/4  Отнеси улов к алтарю (голубой луч) и нажми «Сохранить улов»",
	"4/4  Открой «📖 Коллекция» и экипируй лиса",
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
		arrow.Enabled = false
	end
end
local function finishTutorial()
	if tut.step == 0 or tut.step == 5 then return end
	setStep(5)
	remotes.TutorialDone:FireServer()
	showToast("Обучение пройдено! Сохрани 3 разных духа — откроется Храмовый сад", 4)
end
skipBtn.Activated:Connect(finishTutorial)

------------------------------------------------------------------ серверные события
local firstState = true
remotes.State.OnClientEvent:Connect(function(s)
	state = s
	refreshHUD()
	if firstState then
		firstState = false
		if not s.tutorialDone then setStep(1) end
		if s.persistent == false then showToast("Сохранения недоступны в этом запуске", 3) end
	end
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
		local cr = root()
		if cr then
			ring(cr.Position + Vector3.new(0, 5, 0), 12, 1, COLD, 0.5, false)
			burst(cr.Position + Vector3.new(0, 2, 0), ColorSequence.new(COLD, Color3.new(1, 1, 1)), 30)
		end
		local msg = ("Сохранено духов: %d"):format(#r.kinds)
		if #r.firsts > 0 then msg ..= "  Новые: " .. #r.firsts end
		if r.gained > 0 then msg ..= ("  +✦%d"):format(r.gained) end
		if not r.persisted then msg ..= " (без DataStore)" end
		showToast(msg, 3)
	end
	if r.gardenOpened then
		task.delay(legendary and 2.3 or 1.2, function() showToast("🏯 Храмовый сад открыт! Иди на юг за канал", 4) end)
	end
	if tut.step == 3 then setStep(4) end
end)

remotes.Caught.OnClientEvent:Connect(function(kind, at, coop)
	catchEffect(kind, at, coop or 1)
	if tut.step == 2 or tut.step == 1 then setStep(3) end
end)

remotes.Hit.OnClientEvent:Connect(function(lost)
	vignette.BackgroundTransparency = 0.55
	TweenService:Create(vignette, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	showToast(lost > 0 and ("Они разбил банку! Потеряно духов: " .. lost) or "Они попал! Банка была пуста", 3)
end)
remotes.Notice.OnClientEvent:Connect(function(text) showToast(text, 2.5) end)

------------------------------------------------------------------ визуал духов
local visFolder = Instance.new("Folder")
visFolder.Name = "SpiritVisuals"
visFolder.Parent = workspace
local visuals = {}

local function addAnchor(a)
	if not a:IsA("BasePart") then return end
	local kind = a:GetAttribute("Kind")
	local info = kind and Catalog.Kinds[kind]
	if not info then return end
	local v = { anchor = a, kind = kind, info = info, seed = math.random() * 10 }
	if info.move ~= "swim" then
		v.shadow = Spirits.buildShadow(Catalog.Rarity[info.rarity].shadow)
		v.shadow.Parent = visFolder
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

-- спутники всех игроков (видны всем)
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

-- они: модель строится у каждого клиента, сервер двигает опору
local oniModel, oniT = nil, 0
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
	elseif st == "windup" then
		pose = CFrame.Angles(math.rad(-12), 0, 0) * CFrame.new(math.sin(os.clock() * 40) * 0.15, 0, 0)
		oniT = math.pi / 2
	else
		pose = CFrame.new(0, 0, -1) * CFrame.Angles(math.rad(18), 0, 0)
		oniT = -math.pi / 2
	end
	Spirits.animate(oniModel, a.CFrame * pose, oniT)
end

------------------------------------------------------------------ фонарь и мягкое наведение
local highlight = Instance.new("Highlight")
highlight.FillTransparency, highlight.OutlineColor = 0.7, Color3.fromRGB(255, 230, 150)
highlight.Parent = visFolder

local target: BasePart? = nil
local aimTime, revealSent = 0, {}
local holding, holdId = false, nil

local function lanternRange()
	return Catalog.LanternRange[plr:GetAttribute("LanternLvl") or 1]
end

local function findTarget(r)
	local best, bestScore = nil, -math.huge
	local look = r.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	local range = lanternRange()
	for a, v in visuals do
		local d = a.Position - r.Position
		local dist = d.Magnitude
		local rng = v.info.move == "swim" and range + 8 or range
		if dist < rng and (v.anchor.Position.Z > -73 or state.gardenOpen) then
			local flat = Vector3.new(d.X, 0, d.Z)
			local dot = flat.Magnitude > 0.5 and flat.Unit:Dot(flatLook) or 1
			if dot > 0.7 or dist < 8 then
				local score = dot * 2 - dist / rng + (a:GetAttribute("Revealed") and 0.3 or 0)
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
local TINT = {
	street = Color3.fromRGB(255, 238, 220),
	plaza = Color3.fromRGB(235, 245, 255),
	canal = Color3.fromRGB(220, 240, 255),
	garden = Color3.fromRGB(230, 255, 235),
}

RunService.RenderStepped:Connect(function(dt)
	local now = os.clock()
	local r = root()

	-- фаза Красной луны
	local ends = workspace:GetAttribute("PhaseEnds")
	if ends then
		local left = math.max(0, math.floor(ends - workspace:GetServerTimeNow()))
		local timeStr = ("%d:%02d"):format(left // 60, left % 60)
		if workspace:GetAttribute("MoonActive") then
			banner.Text = "🌕 КРАСНАЯ ЛУНА " .. timeStr
			banner.BackgroundColor3, banner.BackgroundTransparency = Color3.fromRGB(130, 15, 25), 0.1
		else
			banner.Text = "До Красной луны " .. timeStr
			banner.BackgroundColor3, banner.BackgroundTransparency = Color3.fromRGB(20, 20, 40), 0.3
		end
	end

	-- духи: тени и проявленные модели
	for a, v in visuals do
		local cf = a.CFrame
		local revealed = a:GetAttribute("Revealed")
		local near = not r or (cf.Position - r.Position).Magnitude < 170
		if v.shadow then
			local g = Vector3.new(cf.X, 0.62, cf.Z)
			v.shadow.CFrame = CFrame.new(g) * CFrame.Angles(0, now * 0.8, math.rad(90))
			v.shadow.Transparency = revealed and 0.85 or 0.2 + math.sin(now * 3 + v.seed) * 0.1
		end
		if revealed and not v.model then
			v.model = Spirits.Builders[v.kind]()
			v.model.Parent = visFolder
			ring(cf.Position + Vector3.new(0, 1, 0), 2, 10, Catalog.Rarity[v.info.rarity].color, 0.4, false)
			local pe = v.shadow and v.shadow:FindFirstChildOfClass("ParticleEmitter")
			if pe then pe:Emit(25) pe.Rate = 3 end
		end
		if v.model and near then
			local t = now + v.seed
			Spirits.animate(v.model, cf * Spirits.Pose[v.kind](t), t * v.info.animSpeed)
		end
	end
	updateFollowers(now)
	updateOni(dt)
	if not r then return end

	-- район: подпись и оттенок света
	local d = Catalog.district(r.Position.Z)
	if d ~= currentDistrict then
		currentDistrict = d
		districtTitle.Text, districtTitle.Visible = Catalog.DistrictNames[d], true
		districtTitle.TextTransparency = 0
		TweenService:Create(districtTitle, TweenInfo.new(1, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, 1.6), { TextTransparency = 1 }):Play()
		TweenService:Create(districtCC, TweenInfo.new(1.5), { TintColor = TINT[d] }):Play()
	end
	local nearAltar = (r.Position - ALTAR_POS).Magnitude < 24
	upBtn.Visible = nearAltar
	if not nearAltar then upFrame.Visible = false end

	-- выбор цели и мягкое наведение луча
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
	if target and target.Parent then
		local v = visuals[target]
		local id = target:GetAttribute("SpiritId")
		local dist = (target.Position - r.Position).Magnitude
		local rar = v and Catalog.Rarity[v.info.rarity]
		if target:GetAttribute("Revealed") then
			highlight.Adornee = v and v.model
			highlight.OutlineColor = rar and rar.color or Color3.new(1, 1, 1)
			inRange = v and dist < Catalog.catchRange(v.kind)
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, 7, 0)
			local full = #state.jar >= state.cap
			local holders = target:GetAttribute("Holders") or 0
			if full then
				hintText.Text, hintText.TextColor3 = "Банка полна!", Color3.fromRGB(255, 160, 120)
			elseif holders > 1 then
				hintText.Text, hintText.TextColor3 = ("Ловим вместе ×%d"):format(holders), GOLD
			else
				hintText.Text = inRange and (v.info.name) or "Подойди ближе"
				hintText.TextColor3 = inRange and Color3.fromRGB(140, 255, 180) or Color3.new(1, 1, 1)
			end
			if tut.step == 1 then setStep(2) end
		elseif v then
			highlight.Adornee = v.shadow
			highlight.OutlineColor = rar.color
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, 3, 0)
			local need = rar.revealTime / Catalog.LanternSpeed[plr:GetAttribute("LanternLvl") or 1]
			aimTime += dt
			hintText.Text = "Свети… " .. string.rep("•", math.clamp(math.floor(aimTime / need * 3), 0, 3))
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
			catchBtn.Rotation = math.sin(now * 40) * 4 * p
			local holders = target:GetAttribute("Holders") or 0
			catchBtn.Text = holders > 1 and ("×" .. holders) or "ЛОВИТЬ"
		end
	end
	if not holding then
		fill.Size = UDim2.new(1, 0, 0, 0)
		catchBtn.Rotation = 0
		catchBtn.Text = #state.jar >= state.cap and "ПОЛНА" or "ЛОВИТЬ"
	end

	-- стрелка обучения
	if tut.step >= 1 and tut.step <= 3 then
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
		else
			goalPos = ALTAR_POS + Vector3.new(0, 2, 0)
		end
		local att = r:FindFirstChild("TutAtt")
		if not att then
			att = Instance.new("Attachment")
			att.Name = "TutAtt"
			att.Position = Vector3.new(0, -2, 0)
			att.Parent = r
		end
		arrow.Attachment0 = att
		arrow.Enabled = goalPos ~= nil and (goalPos - r.Position).Magnitude > 6
		if goalPos then arrowPart.Position = goalPos end
	elseif tut.step == 4 then
		arrow.Enabled = false
		collBtn.BackgroundColor3 = (math.floor(now * 3) % 2 == 0) and Color3.fromRGB(230, 160, 40) or Color3.fromRGB(70, 80, 160)
	else
		arrow.Enabled = false
		collBtn.BackgroundColor3 = Color3.fromRGB(70, 80, 160)
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
-- ПК/Studio: клавиша F
UserInputService.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.F then beginHold() end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.F then release() end
end)
