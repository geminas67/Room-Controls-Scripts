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
-- Conference state update configuration
-- Set to true to skip showing USB connection layers for these sources
-- Set to false to re-enable USB connection layer display (for future use)
local conferenceStateConfig = {
    skipLaptopA = true,  -- Skip "J01-ConnectUSBLaptopA" layer for LaptopA
    skipLaptopB = true   -- Skip "J02-ConnectUSBLaptopB" layer for LaptopB
}

local function validateControls()
    -- Core navigation controls
    local required = {
        "btnNav01", "btnNav02", "btnNav03", "btnNav04", "btnNav05", "btnNav06", "btnNav07", "btnNav08", 
        "btnNav09", "btnNav10", "btnNav11", "btnNav12", "btnNav13", "btnNav14", "btnNav15",
        "btnStartSystem", "btnNavShutdown", "btnShutdownCancel", "btnShutdownConfirm",
        "pinLEDHDMIConnectedPCA", "pinLEDHDMIConnectedPCB", "pinLEDHDMIConnectedLaptopA", "pinLEDHDMIConnectedLaptopB"
    }
    
    -- Optional but recommended controls
    local optional = {
        "knbProgressBar", "txtProgressBar",
        "btnOpenHelpLaptopA", "btnOpenHelpLaptopB", "btnOpenHelpPCA", "btnOpenHelpPCB", "btnOpenHelpWirelessA", "btnOpenHelpWirelessB", "btnOpenHelpRouting","btnOpenHelpStreamMusic",
        "btnCloseHelpLaptopA", "btnCloseHelpLaptopB", "btnCloseHelpPCA", "btnCloseHelpPCB", "btnCloseHelpWirelessA", "btnCloseHelpWirelessB", "btnCloseHelpRouting", "btnCloseHelpStreamMusic",
        "pinLEDTouchActivity",
        "pinLEDACPRBypassSeparated", "pinLEDACPRBypassCombined"
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
    
    -- Build navigation button array dynamically - discover all btnNav## buttons
    for key, btn in pairs(controls) do
        if type(key) == "string" and key:match("^btnNav%d+$") then
            local num = tonumber(key:match("%d+"))
            if num and btn then
                controlsToNormalize.navButtons[num] = btn
            end
        end
    end
    
    -- Build routing button array dynamically - discover all btnRouting## buttons
    for key, btn in pairs(controls) do
        if type(key) == "string" and key:match("^btnRouting%d+$") then
            local num = tonumber(key:match("%d+"))
            if num and btn then
                controlsToNormalize.routingButtons[num] = btn
            end
        end
    end
    
    -- Build help button array
    local helpButtons = {"btnOpenHelpLaptopA", "btnOpenHelpLaptopB", "btnOpenHelpPCA", "btnOpenHelpPCB", "btnOpenHelpWirelessA", "btnOpenHelpWirelessB", "btnOpenHelpRouting", "btnOpenHelpStreamMusic", 
    "btnCloseHelpLaptopA", "btnCloseHelpLaptopB", "btnCloseHelpPCA", "btnCloseHelpPCB", "btnCloseHelpWirelessA", "btnCloseHelpWirelessB", "btnCloseHelpRouting", "btnCloseHelpStreamMusic"}
    for i, name in ipairs(helpButtons) do
        if controls[name] then controlsToNormalize.helpButtons[i] = controls[name] end
    end
    
    -- Build pin input array  
    local pinInputs = {"pinCallActive", "pinLEDUSBLaptopA", "pinLEDUSBPCA", "pinLEDUSBPCB", "pinLEDOffHookLaptopA", "pinLEDOffHookLaptopB", "pinLEDOffHookPCA", "pinLEDOffHookPCB", 
                      "pinLEDHDMIActiveLaptopA", "pinLEDHDMIActivePCA", "pinLEDHDMIActiveLaptopB", "pinLEDHDMIActivePCB", "pinLEDPresetSaved", "pinLEDACPRBypassSeparated", "pinLEDACPRBypassCombined", "pinLEDTouchActivity"}
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
        "J01-ConnectUSBLaptopA", "J02-ConnectUSBLaptopB", "J03-ConnectUSBPCA", "J04-ConnectUSBPCB", 
        "J06-ACPRActiveCombined", "J07-ACPRActiveSeparated", "J08-CamPresetSaved", 
        "J09-ACPRBtnCombined", "J10-ACPRBtnSeparated", 
        "J11-CameraSelectionLaptopA", "J12-CameraSelectionLaptopB", "J13-CameraSelectionPCA", "J14-CameraSelectionPCB",
        "J21-ConferenceControlsLaptopA", "J22-ConferenceControlsLaptopB", "J23-ConferenceControlsPCA", "J24-ConferenceControlsPCB",
        "L01-HDMIDisconnected", "L01-LaptopA",
        "L02-HDMIDisconnected", "L02-LaptopB",
        "P01-HDMIDisconnected", "P01-PCA",
        "P02-HDMIDisconnected", "P02-PCB",
        "W01-WirelessA", "W02-WirelessB", "W05-Wireless",
        "R10-Routing",
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
    
    -- Update navigation button/text visibility whenever navbar becomes visible
    if self.controller.divisibleSpaceModule then
        self.controller.divisibleSpaceModule:updateNavigationVisibility()
    end

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
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updatePCAHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerPCB] = {
            showLayers = {"P02-PCB"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStatePCB() end,
                function() self.controller.sublayerModule:updateConferenceState() end,
                function() self.controller.sublayerModule:updateConferenceControlsLayer() end,
                function() self.controller.sublayerModule:updatePresetSavedState() end,
                function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updatePCBHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerLaptopA] = {
            showLayers = {"L01-LaptopA"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStateLaptopA() end,
                --function() self.controller.sublayerModule:updateConferenceState() end,
                --function() self.controller.sublayerModule:updateConferenceControlsLayer() end,
                --function() self.controller.sublayerModule:updatePresetSavedState() end,
                --function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updateLaptopAHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
            }
        },
        [self.controller.kLayerLaptopB] = {
            showLayers = {"L02-LaptopB"},
            conditionalVisibility = true,
            callLayerFunctions = {
                function() self.controller.sublayerModule:updateHDMIStateLaptopB() end,
                --function() self.controller.sublayerModule:updateConferenceState() end,
                --function() self.controller.sublayerModule:updateConferenceControlsLayer() end,
                --function() self.controller.sublayerModule:updatePresetSavedState() end,
                --function() self.controller.sublayerModule:updateACPRBypassState() end,
                function() self.controller.sublayerModule:updateLaptopBHelpState() end,
                function() self.controller.sublayerModule:updateCallActiveState() end
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

    --self:updateRoutingButtonState() 
end

function LayerModule:resetLayerStates()
    self.layerStates = {}
    self:debug("Layer states reset")
end
--[[
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
]]
-------------------[ Sublayer Module ]---------------------
local SublayerModule = setmetatable({}, BaseModule); SublayerModule.__index = SublayerModule
function SublayerModule.new(controller)
    local self = BaseModule.new(controller, "Sublayer")
    setmetatable(self, SublayerModule)
    
    -- Cache HDMI pin mapping for O(1) lookups (required controls)
    self.hdmiPinMap = {
        [controller.kLayerLaptopA] = controls.pinLEDHDMIConnectedLaptopA,
        [controller.kLayerLaptopB] = controls.pinLEDHDMIConnectedLaptopB,
        [controller.kLayerPCA] = controls.pinLEDHDMIConnectedPCA,
        [controller.kLayerPCB] = controls.pinLEDHDMIConnectedPCB
    }
    
    return self
end

function SublayerModule:updateCallActiveState()
    -- Guard clause - early return if control doesn't exist
    if not controls.pinCallActive then return end
    
    local isActive = controls.pinCallActive.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    self:debug("Call Active: " .. (isActive and "Showing" or "Hiding"))
end

-- DRY Helper: Check HDMI connection using cached map (O(1) lookup)
function SublayerModule:checkHDMIConnection()
    local hdmiPin = self.hdmiPinMap[self.controller.varActiveLayer]
    if not hdmiPin then
        return true -- Non-source layers always pass
    end
    return hdmiPin.Boolean
end

function SublayerModule:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"J08-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    self:debug("Preset Saved: " .. (isVisible and "Showing" or "Hiding") .. " J08-CamPresetSaved")
end

function SublayerModule:updateACPRBypassState()
    -- Divisible space: Check for any of the 4 source layers (PCA, PCB, LaptopA, LaptopB)
    local activeLayer = self.controller.varActiveLayer
    if activeLayer ~= self.controller.kLayerPCA and 
       activeLayer ~= self.controller.kLayerPCB and
       activeLayer ~= self.controller.kLayerLaptopA and 
       activeLayer ~= self.controller.kLayerLaptopB then return end

    -- Guard: Check HDMI connection first
    if not self:checkHDMIConnection() then
        self:debug("ACPR bypass check blocked: HDMI not connected")
        return
    end

    -- Get room state to determine which control and layer to use
    local roomState = "separated" -- default
    if self.controller.divisibleSpaceModule then
        roomState = self.controller.divisibleSpaceModule:getRoomState()
    end

    -- Determine which conference controls layer based on active source
    local conferenceLayer
    if activeLayer == self.controller.kLayerLaptopA then
        conferenceLayer = "J21-ConferenceControlsLaptopA"
    elseif activeLayer == self.controller.kLayerLaptopB then
        conferenceLayer = "J22-ConferenceControlsLaptopB"
    elseif activeLayer == self.controller.kLayerPCA then
        conferenceLayer = "J23-ConferenceControlsPCA"
    elseif activeLayer == self.controller.kLayerPCB then
        conferenceLayer = "J24-ConferenceControlsPCB"
    end

    -- Read appropriate bypass control based on room state
    local bypassControl, acprActiveLayer
    if roomState == "separated" then
        bypassControl = controls.pinLEDACPRBypassSeparated
        acprActiveLayer = "J07-ACPRActiveSeparated"
    else
        -- Combined state (combinedA or combinedB)
        bypassControl = controls.pinLEDACPRBypassCombined
        acprActiveLayer = "J06-ACPRActiveCombined"
    end

    local isBypassActive = bypassControl and bypassControl.Boolean or false
    
    -- Hide the other ACPR Active layer based on room state
    if roomState == "separated" then
        self.controller.layerModule:updateLayerVisibility({"J06-ACPRActiveCombined"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"J07-ACPRActiveSeparated"}, false, "none")
    end

    -- Show/hide appropriate layers based on bypass state
    if not isBypassActive then
        self.controller.layerModule:updateLayerVisibility({acprActiveLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({acprActiveLayer}, false, "none")
    end
    self:debug("ACPR Bypass (" .. roomState .. "): " .. (isBypassActive and "Active" or "Inactive"))
    
    -- Update ACPR button visibility after bypass state changes
    -- This ensures J09/J10 buttons show/hide correctly when bypass activates/deactivates
    self:updateConferenceControlsLayer()
end

function SublayerModule:updateConferenceState()
    -- Divisible space: Determine USB connection and conference layer based on active layer
    local usbConnected = false
    local usbNotConnectedLayer
    local conferenceLayer
    local activeLayer = self.controller.varActiveLayer
    
    -- Guard: Check HDMI connection first
    if not self:checkHDMIConnection() then
        self.controller.layerModule:updateLayerVisibility({
            "J01-ConnectUSBLaptopA", "J02-ConnectUSBLaptopB", "J03-ConnectUSBPCA", "J04-ConnectUSBPCB",
            "J21-ConferenceControlsLaptopA", "J22-ConferenceControlsLaptopB", 
            "J23-ConferenceControlsPCA", "J24-ConferenceControlsPCB"
        }, false, "none")
        self:debug("Conference state blocked: HDMI not connected")
        return
    end
    
    -- Skip conference state updates based on configuration (non-destructive, can be re-enabled)
    if activeLayer == self.controller.kLayerLaptopA and conferenceStateConfig.skipLaptopA then
        return
    end
    if activeLayer == self.controller.kLayerLaptopB and conferenceStateConfig.skipLaptopB then
        return
    end
    
    if activeLayer == self.controller.kLayerLaptopA then
        -- LaptopA: pinLEDUSBLaptopA and J21-ConferenceControlsLaptopA
        usbConnected = controls.pinLEDUSBLaptopA and controls.pinLEDUSBLaptopA.Boolean or false
        usbNotConnectedLayer = "J01-ConnectUSBLaptopA"
        conferenceLayer = "J21-ConferenceControlsLaptopA"
    elseif activeLayer == self.controller.kLayerLaptopB then
        -- LaptopB: pinLEDUSBLaptopB and J22-ConferenceControlsLaptopB
        usbConnected = controls.pinLEDUSBLaptopB and controls.pinLEDUSBLaptopB.Boolean or false
        usbNotConnectedLayer = "J02-ConnectUSBLaptopB"
        conferenceLayer = "J22-ConferenceControlsLaptopB"
    elseif activeLayer == self.controller.kLayerPCA then
        -- PCA: pinLEDUSBPCA and J23-ConferenceControlsPCA
        usbConnected = controls.pinLEDUSBPCA and controls.pinLEDUSBPCA.Boolean or false
        usbNotConnectedLayer = "J03-ConnectUSBPCA"
        conferenceLayer = "J23-ConferenceControlsPCA"
    elseif activeLayer == self.controller.kLayerPCB then
        -- PCB: pinLEDUSBPCB and J24-ConferenceControlsPCB
        usbConnected = controls.pinLEDUSBPCB and controls.pinLEDUSBPCB.Boolean or false
        usbNotConnectedLayer = "J04-ConnectUSBPCB"
        conferenceLayer = "J24-ConferenceControlsPCB"
    else
        return
    end

    if usbConnected then
        self.controller.layerModule:updateLayerVisibility({conferenceLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({"J01-ConnectUSBLaptopA", "J02-ConnectUSBLaptopB", "J03-ConnectUSBPCA", "J04-ConnectUSBPCB"}, false, "none")
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

-------------------[ Generic HDMI State Handler ]----------
-- DRY Pattern: Single method handles all 4 source HDMI states
function SublayerModule:updateHDMIState(layerConstant, pinName, baseLayer, disconnectLayer, sourceName)
    -- Guard clauses with early returns
    if self.controller.varActiveLayer ~= layerConstant then return end
    if not controls[pinName] then return end
    
    local isConnected = controls[pinName].Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({baseLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({disconnectLayer}, false, "none")
        self:debug("HDMI " .. sourceName .. ": Connected")
        return
    end
    
    -- Determine which conference layer to hide based on source
    local conferenceLayer
    if sourceName == "LaptopA" then
        conferenceLayer = "J21-ConferenceControlsLaptopA"
    elseif sourceName == "LaptopB" then
        conferenceLayer = "J22-ConferenceControlsLaptopB"
    elseif sourceName == "PCA" then
        conferenceLayer = "J23-ConferenceControlsPCA"
    elseif sourceName == "PCB" then
        conferenceLayer = "J24-ConferenceControlsPCB"
    end
    
    self.controller.layerModule:updateLayerVisibility({disconnectLayer}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({baseLayer, conferenceLayer}, false, "none")
    self:debug("HDMI " .. sourceName .. ": Disconnected")
end

-------------------[ Generic Source Help State Handler ]---
-- DRY Pattern: Single method handles all source help states
function SublayerModule:updateSourceHelpState(btnName, helpLayer, conferenceLayer, sourceName)
    local isVisible = controls[btnName] and controls[btnName].Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({helpLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({
            "J21-ConferenceControlsLaptopA", "J22-ConferenceControlsLaptopB", 
            "J23-ConferenceControlsPCA", "J24-ConferenceControlsPCB", 
            "J01-ConnectUSBLaptopA", "J02-ConnectUSBLaptopB", "J03-ConnectUSBPCA", "J04-ConnectUSBPCB"
        }, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({helpLayer}, false, "none")
        self:updateConferenceState()
    end
    self:debug(sourceName .. " Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateHDMIStatePCA()
    self:updateHDMIState(
        self.controller.kLayerPCA,
        "pinLEDHDMIConnectedPCA",
        "P01-PCA",
        "P01-HDMIDisconnected",
        "PCA"
    )
end

function SublayerModule:updateHDMIStatePCB()
    self:updateHDMIState(
        self.controller.kLayerPCB,
        "pinLEDHDMIConnectedPCB",
        "P02-PCB",
        "P02-HDMIDisconnected",
        "PCB"
    )
end

function SublayerModule:updateHDMIStateLaptopA()
    self:updateHDMIState(
        self.controller.kLayerLaptopA,
        "pinLEDHDMIConnectedLaptopA",
        "L01-LaptopA",
        "L01-HDMIDisconnected",
        "LaptopA"
    )
end

function SublayerModule:updateHDMIStateLaptopB()
    self:updateHDMIState(
        self.controller.kLayerLaptopB,
        "pinLEDHDMIConnectedLaptopB",
        "L02-LaptopB",
        "L02-HDMIDisconnected",
        "LaptopB"
    )
end

-- Help state methods for new sources
function SublayerModule:updatePCAHelpState()
    self:updateSourceHelpState("btnOpenHelpPCA", "I04-HelpPCA", "J23-ConferenceControlsPCA", "PCA")
end

function SublayerModule:updatePCBHelpState()
    self:updateSourceHelpState("btnOpenHelpPCB", "I05-HelpPCB", "J24-ConferenceControlsPCB", "PCB")
end

function SublayerModule:updateLaptopAHelpState()
    self:updateSourceHelpState("btnOpenHelpLaptopA", "I02-HelpLaptopA", "J21-ConferenceControlsLaptopA", "LaptopA")
end

function SublayerModule:updateLaptopBHelpState()
    self:updateSourceHelpState("btnOpenHelpLaptopB", "I03-HelpLaptopB", "J22-ConferenceControlsLaptopB", "LaptopB")
end

-- Conference controls and camera selection layer visibility based on active layer and room state
function SublayerModule:updateConferenceControlsLayer()
    if not self.controller.divisibleSpaceModule then return end
    
    local activeLayer = self.controller.varActiveLayer
    
    -- Guard: Check HDMI connection first
    if not self:checkHDMIConnection() then
        self.controller.layerModule:updateLayerVisibility({
            "J11-CameraSelectionLaptopA", "J12-CameraSelectionLaptopB", "J13-CameraSelectionPCA", "J14-CameraSelectionPCB",
            "J21-ConferenceControlsLaptopA", "J22-ConferenceControlsLaptopB", 
            "J23-ConferenceControlsPCA", "J24-ConferenceControlsPCB",
            "J09-ACPRBtnCombined", "J10-ACPRBtnSeparated"
        }, false, "none")
        self:debug("Conference controls blocked: HDMI not connected")
        return
    end
    
    local roomState = self.controller.divisibleSpaceModule:getRoomState()
    
    -- Determine which camera selection layer to show based on active source
    local showJ11 = (activeLayer == self.controller.kLayerLaptopA) and (roomState ~= "separated")
    local showJ12 = (activeLayer == self.controller.kLayerLaptopB) and (roomState ~= "separated")
    -- J13 and J14 only show when room is NOT separated (hide when separated)
    local showJ13 = (activeLayer == self.controller.kLayerPCA) and (roomState ~= "separated")
    local showJ14 = (activeLayer == self.controller.kLayerPCB) and (roomState ~= "separated")
    
    -- Show camera selection layers
    self.controller.layerModule:updateLayerVisibility({"J11-CameraSelectionLaptopA"}, showJ11, showJ11 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J12-CameraSelectionLaptopB"}, showJ12, showJ12 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J13-CameraSelectionPCA"}, showJ13, showJ13 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J14-CameraSelectionPCB"}, showJ14, showJ14 and "fade" or "none")
    
    -- Determine USB connection state for each source
    local usbLaptopA = controls.pinLEDUSBLaptopA and controls.pinLEDUSBLaptopA.Boolean or false
    local usbLaptopB = controls.pinLEDUSBLaptopB and controls.pinLEDUSBLaptopB.Boolean or false
    local usbPCA = controls.pinLEDUSBPCA and controls.pinLEDUSBPCA.Boolean or false
    local usbPCB = controls.pinLEDUSBPCB and controls.pinLEDUSBPCB.Boolean or false
    
    -- Show conference controls layers if USB is connected for active source
    -- Conference controls show when active layer matches and USB connected (ignore room state)
    -- Camera selection (J13/J14) respects room state, but conference controls (J21-J24) show regardless
    local showJ21 = (activeLayer == self.controller.kLayerLaptopA) and usbLaptopA
    local showJ22 = (activeLayer == self.controller.kLayerLaptopB) and usbLaptopB
    local showJ23 = (activeLayer == self.controller.kLayerPCA) and usbPCA
    local showJ24 = (activeLayer == self.controller.kLayerPCB) and usbPCB
    
    self.controller.layerModule:updateLayerVisibility({"J21-ConferenceControlsLaptopA"}, showJ21, showJ21 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J22-ConferenceControlsLaptopB"}, showJ22, showJ22 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J23-ConferenceControlsPCA"}, showJ23, showJ23 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J24-ConferenceControlsPCB"}, showJ24, showJ24 and "fade" or "none")
    
    -- ACPR button visibility based on room state and any conference controls active
    -- Check both computed visibility AND actual layer states (in case updateACPRBypassState() shows them)
    local computedConferenceActive = (showJ21 or showJ22 or showJ23 or showJ24)
    local actualJ21 = self.controller.layerModule.layerStates["J21-ConferenceControlsLaptopA"] == true
    local actualJ22 = self.controller.layerModule.layerStates["J22-ConferenceControlsLaptopB"] == true
    local actualJ23 = self.controller.layerModule.layerStates["J23-ConferenceControlsPCA"] == true
    local actualJ24 = self.controller.layerModule.layerStates["J24-ConferenceControlsPCB"] == true
    local conferenceActive = computedConferenceActive or actualJ21 or actualJ22 or actualJ23 or actualJ24
    
    local showJ09 = (roomState ~= "separated") and conferenceActive
    local showJ10 = (roomState == "separated") and conferenceActive
    
    self.controller.layerModule:updateLayerVisibility({"J09-ACPRBtnCombined"}, showJ09, showJ09 and "fade" or "none")
    self.controller.layerModule:updateLayerVisibility({"J10-ACPRBtnSeparated"}, showJ10, showJ10 and "fade" or "none")
    
    self:debug("Camera: J11=" .. tostring(showJ11) .. ", J12=" .. tostring(showJ12) .. ", J13=" .. tostring(showJ13) .. ", J14=" .. tostring(showJ14) .. 
               " | Conference: J21=" .. tostring(showJ21) .. ", J22=" .. tostring(showJ22) .. ", J23=" .. tostring(showJ23) .. ", J24=" .. tostring(showJ24) ..
               " | ACPR: J09(Combined)=" .. tostring(showJ09) .. ", J10(Separated)=" .. tostring(showJ10) .. " | RoomState=" .. roomState)
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
    AVProEdge = {
        componentType = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
        switcherNames = {"devAVProEdge", "compAVProEdge", "varAVProEdge"},
        routingMethod = "trigger", -- Boolean controls that can be triggered
        -- Output 1 (Collab A): Laptop A = Input 1, Laptop B = Input 2, PC A = Input 3, PC B = Input 4
        -- Output 2 (Collab B): Laptop A = Input 5, Laptop B = Input 6, PC A = Input 7, PC B = Input 8
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

function VideoSwitcherModule:switchToInput(uciButton)
    -- Guard clauses with early returns
    if not self.isEnabled then return false end
    if not self.switcherComponent then return false end
    if not uciButton then return false end
    
    local config = self.SwitcherTypes[self.switcherType]
    if not config then return false end
    
    -- Get room identity from DivisibleSpaceModule
    local roomIdentity = nil
    if self.controller.divisibleSpaceModule then
        roomIdentity = self.controller.divisibleSpaceModule:getCurrentRoom()
    end
    
    -- Guard clause: ensure room identity is determined
    if not roomIdentity then
        self:debug("Cannot switch: Room identity not determined")
        return false
    end
    
    -- Get the correct input control name based on room identity and UCI button
    local inputMapping = config.outputMappings and config.outputMappings[roomIdentity]
    if not inputMapping then
        self:debug("Cannot switch: No output mapping for room " .. roomIdentity)
        return false
    end
    
    local inputControlName = inputMapping[uciButton]
    if not inputControlName then
        self:debug("No input mapping for UCI button " .. uciButton .. " in room " .. roomIdentity)
        return false
    end
    
    self:debug("Switching to " .. inputControlName .. " via UCI button " .. uciButton .. " (Room: " .. roomIdentity .. ")")
    
    -- Trigger the Boolean control
    local success, err = pcall(function()
        if self.switcherComponent[inputControlName] then
            self.switcherComponent[inputControlName]:Trigger()
            return true
        else
            self:debug("Warning: Control " .. inputControlName .. " not found on switcher")
            return false
        end
    end)
    
    if not success then
        self:debug("Failed to switch: " .. tostring(err))
        return false
    end
    
    self:debug("Successfully switched to " .. inputControlName)
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
        
        -- Initialize previous state from ledSystemPower (authoritative status indicator)
        -- Use ledSystemPower for status reads, btnSystemOnOff for control writes
        if self.roomControlsComponent["ledSystemPower"] then
            self.previousPowerState = self.roomControlsComponent["ledSystemPower"].Boolean
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
    
    -- Set btnSystemOnOff control to trigger power on (ledSystemPower will update via SystemAutomationController)
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
    
    -- Set btnSystemOnOff control to trigger power off (ledSystemPower will update via SystemAutomationController)
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
    -- Guard clause: ensure component is available with ledSystemPower (authoritative status)
    if not self.roomControlsComponent or not self.roomControlsComponent["ledSystemPower"] then
        return
    end
    
    -- Use ledSystemPower as authoritative status indicator
    local currentState = self.roomControlsComponent["ledSystemPower"].Boolean
    
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
    self.btnRoomState = nil -- Cached btnRoomState array
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
        
        -- Cache btnRoomState array for reuse
        self:cacheBtnRoomState()
        
        self:registerStateChangeHandlers()
        
        -- Set initial navigation button visibility based on current state
        self:updateNavigationVisibility()
    else
        self:debug("DivisibleSpaceControls component not found (feature disabled)")
        self.isEnabled = false
        
        -- Still update navigation visibility based on room identity alone
        self:updateNavigationVisibility()
    end
    
    return self.isEnabled
end

function DivisibleSpaceModule:cacheBtnRoomState()
    -- DRY Pattern: Cache btnRoomState array for reuse across methods
    if not self.compDivisibleSpaceControls then
        self.btnRoomState = nil
        return
    end
    
    self.btnRoomState = {
        self.compDivisibleSpaceControls["btnRoomState 1"],
        self.compDivisibleSpaceControls["btnRoomState 2"],
        self.compDivisibleSpaceControls["btnRoomState 3"]
    }
    
    self:debug("btnRoomState array cached (" .. #self.btnRoomState .. " controls)")
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
    if not self.isEnabled or not self.btnRoomState then
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

function DivisibleSpaceModule:shouldShowLayer(layerIndex)
    -- Determine if a layer should be shown based on room state and room identity
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    -- Define which layers are available for each room identity in separated mode
    local layerAvailability = {
        CollabA = {
            [self.controller.kLayerPCA] = true,
            [self.controller.kLayerLaptopA] = true
        },
        CollabB = {
            [self.controller.kLayerPCB] = true,
            [self.controller.kLayerLaptopB] = true
        }
    }
    
    -- If rooms are combined, all source layers are available
    if roomState == "combinedA" or roomState == "combinedB" then
        return true
    end
    
    -- If separated, check if the layer is available for this room
    if roomState == "separated" and layerAvailability[roomIdentity] then
        local isAvailable = layerAvailability[roomIdentity][layerIndex]
        if isAvailable ~= nil then
            return isAvailable
        end
    end
    
    -- Default to showing the layer (for non-source layers like Routing, Wireless, etc.)
    return true
end

function DivisibleSpaceModule:updateNavigationVisibility()
    -- Update navigation button and text visibility based on room identity and separation state
    -- btnNav EventHandlers handle showing layers; this only controls button/text visibility
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    local isSeparated = (roomState == "separated")
    
    self:debug(string.format("Updating navigation visibility: Room=%s, State=%s", 
        tostring(roomIdentity), roomState))
    
    -- Configuration map: room -> navigation controls to hide when separated
    local navConfig = {
        CollabA = {
            {num = "08", label = "PCB"},      -- btnNav08/txtNav08
            {num = "10", label = "LaptopB"}   -- btnNav10/txtNav10
        },
        CollabB = {
            {num = "07", label = "PCA"},      -- btnNav07/txtNav07
            {num = "09", label = "LaptopA"}   -- btnNav09/txtNav09
        }
    }
    
    -- Get the controls to update for current room
    local controlsToUpdate = navConfig[roomIdentity]
    if not controlsToUpdate then return end
    
    -- Helper function to set visibility for a button/text pair
    local function setNavVisibility(num, label, isInvisible)
        local controlNames = {"btnNav" .. num, "txtNav" .. num}
        
        for _, controlName in ipairs(controlNames) do
            if controls[controlName] then
                setProp(controls[controlName], "IsInvisible", isInvisible)
                self:debug(string.format("%s (%s) IsInvisible = %s", controlName, label, tostring(isInvisible)))
            end
        end
    end
    
    -- Apply visibility to all configured controls
    for _, config in ipairs(controlsToUpdate) do
        setNavVisibility(config.num, config.label, isSeparated)
    end
end

function DivisibleSpaceModule:registerStateChangeHandlers()
    if not self.btnRoomState or not self.btnRoomState[1] then
        return
    end
    
    forEach(self.btnRoomState, function(i, btn)
        bind(btn, function(ctl)
            self:onRoomStateChanged(i, ctl.Boolean)
        end)
    end)
end

function DivisibleSpaceModule:onRoomStateChanged(buttonIndex, state)
    if not state then return end
    
    -- Only update navigation visibility if the navbar is currently visible
    if self.controller and self.controller.layerModule then
        local navbarVisible = self.controller.layerModule.layerStates["Y01-Navbar"]
        if navbarVisible then
            self:updateNavigationVisibility()
        end
    end
    
    -- Update conference controls layer visibility when room state changes
    -- This ensures J13/J14 camera selection layers are updated for PCA/PCB
    if self.controller and self.controller.sublayerModule then
        self.controller.sublayerModule:updateConferenceControlsLayer()
    end
end

function DivisibleSpaceModule:cleanup()
    -- Cleanup event handlers
    if self.btnRoomState then
        forEach(self.btnRoomState, function(i, btn)
            btn.EventHandler = nil
        end)
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
    -- Check if we're still on the RoomCombining layer before navigating away
    if self.varActiveLayer == self.kLayerRoomCombining then
        self:debug("Touch inactivity timeout - returning to Start layer")
        self:btnNavEventHandler(self.kLayerStart)
    end
end

function UCIController:resetTouchInactivityTimer()
    -- Guard clause - ensure timer exists
    if not self.uciTouchInactivityTimer then return end
    
    -- Stop any existing timer first to prevent immediate firing
    self.uciTouchInactivityTimer:Stop()
    
    -- Check if we're actually on the RoomCombining layer
    -- Use actual layer visibility check instead of relying on layerStates which might not be updated yet
    local isOnRoomCombining = (self.varActiveLayer == self.kLayerRoomCombining)
    
    if isOnRoomCombining then
        -- Get timeout value with validation
        local timeout = tonumber(Uci.Variables.numTouchInactivityTimer.Value) or 60
        -- Ensure minimum timeout of 1 second to prevent immediate firing
        if timeout <= 0 then
            timeout = 60
            self:debug("Warning: Invalid timeout value, using default 60s")
        end
        
        -- Set new event handler and start timer
        self.uciTouchInactivityTimer.EventHandler = function() self:onRoomCombiningInactivity() end
        self.uciTouchInactivityTimer:Start(timeout)
        self:debug("Touch inactivity timer reset (" .. timeout .. "s)")
    else
        self:debug("Touch inactivity timer not started (not on RoomCombining layer)")
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
            -- Check ledSystemPower status (authoritative status indicator)
            if self.roomAutomationModule.roomControlsComponent["ledSystemPower"] and 
               not self.roomAutomationModule.roomControlsComponent["ledSystemPower"].Boolean then
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
        [controls.pinLEDUSBLaptopA] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        [controls.pinLEDUSBLaptopB] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        [controls.pinLEDUSBPCA] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        [controls.pinLEDUSBPCB] = function(ctl)
            self.sublayerModule:updateConferenceState()
        end,
        
        -- HDMI active detection (optional - triggers automatic layer switching when source goes active)
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
        
        -- Other pin handlers
        [controls.pinLEDPresetSaved] = function() self.sublayerModule:updatePresetSavedState() end,
        [controls.pinCallActive] = function() self.sublayerModule:updateCallActiveState() end,
        
        -- Touch Activity Monitor for H04-RoomCombining inactivity
        [controls.pinLEDTouchActivity] = function(ctl) self:resetTouchInactivityTimer() end,
        
        -- HDMI connection monitoring (required controls)
        [controls.pinLEDHDMIConnectedPCA] = function() 
            if self.varActiveLayer == self.kLayerPCA then
                self.sublayerModule:updateHDMIStatePCA()
                self.sublayerModule:updateConferenceState()
                self.sublayerModule:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedPCB] = function() 
            if self.varActiveLayer == self.kLayerPCB then
                self.sublayerModule:updateHDMIStatePCB()
                self.sublayerModule:updateConferenceState()
                self.sublayerModule:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopA] = function() 
            if self.varActiveLayer == self.kLayerLaptopA then
                self.sublayerModule:updateHDMIStateLaptopA()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopB] = function() 
            if self.varActiveLayer == self.kLayerLaptopB then
                self.sublayerModule:updateHDMIStateLaptopB()
            end
        end
    }
    
    -- Helper function to conditionally add optional control handlers with logging
    local missingOptionalControls = {}
    local function addOptionalHandler(control, controlName, handler)
        if control then
            pinHandlerMap[control] = handler
        else
            table.insert(missingOptionalControls, controlName)
        end
    end
    
    -- Conditionally add ACPR bypass handlers (optional controls)
    addOptionalHandler(controls.pinLEDACPRBypassSeparated, "pinLEDACPRBypassSeparated", function() self.sublayerModule:updateACPRBypassState() end)
    addOptionalHandler(controls.pinLEDACPRBypassCombined, "pinLEDACPRBypassCombined", function() self.sublayerModule:updateACPRBypassState() end)
    
    -- Report missing optional controls if any
    if #missingOptionalControls > 0 then
        self:debug("Optional control handlers skipped (controls not found): " .. table.concat(missingOptionalControls, ", "))
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
    self:btnNavEventHandler(self.kLayerCooling)
end

-------------------[ Core Navigation Logic ]---------------
function UCIController:btnNavEventHandler(argIndex)
    local previousLayer = self.varActiveLayer
    self.varActiveLayer = argIndex
    
    -- Trigger video switcher for specific buttons
    if self.videoSwitcherModule.isEnabled then
        -- switchToInput will determine the correct input based on room identity and UCI button
        self.videoSwitcherModule:switchToInput(argIndex)
    end
    
    self.layerModule:showLayer()
    self:interlock()
    self:debug("Layer changed from " .. previousLayer .. " to " .. argIndex)
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
        "txtNav09", "txtNav10", "txtNav11", "txtNav12", "txtNav13","txtNav14","txtNav15",
        "txtNavShutdown", "txtRoomNameNav", "txtRoomNameStart",
        "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03","txtRouting04", 
        "txtRouting05", "txtRouting06", "txtRouting07", "txtRouting08", "txtRouting09", "txtRouting10", "txtRouting11", "txtRouting12", "txtRoutingSources",
        "txtVidSrc01", "txtVidSrc02", "txtVidSrc03", "txtVidSrc04", "txtVidSrc05", "txtVidSrc06", "txtVidSrc07", "txtVidSrc08", "txtVidSrc09", "txtVidSrc10", "txtVidSrc11", "txtVidSrc12", 
        "txtGainPGM", 
        "txtGain01", "txtGain02", "txtGain03", "txtGain04","txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
        "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04", "txtDisplay05", "txtDisplay06", "txtDisplay07", "txtDisplay08", "txtDisplay09", "txtDisplay10", "txtDisplay11", "txtDisplay12", 
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
        "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12", "txtLabelNav13","txtLabelNav14","txtLabelNav15",
        "txtLabelNavShutdown", "txtLabelRoomNameNav", "txtLabelRoomNameStart",
        "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03","txtLabelRouting04", 
        "txtLabelRouting05", "txtLabelRouting06", "txtLabelRouting07", "txtLabelRouting08", "txtLabelRouting09", "txtLabelRouting10", "txtLabelRouting11", "txtLabelRouting12", "txtLabelRoutingSources",
        "txtLabelVidSrc01", "txtLabelVidSrc02", "txtLabelVidSrc03", "txtLabelVidSrc04","txtLabelVidSrc05", "txtLabelVidSrc06", "txtLabelVidSrc07", "txtLabelVidSrc08","txtLabelVidSrc09", "txtLabelVidSrc10", "txtLabelVidSrc11", "txtLabelVidSrc12", 
        "txtLabelGainPGM", 
        "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04","txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
        "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04", "txtLabelDisplay05", "txtLabelDisplay06", "txtLabelDisplay07", "txtLabelDisplay08", "txtLabelDisplay09", "txtLabelDisplay10", "txtLabelDisplay11", "txtLabelDisplay12", 
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
    myUCI.videoSwitcherModule:switchToInput(uciButton)
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
