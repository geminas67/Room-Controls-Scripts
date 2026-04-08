--[[
    NV32 Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2026-03-29
    Firmware Req: 10.0.0
    Flat singleton: routing, room controls (power / fire alarm), optional UCI nav button sync.
]]--

-------------------[ Configuration ]-------------------
local inputs = {
    Graphic1 = 1, 
    Graphic2 = 2, 
    Graphic3 = 3,
    HDMI1 = 4, 
    HDMI2 = 5,
    HDMI3 = 6,
    AV1 = 7, 
    AV2 = 8, 
    AV3 = 9,
}

local outputs = { Output01 = 1, Output02 = 2 }

-- Button row order matches uciInputs indices (Output preset buttons)
local uciInputs = { inputs.AV1, inputs.AV2, inputs.AV3, inputs.Graphic1, inputs.Graphic2 }

-- UCI nav layer index → uciInputs slot (see btnNav07/08/09)
local uciLayerToInput = {
    [7] = uciInputs[2],
    [8] = uciInputs[1],
    [9] = uciInputs[3],
}

local componentTypes = {
    nv32Router = "streamer_hdmi_switcher",
    roomControls = "device_controller_script",
}

-------------------[ Controls ]-------------------
local controls = {
    devNV32 = Controls.devNV32,
    btnNV32Out01 = Controls.btnNV32Out01,
    btnNV32Out02 = Controls.btnNV32Out02,
    txtStatus = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls,
}

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    local ok = pcall(function() ctrl.EventHandler = handler end)
    return ok
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
        end) then
            count = count + 1
        end
    end
    return count
end

local function cleanupComponentHandlers(oldComp, controlNames, debugCb)
    if not oldComp or not controlNames then return 0 end
    local cleaned = 0
    for _, name in ipairs(controlNames) do
        if oldComp[name] and oldComp[name].EventHandler then
            oldComp[name].EventHandler = nil
            cleaned = cleaned + 1
        end
    end
    if debugCb and cleaned > 0 then debugCb("Cleaned up " .. cleaned .. " handler(s) from old component") end
    return cleaned
end

-------------------[ Config & State ]-------------------
local const = {
    roomName = "NV32 Router",
    debug = true,
    uciIntegrationEnabled = true,
    enableOutput2 = true,
    clearString = "[Clear]",
}

local componentsTbl = {
    nv32Router = nil,
    roomControls = nil,
    invalid = {},
}

local state = {
    lastInput = {},
    preFireAlarmInput = {},
    fireAlarmActive = false,
    uciController = nil,
    lastUCILayer = nil,
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-------------------[ Validation ]-------------------
local function validateControls()
    local required = {
        devNV32 = controls.devNV32,
        txtStatus = controls.txtStatus,
        btnNV32Out01 = controls.btnNV32Out01,
    }
    local optional = {
        btnNV32Out02 = controls.btnNV32Out02,
        compRoomControls = controls.compRoomControls,
    }
    local missing = {}
    for name, control in pairs(required) do
        if not control then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: NV32RouterController validation failed — missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    for name, control in pairs(optional) do
        if not control then
            print("WARNING: NV32RouterController optional control missing: " .. name)
        end
    end
    return true
end

local function normalizeControlArrays()
    for _, controlName in ipairs({ "btnNV32Out01", "btnNV32Out02" }) do
        local control = controls[controlName]
        if control and type(control) ~= "table" then
            controls[controlName] = { control }
        end
    end
end

-------------------[ Component / status ]-------------------
local function checkStatus()
    local txt = controls.txtStatus
    if not txt then return end
    for _, invalid in pairs(componentsTbl.invalid) do
        if invalid == true then
            setProp(txt, "String", "Invalid Components")
            setProp(txt, "Value", 1)
            return
        end
    end
    setProp(txt, "String", "OK")
    setProp(txt, "Value", 0)
end

local function setComponent(ctrl, componentType, expectedType)
    if not ctrl then
        componentsTbl.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        componentsTbl.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        componentsTbl.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    if expectedType and comp.Type ~= expectedType then
        setProp(ctrl, "String", "[Wrong Component Type]")
        setProp(ctrl, "Color", "pink")
        componentsTbl.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: " .. componentType .. " wrong type. Expected " .. tostring(expectedType)
            .. ", got " .. tostring(comp.Type))
        return nil
    end
    setProp(ctrl, "Color", "white")
    componentsTbl.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function discoverAndSetupInitial()
    debugPrint("Discovering components...")
    local nv32Names = {}
    local roomNames = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.nv32Router then
            table.insert(nv32Names, comp.Name)
            debugPrint("  Found NV32-class: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomNames, comp.Name)
            debugPrint("  Found Room Controls: " .. comp.Name)
        end
    end
    debugPrint("Discovery complete — NV32: " .. #nv32Names .. ", Room Controls: " .. #roomNames)
    if #nv32Names > 0 then
        componentsTbl.nv32Router = Component.New(nv32Names[1])
        debugPrint("Initial NV32 from discovery: " .. nv32Names[1])
    end
    if #roomNames > 0 then
        componentsTbl.roomControls = Component.New(roomNames[1])
        debugPrint("Initial Room Controls from discovery: " .. roomNames[1])
    end
end

local routerHandlerControls = { "hdmi.out.1.select.index", "hdmi.out.2.select.index" }

local function setRoute(input, outputNum, source)
    local src = source or "Internal"
    if outputNum == outputs.Output02 and not const.enableOutput2 then
        debugPrint("Output02 disabled — skip (Source: " .. src .. ")")
        return false
    end
    local router = componentsTbl.nv32Router
    if not router then
        debugPrint("No NV32 router (Source: " .. src .. ")")
        return false
    end
    local outputControl = router["hdmi.out." .. tostring(outputNum) .. ".select.index"]
    if not outputControl then
        debugPrint("Missing output control " .. tostring(outputNum) .. " (Source: " .. src .. ")")
        return false
    end
    if outputControl.Value == input then return false end
    setProp(outputControl, "Value", input)
    debugPrint("Output " .. tostring(outputNum) .. " → Input " .. tostring(input) .. " (Source: " .. src .. ")")
    state.lastInput[outputNum] = input
    return true
end

local function setNV32RouterComponent()
    local oldRouter = componentsTbl.nv32Router
    if oldRouter then
        cleanupComponentHandlers(oldRouter, routerHandlerControls, function(msg) debugPrint("[NV32] " .. msg) end)
    end
    componentsTbl.nv32Router = setComponent(controls.devNV32, "NV32-H", componentTypes.nv32Router)
    local router = componentsTbl.nv32Router
    if not router then return end

    local out1 = router["hdmi.out.1.select.index"]
    local out2 = router["hdmi.out.2.select.index"]
    local btnOut01 = controls.btnNV32Out01
    local btnOut02 = controls.btnNV32Out02

    if out1 then
        out1.EventHandler = function(ctl)
            local inputValue = ctl.Value
            if not isArr(btnOut01) then return end
            for i, btn in ipairs(btnOut01) do
                setProp(btn, "Boolean", (uciInputs[i] == inputValue))
            end
            debugPrint("Output 1 feedback → Input " .. tostring(inputValue) .. " (Source: NV32 Router)")
        end
        debugPrint("Registered: hdmi.out.1.select.index feedback handler")
    end

    if out2 and const.enableOutput2 and btnOut02 and isArr(btnOut02) then
        out2.EventHandler = function(ctl)
            local inputValue = ctl.Value
            for i, btn in ipairs(btnOut02) do
                setProp(btn, "Boolean", (uciInputs[i] == inputValue))
            end
            debugPrint("Output 2 feedback → Input " .. tostring(inputValue) .. " (Source: NV32 Router)")
        end
        debugPrint("Registered: hdmi.out.2.select.index feedback handler")
    end
end

local function setRoomControlsComponent()
    componentsTbl.roomControls = setComponent(controls.compRoomControls, "Room Controls", componentTypes.roomControls)
    local roomControls = componentsTbl.roomControls
    if not roomControls then return end

    local powerLED = roomControls["ledSystemPower"]
    if powerLED then
        powerLED.EventHandler = function(ctl)
            local targetInput = ctl.Boolean and uciInputs[1] or uciInputs[4]
            debugPrint("System power → " .. (ctl.Boolean and "ON" or "OFF") .. " (Source: Room Controls)")
            setRoute(targetInput, outputs.Output01, "Room Controls: System Power")
            if const.enableOutput2 then
                setRoute(targetInput, outputs.Output02, "Room Controls: System Power")
            end
        end
        debugPrint("Registered: ledSystemPower handler")
    end

    local fireAlarmLED = roomControls["ledFireAlarm"]
    if fireAlarmLED then
        fireAlarmLED.EventHandler = function(ctl)
            if ctl.Boolean and not state.fireAlarmActive then
                state.preFireAlarmInput[outputs.Output01] = state.lastInput[outputs.Output01]
                if const.enableOutput2 then
                    state.preFireAlarmInput[outputs.Output02] = state.lastInput[outputs.Output02]
                end
                state.fireAlarmActive = true
                debugPrint("Fire alarm → ACTIVE, routing Graphic2 to outputs (Source: Room Controls)")
                setRoute(uciInputs[5], outputs.Output01, "Room Controls: Fire Alarm")
                if const.enableOutput2 then
                    setRoute(uciInputs[5], outputs.Output02, "Room Controls: Fire Alarm")
                end
            elseif not ctl.Boolean and state.fireAlarmActive then
                state.fireAlarmActive = false
                debugPrint("Fire alarm → CLEAR (Source: Room Controls)")
                if powerLED and powerLED.Boolean then
                    local restore1 = state.preFireAlarmInput[outputs.Output01] or uciInputs[1]
                    local restore2 = state.preFireAlarmInput[outputs.Output02] or uciInputs[1]
                    setRoute(restore1, outputs.Output01, "Room Controls: Fire Alarm Clear")
                    if const.enableOutput2 then
                        setRoute(restore2, outputs.Output02, "Room Controls: Fire Alarm Clear")
                    end
                end
                state.preFireAlarmInput[outputs.Output01] = nil
                if const.enableOutput2 then
                    state.preFireAlarmInput[outputs.Output02] = nil
                end
            end
        end
        debugPrint("Registered: ledFireAlarm handler")
    end
end

local function setupDirectUCIButtonMonitoring()
    local uciButtons = {
        [7] = Controls.btnNav07,
        [8] = Controls.btnNav08,
        [9] = Controls.btnNav09,
    }
    local count = 0
    for layer, button in pairs(uciButtons) do
        if button then
            bind(button, function(ctl)
                if not const.uciIntegrationEnabled then return end
                if not ctl.Boolean then return end
                local targetInput = uciLayerToInput[layer]
                if not targetInput then return end
                debugPrint("UCI nav layer " .. tostring(layer) .. " → Input " .. tostring(targetInput)
                    .. " (Source: UCI Nav Button)")
                setRoute(targetInput, outputs.Output01, "UCI Nav Button")
            end)
            count = count + 1
            debugPrint("Registered UCI nav monitor: layer " .. tostring(layer))
        end
    end
    debugPrint("UCI direct button handlers registered: " .. tostring(count))
end

local function setUCIController(uciController)
    if not uciController then
        debugPrint("setUCIController: invalid reference")
        return false
    end
    state.uciController = uciController
    debugPrint("UCI Controller reference set — use onUCILayerChange() from UCI script for layer sync "
        .. "(timer polling removed; nav buttons use direct handlers when present)")
    return true
end

local function enableUCIIntegration()
    const.uciIntegrationEnabled = true
    debugPrint("UCI integration enabled")
end

local function disableUCIIntegration()
    const.uciIntegrationEnabled = false
    debugPrint("UCI integration disabled")
end

local function onUCILayerChange(layerChangeInfo)
    if not const.uciIntegrationEnabled then return end
    if not layerChangeInfo then return end
    local currentLayer = layerChangeInfo.currentLayer
    debugPrint("UCI layer " .. tostring(layerChangeInfo.previousLayer) .. " → "
        .. tostring(currentLayer) .. " (" .. tostring(layerChangeInfo.layerName) .. ") (Source: UCI callback)")
    state.lastUCILayer = currentLayer
    if uciLayerToInput[currentLayer] then
        local targetInput = uciLayerToInput[currentLayer]
        setRoute(targetInput, outputs.Output01, "UCI Layer Change")
    end
end

local function cleanup()
    if componentsTbl.nv32Router then
        cleanupComponentHandlers(componentsTbl.nv32Router, routerHandlerControls,
            function(msg) debugPrint("[NV32 cleanup] " .. msg) end)
    end
    if componentsTbl.roomControls then
        cleanupComponentHandlers(componentsTbl.roomControls, { "ledSystemPower", "ledFireAlarm" },
            function(msg) debugPrint("[Room Controls cleanup] " .. msg) end)
    end
    state.uciController = nil
    debugPrint("Cleanup complete")
end

-------------------[ Events ]-------------------
local function registerEvents()
    local componentMap = {
        devNV32 = setNV32RouterComponent,
        compRoomControls = setRoomControlsComponent,
    }
    for controlName, handler in pairs(componentMap) do
        local control = controls[controlName]
        if control and bind(control, handler) then
            debugPrint("Registered component selector handler: " .. controlName)
        end
    end

    local out1Count = 0
    if isArr(controls.btnNV32Out01) then
        for i, btn in ipairs(controls.btnNV32Out01) do
            if bind(btn, function()
                setRoute(uciInputs[i], outputs.Output01, "NV32 Output 1 Button " .. tostring(i))
            end) then
                out1Count = out1Count + 1
            end
        end
    end
    debugPrint("Registered " .. out1Count .. " Output 1 preset button handler(s)")

    if const.enableOutput2 and controls.btnNV32Out02 and isArr(controls.btnNV32Out02) then
        local out2Count = 0
        for i, btn in ipairs(controls.btnNV32Out02) do
            if bind(btn, function()
                setRoute(uciInputs[i], outputs.Output02, "NV32 Output 2 Button " .. tostring(i))
            end) then
                out2Count = out2Count + 1
            end
        end
        debugPrint("Registered " .. out2Count .. " Output 2 preset button handler(s)")
    end

    setupDirectUCIButtonMonitoring()
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debug=" .. tostring(const.debug)
        .. ", enableOutput2=" .. tostring(const.enableOutput2)
        .. ", uciIntegration=" .. tostring(const.uciIntegrationEnabled))

    discoverAndSetupInitial()
    registerEvents()
    setNV32RouterComponent()
    setRoomControlsComponent()

    if componentsTbl.nv32Router then
        setRoute(uciInputs[1], outputs.Output01, "Initialization default")
        if const.enableOutput2 then
            setRoute(uciInputs[1], outputs.Output02, "Initialization default")
        end
    end

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready — " .. (const.enableOutput2 and "Output 1 + 2" or "Output 1 only"))
end

-------------------[ Config merge & factory ]-------------------
local function mergeConfig(config)
    if not config then return end
    if config.debugging ~= nil then const.debug = config.debugging end
    if config.uciIntegrationEnabled ~= nil then const.uciIntegrationEnabled = config.uciIntegrationEnabled end
    if config.enableOutput2 ~= nil then const.enableOutput2 = config.enableOutput2 end
    if config.roomName ~= nil then const.roomName = config.roomName end
end

local function createNV32RouterController(config)
    mergeConfig(config)
    local ok, err = pcall(function()
        if not validateControls() then error("Control validation failed") end
        normalizeControlArrays()
        init()
    end)
    if ok then
        print("✓ NV32RouterController initialized (" .. const.roomName .. ")")
        return NV32RouterController
    end
    print("✗ ERROR: NV32RouterController init failed: " .. tostring(err))
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
    return nil
end

-------------------[ Public API ]-------------------
NV32RouterController = {
    setUCIController = setUCIController,
    enableUCIIntegration = enableUCIIntegration,
    disableUCIIntegration = disableUCIIntegration,
    onUCILayerChange = onUCILayerChange,
    setRoute = setRoute,
    cleanup = cleanup,
}

-------------------[ Start ]-------------------
local myNV32RouterController = createNV32RouterController()
if myNV32RouterController then
    _G.myNV32RouterController = myNV32RouterController
    _G.createNV32RouterController = createNV32RouterController
    print("Global: myNV32RouterController (API table — use .setUCIController / .setRoute / .cleanup)")
else
    print("WARNING: NV32RouterController failed to initialize")
end
