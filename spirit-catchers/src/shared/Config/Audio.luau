-- Идентификаторы звуков. Пустая строка — звук не проигрывается.
-- Файлы синтезированы для игры (spirit-catchers/audio), загружаются через Open Cloud.
return {
	Music = {
		lantern = "rbxassetid://79093164547792", -- фортепианная прелюдия (Бах, BWV 846, общественное достояние)
		moonLayer = "rbxassetid://89905665544665", -- низкий ритм Красной луны поверх той же темы
	},
	Sfx = {
		reveal = "rbxassetid://129278619124909",
		catch = "rbxassetid://91148289964123",
		catchRare = "rbxassetid://120882152440325",
		save = "rbxassetid://92669416688338",
		legendary = "rbxassetid://75037825103139",
		oniWarn = "rbxassetid://126025187001826",
		oniHit = "rbxassetid://137487659423309",
		click = "rbxassetid://88424807868026",
	},
	-- звук рядом с редким духом (слышен за углом)
	Spirit = {
		BellTanuki = "rbxassetid://134083503565408",
		Crane = "rbxassetid://86259667052322",
		InkSnake = "rbxassetid://136390755864463",
		MoonRabbit = "rbxassetid://96892450235597",
		FoxFire = "rbxassetid://101635609702611",
		GoldenCarp = "rbxassetid://139447579742528",
	},
}
