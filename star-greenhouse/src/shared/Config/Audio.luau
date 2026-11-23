-- Звуки игры из официальной библиотеки Roblox (авторы Roblox и APMOfficial). Такие звуки разрешены
-- во всех играх без настройки доступа. Свои синтезированные звуки (art/audio, tools/make_sfx.py)
-- лежат в Custom: они заработают, только если в Creator Hub выдать игре доступ к каждому звуку.
return {
	Music = {
		main = "rbxassetid://1848056295", -- Бетховен, «Лунная соната», 1-я часть (рояль, APM)
		space = "rbxassetid://9042041852", -- Calm Space (APM)
	},
	Sfx = {
		click = "rbxassetid://15675032796", -- Roblox_UI_Small_Click
		pop = "rbxassetid://15675055424", -- Roblox_UI_Cute_Pop
		tap = "rbxassetid://15675059323", -- Roblox_UI_Bright_Click
		error = "rbxassetid://15675075163", -- Roblox_UI_Delete
		coins = "rbxassetid://127645268874265", -- CoinTransfer_01
		plant = "rbxassetid://12222124", -- Short spring sound
		water = "rbxassetid://17208204604", -- Roblox GUI - Bubble
		harvest = "rbxassetid://15675043410", -- Roblox_UI_Tonal_Stinger
		harvestRare = "rbxassetid://1839901334", -- Space Chimes
		star = "rbxassetid://1839901334", -- Space Chimes
		meteor = "rbxassetid://12222095", -- Rocket whoosh 01
		boom = "rbxassetid://12222030", -- HalloweenThunder
		laser = "rbxassetid://1841352043", -- Fierce Energy Blast 2
		rocket = "rbxassetid://12222095", -- Rocket whoosh 01
		go = "rbxassetid://12222065", -- Launching rocket
		beep = "rbxassetid://15675085146", -- Roblox_UI_Indicator
		whoosh = "rbxassetid://15675024286", -- Roblox_UI_Whoosh_01
		unlock = "rbxassetid://12222253", -- victory
		reveal = "rbxassetid://1839901345", -- Powered Up Chimes
		mutation = "rbxassetid://1839901345", -- Powered Up Chimes
		legendary = "rbxassetid://1836789962", -- Feeling Like A Winner (sting)
		chest = "rbxassetid://12222253", -- victory
		brew = "rbxassetid://108306323478967", -- Whoosh Magic Spell
	},
	-- громкость отдельных звуков (по умолчанию 1)
	Gain = { meteor = 0.35, boom = 0.7, laser = 0.6, rocket = 0.9, legendary = 0.8, brew = 0.8, star = 0.7, harvestRare = 0.8 },
	Custom = {
		music = "rbxassetid://120589657844865", space = "rbxassetid://72330274258040",
	},
}
