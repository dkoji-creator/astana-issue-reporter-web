-- «Живые» системы: спутники со способностями, модификатор дня, испытания дня и сезонный пропуск.
local L = {}
local rgb = Color3.fromRGB

------------------------------------------------------------------ спутники
-- уровень спутника растёт от поимок этого вида (корень из числа сданных) и от кормления пылью
L.CompanionMax = 10
function L.companionLevel(saved: number, fed: number): number
	return math.clamp(math.floor(math.sqrt(saved)) + (fed or 0), 1, L.CompanionMax)
end
function L.feedCost(level: number): number
	return 15 + level * 15
end
L.Abilities = {
	speed = { name = "Быстрые лапы", short = "к бегу", per = 0.35, fmt = "+%.1f", color = rgb(90, 200, 255) },
	luck = { name = "Удача", short = "удачи", per = 2.5, fmt = "+%d%%", color = rgb(90, 230, 120) },
	coins = { name = "Монетки", short = "монет", per = 4, fmt = "+%d%%", color = rgb(255, 200, 60) },
	dust = { name = "Пыльца", short = "пыли", per = 6, fmt = "+%d%%", color = rgb(190, 130, 255) },
	xp = { name = "Мудрость", short = "опыта", per = 5, fmt = "+%d%%", color = rgb(255, 150, 70) },
	reveal = { name = "Зоркость", short = "к проявлению теней", per = 4, fmt = "+%d%%", color = rgb(170, 120, 255) },
	grip = { name = "Цепкость", short = "к зоне ловли", per = 2.5, fmt = "+%d%%", color = rgb(110, 220, 140) },
}
L.CompanionAbility = {
	PaperFox = "speed", Umbrella = "grip", Firefly = "reveal", PaperMoth = "reveal", LanternSpirit = "xp",
	Kodama = "dust", BellTanuki = "coins", Kappa = "grip", Crane = "speed", InkSnake = "reveal", LuckyCat = "coins",
	JellyLantern = "dust", MoonRabbit = "speed", FoxFire = "xp", TenguMask = "grip", SeaHorse = "dust",
	LighthouseOwl = "reveal", GoldenCarp = "luck", PaperWhale = "coins", PaperDragon = "luck", MistKraken = "xp", Kyubi = "luck",
}
L.RarityPower = { common = 1, uncommon = 1.2, rare = 1.4, epic = 1.7, legendary = 2, mythic = 2.5, secret = 3 }
-- сила способности: число (для speed — студы скорости, для остальных — проценты)
function L.abilityValue(kind: string, rarity: string, level: number): (string, number)
	local key = L.CompanionAbility[kind] or "luck"
	return key, L.Abilities[key].per * level * (L.RarityPower[rarity] or 1)
end
function L.abilityText(key: string, value: number): string
	local a = L.Abilities[key]
	local v = key == "speed" and a.fmt:format(value) or a.fmt:format(math.floor(value + 0.5))
	return v .. " " .. a.short
end

------------------------------------------------------------------ модификатор дня (общий для всех серверов)
L.Modifiers = {
	{ id = "doubleMoon", name = "Двойная луна", desc = "Красная луна приходит вдвое чаще", color = rgb(255, 80, 70) },
	{ id = "tracksOnly", name = "Только следы", desc = "Тени почти невидимы, ищи по следам. Удача x1.5", color = rgb(200, 160, 110) },
	{ id = "goldRush", name = "Золотая лихорадка", desc = "Монеты за улов x1.5", color = rgb(255, 200, 60) },
	{ id = "giants", name = "День гигантов", desc = "Гигантские духи втрое чаще", color = rgb(120, 200, 255) },
	{ id = "lucky", name = "Счастливый день", desc = "Удача x1.3 для всех", color = rgb(90, 230, 120) },
	{ id = "fogDay", name = "Туманный день", desc = "Туманная ночь вместо каждой второй луны", color = rgb(190, 200, 230) },
}
function L.day(t: number): number
	return math.floor(t / 86400)
end
function L.modifierOf(day: number)
	return L.Modifiers[(day * 5 + 2) % #L.Modifiers + 1]
end

------------------------------------------------------------------ испытания дня: 3 штуки, одинаковые у всех в этот день
-- type: catch (поймать N), rarity (N духов редкости min и выше), district (N в районе), variant (N необычных разновидностей), deliver (сдать N банок)
L.ChallengePool = {
	{ type = "catch", need = 20, text = "Поймай %d духов" },
	{ type = "catch", need = 35, text = "Поймай %d духов" },
	{ type = "rarity", min = "rare", need = 4, text = "Поймай %d редких или лучше" },
	{ type = "rarity", min = "epic", need = 2, text = "Поймай %d эпических или лучше" },
	{ type = "district", district = "canal", need = 8, text = "Поймай %d духов у канала" },
	{ type = "district", district = "market", need = 8, text = "Поймай %d духов на рынке" },
	{ type = "district", district = "grove", need = 6, text = "Поймай %d духов в роще" },
	{ type = "district", district = "street", need = 10, text = "Поймай %d духов на улице" },
	{ type = "variant", need = 2, text = "Поймай %d необычных разновидности" },
	{ type = "deliver", need = 4, text = "Сдай %d банок у алтаря" },
}
L.ChallengeReward = { coins = 300, dust = 10, sxp = 120 }
L.ChallengeAllBonus = { coins = 600, dust = 25, sxp = 200 } -- за все три
function L.challengesOf(day: number)
	local list, used = {}, {}
	local seed = day * 7919
	for i = 1, 3 do
		local idx
		repeat
			seed = (seed * 1103 + 12345) % 2147483
			idx = seed % #L.ChallengePool + 1
		until not used[idx] or #list >= #L.ChallengePool
		used[idx] = true
		list[i] = L.ChallengePool[idx]
	end
	return list
end
function L.challengeText(c): string
	return c.text:format(c.need)
end

------------------------------------------------------------------ сезонный пропуск (бесплатный трек + косметика)
L.Season = {
	id = 1,
	name = "Сезон 1: Осенние фонари",
	ends = "до 31 декабря",
	tierXp = 150,
	-- опыт сезона: за поимку по редкости, за испытания (выше)
	catchXp = { common = 4, uncommon = 6, rare = 10, epic = 18, legendary = 35, mythic = 60, secret = 120 },
}
L.Season.tiers = {
	{ coins = 150 }, { dust = 8 }, { coins = 250 }, { potion = 5 }, { skin = "autumn" },
	{ coins = 400 }, { dust = 15 }, { coins = 500 }, { potion = 10 }, { title = "Осенний ловец" },
	{ coins = 700 }, { dust = 25 }, { coins = 900 }, { potion = 10 }, { skin = "maple" },
	{ coins = 1200 }, { dust = 35 }, { coins = 1500 }, { potion = 15 }, { title = "Хранитель листопада" },
	{ coins = 2000 }, { dust = 50 }, { coins = 2500 }, { potion = 15 }, { skin = "harvest" },
	{ coins = 3000 }, { dust = 70 }, { coins = 4000 }, { potion = 20 }, { skin = "aurora", title = "Легенда сезона" },
}
-- премиум-трек (покупка «Премиум сезона 1»): только косметика
L.Season.premium = {
	[3] = { skin = "lotus" }, [6] = { furniture = "koiPond" }, [9] = { title = "Звёздный ловец" },
	[12] = { skin = "starlight" }, [15] = { furniture = "shrine" }, [18] = { title = "Хозяин тумана" },
	[21] = { skin = "phoenix" }, [24] = { furniture = "spiritStatue" }, [27] = { title = "Повелитель фонарей" },
	[30] = { skin = "eclipse" },
}

function L.rewardText(r): string
	local parts = {}
	if r.coins then table.insert(parts, r.coins .. " монет") end
	if r.dust then table.insert(parts, r.dust .. " пыли") end
	if r.potion then table.insert(parts, "удача x2 на " .. r.potion .. " мин") end
	if r.skin then table.insert(parts, "фонарь") end
	if r.title then table.insert(parts, "титул «" .. r.title .. "»") end
	if r.furniture then table.insert(parts, "мебель «" .. L.Furniture[r.furniture].name .. "»") end
	return table.concat(parts, " + ")
end

------------------------------------------------------------------ рейтинг недели «Редчайший улов»
-- очки улова = вес редкости x шанс разновидности (1 к N)
L.RarityScore = { common = 1, uncommon = 2, rare = 5, epic = 12, legendary = 30, mythic = 80, secret = 200 }
function L.week(t: number): number
	return math.floor((t + 3 * 86400) / 604800) -- неделя с понедельника
end

------------------------------------------------------------------ рейд «Тысяча фонарей»
-- над улицей появляется Великий фонарный дух. Все светят на него фонарями: каждый удар — зажжённый фонарик.
-- Если сервер зажжёт нужное число фонариков за время рейда, все участники получают награду.
L.Raid = {
	first = 360, every = 900, duration = 100, -- секунды
	perPlayer = 220, minGoal = 250, maxGoal = 1000,
	radius = 75, hitEvery = 0.2,
	reward = { coins = 500, dust = 25, sxp = 200 }, perLantern = 3, -- монет за каждый свой фонарик
	failShare = 0.3, -- доля награды, если не успели
}
function L.raidGoal(players: number): number
	return math.clamp(L.Raid.perPlayer * players, L.Raid.minGoal, L.Raid.maxGoal)
end

------------------------------------------------------------------ альбом редких поимок
L.AlbumMax = 40
L.AlbumMinRarity = "epic" -- эпические и выше всегда попадают в альбом
L.AlbumMinOdds = 25 -- и любые разновидности от 1 к 25 (блестящий и реже)

------------------------------------------------------------------ эволюция духов
-- 10 дубликатов + пыль: вид становится «Пробуждённым» (крупнее, с сиянием),
-- его способность спутника x1.5, монеты за этот вид x1.5
L.EvolveDupes = 10
L.EvolveDust = { common = 10, uncommon = 20, rare = 35, epic = 60, legendary = 100, mythic = 160, secret = 250 }
L.EvolvedMult = 1.5

------------------------------------------------------------------ мебель для двора
-- slot = место на участке (x вправо, z к выходу; зеркалится для верхнего ряда)
L.FurnitureOrder = { "goldPagoda", "moonGate", "lanternPost", "bench", "bonsai", "stoneGarden", "sakura", "garland", "bell", "bridge", "torii", "fountain", "koiPond", "shrine", "spiritStatue" }
L.Furniture = {
	lanternPost = { name = "Фонарный столб", coins = 300, slot = Vector3.new(-20, 0, -20) },
	bench = { name = "Скамейка", coins = 400, slot = Vector3.new(-14, 0, 2) },
	bonsai = { name = "Бонсай", coins = 600, slot = Vector3.new(20, 0, -6) },
	stoneGarden = { name = "Сад камней", coins = 700, slot = Vector3.new(-16, 0, -8) },
	sakura = { name = "Сакура", coins = 800, slot = Vector3.new(19, 0, 10) },
	garland = { name = "Гирлянда фонарей", coins = 900, slot = Vector3.new(0, 0, 8) },
	bell = { name = "Колокол", coins = 1000, slot = Vector3.new(-20, 0, 12) },
	bridge = { name = "Мостик", coins = 1200, slot = Vector3.new(0, 0, -6) },
	torii = { name = "Тории", coins = 1500, dust = 20, slot = Vector3.new(0, 0, -22) },
	fountain = { name = "Фонтан духов", coins = 2000, dust = 30, slot = Vector3.new(10, 0, -14) },
	goldPagoda = { name = "Золотая пагода", coins = 100000, slot = Vector3.new(21, 0, -21) },
	moonGate = { name = "Лунные врата", coins = 300000, slot = Vector3.new(-12, 0, -23) },
	koiPond = { name = "Пруд с карпами", premium = true, slot = Vector3.new(-6, 0, -14) },
	shrine = { name = "Святилище", premium = true, slot = Vector3.new(14, 0, 16) },
	spiritStatue = { name = "Статуя духа", premium = true, slot = Vector3.new(-13, 0, 17) },
}

------------------------------------------------------------------ сюжет: задания Хранителя алтаря (NPC у алтаря)
-- type: kind (поймать вид), district (поймать в районе), rarity (редкость min и выше), variant (необычные разновидности),
--       deliver (сдать банки), raid (участие в рейде), boss (победа над ночным стражем), evolve (пробуждение)
L.Story = {
	{ title = "Первый свет", type = "kind", kind = "PaperFox", need = 3, coins = 150,
		say = "Фонари гаснут, ловец. Бумажные лисы прячутся у фонарей улицы. Принеси мне троих." },
	{ title = "Банка полна", type = "deliver", need = 3, coins = 200,
		say = "Духи в банке скучают. Сдавай улов у алтаря: так они находят дорогу домой." },
	{ title = "Голоса воды", type = "district", district = "canal", need = 5, coins = 300, dust = 10,
		say = "У канала слышен плеск. Там живут духи воды. Поймай пятерых." },
	{ title = "Ночной рынок", type = "district", district = "market", need = 6, coins = 400,
		say = "На рынке духи воруют фонарики с прилавков. Шесть воришек ждут тебя." },
	{ title = "Редкий гость", type = "rarity", min = "rare", need = 3, coins = 500, dust = 15,
		say = "Простые духи тебе уже не страшны. Найди трёх редких или лучше." },
	{ title = "Тысяча огней", type = "raid", need = 1, coins = 600,
		say = "Когда над улицей поднимется Великий фонарный дух, свети вместе со всеми." },
	{ title = "Страж ночи", type = "boss", need = 1, coins = 800, dust = 25,
		say = "Ночью в районах просыпаются стражи. Одолей одного вместе с другими ловцами." },
	{ title = "Сила дубликатов", type = "evolve", need = 1, coins = 1000,
		say = "Десять одинаковых духов могут стать одним пробуждённым. Попробуй в Атласе." },
	{ title = "Туман над портом", type = "district", district = "port", need = 5, coins = 1200, dust = 30,
		say = "В порту туман прячет морских духов. Пятеро из них нужны мне." },
	{ title = "Сияние", type = "variant", need = 3, coins = 1500,
		say = "Иногда духи сияют: золотом, радугой, тенью. Поймай три необычные разновидности." },
	{ title = "Отражения", type = "district", district = "mirror", need = 5, coins = 2000, dust = 50,
		say = "Есть озеро, где духов видно только в воде. Посвети в отражение и поймай пятерых." },
	{ title = "Хранитель", type = "kind", kind = "GlassHeron", need = 1, coins = 3000, dust = 100, title2 = "Ученик Хранителя",
		say = "Последнее испытание: Стеклянная цапля. Поймаешь её, и станешь моим учеником." },
}

-- короткая цель главы для плашки на экране
function L.storyGoal(ch, kinds, districts): string
	if ch.type == "kind" then return "Поймай: " .. (kinds[ch.kind] and kinds[ch.kind].name or ch.kind) end
	if ch.type == "district" then return "Лови духов: " .. (districts[ch.district] and districts[ch.district].name or ch.district) end
	if ch.type == "rarity" then return "Поймай редких духов или лучше" end
	if ch.type == "variant" then return "Поймай необычные разновидности" end
	if ch.type == "deliver" then return "Сдай банки у алтаря" end
	if ch.type == "raid" then return "Помоги в рейде «Тысяча фонарей»" end
	if ch.type == "boss" then return "Победи ночного стража" end
	if ch.type == "evolve" then return "Пробуди духа в Атласе" end
	return ch.title
end

------------------------------------------------------------------ ночные стражи: мини-босс в районе
L.Boss = {
	every = 420, first = 200, duration = 120, radius = 45, hitEvery = 0.2,
	hpPerPlayer = 90, minHp = 120, maxHp = 700,
	reward = { coins = 350, dust = 15, sxp = 120 },
	list = {
		street = { kind = "BellTanuki", name = "Тануки-великан" },
		canal = { kind = "Kappa", name = "Каппа-страж" },
		market = { kind = "LuckyCat", name = "Кот-ростовщик" },
		grove = { kind = "TenguMask", name = "Тэнгу рощи" },
		garden = { kind = "Kyubi", name = "Девятихвостая тень" },
		port = { kind = "LighthouseOwl", name = "Сова маяка" },
		mirror = { kind = "GlassHeron", name = "Хрустальная цапля" },
	},
}

------------------------------------------------------------------ праздники: лимитированные духи
-- from/to = { месяц, день } включительно; период может переходить через Новый год
L.Holidays = {
	{ id = "halloween", name = "Ночь тыкв", from = { 10, 20 }, to = { 11, 5 }, kind = "PumpkinLantern" },
	{ id = "autumn", name = "Осенний фестиваль", from = { 11, 1 }, to = { 11, 30 }, kind = "MapleSpirit" },
	{ id = "newyear", name = "Новогодние огни", from = { 12, 15 }, to = { 1, 15 }, kind = "SnowSpirit" },
}
L.HolidayChance = 0.07 -- доля появлений праздничного духа в районах
function L.activeHolidays(t: number)
	local d = os.date("!*t", t)
	local now = d.month * 100 + d.day
	local out = {}
	for _, h in L.Holidays do
		local a, b = h.from[1] * 100 + h.from[2], h.to[1] * 100 + h.to[2]
		if (a <= b and now >= a and now <= b) or (a > b and (now >= a or now <= b)) then table.insert(out, h) end
	end
	return out
end

------------------------------------------------------------------ забеги спутников
-- запись открывает лобби на 20 с; если игроков меньше 4, добавляются духи-соперники
L.Race = {
	lobby = 20, length = 100, tick = 0.25, cheerEvery = 2, cheerBoost = 1.2,
	rivals = { { name = "Лис соседа", kind = "PaperFox", speed = 3.2 }, { name = "Кот с рынка", kind = "LuckyCat", speed = 3.4 }, { name = "Тануки-бегун", kind = "BellTanuki", speed = 3.1 } },
	prizes = { { coins = 400, dust = 12 }, { coins = 200, dust = 6 }, { coins = 100, dust = 3 } }, participation = { coins = 40 },
	dailyPrizes = 12, -- забегов с наградой в день
}
-- скорость спутника в забеге: редкость, уровень и пробуждение
function L.raceSpeed(rarity: string, level: number, evolved: boolean): number
	return 2.6 + (L.RarityPower[rarity] or 1) * 0.35 + level * 0.08 + (evolved and 0.4 or 0)
end

------------------------------------------------------------------ войны клубов (недельный рейтинг клубов по поимкам)
L.ClubWar = {
	prizes = {
		{ coins = 5000, dust = 150, title = "Чемпион клубов" },
		{ coins = 3000, dust = 90 },
		{ coins = 1500, dust = 50 },
	},
}

------------------------------------------------------------------ траты монет: святилище удачи, обмен на пыль, призыв духа, зелье
L.CoinShop = {
	shrineMax = 50, shrinePer = 0.02, -- +2% удачи за уровень святилища (до +100%)
	exchangeRate = 120, -- монет за 1 пыль
	summonBase = 3000, summonPerLevel = 150, -- призыв редкого духа рядом с тобой
	potionCoins = 12000, -- зелье удачи x2 на 15 минут за монеты
}
function L.shrineCost(level: number): number
	return math.floor(3000 * 1.28 ^ level)
end
function L.summonCost(level: number): number
	return L.CoinShop.summonBase + level * L.CoinShop.summonPerLevel
end

------------------------------------------------------------------ причины вернуться завтра
-- серия входов: удача +5% за каждый день подряд (до +50%), пропуск дня сбрасывает серию
L.Streak = { per = 0.05, max = 10 }
-- колесо удачи: 1 бесплатное вращение в день (VIP: 2)
L.WheelPrizes = {
	{ id = "coinsS", w = 28, name = "Монеты", icon = "coin", color = Color3.fromRGB(255, 200, 60) },
	{ id = "dustS", w = 20, name = "20 пыли", icon = "dust", color = Color3.fromRGB(180, 120, 255) },
	{ id = "potion", w = 15, name = "Зелье 10 мин", icon = "potion", color = Color3.fromRGB(90, 220, 120) },
	{ id = "coinsL", w = 12, name = "Много монет", icon = "coin", color = Color3.fromRGB(255, 160, 40) },
	{ id = "dustL", w = 8, name = "80 пыли", icon = "dust", color = Color3.fromRGB(140, 80, 255) },
	{ id = "egg", w = 8, name = "Лунное яйцо", icon = "moon", color = Color3.fromRGB(120, 170, 255) },
	{ id = "chest", w = 6, name = "Сундук", icon = "gift", color = Color3.fromRGB(255, 110, 90) },
	{ id = "skin", w = 3, name = "Фонарь «Фортуна»", icon = "luck", color = Color3.fromRGB(255, 120, 220) },
}
function L.wheelCoins(id: string, level: number): number
	if id == "coinsS" then return 300 + level * 40 end
	if id == "coinsL" then return 1500 + level * 150 end
	if id == "chest" then return 5000 + level * 400 end
	return 0
end
-- инкубатор: яйцо вылупляется через несколько часов; дух сразу идёт в коллекцию
L.EggOrder = { "lantern", "moon", "star" }
L.Eggs = {
	lantern = { name = "Фонарное яйцо", coins = 4000, hours = 1, luck = 1, color = Color3.fromRGB(255, 180, 90),
		weights = { common = 40, uncommon = 35, rare = 18, epic = 6, legendary = 1 } },
	moon = { name = "Лунное яйцо", coins = 25000, hours = 4, luck = 2, color = Color3.fromRGB(150, 190, 255),
		weights = { uncommon = 30, rare = 35, epic = 25, legendary = 8, mythic = 2 } },
	star = { name = "Звёздное яйцо", coins = 120000, hours = 12, luck = 4, color = Color3.fromRGB(255, 220, 120),
		weights = { rare = 30, epic = 40, legendary = 22, mythic = 7, secret = 1 } },
}
L.EggSlots = 3
-- дух дня: чаще появляется и даёт x2 монет при сдаче
function L.spiritOfDay(day: number, order, kinds): string?
	local c = {}
	for _, k in order do
		local info = kinds[k]
		if info and not info.moonOnly and not info.holiday and info.move ~= "swim" and next(info.spawn) ~= nil then table.insert(c, k) end
	end
	if #c == 0 then return nil end
	return c[(day * 13 + 5) % #c + 1]
end
-- пока игрока нет, духи его двора собирают пыль (до 12 часов)
L.Offline = { maxHours = 12 }
function L.offlineDust(hours: number, distinct: number): number
	return math.floor(math.min(hours, L.Offline.maxHours) * (3 + distinct * 0.3))
end

-- награды за серию входов (выдаются при входе)
L.StreakRewards = {
	{ days = 3, coins = 1500, dust = 30, text = "3 дня подряд" },
	{ days = 7, coins = 5000, dust = 80, egg = "moon", title = "Верный ловец", text = "Неделя подряд" },
	{ days = 14, coins = 12000, dust = 150, egg = "star", text = "2 недели подряд" },
	{ days = 30, coins = 40000, dust = 400, egg = "star", title = "Хранитель серии", text = "Месяц подряд" },
}
-- недельный сундук: 5 дней за неделю с выполненными всеми испытаниями дня
L.WeekChest = { days = 5, coins = 10000, perLevel = 300, dust = 150, egg = "moon" }
-- выходные: двойная удача в субботу и воскресенье (UTC)
function L.isWeekend(t: number): boolean
	local wd = os.date("!*t", t).wday
	return wd == 1 or wd == 7
end
-- охота за 3 минуты: поймай как можно больше, награда за каждого + рекорд
L.Hunt = { seconds = 180, coinsPer = 150, dustPer = 3 }
-- приглашение друга (по ссылке-приглашению Roblox)
L.Invite = { inviter = { coins = 2000, dust = 50 }, guest = { coins = 1000 } }

------------------------------------------------------------------ бросок фонарика: главный быстрый цикл
-- держишь кнопку, полоска силы ходит вверх-вниз, отпускаешь; чем точнее (q от 0 до 1), тем дальше и реже дух
L.Throw = {
	cooldown = 1.6, cooldownMin = 0.6, -- секунд; уменьшается с силой света
	baseDist = 18, maxDist = 70, -- метров
	rarityBoost = 0.9, -- насколько точный бросок поднимает редкие виды
	variantBoost = 1.5, -- и шанс разновидности
	flight = 0.9, -- секунд полёта фонарика
}
function L.throwQuality(q: number): string
	if q >= 0.94 then return "ИДЕАЛЬНО!" end
	if q >= 0.8 then return "Отлично!" end
	if q >= 0.55 then return "Хорошо" end
	return "Слабо"
end

------------------------------------------------------------------ Ритуал фонаря: «рискни или забери»
-- свет растёт, духи слетаются в рой; «Запечатать» забирает рой с множителем монет;
-- в случайный момент приходит Тьма и забирает незапечатанный рой. Перед Тьмой обычно бывает знак.
L.Ritual = {
	meanCrash = 22, minCrash = 3, -- секунд до Тьмы: в среднем 22, не раньше 3
	growth = 1.075, -- множитель света: growth ^ секунды (x2 за ~10 с, x5 за ~22 с, x10 за ~32 с)
	arriveEvery = 1.8, -- секунд между духами
	omenChance = 0.72, omenPerSense = 0.025, -- шанс настоящего знака перед Тьмой (+2.5% за ступень «Чутья»)
	omenLead = { 1.4, 3.2 }, -- за сколько секунд до Тьмы знак
	falseEvery = 11, -- в среднем раз в 11 с ложный знак (реже с «Чутьём»)
	rarityAt = 6, -- при множителе x7 прилетают самые редкие из района
}
function L.ritualMult(t: number): number
	return L.Ritual.growth ^ math.max(0, t)
end

------------------------------------------------------------------ Ритуал у алтаря за пыль: дороже = редче дух, но ниже шанс
-- при неудаче пыль сгорает, но шанс этого уровня растёт на pity до успеха
L.RitualOrder = { "small", "medium", "great", "forbidden" }
L.Rituals = {
	small = { name = "Малый ритуал", dust = 25, chance = 0.8, luck = 1.5, color = Color3.fromRGB(110, 190, 255),
		weights = { rare = 70, epic = 25, legendary = 5 } },
	medium = { name = "Средний ритуал", dust = 80, chance = 0.55, luck = 2, color = Color3.fromRGB(190, 120, 255),
		weights = { epic = 65, legendary = 30, mythic = 5 } },
	great = { name = "Великий ритуал", dust = 250, chance = 0.3, luck = 3, color = Color3.fromRGB(255, 190, 60),
		weights = { legendary = 70, mythic = 27, secret = 3 } },
	forbidden = { name = "Запретный ритуал", dust = 700, chance = 0.12, luck = 5, color = Color3.fromRGB(255, 70, 90),
		weights = { mythic = 70, secret = 30 } },
}
L.RitualPity = 0.05

------------------------------------------------------------------ ценность духов: инвентарь, команда, продажа
-- у каждого духа (вид + разновидность) есть СИЛА и ЦЕНА. Чем реже вид и разновидность, тем больше.
L.RarityPower = L.RarityPower or {}
L.PowerBase = { common = 1, uncommon = 2, rare = 4, epic = 8, legendary = 16, mythic = 32, secret = 64 }
function L.spiritPower(rarity: string, variantMult: number, evolved: boolean?): number
	return math.floor((L.PowerBase[rarity] or 1) * (variantMult or 1) * (evolved and 1.5 or 1) * 10 + 0.5)
end
-- команда: до N духов дают бонус к монетам и удаче (растёт медленнее силы, чтобы не ломать баланс)
L.TeamSlots = { base = 3, [15] = 4, [30] = 5, vip = 1 }
function L.teamSlots(level: number, vip: boolean): number
	local n = L.TeamSlots.base
	if level >= 15 then n = 4 end
	if level >= 30 then n = 5 end
	return n + (vip and L.TeamSlots.vip or 0)
end
function L.teamBonus(power: number): number -- проценты к монетам от одного духа
	return math.floor(12 * math.log(1 + power / 10, 2) + 0.5)
end
-- цена продажи дубликата
function L.sellPrice(rarityCoins: number, variantMult: number): number
	return math.floor(rarityCoins * (variantMult or 1) * 4)
end

-- анимация ритуала у алтаря (секунд до результата)
L.RitualAnim = 3.2

return L
