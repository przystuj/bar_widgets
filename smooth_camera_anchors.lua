function widget:GetInfo()
    return {
        name = "Camera Suite",
        desc = "Camera anchors with smooth transitions. Follow unit in fps mode. Track unit in fps mode.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true,
        version = 0.3,
    }
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- Transition settings
    TRANSITION = {
        DURATION = 2.0,
        MIN_DURATION = 0.0,
        STEPS_PER_SECOND = 60
    },

    -- FPS camera settings
    FPS = {
        DEFAULT_HEIGHT_OFFSET = 60, -- This will be updated dynamically based on unit height
        DEFAULT_FORWARD_OFFSET = -100,
        DEFAULT_SIDE_OFFSET = 0,
        HEIGHT_OFFSET = 60, -- This will be updated dynamically based on unit height
        FORWARD_OFFSET = -100,
        SIDE_OFFSET = 0
    },

    SMOOTHING = {
        POSITION_FACTOR = 0.05, -- Lower = smoother but more lag (0.0-1.0)
        ROTATION_FACTOR = 0.02, -- Lower = smoother but more lag (0.0-1.0)
        FPS_FACTOR = 0.15, -- Specific for FPS mode
        STATIONARY_FACTOR = 0.1, -- Specific for stationary mode
        MODE_TRANSITION_FACTOR = 0.05  -- For smoothing between camera modes
    }
}

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------

local STATE = {
    -- Widget state
    enabled = false,
    originalCameraState = nil,

    -- Anchors
    anchors = {},

    -- Transition
    transition = {
        active = false,
        startTime = nil,
        steps = {},
        currentStepIndex = 1,
        currentAnchorIndex = nil
    },

    -- Tracking
    tracking = {
        mode = nil, -- 'fps' or 'stationary'
        unitID = nil,
        inFreeCameraMode = false,
        stationaryCamState = nil,
        graceTimer = nil, -- Timer for grace period
        lastUnitID = nil, -- Store the last tracked unit
        unitOffsets = {}, -- Store individual unit camera offsets

        -- Smoothing data
        lastUnitPos = { x = 0, y = 0, z = 0 },
        lastCamPos = { x = 0, y = 0, z = 0 },
        lastCamDir = { x = 0, y = 0, z = 0 },
        lastRotation = { rx = 0, ry = 0, rz = 0 },

        -- Mode transition tracking
        prevMode = nil, -- Previous camera mode
        modeTransition = false, -- Is transitioning between modes
        transitionStartState = nil, -- Start camera state for transition
        transitionStartTime = nil   -- When transition started
    },

    -- Delayed actions
    delayed = {
        frame = nil,
        callback = nil
    }
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------

local Util = {}

-- Debug functions
function Util.dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. Util.dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

function Util.log(o)
    Spring.Echo(Util.dump(o))
end

-- Deep copy function for tables
function Util.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = Util.deepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Interpolation functions
function Util.easeInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

function Util.lerp(a, b, t)
    return a + (b - a) * t
end

-- Normalize angle to be within -pi to pi range
function Util.normalizeAngle(angle)
    local twoPi = 2 * math.pi
    angle = angle % twoPi
    if angle > math.pi then
        angle = angle - twoPi
    end
    return angle
end

-- Interpolate between two angles, always taking the shortest path
function Util.lerpAngle(a, b, t)
    -- Normalize both angles to -pi to pi range
    a = Util.normalizeAngle(a)
    b = Util.normalizeAngle(b)

    -- Find the shortest path
    local diff = b - a

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return a + diff * t
end

-- Get unit height
function Util.getUnitHeight(unitID)
    if not Spring.ValidUnitID(unitID) then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    -- Get unit definition ID and access height from UnitDefs
    local unitDefID = Spring.GetUnitDefID(unitID)
    if not unitDefID then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    local unitDef = UnitDefs[unitDefID]
    if not unitDef then
        return CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    end

    -- Return unit height or default if not available
    return unitDef.height + 20 or CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
end

-- Disable tracking
function Util.disableTracking(camState)
    -- Start mode transition if we're disabling from a tracking mode
    if STATE.tracking.mode then
        Util.beginModeTransition(nil)

        -- If we have a specific camera state to return to (for stationary mode)
        if STATE.tracking.mode == 'stationary' and camState then
            -- Don't set it immediately, we'll transition to it
            STATE.tracking.transitionTargetState = camState
        end
    end

    STATE.tracking.unitID = nil
    STATE.tracking.inFreeCameraMode = false
    STATE.tracking.stationaryCamState = nil
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
end

function Util.smoothStep(current, target, factor)
    return current + (target - current) * factor
end

-- Smooth interpolation between two angles
function Util.smoothStepAngle(current, target, factor)
    -- Normalize both angles to -pi to pi range
    current = Util.normalizeAngle(current)
    target = Util.normalizeAngle(target)

    -- Find the shortest path
    local diff = target - current

    -- If the difference is greater than pi, we need to go the other way around
    if diff > math.pi then
        diff = diff - 2 * math.pi
    elseif diff < -math.pi then
        diff = diff + 2 * math.pi
    end

    return current + diff * factor
end

function Util.beginModeTransition(newMode)
    -- Save the previous mode
    STATE.tracking.prevMode = STATE.tracking.mode
    STATE.tracking.mode = newMode

    -- Only start a transition if we're switching between different modes
    if STATE.tracking.prevMode ~= newMode then
        STATE.tracking.modeTransition = true
        STATE.tracking.transitionStartState = Spring.GetCameraState()
        STATE.tracking.transitionStartTime = Spring.GetTimer()

        -- Store current camera position as last position to smooth from
        local camState = Spring.GetCameraState()
        STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
        STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
        STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
    end
end

--------------------------------------------------------------------------------
-- WIDGET ENABLE/DISABLE FUNCTIONS
--------------------------------------------------------------------------------

local WidgetControl = {}

-- Enable the widget
function WidgetControl.enable()
    if STATE.enabled then
        Spring.Echo("Camera Suite is already enabled")
        return
    end

    -- Save current camera state before enabling
    STATE.originalCameraState = Spring.GetCameraState()

    -- Set required configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)

    -- Get map dimensions to position camera properly
    local mapX = Game.mapSizeX
    local mapZ = Game.mapSizeZ

    -- Calculate center of map
    local centerX = mapX / 2
    local centerZ = mapZ / 2

    -- Calculate good height to view the entire map
    -- Using the longer dimension to ensure everything is visible
    local mapDiagonal = math.sqrt(mapX * mapX + mapZ * mapZ)
    local viewHeight = mapDiagonal

    -- Switch to FPS camera mode and center on map
    local camStatePatch = {
        name = "fps",
        mode = 0, -- FPS camera mode
        px = centerX,
        py = viewHeight,
        pz = centerZ,
        rx = math.pi, -- Slightly tilted for better perspective
    }
    Spring.SetCameraState(camStatePatch, 0.5)

    STATE.enabled = true
    Spring.Echo("Camera Suite enabled - camera centered on map")
end

-- Disable the widget
function WidgetControl.disable()
    if not STATE.enabled then
        Spring.Echo("Camera Suite is already disabled")
        return
    end

    -- Reset any active features
    if STATE.tracking.mode then
        Util.disableTracking()
    end

    if STATE.transition.active then
        STATE.transition.active = false
    end

    -- Reset configuration
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)

    -- Restore original camera state
    if STATE.originalCameraState then
        Spring.SetCameraState(STATE.originalCameraState, 0.5)
        STATE.originalCameraState = nil
    end

    STATE.enabled = false
    Spring.Echo("Camera Suite disabled")
end

-- Toggle widget state
function WidgetControl.toggle()
    if STATE.enabled then
        WidgetControl.disable()
    else
        WidgetControl.enable()
    end
    return true
end

--------------------------------------------------------------------------------
-- CAMERA TRANSITION FUNCTIONS
--------------------------------------------------------------------------------

local CameraTransition = {}

-- Generate a sequence of camera states for smooth transition
function CameraTransition.generateSteps(startState, endState, numSteps)
    local steps = {}

    -- Camera parameters to interpolate
    local cameraParams = {
        "zoomFromHeight", "fov", "gndOffset", "dist", "flipped",
        "vx", "vy", "vz", "ax", "ay", "az", "height",
        "rotZ"
    }

    -- Camera rotation parameters that need special angle interpolation
    local rotationParams = {
        "rx", "ry", "rz", "rotX", "rotY"
    }

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = Util.easeInOutCubic(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = Util.lerp(startState.px, endState.px, easedT)
        statePatch.py = Util.lerp(startState.py, endState.py, easedT)
        statePatch.pz = Util.lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = Util.lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = Util.lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = Util.lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters (non-rotational)
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = Util.lerp(startState[param], endState[param], easedT)
            end
        end

        -- Camera rotation parameters (need special angle interpolation)
        for _, param in ipairs(rotationParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = Util.lerpAngle(startState[param], endState[param], easedT)
            end
        end

        -- Always keep FPS mode
        statePatch.mode = 0
        statePatch.name = "fps"

        steps[i] = statePatch
    end

    -- Ensure the last step is exactly the end state but keep FPS mode
    steps[numSteps] = Util.deepCopy(endState)
    steps[numSteps].mode = 0
    steps[numSteps].name = "fps"

    return steps
end

-- Handle the transition update
function CameraTransition.update()
    if not STATE.transition.active then
        return
    end

    local now = Spring.GetTimer()

    -- Calculate current progress
    local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
    local targetProgress = math.min(elapsed / CONFIG.TRANSITION.DURATION, 1.0)

    -- Determine which step to use based on progress
    local totalSteps = #STATE.transition.steps
    local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

    -- Only update if we need to move to a new step
    if targetStep > STATE.transition.currentStepIndex then
        STATE.transition.currentStepIndex = targetStep

        -- Apply the camera state for this step
        local state = STATE.transition.steps[STATE.transition.currentStepIndex]
        Spring.SetCameraState(state, 0)

        -- Check if we've reached the end
        if STATE.transition.currentStepIndex >= totalSteps then
            STATE.transition.active = false
            STATE.transition.currentAnchorIndex = nil
        end
    end
end

-- Start a transition between camera states
function CameraTransition.start(endState, duration)
    -- Generate transition steps for smooth transition
    local startState = Spring.GetCameraState()
    local numSteps = math.max(2, math.floor(duration * CONFIG.TRANSITION.STEPS_PER_SECOND))

    -- Ensure the target state is in FPS mode
    endState.mode = 0
    endState.name = "fps"

    STATE.transition.steps = CameraTransition.generateSteps(startState, endState, numSteps)
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
end

--------------------------------------------------------------------------------
-- FPS CAMERA FUNCTIONS
--------------------------------------------------------------------------------

local FPSCamera = {}

-- Toggle FPS camera attached to a unit
function FPSCamera.toggle(unitID)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- If no unitID provided, use the first selected unit
    if not unitID then
        local selectedUnits = Spring.GetSelectedUnits()
        if #selectedUnits > 0 then
            unitID = selectedUnits[1]
        else
            Spring.Echo("No unit selected for FPS view")
            return
        end
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Spring.Echo("Invalid unit ID for FPS view")
        return
    end

    -- If we're already tracking this exact unit in FPS mode, turn it off
    if STATE.tracking.mode == 'fps' and STATE.tracking.unitID == unitID then
        -- Save current offsets before disabling
        STATE.tracking.unitOffsets[unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET
        }

        Util.disableTracking()
        Spring.Echo("FPS camera detached")
        return
    end

    -- Otherwise we're either starting fresh or switching units
    Spring.Echo("FPS camera attached to unit " .. unitID)

    -- Check if we have stored offsets for this unit
    if STATE.tracking.unitOffsets[unitID] then
        -- Use stored offsets
        CONFIG.FPS.HEIGHT_OFFSET = STATE.tracking.unitOffsets[unitID].height
        CONFIG.FPS.FORWARD_OFFSET = STATE.tracking.unitOffsets[unitID].forward
        CONFIG.FPS.SIDE_OFFSET = STATE.tracking.unitOffsets[unitID].side

        Spring.Echo("Using previous camera offsets for unit " .. unitID)
    else
        -- Get unit height for the default offset
        local unitHeight = Util.getUnitHeight(unitID)
        CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET

        -- Initialize storage for this unit
        STATE.tracking.unitOffsets[unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET
        }

        Spring.Echo("Using new camera offsets for unit " .. unitID .. " with height: " .. unitHeight)
    end

    -- Begin mode transition from previous mode to FPS mode
    Util.beginModeTransition('fps')
    STATE.tracking.unitID = unitID
    STATE.tracking.inFreeCameraMode = false

    -- Switch to FPS camera mode - this will smoothly transition now
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }
    Spring.SetCameraState(camStatePatch, 0)
end

-- Update the FPS camera position to match the tracked unit
function FPSCamera.update()
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Spring.Echo("Unit no longer exists, detaching FPS camera")
        Util.disableTracking()
        return
    end

    -- Get unit position and vectors
    local x, y, z = Spring.GetUnitPosition(STATE.tracking.unitID)
    local front, up, right = Spring.GetUnitVectors(STATE.tracking.unitID)

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Store unit position for smoothing calculations
    STATE.tracking.lastUnitPos = { x = x, y = y, z = z }

    -- Apply height offset along the unit's up vector
    if CONFIG.FPS.HEIGHT_OFFSET ~= 0 then
        x = x + upX * CONFIG.FPS.HEIGHT_OFFSET
        y = y + upY * CONFIG.FPS.HEIGHT_OFFSET
        z = z + upZ * CONFIG.FPS.HEIGHT_OFFSET
    end

    -- Apply forward offset if needed
    if CONFIG.FPS.FORWARD_OFFSET ~= 0 then
        x = x + frontX * CONFIG.FPS.FORWARD_OFFSET
        y = y + frontY * CONFIG.FPS.FORWARD_OFFSET
        z = z + frontZ * CONFIG.FPS.FORWARD_OFFSET
    end

    -- Apply side offset if needed
    if CONFIG.FPS.SIDE_OFFSET ~= 0 then
        x = x + rightX * CONFIG.FPS.SIDE_OFFSET
        y = y + rightY * CONFIG.FPS.SIDE_OFFSET
        z = z + rightZ * CONFIG.FPS.SIDE_OFFSET
    end

    -- Get current camera state
    local camState = Spring.GetCameraState()

    -- Check if we're still in FPS mode
    if camState.mode ~= 0 then
        -- Force back to FPS mode
        camState.mode = 0
        camState.name = "fps"
    end

    -- Prepare camera state patch
    local camStatePatch = {
        mode = 0,
        name = "fps"
    }

    -- If this is the first update, initialize last positions
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = x, y = y, z = z }
        STATE.tracking.lastCamDir = { x = frontX, y = frontY, z = frontZ }
        STATE.tracking.lastRotation = {
            rx = 1.8,
            ry = -(Spring.GetUnitHeading(STATE.tracking.unitID, true) + math.pi),
            rz = 0
        }
    end

    -- Determine smoothing factor based on whether we're in a mode transition
    local posFactor = CONFIG.SMOOTHING.FPS_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        posFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- Smooth camera position
    camStatePatch.px = Util.smoothStep(STATE.tracking.lastCamPos.x, x, posFactor)
    camStatePatch.py = Util.smoothStep(STATE.tracking.lastCamPos.y, y, posFactor)
    camStatePatch.pz = Util.smoothStep(STATE.tracking.lastCamPos.z, z, posFactor)

    -- If not in free camera mode, smooth rotation and direction too
    if not STATE.tracking.inFreeCameraMode then
        -- Smooth direction vector
        camStatePatch.dx = Util.smoothStep(STATE.tracking.lastCamDir.x, frontX, rotFactor)
        camStatePatch.dy = Util.smoothStep(STATE.tracking.lastCamDir.y, frontY, rotFactor)
        camStatePatch.dz = Util.smoothStep(STATE.tracking.lastCamDir.z, frontZ, rotFactor)

        -- Calculate target rotations
        local targetRy = -(Spring.GetUnitHeading(STATE.tracking.unitID, true) + math.pi)
        local targetRx = 1.8
        local targetRz = 0

        -- Smooth rotations
        camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor)
        camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor)
        camStatePatch.rz = Util.smoothStep(STATE.tracking.lastRotation.rz, targetRz, rotFactor)

        -- Update last rotation values
        STATE.tracking.lastRotation.rx = camStatePatch.rx
        STATE.tracking.lastRotation.ry = camStatePatch.ry
        STATE.tracking.lastRotation.rz = camStatePatch.rz

        -- Update last direction values
        STATE.tracking.lastCamDir.x = camStatePatch.dx
        STATE.tracking.lastCamDir.y = camStatePatch.dy
        STATE.tracking.lastCamDir.z = camStatePatch.dz
    else
        -- In free camera mode, only update position
        -- Keep rotations from current state
        camStatePatch.dx = camState.dx
        camStatePatch.dy = camState.dy
        camStatePatch.dz = camState.dz
        camStatePatch.rx = camState.rx
        camStatePatch.ry = camState.ry
        camStatePatch.rz = camState.rz
    end

    -- Update last camera position
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz

    Spring.SetCameraState(camStatePatch, 0)
end

-- Toggle free camera mode
function FPSCamera.toggleFreeCam()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- Only works if we're tracking a unit in FPS mode
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
        Spring.Echo("Free camera only works when tracking a unit in FPS mode")
        return
    end

    -- Start a transition when toggling free camera
    STATE.tracking.modeTransition = true
    STATE.tracking.transitionStartTime = Spring.GetTimer()

    -- Toggle free camera mode
    STATE.tracking.inFreeCameraMode = not STATE.tracking.inFreeCameraMode

    if STATE.tracking.inFreeCameraMode then
        Spring.Echo("Free camera mode enabled - use mouse to rotate view")
    else
        Spring.Echo("Free camera mode disabled - view follows unit orientation")
    end
end

-- Adjust camera offsets
function FPSCamera.adjustOffset(offsetType, amount)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- Make sure we have a unit to track
    if not STATE.tracking.unitID then
        Spring.Echo("No unit being tracked")
        return
    end

    if offsetType == "height" then
        CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.HEIGHT_OFFSET + amount
    elseif offsetType == "forward" then
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.FORWARD_OFFSET + amount
    elseif offsetType == "side" then
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.SIDE_OFFSET + amount
    end

    -- Update stored offsets for the current unit
    if STATE.tracking.unitID then
        if not STATE.tracking.unitOffsets[STATE.tracking.unitID] then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET
        }
    end
end

-- Reset camera offsets to defaults
function FPSCamera.resetOffsets()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- If we have a tracked unit, get its height for the default height offset
    if STATE.tracking.mode == 'fps' and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
        local unitHeight = Util.getUnitHeight(STATE.tracking.unitID)
        CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.HEIGHT_OFFSET = unitHeight
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET

        -- Update stored offsets for this unit
        STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
            height = CONFIG.FPS.HEIGHT_OFFSET,
            forward = CONFIG.FPS.FORWARD_OFFSET,
            side = CONFIG.FPS.SIDE_OFFSET
        }

        Spring.Echo("Reset camera offsets for unit " .. STATE.tracking.unitID .. " to defaults")
    else
        CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
        Spring.Echo("FPS camera offsets reset to defaults")
    end
end

--------------------------------------------------------------------------------
-- STATIONARY TRACKING FUNCTIONS
--------------------------------------------------------------------------------

local StationaryTracking = {}

-- Toggle stationary camera tracking
function StationaryTracking.toggle()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return true
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no unit is selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'stationary' then
            Util.disableTracking(STATE.tracking.stationaryCamState)
            Spring.Echo("Stationary camera tracking disabled")
        else
            Spring.Echo("No unit selected for stationary tracking")
        end
        return true
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in stationary mode, turn it off
    if STATE.tracking.mode == 'stationary' and STATE.tracking.unitID == selectedUnitID then
        Util.disableTracking(STATE.tracking.stationaryCamState)
        Spring.Echo("Stationary camera tracking disabled")
        return true
    end

    -- Otherwise we're either starting fresh or switching units
    Spring.Echo("Stationary camera tracking enabled. Camera will stay fixed but follow unit " .. selectedUnitID)

    -- Get current camera state and ensure it's FPS mode
    local camState = Spring.GetCameraState()
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
        Spring.SetCameraState(camState, 0)
    end

    -- Begin mode transition
    Util.beginModeTransition('stationary')
    STATE.tracking.unitID = selectedUnitID
    STATE.tracking.stationaryCamState = Spring.GetCameraState()

    return true
end

-- Update stationary camera tracking
function StationaryTracking.update()
    if STATE.tracking.mode ~= 'stationary' or not STATE.tracking.unitID or not STATE.tracking.stationaryCamState then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Spring.Echo("Tracked unit no longer exists, disabling stationary tracking")
        Util.disableTracking()
        return
    end

    -- Check if we're still in FPS mode
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        -- Force back to FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        Spring.SetCameraState(currentState, 0)
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Calculate direction vector from camera to unit
    local dirX = unitX - STATE.tracking.stationaryCamState.px
    local dirY = unitY - STATE.tracking.stationaryCamState.py
    local dirZ = unitZ - STATE.tracking.stationaryCamState.pz

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Calculate appropriate rotation for FPS camera
    local targetRy = -math.atan2(dirX, dirZ) - math.pi

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    local targetRx = -((math.atan2(dirY, horizontalLength) - math.pi) / 1.8)

    -- Create camera state patch
    local camStatePatch = {
        -- Keep camera in the fixed position
        px = STATE.tracking.stationaryCamState.px,
        py = STATE.tracking.stationaryCamState.py,
        pz = STATE.tracking.stationaryCamState.pz,

        -- Keep FPS camera mode
        mode = 0,
        name = "fps"
    }

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        STATE.tracking.lastCamDir = { x = dirX, y = dirY, z = dirZ }
        STATE.tracking.lastRotation = { rx = targetRx, ry = targetRy, rz = 0 }
    end

    -- Determine smoothing factor based on whether we're in a mode transition
    local dirFactor = CONFIG.SMOOTHING.STATIONARY_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        dirFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- Smooth direction vector
    camStatePatch.dx = Util.smoothStep(STATE.tracking.lastCamDir.x, dirX, dirFactor)
    camStatePatch.dy = Util.smoothStep(STATE.tracking.lastCamDir.y, dirY, dirFactor)
    camStatePatch.dz = Util.smoothStep(STATE.tracking.lastCamDir.z, dirZ, dirFactor)

    -- Smooth rotations
    camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, targetRx, rotFactor)
    camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, targetRy, rotFactor)
    camStatePatch.rz = 0

    -- Update last values
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--------------------------------------------------------------------------------
-- CAMERA ANCHOR FUNCTIONS
--------------------------------------------------------------------------------

local CameraAnchor = {}

-- Set a camera anchor
function CameraAnchor.set(index)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return true
    end

    index = tonumber(index)
    if index and index >= 0 and index <= 9 then
        local currentState = Spring.GetCameraState()
        -- Ensure the anchor is in FPS mode
        currentState.mode = 0
        currentState.name = "fps"
        STATE.anchors[index] = currentState
        Spring.Echo("Saved camera anchor: " .. index)
    end
    return true
end

-- Focus on a camera anchor with smooth transition
function CameraAnchor.focus(index)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and index <= 9 and STATE.anchors[index]) then
        return true
    end

    -- Cancel tracking if active
    if STATE.tracking.mode then
        Spring.Echo(STATE.tracking.mode .. " tracking disabled when moving to anchor")
        Util.disableTracking()
    end

    -- Cancel transition if we click the same anchor we're currently moving to
    if STATE.transition.active and STATE.transition.currentAnchorIndex == index then
        STATE.transition.active = false
        STATE.transition.currentAnchorIndex = nil
        Spring.Echo("Transition canceled")
        return true
    end

    -- Cancel any in-progress transition when starting a new one
    if STATE.transition.active then
        STATE.transition.active = false
        Spring.Echo("Canceled previous transition")
    end

    -- Check if we should do an instant transition (duration = 0)
    if CONFIG.TRANSITION.DURATION <= 0 then
        -- Instant camera jump
        local targetState = Util.deepCopy(STATE.anchors[index])
        -- Ensure the target state is in FPS mode
        targetState.mode = 0
        targetState.name = "fps"
        Spring.SetCameraState(targetState, 0)
        Spring.Echo("Instantly jumped to camera anchor: " .. index)
        return true
    end

    -- Start transition
    CameraTransition.start(STATE.anchors[index], CONFIG.TRANSITION.DURATION)
    STATE.transition.currentAnchorIndex = index

    Spring.Echo("Loading camera anchor: " .. index)
    return true
end

-- Adjust transition duration
function CameraAnchor.adjustDuration(amount)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    CONFIG.TRANSITION.DURATION = math.max(CONFIG.TRANSITION.MIN_DURATION, CONFIG.TRANSITION.DURATION + amount)

    if CONFIG.TRANSITION.DURATION == 0 then
        Spring.Echo("Transition duration: INSTANT")
    else
        Spring.Echo("Transition duration: " .. CONFIG.TRANSITION.DURATION .. "s")
    end
end

--------------------------------------------------------------------------------
-- SPRING ENGINE CALLINS
--------------------------------------------------------------------------------

function widget:SelectionChanged(selectedUnits)
    if not STATE.enabled then
        return
    end

    -- If no units are selected and tracking is active, start grace period
    if #selectedUnits == 0 then
        if STATE.tracking.mode then
            -- Store the current tracked unit ID
            STATE.tracking.lastUnitID = STATE.tracking.unitID

            -- Start grace period timer (1 second)
            STATE.tracking.graceTimer = Spring.GetTimer()
        end
        return
    end

    -- If units are selected, cancel any active grace period
    if STATE.tracking.graceTimer then
        STATE.tracking.graceTimer = nil
    end

    -- Get the first selected unit
    local unitID = selectedUnits[1]

    -- Update tracking if it's enabled
    if STATE.tracking.mode and STATE.tracking.unitID ~= unitID then
        -- Save current offsets for the previous unit if in FPS mode
        if STATE.tracking.mode == 'fps' and STATE.tracking.unitID then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
                height = CONFIG.FPS.HEIGHT_OFFSET,
                forward = CONFIG.FPS.FORWARD_OFFSET,
                side = CONFIG.FPS.SIDE_OFFSET
            }
        end

        -- Switch tracking to the new unit
        STATE.tracking.unitID = unitID

        -- For FPS mode, load appropriate offsets
        if STATE.tracking.mode == 'fps' then
            if STATE.tracking.unitOffsets[unitID] then
                -- Use saved offsets
                CONFIG.FPS.HEIGHT_OFFSET = STATE.tracking.unitOffsets[unitID].height
                CONFIG.FPS.FORWARD_OFFSET = STATE.tracking.unitOffsets[unitID].forward
                CONFIG.FPS.SIDE_OFFSET = STATE.tracking.unitOffsets[unitID].side
                Spring.Echo("FPS camera switched to unit " .. unitID .. " with saved offsets")
            else
                -- Get new default height for this unit
                local unitHeight = Util.getUnitHeight(unitID)
                CONFIG.FPS.DEFAULT_HEIGHT_OFFSET = unitHeight
                CONFIG.FPS.HEIGHT_OFFSET = unitHeight
                CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
                CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET

                -- Initialize storage for this unit
                STATE.tracking.unitOffsets[unitID] = {
                    height = CONFIG.FPS.HEIGHT_OFFSET,
                    forward = CONFIG.FPS.FORWARD_OFFSET,
                    side = CONFIG.FPS.SIDE_OFFSET
                }

                Spring.Echo("FPS camera switched to unit " .. unitID .. " with new offsets")
            end
        else
            Spring.Echo("Stationary tracking switched to unit " .. unitID)
        end
    end
end

function widget:Update()
    if not STATE.enabled then
        return
    end

    -- Check grace period timer if it exists
    if STATE.tracking.graceTimer and STATE.tracking.mode then
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.graceTimer)

        -- If grace period expired (1 second), disable tracking
        if elapsed > 1.0 then
            Util.disableTracking(STATE.tracking.stationaryCamState)
            Spring.Echo("Camera tracking disabled - no units selected (after grace period)")
        end
    end

    -- If we're in a mode transition but not tracking any unit,
    -- then we're transitioning back to normal camera from a tracking mode
    if STATE.tracking.modeTransition and not STATE.tracking.mode then
        local currentState = Spring.GetCameraState()

        -- Get transition factor
        local transitionFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- If we have a target state to transition to (from stationary mode)
        if STATE.tracking.transitionTargetState then
            -- Smoothly transition to the target state
            local targetState = STATE.tracking.transitionTargetState

            -- Apply smoothing to position
            currentState.px = Util.smoothStep(currentState.px, targetState.px, transitionFactor)
            currentState.py = Util.smoothStep(currentState.py, targetState.py, transitionFactor)
            currentState.pz = Util.smoothStep(currentState.pz, targetState.pz, transitionFactor)

            -- Apply smoothing to direction
            currentState.dx = Util.smoothStep(currentState.dx, targetState.dx, transitionFactor)
            currentState.dy = Util.smoothStep(currentState.dy, targetState.dy, transitionFactor)
            currentState.dz = Util.smoothStep(currentState.dz, targetState.dz, transitionFactor)

            -- Apply smoothing to rotation
            currentState.rx = Util.smoothStep(currentState.rx, targetState.rx, transitionFactor)
            currentState.ry = Util.smoothStepAngle(currentState.ry, targetState.ry, transitionFactor)
            currentState.rz = Util.smoothStep(currentState.rz, targetState.rz, transitionFactor)

            -- Apply updated state
            Spring.SetCameraState(currentState, 0)

            -- Check if we should end the transition (after ~1 second)
            local now = Spring.GetTimer()
            local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
            if elapsed > 1.0 then
                STATE.tracking.modeTransition = false
                STATE.tracking.transitionTargetState = nil

                -- Final smoothing is done, apply exact target state
                Spring.SetCameraState(targetState, 0)
            end
        else
            -- We're transitioning to free camera
            -- Just let the transition time out
            local now = Spring.GetTimer()
            local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
            if elapsed > 1.0 then
                STATE.tracking.modeTransition = false
            end
        end
    end

    -- Handle smooth transitions between anchors
    CameraTransition.update()

    -- Handle camera tracking updates
    if STATE.tracking.mode == 'fps' then
        FPSCamera.update()
    elseif STATE.tracking.mode == 'stationary' then
        StationaryTracking.update()
    end

    -- Check for delayed position storage callback
    if STATE.delayed.frame and Spring.GetGameFrame() >= STATE.delayed.frame then
        if STATE.delayed.callback then
            STATE.delayed.callback()
        end
        STATE.delayed.frame = nil
        STATE.delayed.callback = nil
    end
end

function widget:Initialize()
    -- Widget starts in disabled state, user must enable it manually
    STATE.enabled = false

    -- Register widget control command
    widgetHandler:AddAction("toggle_camera_suite", function()
        return WidgetControl.toggle()
    end, nil, 'p')

    -- Register camera anchor commands
    widgetHandler:AddAction("set_smooth_camera_anchor", function(_, index)
        return CameraAnchor.set(index)
    end, nil, 'p')

    widgetHandler:AddAction("focus_smooth_camera_anchor", function(_, index)
        return CameraAnchor.focus(index)
    end, nil, 'p')

    widgetHandler:AddAction("decrease_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(-1)
    end, nil, 'p')

    widgetHandler:AddAction("increase_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(1)
    end, nil, 'p')

    -- Register FPS camera commands
    widgetHandler:AddAction("toggle_fps_camera", function()
        return FPSCamera.toggle()
    end, nil, 'p')

    widgetHandler:AddAction("fps_height_offset_up", function()
        FPSCamera.adjustOffset("height", 10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_height_offset_down", function()
        FPSCamera.adjustOffset("height", -10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_forward_offset_up", function()
        FPSCamera.adjustOffset("forward", 10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_forward_offset_down", function()
        FPSCamera.adjustOffset("forward", -10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_side_offset_right", function()
        FPSCamera.adjustOffset("side", 10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_side_offset_left", function()
        FPSCamera.adjustOffset("side", -10)
    end, nil, 'pR')

    widgetHandler:AddAction("fps_toggle_free_cam", function()
        FPSCamera.toggleFreeCam()
    end, nil, 'p')

    widgetHandler:AddAction("fps_reset_defaults", function()
        FPSCamera.resetOffsets()
    end, nil, 'p')

    -- Register stationary tracking command
    widgetHandler:AddAction("toggle_stationary_tracking", function()
        return StationaryTracking.toggle()
    end, nil, 'p')

    Spring.Echo("Camera Suite loaded but disabled. Use /toggle_camera_suite to enable.")
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
end