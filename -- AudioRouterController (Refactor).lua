--[[ 
  Audio Router Controller - Refactored Class-based Implementation
  Author: Nikolas Smith, Q-SYS
  2025-08-14
  Firmware Req: 10.0.0
  Version: 1.0
  
  Class-based implementation maintaining simplicity of functional approach
]]--

-- Define control references
local controls = {
    compAudioRouter  = Controls.compAudioRouter,
    btnAudioSource   = Controls.btnAudioSource,
    txtStatus        = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls,
}

-- AudioRouterController class
AudioRouterController = {}
AudioRouterController.__index = AudioRouterController

--------[ Class Constructor ]--------
function AudioRouterController.new(config)
    local self = setmetatable({}, AudioRouterController)
    
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    
    self.inputs = {
        xlr01 = 1,
        xlr02 = 2,
        dmp01 = 3,
        dmp02 = 4,
        dmp03 = 5,
        xlr03 = 6,
        xlr04 = 7,
        xlr05 = 8,
        none  = 9,
    }
    self.outputs = {
        output01 = 1
    }
    self.componentTypes = {
        audioRouter  = "router_with_output",
        roomControls = "device_controller_script"
    }
    self.audioRouter  = nil
    self.roomControls = nil
    self.controls = controls
    self:initialize()
    
    return self
end

--------[ Debug Helper ]--------
function AudioRouterController:debugPrint(str)
    if self.debugging then
        print("[Audio Router Debug] " .. str)
    end
end

--------[ Component Management ]--------
function AudioRouterController:setComponent(ctrl, componentType)
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    -- Guard clause: empty component name
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    -- Guard clause: clear string selected
    if componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    -- Guard clause: invalid component
    if #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    -- Main path: valid component
    self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return Component.New(componentName)
end

function AudioRouterController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:updateStatus()
end

function AudioRouterController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:updateStatus()
end

function AudioRouterController:updateStatus()
    -- Check for any invalid components
    for _, isInvalid in pairs(self.invalidComponents) do
        if isInvalid then
            self.controls.txtStatus.String = "Invalid Components"
            self.controls.txtStatus.Value = 1
            return
        end
    end
    -- All components valid
    self.controls.txtStatus.String = "OK"
    self.controls.txtStatus.Value = 0
end

--------[ Component Name Discovery ]--------
function AudioRouterController:discoverComponents()
    local audioRouterNames = {}
    local roomControlsNames = {}

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == self.componentTypes.audioRouter then
            table.insert(audioRouterNames, v.Name)
        elseif v.Type == self.componentTypes.roomControls and string.match(v.Name, "^compRoomControls") then
            table.insert(roomControlsNames, v.Name)
        end
    end
    
    table.sort(audioRouterNames)
    table.insert(audioRouterNames, self.clearString)
    self.controls.compAudioRouter.Choices = audioRouterNames
    
    table.sort(roomControlsNames)
    table.insert(roomControlsNames, self.clearString)
    self.controls.compRoomControls.Choices = roomControlsNames
    
    self:debugPrint("Component discovery completed - Audio Router: " .. #audioRouterNames - 1 .. ", Room Controls: " .. #roomControlsNames - 1)
end


--------[ Component Setup ]--------
function AudioRouterController:setAudioRouterComponent()
    -- Clean up old event handlers if switching devices
    if self.audioRouter and self.audioRouter["select.1"] then
        self.audioRouter["select.1"].EventHandler = nil
        self:debugPrint("Cleanup completed due to switching devices")
    end

    self.audioRouter = self:setComponent(self.controls.compAudioRouter, "Audio Router")
    if not self.audioRouter then
        return
    end
    
    self.audioRouter["select.1"].EventHandler = function(ctl)
        local inputValue = ctl.Value
        
        -- Direct UI update for responsiveness
        for i, btn in ipairs(self.controls.btnAudioSource) do
            btn.Boolean = (i == inputValue)
        end
        
        self:debugPrint("Audio Router set Output 1 to Input " .. inputValue)
    end
end

function AudioRouterController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if not self.roomControls then
        return
    end
    
    self.roomControls["ledSystemPower"].EventHandler = function(ctl)
        local route = ctl.Boolean and self.inputs.xlr01 or self.inputs.none
        self:setRoute(route, self.outputs.output01)
    end
    
    self.roomControls["ledFireAlarm"].EventHandler = function(ctl)
        if ctl.Boolean then
            -- Fire alarm active: route to none
            self:setRoute(self.inputs.none, self.outputs.output01)
        else
            -- Fire alarm cleared: revert to last input or default
            if Controls.ledSystemPower.Boolean then
                local defaultRoute = self.lastInput[self.outputs.output01] or self.inputs.xlr01
                self:setRoute(defaultRoute, self.outputs.output01)
            end
        end
    end
end

--------[ Audio Routing Functions ]--------
function AudioRouterController:setRoute(input, output)
    if self.audioRouter then
        self.audioRouter["select."..tostring(output)].Value = input
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(input))
        self.lastInput[output] = input
    end
end

--------[ Event Handler Registration ]--------
function AudioRouterController:registerEventHandlers()
    -- Component selection handlers
    self.controls.compAudioRouter.EventHandler = function()
        self:setAudioRouterComponent()
    end

    self.controls.compRoomControls.EventHandler = function()
        self:setRoomControlsComponent()
    end

    -- Audio source button handlers (direct routing for responsiveness)
    for i, btn in ipairs(self.controls.btnAudioSource) do
        btn.EventHandler = function()
            self:setRoute(i, self.outputs.output01)
        end
    end
end

--------[ Initialization ]--------
function AudioRouterController:initialize()
    -- Batch initialization for better performance
    self:registerEventHandlers()
    self:discoverComponents()
    self:setAudioRouterComponent()
    self:setRoomControlsComponent()
    self:debugPrint("Audio Router Controller Initialized")
end

--------[ Cleanup ]--------
function AudioRouterController:cleanup()
    -- Clean up audio router event handlers
    if self.audioRouter and self.audioRouter["select.1"] then
        self.audioRouter["select.1"].EventHandler = nil
    end
    
    -- Clean up room controls event handlers
    if self.roomControls then
        if self.roomControls["ledSystemPower"] then
            self.roomControls["ledSystemPower"].EventHandler = nil
        end
        if self.roomControls["ledFireAlarm"] then
            self.roomControls["ledFireAlarm"].EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed")
end

--------[ Factory Function ]--------
local function createAudioRouterController(config)
    local defaultConfig = {
        debugging = true
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return AudioRouterController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created Audio Router Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------[ Instance Creation ]--------
-- Create the main audio router controller instance
myAudioRouterController = createAudioRouterController()

--------[ Usage Examples ]--------
--[[
-- Example usage of the audio router controller:

-- Set a route manually
myAudioRouterController:setRoute(1, 1)  -- Set Output 1 to Input 1

-- Get current route (if audio router is available)
if myAudioRouterController.audioRouter then
    local currentInput = myAudioRouterController.audioRouter["select.1"].Value
    
    -- Update source buttons to reflect current state
    for i, btn in ipairs(Controls.btnAudioSource) do
        btn.Boolean = (i == currentInput)
    end
end

-- Clean up when done
-- myAudioRouterController:cleanup()
]]-- 