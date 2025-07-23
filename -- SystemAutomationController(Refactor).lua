--[[ 
  System Automation Controller (Refactored, Lua Refactor Compliant)
  Author: Nikolas Smith, Q-SYS
  2025-07-22
  Version: 2.0
  Description: Refactored for event-driven, OOP, metatable-based architecture per Lua Refactoring Prompt. 
  Uses DisplayWallController (Sony Bravia) as reference for structure and best practices.
]]--

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

--------** Control Validation **--------
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

--------** Class Definition **--------
SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController

function SystemAutomationController.new(roomName, config)
    local self = setmetatable({}, SystemAutomationController)
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.componentTypes = {
        callSync = "call_sync",
        videoBridge = "usb_uvc",
        displays = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920",
        gains = "gain",
        systemMute = "system_mute",
        camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355"
    }
    self.components = {
        callSync = nil,
        videoBridge = nil,
        displays = {},
        gains = {},
        systemMute = nil,
        camACPR = nil,
        invalid = {}
    }
    self.state = {
        isWarming = false,
        isCooling = false,
        powerLocked = false,
        motionTimeoutActive = false,
        motionGraceActive = false
    }
    self.config = {
        motionChoices = {"Motion On/Off", "Motion Off", "Motion Disabled"},
        warmupTime = config and config.warmupTime or 10,
        cooldownTime = config and config.cooldownTime or 5,
        motionTimeout = config and config.motionTimeout or 300,
        gracePeriod = config and config.gracePeriod or 30,
        defaultVolume = config and config.defaultVolume or 0.7
    }
    self.timers = {
        motion = Timer.New(),
        grace = Timer.New(),
        warmup = Timer.New(),
        cooldown = Timer.New()
    }
    self:initAudioModule()
    self:initVideoModule()
    self:initDisplayModule()
    self:initMotionModule()
    self:initPowerModule()
    return self
end

--------** Debug Helper **--------
function SystemAutomationController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Safe Component Access **--------
function SystemAutomationController:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then component[control].Boolean = value; return true
            elseif action == "setPosition" then component[control].Position = value; return true
            elseif action == "setString" then component[control].String = value; return true
            elseif action == "trigger" then component[control]:Trigger(); return true
            elseif action == "get" then return component[control].Boolean
            elseif action == "getPosition" then return component[control].Position
            elseif action == "getString" then return component[control].String
            end
        end
        return false
    end)
    if not success then self:debugPrint("Component access error: "..tostring(result)) end
    return result
end

--------** Dynamic Component Discovery **--------
function SystemAutomationController:getComponentNames()
    local namesTable = {
        CallSyncNames = {},
        VideoBridgeNames = {},
        CamACPRNames = {},
        DisplayNames = {},
        GainNames = {},
        MuteNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == self.componentTypes.videoBridge then
            table.insert(namesTable.VideoBridgeNames, comp.Name)
        elseif comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.gains then
            table.insert(namesTable.GainNames, comp.Name)
        elseif comp.Type == self.componentTypes.systemMute then
            table.insert(namesTable.MuteNames, comp.Name)
        elseif comp.Type == self.componentTypes.camACPR then
            table.insert(namesTable.CamACPRNames, comp.Name)
        end
    end
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    if controls.compCallSync then controls.compCallSync.Choices = namesTable.CallSyncNames end
    if controls.compVideoBridge then controls.compVideoBridge.Choices = namesTable.VideoBridgeNames end
    if controls.compSystemMute then controls.compSystemMute.Choices = namesTable.MuteNames end
    if controls.compACPR then controls.compACPR.Choices = namesTable.CamACPRNames end
    if controls.compGains then for i, ctl in ipairs(controls.compGains) do ctl.Choices = namesTable.GainNames end end
    if controls.devDisplays then for i, ctl in ipairs(controls.devDisplays) do ctl.Choices = namesTable.DisplayNames end end
end

--------** Component Management **--------
function SystemAutomationController:setComponent(ctrl, componentType)
    local componentName = ctrl and ctrl.String or nil
    if not componentName or componentName == "" or componentName == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return nil
    end
    if #Component.GetControls(Component.New(componentName)) < 1 then
        if ctrl then
            ctrl.String = "[Invalid Component Selected]"
            ctrl.Color = "pink"
        end
        self:setComponentInvalid(componentType)
        return nil
    end
    if ctrl then ctrl.Color = "white" end
    self:setComponentValid(componentType)
    return Component.New(componentName)
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
    for _, v in pairs(self.components.invalid) do
        if v == true then
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

--------** Audio/Video/Display/Power/Motion Modules **--------
-- (Retain modular structure, but flatten logic, use early returns, direct UI updates, etc.)
-- ... (Retain and refactor all module initializations and methods as in DisplayWallController style) ...

--------** Audio Module **--------
function SystemAutomationController:initAudioModule()
    self.audioModule = {
        setVolume = function(level, gainIndex)
            if gainIndex then
                local gain = self.components.gains[gainIndex]
                if gain then
                    self:safeComponentAccess(gain, "gain", "setPosition", level)
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                for i, gain in pairs(self.components.gains) do
                    if gain then
                        self:safeComponentAccess(gain, "gain", "setPosition", level)
                        self:updateVolumeVisuals(i)
                    end
                end
            end
            self:publishNotification()
        end,
        setMute = function(state, gainIndex)
            if gainIndex then
                local gain = self.components.gains[gainIndex]
                if gain then
                    self:safeComponentAccess(gain, "mute", "set", state)
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                for i, gain in pairs(self.components.gains) do
                    if gain then
                        self:safeComponentAccess(gain, "mute", "set", state)
                        self:updateVolumeVisuals(i)
                    end
                end
            end
            self:publishNotification()
        end,
        setPrivacy = function(state)
            self:safeComponentAccess(self.components.callSync, "mute", "set", state)
            if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
            self:publishNotification()
        end,
        setSystemMute = function(state)
            if self.components.systemMute then
                self:safeComponentAccess(self.components.systemMute, "mute", "set", state)
            end
        end,
        setVolumeUpDown = function(direction, state, gainIndex)
            if gainIndex then
                local gain = self.components.gains[gainIndex]
                if gain then
                    local control = direction == "up" and "stepper.increase" or "stepper.decrease"
                    self:safeComponentAccess(gain, control, "set", state)
                    if state then
                        self:safeComponentAccess(gain, "mute", "set", false)
                    end
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                for i, gain in pairs(self.components.gains) do
                    if gain then
                        local control = direction == "up" and "stepper.increase" or "stepper.decrease"
                        self:safeComponentAccess(gain, control, "set", state)
                        if state then
                            self:safeComponentAccess(gain, "mute", "set", false)
                        end
                        self:updateVolumeVisuals(i)
                    end
                end
            end
            self:publishNotification()
        end,
        getGainCount = function()
            local count = 0
            for i, gain in pairs(self.components.gains) do
                if gain then count = count + 1 end
            end
            return count
        end,
        getGainLevel = function(gainIndex)
            local gain = self.components.gains[gainIndex]
            if gain then
                return self:safeComponentAccess(gain, "gain", "getPosition")
            end
            return 0
        end,
        getGainMute = function(gainIndex)
            local gain = self.components.gains[gainIndex]
            if gain then
                return self:safeComponentAccess(gain, "mute", "get")
            end
            return false
        end
    }
end

--------** Video Module **--------
function SystemAutomationController:initVideoModule()
    self.videoModule = {
        setPrivacy = function(state)
            self:safeComponentAccess(self.components.videoBridge, "toggle.privacy", "set", state)
            if controls.btnVideoPrivacy then controls.btnVideoPrivacy.Boolean = state end
            if self.components.camACPR then
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", state)
            end
            self:publishNotification()
        end,
        getPrivacyState = function()
            if self.components.videoBridge then
                local state = self:safeComponentAccess(self.components.videoBridge, "toggle.privacy", "get")
                if controls.btnVideoPrivacy then controls.btnVideoPrivacy.Boolean = state end
                self:publishNotification()
                return state
            end
            return false
        end
    }
end

--------** Display Module **--------
function SystemAutomationController:initDisplayModule()
    self.displayModule = {
        powerAll = function(state)
            for i, display in pairs(self.components.displays) do
                if display then
                    local control = state and "PowerOnTrigger" or "PowerOffTrigger"
                    self:safeComponentAccess(display, control, "trigger")
                end
            end
        end,
        powerSingle = function(index, state)
            local display = self.components.displays[index]
            if display then
                local control = state and "PowerOnTrigger" or "PowerOffTrigger"
                self:safeComponentAccess(display, control, "trigger")
            end
        end
    }
end

--------** Motion Module **--------
function SystemAutomationController:initMotionModule()
    self.motionModule = {
        checkMotion = function()
            self:debugPrint("Checking Motion")
            if controls.ledMotionIn and controls.ledMotionIn.Boolean then
                self.state.motionTimeoutActive = false
                if controls.ledMotionTimeoutActive then controls.ledMotionTimeoutActive.Boolean = false end
                self.timers.motion:Stop()
                if controls.ledSystemPower and not controls.ledSystemPower.Boolean and not self.state.motionGraceActive and controls.txtMotionMode and controls.txtMotionMode.String == "Motion On/Off" then
                    self:debugPrint("Turning System on from Motion")
                    self.powerModule.powerOn()
                end
            else
                if controls.txtMotionMode and (controls.txtMotionMode.String == "Motion On/Off" or controls.txtMotionMode.String == "Motion Off") then
                    self:debugPrint("Starting Motion Off Timer")
                    self.state.motionTimeoutActive = true
                    if controls.ledMotionTimeoutActive then controls.ledMotionTimeoutActive.Boolean = true end
                    self.timers.motion:Start(controls.motionTimeout and controls.motionTimeout.Value or self.config.motionTimeout)
                end
            end
        end
    }
end

--------** Power Module **--------
function SystemAutomationController:initPowerModule()
    self.powerModule = {
        enableDisablePowerControls = function(state)
            if controls.btnSystemOnOff then controls.btnSystemOnOff.IsDisabled = not state end
            if controls.btnSystemOn then controls.btnSystemOn.IsDisabled = not state end
            if controls.btnSystemOff then controls.btnSystemOff.IsDisabled = not state end
        end,
        setSystemPowerFB = function(state)
            if controls.ledSystemPower then controls.ledSystemPower.Boolean = state end
            if controls.btnSystemOnOff then controls.btnSystemOnOff.Boolean = state end
            if controls.btnSystemOn then controls.btnSystemOn.Boolean = state end
            if controls.btnSystemOff then controls.btnSystemOff.Boolean = not state end
        end,
        powerOn = function()
            self:debugPrint("Powering System On")
            if controls.btnSystemOnTrig then controls.btnSystemOnTrig:Trigger() end
            self.powerModule.enableDisablePowerControls(false)
            self.state.isWarming = true
            if controls.ledSystemWarming then controls.ledSystemWarming.Boolean = true end
            self.timers.warmup:Start(self.config.warmupTime)
            self.powerModule.setSystemPowerFB(true)
            self.audioModule.setVolume(self.config.defaultVolume)
            self.audioModule.setMute(false)
            self.audioModule.setPrivacy(true)
            self.displayModule.powerAll(true)
            self:publishNotification()
        end,
        powerOff = function()
            self:debugPrint("Powering System Off")
            if controls.btnSystemOffTrig then controls.btnSystemOffTrig:Trigger() end
            self.powerModule.enableDisablePowerControls(false)
            self.state.isCooling = true
            if controls.ledSystemCooling then controls.ledSystemCooling.Boolean = true end
            self.timers.cooldown:Start(self.config.cooldownTime)
            self.powerModule.setSystemPowerFB(false)
            self.audioModule.setPrivacy(true)
            self.audioModule.setMute(true)
            self.videoModule.setPrivacy(true)
            self.displayModule.powerAll(false)
            self:endCalls()
            self:publishNotification()
        end
    }
end

--------** Helper Functions **--------
function SystemAutomationController:callSyncCheckMute()
    if self.components.callSync ~= nil then
        local state = self:safeComponentAccess(self.components.callSync, "mute", "get")
        self:debugPrint("Call Sync Mute State is: " .. tostring(state))
        if controls.btnAudioPrivacy then controls.btnAudioPrivacy.Boolean = state end
    end
end

function SystemAutomationController:callSyncCheckConnection()
    if self.components.callSync ~= nil then
        local state = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
        self:debugPrint("Call Connection State: " .. tostring(state))
        self:callSyncCheckMute()
        self.videoModule.setPrivacy(not state)
        if self.components.camACPR then
            self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", not state)
            if self.components.camACPR["TrackingBypass"] then
                self.components.camACPR["TrackingBypass"].IsDisabled = not state
            end
        end
    end
end

function SystemAutomationController:updateACPRTrackingBypass()
    if self.components.camACPR then
        local state = self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "get")
        self:debugPrint("ACPR Tracking Bypass State: " .. tostring(state))
    end
end

function SystemAutomationController:endCalls()
    if self.components.callSync ~= nil then
        self:debugPrint("Ending Calls")
        self:safeComponentAccess(self.components.callSync, "call.decline", "trigger")
    end
end

function SystemAutomationController:updateVolumeVisuals(gainIndex)
    gainIndex = gainIndex or 1
    local volumeFader = controls.knbVolumeFader and controls.knbVolumeFader[gainIndex]
    local volumeMute = controls.btnVolumeMute and controls.btnVolumeMute[gainIndex]
    if volumeFader and volumeMute then
        if volumeMute.Boolean then
            volumeMute.CssClass = "icon-volume_mute"
            volumeFader.Color = "#CCCCCC"
        else
            volumeMute.CssClass = "icon-volume_off"
            volumeFader.Color = "#0561A5"
        end
    end
end

function SystemAutomationController:getVolumeLvl(gainIndex)
    gainIndex = gainIndex or 1
    local gain = self.components.gains[gainIndex]
    if gain ~= nil then
        local level = self:safeComponentAccess(gain, "gain", "getPosition")
        if controls.knbVolumeFader and controls.knbVolumeFader[gainIndex] then
            controls.knbVolumeFader[gainIndex].Position = level
        end
        self:updateVolumeVisuals(gainIndex)
        self:publishNotification()
    end
end

function SystemAutomationController:getVolumeMute(gainIndex)
    gainIndex = gainIndex or 1
    local gain = self.components.gains[gainIndex]
    if gain ~= nil then
        local state = self:safeComponentAccess(gain, "mute", "get")
        if controls.btnVolumeMute and controls.btnVolumeMute[gainIndex] then
            controls.btnVolumeMute[gainIndex].Boolean = state
        end
        self:updateVolumeVisuals(gainIndex)
        self:publishNotification()
    end
end

function SystemAutomationController:setFireAlarm(state)
    if state then
        self.audioModule.setSystemMute(true)
        self.displayModule.powerAll(false)
    else
        if controls.ledSystemPower and controls.ledSystemPower.Boolean then
            self.audioModule.setSystemMute(false)
            self.displayModule.powerAll(true)
        end
    end
end

function SystemAutomationController:publishNotification()
    local systemState = {
        RoomName = self.roomName,
        PowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean or false,
        SystemWarming = controls.ledSystemWarming and controls.ledSystemWarming.Boolean or false,
        SystemCooling = controls.ledSystemCooling and controls.ledSystemCooling.Boolean or false,
        AudioPrivacy = controls.btnAudioPrivacy and controls.btnAudioPrivacy.Boolean or false,
        VideoPrivacy = controls.btnVideoPrivacy and controls.btnVideoPrivacy.Boolean or false,
        ACPRState = (self.components.camACPR and self.components.camACPR["TrackingBypass"] and self.components.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time()
    }
    systemState.GainControls = {}
    for i, gain in pairs(self.components.gains) do
        if gain then
            systemState.GainControls[i] = {
                Level = self.audioModule.getGainLevel(i),
                Muted = self.audioModule.getGainMute(i)
            }
        end
    end
    if controls.txtNotificationID and controls.txtNotificationID.String ~= "" then
        Notifications.Publish(controls.txtNotificationID.String, systemState)
    end
end

--------** Event Handler Registration **--------
function SystemAutomationController:registerEventHandlers()
    -- Power controls
    if controls.btnSystemOnOff then
        controls.btnSystemOnOff.EventHandler = function(ctl)
            if ctl.Boolean then self.powerModule.powerOn() else self.powerModule.powerOff() end
        end
    end
    if controls.btnSystemOn then
        controls.btnSystemOn.EventHandler = function() self.powerModule.powerOn() end
    end
    if controls.btnSystemOff then
        controls.btnSystemOff.EventHandler = function()
            self.powerModule.powerOff()
            self.state.motionGraceActive = true
            if controls.ledMotionGraceActive then controls.ledMotionGraceActive.Boolean = true end
            self.timers.grace:Start(self.config.gracePeriod)
        end
    end
    -- Privacy controls
    if controls.btnAudioPrivacy then
        controls.btnAudioPrivacy.EventHandler = function(ctl) self.audioModule.setPrivacy(ctl.Boolean) end
    end
    if controls.btnVideoPrivacy then
        controls.btnVideoPrivacy.EventHandler = function(ctl) self.videoModule.setPrivacy(ctl.Boolean) end
    end
    -- Volume controls
    if controls.knbVolumeFader then
        for i, fader in ipairs(controls.knbVolumeFader) do
            fader.EventHandler = function() self.audioModule.setVolume(fader.Position, i) end
        end
    end
    if controls.btnVolumeMute then
        for i, muteBtn in ipairs(controls.btnVolumeMute) do
            muteBtn.EventHandler = function(ctl) self.audioModule.setMute(ctl.Boolean, i) end
        end
    end
    if controls.btnVolumeUp then
        for i, upBtn in ipairs(controls.btnVolumeUp) do
            upBtn.EventHandler = function(ctl) self.audioModule.setVolumeUpDown("up", ctl.Boolean, i) end
        end
    end
    if controls.btnVolumeDn then
        for i, downBtn in ipairs(controls.btnVolumeDn) do
            downBtn.EventHandler = function(ctl) self.audioModule.setVolumeUpDown("down", ctl.Boolean, i) end
        end
    end
    -- Motion detection
    if controls.ledMotionIn then
        controls.ledMotionIn.EventHandler = function() self.motionModule.checkMotion() end
    end
    -- Component selection handlers
    if controls.compCallSync then controls.compCallSync.EventHandler = function() self:setCallSyncComponent() end end
    if controls.compVideoBridge then controls.compVideoBridge.EventHandler = function() self:setVideoBridgeComponent() end end
    if controls.compSystemMute then controls.compSystemMute.EventHandler = function() self:setSystemMuteComponent() end end
    if controls.compACPR then controls.compACPR.EventHandler = function() self:setCamACPRComponent() end end
    if controls.compGains then for i, gainComp in ipairs(controls.compGains) do gainComp.EventHandler = function() self:setGainComponent(i) end end end
    if controls.devDisplays then for i, v in ipairs(controls.devDisplays) do v.EventHandler = function() self:setDisplayComponent(i) end end end
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

--------** Configuration Selection **--------
function SystemAutomationController:setupConfigSelection()
    -- Set up the choices for the configuration selector
    controls.selDefaultConfigs.Choices = {
        "Conference Room",
        "Huddle Room",
        "Default",
        "Custom Room",
        "User Defined"
    }

    -- Define control mappings with array support
    local controlMappings = {
        { control = "warmupTime", config = "warmupTime", isArray = false },
        { control = "cooldownTime", config = "cooldownTime", isArray = false },
        { control = "motionTimeout", config = "motionTimeout", isArray = false },
        { control = "motionGracePeriod", config = "gracePeriod", isArray = false },
        { control = "defaultVolume", config = "defaultVolume", isArray = true, index = 1 }
    }

    -- Function to update control values based on selected configuration
    local function updateControlValues(configType)
        local config = self.defaultConfigs[configType]
        if not config then return end

        -- Enable/Disable controls based on configuration type
        local isUserDefined = configType == "User Defined"
        for _, mapping in ipairs(controlMappings) do
            local control = mapping.isArray and controls[mapping.control][mapping.index] or controls[mapping.control]
            if control then
                control.Value = config[mapping.config]
                control.IsDisabled = not isUserDefined
            end
        end
    end

    -- Event handler for configuration selection
    controls.selDefaultConfigs.EventHandler = function(ctl)
        updateControlValues(ctl.String)
    end

    -- Event handlers for User Defined mode using loop
    for _, mapping in ipairs(controlMappings) do
        local control = mapping.isArray and controls[mapping.control][mapping.index] or controls[mapping.control]
        if control then
            control.EventHandler = function(ctl)
                if controls.selDefaultConfigs.String == "User Defined" then
                    self.defaultConfigs["User Defined"][mapping.config] = ctl.Value
                end
            end
        end
    end

    -- Initialize with default selection
    controls.selDefaultConfigs.String = "Default"
    updateControlValues("Default")
end

--------** Initialization **--------
function SystemAutomationController:funcInit()
    self:getComponentNames()
    self:registerEventHandlers()
    if controls.txtMotionMode then controls.txtMotionMode.Choices = self.config.motionChoices end
    self:setCallSyncComponent()
    self:setVideoBridgeComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    if controls.compGains then for i, gainComp in ipairs(controls.compGains) do self:setGainComponent(i) end end
    if controls.devDisplays then for i, v in ipairs(controls.devDisplays) do self:setDisplayComponent(i) end end
    self:debugPrint("System Automation Controller Initialized with " .. (self.audioModule and self.audioModule.getGainCount() or 0) .. " gain controls")
end

--------** Factory Function **--------
local function createSystemAutomationController(roomName, roomType)
    local defaultConfigs = {
        ["Conference Room"] = {
            debugging = true,
            warmupTime = 15,
            cooldownTime = 10,
            motionTimeout = 600,
            gracePeriod = 60,
            defaultVolume = 0.7
        },
        ["Huddle Room"] = {
            debugging = false,
            warmupTime = 5,
            cooldownTime = 3,
            motionTimeout = 300,
            gracePeriod = 30,
            defaultVolume = 0.6
        },
        ["Default"] = {
            debugging = true,
            warmupTime = 10,
            cooldownTime = 5,
            motionTimeout = 300,
            gracePeriod = 30,
            defaultVolume = 0.7
        },
        ["Custom Room"] = {
            debugging = true,
            warmupTime = 10,
            cooldownTime = 5,
            motionTimeout = 300,
            gracePeriod = 30,
            defaultVolume = 0.7
        },
        ["User Defined"] = {
            debugging = true,
            warmupTime = controls.warmupTime.Value,
            cooldownTime = controls.cooldownTime.Value,
            motionTimeout = controls.motionTimeout.Value,
            gracePeriod = controls.motionGracePeriod.Value,
            defaultVolume = controls.defaultVolume[1].Value
        }
    }
    local roomConfig = defaultConfigs[roomType] or defaultConfigs["Default"]
    local success, controller = pcall(function()
        local instance = SystemAutomationController.new(roomName, roomConfig)
        instance.defaultConfigs = defaultConfigs
        instance:setupConfigSelection()
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created SystemAutomationController for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
if not validateControls() then return end
local formattedRoomName = "[" .. controls.roomName.String .. "]"
mySystemAutomationController = createSystemAutomationController(formattedRoomName, controls.selDefaultConfigs.String)
if mySystemAutomationController then
    print("SystemAutomationController created successfully!")
else
    print("ERROR: Failed to create SystemAutomationController!")
end