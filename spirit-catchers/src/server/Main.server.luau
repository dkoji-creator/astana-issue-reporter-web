-- Spirit Catchers: сервер. Появление, ловля, потеря и сохранение улова — только здесь.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Catalog = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Catalog"))
local Map = require(script.Parent:WaitForChild("Map"))
local Social = require(script.Parent:WaitForChild("Social"))
local SC = Catalog.Worlds.Scale
local map = Map.build()

local TEST_PLACE_ID = 99980756426085
-- Закрытый тест: редкие духи луны гарантированы (Studio и тестовый плейс)
local IS_TEST = RunService:IsStudio() or game.PlaceId == TEST_PLACE_ID
local FIRST_MOON, NORMAL_TIME, MOON_TIME = 100, 150, 70
local ALTAR_RANGE, SAFE_RADIUS = 16, 26
local ONI_RADIUS, ONI_WARN = 8, 1.6
-- веса появления собираются из Config/Spirits (district → kind → вес)
local WEIGHTS = { normal = {}, moon = {} }
for kind, info in Catalog.Kinds do
	for district, w in info.spawn do
		WEIGHTS.normal[district] = WEIGHTS.normal[district] or {}
		WEIGHTS.moon[district] = WEIGHTS.moon[district] or {}
		if (w.w or 0) > 0 then WEIGHTS.normal[district][kind] = w.w end
		if (w.moon or 0) > 0 then WEIGHTS.moon[district][kind] = w.moon end
	end
end

------------------------------------------------------------------ remotes
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function remote(name, class)
	local r = Instance.new(class or "RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local RevealEv = remote("Reveal")
local CatchHoldEv = remote("CatchHold")
local CatchZoneEv = remote("CatchZone") -- мини-игра: метка духа в зоне луча
Social.remotes(remote)
local updateBoard -- доска рекордов (ниже)
local startRaid -- рейд «Тысяча фонарей» (ниже)
local startBossCmd -- ночной страж (ниже)
local RaidHitEv = remote("RaidHit")
local EquipFn = remote("Equip", "RemoteFunction")
local UpgradeFn = remote("Upgrade", "RemoteFunction")
local TutorialEv = remote("TutorialDone")
local StateEv = remote("State")
local SaveResultEv = remote("SaveResult")
local CaughtEv = remote("Caught")
local HitEv = remote("Hit")
local NoticeEv = remote("Notice")
local SettingsEv = remote("SetSettings")
local MarketplaceService = game:GetService("MarketplaceService")
local Money = Catalog.Money
local DailyFn = remote("ClaimDaily", "RemoteFunction")
local TeleportFn = remote("Teleport", "RemoteFunction")
local RedeemFn = remote("Redeem", "RemoteFunction")
local AdminFn = remote("Admin", "RemoteFunction")
local NewsSeenEv = remote("NewsSeen")
local AnnounceEv = remote("Announce") -- объявления о редкой поимке
local PotionFn = remote("BuyPotion", "RemoteFunction")
local TalentFn = remote("Talent", "RemoteFunction")
local RebirthFn = remote("Rebirth", "RemoteFunction")
local AchFn = remote("ClaimAchievement", "RemoteFunction")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")
-- админка: владелец игры (проверка только на сервере)
local ADMINS = { [8432365972] = true }
local function isAdmin(plr) return ADMINS[plr.UserId] == true or (game.CreatorType == Enum.CreatorType.User and plr.UserId == game.CreatorId) end
local adminFast: { [Player]: boolean } = {}
local SkinFn = remote("Skin", "RemoteFunction")
local MilestoneFn = remote("ClaimMilestone", "RemoteFunction")
local RewardEv = remote("Reward") -- всплывающие награды: { coins, dust, xp, levelUp }
local FeedFn = remote("FeedCompanion", "RemoteFunction")
local SeasonFn = remote("ClaimSeason", "RemoteFunction")
local TitleFn = remote("SetTitle", "RemoteFunction")
local EvolveFn = remote("Evolve", "RemoteFunction")
local CoinShopFn = remote("CoinShop", "RemoteFunction")
local FurnitureFn = remote("BuyFurniture", "RemoteFunction")
local StoryFn = remote("Story", "RemoteFunction")
local StoryOpenEv = remote("StoryOpen")
local BossHitEv = remote("BossHit")
remotes.Parent = ReplicatedStorage

------------------------------------------------------------------ свет
Lighting.ClockTime = 0
Lighting.Brightness = 1
Lighting.ExposureCompensation = -0.3
Lighting.Ambient = Color3.fromRGB(44, 44, 72)
Lighting.OutdoorAmbient = Color3.fromRGB(48, 50, 80)
Lighting.EnvironmentDiffuseScale = 0.3
local cc = Instance.new("ColorCorrectionEffect")
cc.Parent = Lighting
local bloom = Instance.new("BloomEffect")
bloom.Name = "Bloom"
bloom.Intensity, bloom.Size, bloom.Threshold = 0.15, 12, 2
bloom.Parent = Lighting
local atm = Instance.new("Atmosphere")
atm.Density, atm.Haze, atm.Color, atm.Decay = 0.3, 1.1, Color3.fromRGB(80, 90, 150), Color3.fromRGB(40, 30, 80)
atm.Parent = Lighting

------------------------------------------------------------------ профили (версия 4; v2 и v3 переносятся)
local store = nil
pcall(function() store = DataStoreService:GetDataStore("SpiritCatchers_v1") end)

type Profile = {
	version: number, saved: { [string]: number }, firstSaved: { [string]: boolean }, equipped: string?,
	coins: number, dust: number, levels: { [string]: number }, tutorialDone: boolean,
	orders: { any }, settings: { music: number, sfx: number, reduced: boolean, diag: boolean },
	xp: number, level: number, daily: { last: number, streak: number }, skins: { [string]: boolean }, skin: string,
	milestones: { [string]: boolean }, variants: { [string]: { [string]: boolean } }, total: number, loadFailed: boolean?,
}
local data: { [Player]: Profile } = {}
local jars: { [Player]: { string } } = {}
local holds: { [Player]: number } = {}
local inZone: { [Player]: boolean } = {}

local function clampLvl(v)
	return typeof(v) == "number" and math.clamp(math.floor(v), 1, Catalog.MaxLevel) or 1
end
local function num(v, lo, hi, def)
	return typeof(v) == "number" and v == v and math.clamp(v, lo, hi) or def
end

local function distinct(d: Profile)
	local n = 0
	for _, v in d.saved do
		if v > 0 then n += 1 end
	end
	return n
end
local function gardenOpen(d: Profile) return distinct(d) >= Catalog.GardenNeed end
local function stats(d: Profile) return { distinct = distinct(d), level = d.level } end
local function opened(d: Profile)
	local t = {}
	for name in Catalog.Districts do t[name] = Catalog.unlocked(name, stats(d)) end
	return t
end
local function hasPass(d, key) return (d.passes ~= nil and d.passes[key] == true) or (d.owned ~= nil and d.owned[key] == true) end
-- удача игрока и из чего она сложена
------------------------------------------------------------------ спутники, модификатор дня, испытания, сезон
local Live = Catalog.Live
local modOverride: string? = nil
local function dayMod(): string
	return workspace:GetAttribute("DayMod") or ""
end
workspace:SetAttribute("DayMod", Live.modifierOf(Live.day(os.time())).id)
task.spawn(function()
	while true do
		task.wait(30)
		workspace:SetAttribute("DayMod", modOverride or Live.modifierOf(Live.day(os.time())).id)
	end
end)
-- спутник: уровень, способность и её сила
local function compOf(d)
	local kind = d and d.equipped
	if not kind or not Catalog.Kinds[kind] then return nil end
	local lvl = Live.companionLevel(d.saved[kind] or 0, (d.fed and d.fed[kind]) or 0)
	local key, value = Live.abilityValue(kind, Catalog.Kinds[kind].rarity, lvl)
	local evolved = d.evolved ~= nil and d.evolved[kind] == true
	if evolved then value *= Live.EvolvedMult end
	return { kind = kind, level = lvl, ability = key, value = value, text = Live.abilityText(key, value), evolved = evolved }
end
local function compPct(d, key: string): number
	local c = compOf(d)
	return (c and c.ability == key) and c.value / 100 or 0
end
local function ensureChal(d)
	local day = Live.day(os.time())
	if typeof(d.chal) ~= "table" or d.chal.day ~= day then
		d.chal = { day = day, prog = { 0, 0, 0 }, done = { false, false, false }, all = false }
	end
	return d.chal, Live.challengesOf(day)
end
local function ensureSeason(d)
	if typeof(d.season) ~= "table" or d.season.id ~= Live.Season.id then d.season = { id = Live.Season.id, xp = 0, claimed = {} } end
	return d.season
end
local function addSeasonXp(d, n: number)
	ensureSeason(d).xp += n
end
local function chalProgress(plr, d, fn)
	local ch, list = ensureChal(d)
	for i, c in list do
		if not ch.done[i] then
			local add = fn(c)
			if add > 0 then
				ch.prog[i] = math.min(c.need, ch.prog[i] + add)
				if ch.prog[i] >= c.need then
					ch.done[i] = true
					local r = Live.ChallengeReward
					d.coins += r.coins
					d.dust += r.dust
					addSeasonXp(d, r.sxp)
					NoticeEv:FireClient(plr, ("Испытание выполнено! +%d монет, +%d пыли, +%d опыта сезона"):format(r.coins, r.dust, r.sxp))
				end
			end
		end
	end
	if not ch.all and ch.done[1] and ch.done[2] and ch.done[3] then
		ch.all = true
		local r = Live.ChallengeAllBonus
		d.coins += r.coins
		d.dust += r.dust
		addSeasonXp(d, r.sxp)
		NoticeEv:FireClient(plr, ("Все испытания дня! Бонус +%d монет и +%d пыли"):format(r.coins, r.dust))
	end
end
local RARITY_RANK = {}
for i, k in Catalog.RarityOrder do RARITY_RANK[k] = i end
-- рейтинг недели: лучший улов игрока за неделю (очки = редкость x шанс разновидности)
local weekStores = {}
local weekInfo
pcall(function() weekInfo = DataStoreService:GetDataStore("SC_RareWeekInfo") end)
local function weekStore(week: number)
	if not weekStores[week] then
		pcall(function() weekStores[week] = DataStoreService:GetOrderedDataStore("SC_RareWeek_" .. week) end)
	end
	return weekStores[week]
end
local function catchScore(kind: string, variant: string): number
	local v = Catalog.Variants[variant]
	local odds = variant ~= "normal" and math.floor(1 / v.chance + 0.5) or 1
	return (Live.RarityScore[Catalog.Kinds[kind].rarity] or 1) * odds
end
local function weeklyCatch(plr, d, kind: string, variant: string)
	local week = Live.week(os.time())
	local score = catchScore(kind, variant)
	if typeof(d.weekBest) ~= "table" or d.weekBest.week ~= week then d.weekBest = { week = week, score = 0 } end
	if score <= d.weekBest.score then return end
	d.weekBest = { week = week, score = score, k = kind, v = variant }
	if d.loadFailed then return end
	task.spawn(function()
		local st = weekStore(week)
		if st then pcall(function() st:SetAsync("u" .. plr.UserId, score) end) end
		if weekInfo then pcall(function() weekInfo:SetAsync(week .. "_" .. plr.UserId, { k = kind, v = variant }) end) end
	end)
end
-- сюжет Хранителя: прогресс текущей главы
local function storyEvent(plr, d, typ: string, info)
	if typeof(d.story) ~= "table" then d.story = { ch = 1, prog = 0 } end
	local ch = Live.Story[d.story.ch]
	if not ch or ch.type ~= typ or d.story.prog >= ch.need then return end
	info = info or {}
	if typ == "kind" and info.kind ~= ch.kind then return end
	if typ == "district" and info.district ~= ch.district then return end
	if typ == "rarity" and RARITY_RANK[info.rarity] < RARITY_RANK[ch.min] then return end
	if typ == "variant" and info.variant == "normal" then return end
	d.story.prog = math.min(ch.need, d.story.prog + 1)
	if d.story.prog >= ch.need then
		NoticeEv:FireClient(plr, ("Глава «%s» выполнена! Поговори с Хранителем у алтаря"):format(ch.title))
	end
end
local function liveOnCatch(plr, d, kind: string, district: string, variant: string)
	local rar = Catalog.Kinds[kind].rarity
	weeklyCatch(plr, d, kind, variant)
	Social.clubCatch(plr)
	local sinfo = { kind = kind, district = district, rarity = rar, variant = variant }
	for _, typ in { "kind", "district", "rarity", "variant" } do storyEvent(plr, d, typ, sinfo) end
	-- альбом редких поимок
	local vOdds = variant ~= "normal" and math.floor(1 / Catalog.Variants[variant].chance + 0.5) or 1
	if RARITY_RANK[rar] >= RARITY_RANK[Live.AlbumMinRarity] or vOdds >= Live.AlbumMinOdds then
		d.album = d.album or {}
		table.insert(d.album, 1, { k = kind, v = variant, t = os.time(), d = district })
		while #d.album > Live.AlbumMax do table.remove(d.album) end
	end
	addSeasonXp(d, Live.Season.catchXp[rar] or 4)
	chalProgress(plr, d, function(c)
		if c.type == "catch" then return 1 end
		if c.type == "rarity" and RARITY_RANK[rar] >= RARITY_RANK[c.min] then return 1 end
		if c.type == "district" and c.district == district then return 1 end
		if c.type == "variant" and variant ~= "normal" then return 1 end
		return 0
	end)
end

local function luckOf(d)
	local L = Catalog.Luck
	local parts = {}
	local mult = 1 + math.min(L.levelCap, (d.level - 1) * L.perLevel)
	if d.level > 1 then table.insert(parts, ("Уровень +%d%%"):format(math.floor((mult - 1) * 100 + 0.5))) end
	local fortune = d.talents and d.talents.fortune or 0
	if fortune > 0 then
		mult *= 1 + 0.05 * fortune
		table.insert(parts, ("Фортуна +%d%%"):format(fortune * 5))
	end
	if (d.rebirths or 0) > 0 then
		mult *= 1 + Catalog.Progress.Rebirth.luck * d.rebirths
		table.insert(parts, ("Перерождения +%d%%"):format(math.floor(Catalog.Progress.Rebirth.luck * d.rebirths * 100 + 0.5)))
	end
	if hasPass(d, "lucky") then
		mult *= L.pass
		table.insert(parts, ("Удача ловца x%.1f"):format(L.pass))
	end
	if (d.luckUntil or 0) > os.time() then
		mult *= L.potion
		table.insert(parts, ("Зелье x%d"):format(L.potion))
	end
	if workspace:GetAttribute("FogActive") then
		mult *= 1.25
		table.insert(parts, "Туманная ночь x1.25")
	end
	if workspace:GetAttribute("MoonActive") then
		mult *= L.moon
		table.insert(parts, ("Красная луна x%.1f"):format(L.moon))
	end
	local shrine = (d.shrine or 0) * Live.CoinShop.shrinePer
	if shrine > 0 then
		mult *= 1 + shrine
		table.insert(parts, ("Святилище +%d%%"):format(math.floor(shrine * 100 + 0.5)))
	end
	local club = Social.clubLuck(d)
	if club > 0 then
		mult *= 1 + club
		table.insert(parts, ("Клуб +%d%%"):format(math.floor(club * 100 + 0.5)))
	end
	local cl = compPct(d, "luck")
	if cl > 0 then
		mult *= 1 + cl
		table.insert(parts, ("Спутник +%d%%"):format(math.floor(cl * 100 + 0.5)))
	end
	if dayMod() == "lucky" then
		mult *= 1.3
		table.insert(parts, "Счастливый день x1.3")
	elseif dayMod() == "tracksOnly" then
		mult *= 1.5
		table.insert(parts, "Только следы x1.5")
	end
	return mult, parts
end
local function talentPoints(d)
	local spent = 0
	for _, v in d.talents do spent += v end
	return math.max(0, (d.level - 1) - spent)
end
local function applySpeed(plr)
	local d = data[plr]
	local h = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if d and h then
		local c = compOf(d)
		h.WalkSpeed = 16 + (d.talents.swift or 0) + ((c and c.ability == "speed") and c.value or 0)
	end
end
local function cap(d: Profile) return Catalog.upgradeValue("jar", d.levels.jar) + (hasPass(d, "bigjar") and Money.BigJarBonus or 0) end
local function power(d: Profile) return Catalog.upgradeValue("power", d.levels.power) end
local function range(d: Profile) return Catalog.upgradeValue("range", d.levels.range) end

------------------------------------------------------------------ заказы алтаря
local function onlyGarden(kind)
	for district in Catalog.Kinds[kind].spawn do
		if district ~= "garden" then return false end
	end
	return next(Catalog.Kinds[kind].spawn) ~= nil
end

local function newOrder(d: Profile, avoid: string?)
	local pool = {}
	for _, kind in Catalog.Order do
		local info = Catalog.Kinds[kind]
		if not info.moonOnly and kind ~= avoid and (gardenOpen(d) or not onlyGarden(kind)) then
			table.insert(pool, kind)
		end
	end
	if math.random() < 0.6 and #pool > 0 then
		local kind = pool[math.random(#pool)]
		local rar = Catalog.Rarity[Catalog.Kinds[kind].rarity]
		local need = Catalog.Kinds[kind].rarity == "common" and 2 or 1
		return { type = "kind", kind = kind, need = need, have = 0, coins = rar.coins * need * 3 + 15, dust = rar.dust }
	end
	local rarity = math.random() < 0.65 and "common" or "uncommon"
	local need = rarity == "common" and math.random(3, 4) or 2
	local rar = Catalog.Rarity[rarity]
	return { type = "rarity", rarity = rarity, need = need, have = 0, coins = rar.coins * need * 2 + 10, dust = rar.dust * 2 }
end

local function fillOrders(d: Profile)
	local valid = {}
	for _, o in d.orders do
		if typeof(o) == "table" and (o.type == "kind" and Catalog.Kinds[o.kind] or o.type == "rarity" and Catalog.Rarity[o.rarity]) then
			table.insert(valid, o)
		end
	end
	d.orders = valid
	while #d.orders < Catalog.OrderSlots do
		table.insert(d.orders, newOrder(d, d.orders[1] and d.orders[1].kind))
	end
end

local function migrate(raw): Profile
	local d: Profile = {
		version = 7, saved = {}, firstSaved = {}, equipped = nil, coins = 0, dust = 0, fed = {}, titles = {}, album = {}, yardLikes = 0, evolved = {}, furniture = {}, story = { ch = 1, prog = 0 },
		levels = { jar = 1, range = 1, power = 1 }, tutorialDone = false, orders = {},
		settings = { music = 0.6, sfx = 0.8, reduced = false, diag = false },
		xp = 0, level = 1, daily = { last = 0, streak = 0 }, skins = { classic = true }, skin = "classic", milestones = {},
		variants = {}, total = 0, owned = {}, codes = {}, newsSeen = 0, luckUntil = 0,
		talents = { swift = 0, sense = 0, grip = 0, fortune = 0, greed = 0, stealth = 0, collector = 0 }, rebirths = 0, ach = {},
	}
	if typeof(raw) == "table" then
		-- v2+: коллекция
		if typeof(raw.saved) == "table" then
			for k, v in raw.saved do
				if Catalog.Kinds[k] and typeof(v) == "number" and v > 0 then
					d.saved[k] = math.floor(v)
					d.firstSaved[k] = true
				end
			end
		end
		if typeof(raw.firstSaved) == "table" then
			for k, v in raw.firstSaved do
				if Catalog.Kinds[k] and v == true then d.firstSaved[k] = true end
			end
		end
		if typeof(raw.equipped) == "string" and (d.saved[raw.equipped] or 0) > 0 then d.equipped = raw.equipped end
		if raw.version == 3 then
			-- материал → пыль духов; фонарь v3 → ширина луча и сила света; стартовые монеты за коллекцию
			d.dust = math.floor(num(raw.materials, 0, 1e9, 0))
			d.levels.range = clampLvl(raw.lanternLvl)
			d.levels.power = clampLvl(raw.lanternLvl)
			d.levels.jar = clampLvl(raw.jarLvl)
			d.tutorialDone = raw.tutorialDone == true
			d.coins = 20 * distinct(d)
		elseif raw.version == 4 or raw.version == 5 or raw.version == 6 or raw.version == 7 then
			d.coins = math.floor(num(raw.coins, 0, 1e9, 0))
			d.dust = math.floor(num(raw.dust, 0, 1e9, 0))
			if typeof(raw.levels) == "table" then
				for _, k in Catalog.UpgradeOrder do d.levels[k] = clampLvl(raw.levels[k]) end
			end
			d.tutorialDone = raw.tutorialDone == true
			if typeof(raw.orders) == "table" then d.orders = raw.orders end
			if typeof(raw.settings) == "table" then
				d.settings.music = num(raw.settings.music, 0, 1, 0.6)
				d.settings.sfx = num(raw.settings.sfx, 0, 1, 0.8)
				d.settings.reduced = raw.settings.reduced == true
				d.settings.diag = raw.settings.diag == true
			end
			if raw.version == 5 or raw.version == 6 or raw.version == 7 then
				if typeof(raw.ach) == "table" then
					for k, v in raw.ach do
						if Catalog.Progress.Achievements[k] and v == true then d.ach[k] = true end
					end
				end
				d.xp = math.floor(num(raw.xp, 0, 1e9, 0))
				d.total = math.floor(num(raw.total, 0, 1e9, 0))
				if typeof(raw.codes) == "table" then
					for k, v in raw.codes do
						if typeof(k) == "string" and v == true then d.codes[k] = true end
					end
				end
				d.newsSeen = math.floor(num(raw.newsSeen, 0, 1000, 0))
				d.luckUntil = math.floor(num(raw.luckUntil, 0, 1e12, 0))
				d.rebirths = math.floor(num(raw.rebirths, 0, 1000, 0))
				if typeof(raw.talents) == "table" then
					for k in d.talents do d.talents[k] = math.floor(num(raw.talents[k], 0, Catalog.Progress.TalentMax, 0)) end
				end
				if typeof(raw.owned) == "table" then
					for k, v in raw.owned do
						if Catalog.Money.Passes[k] and v == true then d.owned[k] = true end
					end
				end
				if typeof(raw.receipts) == "table" then
					d.receipts = {}
					for _, r in raw.receipts do
						if typeof(r) == "string" and #d.receipts < 50 then table.insert(d.receipts, r) end
					end
				end
				if typeof(raw.variants) == "table" then
					for k, vs in raw.variants do
						if Catalog.Kinds[k] and typeof(vs) == "table" then
							d.variants[k] = {}
							for v, on in vs do
								if Catalog.Variants[v] and on == true then d.variants[k][v] = true end
							end
						end
					end
				end
				d.level = math.floor(num(raw.level, 1, 999, 1))
				if typeof(raw.daily) == "table" then
					d.daily.last = math.floor(num(raw.daily.last, 0, 1e7, 0))
					d.daily.streak = math.floor(num(raw.daily.streak, 0, 7, 0))
				end
				if typeof(raw.skins) == "table" then
					for k, v in raw.skins do
						if Catalog.Progress.Skins[k] and v == true then d.skins[k] = true end
					end
				end
				if typeof(raw.skin) == "string" and d.skins[raw.skin] then d.skin = raw.skin end
				if typeof(raw.milestones) == "table" then
					for k, v in raw.milestones do
						if typeof(k) == "string" and v == true then d.milestones[k] = true end
					end
				end
			end
		elseif typeof(raw.saved) == "table" and next(d.saved) then
			d.coins = 20 * distinct(d) -- v2
		end
	end
	if typeof(raw) == "table" and raw.version == 7 then
		-- v7: спутники, испытания, сезон, титулы
		if typeof(raw.fed) == "table" then
			for k, v in raw.fed do
				if Catalog.Kinds[k] then d.fed[k] = math.floor(num(v, 0, Live.CompanionMax, 0)) end
			end
		end
		local c = raw.chal
		if typeof(c) == "table" and typeof(c.day) == "number" and typeof(c.prog) == "table" and typeof(c.done) == "table" then
			d.chal = { day = c.day, prog = {}, done = {}, all = c.all == true }
			for i = 1, 3 do
				d.chal.prog[i] = math.floor(num(c.prog[i], 0, 1e6, 0))
				d.chal.done[i] = c.done[i] == true
			end
		end
		local se = raw.season
		if typeof(se) == "table" and se.id == Live.Season.id then
			d.season = { id = se.id, xp = math.floor(num(se.xp, 0, 1e9, 0)), claimed = {} }
			if typeof(se.claimed) == "table" then
				for k, v in se.claimed do
					if v == true then d.season.claimed[tostring(k)] = true end
				end
			end
		end
		if typeof(raw.titles) == "table" then
			for k, v in raw.titles do
				if typeof(k) == "string" and v == true then d.titles[k] = true end
			end
		end
		if typeof(raw.title) == "string" and d.titles[raw.title] then d.title = raw.title end
		if typeof(raw.album) == "table" then
			for _, e in raw.album do
				if typeof(e) == "table" and Catalog.Kinds[e.k] and Catalog.Variants[e.v] and #d.album < Live.AlbumMax then
					table.insert(d.album, { k = e.k, v = e.v, t = math.floor(num(e.t, 0, 1e12, 0)), d = Catalog.Districts[e.d] and e.d or "street" })
				end
			end
		end
		if typeof(raw.club) == "string" and #raw.club == 5 then d.club = raw.club end
		d.clubWarChecked = math.floor(num(raw.clubWarChecked, 0, 1e7, 0))
		d.shrine = math.floor(num(raw.shrine, 0, Live.CoinShop.shrineMax, 0))
		if typeof(raw.raceDay) == "table" then d.raceDay = { day = math.floor(num(raw.raceDay.day, 0, 1e7, 0)), n = math.floor(num(raw.raceDay.n, 0, 1000, 0)) } end
		if typeof(raw.story) == "table" then
			d.story = { ch = math.floor(num(raw.story.ch, 1, #Live.Story + 1, 1)), prog = math.floor(num(raw.story.prog, 0, 1e6, 0)) }
		end
		for _, f in { "evolved", "furniture" } do
			if typeof(raw[f]) == "table" then
				for k, v in raw[f] do
					if v == true and (f == "evolved" and Catalog.Kinds[k] or f == "furniture" and Live.Furniture[k]) then d[f][k] = true end
				end
			end
		end
		d.yardLikes = math.floor(num(raw.yardLikes, 0, 1e9, 0))
		if typeof(raw.likes) == "table" and typeof(raw.likes.day) == "number" and typeof(raw.likes.given) == "table" then
			d.likes = { day = raw.likes.day, given = {} }
			for k, v in raw.likes.given do
				if typeof(k) == "string" and v == true then d.likes.given[k] = true end
			end
		end
		if typeof(raw.weekBest) == "table" and typeof(raw.weekBest.week) == "number" and typeof(raw.weekBest.score) == "number" then
			d.weekBest = { week = raw.weekBest.week, score = raw.weekBest.score, k = raw.weekBest.k, v = raw.weekBest.v }
		end
	end
	fillOrders(d)
	return d
end

local function persist(plr)
	local d = data[plr]
	if not (store and d) or d.loadFailed then return false end
	local copy = table.clone(d)
	copy.loadFailed = nil
	copy._clubPending = nil
	copy.passes = nil
	local ok, err = pcall(function() store:SetAsync("u" .. plr.UserId, copy) end)
	if not ok then warn("DataStore save failed:", err) end
	return ok
end

local function today() return math.floor(os.time() / 86400) end
local function dailyReady(d: Profile) return d.daily.last < today() end

-- прогресс достижения
local function achProgress(d, a)
	if a.type == "total" then return d.total or 0 end
	if a.type == "distinct" then return distinct(d) end
	if a.type == "level" then return d.level end
	if a.type == "rebirths" then return d.rebirths or 0 end
	if a.type == "evolved" then
		local n = 0
		for _ in d.evolved or {} do n += 1 end
		return n
	end
	if a.type == "variant" then
		for _, vs in d.variants do
			if vs[a.key] then return 1 end
		end
		return 0
	end
	if a.type == "rarity" then
		for kind, n in d.saved do
			if n > 0 and Catalog.Kinds[kind] and Catalog.Kinds[kind].rarity == a.key then return 1 end
		end
		return 0
	end
	return 0
end

-- ранг ловца над головой
local function updateRankTag(plr, d)
	local head = plr.Character and plr.Character:FindFirstChild("Head")
	if not head then return end
	local tag = head:FindFirstChild("RankTag")
	if not tag then
		tag = Instance.new("BillboardGui")
		tag.Name, tag.Size, tag.StudsOffset, tag.MaxDistance = "RankTag", UDim2.fromOffset(260, 26), Vector3.new(0, 3.6, 0), 90
		local t = Instance.new("TextLabel")
		t.Name, t.Size, t.BackgroundTransparency, t.TextScaled, t.Font = "Text", UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
		t.TextStrokeTransparency = 0.2
		t.Parent = tag
		tag.Parent = head
	end
	local rank = Catalog.Progress.rankOf(d.level)
	tag.Text.Text = ((d.rebirths or 0) > 0 and ("★%d "):format(d.rebirths) or "") .. (d.title or rank.name)
	tag.Text.TextColor3 = rank.color
end

local function pushState(plr)
	local d = data[plr]
	if not d then return end
	updateRankTag(plr, d)
	plr:SetAttribute("RangeLvl", d.levels.range)
	plr:SetAttribute("PowerLvl", d.levels.power)
	plr:SetAttribute("GardenOpen", gardenOpen(d))
	plr:SetAttribute("Companion", d.equipped or "")
	plr:SetAttribute("CompanionEvolved", d.equipped ~= nil and d.evolved ~= nil and d.evolved[d.equipped] == true)
	plr:SetAttribute("Skin", d.skin)
	StateEv:FireClient(plr, {
		jar = jars[plr], cap = cap(d), saved = d.saved, equipped = d.equipped, coins = d.coins, dust = d.dust,
		levels = d.levels, tutorialDone = d.tutorialDone, orders = d.orders, settings = d.settings,
		newsSeen = d.newsSeen, isAdmin = isAdmin(plr), adminFast = adminFast[plr] == true,
		luck = (luckOf(d)), luckParts = select(2, luckOf(d)), luckUntil = d.luckUntil or 0,
		talents = d.talents, talentPoints = talentPoints(d), rebirths = d.rebirths or 0,
		rebirthLevel = Catalog.Progress.rebirthLevel(d.rebirths or 0),
		gardenOpen = gardenOpen(d), opened = opened(d), variants = d.variants, total = d.total,
		distinct = distinct(d), persistent = store ~= nil and not d.loadFailed,
		xp = d.xp, level = d.level, xpNext = Catalog.Progress.xpToNext(d.level), daily = d.daily, dailyReady = dailyReady(d),
		achCur = (function()
			local t = {}
			for id, a in Catalog.Progress.Achievements do t[id] = achProgress(d, a) end
			return t
		end)(), achDone = d.ach, rank = Catalog.Progress.rankOf(d.level).name,
		comp = compOf(d), fed = d.fed, dayMod = dayMod(),
		chal = (function()
			local ch, list = ensureChal(d)
			local t = {}
			for i, c in list do t[i] = { text = Live.challengeText(c), need = c.need, have = ch.prog[i], done = ch.done[i] } end
			return { list = t, all = ch.all }
		end)(),
		season = ensureSeason(d), title = d.title, titles = d.titles, album = d.album, weekBest = d.weekBest,
		club = Social.clubView(d), yardLikes = d.yardLikes or 0, evolved = d.evolved, furniture = d.furniture, story = d.story, shrine = d.shrine or 0,
		skins = d.skins, skin = d.skin, milestones = d.milestones, passes = (function()
			local t = {}
			for key in Money.Passes do t[key] = hasPass(d, key) end
			return t
		end)(),
	})
	local ls = plr:FindFirstChild("leaderstats")
	if ls then
		ls["Духи"].Value = distinct(d)
		ls["Уровень"].Value = d.level
		ls["Перерождения"].Value = d.rebirths or 0
	end
end

local function rootOf(plr)
	local c = plr.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	if not h or h.Health <= 0 then return nil end
	return c:FindFirstChild("HumanoidRootPart")
end

------------------------------------------------------------------ спецэффекты фонаря (облик), видны всем
local FX_TEX = {
	sparkles = "rbxasset://textures/particles/sparkles_main.dds",
	fire = "rbxasset://textures/particles/fire_main.dds",
	smoke = "rbxasset://textures/particles/smoke_main.dds",
}
local function seq(colors)
	if #colors == 1 then return ColorSequence.new(colors[1]) end
	local kp = {}
	for i, c in colors do table.insert(kp, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c)) end
	return ColorSequence.new(kp)
end
local function lanternFx(lantern, skin)
	local old = lantern:FindFirstChild("Fx")
	if old then old:Destroy() end
	local f = skin and skin.fx
	if not f then return end
	local folder = Instance.new("Folder")
	folder.Name = "Fx"
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "Glow"
	pe.Texture = FX_TEX[f.tex] or FX_TEX.sparkles
	pe.Color = seq(f.colors)
	pe.LightEmission, pe.Rate = 0.55, f.rate * 0.6
	pe.Lifetime = NumberRange.new(f.life * 0.7, f.life)
	pe.Speed = NumberRange.new(f.speed * 0.5, f.speed)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, f.up, 0)
	pe.Drag = 1
	pe.RotSpeed = NumberRange.new(-90, 90)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, f.size), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new(f.tex == "smoke" and 0.7 or 0.3, 1)
	pe.Parent = lantern
	pe.Parent = folder
	-- шлейф при беге: два крепления сверху и снизу фонаря
	local root = lantern.Parent and lantern.Parent:FindFirstChild("HumanoidRootPart")
	if f.trail and root then
		local a0 = Instance.new("Attachment")
		a0.Name, a0.Position = "FxTrailTop", Vector3.new(0, 0.6, 0.6)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Name, a1.Position = "FxTrailBottom", Vector3.new(0, -1.6, 0.6)
		a1.Parent = root
		local tr = Instance.new("Trail")
		tr.Name = "Trail"
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = seq(f.trail)
		tr.LightEmission = 0.4
		tr.Lifetime = 0.55
		tr.Transparency = NumberSequence.new(0.25, 1)
		tr.WidthScale = NumberSequence.new(1, 0.2)
		tr.FaceCamera = true
		tr.Parent = folder
		a0.Parent, a1.Parent = root, root
		-- старые крепления убираем при смене облика
		for _, ch in root:GetChildren() do
			if (ch.Name == "FxTrailTop" or ch.Name == "FxTrailBottom") and ch ~= a0 and ch ~= a1 then ch:Destroy() end
		end
	elseif root then
		for _, ch in root:GetChildren() do
			if ch.Name == "FxTrailTop" or ch.Name == "FxTrailBottom" then ch:Destroy() end
		end
	end
	if f.aura then
		local aura = Instance.new("PointLight")
		aura.Name, aura.Range, aura.Brightness, aura.Color = "Aura", 10, 0.45, skin.lamp
		aura.Shadows = false
		aura.Parent = folder
	end
	folder.Parent = lantern
end
-- вспышка облика при поимке (золотой, призрачный, драконий, VIP)
local function lanternBurst(plr)
	local d = data[plr]
	local skin = d and Catalog.Progress.Skins[d.skin]
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	local glow = lantern and lantern:FindFirstChild("Fx") and lantern.Fx:FindFirstChild("Glow")
	if skin and skin.fx and skin.fx.burst and glow then glow:Emit(40) end
end

------------------------------------------------------------------ фонарь игрока (виден всем)
local function giveLantern(plr, char)
	local root = char:WaitForChild("HumanoidRootPart", 10)
	if not root then return end
	local p = Instance.new("Part")
	p.Name = "Lantern"
	local skin = Catalog.Progress.Skins[data[plr] and data[plr].skin or "classic"] or Catalog.Progress.Skins.classic
	p.Size, p.Material, p.Color = Vector3.new(0.6, 0.8, 0.6), Enum.Material.Neon, skin.lamp
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CFrame = root.CFrame * CFrame.new(0.9, 0.3, -0.9)
	local w = Instance.new("Weld")
	w.Name, w.Part0, w.Part1, w.C0 = "Weld", root, p, CFrame.new(0.9, 0.3, -0.9)
	w.Parent = p
	local sl = Instance.new("SpotLight")
	sl.Name, sl.Face, sl.Angle, sl.Brightness = "Beam", Enum.NormalId.Front, 40, 3
	sl.Range = data[plr] and range(data[plr]) or 30
	sl.Color = skin.beam
	sl.Parent = p
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 8, 0.8, Color3.fromRGB(255, 220, 160)
	pl.Parent = p
	local att = Instance.new("Attachment")
	att.Name = "BeamAtt"
	att.Parent = p
	-- тёмные крышки сверху и снизу: фонарь читается как бумажный фонарь, а не кубик
	for _, y in { 0.48, -0.48 } do
		local cap = Instance.new("Part")
		cap.Name, cap.Size, cap.Color, cap.Material = "LanternCap", Vector3.new(0.7, 0.16, 0.7), Color3.fromRGB(45, 30, 30), Enum.Material.Wood
		cap.CanCollide, cap.CanQuery, cap.CanTouch, cap.Massless = false, false, false, true
		cap.CFrame = p.CFrame * CFrame.new(0, y, 0)
		local cw = Instance.new("WeldConstraint")
		cw.Part0, cw.Part1 = p, cap
		cw.Parent = cap
		cap.Parent = p
	end
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.75, 0.85, 0.75)
	p.Parent = char
	lanternFx(p, skin)
end

------------------------------------------------------------------ духи
local spiritsFolder = Instance.new("Folder")
spiritsFolder.Name = "Spirits"
spiritsFolder.Parent = workspace

type Spirit = {
	id: number, kind: string, district: string, anchor: Part, revealed: boolean, revealedAt: number,
	born: number, pos: Vector3, dir: Vector3, goal: Vector3, progress: number, tut: boolean,
	variant: string?, lastFlee: number?, fleeing: number?, idleUntil: number?,
}
local live: { [number]: Spirit } = {}
local nextId = 0
local moon = { active = false }

local function rnd(a, b) return a + math.random() * (b - a) end

local function zonePoint(district, near: Vector3?, tut: boolean?, kind: string?)
	if tut then
		return Vector3.new(rnd(-14, 14) * SC, 0.5, rnd(34, 62) * SC)
	end
	local info = kind and Catalog.Kinds[kind]
	-- логова: дух появляется и перебегает между «своими» местами района
	local habs = map.habitats[district]
	if info and info.habitat and habs then
		local pool, nearPool = {}, {}
		for _, tag in info.habitat do
			for _, p in habs[tag] or {} do
				table.insert(pool, p)
				if near and (p - Vector3.new(near.X, 0.5, near.Z)).Magnitude < 35 then table.insert(nearPool, p) end
			end
		end
		local list = #nearPool > 1 and nearPool or pool
		if #list > 0 then
			return list[math.random(#list)] + Vector3.new(rnd(-2, 2), 0, rnd(-2, 2))
		end
	end
	if info and info.spots then
		-- любимые места вида (мосты, пруд)
		local spot = info.spots[math.random(#info.spots)]
		if Catalog.district(spot) == district then
			return spot + Vector3.new(rnd(-6, 6), 0, rnd(-3, 3))
		end
	end
	local zones = Catalog.Districts[district].zones
	local zone = zones[math.random(#zones)]
	if near and #zones > 1 then
		-- остаётся на своём берегу
		for _, z in zones do
			if near.Z >= z.z[1] - 1 and near.Z <= z.z[2] + 1 then zone = z end
		end
	end
	return Vector3.new(rnd(zone.x[1], zone.x[2]), 0.5, rnd(zone.z[1], zone.z[2]))
end

local function lift(kind, p: Vector3)
	return Vector3.new(p.X, 0.5 + Catalog.Kinds[kind].height, p.Z)
end

local function newSpirit(kind, district, tut: boolean?, at: Vector3?, forceVariant: string?)
	nextId += 1
	local info = Catalog.Kinds[kind]
	local a = Instance.new("Part")
	a.Name = "Spirit"
	a.Size, a.Transparency = Vector3.new(1, 1, 1), 1
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	local att = Instance.new("Attachment")
	att.Name = "Att"
	att.Parent = a
	local startPoint = at
	if not startPoint then
		for _ = 1, 10 do
			startPoint = zonePoint(district, nil, tut, kind)
			local near = false
			for _, p in Players:GetPlayers() do
				local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
				if r and (r.Position - startPoint).Magnitude < 35 then near = true end
			end
			if tut or not near then break end
		end
	end
	local start = lift(kind, startPoint)
	local s: Spirit = {
		id = nextId, kind = kind, district = district, anchor = a, revealed = info.move == "swim", revealedAt = os.clock(),
		born = os.clock(), pos = start, dir = Vector3.new(0, 0, -1), goal = lift(kind, zonePoint(district, start, tut, kind)),
		progress = 0, tut = tut == true,
	}
	if info.move == "swim" then
		s.pos = Catalog.Districts[district].swim.center
	end
	a.CFrame = CFrame.new(s.pos)
	a:SetAttribute("SpiritId", s.id)
	a:SetAttribute("Kind", kind)
	a:SetAttribute("Revealed", s.revealed)
	a:SetAttribute("Progress", 0)
	a:SetAttribute("Holders", 0)
	-- разновидность выпадает при появлении: все видят золотого или радужного духа
	local variant = "normal"
	for i = #Catalog.VariantOrder, 2, -1 do
		local key = Catalog.VariantOrder[i]
		local v = Catalog.Variants[key]
		if (not v.moonOnly or moon.active) and math.random() < v.chance * (Catalog.Districts[district].luck or 1) * ((key == "giant" and dayMod() == "giants") and 3 or 1) then
			variant = key
			break
		end
	end
	if tut then variant = "normal" end
	-- редкий гость: сервер предупреждает всех
	local rk = info.rarity
	if not tut and (rk == "legendary" or rk == "mythic" or rk == "secret") then
		for _, p in Players:GetPlayers() do
			NoticeEv:FireClient(p, ("В районе «%s» замечен %s дух!"):format(Catalog.Districts[district].name, Catalog.Rarity[rk].name:lower()))
		end
	end
	if forceVariant and Catalog.Variants[forceVariant] then variant = forceVariant end
	s.variant = variant
	a:SetAttribute("Variant", variant)
	a.Parent = spiritsFolder
	live[s.id] = s
	return s
end

local function stopHold(plr)
	local id = holds[plr]
	holds[plr] = nil
	local s = id and live[id]
	if s then
		local b = s.anchor:FindFirstChild("Beam_" .. plr.UserId)
		if b then b:Destroy() end
	end
end

local function removeSpirit(s: Spirit)
	if live[s.id] ~= s then return end
	for plr, id in holds do
		if id == s.id then stopHold(plr) end
	end
	live[s.id] = nil
	s.anchor:Destroy()
end

local holidayOverride: string? = nil
local function pickKind(district)
	-- праздник: иногда вместо обычного духа приходит лимитированный
	if district ~= "plaza" and district ~= "yard" then
		local hs = Catalog.Live.activeHolidays(os.time())
		if holidayOverride then
			hs = {}
			for _, h in Catalog.Live.Holidays do
				if h.id == holidayOverride then table.insert(hs, h) end
			end
		end
		if #hs > 0 and math.random() < Catalog.Live.HolidayChance then return hs[math.random(#hs)].kind end
	end
	local tbl = WEIGHTS[moon.active and "moon" or "normal"][district]
	if not tbl or next(tbl) == nil then return nil end
	local total = 0
	for _, w in tbl do total += w end
	local r = math.random() * total
	for k, w in tbl do
		r -= w
		if r <= 0 then return k end
	end
	return next(tbl)
end

------------------------------------------------------------------ движение
RunService.Heartbeat:Connect(function(dt)
	local now = os.clock()
	-- группы ловцов: несколько игроков на одном духе ловят быстрее, каждый получает свой экземпляр
	local groups: { [number]: { Player } } = {}
	for plr, id in holds do
		local s = live[id]
		local root = rootOf(plr)
		local d = data[plr]
		if not (s and root and d and jars[plr]) or #jars[plr] >= cap(d)
			or (root.Position - s.pos).Magnitude > Catalog.catchRange(s.kind) + 4 then
			if d and jars[plr] and #jars[plr] >= cap(d) then NoticeEv:FireClient(plr, "Банка полна — отнеси улов к алтарю") end
			stopHold(plr)
		else
			groups[id] = groups[id] or {}
			table.insert(groups[id], plr)
		end
	end

	for id, s in live do
		local info = Catalog.Kinds[s.kind]
		local g = groups[id]
		if info.move == "swim" then
			local sw = Catalog.Districts[s.district].swim
			local a = now * sw.speed
			s.pos = sw.center + Vector3.new(math.cos(a) * sw.rx, 0, math.sin(a) * sw.rz)
			s.dir = Vector3.new(-math.sin(a) * sw.rx, 0, math.cos(a) * sw.rz).Unit
		else
			local speed = info.speed * (s.revealed and 0.55 or 1) * (g and 0.3 or 1)
			if s.revealed and not g and now - (s.lastFlee or 0) > 0.5 then
				s.lastFlee = now
				-- проявленный дух убегает от ближайшего игрока
				for _, p in Players:GetPlayers() do
					local r = rootOf(p)
					if r then
						local away = Vector3.new(s.pos.X - r.Position.X, 0, s.pos.Z - r.Position.Z)
						local stealth = data[p] and data[p].talents.stealth or 0
						if away.Magnitude < 9 - 0.5 * stealth and away.Magnitude > 0.1 then
							local zones = Catalog.Districts[s.district].zones
							local z = zones[1]
							for _, zz in zones do
								if s.pos.Z >= zz.z[1] - 1 and s.pos.Z <= zz.z[2] + 1 then z = zz end
							end
							local target = s.pos + away.Unit * 12
							s.goal = Vector3.new(math.clamp(target.X, z.x[1], z.x[2]), s.pos.Y, math.clamp(target.Z, z.z[1], z.z[2]))
							s.fleeing = now
							break
						end
					end
				end
			end
			if s.fleeing and now - s.fleeing < 1.5 and not g then speed *= 2.2 end
			local to = s.goal - s.pos
			if not s.revealed and s.idleUntil and now < s.idleUntil then
				to = Vector3.zero -- дух затаился и ждёт
			elseif to.Magnitude < 1 then
				s.goal = lift(s.kind, zonePoint(s.district, s.pos, s.tut, s.kind))
				if not s.revealed and not s.tut then s.idleUntil = now + 4 + math.random() * 9 end
			elseif to.Magnitude > 0 then
				s.dir = Vector3.new(to.X, 0, to.Z).Magnitude > 0.05 and Vector3.new(to.X, 0, to.Z).Unit or s.dir
				s.pos += to.Unit * math.min(speed * dt, to.Magnitude)
			end
		end
		s.anchor.CFrame = CFrame.lookAt(s.pos, s.pos + s.dir)

		if g then
			local rate = 0
			for _, p in g do
				rate += adminFast[p] and 50 or (inZone[p] and power(data[p]) * 1.25 or -0.45)
			end
			s.progress = math.max(0, s.progress + dt * rate / Catalog.Rarity[info.rarity].catchTime)
		elseif s.progress > 0 then
			s.progress = math.max(0, s.progress - dt * 0.4)
		end
		local shown = s.anchor:GetAttribute("Progress")
		if math.abs(shown - s.progress) > 0.02 or (s.progress == 0 and shown ~= 0) then
			s.anchor:SetAttribute("Progress", math.min(s.progress, 1))
		end
		local n = g and #g or 0
		if s.anchor:GetAttribute("Holders") ~= n then s.anchor:SetAttribute("Holders", n) end

		if g and s.progress >= 1 then
			for _, plr in g do
				-- бросок удачи: может улучшить разновидность (каждому участнику — свой)
				local base = s.variant or "normal"
				local variant = base
				local luck = luckOf(data[plr]) * (Catalog.Districts[s.district].luck or 1)
				local baseRank = table.find(Catalog.VariantOrder, base) or 1
				for vi = #Catalog.VariantOrder, baseRank + 1, -1 do
					local key = Catalog.VariantOrder[vi]
					local vc = Catalog.Variants[key]
					if (not vc.moonOnly or moon.active) and math.random() < vc.chance * luck then
						variant = key
						break
					end
				end
				local odds = variant ~= "normal" and math.floor(1 / Catalog.Variants[variant].chance + 0.5) or 1
				if odds >= Catalog.Luck.announceLocal then
					AnnounceEv:FireAllClients({ name = plr.DisplayName, kind = s.kind, variant = variant, odds = odds })
				end
				if odds >= Catalog.Luck.announceGlobal then
					task.spawn(function()
						pcall(function()
							MessagingService:PublishAsync("SC_Rare", { name = plr.DisplayName, kind = s.kind, variant = variant, odds = odds, job = game.JobId })
						end)
					end)
				end
				table.insert(jars[plr], { k = s.kind, v = variant })
				CaughtEv:FireClient(plr, s.kind, s.pos, #g, variant, variant ~= base)
				lanternBurst(plr)
				local d = data[plr]
				local xp = math.floor((Catalog.Progress.XP[info.rarity] or 4) * (1 + compPct(d, "xp")) + 0.5)
				d.xp += xp
				liveOnCatch(plr, d, s.kind, s.district, variant)
				local levelUp = nil
				while d.xp >= Catalog.Progress.xpToNext(d.level) do
					d.xp -= Catalog.Progress.xpToNext(d.level)
					d.level += 1
					local bonus = Catalog.Progress.levelReward(d.level)
					d.coins += bonus
					levelUp = { level = d.level, coins = bonus }
					if d.level % Catalog.Progress.ChestEvery == 0 then
						local ch = Catalog.Progress.chest(d.level)
						d.coins += ch.coins
						d.dust += ch.dust
						levelUp.chest = ch
					end
				end
				if levelUp then
					-- столб света над игроком (видят все)
					local rp = rootOf(plr)
					if rp then
						local pillar = Instance.new("Part")
						pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch = true, false, false, false
						pillar.Material, pillar.Color, pillar.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 220, 110), 0.3
						pillar.Shape, pillar.Size = Enum.PartType.Cylinder, Vector3.new(40, 3, 3)
						pillar.CFrame = CFrame.new(rp.Position + Vector3.new(0, 18, 0)) * CFrame.Angles(0, 0, math.rad(90))
						pillar.Parent = workspace
						TweenService:Create(pillar, TweenInfo.new(1.6), { Transparency = 1, Size = Vector3.new(40, 8, 8) }):Play()
						task.delay(1.7, function() pillar:Destroy() end)
					end
				end
				RewardEv:FireClient(plr, { xp = xp, levelUp = levelUp })
				pushState(plr)
			end
			removeSpirit(s)
		end
	end
end)

------------------------------------------------------------------ проявление и удержание
RevealEv.OnServerEvent:Connect(function(plr, id)
	local s = typeof(id) == "number" and live[id]
	local root = rootOf(plr)
	local d = data[plr]
	if not (s and root and d) or s.revealed then return end
	if not Catalog.unlocked(s.district, stats(d)) then return end
	if (root.Position - s.pos).Magnitude > range(d) + 3 then return end
	s.revealed = true
	s.revealedAt = os.clock()
	s.anchor:SetAttribute("Revealed", true)
end)

CatchZoneEv.OnServerEvent:Connect(function(plr, on)
	inZone[plr] = on == true
end)

CatchHoldEv.OnServerEvent:Connect(function(plr, id)
	stopHold(plr)
	inZone[plr] = false
	if typeof(id) ~= "number" then return end
	local s = live[id]
	local root = rootOf(plr)
	local d = data[plr]
	if not (s and root and d and s.revealed) then return end
	if #jars[plr] >= cap(d) then
		NoticeEv:FireClient(plr, "Банка полна — отнеси улов к алтарю")
		return
	end
	if (root.Position - s.pos).Magnitude > Catalog.catchRange(s.kind) + 2 then return end
	holds[plr] = id
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	local att = lantern and lantern:FindFirstChild("BeamAtt")
	if att then
		local b = Instance.new("Beam")
		b.Name = "Beam_" .. plr.UserId
		b.Attachment0, b.Attachment1 = att, s.anchor.Att
		b.Width0, b.Width1, b.LightEmission, b.FaceCamera = 0.4, 1.6, 1, true
		b.Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Catalog.Rarity[Catalog.Kinds[s.kind].rarity].color)
		b.Transparency = NumberSequence.new(0.2, 0.5)
		b.Parent = s.anchor
	end
end)

------------------------------------------------------------------ появление и исчезновение
local function districtCount(d)
	local n, tutN = 0, 0
	for _, s in live do
		if s.district == d then
			n += 1
			if s.tut and not s.revealed then tutN += 1 end
		end
	end
	return n, tutN
end

local lastWhale = 0

task.spawn(function()
	while true do
		local now = os.clock()
		for _, s in live do
			local held = s.anchor:GetAttribute("Holders") > 0
			if not held and not Catalog.Kinds[s.kind].moonOnly and Catalog.Kinds[s.kind].move ~= "swim" then
				if (not s.revealed and now - s.born > 110) or (s.revealed and now - s.revealedAt > 35) then removeSpirit(s) end
			end
		end
		for district, dc in Catalog.Districts do
			local max = dc.max
			local n, tutN = districtCount(district)
			local needTut = false
			for _, p in Players:GetPlayers() do
				if data[p] and not data[p].tutorialDone then needTut = true end
			end
			if district == "street" and needTut and tutN < 2 then
				newSpirit("PaperFox", "street", true) -- рядом с алтарём всегда есть лис для обучения
			elseif max > 0 and n < max + (moon.active and 2 or 0) + ((moon.fog and (district == "canal" or district == "port")) and 3 or 0) then
				local kind = pickKind(district)
				if kind then newSpirit(kind, district) end
			end
		end
		-- бумажный кит иногда проплывает над морем у порта
		if os.clock() - (lastWhale or 0) > 150 then
			lastWhale = os.clock()
			local has = false
			for _, s in live do
				if s.kind == "PaperWhale" then has = true end
			end
			if not has and (IS_TEST or math.random() < 0.3) then
				local w = newSpirit("PaperWhale", "port")
				task.delay(100, function()
					if live[w.id] == w and w.anchor:GetAttribute("Holders") == 0 then removeSpirit(w) end
				end)
			end
		end
		task.wait(1.5)
	end
end)

------------------------------------------------------------------ Красная луна и они
local function tweenLight(red)
	local ti = TweenInfo.new(2.5)
	TweenService:Create(Lighting, ti, red and { Ambient = Color3.fromRGB(70, 52, 66), OutdoorAmbient = Color3.fromRGB(78, 56, 72) }
		or { Ambient = Color3.fromRGB(44, 44, 72), OutdoorAmbient = Color3.fromRGB(48, 50, 80) }):Play()
	TweenService:Create(cc, ti, red and { TintColor = Color3.fromRGB(255, 232, 232), Saturation = 0 } or { TintColor = Color3.new(1, 1, 1), Saturation = 0 }):Play()
	TweenService:Create(atm, ti, { Color = red and Color3.fromRGB(190, 45, 55) or Color3.fromRGB(80, 90, 150), Decay = red and Color3.fromRGB(120, 20, 40) or Color3.fromRGB(40, 30, 80) }):Play()
	TweenService:Create(map.moon, ti, { Transparency = red and 0 or 1 }):Play()
end

local function hitPlayer(plr)
	local lost = jars[plr] and #jars[plr] or 0
	jars[plr] = {}
	stopHold(plr)
	local c = plr.Character
	if c then c:PivotTo(map.spawnCF + Vector3.new(0, 3, 0)) end
	HitEv:FireClient(plr, lost)
	pushState(plr)
end

local oniAnchor: Part? = nil
local oniPos = Vector3.new(0, 0.5, 118 * SC)
local function oniLoop(a: Part)
	local facing = Vector3.new(0, 0, -1)
	local function place() a.CFrame = CFrame.lookAt(oniPos, oniPos + facing) end
	local function walkTo(goal: Vector3, speed, maxT)
		local t0 = os.clock()
		a:SetAttribute("State", "walk")
		while moon.active and a.Parent and os.clock() - t0 < maxT do
			local d = Vector3.new(goal.X, 0.5, goal.Z) - oniPos
			if d.Magnitude < 1.5 then break end
			facing = d.Unit
			oniPos += facing * math.min(speed * 0.05, d.Magnitude)
			place()
			task.wait(0.05)
		end
	end
	while moon.active and a.Parent do
		local target, best = nil, math.huge
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r and (r.Position - map.altarPos).Magnitude > SAFE_RADIUS and r.Position.Z > -72 * SC and r.Position.Z < 240 * SC and r.Position.Y > -2 then
				local d = (r.Position - oniPos).Magnitude - ((jars[plr] and #jars[plr] > 0) and 40 or 0)
				if d < best then target, best = r, d end
			end
		end
		if not target then
			walkTo(Vector3.new(rnd(-12, 12) * SC, 0.5, rnd(40, 120) * SC), 7, 4)
			continue
		end
		-- подходит к игроку
		local tStart = os.clock()
		a:SetAttribute("State", "walk")
		while moon.active and target.Parent and os.clock() - tStart < 3.5 do
			local d = Vector3.new(target.Position.X, 0.5, target.Position.Z) - oniPos
			if d.Magnitude < 10 then break end
			facing = d.Unit
			oniPos += facing * 0.6
			place()
			task.wait(0.05)
		end
		if not (moon.active and target.Parent) then continue end
		local center = Vector3.new(target.Position.X, target.Position.Y - 2.9, target.Position.Z)
		if (center - map.altarPos).Magnitude < SAFE_RADIUS or center.Z < -72 then continue end
		local f = Vector3.new(center.X - oniPos.X, 0, center.Z - oniPos.Z)
		if f.Magnitude > 0.1 then facing = f.Unit end
		place()
		-- круг удара заранее
		a:SetAttribute("State", "windup")
		local ring = Instance.new("Part")
		ring.Name = "OniWarning"
		ring.Shape, ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = Enum.PartType.Cylinder, true, false, false, false
		ring.Material, ring.Color, ring.Transparency = Enum.Material.Neon, Color3.fromRGB(255, 25, 25), 0.3
		ring.Size = Vector3.new(0.15, ONI_RADIUS * 2, ONI_RADIUS * 2)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		ring.Parent = workspace
		-- белая кромка: круг читается и при красном свете луны
		local edge = ring:Clone()
		edge.Name, edge.Color, edge.Transparency = "OniWarningEdge", Color3.new(1, 1, 1), 0.1
		edge.Size = Vector3.new(0.12, ONI_RADIUS * 2 + 0.8, ONI_RADIUS * 2 + 0.8)
		edge.CFrame = ring.CFrame * CFrame.new(-0.02, 0, 0)
		edge.Parent = workspace
		task.delay(ONI_WARN + 0.05, function() edge:Destroy() end)
		local fill = ring:Clone()
		fill.Transparency, fill.Size, fill.Color = 0.2, Vector3.new(0.2, 0.5, 0.5), Color3.fromRGB(255, 140, 60)
		fill.Parent = workspace
		TweenService:Create(fill, TweenInfo.new(ONI_WARN, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, ONI_RADIUS * 2, ONI_RADIUS * 2) }):Play()
		task.wait(ONI_WARN)
		a:SetAttribute("State", "strike")
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			if r then
				local d = r.Position - center
				if Vector3.new(d.X, 0, d.Z).Magnitude <= ONI_RADIUS and math.abs(d.Y) < 8 then hitPlayer(plr) end
			end
		end
		fill:Destroy()
		ring.Color, ring.Transparency = Color3.fromRGB(255, 220, 180), 0.2
		TweenService:Create(ring, TweenInfo.new(0.4), { Transparency = 1, Size = Vector3.new(0.1, ONI_RADIUS * 2.6, ONI_RADIUS * 2.6) }):Play()
		task.delay(0.45, function() ring:Destroy() end)
		task.wait(1.3)
	end
end

local function setPhase(active, secs)
	moon.active = active
	workspace:SetAttribute("MoonActive", active)
	workspace:SetAttribute("PhaseEnds", workspace:GetServerTimeNow() + secs)
end

local phaseEnd = os.clock() + FIRST_MOON
local function startMoon()
	setPhase(true, MOON_TIME)
	tweenLight(true)
	if IS_TEST or math.random() < 0.35 then newSpirit("GoldenCarp", "canal") end
	if IS_TEST or math.random() < 0.5 then newSpirit("MoonRabbit", "street") end
	if IS_TEST or math.random() < 0.5 then newSpirit("FoxFire", "canal") end
	if IS_TEST or math.random() < 0.3 then newSpirit("PaperDragon", "grove") end
	if IS_TEST or math.random() < 0.1 then newSpirit("Kyubi", "garden") end
	if IS_TEST or math.random() < 0.4 then newSpirit("MistKraken", "port") end
	newSpirit("Crane", "garden")
	local a = Instance.new("Part")
	a.Name = "Oni"
	a.Size, a.Transparency = Vector3.new(1, 1, 1), 1
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	oniPos = Vector3.new(0, 0.5, 118 * SC)
	a.CFrame = CFrame.new(oniPos)
	a:SetAttribute("State", "walk")
	a.Parent = workspace
	oniAnchor = a
	task.spawn(oniLoop, a)
end

local function startFog()
	moon.fog = true
	workspace:SetAttribute("FogActive", true)
	workspace:SetAttribute("PhaseEnds", workspace:GetServerTimeNow() + MOON_TIME)
	TweenService:Create(atm, TweenInfo.new(3), { Density = 0.55, Haze = 2.2, Color = Color3.fromRGB(150, 170, 190) }):Play()
	newSpirit("JellyLantern", "port")
	newSpirit("SeaHorse", "port")
	for _, p in Players:GetPlayers() do NoticeEv:FireClient(p, "Туманная ночь! В канале и порту больше духов, удача x1.25") end
end
local function endFog()
	moon.fog = false
	workspace:SetAttribute("FogActive", false)
	setPhase(false, NORMAL_TIME)
	TweenService:Create(atm, TweenInfo.new(3), { Density = 0.3, Haze = 1.1, Color = Color3.fromRGB(80, 90, 150) }):Play()
end

local function endMoon()
	setPhase(false, NORMAL_TIME)
	tweenLight(false)
	if oniAnchor then oniAnchor:Destroy() oniAnchor = nil end
	for _, s in live do
		if Catalog.Kinds[s.kind].moonOnly then removeSpirit(s) end
	end
end

setPhase(false, FIRST_MOON)
task.spawn(function()
	while true do
		task.wait(0.5)
		if os.clock() >= phaseEnd then
			if moon.active then
				endMoon()
				phaseEnd = os.clock() + NORMAL_TIME * (dayMod() == "doubleMoon" and 0.5 or 1)
				workspace:SetAttribute("NextEvent", "fog")
			elseif moon.fog then
				endFog()
				phaseEnd = os.clock() + NORMAL_TIME * (dayMod() == "doubleMoon" and 0.5 or 1)
				workspace:SetAttribute("NextEvent", (dayMod() == "fogDay" and math.random() < 0.5) and "fog" or "moon")
			elseif (workspace:GetAttribute("NextEvent") or "moon") == "moon" then
				startMoon()
				phaseEnd = os.clock() + MOON_TIME
			else
				startFog()
				phaseEnd = os.clock() + MOON_TIME
			end
		end
	end
end)

-- донат «Призвать Красную луну»: начать сейчас или продлить на 30 с
local function summonMoon()
	if moon.fog then endFog() end
	if moon.active then
		phaseEnd += 30
		workspace:SetAttribute("PhaseEnds", (workspace:GetAttribute("PhaseEnds") or workspace:GetServerTimeNow()) + 30)
	else
		startMoon()
		phaseEnd = os.clock() + MOON_TIME
	end
end

------------------------------------------------------------------ алтарь
local savePrompt = Instance.new("ProximityPrompt")
savePrompt.ActionText, savePrompt.ObjectText = "Сохранить улов", "Алтарь"
savePrompt.HoldDuration, savePrompt.MaxActivationDistance = 0.25, ALTAR_RANGE
savePrompt.RequiresLineOfSight = false
savePrompt.Parent = map.altar

local function doSave(plr)
	local root = rootOf(plr)
	local d = data[plr]
	if not (root and d) then return { ok = false, msg = "Нет персонажа" } end
	if (root.Position - map.altarPos).Magnitude > ALTAR_RANGE + 6 then return { ok = false, msg = "Подойди к алтарю" } end
	local jar = jars[plr]
	if #jar == 0 then return { ok = false, msg = "Банка пуста — сначала поймай духа" } end
	local wasOpen = gardenOpen(d)
	local firsts, dust, coins, newVariants = {}, 0, 0, {}
	for _, entry in jar do
		local kind, variant = entry.k, entry.v
		local rar = Catalog.Rarity[Catalog.Kinds[kind].rarity]
		coins += math.floor(rar.coins * Catalog.Variants[variant].mult * ((d.evolved and d.evolved[kind]) and Live.EvolvedMult or 1))
		d.total += 1
		d.variants[kind] = d.variants[kind] or {}
		if not d.variants[kind][variant] then
			d.variants[kind][variant] = true
			if variant ~= "normal" then table.insert(newVariants, { k = kind, v = variant }) end
		end
		if (d.saved[kind] or 0) > 0 then
			dust += rar.dust -- дубликат → пыль духов
		end
		d.saved[kind] = (d.saved[kind] or 0) + 1
		if not d.firstSaved[kind] then
			d.firstSaved[kind] = true
			table.insert(firsts, kind)
		end
		-- заказы
		for _, o in d.orders do
			if o.have < o.need and ((o.type == "kind" and o.kind == kind) or (o.type == "rarity" and o.rarity == Catalog.Kinds[kind].rarity)) then
				o.have += 1
				break
			end
		end
	end
	local done = {}
	for i = #d.orders, 1, -1 do
		local o = d.orders[i]
		if o.have >= o.need then
			coins += o.coins
			dust += o.dust
			table.insert(done, o)
			table.remove(d.orders, i)
		end
	end
	fillOrders(d)
	coins = math.floor(coins * (1 + 0.06 * (d.talents.greed or 0)) * (1 + Catalog.Progress.Rebirth.coins * (d.rebirths or 0)))
	coins = math.floor(coins * (1 + compPct(d, "coins")) * (dayMod() == "goldRush" and 1.5 or 1))
	dust = math.floor(dust * (1 + 0.1 * (d.talents.collector or 0)) * (1 + compPct(d, "dust")) + 0.5)
	chalProgress(plr, d, function(c) return c.type == "deliver" and 1 or 0 end)
	storyEvent(plr, d, "deliver")
	if hasPass(d, "coins2x") then coins *= 2 end
	if hasPass(d, "vip") then coins = math.floor(coins * Money.VipCoinBonus) end
	d.coins += coins
	d.dust += dust
	local kinds = table.clone(jar)
	jars[plr] = {}
	Social.clubSync(plr)
	Social.refreshYard(plr)
	local persisted = persist(plr)
	pushState(plr)
	updateBoard(plr)
	return { ok = true, kinds = kinds, firsts = firsts, coins = coins, dust = dust, orders = done, newVariants = newVariants,
		gardenOpened = not wasOpen and gardenOpen(d), persisted = persisted }
end
savePrompt.Triggered:Connect(function(plr)
	SaveResultEv:FireClient(plr, doSave(plr))
end)

UpgradeFn.OnServerInvoke = function(plr, which)
	local d = data[plr]
	local root = rootOf(plr)
	if not (d and root) then return { ok = false, msg = "Нет персонажа" } end
	local up = typeof(which) == "string" and Catalog.Upgrades[which]
	if not up then return { ok = false } end
	local lvl = d.levels[which]
	if lvl >= Catalog.MaxLevel then return { ok = false, msg = "Максимальный уровень" } end
	local c, du = up.coins[lvl], up.dust[lvl]
	if d.coins < c or d.dust < du then return { ok = false, msg = ("Нужно: %d монет и %d пыли"):format(c, du) } end
	d.coins -= c
	d.dust -= du
	d.levels[which] = lvl + 1
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	if lantern and lantern:FindFirstChild("Beam") then
		lantern.Beam.Range = range(d)
		lantern.Beam.Angle = 36 + d.levels.range * 4
	end
	persist(plr)
	pushState(plr)
	return { ok = true }
end

local function grant(d: Profile, r)
	d.coins += r.coins or 0
	d.dust += r.dust or 0
	if r.skin then d.skins[r.skin] = true end
end

DailyFn.OnServerInvoke = function(plr)
	local d = data[plr]
	if not d then return { ok = false } end
	if not dailyReady(d) then return { ok = false, msg = "Подарок уже получен, приходи завтра" } end
	local streak = (d.daily.last == today() - 1) and (d.daily.streak % #Catalog.Progress.Daily) + 1 or 1
	d.daily = { last = today(), streak = streak }
	local r = Catalog.Progress.Daily[streak]
	grant(d, r)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = r.coins, dust = r.dust, skin = r.skin })
	return { ok = true, day = streak }
end

MilestoneFn.OnServerInvoke = function(plr, i)
	local d = data[plr]
	local m = typeof(i) == "number" and Catalog.Progress.Milestones[i]
	if not (d and m) then return { ok = false } end
	local key = tostring(i)
	if d.milestones[key] then return { ok = false, msg = "Уже получено" } end
	if distinct(d) < m.need then return { ok = false, msg = ("Нужно видов: %d"):format(m.need) } end
	d.milestones[key] = true
	grant(d, m)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = m.coins, dust = m.dust, skin = m.skin })
	return { ok = true }
end

local function applySkin(plr)
	local d = data[plr]
	local lantern = plr.Character and plr.Character:FindFirstChild("Lantern")
	local skin = d and Catalog.Progress.Skins[d.skin]
	if lantern and skin then
		lantern.Color = skin.lamp
		if lantern:FindFirstChild("Beam") then lantern.Beam.Color = skin.beam end
		lanternFx(lantern, skin)
	end
end

SkinFn.OnServerInvoke = function(plr, action, key)
	local d = data[plr]
	local skin = typeof(key) == "string" and Catalog.Progress.Skins[key]
	if not (d and skin) then return { ok = false } end
	if action == "buy" then
		if d.skins[key] then return { ok = false, msg = "Уже куплено" } end
		if not skin.price then return { ok = false, msg = "Получи: " .. (skin.source or "") } end
		local du = skin.dust or 0
		if d.coins < skin.price or d.dust < du then return { ok = false, msg = "Не хватает монет или пыли" } end
		d.coins -= skin.price
		d.dust -= du
		d.skins[key] = true
		d.skin = key
	elseif action == "equip" then
		if not d.skins[key] then return { ok = false, msg = "Облик не открыт" } end
		d.skin = key
	else
		return { ok = false }
	end
	applySkin(plr)
	persist(plr)
	pushState(plr)
	return { ok = true }
end

SettingsEv.OnServerEvent:Connect(function(plr, t)
	local d = data[plr]
	if not (d and typeof(t) == "table") then return end
	d.settings.music = num(t.music, 0, 1, d.settings.music)
	d.settings.sfx = num(t.sfx, 0, 1, d.settings.sfx)
	if typeof(t.reduced) == "boolean" then d.settings.reduced = t.reduced end
	if typeof(t.diag) == "boolean" then d.settings.diag = t.diag end
end)

EquipFn.OnServerInvoke = function(plr, kind)
	local d = data[plr]
	if not d then return false end
	if kind == nil then
		d.equipped = nil
	elseif typeof(kind) == "string" and (d.saved[kind] or 0) > 0 then
		d.equipped = kind
	else
		return false
	end
	applySpeed(plr)
	Social.refreshYard(plr)
	persist(plr)
	pushState(plr)
	return true
end

TutorialEv.OnServerEvent:Connect(function(plr)
	local d = data[plr]
	if d and not d.tutorialDone then
		d.tutorialDone = true
		persist(plr)
		pushState(plr)
	end
end)

------------------------------------------------------------------ сторож: сад и вода
task.spawn(function()
	while true do
		for _, plr in Players:GetPlayers() do
			local r = rootOf(plr)
			local d = data[plr]
			if r and d then
				local p = r.Position
				if p.Y < -3.5 then
					-- упал в канал: на ближайший берег (с Небесного рынка — обратно на крыши)
					if Catalog.district(p) == "skymarket" then
						plr.Character:PivotTo(CFrame.new(Catalog.Districts.skymarket.tp))
					elseif p.X > 63 * SC then
						plr.Character:PivotTo(CFrame.new(118 * SC, 4, math.clamp(p.Z, -66 * SC, -14 * SC)))
					else
						plr.Character:PivotTo(CFrame.new(math.clamp(p.X, -55 * SC, 55 * SC), 4, p.Z > -30 * SC and -14 * SC or -46 * SC))
					end
				else
					local dn = Catalog.district(p)
					local dc = Catalog.Districts[dn]
					if dc and dc.unlock and not Catalog.unlocked(dn, stats(d)) then
						plr.Character:PivotTo(CFrame.new(dc.back))
						NoticeEv:FireClient(plr, dc.name .. " закрыт. " .. Catalog.unlockText(dn, stats(d)))
					end
				end
			end
		end
		task.wait(0.3)
	end
end)

------------------------------------------------------------------ удача: зелья и объявления со всех серверов
local function addPotion(d)
	d.luckUntil = math.max(d.luckUntil or 0, os.time()) + Catalog.Luck.potionMinutes * 60
end
PotionFn.OnServerInvoke = function(plr)
	local d = data[plr]
	if not d then return { ok = false } end
	if d.dust < Catalog.Luck.potionDust then return { ok = false, msg = ("Нужно %d пыли"):format(Catalog.Luck.potionDust) } end
	d.dust -= Catalog.Luck.potionDust
	addPotion(d)
	persist(plr)
	pushState(plr)
	return { ok = true }
end
task.spawn(function()
	pcall(function()
		MessagingService:SubscribeAsync("SC_Rare", function(msg)
			local m = msg.Data
			if typeof(m) == "table" and m.job ~= game.JobId and Catalog.Kinds[m.kind] and Catalog.Variants[m.variant] then
				AnnounceEv:FireAllClients({ name = tostring(m.name), kind = m.kind, variant = m.variant, odds = tonumber(m.odds) or 0, global = true })
			end
		end)
	end)
end)
-- раз в 30 с обновляем у клиентов удачу (зелье истекает, луна меняется)
task.spawn(function()
	while true do
		task.wait(30)
		for _, plr in Players:GetPlayers() do pushState(plr) end
	end
end)

------------------------------------------------------------------ донат
local function applyPassEffects(plr)
	local d = data[plr]
	if not d then return end
	for key in Money.Passes do plr:SetAttribute("Pass_" .. key, hasPass(d, key)) end
	if hasPass(d, "vip") then d.skins.vip = true end
	local head = plr.Character and plr.Character:FindFirstChild("Head")
	if head and hasPass(d, "vip") and not head:FindFirstChild("VipTag") then
		local b = Instance.new("BillboardGui")
		b.Name, b.Size, b.StudsOffset, b.MaxDistance = "VipTag", UDim2.fromOffset(90, 30), Vector3.new(0, 2.6, 0), 80
		local t = Instance.new("TextLabel")
		t.Size, t.BackgroundColor3, t.Text, t.TextScaled, t.Font = UDim2.fromScale(1, 1), Color3.fromRGB(255, 190, 40), "VIP", true, Enum.Font.GothamBlack
		t.TextColor3 = Color3.fromRGB(60, 30, 0)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = t
		t.Parent = b
		b.Parent = head
	end
	pushState(plr)
end

local function checkPasses(plr)
	local d = data[plr]
	if not d then return end
	d.passes = d.passes or {}
	for key, p in Money.Passes do
		if p.id ~= 0 then
			local ok, owns = pcall(function() return MarketplaceService:UserOwnsGamePassAsync(plr.UserId, p.id) end)
			if ok and owns then d.passes[key] = true end
		end
	end
	applyPassEffects(plr)
end

MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(plr, passId, bought)
	if not bought then return end
	local d = data[plr]
	if not d then return end
	for key, p in Money.Passes do
		if p.id == passId then
			d.passes = d.passes or {}
			d.passes[key] = true
			applyPassEffects(plr)
			NoticeEv:FireClient(plr, "Спасибо! Куплено: " .. p.name)
		end
	end
end)

local function fireworks(byName)
	local center = map.altarPos + Vector3.new(0, 30, 0)
	local colors = { Color3.fromRGB(255, 80, 120), Color3.fromRGB(255, 210, 60), Color3.fromRGB(90, 200, 255), Color3.fromRGB(150, 255, 120), Color3.fromRGB(200, 120, 255) }
	for _, plr in Players:GetPlayers() do NoticeEv:FireClient(plr, byName .. " запускает фейерверк над площадью!") end
	for i = 1, 14 do
		task.delay(i * 0.45, function()
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.Transparency, p.Size = true, false, false, 1, Vector3.one
			p.Position = center + Vector3.new(math.random(-30, 30), math.random(-6, 12), math.random(-30, 30))
			p.Parent = workspace
			local pe = Instance.new("ParticleEmitter")
			local col = colors[math.random(#colors)]
			pe.Color = ColorSequence.new(col, Color3.new(1, 1, 1))
			pe.LightEmission, pe.Rate, pe.Lifetime = 1, 0, NumberRange.new(1.2, 2)
			pe.Speed, pe.SpreadAngle = NumberRange.new(18, 28), Vector2.new(180, 180)
			pe.Drag, pe.Acceleration = 2, Vector3.new(0, -10, 0)
			pe.Size = NumberSequence.new(0.8, 0)
			pe.Parent = p
			local l = Instance.new("PointLight")
			l.Color, l.Range, l.Brightness = col, 40, 3
			l.Parent = p
			pe:Emit(120)
			task.delay(0.4, function() l.Enabled = false end)
			task.delay(2.5, function() p:Destroy() end)
		end)
	end
end

MarketplaceService.ProcessReceipt = function(info)
	local plr = Players:GetPlayerByUserId(info.PlayerId)
	local d = plr and data[plr]
	if not d then return Enum.ProductPurchaseDecision.NotProcessedYet end
	d.receipts = d.receipts or {}
	if table.find(d.receipts, info.PurchaseId) then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local granted = false
	for key, p in Money.Passes do
		if p.product and info.ProductId == p.product then
			d.owned = d.owned or {}
			d.owned[key] = true
			applyPassEffects(plr)
			NoticeEv:FireClient(plr, "Спасибо! Навсегда: " .. p.name)
			granted = true
		end
	end
	if granted then
		-- покупка навсегда
	elseif info.ProductId == Money.Products.luckPotion.id then
		addPotion(d)
		pushState(plr)
		NoticeEv:FireClient(plr, "Зелье удачи выпито: удача x2 на 15 минут!")
		granted = true
	elseif info.ProductId == Money.Products.summonMoon.id and Money.Products.summonMoon.id ~= 0 then
		summonMoon()
		for _, p in Players:GetPlayers() do NoticeEv:FireClient(p, plr.Name .. " призвал Красную луну!") end
		granted = true
	elseif info.ProductId == Money.Products.fireworks.id and Money.Products.fireworks.id ~= 0 then
		fireworks(plr.Name)
		granted = true
	end
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	table.insert(d.receipts, info.PurchaseId)
	while #d.receipts > 50 do table.remove(d.receipts, 1) end
	persist(plr)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

------------------------------------------------------------------ таланты и перерождение
TalentFn.OnServerInvoke = function(plr, action, key)
	local d = data[plr]
	if not d then return { ok = false } end
	if action == "up" then
		if typeof(key) ~= "string" or d.talents[key] == nil then return { ok = false } end
		if talentPoints(d) <= 0 then return { ok = false, msg = "Нет очков: повышай уровень" } end
		if d.talents[key] >= Catalog.Progress.TalentMax then return { ok = false, msg = "Максимум" } end
		d.talents[key] += 1
	elseif action == "reset" then
		if d.dust < Catalog.Progress.TalentResetDust then return { ok = false, msg = ("Нужно %d пыли"):format(Catalog.Progress.TalentResetDust) } end
		d.dust -= Catalog.Progress.TalentResetDust
		for k in d.talents do d.talents[k] = 0 end
	else
		return { ok = false }
	end
	applySpeed(plr)
	persist(plr)
	pushState(plr)
	return { ok = true }
end

AchFn.OnServerInvoke = function(plr, id)
	local d = data[plr]
	local a = typeof(id) == "string" and Catalog.Progress.Achievements[id]
	if not (d and a) then return { ok = false } end
	if d.ach[id] then return { ok = false, msg = "Уже получено" } end
	if achProgress(d, a) < a.need then return { ok = false, msg = "Ещё не выполнено" } end
	d.ach[id] = true
	grant(d, a)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = a.coins, dust = a.dust, skin = a.skin })
	return { ok = true }
end

RebirthFn.OnServerInvoke = function(plr)
	local d = data[plr]
	if not d then return { ok = false } end
	local need = Catalog.Progress.rebirthLevel(d.rebirths or 0)
	if d.level < need then return { ok = false, msg = ("Нужен уровень %d"):format(need) } end
	d.rebirths = (d.rebirths or 0) + 1
	d.level, d.xp, d.coins = 1, 0, 0
	for _, k in Catalog.UpgradeOrder do d.levels[k] = 1 end
	for k in d.talents do d.talents[k] = 0 end
	jars[plr] = {}
	applySpeed(plr)
	persist(plr)
	pushState(plr)
	for _, p in Players:GetPlayers() do
		NoticeEv:FireClient(p, ("%s переродился! Перерождений: %d"):format(plr.DisplayName, d.rebirths))
	end
	return { ok = true, rebirths = d.rebirths }
end

------------------------------------------------------------------ телепорт, коды, новости, админка
local function teleportTo(plr, district)
	local d = data[plr]
	local dc = Catalog.Districts[district]
	local root = rootOf(plr)
	if not (d and dc and dc.tp and root) then return { ok = false } end
	if not Catalog.unlocked(district, stats(d)) then
		return { ok = false, msg = dc.name .. " закрыт. " .. Catalog.unlockText(district, stats(d)) }
	end
	stopHold(plr)
	plr.Character:PivotTo(CFrame.new(dc.tp + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2))))
	return { ok = true }
end
TeleportFn.OnServerInvoke = function(plr, district)
	if typeof(district) ~= "string" then return { ok = false } end
	return teleportTo(plr, district)
end
FeedFn.OnServerInvoke = function(plr)
	local d = data[plr]
	local c = d and compOf(d)
	if not c then return { ok = false, msg = "Сначала выбери спутника в Атласе" } end
	if c.level >= Live.CompanionMax then return { ok = false, msg = "Спутник уже максимального уровня" } end
	local cost = Live.feedCost(c.level)
	if d.dust < cost then return { ok = false, msg = ("Нужно %d пыли"):format(cost) } end
	d.dust -= cost
	d.fed[c.kind] = (d.fed[c.kind] or 0) + 1
	applySpeed(plr)
	persist(plr)
	pushState(plr)
	return { ok = true, level = compOf(d).level }
end
SeasonFn.OnServerInvoke = function(plr, tier, premium)
	local d = data[plr]
	local r = d and typeof(tier) == "number" and (premium == true and Live.Season.premium[tier] or Live.Season.tiers[tier])
	if not r then return { ok = false } end
	if premium == true and not hasPass(d, "season1") then return { ok = false, msg = "Нужен Премиум сезона (Магазин, Донат)" } end
	local se = ensureSeason(d)
	local key = (premium == true and "p" or "") .. tostring(tier)
	if se.claimed[key] then return { ok = false, msg = "Уже получено" } end
	if math.floor(se.xp / Live.Season.tierXp) < tier then return { ok = false, msg = "Набери больше опыта сезона" } end
	se.claimed[key] = true
	if r.furniture then
		d.furniture[r.furniture] = true
		Social.refreshYard(plr)
	end
	d.coins += r.coins or 0
	d.dust += r.dust or 0
	if r.potion then d.luckUntil = math.max(d.luckUntil or 0, os.time()) + r.potion * 60 end
	if r.skin then d.skins[r.skin] = true end
	if r.title then
		d.titles[r.title] = true
		d.title = r.title
	end
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = r.coins, dust = r.dust, skin = r.skin })
	return { ok = true }
end
CoinShopFn.OnServerInvoke = function(plr, action, arg)
	local d = data[plr]
	if not d then return { ok = false } end
	local CS = Live.CoinShop
	if action == "shrine" then
		local lvl = d.shrine or 0
		if lvl >= CS.shrineMax then return { ok = false, msg = "Святилище на максимуме" } end
		local cost = Live.shrineCost(lvl)
		if d.coins < cost then return { ok = false, msg = ("Нужно %d монет"):format(cost) } end
		d.coins -= cost
		d.shrine = lvl + 1
	elseif action == "exchange" then
		local n = (arg == 100 or arg == 1000) and arg or 10
		local cost = n * CS.exchangeRate
		if d.coins < cost then return { ok = false, msg = ("Нужно %d монет"):format(cost) } end
		d.coins -= cost
		d.dust += n
	elseif action == "potion" then
		if d.coins < CS.potionCoins then return { ok = false, msg = ("Нужно %d монет"):format(CS.potionCoins) } end
		d.coins -= CS.potionCoins
		addPotion(d)
	elseif action == "summon" then
		local root = rootOf(plr)
		if not root then return { ok = false } end
		local district = Catalog.district(root.Position)
		local dc = Catalog.Districts[district]
		if not dc or dc.max == 0 then return { ok = false, msg = "Призыв работает в районах с духами" } end
		if not Catalog.unlocked(district, stats(d)) then return { ok = false } end
		local cost = Live.summonCost(d.level)
		if d.coins < cost then return { ok = false, msg = ("Нужно %d монет"):format(cost) } end
		-- только редкие и выше из этого района
		-- самые редкие из обычных духов района (редкие и выше, иначе необычные, иначе любые)
		local pool = {}
		for _, minR in { "rare", "uncommon", "common" } do
			for kind, info in Catalog.Kinds do
				if info.spawn[district] and RARITY_RANK[info.rarity] >= RARITY_RANK[minR] and not info.moonOnly then table.insert(pool, kind) end
			end
			if #pool > 0 then break end
		end
		if #pool == 0 then return { ok = false, msg = "Здесь нельзя призвать духа" } end
		d.coins -= cost
		local at = root.Position + root.CFrame.LookVector * 10
		local sp = newSpirit(pool[math.random(#pool)], district, false, Vector3.new(at.X, 0.5, at.Z))
		sp.revealed = true
		sp.revealedAt = os.clock()
		sp.anchor:SetAttribute("Revealed", true)
	else
		return { ok = false }
	end
	persist(plr)
	pushState(plr)
	return { ok = true }
end
EvolveFn.OnServerInvoke = function(plr, kind)
	local d = data[plr]
	local info = d and typeof(kind) == "string" and Catalog.Kinds[kind]
	if not info then return { ok = false } end
	if d.evolved[kind] then return { ok = false, msg = "Уже пробуждён" } end
	if (d.saved[kind] or 0) < Live.EvolveDupes + 1 then
		return { ok = false, msg = ("Нужно %d дубликатов (у тебя %d)"):format(Live.EvolveDupes, math.max(0, (d.saved[kind] or 0) - 1)) }
	end
	local cost = Live.EvolveDust[info.rarity] or 50
	if d.dust < cost then return { ok = false, msg = ("Нужно %d пыли"):format(cost) } end
	d.dust -= cost
	d.saved[kind] -= Live.EvolveDupes
	d.evolved[kind] = true
	storyEvent(plr, d, "evolve")
	applySpeed(plr)
	Social.refreshYard(plr)
	persist(plr)
	pushState(plr)
	return { ok = true }
end
FurnitureFn.OnServerInvoke = function(plr, id)
	local d = data[plr]
	local f = d and typeof(id) == "string" and Live.Furniture[id]
	if not f then return { ok = false } end
	if d.furniture[id] then return { ok = false, msg = "Уже стоит во дворе" } end
	if f.premium then return { ok = false, msg = "Награда премиум-трека сезона" } end
	if d.coins < f.coins or d.dust < (f.dust or 0) then return { ok = false, msg = "Не хватает монет или пыли" } end
	d.coins -= f.coins
	d.dust -= f.dust or 0
	d.furniture[id] = true
	Social.refreshYard(plr)
	persist(plr)
	pushState(plr)
	return { ok = true }
end
StoryFn.OnServerInvoke = function(plr, action)
	local d = data[plr]
	if not d then return { ok = false } end
	local ch = Live.Story[d.story.ch]
	if action ~= "claim" or not ch then return { ok = false } end
	if d.story.prog < ch.need then return { ok = false, msg = "Глава ещё не выполнена" } end
	d.coins += ch.coins or 0
	d.dust += ch.dust or 0
	if ch.title2 then
		d.titles[ch.title2] = true
		d.title = ch.title2
	end
	d.story = { ch = d.story.ch + 1, prog = 0 }
	addSeasonXp(d, 100)
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = ch.coins, dust = ch.dust })
	return { ok = true }
end
TitleFn.OnServerInvoke = function(plr, title)
	local d = data[plr]
	if not d then return { ok = false } end
	if title == nil or title == "" then
		d.title = nil
	elseif typeof(title) == "string" and d.titles[title] then
		d.title = title
	else
		return { ok = false }
	end
	pushState(plr)
	return { ok = true }
end

RedeemFn.OnServerInvoke = function(plr, code)
	local d = data[plr]
	if not (d and typeof(code) == "string") then return { ok = false } end
	local key = string.upper(string.gsub(code, "%s", ""))
	local c = Catalog.Progress.Codes[key]
	if not c then return { ok = false, msg = "Такого кода нет" } end
	d.codes = d.codes or {}
	if d.codes[key] then return { ok = false, msg = "Код уже активирован" } end
	d.codes[key] = true
	d.coins += c.coins or 0
	d.dust += c.dust or 0
	if c.skin then d.skins[c.skin] = true end
	persist(plr)
	pushState(plr)
	RewardEv:FireClient(plr, { coins = c.coins, dust = c.dust, skin = c.skin })
	return { ok = true, msg = c.text }
end

NewsSeenEv.OnServerEvent:Connect(function(plr)
	local d = data[plr]
	if d and d.newsSeen < Catalog.Progress.NewsVersion then
		d.newsSeen = Catalog.Progress.NewsVersion
		persist(plr)
	end
end)

AdminFn.OnServerInvoke = function(plr, cmd, a1, a2)
	if not isAdmin(plr) then return { ok = false, msg = "Нет доступа" } end
	local d = data[plr]
	local root = rootOf(plr)
	if not d then return { ok = false } end
	if cmd == "coins" then
		d.coins += 1000
	elseif cmd == "dust" then
		d.dust += 100
	elseif cmd == "level" then
		d.level += 1
		d.xp = 0
	elseif cmd == "allSpirits" then
		for _, kind in Catalog.Order do
			d.saved[kind] = (d.saved[kind] or 0) + 5
			d.firstSaved[kind] = true
			d.variants[kind] = {}
			for _, v in Catalog.VariantOrder do d.variants[kind][v] = true end
		end
	elseif cmd == "maxUpgrades" then
		for _, k in Catalog.UpgradeOrder do d.levels[k] = Catalog.MaxLevel end
	elseif cmd == "passes" then
		d.owned = d.owned or {}
		for key in Money.Passes do d.owned[key] = true end
		for key in Catalog.Progress.Skins do d.skins[key] = true end
		applyPassEffects(plr)
	elseif cmd == "moon" then
		summonMoon()
	elseif cmd == "endMoon" then
		if moon.active then phaseEnd = os.clock() end
	elseif cmd == "fireworks" then
		fireworks(plr.Name)
	elseif cmd == "mod" then
		-- следующий модификатор дня (для проверки)
		local cur, idx = dayMod(), 1
		for i, m in Live.Modifiers do
			if m.id == cur then idx = i % #Live.Modifiers + 1 end
		end
		modOverride = Live.Modifiers[idx].id
		workspace:SetAttribute("DayMod", modOverride)
		for _, p in Players:GetPlayers() do pushState(p) end
	elseif cmd == "raid" then
		startRaid()
	elseif cmd == "holiday" then
		-- по кругу: праздники по очереди, потом снова по календарю
		local ids = { "autumn", "halloween", "newyear" }
		local idx = holidayOverride and table.find(ids, holidayOverride) or 0
		holidayOverride = ids[idx + 1]
		workspace:SetAttribute("HolidayOverride", holidayOverride or "")
	elseif cmd == "boss" then
		if startBossCmd then startBossCmd(typeof(a1) == "string" and a1 or nil) end
	elseif cmd == "season" then
		addSeasonXp(d, Live.Season.tierXp * 3)
	elseif cmd == "fast" then
		adminFast[plr] = not adminFast[plr]
	elseif cmd == "fillJar" then
		while #jars[plr] < cap(d) do table.insert(jars[plr], { k = "PaperFox", v = "normal" }) end
	elseif cmd == "spawn" then
		local kind = typeof(a1) == "string" and Catalog.Kinds[a1] and a1
		if not (kind and root) then return { ok = false, msg = "Нет такого духа" } end
		local district = Catalog.district(root.Position)
		if not Catalog.Districts[district] or #Catalog.Districts[district].zones == 0 then district = "street" end
		local at = root.Position + root.CFrame.LookVector * 8
		local s = newSpirit(kind, district, false, Vector3.new(at.X, 0.5, at.Z), typeof(a2) == "string" and a2 or nil)
		s.revealed = true
		s.revealedAt = os.clock()
		s.anchor:SetAttribute("Revealed", true)
	elseif cmd == "reset" then
		local fresh = migrate(nil)
		fresh.passes = d.passes
		data[plr] = fresh
		jars[plr] = {}
		d = fresh
	else
		return { ok = false, msg = "Неизвестная команда" }
	end
	persist(plr)
	pushState(plr)
	return { ok = true }
end

------------------------------------------------------------------ доска рекордов (всего поймано)
local board = nil
pcall(function() board = DataStoreService:GetOrderedDataStore("SpiritCatchers_TotalCaught") end)
local nameCache = {}
function updateBoard(plr)
	local d = data[plr]
	if not (board and d) or d.loadFailed then return end
	task.spawn(function()
		pcall(function() board:SetAsync("u" .. plr.UserId, d.total) end)
	end)
end
local function renderBoard()
	if not board then return end
	local ok, pages = pcall(function() return board:GetSortedAsync(false, 10) end)
	if not ok then return end
	local list = pages:GetCurrentPage()
	local gui = map.boardGui
	for _, c in gui:GetChildren() do c:Destroy() end
	local frame = Instance.new("Frame")
	frame.Size, frame.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(30, 22, 40)
	frame.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size, title.BackgroundTransparency, title.TextScaled, title.Font = UDim2.new(1, 0, 0.16, 0), 1, true, Enum.Font.GothamBlack
	title.Text, title.TextColor3 = "ЛУЧШИЕ ЛОВЦЫ", Color3.fromRGB(255, 205, 70)
	title.Parent = frame
	for i, e in list do
		local uid = tonumber(string.sub(e.key, 2))
		local name = uid and nameCache[uid]
		if not name and uid then
			local okN, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
			name = okN and n or ("#" .. uid)
			nameCache[uid] = name
		end
		local row = Instance.new("TextLabel")
		row.Size, row.Position = UDim2.new(0.94, 0, 0.083, 0), UDim2.new(0.03, 0, 0.16 + (i - 1) * 0.083, 0)
		row.BackgroundTransparency, row.TextScaled, row.Font = 1, true, Enum.Font.GothamBold
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = i == 1 and Color3.fromRGB(255, 220, 90) or Color3.new(1, 1, 1)
		row.Text = ("%d. %s — %d"):format(i, name or "?", e.value)
		row.Parent = frame
	end
end
task.spawn(function()
	while true do
		renderBoard()
		task.wait(60)
	end
end)

-- доска «Редчайший улов недели»
local function renderRareBoard()
	local week = Live.week(os.time())
	local st = weekStore(week)
	if not st then return end
	local ok, pages = pcall(function() return st:GetSortedAsync(false, 8) end)
	if not ok then return end
	local list = pages:GetCurrentPage()
	local gui = map.rareGui
	for _, c in gui:GetChildren() do c:Destroy() end
	local frame = Instance.new("Frame")
	frame.Size, frame.BackgroundColor3 = UDim2.fromScale(1, 1), Color3.fromRGB(26, 22, 48)
	frame.Parent = gui
	local title = Instance.new("TextLabel")
	title.Size, title.BackgroundTransparency, title.TextScaled, title.Font = UDim2.new(1, 0, 0.15, 0), 1, true, Enum.Font.GothamBlack
	title.Text, title.TextColor3 = "РЕДЧАЙШИЙ УЛОВ НЕДЕЛИ", Color3.fromRGB(200, 160, 255)
	title.Parent = frame
	for i, e in list do
		local uid = tonumber(string.sub(e.key, 2))
		local name = uid and nameCache[uid]
		if not name and uid then
			local okN, n = pcall(function() return Players:GetNameFromUserIdAsync(uid) end)
			name = okN and n or ("#" .. uid)
			nameCache[uid] = name
		end
		local what = ""
		if weekInfo and uid then
			local okI, info = pcall(function() return weekInfo:GetAsync(week .. "_" .. uid) end)
			if okI and typeof(info) == "table" and Catalog.Kinds[info.k] and Catalog.Variants[info.v] then
				what = (info.v ~= "normal" and (Catalog.Variants[info.v].name .. " ") or "") .. Catalog.Kinds[info.k].name
			end
		end
		local row = Instance.new("TextLabel")
		row.Size, row.Position = UDim2.new(0.94, 0, 0.1, 0), UDim2.new(0.03, 0, 0.16 + (i - 1) * 0.105, 0)
		row.BackgroundTransparency, row.TextScaled, row.Font = 1, true, Enum.Font.GothamBold
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = i == 1 and Color3.fromRGB(255, 220, 90) or Color3.new(1, 1, 1)
		row.Text = ("%d. %s: %s (%d очк.)"):format(i, name or "?", what, e.value)
		row.Parent = frame
	end
end
task.spawn(function()
	while true do
		pcall(renderRareBoard)
		task.wait(90)
	end
end)

------------------------------------------------------------------ рейд «Тысяча фонарей»
local RAID = Live.Raid
local raid = { active = false, lit = 0, goal = 0, contrib = {}, lastHit = {}, endsAt = 0 }
local nextRaid = os.clock() + RAID.first
workspace:SetAttribute("RaidActive", false)
workspace:SetAttribute("RaidNext", os.time() + RAID.first)
local raidGiant
local raidCenter = Vector3.new(0, 15, 72 * Catalog.Worlds.Scale)
local function buildGiant()
	local m = Instance.new("Model")
	m.Name = "RaidGiant"
	local function part(name, size, offset, color, shape, transp)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color, p.Material = name, size, color, Enum.Material.Neon
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		if shape then p.Shape = shape end
		p.Transparency = transp or 0
		p.CFrame = CFrame.new(raidCenter + offset)
		p.Parent = m
		return p
	end
	local body = part("Body", Vector3.new(12, 14, 12), Vector3.new(), Color3.fromRGB(255, 150, 60), Enum.PartType.Ball, 0.1)
	m.PrimaryPart = body
	part("Cap", Vector3.new(9, 1.6, 9), Vector3.new(0, 7.4, 0), Color3.fromRGB(70, 35, 30), nil)
	part("Bottom", Vector3.new(7, 1.4, 7), Vector3.new(0, -7.2, 0), Color3.fromRGB(70, 35, 30), nil)
	for _, x in { -2.4, 2.4 } do
		part("Eye", Vector3.new(1.8, 2.4, 1.8), Vector3.new(x, 1.5, -5.6), Color3.fromRGB(40, 20, 30), Enum.PartType.Ball)
	end
	part("Mouth", Vector3.new(3, 0.8, 1), Vector3.new(0, -1.6, -5.8), Color3.fromRGB(40, 20, 30), nil)
	for i = 1, 6 do
		part("Tail", Vector3.new(2.2, 2.6, 2.2), Vector3.new(0, -9 - i * 2.6, 1 + i * 1.2), Color3.fromRGB(255, 120 + i * 15, 60), Enum.PartType.Ball, 0.15)
	end
	local light = Instance.new("PointLight")
	light.Range, light.Brightness, light.Color = 60, 2, Color3.fromRGB(255, 170, 90)
	light.Parent = body
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 120, 60))
	pe.LightEmission, pe.Rate, pe.Lifetime, pe.Speed = 1, 30, NumberRange.new(2, 3), NumberRange.new(3, 6)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Size = NumberSequence.new(0.8, 0)
	pe.Parent = body
	m.Parent = workspace
	return m
end
local function setRaidAttrs()
	workspace:SetAttribute("RaidActive", raid.active)
	workspace:SetAttribute("RaidLit", raid.lit)
	workspace:SetAttribute("RaidGoal", raid.goal)
	workspace:SetAttribute("RaidEnds", raid.endsAt)
end
local function endRaid()
	if not raid.active then return end
	raid.active = false
	local success = raid.lit >= raid.goal
	if raidGiant then raidGiant:Destroy() raidGiant = nil end
	for plr, n in raid.contrib do
		local d = data[plr]
		if d and plr.Parent and n >= 5 then
			local share = success and 1 or RAID.failShare
			local coins = math.floor((RAID.reward.coins + n * RAID.perLantern) * share)
			local dust = math.floor(RAID.reward.dust * share)
			d.coins += coins
			d.dust += dust
			addSeasonXp(d, math.floor(RAID.reward.sxp * share))
			storyEvent(plr, d, "raid")
			persist(plr)
			pushState(plr)
			RewardEv:FireClient(plr, { coins = coins, dust = dust })
			NoticeEv:FireClient(plr, success and ("Тысяча фонарей зажжена! Твои фонарики: %d. +%d монет"):format(n, coins)
				or ("Не успели зажечь все фонари. Утешительная награда: +%d монет"):format(coins))
		end
	end
	if success then
		fireworks("Весь сервер")
		-- в награду по кварталу разлетаются редкие духи
		for _, dn in { "street", "canal", "market" } do
			local kind = pickKind(dn)
			if kind then newSpirit(kind, dn, false, nil, "shiny") end
		end
	end
	raid.contrib, raid.lastHit = {}, {}
	nextRaid = os.clock() + RAID.every
	workspace:SetAttribute("RaidNext", os.time() + RAID.every)
	setRaidAttrs()
end
startRaid = function()
	if raid.active then return end
	raid.active = true
	raid.lit = 0
	raid.goal = Live.raidGoal(#Players:GetPlayers())
	raid.contrib, raid.lastHit = {}, {}
	raid.endsAt = os.time() + RAID.duration
	raid.endClock = os.clock() + RAID.duration
	raidGiant = buildGiant()
	setRaidAttrs()
	for _, p in Players:GetPlayers() do
		NoticeEv:FireClient(p, "Тысяча фонарей! Над улицей Великий фонарный дух. Свети на него фонарём!")
	end
end
RaidHitEv.OnServerEvent:Connect(function(plr)
	if not (raid.active and raidGiant and raidGiant.PrimaryPart) then return end
	local root = rootOf(plr)
	local d = data[plr]
	if not (root and d) then return end
	local now = os.clock()
	if now - (raid.lastHit[plr] or 0) < RAID.hitEvery then return end
	raid.lastHit[plr] = now
	if (root.Position - raidGiant.PrimaryPart.Position).Magnitude > RAID.radius then return end
	local n = 1 + math.floor((d.levels.power - 1) / 2)
	raid.lit += n
	raid.contrib[plr] = (raid.contrib[plr] or 0) + n
	workspace:SetAttribute("RaidLit", raid.lit)
	if raid.lit >= raid.goal then endRaid() end
end)
task.spawn(function()
	local warned = false
	while true do
		task.wait(0.1)
		local now = os.clock()
		if raid.active then
			if raidGiant and raidGiant.PrimaryPart then
				local t = now * 0.25
				local pos = raidCenter + Vector3.new(math.cos(t) * 14, math.sin(now * 1.3) * 1.5, math.sin(t) * 22)
				raidGiant:PivotTo(CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0) + map.altarPos * Vector3.new(1, 0, 1)))
			end
			if now >= (raid.endClock or 0) then endRaid() end
		else
			if not warned and nextRaid - now < 30 then
				warned = true
				for _, p in Players:GetPlayers() do NoticeEv:FireClient(p, "Через 30 секунд: Тысяча фонарей над улицей!") end
			end
			if now >= nextRaid and #Players:GetPlayers() > 0 then
				warned = false
				startRaid()
			end
		end
	end
end)
Players.PlayerRemoving:Connect(function(plr)
	raid.contrib[plr] = nil
	raid.lastHit[plr] = nil
end)

------------------------------------------------------------------ Хранитель алтаря (NPC сюжета)
do
	local SC2 = Catalog.Worlds.Scale
	local base = Vector3.new(16 * SC2 / 1.6, 0.5, 4 * SC2)
	local npc = Instance.new("Model")
	npc.Name = "AltarKeeper"
	local function np(name, size, offset, color, mat, shape)
		local p = Instance.new("Part")
		p.Name, p.Size, p.Color, p.Material = name, size, color, mat or Enum.Material.SmoothPlastic
		p.Anchored, p.CanCollide = true, name == "Robe"
		if shape then p.Shape = shape end
		p.CFrame = CFrame.new(base + offset) * CFrame.Angles(0, math.rad(200), 0)
		p.Parent = npc
		return p
	end
	local robe = np("Robe", Vector3.new(3, 5, 3), Vector3.new(0, 2.5, 0), Color3.fromRGB(70, 60, 120), Enum.Material.Fabric)
	np("Sash", Vector3.new(3.1, 0.6, 3.1), Vector3.new(0, 3.4, 0), Color3.fromRGB(200, 60, 50), Enum.Material.Fabric)
	np("Head", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, 5.9, 0), Color3.fromRGB(240, 220, 200), nil, Enum.PartType.Ball)
	np("Beard", Vector3.new(1.2, 1.4, 0.6), Vector3.new(0, 5.1, -0.8), Color3.fromRGB(235, 235, 240))
	np("Hat", Vector3.new(3.6, 0.5, 3.6), Vector3.new(0, 7, 0), Color3.fromRGB(150, 120, 70), Enum.Material.Wood, Enum.PartType.Cylinder).CFrame = CFrame.new(base + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90))
	np("Staff", Vector3.new(0.3, 7, 0.3), Vector3.new(1.8, 3.5, -0.4), Color3.fromRGB(90, 60, 40), Enum.Material.Wood)
	local lantern = np("Lantern", Vector3.new(1, 1.2, 1), Vector3.new(1.8, 7.2, -0.4), Color3.fromRGB(255, 190, 100), Enum.Material.Neon, Enum.PartType.Ball)
	local pl = Instance.new("PointLight")
	pl.Range, pl.Brightness, pl.Color = 16, 1, Color3.fromRGB(255, 190, 110)
	pl.Parent = lantern
	npc.PrimaryPart = robe
	local tag = Instance.new("BillboardGui")
	tag.Size, tag.StudsOffset, tag.MaxDistance = UDim2.fromOffset(200, 26), Vector3.new(0, 5.5, 0), 70
	local tl = Instance.new("TextLabel")
	tl.Size, tl.BackgroundTransparency, tl.TextScaled, tl.Font = UDim2.fromScale(1, 1), 1, true, Enum.Font.GothamBlack
	tl.Text, tl.TextColor3, tl.TextStrokeTransparency = "Хранитель алтаря", Color3.fromRGB(255, 220, 140), 0.2
	tl.Parent = tag
	tag.Parent = robe
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText, prompt.ObjectText = "Поговорить", "Хранитель"
	prompt.HoldDuration, prompt.MaxActivationDistance, prompt.RequiresLineOfSight = 0, 12, false
	prompt.Parent = robe
	prompt.Triggered:Connect(function(plr) StoryOpenEv:FireClient(plr) end)
	npc.Parent = workspace
end

------------------------------------------------------------------ ночные стражи
local BOSS = Live.Boss
local boss = { active = false }
local nextBoss = os.clock() + BOSS.first
workspace:SetAttribute("BossActive", false)
local function endBoss(win: boolean)
	if not boss.active then return end
	boss.active = false
	if boss.anchor then boss.anchor:Destroy() end
	workspace:SetAttribute("BossActive", false)
	for plr, n in boss.contrib do
		local d = data[plr]
		if d and plr.Parent and n >= 3 then
			local share = win and 1 or 0.25
			local coins = math.floor((BOSS.reward.coins + n * 2) * share)
			local dust = math.floor(BOSS.reward.dust * share)
			d.coins += coins
			d.dust += dust
			addSeasonXp(d, math.floor(BOSS.reward.sxp * share))
			if win then storyEvent(plr, d, "boss") end
			persist(plr)
			pushState(plr)
			RewardEv:FireClient(plr, { coins = coins, dust = dust })
			NoticeEv:FireClient(plr, win and ("%s повержен! +%d монет, +%d пыли"):format(boss.name, coins, dust) or ("%s ушёл. Утешительная награда +%d монет"):format(boss.name, coins))
		end
	end
	if win then
		for _ = 1, 2 do
			local kind = pickKind(boss.district)
			if kind then newSpirit(kind, boss.district, false, nil, "golden") end
		end
	end
	boss.contrib = {}
	nextBoss = os.clock() + BOSS.every
end
local function startBoss(district: string?)
	if boss.active then return end
	-- район, где есть хотя бы один игрок с открытым доступом
	local options = {}
	for dn, b in BOSS.list do
		for _, p in Players:GetPlayers() do
			local d = data[p]
			if d and Catalog.unlocked(dn, stats(d)) and #Catalog.Districts[dn].zones > 0 then
				table.insert(options, dn)
				break
			end
		end
	end
	district = district or options[math.random(math.max(#options, 1))]
	local b = district and BOSS.list[district]
	if not b then return end
	local dc = Catalog.Districts[district]
	local hp = math.clamp(BOSS.hpPerPlayer * #Players:GetPlayers(), BOSS.minHp, BOSS.maxHp)
	local a = Instance.new("Part")
	a.Name, a.Size, a.Transparency, a.Anchored, a.CanCollide, a.CanQuery = "NightBoss", Vector3.new(4, 4, 4), 1, true, false, false
	a.CFrame = CFrame.new(dc.center + Vector3.new(0, 3, 0))
	a:SetAttribute("Kind", b.kind)
	a:SetAttribute("BossName", b.name)
	a:SetAttribute("District", district)
	a:SetAttribute("HP", hp)
	a:SetAttribute("MaxHP", hp)
	a:SetAttribute("Ends", os.time() + BOSS.duration)
	a.Parent = workspace
	boss = { active = true, anchor = a, hp = hp, contrib = {}, lastHit = {}, district = district, name = b.name, endClock = os.clock() + BOSS.duration, center = dc.center }
	workspace:SetAttribute("BossActive", true)
	for _, p in Players:GetPlayers() do
		NoticeEv:FireClient(p, ("Ночной страж %s проснулся: %s! Свети на него вместе с другими"):format(b.name, dc.name))
	end
end
startBossCmd = startBoss
BossHitEv.OnServerEvent:Connect(function(plr)
	if not (boss.active and boss.anchor) then return end
	local root = rootOf(plr)
	local d = data[plr]
	if not (root and d) then return end
	local now = os.clock()
	if now - (boss.lastHit[plr] or 0) < BOSS.hitEvery then return end
	boss.lastHit[plr] = now
	if (root.Position - boss.anchor.Position).Magnitude > BOSS.radius then return end
	local dmg = 1 + math.floor((d.levels.power - 1) / 2)
	boss.hp -= dmg
	boss.contrib[plr] = (boss.contrib[plr] or 0) + dmg
	boss.anchor:SetAttribute("HP", math.max(0, boss.hp))
	if boss.hp <= 0 then endBoss(true) end
end)
task.spawn(function()
	while true do
		task.wait(0.1)
		local now = os.clock()
		if boss.active then
			if boss.anchor then
				local t = now * 0.3
				local pos = boss.center + Vector3.new(math.cos(t) * 14, 3 + math.sin(now * 1.5) * 0.6, math.sin(t * 0.8) * 10)
				boss.anchor.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(t), 0, math.cos(t * 0.8)))
			end
			if now >= boss.endClock then endBoss(false) end
		elseif now >= nextBoss and not workspace:GetAttribute("RaidActive") and #Players:GetPlayers() > 0 then
			startBoss()
			if not boss.active then nextBoss = now + 30 end
		end
	end
end)

game:GetService("StarterPlayer").CameraMaxZoomDistance = 40

------------------------------------------------------------------ игроки
Social.init({
	data = data, Catalog = Catalog, pushState = pushState, persist = persist, rootOf = rootOf,
	NoticeEv = NoticeEv, stopHold = stopHold, distinct = distinct, compOf = compOf,
})

Players.PlayerAdded:Connect(function(plr)
	plr.CameraMaxZoomDistance = 40
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local v = Instance.new("IntValue")
	v.Name = "Духи"
	v.Parent = ls
	local lv = Instance.new("IntValue")
	lv.Name = "Уровень"
	lv.Parent = ls
	local rb = Instance.new("IntValue")
	rb.Name = "Перерождения"
	rb.Parent = ls
	ls.Parent = plr

	local raw, failed = nil, false
	if store then
		failed = true
		for attempt = 1, 3 do
			local ok, res = pcall(function() return store:GetAsync("u" .. plr.UserId) end)
			if ok then
				raw, failed = res, false
				break
			end
			warn("DataStore load failed:", res)
			task.wait(attempt)
		end
	end
	if not plr.Parent then return end
	local d = migrate(raw)
	d.loadFailed = failed or nil
	data[plr] = d
	jars[plr] = {}
	plr.CharacterAdded:Connect(function(char)
		giveLantern(plr, char)
		task.wait(0.3)
		applyPassEffects(plr)
		applySpeed(plr)
	end)
	if plr.Character then giveLantern(plr, plr.Character) end
	task.spawn(checkPasses, plr)
	pushState(plr)
	Social.playerReady(plr)
	if failed then NoticeEv:FireClient(plr, "Не удалось загрузить сохранение — прогресс этой сессии не запишется") end
end)

Players.PlayerRemoving:Connect(function(plr)
	Social.playerLeft(plr)
	stopHold(plr)
	persist(plr)
	updateBoard(plr)
	data[plr], jars[plr], inZone[plr], adminFast[plr] = nil, nil, nil, nil
end)

task.spawn(function()
	while true do
		task.wait(60)
		for _, plr in Players:GetPlayers() do persist(plr) end
	end
end)

------------------------------------------------------------------ обновление: старые серверы переносят игроков на новую версию
do
	local migrating = false
	local function migrate()
		if migrating or (game.PlaceVersion or 0) == 0 then return end
		migrating = true
		for _, p in Players:GetPlayers() do NoticeEv:FireClient(p, "Вышло обновление! Через 20 секунд перенесём тебя на новый сервер") end
		task.wait(20)
		for _, p in Players:GetPlayers() do persist(p) end
		local list = Players:GetPlayers()
		if #list > 0 then
			pcall(function() game:GetService("TeleportService"):TeleportAsync(game.PlaceId, list) end)
		end
	end
	task.spawn(function()
		pcall(function()
			MessagingService:SubscribeAsync("SC_Version", function(msg)
				local v = typeof(msg.Data) == "table" and msg.Data.v
				if typeof(v) == "number" and v > (game.PlaceVersion or 0) then task.spawn(migrate) end
			end)
		end)
		-- новый сервер сообщает свою версию остальным (и повторяет для поздно запущенных)
		while true do
			pcall(function() MessagingService:PublishAsync("SC_Version", { v = game.PlaceVersion or 0 }) end)
			task.wait(300)
		end
	end)
	Players.PlayerAdded:Connect(function(p)
		if migrating then
			task.wait(5)
			pcall(function() game:GetService("TeleportService"):TeleportAsync(game.PlaceId, { p }) end)
		end
	end)
end

game:BindToClose(function()
	for _, plr in Players:GetPlayers() do persist(plr) end
end)
