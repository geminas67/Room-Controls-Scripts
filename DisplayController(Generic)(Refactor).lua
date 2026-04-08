--[[
  Generic DisplayController — Q-SYS control script for generic display plugins (power & input)
  Author: Nikolas Smith, Q-SYS
  Date: 2025-10-14
  Version: 3.0 (Power & Input — flat module)
  Firmware Req: 10.0.0
  Description: Power management and input switching; integrates with SystemAutomationController.
]]--

--[ Configuration ]--
local displayControls = {
    powerOn = "PowerOnTrigger",
    powerOff = "PowerOffTrigger",
    powerStatus = "PowerStatus",
    inputSelectComboBox = "InputSelectComboBox",
    inputStatusLED = "InputStatus",
    inputSelectButtons = "Input",
    inputNames = "InputNames ",
    currentInput = "CurrentInput ",
}

local inputButtonMap = {
    HDMI1 = 1, HDMI2 = 2, DisplayPort = 3, USB_C = 4,
    DVI = 5, VGA = 6, Component = 7, Composite = 8, S_Video = 9, RF = 10,
}

local componentTypes = {
    displays = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_99a0ad880664be90db7f99285f5ff838",
    roomControls = "device_controller_script",
}

local defaultTimerConfig = { warmupTime = 7, cooldownTime = 5 }

--[ Controls ]--
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
    btnDisplayInputAll = Controls.btnDisplayInputAll,
}

--[ Utilities ]--
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
    for idx, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, idx, ctl)
            if not ok then print("Handler error [index " .. idx .. "]: " .. tostring(err)) end
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
    if debugCb and cleaned > 0 then debugCb("Cleaned up " .. cleaned .. " handler(s) from old display component") end
    return cleaned
end

local function setButtonLegend(ctrl, legend)
    setProp(ctrl, "Legend", legend)
end

local function normalizeControlArrays()
    local arrayControls = { "devDisplays", "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle" }
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then
            controls[controlName] = { ctrl }
        end
    end
end

local function validateControls()
    local required = { "txtStatus", "devDisplays" }
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: Generic DisplayController validation failed — missing: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

--[ Config & state ]--
local const = {
    roomName = "[Generic Display]",
    debug = true,
    clearString = "[Clear]",
    maxDisplays = 9,
    defaultInput = "HDMI1",
}

local components = {
    displays = {},
    compRoomControls = nil,
    invalid = {},
}

local state = {
    lastInput = "HDMI1",
    powerState = false,
    isWarming = false,
    isCooling = false,
}

local timerConfig = { warmupTime = defaultTimerConfig.warmupTime, cooldownTime = defaultTimerConfig.cooldownTime }

local timers = {
    warmup = Timer.New(),
    cooldown = Timer.New(),
}

--[ Debug ]--
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

--[ Functions ]--
local function getRoomNameFromComponent()
    if controls.compRoomControls and controls.compRoomControls.String ~= ""
        and controls.compRoomControls.String ~= const.clearString then
        local roomControlsComponent = Component.New(controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local rn = roomControlsComponent["roomName"].String
            if rn and rn ~= "" then return "[" .. rn .. "]" end
        end
    end
    if controls.roomName and controls.roomName.String and controls.roomName.String ~= "" then
        return "[" .. controls.roomName.String .. "]"
    end
    return "[Generic Display]"
end

local function checkStatus()
    for _, invalid in pairs(components.invalid) do
        if invalid == true then
            if controls.txtStatus then
                setProp(controls.txtStatus, "String", "Invalid Components")
                setProp(controls.txtStatus, "Value", 1)
            end
            return
        end
    end
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "OK")
        setProp(controls.txtStatus, "Value", 0)
    end
end

local function setComponentInvalid(componentType)
    components.invalid[componentType] = true
    checkStatus()
end

local function setComponentValid(componentType)
    components.invalid[componentType] = false
    checkStatus()
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        setComponentInvalid(componentType)
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        setComponentValid(componentType)
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        setComponentInvalid(componentType)
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    setProp(ctrl, "Color", "white")
    setComponentValid(componentType)
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value
                return true
            elseif action == "setString" then
                component[control].String = value
                return true
            elseif action == "trigger" then
                component[control]:Trigger()
                return true
            elseif action == "get" then
                return component[control].Boolean
            elseif action == "getString" then
                return component[control].String
            end
        end
        return false
    end)
    if not success then
        debugPrint("Component access error: " .. tostring(result))
        return false
    end
    return result
end

local function getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = inputButtonMap[normalizedInput]
    if not buttonNumber then
        debugPrint("WARNING: No button mapping for input: " .. input)
    end
    return buttonNumber
end

local function updateTimerConfigFromComponent()
    if not components.compRoomControls then
        timerConfig.warmupTime = defaultTimerConfig.warmupTime
        timerConfig.cooldownTime = defaultTimerConfig.cooldownTime
        debugPrint("Timer config: defaults (warmup " .. timerConfig.warmupTime .. "s, cooldown "
            .. timerConfig.cooldownTime .. "s) (Source: no Room Controls)")
        return
    end
    local comp = components.compRoomControls
    local warmupTime = comp.warmupTime and comp.warmupTime.Value or nil
    timerConfig.warmupTime = (warmupTime and warmupTime > 0) and warmupTime or defaultTimerConfig.warmupTime
    local cooldownTime = comp.cooldownTime and comp.cooldownTime.Value or nil
    timerConfig.cooldownTime = (cooldownTime and cooldownTime > 0) and cooldownTime or defaultTimerConfig.cooldownTime
    debugPrint("Timer config: warmup " .. timerConfig.warmupTime .. "s, cooldown " .. timerConfig.cooldownTime
        .. "s (Source: Room Controls)")
end

local function getTimerConfig(isWarmup)
    updateTimerConfigFromComponent()
    return isWarmup and timerConfig.warmupTime or timerConfig.cooldownTime
end

local function getDisplayCount()
    local count = 0
    for _, display in pairs(components.displays) do
        if display then count = count + 1 end
    end
    return count
end

local function displayPowerAll(powerOn)
    debugPrint("Power all displays → " .. (powerOn and "ON" or "OFF") .. " (Source: UCI / automation)")
    for _, display in pairs(components.displays) do
        if display then
            local control = powerOn and displayControls.powerOn or displayControls.powerOff
            safeComponentAccess(display, control, "trigger")
        end
    end
    state.powerState = powerOn
    setProp(controls.ledDisplayPower, "Boolean", powerOn)
end

local function displayPowerSingle(index, powerOn)
    local display = components.displays[index]
    if not display then return end
    local control = powerOn and displayControls.powerOn or displayControls.powerOff
    safeComponentAccess(display, control, "trigger")
    debugPrint("Display " .. index .. " power → " .. (powerOn and "ON" or "OFF") .. " (Source: UCI / automation)")
end

local function displaySetInputAll(input)
    debugPrint("All displays input → " .. input .. " (Source: UCI / automation)")
    for _, display in pairs(components.displays) do
        if display then
            if display[displayControls.inputSelectComboBox] then
                safeComponentAccess(display, displayControls.inputSelectComboBox, "setString", input)
            else
                local buttonNumber = getInputButtonNumber(input)
                if buttonNumber then
                    local buttonName = displayControls.inputSelectButtons .. buttonNumber .. "Trigger"
                    safeComponentAccess(display, buttonName, "trigger")
                end
            end
        end
    end
    state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

local function displaySetInputSingle(index, input)
    local display = components.displays[index]
    if not display then return end
    if display[displayControls.inputSelectComboBox] then
        safeComponentAccess(display, displayControls.inputSelectComboBox, "setString", input)
        debugPrint("Display " .. index .. " input → " .. input .. " (ComboBox) (Source: UCI / automation)")
    else
        local buttonNumber = getInputButtonNumber(input)
        if buttonNumber then
            local buttonName = displayControls.inputSelectButtons .. buttonNumber .. "Trigger"
            safeComponentAccess(display, buttonName, "trigger")
            debugPrint("Display " .. index .. " input → " .. input .. " (buttons) (Source: UCI / automation)")
        end
    end
end

local function getCurrentInput(displayIndex)
    local display = components.displays[displayIndex]
    if not display then return nil end
    if display[displayControls.inputSelectComboBox] then
        return safeComponentAccess(display, displayControls.inputSelectComboBox, "getString")
    end
    for idx = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. idx]
        if currentInputControl then
            local isActive = safeComponentAccess(display, displayControls.currentInput .. idx, "get")
            if isActive then
                local inputNameControl = display[displayControls.inputNames .. idx]
                if inputNameControl then
                    return safeComponentAccess(display, displayControls.inputNames .. idx, "getString")
                end
                return "Input " .. idx
            end
        end
    end
    return nil
end

local displayModule = {
    powerAll = displayPowerAll,
    powerSingle = displayPowerSingle,
    setInputAll = displaySetInputAll,
    setInputSingle = displaySetInputSingle,
    getDisplayCount = getDisplayCount,
    getCurrentInput = getCurrentInput,
}

local function enableDisablePowerControls(enabled)
    local allPowerControls = {
        "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
        "btnDisplayPowerAll", "btnDisplayInputAll",
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

local function setDisplayPowerFB(powerOn)
    setProp(controls.ledDisplayPower, "Boolean", powerOn)
    setProp(controls.btnDisplayPowerAll, "Boolean", powerOn)
end

local function updatePowerFeedbackFromDisplays()
    local allPoweredOn = true
    local poweredOnCount, totalDisplays = 0, 0
    for idx, display in pairs(components.displays) do
        if display then
            totalDisplays = totalDisplays + 1
            local powerStatus = safeComponentAccess(display, displayControls.powerStatus, "get")
            if powerStatus then
                poweredOnCount = poweredOnCount + 1
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[idx] then
                    setProp(controls.btnDisplayPowerSingle[idx], "Boolean", true)
                end
            else
                allPoweredOn = false
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[idx] then
                    setProp(controls.btnDisplayPowerSingle[idx], "Boolean", false)
                end
            end
        end
    end
    if totalDisplays > 0 then
        setDisplayPowerFB(allPoweredOn)
        state.powerState = allPoweredOn
        debugPrint("Power feedback: " .. poweredOnCount .. "/" .. totalDisplays .. " on (Source: display status)")
    end
end

local function enableDisablePowerControlIndex(index, enabled)
    local individualPowerControls = { "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle" }
    for _, controlName in ipairs(individualPowerControls) do
        local ctrl = controls[controlName]
        if ctrl and ctrl[index] then
            setProp(ctrl[index], "IsDisabled", not enabled)
        end
    end
end

local function setOppositePowerButtonLegend(index, poweringOn)
    local targetControl = poweringOn and controls.btnDisplayPowerOff or controls.btnDisplayPowerOn
    if targetControl and targetControl[index] then
        setButtonLegend(targetControl[index], "Please\nwait")
    end
end

local function resetPowerButtonLegends(index)
    if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
        setButtonLegend(controls.btnDisplayPowerOn[index], "On")
    end
    if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
        setButtonLegend(controls.btnDisplayPowerOff[index], "Off")
    end
end

local function powerOnDisplay(index)
    debugPrint("Display " .. index .. " → warmup (Source: UCI)")
    displayPowerSingle(index, true)
    enableDisablePowerControlIndex(index, false)
    setOppositePowerButtonLegend(index, true)
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    timers.warmup:Start(getTimerConfig(true))
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", true)
    end
end

local function powerOffDisplay(index)
    debugPrint("Display " .. index .. " → cooldown (Source: UCI)")
    displayPowerSingle(index, false)
    enableDisablePowerControlIndex(index, false)
    setOppositePowerButtonLegend(index, false)
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    timers.cooldown:Start(getTimerConfig(false))
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", false)
    end
end

local function powerOnAll()
    debugPrint("All displays → warmup (Source: UCI)")
    displayPowerAll(true)
    enableDisablePowerControls(false)
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    timers.warmup:Start(getTimerConfig(true))
    setDisplayPowerFB(true)
end

local function powerOffAll()
    debugPrint("All displays → cooldown (Source: UCI)")
    displayPowerAll(false)
    enableDisablePowerControls(false)
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    timers.cooldown:Start(getTimerConfig(false))
    setDisplayPowerFB(false)
end

local powerModule = {
    enableDisablePowerControls = enableDisablePowerControls,
    setDisplayPowerFB = setDisplayPowerFB,
    updatePowerFeedbackFromDisplays = updatePowerFeedbackFromDisplays,
    powerOnDisplay = powerOnDisplay,
    powerOffDisplay = powerOffDisplay,
    powerOnAll = powerOnAll,
    powerOffAll = powerOffAll,
    enableDisablePowerControlIndex = enableDisablePowerControlIndex,
    setOppositePowerButtonLegend = setOppositePowerButtonLegend,
    resetPowerButtonLegends = resetPowerButtonLegends,
}

local function collectDisplayHandlerControlNames(display)
    local names = {}
    if display[displayControls.powerStatus] then table.insert(names, displayControls.powerStatus) end
    if display[displayControls.inputSelectComboBox] then table.insert(names, displayControls.inputSelectComboBox) end
    if display[displayControls.inputStatusLED] then table.insert(names, displayControls.inputStatusLED) end
    for idx = 1, 10 do
        local c = display[displayControls.currentInput .. idx]
        if c then table.insert(names, displayControls.currentInput .. idx) end
    end
    return names
end

local function setupDisplayEvents(index)
    local display = components.displays[index]
    if not display then return end
    local selectorName = Controls.devDisplays and Controls.devDisplays[index]
        and Controls.devDisplays[index].String or "?"
    if display[displayControls.powerStatus] then
        display[displayControls.powerStatus].EventHandler = function()
            local powerState = safeComponentAccess(display, displayControls.powerStatus, "get")
            debugPrint("Display " .. selectorName .. " power status → " .. tostring(powerState)
                .. " (Source: device)")
            updatePowerFeedbackFromDisplays()
        end
    end
    if display[displayControls.inputSelectComboBox] then
        display[displayControls.inputSelectComboBox].EventHandler = function()
            local currentInput = safeComponentAccess(display, displayControls.inputSelectComboBox, "getString")
            debugPrint("Display " .. selectorName .. " input → " .. tostring(currentInput) .. " (Source: device)")
        end
    end
    if display[displayControls.inputStatusLED] then
        display[displayControls.inputStatusLED].EventHandler = function()
            local inputActive = safeComponentAccess(display, displayControls.inputStatusLED, "get")
            debugPrint("Display " .. selectorName .. " input active → " .. tostring(inputActive) .. " (Source: device)")
        end
    end
    for idx = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. idx]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = safeComponentAccess(display, displayControls.currentInput .. idx, "get")
                debugPrint("Display " .. selectorName .. " input line " .. idx .. " → "
                    .. tostring(inputActive) .. " (Source: device)")
            end
        end
    end
end

local function setDisplayComponent(index)
    if not Controls.devDisplays or not Controls.devDisplays[index] then
        debugPrint("Display selector " .. index .. " not found")
        return
    end
    local oldDisplay = components.displays[index]
    if oldDisplay then
        cleanupComponentHandlers(oldDisplay, collectDisplayHandlerControlNames(oldDisplay), function(msg) debugPrint(msg) end)
    end
    local componentType = "Display [" .. index .. "]"
    components.displays[index] = setComponent(Controls.devDisplays[index], componentType)
    if components.displays[index] then
        setupDisplayEvents(index)
        updatePowerFeedbackFromDisplays()
    end
end

local function setupDisplayComponents()
    if not Controls.devDisplays then
        debugPrint("No devDisplays control")
        return
    end
    debugPrint("Binding " .. #Controls.devDisplays .. " display selector(s)")
    for idx, displaySelector in ipairs(Controls.devDisplays) do
        if displaySelector then setDisplayComponent(idx) end
    end
end

local function getComponentNames()
    debugPrint("Discovering components...")
    local displayNames = {}
    local roomControlsNames = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.displays then
            table.insert(displayNames, comp.Name)
            debugPrint("  Found display: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomControlsNames, comp.Name)
            debugPrint("  Found room controls: " .. comp.Name)
        end
    end
    table.sort(displayNames)
    table.sort(roomControlsNames)
    table.insert(displayNames, const.clearString)
    table.insert(roomControlsNames, const.clearString)
    if Controls.devDisplays then
        for idx in ipairs(Controls.devDisplays) do
            Controls.devDisplays[idx].Choices = displayNames
        end
        debugPrint("Discovery complete — " .. (#displayNames - 1) .. " display(s), "
            .. (#roomControlsNames - 1) .. " room control(s)")
    end
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = roomControlsNames
    end
end

local function setRoomControlsComponent()
    components.compRoomControls = setComponent(controls.compRoomControls, "Room Controls")
    if components.compRoomControls then
        updateTimerConfigFromComponent()
    end
end

local function updateRoomNameFromComponent()
    if not components.compRoomControls then return end
    local roomNameControl = components.compRoomControls["roomName"]
    if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
        local newRoomName = "[" .. roomNameControl.String .. "]"
        if newRoomName ~= const.roomName then
            const.roomName = newRoomName
            debugPrint("Room name → " .. newRoomName .. " (Source: Room Controls)")
        end
    end
    updateTimerConfigFromComponent()
end

local function registerTimerHandlers()
    timers.warmup.EventHandler = function()
        debugPrint("Warmup ended — controls re-enabled (Source: timer)")
        enableDisablePowerControls(true)
        for idx = 1, const.maxDisplays do
            enableDisablePowerControlIndex(idx, true)
            resetPowerButtonLegends(idx)
        end
        state.isWarming = false
        setProp(controls.ledDisplayWarming, "Boolean", false)
        timers.warmup:Stop()
    end
    timers.cooldown.EventHandler = function()
        debugPrint("Cooldown ended — controls re-enabled (Source: timer)")
        enableDisablePowerControls(true)
        for idx = 1, const.maxDisplays do
            enableDisablePowerControlIndex(idx, true)
            resetPowerButtonLegends(idx)
        end
        state.isCooling = false
        setProp(controls.ledDisplayCooling, "Boolean", false)
        timers.cooldown:Stop()
    end
end

local function registerEventHandlers()
    local singleCount = 0
    if bind(controls.compRoomControls, function()
        setRoomControlsComponent()
        updateRoomNameFromComponent()
    end) then singleCount = singleCount + 1 end
    if bind(controls.btnDisplayPowerAll, function(ctl)
        if ctl.Boolean then powerOnAll() else powerOffAll() end
    end) then singleCount = singleCount + 1 end
    if bind(controls.btnDisplayInputAll, function()
        displaySetInputAll(const.defaultInput)
    end) then singleCount = singleCount + 1 end
    debugPrint("Registered " .. singleCount .. " single-control handler(s)")

    local arrayCount = 0
    arrayCount = arrayCount + bindArray(controls.btnDisplayPowerOn, function(index) powerOnDisplay(index) end)
    arrayCount = arrayCount + bindArray(controls.btnDisplayPowerOff, function(index) powerOffDisplay(index) end)
    arrayCount = arrayCount + bindArray(controls.btnDisplayPowerSingle, function(index, ctl)
        if ctl.Boolean then powerOnDisplay(index) else powerOffDisplay(index) end
    end)
    arrayCount = arrayCount + bindArray(controls.devDisplays, function(index) setDisplayComponent(index) end)
    debugPrint("Registered " .. arrayCount .. " array control binding(s)")
end

local function registerEvents()
    registerEventHandlers()
    registerTimerHandlers()
end

local function cleanup()
    for _, display in pairs(components.displays) do
        if display then
            cleanupComponentHandlers(display, collectDisplayHandlerControlNames(display), nil)
        end
    end
    components.displays = {}
    components.compRoomControls = nil
    components.invalid = {}
    debugPrint("Cleanup complete (Source: cleanup)")
end

local function init()
    const.roomName = getRoomNameFromComponent()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debug=" .. tostring(const.debug))

    getComponentNames()
    setRoomControlsComponent()
    setupDisplayComponents()
    registerEvents()
    updateRoomNameFromComponent()
    updatePowerFeedbackFromDisplays()
    updateTimerConfigFromComponent()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready — " .. getDisplayCount() .. " display(s) connected")
end

--[ Start ]--
const.roomName = getRoomNameFromComponent()

local ok, err = pcall(function()
    print("Initializing Generic DisplayController for " .. const.roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ Generic DisplayController initialized — " .. const.roomName)
    GenericDisplayController = {
        displayModule = displayModule,
        powerModule = powerModule,
        components = components,
        state = state,
        cleanup = cleanup,
        const = const,
    }
    myGenericDisplayController = GenericDisplayController
    GenericDisplayControllerInstance = GenericDisplayController
    print("Display count: " .. tostring(getDisplayCount()))
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
    GenericDisplayController = nil
    myGenericDisplayController = nil
    GenericDisplayControllerInstance = nil
end
