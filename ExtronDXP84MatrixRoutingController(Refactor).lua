--[[
  Extron DXP Matrix Routing Controller (Refactored)
  Author: Nikolas Smith, Q-SYS
  Date: 2025-01-27
  Version: 3.0
  Firmware Req: 10.0.0

  Refactored to Lua Refactoring Prompt specifications:
  - Comprehensive control validation with descriptive error messages
  - Control array normalization for consistent data structures
  - Essential utility functions (isArr, setProp, bind, bindArray, forEach)
  - Batch event registration using handler maps
  - Optimized property access with cached references
  - Factory function with enhanced error handling
  - Direct routing and state management
  - UCI integration for automatic input switching
  - Component discovery using Component.GetComponents()
]]--

-------------------[ Utility Functions ]-------------------
-- Define utilities before any code that uses them

local function isArr(val)
    return type(val) == "table" and #val > 0
end

local function setProp(ctrl, prop, val)
    if not ctrl or not prop then return false end
    if ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    ctrl.EventHandler = handler
    return true
end

local function bindArray(ctrlArray, handlerFunc)
    if not isArr(ctrlArray) then return 0 end
    local boundCount = 0
    for i, ctrl in ipairs(ctrlArray) do
        if ctrl and bind(ctrl, function() handlerFunc(i, ctrl) end) then
            boundCount = boundCount + 1
        end
    end
    return boundCount
end

local function forEach(tbl, func)
    if not tbl or not func then return end
    for i, v in ipairs(tbl) do
        if v then func(i, v) end
    end
end

-------------------[ Control References ]-------------------
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
    compExtronDXPMatrix = Controls.compExtronDXPMatrix,
    compCallSync = Controls.compCallSync,
    compClickShare = Controls.compClickShare,
    compRoomControls = Controls.compRoomControls,
}

-------------------[ ExtronDXPMatrixController Class ]-------------------
ExtronDXPMatrixController = {}
ExtronDXPMatrixController.__index = ExtronDXPMatrixController

--------** Control Validation **--------
function ExtronDXPMatrixController.validateControls()
    local requiredControls = {
        "txtDestination"
    }
    
    local missing = {}
    for _, ctrlName in ipairs(requiredControls) do
        if not controls[ctrlName] then
            table.insert(missing, ctrlName)
        end
    end
    
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    
    return true
end

--------** Control Array Normalization **--------
function ExtronDXPMatrixController.normalizeControlArrays()
    local normalized = {}
    
    -- Normalize button arrays
    normalized.btnVideoSource = {}
    normalized.btnDestination = {}
    normalized.ledSourceRouted = {}
    normalized.ledExtronSignalPresence = {}
    normalized.uciButtons = {}
    
    -- Build video source buttons (1-5)
    if controls.btnVideoSource then
        for i = 1, 5 do
            normalized.btnVideoSource[i] = controls.btnVideoSource[i]
        end
    end
    
    -- Build destination buttons (1-4)
    if controls.btnDestination then
        for i = 1, 4 do
            normalized.btnDestination[i] = controls.btnDestination[i]
        end
    end
    
    -- Build source routed LEDs (1-4)
    if controls.ledSourceRouted then
        for i = 1, 4 do
            normalized.ledSourceRouted[i] = controls.ledSourceRouted[i]
        end
    end
    
    -- Build signal presence LEDs (1-5)
    if controls.ledExtronSignalPresence then
        for i = 1, 5 do
            normalized.ledExtronSignalPresence[i] = controls.ledExtronSignalPresence[i]
        end
    end
    
    -- Build UCI button references
    normalized.uciButtons = {
        [7] = controls.btnNav07,
        [8] = controls.btnNav08,
        [9] = controls.btnNav09
    }
    
    return normalized
end

--------** Class Constructor **--------
function ExtronDXPMatrixController.new()
    -- Validate controls before creating instance
    if not ExtronDXPMatrixController.validateControls() then
        return nil
    end
    
    local self = setmetatable({}, ExtronDXPMatrixController)
    
    -- Configuration
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
        MON01 = 1,
        MON02 = 2,
        MON03 = 3,
        MON04 = 4
    }
    
    -- UCI Layer to Input mapping (for automatic switching)
    self.uciLayerToInput = {
        [7] = self.inputs.TeamsPC,     -- btnNav07 → PC (TeamsPC)
        [8] = self.inputs.LaptopFront, -- btnNav08 → Laptop (LaptopFront)
        [9] = self.inputs.ClickShare,  -- btnNav09 → WPres (ClickShare)
    }
    
    -- Source priority mapping (for auto-switching)
    self.sourcePriority = {
        {name = "TeamsPC", input = self.inputs.TeamsPC, checkFunc = function() 
            return self.callSync and self.callSync["off.hook"].Boolean or 
                   self.normalizedControls.ledExtronSignalPresence[3].Boolean 
        end},
        {name = "LaptopFront", input = self.inputs.LaptopFront, checkFunc = function() 
            return self.normalizedControls.ledExtronSignalPresence[4].Boolean 
        end},
        {name = "LaptopRear", input = self.inputs.LaptopRear, checkFunc = function() 
            return self.normalizedControls.ledExtronSignalPresence[5].Boolean 
        end},
        {name = "ClickShare", input = self.inputs.ClickShare, checkFunc = function() 
            return self.normalizedControls.ledExtronSignalPresence[1].Boolean 
        end},
        {name = "TeamsPC2", input = self.inputs.TeamsPC, checkFunc = function() 
            return self.normalizedControls.ledExtronSignalPresence[2].Boolean 
        end}
    }
    
    -- Control references
    self.controls = controls
    self.normalizedControls = ExtronDXPMatrixController.normalizeControlArrays()
    
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
    
    -- System state
    self.systemPowered = false
    self.systemWarming = true
    
    -- Initialize
    self:funcInit()
    self:registerEventHandlers()
    
    return self
end

--------** Debug Helper **--------
function ExtronDXPMatrixController:debugPrint(str)
    if self.debugging then
        print("[Extron DXP] " .. str)
    end
end

--------** UCI Integration Methods **--------
function ExtronDXPMatrixController:setUCIController(uciController)
    if not uciController then return end
    
    self.uciController = uciController
    self:debugPrint("UCI Controller reference set")
    
    if self.uciIntegrationEnabled then
        self:startUCIMonitoring()
    end
end

function ExtronDXPMatrixController:startUCIMonitoring()
    if not self.uciController then
        self:debugPrint("No UCI Controller available for monitoring")
        return
    end
    
    self.uciMonitorTimer = Timer.New()
    self.uciMonitorTimer.EventHandler = function()
        self:checkUCILayerChange()
        self.uciMonitorTimer:Start(0.1)
    end
    self.uciMonitorTimer:Start(0.1)
    
    self:debugPrint("UCI layer monitoring started")
end

function ExtronDXPMatrixController:checkUCILayerChange()
    if not self.uciController or not self.uciIntegrationEnabled then
        return
    end
    
    local currentLayer = self.uciController.varActiveLayer
    
    if self.lastUCILayer ~= currentLayer then
        self:debugPrint("UCI Layer changed from " .. tostring(self.lastUCILayer) .. 
                       " to " .. tostring(currentLayer))
        self.lastUCILayer = currentLayer
        
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

function ExtronDXPMatrixController:onUCILayerChange(layerChangeInfo)
    if not self.uciIntegrationEnabled then return end
    
    self:debugPrint("UCI Layer changed from " .. tostring(layerChangeInfo.previousLayer) .. 
                   " to " .. tostring(layerChangeInfo.currentLayer) .. 
                   " (" .. layerChangeInfo.layerName .. ")")
    
    if self.uciLayerToInput[layerChangeInfo.currentLayer] then
        local targetInput = self.uciLayerToInput[layerChangeInfo.currentLayer]
        self:debugPrint("UCI Layer " .. layerChangeInfo.currentLayer .. 
                       " triggers input switch to " .. targetInput)
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
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    if componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        setProp(ctrl, "String", "")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    if #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        self:setComponentInvalid(componentType)
        return nil
    end
    
    self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
    setProp(ctrl, "Color", "white")
    self:setComponentValid(componentType)
    return Component.New(componentName)
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
            setProp(self.controls.txtDestination, "String", "Invalid Components")
            setProp(self.controls.txtDestination, "Value", 1)
            return
        end
    end
    setProp(self.controls.txtDestination, "String", "OK")
    setProp(self.controls.txtDestination, "Value", 0)
end

--------** Component Discovery **--------
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
        elseif comp.Type == self.componentTypes.roomControls and 
               string.match(comp.Name, "^compRoomControls") then
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
    
    -- Setup UCI Layer Selector (if exists)
    local success, uciSelector = pcall(function() 
        return Component.New('BDRM-UCI Layer Selector') 
    end)
    if success and uciSelector then
        self.uciLayerSelector = uciSelector
        self:debugPrint("UCI Layer Selector set")
    end
end

function ExtronDXPMatrixController:setExtronDXPComponent()
    self.extronRouter = self:setComponent(self.controls.compExtronDXPMatrix, "Extron DXP Matrix")
end

function ExtronDXPMatrixController:setCallSyncComponent()
    self.callSync = self:setComponent(self.controls.compCallSync, "CallSync")
end

function ExtronDXPMatrixController:setClickShareComponent()
    self.ClickShare = self:setComponent(self.controls.compClickShare, "ClickShare")
end

function ExtronDXPMatrixController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    
    if not self.roomControls then return end
    
    -- Setup system power monitoring
    if self.roomControls["ledSystemPower"] then
        bind(self.roomControls["ledSystemPower"], function(ctl)
            self.systemPowered = ctl.Boolean
            self:debugPrint("System power state: " .. tostring(self.systemPowered))
            if self.systemPowered then
                self:checkAutoSwitch()
            end
        end)
    end
    
    -- Setup system warming monitoring
    if self.roomControls["ledSystemWarming"] then
        bind(self.roomControls["ledSystemWarming"], function(ctl)
            self.systemWarming = ctl.Boolean
            self:debugPrint("System warming state: " .. tostring(self.systemWarming))
            if not self.systemWarming and self.systemPowered then
                self:checkAutoSwitch()
            end
        end)
    end
end

--------** Routing Methods **--------
function ExtronDXPMatrixController:setRoute(input, output)
    if not self.extronRouter then return end
    
    self.extronRouter['output_' .. output].String = tostring(input)
    self:debugPrint("Set Output " .. output .. " to Input " .. input)
    
    -- Update destination feedback
    if self.normalizedControls.ledSourceRouted[output] then
        setProp(self.normalizedControls.ledSourceRouted[output], "Boolean", true)
    end

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearRoute(output)
    if not self.extronRouter then return end
    
    self.extronRouter['output_' .. output].String = '0'
    self:debugPrint("Cleared Output " .. output)
    
    -- Update destination feedback
    if self.normalizedControls.ledSourceRouted[output] then
        setProp(self.normalizedControls.ledSourceRouted[output], "Boolean", false)
    end

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearAllRoutes()
    for output = 1, 4 do
        self:clearRoute(output)
    end
end

function ExtronDXPMatrixController:setSource(input)
    -- Route to all active destinations
    for dest = 1, 4 do
        local isActive = self.normalizedControls.ledSourceRouted[dest] and 
                        self.normalizedControls.ledSourceRouted[dest].Boolean
        if isActive then
            self:setRoute(input, dest)
        end
    end
end

function ExtronDXPMatrixController:updateDestinationFeedback()
    if not self.extronRouter then return end
    
    for i = 1, 4 do
        local currentInput = tonumber(self.extronRouter['output_' .. i].String) or 0
        local isActive = currentInput > 0
        if self.normalizedControls.ledSourceRouted[i] then
            setProp(self.normalizedControls.ledSourceRouted[i], "Boolean", isActive)
        end
    end
end

function ExtronDXPMatrixController:updateDestinationText()
    if not self.extronRouter then return end
    
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
        setProp(self.controls.txtDestination, "String", "")
    elseif activeCount == 4 then
        setProp(self.controls.txtDestination, "String", "All Displays Active")
        Timer.CallAfter(function()
            setProp(self.controls.txtDestination, "String", "")
        end, 3)
    else
        setProp(self.controls.txtDestination, "String", table.concat(activeRoutes, ", "))
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
    if self.callSync and self.callSync["off.hook"] then
        bind(self.callSync["off.hook"], function(ctl)
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end)
    end
    
    -- Monitor Extron signal presence
    forEach(self.normalizedControls.ledExtronSignalPresence, function(i, ctrl)
        bind(ctrl, function(ctl)
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end)
    end)
end

--------** Helper Methods **--------
function ExtronDXPMatrixController:setDestinationButtonProperties(output, color, text, disabled)
    local btn = self.normalizedControls.btnDestination[output]
    if not btn then return end
    
    setProp(btn, "Color", color)
    if text and text ~= "" then
        setProp(btn, "String", text)
    end
    setProp(btn, "Disabled", disabled)
    
    self:debugPrint("Set destination button " .. output .. " properties: color=" .. 
                   color .. ", disabled=" .. tostring(disabled))
end

function ExtronDXPMatrixController:getSelectedSource()
    for src = 1, 5 do
        local btn = self.normalizedControls.btnVideoSource[src]
        if btn and btn.Boolean then
            if src == 1 then return self.inputs.ClickShare
            elseif src == 2 then return self.inputs.TeamsPC
            elseif src == 3 then return self.inputs.LaptopFront
            elseif src == 4 then return self.inputs.LaptopRear
            elseif src == 5 then return self.inputs.NoSource
            end
        end
    end
    return nil
end

--------** Event Handler Registration **--------
function ExtronDXPMatrixController:registerEventHandlers()
    -- Source selection buttons (interlocking)
    local sourceHandlers = {}
    for i = 1, 5 do
        local btn = self.normalizedControls.btnVideoSource[i]
        if btn then
            sourceHandlers[btn] = function(ctl)
                if not ctl.Boolean then return end
                
                -- Deselect all other sources (interlocking)
                for j = 1, 5 do
                    if j ~= i then
                        local otherBtn = self.normalizedControls.btnVideoSource[j]
                        if otherBtn then setProp(otherBtn, "Boolean", false) end
                    end
                end
                
                -- Get the input for this source
                local sourceInput = nil
                if i == 1 then sourceInput = self.inputs.ClickShare
                elseif i == 2 then sourceInput = self.inputs.TeamsPC
                elseif i == 3 then sourceInput = self.inputs.LaptopFront
                elseif i == 4 then sourceInput = self.inputs.LaptopRear
                elseif i == 5 then sourceInput = self.inputs.NoSource
                end
                
                if not sourceInput then return end
                
                -- Route source to all active destinations
                for dest = 1, 4 do
                    local isActive = self.normalizedControls.ledSourceRouted[dest] and 
                                   self.normalizedControls.ledSourceRouted[dest].Boolean
                    if isActive then
                        self:setRoute(sourceInput, dest)
                    end
                end
                
                -- Handle Teams PC button properties
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
    
    -- Destination selection buttons
    local destinationHandlers = {}
    for i = 1, 4 do
        local btn = self.normalizedControls.btnDestination[i]
        if btn then
            destinationHandlers[btn] = function(ctl)
                local selectedSource = self:getSelectedSource()
                if selectedSource then
                    self:setRoute(selectedSource, i)
                end
            end
        end
    end
    
    -- UCI button handlers (direct monitoring)
    local uciHandlers = {}
    for layer, btn in pairs(self.normalizedControls.uciButtons) do
        if btn then
            uciHandlers[btn] = function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    local targetInput = self.uciLayerToInput[layer]
                    self:debugPrint("UCI Button " .. layer .. " pressed, switching to input " .. targetInput)
                    self:setSource(targetInput)
                end
            end
        end
    end
    
    -- Batch register all handlers
    for ctrl, handler in pairs(sourceHandlers) do
        bind(ctrl, handler)
    end
    for ctrl, handler in pairs(destinationHandlers) do
        bind(ctrl, handler)
    end
    for ctrl, handler in pairs(uciHandlers) do
        bind(ctrl, handler)
    end
    
    self:debugPrint("Event handlers registered successfully")
end

--------** Initialization **--------
function ExtronDXPMatrixController:funcInit()
    self:setupComponents()
    self:setExtronDXPComponent()
    self:setCallSyncComponent()
    self:setClickShareComponent()
    self:setRoomControlsComponent()
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
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    
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
        return ExtronDXPMatrixController.new()
    end)
    
    if success and controller then
        print("✓ Successfully created Extron DXP Matrix Controller")
        return controller
    else
        print("✗ Failed to create Extron DXP Matrix Controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
myExtronDXPMatrixController = createExtronDXPMatrixController()

--[[
UCI Integration:

The controller automatically monitors UCI navigation buttons (btnNav07, btnNav08, btnNav09)
When these buttons are active, it automatically switches the Extron DXP input accordingly:
  • btnNav07.Boolean = true → switches to TeamsPC (input 2)
  • btnNav08.Boolean = true → switches to LaptopFront (input 4)  
  • btnNav09.Boolean = true → switches to ClickShare (input 1)

UCI Layer to Input Mapping:
  - Layer 7 (btnNav07) → TeamsPC (input 2)
  - Layer 8 (btnNav08) → LaptopFront (input 4)  
  - Layer 9 (btnNav09) → ClickShare (input 1)

Auto-switching Integration:
  - Monitors system power and warming states
  - Integrates with CallSync off-hook detection
  - Extron signal presence monitoring
  - Priority-based source selection

REFACTORING SUMMARY:
✓ Comprehensive control validation with descriptive error messages
✓ Control array normalization for consistent data structures
✓ Essential utility functions (isArr, setProp, bind, bindArray, forEach)
✓ Batch event registration using handler maps
✓ Optimized property access with cached references
✓ Factory function with enhanced error handling
✓ Direct routing and state management
✓ Flattened control flow with early returns
✓ Component discovery using Component.GetComponents()
✓ Follows Lua Refactoring Prompt specifications v3.0
]]--
