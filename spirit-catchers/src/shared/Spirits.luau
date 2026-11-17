-- Модели духов, собранные из примитивов (оригинальный дизайн).
local Spirits = {}

local function part(model, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		p[k] = v
	end
	p.Parent = model
	return p
end

-- Бумажный лис: острые «оригами»-грани, белая бумага с красными узорами, три хвоста.
function Spirits.buildPaperFox(): Model
	local m = Instance.new("Model")
	m.Name = "PaperFox"
	local paper = Color3.fromRGB(245, 240, 228)
	local ink = Color3.fromRGB(200, 40, 50)

	local body = part(m, { Name = "Body", Size = Vector3.new(1.4, 1.1, 2.2), Color = paper, Material = Enum.Material.SmoothPlastic })
	part(m, { Name = "Head", Shape = Enum.PartType.Block, Size = Vector3.new(1.1, 1, 1),
		CFrame = CFrame.new(0, 0.6, -1.4) * CFrame.Angles(0, math.rad(45), 0), Color = paper })
	part(m, { Name = "Snout", Size = Vector3.new(0.4, 0.4, 0.7), CFrame = CFrame.new(0, 0.45, -2.1), Color = paper })
	for _, x in { -0.35, 0.35 } do
		local ear = Instance.new("WedgePart")
		ear.Anchored, ear.CanCollide = true, false
		ear.Size = Vector3.new(0.15, 0.8, 0.5)
		ear.CFrame = CFrame.new(x, 1.4, -1.4)
		ear.Color = ink
		ear.Parent = m
	end
	for _, x in { -0.2, 0.2 } do
		part(m, { Name = "Eye", Size = Vector3.new(0.12, 0.12, 0.05), CFrame = CFrame.new(x, 0.75, -1.92),
			Color = Color3.fromRGB(255, 210, 90), Material = Enum.Material.Neon })
	end
	part(m, { Name = "Stripe", Size = Vector3.new(1.42, 0.12, 1.6), CFrame = CFrame.new(0, 0.5, 0), Color = ink })
	for i, a in { -30, 0, 30 } do
		part(m, { Name = "Tail" .. i, Size = Vector3.new(0.35, 0.35, 1.8),
			CFrame = CFrame.new(0, 0.3, 1.1) * CFrame.Angles(math.rad(35), math.rad(a), 0) * CFrame.new(0, 0, 0.9),
			Color = paper, Material = Enum.Material.Neon, Transparency = 0.15 })
	end
	m.PrimaryPart = body
	return m
end

-- Тень, которая бродит по улице до проявления.
function Spirits.buildShadow(): Part
	local s = Instance.new("Part")
	s.Name = "Shadow"
	s.Shape = Enum.PartType.Cylinder
	s.Size = Vector3.new(0.2, 4, 4)
	s.Anchored, s.CanCollide = true, false
	s.Color = Color3.new(0, 0, 0)
	s.Material = Enum.Material.SmoothPlastic
	s.Transparency = 0.35
	return s
end

return Spirits
