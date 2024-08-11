local widgetName = "Widgets Toolbar"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Shows buttons to restart custom widgets",
        author = "SuperKitowiec",
        version = 0.1,
        license = "GNU GPL, v2 or later",
        handler = true,
        layer = 0
    }
end

local handledWidgets = {
    --widgetName,
    "Buildings/Units Tracker",
    --"TEST Widget Profiler"
}

local requiredFrameworkVersion = 43
local font, MasterFramework, key
local red, green, yellow, white, backgroundColor, lightBlack

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
    local text = dump(message)
    Spring.Echo(text)
    if string.len(text) < 30 then
        Spring.SendCommands(string.format("say a:%s", text))
    end
end

local param1, param2, rows

local function TextWithBackground(text)
    return MasterFramework:Background(
            MasterFramework:MarginAroundRect(
                    text,
                    MasterFramework:AutoScalingDimension(5),
                    MasterFramework:AutoScalingDimension(1),
                    MasterFramework:AutoScalingDimension(3),
                    MasterFramework:AutoScalingDimension(2)
            ),
            { lightBlack },
            MasterFramework:AutoScalingDimension(5)
    )
end

local function WidgetRow(name)
    local color = widgetHandler.knownWidgets[name].active and green or red
    local text = MasterFramework:Text(name, color, font)

    return MasterFramework:HorizontalStack({
        MasterFramework:Button(
                MasterFramework:MarginAroundRect(
                        TextWithBackground(text),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3)
                ),
                function()
                    if (name == widgetName) then
                        widgetHandler:DisableWidget(name)
                        widgetHandler:EnableWidget(name)
                    else
                        widgetHandler:ToggleWidget(name)
                    end
                    text:SetBaseColor(widgetHandler.knownWidgets[name].active and green or red)
                end),
       TextWithBackground(param1),
       TextWithBackground(param2)
    }, MasterFramework:AutoScalingDimension(1), 1
    )


end

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end

    lightBlack = MasterFramework:Color(0, 0, 0, 0.8)
    backgroundColor = MasterFramework:Color(0, 0, 0, 0.9)
    red = MasterFramework:Color(0.9, 0, 0, 1)
    green = MasterFramework:Color(0.4, 0.92, 0.4, 1)
    yellow = MasterFramework:Color(0.9, 0.9, 0, 1)
    white = MasterFramework:Color(0.92, 0.92, 0.92, 1)
    font = MasterFramework:Font("Exo2-SemiBold.otf", 20)

    param1 = MasterFramework:Text("", white, font)
    param2 = MasterFramework:Text("", white, font)

    rows = {}

    for _, name in ipairs(handledWidgets) do
        if widgetHandler:IsWidgetKnown(name) then
            table.insert(rows, WidgetRow(name))
        end
    end

    local contentStack = MasterFramework:VerticalStack(rows, MasterFramework:AutoScalingDimension(1), 1)
    local frameId = widgetName .. "frameId"

    key = MasterFramework:InsertElement(
            MasterFramework:MovableFrame(
                    frameId,
                    MasterFramework:PrimaryFrame(
                            MasterFramework:MarginAroundRect(
                                    contentStack,
                                    MasterFramework:AutoScalingDimension(5),
                                    MasterFramework:AutoScalingDimension(5),
                                    MasterFramework:AutoScalingDimension(5),
                                    MasterFramework:AutoScalingDimension(5)
                            )
                    ),
                    1700,
                    900
            ),
            frameId,
            MasterFramework.layerRequest.bottom()
    )
end

function widget:GameFrame(frame)
    if (frame % 5 == 0) then
        param1:SetString(('%.3f%%'):format(WG.WidgetProfiler:getResults()["Buildings/Units Tracker"].tLoad))
        param2:SetString(('%.1f'):format(WG.WidgetProfiler:getResults()["Buildings/Units Tracker"].sLoad) .. 'kB/s')
    end
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
end