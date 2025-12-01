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
  - cleanupComponentHandlers() utility (Pattern #25/#33) for divisible space support
  - Generic component setup method (Pattern #21) eliminating code duplication
  - Centralized source input mapping logic (DRY principle)
  - Batch event registration using handler maps
  - Optimized property access with cached references
  - Factory function with enhanced error handling
  - Direct routing and state management
  - UCI integration for automatic input switching
  - Component discovery using Component.GetComponents()
  - Full compliance with Lua Refactoring Prompt v3.0 and DRY principles
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

-- CRITICAL: Clean up old event handlers before reassigning components (Pattern #25/#33)
-- Prevents handler accumulation in divisible space scenarios
local function cleanupComponentHandlers(oldComponent, controlNames, debugCallback)
    if not oldComponent or not controlNames then return 0 end
    
    local cleaned = 0
    for _, controlName in ipairs(controlNames) do
        if oldComponent[controlName] and oldComponent[controlName].EventHandler then
            setProp(oldComponent[controlName], "EventHandler", nil)
            cleaned = cleaned + 1
        end
    end
    
    if debugCallback and cleaned > 0 then
        debugCallback(string.format("Cleaned up %d event handler(s) from old component", cleaned))
    end
    
    return cleaned
end

-------------------[ Control References ]-------------------
local controls = {
    txtSource = Controls.txtSource,
    btnVideoSource = Controls.btnVideoSource,
    btnDestination = Controls.btnDestination,
    ledSourceRouted = Controls.ledSourceRouted,
    ledExtronSignalPresence = Controls.ledExtronSignalPresence,
    btnAVMute = Controls.btnAVMute,
    btnNav07 = Controls['btnNav07'],
    btnNav08 = Controls['btnNav08'],
    btnNav09 = Controls['btnNav09'],
    txtStatus = Controls.txtStatus,
    compExtronDXPMatrix = Controls.compExtronDXPMatrix,
    compCallSync = Controls.compCallSync,
    compClickShare = Controls.compClickShare,
    compRoomControls = Controls.compRoomControls,
}

-------------------[ ExtronDXPMatrixController Class ]-------------------
ExtronDXPMatrixController = {}
ExtronDXPMatrixController.__index = ExtronDXPMatrixController

--------------------------------[ Control Validation ]--------------------------------
function ExtronDXPMatrixController.validateControls()
    local requiredControls = {
        "txtSource",
    }
    
    local missing = {}
    for _, ctrlName in ipairs(requiredControls) do
        if not controls[ctrlName] then
            table.insert(missing, ctrlName)
        end
    end
    
    if #missing > 0 then
        -- Use consistent error format (will be replaced by debugPrint in instance context)
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    
    return true
end

--------------------------------[ Control Array Normalization ]--------------------------------
function ExtronDXPMatrixController.normalizeControlArrays()
    local normalized = {}
    
    -- Normalize button arrays
    normalized.btnVideoSource = {}
    normalized.btnDestination = {}
    normalized.ledSourceRouted = {}
    normalized.ledExtronSignalPresence = {}
    normalized.uciButtons = {}
    
    -- Build video source buttons (1-6)
    if controls.btnVideoSource then
        for i = 1, 6 do
            normalized.btnVideoSource[i] = controls.btnVideoSource[i]
        end
    end
    
    -- Build destination buttons (1-5)
    if controls.btnDestination then
        for i = 1, 5 do
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

--------------------------------[ Class Constructor ]--------------------------------
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
        ClickShare       = 1,
        TeamsPC          = 2,
        TeamsPCSecondary = 3,  -- TeamsPC secondary output (auto-routed to even outputs)
        LaptopFront      = 4,
        LaptopRear       = 5,
        NoSource         = 0
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
    
    -- Source button index to input mapping (aligned with Extron input numbers)
    self.sourceButtonToInput = {
        [1] = self.inputs.ClickShare,       -- input 1
        [2] = self.inputs.TeamsPC,          -- input 2
        [3] = self.inputs.TeamsPCSecondary, -- input 3 (disabled, not independently routable)
        [4] = self.inputs.LaptopFront,      -- input 4
        [5] = self.inputs.LaptopRear,       -- input 5
        [6] = self.inputs.NoSource          -- input 0
    }
    
    -- Source priority mapping (for auto-switching)
    -- NOTE: checkFunc must handle nil safely and return explicit boolean
    self.sourcePriority = {
        {name = "Teams PC", input = self.inputs.TeamsPC, checkFunc = function() 
            -- Check CallSync off-hook OR signal presence on input 3
            local offHook = self.callSync and self.callSync["off.hook"] and self.callSync["off.hook"].Boolean
            local signalPresent = self.normalizedControls.ledExtronSignalPresence[3] and 
                                  self.normalizedControls.ledExtronSignalPresence[3].Boolean
            return offHook or signalPresent
        end},
        {name = "Front Laptop", input = self.inputs.LaptopFront, checkFunc = function() 
            local led = self.normalizedControls.ledExtronSignalPresence[4]
            return led and led.Boolean
        end},
        {name = "Rear Laptop", input = self.inputs.LaptopRear, checkFunc = function() 
            local led = self.normalizedControls.ledExtronSignalPresence[5]
            return led and led.Boolean
        end},
        {name = "ClickShare", input = self.inputs.ClickShare, checkFunc = function() 
            local led = self.normalizedControls.ledExtronSignalPresence[1]
            return led and led.Boolean
        end},
        {name = "Teams PC2", input = self.inputs.TeamsPC, checkFunc = function() 
            local led = self.normalizedControls.ledExtronSignalPresence[2]
            return led and led.Boolean
        end}
    }
    
    -- Source names mapping (DRY: centralized for reuse)
    self.sourceNames = {
        [1] = "ClickShare",
        [2] = "Teams PC",
        [3] = "Teams PC2",
        [4] = "Front Laptop",
        [5] = "Rear Laptop",
        [0] = "No Source"
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

--------------------------------[ Debug Helper ]--------------------------------
function ExtronDXPMatrixController:debugPrint(str)
    if self.debugging then
        print("[Extron DXP] " .. str)
    end
end

--------------------------------[ UCI Integration Methods ]--------------------------------
function ExtronDXPMatrixController:setUCIController(uciController)
    if not uciController then return end
    
    self.uciController = uciController
    self:debugPrint("UCI Controller reference set")
    
    if self.uciIntegrationEnabled then
        self:startUCIMonitoring()
    end
end

--[[
  CRITICAL: Never call layer navigation directly on the UCI.
  Always use triggerUCILayer() which calls btnNav[i]:Trigger() to ensure
  signals propagate correctly through the UCI script's event handlers.
]]--
function ExtronDXPMatrixController:triggerUCILayer(layer)
    -- Map layer number to btnNav button and trigger it
    -- This ensures the signal propagates through UCI script event handlers
    local btnNav = self.normalizedControls.uciButtons[layer]
    if not btnNav then
        self:debugPrint("Warning: btnNav button for layer " .. layer .. " not found")
        return false
    end
    
    -- Use pcall to safely trigger the button
    local success, err = pcall(function()
        btnNav:Trigger()
    end)
    
    if success then
        self:debugPrint("Triggered UCI layer " .. layer .. " via btnNav" .. layer)
        return true
    else
        self:debugPrint("Error triggering btnNav" .. layer .. ": " .. tostring(err))
        return false
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

--------------------------------[ Component Management ]--------------------------------
function ExtronDXPMatrixController:setComponent(ctrl, componentType, expectedComponentType)
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
    
    -- Validate component exists and has controls
    local newComponent = Component.New(componentName)
    if #Component.GetControls(newComponent) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        self:setComponentInvalid(componentType)
        return nil
    end
    
    -- Validate component type if expected type is provided
    if expectedComponentType then
        local actualType = newComponent.Type
        if actualType ~= expectedComponentType then
            self:debugPrint(componentType .. " Component " .. componentName .. " has wrong type. Expected: " .. 
                           tostring(expectedComponentType) .. ", Got: " .. tostring(actualType))
            setProp(ctrl, "String", "[Wrong Component Type]")
            setProp(ctrl, "Color", "pink")
            self:setComponentInvalid(componentType)
            return nil
        end
    end
    
    self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
    setProp(ctrl, "Color", "white")
    self:setComponentValid(componentType)
    return newComponent
end

function ExtronDXPMatrixController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:checkStatus()
end

function ExtronDXPMatrixController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:checkStatus()
end

--------------------------------[ Status Check ]--------------------------------
function ExtronDXPMatrixController:checkStatus()
    for i, v in pairs(self.invalidComponents) do
        if v == true then
            setProp(self.controls.txtStatus, "String", "Invalid Components")
            setProp(self.controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(self.controls.txtStatus, "String", "OK")
    setProp(self.controls.txtStatus, "Value", 0)
end

--------------------------------[ Component Discovery ]--------------------------------
function ExtronDXPMatrixController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        extronDXPNames = {},
        callSyncNames = {},
        clickShareNames = {},
        roomControlsNames = {}
    }
    
    self:debugPrint("Starting component discovery...")
    self:debugPrint("Looking for callSync type: '" .. tostring(self.componentTypes.callSync) .. "'")
    self:debugPrint("Looking for roomControls type: '" .. tostring(self.componentTypes.roomControls) .. "'")
    
    for _, comp in pairs(components) do
        if comp.Type == self.componentTypes.extronRouter then
            table.insert(discovered.extronDXPNames, comp.Name)
            self:debugPrint("Found Extron DXP: " .. comp.Name)
        elseif comp.Type == self.componentTypes.callSync then
            table.insert(discovered.callSyncNames, comp.Name)
            self:debugPrint("Found CallSync: " .. comp.Name .. " (Type: " .. tostring(comp.Type) .. ")")
        elseif comp.Type == self.componentTypes.ClickShare then
            table.insert(discovered.clickShareNames, comp.Name)
            self:debugPrint("Found ClickShare: " .. comp.Name)
        elseif comp.Type == self.componentTypes.roomControls then
            if string.match(comp.Name, "^compRoomControls") then
                table.insert(discovered.roomControlsNames, comp.Name)
                self:debugPrint("Found Room Controls: " .. comp.Name .. " (Type: " .. tostring(comp.Type) .. ")")
            end
        end
    end
    
    self:debugPrint("Discovery complete - CallSync: " .. #discovered.callSyncNames .. 
                   ", Room Controls: " .. #discovered.roomControlsNames)
    
    return discovered
end

--------------------------------[ Component Setup ]--------------------------------
function ExtronDXPMatrixController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Helper to populate choices and set up EventHandler for a component selector
    local function setupComponentSelector(ctrl, componentNames, setMethod, componentType)
        if not ctrl then return end
        
        -- Build choices array with clear option
        local choices = { self.clearString }
        for _, name in ipairs(componentNames) do
            table.insert(choices, name)
        end
        ctrl.Choices = choices
        
        -- Set up EventHandler for user selection changes
        bind(ctrl, function()
            self:debugPrint(componentType .. " selection changed to: " .. ctrl.String)
            setMethod(self)
        end)
        
        -- Auto-select first discovered component if available and control is empty
        if #componentNames > 0 and (ctrl.String == "" or ctrl.String == nil) then
            ctrl.String = componentNames[1]
            self:debugPrint("Auto-selected " .. componentType .. ": " .. componentNames[1])
        end
    end
    
    -- Setup Extron DXP Router selector
    setupComponentSelector(
        self.controls.compExtronDXPMatrix,
        discovered.extronDXPNames,
        self.setExtronDXPComponent,
        "Extron DXP Matrix"
    )
    
    -- Setup CallSync selector
    setupComponentSelector(
        self.controls.compCallSync,
        discovered.callSyncNames,
        self.setCallSyncComponent,
        "CallSync"
    )
    
    -- Setup ClickShare selector
    setupComponentSelector(
        self.controls.compClickShare,
        discovered.clickShareNames,
        self.setClickShareComponent,
        "ClickShare"
    )
    
    -- Setup Room Controls selector
    setupComponentSelector(
        self.controls.compRoomControls,
        discovered.roomControlsNames,
        self.setRoomControlsComponent,
        "Room Controls"
    )
    
    -- Setup UCI Layer Selector (if exists)
    local success, uciSelector = pcall(function() 
        return Component.New('BDRM-UCI Layer Selector') 
    end)
    if success and uciSelector then
        self.uciLayerSelector = uciSelector
        self:debugPrint("UCI Layer Selector set")
    end
end

-- Generic component setup method (DRY: consolidates repetitive setup methods - Pattern #21)
function ExtronDXPMatrixController:setComponentByType(ctrl, componentType, storageKey, eventMap, expectedComponentType)
    if not ctrl then return end
    
    -- CRITICAL: Clean up old handlers before reassigning (Pattern #25/#33)
    local oldComponent = self[storageKey]
    if oldComponent and eventMap then
        local controlNames = {}
        for controlName, _ in pairs(eventMap) do
            table.insert(controlNames, controlName)
        end
        cleanupComponentHandlers(
            oldComponent,
            controlNames,
            function(msg) self:debugPrint("[" .. componentType .. "] " .. msg) end
        )
    end
    
    -- Set new component with type validation
    self[storageKey] = self:setComponent(ctrl, componentType, expectedComponentType)
    
    -- Register event handlers if component is valid and event map provided
    if self[storageKey] and eventMap then
        for controlName, handler in pairs(eventMap) do
            if self[storageKey][controlName] then
                bind(self[storageKey][controlName], handler)
            end
        end
    end
    
    return self[storageKey]
end

-- Specific component setup methods (maintained for backward compatibility)
function ExtronDXPMatrixController:setExtronDXPComponent()
    self.extronRouter = self:setComponent(self.controls.compExtronDXPMatrix, "Extron DXP Matrix")
end

function ExtronDXPMatrixController:setCallSyncComponent()
    -- Event map for CallSync component
    local callSyncEventMap = {
        ["off.hook"] = function(ctl)
            -- No guards - checkAutoSwitch() will power on system if needed
            self:checkAutoSwitch()
        end
    }
    
    -- Skip type validation - discovery already validated component types
    self:setComponentByType(
        self.controls.compCallSync,
        "CallSync",
        "callSync",
        callSyncEventMap,
        nil  -- Type already validated during discovery
    )
end

function ExtronDXPMatrixController:setClickShareComponent()
    self.ClickShare = self:setComponent(self.controls.compClickShare, "ClickShare")
end

function ExtronDXPMatrixController:setRoomControlsComponent()
    -- Event map for Room Controls component
    local roomControlsEventMap = {
        ["ledSystemPower"] = function(ctl)
            self.systemPowered = ctl.Boolean
            self:debugPrint("System power state: " .. tostring(self.systemPowered))
            if self.systemPowered then
                self:checkAutoSwitch()
            end
            -- Note: Power-off recovery handled by ledSystemCooling handler
        end,
        ["ledSystemWarming"] = function(ctl)
            self.systemWarming = ctl.Boolean
            self:debugPrint("System warming state: " .. tostring(self.systemWarming))
            if not self.systemWarming and self.systemPowered then
                self:checkAutoSwitch()
            end
        end,
        ["ledSystemCooling"] = function(ctl)
            self.systemCooling = ctl.Boolean
            self:debugPrint("System cooling state: " .. tostring(self.systemCooling))
            if not self.systemCooling and not self.systemPowered then
                -- System powered OFF - wait for settle then check if priority source still active
                -- This handles accidental power-off or power loss recovery
                Timer.CallAfter(function()
                    self:debugPrint("Power-off settle complete, checking for active priority sources...")
                    self:checkAutoSwitch()
                end, 2)
            end
        end
    }
    
    -- Skip type validation - discovery already validated component types
    self:setComponentByType(
        self.controls.compRoomControls,
        "Room Controls",
        "roomControls",
        roomControlsEventMap,
        nil  -- Type already validated during discovery
    )
end

--------------------------------[ Routing Methods ]--------------------------------
function ExtronDXPMatrixController:setRoute(input, output)
    if not self.extronRouter then return end
    
    self.extronRouter['output.' .. output].String = tostring(input)
    self:debugPrint("Set Output " .. output .. " to Input " .. input)

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearRoute(output)
    if not self.extronRouter then return end
    
    self.extronRouter['output.' .. output].String = '0'
    self:debugPrint("Cleared Output " .. output)

    self:updateDestinationFeedback()
    self:updateDestinationText()
end

function ExtronDXPMatrixController:clearAllRoutes()
    for output = 1, 4 do
        self:clearRoute(output)
    end
    
    -- Update source text display
    self:updateSourceText()
end

function ExtronDXPMatrixController:setSource(input)
    if not self.extronRouter then return end
    
    -- Select the corresponding source button to keep UI in sync
    self:selectSourceButton(input)
    
    -- TeamsPC special routing: primary to odd outputs, secondary to even outputs
    if input == self.inputs.TeamsPC then
        -- Route TeamsPC to outputs 1 and 3, TeamsPCSecondary to outputs 2 and 4
        self:setRoute(self.inputs.TeamsPC, 1)
        self:setRoute(self.inputs.TeamsPCSecondary, 2)
        self:setRoute(self.inputs.TeamsPC, 3)
        self:setRoute(self.inputs.TeamsPCSecondary, 4)
    else
        -- Normal routing: route to all 4 outputs
        for dest = 1, 4 do
            self:setRoute(input, dest)
        end
    end
    
    -- Update source text display and destination feedback
    self:updateSourceText()
    self:updateDestinationFeedback()
end

function ExtronDXPMatrixController:updateDestinationFeedback()
    if not self.extronRouter then return end
    
    local selectedSource = self:getSelectedSource()
    
    for i = 1, 4 do
        local currentInput = tonumber(self.extronRouter['output.' .. i].String) or 0
        local isRouted = false
        
        if selectedSource then
            -- TeamsPC: consider both primary (input 2) and secondary (input 3) as "selected"
            if selectedSource == self.inputs.TeamsPC then
                isRouted = (currentInput == self.inputs.TeamsPC) or 
                           (currentInput == self.inputs.TeamsPCSecondary)
            else
                isRouted = (currentInput == selectedSource)
            end
        end
        
        if self.normalizedControls.ledSourceRouted[i] then
            setProp(self.normalizedControls.ledSourceRouted[i], "Boolean", isRouted)
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
    
    local activeRoutes = {}
    local activeCount = 0
    
    for output = 1, 4 do
        local currentInput = tonumber(self.extronRouter['output.' .. output].String) or 0
        if currentInput > 0 then
            activeCount = activeCount + 1
            local sourceName = self.sourceNames[currentInput] or "Unknown"
            table.insert(activeRoutes, sourceName .. " → " .. destinationNames[output])
        end
    end
    
    if activeCount == 0 then
        setProp(self.controls.txtStatus, "String", "")
    elseif activeCount == 4 then
        setProp(self.controls.txtStatus, "String", "All Displays Active")
        Timer.CallAfter(function()
            setProp(self.controls.txtStatus, "String", "")
        end, 3)
    else
        setProp(self.controls.txtStatus, "String", table.concat(activeRoutes, ", "))
    end
end

--------------------------------[ Auto-Switching Methods ]--------------------------------
function ExtronDXPMatrixController:checkAutoSwitch()
    -- Check sources in priority order and route to ALL displays
    for _, source in ipairs(self.sourcePriority) do
        if source.checkFunc() then
            -- Power on system if not already powered
            if not self.systemPowered and self.roomControls then
                self:debugPrint("Powering on system for " .. source.name)
                self.roomControls["btnSystemOnOff"].Boolean = true
            end
            
            self:debugPrint("Auto-switching to " .. source.name)
            self:setSource(source.input)
            return
        end
    end
end

function ExtronDXPMatrixController:setupAutoSwitchMonitoring()
    -- Note: CallSync off-hook monitoring is now handled in setCallSyncComponent()
    -- via the event map pattern for consistency
    
    -- Monitor Extron signal presence
    -- No guards - checkAutoSwitch() will power on system if needed
    forEach(self.normalizedControls.ledExtronSignalPresence, function(i, ctrl)
        bind(ctrl, function(ctl)
            self:checkAutoSwitch()
        end)
    end)
end

--------------------------------[ Helper Methods ]--------------------------------
function ExtronDXPMatrixController:setDestinationButtonProperties(output, color, text, disabled)
    local btn = self.normalizedControls.btnDestination[output]
    if not btn then return end
    
    setProp(btn, "Color", color)
    if text and text ~= "" then
        setProp(btn, "String", text)
    end
    setProp(btn, "IsDisabled", disabled)
    
    self:debugPrint("Set destination button " .. output .. " properties: color=" .. 
                   color .. ", disabled=" .. tostring(disabled))
end

function ExtronDXPMatrixController:getSelectedSource()
    -- DRY: Use centralized source button to input mapping
    for src = 1, 6 do
        local btn = self.normalizedControls.btnVideoSource[src]
        if btn and btn.Boolean then
            return self.sourceButtonToInput[src]
        end
    end
    return nil
end

function ExtronDXPMatrixController:selectSourceButton(input)
    -- Find and select the button that corresponds to this input
    for btnIndex, inputNum in pairs(self.sourceButtonToInput) do
        if inputNum == input then
            -- Deselect all buttons
            for i = 1, 6 do
                local btn = self.normalizedControls.btnVideoSource[i]
                if btn then setProp(btn, "Boolean", false) end
            end
            -- Select the matching button
            local btn = self.normalizedControls.btnVideoSource[btnIndex]
            if btn then 
                setProp(btn, "Boolean", true)
                self:updateSourceText()
            end
            return
        end
    end
end

function ExtronDXPMatrixController:updateSourceText()
    local selectedInput = self:getSelectedSource()
    local sourceName = "No Source"
    
    if selectedInput and self.sourceNames[selectedInput] then
        sourceName = self.sourceNames[selectedInput]
    end
    
    setProp(self.controls.txtSource, "String", sourceName)
end

--------------------------------[ Event Handler Registration ]--------------------------------
function ExtronDXPMatrixController:registerEventHandlers()
    -- Source selection buttons (interlocking)
    local sourceHandlers = {}
    for i = 1, 6 do
        local btn = self.normalizedControls.btnVideoSource[i]
        if btn then
            sourceHandlers[btn] = function(ctl)
                if not ctl.Boolean then return end
                
                -- Deselect all other sources (interlocking)
                for srcButton = 1, 6 do
                    if srcButton ~= i then
                        local otherBtn = self.normalizedControls.btnVideoSource[srcButton]
                        if otherBtn then setProp(otherBtn, "Boolean", false) end
                    end
                end
                
                -- Handle Teams PC button properties (disable even outputs)
                -- Check for both TeamsPC (index 2) and TeamsPC2 (index 3)
                if i == 2 or i == 3 then
                    self:setDestinationButtonProperties(2, '#ff6666', 'N/A', true)
                    self:setDestinationButtonProperties(4, '#ff6666', 'N/A', true)
                else
                    self:setDestinationButtonProperties(2, '#ff7c7c7c', '', false)
                    self:setDestinationButtonProperties(4, '#ff7c7c7c', '', false)
                end
                
                -- Update source text display and destination feedback LEDs
                self:updateSourceText()
                self:updateDestinationFeedback()
            end
        end
    end
    
    -- Destination selection buttons
    local destinationHandlers = {}
    for i = 1, 5 do
        local btn = self.normalizedControls.btnDestination[i]
        if btn then
            destinationHandlers[btn] = function(ctl)
                local selectedSource = self:getSelectedSource()
                if not selectedSource then return end
                
                -- btnDestination[5]: Route to ALL destinations
                if i == 5 then
                    if selectedSource == self.inputs.TeamsPC or selectedSource == self.inputs.TeamsPCSecondary then
                        -- TeamsPC: route input 2 to outputs 1,3 and input 3 to outputs 2,4
                        self:setRoute(self.inputs.TeamsPC, 1)
                        self:setRoute(self.inputs.TeamsPCSecondary, 2)
                        self:setRoute(self.inputs.TeamsPC, 3)
                        self:setRoute(self.inputs.TeamsPCSecondary, 4)
                    else
                        -- Normal sources: route to all 4 outputs
                        for dest = 1, 4 do
                            self:setRoute(selectedSource, dest)
                        end
                    end
                -- TeamsPC special routing: primary to odd outputs, secondary to adjacent even outputs
                elseif selectedSource == self.inputs.TeamsPC or selectedSource == self.inputs.TeamsPCSecondary then
                    if i == 1 then
                        -- btnDestination[1]: TeamsPC to output 1, TeamsPCSecondary to output 2
                        self:setRoute(self.inputs.TeamsPC, 1)
                        self:setRoute(self.inputs.TeamsPCSecondary, 2)
                    elseif i == 3 then
                        -- btnDestination[3]: TeamsPC to output 3, TeamsPCSecondary to output 4
                        self:setRoute(self.inputs.TeamsPC, 3)
                        self:setRoute(self.inputs.TeamsPCSecondary, 4)
                    end
                    -- btnDestination[2] and [4] are disabled when TeamsPC is selected
                else
                    -- Normal routing: route selected source to pressed destination
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

--------------------------------[ Initialization ]--------------------------------
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
    
    -- Disable TeamsPC2 button (input 3 cannot be routed independently)
    local teamsPC2Btn = self.normalizedControls.btnVideoSource[3]
    if teamsPC2Btn then
        setProp(teamsPC2Btn, "IsDisabled", true)
        setProp(teamsPC2Btn, "Color", "#ff6666")
    end
    
    -- Initialize destination feedback LEDs
    self:updateDestinationFeedback()
    
    self:debugPrint("Extron DXP Controller initialization complete")
end

--------------------------------[ Cleanup ]--------------------------------
function ExtronDXPMatrixController:cleanup()
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    
    self.uciController = nil
    self:debugPrint("Cleanup completed")
end

--------------------------------[ Factory Function ]--------------------------------
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
        -- Use debugPrint for consistency (controller.debugging may be false, so direct print here)
        print("[Extron DXP] ✓ Successfully created Extron DXP Matrix Controller")
        return controller
    else
        print("[Extron DXP] ✗ Failed to create Extron DXP Matrix Controller: " .. tostring(controller))
        return nil
    end
end

--------------------------------[ Instance Creation ]--------------------------------
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

CRITICAL: Layer Navigation Pattern
  - NEVER call layer navigation directly on the UCI
  - ALWAYS use triggerUCILayer(layer) which calls btnNav[i]:Trigger()
  - This ensures signals propagate correctly through the UCI script's event handlers
  - Direct layer manipulation bypasses UCI script logic and can cause state desynchronization

Auto-switching Integration:
  - Monitors system power and warming states
  - Integrates with CallSync off-hook detection
  - Extron signal presence monitoring
  - Priority-based source selection

REFACTORING SUMMARY:
✓ Comprehensive control validation with descriptive error messages
✓ Control array normalization for consistent data structures
✓ Essential utility functions (isArr, setProp, bind, bindArray, forEach)
✓ cleanupComponentHandlers() utility (Pattern #25/#33) - CRITICAL for divisible spaces
✓ Generic component setup method (Pattern #21) - eliminates code duplication
✓ Centralized source input mapping logic - DRY principle compliance
✓ Batch event registration using handler maps
✓ Optimized property access with cached references
✓ Factory function with enhanced error handling
✓ Direct routing and state management
✓ Flattened control flow with early returns
✓ Component discovery using Component.GetComponents()
✓ Full compliance with Lua Refactoring Prompt specifications v3.0
✓ DRY principles applied throughout
]]--
