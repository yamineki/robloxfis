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

local function spawnBubble(fromPos, toPos)
	local bubble = Instance.new("Part")
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.new(1.1, 1.1, 1.1)
	bubble.Color = Color3.fromRGB(90, 190, 255)
	bubble.Material = Enum.Material.Neon
	bubble.Transparency = 0.55
	bubble.Anchored = true
	bubble.CanCollide = false
	bubble.CanQuery = false
	bubble.CFrame = CFrame.new(fromPos)
	bubble.Parent = workspace

	-- Лёгкое свечение пузыря
	local light = Instance.new("PointLight")
	light.Color = bubble.Color
	light.Range = 6
	light.Brightness = 1.5
	light.Parent = bubble

	-- Пульсация размера на лету (слегка "дышит")
	local pulseConn
	local startClock = os.clock()
	pulseConn = RunService.RenderStepped:Connect(function()
		if not bubble.Parent then
			pulseConn:Disconnect()
			return
		end
		local s = 1.1 + math.sin((os.clock() - startClock) * 18) * 0.22
		bubble.Size = Vector3.new(s, s, s)
	end)

	-- Полёт к цели
	local distance = (toPos - fromPos).Magnitude
	local travelTime = math.clamp(distance / 90, 0.08, 0.35)
	local travel = TweenService:Create(bubble, TweenInfo.new(travelTime, Enum.EasingStyle.Quad), {
		CFrame = CFrame.new(toPos),
	})
	travel:Play()
	travel.Completed:Connect(function()
		-- "Лопается": резко раздувается и исчезает
		if pulseConn then pulseConn:Disconnect() end
		local pop = TweenService:Create(bubble, TweenInfo.new(0.18, Enum.EasingStyle.Quad), {
			Size = Vector3.new(3.2, 3.2, 3.2),
			Transparency = 1,
		})
		pop:Play()
		Debris:AddItem(bubble, 0.25)
	end)
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
		target = findAncestorWithAttribute(result.Instance, "Catchable")
			or findAncestorWithAttribute(result.Instance, "Trash")
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

local function fireCrusherDrill(tool)
	if drillOverheated then return end
	local result = raycastFromMouse()
	if not result then return end

	local target = findAncestorWithAttribute(result.Instance, "ResourceId")
	if target then
		FireDrillRemote:FireServer(target)
	end
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

	tool.Activated:Connect(function()
		if tool.Name == "BubbleCannon" then
			fireBubbleCannon(tool)
		else
			fireCrusherDrill(tool)
		end
	end)
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
