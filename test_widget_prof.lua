--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:GetInfo()
    return {
        name = "TEST Widget Profiler",
        desc = "",
        author = "jK, Bluestone, SuperKitowiec",
        version = "2.0",
        date = "2007+",
        license = "GNU GPL, v2 or later",
        layer = -1000000,
        handler = true,
        enabled = false
    }
end

local usePrefixedNames = true

local tick = 0.1
local averageTime = 0.5

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local spGetLuaMemUsage = Spring.GetLuaMemUsage



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local prefixedWnames = {}
local function ConstructPrefixedName (ghInfo)
    local gadgetName = ghInfo.name
    local baseName = ghInfo.basename
    local _pos = baseName:find("_", 1, true)
    local prefix = ((_pos and usePrefixedNames) and (baseName:sub(1, _pos - 1) .. ": ") or "")
    local prefixedGadgetName = "\255\200\200\200" .. prefix .. "\255\255\255\255" .. gadgetName

    prefixedWnames[gadgetName] = prefixedGadgetName
    return prefixedWnames[gadgetName]
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local callinStats = {}
local highres
local spGetTimer = Spring.GetTimer

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

local function contains(table, val)
    for i = 1, #table do
        if table[i] == val then
            return true
        end
    end
    return false
end

local function debug(message)
    Spring.Echo(dump(message))
    Spring.SendCommands(string.format("say a:%s", dump(message)))
end

if Spring.GetTimerMicros and Spring.GetConfigInt("UseHighResTimer", 0) == 1 then
    spGetTimer = Spring.GetTimerMicros
    highres = true
end

Spring.Echo("Profiler using highres timers", highres, Spring.GetConfigInt("UseHighResTimer", 0))

local spDiffTimers = Spring.DiffTimers
local s

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local function ArrayInsert(t, f, g)
    if f then
        local layer = g.whInfo.layer
        local index = 1
        for i, v in ipairs(t) do
            if v == g then
                return -- already in the table
            end
            if layer >= v.whInfo.layer then
                index = i + 1
            end
        end
        table.insert(t, index, g)
    end
end

local function ArrayRemove(t, g)
    for k, v in ipairs(t) do
        if v == g then
            table.remove(t, k)
            -- break
        end
    end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

-- make a table of the names of user widgets



function widget:TextCommand(s)
    local token = {}
    local n = 0
    --for w in string.gmatch(s, "%a+") do
    for w in string.gmatch(s, "%S+") do
        n = n + 1
        token[n] = w
    end
    if token[1] == "widgetprofilertickrate" then
        if token[2] then
            tick = tonumber(token[2]) or tick
        end
        if token[3] then
            averageTime = tonumber(token[3]) or averageTime
        end
        Spring.Echo("Setting widget profiler to tick=", tick, "averageTime=", averageTime)
    end

end

local userWidgets = {}
local sortedList = {}
function widget:Initialize()
    WG.WidgetProfiler = { }
    WG.WidgetProfiler.getResults = function()
        return sortedList
    end
    for name, wData in pairs(widgetHandler.knownWidgets) do
        userWidgets[name] = (not wData.fromZip)
    end
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local oldUpdateWidgetCallIn
local oldInsertWidget

local listOfHooks = {}
setmetatable(listOfHooks, { __mode = 'k' })

local inHook = false
local function IsHook(func)
    return listOfHooks[func]
end

local function Hook(w, name)
    -- name is the callin
    local wname = w.whInfo.name

    local realFunc = w[name]
    w["_old" .. name] = realFunc

    if (widgetName == "Widget Profiler") then
        return realFunc -- don't profile the profilers callins (it works, but it is better that our DrawScreen call is unoptimized and expensive anyway!)
    end

    local widgetCallinTime = callinStats[wname] or {}
    callinStats[wname] = widgetCallinTime
    widgetCallinTime[name] = widgetCallinTime[name] or { 0, 0, 0, 0 }
    local c = widgetCallinTime[name]

    local t

    local helper_func = function(...)
        local dt = spDiffTimers(spGetTimer(), t, nil, highres)
        local _, _, new_s, _ = spGetLuaMemUsage()
        local ds = new_s - s
        c[1] = c[1] + dt
        c[2] = c[2] + dt
        c[3] = c[3] + ds
        c[4] = c[4] + ds
        inHook = nil
        return ...
    end

    local hook_func = function(...)
        if inHook then
            return realFunc(...)
        end

        inHook = true
        t = spGetTimer()
        local _, _, new_s, _ = spGetLuaMemUsage()
        s = new_s
        return helper_func(realFunc(...))
    end

    listOfHooks[hook_func] = true

    return hook_func
end

local function prepareCallInsList()
    local wh = widgetHandler
    local CallInsList = {}
    local CallInsListCount = 0

    for name, e in pairs(wh) do
        local i = name:find("List", nil, true)
        if i and type(e) == "table" then
            CallInsListCount = CallInsListCount + 1
            CallInsList[CallInsListCount] = name:sub(1, i - 1)
        end
    end

    return CallInsList
end

local function StartHook()
    Spring.Echo("start profiling")

    local wh = widgetHandler

    --wh.actionHandler:AddAction("widgetprofiler", widgetprofileraction, "Configure the tick rate of the widget profiler", 't')

    local CallInsList = prepareCallInsList()

    --// hook all existing callins
    for _, callin in ipairs(CallInsList) do
        local callinGadgets = wh[callin .. "List"]
        for _, w in ipairs(callinGadgets or {}) do
            w[callin] = Hook(w, callin)
        end
    end

    Spring.Echo("hooked all callins")

    --// hook the UpdateCallin function
    oldUpdateWidgetCallIn = wh.UpdateWidgetCallIn
    wh.UpdateWidgetCallIn = function(self, name, w)
        local listName = name .. 'List'
        local ciList = self[listName]
        if ciList then
            local func = w[name]
            if type(func) == 'function' then
                if not IsHook(func) then
                    w[name] = Hook(w, name)
                end
                ArrayInsert(ciList, func, w)
            else
                ArrayRemove(ciList, w)
            end
            self:UpdateCallIn(name)
        else
            print('UpdateWidgetCallIn: bad name: ' .. name)
        end
    end

    Spring.Echo("hooked UpdateCallin")

    --// hook the InsertWidget function
    oldInsertWidget = wh.InsertWidget
    widgetHandler.InsertWidget = function(self, widget)
        if widget == nil then
            return
        end

        oldInsertWidget(self, widget)

        for _, callin in ipairs(CallInsList) do
            local func = widget[callin]
            if type(func) == 'function' then
                widget[callin] = Hook(widget, callin)
            end
        end
    end

    Spring.Echo("hooked InsertWidget")
end

local function StopHook()
    Spring.Echo("stop profiling")

    local wh = widgetHandler
    --widgetHandler.RemoveAction("widgetprofiler")
    local CallInsList = prepareCallInsList()

    --// unhook all existing callins
    for _, callin in ipairs(CallInsList) do
        local callinWidgets = wh[callin .. "List"]
        for _, w in ipairs(callinWidgets or {}) do
            if w["_old" .. callin] then
                w[callin] = w["_old" .. callin]
            end
        end
    end

    Spring.Echo("unhooked all callins")

    --// unhook the UpdateCallin and InsertWidget functions
    wh.UpdateWidgetCallIn = oldUpdateWidgetCallIn
    Spring.Echo("unhooked UpdateCallin")
    wh.InsertWidget = oldInsertWidget
    Spring.Echo("unhooked InsertWidget")
end

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

local timeLoadAverages = {}
local spaceLoadAverages = {}
local startTimer

function widget:Update()
    widgetHandler:RemoveWidgetCallIn("Update", self)
    StartHook()
    startTimer = spGetTimer()
end

function widget:Shutdown()
    StopHook()
    WG.WidgetProfiler = nil

end

local lm, _, gm, _, um, _, sm, _ = spGetLuaMemUsage()

local allOverTime = 0
local allOverTimeSec = 0 -- currently unused
local allOverSpace = 0
local totalSpace = {}

local deltaTime
local redStrength = {}

local minPerc = 0.005 -- above this value, we fade in how red we mark a widget
local maxPerc = 0.02 -- above this value, we mark a widget as red
local minSpace = 10 -- Kb
local maxSpace = 100

local title_colour = "\255\160\255\160"
local totals_colour = "\255\200\200\255"

local exp = math.exp

local function CalcLoad(old_load, new_load, t)
    if t and t > 0 then
        local exptick = exp(-tick / t)
        return old_load * exptick + new_load * (1 - exptick)
    else
        return new_load
    end
end

function ColourString(R, G, B)
    local R255 = math.floor(R * 255)
    local G255 = math.floor(G * 255)
    local B255 = math.floor(B * 255)
    if R255 % 10 == 0 then
        R255 = R255 + 1
    end
    if G255 % 10 == 0 then
        G255 = G255 + 1
    end
    if B255 % 10 == 0 then
        B255 = B255 + 1
    end
    return "\255" .. string.char(R255) .. string.char(G255) .. string.char(B255)
end

function GetRedColourStrings(v)
    --tLoad is %
    local tTime = v.tTime
    local sLoad = v.sLoad
    local name = v.plainname
    local u = math.exp(-deltaTime / 5) --magic colour changing rate

    if tTime > maxPerc then
        tTime = maxPerc
    end
    if tTime < minPerc then
        tTime = minPerc
    end

    -- time
    local new_r = (tTime - minPerc) / (maxPerc - minPerc)
    redStrength[name .. '_time'] = redStrength[name .. '_time'] or 0
    redStrength[name .. '_time'] = u * redStrength[name .. '_time'] + (1 - u) * new_r
    local r, g, b = 1, 1 - redStrength[name .. "_time"] * ((255 - 64) / 255), 1 - redStrength[name .. "_time"] * ((255 - 64) / 255)
    v.timeColourString = ColourString(r, g, b)

    -- space
    new_r = (sLoad - minSpace) / (maxSpace - minSpace)
    if new_r > 1 then
        new_r = 1
    elseif new_r < 0 then
        new_r = 0
    end
    redStrength[name .. '_space'] = redStrength[name .. '_space'] or 0
    redStrength[name .. '_space'] = u * redStrength[name .. '_space'] + (1 - u) * new_r
    g = 1 - redStrength[name .. "_space"] * ((255 - 64) / 255)
    b = g
    v.spaceColourString = ColourString(r, g, b)
end

function DrawWidgetList(list, name, x, y, j, fontSize, lineSpace, maxLines, colWidth, dataColWidth)
    if j >= maxLines - 5 then
        x = x - colWidth;
        j = 0;
    end
    j = j + 1
    gl.Text(title_colour .. name .. " WIDGETS", x + 152, y - lineSpace * j, fontSize, "no")
    j = j + 2

    for i = 1, #list do
        if j >= maxLines then
            x = x - colWidth;
            j = 0;
        end

        local v = list[i]
        local name = v.plainname
        local wname = v.fullname
        local tLoad = v.tLoad
        local sLoad = v.sLoad
        local tColour = v.timeColourString
        local sColour = v.spaceColourString
        gl.Text(tColour .. ('%.3f%%'):format(tLoad), x, y - lineSpace * j, fontSize, "no")
        gl.Text(sColour .. ('%.1f'):format(sLoad) .. 'kB/s', x + dataColWidth, y - lineSpace * j, fontSize, "no")
        gl.Text(wname, x + dataColWidth * 2, y - lineSpace * j, fontSize, "no")

        j = j + 1
    end

    gl.Text(totals_colour .. ('%.2f%%'):format(list.allOverTime), x, y - lineSpace * j, fontSize, "no")
    gl.Text(totals_colour .. ('%.0f'):format(list.allOverSpace) .. 'kB/s', x + dataColWidth, y - lineSpace * j, fontSize, "no")
    gl.Text(totals_colour .. "totals (" .. string.lower(name) .. ")", x + dataColWidth * 2, y - lineSpace * j, fontSize, "no")
    j = j + 1

    return x, j
end

function widget:DrawScreen()
    if not next(callinStats) then
        return --// nothing to do
    end

    deltaTime = Spring.DiffTimers(spGetTimer(), startTimer, nil, highres)

    -- sort & count timing
    if deltaTime >= tick then
        startTimer = spGetTimer()
        sortedList = {}

        allOverTime = 0
        allOverSpace = 0
        for wname, callins in pairs(callinStats) do
            local t = 0 -- would call it time, but protected
            local cmax_t = 0
            local cmaxname_t = "-"
            local space = 0
            local cmax_space = 0
            local cmaxname_space = "-"
            for cname, c in pairs(callins) do
                t = t + c[1]
                if c[2] > cmax_t then
                    cmax_t = c[2]
                    cmaxname_t = cname
                end
                c[1] = 0

                space = space + c[3]
                if c[4] > cmax_space then
                    cmax_space = c[4]
                    cmaxname_space = cname
                end
                c[3] = 0
            end

            local relTime = 100 * t / deltaTime
            timeLoadAverages[wname] = CalcLoad(timeLoadAverages[wname] or relTime, relTime, averageTime)

            local relSpace = space / deltaTime
            spaceLoadAverages[wname] = CalcLoad(spaceLoadAverages[wname] or relSpace, relSpace, averageTime)

            allOverTimeSec = allOverTimeSec + t

            local tLoad = timeLoadAverages[wname]
            local sLoad = spaceLoadAverages[wname]
            sortedList[wname] = { plainname = wname, fullname = wname .. ' \255\200\200\200(' .. cmaxname_t .. ',' .. cmaxname_space .. ')', tLoad = tLoad, sLoad = sLoad, tTime = t / deltaTime }
        end

        lm, _, gm, _, um, _, sm, _ = spGetLuaMemUsage()
    end
end



--------------------------------------------------------------------------------
--------------------------------------------------------------------------------