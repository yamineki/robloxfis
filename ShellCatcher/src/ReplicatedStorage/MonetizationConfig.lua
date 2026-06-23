--[[
	MonetizationConfig.lua
	Список всех Game Pass и Developer Product для Shell Catcher.

	КАК ЭТО ИСПОЛЬЗОВАТЬ:
	1. Сначала публикуешь игру в Roblox (даже пустую — обязательно для создания пассов).
	2. На сайте: Creator Hub -> твоя игра -> Monetization -> Passes / Developer Products.
	3. Создаёшь каждый пасс/продукт, копируешь его числовой Id и вставляешь сюда вместо 0.
	4. Скрипты (GamePassService, ShopHandler) читают ID отсюда — больше менять нигде не нужно.

	ПРАВИЛО (см. Roblox Creator Docs):
	- Game Pass = разовая покупка, постоянный эффект (VIP, доп. слоты, скин, доступ).
	- Developer Product = покупка, которую можно повторять (валюта, бусты, реролл).
	Никогда не делай валюту геймпассом — игрок купит её только один раз и больше не сможет.
]]

local MonetizationConfig = {}

-- ============================================================
-- GAME PASSES (одна покупка = навсегда)
-- ============================================================
MonetizationConfig.GamePasses = {

	VIP = {
		Id = 0, -- TODO: вставить реальный GamePassId после создания на сайте
		Name = "VIP Pass",
		Price = 399,
		Description = "Доступ к VIP-зоне на острове, золотая рамка имени, +10% к ценности улова навсегда.",
		Perks = {
			CatchValueBonus = 0.10,
			UnlocksBuilding = "vip_zone",
			ChatTagColor = Color3.fromRGB(255, 215, 0),
		},
	},

	ExtraInventory = {
		Id = 0,
		Name = "Big Bag",
		Price = 149,
		Description = "Permanently +20 inventory slots.",
		Perks = {
			InventorySlotsBonus = 20,
		},
	},

	AutoSorterUnlock = {
		Id = 0,
		Name = "Auto-Sorter Access",
		Price = 249,
		Description = "Открывает AFK-машину (Auto-Sorter Dock) без накопления валюты на острове.",
		Perks = {
			UnlocksBuilding = "afk_dock",
		},
	},

	SkinWorkshopUnlock = {
		Id = 0,
		Name = "Skin Workshop Access",
		Price = 199,
		Description = "Открывает мастерскую скинов для инструментов и персонажа.",
		Perks = {
			UnlocksBuilding = "skin_workshop",
		},
	},

	-- Косметические скины — каждый отдельным пассом (так игрок видит весь список сразу в магазине игры)
	Skin_GoldenDiver = {
		Id = 0,
		Name = "Golden Diver Skin",
		Price = 299,
		Description = "Косметический скин персонажа. Без игровых преимуществ.",
		Perks = {
			CharacterSkinId = "golden_diver",
		},
	},

	Skin_NeonHarpoon = {
		Id = 0,
		Name = "Neon Harpoon Skin",
		Price = 179,
		Description = "Косметический скин для Harpoon Net. Без игровых преимуществ.",
		Perks = {
			ToolSkinId = "neon_harpoon",
		},
	},

	RebirthShortcutToken = {
		Id = 0,
		Name = "Rebirth Keepsake",
		Price = 449,
		Description = "При ребирте сохраняет 1 случайный геймпасс-косметику без повторной покупки (см. дизайн ребирта).",
		Perks = {
			KeepCosmeticOnRebirth = true,
		},
	},
}

-- ============================================================
-- DEVELOPER PRODUCTS (можно покупать многократно)
-- ============================================================
MonetizationConfig.DeveloperProducts = {

	Shells_Small = {
		Id = 0, -- TODO: вставить реальный ProductId
		Name = "120 Shells",
		Price = 49,
		GrantCurrency = 120,
	},

	Shells_Medium = {
		Id = 0,
		Name = "750 Shells",
		Price = 199,
		GrantCurrency = 750, -- бонус ~25% по сравнению с мелкой пачкой
	},

	Shells_Large = {
		Id = 0,
		Name = "2200 Shells",
		Price = 499,
		GrantCurrency = 2200,
	},

	DoubleCatchBoost_30min = {
		Id = 0,
		Name = "2x Catch Value — 30 min",
		Price = 79,
		BoostType = "CatchValueMultiplier",
		BoostAmount = 2.0,
		DurationSeconds = 30 * 60,
	},

	InstantAfkCollect = {
		Id = 0,
		Name = "Instant Auto-Sorter Collect",
		Price = 39,
		Description = "Мгновенно забирает текущий накопленный улов из AFK-машины без ожидания.",
	},

	RerollSilhouette = {
		Id = 0,
		Name = "Reroll Catch (x1)",
		Price = 25,
		Description = "Перебрасывает редкость ОДНОГО только что пойманного силуэта.",
	},

	RebirthSkip = {
		Id = 0,
		Name = "Rebirth Currency Top-Up (1000 Shells)",
		Price = 99,
		GrantCurrency = 1000,
		Description = "Не пропускает ребирт напрямую (это было бы pay-to-win), а просто докидывает валюту к накоплениям.",
	},
}

return MonetizationConfig
