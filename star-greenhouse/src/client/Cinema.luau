-- Ролик сверхредкой находки: режиссёрская сцена из нескольких планов со склейками, как смонтированное видео.
-- 1) призыв: под персонажем магический круг; 2) рождение травы — у каждой планеты своё (лунный луч, песчаный смерч,
-- ледяные шипы, фонтан лавы, портал-галактика, падающая звезда), у каждой формы своё движение; 3) взрыв в замедленной
-- съёмке с эффектом мутации; 4) герой и трофей в одном кадре, персонаж радуется; 5) облёт камерой.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Cinema = {}

local C3 = Color3.fromRGB
local V3, CF, ANG = Vector3.new, CFrame.new, CFrame.Angles
local NEON = Enum.Material.Neon

local THEME = {
	moon = { col = C3(170, 200, 255), light = C3(235, 242, 255), name = "Луна" },
	mars = { col = C3(255, 120, 60), light = C3(255, 205, 150), name = "Марс" },
	europa = { col = C3(120, 210, 255), light = C3(225, 245, 255), name = "Европа" },
	io = { col = C3(255, 90, 30), light = C3(255, 190, 110), name = "Ио" },
	nebula = { col = C3(190, 110, 255), light = C3(150, 255, 230), name = "Туманность" },
	core = { col = C3(255, 200, 90), light = C3(255, 245, 200), name = "Звёздное ядро" },
}
-- как форма растения появляется на свет
local MOTION = {
	flower = "grow", tulip = "grow", tree = "grow", vine = "grow", grass = "grow", coral = "grow", sprout = "grow",
	mushroom = "pop", gourd = "pop", bulb = "pop", pod = "pop", heart = "pop", cactus = "pop",
	jelly = "float", comet = "float", star = "float", spiral = "float", orb = "float", seedcore = "float",
	crystal = "spin", geode = "spin", crown = "spin",
}
local RAINBOW = { C3(255, 90, 120), C3(255, 170, 70), C3(255, 235, 90), C3(110, 255, 150), C3(100, 180, 255), C3(200, 120, 255) }

local function ease(q) return q * q * (3 - 2 * q) end
local function backOut(q)
	local c1, c3 = 1.70158, 2.70158
	return 1 + c3 * (q - 1) ^ 3 + c1 * (q - 1) ^ 2
end

------------------------------------------------------------------ сцена: виртуальное время (замедление), события и обновления
local function newScene(ctx)
	local S = { t = 0, speed = 1, events = {}, ups = {}, done = false }
	S.folder = Instance.new("Folder")
	S.folder.Name = "CinemaScene"
	S.folder.Parent = workspace
	function S.at(t, fn)
		table.insert(S.events, { t = t, fn = fn })
		table.sort(S.events, function(a, b) return a.t < b.t end)
	end
	function S.run(fn) table.insert(S.ups, fn) end
	-- fn(q) для q от 0 до 1 на отрезке виртуального времени
	function S.anim(t0, dur, fn)
		S.at(t0, function()
			local start = S.t
			fn(0)
			S.run(function(t)
				local q = math.clamp((t - start) / dur, 0, 1)
				fn(q)
				return q >= 1
			end)
		end)
	end
	function S.part(props)
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = NEON
		for k, v in props do p[k] = v end
		p.Parent = S.folder
		return p
	end
	function S.fx(shape, scale, color, mat, tr)
		local p = ctx.Fx3D.part(shape, scale, color, mat, tr)
		if p then p.Parent = S.folder end
		return p
	end
	function S.emitter(pos, props, size)
		local holder = S.part({ Transparency = 1, Size = size or V3(0.2, 0.2, 0.2), CFrame = CF(pos) })
		local e = Instance.new("ParticleEmitter")
		e.LightInfluence = 0
		for k, v in props do e[k] = v end
		e.Parent = holder
		return e, holder
	end
	-- ударная волна по земле
	function S.shock(t0, pos, color, maxR, dur, tr0)
		S.at(t0, function()
			local s = S.fx("Shock", 1, color, NEON, tr0 or 0.05)
			if not s then return end
			s.CFrame = CF(pos)
			local start = S.t
			S.run(function(t)
				local q = math.clamp((t - start) / dur, 0, 1)
				local r = 0.5 + maxR * (1 - (1 - q) ^ 3)
				s.Size = ctx.Fx3D.Box.Shock * V3(r, 1, r)
				s.Transparency = (tr0 or 0.05) + (1 - (tr0 or 0.05)) * q
				if q >= 1 then s:Destroy() return true end
			end)
		end)
	end
	-- молния: ломаная из тонких неоновых отрезков
	function S.bolt(from, to, color)
		local pts = { from }
		local n = 7
		for i = 1, n - 1 do
			local q = i / n
			table.insert(pts, from:Lerp(to, q) + V3(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3.5)
		end
		table.insert(pts, to)
		local segs = {}
		for i = 1, #pts - 1 do
			local a, b = pts[i], pts[i + 1]
			table.insert(segs, S.part({ Color = color, Size = V3(0.18, 0.18, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b) }))
		end
		task.delay(0.22, function()
			for _, s in segs do s:Destroy() end
		end)
	end
	function S.step(dt)
		local vdt = dt * S.speed
		S.t += vdt
		while S.events[1] and S.events[1].t <= S.t do
			local e = table.remove(S.events, 1)
			local ok, err = pcall(e.fn)
			if not ok then warn("cinema event", err) end
		end
		for i = #S.ups, 1, -1 do
			local ok, res = pcall(S.ups[i], S.t, vdt)
			if not ok then
				warn("cinema update", res)
				table.remove(S.ups, i)
			elseif res then
				table.remove(S.ups, i)
			end
		end
	end
	return S
end

------------------------------------------------------------------ магический круг под персонажем
local function magicCircle(S, ctx, feet, th)
	local base = CF(feet + V3(0, 0.15, 0))
	local r1 = S.fx("RingBold", 3.0, th.col, NEON, 0.15)
	local r2 = S.fx("Ring", 4.1, th.light, NEON, 0.25)
	local cr = S.fx("Crown", V3(2.5, 0.35, 2.5), th.light, NEON, 0.2)
	local stars = {}
	for j = 1, 6 do
		local st = S.fx("Star", 0.42, j % 2 == 0 and th.col or th.light, NEON, 0.05)
		if st then table.insert(stars, st) end
	end
	local pillar = S.part({ Shape = Enum.PartType.Cylinder, Color = th.light, Transparency = 1, Size = V3(16, 3.6, 3.6), CFrame = base * CF(0, 8, 0) * ANG(0, 0, math.pi / 2) })
	local rise = S.emitter(feet + V3(0, 0.3, 0), { Texture = ctx.TEX.sparkle or "rbxasset://textures/particles/sparkles_main.dds", Color = ColorSequence.new(th.light, th.col),
		LightEmission = 1, Rate = 40, Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(3, 6), EmissionDirection = Enum.NormalId.Top,
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Size = NumberSequence.new(0.35, 0), Transparency = NumberSequence.new(0, 1) }, V3(6, 0.2, 6))
	local appear = S.t
	S.run(function(t)
		if S.done then return true end
		local q = math.clamp((t - appear) / 0.6, 0, 1)
		local k = backOut(q)
		if r1 then r1.Size = ctx.Fx3D.Box.RingBold * 3.0 * math.max(0.05, k) r1.CFrame = base * ANG(0, t * 1.2, 0) end
		if r2 then r2.Size = ctx.Fx3D.Box.Ring * 4.1 * math.max(0.05, k) r2.CFrame = base * ANG(0, -t * 0.8, 0) end
		if cr then cr.CFrame = base * CF(0, 0.05, 0) * ANG(0, t * 2, 0) end
		for j, st in stars do
			local a = t * 1.2 + j * math.pi / 3
			st.CFrame = base * CF(math.cos(a) * 3.55 * k, 0.1, math.sin(a) * 3.55 * k) * ANG(math.pi / 2, 0, t * 3)
		end
		pillar.Transparency = 1 - 0.55 * q * (0.75 + 0.25 * math.sin(t * 6))
	end)
	return rise
end

------------------------------------------------------------------ рождение травы: у каждой планеты своё
local INTRO = {}
-- Луна: лунный луч с неба, серебряная пыль, озерцо света
INTRO.moon = function(S, ctx, P, th)
	local beam = S.part({ Shape = Enum.PartType.Cylinder, Color = th.light, Transparency = 1, Size = V3(140, 5, 5), CFrame = CF(P + V3(-20, 70, 10)) * CFrame.lookAt(V3(), (V3(20, -70, -10)).Unit) * ANG(0, math.pi / 2, 0) })
	S.anim(0.9, 1.4, function(q) beam.Transparency = 1 - 0.6 * ease(q) beam.Size = V3(140, 1 + 5 * q, 1 + 5 * q) end)
	local pool = S.part({ Shape = Enum.PartType.Cylinder, Color = th.light, Transparency = 1, Size = V3(0.12, 0.5, 0.5), CFrame = CF(P + V3(0, 0.1, 0)) * ANG(0, 0, math.pi / 2) })
	S.anim(1.2, 1.2, function(q) pool.Size = V3(0.12, 0.5 + 6 * ease(q), 0.5 + 6 * ease(q)) pool.Transparency = 1 - 0.5 * q end)
	S.at(1.4, function()
		S.emitter(P + V3(0, 9, 0), { Texture = ctx.TEX.sparkle or "", Color = ColorSequence.new(th.light), LightEmission = 1, Rate = 50, Lifetime = NumberRange.new(1.4, 2),
			Speed = NumberRange.new(2, 4), EmissionDirection = Enum.NormalId.Bottom, Shape = Enum.ParticleEmitterShape.Box, Size = NumberSequence.new(0.3, 0),
			Transparency = NumberSequence.new(0.1, 1) }, V3(7, 0.5, 7))
		S.emitter(P + V3(0, 0.5, 0), { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(C3(190, 195, 210)), Rate = 25, Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(80, 80), EmissionDirection = Enum.NormalId.Top, Size = NumberSequence.new(1.5, 4), Transparency = NumberSequence.new(0.6, 1) })
	end)
	S.shock(1.3, P + V3(0, 0.25, 0), th.light, 7, 1.4, 0.3)
end
-- Марс: песчаный смерч и трещины в грунте
INTRO.mars = function(S, ctx, P, th)
	local hx = S.fx("Helix", V3(2.4, 2.6, 2.4), C3(220, 120, 70), NEON, 0.35)
	if hx then
		S.anim(0.9, 2.6, function(q)
			hx.Transparency = 0.35 + 0.65 * math.max(0, (q - 0.8) / 0.2)
			hx.CFrame = CF(P + V3(0, 2 + q * 2, 0)) * ANG(0, S.t * 9, 0)
		end)
	end
	S.at(1.0, function()
		S.emitter(P + V3(0, 1, 0), { Texture = "rbxasset://textures/particles/smoke_main.dds", Color = ColorSequence.new(C3(210, 120, 70), C3(150, 70, 40)), Rate = 45,
			Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, RotSpeed = NumberRange.new(-200, 200),
			Size = NumberSequence.new(1.5, 5), Transparency = NumberSequence.new(0.4, 1), Acceleration = V3(0, 3, 0) })
	end)
	for j = 1, 8 do
		local a = j / 8 * math.pi * 2
		local sh = S.fx("Shard", 0.9 + (j % 3) * 0.25, C3(120, 50, 36), Enum.Material.Slate, 0)
		if sh then
			local dir = V3(math.cos(a), 0, math.sin(a))
			S.anim(1.5 + j * 0.05, 0.5, function(q)
				local k = backOut(q)
				sh.CFrame = CF(P + dir * (2 + 1.4 * k) + V3(0, -2.2 + 2.6 * k, 0)) * CFrame.lookAt(V3(), dir) * ANG(-1.0, 0, 0)
			end)
		end
	end
	S.shock(1.5, P + V3(0, 0.25, 0), th.col, 9, 1.2)
end
-- Европа: кольцо ледяных шипов и ледяное яйцо, которое лопается при взрыве
INTRO.europa = function(S, ctx, P, th)
	for j = 1, 10 do
		local a = j / 10 * math.pi * 2
		local sh = S.fx("Shard", 0.8 + (j % 2) * 0.5, C3(170, 225, 255), Enum.Material.Glass, 0.2)
		if sh then
			sh.Reflectance = 0.35
			local dir = V3(math.cos(a), 0, math.sin(a))
			S.anim(1.0 + j * 0.06, 0.45, function(q)
				local k = backOut(q)
				sh.CFrame = CF(P + dir * 3.2 + V3(0, -2 + 2.6 * k, 0)) * CFrame.lookAt(V3(), dir) * ANG(-0.5, 0, 0)
			end)
		end
	end
	S.shock(1.0, P + V3(0, 0.25, 0), C3(230, 248, 255), 8, 1.3)
	local egg = S.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.Glass, Color = C3(190, 235, 255), Transparency = 1, Reflectance = 0.4, Size = V3(0.5, 0.5, 0.5), CFrame = CF(P + V3(0, 2.4, 0)) })
	S.anim(1.6, 1.4, function(q) egg.Size = V3(1, 1, 1) * (0.5 + 4.2 * ease(q)) egg.Transparency = 1 - 0.6 * q end)
	S.at(3.6, function()
		egg:Destroy()
		if ctx.FX.gemBurst then ctx.FX.gemBurst(P + V3(0, 2.4, 0), C3(180, 230, 255), 14) end
		ctx.playSfx("water", 0.7)
	end)
	S.at(1.2, function()
		S.emitter(P + V3(0, 10, 0), { Texture = ctx.TEX.glow or "", Color = ColorSequence.new(C3(240, 250, 255)), LightEmission = 0.6, Rate = 60, Lifetime = NumberRange.new(2, 3),
			Speed = NumberRange.new(1, 2), Acceleration = V3(0.5, -3, 0), Shape = Enum.ParticleEmitterShape.Box, Size = NumberSequence.new(0.25, 0.15), Transparency = NumberSequence.new(0.1, 0.9) }, V3(14, 0.5, 14))
	end)
end
-- Ио: раскалённый грунт и фонтан лавы
INTRO.io = function(S, ctx, P, th)
	S.shock(0.9, P + V3(0, 0.25, 0), C3(255, 80, 30), 6, 2.4, 0.1)
	local glow = S.part({ Shape = Enum.PartType.Cylinder, Color = C3(255, 90, 30), Transparency = 1, Size = V3(0.12, 0.5, 0.5), CFrame = CF(P + V3(0, 0.12, 0)) * ANG(0, 0, math.pi / 2) })
	S.anim(1.0, 1.0, function(q) glow.Size = V3(0.12, 0.5 + 5.5 * ease(q), 0.5 + 5.5 * ease(q)) glow.Transparency = 1 - 0.65 * q end)
	S.at(1.5, function()
		S.emitter(P + V3(0, 0.5, 0), { Texture = "rbxasset://textures/particles/fire_main.dds", Color = ColorSequence.new(C3(255, 210, 120), C3(255, 60, 20)), LightEmission = 1, Rate = 90,
			Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(14, 22), SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Top, Acceleration = V3(0, -20, 0),
			Size = NumberSequence.new(2.6, 0.6), Transparency = NumberSequence.new(0.1, 1), RotSpeed = NumberRange.new(-90, 90) })
		S.emitter(P + V3(0, 0.5, 0), { Texture = ctx.TEX.sparkle or "", Color = ColorSequence.new(C3(255, 170, 80), C3(255, 70, 30)), LightEmission = 1, Rate = 60,
			Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Top, Acceleration = V3(0, -6, 0),
			Size = NumberSequence.new(0.35, 0), Transparency = NumberSequence.new(0, 1) })
		ctx.playSfx("boom", 1.6)
	end)
	local ring = S.fx("RingBold", 2.6, C3(255, 120, 40), NEON, 0.15)
	if ring then S.anim(1.5, 2.1, function(q) ring.CFrame = CF(P + V3(0, 0.5 + q * 3.5, 0)) * ANG(0, S.t * 4, 0) ring.Transparency = 0.15 + 0.85 * q end) end
end
-- Туманность: вертикальный портал-галактика, из которого выплывает трава
INTRO.nebula = function(S, ctx, P, th, fwd)
	local portalCF = CFrame.lookAt(P + V3(0, 3, 0), P + V3(0, 3, 0) + fwd) * ANG(math.pi / 2, 0, 0)
	local r1 = S.fx("RingBold", 3.2, th.col, NEON, 0.1)
	local r2 = S.fx("Ring", 3.7, th.light, NEON, 0.2)
	S.anim(0.9, 2.7, function(q)
		local k = backOut(math.min(1, q * 2.2))
		if r1 then r1.Size = ctx.Fx3D.Box.RingBold * 3.2 * math.max(0.05, k) r1.CFrame = portalCF * ANG(0, S.t * 2.4, 0) r1.Transparency = 0.1 + 0.9 * math.max(0, (q - 0.85) / 0.15) end
		if r2 then r2.Size = ctx.Fx3D.Box.Ring * 3.7 * math.max(0.05, k) r2.CFrame = portalCF * ANG(0, -S.t * 1.6, 0) r2.Transparency = 0.2 + 0.8 * math.max(0, (q - 0.85) / 0.15) end
	end)
	S.at(1.1, function()
		local e, h = S.emitter(P + V3(0, 3, 0), { Texture = ctx.TEX.glow or "", Color = ColorSequence.new(th.col, th.light), LightEmission = 1, Rate = 70, Lifetime = NumberRange.new(0.8, 1.2),
			Speed = NumberRange.new(4, 7), Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
			Size = NumberSequence.new(0.6, 0.1), Transparency = NumberSequence.new(0.1, 1) }, V3(6, 6, 6))
		task.delay(3, function() if e.Parent then e.Enabled = false end end)
	end)
end
-- Ядро: золотая звезда падает с неба, золотые лучи и пьедестал-корона
INTRO.core = function(S, ctx, P, th)
	local star = S.fx("Star", 2.2, th.light, NEON, 0)
	if star then
		local a0 = Instance.new("Attachment")
		a0.Position = V3(0, 1.5, 0)
		a0.Parent = star
		local a1 = Instance.new("Attachment")
		a1.Position = V3(0, -1.5, 0)
		a1.Parent = star
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(th.light, th.col)
		tr.LightEmission, tr.Lifetime, tr.FaceCamera = 1, 0.6, true
		tr.Transparency = NumberSequence.new(0.1, 1)
		tr.Parent = star
		S.at(0.9, function() ctx.playSfx("rocket", 1.4) end)
		S.anim(0.9, 1.1, function(q)
			star.CFrame = CF(P + V3(0, 2.5 + 70 * (1 - q) ^ 2, 0)) * ANG(0, S.t * 8, 0)
			if q >= 1 then star.Transparency = 1 end
		end)
	end
	S.shock(2.0, P + V3(0, 0.25, 0), th.light, 11, 1.2)
	S.at(2.0, function()
		ctx.playSfx("boom", 1.2)
		for j = 1, 12 do
			local a = j / 12 * math.pi * 2
			local ray = S.part({ Color = j % 2 == 0 and th.col or th.light, Size = V3(0.25, 0.25, 0.5), Transparency = 0.1 })
			local dir = V3(math.cos(a), 0.15, math.sin(a)).Unit
			local start = S.t
			S.run(function(t)
				local q = math.clamp((t - start) / 1.4, 0, 1)
				local len = 2 + 22 * ease(q)
				ray.Size = V3(0.25, 0.25, len)
				ray.CFrame = CFrame.lookAt(P + V3(0, 1, 0) + dir * len / 2, P + V3(0, 1, 0) + dir * len)
				ray.Transparency = 0.1 + 0.9 * q
				if q >= 1 then ray:Destroy() return true end
			end)
		end
	end)
	local crown = S.fx("Crown", 1.6, th.col, NEON, 0.1)
	if crown then S.anim(2.0, 1.2, function(q) crown.CFrame = CF(P + V3(0, -0.8 + 1.0 * backOut(q), 0)) * ANG(0, S.t * 0.8, 0) end) end
end

------------------------------------------------------------------ взрыв: свой у каждой мутации
local function mutationBlast(S, ctx, P, info, glow, light)
	local has = {}
	for _, id in info.m or {} do has[id] = true end
	local c = P + V3(0, 2.6, 0)
	if has.electric or has.plasma then
		ctx.playSfx("laser", 0.8)
		for j = 1, 7 do
			task.delay(j * 0.05, function()
				local a = math.random() * math.pi * 2
				S.bolt(c + V3(math.cos(a) * 10, 18 + math.random() * 8, math.sin(a) * 10), c + V3(math.cos(a) * 1.5, -1.5, math.sin(a) * 1.5), C3(255, 245, 140))
			end)
		end
	end
	if has.lava then
		S.emitter(P + V3(0, 0.6, 0), { Texture = "rbxasset://textures/particles/fire_main.dds", Color = ColorSequence.new(C3(255, 210, 120), C3(255, 60, 20)), LightEmission = 1, Rate = 0,
			Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(16, 26), SpreadAngle = Vector2.new(90, 5), Size = NumberSequence.new(3, 0.5), Transparency = NumberSequence.new(0.1, 1) }):Emit(70)
	end
	if has.frost and ctx.FX.gemBurst then ctx.FX.gemBurst(c, C3(200, 240, 255), 12) end
	if has.rainbow then
		for j, col in RAINBOW do S.shock(S.t + j * 0.05, P + V3(0, 0.3 + j * 0.05, 0), col, 14 + j * 4, 1.2) end
	end
	if has.golden or has.starry then
		S.emitter(c + V3(0, 6, 0), { Texture = ctx.TEX.sparkle or "", Color = ColorSequence.new(C3(255, 230, 140)), LightEmission = 1, Rate = 0, Lifetime = NumberRange.new(1.6, 2.4),
			Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180), Acceleration = V3(0, -9, 0), Size = NumberSequence.new(0.5, 0), Transparency = NumberSequence.new(0, 1) }):Emit(90)
	end
	if has.ghost then
		S.emitter(c, { Texture = ctx.TEX.wisp or "", Color = ColorSequence.new(C3(210, 225, 255)), LightEmission = 0.6, Rate = 0, Lifetime = NumberRange.new(1.5, 2.2), Speed = NumberRange.new(3, 6),
			SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, RotSpeed = NumberRange.new(-60, 60), Size = NumberSequence.new(1, 3), Transparency = NumberSequence.new(0.3, 1) }):Emit(30)
	end
	if has.galactic or has.supernova or has.singularity then
		local e = S.emitter(c, { Texture = ctx.TEX.glow or "", Color = ColorSequence.new(glow, light), LightEmission = 1, Rate = 0, Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(10, 20),
			SpreadAngle = Vector2.new(180, 10), Size = NumberSequence.new(0.8, 0), Transparency = NumberSequence.new(0, 1), RotSpeed = NumberRange.new(-200, 200) })
		e:Emit(120)
	end
	if has.blackhole or has.singularity then
		-- чёрная дыра: тёмная сфера разрастается и схлопывается в точку
		local orb = S.part({ Shape = Enum.PartType.Ball, Material = Enum.Material.SmoothPlastic, Color = C3(6, 4, 12), Size = V3(0.5, 0.5, 0.5), CFrame = CF(c) })
		local rim = S.fx("RingBold", 1, C3(190, 120, 255), NEON, 0.05)
		local start = S.t
		S.run(function(t)
			local q = math.clamp((t - start) / 0.9, 0, 1)
			local s = q < 0.6 and (q / 0.6) * 9 or 9 * (1 - (q - 0.6) / 0.4)
			orb.Size = V3(1, 1, 1) * math.max(0.1, s)
			if rim then rim.Size = ctx.Fx3D.Box.RingBold * math.max(0.1, s * 0.62) rim.CFrame = CF(c) * ANG(0.4, t * 5, 0) end
			if q >= 1 then orb:Destroy() if rim then rim:Destroy() end return true end
		end)
	end
	if has.supernova or has.singularity then
		for j = 1, 4 do S.shock(S.t + j * 0.08, P + V3(0, 0.4 + j * 0.1, 0), j % 2 == 0 and light or C3(255, 255, 255), 30 + j * 15, 1.6) end
	end
end

------------------------------------------------------------------ главный ролик
function Cinema.play(ctx, info)
	local plr, pg = ctx.plr, ctx.pg
	local cam = workspace.CurrentCamera
	local ch = plr.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not cam or not root then return end
	local G, PM = ctx.G, ctx.PM
	local plant0 = G.Plants[info.id]
	local th = THEME[plant0 and plant0.planet or "moon"] or THEME.moon
	local rarest = G.rarestMut(info.m or {})
	local mt = rarest and G.Mut[rarest]
	local glow = mt and PM.glowOf(mt) or th.col
	local light = glow:Lerp(Color3.new(1, 1, 1), 0.35)
	local chance = info.chance or 1
	local label = chance <= 1e-12 and "КОСМИЧЕСКАЯ НАХОДКА" or chance <= 1e-9 and "НЕВЕРОЯТНАЯ НАХОДКА" or "ЛЕГЕНДАРНАЯ НАХОДКА"
	-- ролик снимается на чистой сцене высоко в небе: соседние растения, таблички и постройки не мешают кадру
	local fwd = V3(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	fwd = fwd.Magnitude > 0.1 and fwd.Unit or V3(0, 0, -1)
	local right = fwd:Cross(V3(0, 1, 0))
	local hipToFeet = 3
	pcall(function()
		if hum and hum.RigType == Enum.HumanoidRigType.R15 then hipToFeet = hum.HipHeight + root.Size.Y / 2 end
	end)
	local stageC = root.Position + V3(0, 650, 0) + right * 260
	local feet = stageC + V3(0, 0.5, 0)
	local P = feet + fwd * 9
	-- настоящий персонаж стоит на месте, пока идёт ролик
	local oldWalk, oldJump = hum and hum.WalkSpeed, hum and hum.JumpPower
	if hum then
		hum.WalkSpeed = 0
		pcall(function() hum.JumpPower = 0 end)
	end
	-- подсказки взаимодействия и таблички над объектами прячутся на время ролика
	if ctx.FX.hidePrompts then ctx.FX.hidePrompts(true) end
	local boards = {}
	for _, d in workspace:GetDescendants() do
		if d:IsA("BillboardGui") and d.Enabled then
			d.Enabled = false
			table.insert(boards, d)
		end
	end
	-- интерфейс прячется, мир темнеет, кинорамка
	local hidden = {}
	for _, g in pg:GetChildren() do
		if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "Cinema" then
			g.Enabled = false
			table.insert(hidden, g)
		end
	end
	local S = newScene(ctx)
	-- пол сцены: тёмный глянцевый диск с кольцами цвета планеты и парящие камни вокруг
	S.part({ Name = "StageFloor", Shape = Enum.PartType.Cylinder, Material = Enum.Material.SmoothPlastic, Color = C3(16, 14, 26), Reflectance = 0.25,
		Size = V3(1, 64, 64), CFrame = CF(stageC) * ANG(0, 0, math.pi / 2) })
	for j, r in { 7, 15, 24, 31.5 } do
		local ring = S.fx("Ring", r, j % 2 == 0 and th.light or th.col, NEON, 0.55)
		if ring then ring.CFrame = CF(stageC + V3(0, 0.52, 0)) end
	end
	local rng = Random.new(77)
	for j = 1, 10 do
		local a = j / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local d = rng:NextNumber(40, 60)
		local s = rng:NextNumber(3, 8)
		S.part({ Name = "StageRock", Material = Enum.Material.Slate, Color = th.col:Lerp(C3(30, 28, 40), 0.75), Size = V3(s * 1.4, s, s * 1.2),
			CFrame = CF(stageC + V3(math.cos(a) * d, rng:NextNumber(-6, 14), math.sin(a) * d)) * ANG(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0) })
	end
	local stageLight = S.part({ Transparency = 1, Size = V3(0.2, 0.2, 0.2), CFrame = CF(stageC + V3(0, 12, 0) + fwd * 4) })
	local pl = Instance.new("PointLight")
	pl.Color, pl.Range, pl.Brightness = th.light, 60, 1.6
	pl.Parent = stageLight
	S.emitter(stageC + V3(0, 10, 0), { Texture = ctx.TEX.sparkle or "", Color = ColorSequence.new(th.light), LightEmission = 1, Rate = 25, Lifetime = NumberRange.new(4, 7),
		Speed = NumberRange.new(0.2, 0.6), SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Box, Size = NumberSequence.new(0.25, 0), Transparency = NumberSequence.new(0.2, 1) }, V3(70, 30, 70))
	-- копия персонажа (живой персонаж остаётся в огороде)
	local actor, aHum, aRoot
	pcall(function()
		local was = ch.Archivable
		ch.Archivable = true
		actor = ch:Clone()
		ch.Archivable = was
	end)
	if actor then
		for _, d in actor:GetDescendants() do
			if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("BillboardGui") or d:IsA("Sound") then
				d:Destroy()
			elseif d:IsA("BasePart") then
				d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch = false, false, false, false
				d.LocalTransparencyModifier = 0
			end
		end
		actor.Name = "CinemaActor"
		aHum = actor:FindFirstChildOfClass("Humanoid")
		aRoot = actor:FindFirstChild("HumanoidRootPart")
		if aHum then
			pcall(function()
				aHum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
				aHum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
			end)
		end
		if aRoot then
			aRoot.Anchored = true
			actor:PivotTo(CFrame.lookAt(feet + V3(0, hipToFeet, 0), P + V3(0, hipToFeet, 0)))
			actor.Parent = S.folder
		else
			actor:Destroy()
			actor = nil
		end
	end
	-- анимации копии: покой, жест «смотри», радость (R15 и R6)
	local animator = aHum and (aHum:FindFirstChildOfClass("Animator") or Instance.new("Animator", aHum))
	local r15 = aHum and aHum.RigType == Enum.HumanoidRigType.R15
	local ANIM = r15 and { idle = 507766388, point = 507770453, cheer = 507770677 } or { idle = 180435571, point = 128853357, cheer = 129423030 }
	local tracks = {}
	local function playAnim(key, looped)
		if not animator then return end
		pcall(function()
			for _, tr in tracks do tr:Stop(0.25) end
			local a = Instance.new("Animation")
			a.AnimationId = "rbxassetid://" .. ANIM[key]
			local tr = animator:LoadAnimation(a)
			tr.Looped = looped
			tr:Play(0.25)
			table.insert(tracks, tr)
		end)
	end
	playAnim("idle", true)
	-- питомец игрока рядом с копией
	local stagePet
	local petId = plr:GetAttribute("Pet") or ""
	if petId ~= "" and ctx.FX.buildPet then
		pcall(function() stagePet = ctx.FX.buildPet(petId, plr:GetAttribute("PetLvl") or 1, S.folder) end)
	end
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "CinemaCC"
	cc.Parent = cam
	TweenService:Create(cc, TweenInfo.new(0.8), { Brightness = -0.15, Saturation = -0.3, Contrast = 0.18 }):Play()
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FarIntensity, dof.NearIntensity, dof.InFocusRadius, dof.FocusDistance = 0.6, 0.2, 10, 20
	dof.Parent = cam
	local oldFov = cam.FieldOfView
	cam.CameraType = Enum.CameraType.Scriptable
	local K, T = ctx.K, ctx.T
	local gui = Instance.new("ScreenGui")
	gui.Name, gui.ResetOnSpawn, gui.IgnoreGuiInset, gui.DisplayOrder = "Cinema", false, true, 75
	gui.Parent = pg
	local function bar(top)
		local f = Instance.new("Frame")
		f.BackgroundColor3, f.BorderSizePixel = Color3.new(0, 0, 0), 0
		f.Size = UDim2.new(1, 0, 0, 0)
		if not top then f.AnchorPoint, f.Position = Vector2.new(0, 1), UDim2.fromScale(0, 1) end
		f.Parent = gui
		TweenService:Create(f, TweenInfo.new(0.6), { Size = UDim2.fromScale(1, 0.1) }):Play()
		return f
	end
	local barTop, barBot = bar(true), bar(false)
	local skip = K.button(gui, "Пропустить", T.panel, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(120, 30), MaxText = 14, ZIndex = 40 })
	skip.Activated:Connect(function() S.done = true end)
	-- камера: план (склейка в начале) и плавное движение внутри плана
	local shot
	local function cut(t0, dur, fromPos, toPos, lookFrom, lookTo, fov)
		S.at(t0, function() shot = { t0 = S.t, dur = dur, a = fromPos, b = toPos, la = lookFrom, lb = lookTo, fov = fov or oldFov } end)
	end
	local aPos = feet + V3(0, hipToFeet, 0)
	local mid = (aPos + P) / 2
	-- 1. призыв: из-за спины персонажа
	cut(0, 1.7, aPos - fwd * 10 + right * 4 + V3(0, 3.5, 0), aPos - fwd * 7 + right * 3 + V3(0, 2.8, 0), mid + V3(0, 2, 0), P + V3(0, 2, 0), oldFov)
	-- 2. рождение: крупно сбоку, медленный облёт
	cut(1.7, 1.9, P + right * 9 + fwd * 3 + V3(0, 3, 0), P + right * 7 - fwd * 2 + V3(0, 2.2, 0), P + V3(0, 2, 0), P + V3(0, 2.4, 0), oldFov - 8)
	-- 3. взрыв: снизу вверх, замедленно
	cut(3.6, 0.8, P - fwd * 6 - right * 3 + V3(0, 1, 0), P - fwd * 5 - right * 4 + V3(0, 1.4, 0), P + V3(0, 3, 0), P + V3(0, 3.6, 0), oldFov + 10)
	-- 4. герой: персонаж и трофей в одном кадре
	cut(4.4, 2.6, mid + right * 10.5 + V3(0, 3.6, 0) - fwd * 1, mid + right * 9 + V3(0, 3.1, 0) + fwd * 1, mid + V3(0, 2.4, 0), mid + V3(0, 2.6, 0), oldFov)
	S.run(function(t)
		-- другой режим мог забрать камеру — возвращаем её ролику
		if cam.CameraType ~= Enum.CameraType.Scriptable then cam.CameraType = Enum.CameraType.Scriptable end
		if not shot then return end
		local q = math.clamp((t - shot.t0) / shot.dur, 0, 1)
		local e = ease(q)
		local pos = shot.a:Lerp(shot.b, e)
		local look = shot.la:Lerp(shot.lb, e)
		cam.CFrame = CFrame.lookAt(pos, look)
		cam.FieldOfView = shot.fov
		dof.FocusDistance = (pos - look).Magnitude
	end)
	-- 1. магический круг и жест персонажа
	S.at(0.15, function()
		ctx.playSfx("brew", 0.9)
		magicCircle(S, ctx, feet, th)
		playAnim("point", false)
		task.delay(1.6, function() if not S.done then playAnim("idle", true) end end)
	end)
	-- 2. рождение по теме планеты
	local intro = INTRO[plant0 and plant0.planet or "moon"] or INTRO.moon
	intro(S, ctx, P, th, fwd)
	S.at(1.1, function() ctx.playSfx("mutation", 0.85) end)
	-- трава и её движение по форме
	local plant = PM.build(info.id, info.m)
	plant:PivotTo(CF(P))
	plant:ScaleTo(0.05)
	plant.Parent = S.folder
	local motion = MOTION[plant0 and plant0.form or ""] or "grow"
	local pre, final = 0.9, 2.0
	local plantCF = CF(P)
	local scale = 0.05
	local yaw = 0
	if motion == "float" then
		S.anim(2.0, 1.6, function(q)
			local e = ease(q)
			scale = 0.05 + pre * math.min(1, q * 2)
			plantCF = CF(P + V3(0, 9 * (1 - e) + math.sin(S.t * 3) * 0.25 * (1 - e), 0))
			yaw = S.t * 1.5 * (1 - e)
		end)
	elseif motion == "pop" then
		S.anim(2.4, 1.2, function(q)
			scale = 0.05 + pre * (math.min(1, q * 1.6) + 0.35 * math.sin(q * math.pi * 4) * (1 - q))
			plantCF = CF(P)
		end)
	elseif motion == "spin" then
		S.anim(2.0, 1.6, function(q)
			scale = 0.05 + pre * ease(q)
			plantCF = CF(P + V3(0, -2.5 * (1 - ease(q)), 0))
			yaw = q * math.pi * 4
		end)
	else
		S.anim(2.0, 1.6, function(q)
			scale = 0.05 + pre * q ^ 1.4
			plantCF = CF(P)
			yaw = math.sin(S.t * 2) * 0.15 * (1 - q)
		end)
	end
	-- 3. взрыв в замедленной съёмке
	S.at(3.6, function()
		S.speed = 0.32
		ctx.playSfx("boom", 0.7)
		ctx.playSfx("legendary")
		local fl = Instance.new("Frame")
		fl.Size, fl.BackgroundColor3, fl.BackgroundTransparency, fl.ZIndex = UDim2.fromScale(1, 1), Color3.new(1, 1, 1), 0, 50
		fl.Parent = gui
		TweenService:Create(fl, TweenInfo.new(1.1), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(cc, TweenInfo.new(1.4), { Brightness = 0.03, Saturation = 0.25, Contrast = 0.12 }):Play()
		if ctx.FX.burst then
			ctx.FX.burst(P + V3(0, 2.5, 0), light, 140)
			ctx.FX.burst(P + V3(0, 2.5, 0), glow, 90)
		end
		if ctx.FX.gemBurst then ctx.FX.gemBurst(P + V3(0, 2.5, 0), glow, 16) end
		mutationBlast(S, ctx, P, info, glow, light)
	end)
	S.shock(3.6, P + V3(0, 0.35, 0), light, 34, 1.0)
	S.shock(3.72, P + V3(0, 0.5, 0), glow, 52, 1.3)
	S.anim(3.6, 0.5, function(q) scale = 0.05 + pre + (final - pre) * backOut(q) end)
	S.at(4.25, function() S.speed = 1 end)
	-- 4. герой: персонаж радуется, надпись с шансом, конфетти
	S.at(4.4, function()
		playAnim("cheer", true)
		local lab = K.text(gui, label, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.1, 6), Size = UDim2.new(0.8, 0, 0, 30), MaxText = 26, TextColor3 = light, ZIndex = 20 })
		local odds = K.text(gui, "ШАНС " .. G.fmtOdds(chance), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.1, 36), Size = UDim2.new(0.9, 0, 0, 64), MaxText = 60, TextColor3 = T.gold, ZIndex = 20 })
		K.gradient(odds, C3(255, 245, 200), C3(255, 170, 60), 90)
		local title = G.mutTitle(info.m or {})
		K.text(gui, (title ~= "" and (title .. " ") or "") .. (plant0 and plant0.name or ""), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.9, -58), Size = UDim2.new(0.9, 0, 0, 34), MaxText = 30, TextColor3 = T.text, ZIndex = 20 })
		K.text(gui, ("%s · вес %.2f кг"):format(th.name, info.w or 0), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.9, -32), Size = UDim2.new(0.6, 0, 0, 24), MaxText = 18, TextColor3 = T.sub, ZIndex = 20 })
		K.pop(lab)
		K.pop(odds)
		local cols = { glow, light, th.col, th.light, T.gold, Color3.new(1, 1, 1) }
		for i = 1, 70 do
			task.delay(i * 0.02, function()
				if not gui.Parent then return end
				local cf = Instance.new("Frame")
				cf.BorderSizePixel, cf.BackgroundColor3, cf.ZIndex = 0, cols[math.random(1, #cols)], 30
				cf.Size = UDim2.fromOffset(math.random(6, 11), math.random(10, 18))
				cf.Position, cf.Rotation = UDim2.new(math.random(), 0, -0.05, 0), math.random(0, 360)
				cf.Parent = gui
				TweenService:Create(cf, TweenInfo.new(math.random(18, 30) / 10, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Position = UDim2.new(cf.Position.X.Scale + (math.random() - 0.5) * 0.3, 0, 1.08, 0), Rotation = cf.Rotation + math.random(-540, 540) }):Play()
				task.delay(3.2, function() cf:Destroy() end)
			end)
		end
	end)
	-- 5. облёт трофея
	S.at(7.0, function()
		local start = S.t
		shot = nil
		S.run(function(t)
			local a = (t - start) * 0.25 + math.atan2(right.Z, right.X)
			local pos = P + V3(math.cos(a) * 12, 4.5, math.sin(a) * 12)
			cam.CFrame = CFrame.lookAt(pos, P + V3(0, 3, 0))
			dof.FocusDistance = 12
		end)
	end)
	local okB
	S.at(5.6, function()
		okB = K.button(gui, "Круто!", T.green, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 0.9, -8), Size = UDim2.fromOffset(150, 44), MaxText = 20, ZIndex = 40 })
		okB.Activated:Connect(function() S.done = true end)
		K.pop(okB)
		skip.Visible = false
	end)
	S.at(20, function() S.done = true end)
	-- кадр за кадром
	local conn = RunService.RenderStepped:Connect(function(dt)
		S.step(math.min(dt, 0.1))
		if stagePet and ctx.FX.posePet then
			local pp = feet + right * 3 - fwd * 0.8 + V3(0, (stagePet.mesh and 1.6 or 5) + math.sin(S.t * 2) * 0.3, 0)
			pcall(ctx.FX.posePet, stagePet, CFrame.lookAt(pp, pp + fwd), S.t)
		end
		if plant.Parent then
			plant:PivotTo(plantCF * ANG(0, yaw, 0))
			pcall(function() plant:ScaleTo(math.max(0.05, scale)) end)
			PM.animate(plant, S.t)
		end
	end)
	while not S.done do task.wait(0.05) end
	conn:Disconnect()
	-- конец: всё возвращается
	TweenService:Create(barTop, TweenInfo.new(0.35), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(barBot, TweenInfo.new(0.35), { Size = UDim2.new(1, 0, 0, 0) }):Play()
	TweenService:Create(cc, TweenInfo.new(0.35), { Brightness = 0, Saturation = 0, Contrast = 0 }):Play()
	task.wait(0.4)
	gui:Destroy()
	cc:Destroy()
	dof:Destroy()
	S.folder:Destroy()
	cam.FieldOfView = oldFov
	cam.CameraType = Enum.CameraType.Custom
	if hum and hum.Parent then
		hum.WalkSpeed = oldWalk or 16
		pcall(function() hum.JumpPower = oldJump or 50 end)
	end
	local nowHum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if nowHum then cam.CameraSubject = nowHum end
	for _, g in hidden do if g.Parent then g.Enabled = true end end
	for _, b in boards do if b.Parent then b.Enabled = true end end
	if ctx.FX.hidePrompts then ctx.FX.hidePrompts(false) end
end

return Cinema
