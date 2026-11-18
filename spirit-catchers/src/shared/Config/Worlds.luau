-- Миры и районы. Новый мир добавляется сюда, его духи — в Config/Spirits.
-- Зона района: список прямоугольников { x = {min, max}, z = {min, max} } на уровне земли (y = 0.5).
local W = {}

-- Масштаб карты: все координаты ниже записаны «в старом размере» и умножаются на Scale по X и Z.
-- Высота земли остаётся 0.5. Map.luau масштабирует постройки так же (Y — вокруг уровня земли).
W.Scale = 1.6
function W.sp(v: Vector3): Vector3
	return Vector3.new(v.X * W.Scale, v.Y, v.Z * W.Scale)
end

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
		active = true,
		blurb = "Духов сначала видно только в отражении. По кругам на воде угадываешь, где они вынырнут.",
		search = "Смотри в отражения и на круги на воде",
		star = "Стеклянная цапля, сквозь крылья которой видна луна",
	},
	skymarket = {
		name = "Небесный рынок",
		active = true,
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

W.TeleportOrder = { "plaza", "street", "canal", "market", "grove", "garden", "port", "mirror", "skymarket", "yard" }

-- Районы открываются по уровню, в каждом следующем — более редкие духи и выше удача района.
-- habitats: «логова» района (теги), где духи прячутся и между которыми перебегают (точки строит Map.luau)
W.Districts = {
	plaza = {
		tp = Vector3.new(0, 3, 26), world = "lantern", name = "Площадь алтаря", max = 0, luck = 1,
		zones = {}, tint = Color3.fromRGB(235, 242, 255), center = Vector3.new(0, 0.5, 12),
	},
	street = {
		tp = Vector3.new(0, 3, 40), world = "lantern", name = "Улица бумажных фонарей", max = 6, luck = 1,
		zones = { { x = { -14, 14 }, z = { 34, 124 } } },
		tint = Color3.fromRGB(255, 240, 225), center = Vector3.new(0, 0.5, 80),
	},
	canal = {
		tp = Vector3.new(0, 3, -13), world = "lantern", name = "Канал с мостами", max = 6, luck = 1.2,
		zones = { { x = { -56, 56 }, z = { -18, -11 } }, { x = { -56, 56 }, z = { -49, -42 } } },
		tint = Color3.fromRGB(225, 238, 255), center = Vector3.new(0, 0.5, -30),
		swim = { center = Vector3.new(0, 1.8, -30), rx = 22, rz = 6, speed = 0.3 },
		unlock = { level = 3 }, gate = "CanalGate", back = Vector3.new(0, 4, 2),
	},
	market = {
		tp = Vector3.new(50, 3, 10), world = "lantern", name = "Ночной рынок", max = 8, luck = 1.5,
		zones = { { x = { 48, 140 }, z = { 2, 62 } } },
		tint = Color3.fromRGB(255, 232, 245), center = Vector3.new(95, 0.5, 32),
		unlock = { level = 6 }, gate = "MarketGate", back = Vector3.new(28, 4, 10),
	},
	grove = {
		tp = Vector3.new(-50, 3, 10), world = "lantern", name = "Бамбуковая роща", max = 8, luck = 2,
		zones = { { x = { -140, -48 }, z = { 2, 62 } } },
		tint = Color3.fromRGB(225, 255, 240), center = Vector3.new(-95, 0.5, 32),
		unlock = { level = 10 }, gate = "GroveGate", back = Vector3.new(-28, 4, 10),
	},
	garden = {
		tp = Vector3.new(0, 3, -84), world = "lantern", name = "Храмовый сад", max = 8, luck = 2.5,
		zones = { { x = { -38, 38 }, z = { -144, -80 } } },
		tint = Color3.fromRGB(232, 255, 236), center = Vector3.new(0, 0.5, -110),
		unlock = { level = 15 }, gate = "GardenBarrier", back = Vector3.new(0, 4, -64),
	},
	mirror = { -- второй мир: остров с озером за рощей; духов видно только в отражении
		tp = Vector3.new(-262, 3, -32), world = "mirror", name = "Зеркальное озеро", max = 8, luck = 3.5,
		zones = { { x = { -300, -224 }, z = { -12, 62 } } },
		tint = Color3.fromRGB(220, 235, 255), center = Vector3.new(-262, 0.5, 25),
		unlock = { level = 25 }, back = Vector3.new(0, 4, 26),
	},
	skymarket = { -- третий мир: крыши над облаками к востоку от рынка; ленты на ветру выдают духов
		tp = Vector3.new(265, 3, 30), world = "skymarket", name = "Небесный рынок", max = 9, luck = 4,
		zones = { { x = { 222, 308 }, z = { -13, 73 } } },
		tint = Color3.fromRGB(255, 240, 230), center = Vector3.new(265, 0.5, 30),
		unlock = { level = 30 }, back = Vector3.new(0, 4, 26),
	},
	yard = { -- остров дворов игроков (за улицей фонарей); координаты в старом размере
		tp = Vector3.new(0, 3, 266), world = "lantern", name = "Дворы ловцов", max = 0, luck = 1,
		zones = {}, tint = Color3.fromRGB(240, 245, 230), center = Vector3.new(0, 0.5, 304),
	},
	port = {
		tp = Vector3.new(78, 3, -47), world = "lantern", name = "Туманный порт", max = 8, luck = 3,
		zones = { { x = { 70, 124 }, z = { -66, -14 } } },
		tint = Color3.fromRGB(215, 235, 245), center = Vector3.new(100, 0.5, -40),
		-- над морем: парящие духи кружат вокруг маяка
		swim = { center = Vector3.new(150, 3, -40), rx = 14, rz = 22, speed = 0.22 },
		unlock = { level = 20 }, gate = "PortGate", back = Vector3.new(56, 4, -47),
	},
}

-- перевод координат районов в масштаб карты
for _, d in W.Districts do
	for _, k in { "tp", "center", "back" } do
		if d[k] then d[k] = W.sp(d[k]) end
	end
	for _, zn in d.zones do
		zn.x = { zn.x[1] * W.Scale, zn.x[2] * W.Scale }
		zn.z = { zn.z[1] * W.Scale, zn.z[2] * W.Scale }
	end
	if d.swim then
		d.swim.center = W.sp(d.swim.center)
		d.swim.rx *= W.Scale
		d.swim.rz *= W.Scale
	end
end

-- район по позиции (x, z); пороги — в старом размере
function W.districtAt(pos: Vector3): string
	local x, z = pos.X / W.Scale, pos.Z / W.Scale
	if z > 245 then return "yard" end
	if x < -190 then return "mirror" end
	if x > 190 then return "skymarket" end
	if x > 63 and z < -8 and z > -73 then return "port" end
	if z > -8 and z < 72 then
		if x < -36 then return "grove" end
		if x > 36 then return "market" end
	end
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
