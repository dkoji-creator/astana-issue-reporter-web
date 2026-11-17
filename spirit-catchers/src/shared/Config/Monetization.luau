-- Донат: геймпассы (навсегда) и товары (можно покупать много раз). Цены до 199 Robux (~2$).
-- id — геймпасс (0 = нет), product — донат-товар с покупкой навсегда (сохраняется в профиле).
-- Товары: id — донат-товар Roblox.
local M = {}

M.PassOrder = { "vip", "coins2x", "bigjar", "lucky", "wideBeam" }
M.Passes = {
	vip = {
		id = 0, product = 3732892769, price = 199, icon = "level", color = Color3.fromRGB(255, 190, 40),
		name = "VIP-ловец", desc = "Радужный фонарь: звёзды, радужный шлейф, ореол и салют при поимке. Табличка VIP и +25% монет",
	},
	coins2x = {
		id = 0, product = 3732892783, price = 149, icon = "coin", color = Color3.fromRGB(240, 180, 30),
		name = "x2 Монеты", desc = "Все монеты за сданных духов удваиваются",
	},
	bigjar = {
		id = 0, product = 3732892804, price = 129, icon = "jar", color = Color3.fromRGB(90, 170, 255),
		name = "Огромная банка", desc = "+5 мест в банке навсегда",
	},
	lucky = {
		id = 0, product = 3732892821, price = 99, icon = "dust", color = Color3.fromRGB(170, 110, 255),
		name = "Удача ловца", desc = "Удача x1.5 навсегда: чаще редкие разновидности",
	},
	wideBeam = {
		id = 0, product = 3732892835, price = 79, icon = "target", color = Color3.fromRGB(80, 210, 140),
		name = "Широкий луч", desc = "Зелёная зона в мини-игре ловли на 40% больше",
	},
}

M.ProductOrder = { "luckPotion", "summonMoon", "fireworks" }
M.Products = {
	luckPotion = {
		id = 3732895300, price = 25, icon = "potion", color = Color3.fromRGB(90, 220, 120),
		name = "Зелье удачи x2", desc = "Удача x2 на 15 минут (время складывается)",
	},
	summonMoon = {
		id = 3732892660, price = 49, icon = "moon", color = Color3.fromRGB(230, 60, 70),
		name = "Призвать Красную луну", desc = "Красная луна начнётся сразу для всего сервера (если уже идёт, продлится на 30 с)",
	},
	fireworks = {
		id = 3732892697, price = 15, icon = "gift", color = Color3.fromRGB(255, 120, 190),
		name = "Фейерверк", desc = "Салют над площадью для всех игроков с вашим именем",
	},
}

M.VipCoinBonus = 1.25
M.LuckyChance = 0.15
M.BigJarBonus = 5
M.WideBeamBonus = 1.4

return M
