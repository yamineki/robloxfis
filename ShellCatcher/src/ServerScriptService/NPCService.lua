--[[
	NPCService.lua  (ServerScriptService, ModuleScript)

	Привязывает ProximityPrompt каждого NPC (построенного MapBuilder из GameConfig.NPCs)
	к действию по его роли:
	  Quartermaster -> выдаёт ОБЕ пушки (ToolService.GrantTools)
	  FerryCaptain  -> открывает окно телепортации по зонам (OpenClientWindow "Travel")
	  Shopkeeper    -> "Shop"
	  StorageKeeper -> "Inventory"
	  AfkOperator   -> "Afk"
	  RebirthPriest -> "Rebirth"

	ProximityPrompt.Triggered приходит на СЕРВЕР, поэтому выдачу инструментов делаем
	прямо тут, а открытие окна пробрасываем клиенту через RemoteEvent OpenClientWindow
	(его слушает MasterUI.client.lua).

	Вызывать NPCService.Init() ОДИН раз из Main.server.lua ПОСЛЕ MapBuilder.BuildEverything().
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local ToolService = require(script.Parent:WaitForChild("ToolService"))
local SoundService = require(script.Parent:WaitForChild("SoundService"))

local OpenClientWindowRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OpenClientWindow")

local NPCService = {}

-- Анти-спам: не даём дёргать одного NPC чаще раза в N секунд на игрока.
local INTERACT_COOLDOWN = 0.6
local lastInteract = {} -- [userId .. "_" .. npcRole] = os.clock()

local function onCooldown(player, role)
	local key = player.UserId .. "_" .. role
	local now = os.clock()
	if lastInteract[key] and now - lastInteract[key] < INTERACT_COOLDOWN then
		return true
	end
	lastInteract[key] = now
	return false
end

local function handleInteraction(player, role)
	if onCooldown(player, role) then return end

	if role == "Quartermaster" then
		ToolService.GrantTools(player)
		-- Открываем у игрока короткое подтверждение через тот же канал окна (toast в UI).
		OpenClientWindowRemote:FireClient(player, "ToolsGranted")
		return
	end

	local windowName = GameConfig.NPCRoleWindows[role]
	if windowName then
		OpenClientWindowRemote:FireClient(player, windowName)
	end
end

function NPCService.Init()
	local island = workspace:FindFirstChild("Island")
	local npcFolder = island and island:FindFirstChild("NPCs")
	if not npcFolder then
		warn("[NPCService] Папка NPCs не найдена — MapBuilder ещё не построил остров?")
		return
	end

	for _, npcModel in ipairs(npcFolder:GetChildren()) do
		local role = npcModel:GetAttribute("Role")
		if role then
			local prompt = npcModel:FindFirstChild("NPCPrompt", true)
			if prompt and prompt:IsA("ProximityPrompt") then
				prompt.Triggered:Connect(function(player)
					handleInteraction(player, role)
					local voice = prompt.Parent and prompt.Parent:FindFirstChild("VoiceSound")
					if voice then
						SoundService.PlayToPlayer("NPCVoice", player)
					end
				end)
			else
				warn("[NPCService] У NPC", npcModel.Name, "нет ProximityPrompt 'NPCPrompt'")
			end
		end
	end

	print("[NPCService] Подключено NPC-взаимодействий:", #npcFolder:GetChildren())
end

return NPCService
