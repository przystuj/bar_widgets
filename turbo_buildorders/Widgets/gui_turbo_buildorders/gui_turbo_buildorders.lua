if not RmlUi then return end

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name      = "Turbo Build Orders UI",
		desc      = "UI panel for snapshots, restarts, and wind control",
		author    = "SuperKitowiec",
		date      = "2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

local spGetGameFrame     = Spring.GetGameFrame
local spGetMyTeamID      = Spring.GetMyTeamID
local spGetTeamStatsHistory = Spring.GetTeamStatsHistory
local spSendLuaRulesMsg  = Spring.SendLuaRulesMsg
local spSetClipboard     = Spring.SetClipboard
local spEcho             = Spring.Echo
local spGetTimer         = Spring.GetTimer
local spDiffTimers       = Spring.DiffTimers
local mFloor             = math.floor
local mMax               = math.max

local MODEL_NAME = "quick_restart_model"
local RML_MAIN_PATH = "LuaUI/Widgets/gui_turbo_buildorders/gui_turbo_buildorders_main.rml"
local RML_RUNS_PATH = "LuaUI/Widgets/gui_turbo_buildorders/gui_turbo_buildorders_runs.rml"

local docMain, docRuns, dm
local runOffsetFrame = 0
local ignoreUnitFinishedFrames = 0
local nextCheckpointId = 1
local checkpointsData = {}
local activeCheckpointId = 0
local currentRunTimeline = {}
local savedRunsHistory = {} --- @type RunHistory[]

-- Visual states
local pendingScrollToRightFrame
local flashDuration = 0.1

-- Variables to track baseline engine stats for accurate run calculations
local engineMetalAtRestart = 0
local engineEnergyAtRestart = 0
local activeCheckpointBaseMetal = 0
local activeCheckpointBaseEnergy = 0

-- Tracker for the ACTUAL wind applied to the engine
local activeMinWind = Game.windMin
local activeMaxWind = Game.windMax

local trackedTeamID = spGetMyTeamID()
local isReplay = Spring.IsReplay()
local _, _, isSpec = Spring.GetSpectatingState()

local windFunctions = VFS.Include('common/wind_functions.lua')
local mapAvgWindStr = windFunctions.getAverageWind()

local function GetVirtualFrame()
	return mMax(0, spGetGameFrame() - runOffsetFrame)
end

local function FormatTime(frames)
	local totalSeconds = mFloor(frames / 30)
	return string.format("%02d:%02d", mFloor(totalSeconds / 60), totalSeconds % 60)
end

local function CloneTimeline(source)
	local copy = {}
	for i = 1, #source do
		local v = source[i]
		copy[i] = {
			isCheckpoint = (v.isCheckpoint == true),
			isResource = (v.isResource == true),
			isEnd = (v.isEnd == true),
			id = v.id or -1,
			timeStr = v.timeStr or "00:00",
			humanName = v.humanName or "Unknown",
			metalStr = v.metalStr or "",
			energyStr = v.energyStr or "",
			hidden = (v.hidden == true),
			uid = i,
			folded = (v.folded == true),
			foldCount = v.foldCount or 1,
			foldedChild = (v.foldedChild == true),
			metal = v.metal or 0,
			energy = v.energy or 0
		}
	end
	return copy
end

local modelData
modelData = {
	isReplay = isReplay,
	isSpec = isSpec,
	minWind = Game.windMin,
	maxWind = Game.windMax,
	minWindText = Game.windMin,
	maxWindText = Game.windMax,
	avgWindText = mapAvgWindStr,
	clockTime = "00:00",
	currentTimeline = {},
	isCurrentTimelineEmpty = true,
	savedRuns = savedRunsHistory,
	showRunsPanel = false,
	hasSavedRun = false,
	highlightedUnit = "",
	highlightedUnitCount = {},
	ignoredUnits = {},
	ignoredUnitsList = {},

	updateTimelineVisibilities = function()
		for i = 1, #currentRunTimeline do
			local item = currentRunTimeline[i]
			if item and not (item.isCheckpoint == true) then
				item.hidden = (modelData.ignoredUnits[item.humanName] == true)
			end
		end
		dm.currentTimeline = currentRunTimeline

		for i = 1, #savedRunsHistory do
			local run = savedRunsHistory[i]
			if run and run.timeline then
				for j = 1, #run.timeline do
					local item = run.timeline[j]
					if item and not (item.isCheckpoint == true) and not item.isResource and not item.isEnd then
						item.hidden = (modelData.ignoredUnits[item.humanName] == true)
					end
				end
			end
		end
		dm.savedRuns = savedRunsHistory
	end,

	addCheckpoint = function(ev)
		local cpId = nextCheckpointId
		local reusingId = false

		for i = #currentRunTimeline, 1, -1 do
			local item = currentRunTimeline[i]
			if item.isCheckpoint and item.isPending then
				cpId = item.id
				reusingId = true
				table.remove(currentRunTimeline, i)
				break
			end
		end

		if not reusingId then
			nextCheckpointId = nextCheckpointId + 1
		end

		local vFrame = GetVirtualFrame()
		local range = spGetTeamStatsHistory(trackedTeamID)
		local history = spGetTeamStatsHistory(trackedTeamID, range)
		local stats = (history and #history > 0) and history[#history] or {}

		local currentEngineMetal = stats.metalProduced or 0
		local currentEngineEnergy = stats.energyProduced or 0
		local vMetal = activeCheckpointBaseMetal + mMax(0, currentEngineMetal - engineMetalAtRestart)
		local vEnergy = activeCheckpointBaseEnergy + mMax(0, currentEngineEnergy - engineEnergyAtRestart)

		currentRunTimeline[#currentRunTimeline + 1] = {
			isCheckpoint = true,
			isResource = false,
			isEnd = false,
			id = cpId,
			timeStr = FormatTime(vFrame),
			humanName = "CHECKPOINT " .. cpId .. (reusingId and " (PENDING)" or ""),
			metalStr = "",
			energyStr = "",
			hidden = false,
			isPending = reusingId,
			folded = false,
			foldedChild = false,
			foldCount = 1,
			metal = mFloor(vMetal),
			energy = mFloor(vEnergy)
		}

		checkpointsData[cpId] = {
			virtualFrame = vFrame,
			timelineState = CloneTimeline(currentRunTimeline),
			metal = vMetal,
			energy = vEnergy
		}

		dm.currentTimeline = currentRunTimeline
		spSendLuaRulesMsg("!checkpoint " .. cpId)
	end,

	restartToCheckpoint = function(ev, id)
		local cp = checkpointsData[id]
		if not cp then return end

		spSendLuaRulesMsg("!restart " .. id)
	end,

	saveRun = function(ev)
		modelData.updateTimelineVisibilities()
		local range = spGetTeamStatsHistory(trackedTeamID)
		local history = spGetTeamStatsHistory(trackedTeamID, range)
		local stats = (history and #history > 0) and history[#history] or {}

		local cp = checkpointsData[activeCheckpointId] or { metal = 0, energy = 0 }

		local runProducedMetal = (stats.metalProduced or 0) - engineMetalAtRestart
		local runProducedEnergy = (stats.energyProduced or 0) - engineEnergyAtRestart

		local totalVirtualMetal = mFloor(cp.metal + mMax(0, runProducedMetal))
		local totalVirtualEnergy = mFloor(cp.energy + mMax(0, runProducedEnergy))

		for i = 1, #currentRunTimeline do
			local item = currentRunTimeline[i]
			if not item.isCheckpoint then
				item.hidden = (modelData.ignoredUnits[item.humanName] == true)
			end
		end
		dm.currentTimeline = currentRunTimeline

		local newHistory = {}
		for i = 1, #savedRunsHistory do
			local oldRun = savedRunsHistory[i]
			oldRun.isFlashing = false
			newHistory[i] = oldRun
		end

		-- Build the history timeline, FILTERING OUT checkpoints
		local clonedTimeline = {}
		local uidCounter = 1
		for i = 1, #currentRunTimeline do
			local v = currentRunTimeline[i]
			if not v.isCheckpoint then
				clonedTimeline[#clonedTimeline + 1] = {
					isCheckpoint = false,
					isResource = (v.isResource == true),
					isEnd = (v.isEnd == true),
					id = v.id or -1,
					timeStr = v.timeStr or "00:00",
					humanName = v.humanName or "Unknown",
					metalStr = v.metalStr or "",
					energyStr = v.energyStr or "",
					hidden = (v.hidden == true),
					uid = uidCounter,
					folded = (v.folded == true),
					foldCount = v.foldCount or 1,
					foldedChild = (v.foldedChild == true),
					metal = v.metal or 0,
					energy = v.energy or 0
				}
				uidCounter = uidCounter + 1
			end
		end

		local lastEntry = nil
		for i = #clonedTimeline, 1, -1 do
			if not clonedTimeline[i].hidden then
				lastEntry = clonedTimeline[i]
				break
			end
		end

		if lastEntry and lastEntry.metal and lastEntry.energy then
			clonedTimeline[#clonedTimeline + 1] = {
				isCheckpoint = false,
				isResource = true,
				isEnd = false,
				id = -1,
				timeStr = "",
				humanName = "",
				metalStr = "M: " .. (lastEntry.metal + 1000),
				energyStr = "E: " .. (lastEntry.energy + 1000),
				hidden = false,
				uid = uidCounter,
				folded = false,
				foldedChild = false,
				foldCount = 1,
				metal = 0,
				energy = 0
			}
			uidCounter = uidCounter + 1
		end

		local currentVFrame = GetVirtualFrame()
		clonedTimeline[#clonedTimeline + 1] = {
			isCheckpoint = false,
			isResource = false,
			isEnd = true,
			id = -1,
			timeStr = FormatTime(currentVFrame),
			humanName = "End of Run",
			metalStr = "",
			energyStr = "",
			hidden = false,
			uid = uidCounter,
			folded = false,
			foldedChild = false,
			foldCount = 1,
			metal = 0,
			energy = 0
		}
		uidCounter = uidCounter + 1

		clonedTimeline[#clonedTimeline + 1] = {
			isCheckpoint = false,
			isResource = true,
			isEnd = false,
			id = -1,
			timeStr = "",
			humanName = "",
			metalStr = "M: " .. (totalVirtualMetal + 1000),
			energyStr = "E: " .. (totalVirtualEnergy + 1000),
			hidden = false,
			uid = uidCounter,
			folded = false,
			foldedChild = false,
			foldCount = 1,
			metal = 0,
			energy = 0
		}

		--- @class RunHistory
		newHistory[#savedRunsHistory + 1] = {
			id = #savedRunsHistory + 1,
			isFlashing = true,
			flashEndTime = spGetTimer(),
			metal = totalVirtualMetal + 1000,
			energy = totalVirtualEnergy + 1000,
			minWind = activeMinWind,
			maxWind = activeMaxWind,
			timeline = clonedTimeline
		}

		savedRunsHistory = newHistory
		modelData.refreshUnitCounts()

		dm.savedRuns = savedRunsHistory
		dm.hasSavedRun = true
		dm.showRunsPanel = true

		pendingScrollToRightFrame = spGetGameFrame() + 2
	end,

	copyRun = function(ev, index)
		local run = savedRunsHistory[index + 1]
		if not run then return end

		local windStr = (run.minWind == run.maxWind) and string.format("%.1f", run.minWind) or string.format("%.1f-%.1f", run.minWind, run.maxWind)
		local header = string.format("%s | Wind: %s | %s\n", Game.mapName, windStr, os.date("%Y-%m-%d"))

		local timelineLines = {}
		for i = 1, #run.timeline do
			local v = run.timeline[i]
			if not v.isCheckpoint and not v.hidden then
				if v.isResource then
					timelineLines[#timelineLines + 1] = string.format("      %s   %s", v.metalStr, v.energyStr)
				else
					timelineLines[#timelineLines + 1] = string.format("%s: %s", v.timeStr, v.humanName)
				end
			end
		end

		spSetClipboard(header .. table.concat(timelineLines, "\n"))
		spEcho("Run copied to clipboard!")
	end,

	removeRun = function(ev, index)
		if not savedRunsHistory[index + 1] then return end

		local newHistory = {}
		for i = 1, #savedRunsHistory do
			if i ~= (index + 1) then
				table.insert(newHistory, savedRunsHistory[i])
			end
		end

		savedRunsHistory = newHistory
		modelData.refreshUnitCounts()

		dm.savedRuns = savedRunsHistory
		dm.hasSavedRun = (#savedRunsHistory > 0)
	end,

	toggleRunsPanel = function(ev)
		dm.showRunsPanel = not dm.showRunsPanel
		if docRuns then
			if dm.showRunsPanel then docRuns:Show() else docRuns:Hide() end
		end
	end,

	sendCommand = function(ev, command)
		spSendLuaRulesMsg(command)
	end,

	sendWind = function(ev)
		local minW, maxW = tonumber(dm.minWind) or 10, tonumber(dm.maxWind) or 10
		activeMinWind = minW
		activeMaxWind = maxW
		spEcho(string.format("Wind set to %.1f-%.1f", minW, maxW))
		spSendLuaRulesMsg("!wind " .. minW .. " " .. maxW)
	end,

	sendMinWind = function(ev)
		local w = Game.windMin
		activeMinWind = w
		activeMaxWind = w
		spEcho(string.format("Wind set to %.1f-%.1f", w, w))
		spSendLuaRulesMsg("!wind " .. w .. " " .. w)
	end,

	sendAvgWind = function(ev)
		dm.minWind, dm.maxWind = mapAvgWindStr, mapAvgWindStr
		activeMinWind = mapAvgWindStr
		activeMaxWind = mapAvgWindStr
		spEcho(string.format("Wind set to %.1f-%.1f", mapAvgWindStr, mapAvgWindStr))
		spSendLuaRulesMsg("!wind " .. mapAvgWindStr .. " " .. mapAvgWindStr)
	end,

	sendMaxWind = function(ev)
		local w = Game.windMax
		activeMinWind = w
		activeMaxWind = w
		spEcho(string.format("Wind set to %.1f-%.1f", w, w))
		spSendLuaRulesMsg("!wind " .. w .. " " .. w)
	end,

	copyAllRunsCSV = function(ev)
		if #savedRunsHistory == 0 then
			spEcho("No runs to copy!")
			return
		end

		-- 1. Scan for every unique second where ANY unit was built
		local timesMap = {}
		for i=1, #savedRunsHistory do
			for j=1, #savedRunsHistory[i].timeline do
				local item = savedRunsHistory[i].timeline[j]
				if not item.isCheckpoint and not item.isResource and not item.isEnd and not item.hidden then
					timesMap[item.timeStr] = true
				end
			end
		end

		local timesList = {}
		for t, _ in pairs(timesMap) do table.insert(timesList, t) end
		table.sort(timesList)

		-- 2. Build the top header row
		local headerCols = {"Time"}
		for i=1, #savedRunsHistory do
			local wind
			if savedRunsHistory[i].minWind ~= savedRunsHistory[i].maxWind then
				wind = string.format("Wind %.1f - %.1f", savedRunsHistory[i].minWind, savedRunsHistory[i].maxWind)
			else
				wind = string.format("Wind %.1f", savedRunsHistory[i].minWind)
			end
			table.insert(headerCols, wind)
		end
		local csvLines = { table.concat(headerCols, ",") }

		-- 3. Build each row by time
		for _, tStr in ipairs(timesList) do
			local rowCols = { tStr }
			for i=1, #savedRunsHistory do
				local unitsAtTime = {}
				for j=1, #savedRunsHistory[i].timeline do
					local item = savedRunsHistory[i].timeline[j]
					if item.timeStr == tStr and not item.isCheckpoint and not item.isResource and not item.isEnd and not item.hidden then
						table.insert(unitsAtTime, item.humanName)
					end
				end
				-- Join multiples with a pipe, wrap cell in quotes to prevent standard CSV breakage
				table.insert(rowCols, '"' .. table.concat(unitsAtTime, " | ") .. '"')
			end
			table.insert(csvLines, table.concat(rowCols, ","))
		end

		local metalCols = {"Metal"}
		local energyCols = {"Energy"}

		for i=1, #savedRunsHistory do
			local run = savedRunsHistory[i]
			local lastUnitMetal = 1000
			local lastUnitEnergy = 1000

			-- Scan backwards to find the last valid unit entry
			for j = #run.timeline, 1, -1 do
				local item = run.timeline[j]
				if not item.isCheckpoint and not item.isResource and not item.isEnd and not item.hidden then
					lastUnitMetal = (item.metal or 0) + 1000
					lastUnitEnergy = (item.energy or 0) + 1000
					break
				end
			end

			table.insert(metalCols, tostring(lastUnitMetal))
			table.insert(energyCols, tostring(lastUnitEnergy))
		end

		table.insert(csvLines, table.concat(metalCols, ","))
		table.insert(csvLines, table.concat(energyCols, ","))

		spSetClipboard(table.concat(csvLines, "\n"))
		spEcho("CSV copied to clipboard!")
	end,

	sendDefaultWind = function(ev)
		spSendLuaRulesMsg("!wind off")
		dm.minWind, dm.maxWind = Game.windMin, Game.windMax
		activeMinWind = Game.windMin
		activeMaxWind = Game.windMax
		spEcho(string.format("Wind set to %.1f-%.1f", Game.windMin, Game.windMax))
	end,

	onMinWindChange = function(ev)
		local val = tonumber(ev.parameters.value)
		if val then
			dm.minWind = val
			if dm.minWind > dm.maxWind then dm.maxWind = dm.minWind end
		end
	end,

	onMaxWindChange = function(ev)
		local val = tonumber(ev.parameters.value)
		if val then
			dm.maxWind = val
			if dm.maxWind < dm.minWind then dm.minWind = dm.maxWind end
		end
	end,

	refreshUnitCounts = function(overrideUnit)
		if not dm then return end
		local counts = {}
		local hUnit = (overrideUnit ~= nil) and overrideUnit or dm.highlightedUnit

		for i = 1, #savedRunsHistory do
			local count = 0
			if hUnit and hUnit ~= "" then
				local run = savedRunsHistory[i]
				for j = 1, #run.timeline do
					if run.timeline[j].humanName == hUnit and not run.timeline[j].isCheckpoint and not run.timeline[j].isResource and not run.timeline[j].isEnd then
						count = count + 1
					end
				end
			end
			counts[i] = count
		end
		dm.highlightedUnitCount = counts
	end,

	handleRunItemClick = function(ev, runId, itemUid)
		local itemName, isCp
		for i=1, #savedRunsHistory do
			if savedRunsHistory[i].id == runId then
				for j=1, #savedRunsHistory[i].timeline do
					if savedRunsHistory[i].timeline[j].uid == itemUid then
						itemName = savedRunsHistory[i].timeline[j].humanName
						isCp = savedRunsHistory[i].timeline[j].isCheckpoint
						break
					end
				end
			end
		end

		if not itemName or itemName == "" or itemName == "End of Run" then return end

		if ev.parameters.button == 0 then
			if not isCp then
				local newUnit = (dm.highlightedUnit == itemName) and "" or itemName
				modelData.refreshUnitCounts(newUnit)
				dm.highlightedUnit = newUnit
			end
		elseif ev.parameters.button == 1 then
			modelData.ignoreUnit(ev, itemName, isCp)
		elseif ev.parameters.button == 2 then
			modelData.toggleFold(runId, itemUid)
		end
	end,

	toggleFold = function(runId, itemUid)
		local run = nil
		local runIdx = nil
		for i=1, #savedRunsHistory do
			if savedRunsHistory[i].id == runId then
				run = savedRunsHistory[i]
				runIdx = i
				break
			end
		end
		if not run then return end

		local targetIdx = nil
		for i=1, #run.timeline do
			if run.timeline[i].uid == itemUid then
				targetIdx = i
				break
			end
		end
		if not targetIdx then return end

		local targetItem = run.timeline[targetIdx]
		if targetItem.isCheckpoint or targetItem.isResource or targetItem.isEnd then return end

		local hName = targetItem.humanName

		local startIdx = targetIdx
		while startIdx > 1 and run.timeline[startIdx - 1].humanName == hName and not run.timeline[startIdx - 1].isCheckpoint do
			startIdx = startIdx - 1
		end

		local endIdx = targetIdx
		while endIdx < #run.timeline and run.timeline[endIdx + 1].humanName == hName and not run.timeline[endIdx + 1].isCheckpoint do
			endIdx = endIdx + 1
		end

		if endIdx == startIdx then return end

		local newTimeline = {}
		for i=1, #run.timeline do
			newTimeline[i] = {
				isCheckpoint = run.timeline[i].isCheckpoint,
				isResource = run.timeline[i].isResource,
				isEnd = run.timeline[i].isEnd,
				id = run.timeline[i].id,
				timeStr = run.timeline[i].timeStr,
				humanName = run.timeline[i].humanName,
				metalStr = run.timeline[i].metalStr or "",
				energyStr = run.timeline[i].energyStr or "",
				hidden = run.timeline[i].hidden,
				uid = run.timeline[i].uid,
				folded = run.timeline[i].folded,
				foldCount = run.timeline[i].foldCount,
				foldedChild = run.timeline[i].foldedChild,
				metal = run.timeline[i].metal,
				energy = run.timeline[i].energy
			}
		end

		local headItemCopy = newTimeline[startIdx]

		if headItemCopy.folded then
			headItemCopy.folded = false
			headItemCopy.foldCount = 1
			for i = startIdx + 1, endIdx do
				newTimeline[i].foldedChild = false
			end
		else
			headItemCopy.folded = true
			headItemCopy.foldCount = (endIdx - startIdx + 1)
			for i = startIdx + 1, endIdx do
				newTimeline[i].foldedChild = true
			end
		end

		local newSavedRuns = {}
		for i=1, #savedRunsHistory do
			if i == runIdx then
				local updatedRun = {}
				for k,v in pairs(savedRunsHistory[i]) do updatedRun[k] = v end
				updatedRun.timeline = newTimeline
				newSavedRuns[i] = updatedRun
			else
				newSavedRuns[i] = savedRunsHistory[i]
			end
		end

		savedRunsHistory = newSavedRuns
		dm.savedRuns = savedRunsHistory
	end,

	toggleHighlight = function(ev, unitName, isCheckpoint)
		if isCheckpoint or not unitName or unitName == "" or unitName == "End of Run" then return end

		if ev.parameters.button == 0 then
			local newUnit = (dm.highlightedUnit == unitName) and "" or unitName
			modelData.refreshUnitCounts(newUnit)
			dm.highlightedUnit = newUnit
		elseif ev.parameters.button == 1 then
			modelData.ignoreUnit(ev, unitName, isCheckpoint)
		end
	end,

	ignoreUnit = function(ev, unitName, isCheckpoint)
		if isCheckpoint or not unitName or unitName == "" or unitName == "End of Run" or modelData.ignoredUnits[unitName] then return end

		modelData.ignoredUnits[unitName] = true
		table.insert(modelData.ignoredUnitsList, unitName)
		dm.ignoredUnitsList = modelData.ignoredUnitsList
		dm.ignoredUnits = modelData.ignoredUnits

		if dm.highlightedUnit == unitName then
			modelData.refreshUnitCounts("")
			dm.highlightedUnit = ""
		end
		modelData.updateTimelineVisibilities()
	end,

	restoreUnit = function(ev, unitName)
		if not unitName or not modelData.ignoredUnits[unitName] then return end

		modelData.ignoredUnits[unitName] = nil
		for i = 1, #modelData.ignoredUnitsList do
			if modelData.ignoredUnitsList[i] == unitName then
				table.remove(modelData.ignoredUnitsList, i)
				break
			end
		end

		dm.ignoredUnitsList = modelData.ignoredUnitsList
		dm.ignoredUnits = modelData.ignoredUnits
		modelData.updateTimelineVisibilities()
	end
}

function widget:Initialize()
	widget.rmlContext = RmlUi.GetContext("shared")
	if not widget.rmlContext then return false end

	widget.rmlContext:RemoveDataModel(MODEL_NAME)
	dm = widget.rmlContext:OpenDataModel(MODEL_NAME, modelData)
	if not dm then return false end

	docMain = widget.rmlContext:LoadDocument(RML_MAIN_PATH, widget)
	if docMain then
		docMain:ReloadStyleSheet()
		docMain:Show()
	end

	docRuns = widget.rmlContext:LoadDocument(RML_RUNS_PATH, widget)
	if docRuns then
		docRuns:ReloadStyleSheet()
		docRuns:Hide()
		dm.showRunsPanel = false
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= trackedTeamID or spGetGameFrame() <= ignoreUnitFinishedFrames then return end

	local ud = UnitDefs[unitDefID]
	if not ud then return end

	local hName = ud.translatedHumanName or ud.humanName or ud.name

	local range = spGetTeamStatsHistory(trackedTeamID)
	local history = spGetTeamStatsHistory(trackedTeamID, range)
	local stats = (history and #history > 0) and history[#history] or {}

	local currentEngineMetal = stats.metalProduced or 0
	local currentEngineEnergy = stats.energyProduced or 0
	local vMetal = activeCheckpointBaseMetal + mMax(0, currentEngineMetal - engineMetalAtRestart)
	local vEnergy = activeCheckpointBaseEnergy + mMax(0, currentEngineEnergy - engineEnergyAtRestart)

	currentRunTimeline[#currentRunTimeline + 1] = {
		isCheckpoint = false,
		isResource = false,
		isEnd = false,
		id = -1,
		timeStr = FormatTime(GetVirtualFrame()),
		humanName = hName,
		metalStr = "",
		energyStr = "",
		hidden = modelData.ignoredUnits[hName] or false,
		folded = false,
		foldedChild = false,
		foldCount = 1,
		metal = mFloor(vMetal),
		energy = mFloor(vEnergy)
	}

	if dm then dm.currentTimeline = currentRunTimeline end
end

function widget:GameFrame(f)
	if f < 10 then
		if docRuns then
			docRuns:Hide()
			dm.showRunsPanel = false
		end
	end

	if f == 11 then
		local range = spGetTeamStatsHistory(trackedTeamID)
		local history = spGetTeamStatsHistory(trackedTeamID, range)
		local stats = (history and #history > 0) and history[#history] or {}

		engineMetalAtRestart = stats.metalProduced or 0
		engineEnergyAtRestart = stats.energyProduced or 0
		activeCheckpointBaseMetal = engineMetalAtRestart
		activeCheckpointBaseEnergy = engineEnergyAtRestart

		currentRunTimeline[#currentRunTimeline + 1] = {
			isCheckpoint = true,
			isResource = false,
			isEnd = false,
			id = 0,
			timeStr = "00:00",
			humanName = "CHECKPOINT 0",
			metalStr = "",
			energyStr = "",
			hidden = false,
			folded = false,
			foldedChild = false,
			foldCount = 1,
			metal = mFloor(activeCheckpointBaseMetal),
			energy = mFloor(activeCheckpointBaseEnergy)
		}

		checkpointsData[0] = {
			virtualFrame = 0,
			timelineState = CloneTimeline(currentRunTimeline),
			metal = activeCheckpointBaseMetal,
			energy = activeCheckpointBaseEnergy
		}

		if dm then dm.currentTimeline = currentRunTimeline end
	end
end

function widget:AddConsoleLine(msg, priority)
	local idStr = msg and msg:match("State restored to Checkpoint (%d+)")
	if idStr then
		local id = tonumber(idStr)
		local cp = checkpointsData[id]
		if cp then
			activeCheckpointId = id
			runOffsetFrame = spGetGameFrame() - cp.virtualFrame
			ignoreUnitFinishedFrames = spGetGameFrame() + 15
			currentRunTimeline = cp.timelineState and CloneTimeline(cp.timelineState) or {}

			local range = spGetTeamStatsHistory(trackedTeamID)
			local history = spGetTeamStatsHistory(trackedTeamID, range)
			local stats = (history and #history > 0) and history[#history] or {}

			engineMetalAtRestart = stats.metalProduced or 0
			engineEnergyAtRestart = stats.energyProduced or 0
			activeCheckpointBaseMetal = cp.metal
			activeCheckpointBaseEnergy = cp.energy

			if dm then
				dm.currentTimeline = currentRunTimeline
				dm.clockTime = FormatTime(GetVirtualFrame())
			end
		end
	end
end

function widget:Update()
	if not dm then return end

	dm.isCurrentTimelineEmpty = #currentRunTimeline == 0

	local needsFlashUpdate = false
	for i = 1, #savedRunsHistory do
		if savedRunsHistory[i].isFlashing then
			if spDiffTimers(spGetTimer(), savedRunsHistory[i].flashEndTime) > flashDuration then
				savedRunsHistory[i].isFlashing = false
				needsFlashUpdate = true
			end
		end
	end
	if needsFlashUpdate then
		dm.savedRuns = savedRunsHistory
	end

	if isReplay or isSpec then
		local newTeam = Spring.GetSelectedTeamID()
		if newTeam and newTeam ~= trackedTeamID then
			trackedTeamID = newTeam
			currentRunTimeline = {}
			dm.currentTimeline = currentRunTimeline
		end
		local _, _, nowSpec = Spring.GetSpectatingState()
		if nowSpec ~= isSpec then
			isSpec = nowSpec
			dm.isSpec = isSpec
			if not isSpec then
				trackedTeamID = spGetMyTeamID()
				currentRunTimeline = {}
				dm.currentTimeline = currentRunTimeline
			end
		end
	end

	local newTimeStr = FormatTime(GetVirtualFrame())
	if dm.clockTime ~= newTimeStr then
		dm.clockTime = newTimeStr
	end


	if pendingScrollToRightFrame and pendingScrollToRightFrame <= spGetGameFrame() and docRuns then
		local listEl = docRuns:GetElementById("runs-list-container")
		if listEl then
			listEl.scroll_left = listEl.scroll_width
		end
		pendingScrollToRightFrame = nil
	end
end

function widget:Shutdown()
	if docMain then
		docMain:Hide()
		docMain:Close()
		docMain = nil
	end
	if docRuns then
		docRuns:Hide()
		docRuns:Close()
		docRuns = nil
	end
	if widget.rmlContext then
		widget.rmlContext:RemoveDataModel(MODEL_NAME)
	end
	widget.rmlContext = nil
end

function widget:RecvLuaMsg(message, playerID)
	local shouldShow = (message:sub(1, 19) == 'LobbyOverlayActive0')
	local shouldHide = (message:sub(1, 19) == 'LobbyOverlayActive1')

	if shouldShow then
		docMain:Show()
	end

	if shouldHide then
		docMain:Hide()
		docRuns:Hide()
	end

	if string.sub(message, 1, 13) == "TurboRestart " then
		local id = tonumber(string.sub(message, 14))
		if id then
			local cp = checkpointsData[id]
			if cp then
				activeCheckpointId = id
				runOffsetFrame = spGetGameFrame() - cp.virtualFrame
				ignoreUnitFinishedFrames = spGetGameFrame() + 15
				currentRunTimeline = cp.timelineState and CloneTimeline(cp.timelineState) or {}

				local range = spGetTeamStatsHistory(trackedTeamID)
				local history = spGetTeamStatsHistory(trackedTeamID, range)
				local stats = (history and #history > 0) and history[#history] or {}

				engineMetalAtRestart = stats.metalProduced or 0
				engineEnergyAtRestart = stats.energyProduced or 0

				activeCheckpointBaseMetal = cp.metal
				activeCheckpointBaseEnergy = cp.energy

				if dm then
					dm.currentTimeline = currentRunTimeline
					dm.clockTime = FormatTime(GetVirtualFrame())

					dm.showRunsPanel = false
					if docRuns then docRuns:Hide() end
				end
			end
		end
	end

	if string.sub(message, 1, 15) == "TurboCheckpoint" then
		local action, idStr, frameStr = message:match("^TurboCheckpoint(%a+) (%d+) *(%d*)")
		local id = tonumber(idStr)
		if action and id then

			if action == "Cancelled" then
				for i = #currentRunTimeline, 1, -1 do
					if currentRunTimeline[i].isCheckpoint and currentRunTimeline[i].id == id then
						table.remove(currentRunTimeline, i)
						checkpointsData[id] = nil
						break
					end
				end
				for _, cpData in pairs(checkpointsData) do
					if cpData.timelineState then
						for i = #cpData.timelineState, 1, -1 do
							if cpData.timelineState[i].isCheckpoint and cpData.timelineState[i].id == id then
								table.remove(cpData.timelineState, i)
							end
						end
					end
				end
				if dm then dm.currentTimeline = currentRunTimeline end
				return
			end

			for i = 1, #currentRunTimeline do
				if currentRunTimeline[i].isCheckpoint and currentRunTimeline[i].id == id then
					if action == "Pending" then
						currentRunTimeline[i].humanName = "CHECKPOINT " .. id .. " (PENDING)"
						currentRunTimeline[i].isPending = true

					elseif action == "Updated" then
						currentRunTimeline[i].humanName = "CHECKPOINT " .. id
						currentRunTimeline[i].isPending = false
						local realFrame = tonumber(frameStr)
						if realFrame then
							local newVFrame = mMax(0, realFrame - runOffsetFrame)
							currentRunTimeline[i].timeStr = FormatTime(newVFrame)
							if checkpointsData[id] then
								checkpointsData[id].virtualFrame = newVFrame
								local range = spGetTeamStatsHistory(trackedTeamID)
								local history = spGetTeamStatsHistory(trackedTeamID, range)
								local stats = (history and #history > 0) and history[#history] or {}

								local currentEngineMetal = stats.metalProduced or 0
								local currentEngineEnergy = stats.energyProduced or 0
								local vMetal = activeCheckpointBaseMetal + mMax(0, currentEngineMetal - engineMetalAtRestart)
								local vEnergy = activeCheckpointBaseEnergy + mMax(0, currentEngineEnergy - engineEnergyAtRestart)
								checkpointsData[id].metal = vMetal
								checkpointsData[id].energy = vEnergy
								currentRunTimeline[i].metal = mFloor(vMetal)
								currentRunTimeline[i].energy = mFloor(vEnergy)
							end
						end
						if checkpointsData[id] then
							checkpointsData[id].timelineState = CloneTimeline(currentRunTimeline)
						end

					elseif action == "Saved" then
						currentRunTimeline[i].humanName = "CHECKPOINT " .. id
						currentRunTimeline[i].isPending = false
						if checkpointsData[id] then
							checkpointsData[id].timelineState = CloneTimeline(currentRunTimeline)
						end

					elseif action == "Timeout" then
						if currentRunTimeline[i].isPending then
							currentRunTimeline[i].humanName = "CHECKPOINT " .. id .. " (FALLBACK)"
							currentRunTimeline[i].isPending = false
							if checkpointsData[id] then
								checkpointsData[id].timelineState = CloneTimeline(currentRunTimeline)
							end
						end
					end
				end
			end
			if dm then dm.currentTimeline = currentRunTimeline end
		end
	end
end
