--[[
    NV32 Router Controller - Q-SYS Control Script
    Author: Nikolas Smith, Q-SYS
    Version: 5.2 | Date: 2026-10-23
    Firmware Req: 10.0.0

    NV32 HDMI routing, room controls (power / fire alarm), UCI nav via uciController component.
]]--

-------------------[ Configuration ]-------------------

compType = {
    nv32          = "streamer_hdmi_switcher",
    roomControls  = "device_controller_script",
    uciController = "device_controller_script",
}

compNameMatch = {
    roomControls  = "^compRoomControls",
    uciController = "^uciController",
}

enableOutput2 = false -- set to true to enable control on HDMI Output 2

input = {
    Graphic1 = 1, Graphic2 = 2, Graphic3 = 3,
    HDMI1 = 4, HDMI2 = 5, HDMI3 = 6,
    AV1 = 7, AV2 = 8, AV3 = 9,
}

output = { Out01 = 1, Out02 = 2 }

inputPowerOn  = nil            -- nil = do not change NV32 routing (UCI / nav owns the source)
inputPowerOff = input.AV1
inputFireAlarm = input.Graphic1

uciInputs = { input.AV1, input.AV2, input.AV3, input.Graphic1, input.Graphic2 }

outputConfigs = {
    { output = output.Out01, controlName = "hdmi.out.1.select.index", buttons = Controls.btnOut01, label = "Output 1", enabled = true },
    { output = output.Out02, controlName = "hdmi.out.2.select.index", buttons = Controls.btnOut02, label = "Output 2", enabled = enableOutput2 },
}

uciNavRoute = {
    btnNav07 = {
        { input = uciInputs[1], output = output.Out01 },
        { input = uciInputs[1], output = output.Out02 },
    },
    btnNav08 = {
        { input = uciInputs[2], output = output.Out01 },
        { input = uciInputs[2], output = output.Out02 },
    },
    btnNav09 = {
        { input = uciInputs[3], output = output.Out01 },
        { input = uciInputs[3], output = output.Out02 },
    },
    btnNav10 = {
        { input = uciInputs[3], output = output.Out01 },
        { input = uciInputs[3], output = output.Out02 },
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

function getOutputConfig(outputNum)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.output == outputNum then return cfg end
    end
    return nil
end

function getOutputControl(outputNum)
    local cfg = getOutputConfig(outputNum)
    if not compNV32 or not cfg or not cfg.enabled then return nil end
    return compNV32[cfg.controlName]
end

function forEachOutput(fn)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.enabled then fn(cfg) end
    end
end

-------------------[ Status ]-------------------

function getStatus()
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

function setCompInvalid(compStatus)
    compInvalid[compStatus] = true
    getStatus()
end

function setCompValid(compStatus)
    compInvalid[compStatus] = false
    getStatus()
end

function setComp(ctl, compStatus)
    if not ctl then setCompInvalid(compStatus); return nil end

    local name = ctl.String
    if not name or name == "" then
        ctl.Color = "white"
        setCompValid(compStatus)
        return nil
    end
    if name == strClear then
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(compStatus)
        debugMsg(compStatus .. " cleared")
        return nil
    end

    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(compStatus)
        debugMsg("Invalid " .. compStatus .. ": " .. name)
        return nil
    end
    ctl.Color = "white"
    setCompValid(compStatus)
    debugMsg("Connected " .. compStatus .. ": " .. name)
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
        elseif comp.Type == compType.roomControls and string.match(comp.Name, compNameMatch.roomControls) then
            table.insert(roomNames, comp.Name)
        elseif comp.Type == compType.uciController and string.match(comp.Name, compNameMatch.uciController) then
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

function setRoute(inputNum, outputNum, source)
    source = source or "Internal"

    local cfg = getOutputConfig(outputNum)
    if not cfg or not cfg.enabled then return false end

    local outputControl = getOutputControl(outputNum)
    if not outputControl then
        debugMsg("Missing output control " .. tostring(outputNum) .. " (" .. source .. ")")
        return false
    end
    if not inputNum then
        debugMsg("Missing input for output " .. tostring(outputNum) .. " (" .. source .. ")")
        return false
    end
    if outputControl.Value == inputNum then return false end
    outputControl.Value = inputNum
    debugMsg("Output " .. tostring(outputNum) .. " -> Input " .. tostring(inputNum) .. " (" .. source .. ")")
    return true
end

function setRouteAllOutputs(inputNum, source)
    forEachOutput(function(cfg) setRoute(inputNum, cfg.output, source) end)
end

function applyNavRoutes(routes, source)
    for _, route in ipairs(routes) do
        setRoute(route.input, route.output, source)
    end
end

-------------------[ NV32 ]-------------------

function setOutputFeedback(cfg)
    local outCtl = getOutputControl(cfg.output)
    if not outCtl or not cfg.buttons then return end

    for i, btn in ipairs(cfg.buttons) do
        local isActive = (uciInputs[i] == outCtl.Value)
        if btn.Boolean ~= isActive then btn.Boolean = isActive end
    end
end

function syncOutputFeedback()
    forEachOutput(setOutputFeedback)
end

function cleanupNV32Handlers()
    if not compNV32 then return end
    for _, cfg in ipairs(outputConfigs) do
        local ctl = compNV32[cfg.controlName]
        if ctl then ctl.EventHandler = nil end
    end
end

function setcompNV32()
    cleanupNV32Handlers()
    compNV32 = setComp(Controls.devNV32, "NV32")
    if not compNV32 then return end

    forEachOutput(function(cfg)
        local outCtl = compNV32[cfg.controlName]
        if outCtl then outCtl.EventHandler = function() setOutputFeedback(cfg) end end
    end)
    syncOutputFeedback()
end

-------------------[ Room Controls ]-------------------

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

function cleanupRmCtlsHandlers()
    if not compRmCtls then return end
    if compRmCtls["ledSystemPower"] then compRmCtls["ledSystemPower"].EventHandler = nil end
    if compRmCtls["ledFireAlarm"] then compRmCtls["ledFireAlarm"].EventHandler = nil end
end

function setcompRmCtls()
    cleanupRmCtlsHandlers()
    compRmCtls = setComp(Controls.compRoomControls, "Room Controls")
    if not compRmCtls then return end

    local powerLED = compRmCtls["ledSystemPower"]
    local fireAlarmLED = compRmCtls["ledFireAlarm"]

    if powerLED then
        powerLED.EventHandler = function(ctl)
            debugMsg("System power " .. (ctl.Boolean and "ON" or "OFF"))
            if ctl.Boolean then
                if inputPowerOn then
                    setRouteAllOutputs(inputPowerOn, "Room Controls: System Power ON")
                end
                syncOutputFeedback()
            else
                setRouteAllOutputs(inputPowerOff, "Room Controls: System Power OFF")
            end
        end
    end
    if fireAlarmLED then
        fireAlarmLED.EventHandler = function(ctl)
            if ctl.Boolean and not fireAlarmActive then
                fireAlarmActive = true
                storePreFireAlarmRoutes()
                debugMsg("Fire alarm ACTIVE")
                setRouteAllOutputs(inputFireAlarm, "Room Controls: Fire Alarm")
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

if Controls.devNV32 then Controls.devNV32.EventHandler = setcompNV32 end
if Controls.compRoomControls then Controls.compRoomControls.EventHandler = setcompRmCtls end
if Controls.compUCIController then Controls.compUCIController.EventHandler = setcompUCICtls end

forEachOutput(function(cfg)
    if not cfg.buttons then return end

    for i, btn in ipairs(cfg.buttons) do
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
    if compNV32 and inputPowerOn then
        setRouteAllOutputs(inputPowerOn, "Init")
    end
    syncOutputFeedback()
    debugMsg("=== Initialization Complete ===")
end

funcInit()
