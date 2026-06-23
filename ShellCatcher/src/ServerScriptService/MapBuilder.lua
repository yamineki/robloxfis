--[[
	MapBuilder.lua  (ServerScriptService, ModuleScript)
	Строит ВСЮ геометрию игры кодом из простых Part — остров, 4 зоны лова,
	здания, NPC. Это заглушка-скелет: формы, размеры и цвета условные,
	но ИМЕНА и ИЕРАРХИЯ совпадают с тем, что ожидают остальные сервисы
	(ZoneService, ZoneSpawnerService, AfkSorterService и т.д.), поэтому
	игра полностью играбельна уже на этой геометрии.

	Вызывается ОДИН раз при старте сервера из Main.server.lua, ДО
	ZoneSpawnerService.StartAllZones().

	КАК ЗАМЕНИТЬ ЗАГЛУШКИ НА СВОЙ АРТ — см. подробный гайд в конце файла
	и в docs/README.md (раздел "Замена заглушек карты").
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local MapBuilder = {}

-- ============================================================
-- Хелперы создания Part-заглушек
-- ============================================================

local function makePart(name, parent, size, position, color, material, shape)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color or Color3.fromRGB(120, 120, 130)
	part.Material = material or Enum.Material.SmoothPlastic
	part.Shape = shape or Enum.PartType.Block
	part.Anchored = true
	part.Parent = parent
	return part
end

-- Невидимая точка спавна — обычная Part без коллизии и без видимости,
-- остальные сервисы используют только её CFrame
local function makeSpawnPoint(name, parent, position)
	local point = Instance.new("Part")
	point.Name = name
	point.Size = Vector3.new(2, 1, 2)
	point.Position = position
	point.Anchored = true
	point.CanCollide = false
	point.Transparency = 1
	point.Parent = parent
	return point
end

-- Текстовая подпись над заглушкой здания/NPC (BillboardGui), чтобы было понятно
-- что где, пока нет реальных моделей
local function addNameTag(part, text, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.fromOffset(160, 40)
	billboard.StudsOffset = Vector3.new(0, part.Size.Y / 2 + 1.5, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 0.4
	label.BackgroundColor3 = Color3.new(0, 0, 0)
	label.Text = text
	label.TextColor3 = color or Color3.new(1, 1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = billboard

	return billboard
end

-- Простой ProximityPrompt-каркас на здании — название действия настраивается вызывающим кодом
local function addProximityPrompt(part, actionText, objectText, holdDuration)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = holdDuration or 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	return prompt
end

-- Позиция на кольце острова по углу (градусы) и радиусу (studs от центра)
local function ringPosition(angleDeg, radius, y)
	local a = math.rad(angleDeg or 0)
	return Vector3.new(math.cos(a) * radius, y or 0, math.sin(a) * radius)
end

-- ============================================================
-- ПОДЛОДКА-ЗАГЛУШКА (Model "Submarine")
-- Узнаваемый силуэт субмарины из простых Part: корпус-цилиндр, рубка, перископ,
-- хвостовые плавники, винт, неоновые иллюминаторы. Якорный плейсхолдер — игрок
-- заменит на свою модель, сохранив имя Model "Submarine".
-- ============================================================
local function buildSubmarine(name, parent, cframe)
	local model = Instance.new("Model")
	model.Name = name or "Submarine"

	local function piece(pname, size, offsetCFrame, color, material, shape)
		local p = Instance.new("Part")
		p.Name = pname
		p.Size = size
		p.CFrame = cframe * offsetCFrame
		p.Color = color
		p.Material = material or Enum.Material.Metal
		p.Shape = shape or Enum.PartType.Block
		p.Anchored = true
		p.CanCollide = true
		p.Parent = model
		return p
	end

	local hullColor = Color3.fromRGB(210, 200, 70)   -- жёлтая «классическая» субмарина-заглушка
	local trimColor = Color3.fromRGB(60, 70, 90)

	-- Корпус (длинный цилиндр лежит вдоль локальной оси X — Cylinder вытянут по X)
	local hull = piece("Hull", Vector3.new(20, 6, 6), CFrame.new(0, 0, 0), hullColor, Enum.Material.Metal, Enum.PartType.Cylinder)
	model.PrimaryPart = hull
	-- Нос-конус
	piece("Nose", Vector3.new(3, 4.6, 4.6), CFrame.new(10.5, 0, 0), hullColor, Enum.Material.Metal, Enum.PartType.Ball)
	-- Корма
	piece("Tail", Vector3.new(3, 4.6, 4.6), CFrame.new(-10.5, 0, 0), hullColor, Enum.Material.Metal, Enum.PartType.Ball)
	-- Рубка
	piece("ConningTower", Vector3.new(4, 3, 3.4), CFrame.new(1, 4, 0), trimColor)
	-- Перископ
	piece("Periscope", Vector3.new(0.4, 3, 0.4), CFrame.new(1, 6.4, 0), trimColor, Enum.Material.Metal, Enum.PartType.Cylinder)
	-- Хвостовые плавники
	piece("FinTop", Vector3.new(3, 3, 0.4), CFrame.new(-9, 2.4, 0), trimColor)
	piece("FinSide", Vector3.new(3, 0.4, 5), CFrame.new(-9, 0, 0), trimColor)
	-- Винт
	piece("Propeller", Vector3.new(0.5, 4, 4), CFrame.new(-12.4, 0, 0), Color3.fromRGB(120, 120, 130), Enum.Material.Metal, Enum.PartType.Cylinder)
	-- Иллюминаторы (неоновые)
	for i = -1, 1 do
		local port = piece("Porthole", Vector3.new(0.4, 1.1, 1.1), CFrame.new(i * 4, 0.5, 3.05), Color3.fromRGB(120, 230, 255), Enum.Material.Neon, Enum.PartType.Cylinder)
		port.CanCollide = false
	end

	model.Parent = parent
	return model
end

-- Домик-заглушка для NPC без отдельного игрового здания (Quartermaster/Ferry).
-- Возвращает Part-«здание», на который вешается NameTag.
local function buildHut(name, parent, position, color, labelText)
	local body = makePart(name, parent, Vector3.new(10, 12, 10), position + Vector3.new(0, 6, 0), color)
	-- Дверной проём (тёмный блок-вырез) и крыша-призма для узнаваемости
	makePart(name .. "_Roof", parent, Vector3.new(12, 3, 12), position + Vector3.new(0, 13.5, 0), color:Lerp(Color3.new(0, 0, 0), 0.35))
	local door = makePart(name .. "_Door", parent, Vector3.new(3, 5, 0.5), position + Vector3.new(0, 2.5, 5), Color3.fromRGB(40, 30, 25))
	door.CanCollide = false
	if labelText then
		addNameTag(body, labelText, color)
	end
	return body
end

-- ============================================================
-- 1. ОСТРОВ-ХАБ (общий для всех 6 игроков)
-- ============================================================

function MapBuilder.BuildIsland()
	local island = workspace:FindFirstChild("Island")
	if island then island:Destroy() end

	-- IslandSpawnPoints лежит отдельно в workspace (не внутри Island), поэтому
	-- чистим его отдельно, иначе при перезапуске скрипта появится дубль-папка.
	local oldSpawns = workspace:FindFirstChild("IslandSpawnPoints")
	if oldSpawns then oldSpawns:Destroy() end

	island = Instance.new("Folder")
	island.Name = "Island"
	island.Parent = workspace

	-- Основа острова — большая плоская плита песочного цвета
	local groundPart = makePart(
		"IslandGround", island,
		Vector3.new(120, 4, 120), Vector3.new(0, 0, 0),
		Color3.fromRGB(210, 190, 140), Enum.Material.Sand
	)

	-- Настоящий SpawnLocation, чтобы Roblox корректно спавнил игроков на острове
	-- при первом заходе (иначе персонаж падает из случайной точки над миром).
	-- onCharacterAdded потом всё равно телепортирует на IslandSpawnPoints, но это
	-- убирает полусекундное падение при заходе.
	local spawnLocation = Instance.new("SpawnLocation")
	spawnLocation.Name = "IslandSpawnLocation"
	spawnLocation.Size = Vector3.new(12, 1, 12)
	spawnLocation.Position = Vector3.new(0, 3, 0)
	spawnLocation.Anchored = true
	spawnLocation.Neutral = true
	spawnLocation.Duration = 0 -- без форс-филда
	spawnLocation.Color = Color3.fromRGB(230, 210, 160)
	spawnLocation.Parent = island

	-- Точки спавна персонажей на острове (используются ZoneService.ReturnToIsland)
	local islandSpawns = Instance.new("Folder")
	islandSpawns.Name = "IslandSpawnPoints"
	islandSpawns.Parent = workspace -- ZoneService ищет именно workspace.IslandSpawnPoints

	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local x = math.cos(angle) * 15
		local z = math.sin(angle) * 15
		makeSpawnPoint("Spawn_" .. i, islandSpawns, Vector3.new(x, 4, z))
	end

	return island
end

-- ============================================================
-- 2. ЗДАНИЯ ОСТРОВА (заглушки-кубы, разного цвета по типу здания)
-- ============================================================

local buildingColors = {
	shop_basic     = Color3.fromRGB(90, 200, 120),  -- зелёный — торговая лавка
	storage_room   = Color3.fromRGB(160, 140, 100), -- коричневый — склад
	afk_dock       = Color3.fromRGB(80, 200, 255),  -- голубой — AFK-машина
	skin_workshop  = Color3.fromRGB(230, 90, 200),  -- розовый — мастерская скинов
	rebirth_altar  = Color3.fromRGB(250, 200, 70),  -- золотой — алтарь ребирта
}

function MapBuilder.BuildIslandBuildings()
	local island = workspace:FindFirstChild("Island")
	if not island then return end

	local buildingsFolder = Instance.new("Folder")
	buildingsFolder.Name = "Buildings"
	buildingsFolder.Parent = island

	-- Здания расставлены по кольцу острова по СВОЕМУ углу (совпадает с углом «своего»
	-- NPC), 1 здание = 1 NPC. Радиус — общий из GameConfig.IslandLayout.
	local buildingRadius = GameConfig.IslandLayout.BuildingRadius
	for index, buildingConfig in ipairs(GameConfig.IslandBuildings) do
		local angleDeg = buildingConfig.Angle or ((index / #GameConfig.IslandBuildings) * 360)
		local pos = ringPosition(angleDeg, buildingRadius, 6)

		local buildingPart = makePart(
			buildingConfig.Id, buildingsFolder,
			Vector3.new(10, 12, 10), pos,
			buildingColors[buildingConfig.Id] or Color3.fromRGB(150, 150, 150)
		)
		-- Крыша для узнаваемости силуэта здания
		makePart(
			buildingConfig.Id .. "_Roof", buildingsFolder,
			Vector3.new(12, 3, 12), pos + Vector3.new(0, 7.5, 0),
			(buildingColors[buildingConfig.Id] or Color3.fromRGB(150, 150, 150)):Lerp(Color3.new(0, 0, 0), 0.35)
		)

		addNameTag(buildingPart, buildingConfig.Name, buildingColors[buildingConfig.Id])

		-- Каждое здание получает ProximityPrompt — конкретная логика открытия окна
		-- привязывается в Main.server.lua (см. ниже), тут только сам прompt-каркас.
		local prompt = addProximityPrompt(buildingPart, "Open", buildingConfig.Name)
		prompt.Name = "BuildingPrompt_" .. buildingConfig.Id

		-- SoundId-заглушка на ambient-звук здания (можно вставить зацикленный фоновый звук,
		-- например жужжание станка для afk_dock). Пустой SoundId — звука не будет, пока
		-- не вставишь свой ID.
		local ambientSound = Instance.new("Sound")
		ambientSound.Name = "AmbientSound"
		ambientSound.SoundId = "" -- TODO: rbxassetid://ЗАМЕНИ_НА_СВОЙ_ЗВУК
		ambientSound.Looped = true
		ambientSound.Volume = 0.3
		ambientSound.Parent = buildingPart
	end
end

-- ============================================================
-- 3. NPC ОСТРОВА — полноценные модели-персонажи с ролями
-- Строятся из GameConfig.NPCs. Каждый NPC — Model с PrimaryPart "HumanoidRootPart",
-- телом/головой, двухстрочным бейджем (имя + роль), лёгким покачиванием и ProximityPrompt.
-- Атрибут "Role" на модели читает NPCService, чтобы понять что делать при разговоре.
-- ============================================================

local roleActionText = {
	Quartermaster = "Get Both Cannons",
	FerryCaptain  = "Travel to Zones",
	Shopkeeper    = "Open Shop",
	StorageKeeper = "Inventory / Sell",
	AfkOperator   = "Auto-Sorter Dock",
	RebirthPriest = "Rebirth",
}

local roleSubtitle = {
	Quartermaster = "Quartermaster",
	FerryCaptain  = "Ferry Captain",
	Shopkeeper    = "Trader",
	StorageKeeper = "Net Mender",
	AfkOperator   = "Dock Hand",
	RebirthPriest = "Tide Priestess",
}

-- Двухстрочный бейдж (имя + роль) над NPC
local function addNpcBadge(rootPart, height, name, subtitle, color)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "NameTag"
	billboard.Size = UDim2.fromOffset(190, 54)
	billboard.StudsOffset = Vector3.new(0, height / 2 + 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = rootPart

	local container = Instance.new("Frame")
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundColor3 = Color3.fromRGB(15, 22, 30)
	container.BackgroundTransparency = 0.25
	container.BorderSizePixel = 0
	container.Parent = billboard
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = container
	local stroke = Instance.new("UIStroke")
	stroke.Color = color or Color3.new(1, 1, 1)
	stroke.Thickness = 2
	stroke.Parent = container

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.58, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = name
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Parent = container

	local roleLabel = Instance.new("TextLabel")
	roleLabel.Position = UDim2.fromScale(0, 0.58)
	roleLabel.Size = UDim2.new(1, 0, 0.42, 0)
	roleLabel.BackgroundTransparency = 1
	roleLabel.Text = subtitle
	roleLabel.TextColor3 = color or Color3.fromRGB(200, 220, 235)
	roleLabel.Font = Enum.Font.GothamMedium
	roleLabel.TextScaled = true
	roleLabel.Parent = container
end

-- Сборка стилизованной модели персонажа из Part'ов (без рига — лёгкая заглушка,
-- которую легко заменить на свой Rig, сохранив имя модели и атрибут Role).
local function buildNpcModel(npcConfig, position)
	local model = Instance.new("Model")
	model.Name = "NPC_" .. npcConfig.Id
	model:SetAttribute("Role", npcConfig.Role)
	model:SetAttribute("NpcId", npcConfig.Id)

	local skin = Color3.fromRGB(255, 220, 185)
	local outfit = npcConfig.Color or Color3.fromRGB(120, 130, 150)

	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Position = position + Vector3.new(0, 3, 0)
	root.Transparency = 1
	root.Anchored = true
	root.CanCollide = false
	root.Parent = model
	model.PrimaryPart = root

	local function limb(name, size, offset, color, shape)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.CFrame = root.CFrame * CFrame.new(offset)
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		p.Shape = shape or Enum.PartType.Block
		p.Anchored = true
		p.CanCollide = false
		p.Parent = model
		return p
	end

	limb("Torso", Vector3.new(2, 2.2, 1), Vector3.new(0, 0, 0), outfit)
	limb("Head", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 1.75, 0), skin, Enum.PartType.Ball)
	limb("LeftLeg", Vector3.new(0.7, 2, 0.8), Vector3.new(-0.55, -2.1, 0), Color3.fromRGB(45, 55, 70))
	limb("RightLeg", Vector3.new(0.7, 2, 0.8), Vector3.new(0.55, -2.1, 0), Color3.fromRGB(45, 55, 70))
	limb("LeftArm", Vector3.new(0.6, 2, 0.7), Vector3.new(-1.35, 0, 0), outfit)
	limb("RightArm", Vector3.new(0.6, 2, 0.7), Vector3.new(1.35, 0, 0), outfit)

	addNpcBadge(root, 6, npcConfig.Name, roleSubtitle[npcConfig.Role] or "Islander", npcConfig.Color)

	local prompt = addProximityPrompt(root, roleActionText[npcConfig.Role] or "Talk", npcConfig.Name)
	prompt.Name = "NPCPrompt"
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false

	local voiceSound = Instance.new("Sound")
	voiceSound.Name = "VoiceSound"
	voiceSound.SoundId = ""
	voiceSound.Volume = 0.5
	voiceSound.Parent = root

	return model, root
end

function MapBuilder.BuildIslandNPCs()
	local island = workspace:FindFirstChild("Island")
	if not island then return end

	local npcFolder = Instance.new("Folder")
	npcFolder.Name = "NPCs"
	npcFolder.Parent = island

	-- Отдельные постройки-заглушки для NPC без игрового здания (Quartermaster/Ferry)
	-- и причал с подлодкой. Лежат в той же папке Buildings рядом со своим NPC.
	local buildingsFolder = island:FindFirstChild("Buildings")

	local npcRadius = GameConfig.IslandLayout.NpcRadius
	local subRadius = GameConfig.IslandLayout.SubmarineRadius

	for _, npcConfig in ipairs(GameConfig.NPCs) do
		-- NPC стоит «у входа» своего здания — на том же угле, чуть ближе к центру.
		local position = ringPosition(npcConfig.Angle, npcRadius, 2)

		-- Если у NPC нет игрового здания — строим домик-заглушку у него за спиной (дальше от центра).
		if not npcConfig.BuildingId and buildingsFolder then
			local hutPos = ringPosition(npcConfig.Angle, GameConfig.IslandLayout.BuildingRadius, 0)
			buildHut("station_" .. npcConfig.Id, buildingsFolder, hutPos, npcConfig.BuildingColor or Color3.fromRGB(120, 130, 150), npcConfig.BuildingName)
		end

		-- Подлодка-отправление на «берегу» рядом с Ферри (дальше всех от центра, на воде).
		if npcConfig.HasSubmarine then
			local subPos = ringPosition(npcConfig.Angle, subRadius, -1)
			-- Носом наружу от острова (в сторону открытой воды).
			local outwardCFrame = CFrame.lookAt(subPos, subPos + ringPosition(npcConfig.Angle, 1, 0))
			buildSubmarine("ShoreSubmarine", island, outwardCFrame)
		end

		local model, root = buildNpcModel(npcConfig, position)
		model.Parent = npcFolder

		-- Лёгкое покачивание (idle bob) + разворот лицом к центру острова.
		task.spawn(function()
			local baseCFrame = CFrame.lookAt(root.Position, Vector3.new(0, root.Position.Y, 0))
			local t = math.random() * math.pi * 2
			while model.Parent do
				t += 0.08
				local bob = math.sin(t) * 0.18
				model:PivotTo(baseCFrame * CFrame.new(0, bob, 0))
				task.wait(0.06)
			end
		end)
	end
end

-- ============================================================
-- 4. ЗОНЫ ЛОВА (4 шт., каждая — отдельная площадка в стороне от острова)
-- ============================================================

local zoneColors = {
	reef    = Color3.fromRGB(255, 200, 150),
	kelp    = Color3.fromRGB(80, 180, 100),
	trench  = Color3.fromRGB(60, 70, 110),
	vent    = Color3.fromRGB(200, 70, 50),
}

-- Зоны расставлены по прямой линии друг за другом, с увеличивающимся отступом —
-- условное "погружение глубже" по дизайну. Координата Y тоже понижается, чтобы
-- буквально передать рост глубины.
local zoneWorldOffsets = {
	reef   = Vector3.new(250, 0, 0),
	kelp   = Vector3.new(450, -30, 0),
	trench = Vector3.new(650, -70, 0),
	vent   = Vector3.new(850, -120, 0),
}

function MapBuilder.BuildZone(zoneConfig)
	local zonesRoot = workspace:FindFirstChild("Zones")
	if not zonesRoot then
		zonesRoot = Instance.new("Folder")
		zonesRoot.Name = "Zones"
		zonesRoot.Parent = workspace
	end

	local existing = zonesRoot:FindFirstChild(zoneConfig.Id)
	if existing then existing:Destroy() end

	local zoneFolder = Instance.new("Folder")
	zoneFolder.Name = zoneConfig.Id
	zoneFolder.Parent = zonesRoot

	local worldOffset = zoneWorldOffsets[zoneConfig.Id] or Vector3.new(0, 0, 0)

	-- Дно зоны — большая плоская плита под водой, цвет по биому
	makePart(
		"ZoneFloor", zoneFolder,
		Vector3.new(150, 4, 150), worldOffset - Vector3.new(0, 20, 0),
		zoneColors[zoneConfig.Id] or Color3.fromRGB(100, 100, 140),
		Enum.Material.Slate
	)

	-- Невидимый блок-маркер "вход в зону" с подписью названия и стоимости разблокировки —
	-- реальный вход/выход обрабатывается через UI и ZoneService.EnterZone, это просто
	-- визуальный ориентир на острове/между зонами.
	local entranceMarker = makePart(
		"ZoneEntranceMarker", zoneFolder,
		Vector3.new(6, 10, 6), worldOffset + Vector3.new(0, -10, 0),
		zoneColors[zoneConfig.Id] or Color3.fromRGB(100, 100, 140)
	)
	addNameTag(
		entranceMarker,
		string.format("%s\n(%d Shells)", zoneConfig.Name, zoneConfig.UnlockCost),
		zoneColors[zoneConfig.Id]
	)

	-- Подлодка-база зоны: стоит на месте, пока игрок в зоне (его «дом» под водой).
	-- Игрок появляется рядом с ней. Плейсхолдер — заменяется на свою модель, имя "Submarine".
	local subCFrame = CFrame.new(worldOffset + Vector3.new(0, -15, 0))
	buildSubmarine("Submarine", zoneFolder, subCFrame)

	-- Точки спавна игрока при входе в зону (ZoneService.EnterZone ищет SpawnPoints) —
	-- кольцом вокруг подлодки, чтобы игрок «выныривал» рядом с ней.
	local spawnPoints = Instance.new("Folder")
	spawnPoints.Name = "SpawnPoints"
	spawnPoints.Parent = zoneFolder
	for i = 1, 6 do
		local angle = (i / 6) * math.pi * 2
		local x = math.cos(angle) * 14
		local z = math.sin(angle) * 14
		makeSpawnPoint("Spawn_" .. i, spawnPoints, worldOffset + Vector3.new(x, -13, z))
	end

	-- Точки спавна силуэтов добычи (ZoneSpawnerService ищет CreatureSpawnPoints)
	local creatureSpawnPoints = Instance.new("Folder")
	creatureSpawnPoints.Name = "CreatureSpawnPoints"
	creatureSpawnPoints.Parent = zoneFolder
	for i = 1, 14 do
		local x = math.random(-60, 60)
		local z = math.random(-60, 60)
		local y = math.random(-25, -5)
		makeSpawnPoint("CreatureSpawn_" .. i, creatureSpawnPoints, worldOffset + Vector3.new(x, y, z))
	end

	-- Точки спавна ресурсных блоков (ZoneSpawnerService ищет ResourceSpawnPoints)
	local resourceSpawnPoints = Instance.new("Folder")
	resourceSpawnPoints.Name = "ResourceSpawnPoints"
	resourceSpawnPoints.Parent = zoneFolder
	for i = 1, 10 do
		local x = math.random(-60, 60)
		local z = math.random(-60, 60)
		makeSpawnPoint("ResourceSpawn_" .. i, resourceSpawnPoints, worldOffset + Vector3.new(x, -19, z))
	end

	-- Пустые папки, куда ZoneSpawnerService будет класть спавненые силуэты/блоки
	local creaturesFolder = Instance.new("Folder")
	creaturesFolder.Name = "Creatures"
	creaturesFolder.Parent = zoneFolder

	local resourcesFolder = Instance.new("Folder")
	resourcesFolder.Name = "Resources"
	resourcesFolder.Parent = zoneFolder

	-- Зональный ambient-звук (например бурление воды/специфика биома) — заглушка
	local zoneAmbient = Instance.new("Sound")
	zoneAmbient.Name = "ZoneAmbientSound"
	zoneAmbient.SoundId = "" -- TODO: rbxassetid://ЗАМЕНИ_НА_СВОЙ_ЗВУК (амбиент зоны, looped)
	zoneAmbient.Looped = true
	zoneAmbient.Volume = 0.25
	zoneAmbient.Parent = entranceMarker

	return zoneFolder
end

function MapBuilder.BuildAllZones()
	for _, zoneConfig in ipairs(GameConfig.Zones) do
		MapBuilder.BuildZone(zoneConfig)
	end
end

-- ============================================================
-- Точка входа: строит абсолютно всё за один вызов
-- ============================================================

function MapBuilder.BuildEverything()
	MapBuilder.BuildIsland()
	MapBuilder.BuildIslandBuildings()
	MapBuilder.BuildIslandNPCs()
	MapBuilder.BuildAllZones()
	print("[MapBuilder] Карта-заглушка построена: остров, зданий — "
		.. #GameConfig.IslandBuildings .. ", зон — " .. #GameConfig.Zones)
end

return MapBuilder

--[[
	============================================================
	КАК ЗАМЕНИТЬ ЗАГЛУШКИ НА СВОЙ АРТ (краткая версия — полная в docs/README.md)
	============================================================

	1. ОСТРОВ (IslandGround):
	   Удали или спрячь Part "IslandGround", создай/импортируй свою модель острова
	   в то же место (around Vector3.new(0,0,0)). Главное — оставить Folder
	   "IslandSpawnPoints" в workspace с точками спавна персонажа.

	2. ЗДАНИЯ (workspace.Island.Buildings.<building_id>):
	   Каждое здание — один Part с ProximityPrompt-ребёнком "BuildingPrompt_<id>".
	   Замени сам Part на свою модель (Model), но переименуй Model точно так же
	   (например "shop_basic"), и перенеси внутрь Model дочерний ProximityPrompt
	   с тем же именем — остальной код ищет prompt по имени, не по типу Part/Model.

	3. NPC (workspace.Island.NPCs.NPC_<n>):
	   Замени капсулу на Rig/Model персонажа. Сохрани ProximityPrompt
	   "NPCPrompt_<n>" внутри модели.

	4. ЗОНЫ (workspace.Zones.<zone_id>):
	   - ZoneFloor — замени на свою геометрию дна/рельефа зоны.
	   - SpawnPoints / CreatureSpawnPoints / ResourceSpawnPoints — НЕ переименовывай
	     эти Folder, остальной код ищет их по точному имени. Можно свободно менять
	     количество точек внутри и их позиции — просто перетаскивай Part в Studio.
	   - Creatures / Resources — оставь пустыми, туда сервер кладёт спавненые объекты
	     во время игры (не трогай руками).

	5. СИЛУЭТЫ ДОБЫЧИ И РЕСУРСНЫЕ БЛОКИ:
	   Сейчас они генерируются кодом в ZoneSpawnerService.lua как чёрные кубы/камни
	   (см. функции spawnSilhouette/spawnResourceBlock). Чтобы заменить на свою модель:
	   замени там Instance.new("Part") на клонирование своего шаблона из
	   ReplicatedStorage (например ReplicatedStorage.Models.SilhouetteTemplate:Clone()),
	   и не забудь после клонирования всё равно проставлять Attribute Health/BaseValue/
	   CreatureId / ResourceId/Amount — на них зависит вся боевая логика.
]]
