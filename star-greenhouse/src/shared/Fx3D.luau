-- Объёмные детали спецэффектов: клоны мешей из ReplicatedStorage.FxMeshes (кольца, кристаллы, осколки, звёзды, спираль,
-- ударная волна, корона). Размеры задаются в «естественных» единицах формы; если мешей нет — возвращается nil.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Fx = {}
-- габариты меша при масштабе 1 (см. tools/fx/build_fx.py)
local BOX = {
	Ring = Vector3.new(2.07, 0.07, 2.07),
	RingBold = Vector3.new(2.18, 0.18, 2.18),
	Gem = Vector3.new(1.1, 2, 0.95),
	Shard = Vector3.new(0.44, 2.2, 0.42),
	Star = Vector3.new(2, 2, 0.32),
	Helix = Vector3.new(2.11, 2.5, 2.11),
	Shock = Vector3.new(2, 0.06, 2),
	Crown = Vector3.new(2.12, 0.6, 2.12),
}
Fx.Box = BOX

function Fx.ready(): boolean
	local root = ReplicatedStorage:FindFirstChild("FxMeshes")
	return root ~= nil and #root:GetChildren() > 0
end

-- name: форма, scale: число или Vector3 (множители к габаритам), color, material, transparency
function Fx.part(name: string, scale, color: Color3, material: Enum.Material?, transparency: number?): BasePart?
	local root = ReplicatedStorage:FindFirstChild("FxMeshes")
	local t = root and root:FindFirstChild(name)
	if not t then return nil end
	local p = t:Clone()
	local s = typeof(scale) == "Vector3" and scale or Vector3.new(scale, scale, scale)
	p.Size = BOX[name] * s
	p.Color = color
	p.Material = material or Enum.Material.Neon
	p.Transparency = transparency or 0
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	return p
end

-- кольцо радиуса r с толщиной трубки ~ r * 0.07 (bold — толще)
function Fx.ring(r: number, color: Color3, bold: boolean?, transparency: number?): BasePart?
	local name = bold and "RingBold" or "Ring"
	return Fx.part(name, r, color, Enum.Material.Neon, transparency)
end

return Fx
