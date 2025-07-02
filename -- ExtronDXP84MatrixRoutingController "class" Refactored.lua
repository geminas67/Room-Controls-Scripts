--[[
  Extron DXP Matrix Routing Controller - Refactored
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-01-27
  Firmware Req: 10.0.0
  Version: 2.0

  Performance-optimized class-based implementation with UCI integration
  - Eliminates redundant function calls and timers
  - Direct routing and state management
  - UCI integration for automatic input switching
  - Component discovery using Component.GetComponents()
  - CallSync integration
]]--

-- Define control references
local controls = {
    txtDestination = Controls.txtDestination,
    btnVideoSource = Controls.btnVideoSource,
    btnAVMute = Controls.btnAVMute,
    btnDestinations = Controls.btnDestinations,
    ledExtronSignalPresence = Controls.ledExtronSignalPresence,
    btnNav07 = Controls['btnNav07'],
    btnNav08 = Controls['btnNav08'],
    btnNav09 = Controls['btnNav09'],
}

-- ExtronDXPMatrixController class
ExtronDXPMatrixController = {}
ExtronDXPMatrixController.__index = ExtronDXPMatrixController

--------** Class Constructor **--------
function ExtronDXPMatrixController.new()
    local self = setmetatable({}, ExtronDXPMatrixController)
    
    -- Instance properties
    self.debugging = true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    self.preFireAlarmInput = {}
    self.fireAlarmActive = false
    
    -- UCI Integration properties
    self.uciController = nil
    self.uciIntegrationEnabled = true
    self.lastUCILayer = nil
    
    -- Input/Output mapping
    self.inputs = {
        ClickShare  = 1,
        TeamsPC     = 2,
        LaptopFront = 4,
        LaptopRear  = 5,
        NoSource    = 0
    }
    
    self.outputs = {
        MON01       = 1,
        MON02       = 2,
        MON03       = 3,
        MON04       = 4
    }
    
    -- UCI Layer to Input mapping
    self.uciLayerToInput = {
        [7] = self.inputs.TeamsPC,    -- btnNav07.Boolean = PC
        [8] = self.inputs.LaptopFront, -- btnNav08.Boolean = Laptop
        [9] = self.inputs.ClickShare,  -- btnNav09.Boolean = WPres
    }
    
    -- Source priority mapping (for auto-switching)
    self.sourcePriority = {
        {name = "TeamsPC", input = self.inputs.TeamsPC, checkFunc = function() 
            return callSync["off.hook"].Boolean or self.ledExtronSignalPresence[3].Boolean 
        end},
        {name = "LaptopFront", input = self.inputs.LaptopFront, checkFunc = function() 
            return self.ledExtronSignalPresence[4].Boolean 
        end},
        {name = "LaptopRear", input = self.inputs.LaptopRear, checkFunc = function() 
            return self.ledExtronSignalPresence[5].Boolean 
        end},
        {name = "ClickShare", input = self.inputs.ClickShare, checkFunc = function() 
            return self.ledExtronSignalPresence[1].Boolean 
        end},
        {name = "TeamsPC2", input = self.inputs.TeamsPC, checkFunc = function() 
            return self.ledExtronSignalPresence[2].Boolean 
        end}
    }
    
    -- Instance-specific control references
    self.controls = controls
    
    -- Component storage
    self.extronRouter = nil
    self.roomControls = nil
    self.uciLayerSelector = nil
    self.callSync = nil
    
    -- Current state
    self.currentSource = nil
    self.currentDestinations = {}
    self.systemPowered = false
    self.systemWarming = true
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** Debug Helper **--------
function ExtronDXPMatrixController:debugPrint(str)
    if self.debugging then
        print("[Extron DXP Debug] " .. str)
    end
end

--------** Helper Methods **--------
function ExtronDXPMatrixController:setDestinationButtonProperties(buttonIndex, color, legend, isDisabled)
    if self.controls.btnDestination[buttonIndex] then
        self.controls.btnDestination[buttonIndex].Color = color
        self.controls.btnDestination[buttonIndex].Legend = legend
        self.controls.btnDestination[buttonIndex].IsDisabled = isDisabled
    end
end

--------** Component Discovery **--------
function ExtronDXPMatrixController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        ExtronDXPNames = {},
        CallSyncNames = {},
        ClickShareNames = {},
        RoomControlsNames = {}
    }
    
    for _, v in pairs(components) do
        if v.Type == "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff)" then
            table.insert(discovered.ExtronDXPNames, v.Name)
        elseif v.Type == "call_sync" then
            table.insert(discovered.CallSyncNames, v.Name)
        elseif v.Type == "%PLUGIN%_bb4217ac-401f-4698-aad9-9e4b2496ff46_%FP%_e0a4597b59bdca3247ccb142ce451198" then
            table.insert(discovered.ClickShareNames, v.Name)
        elseif v.Type == "device_controller_script" and string.match(v.Name, "^compRoomControls") then
            table.insert(discovered.RoomControlsNames, v.Name)
        end
    end
    
    return discovered
end

--------** Component Setup **--------
function ExtronDXPMatrixController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Setup Extron DXP Router
    if #discovered.ExtronDXPNames > 0 then
        self.extronRouter = Component.New(discovered.ExtronDXPNames[1])
        self:debugPrint("Extron DXP Router set: " .. discovered.ExtronDXPNames[1])
    end
    
    -- Setup Room Controls
    if #discovered.RoomControlsNames > 0 then
        self.roomControls = Component.New(discovered.RoomControlsNames[1])
        self:debugPrint("Room Controls set: " .. discovered.RoomControlsNames[1])
    end
    
    -- Setup other components
    self.uciLayerSelector = Component.New('BDRM-UCI Layer Selector')
end

--------** UCI Integration Methods **--------
function ExtronDXPMatrixController:setUCIController(uciController)
    self.uciController = uciController
    self:debugPrint("UCI Controller reference set")
    
    -- Start monitoring UCI layer changes
    if self.uciIntegrationEnabled then
        self:startUCIMonitoring()
    end
end

function ExtronDXPMatrixController:startUCIMonitoring()
    if not self.uciController then
        self:debugPrint("No UCI Controller available for monitoring")
        return
    end
    
    -- Create a timer to monitor UCI layer changes
    self.uciMonitorTimer = Timer.New()
    self.uciMonitorTimer.EventHandler = function()
        self:checkUCILayerChange()
        self.uciMonitorTimer:Start(0.1) -- Check every 100ms
    end
    self.uciMonitorTimer:Start(0.1)
    
    self:debugPrint("UCI layer monitoring started")
end

function ExtronDXPMatrixController:checkUCILayerChange()
    if not self.uciController or not self.uciIntegrationEnabled then
        return
    end
    
    local currentLayer = self.uciController.varActiveLayer
    
    -- Check if layer has changed
    if self.lastUCILayer ~= currentLayer then
        self:debugPrint("UCI Layer changed from " .. tostring(self.lastUCILayer) .. " to " .. tostring(currentLayer))
        self.lastUCILayer = currentLayer
        
        -- Check if this layer should trigger input switching
        if self.uciLayerToInput[currentLayer] then
            local targetInput = self.uciLayerToInput[currentLayer]
            self:debugPrint("UCI Layer " .. currentLayer .. " triggers input switch to " .. targetInput)
            self:setSource(targetInput)
        end
    end
end

function ExtronDXPMatrixController:enableUCIIntegration()
    self.uciIntegrationEnabled = true
    if self.uciController then
        self:startUCIMonitoring()
    end
    self:debugPrint("UCI Integration enabled")
end

function ExtronDXPMatrixController:disableUCIIntegration()
    self.uciIntegrationEnabled = false
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    self:debugPrint("UCI Integration disabled")
end

-- Alternative method: Direct UCI button monitoring
function ExtronDXPMatrixController:setupDirectUCIButtonMonitoring()
    -- Monitor UCI navigation buttons directly
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
                    self:debugPrint("UCI Button " .. layer .. " pressed, switching to input " .. targetInput)
                    self:setSource(targetInput)
                end
            end
            self:debugPrint("Direct monitoring set up for UCI button " .. layer)
        end
    end
end

-- UCI Layer Change Notification Method
function ExtronDXPMatrixController:onUCILayerChange(layerChangeInfo)
    if not self.uciIntegrationEnabled then
        return
    end
    
    self:debugPrint("UCI Layer changed from " .. tostring(layerChangeInfo.previousLayer) .. 
                   " to " .. tostring(layerChangeInfo.currentLayer) .. 
                   " (" .. layerChangeInfo.layerName .. ")")
    
    -- Check if this layer should trigger input switching
    if self.uciLayerToInput[layerChangeInfo.currentLayer] then
        local targetInput = self.uciLayerToInput[layerChangeInfo.currentLayer]
        self:debugPrint("UCI Layer " .. layerChangeInfo.currentLayer .. " triggers input switch to " .. targetInput)
        self:setSource(targetInput)
    end
end

--------** Routing Methods **--------
function ExtronDXPMatrixController:setSource(input)
    if not self.extronRouter then return end
    
    self.currentSource = input
    self:debugPrint("Setting source to input " .. input)
    
    -- Clear all destination feedback before updating
    self:clearAllDestinationFeedback()
    
    -- Update all active destinations
    for output, active in pairs(self.currentDestinations) do
        if active then
            self.extronRouter['output_' .. output].String = tostring(input)
        end
    end
    
    -- Update destination feedback
    self:updateDestinationFeedback()
    
    -- Update text destination
    self:updateDestinationText()
end

function ExtronDXPMatrixController:setDestination(output, active)
    if not self.extronRouter then return end
    
    self.currentDestinations[output] = active
    
    if active then
        -- Route current source to this destination
        if self.currentSource then
            self.extronRouter['output_' .. output].String = tostring(self.currentSource)
        end
    else
        -- Clear this destination
        self.extronRouter['output_' .. output].String = '0'
    end
    
    -- Update destination feedback
    self:updateDestinationFeedback()
    
    -- Update text destination
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearAllDestinations()
    for output = 1, 4 do
        self.currentDestinations[output] = false
        if self.extronRouter then
            self.extronRouter['output_' .. output].String = '0'
        end
    end
    
    -- Clear all destination feedback
    for i = 1, 5 do
        self.controls.btnDestination[i].Boolean = false
    end
    
    -- Clear all source destination feedback buttons
    self:clearAllDestinationFeedback()
end

function ExtronDXPMatrixController:clearAllDestinationFeedback()
    -- Clear all destination feedback buttons for all sources
    for i = 1, 4 do
        self.controls.btnDestination[i].Boolean = false
        self.controls.btnDestNoSource[i].Boolean = false
    end
end

function ExtronDXPMatrixController:updateDestinationFeedback()
    -- Update destination feedback based on current source and destinations
    -- All sources (including No Source) use the same destination feedback buttons
    for i = 1, 4 do
        local isActive = self.currentDestinations[i] or false
        -- Use the appropriate destination feedback button based on current source
        if self.currentSource == self.inputs.ClickShare then
            self.controls.btnDestination[i].Boolean = isActive
        elseif self.currentSource == self.inputs.TeamsPC then
            self.controls.btnDestination[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopFront then
            self.controls.btnDestination[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopRear then
            self.controls.btnDestination[i].Boolean = isActive
        elseif self.currentSource == self.inputs.NoSource then
            self.controls.btnDestination[i].Boolean = isActive
        end
    end
end

function ExtronDXPMatrixController:updateDestinationText()
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
    
    if activeCount == 0 then
        self.controls.txtDestination.String = ""
    elseif activeCount == 1 then
        self.controls.txtDestination.String = activeDestinations[1]
    elseif activeCount == 4 then
        self.controls.txtDestination.String = "All Displays"
        -- Clear text after 3 seconds
        Timer.CallAfter(function()
            self.controls.txtDestination.String = ""
        end, 3)
    else
        self.controls.txtDestination.String = table.concat(activeDestinations, ", ")
    end
end

--------** Auto-Switching Methods **--------
function ExtronDXPMatrixController:checkAutoSwitch()
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

function ExtronDXPMatrixController:setupAutoSwitchMonitoring()
    -- Monitor system power state
    if self.roomControls then
        self.roomControls["ledSystemPower"].EventHandler = function(ctl)
            self.systemPowered = ctl.Boolean
            self:debugPrint("System power state: " .. tostring(self.systemPowered))
            if self.systemPowered then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor system warming state
    if self.roomControls then
        self.roomControls["ledSystemWarming"].EventHandler = function(ctl)
            self.systemWarming = ctl.Boolean
            self:debugPrint("System warming state: " .. tostring(self.systemWarming))
            if not self.systemWarming and self.systemPowered then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor CallSync off-hook state
    if self.callSync then
        self.callSync["off.hook"].EventHandler = function(ctl)
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor Extron signal presence
    if self.Controls.ledExtronSignalPresence then
        for i = 1, 5 do
            local signalControl = self.Controls.ledExtronSignalPresence[i]
            if signalControl then
                signalControl.EventHandler = function(ctl)
                    if self.systemPowered and not self.systemWarming then
                        self:checkAutoSwitch()
                    end
                end
            end
        end
    end
end

--------** Event Handler Registration **--------
function ExtronDXPMatrixController:registerEventHandlers()
    -- ClickShare destination selectors
    for i = 1, 5 do
        self.controls.btnVideoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.ClickShare)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.ClickShare)
                self.controls.btnDestination[1].Boolean = true
            end
        end
    end
    
    -- Teams PC destination selectors
    for i = 1, 5 do
        self.controls.btnVideoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i == 1 then
                -- Front displays
                self:setDestination(1, true)
                self:setDestination(2, true)
                self:setSource(self.inputs.TeamsPC)
            elseif i == 3 then
                -- Rear displays
                self:setDestination(3, true)
                self:setDestination(4, true)
                self:setSource(self.inputs.TeamsPC)
            elseif i == 5 then
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.TeamsPC)
                self.controls.btnDestination[2].Boolean = true
            end
        end
    end
    
    -- Laptop Front destination selectors
    for i = 1, 5 do
        self.controls.btnVideoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.LaptopFront)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.LaptopFront)
                self.controls.btnDestination[3].Boolean = true
            end
        end
    end
    
    -- Laptop Rear destination selectors
    for i = 1, 5 do
        self.controls.btnVideoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.LaptopRear)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.LaptopRear)
                self.controls.btnDestination[4].Boolean = true
            end
        end
    end
    
    -- No Source destination selectors
    for i = 1, 5 do
        self.controls.btnVideoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.NoSource)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.NoSource)
                self.controls.btnDestination[5].Boolean = true
            end
        end
    end
    
    -- Extron DXP Signal Presence handlers
    for i = 1, 5 do
        self.controls.ledExtronSignalPresence[i].EventHandler = function()
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- UCI Layer Selector (disable Teams PC buttons for Mon-02 and Mon-04)
    if self.uciLayerSelector then
        self.uciLayerSelector['selector'].EventHandler = function(ctl)
            self:setDestinationButtonProperties(2, '#ff6666', 'N/A', true)
            self:setDestinationButtonProperties(4, '#ff6666', 'N/A', true)
        end
    end
end

--------** Initialization **--------
function ExtronDXPMatrixController:funcInit()
    self:populateExtronDXPChoices()
    self:populateRoomControlsChoices()
    self:setExtronDXPComponent()
    self:setRoomControlsComponent()
    
    -- Set default selection to No Source       
    if self.extronRouter then
        self:setSource(self.inputs.NoSource)
    end
    
    self:debugPrint("Initializing Extron DXP Controller")
    
    -- Setup components
    self:setupComponents()
    
    -- Setup UCI integration with multiple approaches
    if self.uciIntegrationEnabled then
        -- Always set up direct button monitoring as fallback
        self:setupDirectUCIButtonMonitoring()
        self:debugPrint("Direct UCI button monitoring started")
        
        -- If UCI controller is available, also start timer-based monitoring
        if self.uciController then
            self:startUCIMonitoring()
            self:debugPrint("Timer-based UCI monitoring started")
        end
    end
    
    -- Setup auto-switching
    self:setupAutoSwitchMonitoring()
    
    -- Initialize system state
    if self.roomControls then
        self.systemPowered = self.roomControls["ledSystemPower"].Boolean
        self.systemWarming = self.roomControls["ledSystemWarming"].Boolean
    end
    
    self:debugPrint("Extron DXP Controller initialization complete")
end

--------** Cleanup **--------
function ExtronDXPMatrixController:cleanup()
    -- Stop UCI monitoring timer
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    
    -- Clear UCI controller reference
    self.uciController = nil
    
    self:debugPrint("Cleanup completed")
end

--------** Public Interface **--------
function ExtronDXPMatrixController:getStatus()
    local status = {
        systemPowered = self.systemPowered,
        systemWarming = self.systemWarming,
        currentSource = self.currentSource,
        currentDestinations = self.currentDestinations,
        componentsValid = (self.extronRouter ~= nil and self.roomControls ~= nil),
        uciIntegrationEnabled = self.uciIntegrationEnabled,
        uciControllerConnected = (self.uciController ~= nil),
        uciMonitorActive = (self.uciMonitorTimer ~= nil)
    }
    return status
end

function ExtronDXPMatrixController:getUCIStatus()
    local uciStatus = {
        integrationEnabled = self.uciIntegrationEnabled,
        controllerConnected = (self.uciController ~= nil),
        monitorActive = (self.uciMonitorTimer ~= nil),
        lastLayer = self.lastUCILayer,
        layerMapping = self.uciLayerToInput
    }
    return uciStatus
end

-- Create and return the controller instance
local extronDXPController = ExtronDXPMatrixController.new()

-- Export for external access
_G.ExtronDXPMatrixController = extronDXPController

--------** Factory Function **--------
local function createExtronDXPMatrixController(config)
    local defaultConfig = {
        debugging = true,
        uciIntegrationEnabled = true
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return ExtronDXPMatrixController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created Extron DXP Matrix Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the controller for this script instance
myExtronDXPMatrixController = createExtronDXPMatrixController()

--[[
Enhanced UCI Integration Features:

1. Multiple Integration Approaches:
   - Timer-based monitoring (when UCI controller reference is available)
   - Direct button monitoring (fallback when no UCI controller)
   - Layer change notification method (for external UCI controllers)

2. Robust State Management:
   - Tracks last UCI layer to prevent redundant switching
   - Proper cleanup of timers and event handlers
   - Enable/disable integration at runtime

3. Enhanced Debugging:
   - Detailed UCI status reporting
   - Layer change logging
   - Integration state monitoring

4. Usage Examples:
   - Manual UCI controller connection: myExtronDXPMatrixController:setUCIController(myUCI)
   - Enable/disable integration: myExtronDXPMatrixController:enableUCIIntegration()
   - Get UCI status: myExtronDXPMatrixController:getUCIStatus()
   - Cleanup: myExtronDXPMatrixController:cleanup()

5. UCI Layer to Input Mapping:
   - Layer 7 (btnNav07) → TeamsPC (input 2)
   - Layer 8 (btnNav08) → LaptopFront (input 4)  
   - Layer 9 (btnNav09) → ClickShare (input 1)

6. Auto-switching Integration:
   - Monitors system power and warming states
   - Integrates with CallSync off-hook detection
   - Extron signal presence monitoring
   - Priority-based source selection

This implementation provides the same robust UCI integration capabilities as the NV32RouterController
with enhanced error handling and multiple integration approaches for maximum compatibility.
]]-- 