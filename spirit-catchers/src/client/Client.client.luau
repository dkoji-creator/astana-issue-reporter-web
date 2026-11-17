-- Клиент: фонарь с мягким наведением, крупная кнопка ловли, HUD, эффекты.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local plr = Players.LocalPlayer
local remotes = ReplicatedStorage:WaitForChild("Remotes")
local spiritsFolder = workspace:WaitForChild("Spirits")

local AIM_RANGE, AIM_CONE = 30, math.cos(math.rad(40))
local CATCH_RANGE, CATCH_TIME = 13, 1.5

------------------------------------------------------------------ UI
local gui = Instance.new("ScreenGui")
gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset = "SpiritHUD", false, true
gui.Parent = plr:WaitForChild("PlayerGui")

local function label(text, pos, size)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency, l.TextColor3, l.Font, l.TextScaled = 0.4, Color3.new(1, 1, 1), Enum.Font.GothamBold, true
	l.BackgroundColor3 = Color3.fromRGB(20, 20, 40)
	l.Text, l.Position, l.Size = text, pos, size
	Instance.new("UICorner").Parent = l
	l.Parent = gui
	return l
end
local jarLabel = label("Банка: 0", UDim2.new(0, 16, 0, 60), UDim2.new(0, 170, 0, 40))
local savedLabel = label("Коллекция: 0", UDim2.new(0, 16, 0, 106), UDim2.new(0, 170, 0, 34))
local toast = label("", UDim2.new(0.5, -170, 0, 60), UDim2.new(0, 340, 0, 44))
toast.Visible = false

local catchBtn = Instance.new("TextButton")
catchBtn.Name = "Catch"
catchBtn.Size, catchBtn.Position = UDim2.new(0, 150, 0, 150), UDim2.new(1, -180, 1, -330)
catchBtn.Text, catchBtn.TextScaled, catchBtn.Font = "ЛОВИТЬ", true, Enum.Font.GothamBlack
catchBtn.BackgroundColor3, catchBtn.TextColor3 = Color3.fromRGB(90, 160, 255), Color3.new(1, 1, 1)
catchBtn.AutoButtonColor = false
local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(1, 0)
corner.Parent = catchBtn
catchBtn.Parent = gui
local fill = Instance.new("Frame")
fill.BackgroundColor3, fill.BackgroundTransparency = Color3.new(1, 1, 1), 0.5
fill.Size, fill.AnchorPoint, fill.Position = UDim2.new(1, 0, 0, 0), Vector2.new(0, 1), UDim2.new(0, 0, 1, 0)
local fc = Instance.new("UICorner")
fc.CornerRadius = UDim.new(1, 0)
fc.Parent = fill
fill.Parent = catchBtn

local equipBtn = Instance.new("TextButton")
equipBtn.Size, equipBtn.Position = UDim2.new(0, 170, 0, 50), UDim2.new(0, 16, 0, 146)
equipBtn.TextScaled, equipBtn.Font = true, Enum.Font.GothamBold
equipBtn.BackgroundColor3, equipBtn.TextColor3 = Color3.fromRGB(200, 60, 70), Color3.new(1, 1, 1)
equipBtn.Visible = false
Instance.new("UICorner").Parent = equipBtn
equipBtn.Parent = gui

local function showToast(text, secs)
	toast.Text, toast.Visible = text, true
	task.delay(secs or 2, function()
		if toast.Text == text then toast.Visible = false end
	end)
end

------------------------------------------------------------------ состояние
local state = { jar = 0, saved = {}, equipped = nil }

local function ringEffect(fromPos, toPos, color)
	local ring = Instance.new("Part")
	ring.Shape, ring.Anchored, ring.CanCollide, ring.CastShadow = Enum.PartType.Cylinder, true, false, false
	ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, color, 0.2
	ring.Size = Vector3.new(0.15, 7, 7)
	ring.CFrame = CFrame.new(fromPos) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = workspace
	local tw = TweenService:Create(ring, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.new(0.1, 0.6, 0.6), CFrame = CFrame.new(toPos) * CFrame.Angles(0, 0, math.rad(90)) })
	tw:Play()
	tw.Completed:Wait()
	TweenService:Create(ring, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	task.delay(0.3, function() ring:Destroy() end)
end

remotes.State.OnClientEvent:Connect(function(s)
	if s.saveResult then
		local r = s.saveResult
		if r.ok then
			showToast(("Сохранено духов: %d"):format(r.count) .. (r.persisted and "" or " (без DataStore)"))
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root then task.spawn(ringEffect, root.Position + Vector3.new(0, 4, 0), root.Position, Color3.fromRGB(120, 200, 255)) end
		else
			showToast(r.msg)
		end
		return
	end
	state = s
	jarLabel.Text = "Банка: " .. s.jar
	local total = 0
	for _, n in s.saved do total += n end
	savedLabel.Text = "Коллекция: " .. total
	equipBtn.Visible = (s.saved.PaperFox or 0) > 0
	equipBtn.Text = s.equipped == "PaperFox" and "Убрать лиса" or "Экипировать лиса"
end)

equipBtn.Activated:Connect(function()
	remotes.Equip:InvokeServer(state.equipped == "PaperFox" and nil or "PaperFox")
end)

remotes.Caught.OnClientEvent:Connect(function(kind, at)
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if root then
		showToast("Бумажный лис в банке!")
		ringEffect(at + Vector3.new(0, 1.5, 0), root.Position + Vector3.new(0, 0.5, 0), Color3.fromRGB(255, 220, 160))
	end
end)

------------------------------------------------------------------ фонарь и наведение
local beamLight, beamPart
local function setupLight(char)
	local root = char:WaitForChild("HumanoidRootPart")
	beamPart = Instance.new("Part")
	beamPart.Size, beamPart.Transparency, beamPart.CanCollide, beamPart.Massless = Vector3.new(0.2, 0.2, 0.2), 1, false, true
	beamPart.Parent = char
	local w = Instance.new("Weld")
	w.Part0, w.Part1, w.C0 = root, beamPart, CFrame.new(0.8, 0.8, -0.8)
	w.Parent = beamPart
	beamLight = Instance.new("SpotLight")
	beamLight.Range, beamLight.Angle, beamLight.Brightness = AIM_RANGE, 35, 4
	beamLight.Color = Color3.fromRGB(255, 240, 200)
	beamLight.Parent = beamPart
end
plr.CharacterAdded:Connect(setupLight)
if plr.Character then task.spawn(setupLight, plr.Character) end

local highlight = Instance.new("Highlight")
highlight.FillTransparency, highlight.OutlineColor = 0.6, Color3.fromRGB(255, 230, 150)
highlight.Parent = gui

local target: BasePart? = nil
local aimTime, revealSent = 0, {}

local function findTarget(root)
	local best, bestScore = nil, -1
	local look = root.CFrame.LookVector
	for _, s in spiritsFolder:GetChildren() do
		if s:IsA("BasePart") and s.Name == "Shadow" then
			local d = s.Position - root.Position
			local dist = d.Magnitude
			if dist < AIM_RANGE then
				local dot = Vector3.new(d.X, 0, d.Z).Unit:Dot(Vector3.new(look.X, 0, look.Z).Unit)
				if dot > AIM_CONE then
					local score = dot * 2 - dist / AIM_RANGE
					if score > bestScore then best, bestScore = s, score end
				end
			end
		end
	end
	return best
end

local holding, holdStart, holdId = false, 0, nil

RunService.RenderStepped:Connect(function(dt)
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local t = findTarget(root)
	if t ~= target then target, aimTime = t, 0 end
	-- мягкое наведение: луч плавно поворачивается к ближайшему духу перед игроком
	if beamPart and beamPart:FindFirstChild("Weld") then
		local w = beamPart.Weld
		local goal = CFrame.new(0.8, 0.8, -0.8)
		if target then
			local localDir = root.CFrame:VectorToObjectSpace((target.Position - root.Position).Unit)
			goal = CFrame.lookAt(goal.Position, goal.Position + localDir)
		end
		w.C0 = w.C0:Lerp(goal, math.min(1, dt * 6))
	end
	highlight.Adornee = nil
	if target then
		local id = target:GetAttribute("SpiritId")
		local revealed = target:GetAttribute("Revealed")
		if revealed then
			for _, m in spiritsFolder:GetChildren() do
				if m:IsA("Model") and m:GetAttribute("SpiritId") == id then highlight.Adornee = m end
			end
		else
			highlight.Adornee = target
			aimTime += dt
			if aimTime > 0.35 and not revealSent[id] then
				revealSent[id] = true
				remotes.Reveal:FireServer(id)
			end
		end
	end
	-- состояние кнопки
	local inRange = target and target:GetAttribute("Revealed") and (target.Position - root.Position).Magnitude < CATCH_RANGE
	catchBtn.BackgroundColor3 = inRange and Color3.fromRGB(90, 220, 140) or Color3.fromRGB(90, 120, 170)
	if holding then
		if not inRange or target:GetAttribute("SpiritId") ~= holdId then
			holding = false
			remotes.CatchStart:FireServer(nil)
		else
			local p = (os.clock() - holdStart) / CATCH_TIME
			fill.Size = UDim2.new(1, 0, math.min(p, 1), 0)
			if p >= 1 then
				holding = false
				remotes.CatchFinish:FireServer(holdId)
			end
		end
	end
	if not holding then fill.Size = UDim2.new(1, 0, 0, 0) end
end)

local function beginHold()
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
	if not (root and target and target:GetAttribute("Revealed")) then
		showToast("Сначала посвети на тень фонарём", 1.2)
		return
	end
	if (target.Position - root.Position).Magnitude > CATCH_RANGE then
		showToast("Подойди ближе", 1)
		return
	end
	holding, holdStart, holdId = true, os.clock(), target:GetAttribute("SpiritId")
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
-- на ПК в Studio: клавиша F
UserInputService.InputBegan:Connect(function(i, gp)
	if not gp and i.KeyCode == Enum.KeyCode.F then beginHold() end
end)
UserInputService.InputEnded:Connect(function(i)
	if i.KeyCode == Enum.KeyCode.F then endHold() end
end)
