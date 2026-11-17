-- Социальные системы: дворы со спутниками (визиты и лайки), безопасный обмен дубликатами, клубы ловцов.
local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local Social = {}
local R = {} -- remotes
local ctx -- данные и функции из Main

-- remotes создаются сразу при загрузке Main, чтобы клиент их нашёл
function Social.remotes(remote)
	R.Visit = remote("VisitYard", "RemoteFunction")
	R.Trade = remote("Trade", "RemoteFunction")
	R.TradeEv = remote("TradeState")
	R.Club = remote("Club", "RemoteFunction")
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
		table.insert(out, kind .. ":" .. best)
	end
	if d.equipped and not table.find(list, d.equipped) then table.insert(out, d.equipped .. ":normal") end
	return table.concat(out, ",")
end

function Social.refreshYard(plr)
	local i = plotOf[plr]
	local d = ctx.data[plr]
	if not (i and d) then return end
	local p = plots[i]
	p.folder:SetAttribute("Kinds", yardKinds(d))
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
