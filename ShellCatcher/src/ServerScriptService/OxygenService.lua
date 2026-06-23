--[[
	OxygenService.lua  (ServerScriptService)
	Управляет "кислородом" — временным таймером, который тратится в зонах лова
	и восстанавливается у базы. БЕЗОПАСНО вернуться домой можно только на подлодке
	(ZoneService.ReturnToIsland вызывается оттуда явно). Если кислород закончился —
	игрок ТОНЕТ: получает урон/умирает и теряет часть собранного улова, а респаун
	(через стандартный Humanoid.Died) возвращает его на остров.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local DataService = require(script.Parent:WaitForChild("DataService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local OxygenRemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OxygenUpdate")
local AsphyxiateRemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerAsphyxiated")
local DrownedRemoteEvent = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayerDrowned")

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

local drowning = {} -- [userId] = true, защита от повторного триггера до респауна

local function dropLootVisual(rootPart, lostCount)
	if not rootPart or lostCount <= 0 then return end
	for i = 1, math.min(lostCount, 8) do
		local debris = Instance.new("Part")
		debris.Shape = Enum.PartType.Ball
		debris.Size = Vector3.new(0.8, 0.8, 0.8)
		debris.Material = Enum.Material.Neon
		debris.Color = Color3.fromRGB(255, 180, 90)
		debris.CanCollide = false
		debris.Position = rootPart.Position + Vector3.new(math.random(-2, 2), 1, math.random(-2, 2))
		debris.Parent = workspace

		local velocity = Vector3.new(math.random(-6, 6), math.random(2, 6), math.random(-6, 6))
		task.spawn(function()
			for _ = 1, 20 do
				debris.Position += velocity * 0.05
				velocity -= Vector3.new(0, 0.4, 0) -- лёгкая гравитация-заглушка
				task.wait(0.05)
			end
			debris:Destroy()
		end)
	end
end

-- Игрок ТОНЕТ: часть улова теряется (выпадает, см. dropLootVisual), а сам игрок
-- умирает — единственный способ безопасно вернуться домой это подлодка/Ferry,
-- а не доводить кислород до нуля.
local function handleAsphyxiation(player)
	if drowning[player.UserId] then return end
	drowning[player.UserId] = true

	local profile = DataService.Get(player)
	if not profile then
		drowning[player.UserId] = false
		return
	end

	local items = profile.Inventory.Items
	local lossPercent = GameConfig.Oxygen.PenaltyLossPercent
	local keepCount = math.ceil(#items * (1 - lossPercent))
	local lostCount = math.max(0, #items - keepCount)

	-- Оставляем самые ценные предметы, теряем остальное (выпадает за борт) — чуть мягче для игрока
	table.sort(items, function(a, b) return a.Value > b.Value end)
	for i = #items, keepCount + 1, -1 do
		table.remove(items, i)
	end

	local state = runtimeState[player.UserId]
	if state then
		state.Current = state.Max
		state.ZoneId = nil
	end

	local character = player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")

	dropLootVisual(rootPart, lostCount)

	AsphyxiateRemoteEvent:FireClient(player)
	DrownedRemoteEvent:FireClient(player, lostCount)
	SoundService.PlayToPlayer("Asphyxiate", player)

	-- Смерть от удушья — респаун (Humanoid.Died -> CharacterAdded) сам вернёт игрока
	-- на остров через onCharacterAdded в Main.server.lua.
	if humanoid then
		humanoid.Health = 0
	end

	drowning[player.UserId] = false
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
	drowning[player.UserId] = nil
	lowOxygenWarningPlayed[player.UserId] = nil
end)

return OxygenService
