--[[
	InventoryService.lua  (ServerScriptService)
	Управляет слотами инвентаря: добавление пойманной добычи, проверка лимита,
	продажа в магазине на острове.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local GamePassService = require(script.Parent:WaitForChild("GamePassService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local InventoryStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryStateUpdate")

local InventoryService = {}

local function pushInventoryState(player)
	local profile = DataService.Get(player)
	if not profile then return end
	InventoryStateRemote:FireClient(player, profile.Inventory.Items, InventoryService.GetMaxSlots(player))
end

function InventoryService.GetMaxSlots(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end

	local base = UpgradeService.GetStatValue(player, "InventorySlots") or profile.Inventory.Slots
	local passBonus = GamePassService.GetInventorySlotBonus(player)
	return base + passBonus
end

function InventoryService.IsFull(player)
	local profile = DataService.Get(player)
	if not profile then return true end
	return #profile.Inventory.Items >= InventoryService.GetMaxSlots(player)
end

-- catchData = { CreatureId = "silhouette_01", RarityId = "Rare", BaseValue = 40 }
function InventoryService.AddCatch(player, catchData)
	local profile = DataService.Get(player)
	if not profile then return false end

	if InventoryService.IsFull(player) then
		return false, "inventory_full"
	end

	local rarityInfo
	for _, r in ipairs(GameConfig.Rarities) do
		if r.Id == catchData.RarityId then
			rarityInfo = r
			break
		end
	end

	local finalValue = catchData.BaseValue * (rarityInfo and rarityInfo.ValueMultiplier or 1)

	table.insert(profile.Inventory.Items, {
		CreatureId = catchData.CreatureId,
		RarityId = catchData.RarityId,
		Value = finalValue,
	})

	profile.Stats.TotalCatches += 1
	pushInventoryState(player)
	return true
end

-- Сдаёт всё содержимое инвентаря продавцу (Collector NPC): очищает инвентарь, считает
-- сумму, но НЕ начисляет её на счёт напрямую — она уходит в Сундук (см. CollectChest),
-- как в Shell Divers: продавец принимает добычу и перерабатывает в награды, которые
-- летят в сундук; настоящая валюта забирается отдельным явным действием у сундука.
-- Возвращает (заработанная_сумма, количество_проданных_предметов).
function InventoryService.SellAll(player)
	local profile = DataService.Get(player)
	if not profile then return 0, 0 end

	local itemCount = #profile.Inventory.Items
	if itemCount == 0 then return 0, 0 end

	local total = 0
	for _, item in ipairs(profile.Inventory.Items) do
		total += item.Value
	end

	-- Бонус геймпассов/ребирта/бустов применяется в момент продажи, не в момент поимки —
	-- так апгрейды чувствуются мгновенно даже на уже пойманной, но не проданной добыче.
	local catchBonus = 1 + GamePassService.GetCatchValueBonus(player)
	local rebirthBonus = 1 + (profile.RebirthLevel * GameConfig.Rebirth.ValueBonusPerLevel)

	local boost = profile.ActiveBoosts["CatchValueMultiplier"]
	local boostMultiplier = 1
	if boost and boost.ExpiresAt > os.time() then
		boostMultiplier = boost.Amount
	end

	total = total * catchBonus * rebirthBonus * boostMultiplier

	profile.Inventory.Items = {}
	profile.Stats.TotalShellsEarned += total
	profile.Chest.PendingShells += total

	SoundService.PlayToPlayer("SellAll", player)
	pushInventoryState(player)
	return total, itemCount
end

-- Игрок явно забирает накопленное в сундуке — единственный момент, когда Shells
-- реально попадают на счёт (никаких мгновенных "+N монет" при сдаче добычи).
function InventoryService.CollectChest(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end

	local amount = profile.Chest.PendingShells
	if amount <= 0 then return 0 end

	profile.Chest.PendingShells = 0
	profile.Currency.Shells += amount

	SoundService.PlayToPlayer("CoinPickup", player)
	return amount
end

function InventoryService.GetChestPending(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end
	return profile.Chest.PendingShells
end

return InventoryService
