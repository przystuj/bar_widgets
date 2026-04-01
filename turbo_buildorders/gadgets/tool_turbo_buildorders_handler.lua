function gadget:GetInfo()
	return {
		name      = "Quick Restart Handler",
		desc      = "Checkpoint current map state, restart to it, and lock wind",
		author    = "SuperKitowiec",
		date      = "2026",
		license   = "GNU GPL, v2 or later",
		layer     = 0,
		enabled   = true
	}
end

if not gadgetHandler:IsSyncedCode() then return end

local checkpoints = {}
local autoSnapshotTaken = false
local tempCheckpoint = nil
local pendingSave = nil

-- Restore State
local pendingRestore = nil

-- Wind State
local minWind = Game.windMin
local maxWind = Game.windMax

-- Cached Engine Functions
local spGetUnitIsBeingBuilt = Spring.GetUnitIsBeingBuilt
local spGetFactoryCommands = Spring.GetFactoryCommands

local waitFramesForValidSnapshot = 15000

local unitsUnderConstruction = 0

function gadget:UnitCreated(unitID, unitDefID, unitTeam, builderID)
	unitsUnderConstruction = unitsUnderConstruction + 1
end

function gadget:UnitFinished(unitID, unitDefID, unitTeam)
	unitsUnderConstruction = math.max(0, unitsUnderConstruction - 1)
end

function gadget:UnitDestroyed(unitID, unitDefID, unitTeam)
	local _, progress = spGetUnitIsBeingBuilt(unitID)
	if progress and progress < 1.0 then
		unitsUnderConstruction = math.max(0, unitsUnderConstruction - 1)
	end
end

local function IsAnythingBeingBuilt()
	return unitsUnderConstruction > 0
end
-------------------------------------------------------------------

-- Builds the snapshot table
local function CreateSnapshot()
	local cp = { units = {}, features = {}, res = {} }

	-- Save resources
	local teams = Spring.GetTeamList()
	for _, t in ipairs(teams) do
		cp.res[t] = {
			m = Spring.GetTeamResources(t, "metal") or 1000,
			e = Spring.GetTeamResources(t, "energy") or 1000
		}
	end

	-- Save all units
	local allUnits = Spring.GetAllUnits()
	for _, uID in ipairs(allUnits) do
		local beingBuilt, buildProgress = spGetUnitIsBeingBuilt(uID)

		-- Only save units that are 100% finished
		if not beingBuilt or buildProgress >= 1.0 then
			local defID = Spring.GetUnitDefID(uID)
			local team = Spring.GetUnitTeam(uID)
			local x, y, z = Spring.GetUnitPosition(uID)
			local heading = Spring.GetUnitHeading(uID)
			local _, _, _, _, _, _, ux, uy, uz = Spring.GetUnitDirection(uID)

			-- Save states (Crucial for Lab Repeat/On/Off)
			local states = Spring.GetUnitStates(uID)
			local savedStates = nil
			if states then
				savedStates = {
					repeatState = states["repeat"],
					onoff = states.onoff,
					movestate = states.movestate,
					firestate = states.firestate
				}
			end

			-- Save Standard Commands (Rally points, guard orders, etc.)
			local queue = Spring.GetUnitCommands(uID, -1)
			local savedCmds = {}
			if queue then
				for _, cmd in ipairs(queue) do
					table.insert(savedCmds, { id = cmd.id, params = cmd.params, options = cmd.options })
				end
			end

			-- Save Factory Build Orders
			local fQueue = spGetFactoryCommands(uID, -1)
			local savedFCmds = {}
			if fQueue then
				for _, cmd in ipairs(fQueue) do
					table.insert(savedFCmds, { id = cmd.id, params = cmd.params, options = cmd.options })
				end
			end

			table.insert(cp.units, {
				def=defID, team=team, x=x, y=y, z=z, h=heading,
				ux = ux or 0, uy = uy or 1, uz = uz or 0,
				cmds = savedCmds, fCmds = savedFCmds, states = savedStates, oldID = uID
			})
		end
	end

	-- Save features
	local allFeatures = Spring.GetAllFeatures()
	for _, fID in ipairs(allFeatures) do
		local defID = Spring.GetFeatureDefID(fID)
		local x, y, z = Spring.GetFeaturePosition(fID)
		local heading = Spring.GetFeatureHeading(fID)
		table.insert(cp.features, {def=defID, x=x, y=y, z=z, h=heading, oldID = fID})
	end

	return cp
end

-- Wipes the board and prepares for restoration
local function RestoreCheckpoint(id)
	local cp = checkpoints[id]
	if not cp then return end

	-- Step 1: Wipe everything
	local allUnits = Spring.GetAllUnits()
	for _, uID in ipairs(allUnits) do
		Spring.DestroyUnit(uID, false, true)
	end

	local allFeatures = Spring.GetAllFeatures()
	for _, fID in ipairs(allFeatures) do
		Spring.DestroyFeature(fID)
	end

	-- Queue the re-creation for later
	pendingRestore = {
		cp = cp,
		id = id,
		step = 1,
		waitFrames = 5,
		oldToNewUnit = {},
		oldToNewFeature = {}
	}
end

local function ProcessRestore(frame)
	if not pendingRestore then return end

	if pendingRestore.waitFrames > 0 then
		pendingRestore.waitFrames = pendingRestore.waitFrames - 1
		return
	end

	local cp = pendingRestore.cp

	if pendingRestore.step == 1 then
		-- Step 2: Re-create units and features
		for _, u in ipairs(cp.units) do
			local nuID = Spring.CreateUnit(u.def, u.x, u.y, u.z, 0, u.team)
			if nuID then
				Spring.SetUnitHeadingAndUpDir(nuID, u.h, u.ux, u.uy, u.uz)
				pendingRestore.oldToNewUnit[u.oldID] = nuID
				u.nuID = nuID -- temporary
			end
		end

		for _, f in ipairs(cp.features) do
			local nfID = Spring.CreateFeature(f.def, f.x, f.y, f.z, f.h or 0)
			if nfID then
				pendingRestore.oldToNewFeature[f.oldID] = nfID
			end
		end

		pendingRestore.step = 2
		pendingRestore.waitFrames = 5
		return
	end

	if pendingRestore.step == 2 then
		-- Step 3: Issue states and commands
		local oldToNewUnit = pendingRestore.oldToNewUnit
		local oldToNewFeature = pendingRestore.oldToNewFeature

		for _, u in ipairs(cp.units) do
			local nuID = u.nuID
			if nuID then
				-- Restore Unit States FIRST
				if u.states then
					if u.states.repeatState ~= nil then Spring.GiveOrderToUnit(nuID, CMD.REPEAT, {u.states.repeatState and 1 or 0}, 0) end
					if u.states.onoff ~= nil then Spring.GiveOrderToUnit(nuID, CMD.ONOFF, {u.states.onoff and 1 or 0}, 0) end
					if u.states.movestate ~= nil then Spring.GiveOrderToUnit(nuID, CMD.MOVE_STATE, {u.states.movestate}, 0) end
					if u.states.firestate ~= nil then Spring.GiveOrderToUnit(nuID, CMD.FIRE_STATE, {u.states.firestate}, 0) end
				end

				-- Restore Standard Queue (Rally points, guard orders, etc.)
				if u.cmds and #u.cmds > 0 then
					for _, cmd in ipairs(u.cmds) do
						local opts = cmd.options
						if type(opts) == "number" then
							if opts % 64 < 32 then opts = opts + 32 end
							if opts % 32 >= 16 then opts = opts - 16 end
						else
							local hasShift = false
							for _, o in ipairs(opts) do
								if o == "shift" then hasShift = true; break end
							end
							if not hasShift then table.insert(opts, "shift") end
						end

						-- Fix target IDs in params
						local params = {}
						for i, p in ipairs(cmd.params) do params[i] = p end

						local cmdID = cmd.id
						local validCommand = true

						if cmdID == CMD.GUARD or cmdID == CMD.REPAIR or cmdID == CMD.RECLAIM or cmdID == CMD.LOAD_UNITS then
							if #params == 1 then
								local oldTargetID = params[1]
								if oldToNewUnit[oldTargetID] then
									params[1] = oldToNewUnit[oldTargetID]
								elseif oldToNewFeature[oldTargetID] then
									params[1] = oldToNewFeature[oldTargetID]
								else
									validCommand = false
								end
							end
						end

						if validCommand then
							Spring.GiveOrderToUnit(nuID, cmdID, params, opts)
						end
					end
				end

				-- Restore Factory Build Queue
				if u.fCmds and #u.fCmds > 0 then
					for _, cmd in ipairs(u.fCmds) do
						local opts = cmd.options

						-- Clean the options: Keep exactly what was saved, but strip the INTERNAL flag
						if type(opts) == "number" then
							-- If the internal bit (16) is active, subtract it
							if opts % 32 >= 16 then opts = opts - 16 end
						else
							local cleanOpts = {}
							for _, o in ipairs(opts) do
								if o ~= "internal" then
									table.insert(cleanOpts, o)
								end
							end
							opts = cleanOpts
						end

						Spring.GiveOrderToUnit(nuID, cmd.id, cmd.params, opts)
					end
				end
			end
			u.nuID = nil
		end

		-- Restore resources
		local teams = Spring.GetTeamList()
		for _, t in ipairs(teams) do
			if cp.res[t] then
				Spring.SetTeamResource(t, "metal", cp.res[t].m)
				Spring.SetTeamResource(t, "energy", cp.res[t].e)
			end
		end

		pendingRestore = nil
	end
end

function gadget:GameFrame(frame)
	if frame % 30 == 0 then
		if not IsAnythingBeingBuilt() then
			tempCheckpoint = CreateSnapshot()
		end
	end

	if frame > 10 and not autoSnapshotTaken then
		checkpoints[0] = CreateSnapshot() -- ID 0 is the starting frame
		autoSnapshotTaken = true
	end

	-- Smart Checkpoint Logic
	if pendingSave then
		if not IsAnythingBeingBuilt() then
			checkpoints[pendingSave.id] = CreateSnapshot()
			Spring.SendMessageToPlayer(pendingSave.playerID, "Checkpoint " .. pendingSave.id .. " updated to a perfect frame!")
			Spring.SendLuaUIMsg("TurboCheckpointUpdated " .. pendingSave.id .. " " .. frame)
			pendingSave = nil
		elseif frame > pendingSave.timeout then
			Spring.SendMessageToPlayer(pendingSave.playerID, "Checkpoint " .. pendingSave.id .. " waiting period timed out.")
			Spring.SendLuaUIMsg("TurboCheckpointTimeout " .. pendingSave.id)
			pendingSave = nil
		end
	end

	ProcessRestore(frame)
end

function gadget:RecvLuaMsg(msg, playerID)
	if string.sub(msg, 1, 9) == "!restart " then
		local id = tonumber(string.sub(msg, 10))
		if id then
			RestoreCheckpoint(id)
			Spring.SendMessageToPlayer(playerID, "State restored to Checkpoint " .. id)
			Spring.SendLuaUIMsg("TurboRestart " .. id)
			return true
		end
	elseif string.sub(msg, 1, 12) == "!checkpoint " then
		local id = tonumber(string.sub(msg, 13))
		if id then
			-- If a DIFFERENT checkpoint is pending, cancel the old one
			if pendingSave and pendingSave.id ~= id then
				Spring.SendLuaUIMsg("TurboCheckpointCancelled " .. pendingSave.id)
			end
			-- If it's the SAME id, it just silently overwrites the wait timer below

			if IsAnythingBeingBuilt() then
				if tempCheckpoint then
					checkpoints[id] = tempCheckpoint
					Spring.SendMessageToPlayer(playerID, "Unit in progress! Saved fallback. Waiting for an opening to update...")
				else
					Spring.SendMessageToPlayer(playerID, "Unit in progress! Waiting for a clean frame...")
				end
				pendingSave = {
					id = id,
					timeout = Spring.GetGameFrame() + waitFramesForValidSnapshot,
					playerID = playerID
				}
				Spring.SendLuaUIMsg("TurboCheckpointPending " .. id)
			else
				checkpoints[id] = CreateSnapshot()
				pendingSave = nil
				Spring.SendMessageToPlayer(playerID, "Checkpoint " .. id .. " saved precisely.")
				Spring.SendLuaUIMsg("TurboCheckpointSaved " .. id)
			end
			return true
		end
	elseif string.sub(msg, 1, 6) == "!wind " then
		local args = string.sub(msg, 7)
		if args == "off" then
			Spring.SetWind(minWind, maxWind)
		else
			local wx, wz = string.match(args, "^([%-%d%.]+)%s+([%-%d%.]+)$")
			if wx and wz then Spring.SetWind(wx, wz) end
		end
		return true
	end
	return false
end
