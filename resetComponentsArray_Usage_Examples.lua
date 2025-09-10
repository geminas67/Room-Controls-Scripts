--[[
resetComponentsArray Utility Function - Usage Examples
Author: Nikolas Smith, Q-SYS
Date: 2025-09-09

This file demonstrates how to use the resetComponentsArray utility function
from Q-SysControllerUtilities.lua in various Q-SYS controller scenarios.

The utility provides modular, consistent logic for managing dynamic component arrays
that need to be reset and repopulated based on control selections.
]]--

-- First, require the utilities module
local QSysControllerUtils = require("Q-SysControllerUtilities")

--[[
=================================================================================
EXAMPLE 1: Basic Usage - Audio Gain Components
=================================================================================
]]--

-- Example controller class that inherits utility functions
local AudioController = {}
AudioController.__index = AudioController

function AudioController.new(roomName)
    local self = setmetatable({}, AudioController)
    self.roomName = roomName
    self.debugging = true
    self.components = {
        gains = {},
        invalid = {}
    }
    
    -- Inject utility functions into this controller
    QSysControllerUtils.injectAccessors(self)
    
    return self
end

-- Add utility functions to the controller
function AudioController:debugPrint(str)
    if self.debugging then print("["..self.roomName.."] "..str) end
end

function AudioController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
end

function AudioController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
end

-- Population function for gain components
function AudioController:populateGainComponent(ctrl, index)
    -- Use the built-in populateComponent helper
    return QSysControllerUtils.populateComponent(self, ctrl, index, "Gain")
end

-- Method to reset and repopulate gain components
function AudioController:resetGainComponents()
    local controlsArray = Controls.compGains or {}
    
    -- Reset the gains array using the utility
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.gains,     -- Component table to reset
        controlsArray,             -- Array of controls
        self.populateGainComponent, -- Population function
        self                       -- Context (self)
    )
    
    self:debugPrint("Reset completed for "..#controlsArray.." gain controls")
end

--[[
=================================================================================
EXAMPLE 2: Advanced Usage - Display Components with Event Binding
=================================================================================
]]--

function AudioController:populateDisplayComponent(ctrl, index)
    local component = QSysControllerUtils.populateComponent(self, ctrl, index, "Display")
    
    if component then
        -- Bind event handlers after creation
        if component["PowerOnTrigger"] then
            component["PowerOnTrigger"].EventHandler = function()
                self:debugPrint("Display ["..index.."] powered on")
            end
        end
        
        if component["PowerOffTrigger"] then
            component["PowerOffTrigger"].EventHandler = function()
                self:debugPrint("Display ["..index.."] powered off")
            end
        end
    end
    
    return component
end

function AudioController:resetDisplayComponents()
    local controlsArray = Controls.devDisplays or {}
    
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.displays or {},
        controlsArray,
        self.populateDisplayComponent,
        self
    )
end

--[[
=================================================================================
EXAMPLE 3: Simple Usage without Context - MXA Devices
=================================================================================
]]--

-- Simple population function that doesn't need 'self' context
local function populateMXADevice(ctrl, index)
    if not ctrl or not ctrl.String or ctrl.String == "" or ctrl.String == "[Clear]" then
        return nil
    end
    
    local component = Component.New(ctrl.String)
    if #Component.GetControls(component) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        return nil
    end
    
    ctrl.Color = "white"
    print("MXA Device ["..index.."] initialized: "..ctrl.String)
    return component
end

function AudioController:resetMXADevices()
    local controlsArray = Controls.devMXAs or {}
    self.components.mxaDevices = self.components.mxaDevices or {}
    
    -- No context needed, so pass nil
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.mxaDevices,
        controlsArray,
        populateMXADevice,
        nil  -- No context
    )
end

--[[
=================================================================================
EXAMPLE 4: Integration with Room Combination/Division Events
=================================================================================
]]--

function AudioController:onRoomTopologyChange()
    self:debugPrint("Room topology changed - resetting all component arrays")
    
    -- Reset all component arrays when room combine/divide occurs
    self:resetGainComponents()
    self:resetDisplayComponents()
    self:resetMXADevices()
    
    -- Update component choices if needed
    self:refreshComponentChoices()
end

function AudioController:refreshComponentChoices()
    -- This would typically be called after resetComponentsArray
    -- to update the .Choices for controls based on available components
    
    local gainNames = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "gain" then
            table.insert(gainNames, comp.Name)
        end
    end
    
    if Controls.compGains then
        for _, ctrl in ipairs(Controls.compGains) do
            ctrl.Choices = gainNames
        end
    end
end

--[[
=================================================================================
EXAMPLE 5: Error Handling and Validation
=================================================================================
]]--

function AudioController:safeResetComponents(componentTable, controlsArray, populateFunc)
    -- Validate inputs before calling resetComponentsArray
    if not componentTable then
        self:debugPrint("Error: componentTable is nil")
        return false
    end
    
    if not controlsArray or #controlsArray == 0 then
        self:debugPrint("Warning: controlsArray is empty or nil")
        return false
    end
    
    if not populateFunc then
        self:debugPrint("Error: populateFunc is nil")
        return false
    end
    
    -- Call the utility with error handling
    local success = QSysControllerUtils.resetComponentsArray(
        self,
        componentTable,
        controlsArray,
        populateFunc,
        self
    )
    
    if not success then
        self:debugPrint("resetComponentsArray failed")
        return false
    end
    
    return true
end

--[[
=================================================================================
EXAMPLE 6: Usage in Existing Controller Patterns
=================================================================================
]]--

-- How to integrate with SystemAutomationController pattern
function AudioController:setGainComponent(idx)
    -- Original pattern from SystemAutomationController
    -- self.components.gains[idx] = self:setComponent(Controls.compGains[idx], "Gain [" .. idx .. "]")
    
    -- New pattern using resetComponentsArray for single component
    local singleControlArray = { Controls.compGains[idx] }
    local tempTable = {}
    
    QSysControllerUtils.resetComponentsArray(
        self,
        tempTable,
        singleControlArray,
        self.populateGainComponent,
        self
    )
    
    self.components.gains[idx] = tempTable[1]
end

-- How to integrate with batch component setup
function AudioController:initializeAllComponents()
    self:debugPrint("Initializing all components using resetComponentsArray")
    
    -- Initialize component arrays
    self.components.gains = {}
    self.components.displays = {}
    self.components.mxaDevices = {}
    
    -- Reset and populate all arrays
    self:resetGainComponents()
    self:resetDisplayComponents() 
    self:resetMXADevices()
    
    self:debugPrint("Component initialization complete")
end

--[[
=================================================================================
USAGE SUMMARY
=================================================================================

Basic Syntax:
QSysControllerUtils.resetComponentsArray(self, componentTable, controlsArray, populateFunc, context)

Parameters:
- self: The controller instance (for logging)
- componentTable: Table to clear and repopulate (e.g., self.components.gains)
- controlsArray: Array of UI controls that define selections (e.g., Controls.compGains)
- populateFunc: Function that creates components from controls
- context: Optional context passed to populateFunc (usually 'self')

Use Cases:
1. Room topology changes (combine/divide)
2. Component .Choices list updates
3. System initialization
4. Component reinitialization after errors
5. Dynamic component management

Benefits:
- Consistent component clearing and repopulation
- Error handling and logging
- Reusable across different component types
- Integrates with existing Q-SYS patterns
- Modular and maintainable code
]]--

-- Example usage in a script
--[[
local myController = AudioController.new("Conference Room A")
myController:initializeAllComponents()

-- Later, when room topology changes:
myController:onRoomTopologyChange()
]]--
