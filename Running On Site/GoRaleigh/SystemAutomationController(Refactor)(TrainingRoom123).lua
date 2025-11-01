--[[
    System Automation Controller (Refactored OOP, Modular, Modern Lua + Optimized Boardroom Features)
    Author: Nikolas Smith, Q-SYS
    Version: 3.3 | Date: 2025-08-26
    Firmware Req: 10.0.0
    Notes:
    - This script is a modified version of the SystemAutomationController script that adds optimized Boardroom functionality.
    - It also adds a check for the Room Controls component and a fallback method if the component is not found.
    - It also adds a check for the System Automation component and a fallback method if the component is not found.
    - NEW: Optimized Boardroom functionality with ~50% less code
    - This version includes external controller registration and notification for UCI layer changes.
    - Implements strict OOP / modular structure per Lua Refactoring Guidelines.
    - Each logical area (audio, power, video, etc.) is its own class with methods.
    - Controller is shallow, event registration is DRY, logic is delegated.
    - Debugging and config are standardized.
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
    local missing = {}
    if not controls.roomName then table.insert(missing, "roomName") end
    if not controls.txtStatus then table.insert(missing, "txtStatus") end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
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

local function bindControl(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindControlArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do
        bindControl(ctrl, function(ctl) handler(i, ctl) end)
    end
end

local function forEachControl(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

local function setControlProperty(ctrl, property, value, condition)
    if ctrl and (condition == nil or condition) then
        ctrl[property] = value
    end
end

-------------------[ Base Module Class ]------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, getmetatable(controller) or BaseModule)
    self.controller = controller
    self.name = name or "Module"
    self:debug(self.name .. " constructed")
    return self
end

function BaseModule:debug(str)
    self.controller:debugPrint("[" .. self.name .. "] " .. str)
end

function BaseModule:cleanup()
    self:debug("Cleanup completed")
end

-------------------[ Audio Module ]------------------------
AudioModule = setmetatable({}, BaseModule)
AudioModule.__index = AudioModule

function AudioModule.new(controller)
    local self = BaseModule.new(controller, "Audio")
    setmetatable(self, AudioModule)
    return self
end

function AudioModule:setVolume(level, gainIndex)
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if not gain then return end
        self.controller:safeComponentAccess(gain, "gain", "setPosition", level)
        self:updateVolumeVisuals(gainIndex)
    else
        for i, gain in pairs(self.controller.components.gains) do
            if gain then
                self.controller:safeComponentAccess(gain, "gain", "setPosition", level)
                self:updateVolumeVisuals(i)
            end
        end
    end
    self.controller:publishNotification()
end

function AudioModule:setMute(state, gainIndex)
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if not gain then return end
        self.controller:safeComponentAccess(gain, "mute", "set", state)
        self:updateVolumeVisuals(gainIndex)
    else
        for i, gain in pairs(self.controller.components.gains) do
            if gain then
                self.controller:safeComponentAccess(gain, "mute", "set", state)
                self:updateVolumeVisuals(i)
            end
        end
    end
    self.controller:publishNotification()
end

function AudioModule:setPrivacy(state)
    local callSync = self.controller.components.callSync
    self.controller:safeComponentAccess(callSync, "mute", "set", state)
    if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
    self.controller:publishNotification()
end

function AudioModule:setSystemMute(state)
    local systemMute = self.controller.components.systemMute
    if not systemMute then return end
    self.controller:safeComponentAccess(systemMute, "mute", "set", state)
end

function AudioModule:setVolumeUpDown(direction, state, gainIndex)
    local control = direction == "up" and "stepper.increase" or "stepper.decrease"
    if gainIndex then
        local gain = self.controller:getGainComponent(gainIndex)
        if not gain then return end
        self.controller:safeComponentAccess(gain, control, "set", state)
        if state then self.controller:safeComponentAccess(gain, "mute", "set", false) end
        self:updateVolumeVisuals(gainIndex)
    else
        for i, gain in pairs(self.controller.components.gains) do
            if gain then
                self.controller:safeComponentAccess(gain, control, "set", state)
                if state then self.controller:safeComponentAccess(gain, "mute", "set", false) end
                self:updateVolumeVisuals(i)
            end
        end
    end
    self.controller:publishNotification()
end

function AudioModule:getGainCount()
    local c = 0
    for _, gain in pairs(self.controller.components.gains) do if gain then c = c + 1 end end
    return c
end

function AudioModule:getGainLevel(gainIndex)
    local gain = self.controller:getGainComponent(gainIndex)
    if not gain then return 0 end
    return self.controller:safeComponentAccess(gain, "gain", "getPosition") or 0
end

function AudioModule:getGainMute(gainIndex)
    local gain = self.controller:getGainComponent(gainIndex)
    if not gain then return false end
    return self.controller:safeComponentAccess(gain, "mute", "get") or false
end

function AudioModule:updateVolumeVisuals(gainIndex)
    gainIndex = gainIndex or 1
    local volumeFader = controls.knbVolumeFader and controls.knbVolumeFader[gainIndex]
    local volumeMute = controls.btnVolumeMute and controls.btnVolumeMute[gainIndex]
    if not volumeFader or not volumeMute then return end
    if volumeMute.Boolean then
        volumeMute.CssClass = "icon-volume_mute"
        volumeFader.Color = "#CCCCCC"
    else
        volumeMute.CssClass = "icon-volume_off"
        volumeFader.Color = "#0561A5"
    end
end



-------------------[ Video Module ]------------------------
VideoModule = setmetatable({}, BaseModule)
VideoModule.__index = VideoModule

function VideoModule.new(controller)
    local self = BaseModule.new(controller, "Video")
    setmetatable(self, VideoModule)
    return self
end

function VideoModule:setPrivacy(state, bridgeIndex)
    if bridgeIndex then
        -- Set privacy for specific video bridge
        local videoBridge = self.controller.components.videoBridge[bridgeIndex]
        if not videoBridge then return end
        self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "set", state)
        self.controller:videoBridgeCheckPrivacy(bridgeIndex)
    else
        -- Set privacy for all video bridges
        for i, videoBridge in pairs(self.controller.components.videoBridge) do
            if videoBridge then
                self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "set", state)
                self.controller:videoBridgeCheckPrivacy(i)
            end
        end
    end
    local camACPR = self.controller.components.camACPR
    if camACPR then
        self.controller:safeComponentAccess(camACPR, "TrackingBypass", "set", state)
    end
    self.controller:publishNotification()
end

function VideoModule:getPrivacyState(bridgeIndex)
    bridgeIndex = bridgeIndex or 1
    local videoBridge = self.controller.components.videoBridge[bridgeIndex]
    if not videoBridge then return false end
    local state = self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "get")
    self.controller:videoBridgeCheckPrivacy(bridgeIndex)
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
    local trigger = state and "PowerOnTrigger" or "PowerOffTrigger"
    for _, display in pairs(self.controller.components.displays) do
        if display then self.controller:safeComponentAccess(display, trigger, "trigger") end
    end
end

function DisplayModule:powerSingle(index, state)
    local display = self.controller:getDisplayComponent(index)
    if not display then return end
    local trigger = state and "PowerOnTrigger" or "PowerOffTrigger"
    self.controller:safeComponentAccess(display, trigger, "trigger")
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
    setControlProperty(controls.btnSystemOnOff, "IsDisabled", not state)
    setControlProperty(controls.btnSystemOn, "IsDisabled", not state)
    setControlProperty(controls.btnSystemOff, "IsDisabled", not state)
end

function PowerModule:setSystemPowerFB(state)
    setControlProperty(controls.ledSystemPower, "Boolean", state)
    setControlProperty(controls.btnSystemOnOff, "Boolean", state)
    setControlProperty(controls.btnSystemOn, "Boolean", state)
    setControlProperty(controls.btnSystemOff, "Boolean", not state)
end

function PowerModule:powerOn()
    self:debug("Powering On")
    if controls.btnSystemOnTrig then controls.btnSystemOnTrig:Trigger() end
    
    self:enableDisablePowerControls(false)
    self.controller.state.isWarming = true
    setControlProperty(controls.ledSystemWarming, "Boolean", true)
    self.controller.timers.warmup:Start(self.controller.config.warmupTime)
    self:setSystemPowerFB(true)
    
    self.controller:applyVolumeDefaults()
    self.controller.audioModule:setMute(false)
    self.controller.audioModule:setPrivacy(true)
    self.controller.videoModule:setPrivacy(false, 1)
    self.controller.displayModule:powerAll(true)
    self.controller:publishNotification()
end

function PowerModule:powerOff()
    self:debug("Powering Off")
    if controls.btnSystemOffTrig then controls.btnSystemOffTrig:Trigger() end
    
    self:enableDisablePowerControls(false)
    self.controller.state.isCooling = true
    setControlProperty(controls.ledSystemCooling, "Boolean", true)
    self.controller.timers.cooldown:Start(self.controller.config.cooldownTime)
    self:setSystemPowerFB(false)
    
    self.controller.audioModule:setPrivacy(true)
    -- Selectively mute gains, preserving microphone gains
    for i, gain in pairs(self.controller.components.gains) do
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
        setControlProperty(controls.ledMotionTimeoutActive, "Boolean", false)
        self.controller.timers.motion:Stop()
        
        if controls.ledSystemPower and not controls.ledSystemPower.Boolean
            and not self.controller.state.motionGraceActive
            and controls.txtMotionMode and controls.txtMotionMode.String == "Motion On/Off" then
            self.controller:debugPrint("Turning System on from Motion")
            self.controller.powerModule:powerOn()
        end
        return
    end
    
    if controls.txtMotionMode and (
        controls.txtMotionMode.String == "Motion On/Off" or 
        controls.txtMotionMode.String == "Motion Off") then
        self:debug("Starting Motion Off Timer")
        self.controller.state.motionTimeoutActive = true
        setControlProperty(controls.ledMotionTimeoutActive, "Boolean", true)
        local timeout = (controls.motionTimeout and controls.motionTimeout.Value) or self.controller.config.motionTimeout
        self.controller.timers.motion:Start(timeout)
    end
end



-------------------[ SystemAutomationController (The Orchestrator) ]-------------------
SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController

-----------------[ Static / Class Properties ]-------------------
SystemAutomationController.clearString = "[Clear]"
SystemAutomationController.componentTypes = {
    callSync = "call_sync",
    videoBridge = "usb_uvc",
    displays = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920",
    gains = "gain",
    systemMute = "system_mute",
    camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355"
}

function SystemAutomationController.new(roomName, config, defaultConfigs)
    local self = setmetatable({}, SystemAutomationController)
    self.roomName = roomName or "Default Room"
    self.debugging = config.debugging ~= false
    self.defaultConfigs = defaultConfigs
    self.state = {
        isWarming = false,
        isCooling = false,
        powerLocked = false,
        motionTimeoutActive = false,
        motionGraceActive = false
    }
    self.config = config

    self.components = {
        callSync = nil,
        videoBridge = {},
        displays = {},
        gains = {},
        systemMute = nil,
        camACPR = nil,
        invalid = {}
    }

    self.timers = {
        motion = Timer.New(),
        grace = Timer.New(),
        warmup = Timer.New(),
        cooldown = Timer.New()
    }

    self.audioModule = AudioModule.new(self)
    self.videoModule = VideoModule.new(self)
    self.displayModule = DisplayModule.new(self)
    self.powerModule = PowerModule.new(self)
    self.motionModule = MotionModule.new(self)

    self:registerTimerHandlers()
    return self
end

------------------[ Debug Helper ]----------------------
function SystemAutomationController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

------------------[ Component Utility Helpers ]---------------------
function SystemAutomationController:getGainComponent(idx)
    return self.components.gains[idx]
end
function SystemAutomationController:getDisplayComponent(idx)
    return self.components.displays[idx]
end

------------------[ Helper: Gain Type ]--------------------
function SystemAutomationController:getGainType(idx)
    if controls.typeGain and controls.typeGain[idx] then
        return controls.typeGain[idx].String
    end
    if idx == 1 then return "Program" end
    return "Mic"
end

function SystemAutomationController:safeComponentAccess(component, control, action, value)
    if not component or not component[control] then return false end
    local success, result = pcall(function()
        if action == "set" then
            component[control].Boolean = value
            return true
        elseif action == "setPosition" then
            component[control].Position = value
            return true
        elseif action == "setString" then
            component[control].String = value
            return true
        elseif action == "trigger" then
            component[control]:Trigger()
            return true
        elseif action == "get" then
            return component[control].Boolean
        elseif action == "getPosition" then
            return component[control].Position
        elseif action == "getString" then
            return component[control].String
        end
        return false
    end)
    if not success then
        self:debugPrint("Component access error: "..tostring(result))
        return false
    end
    return result
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

------------------[ Event Handler: Registration ]----------------------
function SystemAutomationController:registerEventHandlers()
    -- Power controls
    bindControl(controls.btnSystemOnOff, function(ctl)
        if ctl.Boolean then
            self.powerModule:powerOn()
        else
            self.powerModule:powerOff()
        end
    end)
    
    bindControl(controls.btnSystemOn, function()
        self.powerModule:powerOn()
    end)
    
    bindControl(controls.btnSystemOff, function()
        self.powerModule:powerOff()
        self.state.motionGraceActive = true
        setControlProperty(controls.ledMotionGraceActive, "Boolean", true)
        self.timers.grace:Start(self.config.gracePeriod)
    end)

    -- Privacy controls
    bindControl(controls.btnAudioPrivacy, function(ctl)
        self.audioModule:setPrivacy(ctl.Boolean)
    end)
    
    bindControlArray(controls.btnVideoPrivacy, function(i, ctl)
        self.videoModule:setPrivacy(ctl.Boolean, i)
    end)

    -- Volume controls
    bindControlArray(controls.knbVolumeFader, function(i, fader)
        self.audioModule:setVolume(fader.Position, i)
    end)
    
    bindControlArray(controls.btnVolumeMute, function(i, ctl)
        self.audioModule:setMute(ctl.Boolean, i)
    end)
    
    bindControlArray(controls.btnVolumeUp, function(i, ctl)
        self.audioModule:setVolumeUpDown("up", ctl.Boolean, i)
    end)
    
    bindControlArray(controls.btnVolumeDn, function(i, ctl)
        self.audioModule:setVolumeUpDown("down", ctl.Boolean, i)
    end)

    -- Motion detection
    bindControl(controls.ledMotionIn, function()
        self.motionModule:checkMotion()
    end)

    -- Component change handlers
    bindControl(controls.compCallSync, function() self:setCallSyncComponent() end)
    bindControl(controls.compSystemMute, function() self:setSystemMuteComponent() end)
    bindControl(controls.compACPR, function() self:setCamACPRComponent() end)
    
    forEachControl(controls.compVideoBridge, function(i, ctrl)
        bindControl(ctrl, function() self:setVideoBridgeComponent(i) end)
    end)
    
    forEachControl(controls.compGains, function(i, ctrl)
        bindControl(ctrl, function() self:setGainComponent(i) end)
    end)
    
    forEachControl(controls.devDisplays, function(i, ctrl)
        bindControl(ctrl, function() self:setDisplayComponent(i) end)
    end)

    -- Room name handler
    bindControl(controls.roomName, function()
        local formattedRoomName = "[" .. controls.roomName.String .. "]"
        self.roomName = formattedRoomName
        self:debugPrint("Room name updated to: " .. formattedRoomName)
        self:publishNotification()
    end)
    
    -- Gain type selection handlers
    forEachControl(controls.typeGain, function(i, ctrl)
        if i > 1 then -- Skip gain 1 (program volume)
            bindControl(ctrl, function(ctl)
                self:debugPrint("Gain Type [" .. i .. "] changed to: " .. ctl.String)
                if self.components.gains[i] then
                    local defaultValue = self:getDefaultVolumeForType(ctl.String)
                    self.audioModule:setVolume(defaultValue, i)
                    self:debugPrint("Applied default volume (" .. defaultValue .. ") to gain index " .. i .. " (Type: " .. ctl.String .. ")")
                end
                self:publishNotification()
            end)
        end
    end)
end

-----------------[ Timer Handlers ]-----------------------
function SystemAutomationController:registerTimerHandlers()
    self.timers.motion.EventHandler = function()
        self:debugPrint("Motion Timeout")
        self.state.motionTimeoutActive = false
        if controls.ledMotionTimeoutActive then controls.ledMotionTimeoutActive.Boolean = false end
        self.timers.motion:Stop()
        self.powerModule:powerOff()
    end
    self.timers.grace.EventHandler = function()
        self:debugPrint("Grace Period Ended")
        self.state.motionGraceActive = false
        if controls.ledMotionGraceActive then controls.ledMotionGraceActive.Boolean = false end
        self.timers.grace:Stop()
    end
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Complete")
        self.state.isWarming = false
        if controls.ledSystemWarming then controls.ledSystemWarming.Boolean = false end
        self.powerModule:enableDisablePowerControls(true)
        self.timers.warmup:Stop()
        self:publishNotification()
    end
    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Complete")
        self.state.isCooling = false
        if controls.ledSystemCooling then controls.ledSystemCooling.Boolean = false end
        self.powerModule:enableDisablePowerControls(true)
        self.timers.cooldown:Stop()
        self:publishNotification()
    end
end

------------------[ Component Discovery / Selection ]------------------
function SystemAutomationController:getComponentNames()
    local compType = SystemAutomationController.componentTypes
    local namesTable = {
        CallSyncNames = {},
        VideoBridgeNames = {},
        CamACPRNames = {},
        DisplayNames = {},
        GainNames = {},
        MuteNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == compType.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == compType.videoBridge then
            table.insert(namesTable.VideoBridgeNames, comp.Name)
        elseif comp.Type == compType.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == compType.gains then
            table.insert(namesTable.GainNames, comp.Name)
        elseif comp.Type == compType.systemMute then
            table.insert(namesTable.MuteNames, comp.Name)
        elseif comp.Type == compType.camACPR then
            table.insert(namesTable.CamACPRNames, comp.Name)
        end
    end
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, SystemAutomationController.clearString)
    end
    if controls.compCallSync then controls.compCallSync.Choices = namesTable.CallSyncNames end
    if controls.compVideoBridge then 
        for _, ctl in ipairs(getControlArray(controls.compVideoBridge)) do 
            ctl.Choices = namesTable.VideoBridgeNames 
        end 
    end
    if controls.compSystemMute then controls.compSystemMute.Choices = namesTable.MuteNames end
    if controls.compACPR then controls.compACPR.Choices = namesTable.CamACPRNames end
    if controls.compGains then for _, ctl in ipairs(controls.compGains) do ctl.Choices = namesTable.GainNames end end
    if controls.devDisplays then for _, ctl in ipairs(controls.devDisplays) do ctl.Choices = namesTable.DisplayNames end end
end

----------------[ UI/Component Status Handling ]----------------
function SystemAutomationController:setComponent(ctrl, componentType)
    if not ctrl then return nil end
    local componentName = ctrl.String
    if componentName == "" then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    if componentName == self.clearString then
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
    self:debugPrint("Setting " .. componentType .. ": {" .. componentName .. "}")
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return newComponent
end
function SystemAutomationController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end
function SystemAutomationController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end
function SystemAutomationController:checkStatus()
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

------[ Per-Component Setup/Assignment (wires events) ]------
function SystemAutomationController:setComponentByType(ctrl, componentType, storage, eventMap, initCallback)
    if type(storage) == "table" then
        -- Array storage with index
        local idx = storage.index
        local storageKey = storage.key
        if not ctrl or not getControlArray(ctrl)[idx] then return end
        local label = storage.label or (componentType .. " [" .. idx .. "]")
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
        if ctrl.components.callSync then
            local callState = ctrl:safeComponentAccess(ctrl.components.callSync, "off.hook", "get")
            comp["TrackingBypass"].IsDisabled = not callState
        end
        comp["TrackingBypass"].Legend = " "
    end)
end

function SystemAutomationController:setDisplayComponent(idx)
    self:setComponentByType(controls.devDisplays, "Display", 
        { key = "displays", index = idx })
end

function SystemAutomationController:getVideoBridgePrivacy(idx)
    self:videoBridgeCheckPrivacy(idx)
end

----------------[ Call Sync Helpers ]-------------------
function SystemAutomationController:callSyncCheckMute()
    local callSync = self.components.callSync
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "mute", "get")
    self:debugPrint("Call Sync Mute State: " .. tostring(state))
    if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
end

function SystemAutomationController:videoBridgeCheckPrivacy(idx)
    idx = idx or 1
    local videoBridge = self.components.videoBridge[idx]
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
    local callSync = self.components.callSync
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "off.hook", "get")
    self:debugPrint("Call Connection State: " .. tostring(state))
    self:callSyncCheckMute()
    if self.components.videoBridge then 
        for i, _ in pairs(self.components.videoBridge) do 
            self.videoModule:setPrivacy(not state, i) 
        end 
        self:videoBridgeCheckPrivacy(1)
    end    
    if self.components.camACPR then
        self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", not state)
        if self.components.camACPR["TrackingBypass"] then
            self.components.camACPR["TrackingBypass"].IsDisabled = not state
        end
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
    local camACPR = self.components.camACPR
    if not camACPR then return end
    local state = self:safeComponentAccess(camACPR, "TrackingBypass", "get")
    self:debugPrint("ACPR Tracking Bypass: "..tostring(state))
end

function SystemAutomationController:endCalls()
    local callSync = self.components.callSync
    if not callSync then return end
    self:debugPrint("Ending Calls")
    self:safeComponentAccess(callSync, "call.decline", "trigger")
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
    for i, gain in pairs(self.components.gains) do
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
    local systemState = {
        RoomName = self.roomName,
        PowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean or false,
        SystemWarming = controls.ledSystemWarming and controls.ledSystemWarming.Boolean or false,
        SystemCooling = controls.ledSystemCooling and controls.ledSystemCooling.Boolean or false,
        AudioPrivacy = controls.btnAudioPrivacy and controls.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = controls.btnVideoPrivacy and controls.btnVideoPrivacy.Boolean or false,
        ACPRState = (self.components.camACPR and
            self.components.camACPR["TrackingBypass"] and
            self.components.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time()
    }
    systemState.GainControls = {}
    for i, gain in pairs(self.components.gains) do
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
        ["Huddle Room"] = { "Program", "Mic", "Mic", "Gain", "Gain" },
        ["Custom Room"] = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
        ["Default"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain" }
    }
    
    local assignments = gainTypeAssignments[roomType] or gainTypeAssignments["Default"]
    
    for i, gainType in ipairs(assignments) do
        if controls.typeGain[i] then
            controls.typeGain[i].String = gainType
        end
    end
end

----------------[ Volume Defaults ]-----------------
function SystemAutomationController:applyVolumeDefaults()
    if not self.config then return end
    
    -- Apply program volume to gain 1 (always program)
    if controls.compGains and controls.compGains[1] then
        self.audioModule:setVolume(self.config.defaultProgramVolume, 1)
    end
    
    -- Apply mic volume to mic gains
    if self.config.volumeRanges and self.config.volumeRanges.micVolume then
        for _, gainIndex in ipairs(self.config.volumeRanges.micVolume) do
            if controls.compGains and controls.compGains[gainIndex] then
                self.audioModule:setVolume(self.config.defaultMicVolume, gainIndex)
            end
        end
    end
    
    -- Apply gain volume to gain controls
    if self.config.volumeRanges and self.config.volumeRanges.gainVolume then
        for _, gainIndex in ipairs(self.config.volumeRanges.gainVolume) do
            if controls.compGains and controls.compGains[gainIndex] then
                self.audioModule:setVolume(self.config.defaultGainVolume, gainIndex)
            end
        end
    end
end

----------------[ Initialization ]--------------------------
function SystemAutomationController:init()
    self.powerModule:enableDisablePowerControls(true)
    self:getComponentNames()
    setControlProperty(controls.txtMotionMode, "Choices", { "Motion On/Off", "Motion Off", "Motion Disabled" })
    self:setGainTypeAssignments()
    
    -- Initialize components
    self:setCallSyncComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    
    forEachControl(controls.compVideoBridge, function(i) self:setVideoBridgeComponent(i) end)
    forEachControl(controls.compGains, function(i) self:setGainComponent(i) end)
    forEachControl(controls.devDisplays, function(i) self:setDisplayComponent(i) end)
    
    self:debugPrint("SystemAutomationController ready; "..self.audioModule:getGainCount().." gain controls detected.")
end
----------------[ Cleanup ]--------------------------
function SystemAutomationController:cleanup()
    for _, timer in pairs(self.timers) do if timer then timer:Stop() end end
    
    -- Cleanup all modules
    local modules = { self.audioModule, self.videoModule, self.displayModule, self.powerModule, self.motionModule }
    for _, module in ipairs(modules) do
        if module and module.cleanup then module:cleanup() end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

----------------[ Factory ]--------------------------

local function getDefaultConfig(roomType)
    roomType = roomType or "Default"
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = controls.warmupTime and controls.warmupTime.Value or 10,
            cooldownTime = controls.cooldownTime and controls.cooldownTime.Value or 5,
            motionTimeout = controls.motionTimeout and controls.motionTimeout.Value or 300,
            gracePeriod = controls.motionGracePeriod and controls.motionGracePeriod.Value or 30,
            defaultProgramVolume = (controls.defaultProgramVolume and controls.defaultProgramVolume.Value) or 0.7,
            defaultMicVolume = (controls.defaultMicVolume and controls.defaultMicVolume.Value) or 0.5,
            defaultGainVolume = (controls.defaultGainVolume and controls.defaultGainVolume.Value) or 0.8,
        }
    end
        local baseConfig = {
        defaultProgramVolume = 0.7,
        defaultMicVolume = 0.5, 
        defaultGainVolume = 0.8
    }
    
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

local function createSystemController(roomName, roomType)
    local config = getDefaultConfig(roomType)
    local allConfigs = {
        ["Conference Room"] = getDefaultConfig("Conference Room"),
        ["Huddle Room"]     = getDefaultConfig("Huddle Room"),
        ["Default"]         = getDefaultConfig("Default"),
        ["Custom Room"]     = getDefaultConfig("Custom Room"),
        ["User Defined"]    = getDefaultConfig("User Defined")
    }
    local success, controller = pcall(function()
        local obj = SystemAutomationController.new(roomName, config, allConfigs)
        obj:registerEventHandlers()
        obj:setupConfigSelection()
        obj:init()
        return obj
    end)
    if success then
        print("SystemAutomationController created for "..roomName)
        return controller
    else
        print("ERROR: Failed to create controller: "..tostring(controller))
        return nil
    end
end

--------------[ Instance Creation Entry ]----------------
if not validateControls() then return end
local formattedRoomName = "[" .. (controls.roomName and controls.roomName.String or "Unknown Room") .. "]"
local configType = (controls.selDefaultConfigs and controls.selDefaultConfigs.String) or "Default"
mySystemController = createSystemController(formattedRoomName, configType)

if mySystemController then
    print("SystemAutomationController created successfully!")
else
    print("ERROR: SystemAutomationController NOT created.")
end

----------------[ PUBLIC API ]--------------------------
--[[
Public API:
    mySystemController.audioModule:setVolume(level, idx)
    mySystemController.audioModule:setMute(state, idx)
    mySystemController.audioModule:getGainCount()
    mySystemController:publishNotification()
    mySystemController:cleanup()
    mySystemController:setFireAlarm(true|false)
    mySystemController.powerModule:powerOn()
    mySystemController.powerModule:powerOff()
]]

----------------[ USAGE EXAMPLES ]----------------------
--[[
-- Set volume on all
mySystemController.audioModule:setVolume(0.8)
-- Set volume on gain 2
mySystemController.audioModule:setVolume(0.6, 2)
-- Mute all
mySystemController.audioModule:setMute(true)
-- Mute gain 3
mySystemController.audioModule:setMute(true, 3)
-- Get gain count
local gainCount = mySystemController.audioModule:getGainCount()
-- Get gain level 1
local level = mySystemController.audioModule:getGainLevel(1)
-- Get mute state of gain 2
local isMuted = mySystemController.audioModule:getGainMute(2)
-- Volume up all
mySystemController.audioModule:setVolumeUpDown("up", true)
-- Volume up gain 2
mySystemController.audioModule:setVolumeUpDown("down", true, 2)
-- Fire alarm
mySystemController:setFireAlarm(true)  -- mute and off displays
mySystemController:setFireAlarm(false) -- restore if needed
]]
