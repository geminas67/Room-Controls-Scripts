--[[ 
  System Automation Helper Script - Modular Version with Gain Table
  Author: Nikolas Smith, Q-SYS
  2025-06-20
  Firmware Req: 10.0.0
  Version: 1.0

  Class-based implementation maintaining simplicity of functional approach
]] --

-- SystemAutomationController class
SystemAutomationController = {}
SystemAutomationController.__index = SystemAutomationController

--------** Class Constructor **--------
function SystemAutomationController.new(roomName, config)
    local self = setmetatable({}, SystemAutomationController)
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        videoBridge = "usb_uvc",
        displays = "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920", -- Generic Display Plugin
        gains = "gain",
        systemMute = "system_mute",
        camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
    }
    
    -- Component storage
    self.components = {
        callSync = nil,
        videoBridge = nil,
        displays = {},
        gains = {}, -- Table structure for all gain controls
        systemMute = nil,
        camACPR = nil, -- ACPR component
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        isWarming = false,
        isCooling = false,
        powerLocked = false,
        motionTimeoutActive = false,
        motionGraceActive = false
    }
    
    -- Configuration
    self.config = {
        motionChoices = {"Motion On/Off", "Motion Off", "Motion Disabled"},
        warmupTime = config and config.warmupTime or 10,
        cooldownTime = config and config.cooldownTime or 5,
        motionTimeout = config and config.motionTimeout or 300,
        gracePeriod = config and config.gracePeriod or 30,
        defaultVolume = config and config.defaultVolume or 0.7
    }
    
    -- Timers
    self.timers = {
        motion = Timer.New(),
        grace = Timer.New(),
        warmup = Timer.New(),
        cooldown = Timer.New()
    }
    
    -- Initialize modules
    self:initAudioModule()
    self:initVideoModule()
    self:initDisplayModule()
    self:initMotionModule()
    self:initPowerModule()
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:registerTimerHandlers()
    self:funcInit()
    
    return self
end

--------** Safe Component Access **--------
function SystemAutomationController:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value
                return true
            elseif action == "setPosition" then
                component[control].Position = value
                return true
            elseif action == "trigger" then
                component[control]:Trigger()
                return true
            elseif action == "get" then
                return component[control].Boolean
            elseif action == "getPosition" then
                return component[control].Position
            end
        end
        return false
    end)
    
    if not success then
        self:debugPrint("Component access error: " .. tostring(result))
        return false
    end
    return result
end

--------** Debug Helper **--------
function SystemAutomationController:debugPrint(str)
    if self.debugging then
        print("[" .. self.roomName .. " Debug] " .. str)
    end
end

--------** Audio Module **--------
function SystemAutomationController:initAudioModule()
    self.audioModule = {
        setVolume = function(level, gainIndex)
            if gainIndex then
                -- Set specific gain control
                local gain = self.components.gains[gainIndex]
                if gain then
                    self:safeComponentAccess(gain, "gain", "setPosition", level)
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                -- Set all gain controls
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
                -- Set specific gain control
                local gain = self.components.gains[gainIndex]
                if gain then
                    self:safeComponentAccess(gain, "mute", "set", state)
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                -- Set all gain controls
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
            Controls.btnAudioPrivacy.Boolean = state
            self:publishNotification()
        end,
        
        setSystemMute = function(state)
            if self.components.systemMute then
                self:safeComponentAccess(self.components.systemMute, "mute", "set", state)
            end
        end,
        
        setVolumeUpDown = function(direction, state, gainIndex)
            if gainIndex then
                -- Set specific gain control
                local gain = self.components.gains[gainIndex]
                if gain then
                    local control = direction == "up" and "stepper.increase" or "stepper.decrease"
                    self:safeComponentAccess(gain, control, "set", state)
                    -- Unmute when volume is changed
                    if state then
                        self:safeComponentAccess(gain, "mute", "set", false)
                    end
                    self:updateVolumeVisuals(gainIndex)
                end
            else
                -- Set all gain controls
                for i, gain in pairs(self.components.gains) do
                    if gain then
                        local control = direction == "up" and "stepper.increase" or "stepper.decrease"
                        self:safeComponentAccess(gain, control, "set", state)
                        -- Unmute when volume is changed
                        if state then
                            self:safeComponentAccess(gain, "mute", "set", false)
                        end
                        self:updateVolumeVisuals(i)
                    end
                end
            end
            self:publishNotification()
        end,
                
        -- Helper functions for gain management
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
            Controls.btnVideoPrivacy.Boolean = state
            
            -- Update ACPR tracking bypass based on privacy state
            if self.components.camACPR then
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", state)
            end
            
            self:publishNotification()
        end,
        
        getPrivacyState = function()
            if self.components.videoBridge then
                local state = self:safeComponentAccess(self.components.videoBridge, "toggle.privacy", "get")
                Controls.btnVideoPrivacy.Boolean = state
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
                    local control = state and "PowerOn" or "PowerOff"
                    self:safeComponentAccess(display, control, "trigger")
                end
            end
        end,
        
        powerSingle = function(index, state)
            local display = self.components.displays[index]
            if display then
                local control = state and "PowerOn" or "PowerOff"
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
            if Controls.ledMotionIn.Boolean then
                self.state.motionTimeoutActive = false
                Controls.ledMotionTimeoutActive.Boolean = false
                self.timers.motion:Stop()
                
                if not Controls.ledSystemPower.Boolean and 
                   not self.state.motionGraceActive and 
                   Controls.txtMotionMode.String == "Motion On/Off" then
                    self:debugPrint("Turning System on from Motion")
                    self.powerModule.powerOn()
                end
            else
                if Controls.txtMotionMode.String == "Motion On/Off" or 
                   Controls.txtMotionMode.String == "Motion Off" then
                    self:debugPrint("Starting Motion Off Timer")
                    self.state.motionTimeoutActive = true
                    Controls.ledMotionTimeoutActive.Boolean = true
                    self.timers.motion:Start(Controls.MotionTimeout.Value)
                end
            end
        end
    }
end

--------** Power Module **--------
function SystemAutomationController:initPowerModule()
    self.powerModule = {
        enableDisablePowerControls = function(state)
            Controls.btnSystemOnOff.IsDisabled = not state
            Controls.btnSystemOn.IsDisabled = not state
            Controls.btnSystemOff.IsDisabled = not state
        end,
        
        setSystemPowerFB = function(state)
            Controls.ledSystemPower.Boolean = state
            Controls.btnSystemOnOff.Boolean = state
            Controls.btnSystemOn.Boolean = state
            Controls.btnSystemOff.Boolean = not state
        end,
        
        powerOn = function()
            self:debugPrint("Powering System On")
            Controls.btnSystemOnTrig:Trigger()
            self.powerModule.enableDisablePowerControls(false)
            self.state.isWarming = true
            Controls.ledSystemWarming.Boolean = true
            self.timers.warmup:Start(self.config.warmupTime)
            self.powerModule.setSystemPowerFB(true)
            
            self.audioModule.setVolume(self.config.defaultVolume) -- Sets all gains
            self.audioModule.setMute(false)
            self.audioModule.setPrivacy(true)
            -- self.videoModule.setPrivacy(false) -- setPrivacy for Video during Startup, this is handled on Hook State since the room uses ACPR
            self.displayModule.powerAll(true)
            self:publishNotification()
        end,
        
        powerOff = function()
            self:debugPrint("Powering System Off")
            Controls.btnSystemOffTrig:Trigger()
            self.powerModule.enableDisablePowerControls(false)
            self.state.isCooling = true
            Controls.ledSystemCooling.Boolean = true
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

--------** Component Management **--------
function SystemAutomationController:setComponent(ctrl, componentType)
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    else
        self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
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
    for i, v in pairs(self.components.invalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------** Component Setup Functions **--------
function SystemAutomationController:setCallSyncComponent()
    self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
    if self.components.callSync ~= nil then
        self.components.callSync["off.hook"].EventHandler = function()
            self:callSyncCheckConnection()
        end
        self.components.callSync["mute"].EventHandler = function()
            self:callSyncCheckMute()
        end
    end
end

function SystemAutomationController:setVideoBridgeComponent()
    self.components.videoBridge = self:setComponent(Controls.compVideoBridge, "Video Bridge")
    if self.components.videoBridge ~= nil then
        self.components.videoBridge["toggle.privacy"].EventHandler = function()
            self.videoModule.getPrivacyState()
        end
    end
end

-- Unified gain component setup using compGains array
function SystemAutomationController:setGainComponent(idx)
    if not Controls.compGains or not Controls.compGains[idx] then
        self:debugPrint("Gain control " .. idx .. " not found in compGains array")
        return
    end
    
    local componentType = idx == 1 and "Program Volume [Gain 1]" or "Gain [" .. idx .. "]"
    self.components.gains[idx] = self:setComponent(Controls.compGains[idx], componentType)
    
    if self.components.gains[idx] ~= nil then
        self:getVolumeLvl(idx)
        self:getVolumeMute(idx)
        
        self.components.gains[idx]["gain"].EventHandler = function()
            self:getVolumeLvl(idx)
        end
        self.components.gains[idx]["mute"].EventHandler = function()
            self:getVolumeMute(idx)
        end
    end
end

function SystemAutomationController:setSystemMuteComponent()
    self.components.systemMute = self:setComponent(Controls.compSystemMute, "System Mute")
end

function SystemAutomationController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(Controls.compACPR, "Camera ACPR")
    if self.components.camACPR ~= nil then
        self.components.camACPR["TrackingBypass"].EventHandler = function()
            self:updateACPRTrackingBypass()
        end
        
        -- Set initial disabled state based on call status
        if self.components.callSync then
            local callState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
            self.components.camACPR["TrackingBypass"].IsDisabled = not callState
        end
        self.components.camACPR["TrackingBypass"].Legend = " "
    end
end

function SystemAutomationController:setDisplayComponent(idx)
    self.components.displays[idx] = self:setComponent(Controls.devDisplays[idx], "Display [" .. idx .. "]")
end

--------** Helper Functions **--------
function SystemAutomationController:callSyncCheckMute()
    if self.components.callSync ~= nil then
        local state = self:safeComponentAccess(self.components.callSync, "mute", "get")
        self:debugPrint("Call Sync Mute State is: " .. tostring(state))
        Controls.btnAudioPrivacy.Boolean = state
    end
end

function SystemAutomationController:callSyncCheckConnection()
    -- Handle call connection state changes
    if self.components.callSync ~= nil then
        local state = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
        self:debugPrint("Call Connection State: " .. tostring(state))
        
        -- Check mute state when call connection changes
        self:callSyncCheckMute()
        
        -- Update video privacy based on call state
        self.videoModule.setPrivacy(not state)
        
        -- Update ACPR tracking bypass based on call state
        if self.components.camACPR then
            self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", not state)
            self.components.camACPR["TrackingBypass"].IsDisabled = not state
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

-- Updated to use unified control naming pattern
function SystemAutomationController:updateVolumeVisuals(gainIndex)
    gainIndex = gainIndex or 1 -- Default to first gain if not specified
    
    -- Use unified control naming: knbVolumeFader[index] and btnVolumeMute[index]
    local volumeFader = Controls.knbVolumeFader and Controls.knbVolumeFader[gainIndex]
    local volumeMute = Controls.btnVolumeMute and Controls.btnVolumeMute[gainIndex]
    
    if volumeFader and volumeMute then
        -- Update mute button appearance based on mute state
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
    gainIndex = gainIndex or 1 -- Default to first gain if not specified
    local gain = self.components.gains[gainIndex]
    
    if gain ~= nil then
        local level = self:safeComponentAccess(gain, "gain", "getPosition")
        
        -- Update unified UI control
        if Controls.knbVolumeFader and Controls.knbVolumeFader[gainIndex] then
            Controls.knbVolumeFader[gainIndex].Position = level
        end
        
        self:updateVolumeVisuals(gainIndex)
        self:publishNotification()
    end
end

function SystemAutomationController:getVolumeMute(gainIndex)
    gainIndex = gainIndex or 1 -- Default to first gain if not specified
    local gain = self.components.gains[gainIndex]
    
    if gain ~= nil then
        local state = self:safeComponentAccess(gain, "mute", "get")
        
        -- Update unified UI control
        if Controls.btnVolumeMute and Controls.btnVolumeMute[gainIndex] then
            Controls.btnVolumeMute[gainIndex].Boolean = state
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
        if Controls.ledSystemPower.Boolean then --system was on so, turn it back on
            self.audioModule.setSystemMute(false)
            self.displayModule.powerAll(true)
        end
    end
end

--------** Component Name Discovery **--------
function SystemAutomationController:getComponentNames()
    local namesTable = {
        CallSyncNames = {},
        VideoBridgeNames = {},
        CamACPRNames = {},
        DisplayNames = {},
        GainNames = {},
        MuteNames = {},
    }

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, v.Name)
        elseif v.Type == self.componentTypes.videoBridge then
            table.insert(namesTable.VideoBridgeNames, v.Name)
        elseif v.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, v.Name)
        elseif v.Type == self.componentTypes.gains then
            table.insert(namesTable.GainNames, v.Name)
        elseif v.Type == self.componentTypes.systemMute then
            table.insert(namesTable.MuteNames, v.Name)
        elseif v.Type == self.componentTypes.camACPR then
            table.insert(namesTable.CamACPRNames, v.Name)
        end       
    end

    for i, v in pairs(namesTable) do
        table.sort(v)
        table.insert(v, self.clearString)
    end

    Controls.compCallSync.Choices = namesTable.CallSyncNames
    Controls.compVideoBridge.Choices = namesTable.VideoBridgeNames
    Controls.compSystemMute.Choices = namesTable.MuteNames
    Controls.compACPR.Choices = namesTable.CamACPRNames

    -- Set choices for all gain controls in compGains array
    if Controls.compGains then
        for i, v in ipairs(Controls.compGains) do
            v.Choices = namesTable.GainNames
        end
    end

    -- Handle display controls
    for i, v in ipairs(Controls.devDisplays) do
        v.Choices = namesTable.DisplayNames
    end
end

--------** State Management **--------
function SystemAutomationController:publishNotification()
    local systemState = {
        RoomName = self.roomName,
        PowerState = Controls.ledSystemPower.Boolean,
        SystemWarming = Controls.ledSystemWarming.Boolean,
        SystemCooling = Controls.ledSystemCooling.Boolean,
        AudioPrivacy = Controls.btnAudioPrivacy.Boolean,
        VideoPrivacy = Controls.btnVideoPrivacy.Boolean,
        ACPRState = (self.components.camACPR and self.components.camACPR["TrackingBypass"] and self.components.camACPR["TrackingBypass"].Boolean) or false,
        Timestamp = os.time()
    }
    
    -- Add gain information to notification
    systemState.GainControls = {}
    for i, gain in pairs(self.components.gains) do
        if gain then
            systemState.GainControls[i] = {
                Level = self.audioModule.getGainLevel(i),
                Muted = self.audioModule.getGainMute(i)
            }
        end
    end
    
    if Controls.txtNotificationID and Controls.txtNotificationID.String ~= "" then
        Notifications.Publish(Controls.txtNotificationID.String, systemState)
    end
end

--------** Timer Event Handlers **--------
function SystemAutomationController:registerTimerHandlers()
    self.timers.motion.EventHandler = function()
        self:debugPrint("Motion Timeout")
        self.state.motionTimeoutActive = false
        Controls.ledMotionTimeoutActive.Boolean = false
        self.timers.motion:Stop()
        self.powerModule.powerOff()
    end

    self.timers.grace.EventHandler = function()
        self:debugPrint("Grace Period Has Ended")
        self.state.motionGraceActive = false
        Controls.ledMotionGraceActive.Boolean = false
        self.timers.grace:Stop()
    end

    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        self.state.isWarming = false
        Controls.ledSystemWarming.Boolean = false
        self.powerModule.enableDisablePowerControls(true)
        self.timers.warmup:Stop()
        self:publishNotification()
    end

    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        self.state.isCooling = false
        Controls.ledSystemCooling.Boolean = false
        self.powerModule.enableDisablePowerControls(true)
        self.timers.cooldown:Stop()
        self:publishNotification()
    end
end

--------** Event Handler Registration **--------
function SystemAutomationController:registerEventHandlers()
    -- Power control handlers
    Controls.btnSystemOnOff.EventHandler = function(ctl)
        if ctl.Boolean then
            self.powerModule.powerOn()
        else
            self.powerModule.powerOff()
        end
    end

    Controls.btnSystemOn.EventHandler = function()
        self.powerModule.powerOn()
    end

    Controls.btnSystemOff.EventHandler = function()
        self.powerModule.powerOff()
        self.state.motionGraceActive = true
        Controls.ledMotionGraceActive.Boolean = true
        self.timers.grace:Start(self.config.gracePeriod)
    end

    -- Privacy controls
    Controls.btnAudioPrivacy.EventHandler = function(ctl)
        self.audioModule.setPrivacy(ctl.Boolean)
    end

    Controls.btnVideoPrivacy.EventHandler = function(ctl)
        self.videoModule.setPrivacy(ctl.Boolean)
    end

    -- Volume controls using unified arrays
    if Controls.knbVolumeFader then
        for i, fader in ipairs(Controls.knbVolumeFader) do
            fader.EventHandler = function()
                self.audioModule.setVolume(fader.Position, i)
            end
        end
    end

    if Controls.btnVolumeMute then
        for i, muteBtn in ipairs(Controls.btnVolumeMute) do
            muteBtn.EventHandler = function(ctl)
                self.audioModule.setMute(ctl.Boolean, i)
            end
        end
    end

    -- Volume Up/Down controls using arrays
    if Controls.btnVolumeUp then
        for i, upBtn in ipairs(Controls.btnVolumeUp) do
            upBtn.EventHandler = function(ctl)
                self.audioModule.setVolumeUpDown("up", ctl.Boolean, i)
            end
        end
    end

    if Controls.btnVolumeDn then
        for i, downBtn in ipairs(Controls.btnVolumeDn) do
            downBtn.EventHandler = function(ctl)
                self.audioModule.setVolumeUpDown("down", ctl.Boolean, i)
            end
        end
    end

    -- Motion detection
    Controls.ledMotionIn.EventHandler = function()
        self.motionModule.checkMotion()
    end

    -- Component selection handlers
    Controls.compCallSync.EventHandler = function()
        self:setCallSyncComponent()
    end

    Controls.compVideoBridge.EventHandler = function()
        self:setVideoBridgeComponent()
    end

    -- Room name handler
    Controls.roomName.EventHandler = function()
        local formattedRoomName = "[" .. Controls.roomName.String .. "]"
        self.roomName = formattedRoomName
        self:debugPrint("Room name updated to: " .. formattedRoomName)
        self:publishNotification()
    end

    -- Gain component handlers for compGains array
    if Controls.compGains then
        for i, gainComp in ipairs(Controls.compGains) do
            gainComp.EventHandler = function()
                self:setGainComponent(i)
            end
        end
    end

    Controls.compSystemMute.EventHandler = function()
        self:setSystemMuteComponent()
    end

    Controls.compACPR.EventHandler = function()
        self:setCamACPRComponent()
    end

    -- Display component handlers
    for i, v in ipairs(Controls.devDisplays) do
        v.EventHandler = function()
            self:setDisplayComponent(i)
        end
    end
end

--------** Initialization **--------
function SystemAutomationController:funcInit()
    self.powerModule.enableDisablePowerControls(true)
    self.videoModule.getPrivacyState()
    self:getComponentNames()

    Controls.txtMotionMode.Choices = self.config.motionChoices

    -- Set components with current selections
    self:setCallSyncComponent()
    self:setVideoBridgeComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    
    -- Initialize all gain components from compGains array
    if Controls.compGains then
        for i, gainComp in ipairs(Controls.compGains) do
            self:setGainComponent(i)
        end
    end
    
    -- Initialize display components
    for i, v in ipairs(Controls.devDisplays) do
        self:setDisplayComponent(i)
    end

    self:debugPrint("System Automation Controller Initialized with " .. 
                   self.audioModule.getGainCount() .. " gain controls")
    self:debugPrint("compGains[1] is used for Program Volume, subsequent indices for additional gains")
end

--------** Cleanup **--------
function SystemAutomationController:cleanup()
    -- Stop all timers
    for name, timer in pairs(self.timers) do
        if timer then
            timer:Stop()
        end
    end

    -- Clear event handlers for gain components
    for i, gain in pairs(self.components.gains) do
        if gain and gain.EventHandler then
            gain.EventHandler = nil
        end
    end

    -- Clear event handlers for other components
    for name, component in pairs(self.components) do
        if type(component) == "table" and component.EventHandler then
            component.EventHandler = nil
        end
    end

    self:debugPrint("Cleanup completed for " .. self.roomName)
end

--------** Configuration Selection **--------
function SystemAutomationController:setupConfigSelection()
    -- Set up the choices for the configuration selector
    Controls.selDefaultConfigs.Choices = {
        "Conference Room",
        "Huddle Room",
        "Default",
        "Custom Room",
        "User Defined"
    }

    -- Define control mappings with array support
    local controlMappings = {
        { control = "WarmupTime", config = "warmupTime", isArray = false },
        { control = "CooldownTime", config = "cooldownTime", isArray = false },
        { control = "MotionTimeout", config = "motionTimeout", isArray = false },
        { control = "MotionGracePeriod", config = "gracePeriod", isArray = false },
        { control = "DefaultVolume", config = "defaultVolume", isArray = true, index = 1 }
    }

    -- Function to update control values based on selected configuration
    local function updateControlValues(configType)
        local config = self.defaultConfigs[configType]
        if not config then return end

        -- Enable/Disable controls based on configuration type
        local isUserDefined = configType == "User Defined"
        for _, mapping in ipairs(controlMappings) do
            local control = mapping.isArray and Controls[mapping.control][mapping.index] or Controls[mapping.control]
            if control then
                control.Value = config[mapping.config]
                control.IsDisabled = not isUserDefined
            end
        end
    end

    -- Event handler for configuration selection
    Controls.selDefaultConfigs.EventHandler = function(ctl)
        updateControlValues(ctl.String)
    end

    -- Event handlers for User Defined mode using loop
    for _, mapping in ipairs(controlMappings) do
        local control = mapping.isArray and Controls[mapping.control][mapping.index] or Controls[mapping.control]
        if control then
            control.EventHandler = function(ctl)
                if Controls.selDefaultConfigs.String == "User Defined" then
                    self.defaultConfigs["User Defined"][mapping.config] = ctl.Value
                end
            end
        end
    end

    -- Initialize with default selection
    Controls.selDefaultConfigs.String = "Default"
    updateControlValues("Default")
end

--------** Factory Function **--------
local function createSystemController(roomName, roomType)
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
            warmupTime = Controls.WarmupTime.Value,
            cooldownTime = Controls.CooldownTime.Value,
            motionTimeout = Controls.MotionTimeout.Value,
            gracePeriod = Controls.MotionGracePeriod.Value,
            defaultVolume = Controls.DefaultVolume[1].Value
        }
    }

    local roomConfig = defaultConfigs[roomType] or defaultConfigs["Default"]
    
    local success, controller = pcall(function()
        local instance = SystemAutomationController.new(roomName, roomConfig)
        instance.defaultConfigs = defaultConfigs
        instance:setupConfigSelection()
        return instance
    end)

    if success then
        print("Successfully created System Automation Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main system controller instance
-- Modify roomName and roomType as needed for your specific installation
local formattedRoomName = "[" .. Controls.roomName.String .. "]"
mySystemController = createSystemController(formattedRoomName, Controls.selDefaultConfigs.String)

-- For multiple room instances, create additional controllers:
-- huddle1Controller = createSystemController("Huddle Room 1", "Huddle Room")
-- huddle2Controller = createSystemController("Huddle Room 2", "Huddle Room")

--------** Usage Examples **--------
--[[
-- Example usage of the unified gain control system:

-- Set volume on all gain controls
mySystemController.audioModule.setVolume(0.8)

-- Set volume on specific gain control
mySystemController.audioModule.setVolume(0.6, 2)

-- Mute all gain controls
mySystemController.audioModule.setMute(true)

-- Mute specific gain control
mySystemController.audioModule.setMute(true, 3)

-- Get gain count
local gainCount = mySystemController.audioModule.getGainCount()

-- Get specific gain level
local level = mySystemController.audioModule.getGainLevel(1)

-- Get specific gain mute state
local isMuted = mySystemController.audioModule.getGainMute(2)

-- Volume up/down on all gains
mySystemController.audioModule.setVolumeUpDown("up", true)

-- Volume up/down on specific gain
mySystemController.audioModule.setVolumeUpDown("down", true, 2)
]]--