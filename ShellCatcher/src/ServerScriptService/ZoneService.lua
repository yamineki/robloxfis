--[[
	ZoneService.lua  (ServerScriptService)
	Управляет зонами лова: разблокировка за валюту, перемещение игрока между
	островом (база) и зоной, привязка к OxygenService.

	Структура мира (по дизайну): общий остров-хаб для всех игроков на сервере +
	общие зоны лова вокруг. Зоны — это Folder'ы в workspace с заранее расставленными
	частями ZoneEntrance / ZoneBounds / SpawnPoints.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local OxygenService = require(script.Parent:WaitForChild("OxygenService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local UnlockZoneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UnlockZone")
local EnterZoneRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("EnterZone")
local ZoneStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ZoneStateUpdate")

local ZoneService = {}

local function getZoneConfig(zoneId)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.Id == zoneId then
			return zone
		end
	end
	return nil
end

local function isZoneUnlocked(profile, zoneId)
	for _, id in ipairs(profile.UnlockedZones) do
		if id == zoneId then return true end
	end
	return false
end

function ZoneService.UnlockZone(player, zoneId)
	local profile = DataService.Get(player)
	if not profile then return false end

	if isZoneUnlocked(profile, zoneId) then
		return false, "already_unlocked"
	end

	local zoneConfig = getZoneConfig(zoneId)
	if not zoneConfig then
		return false, "invalid_zone"
	end

	if profile.Currency.Shells < zoneConfig.UnlockCost then
		return false, "not_enough_currency"
	end

	profile.Currency.Shells -= zoneConfig.UnlockCost
	table.insert(profile.UnlockedZones, zoneId)

	SoundService.PlayToPlayer("ZoneUnlock", player)
	ZoneStateRemote:FireClient(player, profile.UnlockedZones)
	return true
end

-- Безопасно выбирает случайную точку из папки; nil если папка пуста
local function pickRandomSpawn(folder)
	if not folder then return nil end
	local children = folder:GetChildren()
	if #children == 0 then return nil end
	return children[math.random(1, #children)]
end

function ZoneService.EnterZone(player, zoneId)
	local profile = DataService.Get(player)
	if not profile then return false end

	if not isZoneUnlocked(profile, zoneId) then
		return false, "zone_locked"
	end

	local zoneFolder = workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild(zoneId)
	if not zoneFolder then
		warn("[ZoneService] Зона не найдена в workspace:", zoneId)
		return false, "zone_missing_in_world"
	end

	local spawnPoints = zoneFolder:FindFirstChild("SpawnPoints")
	local character = player.Character
	if not character then return false end

	local chosenSpawn = pickRandomSpawn(spawnPoints)
	if not chosenSpawn then
		warn("[ZoneService] В зоне нет точек спавна:", zoneId)
		return false, "no_spawn_points"
	end

	character:PivotTo(chosenSpawn.CFrame)

	OxygenService.SetZone(player, zoneId)
	return true
end

function ZoneService.ReturnToIsland(player)
	local islandSpawns = workspace:FindFirstChild("IslandSpawnPoints")
	local character = player.Character
	if not character then return end

	local chosenSpawn = pickRandomSpawn(islandSpawns)
	if not chosenSpawn then
		warn("[ZoneService] Нет точек спавна на острове (IslandSpawnPoints пуст)")
		return
	end

	character:PivotTo(chosenSpawn.CFrame)

	OxygenService.SetZone(player, nil)
end

UnlockZoneRemote.OnServerEvent:Connect(function(player, zoneId)
	ZoneService.UnlockZone(player, zoneId)
end)

EnterZoneRemote.OnServerEvent:Connect(function(player, zoneId)
	-- Спец-значение от кнопки "Return to Island" в окне телепортации.
	if zoneId == "__island__" then
		ZoneService.ReturnToIsland(player)
		return
	end
	ZoneService.EnterZone(player, zoneId)
end)

return ZoneService
