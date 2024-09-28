if Spring.IsReplay() then
    return
end

local widgetName = "Just Buttons"

function widget:GetInfo()
    return {
        name = widgetName,
        desc = "Buttons to easily add units and stuff",
        author = "SuperKitowiec",
        version = 0.1,
        license = "GNU GPL, v2 or later",
        handler = true,
        layer = 0
    }
end

local requiredFrameworkVersion = 43
local font, MasterFramework, key
local white, lightBlack

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

local function ActionButton(action)
    return MasterFramework:HorizontalStack({
        MasterFramework:Button(
                MasterFramework:MarginAroundRect(
                        TextWithBackground(MasterFramework:Text(action, white, font)),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3),
                        MasterFramework:AutoScalingDimension(3)
                ),
                function()
                    Spring.SendCommands(action)
                end), },
            MasterFramework:AutoScalingDimension(1), 1
    )
end

local gf = Spring.GetGameFrame()

function widget:Initialize()
    MasterFramework = WG["MasterFramework " .. requiredFrameworkVersion]
    if not MasterFramework then
        error("[WidgetName] Error: MasterFramework " .. requiredFrameworkVersion .. " not found! Removing self.")
    end

    lightBlack = MasterFramework:Color(0, 0, 0, 0.8)
    white = MasterFramework:Color(0.92, 0.92, 0.92, 1)
    font = MasterFramework:Font("Exo2-SemiBold.otf", 20)

    local contentStack = MasterFramework:VerticalStack({
        MasterFramework:HorizontalStack({
            ActionButton("give 20 armrectr"),
            ActionButton("give 4 cortitan"),
            ActionButton("give armatlas"),
        }, MasterFramework:AutoScalingDimension(1), 1),
        MasterFramework:HorizontalStack({
            ActionButton("pause"),
        }, MasterFramework:AutoScalingDimension(1), 1),
    }, MasterFramework:AutoScalingDimension(1), 1)

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

    if not Spring.IsCheatingEnabled() then
        Spring.SendCommands("say !cheats")
        Spring.SendCommands("cheat")
    end
end

function widget:Shutdown()
    MasterFramework:RemoveElement(key)
end