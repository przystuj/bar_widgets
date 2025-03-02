local widgetName = "Buildings/Units Tracker"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Shows counters for chosen units/buildings. Pinpointers, nukes and junos are displayed by default. Click icon to select one, shift click to select all. Edit counterGroups to add counters for different units. Select unit and toggle Track to track its health",
        author = "SuperKitowiec",
        version = "0.14",
        license = "GNU GPL, v2 or later",
        layer = 1, -- has to be higher than unit_factory_quota.lua
        handler = true
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
isGrouped = if true then each entry from unitNames will be displayed as a separate tracker
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
    airUnits = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "airUnits",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armca = true, corca = true, corcsa = true, armcsa = true, armaca = true, coraca = true,
                              armatlas = true, armdfly = true, corvalk = true, corseah = true, armpeep = true,
                              armsehak = true, armawac = true, corfink = true, corhunt = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
        }
    },
    groundCons = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "groundCons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armck = true, corck = true, armcv = true, corcv = true, cormuskrat = true, armbeaver = true,
                    armcs = true, corcs = true, corch = true, armch = true, armack = true, corack = true,
                    armacv = true, coracv = true, armacsub = true, coracsub = true, armfark = true, armconsul = true,
                    corfast = true, armrectr = true, cornecro = true, },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
        }
    },
    labs = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "labs",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armsy = true, armlab = true, armvp = true, armap = true, armfhp = true, armhp = true,
                    armamsub = true, armplat = true, corsy = true, corlab = true, corvp = true, corap = true,
                    corfhp = true, corhp = true, coramsub = true, corplat = true, armalab = true, armavp = true,
                    armaap = true, armfhp = true, armasy = true, coravp = true, coralab = true, corasy = true,
                    coraap = true, armshltxuw = true, armshltx = true, corgant = true, corgantuw = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
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

local CMD_TOGGLE_UNIT_TRACKING = 455625

local counterGroupsConfig
local configFile = loadfile("LuaUI/config/BuildingsAndUnitsTracker.lua")
if configFile then
    local tmp = {}
    setfenv(configFile, tmp)
    counterGroupsConfig = configFile()
end

local requiredFrameworkVersion = 43
local countersCache, font, MasterFramework, FactoryQuotas
local red, green, yellow, white, backgroundColor, lightBlack
local spectatorMode
local trackFactoryQuotasCounterGroup = "trackFactoryQuotasCounterGroup"
local trackedUnitIds = {}
local trackUnitCounterGroup = "trackUnitCounterGroup"
local COUNTER_TYPE_FACTORY_QUOTA, COUNTER_TYPE_HEALTH = "counterQuota", "counterHealth"

-- Functions
local function deepCopy(obj, seen)
    if type(obj) ~= "table" then
        return obj
    end

    if seen and seen[obj] then
        return seen[obj]
    end

    local copy = {}
    seen = seen or {}
    seen[obj] = copy

    for k, v in pairs(obj) do
        copy[deepCopy(k, seen)] = deepCopy(v, seen)
    end

    return setmetatable(copy, getmetatable(obj))
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
    return MasterFramework:Background(
            MasterFramework:Rect(
                    MasterFramework:AutoScalingDimension(config.iconSize),
                    MasterFramework:AutoScalingDimension(config.iconSize)
            ),
            { MasterFramework:Image("#" .. (counterDef.icon ~= nil and counterDef.icon or counterDef.unitDefs[1])) },
            MasterFramework:AutoScalingDimension(5)
    )
end

local function TextWithBackground(text, textBackgroundColor)
    return MasterFramework:Background(
            MasterFramework:MarginAroundRect(text,
                    MasterFramework:AutoScalingDimension(5),
                    MasterFramework:AutoScalingDimension(1),
                    MasterFramework:AutoScalingDimension(3),
                    MasterFramework:AutoScalingDimension(2)
            ),
            { textBackgroundColor or lightBlack },
            MasterFramework:AutoScalingDimension(5)
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

local function TrackerButton(buttonParams, children)
    return MasterFramework:Button(
            MasterFramework:MarginAroundRect(
                    children,
                    MasterFramework:AutoScalingDimension(2),
                    MasterFramework:AutoScalingDimension(2),
                    MasterFramework:AutoScalingDimension(2),
                    MasterFramework:AutoScalingDimension(2)
            ),
            function()
                handleClick(buttonParams)
            end
    )
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

    local counter = TrackerButton(buttonParams,
            MasterFramework:StackInPlace({ UnitIcon(counterDef), TextWithBackground(counterText) }, 0.975, 0.025)
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
        counterText:SetBaseColor(newColor)
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
            TrackerButton(buttonParams,
                    MasterFramework:StackInPlace({
                        UnitIcon(counterDef),
                        TextWithBackground(counterText)
                    }, 0.975, 0.025)
            ),
            MasterFramework.events.mouseWheel, function(_, _, _, _, value)
                local alt, ctrl, meta, shift = Spring.GetModKeyState()
                local quotas = FactoryQuotas.getQuotas()
                local unitDefID = counterDef.unitDefs[1]
                local factoryID = counterDef.factoryID
                local multiplier = 1
                if ctrl then
                    multiplier = multiplier * 20
                end
                if shift then
                    multiplier = multiplier * 5
                end
                local minValue = 1
                if meta or quotas[factoryID][unitDefID] == 0 then
                    minValue = 0
                end
                local newAmount = math.max(minValue, quotas[factoryID][unitDefID] + (value * multiplier))
                quotas[factoryID][unitDefID] = newAmount
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
        counterText:SetBaseColor(newColor)
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

    local counter = TrackerButton(buttonParams,
            MasterFramework:StackInPlace({
                UnitIcon(counterDef),
                MasterFramework:VerticalStack({
                    TextWithBackground(stockpileText, textBackgroundColor),
                    TextWithBackground(buildPercentText, textBackgroundColor),
                }, MasterFramework:AutoScalingDimension(1), 1),
            }, 0.975, 0.025)
    )

    function counter:update(counterDef)
        if #counterDef.data == 0 then
            stockpileText:SetString("")
            buildPercentText:SetString("")
            textBackgroundColor:SetRawValues(0, 0, 0, 0)
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
        stockpileText:SetBaseColor(color)
        textBackgroundColor:SetRawValues(lightBlack:GetRawValues())
        if stockpileSlotsLeft == 0 then
            buildPercentText:SetString("max")
        else
            buildPercentText:SetString(string.format("%2d%%", maxStockpilePercent))
        end
    end

    countersCache[counterDef.id] = counter
    return counter
end

local function UnitHealthCounter(counterDef)
    if countersCache[counterDef.id] then
        return countersCache[counterDef.id]
    end

    local currentColor = MasterFramework:Color(1, 1, 1, 1)
    local counterText = MasterFramework:Text("", currentColor, font)
    local buttonParams = {
        unitsToSelect = {},
        currentSelectedUnitIndex = 0
    }

    local counter = TrackerButton(buttonParams,
            MasterFramework:StackInPlace({ UnitIcon(counterDef), TextWithBackground(counterText) }, 0.975, 0.025)
    )

    function counter:update(counterDef)
        buttonParams.unitsToSelect = { counterDef.unitId }
        local unitId = counterDef.unitId
        local unitHealth = 0
        local unitMaxHealth = 0

        if Spring.ValidUnitID(unitId) then
            -- Get current and max health
            unitHealth, unitMaxHealth = Spring.GetUnitHealth(unitId)
        end

        if not unitHealth or not unitMaxHealth or unitMaxHealth == 0 then
            -- Unit data couldn't be retrieved or unit is invalid
            counterText:SetString("N/A")
            counterText:SetBaseColor(red)
            return
        end

        -- Calculate health percentage
        local healthPercent = math.floor((unitHealth / unitMaxHealth) * 100)

        -- Determine color based on health percentage
        local newColor
        if healthPercent < 25 then
            newColor = red
        elseif healthPercent < counterDef.greenThreshold then
            newColor = yellow
        else
            newColor = green
        end

        counterText:SetString(string.format("%d%%", healthPercent))
        counterText:SetBaseColor(newColor)
    end

    countersCache[counterDef.id] = counter
    return counter
end

local counterType = {
    [COUNTER_TYPE_BASIC] = UnitCounter,
    [COUNTER_TYPE_STOCKPILE] = UnitWithStockpileCounter,
    [COUNTER_TYPE_FACTORY_QUOTA] = FactoryQuotaCounter,
    [COUNTER_TYPE_HEALTH] = UnitHealthCounter,
}

local function spreadGroupedUnitDefs()
    for _, counterGroup in pairs(counterGroups) do
        local indicesToRemove = {}
        for index, counterDefTemplate in ipairs(counterGroup.counterDefinitions) do
            if counterDefTemplate.isGrouped then
                table.insert(indicesToRemove, index)
                for unitName, _ in pairs(counterDefTemplate.unitNames) do
                    local counterDef = deepCopy(counterDefTemplate)
                    counterDef.id = counterDefTemplate.id .. unitName
                    counterDef.isGrouped = false
                    counterDef.unitNames = { [unitName] = true }
                    table.insert(counterGroup.counterDefinitions, counterDef)
                end
            end
        end
        for _, index in pairs(indicesToRemove) do
            table.remove(counterGroup.counterDefinitions, index)
        end
    end
end

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
                                MasterFramework:Background(
                                        MasterFramework:MarginAroundRect(
                                                counterGroup.contentStack,
                                                MasterFramework:AutoScalingDimension(1),
                                                MasterFramework:AutoScalingDimension(1),
                                                MasterFramework:AutoScalingDimension(1),
                                                MasterFramework:AutoScalingDimension(1)
                                        ),
                                        { backgroundColor },
                                        MasterFramework:AutoScalingDimension(5)
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
    if counterGroup.key ~= nil then
        MasterFramework:RemoveElement(counterGroup.key)
    end
end

local function isFactoryQuotasTrackerEnabled()
    return config.trackFactoryQuotas and FactoryQuotas
end

local function updateFactoryQuotas()
    if not FactoryQuotas then
        Spring.Echo("FactoryQuotas not found on updateFactoryQuotas")
    end
    if isFactoryQuotasTrackerEnabled() then
        local counterGroup = counterGroups[trackFactoryQuotasCounterGroup]
        counterGroup.counterDefinitions = {}
        for factoryID, factoryQuotas in pairs(FactoryQuotas.getQuotas()) do
            local isFactoryDead = Spring.GetUnitIsDead(factoryID)
            if isFactoryDead ~= nil and not isFactoryDead then
                for unitDefID, quota in pairs(factoryQuotas) do
                    if quota > 0 then
                        table.insert(counterGroup.counterDefinitions, {
                            id = trackFactoryQuotasCounterGroup .. factoryID .. unitDefID,
                            alwaysVisible = true,
                            teamWide = false,
                            unitDefs = { unitDefID },
                            counterType = COUNTER_TYPE_FACTORY_QUOTA,
                            greenThreshold = quota,
                            icon = unitDefID,
                            factoryID = factoryID
                        })
                    end
                end
            end
        end
    end
end

local function updateHealthTrackers()
    local counterGroup = counterGroups[trackUnitCounterGroup]
    counterGroup.counterDefinitions = {}

    if #trackedUnitIds == 0 then
        return
    end

    for _, unitId in ipairs(trackedUnitIds) do
        local isUnitDead = Spring.GetUnitIsDead(unitId)

        if isUnitDead ~= nil and not isUnitDead then
            local unitDefID = Spring.GetUnitDefID(unitId)
            if unitDefID then
                table.insert(counterGroup.counterDefinitions, {
                    id = trackUnitCounterGroup .. unitId,
                    alwaysVisible = true,
                    teamWide = false,
                    unitDefs = { },
                    counterType = COUNTER_TYPE_HEALTH,
                    greenThreshold = 75,
                    icon = unitDefID,
                    unitId = unitId,
                })
            end
        else
            for i, trackedId in ipairs(trackedUnitIds) do
                if trackedId == unitId then
                    table.remove(trackedUnitIds, i)
                    break
                end
            end
        end
    end
end

local function onFrame()
    updateFactoryQuotas()
    updateHealthTrackers()
    local playerId, teamIds = updateTeamIds()

    for counterGroupId, counterGroup in pairs(counterGroups) do
        local counterGroupIsVisible = false
        local newMembers = {}
        for _, counterDef in ipairs(counterGroup.counterDefinitions) do
            if not counterDef.skipWhenSpectating or not spectatorMode then
                local playerIdsToSearch = counterDef.teamWide and teamIds or playerId
                local units = findUnits(playerIdsToSearch, counterDef.unitDefs)
                counterDef.data = units
                if hasData(counterDef) or counterDef.alwaysVisible or spectatorMode then
                    table.insert(newMembers, counterType[counterDef.counterType](counterDef))
                    counterGroupIsVisible = true
                end
                callUpdate(counterDef)
            end
        end
        counterGroup.contentStack:SetMembers(newMembers)
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

local function ContentStack(type)
    return counterType[type](MasterFramework, {}, MasterFramework:AutoScalingDimension(0), 1)
end

local function applyOptions()
    if MasterFramework ~= nil then
        font = MasterFramework:Font("Exo2-SemiBold.otf", config.iconSize / 4)
    end
    if not isFactoryQuotasTrackerEnabled() then
        if MasterFramework ~= nil and counterGroups[trackFactoryQuotasCounterGroup] then
            MasterFramework:RemoveElement(counterGroups[trackFactoryQuotasCounterGroup].key)
        end
        counterGroups[trackFactoryQuotasCounterGroup] = nil
    end
    if isFactoryQuotasTrackerEnabled() and MasterFramework ~= nil then
        counterGroups[trackFactoryQuotasCounterGroup] = {
            key = widgetName .. trackFactoryQuotasCounterGroup,
            type = COUNTER_TYPE_HORIZONTAL,
            counterDefinitions = {},
            contentStack = ContentStack(COUNTER_TYPE_HORIZONTAL)
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
    FactoryQuotas = WG.Quotas
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end
    if not FactoryQuotas then
        Spring.Echo("FactoryQuotas not found on init")
    end

    if counterGroupsConfig then
        counterGroups = counterGroupsConfig
    end

    if WG['options'] ~= nil then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end

    spreadGroupedUnitDefs()
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

    counterGroups[trackFactoryQuotasCounterGroup] = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {},
        key = widgetName .. trackFactoryQuotasCounterGroup,
    }
    counterGroups[trackUnitCounterGroup] = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {},
        key = widgetName .. trackUnitCounterGroup,
    }
    for _, counterGroup in pairs(counterGroups) do
        counterGroup.contentStack = ContentStack(counterGroup.type)
    end

    Spring.I18N.load({
        en = {
            ["ui.orderMenu.toggle_unit_tracking"] = "Track",
            ["ui.orderMenu.toggle_unit_tracking_tooltip"] = "Adds a tracker for this unit.",
            ["ui.orderMenu.toggle_unit_tracking_disabled"] = "Not tracked",
            ["ui.orderMenu.toggle_unit_tracking_enabled"] = "Tracked",
        }
    })
end

function widget:GameFrame(frame)
    if frame % config.refreshFrequency == 0 then
        onFrame()
    end
end

function widget:Shutdown()
    for _, counterGroup in pairs(counterGroups) do
        if counterGroup.key ~= nil then
            MasterFramework:RemoveElement(counterGroup.key)
        end
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

local function addUnitToTracking(unitId)
    if not Spring.ValidUnitID(unitId) then
        return false
    end

    for _, trackedId in ipairs(trackedUnitIds) do
        if trackedId == unitId then
            return false
        end
    end

    table.insert(trackedUnitIds, unitId)
    return true
end

local function removeUnitFromTracking(unitId)
    for i, trackedId in ipairs(trackedUnitIds) do
        if trackedId == unitId then
            table.remove(trackedUnitIds, i)
            return true
        end
    end
    return false
end

function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CMD_TOGGLE_UNIT_TRACKING then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits ~= 1 then
            return true
        end

        local unitId = selectedUnits[1]
        local state = cmdParams[1]

        if state == 1 then
            addUnitToTracking(unitId)
        else
            removeUnitFromTracking(unitId)
        end

        return true
    end

    return false
end

function widget:CommandsChanged()
    if Spring.GetSpectatingState() then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 1 then
        local unitId = selectedUnits[1]
        local customCommands = widgetHandler.customCommands

        local isTracked = false
        for _, trackedId in ipairs(trackedUnitIds) do
            if unitId == trackedId then
                isTracked = true
                break
            end
        end

        local trackingCmd = {
            id = CMD_TOGGLE_UNIT_TRACKING,
            type = CMDTYPE.ICON_MODE,
            name = 'Tracking',
            action = 'toggle_unit_tracking',
            params = { isTracked and 1 or 0, 'toggle_unit_tracking_disabled', 'toggle_unit_tracking_enabled' }
        }
        customCommands[#customCommands + 1] = trackingCmd
    end
end