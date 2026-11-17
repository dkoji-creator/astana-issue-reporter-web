-- Миры и районы. Новый мир добавляется сюда, его духи — в Config/Spirits.
-- Зона района: список прямоугольников { x = {min, max}, z = {min, max} } на уровне земли (y = 0.5).
local W = {}

W.Order = { "lantern", "mirror", "skymarket", "dreams" }

W.Worlds = {
	lantern = {
		name = "Квартал фонарей",
		active = true,
		blurb = "Улица бумажных фонарей, канал с мостами и храмовый сад. Во время Красной луны можно рискнуть уловом ради редкости.",
		search = "Иди по бумажным следам, проверяй мосты и сад",
		star = "Золотой карп, плывущий по воздуху над каналом",
	},
	mirror = {
		name = "Зеркальное озеро",
		active = false,
		blurb = "Духов сначала видно только в отражении. По кругам на воде угадываешь, где они вынырнут.",
		search = "Смотри в отражения и на круги на воде",
		star = "Стеклянная цапля, сквозь крылья которой видна луна",
	},
	skymarket = {
		name = "Небесный рынок",
		active = false,
		blurb = "Бумажные ленты летят по ветру и показывают, над какой крышей искать следующую тень.",
		search = "Следи за лентами на ветру",
		star = "Дракон из воздушных змеев с хвостом из флажков",
	},
	dreams = {
		name = "Архив снов",
		active = false,
		blurb = "Фонарь проявляет комнаты и проходы. Атлас хранит найденные подсказки, чтобы можно было вернуться и закончить поиск.",
		search = "Проявляй комнаты фонарём",
		star = "Чернильный кит, проплывающий сквозь книжные полки",
	},
}

W.Districts = {
	street = {
		world = "lantern", name = "Улица бумажных фонарей", max = 7,
		zones = { { x = { -14, 14 }, z = { 34, 124 } } },
		tint = Color3.fromRGB(255, 240, 225), center = Vector3.new(0, 0.5, 80),
	},
	plaza = {
		world = "lantern", name = "Площадь алтаря", max = 0,
		zones = {}, tint = Color3.fromRGB(235, 242, 255), center = Vector3.new(0, 0.5, 12),
	},
	canal = {
		world = "lantern", name = "Канал с мостами", max = 7,
		zones = { { x = { -56, 56 }, z = { -18, -11 } }, { x = { -56, 56 }, z = { -49, -42 } } },
		tint = Color3.fromRGB(225, 238, 255), center = Vector3.new(0, 0.5, -30),
		-- траектория для «плывущих» духов: эллипс над водой
		swim = { center = Vector3.new(0, 1.8, -30), rx = 22, rz = 6, speed = 0.3 },
	},
	garden = {
		world = "lantern", name = "Храмовый сад", max = 8,
		zones = { { x = { -38, 38 }, z = { -144, -80 } } },
		tint = Color3.fromRGB(232, 255, 236), center = Vector3.new(0, 0.5, -110),
		locked = true,
	},
}

function W.districtAt(z: number): string
	if z > 30 then
		return "street"
	elseif z > -8 then
		return "plaza"
	elseif z > -72 then
		return "canal"
	end
	return "garden"
end

return W
