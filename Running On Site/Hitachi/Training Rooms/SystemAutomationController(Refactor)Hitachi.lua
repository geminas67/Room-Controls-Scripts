--[[
  System Automation Controller - Q-SYS Control Script
  Manages power, audio, video, displays, and motion detection
]]

-------------------[ Configuration ]-------------------
local const = {
    componentTypes = {
    callSync = "call_sync",
    videoBridge = "onvif_camera_operative",
    displays =  "%PLUGIN%_e9ef4a50-ba74-4653-a22e-a58c02839313_%FP%_c7165c3b15ead5f69821d69583f73c8b",
    gains = "gain",
    systemMute = "system_mute",
    camACPR = "%PLUGIN%_6ddbd63b-ebb6-43ed-9c5a-9a7d6dac6f37_%FP%_e114a64149fd1bfd9a7fa61aa51085bd" --NEW
    },

    gainTypeAssignments = {
    ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
    ["Huddle Room"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
    ["Custom Room"] = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
    ["Default"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" }
    }
}
-------------------[ Controls ]-------------------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    compCallSync = Controls.compCallSync,
    compVideoBridge = Controls.compVideoBridge,
    compSystemMute = Controls.compSystemMute,
    compACPR = Controls.compACPR,
    compGains = Controls.compGains,
    typeGain = Controls.typeGain,
    devDisplays = Controls.devDisplays,
    selDefaultConfigs = Controls.selDefaultConfigs,
    warmupTime = Controls.warmupTime,
    cooldownTime = Controls.cooldownTime,
    motionTimeout = Controls.motionTimeout,
    motionGracePeriod = Controls.motionGracePeriod,
    defaultProgramVolume = Controls.defaultProgramVolume,
    defaultMicVolume = Controls.defaultMicVolume,
    defaultGainVolume = Controls.defaultGainVolume,
    btnSystemOnOff = Controls.btnSystemOnOff,
    btnSystemOn = Controls.btnSystemOn,
    btnSystemOff = Controls.btnSystemOff,
    btnSystemOnTrig = Controls.btnSystemOnTrig,
    btnSystemOffTrig = Controls.btnSystemOffTrig,
    ledSystemPower = Controls.ledSystemPower,
    ledSystemWarming = Controls.ledSystemWarming,
    ledSystemCooling = Controls.ledSystemCooling,
    ledMotionIn = Controls.ledMotionIn,
    ledMotionTimeoutActive = Controls.ledMotionTimeoutActive,
    ledMotionGraceActive = Controls.ledMotionGraceActive,
    txtMotionMode = Controls.txtMotionMode,
    btnAudioPrivacy = Controls.btnAudioPrivacy,
    btnVideoPrivacy = Controls.btnVideoPrivacy,
    knbVolumeFader = Controls.knbVolumeFader,
    btnVolumeMute = Controls.btnVolumeMute,
    btnVolumeUp = Controls.btnVolumeUp,
    btnVolumeDn = Controls.btnVolumeDn,
    txtNotificationID = Controls.txtNotificationID
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

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = getControlArray(ctrls)
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
        end) then count = count + 1 end
    end
    return count
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

-------------------[ Config ]-------------------
local clearString = "[Clear]"

-------------------[ State ]-------------------
local roomName = ""
local config = {}
local defaultConfigs = {}
local state = { isWarming = false, isCooling = false, powerLocked = false, motionTimeoutActive = false, motionGraceActive = false }
local components = { callSync = nil, videoBridge = {}, displays = {}, gains = {}, systemMute = nil, camACPR = nil, invalid = {} }
local timers = { motion = Timer.New(), grace = Timer.New(), warmup = Timer.New(), cooldown = Timer.New() }

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if config.debugging ~= false then print("[" .. roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    for _, name in ipairs({"roomName", "txtStatus", "btnSystemOnOff", "ledSystemPower"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

local function normalizeControlArrays()
    for _, controlName in ipairs({"compVideoBridge", "compGains", "devDisplays", "typeGain", "btnVideoPrivacy", "knbVolumeFader", "btnVolumeMute", "btnVolumeUp", "btnVolumeDn"}) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then controls[controlName] = { ctrl } end
    end
end

local function safeAccess(component, control, action, value)
    if not component or not component[control] then return false end
    local success, result = pcall(function()
        if      action == "set"         then component[control].Boolean = value; return true
        elseif  action == "setPosition" then component[control].Position = value; return true
        elseif  action == "setString"   then component[control].String = value; return true
        elseif  action == "trigger"     then component[control]:Trigger(); return true
        elseif  action == "get"         then return component[control].Boolean
        elseif  action == "getPosition" then return component[control].Position
        elseif  action == "getString"   then return component[control].String end
        return false
    end)
    if not success then debugPrint("Component access error: "..tostring(result)); return false end
    return success and result or false
end

local function getGainComponent(idx) return components.gains[idx] end

local function getGainType(idx)
    if controls.typeGain and controls.typeGain[idx] then return controls.typeGain[idx].String end
    return idx == 1 and "Program" or "Mic"
end

local function getDefaultVolumeForType(gainType)
    local defaults = { Program = config.defaultProgramVolume, Mic = config.defaultMicVolume, Gain = config.defaultGainVolume }
    return defaults[gainType] or defaults.Mic
end

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

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == clearString then
        if name == clearString then ctrl.String = "" end
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

local function updateVolumeVisuals(idx)
    local fader = controls.knbVolumeFader and controls.knbVolumeFader[idx]
    local mute = controls.btnVolumeMute and controls.btnVolumeMute[idx]
    if not fader or not mute then return end
    local isMuted = mute.Boolean
    local gainType = getGainType(idx)
    setProp(mute, "CssClass", isMuted and (gainType == "Mic" and "icon-mic_none" or "icon-volume_mute") or (gainType == "Mic" and "icon-mic_off" or "icon-volume_off"))
    setProp(fader, "Color", isMuted and "#CCCCCC" or "#0561A5")
end

local function publishNotification()
    if not controls.txtNotificationID or controls.txtNotificationID.String == "" then return end
    local systemState = {
        RoomName = roomName,
        PowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean or false,
        SystemWarming = controls.ledSystemWarming and controls.ledSystemWarming.Boolean or false,
        SystemCooling = controls.ledSystemCooling and controls.ledSystemCooling.Boolean or false,
        AudioPrivacy = controls.btnAudioPrivacy and controls.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = (function()
            local vb = controls.btnVideoPrivacy
            if not vb then return false end
            local ctrl = isArr(vb) and vb[1] or vb
            return ctrl and ctrl.Boolean or false
        end)(),
        ACPRState = (components.camACPR and components.camACPR["TrackingBypass"] and components.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time(),
        GainControls = {}
    }
    for idx, gain in pairs(components.gains) do
        if gain then
            systemState.GainControls[idx] = {
                Level = safeAccess(gain, "gain", "getPosition") or 0,
                Muted = safeAccess(gain, "mute", "get") or false
            }
        end
    end
    Notifications.Publish(controls.txtNotificationID.String, systemState)
end

local function getGainCount()
    local count = 0
    for _ in pairs(components.gains) do count = count + 1 end
    return count
end

local function enablePowerControls(enabled)
    for _, btn in ipairs({controls.btnSystemOnOff, controls.btnSystemOn, controls.btnSystemOff}) do
        if btn then setProp(btn, "IsDisabled", not enabled) end
    end
end

local function setSystemPowerFB(powerState)
    setProp(controls.ledSystemPower, "Boolean", powerState)
    setProp(controls.btnSystemOnOff, "Boolean", powerState)
    setProp(controls.btnSystemOn, "Boolean", powerState)
    setProp(controls.btnSystemOff, "Boolean", not powerState)
end

local function endCalls()
    if components.callSync then safeAccess(components.callSync, "call.decline", "trigger") end
end

local function applyVolumeDefaults()
    debugPrint("Applying volume defaults based on current typeGain settings")
    for idx, gain in pairs(components.gains) do
        if gain then
            local gainType = getGainType(idx)
            local defaultValue = getDefaultVolumeForType(gainType)
            safeAccess(gain, "gain", "setPosition", defaultValue)
            updateVolumeVisuals(idx)
            debugPrint("Applied default " .. gainType .. " Volume (" .. defaultValue .. ") to gain index " .. idx .. " (Source: Power On)")
        end
    end
end

local function powerDisplays(displayState)
    local control = displayState and "PowerOn" or "PowerOff"
    for _, display in pairs(components.displays) do
        if display then safeAccess(display, control, "trigger") end
    end
end

local function setVolume(level, gainIndex)
    local update = function(idx, gain)
        safeAccess(gain, "gain", "setPosition", level)
        updateVolumeVisuals(idx)
    end
    if gainIndex then
        local gain = getGainComponent(gainIndex)
        if gain then update(gainIndex, gain) end
    else
        for idx, gain in pairs(components.gains) do if gain then update(idx, gain) end end
    end
    publishNotification()
end

local function setMute(muteState, gainIndex)
    local mute = function(idx, gain)
        safeAccess(gain, "mute", "set", muteState)
        updateVolumeVisuals(idx)
    end
    if gainIndex then
        local gain = getGainComponent(gainIndex)
        if gain then mute(gainIndex, gain) end
    else
        for idx, gain in pairs(components.gains) do if gain then mute(idx, gain) end end
    end
    publishNotification()
end

local function setAudioPrivacy(privacyState)
    safeAccess(components.callSync, "mute", "set", privacyState)
    setProp(controls.btnAudioPrivacy, "Boolean", privacyState)
    setProp(controls.btnAudioPrivacy, "CssClass", privacyState and "icon-mic_none" or "icon-mic_off")
    publishNotification()
end

local function setSystemMute(muteState)
    if components.systemMute then safeAccess(components.systemMute, "mute", "set", muteState) end
end

local function setVolumeUpDown(direction, pressed, gainIndex)
    local action = direction == "up" and "stepper.increase" or "stepper.decrease"
    local step = function(idx, gain)
        safeAccess(gain, action, "set", pressed)
        if pressed then safeAccess(gain, "mute", "set", false) end
        updateVolumeVisuals(idx)
    end
    if gainIndex then
        local gain = getGainComponent(gainIndex)
        if gain then step(gainIndex, gain) end
    else
        for idx, gain in pairs(components.gains) do if gain then step(idx, gain) end end
    end
    publishNotification()
end

local function setVideoPrivacy(privacyState, idx)
    local apply = function(index, videoBridge)
        safeAccess(videoBridge, "toggle.privacy", "set", privacyState)
        -- videoBridgeCheckPrivacy called from event
    end
    if idx then
        local videoBridge = components.videoBridge[idx]
        if videoBridge then apply(idx, videoBridge) end
    else
        for index, videoBridge in pairs(components.videoBridge) do if videoBridge then apply(index, videoBridge) end end
    end
    publishNotification()
end

local function videoBridgeCheckPrivacy(idx)
    idx = idx or 1
    local videoBridge = components.videoBridge[idx]
    if not videoBridge then return end
    local privacyState = safeAccess(videoBridge, "toggle.privacy", "get")
    debugPrint("Video Bridge [" .. idx .. "] Privacy State: " .. tostring(privacyState) .. " (Source: Component)")
    if isArr(controls.btnVideoPrivacy) and controls.btnVideoPrivacy[idx] then
        setProp(controls.btnVideoPrivacy[idx], "Boolean", privacyState)
    elseif controls.btnVideoPrivacy and not isArr(controls.btnVideoPrivacy) then
        setProp(controls.btnVideoPrivacy, "Boolean", privacyState)
    end
end

local function callSyncCheckMute()
    if not components.callSync then return end
    local muteState = safeAccess(components.callSync, "mute", "get")
    debugPrint("Call Sync Mute State: " .. tostring(muteState) .. " (Source: Component)")
    if controls.btnAudioPrivacy then setProp(controls.btnAudioPrivacy, "Boolean", muteState) end
end

local function callSyncCheckConnection()
    if not components.callSync then return end
    local offHook = safeAccess(components.callSync, "off.hook", "get")
    callSyncCheckMute()
    for idx in pairs(components.videoBridge) do setVideoPrivacy(not offHook, idx) end
    if components.videoBridge[1] then videoBridgeCheckPrivacy(1) end
    if components.camACPR and components.camACPR["TrackingBypass"] then
        components.camACPR["TrackingBypass"].IsDisabled = not offHook
        safeAccess(components.camACPR, "TrackingBypass", "set", not offHook)
    end
end

local function getVolumeLvl(idx)
    local gain = getGainComponent(idx)
    if not gain or not controls.knbVolumeFader or not controls.knbVolumeFader[idx] then return end
    setProp(controls.knbVolumeFader[idx], "Position", safeAccess(gain, "gain", "getPosition"))
    updateVolumeVisuals(idx)
    publishNotification()
end

local function getVolumeMute(idx)
    local gain = getGainComponent(idx)
    if not gain or not controls.btnVolumeMute or not controls.btnVolumeMute[idx] then return end
    setProp(controls.btnVolumeMute[idx], "Boolean", safeAccess(gain, "mute", "get"))
    updateVolumeVisuals(idx)
    publishNotification()
end

local function powerOn()
    debugPrint("[Power] Powering On (Source: User)")
    if controls.btnSystemOnTrig then controls.btnSystemOnTrig:Trigger() end
    enablePowerControls(false)
    state.isWarming = true
    setProp(controls.ledSystemWarming, "Boolean", true)
    timers.warmup:Start(config.warmupTime or 10)
    setSystemPowerFB(true)
    applyVolumeDefaults()
    setMute(false)
    setAudioPrivacy(true)
    powerDisplays(true)
    publishNotification()
end

local function powerOff(sourceTag)
    sourceTag = sourceTag or "User"
    debugPrint("[Power] Powering Off (Source: " .. sourceTag .. ")")
    if controls.btnSystemOffTrig then controls.btnSystemOffTrig:Trigger() end
    enablePowerControls(false)
    state.isCooling = true
    setProp(controls.ledSystemCooling, "Boolean", true)
    timers.cooldown:Start(config.cooldownTime or 5)
    setSystemPowerFB(false)
    setAudioPrivacy(true)
    for idx, gain in pairs(components.gains) do
        if gain then
            local gainType = getGainType(idx)
            if gainType ~= "micVolume" and gainType ~= "Mic" then setMute(true, idx) end
        end
    end
    setVideoPrivacy(true)
    powerDisplays(false)
    endCalls()
    publishNotification()
end

local function checkMotion()
    debugPrint("[Motion] Checking Motion")
    if controls.ledMotionIn and controls.ledMotionIn.Boolean then
        state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        timers.motion:Stop()
        if controls.ledSystemPower and not controls.ledSystemPower.Boolean and not state.motionGraceActive and controls.txtMotionMode and controls.txtMotionMode.String == "Motion On/Off" then
            debugPrint("[Motion] Turning system on from motion (Source: Motion Sensor)")
            powerOn()
        end
        return
    end
    if controls.txtMotionMode and (controls.txtMotionMode.String == "Motion On/Off" or controls.txtMotionMode.String == "Motion Off") then
        debugPrint("[Motion] Starting Motion Off Timer")
        state.motionTimeoutActive = true
        setProp(controls.ledMotionTimeoutActive, "Boolean", true)
        timers.motion:Start((controls.motionTimeout and controls.motionTimeout.Value) or config.motionTimeout or 300)
    end
end

local function getComponentNames()
    local names = { callSync = {}, videoBridge = {}, camACPR = {}, displays = {}, gains = {}, systemMute = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == const.componentTypes.callSync then table.insert(names.callSync, comp.Name)
        elseif comp.Type == const.componentTypes.videoBridge then table.insert(names.videoBridge, comp.Name)
        elseif comp.Type == const.componentTypes.displays then table.insert(names.displays, comp.Name)
        elseif comp.Type == const.componentTypes.gains then table.insert(names.gains, comp.Name)
        elseif comp.Type == const.componentTypes.systemMute then table.insert(names.systemMute, comp.Name)
        elseif comp.Type == const.componentTypes.camACPR then table.insert(names.camACPR, comp.Name) end
    end
    for _, list in pairs(names) do table.sort(list); table.insert(list, clearString) end
    if controls.compCallSync then controls.compCallSync.Choices = names.callSync end
    forEach(controls.compVideoBridge, function(_, ctrl) ctrl.Choices = names.videoBridge end)
    if controls.compSystemMute then controls.compSystemMute.Choices = names.systemMute end
    if controls.compACPR then controls.compACPR.Choices = names.camACPR end
    forEach(controls.compGains, function(_, ctrl) ctrl.Choices = names.gains end)
    forEach(controls.devDisplays, function(_, ctrl) ctrl.Choices = names.displays end)
    debugPrint("Discovery complete: " .. (#names.callSync - 1) .. " callSync, " .. (#names.videoBridge - 1) .. " videoBridge, " .. (#names.gains - 1) .. " gains, " .. (#names.displays - 1) .. " displays")
end

local function setCallSyncComponent()
    components.callSync = setComponent(controls.compCallSync, "Call Sync")
    local comp = components.callSync
    if not comp then return end
    if comp["off.hook"] then comp["off.hook"].EventHandler = callSyncCheckConnection end
    if comp["mute"] then comp["mute"].EventHandler = callSyncCheckMute end
end

local function setVideoBridgeComponent(idx)
    if not controls.compVideoBridge or not controls.compVideoBridge[idx] then return end
    components.videoBridge[idx] = setComponent(controls.compVideoBridge[idx], "Video Bridge [" .. idx .. "]")
    local comp = components.videoBridge[idx]
    if not comp then return end
    if comp["toggle.privacy"] then
        comp["toggle.privacy"].EventHandler = function() videoBridgeCheckPrivacy(idx) end
    end
    videoBridgeCheckPrivacy(idx)
end

local function setGainComponent(idx)
    if not controls.compGains or not controls.compGains[idx] then return end
    components.gains[idx] = setComponent(controls.compGains[idx], "Gain [" .. idx .. "]")
    local comp = components.gains[idx]
    if not comp then return end
    if comp["gain"] then comp["gain"].EventHandler = function() getVolumeLvl(idx) end end
    if comp["mute"] then comp["mute"].EventHandler = function() getVolumeMute(idx) end end
    getVolumeLvl(idx)
    getVolumeMute(idx)
end

local function setSystemMuteComponent()
    components.systemMute = setComponent(controls.compSystemMute, "System Mute")
end

local function setCamACPRComponent()
    components.camACPR = setComponent(controls.compACPR, "Camera ACPR")
    local comp = components.camACPR
    if not comp then return end
    if comp["TrackingBypass"] then
        comp["TrackingBypass"].EventHandler = function()
            local cam = components.camACPR
            if not cam or not cam["TrackingBypass"] then return end
            local bypassState = safeAccess(cam, "TrackingBypass", "get")
            debugPrint("ACPR Tracking Bypass: " .. tostring(bypassState) .. " (Source: Component)")
            cam["TrackingBypass"].Legend = cam["TrackingBypass"].IsDisabled and "Disabled" or (bypassState and "Off" or "Auto")
        end
    end
    callSyncCheckConnection()
end

local function setDisplayComponent(idx)
    if not controls.devDisplays or not controls.devDisplays[idx] then return end
    components.displays[idx] = setComponent(controls.devDisplays[idx], "Display [" .. idx .. "]")
end

local function setGainTypeAssignments(roomType)
    roomType = roomType or (controls.selDefaultConfigs and controls.selDefaultConfigs.String) or "Default"
    local assign = const.gainTypeAssignments[roomType] or const.gainTypeAssignments["Default"]
    for idx, gainType in ipairs(assign) do
        if controls.typeGain and controls.typeGain[idx] then
            controls.typeGain[idx].String = idx == 1 and "Program" or gainType
            controls.typeGain[idx].IsDisabled = idx == 1
        end
    end
end

local function setupConfigSelection()
    if not controls.selDefaultConfigs then return end
    controls.selDefaultConfigs.Choices = { "Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined" }
    local maps = {
        { control = "warmupTime", config = "warmupTime" },
        { control = "cooldownTime", config = "cooldownTime" },
        { control = "motionTimeout", config = "motionTimeout" },
        { control = "motionGracePeriod", config = "gracePeriod" },
        { control = "defaultProgramVolume", config = "defaultProgramVolume" },
        { control = "defaultMicVolume", config = "defaultMicVolume" },
        { control = "defaultGainVolume", config = "defaultGainVolume" }
    }
    local function updateValues(configType)
        local conf = defaultConfigs[configType]
        if not conf then return end
        local isUser = configType == "User Defined"
        for _, map in ipairs(maps) do
            local ctrl = controls[map.control]
            if ctrl and ctrl.Value ~= nil then
                ctrl.Value = conf[map.config]
                ctrl.IsDisabled = not isUser
            end
        end
    end
    bind(controls.selDefaultConfigs, function(ctl)
        updateValues(ctl.String)
        setGainTypeAssignments(ctl.String)
        applyVolumeDefaults()
    end)
    for _, map in ipairs(maps) do
        local ctrl = controls[map.control]
        if ctrl then
            bind(ctrl, function(value)
                if controls.selDefaultConfigs and controls.selDefaultConfigs.String == "User Defined" then
                    defaultConfigs["User Defined"][map.config] = value.Value
                end
            end)
        end
    end
    controls.selDefaultConfigs.String = "Default"
    updateValues("Default")
end

local function setFireAlarm(alarmState)
    if alarmState then
        setSystemMute(true)
        powerDisplays(false)
        return
    end
    if controls.ledSystemPower and controls.ledSystemPower.Boolean then
        setSystemMute(false)
        powerDisplays(true)
    end
end

-------------------[ Events ]-------------------
local function registerEvents()
    local btnCount, arrayCount = 0, 0
    if bind(controls.btnSystemOnOff, function(ctl) if ctl.Boolean then powerOn() else powerOff() end end) then btnCount = btnCount + 1 end
    if bind(controls.btnSystemOn, powerOn) then btnCount = btnCount + 1 end
    if bind(controls.btnSystemOff, function()
        powerOff()
        state.motionGraceActive = true
        setProp(controls.ledMotionGraceActive, "Boolean", true)
        timers.grace:Start(config.gracePeriod or 30)
    end) then btnCount = btnCount + 1 end
    if bind(controls.btnAudioPrivacy, function(ctl) setAudioPrivacy(ctl.Boolean) end) then btnCount = btnCount + 1 end
    if bind(controls.roomName, function()
        roomName = "[" .. (controls.roomName.String or "Unknown") .. "]"
        debugPrint("Room name updated to: " .. roomName)
        publishNotification()
    end) then btnCount = btnCount + 1 end
    if bind(controls.ledMotionIn, checkMotion) then btnCount = btnCount + 1 end
    if bind(controls.compCallSync, setCallSyncComponent) then btnCount = btnCount + 1 end
    if bind(controls.compSystemMute, setSystemMuteComponent) then btnCount = btnCount + 1 end
    if bind(controls.compACPR, setCamACPRComponent) then btnCount = btnCount + 1 end

    arrayCount = arrayCount + bindArray(controls.btnVideoPrivacy, function(idx, ctl) setVideoPrivacy(ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(controls.knbVolumeFader, function(idx, ctl) setVolume(ctl.Position, idx) end)
    arrayCount = arrayCount + bindArray(controls.btnVolumeMute, function(idx, ctl) setMute(ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(controls.btnVolumeUp, function(idx, ctl) setVolumeUpDown("up", ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(controls.btnVolumeDn, function(idx, ctl) setVolumeUpDown("down", ctl.Boolean, idx) end)

    forEach(controls.compVideoBridge, function(idx, ctrl) bind(ctrl, function() setVideoBridgeComponent(idx) end) end)
    forEach(controls.compGains, function(idx, ctrl) bind(ctrl, function() setGainComponent(idx) end) end)
    forEach(controls.devDisplays, function(idx, ctrl) bind(ctrl, function() setDisplayComponent(idx) end) end)

    forEach(controls.typeGain, function(i, ctrl)
        if i > 1 then
            bind(ctrl, function(gainCtl)
                if components.gains[i] then
                    local defaultValue = getDefaultVolumeForType(gainCtl.String)
                    setVolume(defaultValue, i)
                    debugPrint("Applying default volume (" .. defaultValue .. ") to gain index " .. i .. " (Type: " .. gainCtl.String .. ") (Source: Type Selector)")
                end
                publishNotification()
            end)
        end
    end)

    debugPrint("Registered " .. btnCount .. " button/control handlers, " .. arrayCount .. " array handlers")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    roomName = "[" .. (controls.roomName.String or "Unknown") .. "]"
    debugPrint("Configuration: ROOM_NAME=" .. roomName .. ", debugging=" .. tostring(config.debugging ~= false))

    enablePowerControls(true)
    getComponentNames()
    if controls.txtMotionMode then controls.txtMotionMode.Choices = { "Motion On/Off", "Motion Off", "Motion Disabled" } end
    forEach(controls.typeGain, function(_, ctrl) ctrl.Choices = { "Mic", "Gain" } end)
    setGainTypeAssignments()
    setCallSyncComponent()
    setSystemMuteComponent()
    setCamACPRComponent()
    forEach(controls.compVideoBridge, function(idx) setVideoBridgeComponent(idx) end)
    forEach(controls.compGains, function(idx) setGainComponent(idx) end)
    forEach(controls.devDisplays, function(idx) setDisplayComponent(idx) end)

    timers.motion.EventHandler = function()
        state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        powerOff("Motion timeout")
    end
    timers.grace.EventHandler = function()
        state.motionGraceActive = false
        setProp(controls.ledMotionGraceActive, "Boolean", false)
    end
    timers.warmup.EventHandler = function()
        state.isWarming = false
        setProp(controls.ledSystemWarming, "Boolean", false)
        enablePowerControls(true)
        publishNotification()
    end
    timers.cooldown.EventHandler = function()
        state.isCooling = false
        setProp(controls.ledSystemCooling, "Boolean", false)
        enablePowerControls(true)
        publishNotification()
    end

    powerOff("Initialization")

    debugPrint("Ready - " .. getGainCount() .. " gain controls detected")
    debugPrint("=== Initialization Complete ===")
end

-------------------[ Factory ]-------------------
local function getDefaultConfig(roomType)
    local base = { defaultProgramVolume = 0.7, defaultMicVolume = 0.5, defaultGainVolume = 0.7 }
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = (controls.warmupTime and controls.warmupTime.Value) or 10,
            cooldownTime = (controls.cooldownTime and controls.cooldownTime.Value) or 5,
            motionTimeout = (controls.motionTimeout and controls.motionTimeout.Value) or 300,
            gracePeriod = (controls.motionGracePeriod and controls.motionGracePeriod.Value) or 30,
            defaultProgramVolume = (controls.defaultProgramVolume and controls.defaultProgramVolume.Value) or base.defaultProgramVolume,
            defaultMicVolume = (controls.defaultMicVolume and controls.defaultMicVolume.Value) or base.defaultMicVolume,
            defaultGainVolume = (controls.defaultGainVolume and controls.defaultGainVolume.Value) or base.defaultGainVolume,
        }
    end
    local defaults = {
        ["Conference Room"] = { debugging = true, warmupTime = 15, cooldownTime = 10, motionTimeout = 600, gracePeriod = 60, defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
        ["Huddle Room"] = { debugging = false, warmupTime = 5, cooldownTime = 3, motionTimeout = 300, gracePeriod = 30, defaultProgramVolume = 0.6, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
        ["Default"] = { debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30, defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
        ["Custom Room"] = { debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30, defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume }
    }
    return defaults[roomType] or defaults["Default"]
end

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing SystemAutomationController...")
    if not validateControls() then error("Control validation failed") end
    local configType = controls.selDefaultConfigs and controls.selDefaultConfigs.String or "Default"
    config = getDefaultConfig(configType)
    defaultConfigs = {
        ["Conference Room"] = getDefaultConfig("Conference Room"),
        ["Huddle Room"] = getDefaultConfig("Huddle Room"),
        ["Default"] = getDefaultConfig("Default"),
        ["Custom Room"] = getDefaultConfig("Custom Room"),
        ["User Defined"] = getDefaultConfig("User Defined")
    }
    normalizeControlArrays()
    registerEvents()
    setupConfigSelection()
    init()
end)

if ok then
    print("✓ SystemAutomationController initialized for " .. roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        controls.txtStatus.String = "INIT FAILED"
        controls.txtStatus.Value = 2
    end
end

-------------------[ Public API ]-------------------
mySystemController = {
    setVolume = setVolume,
    setMute = setMute,
    getGainCount = getGainCount,
    publishNotification = publishNotification,
    setFireAlarm = setFireAlarm,
    powerOn = powerOn,
    powerOff = powerOff,
}
