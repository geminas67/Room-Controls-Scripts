--[[ 
  Shure MXA Controls - Class-based Implementation
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.0
  
  Refactored to follow class-based pattern for modularity and reusability
  Maintains all existing MXA functionality including LED and mute control
  Preserves integration with Call Sync and Video Bridge components
]]--

-- Define control references
local controls = {
    devMXAs = Controls.devMXAs,
    btnMXAMute = Controls.btnMXAMute,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    compVideoBridge = Controls.compVideoBridge,
    txtStatus = Controls.txtStatus,
}

-- ShureMXAController class
ShureMXAController = {}
ShureMXAController.__index = ShureMXAController

--------** Class Constructor **--------
function ShureMXAController.new(config)
    local self = setmetatable({}, ShureMXAController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Component storage
    self.components = {
        callSync = nil,
        videoBridge = nil,
        roomControls = nil,
        mxaDevices = {}, -- Table of MXA devices
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        audioPrivacy = false,
        videoPrivacy = false
    }
    
    -- Configuration
    self.config = {
        ledBrightness = config and config.ledBrightness or 5,
        ledOff = config and config.ledOff or 0
    }
    
    -- Store controls reference
    self.controls = controls
    
    -- Initialize modules
    self:initMXAModule()
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** Debug Helper **--------
function ShureMXAController:debugPrint(str)
    if self.debugging then
        print("[Shure MXA Debug] " .. str)
    end
end

--------** MXA Module **--------
function ShureMXAController:initMXAModule()
    self.mxaModule = {
        setComponent = function(idx)
            self.components.mxaDevices[idx] = self:setComponent(Controls.devMXAs[idx], "MXA [" .. idx .. "]")
            if self.components.mxaDevices[idx] ~= nil then
                if self.components.mxaDevices[idx]["muteall"] then
                    self.components.mxaDevices[idx]["muteall"].EventHandler = function(control)
                        self:debugPrint("MXA ["..idx.."] Mute: "..tostring(control.Boolean))
                    end
                end
                if self.components.mxaDevices[idx]["bright"] then
                    self.components.mxaDevices[idx]["bright"].EventHandler = function(control)
                        self:debugPrint("MXA ["..idx.."] Brightness: "..tostring(control.Value))
                    end
                end
            end
        end,
        
        setLED = function(state)
            for i, device in pairs(self.components.mxaDevices) do
                if device["bright"] then
                    device["bright"].Value = state and self.config.ledBrightness or self.config.ledOff
                end
            end
        end,
        
        setMute = function(state)
            for i, device in pairs(self.components.mxaDevices) do
                if device["muteall"] then
                    device["muteall"].Boolean = state
                end
            end
        end,

        -- LED toggle functionality
        ledToggleTimer = Timer.New(),
        ledState = false,

        startLEDToggle = function()
            self.mxaModule.ledToggleTimer:Start(1.5) -- 1.5 second interval
            self:debugPrint("Started LED toggle timer")
        end,

        stopLEDToggle = function()
            self.mxaModule.ledToggleTimer:Stop()
            self:debugPrint("Stopped LED toggle timer")
        end
    }

    -- Set up LED toggle timer handler
    self.mxaModule.ledToggleTimer.EventHandler = function()
        self.mxaModule.ledState = not self.mxaModule.ledState
        self.mxaModule.setLED(self.mxaModule.ledState)
    end
end

--------** Room Controls Component **--------
function ShureMXAController:setRoomControlsComponent()
    self.components.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if self.components.roomControls ~= nil then
        -- Add event handlers for system power and fire alarm
        local this = self  -- Capture self for use in handlers

        -- System Power Handler
        self.components.roomControls["ledSystemPower"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:debugPrint("System Power On")
            else
                this:debugPrint("System Power Off")
                self.mxaModule.setMute(true)
                self.mxaModule.setLED(false)
            end
        end

        -- Fire Alarm Handler
        self.components.roomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:debugPrint("Fire Alarm Active")
                this.mxaModule.startLEDToggle()
                this.mxaModule.setMute(true)
                this.mxaModule.setLED(false)
            else
                this.mxaModule.stopLEDToggle()
                if this.components.callSync["off.hook"].Boolean then
                    this:debugPrint("Fire Alarm Cleared and Call is Off-Hook")
                    this.mxaModule.setMute(false)
                    this.mxaModule.setLED(true)
                else
                    this:debugPrint("Fire Alarm Cleared and Call is On-Hook")
                    this.mxaModule.setMute(true)
                    this.mxaModule.setLED(false)
                end
            end
        end
    end
end

--------** Call Sync Component **--------
function ShureMXAController:setCallSyncComponent()
    self.components.callSync = self:setComponent(self.controls.compCallSync, "Call Sync")
    if self.components.callSync ~= nil then
        local this = self  -- Capture self for use in handlers
        
        -- Handle off-hook state changes
        self.components.callSync["off.hook"].EventHandler = function(ctl)
            local state = ctl.Boolean
            this:debugPrint("Call Sync Off Hook State: " .. tostring(state))
            -- Update MXA LED state based on off-hook
            this.mxaModule.setLED(state)
        end
        
        -- Handle mute state changes
        self.components.callSync["mute"].EventHandler = function(ctl)
            local state = ctl.Boolean
            this:debugPrint("Call Sync Mute State: " .. tostring(state))
            -- Update MXA mute state
            this.mxaModule.setMute(state)
        end
    end
end

--------** Video Bridge Component **--------
function ShureMXAController:setVideoBridgeComponent()   
    self.components.videoBridge = self:setComponent(self.controls.compVideoBridge, "Video Bridge")
    if self.components.videoBridge ~= nil then
        local this = self  -- Capture self for use in handlers
        self.components.videoBridge["toggle.privacy"].EventHandler = function(ctl)
            local state = ctl.Boolean
            this:debugPrint("Video Privacy State is: " .. tostring(state))
            this.mxaModule.setMute(state)
        end
    end
end

--------** Component Management **--------
function ShureMXAController:setComponent(ctrl, componentType)
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

function ShureMXAController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function ShureMXAController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function ShureMXAController:checkStatus()
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

--------** Component Name Discovery **--------
function ShureMXAController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {},
        CallSyncNames = {},
        VideoBridgeNames = {},
        MXANames = {}
    }

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == "call_sync" then
            table.insert(namesTable.CallSyncNames, v.Name)
        elseif v.Type == "%PLUGIN%_984f65d4-443f-406d-9742-3cb4027ff81c_%FP%_1257aeeea0835196bee126b4dccce889" then
            table.insert(namesTable.MXANames, v.Name)
        elseif v.Type == "usb_uvc" then
            table.insert(namesTable.VideoBridgeNames, v.Name)
        elseif v.Type == "device_controller_script" and string.match(v.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, v.Name)
        end
    end

    for i, v in pairs(namesTable) do
        table.sort(v)
        table.insert(v, self.clearString)
    end

    Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    Controls.compCallSync.Choices = namesTable.CallSyncNames
    Controls.compVideoBridge.Choices = namesTable.VideoBridgeNames
    
    -- Set choices for each MXA device control in the table
    for i, v in ipairs(Controls.devMXAs) do
        v.Choices = namesTable.MXANames
    end
end

--------** Event Handler Registration **--------
function ShureMXAController:registerEventHandlers()

    Controls.btnMXAMute.EventHandler = function(ctl)
        self.mxaModule.setMute(ctl.Boolean)
    end

    -- Component selection handlers
    self.controls.compRoomControls.EventHandler = function()
        self:setRoomControlsComponent()
    end

    self.controls.compCallSync.EventHandler = function()
        self:setCallSyncComponent()
    end

    self.controls.compVideoBridge.EventHandler = function()
        self:setVideoBridgeComponent()
    end

    -- MXA device handlers
    for i, v in ipairs(self.controls.devMXAs) do
        v.EventHandler = function()
            self.mxaModule.setComponent(i)
        end
    end
end

--------** Initialization **--------
function ShureMXAController:funcInit()
    self:getComponentNames()

    -- Set components with current selections
    self:setCallSyncComponent()
    self:setVideoBridgeComponent()
    self:setRoomControlsComponent()
    
    -- Initialize MXA devices
    for i, v in ipairs(Controls.devMXAs) do
        self.mxaModule.setComponent(i)
    end

    self:debugPrint("Shure MXA Controller Initialized")
end

--------** Cleanup **--------
function ShureMXAController:cleanup()
    -- Clear event handlers for components
    if self.components.callSync then
        self.components.callSync["off.hook"].EventHandler = nil
        self.components.callSync["mute"].EventHandler = nil
    end
    
    if self.components.videoBridge then
        self.components.videoBridge["toggle.privacy"].EventHandler = nil
    end
    
    for i, device in pairs(self.components.mxaDevices) do
        if device["muteall"] then
            device["muteall"].EventHandler = nil
        end
        if device["bright"] then
            device["bright"].EventHandler = nil
        end
    end

    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createShureMXAController(config)
    local defaultConfig = {
        debugging = true,
        ledBrightness = 5,
        ledOff = 0
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return ShureMXAController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created Shure MXA Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main MXA controller instance
myMXAController = createShureMXAController()

--------** Usage Examples **--------
--[[
-- Example usage of the MXA controller:

-- Set audio privacy
myMXAController.callSyncModule.setMute(true)

-- Set video privacy
myMXAController.videoBridgeModule.setPrivacy(true)

-- Control MXA LEDs
myMXAController.mxaModule.setLED(true)

-- Control MXA mute
myMXAController.mxaModule.setMute(true)

-- End active calls
myMXAController.callSyncModule.endCall()
]]--
