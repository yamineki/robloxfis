--[[
	CrusherDrillService.lua  (ServerScriptService)
	Логика второго инструмента: "Crusher Drill" — дробит ресурсные блоки (не живую добычу).
	Вместо клипа патронов использует перегрев при удержании кнопки.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local DataService = require(script.Parent:WaitForChild("DataService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local FireDrillRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("FireDrill")
local DrillResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DrillResult")
local OverheatRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("DrillOverheat")
local CatchResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CatchResult")
local UpgradeStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeStateUpdate")

local CrusherDrillService = {}

local lastFireTime = {}      -- [userId] = os.clock()
local heatLevel = {}         -- [userId] = number 0..OverheatAfter (секунды непрерывного использования)
local overheated = {}        -- [userId] = bool

-- Сбрасываем нагрев, если игрок не стрелял какое-то время
task.spawn(function()
	while true do
		task.wait(0.5)
		for userId, heat in pairs(heatLevel) do
			if heat > 0 then
				heatLevel[userId] = math.max(0, heat - 0.5) -- остывает вдвое медленнее, чем нагревается
				if heatLevel[userId] == 0 then
					overheated[userId] = false
				end
			end
		end
	end
end)

local function rewardResource(player, resourceBlock)
	local profile = DataService.Get(player)
	if not profile then return end

	local resourceId = resourceBlock:GetAttribute("ResourceId") or "scrap"
	local amount = resourceBlock:GetAttribute("Amount") or 1

	-- Ресурсы блоков идут как отдельная "крафтовая" валюта, не как Shells —
	-- хранится в профиле отдельно, чтобы не путать с основной экономикой улова.
	profile.Currency[resourceId] = (profile.Currency[resourceId] or 0) + amount

	DrillResultRemote:FireClient(player, {
		ResourceId = resourceId,
		Amount = amount,
	})
end

-- Лопнувший лазером мусор -> мгновенные Shells (как у пузыря, но через дробилку).
local function rewardTrash(player, trashPart)
	local profile = DataService.Get(player)
	if not profile then return end
	local value = trashPart:GetAttribute("TrashValue") or GameConfig.Trash.BaseValue
	profile.Currency.Shells += value
	profile.Stats.TotalShellsEarned = (profile.Stats.TotalShellsEarned or 0) + value
	CatchResultRemote:FireClient(player, {
		Success = true,
		IsTrash = true,
		TrashKind = trashPart:GetAttribute("TrashKind") or "trash",
		Value = value,
	})
	SoundService.PlayAt("DrillBreakBlock", trashPart)
	UpgradeStateRemote:FireClient(player, UpgradeService.GetFullSnapshot(player), profile.Currency.Shells)
	trashPart:Destroy()
end

-- Урон заряженного лазера скейлится веткой прокачки (DrillDamage).
local function laserDamage(player)
	local cfg = GameConfig.CrusherLaser
	local levelDamage = UpgradeService.GetStatValue(player, "DrillDamage") or GameConfig.Tools.CrusherDrill.BaseDamage
	return cfg.BaseLaserDamage + levelDamage
end

FireDrillRemote.OnServerEvent:Connect(function(player, targetInstance, isLaser)
	if overheated[player.UserId] then
		return -- инструмент перегрет, сервер игнорирует попытки стрельбы
	end

	if typeof(targetInstance) ~= "Instance" then return end
	if not targetInstance:IsDescendantOf(workspace) then return end
	if not targetInstance:GetAttribute("Health") then return end

	local now = os.clock()
	local fireRate = UpgradeService.GetStatValue(player, "DrillFireRate") or GameConfig.Tools.CrusherDrill.BaseFireRate
	local minInterval = 1 / fireRate
	if lastFireTime[player.UserId] and now - lastFireTime[player.UserId] < minInterval then
		return
	end
	lastFireTime[player.UserId] = now

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end

	-- Лазер бьёт дальше (направленный луч); ближний радиус — для обычного режима.
	local maxRange = isLaser and (GameConfig.CrusherLaser.BaseBeamLength + 20) or (GameConfig.Tools.CrusherDrill.BaseRange + 3)
	local distance = (rootPart.Position - targetInstance:GetPivot().Position).Magnitude
	if distance > maxRange then
		return
	end

	local overheatThreshold = UpgradeService.GetStatValue(player, "DrillOverheat") or GameConfig.Tools.CrusherDrill.OverheatAfter
	heatLevel[player.UserId] = (heatLevel[player.UserId] or 0) + minInterval
	if heatLevel[player.UserId] >= overheatThreshold then
		overheated[player.UserId] = true
		OverheatRemote:FireClient(player, true)
		SoundService.PlayAt("DrillOverheat", rootPart)
	end

	SoundService.PlayAt("DrillFire", targetInstance)

	local health = targetInstance:GetAttribute("Health")
	local damage = isLaser and laserDamage(player)
		or (UpgradeService.GetStatValue(player, "DrillDamage") or GameConfig.Tools.CrusherDrill.BaseDamage)
	health -= damage
	targetInstance:SetAttribute("Health", health)

	if health <= 0 then
		if targetInstance:GetAttribute("Trash") then
			rewardTrash(player, targetInstance)
		else
			SoundService.PlayAt("DrillBreakBlock", targetInstance)
			rewardResource(player, targetInstance)
			targetInstance:Destroy()
		end
	end
end)

return CrusherDrillService
