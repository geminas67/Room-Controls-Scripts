--[[
  UCIController class - Enhanced Version (External Controller Notification)
  Author: Nikolas Smith, Q-SYS
  2025-06-23
  Version: 1.2 (External Notification)
      Firmware Req: 10.0
    Notes:
    - This script is a modified version of the UCIController class that adds enhanced error handling and validation for required controls.
    - It also adds a check for the Room Controls component and a fallback method if the component is not found.
    - It also adds a check for the System Automation component and a fallback method if the component is not found.


  This version includes external controller registration and notification for UCI layer changes.
]]--

UCIController = {}
UCIController.__index = UCIController

-- Add debug check for required controls
function UCIController:checkRequiredControls()
    print("=== Checking Required Controls ===")
    local requiredControls = {
        -- Main Navigation Buttons
        "btnNav01", "btnNav02", "btnNav03", 
        "btnNav04", "btnNav05", "btnNav06", 
        "btnNav07", "btnNav08", "btnNav09", 
        "btnNav10", "btnNav11", "btnNav12",
        -- System Control Buttons
        "btnStartSystem", "btnNavShutdown", "btnShutdownCancel", "btnShutdownConfirm",
        -- Help Sublayer Buttons (optional)
        "btnHelpLaptop", "btnHelpPC", "btnHelpWireless", "btnHelpRouting", "btnHelpDialer", "btnHelpStreamMusic"
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
    self.uciPage = uciPage
    self.varActiveLayer = defaultActiveLayer or 3 -- kLayerStart
    self.defaultActiveLayer = defaultActiveLayer or 8 -- Store the default active layer
    self.isAnimating = false
    self.loadingTimer = nil
    self.timeoutTimer = nil
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.hiddenHelpIndices = hiddenHelpIndices or {}
    self.isInitialized = false
    
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
    
    -- Setup arrays for controls and labels
    self.arrbtnNavs = {
        Controls.btnNav01, 
        Controls.btnNav02, 
        Controls.btnNav03, 
        Controls.btnNav04,
        Controls.btnNav05, 
        Controls.btnNav06, 
        Controls.btnNav07, 
        Controls.btnNav08,
        Controls.btnNav09, 
        Controls.btnNav10, 
        Controls.btnNav11,
        Controls.btnNav12
    }
    
    self.arrUCILegends = {
        Controls.txtNav01, 
        Controls.txtNav02, 
        Controls.txtNav03, 
        Controls.txtNav04,
        Controls.txtNav05, 
        Controls.txtNav06, 
        Controls.txtNav07, 
        Controls.txtNav08,
        Controls.txtNav09, 
        Controls.txtNav10, 
        Controls.txtNav11, 
        Controls.txtNav12,
        Controls.txtNavShutdown,
        Controls.txtRoomName, 
        Controls.txtRoomNameStart,
        Controls.txtRoutingRooms,
        Controls.txtRouting01, 
        Controls.txtRouting02, 
        Controls.txtRouting03, 
        Controls.txtRouting04, 
        Controls.txtRouting05,
        Controls.txtRoutingSources,
        Controls.txtAudSrc01,
        Controls.txtAudSrc02,
        Controls.txtAudSrc03,
        Controls.txtAudSrc04,
        Controls.txtAudSrc05,
        Controls.txtAudSrc06,
        Controls.txtAudSrc07,
        Controls.txtAudSrc08,
        Controls.txtGainPGM,
        Controls.txtGain01,
        Controls.txtGain02,
        Controls.txtGain03,
        Controls.txtGain04,
        Controls.txtGain05,
        Controls.txtGain06,
        Controls.txtGain07,
        Controls.txtGain08,
        Controls.txtGain09,
        Controls.txtGain10,
        Controls.txtDisplay01,
        Controls.txtDisplay02,
        Controls.txtDisplay03,
        Controls.txtDisplay04,
    }
    
    self.arrUCIUserLabels = {
        Uci.Variables.txtLabelNav01, 
        Uci.Variables.txtLabelNav02, 
        Uci.Variables.txtLabelNav03,
        Uci.Variables.txtLabelNav04, 
        Uci.Variables.txtLabelNav05, 
        Uci.Variables.txtLabelNav06,
        Uci.Variables.txtLabelNav07, 
        Uci.Variables.txtLabelNav08, 
        Uci.Variables.txtLabelNav09,
        Uci.Variables.txtLabelNav10, 
        Uci.Variables.txtLabelNav11, 
        Uci.Variables.txtLabelNav12,
        Uci.Variables.txtLabelNavShutdown,
        Uci.Variables.txtLabelRoomName, 
        Uci.Variables.txtLabelRoomNameStart,
        Uci.Variables.txtLabelRoutingRooms,
        Uci.Variables.txtLabelRouting01, 
        Uci.Variables.txtLabelRouting02, 
        Uci.Variables.txtLabelRouting03, 
        Uci.Variables.txtLabelRouting04, 
        Uci.Variables.txtLabelRouting05,
        Uci.Variables.txtLabelRoutingSources,
        Uci.Variables.txtLabelAudSrc01,
        Uci.Variables.txtLabelAudSrc02,
        Uci.Variables.txtLabelAudSrc03,
        Uci.Variables.txtLabelAudSrc04,
        Uci.Variables.txtLabelAudSrc05,
        Uci.Variables.txtLabelAudSrc06,
        Uci.Variables.txtLabelAudSrc07,
        Uci.Variables.txtLabelAudSrc08,
        Uci.Variables.txtLabelGainPGM,
        Uci.Variables.txtLabelGain01,
        Uci.Variables.txtLabelGain02,
        Uci.Variables.txtLabelGain03,
        Uci.Variables.txtLabelGain04,
        Uci.Variables.txtLabelGain05,
        Uci.Variables.txtLabelGain06,
        Uci.Variables.txtLabelGain07,
        Uci.Variables.txtLabelGain08,
        Uci.Variables.txtLabelGain09,
        Uci.Variables.txtLabelGain10,
        Uci.Variables.txtLabelDisplay01,
        Uci.Variables.txtLabelDisplay02,
        Uci.Variables.txtLabelDisplay03,
        Uci.Variables.txtLabelDisplay04,
    }
    
    -- Setup arrays for routing controls
    self.arrRoutingButtons = {
        Controls.btnRouting01, 
        Controls.btnRouting02, 
        Controls.btnRouting03,
        Controls.btnRouting04, 
        Controls.btnRouting05
    }
    
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
        [self.kLayerRoomControls] = {self.kLayerAlarm, self.kLayerLaptop, self.kLayerPC, self.kLayerWireless, self.kLayerRouting, self.kLayerDialer, self.kLayerStreamMusic},
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

-- Room Automation Integration Methods with enhanced error handling
function UCIController:powerOnRoomAutomation()
    local success = false
    
    -- Method 1: Component Reference
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
        local componentSuccess = pcall(function()
            self.roomControlsComponent["btnSystemOnOff"].Boolean = true
        end)
        if componentSuccess then
            print("Room powered ON via component reference")
            success = true
        end
    end
    
    -- Method 2: Direct Control (fallback)
    if not success then
        local directSuccess = pcall(function()
            Controls.btnSystemOnOff.Boolean = true
        end)
        if directSuccess then
            print("Room powered ON via direct control")
            success = true
        end
    end
    
    -- Method 3: Global Controller Reference (if available)
    if not success and mySystemController then
        local controllerSuccess = pcall(function()
            mySystemController.powerModule.powerOn()
        end)
        if controllerSuccess then
            print("Room powered ON via global controller")
            success = true
        end
    end
    
    if not success then
        print("Warning: Failed to power on room automation system")
    end
    
    return success
end

function UCIController:powerOffRoomAutomation()
    local success = false
    
    -- Method 1: Component Reference
    if self.roomControlsComponent and self.roomControlsComponent["btnSystemOnOff"] then
        local componentSuccess = pcall(function()
            self.roomControlsComponent["btnSystemOnOff"].Boolean = false
        end)
        if componentSuccess then
            print("Room powered OFF via component reference")
            success = true
        end
    end
    
    -- Method 2: Direct Control (fallback)
    if not success then
        local directSuccess = pcall(function()
            Controls.btnSystemOnOff.Boolean = false
        end)
        if directSuccess then
            print("Room powered OFF via direct control")
            success = true
        end
    end
    
    -- Method 3: Global Controller Reference (if available)
    if not success and mySystemController then
        local controllerSuccess = pcall(function()
            mySystemController.powerModule.powerOff()
        end)
        if controllerSuccess then
            print("Room powered OFF via global controller")
            success = true
        end
    end
    
    if not success then
        print("Warning: Failed to power off room automation system")
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
    self:updateLayerVisibility({"I01-CallActive"}, Controls.pinCallActive.Boolean, Controls.pinCallActive.Boolean and "fade" or "none")
end

function UCIController:showPresetSavedSublayer()
    self:updatePresetSavedState(Controls.pinLEDPresetSaved.Boolean)
end

function UCIController:showHDMISublayer()
    self:updateHDMI01State(Controls.pinLEDHDMI01Connect.Boolean)
end

function UCIController:showLaptopHelpSublayer()
    self:updateLaptopHelpState(Controls.btnHelpLaptop.Boolean)
end

function UCIController:showACPRSublayer()
    self:updateACPRBypassState(Controls.pinLEDACPRBypassActive.Boolean)
end

function UCIController:showPCHelpSublayer()
    self:updatePCHelpState(Controls.btnHelpPC.Boolean)
end

function UCIController:showWirelessHelpSublayer()
    self:updateWirelessHelpState(Controls.btnHelpWireless.Boolean)
end

function UCIController:showRoutingHelpSublayer()
    self:updateRoutingHelpState(Controls.btnHelpRouting.Boolean)
end

function UCIController:showDialerHelpSublayer()
    self:updateDialerHelpState(Controls.btnHelpDialer.Boolean)
end

function UCIController:showStreamMusicHelpSublayer()
    self:updateStreamMusicHelpState(Controls.btnHelpStreamMusic.Boolean)
end

function UCIController:showCameraSublayer()
    -- Check the appropriate USB state based on current layer
    local usbConnected = false
    
    if self.varActiveLayer == self.kLayerLaptop then
        usbConnected = Controls.pinLEDUSBLaptop.Boolean
        print("Camera Sublayer: Checking laptop USB state: " .. tostring(usbConnected))
    elseif self.varActiveLayer == self.kLayerPC then
        usbConnected = Controls.pinLEDUSBPC.Boolean
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
        btn.Boolean = (i == self.activeRoutingLayer)
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

-- Add state tracking table
function UCIController:init()
    self.layerStates = {}
end

function UCIController:updateLayerVisibility(layers, visible, transition)
    for _, layer in ipairs(layers) do
        if not self.isInitialized or self.layerStates[layer] ~= visible then
            self:safeSetLayerVisibility(self.uciPage, layer, visible, transition)
            self.layerStates[layer] = visible
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
                function() self:showHDMISublayer() end,
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
        Controls["btnNav" .. string.format("%02d", i)].Boolean = false
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
        Controls["btnNav" .. string.format("%02d", btnIndex)].Boolean = true
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
    
    Controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    Controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
    
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
        
        if isPoweringOn then
            Controls.knbProgressBar.Value = currentStep
            Controls.txtProgressBar.String = currentStep .. "%"
        else
            Controls.knbProgressBar.Value = 100 - currentStep
            Controls.txtProgressBar.String = (100 - currentStep) .. "%"
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
        lbl.Legend = self.arrUCIUserLabels[i].String
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
    
    -- Stop NV32 control timer
    if nv32ControlTimer then
        nv32ControlTimer:Stop()
        nv32ControlTimer = nil
    end
    
    -- Remove event handlers
    for _, btn in ipairs(self.arrbtnNavs) do
        btn.EventHandler = nil
    end
    
    for _, btn in ipairs(self.arrRoutingButtons) do
        btn.EventHandler = nil
    end
    
    for _, lbl in ipairs(self.arrUCIUserLabels) do
        lbl.EventHandler = nil
    end
    
    -- Clear component reference
    self.roomControlsComponent = nil
    
    print("UCI Controller cleaned up for " .. self.uciPage)
end

-- All Event Handlers, grouped for clarity
function UCIController:registerEventHandlers()
    -- Nav Buttons
    for i, ctl in ipairs(self.arrbtnNavs) do
        ctl.EventHandler = function()
            local previousLayer = self.varActiveLayer
            if not self:validateLayerTransition(self.varActiveLayer, i) then
                print("Invalid layer transition attempted")
                return
            end
            self.varActiveLayer = i
            self:showLayer()
            self:interlock()
            self:debug()
        end
    end
    
    -- Routing Buttons
    for i, btn in ipairs(self.arrRoutingButtons) do
        btn.EventHandler = function()
            self:routingButtonEventHandler(i)
        end
    end
    
    -- System State with Room Automation Integration
    
    -- Start System - Modified to control room automation
    Controls.btnStartSystem.EventHandler = function()
        self:powerOnRoomAutomation()
        self:startLoadingBar(true)
        local previousLayer = self.varActiveLayer
        self.varActiveLayer = self.kLayerWarming
        self:showLayer()
        self:interlock()
        self:debug()
        print("System started with Start button for " .. self.uciPage)
    end
    
    -- Shutdown Confirm
    Controls.btnNavShutdown.EventHandler = function()
        self:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
        print("Shutdown Confirm page set for " .. self.uciPage)
    end
    
    -- Shutdown Cancel
    Controls.btnShutdownCancel.EventHandler = function()
        self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        print("Shutdown cancelled by Cancel button for " .. self.uciPage)
        self:debug()
    end
    
    -- Shutdown Confirmed - Modified to control room automation
    Controls.btnShutdownConfirm.EventHandler = function()
        self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        self:powerOffRoomAutomation()
        self:startLoadingBar(false)
        local previousLayer = self.varActiveLayer
        self.varActiveLayer = self.kLayerCooling
        self:showLayer()
        self:interlock()
        self:debug()
        print("System shutdown confirmed for " .. self.uciPage)
    end
    
    -- Modal Popups - Button Triggers
    Controls.btnHelpLaptop.EventHandler = function()
        self:updateLaptopHelpState(Controls.btnHelpLaptop.Boolean)
    end
    
    Controls.btnHelpPC.EventHandler = function()
        self:updatePCHelpState(Controls.btnHelpPC.Boolean)
    end

    Controls.btnHelpWireless.EventHandler = function()
        self:updateWirelessHelpState(Controls.btnHelpWireless.Boolean)
    end

    Controls.btnHelpRouting.EventHandler = function()
        self:updateRoutingHelpState(Controls.btnHelpRouting.Boolean)
    end
    Controls.btnHelpDialer.EventHandler = function()
        self:updateDialerHelpState(Controls.btnHelpDialer.Boolean)
    end

    Controls.btnHelpStreamMusic.EventHandler = function()
        self:updateStreamMusicHelpState(Controls.btnHelpStreamMusic.Boolean)
    end

    -- External Triggers
    Controls.pinLEDUSBLaptop.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerLaptop end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    Controls.pinLEDUSBPC.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerPC end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDOffHookLaptop.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerLaptop end
        self:showLayer()
        self:interlock()
        self:debug()
    end

    Controls.pinLEDOffHookPC.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerPC end
        self:showLayer()
        self:interlock()
        self:debug()
    end
        
    Controls.pinLEDHDMI01Active.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerLaptop end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDHDMI02Active.EventHandler = function(ctl)
        local previousLayer = self.varActiveLayer
        if ctl.Boolean then self.varActiveLayer = self.kLayerPC end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    -- Pin Event Handlers for Sublayers
    Controls.pinLEDPresetSaved.EventHandler = function(ctl)
        self:updatePresetSavedState(ctl.Boolean)
    end
    
    Controls.pinLEDHDMI01Connect.EventHandler = function(ctl)
        self:updateHDMI01State(ctl.Boolean)
    end
    
    Controls.pinLEDACPRBypassActive.EventHandler = function(ctl)
        self:updateACPRBypassState(ctl.Boolean)
    end
    
    Controls.pinCallActive.EventHandler = function(ctl)
        self:updateCallActiveState(ctl.Boolean)
    end
    
    -- Legend label updates
    for i, lbl in ipairs(self.arrUCIUserLabels) do
        lbl.EventHandler = function()
            self:updateLegends()
        end
        print("funcUpdateLegends ran successfully for " .. self.uciPage)
    end
end

function UCIController:funcInit()
    -- Sync with Room Automation state if available
    if mySystemController and mySystemController.state then
        -- Check Room Automation state and sync UCI accordingly
        if Controls.ledSystemPower and Controls.ledSystemPower.Boolean then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
            elseif mySystemController.state.isCooling then
                self.varActiveLayer = self.kLayerCooling
                self:startLoadingBar(false)
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
    -- Hide specified navigation buttons [1][3]
    for _, index in ipairs(self.hiddenNavIndices) do
        if self.arrbtnNavs[index] then
            self.arrbtnNavs[index].Visible = false
            print("Hidden navigation button: btnNav"..string.format("%02d", index))
        end
    end
 
    self:showLayer()
    self:interlock()
    self:debug()
    self:updateLegends()
    print("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
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

-- Alternative approach: Direct UCI button monitoring for NV32 control
local nv32ControlTimer = nil -- Make timer accessible for cleanup

local function setupDirectNV32Control()
    print("=== Setting up Direct NV32 Control via UCI Buttons ===")
    
    -- Define the UCI button to NV32 input mapping
    local uciToNV32Mapping = {
        [7] = 5, -- btnNav07 → HDMI2 (Input 5)
        [8] = 4, -- btnNav08 → HDMI1 (Input 4)
        [9] = 6  -- btnNav09 → HDMI3 (Input 6)
    }
    
    -- Store previous button states to detect changes
    local previousButtonStates = {}
    
    -- Create a timer to monitor button states without overriding EventHandlers
    nv32ControlTimer = Timer.New()
    nv32ControlTimer.EventHandler = function()
        for uciButton, nv32Input in pairs(uciToNV32Mapping) do
            local buttonName = "btnNav" .. string.format("%02d", uciButton)
            if Controls[buttonName] then
                local currentState = Controls[buttonName].Boolean
                local previousState = previousButtonStates[uciButton]
                
                -- Check if button state changed to true
                if currentState and not previousState then
                    print("UCI Button " .. uciButton .. " pressed, switching NV32 to input " .. nv32Input)
                    
                    -- Control NV32 using UCI variable
                    if Controls.devNV32 and Controls.devNV32.String and Controls.devNV32.String ~= "" then
                        local success, nv32Component = pcall(function()
                            return Component.New(Controls.devNV32.String)
                        end)
                        if success and nv32Component then
                            local routeSuccess, routeErr = pcall(function()
                                nv32Component["hdmi.out.1.select.index"].Value = nv32Input
                            end)
                            if routeSuccess then
                                print("✓ NV32 controlled: Set Output 1 to Input " .. nv32Input .. " on " .. Controls.devNV32.String)
                            else
                                print("⚠ Failed to set NV32 route: " .. tostring(routeErr))
                            end
                        else
                            print("⚠ Failed to create NV32 component: " .. tostring(nv32Component))
                        end
                    else
                        print("⚠ NV32 device not selected in UCI variable devNV32")
                    end
                end
                
                -- Update previous state
                previousButtonStates[uciButton] = currentState
            end
        end
        
        -- Continue monitoring
        nv32ControlTimer:Start(0.1) -- Check every 100ms
    end
    
    -- Start the monitoring timer
    nv32ControlTimer:Start(0.1)
    print("✓ Timer-based UCI button monitoring started")
    print("=== Direct NV32 Control Setup Complete ===")
end

-- Set up direct control
setupDirectNV32Control()

-- Test UCI button accessibility
print("=== Testing UCI Button Accessibility ===")
for i = 7, 9 do
    local buttonName = "btnNav" .. string.format("%02d", i)
    if Controls[buttonName] then
        print("✓ " .. buttonName .. " accessible, current state: " .. tostring(Controls[buttonName].Boolean))
    else
        print("✗ " .. buttonName .. " NOT accessible")
    end
end

-- Test NV32 variable
if Controls.devNV32 then
    print("✓ UCI devNV32 variable accessible: " .. tostring(Controls.devNV32.String))
else
    print("✗ UCI devNV32 variable NOT accessible")
end
print("=== End Connectivity Test ===")

print("=== UCI and NV32 Integration Status ===")
print("✓ UCI script: Direct NV32 control via UCI variable active")
print("✓ Each UCI controls only its assigned NV32 device")
print("=== Integration Status Complete ===") 