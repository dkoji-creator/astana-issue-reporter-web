-- Фасад конфигураций для сервера и клиента.
local Config = script.Parent:WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))
local SpiritCfg = require(Config:WaitForChild("Spirits"))
local Economy = require(Config:WaitForChild("Economy"))
local Progress = require(Config:WaitForChild("Progress"))
local Monetization = require(Config:WaitForChild("Monetization"))

local C = {}
C.Worlds = Worlds
C.Order = SpiritCfg.Order
C.Kinds = SpiritCfg.Kinds
C.ConditionText = SpiritCfg.ConditionText
C.Rarity = Economy.Rarity
C.RarityOrder = Economy.RarityOrder
C.Struggle = Economy.Struggle
C.Variants = Economy.Variants
C.VariantOrder = Economy.VariantOrder
C.Luck = Economy.Luck
C.Upgrades = Economy.Upgrades
C.UpgradeOrder = Economy.UpgradeOrder
C.MaxLevel = Economy.MaxLevel
C.GardenNeed = Economy.GardenNeed
C.OrderSlots = Economy.OrderSlots
C.Progress = Progress
C.Money = Monetization
C.Districts = Worlds.Districts
C.district = Worlds.districtAt

C.DistrictNames = {}
for k, d in Worlds.Districts do
	C.DistrictNames[k] = d.name
end

function C.upgradeValue(key: string, lvl: number)
	return C.Upgrades[key].values[math.clamp(lvl, 1, C.MaxLevel)]
end

function C.catchRange(kind: string): number
	return C.Kinds[kind].move == "swim" and Economy.SwimCatchRange or Economy.CatchRange
end

-- открыт ли район для игрока: stats = { distinct, level }
function C.unlocked(district: string, stats): boolean
	local u = C.Districts[district] and C.Districts[district].unlock
	if not u then return true end
	if u.kinds and (stats.distinct or 0) < u.kinds then return false end
	if u.level and (stats.level or 1) < u.level then return false end
	return true
end
function C.unlockText(district: string, stats): string
	local u = C.Districts[district].unlock
	if u.kinds then return ("Сохрани %d разных духов: %d/%d"):format(u.kinds, math.min(stats.distinct or 0, u.kinds), u.kinds) end
	return ("Нужен уровень %d (сейчас %d)"):format(u.level, stats.level or 1)
end

-- районы, где встречается вид (по конфигу появления)
function C.districtsOf(kind: string)
	local list = {}
	for d in C.Kinds[kind].spawn do
		table.insert(list, d)
	end
	if C.Kinds[kind].move == "swim" then table.insert(list, "canal") end
	return list
end

return C
