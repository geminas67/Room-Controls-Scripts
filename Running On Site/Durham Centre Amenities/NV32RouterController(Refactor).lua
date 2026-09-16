--[[
    NV32 Router Controller
    Author: Nikolas Smith, Q-SYS
    Version: 5.0 | Date: 2026-06-26
    Firmware Req: 10.0.0
    NV32 HDMI routing, room controls (power / fire alarm), UCI nav via uciController component.
    Durham: btnNav07/08 route HDMI1→Output1 and HDMI2→Output2; power-on and init force HDMI1 to all active outputs.
]]--

--------** Constant Tables **--------

compInvalid  = {}   -- invalid component flags by type
compNV32     = nil  -- NV32 streamer block reference
compRmCtls   = nil  -- room controls script reference (optional)
compUCICtls  = nil  -- UCI controller script reference (optional)

--------** Constants **--------

stateDebug    = true
strClear      = "[Clear]"
compName      = "NV32 Router"
enableOutput2 = true

typeNV32      = "streamer_hdmi_switcher"
typeRmCtls    = "device_controller_script"
typeUCICtls   = "device_controller_script"

inputs = {
    Graphic1 = 1, Graphic2 = 2, Graphic3 = 3,
    HDMI1 = 4, HDMI2 = 5, HDMI3 = 6,
    Mediacast1 = 7,
}
outputs = { Output01 = 1, Output02 = 2 }

-- Button row order matches uciInputs indices (output preset buttons)
uciInputs = { inputs.HDMI1, inputs.HDMI2, inputs.HDMI3, inputs.Graphic1, inputs.Graphic2 }

-- btnNav on uciController → per-output routes (edit input/output pairs per button)
uciNavRoutes = {
    btnNav07 = {
        { input = uciInputs[1], output = outputs.Output01 },
        { input = uciInputs[2], output = outputs.Output02 },
    },
    btnNav08 = {
        { input = uciInputs[1], output = outputs.Output01 },
        { input = uciInputs[1], output = outputs.Output02 },
    },
    btnNav09 = {
        { input = uciInputs[3], output = outputs.Output01 },
    },
}

fireAlarmActive   = false
lastInput         = {}
preFireAlarmInput = {}

--------** Functions **--------

--------## Debug ##--------

function debugMsg(str)
    if stateDebug then
        print("[" .. compName .. "] " .. str)
    end
end

function getButtonArray(ctl)
    if not ctl then return nil end
    if type(ctl) == "table" then return ctl end
    return { ctl }
end

--------## Status ##--------

function checkStatus()
    for _, isInvalid in pairs(compInvalid) do
        if isInvalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value  = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value  = 0
end

function setCompInvalid(componentType)
    compInvalid[componentType] = true
    checkStatus()
end

function setCompValid(componentType)
    compInvalid[componentType] = false
    checkStatus()
end

--------## System Components ##--------

function discoverComponents()
    debugMsg("Discovering components...")
    local nv32Names = {}
    local compNames = {}
    local uciNames  = {}

    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == typeNV32 then
            table.insert(nv32Names, comp.Name)
            debugMsg("  Found NV32: " .. comp.Name)
        elseif comp.Type == typeRmCtls and string.match(comp.Name, "^compRoomControls") then
            table.insert(compNames, comp.Name)
            debugMsg("  Found Room Controls: " .. comp.Name)
        elseif comp.Type == typeUCICtls and string.match(comp.Name, "^uciController") then
            table.insert(uciNames, comp.Name)
            debugMsg("  Found UCI Controller: " .. comp.Name)
        end
    end

    table.sort(nv32Names)
    table.sort(compNames)
    table.sort(uciNames)
    debugMsg("Discovery complete - NV32: " .. #nv32Names
        .. ", Room Controls: " .. #compNames
        .. ", UCI Controller: " .. #uciNames)
    return nv32Names, compNames, uciNames
end

function setComp(ctl, componentType)
    if not ctl then
        setCompInvalid(componentType)
        return nil
    end

    local name = ctl.String
    if not name or name == "" then
        debugMsg("No " .. componentType .. " component selected")
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    elseif name == strClear then
        debugMsg(componentType .. ": Component cleared")
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    end

    local comp     = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        debugMsg("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end

    debugMsg("Connected " .. componentType .. ": " .. name)
    ctl.Color = "white"
    setCompValid(componentType)
    return comp
end

function setupComponents()
    local nv32Names, compNames, uciNames = discoverComponents()

    local function autoFill(ctl, names, label)
        if not ctl or #names < 1 then return end
        ctl.Choices = names
        local str = ctl.String
        if str == "" or str == strClear then
            ctl.String = names[1]
            debugMsg("Auto-populated " .. label .. ": " .. names[1])
        end
    end

    autoFill(Controls.devNV32, nv32Names, "devNV32")
    autoFill(Controls.compRoomControls, compNames, "compRoomControls")
    autoFill(Controls.compUCIController, uciNames, "compUCIController")
end

--------## NV32 Routing ##--------

function isOutputActive(outputNum)
    return outputNum ~= outputs.Output02 or enableOutput2
end

function forEachOutput(fn)
    if isOutputActive(outputs.Output01) then fn(outputs.Output01) end
    if isOutputActive(outputs.Output02) then fn(outputs.Output02) end
end

function setRoute(input, outputNum, source)
    source = source or "Internal"
    if not isOutputActive(outputNum) then
        debugMsg("Output " .. tostring(outputNum) .. " disabled — skip (Source: " .. tostring(source) .. ")")
        return false
    end
    if not compNV32 then
        debugMsg("No NV32 router (Source: " .. tostring(source) .. ")")
        return false
    end

    local outputControl = compNV32["hdmi.out." .. tostring(outputNum) .. ".select.index"]
    if not outputControl then
        debugMsg("Missing output control " .. tostring(outputNum) .. " (Source: " .. tostring(source) .. ")")
        return false
    end
    if outputControl.Value == input then return false end

    outputControl.Value = input
    lastInput[outputNum] = input
    debugMsg("Output " .. tostring(outputNum) .. " → Input " .. tostring(input) .. " (Source: " .. tostring(source) .. ")")
    return true
end

function setRouteAllOutputs(input, source)
    forEachOutput(function(out) setRoute(input, out, source) end)
end

--------## NV32 Router ##--------

function cleanupNV32Handlers()
    if not compNV32 then return end
    if compNV32["hdmi.out.1.select.index"] then compNV32["hdmi.out.1.select.index"].EventHandler = nil end
    if compNV32["hdmi.out.2.select.index"] then compNV32["hdmi.out.2.select.index"].EventHandler = nil end
end

function bindOutputFeedback(outCtl, btnArray)
    if not outCtl or not btnArray then return end
    outCtl.EventHandler = function(ctl)
        local inputValue = ctl.Value
        for i, btn in ipairs(btnArray) do
            if btn.Boolean ~= (uciInputs[i] == inputValue) then
                btn.Boolean = (uciInputs[i] == inputValue)
            end
        end
        debugMsg("Output feedback → Input " .. tostring(inputValue))
    end
end

function setcompNV32()
    cleanupNV32Handlers()

    local prev = Controls.devNV32.String
    compNV32 = setComp(Controls.devNV32, "NV32")
    debugMsg("NV32 component: '" .. prev .. "' → '" .. Controls.devNV32.String .. "'")
    if not compNV32 then return end

    local outputFeedback = {
        { outputs.Output01, "hdmi.out.1.select.index", getButtonArray(Controls.btnOut01) },
        { outputs.Output02, "hdmi.out.2.select.index", getButtonArray(Controls.btnOut02) },
    }
    for _, cfg in ipairs(outputFeedback) do
        if isOutputActive(cfg[1]) then
            bindOutputFeedback(compNV32[cfg[2]], cfg[3])
        end
    end
end

--------## Room Controls ##--------

function cleanupRmCtlsHandlers()
    if not compRmCtls then return end
    if compRmCtls["ledSystemPower"] then compRmCtls["ledSystemPower"].EventHandler = nil end
    if compRmCtls["ledFireAlarm"]  then compRmCtls["ledFireAlarm"].EventHandler  = nil end
end

function setcompRmCtls()
    cleanupRmCtlsHandlers()

    compRmCtls = setComp(Controls.compRoomControls, "Room Controls")
    if not compRmCtls then return end

    local powerLED = compRmCtls["ledSystemPower"]
    if powerLED then
        powerLED.EventHandler = function(ctl)
            local targetInput = ctl.Boolean and uciInputs[1] or uciInputs[4]
            debugMsg("System power → " .. (ctl.Boolean and "ON" or "OFF"))
            setRouteAllOutputs(targetInput, "Room Controls: System Power")
        end
    end

    local fireAlarmLED = compRmCtls["ledFireAlarm"]
    if fireAlarmLED then
        fireAlarmLED.EventHandler = function(ctl)
            if ctl.Boolean and not fireAlarmActive then
                forEachOutput(function(out)
                    preFireAlarmInput[out] = lastInput[out]
                end)
                fireAlarmActive = true
                debugMsg("Fire alarm → ACTIVE, routing Graphic2 to outputs")
                setRouteAllOutputs(uciInputs[5], "Room Controls: Fire Alarm")
            elseif not ctl.Boolean and fireAlarmActive then
                fireAlarmActive = false
                debugMsg("Fire alarm → CLEAR")
                if powerLED and powerLED.Boolean then
                    forEachOutput(function(out)
                        setRoute(preFireAlarmInput[out] or uciInputs[1], out, "Room Controls: Fire Alarm Clear")
                    end)
                end
                forEachOutput(function(out) preFireAlarmInput[out] = nil end)
            end
        end
    end
end

--------## UCI ##--------

function cleanupUCINavHandlers()
    if not compUCICtls then return end
    for btnName in pairs(uciNavRoutes) do
        if compUCICtls[btnName] then compUCICtls[btnName].EventHandler = nil end
    end
end

function applyNavRoutes(routes, source)
    for _, route in ipairs(routes) do
        setRoute(route.input, route.output, source)
    end
end

function setcompUCICtls()
    cleanupUCINavHandlers()

    if not Controls.compUCIController then return end

    compUCICtls = setComp(Controls.compUCIController, "UCI Controller")
    if not compUCICtls then return end

    for btnName, routes in pairs(uciNavRoutes) do
        local btn = compUCICtls[btnName]
        if btn and routes and #routes > 0 then
            btn.EventHandler = function(ctl)
                if not ctl.Boolean then return end
                debugMsg(btnName .. " → " .. #routes .. " route(s)")
                applyNavRoutes(routes, "UCI Nav Button")
            end
            debugMsg("Registered UCI button: " .. btnName)
        end
    end
end

--------** Event Handlers **--------

Controls.devNV32.EventHandler = setcompNV32

if Controls.compRoomControls then
    Controls.compRoomControls.EventHandler = setcompRmCtls
end

if Controls.compUCIController then
    Controls.compUCIController.EventHandler = setcompUCICtls
end

local outputButtons = {
    { outputs.Output01, getButtonArray(Controls.btnOut01), "Output 1" },
    { outputs.Output02, getButtonArray(Controls.btnOut02), "Output 2" },
}
for _, cfg in ipairs(outputButtons) do
    if isOutputActive(cfg[1]) and cfg[2] then
        for i, btn in ipairs(cfg[2]) do
            btn.EventHandler = function()
                setRoute(uciInputs[i], cfg[1], cfg[3])
            end
        end
    end
end

--------** Always Run **--------

function funcInit()
    debugMsg("=== Initialization Started ===")

    setupComponents()
    setcompNV32()
    setcompRmCtls()
    setcompUCICtls()

    if compNV32 then
        setRouteAllOutputs(uciInputs[1], "Init")
    end

    debugMsg("=== Initialization Complete ===")
end

funcInit()
