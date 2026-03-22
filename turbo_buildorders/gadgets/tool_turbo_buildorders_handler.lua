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

-- Restore State
local pendingRestore = nil

-- Wind State
local minWind = Game.windMin
local maxWind = Game.windMax

-- Takes a snapshot of the entire board state and stores it under an ID
local function TakeCheckpoint(id)
	local cp = { units = {}, features = {}, res = {} }

	-- Save all units
	local allUnits = Spring.GetAllUnits()
	for _, uID in ipairs(allUnits) do
		local defID = Spring.GetUnitDefID(uID)
		local team = Spring.GetUnitTeam(uID)
		local x, y, z = Spring.GetUnitPosition(uID)
		local heading = Spring.GetUnitHeading(uID)

		local _, _, _, _, _, _, ux, uy, uz = Spring.GetUnitDirection(uID)

		local queue = Spring.GetUnitCommands(uID, -1)
		local savedCmds = {}
		if queue then
			for _, cmd in ipairs(queue) do
				table.insert(savedCmds, {
					id = cmd.id,
					params = cmd.params,
					options = cmd.options
				})
			end
		end

		local uData = {
			def=defID, team=team, x=x, y=y, z=z, h=heading,
			ux = ux or 0, uy = uy or 1, uz = uz or 0,
			cmds = savedCmds,
			oldID = uID
		}
		table.insert(cp.units, uData)
	end

	-- Save all features
	local allFeatures = Spring.GetAllFeatures()
	for _, fID in ipairs(allFeatures) do
		local defID = Spring.GetFeatureDefID(fID)
		local x, y, z = Spring.GetFeaturePosition(fID)
		local heading = Spring.GetFeatureHeading(fID)
		table.insert(cp.features, {def=defID, x=x, y=y, z=z, h=heading, oldID = fID})
	end

	-- Save resources
	local teams = Spring.GetTeamList()
	for _, t in ipairs(teams) do
		cp.res[t] = {
			m = Spring.GetTeamResources(t, "metal") or 1000,
			e = Spring.GetTeamResources(t, "energy") or 1000
		}
	end

	checkpoints[id] = cp
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
		pendingRestore.waitFrames = 2 -- Short delay before commands to ensure units are fully "alive"
		return
	end

	if pendingRestore.step == 2 then
		-- Step 3: Issue commands
		local oldToNewUnit = pendingRestore.oldToNewUnit
		local oldToNewFeature = pendingRestore.oldToNewFeature

		for _, u in ipairs(cp.units) do
			local nuID = u.nuID
			if nuID and u.cmds and #u.cmds > 0 then
				for _, cmd in ipairs(u.cmds) do
					local opts = cmd.options
					if type(opts) == "number" then
						if opts % 64 < 32 then opts = opts + 32 end
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
					-- Commands that take a single UnitID as param[1]
					if cmdID == CMD.GUARD or cmdID == CMD.REPAIR or cmdID == CMD.RECLAIM or cmdID == CMD.LOAD_UNITS then
						if #params == 1 then
							local oldTargetID = params[1]
							if oldToNewUnit[oldTargetID] then
								params[1] = oldToNewUnit[oldTargetID]
							elseif oldToNewFeature[oldTargetID] then
								params[1] = oldToNewFeature[oldTargetID]
							end
						end
					end

					Spring.GiveOrderToUnit(nuID, cmdID, params, opts)
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
	if frame > 10 and not autoSnapshotTaken then
		TakeCheckpoint(0) -- ID 0 is the starting frame
		autoSnapshotTaken = true
	end

	ProcessRestore(frame)
end

function gadget:RecvLuaMsg(msg, playerID)
	if string.sub(msg, 1, 9) == "!restart " then
		local id = tonumber(string.sub(msg, 10))
		if id then
			RestoreCheckpoint(id)
			Spring.SendMessageToPlayer(playerID, "State restored to Checkpoint " .. id)
			return true
		end
	elseif string.sub(msg, 1, 12) == "!checkpoint " then
		local id = tonumber(string.sub(msg, 13))
		if id then
			TakeCheckpoint(id)
			Spring.SendMessageToPlayer(playerID, "Checkpoint " .. id .. " saved!")
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
