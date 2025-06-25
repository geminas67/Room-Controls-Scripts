--[[ 
  Shure MXA Controls - Class-based Implementation
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-06-18
  Firmware Req: 10.0.0
  Version: 2.1
  
  Compact refactor following SkarrhojCameraController patterns
  Maintains all existing MXA functionality with improved safety
]]--

--------** Class Constructor **--------
ShureMXAController = {}
ShureMXAController.__index = ShureMXAController

function ShureMXAController.new(roomName, config)
    local self = setmetatable({}, ShureMXAController)
    self.roomName = roomName or "Shure MXA"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    
    self.components = {
        callSync = nil, videoBridge = nil, roomControls = nil,
        mxaDevices = {}, invalid = {}
    }
    
    self.state = {
        audioPrivacy = false, videoPrivacy = false,
        systemPower = false, fireAlarm = false
    }
    
    self.config = {
        ledBrightness = (config and config.ledBrightness) or 5,
        ledOff = (config and config.ledOff) or 0,
        controlColors = { white = 'White', pink = 'Pink', off = 'Off' },
        ledToggleInterval = 1.5
    }
    
    self:initModules()
    return self
end

--------** Debug Helper **--------
function ShureMXAController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." MXA Debug] "..str) end
end

--------** Safe Component Access **--------
function ShureMXAController:safeComponentAccess(component, control, action, value)
    local compCtrl = component and component[control]
    if not compCtrl then return false end
    local ok, result = pcall(function()
        if action == "set" then compCtrl.Boolean = value
        elseif action == "setValue" then compCtrl.Value = value
        elseif action == "setString" then compCtrl.String = value
        elseif action == "trigger" then compCtrl:Trigger()
        elseif action == "get" then return compCtrl.Boolean
        elseif action == "getValue" then return compCtrl.Value
        elseif action == "getString" then return compCtrl.String
        end
        return true
    end)
    if not ok then self:debugPrint("Component access error: "..tostring(result)) end
    return ok and result
end

--------** Initialize Modules **--------
function ShureMXAController:initModules()
    self:initMXAModule()
    self:initPrivacyModule()
    self:initSystemModule()
    self:initCallSyncModule()
    self:initVideoBridgeModule()
end

--------** MXA Module **--------
function ShureMXAController:initMXAModule()
    self.mxaModule = {
        setComponent = function(idx)
            self.components.mxaDevices[idx] = self:setComponent(Controls.devMXAs[idx], "MXA [" .. idx .. "]")
            if self.components.mxaDevices[idx] then self:registerMXAEventHandlers(idx) end
        end,
        
        setLED = function(state)
            for _, device in pairs(self.components.mxaDevices) do
                if device then self:safeComponentAccess(device, "bright", "setValue", state and self.config.ledBrightness or self.config.ledOff) end
            end
        end,
        
        setMute = function(state)
            for _, device in pairs(self.components.mxaDevices) do
                if device then self:safeComponentAccess(device, "muteall", "set", state) end
            end
        end,

        ledToggleTimer = Timer.New(),
        ledState = false,

        startLEDToggle = function()
            self.mxaModule.ledToggleTimer:Start(self.config.ledToggleInterval)
            self:debugPrint("Started LED toggle timer")
        end,

        stopLEDToggle = function()
            self.mxaModule.ledToggleTimer:Stop()
            self:debugPrint("Stopped LED toggle timer")
        end,

        getDeviceCount = function()
            local count = 0
            for _, device in pairs(self.components.mxaDevices) do if device then count = count + 1 end end
            return count
        end
    }

    self.mxaModule.ledToggleTimer.EventHandler = function()
        self.mxaModule.ledState = not self.mxaModule.ledState
        self.mxaModule.setLED(self.mxaModule.ledState)
    end
end

--------** Privacy Module **--------
function ShureMXAController:initPrivacyModule()
    self.privacyModule = {
        setAudioPrivacy = function(state)
            self.state.audioPrivacy = state
            self.mxaModule.setMute(state)
            self:debugPrint("Set Audio Privacy to "..tostring(state))
        end,
        
        setVideoPrivacy = function(state)
            self.state.videoPrivacy = state
            self.mxaModule.setMute(state)
            self:debugPrint("Set Video Privacy to "..tostring(state))
        end,
        
        getPrivacyState = function()
            return self.state.audioPrivacy or self.state.videoPrivacy
        end
    }
end

--------** System Module **--------
function ShureMXAController:initSystemModule()
    self.systemModule = {
        setSystemPower = function(state)
            self.state.systemPower = state
            if not state then
                self.mxaModule.setMute(true)
                self.mxaModule.setLED(false)
                self:debugPrint("System Power Off - MXA muted and LEDs off")
            else
                self:debugPrint("System Power On")
            end
        end,
        
        setFireAlarm = function(state)
            self.state.fireAlarm = state
            if state then
                self:debugPrint("Fire Alarm Active")
                self.mxaModule.startLEDToggle()
                self.mxaModule.setMute(true)
                self.mxaModule.setLED(false)
            else
                self.mxaModule.stopLEDToggle()
                if self.components.callSync and self:safeComponentAccess(self.components.callSync, "off.hook", "get") then
                    self:debugPrint("Fire Alarm Cleared and Call is Off-Hook")
                    self.mxaModule.setMute(false)
                    self.mxaModule.setLED(true)
                else
                    self:debugPrint("Fire Alarm Cleared and Call is On-Hook")
                    self.mxaModule.setMute(true)
                    self.mxaModule.setLED(false)
                end
            end
        end
    }
end

--------** Call Sync Module **--------
function ShureMXAController:initCallSyncModule()
    self.callSyncModule = {
        setHookState = function(state)
            self:debugPrint("Call Sync Off Hook State: " .. tostring(state))
            self.mxaModule.setLED(state)
        end,
        
        setMuteState = function(state)
            self:debugPrint("Call Sync Mute State: " .. tostring(state))
            self.mxaModule.setMute(state)
        end,
        
        endCall = function()
            if self.components.callSync then
                self:safeComponentAccess(self.components.callSync, "end.call", "trigger")
                self:debugPrint("End call triggered")
            end
        end
    }
end

--------** Video Bridge Module **--------
function ShureMXAController:initVideoBridgeModule()
    self.videoBridgeModule = {
        setPrivacy = function(state)
            self:debugPrint("Video Privacy State is: " .. tostring(state))
            self.privacyModule.setVideoPrivacy(state)
        end,
        
        getPrivacyState = function()
            return self.state.videoPrivacy
        end
    }
end

--------** Component Management **--------
function ShureMXAController:setComponent(ctrl, componentType)
    local componentName = ctrl.String
    
    if componentName == "" then
        self:setComponentValid(componentType)
        ctrl.Color = "white"
        return nil
    elseif componentName == self.clearString then
        ctrl.String = ""
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = self.config.controlColors.pink
        self:setComponentInvalid(componentType)
        return nil
    else
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
end

function ShureMXAController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function ShureMXAController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function ShureMXAController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------** Component Setup **--------
function ShureMXAController:setupComponents()
    self:setCallSyncComponent()
    self:setVideoBridgeComponent()
    self:setRoomControlsComponent()
    
    for i, _ in ipairs(Controls.devMXAs) do
        self.mxaModule.setComponent(i)
    end
end

function ShureMXAController:setCallSyncComponent()
    self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
    if self.components.callSync then self:registerCallSyncEventHandlers() end
end

function ShureMXAController:setVideoBridgeComponent()   
    self.components.videoBridge = self:setComponent(Controls.compVideoBridge, "Video Bridge")
    if self.components.videoBridge then self:registerVideoBridgeEventHandlers() end
end

function ShureMXAController:setRoomControlsComponent()
    self.components.roomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.roomControls then self:registerRoomControlsEventHandlers() end
end

--------** Event Handler Registration **--------
function ShureMXAController:registerCallSyncEventHandlers()
    local callSync = self.components.callSync
    if not callSync then return end
    
    local offHook = callSync["off.hook"]
    if offHook then
        offHook.EventHandler = function(ctl) self.callSyncModule.setHookState(ctl.Boolean) end
    end
    
    local mute = callSync["mute"]
    if mute then
        mute.EventHandler = function(ctl) self.callSyncModule.setMuteState(ctl.Boolean) end
    end
end

function ShureMXAController:registerVideoBridgeEventHandlers()
    local videoBridge = self.components.videoBridge
    if not videoBridge then return end
    
    local privacy = videoBridge["toggle.privacy"]
    if privacy then
        privacy.EventHandler = function(ctl) self.videoBridgeModule.setPrivacy(ctl.Boolean) end
    end
end

function ShureMXAController:registerRoomControlsEventHandlers()
    local roomControls = self.components.roomControls
    if not roomControls then return end
    
    local systemPower = roomControls["ledSystemPower"]
    if systemPower then
        systemPower.EventHandler = function(ctl) self.systemModule.setSystemPower(ctl.Boolean) end
    end
    
    local fireAlarm = roomControls["ledFireAlarm"]
    if fireAlarm then
        fireAlarm.EventHandler = function(ctl) self.systemModule.setFireAlarm(ctl.Boolean) end
    end
end

function ShureMXAController:registerMXAEventHandlers(idx)
    local device = self.components.mxaDevices[idx]
    if not device then return end
    
    local muteAll = device["muteall"]
    if muteAll then
        muteAll.EventHandler = function(control) self:debugPrint("MXA ["..idx.."] Mute: "..tostring(control.Boolean)) end
    end
    
    local bright = device["bright"]
    if bright then
        bright.EventHandler = function(control) self:debugPrint("MXA ["..idx.."] Brightness: "..tostring(control.Value)) end
    end
end

function ShureMXAController:registerEventHandlers()
    if Controls.btnMXAMute then
        Controls.btnMXAMute.EventHandler = function(ctl) self.mxaModule.setMute(ctl.Boolean) end
    end

    if Controls.compRoomControls then
        Controls.compRoomControls.EventHandler = function() self:setRoomControlsComponent() end
    end

    if Controls.compCallSync then
        Controls.compCallSync.EventHandler = function() self:setCallSyncComponent() end
    end

    if Controls.compVideoBridge then
        Controls.compVideoBridge.EventHandler = function() self:setVideoBridgeComponent() end
    end

    for i, _ in ipairs(Controls.devMXAs) do
        Controls.devMXAs[i].EventHandler = function() self.mxaModule.setComponent(i) end
    end
end

--------** Component Name Discovery **--------
function ShureMXAController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {}, 
        CallSyncNames = {},
        VideoBridgeNames = {}, 
        MXANames = {}
    }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "call_sync" then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == "%PLUGIN%_984f65d4-443f-406d-9742-3cb4027ff81c_%FP%_1257aeeea0835196bee126b4dccce889" then
            table.insert(namesTable.MXANames, comp.Name)
        elseif comp.Type == "usb_uvc" then
            table.insert(namesTable.VideoBridgeNames, comp.Name)
        elseif comp.Type == "device_controller_script" and comp.Name:find("compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    if Controls.compRoomControls then Controls.compRoomControls.Choices = namesTable.RoomControlsNames end
    if Controls.compCallSync then Controls.compCallSync.Choices = namesTable.CallSyncNames end
    if Controls.compVideoBridge then Controls.compVideoBridge.Choices = namesTable.VideoBridgeNames end
    
    for i, _ in ipairs(Controls.devMXAs) do
        Controls.devMXAs[i].Choices = namesTable.MXANames
    end
end

--------** System Initialization **--------
function ShureMXAController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.mxaModule.setMute(true)
    self.mxaModule.setLED(false)
    self:debugPrint("System initialization completed")
end

--------** Initialization **--------
function ShureMXAController:funcInit()
    self:debugPrint("Starting Shure MXA Controller initialization...")
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    self:debugPrint("Shure MXA Controller Initialized with "..self.mxaModule.getDeviceCount().." MXA devices")
end

--------** Cleanup **--------
function ShureMXAController:cleanup()
    if self.components.callSync then
        local offHook = self.components.callSync["off.hook"]
        if offHook then offHook.EventHandler = nil end
        local mute = self.components.callSync["mute"]
        if mute then mute.EventHandler = nil end
    end
    
    if self.components.videoBridge then
        local privacy = self.components.videoBridge["toggle.privacy"]
        if privacy then privacy.EventHandler = nil end
    end
    
    if self.components.roomControls then
        local systemPower = self.components.roomControls["ledSystemPower"]
        if systemPower then systemPower.EventHandler = nil end
        local fireAlarm = self.components.roomControls["ledFireAlarm"]
        if fireAlarm then fireAlarm.EventHandler = nil end
    end
    
    for _, device in pairs(self.components.mxaDevices) do
        if device then
            local muteAll = device["muteall"]
            if muteAll then muteAll.EventHandler = nil end
            local bright = device["bright"]
            if bright then bright.EventHandler = nil end
        end
    end

    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createShureMXAController(roomName, config)
    print("Creating Shure MXA Controller for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = ShureMXAController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    
    if success then
        print("Successfully created Shure MXA Controller for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
local formattedRoomName = "[Shure MXA Controller]"
myMXAController = createShureMXAController(formattedRoomName)

if myMXAController then
    print("Shure MXA Controller created successfully!")
else
    print("ERROR: Failed to create Shure MXA Controller!")
end

--------** Usage Examples **--------
--[[
-- Example usage of the MXA controller:

-- Set audio privacy
myMXAController.privacyModule.setAudioPrivacy(true)

-- Set video privacy
myMXAController.videoBridgeModule.setPrivacy(true)

-- Control MXA LEDs
myMXAController.mxaModule.setLED(true)

-- Control MXA mute
myMXAController.mxaModule.setMute(true)

-- End active calls
myMXAController.callSyncModule.endCall()

-- Check system status
local deviceCount = myMXAController.mxaModule.getDeviceCount()
local privacyState = myMXAController.privacyModule.getPrivacyState()
]]--
