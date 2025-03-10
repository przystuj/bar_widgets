include("keysym.h.lua")

function widget:GetInfo()
    return {
        name = "Air Defense Range",
        desc = "Displays range of enemy air defenses",
        author = "lov",
        date = "2023",
        license = "GNU GPL v2",
        layer = 0,
        enabled = false
    }
end

-- CONFIGURATION
local lowspec = false -- if your computer is low spec
--local keycode = 112   -- o key
local onlyShowWhenAircraftSelected = true
local drawToggle = true
local drawMode = 1

local enabledAsSpec = true
local pi = math.pi

local function rgb(r, b, g, a)
    return { r / 255, b / 255, g / 255 }
end

local lightAaColor = rgb(242, 121, 0)
local heavyAaColor = rgb(255, 0, 0)
local longRangeAaColor = rgb(0, 0, 255)
local antiNukeColor = rgb(255, 0, 0)
local alphamax = 30 -- limits the maximum alpha that overlapping circles can reach
local drawalpha = 10
local alphaincrement = 10
local antiAirList = {
    -- ARMADA
    armrl = { weapons = { 2 }, color = lightAaColor, weaponheight = 64 }, --nettle
    armfrt = { weapons = { 2 }, color = lightAaColor, weaponheight = 64 }, --floating nettle
    armferret = { weapons = { 2 }, color = lightAaColor, weaponheight = 16 },
    armfrock = { weapons = { 2 }, color = lightAaColor, weaponheight = 29 },
    armcir = { weapons = { 2 }, color = longRangeAaColor, weaponheight = 46 }, --chainsaw
    armflak = { weapons = { 2 }, color = heavyAaColor, weaponheight = 44 },
    armfflak = { weapons = { 2 }, color = heavyAaColor }, --floating flak AA
    armmercury = { weapons = { 1 }, color = longRangeAaColor, weaponheight = 70 },
    armsam = { weapons = { 2 }, color = lightAaColor }, --whistler
    armjeth = { weapons = { 2 }, color = lightAaColor }, --bot
    armamph = { weapons = { 2 }, color = lightAaColor }, --platypus
    armaak = { weapons = { 2 }, color = lightAaColor }, -- t2bot
    armlatnk = { weapons = { 2 }, color = lightAaColor }, --jaguar
    armyork = { weapons = { 2 }, color = heavyAaColor }, --mflak
    armpt = { weapons = { 2 }, color = lightAaColor }, --boat
    armaas = { weapons = { 2 }, color = lightAaColor }, --t2boat
    armah = { weapons = { 2 }, color = lightAaColor }, --hover

    corrl = { weapons = { 2 }, color = lightAaColor },
    corfrt = { weapons = { 2 }, color = lightAaColor }, --floating rocket laucher
    cormadsam = { weapons = { 2 }, color = lightAaColor },
    corfrock = { weapons = { 2 }, color = lightAaColor },
    corflak = { weapons = { 2 }, color = heavyAaColor },
    cornaa = { weapons = { 2 }, color = heavyAaColor },
    corscreamer = { weapons = { 1 }, color = longRangeAaColor, weaponheight = 59 },
    corcrash = { weapons = { 2 }, color = lightAaColor }, --bot
    coraak = { weapons = { 2 }, color = lightAaColor }, --t2bot
    cormist = { weapons = { 2 }, color = lightAaColor }, --lasher
    corsent = { weapons = { 2 }, color = heavyAaColor }, --flak
    corban = { weapons = { 2 }, color = longRangeAaColor },
    corpt = { weapons = { 2 }, color = lightAaColor }, --boat
    corarch = { weapons = { 2 }, color = lightAaColor }, --t2boat
    corah = { weapons = { 2 }, color = lightAaColor }, --hover
}
local antiNukeNames = {
    armamd = true,
    armscab = true,
    corfmd = true,
    cormabm = true,
}
local nukeNames = {
    corsilo = true,
    armsilo = true,
}
-- cache only what we use
local weapTab = {} --WeaponDefs
local wdefParams = {
    "salvoSize",
    "reload",
    "coverageRange",
    "damages",
    "range",
    "type",
    "projectilespeed",
    "heightBoostFactor",
    "heightMod",
    "heightBoostFactor",
    "projectilespeed",
    "myGravity"
}
for weaponDefID, weaponDef in pairs(WeaponDefs) do
    weapTab[weaponDefID] = {}
    for i, param in ipairs(wdefParams) do
        weapTab[weaponDefID][param] = weaponDef[param]
    end
end
wdefParams = nil

local unitRadius = {}
local unitNumWeapons = {}
local canMove = {}
local unitSpeeds = {}
local unitName = {}
local unitWeapons = {}
for unitDefID, unitDef in pairs(UnitDefs) do
    unitRadius[unitDefID] = unitDef.radius
    local weapons = unitDef.weapons
    if #weapons > 0 then
        unitNumWeapons[unitDefID] = #weapons
        for i = 1, #weapons do
            if not unitWeapons[unitDefID] then
                unitWeapons[unitDefID] = {}
            end
            unitWeapons[unitDefID][i] = weapons[i].weaponDef
        end
    end
    unitSpeeds[unitDefID] = unitDef.speed
    -- for a, b in unitDef:pairs() do
    -- 	Spring.Echo(a, b)
    -- end
    canMove[unitDefID] = unitDef.canMove
    unitName[unitDefID] = unitDef.name
end

--Button display configuration
--position only relevant if no saved config data found
local buttonConfig = {}
buttonConfig["enabled"] = {
    ally = { ground = false, air = false, nuke = false, radar = false },
    enemy = { ground = true, air = true, nuke = true, radar = false }
}

local rangeCircleList  --glList for drawing range circles

local spGetSpectatingState = Spring.GetSpectatingState
local spec, fullview = spGetSpectatingState()
local myAllyTeam = Spring.GetMyAllyTeamID()

local defences = {}

local lineConfig = {}
lineConfig["lineWidth"] = 1.5 -- calcs dynamic now
lineConfig["alphaValue"] = 0.0 --> dynamic behavior can be found in the function "widget:Update"
lineConfig["circleDivs"] = 80.0

local myPlayerID

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------
---
local GL_LINE_LOOP = GL.LINE_LOOP
local glBeginEnd = gl.BeginEnd
local glColor = gl.Color
local glDepthTest = gl.DepthTest
local glLineWidth = gl.LineWidth
local glTranslate = gl.Translate
local glVertex = gl.Vertex
local glCallList = gl.CallList
local glCreateList = gl.CreateList
local glDeleteList = gl.DeleteList

local sqrt = math.sqrt
local abs = math.abs
local upper = string.upper
local floor = math.floor
local PI = math.pi
local cos = math.cos
local sin = math.sin

local spEcho = Spring.Echo
local spGetGameSeconds = Spring.GetGameSeconds
local spGetMyPlayerID = Spring.GetMyPlayerID
local spGetPlayerInfo = Spring.GetPlayerInfo
local spGetPositionLosState = Spring.GetPositionLosState
local spGetUnitDefID = Spring.GetUnitDefID
local spGetUnitPosition = Spring.GetUnitPosition
local spGetGroundHeight = Spring.GetGroundHeight
local spIsGUIHidden = Spring.IsGUIHidden
local spGetLocalTeamID = Spring.GetLocalTeamID
local spIsSphereInView = Spring.IsSphereInView

local chobbyInterface

local mapBaseHeight
local h = {}
for i = 1, 3 do
    for i = 1, 3 do
        h[#h + 1] = Spring.GetGroundHeight(Game.mapSizeX * i / 4, Game.mapSizeZ * i / 4)
    end
end
mapBaseHeight = 0
for _, s in ipairs(h) do
    mapBaseHeight = mapBaseHeight + s
end
mapBaseHeight = mapBaseHeight / #h
local gy = math.max(0, mapBaseHeight)

--------------------------------------------------------------------------------
--------------------------------------------------------------------------------

function widget:Shutdown()
    if rangeCircleList then
        gl.DeleteList(rangeCircleList)
    end
end

local function init()
    if WG.options then
        WG.options.addOption(
                {
                    widgetname = "Air Defense Range",
                    id = "airdeftoggle",
                    group = "custom",
                    category = 2,
                    name = "When should it show",
                    type = "select",
                    options = { "When aricraft selected", "Toggle with keybind", "Always" },
                    value = drawMode,
                    description = "Toggle between always showing the rings or only when aircraft are selected.",
                    onload = function(i)
                        --onlyShowWhenAircraftSelected = true
                    end,
                    onchange = function(i, value)
                        drawMode = value
                        onlyShowWhenAircraftSelected = drawMode == 1
                    end
                }
        )
        WG.options.addOption(
                {
                    widgetname = "Air Defense Range",
                    id = "airdefalpha",
                    group = "custom",
                    category = 2,
                    name = "Alpha",
                    type = "slider",
                    min = 0,
                    max = 99,
                    step = 1,
                    value = drawalpha,
                    description = "Set the alpha of the rings",
                    onload = function(i)
                        --onlyShowWhenAircraftSelected = true
                    end,
                    onchange = function(i, value)
                        drawalpha = tonumber(value)
                    end
                }
        )
    end
    local units = Spring.GetAllUnits()
    for i = 1, #units do
        local unitID = units[i]
        UnitDetected(unitID, Spring.IsUnitAllied(unitID))
        -- Spring.Echo("height", unitID, Spring.GetUnitDefID(unitID), Spring.GetUnitHeight(unitID), Spring.GetUnitMass(unitID),
        -- 	Spring.GetUnitRadius(unitID), Spring.GetUnitArmored(unitID))
    end
end

local function toggleAARanges()
    drawToggle = not drawToggle
    local text = "off"
    if drawToggle then
        text = "on"
    end
    Spring.Echo("AA ranges toggled " .. text)
end

function widget:Initialize()
    myPlayerID = spGetLocalTeamID()
    widgetHandler:AddAction("toggle_aa_ranges", toggleAARanges, nil, "p")

    init()
end

function widget:KeyPress(key, modifier, isRepeat)
    if key == keycode then
        drawalpha = (drawalpha + alphaincrement) % alphamax
        UpdateCircleList()
    end
end

function widget:UnitEnteredLos(unitID, allyTeam)
    UnitDetected(unitID, false, allyTeam)
end

function widget:UnitEnteredRadar(unitID, allyTeam)
    if defences[unitID] then
        local i
        for i = 1, #defences[unitID].weapons do
            defences[unitID].weapons[i].range = defences[unitID].weapons[i].originalrange
        end
    end
end

local function traceRay(x, y, z, tx, ty, tz)
    local stepsize = 3
    local dx = tx - x
    local dy = ty - y
    local dz = tz - z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if not (distance > stepsize) then
        return tx, ty, tz
    end
    local iterations = distance / stepsize
    local nx = dx / distance
    local ny = dy / distance
    local nz = dz / distance
    local height
    for i = 0, iterations do
        x = x + nx * stepsize
        y = y + ny * stepsize
        z = z + nz * stepsize
        height = Spring.GetGroundHeight(x, z)
        if y < height then
            return x, height, z
        end
    end
    return tx, ty, tz
end

local function drawCircle(x, y, z, range, weaponheight, donttraceray)
    if lowspec then
        donttraceray = true
    end
    local altitude = 85
    local list = { { x, y + weaponheight, z } }
    local numSegments = 100
    local angleStep = (2 * pi) / numSegments
    local gy = Spring.GetGroundHeight(x, z)
    for i = 0, numSegments do
        local angle = i * angleStep
        local rx = sin(angle) * range + x
        local rz = cos(angle) * range + z
        local dx = x - rx
        local dz = z - rz
        local len2d = math.sqrt(dx ^ 2 + dz ^ 2)
        local splits = 30
        local step = len2d / splits
        dx = dx / len2d
        dz = dz / len2d
        local j = 0
        local ry = Spring.GetGroundHeight(rx, rz) + altitude
        while j < splits - 1 and not donttraceray do
            local hx, hy, hz = traceRay(x, gy + weaponheight, z, rx, ry, rz)
            if hx == rx and hy == ry and hz == rz then
                j = splits + 1 -- exit
            else
                rx = rx + dx * step
                rz = rz + dz * step
                ry = Spring.GetGroundHeight(rx, rz) + altitude
                j = j + 1
            end
        end

        list[#list + 1] = { rx, ry, rz }
    end
    return list
end

local function whatToShow()
    local selectedUnits = Spring.GetSelectedUnits()
    local aircraftSelected = false
    local showAntinukes = false
    local showAntiair = true
    for _, uID in ipairs(selectedUnits) do
        local unitDef = UnitDefs[Spring.GetUnitDefID(uID)]
        if unitDef.canFly then
            aircraftSelected = true
        end
        if nukeNames[unitDef.name] then
            showAntinukes = true
        end
    end
    if (not aircraftSelected) and onlyShowWhenAircraftSelected then
        showAntiair = false
    end
    return showAntiair, showAntinukes
end

local function ShouldEnd()
    if drawMode == 2 then
        return drawToggle
    end
    if drawMode == 3 then
        return false
    end
    if fullview and not enabledAsSpec then
        return true
    end
    if drawalpha == 0 then
        return true
    end
    local showAntiair, showAntinukes = whatToShow()
    if not showAntiair and not showAntinukes then
        return true
    end
    return false
end

local function handleAntiAir(unitID, unitDefID, uName, allyTeam)
    if antiAirList[uName] == nil then
        return
    end

    local x, y, z = spGetUnitPosition(unitID)
    local foundWeapons = {}
    for i = 1, unitNumWeapons[unitDefID] do
        if antiAirList[uName]["weapons"][i] then
            local weaponDef = weapTab[unitWeapons[unitDefID][i]]
            local range = weaponDef.range --get normal weapon range
            local type = antiAirList[uName]["weapons"][i]
            local dam = weaponDef.damages
            local dps, damage
            local color = antiAirList[uName].color
            color[4] = .2

            dps = 0
            damage = dam[Game.armorTypes.vtol]
            if damage then
                dps = damage * weaponDef.salvoSize / weaponDef.reload
            end

            -- color1 = GetColorsByTypeAndDps(dps, type, (allyTeam == false))

            local weaponheight = antiAirList[uName].weaponheight or 63
            local verts = drawCircle(x, y, z, range, weaponheight, type == 1)

            foundWeapons[#foundWeapons + 1] = {
                type = type,
                range = range,
                originalrange = range,
                color1 = color,
                unitID = unitID,
                weaponnum = i,
                weaponheight = weaponheight,
                verts = verts,
                x = x,
                y = y,
                z = z
            }
        end
    end
    defences[unitID] = {
        allyState = (allyTeam == false),
        pos = { x, y, z },
        unitId = unitID,
        mobile = canMove[unitDefID],
        weapons = foundWeapons,
        unitSpeed = unitSpeeds[unitDefID],
        type = 'antiAir'
    }

    UpdateCircleList()
end

local function handleAntiNuke(unitID, uName, allyTeam)
    if not antiNukeNames[uName] then
        return
    end

    local x, y, z = spGetUnitPosition(unitID)
    local weaponHeight = 0
    local weaponRange = 1990
    local verts = drawCircle(x, 0, z, weaponRange, weaponHeight, true)
    defences[unitID] = {
        allyState = (allyTeam == false),
        pos = { x, y, z },
        unitId = unitID,
        mobile = false,
        weapons = { [1] = { type = 1,
                            range = weaponRange,
                            originalrange = weaponRange,
                            color1 = antiNukeColor,
                            unitID = unitID,
                            weaponnum = 1,
                            weaponheight = weaponHeight,
                            verts = verts,
                            x = x,
                            y = y,
                            z = z }
        },
        unitSpeed = 0,
        type = 'antiNuke'
    }

    UpdateCircleList()
end

function UnitDetected(unitID, allyTeam, teamId)
    if allyTeam then
        return
    end
    local unitDefID = spGetUnitDefID(unitID)
    local uName = unitName[unitDefID]
    handleAntiAir(unitID, unitDefID, uName, allyTeam)
    handleAntiNuke(unitID, uName, allyTeam)
end

function ResetGl()
    glColor({ 1.0, 1.0, 1.0, 1.0 })
    glLineWidth(1.0)
end

function widget:PlayerChanged()
    if myAllyTeam ~= Spring.GetMyAllyTeamID() or fullview ~= select(2, spGetSpectatingState()) then
        myAllyTeam = Spring.GetMyAllyTeamID()
        spec, fullview = spGetSpectatingState()
        init()
    end
end

local lastupdate = 0
local updateinterval = .6
function widget:Update()
    if ShouldEnd() then
        return
    end

    local time = spGetGameSeconds()

    if time - lastupdate > updateinterval then
        lastupdate = time
        local didupdate = false
        for k, def in pairs(defences) do
            if def.type == 'antiNuke' then
                didupdate = true
            end
            if def.mobile then
                local ux, uy, uz = Spring.GetUnitPosition(def["unitId"])
                for i = 1, #def.weapons do
                    local weapon = def.weapons[i]
                    local upd = false
                    if not uy then
                        weapon.range = weapon.range - def.unitSpeed * updateinterval
                        upd = true
                    else
                        if weapon.x ~= ux or weapon.y ~= uy or weapon.z ~= uz then
                            upd = true
                        end
                        weapon.x = ux
                        weapon.y = uy
                        weapon.z = uz
                    end
                    if upd then
                        didupdate = true
                        if weapon.range > 0 then
                            weapon.verts = drawCircle(weapon.x, weapon.y, weapon.z, weapon.range, weapon.weaponheight)
                        else
                            defences[k] = nil
                        end
                    end
                end
            end
            local x, y, z = def["pos"][1], def["pos"][2], def["pos"][3]
            local a, b, c = spGetPositionLosState(x, y, z)
            local losState = b
            if losState then
                if not spGetUnitDefID(def["unitId"]) then
                    defences[k] = nil
                    didupdate = true
                end
            end
        end
        if didupdate then
            UpdateCircleList()
        end
    end
end

local function BuildVertexList(verts)
    for i, vert in pairs(verts) do
        glVertex(vert)
    end
end

local function drawRangedInternal(def)
    local showAntiair, showAntinukes = whatToShow()
    if def.type == 'antiNuke' and not showAntinukes then
        return
    end
    if def.type == 'antiAir' and not showAntiair then
        return
    end

    local color
    local range
    local alpha = drawalpha
    if def.type == 'antiNuke' then
        alpha = alpha * 4
    end

    for i, weapon in pairs(def["weapons"]) do
        local execDraw = spIsSphereInView(def["pos"][1], def["pos"][2], def["pos"][3], weapon["range"])
        if execDraw then
            color = weapon["color1"]
            range = weapon["range"]

            gl.Blending("alpha_add")
            if alpha > alphamax then
                alpha = alphamax
            end
            glColor(color[1], color[2], color[3], alpha / 255)
            gl.PolygonMode(GL.FRONT_AND_BACK, GL.FILL)
            glBeginEnd(GL.TRIANGLE_FAN, BuildVertexList, weapon.verts)
        end
    end
end

function DrawRanges()
    glDepthTest(false)
    glTranslate(0, 0, 0) -- else it gets rendered below map sometimes


    for test, def in pairs(defences) do
        gl.PushMatrix()
        drawRangedInternal(def)
        gl.PopMatrix()
    end

    glDepthTest(true)
end

function UpdateCircleList()
    --delete old list
    if rangeCircleList then
        glDeleteList(rangeCircleList)
    end

    rangeCircleList = glCreateList(
            function()
                --create new list
                DrawRanges()
                ResetGl()
            end
    )
end

function widget:RecvLuaMsg(msg, playerID)
    if msg:sub(1, 18) == "LobbyOverlayActive" then
        chobbyInterface = (msg:sub(1, 19) == "LobbyOverlayActive1")
    end
end

function widget:DrawWorld()
    if ShouldEnd() then
        return
    end
    if chobbyInterface then
        return
    end
    if not spIsGUIHidden() and (not WG["topbar"] or not WG["topbar"].showingQuit()) then
        if rangeCircleList then
            glCallList(rangeCircleList)
        else
            UpdateCircleList()
        end
    end
end

function widget:GetConfigData()
    return {
        alpha = drawalpha,
        drawMode = drawMode
    }
end

function widget:SetConfigData(data)
    if data.alpha ~= nil then
        drawalpha = data.alpha
        drawMode = data.mode
    end
end
