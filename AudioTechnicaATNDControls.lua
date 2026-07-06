--[[
    ATNDController (Refactored) - plugin version 1.1
    Author: Nikolas Smith, Q-SYS
    Version: 4.0 | Date: 2025-09-10
    Firmware Req: 10.0.0
    Notes: Flat module, event-driven, no OOP. Lean code + rich debug output.
]]

-------------------[ Config ]-------------------
local config = {
    roomName = "[ATND Controller]",
    debug = true,
    clearString = "[Clear]",
    ledBlack = "Black",
    ledRed = "Red",
    ledGreen = "Green",
    controlColors = { white = "White", pink = "Pink", off = "Off" },
    ledToggleInterval = 1.5,
}

-------------------[ Controls ]-------------------
local controls = {
    devATND = Controls.devATND,
    btnMute = Controls.btnMute,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus,
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

local function getControlArray(ctrl)
    return ctrl and (isArr(ctrl) and ctrl or { ctrl }) or {}
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

local function cleanupComponentHandlers(oldComponent, controlNames, debugCallback)
    if not oldComponent or not controlNames then return false end
    local cleaned = 0
    for _, controlName in ipairs(controlNames) do
        if oldComponent[controlName] then
            setProp(oldComponent[controlName], "EventHandler", nil)
            cleaned = cleaned + 1
        end
    end
    if debugCallback and cleaned > 0 then
        debugCallback("Cleaned up " .. cleaned .. " event handler(s) from old component")
    end
    return cleaned > 0
end

local function validateControls()
    local required = { "devATND", "btnMute" }
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

local function normalizeControlArrays()
    if controls.devATND and not isArr(controls.devATND) then
        controls.devATND = { controls.devATND }
    end
end

-------------------[ State ]-------------------
local components = {
    callSync = nil,
    roomControls = nil,
    micATND = {},
    invalid = {},
}

local state = {
    audioPrivacy = false,
    systemPower = false,
    fireAlarm = false,
    ledState = false,
    muteState = false,
}

local ledToggleTimer = nil
local componentTypes = {
    callSync = "call_sync",
    micATND = "%PLUGIN%_005284C9-04CA-43c1-8D87-EEB0803B4AD9_%FP%_30fd6e855cd3e1f89b7105fc0eb1ce08",
    roomControls = "device_controller_script",
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if config.debug then print("[" .. config.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function updateStatus()
    if not controls.txtStatus then return end
    for _, invalid in pairs(components.invalid) do
        if invalid == true then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function resetmicATND()
    local cleared = {}
    for idx in pairs(components.micATND) do
        components.micATND[idx] = nil
        table.insert(cleared, idx)
    end
    if #cleared > 0 then
        debugPrint("Reset ATND devices array: " .. table.concat(cleared, ", "))
    end
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        updateStatus()
        return nil
    end

    local name = ctrl.String
    if not name or name == "" or name == config.clearString then
        if name == config.clearString then ctrl.String = "" end
        setProp(ctrl, "Color", config.controlColors.white)
        components.invalid[componentType] = false
        updateStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end

    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctrl.String = "[Invalid Component Selected]"
        setProp(ctrl, "Color", config.controlColors.pink)
        components.invalid[componentType] = true
        updateStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end

    setProp(ctrl, "Color", config.controlColors.white)
    components.invalid[componentType] = false
    updateStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function getComponentNames()
    debugPrint("Discovering components...")
    local namesTable = { RoomControlsNames = {}, CallSyncNames = {}, ATNDNames = {} }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
            debugPrint("  Found Call Sync: " .. comp.Name)
        elseif comp.Type == componentTypes.micATND then
            table.insert(namesTable.ATNDNames, comp.Name)
            debugPrint("  Found ATND device: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
            debugPrint("  Found Room Controls: " .. comp.Name)
        end
    end

    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, config.clearString)
    end

    setProp(controls.compRoomControls, "Choices", namesTable.RoomControlsNames)
    setProp(controls.compCallSync, "Choices", namesTable.CallSyncNames)
    forEach(controls.devATND, function(_, ctrl) setProp(ctrl, "Choices", namesTable.ATNDNames) end)
    debugPrint("Discovery complete - " .. (#namesTable.ATNDNames - 1) .. " ATND, " .. (#namesTable.CallSyncNames - 1) .. " Call Sync, " .. (#namesTable.RoomControlsNames - 1) .. " Room Controls")
end

local function getATNDDeviceCount()
    local count = 0
    for _, device in pairs(components.micATND) do
        if device then count = count + 1 end
    end
    return count
end

local function setAllATNDLEDsColor(color)
    for _, device in pairs(components.micATND) do
        if device and device.LedUnmuteColor then
            setProp(device.LedUnmuteColor, "String", color)
        end
    end
end

local function isCallOffHook()
    local callSync = components.callSync
    return callSync and callSync["off.hook"] and callSync["off.hook"].Boolean
end

local function setPrivacyLEDColor(privacyState)
    local color
    if isCallOffHook() or state.fireAlarm then
        color = privacyState and config.ledRed or config.ledGreen
    else
        color = config.ledBlack
    end
    setAllATNDLEDsColor(color)
    debugPrint("Audio Privacy LED: " .. color .. " (Source: Privacy)")
end

local function setFireAlarm(fireAlarmState)
    state.fireAlarm = fireAlarmState

    if fireAlarmState then
        debugPrint("Fire Alarm Active (Source: Room Controls)")
        ledToggleTimer:Start(config.ledToggleInterval)
        setPrivacyLEDColor(true)
        setAllATNDLEDs(false)
        return
    end

    ledToggleTimer:Stop()
    local callSync = components.callSync
    if not callSync or not callSync["off.hook"] then return end

    local isOffHook = callSync["off.hook"].Boolean
    if isOffHook then
        debugPrint("Fire Alarm Cleared - Call Off-Hook (Source: Room Controls)")
        setPrivacyLEDColor(false)
        setAllATNDLEDs(true)
    else
        debugPrint("Fire Alarm Cleared - Call On-Hook (Source: Room Controls)")
        setPrivacyLEDColor(true)
        setAllATNDLEDs(false)
    end
end

local function setHookState(offHook)
    debugPrint("Call Sync Hook: " .. tostring(offHook) .. " (Source: Call Sync)")
    setAllATNDLEDs(offHook)
    local callSync = components.callSync
    local muteState = callSync and callSync["mute"] and callSync["mute"].Boolean
    setPrivacyLEDColor(muteState or false)
end

local function setMuteState(muteState)
    debugPrint("Call Sync Mute: " .. tostring(muteState) .. " (Source: Call Sync)")
    setPrivacyLEDColor(muteState)
end

local function endCall()
    local callSync = components.callSync
    if not callSync or not callSync["end.call"] then return end
    callSync["end.call"]:Trigger()
    debugPrint("End call triggered (Source: Call Control)")
end

local function setupCallSyncComponent()
    if not controls.compCallSync then return end

    cleanupComponentHandlers(
        components.callSync,
        { "off.hook", "mute" },
        function(msg) debugPrint("[CallSync] " .. msg) end
    )

    components.callSync = setComponent(controls.compCallSync, "Call Sync")
    if not components.callSync then return end

    local callSyncName = controls.compCallSync.String or "unknown"
    local atndCount = getATNDDeviceCount()

    bind(components.callSync["off.hook"], function(ctl)
        debugPrint("off.hook: " .. tostring(ctl.Boolean) .. " (affecting " .. atndCount .. " ATND device(s)) (Source: Call Sync)")
        setHookState(ctl.Boolean)
    end)
    bind(components.callSync["mute"], function(ctl)
        debugPrint("mute: " .. tostring(ctl.Boolean) .. " (affecting " .. atndCount .. " ATND device(s)) (Source: Call Sync)")
        setMuteState(ctl.Boolean)
    end)
    debugPrint("Registered Call Sync handlers for: " .. callSyncName .. " (controlling " .. atndCount .. " ATND device(s))")
end

local function setupRoomControlsComponent()
    if not controls.compRoomControls then return end

    cleanupComponentHandlers(
        components.roomControls,
        { "ledSystemPower", "ledFireAlarm" },
        function(msg) debugPrint("[RoomControls] " .. msg) end
    )

    components.roomControls = setComponent(controls.compRoomControls, "Room Controls")
    if not components.roomControls then return end

    bind(components.roomControls["ledSystemPower"], function(ctl)
        if not ctl.Boolean then
            setPrivacyLEDColor(true)
            setAllATNDLEDs(false)
            debugPrint("System Power OFF - All ATNDs muted and LEDs off (Source: Room Controls)")
            return
        end
        debugPrint("System Power ON - Restoring ATND states (Source: Room Controls)")
    end)
    bind(components.roomControls["ledFireAlarm"], function(ctl)
        setFireAlarm(ctl.Boolean)
    end)
    debugPrint("Registered Room Controls handlers")
end

local function registerATNDEventHandlers(idx, device)
    if not device then return end

    bind(device.LedUnmuteColor, function(ctl)
        debugPrint("ATND [" .. idx .. "] Unmute Color: " .. tostring(ctl.String) .. " (Source: ATND Device)")
    end)
end

local function setupATNDComponents()
    resetmicATND()
    if not controls.devATND then return end

    forEach(controls.devATND, function(idx, ctrl)
        local device = setComponent(ctrl, "ATND [" .. idx .. "]")
        if device then
            components.micATND[idx] = device
            registerATNDEventHandlers(idx, device)
        end
    end)
end

local function setupComponents()
    setupCallSyncComponent()
    setupRoomControlsComponent()
    setupATNDComponents()
end

-------------------[ Events ]-------------------
local function registerEvents()
    bind(controls.btnMute, function(ctl)
        setAllATNDLEDsColor(config.ledGreen)
        debugPrint("Mute: " .. tostring(ctl.Boolean) .. " (Source: Mute Button)")
    end)

    bind(controls.compRoomControls, function() setupRoomControlsComponent() end)
    bind(controls.compCallSync, function() setupCallSyncComponent() end)

    bindArray(controls.devATND, function(idx, ctrl)
        local device = setComponent(ctrl, "ATND [" .. idx .. "]")
        if device then
            components.micATND[idx] = device
            registerATNDEventHandlers(idx, device)
        end
    end)
end

local function performSystemInitialization()
    debugPrint("System initialization")
    setPrivacyLEDColor(true)
    setAllATNDLEDs(false)
    debugPrint("System initialization completed")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. config.roomName .. ", debugging=" .. tostring(config.debug))

    ledToggleTimer = Timer.New()
    ledToggleTimer.EventHandler = function()
        state.ledState = not state.ledState
        setAllATNDLEDs(state.ledState)
    end

    getComponentNames()
    setupComponents()
    registerEvents()
    performSystemInitialization()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation - " .. getATNDDeviceCount() .. " ATND device(s)")
end

-------------------[ Public API ]-------------------
local function cleanup()
    if ledToggleTimer then ledToggleTimer:Stop() end
    cleanupComponentHandlers(components.callSync, { "off.hook", "mute" }, function(msg) debugPrint("[Cleanup] " .. msg) end)
    cleanupComponentHandlers(components.roomControls, { "ledSystemPower", "ledFireAlarm" }, function(msg) debugPrint("[Cleanup] " .. msg) end)
    for idx, device in pairs(components.micATND) do
        cleanupComponentHandlers(device, { "LedUnmuteColor" }, function(msg) debugPrint("[Cleanup ATND " .. idx .. "] " .. msg) end)
    end
    resetmicATND()
    components.callSync = nil
    components.roomControls = nil
    components.invalid = {}
    debugPrint("Cleanup completed")
end

ATNDController = {
    setAllLEDs = setAllATNDLEDs,
    setAllLEDsColor = setAllATNDLEDsColor,
    setAudioPrivacy = function(privacyState)
        state.audioPrivacy = privacyState
        setPrivacyLEDColor(privacyState)
    end,
    getPrivacyState = function() return state.audioPrivacy end,
    setFireAlarm = setFireAlarm,
    endCall = endCall,
    setHookState = setHookState,
    setMuteState = setMuteState,
    getDeviceCount = getATNDDeviceCount,
    resetmicATND = resetmicATND,
    getComponentNames = getComponentNames,
    cleanup = cleanup,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing ATND Controller for " .. config.roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ ATND Controller initialized for " .. config.roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end
