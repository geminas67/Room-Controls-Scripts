--[[
  UCI Controller - Q-SYS Control Script
  
  Author: Nikolas Smith, Q-SYS
  Version: 3.0 | Date: 2025-01-28
  Firmware Req: 10.0.0
  
  Features:
  - Single-class architecture with direct method calls
  - Centralized data maps for sources, help overlays, HDMI states, and ACPR bypass
  - Event-driven synchronization with SystemAutomationController
  - Fail-fast control validation
  - Optimized layer visibility batching and legend management
  - Video switcher auto-detection (NV32, Extron DXP, AVProEdge)
  - Passcode support with inactivity timeout
]]

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Buttons (array for easy iteration)
    btnNav = {
        Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04,
        Controls.btnNav05, Controls.btnNav06, Controls.btnNav07, Controls.btnNav08,
        Controls.btnNav09, Controls.btnNav10, Controls.btnNav11, Controls.btnNav12,
        Controls.btnNav13
    },
    
    -- System Controls
    btnStartSystem      = Controls.btnStartSystem,
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel,
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    
    -- Help Buttons (organized as pairs)
    btnOpenHelp = {
        Laptop      = Controls.btnOpenHelpLaptop,
        PC          = Controls.btnOpenHelpPC,
        Wireless    = Controls.btnOpenHelpWireless,
        Routing     = Controls.btnOpenHelpRouting,
        StreamMusic = Controls.btnOpenHelpStreamMusic
    },
    btnCloseHelp = {
        Laptop      = Controls.btnCloseHelpLaptop,
        PC          = Controls.btnCloseHelpPC,
        Wireless    = Controls.btnCloseHelpWireless,
        Routing     = Controls.btnCloseHelpRouting,
        StreamMusic = Controls.btnCloseHelpStreamMusic
    },
    
    -- Routing Buttons (array for easy iteration)
    btnRouting = {
        Controls.btnRouting01, Controls.btnRouting02, Controls.btnRouting03,
        Controls.btnRouting04, Controls.btnRouting05
    },
    
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
    pinLEDHDMI03Active      = Controls.pinLEDHDMI03Active,
    pinLEDPresetSaved       = Controls.pinLEDPresetSaved,
    pinLEDHDMI01Connect     = Controls.pinLEDHDMI01Connect,
    pinLEDHDMI02Connect     = Controls.pinLEDHDMI02Connect,
    pinLEDHDMI03Connect     = Controls.pinLEDHDMI03Connect,
    pinLEDACPRBypassActive  = Controls.pinLEDACPRBypassActive,
    pinLEDTouchActivity     = Controls.pinLEDTouchActivity,
}

-------------------[ Configuration ]-------------------
local conferenceStateConfig = {
    skipLaptop = true,
    skipPC = true,
    skipWireless = true
}

local acprConfig = {
    disableACPRShow = true
}

-- Source switching priority configuration
-- Higher number = higher priority
-- Priority >= 100: Always switch (even during active calls) - typically call sources
-- Priority < 100: Only switch when NOT in an active call - typically HDMI sources
local sourceAutoSwitchPriorityConfig = {
    pinLEDOffHookLaptop = 200,   -- Highest priority - call on Laptop
    pinLEDOffHookPC     = 200,   -- Highest priority - call on PC
    pinLEDHDMI03Active  = 30,    -- Wireless HDMI (highest HDMI priority)
    pinLEDHDMI02Active  = 20,    -- PC HDMI
    pinLEDHDMI01Active  = 10,    -- Laptop HDMI (lowest HDMI priority)
    -- USB sources don't auto-switch (handled by conference state)
}

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

local function normalizeControlArrays()
    -- Normalize all array controls to consistent structures
    local arrayControls = {
        'btnNav', 'btnRouting'
    }
    
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then
            -- Convert single control to array format
            controls[controlName] = { ctrl }
        end
    end
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end  -- Guard against redundant assignments
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do bind(ctrl, function(ctl) handler(i, ctl) end) end
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
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

local function validateControls()
    -- Optional controls (for passcode functionality)
    local optionalControls = { "pinLEDTouchActivity" } -- Only needed if passcode timeout is used
    
    local missing = {}
    local warnings = {}
    
    for name, ctrl in pairs(controls) do
        if type(ctrl) == "table" then
            -- Handle arrays and nested tables (btnNav, btnRouting, btnOpenHelp, btnCloseHelp)
            for key, subCtrl in pairs(ctrl) do
                if not subCtrl then
                    table.insert(missing, name .. "[" .. tostring(key) .. "]")
                end
            end
        elseif not ctrl then
            -- Check if it's optional
            local isOptional = false
            for _, optName in ipairs(optionalControls) do
                if name == optName then
                    isOptional = true
                    break
                end
            end
            
            if isOptional then
                table.insert(warnings, name)
            else
                table.insert(missing, name)
            end
        end
    end
    
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    if #warnings > 0 then
        print("WARNING: UCIController - Missing optional controls (reduced functionality):")
        for _, name in ipairs(warnings) do
            local functionalityNote = ""
            if name == "pinLEDTouchActivity" then
                functionalityNote = " (passcode inactivity timeout disabled)"
            end
            print("  - " .. name .. functionalityNote)
        end
    end
    
    return true
end

-------------------[ Layer Data & Configuration ]-------------------
local layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
    "H01-PasscodeEntry","H05-RoomControls",
    "I01-CallActive","I02-HelpLaptop","I03-HelpPC","I04-HelpWireless","I05-HelpRouting","I07-HelpStreamMusic",
    "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J05-ConferenceControls",
    "L01-HDMIDisconnected","L05-Laptop",
    "P01-HDMIDisconnected","P05-PC","W05-Wireless",
    "R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05","R10-Routing",
    "S05-StreamMusic",
    "V05-Dialer",
    "X01-ProgramVolume","Y01-Navbar","Z01-Base"
}

-- Video Switcher Types Configuration
local SwitcherTypes = {
    NV32 = {
        componentType = "streamer_hdmi_switcher",
        switcherNames = {"devNV32", "compNV32"},
        routingMethod = "hdmi.out.1.select.index",
        defaultMapping = {[7] = 7, [8] = 8, [9] = 9}
    },
    ExtronDXP = {
        componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames = {"devExtronDXP", "compExtronDXP"},
        routingMethod = "output.1",
        defaultMapping = {[7] = 2, [8] = 4, [9] = 1}
    },
    AVProEdge = {
        componentType = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
        switcherNames = {"devAVProEdge", "compAVProEdge"},
        routingMethod = "trigger",
        defaultMapping = {[7] = "Input 3", [8] = "Input 4", [9] = "Input 1", [10] = "Input 2"}
    }
}

-------------------[ Controller ]-------------------
UCIController = {}
UCIController.__index = UCIController

function UCIController.new(uciPage, config)
    local self = setmetatable({}, UCIController)
    self.uciPage = uciPage or "UCI"
    self.debugging = config.debugging ~= false
    self.config = config
    self.varActiveLayer = config.defaultActiveLayer or 8
    self.defaultActiveLayer = config.defaultActiveLayer or 8
    self.hiddenNavIndices = config.hiddenNavIndices or {}
    self.isInitialized = false
    self.callActive = false  -- Cached call state for efficient lookups
    
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
    self.kLayerPasscode     = 13
    
    -- Routing state
    self.routingLayers = {
        "R01-Routing01", "R02-Routing02", "R03-Routing03",
        "R04-Routing04", "R05-Routing05"
    }
    self.activeRoutingLayer = config.defaultRoutingLayer or 1
    
    -- Layer module state
    self.layerStates = {}
    self.layerConfigs = nil  -- Built once during first showLayer() call
    
    -- Video switcher state
    self.videoSwitcherEnabled = false
    self.switcherComponent = nil
    self.switcherType = nil
    self.uciToInputMapping = {}
    
    -- Room automation state
    self.roomControlsComponent = nil
    self.previousPowerState = nil
    
    -- Progress state
    self.isAnimating = false
    self.loadingTimer = nil
    self.timeoutTimer = nil
    
    -- Passcode state
    self.compPasscode = nil
    self.roomIdentifier = nil
    self.passcodeEnabled = false
    
    -- Source data map
    self.sources = {
        PC = {
            layerConst   = 7,  -- kLayerPC
            hdmiPin      = controls.pinLEDHDMI01Connect,
            baseLayer    = "P05-PC",
            discLayer    = "P01-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBPC,
            usbConnect   = "J02-ConnectUSBPC",
            confLayer    = "J05-ConferenceControls",
            helpLayer    = "I03-HelpPC",
            btnOpen      = controls.btnOpenHelp.PC,
            btnClose     = controls.btnCloseHelp.PC
        },
        Laptop = {
            layerConst   = 8,  -- kLayerLaptop
            hdmiPin      = controls.pinLEDHDMI02Connect,
            baseLayer    = "L05-Laptop",
            discLayer    = "L01-HDMIDisconnected",
            usbPin       = controls.pinLEDUSBLaptop,
            usbConnect   = "J01-ConnectUSBLaptop",
            confLayer    = "J05-ConferenceControls",
            helpLayer    = "I02-HelpLaptop",
            btnOpen      = controls.btnOpenHelp.Laptop,
            btnClose     = controls.btnCloseHelp.Laptop
        },
        Wireless = {
            layerConst   = 9,  -- kLayerWireless
            hdmiPin      = controls.pinLEDHDMI03Connect,
            baseLayer    = "W05-Wireless",
            discLayer    = "W01-HDMIDisconnected",
            usbPin       = nil,
            usbConnect   = nil,
            confLayer    = nil,
            helpLayer    = "I04-HelpWireless",
            btnOpen      = controls.btnOpenHelp.Wireless,
            btnClose     = controls.btnCloseHelp.Wireless
        }
    }
    
    -- Help layer button map
    self.helpLayerButtonMap = {
        ["I02-HelpLaptop"]     = {open = controls.btnOpenHelp.Laptop,      close = controls.btnCloseHelp.Laptop},
        ["I03-HelpPC"]         = {open = controls.btnOpenHelp.PC,          close = controls.btnCloseHelp.PC},
        ["I04-HelpWireless"]   = {open = controls.btnOpenHelp.Wireless,    close = controls.btnCloseHelp.Wireless},
        ["I05-HelpRouting"]    = {open = controls.btnOpenHelp.Routing,     close = controls.btnCloseHelp.Routing},
        ["I07-HelpStreamMusic"]= {open = controls.btnOpenHelp.StreamMusic, close = controls.btnCloseHelp.StreamMusic},
    }
    
    -- Timers
    self.syncTimer = nil
    self.uciTouchInactivityTimer = Timer.New()
    
    return self
end

function UCIController:debug(msg)
    if self.debugging then
        print("[" .. self.uciPage .. "] " .. msg)
    end
end

-------------------[ Layer Methods ]-------------------
function UCIController:safeSetLayerVisibility(layer, visible, transition)
    local ok, err = pcall(function()
        Uci.SetLayerVisibility(self.uciPage, layer, visible, transition or "none")
    end)
    if ok then
        -- Only log if the state actually changed
        if self.layerStates[layer] ~= visible then
            self:debug("Layer '" .. layer .. "' -> " .. tostring(visible))
        end
        self.layerStates[layer] = visible
    else
        self:debug("Warning: Layer '" .. layer .. "' not found: " .. tostring(err))
    end
    return ok
end

function UCIController:updateLayerVisibility(layers, visible, transition)
    if not layers or visible == nil then return end
    for _, layer in ipairs(layers) do
        if layer then
            self:safeSetLayerVisibility(layer, visible, transition)
        end
    end
end

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
            show = {"H05-RoomControls"},
            hide = {"X01-ProgramVolume"},
            call = {function() self:updateCallActiveState() end}
        },
        [self.kLayerLaptop] = {
            show = {"L05-Laptop"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updateSourceHelpState("Laptop") end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerPC] = {
            show = {"P05-PC"},
            call = {
                function() self:updateHDMIForActiveSource() end,
                function() self:updateConferenceState() end,
                function() self:updatePresetSavedState() end,
                function() self:updateACPRBypassState() end,
                function() self:updateSourceHelpState("PC") end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerWireless] = {
            show = {"W05-Wireless"},
            call = {
                function() self:updateSourceHelpState("Wireless") end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerRouting] = {
            show = {"R10-Routing"},
            call = {
                function() self:updateRoutingHelpState() end,
                function() self:showRoutingLayer() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerDialer] = {
            show = {"V05-Dialer"},
            call = {
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerStreamMusic] = {
            show = {"S05-StreamMusic"},
            call = {
                function() self:updateStreamMusicHelpState() end,
                function() self:updateCallActiveState() end
            }
        },
        [self.kLayerPasscode] = {
            show = {"H01-PasscodeEntry"},
            hideBase = true,
            call = {
                function() self:resetTouchInactivityTimer() end,
                function() self:updateCallActiveState() end
            }
        }
    }
end

function UCIController:showLayer()
    -- Build layer configs once on first call
    if not self.layerConfigs then
        self.layerConfigs = self:buildLayerConfigs()
    end
    
    -- Hide everything first
    self:updateLayerVisibility(layersToHide, false, "none")

    local active = self.varActiveLayer
    local config = self.layerConfigs[active]
    if not config then return end

    -- Show base layers only if config doesn't hide them
    if not config.hideBase then
        self:updateLayerVisibility({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, true, "none")
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

function UCIController:resetLayerStates()
    self.layerStates = {}
    self:debug("Layer states reset")
end

-------------------[ Passcode Methods ]-------------------
function UCIController:extractRoomFromPageName()
    local pageName = self.uciPage
    -- Extract everything after "uci" with optional spaces
    -- Examples: "uciBoardroom" -> "Boardroom", "uci Boardroom" -> "Boardroom"
    local room = pageName:match("^uci%s*(.+)$")
    if room then
        -- Trim any trailing whitespace
        room = room:match("^%s*(.-)%s*$")
        self.roomIdentifier = room
        self:debug("Extracted room identifier: " .. room)
        return self.roomIdentifier
    end
    self:debug("Failed to extract room identifier from: " .. pageName)
    return nil
end

function UCIController:initializePasscode()
    local roomId = self:extractRoomFromPageName()
    if not roomId then
        self:debug("Cannot initialize without room identifier")
        return false
    end

    local componentName = "passcode" .. roomId
    local success, component = pcall(function()
        return Component.New(componentName)
    end)
    
    if success and component then
        self.compPasscode = component
        self.passcodeEnabled = true
        self:debug("Passcode component initialized: " .. componentName)
        self:registerPasscodeHandler()
        return true
    else
        self:debug("Passcode component not found: " .. componentName .. " (feature disabled)")
        return false
    end
end

function UCIController:registerPasscodeHandler()
    if not self.compPasscode or not self.compPasscode["PasscodeCorrect"] then
        self:debug("PasscodeCorrect control not found")
        return false
    end

    self.compPasscode["PasscodeCorrect"].EventHandler = function(ctl)
        self:onPasscodeCorrect(ctl.Boolean)
    end

    self:debug("PasscodeCorrect EventHandler registered for " .. self.roomIdentifier)
    return true
end

function UCIController:onPasscodeCorrect(isCorrect)
    if not isCorrect then 
        self:debug("Incorrect passcode entered")
        return 
    end
    
    self:debug("Correct passcode entered for " .. self.roomIdentifier)
    
    -- Hide passcode layer
    self:updateLayerVisibility({"H01-PasscodeEntry"}, false, "fade")
    
    -- Start the system directly (bypass passcode check since we just validated it)
    self:powerOn()
    self:startLoadingBar(true)
    self:btnNavEventHandler(self.kLayerWarming, "Passcode Correct")
end

function UCIController:isPasscodeCorrect()
    if not self.passcodeEnabled or not self.compPasscode then
        return true -- If no passcode component, allow access
    end

    if self.compPasscode["PasscodeCorrect"] then
        return self.compPasscode["PasscodeCorrect"].Boolean
    end

    return true -- Default to allowing access if control doesn't exist
end


-------------------[ Sublayer Methods ]-------------------
function UCIController:getActiveSource()
    -- Direct comparison - simpler than maintaining reverse lookup table
    local activeLayer = self.varActiveLayer
    for name, src in pairs(self.sources) do
        if src.layerConst == activeLayer then
            return src
        end
    end
    return nil
end

function UCIController:checkHDMIConnection()
    local src = self:getActiveSource()
    if not src then return true end
    local hdmiPin = src.hdmiPin
    return not hdmiPin or hdmiPin.Boolean
end

function UCIController:syncHelpButtonStates(helpLayer)
    local map = self.helpLayerButtonMap[helpLayer]
    if not map then return end
    local visible = self.layerStates[helpLayer]
    if visible == nil then return end  -- Early exit if state unknown
    setProp(map.open, "Boolean", visible)
    setProp(map.close, "Boolean", false)
end

function UCIController:isInCall()
    return self.callActive
end

function UCIController:shouldAutoSwitchSource(triggerPinName)
    local priority = sourceAutoSwitchPriorityConfig[triggerPinName]
    if not priority then 
        self:debug("Source switch not allowed: No priority config for " .. triggerPinName .. " (please add to sourceAutoSwitchPriorityConfig)")
        return false
    end
    
    -- Priority >= 100 always switches (call sources - highest priority)
    if priority >= 100 then 
        self:debug("Source switch allowed: High priority (" .. priority .. ") for " .. triggerPinName)
        return true 
    end
    -- Lower priority sources blocked during active calls
    if self:isInCall() then
        self:debug("Source switch BLOCKED: Call in progress, priority " .. priority .. " insufficient for " .. triggerPinName)
        return false
    end
    
    self:debug("Source switch allowed: Priority " .. priority .. " for " .. triggerPinName .. " (no call active)")
    return true
end

function UCIController:handlePrioritySourceSwitch(triggerPinName, targetLayer)
    if self:shouldAutoSwitchSource(triggerPinName) then
        self:ensureSystemIsOn(targetLayer)
    end
end

function UCIController:updateCallActiveState()
    local isActive = controls.pinCallActive.Boolean or false
    self.callActive = isActive  -- Update cached state
    self:updateLayerVisibility({"I01-CallActive"}, isActive, isActive and "fade" or "none")
    self:debug("Call Active: " .. (isActive and "Showing" or "Hiding"))
    self:updateACPRBypassState()
end

function UCIController:updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved.Boolean or false
    self:updateLayerVisibility({"J04-CamPresetSaved"}, isVisible, isVisible and "fade" or "none")
    self:debug("Preset Saved: " .. (isVisible and "Showing" or "Hiding"))
end

-- Generic HDMI handler using source map
function UCIController:updateHDMIForActiveSource()
    local src = self:getActiveSource()
    if not src then return end

    local isConnected = src.hdmiPin and src.hdmiPin.Boolean or false
    if isConnected then
        self:updateLayerVisibility({src.baseLayer}, true, "fade")
        self:updateLayerVisibility({src.discLayer}, false, "none")
        self:debug("HDMI " .. src.baseLayer .. ": Connected")
        self:updateACPRBypassState()
        self:updateConferenceState()
        return
    end
    -- On disconnect: show disconnect layer, hide base + conference + ACPR + help
    self:updateLayerVisibility({src.discLayer}, true, "fade")
    self:updateLayerVisibility({src.baseLayer, "J03-ACPRActive", src.confLayer}, false, "none")
    if src.helpLayer then
        self:syncHelpButtonStates(src.helpLayer)
    end
    self:debug("HDMI " .. src.baseLayer .. ": Disconnected")
end

-- Generic source help handler using source map
function UCIController:updateSourceHelpState(srcKey)
    local src = self.sources[srcKey]
    if not src then return end

    -- HDMI gate: help hidden if HDMI is not connected (only if source has HDMI)
    if src.hdmiPin and not self:checkHDMIConnection() then
        self:updateLayerVisibility({src.helpLayer}, false, "none")
        self:syncHelpButtonStates(src.helpLayer)
        self:debug(srcKey .. " Help: Hiding (HDMI not connected)")
        return
    end

    local isVisible = src.btnOpen.Boolean or false
    if isVisible then
        self:updateLayerVisibility({src.helpLayer}, true, "fade")
        -- Hide conference/USB layers if they exist (Laptop/PC have these, Wireless doesn't)
        local layersToHide = {}
        if src.confLayer then table.insert(layersToHide, "J05-ConferenceControls") end
        -- Hide all USB connect layers when showing help (not just this source's)
        table.insert(layersToHide, "J01-ConnectUSBLaptop")
        table.insert(layersToHide, "J02-ConnectUSBPC")
        if #layersToHide > 0 then
            self:updateLayerVisibility(layersToHide, false, "none")
        end
    else
        self:updateLayerVisibility({src.helpLayer}, false, "none")
        -- Only update conference state if this source has conference controls
        if src.confLayer then
            self:updateConferenceState()
        end
    end

    self:syncHelpButtonStates(src.helpLayer)
    self:debug(srcKey .. " Help: " .. (isVisible and "Showing" or "Hiding"))
end

-- Conference state using source map
function UCIController:updateConferenceState()
    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        local hideLayers = {
            "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J05-ConferenceControls"
        }
        if src.helpLayer then 
            table.insert(hideLayers, src.helpLayer)
            self:updateLayerVisibility(hideLayers, false, "none")
            self:syncHelpButtonStates(src.helpLayer)
        end
        self:debug("Conference blocked: HDMI not connected for " .. src.baseLayer)
        return
    end

    -- ACPR priority gate: ACPR overrides conference controls when call is active
    local isBypassActive = controls.pinLEDACPRBypassActive.Boolean or false
    local isCallActive = controls.pinCallActive.Boolean or false
    if not isBypassActive and isCallActive then
        self:updateLayerVisibility({src.confLayer}, false, "none")
        self:debug("Conference blocked: ACPR active during call")
        return
    end

    -- Config skip
    if src.layerConst == self.kLayerLaptop and conferenceStateConfig.skipLaptop then return end
    if src.layerConst == self.kLayerPC and conferenceStateConfig.skipPC then return end
    if src.layerConst == self.kLayerWireless and conferenceStateConfig.skipWireless then return end

    local usbConnected = src.usbPin and src.usbPin.Boolean or false
    if usbConnected then
        self:updateLayerVisibility({src.confLayer}, true, "fade")
        self:updateLayerVisibility({
            "J01-ConnectUSBLaptop","J02-ConnectUSBPC"
        }, false, "none")
    else
        self:updateLayerVisibility({src.usbConnect}, true, "fade")
        self:updateLayerVisibility({src.confLayer, src.helpLayer}, false, "none")
        if src.helpLayer then self:syncHelpButtonStates(src.helpLayer) end
    end
    self:debug("Conference: " .. src.confLayer .. " " .. (usbConnected and "Connected" or "Disconnected"))
end

-------------------[ ACPR Bypass Methods ]-------------------
function UCIController:updateACPRBypassState()
    if acprConfig.disableACPRShow then
        self:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        self:debug("ACPR Show logic disabled via acprConfig")
        return
    end

    local src = self:getActiveSource()
    if not src then return end

    -- HDMI gate
    if not self:checkHDMIConnection() then
        self:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        self:debug("ACPR bypass check blocked: HDMI not connected")
        return
    end

    local isBypassActive = controls.pinLEDACPRBypassActive.Boolean or false
    local isCallActive = controls.pinCallActive.Boolean or false

    -- J03-ACPRActive requires call to be active
    if not isBypassActive and isCallActive then
        self:updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
        self:updateLayerVisibility({src.confLayer}, false, "none")
    else
        self:updateLayerVisibility({src.confLayer}, isBypassActive and true or false, isBypassActive and "fade" or "none")
        self:updateLayerVisibility({"J03-ACPRActive"}, false, "none")
    end
    self:debug("ACPR Bypass: " .. (isBypassActive and "Active" or "Inactive") .. " | Call: " .. (isCallActive and "Active" or "Inactive"))
end

function UCIController:updateRoutingHelpState()
    local isVisible = controls.btnOpenHelp.Routing.Boolean or false
    self:updateLayerVisibility({"I05-HelpRouting"}, isVisible, "none")
    self:syncHelpButtonStates("I05-HelpRouting")
    self:debug("Routing Help: " .. (isVisible and "Showing" or "Hiding"))
end

function UCIController:updateStreamMusicHelpState()
    local isVisible = controls.btnOpenHelp.StreamMusic.Boolean or false
    self:updateLayerVisibility({"I07-HelpStreamMusic"}, isVisible, "none")
    self:syncHelpButtonStates("I07-HelpStreamMusic")
    self:debug("Stream Music Help: " .. (isVisible and "Showing" or "Hiding"))
end


-------------------[ Video Switcher Methods ]-------------------
function UCIController:initializeVideoSwitcher()
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
    self.uciToInputMapping = SwitcherTypes[switcherType].defaultMapping
    self.videoSwitcherEnabled = true
    self:debug("Video switcher initialized: " .. switcherType)
    return true
end

function UCIController:autoDetectSwitcher()
    -- First check control references (fastest)
    for switcherType, config in pairs(SwitcherTypes) do
        for _, switchName in ipairs(config.switcherNames) do
            local ctrl = Controls[switchName]
            if ctrl and ctrl.String ~= "" then
                return switcherType, ctrl.String
            end
        end
    end
    
    -- Then check components (slower) - build lookup table to avoid nested loops
    local components = Component.GetComponents()
    local typeMap = {}
    for switcherType, config in pairs(SwitcherTypes) do
        typeMap[config.componentType] = switcherType
    end
    
    for _, comp in pairs(components) do
        local switcherType = typeMap[comp.Type]
        if switcherType then
            return switcherType, comp.Name
        end
    end
    
    return nil, nil
end

function UCIController:switchToInput(inputNumber, uciButton)
    if not self.videoSwitcherEnabled then return false end
    if not self.switcherComponent then return false end
    if not inputNumber or not uciButton then return false end
    
    self:debug("Switching to input " .. inputNumber .. " via UCI button " .. uciButton)
    
    local success, err = pcall(function()
        local config = SwitcherTypes[self.switcherType]
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

-------------------[ Room Automation Methods ]-------------------
function UCIController:initializeRoomControls()
    local componentName = nil
    
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    
    if not componentName then
        local pageName = self.uciPage:match("uci%s+([^(]+)")
        if pageName then
            componentName = "compRoomControls" .. pageName:gsub("%s+", "")
        end
        if not componentName then
            self:debug("Could not determine Room Controls component name")
            return false
        end
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

function UCIController:powerOn()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debug("Cannot power on: Room Controls component not available")
        return false
    end
    -- Set btnSystemOnOff control to trigger power on (ledSystemPower will update via SystemAutomationController)
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = true end)
    if ok then self:debug("Room powered ON") else self:debug("Failed to power on room automation") end
    return ok
end

function UCIController:powerOff()
    if not self.roomControlsComponent or not self.roomControlsComponent["btnSystemOnOff"] then
        self:debug("Cannot power off: Room Controls component not available")
        return false
    end
    -- Set btnSystemOnOff control to trigger power off (ledSystemPower will update via SystemAutomationController)
    local ok = pcall(function() self.roomControlsComponent["btnSystemOnOff"].Boolean = false end)
    if ok then self:debug("Room powered OFF") else self:debug("Failed to power off room automation") end
    return ok
end

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

function UCIController:syncRoomControlsState() -- use ledSystemPower as authoritative status
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
        self:startLoadingBar(true)
        self:btnNavEventHandler(self.kLayerWarming, "Room Automation Power On")
        self:debug("Synchronized to WARMING state")
    else
        self:startLoadingBar(false)
        self:btnNavEventHandler(self.kLayerCooling, "Room Automation Power Off")
        self:debug("Synchronized to COOLING state")
    end
end

-------------------[ Progress Methods ]-------------------
function UCIController:startLoadingBar(isPoweringOn)
    if self.isAnimating then return end
    
    self.isAnimating = true
    local duration = self:getTiming(isPoweringOn)
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
            self:btnNavEventHandler(isPoweringOn and self.defaultActiveLayer or self.kLayerStart, "Loading Timeout")
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
            
            local targetLayer = isPoweringOn and self.defaultActiveLayer or self.kLayerStart
            self:btnNavEventHandler(targetLayer, isPoweringOn and "Warmup Complete" or "Cooldown Complete")
        else
            self.loadingTimer:Start(interval)
        end
    end
    
    self.loadingTimer:Start(interval)
    self:debug("Loading bar started (" .. duration .. "s)")
end

-------------------[ Touch Inactivity Methods ]-------------------
function UCIController:onPasscodeInactivity()
    self:debug("Touch inactivity timeout - returning to Start layer")
    self:btnNavEventHandler(self.kLayerStart, "Inactivity Timeout")
end

function UCIController:resetTouchInactivityTimer()
    if not self.uciTouchInactivityTimer then return end
    
    local success, err = pcall(function()
        self.uciTouchInactivityTimer:Stop()
        
        -- Check if we're on the Passcode layer
        local isOnPasscode = (self.varActiveLayer == self.kLayerPasscode)
        
        if isOnPasscode then
            local timeout = tonumber(Uci.Variables.numTouchInactivityTimer.Value) or 60
            if timeout <= 0 then
                timeout = 60
                self:debug("Warning: Invalid timeout value, using default 60s")
            end
            
            self.uciTouchInactivityTimer.EventHandler = function() self:onPasscodeInactivity() end
            self.uciTouchInactivityTimer:Start(timeout)
            self:debug("Touch inactivity timer reset (" .. timeout .. "s)")
        else
            self:debug("Touch inactivity timer not started (not on Passcode layer)")
        end
    end)
    
    if not success then
        self:debug("Failed to reset touch inactivity timer: " .. tostring(err))
    end
end

-------------------[ Event Registration ]-------------------
function UCIController:registerEventHandlers()
    -- Navigation buttons
    for i, btn in ipairs(controls.btnNav) do
        if btn then
            bind(btn, function() self:btnNavEventHandler(i, "User Button") end)
        end
    end
    
    -- Routing buttons
    for i, btn in ipairs(controls.btnRouting) do
        if btn then
            bind(btn, function() self:routingButtonEventHandler(i) end)
        end
    end
    
    -- Help control pairs
    local helpControlPairs = {
        {open = controls.btnOpenHelp.Laptop, close = controls.btnCloseHelp.Laptop, handler = function() self:updateSourceHelpState("Laptop") end},
        {open = controls.btnOpenHelp.PC, close = controls.btnCloseHelp.PC, handler = function() self:updateSourceHelpState("PC") end},
        {open = controls.btnOpenHelp.Wireless, close = controls.btnCloseHelp.Wireless, handler = function() self:updateSourceHelpState("Wireless") end},
        {open = controls.btnOpenHelp.Routing, close = controls.btnCloseHelp.Routing, handler = function() self:updateRoutingHelpState() end},
        {open = controls.btnOpenHelp.StreamMusic, close = controls.btnCloseHelp.StreamMusic, handler = function() self:updateStreamMusicHelpState() end}
    }
    for _, pair in ipairs(helpControlPairs) do
        bindPairedControls(pair.open, pair.close, pair.handler)
    end
    
    -- Flattened handler map - all controls in single table for efficient registration
    -- BEST PRACTICE: Route all layer changes through ensureSystemIsOn() for centralized state management
    local allHandlers = {
        -- System controls
        [controls.btnStartSystem] = function()
            self:ensureSystemIsOn(self.defaultActiveLayer)
        end,
        [controls.btnNavShutdown] = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
        end,
        [controls.btnShutdownCancel] = function()
            self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        end,
        [controls.btnShutdownConfirm] = function()
            self:shutdownSystem()
        end,
        -- Pin state handlers
        [controls.pinLEDUSBLaptop] = function(ctl)
            if ctl.Boolean then 
                self:ensureSystemIsOn(self.kLayerLaptop)
            else
                self:updateConferenceState()
            end
        end,
        [controls.pinLEDUSBPC] = function(ctl)
            if ctl.Boolean then 
                self:ensureSystemIsOn(self.kLayerPC)
            else
                self:updateConferenceState()
            end
        end,
        [controls.pinLEDOffHookLaptop] = function(ctl)
            if ctl.Boolean then 
                self:handlePrioritySourceSwitch("pinLEDOffHookLaptop", self.kLayerLaptop)
            end
        end,
        [controls.pinLEDOffHookPC] = function(ctl)
            if ctl.Boolean then 
                self:handlePrioritySourceSwitch("pinLEDOffHookPC", self.kLayerPC)
            end
        end,
        [controls.pinLEDHDMI01Active] = function(ctl)
            if ctl.Boolean then 
                self:handlePrioritySourceSwitch("pinLEDHDMI01Active", self.kLayerLaptop)
            end
        end,
        [controls.pinLEDHDMI02Active] = function(ctl)
            if ctl.Boolean then 
                self:handlePrioritySourceSwitch("pinLEDHDMI02Active", self.kLayerPC)
            end
        end,
        [controls.pinLEDHDMI03Active] = function(ctl)
            if ctl.Boolean then 
                self:handlePrioritySourceSwitch("pinLEDHDMI03Active", self.kLayerWireless)
            end
        end,
        [controls.pinLEDPresetSaved] = function()
            self:updatePresetSavedState()
        end,
        [controls.pinLEDHDMI01Connect] = function()
            self:updateHDMIForActiveSource()
        end,
        [controls.pinLEDHDMI02Connect] = function()
            self:updateHDMIForActiveSource()
        end,
        [controls.pinLEDHDMI03Connect] = function()
            self:updateHDMIForActiveSource()
        end,
        [controls.pinLEDACPRBypassActive] = function()
            self:updateACPRBypassState()
        end,
        [controls.pinCallActive] = function()
            self:updateCallActiveState()
        end,
        [controls.pinLEDTouchActivity] = function(ctl)
            self:resetTouchInactivityTimer()
        end
    }
    
    -- Single iteration to register all handlers
    for ctrl, handler in pairs(allHandlers) do
        bind(ctrl, handler)
    end
    
    self:debug("Event handlers registered (optimized single-pass)")
end

-------------------[ System Control Methods ]-------------------
function UCIController:startSystem()
    -- NOTE: Passcode check is handled by ensureSystemIsOn() - don't check again here
    -- This method should only be called after passcode validation
    self:powerOn()
    self:startLoadingBar(true)
    self:btnNavEventHandler(self.kLayerWarming, "System Start")
end

function UCIController:shutdownSystem()
    self:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
    self:powerOff()
    self:startLoadingBar(false)
    self:btnNavEventHandler(self.kLayerCooling, "System Shutdown")
end

function UCIController:ensureSystemIsOn(targetLayer)
    targetLayer = targetLayer or self.defaultActiveLayer
    
    -- Check if system is already on
    local isSystemOn = false
    if self.roomControlsComponent and 
       self.roomControlsComponent["ledSystemPower"] then
        isSystemOn = self.roomControlsComponent["ledSystemPower"].Boolean
    end
    
    if isSystemOn then
        -- System is already ON, navigate to target layer
        self:debug("ensureSystemIsOn: System is already on, navigating to layer " .. targetLayer)
        self:btnNavEventHandler(targetLayer, "Source Active")
    else
        -- System is OFF, need to start it
        -- Check if passcode is enabled and correct
        if self.passcodeEnabled and not self:isPasscodeCorrect() then
            self:debug("ensureSystemIsOn: Passcode required, navigating to passcode layer")
            self:btnNavEventHandler(self.kLayerPasscode, "Passcode Required")
        else
            -- No passcode or already correct, start system
            self:debug("ensureSystemIsOn: Starting system")
            self:startSystem()
        end
    end
end


-------------------[ Navigation Methods ]-------------------
function UCIController:btnNavEventHandler(argIndex, source)
    source = source or "Navigation"
    local previousLayer = self.varActiveLayer
    self.varActiveLayer = argIndex
    
    if self.videoSwitcherEnabled then
        local inputNumber = self.uciToInputMapping[argIndex]
        if inputNumber then
            self:debug("Video switch to input " .. inputNumber .. " (Source: " .. source .. ")")
            self:switchToInput(inputNumber, argIndex)
        end
    end
    
    self:showLayer()
    self:interlock()
    self:debug("Layer " .. previousLayer .. " → " .. argIndex .. " (Source: " .. source .. ")")
end

function UCIController:interlock()
    -- Layer constants are already the button indices (1-13) 
    local activeButtonIndex = self.varActiveLayer
    
    for i, btn in ipairs(controls.btnNav) do
        if btn then
            local shouldBeActive = (i == activeButtonIndex)
            setProp(btn, "Boolean", shouldBeActive)
        end
    end
end

-------------------[ Routing Methods ]-------------------
function UCIController:getRoutingButtons()
    return controls.btnRouting
end

function UCIController:showRoutingLayer()
    if self.activeRoutingLayer < 1 or self.activeRoutingLayer > #self.routingLayers then
        self.activeRoutingLayer = 1
    end
    
    -- Batch all hide operations into single array
    local layersToHideRouting = {"X01-ProgramVolume"}
    for i = 1, #self.routingLayers do
        table.insert(layersToHideRouting, self.routingLayers[i])
    end
    self:updateLayerVisibility(layersToHideRouting, false, "none")
    
    -- Show active routing layer
    self:updateLayerVisibility({self.routingLayers[self.activeRoutingLayer]}, true, "fade")
    self:interlockRoutingButtons()
end

function UCIController:interlockRoutingButtons()
    local routingButtons = self:getRoutingButtons()
    for i, btn in ipairs(routingButtons) do
        if btn then
            btn.Boolean = (i == self.activeRoutingLayer)
        end
    end
end

function UCIController:routingButtonEventHandler(buttonIndex)
    if buttonIndex < 1 or buttonIndex > #self.routingLayers then
        self:debug("Invalid routing button index: " .. tostring(buttonIndex))
        return
    end
    
    self.activeRoutingLayer = buttonIndex
    self:showRoutingLayer()
    self:debug("Routing layer switched to: " .. self.routingLayers[buttonIndex])
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

-------------------[ Legend Management ]-------------------
function UCIController:initializeLegendArrays()
    local legendConfig = {
        {suffix = "Nav", count = 13},        -- Navigation labels (Nav01 - Nav13)
        {suffix = "Routing", count = 5},     -- Routing labels (Routing01 - Routing05)
        {suffix = "VidSrc", count = 12},     -- Audio source labels (AudSrc01 - AudSrc12)
        {suffix = "Gain", count = 10},       -- Gain labels (Gain01 - Gain10)
        {suffix = "Display", count = 4},      -- Display labels (Display01 - Display04)
        {single = {"NavShutdown", "RoomNameNav", "RoomNameStart", "RoutingRooms",
        "RoutingSources", "GainPGM"}}, -- Single labels
    }
    
    self.arrUCILegends = {}
    self.arrUCIUserLabels = {}
    local idx = 0
    
    for _, config in ipairs(legendConfig) do
        if config.suffix then
            for i = 1, config.count do
                idx = idx + 1
                local name = config.suffix .. string.format("%02d", i)
                self.arrUCILegends[idx] = Controls["txt" .. name]
                self.arrUCIUserLabels[idx] = Uci.Variables["txtLabel" .. name]
            end
        elseif config.single then
            for _, name in ipairs(config.single) do
                idx = idx + 1
                self.arrUCILegends[idx] = Controls["txt" .. name]
                self.arrUCIUserLabels[idx] = Uci.Variables["txtLabel" .. name]
            end
        end
    end
    
    -- Register event handlers
    for i, label in ipairs(self.arrUCIUserLabels) do
        if label then 
            label.EventHandler = function() 
                self:updateLegends() 
            end 
        end
    end
    
    self:debug("Legend arrays initialized with " .. #self.arrUCILegends .. " controls and " .. #self.arrUCIUserLabels .. " variables")
end

-------------------[ Initialization ]-------------------
function UCIController:init()
    self:resetLayerStates()
    
    self:initializeLegendArrays()
    self:initializeRoomControls()
    self:initializeVideoSwitcher()
    self:initializePasscode()

    -- Set the default layer to start screen
    self.varActiveLayer = self.kLayerStart
    
    -- Synchronize with SystemAutomationController state if available
    -- Note: mySystemController and roomControlsComponent are the same Q-SYS component
    if mySystemController and mySystemController.state then
        local component = self.roomControlsComponent
        local systemPowerState = component and component["ledSystemPower"] and component["ledSystemPower"].Boolean
        
        if systemPowerState then
            if mySystemController.state.isWarming then
                self.varActiveLayer = self.kLayerWarming
                self:startLoadingBar(true)
                self:debug("Synchronized with Room Automation: WARMING")
            else
                self.varActiveLayer = self.defaultActiveLayer
                self:debug("Synchronized with Room Automation: READY")
            end
        else
            self:debug("Using default initialization (system OFF)")
        end
    else
        self:debug("Using default initialization (Room Automation not available)")
    end
    
    for _, index in ipairs(self.hiddenNavIndices) do
        local btn = controls.btnNav[index]
        if btn then
            btn.Visible = false
            self:debug("Hidden navigation button: btnNav[" .. index .. "]")
        end
    end
    
    self:showLayer()
    self:interlock()
    self:updateLegends()
    
    self:startSyncTimer()
    
    self:debug("UCI Initialized for " .. self.uciPage)
    self.isInitialized = true
end

function UCIController:startSyncTimer()
    if not self.roomControlsComponent then
        self:debug("Room Controls sync disabled (component not available)")
        return false
    end
    
    local success, timer = pcall(function()
        local roomControlsTimer = Timer.New()
        roomControlsTimer.EventHandler = function()
            self:syncRoomControlsState()
            roomControlsTimer:Start(1)
        end
        return roomControlsTimer
    end)
    
    if success and timer then
        self.syncTimer = timer
        self.syncTimer:Start(1)  -- Initial start
        self:debug("Room Controls state synchronization enabled (1s interval)")
        return true
    else
        self:debug("Failed to create sync timer: " .. tostring(timer))
        return false
    end
end

function UCIController:stopSyncTimer()
    if self.syncTimer then
        self.syncTimer:Stop()
        self.syncTimer = nil
        self:debug("Room Controls sync timer stopped")
    end
end

-------------------[ Cleanup ]-------------------
function UCIController:cleanup()
    self:stopSyncTimer()
    
    -- Stop touch inactivity timer
    if self.uciTouchInactivityTimer then
        self.uciTouchInactivityTimer:Stop()
        self.uciTouchInactivityTimer = nil
    end
    
    -- Stop progress timers
    if self.loadingTimer then self.loadingTimer:Stop(); self.loadingTimer = nil end
    if self.timeoutTimer then self.timeoutTimer:Stop(); self.timeoutTimer = nil end
    self.isAnimating = false
    
    -- Clean up passcode handler
    if self.compPasscode and self.compPasscode["PasscodeCorrect"] then
        self.compPasscode["PasscodeCorrect"].EventHandler = nil
    end
    
    -- Clean up legend event handlers
    if self.arrUCIUserLabels then
        for _, label in ipairs(self.arrUCIUserLabels) do
            if label then
                label.EventHandler = nil
            end
        end
    end
    
    self:debug("UCI Controller cleanup completed")
end

-------------------[ Factory & Configuration ]-------------------
local function getDefaultConfig()
    return {
        debugging = true,
        defaultRoutingLayer = tonumber(Uci.Variables.numDefaultRoutingLayer.Value) or 4,
        defaultActiveLayer = tonumber(Uci.Variables.numDefaultActiveLayer.Value) or 8,
        hiddenNavIndices = {}
    }
end

local function createUCIController(targetPageName, config)
    if not targetPageName or targetPageName == "" then 
        print("ERROR: Invalid UCI page name")
        return nil 
    end
    
    config = config or getDefaultConfig()
    
    local pageNames = {
        targetPageName,                                                 -- 1. Original: "Routing  Panel  (Main)"
        targetPageName:gsub("%s+", " "),                                -- 2. Normalized spaces: "Routing Panel (Main)"
        targetPageName:gsub("%s+", ""),                                 -- 3. No spaces: "RoutingPanel(Main)"
        targetPageName:gsub("%(", ""):gsub("%)", ""),                   -- 4. No parentheses: "Routing  Panel  Main"
        targetPageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", ""),  -- 5. Dashes instead of spaces, no parens: "Routing-Panel-Main"
        "UCI " .. targetPageName,                                       -- 6. With "UCI " prefix: "UCI Routing  Panel  (Main)"
        targetPageName:match("^(.-)%s*%(") or targetPageName            -- 7. Everything before first parenthesis: "Routing  Panel"
    }
    
    local lastError = nil
    
    for i, pageName in ipairs(pageNames) do
        local success, controller = pcall(function()
            local obj = UCIController.new(pageName, config)
            if not obj then error("Controller creation failed") end
            normalizeControlArrays()
            obj:registerEventHandlers()
            obj:init()
            return obj
        end)
        
        if success then
            print("UCIController initialized for " .. pageName)
            _G.myUCI = controller
            _G.UCIController = UCIController
            return controller
        else
            lastError = controller
            print("UCI creation attempt " .. i .. " failed for '" .. pageName .. "': " .. tostring(lastError))
        end
    end
    
    print("ERROR: " .. tostring(lastError))
    return nil
end

if not validateControls() then return end
local pageName = Uci.Variables.txtUCIPageName.String or "UCI"
local config = getDefaultConfig()
myUCI = createUCIController(pageName, config)

------------------[ Public API ]-----------------------------
--[[
Public API:
    myUCI:btnNavEventHandler(layerIndex)
    myUCI:cleanup()
    myUCI:startSyncTimer()
    myUCI:stopSyncTimer()
    myUCI:switchToInput(inputNumber, uciButton)
    myUCI:powerOn()
    myUCI:powerOff()
    myUCI:syncRoomControlsState()
    myUCI:startLoadingBar(isPoweringOn)

Event-Driven Synchronization:
    - Automatic monitoring of SystemAutomationController ledSystemPower status (1s interval)
    - Uses ledSystemPower as authoritative status indicator (not btnSystemOnOff)
    - Sets btnSystemOnOff to trigger power changes (control)
    - Monitors ledSystemPower to detect actual system state changes (status)
    - Updates UCI layers and progress bar when power state changes externally
    - Prevents double-triggering of automation logic
    - Can be manually invoked via myUCI:syncRoomControlsState()
]]