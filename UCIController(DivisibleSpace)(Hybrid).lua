--[[
    UCIController (DivisibleSpace)(Hybrid Version)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0-Hybrid | Date: 2026-01-13
    Firmware Req: 10.0.0
    SIMPLIFIED FOR MAINTAINABILITY:
    - Single class structure (no module inheritance)
    - Direct methods instead of module abstractions
    - Clear, traceable event flow
    - Comprehensive inline documentation

]]--

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Buttons
    btnNav01 = Controls.btnNav01, btnNav02 = Controls.btnNav02, btnNav03 = Controls.btnNav03,
    btnNav04 = Controls.btnNav04, btnNav05 = Controls.btnNav05, btnNav06 = Controls.btnNav06,
    btnNav07 = Controls.btnNav07, btnNav08 = Controls.btnNav08, btnNav09 = Controls.btnNav09,
    btnNav10 = Controls.btnNav10, btnNav11 = Controls.btnNav11, btnNav12 = Controls.btnNav12,
    btnNav13 = Controls.btnNav13, btnNav14 = Controls.btnNav14, btnNav15 = Controls.btnNav15,

    -- Navigation Text Labels
    txtNav01 = Controls.txtNav01, txtNav02 = Controls.txtNav02, txtNav03 = Controls.txtNav03,
    txtNav04 = Controls.txtNav04, txtNav05 = Controls.txtNav05, txtNav06 = Controls.txtNav06,
    txtNav07 = Controls.txtNav07, txtNav08 = Controls.txtNav08, txtNav09 = Controls.txtNav09,
    txtNav10 = Controls.txtNav10, txtNav11 = Controls.txtNav11, txtNav12 = Controls.txtNav12,
    txtNav13 = Controls.txtNav13, txtNav14 = Controls.txtNav14, txtNav15 = Controls.txtNav15,
    
    -- System Controls
    btnStartSystem      = Controls.btnStartSystem,
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel,
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    
    -- Help Buttons
    btnOpenHelpLaptopA      = Controls.btnOpenHelpLaptopA,
    btnOpenHelpLaptopB      = Controls.btnOpenHelpLaptopB,
    btnOpenHelpPCA          = Controls.btnOpenHelpPCA,
    btnOpenHelpPCB          = Controls.btnOpenHelpPCB,
    btnOpenHelpWirelessA    = Controls.btnOpenHelpWirelessA,
    btnOpenHelpWirelessB    = Controls.btnOpenHelpWirelessB,
    btnOpenHelpRouting      = Controls.btnOpenHelpRouting,
    btnOpenHelpStreamMusic  = Controls.btnOpenHelpStreamMusic,

    btnCloseHelpLaptopA      = Controls.btnCloseHelpLaptopA,
    btnCloseHelpLaptopB      = Controls.btnCloseHelpLaptopB,
    btnCloseHelpPCA          = Controls.btnCloseHelpPCA,
    btnCloseHelpPCB          = Controls.btnCloseHelpPCB,
    btnCloseHelpWirelessA    = Controls.btnCloseHelpWirelessA,
    btnCloseHelpWirelessB    = Controls.btnCloseHelpWirelessB,
    btnCloseHelpRouting      = Controls.btnCloseHelpRouting,
    btnCloseHelpStreamMusic  = Controls.btnCloseHelpStreamMusic,
    
    btnHelpDialer           = Controls.btnHelpDialer,
    
    -- Progress Controls
    knbProgressBar = Controls.knbProgressBar,
    txtProgressBar = Controls.txtProgressBar,
    
    -- Pin Inputs
    pinCallActive               = Controls.pinCallActive,
    pinLEDUSBLaptopA            = Controls.pinLEDUSBLaptopA,
    pinLEDUSBLaptopB            = Controls.pinLEDUSBLaptopB,
    pinLEDUSBPCA                = Controls.pinLEDUSBPCA,
    pinLEDUSBPCB                = Controls.pinLEDUSBPCB,
    pinLEDOffHookLaptopA        = Controls.pinLEDOffHookLaptopA,
    pinLEDOffHookLaptopB        = Controls.pinLEDOffHookLaptopB,
    pinLEDOffHookPCA            = Controls.pinLEDOffHookPCA,
    pinLEDOffHookPCB            = Controls.pinLEDOffHookPCB,
    pinLEDHDMIActiveLaptopA     = Controls.pinLEDHDMIActiveLaptopA,
    pinLEDHDMIActiveLaptopB     = Controls.pinLEDHDMIActiveLaptopB,
    pinLEDHDMIActivePCA         = Controls.pinLEDHDMIActivePCA,
    pinLEDHDMIActivePCB         = Controls.pinLEDHDMIActivePCB,
    pinLEDPresetSaved           = Controls.pinLEDPresetSaved,
    pinLEDACPRBypassSeparated   = Controls.pinLEDACPRBypassSeparated,
    pinLEDACPRBypassCombined    = Controls.pinLEDACPRBypassCombined,
    pinLEDTouchActivity         = Controls.pinLEDTouchActivity,
    
    -- Divisible Space HDMI Connection Monitoring (optional)
    pinLEDHDMIConnectedPCA      = Controls.pinLEDHDMIConnectedPCA,
    pinLEDHDMIConnectedPCB      = Controls.pinLEDHDMIConnectedPCB,
    pinLEDHDMIConnectedLaptopA  = Controls.pinLEDHDMIConnectedLaptopA,
    pinLEDHDMIConnectedLaptopB  = Controls.pinLEDHDMIConnectedLaptopB,
}

-------------------[ Configuration ]-------------------
local conferenceStateConfig = {
    skipLaptopA = true,
    skipLaptopB = true
}

local acprConfig = {
    disableACPRShow = false
}

-------------------[ Utility Functions ]-------------------
-- Check if a value is an array (table with numeric indices)
local function isArr(t) 
    return type(t) == "table" and t[1] ~= nil 
end

-- Get control array (normalizes single controls to arrays)
local function getControlArray(ctrl)
    return ctrl and (isArr(ctrl) and ctrl or {ctrl}) or {}
end

-- Set property only if value changed (prevents unnecessary signal propagation)
-- This is insurance against feedback loops and improves performance
local function setProp(ctrl, prop, val)
    if ctrl and ctrl[prop] ~= val then 
        ctrl[prop] = val 
        return true
    end
    return false
end

-- Bind an event handler to a control
local function bind(ctrl, handler)
    if ctrl then 
        ctrl.EventHandler = handler 
    end
end

-- Bind event handlers to an array of controls
local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do
        bind(ctrl, function(ctl) handler(i, ctl) end)
    end
end

-- Execute function for each item in array (generic utility - works with any array)
local function forEach(arr, fn)
    if not arr then return end
    for i, v in ipairs(arr) do 
        if fn then fn(i, v) end 
    end
end

-- Bind paired controls (open/close, on/off) with interlocking behavior
local function bindPairedControls(openCtrl, closeCtrl, updateHandler)
    local function bindPair(ctrl, oppCtrl)
        if ctrl and updateHandler then
            bind(ctrl, function()
                if oppCtrl then setProp(oppCtrl, "Boolean", false) end
                updateHandler()
            end)
        end
    end
    bindPair(openCtrl, closeCtrl)
    bindPair(closeCtrl, openCtrl)
end

-------------------[ Validation Functions ]-------------------
-- Check that all required controls exist before proceeding to prevent nil reference errors
local function validateControls()
    local missing = {}
    for name, ctrl in pairs(controls) do
        if not ctrl then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing REQUIRED controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        error("UCIController initialization failed: Missing required controls. All controls must be present.")
    end
    print("UCIController validation passed - All controls present")
    return true
end

-------------------[ Layer Data Configuration ]-------------------
-- All layers that need to be hidden before showing a new layer
local layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
    "H04-RoomCombining","H08-RoomControlsCombined","H09-RoomControlsSeparated","H10-RoomControls",
    "I01-CallActive","I02-HelpLaptopA","I03-HelpLaptopB","I04-HelpPCA","I05-HelpPCB",
    "I06-HelpWirelessA","I07-HelpWirelessB","I08-HelpRouting","I09-HelpDialer","I10-HelpStreamMusic",
    "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB","J03-ConnectUSBPCA","J04-ConnectUSBPCB",
    "J06-ACPRActiveCombined","J07-ACPRActiveSeparated","J08-CamPresetSaved",
    "J09-ACPRBtnCombined","J10-ACPRBtnSeparated",
    "J11-CameraSelectionLaptopA","J12-CameraSelectionLaptopB","J13-CameraSelectionPCA","J14-CameraSelectionPCB",
    "J17-VideoPrivacySeparatedA","J18-VideoPrivacySeparatedB","J19-VideoPrivacyCombinedA","J20-VideoPrivacyCombinedB",
    "J21-ConferenceControlsLaptopA","J22-ConferenceControlsLaptopB","J23-ConferenceControlsPCA","J24-ConferenceControlsPCB",
    "L01-HDMIDisconnected","L01-LaptopA",
    "L02-HDMIDisconnected","L02-LaptopB",
    "P01-HDMIDisconnected","P01-PCA",
    "P02-HDMIDisconnected","P02-PCB",
    "W01-WirelessA","W02-WirelessB","W05-Wireless",
    "R10-Routing",
    "S10-StreamMusic",
    "V05-Dialer",
    "X01-ProgramVolume",
    "Y01-Navbar",
    "Z01-Base"
}

-------------------[ Main UCIController Class ]-------------------
UCIController = {}
UCIController.__index = UCIController

function UCIController.new(uciPage, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
    -- Validate that all required controls exist
    if not validateControls() then 
        print("ERROR: UCIController initialization failed - validation errors")
        return nil 
    end
    
    local self = setmetatable({}, UCIController)
    
    -- Basic configuration
    self.uciPage = uciPage
    self.debugging = true
    self.varActiveLayer = defaultActiveLayer or 10
    self.defaultActiveLayer = defaultActiveLayer or 10
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.isInitialized = false
    
    -- Layer constants - these map UCI button indices to layer types
    self.kLayerAlarm            = 1
    self.kLayerIncomingCall     = 2
    self.kLayerStart            = 3
    self.kLayerWarming          = 4
    self.kLayerCooling          = 5
    self.kLayerRoomControls     = 6
    self.kLayerPCA              = 7
    self.kLayerPCB              = 8
    self.kLayerLaptopA          = 9
    self.kLayerLaptopB          = 10
    self.kLayerWireless         = 11
    self.kLayerRouting          = 12
    self.kLayerDialer           = 13
    self.kLayerStreamMusic      = 14
    self.kLayerRoomCombining    = 15
    
    -- Layer visibility state tracking
    self.layerStates = {}
    
    -- Component references - these are discovered/assigned during init
    self.roomControlsComponent = nil
    self.switcherComponent = nil
    self.compDivisibleSpaceControls = nil
    self.btnRoomState = nil
    
    -- State tracking - all in one place for easy reference
    self.previousPowerState = nil
    self.isAnimating = false
    self.roomIdentity = nil  -- "CollabA" or "CollabB"
    self.videoSwitcherEnabled = false
    self.videoSwitcherType = nil
    self.divisibleSpaceEnabled = false
    
    -- Timers
    self.syncTimer = nil
    self.loadingTimer = nil
    self.timeoutTimer = nil
    self.uciTouchInactivityTimer = Timer.New()
    
    -- Legend arrays (initialized later)
    self.arrUCILegends = {}
    self.arrUCIUserLabels = {}
    
    -- Layer configuration maps (initialized later)
    self.layerConfigs = nil
    
    -- Source data map: centralized place to define all source-related data
    -- This eliminates repetitive code and makes it easy to add new sources
    self.sources = {
        LaptopA = {
            layerConst   = 9,  -- kLayerLaptopA
            hdmiPin      = controls.pinLEDHDMIConnectedLaptopA,
            baseLayer    = "L01-LaptopA",
            discLayer    = "L01-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBLaptopA,
            usbConnect   = "J01-ConnectUSBLaptopA",
            confLayer    = "J21-ConferenceControlsLaptopA",
            cameraLayer  = "J11-CameraSelectionLaptopA",
            videoPrivacySeparate = nil,  -- Laptops don't have video privacy
            videoPrivacyCombine = nil,
            helpLayer    = "I02-HelpLaptopA",
            btnOpen      = controls.btnOpenHelpLaptopA,
            btnClose     = controls.btnCloseHelpLaptopA
        },
        LaptopB = {
            layerConst   = 10,  -- kLayerLaptopB
            hdmiPin      = controls.pinLEDHDMIConnectedLaptopB,
            baseLayer    = "L02-LaptopB",
            discLayer    = "L02-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBLaptopB,
            usbConnect   = "J02-ConnectUSBLaptopB",
            confLayer    = "J22-ConferenceControlsLaptopB",
            cameraLayer  = "J12-CameraSelectionLaptopB",
            videoPrivacySeparate = nil,
            videoPrivacyCombine = nil,
            helpLayer    = "I03-HelpLaptopB",
            btnOpen      = controls.btnOpenHelpLaptopB,
            btnClose     = controls.btnCloseHelpLaptopB
        },
        PCA = {
            layerConst   = 7,  -- kLayerPCA
            hdmiPin      = controls.pinLEDHDMIConnectedPCA,
            baseLayer    = "P01-PCA",
            discLayer    = "P01-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBPCA,
            usbConnect   = "J03-ConnectUSBPCA",
            confLayer    = "J23-ConferenceControlsPCA",
            cameraLayer  = "J13-CameraSelectionPCA",
            videoPrivacySeparate = "J17-VideoPrivacySeparatedA",
            videoPrivacyCombine = "J19-VideoPrivacyCombinedA",
            helpLayer    = "I04-HelpPCA",
            btnOpen      = controls.btnOpenHelpPCA,
            btnClose     = controls.btnCloseHelpPCA
        },
        PCB = {
            layerConst   = 8,  -- kLayerPCB
            hdmiPin      = controls.pinLEDHDMIConnectedPCB,
            baseLayer    = "P02-PCB",
            discLayer    = "P02-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBPCB,
            usbConnect   = "J04-ConnectUSBPCB",
            confLayer    = "J24-ConferenceControlsPCB",
            cameraLayer  = "J14-CameraSelectionPCB",
            videoPrivacySeparate = "J18-VideoPrivacySeparatedB",
            videoPrivacyCombine = "J20-VideoPrivacyCombinedB",
            helpLayer    = "I05-HelpPCB",
            btnOpen      = controls.btnOpenHelpPCB,
            btnClose     = controls.btnCloseHelpPCB
        }
    }
    
    -- Quick lookup from layerConst to source key
    self.layerToSource = {}
    for name, src in pairs(self.sources) do
        self.layerToSource[src.layerConst] = name
    end
    
    -- Help layer to button mapping for state synchronization
    self.helpLayerButtonMap = {
        ["I02-HelpLaptopA"]    = {open = "btnOpenHelpLaptopA",    close = "btnCloseHelpLaptopA"},
        ["I03-HelpLaptopB"]    = {open = "btnOpenHelpLaptopB",    close = "btnCloseHelpLaptopB"},
        ["I04-HelpPCA"]        = {open = "btnOpenHelpPCA",        close = "btnCloseHelpPCA"},
        ["I05-HelpPCB"]        = {open = "btnOpenHelpPCB",        close = "btnCloseHelpPCB"},
        ["I06-HelpWirelessA"]  = {open = "btnOpenHelpWirelessA",  close = "btnCloseHelpWirelessA"},
        ["I07-HelpWirelessB"]  = {open = "btnOpenHelpWirelessB",  close = "btnCloseHelpWirelessB"},
        ["I08-HelpRouting"]    = {open = "btnOpenHelpRouting",    close = "btnCloseHelpRouting"},
        ["I10-HelpStreamMusic"]= {open = "btnOpenHelpStreamMusic",close = "btnCloseHelpStreamMusic"},
    }
    
    -- Generate layer arrays from source map to avoid repetition
    self.allUSBConnectLayers = {}
    self.allConferenceLayers = {}
    self.allCameraLayers = {}
    self.allVideoPrivacyLayers = {}
    
    for _, src in pairs(self.sources) do
        if src.usbConnect then table.insert(self.allUSBConnectLayers, src.usbConnect) end
        if src.confLayer then table.insert(self.allConferenceLayers, src.confLayer) end
        if src.cameraLayer then table.insert(self.allCameraLayers, src.cameraLayer) end
        if src.videoPrivacySeparate then table.insert(self.allVideoPrivacyLayers, src.videoPrivacySeparate) end
        if src.videoPrivacyCombine then table.insert(self.allVideoPrivacyLayers, src.videoPrivacyCombine) end
    end
    
    -- ACPR layer constants
    self.acprLayers = {
        combined = "J06-ACPRActiveCombined",
        separated = "J07-ACPRActiveSeparated"
    }
    self.acprBtnLayers = {
        combined = "J09-ACPRBtnCombined",
        separated = "J10-ACPRBtnSeparated"
    }
    
    return self
end

function UCIController:debugPrint(msg)
    if self.debugging then 
        print("[" .. self.uciPage .. "] " .. msg) 
    end
end

-------------------[ Layer Visibility Methods ]-------------------
-- Called from: showLayer(), updateLayerVisibility(), all sublayer update methods
function UCIController:safeSetLayerVisibility(layer, visible, transition)
    local ok, err = pcall(function()
        Uci.SetLayerVisibility(self.uciPage, layer, visible, transition or "none")
    end)
    if ok then
        self.layerStates[layer] = visible
        self:debugPrint("Layer '" .. layer .. "' -> " .. tostring(visible))
    else
        self:debugPrint("Warning: Layer '" .. layer .. "' not found: " .. tostring(err))
    end
    return ok
end

-- Called from: showLayer(), all update methods
function UCIController:updateLayerVisibility(layers, visible, transition)
    if not layers or visible == nil then return end
    
    -- Loop through all layers and update visibility
    forEach(layers, function(i, layer)
        if layer then
            local current = self.layerStates[layer]
            -- Only update if not initialized yet OR if state changed
            if not self.isInitialized or current ~= visible then
                self:safeSetLayerVisibility(layer, visible, transition)
            end
        end
    end)
end

-- Called from: showLayer() when layer config specifies hideBase=true
function UCIController:hideBaseLayers()
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
end

-- Main layer show function - orchestrates all layer visibility
-- Called from: btnNavEventHandler() when user navigates, startSystem(), shutdownSystem()
function UCIController:showLayer()
    -- Step 1: Hide everything first for clean slate
    self:updateLayerVisibility(layersToHide, false, "none")
    -- Step 2: Base layers always visible unless config hides them
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")
    -- Step 3: Update navigation visibility based on room state
    self:updateNavigationVisibility()
    -- Step 4: Build layer configurations if not already cached
    if not self.layerConfigs then
        self.layerConfigs = self:buildLayerConfigs()
    end

    local active = self.varActiveLayer
    local config = self.layerConfigs[active]
    if not config then return end

    -- Step 5: Handle conditional layers (divisible space dependent)
    if config.conditional then
        if config.showRoomControls then
            local layerName = self:getRoomControlsLayerName()
            if not layerName then
                self:debugPrint("RoomControls layer not available")
                return
            end
            config.show = {layerName}
        else
            local ok = self:shouldShowLayer(active)
            if not ok then
                self:debugPrint("Layer " .. tostring(active) .. " hidden by divisible-space state")
                return
            end
        end
    end

    -- Step 6: Hide base if config specifies
    if config.hideBase then
        self:hideBaseLayers()
    end

    -- Step 7: Show layers specified in config
    if config.show then
        self:updateLayerVisibility(config.show, true, "fade")
    end
    
    -- Step 8: Hide specific layers if config specifies
    if config.hide then
        self:updateLayerVisibility(config.hide, false, "none")
    end
    
    -- Step 9: Execute callbacks (update sublayers)
    if config.call then
        for i = 1, #config.call do
            config.call[i]()
        end
    end
end

-- Build layer configuration map (data-driven layer management)
-- Called from: showLayer() on first use
function UCIController:buildLayerConfigs()
    return {
        [self.kLayerAlarm] = {
            show = {"A01-Alarm"},
            hideBase = true
        },
        [self.kLayerIncomingCall] = {
            show = {"B01-IncomingCall"}
        },
        [self.kLayerStart] = {
            show = {"C05-Start"},
            hideBase = true
        },
        [self.kLayerWarming] = {
            show = {"E05-SystemProgress","E01-SystemProgressWarming"},
            hideBase = true
        },
        [self.kLayerCooling] = {
            show = {"E05-SystemProgress","E02-SystemProgressCooling"},
            hideBase = true
        },
        [self.kLayerRoomControls] = {
            conditional = true,
            showRoomControls = true,
            hide = {"X01-ProgramVolume"},
            call = {function() self:updateCallActiveState() end}
        },
        [self.kLayerPCA] = {
            conditional = true,
            show = {"P01-PCA"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updateConferenceControlsLayer() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updatePCAHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerPCB] = {
            conditional = true,
            show = {"P02-PCB"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updateConferenceControlsLayer() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updatePCBHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerLaptopA] = {
            conditional = true,
            show = {"L01-LaptopA"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updateConferenceControlsLayer() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updateLaptopAHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerLaptopB] = {
            conditional = true,
            show = {"L02-LaptopB"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updateConferenceControlsLayer() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updateLaptopBHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerWireless] = {
            show = {"W05-Wireless"},
            call = {
                function() self:updateWirelessHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerRouting] = {
            show = {"R10-Routing"},
            call = {
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerDialer] = {
            show = {"V05-Dialer"},
            call = {
                function() self:updateDialerHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerStreamMusic] = {
            show = {"S10-StreamMusic"},
            call = {
                function() self:updateStreamMusicHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerRoomCombining] = {
            show = {"H04-RoomCombining"},
            hideBase = true,
            call = {
                function() self:updateCallActiveState() end,
                function() self:resetTouchInactivityTimer() end,
            }
        }
    }
end

-------------------[ Source & Sublayer Methods ]-------------------
-- Get the active source data based on current layer
-- Called from: updateHDMIForActiveSource(), updateConferenceState(), updateACPRBypassState()
function UCIController:getActiveSource()
    local key = self.layerToSource[self.varActiveLayer]
    return key and self.sources[key] or nil
end

-- Check if HDMI is connected for the active source
-- Called from: updateConferenceState(), updateACPRBypassState(), updateConferenceControlsLayer()
function UCIController:checkHDMIConnection()
    local src = self:getActiveSource()
    if not src then return true end  -- No source = allow operation (optimistic for guard clauses)
    if not src.hdmiPin then return false end  -- No hdmiPin = disconnected
    return src.hdmiPin.Boolean
end

-- Sync help button states with layer visibility
-- Called from: updateHDMIForActiveSource(), updateConferenceState(), updateSourceHelpState()
function UCIController:syncHelpButtonStates(helpLayer)
    local map = self.helpLayerButtonMap[helpLayer]
    if not map then return end
    
    local visible = self.layerStates[helpLayer] == true
    local openBtn = controls[map.open]
    local closeBtn = controls[map.close]
    
    setProp(openBtn, "Boolean", visible)
    setProp(closeBtn, "Boolean", false)
end

-- Called from: Layer configs for all main layers, pinCallActive EventHandler
function UCIController:updateCallActiveState()
    local isActive = controls.pinCallActive.Boolean or false
    self:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    self:debugPrint("Call Active: " .. (isActive and "Showing" or "Hiding"))
end

-- Called from: Layer configs for source layers, pinLEDPresetSaved EventHandler
function UCIController:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved.Boolean or false
    self:updateLayerVisibility({"J08-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    self:debugPrint("Preset Saved: " .. (isVisible and "Showing" or "Hiding"))
end

-- Generic HDMI handler using source map (This handles both HDMI connected and disconnected states)
-- Called from: Layer configs when navigating to source layers, HDMI connection pin EventHandlers
function UCIController:updateHDMIForActiveSource()
    local src = self:getActiveSource()
    if not src then return end

    local isConnected = self:checkHDMIConnection()
    
    if isConnected then
        -- HDMI is connected: show normal source layer
        self:updateLayerVisibility({src.baseLayer}, true, "fade")
        self:updateLayerVisibility({src.discLayer}, false, "none")
        self:debugPrint("HDMI " .. src.baseLayer .. ": Connected")
        return
    end

    -- HDMI disconnected: show disconnect layer and hide everything else
    self:updateLayerVisibility({src.discLayer}, true, "fade")
    self:updateLayerVisibility({src.baseLayer, src.confLayer, src.helpLayer}, false, "none")
    
    -- Sync help button state
    if src.helpLayer then
        self:syncHelpButtonStates(src.helpLayer)
    end
    
    self:debugPrint("HDMI " .. src.baseLayer .. ": Disconnected")
end

-- Generic source help handler
-- Called from: updatePCAHelpState(), updatePCBHelpState(), updateLaptopAHelpState(), updateLaptopBHelpState()
function UCIController:updateSourceHelpState(srcKey)
    local src = self.sources[srcKey]
    if not src then return end

    -- HDMI gate: help hidden if HDMI is not connected
    if not self:checkHDMIConnection() then
        self:updateLayerVisibility({src.helpLayer}, false, "none")
        self:syncHelpButtonStates(src.helpLayer)
        self:debugPrint(srcKey .. " Help: Hiding (HDMI not connected)")
        return
    end

    local isVisible = src.btnOpen.Boolean or false
    
    if isVisible then
        -- Show help layer and hide conference controls
        self:updateLayerVisibility({src.helpLayer}, true, "fade")
        -- Hide all conference and USB connect layers using generated arrays
        local hideLayers = {}
        for _, layer in ipairs(self.allConferenceLayers) do table.insert(hideLayers, layer) end
        for _, layer in ipairs(self.allUSBConnectLayers) do table.insert(hideLayers, layer) end
        self:updateLayerVisibility(hideLayers, false, "none")
    else
        -- Hide help layer and restore conference state
        self:updateLayerVisibility({src.helpLayer}, false, "none")
        self:updateConferenceState()
    end

    self:syncHelpButtonStates(src.helpLayer)
    self:debugPrint(srcKey .. " Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Specific help state updaters (wrappers around generic handler)
function UCIController:updatePCAHelpState()   self:updateSourceHelpState("PCA")   end
function UCIController:updatePCBHelpState()   self:updateSourceHelpState("PCB")   end
function UCIController:updateLaptopAHelpState() self:updateSourceHelpState("LaptopA") end
function UCIController:updateLaptopBHelpState() self:updateSourceHelpState("LaptopB") end

-- Conference state (USB) handler using source map
-- Called from: Layer configs when navigating to source layers, USB pin EventHandlers
function UCIController:updateConferenceState()
    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate: conference controls require HDMI connection
    if not self:checkHDMIConnection() then
        local hideLayers = {}
        for _, layer in ipairs(self.allUSBConnectLayers) do table.insert(hideLayers, layer) end
        for _, layer in ipairs(self.allConferenceLayers) do table.insert(hideLayers, layer) end
        if src.helpLayer then table.insert(hideLayers, src.helpLayer) end
        
        self:updateLayerVisibility(hideLayers, false, "none")
        
        if src.helpLayer then 
            self:syncHelpButtonStates(src.helpLayer) 
        end
        
        self:debugPrint("Conference blocked: HDMI not connected")
        return
    end

    -- Config skip for laptops (if configured to skip USB check)
    if src.layerConst == self.kLayerLaptopA and conferenceStateConfig.skipLaptopA then return end
    if src.layerConst == self.kLayerLaptopB and conferenceStateConfig.skipLaptopB then return end

    local usbConnected = src.usbPin and src.usbPin.Boolean or false
    
    if usbConnected then
        -- USB connected: show conference controls
        self:updateLayerVisibility({src.confLayer}, true, "fade")
        self:updateLayerVisibility(self.allUSBConnectLayers, false, "none")
    else
        -- USB not connected: show "Connect USB" prompt
        self:updateLayerVisibility({src.usbConnect}, true, "fade")
        self:updateLayerVisibility({src.confLayer, src.helpLayer}, false, "none")
        
        if src.helpLayer then 
            self:syncHelpButtonStates(src.helpLayer) 
        end
    end
    
    self:debugPrint("Conference: " .. src.confLayer .. " " .. (usbConnected and "Connected" or "Disconnected"))
end

-- Called from: Layer configs when navigating to source layers, ACPR bypass pin EventHandlers
function UCIController:updateACPRBypassState()
    -- Check if ACPR display is disabled in configuration
    if acprConfig.disableACPRShow then
        self:updateLayerVisibility({
            self.acprLayers.combined, self.acprLayers.separated
        }, false, "none")
        self:debugPrint("ACPR Show logic disabled via acprConfig")
        return
    end

    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate: ACPR requires HDMI connection
    if not self:checkHDMIConnection() then
        self:debugPrint("ACPR bypass check blocked: HDMI not connected")
        return
    end

    -- Get room state to determine which control and layers to use
    local roomState = self:getRoomState()
    local isSeparated = (roomState == "separated")
    
    local bypassControl = isSeparated and controls.pinLEDACPRBypassSeparated or controls.pinLEDACPRBypassCombined
    local acprActiveLayer = isSeparated and self.acprLayers.separated or self.acprLayers.combined
    local acprInactiveLayer = isSeparated and self.acprLayers.combined or self.acprLayers.separated
    
    local isBypassActive = bypassControl.Boolean or false
    
    -- Hide the inactive ACPR layer for the current room state
    self:updateLayerVisibility({acprInactiveLayer}, false, "none")

    -- Show/hide appropriate layers based on bypass state
    if not isBypassActive then
        -- ACPR is active (NOT bypassed): show ACPR active layer, hide conference controls
        self:updateLayerVisibility({acprActiveLayer}, true, "fade")
        self:updateLayerVisibility({src.confLayer}, false, "none")
    else
        -- ACPR is bypassed: show conference controls, hide ACPR active layer
        self:updateLayerVisibility({src.confLayer}, true, "fade")
        self:updateLayerVisibility({acprActiveLayer}, false, "none")
    end
    
    self:debugPrint("ACPR Bypass (" .. roomState .. "): " .. (isBypassActive and "Active" or "Inactive"))
    
    -- Update ACPR button visibility after bypass state changes
    self:updateConferenceControlsLayer()
end

-- Conference Controls Layer - comprehensive visibility management for all conference-related layers
-- Called from: Layer configs, updateACPRBypassState(), onRoomStateChanged()
-- Determine layer visibility for a single source
function UCIController:determineSourceLayerVisibility(src, isActive, usbConnected, isCombined, showLayers, hideLayers)
    local conferenceIsActive = false
    
    -- Camera selection: show only for active source when combined
    if src.cameraLayer then
        if isActive and isCombined then
            table.insert(showLayers, src.cameraLayer)
        else
            table.insert(hideLayers, src.cameraLayer)
        end
    end
    
    -- Conference controls: show if USB connected and active
    if isActive and usbConnected then
        table.insert(showLayers, src.confLayer)
        conferenceIsActive = true
    else
        table.insert(hideLayers, src.confLayer)
    end
    
    -- Video privacy: show based on room state and conference controls
    if src.videoPrivacySeparate and src.videoPrivacyCombine then
        if isActive and usbConnected then
            if isCombined then
                table.insert(showLayers, src.videoPrivacyCombine)
                table.insert(hideLayers, src.videoPrivacySeparate)
            else
                table.insert(showLayers, src.videoPrivacySeparate)
                table.insert(hideLayers, src.videoPrivacyCombine)
            end
        else
            table.insert(hideLayers, src.videoPrivacySeparate)
            table.insert(hideLayers, src.videoPrivacyCombine)
        end
    end
    
    return conferenceIsActive
end

-- Determine ACPR button visibility
function UCIController:determineACPRButtonVisibility(anyConferenceActive, isCombined, showLayers, hideLayers)
    if not acprConfig.disableACPRShow and anyConferenceActive then
        if isCombined then
            table.insert(showLayers, self.acprBtnLayers.combined)
            table.insert(hideLayers, self.acprBtnLayers.separated)
        else
            table.insert(showLayers, self.acprBtnLayers.separated)
            table.insert(hideLayers, self.acprBtnLayers.combined)
        end
    else
        table.insert(hideLayers, self.acprBtnLayers.combined)
        table.insert(hideLayers, self.acprBtnLayers.separated)
    end
end

-- Conference Controls Layer - orchestrates visibility updates
function UCIController:updateConferenceControlsLayer()
    -- HDMI gate: hide all conference-related layers if HDMI not connected
    if not self:checkHDMIConnection() then
        local allHideLayers = {}
        for _, layer in ipairs(self.allCameraLayers) do table.insert(allHideLayers, layer) end
        for _, layer in ipairs(self.allConferenceLayers) do table.insert(allHideLayers, layer) end
        for _, layer in ipairs(self.allVideoPrivacyLayers) do table.insert(allHideLayers, layer) end
        table.insert(allHideLayers, self.acprBtnLayers.combined)
        table.insert(allHideLayers, self.acprBtnLayers.separated)
        
        self:updateLayerVisibility(allHideLayers, false, "none")
        self:debugPrint("Conference controls blocked: HDMI not connected")
        return
    end
    
    local roomState = self:getRoomState()
    local isCombined = (roomState ~= "separated")
    
    -- Determine which layers to show based on active source and room state
    local showLayers = {}
    local hideLayers = {}
    local anyConferenceActive = false
    
    -- Loop through all sources and determine visibility for each
    for srcKey, src in pairs(self.sources) do
        local isActive = (self.varActiveLayer == src.layerConst)
        local usbConnected = src.usbPin and src.usbPin.Boolean or false
        
        -- Track if any conference controls are active while building layer lists
        local conferenceIsActive = self:determineSourceLayerVisibility(
            src, isActive, usbConnected, isCombined, showLayers, hideLayers
        )
        if conferenceIsActive then
            anyConferenceActive = true
        end
    end
    
    -- Determine ACPR button visibility based on conference state
    self:determineACPRButtonVisibility(anyConferenceActive, isCombined, showLayers, hideLayers)
    
    -- Apply visibility changes to all layers in our lists
    for i = 1, #showLayers do
        self:updateLayerVisibility({showLayers[i]}, true, "fade")
    end
    for i = 1, #hideLayers do
        self:updateLayerVisibility({hideLayers[i]}, false, "none")
    end
    
    self:debugPrint("Conference controls updated: " .. #showLayers .. " shown, " .. #hideLayers .. " hidden")
end

-- Called from: Layer configs when navigating to wireless layer, wireless help button EventHandlers
function UCIController:updateWirelessHelpState()
    local isVisible = controls.btnOpenHelpWirelessA.Boolean or false
    self:updateLayerVisibility({"I06-HelpWirelessA"}, isVisible, "none")
    self:syncHelpButtonStates("I06-HelpWirelessA")
    self:debugPrint("Wireless Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Called from: Routing help button EventHandlers
function UCIController:updateRoutingHelpState()
    local isVisible = controls.btnOpenHelpRouting.Boolean or false
    self:updateLayerVisibility({"I08-HelpRouting"}, isVisible, "none")
    self:syncHelpButtonStates("I08-HelpRouting")
    self:debugPrint("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Called from: Layer configs when navigating to dialer layer, dialer help button EventHandler
function UCIController:updateDialerHelpState()
    local isVisible = controls.btnHelpDialer.Boolean or false
    self:updateLayerVisibility({"I09-HelpDialer"}, isVisible, "none")
    self:debugPrint("Dialer Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Called from: Layer configs when navigating to stream music layer, stream music help button EventHandlers
function UCIController:updateStreamMusicHelpState()
    local isVisible = controls.btnOpenHelpStreamMusic.Boolean or false
    self:updateLayerVisibility({"I10-HelpStreamMusic"}, isVisible, "none")
    self:syncHelpButtonStates("I10-HelpStreamMusic")
    self:debugPrint("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
end

-------------------[ Video Switcher Methods ]-------------------
UCIController.SwitcherTypes = {
    AVProEdge = {
        componentType = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
        switcherNames = {"devAVProEdge", "compAVProEdge"},
        routingMethod = "trigger",
        outputMappings = {
            CollabA = {
                [7] = "Input 3",   -- kLayerPCA -> Input 3
                [8] = "Input 4",   -- kLayerPCB -> Input 4
                [9] = "Input 1",   -- kLayerLaptopA -> Input 1
                [10] = "Input 2"   -- kLayerLaptopB -> Input 2
            },
            CollabB = {
                [7] = "Input 7",   -- kLayerPCA -> Input 7
                [8] = "Input 8",   -- kLayerPCB -> Input 8
                [9] = "Input 5",   -- kLayerLaptopA -> Input 5
                [10] = "Input 6"   -- kLayerLaptopB -> Input 6
            }
        }
    }
}

-- Initialize video switcher (auto-detect and setup)
-- Called from: init()
function UCIController:initializeVideoSwitcher()
    local switcherType, componentName = self:autoDetectSwitcher()
    if not switcherType then
        self:debugPrint("No video switcher detected")
        return false
    end
    
    local success, component = pcall(function() return Component.New(componentName) end)
    if not success or not component then
        self:debugPrint("Failed to create switcher component: " .. componentName)
        return false
    end
    
    self.videoSwitcherType = switcherType
    self.switcherComponent = component
    self.videoSwitcherEnabled = true
    self:debugPrint("Video switcher initialized: " .. switcherType)
    return true
end

-- Auto-detect video switcher in design
-- Called from: initializeVideoSwitcher()
function UCIController:autoDetectSwitcher()
    -- Check UCI variables first
    for switcherType, config in pairs(self.SwitcherTypes) do
        for i = 1, #config.switcherNames do
            local switchName = config.switcherNames[i]
            if Controls[switchName] and Controls[switchName].String ~= "" then
                return switcherType, Controls[switchName].String
            end
        end
    end
    
    -- Check available components
    local components = Component.GetComponents()
    for switcherType, config in pairs(self.SwitcherTypes) do
        for _, comp in pairs(components) do
            if comp.Type == config.componentType then
                return switcherType, comp.Name
            end
        end
    end
    
    return nil, nil
end

-- Switch video input based on UCI button
-- Called from: btnNavEventHandler() whenever user navigates
function UCIController:switchToInput(uciButton)
    if not self.videoSwitcherEnabled then return false end
    if not self.switcherComponent then return false end
    if not uciButton then return false end
    
    local config = self.SwitcherTypes[self.videoSwitcherType]
    if not config then return false end
    
    -- Get room identity to determine correct input mapping
    local roomIdentity = self:getCurrentRoom()
    
    if not roomIdentity then
        self:debugPrint("Cannot switch: Room identity not determined")
        return false
    end
    
    local inputMapping = config.outputMappings and config.outputMappings[roomIdentity]
    if not inputMapping then
        self:debugPrint("Cannot switch: No output mapping for room " .. roomIdentity)
        return false
    end
    
    local inputControlName = inputMapping[uciButton]
    if not inputControlName then
        self:debugPrint("No input mapping for UCI button " .. uciButton .. " in room " .. roomIdentity)
        return false
    end
    
    self:debugPrint("Switching to " .. inputControlName .. " via UCI button " .. uciButton .. " (Room: " .. roomIdentity .. ")")
    
    local success, err = pcall(function()
        if self.switcherComponent[inputControlName] then
            self.switcherComponent[inputControlName]:Trigger()
            return true
        else
            self:debugPrint("Warning: Control " .. inputControlName .. " not found on switcher")
            return false
        end
    end)
    
    if not success then
        self:debugPrint("Failed to switch: " .. tostring(err))
        return false
    end
    
    self:debugPrint("Successfully switched to " .. inputControlName)
    return true
end

-------------------[ Room Automation Methods ]-------------------
-- Called from: init()
function UCIController:initializeRoomControlsComponent()
    local componentName = nil
    
    -- Try to get component name from UCI Variables
    if Uci.Variables.compRoomControls then componentName = Uci.Variables.compRoomControls.String end
    
    -- Fallback: construct name from page name
    if not componentName then
        local pageName = self.uciPage:match("uci%s+([^(]+)")
        if pageName then
            componentName = "compRoomControls" .. pageName:gsub("%s+", "")
        end
    end
    
    if not componentName then
        self:debugPrint("Could not determine Room Controls component name")
        return false
    end
    
    local success, component = pcall(function() return Component.New(componentName) end)
    if success and component then
        self.roomControlsComponent = component
        self:debugPrint("Room Controls Component referenced: " .. componentName)
        
        -- use ledSystemPower as authoritative status indicator [[memory:10919377]]
        if self.roomControlsComponent["ledSystemPower"] then
            self.previousPowerState = self.roomControlsComponent["ledSystemPower"].Boolean
            self:debugPrint("Initial power state: " .. tostring(self.previousPowerState))
        end
        
        return true
    else
        self:debugPrint("Room Controls Component not found: " .. componentName)
        return false
    end
end

-- Power on the system
-- Called from: startSystem(), ensureSystemIsOn()
function UCIController:powerOn()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debugPrint("Cannot power on: Room Controls component not available")
        return false
    end
    
    -- Set btnSystemOnOff control to trigger power on (ledSystemPower will update via SystemAutomationController) [[memory:10919377]]
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = true end)
    if ok then 
        self:debugPrint("Room powered ON") 
    else 
        self:debugPrint("Failed to power on room automation") 
    end
    return ok
end

-- Power off the system
-- Called from: shutdownSystem()
function UCIController:powerOff()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debugPrint("Cannot power off: Room Controls component not available")
        return false
    end
    
    -- Set btnSystemOnOff control to trigger power off (ledSystemPower will update via SystemAutomationController) [[memory:10919377]]
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = false end)
    if ok then 
        self:debugPrint("Room powered OFF") 
    else 
        self:debugPrint("Failed to power off room automation") 
    end
    return ok
end

-- Get timing values from room controls component
-- Called from: startLoadingBar()
function UCIController:getTiming(isPoweringOn)
    if self.roomControlsComponent then
        local success, result = pcall(function()
            if isPoweringOn then
                return self.roomControlsComponent["warmupTime"] and self.roomControlsComponent["warmupTime"].Value or 10
            else
                return self.roomControlsComponent["cooldownTime"] and self.roomControlsComponent["cooldownTime"].Value or 5
            end
        end)
        if success and result then
            self:debugPrint("Using component timing: " .. result .. " seconds")
            return result
        end
    end
    
    -- Fallback to UCI variables
    local duration = isPoweringOn and 
        (tonumber(Uci.Variables.timeProgressWarming) or 10) or
        (tonumber(Uci.Variables.timeProgressCooling) or 5)
    
    self:debugPrint("Using UCI timing: " .. duration .. " seconds")
    return duration
end

-- Synchronize with Room Controls state changes
-- Called from: syncTimer EventHandler (every 1 second)
function UCIController:syncRoomControlsState()
    -- use ledSystemPower as authoritative status [[memory:10919377]]
    if not self.roomControlsComponent or not self.roomControlsComponent["ledSystemPower"] then
        return
    end
    
    local currentState = self.roomControlsComponent["ledSystemPower"].Boolean
    
    -- Only act if state has changed
    if currentState == self.previousPowerState then
        return
    end
    
    self:debugPrint("Power state changed: " .. tostring(self.previousPowerState) .. " -> " .. tostring(currentState))
    self.previousPowerState = currentState
    
    if currentState then
        -- System powered on externally
        self:startLoadingBar(true)
        self:btnNavEventHandler(self.kLayerWarming)
        self:debugPrint("Synchronized to WARMING state")
    else
        -- System powered off externally
        self:startLoadingBar(false)
        self:btnNavEventHandler(self.kLayerCooling)
        self:debugPrint("Synchronized to COOLING state")
    end
end

-------------------[ Progress Bar Methods ]-------------------
-- Start loading bar animation
-- Called from: startSystem(), shutdownSystem(), syncRoomControlsState()
function UCIController:startLoadingBar(isPoweringOn)
    if self.isAnimating then return end
    
    self.isAnimating = true
    local duration = self:getTiming(isPoweringOn)
    local steps = 100
    local interval = duration / steps
    local currentStep = 0
    
    -- Clean up existing timers
    if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
    if self.timeoutTimer then self.timeoutTimer:Stop(); self.timeoutTimer = nil end
    
    self.loadingTimer = Timer.New()
    self.timeoutTimer = Timer.New()
    
    -- Set initial progress
    controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
    
    -- Safety timeout (5 minutes max)
    self.timeoutTimer.EventHandler = function()
        if self.isAnimating then
            self:debugPrint("Loading bar timeout reached")
            self.isAnimating = false
            if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
            self:btnNavEventHandler(isPoweringOn and self.defaultActiveLayer or self.kLayerStart)
        end
    end
    self.timeoutTimer:Start(300)
    
    -- Progress animation timer
    self.loadingTimer.EventHandler = function()
        currentStep = currentStep + 1
        
        -- Calculate progress (0->100 for power on, 100->0 for power off)
        local progress = isPoweringOn and currentStep or (100 - currentStep)
        controls.knbProgressBar.Value = progress
        controls.txtProgressBar.String = progress .. "%"
        
        if currentStep >= steps then
            -- Animation complete
            self.loadingTimer:Stop()
            self.timeoutTimer:Stop()
            self.isAnimating = false
            
            -- Navigate to appropriate layer
            local targetLayer
            if isPoweringOn then
                targetLayer = self:getDefaultLayerAfterWarming()
            else
                targetLayer = self.kLayerStart
            end
            self:btnNavEventHandler(targetLayer)
        else
            -- Continue animation
            self.loadingTimer:Start(interval)
        end
    end
    
    self.loadingTimer:Start(interval)
    self:debugPrint("Loading bar started (" .. duration .. "s)")
end

-------------------[ Divisible Space Methods ]-------------------
-- Initialize Divisible Space functionality
-- Called from: init()
function UCIController:initializeDivisibleSpace()
    -- Parse room identity from page name
    self:parseRoomIdentity()
    
    local success, component = pcall(function()
        return Component.New("compDivisibleSpaceControls")
    end)
    
    if success and component then
        self.compDivisibleSpaceControls = component
        self.divisibleSpaceEnabled = true
        self:debugPrint("DivisibleSpaceControls component referenced successfully")
        
        self:cacheBtnRoomState()
        self:registerRoomStateChangeHandlers()
        self:updateNavigationVisibility()
        self:updateStartSystemLegend()
    else
        self:debugPrint("DivisibleSpaceControls component not found (feature disabled)")
        self.divisibleSpaceEnabled = false
        
        -- Still update navigation (all visible if not divisible space)
        self:updateNavigationVisibility()
        self:updateStartSystemLegend()
    end
    
    return self.divisibleSpaceEnabled
end

-- Cache btnRoomState array for performance
-- Called from: initializeDivisibleSpace()
function UCIController:cacheBtnRoomState()
    if not self.compDivisibleSpaceControls then
        self.btnRoomState = nil
        return
    end
    
    self.btnRoomState = {
        self.compDivisibleSpaceControls["btnRoomState 1"],
        self.compDivisibleSpaceControls["btnRoomState 2"],
        self.compDivisibleSpaceControls["btnRoomState 3"]
    }
    
    self:debugPrint("btnRoomState array cached (" .. #self.btnRoomState .. " controls)")
end

-- Parse room identity from component name
-- Called from: initializeDivisibleSpace()
function UCIController:parseRoomIdentity()
    if not Uci.Variables.compRoomControls then
        self:debugPrint("Warning: Uci.Variables.compRoomControls not found")
        return
    end
    
    local roomControlsName = Uci.Variables.compRoomControls.String or ""
    
    if roomControlsName:find("CollabA") then
        self.roomIdentity = "CollabA"
        self:debugPrint("Room identity detected: Collab A")
    elseif roomControlsName:find("CollabB") then
        self.roomIdentity = "CollabB"
        self:debugPrint("Room identity detected: Collab B")
    else
        self:debugPrint("Warning: Could not determine room identity from: " .. roomControlsName)
    end
end

-- Get current room identity
-- Called from: switchToInput(), updateNavigationVisibility()
function UCIController:getCurrentRoom()
    return self.roomIdentity
end

-- Get room state (separated, combinedA, or combinedB)
-- Called from: updateACPRBypassState(), updateConferenceControlsLayer(), getDefaultLayerAfterWarming(), shouldShowLayer(), getRoomControlsLayerName(), updateNavigationVisibility(), updateStartSystemLegend()
function UCIController:getRoomState()
    if not self.divisibleSpaceEnabled or not self.btnRoomState then
        return "separated"
    end
    
    if not self.btnRoomState[1] then
        return "separated"
    end
    
    if self.btnRoomState[1] and self.btnRoomState[1].Boolean then
        return "separated"
    elseif self.btnRoomState[2] and self.btnRoomState[2].Boolean then
        return "combinedA"
    elseif self.btnRoomState[3] and self.btnRoomState[3].Boolean then
        return "combinedB"
    end
    
    return "separated"
end

-- Get default layer to navigate to after warming completes
-- Called from: startLoadingBar() when warming completes
function UCIController:getDefaultLayerAfterWarming()
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    self:debugPrint("Determining default layer: State=" .. roomState .. ", Room=" .. tostring(roomIdentity))
    
    if roomState == "separated" then
        if roomIdentity == "CollabA" then
            return self.kLayerPCA
        elseif roomIdentity == "CollabB" then
            return self.kLayerPCB
        else
            return self.kLayerPCA
        end
    elseif roomState == "combinedA" then
        return self.kLayerPCA
    elseif roomState == "combinedB" then
        return self.kLayerPCB
    end
    
    return self.kLayerRouting
end

-- Check if a layer should be shown based on divisible space state
-- Called from: showLayer() for conditional layers
function UCIController:shouldShowLayer(layerIndex)
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    -- Define which layers are available in each room when separated
    local layerAvailability = {
        CollabA = {
            [self.kLayerPCA] = true,
            [self.kLayerLaptopA] = true
        },
        CollabB = {
            [self.kLayerPCB] = true,
            [self.kLayerLaptopB] = true
        }
    }
    
    if roomState == "combinedA" or roomState == "combinedB" then
        return true --[[ All layers are available when rooms are combined ]]
    end
    
    -- When separated, check layer availability for this room
    if roomState == "separated" and layerAvailability[roomIdentity] then
        local isAvailable = layerAvailability[roomIdentity][layerIndex]
        if isAvailable ~= nil then
            return isAvailable --[[ Layer is available for this room ]]
        end
    end
    return true --[[ Default: allow layer to be shown ]]
end

-- Get the appropriate room controls layer name based on room state
-- Called from: showLayer() when showing kLayerRoomControls
function UCIController:getRoomControlsLayerName()
    local roomState = self:getRoomState()
    local isSeparated = (roomState == "separated")
    
    if isSeparated then
        return "H09-RoomControlsSeparated"
    else
        return "H08-RoomControlsCombined"
    end
end

-- Update navigation button visibility based on room state
-- Called from: showLayer(), initializeDivisibleSpace(), onRoomStateChanged()
function UCIController:updateNavigationVisibility()
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    local isSeparated = (roomState == "separated")
    
    self:debugPrint(string.format("Updating navigation visibility: Room=%s, State=%s", 
        tostring(roomIdentity), roomState))
    
    -- Define which nav buttons to control per room
    local navConfig = {
        CollabA = {
            {num = "08", label = "PCB"},
            {num = "10", label = "LaptopB"}
        },
        CollabB = {
            {num = "07", label = "PCA"},
            {num = "09", label = "LaptopA"}
        }
    }
    
    local controlsToUpdate = navConfig[roomIdentity]
    if not controlsToUpdate then return end
    
    -- Helper function to set visibility on button and label
    local function setNavVisibility(num, label, isInvisible)
        local controlNames = {"btnNav" .. num, "txtNav" .. num}
        
        for i = 1, #controlNames do
            local controlName = controlNames[i]
            setProp(controls[controlName], "IsInvisible", isInvisible)
            self:debugPrint(string.format("%s (%s) IsInvisible = %s", controlName, label, tostring(isInvisible)))
        end
    end
    
    -- Update visibility for opposite room's nav buttons
    for i = 1, #controlsToUpdate do
        local config = controlsToUpdate[i]
        setNavVisibility(config.num, config.label, isSeparated)
    end
end

-- Update Start System button legend based on room state
-- Called from: initializeDivisibleSpace(), onRoomStateChanged()
function UCIController:updateStartSystemLegend()
    local roomState = self:getRoomState()
    local legend = (roomState == "separated") and "Start Room" or "Start Rooms"
    
    setProp(controls.btnStartSystem, "Legend", legend)
    self:debugPrint("Start System button legend updated: " .. legend .. " (State: " .. roomState .. ")")
end

-- Register room state change event handlers
-- Called from: initializeDivisibleSpace()
function UCIController:registerRoomStateChangeHandlers()
    if not self.btnRoomState or not self.btnRoomState[1] then
        return
    end
    
    -- Register event handler for each room state button
    for i = 1, #self.btnRoomState do
        local btn = self.btnRoomState[i]
        bind(btn, function(ctl)
            self:onRoomStateChanged(i, ctl.Boolean)
        end)
    end
end

-- Handle room state changes
-- Called from: btnRoomState EventHandlers
function UCIController:onRoomStateChanged(buttonIndex, state)
    if not state then return end
    
    -- Update navigation visibility if navbar is visible
    if self.layerStates["Y01-Navbar"] then
        self:updateNavigationVisibility()
        self:updateStartSystemLegend()
    end
    
    -- Always update start system legend
    self:updateStartSystemLegend()
    
    -- Update conference controls layer for room state change
    self:updateConferenceControlsLayer()
end

-------------------[ Touch Inactivity Handler ]-------------------
-- Handle room combining inactivity timeout
-- Called from: uciTouchInactivityTimer EventHandler
function UCIController:onRoomCombiningInactivity()
    if self.varActiveLayer == self.kLayerRoomCombining then
        self:debugPrint("Touch inactivity timeout - returning to Start layer")
        self:btnNavEventHandler(self.kLayerStart)
    end
end

-- Reset touch inactivity timer
-- Called from: kLayerRoomCombining config callback, pinLEDTouchActivity EventHandler
function UCIController:resetTouchInactivityTimer()
    self.uciTouchInactivityTimer:Stop()
    
    local isOnRoomCombining = (self.varActiveLayer == self.kLayerRoomCombining)
    
    if isOnRoomCombining then
        local timeout = tonumber(Uci.Variables.numTouchInactivityTimer.Value) or 60
        if timeout <= 0 then
            timeout = 60
            self:debugPrint("Warning: Invalid timeout value, using default 60s")
        end
        
        self.uciTouchInactivityTimer.EventHandler = function() self:onRoomCombiningInactivity() end
        self.uciTouchInactivityTimer:Start(timeout)
        self:debugPrint("Touch inactivity timer reset (" .. timeout .. "s)")
    else
        self:debugPrint("Touch inactivity timer not started (not on RoomCombining layer)")
    end
end

-------------------[ System Control Methods ]-------------------
-- Start the system (power on and begin warming)
-- Called from: btnStartSystem EventHandler
function UCIController:startSystem()
    self:powerOn()
    self:startLoadingBar(true)
    self:btnNavEventHandler(self.kLayerWarming)
end

-- Shutdown the system (power off and begin cooling)
-- Called from: btnShutdownConfirm EventHandler
function UCIController:shutdownSystem()
    self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
    self:powerOff()
    self:startLoadingBar(false)
    self:btnNavEventHandler(self.kLayerCooling)
end

-------------------[ Core Navigation Logic ]-------------------
-- Central navigation event handler - ALL layer changes route through here
-- Called from: btnNav01-15 EventHandlers, startSystem(), shutdownSystem(), syncRoomControlsState(), startLoadingBar(), and various pin handlers
function UCIController:btnNavEventHandler(argIndex)
    local previousLayer = self.varActiveLayer
    self.varActiveLayer = argIndex
    
    -- Switch video input if video switcher is enabled
    if self.videoSwitcherEnabled then
        self:switchToInput(argIndex)
    end
    
    -- Update all layer visibility
    self:showLayer()
    
    -- Update navigation button interlock
    self:interlock()
    
    self:debugPrint("Layer changed from " .. previousLayer .. " to " .. argIndex)
end

-- Navigation button interlock - ensures only active button is highlighted
-- Called from: btnNavEventHandler()
function UCIController:interlock()
    -- Layer constants are already the button indices (1-15) 
    local activeButtonIndex = self.varActiveLayer

    -- Loop through all navigation buttons and set their state
    for i = 1, 15 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            local shouldBeActive = (i == activeButtonIndex)
            setProp(btn, "Boolean", shouldBeActive)
        end
    end
end

-------------------[ Legend Array Methods ]-------------------
-- Initialize legend arrays for dynamic text updates
-- Called from: init()
function UCIController:initializeLegendArrays()
    -- Build array of all legend controls
    self.arrUCILegends = {}
    local legendControls = {
        "txtNav01", "txtNav02", "txtNav03", "txtNav04",
        "txtNav05", "txtNav06", "txtNav07", "txtNav08",
        "txtNav09", "txtNav10", "txtNav11", "txtNav12", "txtNav13","txtNav14","txtNav15",
        "txtNavShutdown", "txtRoomNameNav", "txtRoomNameStart",
        "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03","txtRouting04", 
        "txtRouting05", "txtRouting06", "txtRouting07", "txtRouting08", "txtRouting09", "txtRouting10", "txtRouting11", "txtRouting12", "txtRoutingSources",
        "txtVidSrc01", "txtVidSrc02", "txtVidSrc03", "txtVidSrc04", "txtVidSrc05", "txtVidSrc06", "txtVidSrc07", "txtVidSrc08", "txtVidSrc09", "txtVidSrc10", "txtVidSrc11", "txtVidSrc12", 
        "txtGainPGM", 
        "txtGain01", "txtGain02", "txtGain03", "txtGain04","txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
        "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04", "txtDisplay05", "txtDisplay06", "txtDisplay07", "txtDisplay08", "txtDisplay09", "txtDisplay10", "txtDisplay11", "txtDisplay12", 
    }
    
    for i = 1, #legendControls do
        local controlName = legendControls[i]
        self.arrUCILegends[i] = Controls[controlName]
    end
    
    -- Build array of all user label variables (from UCI Variables page)
    self.arrUCIUserLabels = {}
    local userLabelVariables = {
        "txtLabelNav01", "txtLabelNav02", "txtLabelNav03", "txtLabelNav04",
        "txtLabelNav05", "txtLabelNav06", "txtLabelNav07", "txtLabelNav08",
        "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12", "txtLabelNav13","txtLabelNav14","txtLabelNav15",
        "txtLabelNavShutdown", "txtLabelRoomNameNav", "txtLabelRoomNameStart",
        "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03","txtLabelRouting04", 
        "txtLabelRouting05", "txtLabelRouting06", "txtLabelRouting07", "txtLabelRouting08", "txtLabelRouting09", "txtLabelRouting10", "txtLabelRouting11", "txtLabelRouting12", "txtLabelRoutingSources",
        "txtLabelVidSrc01", "txtLabelVidSrc02", "txtLabelVidSrc03", "txtLabelVidSrc04","txtLabelVidSrc05", "txtLabelVidSrc06", "txtLabelVidSrc07", "txtLabelVidSrc08","txtLabelVidSrc09", "txtLabelVidSrc10", "txtLabelVidSrc11", "txtLabelVidSrc12", 
        "txtLabelGainPGM", 
        "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04","txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
        "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04", "txtLabelDisplay05", "txtLabelDisplay06", "txtLabelDisplay07", "txtLabelDisplay08", "txtLabelDisplay09", "txtLabelDisplay10", "txtLabelDisplay11", "txtLabelDisplay12", 
    }
    
    for i = 1, #userLabelVariables do
        local varLabel = userLabelVariables[i]
        self.arrUCIUserLabels[i] = Uci.Variables[varLabel]
    end
    
    -- Register event handlers for user label changes
    for i = 1, #self.arrUCIUserLabels do
        local label = self.arrUCIUserLabels[i]
        if label then
            label.EventHandler = function()
                self:updateLegends()
            end
        end
    end
    
    self:debugPrint("Legend arrays initialized with " .. #self.arrUCILegends .. " controls and " .. #self.arrUCIUserLabels .. " variables")
end

-- Update all legends from user label variables
-- Called from: UCI Variable EventHandlers, init()
function UCIController:updateLegends()
    if not self.arrUCILegends or not self.arrUCIUserLabels then
        self:debugPrint("Legend arrays not initialized, skipping update")
        return
    end
    
    -- Loop through and update each legend with corresponding user label
    for i = 1, #self.arrUCILegends do
        local lbl = self.arrUCILegends[i]
        if lbl and self.arrUCIUserLabels[i] then
            local newLegend = self.arrUCIUserLabels[i].String or ""
            setProp(lbl, "Legend", newLegend)
        end
    end
end

-------------------[ Event Handler Registration ]-------------------
-- Register all event handlers for controls and pins
-- Called from: UCIController.new() constructor
function UCIController:registerEventHandlers()
    -- Navigation buttons (btnNav01 through btnNav15)
    for i = 1, 15 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            bind(btn, function() self:btnNavEventHandler(i) end)
        end
    end
    
    -- System control handler map (Start, Shutdown buttons)
    local systemHandlerMap = {
        [controls.btnStartSystem] = function()
            self:startSystem()
        end,
        [controls.btnNavShutdown] = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
        end,
        [controls.btnShutdownCancel] = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        end,
        [controls.btnShutdownConfirm] = function()
            self:shutdownSystem()
        end
    }
    
    -- Help control pairs (Open/Close button pairs with interlocking)
    local helpControlPairs = {
        {open = controls.btnOpenHelpLaptopA, close = controls.btnCloseHelpLaptopA, handler = function() self:updateLaptopAHelpState() end},
        {open = controls.btnOpenHelpLaptopB, close = controls.btnCloseHelpLaptopB, handler = function() self:updateLaptopBHelpState() end},
        {open = controls.btnOpenHelpPCA, close = controls.btnCloseHelpPCA, handler = function() self:updatePCAHelpState() end},
        {open = controls.btnOpenHelpPCB, close = controls.btnCloseHelpPCB, handler = function() self:updatePCBHelpState() end},
        {open = controls.btnOpenHelpWirelessA, close = controls.btnCloseHelpWirelessA, handler = function() self:updateWirelessHelpState() end},
        {open = controls.btnOpenHelpWirelessB, close = controls.btnCloseHelpWirelessB, handler = function() self:updateWirelessHelpState() end},
        {open = controls.btnOpenHelpRouting, close = controls.btnCloseHelpRouting, handler = function() self:updateRoutingHelpState() end},
        {open = controls.btnOpenHelpStreamMusic, close = controls.btnCloseHelpStreamMusic, handler = function() self:updateStreamMusicHelpState() end},
    }
    
    for i = 1, #helpControlPairs do
        local pair = helpControlPairs[i]
        bindPairedControls(pair.open, pair.close, pair.handler)
    end
    
    -- Helper function to check and start system if needed
    -- Used by HDMI Active pin handlers to auto-start system
    local function ensureSystemIsOn()
        if self.roomControlsComponent then
            -- check ledSystemPower status [[memory:10919377]]
            local ledPower = self.roomControlsComponent["ledSystemPower"]
            if ledPower and not ledPower.Boolean then
                self:startSystem()
            end
        end
    end
    
    -- Pin state handler map (all pin-based events)
    local pinHandlerMap = {
        -- USB connection pins (trigger conference state update)
        [controls.pinLEDUSBLaptopA] = function(ctl)
            self:updateConferenceState()
        end,
        [controls.pinLEDUSBLaptopB] = function(ctl)
            self:updateConferenceState()
        end,
        [controls.pinLEDUSBPCA] = function(ctl)
            self:updateConferenceState()
        end,
        [controls.pinLEDUSBPCB] = function(ctl)
            self:updateConferenceState()
        end,
        
        -- HDMI Active pins (auto-switch to source and power on if needed)
        -- Note: Only triggers on positive edge (when Boolean becomes true) [[memory:11606711]]
        [controls.pinLEDHDMIActiveLaptopA] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn() 
                self:btnNavEventHandler(self.kLayerLaptopA)
            end
        end,
        [controls.pinLEDHDMIActiveLaptopB] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerLaptopB)
            end
        end,
        [controls.pinLEDHDMIActivePCA] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerPCA)
            end
        end,
        [controls.pinLEDHDMIActivePCB] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerPCB)
            end
        end,
        
        -- Camera preset and call activity pins
        [controls.pinLEDPresetSaved] = function() self:updatePresetSavedState() end,
        [controls.pinCallActive] = function() self:updateCallActiveState() end,
        
        -- Touch activity pin (for room combining inactivity timeout)
        [controls.pinLEDTouchActivity] = function(ctl) self:resetTouchInactivityTimer() end,
        
        -- HDMI Connection pins (monitor connection state changes)
        -- These fire on both connect and disconnect
        [controls.pinLEDHDMIConnectedPCA] = function() 
            if self.varActiveLayer == self.kLayerPCA then
                self:updateHDMIForActiveSource()
                self:updateConferenceState()
                self:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedPCB] = function() 
            if self.varActiveLayer == self.kLayerPCB then
                self:updateHDMIForActiveSource()
                self:updateConferenceState()
                self:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopA] = function() 
            if self.varActiveLayer == self.kLayerLaptopA then
                self:updateHDMIForActiveSource()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopB] = function() 
            if self.varActiveLayer == self.kLayerLaptopB then
                self:updateHDMIForActiveSource()
            end
        end,
        
        -- ACPR Bypass pins
        [controls.pinLEDACPRBypassSeparated] = function() self:updateACPRBypassState() end,
        [controls.pinLEDACPRBypassCombined] = function() self:updateACPRBypassState() end,
    }
    
    -- Batch register all handler maps
    local handlerMaps = {systemHandlerMap, pinHandlerMap}
    for i = 1, #handlerMaps do
        local handlerMap = handlerMaps[i]
        for ctrl, handler in pairs(handlerMap) do
            bind(ctrl, handler)
        end
    end
    
    self:debugPrint("Event handlers registered using batch registration")
end

-------------------[ Initialization ]-------------------
-- Initialize the controller
-- Called from: Factory function after creating instance
function UCIController:init()
    -- Reset layer states for clean initialization
    self.layerStates = {}
    
    -- Initialize all subsystems
    self:initializeLegendArrays()
    self:initializeRoomControlsComponent()
    self:initializeVideoSwitcher()
    self:initializeDivisibleSpace()
    
    -- Set the default layer to start screen
    self.varActiveLayer = self.kLayerStart
    
    -- Determine initial layer based on system state
    -- Check if we can sync with existing System Automation Controller
    if mySystemController and mySystemController.state then
        local systemPowerState = false
        
        -- Get actual system power state from room controls component
        if self.roomControlsComponent and self.roomControlsComponent["ledSystemPower"] then
            systemPowerState = self.roomControlsComponent["ledSystemPower"].Boolean
        end
        
        if systemPowerState then--[[ System is powered on ]]
            if mySystemController.state.isWarming then--[[ System is currently warming up ]]
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
            else--[[ System is fully warmed up, go to default layer ]]
                self.varActiveLayer = self:getDefaultLayerAfterWarming()
            end
        end
    end
    self:debugPrint("Synchronized with Room Automation state")
    
    -- Hide specified navigation buttons (if any configured)
    for i = 1, #self.hiddenNavIndices do
        local index = self.hiddenNavIndices[i]
        local btn = controls["btnNav" .. string.format("%02d", index)]
        if btn then
            btn.Visible = false
            self:debugPrint("Hidden navigation button: btnNav" .. string.format("%02d", index))
        end
    end
    
    -- Show initial layer and set button states
    self:showLayer()
    self:interlock()
    self:updateLegends()
    
    -- Start sync timer for room controls state monitoring
    self:startSyncTimer()
    
    self:debugPrint("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
end

-- Start sync timer for room controls state monitoring
-- Called from: init()
function UCIController:startSyncTimer()
    if not self.roomControlsComponent then
        self:debugPrint("Room Controls sync disabled (component not available)")
        return
    end
    
    self.syncTimer = Timer.New()
    self.syncTimer.EventHandler = function()
        self:syncRoomControlsState()
        self.syncTimer:Start(1)
    end
    self.syncTimer:Start(1)
    
    self:debugPrint("Room Controls state synchronization enabled (1s interval)")
end

-- Stop sync timer
-- Called from: cleanup()
function UCIController:stopSyncTimer()
    if self.syncTimer then
        self.syncTimer:Stop()
        self.syncTimer = nil
        self:debugPrint("Room Controls sync timer stopped")
    end
end

-------------------[ Cleanup ]-------------------
-- Clean up all resources before destroying instance
-- Called manually when instance is no longer needed
function UCIController:cleanup()
    -- Stop sync timer
    self:stopSyncTimer()
    
    -- Stop touch inactivity timer
    if self.uciTouchInactivityTimer then
        self.uciTouchInactivityTimer:Stop()
        self:debugPrint("Touch inactivity timer stopped")
    end
    
    -- Stop progress timers
    if self.loadingTimer then
        self.loadingTimer:Stop()
        self.loadingTimer = nil
    end
    if self.timeoutTimer then
        self.timeoutTimer:Stop()
        self.timeoutTimer = nil
    end
    
    -- Clear legend event handlers
    if self.arrUCIUserLabels then
        for i = 1, #self.arrUCIUserLabels do
            local label = self.arrUCIUserLabels[i]
            if label then
                label.EventHandler = nil
            end
        end
    end
    
    -- Clear room state event handlers
    if self.btnRoomState then
        for i = 1, #self.btnRoomState do
            local btn = self.btnRoomState[i]
            if btn then
                btn.EventHandler = nil
            end
        end
    end
    
    self:debugPrint("UCI Controller cleanup completed")
end

-------------------[ Factory Function ]-------------------
-- Factory function to create a controller instance with error handling and fallback
local function createUCIController(targetPageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
    if not targetPageName or targetPageName == "" then
        print("ERROR: UCI Factory - Invalid or missing target page name")
        return nil
    end
    
    -- Try various page name variations to find the right one
    local pageNames = {
        targetPageName,
        targetPageName:gsub("%s+", " "),
        targetPageName:gsub("%s+", ""),
        targetPageName:gsub("%(", ""):gsub("%)", ""),
        targetPageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", ""),
        "UCI " .. targetPageName,
        targetPageName:match("^(.-)%s*%(") or targetPageName
    }
    
    local lastError = nil
    
    -- Try each page name variation
    for i = 1, #pageNames do
        local pageName = pageNames[i]
        local success, result = pcall(function()
            return UCIController.new(pageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
        end)
        
        if success and result then
            print("✓ UCI Factory: Successfully created controller for page '" .. pageName .. "' (attempt " .. i .. ")")
            
            -- Export to global namespace
            _G.myUCI = result
            _G.UCIController = UCIController
            
            return result
        else
            lastError = result
            print("✗ UCI Factory: Attempt " .. i .. " failed for '" .. pageName .. "': " .. tostring(lastError))
        end
    end
    
    -- If all attempts failed, create minimal fallback controller
    print("⚠ UCI Factory: All attempts failed. Attempting minimal controller...")
    local success, minimalController = pcall(function()
        return {
            uciPage = targetPageName,
            debugging = true,
            varActiveLayer = defaultActiveLayer,
            isInitialized = false,
            btnNavEventHandler = function(self, layer)
                print("Minimal UCI: Navigation to layer " .. layer .. " (limited functionality)")
            end,
            cleanup = function(self)
                print("Minimal UCI: Cleanup completed")
            end
        }
    end)
    
    if success and minimalController then
        print("⚠ UCI Factory: Created minimal controller with reduced functionality")
        _G.myUCI = minimalController
        return minimalController
    end
    
    -- Complete failure
    print("✗ UCI Factory: Complete failure - Could not create any controller for '" .. targetPageName .. "'")
    print("✗ Last error: " .. tostring(lastError))
    return nil
end

-------------------[ Instance Creation ]-------------------
-- Create the UCI controller instance
myUCI = createUCIController(
    Uci.Variables.txtUCIPageName.String,
    tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 1,
    tonumber(Uci.Variables.numDefaultActiveLayer.Value) or 10,
    {}
)

if myUCI then
    print("UCIController created successfully!")
    print("Event-driven Room Controls synchronization is active")
else
    print("ERROR: UCIController NOT created.")
end

-------------------[ Public API ]-------------------
--[[
PUBLIC API - How to use this controller from other scripts:

Navigation:
    myUCI:btnNavEventHandler(layerIndex)  -- Navigate to a specific layer

System Control:
    myUCI:startSystem()                   -- Power on and start warming
    myUCI:shutdownSystem()                -- Power off and start cooling

Direct Power Control:
    myUCI:powerOn()                       -- Power on without animation
    myUCI:powerOff()                      -- Power off without animation

Sync Control:
    myUCI:startSyncTimer()                -- Start room controls sync
    myUCI:stopSyncTimer()                 -- Stop room controls sync
    myUCI:syncRoomControlsState()         -- Manual sync trigger

Layer Updates:
    myUCI:showLayer()                     -- Refresh current layer
    myUCI:updateHDMIForActiveSource()     -- Update HDMI connection state
    myUCI:updateConferenceState()         -- Update conference/USB state
    myUCI:updateConferenceControlsLayer() -- Update conference controls visibility

Video Switcher:
    myUCI:switchToInput(uciButton)        -- Switch video input

Divisible Space:
    myUCI:getRoomState()                  -- Get current room state ("separated", "combinedA", "combinedB")
    myUCI:getCurrentRoom()                -- Get room identity ("CollabA", "CollabB")
    myUCI:updateNavigationVisibility()    -- Update nav button visibility

Progress Bar:
    myUCI:startLoadingBar(isPoweringOn)   -- Start progress animation

Cleanup:
    myUCI:cleanup()                       -- Clean up all resources

UCI Variables (Component Discovery):
    - txtUCIPageName: Name of the UCI page this controller manages
    - compRoomControls: Name of System Automation Controller component
    - numDefaultActiveLayer: Default layer to show after warming (typically 10 for LaptopB)
    - numDefaultRoutingLayer: Default routing layer (typically 12)
    - timeProgressWarming: Warmup duration in seconds (default 10)
    - timeProgressCooling: Cooldown duration in seconds (default 5)
    - numTouchInactivityTimer: Timeout for room combining layer (default 60 seconds)

Touch Inactivity Feature:
    - Monitors touch activity on H04-RoomCombining layer via pinLEDTouchActivity control
    - After configured timeout (default 60 seconds) of no touch activity, automatically returns to C05-Start layer
    - Optional control - gracefully degrades if not present

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController ledSystemPower state (1s interval)
    - Updates UCI layers and progress bar when power state changes externally
    - Prevents double-triggering of automation logic
    - Uses ledSystemPower as authoritative status indicator (not btnSystemOnOff)
    - Can be manually invoked via myUCI:syncRoomControlsState()

HDMI Auto-Switching:
    - pinLEDHDMIActiveLaptopA/B/PCA/PCB fire on positive edge (signal detected)
    - Automatically powers on system if off
    - Automatically switches to that source
    - Uses ctl.Boolean check to only trigger on signal detection, not loss

Configuration:
    - conferenceStateConfig.skipLaptopA/B: Skip USB check for laptop sources
    - acprConfig.disableACPRShow: Disable ACPR layer visibility logic

Architecture:
    - Single class structure (no module inheritance)
    - Direct methods for all functionality
    - Data-driven layer configuration
    - Source map pattern for DRY source handling
    - Explicit loops for clarity
    - Comprehensive inline documentation
]]--

--[[     
============================================
FLOW DOCUMENTATION - Common Scenarios:
============================================

SCENARIO 1: User presses Start System button
  1. btnStartSystem EventHandler fires (line ~1750)
  2. Calls self:startSystem() (line ~1570)
  3. Powers on via roomControlsComponent (line ~830)
  4. Starts warming progress bar (line ~950)
  5. Navigates to kLayerWarming (line ~1580)
  6. Shows warming animation layers

SCENARIO 2: User presses a navigation button (e.g., btnNav07 for PCA)
  1. btnNav07 EventHandler fires (line ~1730)
  2. Calls self:btnNavEventHandler(7) (line ~1550)
  3. Updates varActiveLayer to 7 (kLayerPCA)
  4. Switches video input if video switcher enabled (line ~880)
  5. Calls self:showLayer() (line ~450) to update layer visibility
  6. Shows P01-PCA layer and relevant sublayers
  7. Updates HDMI connection state (line ~650)
  8. Updates conference controls if USB connected (line ~700)
  9. Calls self:interlock() (line ~1580) to update button states

SCENARIO 3: USB cable connected to PCA
  1. pinLEDUSBPCA EventHandler fires (line ~1850)
  2. Calls self:updateConferenceState() (line ~700)
  3. Checks if HDMI is connected first (gate condition)
  4. Shows J23-ConferenceControlsPCA layer
  5. Hides "Connect USB" prompt layer
  6. Shows camera selection and video privacy layers

SCENARIO 4: HDMI cable connected to LaptopA (auto-switching)
  1. pinLEDHDMIActiveLaptopA EventHandler fires (line ~1880)
  2. Checks Boolean is true (positive edge)
  3. Calls ensureSystemIsOn() to power system if needed
  4. Calls self:btnNavEventHandler(kLayerLaptopA)
  5. System auto-switches to LaptopA input

SCENARIO 5: Room state changes (Combined -> Separated)
  1. btnRoomState EventHandler fires (line ~1300)
  2. Calls self:onRoomStateChanged() (line ~1310)
  3. Updates navigation button visibility (hides opposite room's sources)
  4. Updates "Start Room" vs "Start Rooms" legend
  5. Updates conference controls layer visibility
  6. Updates ACPR button visibility based on room state

SCENARIO 6: System shutdown requested
  1. btnNavShutdown EventHandler fires (line ~1760)
  2. Shows D01-ShutdownConfirm layer
  3. User presses btnShutdownConfirm (line ~1770)
  4. Calls self:shutdownSystem() (line ~1590)
  5. Powers off via roomControlsComponent
  6. Starts cooling progress bar
  7. Navigates to kLayerCooling
  8. After cooldown, returns to kLayerStart 
  ]]--