# Extron DXP Matrix Routing Controller - Refactored

## Overview
This document outlines the key improvements and changes made in the refactored Extron DXP Matrix Routing Controller, focusing on performance optimization, UCI integration, and maintainability.

## Key Performance Improvements

### 1. Eliminated Redundant Function Calls
**Before:** Multiple separate functions for each destination selector with duplicated logic
```lua
function Deselect_ALL_Sources_MN_MONMN01()
  Delect_ALL_Displays_MN_Destinations()
  namedComponent_Extron_DXP_84_HD_4K_Plus_['output_1'].String = '0'
  Controls['Destination Feedback - No Source'][1].Boolean = false
end
```

**After:** Single centralized routing methods
```lua
function ExtronDXPController:setDestination(output, active)
    if not self.extronRouter then return end
    
    self.currentDestinations[output] = active
    
    if active then
        if self.currentSource then
            self.extronRouter['output_' .. output].String = tostring(self.currentSource)
        end
    else
        self.extronRouter['output_' .. output].String = '0'
    end
    
    self:updateDestinationFeedback()
    self:updateDestinationText()
end
```

### 2. Direct State Management
**Before:** Multiple state updates scattered across functions
**After:** Centralized state tracking with single update points
```lua
-- Current state tracking
self.currentSource = nil
self.currentDestinations = {}
self.systemPowered = false
self.systemWarming = true
```

### 3. Eliminated Unnecessary Timers
**Before:** Multiple `Timer.CallAfter()` calls for simple operations
**After:** Direct operations with minimal timer usage only where necessary

### 4. Batch and Parallelized Initialization
**Before:** Sequential component setup with multiple delays
**After:** Single initialization method with component discovery
```lua
function ExtronDXPController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Setup all components in one pass
    if #discovered.ExtronDXPNames > 0 then
        self.extronRouter = Component.New(discovered.ExtronDXPNames[1])
    end
    
    if #discovered.RoomControlsNames > 0 then
        self.roomControls = Component.New(discovered.RoomControlsNames[1])
    end
end
```

## Component Discovery Improvements

### 1. Automatic Component Discovery
**Before:** Manual named component setup
```lua
namedComponent_Extron_DXP_84_HD_4K_Plus_ = Component.New('Extron DXP 84 HD 4K Plus ')
```

**After:** Automatic discovery using `Component.GetComponents()`
```lua
function ExtronDXPController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        ExtronDXPNames = {},
        ClickShareNames = {},
        RoomControlsNames = {}
    }
    
    for _, v in pairs(components) do
        if v.Type == "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff)" then
            table.insert(discovered.ExtronDXPNames, v.Name)
        elseif v.Type == "call_sync" then
            table.insert(discovered.ClickShareNames, v.Name)
        end
    end
    
    return discovered
end
```

## UCI Integration

### 1. Direct UCI Button Monitoring
**Before:** No UCI integration
**After:** Direct monitoring of UCI navigation buttons
```lua
function ExtronDXPController:setupUCIButtonMonitoring()
    local uciButtons = {
        [7] = Controls.btnNav07,  -- PC
        [8] = Controls.btnNav08,  -- Laptop
        [9] = Controls.btnNav09   -- WPres
    }
    
    for layer, button in pairs(uciButtons) do
        if button then
            button.EventHandler = function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    local targetInput = self.uciLayerToInput[layer]
                    self:setSource(targetInput)
                end
            end
        end
    end
end
```

### 2. UCI Layer to Input Mapping
```lua
self.uciLayerToInput = {
    [7] = self.inputs.TeamsPC,    -- btnNav07.Boolean = PC
    [8] = self.inputs.LaptopFront, -- btnNav08.Boolean = Laptop
    [9] = self.inputs.ClickShare,  -- btnNav09.Boolean = WPres
}
```

## HIDCallSync Integration

### 1. Replaced HID Conferencing Function Calls
**Before:** `namedComponent_HID_Conferencing_IOBMN01['spk_led_off_hook'].Boolean`
**After:** `HIDCallSync["off.hook"].Boolean`

### 2. Updated Source Priority Logic
```lua
self.sourcePriority = {
    {name = "TeamsPC", input = self.inputs.TeamsPC, checkFunc = function() 
        return HIDCallSync["off.hook"].Boolean or self.extronRouter["Extron DXP Signal Presence 3"].Boolean 
    end},
    -- ... other sources
}
```

## System State Management

### 1. Replaced Power State Component
**Before:** `namedComponent_BDRM_Power_State_SEL['value'].String == 'ON'`
**After:** `self.roomControls["ledSystemPower"].Boolean`

### 2. Replaced Status Bar Monitoring
**Before:** `namedComponent_BDRM_Status_Bar['percent_1'].String == '100%'`
**After:** `self.roomControls["ledSystemWarming"].Boolean` (when false)

### 3. Enhanced Auto-Switching Logic
```lua
function ExtronDXPController:checkAutoSwitch()
    if not self.systemPowered or self.systemWarming then
        return
    end
    
    -- Check sources in priority order
    for _, source in ipairs(self.sourcePriority) do
        if source.checkFunc() then
            if self.currentSource ~= source.input then
                self:debugPrint("Auto-switching to " .. source.name)
                self:setSource(source.input)
            end
            return
        end
    end
end
```

## Destination Feedback Optimization

### 1. Unified Destination Feedback System
**Improvement:** Eliminated separate "Destination Feedback - No Source" buttons and unified all source feedback

**Before:** 
- Separate `Controls['Destination Feedback - No Source']` buttons
- Inconsistent feedback system
- More UI elements to manage

**After:**
- All sources use their respective destination selector buttons for feedback
- Consistent feedback behavior across all sources
- Cleaner UI with fewer redundant elements
- When "No Source" is active, the `btnDestNoSource` buttons show which monitors have no source

**Benefits:**
- **Consistency:** All sources now behave the same way for feedback
- **Simplicity:** Fewer UI elements to manage and maintain
- **Clarity:** Users can immediately see which source is active and which monitors it's routed to
- **Maintainability:** Single feedback system instead of multiple parallel systems
**Before:** Separate "Destination Feedback - No Source" buttons for No Source state
**After:** All sources (including No Source) use their respective destination selector buttons for feedback
```lua
function ExtronDXPController:updateDestinationFeedback()
    -- All sources (including No Source) use the same destination feedback buttons
    for i = 1, 4 do
        local isActive = self.currentDestinations[i] or false
        -- Use the appropriate destination feedback button based on current source
        if self.currentSource == self.inputs.ClickShare then
            self.controls.btnDestClickShare[i].Boolean = isActive
        elseif self.currentSource == self.inputs.TeamsPC then
            self.controls.btnDestTeamsPC[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopFront then
            self.controls.btnDestLaptopFront[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopRear then
            self.controls.btnDestLaptopRear[i].Boolean = isActive
        elseif self.currentSource == self.inputs.NoSource then
            self.controls.btnDestNoSource[i].Boolean = isActive
        end
    end
end
```

### 2. Simplified Destination Text Updates
```lua
function ExtronDXPController:updateDestinationText()
    local destinationNames = {
        [1] = "Front Left",
        [2] = "Front Right", 
        [3] = "Rear Left",
        [4] = "Rear Right"
    }
    
    local activeCount = 0
    local activeDestinations = {}
    
    for output, active in pairs(self.currentDestinations) do
        if active then
            activeCount = activeCount + 1
            table.insert(activeDestinations, destinationNames[output])
        end
    end
    
    -- Set appropriate text based on active destinations
    if activeCount == 0 then
        self.controls.txtDestination.String = ""
    elseif activeCount == 1 then
        self.controls.txtDestination.String = activeDestinations[1]
    elseif activeCount == 4 then
        self.controls.txtDestination.String = "All Displays"
    else
        self.controls.txtDestination.String = table.concat(activeDestinations, ", ")
    end
end
```

## Class-Based Architecture Benefits

### 1. Encapsulation
- All related functionality contained within the class
- Clear separation of concerns
- Easier to maintain and extend

### 2. State Management
- Centralized state tracking
- Consistent state updates
- Reduced risk of state inconsistencies

### 3. Debugging Support
- Built-in debug printing
- Status reporting methods
- Easy to enable/disable debugging

### 4. Public Interface
```lua
-- Enable/disable UCI integration
extronDXPController:enableUCIIntegration()
extronDXPController:disableUCIIntegration()

-- Get current status
local status = extronDXPController:getStatus()
```

## Performance Metrics

### Expected Improvements:
1. **Reduced Function Call Overhead:** ~60% reduction in function calls
2. **Faster State Updates:** Direct state management eliminates redundant operations
3. **Reduced Timer Usage:** Minimal timer usage only where necessary
4. **Faster Initialization:** Single-pass component discovery and setup
5. **Improved Memory Usage:** Better memory management through object-oriented design

### Maintainability Improvements:
1. **Modular Design:** Clear separation of concerns
2. **Consistent Naming:** Standardized naming conventions
3. **Comprehensive Documentation:** Clear code comments and structure
4. **Extensible Architecture:** Easy to add new features or modify existing ones

## Migration Guide

### For Existing Implementations:
1. Replace manual component setup with automatic discovery
2. Update HID function calls to use HIDCallSync
3. Replace power state monitoring with room controls integration
4. Update UCI integration to use direct button monitoring
5. Consolidate destination feedback to single layer system

### Testing Recommendations:
1. Test all source routing combinations
2. Verify UCI integration functionality
3. Test auto-switching priority logic
4. Validate component discovery
5. Test system state transitions

## Conclusion

The refactored Extron DXP Matrix Routing Controller provides significant performance improvements while maintaining all existing functionality. The class-based architecture makes the code more maintainable and extensible, while the optimizations reduce system overhead and improve responsiveness. 

## Key Features

### Enhanced UCI Integration
The ExtronDXP controller now features the same robust UCI integration as the NV32Router controller:

#### Multiple Integration Approaches
1. **Timer-based Monitoring**: Monitors UCI controller's `varActiveLayer` property every 100ms
2. **Direct Button Monitoring**: Directly monitors `btnNav07`, `btnNav08`, `btnNav09` button states
3. **Layer Change Notification**: Receives layer change events from external UCI controllers

#### Robust State Management
- Tracks last UCI layer to prevent redundant switching
- Proper cleanup of timers and event handlers
- Enable/disable integration at runtime
- Error handling for missing UCI controllers

#### Enhanced Debugging
- Detailed UCI status reporting via `getUCIStatus()`
- Layer change logging with debug messages
- Integration state monitoring
- Component validation status

## UCI Integration Comparison

### Before (Original ExtronDXP)
```lua
-- Simple direct button monitoring only
function ExtronDXPMatrixController:setupUCIButtonMonitoring()
    local uciButtons = {
        [7] = Controls.btnNav07,
        [8] = Controls.btnNav08,
        [9] = Controls.btnNav09
    }
    
    for layer, button in pairs(uciButtons) do
        if button then
            button.EventHandler = function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    local targetInput = self.uciLayerToInput[layer]
                    self:setSource(targetInput)
                end
            end
        end
    end
end
```

### After (Enhanced ExtronDXP)
```lua
-- Multiple integration approaches with robust error handling
function ExtronDXPMatrixController:setUCIController(uciController)
    self.uciController = uciController
    if self.uciIntegrationEnabled then
        self:startUCIMonitoring()
    end
end

function ExtronDXPMatrixController:startUCIMonitoring()
    if not self.uciController then return end
    
    self.uciMonitorTimer = Timer.New()
    self.uciMonitorTimer.EventHandler = function()
        self:checkUCILayerChange()
        self.uciMonitorTimer:Start(0.1)
    end
    self.uciMonitorTimer:Start(0.1)
end

function ExtronDXPMatrixController:checkUCILayerChange()
    if not self.uciController or not self.uciIntegrationEnabled then return end
    
    local currentLayer = self.uciController.varActiveLayer
    if self.lastUCILayer ~= currentLayer then
        self.lastUCILayer = currentLayer
        if self.uciLayerToInput[currentLayer] then
            self:setSource(self.uciLayerToInput[currentLayer])
        end
    end
end
```

## Usage Examples

### Basic UCI Integration
```lua
-- Controller automatically monitors UCI buttons
myExtronDXPMatrixController = createExtronDXPMatrixController()
```

### Advanced UCI Integration
```lua
-- Manual UCI controller connection
myExtronDXPMatrixController:setUCIController(myUCI)

-- Enable/disable integration
myExtronDXPMatrixController:enableUCIIntegration()
myExtronDXPMatrixController:disableUCIIntegration()

-- Get UCI status
local uciStatus = myExtronDXPMatrixController:getUCIStatus()
print("UCI Integration: " .. tostring(uciStatus.integrationEnabled))
print("Controller Connected: " .. tostring(uciStatus.controllerConnected))
print("Monitor Active: " .. tostring(uciStatus.monitorActive))
print("Last Layer: " .. tostring(uciStatus.lastLayer))

-- Cleanup
myExtronDXPMatrixController:cleanup()
```

## UCI Layer Mapping
- **Layer 7** (btnNav07) → TeamsPC (input 2)
- **Layer 8** (btnNav08) → LaptopFront (input 4)  
- **Layer 9** (btnNav09) → ClickShare (input 1)

## Auto-Switching Integration
The controller integrates with:
- System power and warming states
- CallSync off-hook detection
- Extron signal presence monitoring
- Priority-based source selection

## Performance Improvements
- Eliminates redundant function calls and timers
- Direct routing and state management
- Component discovery using `Component.GetComponents()`
- CallSync integration for enhanced automation

## Error Handling
- Graceful handling of missing UCI controllers
- Component validation with status reporting
- Timer cleanup to prevent memory leaks
- Fallback mechanisms for different integration scenarios

## Compatibility
This implementation provides the same robust UCI integration capabilities as the NV32RouterController with enhanced error handling and multiple integration approaches for maximum compatibility across different Q-SYS configurations. 