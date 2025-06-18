--[[ 
  Audio Router Controller - Class-based Implementation
  Author: Nikolas Smith, Q-SYS
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.0
  
  Class-based implementation maintaining simplicity of functional approach
]]--

-- Define control references
local controls = {
    compAudioRouter = Controls.compAudioRouter,
    btnAudioSource = Controls.btnAudioSource,
    txtStatus = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls, -- Room Controls component
}

-- AudioRouterController class
AudioRouterController = {}
AudioRouterController.__index = AudioRouterController

--------** Class Constructor **--------
function AudioRouterController.new(config)
    local self = setmetatable({}, AudioRouterController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    
    -- Input/Output mapping
    self.inputs = {
        XLR01 = 1,
        XLR02 = 2,
        DMP01 = 3,
        DMP02 = 4,
        DMP03 = 5,
        XLR03 = 6,
        XLR04 = 7,
        XLR05 = 8,
        NONE = 9
    }
    
    self.outputs = {
        OUTPUT01 = 1
    }
    
    -- Component storage
    self.audioRouter = nil
    self.roomControls = nil
    self.lastInput = {} -- Store the last input for each output
    -- Store controls reference
    self.controls = controls
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** Debug Helper **--------
function AudioRouterController:debugPrint(str)
    if self.debugging then
        print("[Audio Router Debug] " .. str)
    end
end

--------** Component Management **--------
function AudioRouterController:setComponent(ctrl, componentType)
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

function AudioRouterController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:checkStatus()
end

function AudioRouterController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:checkStatus()
end

function AudioRouterController:checkStatus()
    for i, v in pairs(self.invalidComponents) do
        if v == true then
            self.controls.txtStatus.String = "Invalid Components"
            self.controls.txtStatus.Value = 1
            return
        end
    end
    self.controls.txtStatus.String = "OK"
    self.controls.txtStatus.Value = 0
end

--------** Component Name Discovery **--------
function AudioRouterController:getComponentNames()
    local namesTable = {}

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == "router_with_output" then
            table.insert(namesTable, v.Name)
        end
    end
    table.sort(namesTable)
    table.insert(namesTable, self.clearString)

    self.controls.compAudioRouter.Choices = namesTable
end

function AudioRouterController:populateRoomControlsChoices()
    local names = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls") then
            table.insert(names, comp.Name)
        end
    end
    table.sort(names)
    table.insert(names, self.clearString)
    self.controls.compRoomControls.Choices = names
end


--------** Component Setup **--------
function AudioRouterController:setAudioRouterComponent()
    -- Clean up old event handlers if switching devices
    if self.audioRouter then
        if self.audioRouter["select.1"].EventHandler then
            self.audioRouter["select.1"].EventHandler = nil
        end
        self:debugPrint("Cleanup completed to due to switching devices")
    end

    -- Now assign the new device
    self.audioRouter = self:setComponent(self.controls.compAudioRouter, "Audio Router")
    if self.audioRouter ~= nil then
        self.audioRouter["select.1"].EventHandler = function(ctl)
            for i, btn in ipairs(self.controls.btnAudioSource) do
                btn.Boolean = (i == ctl.Value)
            end
            self:debugPrint("Audio Router set Output 1 to Input " .. ctl.Value)
        end
    end
end

function AudioRouterController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if self.roomControls ~= nil then
        -- Add event handlers for system power and fire alarm
        local this = self  -- Capture self for use in handlers

        self.roomControls["ledSystemPower"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:setRoute(this.inputs.XLR01, this.outputs.OUTPUT01) -- System power on: route to XLR01
            else
                this:setRoute(this.inputs.NONE, this.outputs.OUTPUT01) -- System power off: route to NONE
            end
        end
        -- Fire alarm active: route to NONE        
        self.roomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:setRoute(this.inputs.NONE, this.outputs.OUTPUT01)
            else
               if Controls.ledSystemPower.Boolean then -- If system power was On, set the route to Default
               -- Fire alarm cleared: revert to last input (or default to XLR01) 
               this:setRoute(this.lastInput[this.outputs.OUTPUT01] or this.inputs.XLR01, this.outputs.OUTPUT01)
               end
            end
        end
    end
end

--------** Audio Routing Functions **--------
function AudioRouterController:setRoute(input, output)
    if self.audioRouter then
        self.audioRouter["select."..tostring(output)].Value = input
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(input))
        self.lastInput[output] = input
    end
end

--------** Event Handler Registration **--------
function AudioRouterController:registerEventHandlers()
    -- Audio Router component handler
    self.controls.compAudioRouter.EventHandler = function()
        self:setAudioRouterComponent()
    end

    -- Room Controls component handler
    self.controls.compRoomControls.EventHandler = function()
        self:setRoomControlsComponent()
    end

    -- Audio Source button handlers
    for i, btn in ipairs(self.controls.btnAudioSource) do
        btn.EventHandler = function()
            self:setRoute(i, self.outputs.OUTPUT01)
        end
    end
end

--------** Initialization **--------
function AudioRouterController:funcInit()
    self:getComponentNames()
    self:populateRoomControlsChoices()
    self:setAudioRouterComponent()
    self:setRoomControlsComponent()
    self:debugPrint("Audio Router Controller Initialized")
end

--------** Cleanup **--------
function AudioRouterController:cleanup()
    if self.audioRouter and self.audioRouter["select.1"].EventHandler then
        self.audioRouter["select.1"].EventHandler = nil
    end
    
    if self.roomControls and self.roomControls["ledSystemPower"].EventHandler then
        self.roomControls["ledSystemPower"].EventHandler = nil
    end
    if self.roomControls and self.roomControls["ledFireAlarm"].EventHandler then
        self.roomControls["ledFireAlarm"].EventHandler = nil
    end 
    self:debugPrint("Cleanup completed")
end


--------** Factory Function **--------
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

--------** Instance Creation **--------
-- Create the main audio router controller instance
myAudioRouterController = createAudioRouterController()

--------** Usage Examples **--------
--[[
-- Example usage of the audio router controller:

-- Set a route manually
myAudioRouterController:setRoute(1, 1)  -- Set Output 1 to Input 1

-- Get current route
local currentInput = myAudioRouterController.audioRouter["select.1"].Value

-- Update source buttons
for i, btn in ipairs(Controls.btnAudioSource) do
    btn.Boolean = (i == currentInput)
end
]]-- 