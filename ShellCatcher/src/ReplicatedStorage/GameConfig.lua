--[[
	GameConfig.lua
	Единый источник правды для баланса Shell Catcher.
	Лежит в ReplicatedStorage, чтобы сервер и клиент читали одни и те же числа.
]]

local GameConfig = {}

-- ============================================================
-- КИСЛОРОД (таймер сессии в зоне лова)
-- ============================================================
GameConfig.Oxygen = {
	BaseMax = 60,           -- секунд базового запаса кислорода
	DrainPerSecond = 1,     -- расход в секунду находясь в зоне
	RegenNearBase = 8,      -- восстановление в секунду у лодки/базы
	LowOxygenWarningAt = 15,-- порог для UI-предупреждения (мигание/звук)
	PenaltyLossPercent = 0.5, -- сколько % улова теряется при "заглушке" (0 кислорода)
}

-- ============================================================
-- ЗОНЫ ЛОВА (аналог биомов). Дизайн: 4 на старт, легко добавить 5-ю+.
-- ============================================================
GameConfig.Zones = {
	{
		Id = "reef",
		Name = "Coral Reef Shallows",
		UnlockCost = 0,            -- бесплатная стартовая зона
		OxygenMultiplier = 1.0,    -- 1.0 = обычный расход
		CatchValueMultiplier = 1.0,
		HazardLevel = 0,           -- 0 = без угроз урона
	},
	{
		Id = "kelp",
		Name = "Kelp Forest",
		UnlockCost = 250,          -- в игровой валюте (Shells)
		OxygenMultiplier = 1.15,
		CatchValueMultiplier = 2.2,
		HazardLevel = 0,
		-- Ферри открывает погружение только при достаточной прокачке акваланга:
		-- глубже -> нужен больший уровень узла OxygenCapacity (дерево навыков).
		RequiredOxygenLevel = 1,
	},
	{
		Id = "trench",
		Name = "Murk Trench",
		UnlockCost = 1200,
		OxygenMultiplier = 1.35,
		CatchValueMultiplier = 5.5,
		HazardLevel = 1,           -- лёгкие шоковые/ядовитые силуэты
		RequiredOxygenLevel = 3,
	},
	{
		Id = "vent",
		Name = "Thermal Vent Abyss",
		UnlockCost = 6000,
		OxygenMultiplier = 1.6,
		CatchValueMultiplier = 14,
		HazardLevel = 2,           -- больше урона, нужен Resist-скилл/гейр
		RequiredOxygenLevel = 5,
	},
	-- Задел на будущее расширение: просто добавляешь сюда новую запись,
	-- остальные системы (магазин, спавнер, UI) читают список динамически.
}

-- ============================================================
-- РЕДКОСТИ ДОБЫЧИ (силуэты раскрываются после поимки)
-- ============================================================
-- Силуэт спавнится без раскрытого вида; вид и редкость решаются в момент поимки (RNG),
-- это и есть "гача-момент" вскрытия силуэта.
GameConfig.Rarities = {
	{ Id = "Common",    Weight = 600, ValueMultiplier = 1,   Color = Color3.fromRGB(200, 200, 200) },
	{ Id = "Uncommon",  Weight = 250, ValueMultiplier = 3,   Color = Color3.fromRGB(90, 200, 110) },
	{ Id = "Rare",      Weight = 110, ValueMultiplier = 9,   Color = Color3.fromRGB(70, 140, 230) },
	{ Id = "Epic",      Weight = 35,  ValueMultiplier = 28,  Color = Color3.fromRGB(170, 80, 230) },
	{ Id = "Legendary", Weight = 5,   ValueMultiplier = 100, Color = Color3.fromRGB(250, 190, 60) },
}

-- ============================================================
-- ИНСТРУМЕНТЫ
-- ============================================================
GameConfig.Tools = {
	HarpoonNet = {
		-- Историческое имя ключа сохранено (его читают дерево навыков и сервисы),
		-- но по дизайну это теперь "Пушка пузырей": стреляет пузырями и ловит медуз.
		DisplayName = "Bubble Cannon",
		BaseDamage = 10,         -- урон по "здоровью" медузы до поимки
		BaseFireRate = 1.4,      -- выстрелов в секунду
		BaseRange = 28,
		AmmoCapacity = 6,
		ReloadTime = 1.2,
	},
	CrusherDrill = {
		DisplayName = "Crusher Drill",
		BaseDamage = 14,
		BaseFireRate = 1.0,
		BaseRange = 10,          -- ближний радиус, бьёт по ресурсным блокам
		AmmoCapacity = 1,        -- работает по "заряду", не клипу
		OverheatAfter = 8,       -- секунд непрерывного использования до перегрева
	},
}

-- ============================================================
-- ЛАЗЕР CRUSHER DRILL (заряжаемый направленный выстрел)
-- Дробилка НЕ стреляет мгновенно: игрок зажимает кнопку, оружие копит заряд
-- (полоса заряда над пушкой), и при полном заряде выпускает большой направленный
-- ЛАЗЕР, который дробит мусор/ресурсы на своём пути. Время заряда и урон лазера
-- скейлятся веткой прокачки (DrillFireRate -> быстрее заряд, DrillDamage -> урон,
-- DrillRange -> длина луча).
-- ============================================================
GameConfig.CrusherLaser = {
	BaseChargeTime = 1.6,        -- секунд удержания до полного заряда на 1 уровне FireRate
	MinChargeTime = 0.45,        -- предел, до которого может ускориться заряд прокачкой
	ChargeTimePerFireRate = 0.18,-- на сколько секунд сокращается заряд за уровень DrillFireRate
	BaseBeamLength = 28,         -- длина луча (studs) на базовом DrillRange
	BeamLengthPerRange = 2.2,    -- +длина за единицу прибавки DrillRange над базой
	BeamThickness = 1.6,         -- толщина визуального луча
	BaseLaserDamage = 30,        -- урон лазера (он мощнее одиночного удара)
	LaserDamagePerLevel = 8,     -- множитель от DrillDamage поверх базы
	Color = Color3.fromRGB(255, 90, 40),
}

-- ============================================================
-- ПРОКАЧКА — РАДИАЛЬНОЕ ДЕРЕВО НАВЫКОВ
-- Узлы расходятся лучами от центрального узла "Start" (как круговое skill-дерево
-- в духе ARPG: открыть узел можно только купив его прямого родителя).
--
-- Angle  — направление луча от центра, градусы (0 = вправо, 90 = вверх, и т.д.)
-- Radius — расстояние слоя от центра (слой 1 = первое кольцо, слой 2 = следующее и т.д.)
-- ParentKey — ключ родительского узла; nil/отсутствует = растёт прямо из центра
-- Branch — для подсветки цветом луча (Harpoon / Drill / Oxygen / Inventory)
-- ============================================================
GameConfig.UpgradeTree = {

	-- Центральный узел дерева — не апгрейд, просто "ствол", всегда открыт.
	Start = {
		DisplayName = "Diver's Core",
		Branch = "Core",
		Angle = 0,
		Radius = 0,
		ParentKey = nil,
		IsRoot = true,
	},

	-- ================= ВЕТКА: HARPOON NET (луч вверх, 60°..120°) =================
	HarpoonDamage = {
		DisplayName = "Harpoon Damage",
		Tool = "HarpoonNet", Stat = "Damage",
		Branch = "Harpoon", Angle = 100, Radius = 1, ParentKey = "Start",
		MaxLevel = 10, BaseCost = 50, CostGrowth = 1.45, BaseValue = 10, ValuePerLevel = 4,
	},
	HarpoonFireRate = {
		DisplayName = "Harpoon Fire Rate",
		Tool = "HarpoonNet", Stat = "FireRate",
		Branch = "Harpoon", Angle = 80, Radius = 1, ParentKey = "Start",
		MaxLevel = 8, BaseCost = 75, CostGrowth = 1.5, BaseValue = 1.4, ValuePerLevel = 0.18,
	},
	HarpoonRange = {
		DisplayName = "Harpoon Range",
		Tool = "HarpoonNet", Stat = "Range",
		Branch = "Harpoon", Angle = 100, Radius = 2, ParentKey = "HarpoonDamage",
		MaxLevel = 6, BaseCost = 60, CostGrowth = 1.4, BaseValue = 28, ValuePerLevel = 5,
	},
	HarpoonReload = {
		DisplayName = "Harpoon Reload Speed",
		Tool = "HarpoonNet", Stat = "ReloadTime",
		Branch = "Harpoon", Angle = 80, Radius = 2, ParentKey = "HarpoonFireRate",
		MaxLevel = 6, BaseCost = 65, CostGrowth = 1.4, BaseValue = 1.2, ValuePerLevel = -0.1,
	},
	HarpoonCrit = {
		DisplayName = "Harpoon Critical Chance",
		Tool = "HarpoonNet", Stat = "CritChance",
		Branch = "Harpoon", Angle = 90, Radius = 3, ParentKey = "HarpoonRange",
		MaxLevel = 5, BaseCost = 220, CostGrowth = 1.55, BaseValue = 0, ValuePerLevel = 0.04,
	},

	-- ================= ВЕТКА: CRUSHER DRILL (луч вправо, -20°..20°) =================
	DrillDamage = {
		DisplayName = "Drill Damage",
		Tool = "CrusherDrill", Stat = "Damage",
		Branch = "Drill", Angle = 10, Radius = 1, ParentKey = "Start",
		MaxLevel = 10, BaseCost = 55, CostGrowth = 1.45, BaseValue = 14, ValuePerLevel = 5,
	},
	DrillFireRate = {
		DisplayName = "Drill Fire Rate",
		Tool = "CrusherDrill", Stat = "FireRate",
		Branch = "Drill", Angle = -10, Radius = 1, ParentKey = "Start",
		MaxLevel = 8, BaseCost = 70, CostGrowth = 1.5, BaseValue = 1.0, ValuePerLevel = 0.15,
	},
	DrillOverheat = {
		DisplayName = "Heat Capacity",
		Tool = "CrusherDrill", Stat = "OverheatAfter",
		Branch = "Drill", Angle = 10, Radius = 2, ParentKey = "DrillDamage",
		MaxLevel = 6, BaseCost = 80, CostGrowth = 1.4, BaseValue = 8, ValuePerLevel = 2,
	},
	DrillRange = {
		DisplayName = "Drill Range",
		Tool = "CrusherDrill", Stat = "Range",
		Branch = "Drill", Angle = -10, Radius = 2, ParentKey = "DrillFireRate",
		MaxLevel = 5, BaseCost = 75, CostGrowth = 1.4, BaseValue = 10, ValuePerLevel = 2.5,
	},
	DrillChainBreak = {
		DisplayName = "Chain Break Chance",
		Tool = "CrusherDrill", Stat = "ChainBreakChance",
		Branch = "Drill", Angle = 0, Radius = 3, ParentKey = "DrillOverheat",
		MaxLevel = 5, BaseCost = 240, CostGrowth = 1.55, BaseValue = 0, ValuePerLevel = 0.05,
	},

	-- ================= ВЕТКА: OXYGEN TANK (луч вниз, 250°..290°) =================
	OxygenCapacity = {
		DisplayName = "Oxygen Tank Capacity",
		Tool = "Oxygen", Stat = "Max",
		Branch = "Oxygen", Angle = 260, Radius = 1, ParentKey = "Start",
		MaxLevel = 10, BaseCost = 90, CostGrowth = 1.5, BaseValue = 60, ValuePerLevel = 12,
	},
	OxygenRegen = {
		DisplayName = "Oxygen Regen Speed",
		Tool = "Oxygen", Stat = "RegenNearBase",
		Branch = "Oxygen", Angle = 280, Radius = 1, ParentKey = "Start",
		MaxLevel = 8, BaseCost = 85, CostGrowth = 1.45, BaseValue = 8, ValuePerLevel = 2,
	},
	OxygenEfficiency = {
		DisplayName = "Oxygen Efficiency",
		Tool = "Oxygen", Stat = "DrainPerSecond",
		Branch = "Oxygen", Angle = 260, Radius = 2, ParentKey = "OxygenCapacity",
		MaxLevel = 6, BaseCost = 100, CostGrowth = 1.5, BaseValue = 1, ValuePerLevel = -0.1,
	},
	OxygenWarning = {
		DisplayName = "Low Oxygen Sense",
		Tool = "Oxygen", Stat = "LowOxygenWarningAt",
		Branch = "Oxygen", Angle = 280, Radius = 2, ParentKey = "OxygenRegen",
		MaxLevel = 4, BaseCost = 90, CostGrowth = 1.4, BaseValue = 15, ValuePerLevel = 3,
	},
	OxygenDeepDive = {
		DisplayName = "Deep Dive Mastery",
		Tool = "Oxygen", Stat = "ZoneOxygenPenaltyReduction",
		Branch = "Oxygen", Angle = 270, Radius = 3, ParentKey = "OxygenEfficiency",
		MaxLevel = 5, BaseCost = 260, CostGrowth = 1.55, BaseValue = 0, ValuePerLevel = 0.06,
	},

	-- ================= ВЕТКА: INVENTORY (луч влево, 160°..200°) =================
	InventorySlots = {
		DisplayName = "Inventory Slots",
		Tool = "Inventory", Stat = "Slots",
		Branch = "Inventory", Angle = 170, Radius = 1, ParentKey = "Start",
		MaxLevel = 12, BaseCost = 120, CostGrowth = 1.4, BaseValue = 30, ValuePerLevel = 5,
	},
	PickupRange = {
		DisplayName = "Pickup Range",
		Tool = "Inventory", Stat = "PickupRange",
		Branch = "Inventory", Angle = 190, Radius = 1, ParentKey = "Start",
		MaxLevel = 6, BaseCost = 65, CostGrowth = 1.4, BaseValue = 6, ValuePerLevel = 1.5,
	},
	SellSpeed = {
		DisplayName = "Sell Speed",
		Tool = "Inventory", Stat = "SellSpeedMultiplier",
		Branch = "Inventory", Angle = 170, Radius = 2, ParentKey = "InventorySlots",
		MaxLevel = 8, BaseCost = 130, CostGrowth = 1.45, BaseValue = 1, ValuePerLevel = 0.12,
	},
	AutoSort = {
		DisplayName = "Auto-Sort Catches",
		Tool = "Inventory", Stat = "AutoSortEnabled",
		Branch = "Inventory", Angle = 190, Radius = 2, ParentKey = "PickupRange",
		MaxLevel = 1, BaseCost = 300, CostGrowth = 1, BaseValue = 0, ValuePerLevel = 1,
	},
	StorageStretch = {
		DisplayName = "Storage Stretch",
		Tool = "Inventory", Stat = "SlotCapacityBonus",
		Branch = "Inventory", Angle = 180, Radius = 3, ParentKey = "SellSpeed",
		MaxLevel = 5, BaseCost = 280, CostGrowth = 1.55, BaseValue = 0, ValuePerLevel = 0.1,
	},
}

-- Цвета веток для отрисовки луча/узлов в UI (читается клиентом)
GameConfig.BranchColors = {
	Core      = Color3.fromRGB(255, 255, 255),
	Harpoon   = Color3.fromRGB(255, 90, 90),
	Drill     = Color3.fromRGB(250, 200, 70),
	Oxygen    = Color3.fromRGB(80, 200, 255),
	Inventory = Color3.fromRGB(120, 220, 130),
}

-- ============================================================
-- Старое плоское представление (GameConfig.Upgrades) оставлено как ALIAS
-- на UpgradeTree, чтобы остальной код (UpgradeService и т.д.) продолжал работать
-- без переписывания: смотри ниже автогенерацию.
-- ============================================================
GameConfig.Upgrades = {}
for key, nodeConfig in pairs(GameConfig.UpgradeTree) do
	if not nodeConfig.IsRoot then
		GameConfig.Upgrades[key] = nodeConfig
	end
end

-- ============================================================
-- ЗВУКИ — ВСЕ SoundId — ЗАГЛУШКИ (пустая строка = звук не играет).
-- Замени каждое значение на "rbxassetid://ТВОЙ_ID" когда подберёшь/загрузишь звук.
-- Ключи используются SoundService.PlayAt/PlayToPlayer и клиентским MasterUI —
-- ничего больше менять не нужно после простановки ID.
-- ============================================================
GameConfig.SoundIds = {
	-- Инструменты
	HarpoonFire        = "", -- выстрел сетью/гарпуном
	HarpoonCatchSuccess= "", -- "дзынь" в момент успешной поимки (силуэт раскрылся)
	DrillFire          = "", -- удар дробящего инструмента по блоку
	DrillBreakBlock    = "", -- блок разрушен, ресурс выпал
	DrillOverheat      = "", -- инструмент перегрелся

	-- Кислород
	OxygenLowWarning   = "", -- предупреждающий сигнал на низком кислороде (повторяется)
	Asphyxiate         = "", -- "захлебнулся", обнулился кислород

	-- Экономика
	SellAll            = "", -- продал весь инвентарь
	CoinPickup         = "", -- мелкий "монетный" звук (например при сборе ресурса)
	UpgradeBuy         = "", -- купил узел в дереве навыков
	UpgradeMaxed       = "", -- узел дерева достиг максимума
	NotEnoughCurrency  = "", -- попытка купить без денег ("эй, не хватает")

	-- Мета-прогрессия
	RebirthSuccess     = "", -- успешный ребирт (что-то торжественное)
	ZoneUnlock         = "", -- разблокирована новая зона лова

	-- UI
	UIClick            = "", -- обычный клик по кнопке/открытие окна
	UIClose            = "", -- закрытие окна
	NotificationPop    = "", -- появление toast-уведомления

	-- Покупки за Robux
	GamePassPurchased  = "", -- успешная покупка геймпасса
	ProductPurchased   = "", -- успешная покупка dev-продукта

	-- Окружение (ambient, зацикленные — используются на Part напрямую, не через SoundService)
	ZoneAmbient_reef   = "",
	ZoneAmbient_kelp   = "",
	ZoneAmbient_trench = "",
	ZoneAmbient_vent   = "",
	BuildingAmbient    = "", -- общий фоновый звук для зданий (можно различать по зданию вручную)
	NPCVoice           = "", -- "бубнящий" звук при разговоре с NPC
}

-- Громкость по умолчанию для каждого звука (от 0 до 1) — настраивай отдельно от ID
GameConfig.SoundVolumes = {
	HarpoonFire = 0.5,
	HarpoonCatchSuccess = 0.6,
	DrillFire = 0.45,
	DrillBreakBlock = 0.55,
	DrillOverheat = 0.6,
	OxygenLowWarning = 0.5,
	Asphyxiate = 0.7,
	SellAll = 0.6,
	CoinPickup = 0.35,
	UpgradeBuy = 0.55,
	UpgradeMaxed = 0.6,
	NotEnoughCurrency = 0.4,
	RebirthSuccess = 0.8,
	ZoneUnlock = 0.6,
	UIClick = 0.3,
	UIClose = 0.3,
	NotificationPop = 0.35,
	GamePassPurchased = 0.7,
	ProductPurchased = 0.6,
}

-- ============================================================
-- ЭКОНОМИКА БАЗОВЫХ ЗДАНИЙ НА ОСТРОВЕ (разблокируются по отдельности)
-- ============================================================
GameConfig.IslandBuildings = {
	{ Id = "shop_basic",     Name = "Trading Stall",       UnlockCost = 0 },
	{ Id = "storage_room",   Name = "Storage Shed",        UnlockCost = 500 },
	{ Id = "afk_dock",       Name = "Auto-Sorter Dock",    UnlockCost = 3000 }, -- AFK-машина
	{ Id = "skin_workshop",  Name = "Skin Workshop",       UnlockCost = 1500 },
	{ Id = "rebirth_altar",  Name = "Rebirth Altar",       UnlockCost = 10000 },
}

-- ============================================================
-- МЕДУЗЫ (живая добыча, ловится Пушкой пузырей)
-- Это бывшие "силуэты" — теперь полупрозрачные неоновые медузы, которые плавают
-- в зоне. Внешний вид (цвет купола) задаётся по зоне; редкость по-прежнему решается
-- RNG в момент поимки (см. HarpoonToolService.rollRarity).
-- ============================================================
GameConfig.Jellyfish = {
	BaseHealth = 20,            -- сколько урона нужно нанести пузырями до поимки
	MaxPerZone = 14,            -- одновременно живых медуз в зоне
	SpawnInterval = 2.5,        -- как часто пытаемся доспавнить (сек)
	BobAmplitude = 1.6,         -- амплитуда покачивания вверх/вниз (studs)
	DriftRadius = 9,            -- радиус блуждания вокруг точки спавна (studs)
	-- Цвет купола медузы по зоне (неоновый, полупрозрачный)
	ColorByZone = {
		reef   = Color3.fromRGB(255, 140, 200),
		kelp   = Color3.fromRGB(150, 255, 170),
		trench = Color3.fromRGB(140, 160, 255),
		vent   = Color3.fromRGB(255, 120, 90),
	},
}

-- ============================================================
-- ПЛАВАЮЩИЙ МУСОР (дрейфующий хлам в зонах)
-- По просьбе дизайна: кроме медуз в зоне дрейфует мусор. Его тоже можно "лопнуть"
-- Пушкой пузырей ради мелкой награды в Shells — лёгкий постоянный доход + оживляет сцену.
-- ============================================================
GameConfig.Trash = {
	MaxPerZone = 10,
	SpawnInterval = 4,
	BaseValue = 3,             -- базовые Shells за единицу мусора (умножается на CatchValueMultiplier зоны)
	Health = 10,               -- базовое здоровье мусора (умножается на HealthMul вида)
	DriftSpeed = 4,            -- скорость медленного дрейфа (studs/сек ориентир для твина)
	-- Виды мусора: у каждого СВОЁ название (показывается билбордом), размер (большой/маленький),
	-- здоровье (большой крепче) и ценность (большой дороже). Size — это Vector3-заготовка
	-- через {x,y,z}, ValueMul/HealthMul — множители поверх BaseValue/здоровья.
	Kinds = {
		{ Id = "soda_can",    DisplayName = "Ржавая банка",     Color = Color3.fromRGB(180, 180, 190), Shape = "Cylinder", Size = {1.2, 1.2, 1.2}, HealthMul = 0.6, ValueMul = 0.7 },
		{ Id = "bottle",      DisplayName = "Стеклянная бутылка", Color = Color3.fromRGB(120, 200, 180), Shape = "Cylinder", Size = {1.0, 2.0, 1.0}, HealthMul = 0.8, ValueMul = 1.0 },
		{ Id = "plastic_bag", DisplayName = "Пакет",            Color = Color3.fromRGB(210, 210, 220), Shape = "Block",    Size = {1.6, 1.6, 0.4}, HealthMul = 0.5, ValueMul = 0.8 },
		{ Id = "crate",       DisplayName = "Сломанный ящик",   Color = Color3.fromRGB(150, 110, 70),  Shape = "Block",    Size = {3.0, 3.0, 3.0}, HealthMul = 1.8, ValueMul = 2.4 },
		{ Id = "tire",        DisplayName = "Покрышка",         Color = Color3.fromRGB(40, 40, 45),    Shape = "Cylinder", Size = {3.4, 1.2, 3.4}, HealthMul = 1.6, ValueMul = 2.0 },
		{ Id = "barrel",      DisplayName = "Бочка с хламом",   Color = Color3.fromRGB(90, 130, 90),   Shape = "Cylinder", Size = {2.6, 3.4, 2.6}, HealthMul = 2.4, ValueMul = 3.2 },
		{ Id = "anchor",      DisplayName = "Старый якорь",     Color = Color3.fromRGB(70, 75, 85),    Shape = "Block",    Size = {2.2, 4.0, 1.0}, HealthMul = 3.0, ValueMul = 4.5 },
	},
}

-- Названия медуз по зоне (показываются билбордом над медузой)
GameConfig.JellyfishNames = {
	reef   = "Коралловая медуза",
	kelp   = "Ламинариевая медуза",
	trench = "Глубинная медуза",
	vent   = "Жар-медуза",
}

-- ============================================================
-- НПС ОСТРОВА (реестр ролей)
-- Каждый НПС — точка интереса на острове с конкретной ролью. MapBuilder строит
-- модель по этому списку, NPCService привязывает к роли действие:
--   Quartermaster -> выдаёт ОБЕ пушки (Bubble Cannon + Crusher Drill)
--   FerryCaptain  -> открывает окно телепортации по зонам (Travel)
--   Shopkeeper    -> открывает магазин (Robux)
--   StorageKeeper -> открывает инвентарь / продажу
--   AfkOperator   -> открывает окно AFK-дока
--   RebirthPriest -> открывает окно ребирта
-- Angle/Radius — расстановка по кольцу вокруг центра острова.
-- ============================================================
GameConfig.NPCs = {
	{ Id = "quartermaster", Name = "Quartermaster Brine",  Role = "Quartermaster", Angle = 90,  Radius = 24, Color = Color3.fromRGB(80, 150, 220) },
	{ Id = "ferry_captain", Name = "Ferry Captain Maris",  Role = "FerryCaptain",  Angle = 30,  Radius = 26, Color = Color3.fromRGB(70, 200, 210) },
	{ Id = "shopkeeper",    Name = "Trader Bramble",       Role = "Shopkeeper",    Angle = 150, Radius = 24, Color = Color3.fromRGB(90, 200, 120) },
	{ Id = "storage_keep",  Name = "Net Mender Tilly",     Role = "StorageKeeper", Angle = 210, Radius = 24, Color = Color3.fromRGB(180, 150, 110) },
	{ Id = "afk_operator",  Name = "Dock Boy Wren",        Role = "AfkOperator",   Angle = 330, Radius = 26, Color = Color3.fromRGB(80, 200, 255) },
	{ Id = "rebirth_priest",Name = "Tide Priestess Ova",   Role = "RebirthPriest", Angle = 270, Radius = 24, Color = Color3.fromRGB(250, 200, 70) },
}

-- Роль -> имя клиентского окна, которое сервер просит открыть (OpenClientWindow).
-- Quartermaster обрабатывается отдельно (выдача инструментов, без окна).
GameConfig.NPCRoleWindows = {
	FerryCaptain  = "Travel",
	Shopkeeper    = "Shop",
	StorageKeeper = "Inventory",
	AfkOperator   = "Afk",
	RebirthPriest = "Rebirth",
}

-- ============================================================
-- РЕБИРТ (мета-прогрессия)
-- ============================================================
GameConfig.Rebirth = {
	MaxLevel = 25,
	BaseCurrencyRequirement = 10000,
	RequirementGrowth = 1.6,    -- каждый ребирт дороже в 1.6 раза
	ValueBonusPerLevel = 0.12,  -- +12% к ценности улова за каждый уровень ребирта
	ResetsInventoryAndZones = true, -- по дизайну: ребирт сбрасывает прогресс зон, оставляет скины/геймпассы
}

return GameConfig
