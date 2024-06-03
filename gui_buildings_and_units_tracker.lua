local widgetName = "Buildings/Units Tracker"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Shows counters for chosen units/buildings. Pinpointers, nukes and junos are displayed by default. Click icon to select one, shift click to select all. Edit counterGroups to add counters for different units",
        author = "SuperKitowiec",
        version = 0.5,
        license = "GNU GPL, v2 or later",
        layer = 0
    }
end

--[[
Each counterGroup is a separate draggable window with own counterDefinitions.counterDefinitions.counterDefinitions.
In this case, counter group "buildings" will show pinpointers, nukes and junos and group "units" will show transports.
You can add own groups and definitions, just make sure that their ids are unique. You can make each group vertical or horizontal

Counter definition params:
id = unique identifier of the counter
alwaysVisible = if false, counter is displayed only if value is > 0
teamWide = if true, it counts across the whole team
unitNames = list of unit names. You can find them in url of this site https://www.beyondallreason.info/unit/armflea. For example Tick's name is armflea
counterType = COUNTER_TYPE_BASIC or COUNTER_TYPE_STOCKPILE. Basic is just a number of units/buildings. Stockpile shows current stockpile of missiles instead
greenThreshold (optional, only for COUNTER_TYPE_BASIC) = if counter is below greenThreshold the text will be yellow.
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
            }
        }
    },
    groundBuilders = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "t1cons",
                alwaysVisible = true,
                teamWide = false,
                unitNames = {  corck = true, armcv = true, corcv = true, cormuskrat = true, armbeaver = true, armcs = true, corcs = true, corch = true, armch = true},
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armck"
            },
            {
                id = "t2cons",
                alwaysVisible = true,
                teamWide = false,
                unitNames = { armack = true, corack = true, armacv = true, coracv = true, armacsub = true, coracsub = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armack"
            }
        }
    },
}

local config = {
    iconSize = 50,
    refreshFrequency = 5,
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
    }
}

local MasterFramework
local requiredFrameworkVersion = 42
local countersCache
local red, green, yellow, white, backgroundColor, font
local spectatorMode

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

local function callUpdate(counterDef)
    if countersCache[counterDef.id] then
        countersCache[counterDef.id]:update(counterDef.data)
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

local function UnitCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end
    local unitsToSelect = {}
    local currentColor = MasterFramework:Color(1, 1, 1, 1)
    local counterText = MasterFramework:Text("", currentColor, font)
    local counter = MasterFramework:VerticalStack(
            {
                MasterFramework:Button(UnitIcon(counterDef), function()
                    local _, _, _, shift = Spring.GetModKeyState()
                    Spring.SelectUnitArray(shift and unitsToSelect or { unitsToSelect[1] }, false)
                end)
            , counterText },
            MasterFramework:Dimension(8), 1
    )

    function counter:update(units)
        unitsToSelect = units
        local unitCount = #units
        local newColor
        if unitCount == 0 then
            newColor = red
        elseif greenThreshold and unitCount < greenThreshold then
            newColor = yellow
        else
            newColor = green
        end

        counterText:SetString(string.format("%d", unitCount))
        applyColor(currentColor, newColor)
    end

    countersCache[counterDef.id] = counter
    return counter
end

local function UnitWithStockpileCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end
    local unitsToSelect = {}
    local stockpileColor = MasterFramework:Color(1, 0, 0, 1)
    local stockpileText = MasterFramework:Text("", stockpileColor, font)
    local buildPercentText = MasterFramework:Text("", white, font)

    local counter = MasterFramework:VerticalStack(
            {
                MasterFramework:Button(UnitIcon(counterDef), function()
                    local _, _, _, shift = Spring.GetModKeyState()

                    if not shift then
                        unitsToSelect = { unitsToSelect[1] }
                    end
                    Spring.SelectUnitArray(unitsToSelect, shift)
                end),
                MasterFramework:HorizontalStack({ buildPercentText, stockpileText, }, MasterFramework:Dimension(6), 1)
            },
            MasterFramework:Dimension(8), 1
    )

    function counter:update(units)
        if #units == 0 then
            stockpileText:SetString("")
            buildPercentText:SetString("")
            return
        end

        local stockpile = 0
        local maxStockpilePercent = 0
        local stockpileSlotsLeft = 0
        local color
        unitsToSelect = {}

        for _, unitId in ipairs(units) do
            local unitStockpile, unitStockpileSlotsLeft, unitBuildPercent = Spring.GetUnitStockpile(unitId)
            if unitStockpile > 0 then
                table.insert(unitsToSelect, unitId)
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
local function onFrame()
    for _, counterGroup in pairs(counterGroups) do
        counterGroup.contentStack.members = {}
    end

    local playerId, teamIds = updateTeamIds()

    for _, counterGroup in pairs(counterGroups) do
        for _, counterDef in ipairs(counterGroup.counterDefinitions) do
            if not counterDef.skipWhenSpectating or not spectatorMode then
                local playerIdsToSearch = counterDef.teamWide and teamIds or playerId
                local units = findUnits(playerIdsToSearch, counterDef.unitDefs)
                counterDef.data = units
                if hasData(counterDef) or counterDef.alwaysVisible or spectatorMode then
                    table.insert(counterGroup.contentStack.members, counterType[counterDef.counterType](counterDef))
                end
                callUpdate(counterDef)
            end
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
        font = MasterFramework:Font("Exo2-SemiBold.otf", config.iconSize / 4.8)
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

    backgroundColor = MasterFramework:Color(0, 0, 0, 0.9)
    red = MasterFramework:Color(1, 0, 0, 1)
    green = MasterFramework:Color(0, 1, 0, 1)
    yellow = MasterFramework:Color(1, 1, 0, 1)
    white = MasterFramework:Color(1, 1, 1, 1)
    font = MasterFramework:Font("Exo2-SemiBold.otf", config.iconSize / 4.8)

    for counterGroupId, counterGroup in pairs(counterGroups) do
        local frameId = widgetName .. counterGroupId

        counterGroup.contentStack = counterType[counterGroup.type](MasterFramework, {}, MasterFramework:Dimension(8), 1)
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