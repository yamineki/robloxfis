--[[
	SoundService.lua  (ServerScriptService, ModuleScript)
	Централизованный хелпер для звуков игры. Все SoundId — заглушки (пустая строка),
	их нужно заменить на свои rbxassetid:// — полный список и описание каждого звука
	см. в GameConfig.SoundIds (ReplicatedStorage) и в docs/README.md.

	Зачем централизовать: чтобы не плодить Instance.new("Sound") в каждом сервисе
	и чтобы при замене звука нужно было поменять ОДНО место (GameConfig.SoundIds),
	а не искать по всем файлам.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local SoundService = {}

-- Проигрывает звук в 3D-пространстве, прикреплённый к позиции конкретного Part/Instance.
-- Звук автоматически удаляется после воспроизведения, чтобы не копился мусор.
function SoundService.PlayAt(soundKey, anchorPart)
	local soundId = GameConfig.SoundIds[soundKey]
	if not soundId then
		warn("[SoundService] Неизвестный ключ звука:", soundKey)
		return
	end

	if soundId == "" then
		return -- заглушка ещё не заменена на реальный rbxassetid — просто молча пропускаем
	end

	if not anchorPart or not anchorPart.Parent then return end

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = GameConfig.SoundVolumes[soundKey] or 0.5
	sound.Parent = anchorPart
	sound:Play()

	game:GetService("Debris"):AddItem(sound, 5)
end

-- Проигрывает звук персонально игроку (например UI-клик), без привязки к месту в мире —
-- удобно слать через RemoteEvent и проигрывать локально на клиенте (см. PlayLocalSoundRemote).
function SoundService.PlayToPlayer(soundKey, player)
	local PlayLocalSoundRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PlayLocalSound")
	PlayLocalSoundRemote:FireClient(player, soundKey)
end

return SoundService
