--[[
SystemAutomationController Integration with resetComponentsArray Utility
Author: Nikolas Smith, Q-SYS
Date: 2025-09-09

This file demonstrates how to integrate the resetComponentsArray utility function
with the existing SystemAutomationController patterns for improved component management.

Benefits of Integration:
- Simplifies component array initialization
- Provides consistent reset/repopulation logic  
- Reduces code duplication
- Improves maintainability
- Better error handling and logging
- Easier to manage topology changes (room combine/divide)
]]--

-- Require the utilities module (would typically be at the top of SystemAutomationController)
local QSysControllerUtils = require("Q-SysControllerUtilities")


-------------------[ SystemAutomationController with resetComponentsArray Integration ]------------------------

-- Example of how to modify the existing SystemAutomationController constructor
function SystemAutomationController.new(roomName, config, defaultConfigs)
    local self = setmetatable({}, SystemAutomationController)
    self.roomName = roomName or "Default Room"
    self.debugging = config.debugging ~= false
    self.defaultConfigs = defaultConfigs
    self.state = { isWarming = false, isCooling = false, powerLocked = false, motionTimeoutActive = false, motionGraceActive = false }
    self.config = config
    
    -- Initialize component arrays (same as before)
    self.components = {
        callSync = nil, videoBridge = {}, displays = {}, gains = {}, systemMute = nil, camACPR = nil, invalid = {}
    }
    
    -- Inject utility functions into the controller
    QSysControllerUtils.injectAccessors(self)
    
    -- Rest of initialization...
    self.timers = {
        motion = Timer.New(), grace = Timer.New(), warmup = Timer.New(), cooldown = Timer.New()
    }
    self.audioModule    = AudioModule.new(self)
    self.videoModule    = VideoModule.new(self)
    self.displayModule  = DisplayModule.new(self)
    self.powerModule    = PowerModule.new(self)
    self.motionModule   = MotionModule.new(self)
    self:registerTimerHandlers()
    return self
end


-------------------[ Component Population Functions using resetComponentsArray ]------------------------

-- Enhanced gain component population function
function SystemAutomationController:populateGainComponent(ctrl, index)
    if not ctrl or not ctrl.String or ctrl.String == "" or ctrl.String == self.clearString then
        return nil
    end
    
    local component = Component.New(ctrl.String)
    if #Component.GetControls(component) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid("Gain [" .. index .. "]")
        return nil
    end
    
    ctrl.Color = "white"
    self:setComponentValid("Gain [" .. index .. "]")
    
    -- Register component event handlers
    if component["gain"] then
        component["gain"].EventHandler = function() self:getVolumeLvl(index) end
    end
    if component["mute"] then
        component["mute"].EventHandler = function() self:getVolumeMute(index) end
    end
    
    self:debugPrint("Gain component [" .. index .. "] initialized: " .. ctrl.String)
    return component
end

-- Enhanced display component population function  
function SystemAutomationController:populateDisplayComponent(ctrl, index)
    if not ctrl or not ctrl.String or ctrl.String == "" or ctrl.String == self.clearString then
        return nil
    end
    
    local component = Component.New(ctrl.String)
    if #Component.GetControls(component) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid("Display [" .. index .. "]")
        return nil
    end
    
    ctrl.Color = "white" 
    self:setComponentValid("Display [" .. index .. "]")
    
    self:debugPrint("Display component [" .. index .. "] initialized: " .. ctrl.String)
    return component
end

-- Enhanced video bridge component population function
function SystemAutomationController:populateVideoBridgeComponent(ctrl, index)
    if not ctrl or not ctrl.String or ctrl.String == "" or ctrl.String == self.clearString then
        return nil
    end
    
    local component = Component.New(ctrl.String)
    if #Component.GetControls(component) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        local label = index == 1 and "Video Bridge [Main]" or "Video Bridge [" .. index .. "]"
        self:setComponentInvalid(label)
        return nil
    end
    
    ctrl.Color = "white"
    local label = index == 1 and "Video Bridge [Main]" or "Video Bridge [" .. index .. "]" 
    self:setComponentValid(label)
    
    -- Register event handler for privacy toggle
    if component["toggle.privacy"] then
        component["toggle.privacy"].EventHandler = function() self:videoBridgeCheckPrivacy(index) end
    end
    
    -- Initialize privacy state
    self:getVideoBridgePrivacy(index)
    
    self:debugPrint("Video Bridge component [" .. index .. "] initialized: " .. ctrl.String)
    return component
end


-------------------[ Batch Component Reset Methods using resetComponentsArray ]------------------------

-- Reset and repopulate all gain components
function SystemAutomationController:resetGainComponents()
    if not controls.compGains then return end
    
    self:debugPrint("Resetting gain components array...")
    
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.gains,
        controls.compGains,
        self.populateGainComponent,
        self
    )
    
    -- Apply volume defaults after reset
    self:applyVolumeDefaults()
end

-- Reset and repopulate all display components
function SystemAutomationController:resetDisplayComponents()
    if not controls.devDisplays then return end
    
    self:debugPrint("Resetting display components array...")
    
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.displays,
        controls.devDisplays, 
        self.populateDisplayComponent,
        self
    )
end

-- Reset and repopulate all video bridge components
function SystemAutomationController:resetVideoBridgeComponents()
    if not controls.compVideoBridge then return end
    
    self:debugPrint("Resetting video bridge components array...")
    
    QSysControllerUtils.resetComponentsArray(
        self,
        self.components.videoBridge,
        getControlArray(controls.compVideoBridge),
        self.populateVideoBridgeComponent,
        self
    )
end

-- Reset all component arrays (useful for topology changes)
function SystemAutomationController:resetAllComponentArrays()
    self:debugPrint("Resetting all component arrays...")
    
    self:resetGainComponents()
    self:resetDisplayComponents() 
    self:resetVideoBridgeComponents()
    
    self:debugPrint("All component arrays reset completed")
end




-------------------[ Initialization Method ]------------------------

-- Enhanced initialization using batch reset methods
function SystemAutomationController:init()
    self.powerModule:enableDisablePowerControls(true)
    self:getComponentNames()
    setProp(controls.txtMotionMode, "Choices", { "Motion On/Off", "Motion Off", "Motion Disabled" })
    
    -- Setup typeGain dropdown choices (same as before)
    if controls.typeGain then
        local gainChoices = { "Program", "Mic", "Gain" }
        for i, gainControl in ipairs(getControlArray(controls.typeGain)) do
            if gainControl then
                gainControl.Choices = gainChoices
                if i == 1 then
                    gainControl.String = "Program"
                    gainControl.IsDisabled = true
                end
            end
        end
    end
    
    self:setGainTypeAssignments()
    
    -- Initialize single components (unchanged)
    self:setCallSyncComponent()
    self:setSystemMuteComponent()
    self:setCamACPRComponent()
    
    -- NEW: Use batch reset methods for component arrays
    self:resetAllComponentArrays()
    
    self:debugPrint("SystemAutomationController ready; "..self.audioModule:getGainCount().." gain controls detected.")
end

-------------------[ Room Topology Change Handler ]------------------------

-- Handler for room topology changes (combine/divide)
function SystemAutomationController:onRoomTopologyChange()
    self:debugPrint("Room topology change detected - resetting component arrays")
    
    -- Update component choices first
    self:getComponentNames()
    
    -- Reset all component arrays to reflect new topology
    self:resetAllComponentArrays()
    
    -- Re-register event handlers
    self:registerEventHandlers()
    
    self:debugPrint("Room topology change handling completed")
end

-- Method to call when component choices are updated
function SystemAutomationController:onComponentChoicesUpdated()
    self:debugPrint("Component choices updated - resetting arrays")
    self:resetAllComponentArrays()
end


-------------------[ Event Handler Registration with Reset Support ]------------------------

-- Enhanced event handler registration with reset support
function SystemAutomationController:registerEventHandlers()
    -- ... existing event handlers ...
    
    -- Add handlers for component choice changes - use batch reset for consistency
    forEach(controls.compGains, function(i, ctrl)
        bind(ctrl, function() 
            self:resetGainComponents()
        end) 
    end)
    
    forEach(controls.devDisplays, function(i, ctrl)
        bind(ctrl, function() 
            self:resetDisplayComponents()
        end) 
    end)
    
    forEach(controls.compVideoBridge, function(i, ctrl)
        bind(ctrl, function() 
            self:resetVideoBridgeComponents()
        end) 
    end)
    
    -- ... rest of event handlers ...
end

--[[
USAGE COMPARISON: Before vs After
]]--

--[[
BEFORE (Original Pattern):
------------------------
function SystemAutomationController:init()
    -- ... setup code ...
    
    forEach(controls.compVideoBridge, function(i) self:setVideoBridgeComponent(i) end)
    forEach(controls.compGains, function(i) self:setGainComponent(i) end)
    forEach(controls.devDisplays, function(i) self:setDisplayComponent(i) end)
end

NOTE: Individual setter methods (setGainComponent, setDisplayComponent, setVideoBridgeComponent) 
have been removed. All component updates now use batch reset methods for consistency.

AFTER (With resetComponentsArray):
---------------------------------
function SystemAutomationController:init()
    -- ... setup code ...
    
    self:resetAllComponentArrays()  -- Much cleaner and more maintainable
end

BENEFITS:
---------
1. Single method call replaces multiple forEach loops
2. Consistent error handling across all component types
3. Better logging and debugging information
4. Easier to add new component types
5. Built-in support for topology changes
6. Reduced code duplication
7. More robust component validation
]]--

--[[
=================================================================================
INTEGRATION CHECKLIST
=================================================================================

To integrate resetComponentsArray into SystemAutomationController:

1. ✓ Add QSysControllerUtils require statement
2. ✓ Inject utility functions in constructor  
3. ✓ Create populate functions for each component type
4. ✓ Create reset methods for each component array
5. ✓ Update init() method to use batch reset
6. ✓ Add topology change handler
7. ✓ Update event handlers to use batch reset methods
8. ✓ Add enhanced error handling and logging

TESTING:
--------
1. Test component initialization on startup
2. Test component changes via event handlers (should trigger batch reset)
3. Test batch component reset
4. Test error handling with invalid components
5. Test room topology changes
]]--
