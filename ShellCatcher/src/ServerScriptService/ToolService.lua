--!strict
--[[
	ToolService.lua  (ServerScriptService, ModuleScript)

	Отвечает за ВЫДАЧУ двух инструментов игроку (по дизайну — оба берутся у NPC
	"Quartermaster", см. NPCService):
	  • BubbleCannon  — "Пушка пузырей": стреляет пузырями, ловит медуз.
	  • CrusherDrill  — дробит ресурсные блоки.

	Раньше игрок не получал НИ ОДНОГО Tool: ToolController просто переключал
	переменную по клавишам 1/2. Теперь это настоящие Tool-объекты с Handle,
	которые кладутся в Backpack и StarterGear (StarterGear переживает респаун).

	Модели инструментов строятся кодом (простые Part), их легко заменить на свой арт —
	главное сохранить: имя Tool ("BubbleCannon"/"CrusherDrill"), Handle и Attachment
	"Muzzle" на стволе (от него ToolController рисует пузыри).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DataService = require(script.Parent:WaitForChild("DataService"))

local ToolService = {}

-- Папка-хранилище шаблонов инструментов (создаётся на сервере, клиенту не нужна).
local templatesFolder = Instance.new("Folder")
templatesFolder.Name = "ToolTemplates"
templatesFolder.Parent = ReplicatedStorage

local function makeHandle(toolName: string, size: Vector3, color: Color3): Part
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = size
	handle.Color = color
	handle.Material = Enum.Material.SmoothPlastic
	handle.CanCollide = false
	handle.Massless = true

	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	muzzle.Position = Vector3.new(0, 0, -size.Z / 2)
	muzzle.Parent = handle

	return handle
end

-- Декоративная (приваренная) деталь поверх Handle
local function weldDetail(handle: Part, name: string, size: Vector3, offset: CFrame, color: Color3, neon: boolean?): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Color = color
	part.Material = neon and Enum.Material.Neon or Enum.Material.SmoothPlastic
	part.CanCollide = false
	part.Massless = true
	part.CFrame = handle.CFrame * offset
	part.Parent = handle.Parent

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = handle
	weld.Part1 = part
	weld.Parent = handle
	return part
end

local function buildBubbleCannon(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "BubbleCannon"
	tool.ToolTip = "Пушка пузырей — лови медуз пузырями (ЛКМ)"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = makeHandle("BubbleCannon", Vector3.new(1, 1.2, 3.2), Color3.fromRGB(60, 110, 160))
	handle.Parent = tool
	-- Неоновое синее "сопло" на конце ствола
	weldDetail(handle, "Emitter", Vector3.new(1.2, 1.2, 0.6), CFrame.new(0, 0, -1.7), Color3.fromRGB(90, 200, 255), true)
	weldDetail(handle, "Tank", Vector3.new(0.9, 0.9, 1.2), CFrame.new(0, 0.6, 0.9), Color3.fromRGB(120, 220, 255), true)
	return tool
end

local function buildCrusherDrill(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "CrusherDrill"
	tool.ToolTip = "Дробящий бур — разбивай ресурсные блоки (ЛКМ)"
	tool.RequiresHandle = true
	tool.CanBeDropped = false

	local handle = makeHandle("CrusherDrill", Vector3.new(1, 1.3, 2.6), Color3.fromRGB(90, 80, 70))
	handle.Parent = tool
	-- Конусообразный бур на конце
	local bit = weldDetail(handle, "DrillBit", Vector3.new(0.9, 0.9, 1.4), CFrame.new(0, 0, -1.8), Color3.fromRGB(230, 200, 80))
	bit.Shape = Enum.PartType.Cylinder
	bit.Orientation = Vector3.new(0, 90, 0)
	return tool
end

-- Строим оба шаблона один раз при загрузке модуля.
local bubbleTemplate = buildBubbleCannon()
bubbleTemplate.Parent = templatesFolder
local drillTemplate = buildCrusherDrill()
drillTemplate.Parent = templatesFolder

ToolService.ToolNames = { "BubbleCannon", "CrusherDrill" }

-- Есть ли уже такой Tool у игрока (в Backpack или в руках)?
local function playerHasTool(player: Player, toolName: string): boolean
	local backpack = player:FindFirstChildOfClass("Backpack")
	if backpack and backpack:FindFirstChild(toolName) then
		return true
	end
	local character = player.Character
	if character and character:FindFirstChild(toolName) then
		return true
	end
	return false
end

-- Кладём шаблон в StarterGear (переживает респаун) и сразу в Backpack текущей сессии.
local function ensureTool(player: Player, template: Tool)
	local starterGear = player:FindFirstChildOfClass("StarterGear")
	if starterGear and not starterGear:FindFirstChild(template.Name) then
		template:Clone().Parent = starterGear
	end
	if not playerHasTool(player, template.Name) then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			template:Clone().Parent = backpack
		end
	end
end

-- Главная точка входа: выдаёт игроку ОБЕ пушки. Вызывается NPCService при разговоре
-- с Quartermaster, а также при заходе, если профиль помечен как уже получивший инструменты.
function ToolService.GrantTools(player: Player): boolean
	ensureTool(player, bubbleTemplate)
	ensureTool(player, drillTemplate)

	local profile = DataService.Get(player)
	if profile then
		profile.ToolsGranted = true
	end
	return true
end

-- При заходе игрока, если он уже брал пушки в прошлой сессии — вернуть их сразу.
function ToolService.RestoreToolsIfOwned(player: Player)
	local profile = DataService.Get(player)
	if profile and profile.ToolsGranted then
		ToolService.GrantTools(player)
	end
end

-- StarterGear копируется в Backpack автоматически при респауне, поэтому отдельный
-- хук на CharacterAdded не обязателен. Но на случай "горячего" старта в Studio,
-- когда персонаж уже существует, доливаем инструменты вручную.
Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(function()
		task.wait(0.4)
		ToolService.RestoreToolsIfOwned(player)
	end)
end)

return ToolService
