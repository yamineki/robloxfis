--[[
	GamePassService.lua  (ServerScriptService)
	Проверяет владение Game Pass и применяет их постоянные эффекты.

	Использует MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId) —
	это официальный способ Roblox проверять владение пассом.
	См. Roblox Creator Docs: Monetization > Game Passes.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local GamePassService = {}

-- Кэш, чтобы не дёргать API каждый раз заново в текущей сессии
local ownershipCache = {} -- [userId][gamePassKey] = true/false

local function checkOwnership(player, gamePassKey, gamePassId)
	if gamePassId == 0 then
		-- Пасс ещё не создан на сайте (TODO в конфиге). Не ломаем игру, просто считаем "не куплен".
		return false
	end

	ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
	local cached = ownershipCache[player.UserId][gamePassKey]
	if cached ~= nil then
		return cached
	end

	local success, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, gamePassId)
	end)

	if not success then
		warn("[GamePassService] Ошибка проверки пасса", gamePassKey, "для", player.Name)
		return false
	end

	ownershipCache[player.UserId][gamePassKey] = owns
	return owns
end

-- Применяет эффекты пасса к профилю игрока (постоянные изменения сохранённых данных)
local function applyPerks(player, profile, gamePassKey, passInfo)
	local perks = passInfo.Perks
	if not perks then return end

	if perks.UnlocksBuilding then
		local already = false
		for _, id in ipairs(profile.UnlockedBuildings) do
			if id == perks.UnlocksBuilding then already = true break end
		end
		if not already then
			table.insert(profile.UnlockedBuildings, perks.UnlocksBuilding)
		end
	end

	if perks.InventorySlotsBonus then
		-- Бонус слотов фиксируем один раз через флаг во владении, не плюсуем на каждый вход
		profile.OwnedGamePasses[gamePassKey] = true
	end

	if perks.CharacterSkinId then
		profile.CosmeticsEquipped.CharacterSkinId = profile.CosmeticsEquipped.CharacterSkinId
			or perks.CharacterSkinId
	end

	if perks.ToolSkinId then
		profile.CosmeticsEquipped.ToolSkinId = profile.CosmeticsEquipped.ToolSkinId
			or perks.ToolSkinId
	end

	profile.OwnedGamePasses[gamePassKey] = true
end

-- Считает суммарный бонус к ценности улова от всех пассов, которыми владеет игрок
function GamePassService.GetCatchValueBonus(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end

	local bonus = 0
	for key, owned in pairs(profile.OwnedGamePasses) do
		if owned then
			local passInfo = MonetizationConfig.GamePasses[key]
			if passInfo and passInfo.Perks and passInfo.Perks.CatchValueBonus then
				bonus += passInfo.Perks.CatchValueBonus
			end
		end
	end
	return bonus
end

-- Считает суммарный бонус слотов инвентаря от пассов
function GamePassService.GetInventorySlotBonus(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end

	local bonus = 0
	for key, owned in pairs(profile.OwnedGamePasses) do
		if owned then
			local passInfo = MonetizationConfig.GamePasses[key]
			if passInfo and passInfo.Perks and passInfo.Perks.InventorySlotsBonus then
				bonus += passInfo.Perks.InventorySlotsBonus
			end
		end
	end
	return bonus
end

-- Вызывается при заходе игрока: сверяет все пассы и применяет их разово
function GamePassService.RefreshAllPasses(player)
	local profile = DataService.Get(player)
	if not profile then return end

	for gamePassKey, passInfo in pairs(MonetizationConfig.GamePasses) do
		local owns = checkOwnership(player, gamePassKey, passInfo.Id)
		if owns then
			applyPerks(player, profile, gamePassKey, passInfo)
		end
	end
end

-- Подписка на покупку пасса прямо во время игры (всплывающее окно покупки)
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, gamePassId, wasPurchased)
	if not wasPurchased then return end

	-- Находим, какому ключу конфига соответствует купленный Id
	for gamePassKey, passInfo in pairs(MonetizationConfig.GamePasses) do
		if passInfo.Id == gamePassId then
			ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
			ownershipCache[player.UserId][gamePassKey] = true

			local profile = DataService.Get(player)
			if profile then
				applyPerks(player, profile, gamePassKey, passInfo)
			end

			SoundService.PlayToPlayer("GamePassPurchased", player)
			break
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	ownershipCache[player.UserId] = nil
end)

function GamePassService.PromptPurchase(player, gamePassKey)
	local passInfo = MonetizationConfig.GamePasses[gamePassKey]
	if not passInfo or passInfo.Id == 0 then
		warn("[GamePassService] Попытка купить несуществующий/ненастроенный пасс:", gamePassKey)
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, passInfo.Id)
end

return GamePassService
