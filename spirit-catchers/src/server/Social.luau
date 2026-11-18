-- Социальные системы: дворы со спутниками (визиты и лайки), безопасный обмен дубликатами, клубы ловцов.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Social = {}
local memWeek -- поимки клубов за неделю в памяти (если DataStore недоступен)
local R = {} -- remotes
local ctx -- данные и функции из Main

-- remotes создаются сразу при загрузке Main, чтобы клиент их нашёл
function Social.remotes(remote)
	R.Visit = remote("VisitYard", "RemoteFunction")
	R.Trade = remote("Trade", "RemoteFunction")
	R.TradeEv = remote("TradeState")
	R.Club = remote("Club", "RemoteFunction")
	R.Race = remote("Race", "RemoteFunction")
	R.RaceEv = remote("RaceState")
	R.JoinFriend = remote("JoinFriend", "RemoteFunction")
	R.ClubTop = remote("ClubTop", "RemoteFunction")
end

------------------------------------------------------------------ дворы
local PLOT_X = { -96, -32, 32, 96 }
local PLOT_Z = { 452, 522 }
local PLOT = 56
local plots = {} -- [i] = { folder, sign, owner }
local plotOf = {} -- [Player] = i
local function part(parent, name, size, cf, color, mat, props)
	local p = Instance.new("Part")
	p.Name, p.Size, p.CFrame, p.Color = name, size, cf, color
	p.Anchored = true
	p.Material = mat or Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in props or {} do p[k] = v end
	p.Parent = parent
	return p
end
local function buildYards()
	local root = Instance.new("Folder")
	root.Name = "Yards"
	root.Parent = workspace
	-- общий остров дворов: площадка, дорожка, невидимые стены
	part(root, "YardIsland", Vector3.new(280, 1, 160), CFrame.new(0, 0, 487), Color3.fromRGB(60, 78, 64), Enum.Material.Grass)
	part(root, "YardPath", Vector3.new(14, 0.1, 150), CFrame.new(0, 0.55, 487), Color3.fromRGB(150, 135, 115), Enum.Material.Pebble, { CanCollide = false })
	part(root, "YardPathX", Vector3.new(270, 0.1, 10), CFrame.new(0, 0.55, 487), Color3.fromRGB(150, 135, 115), Enum.Material.Pebble, { CanCollide = false })
	for _, w in {
		{ Vector3.new(1, 60, 160), Vector3.new(140.5, 30, 487) }, { Vector3.new(1, 60, 160), Vector3.new(-140.5, 30, 487) },
		{ Vector3.new(280, 60, 1), Vector3.new(0, 30, 407.5) }, { Vector3.new(280, 60, 1), Vector3.new(0, 30, 567.5) },
	} do
		part(root, "Boundary", w[1], CFrame.new(w[2]), Color3.new(), nil, { Transparency = 1, CanQuery = false })
	end
	-- арка входа с фонарями
	for _, x in { -9, 9 } do
		part(root, "ArchPost", Vector3.new(1.6, 14, 1.6), CFrame.new(x, 7.5, 418), Color3.fromRGB(170, 50, 45), Enum.Material.Wood)
		local l = part(root, "ArchLamp", Vector3.new(1.6, 2, 1.6), CFrame.new(x, 12, 416.5), Color3.fromRGB(255, 170, 80), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		local pl = Instance.new("PointLight")
		pl.Range, pl.Brightness, pl.Color = 22, 1, Color3.fromRGB(255, 180, 100)
		pl.Parent = l
	end
	part(root, "ArchBeam", Vector3.new(24, 1.4, 2.2), CFrame.new(0, 15, 418), Color3.fromRGB(40, 30, 30), Enum.Material.Wood)
	local i = 0
	for _, z in PLOT_Z do
		for _, x in PLOT_X do
			i += 1
			local f = Instance.new("Folder")
			f.Name = "Plot" .. i
			f:SetAttribute("Owner", 0)
			f:SetAttribute("Kinds", "")
			f:SetAttribute("Center", Vector3.new(x, 0.5, z))
			part(f, "PlotGround", Vector3.new(PLOT, 0.2, PLOT), CFrame.new(x, 0.6, z), Color3.fromRGB(78, 110, 74), Enum.Material.Grass)
			-- низкий забор
			for _, side in { -1, 1 } do
				part(f, "Fence", Vector3.new(PLOT, 2.2, 0.6), CFrame.new(x, 1.6, z + side * PLOT / 2), Color3.fromRGB(120, 90, 60), Enum.Material.WoodPlanks)
				part(f, "Fence", Vector3.new(0.6, 2.2, PLOT * 0.38), CFrame.new(x + side * PLOT / 2, 1.6, z - PLOT * 0.31), Color3.fromRGB(120, 90, 60), Enum.Material.WoodPlanks)
				part(f, "Fence", Vector3.new(0.6, 2.2, PLOT * 0.38), CFrame.new(x + side * PLOT / 2, 1.6, z + PLOT * 0.31), Color3.fromRGB(120, 90, 60), Enum.Material.WoodPlanks)
			end
			-- домик ловца
			local back = z > 487 and 1 or -1
			part(f, "Hut", Vector3.new(14, 8, 10), CFrame.new(x, 4.6, z + back * 18), Color3.fromRGB(110, 78, 55), Enum.Material.WoodPlanks)
			part(f, "HutRoof", Vector3.new(16, 1.2, 12), CFrame.new(x, 9.2, z + back * 18), Color3.fromRGB(150, 45, 40), Enum.Material.Slate)
			local win = part(f, "HutWindow", Vector3.new(3, 2.4, 0.2), CFrame.new(x, 5, z + back * 12.9), Color3.fromRGB(255, 190, 110), Enum.Material.Neon)
			local wl = Instance.new("PointLight")
			wl.Range, wl.Brightness, wl.Color = 14, 0.8, Color3.fromRGB(255, 190, 110)
			wl.Parent = win
			-- табличка с именем и лайками
			local sign = part(f, "Sign", Vector3.new(10, 5, 0.6), CFrame.new(x + 14, 3.4, z - back * PLOT / 2 + back * 2) * CFrame.Angles(0, back > 0 and 0 or math.pi, 0), Color3.fromRGB(60, 40, 35), Enum.Material.Wood)
			for _, face in { Enum.NormalId.Front, Enum.NormalId.Back } do
				local g = Instance.new("SurfaceGui")
				g.Face = face
				g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
				g.PixelsPerStud = 24
				local t = Instance.new("TextLabel")
				t.Name = "Text"
				t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
				t.TextColor3, t.TextStrokeTransparency = Color3.new(1, 1, 1), 0.3
				t.Text = "Свободный двор"
				t.Parent = g
				g.Parent = sign
			end
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText, prompt.ObjectText = "Нравится", "Двор"
			prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0.3, 10, false
			prompt.Enabled = false
			prompt.Parent = sign
			f.Parent = root
			plots[i] = { folder = f, sign = sign, prompt = prompt, owner = nil, center = Vector3.new(x, 0.5, z), back = back }
		end
	end
end

local function yardKinds(d)
	-- до 6 духов: самые редкие пойманные, с лучшей разновидностью
	local rank = {}
	for i, k in ctx.Catalog.RarityOrder do rank[k] = i end
	local list = {}
	for kind, n in d.saved do
		if n > 0 and ctx.Catalog.Kinds[kind] then table.insert(list, kind) end
	end
	table.sort(list, function(a, b)
		local ra, rb = rank[ctx.Catalog.Kinds[a].rarity], rank[ctx.Catalog.Kinds[b].rarity]
		if ra ~= rb then return ra > rb end
		return (d.saved[a] or 0) > (d.saved[b] or 0)
	end)
	local out = {}
	for i = 1, math.min(6, #list) do
		local kind = list[i]
		local best = "normal"
		local vs = d.variants[kind] or {}
		for j = #ctx.Catalog.VariantOrder, 2, -1 do
			if vs[ctx.Catalog.VariantOrder[j]] then
				best = ctx.Catalog.VariantOrder[j]
				break
			end
		end
		table.insert(out, kind .. ":" .. best .. ((d.evolved and d.evolved[kind]) and ":e" or ""))
	end
	if d.equipped and not table.find(list, d.equipped) then table.insert(out, d.equipped .. ":normal") end
	return table.concat(out, ",")
end

-- мебель двора: простые постройки из деталей в слотах участка
local WOOD, DARK, RED, STONE = Color3.fromRGB(120, 85, 55), Color3.fromRGB(50, 35, 30), Color3.fromRGB(200, 55, 45), Color3.fromRGB(140, 140, 150)
local function lamp(parent, pos, color)
	local l = part(parent, "Lamp", Vector3.new(1.4, 1.6, 1.4), CFrame.new(pos), color, Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 14, 0.7, color
	pl.Parent = l
end
local FURN = {
	lanternPost = function(f, o)
		part(f, "Post", Vector3.new(0.6, 7, 0.6), CFrame.new(o + Vector3.new(0, 4, 0)), DARK, Enum.Material.Wood)
		lamp(f, o + Vector3.new(0, 7.8, 0), Color3.fromRGB(255, 170, 80))
	end,
	bench = function(f, o)
		part(f, "Seat", Vector3.new(6, 0.5, 2), CFrame.new(o + Vector3.new(0, 1.6, 0)), WOOD, Enum.Material.WoodPlanks)
		part(f, "Back", Vector3.new(6, 1.6, 0.4), CFrame.new(o + Vector3.new(0, 2.6, 0.9)), WOOD, Enum.Material.WoodPlanks)
		for _, x in { -2.6, 2.6 } do part(f, "Leg", Vector3.new(0.4, 1.2, 1.6), CFrame.new(o + Vector3.new(x, 0.9, 0)), DARK, Enum.Material.Wood) end
	end,
	bonsai = function(f, o)
		part(f, "Pot", Vector3.new(2.4, 1.2, 2.4), CFrame.new(o + Vector3.new(0, 1.1, 0)), Color3.fromRGB(90, 60, 110), Enum.Material.Slate)
		part(f, "Trunk", Vector3.new(0.5, 2.4, 0.5), CFrame.new(o + Vector3.new(0, 2.8, 0)) * CFrame.Angles(0, 0, 0.3), DARK, Enum.Material.Wood)
		part(f, "Leaves", Vector3.new(3.4, 1.6, 3.4), CFrame.new(o + Vector3.new(0.5, 4.2, 0)), Color3.fromRGB(70, 140, 80), Enum.Material.Grass, { Shape = Enum.PartType.Ball })
	end,
	stoneGarden = function(f, o)
		part(f, "Sand", Vector3.new(8, 0.2, 6), CFrame.new(o + Vector3.new(0, 0.75, 0)), Color3.fromRGB(220, 210, 185), Enum.Material.Sand, { CanCollide = false })
		for i, p in { Vector3.new(-2, 0, -1), Vector3.new(1.8, 0, 1), Vector3.new(0.5, 0, -1.8) } do
			part(f, "Rock", Vector3.new(1.4 + i * 0.3, 1 + i * 0.3, 1.2 + i * 0.2), CFrame.new(o + p + Vector3.new(0, 1.2, 0)), STONE, Enum.Material.Rock, { Shape = Enum.PartType.Ball })
		end
	end,
	sakura = function(f, o)
		part(f, "Trunk", Vector3.new(1, 7, 1), CFrame.new(o + Vector3.new(0, 4, 0)), DARK, Enum.Material.Wood)
		for i, p in { Vector3.new(0, 8.5, 0), Vector3.new(2, 7.5, 1), Vector3.new(-2, 7.8, -1) } do
			part(f, "Blossom", Vector3.new(5, 4, 5), CFrame.new(o + p), Color3.fromRGB(255, 170 + i * 10, 210), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false })
		end
	end,
	garland = function(f, o)
		for _, x in { -9, 9 } do part(f, "Pole", Vector3.new(0.5, 7, 0.5), CFrame.new(o + Vector3.new(x, 4, 0)), DARK, Enum.Material.Wood) end
		part(f, "String", Vector3.new(18, 0.1, 0.1), CFrame.new(o + Vector3.new(0, 7.2, 0)), DARK, nil, { CanCollide = false })
		for x = -7, 7, 3.5 do lamp(f, o + Vector3.new(x, 6.4, 0), Color3.fromHSV(((x + 7) / 14) * 0.9, 0.6, 1)) end
	end,
	bell = function(f, o)
		for _, x in { -2, 2 } do part(f, "Post", Vector3.new(0.6, 6, 0.6), CFrame.new(o + Vector3.new(x, 3.6, 0)), RED, Enum.Material.Wood) end
		part(f, "Beam", Vector3.new(5.4, 0.6, 0.8), CFrame.new(o + Vector3.new(0, 6.6, 0)), DARK, Enum.Material.Wood)
		part(f, "Bell", Vector3.new(2, 2.6, 2), CFrame.new(o + Vector3.new(0, 4.8, 0)), Color3.fromRGB(200, 160, 70), Enum.Material.Metal, { Shape = Enum.PartType.Ball })
	end,
	bridge = function(f, o)
		part(f, "Stream", Vector3.new(4, 0.2, 14), CFrame.new(o + Vector3.new(0, 0.72, 0)), Color3.fromRGB(70, 140, 200), Enum.Material.Glass, { Transparency = 0.2, CanCollide = false })
		part(f, "Deck", Vector3.new(7, 0.5, 3), CFrame.new(o + Vector3.new(0, 1.4, 0)), RED, Enum.Material.Wood)
		for _, z in { -1.4, 1.4 } do part(f, "Rail", Vector3.new(7, 0.8, 0.3), CFrame.new(o + Vector3.new(0, 2, z)), RED, Enum.Material.Wood) end
	end,
	torii = function(f, o)
		for _, x in { -4, 4 } do part(f, "Pillar", Vector3.new(1, 9, 1), CFrame.new(o + Vector3.new(x, 5, 0)), RED, Enum.Material.SmoothPlastic) end
		part(f, "Top", Vector3.new(11, 1, 1.4), CFrame.new(o + Vector3.new(0, 9.8, 0)), DARK, Enum.Material.Wood)
		part(f, "Mid", Vector3.new(9, 0.6, 1), CFrame.new(o + Vector3.new(0, 8.2, 0)), RED, Enum.Material.SmoothPlastic)
	end,
	fountain = function(f, o)
		part(f, "Basin", Vector3.new(6, 1.2, 6), CFrame.new(o + Vector3.new(0, 1.2, 0)), STONE, Enum.Material.Concrete, { Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(o + Vector3.new(0, 1.2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		part(f, "Water", Vector3.new(0.3, 5.4, 5.4), CFrame.new(o + Vector3.new(0, 1.9, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 200, 255), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.3, CanCollide = false })
		local orb = part(f, "SpiritOrb", Vector3.new(1.4, 1.4, 1.4), CFrame.new(o + Vector3.new(0, 4, 0)), Color3.fromRGB(170, 230, 255), Enum.Material.Neon, { Shape = Enum.PartType.Ball, CanCollide = false })
		local pe = Instance.new("ParticleEmitter")
		pe.Color, pe.LightEmission, pe.Rate = ColorSequence.new(Color3.fromRGB(170, 230, 255)), 0.6, 10
		pe.Speed, pe.Lifetime, pe.Size = NumberRange.new(2, 4), NumberRange.new(1, 1.5), NumberSequence.new(0.3, 0)
		pe.Acceleration = Vector3.new(0, -6, 0)
		pe.Parent = orb
	end,
	koiPond = function(f, o)
		part(f, "Pond", Vector3.new(0.3, 9, 9), CFrame.new(o + Vector3.new(0, 0.75, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 120, 190), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.15, CanCollide = false })
		for i = 1, 3 do
			local a = i * 2.1
			part(f, "Koi", Vector3.new(0.8, 0.4, 1.8), CFrame.new(o + Vector3.new(math.cos(a) * 2.4, 0.95, math.sin(a) * 2.4)) * CFrame.Angles(0, a, 0), i == 2 and Color3.fromRGB(255, 250, 240) or Color3.fromRGB(255, 120, 40), Enum.Material.SmoothPlastic, { CanCollide = false })
		end
	end,
	shrine = function(f, o)
		part(f, "Base", Vector3.new(6, 1, 5), CFrame.new(o + Vector3.new(0, 1, 0)), STONE, Enum.Material.Concrete)
		part(f, "House", Vector3.new(4, 4, 3.4), CFrame.new(o + Vector3.new(0, 3.5, 0)), Color3.fromRGB(150, 50, 45), Enum.Material.Wood)
		part(f, "Roof", Vector3.new(5.6, 0.8, 5), CFrame.new(o + Vector3.new(0, 6, 0)), Color3.fromRGB(40, 70, 60), Enum.Material.Slate)
		lamp(f, o + Vector3.new(0, 3.4, -1.8), Color3.fromRGB(255, 210, 120))
	end,
	spiritStatue = function(f, o)
		part(f, "Pedestal", Vector3.new(3, 2, 3), CFrame.new(o + Vector3.new(0, 1.6, 0)), STONE, Enum.Material.Marble)
		part(f, "Body", Vector3.new(2.4, 3, 2.4), CFrame.new(o + Vector3.new(0, 4.1, 0)), Color3.fromRGB(230, 230, 240), Enum.Material.Marble, { Shape = Enum.PartType.Ball })
		for _, x in { -0.7, 0.7 } do
			part(f, "Ear", Vector3.new(0.6, 1.2, 0.4), CFrame.new(o + Vector3.new(x, 5.8, 0)), Color3.fromRGB(230, 230, 240), Enum.Material.Marble)
			part(f, "Eye", Vector3.new(0.4, 0.4, 0.2), CFrame.new(o + Vector3.new(x * 0.6, 4.6, -1.15)), Color3.fromRGB(120, 220, 255), Enum.Material.Neon)
		end
	end,
}
FURN.goldPagoda = function(f, o)
	for i = 0, 2 do
		local w = 7 - i * 1.8
		part(f, "Pagoda", Vector3.new(w - 1.5, 2.6, w - 1.5), CFrame.new(o + Vector3.new(0, 1.8 + i * 3.2, 0)), Color3.fromRGB(150, 50, 45), Enum.Material.Wood)
		part(f, "PagodaRoof", Vector3.new(w + 1, 0.6, w + 1), CFrame.new(o + Vector3.new(0, 3.4 + i * 3.2, 0)), Color3.fromRGB(240, 190, 60), Enum.Material.Metal)
	end
	lamp(f, o + Vector3.new(0, 11.2, 0), Color3.fromRGB(255, 220, 120))
end
FURN.moonGate = function(f, o)
	for i = 0, 15 do
		local a = i / 16 * math.pi * 2
		part(f, "MoonGate", Vector3.new(1.4, 1.6, 1.2), CFrame.new(o + Vector3.new(math.cos(a) * 4.5, 5 + math.sin(a) * 4.5, 0)) * CFrame.Angles(0, 0, a), Color3.fromRGB(200, 205, 215), Enum.Material.Marble)
	end
	local disc = part(f, "MoonGlow", Vector3.new(0.2, 7.6, 7.6), CFrame.new(o + Vector3.new(0, 5, 0)) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(190, 215, 255), Enum.Material.Neon, { Shape = Enum.PartType.Cylinder, Transparency = 0.6, CanCollide = false })
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 18, 0.8, Color3.fromRGB(190, 215, 255)
	pl.Parent = disc
end
local function buildFurniture(p, d)
	local old = p.folder:FindFirstChild("Furniture")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "Furniture"
	for id in (d and d.furniture) or {} do
		local cfg = ctx.Catalog.Live.Furniture[id]
		local fn = FURN[id]
		if cfg and fn then
			local o = p.center + Vector3.new(cfg.slot.X, 0.2, cfg.slot.Z * p.back)
			pcall(fn, f, o)
		end
	end
	f.Parent = p.folder
end

function Social.refreshYard(plr)
	local i = plotOf[plr]
	local d = ctx.data[plr]
	if not (i and d) then return end
	local p = plots[i]
	p.folder:SetAttribute("Kinds", yardKinds(d))
	local sig = ""
	for id in d.furniture or {} do sig ..= id end
	if p.furnSig ~= sig then
		p.furnSig = sig
		buildFurniture(p, d)
	end
	local text = ("Двор %s\nДухов %d/%d   Лайков %d"):format(plr.DisplayName, ctx.distinct(d), #ctx.Catalog.Order, d.yardLikes or 0)
	for _, g in p.sign:GetChildren() do
		if g:IsA("SurfaceGui") then g.Text.Text = text end
	end
end

local function assignPlot(plr)
	for i, p in plots do
		if not p.owner then
			p.owner = plr
			plotOf[plr] = i
			p.folder:SetAttribute("Owner", plr.UserId)
			p.folder:SetAttribute("OwnerName", plr.DisplayName)
			p.prompt.Enabled = true
			p.prompt.ObjectText = "Двор " .. plr.DisplayName
			Social.refreshYard(plr)
			return
		end
	end
end
local function freePlot(plr)
	local i = plotOf[plr]
	if not i then return end
	local p = plots[i]
	p.owner = nil
	plotOf[plr] = nil
	p.folder:SetAttribute("Owner", 0)
	p.folder:SetAttribute("Kinds", "")
	p.prompt.Enabled = false
	p.furnSig = nil
	buildFurniture(p, nil)
	for _, g in p.sign:GetChildren() do
		if g:IsA("SurfaceGui") then g.Text.Text = "Свободный двор" end
	end
end

local function onLike(liker, plotIndex)
	local p = plots[plotIndex]
	local owner = p and p.owner
	if not owner or owner == liker then return end
	local d, od = ctx.data[liker], ctx.data[owner]
	if not (d and od) then return end
	local day = math.floor(os.time() / 86400)
	if typeof(d.likes) ~= "table" or d.likes.day ~= day then d.likes = { day = day, given = {} } end
	local key = tostring(owner.UserId)
	if d.likes.given[key] then
		ctx.NoticeEv:FireClient(liker, "Ты уже оценил этот двор сегодня")
		return
	end
	d.likes.given[key] = true
	od.yardLikes = (od.yardLikes or 0) + 1
	od.coins += 25
	d.coins += 10
	ctx.NoticeEv:FireClient(owner, liker.DisplayName .. " оценил твой двор! +25 монет")
	ctx.NoticeEv:FireClient(liker, "Спасибо за визит! +10 монет")
	ctx.pushState(owner)
	ctx.pushState(liker)
	Social.refreshYard(owner)
end

------------------------------------------------------------------ обмен дубликатами
-- предложить можно только дубликаты (у себя остаётся хотя бы один дух вида), до 4 видов.
-- Любое изменение снимает готовность; обмен проходит через 3 секунды после «Готов» у обоих.
local trades = {} -- [id] = { a, b, offer = { [Player] = { [kind] = n } }, ready = { [Player] = bool }, seq }
local tradeOf = {} -- [Player] = id
local requests = {} -- [target] = { from = Player, at = os.clock() }
local nextTradeId = 0

local function tradeState(t, plr)
	local other = t.a == plr and t.b or t.a
	return {
		id = t.id, other = other.DisplayName, mine = t.offer[plr], theirs = t.offer[other],
		readyMe = t.ready[plr] == true, readyThem = t.ready[other] == true, counting = t.counting == true,
	}
end
local function pushTrade(t)
	for _, p in { t.a, t.b } do
		if p.Parent then R.TradeEv:FireClient(p, { type = "state", trade = tradeState(t, p) }) end
	end
end
local function closeTrade(t, msg)
	trades[t.id] = nil
	for _, p in { t.a, t.b } do
		tradeOf[p] = nil
		if p.Parent then R.TradeEv:FireClient(p, { type = "closed", msg = msg }) end
	end
end
local function offerCount(o)
	local n = 0
	for _ in o do n += 1 end
	return n
end
local function canGive(d, kind, n)
	return (d.saved[kind] or 0) - n >= 1
end
local function finishTrade(t)
	local da, db = ctx.data[t.a], ctx.data[t.b]
	if not (da and db) then return closeTrade(t, "Обмен отменён") end
	-- финальная проверка обеих сторон
	for kind, n in t.offer[t.a] do
		if not canGive(da, kind, n) then return closeTrade(t, "Обмен отменён: не хватает духов") end
	end
	for kind, n in t.offer[t.b] do
		if not canGive(db, kind, n) then return closeTrade(t, "Обмен отменён: не хватает духов") end
	end
	local function move(from, to, offer)
		for kind, n in offer do
			from.saved[kind] -= n
			to.saved[kind] = (to.saved[kind] or 0) + n
			to.firstSaved[kind] = true
			to.variants[kind] = to.variants[kind] or {}
			to.variants[kind].normal = true
		end
	end
	move(da, db, t.offer[t.a])
	move(db, da, t.offer[t.b])
	closeTrade(t, "Обмен завершён!")
	for _, p in { t.a, t.b } do
		ctx.persist(p)
		ctx.pushState(p)
		Social.refreshYard(p)
		Social.clubSync(p)
	end
end

local function tradeAction(plr, action, arg, n)
	local d = ctx.data[plr]
	if not d then return { ok = false } end
	if action == "request" then
		local target = typeof(arg) == "number" and Players:GetPlayerByUserId(arg)
		if not target or target == plr or not ctx.data[target] then return { ok = false, msg = "Игрок не найден" } end
		if tradeOf[plr] or tradeOf[target] then return { ok = false, msg = "Кто-то из вас уже обменивается" } end
		requests[target] = { from = plr, at = os.clock() }
		R.TradeEv:FireClient(target, { type = "request", from = plr.DisplayName, fromId = plr.UserId })
		return { ok = true, msg = "Запрос отправлен игроку " .. target.DisplayName }
	elseif action == "respond" then
		local rq = requests[plr]
		requests[plr] = nil
		if not rq or os.clock() - rq.at > 30 or not rq.from.Parent then return { ok = false, msg = "Запрос устарел" } end
		if arg ~= true then
			ctx.NoticeEv:FireClient(rq.from, plr.DisplayName .. " отказался от обмена")
			return { ok = true }
		end
		if tradeOf[plr] or tradeOf[rq.from] then return { ok = false, msg = "Кто-то из вас уже обменивается" } end
		nextTradeId += 1
		local t = { id = nextTradeId, a = rq.from, b = plr, offer = { [rq.from] = {}, [plr] = {} }, ready = {} }
		trades[t.id] = t
		tradeOf[plr], tradeOf[rq.from] = t.id, t.id
		pushTrade(t)
		return { ok = true }
	end
	local t = tradeOf[plr] and trades[tradeOf[plr]]
	if not t then return { ok = false, msg = "Нет активного обмена" } end
	if action == "cancel" then
		closeTrade(t, plr.DisplayName .. " отменил обмен")
		return { ok = true }
	elseif action == "add" or action == "remove" then
		if t.counting then return { ok = false } end
		local kind = typeof(arg) == "string" and ctx.Catalog.Kinds[arg] and arg
		if not kind then return { ok = false } end
		local o = t.offer[plr]
		local cur = o[kind] or 0
		local want = action == "add" and cur + 1 or cur - 1
		if want < 0 then return { ok = false } end
		if want > 0 and not canGive(d, kind, want) then return { ok = false, msg = "Это последний дух этого вида" } end
		if want > 0 and cur == 0 and offerCount(o) >= 4 then return { ok = false, msg = "Не больше 4 видов за обмен" } end
		o[kind] = want > 0 and want or nil
		t.ready = {}
		pushTrade(t)
		return { ok = true }
	elseif action == "ready" then
		t.ready[plr] = arg == true
		pushTrade(t)
		if t.ready[t.a] and t.ready[t.b] and not t.counting then
			t.counting = true
			pushTrade(t)
			task.delay(3, function()
				if trades[t.id] == t and t.ready[t.a] and t.ready[t.b] then
					finishTrade(t)
				elseif trades[t.id] == t then
					t.counting = false
					pushTrade(t)
				end
			end)
		end
		return { ok = true }
	end
	return { ok = false }
end

------------------------------------------------------------------ клубы ловцов
-- клуб хранится в DataStore по коду; общая коллекция = все виды, которые сдали участники.
-- Бонус клуба: удача +1% за каждый вид общей коллекции.
local CLUB_COST, CLUB_MAX = 500, 20
local clubStore
pcall(function() clubStore = DataStoreService:GetDataStore("SC_Clubs") end)
local clubs = {} -- [code] = record (кэш)
local memClubs = {} -- если DataStore недоступен (тест), клубы живут в памяти сервера
local CODE_CHARS = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

local function loadClub(code: string)
	if clubs[code] then return clubs[code] end
	local rec = memClubs[code]
	if clubStore then
		local ok, res = pcall(function() return clubStore:GetAsync("c_" .. code) end)
		if ok and typeof(res) == "table" then rec = res end
	end
	clubs[code] = rec
	return rec
end
local function saveClub(code: string, mutate)
	local result
	if clubStore then
		local ok = pcall(function()
			clubStore:UpdateAsync("c_" .. code, function(old)
				if typeof(old) ~= "table" and not mutate.create then return nil end
				local rec = typeof(old) == "table" and old or mutate.create
				if mutate.fn(rec) == false then return nil end
				result = rec
				return rec
			end)
		end)
		if not ok then result = nil end
	end
	if not result then
		-- без DataStore (или при сбое) — память сервера
		local rec = memClubs[code] or mutate.create
		if not rec or mutate.fn(rec) == false then return nil end
		memClubs[code] = rec
		result = rec
	end
	clubs[code] = result
	return result
end
local function clubCount(rec)
	local n, k = 0, 0
	for _ in rec.members or {} do n += 1 end
	for _ in rec.kinds or {} do k += 1 end
	return n, k
end
function Social.clubLuck(d): number
	local rec = d.club and clubs[d.club]
	if not rec then return 0 end
	local _, k = clubCount(rec)
	return k * 0.01
end
local function clubView(d)
	local rec = d.club and clubs[d.club]
	if not rec then return nil end
	local members = {}
	for _, name in rec.members do table.insert(members, name) end
	table.sort(members)
	local n, k = clubCount(rec)
	return { name = rec.name, code = d.club, members = members, count = n, kinds = rec.kinds, distinct = k, total = rec.total or 0, luck = k }
end
Social.clubView = clubView
-- добавить свои виды в общую коллекцию клуба
function Social.clubSync(plr)
	local d = ctx.data[plr]
	if not (d and d.club) then return end
	local rec = clubs[d.club]
	local missing = false
	for kind, n in d.saved do
		if n > 0 and not (rec and rec.kinds and rec.kinds[kind]) then missing = true end
	end
	if not missing then return end
	task.spawn(function()
		saveClub(d.club, { fn = function(r)
			r.kinds = r.kinds or {}
			for kind, n in d.saved do
				if n > 0 then r.kinds[kind] = true end
			end
		end })
		for _, p in Players:GetPlayers() do
			local pd = ctx.data[p]
			if pd and pd.club == d.club then ctx.pushState(p) end
		end
	end)
end
function Social.clubCatch(plr)
	local d = ctx.data[plr]
	if not (d and d.club) then return end
	local rec = clubs[d.club]
	if rec then rec.total = (rec.total or 0) + 1 end
	d._clubPending = (d._clubPending or 0) + 1
end
local function filterName(text: string, uid: number): string?
	local ok, res = pcall(function()
		local r = game:GetService("TextService"):FilterStringAsync(text, uid)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if ok and typeof(res) == "string" and not string.find(res, "#") then return res end
	return nil
end
local function clubAction(plr, action, arg)
	local d = ctx.data[plr]
	if not d then return { ok = false } end
	if action == "create" then
		if d.club then return { ok = false, msg = "Сначала выйди из клуба" } end
		if d.coins < CLUB_COST then return { ok = false, msg = ("Нужно %d монет"):format(CLUB_COST) } end
		local raw = typeof(arg) == "string" and arg or ""
		if utf8.len(raw) == nil then return { ok = false, msg = "Название от 3 до 20 букв" } end
		if utf8.len(raw) > 20 then raw = string.sub(raw, 1, utf8.offset(raw, 21) - 1) end
		raw = string.gsub(raw, "^%s+", "")
		raw = string.gsub(raw, "%s+$", "")
		if utf8.len(raw) == nil or utf8.len(raw) < 3 then return { ok = false, msg = "Название от 3 до 20 букв" } end
		local code = ""
		for _ = 1, 5 do
			local i = math.random(#CODE_CHARS)
			code ..= string.sub(CODE_CHARS, i, i)
		end
		local name = filterName(raw, plr.UserId) or ("Клуб " .. code)
		local rec = saveClub(code, { create = { name = name, owner = plr.UserId, members = {}, kinds = {}, total = 0 }, fn = function(r)
			r.members[tostring(plr.UserId)] = plr.DisplayName
		end })
		if not rec then return { ok = false, msg = "Не удалось создать клуб, попробуй позже" } end
		d.coins -= CLUB_COST
		d.club = code
		Social.clubSync(plr)
		ctx.persist(plr)
		ctx.pushState(plr)
		return { ok = true, msg = "Клуб создан! Код для друзей: " .. code }
	elseif action == "join" then
		if d.club then return { ok = false, msg = "Сначала выйди из клуба" } end
		local code = typeof(arg) == "string" and string.upper(string.gsub(arg, "%s", "")) or ""
		if #code ~= 5 then return { ok = false, msg = "Код клуба: 5 символов" } end
		local found = loadClub(code)
		if not found then return { ok = false, msg = "Клуб не найден" } end
		local full = false
		local rec = saveClub(code, { fn = function(r)
			local n = clubCount(r)
			if n >= CLUB_MAX and not r.members[tostring(plr.UserId)] then
				full = true
				return false
			end
			r.members[tostring(plr.UserId)] = plr.DisplayName
		end })
		if full then return { ok = false, msg = "В клубе нет мест" } end
		if not rec then return { ok = false, msg = "Не удалось вступить, попробуй позже" } end
		d.club = code
		Social.clubSync(plr)
		ctx.persist(plr)
		ctx.pushState(plr)
		return { ok = true, msg = "Ты вступил в клуб «" .. rec.name .. "»" }
	elseif action == "leave" then
		if not d.club then return { ok = false } end
		local code = d.club
		d.club = nil
		task.spawn(saveClub, code, { fn = function(r) r.members[tostring(plr.UserId)] = nil end })
		ctx.persist(plr)
		ctx.pushState(plr)
		return { ok = true, msg = "Ты вышел из клуба" }
	end
	return { ok = false }
end

------------------------------------------------------------------ войны клубов: недельный рейтинг клубов
local clubWeekStores = {}
memWeek = {}
function Social.clubWeekStore(week: number)
	if not clubWeekStores[week] then
		pcall(function() clubWeekStores[week] = DataStoreService:GetOrderedDataStore("SC_ClubWeek_" .. week) end)
	end
	return clubWeekStores[week]
end
local function clubTop(week: number, n: number)
	local out = {}
	local st = Social.clubWeekStore(week)
	local ok, pages = false, nil
	if st then ok, pages = pcall(function() return st:GetSortedAsync(false, n) end) end
	if ok and pages then
		for _, e in pages:GetCurrentPage() do table.insert(out, { code = e.key, value = e.value }) end
	elseif week == ctx.Catalog.Live.week(os.time()) then
		for code, v in memWeek do table.insert(out, { code = code, value = v }) end
		table.sort(out, function(a, b) return a.value > b.value end)
	end
	for _, e in out do
		local rec = loadClub(e.code)
		e.name = rec and rec.name or e.code
	end
	return out
end
-- награда за прошлую неделю: проверяется при входе игрока
local function checkClubWar(plr)
	local d = ctx.data[plr]
	local week = ctx.Catalog.Live.week(os.time())
	if not (d and d.club) or (d.clubWarChecked or 0) >= week then return end
	d.clubWarChecked = week
	local top = clubTop(week - 1, 3)
	for rank, e in top do
		if e.code == d.club then
			local pz = ctx.Catalog.Live.ClubWar.prizes[rank]
			d.coins += pz.coins
			d.dust += pz.dust
			if pz.title then
				d.titles[pz.title] = true
			end
			ctx.NoticeEv:FireClient(plr, ("Войны клубов: твой клуб занял %d место за прошлую неделю! +%d монет, +%d пыли"):format(rank, pz.coins, pz.dust))
			ctx.pushState(plr)
		end
	end
end

------------------------------------------------------------------ забеги спутников (показываются в окне, без постройки трассы)
local race = { phase = "idle", entrants = {} }
local function raceView()
	local list = {}
	for _, e in race.entrants do
		table.insert(list, { name = e.name, kind = e.kind, pos = e.pos, place = e.place, me = e.uid })
	end
	return { phase = race.phase, list = list, lobbyLeft = race.lobbyEnd and math.max(0, math.ceil(race.lobbyEnd - os.clock())) or 0, length = ctx.Catalog.Live.Race.length }
end
local function raceBroadcast()
	local v = raceView()
	for _, e in race.entrants do
		if e.plr and e.plr.Parent then R.RaceEv:FireClient(e.plr, v) end
	end
end
local function runRace()
	local RC = ctx.Catalog.Live.Race
	-- соперники-духи, если людей меньше 4
	local i = 1
	while #race.entrants < 4 and RC.rivals[i] do
		local rv = RC.rivals[i]
		table.insert(race.entrants, { name = rv.name, kind = rv.kind, speed = rv.speed, pos = 0, boost = 0 })
		i += 1
	end
	race.phase = "run"
	local finished = 0
	local t0 = os.clock()
	while finished < #race.entrants and os.clock() - t0 < 45 do
		task.wait(RC.tick)
		for _, e in race.entrants do
			if not e.place then
				e.pos += (e.speed * (0.8 + math.random() * 0.45) + e.boost) * RC.tick * 3
				e.boost = math.max(0, e.boost - RC.cheerBoost * 0.5)
				if e.pos >= RC.length then
					e.pos = RC.length
					finished += 1
					e.place = finished
				end
			end
		end
		raceBroadcast()
	end
	race.phase = "done"
	raceBroadcast()
	-- награды людям по месту
	local day = math.floor(os.time() / 86400)
	for _, e in race.entrants do
		local d = e.plr and ctx.data[e.plr]
		if d then
			if typeof(d.raceDay) ~= "table" or d.raceDay.day ~= day then d.raceDay = { day = day, n = 0 } end
			if d.raceDay.n < RC.dailyPrizes then
				d.raceDay.n += 1
				local pz = RC.prizes[e.place or 99] or RC.participation
				d.coins += pz.coins
				d.dust += pz.dust or 0
				ctx.NoticeEv:FireClient(e.plr, ("Забег: %s место! +%d монет"):format(e.place and tostring(e.place) or "-", pz.coins))
				ctx.pushState(e.plr)
			else
				ctx.NoticeEv:FireClient(e.plr, "Забег окончен. Награды на сегодня уже получены")
			end
		end
	end
	task.wait(4)
	race = { phase = "idle", entrants = {} }
end
local function raceAction(plr, action)
	local d = ctx.data[plr]
	if not d then return { ok = false } end
	local RC = ctx.Catalog.Live.Race
	if action == "join" then
		if race.phase == "run" or race.phase == "done" then return { ok = false, msg = "Забег уже идёт, подожди следующий" } end
		local c = ctx.compOf(d)
		if not c then return { ok = false, msg = "Сначала выбери спутника в Атласе" } end
		for _, e in race.entrants do
			if e.plr == plr then return { ok = false, msg = "Ты уже записан" } end
		end
		if #race.entrants >= 8 then return { ok = false, msg = "Все дорожки заняты" } end
		table.insert(race.entrants, { plr = plr, uid = plr.UserId, name = plr.DisplayName, kind = c.kind,
			speed = 0, pos = 0, boost = 0 })
		local e = race.entrants[#race.entrants]
		e.speed = ctx.Catalog.Live.raceSpeed(ctx.Catalog.Kinds[c.kind].rarity, c.level, c.evolved)
		if race.phase == "idle" then
			race.phase = "lobby"
			race.lobbyEnd = os.clock() + RC.lobby
			for _, p in Players:GetPlayers() do
				if p ~= plr then ctx.NoticeEv:FireClient(p, plr.DisplayName .. " открыл забег спутников! Окно «Ловцы», вкладка «Забег»") end
			end
			task.delay(RC.lobby, function()
				if race.phase == "lobby" then runRace() end
			end)
		end
		raceBroadcast()
		return { ok = true }
	elseif action == "cheer" then
		if race.phase ~= "run" then return { ok = false } end
		for _, e in race.entrants do
			if e.plr == plr then
				local now = os.clock()
				if now - (e.lastCheer or 0) < RC.cheerEvery then return { ok = false } end
				e.lastCheer = now
				e.boost += RC.cheerBoost
				return { ok = true }
			end
		end
	end
	return { ok = false }
end

------------------------------------------------------------------ подключение
function Social.init(c)
	ctx = c
	buildYards()
	for _, p in plots do
		local i = table.find(plots, p)
		p.prompt.Triggered:Connect(function(liker) onLike(liker, i) end)
	end
	R.Visit.OnServerInvoke = function(plr, uid)
		local root = ctx.rootOf(plr)
		if not root then return { ok = false } end
		local target = typeof(uid) == "number" and Players:GetPlayerByUserId(uid) or plr
		local i = plotOf[target]
		if not i then return { ok = false, msg = "У игрока нет двора" } end
		ctx.stopHold(plr)
		local p = plots[i]
		plr.Character:PivotTo(CFrame.new(p.center + Vector3.new(math.random(-3, 3), 3, -p.back * 20)))
		if target ~= plr then ctx.NoticeEv:FireClient(target, plr.DisplayName .. " пришёл к тебе во двор!") end
		return { ok = true }
	end
	R.Trade.OnServerInvoke = tradeAction
	R.Race.OnServerInvoke = raceAction
	R.ClubTop.OnServerInvoke = function(plr)
		return clubTop(ctx.Catalog.Live.week(os.time()), 10)
	end
	-- переход на сервер друга: только этот же плейс и только к другу
	R.JoinFriend.OnServerInvoke = function(plr, friendId, jobId)
		if typeof(friendId) ~= "number" or typeof(jobId) ~= "string" or #jobId < 10 or #jobId > 64 or jobId == game.JobId then return { ok = false } end
		local ok, isFriend = pcall(function() return plr:IsFriendsWith(friendId) end)
		if not (ok and isFriend) then return { ok = false, msg = "Это не твой друг" } end
		local tpOk, err = pcall(function()
			game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, jobId, plr)
		end)
		if not tpOk then return { ok = false, msg = "Не получилось перейти: " .. tostring(err) } end
		ctx.persist(plr)
		return { ok = true }
	end
	R.Club.OnServerInvoke = clubAction
	-- клубы: обновление кэша и запись накопленных поимок
	task.spawn(function()
		while true do
			task.wait(60)
			local seen = {}
			for _, p in Players:GetPlayers() do
				local d = ctx.data[p]
				if d and d.club and not seen[d.club] then
					seen[d.club] = true
					local pending = 0
					for _, q in Players:GetPlayers() do
						local qd = ctx.data[q]
						if qd and qd.club == d.club then
							pending += qd._clubPending or 0
							qd._clubPending = 0
						end
					end
					clubs[d.club] = nil
					saveClub(d.club, { fn = function(r) r.total = (r.total or 0) + pending end })
					if pending > 0 then
						local code = d.club
						local st = Social.clubWeekStore(ctx.Catalog.Live.week(os.time()))
						if st then pcall(function() st:IncrementAsync(code, pending) end) end
						memWeek[code] = (memWeek[code] or 0) + pending
					end
				end
			end
		end
	end)
end
function Social.playerReady(plr)
	assignPlot(plr)
	local d = ctx.data[plr]
	if d and d.club then
		task.spawn(function()
			if not loadClub(d.club) then d.club = nil end
			checkClubWar(plr)
			ctx.pushState(plr)
		end)
	end
end
function Social.playerLeft(plr)
	freePlot(plr)
	requests[plr] = nil
	local t = tradeOf[plr] and trades[tradeOf[plr]]
	if t then closeTrade(t, plr.DisplayName .. " вышел из игры") end
end

return Social
