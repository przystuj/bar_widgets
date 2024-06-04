local widgetName = "Context Select"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = [[
        Adds a select action which tries to select, in order:
        1. Units with relative hp (default <50%), in current selection. If selection didn't change, go to the next step.
        2. One builder, close to the cursor
        3. One skuttle/spybot, close to the cursor
        4. All radar and jammers, close to the cursor
        5. Otherwise - select single unit close to the cursor and select its group or all visible units of its type
        ]],
        author = "SuperKitowiec",
        version = 1.1,
        layer = 0,
        enabled = true
    }
end

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

function SmartSelect()
    local clearSelection = true
    for _, unitId in ipairs(GetSelectedUnits()) do
        local health, maxHealth = Spring.GetUnitHealth(unitId)
        local healthPercent = health / maxHealth * 100

        if (config.selectDamaged and healthPercent > config.healthThreshold) or
                (not config.selectDamaged and healthPercent <= config.healthThreshold) then
            clearSelection = false
        end

    end

    if clearSelection then
        Spring.SelectUnitArray({})
    end

    SendCommands("select PrevSelection+_Not_Building_" .. relativeHealthQuery .. "+_ClearSelection_SelectAll+")

    if #GetSelectedUnits() == 0 then
        SendCommands("select FromMouse_200+_Buildoptions_Not_Building+_ClearSelection_SelectNum_1+")
        if #GetSelectedUnits() == 0 then
            SendCommands("select FromMouse_200+_IdMatches_" .. specialUnitsQuery .. "+_ClearSelection_SelectClosestToCursor+")
            if #GetSelectedUnits() == 0 then
                SendCommands("select FromMouse_400+_IdMatches_" .. radarsAndJammersQuery .. "+_ClearSelection_SelectAll+")
                if #GetSelectedUnits() == 0 then
                    SendCommands("select FromMouse_100+_Not_Building+_ClearSelection_SelectClosestToCursor+")
                    selectedUnits = GetSelectedUnits()
                    if #selectedUnits > 0 then
                        local unitGroup = Spring.GetUnitGroup(selectedUnits[1])
                        if unitGroup ~= nil then
                            SendCommands("group " .. Spring.GetUnitGroup(selectedUnits[1]))
                        else
                            SendCommands("select Visible+_InPrevSel+_ClearSelection_SelectAll+")
                        end
                    end
                end
            end
        end
    end
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