--[[
	HarpoonToolService.lua  (ServerScriptService)
	Логика "Пушки пузырей" (ключ инструмента исторически HarpoonNet): стрельба
	пузырями по МЕДУЗАМ и плавающему МУСОРУ. Накопление урона до поимки/разрушения.
	Редкость/вид медузы раскрываются ТОЛЬКО в момент поимки (RNG-момент).

	Цель определяется по атрибутам (Catchable / Trash / Health), а не по имени —
	поэтому арт можно менять свободно.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local FireHarpoonRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FireHarpoon")
local CatchResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CatchResult")
local UpgradeStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeStateUpdate")

local HarpoonToolService = {}

-- Кулдаун на сервере, чтобы клиент не мог спамить FireServer быстрее реального файрейта
local lastFireTime = {} -- [userId] = os.clock()

local function rollRarity()
	local totalWeight = 0
	for _, r in ipairs(GameConfig.Rarities) do
		totalWeight += r.Weight
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for _, r in ipairs(GameConfig.Rarities) do
		cumulative += r.Weight
		if roll <= cumulative then
			return r
		end
	end

	return GameConfig.Rarities[1]
end

-- target: Instance в воркспейсе с атрибутом Health (медуза-модель или мусор-парт)
local function applyDamageAndMaybeCatch(player, target)
	local health = target:GetAttribute("Health") or 0
	local toolDamage = UpgradeService.GetStatValue(player, "HarpoonDamage") or GameConfig.Tools.HarpoonNet.BaseDamage

	health -= toolDamage
	target:SetAttribute("Health", health)

	if health > 0 then return end

	-- Медуза: RNG-раскрытие редкости и добавление в инвентарь.
	local rarity = rollRarity()
	local baseValue = target:GetAttribute("BaseValue") or 5
	local creatureId = target:GetAttribute("CreatureId") or "unknown"

	local added, errorReason = InventoryService.AddCatch(player, {
		CreatureId = creatureId,
		RarityId = rarity.Id,
		BaseValue = baseValue,
	})

	if added then
		CatchResultRemote:FireClient(player, {
			Success = true,
			CreatureId = creatureId,
			RarityId = rarity.Id,
			RarityColor = rarity.Color,
		})
		SoundService.PlayAt("HarpoonCatchSuccess", target)
		target:Destroy()
	else
		CatchResultRemote:FireClient(player, {
			Success = false,
			Reason = errorReason,
		})
	end
end

FireHarpoonRemote.OnServerEvent:Connect(function(player, silhouetteInstance)
	if typeof(silhouetteInstance) ~= "Instance" then return end
	if not silhouetteInstance:IsDescendantOf(workspace) then return end
	if not silhouetteInstance:GetAttribute("Health") then return end -- не похож на валидную цель
	if not silhouetteInstance:GetAttribute("Catchable") then return end -- пузырь ловит только медуз, не мусор

	local now = os.clock()
	local fireRate = UpgradeService.GetStatValue(player, "HarpoonFireRate") or GameConfig.Tools.HarpoonNet.BaseFireRate
	local minInterval = 1 / fireRate
	if lastFireTime[player.UserId] and now - lastFireTime[player.UserId] < minInterval then
		return -- слишком частая стрельба — игнорируем как потенциальный эксплойт/лаг
	end
	lastFireTime[player.UserId] = now

	-- Проверка дистанции на сервере (анти-чит): нельзя ловить силуэт через всю карту
	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	local range = UpgradeService.GetStatValue(player, "HarpoonRange") or GameConfig.Tools.HarpoonNet.BaseRange
	local distance = (rootPart.Position - silhouetteInstance:GetPivot().Position).Magnitude
	if distance > range + 5 then -- +5 запас на задержку сети
		return
	end

	SoundService.PlayAt("HarpoonFire", rootPart)
	applyDamageAndMaybeCatch(player, silhouetteInstance)
end)

return HarpoonToolService
