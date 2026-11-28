--[[
    NV32 Router Controller
    Author: Nikolas Smith, Q-SYS
    Version: 5.2 | Date: 2026-11-27
    Firmware Req: 10.0.0

    NV32 HDMI routing, room controls (power / fire alarm), UCI nav via uciController component.
    Durham: btnNav07 routes HDMI1→Output1 and HDMI2→Output2; power-on and init route HDMI1 to all active outputs.
    5.2: each decision stated once (button feedback, pin binding, power/fire inputs, output lookup)
    Source buttons show NV32-reported routes only (no optimistic feedback).
]]--

-------------------[ Configuration ]-------------------

compType = {
    nv32 = "streamer_hdmi_switcher",
    roomControls = "device_controller_script",
    uciController = "device_controller_script",
}

compName = {
    roomControls = "^compRoomControls",
    uciController = "^uciController",
}

enableOutput2 = true

input = {
    Graphic1 = 1, Graphic2 = 2, Graphic3 = 3,
    HDMI1 = 4, HDMI2 = 5, HDMI3 = 6,
    Mediacast1 = 7,
}

output = { Out01 = 1, Out02 = 2 }

-- source button order on each output row (button i routes uciInputs[i])
uciInputs = { input.HDMI1, input.HDMI2, input.HDMI3, input.Mediacast1, input.Graphic1 }

-- what the room-controls script drives
powerOnInput   = input.HDMI1        -- system power on, init, and fire-alarm restore fallback
powerOffInput  = input.Mediacast1   -- system power off
fireAlarmInput = input.Graphic1     -- fire alarm active

-- indexed by output number; disabled outputs are skipped everywhere
outputConfigs = {
    [output.Out01] = { controlName = "hdmi.out.1.select.index", buttons = Controls.btnOut01, label = "Output 1", enabled = true },
    [output.Out02] = { controlName = "hdmi.out.2.select.index", buttons = Controls.btnOut02, label = "Output 2", enabled = enableOutput2 },
}

-- UCI nav button -> routes applied when it is pressed
uciNavRoute = {
    btnNav07 = {
        { input = uciInputs[1], output = output.Out01 },
        { input = uciInputs[2], output = output.Out02 },
    },
    btnNav08 = {
        { input = uciInputs[3], output = output.Out01 },
        { input = uciInputs[3], output = output.Out02 },
    },
    btnNav09 = {
        { input = uciInputs[4], output = output.Out01 },
    },
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compNV32 = nil
compRmCtls = nil
compUCICtls = nil
preFireAlarmRoutes = {}

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
scriptName = "NV32 Router"
fireAlarmActive = false   -- edge guard so a repeated alarm event can't overwrite the saved routes

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
    if stateDebug then print("[" .. scriptName .. "] " .. str) end
end

-- Text Controller pins are a single control at count 1 and an array above 1
function asControlList(ctl)
    if not ctl then return {} end
    if type(ctl) == "table" then return ctl end
    return { ctl }
end

-- run fn(outputNum, cfg) for every enabled output
function forEachOutput(fn)
    for outputNum, cfg in ipairs(outputConfigs) do
        if cfg.enabled then fn(outputNum, cfg) end
    end
end

-- attach (or release) handlers on another component's pins; missing pins are skipped
function bindPins(comp, handlers, attach)
    if comp == nil then return end
    for name, handler in pairs(handlers) do
        if comp[name] then comp[name].EventHandler = attach and handler or nil end
    end
end

-------------------[ Status ]-------------------

function getStatus()
    for _, invalid in pairs(compInvalid) do
        if invalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

-- bind the component named in a selector; returns nil when cleared or invalid
function setComp(ctl, componentType)
    local name = ctl.String
    if name == "" or name == strClear then
        ctl.String = ""
        ctl.Color = "white"
        compInvalid[componentType] = false
        getStatus()
        return nil
    end
    local comp = Component.New(name)
    local valid = #Component.GetControls(comp) > 0
    ctl.Color = valid and "white" or "pink"
    compInvalid[componentType] = not valid
    getStatus()
    if not valid then
        ctl.String = "[Invalid Component Selected]"
        debugMsg("Invalid " .. componentType .. ": " .. name)
        return nil
    end
    debugMsg("Connected " .. componentType .. ": " .. name)
    return comp
end

-------------------[ Discovery ]-------------------

-- sort and load a selector's choices; auto-select the first when empty
function fillChoices(ctl, names, label)
    if #names < 1 then return end
    table.sort(names)
    ctl.Choices = names
    if ctl.String == "" or ctl.String == strClear then
        ctl.String = names[1]
        debugMsg("Auto-populated " .. label .. ": " .. names[1])
    end
end

function getComponentNames()
    local nv32Names, roomNames, uciNames = {}, {}, {}
    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == compType.nv32 then
            table.insert(nv32Names, comp.Name)
        elseif comp.Type == compType.roomControls and comp.Name:match(compName.roomControls) then
            table.insert(roomNames, comp.Name)
        elseif comp.Type == compType.uciController and comp.Name:match(compName.uciController) then
            table.insert(uciNames, comp.Name)
        end
    end
    fillChoices(Controls.devNV32, nv32Names, "devNV32")
    fillChoices(Controls.compRoomControls, roomNames, "compRoomControls")
    fillChoices(Controls.compUCIController, uciNames, "compUCIController")
    debugMsg("Discovery complete - NV32: " .. #nv32Names .. ", Room Controls: " .. #roomNames .. ", UCI Controller: " .. #uciNames)
end

-------------------[ Routing ]-------------------

-- NV32 select control for an enabled output, or nil
function getOutputControl(outputNum)
    local cfg = outputConfigs[outputNum]
    if compNV32 == nil or not cfg or not cfg.enabled then return nil end
    return compNV32[cfg.controlName]
end

-- light the button whose input the NV32 reports live on this output
function syncButtons(outputNum)
    local outCtl = getOutputControl(outputNum)
    if not outCtl then return end
    for i, btn in ipairs(asControlList(outputConfigs[outputNum].buttons)) do
        btn.Boolean = (uciInputs[i] == outCtl.Value)
    end
end

function setRoute(inputNum, outputNum, source)
    local outCtl = getOutputControl(outputNum)
    if not outCtl then
        debugMsg("Output " .. tostring(outputNum) .. " unavailable (" .. source .. ")")
        return
    end
    if outCtl.Value == inputNum then return end
    outCtl.Value = inputNum -- buttons follow when the NV32 reports the change (nv32Handlers)
    debugMsg("Output " .. outputNum .. " -> Input " .. inputNum .. " (" .. source .. ")")
end

function setRouteAllOutputs(inputNum, source)
    forEachOutput(function(outputNum) setRoute(inputNum, outputNum, source) end)
end

-------------------[ NV32 ]-------------------

-- NV32 output selects -> source buttons; the only path that drives button feedback
nv32Handlers = {}
for outputNum, cfg in ipairs(outputConfigs) do
    nv32Handlers[cfg.controlName] = function() syncButtons(outputNum) end
end

function setcompNV32()
    bindPins(compNV32, nv32Handlers, false) -- release the previous NV32
    compNV32 = setComp(Controls.devNV32, "NV32")
    bindPins(compNV32, nv32Handlers, true)
    for _, handler in pairs(nv32Handlers) do handler() end -- read the NV32's current routes on bind
end

-------------------[ Room Controls ]-------------------

function storePreFireAlarmRoutes()
    preFireAlarmRoutes = {}
    forEachOutput(function(outputNum)
        local outCtl = getOutputControl(outputNum)
        if outCtl then preFireAlarmRoutes[outputNum] = outCtl.Value end
    end)
end

function restorePreFireAlarmRoutes()
    forEachOutput(function(outputNum)
        setRoute(preFireAlarmRoutes[outputNum] or powerOnInput, outputNum, "Room Controls: Fire Alarm Clear")
    end)
end

-- room-controls pins this script listens to (either may be missing on a given automation script)
roomControlHandlers = {
    ledSystemPower = function(ctl)
        -- power on -> powerOnInput, power off -> powerOffInput, on every enabled output
        debugMsg("System power " .. (ctl.Boolean and "ON" or "OFF"))
        setRouteAllOutputs(ctl.Boolean and powerOnInput or powerOffInput, "Room Controls: System Power")
    end,
    ledFireAlarm = function(ctl)
        -- alarm -> save routes and show fireAlarmInput; clear -> restore saved routes only if the system is on
        if ctl.Boolean == fireAlarmActive then return end
        fireAlarmActive = ctl.Boolean
        local power = compRmCtls["ledSystemPower"]
        if fireAlarmActive then
            debugMsg("Fire alarm ACTIVE")
            storePreFireAlarmRoutes()
            setRouteAllOutputs(fireAlarmInput, "Room Controls: Fire Alarm")
        else
            debugMsg("Fire alarm CLEAR")
            if power and power.Boolean then restorePreFireAlarmRoutes() end
            preFireAlarmRoutes = {}
        end
    end,
}

function setcompRmCtls()
    bindPins(compRmCtls, roomControlHandlers, false) -- release the previous room script
    compRmCtls = setComp(Controls.compRoomControls, "Room Controls")
    bindPins(compRmCtls, roomControlHandlers, true)
end

-------------------[ UCI Controller ]-------------------

-- UCI nav button press -> that button's routes from uciNavRoute
uciNavHandlers = {}
for btnName, routes in pairs(uciNavRoute) do
    uciNavHandlers[btnName] = function(ctl)
        if not ctl.Boolean then return end
        debugMsg(btnName .. " selected")
        for _, route in ipairs(routes) do setRoute(route.input, route.output, "UCI Nav: " .. btnName) end
    end
end

function setcompUCICtls()
    bindPins(compUCICtls, uciNavHandlers, false) -- release the previous UCI controller
    compUCICtls = setComp(Controls.compUCIController, "UCI Controller")
    bindPins(compUCICtls, uciNavHandlers, true)
end

-------------------[ Event Handlers ]-------------------

-- component selectors
Controls.devNV32.EventHandler = setcompNV32
Controls.compRoomControls.EventHandler = setcompRmCtls
Controls.compUCIController.EventHandler = setcompUCICtls

-- source buttons on each output row -> route that button's input
forEachOutput(function(outputNum, cfg)
    for i, btn in ipairs(asControlList(cfg.buttons)) do
        btn.EventHandler = function() setRoute(uciInputs[i], outputNum, cfg.label) end
    end
end)

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")
    getComponentNames()
    setcompNV32()
    setcompRmCtls()
    setcompUCICtls()
    if compNV32 then setRouteAllOutputs(powerOnInput, "Init") end
    debugMsg("=== Initialization Complete ===")
end

funcInit()
