--[[
  System Automation Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2026-08-07 
  Firmware Req: 10.4
  Manages power, audio, video, displays, and motion detection
]]

-------------------[ Configuration ]-------------------
cfg = {
    componentType = {
    callSync = "call_sync",
    videoBridge = "usb_uvc",
    displays = "%PLUGIN%_bd0a5e74-c1bf-48ee-8574-e42e1e7b2bb9_%FP%_31e2e2d7be2243768d2bd9c853a6295c",
    gains = "gain",
    systemMute = "system_mute",
    camACPR = "%PLUGIN%_6ddbd63b-ebb6-43ed-9c5a-9a7d6dac6f37_%FP%_e114a64149fd1bfd9a7fa61aa51085bd" --NEW
    },

    gainTypeAssignment = {
    ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
    ["Huddle Room"]     = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
    ["Custom Room"]     = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
    ["Default"]         = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" }
    },

    btnMuteShell = "button-square-red-big-icon",
    gainTypeIcon = {
        Mic = "iconmicoutline",
        Program = "iconvolumemuteoutline",
        Gain = "iconvolumemuteoutline",
    },
}
-------------------[ Controls ]-------------------
control = {
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
function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    local ok = pcall(function() ctrl.EventHandler = handler end)
    return ok
end

function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

function bindArray(ctrls, handler)
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

function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

-------------------[ Config ]-------------------
clearString = "[Clear]"

-------------------[ State ]-------------------
roomName = ""
config = {}
defaultConfigs = {}
state = { isWarming = false, isCooling = false, powerLocked = false, motionTimeoutActive = false, motionGraceActive = false }
component = { callSync = nil, videoBridge = {}, displays = {}, gains = {}, systemMute = nil, camACPR = nil, invalid = {} }
timers = { motion = Timer.New(), grace = Timer.New(), warmup = Timer.New(), cooldown = Timer.New() }

-------------------[ Debug ]-------------------
function debugPrint(str)
    if config.debugging ~= false then print("[" .. roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
function validateControls()
    for _, name in ipairs({"roomName", "txtStatus", "btnSystemOnOff", "ledSystemPower"}) do
        if not control[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

function normalizeControlArrays()
    for _, controlName in ipairs({"compVideoBridge", "compGains", "devDisplays", "typeGain", "btnVideoPrivacy", "knbVolumeFader", "btnVolumeMute", "btnVolumeUp", "btnVolumeDn"}) do
        local ctrl = control[controlName]
        if ctrl and not isArr(ctrl) then control[controlName] = { ctrl } end
    end
end

function safeAccess(component, control, action, value)
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

function getGainComponent(idx) return component.gains[idx] end

function getGainType(idx)
    if control.typeGain and control.typeGain[idx] then return control.typeGain[idx].String end
    return idx == 1 and "Program" or "Mic"
end

function getDefaultVolumeForType(gainType)
    local defaults = { Program = config.defaultProgramVolume, Mic = config.defaultMicVolume, Gain = config.defaultGainVolume }
    return defaults[gainType] or defaults.Mic
end

function checkStatus()
    for _, isInvalid in pairs(component.invalid) do
        if isInvalid then
            setProp(control.txtStatus, "String", "Invalid Components")
            setProp(control.txtStatus, "Value", 1)
            return
        end
    end
    setProp(control.txtStatus, "String", "OK")
    setProp(control.txtStatus, "Value", 0)
end

function setComponent(ctrl, componentType)
    if not ctrl then
        component.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == clearString then
        if name == clearString then ctrl.String = "" end
        ctrl.Color = "white"
        component.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        component.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    ctrl.Color = "white"
    component.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

function updateVolumeVisuals(idx)
    local fader = control.knbVolumeFader and control.knbVolumeFader[idx]
    local mute = control.btnVolumeMute and control.btnVolumeMute[idx]
    if not mute or not fader then return end
    local gainType = getGainType(idx)
    local isMuted = mute.Boolean
    setProp(fader, "CssClass", isMuted and "meter-muted" or "meter") --set the css classes for the fader
    local muteIcon = cfg.gainTypeIcon[gainType] or cfg.gainTypeIcon.Program
    setProp(mute, "CssClass", cfg.btnMuteShell .. " " .. muteIcon)
end

function publishNotification()
    if not control.txtNotificationID or control.txtNotificationID.String == "" then return end
    local systemState = {
        RoomName = roomName,
        PowerState = control.ledSystemPower and control.ledSystemPower.Boolean or false,
        SystemWarming = control.ledSystemWarming and control.ledSystemWarming.Boolean or false,
        SystemCooling = control.ledSystemCooling and control.ledSystemCooling.Boolean or false,
        AudioPrivacy = control.btnAudioPrivacy and control.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = (function()
            local vb = control.btnVideoPrivacy
            if not vb then return false end
            local ctrl = isArr(vb) and vb[1] or vb
            return ctrl and ctrl.Boolean or false
        end)(),
        ACPRState = (component.camACPR and component.camACPR["TrackingBypass"] and component.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time(),
        GainControls = {}
    }
    for idx, gain in pairs(component.gains) do
        if gain then
            systemState.GainControls[idx] = {
                Level = safeAccess(gain, "gain", "getPosition") or 0,
                Muted = safeAccess(gain, "mute", "get") or false
            }
        end
    end
    Notifications.Publish(control.txtNotificationID.String, systemState)
end

function getGainCount()
    local count = 0
    for _ in pairs(component.gains) do count = count + 1 end
    return count
end

function enablePowerControls(enabled)
    for _, btn in ipairs({control.btnSystemOnOff, control.btnSystemOn, control.btnSystemOff}) do
        if btn then setProp(btn, "IsDisabled", not enabled) end
    end
end

function setSystemPowerFB(powerState)
    setProp(control.ledSystemPower, "Boolean", powerState)
    setProp(control.btnSystemOnOff, "Boolean", powerState)
    setProp(control.btnSystemOn, "Boolean", powerState)
    setProp(control.btnSystemOff, "Boolean", not powerState)
end

function endCalls()
    if component.callSync then safeAccess(component.callSync, "call.decline", "trigger") end
end

function applyVolumeDefaults()
    debugPrint("Applying volume defaults based on current typeGain settings")
    for idx, gain in pairs(component.gains) do
        if gain then
            local gainType = getGainType(idx)
            local defaultValue = getDefaultVolumeForType(gainType)
            safeAccess(gain, "gain", "setPosition", defaultValue)
            updateVolumeVisuals(idx)
            debugPrint("Applied default " .. gainType .. " Volume (" .. defaultValue .. ") to gain index " .. idx .. " (Source: Power On)")
        end
    end
end

function powerDisplays(displayState)
    local control = displayState and "PowerOn" or "PowerOff"
    for _, display in pairs(component.displays) do
        if display then safeAccess(display, control, "trigger") end
    end
end

function setVolume(level, gainIndex)
    local update = function(idx, gain)
        safeAccess(gain, "gain", "setPosition", level)
        updateVolumeVisuals(idx)
    end
    if gainIndex then
        local gain = getGainComponent(gainIndex)
        if gain then update(gainIndex, gain) end
    else
        for idx, gain in pairs(component.gains) do if gain then update(idx, gain) end end
    end
    publishNotification()
end

function setMute(muteState, gainIndex)
    local mute = function(idx, gain)
        safeAccess(gain, "mute", "set", muteState)
        updateVolumeVisuals(idx)
    end
    if gainIndex then
        local gain = getGainComponent(gainIndex)
        if gain then mute(gainIndex, gain) end
    else
        for idx, gain in pairs(component.gains) do if gain then mute(idx, gain) end end
    end
    publishNotification()
end

function setAudioPrivacy(privacyState)
    safeAccess(component.callSync, "mute", "set", privacyState)
    setProp(control.btnAudioPrivacy, "Boolean", privacyState)
    publishNotification()
end

function setSystemMute(muteState)
    if component.systemMute then safeAccess(component.systemMute, "mute", "set", muteState) end
end

function setVolumeUpDown(direction, pressed, gainIndex)
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
        for idx, gain in pairs(component.gains) do if gain then step(idx, gain) end end
    end
    publishNotification()
end

function setVideoPrivacy(privacyState, idx)
    local apply = function(index, videoBridge)
        safeAccess(videoBridge, "toggle.privacy", "set", privacyState)
        -- getVideoBridgePrivacyState called from event
    end
    if idx then
        local videoBridge = component.videoBridge[idx]
        if videoBridge then apply(idx, videoBridge) end
    else
        for index, videoBridge in pairs(component.videoBridge) do if videoBridge then apply(index, videoBridge) end end
    end
    publishNotification()
end

function getVideoBridgePrivacyState(idx)
    idx = idx or 1
    local videoBridge = component.videoBridge[idx]
    if not videoBridge then return end
    local privacyState = safeAccess(videoBridge, "toggle.privacy", "get")
    debugPrint("Video Bridge [" .. idx .. "] Privacy State: " .. tostring(privacyState) .. " (Source: Component)")
    if isArr(control.btnVideoPrivacy) and control.btnVideoPrivacy[idx] then
        setProp(control.btnVideoPrivacy[idx], "Boolean", privacyState)
    elseif control.btnVideoPrivacy and not isArr(control.btnVideoPrivacy) then
        setProp(control.btnVideoPrivacy, "Boolean", privacyState)
    end
end

function getCallSyncMuteState()
    if not component.callSync then return end
    local muteState = safeAccess(component.callSync, "mute", "get")
    debugPrint("Call Sync Mute State: " .. tostring(muteState) .. " (Source: Component)")
    if control.btnAudioPrivacy then setProp(control.btnAudioPrivacy, "Boolean", muteState) end
end

function getCallSyncHookState()
    if not component.callSync then return end
    local offHook = safeAccess(component.callSync, "off.hook", "get")
    getCallSyncMuteState()
    for idx in pairs(component.videoBridge) do setVideoPrivacy(not offHook, idx) end
    if component.videoBridge[1] then getVideoBridgePrivacyState(1) end
    if component.camACPR and component.camACPR["TrackingBypass"] then
        component.camACPR["TrackingBypass"].IsDisabled = not offHook
        safeAccess(component.camACPR, "TrackingBypass", "set", not offHook)
    end
end

function getVolumeLvl(idx)
    local gain = getGainComponent(idx)
    if not gain or not control.knbVolumeFader or not control.knbVolumeFader[idx] then return end
    setProp(control.knbVolumeFader[idx], "Position", safeAccess(gain, "gain", "getPosition"))
    updateVolumeVisuals(idx)
    publishNotification()
end

function getVolumeMute(idx)
    local gain = getGainComponent(idx)
    if not gain or not control.btnVolumeMute or not control.btnVolumeMute[idx] then return end
    setProp(control.btnVolumeMute[idx], "Boolean", safeAccess(gain, "mute", "get"))
    updateVolumeVisuals(idx)
    publishNotification()
end

function powerOn()
    debugPrint("[Power] Powering On (Source: User)")
    if control.btnSystemOnTrig then control.btnSystemOnTrig:Trigger() end
    enablePowerControls(false)
    state.isWarming = true
    setProp(control.ledSystemWarming, "Boolean", true)
    timers.warmup:Start(config.warmupTime or 10)
    setSystemPowerFB(true)
    applyVolumeDefaults()
    setMute(false)
    setAudioPrivacy(true)
    powerDisplays(true)
    publishNotification()
end

function powerOff(sourceTag)
    sourceTag = sourceTag or "User"
    debugPrint("[Power] Powering Off (Source: " .. sourceTag .. ")")
    if control.btnSystemOffTrig then control.btnSystemOffTrig:Trigger() end
    enablePowerControls(false)
    state.isCooling = true
    setProp(control.ledSystemCooling, "Boolean", true)
    timers.cooldown:Start(config.cooldownTime or 5)
    setSystemPowerFB(false)
    setAudioPrivacy(true)
    for idx, gain in pairs(component.gains) do
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

function checkMotion()
    debugPrint("[Motion] Checking Motion")
    if control.ledMotionIn and control.ledMotionIn.Boolean then
        state.motionTimeoutActive = false
        setProp(control.ledMotionTimeoutActive, "Boolean", false)
        timers.motion:Stop()
        if control.ledSystemPower and not control.ledSystemPower.Boolean and not state.motionGraceActive and control.txtMotionMode and control.txtMotionMode.String == "Motion On/Off" then
            debugPrint("[Motion] Turning system on from motion (Source: Motion Sensor)")
            powerOn()
        end
        return
    end
    if control.txtMotionMode and (control.txtMotionMode.String == "Motion On/Off" or control.txtMotionMode.String == "Motion Off") then
        debugPrint("[Motion] Starting Motion Off Timer")
        state.motionTimeoutActive = true
        setProp(control.ledMotionTimeoutActive, "Boolean", true)
        timers.motion:Start((control.motionTimeout and control.motionTimeout.Value) or config.motionTimeout or 300)
    end
end

function getComponentNames()
    local names = { callSync = {}, videoBridge = {}, camACPR = {}, displays = {}, gains = {}, systemMute = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == cfg.componentType.callSync then table.insert(names.callSync, comp.Name)
        elseif comp.Type == cfg.componentType.videoBridge then table.insert(names.videoBridge, comp.Name)
        elseif comp.Type == cfg.componentType.displays then table.insert(names.displays, comp.Name)
        elseif comp.Type == cfg.componentType.gains then table.insert(names.gains, comp.Name)
        elseif comp.Type == cfg.componentType.systemMute then table.insert(names.systemMute, comp.Name)
        elseif comp.Type == cfg.componentType.camACPR then table.insert(names.camACPR, comp.Name) end
    end
    for _, list in pairs(names) do table.sort(list); table.insert(list, clearString) end
    if control.compCallSync then control.compCallSync.Choices = names.callSync end
    forEach(control.compVideoBridge, function(_, ctrl) ctrl.Choices = names.videoBridge end)
    if control.compSystemMute then control.compSystemMute.Choices = names.systemMute end
    if control.compACPR then control.compACPR.Choices = names.camACPR end
    forEach(control.compGains, function(_, ctrl) ctrl.Choices = names.gains end)
    forEach(control.devDisplays, function(_, ctrl) ctrl.Choices = names.displays end)
    debugPrint("Discovery complete: " .. (#names.callSync - 1) .. " callSync, " .. (#names.videoBridge - 1) .. " videoBridge, " .. (#names.gains - 1) .. " gains, " .. (#names.displays - 1) .. " displays")
end

function setCallSyncComponent()
    component.callSync = setComponent(control.compCallSync, "Call Sync")
    local comp = component.callSync
    if not comp then return end
    if comp["off.hook"] then comp["off.hook"].EventHandler = getCallSyncHookState end
    if comp["mute"] then comp["mute"].EventHandler = getCallSyncMuteState end
end

function setVideoBridgeComponent(idx)
    if not control.compVideoBridge or not control.compVideoBridge[idx] then return end
    component.videoBridge[idx] = setComponent(control.compVideoBridge[idx], "Video Bridge [" .. idx .. "]")
    local comp = component.videoBridge[idx]
    if not comp then return end
    if comp["toggle.privacy"] then
        comp["toggle.privacy"].EventHandler = function() getVideoBridgePrivacyState(idx) end
    end
    getVideoBridgePrivacyState(idx)
end

function setGainComponent(idx)
    if not control.compGains or not control.compGains[idx] then return end
    component.gains[idx] = setComponent(control.compGains[idx], "Gain [" .. idx .. "]")
    local comp = component.gains[idx]
    if not comp then return end
    if comp["gain"] then comp["gain"].EventHandler = function() getVolumeLvl(idx) end end
    if comp["mute"] then comp["mute"].EventHandler = function() getVolumeMute(idx) end end
    getVolumeLvl(idx)
    getVolumeMute(idx)
end

function setSystemMuteComponent()
    component.systemMute = setComponent(control.compSystemMute, "System Mute")
end

function setCamACPRComponent()
    component.camACPR = setComponent(control.compACPR, "Camera ACPR")
    local comp = component.camACPR
    if not comp then return end
    if comp["TrackingBypass"] then
        comp["TrackingBypass"].EventHandler = function()
            local cam = component.camACPR
            if not cam or not cam["TrackingBypass"] then return end
            local bypassState = safeAccess(cam, "TrackingBypass", "get")
            debugPrint("ACPR Tracking Bypass: " .. tostring(bypassState) .. " (Source: Component)")
            cam["TrackingBypass"].Legend = cam["TrackingBypass"].IsDisabled and "Disabled" or (bypassState and "Off" or "Auto")
        end
    end
    getCallSyncHookState()
end

function setDisplayComponent(idx)
    if not control.devDisplays or not control.devDisplays[idx] then return end
    component.displays[idx] = setComponent(control.devDisplays[idx], "Display [" .. idx .. "]")
end

function setGainTypeAssignments(roomType)
    roomType = roomType or (control.selDefaultConfigs and control.selDefaultConfigs.String) or "Default"
    local assign = cfg.gainTypeAssignment[roomType] or cfg.gainTypeAssignment["Default"]
    for idx, gainType in ipairs(assign) do
        if control.typeGain and control.typeGain[idx] then
            control.typeGain[idx].String = idx == 1 and "Program" or gainType
            control.typeGain[idx].IsDisabled = idx == 1
        end
    end
end

function setupConfigSelection()
    if not control.selDefaultConfigs then return end
    control.selDefaultConfigs.Choices = { "Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined" }
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
            local ctrl = control[map.control]
            if ctrl and ctrl.Value ~= nil then
                ctrl.Value = conf[map.config]
                ctrl.IsDisabled = not isUser
            end
        end
    end
    bind(control.selDefaultConfigs, function(ctl)
        updateValues(ctl.String)
        setGainTypeAssignments(ctl.String)
        applyVolumeDefaults()
    end)
    for _, map in ipairs(maps) do
        local ctrl = control[map.control]
        if ctrl then
            bind(ctrl, function(value)
                if control.selDefaultConfigs and control.selDefaultConfigs.String == "User Defined" then
                    defaultConfigs["User Defined"][map.config] = value.Value
                end
            end)
        end
    end
    control.selDefaultConfigs.String = "Default"
    updateValues("Default")
end

function setFireAlarm(alarmState)
    if alarmState then
        setSystemMute(true)
        powerDisplays(false)
        return
    end
    if control.ledSystemPower and control.ledSystemPower.Boolean then
        setSystemMute(false)
        powerDisplays(true)
    end
end

-------------------[ Events ]-------------------
function registerEvents()
    local btnCount, arrayCount = 0, 0
    if bind(control.btnSystemOnOff, function(ctl) if ctl.Boolean then powerOn() else powerOff() end end) then btnCount = btnCount + 1 end
    if bind(control.btnSystemOn, powerOn) then btnCount = btnCount + 1 end
    if bind(control.btnSystemOff, function()
        powerOff()
        state.motionGraceActive = true
        setProp(control.ledMotionGraceActive, "Boolean", true)
        timers.grace:Start(config.gracePeriod or 30)
    end) then btnCount = btnCount + 1 end
    if bind(control.btnAudioPrivacy, function(ctl) setAudioPrivacy(ctl.Boolean) end) then btnCount = btnCount + 1 end
    if bind(control.roomName, function()
        roomName = "[" .. (control.roomName.String or "Unknown") .. "]"
        debugPrint("Room name updated to: " .. roomName)
        publishNotification()
    end) then btnCount = btnCount + 1 end
    if bind(control.ledMotionIn, checkMotion) then btnCount = btnCount + 1 end
    if bind(control.compCallSync, setCallSyncComponent) then btnCount = btnCount + 1 end
    if bind(control.compSystemMute, setSystemMuteComponent) then btnCount = btnCount + 1 end
    if bind(control.compACPR, setCamACPRComponent) then btnCount = btnCount + 1 end

    arrayCount = arrayCount + bindArray(control.btnVideoPrivacy, function(idx, ctl) setVideoPrivacy(ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(control.knbVolumeFader, function(idx, ctl) setVolume(ctl.Position, idx) end)
    arrayCount = arrayCount + bindArray(control.btnVolumeMute, function(idx, ctl) setMute(ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(control.btnVolumeUp, function(idx, ctl) setVolumeUpDown("up", ctl.Boolean, idx) end)
    arrayCount = arrayCount + bindArray(control.btnVolumeDn, function(idx, ctl) setVolumeUpDown("down", ctl.Boolean, idx) end)

    forEach(control.compVideoBridge, function(idx, ctrl) bind(ctrl, function() setVideoBridgeComponent(idx) end) end)
    forEach(control.compGains, function(idx, ctrl) bind(ctrl, function() setGainComponent(idx) end) end)
    forEach(control.devDisplays, function(idx, ctrl) bind(ctrl, function() setDisplayComponent(idx) end) end)

    forEach(control.typeGain, function(i, ctrl)
        if i > 1 then
            bind(ctrl, function(gainCtl)
                if component.gains[i] then
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
function init()
    debugPrint("=== Initialization Started ===")
    roomName = "[" .. (control.roomName.String or "Unknown") .. "]"
    debugPrint("Configuration: ROOM_NAME=" .. roomName .. ", debugging=" .. tostring(config.debugging ~= false))

    enablePowerControls(true)
    getComponentNames()
    if control.txtMotionMode then control.txtMotionMode.Choices = { "Motion On/Off", "Motion Off", "Motion Disabled" } end
    forEach(control.typeGain, function(_, ctrl) ctrl.Choices = { "Mic", "Gain" } end)
    setGainTypeAssignments()
    setCallSyncComponent()
    setSystemMuteComponent()
    setCamACPRComponent()
    forEach(control.compVideoBridge, function(idx) setVideoBridgeComponent(idx) end)
    forEach(control.compGains, function(idx) setGainComponent(idx) end)
    forEach(control.devDisplays, function(idx) setDisplayComponent(idx) end)

    timers.motion.EventHandler = function()
        state.motionTimeoutActive = false
        setProp(control.ledMotionTimeoutActive, "Boolean", false)
        powerOff("Motion timeout")
    end
    timers.grace.EventHandler = function()
        state.motionGraceActive = false
        setProp(control.ledMotionGraceActive, "Boolean", false)
    end
    timers.warmup.EventHandler = function()
        state.isWarming = false
        setProp(control.ledSystemWarming, "Boolean", false)
        enablePowerControls(true)
        publishNotification()
    end
    timers.cooldown.EventHandler = function()
        state.isCooling = false
        setProp(control.ledSystemCooling, "Boolean", false)
        enablePowerControls(true)
        publishNotification()
    end

    powerOff("Initialization")

    debugPrint("Ready - " .. getGainCount() .. " gain controls detected")
    debugPrint("=== Initialization Complete ===")
end

-------------------[ Factory ]-------------------
function getDefaultConfig(roomType)
    local base = { defaultProgramVolume = 0.7, defaultMicVolume = 0.5, defaultGainVolume = 0.7 }
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = (control.warmupTime and control.warmupTime.Value) or 10,
            cooldownTime = (control.cooldownTime and control.cooldownTime.Value) or 5,
            motionTimeout = (control.motionTimeout and control.motionTimeout.Value) or 300,
            gracePeriod = (control.motionGracePeriod and control.motionGracePeriod.Value) or 30,
            defaultProgramVolume = (control.defaultProgramVolume and control.defaultProgramVolume.Value) or base.defaultProgramVolume,
            defaultMicVolume = (control.defaultMicVolume and control.defaultMicVolume.Value) or base.defaultMicVolume,
            defaultGainVolume = (control.defaultGainVolume and control.defaultGainVolume.Value) or base.defaultGainVolume,
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
ok, err = pcall(function()
    print("Initializing SystemAutomationController...")
    if not validateControls() then error("Control validation failed") end
    local configType = control.selDefaultConfigs and control.selDefaultConfigs.String or "Default"
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
    if control and control.txtStatus then
        control.txtStatus.String = "INIT FAILED"
        control.txtStatus.Value = 2
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
