--[[
    UCIController (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-09-10
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular).
    - All event registration is DRY and centralized using control/event maps.
    - Added debug logging for each layer function call.
    - This script is a modified version of the UCIController class that adds enhanced error handling and validation for required controls.
    - It also adds a check for the System Automation (Room Controls) component and a fallback method if the component is not found.
    - NEW: Universal video switcher integration supporting NV32, Extron DXP, and other video switchers
    - Each logical domain is its own module; orchestrator is thin.
    - Aligned with SystemAutomationController architecture patterns.
]]

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Buttons
    btnNav01 = Controls.btnNav01, btnNav02 = Controls.btnNav02, btnNav03 = Controls.btnNav03,
    btnNav04 = Controls.btnNav04, btnNav05 = Controls.btnNav05, btnNav06 = Controls.btnNav06,
    btnNav07 = Controls.btnNav07, btnNav08 = Controls.btnNav08, btnNav09 = Controls.btnNav09,
    btnNav10 = Controls.btnNav10, btnNav11 = Controls.btnNav11, btnNav12 = Controls.btnNav12,
    btnNav13 = Controls.btnNav13, btnNav14 = Controls.btnNav14, btnNav15 = Controls.btnNav15,
    
    -- System Controls
    btnStartSystem      = Controls.btnStartSystem,
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel,
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    
    -- Help Buttons
    btnOpenHelpLaptopA       = Controls.btnOpenHelpLaptopA,
    btnOpenHelpLaptopB       = Controls.btnOpenHelpLaptopB,
    btnOpenHelpPCA           = Controls.btnOpenHelpPCA,
    btnOpenHelpPCB           = Controls.btnOpenHelpPCB,
    btnOpenHelpWirelessA     = Controls.btnOpenHelpWirelessA,
    btnOpenHelpWirelessB     = Controls.btnOpenHelpWirelessB,
    btnOpenHelpRouting      = Controls.btnOpenHelpRouting,
    btnOpenHelpStreamMusic  = Controls.btnOpenHelpStreamMusic,

    btnCloseHelpLaptopA      = Controls.btnCloseHelpLaptopA,
    btnCloseHelpLaptopB      = Controls.btnCloseHelpLaptopB,
    btnCloseHelpPCA          = Controls.btnCloseHelpPCA,
    btnCloseHelpPCB          = Controls.btnCloseHelpPCB,
    btnCloseHelpWirelessA    = Controls.btnCloseHelpWirelessA,
    btnCloseHelpWirelessB    = Controls.btnCloseHelpWirelessB,
    btnCloseHelpRouting     = Controls.btnCloseHelpRouting,
    btnCloseHelpStreamMusic = Controls.btnCloseHelpStreamMusic,
    
    -- Progress Controls
    knbProgressBar = Controls.knbProgressBar,
    txtProgressBar = Controls.txtProgressBar,
    
    -- Pin Inputs
    pinCallActive           = Controls.pinCallActive,
    pinLEDUSBLaptop         = Controls.pinLEDUSBLaptop,
    pinLEDUSBPC             = Controls.pinLEDUSBPC,
    pinLEDOffHookLaptop     = Controls.pinLEDOffHookLaptop,
    pinLEDOffHookPC         = Controls.pinLEDOffHookPC,
    pinLEDHDMI01Active      = Controls.pinLEDHDMI01Active,
    pinLEDHDMI02Active      = Controls.pinLEDHDMI02Active,
    pinLEDPresetSaved       = Controls.pinLEDPresetSaved,
    pinLEDHDMI01Connect     = Controls.pinLEDHDMI01Connect,
    pinLEDHDMI02Connect     = Controls.pinLEDHDMI02Connect,
    pinLEDACPRBypassActive  = Controls.pinLEDACPRBypassActive,
    pinLEDTouchActivity     = Controls.pinLEDTouchActivity,
    
}

local function validateControls()
    -- Core navigation controls
    local required = {
        "btnNav01", "btnNav02", "btnNav03", "btnNav04", "btnNav05", "btnNav06",
        "btnNav07", "btnNav08", "btnNav09", "btnNav10", "btnNav11", "btnNav12", "btnNav13", "btnNav14", "btnNav15",
        "btnStartSystem", "btnNavShutdown", "btnShutdownCancel", "btnShutdownConfirm"
    }
    
    -- Optional but recommended controls
    local optional = {
        "knbProgressBar", "txtProgressBar",
        "btnOpenHelpLaptopA", "btnOpenHelpLaptopB", "btnOpenHelpPCA", "btnOpenHelpPCB", "btnOpenHelpWirelessA", "btnOpenHelpWirelessB", "btnOpenHelpRouting","btnOpenHelpStreamMusic",
        "btnCloseHelpLaptopA", "btnCloseHelpLaptopB", "btnCloseHelpPCA", "btnCloseHelpPCB", "btnCloseHelpWirelessA", "btnCloseHelpWirelessB", "btnCloseHelpRouting", "btnCloseHelpStreamMusic",
        "btnRouting01", "btnRouting02", "btnRouting03", "btnRouting04", "btnRouting05", "btnRouting06", "btnRouting07", "btnRouting08",
        "txtRouting01", "txtRouting02", "txtRouting03", "txtRouting04", "txtRouting05", "txtRouting06", "txtRouting07", "txtRouting08",
        "pinLEDTouchActivity",
    }
    
    local missing = {}
    local warnings = {}
    
    -- Check required controls
    for _, name in ipairs(required) do
        if not controls[name] then
            table.insert(missing, name)
        end
    end
    
    -- Check optional controls for warnings
    for _, name in ipairs(optional) do
        if not controls[name] then
            table.insert(warnings, name)
        end
    end
    
    -- Report missing required controls
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    -- Report missing optional controls as warnings with functionality notes
    if #warnings > 0 then
        print("WARNING: UCIController - Missing optional controls (reduced functionality):")
        for _, name in ipairs(warnings) do
            local functionalityNote = ""
            if name == "knbProgressBar" or name == "txtProgressBar" then
                functionalityNote = " (progress bar animation disabled)"
            end
            print("  - " .. name .. functionalityNote)
        end
    end
    
    print("UCIController validation passed - All required controls found")
    return true
end

-------------------[ Control Normalization ]---------------
local function normalizeControlArrays()
    -- Convert single controls to arrays where array processing is expected
    local controlsToNormalize = {
        navButtons = {},
        routingButtons = {},
        helpButtons = {},
        pinInputs = {}
    }
    
    -- Build navigation button array
    for i = 1, 13 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then controlsToNormalize.navButtons[i] = btn end
    end
    
    -- Build routing button array
    for i = 1, 8 do
        local btn = controls["btnRouting" .. string.format("%02d", i)]
        if btn then controlsToNormalize.routingButtons[i] = btn end
    end
    
    -- Build help button array
    local helpButtons = {"btnOpenHelpLaptopA", "btnOpenHelpLaptopB", "btnOpenHelpPCA", "btnOpenHelpPCB", "btnOpenHelpWirelessA", "btnOpenHelpWirelessB", "btnOpenHelpRouting", "btnOpenHelpStreamMusic", 
    "btnCloseHelpLaptopA", "btnCloseHelpLaptopB", "btnCloseHelpPCA", "btnCloseHelpPCB", "btnCloseHelpWirelessA", "btnCloseHelpWirelessB", "btnCloseHelpRouting", "btnCloseHelpStreamMusic"}
    for i, name in ipairs(helpButtons) do
        if controls[name] then controlsToNormalize.helpButtons[i] = controls[name] end
    end
    
    -- Build pin input array  
    local pinInputs = {"pinCallActive", "pinLEDUSBLaptop", "pinLEDUSBPC", "pinLEDOffHookLaptop", "pinLEDOffHookPC", 
                      "pinLEDHDMI01Active", "pinLEDHDMI02Active", "pinLEDPresetSaved", "pinLEDHDMI01Connect", 
                      "pinLEDHDMI02Connect", "pinLEDACPRBypassActive", "pinLEDTouchActivity"}
    for i, name in ipairs(pinInputs) do
        if controls[name] then controlsToNormalize.pinInputs[i] = controls[name] end
    end
    
    return controlsToNormalize
end

-------------------[ Utility Functions ]-------------------
local function isArr(t) return type(t) == "table" and t[1] ~= nil end
local function getControlArray(ctrl) return isArr(ctrl) and ctrl or (type(ctrl) == "table" and {ctrl} or {}) end

-- Enhanced setProp with guard logic to prevent redundant assignments
local function setProp(ctrl, prop, val)
    if not ctrl or not prop then return false end
    if ctrl[prop] == val then return false end -- Prevent redundant assignment
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler) 
    if ctrl and handler then ctrl.EventHandler = handler end 
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

-- Enhanced forEach utility for normalized arrays
local function forEach(arr, fn)
    if not arr or not fn then return end
    for i, item in ipairs(arr) do
        if item then fn(i, item) end
    end
end

-- Utility function for managing paired controls (open/close, on/off, etc.)
local function bindPairedControls(openCtrl, closeCtrl, updateHandler)
    if openCtrl and updateHandler then
        bind(openCtrl, function()
            if closeCtrl then setProp(closeCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
    
    if closeCtrl and updateHandler then
        bind(closeCtrl, function()
            if openCtrl then setProp(openCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
end


-------------------[ State Management Utility ]-------------
local function resetComponentsArray()
    -- State management utility for dynamic component arrays
    -- Following SystemAutomationController pattern for consistency
    local componentState = {
        videoSwitchers = {},
        roomControllers = {},
        audioComponents = {},
        initialized = false
    }
    
    -- Clear any existing component references
    for category, components in pairs(componentState) do
        if type(components) == "table" then
            for k in pairs(components) do
                components[k] = nil
            end
        end
    end
    
    -- Reinitialize component discovery
    local availableComponents = Component.GetComponents()
    if availableComponents then
        -- Categorize components by type
        for name, comp in pairs(availableComponents) do
            if comp.Type then
                if comp.Type:find("streamer_hdmi_switcher") or comp.Type:find("extron") then
                    componentState.videoSwitchers[name] = comp
                elseif comp.Type:find("automation") or comp.Type:find("room") then
                    componentState.roomControllers[name] = comp
                elseif comp.Type:find("audio_router") then
                    componentState.audioComponents[name] = comp
                end
            end
        end
    end
    
    componentState.initialized = true
    return componentState
end

-------------------[ Base Module Class ]-------------------
local BaseModule = {}; BaseModule.__index = BaseModule
function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    return self
end
function BaseModule:debug(msg)
    if self.controller.debugging then
        print("[" .. self.controller.uciPage .. " - " .. self.name .. "] " .. msg)
    end
end
function BaseModule:cleanup() self:debug("Cleanup complete") end

-------------------[ Layer Module ]------------------------
local LayerModule = setmetatable({}, BaseModule); LayerModule.__index = LayerModule
function LayerModule.new(controller)
    local self = BaseModule.new(controller, "Layer")
    setmetatable(self, LayerModule)
    self.layerStates = {}
    return self
end

function LayerModule:safeSetLayerVisibility(layer, visible, transition)
    local success, err = pcall(function()
        Uci.SetLayerVisibility(self.controller.uciPage, layer, visible, transition or "none")
    end)
    if success then
        self:debug("Layer '" .. layer .. "' set to " .. tostring(visible))
        self.layerStates[layer] = visible
    else
        self:debug("Warning: Layer '" .. layer .. "' not found: " .. tostring(err))
    end
    return success
end

function LayerModule:updateLayerVisibility(layers, visible, transition)
    -- Guard clauses with early returns
    if not layers or #layers == 0 then return end
    if visible == nil then return end
    
    for _, layer in ipairs(layers) do
        if not layer then goto continue end -- Skip nil layers
        
        local currentState = self.layerStates[layer]
        if not self.controller.isInitialized or currentState ~= visible then
            self:safeSetLayerVisibility(layer, visible, transition)
        end
        
        ::continue::
    end
end

function LayerModule:hideBaseLayers()
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
end

function LayerModule:showLayer()
    -- Hide all layers first
    local layersToHide = {
        "A01-Alarm", 
        "B01-IncomingCall", 
        "C05-Start", 
        "D01-ShutdownConfirm",
        "E01-SystemProgressWarming", "E02-SystemProgressCooling", "E05-SystemProgress",
        "H04-RoomCombining", "H05-RoomControls",
        "I01-CallActive", "I02-HelpLaptopA", "I03-HelpLaptopB", "I04-HelpPCA", "I05-HelpPCB", "I06-HelpWirelessA", "I07-HelpWirelessB", "I08-HelpRouting", "I09-HelpDialer", "I10-HelpStreamMusic",
        "J01-ConnectUSBLaptop", "J02-ConnectUSBPC", "J03-ACPRActive","J04-CamPresetSaved", "J05-ConferenceControls", "J06-ConferenceControls", 
        "L01-HDMIDisconnected", "L01-LaptopA",
        "L02-HDMIDisconnected", "L02-LaptopB",
        "P01-HDMIDisconnected", "P01-PCA",
        "P02-HDMIDisconnected", "P02-PCB",
        "W01-WirelessA", "W02-WirelessB", "W05-Wireless",
        "R01-Routing-SalonD", "R02-Routing-SalonE", "R03-Routing-SalonA","R04-Routing-SalonB", "R05-Routing-SalonC","R06-Routing-SalonF", "R07-Routing-SalonG", "R08-Routing-SalonH", "R10-Routing",
        "S10-StreamMusic", 
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
        [self.controller.kLayerAlarm] = {
            showLayers = {"A01-Alarm"},
            callLayerFunctions = {function() self:hideBaseLayers() end}
        },
        [self.controller.kLayerIncomingCall] = {
            showLayers = {"B01-IncomingCall"}
        },
        [self.controller.kLayerStart] = {
            showLayers = {"C05-Start"},
            callLayerFunctions = {function() self:hideBaseLayers() end}
        },
        [self.controller.kLayerWarming] = {
            showLayers = {"E05-SystemProgress", "E01-SystemProgressWarming"},
            callLayerFunctions = {function() self:hideBaseLayers() end}
        },
        [self.controller.kLayerCooling] = {
            showLayers = {"E05-SystemProgress", "E02-SystemProgressCooling"},
            callLayerFunctions = {function() self:hideBaseLayers() end}
        },
        [self.controller.kLayerRoomControls] = {
            showLayers = {"H05-RoomControls"},
            hideLayers = {"X01-ProgramVolume"},
            callLayerFunctions = {function() self.controller.sublayerModule:updateCallActiveState() end}
        },
        [self.controller.kLayerPCA] = {
            showLayers = {"P01-PCA"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStatePCA() end,
                function() self.controller.sublayerModule:updateConferenceState() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updatePCAHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end,
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end
            }
        },
        [self.controller.kLayerPCB] = {
            showLayers = {"P02-PCB"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStatePCB() end,
                function() self.controller.sublayerModule:updateConferenceState() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updatePCBHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end,
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end
            }
        },
        [self.controller.kLayerLaptopA] = {
            showLayers = {"L01-LaptopA"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStateLaptopA() end,
                function() self.controller.sublayerModule:updateConferenceState() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updateLaptopAHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end,
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end
            }
        },
        [self.controller.kLayerLaptopB] = {
            showLayers = {"L02-LaptopB"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStateLaptopB() end,
                function() self.controller.sublayerModule:updateConferenceState() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updateLaptopBHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end,
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end
            }
        },
        [self.controller.kLayerWireless] = {
            showLayers = {"W05-Wireless"},
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateWirelessHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerRouting] = {
            showLayers = {"R10-Routing"},
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerDialer] = {
            showLayers = {"V05-Dialer"},
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateDialerHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerStreamMusic] = {
            showLayers = {"S10-StreamMusic"},
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateStreamMusicHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerRoomCombining] = {
            showLayers = {"H04-RoomCombining"},
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateCallActiveState() end,
                function() self.controller:resetTouchInactivityTimer() end
            }
        }
    }
    
    local config = layerConfigs[self.controller.varActiveLayer]
    if not config then return end
    
    -- Check conditional visibility for divisible space layers
    if config.conditionalVisibility and self.controller.divisibleSpaceModule then
        local shouldShow = self.controller.divisibleSpaceModule:shouldShowLayer(self.controller.varActiveLayer)
        if not shouldShow then
            self:debug("Layer " .. self.controller.varActiveLayer .. " hidden by divisible space conditional visibility")
            return
        end
    end
    
    -- Show main layers
    for _, layer in ipairs(config.showLayers or {}) do
        self:updateLayerVisibility({layer}, true, "fade")
    end
    
    -- Hide specified layers
    for _, layer in ipairs(config.hideLayers or {}) do
        self:updateLayerVisibility({layer}, false, "none")
    end
    
    -- Call functions in order
    for _, func in ipairs(config.callLayerFunctions or {}) do
        func()
    end

    self:updateRoutingButtonState()
end

function LayerModule:resetLayerStates()
    self.layerStates = {}
    self:debug("Layer states reset")
end

function LayerModule:updateRoutingButtonState()
    if self.controller.varActiveLayer == self.controller.kLayerRouting or controls.btnNav06.Boolean then
    setProp(controls.btnNav10, "IsDisabled", true)
    setProp(controls.btnNav10, "IsInvisible", true)
    self:debug("Routing button disabled")
else
        setProp(controls.btnNav10, "IsDisabled", false)
        setProp(controls.btnNav10, "IsInvisible", false)
        self:debug("Routing button enabled")
    end
end

-------------------[ Sublayer Module ]---------------------
local SublayerModule = setmetatable({}, BaseModule); SublayerModule.__index = SublayerModule
function SublayerModule.new(controller)
    local self = BaseModule.new(controller, "Sublayer")
    setmetatable(self, SublayerModule)
    return self
end

function SublayerModule:updateCallActiveState()
    -- Guard clause - early return if control doesn't exist
    if not controls.pinCallActive then return end
    
    local isActive = controls.pinCallActive.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    self:debug("Call Active: " .. (isActive and "Showing" or "Hiding"))
end

function SublayerModule:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"J04-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    self:debug("Preset Saved: " .. (isVisible and "Showing" or "Hiding") .. " J04-CamPresetSaved")
end

function SublayerModule:updateACPRBypassState()
    -- Divisible space: Check for any of the 4 source layers (PCA, PCB, LaptopA, LaptopB)
    local activeLayer = self.controller.varActiveLayer
    if activeLayer ~= self.controller.kLayerPCA and 
       activeLayer ~= self.controller.kLayerPCB and
       activeLayer ~= self.controller.kLayerLaptopA and 
       activeLayer ~= self.controller.kLayerLaptopB then return end

    -- Determine which conference controls layer based on source type
    local conferenceLayer
    if activeLayer == self.controller.kLayerLaptopA or activeLayer == self.controller.kLayerLaptopB then
        conferenceLayer = "J05-ConferenceControls"
    else -- PCA or PCB
        conferenceLayer = "J06-ConferenceControls"
    end

    local isBypassActive = controls.pinLEDACPRBypassActive and controls.pinLEDACPRBypassActive.Boolean or false
    if not isBypassActive then
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
    end
    self:debug("ACPR Bypass: " .. (isBypassActive and "Active" or "Inactive"))
end

function SublayerModule:updateConferenceState()
    -- Divisible space: Determine USB connection and conference layer based on active layer
    local usbConnected = false
    local usbNotConnectedLayer
    local conferenceLayer
    local activeLayer = self.controller.varActiveLayer
    
    if activeLayer == self.controller.kLayerPCA or activeLayer == self.controller.kLayerPCB then
        -- PC layers use pinLEDUSBPC and J06-ConferenceControls
        usbConnected = controls.pinLEDUSBPC and controls.pinLEDUSBPC.Boolean or false
        usbNotConnectedLayer = "J02-ConnectUSBPC"
        conferenceLayer = "J06-ConferenceControls"
    elseif activeLayer == self.controller.kLayerLaptopA or activeLayer == self.controller.kLayerLaptopB then
        -- Laptop layers use pinLEDUSBLaptop and J05-ConferenceControls
        usbConnected = controls.pinLEDUSBLaptop and controls.pinLEDUSBLaptop.Boolean or false
        usbNotConnectedLayer = "J01-ConnectUSBLaptop"
        conferenceLayer = "J05-ConferenceControls"
    else
        return
    end

    if usbConnected then
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({usbNotConnectedLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, false, "none")
    end
    self:debug("Conference: " .. conferenceLayer .. " " .. (usbConnected and "Connected" or "Disconnected"))
end

function SublayerModule:updateWirelessHelpState()
    local isVisible = controls.btnHelpWireless and controls.btnHelpWireless.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I06-HelpWirelessA"}, isVisible, "none")
    self:debug("Wireless Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateRoutingHelpState()
    local isVisible = controls.btnHelpRouting and controls.btnHelpRouting.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I08-HelpRouting"}, isVisible, "none")
    self:debug("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateDialerHelpState()
    local isVisible = controls.btnHelpDialer and controls.btnHelpDialer.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I09-HelpDialer"}, isVisible, "none")
    self:debug("Dialer Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateStreamMusicHelpState()
    local isVisible = controls.btnHelpStreamMusic and controls.btnHelpStreamMusic.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I10-HelpStreamMusic"}, isVisible, "none")
    self:debug("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- New methods for divisible space - 4 sources (PCA, PCB, LaptopA, LaptopB)
function SublayerModule:updateHDMIStatePCA()
    if self.controller.varActiveLayer ~= self.controller.kLayerPCA then return end
    if not controls.pinLEDHDMIPCAConnect then return end
    local isConnected = controls.pinLEDHDMIPCAConnect.Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({"P01-PCA"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"P01-HDMIDisconnected"}, false, "none")
        self:debug("HDMI PCA: Connected")
        return
    end
    self.controller.layerModule:updateLayerVisibility({"P01-HDMIDisconnected"}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({"P01-PCA", "J06-ConferenceControls"}, false, "none")
    self:debug("HDMI PCA: Disconnected")
end

function SublayerModule:updateHDMIStatePCB()
    if self.controller.varActiveLayer ~= self.controller.kLayerPCB then return end
    if not controls.pinLEDHDMIPCBConnect then return end
    local isConnected = controls.pinLEDHDMIPCBConnect.Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({"P02-PCB"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"P02-HDMIDisconnected"}, false, "none")
        self:debug("HDMI PCB: Connected")
        return
    end
    self.controller.layerModule:updateLayerVisibility({"P02-HDMIDisconnected"}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({"P02-PCB", "J06-ConferenceControls"}, false, "none")
    self:debug("HDMI PCB: Disconnected")
end

function SublayerModule:updateHDMIStateLaptopA()
    if self.controller.varActiveLayer ~= self.controller.kLayerLaptopA then return end
    if not controls.pinLEDHDMILaptopAConnect then return end
    local isConnected = controls.pinLEDHDMILaptopAConnect.Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({"L01-LaptopA"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"L01-HDMIDisconnected"}, false, "none")
        self:debug("HDMI LaptopA: Connected")
        return
    end
    self.controller.layerModule:updateLayerVisibility({"L01-HDMIDisconnected"}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({"L01-LaptopA", "J05-ConferenceControls"}, false, "none")
    self:debug("HDMI LaptopA: Disconnected")
end

function SublayerModule:updateHDMIStateLaptopB()
    if self.controller.varActiveLayer ~= self.controller.kLayerLaptopB then return end
    if not controls.pinLEDHDMILaptopBConnect then return end
    local isConnected = controls.pinLEDHDMILaptopBConnect.Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({"L02-LaptopB"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"L02-HDMIDisconnected"}, false, "none")
        self:debug("HDMI LaptopB: Connected")
        return
    end
    self.controller.layerModule:updateLayerVisibility({"L02-HDMIDisconnected"}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({"L02-LaptopB", "J05-ConferenceControls"}, false, "none")
    self:debug("HDMI LaptopB: Disconnected")
end

-- Help state methods for new sources
function SublayerModule:updatePCAHelpState()
    local isVisible = controls.btnHelpPCA and controls.btnHelpPCA.Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({"I04-HelpPCA"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J06-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"I04-HelpPCA"}, false, "none")
        self:updateConferenceState()
    end
    self:debug("PCA Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updatePCBHelpState()
    local isVisible = controls.btnHelpPCB and controls.btnHelpPCB.Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({"I05-HelpPCB"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J06-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"I05-HelpPCB"}, false, "none")
        self:updateConferenceState()
    end
    self:debug("PCB Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateLaptopAHelpState()
    local isVisible = controls.btnHelpLaptopA and controls.btnHelpLaptopA.Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({"I02-HelpLaptopA"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J05-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"I02-HelpLaptopA"}, false, "none")
        self:updateConferenceState()
    end
    self:debug("LaptopA Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateLaptopBHelpState()
    local isVisible = controls.btnHelpLaptopB and controls.btnHelpLaptopB.Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({"I03-HelpLaptopB"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J05-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"I03-HelpLaptopB"}, false, "none")
        self:updateConferenceState()
    end
    self:debug("LaptopB Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Conference controls layer visibility based on active layer and room identity
function SublayerModule:updateConferenceControlsLayer()
    if not self.controller.divisibleSpaceModule then return end
    
    local activeLayer = self.controller.varActiveLayer
    
    -- Determine which conference controls layer to show based on source type
    -- LaptopA/B -> J05-ConferenceControls, PC A/B -> J06-ConferenceControls
    local showJ04 = false
    local showJ05 = false
    
    if activeLayer == self.controller.kLayerLaptopA or activeLayer == self.controller.kLayerLaptopB then
        showJ04 = true
    elseif activeLayer == self.controller.kLayerPCA or activeLayer == self.controller.kLayerPCB then
        showJ05 = true
    end
    
    self.controller.layerModule:updateLayerVisibility({"J05-ConferenceControls"}, showJ04, showJ04 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J06-ConferenceControls"}, showJ05, showJ05 and "fade" or "none")
    self:debug("Conference Controls: J04(Laptop)=" .. tostring(showJ04) .. ", J05(PC)=" .. tostring(showJ05))
end

-------------------[ Video Switcher Module ]---------------
local VideoSwitcherModule = setmetatable({}, BaseModule); VideoSwitcherModule.__index = VideoSwitcherModule
function VideoSwitcherModule.new(controller)
    local self = BaseModule.new(controller, "VideoSwitcher")
    setmetatable(self, VideoSwitcherModule)
    self.isEnabled = false
    self.switcherComponent = nil
    self.switcherType = nil
    self.uciToInputMapping = {}
    return self
end

VideoSwitcherModule.SwitcherTypes = {
    NV32 = {
        componentType = "streamer_hdmi_switcher",
        switcherNames = {"devNV32", "codenameNV32", "varNV32"},
        routingMethod = "hdmi.out.1.select.index",
        defaultMapping = {[7] = 5, [8] = 4, [9] = 6}
    },
    ExtronDXP = {
        componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames = {"devExtronDXP", "codenameExtronDXP", "varExtronDXP"},
        routingMethod = "output.1",
        defaultMapping = {[7] = 2, [8] = 4, [9] = 1}
    }
}

function VideoSwitcherModule:initialize()
    local switcherType, componentName = self:autoDetectSwitcher()
    if not switcherType then
        self:debug("No video switcher detected")
        return false
    end
    
    local success, component = pcall(function() return Component.New(componentName) end)
    if not success or not component then
        self:debug("Failed to create switcher component: " .. componentName)
        return false
    end
    
    self.switcherType = switcherType
    self.switcherComponent = component
    self.uciToInputMapping = self.SwitcherTypes[switcherType].defaultMapping
    self.isEnabled = true
    self:debug("Video switcher initialized: " .. switcherType)
    return true
end

function VideoSwitcherModule:autoDetectSwitcher()
    -- Check UCI variables first
    for switcherType, config in pairs(self.SwitcherTypes) do
        for _, switchName in ipairs(config.switcherNames) do
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

function VideoSwitcherModule:switchToInput(inputNumber, uciButton)
    -- Guard clauses with early returns
    if not self.isEnabled then return false end
    if not self.switcherComponent then return false end
    if not inputNumber or not uciButton then return false end
    
    self:debug("Switching to input " .. inputNumber .. " via UCI button " .. uciButton)
    
    local success, err = pcall(function()
        local config = self.SwitcherTypes[self.switcherType]
        if not config then return false end
        
        if self.switcherType == "NV32" then
            setProp(self.switcherComponent[config.routingMethod], "Value", inputNumber)
        else
            setProp(self.switcherComponent[config.routingMethod], "String", tostring(inputNumber))
        end
        return true
    end)
    
    if not success then
        self:debug("Failed to switch: " .. tostring(err))
        return false
    end
    
    self:debug("Successfully switched to input " .. inputNumber)
    return true
end

-------------------[ Room Automation Module ]--------------
local RoomAutomationModule = setmetatable({}, BaseModule); RoomAutomationModule.__index = RoomAutomationModule
function RoomAutomationModule.new(controller)
    local self = BaseModule.new(controller, "RoomAutomation")
    setmetatable(self, RoomAutomationModule)
    self.roomControlsComponent = nil
    self.previousPowerState = nil
    return self
end

function RoomAutomationModule:initializeComponent()
    local componentName = nil
    
    -- Try UCI variable first
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    
    -- Try default naming convention
    if not componentName then
        local pageName = self.controller.uciPage:match("uci%s+([^(]+)")
        if pageName then
            componentName = "compRoomControls" .. pageName:gsub("%s+", "")
        end
    end
    
    if not componentName then
        self:debug("Could not determine Room Controls component name")
        return false
    end
    
    local success, component = pcall(function() return Component.New(componentName) end)
    if success and component then
        self.roomControlsComponent = component
        self:debug("Room Controls Component referenced: " .. componentName)
        
        -- Initialize previous state
        if self.roomControlsComponent["btnSystemOnOff"] then
            self.previousPowerState = self.roomControlsComponent["btnSystemOnOff"].Boolean
            self:debug("Initial power state: " .. tostring(self.previousPowerState))
        end
        
        return true
    else
        self:debug("Room Controls Component not found: " .. componentName)
        return false
    end
end

function RoomAutomationModule:powerOn()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debug("Cannot power on: Room Controls component not available")
        return false
    end
    
    local ok, result = pcall(function()
        self.roomControlsComponent["btnSystemOnOff"].Boolean = true
        return self.roomControlsComponent["btnSystemOnOff"].Boolean
    end)
    
    if ok and result then
        self:debug("Room powered ON")
        return true
    else
        self:debug("Failed to power on room automation")
        return false
    end
end

function RoomAutomationModule:powerOff()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debug("Cannot power off: Room Controls component not available")
        return false
    end
    
    local ok, result = pcall(function()
        self.roomControlsComponent["btnSystemOnOff"].Boolean = false
        return not self.roomControlsComponent["btnSystemOnOff"].Boolean
    end)
    
    if ok and result then
        self:debug("Room powered OFF")
        return true
    else
        self:debug("Failed to power off room automation")
        return false
    end
end

function RoomAutomationModule:getTiming(isPoweringOn)
    -- Try component reference first
    if self.roomControlsComponent then
        local success, result = pcall(function()
            if isPoweringOn then
                return self.roomControlsComponent["warmupTime"] and self.roomControlsComponent["warmupTime"].Value or 10
            else
                return self.roomControlsComponent["cooldownTime"] and self.roomControlsComponent["cooldownTime"].Value or 5
            end
        end)
        if success and result then
            self:debug("Using component timing: " .. result .. " seconds")
            return result
        end
    end
    
    -- Fallback to UCI variables
    local duration = isPoweringOn and 
        (tonumber(Uci.Variables.timeProgressWarming) or 10) or
        (tonumber(Uci.Variables.timeProgressCooling) or 5)
    
    self:debug("Using UCI timing: " .. duration .. " seconds")
    return duration
end

function RoomAutomationModule:syncRoomControlsState()
    -- Guard clause: ensure component is available
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        return
    end
    
    local currentState = self.roomControlsComponent["btnSystemOnOff"].Boolean
    
    -- Only react to state changes
    if currentState == self.previousPowerState then
        return
    end
    
    self:debug("Power state changed: " .. tostring(self.previousPowerState) .. " -> " .. tostring(currentState))
    self.previousPowerState = currentState
    
    -- Update UCI based on new state (without triggering automation logic)
    if currentState then
        -- System is powering on
        self.controller.progressModule:startLoadingBar(true)
        self.controller:btnNavEventHandler(self.controller.kLayerWarming)
        self:debug("Synchronized to WARMING state")
    else
        -- System is powering off
        self.controller.progressModule:startLoadingBar(false)
        self.controller:btnNavEventHandler(self.controller.kLayerCooling)
        self:debug("Synchronized to COOLING state")
    end
end

-------------------[ Progress Module ]---------------------
local ProgressModule = setmetatable({}, BaseModule); ProgressModule.__index = ProgressModule
function ProgressModule.new(controller)
    local self = BaseModule.new(controller, "Progress")
    setmetatable(self, ProgressModule)
    self.isAnimating = false
    self.loadingTimer = nil
    self.timeoutTimer = nil
    return self
end

function ProgressModule:startLoadingBar(isPoweringOn)
    if self.isAnimating then return end
    
    self.isAnimating = true
    local duration = self.controller.roomAutomationModule:getTiming(isPoweringOn)
    local steps = 100
    local interval = duration / steps
    local currentStep = 0
    
    -- Cleanup existing timers
    if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
    if self.timeoutTimer then self.timeoutTimer:Stop(); self.timeoutTimer = nil end
    
    self.loadingTimer = Timer.New()
    self.timeoutTimer = Timer.New()
    
    -- Initialize progress display
    if controls.knbProgressBar then
        controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    end
    if controls.txtProgressBar then
        controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
    end
    
    -- Timeout protection
    self.timeoutTimer.EventHandler = function()
        if self.isAnimating then
            self:debug("Loading bar timeout reached")
            self.isAnimating = false
            if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
            self.controller:btnNavEventHandler(isPoweringOn and self.controller.defaultActiveLayer or self.controller.kLayerStart)
        end
    end
    self.timeoutTimer:Start(300) -- 5-minute timeout
    
    -- Progress animation
    self.loadingTimer.EventHandler = function()
        currentStep = currentStep + 1
        
        local progress = isPoweringOn and currentStep or (100 - currentStep)
        if controls.knbProgressBar then controls.knbProgressBar.Value = progress end
        if controls.txtProgressBar then controls.txtProgressBar.String = progress .. "%" end
        
        if currentStep >= steps then
            self.loadingTimer:Stop()
            self.timeoutTimer:Stop()
            self.isAnimating = false
            
            -- Use DivisibleSpaceModule to determine default layer after warming
            local targetLayer
            if isPoweringOn and self.controller.divisibleSpaceModule then
                targetLayer = self.controller.divisibleSpaceModule:getDefaultLayerAfterWarming()
            else
                targetLayer = self.controller.kLayerStart
            end
            self.controller:btnNavEventHandler(targetLayer)
        else
            self.loadingTimer:Start(interval)
        end
    end
    
    self.loadingTimer:Start(interval)
    self:debug("Loading bar started (" .. duration .. "s)")
end

function ProgressModule:cleanup()
    if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
    if self.timeoutTimer then self.timeoutTimer:Stop(); self.timeoutTimer = nil end
    self.isAnimating = false
    self:debug("Progress module cleanup complete")
end

-------------------[ DivisibleSpace Module ]---------------
local DivisibleSpaceModule = setmetatable({}, BaseModule); DivisibleSpaceModule.__index = DivisibleSpaceModule
function DivisibleSpaceModule.new(controller)
    local self = BaseModule.new(controller, "DivisibleSpace")
    setmetatable(self, DivisibleSpaceModule)
    self.roomIdentity = nil -- "CollabA" or "CollabB"
    self.compDivisibleSpaceControls = nil
    self.isEnabled = false
    return self
end

function DivisibleSpaceModule:initialize()
    -- Parse room identity from Uci.Variables.compRoomControls
    self:parseRoomIdentity()
    
    -- Try to reference compDivisibleSpaceControls component
    local success, component = pcall(function()
        return Component.New("compDivisibleSpaceControls")
    end)
    
    if success and component then
        self.compDivisibleSpaceControls = component
        self.isEnabled = true
        self:debug("DivisibleSpaceControls component referenced successfully")
        self:registerStateChangeHandlers()
    else
        self:debug("DivisibleSpaceControls component not found (feature disabled)")
        self.isEnabled = false
    end
    
    return self.isEnabled
end

function DivisibleSpaceModule:parseRoomIdentity()
    -- Parse room identity from Uci.Variables.compRoomControls.String
    if not Uci.Variables.compRoomControls then
        self:debug("Warning: Uci.Variables.compRoomControls not found")
        return
    end
    
    local roomControlsName = Uci.Variables.compRoomControls.String or ""
    
    if roomControlsName:find("CollabA") then
        self.roomIdentity = "CollabA"
        self:debug("Room identity detected: Collab A")
    elseif roomControlsName:find("CollabB") then
        self.roomIdentity = "CollabB"
        self:debug("Room identity detected: Collab B")
    else
        self:debug("Warning: Could not determine room identity from: " .. roomControlsName)
    end
end

function DivisibleSpaceModule:getCurrentRoom()
    return self.roomIdentity
end

function DivisibleSpaceModule:getRoomState()
    -- Returns "separated", "combinedA", or "combinedB"
    if not self.isEnabled or not self.compDivisibleSpaceControls then
        return "separated" -- Default to separated if component not available
    end
    
    local btnRoomState = self.compDivisibleSpaceControls["btnRoomState"]
    if not btnRoomState then
        self:debug("Warning: btnRoomState control not found")
        return "separated"
    end
    
    -- Check button states
    if btnRoomState[1] and btnRoomState[1].Boolean then
        return "separated"
    elseif btnRoomState[2] and btnRoomState[2].Boolean then
        return "combinedA"
    elseif btnRoomState[3] and btnRoomState[3].Boolean then
        return "combinedB"
    end
    
    return "separated" -- Default fallback
end

function DivisibleSpaceModule:getDefaultLayerAfterWarming()
    -- Determine default layer based on room state and room identity
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    self:debug("Determining default layer: State=" .. roomState .. ", Room=" .. tostring(roomIdentity))
    
    if roomState == "separated" then
        -- Use room-specific PC layer
        if roomIdentity == "CollabA" then
            return self.controller.kLayerPCA
        elseif roomIdentity == "CollabB" then
            return self.controller.kLayerPCB
        else
            -- Fallback to PCA if identity unknown
            return self.controller.kLayerPCA
        end
    elseif roomState == "combinedA" then
        -- Combined on PC A - use PCA for both rooms
        return self.controller.kLayerPCA
    elseif roomState == "combinedB" then
        -- Combined on PC B - use PCB for both rooms
        return self.controller.kLayerPCB
    end
    
    -- Fallback to routing layer
    return self.controller.kLayerRouting
end

function DivisibleSpaceModule:shouldShowLayer(layerConstant)
    -- Determine if a specific layer should be visible based on room state and identity
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    -- If component not available, show room-specific layers only
    if not self.isEnabled then
        if roomIdentity == "CollabA" then
            return layerConstant == self.controller.kLayerPCA or layerConstant == self.controller.kLayerLaptopA
        elseif roomIdentity == "CollabB" then
            return layerConstant == self.controller.kLayerPCB or layerConstant == self.controller.kLayerLaptopB
        end
        return true -- Show all layers if identity unknown
    end
    
    -- Combined state - show all source layers
    if roomState == "combinedA" or roomState == "combinedB" then
        return true
    end
    
    -- Separated state - show only room-specific layers
    if roomState == "separated" then
        if roomIdentity == "CollabA" then
            -- Collab A: show only PCA and LaptopA
            if layerConstant == self.controller.kLayerPCA or layerConstant == self.controller.kLayerLaptopA then
                return true
            end
            if layerConstant == self.controller.kLayerPCB or layerConstant == self.controller.kLayerLaptopB then
                return false
            end
        elseif roomIdentity == "CollabB" then
            -- Collab B: show only PCB and LaptopB
            if layerConstant == self.controller.kLayerPCB or layerConstant == self.controller.kLayerLaptopB then
                return true
            end
            if layerConstant == self.controller.kLayerPCA or layerConstant == self.controller.kLayerLaptopA then
                return false
            end
        end
    end
    
    return true -- Default to showing layer
end

function DivisibleSpaceModule:registerStateChangeHandlers()
    -- Register event handlers on btnRoomState array to trigger layer updates
    if not self.compDivisibleSpaceControls or not self.compDivisibleSpaceControls["btnRoomState"] then
        self:debug("Warning: Cannot register state change handlers - btnRoomState not found")
        return
    end
    
    local btnRoomState = self.compDivisibleSpaceControls["btnRoomState"]
    
    for i = 1, 3 do
        if btnRoomState[i] then
            btnRoomState[i].EventHandler = function(ctl)
                self:onRoomStateChanged(i, ctl.Boolean)
            end
            self:debug("Registered event handler for btnRoomState[" .. i .. "]")
        end
    end
end

function DivisibleSpaceModule:onRoomStateChanged(buttonIndex, state)
    self:debug("Room state button " .. buttonIndex .. " changed to: " .. tostring(state))
    
    if not state then return end -- Only react to button being pressed (true)
    
    -- Update layer visibility when state changes
    if self.controller and self.controller.layerModule then
        self.controller.layerModule:showLayer()
    end
end

function DivisibleSpaceModule:cleanup()
    -- Cleanup event handlers
    if self.compDivisibleSpaceControls and self.compDivisibleSpaceControls["btnRoomState"] then
        local btnRoomState = self.compDivisibleSpaceControls["btnRoomState"]
        for i = 1, 3 do
            if btnRoomState[i] then
                btnRoomState[i].EventHandler = nil
            end
        end
    end
    BaseModule.cleanup(self)
end

-------------------[ UCIController (Main Orchestrator) ]---
local UCIController = {}; UCIController.__index = UCIController

function UCIController.new(uciPage, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
    -- Early validation - return nil if controls are missing
    if not validateControls() then 
        print("ERROR: UCIController initialization failed - validation errors")
        return nil 
    end
    
    local self = setmetatable({}, UCIController)
    
    -- Normalize control arrays early in initialization
    self.normalizedControls = normalizeControlArrays()
    
    -- Reset component state for clean initialization
    self.componentState = resetComponentsArray()
    
    -- Core properties
    self.uciPage = uciPage
    self.debugging = true
    self.varActiveLayer = defaultActiveLayer or 10 -- kLayerRouting
    self.defaultActiveLayer = defaultActiveLayer or 10
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.isInitialized = false
    
    -- Layer constants
    self.kLayerAlarm            = 1; 
    self.kLayerIncomingCall     = 2; 
    self.kLayerStart            = 3;
    self.kLayerWarming          = 4; 
    self.kLayerCooling          = 5; 
    self.kLayerRoomControls     = 6;
    self.kLayerPCA              = 7; 
    self.kLayerPCB              = 8; 
    self.kLayerLaptopA          = 9;
    self.kLayerLaptopB          = 10;
    self.kLayerWireless         = 11;
    self.kLayerRouting          = 12; 
    self.kLayerDialer           = 13; 
    self.kLayerStreamMusic      = 14;
    self.kLayerRoomCombining    = 15;
    
    -- Initialize modules
    self.layerModule            = LayerModule.new(self)
    self.sublayerModule         = SublayerModule.new(self)
    self.videoSwitcherModule    = VideoSwitcherModule.new(self)
    self.roomAutomationModule   = RoomAutomationModule.new(self)
    self.progressModule         = ProgressModule.new(self)
    self.divisibleSpaceModule   = DivisibleSpaceModule.new(self)
    
    -- Sync timer for monitoring Room Controls state
    self.syncTimer              = nil
    
    -- Touch inactivity timer for H04-RoomCombining layer
    self.uciTouchInactivityTimer = Timer.New()
    
    -- Initialize and register events
    self:registerEventHandlers()
    self:init()
    
    return self
end

function UCIController:debug(msg)
    if self.debugging then
        print("[" .. self.uciPage .. "] " .. msg)
    end
end

-------------------[ Touch Inactivity Handler ]------------
function UCIController:onRoomCombiningInactivity()
    if self.layerModule and self.layerModule.layerStates["H04-RoomCombining"] then
        self:debug("Touch inactivity timeout - returning to Start layer")
        self:btnNavEventHandler(self.kLayerStart)
    end
end

function UCIController:resetTouchInactivityTimer()
    if self.layerModule and self.layerModule.layerStates["H04-RoomCombining"] then
        self.uciTouchInactivityTimer:Stop()
        self.uciTouchInactivityTimer.EventHandler = function() self:onRoomCombiningInactivity() end
        local timeout = tonumber(Uci.Variables.numTouchInactivityTimer.Value) or 60
        self.uciTouchInactivityTimer:Start(timeout)
        self:debug("Touch inactivity timer reset (" .. timeout .. "s)")
    end
end

-------------------[ Event Handler Registration ]----------
function UCIController:registerEventHandlers()
    -- Batch event registration using normalized control arrays
    local normalizedControls = normalizeControlArrays()
    
    -- Navigation button batch registration
    if normalizedControls.navButtons then
        forEach(normalizedControls.navButtons, function(i, btn)
            bind(btn, function() self:btnNavEventHandler(i) end)
        end)
    end
    
    -- System control handler map with direct object references
    local systemHandlerMap = {
        [controls.btnStartSystem] = function()
            self:startSystem()
        end,
        [controls.btnNavShutdown] = function()
            self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
        end,
        [controls.btnShutdownCancel] = function()
            self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        end,
        [controls.btnShutdownConfirm] = function()
            self:shutdownSystem()
        end
    }
    
    -- Divisible space: Help control pairs for 4 sources + wireless/routing/streaming
    local helpControlPairs = {
        {open = controls.btnOpenHelpLaptopA, close = controls.btnCloseHelpLaptopA, handler = function() self.sublayerModule:updateLaptopAHelpState() end},
        {open = controls.btnOpenHelpLaptopB, close = controls.btnCloseHelpLaptopB, handler = function() self.sublayerModule:updateLaptopBHelpState() end},
        {open = controls.btnOpenHelpPCA, close = controls.btnCloseHelpPCA, handler = function() self.sublayerModule:updatePCAHelpState() end},
        {open = controls.btnOpenHelpPCB, close = controls.btnCloseHelpPCB, handler = function() self.sublayerModule:updatePCBHelpState() end},
        {open = controls.btnOpenHelpWirelessA, close = controls.btnCloseHelpWirelessA, handler = function() self.sublayerModule:updateWirelessHelpState() end},
        {open = controls.btnOpenHelpWirelessB, close = controls.btnCloseHelpWirelessB, handler = function() self.sublayerModule:updateWirelessHelpState() end},
        {open = controls.btnOpenHelpRouting, close = controls.btnCloseHelpRouting, handler = function() self.sublayerModule:updateRoutingHelpState() end},
        {open = controls.btnOpenHelpStreamMusic, close = controls.btnCloseHelpStreamMusic, handler = function() self.sublayerModule:updateStreamMusicHelpState() end},
    }
        for _, pair in ipairs(helpControlPairs) do
            bindPairedControls(pair.open, pair.close, pair.handler)
    end
    
    -- Helper function to check and start system if needed
    local function ensureSystemIsOn()
        if self.roomAutomationModule and self.roomAutomationModule.roomControlsComponent then
            if self.roomAutomationModule.roomControlsComponent["btnSystemOnOff"] and 
               not self.roomAutomationModule.roomControlsComponent["btnSystemOnOff"].Boolean then
                -- System is OFF, trigger start system
                self:startSystem()
            end
        end
    end
    
    -- Pin state handler map - Divisible space version (4 sources: PCA, PCB, LaptopA, LaptopB)
    -- BEST PRACTICE: Route all layer changes through btnNavEventHandler for centralized state management
    -- This ensures varActiveLayer, video switching, and navButton interlocking are always synchronized
    local pinHandlerMap = {
        -- USB connection monitoring (updates conference state only, doesn't change layers)
        [controls.pinLEDUSBLaptop] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        [controls.pinLEDUSBPC] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        
        -- HDMI connection monitoring for divisible space sources
        [controls.pinLEDHDMIPCAConnect] = function() self.sublayerModule:updateHDMIStatePCA() end,
        [controls.pinLEDHDMIPCBConnect] = function() self.sublayerModule:updateHDMIStatePCB() end,
        [controls.pinLEDHDMILaptopAConnect] = function() self.sublayerModule:updateHDMIStateLaptopA() end,
        [controls.pinLEDHDMILaptopBConnect] = function() self.sublayerModule:updateHDMIStateLaptopB() end,
        
        -- HDMI active detection (optional - triggers automatic layer switching when source goes active)
        [controls.pinLEDHDMI01Active] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn() 
                -- Determine which laptop layer based on room state
                if self.divisibleSpaceModule then
                    local roomState = self.divisibleSpaceModule:getRoomState()
                    local roomIdentity = self.divisibleSpaceModule:getCurrentRoom()
                    if roomState == "separated" and roomIdentity == "CollabA" then
                        self:btnNavEventHandler(self.kLayerLaptopA)
                    elseif roomState == "separated" and roomIdentity == "CollabB" then
                        self:btnNavEventHandler(self.kLayerLaptopB)
                    else
                        self:btnNavEventHandler(self.kLayerLaptopA) -- Default to LaptopA in combined mode
                    end
                end
            end
        end,
        [controls.pinLEDHDMI02Active] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                -- Determine which PC layer based on room state
                if self.divisibleSpaceModule then
                    local roomState = self.divisibleSpaceModule:getRoomState()
                    local roomIdentity = self.divisibleSpaceModule:getCurrentRoom()
                    if roomState == "separated" and roomIdentity == "CollabA" then
                        self:btnNavEventHandler(self.kLayerPCA)
                    elseif roomState == "separated" and roomIdentity == "CollabB" then
                        self:btnNavEventHandler(self.kLayerPCB)
                    else
                        self:btnNavEventHandler(self.kLayerPCA) -- Default to PCA in combined mode
                    end
                end
            end
        end,
        
        -- Other pin handlers
        [controls.pinLEDPresetSaved] = function() self.sublayerModule:updatePresetSavedState() end,
        [controls.pinLEDACPRBypassActive] = function() self.sublayerModule:updateACPRBypassState() end,
        [controls.pinCallActive] = function() self.sublayerModule:updateCallActiveState() end,
        
        -- Touch Activity Monitor for H04-RoomCombining inactivity
        [controls.pinLEDTouchActivity] = function(ctl) self:resetTouchInactivityTimer() end
    }
    
    -- Routing Button Visibility Controls - DRY batch registration
    for i = 1, 8 do
        local pin = controls["pinLEDIsVisibleBtn" .. string.format("%02d", i)]
        if pin then
            pinHandlerMap[pin] = function(ctl) 
                self:updateRoutingControlVisibility(i, ctl.Boolean) 
            end
        end
    end
    
    -- Batch register all handler maps
    local handlerMaps = {systemHandlerMap, pinHandlerMap}
    for _, handlerMap in ipairs(handlerMaps) do
        for ctrl, handler in pairs(handlerMap) do
            if ctrl then -- Only bind if control exists
                bind(ctrl, handler)
            end
        end
    end
    
    self:debug("Event handlers registered using batch registration")
end

-------------------[ System Control Methods ]-------------
function UCIController:startSystem()
    self.roomAutomationModule:powerOn()
    self.progressModule:startLoadingBar(true)
    self:btnNavEventHandler(self.kLayerWarming)
end

function UCIController:shutdownSystem()
    self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
    self.roomAutomationModule:powerOff()
    self.progressModule:startLoadingBar(false)
    self.varActiveLayer = self.kLayerCooling
    self.layerModule:showLayer()
    self:interlock()
end

-------------------[ Core Navigation Logic ]---------------
function UCIController:btnNavEventHandler(argIndex)
    local previousLayer = self.varActiveLayer
    self.varActiveLayer = argIndex
    
    -- Trigger video switcher for specific buttons
    if self.videoSwitcherModule.isEnabled then
        local inputNumber = self.videoSwitcherModule.uciToInputMapping[argIndex]
        if inputNumber then
            self:debug("Triggering video switch to input " .. inputNumber)
            self.videoSwitcherModule:switchToInput(inputNumber, argIndex)
        end
    end
    
    self.layerModule:showLayer()
    self:interlock()
    self:debug("Layer changed from " .. previousLayer .. " to " .. argIndex)
end

function UCIController:updateRoutingControlVisibility(buttonIndex, isVisible)
    local indexStr = string.format("%02d", buttonIndex)
    local controlNames = {"btnRouting" .. indexStr, "txtRouting" .. indexStr}
    
    for _, controlName in ipairs(controlNames) do
        local control = controls[controlName]
        if control then
            setProp(control, "IsInvisible", not isVisible)
        else
            self:debug("Warning: " .. controlName .. " not found")
        end
    end
    
    self:debug("Routing controls " .. indexStr .. " visibility: " .. (isVisible and "shown" or "hidden"))
end

function UCIController:initializeRoutingControlVisibility()
    -- Initialize routing button visibility based on pin states
    for i = 1, 8 do
        local pin = controls["pinLEDIsVisibleBtn" .. string.format("%02d", i)]
        if pin then
            local isVisible = pin.Boolean or false
            self:updateRoutingControlVisibility(i, isVisible)
        end
    end
    
    self:debug("Routing control visibility initialized")
end

function UCIController:interlock()
    local navButtons = self.normalizedControls.navButtons
    if not navButtons then return end
    
    -- Layer to button index mapping (cached at class level for better performance)
    if not self.layerToButtonMap then
        self.layerToButtonMap = {
            [self.kLayerAlarm]          = 1, 
            [self.kLayerIncomingCall]   = 2, 
            [self.kLayerStart]          = 3,
            [self.kLayerWarming]        = 4, 
            [self.kLayerCooling]        = 5, 
            [self.kLayerRoomControls]   = 6,
            [self.kLayerPCA]            = 7, 
            [self.kLayerPCB]            = 8, 
            [self.kLayerLaptopA]        = 9,
            [self.kLayerLaptopB]        = 10,
            [self.kLayerWireless]       = 11,
            [self.kLayerRouting]        = 12, 
            [self.kLayerDialer]         = 13,
            [self.kLayerStreamMusic]    = 14,
            [self.kLayerRoomCombining]  = 15
        }
    end
    
    local activeButtonIndex = self.layerToButtonMap[self.varActiveLayer]
    
    -- Reset all buttons and set active one in single loop
    for i, btn in ipairs(navButtons) do
        if btn then
            local shouldBeActive = (i == activeButtonIndex)
            setProp(btn, "Boolean", shouldBeActive) -- Use setProp to prevent redundant assignments
        end
    end
end

function UCIController:updateLegends()
    -- Use array-based approach for consistency with original version
    if not self.arrUCILegends or not self.arrUCIUserLabels then
        self:debug("Legend arrays not initialized, skipping update")
        return
    end
    
    for i, lbl in ipairs(self.arrUCILegends) do
        if lbl and self.arrUCIUserLabels[i] then
            local newLegend = self.arrUCIUserLabels[i].String or ""
            setProp(lbl, "Legend", newLegend)
        else
            if not lbl then
                self:debug("Warning: Legend control at index " .. i .. " is nil")
            end
            if not self.arrUCIUserLabels[i] then
                self:debug("Warning: User label variable at index " .. i .. " is nil")
            end
        end
    end
end

-------------------[ Legend Array Initialization ]----------
function UCIController:initializeLegendArrays()
    -- Initialize legend controls array
    self.arrUCILegends = {}
    local legendControls = {
        "txtNav01", "txtNav02", "txtNav03", "txtNav04",
        "txtNav05", "txtNav06", "txtNav07", "txtNav08",
        "txtNav09", "txtNav10", "txtNav11", "txtNav12", "txtNav13",
        "txtNavShutdown", "txtRoomNameNav", "txtRoomNameStart",
        "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03","txtRouting04", 
        "txtRouting05", "txtRouting06", "txtRouting07", "txtRouting08", "txtRoutingSources",
        "txtAudSrc01", "txtAudSrc02", "txtAudSrc03", "txtAudSrc04",
        "txtAudSrc05", "txtAudSrc06", "txtAudSrc07", "txtAudSrc08",
        "txtGainPGM", 
        "txtGain01", "txtGain02", "txtGain03", "txtGain04","txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
        "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04", "txtDisplay05", "txtDisplay06", "txtDisplay07", "txtDisplay08", "txtDisplay09", "txtDisplay10",
    }
    
    for i, controlName in ipairs(legendControls) do
        local control = Controls[controlName]
        if control then
            self.arrUCILegends[i] = control
        else
            self:debug("Warning: Legend control " .. controlName .. " not found")
            self.arrUCILegends[i] = nil
        end
    end
    
    -- Initialize UCI user label variables array
    self.arrUCIUserLabels = {}
    local userLabelVariables = {
        "txtLabelNav01", "txtLabelNav02", "txtLabelNav03", "txtLabelNav04",
        "txtLabelNav05", "txtLabelNav06", "txtLabelNav07", "txtLabelNav08",
        "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12", "txtLabelNav13",
        "txtLabelNavShutdown", "txtLabelRoomNameNav", "txtLabelRoomNameStart",
        "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03","txtLabelRouting04", 
        "txtLabelRouting05", "txtLabelRouting06", "txtLabelRouting07", "txtLabelRouting08", "txtLabelRoutingSources",
        "txtLabelAudSrc01", "txtLabelAudSrc02", "txtLabelAudSrc03", "txtLabelAudSrc04",
        "txtLabelAudSrc05", "txtLabelAudSrc06", "txtLabelAudSrc07", "txtLabelAudSrc08",
        "txtLabelGainPGM", 
        "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04","txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
        "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04", "txtLabelDisplay05", "txtLabelDisplay06", "txtLabelDisplay07", "txtLabelDisplay08", "txtLabelDisplay09", "txtLabelDisplay10",
    }
    
    for i, varLabel in ipairs(userLabelVariables) do
        local variable = Uci.Variables[varLabel]
        if variable then
            self.arrUCIUserLabels[i] = variable
        else
            self:debug("Warning: UCI Variable " .. varLabel .. " not found")
            self.arrUCIUserLabels[i] = nil
        end
    end
    
    -- Set up event handlers for UCI variables to automatically update legends
    for i, label in ipairs(self.arrUCIUserLabels) do
        if label then
            label.EventHandler = function()
                self:updateLegends()
            end
        else
            self:debug("Warning: User label variable at index " .. i .. " is nil, skipping event handler")
        end
    end
    
    self:debug("Legend arrays initialized with " .. #self.arrUCILegends .. " controls and " .. #self.arrUCIUserLabels .. " variables")
end

-------------------[ Initialization ]-----------------------
function UCIController:init()
    self.layerModule:resetLayerStates()
    
    -- Initialize legend arrays and event handlers
    self:initializeLegendArrays()
    
    -- Initialize room automation component
    self.roomAutomationModule:initializeComponent()
    
    -- Initialize video switcher
    self.videoSwitcherModule:initialize()
    
    -- Initialize divisible space module (handles room identity and state monitoring)
    if self.divisibleSpaceModule then
        self.divisibleSpaceModule:initialize()
    end
    
    -- Sync with Room Automation state if available
    if mySystemController and mySystemController.state then
        local systemPowerState = controls.ledSystemPower and controls.ledSystemPower.Boolean
        if systemPowerState then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self.progressModule:startLoadingBar(true)
            else
                -- Use DivisibleSpaceModule to determine default layer
                if self.divisibleSpaceModule then
                    self.varActiveLayer = self.divisibleSpaceModule:getDefaultLayerAfterWarming()
                else
                    self.varActiveLayer = self.defaultActiveLayer
                end
            end
        else
            self.varActiveLayer = self.kLayerStart
        end
        self:debug("Synchronized with Room Automation state")
    else
        self.varActiveLayer = self.kLayerStart
        self:debug("Using default initialization")
    end
    
    -- Hide specified navigation buttons
    for _, index in ipairs(self.hiddenNavIndices) do
        local btn = controls["btnNav" .. string.format("%02d", index)]
        if btn then
            btn.Visible = false
            self:debug("Hidden navigation button: btnNav" .. string.format("%02d", index))
        end
    end
    
    self.layerModule:showLayer()
    self:interlock()
    self:updateLegends()
    
    -- Initialize routing button visibility based on pin states
    self:initializeRoutingControlVisibility()
    
    -- Start synchronization timer if Room Controls component is available
    self:startSyncTimer()
    
    self:debug("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
end

function UCIController:startSyncTimer()
    if not self.roomAutomationModule.roomControlsComponent then
        self:debug("Room Controls sync disabled (component not available)")
        return
    end
    
    -- Create and start periodic sync timer (every 1 second)
    self.syncTimer = Timer.New()
    self.syncTimer.EventHandler = function()
        self.roomAutomationModule:syncRoomControlsState()
        self.syncTimer:Start(1) -- Check every second
    end
    self.syncTimer:Start(1)
    
    self:debug("Room Controls state synchronization enabled (1s interval)")
end

function UCIController:stopSyncTimer()
    if self.syncTimer then
        self.syncTimer:Stop()
        self.syncTimer = nil
        self:debug("Room Controls sync timer stopped")
    end
end

-------------------[ Cleanup ]------------------------------
function UCIController:cleanup()
    -- Stop sync timer
    self:stopSyncTimer()
    
    -- Stop touch inactivity timer
    if self.uciTouchInactivityTimer then
        self.uciTouchInactivityTimer:Stop()
        self:debug("Touch inactivity timer stopped")
    end
    
    -- Cleanup all modules
    local modules = {
        self.layerModule, self.sublayerModule,
        self.videoSwitcherModule, self.roomAutomationModule, self.progressModule,
        self.divisibleSpaceModule
    }
    
    for _, module in ipairs(modules) do
        if module and module.cleanup then module:cleanup() end
    end
    
    -- Cleanup UCI variable event handlers
    if self.arrUCIUserLabels then
        for _, label in ipairs(self.arrUCIUserLabels) do
            if label then
                label.EventHandler = nil
            end
        end
    end
    
    self:debug("UCI Controller cleanup completed")
end

------------------[ Factory Function ]----------------------
local function createUCIController(targetPageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
    -- Guard clause - validate input parameters
    if not targetPageName or targetPageName == "" then
        print("ERROR: UCI Factory - Invalid or missing target page name")
        return nil
    end
    
    -- Comprehensive page name variations with graceful fallbacks
    local pageNames = {
        targetPageName,
        targetPageName:gsub("%s+", " "),       -- Normalize spaces
        targetPageName:gsub("%s+", ""),        -- Remove spaces
        targetPageName:gsub("%(", ""):gsub("%)", ""), -- Remove parentheses
        targetPageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", ""), -- Dashes instead of spaces
        "UCI " .. targetPageName,              -- Add UCI prefix
        targetPageName:match("^(.-)%s*%(") or targetPageName -- Remove trailing parentheses content
    }
    
    local lastError = nil
    
    for i, pageName in ipairs(pageNames) do
        local success, result = pcall(function()
            return UCIController.new(pageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
        end)
        
        if success and result then
            print("✓ UCI Factory: Successfully created controller for page '" .. pageName .. "' (attempt " .. i .. ")")
            
            -- Export for global access and external integration
            _G.myUCI = result
            _G.UCIController = UCIController -- Export class for multiple instances
            
            return result
        else
            lastError = result
            print("✗ UCI Factory: Attempt " .. i .. " failed for '" .. pageName .. "': " .. tostring(lastError))
        end
    end
    
    -- Graceful degradation - return minimal controller if possible
    print("⚠ UCI Factory: All attempts failed. Attempting minimal controller...")
    local success, minimalController = pcall(function()
        -- Create minimal controller with basic functionality only
        return {
            uciPage = targetPageName,
            debugging = true,
            varActiveLayer = defaultActiveLayer or 10,
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
    
    print("✗ UCI Factory: Complete failure - Could not create any controller for '" .. targetPageName .. "'")
    print("✗ Last error: " .. tostring(lastError))
    return nil
end

--------------[ Instance Creation ]-------------------------
myUCI = createUCIController(
    Uci.Variables.txtUCIPageName.String,
    tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 1,
    tonumber(Uci.Variables.numDefaultActiveLayer.Value) or 10,
    {} -- Hidden nav indices
)

if myUCI then
    print("UCIController created successfully!")
    print("Event-driven Room Controls synchronization is active")
else
    print("ERROR: UCIController NOT created.")
end

------------------[ Public API ]-----------------------------
--[[
Public API:
    myUCI:btnNavEventHandler(layerIndex)
    myUCI:cleanup()
    myUCI:startSyncTimer()
    myUCI:stopSyncTimer()
    myUCI.videoSwitcherModule:switchToInput(inputNumber, uciButton)
    myUCI.roomAutomationModule:powerOn()
    myUCI.roomAutomationModule:powerOff()
    myUCI.roomAutomationModule:syncRoomControlsState()
    myUCI.progressModule:startLoadingBar(isPoweringOn)

UCI Variables (Component Discovery):
    - compRoomControls: Name of System Automation Controller component
    
Touch Inactivity Feature:
    - Monitors touch activity on H04-RoomCombining layer via pinLEDTouchActivity control
    - After 10 seconds of no touch activity, automatically returns to C05-Start layer
    - Optional control - gracefully degrades if not present

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController btnSystemOnOff state (1s interval)
    - Updates UCI layers and progress bar when power state changes externally
    - Prevents double-triggering of automation logic
    - Can be manually invoked via myUCI.roomAutomationModule:syncRoomControlsState()
]]
