-- Клиент: фонарь с мягким наведением, контекстная кнопка ловли, HUD, эффекты, раскрытие карпа.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")

local Spirits = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Spirits"))
local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spiritsFolder = workspace:WaitForChild("Spirits")

local AIM_RANGE, AIM_CONE = 32, math.cos(math.rad(45))
local CATCH_RANGE = 14
local GOLD = Color3.fromRGB(255, 200, 80)
local ICON = { PaperFox = "🦊", GoldenCarp = "🐟" }

local function root()
	return plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ UI
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "SpiritHUD", false, true
gui.Parent = plr:WaitForChild("PlayerGui")

local function corner(o, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = r or UDim.new(0, 10)
	c.Parent = o
end
local function label(text, pos, size, parent)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency, l.TextColor3, l.Font, l.TextScaled = 0.35, Color3.new(1, 1, 1), Enum.Font.GothamBold, true
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	l.Text, l.Position, l.Size = text, pos, size
	corner(l)
	l.Parent = parent or gui
	return l
end
local jarLabel = label("Банка: пусто", UDim2.new(0, 16, 0, 60), UDim2.new(0, 190, 0, 36))
local savedLabel = label("Коллекция: 0", UDim2.new(0, 16, 0, 100), UDim2.new(0, 190, 0, 28))
local toast = label("", UDim2.new(0.5, -180, 0, 110), UDim2.new(0, 360, 0, 40))
toast.Visible = false
local banner = label("", UDim2.new(0.5, -200, 0, 58), UDim2.new(0, 400, 0, 44))
banner.BackgroundColor3, banner.Visible = Color3.fromRGB(110, 15, 25), false

-- компактная кнопка ловли слева от стандартной кнопки прыжка; видна только рядом с доступным духом
local catchBtn = Instance.new("TextButton")
catchBtn.Name = "Catch"
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
stroke.Thickness, stroke.Color = 3, Color3.new(1, 1, 1)
stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
stroke.Parent = catchBtn
catchBtn.Parent = gui
local fill = Instance.new("Frame")
fill.BackgroundColor3, fill.BackgroundTransparency = Color3.new(1, 1, 1), 0.45
fill.Size, fill.AnchorPoint, fill.Position, fill.ZIndex = UDim2.new(1, 0, 0, 0), Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), 0
corner(fill, UDim.new(1, 0))
fill.Parent = catchBtn

local equipBtn = Instance.new("TextButton")
equipBtn.Size, equipBtn.Position = UDim2.new(0, 190, 0, 40), UDim2.new(0, 16, 0, 134)
equipBtn.TextScaled, equipBtn.Font = true, Enum.Font.GothamBold
equipBtn.BackgroundColor3, equipBtn.TextColor3 = Color3.fromRGB(200, 60, 70), Color3.new(1, 1, 1)
equipBtn.Visible = false
corner(equipBtn)
equipBtn.Parent = gui

local vignette = Instance.new("Frame")
vignette.Size, vignette.BackgroundTransparency, vignette.Visible = UDim2.fromScale(1, 1), 1, true
vignette.BackgroundColor3 = Color3.fromRGB(200, 0, 0)
vignette.Parent = gui

-- подсказка над духом
local hint = Instance.new("BillboardGui")
hint.Size, hint.StudsOffset, hint.AlwaysOnTop = UDim2.new(0, 150, 0, 34), Vector3.new(0, 7, 0), true
local hintText = Instance.new("TextLabel")
hintText.Size, hintText.BackgroundTransparency, hintText.TextScaled, hintText.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
hintText.TextColor3, hintText.TextStrokeTransparency = Color3.new(1, 1, 1), 0.2
hintText.Parent = hint
hint.Parent = gui

local function showToast(text, secs)
	toast.Text, toast.Visible = text, true
	task.delay(secs or 2, function()
		if toast.Text == text then toast.Visible = false end
	end)
end
local function punch(o)
	local s = o.Size
	o.Size = UDim2.new(s.X.Scale, s.X.Offset * 1.2, s.Y.Scale, s.Y.Offset * 1.2)
	TweenService:Create(o, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = s }):Play()
end

------------------------------------------------------------------ эффекты
local function ring(pos, fromSize, toSize, color, secs, upright)
	local r = Instance.new("Part")
	r.Shape, r.Anchored, r.CanCollide, r.CanQuery, r.CastShadow = Enum.PartType.Cylinder, true, false, false, false
	r.Material, r.Color, r.Transparency = Enum.Material.Neon, color, 0.15
	r.Size = Vector3.new(0.15, fromSize, fromSize)
	local rot = upright and CFrame.Angles(0, math.rad(90), 0) or CFrame.Angles(0, 0, math.rad(90))
	r.CFrame = CFrame.new(pos) * rot
	r.Parent = workspace
	TweenService:Create(r, TweenInfo.new(secs, Enum.EasingStyle.Quad), { Size = Vector3.new(0.1, toSize, toSize), Transparency = 1 }):Play()
	task.delay(secs + 0.05, function() r:Destroy() end)
	return r
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

-- поимка: дух сворачивается, крутясь, в банку на поясе
local streak, lastCatch = 0, 0
local function catchEffect(kind, at)
	local r = root()
	if not r then return end
	streak = (os.clock() - lastCatch < 20) and streak + 1 or 1
	lastCatch = os.clock()
	local build = Spirits.Builders[kind]
	local m = build()
	if kind == "GoldenCarp" then Spirits.scale(m, 0.6) end
	m.Parent = workspace
	local t0 = os.clock()
	local dur = kind == "GoldenCarp" and 0.9 or 0.55
	ring(at + Vector3.new(0, 2, 0), kind == "GoldenCarp" and 18 or 8, 2, kind == "GoldenCarp" and GOLD or Color3.fromRGB(255, 220, 170), dur, true)
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
		Spirits.animate(m, CFrame.new(pos) * CFrame.Angles(0, p * 12, 0) * CFrame.new(0, 0, 0), os.clock() * 15)
		if p >= 1 then
			conn:Disconnect()
			m:Destroy()
			local cols = kind == "GoldenCarp" and ColorSequence.new(GOLD, Color3.fromRGB(255, 150, 40))
				or ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(220, 50, 60))
			burst(goal, cols, kind == "GoldenCarp" and 60 or 25)
			ring(goal, 1, kind == "GoldenCarp" and 14 or 6, kind == "GoldenCarp" and GOLD or Color3.fromRGB(255, 230, 200), 0.35, false)
			punch(jarLabel)
		end
	end)
	if kind == "GoldenCarp" then
		showToast("✦ ЗОЛОТОЙ КАРП в банке! Неси к алтарю ✦", 3)
	else
		showToast(streak > 1 and ("Бумажный лис! Серия x" .. streak) or "Бумажный лис в банке!", 2)
	end
end

-- раскрытие карпа при первом сохранении (~2 с): силуэт → пауза → кольцо → цвет → круг вокруг игрока
local revealCC = Instance.new("ColorCorrectionEffect")
revealCC.Name = "RevealDim"
revealCC.Parent = Lighting
local function revealCarp()
	local r = root()
	if not r then return end
	local m = Spirits.buildGoldenCarp()
	Spirits.scale(m, 0.55)
	local orig = {}
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			orig[p] = { p.Color, p.Material, p.Transparency, p.Reflectance }
			if p.Name == "Fin" or p.Name == "Whisker" then
				p.Color, p.Material, p.Transparency = GOLD, Enum.Material.Neon, 0.25 -- подсвеченные плавники
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
		local center = cr.Position + Vector3.new(0, 1.5, 0)
		local pivot
		if t < 0.9 then
			-- силуэт висит перед игроком
			local front = cr.CFrame * CFrame.new(0, 2, -9)
			pivot = CFrame.lookAt(front.Position, front.Position + cr.CFrame.RightVector) * CFrame.new(0, math.sin(t * 3) * 0.2, 0)
		else
			-- облёт вокруг игрока
			local a = (t - 0.9) * 5.2 + math.atan2(-(cr.CFrame.LookVector.X), -(cr.CFrame.LookVector.Z))
			local p = center + Vector3.new(math.sin(a) * 8, 1 + math.sin(t * 4) * 0.5, math.cos(a) * 8)
			local tangent = Vector3.new(math.cos(a), 0, -math.sin(a))
			pivot = CFrame.lookAt(p, p + tangent)
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
		if t > 1.85 then
			for p in orig do
				TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			end
		end
		if t > 2.15 then
			conn:Disconnect()
			m:Destroy()
		end
	end)
	showToast("✦ Золотой карп в коллекции! ✦", 2.5)
end

------------------------------------------------------------------ состояние
local state = { jar = 0, jarKinds = {}, saved = {}, equipped = nil }
local owned = {}

local function refreshEquip()
	owned = {}
	for _, k in { "PaperFox", "GoldenCarp" } do
		if (state.saved[k] or 0) > 0 then table.insert(owned, k) end
	end
	equipBtn.Visible = #owned > 0
	equipBtn.Text = state.equipped and ("Спутник: " .. Spirits.Names[state.equipped]) or "Экипировать духа"
end

remotes.State.OnClientEvent:Connect(function(s)
	if s.saveResult then
		local r = s.saveResult
		if not r.ok then
			showToast(r.msg)
			return
		end
		local hasNewCarp = table.find(r.firsts, "GoldenCarp") ~= nil
		if hasNewCarp then
			revealCarp()
		else
			local cr = root()
			if cr then
				ring(cr.Position + Vector3.new(0, 5, 0), 12, 1, Color3.fromRGB(120, 200, 255), 0.5, false)
				burst(cr.Position + Vector3.new(0, 2, 0), ColorSequence.new(Color3.fromRGB(120, 200, 255), Color3.new(1, 1, 1)), 30)
			end
			showToast(("Сохранено духов: %d"):format(r.count) .. (r.persisted and "" or " (без DataStore)"))
		end
		return
	end
	state = s
	if s.jar == 0 then
		jarLabel.Text = "Банка: пусто"
	else
		local icons = ""
		for _, k in s.jarKinds do icons ..= (ICON[k] or "?") end
		jarLabel.Text = "Банка: " .. icons
	end
	local total = 0
	for _, n in s.saved do total += n end
	savedLabel.Text = "Коллекция: " .. total
	refreshEquip()
end)

equipBtn.Activated:Connect(function()
	-- по кругу: нет → лис → карп → нет
	local order = table.clone(owned)
	table.insert(order, false)
	local idx = table.find(order, state.equipped or false) or #order
	local nextKind = order[idx % #order + 1]
	remotes.Equip:InvokeServer(nextKind or nil)
end)

remotes.Caught.OnClientEvent:Connect(catchEffect)

local moonEnds = 0
remotes.Moon.OnClientEvent:Connect(function(active, secs)
	if active then
		moonEnds = os.clock() + (secs or 75)
		banner.Visible = true
		showToast("Над каналом золотой карп! Сохраниться у алтаря или рискнуть?", 4)
	else
		banner.Visible = false
		showToast("Красная луна ушла", 2)
	end
end)

remotes.Hit.OnClientEvent:Connect(function(lost)
	vignette.BackgroundTransparency = 0.55
	TweenService:Create(vignette, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	showToast(lost > 0 and ("Они разбил банку! Потеряно духов: " .. lost) or "Они попал! Банка была пуста", 3)
end)

------------------------------------------------------------------ фонарь и мягкое наведение
local beamPart
local function setupLight(char)
	local r = char:WaitForChild("HumanoidRootPart")
	beamPart = Instance.new("Part")
	beamPart.Name = "Lantern"
	beamPart.Size, beamPart.CanCollide, beamPart.Massless, beamPart.CanQuery = Vector3.new(0.5, 0.7, 0.5), false, true, false
	beamPart.Material, beamPart.Color = Enum.Material.Neon, Color3.fromRGB(255, 230, 170)
	beamPart.Parent = char
	local w = Instance.new("Weld")
	w.Part0, w.Part1, w.C0 = r, beamPart, CFrame.new(0.9, 0.3, -0.9)
	w.Parent = beamPart
	local sl = Instance.new("SpotLight")
	sl.Range, sl.Angle, sl.Brightness, sl.Face = AIM_RANGE, 40, 6, Enum.NormalId.Front
	sl.Color = Color3.fromRGB(255, 240, 200)
	sl.Parent = beamPart
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 8, 0.8, Color3.fromRGB(255, 220, 160)
	pl.Parent = beamPart
end
plr.CharacterAdded:Connect(setupLight)
if plr.Character then task.spawn(setupLight, plr.Character) end

local highlight = Instance.new("Highlight")
highlight.FillTransparency, highlight.OutlineColor = 0.7, Color3.fromRGB(255, 230, 150)
highlight.Parent = gui

local target: BasePart? = nil
local aimTime, revealSent = 0, {}
local holding, holdStart, holdId, holdTime = false, 0, nil, 1.5

local function findTarget(r)
	local best, bestScore = nil, -math.huge
	local look = r.CFrame.LookVector
	local flatLook = Vector3.new(look.X, 0, look.Z).Unit
	for _, s in spiritsFolder:GetChildren() do
		if s:IsA("BasePart") and s.Name == "Shadow" then
			local d = s.Position - r.Position
			local dist = d.Magnitude
			local range = s:GetAttribute("Kind") == "GoldenCarp" and AIM_RANGE + 6 or AIM_RANGE
			if dist < range then
				local flat = Vector3.new(d.X, 0, d.Z)
				local dot = flat.Magnitude > 0.5 and flat.Unit:Dot(flatLook) or 1
				-- рядом стоящий дух можно ловить и сбоку
				if dot > AIM_CONE or dist < 7 then
					local score = dot * 2 - dist / range + (s:GetAttribute("Revealed") and 0.3 or 0)
					if score > bestScore then best, bestScore = s, score end
				end
			end
		end
	end
	return best
end

local function modelFor(id)
	for _, m in spiritsFolder:GetChildren() do
		if m:IsA("Model") and m:GetAttribute("SpiritId") == id then return m end
	end
end

RunService.RenderStepped:Connect(function(dt)
	local r = root()
	if not r then return end
	if banner.Visible then
		banner.Text = ("🌕 КРАСНАЯ ЛУНА  %d с"):format(math.max(0, math.ceil(moonEnds - os.clock())))
	end
	local t = holding and target or findTarget(r)
	if t ~= target then target, aimTime = t, 0 end
	-- мягкое наведение луча на ближайшего духа перед игроком
	if beamPart and beamPart:FindFirstChild("Weld") then
		local w = beamPart.Weld
		local goal = CFrame.new(0.9, 0.3, -0.9)
		if target and target.Parent then
			local localDir = r.CFrame:VectorToObjectSpace((target.Position - r.Position).Unit)
			goal = CFrame.lookAt(goal.Position, goal.Position + localDir)
		end
		w.C0 = w.C0:Lerp(goal, math.min(1, dt * 6))
	end
	highlight.Adornee = nil
	hint.Adornee = nil
	local inRange = false
	if target and target.Parent then
		local id = target:GetAttribute("SpiritId")
		local dist = (target.Position - r.Position).Magnitude
		local isCarp = target:GetAttribute("Kind") == "GoldenCarp"
		if target:GetAttribute("Revealed") then
			highlight.Adornee = modelFor(id)
			highlight.OutlineColor = isCarp and GOLD or Color3.fromRGB(255, 230, 150)
			inRange = dist < CATCH_RANGE + (isCarp and 4 or 0)
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, isCarp and 6 or 8, 0)
			hintText.Text = inRange and "Держи ЛОВИТЬ" or "Подойди ближе"
			hintText.TextColor3 = inRange and Color3.fromRGB(140, 255, 180) or Color3.new(1, 1, 1)
		else
			highlight.Adornee = target
			hint.Adornee = target
			hint.StudsOffset = Vector3.new(0, 3, 0)
			hintText.Text = "Свети… " .. string.rep("•", math.clamp(math.floor(aimTime / 0.12), 0, 3))
			hintText.TextColor3 = Color3.fromRGB(200, 170, 255)
			aimTime += dt
			if aimTime > 0.35 and not revealSent[id] then
				revealSent[id] = true
				remotes.Reveal:FireServer(id)
			end
		end
	end
	catchBtn.Visible = inRange or holding
	if holding then
		if not inRange or not target or target:GetAttribute("SpiritId") ~= holdId then
			holding = false
			remotes.CatchStart:FireServer(nil)
			showToast("Дух вырвался!", 1)
		else
			local p = (os.clock() - holdStart) / holdTime
			fill.Size = UDim2.new(1, 0, math.min(p, 1), 0)
			catchBtn.Rotation = math.sin(os.clock() * 40) * 4 * p -- банка дрожит
			if p >= 1 then
				holding = false
				remotes.CatchFinish:FireServer(holdId)
			end
		end
	end
	if not holding then
		fill.Size = UDim2.new(1, 0, 0, 0)
		catchBtn.Rotation = 0
	end
end)

local function beginHold()
	local r = root()
	if not (r and target and target.Parent and target:GetAttribute("Revealed")) then return end
	holding, holdStart, holdId = true, os.clock(), target:GetAttribute("SpiritId")
	holdTime = target:GetAttribute("CatchTime") or 1.5
	remotes.CatchStart:FireServer(holdId)
end
local function endHold()
	if holding then
		holding = false
		remotes.CatchStart:FireServer(nil)
	end
end
catchBtn.MouseButton1Down:Connect(beginHold)
catchBtn.MouseButton1Up:Connect(endHold)
catchBtn.MouseLeave:Connect(endHold)
-- ПК/Studio: клавиша F
UserInputService.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.F then beginHold() end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.F then endHold() end
end)
