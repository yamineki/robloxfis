--[[
	UpgradeService.lua  (ServerScriptService)
	Считает текущие статы инструментов/акваланга/инвентаря на основе купленных
	уровней в радиальном дереве навыков (см. GameConfig.UpgradeTree) и обрабатывает
	покупку следующего уровня узла.

	Зависимости: узел можно купить только если у него нет родителя (ParentKey == nil,
	растёт прямо из центрального узла "Start") ИЛИ родитель уже куплен хотя бы
	на 1 уровень (см. UpgradeService.IsNodeUnlocked).

	Стоимость уровня N (1-индексация, N=1 это первая покупка после старта):
		cost = BaseCost * CostGrowth ^ (N - 1)
	Значение статы на уровне N:
		value = BaseValue + ValuePerLevel * N
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local BuyUpgradeRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("BuyUpgrade")
local UpgradeStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeStateUpdate")

local UpgradeService = {}

local function getUpgradeConfig(upgradeKey)
	return GameConfig.Upgrades[upgradeKey]
end

local function getCostForLevel(upgradeConfig, level)
	-- level — уровень, который мы ПОКУПАЕМ (т.е. текущий+1)
	return math.floor(upgradeConfig.BaseCost * (upgradeConfig.CostGrowth ^ (level - 1)))
end

-- Текущее значение статы с учётом купленного уровня
function UpgradeService.GetStatValue(player, upgradeKey)
	local profile = DataService.Get(player)
	if not profile then return nil end

	local upgradeConfig = getUpgradeConfig(upgradeKey)
	if not upgradeConfig then return nil end

	local level = profile.UpgradeLevels[upgradeKey] or 0
	return upgradeConfig.BaseValue + upgradeConfig.ValuePerLevel * level
end

-- Удобный хелпер: считает все статы инструмента сразу, например "HarpoonNet" -> {Damage=.., FireRate=.., ...}
function UpgradeService.GetToolStats(player, toolName)
	local stats = {}
	for upgradeKey, upgradeConfig in pairs(GameConfig.Upgrades) do
		if upgradeConfig.Tool == toolName then
			stats[upgradeConfig.Stat] = UpgradeService.GetStatValue(player, upgradeKey)
		end
	end
	return stats
end

-- Проверяет, открыт ли узел для покупки: либо это корень дерева, либо его родитель
-- уже куплен хотя бы на 1 уровень.
function UpgradeService.IsNodeUnlocked(player, upgradeKey)
	local profile = DataService.Get(player)
	if not profile then return false end

	local nodeConfig = GameConfig.UpgradeTree[upgradeKey]
	if not nodeConfig then return false end

	if not nodeConfig.ParentKey then
		return true -- узел без родителя (растёт прямо из центра) — всегда доступен
	end

	local parentLevel = profile.UpgradeLevels[nodeConfig.ParentKey] or 0
	return parentLevel > 0
end

function UpgradeService.GetUpgradeInfo(player, upgradeKey)
	local profile = DataService.Get(player)
	if not profile then return nil end

	local upgradeConfig = getUpgradeConfig(upgradeKey)
	if not upgradeConfig then return nil end

	local currentLevel = profile.UpgradeLevels[upgradeKey] or 0
	local isMaxed = currentLevel >= upgradeConfig.MaxLevel
	local isUnlocked = UpgradeService.IsNodeUnlocked(player, upgradeKey)

	return {
		Key = upgradeKey,
		DisplayName = upgradeConfig.DisplayName,
		Tool = upgradeConfig.Tool,
		Stat = upgradeConfig.Stat,
		Branch = upgradeConfig.Branch,
		Angle = upgradeConfig.Angle,
		Radius = upgradeConfig.Radius,
		ParentKey = upgradeConfig.ParentKey,
		CurrentLevel = currentLevel,
		MaxLevel = upgradeConfig.MaxLevel,
		CurrentValue = UpgradeService.GetStatValue(player, upgradeKey),
		NextCost = isMaxed and nil or getCostForLevel(upgradeConfig, currentLevel + 1),
		IsMaxed = isMaxed,
		IsUnlocked = isUnlocked, -- false = родитель ещё не куплен, узел показывается "заблокированным"
	}
end

-- Отдаёт клиенту полный снапшот всех веток прокачки (для отрисовки UI)
function UpgradeService.GetFullSnapshot(player)
	local snapshot = {}
	for upgradeKey in pairs(GameConfig.Upgrades) do
		snapshot[upgradeKey] = UpgradeService.GetUpgradeInfo(player, upgradeKey)
	end
	return snapshot
end

function UpgradeService.BuyUpgrade(player, upgradeKey)
	local profile = DataService.Get(player)
	if not profile then return false, "no_profile" end

	local upgradeConfig = getUpgradeConfig(upgradeKey)
	if not upgradeConfig then return false, "invalid_upgrade" end

	if not UpgradeService.IsNodeUnlocked(player, upgradeKey) then
		SoundService.PlayToPlayer("NotEnoughCurrency", player) -- тот же "отказной" звук подходит и для заблокированного узла
		return false, "parent_node_locked"
	end

	local currentLevel = profile.UpgradeLevels[upgradeKey] or 0
	if currentLevel >= upgradeConfig.MaxLevel then
		SoundService.PlayToPlayer("UpgradeMaxed", player)
		return false, "max_level_reached"
	end

	local cost = getCostForLevel(upgradeConfig, currentLevel + 1)
	if profile.Currency.Shells < cost then
		SoundService.PlayToPlayer("NotEnoughCurrency", player)
		return false, "not_enough_currency"
	end

	profile.Currency.Shells -= cost
	profile.UpgradeLevels[upgradeKey] = currentLevel + 1

	if upgradeConfig.Tool == "Oxygen" then
		-- Ленивый require, чтобы избежать циклической зависимости
		-- (OxygenService тоже требует UpgradeService для расчёта статов).
		local OxygenService = require(script.Parent:WaitForChild("OxygenService"))
		OxygenService.RefreshMaxOxygen(player)
	end

	SoundService.PlayToPlayer("UpgradeBuy", player)
	UpgradeStateRemote:FireClient(player, UpgradeService.GetFullSnapshot(player), profile.Currency.Shells)
	return true
end

BuyUpgradeRemote.OnServerEvent:Connect(function(player, upgradeKey)
	local success, reason = UpgradeService.BuyUpgrade(player, upgradeKey)
	if not success then
		warn(("[UpgradeService] %s не смог купить %s: %s"):format(player.Name, tostring(upgradeKey), reason))
	end
end)

return UpgradeService
