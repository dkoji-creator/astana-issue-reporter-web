-- Падающие звёзды: часто падают с неба в случайных местах планет, где есть игроки.
-- В полёте ярко светятся (анимация на клиенте), после падения постепенно тускнеют и исчезают.
-- Подобрать можно только упавшую звезду (касание). Награду выдаёт Main через onCollect.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local G = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Game"))

local Stars = {}
local V3, CF = Vector3.new, CFrame.new

local function now() return workspace:GetServerTimeNow() end

local function newStar(folder, pos, meteor)
	local m = Instance.new("Model")
	m.Name = meteor and "Meteor" or "Star"
	local col = meteor and Color3.fromRGB(255, 170, 90) or Color3.fromRGB(255, 236, 170)
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = meteor and V3(2.4, 2.4, 2.4) or V3(1.4, 1.4, 1.4)
	core.CFrame = CF(pos)
	core.Material = Enum.Material.Neon
	core.Color = col
	core.Anchored, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, false, false, false, false
	core.Parent = m
	local hit = Instance.new("Part")
	hit.Name = "Hit"
	hit.Size = V3(6, 7, 6)
	hit.CFrame = CF(pos)
	hit.Transparency = 1
	hit.Anchored, hit.CanCollide, hit.CanQuery, hit.CastShadow = true, false, false, false
	hit.CanTouch = true
	hit.Parent = m
	local l = Instance.new("PointLight")
	l.Name = "Glow"
	l.Color, l.Range, l.Brightness = col, meteor and 22 or 14, 1.6
	l.Parent = core
	m.PrimaryPart = core
	m:SetAttribute("Star", true)
	m:SetAttribute("Meteor", meteor == true)
	m:SetAttribute("LandAt", now() + G.Stars.fall)
	m:SetAttribute("Angle", math.random() * math.pi * 2)
	m.Parent = folder
	return m, hit
end

-- ctx: { parent, pickSpot() -> Vector3?, isMeteorEvent(), onCollect(plr, meteor, pos) }
function Stars.start(ctx)
	local folder = Instance.new("Folder")
	folder.Name = "Stars"
	folder.Parent = ctx.parent
	local active = {}

	local function spawnOne()
		local pos = ctx.pickSpot()
		if not pos then return end
		local meteor = math.random() < G.Stars.meteorChance * (ctx.isMeteorEvent() and 3 or 1)
		local m, hit = newStar(folder, pos + V3(0, 1.6, 0), meteor)
		local landAt = m:GetAttribute("LandAt")
		active[m] = landAt + G.Stars.glow
		local taken = false
		hit.Touched:Connect(function(part)
			if taken or now() < landAt - 0.3 then return end
			local plr = Players:GetPlayerFromCharacter(part.Parent)
			if not plr then return end
			taken = true
			active[m] = nil
			ctx.onCollect(plr, meteor, pos)
			m:Destroy()
		end)
	end

	task.spawn(function()
		while true do
			task.wait(G.Stars.every * (ctx.isMeteorEvent() and 0.35 or 1))
			local t = now()
			local n = 0
			for m, dieAt in active do
				if not m.Parent or t > dieAt then
					active[m] = nil
					if m.Parent then m:Destroy() end
				else
					n += 1
				end
			end
			if n < G.Stars.max then spawnOne() end
		end
	end)
	return folder
end

return Stars
