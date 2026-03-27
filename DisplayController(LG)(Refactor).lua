--[[
  LG DisplayController (Refactored) - Q-SYS Control Script for LG Displays
  Author: Nikolas Smith, Q-SYS
  Date: 2026-03-27
  Version: 1.0 (Power & Input Only)
  Firmware Req: 10.2.0
  Description: Controls LG Display components with power management and
  input switching. Integrates with SystemAutomationController.
]]--

-------------------[ Configuration ]-------------------
local displayControls = {
    powerOn = "PowerOn",
    powerOff = "PowerOff",
    powerStatus = "PowerStatus",
    inputStatusLED = "InputStatus",
    inputSelectButtons = "InputSelectButtons ",
    inputNames = "InputNames ",
    currentInput = "CurrentInput "
}

local componentTypes = {
    displays = "%PLUGIN%_e9ef4a50-ba74-4653-a22e-a58c02839313_%FP%_c7165c3b15ead5f69821d69583f73c8b",
    roomControls = "device_controller_script"
}

local inputButtonMap = {
    HDMI1 = 1, HDMI2 = 2, DisplayPort = 3, USB_C = 4,
    DVI = 5, VGA = 6, Component = 7, Composite = 8, S_Video = 9, RF = 10
}

-------------------[ Controls ]-------------------
local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
    compRoomControls = Controls.compRoomControls,
    roomName = Controls.roomName,
    ledDisplayPower = Controls.ledDisplayPower,
    ledDisplayInput = Controls.ledDisplayInput,
    ledDisplayWarming = Controls.ledDisplayWarming,
    ledDisplayCooling = Controls.ledDisplayCooling,
    btnDisplayPowerAll = Controls.btnDisplayPowerAll,
    btnDisplayPowerOn = Controls.btnDisplayPowerOn,
    btnDisplayPowerOff = Controls.btnDisplayPowerOff,
    btnDisplayPowerSingle = Controls.btnDisplayPowerSingle,
    btnDisplayInputAll = Controls.btnDisplayInputAll
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
        end) then count = count + 1 end
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

local function setButtonLegend(ctrl, legend)
    setProp(ctrl, "Legend", legend)
end

-------------------[ Config ]-------------------
local const = {
    roomName = "[LG Display]",
    debug = true,
    clearString = "[Clear]",
    maxDisplays = 9,
    defaultInput = "HDMI1",
    inputChoices = {"HDMI1", "HDMI2", "DisplayPort", "USB-C"}
}

-------------------[ State ]-------------------
local components = {
    displays = {},
    compRoomControls = nil,
    invalid = {}
}

local state = {
    lastInput = "HDMI1",
    powerState = false,
    isWarming = false,
    isCooling = false
}

local timerConfig = { warmupTime = 7, cooldownTime = 5 }
local timers = { warmup = Timer.New(), cooldown = Timer.New() }

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local required = { "txtStatus", "devDisplays" }
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: LGDisplayController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    return true
end

local function normalizeControlArrays()
    local arrayControls = { "devDisplays", "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle" }
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then controls[controlName] = { ctrl } end
    end
end

local function checkStatus()
    for _, invalid in pairs(components.invalid) do
        if invalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if not component or not component[control] then return false end
        if action == "set" then component[control].Boolean = value; return true end
        if action == "setString" then component[control].String = value; return true end
        if action == "trigger" then component[control]:Trigger(); return true end
        if action == "get" then return component[control].Boolean end
        return false
    end)
    if not success then debugPrint("Component access error: " .. tostring(result)) end
    return success and result
end

local function getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = inputButtonMap[normalizedInput]
    if not buttonNumber then debugPrint("WARNING: No button mapping for input: " .. input) end
    return buttonNumber
end

local function updateTimerConfig()
    if not components.compRoomControls then return end
    local comp = components.compRoomControls
    if comp.warmupTime and comp.warmupTime.Value and comp.warmupTime.Value > 0 then
        timerConfig.warmupTime = comp.warmupTime.Value
    end
    if comp.cooldownTime and comp.cooldownTime.Value and comp.cooldownTime.Value > 0 then
        timerConfig.cooldownTime = comp.cooldownTime.Value
    end
end

local function getTimerConfig(isWarmup)
    return isWarmup and timerConfig.warmupTime or timerConfig.cooldownTime
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        components.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    setProp(ctrl, "Color", "white")
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function powerAll(powerState)
    debugPrint("Powering all displays: " .. tostring(powerState) .. " (Source: Power All)")
    local control = powerState and displayControls.powerOn or displayControls.powerOff
    for displayIdx, display in pairs(components.displays) do
        if display then safeComponentAccess(display, control, "trigger") end
    end
    state.powerState = powerState
    setProp(controls.ledDisplayPower, "Boolean", powerState)
end

local function powerSingle(index, powerState)
    local display = components.displays[index]
    if not display then return end
    local control = powerState and displayControls.powerOn or displayControls.powerOff
    safeComponentAccess(display, control, "trigger")
    debugPrint("Display " .. index .. " power: " .. tostring(powerState) .. " (Source: Power Single)")
end

local function setInputOnDisplay(display, input)
    local buttonNumber = getInputButtonNumber(input)
    if not buttonNumber then return end
    local buttonName = displayControls.inputSelectButtons .. buttonNumber
    safeComponentAccess(display, buttonName, "trigger")
end

local function setInputAll(input)
    debugPrint("Setting all displays to input: " .. input .. " (Source: Input All)")
    for i, display in pairs(components.displays) do
        if display then setInputOnDisplay(display, input) end
    end
    state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

local function setInputSingle(index, input)
    local display = components.displays[index]
    if not display then return end
    setInputOnDisplay(display, input)
    debugPrint("Display " .. index .. " input: " .. input .. " (Source: Input Single)")
end

local function getDisplayCount()
    local count = 0
    for _ in pairs(components.displays) do count = count + 1 end
    return count
end

local function setEnabledDisabled(enabled)
    local allPowerControls = {
        "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
        "btnDisplayPowerAll", "btnDisplayInputAll"
    }
    for _, controlName in ipairs(allPowerControls) do
        local ctrl = controls[controlName]
        if ctrl then
            if isArr(ctrl) then
                for _, btn in ipairs(ctrl) do setProp(btn, "IsDisabled", not enabled) end
            else
                setProp(ctrl, "IsDisabled", not enabled)
            end
        end
    end
end

local function setDisplayPowerFB(powerState)
    setProp(controls.ledDisplayPower, "Boolean", powerState)
    setProp(controls.btnDisplayPowerAll, "Boolean", powerState)
end

local function updatePowerFeedbackFromDisplays()
    local allPoweredOn, poweredOnCount, totalDisplays = true, 0, 0
    for displayIdx, display in pairs(components.displays) do
        if display then
            totalDisplays = totalDisplays + 1
            local powerStatus = safeComponentAccess(display, displayControls.powerStatus, "get")
            if powerStatus then
                poweredOnCount = poweredOnCount + 1
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[displayIdx] then
                    setProp(controls.btnDisplayPowerSingle[displayIdx], "Boolean", true)
                end
            else
                allPoweredOn = false
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[displayIdx] then
                    setProp(controls.btnDisplayPowerSingle[displayIdx], "Boolean", false)
                end
            end
        end
    end
    if totalDisplays > 0 then
        setDisplayPowerFB(allPoweredOn)
        state.powerState = allPoweredOn
        debugPrint("Power feedback updated - Powered: " .. poweredOnCount .. "/" .. totalDisplays)
    end
end

local function enableDisablePowerControlIndex(index, enabled)
    local individualPowerControls = { "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle" }
    for _, controlName in ipairs(individualPowerControls) do
        local ctrl = controls[controlName]
        if ctrl and ctrl[index] then setProp(ctrl[index], "IsDisabled", not enabled) end
    end
end

local function setPowerButtonLegends(index, onLegend, offLegend)
    if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
        setButtonLegend(controls.btnDisplayPowerOn[index], onLegend or "On")
    end
    if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
        setButtonLegend(controls.btnDisplayPowerOff[index], offLegend or "Off")
    end
end

local function powerOnDisplay(index)
    debugPrint("Powering on display " .. index .. " (Source: Power On Button)")
    powerSingle(index, true)
    enableDisablePowerControlIndex(index, false)
    setPowerButtonLegends(index, "On", "Please\nwait")
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    timers.warmup:Start(getTimerConfig(true))
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", true)
    end
end

local function powerOffDisplay(index)
    debugPrint("Powering off display " .. index .. " (Source: Power Off Button)")
    powerSingle(index, false)
    enableDisablePowerControlIndex(index, false)
    setPowerButtonLegends(index, "Please\nwait", "Off")
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    timers.cooldown:Start(getTimerConfig(false))
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", false)
    end
end

local function powerOnAll()
    debugPrint("Powering on all displays (Source: Power All Button)")
    powerAll(true)
    setEnabledDisabled(false)
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    timers.warmup:Start(getTimerConfig(true))
    setDisplayPowerFB(true)
end

local function powerOffAll()
    debugPrint("Powering off all displays (Source: Power All Button)")
    powerAll(false)
    setEnabledDisabled(false)
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    timers.cooldown:Start(getTimerConfig(false))
    setDisplayPowerFB(false)
end

local displayEventControlNames = {}
for inputIdx = 1, 10 do
    table.insert(displayEventControlNames, displayControls.currentInput .. inputIdx)
end
table.insert(displayEventControlNames, displayControls.powerStatus)
table.insert(displayEventControlNames, displayControls.inputStatusLED)

local function setupDisplayEvents(index)
    local display = components.displays[index]
    if not display then return end

    if display[displayControls.powerStatus] then
        display[displayControls.powerStatus].EventHandler = function()
            local powerState = safeComponentAccess(display, displayControls.powerStatus, "get")
            local componentName = controls.devDisplays and controls.devDisplays[index] and controls.devDisplays[index].String or "Unknown"
            debugPrint("Display " .. componentName .. " power status: " .. tostring(powerState) .. " (Source: Component Event)")
            updatePowerFeedbackFromDisplays()
        end
    end


    if display[displayControls.inputStatusLED] then
        display[displayControls.inputStatusLED].EventHandler = function()
            local inputActive = safeComponentAccess(display, displayControls.inputStatusLED, "get")
            local componentName = controls.devDisplays and controls.devDisplays[index] and controls.devDisplays[index].String or "Unknown"
            debugPrint("Display " .. componentName .. " input active: " .. tostring(inputActive) .. " (Source: Component Event)")
        end
    end

    for inputIdx = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. inputIdx]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = safeComponentAccess(display, displayControls.currentInput .. inputIdx, "get")
                local componentName = controls.devDisplays and controls.devDisplays[index] and controls.devDisplays[index].String or "Unknown"
                debugPrint("Display " .. componentName .. " input " .. inputIdx .. " active: " .. tostring(inputActive) .. " (Source: Component Event)")
            end
        end
    end
end

local function setDisplayComponent(index)
    if not controls.devDisplays or not controls.devDisplays[index] then return end

    local componentType = "Display [" .. index .. "]"
    local oldComp = components.displays[index]
    if oldComp then
        cleanupComponentHandlers(oldComp, displayEventControlNames, function(msg) debugPrint("[Display] " .. msg) end)
    end

    components.displays[index] = setComponent(controls.devDisplays[index], componentType)

    if components.displays[index] then
        setupDisplayEvents(index)
        updatePowerFeedbackFromDisplays()
    end
end

local function setRoomControlsComponent()
    components.compRoomControls = setComponent(controls.compRoomControls, "Room Controls")
    if components.compRoomControls then
        updateTimerConfig()
        debugPrint("Timer config - Warmup: " .. getTimerConfig(true) .. "s, Cooldown: " .. getTimerConfig(false) .. "s")
    end
end

local function discoverComponents()
    debugPrint("Discovering components...")
    local displayNames = {}
    local roomControlsNames = {}

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.displays then
            table.insert(displayNames, comp.Name)
            debugPrint("  Found display: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomControlsNames, comp.Name)
        end
    end

    table.sort(displayNames)
    table.sort(roomControlsNames)
    table.insert(displayNames, const.clearString)
    table.insert(roomControlsNames, const.clearString)

    if controls.devDisplays then
        for displayIdx = 1, #controls.devDisplays do
            local ctrl = controls.devDisplays[displayIdx]
            ctrl.Choices = displayNames
            if #displayNames == 2 and (not ctrl.String or ctrl.String == "") then
                setProp(ctrl, "String", displayNames[1])
                debugPrint("Auto-selected display: " .. displayNames[1])
            end
        end
        debugPrint("Discovery complete - " .. (#displayNames - 1) .. " displays found")
    end

    if controls.compRoomControls then
        controls.compRoomControls.Choices = roomControlsNames
    end
end

local function updateRoomNameFromComponent()
    if not components.compRoomControls then return end
    local roomNameControl = components.compRoomControls["roomName"]
    if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
        local newRoomName = "[" .. roomNameControl.String .. "]"
        if newRoomName ~= const.roomName then
            const.roomName = newRoomName
            debugPrint("Room name updated to: " .. newRoomName)
        end
    end
end

-------------------[ Events ]-------------------
local function registerEvents()
    bind(controls.compRoomControls, function() setRoomControlsComponent() end)
    bind(controls.btnDisplayPowerAll, function(ctl) if ctl.Boolean then powerOnAll() else powerOffAll() end end)
    bind(controls.btnDisplayInputAll, function() setInputAll(const.defaultInput) end)

    local powerOnCount = bindArray(controls.btnDisplayPowerOn, function(index) powerOnDisplay(index) end)
    local powerOffCount = bindArray(controls.btnDisplayPowerOff, function(index) powerOffDisplay(index) end)
    local powerSingleCount = bindArray(controls.btnDisplayPowerSingle, function(index, ctl)
        if ctl.Boolean then powerOnDisplay(index) else powerOffDisplay(index) end
    end)
    local devDisplaysCount = bindArray(controls.devDisplays, function(index) setDisplayComponent(index) end)

    debugPrint("Registered: compRoomControls, btnDisplayPowerAll, btnDisplayInputAll")
    debugPrint("Registered " .. powerOnCount .. " power-on, " .. powerOffCount .. " power-off, " .. powerSingleCount .. " power-single handlers")
    debugPrint("Registered " .. devDisplaysCount .. " display handlers")

    timers.warmup.EventHandler = function()
        debugPrint("Warmup period ended (Source: Timer)")
        setEnabledDisabled(true)
        for displayIdx = 1, const.maxDisplays do
            enableDisablePowerControlIndex(displayIdx, true)
            setPowerButtonLegends(displayIdx, "On", "Off")
        end
        state.isWarming = false
        setProp(controls.ledDisplayWarming, "Boolean", false)
        timers.warmup:Stop()
    end

    timers.cooldown.EventHandler = function()
        debugPrint("Cooldown period ended (Source: Timer)")
        setEnabledDisabled(true)
        for displayIdx = 1, const.maxDisplays do
            enableDisablePowerControlIndex(displayIdx, true)
            setPowerButtonLegends(displayIdx, "On", "Off")
        end
        state.isCooling = false
        setProp(controls.ledDisplayCooling, "Boolean", false)
        timers.cooldown:Stop()
    end
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debug=" .. tostring(const.debug))

    discoverComponents()
    setRoomControlsComponent()

    if controls.devDisplays then
        for displayIdx = 1, #controls.devDisplays do
            setDisplayComponent(displayIdx)
        end
    end

    registerEvents()
    updateRoomNameFromComponent()
    updatePowerFeedbackFromDisplays()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation - " .. getDisplayCount() .. " displays")
end

-------------------[ Public API ]-------------------
LGDisplayController = {
    powerOnAll = powerOnAll,
    powerOffAll = powerOffAll,
    setInputAll = setInputAll,
    setInputSingle = setInputSingle,
    getDisplayCount = getDisplayCount,
    updatePowerFeedbackFromDisplays = updatePowerFeedbackFromDisplays
}

-- Backward compatibility for scripts expecting instance
LGDisplayControllerInstance = LGDisplayController

-------------------[ Start ]-------------------
local function getRoomNameFromComponent()
    if controls.compRoomControls and controls.compRoomControls.String ~= "" and controls.compRoomControls.String ~= const.clearString then
        local roomControlsComponent = Component.New(controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then return "[" .. roomName .. "]" end
        end
    end
    if controls.roomName and controls.roomName.String and controls.roomName.String ~= "" then
        return "[" .. controls.roomName.String .. "]"
    end
    return "[LG Display]"
end

const.roomName = getRoomNameFromComponent()

local ok, err = pcall(function()
    print("Initializing LG DisplayController for " .. const.roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ LG DisplayController initialized for " .. const.roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end

