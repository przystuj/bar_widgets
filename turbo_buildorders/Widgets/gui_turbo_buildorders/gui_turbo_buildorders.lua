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
local currentRunTimeline = {}
local savedRunsHistory = {}

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
			id = v.id or -1,
			timeStr = v.timeStr or "00:00",
			humanName = v.humanName or "Unknown",
			hidden = (v.hidden == true)
		}
	end
	return copy
end

local modelData
modelData = {
	isReplay = isReplay,
	isSpec = isSpec,
	minWind = 10,
	maxWind = 10,
	avgWindText = mapAvgWindStr,
	clockTime = "00:00",
	currentTimeline = {},
	savedRuns = savedRunsHistory,
	showRunsPanel = false,
	hasSavedRun = false,
	highlightedUnit = "",
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
					if item and not (item.isCheckpoint == true) then
						item.hidden = (modelData.ignoredUnits[item.humanName] == true)
					end
				end
			end
		end
		dm.savedRuns = savedRunsHistory
	end,

	addCheckpoint = function(ev)
		local cpId = nextCheckpointId
		nextCheckpointId = nextCheckpointId + 1

		local vFrame = GetVirtualFrame()
		currentRunTimeline[#currentRunTimeline + 1] = {
			isCheckpoint = true,
			id = cpId,
			timeStr = FormatTime(vFrame),
			humanName = "CHECKPOINT " .. cpId,
			hidden = false
		}

		checkpointsData[cpId] = {
			virtualFrame = vFrame,
			timelineState = CloneTimeline(currentRunTimeline)
		}

		dm.currentTimeline = currentRunTimeline
		spSendLuaRulesMsg("!checkpoint " .. cpId)
	end,

	restartToCheckpoint = function(ev, id)
		local cp = checkpointsData[id]
		if not cp then return end

		runOffsetFrame = spGetGameFrame() - cp.virtualFrame
		ignoreUnitFinishedFrames = spGetGameFrame() + 15

		currentRunTimeline = cp.timelineState and CloneTimeline(cp.timelineState) or {}

		dm.currentTimeline = currentRunTimeline
		dm.clockTime = FormatTime(GetVirtualFrame())
		spSendLuaRulesMsg("!restart " .. id)
	end,

	saveRun = function(ev)
		modelData.updateTimelineVisibilities()
		local range = spGetTeamStatsHistory(trackedTeamID)
		local history = spGetTeamStatsHistory(trackedTeamID, range)
		local stats = (history and #history > 0) and history[#history] or {}
		table.insert(savedRunsHistory, 1, {
			id = #savedRunsHistory + 1,
			metal = mFloor(1000 + (stats.metalProduced or 0)),
			energy = mFloor(1000 + (stats.energyProduced or 0)),
			minWind = dm.minWind,
			maxWind = dm.maxWind,
			timeline = CloneTimeline(currentRunTimeline)
		})

		dm.savedRuns = savedRunsHistory
		dm.hasSavedRun = true
		dm.showRunsPanel = true
		if docRuns then docRuns:Show() end
	end,

	copyRun = function(ev, index)
		local run = savedRunsHistory[index + 1]
		if not run then return end

		local windStr = (run.minWind == run.maxWind) and string.format("%.1f", run.minWind) or string.format("%.1f-%.1f", run.minWind, run.maxWind)
		local header = string.format("%s | Wind: %s | %s\n", Game.mapName, windStr, os.date("%Y-%m-%d"))

		local timelineLines = {}
		for i = 1, #run.timeline do
			local v = run.timeline[i]
			if not v.isCheckpoint then
				timelineLines[#timelineLines + 1] = string.format("%s: %s", v.timeStr, v.humanName)
			end
		end

		local footer = string.format("\nfinal produced resources:\nmetal: %d energy: %d", run.metal, run.energy)
		spSetClipboard(header .. table.concat(timelineLines, "\n") .. footer)
		spEcho("Run copied to clipboard!")
	end,

	removeRun = function(ev, index)
		if not savedRunsHistory[index + 1] then return end
		table.remove(savedRunsHistory, index + 1)
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
		spEcho(string.format("Wind set to %.1f-%.1f", minW, maxW))
		spSendLuaRulesMsg("!wind " .. minW .. " " .. maxW)
	end,

	sendAvgWind = function(ev)
		dm.minWind, dm.maxWind = mapAvgWindStr, mapAvgWindStr
		spEcho(string.format("Wind set to %.1f-%.1f", mapAvgWindStr, mapAvgWindStr))
		spSendLuaRulesMsg("!wind " .. mapAvgWindStr .. " " .. mapAvgWindStr)
	end,

	sendDefaultWind = function(ev)
		spSendLuaRulesMsg("!wind off")
		dm.minWind, dm.maxWind = Game.windMin, Game.windMax
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

	toggleHighlight = function(ev, unitName, isCheckpoint)
		if isCheckpoint or not unitName then return end
		if ev.parameters.button == 1 then
			modelData.ignoreUnit(ev, unitName, isCheckpoint)
		elseif ev.parameters.button == 0 then
			dm.highlightedUnit = (dm.highlightedUnit == unitName) and "" or unitName
		end
	end,

	ignoreUnit = function(ev, unitName, isCheckpoint)
		if isCheckpoint or not unitName or modelData.ignoredUnits[unitName] then return end

		modelData.ignoredUnits[unitName] = true
		table.insert(modelData.ignoredUnitsList, unitName)
		dm.ignoredUnitsList = modelData.ignoredUnitsList
		dm.ignoredUnits = modelData.ignoredUnits

		if dm.highlightedUnit == unitName then dm.highlightedUnit = "" end
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
		if modelData.showRunsPanel then docRuns:Show() else docRuns:Hide() end
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= trackedTeamID or spGetGameFrame() <= ignoreUnitFinishedFrames then return end

	local ud = UnitDefs[unitDefID]
	if not ud then return end

	local hName = ud.translatedHumanName or ud.humanName or ud.name
	currentRunTimeline[#currentRunTimeline + 1] = {
		isCheckpoint = false,
		id = -1,
		timeStr = FormatTime(GetVirtualFrame()),
		humanName = hName,
		hidden = modelData.ignoredUnits[hName] or false
	}

	if dm then dm.currentTimeline = currentRunTimeline end
end

function widget:GameFrame(f)
	if f == 11 then
		currentRunTimeline[#currentRunTimeline + 1] = {
			isCheckpoint = true,
			id = 0,
			timeStr = "00:00",
			humanName = "CHECKPOINT 0",
			hidden = false
		}

		checkpointsData[0] = {
			virtualFrame = 0,
			timelineState = CloneTimeline(currentRunTimeline)
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
			runOffsetFrame = spGetGameFrame() - cp.virtualFrame
			ignoreUnitFinishedFrames = spGetGameFrame() + 15
			currentRunTimeline = cp.timelineState and CloneTimeline(cp.timelineState) or {}

			if dm then
				dm.currentTimeline = currentRunTimeline
				dm.clockTime = FormatTime(GetVirtualFrame())
			end
		end
	end
end

function widget:Update()
	if not dm then return end
	if isReplay or isSpec then
		local newTeam = Spring.GetSelectedTeamID()
		if newTeam and newTeam ~= trackedTeamID then
			trackedTeamID = newTeam
			currentRunTimeline = {}
			dm.currentTimeline = currentRunTimeline
		end
		-- Also check if we should update trackedTeamID because of spec state change
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
end

function widget:Shutdown()
	if docMain then docMain:Close(); docMain = nil end
	if docRuns then docRuns:Close(); docRuns = nil end
	if widget.rmlContext then widget.rmlContext:RemoveDataModel(MODEL_NAME) end
	widget.rmlContext = nil
end

function widget:RecvLuaMsg(message, playerID)
	local isActive0 = (message:sub(1, 19) == 'LobbyOverlayActive0')
	local isActive1 = (message:sub(1, 19) == 'LobbyOverlayActive1')

	if isActive0 or isActive1 then
		if docMain then (isActive0 and docMain.Show or docMain.Hide)(docMain) end
		if docRuns then (isActive0 and docRuns.Show or docRuns.Hide)(docRuns) end
	end
end
