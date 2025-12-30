--[[
    UCIController (DivisibleSpace)(Refactored - Lean)
    Author: Nikolas Smith, Q-SYS
    Version: 2.2 | Date: 2025-12-29
    Firmware Req: 10.0.0
    Notes:
    - Centralized data maps for sources, help, HDMI, ACPR.
    - Reduced branching; single generic helpers for HDMI, help, conference, ACPR.
    - Fail-fast control validation preserved.
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

-------------------[ Utility ]-------------------
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

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function getControlArray(ctrl)
    if type(ctrl) ~= "table" then return {} end
    return ctrl[1] and ctrl or {ctrl}
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do
        bind(ctrl, function(ctl) handler(i, ctl) end)
    end
end

local function forEach(arr, fn)
    if not arr then return end
    for i, v in ipairs(arr) do fn(i, v) end
end

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

-------------------[ Base Module ]-------------------
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
function BaseModule:cleanup()
    self:debug("Cleanup complete")
end

-------------------[ Layer Module ]-------------------
local LayerModule = setmetatable({}, BaseModule); LayerModule.__index = LayerModule
function LayerModule.new(controller)
    local self = BaseModule.new(controller, "Layer")
    setmetatable(self, LayerModule)
    self.layerStates = {}
    return self
end

function LayerModule:safeSetLayerVisibility(layer, visible, transition)
    local ok, err = pcall(function()
        Uci.SetLayerVisibility(self.controller.uciPage, layer, visible, transition or "none")
    end)
    if ok then
        self.layerStates[layer] = visible
        self:debug("Layer '" .. layer .. "' -> " .. tostring(visible))
    else
        self:debug("Warning: Layer '" .. layer .. "' not found: " .. tostring(err))
    end
    return ok
end

function LayerModule:updateLayerVisibility(layers, visible, transition)
    if not layers or visible == nil then return end
    for _, layer in ipairs(layers) do
        if layer then
            local current = self.layerStates[layer]
            if not self.controller.isInitialized or current ~= visible then
                self:safeSetLayerVisibility(layer, visible, transition)
            end
        end
    end
end

function LayerModule:hideBaseLayers()
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
end

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

-- Data-driven layer configuration
local function buildLayerConfigs(controller)
    return {
        [controller.kLayerAlarm] = {
            show = {"A01-Alarm"},
            hideBase = true
        },
        [controller.kLayerIncomingCall] = {
            show = {"B01-IncomingCall"}
        },
        [controller.kLayerStart] = {
            show = {"C05-Start"},
            hideBase = true
        },
        [controller.kLayerWarming] = {
            show = {"E05-SystemProgress","E01-SystemProgressWarming"},
            hideBase = true
        },
        [controller.kLayerCooling] = {
            show = {"E05-SystemProgress","E02-SystemProgressCooling"},
            hideBase = true
        },
        [controller.kLayerRoomControls] = {
            conditional = true,
            showRoomControls = true,
            hide = {"X01-ProgramVolume"},
            call = {function() controller.sublayerModule:updateCallActiveState() end}
        },
        [controller.kLayerPCA] = {
            conditional = true,
            show = {"P01-PCA"},
            call = {
                function() controller.sublayerModule:updateHDMIForActiveSource() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updateConferenceControlsLayer() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updatePCAHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerPCB] = {
            conditional = true,
            show = {"P02-PCB"},
            call = {
                function() controller.sublayerModule:updateHDMIForActiveSource() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updateConferenceControlsLayer() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updatePCBHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerLaptopA] = {
            conditional = true,
            show = {"L01-LaptopA"},
            call = {
                function() controller.sublayerModule:updateHDMIForActiveSource() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updateConferenceControlsLayer() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updateLaptopAHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerLaptopB] = {
            conditional = true,
            show = {"L02-LaptopB"},
            call = {
                function() controller.sublayerModule:updateHDMIForActiveSource() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updateConferenceControlsLayer() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updateLaptopBHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerWireless] = {
            show = {"W05-Wireless"},
            call = {
                function() controller.sublayerModule:updateWirelessHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerRouting] = {
            show = {"R10-Routing"},
            call = {
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerDialer] = {
            show = {"V05-Dialer"},
            call = {
                function() controller.sublayerModule:updateDialerHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerStreamMusic] = {
            show = {"S10-StreamMusic"},
            call = {
                function() controller.sublayerModule:updateStreamMusicHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerRoomCombining] = {
            show = {"H04-RoomCombining"},
            hideBase = true,
            call = {
                function() controller.sublayerModule:updateCallActiveState() end,
                function() controller:resetTouchInactivityTimer() end,
            }
        }
    }
end

function LayerModule:showLayer()
    -- Hide everything
    self:updateLayerVisibility(layersToHide, false, "none")

    -- Base always on unless layer config hides it
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")

    self.controller.divisibleSpaceModule:updateNavigationVisibility()

    local configs = self.configs or buildLayerConfigs(self.controller)
    self.configs = configs

    local active = self.controller.varActiveLayer
    local config = configs[active]
    if not config then return end

    -- Divisible-space condition
    if config.conditional then
        if config.showRoomControls then
            local layerName = self.controller.divisibleSpaceModule:getRoomControlsLayerName()
            if not layerName then
                self:debug("RoomControls layer not available")
                return
            end
            config.show = {layerName}
        else
            local ok = self.controller.divisibleSpaceModule:shouldShowLayer(active)
            if not ok then
                self:debug("Layer " .. tostring(active) .. " hidden by divisible-space state")
                return
            end
        end
    end

    if config.hideBase then
        self:hideBaseLayers()
    end

    if config.show then
        self:updateLayerVisibility(config.show, true, "fade")
    end
    if config.hide then
        self:updateLayerVisibility(config.hide, false, "none")
    end
    if config.call then
        for _, f in ipairs(config.call) do f() end
    end
end

function LayerModule:resetLayerStates()
    self.layerStates = {}
    self:debug("Layer states reset")
end

-------------------[ Sublayer Module ]-------------------
local SublayerModule = setmetatable({}, BaseModule); SublayerModule.__index = SublayerModule
function SublayerModule.new(controller)
    local self = BaseModule.new(controller, "Sublayer")
    setmetatable(self, SublayerModule)

    -- Source data map: one place to define HDMI pin, UCI layers, help ids, USB pins.
    self.sources = {
        LaptopA = {
            layerConst   = controller.kLayerLaptopA,
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
            layerConst   = controller.kLayerLaptopB,
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
            layerConst   = controller.kLayerPCA,
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
            layerConst   = controller.kLayerPCB,
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

    return self
end

function SublayerModule:getActiveSource()
    local key = self.layerToSource[self.controller.varActiveLayer]
    return key and self.sources[key] or nil
end

function SublayerModule:checkHDMIConnection()
    local src = self:getActiveSource()
    if not src or not src.hdmiPin then return true end
    return src.hdmiPin.Boolean
end

function SublayerModule:syncHelpButtonStates(helpLayer)
    local map = self.helpLayerButtonMap[helpLayer]
    if not map then return end
    local visible = self.controller.layerModule.layerStates[helpLayer] == true
    local openBtn = controls[map.open]
    local closeBtn = controls[map.close]
    setProp(openBtn, "Boolean", visible)
    setProp(closeBtn, "Boolean", false)
end

function SublayerModule:updateCallActiveState()
    local isActive = controls.pinCallActive.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    self:debug("Call Active: " .. (isActive and "Showing" or "Hiding"))
end

function SublayerModule:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"J08-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    self:debug("Preset Saved: " .. (isVisible and "Showing" or "Hiding"))
end

-- Generic HDMI handler using source map
function SublayerModule:updateHDMIForActiveSource()
    local src = self:getActiveSource()
    if not src then return end

    local isConnected = src.hdmiPin and src.hdmiPin.Boolean or false
    if isConnected then
        self.controller.layerModule:updateLayerVisibility({src.baseLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({src.discLayer}, false, "none")
        self:debug("HDMI " .. src.baseLayer .. ": Connected")
        return
    end

    -- On disconnect: show disconnect layer, hide base + conference + help
    self.controller.layerModule:updateLayerVisibility({src.discLayer}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({src.baseLayer, src.confLayer, src.helpLayer}, false, "none")
    if src.helpLayer then
        self:syncHelpButtonStates(src.helpLayer)
    end
    self:debug("HDMI " .. src.baseLayer .. ": Disconnected")
end


-- Generic source help handler
function SublayerModule:updateSourceHelpState(srcKey)
    local src = self.sources[srcKey]
    if not src then return end

    -- HDMI gate: help hidden if HDMI is not connected
    if not self:checkHDMIConnection() then
        self.controller.layerModule:updateLayerVisibility({src.helpLayer}, false, "none")
        self:syncHelpButtonStates(src.helpLayer)
        self:debug(srcKey .. " Help: Hiding (HDMI not connected)")
        return
    end

    local isVisible = src.btnOpen.Boolean or false
    if isVisible then
        self.controller.layerModule:updateLayerVisibility({src.helpLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({
            "J21-ConferenceControlsLaptopA","J22-ConferenceControlsLaptopB",
            "J23-ConferenceControlsPCA","J24-ConferenceControlsPCB",
            "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB",
            "J03-ConnectUSBPCA","J04-ConnectUSBPCB"
        }, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({src.helpLayer}, false, "none")
        self:updateConferenceState()
    end

    self:syncHelpButtonStates(src.helpLayer)
    self:debug(srcKey .. " Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updatePCAHelpState()   self:updateSourceHelpState("PCA")   end
function SublayerModule:updatePCBHelpState()   self:updateSourceHelpState("PCB")   end
function SublayerModule:updateLaptopAHelpState() self:updateSourceHelpState("LaptopA") end
function SublayerModule:updateLaptopBHelpState() self:updateSourceHelpState("LaptopB") end

-- Conference state (USB) now also uses source map
function SublayerModule:updateConferenceState()
    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        local hideLayers = {
            "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB",
            "J03-ConnectUSBPCA","J04-ConnectUSBPCB",
            "J21-ConferenceControlsLaptopA","J22-ConferenceControlsLaptopB",
            "J23-ConferenceControlsPCA","J24-ConferenceControlsPCB"
        }
        if src.helpLayer then table.insert(hideLayers, src.helpLayer) end
        self.controller.layerModule:updateLayerVisibility(hideLayers, false, "none")
        if src.helpLayer then self:syncHelpButtonStates(src.helpLayer) end
        self:debug("Conference blocked: HDMI not connected")
        return
    end

    -- Config skip for laptops
    if src.layerConst == self.controller.kLayerLaptopA and conferenceStateConfig.skipLaptopA then return end
    if src.layerConst == self.controller.kLayerLaptopB and conferenceStateConfig.skipLaptopB then return end

    local usbConnected = src.usbPin and src.usbPin.Boolean or false
    if usbConnected then
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({
            "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB",
            "J03-ConnectUSBPCA","J04-ConnectUSBPCB"
        }, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({src.usbConnect}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({src.confLayer, src.helpLayer}, false, "none")
        if src.helpLayer then self:syncHelpButtonStates(src.helpLayer) end
    end
    self:debug("Conference: " .. src.confLayer .. " " .. (usbConnected and "Connected" or "Disconnected"))
end

-- ACPR Bypass State using source map
function SublayerModule:updateACPRBypassState()
    if acprConfig.disableACPRShow then
        self.controller.layerModule:updateLayerVisibility({
            "J06-ACPRActiveCombined", "J07-ACPRActiveSeparated"
        }, false, "none")
        self:debug("ACPR Show logic disabled via acprConfig")
        return
    end

    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        self:debug("ACPR bypass check blocked: HDMI not connected")
        return
    end

    -- Get room state to determine which control and layer to use
    local roomState = self.controller.divisibleSpaceModule:getRoomState()

    local bypassControl, acprActiveLayer
    if roomState == "separated" then
        bypassControl = controls.pinLEDACPRBypassSeparated
        acprActiveLayer = "J07-ACPRActiveSeparated"
    else
        bypassControl = controls.pinLEDACPRBypassCombined
        acprActiveLayer = "J06-ACPRActiveCombined"
    end

    local isBypassActive = bypassControl.Boolean or false
    
    -- Hide the other ACPR Active layer based on room state
    if roomState == "separated" then
        self.controller.layerModule:updateLayerVisibility({"J06-ACPRActiveCombined"}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({"J07-ACPRActiveSeparated"}, false, "none")
    end

    -- Show/hide appropriate layers based on bypass state
    if not isBypassActive then
        self.controller.layerModule:updateLayerVisibility({acprActiveLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({acprActiveLayer}, false, "none")
    end
    self:debug("ACPR Bypass (" .. roomState .. "): " .. (isBypassActive and "Active" or "Inactive"))
    
    -- Update ACPR button visibility after bypass state changes
    self:updateConferenceControlsLayer()
end

-- Conference Controls Layer - uses source map for lookups
function SublayerModule:updateConferenceControlsLayer()
    -- HDMI gate
    if not self:checkHDMIConnection() then
        self.controller.layerModule:updateLayerVisibility({
            "J11-CameraSelectionLaptopA", "J12-CameraSelectionLaptopB", "J13-CameraSelectionPCA", "J14-CameraSelectionPCB",
            "J21-ConferenceControlsLaptopA", "J22-ConferenceControlsLaptopB", 
            "J23-ConferenceControlsPCA", "J24-ConferenceControlsPCB",
            "J17-VideoPrivacySeparatedA", "J18-VideoPrivacySeparatedB", "J19-VideoPrivacyCombinedA", "J20-VideoPrivacyCombinedB",
            "J09-ACPRBtnCombined", "J10-ACPRBtnSeparated"
        }, false, "none")
        self:debug("Conference controls blocked: HDMI not connected")
        return
    end
    
    local roomState = self.controller.divisibleSpaceModule:getRoomState()
    local isCombined = (roomState ~= "separated")
    
    -- Determine which layers to show based on active source and room state
    local showLayers = {}
    local hideLayers = {}
    
    -- Iterate through all sources and determine visibility
    for srcKey, src in pairs(self.sources) do
        local isActive = (self.controller.varActiveLayer == src.layerConst)
        local usbConnected = src.usbPin and src.usbPin.Boolean or false
        
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
    end
    
    -- ACPR buttons: show based on room state and any conference controls active
    local anyConferenceActive = false
    for _, layer in ipairs(showLayers) do
        if layer:match("^J2[1-4]%-Conference") or 
           self.controller.layerModule.layerStates[layer:match("J2[1-4]%-ConferenceControls%w+")] == true then
            anyConferenceActive = true
            break
        end
    end
    
    if not acprConfig.disableACPRShow and anyConferenceActive then
        if isCombined then
            table.insert(showLayers, "J09-ACPRBtnCombined")
            table.insert(hideLayers, "J10-ACPRBtnSeparated")
        else
            table.insert(showLayers, "J10-ACPRBtnSeparated")
            table.insert(hideLayers, "J09-ACPRBtnCombined")
        end
    else
        table.insert(hideLayers, "J09-ACPRBtnCombined")
        table.insert(hideLayers, "J10-ACPRBtnSeparated")
    end
    
    -- Apply visibility changes
    for _, layer in ipairs(showLayers) do
        self.controller.layerModule:updateLayerVisibility({layer}, true, "fade")
    end
    for _, layer in ipairs(hideLayers) do
        self.controller.layerModule:updateLayerVisibility({layer}, false, "none")
    end
    
    self:debug("Conference controls updated: " .. #showLayers .. " shown, " .. #hideLayers .. " hidden")
end

function SublayerModule:updateWirelessHelpState()
    local isVisible = controls.btnOpenHelpWirelessA.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I06-HelpWirelessA"}, isVisible, "none")
    self:syncHelpButtonStates("I06-HelpWirelessA")
    self:debug("Wireless Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateRoutingHelpState()
    local isVisible = controls.btnOpenHelpRouting.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I08-HelpRouting"}, isVisible, "none")
    self:syncHelpButtonStates("I08-HelpRouting")
    self:debug("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateDialerHelpState()
    local isVisible = controls.btnHelpDialer.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I09-HelpDialer"}, isVisible, "none")
    self:debug("Dialer Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateStreamMusicHelpState()
    local isVisible = controls.btnOpenHelpStreamMusic.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I10-HelpStreamMusic"}, isVisible, "none")
    self:syncHelpButtonStates("I10-HelpStreamMusic")
    self:debug("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
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
    if not self.isEnabled then return false end
    if not self.switcherComponent then return false end
    if not uciButton then return false end
    
    local config = self.SwitcherTypes[self.switcherType]
    if not config then return false end
    
    -- Get room identity from DivisibleSpaceModule
    local roomIdentity = self.controller.divisibleSpaceModule:getCurrentRoom()
    
    if not roomIdentity then
        self:debug("Cannot switch: Room identity not determined")
        return false
    end
    
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
    
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    
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
        
        -- use ledSystemPower as authoritative status indicator
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
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = true end)
    if ok then self:debug("Room powered ON") else self:debug("Failed to power on room automation") end
    return ok
end

function RoomAutomationModule:powerOff()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debug("Cannot power off: Room Controls component not available")
        return false
    end
    -- Set btnSystemOnOff control to trigger power off (ledSystemPower will update via SystemAutomationController)
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = false end)
    if ok then self:debug("Room powered OFF") else self:debug("Failed to power off room automation") end
    return ok
end

function RoomAutomationModule:getTiming(isPoweringOn)
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
    
    local duration = isPoweringOn and 
        (tonumber(Uci.Variables.timeProgressWarming) or 10) or
        (tonumber(Uci.Variables.timeProgressCooling) or 5)
    
    self:debug("Using UCI timing: " .. duration .. " seconds")
    return duration
end

function RoomAutomationModule:syncRoomControlsState()
    -- use ledSystemPower as authoritative status
    if not self.roomControlsComponent or not self.roomControlsComponent["ledSystemPower"] then
        return
    end
    
    local currentState = self.roomControlsComponent["ledSystemPower"].Boolean
    
    if currentState == self.previousPowerState then
        return
    end
    
    self:debug("Power state changed: " .. tostring(self.previousPowerState) .. " -> " .. tostring(currentState))
    self.previousPowerState = currentState
    
    if currentState then
        self.controller.progressModule:startLoadingBar(true)
        self.controller:btnNavEventHandler(self.controller.kLayerWarming)
        self:debug("Synchronized to WARMING state")
    else
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
    
    if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
    if self.timeoutTimer then self.timeoutTimer:Stop(); self.timeoutTimer = nil end
    
    self.loadingTimer = Timer.New()
    self.timeoutTimer = Timer.New()
    
    controls.knbProgressBar.Value = isPoweringOn and 0 or 100
    controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
    
    self.timeoutTimer.EventHandler = function()
        if self.isAnimating then
            self:debug("Loading bar timeout reached")
            self.isAnimating = false
            if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
            self.controller:btnNavEventHandler(isPoweringOn and self.controller.defaultActiveLayer or self.controller.kLayerStart)
        end
    end
    self.timeoutTimer:Start(300)
    
    self.loadingTimer.EventHandler = function()
        currentStep = currentStep + 1
        
        local progress = isPoweringOn and currentStep or (100 - currentStep)
        controls.knbProgressBar.Value = progress
        controls.txtProgressBar.String = progress .. "%"
        
        if currentStep >= steps then
            self.loadingTimer:Stop()
            self.timeoutTimer:Stop()
            self.isAnimating = false
            
            local targetLayer
            if isPoweringOn then
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
    self.roomIdentity = nil
    self.compDivisibleSpaceControls = nil
    self.btnRoomState = nil
    self.isEnabled = false
    return self
end

function DivisibleSpaceModule:initialize()
    self:parseRoomIdentity()
    
    local success, component = pcall(function()
        return Component.New("compDivisibleSpaceControls")
    end)
    
    if success and component then
        self.compDivisibleSpaceControls = component
        self.isEnabled = true
        self:debug("DivisibleSpaceControls component referenced successfully")
        
        self:cacheBtnRoomState()
        self:registerStateChangeHandlers()
        self:updateNavigationVisibility()
        self:updateStartSystemLegend()
    else
        self:debug("DivisibleSpaceControls component not found (feature disabled)")
        self.isEnabled = false
        
        self:updateNavigationVisibility()
        self:updateStartSystemLegend()
    end
    
    return self.isEnabled
end

function DivisibleSpaceModule:cacheBtnRoomState()
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
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
    self:debug("Determining default layer: State=" .. roomState .. ", Room=" .. tostring(roomIdentity))
    
    if roomState == "separated" then
        if roomIdentity == "CollabA" then
            return self.controller.kLayerPCA
        elseif roomIdentity == "CollabB" then
            return self.controller.kLayerPCB
        else
            return self.controller.kLayerPCA
        end
    elseif roomState == "combinedA" then
        return self.controller.kLayerPCA
    elseif roomState == "combinedB" then
        return self.controller.kLayerPCB
    end
    
    return self.controller.kLayerRouting
end

function DivisibleSpaceModule:shouldShowLayer(layerIndex)
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    
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
    
    if roomState == "combinedA" or roomState == "combinedB" then
        return true
    end
    
    if roomState == "separated" and layerAvailability[roomIdentity] then
        local isAvailable = layerAvailability[roomIdentity][layerIndex]
        if isAvailable ~= nil then
            return isAvailable
        end
    end
    
    return true
end

function DivisibleSpaceModule:getRoomControlsLayerName()
    local roomState = self:getRoomState()
    local isSeparated = (roomState == "separated")
    
    if isSeparated then
        return "H09-RoomControlsSeparated"
    else
        return "H08-RoomControlsCombined"
    end
end

function DivisibleSpaceModule:updateNavigationVisibility()
    local roomState = self:getRoomState()
    local roomIdentity = self:getCurrentRoom()
    local isSeparated = (roomState == "separated")
    
    self:debug(string.format("Updating navigation visibility: Room=%s, State=%s", 
        tostring(roomIdentity), roomState))
    
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
    
    local function setNavVisibility(num, label, isInvisible)
        local controlNames = {"btnNav" .. num, "txtNav" .. num}
        
        for _, controlName in ipairs(controlNames) do
            setProp(controls[controlName], "IsInvisible", isInvisible)
            self:debug(string.format("%s (%s) IsInvisible = %s", controlName, label, tostring(isInvisible)))
        end
    end
    
    for _, config in ipairs(controlsToUpdate) do
        setNavVisibility(config.num, config.label, isSeparated)
    end
end

function DivisibleSpaceModule:updateStartSystemLegend()
    local roomState = self:getRoomState()
    local legend = (roomState == "separated") and "Start Room" or "Start Rooms"
    
    setProp(controls.btnStartSystem, "Legend", legend)
    self:debug("Start System button legend updated: " .. legend .. " (State: " .. roomState .. ")")
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
    
    if self.controller and self.controller.layerModule then
        local navbarVisible = self.controller.layerModule.layerStates["Y01-Navbar"]
        if navbarVisible then
            self:updateNavigationVisibility()
            self:updateStartSystemLegend()
        end
    end
    
    self:updateStartSystemLegend()
    
    if self.controller and self.controller.sublayerModule then
        self.controller.sublayerModule:updateConferenceControlsLayer()
    end
end

function DivisibleSpaceModule:cleanup()
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
    if not validateControls() then 
        print("ERROR: UCIController initialization failed - validation errors")
        return nil 
    end
    
    local self = setmetatable({}, UCIController)
    
    self.uciPage = uciPage
    self.debugging = true
    self.varActiveLayer = defaultActiveLayer or 10
    self.defaultActiveLayer = defaultActiveLayer or 10
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.isInitialized = false
    
    -- Layer constants
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
    
    -- Initialize modules
    self.layerModule            = LayerModule.new(self)
    self.sublayerModule         = SublayerModule.new(self)
    self.videoSwitcherModule    = VideoSwitcherModule.new(self)
    self.roomAutomationModule   = RoomAutomationModule.new(self)
    self.progressModule         = ProgressModule.new(self)
    self.divisibleSpaceModule   = DivisibleSpaceModule.new(self)
    
    self.syncTimer              = nil
    self.uciTouchInactivityTimer = Timer.New()
    
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
    if self.varActiveLayer == self.kLayerRoomCombining then
        self:debug("Touch inactivity timeout - returning to Start layer")
        self:btnNavEventHandler(self.kLayerStart)
    end
end

function UCIController:resetTouchInactivityTimer()
    self.uciTouchInactivityTimer:Stop()
    
    local isOnRoomCombining = (self.varActiveLayer == self.kLayerRoomCombining)
    
    if isOnRoomCombining then
        local timeout = tonumber(Uci.Variables.numTouchInactivityTimer.Value) or 60
        if timeout <= 0 then
            timeout = 60
            self:debug("Warning: Invalid timeout value, using default 60s")
        end
        
        self.uciTouchInactivityTimer.EventHandler = function() self:onRoomCombiningInactivity() end
        self.uciTouchInactivityTimer:Start(timeout)
        self:debug("Touch inactivity timer reset (" .. timeout .. "s)")
    else
        self:debug("Touch inactivity timer not started (not on RoomCombining layer)")
    end
end

-------------------[ Event Handler Registration ]----------
function UCIController:registerEventHandlers()
    -- Navigation buttons
    for i = 1, 15 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            bind(btn, function() self:btnNavEventHandler(i) end)
        end
    end
    
    -- System control handler map
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
    
    -- Help control pairs
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
            -- check ledSystemPower status
            local ledPower = self.roomAutomationModule.roomControlsComponent["ledSystemPower"]
            if ledPower and not ledPower.Boolean then
                self:startSystem()
            end
        end
    end
    
    -- Pin state handler map
    local pinHandlerMap = {
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
        
        [controls.pinLEDPresetSaved] = function() self.sublayerModule:updatePresetSavedState() end,
        [controls.pinCallActive] = function() self.sublayerModule:updateCallActiveState() end,
        
        [controls.pinLEDTouchActivity] = function(ctl) self:resetTouchInactivityTimer() end,
        
        [controls.pinLEDHDMIConnectedPCA] = function() 
            if self.varActiveLayer == self.kLayerPCA then
                self.sublayerModule:updateHDMIForActiveSource()
                self.sublayerModule:updateConferenceState()
                self.sublayerModule:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedPCB] = function() 
            if self.varActiveLayer == self.kLayerPCB then
                self.sublayerModule:updateHDMIForActiveSource()
                self.sublayerModule:updateConferenceState()
                self.sublayerModule:updateConferenceControlsLayer()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopA] = function() 
            if self.varActiveLayer == self.kLayerLaptopA then
                self.sublayerModule:updateHDMIForActiveSource()
            end
        end,
        
        [controls.pinLEDHDMIConnectedLaptopB] = function() 
            if self.varActiveLayer == self.kLayerLaptopB then
                self.sublayerModule:updateHDMIForActiveSource()
            end
        end
    }
    
    pinHandlerMap[controls.pinLEDACPRBypassSeparated] = function() self.sublayerModule:updateACPRBypassState() end
    pinHandlerMap[controls.pinLEDACPRBypassCombined] = function() self.sublayerModule:updateACPRBypassState() end
    
    -- Batch register all handler maps
    local handlerMaps = {systemHandlerMap, pinHandlerMap}
    for _, handlerMap in ipairs(handlerMaps) do
        for ctrl, handler in pairs(handlerMap) do
            bind(ctrl, handler)
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
    
    if self.videoSwitcherModule.isEnabled then
        self.videoSwitcherModule:switchToInput(argIndex)
    end
    
    self.layerModule:showLayer()
    self:interlock()
    self:debug("Layer changed from " .. previousLayer .. " to " .. argIndex)
end

function UCIController:interlock()
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
    
    for i = 1, 15 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            local shouldBeActive = (i == activeButtonIndex)
            setProp(btn, "Boolean", shouldBeActive)
        end
    end
end

function UCIController:updateLegends()
    if not self.arrUCILegends or not self.arrUCIUserLabels then
        self:debug("Legend arrays not initialized, skipping update")
        return
    end
    
    for i, lbl in ipairs(self.arrUCILegends) do
        if lbl and self.arrUCIUserLabels[i] then
            local newLegend = self.arrUCIUserLabels[i].String or ""
            setProp(lbl, "Legend", newLegend)
        end
    end
end

-------------------[ Legend Array Initialization ]----------
function UCIController:initializeLegendArrays()
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
        self.arrUCILegends[i] = Controls[controlName]
    end
    
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
        self.arrUCIUserLabels[i] = Uci.Variables[varLabel]
    end
    
    for i, label in ipairs(self.arrUCIUserLabels) do
        if label then
            label.EventHandler = function()
                self:updateLegends()
            end
        end
    end
    
    self:debug("Legend arrays initialized with " .. #self.arrUCILegends .. " controls and " .. #self.arrUCIUserLabels .. " variables")
end

-------------------[ Initialization ]-----------------------
function UCIController:init()
    self.layerModule:resetLayerStates()
    
    self:initializeLegendArrays()
    self.roomAutomationModule:initializeComponent()
    self.videoSwitcherModule:initialize()
    
    self.divisibleSpaceModule:initialize()
    
    if mySystemController and mySystemController.state then
        local systemPowerState = false
        if self.roomAutomationModule.roomControlsComponent and 
           self.roomAutomationModule.roomControlsComponent["ledSystemPower"] then
            systemPowerState = self.roomAutomationModule.roomControlsComponent["ledSystemPower"].Boolean
        end
        if systemPowerState then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self.progressModule:startLoadingBar(true)
            else
                self.varActiveLayer = self.divisibleSpaceModule:getDefaultLayerAfterWarming()
            end
        else
            self.varActiveLayer = self.kLayerStart
        end
        self:debug("Synchronized with Room Automation state")
    else
        self.varActiveLayer = self.kLayerStart
        self:debug("Using default initialization")
    end
    
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
    
    self:startSyncTimer()
    
    self:debug("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
end

function UCIController:startSyncTimer()
    if not self.roomAutomationModule.roomControlsComponent then
        self:debug("Room Controls sync disabled (component not available)")
        return
    end
    
    self.syncTimer = Timer.New()
    self.syncTimer.EventHandler = function()
        self.roomAutomationModule:syncRoomControlsState()
        self.syncTimer:Start(1)
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
    self:stopSyncTimer()
    
    if self.uciTouchInactivityTimer then
        self.uciTouchInactivityTimer:Stop()
        self:debug("Touch inactivity timer stopped")
    end
    
    local modules = {
        self.layerModule, self.sublayerModule,
        self.videoSwitcherModule, self.roomAutomationModule, self.progressModule,
        self.divisibleSpaceModule
    }
    
    for _, module in ipairs(modules) do
        if module and module.cleanup then module:cleanup() end
    end
    
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
    if not targetPageName or targetPageName == "" then
        print("ERROR: UCI Factory - Invalid or missing target page name")
        return nil
    end
    
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
    
    for i, pageName in ipairs(pageNames) do
        local success, result = pcall(function()
            return UCIController.new(pageName, defaultRoutingLayer, defaultActiveLayer, hiddenNavIndices)
        end)
        
        if success and result then
            print("✓ UCI Factory: Successfully created controller for page '" .. pageName .. "' (attempt " .. i .. ")")
            
            _G.myUCI = result
            _G.UCIController = UCIController
            
            return result
        else
            lastError = result
            print("✗ UCI Factory: Attempt " .. i .. " failed for '" .. pageName .. "': " .. tostring(lastError))
        end
    end
    
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
    
    print("✗ UCI Factory: Complete failure - Could not create any controller for '" .. targetPageName .. "'")
    print("✗ Last error: " .. tostring(lastError))
    return nil
end

--------------[ Instance Creation ]-------------------------
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
    - After 60 seconds (configurable) of no touch activity, automatically returns to C05-Start layer
    - Optional control - gracefully degrades if not present

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController ledSystemPower state (1s interval)
    - Updates UCI layers and progress bar when power state changes externally
    - Prevents double-triggering of automation logic
    - Can be manually invoked via myUCI.roomAutomationModule:syncRoomControlsState()
]]

