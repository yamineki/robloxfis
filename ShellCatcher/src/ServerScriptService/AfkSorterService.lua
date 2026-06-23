--[[
	AfkSorterService.lua  (ServerScriptService)
	"Auto-Sorter Dock" — здание на острове, открываемое за валюту или геймпасс.
	Пока игрок находится на сервере (не обязательно физически у машины), копит
	небольшой пассивный доход. Игрок забирает накопленное руками или мгновенно
	через Developer Product InstantAfkCollect.

	Дизайн-намерение: это НЕ полноценный idle-офлайн доход (чтобы не убивать смысл
	активной игры), а небольшой бонус для тех, кто уже разблокировал здание —
	копится только пока сессия активна.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent:WaitForChild("DataService"))

local CollectAfkRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectAfkStorage")
local AfkStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AfkStateUpdate")

local AfkSorterService = {}

local ACCRUAL_PER_SECOND = 0.5 -- базовая скорость накопления Shells/сек, балансируется отдельно
local MAX_STORED = 600         -- кэп накопления, чтобы не было смысла не заходить месяцами

local function hasAfkDock(profile)
	for _, id in ipairs(profile.UnlockedBuildings) do
		if id == "afk_dock" then return true end
	end
	return false
end

task.spawn(function()
	while true do
		task.wait(1)
		for _, player in ipairs(Players:GetPlayers()) do
			local profile = DataService.Get(player)
			if profile then
				if hasAfkDock(profile) then
					profile.Stats.AfkStored = math.min(
						MAX_STORED,
						(profile.Stats.AfkStored or 0) + ACCRUAL_PER_SECOND
					)

					if profile.Stats.PendingInstantAfkCollect then
						profile.Currency.Shells += (profile.Stats.AfkStored or 0)
						profile.Stats.AfkStored = 0
						profile.Stats.PendingInstantAfkCollect = false
					end

					AfkStateRemote:FireClient(player, profile.Stats.AfkStored, MAX_STORED)
				elseif profile.Stats.PendingInstantAfkCollect then
					-- У игрока нет AFK-дока (например потерял при ребирте), но есть
					-- висящий флаг мгновенного сбора — гасим его, чтобы он не сработал
					-- неожиданно позже. Накопления без дока всё равно нет.
					profile.Stats.PendingInstantAfkCollect = false
				end
			end
		end
	end
end)

CollectAfkRemote.OnServerEvent:Connect(function(player)
	local profile = DataService.Get(player)
	if not profile or not hasAfkDock(profile) then return end

	profile.Currency.Shells += (profile.Stats.AfkStored or 0)
	profile.Stats.AfkStored = 0
end)

return AfkSorterService
