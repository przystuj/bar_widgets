function widget:GetInfo()
    return {
        name = "Camera Suite",
        desc = "Camera anchors with smooth transitions. Follow unit in fps mode. Track unit in fps mode.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 0,
        enabled = true,
        version = 0.4,
        handler = true,
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
        ROTATION_FACTOR = 0.008, -- Lower = smoother but more lag (0.0-1.0)
        FPS_FACTOR = 0.15, -- Specific for FPS mode
        TRACKING_FACTOR = 0.05, -- Specific for Tracking Camera mode
        MODE_TRANSITION_FACTOR = 0.04  -- For smoothing between camera modes
    },

    ORBIT = {
        DEFAULT_HEIGHT_FACTOR = 4, -- Default height is 10x unit height
        DEFAULT_DISTANCE = 300, -- Default distance from unit
        DEFAULT_SPEED = 0.0005, -- Radians per frame
        HEIGHT = nil, -- Will be set dynamically based on unit height
        DISTANCE = 300, -- Distance from unit
        SPEED = 0.01, -- Orbit speed in radians per frame
        AUTO_ORBIT_DELAY = 3, -- Seconds of no movement to trigger auto orbit
        AUTO_ORBIT_ENABLED = true, -- Whether auto-orbit is enabled
        AUTO_ORBIT_SMOOTHING_FACTOR = 5
    },
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
    lastUsedAnchor = nil,

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
        mode = nil, -- 'fps' or 'tracking_camera' or 'fixed_point'
        unitID = nil,
        targetUnitID = nil, -- Store the ID of the unit we're looking at
        inFreeCameraMode = false,
        graceTimer = nil, -- Timer for grace period
        lastUnitID = nil, -- Store the last tracked unit
        unitOffsets = {}, -- Store individual unit camera offsets

        -- For fixed point tracking
        fixedPoint = nil, -- {x, y, z}

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
        frame = nil, -- Game frame when the callback should execute
        callback = nil  -- Function to call when frame is reached
    },

    orbit = {
        angle = 0, -- Current orbit angle in radians
        lastPosition = nil, -- Last unit position to detect movement
        stationaryTimer = nil, -- Timer to track how long unit has been stationary
        autoOrbitActive = false, -- Whether auto-orbit is currently active
        unitOffsets = {}, -- Store individual unit orbit settings
        originalTransitionFactor = nil, -- Store original transition factor
    },
}

--------------------------------------------------------------------------------
-- UTILITY FUNCTIONS
--------------------------------------------------------------------------------
local CMD_SET_FIXED_LOOK_POINT = 455625
local CMD_SET_FIXED_LOOK_POINT_DEFINITION = {
    id = CMD_SET_FIXED_LOOK_POINT,
    type = CMDTYPE.ICON_UNIT_OR_MAP,
    name = 'Set Fixed Look Point',
    tooltip = 'Click on a location to focus camera on while following unit',
    cursor = 'settarget',
    action = 'set_fixed_look_point',
}

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
function Util.disableTracking()
    -- Start mode transition if we're disabling from a tracking mode
    if STATE.tracking.mode then
        Util.beginModeTransition(nil)
    end

    -- Restore original transition factor if needed
    if STATE.orbit.originalTransitionFactor then
        CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.orbit.originalTransitionFactor
        STATE.orbit.originalTransitionFactor = nil
    end

    STATE.tracking.unitID = nil
    STATE.tracking.targetUnitID = nil  -- Clear the target unit ID
    STATE.tracking.inFreeCameraMode = false
    STATE.tracking.graceTimer = nil
    STATE.tracking.lastUnitID = nil
    STATE.tracking.fixedPoint = nil
    STATE.tracking.mode = nil

    -- Reset orbit-specific states
    STATE.orbit.autoOrbitActive = false
    STATE.orbit.stationaryTimer = nil
    STATE.orbit.lastPosition = nil
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

-- Calculate camera direction and rotation to look at a point
function Util.calculateLookAtPoint(camPos, targetPos)
    -- Calculate direction vector from camera to target
    local dirX = targetPos.x - camPos.x
    local dirY = targetPos.y - camPos.y
    local dirZ = targetPos.z - camPos.z

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Calculate appropriate rotation for FPS camera
    local ry = -math.atan2(dirX, dirZ) - math.pi

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    local rx = -((math.atan2(dirY, horizontalLength) - math.pi) / 1.8)

    return {
        dx = dirX,
        dy = dirY,
        dz = dirZ,
        rx = rx,
        ry = ry,
        rz = 0
    }
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
    local viewHeight = mapDiagonal / 3

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

        -- Apply the base camera state (position)
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

    -- Disable fixed point tracking if active
    STATE.tracking.fixedPoint = nil

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

-- Set a fixed point for the camera to look at while following a unit
function FPSCamera.setFixedLookPoint(cmdParams)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- Only works if we're tracking a unit in FPS mode
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
        Spring.Echo("Fixed point tracking only works when in FPS mode")
        return false
    end

    local x, y, z
    STATE.tracking.targetUnitID = nil -- Reset target unit ID

    -- Process different types of input
    if cmdParams then
        if #cmdParams == 1 then
            -- Clicked on a unit
            local unitID = cmdParams[1]
            if Spring.ValidUnitID(unitID) then
                -- Store the target unit ID for continuous tracking
                STATE.tracking.targetUnitID = unitID
                x, y, z = Spring.GetUnitPosition(unitID)
                Spring.Echo("Camera will follow current unit but look at unit " .. unitID)
            end
        elseif #cmdParams == 3 then
            -- Clicked on ground/feature
            x, y, z = cmdParams[1], cmdParams[2], cmdParams[3]
        end
    else
        -- Legacy behavior - use current mouse position
        local _, pos = Spring.TraceScreenRay(Spring.GetMouseState(), true)
        if pos then
            x, y, z = pos[1], pos[2], pos[3]
        end
    end

    if not x or not y or not z then
        Spring.Echo("Could not find a valid position")
        return false
    end

    -- Set the fixed point
    STATE.tracking.fixedPoint = {
        x = x,
        y = y,
        z = z
    }

    -- Switch to fixed point mode
    STATE.tracking.mode = 'fixed_point'

    if not STATE.tracking.targetUnitID then
        Spring.Echo("Camera will follow unit but look at fixed point")
    end

    return true
end

-- Clear fixed point tracking
function FPSCamera.clearFixedLookPoint()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    if STATE.tracking.mode == 'fixed_point' and STATE.tracking.unitID then
        -- Switch back to FPS mode
        STATE.tracking.mode = 'fps'
        STATE.tracking.fixedPoint = nil
        STATE.tracking.targetUnitID = nil  -- Clear the target unit ID
        Spring.Echo("Fixed point tracking disabled, returning to FPS mode")
    end
end

-- Update the FPS camera position to match the tracked unit
function FPSCamera.update()
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
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

    -- Handle different cases for direction and rotation
    if STATE.tracking.mode == 'fixed_point' then
        -- Update fixed point if we're tracking a unit
        if STATE.tracking.targetUnitID and Spring.ValidUnitID(STATE.tracking.targetUnitID) then
            -- Get the current position of the target unit
            local targetX, targetY, targetZ = Spring.GetUnitPosition(STATE.tracking.targetUnitID)
            STATE.tracking.fixedPoint = {
                x = targetX,
                y = targetY,
                z = targetZ
            }
        end

        -- Fixed point tracking - look at the fixed point
        local lookDir = Util.calculateLookAtPoint(
                { x = camStatePatch.px, y = camStatePatch.py, z = camStatePatch.pz },
                STATE.tracking.fixedPoint
        )

        -- Apply the look direction with smoothing
        camStatePatch.dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, rotFactor)
        camStatePatch.dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, rotFactor)
        camStatePatch.dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, rotFactor)

        -- Apply rotation angles with smoothing
        camStatePatch.rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor)
        camStatePatch.ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor)
        camStatePatch.rz = Util.smoothStep(STATE.tracking.lastRotation.rz, lookDir.rz, rotFactor)
    elseif not STATE.tracking.inFreeCameraMode then
        -- ... rest of the original code for normal FPS mode ...
        -- Normal FPS mode - follow unit orientation
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
    else
        -- ... rest of the original code for free camera mode ...
        -- In free camera mode, only update position
        -- Keep rotations from current state
        camStatePatch.dx = camState.dx
        camStatePatch.dy = camState.dy
        camStatePatch.dz = camState.dz
        camStatePatch.rx = camState.rx
        camStatePatch.ry = camState.ry
        camStatePatch.rz = camState.rz

    end


    -- ... rest of the update function ...
    -- Update last rotation values
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry
    STATE.tracking.lastRotation.rz = camStatePatch.rz

    -- Update last direction values
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz

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
    if (STATE.tracking.mode ~= 'fps' and STATE.tracking.mode ~= 'fixed_point') or not STATE.tracking.unitID then
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

    -- Print the updated offsets
    Spring.Echo("Camera offsets for unit " .. STATE.tracking.unitID .. ":")
    Spring.Echo("  Height: " .. CONFIG.FPS.HEIGHT_OFFSET)
    Spring.Echo("  Forward: " .. CONFIG.FPS.FORWARD_OFFSET)
    Spring.Echo("  Side: " .. CONFIG.FPS.SIDE_OFFSET)
end

-- Reset camera offsets to defaults
function FPSCamera.resetOffsets()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- If we have a tracked unit, get its height for the default height offset
    if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
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
-- TRACKING CAMERA FUNCTIONS
--------------------------------------------------------------------------------

local TrackingCamera = {}

-- Toggle tracking camera
function TrackingCamera.toggle()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return true
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        -- If no unit is selected and tracking is currently on, turn it off
        if STATE.tracking.mode == 'tracking_camera' then
            Util.disableTracking()
            Spring.Echo("Tracking Camera disabled")
        else
            Spring.Echo("No unit selected for Tracking Camera")
        end
        return true
    end

    local selectedUnitID = selectedUnits[1]

    -- If we're already tracking this exact unit in tracking camera mode, turn it off
    if STATE.tracking.mode == 'tracking_camera' and STATE.tracking.unitID == selectedUnitID then
        Util.disableTracking()
        Spring.Echo("Tracking Camera disabled")
        return true
    end

    -- Otherwise we're either starting fresh or switching units
    Spring.Echo("Tracking Camera enabled. Camera will track unit " .. selectedUnitID)

    -- Get current camera state and ensure it's FPS mode
    local camState = Spring.GetCameraState()
    if camState.mode ~= 0 then
        camState.mode = 0
        camState.name = "fps"
        Spring.SetCameraState(camState, 0)
    end

    -- Begin mode transition
    Util.beginModeTransition('tracking_camera')
    STATE.tracking.unitID = selectedUnitID

    return true
end

-- Update tracking camera
function TrackingCamera.update()
    if STATE.tracking.mode ~= 'tracking_camera' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Spring.Echo("Tracked unit no longer exists, disabling Tracking Camera")
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
    local targetPos = { x = unitX, y = unitY, z = unitZ }

    -- Get current camera position
    local camPos = { x = currentState.px, y = currentState.py, z = currentState.pz }

    -- Calculate look direction to the unit
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Determine smoothing factor based on whether we're in a mode transition
    local dirFactor = CONFIG.SMOOTHING.TRACKING_FACTOR
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

    -- Initialize last values if needed
    if STATE.tracking.lastCamDir.x == 0 and STATE.tracking.lastCamDir.y == 0 and STATE.tracking.lastCamDir.z == 0 then
        STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
        STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
    end

    -- Create camera state patch - only update direction, not position
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth direction vector
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, dirFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, dirFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, dirFactor),

        -- Smooth rotations
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state - only updating direction and rotation
    Spring.SetCameraState(camStatePatch, 0)
end

--------------------------------------------------------------------------------
-- ORBITING CAMERA FUNCTIONS
--------------------------------------------------------------------------------

local OrbitingCamera = {}

-- Toggle orbiting camera
function OrbitingCamera.toggle(unitID)
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
            Spring.Echo("No unit selected for Orbiting view")
            return
        end
    end

    -- Check if it's a valid unit
    if not Spring.ValidUnitID(unitID) then
        Spring.Echo("Invalid unit ID for Orbiting view")
        return
    end

    -- If we're already tracking this exact unit in Orbiting mode, turn it off
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID == unitID then
        -- Save current orbiting settings before disabling
        STATE.orbit.unitOffsets[unitID] = {
            speed = CONFIG.ORBIT.SPEED
        }

        Util.disableTracking()
        Spring.Echo("Orbiting camera detached")
        return
    end

    -- Get unit height for the default height offset
    local unitHeight = Util.getUnitHeight(unitID)

    -- Check if we have stored settings for this unit
    if STATE.orbit.unitOffsets[unitID] then
        -- Use stored settings
        CONFIG.ORBIT.SPEED = STATE.orbit.unitOffsets[unitID].speed
        Spring.Echo("Using previous orbit speed for unit " .. unitID)
    else
        -- Use default settings
        CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

        -- Initialize storage for this unit
        STATE.orbit.unitOffsets[unitID] = {
            speed = CONFIG.ORBIT.SPEED
        }
    end

    -- Set height based on unit height
    CONFIG.ORBIT.HEIGHT = unitHeight * CONFIG.ORBIT.DEFAULT_HEIGHT_FACTOR
    CONFIG.ORBIT.DISTANCE = CONFIG.ORBIT.DEFAULT_DISTANCE

    -- Begin mode transition from previous mode to orbit mode
    Util.beginModeTransition('orbit')
    STATE.tracking.unitID = unitID

    -- Initialize orbit angle based on current camera position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(unitID)
    local camState = Spring.GetCameraState()

    -- Calculate current angle based on camera position relative to unit
    STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

    -- Initialize the last position for auto-orbit feature
    STATE.orbit.lastPosition = { x = unitX, y = unitY, z = unitZ }
    STATE.orbit.stationaryTimer = nil
    STATE.orbit.autoOrbitActive = false

    -- Switch to FPS camera mode for consistent behavior
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }
    Spring.SetCameraState(camStatePatch, 0)

    Spring.Echo("Orbiting camera attached to unit " .. unitID)
end

-- Update the Orbiting camera position
function OrbitingCamera.update()
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.tracking.unitID) then
        Spring.Echo("Unit no longer exists, detaching Orbiting camera")
        Util.disableTracking()
        return
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

    -- Update orbit angle
    STATE.orbit.angle = STATE.orbit.angle + CONFIG.ORBIT.SPEED

    -- Calculate camera position on the orbit circle
    local camX = unitX + CONFIG.ORBIT.DISTANCE * math.sin(STATE.orbit.angle)
    local camY = unitY + CONFIG.ORBIT.HEIGHT
    local camZ = unitZ + CONFIG.ORBIT.DISTANCE * math.cos(STATE.orbit.angle)

    -- Create camera state looking at the unit
    local camPos = { x = camX, y = camY, z = camZ }
    local targetPos = { x = unitX, y = unitY, z = unitZ }
    local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

    -- Determine smoothing factor based on whether we're in a mode transition
    local smoothFactor = CONFIG.SMOOTHING.POSITION_FACTOR
    local rotFactor = CONFIG.SMOOTHING.ROTATION_FACTOR

    if STATE.tracking.modeTransition then
        -- Use a special transition factor during mode changes
        smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
        rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR

        -- Check if we should end the transition (after ~1 second)
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- If this is the first update, initialize last positions
    if STATE.tracking.lastCamPos.x == 0 and STATE.tracking.lastCamPos.y == 0 and STATE.tracking.lastCamPos.z == 0 then
        STATE.tracking.lastCamPos = { x = camX, y = camY, z = camZ }
        STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
        STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
    end

    -- Prepare camera state patch with smoothed values
    local camStatePatch = {
        mode = 0,
        name = "fps",

        -- Smooth camera position
        px = Util.smoothStep(STATE.tracking.lastCamPos.x, camX, smoothFactor),
        py = Util.smoothStep(STATE.tracking.lastCamPos.y, camY, smoothFactor),
        pz = Util.smoothStep(STATE.tracking.lastCamPos.z, camZ, smoothFactor),

        -- Smooth direction
        dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
        dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
        dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

        -- Smooth rotation
        rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
        ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
        rz = 0
    }

    -- Update last values for next frame
    STATE.tracking.lastCamPos.x = camStatePatch.px
    STATE.tracking.lastCamPos.y = camStatePatch.py
    STATE.tracking.lastCamPos.z = camStatePatch.pz
    STATE.tracking.lastCamDir.x = camStatePatch.dx
    STATE.tracking.lastCamDir.y = camStatePatch.dy
    STATE.tracking.lastCamDir.z = camStatePatch.dz
    STATE.tracking.lastRotation.rx = camStatePatch.rx
    STATE.tracking.lastRotation.ry = camStatePatch.ry

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

-- Adjust orbit speed
function OrbitingCamera.adjustSpeed(amount)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- Make sure we have a unit to orbit around
    if STATE.tracking.mode ~= 'orbit' or not STATE.tracking.unitID then
        Spring.Echo("No unit being orbited")
        return
    end

    CONFIG.ORBIT.SPEED = math.max(0.0001, math.min(0.05, CONFIG.ORBIT.SPEED + amount))

    -- Update stored settings for the current unit
    if STATE.tracking.unitID then
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end

        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.ORBIT.SPEED
    end

    -- Print the updated settings
    Spring.Echo("Orbit speed for unit " .. STATE.tracking.unitID .. ": " .. CONFIG.ORBIT.SPEED)
end

-- Reset orbit settings to defaults
function OrbitingCamera.resetSettings()
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return
    end

    -- If we have a tracked unit, reset its orbit speed
    if STATE.tracking.mode == 'orbit' and STATE.tracking.unitID and Spring.ValidUnitID(STATE.tracking.unitID) then
        CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

        -- Update stored settings for this unit
        if not STATE.orbit.unitOffsets[STATE.tracking.unitID] then
            STATE.orbit.unitOffsets[STATE.tracking.unitID] = {}
        end
        STATE.orbit.unitOffsets[STATE.tracking.unitID].speed = CONFIG.ORBIT.SPEED

        Spring.Echo("Reset orbit speed for unit " .. STATE.tracking.unitID .. " to default")
    else
        Spring.Echo("No unit being orbited")
    end
end

-- Check for unit movement for auto-orbit feature
function OrbitingCamera.checkUnitMovement()
    -- Only check if we're in FPS mode with a valid unit and auto-orbit is enabled
    if STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID or not CONFIG.ORBIT.AUTO_ORBIT_ENABLED then
        return
    end

    -- Get current unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
    local currentPos = { x = unitX, y = unitY, z = unitZ }

    -- If this is the first check, just store the position
    if not STATE.orbit.lastPosition then
        STATE.orbit.lastPosition = currentPos
        return
    end

    -- Check if unit has moved
    local epsilon = 0.1  -- Small threshold to account for floating point precision
    local hasMoved = math.abs(currentPos.x - STATE.orbit.lastPosition.x) > epsilon or
            math.abs(currentPos.y - STATE.orbit.lastPosition.y) > epsilon or
            math.abs(currentPos.z - STATE.orbit.lastPosition.z) > epsilon

    if hasMoved then
        -- Unit is moving, reset timer
        STATE.orbit.stationaryTimer = nil

        -- If auto-orbit is active, transition back to FPS
        if STATE.orbit.autoOrbitActive then
            STATE.orbit.autoOrbitActive = false

            -- Begin transition from orbit back to FPS mode
            -- We need to do this manually as we're already in "fps" tracking mode
            STATE.tracking.modeTransition = true
            STATE.tracking.transitionStartTime = Spring.GetTimer()

            -- Restore original transition factor
            if STATE.orbit.originalTransitionFactor then
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = STATE.orbit.originalTransitionFactor
                STATE.orbit.originalTransitionFactor = nil
            end

            -- Store current camera position as last position to smooth from
            local camState = Spring.GetCameraState()
            STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
            STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
            STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }
        end
    else
        -- Unit is stationary
        if not STATE.orbit.stationaryTimer then
            -- Start timer
            STATE.orbit.stationaryTimer = Spring.GetTimer()
        else
            -- Check if we've been stationary long enough
            local now = Spring.GetTimer()
            local elapsed = Spring.DiffTimers(now, STATE.orbit.stationaryTimer)

            if elapsed > CONFIG.ORBIT.AUTO_ORBIT_DELAY and not STATE.orbit.autoOrbitActive then
                -- Transition to auto-orbit
                STATE.orbit.autoOrbitActive = true

                -- Initialize orbit settings with default values
                local unitHeight = Util.getUnitHeight(STATE.tracking.unitID)
                CONFIG.ORBIT.HEIGHT = unitHeight * CONFIG.ORBIT.DEFAULT_HEIGHT_FACTOR
                CONFIG.ORBIT.DISTANCE = CONFIG.ORBIT.DEFAULT_DISTANCE
                CONFIG.ORBIT.SPEED = CONFIG.ORBIT.DEFAULT_SPEED

                -- Initialize orbit angle based on current camera position
                local camState = Spring.GetCameraState()
                STATE.orbit.angle = math.atan2(camState.px - unitX, camState.pz - unitZ)

                -- Begin transition from FPS to orbit
                -- We need to do this manually as we're already in "fps" tracking mode
                STATE.tracking.modeTransition = true
                STATE.tracking.transitionStartTime = Spring.GetTimer()

                -- Store current camera position as last position to smooth from
                STATE.tracking.lastCamPos = { x = camState.px, y = camState.py, z = camState.pz }
                STATE.tracking.lastCamDir = { x = camState.dx, y = camState.dy, z = camState.dz }
                STATE.tracking.lastRotation = { rx = camState.rx, ry = camState.ry, rz = camState.rz }

                -- Store original transition factor and use a more delayed transition
                STATE.orbit.originalTransitionFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR
                CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR
            end

        end
        -- Update last position
        STATE.orbit.lastPosition = currentPos
    end

    -- Handle actual auto-orbit camera update
    function OrbitingCamera.updateAutoOrbit()
        if not STATE.orbit.autoOrbitActive or STATE.tracking.mode ~= 'fps' or not STATE.tracking.unitID then
            return
        end

        -- Auto-orbit uses the same update logic as manual orbit, but without changing tracking.mode
        -- Get unit position
        local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)

        -- Update orbit angle
        STATE.orbit.angle = STATE.orbit.angle + CONFIG.ORBIT.SPEED

        -- Calculate camera position on the orbit circle
        local camX = unitX + CONFIG.ORBIT.DISTANCE * math.sin(STATE.orbit.angle)
        local camY = unitY + CONFIG.ORBIT.HEIGHT
        local camZ = unitZ + CONFIG.ORBIT.DISTANCE * math.cos(STATE.orbit.angle)

        -- Create camera state looking at the unit
        local camPos = { x = camX, y = camY, z = camZ }
        local targetPos = { x = unitX, y = unitY, z = unitZ }
        local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

        -- Determine smoothing factor - use a very smooth transition for auto-orbit
        local smoothFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR
        local rotFactor = CONFIG.SMOOTHING.MODE_TRANSITION_FACTOR / CONFIG.ORBIT.AUTO_ORBIT_SMOOTHING_FACTOR

        -- Prepare camera state patch with smoothed values
        local camStatePatch = {
            mode = 0,
            name = "fps",

            -- Smooth camera position
            px = Util.smoothStep(STATE.tracking.lastCamPos.x, camX, smoothFactor),
            py = Util.smoothStep(STATE.tracking.lastCamPos.y, camY, smoothFactor),
            pz = Util.smoothStep(STATE.tracking.lastCamPos.z, camZ, smoothFactor),

            -- Smooth direction
            dx = Util.smoothStep(STATE.tracking.lastCamDir.x, lookDir.dx, smoothFactor),
            dy = Util.smoothStep(STATE.tracking.lastCamDir.y, lookDir.dy, smoothFactor),
            dz = Util.smoothStep(STATE.tracking.lastCamDir.z, lookDir.dz, smoothFactor),

            -- Smooth rotation
            rx = Util.smoothStep(STATE.tracking.lastRotation.rx, lookDir.rx, rotFactor),
            ry = Util.smoothStepAngle(STATE.tracking.lastRotation.ry, lookDir.ry, rotFactor),
            rz = 0
        }

        -- Update last values for next frame
        STATE.tracking.lastCamPos.x = camStatePatch.px
        STATE.tracking.lastCamPos.y = camStatePatch.py
        STATE.tracking.lastCamPos.z = camStatePatch.pz
        STATE.tracking.lastCamDir.x = camStatePatch.dx
        STATE.tracking.lastCamDir.y = camStatePatch.dy
        STATE.tracking.lastCamDir.z = camStatePatch.dz
        STATE.tracking.lastRotation.rx = camStatePatch.rx
        STATE.tracking.lastRotation.ry = camStatePatch.ry

        -- Apply camera state
        Spring.SetCameraState(camStatePatch, 0)
    end

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

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    -- Always disable any tracking when moving to an anchor
    if STATE.tracking.mode then
        -- Disable tracking without planning to restore it
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

function CameraAnchor.focusAndTrack(index)
    if not STATE.enabled then
        Spring.Echo("Camera Suite must be enabled first")
        return true
    end

    index = tonumber(index)
    if not (index and index >= 0 and index <= 9 and STATE.anchors[index]) then
        Spring.Echo("Invalid or unset camera anchor: " .. (index or "nil"))
        return true
    end

    -- Store the anchor we're moving to
    STATE.lastUsedAnchor = index

    -- Get the selected unit to track
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        Spring.Echo("No unit selected for tracking during anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    local unitID = selectedUnits[1]
    if not Spring.ValidUnitID(unitID) then
        Spring.Echo("Invalid unit for tracking during anchor transition")
        -- Just do a normal anchor transition
        return CameraAnchor.focus(index)
    end

    -- Cancel any in-progress transitions
    if STATE.transition.active then
        STATE.transition.active = false
        Spring.Echo("Canceled previous transition")
    end

    -- Disable any existing tracking modes to avoid conflicts
    if STATE.tracking.mode then
        Util.disableTracking()
    end

    -- Create a specialized transition that maintains focus on the unit
    local startState = Spring.GetCameraState()
    local endState = Util.deepCopy(STATE.anchors[index])

    -- Ensure both states are in FPS mode
    startState.mode = 0
    startState.name = "fps"
    endState.mode = 0
    endState.name = "fps"

    -- Generate transition steps that keep the camera looking at the unit
    local numSteps = math.max(2, math.floor(CONFIG.TRANSITION.DURATION * CONFIG.TRANSITION.STEPS_PER_SECOND))

    -- Create transition steps with special handling to look at the unit
    local steps = {}

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = Util.easeInOutCubic(t)

        -- Interpolate position only
        local statePatch = {
            mode = 0,
            name = "fps",
            px = Util.lerp(startState.px, endState.px, easedT),
            py = Util.lerp(startState.py, endState.py, easedT),
            pz = Util.lerp(startState.pz, endState.pz, easedT)
        }

        steps[i] = statePatch
    end

    -- Set up the transition
    STATE.transition.steps = steps
    STATE.transition.currentStepIndex = 1
    STATE.transition.startTime = Spring.GetTimer()
    STATE.transition.active = true
    STATE.transition.currentAnchorIndex = index

    -- Enable tracking camera on the unit
    STATE.tracking.mode = 'tracking_camera'
    STATE.tracking.unitID = unitID
    STATE.tracking.lastCamDir = { x = 0, y = 0, z = 0 }
    STATE.tracking.lastRotation = { rx = 0, ry = 0, rz = 0 }

    Spring.Echo("Moving to anchor " .. index .. " while tracking unit " .. unitID)
    return true
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
        if (STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point') and STATE.tracking.unitID then
            STATE.tracking.unitOffsets[STATE.tracking.unitID] = {
                height = CONFIG.FPS.HEIGHT_OFFSET,
                forward = CONFIG.FPS.FORWARD_OFFSET,
                side = CONFIG.FPS.SIDE_OFFSET
            }
        end

        -- Switch tracking to the new unit
        STATE.tracking.unitID = unitID

        -- For FPS mode, load appropriate offsets
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            if STATE.tracking.unitOffsets[unitID] then
                -- Use saved offsets
                CONFIG.FPS.HEIGHT_OFFSET = STATE.tracking.unitOffsets[unitID].height
                CONFIG.FPS.FORWARD_OFFSET = STATE.tracking.unitOffsets[unitID].forward
                CONFIG.FPS.SIDE_OFFSET = STATE.tracking.unitOffsets[unitID].side
                Spring.Echo("Camera switched to unit " .. unitID .. " with saved offsets")
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

                Spring.Echo("Camera switched to unit " .. unitID .. " with new offsets")
            end
        else
            Spring.Echo("Tracking switched to unit " .. unitID)
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
            Util.disableTracking()
            Spring.Echo("Camera tracking disabled - no units selected (after grace period)")
        end
    end

    -- If we're in a mode transition but not tracking any unit,
    -- then we're transitioning back to normal camera from a tracking mode
    if STATE.tracking.modeTransition and not STATE.tracking.mode then
        -- We're transitioning to free camera
        -- Just let the transition time out
        local now = Spring.GetTimer()
        local elapsed = Spring.DiffTimers(now, STATE.tracking.transitionStartTime)
        if elapsed > 1.0 then
            STATE.tracking.modeTransition = false
        end
    end

    -- During special transition + tracking, handle both components
    if STATE.transition.active then
        -- Update transition position
        local now = Spring.GetTimer()

        -- Calculate current progress
        local elapsed = Spring.DiffTimers(now, STATE.transition.startTime)
        local targetProgress = math.min(elapsed / CONFIG.TRANSITION.DURATION, 1.0)

        -- Determine which position step to use
        local totalSteps = #STATE.transition.steps
        local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

        -- Only update position if we need to move to a new step
        if targetStep > STATE.transition.currentStepIndex then
            STATE.transition.currentStepIndex = targetStep

            -- Get the position state for this step
            local posState = STATE.transition.steps[STATE.transition.currentStepIndex]

            -- Check if we've reached the end
            if STATE.transition.currentStepIndex >= totalSteps then
                STATE.transition.active = false
                STATE.transition.currentAnchorIndex = nil
            end

            -- Only update position, not direction (tracking will handle that)
            if STATE.tracking.mode == 'tracking_camera' and STATE.tracking.unitID then
                -- Get unit position for look direction
                local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.tracking.unitID)
                local targetPos = { x = unitX, y = unitY, z = unitZ }

                -- Get current (transitioning) camera position
                local camPos = { x = posState.px, y = posState.py, z = posState.pz }

                -- Calculate look direction to the unit
                local lookDir = Util.calculateLookAtPoint(camPos, targetPos)

                -- Create complete camera state with position and look direction
                local combinedState = {
                    mode = 0,
                    name = "fps",
                    px = camPos.x,
                    py = camPos.y,
                    pz = camPos.z,
                    dx = lookDir.dx,
                    dy = lookDir.dy,
                    dz = lookDir.dz,
                    rx = lookDir.rx,
                    ry = lookDir.ry,
                    rz = 0
                }

                -- Apply combined state
                Spring.SetCameraState(combinedState, 0)

                -- Update last values for smooth tracking
                STATE.tracking.lastCamDir = { x = lookDir.dx, y = lookDir.dy, z = lookDir.dz }
                STATE.tracking.lastRotation = { rx = lookDir.rx, ry = lookDir.ry, rz = 0 }
            else
                -- If not tracking, just apply position
                Spring.SetCameraState(posState, 0)
            end
        end
    else
        -- Normal transition behavior when not in special mode
        CameraTransition.update()

        -- Normal tracking behavior when not in special transition
        if STATE.tracking.mode == 'fps' or STATE.tracking.mode == 'fixed_point' then
            -- Check for auto-orbit
            OrbitingCamera.checkUnitMovement()

            if STATE.orbit.autoOrbitActive then
                -- Handle auto-orbit camera update
                OrbitingCamera.updateAutoOrbit()
            else
                -- Normal FPS update
                FPSCamera.update()
            end
        elseif STATE.tracking.mode == 'tracking_camera' then
            TrackingCamera.update()
        elseif STATE.tracking.mode == 'orbit' then
            OrbitingCamera.update()
        end
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
    widgetHandler.actionHandler:AddAction(self, "toggle_camera_suite", function()
        return WidgetControl.toggle()
    end, nil, 'p')

    -- Register camera anchor commands
    widgetHandler.actionHandler:AddAction(self, "set_smooth_camera_anchor", function(_, index)
        return CameraAnchor.set(index)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "focus_smooth_camera_anchor", function(_, index)
        return CameraAnchor.focus(index)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "decrease_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(-1)
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "increase_smooth_camera_duration", function()
        CameraAnchor.adjustDuration(1)
    end, nil, 'p')

    -- Register FPS camera commands
    widgetHandler.actionHandler:AddAction(self, "toggle_fps_camera", function()
        return FPSCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "fps_height_offset_up", function()
        FPSCamera.adjustOffset("height", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_height_offset_down", function()
        FPSCamera.adjustOffset("height", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_forward_offset_up", function()
        FPSCamera.adjustOffset("forward", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_forward_offset_down", function()
        FPSCamera.adjustOffset("forward", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_side_offset_right", function()
        FPSCamera.adjustOffset("side", 10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_side_offset_left", function()
        FPSCamera.adjustOffset("side", -10)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "fps_toggle_free_cam", function()
        FPSCamera.toggleFreeCam()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "fps_reset_defaults", function()
        FPSCamera.resetOffsets()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "clear_fixed_look_point", function()
        FPSCamera.clearFixedLookPoint()
    end, nil, 'p')

    -- Register Tracking Camera command
    widgetHandler.actionHandler:AddAction(self, "toggle_tracking_camera", function()
        return TrackingCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "focus_anchor_and_track", function(_, index)
        return CameraAnchor.focusAndTrack(index)
    end, nil, 'p')

    -- Register Orbiting Camera commands
    widgetHandler.actionHandler:AddAction(self, "toggle_orbiting_camera", function()
        OrbitingCamera.toggle()
    end, nil, 'p')

    widgetHandler.actionHandler:AddAction(self, "orbit_speed_up", function()
        OrbitingCamera.adjustSpeed(0.0001)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "orbit_speed_down", function()
        OrbitingCamera.adjustSpeed(-0.0001)
    end, nil, 'pR')

    widgetHandler.actionHandler:AddAction(self, "orbit_reset_defaults", function()
        OrbitingCamera.resetSettings()
    end, nil, 'p')

    Spring.I18N.load({
        en = {
            ["ui.orderMenu.set_fixed_look_point"] = "Look point",
            ["ui.orderMenu.set_fixed_look_point_tooltip"] = "Click on a location to focus camera on while following unit.",
        }
    })

    Spring.Echo("Camera Suite loaded but disabled. Use /toggle_camera_suite to enable.")
end

function widget:Shutdown()
    -- Make sure we clean up
    if STATE.enabled then
        WidgetControl.disable()
    end
end

function widget:CommandNotify(cmdID, cmdParams, _)
    if cmdID == CMD_SET_FIXED_LOOK_POINT then
        return FPSCamera.setFixedLookPoint(cmdParams)
    end
    return false
end

function widget:CommandsChanged()
    if not STATE.enabled then
        return
    end

    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        local customCommands = widgetHandler.customCommands
        customCommands[#customCommands + 1] = CMD_SET_FIXED_LOOK_POINT_DEFINITION
    end
end