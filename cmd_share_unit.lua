function widget:GetInfo()
    return {
        name = "Share Unit Command",
        desc = "Adds a command which allows you to quickly share unit to other player. Just target the command on any allied unit and you will share to this player",
        author = "Stolen by SuperKitowiec from citrine",
        date = "2024",
        license = "GNU GPL, v2 or later",
        version = 2,
        layer = 0,
        enabled = true,
        handler = true,
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
local SpringI18N = Spring.I18N
local SpringGetSpectatingState = Spring.GetSpectatingState
local SpringWorldToScreenCoords = Spring.WorldToScreenCoords
local SpringPlaySoundFile = Spring.PlaySoundFile

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

local CMD_SHARE_UNIT_TO_TARGET = 455624
local CMD_SHARE_UNIT_TO_TARGET_DEFINITION = {
    id = CMD_SHARE_UNIT_TO_TARGET,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Share Unit To Target',
    cursor = 'settarget',
    action = 'quick_share_to_target',
}

local myTeamID = SpringGetMyTeamID()
local myAllyTeamID = SpringGetTeamAllyTeamID(myTeamID)

local function FindTeam(mx, my)
    local _, cUnitID = SpringTraceScreenRay(mx, my, true)
    local foundUnits = SpringGetUnitsInCylinder(cUnitID[1], cUnitID[3], 200)

    if #foundUnits < 1 then
        return nil
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
        return nil
    end

    local selectedTeam
    for unitTeamId, count in pairs(unitTeamCounters) do
        if selectedTeam == nil then
            selectedTeam = unitTeamId
        elseif count > unitTeamCounters[selectedTeam] then
            selectedTeam = unitTeamId
        end
    end
    return selectedTeam
end

function widget:CommandNotify(cmdID, cmdParams, cmdOpts)
    if cmdID == CMD_SHARE_UNIT_TO_TARGET then
        local targetTeamID = nil
        if #cmdParams ~= 1 and #cmdParams ~= 3  then
            return true
        elseif #cmdParams == 1 then
            -- click on unit
            local targetUnitID = cmdParams[1]
            targetTeamID = SpringGetUnitTeam(targetUnitID)
        elseif #cmdParams == 3 then
            -- click on the ground
            local mouseX, mouseY = SpringWorldToScreenCoords(cmdParams[1], cmdParams[2], cmdParams[3])
            targetTeamID = FindTeam(mouseX, mouseY)
        end

        if targetTeamID == nil or targetTeamID == myTeamID or SpringGetTeamAllyTeamID(targetTeamID) ~= myAllyTeamID then
            -- invalid target, don't do anything
            return true
        end

        SpringShareResources(targetTeamID, "units")
        SpringPlaySoundFile("beep4", 1, 'ui')
        return false
    end
end

local function QuickShareUnit()
    local selectedUnits = SpringGetSelectedUnits()
    if #selectedUnits < 1 then
        return
    end

    local mx, my, _, mmb, _, mouseOffScreen, cameraPanMode = SpringGetMouseState()
    if mouseOffScreen or mmb or cameraPanMode then
        return
    end

    local selectedTeam = FindTeam(mx, my)
    SpringShareResources(selectedTeam, "units")
    SpringPlaySoundFile("beep4", 1, 'ui')
end

function widget:CommandsChanged()
    if SpringGetSpectatingState() then
        return
    end

    local selectedUnits = SpringGetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = CMD_SHARE_UNIT_TO_TARGET_DEFINITION
    end
end

function widget:Initialize()
    widgetHandler.actionHandler:AddAction(self, "quick_share_near_cursor", QuickShareUnit, nil, 'p')
    SpringI18N.load({
        en = {
            ["ui.orderMenu.quick_share_to_target"] = "Share Unit",
            ["ui.orderMenu.quick_share_to_target_tooltip"] = "Share unit to target player.",
        }
    })
end