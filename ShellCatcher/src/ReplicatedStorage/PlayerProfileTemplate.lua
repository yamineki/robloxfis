--[[
	PlayerProfileTemplate.lua
	Дефолтная структура данных игрока. Используется ProfileService/DataStore-обёрткой
	как "шаблон" — недостающие поля у старых сохранений достраиваются автоматически.
]]

local PlayerProfileTemplate = {

	Currency = {
		Shells = 0,
	},

	RebirthLevel = 0,

	UnlockedZones = { "reef" }, -- стартовая зона открыта всем

	UnlockedBuildings = { "shop_basic" },

	Inventory = {
		Slots = 30,       -- база, апгрейдится скиллами/геймпассом ExtraInventory
		Items = {},       -- { {Id=..., RarityId=..., Value=...}, ... }
	},

	Tools = {
		HarpoonNetLevel = 1,
		CrusherDrillLevel = 1,
	},

	-- Получил ли игрок обе пушки у NPC Quartermaster. Если true — при заходе
	-- инструменты возвращаются автоматически (ToolService.RestoreToolsIfOwned).
	ToolsGranted = false,

	-- Уровни узлов дерева навыков. Можно оставить пустым {} — UpgradeService читает
	-- значения как profile.UpgradeLevels[key] or 0, поэтому отсутствующие ключи = уровень 0.
	-- Перечислять все узлы вручную не нужно (и легко забыть при добавлении новых в дерево).
	UpgradeLevels = {},

	OwnedGamePasses = {}, -- кэш { [GamePassKey] = true }, обновляется при покупке/входе

	ActiveBoosts = {}, -- { [BoostType] = { Amount = .., ExpiresAt = unixTime } }

	CosmeticsEquipped = {
		CharacterSkinId = nil,
		ToolSkinId = nil,
	},

	Stats = {
		TotalCatches = 0,
		TotalShellsEarned = 0,
		PlayTimeSeconds = 0,
	},

	-- Защита от двойного начисления Developer Products: храним ID последних обработанных
	-- покупок прямо в сохранении игрока. ProcessReceipt сверяется с этим списком,
	-- так что даже при краше сервера или смене сервера покупка не начислится дважды.
	-- Храним ограниченное число последних ID (см. DeveloperProductService), чтобы не раздувать профиль.
	ProcessedReceipts = {}, -- массив строк PurchaseId, новые добавляются в конец
}

return PlayerProfileTemplate
