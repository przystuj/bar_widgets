local widgetName = "Buildings Tracker"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Shows counters for pinpointers, nukes and junos. Click building icon to select one, shift click to select all",
        author = "SuperKitowiec",
        version = 0.4,
        license = "GNU GPL, v2 or later",
        layer = 0
    }
end

------------------------------------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = 42
local key, contentStack, countersCache
local red, green, yellow, white, backgroundColor
local spectatorMode
local pinpointersId, nukesId, junosId = "pinpointers", "nukes", "junos"

local nukeNames = {
    armsilo = true,
    corsilo = true,
}

local junoNames = {
    armjuno = true,
    corjuno = true,
}

local pinpointerNames = {
    armtarg = true,
    cortarg = true,
}

local junoDefIDs = {}
local pinpointerDefIDs = {}
local nukeDefIDs = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    if pinpointerNames[unitDef.name] then
        table.insert(pinpointerDefIDs, unitDefID)
    end
    if junoNames[unitDef.name] then
        table.insert(junoDefIDs, unitDefID)
    end
    if nukeNames[unitDef.name] then
        table.insert(nukeDefIDs, unitDefID)
    end
end

local iconSize = 50

local function applyColor(currentColor, newColor)
    currentColor.r = newColor.r
    currentColor.g = newColor.g
    currentColor.b = newColor.b
    currentColor.a = newColor.a
end

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end

    spectatorMode = Spring.GetSpectatingState()
    countersCache = {}

    backgroundColor = MasterFramework:Color(0, 0, 0, 0.6)
    red = MasterFramework:Color(1, 0, 0, 1)
    green = MasterFramework:Color(0, 1, 0, 1)
    yellow = MasterFramework:Color(1, 1, 0, 1)
    white = MasterFramework:Color(1, 1, 1, 1)

    contentStack = MasterFramework:HorizontalStack({}, MasterFramework:Dimension(8), 1)

    key = MasterFramework:InsertElement(
            MasterFramework:MovableFrame(
                    widgetName,
                    MasterFramework:PrimaryFrame(
                            MasterFramework:MarginAroundRect(
                                    contentStack,
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
            widgetName,
            MasterFramework.layerRequest.bottom()
    )
end

local function UnitCounter(id, greenThreshold)
    if countersCache[id] then
        return countersCache[id]
    end
    local currentColor = MasterFramework:Color(1, 1, 1, 1)
    local counterText = MasterFramework:Text("", currentColor)
    local counter = MasterFramework:VerticalStack({
        MasterFramework:Rect(
                MasterFramework:Dimension(iconSize),
                MasterFramework:Dimension(iconSize),
                MasterFramework:Dimension(3),
                { MasterFramework:Image("#" .. pinpointerDefIDs[1]) }
        ),
        counterText },
            MasterFramework:Dimension(8),
            1
    )

    function counter:Update(unitCount)
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

    countersCache[id] = counter
    return counter
end

local function UnitWithStockpileCounter(id, icon)
    if countersCache[id] then
        return countersCache[id]
    end
    local unitsToSelect = {}
    local stockpileColor = MasterFramework:Color(1, 0, 0, 1)
    local stockpileText = MasterFramework:Text("", stockpileColor)
    local buildPercentText = MasterFramework:Text("", white)

    local counter = MasterFramework:VerticalStack({
        MasterFramework:Button(
                MasterFramework:Rect(
                        MasterFramework:Dimension(iconSize),
                        MasterFramework:Dimension(iconSize),
                        MasterFramework:Dimension(3),
                        { MasterFramework:Image("#" .. icon) }
                ),
                function()
                    local _, _, _, shift = Spring.GetModKeyState()

                    if not shift then
                        unitsToSelect = { unitsToSelect[1] }
                    end
                    Spring.SelectUnitArray(unitsToSelect, shift)
                end
        ),
        MasterFramework:HorizontalStack({
            buildPercentText,
            stockpileText,
        },
                MasterFramework:Dimension(6),
                1
        )
    },
            MasterFramework:Dimension(8),
            1
    )

    function counter:Update(units)
        local stockpile = 0
        local maxStockpilePercent = 0
        local color
        unitsToSelect = {}

        if #units == 0 then
            stockpileText:SetString("")
            buildPercentText:SetString("")
            return
        end

        for _, unitId in ipairs(units) do
            local unitStockpile, _, unitBuildPercent = Spring.GetUnitStockpile(unitId)
            if unitStockpile > 0 then
                table.insert(unitsToSelect, unitId)
            end
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
        buildPercentText:SetString(string.format("%2d%%", maxStockpilePercent))
    end

    countersCache[id] = counter
    return counter
end

local function findUnits(teamIDs, unitDefIDs)
    return table.reduce(teamIDs, function(acc, teamID)
        table.append(acc, Spring.GetTeamUnitsByDefs(teamID, unitDefIDs))
        return acc
    end, {})
end

function widget:GameFrame(n)
    contentStack.members = {}
    local pinpointersCount = 0
    local allUnits = Spring.GetAllUnits()

    for _, unitId in ipairs(allUnits) do
        if Spring.IsUnitAllied(unitId) then
            if pinpointerNames[UnitDefs[Spring.GetUnitDefID(unitId)].name] then
                pinpointersCount = pinpointersCount + 1
            end
        end
    end
    table.insert(contentStack.members, UnitCounter(pinpointersId, 3))

    local teamId, teamIds
    if spectatorMode then
        teamId = Spring.GetMyAllyTeamID()
        teamIds = Spring.GetTeamList(teamId)
    else
        teamId = Spring.GetMyTeamID()
        teamIds = { teamId }
    end

    local nukes = findUnits(teamIds, nukeDefIDs)
    local junos = findUnits(teamIds, junoDefIDs)

    if (#junos > 0 or spectatorMode) then
        table.insert(contentStack.members, UnitWithStockpileCounter("junos", junoDefIDs[1]))
    end
    if (#nukes > 0 or spectatorMode) then
        table.insert(contentStack.members, UnitWithStockpileCounter("nukes", nukeDefIDs[1]))
    end

    countersCache[pinpointersId]:Update(pinpointersCount)
    countersCache[nukesId]:Update(nukes)
    countersCache[junosId]:Update(junos)
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
end