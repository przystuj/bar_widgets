function widget:GetInfo()
    return {
        name = "Smooth Camera Anchors",
        desc = "Camera anchors with smooth transition and unit FPS camera",
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

-- Set the transition duration in seconds
local TRANSITION_DURATION = 1.0
local MIN_TRANSITION_DURATION = 0.0
local STEPS_PER_SECOND = 60 -- Fixed step rate for smooth transitions

-- FPS camera configuration
local DEFAULT_FPS_HEIGHT_OFFSET = 60
local DEFAULT_FPS_FORWARD_OFFSET = -100
local DEFAULT_FPS_SIDE_OFFSET = 0
local FPS_HEIGHT_OFFSET = DEFAULT_FPS_HEIGHT_OFFSET-- Height offset for FPS camera above unit
local FPS_FORWARD_OFFSET = DEFAULT_FPS_FORWARD_OFFSET-- Forward offset from unit center
local FPS_SIDE_OFFSET = DEFAULT_FPS_SIDE_OFFSET -- Forward offset from unit center

-- Stationary camera tracking configuration
local STATIONARY_TRACK_ENABLED = false
local STATIONARY_TRACK_UNIT_ID = nil
local STATIONARY_CAMERA_POSITION = nil

--------------------------------------------------------------------------------
-- VARIABLES
--------------------------------------------------------------------------------

-- Saved camera anchors
local anchors = {}

-- Transition state
local isTransitioning = false
local transitionStartTime
local transitionSteps = {}
local currentStepIndex = 1
local currentAnchorIndex -- Track which anchor we're currently moving to

-- FPS camera tracking
local trackedUnitID
local wasInFPSMode = false
local savedCameraState
local inFreeCameraMode = false

-- Delayed action variables for stationary tracking
local delayedPositionStoreFrame = nil
local delayedPositionStoreCallback = nil

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

local function dump(o)
    if type(o) == 'table' then
        local s = '{ '
        for k, v in pairs(o) do
            if type(k) ~= 'number' then
                k = '"' .. k .. '"'
            end
            s = s .. '[' .. k .. '] = ' .. dump(v) .. ','
        end
        return s .. '} '
    else
        return tostring(o)
    end
end

local function log(o)
    Spring.Echo(dump(o))
end

-- Deep copy function for tables
local function DeepCopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in pairs(orig) do
            copy[orig_key] = DeepCopy(orig_value)
        end
    else
        copy = orig
    end
    return copy
end

-- Interpolation function (ease in-out cubic)
local function EaseInOutCubic(t)
    if t < 0.5 then
        return 4 * t * t * t
    else
        local t2 = (t - 1)
        return 1 + 4 * t2 * t2 * t2
    end
end

-- Linear interpolation between two values
local function Lerp(a, b, t)
    return a + (b - a) * t
end

-- Generate a sequence of camera states for smooth transition
local function GenerateTransitionSteps(startState, endState, numSteps)
    local steps = {}

    for i = 1, numSteps do
        local t = (i - 1) / (numSteps - 1)
        local easedT = EaseInOutCubic(t)

        -- Create a new state by interpolating between start and end
        local statePatch = {}

        -- Core position parameters
        statePatch.px = Lerp(startState.px, endState.px, easedT)
        statePatch.py = Lerp(startState.py, endState.py, easedT)
        statePatch.pz = Lerp(startState.pz, endState.pz, easedT)

        -- Core direction parameters
        statePatch.dx = Lerp(startState.dx, endState.dx, easedT)
        statePatch.dy = Lerp(startState.dy, endState.dy, easedT)
        statePatch.dz = Lerp(startState.dz, endState.dz, easedT)

        -- Camera specific parameters
        local cameraParams = {
            "zoomFromHeight", "fov", "gndOffset", "dist", "flipped",
            "rx", "ry", "rz", "vx", "vy", "vz", "ax", "ay", "az", "height"
        }

        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                statePatch[param] = Lerp(startState[param], endState[param], easedT)
            end
        end

        -- Handle rotation rates for rotating camera modes
        if startState.mode == endState.mode and
                (startState.mode == 2 or startState.mode == 3 or startState.mode == 4) then
            -- For rotating camera modes, interpolate rotation rates
            if startState.rotX ~= nil and endState.rotX ~= nil then
                statePatch.rotX = Lerp(startState.rotX, endState.rotX, easedT)
            end
            if startState.rotY ~= nil and endState.rotY ~= nil then
                statePatch.rotY = Lerp(startState.rotY, endState.rotY, easedT)
            end
            if startState.rotZ ~= nil and endState.rotZ ~= nil then
                statePatch.rotZ = Lerp(startState.rotZ, endState.rotZ, easedT)
            end
        end

        -- For camera mode changes, switch at 90% through the transition
        if startState.mode ~= endState.mode and t > 0.9 then
            statePatch.mode = endState.mode
        end

        steps[i] = statePatch
    end

    -- Ensure the last step is exactly the end state
    steps[numSteps] = DeepCopy(endState)

    return steps
end

--------------------------------------------------------------------------------
-- FPS CAMERA FUNCTIONS
--------------------------------------------------------------------------------

-- Function to toggle FPS camera attached to a unit
local function ToggleUnitFPSCamera(unitID)
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
    if STATIONARY_TRACK_ENABLED then
        STATIONARY_TRACK_ENABLED = false
        STATIONARY_TRACK_UNIT_ID = nil
        STATIONARY_CAMERA_POSITION = nil
        Spring.Echo("Stationary camera tracking disabled")
    end

    -- If we're already tracking this unit, turn it off
    if trackedUnitID ~= nil then
        trackedUnitID = nil
        Spring.Echo("FPS camera detached")
        return
    end

    -- Start tracking the new unit
    trackedUnitID = unitID
    wasInFPSMode = false

    -- Switch to FPS camera mode
    local camStatePatch = {}
    camStatePatch.name = "fps"
    camStatePatch.mode = 0  -- FPS camera mode
    Spring.SetCameraState(camStatePatch, 0)

    Spring.Echo("FPS camera attached to unit " .. unitID)
end

-- Function to update the FPS camera position to match the tracked unit
local function UpdateUnitFPSCamera()
    if not trackedUnitID then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(trackedUnitID) then
        Spring.Echo("Unit no longer exists, detaching FPS camera")
        trackedUnitID = nil
        inFreeCameraMode = false

        -- Restore previous camera state if we saved one
        if savedCameraState then
            Spring.SetCameraState(savedCameraState, 0.5)
            savedCameraState = nil
        end

        return
    end

    -- Get unit position and vectors
    local x, y, z = Spring.GetUnitPosition(trackedUnitID)
    local front, up, right = Spring.GetUnitVectors(trackedUnitID)

    -- Extract components from the vector tables
    local frontX, frontY, frontZ = front[1], front[2], front[3]
    local upX, upY, upZ = up[1], up[2], up[3]
    local rightX, rightY, rightZ = right[1], right[2], right[3]

    -- Apply height offset along the unit's up vector
    if FPS_HEIGHT_OFFSET ~= 0 then
        x = x + upX * FPS_HEIGHT_OFFSET
        y = y + upY * FPS_HEIGHT_OFFSET
        z = z + upZ * FPS_HEIGHT_OFFSET
    end

    -- Apply forward offset if needed
    if FPS_FORWARD_OFFSET ~= 0 then
        x = x + frontX * FPS_FORWARD_OFFSET
        y = y + frontY * FPS_FORWARD_OFFSET
        z = z + frontZ * FPS_FORWARD_OFFSET
    end

    if FPS_SIDE_OFFSET ~= 0 then
        x = x + rightX * FPS_SIDE_OFFSET
        y = y + rightY * FPS_SIDE_OFFSET
        z = z + rightZ * FPS_SIDE_OFFSET
    end

    -- Get current camera state
    local camState = Spring.GetCameraState()

    -- Detect if user manually changed camera mode
    if wasInFPSMode and camState.name ~= "fps" then
        -- User switched away from FPS mode, stop tracking
        trackedUnitID = nil
        inFreeCameraMode = false
        Spring.Echo("FPS camera mode changed, detaching")
        return
    end

    wasInFPSMode = (camState.name == "fps")

    local camStatePatch = {}

    -- Update camera state
    camStatePatch.px = x
    camStatePatch.py = y
    camStatePatch.pz = z

    -- If in free camera mode, don't update rotation but keep updating position
    if not inFreeCameraMode then
        camStatePatch.dx = frontX
        camStatePatch.dy = frontY
        camStatePatch.dz = frontZ
        camStatePatch.ry = -(Spring.GetUnitHeading(trackedUnitID, true) + math.pi)
        camStatePatch.rx = 1.8
    end

    Spring.SetCameraState(camStatePatch, 0)
end

-- Function to toggle stationary camera tracking
local function ToggleStationaryTracking()
    -- If tracking is already on, turn it off
    if STATIONARY_TRACK_ENABLED then
        local unitX, unitY, _ = Spring.GetUnitPosition(STATIONARY_TRACK_UNIT_ID)
        STATIONARY_TRACK_ENABLED = false
        STATIONARY_TRACK_UNIT_ID = nil
        STATIONARY_CAMERA_POSITION = nil

        -- Reset camera orientation to prevent upside-down view
        local camStatePatch = {}
        camStatePatch.py = 5000
        camStatePatch.px = unitX
        camStatePatch.py = unitY
        camStatePatch.rx = 3.6  -- Reset pitch
        --camStatePatch.rz = 3.6  -- Reset roll
        camStatePatch.mode = 2
        Spring.SetCameraState(camStatePatch, 0.5)  -- Use a transition time of 0.5 seconds

        Spring.Echo("Stationary camera tracking disabled")
        return true
    end

    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits == 0 then
        Spring.Echo("No unit selected for stationary tracking")
        return true
    end

    -- Disable FPS camera if it's active
    if trackedUnitID then
        trackedUnitID = nil
        Spring.Echo("FPS camera detached")
    end

    -- Store the unit ID to track
    STATIONARY_TRACK_UNIT_ID = selectedUnits[1]

    -- Switch to FPS camera mode first
    local camStatePatch = {}
    camStatePatch.name = "fps"
    camStatePatch.mode = 0  -- FPS camera mode
    Spring.SetCameraState(camStatePatch, 0)

    -- Wait a frame to ensure the camera mode has changed
    Spring.Echo("Switching to FPS mode for stationary tracking...")

    -- Small delay to ensure camera mode has changed
    local frame = Spring.GetGameFrame()
    local function StorePositionAndActivate()
        -- Now store the camera position after it's in FPS mode
        local camState = Spring.GetCameraState()
        STATIONARY_CAMERA_POSITION = {
            x = camState.px,
            y = camState.py,
            z = camState.pz
        }

        -- Enable tracking
        STATIONARY_TRACK_ENABLED = true
        Spring.Echo("Stationary camera tracking enabled - camera will stay in place and look at unit " .. STATIONARY_TRACK_UNIT_ID)
    end

    -- We'll use a delay frame counter in the Update function
    delayedPositionStoreFrame = frame + 2 -- Wait 2 frames
    delayedPositionStoreCallback = StorePositionAndActivate

    return true
end

-- Function to update stationary camera tracking
local function UpdateStationaryTracking()
    if not STATIONARY_TRACK_ENABLED or not STATIONARY_TRACK_UNIT_ID or not STATIONARY_CAMERA_POSITION then
        return
    end

    -- Check if unit still exists
    if not Spring.ValidUnitID(STATIONARY_TRACK_UNIT_ID) then
        Spring.Echo("Tracked unit no longer exists, disabling stationary tracking")
        STATIONARY_TRACK_ENABLED = false
        STATIONARY_TRACK_UNIT_ID = nil
        return
    end

    -- Get unit position
    local unitX, unitY, unitZ = Spring.GetUnitPosition(STATIONARY_TRACK_UNIT_ID)

    -- Calculate direction vector from camera to unit
    local dirX = unitX - STATIONARY_CAMERA_POSITION.x
    local dirY = unitY - STATIONARY_CAMERA_POSITION.y
    local dirZ = unitZ - STATIONARY_CAMERA_POSITION.z

    -- Normalize the direction vector
    local length = math.sqrt(dirX*dirX + dirY*dirY + dirZ*dirZ)
    if length > 0 then
        dirX = dirX / length
        dirY = dirY / length
        dirZ = dirZ / length
    end

    -- Create camera state patch
    local camStatePatch = {}

    -- Keep camera in the fixed position
    camStatePatch.px = STATIONARY_CAMERA_POSITION.x
    camStatePatch.py = STATIONARY_CAMERA_POSITION.y
    camStatePatch.pz = STATIONARY_CAMERA_POSITION.z

    -- Set camera to look at the unit
    camStatePatch.dx = dirX
    camStatePatch.dy = dirY
    camStatePatch.dz = dirZ

    -- Force FPS-like camera mode
    camStatePatch.mode = 0
    camStatePatch.name = "fps"

    -- Calculate angles for rotation
    -- ry (yaw) is the horizontal rotation
    camStatePatch.ry = -math.atan2(dirX, dirZ)

    -- rx (pitch) is the vertical rotation
    -- We need to calculate the pitch angle from the direction vector
    local horizontalLength = math.sqrt(dirX*dirX + dirZ*dirZ)
    camStatePatch.rx = (math.atan2(dirY, horizontalLength) - math.pi)/1.5

    camStatePatch.rz = -math.pi

    -- Apply camera state
    Spring.SetCameraState(camStatePatch, 0)
end

--------------------------------------------------------------------------------
-- CALLINS
--------------------------------------------------------------------------------

function widget:Update()
    -- Handle smooth transitions between anchors
    if isTransitioning then
        local now = Spring.GetTimer()

        -- Calculate current progress
        local elapsed = Spring.DiffTimers(now, transitionStartTime)
        local targetProgress = math.min(elapsed / TRANSITION_DURATION, 1.0)

        -- Determine which step to use based on progress
        local totalSteps = #transitionSteps
        local targetStep = math.max(1, math.min(totalSteps, math.ceil(targetProgress * totalSteps)))

        -- Only update if we need to move to a new step
        if targetStep > currentStepIndex then
            currentStepIndex = targetStep

            -- Apply the camera state for this step
            local state = transitionSteps[currentStepIndex]
            Spring.SetCameraState(state, 0)

            -- Check if we've reached the end
            if currentStepIndex >= totalSteps then
                isTransitioning = false
                currentAnchorIndex = nil
            end
        end
    end

    -- Handle FPS camera updates
    if trackedUnitID then
        UpdateUnitFPSCamera()
    end

    -- Handle stationary camera tracking (independent of FPS camera)
    if STATIONARY_TRACK_ENABLED then
        UpdateStationaryTracking()
    end

    -- Check for delayed position storage callback
    if delayedPositionStoreFrame and Spring.GetGameFrame() >= delayedPositionStoreFrame then
        if delayedPositionStoreCallback then
            delayedPositionStoreCallback()
        end
        delayedPositionStoreFrame = nil
        delayedPositionStoreCallback = nil
    end
end

-- Function to set a camera anchor
local function SetCameraAnchor(cmd, index)
    index = tonumber(index)
    if index and index >= 0 and index <= 9 then
        anchors[index] = Spring.GetCameraState()
        Spring.Echo("Saved smooth camera anchor: " .. index)
    end
    return true
end

-- Function to focus on a camera anchor with smooth transition
local function FocusCameraAnchor(cmd, index)
    index = tonumber(index)
    if index and index >= 0 and index <= 9 and anchors[index] then
        -- Cancel FPS mode if active
        if trackedUnitID then
            trackedUnitID = nil
            savedCameraState = nil
            Spring.Echo("FPS camera detached")
        end

        -- Cancel transition if we click the same anchor we're currently moving to
        if isTransitioning and currentAnchorIndex == index then
            isTransitioning = false
            currentAnchorIndex = nil
            Spring.Echo("Transition canceled")
            return true
        end

        -- Cancel any in-progress transition when starting a new one
        if isTransitioning then
            isTransitioning = false
            Spring.Echo("Canceled previous transition")
        end

        -- Check if we should do an instant transition (duration = 0)
        if TRANSITION_DURATION <= 0 then
            -- Instant camera jump
            Spring.SetCameraState(anchors[index], 0)
            Spring.Echo("Instantly jumped to camera anchor: " .. index)
            return true
        end

        -- Generate transition steps for smooth transition
        local startState = Spring.GetCameraState()
        local endState = DeepCopy(anchors[index])
        local numSteps = math.max(2, math.floor(TRANSITION_DURATION * STEPS_PER_SECOND))

        transitionSteps = GenerateTransitionSteps(startState, endState, numSteps)
        currentStepIndex = 1
        transitionStartTime = Spring.GetTimer()
        isTransitioning = true
        currentAnchorIndex = index -- Store which anchor we're moving to

        Spring.Echo("Loading camera anchor: " .. index)
    end
    return true
end

-- Function to toggle FPS camera through command
local function ToggleFPSCamera()
    -- Get the selected unit
    local selectedUnits = Spring.GetSelectedUnits()
    if #selectedUnits > 0 then
        ToggleUnitFPSCamera(selectedUnits[1])
    else
        Spring.Echo("No unit selected for FPS view")
    end
    return true
end

-- Function to adjust FPS camera height offset
local function AdjustFPSHeightOffset(cmd, amount)
    amount = tonumber(amount) or 1
    FPS_HEIGHT_OFFSET = FPS_HEIGHT_OFFSET + amount
    return true
end

-- Function to adjust FPS camera forward offset
local function AdjustFPSForwardOffset(cmd, amount)
    amount = tonumber(amount) or 1
    FPS_FORWARD_OFFSET = FPS_FORWARD_OFFSET + amount
    return true
end

-- Function to adjust FPS camera side offset
local function AdjustFPSSideOffset(cmd, amount)
    amount = tonumber(amount) or 1
    FPS_SIDE_OFFSET = FPS_SIDE_OFFSET + amount
    return true
end

local function IncreaseDuration()
    TRANSITION_DURATION = TRANSITION_DURATION + 1
    Spring.Echo("transition duration:" .. TRANSITION_DURATION .. "s")
end

local function DecreaseDuration()
    TRANSITION_DURATION = math.max(MIN_TRANSITION_DURATION, TRANSITION_DURATION - 1)
    if TRANSITION_DURATION == 0 then
        Spring.Echo("transition duration: INSTANT")
    else
        Spring.Echo("transition duration:" .. TRANSITION_DURATION .. "s")
    end
end

local function ToggleFreeCam()
    Spring.Echo("Free camera mode enabled - use mouse to rotate view")
    -- Only works if we're tracking a unit in FPS mode
    if not trackedUnitID or not wasInFPSMode then
        Spring.Echo("Free camera only works in FPS mode")
        return
    end

    -- Toggle free camera mode
    inFreeCameraMode = not inFreeCameraMode
end

function widget:Initialize()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)
    widgetHandler:AddAction("set_smooth_camera_anchor", SetCameraAnchor, nil, 'p')
    widgetHandler:AddAction("focus_smooth_camera_anchor", FocusCameraAnchor, nil, 'p')
    widgetHandler:AddAction("decrease_smooth_camera_duration", DecreaseDuration, nil, 'p')
    widgetHandler:AddAction("increase_smooth_camera_duration", IncreaseDuration, nil, 'p')

    widgetHandler:AddAction("toggle_fps_camera", ToggleFPSCamera, nil, 'p')
    widgetHandler:AddAction("toggle_stationary_tracking", ToggleStationaryTracking, nil, 'p')
    widgetHandler:AddAction("fps_height_offset_up", function()
        AdjustFPSHeightOffset(nil, 5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_height_offset_down", function()
        AdjustFPSHeightOffset(nil, -5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_forward_offset_up", function()
        AdjustFPSForwardOffset(nil, 5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_forward_offset_down", function()
        AdjustFPSForwardOffset(nil, -5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_side_offset_right", function()
        AdjustFPSSideOffset(nil, 5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_side_offset_left", function()
        AdjustFPSSideOffset(nil, -5)
    end, nil, 'pR')
    widgetHandler:AddAction("fps_toggle_free_cam", ToggleFreeCam, nil, 'p')
    widgetHandler:AddAction("fps_reset_defaults", function()
        FPS_HEIGHT_OFFSET = DEFAULT_FPS_HEIGHT_OFFSET
        FPS_FORWARD_OFFSET = DEFAULT_FPS_FORWARD_OFFSET
        FPS_SIDE_OFFSET = DEFAULT_FPS_SIDE_OFFSET
    end, nil, 'p')
end

function widget:Shutdown()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)
    if savedCameraState then
        Spring.SetCameraState(savedCameraState, 0)
    end
end