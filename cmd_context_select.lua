function widget:GetInfo()
    return {
        name = "Context Select",
        desc = "Adds unit select action which changes depending on what you have selected.\n\n- Nothing or single unit selected: select single nearest builder.\n- Radar and/or jammer in selection: select all radars/jammers.\n- Special unit in selection (spy/skuttle): select special unit closest to the mouse.\n- Otherwise: select units with < 50% health",
        author = "SuperKitowiec",
        date = "2024-04-07 v0.1",
        layer = 0,
        enabled = true
    }
end

local GetUnitDefID = Spring.GetUnitDefID
local GetSelectedUnits = Spring.GetSelectedUnits
local SendCommands = Spring.SendCommands
local Echo = Spring.Echo
local UnitDefs = UnitDefs

local specialUnitNames = {
	armspy = true, 		-- arm spybot
	corspy = true, 		-- cor spybot
	corsktl = true 		-- cor skuttle
}

local radarAndJammerNames = {
    armaser = true, 	-- arm bot jammer
	armmark = true, 	-- arm bot radar
	corspec = true, 	-- cor bot jammer
	corvoyr = true, 	-- cor bot radar
	armseer = true, 	-- arm veh radar
	armjam = true, 		-- arm veh jammer
	corvrad = true, 	-- cor veh radar
	coreter = true, 	-- cor veh jammer
	armpeep = true, 	-- arm t1 airscout
	armsehak = true,	-- arm seaplane scout
	armawac = true, 	-- arm t2 airscout
	corawac = true, 	-- cor t2 airscout
	corfink = true, 	-- cor t1 airscout
	corhunt = true 		-- cor seaplane scout
}

local specialUnitDefs = {}
local radarAndJammerDefs = {}
local specialUnitsQuery, radarsAndJammersQuery;

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

	for unitDefID, def in ipairs(UnitDefs) do
		if specialUnitNames[def.name] then
			specialUnitDefs[unitDefID] = true
		end
		if radarAndJammerNames[def.name] then
			radarAndJammerDefs[unitDefID] = true
		end
	end
	widgetHandler:AddAction("context_select", SmartSelect, nil, 'p')
end

function SmartSelect()
    local selectedUnits = GetSelectedUnits()
	local selectedSpecialUnits = 0
	local selectedJammerAndRadars = 0
	
	if #selectedUnits < 2 then
		-- select 1 builder up to 500 units from mouse
		SendCommands("select FromMouse_500+_Buildoptions_Not_Building+_ClearSelection_SelectNum_1+")
	else
		for i = 1, #selectedUnits do
			local unitId = selectedUnits[i]
			local unitDefId = GetUnitDefID(unitId)
			
			if specialUnitDefs[unitDefId] then
				selectedSpecialUnits = selectedSpecialUnits + 1
			elseif radarAndJammerDefs[unitDefId] then
				selectedJammerAndRadars = selectedJammerAndRadars + 1
			end
		end
		
		if selectedJammerAndRadars > 0 then
			-- from current selection select only jammers and radars 
			SendCommands("select PrevSelection+_IdMatches_" .. radarsAndJammersQuery .. "+_ClearSelection_SelectAll+")
		elseif selectedSpecialUnits > 0 then
			-- from current selection select only special units (spy/skuttle)
			SendCommands("select PrevSelection+_IdMatches_" .. specialUnitsQuery .. "+_ClearSelection_SelectClosestToCursor")
		else
			-- from current selection select units with less that 50% hp
			SendCommands("select PrevSelection+_Not_Building_Not_RelativeHealth_50+_ClearSelection_SelectAll+")
		end
	end
end