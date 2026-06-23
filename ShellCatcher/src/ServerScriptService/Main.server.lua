--[[
	Main.server.lua  (ServerScriptService)
	Точка входа: загружает все сервисы, подключает обработку входа/выхода игроков.

	Папка ReplicatedStorage.Remotes со всеми RemoteEvent создаётся СТАТИЧЕСКИ через
	default.project.json (Rojo), поэтому она гарантированно существует до запуска
	этого скрипта — никаких "Infinite yield on WaitForChild(Remotes)".
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Порядок важен: DataService должен быть готов раньше всех, кто его требует.
local DataService = require(script.Parent:WaitForChild("DataService"))
local GamePassService = require(script.Parent:WaitForChild("GamePassService"))
local DeveloperProductService = require(script.Parent:WaitForChild("DeveloperProductService"))
local InventoryService = require(script.Parent:WaitForChild("InventoryService"))
local UpgradeService = require(script.Parent:WaitForChild("UpgradeService"))
local OxygenService = require(script.Parent:WaitForChild("OxygenService"))
local HarpoonToolService = require(script.Parent:WaitForChild("HarpoonToolService"))
local CrusherDrillService = require(script.Parent:WaitForChild("CrusherDrillService"))
local ZoneService = require(script.Parent:WaitForChild("ZoneService"))
local ZoneSpawnerService = require(script.Parent:WaitForChild("ZoneSpawnerService"))
local AfkSorterService = require(script.Parent:WaitForChild("AfkSorterService"))
local RebirthService = require(script.Parent:WaitForChild("RebirthService"))
local MapBuilder = require(script.Parent:WaitForChild("MapBuilder"))
local ToolService = require(script.Parent:WaitForChild("ToolService"))
local NPCService = require(script.Parent:WaitForChild("NPCService"))

local SellInventoryRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellInventory")
local SellResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellResult")
local PromptGamePassRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PromptGamePassPurchase")
local PromptProductRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("PromptProductPurchase")
local UpgradeStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("UpgradeStateUpdate")
local InventoryStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("InventoryStateUpdate")
local ZoneStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ZoneStateUpdate")
local RebirthResultRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RebirthResult")
local RequestInitialStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("RequestInitialState")
local SellFlowFxRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("SellFlowFx")
local ChestStateRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("ChestStateUpdate")
local CollectChestRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("CollectChest")

-- Строим карту-заглушку ДО запуска спавнера зон, иначе зонам некуда будет спавнить добычу
MapBuilder.BuildEverything()

-- Подключаем взаимодействия NPC (выдача пушек, телепорт-окно, магазин и т.д.)
-- строго ПОСЛЕ постройки острова, иначе папки NPCs ещё нет.
NPCService.Init()

-- ============================================================
-- Открытие клиентских окон из ProximityPrompt на зданиях острова.
-- ProximityPrompt.Triggered срабатывает на сервере, поэтому пробрасываем
-- "открой окно у конкретного игрока" через RemoteEvent, который слушает клиент
-- (MasterUI.client.lua подписан на OpenClientWindow). Сам RemoteEvent уже создан
-- статически через default.project.json — берём существующий, не создаём дубль.
-- ============================================================
local OpenClientWindowRemote = ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("OpenClientWindow")

local buildingPromptActions = {
	shop_basic    = "Inventory",  -- Trading Stall = здание Collector NPC (сдача добычи / сундук)
	skin_workshop = "Shop",       -- мастерская скинов открывает Robux-магазин (вкладка с косметикой)
	afk_dock      = "Afk",
	rebirth_altar = "Rebirth",
}

local function connectBuildingPrompts()
	local buildingsFolder = workspace:FindFirstChild("Island") and workspace.Island:FindFirstChild("Buildings")
	if not buildingsFolder then
		warn("[Main] Не найдена папка Buildings — карта не построилась?")
		return
	end

	for _, buildingPart in ipairs(buildingsFolder:GetChildren()) do
		local prompt = buildingPart:FindFirstChild("BuildingPrompt_" .. buildingPart.Name)
		local windowName = buildingPromptActions[buildingPart.Name]

		if prompt and windowName then
			prompt.Triggered:Connect(function(player)
				OpenClientWindowRemote:FireClient(player, windowName)
			end)
		end
	end
end

connectBuildingPrompts()

-- Отправляет клиенту ПОЛНЫЙ снапшот состояния. Вызывается и при заходе, и по запросу
-- клиента (RequestInitialState) — это устраняет гонку, когда сервер шлёт данные раньше,
-- чем LocalScript успел подключить свои OnClientEvent-обработчики.
local function pushFullState(player)
	local profile = DataService.Get(player)
	if not profile then return end

	UpgradeStateRemote:FireClient(player, UpgradeService.GetFullSnapshot(player), profile.Currency.Shells)
	InventoryStateRemote:FireClient(player, profile.Inventory.Items, InventoryService.GetMaxSlots(player))
	ZoneStateRemote:FireClient(player, profile.UnlockedZones)
	ChestStateRemote:FireClient(player, profile.Chest.PendingShells)

	-- Снапшот ребирта (для окна Rebirth) — тихий, без всплывашки на клиенте.
	RebirthResultRemote:FireClient(player, {
		InfoOnly = true,
		RebirthLevel = profile.RebirthLevel,
		Requirement = RebirthService.GetRequirement(player),
	})
end

local function onPlayerAdded(player)
	local profile = DataService.LoadForPlayer(player)
	if not profile then return end -- LoadForPlayer уже кикнул игрока при ошибке

	OxygenService.InitPlayer(player)
	GamePassService.RefreshAllPasses(player)

	-- Если игрок уже брал пушки в прошлой сессии — возвращаем их (в StarterGear),
	-- чтобы не идти к Quartermaster каждый раз.
	ToolService.RestoreToolsIfOwned(player)

	-- Шлём состояние сразу (на случай, если клиент уже готов), а клиент дополнительно
	-- запросит его сам через RequestInitialState когда подключит обработчики.
	pushFullState(player)
end

-- Клиент сообщает, что готов принимать данные — отправляем полный снапшот ещё раз.
RequestInitialStateRemote.OnServerEvent:Connect(function(player)
	pushFullState(player)
end)

local function onCharacterAdded(player)
	-- Каждый раз когда персонаж респаунится, возвращаем его на остров (безопасная точка),
	-- а не оставляем посреди зоны лова, где могло случиться удушение.
	task.wait(0.5)
	ZoneService.ReturnToIsland(player)
end

-- Единая обработка персонажа: подключение CharacterAdded + обработка уже существующего
local function setupCharacterHandling(player)
	player.CharacterAdded:Connect(function()
		onCharacterAdded(player)
	end)
	-- Если персонаж уже есть к моменту подключения (перезапуск скрипта в Studio) — обработаем сразу
	if player.Character then
		task.spawn(onCharacterAdded, player)
	end
end

Players.PlayerAdded:Connect(function(player)
	onPlayerAdded(player)
	setupCharacterHandling(player)
end)

-- На случай если скрипт перезапускается, а игроки уже в игре (Studio-тест)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
	setupCharacterHandling(player)
end

-- Сдача добычи продавцу: медузы из инвентаря "летят" к Collector NPC (визуал на клиенте
-- через SellFlowFx), деньги попадают НЕ на счёт, а в Сундук — забрать их нужно отдельно.
SellInventoryRemote.OnServerEvent:Connect(function(player)
	local total, itemCount = InventoryService.SellAll(player)
	SellResultRemote:FireClient(player, total)
	if itemCount > 0 then
		SellFlowFxRemote:FireClient(player, itemCount, total)
	end
	ChestStateRemote:FireClient(player, InventoryService.GetChestPending(player))
end)

-- Игрок забирает накопленное в сундуке в реальную валюту.
CollectChestRemote.OnServerEvent:Connect(function(player)
	local collected = InventoryService.CollectChest(player)
	if collected > 0 then
		ChestStateRemote:FireClient(player, 0)
		UpgradeStateRemote:FireClient(player, UpgradeService.GetFullSnapshot(player), DataService.Get(player).Currency.Shells)
	end
end)

PromptGamePassRemote.OnServerEvent:Connect(function(player, gamePassKey)
	GamePassService.PromptPurchase(player, gamePassKey)
end)

PromptProductRemote.OnServerEvent:Connect(function(player, productKey)
	DeveloperProductService.PromptPurchase(player, productKey)
end)

ZoneSpawnerService.StartAllZones()

print("[Main] Shell Catcher сервер запущен.")
