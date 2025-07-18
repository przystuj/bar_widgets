function widget:GetInfo()
    return {
        name = "Beg For Metal",
        desc = "Beg for metal with a single click.",
        author = "SuperKitowiec",
        date = "July 12, 2025",
        license = "GNU GPL, v2 or later",
        version = "1",
        layer = 0,
        enabled = true,
        handler = true,
    }
end

local config = {}

-- State variables for managing the message queue.
local shuffledMessages = {}
local currentMessageIndex = 1

-- Speedups
local spGetMouseState = Spring.GetMouseState
local spTraceScreenRay = Spring.TraceScreenRay
local spMarkerAddPoint = Spring.MarkerAddPoint
local spPlaySoundFile = Spring.PlaySoundFile
local spSendCommands = Spring.SendCommands
local osTime = os.time
local mathRandom = math.random
local mathRandomSeed = math.randomseed

--- Shuffles the messages using the Fisher-Yates algorithm and resets the index.
local function ShuffleMessages()
    for i = 1, #config.messages do
        shuffledMessages[i] = config.messages[i]
    end

    for i = #shuffledMessages, 2, -1 do
        local j = mathRandom(i)
        shuffledMessages[i], shuffledMessages[j] = shuffledMessages[j], shuffledMessages[i]
    end
    currentMessageIndex = 1
end

--- Contains the logic for pinging, sending a message, and cycling to the next one.
local function PerformBegAction()
    if currentMessageIndex > #shuffledMessages then
        ShuffleMessages()
    end

    local mx, my = spGetMouseState()
    local _, pos = spTraceScreenRay(mx, my, true)

    local messageToSend = shuffledMessages[currentMessageIndex]


    if pos then
        spMarkerAddPoint(pos[1], pos[2], pos[3], messageToSend, false)
        spPlaySoundFile("sounds/ui/mappoint2.wav", 1, 'ui')
    end

    currentMessageIndex = currentMessageIndex + 1
end

function widget:Initialize()
    mathRandomSeed(osTime())
    ShuffleMessages()
    widgetHandler.actionHandler:AddAction(self, "beg_for_metal", PerformBegAction, {}, "p")
end

--- This function is called by the engine on every mouse press.
function widget:MousePress(mx, my, button)
    -- Check if the pressed button is mouse button 5 (often a side/thumb button).

    if button == 5 then
        PerformBegAction()
        return true -- Consume the event to prevent other widgets from reacting to it.
    end
    return false -- Do not consume other mouse button presses.
end

config.messages = {
    "Mighty Commander, even your wreckage salutes you. Spare a scrap, that I may tech in the glow of your glory.",

    "Your path is paved with wrecks, your will is law. A scrap from you would be a blessing beyond measure.",

    "O Bringer of Ruin, I beg for a fragment of your glorious trail of carnage — metal born of your divine wrath.",

    "Your enemies fall just to feed your greatness. Might one humble speck claim a bolt from your bounty?",

    "Greatest of Commanders, every wreck you leave is gold. Let me gather a flake, to build in your honor.",

    "You create metal by merely existing. Surely a warlord like you can spare a crumb for your crawling admirer?",

    "Oh Lord of Metal, each bolt you drop is sacred. May I, a tech-starved worm, receive just one?",

    "They fall, you rise. And behind you, metal flows. Let me sip from that river, oh Titan of Destruction.",

    "O Commander Divine, you breathe fire and bleed metal. Please share a drop of your molten mercy.",

    "The ground itself honors you with metal. Might I crawl forth and collect a holy fragment?",

    "You don’t need metal — you command it. I beg a sliver, that I may pretend to matter.",

    "Oh Unstoppable One, grant me the privilege of your metal. I will upgrade in your name.",

    "A metal from you is worth more than a thousand victories. Please, make me rich in your shadow.",

    "You are the storm, the fire, the grinder of metal. Spare one flake from your flood of ruin?",

    "O Commander of Carnage, your metal is legend. May I borrow a single line from your saga?",

}