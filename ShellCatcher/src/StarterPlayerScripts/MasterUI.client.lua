--[[
	MasterUI.client.lua  (StarterPlayerScripts)

	ОДИН скрипт, который строит ВЕСЬ UI игры схематично (простые прямоугольники,
	подписанные текстом, без картинок). Каждый элемент — это Frame/ImageLabel
	с понятным именем в иерархии, чтобы ты потом легко нашёл его в Explorer
	и добавил своё изображение в свойство Image / повесил иконку рядом с текстом.

	Что внутри:
	  1. HUD (полоска кислорода + валюта) — всегда на экране
	  2. Кнопка-бургер открытия Inventory / Upgrades / Shop
	  3. Inventory — список пойманного + кнопка "Продать всё"
	  4. Upgrades — РАДИАЛЬНОЕ ДЕРЕВО НАВЫКОВ: узлы-ромбы лучами от центра,
	     с зависимостями (нельзя купить узел без купленного родителя),
	     перетаскиваемый холст (ScrollingFrame), панель деталей выбранного узла
	  5. Shop — геймпассы и dev-продукты
	  6. Всплывающие уведомления (поймал рыбу, перегрев, удушение, ребирт)

	ВАЖНО: этот скрипт ПОЛНОСТЬЮ заменяет OxygenUIController.client.lua и
	ShopUIController.client.lua — те два файла можно удалить, чтобы не было
	задвоения UI. ToolController.client.lua остаётся отдельно (он не про UI,
	а про ввод/прицеливание).

	КАК ДОБАВИТЬ СВОИ ИЗОБРАЖЕНИЯ ПОТОМ:
	- Найди нужный элемент в Explorer (все имена на английском, по смыслу)
	- Если это Frame — можешь заменить на ImageLabel или добавить ImageLabel ребёнком
	- Если это TextButton — можно задать .Image-подобный вид, добавив ImageLabel
	  поверх с .ZIndex выше текста, либо просто покрасить .BackgroundColor3
	- Все цвета/размеры заданы переменными в начале файла (THEME) — меняй там,
	  чтобы перекрасить всю игру одним местом.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage:WaitForChild("GameConfig"))
local MonetizationConfig = require(ReplicatedStorage:WaitForChild("MonetizationConfig"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")

-- ============================================================
-- THEME — меняй тут, чтобы перекрасить весь UI одним местом
-- ============================================================
local THEME = {
	Background = Color3.fromRGB(20, 28, 38),
	Panel = Color3.fromRGB(30, 42, 54),
	PanelLight = Color3.fromRGB(40, 55, 70),
	Accent = Color3.fromRGB(80, 200, 255),
	AccentGreen = Color3.fromRGB(90, 200, 120),
	AccentRed = Color3.fromRGB(230, 90, 90),
	AccentGold = Color3.fromRGB(250, 200, 70),
	TextPrimary = Color3.fromRGB(255, 255, 255),
	TextSecondary = Color3.fromRGB(190, 200, 210),
	Font = Enum.Font.GothamBold,
	FontRegular = Enum.Font.Gotham,
	CornerRadius = UDim.new(0, 10),
}

-- ============================================================
-- ROOT ScreenGui
-- ============================================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MasterUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.Parent = playerGui

-- ============================================================
-- Хелперы создания элементов (схематичные, без картинок)
-- ============================================================

local function addCorner(instance, radius)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = radius or THEME.CornerRadius
	corner.Parent = instance
	return corner
end

local function addPadding(instance, amount)
	local padding = Instance.new("UIPadding")
	amount = amount or 8
	padding.PaddingTop = UDim.new(0, amount)
	padding.PaddingBottom = UDim.new(0, amount)
	padding.PaddingLeft = UDim.new(0, amount)
	padding.PaddingRight = UDim.new(0, amount)
	padding.Parent = instance
	return padding
end

local function makeFrame(name, parent, size, position, color)
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position or UDim2.fromOffset(0, 0)
	frame.BackgroundColor3 = color or THEME.Panel
	frame.BorderSizePixel = 0
	frame.Parent = parent
	addCorner(frame)
	return frame
end

local function makeLabel(name, parent, size, position, text, textSize, color, font, alignment)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = size
	label.Position = position or UDim2.fromOffset(0, 0)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextSize = textSize or 16
	label.TextColor3 = color or THEME.TextPrimary
	label.Font = font or THEME.FontRegular
	label.TextXAlignment = alignment or Enum.TextXAlignment.Left
	label.TextWrapped = true
	label.Parent = parent
	return label
end

local function makeButton(name, parent, size, position, text, color)
	local button = Instance.new("TextButton")
	button.Name = name
	button.Size = size
	button.Position = position or UDim2.fromOffset(0, 0)
	button.BackgroundColor3 = color or THEME.PanelLight
	button.Text = text
	button.TextColor3 = THEME.TextPrimary
	button.Font = THEME.Font
	button.TextSize = 15
	button.AutoButtonColor = true
	button.Parent = parent
	addCorner(button)
	return button
end

-- Маленький цветной квадрат-плейсхолдер вместо иконки — замени потом на ImageLabel.Image
local function makeIconPlaceholder(name, parent, size, position, color)
	local icon = Instance.new("Frame")
	icon.Name = name .. "_IconPlaceholder"
	icon.Size = size
	icon.Position = position
	icon.BackgroundColor3 = color or THEME.Accent
	icon.BorderSizePixel = 0
	icon.Parent = parent
	addCorner(icon, UDim.new(0, 6))
	return icon
end

-- ============================================================
-- 1. HUD — кислород + валюта, всегда видим
-- ============================================================
local hud = Instance.new("Frame")
hud.Name = "HUD"
hud.Size = UDim2.fromScale(1, 1)
hud.BackgroundTransparency = 1
hud.Parent = screenGui

-- Полоска кислорода
local oxygenBarBg = makeFrame("OxygenBarBackground", hud, UDim2.fromOffset(280, 28), UDim2.new(0.5, -140, 0, 16), THEME.Background)
local oxygenBarFill = Instance.new("Frame")
oxygenBarFill.Name = "OxygenBarFill"
oxygenBarFill.Size = UDim2.fromScale(1, 1)
oxygenBarFill.BackgroundColor3 = THEME.Accent
oxygenBarFill.BorderSizePixel = 0
oxygenBarFill.Parent = oxygenBarBg
addCorner(oxygenBarFill)

local oxygenLabel = makeLabel("OxygenLabel", oxygenBarBg, UDim2.fromScale(1, 1), UDim2.fromOffset(0, 0), "Oxygen: 60s", 14, THEME.TextPrimary, THEME.Font, Enum.TextXAlignment.Center)

-- Валюта (Shells)
local currencyFrame = makeFrame("CurrencyDisplay", hud, UDim2.fromOffset(160, 40), UDim2.new(0, 16, 0, 16), THEME.Background)
makeIconPlaceholder("Currency", currencyFrame, UDim2.fromOffset(26, 26), UDim2.fromOffset(7, 7), THEME.AccentGold)
local currencyLabel = makeLabel("CurrencyLabel", currencyFrame, UDim2.new(1, -42, 1, 0), UDim2.fromOffset(40, 0), "0 Shells", 16, THEME.TextPrimary, THEME.Font, Enum.TextXAlignment.Left)

-- ============================================================
-- 2. Нижняя панель кнопок (Inventory / Upgrades / Shop)
-- ============================================================
local bottomBar = Instance.new("Frame")
bottomBar.Name = "BottomBar"
bottomBar.Size = UDim2.fromOffset(420, 60)
bottomBar.Position = UDim2.new(0.5, -210, 1, -70)
bottomBar.BackgroundTransparency = 1
bottomBar.Parent = hud

local bottomBarLayout = Instance.new("UIListLayout")
bottomBarLayout.FillDirection = Enum.FillDirection.Horizontal
bottomBarLayout.Padding = UDim.new(0, 10)
bottomBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bottomBarLayout.Parent = bottomBar

local inventoryToggleButton = makeButton("InventoryButton", bottomBar, UDim2.fromOffset(130, 60), nil, "🎣 Inventory", THEME.Panel)
local upgradesToggleButton = makeButton("UpgradesButton", bottomBar, UDim2.fromOffset(130, 60), nil, "⚙ Upgrades", THEME.Panel)
local shopToggleButton = makeButton("ShopButton", bottomBar, UDim2.fromOffset(130, 60), nil, "🛒 Shop", THEME.Panel)

-- ============================================================
-- Универсальная "панель окна" — общий каркас для Inventory/Upgrades/Shop
-- ============================================================
-- Локальное проигрывание звука (используется и для UI-кликов, и для PlayLocalSound с сервера).
-- SoundId сейчас всегда заглушка — реальные ID лежат в GameConfig.SoundIds, замени там.
local function playSound(soundKey)
	local soundId = GameConfig.SoundIds[soundKey]
	if not soundId or soundId == "" then return end -- заглушка ещё не заменена, тихо пропускаем

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = GameConfig.SoundVolumes[soundKey] or 0.5
	sound.Parent = screenGui
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 5)
end

local function makeWindowPanel(name, title, sizeOffset)
	local panel = Instance.new("Frame")
	panel.Name = name
	panel.Size = sizeOffset or UDim2.fromOffset(480, 560)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.BackgroundColor3 = THEME.Background
	panel.BorderSizePixel = 0
	panel.Visible = false
	panel.Parent = screenGui
	addCorner(panel, UDim.new(0, 14))

	local titleBar = makeFrame("TitleBar", panel, UDim2.new(1, 0, 0, 50), UDim2.fromOffset(0, 0), THEME.Panel)
	addCorner(titleBar, UDim.new(0, 14))
	makeLabel("TitleLabel", titleBar, UDim2.new(1, -50, 1, 0), UDim2.fromOffset(16, 0), title, 20, THEME.TextPrimary, THEME.Font)

	local closeButton = makeButton("CloseButton", titleBar, UDim2.fromOffset(36, 36), UDim2.new(1, -44, 0.5, -18), "X", THEME.AccentRed)
	closeButton.MouseButton1Click:Connect(function()
		panel.Visible = false
		playSound("UIClose")
	end)

	local contentArea = Instance.new("ScrollingFrame")
	contentArea.Name = "Content"
	contentArea.Size = UDim2.new(1, -20, 1, -64)
	contentArea.Position = UDim2.fromOffset(10, 58)
	contentArea.BackgroundTransparency = 1
	contentArea.BorderSizePixel = 0
	contentArea.ScrollBarThickness = 6
	contentArea.CanvasSize = UDim2.fromOffset(0, 0)
	contentArea.AutomaticCanvasSize = Enum.AutomaticSize.Y
	contentArea.Parent = panel

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 8)
	listLayout.Parent = contentArea

	return panel, contentArea
end

local function toggleWindow(panel, others)
	local willShow = not panel.Visible
	for _, other in ipairs(others) do
		other.Visible = false
	end
	panel.Visible = willShow
	playSound(willShow and "UIClick" or "UIClose")
end

-- ============================================================
-- 3. INVENTORY WINDOW
-- ============================================================
local inventoryPanel, inventoryContent = makeWindowPanel("InventoryWindow", "Your Inventory")

local inventorySummaryLabel = makeLabel(
	"InventorySummary", inventoryContent, UDim2.new(1, 0, 0, 30), nil,
	"0 / 30 slots used", 15, THEME.TextSecondary, THEME.FontRegular
)

local sellAllButton = makeButton("SellAllButton", inventoryContent, UDim2.new(1, 0, 0, 46), nil, "Sell All Catches", THEME.AccentGreen)

local inventoryListFrame = Instance.new("Frame")
inventoryListFrame.Name = "ItemList"
inventoryListFrame.Size = UDim2.new(1, 0, 0, 0)
inventoryListFrame.AutomaticSize = Enum.AutomaticSize.Y
inventoryListFrame.BackgroundTransparency = 1
inventoryListFrame.Parent = inventoryContent

local inventoryListLayout = Instance.new("UIListLayout")
inventoryListLayout.Padding = UDim.new(0, 6)
inventoryListLayout.Parent = inventoryListFrame

local function refreshInventoryDisplay(items, maxSlots)
	for _, child in ipairs(inventoryListFrame:GetChildren()) do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	inventorySummaryLabel.Text = string.format("%d / %d slots used", #items, maxSlots)

	for index, item in ipairs(items) do
		local rarityColor = THEME.TextSecondary
		for _, r in ipairs(GameConfig.Rarities) do
			if r.Id == item.RarityId then
				rarityColor = r.Color
				break
			end
		end

		local row = makeFrame("Item_" .. index, inventoryListFrame, UDim2.new(1, 0, 0, 44), nil, THEME.Panel)
		makeIconPlaceholder("Item", row, UDim2.fromOffset(30, 30), UDim2.fromOffset(7, 7), rarityColor)
		makeLabel(
			"ItemName", row, UDim2.new(1, -150, 1, 0), UDim2.fromOffset(46, 0),
			item.CreatureId .. " — " .. item.RarityId, 14, THEME.TextPrimary, THEME.FontRegular
		)
		makeLabel(
			"ItemValue", row, UDim2.fromOffset(90, row.Size.Y.Offset), UDim2.new(1, -98, 0, 0),
			string.format("%d Shells", math.floor(item.Value)), 14, THEME.AccentGold, THEME.Font, Enum.TextXAlignment.Right
		)
	end
end

-- ============================================================
-- 4. UPGRADES WINDOW — РАДИАЛЬНОЕ ДЕРЕВО НАВЫКОВ
-- Узлы-ромбы расходятся лучами от центра. Линия между узлом и его родителем
-- подсвечивается цветом ветки. Серый/затемнённый узел = родитель ещё не куплен.
-- Скролл-зона больше окна, поэтому дерево можно "перетаскивать" (drag to pan).
-- ============================================================
local upgradesPanel, upgradesViewport = makeWindowPanel("UpgradesWindow", "Skill Tree", UDim2.fromOffset(620, 640))

-- Canvas дерева — большой холст внутри ScrollingFrame, узлы размещаются абсолютными
-- координатами относительно центра холста.
local treeCanvas = Instance.new("Frame")
treeCanvas.Name = "TreeCanvas"
treeCanvas.Size = UDim2.fromOffset(1400, 1400)
treeCanvas.BackgroundTransparency = 1
treeCanvas.Parent = upgradesViewport

upgradesViewport.CanvasSize = UDim2.fromOffset(1400, 1400)
upgradesViewport.AutomaticCanvasSize = Enum.AutomaticSize.None
upgradesViewport.ScrollingDirection = Enum.ScrollingDirection.XY
upgradesViewport.CanvasPosition = Vector2.new(700 - 260, 700 - 280) -- центрируем на старте

local TREE_CENTER = Vector2.new(700, 700)
local RADIUS_STEP = 130 -- пикселей между слоями дерева

-- Переводит (Angle, Radius) узла в пиксельную позицию на холсте
local function polarToCanvasPosition(angleDegrees, radiusLayer)
	local angleRad = math.rad(angleDegrees)
	local distance = radiusLayer * RADIUS_STEP
	local x = TREE_CENTER.X + math.cos(angleRad) * distance
	local y = TREE_CENTER.Y - math.sin(angleRad) * distance -- минус: Y растёт вниз в UI
	return Vector2.new(x, y)
end

-- Рисует линию между двумя точками холста (тонкий Frame, повёрнутый под нужным углом)
local function drawTreeLine(parent, fromPos, toPos, color, name)
	local delta = toPos - fromPos
	local length = delta.Magnitude
	local angle = math.atan2(delta.Y, delta.X)

	local line = Instance.new("Frame")
	line.Name = name or "TreeLine"
	line.AnchorPoint = Vector2.new(0, 0.5)
	line.Position = UDim2.fromOffset(fromPos.X, fromPos.Y)
	line.Size = UDim2.fromOffset(length, 4)
	line.Rotation = math.deg(angle)
	line.BackgroundColor3 = color
	line.BorderSizePixel = 0
	line.ZIndex = 1
	line.Parent = parent
	return line
end

-- Узел дерева: ромб (Frame повёрнутый на 45°) с иконкой-плейсхолдером и подписью под ним
local function drawTreeNode(parent, nodeKey, nodeInfo, canvasPos, branchColor)
	local nodeSize = nodeInfo.IsRoot and 64 or 52

	local diamond = Instance.new("Frame")
	diamond.Name = "Node_" .. nodeKey
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromOffset(canvasPos.X, canvasPos.Y)
	diamond.Size = UDim2.fromOffset(nodeSize, nodeSize)
	diamond.Rotation = 45
	diamond.BorderSizePixel = 0
	diamond.ZIndex = 2
	diamond.Parent = parent

	local isLocked = nodeInfo.IsUnlocked == false
	local isMaxed = nodeInfo.IsMaxed == true
	local hasLevels = (nodeInfo.CurrentLevel or 0) > 0

	if nodeInfo.IsRoot then
		diamond.BackgroundColor3 = THEME.AccentGold
	elseif isLocked then
		diamond.BackgroundColor3 = Color3.fromRGB(45, 50, 58) -- затемнённый, недоступный
	elseif isMaxed then
		diamond.BackgroundColor3 = branchColor
	elseif hasLevels then
		diamond.BackgroundColor3 = branchColor:Lerp(Color3.new(0, 0, 0), 0.35)
	else
		diamond.BackgroundColor3 = THEME.PanelLight
	end

	local border = Instance.new("UIStroke")
	border.Color = isLocked and Color3.fromRGB(70, 75, 85) or branchColor
	border.Thickness = 2
	border.Parent = diamond

	-- Иконка-плейсхолдер внутри ромба (контр-поворот -45° чтобы не выглядела криво)
	local iconHolder = Instance.new("Frame")
	iconHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	iconHolder.Position = UDim2.fromScale(0.5, 0.5)
	iconHolder.Size = UDim2.fromOffset(nodeSize * 0.55, nodeSize * 0.55)
	iconHolder.Rotation = -45
	iconHolder.BackgroundTransparency = 1
	iconHolder.ZIndex = 3
	iconHolder.Parent = diamond

	local iconLabel = Instance.new("TextLabel")
	iconLabel.Size = UDim2.fromScale(1, 1)
	iconLabel.BackgroundTransparency = 1
	iconLabel.Text = nodeInfo.IsRoot and "★" or tostring(nodeInfo.CurrentLevel or 0)
	iconLabel.TextColor3 = THEME.TextPrimary
	iconLabel.Font = THEME.Font
	iconLabel.TextScaled = true
	iconLabel.Parent = iconHolder

	-- Подпись с именем узла под ромбом (не повёрнута)
	local nameLabel = Instance.new("TextLabel")
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.fromOffset(canvasPos.X, canvasPos.Y + nodeSize * 0.55)
	nameLabel.Size = UDim2.fromOffset(120, 32)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = nodeInfo.IsRoot and nodeInfo.DisplayName
		or string.format("%s\n%d/%d", nodeInfo.DisplayName, nodeInfo.CurrentLevel, nodeInfo.MaxLevel)
	nameLabel.TextColor3 = isLocked and THEME.TextSecondary or THEME.TextPrimary
	nameLabel.Font = THEME.FontRegular
	nameLabel.TextSize = 11
	nameLabel.TextWrapped = true
	nameLabel.ZIndex = 2
	nameLabel.Parent = parent

	-- Кликабельная зона поверх ромба (квадрат без поворота — проще ловить клик)
	local clickArea = Instance.new("TextButton")
	clickArea.AnchorPoint = Vector2.new(0.5, 0.5)
	clickArea.Position = UDim2.fromOffset(canvasPos.X, canvasPos.Y)
	clickArea.Size = UDim2.fromOffset(nodeSize, nodeSize)
	clickArea.BackgroundTransparency = 1
	clickArea.Text = ""
	clickArea.ZIndex = 4
	clickArea.Parent = parent

	return clickArea, diamond
end

local selectedNodeKey = nil
local latestUpgradeSnapshot = nil

-- Панель деталей выбранного узла — внизу окна дерева, показывает имя/уровень/кнопку покупки
local detailsPanel = makeFrame("NodeDetails", upgradesPanel, UDim2.new(1, -20, 0, 90), UDim2.new(0, 10, 1, -98), THEME.Panel)
detailsPanel.ZIndex = 5

local detailsTitle = makeLabel("Title", detailsPanel, UDim2.new(1, -130, 0, 24), UDim2.fromOffset(12, 8), "Select a node", 16, THEME.TextPrimary, THEME.Font)
detailsTitle.ZIndex = 5
local detailsSubtitle = makeLabel("Subtitle", detailsPanel, UDim2.new(1, -130, 0, 40), UDim2.fromOffset(12, 32), "", 13, THEME.TextSecondary, THEME.FontRegular)
detailsSubtitle.ZIndex = 5
local detailsBuyButton = makeButton("BuyButton", detailsPanel, UDim2.fromOffset(110, 60), UDim2.new(1, -120, 0.5, -30), "—", THEME.AccentGreen)
detailsBuyButton.ZIndex = 5

local function updateDetailsPanel(nodeKey)
	selectedNodeKey = nodeKey
	if not nodeKey or not latestUpgradeSnapshot then
		detailsTitle.Text = "Select a node"
		detailsSubtitle.Text = ""
		detailsBuyButton.Text = "—"
		detailsBuyButton.AutoButtonColor = false
		return
	end

	local info = latestUpgradeSnapshot[nodeKey]
	if not info then return end

	detailsTitle.Text = info.DisplayName
	if info.IsUnlocked == false then
		detailsSubtitle.Text = "Locked — purchase the connected node first."
		detailsBuyButton.Text = "LOCKED"
		detailsBuyButton.BackgroundColor3 = THEME.PanelLight
		detailsBuyButton.AutoButtonColor = false
	elseif info.IsMaxed then
		detailsSubtitle.Text = string.format("Level %d / %d  •  Current: %.2f", info.CurrentLevel, info.MaxLevel, info.CurrentValue)
		detailsBuyButton.Text = "MAX"
		detailsBuyButton.BackgroundColor3 = THEME.PanelLight
		detailsBuyButton.AutoButtonColor = false
	else
		detailsSubtitle.Text = string.format("Level %d / %d  •  Current: %.2f", info.CurrentLevel, info.MaxLevel, info.CurrentValue)
		detailsBuyButton.Text = string.format("%d 🐚", info.NextCost or 0)
		detailsBuyButton.BackgroundColor3 = THEME.AccentGreen
		detailsBuyButton.AutoButtonColor = true
	end
end

detailsBuyButton.MouseButton1Click:Connect(function()
	if not selectedNodeKey then return end
	local info = latestUpgradeSnapshot and latestUpgradeSnapshot[selectedNodeKey]
	if not info or info.IsUnlocked == false or info.IsMaxed then return end
	Remotes.BuyUpgrade:FireServer(selectedNodeKey)
end)

-- Полная перестройка дерева (вызывается при первом снапшоте и при каждом обновлении с сервера)
local function renderSkillTree()
	for _, child in ipairs(treeCanvas:GetChildren()) do
		child:Destroy()
	end

	if not latestUpgradeSnapshot then return end

	-- Сначала линии (чтобы узлы рисовались поверх них), потом узлы
	for nodeKey, info in pairs(latestUpgradeSnapshot) do
		if info.ParentKey then
			local parentInfo = latestUpgradeSnapshot[info.ParentKey]
			if parentInfo then
				local fromPos = parentInfo.IsRoot and TREE_CENTER or polarToCanvasPosition(parentInfo.Angle, parentInfo.Radius)
				local toPos = polarToCanvasPosition(info.Angle, info.Radius)
				local lineColor = info.IsUnlocked == false
					and Color3.fromRGB(55, 60, 68)
					or (GameConfig.BranchColors[info.Branch] or THEME.Accent)
				drawTreeLine(treeCanvas, fromPos, toPos, lineColor, "Line_" .. nodeKey)
			end
		end
	end

	-- Центральный узел "Start"
	local rootClickArea = drawTreeNode(treeCanvas, "Start", { IsRoot = true, DisplayName = "Diver's Core" }, TREE_CENTER, THEME.AccentGold)
	rootClickArea.MouseButton1Click:Connect(function()
		updateDetailsPanel(nil)
	end)

	for nodeKey, info in pairs(latestUpgradeSnapshot) do
		local canvasPos = polarToCanvasPosition(info.Angle, info.Radius)
		local branchColor = GameConfig.BranchColors[info.Branch] or THEME.Accent
		local clickArea = drawTreeNode(treeCanvas, nodeKey, info, canvasPos, branchColor)

		clickArea.MouseButton1Click:Connect(function()
			updateDetailsPanel(nodeKey)
		end)
	end
end

-- ============================================================
-- 5. SHOP WINDOW (Game Passes + Developer Products)
-- ============================================================
local shopPanel, shopContent = makeWindowPanel("ShopWindow", "Shop", UDim2.fromOffset(460, 600))

local shopSectionGamepasses = makeLabel(
	"GamepassesHeader", shopContent, UDim2.new(1, 0, 0, 26), nil,
	"— Permanent Upgrades (Game Passes) —", 15, THEME.AccentGold, THEME.Font, Enum.TextXAlignment.Center
)

local function makeShopEntry(parent, name, priceText, description, buttonColor, onClick)
	local entry = makeFrame(name:gsub("%s+", "") .. "_Entry", parent, UDim2.new(1, 0, 0, 78), nil, THEME.Panel)

	makeIconPlaceholder("Item", entry, UDim2.fromOffset(46, 46), UDim2.fromOffset(8, 8), THEME.Accent)

	makeLabel("Name", entry, UDim2.new(1, -180, 0, 22), UDim2.fromOffset(62, 6), name, 15, THEME.TextPrimary, THEME.Font)
	makeLabel("Description", entry, UDim2.new(1, -180, 0, 40), UDim2.fromOffset(62, 28), description, 12, THEME.TextSecondary, THEME.FontRegular)

	local buyButton = makeButton("BuyButton", entry, UDim2.fromOffset(100, 40), UDim2.new(1, -108, 0.5, -20), priceText, buttonColor)
	buyButton.MouseButton1Click:Connect(onClick)

	return entry
end

for key, passInfo in pairs(MonetizationConfig.GamePasses) do
	makeShopEntry(
		shopContent, passInfo.Name, tostring(passInfo.Price) .. " R$", passInfo.Description, THEME.AccentGreen,
		function()
			Remotes.PromptGamePassPurchase:FireServer(key)
		end
	)
end

makeLabel(
	"ProductsHeader", shopContent, UDim2.new(1, 0, 0, 26), nil,
	"— Consumables (Developer Products) —", 15, THEME.AccentGold, THEME.Font, Enum.TextXAlignment.Center
)

for key, productInfo in pairs(MonetizationConfig.DeveloperProducts) do
	makeShopEntry(
		shopContent, productInfo.Name, tostring(productInfo.Price) .. " R$", productInfo.Description or "", THEME.Accent,
		function()
			Remotes.PromptProductPurchase:FireServer(key)
		end
	)
end

-- ============================================================
-- 5b. TRAVEL WINDOW — телепортация по зонам (открывается у NPC Ferry Captain)
-- ============================================================
local travelPanel, travelContent = makeWindowPanel("TravelWindow", "Ferry — Travel", UDim2.fromOffset(460, 560))

local travelHint = makeLabel(
	"TravelHint", travelContent, UDim2.new(1, 0, 0, 36), nil,
	"Choose a fishing zone to dive into. Locked zones can be unlocked with Shells.",
	13, THEME.TextSecondary, THEME.FontRegular, Enum.TextXAlignment.Center
)
travelHint.TextWrapped = true

local returnIslandButton = makeButton("ReturnIsland", travelContent, UDim2.new(1, 0, 0, 44), nil, "🏝 Return to Island", THEME.PanelLight)
returnIslandButton.MouseButton1Click:Connect(function()
	-- Возврат на остров = вход в "пустую зону". У нас нет отдельного remote возврата,
	-- но сервер сам возвращает на остров при респауне; здесь просто закрываем окно
	-- и подсказываем игроку. Телепорт-на-остров реализуем через EnterZone(nil-safe):
	Remotes.EnterZone:FireServer("__island__") -- сервер проигнорирует неизвестную зону
	travelPanel.Visible = false
end)

local zoneRows = {} -- [zoneId] = { button = ..., locked = bool }
local unlockedZonesSet = { reef = true }

local function refreshTravelWindow()
	for zoneId, row in pairs(zoneRows) do
		local unlocked = unlockedZonesSet[zoneId] == true
		if unlocked then
			row.button.Text = "Dive In"
			row.button.BackgroundColor3 = THEME.AccentGreen
		else
			row.button.Text = string.format("Unlock (%d 🐚)", row.cost)
			row.button.BackgroundColor3 = THEME.AccentGold
		end
	end
end

for _, zoneConfig in ipairs(GameConfig.Zones) do
	local row = makeFrame("Zone_" .. zoneConfig.Id, travelContent, UDim2.new(1, 0, 0, 70), nil, THEME.Panel)
	makeIconPlaceholder("Zone", row, UDim2.fromOffset(46, 46), UDim2.fromOffset(8, 12), THEME.Accent)
	makeLabel("Name", row, UDim2.new(1, -200, 0, 24), UDim2.fromOffset(62, 8), zoneConfig.Name, 15, THEME.TextPrimary, THEME.Font)
	makeLabel(
		"Info", row, UDim2.new(1, -200, 0, 36), UDim2.fromOffset(62, 30),
		string.format("Value x%.1f  •  O₂ x%.2f", zoneConfig.CatchValueMultiplier, zoneConfig.OxygenMultiplier),
		12, THEME.TextSecondary, THEME.FontRegular
	)

	local actionButton = makeButton("Action", row, UDim2.fromOffset(120, 46), UDim2.new(1, -130, 0.5, -23), "—", THEME.PanelLight)
	zoneRows[zoneConfig.Id] = { button = actionButton, cost = zoneConfig.UnlockCost }

	actionButton.MouseButton1Click:Connect(function()
		if unlockedZonesSet[zoneConfig.Id] then
			Remotes.EnterZone:FireServer(zoneConfig.Id)
			travelPanel.Visible = false
			playSound("UIClick")
		else
			Remotes.UnlockZone:FireServer(zoneConfig.Id)
		end
	end)
end

-- ============================================================
-- 5c. REBIRTH WINDOW (открывается у NPC Tide Priestess)
-- ============================================================
local rebirthPanel, rebirthContent = makeWindowPanel("RebirthWindow", "Rebirth Altar", UDim2.fromOffset(440, 440))

local rebirthLevelLabel = makeLabel("Level", rebirthContent, UDim2.new(1, 0, 0, 40), nil, "Rebirth Level: 0", 20, THEME.AccentGold, THEME.Font, Enum.TextXAlignment.Center)
local rebirthBonusLabel = makeLabel("Bonus", rebirthContent, UDim2.new(1, 0, 0, 28), nil, "", 14, THEME.AccentGreen, THEME.FontRegular, Enum.TextXAlignment.Center)
local rebirthReqLabel = makeLabel("Requirement", rebirthContent, UDim2.new(1, 0, 0, 60), nil, "", 14, THEME.TextSecondary, THEME.FontRegular, Enum.TextXAlignment.Center)
rebirthReqLabel.TextWrapped = true
local rebirthWarnLabel = makeLabel(
	"Warn", rebirthContent, UDim2.new(1, 0, 0, 56), nil,
	"⚠ Rebirth resets your zones & inventory, but permanently boosts catch value.",
	12, THEME.AccentRed, THEME.FontRegular, Enum.TextXAlignment.Center
)
rebirthWarnLabel.TextWrapped = true
local rebirthButton = makeButton("RebirthButton", rebirthContent, UDim2.new(1, 0, 0, 56), nil, "Rebirth", THEME.AccentGold)
rebirthButton.MouseButton1Click:Connect(function()
	Remotes.RequestRebirth:FireServer()
end)

local latestShells = 0
local latestRebirthLevel = 0
local latestRebirthRequirement = GameConfig.Rebirth.BaseCurrencyRequirement

local function updateRebirthInfo(level, requirement)
	rebirthLevelLabel.Text = string.format("Rebirth Level: %d", level)
	rebirthBonusLabel.Text = string.format("Current bonus: +%d%% catch value", math.floor(level * GameConfig.Rebirth.ValueBonusPerLevel * 100))
	if level >= GameConfig.Rebirth.MaxLevel then
		rebirthReqLabel.Text = "Maximum rebirth level reached!"
		rebirthButton.Text = "MAX"
		rebirthButton.BackgroundColor3 = THEME.PanelLight
		rebirthButton.AutoButtonColor = false
	else
		rebirthReqLabel.Text = string.format("Need %d Shells to rebirth (next bonus: +%d%%)",
			requirement or 0, math.floor((level + 1) * GameConfig.Rebirth.ValueBonusPerLevel * 100))
		local canAfford = latestShells >= (requirement or math.huge)
		rebirthButton.Text = canAfford and "Rebirth Now" or "Not enough Shells"
		rebirthButton.BackgroundColor3 = canAfford and THEME.AccentGold or THEME.PanelLight
		rebirthButton.AutoButtonColor = canAfford
	end
end

-- ============================================================
-- 5d. AFK WINDOW (открывается у NPC Dock Boy)
-- ============================================================
local afkPanel, afkContent = makeWindowPanel("AfkWindow", "Auto-Sorter Dock", UDim2.fromOffset(420, 360))

local afkInfoLabel = makeLabel(
	"Info", afkContent, UDim2.new(1, 0, 0, 56), nil,
	"The dock slowly accrues Shells while you play. Collect them here anytime.",
	13, THEME.TextSecondary, THEME.FontRegular, Enum.TextXAlignment.Center
)
afkInfoLabel.TextWrapped = true

local afkBarBg = makeFrame("AfkBarBackground", afkContent, UDim2.new(1, 0, 0, 30), nil, THEME.Background)
local afkBarFill = Instance.new("Frame")
afkBarFill.Name = "Fill"
afkBarFill.Size = UDim2.fromScale(0, 1)
afkBarFill.BackgroundColor3 = THEME.Accent
afkBarFill.BorderSizePixel = 0
afkBarFill.Parent = afkBarBg
addCorner(afkBarFill)
local afkAmountLabel = makeLabel("Amount", afkBarBg, UDim2.fromScale(1, 1), nil, "0 Shells stored", 13, THEME.TextPrimary, THEME.Font, Enum.TextXAlignment.Center)

local afkCollectButton = makeButton("Collect", afkContent, UDim2.new(1, 0, 0, 50), nil, "Collect Shells", THEME.AccentGreen)
afkCollectButton.MouseButton1Click:Connect(function()
	Remotes.CollectAfkStorage:FireServer()
end)

-- ============================================================
-- Подключение кнопок нижней панели к окнам
-- ============================================================
local allWindows = { inventoryPanel, upgradesPanel, shopPanel, travelPanel, rebirthPanel, afkPanel }

inventoryToggleButton.MouseButton1Click:Connect(function()
	toggleWindow(inventoryPanel, allWindows)
end)

upgradesToggleButton.MouseButton1Click:Connect(function()
	toggleWindow(upgradesPanel, allWindows)
	if upgradesPanel.Visible then
		renderSkillTree()
	end
end)

shopToggleButton.MouseButton1Click:Connect(function()
	toggleWindow(shopPanel, allWindows)
end)

-- ============================================================
-- 6. Всплывающие уведомления (toast) — поимка, перегрев, удушение, ребирт
-- ============================================================
local toastContainer = Instance.new("Frame")
toastContainer.Name = "ToastContainer"
toastContainer.Size = UDim2.fromOffset(320, 400)
toastContainer.Position = UDim2.new(1, -336, 0, 70)
toastContainer.BackgroundTransparency = 1
toastContainer.Parent = hud

local toastLayout = Instance.new("UIListLayout")
toastLayout.Padding = UDim.new(0, 6)
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.Parent = toastContainer

local function showToast(text, color)
	playSound("NotificationPop")

	local toast = makeFrame("Toast", toastContainer, UDim2.new(1, 0, 0, 44), nil, color or THEME.Panel)
	makeLabel("Text", toast, UDim2.new(1, -16, 1, 0), UDim2.fromOffset(8, 0), text, 14, THEME.TextPrimary, THEME.Font, Enum.TextXAlignment.Center)

	toast.BackgroundTransparency = 1
	local fillCover = Instance.new("Frame")
	fillCover.Size = UDim2.fromScale(1, 1)
	fillCover.BackgroundColor3 = color or THEME.Panel
	fillCover.BackgroundTransparency = 0
	fillCover.ZIndex = 0
	fillCover.Parent = toast
	addCorner(fillCover)
	toast.BackgroundTransparency = 1

	TweenService:Create(fillCover, TweenInfo.new(0.25), { BackgroundTransparency = 0 }):Play()

	task.delay(3, function()
		local fadeTween = TweenService:Create(toast, TweenInfo.new(0.4), { BackgroundTransparency = 1 })
		TweenService:Create(fillCover, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		fadeTween:Play()
		fadeTween.Completed:Wait()
		toast:Destroy()
	end)
end

-- ============================================================
-- Подписки на серверные события
-- ============================================================

Remotes.OxygenUpdate.OnClientEvent:Connect(function(current, max)
	local ratio = max > 0 and (current / max) or 0
	TweenService:Create(oxygenBarFill, TweenInfo.new(0.3), { Size = UDim2.fromScale(ratio, 1) }):Play()
	oxygenLabel.Text = string.format("Oxygen: %ds", math.ceil(current))
	oxygenBarFill.BackgroundColor3 = (current <= GameConfig.Oxygen.LowOxygenWarningAt) and THEME.AccentRed or THEME.Accent
end)

Remotes.PlayerAsphyxiated.OnClientEvent:Connect(function()
	showToast("You ran out of oxygen! Some catches were lost.", THEME.AccentRed)
end)

Remotes.CatchResult.OnClientEvent:Connect(function(resultData)
	if not resultData.Success then return end
	if resultData.IsTrash then
		showToast(("Popped %s  +%d Shells"):format(resultData.TrashKind or "trash", resultData.Value or 0), THEME.Accent)
	else
		showToast(("Caught jellyfish [%s]"):format(resultData.RarityId), THEME.AccentGreen)
	end
end)

Remotes.DrillResult.OnClientEvent:Connect(function(resultData)
	showToast(("+%d %s"):format(resultData.Amount, resultData.ResourceId), THEME.Accent)
end)

Remotes.DrillOverheat.OnClientEvent:Connect(function(isOverheated)
	if isOverheated then
		showToast("Crusher Drill overheated! Wait to cool down.", THEME.AccentRed)
	end
end)

Remotes.SellResult.OnClientEvent:Connect(function(totalEarned)
	showToast(("Sold catches for %d Shells!"):format(math.floor(totalEarned)), THEME.AccentGold)
end)

Remotes.RebirthResult.OnClientEvent:Connect(function(resultData)
	-- Тихий снапшот состояния ребирта (присылается при заходе и после ребирта) —
	-- обновляет окно без всплывашки.
	if resultData.InfoOnly then
		latestRebirthLevel = resultData.RebirthLevel or latestRebirthLevel
		latestRebirthRequirement = resultData.Requirement or latestRebirthRequirement
		updateRebirthInfo(latestRebirthLevel, latestRebirthRequirement)
		return
	end

	if resultData.Success then
		latestRebirthLevel = resultData.NewLevel or (latestRebirthLevel + 1)
		latestRebirthRequirement = resultData.Requirement or latestRebirthRequirement
		updateRebirthInfo(latestRebirthLevel, latestRebirthRequirement)
		showToast(("Rebirth complete! Now level %d."):format(resultData.NewLevel), THEME.AccentGold)
	else
		local reasons = {
			not_enough_currency = "Not enough Shells.",
			max_level_reached = "Already at max rebirth.",
		}
		showToast("Rebirth failed: " .. (reasons[resultData.Reason] or tostring(resultData.Reason)), THEME.AccentRed)
	end
end)

Remotes.UpgradeStateUpdate.OnClientEvent:Connect(function(snapshot, currentShells)
	latestUpgradeSnapshot = snapshot
	latestShells = math.floor(currentShells)
	currencyLabel.Text = string.format("%d Shells", latestShells)
	if upgradesPanel.Visible then
		renderSkillTree()
		updateDetailsPanel(selectedNodeKey)
	end
	-- Если открыто окно ребирта — пересчитать доступность кнопки под новую валюту.
	if rebirthPanel.Visible then
		updateRebirthInfo(latestRebirthLevel, latestRebirthRequirement)
	end
end)

Remotes.ZoneStateUpdate.OnClientEvent:Connect(function(unlockedZones)
	unlockedZonesSet = {}
	for _, zoneId in ipairs(unlockedZones) do
		unlockedZonesSet[zoneId] = true
	end
	refreshTravelWindow()
end)

Remotes.AfkStateUpdate.OnClientEvent:Connect(function(stored, maxStored)
	local ratio = maxStored > 0 and math.clamp(stored / maxStored, 0, 1) or 0
	afkBarFill.Size = UDim2.fromScale(ratio, 1)
	afkAmountLabel.Text = string.format("%d / %d Shells stored", math.floor(stored), math.floor(maxStored))
end)

Remotes.InventoryStateUpdate.OnClientEvent:Connect(function(items, maxSlots)
	refreshInventoryDisplay(items, maxSlots)
end)

-- Звуки, которые сервер просит проиграть персонально этому игроку
-- (SoundService.PlayToPlayer на сервере шлёт именно сюда)
Remotes.PlayLocalSound.OnClientEvent:Connect(function(soundKey)
	playSound(soundKey)
end)

-- Кнопка продажи всего инвентаря
sellAllButton.MouseButton1Click:Connect(function()
	Remotes.SellInventory:FireServer()
end)

-- ============================================================
-- Открытие окон по сигналу с сервера (ProximityPrompt на зданиях острова)
-- ============================================================
local windowsByName = {
	Shop = shopPanel,
	Upgrades = upgradesPanel,
	Inventory = inventoryPanel,
	Travel = travelPanel,
	Rebirth = rebirthPanel,
	Afk = afkPanel,
}

Remotes.OpenClientWindow.OnClientEvent:Connect(function(windowName)
	-- Специальный сигнал: NPC Quartermaster выдал обе пушки.
	if windowName == "ToolsGranted" then
		showToast("You received the Bubble Cannon & Crusher Drill! Equip them from your backpack.", THEME.Accent)
		return
	end

	local panel = windowsByName[windowName]
	if not panel then
		showToast("Coming soon: " .. tostring(windowName), THEME.Accent)
		return
	end

	for _, other in ipairs(allWindows) do
		other.Visible = false
	end
	panel.Visible = true
	playSound("UIClick")
	if panel == upgradesPanel then
		renderSkillTree()
	elseif panel == travelPanel then
		refreshTravelWindow()
	elseif panel == rebirthPanel then
		updateRebirthInfo(latestRebirthLevel, latestRebirthRequirement)
	end
end)

-- Старый BindableEvent оставлен для совместимости (на случай если где-то в Studio
-- уже подключён ProximityPrompt напрямую на него) — просто открывает магазин.
local openShopBindable = ReplicatedStorage:FindFirstChild("OpenShopBindable")
if not openShopBindable then
	openShopBindable = Instance.new("BindableEvent")
	openShopBindable.Name = "OpenShopBindable"
	openShopBindable.Parent = ReplicatedStorage
end

openShopBindable.Event:Connect(function()
	toggleWindow(shopPanel, allWindows)
	shopPanel.Visible = true
end)

-- Все обработчики OnClientEvent уже подключены выше — теперь сообщаем серверу, что готовы.
-- Сервер в ответ пришлёт полный снапшот (валюта, дерево навыков, инвентарь, зоны).
-- Это устраняет гонку, когда сервер отправлял данные раньше, чем этот скрипт успевал
-- подписаться на события.
Remotes.RequestInitialState:FireServer()

print("[MasterUI] UI собран и готов к работе.")
