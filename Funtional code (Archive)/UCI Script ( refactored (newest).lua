-- UCIController "class"
UCIController = {}
UCIController.__index = UCIController

function UCIController.new(uciPage, defaultRoutingLayer)
    local self = setmetatable({}, UCIController)

    -- Instance properties
    self.uciPage = uciPage
    self.varActiveLayer = 3 -- kLayer_Start
    self.isAnimating = false
    self.loadingTimer = nil

    -- Layer constants
    self.kLayer_Initialize   = 1
    self.kLayer_IncomingCall = 2
    self.kLayer_Start        = 3
    self.kLayer_Warming      = 4
    self.kLayer_Cooling      = 5
    self.kLayer_RoomControls = 6
    self.kLayer_PC           = 7
    self.kLayer_Laptop       = 8
    self.kLayer_Wireless     = 9
    self.kLayer_Routing      = 10
    self.kLayer_Dialer       = 11

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
        Controls.txtNavShutdown, 
        Controls.txtRoomName, 
        Controls.txtRoomNameStart,
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
        Uci.Variables.txtLabelNavShutdown,
        Uci.Variables.txtLabelRoomName, 
        Uci.Variables.txtLabelRoomNameStart,
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

    -- Set default routing layer (with fallback to 1 if not provided)
    self.activeRoutingLayer = defaultRoutingLayer or 1

    -- Setup
    self:registerEventHandlers()
    self:funcInit()

    return self
end

-- Add safe layer visibility method
function UCIController:safeSetLayerVisibility(page, layer, visible, transition)
    local success, error = pcall(function()
        Uci.SetLayerVisibility(page, layer, visible, transition)
    end)
    
    if not success then
        print("Warning: Layer '" .. layer .. "' not found on page '" .. page .. "'")
        print("Error: " .. tostring(error))
    end
    
    return success
end

-- Core logic methods
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

function UCIController:showACPRSublayer()
    if Controls.pinLEDACPRActive.Boolean then 
        self:safeSetLayerVisibility(self.uciPage, "J02-ACPROn", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", false, "none")
    else
        self:safeSetLayerVisibility(self.uciPage, "J05-CameraControls", true, "fade")
        self:safeSetLayerVisibility(self.uciPage, "J02-ACPROn", false, "none")
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
        self.activeRoutingLayer = 1  -- Reset to default
    end
    
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
        "I02-HelpPC", 
        "I03-HelpLaptop",
        "I04-HelpWireless", 
        "I05-HelpRouting", 
        "J01-USBConnectedNOT", 
        "J02-ACPROn",
        "J04-CamPresetSaved", 
        "J05-CameraControls", 
        "P05-PC", 
        "L01-HDMIDisconnected",
        "L05-Laptop", 
        "W05-Wireless", 
        "R01-Routing-Lobby", 
        "R02-Routing-WTerrace",
        "R03-Routing-NTerraceWall", 
        "R04-Routing-Garden", 
        "R05-Routing-NTerraceFloor",
        "R10-Routing", 
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
        [self.kLayer_Initialize] = {
            showLayers = {"A01-Initialize"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayer_IncomingCall] = {showLayers = {"B01-IncomingCall"}},
        [self.kLayer_Start] = {
            showLayers = {"C01-Start"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayer_Warming] = {
            showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayer_Cooling] = {
            showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
            callFunctions = {function() self:hideBaseLayers() end}
        },
        [self.kLayer_RoomControls] = {
            showLayers = {"H01-RoomControls"},
            hideLayers = {"X01-ProgramVolume"}
        },
        [self.kLayer_PC] = {
            showLayers = {"P05-PC"},
            callFunctions = {
                function() self:callActivePopup() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end
            }
        },
        [self.kLayer_Laptop] = {
            showLayers = {"L05-Laptop"},
            callFunctions = {
                function() self:callActivePopup() end,
                function() self:showHDMISublayer() end,
                function() self:showCameraSublayer() end,
                function() self:showPresetSavedSublayer() end,
                function() self:showACPRSublayer() end
            }
        },
        [self.kLayer_Wireless] = {showLayers = {"W05-Wireless"}
        },
        [self.kLayer_Routing] = {
            showLayers = {"R10-Routing"},
            callFunctions = {function() self:showRoutingLayer() end}
        },
        [self.kLayer_Dialer] = {
            showLayers = {"V05-Dialer"},
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
    for i = 1, 11 do
        Controls["btnNav" .. string.format("%02d", i)].Boolean = false
    end
    local layerToButton = {
        [self.kLayer_Initialize]   = 1,
        [self.kLayer_IncomingCall] = 2,
        [self.kLayer_Start]        = 3,
        [self.kLayer_Warming]      = 4,
        [self.kLayer_Cooling]      = 5,
        [self.kLayer_RoomControls] = 6,
        [self.kLayer_PC]           = 7,
        [self.kLayer_Laptop]       = 8,
        [self.kLayer_Wireless]     = 9,
        [self.kLayer_Routing]      = 10,
        [self.kLayer_Dialer]       = 11,
    }
    local btnIndex = layerToButton[self.varActiveLayer]
    if btnIndex then
        Controls["btnNav" .. string.format("%02d", btnIndex)].Boolean = true
    end
end

function UCIController:debug()
    local layers = {
        {var = self.kLayer_Initialize,   msg = "Set UCI to Initialize"},
        {var = self.kLayer_IncomingCall, msg = "Set UCI to IncomingCall"},
        {var = self.kLayer_Start,        msg = "Set UCI to Start"},
        {var = self.kLayer_Warming,      msg = "Set UCI to Warming"},
        {var = self.kLayer_Cooling,      msg = "Set UCI to Cooling"},
        {var = self.kLayer_RoomControls, msg = "Set UCI to Room Controls"},
        {var = self.kLayer_PC,           msg = "Set UCI to PC"},
        {var = self.kLayer_Laptop,       msg = "Set UCI to Laptop"},
        {var = self.kLayer_Wireless,     msg = "Set UCI to Wireless"},
        {var = self.kLayer_Routing,      msg = "Set UCI to Routing"},
        {var = self.kLayer_Dialer,       msg = "Set UCI to Dialer"},
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

function UCIController:startLoadingBar(isPoweringOn)
    if self.isAnimating then return end
    self.isAnimating = true
    local duration
    if isPoweringOn then
        duration = tonumber(Uci.Variables["timeProgressWarming"]) or 7
    else
        duration = tonumber(Uci.Variables["timeProgressCooling"]) or 7
    end
    local steps = 100
    local interval = duration / steps
    local currentStep = 0
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
    self.loadingTimer = Timer.New()
    Controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    Controls.txtProgressBar.String = isPoweringOn and "0%" or "100%"
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
                self:btnNavEventHandler(self.kLayer_Laptop)
            else
                self:btnNavEventHandler(self.kLayer_Start)
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
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
end

-- All Event Handlers, grouped for clarity
function UCIController:registerEventHandlers()
    -- Nav Buttons
    for i, ctl in ipairs(self.arrbtnNavs) do
        ctl.EventHandler = function() self:btnNavEventHandler(i) end
    end
    
    -- Routing Buttons
    for i, btn in ipairs(self.arrRoutingButtons) do
        btn.EventHandler = function() self:routingButtonEventHandler(i) end
    end
    
    -- System State
    -- Controls.btnPGMVolMute.EventHandler = function(ctl)
    --     if ctl.Boolean or Controls.mtrPGMVolLvl.Position == 0 then
    --         Controls.mtrPGMVolLvl.Color = "#CCCCCC"
    --         Controls.btnPGMVolMute.CssClass = "icon-volume_off"
    --     else
    --         Controls.mtrPGMVolLvl.Color = "#0561A5"
    --         Controls.btnPGMVolMute.CssClass = "icon-volume_mute"
    --     end
    -- end
    
    -- Start System
    Controls.btnStartSystem.EventHandler = function()
        self:startLoadingBar(true)
        self:btnNavEventHandler(self.kLayer_Warming)
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
    
    -- Shutdown Confirmed
    Controls.btnShutdownConfirm.EventHandler = function()
        self:startLoadingBar(false)
        self:btnNavEventHandler(self.kLayer_Cooling)
    end
    
    -- External Triggers
    Controls.pinLEDUSBPC.EventHandler = function(ctl)
        if ctl.Boolean then self.varActiveLayer = self.kLayer_PC end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDUSBLaptop.EventHandler = function(ctl)
        if ctl.Boolean then self.varActiveLayer = self.kLayer_Laptop end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDOffHookPC.EventHandler = function(ctl)
        if ctl.Boolean then self.varActiveLayer = self.kLayer_PC end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDOffHookLaptop.EventHandler = function(ctl)
        if ctl.Boolean then self.varActiveLayer = self.kLayer_Laptop end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDLaptop01Active.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayer_Laptop
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    Controls.pinLEDLaptop02Active.EventHandler = function(ctl)
        if ctl.Boolean then
            self.varActiveLayer = self.kLayer_Laptop
        end
        self:showLayer()
        self:interlock()
        self:debug()
    end
    
    -- Legend label updates
    for i, lbl in ipairs(self.arrUCIUserLabels) do
        lbl.EventHandler = function() self:updateLegends() end
        print("funcUpdateLegends() ran successfully for " .. self.uciPage)
    end
end

function UCIController:funcInit()
    self.varActiveLayer = self.kLayer_Start
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
        targetPageName,                    -- Try exact name first
        targetPageName:gsub("%(", " "):gsub("%)", ""),  -- Remove parentheses
        targetPageName:gsub(" ", "-"),     -- Replace spaces with hyphens
        targetPageName:gsub(" ", "_"),     -- Replace spaces with underscores
        targetPageName:gsub("%(", "-"):gsub("%)", ""),  -- Replace parentheses with hyphens
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

-- Create the controller instances for your pages with error handling
myUCI = createUCIControllerWithErrorHandling("UCI MPR(005)", 4)
