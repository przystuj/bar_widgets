function widget:GetInfo()
    return {
        name = "Share Unit Command",
        desc = "Adds a command which allows you to quickly share unit to other player. Just target the command on any allied unit and you will share to this player",
        author = "Stolen by SuperKitowiec from citrine",
        date = "2024",
        license = "GNU GPL, v2 or later",
        version = 1,
        layer = 0,
        enabled = true,
    }
end

-- engine call optimizations
-- =========================
local SpringGetUnitsInCylinder = Spring.GetUnitsInCylinder
local SpringGetMouseState = Spring.GetMouseState
local SpringGetMyTeamID = Spring.GetMyTeamID
local SpringTraceScreenRay = Spring.TraceScreenRay
local SpringGetUnitTeam = Spring.GetUnitTeam
local SpringGetSelectedUnits = Spring.GetSelectedUnits
local SpringGetTeamAllyTeamID = Spring.GetTeamAllyTeamID
local SpringShareResources = Spring.ShareResources
local SpringGiveOrderToUnitArray = Spring.GiveOrderToUnitArray
local SpringSelectUnitArray = Spring.SelectUnitArray
local SpringI18N = Spring.I18N
local SpringGetSpectatingState = Spring.GetSpectatingState

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

local function tablelength(T)
    local count = 0
    for _ in pairs(T) do
        count = count + 1
    end
    return count
end

-- widget code
-- ===========
-- the command that a user can execute, params = { targetUnitID }
--local CMD_SHARE_UNIT_TO_TARGET = 455624
--local CMD_SHARE_UNIT_TO_TARGET_DEFINITION = {
--    id = CMD_SHARE_UNIT_TO_TARGET,
--    type = CMDTYPE.ICON_UNIT,
--    name = 'Share Unit To Target',
--    cursor = 'settarget',
--    action = 'shareunittotarget',
--}

local myTeamID = SpringGetMyTeamID()
local myAllyTeamID = SpringGetTeamAllyTeamID(myTeamID)

--function widget:CommandsChanged()
--    if SpringGetSpectatingState() then
--        return
--    end
--
--    local selectedUnits = SpringGetSelectedUnits()
--    if #selectedUnits > 0 then
--        local customCommands = widgetHandler.customCommands
--        customCommands[#customCommands + 1] = CMD_SHARE_UNIT_TO_TARGET_DEFINITION
--    end
--end
--
--function widget:UnitCmdDone(unitID, unitDefID, unitTeam, cmdID, cmdParams, cmdOpts, cmdTag)
--    if cmdID == CMD_SHARE_UNIT_TO_TARGET then
--        if #cmdParams < 1 then
--            return true
--        end
--        local targetUnitID = cmdParams[1]
--        local targetTeamID = SpringGetUnitTeam(targetUnitID)
--
--        if targetTeamID == myTeamID or SpringGetTeamAllyTeamID(targetTeamID) ~= myAllyTeamID then
--            -- invalid target, don't do anything
--            return true
--        end
--
--        SpringShareResources(targetTeamID, "units")
--        Spring.PlaySoundFile("beep4", 1, 'ui')
--        return false
--    end
--end

--function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
--    if cmdID == CMD_SHARE_UNIT_TO_TARGET then
--        if #cmdParams < 1 then
--            return true
--        end
--        local targetUnitID = cmdParams[1]
--        local targetTeamID = SpringGetUnitTeam(targetUnitID)
--
--        if targetTeamID == myTeamID or SpringGetTeamAllyTeamID(targetTeamID) ~= myAllyTeamID then
--            -- invalid target, don't do anything
--            return true
--        end
--
--        SpringShareResources(targetTeamID, "units")
--        Spring.PlaySoundFile("beep4", 1, 'ui')
--        return false
--    end
--end

local function ShareUnit()
    local selectedUnits = SpringGetSelectedUnits()
    if #selectedUnits < 1 then
        return
    end

    local mx, my, _, mmb, _, mouseOffScreen, cameraPanMode = SpringGetMouseState()
    if mouseOffScreen or mmb or cameraPanMode then
        return
    end

    local _, cUnitID = SpringTraceScreenRay(mx, my, true)
    local foundUnits = SpringGetUnitsInCylinder(cUnitID[1], cUnitID[3], 200)

    if #foundUnits < 1 then
        return
    end

    local unitTeamCounters = {}

    for _, unitId in ipairs(foundUnits) do
        local unitTeamId = SpringGetUnitTeam(unitId)
        if unitTeamId ~= myTeamID and SpringGetTeamAllyTeamID(unitTeamId) == myAllyTeamID then
            unitTeamId = tostring(unitTeamId)
            if unitTeamCounters[unitTeamId] == nil then
                unitTeamCounters[unitTeamId] = 1
            else
                unitTeamCounters[unitTeamId] = unitTeamCounters[unitTeamId] + 1
            end
        end
    end

    if tablelength(unitTeamCounters) < 1 then
        return
    end

    local selectedTeam
    for unitTeamId, count in pairs(unitTeamCounters) do
        if selectedTeam == nil then
            selectedTeam = unitTeamId
        elseif count > unitTeamCounters[selectedTeam] then
            selectedTeam = unitTeamId
        end
    end

    SpringShareResources(selectedTeam, "units")
    Spring.PlaySoundFile("beep4", 1, 'ui')
end

function widget:Initialize()
    widgetHandler:AddAction("shareunittotarget", ShareUnit, nil, 'p')
    --SpringI18N.load({
    --    en = {
    --        ["ui.orderMenu.shareunittotarget"] = "Share Unit",
    --        ["ui.orderMenu.shareunittotarget_tooltip"] = "Share unit to target player.",
    --    }
    --})
end
