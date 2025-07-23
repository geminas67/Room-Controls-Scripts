--[[
    System Automation Controller (Refactored OOP, Modular, Modern Lua)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2025-07-23

    Implements strict OOP / modular structure per Lua Refactoring Guidelines.
    Each logical area (audio, power, video, etc.) is its own class with methods.
    Controller is shallow, event registration is DRY, logic is delegated.
    Debugging and config are standardized.
]]

--------** Control References **--------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    compCallSync = Controls.compCallSync,
    compVideoBridge = Controls.compVideoBridge,
    compSystemMute = Controls.compSystemMute,
    compACPR = Controls.compACPR,
    compGains = Controls.compGains,
    devDisplays = Controls.devDisplays,
    selDefaultConfigs = Controls.selDefaultConfigs,
    warmupTime = Controls.warmupTime,
    cooldownTime = Controls.cooldownTime,
    motionTimeout = Controls.motionTimeout,
    motionGracePeriod = Controls.motionGracePeriod,
    defaultVolume = Controls.defaultVolume,
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
local function registerHandlers(controlArray, callback)
    for i, ctrl in ipairs(controlArray) do
        ctrl.EventHandler = function(ctl) callback(i, ctl) end
    end
end

local function isArr(t)
    -- is this table an array? (index 1 exists)
    return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

-------------------[ Audio Module ]------------------------
AudioModule = {}
AudioModule.__index = AudioModule

function AudioModule.new(controller)
    local self = setmetatable({}, AudioModule)
    self.controller = controller
    self:debug("AudioModule constructed")
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

function AudioModule:cleanup()
    -- nothing needed unless you wire events directly here
end

function AudioModule:debug(str) self.controller:debugPrint("[Audio] "..str) end

-------------------[ Video Module ]------------------------
VideoModule = {}
VideoModule.__index = VideoModule
function VideoModule.new(controller)
    local self = setmetatable({}, VideoModule)
    self.controller = controller
    self:debug("VideoModule constructed")
    return self
end

function VideoModule:setPrivacy(state)
    local videoBridge = self.controller.components.videoBridge
    self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "set", state)
    if controls.btnVideoPrivacy then controls.btnVideoPrivacy.Boolean = state end
    local camACPR = self.controller.components.camACPR
    if camACPR then
        self.controller:safeComponentAccess(camACPR, "TrackingBypass", "set", state)
    end
    self.controller:publishNotification()
end

function VideoModule:getPrivacyState()
    local videoBridge = self.controller.components.videoBridge
    if not videoBridge then return false end
    local state = self.controller:safeComponentAccess(videoBridge, "toggle.privacy", "get")
    if controls.btnVideoPrivacy then controls.btnVideoPrivacy.Boolean = state end
    self.controller:publishNotification()
    return state
end

function VideoModule:cleanup() end
function VideoModule:debug(str) self.controller:debugPrint("[Video] "..str) end

-------------------[ Display Module ]----------------------
DisplayModule = {}
DisplayModule.__index = DisplayModule
function DisplayModule.new(controller)
    local self = setmetatable({}, DisplayModule)
    self.controller = controller
    self:debug("DisplayModule constructed")
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

function DisplayModule:cleanup() end
function DisplayModule:debug(str) self.controller:debugPrint("[Display] "..str) end

-------------------[ Power Module ]------------------------
PowerModule = {}
PowerModule.__index = PowerModule

function PowerModule.new(controller)
    local self = setmetatable({}, PowerModule)
    self.controller = controller
    self:debug("PowerModule constructed")
    return self
end

function PowerModule:enableDisablePowerControls(state)
    if controls.btnSystemOnOff then controls.btnSystemOnOff.IsDisabled = not state end
    if controls.btnSystemOn then controls.btnSystemOn.IsDisabled = not state end
    if controls.btnSystemOff then controls.btnSystemOff.IsDisabled = not state end
end

function PowerModule:setSystemPowerFB(state)
    if controls.ledSystemPower then controls.ledSystemPower.Boolean = state end
    if controls.btnSystemOnOff then controls.btnSystemOnOff.Boolean = state end
    if controls.btnSystemOn then controls.btnSystemOn.Boolean = state end
    if controls.btnSystemOff then controls.btnSystemOff.Boolean = not state end
end

function PowerModule:powerOn()
    self:debug("Powering On")
    if controls.btnSystemOnTrig then controls.btnSystemOnTrig:Trigger() end
    self:enableDisablePowerControls(false)
    self.controller.state.isWarming = true
    if controls.ledSystemWarming then controls.ledSystemWarming.Boolean = true end
    self.controller.timers.warmup:Start(self.controller.config.warmupTime)
    self:setSystemPowerFB(true)
    self.controller.audioModule:setVolume(self.controller.config.defaultVolume)
    self.controller.audioModule:setMute(false)
    self.controller.audioModule:setPrivacy(true)
    self.controller.displayModule:powerAll(true)
    self.controller:publishNotification()
end

function PowerModule:powerOff()
    self:debug("Powering Off")
    if controls.btnSystemOffTrig then controls.btnSystemOffTrig:Trigger() end
    self:enableDisablePowerControls(false)
    self.controller.state.isCooling = true
    if controls.ledSystemCooling then controls.ledSystemCooling.Boolean = true end
    self.controller.timers.cooldown:Start(self.controller.config.cooldownTime)
    self:setSystemPowerFB(false)
    self.controller.audioModule:setPrivacy(true)
    self.controller.audioModule:setMute(true)
    self.controller.videoModule:setPrivacy(true)
    self.controller.displayModule:powerAll(false)
    self.controller:endCalls()
    self.controller:publishNotification()
end

function PowerModule:cleanup() end
function PowerModule:debug(str) self.controller:debugPrint("[Power] "..str) end

-------------------[ Motion Module ]-----------------------
MotionModule = {}
MotionModule.__index = MotionModule

function MotionModule.new(controller)
    local self = setmetatable({}, MotionModule)
    self.controller = controller
    self:debug("MotionModule constructed")
    return self
end

function MotionModule:checkMotion()
    self:debug("Checking Motion")
    if controls.ledMotionIn and controls.ledMotionIn.Boolean then
        self.controller.state.motionTimeoutActive = false
        if controls.ledMotionTimeoutActive then controls.ledMotionTimeoutActive.Boolean = false end
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
        controls.txtMotionMode.String == "Motion On/Off" or controls.txtMotionMode.String == "Motion Off") then
        self:debug("Starting Motion Off Timer")
        self.controller.state.motionTimeoutActive = true
        if controls.ledMotionTimeoutActive then controls.ledMotionTimeoutActive.Boolean = true end
        local timeout = (controls.motionTimeout and controls.motionTimeout.Value) or self.controller.config.motionTimeout
        self.controller.timers.motion:Start(timeout)
    end
end

function MotionModule:cleanup() end
function MotionModule:debug(str) self.controller:debugPrint("[Motion] "..str) end

--- SystemAutomationController (The Orchestrator) ---------
SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController

--** static/class properties
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
        videoBridge = nil,
        displays = {},
        gains = {},
        systemMute = nil,
        camACPR = nil,
        invalid = {}
    }

    -- Timer objects for motion, warmup/cooldown, grace
    self.timers = {
        motion = Timer.New(),
        grace = Timer.New(),
        warmup = Timer.New(),
        cooldown = Timer.New()
    }

    -- Module initialization
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

------------------[ Event Handler: Registration ]----------------------
function SystemAutomationController:registerEventHandlers()
    -- Power controls
    if controls.btnSystemOnOff then
        controls.btnSystemOnOff.EventHandler = function(ctl)
            if ctl.Boolean then
                self.powerModule:powerOn()
            else
                self.powerModule:powerOff()
            end
        end
    end
    if controls.btnSystemOn then
        controls.btnSystemOn.EventHandler = function()
            self.powerModule:powerOn()
        end
    end
    if controls.btnSystemOff then
        controls.btnSystemOff.EventHandler = function()
            self.powerModule:powerOff()
            self.state.motionGraceActive = true
            if controls.ledMotionGraceActive then controls.ledMotionGraceActive.Boolean = true end
            self.timers.grace:Start(self.config.gracePeriod)
        end
    end

    -- Audio/Video privacy
    if controls.btnAudioPrivacy then
        controls.btnAudioPrivacy.EventHandler = function(ctl)
            self.audioModule:setPrivacy(ctl.Boolean)
        end
    end
    if controls.btnVideoPrivacy then
        controls.btnVideoPrivacy.EventHandler = function(ctl)
            self.videoModule:setPrivacy(ctl.Boolean)
        end
    end

    -- Volume/knob/mute/up/down
    if controls.knbVolumeFader then
        registerHandlers(getControlArray(controls.knbVolumeFader), function(i, fader)
            self.audioModule:setVolume(fader.Position, i)
        end)
    end
    if controls.btnVolumeMute then
        registerHandlers(getControlArray(controls.btnVolumeMute), function(i, ctl)
            self.audioModule:setMute(ctl.Boolean, i)
        end)
    end
    if controls.btnVolumeUp then
        registerHandlers(getControlArray(controls.btnVolumeUp), function(i, ctl)
            self.audioModule:setVolumeUpDown("up", ctl.Boolean, i)
        end)
    end
    if controls.btnVolumeDn then
        registerHandlers(getControlArray(controls.btnVolumeDn), function(i, ctl)
            self.audioModule:setVolumeUpDown("down", ctl.Boolean, i)
        end)
    end

    -- Motion detection
    if controls.ledMotionIn then
        controls.ledMotionIn.EventHandler = function()
            self.motionModule:checkMotion()
        end
    end

    -- Component dropdown selection/assignment
    if controls.compCallSync then controls.compCallSync.EventHandler = function() self:setCallSyncComponent() end end
    if controls.compVideoBridge then controls.compVideoBridge.EventHandler = function() self:setVideoBridgeComponent() end end
    if controls.compSystemMute then controls.compSystemMute.EventHandler = function() self:setSystemMuteComponent() end end
    if controls.compACPR then controls.compACPR.EventHandler = function() self:setCamACPRComponent() end end

    if controls.compGains then
        for i, _ in ipairs(controls.compGains) do
            controls.compGains[i].EventHandler = function() self:setGainComponent(i) end
        end
    end
    if controls.devDisplays then
        for i, _ in ipairs(controls.devDisplays) do
            controls.devDisplays[i].EventHandler = function() self:setDisplayComponent(i) end
        end
    end

    -- Room name handler
    if controls.roomName then
        controls.roomName.EventHandler = function()
            local formattedRoomName = "[" .. controls.roomName.String .. "]"
            self.roomName = formattedRoomName
            self:debugPrint("Room name updated to: " .. formattedRoomName)
            self:publishNotification()
        end
    end
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
    local ct = SystemAutomationController.componentTypes
    local namesTable = {
        CallSyncNames = {},
        VideoBridgeNames = {},
        CamACPRNames = {},
        DisplayNames = {},
        GainNames = {},
        MuteNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == ct.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == ct.videoBridge then
            table.insert(namesTable.VideoBridgeNames, comp.Name)
        elseif comp.Type == ct.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == ct.gains then
            table.insert(namesTable.GainNames, comp.Name)
        elseif comp.Type == ct.systemMute then
            table.insert(namesTable.MuteNames, comp.Name)
        elseif comp.Type == ct.camACPR then
            table.insert(namesTable.CamACPRNames, comp.Name)
        end
    end
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, SystemAutomationController.clearString)
    end
    if controls.compCallSync then controls.compCallSync.Choices = namesTable.CallSyncNames end
    if controls.compVideoBridge then controls.compVideoBridge.Choices = namesTable.VideoBridgeNames end
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
function SystemAutomationController:setCallSyncComponent()
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    local callSync = self.components.callSync
    if not callSync then return end
    callSync["off.hook"].EventHandler = function() self:callSyncCheckConnection() end
    callSync["mute"].EventHandler = function() self:callSyncCheckMute() end
end
function SystemAutomationController:setVideoBridgeComponent()
    self.components.videoBridge = self:setComponent(controls.compVideoBridge, "Video Bridge")
    local vb = self.components.videoBridge
    if not vb then return end
    vb["toggle.privacy"].EventHandler = function() self.videoModule:getPrivacyState() end
end
function SystemAutomationController:setGainComponent(idx)
    if not controls.compGains or not controls.compGains[idx] then return end
    local label = idx == 1 and "Program Volume [Gain 1]" or "Gain [" .. idx .. "]"
    self.components.gains[idx] = self:setComponent(controls.compGains[idx], label)
    if not self.components.gains[idx] then return end
    self:getVolumeLvl(idx)
    self:getVolumeMute(idx)
    local gain = self.components.gains[idx]
    gain["gain"].EventHandler = function() self:getVolumeLvl(idx) end
    gain["mute"].EventHandler = function() self:getVolumeMute(idx) end
end
function SystemAutomationController:setSystemMuteComponent()
    self.components.systemMute = self:setComponent(controls.compSystemMute, "System Mute")
end
function SystemAutomationController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(controls.compACPR, "Camera ACPR")
    local camACPR = self.components.camACPR
    if not camACPR then return end
    camACPR["TrackingBypass"].EventHandler = function() self:updateACPRTrackingBypass() end
    if self.components.callSync then
        local callState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
        camACPR["TrackingBypass"].IsDisabled = not callState
    end
    camACPR["TrackingBypass"].Legend = " "
end
function SystemAutomationController:setDisplayComponent(idx)
    self.components.displays[idx] = self:setComponent(controls.devDisplays[idx], "Display [" .. idx .. "]")
end

----------------[ Call Sync Helpers ]-------------------
function SystemAutomationController:callSyncCheckMute()
    local callSync = self.components.callSync
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "mute", "get")
    self:debugPrint("Call Sync Mute State: " .. tostring(state))
    if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
end
function SystemAutomationController:callSyncCheckConnection()
    local callSync = self.components.callSync
    if not callSync then return end
    local state = self:safeComponentAccess(callSync, "off.hook", "get")
    self:debugPrint("Call Connection State: " .. tostring(state))
    self:callSyncCheckMute()
    self.videoModule:setPrivacy(not state)
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
        { control = "defaultVolume", config = "defaultVolume", array = true, idx = 1 }
    }
    local function updateControlValues(configType)
        local conf = self.defaultConfigs[configType]
        if not conf then return end
        local isUser = configType == "User Defined"
        for _, map in ipairs(mappings) do
            local ctl = (map.array and controls[map.control][map.idx]) or controls[map.control]
            if ctl then
                ctl.Value = conf[map.config]
                ctl.IsDisabled = not isUser
            end
        end
    end
    controls.selDefaultConfigs.EventHandler = function(ctl)
        updateControlValues(ctl.String)
    end
    for _, map in ipairs(mappings) do
        local ctl = (map.array and controls[map.control][map.idx]) or controls[map.control]
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

-------------------[ INIT ]--------------------------
function SystemAutomationController:init()
    self.powerModule:enableDisablePowerControls(true)
    self.videoModule:getPrivacyState()
    self:getComponentNames()
    if controls.txtMotionMode then controls.txtMotionMode.Choices = { "Motion On/Off", "Motion Off", "Motion Disabled" } end
    self:setCallSyncComponent()
    self:setVideoBridgeComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    if controls.compGains then for i, _ in ipairs(controls.compGains) do self:setGainComponent(i) end end
    if controls.devDisplays then for i, _ in ipairs(controls.devDisplays) do self:setDisplayComponent(i) end end
    self:debugPrint("SystemAutomationController ready; "..self.audioModule:getGainCount().." gain controls detected.")
end
-------------------[ CLEANUP ]--------------------------
function SystemAutomationController:cleanup()
    for _, timer in pairs(self.timers) do if timer then timer:Stop() end end
    self.audioModule:cleanup()
    self.videoModule:cleanup()
    self.displayModule:cleanup()
    self.powerModule:cleanup()
    self.motionModule:cleanup()
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

-------------------[ Factory ]--------------------------
local function getDefaultConfig(roomType)
    roomType = roomType or "Default"
    if roomType == "User Defined" then
        return {
            debugging = true,
            warmupTime = controls.warmupTime and controls.warmupTime.Value or 10,
            cooldownTime = controls.cooldownTime and controls.cooldownTime.Value or 5,
            motionTimeout = controls.motionTimeout and controls.motionTimeout.Value or 300,
            gracePeriod = controls.motionGracePeriod and controls.motionGracePeriod.Value or 30,
            defaultVolume = controls.defaultVolume and controls.defaultVolume[1] and controls.defaultVolume[1].Value or 0.7
        }
    end
    local defaults = {
        ["Conference Room"] =   { debugging = true,  warmupTime = 15, cooldownTime = 10, motionTimeout = 600, gracePeriod = 60,  defaultVolume = 0.7 },
        ["Huddle Room"]     =   { debugging = false, warmupTime = 5,  cooldownTime = 3,  motionTimeout = 300, gracePeriod = 30,  defaultVolume = 0.6 },
        ["Default"]         =   { debugging = true,  warmupTime = 10, cooldownTime = 5,  motionTimeout = 300, gracePeriod = 30,  defaultVolume = 0.7 },
        ["Custom Room"]     =   { debugging = true,  warmupTime = 10, cooldownTime = 5,  motionTimeout = 300, gracePeriod = 30,  defaultVolume = 0.7 }
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
