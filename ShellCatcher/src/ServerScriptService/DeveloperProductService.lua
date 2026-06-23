--[[
	DeveloperProductService.lua  (ServerScriptService)
	Обрабатывает покупки Developer Products через MarketplaceService.ProcessReceipt.

	КРИТИЧЕСКИ ВАЖНО (по докам Roblox):
	- ProcessReceipt должен вернуть Enum.ProductPurchaseDecision.PurchaseGranted
	  ТОЛЬКО когда эффект уже гарантированно применён и сохранён.
	- Если функция не вернёт PurchaseGranted (упадёт с ошибкой, вернёт nil, зависнет),
	  Roblox повторит вызов позже — поэтому код должен быть идемпотентным
	  (повторный вызов с тем же purchaseId не должен начислить дважды).
	- На весь датастор-сервис должен быть только ОДИН ProcessReceipt на всю игру.
	  Нельзя назначать его в нескольких скриптах одновременно.
]]

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local DeveloperProductService = {}

-- Строим обратный индекс productId -> ключ конфига, для быстрого поиска в ProcessReceipt
local productIdToKey = {}
for key, info in pairs(MonetizationConfig.DeveloperProducts) do
	if info.Id ~= 0 then
		productIdToKey[info.Id] = key
	end
end

-- Идемпотентность через persistent-хранилище: обработанные PurchaseId записываются
-- в профиль игрока (profile.Stats.ProcessedReceipts) и сохраняются в DataStore.
-- Так двойное начисление невозможно даже при краше сервера или смене сервера —
-- при повторном ProcessReceipt мы видим, что покупка уже в списке профиля.
-- In-memory кэш используем только как быстрый фильтр в рамках сессии.
local MAX_STORED_RECEIPTS = 50 -- храним последние N покупок, чтобы профиль не раздувался

local function isReceiptProcessed(profile, purchaseId)
	for _, storedId in ipairs(profile.ProcessedReceipts) do
		if storedId == purchaseId then
			return true
		end
	end
	return false
end

local function markReceiptProcessed(profile, purchaseId)
	table.insert(profile.ProcessedReceipts, purchaseId)
	-- Обрезаем старые записи, оставляя только последние MAX_STORED_RECEIPTS
	while #profile.ProcessedReceipts > MAX_STORED_RECEIPTS do
		table.remove(profile.ProcessedReceipts, 1)
	end
end

local function grantProduct(player, productKey, productInfo)
	local profile = DataService.Get(player)
	if not profile then
		return false -- профиль не загружен — нельзя начислять, пусть Roblox повторит позже
	end

	if productInfo.GrantCurrency then
		profile.Currency.Shells += productInfo.GrantCurrency
		profile.Stats.TotalShellsEarned += productInfo.GrantCurrency
	end

	if productInfo.BoostType then
		profile.ActiveBoosts[productInfo.BoostType] = {
			Amount = productInfo.BoostAmount,
			ExpiresAt = os.time() + productInfo.DurationSeconds,
		}
	end

	if productKey == "InstantAfkCollect" then
		-- Сигнал AFK-сервису забрать накопленное немедленно.
		-- AfkSorterService слушает это поле и обрабатывает в своём цикле.
		profile.Stats.PendingInstantAfkCollect = true
	end

	if productKey == "RerollSilhouette" then
		profile.Stats.PendingRerollCharges = (profile.Stats.PendingRerollCharges or 0) + 1
	end

	SoundService.PlayToPlayer("ProductPurchased", player)
	return true
end

local function processReceipt(receiptInfo)
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Игрок уже вышел — Roblox повторит попытку позже, когда он зайдёт снова.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local profile = DataService.Get(player)
	if not profile then
		-- Профиль ещё не загружен — нельзя проверить идемпотентность и начислить.
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local purchaseId = tostring(receiptInfo.PurchaseId)

	-- Уже обработано (persistent-проверка) — подтверждаем без повторного начисления.
	if isReceiptProcessed(profile, purchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local productKey = productIdToKey[receiptInfo.ProductId]
	if not productKey then
		warn("[DeveloperProductService] Неизвестный ProductId:", receiptInfo.ProductId)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productInfo = MonetizationConfig.DeveloperProducts[productKey]
	local success, granted = pcall(grantProduct, player, productKey, productInfo)

	if success and granted then
		-- ВАЖНО: помечаем покупку обработанной И сохраняем профиль ДО возврата PurchaseGranted.
		-- Если сохранение упадёт — не возвращаем PurchaseGranted, и Roblox повторит позже,
		-- а так как начисление и пометка идут в одном профиле, повтор не задвоит валюту
		-- (на повторе isReceiptProcessed уже вернёт true после успешного сейва).
		markReceiptProcessed(profile, purchaseId)

		local saveOk = pcall(function()
			DataService.SaveForPlayer(player, false)
		end)

		if saveOk then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end

		-- Сохранение не удалось — откатываем пометку, чтобы повтор сработал чисто.
		warn("[DeveloperProductService] Не удалось сохранить покупку, Roblox повторит:", productKey)
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	warn("[DeveloperProductService] Не удалось начислить продукт", productKey, "для", player.Name)
	return Enum.ProductPurchaseDecision.NotProcessedYet
end

MarketplaceService.ProcessReceipt = processReceipt

function DeveloperProductService.PromptPurchase(player, productKey)
	local productInfo = MonetizationConfig.DeveloperProducts[productKey]
	if not productInfo or productInfo.Id == 0 then
		warn("[DeveloperProductService] Попытка купить несуществующий/ненастроенный продукт:", productKey)
		return
	end
	MarketplaceService:PromptProductPurchase(player, productInfo.Id)
end

return DeveloperProductService
