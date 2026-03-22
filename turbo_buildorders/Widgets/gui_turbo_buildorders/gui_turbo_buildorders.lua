if not RmlUi then return end

local widget = widget ---@type Widget

function widget:GetInfo()
	return {
		name      = "Turbo Build Orders UI",
		desc      = "UI panel for snapshots, restarts, and wind control",
		author    = "You",
		date      = "2026",
		license   = "MIT",
		layer     = 0,
		enabled   = true
	}
end

local MODEL_NAME = "quick_restart_model"
local RML_MAIN_PATH = "LuaUI/Widgets/gui_turbo_buildorders/gui_turbo_buildorders_main.rml"
local RML_RUNS_PATH = "LuaUI/Widgets/gui_turbo_buildorders/gui_turbo_buildorders_runs.rml"

local docMain
local docRuns
local dm

-- Time and Timeline Variables
local runOffsetFrame = 0
local ignoreUnitFinishedFrames = 0

local nextCheckpointId = 1
local checkpointsData = {}

local currentRunTimeline = {}

local savedRunsHistory = {}

local windFunctions = VFS.Include('common/wind_functions.lua')
local mapAvgWindStr = windFunctions.getAverageWind()

local function GetVirtualFrame()
	return math.max(0, Spring.GetGameFrame() - runOffsetFrame)
end

local function FormatTime(frames)
	local totalSeconds = math.floor(frames / 30)
	local m = math.floor(totalSeconds / 60)
	local s = totalSeconds % 60
	return string.format("%02d:%02d", m, s)
end

local modelData = {
	minWind = 10,
	maxWind = 10,
	avgWindText = mapAvgWindStr,
	clockTime = "00:00",

	-- Main Panel Timeline
	currentTimeline = {},

	-- History Panel Data
	savedRuns = savedRunsHistory,
	showRunsPanel = false,
	hasSavedRun = false,

	addCheckpoint = function(ev)
		local cpId = nextCheckpointId
		nextCheckpointId = nextCheckpointId + 1

		local vFrame = GetVirtualFrame()

		local marker = {
			isCheckpoint = true,
			id = cpId,
			timeStr = FormatTime(vFrame),
			humanName = "CHECKPOINT " .. cpId
		}
		table.insert(currentRunTimeline, marker)

		-- Capture the exact state of the timeline at this moment
		local timelineCopy = {}
		for _, v in ipairs(currentRunTimeline) do
			table.insert(timelineCopy, {
				isCheckpoint = v.isCheckpoint,
				id = v.id,
				timeStr = v.timeStr,
				humanName = v.humanName
			})
		end

		checkpointsData[cpId] = {
			virtualFrame = vFrame,
			timelineState = timelineCopy
		}

		dm.currentTimeline = currentRunTimeline
		Spring.SendLuaRulesMsg("!checkpoint " .. cpId)
	end,

	restartToCheckpoint = function(ev, id)
		if not checkpointsData[id] then return end

		local cp = checkpointsData[id]
		runOffsetFrame = Spring.GetGameFrame() - cp.virtualFrame
		ignoreUnitFinishedFrames = Spring.GetGameFrame() + 15

		-- Wipe the "future" and restore the timeline exactly to how it was
		currentRunTimeline = {}
		if cp.timelineState then
			for _, v in ipairs(cp.timelineState) do
				table.insert(currentRunTimeline, {
					isCheckpoint = v.isCheckpoint,
					id = v.id,
					timeStr = v.timeStr,
					humanName = v.humanName
				})
			end
		end

		dm.currentTimeline = currentRunTimeline
		dm.clockTime = FormatTime(GetVirtualFrame())
		Spring.SendLuaRulesMsg("!restart " .. id)
	end,

	saveRun = function(ev)
		local currentMetal = Spring.GetTeamResources(Spring.GetMyTeamID(), "metal")
		local currentEnergy = Spring.GetTeamResources(Spring.GetMyTeamID(), "energy")

		local runCopy = {}
		for i, v in ipairs(currentRunTimeline) do
			table.insert(runCopy, {
				isCheckpoint = v.isCheckpoint,
				timeStr = v.timeStr,
				humanName = v.humanName
			})
		end

		table.insert(savedRunsHistory, 1, {
			id = #savedRunsHistory + 1,
			metal = math.floor(currentMetal or 0),
			energy = math.floor(currentEnergy or 0),
			timeline = runCopy
		})

		dm.savedRuns = savedRunsHistory
		dm.hasSavedRun = true
		dm.showRunsPanel = true
	end,

	removeRun = function(ev, index)
		if not savedRunsHistory[index + 1] then return end
		table.remove(savedRunsHistory, index + 1)
		dm.savedRuns = savedRunsHistory
		dm.hasSavedRun = (#savedRunsHistory > 0)
	end,

	toggleRunsPanel = function(ev)
		dm.showRunsPanel = not dm.showRunsPanel
	end,

	sendCommand = function(ev, command)
		Spring.SendLuaRulesMsg(command)
	end,

	sendWind = function(ev)
		local minW = tonumber(dm.minWind) or 10
		local maxW = tonumber(dm.maxWind) or 10
		Spring.Echo(string.format("Wind set to %.1f-%.1f", minW, maxW))
		Spring.SendLuaRulesMsg("!wind " .. minW .. " " .. maxW)
	end,

	sendAvgWind = function(ev)
		local val = mapAvgWindStr
		dm.minWind = val
		dm.maxWind = val
		Spring.Echo(string.format("Wind set to %.1f-%.1f", val, val))
		Spring.SendLuaRulesMsg("!wind " .. val .. " " .. val)
	end,

	sendDefaultWind = function(ev)
		Spring.SendLuaRulesMsg("!wind off")
		dm.minWind = Game.windMin
		dm.maxWind = Game.windMax
		Spring.Echo(string.format("Wind set to %.1f-%.1f", Game.windMin, Game.windMax))
	end,

	onMinWindChange = function(ev)
		local val = tonumber(ev.parameters.value)
		if val then
			dm.minWind = val
			if dm.minWind > dm.maxWind then
				dm.maxWind = dm.minWind
			end
		end
	end,

	onMaxWindChange = function(ev)
		local val = tonumber(ev.parameters.value)
		if val then
			dm.maxWind = val
			if dm.maxWind < dm.minWind then
				dm.minWind = dm.maxWind
			end
		end
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
		docRuns:Show()
	end
end

function widget:UnitFinished(unitID, unitDefID, unitTeam)
	if unitTeam ~= Spring.GetMyTeamID() then return end
	if Spring.GetGameFrame() <= ignoreUnitFinishedFrames then return end

	local ud = UnitDefs[unitDefID]
	if not ud then return end

	table.insert(currentRunTimeline, {
		isCheckpoint = false,
		id = -1,
		timeStr = FormatTime(GetVirtualFrame()),
		humanName = ud.translatedHumanName or ud.humanName or ud.name
	})

	if dm then dm.currentTimeline = currentRunTimeline end
end

function widget:GameFrame(f)
	if f == 11 then
		-- Automatically map Checkpoint 0 to the start of the game
		local cpId = 0
		local vFrame = 0

		local marker = {
			isCheckpoint = true,
			id = cpId,
			timeStr = "00:00",
			humanName = "CHECKPOINT 0"
		}
		table.insert(currentRunTimeline, marker)

		local timelineCopy = {}
		for _, v in ipairs(currentRunTimeline) do
			table.insert(timelineCopy, {
				isCheckpoint = v.isCheckpoint,
				id = v.id,
				timeStr = v.timeStr,
				humanName = v.humanName
			})
		end

		checkpointsData[cpId] = {
			virtualFrame = vFrame,
			timelineState = timelineCopy
		}
		if dm then dm.currentTimeline = currentRunTimeline end
	end
end

-- Catch the gadget's print message just in case the user typed !restart manually via chat
function widget:AddConsoleLine(msg, priority)
	if msg and string.find(msg, "State restored to Checkpoint") then
		local idStr = string.match(msg, "State restored to Checkpoint (%d+)")
		local id = tonumber(idStr)
		if id and checkpointsData[id] then
			local cp = checkpointsData[id]
			runOffsetFrame = Spring.GetGameFrame() - cp.virtualFrame
			ignoreUnitFinishedFrames = Spring.GetGameFrame() + 15

			-- Wipe future events if restoring via chat command
			currentRunTimeline = {}
			if cp.timelineState then
				for _, v in ipairs(cp.timelineState) do
					table.insert(currentRunTimeline, {
						isCheckpoint = v.isCheckpoint,
						id = v.id,
						timeStr = v.timeStr,
						humanName = v.humanName
					})
				end
			end

			if dm then
				dm.currentTimeline = currentRunTimeline
				dm.clockTime = FormatTime(GetVirtualFrame())
			end
		end
	end
end

function widget:Update()
	if not dm then return end

	local newTimeStr = FormatTime(GetVirtualFrame())
	if dm.clockTime ~= newTimeStr then
		dm.clockTime = newTimeStr
	end
end

function widget:Shutdown()
	if docMain then
		docMain:Close()
		docMain = nil
	end
	if docRuns then
		docRuns:Close()
		docRuns = nil
	end
	if widget.rmlContext then
		widget.rmlContext:RemoveDataModel(MODEL_NAME)
	end
	widget.rmlContext = nil
end


function widget:RecvLuaMsg(message, playerID)
	if docMain then
		if message:sub(1, 19) == 'LobbyOverlayActive0' then
			docMain:Show()
		elseif message:sub(1, 19) == 'LobbyOverlayActive1' then
			docMain:Hide()
		end
	end
	if docRuns then
		if message:sub(1, 19) == 'LobbyOverlayActive0' then
			docRuns:Show()
		elseif message:sub(1, 19) == 'LobbyOverlayActive1' then
			docRuns:Hide()
		end
	end
end
