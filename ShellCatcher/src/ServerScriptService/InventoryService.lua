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

-- Продаёт всё содержимое инвентаря, возвращает заработанную сумму
function InventoryService.SellAll(player)
	local profile = DataService.Get(player)
	if not profile then return 0 end

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

	profile.Currency.Shells += total
	profile.Stats.TotalShellsEarned += total
	profile.Inventory.Items = {}

	SoundService.PlayToPlayer("SellAll", player)
	pushInventoryState(player)
	return total
end

return InventoryService
