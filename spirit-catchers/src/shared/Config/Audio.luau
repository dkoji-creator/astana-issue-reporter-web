-- Идентификаторы звуков. Пустая строка — звук не проигрывается.
-- Файлы синтезированы для игры (spirit-catchers/audio), загружаются через Open Cloud.
return {
	Music = {
		lantern = "", -- тема квартала: калимба, вода, колокольчики
		moonLayer = "", -- низкий ритм Красной луны поверх той же темы
	},
	Sfx = {
		reveal = "",
		catch = "",
		catchRare = "",
		save = "",
		legendary = "",
		oniWarn = "",
		oniHit = "",
		click = "",
	},
	-- звук рядом с редким духом (слышен за углом)
	Spirit = {
		BellTanuki = "",
		Crane = "",
		InkSnake = "",
		MoonRabbit = "",
		FoxFire = "",
		GoldenCarp = "",
	},
}
