function widget:GetInfo()
    return {
        name = "Camera Suite",
        desc = "Camera anchors with smooth transitions. Follow unit in fps mode. Track unit in fps mode.",
        author = "SuperKitowiec",
        date = "Mar 2025",
        license = "GNU GPL, v2 or later",
        layer = 1,
        enabled = true,
        version = 2,
    }
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

local CONFIG = {
    -- Transition settings
    TRANSITION = {
        DURATION = 1.0,
        MIN_DURATION = 0.0,
        STEPS_PER_SECOND = 60
    },

    -- FPS camera settings
    FPS = {
        DEFAULT_HEIGHT_OFFSET = 60,
        DEFAULT_FORWARD_OFFSET = -100,
        DEFAULT_SIDE_OFFSET = 0,
        HEIGHT_OFFSET = 60,
        FORWARD_OFFSET = -100,
        SIDE_OFFSET = 0
    }
}

--------------------------------------------------------------------------------
-- STATE MANAGEMENT
--------------------------------------------------------------------------------

local STATE = {
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

    -- FPS Camera
    fps = {
        trackedUnitID = nil,
        wasInFPSMode = false,
        inFreeCameraMode = false
    },

    -- Stationary Tracking
    stationary = {
        enabled = false,
        unitId = nil,
        camState = nil
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

        -- For camera mode changes, switch at 90% through the transition
        if startState.mode ~= endState.mode and t > 0.9 then
            statePatch.mode = endState.mode
        end

        steps[i] = statePatch
    end

    -- Ensure the last step is exactly the end state
    steps[numSteps] = Util.deepCopy(endState)

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

    -- Disable stationary tracking if it's active
    if STATE.stationary.enabled then
        STATE.stationary.enabled = false
        STATE.stationary.unitId = nil
        STATE.stationary.camState = nil
        Spring.Echo("Stationary camera tracking disabled")
    end

    -- If we're already tracking this unit, turn it off
    if STATE.fps.trackedUnitID ~= nil then
        STATE.fps.trackedUnitID = nil
        Spring.Echo("FPS camera detached")
        return
    end

    -- Start tracking the new unit
    STATE.fps.trackedUnitID = unitID
    STATE.fps.wasInFPSMode = false

    -- Switch to FPS camera mode
    local camStatePatch = {
        name = "fps",
        mode = 0  -- FPS camera mode
    }
    Spring.SetCameraState(camStatePatch, 0)

    Spring.Echo("FPS camera attached to unit " .. unitID)
end

-- Update the FPS camera position to match the tracked unit
function FPSCamera.update()
    if not STATE.fps.trackedUnitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.fps.trackedUnitID) then
        Spring.Echo("Unit no longer exists, detaching FPS camera")
        STATE.fps.trackedUnitID = nil
        STATE.fps.inFreeCameraMode = false
        return
    end

    -- Get unit position and vectors
    local x, y, z = Spring.GetUnitPosition(STATE.fps.trackedUnitID)
    local front, up, right = Spring.GetUnitVectors(STATE.fps.trackedUnitID)

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

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

    -- Detect if user manually changed camera mode
    if STATE.fps.wasInFPSMode and camState.name ~= "fps" then
        -- User switched away from FPS mode, stop tracking
        STATE.fps.trackedUnitID = nil
        STATE.fps.inFreeCameraMode = false
        Spring.Echo("FPS camera mode changed, detaching")
        return
    end

    STATE.fps.wasInFPSMode = (camState.name == "fps")

    local camStatePatch = {
        px = x,
        py = y,
        pz = z
    }

    -- If in free camera mode, don't update rotation but keep updating position
    if not STATE.fps.inFreeCameraMode then
        camStatePatch.dx = frontX
        camStatePatch.dy = frontY
        camStatePatch.dz = frontZ
        camStatePatch.ry = -(Spring.GetUnitHeading(STATE.fps.trackedUnitID, true) + math.pi)
        camStatePatch.rx = 1.8
        camStatePatch.rz = 0
    end

    Spring.SetCameraState(camStatePatch, 0)
end

-- Toggle free camera mode
function FPSCamera.toggleFreeCam()
    -- Only works if we're tracking a unit in FPS mode
    if not STATE.fps.trackedUnitID or not STATE.fps.wasInFPSMode then
        Spring.Echo("Free camera only works in FPS mode")
        return
    end

    -- Toggle free camera mode
    STATE.fps.inFreeCameraMode = not STATE.fps.inFreeCameraMode

    if STATE.fps.inFreeCameraMode then
        Spring.Echo("Free camera mode enabled - use mouse to rotate view")
    else
        Spring.Echo("Free camera mode disabled - view follows unit orientation")
    end
end

-- Adjust camera offsets
function FPSCamera.adjustOffset(offsetType, amount)
    if offsetType == "height" then
        CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.HEIGHT_OFFSET + amount
    elseif offsetType == "forward" then
        CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.FORWARD_OFFSET + amount
    elseif offsetType == "side" then
        CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.SIDE_OFFSET + amount
    end
end

-- Reset camera offsets to defaults
function FPSCamera.resetOffsets()
    CONFIG.FPS.HEIGHT_OFFSET = CONFIG.FPS.DEFAULT_HEIGHT_OFFSET
    CONFIG.FPS.FORWARD_OFFSET = CONFIG.FPS.DEFAULT_FORWARD_OFFSET
    CONFIG.FPS.SIDE_OFFSET = CONFIG.FPS.DEFAULT_SIDE_OFFSET
    Spring.Echo("FPS camera offsets reset to defaults")
end

--------------------------------------------------------------------------------
-- STATIONARY TRACKING FUNCTIONS
--------------------------------------------------------------------------------

local StationaryTracking = {}

-- Toggle stationary camera tracking
function StationaryTracking.toggle()
    -- If tracking is already on, turn it off
    if STATE.stationary.enabled then
        STATE.stationary.enabled = false
        Spring.SetCameraState(STATE.stationary.camState, 0.5)
        STATE.stationary.unitId = nil
        STATE.stationary.camState = nil
        Spring.Echo("Stationary camera tracking disabled")
        return true
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        Spring.Echo("No unit selected for stationary tracking")
        return true
    end

    -- Check if we're in FPS camera mode
    local camState = Spring.GetCameraState()
    if camState.mode ~= 0 then
        -- Mode 0 is FPS camera mode
        Spring.Echo("Stationary tracking requires FPS camera mode. Switching to FPS mode first.")

        -- Switch to FPS camera mode
        local camStatePatch = {
            name = "fps",
            mode = 0  -- FPS camera mode
        }
        Spring.SetCameraState(camStatePatch, 0)

        -- Return without enabling stationary tracking yet
        return true
    end

    -- Now we're in FPS mode, so we can enable stationary tracking
    STATE.stationary.unitId = selectedUnits[1]
    STATE.stationary.camState = Spring.GetCameraState()
    STATE.stationary.enabled = true

    -- If the unit is also being tracked with the FPS camera function, disable that
    if STATE.fps.trackedUnitID then
        STATE.fps.trackedUnitID = nil
        Spring.Echo("FPS camera tracking disabled")
    end

    Spring.Echo("Stationary camera tracking enabled. Camera will stay fixed but follow unit " .. STATE.stationary.unitId)

    return true
end

-- Update stationary camera tracking
function StationaryTracking.update()
    if not STATE.stationary.enabled or not STATE.stationary.unitId or not STATE.stationary.camState then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATE.stationary.unitId) then
        Spring.Echo("Tracked unit no longer exists, disabling stationary tracking")
        STATE.stationary.enabled = false
        STATE.stationary.unitId = nil
        return
    end

    -- Check if user changed camera mode manually
    local currentState = Spring.GetCameraState()
    if currentState.mode ~= 0 then
        Spring.Echo("Camera mode changed, disabling stationary tracking")
        STATE.stationary.enabled = false
        STATE.stationary.unitId = nil
        STATE.stationary.camState = nil
        return
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATE.stationary.unitId)

    -- Calculate direction vector from camera to unit
    local dirX = unitX - STATE.stationary.camState.px
    local dirY = unitY - STATE.stationary.camState.py
    local dirZ = unitZ - STATE.stationary.camState.pz

    -- Normalize the direction vector
    local length = math.sqrt(dirX * dirX + dirY * dirY + dirZ * dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Create camera state patch
    local camStatePatch = {
        -- Keep camera in the fixed position
        px = STATE.stationary.camState.px,
        py = STATE.stationary.camState.py,
        pz = STATE.stationary.camState.pz,

        -- Keep FPS camera mode
        mode = 0,
        name = "fps",

        -- Set direction vectors
        dx = dirX,
        dy = dirY,
        dz = dirZ,

        -- Calculate appropriate rotation for FPS camera
        ry = -math.atan2(dirX, dirZ) - math.pi,
    }

    -- Calculate pitch (rx)
    local horizontalLength = math.sqrt(dirX * dirX + dirZ * dirZ)
    camStatePatch.rx = -((math.atan2(dirY, horizontalLength) - math.pi) / 1.8)

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--------------------------------------------------------------------------------
-- CAMERA ANCHOR FUNCTIONS
--------------------------------------------------------------------------------

local CameraAnchor = {}

-- Set a camera anchor
function CameraAnchor.set(index)
    index = tonumber(index)
    if index and index >= 0 and index <= 9 then
        STATE.anchors[index] = Spring.GetCameraState()
        Spring.Echo("Saved smooth camera anchor: " .. index)
    end
    return true
end

-- Focus on a camera anchor with smooth transition
function CameraAnchor.focus(index)
    index = tonumber(index)
    if not (index and index >= 0 and index <= 9 and STATE.anchors[index]) then
        return true
    end

    -- Cancel FPS mode if active
    if STATE.fps.trackedUnitID then
        STATE.fps.trackedUnitID = nil
        Spring.Echo("FPS camera detached")
    end

    -- Disable stationary tracking if active
    if STATE.stationary.enabled then
        STATE.stationary.enabled = false
        STATE.stationary.unitId = nil
        STATE.stationary.camState = nil
        Spring.Echo("Stationary camera tracking disabled when moving to anchor")
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
        Spring.SetCameraState(STATE.anchors[index], 0)
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

function widget:Update()
    -- Handle smooth transitions between anchors
    CameraTransition.update()

    -- Handle FPS camera updates
    if STATE.fps.trackedUnitID then
        FPSCamera.update()
    end

    -- Handle stationary camera tracking
    if STATE.stationary.enabled then
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

    --Util.log({ "stationary.enabled", STATE.stationary.enabled })
    --Util.log({ "cameraState", Spring.GetCameraState() })
end

function widget:Initialize()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)

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
end

function widget:Shutdown()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)
    Spring.SetCameraState({ rz = 0 }, 0)
end