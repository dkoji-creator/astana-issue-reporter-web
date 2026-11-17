-- Модели духов и они из примитивов (оригинальный дизайн) + процедурная анимация.
-- Каждая деталь хранит атрибут Base (CFrame относительно опоры модели).
-- Подвижные детали: Joint (точка вращения), Anim (тип), Phase, Amp.
local S = {}

local function mk(m, props, cls)
	local p = Instance.new(cls or "Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		p[k] = v
	end
	p:SetAttribute("Base", p.CFrame)
	p.Parent = m
	return p
end

local function ellipsoid(p)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = p
	return p
end

local function joint(p, at: Vector3, anim: string, phase: number?, amp: number?)
	p:SetAttribute("Joint", CFrame.new(at))
	p:SetAttribute("Anim", anim)
	p:SetAttribute("Phase", phase or 0)
	p:SetAttribute("Amp", amp or 1)
end

function S.scale(m: Model, k: number)
	for _, p in m:GetDescendants() do
		if p:IsA("BasePart") then
			p.Size *= k
			local b = p:GetAttribute("Base")
			p:SetAttribute("Base", CFrame.new(b.Position * k) * b.Rotation)
			local j = p:GetAttribute("Joint")
			if j then p:SetAttribute("Joint", CFrame.new(j.Position * k)) end
			p.CFrame = p:GetAttribute("Base")
		elseif p:IsA("Attachment") then
			p.Position *= k
		end
	end
	m:SetAttribute("Scale", (m:GetAttribute("Scale") or 1) * k)
end

local sin = math.sin
function S.animate(m: Model, pivot: CFrame, t: number, speed: number?)
	speed = speed or 1
	for _, p in m:GetChildren() do
		local base = p:IsA("BasePart") and p:GetAttribute("Base")
		if base then
			local anim = p:GetAttribute("Anim")
			local cf = base
			if anim then
				local a = sin(t * speed + p:GetAttribute("Phase")) * p:GetAttribute("Amp")
				local rot
				if anim == "wagY" then
					rot = CFrame.Angles(0, a * 0.45, 0)
				elseif anim == "flapZ" then
					rot = CFrame.Angles(0, 0, a * 0.5)
				elseif anim == "swingX" then
					rot = CFrame.Angles(a * 0.6, 0, 0)
				else -- "twitch"
					rot = CFrame.Angles(a * 0.2, 0, a * 0.1)
				end
				local j = p:GetAttribute("Joint")
				cf = j * rot * j:Inverse() * base
			end
			p.CFrame = pivot * cf
		end
	end
end

------------------------------------------------------------------ бумажный лис
-- Опора — у лап. Длина ~8 стадов после масштаба: видно издалека.
function S.buildPaperFox(): Model
	local m = Instance.new("Model")
	m.Name = "PaperFox"
	local paper = Color3.fromRGB(250, 244, 230)
	local ink = Color3.fromRGB(215, 45, 55)

	local body = mk(m, { Name = "Body", Size = Vector3.new(1.5, 1.3, 2.6), CFrame = CFrame.new(0, 1.5, 0), Color = paper })
	mk(m, { Name = "Stripe", Size = Vector3.new(1.55, 0.2, 1.8), CFrame = CFrame.new(0, 2.1, 0), Color = ink })
	mk(m, { Name = "Chest", Size = Vector3.new(1.2, 1.1, 0.6), CFrame = CFrame.new(0, 1.5, -1.3) * CFrame.Angles(math.rad(20), 0, 0), Color = paper })
	-- голова-ромб «оригами»
	mk(m, { Name = "Head", Size = Vector3.new(1.3, 1.2, 1.3), CFrame = CFrame.new(0, 2.5, -1.7) * CFrame.Angles(0, math.rad(45), 0), Color = paper })
	local snout = mk(m, { Name = "Snout", Size = Vector3.new(0.7, 0.6, 1.1), CFrame = CFrame.new(0, 2.25, -2.6) * CFrame.Angles(0, math.rad(180), 0), Color = paper }, "WedgePart")
	snout.Size = Vector3.new(0.7, 0.6, 1.1)
	mk(m, { Name = "Nose", Size = Vector3.new(0.25, 0.2, 0.2), CFrame = CFrame.new(0, 2.4, -3.1), Color = Color3.fromRGB(30, 20, 30) })
	for i, x in { -0.3, 0.3 } do
		mk(m, { Name = "Eye", Size = Vector3.new(0.18, 0.22, 0.08), CFrame = CFrame.new(x, 2.75, -2.3), Color = Color3.fromRGB(255, 200, 70), Material = Enum.Material.Neon })
		-- большие уши: белые с красными кончиками
		local ear = mk(m, { Name = "Ear", Size = Vector3.new(0.2, 1.3, 0.9), CFrame = CFrame.new(x * 1.6, 3.6, -1.6), Color = paper }, "WedgePart")
		joint(ear, Vector3.new(x * 1.6, 3, -1.6), "twitch", i * 1.3, 1)
		local tip = mk(m, { Name = "EarTip", Size = Vector3.new(0.22, 0.5, 0.36), CFrame = CFrame.new(x * 1.6, 4.05, -1.43), Color = ink }, "WedgePart")
		joint(tip, Vector3.new(x * 1.6, 3, -1.6), "twitch", i * 1.3, 1)
	end
	-- лапы: шаг
	for i, pos in { Vector3.new(-0.5, 0.5, -0.9), Vector3.new(0.5, 0.5, -0.9), Vector3.new(-0.5, 0.5, 0.9), Vector3.new(0.5, 0.5, 0.9) } do
		local leg = mk(m, { Name = "Leg", Size = Vector3.new(0.35, 1.1, 0.35), CFrame = CFrame.new(pos), Color = paper })
		joint(leg, pos + Vector3.new(0, 0.5, 0), "swingX", (i == 1 or i == 4) and 0 or math.pi, 1)
	end
	-- пушистый хвост из трёх сегментов, светящийся кончик
	local tailRoot = Vector3.new(0, 1.9, 1.3)
	local segs = {
		{ Vector3.new(0.6, 0.6, 1.2), CFrame.new(0, 2.2, 1.9) * CFrame.Angles(math.rad(35), 0, 0), paper, Enum.Material.SmoothPlastic },
		{ Vector3.new(0.9, 0.9, 1.4), CFrame.new(0, 2.9, 2.7) * CFrame.Angles(math.rad(50), 0, 0), paper, Enum.Material.SmoothPlastic },
		{ Vector3.new(0.7, 0.7, 0.9), CFrame.new(0, 3.6, 3.3) * CFrame.Angles(math.rad(65), 0, 0), Color3.fromRGB(255, 120, 110), Enum.Material.Neon },
	}
	for i, s in segs do
		local p = mk(m, { Name = "Tail" .. i, Size = s[1], CFrame = s[2], Color = s[3], Material = s[4] })
		joint(p, tailRoot, "wagY", -i * 0.4, 1)
	end
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(255, 210, 180), 12, 1.5
	glow.Parent = body
	m.PrimaryPart = body
	S.scale(m, 1.6)
	return m
end

------------------------------------------------------------------ золотой карп
-- Длина ~16 стадов, прозрачные длинные плавники, светящийся след.
function S.buildGoldenCarp(): Model
	local m = Instance.new("Model")
	m.Name = "GoldenCarp"
	local gold = Color3.fromRGB(255, 190, 60)
	local deep = Color3.fromRGB(230, 120, 30)
	local fin = Color3.fromRGB(255, 235, 170)

	local segs = {
		{ Vector3.new(2.6, 2.8, 3.2), -3.6, gold },
		{ Vector3.new(3.0, 3.2, 3.4), -1.4, gold },
		{ Vector3.new(2.6, 2.8, 3.0), 0.9, deep },
		{ Vector3.new(1.9, 2.0, 2.6), 2.9, gold },
		{ Vector3.new(1.2, 1.3, 2.0), 4.6, deep },
	}
	local head
	for i, s in segs do
		local p = ellipsoid(mk(m, { Name = "Seg" .. i, Size = s[1], CFrame = CFrame.new(0, 0, s[2]), Color = s[3], Material = Enum.Material.Metal, Reflectance = 0.25 }))
		joint(p, Vector3.new(0, 0, s[2] - 1.2), "wagY", -i * 0.7, 0.12 * i)
		if i == 1 then head = p end
	end
	for _, x in { -0.9, 0.9 } do
		mk(m, { Name = "Eye", Size = Vector3.new(0.3, 0.35, 0.35), CFrame = CFrame.new(x, 0.5, -4.6), Color = Color3.fromRGB(20, 20, 30), Material = Enum.Material.Neon })
		local wh = mk(m, { Name = "Whisker", Size = Vector3.new(0.12, 0.12, 2.8), CFrame = CFrame.new(x * 0.8, -0.6, -5.8) * CFrame.Angles(0, math.rad(x * 25), 0),
			Color = fin, Material = Enum.Material.Neon })
		joint(wh, Vector3.new(x * 0.8, -0.6, -4.6), "wagY", x, 0.6)
		-- длинные грудные плавники
		local pf = mk(m, { Name = "Fin", Size = Vector3.new(0.1, 1.6, 4.2), CFrame = CFrame.new(x * 2.6, -0.7, -0.8) * CFrame.Angles(0, 0, math.rad(x * -60)),
			Color = fin, Material = Enum.Material.Neon, Transparency = 0.55 })
		joint(pf, Vector3.new(x * 1.3, -0.5, -0.8), "flapZ", x > 0 and 0 or math.pi, 0.7)
		local vf = mk(m, { Name = "Fin", Size = Vector3.new(0.1, 1.2, 3), CFrame = CFrame.new(x * 1.6, -1.6, 2.2) * CFrame.Angles(0, 0, math.rad(x * -35)),
			Color = fin, Material = Enum.Material.Neon, Transparency = 0.6 })
		joint(vf, Vector3.new(x * 0.8, -1, 2.2), "flapZ", x > 0 and 1 or 1 + math.pi, 0.5)
	end
	local dorsal = mk(m, { Name = "Fin", Size = Vector3.new(0.1, 2.4, 6), CFrame = CFrame.new(0, 2.3, 0.6), Color = fin, Material = Enum.Material.Neon, Transparency = 0.5 })
	joint(dorsal, Vector3.new(0, 1.4, 0.6), "wagY", -1, 0.15)
	-- большой вуалевый хвост
	for i, a in { -28, 28 } do
		local tf = mk(m, { Name = "Fin", Size = Vector3.new(0.1, 3.4, 5.2), CFrame = CFrame.new(0, a / 28 * 1.3, 7.6) * CFrame.Angles(math.rad(a), 0, 0),
			Color = fin, Material = Enum.Material.Neon, Transparency = 0.45 })
		joint(tf, Vector3.new(0, 0, 5.4), "wagY", -4 - i * 0.2, 0.9)
	end
	-- светящийся след
	local tailSeg = m:FindFirstChild("Seg5")
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.6, 0)
	a0.Parent = tailSeg
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.6, 0)
	a1.Parent = tailSeg
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Lifetime, trail.LightEmission = 1.2, 1
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 150, 40))
	trail.Transparency = NumberSequence.new(0.1, 1)
	trail.WidthScale = NumberSequence.new(1, 0.2)
	trail.Parent = tailSeg
	local glow = Instance.new("PointLight")
	glow.Color, glow.Range, glow.Brightness = Color3.fromRGB(255, 200, 100), 22, 2.5
	glow.Parent = head
	m.PrimaryPart = head
	S.scale(m, 1.25)
	return m
end

------------------------------------------------------------------ они
function S.buildOni(): Model
	local m = Instance.new("Model")
	m.Name = "Oni"
	local skin = Color3.fromRGB(170, 30, 40)
	local body = mk(m, { Name = "Body", Size = Vector3.new(6, 6, 3.5), CFrame = CFrame.new(0, 9, 0), Color = skin })
	mk(m, { Name = "Belt", Size = Vector3.new(6.2, 1.2, 3.7), CFrame = CFrame.new(0, 6.6, 0), Color = Color3.fromRGB(40, 30, 30) })
	mk(m, { Name = "Head", Size = Vector3.new(4, 3.6, 3.4), CFrame = CFrame.new(0, 14, -0.3), Color = skin })
	for _, x in { -1, 1 } do
		mk(m, { Name = "Horn", Size = Vector3.new(0.7, 2.2, 0.8), CFrame = CFrame.new(x * 1.4, 16.8, -0.3) * CFrame.Angles(0, 0, math.rad(-x * 15)), Color = Color3.fromRGB(240, 220, 150) }, "WedgePart")
		mk(m, { Name = "Eye", Size = Vector3.new(0.9, 0.5, 0.2), CFrame = CFrame.new(x * 0.9, 14.6, -2), Color = Color3.fromRGB(255, 240, 80), Material = Enum.Material.Neon })
		local leg = mk(m, { Name = "Leg", Size = Vector3.new(2, 6, 2), CFrame = CFrame.new(x * 1.6, 3, 0), Color = skin })
		joint(leg, Vector3.new(x * 1.6, 6, 0), "swingX", x > 0 and 0 or math.pi, 0.6)
		local arm = mk(m, { Name = "Arm", Size = Vector3.new(1.6, 5.5, 1.6), CFrame = CFrame.new(x * 3.9, 9, 0), Color = skin })
		joint(arm, Vector3.new(x * 3.9, 11.5, 0), "swingX", x > 0 and math.pi or 0, 0.5)
	end
	mk(m, { Name = "Mouth", Size = Vector3.new(2.4, 0.5, 0.2), CFrame = CFrame.new(0, 13, -2), Color = Color3.fromRGB(255, 255, 255) })
	local club = mk(m, { Name = "Club", Size = Vector3.new(1.4, 7, 1.4), CFrame = CFrame.new(3.9, 8, -2.5) * CFrame.Angles(math.rad(60), 0, 0), Color = Color3.fromRGB(70, 50, 40), Material = Enum.Material.Wood })
	joint(club, Vector3.new(3.9, 11.5, 0), "swingX", math.pi, 0.5)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness = Color3.fromRGB(255, 60, 40), 18, 2
	l.Parent = body
	m.PrimaryPart = body
	return m
end

------------------------------------------------------------------ тень
function S.buildShadow(): Part
	local s = Instance.new("Part")
	s.Name = "Shadow"
	s.Shape = Enum.PartType.Cylinder
	s.Size = Vector3.new(0.2, 7, 7)
	s.Anchored, s.CanCollide, s.CanTouch = true, false, false
	s.Color = Color3.fromRGB(20, 0, 40)
	s.Material = Enum.Material.Neon
	s.Transparency = 0.25
	local pe = Instance.new("ParticleEmitter")
	pe.Color = ColorSequence.new(Color3.fromRGB(150, 90, 255), Color3.fromRGB(40, 0, 80))
	pe.LightEmission, pe.Rate, pe.Lifetime = 0.6, 14, NumberRange.new(1, 1.6)
	pe.Speed, pe.SpreadAngle = NumberRange.new(2, 4), Vector2.new(25, 25)
	pe.Size = NumberSequence.new(1.2, 0)
	pe.Transparency = NumberSequence.new(0.3, 1)
	pe.EmissionDirection = Enum.NormalId.Right -- цилиндр лежит на боку: «вверх»
	pe.Parent = s
	return s
end

S.Names = { PaperFox = "Бумажный лис", GoldenCarp = "Золотой карп" }
S.Builders = { PaperFox = S.buildPaperFox, GoldenCarp = S.buildGoldenCarp }

return S
