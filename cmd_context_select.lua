local widgetName = "Context Select"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = [[
        Adds a select action which tries to select units depending on cursor location.
        If cursor is almost directly next to the unit it will select all units from the same group.
        If unit is not in group it will select all visible units of this type.
        Otherwise, it will select units close to the cursor. If selection didn't change it will go to the next step:
        1. Units with relative hp (default <50%).
        2. One builder. Repeating will cycle the builders in range.
        3. One skuttle/spybot, close to the cursor
        4. All radar and jammers, close to the cursor
        5. Otherwise:
         - If nothing could be selected in previous steps - cycle your labs across the whole map.
         - If something could be selected in previous steps - select all units from the selected group/all visible units of selected type
           (this one is mostly used for cycling between damaged units and their group)
        ]],
        author = "SuperKitowiec",
        version = 1.3,
        layer = 0,
        enabled = true
    }
end

local debugMode = false

local config = {
    healthThreshold = 50,
    selectDamaged = true,
}

local OPTION_SPECS = {
    {
        configVariable = "healthThreshold",
        name = "Select health",
        description = "Will select units with this health %",
        type = "slider",
        min = 0,
        max = 100,
        step = 1,
        value = 50,
    },
    {
        configVariable = "selectDamaged",
        name = "Select damaged",
        description = "If true, will select units below 'Select health'. If false, will select units above 'Select health'",
        type = "bool",
        value = true,
    }
}

local GetSelectedUnits = Spring.GetSelectedUnits
local SendCommands = Spring.SendCommands

local specialUnitNames = {
    armspy = true, -- arm spybot
    corspy = true, -- cor spybot
    corsktl = true, -- cor skuttle
}

local radarAndJammerNames = {
    armaser = true, -- arm bot jammer
    armmark = true, -- arm bot radar
    corspec = true, -- cor bot jammer
    corvoyr = true, -- cor bot radar
    armseer = true, -- arm veh radar
    armjam = true, -- arm veh jammer
    corvrad = true, -- cor veh radar
    coreter = true, -- cor veh jammer
    armpeep = true, -- arm t1 airscout
    armsehak = true, -- arm seaplane scout
    armawac = true, -- arm t2 airscout
    corawac = true, -- cor t2 airscout
    corfink = true, -- cor t1 airscout
    corhunt = true, -- cor seaplane scout
}

local specialUnitsQuery, radarsAndJammersQuery, relativeHealthQuery;

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
    if debugMode then
        Spring.SendCommands(string.format("say a:%s", dump(message)))
    end
end

local function tableKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
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
    relativeHealthQuery = config.selectDamaged
            and "Not_RelativeHealth_" .. config.healthThreshold
            or "RelativeHealth_" .. config.healthThreshold
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
    return "cmd_context_select_" .. optionSpec.configVariable
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

local function setsEqual(set1, set2)
    if #set1 ~= #set2 then
        return false
    end

    local setMap = {}
    for _, value in ipairs(set1) do
        setMap[value] = (setMap[value] or 0) + 1
    end

    for _, value in ipairs(set2) do
        if not setMap[value] or setMap[value] == 0 then
            return false
        end
        setMap[value] = setMap[value] - 1
    end

    for _, count in pairs(setMap) do
        if count ~= 0 then
            return false
        end
    end

    return true
end

local selectedUnits = {}
local cycleBuildings;
local function sendCommand(command, message)
    SendCommands(command)
    local newSelectedUnits = GetSelectedUnits();
    local selectionNotChanged = setsEqual(selectedUnits, newSelectedUnits)
    local isInvalidSelection = #newSelectedUnits == 0 or selectionNotChanged

    if not isInvalidSelection and message ~= nil and debugMode then
        debug(message)
    end

    if selectionNotChanged and #newSelectedUnits > 0 and #selectedUnits == 0 and debugMode then
        debug("Selection didn't change - trying the next step...")
    end

    if #newSelectedUnits > 0 then
        cycleBuildings = false
    end

    return isInvalidSelection
end

local function getBiggestUnitGroup(currentUnits)
    local unitGroups = {}
    local result
    local currentMax = -1
    for _, unitId in ipairs(currentUnits) do
        local unitGroup = Spring.GetUnitGroup(unitId)
        if unitGroup ~= nil then
            if unitGroups[unitGroup] == nil then
                unitGroups[unitGroup] = 1
            else
                unitGroups[unitGroup] = unitGroups[unitGroup] + 1
            end
        end
    end

    for groupId, count in pairs(unitGroups) do
        if count > currentMax then
            currentMax = count
            result = groupId
        end
    end

    return result
end

local function SmartSelect()
    cycleBuildings = true
    selectedUnits = GetSelectedUnits()

    sendCommand("select FromMouseC_35+_Not_Building+_ClearSelection_SelectClosestToCursor+")
    local newSelectedUnits = GetSelectedUnits()
    if #newSelectedUnits > 0 then
        local unitGroup = Spring.GetUnitGroup(newSelectedUnits[1])
        if unitGroup ~= nil then
            sendCommand("group " .. Spring.GetUnitGroup(newSelectedUnits[1]), "Selecting all units in the group")
        else
            sendCommand("select Visible+_InPrevSel+_ClearSelection_SelectAll+", "Selecting visible units of this type")
        end
    else
        if sendCommand("select FromMouseC_400+_Not_Building_" .. relativeHealthQuery .. "+_ClearSelection_SelectAll+", "Selecting units with relative hp (default <50%)") then
            if sendCommand("select FromMouseC_400+_Buildoptions_Not_Building+_ClearSelection_SelectNum_1+", "Cycling through nearby builders...") then
                if sendCommand("select FromMouseC_200+_IdMatches_" .. specialUnitsQuery .. "+_ClearSelection_SelectClosestToCursor+", "Selecting single spybot or skuttle") then
                    if sendCommand("select FromMouseC_400+_IdMatches_" .. radarsAndJammersQuery .. "+_ClearSelection_SelectAll+", "Selecting nearby radars and jammers") then
                        if cycleBuildings then
                            sendCommand("select AllMap+_Buildoptions_Building+_ClearSelection_SelectNum_1+", "Cycling through labs across the map...")
                        else
                            debug("Cycling relative hp units...")
                            if #selectedUnits > 0 then
                                local unitGroup = getBiggestUnitGroup(selectedUnits)
                                Spring.SelectUnitArray(selectedUnits)
                                if unitGroup ~= nil then
                                    debug("Selecting all units in group " .. unitGroup)
                                    SendCommands("group " .. unitGroup)
                                else
                                    debug("Selecting visible units of this type")
                                    SendCommands("select Visible+_InPrevSel+_ClearSelection_SelectAll+")
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function widget:Initialize()
    if WG['options'] ~= nil then
        WG['options'].addOptions(table.map(OPTION_SPECS, createOptionFromSpec))
    end

    specialUnitsQuery = table.concat(tableKeys(specialUnitNames), "_IdMatches_")
    radarsAndJammersQuery = table.concat(tableKeys(radarAndJammerNames), "_IdMatches_")
    relativeHealthQuery = config.selectDamaged
            and "Not_RelativeHealth_" .. config.healthThreshold
            or "RelativeHealth_" .. config.healthThreshold
    widgetHandler:AddAction("context_select", SmartSelect, nil, 'p')
end

function widget:Shutdown()
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