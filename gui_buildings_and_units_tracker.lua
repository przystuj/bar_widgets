local widgetName = "Buildings/Units Tracker"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Shows counters for chosen units/buildings. Pinpointers, nukes and junos are displayed by default. Click icon to select one, shift click to select all. Edit counterGroups to add counters for different units",
        author = "SuperKitowiec",
        version = 0.8,
        license = "GNU GPL, v2 or later",
        layer = 0
    }
end

--[[
Each counterGroup is a separate draggable window with own counterDefinitions.counterDefinitions.counterDefinitions.
You can add own groups and definitions, just make sure that their ids are unique. You can make each group vertical or horizontal

Counter definition params:
id = unique identifier of the counter
alwaysVisible = if false, counter is displayed only if value is > 0
teamWide = if true, it counts across the whole team
unitNames = list of unit names. You can find them in url of this site https://www.beyondallreason.info/unit/armflea. For example Tick's name is armflea
counterType = COUNTER_TYPE_BASIC or COUNTER_TYPE_STOCKPILE. Basic is just a number of units/buildings. Stockpile shows current stockpile of missiles instead
greenThreshold (optional, only for COUNTER_TYPE_BASIC) = if counter is below greenThreshold the text is yellow. If it's above, the text is green.
skipWhenSpectating = counter won't be shown when spectating
icon = specify which unit icon should be displayed. For example icon = "armack"
]]
local COUNTER_TYPE_BASIC, COUNTER_TYPE_STOCKPILE = "basic", "stockpile"
local COUNTER_TYPE_HORIZONTAL, COUNTER_TYPE_VERTICAL = "horizontal", "vertical"
local counterGroups = {
    buildings = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "pinpointers",
                alwaysVisible = true,
                teamWide = true,
                unitNames = { armtarg = true, cortarg = true, },
                counterType = COUNTER_TYPE_BASIC,
                greenThreshold = 3
            },
            {
                id = "nukes",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armsilo = true, corsilo = true },
                counterType = COUNTER_TYPE_STOCKPILE
            },
            {
                id = "junos",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armjuno = true, corjuno = true, },
                counterType = COUNTER_TYPE_STOCKPILE
            },
        }
    },
    air = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "airt1cons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armca = true, corca = true, corcsa = true, armcsa = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
            },
            {
                id = "airt2cons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armaca = true, coraca = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
            },
            {
                id = "transports",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armatlas = true, armdfly = true, corvalk = true, corseah = true, },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
            },
            {
                id = "air scouts",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armpeep = true, armsehak = true, armawac = true, corfink = true, corhunt = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
            }
        }
    },
    groundCons = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "t1cons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armck = true,
                    corck = true,
                    armcv = true,
                    corcv = true,
                    cormuskrat = true,
                    armbeaver = true,
                    armcs = true,
                    corcs = true,
                    corch = true,
                    armch = true
                },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armck"
            },
            {
                id = "t2cons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armack = true, corack = true, armacv = true, coracv = true, armacsub = true, coracsub = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armack"
            },
            {
                id = "engineers",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armfark = true, armconsul = true, corfast = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "corfast"
            },
            {
                id = "resbots",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armrectr = true, cornecro = true, },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armrectr"
            }
        }
    },
    labs = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "t1labs",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armsy = true,
                    armlab = true,
                    armvp = true,
                    armap = true,
                    armfhp = true,
                    armhp = true,
                    armamsub = true,
                    armplat = true,
                    corsy = true,
                    corlab = true,
                    corvp = true,
                    corap = true,
                    corfhp = true,
                    corhp = true,
                    coramsub = true,
                    corplat = true,
                },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armlab"
            },
            {
                id = "t2labs",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armalab = true,
                    armavp = true,
                    armaap = true,
                    armfhp = true,
                    armasy = true,
                    coravp = true,
                    coralab = true,
                    corasy = true,
                    coraap = true,
                },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armalab"
            },
            {
                id = "t3labs",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armshltxuw = true, armshltx = true, corgant = true, corgantuw = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armshltx"
            }
        }
    },
    special = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "spies",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armspy = true, corspy = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armspy"
            },
            {
                id = "skuttles",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { corsktl = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "corsktl"
            }
        }
    },
}

local config = {
    iconSize = 50,
    refreshFrequency = 5,
    trackFactoryQuotas = true,
}

local OPTION_SPECS = {
    {
        configVariable = "iconSize",
        name = "Size",
        description = "Size of the unit icons.",
        type = "slider",
        min = 30,
        max = 100,
        step = 1,
        value = 60,
    },
    {
        configVariable = "refreshFrequency",
        name = "Refresh frequency",
        description = "How often data will be updated. Increase it to improve performance",
        type = "slider",
        min = 5,
        max = 60,
        step = 1,
        value = 5,
    },
    {
        configVariable = "trackFactoryQuotas",
        name = "Track Factory Quotas",
        description = "Tracks units added to factory quotas (requires cmd_factory_quota widget)",
        type = "bool",
        value = true,
    }
}

local requiredFrameworkVersion = 42
local countersCache, font, MasterFramework, FactoryQuotas
local red, green, yellow, white, backgroundColor, lightBlack
local spectatorMode
local trackFactoryQuotasCounterGroup = "trackFactoryQuotasCounterGroup"
local COUNTER_TYPE_FACTORY_QUOTA = "counterQuota"

-- Functions
local function applyColor(currentColor, newColor)
    currentColor.r = newColor.r
    currentColor.g = newColor.g
    currentColor.b = newColor.b
    currentColor.a = newColor.a
end

local function findUnits(teamIDs, unitDefIDs)
    return table.reduce(teamIDs, function(acc, teamID)
        table.append(acc, Spring.GetTeamUnitsByDefs(teamID, unitDefIDs))
        return acc
    end, {})
end

local function moveCameraToUnit(unitId)
    local ux, uy, uz = Spring.GetUnitPosition(unitId)
    local camState = Spring.GetCameraState()
    camState.px = ux
    camState.py = 0
    camState.pz = uz
    Spring.SetCameraState(camState, 1)
end

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function debug(message)
    Spring.SendCommands(string.format("say a:%s", dump(message)))
end

local function callUpdate(counterDef)
    if countersCache[counterDef.id] then
        countersCache[counterDef.id]:update(counterDef)
    end
end

-- Counters
local function UnitIcon(counterDef)
    return MasterFramework:Rect(
            MasterFramework:Dimension(config.iconSize),
            MasterFramework:Dimension(config.iconSize),
            MasterFramework:Dimension(3),
            { MasterFramework:Image("#" .. (counterDef.icon ~= nil and counterDef.icon or counterDef.unitDefs[1])) }
    )
end

local function TextWithBackground(text, textBackgroundColor)
    return MasterFramework:MarginAroundRect(text,
            MasterFramework:Dimension(5),
            MasterFramework:Dimension(1),
            MasterFramework:Dimension(3),
            MasterFramework:Dimension(2),
            { textBackgroundColor or lightBlack },
            MasterFramework:Dimension(5),
            true
    )
end

local handleClick = function(buttonParams)
    local _, isCtrlClick, _, isShiftClick = Spring.GetModKeyState()
    buttonParams.currentSelectedUnitIndex = buttonParams.currentSelectedUnitIndex + 1
    if (buttonParams.currentSelectedUnitIndex > #buttonParams.unitsToSelect) then
        buttonParams.currentSelectedUnitIndex = 1
    end
    table.sort(buttonParams.unitsToSelect)
    local unitArray = isShiftClick and buttonParams.unitsToSelect or { buttonParams.unitsToSelect[buttonParams.currentSelectedUnitIndex] }
    local shouldMoveCamera = isCtrlClick and not isShiftClick
    Spring.SelectUnitArray(unitArray, false)
    if shouldMoveCamera then
        moveCameraToUnit(unitArray[1])
    end
end

local function UnitCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end
    local currentColor = MasterFramework:Color(1, 1, 1, 1)
    local counterText = MasterFramework:Text("", currentColor, font)
    local buttonParams = {
        unitsToSelect = {},
        currentSelectedUnitIndex = 0
    }

    local counter = MasterFramework:Button(
            MasterFramework:MarginAroundRect(
                    MasterFramework:StackInPlace({ UnitIcon(counterDef),
                                                   TextWithBackground(counterText)
                    }, 0.975, 0.025),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    { backgroundColor },
                    MasterFramework:Dimension(10),
                    true
            ),
            function()
                handleClick(buttonParams)
            end
    )

    function counter:update(counterDef)
        buttonParams.unitsToSelect = counterDef.data
        local unitCount = #counterDef.data
        local newColor
        if unitCount == 0 then
            newColor = red
        elseif counterDef.greenThreshold and unitCount < counterDef.greenThreshold then
            newColor = yellow
        else
            newColor = counterDef.greenThreshold and green or white
        end

        counterText:SetString(string.format("%d", unitCount))
        applyColor(currentColor, newColor)
    end

    countersCache[counterDef.id] = counter
    return counter
end

local function FactoryQuotaCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end
    local currentColor = MasterFramework:Color(1, 1, 1, 1)
    local counterText = MasterFramework:Text("", currentColor, font)
    local buttonParams = {
        unitsToSelect = {},
        currentSelectedUnitIndex = 0
    }

    local counter = MasterFramework:Responder(
            MasterFramework:Button(
                    MasterFramework:MarginAroundRect(
                            MasterFramework:StackInPlace({ UnitIcon(counterDef),
                                                           TextWithBackground(counterText)
                            }, 0.975, 0.025),
                            MasterFramework:Dimension(3),
                            MasterFramework:Dimension(3),
                            MasterFramework:Dimension(3),
                            MasterFramework:Dimension(3),
                            { backgroundColor },
                            MasterFramework:Dimension(10),
                            true
                    ),
                    function()
                        handleClick(buttonParams)
                    end
            ),
            MasterFramework.events.mouseWheel, function(_, _, _, _, value)
                local alt, ctrl, meta, shift = Spring.GetModKeyState()
                local quotas = FactoryQuotas.getQuotas()
                local unitDefID = counterDef.unitDefs[1]
                local multiplier = 1
                if ctrl then multiplier = multiplier * 20 end
                if shift then multiplier = multiplier * 5 end
                local minValue = 1
                if meta or quotas[unitDefID].amount == 0 then
                    minValue = 0
                end
                local newAmount = math.max(minValue, quotas[unitDefID].amount + (value * multiplier))
                quotas[unitDefID].amount = newAmount
                FactoryQuotas.update(quotas)
            end)

    function counter:update(counterDef)
        buttonParams.unitsToSelect = counterDef.data
        local unitCount = #counterDef.data
        local newColor
        if unitCount == 0 then
            newColor = red
        elseif counterDef.greenThreshold and unitCount < counterDef.greenThreshold then
            newColor = yellow
        else
            newColor = counterDef.greenThreshold and green or white
        end

        counterText:SetString(string.format("%d/%d", unitCount, counterDef.greenThreshold))
        applyColor(currentColor, newColor)
    end

    countersCache[counterDef.id] = counter
    return counter
end

local function UnitWithStockpileCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end
    local buttonParams = {
        unitsToSelect = {},
        currentSelectedUnitIndex = 0
    }
    local stockpileColor = MasterFramework:Color(1, 0, 0, 1)
    local textBackgroundColor = MasterFramework:Color(0, 0, 0, 0.8)
    local stockpileText = MasterFramework:Text("", stockpileColor, font)
    local buildPercentText = MasterFramework:Text("", white, font)

    local counter = MasterFramework:Button(
            MasterFramework:MarginAroundRect(
                    MasterFramework:StackInPlace({ UnitIcon(counterDef),
                                                   MasterFramework:VerticalStack({
                                                       TextWithBackground(stockpileText, textBackgroundColor),
                                                       TextWithBackground(buildPercentText, textBackgroundColor),
                                                   }, MasterFramework:Dimension(1), 1),
                    }, 0.975, 0.025),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    MasterFramework:Dimension(3),
                    { backgroundColor },
                    MasterFramework:Dimension(10),
                    true
            ),
            function()
                handleClick(buttonParams)
            end
    )

    function counter:update(counterDef)
        if #counterDef.data == 0 then
            stockpileText:SetString("")
            buildPercentText:SetString("")
            textBackgroundColor.a = 0
            return
        end

        local stockpile = 0
        local maxStockpilePercent = 0
        local stockpileSlotsLeft = 0
        local color
        buttonParams.unitsToSelect = {}

        for _, unitId in ipairs(counterDef.data) do
            local unitStockpile, unitStockpileSlotsLeft, unitBuildPercent = Spring.GetUnitStockpile(unitId)
            if unitStockpile > 0 or spectatorMode then
                table.insert(buttonParams.unitsToSelect, unitId)
            end
            stockpileSlotsLeft = stockpileSlotsLeft + unitStockpileSlotsLeft
            stockpile = stockpile + unitStockpile
            if unitBuildPercent * 100 > maxStockpilePercent then
                maxStockpilePercent = unitBuildPercent * 100
            end
        end

        if stockpile == 0 then
            color = red
        else
            color = green
        end

        stockpileText:SetString(string.format("%d", stockpile))
        applyColor(stockpileColor, color)
        applyColor(textBackgroundColor, lightBlack)
        if stockpileSlotsLeft == 0 then
            buildPercentText:SetString("max")
        else
            buildPercentText:SetString(string.format("%2d%%", maxStockpilePercent))
        end
    end

    countersCache[counterDef.id] = counter
    return counter
end

local counterType = {
    [COUNTER_TYPE_BASIC] = UnitCounter,
    [COUNTER_TYPE_STOCKPILE] = UnitWithStockpileCounter,
    [COUNTER_TYPE_FACTORY_QUOTA] = FactoryQuotaCounter,
}

local function initUnitDefs()
    for unitDefID, unitDef in pairs(UnitDefs) do
        for _, counterGroup in pairs(counterGroups) do
            for _, counterDef in pairs(counterGroup.counterDefinitions) do
                if counterDef.unitDefs == nil then
                    counterDef.unitDefs = {}
                end
                if counterDef.unitNames[unitDef.name] then
                    table.insert(counterDef.unitDefs, unitDefID)
                end
                if counterDef.icon == unitDef.name then
                    counterDef.icon = unitDefID
                end
            end
        end
    end
end

local function updateTeamIds()
    local teamId, teamIds
    if spectatorMode then
        teamId = Spring.GetMyAllyTeamID()
        teamIds = Spring.GetTeamList(teamId)
    else
        teamId = Spring.GetMyTeamID()
        teamIds = { teamId }
    end
    local teamList = Spring.GetTeamList(teamId)

    return teamIds, teamList
end

local function hasData(counterDef)
    return counterDef.data ~= nil and #counterDef.data > 0
end

-- Widget logic
local function displayCounterGroup(counterGroupId, counterGroup)
    local frameId = widgetName .. counterGroupId
    if counterGroup.key == nil or MasterFramework:GetElement(counterGroup.key) == nil then
        counterGroup.key = MasterFramework:InsertElement(
                MasterFramework:MovableFrame(
                        frameId,
                        MasterFramework:PrimaryFrame(
                                MasterFramework:MarginAroundRect(
                                        counterGroup.contentStack,
                                        MasterFramework:Dimension(5),
                                        MasterFramework:Dimension(5),
                                        MasterFramework:Dimension(5),
                                        MasterFramework:Dimension(5),
                                        { backgroundColor },
                                        MasterFramework:Dimension(5),
                                        true
                                )
                        ),
                        1700,
                        900
                ),
                frameId,
                MasterFramework.layerRequest.bottom()
        )
    end
end

local function hideCounterGroup(counterGroup)
    MasterFramework:RemoveElement(counterGroup.key)
end

local function isFactoryQuotasTrackerEnabled()
    return config.trackFactoryQuotas and FactoryQuotas
end

local function updateFactoryQuotas()
    if isFactoryQuotasTrackerEnabled() then
        local counterGroup = counterGroups[trackFactoryQuotasCounterGroup]
        counterGroup.counterDefinitions = {}
        for unitDefID, quota in pairs(FactoryQuotas.getQuotas()) do
            if quota.amount > 0 then
                table.insert(counterGroup.counterDefinitions, {
                    id = "trackFactoryQuotasCounterGroup" .. unitDefID,
                    alwaysVisible = true,
                    teamWide = false,
                    unitDefs = { unitDefID },
                    counterType = COUNTER_TYPE_FACTORY_QUOTA,
                    greenThreshold = quota.amount,
                    icon = unitDefID
                })
            end
        end
    end
end

local function onFrame()
    updateFactoryQuotas()
    for _, counterGroup in pairs(counterGroups) do
        counterGroup.contentStack.members = {}
    end

    local playerId, teamIds = updateTeamIds()

    for counterGroupId, counterGroup in pairs(counterGroups) do
        local counterGroupIsVisible = false
        for _, counterDef in ipairs(counterGroup.counterDefinitions) do
            if not counterDef.skipWhenSpectating or not spectatorMode then
                local playerIdsToSearch = counterDef.teamWide and teamIds or playerId
                local units = findUnits(playerIdsToSearch, counterDef.unitDefs)
                counterDef.data = units
                if hasData(counterDef) or counterDef.alwaysVisible or spectatorMode then
                    table.insert(counterGroup.contentStack.members, counterType[counterDef.counterType](counterDef))
                    counterGroupIsVisible = true
                end
                callUpdate(counterDef)
            end
        end
        if not counterGroupIsVisible then
            hideCounterGroup(counterGroup)
        else
            displayCounterGroup(counterGroupId, counterGroup)
        end
    end
end

local function getOptionValue(optionSpec)
    if optionSpec.type == "slider" then
        return config[optionSpec.configVariable]
    elseif optionSpec.type == "bool" then
        return config[optionSpec.configVariable]
    elseif optionSpec.type == "select" then
        for i, v in ipairs(optionSpec.options) do
            if config[optionSpec.configVariable] == v then
                return i
            end
        end
    end
end

local function applyOptions()
    if MasterFramework ~= nil then
        font = MasterFramework:Font("Exo2-SemiBold.otf", config.iconSize / 4)
    end
    if not isFactoryQuotasTrackerEnabled() then
        if MasterFramework ~= nil then
            MasterFramework:RemoveElement(counterGroups[trackFactoryQuotasCounterGroup].key)
        end
        counterGroups[trackFactoryQuotasCounterGroup] = nil
    end
    if isFactoryQuotasTrackerEnabled() and MasterFramework ~= nil then
        counterGroups[trackFactoryQuotasCounterGroup] = {
            type = COUNTER_TYPE_HORIZONTAL,
            counterDefinitions = {},
            contentStack = counterType[COUNTER_TYPE_HORIZONTAL](MasterFramework, {}, MasterFramework:Dimension(8), 1)
        }
    end
    countersCache = {}
end

local function setOptionValue(optionSpec, value)
    if optionSpec.type == "slider" then
        config[optionSpec.configVariable] = value
    elseif optionSpec.type == "bool" then
        config[optionSpec.configVariable] = value
    elseif optionSpec.type == "select" then
        config[optionSpec.configVariable] = optionSpec.options[value]
    end
    applyOptions()
end

local function createOnChange(optionSpec)
    return function(i, value, force)
        setOptionValue(optionSpec, value)
    end
end

local function getOptionId(optionSpec)
    return "gui_buildings_and_units_tracker_" .. optionSpec.configVariable
end

local function createOptionFromSpec(optionSpec)
    local option = table.copy(optionSpec)
    option.configVariable = nil
    option.enabled = nil
    option.id = getOptionId(optionSpec)
    option.widgetname = widgetName
    option.value = getOptionValue(optionSpec)
    option.onchange = createOnChange(optionSpec)
    return option
end

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    FactoryQuotas = WG.Quotas
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end

    if WG['options'] ~= nil then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end

    initUnitDefs()
    counterType[COUNTER_TYPE_HORIZONTAL] = MasterFramework.HorizontalStack
    counterType[COUNTER_TYPE_VERTICAL] = MasterFramework.VerticalStack

    spectatorMode = Spring.GetSpectatingState()
    countersCache = {}

    lightBlack = MasterFramework:Color(0, 0, 0, 0.8)
    backgroundColor = MasterFramework:Color(0, 0, 0, 0.9)
    red = MasterFramework:Color(0.9, 0, 0, 1)
    green = MasterFramework:Color(0.4, 0.92, 0.4, 1)
    yellow = MasterFramework:Color(0.9, 0.9, 0, 1)
    white = MasterFramework:Color(0.92, 0.92, 0.92, 1)
    font = MasterFramework:Font("Exo2-SemiBold.otf", config.iconSize / 4)

    if isFactoryQuotasTrackerEnabled() then
        counterGroups[trackFactoryQuotasCounterGroup] = { type = COUNTER_TYPE_HORIZONTAL, counterDefinitions = {} }
    end
    for _, counterGroup in pairs(counterGroups) do
        counterGroup.contentStack = counterType[counterGroup.type](MasterFramework, {}, MasterFramework:Dimension(8), 1)
    end
end

function widget:GameFrame(frame)
    if frame % config.refreshFrequency == 0 then
        onFrame()
    end
end

function widget:Shutdown()
    for _, counterGroup in pairs(counterGroups) do
        MasterFramework:RemoveElement(counterGroup.key)
    end

    if WG['options'] ~= nil then
        WG['options'].removeOptions(table.map(OPTION_SPECS, getOptionId))
    end
end

function widget:GetConfigData()
    local result = {}
    for _, option in ipairs(OPTION_SPECS) do
        result[option.configVariable] = getOptionValue(option)
    end
    return result
end

function widget:SetConfigData(data)
    for _, option in ipairs(OPTION_SPECS) do
        local configVariable = option.configVariable
        if data[configVariable] ~= nil then
            setOptionValue(option, data[configVariable])
        end
    end
end
