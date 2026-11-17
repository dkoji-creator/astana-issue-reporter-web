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
function L.rewardText(r): string
	local parts = {}
	if r.coins then table.insert(parts, r.coins .. " монет") end
	if r.dust then table.insert(parts, r.dust .. " пыли") end
	if r.potion then table.insert(parts, "удача x2 на " .. r.potion .. " мин") end
	if r.skin then table.insert(parts, "фонарь") end
	if r.title then table.insert(parts, "титул «" .. r.title .. "»") end
	return table.concat(parts, " + ")
end

return L
