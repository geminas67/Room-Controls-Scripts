--[[
  Generic DisplayController (Sharp) - Q-SYS Control Script
  Controls Sharp/Generic displays with power management and input switching
  Integrates with SystemAutomationController
]]--

-------------------[ Configuration ]-------------------
local displayControls = {
    powerOn = "PowerOnTrigger",
    powerOff = "PowerOffTrigger",
    powerStatus = "PowerStatus",
    inputSelectComboBox = "InputSelectComboBox",
    inputStatusLED = "InputStatus",
    inputSelectButtons = "Input",
    inputNames = "InputNames",
    currentInput = "CurrentInput",
    displayVolume0 = "Custom1Trigger",
}

local inputButtonMap = {
    HDMI1 = 1, HDMI2 = 2, DisplayPort = 3, USB_C = 4,
    DVI = 5, VGA = 6, Component = 7, Composite = 8, S_Video = 9, RF = 10
}

local componentTypes = {
    displays = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920",
    roomControls = "device_controller_script",
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
    btnDisplayPowerToggle = Controls.btnDisplayPowerToggle,
    btnDisplayInputAll = Controls.btnDisplayInputAll,
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

local function normalizeControlArrays()
    for _, name in ipairs({"devDisplays", "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerToggle"}) do
        local ctrl = controls[name]
        if ctrl and not isArr(ctrl) then controls[name] = { ctrl } end
    end
end

local function validateControls()
    for _, name in ipairs({"txtStatus", "devDisplays"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

-------------------[ Config ]-------------------
local const = {
    clearString = "[Clear]",
    maxDisplays = 9,
    defaultInput = "HDMI1",
    warmupTime = 7,
    cooldownTime = 5,
    debug = true,
}

-------------------[ State ]-------------------
local components = { displays = {}, compRoomControls = nil, invalid = {} }
local state = { lastInput = "HDMI1", powerState = false, isWarming = false, isCooling = false }
local timerConfig = { warmupTime = const.warmupTime, cooldownTime = const.cooldownTime }
local timers = { warmup = Timer.New(), cooldown = Timer.New(), volumeMute = {} }
for idx = 1, const.maxDisplays do
    timers.volumeMute[idx] = Timer.New()
end

-------------------[ Debug ]-------------------
local function getRoomName()
    if controls.compRoomControls and controls.compRoomControls.String ~= "" and controls.compRoomControls.String ~= const.clearString then
        local comp = Component.New(controls.compRoomControls.String)
        if comp and comp["roomName"] and comp["roomName"].String ~= "" then
            return "[" .. comp["roomName"].String .. "]"
        end
    end
    if controls.roomName and controls.roomName.String ~= "" then
        return "[" .. controls.roomName.String .. "]"
    end
    return "[Generic Display]"
end

local roomName = getRoomName()

local function debugPrint(str)
    if const.debug then print("[" .. roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    return inputButtonMap[normalizedInput]
end

local function safeAccess(component, control, action, value)
    local success, result = pcall(function()
        if not component or not component[control] then return false end
        if action == "trigger" then component[control]:Trigger(); return true end
        if action == "get" then return component[control].Boolean end
        if action == "getString" then return component[control].String end
        if action == "set" then component[control].Boolean = value; return true end
        if action == "setString" then component[control].String = value; return true end
    end)
    return success and result or false
end

local function getDisplayCount()
    local count = 0
    for _ in pairs(components.displays) do count = count + 1 end
    return count
end

local function checkStatus()
    for _, invalid in pairs(components.invalid) do
        if invalid then
            debugPrint("Invalid components found")
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    debugPrint("Components are valid")
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then ctrl.String = "" end
        ctrl.Color = "white"
        components.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    ctrl.Color = "white"
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function updateTimerConfig()
    if not components.compRoomControls then
        debugPrint("No room controls component found - Using default timing values")
        return
    end
    local comp = components.compRoomControls
    local warmup = comp.warmupTime and comp.warmupTime.Value
    local cooldown = comp.cooldownTime and comp.cooldownTime.Value
    if warmup and warmup > 0 then timerConfig.warmupTime = warmup end
    if cooldown and cooldown > 0 then timerConfig.cooldownTime = cooldown end
    debugPrint("Timer config - Warmup: " .. timerConfig.warmupTime .. "s, Cooldown: " .. timerConfig.cooldownTime .. "s")
end

local function powerAll(powerState)
    debugPrint("Powering all displays: " .. tostring(powerState) .. " (Source: Power All)")
    local ctrl = powerState and displayControls.powerOn or displayControls.powerOff
    for idx, display in pairs(components.displays) do
        if display then safeAccess(display, ctrl, "trigger") end
    end
    state.powerState = powerState
    setProp(controls.ledDisplayPower, "Boolean", powerState)
end

local function powerSingle(index, powerState)
    debugPrint("Powering display " .. index .. " to: " .. tostring(powerState) .. " (Source: Single Display)")
    local display = components.displays[index]
    local ctrl = powerState and displayControls.powerOn or displayControls.powerOff
    if display then safeAccess(display, ctrl, "trigger") end
end

local function setInputAll(input)
    debugPrint("Setting all displays to input: " .. input .. " (Source: Input All)")
    for idx, display in pairs(components.displays) do
        if display then
            if display[displayControls.inputSelectComboBox] then
                safeAccess(display, displayControls.inputSelectComboBox, "setString", input)
            else
                local buttonNumber = getInputButtonNumber(input)
                if buttonNumber then
                    local buttonName = displayControls.inputSelectButtons .. buttonNumber .. "Trigger"
                    safeAccess(display, buttonName, "trigger")
                end
            end
        end
    end
    state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

local function enablePowerControls(enabled)
    for _, name in ipairs({"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerToggle", "btnDisplayPowerAll", "btnDisplayInputAll"}) do
        local ctrl = controls[name]
        if isArr(ctrl) then
            for _, btn in ipairs(ctrl) do setProp(btn, "IsDisabled", not enabled) end
        else
            setProp(ctrl, "IsDisabled", not enabled)
        end
    end
end

local function enablePowerControlIndex(index, enabled)
    for _, name in ipairs({"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerToggle"}) do
        local ctrl = controls[name]
        if ctrl and ctrl[index] then setProp(ctrl[index], "IsDisabled", not enabled) end
    end
end

local function updatePowerFeedback()
    local allOn, count = true, 0
    for idx, display in pairs(components.displays) do
        if display then
            count = count + 1
            local powerStatus = safeAccess(display, displayControls.powerStatus, "get")
            if controls.btnDisplayPowerToggle and controls.btnDisplayPowerToggle[idx] then
                setProp(controls.btnDisplayPowerToggle[idx], "Boolean", powerStatus)
            end
            if not powerStatus then allOn = false end
        end
    end
    if count > 0 then
        setProp(controls.ledDisplayPower, "Boolean", allOn)
        setProp(controls.btnDisplayPowerAll, "Boolean", allOn)
        state.powerState = allOn
        debugPrint("Power feedback updated - Powered: " .. count .. "/" .. getDisplayCount())
    end
end

local function setOppositePowerButtonLegend(index, poweringOn)
    local targetControl = poweringOn and controls.btnDisplayPowerOff or controls.btnDisplayPowerOn
    if targetControl and targetControl[index] then
        setProp(targetControl[index], "Legend", "Please\nwait")
    end
end

local function resetButtonLegends(index)
    debugPrint("Resetting button legends for [ Display " .. index .. "]")
    if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
        setProp(controls.btnDisplayPowerOn[index], "Legend", "On")
    end
    if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
        setProp(controls.btnDisplayPowerOff[index], "Legend", "Off")
    end
end

local function powerOnDisplay(index)
    debugPrint("Powering on display " .. index .. " (Source: Power On Button)")
    powerSingle(index, true)
    enablePowerControlIndex(index, false)
    setOppositePowerButtonLegend(index, true)
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    timers.warmup:Start(timerConfig.warmupTime)
    if timers.volumeMute and timers.volumeMute[index] then
        timers.volumeMute[index]:Start(5)
    end
end

local function powerOffDisplay(index)
    debugPrint("Powering off display " .. index .. " (Source: Power Off Button)")
    powerSingle(index, false)
    enablePowerControlIndex(index, false)
    setOppositePowerButtonLegend(index, false)
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    timers.cooldown:Start(timerConfig.cooldownTime)
end

local function powerOnAll()
    debugPrint("Powering on all displays (Source: Power All Button)")
    powerAll(true)
    enablePowerControls(false)
    state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    setProp(controls.ledDisplayPower, "Boolean", true)
    setProp(controls.btnDisplayPowerAll, "Boolean", true)
    timers.warmup:Start(timerConfig.warmupTime)
end

local function powerOffAll()
    debugPrint("Powering off all displays (Source: Power All Button)")
    powerAll(false)
    enablePowerControls(false)
    state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    setProp(controls.ledDisplayPower, "Boolean", false)
    setProp(controls.btnDisplayPowerAll, "Boolean", false)
    timers.cooldown:Start(timerConfig.cooldownTime)
end

local function setupDisplayEvents(index)
    local display = components.displays[index]
    if not display then return end
    if display[displayControls.powerStatus] then
        display[displayControls.powerStatus].EventHandler = function()
            updatePowerFeedback()
        end
        debugPrint("Registered: power status handler for display " .. index)
    end
end

local function setDisplayComponent(index)
    if not controls.devDisplays or not controls.devDisplays[index] then return end
    components.displays[index] = setComponent(controls.devDisplays[index], "Display [" .. index .. "]")
    if components.displays[index] then
        debugPrint("Successfully set up display component " .. index)
        setupDisplayEvents(index)
        updatePowerFeedback()
    else
        debugPrint("Failed to set up display component " .. index)
    end
end

local function setRoomControlsComponent()
    debugPrint("Setting room controls component")
    components.compRoomControls = setComponent(controls.compRoomControls, "Room Controls")
    if components.compRoomControls then updateTimerConfig() end
end

local function getComponentNames()
    debugPrint("Discovering components...")
    local names = { DisplayNames = {}, RoomControlsNames = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.displays then
            table.insert(names.DisplayNames, comp.Name)
            debugPrint("  Found display: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and comp.Name:match("^compRoomControls") then
            table.insert(names.RoomControlsNames, comp.Name)
        end
    end
    for _, list in pairs(names) do
        table.sort(list)
        table.insert(list, const.clearString)
    end
    if controls.devDisplays then
        for idx = 1, #controls.devDisplays do
            controls.devDisplays[idx].Choices = names.DisplayNames
        end
        debugPrint("Set choices for " .. #controls.devDisplays .. " display controls")
        debugPrint("Discovery complete - " .. #names.DisplayNames .. " display components found")
    end
    if controls.compRoomControls then
        controls.compRoomControls.Choices = names.RoomControlsNames
    end
end

local function updateRoomName()
    if not components.compRoomControls then return end
    local roomNameCtrl = components.compRoomControls["roomName"]
    if roomNameCtrl and roomNameCtrl.String ~= "" then
        roomName = "[" .. roomNameCtrl.String .. "]"
        debugPrint("Room name updated to: " .. roomName)
    end
    updateTimerConfig()
end

-------------------[ Events ]-------------------
local function registerTimers()
    timers.warmup.EventHandler = function()
        debugPrint("Warmup period ended (Source: Timer)")
        enablePowerControls(true)
        if controls.devDisplays then
            for idx = 1, #controls.devDisplays do
                enablePowerControlIndex(idx, true)
                resetButtonLegends(idx)
            end
        end
        state.isWarming = false
        setProp(controls.ledDisplayWarming, "Boolean", false)
        timers.warmup:Stop()
    end

    timers.cooldown.EventHandler = function()
        debugPrint("Cooldown period ended (Source: Timer)")
        enablePowerControls(true)
        if controls.devDisplays then
            for idx = 1, #controls.devDisplays do
                enablePowerControlIndex(idx, true)
                resetButtonLegends(idx)
            end
        end
        state.isCooling = false
        setProp(controls.ledDisplayCooling, "Boolean", false)
        timers.cooldown:Stop()
    end

    for idx = 1, const.maxDisplays do
        if timers.volumeMute[idx] then
            timers.volumeMute[idx].EventHandler = function()
                local display = components.displays[idx]
                if display then
                    debugPrint("Muting volume for display " .. idx .. " (Source: Timer)")
                    safeAccess(display, displayControls.displayVolume0, "trigger")
                end
                timers.volumeMute[idx]:Stop()
            end
        end
    end
end

local function registerEvents()
    local rcCount = bind(controls.compRoomControls, function() setRoomControlsComponent() end) and 1 or 0
    local powerAllCount = bind(controls.btnDisplayPowerAll, function(ctl)
        if ctl.Boolean then powerOnAll() else powerOffAll() end
    end) and 1 or 0
    local inputAllCount = bind(controls.btnDisplayInputAll, function() setInputAll(const.defaultInput) end) and 1 or 0
    local powerOnCount = bindArray(controls.btnDisplayPowerOn, powerOnDisplay)
    local powerOffCount = bindArray(controls.btnDisplayPowerOff, powerOffDisplay)
    local toggleCount = bindArray(controls.btnDisplayPowerToggle, function(idx, ctl)
        if ctl.Boolean then powerOnDisplay(idx) else powerOffDisplay(idx) end
    end)
    local displayCount = bindArray(controls.devDisplays, setDisplayComponent)

    debugPrint("Registered room controls handler")
    debugPrint("Registered " .. powerOnCount .. " power-on, " .. powerOffCount .. " power-off, " .. toggleCount .. " toggle handlers")
    debugPrint("Registered " .. displayCount .. " display component handlers")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. roomName .. ", debugging=" .. tostring(const.debug))

    getComponentNames()
    setRoomControlsComponent()
    if controls.devDisplays then
        for idx = 1, #controls.devDisplays do
            setDisplayComponent(idx)
        end
    end
    registerEvents()
    registerTimers()
    updateRoomName()
    updatePowerFeedback()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation - " .. getDisplayCount() .. " displays")
end

-------------------[ Public API ]-------------------
DisplayController = {
    powerOnAll = powerOnAll,
    powerOffAll = powerOffAll,
    setInputAll = setInputAll,
    getDisplayCount = getDisplayCount,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing DisplayController for " .. roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ DisplayController initialized for " .. roomName .. " - " .. getDisplayCount() .. " displays")
else
    print("✗ ERROR: DisplayController initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        controls.txtStatus.String = "INIT FAILED"
        controls.txtStatus.Value = 2
    end
end
