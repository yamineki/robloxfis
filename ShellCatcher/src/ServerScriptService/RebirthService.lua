--[[
	RebirthService.lua  (ServerScriptService)
	Ребирт: сбрасывает зоны/инвентарь/прогресс по острову, но даёт постоянный
	прирост ценности улова и сохраняет геймпассы/косметику (это вне сброса).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))
local GamePassService = require(script.Parent:WaitForChild("GamePassService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))

local RebirthRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestRebirth")
local RebirthResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RebirthResult")
local InventoryStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryStateUpdate")
local ZoneStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ZoneStateUpdate")
local UpgradeStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeStateUpdate")

local RebirthService = {}

local function getRequiredCurrency(rebirthLevel)
	local base = GameConfig.Rebirth.BaseCurrencyRequirement
	local growth = GameConfig.Rebirth.RequirementGrowth
	return math.floor(base * (growth ^ rebirthLevel))
end

function RebirthService.GetRequirement(player)
	local profile = DataService.Get(player)
	if not profile then return nil end
	return getRequiredCurrency(profile.RebirthLevel)
end

function RebirthService.PerformRebirth(player)
	local profile = DataService.Get(player)
	if not profile then return false end

	if profile.RebirthLevel >= GameConfig.Rebirth.MaxLevel then
		return false, "max_level_reached"
	end

	local required = getRequiredCurrency(profile.RebirthLevel)
	if profile.Currency.Shells < required then
		return false, "not_enough_currency"
	end

	-- Проверяем "Rebirth Keepsake" — пасс, сохраняющий 1 косметику без повторной покупки логики
	local keepsakeOwned = profile.OwnedGamePasses["RebirthShortcutToken"] == true

	profile.Currency.Shells -= required
	profile.RebirthLevel += 1

	if GameConfig.Rebirth.ResetsInventoryAndZones then
		profile.Inventory.Items = {}
		profile.UnlockedZones = { "reef" }
		profile.UnlockedBuildings = { "shop_basic" }

		-- Переприменяем геймпассы: те, что разблокируют здания (AutoSorter/SkinWorkshop и т.п.),
		-- должны вернуть свои здания сразу, а не только при следующем заходе.
		GamePassService.RefreshAllPasses(player)
	end

	-- Синхронизируем клиент: после сброса инвентарь/зоны/дерево навыков показывали бы
	-- старое состояние, пока что-нибудь не обновится — поэтому шлём всё явно.
	InventoryStateRemote:FireClient(player, profile.Inventory.Items, InventoryService.GetMaxSlots(player))
	ZoneStateRemote:FireClient(player, profile.UnlockedZones)
	UpgradeStateRemote:FireClient(player, UpgradeService.GetFullSnapshot(player), profile.Currency.Shells)

	RebirthResultRemote:FireClient(player, {
		Success = true,
		NewLevel = profile.RebirthLevel,
		Requirement = getRequiredCurrency(profile.RebirthLevel),
		KeptCosmetic = keepsakeOwned,
	})

	SoundService.PlayToPlayer("RebirthSuccess", player)

	return true
end

RebirthRemote.OnServerEvent:Connect(function(player)
	local success, reason = RebirthService.PerformRebirth(player)
	if not success then
		RebirthResultRemote:FireClient(player, { Success = false, Reason = reason })
	end
end)

return RebirthService
