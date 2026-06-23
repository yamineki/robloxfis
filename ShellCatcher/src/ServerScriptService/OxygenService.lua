--[[
	OxygenService.lua  (ServerScriptService)
	Управляет "кислородом" — временным таймером, который тратится в зонах лова
	и восстанавливается у базы. При обнулении — штраф по инвентарю и телепорт на базу.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local OxygenRemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OxygenUpdate")
local AsphyxiateRemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerAsphyxiated")

local OxygenService = {}

-- Runtime-состояние, не сохраняется между сессиями (это таймер текущего захода, не прогресс)
local runtimeState = {} -- [userId] = { Current = number, Max = number, ZoneId = string|nil }

local function getZoneOxygenMultiplier(zoneId)
	if not zoneId then return 1 end
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.Id == zoneId then
			return zone.OxygenMultiplier
		end
	end
	return 1
end

function OxygenService.InitPlayer(player)
	local maxOxygen = UpgradeService.GetStatValue(player, "OxygenCapacity") or GameConfig.Oxygen.BaseMax
	runtimeState[player.UserId] = {
		Current = maxOxygen,
		Max = maxOxygen,
		ZoneId = nil, -- nil = на базе/острове, восстанавливается
	}
end

-- Вызывается после покупки прокачки кислородных статов, чтобы Max обновился сразу,
-- не дожидаясь следующего респауна
function OxygenService.RefreshMaxOxygen(player)
	local state = runtimeState[player.UserId]
	if not state then return end

	local newMax = UpgradeService.GetStatValue(player, "OxygenCapacity") or GameConfig.Oxygen.BaseMax
	local diff = newMax - state.Max
	state.Max = newMax
	state.Current = math.min(newMax, state.Current + math.max(0, diff)) -- даём сразу прибавку при покупке
end

function OxygenService.SetZone(player, zoneId)
	local state = runtimeState[player.UserId]
	if not state then return end
	state.ZoneId = zoneId
end

local function handleAsphyxiation(player)
	-- Штраф: теряем часть инвентаря (мягкое наказание, не полная потеря — по дизайну Shelldiver-жанра)
	local profile = DataService.Get(player)
	if not profile then return end

	local items = profile.Inventory.Items
	local lossPercent = GameConfig.Oxygen.PenaltyLossPercent
	local keepCount = math.ceil(#items * (1 - lossPercent))

	-- Оставляем самые ценные предметы, теряем остальное — чуть мягче для игрока
	table.sort(items, function(a, b) return a.Value > b.Value end)
	for i = #items, keepCount + 1, -1 do
		table.remove(items, i)
	end

	local state = runtimeState[player.UserId]
	if state then
		state.Current = state.Max
		state.ZoneId = nil
	end

	AsphyxiateRemoteEvent:FireClient(player)
	SoundService.PlayToPlayer("Asphyxiate", player)

	-- Телепортируем игрока обратно на остров. Ленивый require, чтобы избежать
	-- циклической зависимости (ZoneService требует OxygenService на верхнем уровне).
	local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
	ZoneService.ReturnToIsland(player)
end

local lowOxygenWarningPlayed = {} -- [userId] = bool, чтобы не спамить звук каждую секунду

-- Главный тик расхода/восстановления кислорода, раз в секунду на каждого игрока
task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local state = runtimeState[player.UserId]
			if state then
				if state.ZoneId then
					local multiplier = getZoneOxygenMultiplier(state.ZoneId)
					local drainRate = UpgradeService.GetStatValue(player, "OxygenEfficiency") or GameConfig.Oxygen.DrainPerSecond
					state.Current = math.max(0, state.Current - drainRate * multiplier)

					if state.Current <= GameConfig.Oxygen.LowOxygenWarningAt and not lowOxygenWarningPlayed[player.UserId] then
						lowOxygenWarningPlayed[player.UserId] = true
						SoundService.PlayToPlayer("OxygenLowWarning", player)
					end

					if state.Current <= 0 then
						handleAsphyxiation(player)
						lowOxygenWarningPlayed[player.UserId] = false
					end
				else
					local regenRate = UpgradeService.GetStatValue(player, "OxygenRegen") or GameConfig.Oxygen.RegenNearBase
					state.Current = math.min(state.Max, state.Current + regenRate)
					if state.Current > GameConfig.Oxygen.LowOxygenWarningAt then
						lowOxygenWarningPlayed[player.UserId] = false
					end
				end

				OxygenRemoteEvent:FireClient(player, state.Current, state.Max)
			end
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	runtimeState[player.UserId] = nil
end)

return OxygenService
