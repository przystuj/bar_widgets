local widget = widget ---@type

function widget:GetInfo()
    return {
        name = "Pick Build Ghost",
        desc = "Adds a command to prioritize a building from the queue.",
        author = "SuperKitowiec",
        date = "August 26, 2025",
        license = "GNU GPL, v2 or later",
        version = 1,
        layer = 0,
        enabled = true,
        handler = true,
    }
end

--------------------------------------------------------------------------------
-- Spring API Imports
--------------------------------------------------------------------------------

local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitTeam = Spring.GetUnitTeam
local spGetUnitCommands = Spring.GetUnitCommands
local spGetUnitCommandCount = Spring.GetUnitCommandCount
local spGetUnitPosition = Spring.GetUnitPosition
local spGetGroundHeight = Spring.GetGroundHeight
local spGetSelectedUnits = Spring.GetSelectedUnits
local spGiveOrderToUnit = Spring.GiveOrderToUnit
local spTraceScreenRay = Spring.TraceScreenRay
local spGetMouseState = Spring.GetMouseState
local spEcho = Spring.Echo
local spGetActiveCommand = Spring.GetActiveCommand
local spGetSpectatingState = Spring.GetSpectatingState
local spPlaySoundFile = Spring.PlaySoundFile
local I18N = Spring.I18N

--------------------------------------------------------------------------------
-- Command Definition & Constants
--------------------------------------------------------------------------------

local CMD_PRIORITIZE_GHOST = 455650 -- Unique Command ID
local CMD_PRIORITIZE_GHOST_DEFINITION = {
    id = CMD_PRIORITIZE_GHOST,
    type = CMDTYPE.ICON_MAP,
    name = 'Prioritize Ghost',
    cursor = 'cursorrepair',
    action = 'prioritize_ghost',
    tooltip = 'Select a build ghost to prioritize. One builder will build it, others will guard.',
    params = {},
}

local HIGHLIGHT_LINE_WIDTH = 3
local HIGHLIGHT_ALPHA = 0.9
local COLORS = {
    green = { 0.2, 1.0, 0.2, HIGHLIGHT_ALPHA },
    yellow = { 1.0, 1.0, 0.2, HIGHLIGHT_ALPHA },
    red = { 1.0, 0.2, 0.2, HIGHLIGHT_ALPHA },
}
local MAX_QUEUE_DEPTH = 2000
local font = gl.LoadFont("fonts/Exo2-SemiBold.otf", 24, 8, 10)

--------------------------------------------------------------------------------
-- Widget State
--------------------------------------------------------------------------------

-- State for ghost tracking
local command = {}
local builderCommands = {}
local createdUnitLocDefID = {}
local createdUnitID = {}
local newBuildCmdUnits = {}
local isBuilder = {}

-- Caches
local builderBuildOptions = {}

--------------------------------------------------------------------------------
-- Ghost Tracking Logic (stolen from gfx_showbuilderqueue for now)
--------------------------------------------------------------------------------

local floor = math.floor

local function clearbuilderCommands(unitID)
    if builderCommands[unitID] then
        for id, _ in pairs(builderCommands[unitID]) do
            if command[id] and command[id][unitID] then
                command[id][unitID] = nil
                command[id].builders = command[id].builders - 1
                if command[id].builders == 0 then
                    command[id] = nil
                end
            end
        end
        builderCommands[unitID] = nil
    end
end

local function checkBuilder(unitID)
    clearbuilderCommands(unitID)
    local queueDepth = spGetUnitCommandCount(unitID)
    if queueDepth and queueDepth > 0 then
        local queue = spGetUnitCommands(unitID, math.min(queueDepth, MAX_QUEUE_DEPTH))
        for i = 1, #queue do
            local cmd = queue[i]
            if cmd.id < 0 then
                local myCmd = { id = cmd.id, teamid = spGetUnitTeam(unitID), params = cmd.params }
                local id = math.abs(cmd.id) .. '_' .. floor(cmd.params[1]) .. '_' .. floor(cmd.params[3])
                if createdUnitLocDefID[id] == nil then
                    if command[id] == nil then command[id] = { id = myCmd, builders = 0 } end
                    if not command[id][unitID] then
                        command[id][unitID] = true
                        command[id].builders = command[id].builders + 1
                    end
                    if builderCommands[unitID] == nil then builderCommands[unitID] = {} end
                    builderCommands[unitID][id] = true
                end
            end
        end
    end
end

local function clearUnit(unitID)
    if createdUnitID[unitID] then
        local udefLocID = createdUnitID[unitID]
        command[udefLocID] = nil
        createdUnitLocDefID[udefLocID] = nil
        createdUnitID[unitID] = nil
    end
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

--------------------------------------------------------------------------------
-- UI & Interaction Logic
--------------------------------------------------------------------------------

local function CacheDefs()
    for udefID, udef in ipairs(UnitDefs) do
        if udef.isBuilder and not udef.isFactory and udef.buildOptions and udef.buildOptions[1] then
            isBuilder[udefID] = true
            local buildSet = {}
            for i = 1, #udef.buildOptions do buildSet[udef.buildOptions[i]] = true end
            builderBuildOptions[udefID] = buildSet
        end
    end
end

local function CanBuilderBuild(builderDefID, targetUnitDefID)
    return builderBuildOptions[builderDefID] and builderBuildOptions[builderDefID][targetUnitDefID]
end

local function FindTargetedShapeAtPos(groundPos)
    if not groundPos then return nil end
    local gx, _, gz = groundPos[1], groundPos[2], groundPos[3]

    for id, cmdData in pairs(command) do
        if cmdData.id and cmdData.id.params then
            local udef = UnitDefs[math.abs(cmdData.id.id)]
            if udef then
                local px, pz = cmdData.id.params[1], cmdData.id.params[3]
                local footprintX, footprintZ = udef.xsize * 4, udef.zsize * 4
                if (gx > px - footprintX and gx < px + footprintX and gz > pz - footprintZ and gz < pz + footprintZ) then
                    return id
                end
            end
        end
    end
    return nil
end

local function GetHoverInfo()
    local _, cmd, _ = spGetActiveCommand()
    if cmd ~= CMD_PRIORITIZE_GHOST then return nil end

    local mx, my = spGetMouseState()
    local _, groundPos = spTraceScreenRay(mx, my, true)
    local shapeID = FindTargetedShapeAtPos(groundPos)
    if not shapeID then return nil, "red", nil end

    local selectedUnits = spGetSelectedUnits()
    local canBuildCount, cannotBuildCount, hasBuilders = 0, 0, false
    local targetUnitDefID = tonumber(shapeID:match("^(%d+)_"))

    for i = 1, #selectedUnits do
        local unitDefID = spGetUnitDefID(selectedUnits[i])
        if builderBuildOptions[unitDefID] then
            hasBuilders = true
            if CanBuilderBuild(unitDefID, targetUnitDefID) then
                canBuildCount = canBuildCount + 1
            else
                cannotBuildCount = cannotBuildCount + 1
            end
        end
    end

    local colorName
    if not hasBuilders or (canBuildCount == 0 and cannotBuildCount > 0) then
        colorName = "red"
    elseif canBuildCount > 0 and cannotBuildCount == 0 then
        colorName = "green"
    elseif canBuildCount > 0 and cannotBuildCount > 0 then
        colorName = "yellow"
    else
        colorName = "red"
    end
    return shapeID, colorName
end


--------------------------------------------------------------------------------
-- Widget Callins
--------------------------------------------------------------------------------

function widget:Initialize()
    CacheDefs()
    for i = 1, #Spring.GetAllUnits() do
        local unitID = Spring.GetAllUnits()[i]
        if isBuilder[spGetUnitDefID(unitID)] then checkBuilder(unitID) end
    end
    I18N.load({
        en = {
            ["ui.orderMenu.prioritize_ghost"] = CMD_PRIORITIZE_GHOST_DEFINITION.name,
            ["ui.orderMenu.prioritize_ghost_tooltip"] = CMD_PRIORITIZE_GHOST_DEFINITION.tooltip,
            ["ui.orderMenu.prioritize_ghost_no_target"] = "No valid ghost selected",
            ["ui.orderMenu.prioritize_ghost_prioritize"] = "Prioritize:"
        }
    })
end

function widget:CommandsChanged()
    if spGetSpectatingState() then return end
    local selectedUnits = spGetSelectedUnits()
    if #selectedUnits == 0 then return end

    local hasBuilder = false
    for i = 1, #selectedUnits do
        if isBuilder[spGetUnitDefID(selectedUnits[i])] then
            hasBuilder = true
            break
        end
    end

    if hasBuilder then
        widgetHandler.customCommands[#widgetHandler.customCommands + 1] = CMD_PRIORITIZE_GHOST_DEFINITION
    end
end

function widget:CommandNotify(cmdID, cmdParams)
    if cmdID ~= CMD_PRIORITIZE_GHOST then return false end

    local shapeID = FindTargetedShapeAtPos(cmdParams)
    if not shapeID then return true end

    local targetUnitDefID_positive = tonumber(shapeID:match("^(%d+)_"))

    local buildersWhoCan = {}
    for _, unitID in ipairs(spGetSelectedUnits()) do
        if CanBuilderBuild(spGetUnitDefID(unitID), targetUnitDefID_positive) then
            table.insert(buildersWhoCan, unitID)
        end
    end

    if #buildersWhoCan == 0 then
        spPlaySoundFile("beep4", 1, 'ui')
        return true
    end

    local cmdToExecute = command[shapeID].id
    local mainBuilder = buildersWhoCan[1]
    spGiveOrderToUnit(mainBuilder, cmdToExecute.id, cmdToExecute.params, {})

    for i = 2, #buildersWhoCan do
        spGiveOrderToUnit(buildersWhoCan[i], CMD.GUARD, { mainBuilder }, { "" })
    end
    spEcho(string.format("Prioritizing build of %s.", UnitDefs[targetUnitDefID_positive].translatedHumanName))
    return false -- Command successfully executed and consumed
end

local sec, lastUpdate, checkCount = 0, 0, 1
function widget:Update(dt)
    sec = sec + dt
    if sec > lastUpdate + 0.12 then
        lastUpdate = sec
        checkCount = checkCount + 1
        for unitID, _ in pairs(builderCommands) do
            if (unitID + checkCount) % 30 == 1 and not newBuildCmdUnits[unitID] then
                checkBuilder(unitID)
            end
        end

        local clock = os.clock()
        for unitID, cmdClock in pairs(newBuildCmdUnits) do
            if clock > cmdClock then
                checkBuilder(unitID)
                newBuildCmdUnits[unitID] = nil
            end
        end
    end
end

function widget:DrawWorld()
    local shapeID, colorName = GetHoverInfo()
    if not shapeID then return end

    local cmdData = command[shapeID]
    if not cmdData or not cmdData.id then return end

    local cmd = cmdData.id
    local px, pz = cmd.params[1], cmd.params[3]
    local groundHeight = spGetGroundHeight(px, pz)
    local udef = UnitDefs[math.abs(cmd.id)]
    local radius = (udef.xsize + udef.zsize) * 2.5

    local r, g, b, a = unpack(COLORS[colorName])
    gl.Color(r, g, b, a)
    gl.LineWidth(HIGHLIGHT_LINE_WIDTH)

    gl.BeginEnd(GL.LINE_LOOP, function()
        for i = 0, 32 do
            local angle = i / 32 * 2 * math.pi
            gl.Vertex(px + math.cos(angle) * radius, groundHeight + 1, pz + math.sin(angle) * radius)
        end
    end)
    gl.LineWidth(1)
end

function widget:DrawScreen()
    local shapeID, colorName = GetHoverInfo()
    if not shapeID then return end

    local mouseX, mouseY = spGetMouseState()
    local textY = mouseY + 40

    font:Begin()
    font:SetOutlineColor({ 0, 0, 0, 1 })
    font:SetTextColor(unpack(COLORS[colorName]))

    if colorName == "red" then
        font:Print(I18N("ui.orderMenu.prioritize_ghost_no_target"), mouseX, textY, 24, "con")
    else
        local udef = UnitDefs[tonumber(shapeID:match("^(%d+)_"))]
        font:Print(I18N("ui.orderMenu.prioritize_ghost_prioritize"), mouseX, textY + 30, 24, "con")
        font:Print(udef.translatedHumanName, mouseX, textY, 24, "con")
    end
    font:End()
end

function widget:UnitCommand(unitID, unitDefID)
    if isBuilder[unitDefID] then
        clearbuilderCommands(unitID)
        newBuildCmdUnits[unitID] = os.clock() + 0.13
    end
end

function widget:UnitCreated(unitID, unitDefID)
    local x, _, z = spGetUnitPosition(unitID)
    if x then
        local udefLocID = unitDefID .. '_' .. floor(x) .. '_' .. floor(z)
        command[udefLocID] = nil
        createdUnitLocDefID[udefLocID] = unitID
        createdUnitID[unitID] = udefLocID
    end
end

function widget:UnitFinished(unitID) clearUnit(unitID) end
function widget:UnitDestroyed(unitID, unitDefID)
    if isBuilder[unitDefID] then
        newBuildCmdUnits[unitID] = nil
        clearbuilderCommands(unitID)
    end
    clearUnit(unitID)
end
