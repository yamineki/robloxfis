--[[
	DataService.lua  (ServerScriptService)
	Простая, но надёжная обёртка над DataStoreService:
	- кэш в памяти на время сессии
	- сохранение при выходе и периодически (autosave)
	- защита от потери данных при обрыве (pcall + retry)
	- слияние с шаблоном профиля для новых полей после обновлений игры

	Для продакшена можно заменить на ProfileService (популярный открытый модуль),
	но эта версия самодостаточна и не требует внешних зависимостей.
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlayerProfileTemplate = require(ReplicatedStorage:WaitForChild("PlayerProfileTemplate"))

local DataService = {}

local STORE_NAME = "ShellCatcher_PlayerData_v1"
local AUTOSAVE_INTERVAL = 120 -- секунд

local dataStore = DataStoreService:GetDataStore(STORE_NAME)
local sessionCache = {} -- [userId] = profileTable

-- Глубокое слияние шаблона -> в сохранённые данные, чтобы новые поля появлялись у старых игроков
local function deepFill(target, template)
	for key, value in pairs(template) do
		if target[key] == nil then
			if type(value) == "table" then
				target[key] = {}
				deepFill(target[key], value)
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" then
			deepFill(target[key], value)
		end
	end
	return target
end

local function loadProfileFromStore(userId)
	local key = "user_" .. tostring(userId)
	local success, data = pcall(function()
		return dataStore:GetAsync(key)
	end)

	if not success then
		warn("[DataService] Не удалось загрузить данные для", userId, data)
		return nil, false
	end

	local profile = data or {}
	deepFill(profile, PlayerProfileTemplate)
	return profile, true
end

local function saveProfileToStore(userId, profile)
	local key = "user_" .. tostring(userId)
	local success, err = pcall(function()
		dataStore:SetAsync(key, profile)
	end)

	if not success then
		warn("[DataService] Не удалось сохранить данные для", userId, err)
	end

	return success
end

function DataService.Get(player)
	local profile = sessionCache[player.UserId]
	if not profile then
		warn("[DataService] Профиль для", player.Name, "ещё не загружен")
	end
	return profile
end

function DataService.LoadForPlayer(player)
	local profile, ok = loadProfileFromStore(player.UserId)
	if not ok then
		-- Не пускаем играть с риском перезаписать прогресс пустыми данными.
		-- Тут хороший момент для "Place is restarting, please rejoin" сообщения.
		player:Kick("Не удалось загрузить твой прогресс. Попробуй зайти ещё раз через минуту.")
		return nil
	end

	sessionCache[player.UserId] = profile
	return profile
end

function DataService.SaveForPlayer(player, removeFromCache)
	local profile = sessionCache[player.UserId]
	if not profile then return end

	saveProfileToStore(player.UserId, profile)

	if removeFromCache then
		sessionCache[player.UserId] = nil
	end
end

-- Автосейв всех онлайн-игроков
task.spawn(function()
	while true do
		task.wait(AUTOSAVE_INTERVAL)
		for _, player in ipairs(Players:GetPlayers()) do
			DataService.SaveForPlayer(player, false)
		end
	end
end)

Players.PlayerRemoving:Connect(function(player)
	DataService.SaveForPlayer(player, true)
end)

-- Сохранение при закрытии сервера (важно для BindToClose)
game:BindToClose(function()
	for _, player in ipairs(Players:GetPlayers()) do
		DataService.SaveForPlayer(player, true)
	end
end)

return DataService
