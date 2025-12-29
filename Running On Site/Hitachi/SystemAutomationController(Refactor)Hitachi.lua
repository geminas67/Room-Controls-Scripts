--[[
    System Automation Controller (Refactored, Hybrid OOP/Functional Architecture)
    Author: Nikolas Smith, Q-SYS
    Version: 4.0 | Date: 2025-01-XX
    Firmware Req: 10.0.0
    
    Architecture Improvements (v4.0):
    - TimerModule: Dedicated module for all timer management and lifecycle
    - PowerStateMachine: Explicit state machine for power transitions (idle → warming → ready → cooling)
    - ComponentRegistry: Separate class for component discovery, validation, and lifecycle management
    
    Core Features:
    - Hybrid OOP/Functional: OOP for stateful modules, timers, and components; Functional for utilities
    - Enhanced validation: Comprehensive control validation with descriptive error messages
    - Array normalization: Automatic conversion of single controls to array format
    - Optimized event registration: Batch event registration using handler maps
    - Enhanced BaseModule: Improved module pattern with initialization and cleanup
    - Factory functions: Comprehensive error handling with graceful degradation
    - Property access optimization: Cached references and redundancy prevention
    - All event registration is DRY and centralized using control/event maps
    - Each logical domain is its own module; orchestrator is thin
    - Debug/config standardized, all validation centralized
]]

-------------------[ Control References ]-------------------
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
    local required = {
        -- Core required controls
        roomName = controls.roomName,
        txtStatus = controls.txtStatus,
        btnSystemOnOff = controls.btnSystemOnOff,
        ledSystemPower = controls.ledSystemPower,
        -- Essential timers and state controls
        warmupTime = controls.warmupTime,
        cooldownTime = controls.cooldownTime,
        motionTimeout = controls.motionTimeout,
        motionGracePeriod = controls.motionGracePeriod,
        -- Volume defaults
        defaultProgramVolume = controls.defaultProgramVolume,
        defaultMicVolume = controls.defaultMicVolume,
        defaultGainVolume = controls.defaultGainVolume
    }
    
    local missing = {}
    for name, control in pairs(required) do
        if not control then 
            table.insert(missing, name) 
        end
    end

    if #missing > 0 then
        print("ERROR: SystemAutomationController missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end

    return true
end

-------------------[ Utility Functions ]-------------------
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

-- DRY utility: Clean up event handlers from old component before assigning new one
-- Usage: cleanupComponentHandlers(oldComponent, eventMap, debugCallback)
-- eventMap: table of event names (keys) and handlers (values) that were registered
-- Returns: number of handlers cleaned up
local function cleanupComponentHandlers(oldComponent, eventMap, debugCallback)
    if not oldComponent or not eventMap then return 0 end
    local cleaned = 0
    for event, _ in pairs(eventMap) do
        if oldComponent[event] then
            oldComponent[event].EventHandler = nil
            cleaned = cleaned + 1
        end
    end
    if debugCallback and cleaned > 0 then
        debugCallback("Cleaned up " .. cleaned .. " event handler(s) from old component")
    end
    return cleaned
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do bind(ctrl, function(ctl) handler(i, ctl) end) end
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

-------------------[ Base Module Class ]------------------
local BaseModule = {}; BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    self.initialized = false
    return self
end

function BaseModule:debug(msg)
    if self.controller and self.controller.debugPrint then
        self.controller:debugPrint("[" .. self.name .. "] " .. msg)
    end
end

function BaseModule:safeAccess(component, control, action, value)
    return self.controller:safeComponentAccess(component, control, action, value)
end

function BaseModule:init()
    self.initialized = true
    self:debug("Module initialized")
end

function BaseModule:cleanup() 
    self.initialized = false
    self:debug("Cleanup complete") 
end

-------------------[ Power State Machine ]------------------
local PowerStateMachine = setmetatable({}, BaseModule)
PowerStateMachine.__index = PowerStateMachine

PowerStateMachine.States = {
    IDLE = "idle",
    WARMING = "warming",
    READY = "ready",
    COOLING = "cooling"
}

function PowerStateMachine.new(controller)
    local self = BaseModule.new(controller, "PowerStateMachine")
    setmetatable(self, PowerStateMachine)
    self.currentState = PowerStateMachine.States.IDLE
    self:init()
    return self
end

function PowerStateMachine:transitionTo(newState)
    if self.currentState == newState then return end
    
    local oldState = self.currentState
    self.currentState = newState
    self:debug("State transition: " .. oldState .. " → " .. newState)
    
    -- Execute state entry actions
    if newState == PowerStateMachine.States.WARMING then
        self:onEnterWarming()
    elseif newState == PowerStateMachine.States.READY then
        self:onEnterReady()
    elseif newState == PowerStateMachine.States.COOLING then
        self:onEnterCooling()
    elseif newState == PowerStateMachine.States.IDLE then
        self:onEnterIdle()
    end
    
    self.controller:publishNotification()
end

function PowerStateMachine:onEnterWarming()
    setProp(controls.ledSystemWarming, "Boolean", true)
    setProp(controls.ledSystemCooling, "Boolean", false)
end

function PowerStateMachine:onEnterReady()
    setProp(controls.ledSystemWarming, "Boolean", false)
    setProp(controls.ledSystemCooling, "Boolean", false)
end

function PowerStateMachine:onEnterCooling()
    setProp(controls.ledSystemWarming, "Boolean", false)
    setProp(controls.ledSystemCooling, "Boolean", true)
end

function PowerStateMachine:onEnterIdle()
    setProp(controls.ledSystemWarming, "Boolean", false)
    setProp(controls.ledSystemCooling, "Boolean", false)
end

function PowerStateMachine:isWarming()
    return self.currentState == PowerStateMachine.States.WARMING
end

function PowerStateMachine:isCooling()
    return self.currentState == PowerStateMachine.States.COOLING
end

function PowerStateMachine:isReady()
    return self.currentState == PowerStateMachine.States.READY
end

function PowerStateMachine:isIdle()
    return self.currentState == PowerStateMachine.States.IDLE
end

function PowerStateMachine:getCurrentState()
    return self.currentState
end

-------------------[ Timer Module ]---------------------------
local TimerModule = setmetatable({}, BaseModule)
TimerModule.__index = TimerModule

function TimerModule.new(controller)
    local self = BaseModule.new(controller, "Timer")
    setmetatable(self, TimerModule)
    self.timers = {
        warmup = Timer.New(),
        cooldown = Timer.New(),
        motion = Timer.New(),
        grace = Timer.New()
    }
    self:registerHandlers()
    self:init()
    return self
end

function TimerModule:registerHandlers()
    self.timers.warmup.EventHandler = function()
        self:debug("Warmup complete")
        self.controller.powerStateMachine:transitionTo(PowerStateMachine.States.READY)
        self.controller.powerModule:enableDisablePowerControls(true)
        self.timers.warmup:Stop()
    end
    
    self.timers.cooldown.EventHandler = function()
        self:debug("Cooldown complete")
        self.controller.powerStateMachine:transitionTo(PowerStateMachine.States.IDLE)
        self.controller.powerModule:enableDisablePowerControls(true)
        self.timers.cooldown:Stop()
    end
    
    self.timers.motion.EventHandler = function()
        self:debug("Motion timeout triggered")
        self.controller.state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        self.timers.motion:Stop()
        self.controller.powerModule:powerOff()
    end
    
    self.timers.grace.EventHandler = function()
        self:debug("Grace period ended")
        self.controller.state.motionGraceActive = false
        setProp(controls.ledMotionGraceActive, "Boolean", false)
        self.timers.grace:Stop()
    end
end

function TimerModule:startWarmup(duration)
    self:debug("Starting warmup timer (" .. duration .. "s)")
    self.timers.warmup:Start(duration)
end

function TimerModule:startCooldown(duration)
    self:debug("Starting cooldown timer (" .. duration .. "s)")
    self.timers.cooldown:Start(duration)
end

function TimerModule:startMotion(duration)
    self:debug("Starting motion timer (" .. duration .. "s)")
    self.timers.motion:Start(duration)
end

function TimerModule:startGrace(duration)
    self:debug("Starting grace period timer (" .. duration .. "s)")
    self.timers.grace:Start(duration)
end

function TimerModule:stopMotion()
    self.timers.motion:Stop()
end

function TimerModule:stopGrace()
    self.timers.grace:Stop()
end

function TimerModule:cleanup()
    for _, timer in pairs(self.timers) do
        if timer then timer:Stop() end
    end
    BaseModule.cleanup(self)
end

-------------------[ Component Registry ]---------------------
local ComponentRegistry = setmetatable({}, BaseModule)
ComponentRegistry.__index = ComponentRegistry

ComponentRegistry.componentTypes = {
    callSync    = "call_sync",
    videoBridge = "onvif_camera_operative",
    displays    = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920",
    gains       = "gain",
    systemMute  = "system_mute",
    camACPR     = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355"
}

ComponentRegistry.clearString = "[Clear]"

function ComponentRegistry.new(controller)
    local self = BaseModule.new(controller, "ComponentRegistry")
    setmetatable(self, ComponentRegistry)
    self.components = {
        callSync = nil,
        videoBridge = {},
        displays = {},
        gains = {},
        systemMute = nil,
        camACPR = nil,
        invalid = {}
    }
    self:init()
    return self
end

function ComponentRegistry:getComponent(type, idx)
    if idx then
        return self.components[type] and self.components[type][idx]
    end
    return self.components[type]
end

function ComponentRegistry:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function ComponentRegistry:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function ComponentRegistry:checkStatus()
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid then
            if controls.txtStatus then
                controls.txtStatus.String = "Invalid Components"
                controls.txtStatus.Value = 1
            end
            return
        end
    end
    if controls.txtStatus then
        controls.txtStatus.String = "OK"
        controls.txtStatus.Value = 0
    end
end

function ComponentRegistry:setComponent(ctrl, componentType)
    if not ctrl then return nil end
    local componentName = ctrl.String
    
    if componentName == "" then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    
    if componentName == ComponentRegistry.clearString then
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    
    local newComponent = Component.New(componentName)
    if #Component.GetControls(newComponent) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    
    self:debug("Setting " .. componentType .. ": {" .. componentName .. "}")
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return newComponent
end

function ComponentRegistry:discoverComponents()
    local compType = ComponentRegistry.componentTypes
    local namesTable = {
        namesCallSync = {},
        namesVideoBridge = {},
        namesCamACPR = {},
        namesDisplay = {},
        namesGain = {},
        namesMute = {}
    }
    
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == compType.callSync then
            table.insert(namesTable.namesCallSync, comp.Name)
        elseif comp.Type == compType.videoBridge then
            table.insert(namesTable.namesVideoBridge, comp.Name)
        elseif comp.Type == compType.displays then
            table.insert(namesTable.namesDisplay, comp.Name)
        elseif comp.Type == compType.gains then
            table.insert(namesTable.namesGain, comp.Name)
        elseif comp.Type == compType.systemMute then
            table.insert(namesTable.namesMute, comp.Name)
        elseif comp.Type == compType.camACPR then
            table.insert(namesTable.namesCamACPR, comp.Name)
        end
    end
    
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, ComponentRegistry.clearString)
    end
    
    return namesTable
end

function ComponentRegistry:populateChoices(namesTable)
    if controls.compCallSync then
        controls.compCallSync.Choices = namesTable.namesCallSync
    end
    if controls.compVideoBridge then
        for _, ctl in ipairs(getControlArray(controls.compVideoBridge)) do
            ctl.Choices = namesTable.namesVideoBridge
        end
    end
    if controls.compSystemMute then
        controls.compSystemMute.Choices = namesTable.namesMute
    end
    if controls.compACPR then
        controls.compACPR.Choices = namesTable.namesCamACPR
    end
    if controls.compGains then
        for _, ctl in ipairs(controls.compGains) do
            ctl.Choices = namesTable.namesGain
        end
    end
    if controls.devDisplays then
        for _, ctl in ipairs(controls.devDisplays) do
            ctl.Choices = namesTable.namesDisplay
        end
    end
end

-------------------[ Audio Module ]------------------------
local AudioModule = setmetatable({}, BaseModule); AudioModule.__index = AudioModule

function AudioModule.new(controller)
    local self = BaseModule.new(controller, "Audio")
    setmetatable(self, AudioModule)
    self:init()
    return self
end

function AudioModule:setVolume(level, gainIndex)
    local update = function(i, gain)
        self:safeAccess(gain, "gain", "setPosition", level)
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if gain then update(gainIndex, gain) end
    else
        for i, gain in pairs(self.controller.componentRegistry.components.gains) do 
            if gain then update(i, gain) end 
        end
    end
    self.controller:publishNotification()
end

function AudioModule:setMute(state, gainIndex)
    local mute = function(i, gain)
        self:safeAccess(gain, "mute", "set", state)
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if gain then mute(gainIndex, gain) end
    else
        for i, gain in pairs(self.controller.componentRegistry.components.gains) do 
            if gain then mute(i, gain) end 
        end
    end
    self.controller:publishNotification()
end

function AudioModule:setPrivacy(state)
    local callSync = self.controller.componentRegistry:getComponent("callSync")
    self.controller:safeComponentAccess(callSync, "mute", "set", state)
    setProp(controls.btnAudioPrivacy, "Boolean", state)
    if controls.btnAudioPrivacy then
        setProp(controls.btnAudioPrivacy, "CssClass", state and "icon-mic_off" or "icon-mic_none")
    end
    self.controller:publishNotification()
end

function AudioModule:setSystemMute(state)
    local systemMute = self.controller.componentRegistry:getComponent("systemMute")
    if systemMute then self.controller:safeComponentAccess(systemMute, "mute", "set", state) end
end

function AudioModule:setVolumeUpDown(direction, state, gainIndex)
    local action = direction == "up" and "stepper.increase" or "stepper.decrease"
    local step = function(i, gain)
        self.controller:safeComponentAccess(gain, action, "set", state)
        if state then self.controller:safeComponentAccess(gain, "mute", "set", false) end
        self:updateVolumeVisuals(i)
    end
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if gain then step(gainIndex, gain) end
    else
        for i, gain in pairs(self.controller.componentRegistry.components.gains) do 
            if gain then step(i, gain) end 
        end
    end
    self.controller:publishNotification()
end

function AudioModule:getGainLevel(i)
    local gain = self.controller:getGainComponent(i)
    return gain and self.controller:safeComponentAccess(gain, "gain", "getPosition") or 0
end

function AudioModule:getGainMute(i)
    local gain = self.controller:getGainComponent(i)
    return gain and self.controller:safeComponentAccess(gain, "mute", "get") or false
end

function AudioModule:getGainCount()
    local count = 0
    for _, gain in pairs(self.controller.componentRegistry.components.gains) do
        if gain then count = count + 1 end
    end
    return count
end

function AudioModule:updateVolumeVisuals(i)
    -- Cache control references to reduce repeated lookups
    local fader = controls.knbVolumeFader and controls.knbVolumeFader[i]
    local mute = controls.btnVolumeMute and controls.btnVolumeMute[i]
    if not fader or not mute then return end
    
    -- Cache current state to avoid redundant property access
    local isMuted = mute.Boolean
    local gainType = self.controller:getGainType(i)
    setProp(mute, "CssClass", isMuted and (gainType == "Mic" and "icon-mic_none" or "icon-volume_off") or (gainType == "Mic" and "icon-mic_off" or "icon-volume_mute"))
    setProp(fader, "Color", isMuted and "#CCCCCC" or "#0561A5")
end

-------------------[ Video Module ]------------------------
VideoModule = setmetatable({}, BaseModule)
VideoModule.__index = VideoModule

function VideoModule.new(controller)
    local self = BaseModule.new(controller, "Video")
    setmetatable(self, VideoModule)
    return self
end

function VideoModule:setPrivacy(state, idx)
    local apply = function(i, videoBridge)
        self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "set", state)
        self.controller:videoBridgeCheckPrivacy(i)
    end
    if idx then
        local videoBridge = self.controller.componentRegistry:getComponent("videoBridge", idx)
        if videoBridge then apply(idx, videoBridge) end
    else
        for i, videoBridge in pairs(self.controller.componentRegistry.components.videoBridge) do 
            if videoBridge then apply(i, videoBridge) end 
        end
    end
    self.controller:publishNotification()
end

function VideoModule:getPrivacyState(idx)
    idx = idx or 1
    local videoBridge = self.controller.componentRegistry:getComponent("videoBridge", idx)
    if not videoBridge then return false end
    local state = self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "get")
    self.controller:videoBridgeCheckPrivacy(idx)
    self.controller:publishNotification()
    return state
end

-------------------[ Display Module ]----------------------
DisplayModule = setmetatable({}, BaseModule)
DisplayModule.__index = DisplayModule

function DisplayModule.new(controller)
    local self = BaseModule.new(controller, "Display")
    setmetatable(self, DisplayModule)
    return self
end

function DisplayModule:powerAll(state)
    local control = state and "PowerOnTrigger" or "PowerOffTrigger"
    for _, display in pairs(self.controller.componentRegistry.components.displays) do
        if display then self.controller:safeComponentAccess(display, control, "trigger") end
    end
end

function DisplayModule:powerSingle(idx, state)
    local display = self.controller:getDisplayComponent(idx)
    if display then self.controller:safeComponentAccess(display, state and "PowerOnTrigger" or "PowerOffTrigger", "trigger") end
end

-------------------[ Power Module ]------------------------
PowerModule = setmetatable({}, BaseModule)
PowerModule.__index = PowerModule

function PowerModule.new(controller)
    local self = BaseModule.new(controller, "Power")
    setmetatable(self, PowerModule)
    return self
end

function PowerModule:enableDisablePowerControls(state)
    for _, btn in ipairs({controls.btnSystemOnOff, controls.btnSystemOn, controls.btnSystemOff}) do
        setProp(btn, "IsDisabled", not state)
    end
end

function PowerModule:setSystemPowerFB(state)
    setProp(controls.ledSystemPower, "Boolean", state)
    setProp(controls.btnSystemOnOff, "Boolean", state)
    setProp(controls.btnSystemOn, "Boolean", state)
    setProp(controls.btnSystemOff, "Boolean", not state)
end

function PowerModule:powerOn()
    self:debug("Powering On")
    if controls.btnSystemOnTrig then controls.btnSystemOnTrig:Trigger() end
    self:enableDisablePowerControls(false)
    
    -- Use state machine for power state transitions
    self.controller.powerStateMachine:transitionTo(PowerStateMachine.States.WARMING)
    self.controller.timerModule:startWarmup(self.controller.config.warmupTime)
    
    self:setSystemPowerFB(true)
    self.controller:applyVolumeDefaults()
    self.controller.audioModule:setMute(false)
    self.controller.audioModule:setPrivacy(true)
    --self.controller.videoModule:setPrivacy(false, 1) -- setPrivacy for Video during Startup, this is handled on Hook State since the room uses ACPR
    self.controller.displayModule:powerAll(true)
    self.controller:publishNotification()
end

function PowerModule:powerOff()
    self:debug("Powering Off")
    if controls.btnSystemOffTrig then controls.btnSystemOffTrig:Trigger() end
    self:enableDisablePowerControls(false)
    
    -- Use state machine for power state transitions
    self.controller.powerStateMachine:transitionTo(PowerStateMachine.States.COOLING)
    self.controller.timerModule:startCooldown(self.controller.config.cooldownTime)
    
    self:setSystemPowerFB(false)
    self.controller.audioModule:setPrivacy(true)
    
    -- Use component registry to access gains
    for i, gain in pairs(self.controller.componentRegistry.components.gains) do
        if gain then
            local gainType = self.controller:getGainType(i)
            if gainType ~= "micVolume" and gainType ~= "Mic" then
                self.controller.audioModule:setMute(true, i)
            end
        end
    end
    self.controller.videoModule:setPrivacy(true)
    self.controller.displayModule:powerAll(false)
    self.controller:endCalls()
    self.controller:publishNotification()
end

-------------------[ Motion Module ]-----------------------
MotionModule = setmetatable({}, BaseModule)
MotionModule.__index = MotionModule

function MotionModule.new(controller)
    local self = BaseModule.new(controller, "Motion")
    setmetatable(self, MotionModule)
    return self
end

function MotionModule:checkMotion()
    self:debug("Checking Motion")
    if controls.ledMotionIn and controls.ledMotionIn.Boolean then
        self.controller.state.motionTimeoutActive = false
        setProp(controls.ledMotionTimeoutActive, "Boolean", false)
        self.controller.timerModule:stopMotion()
        if controls.ledSystemPower and not controls.ledSystemPower.Boolean
            and not self.controller.state.motionGraceActive
            and controls.txtMotionMode and controls.txtMotionMode.String == "Motion On/Off" then
            self.controller:debugPrint("Turning System on from Motion")
            self.controller.powerModule:powerOn()
        end
        return
    end
    if controls.txtMotionMode and (
        controls.txtMotionMode.String == "Motion On/Off" or controls.txtMotionMode.String == "Motion Off") then
        self:debug("Starting Motion Off Timer")
        self.controller.state.motionTimeoutActive = true
        setProp(controls.ledMotionTimeoutActive, "Boolean", true)
        local timeout = (controls.motionTimeout and controls.motionTimeout.Value) or self.controller.config.motionTimeout
        self.controller.timerModule:startMotion(timeout)
    end
end

-------------------[ SystemAutomationController (The Orchestrator) ]-------------------
local SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController

function SystemAutomationController.new(roomName, config, defaultConfigs)
    local self = setmetatable({}, SystemAutomationController)
    self.roomName = roomName or "Default Room"
    self.debugging = config.debugging ~= false
    self.defaultConfigs = defaultConfigs
    self.state = { powerLocked = false, motionTimeoutActive = false, motionGraceActive = false }
    self.config = config
    
    -- Initialize new modules
    self.componentRegistry  = ComponentRegistry.new(self)
    self.timerModule        = TimerModule.new(self)
    self.powerStateMachine  = PowerStateMachine.new(self)
    
    -- Initialize domain modules
    self.audioModule    = AudioModule.new(self)
    self.videoModule    = VideoModule.new(self)
    self.displayModule  = DisplayModule.new(self)
    self.powerModule    = PowerModule.new(self)
    self.motionModule   = MotionModule.new(self)
    
    return self
end

-----------------[ Debug Helper ]----------------------
function SystemAutomationController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

------------------[ Component Utility Helpers ]---------------------
function SystemAutomationController:getGainComponent(idx) 
    return self.componentRegistry:getComponent("gains", idx)
end

function SystemAutomationController:getDisplayComponent(idx) 
    return self.componentRegistry:getComponent("displays", idx)
end

function SystemAutomationController:getGainType(idx)
    if controls.typeGain and controls.typeGain[idx] then return controls.typeGain[idx].String end
    if idx == 1 then return "Program" end
    return "Mic"
end

------------------[ Component Access Helper ]---------------------
function SystemAutomationController:safeComponentAccess(component, control, action, value)
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
    if not success then self:debugPrint("Component access error: "..tostring(result)); return false end
    return result
end

------------------[ Event Handler Mapping/Registration ]----------------------
function SystemAutomationController:registerEventHandlers()
    -- Single control event mappings with direct object references
    local singleEventMap = {
        { ctrl = controls.btnSystemOnOff, handler = function(ctl) 
            if ctl.Boolean then self.powerModule:powerOn() else self.powerModule:powerOff() end 
        end },
        { ctrl = controls.btnSystemOn, handler = function() self.powerModule:powerOn() end },
        { ctrl = controls.btnSystemOff, handler = function() 
            self.powerModule:powerOff()
            self.state.motionGraceActive = true
            setProp(controls.ledMotionGraceActive, "Boolean", true)
            self.timerModule:startGrace(self.config.gracePeriod) 
        end },
        { ctrl = controls.btnAudioPrivacy, handler = function(ctl) self.audioModule:setPrivacy(ctl.Boolean) end },
        { ctrl = controls.roomName, handler = function()
            local fmt = "[" .. controls.roomName.String .. "]"
            self.roomName = fmt
            self:debugPrint("Room name updated: " .. fmt)
            self:publishNotification()
        end },
        { ctrl = controls.ledMotionIn, handler = function() self.motionModule:checkMotion() end },
        { ctrl = controls.compCallSync, handler = function() self:setCallSyncComponent() end },
        { ctrl = controls.compSystemMute, handler = function() self:setSystemMuteComponent() end },
        { ctrl = controls.compACPR, handler = function() self:setCamACPRComponent() end }
    }
    
    -- Batch register single controls
    for _, mapping in ipairs(singleEventMap) do
        bind(mapping.ctrl, mapping.handler)
    end
    
    -- Array control mappings with indexed handlers
    local arrayEventMap = {
        { ctrls = controls.btnVideoPrivacy, handler = function(i, ctl) 
            self.videoModule:setPrivacy(ctl.Boolean, i) 
        end },
        { ctrls = controls.knbVolumeFader, handler = function(i, ctl) 
            self.audioModule:setVolume(ctl.Position, i) 
        end },
        { ctrls = controls.btnVolumeMute, handler = function(i, ctl) 
            self.audioModule:setMute(ctl.Boolean, i) 
        end },
        { ctrls = controls.btnVolumeUp, handler = function(i, ctl) 
            self.audioModule:setVolumeUpDown("up", ctl.Boolean, i) 
        end },
        { ctrls = controls.btnVolumeDn, handler = function(i, ctl) 
            self.audioModule:setVolumeUpDown("down", ctl.Boolean, i) 
        end }
    }
    
    -- Batch register array controls
    for _, mapping in ipairs(arrayEventMap) do
        bindArray(mapping.ctrls, mapping.handler)
    end
    
    -- Component selection handlers (with forEach optimization)
    local componentMaps = {
        { ctrls = controls.compVideoBridge, handler = function(i) self:setVideoBridgeComponent(i) end },
        { ctrls = controls.compGains, handler = function(i) self:setGainComponent(i) end },
        { ctrls = controls.devDisplays, handler = function(i) self:setDisplayComponent(i) end }
    }
    
    for _, mapping in ipairs(componentMaps) do
        forEach(mapping.ctrls, function(i, ctrl)
            bind(ctrl, function() mapping.handler(i) end)
        end)
    end
    
    -- Special case: typeGain with conditional logic
    forEach(controls.typeGain, function(i, ctrl)
        if i > 1 then 
            bind(ctrl, function(ctl)
                self:debugPrint("Gain Type [" .. i .. "] changed to: " .. ctl.String)
                if self.componentRegistry.components.gains[i] then
                    local val = self:getDefaultVolumeForType(ctl.String)
                    self.audioModule:setVolume(val, i)
                    self:debugPrint("Applied default volume (" .. val .. ") to gain index " .. i)
                end
                self:publishNotification()
            end) 
        end
    end)
end

------------------[ Component Discovery / Selection ]------------------
function SystemAutomationController:getComponentNames()
    local namesTable = self.componentRegistry:discoverComponents()
    self.componentRegistry:populateChoices(namesTable)
end

----------------[ UI/Component Status Handling ]----------------
function SystemAutomationController:setComponent(ctrl, componentType)
    return self.componentRegistry:setComponent(ctrl, componentType)
end

function SystemAutomationController:setComponentInvalid(componentType)
    self.componentRegistry:setComponentInvalid(componentType)
end

function SystemAutomationController:setComponentValid(componentType)
    self.componentRegistry:setComponentValid(componentType)
end

function SystemAutomationController:checkStatus()
    self.componentRegistry:checkStatus()
end

------[ Per-Component Setup/Assignment (wires events) ]------
function SystemAutomationController:setComponentByType(ctrl, componentType, storage, eventMap, initCallback)
    if type(storage) == "table" then
        -- Array storage with index
        local idx = storage.index
        local storageKey = storage.key
        if not ctrl or not getControlArray(ctrl)[idx] then return end
        local label = storage.label or (componentType .. " [" .. idx .. "]")
        
        -- Clean up old event handlers before setting new component (DRY pattern)
        cleanupComponentHandlers(
            self.components[storageKey][idx],
            eventMap,
            function(msg) self:debugPrint("[" .. label .. "] " .. msg) end
        )
        
        self.components[storageKey][idx] = self:setComponent(getControlArray(ctrl)[idx], label)
        local comp = self.components[storageKey][idx]
        if not comp then return end
        
        -- Bind events with index context
        if eventMap then
            for event, handler in pairs(eventMap) do
                if comp[event] then 
                    comp[event].EventHandler = function() handler(self, idx) end 
                end
            end
        end
        if initCallback then initCallback(self, idx) end
    else
        -- Single storage
        -- Clean up old event handlers before setting new component (DRY pattern)
        cleanupComponentHandlers(
            self.components[storage],
            eventMap,
            function(msg) self:debugPrint("[" .. componentType .. "] " .. msg) end
        )
        
        self.components[storage] = self:setComponent(ctrl, componentType)
        local comp = self.components[storage]
        if not comp then return end
        
        -- Bind events
        if eventMap then
            for event, handler in pairs(eventMap) do
                if comp[event] then 
                    comp[event].EventHandler = function() handler(self) end 
                end
            end
        end
        if initCallback then initCallback(self, comp) end
    end
end

function SystemAutomationController:setCallSyncComponent()
    self:setComponentByType(controls.compCallSync, "Call Sync", "callSync", {
        ["off.hook"] = function(ctrl) ctrl:callSyncCheckConnection() end,
        ["mute"] = function(ctrl) ctrl:callSyncCheckMute() end
    })
end

function SystemAutomationController:setVideoBridgeComponent(idx)
    local label = idx == 1 and "Video Bridge [Main]" or "Video Bridge [" .. idx .. "]"
    self:setComponentByType(controls.compVideoBridge, "Video Bridge", 
        { key = "videoBridge", index = idx, label = label }, {
        ["toggle.privacy"] = function(ctrl, i) ctrl:videoBridgeCheckPrivacy(i) end
    }, function(ctrl, i) ctrl:getVideoBridgePrivacy(i) end)
end

-- Public method for external scripts to trigger VideoBridge re-initialization
-- Used by DivisibleSpaceController when VideoBridge routing changes programmatically
function SystemAutomationController:reinitializeVideoBridgeComponent(idx)
    self:debugPrint("Manually re-initializing Video Bridge [" .. (idx or 1) .. "]")
    self:setVideoBridgeComponent(idx or 1)
end

function SystemAutomationController:setGainComponent(idx)
    local label = idx == 1 and "Program Volume [Gain 1]" or "Gain [" .. idx .. "]"
    self:setComponentByType(controls.compGains, "Gain", 
        { key = "gains", index = idx, label = label }, {
        ["gain"] = function(ctrl, i) ctrl:getVolumeLvl(i) end,
        ["mute"] = function(ctrl, i) ctrl:getVolumeMute(i) end
    }, function(ctrl, i) 
        ctrl:getVolumeLvl(i)
        ctrl:getVolumeMute(i)
    end)
end

function SystemAutomationController:setSystemMuteComponent()
    self:setComponentByType(controls.compSystemMute, "System Mute", "systemMute")
end

function SystemAutomationController:setCamACPRComponent()
    self:setComponentByType(controls.compACPR, "Camera ACPR", "camACPR", {
        ["TrackingBypass"] = function(ctrl) ctrl:updateACPRTrackingBypass() end
    }, function(ctrl, comp)
        ctrl:callSyncCheckConnection()
    end)
end

function SystemAutomationController:setDisplayComponent(idx)
    self:setComponentByType(controls.devDisplays, "Display", 
        { key = "displays", index = idx }, {
        ["PowerIsOn"] = function(ctrl, i) 
            ctrl:debugPrint("Display [" .. i .. "] powered ON")
        end,
        ["PowerIsOff"] = function(ctrl, i) 
            ctrl:debugPrint("Display [" .. i .. "] powered OFF")
        end
    })
end

function SystemAutomationController:getVideoBridgePrivacy(idx)
    self:videoBridgeCheckPrivacy(idx)
end

----------------[ Call Sync Helpers ]-------------------
function SystemAutomationController:callSyncCheckMute()
    local callSync = self.componentRegistry:getComponent("callSync")
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "mute", "get")
    self:debugPrint("Call Sync Mute State: " .. tostring(state))
    if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
end

function SystemAutomationController:videoBridgeCheckPrivacy(idx)
    idx = idx or 1
    local videoBridge = self.componentRegistry:getComponent("videoBridge", idx)
    if not videoBridge then return end
    local state = self:safeComponentAccess(videoBridge, "toggle.privacy", "get")
    self:debugPrint("Video Bridge [" .. idx .. "] Privacy State: " .. tostring(state))
    
    -- Update the appropriate button based on whether it's an array or single button
    if controls.btnVideoPrivacy then
        if isArr(controls.btnVideoPrivacy) and controls.btnVideoPrivacy[idx] then
            controls.btnVideoPrivacy[idx].Boolean = state
            -- Multiple buttons - update the specific button for this bridge
        elseif not isArr(controls.btnVideoPrivacy) then
            -- Single button - update it (typically represents primary bridge)
            controls.btnVideoPrivacy.Boolean = state
        end
    end
end

function SystemAutomationController:callSyncCheckConnection()
    local callSync = self.componentRegistry:getComponent("callSync")
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "off.hook", "get")
    self:debugPrint("Call Connection State: " .. tostring(state))
    self:callSyncCheckMute()
    if self.componentRegistry.components.videoBridge then 
        for i, _ in pairs(self.componentRegistry.components.videoBridge) do 
            self.videoModule:setPrivacy(not state, i) 
        end 
        self:videoBridgeCheckPrivacy(1)
    end    
    local camACPR = self.componentRegistry:getComponent("camACPR")
    if camACPR and camACPR["TrackingBypass"] then
        -- Set IsDisabled based on call state (enabled during call, disabled when no call)
        camACPR["TrackingBypass"].IsDisabled = not state
        -- Set Boolean: false (Auto) when call active, true (Off) when no call
        self:safeComponentAccess(camACPR, "TrackingBypass", "set", not state)
    end
end

----------------[ Misc Volume Helpers ]-----------------
function SystemAutomationController:updateVolumeVisuals(idx)
    self.audioModule:updateVolumeVisuals(idx)
end

function SystemAutomationController:getVolumeLvl(idx)
    local gain = self:getGainComponent(idx)
    if not gain then return end
    local level = self:safeComponentAccess(gain, "gain", "getPosition")
    if controls.knbVolumeFader and controls.knbVolumeFader[idx] then
        controls.knbVolumeFader[idx].Position = level
    end
    self:updateVolumeVisuals(idx)
    self:publishNotification()
end

function SystemAutomationController:getVolumeMute(idx)
    local gain = self:getGainComponent(idx)
    if not gain then return end
    local state = self:safeComponentAccess(gain, "mute", "get")
    if controls.btnVolumeMute and controls.btnVolumeMute[idx] then
        controls.btnVolumeMute[idx].Boolean = state
    end
    self:updateVolumeVisuals(idx)
    self:publishNotification()
end

function SystemAutomationController:updateACPRTrackingBypass()
    local camACPR = self.componentRegistry:getComponent("camACPR")
    if not camACPR then return end
    local state = self:safeComponentAccess(camACPR, "TrackingBypass", "get")
    self:debugPrint("ACPR Tracking Bypass: "..tostring(state))
    
    -- Update Legend based on IsDisabled state
    if camACPR["TrackingBypass"] then
        if camACPR["TrackingBypass"].IsDisabled then
            camACPR["TrackingBypass"].Legend = "Disabled"
        else
            camACPR["TrackingBypass"].Legend = state and "Off" or "Auto"
        end
    end
end

function SystemAutomationController:endCalls()
    local callSync = self.componentRegistry:getComponent("callSync")
    if not callSync then return end
    self:debugPrint("Ending Calls")
    self:safeComponentAccess(callSync, "call.decline", "trigger")
end

------------------[ Helper: Default Volume By Type ]--------------------
function SystemAutomationController:getDefaultVolumeForType(type)
    local defaults = {
        Program = self.config.defaultProgramVolume,
        Mic = self.config.defaultMicVolume,
        Gain = self.config.defaultGainVolume
    }
    return defaults[type] or self.config.defaultMicVolume
end

----------------[ Fire Alarm ]-----------------
function SystemAutomationController:setFireAlarm(state)
    if state then
        self.audioModule:setSystemMute(true)
        self.displayModule:powerAll(false)
        return
    end
    if controls.ledSystemPower and controls.ledSystemPower.Boolean then
        self.audioModule:setSystemMute(false)
        self.displayModule:powerAll(true)
    end
end

----------------[ Volume Range Management ]-----------------
function SystemAutomationController:applyVolumeDefaults()
    self:debugPrint("Applying volume defaults based on current typeGain settings")
    for i, gain in pairs(self.componentRegistry.components.gains) do
        if gain then
            local gainType = self:getGainType(i)
            local defaultValue = self:getDefaultVolumeForType(gainType)
            self.audioModule:setVolume(defaultValue, i)
            self:debugPrint("Applied default " .. gainType .. " Volume (" .. defaultValue .. ") to gain index " .. i .. " (Type: " .. gainType .. ")")
        end
    end
end

----------------[ Main State Publishing ]-----------------
function SystemAutomationController:publishNotification()
    local camACPR = self.componentRegistry:getComponent("camACPR")
    local systemState = {
        RoomName = self.roomName,
        PowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean or false,
        PowerStateMachine = self.powerStateMachine:getCurrentState(),
        SystemWarming = self.powerStateMachine:isWarming(),
        SystemCooling = self.powerStateMachine:isCooling(),
        AudioPrivacy = controls.btnAudioPrivacy and controls.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = controls.btnVideoPrivacy and controls.btnVideoPrivacy.Boolean or false,
        ACPRState = (camACPR and
            camACPR["TrackingBypass"] and
            camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time()
    }
    systemState.GainControls = {}
    for i, gain in pairs(self.componentRegistry.components.gains) do
        if gain then
            systemState.GainControls[i] = {
                Level = self.audioModule:getGainLevel(i),
                Muted = self.audioModule:getGainMute(i)
            }
        end
    end
    if controls.txtNotificationID and controls.txtNotificationID.String ~= "" then
        Notifications.Publish(controls.txtNotificationID.String, systemState)
    end
end

----------------[ Default Config Selection UI Handler ]-----------------
function SystemAutomationController:setupConfigSelection()
    if not controls.selDefaultConfigs then return end

    controls.selDefaultConfigs.Choices = {
        "Conference Room",
        "Huddle Room",
        "Default",
        "Custom Room",
        "User Defined"
    }
    local mappings = {
        { control = "warmupTime", config = "warmupTime" },
        { control = "cooldownTime", config = "cooldownTime" },
        { control = "motionTimeout", config = "motionTimeout" },
        { control = "motionGracePeriod", config = "gracePeriod" },
        { control = "defaultProgramVolume", config = "defaultProgramVolume" },
        { control = "defaultMicVolume", config = "defaultMicVolume" },
        { control = "defaultGainVolume", config = "defaultGainVolume" }
    }
    local function updateControlValues(configType)
        local conf = self.defaultConfigs[configType]
        if not conf then return end
        local isUser = configType == "User Defined"
        for _, map in ipairs(mappings) do
            local ctl = nil
            if map.array then
                if controls[map.control] and controls[map.control][map.idx] then
                    ctl = controls[map.control][map.idx]
                end
            else
                ctl = controls[map.control]
            end
            if ctl then
                ctl.Value = conf[map.config]
                ctl.IsDisabled = not isUser
            end
        end
    end
    
    controls.selDefaultConfigs.EventHandler = function(ctl)
        updateControlValues(ctl.String)
        -- Update typeGain controls when room type changes
        self:setGainTypeAssignments(ctl.String)
        -- Reapply volume defaults with new gain type assignments
        self:applyVolumeDefaults()
    end
    
    for _, map in ipairs(mappings) do
        local ctl = nil
        if map.array then
            if controls[map.control] and controls[map.control][map.idx] then
                ctl = controls[map.control][map.idx]
            end
        else
            ctl = controls[map.control]
        end
        if ctl then
            ctl.EventHandler = function(val)
                if controls.selDefaultConfigs.String == "User Defined" then
                    self.defaultConfigs["User Defined"][map.config] = val.Value
                end
            end
        end
    end
    
    controls.selDefaultConfigs.String = "Default"
    updateControlValues("Default")
end

----------------[ Gain Type Assignments ]-----------------
function SystemAutomationController:setGainTypeAssignments(roomType)
    if not controls.typeGain then return end
    
    -- Use current room configuration if no roomType specified
    roomType = roomType or (controls.selDefaultConfigs and controls.selDefaultConfigs.String) or "Default"
    
    local gainTypeAssignments = {
        ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
        ["Huddle Room"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
        ["Custom Room"] = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
        ["Default"] = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" }
    }
    
    local assignments = gainTypeAssignments[roomType] or gainTypeAssignments["Default"]
    
    for i, gainType in ipairs(assignments) do
        if controls.typeGain[i] then
            if i == 1 then
                -- First gain control is always Program and should remain disabled
                controls.typeGain[i].String = "Program"
                controls.typeGain[i].IsDisabled = true
            else
                controls.typeGain[i].String = gainType
            end
        end
    end
end

----------------[ Initialization ]--------------------------
function SystemAutomationController:init()
    self.powerModule:enableDisablePowerControls(true)
    self:getComponentNames()
    setProp(controls.txtMotionMode, "Choices", { "Motion On/Off", "Motion Off", "Motion Disabled" })
    
    -- Setup typeGain dropdown choices
    if controls.typeGain then
        local gainChoices = { "Program", "Mic", "Gain" }
        for i, gainControl in ipairs(getControlArray(controls.typeGain)) do
            if gainControl then
                gainControl.Choices = gainChoices
                if i == 1 then
                    -- First gain control is always Program and should be disabled
                    gainControl.String = "Program"
                    gainControl.IsDisabled = true
                end
            end
        end
    end
    
    self:setGainTypeAssignments()
    
    -- Initialize components
    self:setCallSyncComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    
    forEach(controls.compVideoBridge, function(i) self:setVideoBridgeComponent(i) end)
    forEach(controls.compGains, function(i) self:setGainComponent(i) end)
    forEach(controls.devDisplays, function(i) self:setDisplayComponent(i) end)
    
    self:debugPrint("SystemAutomationController ready; "..self.audioModule:getGainCount().." gain controls detected.")
end

----------------[ Cleanup ]--------------------------
function SystemAutomationController:cleanup()
    -- Cleanup all modules
    local modules = { 
        self.timerModule, 
        self.audioModule, 
        self.videoModule, 
        self.displayModule, 
        self.powerModule, 
        self.motionModule,
        self.powerStateMachine,
        self.componentRegistry
    }
    for _, module in ipairs(modules) do
        if module and module.cleanup then module:cleanup() end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

------------------[ Application Boot / Setup ]------------------

-- Factory function for default configurations
local function getDefaultConfig(roomType)
    -- Single source of truth for default volume values
    local baseConfig = {
        defaultProgramVolume = 0.7,
        defaultMicVolume = 0.5, 
        defaultGainVolume = 0.7  -- Now same as defaultProgramVolume
    }
    
    roomType = roomType or "Default"
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = controls.warmupTime and controls.warmupTime.Value or 10,
            cooldownTime = controls.cooldownTime and controls.cooldownTime.Value or 5,
            motionTimeout = controls.motionTimeout and controls.motionTimeout.Value or 300,
            gracePeriod = controls.motionGracePeriod and controls.motionGracePeriod.Value or 30,
            defaultProgramVolume = (controls.defaultProgramVolume and controls.defaultProgramVolume.Value) or baseConfig.defaultProgramVolume,
            defaultMicVolume = (controls.defaultMicVolume and controls.defaultMicVolume.Value) or baseConfig.defaultMicVolume,
            defaultGainVolume = (controls.defaultGainVolume and controls.defaultGainVolume.Value) or baseConfig.defaultGainVolume,
        }
    end
    
    local defaults = {
        ["Conference Room"] = { 
            debugging = true, warmupTime = 15, cooldownTime = 10, motionTimeout = 600, gracePeriod = 60,
            defaultProgramVolume = baseConfig.defaultProgramVolume,
            defaultMicVolume = baseConfig.defaultMicVolume,
            defaultGainVolume = baseConfig.defaultGainVolume,
        },
        ["Huddle Room"] = { 
            debugging = false, warmupTime = 5, cooldownTime = 3, motionTimeout = 300, gracePeriod = 30,
            defaultProgramVolume = 0.6,  -- Lower for huddle rooms
            defaultMicVolume = baseConfig.defaultMicVolume,
            defaultGainVolume = baseConfig.defaultGainVolume,
        },
        ["Default"] = { 
            debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30,
            defaultProgramVolume = baseConfig.defaultProgramVolume,
            defaultMicVolume = baseConfig.defaultMicVolume,
            defaultGainVolume = baseConfig.defaultGainVolume,
        },
        ["Custom Room"] = { 
            debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30,
            defaultProgramVolume = baseConfig.defaultProgramVolume,
            defaultMicVolume = baseConfig.defaultMicVolume,
            defaultGainVolume = baseConfig.defaultGainVolume,
        }
    }
    return defaults[roomType] or defaults["Default"]
end

-- Enhanced factory function with comprehensive error handling
local function createSystemController(roomName, roomType)
    -- Input validation
    if not roomName or roomName == "" then
        print("ERROR: createSystemController requires a valid roomName")
        return nil
    end
    
    roomType = roomType or "Default"
    local validRoomTypes = {"Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined"}
    local isValidType = false
    for _, validType in ipairs(validRoomTypes) do
        if roomType == validType then isValidType = true; break end
    end
    
    if not isValidType then
        print("WARNING: Invalid room type '" .. roomType .. "', defaulting to 'Default'")
        roomType = "Default"
    end
    
    -- Configuration preparation with error handling
    local config, allConfigs
    local configSuccess, configError = pcall(function()
        config = getDefaultConfig(roomType)
        allConfigs = {
            ["Conference Room"] = getDefaultConfig("Conference Room"),
            ["Huddle Room"]     = getDefaultConfig("Huddle Room"),
            ["Default"]         = getDefaultConfig("Default"),
            ["Custom Room"]     = getDefaultConfig("Custom Room"),
            ["User Defined"]    = getDefaultConfig("User Defined")
        }
    end)
    
    if not configSuccess then
        print("ERROR: Failed to load configurations: " .. tostring(configError))
        return nil
    end
    
    -- Controller creation with detailed error context
    local success, controller = pcall(function()
        print("Initializing SystemAutomationController for " .. roomName .. " (" .. roomType .. ")")
        
        -- Step 1: Create controller object
        local object = SystemAutomationController.new(roomName, config, allConfigs)
        if not object then error("Controller constructor returned nil") end
        
        -- Step 2: Normalize control arrays
        normalizeControlArrays()
        
        -- Step 3: Register event handlers
        object:registerEventHandlers()
        
        -- Step 4: Setup configuration selection UI
        object:setupConfigSelection()
        
        -- Step 5: Initialize modules and components
        object:init()
        
        return object
    end)
    
    if success and controller then
        print("✓ SystemAutomationController successfully created for " .. roomName)
        
        -- Initialize global registry if it doesn't exist
        if not _G.SystemAutomationControllers then
            _G.SystemAutomationControllers = {}
        end
        
        -- Register instance by room name (extract name from formatted string "[Room Name]" -> "Room Name")
        local roomKey = roomName:match("%[(.+)%]") or roomName:gsub("^%s+", ""):gsub("%s+$", "")
        _G.SystemAutomationControllers[roomKey] = controller
        print("  Registered as: SystemAutomationControllers[\"" .. roomKey .. "\"]")
        
        -- For backward compatibility: set as default if first instance or if roomName matches default pattern
        if not _G.mySystemController or roomKey == "Default Room" then
            _G.mySystemController = controller
        end
        
        return controller
    else
        local errorMsg = tostring(controller)
        print("✗ ERROR: SystemAutomationController creation failed")
        print("  Room: " .. roomName .. " (" .. roomType .. ")")
        print("  Error: " .. errorMsg)
        
        -- Provide graceful degradation guidance
        if errorMsg:find("Missing required controls") then
            print("  Suggestion: Check that all required UI controls are properly named and connected")
        elseif errorMsg:find("Component") then
            print("  Suggestion: Verify Q-SYS component assignments and naming")
        else
            print("  Suggestion: Review script configuration and control mappings")
        end
        
        return nil
    end
end

--------------[ Instance Creation Entry ]----------------
if not validateControls() then return end
local formattedRoomName = "[" .. (controls.roomName and controls.roomName.String or "Unknown Room") .. "]"
local configType = (controls.selDefaultConfigs and controls.selDefaultConfigs.String) or "Default"
mySystemController = createSystemController(formattedRoomName, configType)

----------------[ Instance Registry Helper ]----------------
-- Helper function to get controller instance by room name
-- Usage: GetSystemController("RoomA") or GetSystemController() for default
function GetSystemController(roomName)
    if not _G.SystemAutomationControllers then
        return _G.mySystemController  -- Fallback to default
    end
    
    if roomName then
        return _G.SystemAutomationControllers[roomName]
    end
    
    -- Return default instance or first available
    return _G.mySystemController or (function()
        for _, controller in pairs(_G.SystemAutomationControllers) do
            return controller
        end
        return nil
    end)()
end

if mySystemController then
    print("SystemAutomationController created successfully!")
else
    print("ERROR: SystemAutomationController NOT created.")
end

----------------[ PUBLIC API ]--------------------------
--[[
INSTANCE ACCESS:
    For single-instance designs:
        mySystemController  -- Default instance (backward compatible)
        GetSystemController()  -- Helper function (returns default)
    
    For multi-instance designs (8 rooms, etc.):
        -- Direct registry access:
        SystemAutomationControllers["RoomA"]  -- Access by room name
        SystemAutomationControllers["RoomB"]
        SystemAutomationControllers["Conference Room 1"]
        
        -- Helper function (recommended):
        GetSystemController("RoomA")
        GetSystemController("RoomB")
        
        -- Iterate over all instances:
        for roomName, controller in pairs(SystemAutomationControllers) do
            controller.powerModule:powerOn()
        end

PUBLIC API (same for all instances):
    -- Audio Control
    controller.audioModule:setVolume(level, idx)
    controller.audioModule:setMute(state, idx)
    controller.audioModule:getGainCount()
    
    -- Power Control
    controller.powerModule:powerOn()
    controller.powerModule:powerOff()
    
    -- Power State Machine
    controller.powerStateMachine:getCurrentState()
    controller.powerStateMachine:isWarming()
    controller.powerStateMachine:isCooling()
    controller.powerStateMachine:isReady()
    controller.powerStateMachine:isIdle()
    
    -- Timer Control
    controller.timerModule:startWarmup(duration)
    controller.timerModule:startCooldown(duration)
    controller.timerModule:startMotion(duration)
    controller.timerModule:startGrace(duration)
    
    -- Component Registry
    controller.componentRegistry:getComponent(type, idx)
    controller.componentRegistry.components.gains[idx]
    controller.componentRegistry.components.displays[idx]
    controller.componentRegistry.components.videoBridge[idx]
    controller.componentRegistry.components.callSync
    controller.componentRegistry.components.systemMute
    controller.componentRegistry.components.camACPR
    
    -- System Control
    controller:publishNotification()
    controller:cleanup()
    controller:setFireAlarm(true|false)

EXAMPLES:
    -- Single instance (backward compatible)
    mySystemController.powerModule:powerOn()
    GetSystemController().powerModule:powerOn()  -- Same as above
    
    -- Multiple instances (direct registry access)
    SystemAutomationControllers["RoomA"].powerModule:powerOn()
    SystemAutomationControllers["RoomB"].audioModule:setVolume(0.7, 1)
    
    -- Multiple instances (using helper function - recommended)
    GetSystemController("RoomA").powerModule:powerOn()
    GetSystemController("RoomB").audioModule:setVolume(0.7, 1)
    
    -- Power on all rooms
    for _, controller in pairs(SystemAutomationControllers) do
        controller.powerModule:powerOn()
    end
    
    -- Get all room names
    for roomName, _ in pairs(SystemAutomationControllers) do
        print("Found controller for: " .. roomName)
    end
]]

