--[[
    UCIController (Refactored - Lean v2)
    Author: Nikolas Smith, Q-SYS
    Version: 2.2 | Date: 2025-12-29
    Firmware Req: 10.0.0
    Notes:
    - Centralized data maps for sources, help, HDMI, ACPR.
    - Reduced branching; single generic helpers for HDMI, help, conference, ACPR.
    - Fail-fast control validation preserved.
    - Applied DivisibleSpace lean patterns to single-room controller.
]]

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Buttons
    btnNav01 = Controls.btnNav01, btnNav02 = Controls.btnNav02, btnNav03 = Controls.btnNav03,
    btnNav04 = Controls.btnNav04, btnNav05 = Controls.btnNav05, btnNav06 = Controls.btnNav06,
    btnNav07 = Controls.btnNav07, btnNav08 = Controls.btnNav08, btnNav09 = Controls.btnNav09,
    btnNav10 = Controls.btnNav10, btnNav11 = Controls.btnNav11, btnNav12 = Controls.btnNav12,
    
    -- System Controls
    btnStartSystem      = Controls.btnStartSystem,
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel,
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    
    -- Help Buttons
    btnOpenHelpLaptop       = Controls.btnOpenHelpLaptop,
    btnOpenHelpPC           = Controls.btnOpenHelpPC,
    btnOpenHelpWireless     = Controls.btnOpenHelpWireless,
    btnOpenHelpRouting      = Controls.btnOpenHelpRouting,
    btnOpenHelpStreamMusic  = Controls.btnOpenHelpStreamMusic,
    
    btnCloseHelpLaptop      = Controls.btnCloseHelpLaptop,
    btnCloseHelpPC          = Controls.btnCloseHelpPC,
    btnCloseHelpWireless    = Controls.btnCloseHelpWireless,
    btnCloseHelpRouting     = Controls.btnCloseHelpRouting,
    btnCloseHelpStreamMusic = Controls.btnCloseHelpStreamMusic,
    
    -- Routing Buttons
    btnRouting01 = Controls.btnRouting01, btnRouting02 = Controls.btnRouting02,
    btnRouting03 = Controls.btnRouting03, btnRouting04 = Controls.btnRouting04, btnRouting05 = Controls.btnRouting05,
    
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
}

-------------------[ Configuration ]-------------------
local conferenceStateConfig = {
    skipLaptop = false,
    skipPC = false
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
    "H01-RoomControls",
    "I01-CallActive","I02-HelpLaptop","I03-HelpPC","I04-HelpWireless","I05-HelpRouting","I07-HelpStreamMusic",
    "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J05-ConferenceControls",
    "L01-HDMI01Disconnected","L05-Laptop",
    "P01-HDMI02Disconnected","P05-PC","W05-Wireless",
    "R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05","R10-Routing",
    "S05-StreamMusic",
    "V05-Dialer",
    "X01-ProgramVolume","Y01-Navbar","Z01-Base"
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
            show = {"H01-RoomControls"},
            hide = {"X01-ProgramVolume"},
            call = {function() controller.sublayerModule:updateCallActiveState() end}
        },
        [controller.kLayerLaptop] = {
            show = {"L05-Laptop"},
            call = {
                function() controller.sublayerModule:updateHDMIStateLaptop() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updateLaptopHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerPC] = {
            show = {"P05-PC"},
            call = {
                function() controller.sublayerModule:updateHDMIStatePC() end,
                function() controller.sublayerModule:updateConferenceState() end,
                function() controller.sublayerModule:updatePresetSavedState() end,
                function() controller.sublayerModule:updateACPRBypassState() end,
                function() controller.sublayerModule:updatePCHelpState() end,
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
                function() controller.sublayerModule:updateRoutingHelpState() end,
                function() controller.routingModule:showRoutingLayer() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerDialer] = {
            show = {"V05-Dialer"},
            call = {
                function() controller.sublayerModule:updateCallActiveState() end
            }
        },
        [controller.kLayerStreamMusic] = {
            show = {"S05-StreamMusic"},
            call = {
                function() controller.sublayerModule:updateStreamMusicHelpState() end,
                function() controller.sublayerModule:updateCallActiveState() end
            }
        }
    }
end

function LayerModule:showLayer()
    -- Hide everything
    self:updateLayerVisibility(layersToHide, false, "none")

    -- Base always on unless layer config hides it
    self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")

    local configs = self.configs or buildLayerConfigs(self.controller)
    self.configs = configs

    local active = self.controller.varActiveLayer
    local config = configs[active]
    if not config then return end

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

    -- Source data map: centralized configuration for all sources
    self.sources = {
        Laptop = {
            layerConst   = controller.kLayerLaptop,
            hdmiPin      = controls.pinLEDHDMI01Connect,
            baseLayer    = "L05-Laptop",
            discLayer    = "L01-HDMI01Disconnected",
            usbPin       = controls.pinLEDUSBLaptop,
            usbConnect   = "J01-ConnectUSBLaptop",
            confLayer    = "J05-ConferenceControls",
            helpLayer    = "I02-HelpLaptop",
            btnOpen      = controls.btnOpenHelpLaptop,
            btnClose     = controls.btnCloseHelpLaptop
        },
        PC = {
            layerConst   = controller.kLayerPC,
            hdmiPin      = controls.pinLEDHDMI02Connect,
            baseLayer    = "P05-PC",
            discLayer    = "P01-HDMI02Disconnected",
            usbPin       = controls.pinLEDUSBPC,
            usbConnect   = "J02-ConnectUSBPC",
            confLayer    = "J05-ConferenceControls",
            helpLayer    = "I03-HelpPC",
            btnOpen      = controls.btnOpenHelpPC,
            btnClose     = controls.btnCloseHelpPC
        }
    }

    -- Quick lookup from layerConst to source key
    self.layerToSource = {}
    for name, src in pairs(self.sources) do
        self.layerToSource[src.layerConst] = name
    end

    self.helpLayerButtonMap = {
        ["I02-HelpLaptop"]     = {open = "btnOpenHelpLaptop",     close = "btnCloseHelpLaptop"},
        ["I03-HelpPC"]         = {open = "btnOpenHelpPC",         close = "btnCloseHelpPC"},
        ["I04-HelpWireless"]   = {open = "btnOpenHelpWireless",   close = "btnCloseHelpWireless"},
        ["I05-HelpRouting"]    = {open = "btnOpenHelpRouting",    close = "btnCloseHelpRouting"},
        ["I07-HelpStreamMusic"]= {open = "btnOpenHelpStreamMusic",close = "btnCloseHelpStreamMusic"},
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
    self:updateACPRBypassState()
end

function SublayerModule:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"J04-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
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
        self:updateACPRBypassState()
        self:updateConferenceState()
        return
    end

    -- On disconnect: show disconnect layer, hide base + conference + ACPR + help
    self.controller.layerModule:updateLayerVisibility({src.discLayer}, true, "fade")
    self.controller.layerModule:updateLayerVisibility({src.baseLayer, "J03-ACPRActive", src.confLayer}, false, "none")
    if src.helpLayer then
        self:syncHelpButtonStates(src.helpLayer)
    end
    self:debug("HDMI " .. src.baseLayer .. ": Disconnected")
end

function SublayerModule:updateHDMIStateLaptop()
    if self.controller.varActiveLayer == self.controller.kLayerLaptop then
        self:updateHDMIForActiveSource()
    end
end

function SublayerModule:updateHDMIStatePC()
    if self.controller.varActiveLayer == self.controller.kLayerPC then
        self:updateHDMIForActiveSource()
    end
end

-- Generic source help handler using source map
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
            "J05-ConferenceControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC"
        }, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({src.helpLayer}, false, "none")
        self:updateConferenceState()
    end

    self:syncHelpButtonStates(src.helpLayer)
    self:debug(srcKey .. " Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateLaptopHelpState()
    self:updateSourceHelpState("Laptop")
end

function SublayerModule:updatePCHelpState()
    self:updateSourceHelpState("PC")
end

-- Conference state using source map
function SublayerModule:updateConferenceState()
    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        local hideLayers = {
            "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J05-ConferenceControls"
        }
        if src.helpLayer then table.insert(hideLayers, src.helpLayer) end
        self.controller.layerModule:updateLayerVisibility(hideLayers, false, "none")
        if src.helpLayer then self:syncHelpButtonStates(src.helpLayer) end
        self:debug("Conference blocked: HDMI not connected")
        return
    end

    -- Config skip
    if src.layerConst == self.controller.kLayerLaptop and conferenceStateConfig.skipLaptop then return end
    if src.layerConst == self.controller.kLayerPC and conferenceStateConfig.skipPC then return end

    local usbConnected = src.usbPin and src.usbPin.Boolean or false
    if usbConnected then
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({
            "J01-ConnectUSBLaptop","J02-ConnectUSBPC"
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
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        self:debug("ACPR Show logic disabled via acprConfig")
        return
    end

    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        self:debug("ACPR bypass check blocked: HDMI not connected")
        return
    end

    local isBypassActive = controls.pinLEDACPRBypassActive.Boolean or false
    local isCallActive = controls.pinCallActive.Boolean or false

    -- J03-ACPRActive requires call to be active
    if not isBypassActive and isCallActive then
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, false, "none")
    else
        self.controller.layerModule:updateLayerVisibility({src.confLayer}, isBypassActive and true or false, isBypassActive and "fade" or "none")
        self.controller.layerModule:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
    end
    self:debug("ACPR Bypass: " .. (isBypassActive and "Active" or "Inactive") .. " | Call: " .. (isCallActive and "Active" or "Inactive"))
end

function SublayerModule:updateWirelessHelpState()
    local isVisible = controls.btnOpenHelpWireless.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I04-HelpWireless"}, isVisible, "none")
    self:syncHelpButtonStates("I04-HelpWireless")
    self:debug("Wireless Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateRoutingHelpState()
    local isVisible = controls.btnOpenHelpRouting.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I05-HelpRouting"}, isVisible, "none")
    self:syncHelpButtonStates("I05-HelpRouting")
    self:debug("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
end

function SublayerModule:updateStreamMusicHelpState()
    local isVisible = controls.btnOpenHelpStreamMusic.Boolean or false
    self.controller.layerModule:updateLayerVisibility({"I07-HelpStreamMusic"}, isVisible, "none")
    self:syncHelpButtonStates("I07-HelpStreamMusic")
    self:debug("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
end

-------------------[ Routing Module ]----------------------
local RoutingModule = setmetatable({}, BaseModule); RoutingModule.__index = RoutingModule
function RoutingModule.new(controller)
    local self = BaseModule.new(controller, "Routing")
    setmetatable(self, RoutingModule)
    self.routingLayers = {
        "R01-Routing01", "R02-Routing02", "R03-Routing03",
        "R04-Routing04", "R05-Routing05"
    }
    self.activeRoutingLayer = 1
    return self
end

function RoutingModule:showRoutingLayer()
    if self.activeRoutingLayer < 1 or self.activeRoutingLayer > #self.routingLayers then
        self.activeRoutingLayer = 1
    end
    
    self.controller.layerModule:updateLayerVisibility({"X01-ProgramVolume"}, false, "none")
    
    for _, layer in ipairs(self.routingLayers) do
        self.controller.layerModule:updateLayerVisibility({layer}, false, "none")
    end
    
    self.controller.layerModule:updateLayerVisibility({self.routingLayers[self.activeRoutingLayer]}, true, "fade")
    self:interlockRoutingButtons()
end

function RoutingModule:getRoutingButtons()
    return {controls.btnRouting01, controls.btnRouting02, controls.btnRouting03, controls.btnRouting04, 
    controls.btnRouting05}
end

function RoutingModule:interlockRoutingButtons()
    local routingButtons = self:getRoutingButtons()
    for i, btn in ipairs(routingButtons) do
        btn.Boolean = (i == self.activeRoutingLayer)
    end
end

function RoutingModule:routingButtonEventHandler(buttonIndex)
    if buttonIndex < 1 or buttonIndex > #self.routingLayers then
        self:debug("Invalid routing button index: " .. tostring(buttonIndex))
        return
    end
    
    self.activeRoutingLayer = buttonIndex
    self:showRoutingLayer()
    self:debug("Routing layer switched to: " .. self.routingLayers[buttonIndex])
end

function RoutingModule:resetRoutingButtons()
    local routingButtons = self:getRoutingButtons()
    for i, btn in ipairs(routingButtons) do
        btn.Boolean = (i == self.activeRoutingLayer)
    end
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
    for switcherType, config in pairs(self.SwitcherTypes) do
        for _, switchName in ipairs(config.switcherNames) do
            if Controls[switchName] and Controls[switchName].String ~= "" then
                return switcherType, Controls[switchName].String
            end
        end
    end
    
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
            
            local targetLayer = isPoweringOn and self.controller.defaultActiveLayer or self.controller.kLayerStart
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
    self.varActiveLayer = defaultActiveLayer or 8
    self.defaultActiveLayer = defaultActiveLayer or 8
    self.hiddenNavIndices = hiddenNavIndices or {}
    self.isInitialized = false
    
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
    
    -- Initialize modules
    self.layerModule            = LayerModule.new(self)
    self.sublayerModule         = SublayerModule.new(self)
    self.routingModule          = RoutingModule.new(self)
    self.videoSwitcherModule    = VideoSwitcherModule.new(self)
    self.roomAutomationModule   = RoomAutomationModule.new(self)
    self.progressModule         = ProgressModule.new(self)
    
    self.syncTimer              = nil
    
    if defaultRoutingLayer then
        self.routingModule.activeRoutingLayer = defaultRoutingLayer
    end
    
    self:registerEventHandlers()
    self:init()
    
    return self
end

function UCIController:debug(msg)
    if self.debugging then
        print("[" .. self.uciPage .. "] " .. msg)
    end
end

-------------------[ Event Handler Registration ]----------
function UCIController:registerEventHandlers()
    -- Navigation buttons
    for i = 1, 12 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            bind(btn, function() self:btnNavEventHandler(i) end)
        end
    end
    
    -- Routing buttons
    for i = 1, 5 do
        local btn = controls["btnRouting" .. string.format("%02d", i)]
        if btn then
            bind(btn, function() self.routingModule:routingButtonEventHandler(i) end)
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
        {open = controls.btnOpenHelpLaptop, close = controls.btnCloseHelpLaptop, handler = function() self.sublayerModule:updateLaptopHelpState() end},
        {open = controls.btnOpenHelpPC, close = controls.btnCloseHelpPC, handler = function() self.sublayerModule:updatePCHelpState() end},
        {open = controls.btnOpenHelpWireless, close = controls.btnCloseHelpWireless, handler = function() self.sublayerModule:updateWirelessHelpState() end},
        {open = controls.btnOpenHelpRouting, close = controls.btnCloseHelpRouting, handler = function() self.sublayerModule:updateRoutingHelpState() end},
        {open = controls.btnOpenHelpStreamMusic, close = controls.btnCloseHelpStreamMusic, handler = function() self.sublayerModule:updateStreamMusicHelpState() end}
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
        [controls.pinLEDUSBLaptop] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerLaptop)
            else
                self.sublayerModule:updateConferenceState()
            end
        end,
        [controls.pinLEDUSBPC] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerPC)
            else
                self.sublayerModule:updateConferenceState()
            end
        end,
        [controls.pinLEDOffHookLaptop] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerLaptop)
            end
        end,
        [controls.pinLEDOffHookPC] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerPC)
            end
        end,
        [controls.pinLEDHDMI01Active] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerLaptop)
            end
        end,
        [controls.pinLEDHDMI02Active] = function(ctl)
            if ctl.Boolean then 
                ensureSystemIsOn()
                self:btnNavEventHandler(self.kLayerPC)
            end
        end,
        [controls.pinLEDPresetSaved] = function() self.sublayerModule:updatePresetSavedState() end,
        [controls.pinLEDHDMI01Connect] = function() self.sublayerModule:updateHDMIStateLaptop() end,
        [controls.pinLEDHDMI02Connect] = function() self.sublayerModule:updateHDMIStatePC() end,
        [controls.pinLEDACPRBypassActive] = function() self.sublayerModule:updateACPRBypassState() end,
        [controls.pinCallActive] = function() self.sublayerModule:updateCallActiveState() end
    }
    
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

function UCIController:interlock()
    if not self.layerToButtonMap then
        self.layerToButtonMap = {
            [self.kLayerAlarm]          = 1,
            [self.kLayerIncomingCall]   = 2,
            [self.kLayerStart]          = 3,
            [self.kLayerWarming]        = 4,
            [self.kLayerCooling]        = 5,
            [self.kLayerRoomControls]   = 6,
            [self.kLayerPC]             = 7,
            [self.kLayerLaptop]         = 8,
            [self.kLayerWireless]       = 9,
            [self.kLayerRouting]        = 10,
            [self.kLayerDialer]         = 11,
            [self.kLayerStreamMusic]    = 12
        }
    end
    
    local activeButtonIndex = self.layerToButtonMap[self.varActiveLayer]
    
    for i = 1, 12 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then
            local shouldBeActive = (i == activeButtonIndex)
            setProp(btn, "Boolean", shouldBeActive)
        end
    end
    
    if self.varActiveLayer ~= self.kLayerRouting then
        self.routingModule:resetRoutingButtons()
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
        "txtNav09", "txtNav10", "txtNav11", "txtNav12",
        "txtNavShutdown", "txtRoomNameNav", "txtRoomNameStart",
        "txtRoutingRooms", "txtRouting01", "txtRouting02", "txtRouting03","txtRouting04", "txtRouting05", "txtRoutingSources",
        "txtAudSrc01", "txtAudSrc02", "txtAudSrc03", "txtAudSrc04",
        "txtAudSrc05", "txtAudSrc06", "txtAudSrc07", "txtAudSrc08",
        "txtAudSrc09", "txtAudSrc10", "txtAudSrc11", "txtAudSrc12",
        "txtGainPGM", 
        "txtGain01", "txtGain02", "txtGain03", "txtGain04",
        "txtGain05", "txtGain06", "txtGain07", "txtGain08", "txtGain09", "txtGain10",
        "txtDisplay01", "txtDisplay02", "txtDisplay03", "txtDisplay04",
    }
    
    for i, controlName in ipairs(legendControls) do
        self.arrUCILegends[i] = Controls[controlName]
    end
    
    self.arrUCIUserLabels = {}
    local userLabelVariables = {
        "txtLabelNav01", "txtLabelNav02", "txtLabelNav03", "txtLabelNav04",
        "txtLabelNav05", "txtLabelNav06", "txtLabelNav07", "txtLabelNav08",
        "txtLabelNav09", "txtLabelNav10", "txtLabelNav11", "txtLabelNav12",
        "txtLabelNavShutdown", "txtLabelRoomNameNav", "txtLabelRoomNameStart",
        "txtLabelRoutingRooms", "txtLabelRouting01", "txtLabelRouting02", "txtLabelRouting03","txtLabelRouting04", "txtLabelRouting05", "txtLabelRoutingSources",
        "txtLabelAudSrc01", "txtLabelAudSrc02", "txtLabelAudSrc03", "txtLabelAudSrc04",
        "txtLabelAudSrc05", "txtLabelAudSrc06", "txtLabelAudSrc07", "txtLabelAudSrc08",
        "txtLabelAudSrc09", "txtLabelAudSrc10", "txtLabelAudSrc11", "txtLabelAudSrc12",
        "txtLabelGainPGM", 
        "txtLabelGain01", "txtLabelGain02", "txtLabelGain03", "txtLabelGain04",
        "txtLabelGain05", "txtLabelGain06", "txtLabelGain07", "txtLabelGain08", "txtLabelGain09", "txtLabelGain10",
        "txtLabelDisplay01", "txtLabelDisplay02", "txtLabelDisplay03", "txtLabelDisplay04",
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
                self.varActiveLayer = self.defaultActiveLayer
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
    
    local modules = {
        self.layerModule, self.sublayerModule, self.routingModule,
        self.videoSwitcherModule, self.roomAutomationModule, self.progressModule
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
            varActiveLayer = defaultActiveLayer or 8,
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
    tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 4,
    tonumber(Uci.Variables.numDefaultActiveLayer.Value) or 8,
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
    myUCI.videoSwitcherModule:switchToInput(inputNumber, uciButton)
    myUCI.roomAutomationModule:powerOn()
    myUCI.roomAutomationModule:powerOff()
    myUCI.roomAutomationModule:syncRoomControlsState()
    myUCI.progressModule:startLoadingBar(isPoweringOn)

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController ledSystemPower status (1s interval)
    - Uses ledSystemPower as authoritative status indicator (not btnSystemOnOff)
    - Sets btnSystemOnOff to trigger power changes (control)
    - Monitors ledSystemPower to detect actual system state changes (status)
    - Updates UCI layers and progress bar when power state changes externally
    - Prevents double-triggering of automation logic
    - Can be manually invoked via myUCI.roomAutomationModule:syncRoomControlsState()
]]