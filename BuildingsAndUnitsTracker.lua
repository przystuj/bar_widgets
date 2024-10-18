--[[
Each counterGroup is a separate draggable window with its own counterDefinitions.counterDefinitions.counterDefinitions.
You can add own groups and definitions, just make sure that their ids are unique. You can make each group vertical or horizontal

Counter definition params:
id = unique identifier of the counter
alwaysVisible = if false, counter is displayed only if value is > 0
teamWide = if true, it counts across the whole team
unitNames = list of unit names. You can find them in url of this site https://www.beyondallreason.info/unit/armflea. For example Tick's name is armflea
counterType = COUNTER_TYPE_BASIC or COUNTER_TYPE_STOCKPILE. Basic is just a number of units/buildings. Stockpile shows current stockpile of missiles instead
greenThreshold (optional, only for COUNTER_TYPE_BASIC) = if counter is below greenThreshold the text is yellow. If it's above, the text is green.
skipWhenSpectating = counter won't be shown when spectating
icon = specify which unit icon should be displayed. For example icon = "armack"
isGrouped = if true then each entry from unitNames will be displayed as separate tracker
]]

local COUNTER_TYPE_BASIC, COUNTER_TYPE_STOCKPILE = "basic", "stockpile"
local COUNTER_TYPE_HORIZONTAL, COUNTER_TYPE_VERTICAL = "horizontal", "vertical"

return {
    buildings = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "pinpointers",
                alwaysVisible = true,
                teamWide = true,
                unitNames = { armtarg = true, cortarg = true, },
                counterType = COUNTER_TYPE_BASIC,
                greenThreshold = 3
            },
            {
                id = "nukes",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armsilo = true, corsilo = true },
                counterType = COUNTER_TYPE_STOCKPILE
            },
            {
                id = "junos",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armjuno = true, corjuno = true, },
                counterType = COUNTER_TYPE_STOCKPILE
            },
        }
    },
    airUnits = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "airUnits",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armca = true, corca = true, corcsa = true, armcsa = true, armaca = true, coraca = true,
                              armatlas = true, armdfly = true, corvalk = true, corseah = true, armpeep = true,
                              armsehak = true, armawac = true, corfink = true, corhunt = true, legatrans = true, corhvytrans = true, armhvytrans = true, leghvytrans = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
        }
    },
    groundCons = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "groundCons",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armck = true, corck = true, armcv = true, corcv = true, cormuskrat = true, armbeaver = true,
                    armcs = true, corcs = true, corch = true, armch = true, armack = true, corack = true,
                    armacv = true, coracv = true, armacsub = true, coracsub = true, armfark = true, armconsul = true,
                    corfast = true, armrectr = true, cornecro = true, },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
        }
    },
    labs = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "labs",
                alwaysVisible = false,
                teamWide = false,
                unitNames = {
                    armsy = true, armlab = true, armvp = true, armap = true, armfhp = true, armhp = true,
                    armamsub = true, armplat = true, corsy = true, corlab = true, corvp = true, corap = true,
                    corfhp = true, corhp = true, coramsub = true, corplat = true, armalab = true, armavp = true,
                    armaap = true, armfhp = true, armasy = true, coravp = true, coralab = true, corasy = true,
                    coraap = true, armshltxuw = true, armshltx = true, corgant = true, corgantuw = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                isGrouped = true,
            },
        }
    },
    special = {
        type = COUNTER_TYPE_HORIZONTAL,
        counterDefinitions = {
            {
                id = "spies",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { armspy = true, corspy = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "armspy"
            },
            {
                id = "skuttles",
                alwaysVisible = false,
                teamWide = false,
                unitNames = { corsktl = true },
                counterType = COUNTER_TYPE_BASIC,
                skipWhenSpectating = true,
                icon = "corsktl"
            }
        }
    },
}