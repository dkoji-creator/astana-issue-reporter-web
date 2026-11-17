-- Фасад конфигураций для сервера и клиента.
local Config = script.Parent:WaitForChild("Config")
local Worlds = require(Config:WaitForChild("Worlds"))
local SpiritCfg = require(Config:WaitForChild("Spirits"))
local Economy = require(Config:WaitForChild("Economy"))
local Progress = require(Config:WaitForChild("Progress"))

local C = {}
C.Worlds = Worlds
C.Order = SpiritCfg.Order
C.Kinds = SpiritCfg.Kinds
C.ConditionText = SpiritCfg.ConditionText
C.Rarity = Economy.Rarity
C.RarityOrder = Economy.RarityOrder
C.Upgrades = Economy.Upgrades
C.UpgradeOrder = Economy.UpgradeOrder
C.MaxLevel = Economy.MaxLevel
C.GardenNeed = Economy.GardenNeed
C.OrderSlots = Economy.OrderSlots
C.Progress = Progress
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
