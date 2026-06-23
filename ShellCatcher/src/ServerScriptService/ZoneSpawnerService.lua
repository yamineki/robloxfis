--[[
	ZoneSpawnerService.lua  (ServerScriptService)

	Наполняет каждую зону живностью и мусором:
	  • МЕДУЗЫ (Jellyfish) — полупрозрачные неоновые модели, плавают (bob + drift).
	    Ловятся Пушкой пузырей. Вид/редкость раскрываются RNG в момент поимки
	    (см. HarpoonToolService). Атрибуты: Health, BaseValue, CreatureId, Catchable=true.
	  • ПЛАВАЮЩИЙ МУСОР (FloatingTrash) — дрейфующий хлам, тоже лопается пузырём ради
	    мелких Shells. Атрибуты: Health, TrashValue, Trash=true.
	  • РЕСУРСНЫЕ БЛОКИ (ResourceBlock) — для Crusher Drill (как раньше).

	Детект цели идёт по АТРИБУТАМ (Catchable/Trash/Health), а не по имени, поэтому
	арт можно менять свободно, лишь бы атрибуты стояли.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local ZoneSpawnerService = {}

local RESOURCE_BLOCK_BASE_HEALTH = 30
local MAX_RESOURCE_BLOCKS_PER_ZONE = 10
local SPAWN_CHECK_INTERVAL = 3

local resourceIdsByHazard = {
	[0] = { "scrap", "shellfragment" },
	[1] = { "scrap", "shellfragment", "darkpearl" },
	[2] = { "obsidianite", "magmacrystal" },
}

local function getZoneConfig(zoneId)
	for _, zone in ipairs(GameConfig.Zones) do
		if zone.Id == zoneId then return zone end
	end
	return nil
end

local function randomPoint(spawnFolder)
	if not spawnFolder then return nil end
	local children = spawnFolder:GetChildren()
	if #children == 0 then return nil end
	return children[math.random(1, #children)]
end

-- ============================================================
-- МЕДУЗА
-- ============================================================

local function buildJellyfish(zoneConfig, cframe)
	local cfg = GameConfig.Jellyfish
	local color = (cfg.ColorByZone and cfg.ColorByZone[zoneConfig.Id]) or Color3.fromRGB(170, 200, 255)

	local model = Instance.new("Model")
	model.Name = "Jellyfish"

	-- Купол медузы — неоновый полупрозрачный шар (он же PrimaryPart)
	local bell = Instance.new("Part")
	bell.Name = "Bell"
	bell.Shape = Enum.PartType.Ball
	bell.Size = Vector3.new(3, 2.4, 3)
	bell.Color = color
	bell.Material = Enum.Material.Neon
	bell.Transparency = 0.45
	bell.Anchored = true
	bell.CanCollide = false
	bell.CFrame = cframe
	bell.Parent = model
	model.PrimaryPart = bell

	-- Щупальца — несколько тонких неоновых цилиндров под куполом
	for i = 1, 5 do
		local a = (i / 5) * math.pi * 2
		local tentacle = Instance.new("Part")
		tentacle.Name = "Tentacle"
		tentacle.Size = Vector3.new(0.25, 2.6, 0.25)
		tentacle.Color = color
		tentacle.Material = Enum.Material.Neon
		tentacle.Transparency = 0.55
		tentacle.Anchored = true
		tentacle.CanCollide = false
		tentacle.CFrame = cframe * CFrame.new(math.cos(a) * 0.8, -1.8, math.sin(a) * 0.8)
		tentacle.Parent = model
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = bell
		weld.Part1 = tentacle
		weld.Parent = bell
	end

	model:SetAttribute("Health", cfg.BaseHealth)
	model:SetAttribute("BaseValue", 5 * zoneConfig.CatchValueMultiplier)
	model:SetAttribute("CreatureId", "jellyfish_" .. zoneConfig.Id)
	model:SetAttribute("Catchable", true)

	return model, bell
end

local function spawnJellyfish(zoneFolder, zoneConfig)
	local point = randomPoint(zoneFolder:FindFirstChild("CreatureSpawnPoints"))
	if not point then return end

	local cfg = GameConfig.Jellyfish
	local model, bell = buildJellyfish(zoneConfig, point.CFrame)
	model.Parent = zoneFolder:FindFirstChild("Creatures") or zoneFolder

	local origin = point.Position
	-- Плавное блуждание: дрейф вокруг origin + bob по Y. Части модели Anchored и
	-- приварены к bell, поэтому двигаем модель целиком (PivotTo) вслед за твином bell.
	task.spawn(function()
		local phase = math.random() * math.pi * 2
		while model.Parent and bell.Parent do
			phase += 0.6
			local drift = Vector3.new(
				math.random(-cfg.DriftRadius, cfg.DriftRadius),
				0,
				math.random(-cfg.DriftRadius, cfg.DriftRadius)
			)
			local bob = math.sin(phase) * cfg.BobAmplitude
			local goal = origin + drift + Vector3.new(0, bob, 0)
			local duration = math.random(20, 35) / 10
			local tween = TweenService:Create(
				bell,
				TweenInfo.new(duration, Enum.EasingStyle.Sine),
				{ CFrame = CFrame.new(goal) }
			)
			tween:Play()
			local elapsed = 0
			while elapsed < duration and model.Parent do
				task.wait(0.05)
				elapsed += 0.05
				model:PivotTo(bell.CFrame)
			end
			if not model.Parent then break end
		end
	end)
end

-- ============================================================
-- ПЛАВАЮЩИЙ МУСОР
-- ============================================================

local function spawnTrash(zoneFolder, zoneConfig)
	local cfg = GameConfig.Trash
	local point = randomPoint(zoneFolder:FindFirstChild("CreatureSpawnPoints"))
	if not point then return end

	local kind = cfg.Kinds[math.random(1, #cfg.Kinds)]

	local part = Instance.new("Part")
	part.Name = "FloatingTrash"
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Shape = kind.Shape == "Cylinder" and Enum.PartType.Cylinder or Enum.PartType.Block
	part.Color = kind.Color
	part.Material = Enum.Material.SmoothPlastic
	part.Transparency = 0.1
	part.Anchored = true
	part.CanCollide = false
	part.CFrame = point.CFrame * CFrame.new(0, math.random(2, 6), 0)

	part:SetAttribute("Health", cfg.Health)
	part:SetAttribute("TrashValue", math.floor(cfg.BaseValue * zoneConfig.CatchValueMultiplier))
	part:SetAttribute("Trash", true)
	part:SetAttribute("TrashKind", kind.Id)

	part.Parent = zoneFolder:FindFirstChild("Creatures") or zoneFolder

	-- Медленный дрейф + лёгкое вращение
	local origin = part.Position
	task.spawn(function()
		while part.Parent do
			local drift = Vector3.new(math.random(-8, 8), math.random(-3, 3), math.random(-8, 8))
			local goal = origin + drift
			local tween = TweenService:Create(
				part,
				TweenInfo.new(math.random(30, 50) / 10, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ CFrame = CFrame.new(goal) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0) }
			)
			tween:Play()
			tween.Completed:Wait()
			if not part.Parent then break end
		end
	end)
end

-- ============================================================
-- РЕСУРСНЫЙ БЛОК (для Crusher Drill)
-- ============================================================

local function spawnResourceBlock(zoneFolder, zoneConfig)
	local point = randomPoint(zoneFolder:FindFirstChild("ResourceSpawnPoints"))
	if not point then return end

	local possibleResources = resourceIdsByHazard[zoneConfig.HazardLevel] or resourceIdsByHazard[0]
	local resourceId = possibleResources[math.random(1, #possibleResources)]

	local block = Instance.new("Part")
	block.Name = "ResourceBlock"
	block.Shape = Enum.PartType.Block
	block.Size = Vector3.new(3, 3, 3)
	block.Anchored = true
	block.CanCollide = true
	block.CFrame = point.CFrame
	block.Material = Enum.Material.Rock

	block:SetAttribute("Health", RESOURCE_BLOCK_BASE_HEALTH)
	block:SetAttribute("ResourceId", resourceId)
	block:SetAttribute("Amount", math.random(1, 3))

	block.Parent = zoneFolder:FindFirstChild("Resources") or zoneFolder
end

-- ============================================================
-- Главный цикл спавна по зоне
-- ============================================================

function ZoneSpawnerService.StartSpawningForZone(zoneId)
	local zoneConfig = getZoneConfig(zoneId)
	if not zoneConfig then
		warn("[ZoneSpawnerService] Неизвестная зона:", zoneId)
		return
	end

	local zoneFolder = workspace:FindFirstChild("Zones") and workspace.Zones:FindFirstChild(zoneId)
	if not zoneFolder then
		warn("[ZoneSpawnerService] Папка зоны не найдена в workspace:", zoneId)
		return
	end

	task.spawn(function()
		while true do
			task.wait(SPAWN_CHECK_INTERVAL)

			local creaturesFolder = zoneFolder:FindFirstChild("Creatures")
			local creatures = creaturesFolder and creaturesFolder:GetChildren() or {}

			-- Считаем медуз и мусор раздельно (лежат в одной папке Creatures)
			local jellyCount, trashCount = 0, 0
			for _, obj in ipairs(creatures) do
				if obj:GetAttribute("Trash") then
					trashCount += 1
				elseif obj:GetAttribute("Catchable") then
					jellyCount += 1
				end
			end

			if jellyCount < GameConfig.Jellyfish.MaxPerZone then
				spawnJellyfish(zoneFolder, zoneConfig)
			end
			if trashCount < GameConfig.Trash.MaxPerZone then
				spawnTrash(zoneFolder, zoneConfig)
			end

			local resourcesFolder = zoneFolder:FindFirstChild("Resources")
			local currentResources = resourcesFolder and #resourcesFolder:GetChildren() or 0
			if currentResources < MAX_RESOURCE_BLOCKS_PER_ZONE then
				spawnResourceBlock(zoneFolder, zoneConfig)
			end
		end
	end)
end

function ZoneSpawnerService.StartAllZones()
	for _, zone in ipairs(GameConfig.Zones) do
		ZoneSpawnerService.StartSpawningForZone(zone.Id)
	end
end

return ZoneSpawnerService
