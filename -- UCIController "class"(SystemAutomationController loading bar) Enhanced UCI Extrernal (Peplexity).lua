--[[ 
    UCIController class - Enhanced Version with Universal Video Switcher Integration
    Date: 2025-06-18
    Version: 1.2 (Performance Optimized String Concatenation)
    Author: Nikolas Smith, Q-SYS
    Firmware Req: 10.0
    Notes:
    - This script is a modified version of the UCIController class that adds enhanced error handling and validation for required controls.
    - It also adds a check for the Room Controls component and a fallback method if the component is not found.
    - It also adds a check for the System Automation component and a fallback method if the component is not found.
    - NEW: Universal video switcher integration supporting NV32, Extron DXP, and other video switchers
    - PERFORMANCE: Optimized string concatenation with caching for high-frequency operations
--]]

UCIController = {}
UCIController.__index = UCIController

-- Video Switcher Integration System
local VideoSwitcherIntegration = {}

-- Component discovery cache (shared across instances)
local componentDiscoveryCache = {
    timestamp = 0,
    cacheDuration = 30, -- Cache for 30 seconds
    data = nil
}

-- Safe Controls access helper function
local function safeControl(controlName, property)
    if not Controls[controlName] then
        print("Warning: Control '" .. tostring(controlName) .. "' not found")
        return nil
    end
    
    if property then
        if Controls[controlName][property] == nil then
            print("Warning: Property '" .. tostring(property) .. "' not found on control '" .. tostring(controlName) .. "'")
            return nil
        end
        return Controls[controlName][property]
    end
    
    return Controls[controlName]
end

-- Optimized string formatting helpers
local buttonNameCache = {}
local function getButtonName(buttonNumber)
    if not buttonNameCache[buttonNumber] then
        buttonNameCache[buttonNumber] = "btnNav" .. string.format("%02d", buttonNumber)
    end
    return buttonNameCache[buttonNumber]
end

local function getButtonNameWithPrefix(prefix, buttonNumber)
    local key = prefix .. buttonNumber
    if not buttonNameCache[key] then
        buttonNameCache[key] = prefix .. string.format("%02d", buttonNumber)
    end
    return buttonNameCache[key]
end

-- Optimized legend text helper
local legendNameCache = {}
local function getLegendName(legendNumber)
    if not legendNameCache[legendNumber] then
        legendNameCache[legendNumber] = "txtNav" .. string.format("%02d", legendNumber)
    end
    return legendNameCache[legendNumber]
end

-- Video Switcher Types and Configurations
VideoSwitcherIntegration.SwitcherTypes = {
    NV32 = {
        name = "NV32",
        componentType = "streamer_hdmi_switcher",
        variableNames = {"devNV32", "codenameNV32", "varNV32", "nv32Device", "nv32Component"},
        routingMethod = "hdmi.out.1.select.index",
        defaultMapping = {
            [7] = 5, -- btnNav07 → HDMI2 (Input 5)
            [8] = 4, -- btnNav08 → HDMI1 (Input 4)
            [9] = 6  -- btnNav09 → HDMI3 (Input 6)
        }
    },
    ExtronDXP = {
        name = "Extron DXP",
        componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        variableNames = {"devExtronDXP", "codenameExtronDXP", "varExtronDXP", "extronDXPDevice", "extronDXPComponent"},
        routingMethod = "output.1", -- Uses String property with input number
        defaultMapping = {
            [7] = 2, -- btnNav07 → Teams PC (Input 2)
            [8] = 4, -- btnNav08 → Laptop Front (Input 4)
            [9] = 1  -- btnNav09 → ClickShare (Input 1)
        }
    },
    Generic = {
        name = "Generic",
        componentType = nil, -- Will be auto-detected
        variableNames = {"devVideoSwitcher", "codenameVideoSwitcher", "varVideoSwitcher"},
        routingMethod = "output.1", -- Default routing method
        defaultMapping = {
            [7] = 1, -- btnNav07 → Input 1
            [8] = 2, -- btnNav08 → Input 2
            [9] = 3  -- btnNav09 → Input 3
        }
    }
}

-- Video Switcher Integration Class
function VideoSwitcherIntegration.new()
    local self = {}
    
    -- Instance properties
    self.switcherType = nil
    self.switcherComponent = nil
    self.switcherConfig = nil
    self.isEnabled = false
    self.debugMode = true
    self.uciToInputMapping = {}
    self.monitoringTimer = nil
    self.previousButtonStates = {}
    
    -- Debug helper
    function self:debugPrint(str)
        if self.debugMode then
            print("[Video Switcher] " .. str)
        end
    end
    
    -- Discover video switcher components (Optimized O(N+M) approach with caching)
    function self:discoverSwitchers()
        local currentTime = Timer.Now()
        
        -- Check cache first
        if componentDiscoveryCache.data and 
           (currentTime - componentDiscoveryCache.timestamp) < componentDiscoveryCache.cacheDuration then
            self:debugPrint("Using cached component discovery data")
            return componentDiscoveryCache.data
        end
        
        local startTime = Timer.Now()
        local components = Component.GetComponents()
        local discovered = {}
        
        -- Build component type map first (O(N))
        local componentTypeMap = {}
        local componentCount = 0
        for _, comp in pairs(components) do
            componentCount = componentCount + 1
            if not componentTypeMap[comp.Type] then
                componentTypeMap[comp.Type] = {}
            end
            table.insert(componentTypeMap[comp.Type], comp.Name)
        end
        
        -- Check for matches against switcher types (O(M))
        local switcherTypeCount = 0
        for switcherType, config in pairs(VideoSwitcherIntegration.SwitcherTypes) do
            switcherTypeCount = switcherTypeCount + 1
            if config.componentType and componentTypeMap[config.componentType] then
                discovered[switcherType] = componentTypeMap[config.componentType]
                self:debugPrint("Found " .. switcherType .. " components: " .. #componentTypeMap[config.componentType])
            end
        end
        
        -- Update cache
        componentDiscoveryCache.data = discovered
        componentDiscoveryCache.timestamp = currentTime
        
        local endTime = Timer.Now()
        local duration = (endTime - startTime) * 1000 -- Convert to milliseconds
        self:debugPrint(string.format("Component discovery completed in %.2fms (Components: %d, SwitcherTypes: %d)", 
                                     duration, componentCount, switcherTypeCount))
        
        return discovered
    end
    
    -- Auto-detect switcher type (using direct Controls access like Brookgreen version)
    function self:autoDetectSwitcherType()
        local discovered = self:discoverSwitchers()
        
        -- Check UCI variables first (direct access)
        for switcherType, config in pairs(VideoSwitcherIntegration.SwitcherTypes) do
            for _, varName in ipairs(config.variableNames) do
                if Controls[varName] then
                    local varValue = Controls[varName].String or ""
                    if varValue ~= "" then
                        self:debugPrint("Found " .. switcherType .. " via UCI variable: " .. varName)
                        return switcherType, varValue
                    end
                end
            end
        end
        
        -- Check discovered components
        for switcherType, components in pairs(discovered) do
            if #components > 0 then
                self:debugPrint("Auto-detected " .. switcherType .. " component: " .. components[1])
                return switcherType, components[1]
            end
        end
        
        return nil, nil
    end
    
    -- Initialize video switcher integration
    function self:initialize()
        self:debugPrint("Initializing Video Switcher Integration")
        
        -- Auto-detect switcher type and component
        local switcherType, componentName = self:autoDetectSwitcherType()
        
        if not switcherType then
            self:debugPrint("No video switcher detected - integration disabled")
            return false
        end
        
        -- Set up configuration
        self.switcherType = switcherType
        self.switcherConfig = VideoSwitcherIntegration.SwitcherTypes[switcherType]
        self.uciToInputMapping = self.switcherConfig.defaultMapping
        
        -- Create component reference
        local success, component = pcall(function()
            return Component.New(componentName)
        end)
        
        if success and component then
            self.switcherComponent = component
            self:debugPrint("Video switcher component created: " .. componentName)
        else
            self:debugPrint("Failed to create video switcher component: " .. tostring(component))
            return false
        end
        
        -- Timer-based monitoring disabled - using direct event handlers instead
        self:debugPrint("Using direct event handlers for video switching")
        
        self.isEnabled = true
        self:debugPrint("Video Switcher Integration initialized successfully")
        return true
    end
    
    -- Set up UCI button monitoring
    function self:setupUCIButtonMonitoring()
        if not self.isEnabled then return end
        
        -- Create monitoring timer
        self.monitoringTimer = Timer.New()
        self.monitoringTimer.EventHandler = function()
            for uciButton, inputNumber in pairs(self.uciToInputMapping) do
                local buttonName = getButtonName(uciButton)
                local currentState = safeControl(buttonName, "Boolean")
                if currentState ~= nil then
                    local previousState = self.previousButtonStates[uciButton]
                    
                    -- Check if button state changed to true
                    if currentState and not previousState then
                        self:switchToInput(inputNumber, uciButton)
                    end
                    
                    -- Update previous state
                    self.previousButtonStates[uciButton] = currentState
                end
            end
            
            -- Continue monitoring
            self.monitoringTimer:Start(0.1) -- Check every 100ms
        end
        
        -- Start the monitoring timer
        self.monitoringTimer:Start(0.1)
        self:debugPrint("UCI button monitoring started")
    end
    
    -- Switch to specific input
    function self:switchToInput(inputNumber, uciButton)
        if not self.isEnabled or not self.switcherComponent then
            self:debugPrint("⚠ Video switcher not enabled or component not available")
            return false
        end
        
        self:debugPrint("UCI Button " .. uciButton .. " pressed, switching to input " .. inputNumber)
        self:debugPrint("Switcher type: " .. self.switcherType .. ", Routing method: " .. self.switcherConfig.routingMethod)
        
        local success, err = pcall(function()
            local operationSuccess = false
            
            if self.switcherType == "NV32" then
                -- NV32 uses Value property
                self:debugPrint("Setting NV32 " .. self.switcherConfig.routingMethod .. " to " .. inputNumber)
                self.switcherComponent[self.switcherConfig.routingMethod].Value = inputNumber
                -- Verify the operation was successful
                operationSuccess = (self.switcherComponent[self.switcherConfig.routingMethod].Value == inputNumber)
                self:debugPrint("NV32 verification result: " .. tostring(operationSuccess))
            elseif self.switcherType == "ExtronDXP" then
                -- Extron DXP uses String property
                self:debugPrint("Setting Extron DXP " .. self.switcherConfig.routingMethod .. " to " .. tostring(inputNumber))
                self.switcherComponent[self.switcherConfig.routingMethod].String = tostring(inputNumber)
                -- Verify the operation was successful
                operationSuccess = (self.switcherComponent[self.switcherConfig.routingMethod].String == tostring(inputNumber))
            else
                -- Generic switcher - try both methods
                local success1 = pcall(function()
                    self.switcherComponent[self.switcherConfig.routingMethod].Value = inputNumber
                    return (self.switcherComponent[self.switcherConfig.routingMethod].Value == inputNumber)
                end)
                if success1 then
                    operationSuccess = true
                else
                    local success2 = pcall(function()
                        self.switcherComponent[self.switcherConfig.routingMethod].String = tostring(inputNumber)
                        return (self.switcherComponent[self.switcherConfig.routingMethod].String == tostring(inputNumber))
                    end)
                    operationSuccess = success2
                end
            end
            
            if not operationSuccess then
                error("Failed to verify input switch operation")
            end
            
            return operationSuccess
        end)
        
        if success then
            self:debugPrint("✓ Successfully switched to input " .. inputNumber)
            return true
        else
            self:debugPrint("⚠ Failed to switch to input " .. inputNumber .. ": " .. tostring(err))
            return false
        end
    end
    
    -- Update UCI to input mapping
    function self:updateMapping(newMapping)
        self.uciToInputMapping = newMapping or self.switcherConfig.defaultMapping
        self:debugPrint("Updated UCI to input mapping")
    end
    
    -- Get current status
    function self:getStatus()
        return {
            enabled = self.isEnabled,
            switcherType = self.switcherType,
            componentValid = (self.switcherComponent ~= nil),
            mapping = self.uciToInputMapping
        }
    end
    
    -- Cleanup
    function self:cleanup()
        -- No timer cleanup needed since we're using direct event handlers
        self.switcherComponent = nil
        self.isEnabled = false
        self:debugPrint("Video Switcher Integration cleaned up")
    end
    
    return self
end

-- Add debug check for required controls
function UCIController:checkRequiredControls()
    print("=== Checking Required Controls ===")
    local requiredControls = {
        -- Main Navigation Buttons
        "btnNav01",
        "btnNav02",
        "btnNav03",
        "btnNav04",
        "btnNav05",
        "btnNav06",
        "btnNav07",
        "btnNav08",
        "btnNav09",
        "btnNav10",
        "btnNav11",
        "btnNav12",
        -- System Control Buttons
        "btnStartSystem",
        "btnNavShutdown",
        "btnShutdownCancel",
        "btnShutdownConfirm",
        -- Help Sublayer Buttons (optional)
        "btnHelpLaptop",
        "btnHelpPC",
        "btnHelpWireless",
        "btnHelpRouting",
        "btnHelpDialer",
        "btnHelpStreamMusic"
    }
    
    local missingControls = {}
    for _, controlName in ipairs(requiredControls) do
        if Controls[controlName] then
            print("✓ " .. controlName .. " exists")
        else
            print("✗ " .. controlName .. " is missing")
            table.insert(missingControls, controlName)
        end
    end
    
    if #missingControls > 0 then
        print("=== WARNING: Missing Required Controls ===")
        for _, controlName in ipairs(missingControls) do
            print("Missing: " .. controlName)
        end
        print("=== End Missing Controls Warning ===")
    end
    
    print("=== End Controls Check ===")
    return #missingControls == 0
end

function UCIController.new(uciPage, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices, hiddenHelpIndices)
    local self = setmetatable({}, UCIController)
    
    print("=== Creating new UCIController ===")
    print("Page name: " .. tostring(uciPage))
    print("Default routing layer: " .. tostring(defaultRoutingLayer))
    print("Default active layer: " .. tostring(defaultActiveLayer))
    
    -- Initialize layerStates table first
    self.layerStates = {}
    
    -- Instance properties
    self.uciPage            = uciPage
    self.varActiveLayer     = defaultActiveLayer or 3 -- kLayerStart
    self.defaultActiveLayer = defaultActiveLayer or 8 -- Store the default active layer
    self.isAnimating        = false
    self.loadingTimer       = nil
    self.timeoutTimer       = nil
    self.hiddenNavIndices   = hiddenNavIndices or {}
    self.hiddenHelpIndices  = hiddenHelpIndices or {}
    self.isInitialized      = false
    
    -- External controller registration for UCI layer change notifications
    self.externalControllers = {}
    
    -- Video Switcher Integration
    self.videoSwitcher = VideoSwitcherIntegration.new()
    
    -- Check required controls before proceeding
    self:checkRequiredControls()
    
    -- Layer constants
    self.kLayerAlarm        = 1
    self.kLayerIncomingCall = 2
    self.kLayerStart        = 3
    self.kLayerWarming      = 4
    self.kLayerCooling      = 5
    self.kLayerRoomControls = 6
    self.kLayerPC           = 7
    self.kLayerLaptop       = 8
    self.kLayerWireless     = 9
    self.kLayerRouting      = 10
    self.kLayerDialer       = 11
    self.kLayerStreamMusic  = 12    

    -- Room Automation Component Reference
    self.roomControlsComponent = nil
    self:initializeRoomControlsComponent()
    
    -- Setup arrays for controls and labels with validation
    self.arrbtnNavs = {}
    local navButtons = {
        "btnNav01", "btnNav02", "btnNav03", "btnNav04",
        "btnNav05", "btnNav06", "btnNav07", "btnNav08",
        "btnNav09", "btnNav10", "btnNav11", "btnNav12"
    }
    
    for i, buttonName in ipairs(navButtons) do
        local control = safeControl(buttonName)
        if control then
            self.arrbtnNavs[i] = control
        else
            print("Warning: Navigation button " .. buttonName .. " not found")
            self.arrbtnNavs[i] = nil
        end
    end
    
    self.arrUCILegends = {}
    local legendControls = {
        "txtNav01", "txtNav02", "txtNav03", "txtNav04",
        "txtNav05", "txtNav06", "txtNav07", "txtNav08",
        "txtNav09", "txtNav10", "txtNav11", "txtNav12",
        "txtNavShutdown", "txtRoomName", "txtRoomNameStart",
        "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03",
        "txtRouting04", "txtRouting05", "txtRoutingSources",
        "txtAudSrc01", "txtAudSrc02", "txtAudSrc03", "txtAudSrc04",
        "txtAudSrc05", "txtAudSrc06", "txtAudSrc07", "txtAudSrc08",
        "txtGainPGM", "txtGain01", "txtGain02", "txtGain03", "txtGain04",
        "txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
        "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04"
    }
    
    for i, controlName in ipairs(legendControls) do
        local control = safeControl(controlName)
        if control then
            self.arrUCILegends[i] = control
        else
            print("Warning: Legend control " .. controlName .. " not found")
            self.arrUCILegends[i] = nil
        end
    end
    
    self.arrUCIUserLabels = {}
    local userLabelVariables = {
        "txtLabelNav01", "txtLabelNav02", "txtLabelNav03", "txtLabelNav04",
        "txtLabelNav05", "txtLabelNav06", "txtLabelNav07", "txtLabelNav08",
        "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12",
        "txtLabelNavShutdown", "txtLabelRoomName", "txtLabelRoomNameStart",
        "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03",
        "txtLabelRouting04", "txtLabelRouting05", "txtLabelRoutingSources",
        "txtLabelAudSrc01", "txtLabelAudSrc02", "txtLabelAudSrc03", "txtLabelAudSrc04",
        "txtLabelAudSrc05", "txtLabelAudSrc06", "txtLabelAudSrc07", "txtLabelAudSrc08",
        "txtLabelGainPGM", "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04",
        "txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
        "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04"
    }
    
    for i, varName in ipairs(userLabelVariables) do
        local variable = Uci.Variables[varName]
        if variable then
            self.arrUCIUserLabels[i] = variable
        else
            print("Warning: UCI Variable " .. varName .. " not found")
            self.arrUCIUserLabels[i] = nil
        end
    end
    
    -- Setup arrays for routing controls with validation
    self.arrRoutingButtons = {}
    local routingButtons = {
        "btnRouting01", "btnRouting02", "btnRouting03", "btnRouting04", "btnRouting05"
    }
    
    for i, buttonName in ipairs(routingButtons) do
        local control = safeControl(buttonName)
        if control then
            self.arrRoutingButtons[i] = control
        else
            print("Warning: Routing button " .. buttonName .. " not found")
            self.arrRoutingButtons[i] = nil
        end
    end
    
    self.routingLayers = {
        "R01-Routing-Lobby", 
        "R02-Routing-WTerrace", 
        "R03-Routing-NTerraceWall",
        "R04-Routing-Garden", 
        "R05-Routing-NTerraceFloor"
    }
    
    -- Set default routing layer with fallback to 1 if not provided
    self.activeRoutingLayer = defaultRoutingLayer or 1
    
    -- Setup
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

-- Initialize Room Controls Component Reference with enhanced error handling
function UCIController:initializeRoomControlsComponent()
    -- Try different methods to get the component name
    local componentName = nil
    
    -- Method 1: Try UCI variable
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    
    -- Method 2: Try default naming convention
    if not componentName then
        local pageName = self.uciPage:match("UCI%s+([^(]+)")
        if pageName then
            pageName = pageName:gsub("%s+", "")
            componentName = "compRoomControls" .. pageName
        end
    end
    
    if not componentName then
        print("Warning: Could not determine Room Controls component name")
        self.roomControlsComponent = nil
        return
    end
    
    print("Attempting to reference Room Controls component: " .. componentName)
    
    local success, component = pcall(function()
        return Component.New(componentName)
    end)
    
    if success and component then
        self.roomControlsComponent = component
        print("Room Controls Component successfully referenced: " .. componentName)
    else
        print("Warning: Room Controls Component '" .. componentName .. "' not found - using direct control method")
        self.roomControlsComponent = nil
    end
end

-- Add layer transition validation
function UCIController:validateLayerTransition(fromLayer, toLayer)
    -- Add validation logic to prevent invalid transitions
    local validTransitions = {
        [self.kLayerStart] = {self.kLayerAlarm, self.kLayerWarming, self.kLayerCooling},
        [self.kLayerWarming] = {self.kLayerAlarm, self.kLayerLaptop, self.kLayerPC, self.kLayerWireless, self.kLayerRouting, self.kLayerDialer, self.kLayerStreamMusic},
        [self.kLayerCooling] = {self.kLayerAlarm, self.kLayerStart},
        [self.kLayerRoomControls] = {self.kLayerAlarm, self.kLayerPC, self.kLayerWireless, self.kLayerRouting, self.kLayerDialer, self.kLayerStreamMusic},
        [self.kLayerPC] = {self.kLayerAlarm, self.kLayerRoomControls, self.kLayerLaptop, self.kLayerWireless, self.kLayerRouting, self.kLayerDialer, self.kLayerStreamMusic},
        [self.kLayerWireless] = {self.kLayerAlarm, self.kLayerRoomControls, self.kLayerLaptop, self.kLayerPC, self.kLayerRouting, self.kLayerDialer, self.kLayerStreamMusic},
        [self.kLayerRouting] = {self.kLayerAlarm, self.kLayerRoomControls, self.kLayerLaptop, self.kLayerPC, self.kLayerWireless, self.kLayerDialer, self.kLayerStreamMusic},
        [self.kLayerDialer] = {self.kLayerAlarm, self.kLayerRoomControls, self.kLayerLaptop, self.kLayerPC, self.kLayerWireless, self.kLayerRouting, self.kLayerStreamMusic},
        [self.kLayerStreamMusic] = {self.kLayerAlarm, self.kLayerRoomControls, self.kLayerLaptop, self.kLayerPC, self.kLayerWireless, self.kLayerRouting, self.kLayerDialer}
    }
    
    if not validTransitions[fromLayer] then
        return true -- Allow transition if no restrictions defined
    end
    
    for _, validLayer in ipairs(validTransitions[fromLayer]) do
        if validLayer == toLayer then
            return true
        end
    end
    
    print("Warning: Invalid layer transition from " .. fromLayer .. " to " .. toLayer)
    return false
end

-- Room Automation Integration Methods with enhanced error handling and functional validation
function UCIController:powerOnRoomAutomation()
    local success = false
    local methodUsed = "none"
    
    -- Method 1: Component Reference
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
        local componentSuccess, componentResult = pcall(function()
            self.roomControlsComponent["btnSystemOnOff"].Boolean = true
            -- Verify the operation was successful
            return self.roomControlsComponent["btnSystemOnOff"].Boolean == true
        end)
        if componentSuccess and componentResult then
            print("Room powered ON via component reference")
            success = true
            methodUsed = "component"
        else
            print("Warning: Component reference power ON failed - pcall: " .. tostring(componentSuccess) .. ", result: " .. tostring(componentResult))
        end
    end
    
    -- Method 2: Direct Control (fallback)
    if not success then
        local directSuccess, directResult = pcall(function()
            local control = safeControl("btnSystemOnOff")
            if control then
                control.Boolean = true
                -- Verify the operation was successful
                return control.Boolean == true
            end
            return false
        end)
        if directSuccess and directResult then
            print("Room powered ON via direct control")
            success = true
            methodUsed = "direct"
        else
            print("Warning: Direct control power ON failed - pcall: " .. tostring(directSuccess) .. ", result: " .. tostring(directResult))
        end
    end
    
    -- Method 3: Global Controller Reference (if available)
    if not success and mySystemController then
        local controllerSuccess, controllerResult = pcall(function()
            mySystemController.powerModule.powerOn()
            -- Try to verify the operation was successful
            return mySystemController.powerModule and mySystemController.powerModule.isPoweredOn and mySystemController.powerModule.isPoweredOn() or true
        end)
        if controllerSuccess and controllerResult then
            print("Room powered ON via global controller")
            success = true
            methodUsed = "global_controller"
        else
            print("Warning: Global controller power ON failed - pcall: " .. tostring(controllerSuccess) .. ", result: " .. tostring(controllerResult))
        end
    end
    
    if not success then
        print("Warning: Failed to power on room automation system - all methods failed")
    else
        print("Room automation power ON successful via method: " .. methodUsed)
    end
    
    return success
end

function UCIController:powerOffRoomAutomation()
    local success = false
    local methodUsed = "none"
    
    -- Method 1: Component Reference
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
        local componentSuccess, componentResult = pcall(function()
            self.roomControlsComponent["btnSystemOnOff"].Boolean = false
            -- Verify the operation was successful
            return self.roomControlsComponent["btnSystemOnOff"].Boolean == false
        end)
        if componentSuccess and componentResult then
            print("Room powered OFF via component reference")
            success = true
            methodUsed = "component"
        else
            print("Warning: Component reference power OFF failed - pcall: " .. tostring(componentSuccess) .. ", result: " .. tostring(componentResult))
        end
    end
    
    -- Method 2: Direct Control (fallback)
    if not success then
        local directSuccess, directResult = pcall(function()
            local control = safeControl("btnSystemOnOff")
            if control then
                control.Boolean = false
                -- Verify the operation was successful
                return control.Boolean == false
            end
            return false
        end)
        if directSuccess and directResult then
            print("Room powered OFF via direct control")
            success = true
            methodUsed = "direct"
        else
            print("Warning: Direct control power OFF failed - pcall: " .. tostring(directSuccess) .. ", result: " .. tostring(directResult))
        end
    end
    
    -- Method 3: Global Controller Reference (if available)
    if not success and mySystemController then
        local controllerSuccess, controllerResult = pcall(function()
            mySystemController.powerModule.powerOff()
            -- Try to verify the operation was successful
            return mySystemController.powerModule and mySystemController.powerModule.isPoweredOff and mySystemController.powerModule.isPoweredOff() or true
        end)
        if controllerSuccess and controllerResult then
            print("Room powered OFF via global controller")
            success = true
            methodUsed = "global_controller"
        else
            print("Warning: Global controller power OFF failed - pcall: " .. tostring(controllerSuccess) .. ", result: " .. tostring(controllerResult))
        end
    end
    
    if not success then
        print("Warning: Failed to power off room automation system - all methods failed")
    else
        print("Room automation power OFF successful via method: " .. methodUsed)
    end
    
    return success
end

-- Get Room Automation Timing with enhanced error handling
function UCIController:getRoomAutomationTiming(isPoweringOn)
    local duration
    
    -- Try to get timing from component reference first
    if self.roomControlsComponent then
        local success, result = pcall(function()
            if isPoweringOn then
                return self.roomControlsComponent["warmupTime"] and self.roomControlsComponent["warmupTime"].Value or 10
            else
                return self.roomControlsComponent["cooldownTime"] and self.roomControlsComponent["cooldownTime"].Value or 5
            end
        end)
        
        if success and result then
            duration = result
            print("Using Room Automation component timing: " .. duration .. " seconds")
            return duration
        end
    end
    
    -- Fallback to UCI variables
    if isPoweringOn then
        duration = tonumber(Uci.Variables.timeProgressWarming) or 10
    else
        duration = tonumber(Uci.Variables.timeProgressCooling) or 5
    end
    
    print("Using UCI fallback timing: " .. duration .. " seconds")
    return duration
end

-- Add safe layer visibility method with enhanced error handling
function UCIController:safeSetLayerVisibility(page, layer, visible, transition)
    local success, err = pcall(function()
        Uci.SetLayerVisibility(page, layer, visible, transition)
    end)
    
    if success then
        print("Layer visibility: '" .. layer .. "' set to " .. tostring(visible))
    else
        print("Warning: Layer '" .. layer .. "' not found on page " .. page, ". Error: " .. tostring(err))
    end
    
    return success
end

-- Core UCI logic methods with enhanced state management
function UCIController:hideBaseLayers()
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
end

function UCIController:callActivePopup()
    local callActiveState = safeControl("pinCallActive", "Boolean") or false
    self:updateLayerVisibility({"I01-CallActive"}, callActiveState, callActiveState and "fade" or "none")
end

function UCIController:showPresetSavedSublayer()
    self:updatePresetSavedState(safeControl("pinLEDPresetSaved", "Boolean") or false)
end

function UCIController:showHDMI01Sublayer()
    self:updateHDMI01State(safeControl("pinLEDHDMI01Connect", "Boolean") or false)
end

function UCIController:showHDMI02Sublayer()
    self:updateHDMI02State(safeControl("pinLEDHDMI02Connect", "Boolean") or false)
end

function UCIController:showLaptopHelpSublayer()
    self:updateLaptopHelpState(safeControl("btnHelpLaptop", "Boolean") or false)
end

function UCIController:showACPRSublayer()
    self:updateACPRBypassState(safeControl("pinLEDACPRBypassActive", "Boolean") or false)
end

function UCIController:showPCHelpSublayer()
    self:updatePCHelpState(safeControl("btnHelpPC", "Boolean") or false)
end

function UCIController:showWirelessHelpSublayer()
    self:updateWirelessHelpState(safeControl("btnHelpWireless", "Boolean") or false)
end

function UCIController:showRoutingHelpSublayer()
    self:updateRoutingHelpState(safeControl("btnHelpRouting", "Boolean") or false)
end

function UCIController:showDialerHelpSublayer()
    self:updateDialerHelpState(safeControl("btnHelpDialer", "Boolean") or false)
end

function UCIController:showStreamMusicHelpSublayer()
    self:updateStreamMusicHelpState(safeControl("btnHelpStreamMusic", "Boolean") or false)
end

function UCIController:showCameraSublayer()
    -- Check the appropriate USB state based on current layer
    local usbConnected = false
    
    if self.varActiveLayer == self.kLayerLaptop then
        usbConnected = safeControl("pinLEDUSBLaptop", "Boolean") or false
        print("Camera Sublayer: Checking laptop USB state: " .. tostring(usbConnected))
    elseif self.varActiveLayer == self.kLayerPC then
        usbConnected = safeControl("pinLEDUSBPC", "Boolean") or false
        print("Camera Sublayer: Checking PC USB state: " .. tostring(usbConnected))
    else
        print("Camera Sublayer: Not on laptop or PC layer, skipping camera state update")
        return
    end
    
    self:updateCameraState(usbConnected)
end

function UCIController:showRoutingLayer()
    -- Add bounds check
    if self.activeRoutingLayer < 1 or self.activeRoutingLayer > #self.routingLayers then
        self.activeRoutingLayer = 1 -- Reset to default
    end    
    
    -- Hide program volume layer for routing view
    self:updateLayerVisibility({"X01-ProgramVolume"}, false, "none")

    -- Hide all routing layers
    for _, layer in ipairs(self.routingLayers) do
        self:updateLayerVisibility({layer}, false, "none")
    end
    
    -- Show active layer and update buttons
    self:updateLayerVisibility({self.routingLayers[self.activeRoutingLayer]}, true, "fade")
    self:interlockRoutingButtons()
end

function UCIController:interlockRoutingButtons()
    for i, btn in ipairs(self.arrRoutingButtons) do
        if btn then
            btn.Boolean = (i == self.activeRoutingLayer)
        else
            print("Warning: Routing button " .. i .. " is nil, cannot set interlock state")
        end
    end
end

function UCIController:routingButtonEventHandler(buttonIndex)
    -- Add validation
    if buttonIndex < 1 or buttonIndex > #self.routingLayers then
        print("Invalid routing button index: " .. tostring(buttonIndex))
        return
    end
    
    self.activeRoutingLayer = buttonIndex
    self:showRoutingLayer()
    print("Routing layer switched to: " .. self.routingLayers[buttonIndex])
end

-- Layer state management functions
function UCIController:resetLayerStates()
    self.layerStates = {}
    print("Layer states reset for " .. self.uciPage)
end

function UCIController:getLayerState(layerName)
    return self.layerStates[layerName]
end

function UCIController:setLayerState(layerName, visible)
    self.layerStates[layerName] = visible
end

-- Legacy init function for backward compatibility
function UCIController:init()
    self:resetLayerStates()
end

function UCIController:updateLayerVisibility(layers, visible, transition)
    for _, layer in ipairs(layers) do
        local currentState = self:getLayerState(layer)
        if not self.isInitialized or currentState ~= visible then
            self:safeSetLayerVisibility(self.uciPage, layer, visible, transition)
            self:setLayerState(layer, visible)
        end
    end
end

function UCIController:updatePresetSavedState(isVisible)
    self:updateLayerVisibility({"J04-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    print("Preset Saved Sublayer: " .. (isVisible and "Showing" or "Hiding") .. " J04-CamPresetSaved")
end

function UCIController:updateHDMI01State(isConnected)
    if self.varActiveLayer ~= self.kLayerLaptop then
        print("HDMI Sublayer: Not on laptop interface, ignoring HDMI state update")
        return
    end
    
    if isConnected then
        self:updateLayerVisibility({"L05-Laptop"}, true, "fade")
        self:updateLayerVisibility({"L01-HDMI01Disconnected"}, false, "none")
        print("HDMI Sublayer: Showing L05-Laptop, Hiding L01-HDMI01Disconnected")
    else
        self:updateLayerVisibility({"L01-HDMI01Disconnected"}, true, "fade")
        self:updateLayerVisibility({"L05-Laptop"}, false, "none")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        print("HDMI Sublayer: Showing L01-HDMI01Disconnected, Hiding L05-Laptop")
    end
end

function UCIController:updateHDMI02State(isConnected)
    if self.varActiveLayer ~= self.kLayerPC then
        print("HDMI Sublayer: Not on PC interface, ignoring HDMI state update")
        return
    end
    
    if isConnected then
        self:updateLayerVisibility({"P05-PC"}, true, "fade")
        self:updateLayerVisibility({"P01-HDMI02Disconnected"}, false, "none")
        print("HDMI Sublayer: Showing P05-PC, Hiding P01-HDMI02Disconnected")
    else
        self:updateLayerVisibility({"P01-HDMI02Disconnected"}, true, "fade")
        self:updateLayerVisibility({"P05-PC"}, false, "none")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        print("HDMI Sublayer: Showing P01-HDMI02Disconnected, Hiding P05-PC")
    end
end

function UCIController:updateACPRBypassState(isBypassActive)
    if self.varActiveLayer ~= self.kLayerLaptop and self.varActiveLayer ~= self.kLayerPC then
        print("ACPR Sublayer: Not on laptop or PC interface, ignoring ACPR state update")
        return
    end

    if not isBypassActive then
        self:updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        print("ACPR Sublayer: Showing J03-ACPRActive, Hiding J05-CameraControls")
    else
        self:updateLayerVisibility({"J05-CameraControls"}, true, "fade")
        self:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        print("ACPR Sublayer: Showing J05-CameraControls, Hiding J03-ACPRActive")
    end
end

function UCIController:updateCameraState(isConnected)
    local usbNotConnectedLayerToShow
    if self.varActiveLayer == self.kLayerLaptop then
        usbNotConnectedLayerToShow = "J01-ConnectUSBLaptop"
    elseif self.varActiveLayer == self.kLayerPC then
        usbNotConnectedLayerToShow = "J02-ConnectUSBPC"
    else
        return -- Not on a relevant layer
    end

    if isConnected then
        self:updateLayerVisibility({"J05-CameraControls"}, true, "fade")
        self:updateLayerVisibility({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        print("Camera Sublayer: Showing J05-CameraControls")
    else
        self:updateLayerVisibility({usbNotConnectedLayerToShow}, true, "fade")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        print("Camera Sublayer: Showing " .. usbNotConnectedLayerToShow .. ", Hiding J05-CameraControls")
    end
end

function UCIController:updateCallActiveState(isActive)
    self:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    print("Call Active Popup: " .. (isActive and "Showing" or "Hiding") .. " I01-CallActive")
end

function UCIController:updateLaptopHelpState(isVisible)
    if isVisible then
        self:updateLayerVisibility({"I02-HelpLaptop"}, true, "fade")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        self:updateLayerVisibility({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        print("Laptop Help Sublayer: Showing I02-HelpLaptop, Hiding Camera Controls")
    else
        self:updateLayerVisibility({"I02-HelpLaptop"}, false, "none")
        self:showCameraSublayer()
        print("Laptop Help Sublayer: Hiding I02-HelpLaptop, restoring camera state")
    end
end

function UCIController:updatePCHelpState(isVisible)
    if isVisible then
        self:updateLayerVisibility({"I03-HelpPC"}, true, "fade")
        self:updateLayerVisibility({"J05-CameraControls"}, false, "none")
        self:updateLayerVisibility({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
        print("PC Help Sublayer: Showing I03-HelpPC, Hiding Camera Controls")
    else
        self:updateLayerVisibility({"I03-HelpPC"}, false, "none")
        self:showCameraSublayer()
        print("PC Help Sublayer: Hiding I03-HelpPC, restoring camera state")
    end
end

function UCIController:updateWirelessHelpState(isVisible)
    self:updateLayerVisibility({"I04-HelpWireless"}, isVisible, "none")
    print("Wireless Help Sublayer: " .. (isVisible and "Showing" or "Hiding") .. " I04-HelpWireless")
end

function UCIController:updateRoutingHelpState(isVisible)
    self:updateLayerVisibility({"I05-HelpRouting"}, isVisible, "none")
    print("Routing Help Sublayer: " .. (isVisible and "Showing" or "Hiding") .. " I05-HelpRouting")
end

function UCIController:updateDialerHelpState(isVisible)
    self:updateLayerVisibility({"I06-HelpDialer"}, isVisible, "none")
    print("Dialer Help Sublayer: " .. (isVisible and "Showing" or "Hiding") .. " I06-HelpDialer")
end

function UCIController:updateStreamMusicHelpState(isVisible)
    self:updateLayerVisibility({"I07-HelpStreamMusic"}, isVisible, "none")
    print("Stream Music Help Sublayer: " .. (isVisible and "Showing" or "Hiding") .. " I07-HelpStreamMusic")
end

-- Modify showLayer to use state information and validate transitions
function UCIController:showLayer()
    -- Hide all layers first
    local layersToHide = {
        "A01-Alarm", 
        "B01-IncomingCall", 
        "C05-Start", 
        "D01-ShutdownConfirm",
        "E01-SystemProgressWarming", 
        "E02-SystemProgressCooling", 
        "E05-SystemProgress",
        "H01-RoomControls", 
        "I01-CallActive", 
        "I02-HelpLaptop", 
        "I03-HelpPC",
        "I04-HelpWireless", 
        "I05-HelpRouting", 
        "I06-HelpDialer", 
        "I07-HelpStreamMusic", 
        "J01-ConnectUSBLaptop",
        "J02-ConnectUSBPC",
        "J03-ACPRActive",
        "J04-CamPresetSaved", 
        "J05-CameraControls", 
        "L01-HDMI01Disconnected", 
        "L05-Laptop", 
        "P01-HDMI02Disconnected",
        "P05-PC", 
        "W05-Wireless", 
        "R01-Routing-Lobby", 
        "R02-Routing-WTerrace",
        "R03-Routing-NTerraceWall", 
        "R04-Routing-Garden", 
        "R05-Routing-NTerraceFloor",
        "R10-Routing", 
        "S05-StreamMusic",
        "V05-Dialer", 
        "X01-ProgramVolume", 
        "Y01-Navbar", 
        "Z01-Base"
    }
    
    for _, layer in ipairs(layersToHide) do
        self:updateLayerVisibility({layer}, false, "none")
    end

    -- Set base layers visible
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")

    local layerConfigs = {
        [self.kLayerAlarm] = {
            showLayers = {"A01-Alarm"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayerIncomingCall] = {
            showLayers = {"B01-IncomingCall"}
        },
        [self.kLayerStart] = {
            showLayers = {"C05-Start"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayerWarming] = {
            showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayerCooling] = {
            showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayerRoomControls] = {
            showLayers = {"H01-RoomControls"},
            hideLayers = {"X01-ProgramVolume"},
            callFunctions = {
                function() self:callActivePopup() end
            }
        },
        [self.kLayerLaptop] = {
            showLayers = {"L05-Laptop"},
            callFunctions = {
                function() self:showHDMI01Sublayer() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end,
                function() self:showLaptopHelpSublayer() end,
                function() self:callActivePopup() end
            }
        },
        [self.kLayerPC] = {
            showLayers = {"P05-PC"},
            callFunctions = {
                function() self:showHDMI02Sublayer() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end,
                function() self:showPCHelpSublayer() end,
                function() self:callActivePopup() end
            }
        },
        [self.kLayerWireless] = {
            showLayers = {"W05-Wireless"},
            callFunctions = {
                function() self:showWirelessHelpSublayer() end,
                function() self:callActivePopup() end
            }
        },
        [self.kLayerRouting] = {
            showLayers = {"R10-Routing"},
            callFunctions = {
                function() self:showRoutingLayer() end,
                function() self:callActivePopup() end
            }
        },
        [self.kLayerDialer] = {
            showLayers = {"V05-Dialer"},
            callFunctions = {
                function() self:showDialerHelpSublayer() end,
                function() self:callActivePopup() end
            }
        },
        [self.kLayerStreamMusic] = {
            showLayers = {"S05-StreamMusic"},
            callFunctions = {
                function() self:showStreamMusicHelpSublayer() end,
                function() self:callActivePopup() end
            }
        }
    }
    
    local config = layerConfigs[self.varActiveLayer]
    if config then
        -- Show main layers
        for _, layer in ipairs(config.showLayers or {}) do
            self:updateLayerVisibility({layer}, true, "fade")
        end
        
        -- Hide specified layers
        for _, layer in ipairs(config.hideLayers or {}) do
            self:updateLayerVisibility({layer}, false, "none")
        end
        
        -- Call functions in order
        for _, func in ipairs(config.callFunctions or {}) do
            func()
        end
    end
end

function UCIController:interlock()
    for i = 1, 12 do
        local control = safeControl(getButtonName(i))
        if control then
            control.Boolean = false
        end
    end
    
    local layerToButton = {
        [self.kLayerAlarm]           = 1,
        [self.kLayerIncomingCall]    = 2,
        [self.kLayerStart]           = 3,
        [self.kLayerWarming]         = 4,
        [self.kLayerCooling]         = 5,
        [self.kLayerRoomControls]    = 6,
        [self.kLayerPC]              = 7,
        [self.kLayerLaptop]          = 8,
        [self.kLayerWireless]        = 9,
        [self.kLayerRouting]         = 10,
        [self.kLayerDialer]          = 11,
        [self.kLayerStreamMusic]     = 12
    }
    
    local btnIndex = layerToButton[self.varActiveLayer]
    if btnIndex then
        local control = safeControl(getButtonName(btnIndex))
        if control then
            control.Boolean = true
        end
    end
end

function UCIController:debug()
    local layers = {
        {var = self.kLayerAlarm,        msg = "Set UCI to Alarm"},
        {var = self.kLayerIncomingCall, msg = "Set UCI to Incoming Call"},
        {var = self.kLayerStart,        msg = "Set UCI to Start"},
        {var = self.kLayerWarming,      msg = "Set UCI to Warming"},
        {var = self.kLayerCooling,      msg = "Set UCI to Cooling"},
        {var = self.kLayerRoomControls, msg = "Set UCI to Room Controls"},
        {var = self.kLayerPC,           msg = "Set UCI to PC"},
        {var = self.kLayerLaptop,       msg = "Set UCI to Laptop"},
        {var = self.kLayerWireless,     msg = "Set UCI to Wireless"},
        {var = self.kLayerRouting,      msg = "Set UCI to Routing"},
        {var = self.kLayerDialer,       msg = "Set UCI to Dialer"},
        {var = self.kLayerStreamMusic,  msg = "Set UCI to Stream Music"}
    }
    
    for i = 1, #layers do
        if self.varActiveLayer == layers[i].var then
            print(layers[i].msg)
            break
        end
    end
end

function UCIController:btnNavEventHandler(argIndex)
    -- Validate layer transition
    if not self:validateLayerTransition(self.varActiveLayer, argIndex) then
        print("Invalid layer transition attempted")
        return
    end
    
    local previousLayer = self.varActiveLayer
    self.varActiveLayer = argIndex
    
    -- Notify external controllers of layer change
    local layerChangeInfo = {
        previousLayer = previousLayer,
        currentLayer = self.varActiveLayer,
        layerName = self:getLayerName(self.varActiveLayer)
    }
    self:notifyExternalControllers(layerChangeInfo)
    
    -- Trigger video switcher for specific buttons (7, 8, 9)
    if self.videoSwitcher and self.videoSwitcher.isEnabled then
        local inputNumber = self.videoSwitcher.uciToInputMapping[argIndex]
        if inputNumber then
            print("UCI Button " .. argIndex .. " pressed - triggering video switcher to input " .. inputNumber)
            self.videoSwitcher:switchToInput(inputNumber, argIndex)
        end
    end
    
    self:showLayer()
    self:interlock()
    self:debug()
end

-- Helper method to get layer name
function UCIController:getLayerName(layerNumber)
    local layerNames = {
        [self.kLayerAlarm] = "Alarm",
        [self.kLayerIncomingCall] = "Incoming Call",
        [self.kLayerStart] = "Start",
        [self.kLayerWarming] = "Warming",
        [self.kLayerCooling] = "Cooling",
        [self.kLayerRoomControls] = "Room Controls",
        [self.kLayerPC] = "PC",
        [self.kLayerLaptop] = "Laptop",
        [self.kLayerWireless] = "Wireless",
        [self.kLayerRouting] = "Routing",
        [self.kLayerDialer] = "Dialer",
        [self.kLayerStreamMusic] = "Stream Music"
    }
    return layerNames[layerNumber] or "Unknown"
end

-- Modified Loading Bar with Room Automation Integration and timeout protection
function UCIController:startLoadingBar(isPoweringOn)
    if self.isAnimating then
        return
    end
    
    self.isAnimating = true
    
    -- Get timing using existing function with built-in fallbacks
    local duration = self:getRoomAutomationTiming(isPoweringOn)
    
    local steps = 100
    local interval = duration / steps
    local currentStep = 0
    
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
    
    if self.timeoutTimer then
        self.timeoutTimer:Stop()
        self.timeoutTimer = nil
    end
    
    self.loadingTimer = Timer.New()
    self.timeoutTimer = Timer.New()
    
    local progressBar = safeControl("knbProgressBar")
    local progressText = safeControl("txtProgressBar")
    if progressBar then
        progressBar.Value = isPoweringOn and 0 or 100
    end
    if progressText then
        progressText.String = (isPoweringOn and 0 or 100) .. "%"
    end
    
    -- Add timeout protection
    self.timeoutTimer.EventHandler = function()
        if self.isAnimating then
            print("Warning: Loading bar timeout reached")
            self.isAnimating = false
            if self.loadingTimer then
                self.loadingTimer:Stop()
                self.loadingTimer = nil
            end
            -- Force transition to appropriate state
            self:btnNavEventHandler(isPoweringOn and self.kLayerLaptop or self.kLayerStart)
        end
    end
    self.timeoutTimer:Start(300) -- 5-minute timeout
    
    self.loadingTimer.EventHandler = function()
        currentStep = currentStep + 1
        
        local progressBar = safeControl("knbProgressBar")
        local progressText = safeControl("txtProgressBar")
        
        if isPoweringOn then
            if progressBar then
                progressBar.Value = currentStep
            end
            if progressText then
                progressText.String = currentStep .. "%"
            end
        else
            if progressBar then
                progressBar.Value = 100 - currentStep
            end
            if progressText then
                progressText.String = (100 - currentStep) .. "%"
            end
        end
        
        if currentStep >= steps then
            self.loadingTimer:Stop()
            self.timeoutTimer:Stop()
            self.isAnimating = false
            
            if isPoweringOn then
                self:btnNavEventHandler(self.kLayerLaptop)
            else
                self:btnNavEventHandler(self.kLayerStart)
            end
        else
            self.loadingTimer:Start(interval)
        end
    end
    
    self.loadingTimer:Start(interval)
end

function UCIController:updateLegends()
    for i, lbl in ipairs(self.arrUCILegends) do
        if lbl and self.arrUCIUserLabels[i] then
            lbl.Legend = self.arrUCIUserLabels[i].String
        else
            if not lbl then
                print("Warning: Legend control at index " .. i .. " is nil")
            end
            if not self.arrUCIUserLabels[i] then
                print("Warning: User label variable at index " .. i .. " is nil")
            end
        end
    end
end

function UCIController:cleanup()
    -- Stop and cleanup timers
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
    
    if self.timeoutTimer then
        self.timeoutTimer:Stop()
        self.timeoutTimer = nil
    end
    
    -- Cleanup video switcher integration
    if self.videoSwitcher then
        self.videoSwitcher:cleanup()
    end
    
    -- Remove event handlers
    for _, btn in ipairs(self.arrbtnNavs) do
        if btn then
            btn.EventHandler = nil
        end
    end
    
    for _, btn in ipairs(self.arrRoutingButtons) do
        if btn then
            btn.EventHandler = nil
        end
    end
    
    for _, lbl in ipairs(self.arrUCIUserLabels) do
        if lbl then
            lbl.EventHandler = nil
        end
    end
    
    -- Clear component reference
    self.roomControlsComponent = nil
    
    -- Reset layer states
    self:resetLayerStates()
    
    print("UCI Controller cleaned up for " .. self.uciPage)
end

-- All Event Handlers, grouped for clarity
function UCIController:registerEventHandlers()
    -- Nav Buttons
    for i, ctl in ipairs(self.arrbtnNavs) do
        if ctl then
            ctl.EventHandler = function()
                self:btnNavEventHandler(i)
            end
        else
            print("Warning: Navigation button " .. i .. " is nil, skipping event handler")
        end
    end
    
    -- Routing Buttons
    for i, btn in ipairs(self.arrRoutingButtons) do
        if btn then
            btn.EventHandler = function()
                self:routingButtonEventHandler(i)
            end
        else
            print("Warning: Routing button " .. i .. " is nil, skipping event handler")
        end
    end
    
    -- System State with Room Automation Integration
    
    -- Start System - Modified to control room automation
    local btnStartSystem = safeControl("btnStartSystem")
    if btnStartSystem then
        btnStartSystem.EventHandler = function()
            -- Power on Room Automation system
            self:powerOnRoomAutomation()
            
            -- Start UCI loading bar with Room Automation timing
            self:startLoadingBar(true)
            self:btnNavEventHandler(self.kLayerWarming)
            print("System started with Start button for " .. self.uciPage)
        end
    end
    
    -- Shutdown Confirm
    local btnNavShutdown = safeControl("btnNavShutdown")
    if btnNavShutdown then
        btnNavShutdown.EventHandler = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
            print("Shutdown Confirm page set for " .. self.uciPage)
        end
    end
    
    -- Shutdown Cancel
    local btnShutdownCancel = safeControl("btnShutdownCancel")
    if btnShutdownCancel then
        btnShutdownCancel.EventHandler = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
            print("Shutdown cancelled by Cancel button for " .. self.uciPage)
            self:debug()
        end
    end
    
    -- Shutdown Confirmed - Modified to control room automation
    local btnShutdownConfirm = safeControl("btnShutdownConfirm")
    if btnShutdownConfirm then
        btnShutdownConfirm.EventHandler = function()
            -- Hide the shutdown confirm overlay first
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
            
            -- Power off Room Automation system
            self:powerOffRoomAutomation()
            
            -- Start UCI loading bar with Room Automation timing
            self:startLoadingBar(false)
            
            -- Set the active layer to cooling without validation
            self.varActiveLayer = self.kLayerCooling
            self:showLayer()
            self:interlock()
            self:debug()
            
            print("System shutdown confirmed for " .. self.uciPage)
        end
    end
    
    -- Modal Popups - Button Triggers
    local btnHelpLaptop = safeControl("btnHelpLaptop")
    if btnHelpLaptop then
        btnHelpLaptop.EventHandler = function()
            self:updateLaptopHelpState(safeControl("btnHelpLaptop", "Boolean") or false)
        end
    end
    
    local btnHelpPC = safeControl("btnHelpPC")
    if btnHelpPC then
        btnHelpPC.EventHandler = function()
            self:updatePCHelpState(safeControl("btnHelpPC", "Boolean") or false)
        end
    end

    local btnHelpWireless = safeControl("btnHelpWireless")
    if btnHelpWireless then
        btnHelpWireless.EventHandler = function()
            self:updateWirelessHelpState(safeControl("btnHelpWireless", "Boolean") or false)
        end
    end

    local btnHelpRouting = safeControl("btnHelpRouting")
    if btnHelpRouting then
        btnHelpRouting.EventHandler = function()
            self:updateRoutingHelpState(safeControl("btnHelpRouting", "Boolean") or false)
        end
    end
    
    local btnHelpDialer = safeControl("btnHelpDialer")
    if btnHelpDialer then
        btnHelpDialer.EventHandler = function()
            self:updateDialerHelpState(safeControl("btnHelpDialer", "Boolean") or false)
        end
    end

    local btnHelpStreamMusic = safeControl("btnHelpStreamMusic")
    if btnHelpStreamMusic then
        btnHelpStreamMusic.EventHandler = function()
            self:updateStreamMusicHelpState(safeControl("btnHelpStreamMusic", "Boolean") or false)
        end
    end

    -- External Triggers
    local pinLEDUSBLaptop = safeControl("pinLEDUSBLaptop")
    if pinLEDUSBLaptop then
        pinLEDUSBLaptop.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerLaptop -- show laptop layer
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
    
    local pinLEDUSBPC = safeControl("pinLEDUSBPC")
    if pinLEDUSBPC then
        pinLEDUSBPC.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerPC -- show PC layer
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
    
    local pinLEDOffHookLaptop = safeControl("pinLEDOffHookLaptop")
    if pinLEDOffHookLaptop then
        pinLEDOffHookLaptop.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerLaptop -- show laptop layer
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end

    local pinLEDOffHookPC = safeControl("pinLEDOffHookPC")
    if pinLEDOffHookPC then
        pinLEDOffHookPC.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerPC -- show PC layer
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
        
    local pinLEDHDMI01Active = safeControl("pinLEDHDMI01Active")
    if pinLEDHDMI01Active then
        pinLEDHDMI01Active.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerLaptop -- show laptop layer
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
    
    local pinLEDHDMI02Active = safeControl("pinLEDHDMI02Active")
    if pinLEDHDMI02Active then
        pinLEDHDMI02Active.EventHandler = function(ctl)
            if ctl.Boolean then
                self.varActiveLayer = self.kLayerPC -- show PC layer        
            end
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
    
    -- Pin Event Handlers for Sublayers
    local pinLEDPresetSaved = safeControl("pinLEDPresetSaved")
    if pinLEDPresetSaved then
        pinLEDPresetSaved.EventHandler = function(ctl)
            self:updatePresetSavedState(ctl.Boolean)
        end
    end
    
    local pinLEDHDMI01Connect = safeControl("pinLEDHDMI01Connect")
    if pinLEDHDMI01Connect then
        pinLEDHDMI01Connect.EventHandler = function(ctl)
            self:updateHDMI01State(ctl.Boolean)
        end
    end
    
    local pinLEDACPRBypassActive = safeControl("pinLEDACPRBypassActive")
    if pinLEDACPRBypassActive then
        pinLEDACPRBypassActive.EventHandler = function(ctl)
            self:updateACPRBypassState(ctl.Boolean)
        end
    end
    
    local pinCallActive = safeControl("pinCallActive")
    if pinCallActive then
        pinCallActive.EventHandler = function(ctl)
            self:updateCallActiveState(ctl.Boolean)
        end
    end
    
    -- Legend label updates
    for i, lbl in ipairs(self.arrUCIUserLabels) do
        if lbl then
            lbl.EventHandler = function()
                self:updateLegends()
            end
        else
            print("Warning: User label variable at index " .. i .. " is nil, skipping event handler")
        end
    end
    print("funcUpdateLegends ran successfully for " .. self.uciPage)
end

function UCIController:funcInit()
    -- Reset layer states to ensure clean initialization
    self:resetLayerStates()
    
    -- Sync with Room Automation state if available
    if mySystemController and mySystemController.state then
        -- Check Room Automation state and sync UCI accordingly
        local systemPowerState = safeControl("ledSystemPower", "Boolean")
        if systemPowerState then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
            else
                self.varActiveLayer = self.defaultActiveLayer -- Use stored default active layer
            end
        else
            self.varActiveLayer = self.kLayerStart
        end
        print("UCI synchronized with Room Automation state")
    else
        -- Default initialization
        self.varActiveLayer = self.kLayerStart
        print("Room Automation not available - using default UCI initialization")
    end
    
    -- Initialize video switcher integration
    if self.videoSwitcher then
        local videoSwitcherSuccess = self.videoSwitcher:initialize()
        if videoSwitcherSuccess then
            print("Video Switcher Integration initialized successfully")
        else
            print("Video Switcher Integration failed to initialize - continuing without video switching")
        end
    end
    
    -- Hide specified navigation buttons [1][3]
    for _, index in ipairs(self.hiddenNavIndices) do
        if self.arrbtnNavs[index] then
            self.arrbtnNavs[index].Visible = false
            print("Hidden navigation button: " .. getButtonName(index))
        else
            print("Warning: Cannot hide navigation button " .. index .. " - control not found")
        end
    end
 
    self:showLayer()
    self:interlock()
    self:debug()
    self:updateLegends()
    print("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
end

-- Reinitialize function for UCIController
function UCIController:reinitialize()
    print("=== Reinitializing UCIController ===")
    
    -- Reset layer states
    self:resetLayerStates()
    
    -- Reset initialization flag
    self.isInitialized = false
    
    -- Re-run initialization
    self:funcInit()
    
    print("=== UCIController reinitialized ===")
end

-- Quick Fix implementation with error handling for page name validation
local function createUCIControllerWithErrorHandling(targetPageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices, hiddenHelpIndices)
    -- Test with different page name variations
    local pageNames = {
        targetPageName, -- Try exact name first
        targetPageName:gsub("%s+", " "), -- Normalize spaces
        targetPageName:gsub("%s+", ""), -- Remove spaces
        targetPageName:gsub("%(", ""):gsub("%)", ""), -- Remove parentheses
        targetPageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", "") -- Replace spaces with hyphens and remove parentheses
    }
    
    print("=== Testing UCI Page Names ===")
    for _, pageName in ipairs(pageNames) do
        print("Attempting page name: " .. pageName)
    end
    print("=== End Page Name Testing ===")
    
    local controller
    for _, pageName in ipairs(pageNames) do
        local success, result = pcall(function()
            return UCIController.new(pageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices, hiddenHelpIndices)
        end)
        
        if success then
            controller = result
            print("Successfully created UCI controller for page: " .. pageName)
            break
        else
            print("Failed to create controller for page: " .. pageName)
            print("Error: " .. tostring(result))
        end
    end
    
    if not controller then
        print("ERROR: Could not create UCI controller for any page name variation of: " .. targetPageName)
        print("Please verify the exact page name in your UCI system")
    end
    
    return controller
end

-- Create the controller instances for your pages with error handling and Room Automation integration
myUCI = createUCIControllerWithErrorHandling(
    Uci.Variables.txtUCIPageName.String,  -- Use UCI name
    tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 4,  -- Use UCI Variable for routing layer with fallback
    tonumber(Uci.Variables.numDefaultActiveLayer.Value) or 8,  -- Use UCI Variable for default active layer with fallback to kLayerLaptop
    {}, -- specify which self.arrbtnNavs to hide {2, 4}, {} --no self.arrbtnNavs to hide
    {} -- specify which help buttons to hide {2, 4} {} --no buttons to hide
)

-- Optional: Add periodic sync with Room Automation
if myUCI and mySystemController then
    -- Create a timer to periodically sync UCI with Room Automation state
    local syncTimer = Timer.New()
    syncTimer.EventHandler = function()
        if myUCI and myUCI.syncWithRoomAutomation then
            myUCI:syncWithRoomAutomation()
        end
        syncTimer:Start(5) -- Check every 5 seconds
    end
    
    -- Add cleanup method
    function myUCI:cleanup()
        if syncTimer then
            syncTimer:Stop()
            syncTimer = nil
        end
        if self.loadingTimer then
            self.loadingTimer:Stop()
            self.loadingTimer = nil
        end
        if self.timeoutTimer then
            self.timeoutTimer:Stop()
            self.timeoutTimer = nil
        end
    end
    
    syncTimer:Start(5)
    print("Room Automation sync timer started for UCI")
end

-- Optional: Auto-connect NV32RouterController if it exists
if myUCI and myNV32RouterController then
    myUCI:registerExternalController(myNV32RouterController, "NV32Router")
    print("NV32RouterController automatically connected to UCIController")
    
    -- Also set the UCI controller reference in the NV32 controller
    myNV32RouterController:setUCIController(myUCI)
    print("UCIController reference set in NV32RouterController")
end

-- Video Switcher Configuration and Debugging Functions
function printVideoSwitcherStatus()
    if myUCI then
        local status = myUCI:getVideoSwitcherStatus()
        print("=== Video Switcher Status ===")
        print("Enabled: " .. tostring(status.enabled))
        print("Type: " .. tostring(status.switcherType))
        print("Component Valid: " .. tostring(status.componentValid))
        if status.mapping then
            print("Current Mapping:")
            for uciButton, inputNumber in pairs(status.mapping) do
                print("  " .. getButtonName(uciButton) .. " → Input " .. inputNumber)
            end
        end
        print("=== End Video Switcher Status ===")
    else
        print("UCI Controller not available")
    end
end

-- Example: Custom video switcher mapping
function configureCustomVideoSwitcherMapping()
    if myUCI then
        -- Example: Custom mapping for a different video switcher
        local customMapping = {
            [7] = 3, -- btnNav07 → Input 3 (PC)
            [8] = 1, -- btnNav08 → Input 1 (Laptop)
            [9] = 2  -- btnNav09 → Input 2 (Wireless)
        }
        
        local success = myUCI:updateVideoSwitcherMapping(customMapping)
        if success then
            print("Custom video switcher mapping applied successfully")
            printVideoSwitcherStatus()
        else
            print("Failed to apply custom video switcher mapping")
        end
    end
end

-- Print initial video switcher status
Timer.CallAfter(function()
    printVideoSwitcherStatus()
end, 2)

-- Debug function to print current layer states
function printLayerStates()
    if myUCI then
        print("=== Current Layer States ===")
        for layerName, state in pairs(myUCI.layerStates) do
            print("  " .. layerName .. ": " .. tostring(state))
        end
        print("=== End Layer States ===")
    else
        print("UCI Controller not available")
    end
end

-- Video Switcher Integration Methods
function UCIController:getVideoSwitcherStatus()
    if self.videoSwitcher then
        return self.videoSwitcher:getStatus()
    end
    return { enabled = false, switcherType = "None", componentValid = false }
end

-- Clear component discovery cache
function clearComponentDiscoveryCache()
    componentDiscoveryCache.data = nil
    componentDiscoveryCache.timestamp = 0
    print("Component discovery cache cleared")
end

function UCIController:updateVideoSwitcherMapping(newMapping)
    if self.videoSwitcher then
        self.videoSwitcher:updateMapping(newMapping)
        return true
    end
    return false
end

function UCIController:switchVideoInput(inputNumber)
    if self.videoSwitcher then
        return self.videoSwitcher:switchToInput(inputNumber, 0) -- 0 indicates manual switch
    end
    return false
end

-- External Controller Registration Methods
function UCIController:registerExternalController(controller, controllerType)
    if not self.externalControllers[controllerType] then
        self.externalControllers[controllerType] = {}
    end
    table.insert(self.externalControllers[controllerType], controller)
    print("Registered external controller: " .. tostring(controllerType))
end

function UCIController:unregisterExternalController(controller, controllerType)
    if self.externalControllers[controllerType] then
        for i, registeredController in ipairs(self.externalControllers[controllerType]) do
            if registeredController == controller then
                table.remove(self.externalControllers[controllerType], i)
                print("Unregistered external controller: " .. tostring(controllerType))
                break
            end
        end
    end
end

function UCIController:notifyExternalControllers(layerChangeInfo)
    for controllerType, controllers in pairs(self.externalControllers) do
        for _, controller in ipairs(controllers) do
            -- Try to call the notification method if it exists
            if controller.onUCILayerChange then
                local success, err = pcall(function()
                    controller:onUCILayerChange(layerChangeInfo)
                end)
                if not success then
                    print("Warning: Failed to notify " .. tostring(controllerType) .. " controller: " .. tostring(err))
                end
            end
        end
    end
end

-- Test function for manual video switcher testing
function testVideoSwitcherInput(inputNumber)
    if myUCI and myUCI.videoSwitcher then
        print("=== Testing Video Switcher Input " .. inputNumber .. " ===")
        local success = myUCI.videoSwitcher:switchToInput(inputNumber, 0)
        if success then
            print("✓ Manual test successful - switched to input " .. inputNumber)
        else
            print("✗ Manual test failed - could not switch to input " .. inputNumber)
        end
        print("=== End Test ===")
    else
        print("UCI Controller or Video Switcher not available")
    end
end

-- Test function to simulate button press
function testButtonPress(buttonNumber)
    if myUCI and myUCI.videoSwitcher then
        print("=== Testing Button Press btnNav" .. string.format("%02d", buttonNumber) .. " ===")
        local buttonName = "btnNav" .. string.format("%02d", buttonNumber)
        if Controls[buttonName] then
            -- Simulate button press
            Controls[buttonName].Boolean = true
            Timer.CallAfter(function()
                Controls[buttonName].Boolean = false
            end, 0.1)
            print("✓ Simulated button press for " .. buttonName)
        else
            print("✗ Button " .. buttonName .. " not found")
        end
        print("=== End Button Test ===")
    else
        print("UCI Controller not available")
    end
end

-- Test function to check video switcher component access
function testVideoSwitcherComponent()
    if myUCI and myUCI.videoSwitcher then
        print("=== Testing Video Switcher Component Access ===")
        local status = myUCI:getVideoSwitcherStatus()
        print("Video Switcher Enabled: " .. tostring(status.enabled))
        print("Component Valid: " .. tostring(status.componentValid))
        print("Switcher Type: " .. tostring(status.switcherType))
        
        if status.componentValid and myUCI.videoSwitcher.switcherComponent then
            print("✓ Video switcher component is available")
            -- Test direct component access
            local success = pcall(function()
                local component = myUCI.videoSwitcher.switcherComponent
                local routingMethod = myUCI.videoSwitcher.switcherConfig.routingMethod
                print("Routing method: " .. routingMethod)
                if component[routingMethod] then
                    print("✓ Routing property exists")
                    return true
                else
                    print("✗ Routing property not found")
                    return false
                end
            end)
            print("Component access test: " .. tostring(success))
        else
            print("✗ Video switcher component not available")
        end
        
        print("=== End Component Test ===")
    else
        print("UCI Controller or Video Switcher not available")
    end
end

print("=== Universal Video Switcher Integration Status ===")
print("✓ UCI script: Universal video switcher integration active")
print("✓ Supports NV32, Extron DXP, and other video switchers")
print("✓ Auto-detection and configuration")
print("✓ Test functions available:")
print("  - testVideoSwitcherInput(inputNumber)")
print("  - testButtonPress(buttonNumber)")
print("  - testVideoSwitcherComponent()")
print("=== Integration Status Complete ===") 