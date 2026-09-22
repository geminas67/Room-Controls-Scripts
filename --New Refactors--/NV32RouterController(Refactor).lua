--[[
    NV32 Router Controller
    Author: Nikolas Smith, Q-SYS
    Version: 5.1 | Date: 2026-09-17
    Firmware Req: 10.0.0

    NV32 HDMI routing, room controls (power / fire alarm), UCI nav via uciController component.
    Durham: btnNav07 routes HDMI1→Output1 and HDMI2→Output2; power-on and init route HDMI1 to all active output.
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

uciInputs = { input.HDMI1, input.HDMI2, input.HDMI3, input.Mediacast1, input.Graphic1 }

outputConfigs = {
    { output = output.Out01, controlName = "hdmi.out.1.select.index", buttons = Controls.btnOut01, label = "Output 1", enabled = true },
    { output = output.Out02, controlName = "hdmi.out.2.select.index", buttons = Controls.btnOut02, label = "Output 2", enabled = enableOutput2 },
}

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
fireAlarmActive = false

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
    if stateDebug then print("[" .. scriptName .. "] " .. str) end
end

function getButtonArray(ctl)
    if not ctl then return nil end
    if type(ctl) == "table" then return ctl end
    return { ctl }
end

function getOutputConfig(outputNum)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.output == outputNum then return cfg end
    end
    return nil
end

function forEachOutput(fn)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.enabled then fn(cfg) end
    end
end

function getOutputControl(outputNum)
    local cfg = getOutputConfig(outputNum)
    if not compNV32 or not cfg then return nil end
    return compNV32[cfg.controlName]
end

-------------------[ Status ]-------------------

function checkStatus()
    for _, isInvalid in pairs(compInvalid) do
        if isInvalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

function setCompInvalid(componentType)
    compInvalid[componentType] = true
    checkStatus()
end

function setCompValid(componentType)
    compInvalid[componentType] = false
    checkStatus()
end

function setComp(ctl, componentType)
    if not ctl then setCompInvalid(componentType); return nil end

    local name = ctl.String
    if not name or name == "" then
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    end

    if name == strClear then
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        debugMsg(componentType .. " cleared")
        return nil
    end

    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        debugMsg("Invalid " .. componentType .. ": " .. name)
        return nil
    end

    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("Connected " .. componentType .. ": " .. name)
    return comp
end

-------------------[ Discovery ]-------------------

function fillChoices(ctl, names, label)
    if not ctl or #names < 1 then return end
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
        elseif comp.Type == compType.roomControls and string.match(comp.Name, compName.roomControls) then
            table.insert(roomNames, comp.Name)
        elseif comp.Type == compType.uciController and string.match(comp.Name, compName.uciController) then
            table.insert(uciNames, comp.Name)
        end
    end

    table.sort(nv32Names)
    table.sort(roomNames)
    table.sort(uciNames)

    fillChoices(Controls.devNV32, nv32Names, "devNV32")
    fillChoices(Controls.compRoomControls, roomNames, "compRoomControls")
    fillChoices(Controls.compUCIController, uciNames, "compUCIController")

    debugMsg("Discovery complete - NV32: " .. #nv32Names .. ", Room Controls: " .. #roomNames .. ", UCI Controller: " .. #uciNames)
end

-------------------[ Routing ]-------------------

function setRoute(input, outputNum, source)
    source = source or "Internal"

    local outputControl = getOutputControl(outputNum)
    if not outputControl then
        debugMsg("Missing output control " .. tostring(outputNum) .. " (" .. source .. ")")
        return false
    end

    if outputControl.Value == input then return false end
    outputControl.Value = input
    debugMsg("Output " .. tostring(outputNum) .. " -> Input " .. tostring(input) .. " (" .. source .. ")")
    return true
end

function setRouteAllOutputs(input, source)
    forEachOutput(function(cfg) setRoute(input, cfg.output, source) end)
end

function applyNavRoutes(routes, source)
    for _, route in ipairs(routes) do
        setRoute(route.input, route.output, source)
    end
end

-------------------[ NV32 ]-------------------

function cleanupNV32Handlers()
    if not compNV32 then return end
    for _, cfg in ipairs(outputConfigs) do
        local ctl = compNV32[cfg.controlName]
        if ctl then ctl.EventHandler = nil end
    end
end

function bindOutputFeedback(outCtl, buttons)
    local btnArray = getButtonArray(buttons)
    if not outCtl or not btnArray then return end

    outCtl.EventHandler = function(ctl)
        for i, btn in ipairs(btnArray) do
            btn.Boolean = (uciInputs[i] == ctl.Value)
        end
    end
end

function syncOutputFeedback()
    if not compNV32 then return end

    forEachOutput(function(cfg)
        local outCtl = compNV32[cfg.controlName]
        local btnArray = getButtonArray(cfg.buttons)
        if not outCtl or not btnArray then return end

        for i, btn in ipairs(btnArray) do
            btn.Boolean = (uciInputs[i] == outCtl.Value)
        end
    end)
end

function setcompNV32()
    cleanupNV32Handlers()
    compNV32 = setComp(Controls.devNV32, "NV32")
    if not compNV32 then return end

    forEachOutput(function(cfg)
        bindOutputFeedback(compNV32[cfg.controlName], cfg.buttons)
    end)

    syncOutputFeedback()
end

-------------------[ Room Controls ]-------------------

function cleanupRmCtlsHandlers()
    if not compRmCtls then return end
    if compRmCtls["ledSystemPower"] then compRmCtls["ledSystemPower"].EventHandler = nil end
    if compRmCtls["ledFireAlarm"] then compRmCtls["ledFireAlarm"].EventHandler = nil end
end

function storePreFireAlarmRoutes()
    preFireAlarmRoutes = {}
    forEachOutput(function(cfg)
        local outCtl = getOutputControl(cfg.output)
        if outCtl then preFireAlarmRoutes[cfg.output] = outCtl.Value end
    end)
end

function restorePreFireAlarmRoutes()
    forEachOutput(function(cfg)
        setRoute(preFireAlarmRoutes[cfg.output] or uciInputs[1], cfg.output, "Room Controls: Fire Alarm Clear")
    end)
    preFireAlarmRoutes = {}
end

function setcompRmCtls()
    cleanupRmCtlsHandlers()
    compRmCtls = setComp(Controls.compRoomControls, "Room Controls")
    if not compRmCtls then return end

    local powerLED = compRmCtls["ledSystemPower"]
    local fireAlarmLED = compRmCtls["ledFireAlarm"]

    if powerLED then
        powerLED.EventHandler = function(ctl)
            local targetInput = ctl.Boolean and uciInputs[1] or uciInputs[4]
            debugMsg("System power " .. (ctl.Boolean and "ON" or "OFF"))
            setRouteAllOutputs(targetInput, "Room Controls: System Power")
        end
    end

    if fireAlarmLED then
        fireAlarmLED.EventHandler = function(ctl)
            if ctl.Boolean and not fireAlarmActive then
                fireAlarmActive = true
                storePreFireAlarmRoutes()
                debugMsg("Fire alarm ACTIVE")
                setRouteAllOutputs(uciInputs[5], "Room Controls: Fire Alarm")
            elseif not ctl.Boolean and fireAlarmActive then
                fireAlarmActive = false
                debugMsg("Fire alarm CLEAR")
                if powerLED and powerLED.Boolean then
                    restorePreFireAlarmRoutes()
                else
                    preFireAlarmRoutes = {}
                end
            end
        end
    end
end

-------------------[ UCI Controller ]-------------------

function cleanupUCINavHandlers()
    if not compUCICtls then return end
    for btnName in pairs(uciNavRoute) do
        if compUCICtls[btnName] then compUCICtls[btnName].EventHandler = nil end
    end
end

function setcompUCICtls()
    cleanupUCINavHandlers()
    if not Controls.compUCIController then return end

    compUCICtls = setComp(Controls.compUCIController, "UCI Controller")
    if not compUCICtls then return end

    for btnName, routes in pairs(uciNavRoute) do
        local btn = compUCICtls[btnName]
        if btn and #routes > 0 then
            btn.EventHandler = function(ctl)
                if not ctl.Boolean then return end
                debugMsg(btnName .. " selected")
                applyNavRoutes(routes, "UCI Nav: " .. btnName)
            end
        end
    end
end

-------------------[ Event Handlers ]-------------------

Controls.devNV32.EventHandler = setcompNV32

if Controls.compRoomControls then
    Controls.compRoomControls.EventHandler = setcompRmCtls
end

if Controls.compUCIController then
    Controls.compUCIController.EventHandler = setcompUCICtls
end

forEachOutput(function(cfg)
    local btnArray = getButtonArray(cfg.buttons)
    if not btnArray then return end

    for i, btn in ipairs(btnArray) do
        btn.EventHandler = function()
            setRoute(uciInputs[i], cfg.output, cfg.label)
        end
    end
end)

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")

    getComponentNames()
    setcompNV32()
    setcompRmCtls()
    setcompUCICtls()

    if compNV32 then
        setRouteAllOutputs(uciInputs[1], "Init")
        syncOutputFeedback()
    end

    debugMsg("=== Initialization Complete ===")
end

funcInit()
