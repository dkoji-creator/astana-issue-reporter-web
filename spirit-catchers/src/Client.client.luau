-- Spirit Catchers prototype: client (lantern soft-aim, hold-to-catch button, altar UI, effects)
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UIS = game:GetService("UserInputService")
local Models = require(RS:WaitForChild("Models"))
local player = Players.LocalPlayer
local Reveal, Catch, Caught = RS:WaitForChild("Reveal"), RS:WaitForChild("Catch"), RS:WaitForChild("Caught")
local Save, Equip, State = RS:WaitForChild("Save"), RS:WaitForChild("Equip"), RS:WaitForChild("State")
local altar = RS:WaitForChild("AltarRef").Value
local spiritsFolder = workspace:WaitForChild("Spirits")
local state = { jar = {}, collection = {} }

---------------- UI ----------------
local gui = Instance.new("ScreenGui"); gui.Name = "SpiritUI"; gui.ResetOnSpawn = false; gui.Parent = player:WaitForChild("PlayerGui")
local function label(text, size, pos, anchor)
	local t = Instance.new("TextLabel"); t.Size = size; t.Position = pos; t.AnchorPoint = anchor or Vector2.zero
	t.BackgroundColor3 = Color3.fromRGB(15, 15, 35); t.BackgroundTransparency = 0.3; t.TextColor3 = Color3.new(1, 1, 1)
	t.Font = Enum.Font.GothamBold; t.TextScaled = true; t.Text = text; t.Parent = gui
	Instance.new("UICorner", t).CornerRadius = UDim.new(0, 12)
	return t
end
local jarLabel = label("Банка: 0", UDim2.fromOffset(170, 44), UDim2.new(0, 16, 0, 16))
local hint = label("Ищи движущиеся тени и свети на них фонарём", UDim2.new(0.6, 0, 0, 36), UDim2.new(0.5, 0, 0, 70), Vector2.new(0.5, 0))
local toast = label("", UDim2.new(0.5, 0, 0, 40), UDim2.new(0.5, 0, 0.3, 0), Vector2.new(0.5, 0)); toast.Visible = false

local catchBtn = Instance.new("TextButton"); catchBtn.Name = "Catch"
catchBtn.Size = UDim2.fromOffset(150, 150); catchBtn.AnchorPoint = Vector2.new(1, 1); catchBtn.Position = UDim2.new(1, -30, 1, -170)
catchBtn.BackgroundColor3 = Color3.fromRGB(90, 200, 255); catchBtn.Text = "ЛОВИТЬ"; catchBtn.Font = Enum.Font.GothamBlack
catchBtn.TextScaled = true; catchBtn.TextColor3 = Color3.fromRGB(10, 20, 40); catchBtn.AutoButtonColor = false; catchBtn.Parent = gui
Instance.new("UICorner", catchBtn).CornerRadius = UDim.new(1, 0)
local progress = Instance.new("Frame"); progress.Size = UDim2.new(0, 0, 0, 10); progress.Position = UDim2.new(0, 0, 1, 8)
progress.BackgroundColor3 = Color3.fromRGB(255, 240, 140); progress.Parent = catchBtn

local altarPanel = Instance.new("Frame"); altarPanel.Size = UDim2.fromOffset(260, 130); altarPanel.AnchorPoint = Vector2.new(0, 1)
altarPanel.Position = UDim2.new(0, 16, 1, -260); altarPanel.BackgroundTransparency = 1; altarPanel.Visible = false; altarPanel.Parent = gui
local function button(text, y, color)
	local b = Instance.new("TextButton"); b.Size = UDim2.new(1, 0, 0, 58); b.Position = UDim2.fromOffset(0, y)
	b.BackgroundColor3 = color; b.Text = text; b.Font = Enum.Font.GothamBold; b.TextScaled = true; b.TextColor3 = Color3.new(1, 1, 1); b.Parent = altarPanel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 14)
	return b
end
local saveBtn = button("Сохранить улов", 0, Color3.fromRGB(40, 150, 110))
local equipBtn = button("Экипировать лиса", 70, Color3.fromRGB(170, 70, 160))

local function flash(msg) toast.Text = msg; toast.Visible = true; task.delay(2.2, function() if toast.Text == msg then toast.Visible = false end end) end
State.OnClientEvent:Connect(function(s)
	state = s
	jarLabel.Text = "Банка: " .. #s.jar .. "   Коллекция: " .. (s.collection.fox or 0)
	equipBtn.Text = s.equipped == "fox" and "Убрать лиса" or "Экипировать лиса"
	equipBtn.Visible = (s.collection.fox or 0) > 0
	if s.stored == false then hint.Text = "DataStore недоступен (Studio: включи API Services)" end
end)

---------------- Lantern with soft aim ----------------
local lanternPart = Instance.new("Part"); lanternPart.Size = Vector3.new(0.4, 0.4, 0.4); lanternPart.Transparency = 1
lanternPart.Anchored = true; lanternPart.CanCollide = false; lanternPart.CanQuery = false; lanternPart.Parent = workspace
local spot = Instance.new("SpotLight"); spot.Angle = 40; spot.Range = 45; spot.Brightness = 4; spot.Color = Color3.fromRGB(255, 235, 180); spot.Parent = lanternPart
local aimDir = Vector3.new(0, 0, -1)
local target -- current spirit model in the beam

local function findTarget(root)
	local best, bestScore
	for _, m in ipairs(spiritsFolder:GetChildren()) do
		local sh = m:FindFirstChild("Shadow")
		if sh then
			local off = sh.Position - root.Position
			local flat = Vector3.new(off.X, 0, off.Z)
			local dist = flat.Magnitude
			if dist < 38 then
				local dot = dist > 0.1 and root.CFrame.LookVector:Dot(flat.Unit) or 1
				if dot > 0.55 then -- inside the forward cone
					local score = dist * (2 - dot)
					if not bestScore or score < bestScore then best, bestScore = m, score end
				end
			end
		end
	end
	return best
end

local lastReveal = 0
RunService.RenderStepped:Connect(function(dt)
	local char = player.Character; local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	target = findTarget(root)
	local desired = root.CFrame.LookVector - Vector3.new(0, 0.35, 0)
	if target then desired = (target.Shadow.Position + Vector3.new(0, 1.5, 0) - root.Position) end
	aimDir = aimDir:Lerp(desired.Unit, math.min(1, dt * 6)) -- soft aim
	local origin = root.Position + Vector3.new(0, 1.5, 0) + root.CFrame.LookVector
	lanternPart.CFrame = CFrame.lookAt(origin, origin + aimDir)
	if target and os.clock() - lastReveal > 0.5 then
		lastReveal = os.clock(); Reveal:FireServer(target:GetAttribute("Id"))
	end
	local nearAltar = (root.Position - altar.Position).Magnitude < 16
	altarPanel.Visible = nearAltar
	local canCatch = target and target:GetAttribute("Revealed") and (target.Shadow.Position - root.Position).Magnitude < 14
	catchBtn.BackgroundColor3 = canCatch and Color3.fromRGB(255, 220, 90) or Color3.fromRGB(90, 200, 255)
	if canCatch then hint.Text = "Удерживай ЛОВИТЬ" elseif target and target:GetAttribute("Revealed") then hint.Text = "Подойди ближе" end
end)

---------------- Hold to catch ----------------
local holding, holdStart, holdId = false, 0, nil
local function startHold()
	if not target then flash("Нет духа в луче"); return end
	holding, holdStart, holdId = true, os.clock(), target:GetAttribute("Id")
	Catch:FireServer(holdId)
end
local function stopHold()
	if holding then Catch:FireServer(nil) end
	holding = false; progress.Size = UDim2.new(0, 0, 0, 10)
end
catchBtn.MouseButton1Down:Connect(startHold)
catchBtn.MouseButton1Up:Connect(stopHold)
catchBtn.MouseLeave:Connect(stopHold)
UIS.InputBegan:Connect(function(i, gp) if not gp and i.KeyCode == Enum.KeyCode.E then startHold() end end)
UIS.InputEnded:Connect(function(i) if i.KeyCode == Enum.KeyCode.E then stopHold() end end)
RunService.Heartbeat:Connect(function()
	if holding then progress.Size = UDim2.new(math.clamp((os.clock() - holdStart) / 1.4, 0, 1), 0, 0, 10) end
end)

---------------- Effects ----------------
local function ring(pos, from, to, time, color)
	local r = Instance.new("Part"); r.Shape = Enum.PartType.Cylinder; r.Anchored = true; r.CanCollide = false; r.CanQuery = false
	r.Material = Enum.Material.Neon; r.Color = color; r.Size = Vector3.new(0.15, from, from)
	r.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)); r.Transparency = 0.2; r.Parent = workspace
	return r, TweenService:Create(r, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.15, to, to), Transparency = 1 })
end
-- normal catch: glowing ring contracts into the jar and fades
Caught.OnClientEvent:Connect(function(kind, pos)
	stopHold()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local r, tw = ring(pos, 9, 0.5, 0.6, Color3.fromRGB(150, 230, 255))
	if root then TweenService:Create(r, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = root.CFrame * CFrame.new(0.8, 0, -0.5) * CFrame.Angles(0, 0, math.rad(90)) }):Play() end
	tw:Play(); tw.Completed:Connect(function() r:Destroy() end)
	flash("Пойман: " .. Models.Names[kind] .. "!")
end)

saveBtn.MouseButton1Click:Connect(function()
	local res = Save:InvokeServer()
	if not res.ok then flash(res.msg); return end
	-- animation only after the server confirmed the save
	flash("Сохранено духов: " .. #res.saved .. (res.persisted and "" or " (без DataStore)"))
	local r, tw = ring(altar.Position, 2, 16, 0.8, Color3.fromRGB(120, 230, 255)); tw:Play(); tw.Completed:Connect(function() r:Destroy() end)
end)
equipBtn.MouseButton1Click:Connect(function()
	local ok = Equip:InvokeServer("fox")
	if not ok then flash("Сначала сохрани лиса") end
end)
