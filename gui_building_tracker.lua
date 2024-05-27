function widget:GetInfo()
    return {
        name = "Buildings Tracker",
        desc = "Shows counters for pinpointers, nukes and junos. Click building icon to select one, shift click to select all",
        author = "SuperKitowiec",
        version = 0.3,
        license = "GNU GPL, v2 or later",
        layer = 0
    }
end

------------------------------------------------------------------------------------------------------------
-- Imports
------------------------------------------------------------------------------------------------------------

local MasterFramework
local requiredFrameworkVersion = 42
local key
local backgroundColor
local contentStack
local red
local green
local yellow
local white
local spectatorMode

local nukeNames = {
	armsilo = true, 		-- arm nuke
	corsilo = true, 		-- cor nuke
}

local junoNames = {
	armjuno = true, 		-- arm juno
	corjuno = true 		    -- cor juno
}

local pinpointerNames = {
	armtarg = true, 		-- arm pinpointer
	cortarg = true, 		-- cor pinpointer
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

local function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end
	
	spectatorMode = Spring.GetSpectatingState()

    backgroundColor = MasterFramework:Color(0, 0, 0, 0)
    red = MasterFramework:Color(1, 0, 0, 1)
    green = MasterFramework:Color(0, 1, 0, 1)
    yellow = MasterFramework:Color(1, 1, 0, 1)
    white = MasterFramework:Color(1, 1, 1, 1)

    contentStack = MasterFramework:HorizontalStack({}, MasterFramework:Dimension(8), 1)

    key =
        MasterFramework:InsertElement(
        MasterFramework:MovableFrame(
            "Buildings Tracker",
            MasterFramework:PrimaryFrame(
                MasterFramework:MarginAroundRect(
                    contentStack,
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    MasterFramework:Dimension(5),
                    {backgroundColor},
                    MasterFramework:Dimension(5),
                    true
                )
            ),
            1700,
            900
        ),
        "Buildings Tracker",
        MasterFramework.layerRequest.bottom()
    )
end

local function displayPinpointers(pinpointersCount)
    local color
    if pinpointersCount == 0 then
        color = red
    elseif pinpointersCount < 3 then
        color = yellow
    else
        color = green
    end

    local pinpointerText = MasterFramework:Text(string.format("%d", pinpointersCount), color)

    return MasterFramework:VerticalStack({
        MasterFramework:Rect(
            MasterFramework:Dimension(50),
            MasterFramework:Dimension(50),
            MasterFramework:Dimension(3),
            {MasterFramework:Image("#" .. pinpointerDefIDs[1])}
        ),
        pinpointerText},
        MasterFramework:Dimension(8),
        1
    )
end

local function display(buildings, icon)
    local stockpile = 0
    local maxStockpilePercent = 0
    local color
    local unitsToSelect = {}

    for _, unitId in ipairs(buildings) do
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
    local stockpileText = MasterFramework:Text(string.format("%d", stockpile), color)
    local buildPercentText = MasterFramework:Text(string.format("%02d%%", maxStockpilePercent), white)
	
	if #buildings == 0 then 
		buildPercentText = nil
		stockpileText = nil
	end

    return MasterFramework:VerticalStack({
        MasterFramework:Button(
            MasterFramework:Rect(
                MasterFramework:Dimension(50),
                MasterFramework:Dimension(50),
                MasterFramework:Dimension(3),
                {MasterFramework:Image("#" .. icon)}
            ),
            function()
                local _, _, _, shift = Spring.GetModKeyState()

                if not shift then
                    unitsToSelect = {unitsToSelect[1]}
                end
                Spring.SelectUnitArray(unitsToSelect, shift)
            end
        ),
        MasterFramework:HorizontalStack({
            stockpileText,
            buildPercentText
        },
        MasterFramework:Dimension(6),
        1
        )
    },
    MasterFramework:Dimension(8),
    1
    )
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
    table.insert(contentStack.members, displayPinpointers(pinpointersCount))
	
	local teamId
	if spectatorMode then
		teamId = Spring.GetMyAllyTeamID()
	else
		teamId = Spring.GetMyTeamID()
	end
	
    local nukes
    local junos
	if spectatorMode then
		local teamIds = Spring.GetTeamList(teamId)
		nukes = findUnits(teamIds, nukeDefIDs)
		junos = findUnits(teamIds, junoDefIDs)
	else
		nukes = Spring.GetTeamUnitsByDefs(teamId, nukeDefIDs)
		junos = Spring.GetTeamUnitsByDefs(teamId, junoDefIDs)
	end
	
    if (#junos > 0 or spectatorMode) then
        table.insert(contentStack.members, display(junos, junoDefIDs[1]))
    end
    if (#nukes > 0 or spectatorMode) then
        table.insert(contentStack.members, display(nukes, nukeDefIDs[1]))
    end

    backgroundColor.a = 0.6
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
end