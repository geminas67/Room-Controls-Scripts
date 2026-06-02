--[[
  ClockAudioCDTMicController - Q-SYS Control Script for ClockAudio CDT 100
  Author: Nikolas Smith, Q-SYS
  Date: 2026-03-11
  Version: 4.0
  Firmware Req: 10.0.0  

  Controls ClockAudio CDT mic boxes, call sync, mic mixer, and room controls.
  Flat module pattern per qsys-lua-architecture.
]]--

-------------------[ Configuration ]-------------------
local componentTypes = {
    callSync    = "call_sync",
    micBoxes    = "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3",
    micMixer    = "mixer",
    roomControls = "device_controller_script",
}

-- Each entry: {box, buttons = {{toggle, ledIdx, mixerInput}, ...}}
-- toggle=ButtonState num, ledIdx=LED/privacy index, mixerInput=mixer channel
local micButtonConfigs = {
    {box = 1, buttons = {{6,1,1}, {8,2,2}, {10,3,3}}},
    {box = 2, buttons = {{6,1,4}, {8,2,5}, {10,3,6}, {12,4,7}}},
    {box = 3, buttons = {{6,1,8}, {8,2,9}, {10,3,10}, {12,4,11}}},
    {box = 4, buttons = {{6,1,12}, {8,2,13}, {10,3,14}}},
}

-------------------[ Controls ]-------------------
local controls = {
    compMicBox       = Controls.compMicBox,
    compMicMixer     = Controls.compMicMixer,
    compCallSync     = Controls.compCallSync,
    compRoomControls = Controls.compRoomControls,
    txtStatus        = Controls.txtStatus,
    ledFireAlarm     = Controls.ledFireAlarm,
    ledSystemPower   = Controls.ledSystemPower,
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

-------------------[ Config ]-------------------
local const = {
    roomName   = "[ClockAudio CDT]",
    debug      = false,
    clearString = "[Clear]",
}

-------------------[ State ]-------------------
local components = {
    callSync    = nil,
    micBoxes    = {},
    micMixer    = nil,
    roomControls = nil,
    invalid     = {},
}

local state = {
    globalMute   = false,
    offHook      = false,
    audioPrivacy = false,
    systemPower  = true,
    fireAlarm    = false,
}

local config = { toggleInterval = 1.0 }
local ledToggleTimer = nil
local ledState = false

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function checkStatus()
    for _, isInvalid in pairs(components.invalid) do
        if isInvalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function setComponent(ctrl, componentType, expectedType)
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
    if expectedType and comp.Type ~= expectedType then
        setProp(ctrl, "String", "[Wrong Component Type]")
        setProp(ctrl, "Color", "pink")
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: " .. componentType .. " wrong type. Expected " .. tostring(expectedType) .. ", got " .. tostring(comp.Type))
        return nil
    end
    setProp(ctrl, "Color", "white")
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function getMicBoxCount()
    local count = 0
    for boxIdx = 1, 4 do
        if components.micBoxes[boxIdx] then count = count + 1 end
    end
    return count
end

local function getConfigForBox(boxIdx)
    for _, cfg in ipairs(micButtonConfigs) do
        if cfg.box == boxIdx then return cfg end
    end
    return nil
end

local function setLED(stateVal)
    ledState = stateVal
    local greenValue = stateVal and 1 or 0
    for _, cfg in ipairs(micButtonConfigs) do
        local box = components.micBoxes[cfg.box]
        if box then
            for _, btn in ipairs(cfg.buttons) do
                local ledIdx = btn[2]
                local redInput = box["RedBrightnessInput " .. ledIdx]
                local greenInput = box["GreenBrightnessInput " .. ledIdx]
                if redInput then setProp(redInput, "Position", 0) end
                if greenInput then setProp(greenInput, "Position", greenValue) end
            end
        end
    end
end

local function updateIndividualLEDs()
    if not state.offHook then return end
    for _, cfg in ipairs(micButtonConfigs) do
        local box = components.micBoxes[cfg.box]
        if not box then goto continue end
        for _, btn in ipairs(cfg.buttons) do
            local toggle, ledIdx = btn[1], btn[2]
            local buttonState = box["ButtonState " .. toggle]
            local redInput = box["RedBrightnessInput " .. ledIdx]
            local greenInput = box["GreenBrightnessInput " .. ledIdx]
            if not (buttonState and redInput and greenInput) then goto continue end
            if not buttonState.Boolean then
                setProp(redInput, "Position", 0)
                setProp(greenInput, "Position", 0)
            else
                if state.globalMute then
                    setProp(redInput, "Position", 1)
                    setProp(greenInput, "Position", 0)
                else
                    setProp(redInput, "Position", 0)
                    setProp(greenInput, "Position", 1)
                end
            end
            ::continue::
        end
        ::continue::
    end
end

local function turnOffAllLEDs()
    for _, cfg in ipairs(micButtonConfigs) do
        local box = components.micBoxes[cfg.box]
        if box then
            for _, btn in ipairs(cfg.buttons) do
                local ledIdx = btn[2]
                local redInput = box["RedBrightnessInput " .. ledIdx]
                local greenInput = box["GreenBrightnessInput " .. ledIdx]
                if redInput then setProp(redInput, "Position", 0) end
                if greenInput then setProp(greenInput, "Position", 0) end
            end
        end
    end
end

local function updatePrivacyButtonStates(boxIndex)
    local box = components.micBoxes[boxIndex]
    if not box then return end
    local cfg = getConfigForBox(boxIndex)
    if not cfg then return end
    for _, btn in ipairs(cfg.buttons) do
        local toggle, privacyNum = btn[1], btn[2]
        local toggleButton = box["ButtonState " .. toggle]
        local privacyButton = box["ButtonState " .. privacyNum]
        if toggleButton and privacyButton then
            setProp(privacyButton, "IsDisabled", not toggleButton.Boolean)
            debugPrint("Box" .. boxIndex .. " Privacy Button " .. privacyNum .. " " .. (toggleButton.Boolean and "enabled" or "disabled") .. " (Source: Toggle)")
        end
    end
end

local function toggleMic(boxIndex, ledIndex, mixerInput)
    local box = components.micBoxes[boxIndex]
    local mixer = components.micMixer
    if not box or not mixer then return end
    local cfg = getConfigForBox(boxIndex)
    if not cfg then return end
    local toggle = nil
    for _, btn in ipairs(cfg.buttons) do
        if btn[2] == ledIndex then toggle = btn[1]; break end
    end
    if not toggle then return end
    local buttonState = box["ButtonState " .. toggle]
    if not buttonState then return end
    local isActive = buttonState.Boolean
    local muteCtrl = mixer["input." .. mixerInput .. ".mute"]
    if muteCtrl then setProp(muteCtrl, "Boolean", not isActive) end
    updateIndividualLEDs()
    updatePrivacyButtonStates(boxIndex)
end

local function setGlobalMute(muteState)
    state.globalMute = muteState
    if components.callSync and components.callSync["mute"] then
        setProp(components.callSync["mute"], "Boolean", muteState)
    end
    if state.offHook then updateIndividualLEDs() end
end

local function setHookState(hookState)
    state.offHook = hookState
    if hookState then
        updateIndividualLEDs()
    else
        turnOffAllLEDs()
    end
end

local function startLEDToggle()
    if ledToggleTimer then ledToggleTimer:Start(config.toggleInterval) end
end

local function stopLEDToggle()
    if ledToggleTimer then ledToggleTimer:Stop() end
end

local function setupComponentSelector(ctrl, names, componentType)
    if not ctrl then return end
    ctrl.Choices = names
    if #names == 2 and (not ctrl.String or ctrl.String == "") then
        setProp(ctrl, "String", names[1])
        debugPrint("Auto-selected " .. componentType .. ": " .. names[1])
    end
end

local function discoverComponents()
    debugPrint("Discovering components...")
    local namesTable = {
        RoomControlsNames = {},
        CallSyncNames = {},
        MicBoxNames = {},
        MicMixerNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == componentTypes.micBoxes then
            table.insert(namesTable.MicBoxNames, comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        elseif comp.Type == componentTypes.micMixer then
            table.insert(namesTable.MicMixerNames, comp.Name)
        end
    end
    for _, nameList in pairs(namesTable) do
        table.sort(nameList)
        table.insert(nameList, const.clearString)
    end
    if controls.compRoomControls then setupComponentSelector(controls.compRoomControls, namesTable.RoomControlsNames, "Room Controls") end
    if controls.compCallSync then setupComponentSelector(controls.compCallSync, namesTable.CallSyncNames, "Call Sync") end
    if controls.compMicMixer then setupComponentSelector(controls.compMicMixer, namesTable.MicMixerNames, "Mic Mixer") end
    if controls.compMicBox then
        for boxIdx in ipairs(controls.compMicBox) do
            setupComponentSelector(controls.compMicBox[boxIdx], namesTable.MicBoxNames, "MicBox" .. boxIdx)
        end
    end
    local total = #namesTable.RoomControlsNames + #namesTable.CallSyncNames + #namesTable.MicBoxNames + #namesTable.MicMixerNames - 4
    debugPrint("Discovery complete - " .. total .. " components found")
end

local function setupComponents()
    cleanupComponentHandlers(components.roomControls, {"ledSystemPower", "ledFireAlarm"}, function(msg) debugPrint("[Room Controls] " .. msg) end)
    components.roomControls = setComponent(controls.compRoomControls, "Room Controls")

    cleanupComponentHandlers(components.callSync, {"off.hook", "mute"}, function(msg) debugPrint("[Call Sync] " .. msg) end)
    components.callSync = setComponent(controls.compCallSync, "Call Sync")

    components.micMixer = setComponent(controls.compMicMixer, "Mic Mixer")

    for boxIdx = 1, 4 do
        if controls.compMicBox and controls.compMicBox[boxIdx] then
            local oldBox = components.micBoxes[boxIdx]
            if oldBox then
                local buttonControlNames = {}
                for btnNum = 1, 12 do table.insert(buttonControlNames, "ButtonState " .. btnNum) end
                cleanupComponentHandlers(oldBox, buttonControlNames, function(msg) debugPrint("[MicBox" .. string.format("%02d", boxIdx) .. "] " .. msg) end)
            end
            components.micBoxes[boxIdx] = setComponent(controls.compMicBox[boxIdx], "MicBox" .. string.format("%02d", boxIdx))
        end
    end
end

local function initializeLEDStates()
    if not components.callSync then return end
    local offHookControl = components.callSync["off.hook"]
    local muteControl = components.callSync["mute"]
    if not (offHookControl and muteControl) then return end
    state.offHook = offHookControl.Boolean
    state.globalMute = muteControl.Boolean
    if state.offHook then
        updateIndividualLEDs()
    else
        turnOffAllLEDs()
    end
end

local function registerMicHandlers()
    local micHandlerMap = {}
    for _, cfg in ipairs(micButtonConfigs) do
        local box = components.micBoxes[cfg.box]
        if not box then goto continue end
        for _, btn in ipairs(cfg.buttons) do
            local buttonControl = box["ButtonState " .. btn[1]]
            if buttonControl then
                local boxIdx, ledIdx, mixerIdx = cfg.box, btn[2], btn[3]
                micHandlerMap[buttonControl] = function()
                    toggleMic(boxIdx, ledIdx, mixerIdx)
                end
            end
        end
        ::continue::
    end
    local registeredCount = 0
    for ctrl, handler in pairs(micHandlerMap) do
        if bind(ctrl, handler) then registeredCount = registeredCount + 1 end
    end
    debugPrint("Registered " .. registeredCount .. " mic button handlers")
end

local function registerPrivacyButtonHandlers()
    local privacyHandlerMap = {}
    for _, cfg in ipairs(micButtonConfigs) do
        local box = components.micBoxes[cfg.box]
        if not box then goto continue end
        for _, btn in ipairs(cfg.buttons) do
            local privacyNum = btn[2]
            local buttonControl = box["ButtonState " .. privacyNum]
            if buttonControl then
                local boxIndex = cfg.box
                privacyHandlerMap[buttonControl] = function(ctl)
                    if not ctl.Boolean then return end
                    if ctl.IsDisabled then
                        debugPrint("Privacy button " .. privacyNum .. " on box " .. boxIndex .. " ignored (disabled)")
                        return
                    end
                    local callSync = components.callSync
                    if not callSync or not callSync["mute"] then return end
                    local newMute = not callSync["mute"].Boolean
                    setProp(callSync["mute"], "Boolean", newMute)
                    debugPrint("Privacy button " .. privacyNum .. " on box " .. boxIndex .. " → mute " .. tostring(newMute) .. " (Source: Privacy Button)")
                    if state.offHook then updateIndividualLEDs() end
                end
            end
        end
        ::continue::
    end
    local registeredCount = 0
    for ctrl, handler in pairs(privacyHandlerMap) do
        if bind(ctrl, handler) then registeredCount = registeredCount + 1 end
    end
    debugPrint("Registered " .. registeredCount .. " privacy button handlers")
end

local function registerEventHandlers()
    local systemHandlerMap = {}

    if components.roomControls then
        if components.roomControls.ledSystemPower then
            systemHandlerMap[components.roomControls.ledSystemPower] = function(ctl)
                state.systemPower = ctl.Boolean
                debugPrint("System power → " .. (ctl.Boolean and "ON" or "OFF") .. " (Source: Room Controls)")
                if not ctl.Boolean then
                    state.globalMute = true
                    setHookState(false)
                end
            end
        end
        if components.roomControls.ledFireAlarm then
            systemHandlerMap[components.roomControls.ledFireAlarm] = function(ctl)
                state.fireAlarm = ctl.Boolean
                debugPrint("Fire alarm → " .. (ctl.Boolean and "ON" or "OFF") .. " (Source: Room Controls)")
                if ctl.Boolean then
                    startLEDToggle()
                    state.globalMute = true
                    setHookState(false)
                else
                    stopLEDToggle()
                    if state.offHook then setHookState(true) end
                end
            end
        end
    end

    if components.callSync then
        if components.callSync["off.hook"] then
            systemHandlerMap[components.callSync["off.hook"]] = function(ctl)
                debugPrint("Off-hook → " .. (ctl.Boolean and "ON" or "OFF") .. " (Source: Call Sync)")
                setHookState(ctl.Boolean)
            end
        end
        if components.callSync["mute"] then
            systemHandlerMap[components.callSync["mute"]] = function(ctl)
                debugPrint("Global mute → " .. (ctl.Boolean and "ON" or "OFF") .. " (Source: Call Sync)")
                setGlobalMute(ctl.Boolean)
            end
        end
    end

    local registeredCount = 0
    for ctrl, handler in pairs(systemHandlerMap) do
        if bind(ctrl, handler) then registeredCount = registeredCount + 1 end
    end
    debugPrint("Registered " .. registeredCount .. " system handlers")

    registerMicHandlers()
    registerPrivacyButtonHandlers()
end

local function registerComponentSelectorHandlers()
    local function onSelectorChange()
        setupComponents()
        registerEventHandlers()
        initializeLEDStates()
        for _, cfg in ipairs(micButtonConfigs) do
            if components.micBoxes[cfg.box] then updatePrivacyButtonStates(cfg.box) end
        end
    end
    local count = 0
    if controls.compRoomControls then
        if bind(controls.compRoomControls, onSelectorChange) then count = count + 1 end
    end
    if controls.compCallSync then
        if bind(controls.compCallSync, onSelectorChange) then count = count + 1 end
    end
    if controls.compMicMixer then
        if bind(controls.compMicMixer, onSelectorChange) then count = count + 1 end
    end
    if controls.compMicBox then
        for boxIdx in ipairs(controls.compMicBox) do
            if bind(controls.compMicBox[boxIdx], onSelectorChange) then count = count + 1 end
        end
    end
    debugPrint("Registered " .. count .. " component selector handlers")
end

-------------------[ Events ]-------------------
local function registerEvents()
    registerEventHandlers()
    registerComponentSelectorHandlers()
end

-------------------[ Init ]-------------------
local function validateControls()
    local required = {"compMicBox", "compMicMixer", "compCallSync", "compRoomControls", "txtStatus"}
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: ClockAudioCDTMicController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    return true
end

local function normalizeControlArrays()
    if not controls.compMicBox then controls.compMicBox = {} end
    if type(controls.compMicBox) ~= "table" then controls.compMicBox = {controls.compMicBox} end
    local normalized = {}
    for boxIdx = 1, 4 do
        if controls.compMicBox[boxIdx] then normalized[boxIdx] = controls.compMicBox[boxIdx] end
    end
    controls.compMicBox = normalized
end

local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debugging=" .. tostring(const.debug))

    discoverComponents()
    setupComponents()
    registerEvents()
    initializeLEDStates()

    for boxIdx = 1, 4 do
        if components.micBoxes[boxIdx] then updatePrivacyButtonStates(boxIdx) end
    end

    ledToggleTimer = Timer.New()
    ledToggleTimer.EventHandler = function()
        ledState = not ledState
        setLED(ledState)
    end

    if components.roomControls and components.roomControls["roomName"] then
        local actualRoomName = components.roomControls["roomName"].String
        if actualRoomName and actualRoomName ~= "" then
            const.roomName = "[" .. actualRoomName .. "]"
            debugPrint("Room name set to: " .. const.roomName)
        end
    end

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation - " .. getMicBoxCount() .. " mic boxes connected")
end

-------------------[ Public API ]-------------------
ClockAudioCDTMicController = {
    setMicBoxButtonState = function(boxIndex, buttonNumber, stateVal)
        if boxIndex < 1 or boxIndex > 4 then return false end
        if buttonNumber < 1 or buttonNumber > 12 then return false end
        local box = components.micBoxes[boxIndex]
        if not box then return false end
        local buttonControl = box["ButtonState " .. buttonNumber]
        if not buttonControl then return false end
        setProp(buttonControl, "Boolean", stateVal)
        debugPrint("Set Box" .. string.format("%02d", boxIndex) .. " ButtonState " .. buttonNumber .. " → " .. tostring(stateVal))
        return true
    end,
    pulseMicBoxButton = function(boxIndex, buttonNumber, pulseDuration)
        pulseDuration = pulseDuration or 0.2
        if boxIndex < 1 or boxIndex > 4 then return false end
        if buttonNumber < 1 or buttonNumber > 12 then return false end
        local box = components.micBoxes[boxIndex]
        if not box then return false end
        local buttonControl = box["ButtonState " .. buttonNumber]
        if not buttonControl then return false end
        setProp(buttonControl, "Boolean", true)
        local pulseTimer = Timer.New()
        pulseTimer.EventHandler = function()
            setProp(buttonControl, "Boolean", false)
            pulseTimer:Stop()
        end
        pulseTimer:Start(pulseDuration)
        return true
    end,
    getMicBoxCount = getMicBoxCount,
}
-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing ClockAudioCDTMicController for " .. const.roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ ClockAudioCDTMicController initialized for " .. const.roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end

