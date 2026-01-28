--[[
  System Automation Controller - Q-SYS Control Script
  Manages power, audio, video, displays, and motion detection
]]

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

local function validateControls()
    for _, name in ipairs({"roomName", "txtStatus", "btnSystemOnOff", "ledSystemPower", 
                           "warmupTime", "cooldownTime", "motionTimeout", "motionGracePeriod",
                           "defaultProgramVolume", "defaultMicVolume", "defaultGainVolume"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

local function normalizeControlArrays()
    -- Normalize all array controls to consistent structures
    local arrayControls = {
        'compVideoBridge', 'compGains', 'devDisplays', 'typeGain', 
        'btnVideoPrivacy', 'knbVolumeFader', 'btnVolumeMute', 
        'btnVolumeUp', 'btnVolumeDn'
    }
    
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then
            -- Convert single control to array format
            controls[controlName] = { ctrl }
        end
    end
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end  -- Guard against redundant assignments
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do bind(ctrl, function(ctl) handler(i, ctl) end) end
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

-------------------[ Controller ]-------------------
SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController
SystemAutomationController.clearString = "[Clear]"
SystemAutomationController.componentTypes = {
    callSync = "call_sync", videoBridge = "usb_uvc",
    displays = "%PLUGIN%_404F4311-A38D-4891-AF61-709B8F48A6E1_%FP%_77008e895ac50ad1242e3dee981c5e4a",
    gains = "gain", systemMute = "system_mute",
    camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355"
}

function SystemAutomationController.new(roomName, config, defaultConfigs)
    local self = setmetatable({}, SystemAutomationController)
    self.roomName = roomName or "Default Room"
    self.debugging = config.debugging ~= false
    self.defaultConfigs = defaultConfigs
    self.state = { isWarming = false, isCooling = false, powerLocked = false, motionTimeoutActive = false, motionGraceActive = false }
    self.config = config
    self.components = { callSync = nil, videoBridge = {}, displays = {}, gains = {}, systemMute = nil, camACPR = nil, invalid = {} }
    self.timers = { motion = Timer.New(), grace = Timer.New(), warmup = Timer.New(), cooldown = Timer.New() }
    self:registerTimers()
    return self
end

function SystemAutomationController:debugPrint(str)
    if self.debugging then print("["..self.roomName.."] "..str) end
end

function SystemAutomationController:getGainComponent(idx) return self.components.gains[idx] end
function SystemAutomationController:getDisplayComponent(idx) return self.components.displays[idx] end
function SystemAutomationController:getGainType(idx)
    if controls.typeGain[idx] then return controls.typeGain[idx].String end
    return idx == 1 and "Program" or "Mic"
end

function SystemAutomationController:safeAccess(component, control, action, value)
    if not component or not component[control] then return false end
    local success, result = pcall(function()
        if action == "set" then component[control].Boolean = value; return true
        elseif action == "setPosition" then component[control].Position = value; return true
        elseif action == "setString" then component[control].String = value; return true
        elseif action == "trigger" then component[control]:Trigger(); return true
        elseif action == "get" then return component[control].Boolean
        elseif action == "getPosition" then return component[control].Position
        elseif action == "getString" then return component[control].String end
        return false
    end)
    return success and result or false
end

-------------------[ Audio Methods ]-------------------
function SystemAutomationController:setVolume(level, gainIndex)
    local update = function(i, gain)
        self:safeAccess(gain, "gain", "setPosition", level)
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self:getGainComponent(gainIndex)
        if gain then update(gainIndex, gain) end
    else
        for i, gain in pairs(self.components.gains) do if gain then update(i, gain) end end
    end
    self:publishNotification()
end

function SystemAutomationController:setMute(state, gainIndex)
    local mute = function(i, gain)
        self:safeAccess(gain, "mute", "set", state)
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self:getGainComponent(gainIndex)
        if gain then mute(gainIndex, gain) end
    else
        for i, gain in pairs(self.components.gains) do if gain then mute(i, gain) end end
    end
    self:publishNotification()
end

function SystemAutomationController:setAudioPrivacy(state)
    self:safeAccess(self.components.callSync, "mute", "set", state)
    setProp(controls.btnAudioPrivacy, "Boolean", state)
    setProp(controls.btnAudioPrivacy, "CssClass", state and "icon-mic_none" or "icon-mic_off")
    self:publishNotification()
end

function SystemAutomationController:setSystemMute(state)
    if self.components.systemMute then self:safeAccess(self.components.systemMute, "mute", "set", state) end
end

function SystemAutomationController:setVolumeUpDown(direction, state, gainIndex)
    local action = direction == "up" and "stepper.increase" or "stepper.decrease"
    local step = function(i, gain)
        self:safeAccess(gain, action, "set", state)
        if state then self:safeAccess(gain, "mute", "set", false) end
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self:getGainComponent(gainIndex)
        if gain then step(gainIndex, gain) end
    else
        for i, gain in pairs(self.components.gains) do if gain then step(i, gain) end end
    end
    self:publishNotification()
end

function SystemAutomationController:getGainLevel(i)
    local gain = self:getGainComponent(i)
    return gain and self:safeAccess(gain, "gain", "getPosition") or 0
end

function SystemAutomationController:getGainMute(i)
    local gain = self:getGainComponent(i)
    return gain and self:safeAccess(gain, "mute", "get") or false
end

function SystemAutomationController:getGainCount()
    local count = 0
    for _ in pairs(self.components.gains) do count = count + 1 end
    return count
end

function SystemAutomationController:updateVolumeVisuals(i)
    local fader = controls.knbVolumeFader and controls.knbVolumeFader[i]
    local mute = controls.btnVolumeMute and controls.btnVolumeMute[i]
    if not fader or not mute then return end
    local isMuted = mute.Boolean
    local gainType = self:getGainType(i)
    setProp(mute, "CssClass", isMuted and (gainType == "Mic" and "icon-mic_none" or "icon-volume_mute") or (gainType == "Mic" and "icon-mic_off" or "icon-volume_off"))
    setProp(fader, "Color", isMuted and "#CCCCCC" or "#0561A5")
end

-------------------[ Video Methods ]-------------------
function SystemAutomationController:setVideoPrivacy(state, idx)
    local apply = function(i, videoBridge)
        self:safeAccess(videoBridge, "toggle.privacy", "set", state)
        self:videoBridgeCheckPrivacy(i)
    end
    if idx then
        local videoBridge = self.components.videoBridge[idx]
        if videoBridge then apply(idx, videoBridge) end
    else
        for i, videoBridge in pairs(self.components.videoBridge) do if videoBridge then apply(i, videoBridge) end end
    end
    self:publishNotification()
end

function SystemAutomationController:getVideoPrivacy(idx)
    idx = idx or 1
    local videoBridge = self.components.videoBridge[idx]
    if not videoBridge then return false end
    local state = self:safeAccess(videoBridge, "toggle.privacy", "get")
    self:videoBridgeCheckPrivacy(idx)
    self:publishNotification()
    return state
end

-------------------[ Display Methods ]-------------------
function SystemAutomationController:powerDisplays(state)
    local control = state and "PowerOn" or "PowerOff"
    for _, display in pairs(self.components.displays) do
        if display then self:safeAccess(display, control, "trigger") end
    end
end

function SystemAutomationController:powerDisplay(idx, state)
    local display = self:getDisplayComponent(idx)
    if display then self:safeAccess(display, state and "PowerOn" or "PowerOff", "trigger") end
end

-------------------[ Power Methods ]-------------------
function SystemAutomationController:enablePowerControls(state)
    for _, btn in ipairs({controls.btnSystemOnOff, controls.btnSystemOn, controls.btnSystemOff}) do
        setProp(btn, "IsDisabled", not state)
    end
end

function SystemAutomationController:setSystemPowerFB(state)
    setProp(controls.ledSystemPower, "Boolean", state)
    setProp(controls.btnSystemOnOff, "Boolean", state)
    setProp(controls.btnSystemOn, "Boolean", state)
    setProp(controls.btnSystemOff, "Boolean", not state)
end

function SystemAutomationController:powerOn()
    controls.btnSystemOnTrig:Trigger()
    self:enablePowerControls(false)
    self.state.isWarming = true
    setProp(controls.ledSystemWarming, "Boolean", true)
    self.timers.warmup:Start(self.config.warmupTime)
    self:setSystemPowerFB(true)
    self:applyVolumeDefaults()
    self:setMute(false)
    self:setAudioPrivacy(true)
    self:powerDisplays(true)
    self:publishNotification()
end

function SystemAutomationController:powerOff()
    controls.btnSystemOffTrig:Trigger()
    self:enablePowerControls(false)
    self.state.isCooling = true
    setProp(controls.ledSystemCooling, "Boolean", true)
    self.timers.cooldown:Start(self.config.cooldownTime)
    self:setSystemPowerFB(false)
    self:setAudioPrivacy(true)
    for i, gain in pairs(self.components.gains) do
        if gain then
            local gainType = self:getGainType(i)
            if gainType ~= "micVolume" and gainType ~= "Mic" then
                self:setMute(true, i)
            end
        end
    end
    self:setVideoPrivacy(true)
    self:powerDisplays(false)
    self:endCalls()
    self:publishNotification()
end

-------------------[ Motion Methods ]-------------------
function SystemAutomationController:checkMotion()
    if controls.ledMotionIn.Boolean then
        self.state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        self.timers.motion:Stop()
        if not controls.ledSystemPower.Boolean and not self.state.motionGraceActive and controls.txtMotionMode.String == "Motion On/Off" then
            self:debugPrint("Turning system on from motion")
            self:powerOn()
        end
        return
    end
    if controls.txtMotionMode.String == "Motion On/Off" or controls.txtMotionMode.String == "Motion Off" then
        self.state.motionTimeoutActive = true
        setProp(controls.ledMotionTimeoutActive, "Boolean", true)
        self.timers.motion:Start(controls.motionTimeout.Value or self.config.motionTimeout)
    end
end

-------------------[ Event Registration ]-------------------
function SystemAutomationController:registerEvents()
    bind(controls.btnSystemOnOff, function(c) if c.Boolean then self:powerOn() else self:powerOff() end end)
    bind(controls.btnSystemOn, function() self:powerOn() end)
    bind(controls.btnSystemOff, function()
        self:powerOff()
        self.state.motionGraceActive = true
        setProp(controls.ledMotionGraceActive, "Boolean", true)
        self.timers.grace:Start(self.config.gracePeriod)
    end)
    bind(controls.btnAudioPrivacy, function(c) self:setAudioPrivacy(c.Boolean) end)
    bind(controls.roomName, function()
        self.roomName = "["..controls.roomName.String.."]"
        self:publishNotification()
    end)
    bind(controls.ledMotionIn, function() self:checkMotion() end)
    bind(controls.compCallSync, function() self:setCallSyncComponent() end)
    bind(controls.compSystemMute, function() self:setSystemMuteComponent() end)
    bind(controls.compACPR, function() self:setCamACPRComponent() end)
    
    bindArray(controls.btnVideoPrivacy, function(i, c) self:setVideoPrivacy(c.Boolean, i) end)
    bindArray(controls.knbVolumeFader, function(i, c) self:setVolume(c.Position, i) end)
    bindArray(controls.btnVolumeMute, function(i, c) self:setMute(c.Boolean, i) end)
    bindArray(controls.btnVolumeUp, function(i, c) self:setVolumeUpDown("up", c.Boolean, i) end)
    bindArray(controls.btnVolumeDn, function(i, c) self:setVolumeUpDown("down", c.Boolean, i) end)
    
    forEach(controls.compVideoBridge, function(i, c) bind(c, function() self:setVideoBridgeComponent(i) end) end)
    forEach(controls.compGains, function(i, c) bind(c, function() self:setGainComponent(i) end) end)
    forEach(controls.devDisplays, function(i, c) bind(c, function() self:setDisplayComponent(i) end) end)
    
    forEach(controls.typeGain, function(i, c)
        if i > 1 then
            bind(c, function(ctl)
                if self.components.gains[i] then
                    self:setVolume(self:getDefaultVolumeForType(ctl.String), i)
                end
                self:publishNotification()
            end)
        end
    end)
end

function SystemAutomationController:registerTimers()
    self.timers.motion.EventHandler = function()
        self.state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        self:powerOff()
    end
    self.timers.grace.EventHandler = function()
        self.state.motionGraceActive = false
        setProp(controls.ledMotionGraceActive, "Boolean", false)
    end
    self.timers.warmup.EventHandler = function()
        self.state.isWarming = false
        setProp(controls.ledSystemWarming, "Boolean", false)
        self:enablePowerControls(true)
        self:publishNotification()
    end
    self.timers.cooldown.EventHandler = function()
        self.state.isCooling = false
        setProp(controls.ledSystemCooling, "Boolean", false)
        self:enablePowerControls(true)
        self:publishNotification()
    end
end

-------------------[ Component Discovery ]-------------------
function SystemAutomationController:getComponentNames()
    local ct = SystemAutomationController.componentTypes
    local names = { callSync = {}, videoBridge = {}, camACPR = {}, displays = {}, gains = {}, systemMute = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == ct.callSync then table.insert(names.callSync, comp.Name)
        elseif comp.Type == ct.videoBridge then table.insert(names.videoBridge, comp.Name)
        elseif comp.Type == ct.displays then table.insert(names.displays, comp.Name)
        elseif comp.Type == ct.gains then table.insert(names.gains, comp.Name)
        elseif comp.Type == ct.systemMute then table.insert(names.systemMute, comp.Name)
        elseif comp.Type == ct.camACPR then table.insert(names.camACPR, comp.Name) end
    end
    for _, list in pairs(names) do table.sort(list); table.insert(list, self.clearString) end
    controls.compCallSync.Choices = names.callSync
    forEach(controls.compVideoBridge, function(i, c) c.Choices = names.videoBridge end)
    controls.compSystemMute.Choices = names.systemMute
    controls.compACPR.Choices = names.camACPR
    forEach(controls.compGains, function(i, c) c.Choices = names.gains end)
    forEach(controls.devDisplays, function(i, c) c.Choices = names.displays end)
end

-------------------[ Component Validation ]-------------------
function SystemAutomationController:setComponent(ctrl, componentType)
    if not ctrl or not ctrl.String or ctrl.String == "" or ctrl.String == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self.components.invalid[componentType] = false
        self:checkStatus()
        return nil
    end
    local comp = Component.New(ctrl.String)
    if #Component.GetControls(comp) < 1 then
        ctrl.String = "[Invalid]"
        ctrl.Color = "pink"
        self.components.invalid[componentType] = true
        self:checkStatus()
        return nil
    end
    ctrl.Color = "white"
    self.components.invalid[componentType] = false
    self:checkStatus()
    return comp
end

function SystemAutomationController:checkStatus()
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid then
            controls.txtStatus.String = "Invalid Components"
            controls.txtStatus.Value = 1
            return
        end
    end
    controls.txtStatus.String = "OK"
    controls.txtStatus.Value = 0
end

-------------------[ Component Setup ]-------------------
function SystemAutomationController:setCallSyncComponent()
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    local comp = self.components.callSync
    if not comp then return end
    if comp["off.hook"] then comp["off.hook"].EventHandler = function() self:callSyncCheckConnection() end end
    if comp["mute"] then comp["mute"].EventHandler = function() self:callSyncCheckMute() end end
end

function SystemAutomationController:setVideoBridgeComponent(idx)
    if not controls.compVideoBridge[idx] then return end
    self.components.videoBridge[idx] = self:setComponent(controls.compVideoBridge[idx], "Video Bridge ["..idx.."]")
    local comp = self.components.videoBridge[idx]
    if not comp then return end
    if comp["toggle.privacy"] then comp["toggle.privacy"].EventHandler = function() self:videoBridgeCheckPrivacy(idx) end end
    self:videoBridgeCheckPrivacy(idx)
end

function SystemAutomationController:setGainComponent(idx)
    if not controls.compGains[idx] then return end
    self.components.gains[idx] = self:setComponent(controls.compGains[idx], "Gain ["..idx.."]")
    local comp = self.components.gains[idx]
    if not comp then return end
    if comp["gain"] then comp["gain"].EventHandler = function() self:getVolumeLvl(idx) end end
    if comp["mute"] then comp["mute"].EventHandler = function() self:getVolumeMute(idx) end end
    self:getVolumeLvl(idx)
    self:getVolumeMute(idx)
end

function SystemAutomationController:setSystemMuteComponent()
    self.components.systemMute = self:setComponent(controls.compSystemMute, "System Mute")
end

function SystemAutomationController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(controls.compACPR, "Camera ACPR")
    local comp = self.components.camACPR
    if not comp then return end
    if comp["TrackingBypass"] then comp["TrackingBypass"].EventHandler = function() self:updateACPRTrackingBypass() end end
    self:callSyncCheckConnection()
end

function SystemAutomationController:setDisplayComponent(idx)
    if not controls.devDisplays[idx] then return end
    self.components.displays[idx] = self:setComponent(controls.devDisplays[idx], "Display ["..idx.."]")
end

-------------------[ Call Sync / Video Bridge Helpers ]-------------------
function SystemAutomationController:callSyncCheckMute()
    if not self.components.callSync then return end
    local state = self:safeAccess(self.components.callSync, "mute", "get")
    if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
end

function SystemAutomationController:videoBridgeCheckPrivacy(idx)
    idx = idx or 1
    local videoBridge = self.components.videoBridge[idx]
    if not videoBridge then return end
    local state = self:safeAccess(videoBridge, "toggle.privacy", "get")
    if isArr(controls.btnVideoPrivacy) and controls.btnVideoPrivacy[idx] then
        controls.btnVideoPrivacy[idx].Boolean = state
    elseif not isArr(controls.btnVideoPrivacy) then
        controls.btnVideoPrivacy.Boolean = state
    end
end

function SystemAutomationController:callSyncCheckConnection()
    local callSync = self.components.callSync
    if not callSync then return end
    local state = self:safeAccess(callSync, "off.hook", "get")
    self:callSyncCheckMute()
    if self.components.videoBridge then
        for i in pairs(self.components.videoBridge) do self:setVideoPrivacy(not state, i) end
        self:videoBridgeCheckPrivacy(1)
    end
    if self.components.camACPR and self.components.camACPR["TrackingBypass"] then
        self.components.camACPR["TrackingBypass"].IsDisabled = not state
        self:safeAccess(self.components.camACPR, "TrackingBypass", "set", not state)
    end
end

function SystemAutomationController:getVolumeLvl(idx)
    local gain = self:getGainComponent(idx)
    if not gain then return end
    controls.knbVolumeFader[idx].Position = self:safeAccess(gain, "gain", "getPosition")
    self:updateVolumeVisuals(idx)
    self:publishNotification()
end

function SystemAutomationController:getVolumeMute(idx)
    local gain = self:getGainComponent(idx)
    if not gain then return end
    controls.btnVolumeMute[idx].Boolean = self:safeAccess(gain, "mute", "get")
    self:updateVolumeVisuals(idx)
    self:publishNotification()
end

function SystemAutomationController:updateACPRTrackingBypass()
    local camACPR = self.components.camACPR
    if not camACPR or not camACPR["TrackingBypass"] then return end
    local state = self:safeAccess(camACPR, "TrackingBypass", "get")
    camACPR["TrackingBypass"].Legend = camACPR["TrackingBypass"].IsDisabled and "Disabled" or (state and "Off" or "Auto")
end

function SystemAutomationController:endCalls()
    if self.components.callSync then self:safeAccess(self.components.callSync, "call.decline", "trigger") end
end

function SystemAutomationController:getDefaultVolumeForType(type)
    local defaults = { Program = self.config.defaultProgramVolume, Mic = self.config.defaultMicVolume, Gain = self.config.defaultGainVolume }
    return defaults[type] or self.config.defaultMicVolume
end

function SystemAutomationController:setFireAlarm(state)
    if state then
        self:setSystemMute(true)
        self:powerDisplays(false)
        return
    end
    if controls.ledSystemPower.Boolean then
        self:setSystemMute(false)
        self:powerDisplays(true)
    end
end

function SystemAutomationController:applyVolumeDefaults()
    for i, gain in pairs(self.components.gains) do
        if gain then self:setVolume(self:getDefaultVolumeForType(self:getGainType(i)), i) end
    end
end

function SystemAutomationController:publishNotification()
    if not controls.txtNotificationID or controls.txtNotificationID.String == "" then return end
    local systemState = {
        RoomName = self.roomName,
        PowerState = controls.ledSystemPower.Boolean or false,
        SystemWarming = controls.ledSystemWarming.Boolean or false,
        SystemCooling = controls.ledSystemCooling.Boolean or false,
        AudioPrivacy = controls.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = controls.btnVideoPrivacy.Boolean or false,
        ACPRState = (self.components.camACPR and self.components.camACPR["TrackingBypass"] and self.components.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time(),
        GainControls = {}
    }
    for i, gain in pairs(self.components.gains) do
        if gain then systemState.GainControls[i] = { Level = self:getGainLevel(i), Muted = self:getGainMute(i) } end
    end
    Notifications.Publish(controls.txtNotificationID.String, systemState)
end

-------------------[ Config Selection ]-------------------
function SystemAutomationController:setupConfigSelection()
    controls.selDefaultConfigs.Choices = { "Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined" }
    local maps = {
        { c = "warmupTime", k = "warmupTime" },
        { c = "cooldownTime", k = "cooldownTime" },
        { c = "motionTimeout", k = "motionTimeout" },
        { c = "motionGracePeriod", k = "gracePeriod" },
        { c = "defaultProgramVolume", k = "defaultProgramVolume" },
        { c = "defaultMicVolume", k = "defaultMicVolume" },
        { c = "defaultGainVolume", k = "defaultGainVolume" }
    }
    local function updateValues(configType)
        local conf = self.defaultConfigs[configType]
        if not conf then return end
        local isUser = configType == "User Defined"
        for _, m in ipairs(maps) do
            local ctl = controls[m.c]
            if ctl then ctl.Value = conf[m.k]; ctl.IsDisabled = not isUser end
        end
    end
    controls.selDefaultConfigs.EventHandler = function(c)
        updateValues(c.String)
        self:setGainTypeAssignments(c.String)
        self:applyVolumeDefaults()
    end
    for _, m in ipairs(maps) do
        local ctl = controls[m.c]
        if ctl then
            ctl.EventHandler = function(v)
                if controls.selDefaultConfigs.String == "User Defined" then
                    self.defaultConfigs["User Defined"][m.k] = v.Value
                end
            end
        end
    end
    controls.selDefaultConfigs.String = "Default"
    updateValues("Default")
end

function SystemAutomationController:setGainTypeAssignments(roomType)
    roomType = roomType or (controls.selDefaultConfigs and controls.selDefaultConfigs.String) or "Default"
    local assignments = {
        ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
        ["Huddle Room"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
        ["Custom Room"] = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
        ["Default"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" }
    }
    local assign = assignments[roomType] or assignments["Default"]
    for i, gainType in ipairs(assign) do
        controls.typeGain[i].String = i == 1 and "Program" or gainType
        controls.typeGain[i].IsDisabled = i == 1
    end
end

-------------------[ Initialization ]-------------------
function SystemAutomationController:init()
    self:enablePowerControls(true)
    self:getComponentNames()
    controls.txtMotionMode.Choices = { "Motion On/Off", "Motion Off", "Motion Disabled" }
    forEach(controls.typeGain, function(i, c) c.Choices = { "Program", "Mic", "Gain" } end)
    self:setGainTypeAssignments()
    self:setCallSyncComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    forEach(controls.compVideoBridge, function(i) self:setVideoBridgeComponent(i) end)
    forEach(controls.compGains, function(i) self:setGainComponent(i) end)
    forEach(controls.devDisplays, function(i) self:setDisplayComponent(i) end)
    self:debugPrint("Ready - " .. self:getGainCount() .. " gain controls detected")
end

-------------------[ Factory & Configuration ]-------------------
local function getDefaultConfig(roomType)
    local base = { defaultProgramVolume = 0.7, defaultMicVolume = 0.5, defaultGainVolume = 0.7 }
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = controls.warmupTime.Value or 10,
            cooldownTime = controls.cooldownTime.Value or 5,
            motionTimeout = controls.motionTimeout.Value or 300,
            gracePeriod = controls.motionGracePeriod.Value or 30,
            defaultProgramVolume = controls.defaultProgramVolume.Value or base.defaultProgramVolume,
            defaultMicVolume = controls.defaultMicVolume.Value or base.defaultMicVolume,
            defaultGainVolume = controls.defaultGainVolume.Value or base.defaultGainVolume
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

local function createSystemController(roomName, roomType)
    if not roomName or roomName == "" then print("ERROR: Invalid room name"); return nil end
    roomType = roomType or "Default"
    local config = getDefaultConfig(roomType)
    local allConfigs = {
        ["Conference Room"] = getDefaultConfig("Conference Room"),
        ["Huddle Room"] = getDefaultConfig("Huddle Room"),
        ["Default"] = getDefaultConfig("Default"),
        ["Custom Room"] = getDefaultConfig("Custom Room"),
        ["User Defined"] = getDefaultConfig("User Defined")
    }
    local success, controller = pcall(function()
        local obj = SystemAutomationController.new(roomName, config, allConfigs)
        if not obj then error("Controller creation failed") end
        normalizeControlArrays()
        obj:registerEvents()
        obj:setupConfigSelection()
        obj:init()
        return obj
    end)
    if success then
        print("SystemAutomationController initialized for " .. roomName)
        _G.mySystemController = controller
        return controller
    else
        print("ERROR: " .. tostring(controller))
        return nil
    end
end

if not validateControls() then return end
local roomName = "[".. (controls.roomName.String or "Unknown") .."]"
local configType = controls.selDefaultConfigs and controls.selDefaultConfigs.String or "Default"
mySystemController = createSystemController(roomName, configType)