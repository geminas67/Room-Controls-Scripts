--[[
  Extron DXP Matrix Routing Controller - Simplified
  Author: Nikolas Smith, Q-SYS (Simplified)
  2025-01-27
  Firmware Req: 10.0.0
  Version: 2.1

  Simplified class-based implementation matching NV32RouterController pattern
  - Direct routing and state management
  - UCI integration for automatic input switching
  - Essential auto-switching functionality
  - Component discovery using Component.GetComponents()
]]--

-- Define control references
local controls = {
    txtDestination = Controls.txtDestination,
    btnVideoSource = Controls.btnVideoSource,
    btnDestination = Controls.btnDestination,
    ledSourceRouted = Controls.ledSourceRouted,
    ledExtronSignalPresence = Controls.ledExtronSignalPresence,
    btnAVMute = Controls.btnAVMute,
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
    
    -- UCI Layer to Input mapping (matching NV32RouterController pattern)
    self.uciLayerToInput = {
        [7] = self.inputs.TeamsPC,     -- btnNav07.Boolean = PC (TeamsPC)
        [8] = self.inputs.LaptopFront, -- btnNav08.Boolean = Laptop (LaptopFront)
        [9] = self.inputs.ClickShare,  -- btnNav09.Boolean = WPres (ClickShare)
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

    -- Component type definitions
    self.componentTypes = {
        extronRouter = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        callSync = "call_sync",
        ClickShare = "%PLUGIN%_bb4217ac-401f-4698-aad9-9e4b2496ff46_%FP%_e0a4597b59bdca3247ccb142ce451198",
        roomControls = "device_controller_script" 
    }
    -- Component storage
    self.extronRouter = nil
    self.roomControls = nil
    self.uciLayerSelector = nil
    self.callSync = nil
    self.ClickShare = nil
    -- Current state
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

-- Direct UCI button monitoring (matching NV32RouterController pattern)
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

--------** Component Management **--------
function ExtronDXPMatrixController:setComponent(ctrl, componentType)
    if not ctrl then
        self:debugPrint("Control for " .. componentType .. " is nil!")
        self:setComponentInvalid(componentType)
        return nil
    end
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

function ExtronDXPMatrixController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:checkStatus()
end

function ExtronDXPMatrixController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:checkStatus()
end

function ExtronDXPMatrixController:checkStatus()
    for i, v in pairs(self.invalidComponents) do
        if v == true then
            self.controls.txtDestination.String = "Invalid Components"
            self.controls.txtDestination.Value = 1
            return
        end
    end
    self.controls.txtDestination.String = "OK"
    self.controls.txtDestination.Value = 0
end

--------** Component Name Discovery **--------
function ExtronDXPMatrixController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        extronDXPNames = {},
        callSyncNames = {},
        clickShareNames = {},
        roomControlsNames = {}
    }
    
    for _, comp in pairs(components) do
        if comp.Type == self.componentTypes.extronRouter then
            table.insert(discovered.extronDXPNames, comp.Name)
        elseif comp.Type == self.componentTypes.callSync then
            table.insert(discovered.callSyncNames, comp.Name)
        elseif comp.Type == self.componentTypes.ClickShare then
            table.insert(discovered.clickShareNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(discovered.roomControlsNames, comp.Name)
        end
    end
    
    return discovered
end

--------** Component Setup **--------
function ExtronDXPMatrixController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Setup Extron DXP Router
    if #discovered.extronDXPNames > 0 then
        self.extronRouter = Component.New(discovered.extronDXPNames[1])
        self:debugPrint("Extron DXP Router set: " .. discovered.extronDXPNames[1])
    end
    
    -- Setup CallSync
    if #discovered.callSyncNames > 0 then
        self.callSync = Component.New(discovered.callSyncNames[1])
        self:debugPrint("CallSync set: " .. discovered.callSyncNames[1])
    end
    
    -- Setup ClickShare
    if #discovered.clickShareNames > 0 then
        self.ClickShare = Component.New(discovered.clickShareNames[1])
        self:debugPrint("ClickShare set: " .. discovered.clickShareNames[1])
    end
    
    -- Setup Room Controls
    if #discovered.roomControlsNames > 0 then
        self.roomControls = Component.New(discovered.roomControlsNames[1])
        self:debugPrint("Room Controls set: " .. discovered.roomControlsNames[1])
    end
    
    -- Setup UCI Layer Selector
    self.uciLayerSelector = Component.New('BDRM-UCI Layer Selector')
end

function ExtronDXPMatrixController:setExtronDXPComponent()
    self.extronRouter = self:setComponent(Controls.compExtronDXPMatrix, "Extron DXP Matrix")
end

function ExtronDXPMatrixController:setCallSyncComponent()
    self.callSync = self:setComponent(Controls.compCallSync, "CallSync")
end

function ExtronDXPMatrixController:setClickShareComponent()
    self.ClickShare = self:setComponent(Controls.compClickShare, "ClickShare")
end

function ExtronDXPMatrixController:setRoomControlsComponent()
    self.roomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.roomControls ~= nil then
        -- Add event handlers for system power and warming
        local this = self  -- Capture self for use in handlers

        self.roomControls["ledSystemPower"].EventHandler = function(ctl)
            this.systemPowered = ctl.Boolean
            this:debugPrint("System power state: " .. tostring(this.systemPowered))
            if this.systemPowered then
                this:checkAutoSwitch()
            end
        end
        
        self.roomControls["ledSystemWarming"].EventHandler = function(ctl)
            this.systemWarming = ctl.Boolean
            this:debugPrint("System warming state: " .. tostring(this.systemWarming))
            if not this.systemWarming and this.systemPowered then
                this:checkAutoSwitch()
            end
        end
    end
end

--------** Routing Methods **--------
function ExtronDXPMatrixController:setRoute(input, output)
    if not self.extronRouter then return end
    
    self.extronRouter['output_' .. output].String = tostring(input)
    self:debugPrint("Set Output " .. output .. " to Input " .. input)
    
    -- Update destination feedback
    if self.controls.ledSourceRouted and self.controls.ledSourceRouted[output] then
        self.controls.ledSourceRouted[output].Boolean = true
    end

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearRoute(output)
    if not self.extronRouter then return end
    
    self.extronRouter['output_' .. output].String = '0'
    self:debugPrint("Cleared Output " .. output)
    
    -- Update destination feedback
    if self.controls.ledSourceRouted and self.controls.ledSourceRouted[output] then
        self.controls.ledSourceRouted[output].Boolean = false
    end

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearAllRoutes()
    for output = 1, 4 do
        self:clearRoute(output)
    end
end

function ExtronDXPMatrixController:updateDestinationFeedback()
    -- Update destination feedback based on current router state
    for i = 1, 4 do
        local currentInput = tonumber(self.extronRouter['output_' .. i].String) or 0
        local isActive = currentInput > 0
        -- Remove toggle feedback for btnDestination
        if self.controls.ledSourceRouted and self.controls.ledSourceRouted[i] then
            self.controls.ledSourceRouted[i].Boolean = isActive
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
    
    local sourceNames = {
        [1] = "ClickShare",
        [2] = "TeamsPC",
        [4] = "LaptopFront",
        [5] = "LaptopRear",
        [0] = "NoSource"
    }
    
    local activeRoutes = {}
    local activeCount = 0
    
    for output = 1, 4 do
        local currentInput = tonumber(self.extronRouter['output_' .. output].String) or 0
        if currentInput > 0 then
            activeCount = activeCount + 1
            local sourceName = sourceNames[currentInput] or "Unknown"
            table.insert(activeRoutes, sourceName .. " → " .. destinationNames[output])
        end
    end
    
    if activeCount == 0 then
        self.controls.txtDestination.String = ""
    elseif activeCount == 4 then
        self.controls.txtDestination.String = "All Displays Active"
        -- Clear text after 3 seconds
        Timer.CallAfter(function()
            self.controls.txtDestination.String = ""
        end, 3)
    else
        self.controls.txtDestination.String = table.concat(activeRoutes, ", ")
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
            -- Check if any outputs are currently active
            local hasActiveOutputs = false
            for output = 1, 4 do
                local currentInput = tonumber(self.extronRouter['output_' .. output].String) or 0
                if currentInput > 0 then
                    hasActiveOutputs = true
                    break
                end
            end
            
            -- If no outputs are active, activate the first one
            if not hasActiveOutputs then
                self:setRoute(source.input, 1)
            else
                -- Update all active outputs to the new source
                for output = 1, 4 do
                    local currentInput = tonumber(self.extronRouter['output_' .. output].String) or 0
                    if currentInput > 0 then
                        self:setRoute(source.input, output)
                    end
                end
            end
            return
        end
    end
end

function ExtronDXPMatrixController:setupAutoSwitchMonitoring()
    -- Monitor CallSync off-hook state
    if self.callSync then
        self.callSync["off.hook"].EventHandler = function(ctl)
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor Extron signal presence
    if self.controls.ledExtronSignalPresence then
        for i = 1, 5 do
            local signalControl = self.controls.ledExtronSignalPresence[i]
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
    -- Safety check: ensure controls exist before setting up event handlers
    if not self.controls or not self.controls.btnVideoSource then
        self:debugPrint("Warning: Video source controls not found - skipping event handler setup")
        return
    end
    
    -- Source selection buttons (interlocking)
    for i = 1, 5 do
        if self.controls.btnVideoSource[i] then
            self.controls.btnVideoSource[i].EventHandler = function(ctl)
                if ctl.Boolean then
                    -- Deselect all other sources
                    for j = 1, 5 do
                        if j ~= i and self.controls.btnVideoSource[j] then
                            self.controls.btnVideoSource[j].Boolean = false
                        end
                    end
                    -- Get the input for this source
                    local sourceInput = nil
                    if i == 1 then
                        sourceInput = self.inputs.ClickShare
                    elseif i == 2 then
                        sourceInput = self.inputs.TeamsPC
                    elseif i == 3 then
                        sourceInput = self.inputs.LaptopFront
                    elseif i == 4 then
                        sourceInput = self.inputs.LaptopRear
                    elseif i == 5 then
                        sourceInput = self.inputs.NoSource
                    end
                    if sourceInput then
                        -- Route the source to all destinations that are currently routed (feedback only)
                        for dest = 1, 4 do
                            local isActive = false
                            if self.controls.ledSourceRouted and self.controls.ledSourceRouted[dest] then
                                isActive = self.controls.ledSourceRouted[dest].Boolean
                            end
                            if isActive then
                                self:setRoute(sourceInput, dest)
                            end
                        end
                        -- Handle Teams PC button properties based on source
                        if i == 2 then
                            self:setDestinationButtonProperties(2, '#ff6666', 'N/A', true)
                            self:setDestinationButtonProperties(4, '#ff6666', 'N/A', true)
                        else
                            self:setDestinationButtonProperties(2, 'white', '', false)
                            self:setDestinationButtonProperties(4, 'white', '', false)
                        end
                    end
                end
            end
        end
    end
    -- Destination selection buttons (Trigger logic)
    for i = 1, 4 do
        if self.controls.btnDestination[i] then
            self.controls.btnDestination[i].EventHandler = function(ctl)
                -- Get the currently selected source
                local selectedSource = nil
                for src = 1, 5 do
                    if self.controls.btnVideoSource[src] and self.controls.btnVideoSource[src].Boolean then
                        if src == 1 then
                            selectedSource = self.inputs.ClickShare
                        elseif src == 2 then
                            selectedSource = self.inputs.TeamsPC
                        elseif src == 3 then
                            selectedSource = self.inputs.LaptopFront
                        elseif src == 4 then
                            selectedSource = self.inputs.LaptopRear
                        elseif src == 5 then
                            selectedSource = self.inputs.NoSource
                        end
                        break
                    end
                end
                -- On trigger, always route selected source to this destination
                if selectedSource then
                    self:setRoute(selectedSource, i)
                end
            end
        end
    end
    -- Remove "All Displays" toggle logic for btnDestination[5]
    
    -- Extron DXP Signal Presence handlers
    if self.controls.ledExtronSignalPresence then
        for i = 1, 5 do
            if self.controls.ledExtronSignalPresence[i] then
                self.controls.ledExtronSignalPresence[i].EventHandler = function()
                    if self.systemPowered and not self.systemWarming then
                        self:checkAutoSwitch()
                    end
                end
            end
        end
    end
    
    -- Re-enable Teams PC buttons when other sources are selected (not TeamsPC)
    -- This is handled in the main source selection logic above
    
    -- Set up direct UCI button monitoring (matching NV32RouterController pattern)
    self:setupDirectUCIButtonMonitoring()
    
    self:debugPrint("Event handlers registered successfully")
end

-- Helper method for setting destination button properties
function ExtronDXPMatrixController:setDestinationButtonProperties(output, color, text, disabled)
    if self.controls.btnDestination[output] then
        -- Set button color
        self.controls.btnDestination[output].Color = color
        
        -- Set button text if provided
        if text and text ~= "" then
            self.controls.btnDestination[output].String = text
        end
        
        -- Set button disabled state
        self.controls.btnDestination[output].Disabled = disabled
        
        self:debugPrint("Set destination button " .. output .. " properties: color=" .. color .. ", text=" .. text .. ", disabled=" .. tostring(disabled))
    end
end

--------** Initialization **--------
function ExtronDXPMatrixController:funcInit()
    self:setupComponents()
    self:setExtronDXPComponent()
    self:setCallSyncComponent()
    self:setClickShareComponent()
    self:setRoomControlsComponent()
    
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
UCI Integration (Matching NV32RouterController Pattern):

The controller automatically monitors UCI navigation buttons (btnNav07, btnNav08, btnNav09)
When these buttons are active, it automatically switches the Extron DXP input accordingly:
  * btnNav07.Boolean = true → switches to TeamsPC (input 2)
  * btnNav08.Boolean = true → switches to LaptopFront (input 4)  
  * btnNav09.Boolean = true → switches to ClickShare (input 1)

UCI Layer to Input Mapping:
  - Layer 7 (btnNav07) → TeamsPC (input 2)
  - Layer 8 (btnNav08) → LaptopFront (input 4)  
  - Layer 9 (btnNav09) → ClickShare (input 1)

Auto-switching Integration:
  - Monitors system power and warming states
  - Integrates with CallSync off-hook detection
  - Extron signal presence monitoring
  - Priority-based source selection

This simplified implementation matches the NV32RouterController pattern
while maintaining essential auto-switching functionality.
]]-- 