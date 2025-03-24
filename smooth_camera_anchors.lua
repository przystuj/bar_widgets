function widget:GetInfo()
    return {
        name      = "Smooth Camera Anchors",
        desc      = "Camera anchors with smooth transition",
        author    = "SuperKitowiec",
        date      = "Mar 2025",
        license   = "GNU GPL, v2 or later",
        layer     = 1,
        enabled   = true,
        version   = 1.0,
    }
end

--------------------------------------------------------------------------------
-- CONFIGURATION
--------------------------------------------------------------------------------

-- Set the transition duration in seconds
local TRANSITION_DURATION = 1.0
local MIN_TRANSITION_DURATION = 0.0
local STEPS_PER_SECOND = 60 -- Fixed step rate for smooth transitions

--------------------------------------------------------------------------------
-- VARIABLES
--------------------------------------------------------------------------------

-- Saved camera anchors
local anchors = {}

-- Transition state
local isTransitioning = false
local transitionStartTime = nil
local transitionSteps = {}
local currentStepIndex = 1
local currentAnchorIndex = nil -- Track which anchor we're currently moving to

--------------------------------------------------------------------------------
-- HELPER FUNCTIONS
--------------------------------------------------------------------------------

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
        local state = DeepCopy(startState) -- Start with a copy of the start state
        
        -- Core position parameters
        state.px = Lerp(startState.px, endState.px, easedT)
        state.py = Lerp(startState.py, endState.py, easedT)
        state.pz = Lerp(startState.pz, endState.pz, easedT)
        
        -- Core direction parameters
        state.dx = Lerp(startState.dx, endState.dx, easedT)
        state.dy = Lerp(startState.dy, endState.dy, easedT)
        state.dz = Lerp(startState.dz, endState.dz, easedT)
        
        -- Height parameter 
        if startState.height ~= nil and endState.height ~= nil then
            state.height = Lerp(startState.height, endState.height, easedT)
        end
        
        -- Camera specific parameters
        local cameraParams = {
            "zoomFromHeight", "fov", "gndOffset", "dist", "flipped",
            "rx", "ry", "rz", "vx", "vy", "vz", "ax", "ay", "az"
        }
        
        for _, param in ipairs(cameraParams) do
            if startState[param] ~= nil and endState[param] ~= nil then
                state[param] = Lerp(startState[param], endState[param], easedT)
            end
        end
        
        -- Handle rotation rates for rotating camera modes
        if startState.mode == endState.mode and 
           (startState.mode == 2 or startState.mode == 3 or startState.mode == 4) then
            -- For rotating camera modes, interpolate rotation rates
            if startState.rotX ~= nil and endState.rotX ~= nil then
                state.rotX = Lerp(startState.rotX, endState.rotX, easedT)
            end
            if startState.rotY ~= nil and endState.rotY ~= nil then
                state.rotY = Lerp(startState.rotY, endState.rotY, easedT)
            end
            if startState.rotZ ~= nil and endState.rotZ ~= nil then
                state.rotZ = Lerp(startState.rotZ, endState.rotZ, easedT)
            end
        end
        
        -- For camera mode changes, switch at 90% through the transition
        if startState.mode ~= endState.mode and t > 0.9 then
            state.mode = endState.mode
        end
        
        steps[i] = state
    end
    
    -- Ensure the last step is exactly the end state
    steps[numSteps] = DeepCopy(endState)
    
    return steps
end

--------------------------------------------------------------------------------
-- CALLINS
--------------------------------------------------------------------------------

function widget:Update()
    if not isTransitioning then return end
    
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

-- Function to set a camera anchor
local function SetCameraAnchor(cmd, index)
    index = tonumber(index)
    if index and index >= 0 and index <= 9 then
        anchors[index] = Spring.GetCameraState()
        Spring.Echo("Saved camera anchor: " .. index)
    end
    return true
end

-- Function to focus on a camera anchor with smooth transition
local function FocusCameraAnchor(cmd, index)
    index = tonumber(index)
    if index and index >= 0 and index <= 9 and anchors[index] then
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

function widget:Initialize()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 0)
    widgetHandler:AddAction("set_smooth_camera_anchor", SetCameraAnchor, nil, 'p')
    widgetHandler:AddAction("focus_smooth_camera_anchor", FocusCameraAnchor, nil, 'p')
    widgetHandler:AddAction("decrease_smooth_camera_duration", DecreaseDuration, nil, 'p')
    widgetHandler:AddAction("increase_smooth_camera_duration", IncreaseDuration, nil, 'p')
end

function widget:Shutdown()
    Spring.SetConfigInt("CamSpringLockCardinalDirections", 1)
end