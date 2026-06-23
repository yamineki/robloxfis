--[[
	ToolController.client.lua  (StarterPlayerScripts)

	Управление двумя пушками, которые игрок получает у NPC Quartermaster:
	  • BubbleCannon — стреляет ПУЗЫРЯМИ (прозрачные синие неоновые парты, пульсирующие
	    размером), ловит МЕДУЗ и лопает плавающий МУСОР.
	  • CrusherDrill — дробит ресурсные блоки.

	Логика: ловим Tool.Activated на каждом из инструментов (они кладутся в Backpack
	сервером), делаем рейкаст под курсор, ищем валидную цель по АТРИБУТАМ и шлём её
	на сервер. Сервер перепроверяет дистанцию/файрейт/валидность (анти-чит).

	Пузырь — чисто визуальный клиентский эффект, на геймплей не влияет.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local camera = workspace.CurrentCamera

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local FireHarpoonRemote = Remotes:WaitForChild("FireHarpoon")
local FireDrillRemote = Remotes:WaitForChild("FireDrill")
local CatchResultRemote = Remotes:WaitForChild("CatchResult")
local DrillOverheatRemote = Remotes:WaitForChild("DrillOverheat")

local drillOverheated = false

-- ============================================================
-- Поиск валидной цели
-- ============================================================

-- Поднимаемся по иерархии от попавшего парта, ищем предка (или сам парт) с нужным атрибутом.
local function findAncestorWithAttribute(instance, attribute)
	local current = instance
	while current and current ~= workspace do
		if current:GetAttribute(attribute) ~= nil then
			return current
		end
		current = current.Parent
	end
	return nil
end

local function raycastFromMouse()
	local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { player.Character }
	return workspace:Raycast(unitRay.Origin, unitRay.Direction * 250, params)
end

-- ============================================================
-- ПУЗЫРЬ — прозрачный синий неоновый парт, летит к цели и пульсирует размером
-- ============================================================

local function muzzlePosition(tool)
	local handle = tool:FindFirstChild("Handle")
	local muzzle = handle and handle:FindFirstChild("Muzzle")
	if muzzle and muzzle:IsA("Attachment") then
		return muzzle.WorldPosition
	end
	if handle then
		return handle.Position
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return root and root.Position or Vector3.new(0, 0, 0)
end

-- Пузырь — КВАДРАТНЫЙ неоновый синий парт, летит МЕДЛЕННО к цели и слегка пульсирует размером.
local function spawnBubble(fromPos, toPos)
	local baseSize = 1.4
	local bubble = Instance.new("Part")
	bubble.Shape = Enum.PartType.Block          -- квадратный пузырь по дизайну
	bubble.Size = Vector3.new(baseSize, baseSize, baseSize)
	bubble.Color = Color3.fromRGB(90, 190, 255)
	bubble.Material = Enum.Material.Neon
	bubble.Transparency = 0.4
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CastShadow = false
	bubble.CFrame = CFrame.new(fromPos)
	bubble.Parent = workspace

	-- Лёгкое свечение пузыря
	local light = Instance.new("PointLight")
	light.Color = bubble.Color
	light.Range = 7
	light.Brightness = 1.6
	light.Parent = bubble

	-- Пульсация размера + лёгкое вращение на лету (слегка "дышит")
	local pulseConn
	local startClock = os.clock()
	pulseConn = RunService.RenderStepped:Connect(function()
		if not bubble.Parent then
			pulseConn:Disconnect()
			return
		end
		local s = baseSize + math.sin((os.clock() - startClock) * 10) * 0.28
		bubble.Size = Vector3.new(s, s, s)
	end)

	-- МЕДЛЕННЫЙ полёт к цели (фиксированная скорость ~ 26 studs/сек)
	local distance = (toPos - fromPos).Magnitude
	local travelTime = math.clamp(distance / 26, 0.3, 1.6)
	local travel = TweenService:Create(bubble, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.new(toPos) * CFrame.Angles(0, math.rad(120), 0),
	})
	travel:Play()
	travel.Completed:Connect(function()
		-- "Лопается": резко раздувается и исчезает
		if pulseConn then pulseConn:Disconnect() end
		local pop = TweenService:Create(bubble, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Size = Vector3.new(3.4, 3.4, 3.4),
			Transparency = 1,
		})
		pop:Play()
		Debris:AddItem(bubble, 0.25)
	end)
end

-- ============================================================
-- ЛАЗЕР CRUSHER DRILL — заряжаемый направленный луч
-- ============================================================

-- Полоса заряда над пушкой (billboard на Handle), пока игрок держит кнопку.
local function makeChargeBar(handle)
	local gui = Instance.new("BillboardGui")
	gui.Name = "DrillChargeBar"
	gui.Adornee = handle
	gui.Size = UDim2.fromOffset(90, 12)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = handle

	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bg.BackgroundTransparency = 0.2
	bg.BorderSizePixel = 0
	bg.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = GameConfig.CrusherLaser.Color
	fill.BorderSizePixel = 0
	fill.Parent = bg
	return gui, fill
end

-- Визуальный луч из дула в направлении точки прицела.
local function spawnLaserBeam(fromPos, toPos)
	local cfg = GameConfig.CrusherLaser
	local dir = (toPos - fromPos)
	local length = math.min(dir.Magnitude, cfg.BaseBeamLength + 40)
	if length < 1 then length = 1 end
	local midpoint = fromPos + dir.Unit * (length / 2)

	local beam = Instance.new("Part")
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.Material = Enum.Material.Neon
	beam.Color = cfg.Color
	beam.Size = Vector3.new(cfg.BeamThickness, cfg.BeamThickness, length)
	beam.CFrame = CFrame.lookAt(midpoint, toPos)
	beam.Transparency = 0.15
	beam.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = cfg.Color
	light.Range = 12
	light.Brightness = 2.5
	light.Parent = beam

	local fade = TweenService:Create(beam, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
		Transparency = 1,
		Size = Vector3.new(cfg.BeamThickness * 2.2, cfg.BeamThickness * 2.2, length),
	})
	fade:Play()
	Debris:AddItem(beam, 0.3)
end

-- Время полного заряда с учётом уровня FireRate (читаем через урон? на клиенте нет
-- доступа к уровням — используем базовое время; сервер всё равно подтверждает выстрел).
local function chargeTimeFor()
	-- Клиент не знает уровней прокачки, поэтому копит до базового времени; реальный
	-- эффект скейла применяет сервер (длина/урон). Это лишь UX-таймер заряда.
	return GameConfig.CrusherLaser.BaseChargeTime
end

-- ============================================================
-- Стрельба
-- ============================================================

local function fireBubbleCannon(tool)
	local result = raycastFromMouse()
	local fromPos = muzzlePosition(tool)
	local toPos
	local target

	if result then
		toPos = result.Position
		-- Пузырь ловит ТОЛЬКО медуз — мусор и ресурсы для него невидимы (исключительность по дизайну).
		target = findAncestorWithAttribute(result.Instance, "Catchable")
	else
		local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
		toPos = unitRay.Origin + unitRay.Direction * 60
	end

	-- Пузырь рисуем ВСЕГДА (приятная отдача), на сервер шлём только если есть цель.
	spawnBubble(fromPos, toPos)

	if target then
		FireHarpoonRemote:FireServer(target)
	end
end

-- Выпуск заряженного лазера: рисуем луч и шлём цель (мусор/ресурс) на сервер.
local function releaseLaser(tool)
	if drillOverheated then return end
	local fromPos = muzzlePosition(tool)
	local result = raycastFromMouse()
	local toPos
	if result then
		toPos = result.Position
	else
		local unitRay = camera:ViewportPointToRay(mouse.X, mouse.Y)
		toPos = unitRay.Origin + unitRay.Direction * GameConfig.CrusherLaser.BaseBeamLength
	end

	spawnLaserBeam(fromPos, toPos)

	-- Лазер дробит ресурсные блоки И крупный мусор перед собой.
	-- Лазер дробит ресурсы/мусор, но НИКОГДА медуз — даже если луч случайно задел силуэт.
	local target
	if result and not findAncestorWithAttribute(result.Instance, "Catchable") then
		target = findAncestorWithAttribute(result.Instance, "ResourceId")
			or findAncestorWithAttribute(result.Instance, "Trash")
	end
	if target then
		FireDrillRemote:FireServer(target, true) -- true = заряженный лазер
	end
end

-- Заряд дробилки: зажал кнопку -> копится заряд (полоса над пушкой) -> при полном
-- заряде выпускается лазер. Отпустил раньше -> заряд сбрасывается.
local drillCharge = setmetatable({}, { __mode = "k" }) -- [tool] = { active=bool }

local function startCharging(tool)
	if drillOverheated then return end
	local handle = tool:FindFirstChild("Handle")
	if not handle then return end
	if drillCharge[tool] and drillCharge[tool].active then return end

	local state = { active = true }
	drillCharge[tool] = state

	task.spawn(function()
		local gui, fill = makeChargeBar(handle)
		local startClock = os.clock()
		local fullTime = chargeTimeFor()
		while state.active and tool.Parent do
			local frac = math.clamp((os.clock() - startClock) / fullTime, 0, 1)
			fill.Size = UDim2.new(frac, 0, 1, 0)
			if frac >= 1 then
				releaseLaser(tool)
				break
			end
			RunService.RenderStepped:Wait()
		end
		state.active = false
		if gui then gui:Destroy() end
	end)
end

local function stopCharging(tool)
	local state = drillCharge[tool]
	if state then state.active = false end
end

-- ============================================================
-- Привязка Activated к инструментам по мере их появления
-- ============================================================

local connectedTools = setmetatable({}, { __mode = "k" })

local function hookTool(tool)
	if not tool:IsA("Tool") then return end
	if connectedTools[tool] then return end
	if tool.Name ~= "BubbleCannon" and tool.Name ~= "CrusherDrill" then return end
	connectedTools[tool] = true

	if tool.Name == "BubbleCannon" then
		tool.Activated:Connect(function()
			fireBubbleCannon(tool)
		end)
	else
		-- Дробилка: зажатие = заряд, отпускание = сброс/выстрел при полном заряде.
		tool.Activated:Connect(function()
			startCharging(tool)
		end)
		tool.Deactivated:Connect(function()
			stopCharging(tool)
		end)
		tool.Unequipped:Connect(function()
			stopCharging(tool)
		end)
	end
end

local function watchContainer(container)
	if not container then return end
	for _, child in ipairs(container:GetChildren()) do
		hookTool(child)
	end
	container.ChildAdded:Connect(hookTool)
end

local function onCharacter(character)
	watchContainer(character)
end

if player.Character then
	onCharacter(player.Character)
end
player.CharacterAdded:Connect(onCharacter)

-- Backpack пересоздаётся при каждом респауне
local function watchBackpack()
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack then
		watchContainer(backpack)
	end
end
watchBackpack()
player.ChildAdded:Connect(function(child)
	if child:IsA("Backpack") then
		watchContainer(child)
	end
end)

-- ============================================================
-- Серверные ответы
-- ============================================================

DrillOverheatRemote.OnClientEvent:Connect(function(isOverheated)
	drillOverheated = isOverheated
end)
