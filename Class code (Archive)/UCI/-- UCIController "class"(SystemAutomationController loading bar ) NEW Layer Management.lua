-- UCIController class
UCIController = {}
UCIController.__index = UCIController

function UCIController.new(uciPage, defaultRoutingLayer)
    local self = setmetatable({}, UCIController)
    
    -- Instance properties
    self.uciPage = uciPage
    self.varActiveLayer = 3 -- kLayerStart
    self.isAnimating = false
    self.loadingTimer = nil
    
    -- Layer constants
    self.kLayerInitialize   = 1
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

-- Initialize Room Controls Component Reference
function UCIController:initializeRoomControlsComponent()
    -- Try different methods to get the component name
    local componentName = nil
    
    -- Method 1: Try UCI variable
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    
    -- Method 2: Try default naming convention
    if not componentName then
        -- Try to extract room name from UCI page name
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

-- Room Automation Integration Methods
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

-- Get Room Automation Timing
function UCIController:getRoomAutomationTiming(isPoweringOn)
    local duration
    
    -- Try to get timing from component reference first
    if self.roomControlsComponent then
        local success, result = pcall(function()
            if isPoweringOn then
                return self.roomControlsComponent["warmupTime"] and self.roomControlsComponent["warmupTime"].Value or 10 -- default 10 seconds, change to "WarmupTime" to use component value set by user
            else
                return self.roomControlsComponent["cooldownTime"] and self.roomControlsComponent["cooldownTime"].Value or 5 -- default 5 seconds, change to "CooldownTime" to use component value set by user
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

-- Add safe layer visibility method
function UCIController:safeSetLayerVisibility(page, layer, visible, transition)
    local success, error = pcall(function()
        Uci.SetLayerVisibility(page, layer, visible, transition)
    end)
    
    if not success then
        print("Warning: Layer " .. layer .. " not found on page " .. page)
        print("Error: " .. tostring(error))
    end
    
    return success
end

-- Core UCI logic methods
function UCIController:hideBaseLayers()
    self:safeSetLayerVisibility(self.uciPage, "X01-ProgramVolume", false, "none")
    self:safeSetLayerVisibility(self.uciPage, "Y01-Navbar", false, "none")
    self:safeSetLayerVisibility(self.uciPage, "Z01-Base", false, "none")
end

function UCIController:callActivePopup()
    if Controls.pinCallActive.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I01-CallActive", true, "fade")
    else
        self:safeSetLayerVisibility(self.uciPage, "I01-CallActive", false, "none")
    end
end

function UCIController:showPresetSavedSublayer()
    if Controls.pinLEDPresetSaved.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "J04-CamPresetSaved", true, "fade")
    else
        self:safeSetLayerVisibility(self.uciPage, "J04-CamPresetSaved", false, "none")
    end
end

function UCIController:showHDMISublayer()
    if Controls.pinLEDHDMIConnected.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "L05-Laptop", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "L01-HDMIDisconnected", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "L01-HDMIDisconnected", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "L05-Laptop", false, "none")
    end
end

function UCIController:showLaptopHelpSublayer()
    if Controls.btnHelpLaptop.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I02-HelpLaptop", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "I02-HelpLaptop", false, "none")
    end
end

function UCIController:showACPRSublayer()
    if Controls.pinLEDACPRActive.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J02-ACPROn", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "J02-ACPROn", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", false, "none")
    end
end

function UCIController:showPCHelpSublayer()
    if Controls.btnHelpPC.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I03-HelpPC", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "I03-HelpPC", false, "none")
    end
end

function UCIController:showWirelessHelpSublayer()
    if Controls.btnHelpWireless.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I04-HelpWireless", true , "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "I04-HelpWireless", false, "none")
    end
end

function UCIController:showRoutingHelpSublayer()
    if Controls.btnHelpRouting.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I05-HelpRouting", true , "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "I05-HelpRouting", false, "none")
    end
end

function UCIController:showDialerHelpSublayer()
    if Controls.btnHelpDialer.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I06-HelpDialer", true , "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "I06-HelpDialer", false, "none")
    end
end

function UCIController:showStreamMusicHelpSublayer()
    if Controls.btnHelpStreamMusic.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "I07-HelpStreamMusic", true , "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "I07-HelpStreamMusic", false, "none")
    end
end

function UCIController:showCameraSublayer()
    if Controls.pinLEDUSBPC.Boolean then
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J01-USBConnectedNOT", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "J01-USBConnectedNOT", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", false, "none")
    end
end

function UCIController:showRoutingLayer()
    -- Add bounds check
    if self.activeRoutingLayer < 1 or self.activeRoutingLayer > #self.routingLayers then
        self.activeRoutingLayer = 1 -- Reset to default
    end    
    -- Hide program volume layer for routing view
    self:safeSetLayerVisibility(self.uciPage, "X01-ProgramVolume", false, "none")

    -- Hide all routing layers
    for _, layer in ipairs(self.routingLayers) do
        self:safeSetLayerVisibility(self.uciPage, layer, false, "none")
    end
    
    -- Show active layer and update buttons
    self:safeSetLayerVisibility(self.uciPage, self.routingLayers[self.activeRoutingLayer], true, "fade")
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

function UCIController:showLayer()
    local layersToHide = {
        "A01-Initialize", 
        "B01-IncomingCall", 
        "C01-Start", 
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
        "J01-USBConnectedNOT", 
        "J02-ACPROn",
        "J04-CamPresetSaved", 
        "J05-CameraControls", 
        "L01-HDMIDisconnected",
        "L05-Laptop", 
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
        self:safeSetLayerVisibility(self.uciPage, layer, false, "none")
    end
    
    self:safeSetLayerVisibility(self.uciPage, "X01-ProgramVolume", true, "none")
    self:safeSetLayerVisibility(self.uciPage, "Y01-Navbar", true, "none")
    self:safeSetLayerVisibility(self.uciPage, "Z01-Base", true, "none")
    
    local layerConfigs = {
        [self.kLayerInitialize] = {
            showLayers = {"A01-Initialize"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayerIncomingCall] = {
            showLayers = {"B01-IncomingCall"}
        },
        [self.kLayerStart] = {
            showLayers = {"C01-Start"},
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
            hideLayers = {"X01-ProgramVolume"}
        },
        [self.kLayerLaptop] = {
            showLayers = {"L05-Laptop"},
            callFunctions = {
                function() self:callActivePopup() end,
                function() self:showHDMISublayer() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end,
                function() self:showLaptopHelpSublayer() end
            }
        },
        [self.kLayerPC] = {
            showLayers = {"P05-PC"},
            callFunctions = {
                function() self:callActivePopup() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end,
                function() self:showPCHelpSublayer() end
            }
        },
        [self.kLayerWireless] = {
            showLayers = {"W05-Wireless"},
            callFunctions = {function() self:showWirelessHelpSublayer() end}
        },
        [self.kLayerRouting] = {
            showLayers = {"R10-Routing"},
            callFunctions = {function() self:showRoutingLayer() end}
        },
        [self.kLayerDialer] = {
            showLayers = {"V05-Dialer"},
            callFunctions = {function() self:callActivePopup() end}
        },
        [self.kLayerStreamMusic] = {
            showLayers = {"S05-StreamMusic"}, 
            callFunctions = {function() self:callActivePopup() end}
        }
    }
    
    local config = layerConfigs[self.varActiveLayer]
    if config then
        for _, layer in ipairs(config.showLayers or {}) do
            self:safeSetLayerVisibility(self.uciPage, layer, true, "fade")
        end
        
        for _, layer in ipairs(config.hideLayers or {}) do
            self:safeSetLayerVisibility(self.uciPage, layer, false, "none")
        end
        
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
        [self.kLayerInitialize] =   1,
        [self.kLayerIncomingCall] = 2,
        [self.kLayerStart] =        3,
        [self.kLayerWarming] =      4,
        [self.kLayerCooling] =      5,
        [self.kLayerRoomControls] = 6,
        [self.kLayerPC] =           7,
        [self.kLayerLaptop] =       8,
        [self.kLayerWireless] =     9,
        [self.kLayerRouting] =      10,
        [self.kLayerDialer] =       11,
        [self.kLayerStreamMusic] =  12
    }
    
    local btnIndex = layerToButton[self.varActiveLayer]
    if btnIndex then
        Controls["btnNav" .. string.format("%02d", btnIndex)].Boolean = true
    end
end

function UCIController:debug()
    local layers = {
        {var = self.kLayerInitialize, msg   = "Set UCI to Initialize"},
        {var = self.kLayerIncomingCall, msg = "Set UCI to IncomingCall"},
        {var = self.kLayerStart, msg        = "Set UCI to Start"},
        {var = self.kLayerWarming, msg      = "Set UCI to Warming"},
        {var = self.kLayerCooling, msg      = "Set UCI to Cooling"},
        {var = self.kLayerRoomControls, msg = "Set UCI to Room Controls"},
        {var = self.kLayerPC, msg           = "Set UCI to PC"},
        {var = self.kLayerLaptop, msg       = "Set UCI to Laptop"},
        {var = self.kLayerWireless, msg     = "Set UCI to Wireless"},
        {var = self.kLayerRouting, msg      = "Set UCI to Routing"},
        {var = self.kLayerDialer, msg       = "Set UCI to Dialer"},
        {var = self.kLayerStreamMusic, msg  = "Set UCI to Stream Music"}
    }
    
    for i = 1, #layers do
        if self.varActiveLayer == layers[i].var then
            print(layers[i].msg)
            break
        end
    end
end

function UCIController:btnNavEventHandler(argIndex)
    self.varActiveLayer = argIndex
    self:showLayer()
    self:interlock()
    self:debug()
end

-- Modified Loading Bar with Room Automation Integration
function UCIController:startLoadingBar(isPoweringOn)
    if self.isAnimating then
        return
    end
    
    self.isAnimating = true
    
    -- Get timing from Room Automation system
    local duration = self:getRoomAutomationTiming(isPoweringOn)
    local steps = 100
    local interval = duration / steps
    local currentStep = 0
    
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
    
    self.loadingTimer = Timer.New()
    
    Controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    Controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
    
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
            self:btnNavEventHandler(i)
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
        -- Power on Room Automation system
        self:powerOnRoomAutomation()
        
        -- Start UCI loading bar with Room Automation timing
        self:startLoadingBar(true)
        self:btnNavEventHandler(self.kLayerWarming)
        print("System started with Start button for " .. self.uciPage)
    end
    
    -- Shutdown Confirm
    Controls.btnNavShutdown.EventHandler = function()
        self:safeSetLayerVisibility(self.uciPage, "D01-ShutdownConfirm", true, "fade")
        print("Shutdown Confirm page set for " .. self.uciPage)
    end
    
    -- Shutdown Cancel
    Controls.btnShutdownCancel.EventHandler = function()
        self:safeSetLayerVisibility(self.uciPage, "D01-ShutdownConfirm", false, "fade")
        print("Shutdown cancelled by Cancel button for " .. self.uciPage)
        self:debug()
    end
    
    -- Shutdown Confirmed - Modified to control room automation
    Controls.btnShutdownConfirm.EventHandler = function()
        -- Power off Room Automation system
        self:powerOffRoomAutomation()
        
        -- Start UCI loading bar with Room Automation timing
        self:startLoadingBar(false)
        self:btnNavEventHandler(self.kLayerCooling)
        print("System shutdown confirmed for " .. self.uciPage)
    end
    
    -- Modal Popups - Button Triggers
    Controls.btnHelpLaptop.EventHandler = function()
        self:showLaptopHelpSublayer()       -- show laptop help sublayer
    end
    
    Controls.btnHelpPC.EventHandler = function()
        self:showPCHelpSublayer()           -- show pc help sublayer
    end

    Controls.btnHelpWireless.EventHandler = function()
        self:showWirelessHelpSublayer()       -- show wireless help sublayer
    end

    Controls.btnHelpRouting.EventHandler = function()
        self:showRoutingHelpSublayer()       -- show routing help sublayer
    end

    Controls.btnHelpDialer.EventHandler = function()
        self:showDialerHelpSublayer()       -- show dialer help sublayer
    end

    Controls.btnHelpStreamMusic.EventHandler = function()
        self:showStreamMusicHelpSublayer()       -- show stream music help sublayer
    end

    -- External Triggers
    Controls.pinLEDUSBPC.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerPC -- show PC layer
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDUSBLaptop.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerLaptop -- show laptop layer
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDOffHookPC.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerPC -- show PC layer
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDOffHookLaptop.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerLaptop -- show laptop layer
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDLaptop01Active.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerLaptop -- show laptop layer
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDLaptop02Active.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayerLaptop -- show laptop layer        
        end
        self:showLayer()
        self:interlock()
        self:debug()
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
    if mySystemController then
        -- Check Room Automation state and sync UCI accordingly
        if Controls.ledSystemPower and Controls.ledSystemPower.Boolean then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
            elseif mySystemController.state.isCooling then
                self.varActiveLayer = self.kLayerCooling
                self:startLoadingBar(false)
            else
                self.varActiveLayer = self.kLayerLaptop -- Default active state
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
    
    self:showLayer()
    self:interlock()
    self:debug()
    self:updateLegends()
    print("UCI Initialized for " .. self.uciPage)
end

-- Quick Fix implementation with error handling for page name validation
local function createUCIControllerWithErrorHandling(targetPageName, defaultRoutingLayer)
    -- Test with different page name variations
    local pageNames = {
        targetPageName, -- Try exact name first
        targetPageName:gsub("%(", ""):gsub("%)", ""), -- Remove parentheses
        targetPageName:gsub(" ", "-"), -- Replace spaces with hyphens
        targetPageName:gsub(" ", "_"), -- Replace spaces with underscores
        targetPageName:gsub("%(", "-"):gsub("%)", "") -- Replace parentheses with hyphens
    }
    
    local controller
    for _, pageName in ipairs(pageNames) do
        local success, result = pcall(function()
            return UCIController.new(pageName, defaultRoutingLayer)
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
    Uci.Variables.txtUCIPageName.String or "UCI MPR(005)",  -- Use UCI Variable for page name with fallback
    tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 4  -- Use UCI Variable for routing layer with fallback
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
    end
    
    syncTimer:Start(5)
    print("Room Automation sync timer started for UCI")
end

-- Add syncWithRoomAutomation method
function UCIController:syncWithRoomAutomation()
    if not mySystemController then
        return
    end
    
    local success, error = pcall(function()
        -- Sync power state
        if Controls.ledSystemPower and Controls.ledSystemPower.Boolean then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
            elseif mySystemController.state.isCooling then
                self.varActiveLayer = self.kLayerCooling
                self:startLoadingBar(false)
            else
                self.varActiveLayer = self.kLayerLaptop -- Default active state
            end
        else
            self.varActiveLayer = self.kLayerStart
        end
        
        -- Update UI
        self:showLayer()
        self:interlock()
        self:debug()
    end)
    
    if not success then
        print("Warning: Failed to sync with Room Automation: " .. tostring(error))
    end
end
