function widget:GetInfo()
    return {
        name = "Context Select",
        desc = [[
        Adds a select action which tries to select, in order:
        1. Units with <50% hp, in current selection
        2. One builder, close to the cursor
        3. One skuttle/spybot, close to the cursor
        4. All radar and jammers, close to the cursor
        5. All units with <50% hp, close to the cursor
        6. Otherwise - select single unit close to the cursor and select its group or all visible units of its type
        ]],
        author = "SuperKitowiec",
        version = 1.0,
        layer = 0,
        enabled = true
    }
end

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

local specialUnitsQuery, radarsAndJammersQuery;

local function tableKeys(tbl)
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

function widget:Initialize()
    specialUnitsQuery = table.concat(tableKeys(specialUnitNames), "_IdMatches_")
    radarsAndJammersQuery = table.concat(tableKeys(radarAndJammerNames), "_IdMatches_")
    widgetHandler:AddAction("context_select", SmartSelect, nil, 'p')
end

function SmartSelect()
    local selectedUnits = GetSelectedUnits()

    -- from current selection select units with less that 50% hp
    SendCommands("select PrevSelection+_Not_Building_Not_RelativeHealth_50+_ClearSelection_SelectAll+")

    if #GetSelectedUnits() == 0 then
        -- select 1 builder up to 300 units from mouse
        SendCommands("select FromMouse_300+_Buildoptions_Not_Building+_ClearSelection_SelectNum_1+")
        if #GetSelectedUnits() == 0 then
            -- select single special unit close to the cursor
            SendCommands("select FromMouse_200+_IdMatches_" .. specialUnitsQuery .. "+_ClearSelection_SelectClosestToCursor+")
            if #GetSelectedUnits() == 0 then
                -- select all jammers and radars close to the cursor
                SendCommands("select FromMouse_400+_IdMatches_" .. radarsAndJammersQuery .. "+_ClearSelection_SelectAll+")
                if #GetSelectedUnits() == 0 then
                    -- select low hp units close to the cursor
                    SendCommands("select FromMouse_800+_Not_Building_Not_RelativeHealth_50+_ClearSelection_SelectAll+")
                    if #GetSelectedUnits() == 0 then
                        -- select any unit close to the cursor
                        SendCommands("select FromMouse_100+_Not_Building+_ClearSelection_SelectClosestToCursor+")
                        selectedUnits = GetSelectedUnits()
                        if #selectedUnits > 0 then
                            local unitGroup = Spring.GetUnitGroup(selectedUnits[1])
                            if unitGroup ~= nil then
                                -- select whole group of selected unit
                                SendCommands("group " .. Spring.GetUnitGroup(selectedUnits[1]))
                            else
                                -- select all visible units of the same type
                                SendCommands("select Visible+_InPrevSel+_ClearSelection_SelectAll+")
                            end
                        end
                    end
                end
            end
        end
    end
end