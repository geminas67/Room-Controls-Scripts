--[[
    UCIController (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 3.1 | Date: 2026-03-24
    Firmware Req: 10.0.0
    Notes:
    - Event-driven Room Controls synchronization via ledSystemPower.EventHandler (no timer polling).
    - Passcode protection for Room Combining layer with graceful degradation.
    - Touch inactivity timer for H04-RoomCombining layer.
    - Universal video switcher support: NV32, Extron DXP, auto-detected.
]]

-------------------[ Configuration ]------------------------
-- All non-base layers cleared at start of showLayer (excludes X01/Y01/Z01; see qsys-lua-architecture §8.5)
local layersToHide = {
    "A01-Alarm", "B01-IncomingCall", "C05-Start", "D01-ShutdownConfirm",
    "E01-SystemProgressWarming", "E02-SystemProgressCooling", "E05-SystemProgress",
    "H01-PasscodeEntry", "H04-RoomCombining", "H05-RoomControls",
    "I01-CallActive", "I02-HelpLaptop", "I03-HelpPC", "I04-HelpWireless",
    "I05-HelpRouting", "I06-HelpDialer", "I07-HelpStreamMusic",
    "J01-ConnectUSBLaptop", "J02-ConnectUSBPC", "J03-ACPRActive",
    "J04-CamPresetSaved", "J05-CameraControls",
    "L01-HDMI01Disconnected", "L05-Laptop",
    "P01-HDMI02Disconnected", "P05-PC", "W05-Wireless",
    "R01-Routing-SalonD", "R02-Routing-SalonE", "R03-Routing-SalonA",
    "R04-Routing-SalonB", "R05-Routing-SalonC", "R06-Routing-SalonF",
    "R07-Routing-SalonG", "R08-Routing-SalonH", "R10-Routing",
    "S10-StreamMusic", "V05-Dialer",
}

local layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}

local layersRouting = {
    "R01-Routing-SalonD", "R02-Routing-SalonE", "R03-Routing-SalonA",
    "R04-Routing-SalonB", "R05-Routing-SalonC", "R06-Routing-SalonF",
    "R07-Routing-SalonG", "R08-Routing-SalonH"
}

-- Drives initLegendArrays: control txt* ↔ Uci variable txtLabel*
local legendConfig = {
    { suffix = "Nav", count = 13 },
    { single = { "NavShutdown", "RoomNameNav", "RoomNameStart", "RoutingRooms" } },
    { suffix = "Routing", count = 8 },
    { single = { "RoutingSources" } },
    { suffix = "AudSrc", count = 8 },
    { single = { "GainPGM" } },
    { suffix = "Gain", count = 40 },
    { suffix = "Display", count = 4 },
}

local configSwitcher = {
    NV32 = {
        componentType  = "streamer_hdmi_switcher",
        switcherNames  = {"devNV32", "codenameNV32", "varNV32"},
        routingControl = "hdmi.out.1.select.index",
        setPropMode    = "Value",
        defaultMapping = {[7] = 5, [8] = 4, [9] = 6}
    },
    ExtronDXP = {
        componentType  = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames  = {"devExtronDXP", "codenameExtronDXP", "varExtronDXP"},
        routingControl = "output.1",
        setPropMode    = "String",
        defaultMapping = {[7] = 2, [8] = 4, [9] = 1}
    }
}

-- Layer index constants
local kLayer = {
    Alarm           = 1,
    IncomingCall    = 2,
    Start           = 3,
    Warming         = 4,
    Cooling         = 5,
    RoomControls    = 6,
    PC              = 7,
    Laptop          = 8,
    Wireless        = 9,
    Routing         = 10,
    Dialer          = 11,
    StreamMusic     = 12,
    RoomCombining   = 13
}

-------------------[ Controls ]-----------------------------
local controls = {
    btnNav = {
        Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04, Controls.btnNav05, Controls.btnNav06,
        Controls.btnNav07, Controls.btnNav08, Controls.btnNav09, Controls.btnNav10, Controls.btnNav11, Controls.btnNav12, Controls.btnNav13,
    },
    btnRouting = {
        Controls.btnRouting01, Controls.btnRouting02, Controls.btnRouting03, Controls.btnRouting04,
        Controls.btnRouting05, Controls.btnRouting06, Controls.btnRouting07, Controls.btnRouting08,
    },
    btnOpenHelp = {
        Laptop      = Controls.btnOpenHelpLaptop,
        PC          = Controls.btnOpenHelpPC,
        Wireless    = Controls.btnOpenHelpWireless,
        Routing     = Controls.btnOpenHelpRouting,
        StreamMusic = Controls.btnOpenHelpStreamMusic,
    },
    btnCloseHelp = {
        Laptop      = Controls.btnCloseHelpLaptop,
        PC          = Controls.btnCloseHelpPC,
        Wireless    = Controls.btnCloseHelpWireless,
        Routing     = Controls.btnCloseHelpRouting,
        StreamMusic = Controls.btnCloseHelpStreamMusic,
    },
    btnStartSystem     = Controls.btnStartSystem,
    btnNavShutdown     = Controls.btnNavShutdown,
    btnShutdownCancel  = Controls.btnShutdownCancel,
    btnShutdownConfirm = Controls.btnShutdownConfirm,
    txtRouting01 = Controls.txtRouting01, txtRouting02 = Controls.txtRouting02,
    txtRouting03 = Controls.txtRouting03, txtRouting04 = Controls.txtRouting04,
    txtRouting05 = Controls.txtRouting05, txtRouting06 = Controls.txtRouting06,
    txtRouting07 = Controls.txtRouting07, txtRouting08 = Controls.txtRouting08,
    knbProgressBar = Controls.knbProgressBar,
    txtProgressBar = Controls.txtProgressBar,
    pinCallActive          = Controls.pinCallActive,
    pinLEDUSBLaptop        = Controls.pinLEDUSBLaptop,
    pinLEDUSBPC            = Controls.pinLEDUSBPC,
    pinLEDOffHookLaptop    = Controls.pinLEDOffHookLaptop,
    pinLEDOffHookPC        = Controls.pinLEDOffHookPC,
    pinLEDHDMI01Active     = Controls.pinLEDHDMI01Active,
    pinLEDHDMI02Active     = Controls.pinLEDHDMI02Active,
    pinLEDPresetSaved      = Controls.pinLEDPresetSaved,
    pinLEDHDMI01Connect    = Controls.pinLEDHDMI01Connect,
    pinLEDHDMI02Connect    = Controls.pinLEDHDMI02Connect,
    pinLEDACPRBypassActive = Controls.pinLEDACPRBypassActive,
    pinLEDIsVisibleBtn01   = Controls.pinLEDIsVisibleBtn01, pinLEDIsVisibleBtn02 = Controls.pinLEDIsVisibleBtn02,
    pinLEDIsVisibleBtn03   = Controls.pinLEDIsVisibleBtn03, pinLEDIsVisibleBtn04 = Controls.pinLEDIsVisibleBtn04,
    pinLEDIsVisibleBtn05   = Controls.pinLEDIsVisibleBtn05, pinLEDIsVisibleBtn06 = Controls.pinLEDIsVisibleBtn06,
    pinLEDIsVisibleBtn07   = Controls.pinLEDIsVisibleBtn07, pinLEDIsVisibleBtn08 = Controls.pinLEDIsVisibleBtn08,
    pinLEDTouchActivity    = Controls.pinLEDTouchActivity,
}

-------------------[ Utilities ]----------------------------
local function isArr(t) return type(t) == "table" and t[1] ~= nil end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    local ok = pcall(function() ctrl.EventHandler = handler end)
    return ok
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
        end) then
            count = count + 1
        end
    end
    return count
end

local function stopTimer(timer)
    if timer then pcall(function() timer:Stop() end); return nil end
    return timer
end

-------------------[ Config ]-------------------------------
local config = {
    pageUCI         = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or "UCI",
    debug           = true,
    defaultRouting  = tonumber(Uci.Variables.numDefaultRoutingLayer and Uci.Variables.numDefaultRoutingLayer.Value) or 1,
    defaultLayer    = tonumber(Uci.Variables.numDefaultActiveLayer  and Uci.Variables.numDefaultActiveLayer.Value)  or kLayer.Routing,
    navHidden       = {},
}

-------------------[ State ]--------------------------------
-- Forward declaration: btnNavEventHandler is defined after its dependencies but referenced in
-- timer closures (startLoadingBar, resetTouchInactivityTimer) that execute later at runtime.
local btnNavEventHandler

local state = {
    activeLayer        = kLayer.Start,
    layerStates        = {},
    activeRoutingLayer = config.defaultRouting,
    isInitialized      = false,
}

local components = {
    roomControls      = nil,
    prevPowerState    = nil,
    videoSwitcher     = nil,
    videoSwitcherType = nil,
    videoMapping      = {},
    passcode          = nil,
    passcodeRoom      = nil,
    passcodeEnabled   = false,
}

local timers = {
    progress   = nil,
    timeout    = nil,
    inactivity = Timer.New(),
}

local navButtons     = {}
local routingButtons = {}
local arrLegends     = {}
local arrUserLabels  = {}
local layerConfigs

-------------------[ Debug ]--------------------------------
local function debugPrint(str)
    if config.debug then print("[" .. config.pageUCI .. "] " .. str) end
end

-------------------[ Functions ]----------------------------

-- Layer visibility
local function setLayerVisible(layer, visible, transition)
    if not layer or layer == "" then return end
    local currentState = state.layerStates[layer]
    if state.isInitialized and currentState == visible then return end
    local ok, err = pcall(Uci.SetLayerVisibility, config.pageUCI, layer, visible, transition or "none")
    if ok then
        state.layerStates[layer] = visible
    else
        debugPrint("Layer '" .. layer .. "' error: " .. tostring(err))
    end
end

local function updateLayerVisibility(layers, visible, transition)
    if not layers or visible == nil then return end
    for _, layer in ipairs(layers) do
        setLayerVisible(layer, visible, transition)
    end
end

local function showLayers(layers, visible, transition)
    updateLayerVisibility(layers, visible, transition)
end

local function hideBaseLayers()
    updateLayerVisibility(layersBase, false, "none")
end

-- Validation
local function validateControls()
    local missing, optional = {}, { pinLEDTouchActivity = true }
    for name, ctrl in pairs(controls) do
        if type(ctrl) == "table" then
            for key, sub in pairs(ctrl) do
                if not sub then table.insert(missing, name .. "[" .. tostring(key) .. "]") end
            end
        elseif not ctrl then
            if not optional[name] then table.insert(missing, name) end
        end
    end
    if #missing > 0 then
        print("ERROR: UCIController - Missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    print("UCIController: all required controls found")
    return true
end

local function normalizeControlArrays()
    for _, key in ipairs({ "btnNav", "btnRouting" }) do
        local c = controls[key]
        if c and not isArr(c) then controls[key] = { c } end
    end
    navButtons = controls.btnNav
    routingButtons = controls.btnRouting
    debugPrint("Normalized " .. #navButtons .. " nav buttons, " .. #routingButtons .. " routing buttons")
end

-- Legends
local function updateLegends()
    for i, ctrl in ipairs(arrLegends) do
        if ctrl and arrUserLabels[i] then
            setProp(ctrl, "Legend", arrUserLabels[i].String or "")
        end
    end
end

local function initLegendArrays()
    arrLegends, arrUserLabels = {}, {}
    local idx = 0
    for _, cfg in ipairs(legendConfig) do
        if cfg.suffix and cfg.count then
            for i = 1, cfg.count do
                idx = idx + 1
                local name = cfg.suffix .. string.format("%02d", i)
                arrLegends[idx] = Controls["txt" .. name]
                arrUserLabels[idx] = Uci.Variables["txtLabel" .. name]
                if not Controls["txt" .. name] then debugPrint("Warning: Legend control not found: txt" .. name) end
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do
                idx = idx + 1
                arrLegends[idx] = Controls["txt" .. name]
                arrUserLabels[idx] = Uci.Variables["txtLabel" .. name]
            end
        end
    end
    for i, label in ipairs(arrUserLabels) do
        if label then label.EventHandler = function() updateLegends() end end
    end
    debugPrint("Legends: " .. #arrLegends .. " controls, " .. #arrUserLabels .. " variables")
end

-- Routing control visibility
local function updateRoutingControlVisibility(buttonIndex, isVisible)
    local indexStr = string.format("%02d", buttonIndex)
    local btn = controls.btnRouting and controls.btnRouting[buttonIndex]
    local txt = controls["txtRouting" .. indexStr]
    if btn then setProp(btn, "IsInvisible", not isVisible) end
    if txt then setProp(txt, "IsInvisible", not isVisible) end
    debugPrint("Routing controls " .. indexStr .. ": " .. (isVisible and "shown" or "hidden"))
end

local function initRoutingVisibility()
    for i = 1, 8 do
        local pin = controls["pinLEDIsVisibleBtn" .. string.format("%02d", i)]
        if pin then updateRoutingControlVisibility(i, pin.Boolean or false) end
    end
    debugPrint("Routing visibility initialized")
end

-- Sublayer state updates (called from showLayer and pin event handlers)
local function updateCallActiveState()
    if not controls.pinCallActive then return end
    local isActive = controls.pinCallActive.Boolean or false
    setLayerVisible("I01-CallActive", isActive, isActive and "fade" or "none")
    debugPrint("Call Active → " .. (isActive and "ON" or "OFF"))
end

local function updatePresetSavedState()
    local isVisible = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
    setLayerVisible("J04-CamPresetSaved", isVisible, isVisible and "fade" or "none")
end

local function updateConferenceState()
    local usbConnected, disconnectedLayer
    if state.activeLayer == kLayer.Laptop then
        usbConnected     = controls.pinLEDUSBLaptop and controls.pinLEDUSBLaptop.Boolean or false
        disconnectedLayer = "J01-ConnectUSBLaptop"
    elseif state.activeLayer == kLayer.PC then
        usbConnected     = controls.pinLEDUSBPC and controls.pinLEDUSBPC.Boolean or false
        disconnectedLayer = "J02-ConnectUSBPC"
    else
        return
    end
    if usbConnected then
        setLayerVisible("J05-CameraControls", true, "fade")
        showLayers({"J01-ConnectUSBLaptop", "J02-ConnectUSBPC"}, false, "none")
    else
        setLayerVisible(disconnectedLayer, true, "fade")
        setLayerVisible("J05-CameraControls", false, "none")
    end
    debugPrint("Camera/USB: " .. (usbConnected and "Connected" or "Disconnected"))
end

local function updateHDMI01State()
    if state.activeLayer ~= kLayer.Laptop then return end
    if not controls.pinLEDHDMI01Connect then return end
    local isConnected = controls.pinLEDHDMI01Connect.Boolean or false
    if isConnected then
        setLayerVisible("L05-Laptop", true, "fade")
        setLayerVisible("L01-HDMI01Disconnected", false, "none")
    else
        setLayerVisible("L01-HDMI01Disconnected", true, "fade")
        showLayers({"L05-Laptop", "J05-CameraControls"}, false, "none")
    end
    debugPrint("HDMI01 → " .. (isConnected and "Connected" or "Disconnected"))
end

local function updateHDMI02State()
    if state.activeLayer ~= kLayer.PC then return end
    local isConnected = controls.pinLEDHDMI02Connect and controls.pinLEDHDMI02Connect.Boolean or false
    if isConnected then
        setLayerVisible("P05-PC", true, "fade")
        setLayerVisible("P01-HDMI02Disconnected", false, "none")
    else
        setLayerVisible("P01-HDMI02Disconnected", true, "fade")
        showLayers({"P05-PC", "J05-CameraControls"}, false, "none")
    end
    debugPrint("HDMI02 → " .. (isConnected and "Connected" or "Disconnected"))
end

local function updateACPRBypassState()
    if state.activeLayer ~= kLayer.Laptop and state.activeLayer ~= kLayer.PC then return end
    local isBypass = controls.pinLEDACPRBypassActive and controls.pinLEDACPRBypassActive.Boolean or false
    if not isBypass then
        setLayerVisible("J03-ACPRActive", true, "fade")
        setLayerVisible("J05-CameraControls", false, "none")
    else
        setLayerVisible("J05-CameraControls", true, "fade")
        setLayerVisible("J03-ACPRActive", false, "none")
    end
    debugPrint("ACPR Bypass → " .. (isBypass and "Active" or "Inactive"))
end

-- Routing
local function interlockRoutingButtons()
    for i, btn in ipairs(routingButtons) do
        if btn then setProp(btn, "Boolean", i == state.activeRoutingLayer) end
    end
end

local function resetRoutingButtons()
    for _, btn in ipairs(routingButtons) do
        if btn then setProp(btn, "Boolean", false) end
    end
end

local function showRoutingLayer()
    if state.activeRoutingLayer < 1 or state.activeRoutingLayer > #layersRouting then
        state.activeRoutingLayer = 1
    end
    for _, layer in ipairs(layersRouting) do
        setLayerVisible(layer, false, "none")
    end
    setLayerVisible(layersRouting[state.activeRoutingLayer], true, "fade")
    interlockRoutingButtons()
    debugPrint("Routing layer → " .. layersRouting[state.activeRoutingLayer])
end

local function routingButtonHandler(buttonIndex)
    if buttonIndex < 1 or buttonIndex > #layersRouting then return end
    if state.isInitialized and buttonIndex == state.activeRoutingLayer then return end
    state.activeRoutingLayer = buttonIndex
    showRoutingLayer()
end

-- Passcode
local function isPasscodeCorrect()
    if not components.passcodeEnabled or not components.passcode then return true end
    if components.passcode["PasscodeCorrect"] then
        return components.passcode["PasscodeCorrect"].Boolean
    end
    return true
end

local function initPasscode()
    local room = config.pageUCI:match("Salon%s*([A-H])")
    if not room then
        debugPrint("Passcode: could not extract room from '" .. config.pageUCI .. "' (feature disabled)")
        return false
    end
    components.passcodeRoom = "Salon" .. room
    local componentName = "passcode" .. components.passcodeRoom
    local ok, comp = pcall(function() return Component.New(componentName) end)
    if not ok or not comp then
        debugPrint("Passcode component not found: " .. componentName .. " (feature disabled)")
        return false
    end
    components.passcode        = comp
    components.passcodeEnabled = true
    if comp["PasscodeCorrect"] then
        comp["PasscodeCorrect"].EventHandler = function(ctl)
            if not ctl.Boolean then return end
            debugPrint("Passcode correct: " .. components.passcodeRoom .. " → H04-RoomCombining (Source: PasscodeCorrect)")
            setLayerVisible("H01-PasscodeEntry", false, "fade")
            setLayerVisible("H04-RoomCombining", true, "fade")
        end
        debugPrint("Passcode: handler registered for " .. components.passcodeRoom)
    end
    return true
end

-- Touch inactivity (H04-RoomCombining auto-return)
local function resetTouchInactivityTimer()
    timers.inactivity:Stop()
    -- Do not set EventHandler = nil; Q-SYS addEventHandler requires a function.
    if state.activeLayer ~= kLayer.RoomCombining then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity.EventHandler = function()
        if state.activeLayer ~= kLayer.RoomCombining then return end
        debugPrint("Touch inactivity timeout → C05-Start (Source: inactivity timer)")
        btnNavEventHandler(kLayer.Start)
    end
    timers.inactivity:Start(timeout)
    debugPrint("Touch inactivity timer reset (" .. timeout .. "s)")
end

-- Navigation interlock
local function interlock()
    local layerToBtn = {
        [kLayer.Alarm]           =1,        
        [kLayer.IncomingCall]    =2,  
        [kLayer.Start]           =3,
        [kLayer.Warming]         =4,      
        [kLayer.Cooling]         =5,        
        [kLayer.RoomControls]    =6,
        [kLayer.PC]              =7,           
        [kLayer.Laptop]          =8,         
        [kLayer.Wireless]        =9,
        [kLayer.Routing]         =10,     
        [kLayer.Dialer]          =11,        
        [kLayer.StreamMusic]     =12,
        [kLayer.RoomCombining]   =13
    }
    local activeBtn = layerToBtn[state.activeLayer]
    for i, btn in ipairs(navButtons) do
        if btn then setProp(btn, "Boolean", i == activeBtn) end
    end
    if state.activeLayer ~= kLayer.Routing then resetRoutingButtons() end
    -- Routing nav button (btnNav10) hidden when on Room Controls or Routing layer
    local hideRoutingBtn = (state.activeLayer == kLayer.RoomControls) or (state.activeLayer == kLayer.Routing)
    local btnNav10 = controls.btnNav and controls.btnNav[10]
    if btnNav10 then
        setProp(btnNav10, "IsDisabled",  hideRoutingBtn)
        setProp(btnNav10, "IsInvisible", hideRoutingBtn)
    end
end

local function buildLayerConfigs()
    layerConfigs = {
        [kLayer.Alarm] = {
            show = { "A01-Alarm" },
            hideBase = true,
            fn = function() updateCallActiveState() end,
        },
        [kLayer.IncomingCall] = {
            show = { "B01-IncomingCall" },
            fn = function() updateCallActiveState() end,
        },
        [kLayer.Start] = {
            show = { "C05-Start" },
            hideBase = true,
            fn = function() updateCallActiveState() end,
        },
        [kLayer.Warming] = {
            show = { "E05-SystemProgress", "E01-SystemProgressWarming" },
            hideBase = true,
            fn = function() updateCallActiveState() end,
        },
        [kLayer.Cooling] = {
            show = { "E05-SystemProgress", "E02-SystemProgressCooling" },
            hideBase = true,
            fn = function() updateCallActiveState() end,
        },
        [kLayer.RoomControls] = {
            show = { "H05-RoomControls" },
            hide = { "X01-ProgramVolume" },
            fn = function() updateCallActiveState() end,
        },
        [kLayer.Laptop] = {
            show = { "L05-Laptop" },
            fn = function()
                updateHDMI01State()
                updateConferenceState()
                updatePresetSavedState()
                updateACPRBypassState()
                updateCallActiveState()
            end,
        },
        [kLayer.PC] = {
            show = { "P05-PC" },
            fn = function()
                updateHDMI02State()
                updateConferenceState()
                updatePresetSavedState()
                updateACPRBypassState()
                updateCallActiveState()
            end,
        },
        [kLayer.Wireless] = {
            show = { "W05-Wireless" },
            fn = function() updateCallActiveState() end,
        },
        [kLayer.Routing] = {
            show = { "R10-Routing" },
            fn = function()
                showRoutingLayer()
                updateCallActiveState()
            end,
        },
        [kLayer.Dialer] = {
            show = { "V05-Dialer" },
            fn = function() updateCallActiveState() end,
        },
        [kLayer.StreamMusic] = {
            show = { "S10-StreamMusic" },
            fn = function() updateCallActiveState() end,
        },
        [kLayer.RoomCombining] = {
            show = {},
            hideBase = true,
            fn = function()
                resetTouchInactivityTimer()
                if isPasscodeCorrect() then
                    setLayerVisible("H04-RoomCombining", true, "fade")
                    debugPrint("Passcode pre-cleared → H04-RoomCombining shown directly")
                else
                    setLayerVisible("H01-PasscodeEntry", true, "fade")
                end
                updateCallActiveState()
            end,
        },
    }
end

-- Layer display: clear non-base layers, show base, then layer-specific content (§8.5 base-layer pattern)
local function showLayer()
    if not layerConfigs then buildLayerConfigs() end
    updateLayerVisibility(layersToHide, false, "none")
    updateLayerVisibility(layersBase, true, "none")
    local cfg = layerConfigs[state.activeLayer]
    if not cfg then return end
    if cfg.hideBase then hideBaseLayers() end
    for _, layer in ipairs(cfg.show or {}) do setLayerVisible(layer, true, "fade") end
    for _, layer in ipairs(cfg.hide or {}) do setLayerVisible(layer, false, "none") end
    if cfg.fn then cfg.fn() end
end

-- Video switcher
local function initVideoSwitcher()
    for switcherType, swCfg in pairs(configSwitcher) do
        for _, varName in ipairs(swCfg.switcherNames) do
            if Controls[varName] and Controls[varName].String ~= "" then
                local ok, comp = pcall(function() return Component.New(Controls[varName].String) end)
                if ok and comp then
                    components.videoSwitcher     = comp
                    components.videoSwitcherType = switcherType
                    components.videoMapping      = swCfg.defaultMapping
                    debugPrint("Video switcher: " .. switcherType .. " → " .. Controls[varName].String .. " (Source: UCI variable)")
                    return true
                end
            end
        end
    end
    for switcherType, swCfg in pairs(configSwitcher) do
        for _, comp in pairs(Component.GetComponents()) do
            if comp.Type == swCfg.componentType then
                local ok, compRef = pcall(function() return Component.New(comp.Name) end)
                if ok and compRef then
                    components.videoSwitcher     = compRef
                    components.videoSwitcherType = switcherType
                    components.videoMapping      = swCfg.defaultMapping
                    debugPrint("Video switcher: " .. switcherType .. " → " .. comp.Name .. " (Source: auto-detect)")
                    return true
                end
            end
        end
    end
    debugPrint("Video switcher: none detected")
    return false
end

local function switchToInput(inputNumber)
    if not components.videoSwitcher or not components.videoSwitcherType then return false end
    if not inputNumber then return false end
    local swCfg = configSwitcher[components.videoSwitcherType]
    if not swCfg then return false end
    local ok, err = pcall(function()
        if swCfg.setPropMode == "Value" then
            components.videoSwitcher[swCfg.routingControl].Value = inputNumber
        else
            components.videoSwitcher[swCfg.routingControl].String = tostring(inputNumber)
        end
    end)
    if ok then
        debugPrint("Video → input " .. inputNumber .. " (" .. tostring(components.videoSwitcherType) .. ")")
    else
        debugPrint("Video switch error: " .. tostring(err))
    end
    return ok
end

-- Progress bar
local function startLoadingBar(isPoweringOn)
    timers.progress = stopTimer(timers.progress)
    timers.timeout  = stopTimer(timers.timeout)

    local duration = 10
    if components.roomControls then
        local ok, result = pcall(function()
            return isPoweringOn
                and (components.roomControls["warmupTime"]   and components.roomControls["warmupTime"].Value   or 10)
                or  (components.roomControls["cooldownTime"] and components.roomControls["cooldownTime"].Value or 5)
        end)
        if ok and result then duration = result end
    else
        duration = isPoweringOn
            and (tonumber(Uci.Variables.timeProgressWarming) or 10)
            or  (tonumber(Uci.Variables.timeProgressCooling) or 5)
    end

    local steps       = 100
    local interval    = duration / steps
    local currentStep = 0

    if controls.knbProgressBar then controls.knbProgressBar.Value  = isPoweringOn and 0 or 100 end
    if controls.txtProgressBar  then controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%" end

    timers.progress = Timer.New()
    timers.timeout  = Timer.New()

    timers.timeout.EventHandler = function()
        timers.progress = stopTimer(timers.progress)
        btnNavEventHandler(isPoweringOn and config.defaultLayer or kLayer.Start)
        debugPrint("Loading bar: timeout (300s)")
    end
    timers.timeout:Start(300)

    timers.progress.EventHandler = function()
        currentStep = currentStep + 1
        local progress = isPoweringOn and currentStep or (100 - currentStep)
        if controls.knbProgressBar then controls.knbProgressBar.Value  = progress end
        if controls.txtProgressBar  then controls.txtProgressBar.String = progress .. "%" end
        if currentStep >= steps then
            timers.timeout = stopTimer(timers.timeout)
            btnNavEventHandler(isPoweringOn and config.defaultLayer or kLayer.Start)
        else
            timers.progress:Start(interval)
        end
    end
    timers.progress:Start(interval)
    debugPrint("Loading bar started (" .. duration .. "s, " .. (isPoweringOn and "warming" or "cooling") .. ")")
end

-- Room automation
local function initRoomAutomation()
    local componentName = nil
    if Uci.Variables.compRoomControls then
        componentName = Uci.Variables.compRoomControls.String
    end
    if not componentName then
        local pageName = config.pageUCI:match("uci%s+([^(]+)")
        if pageName then componentName = "compRoomControls" .. pageName:gsub("%s+", "") end
    end
    if not componentName then
        debugPrint("Room Controls: could not determine component name")
        return false
    end
    local ok, comp = pcall(function() return Component.New(componentName) end)
    if not ok or not comp then
        debugPrint("Room Controls: component not found: " .. componentName)
        return false
    end
    components.roomControls = comp
    if comp["ledSystemPower"] then
        components.prevPowerState = comp["ledSystemPower"].Boolean
    end
    debugPrint("Room Controls: connected → " .. componentName .. " (power=" .. tostring(components.prevPowerState) .. ")")
    return true
end

local function powerOn()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then
        debugPrint("Cannot power on: Room Controls not available")
        return false
    end
    components.roomControls["btnSystemOnOff"].Boolean = true
    debugPrint("Room → ON (Source: btnStartSystem)")
    return true
end

local function powerOff()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then
        debugPrint("Cannot power off: Room Controls not available")
        return false
    end
    components.roomControls["btnSystemOnOff"].Boolean = false
    debugPrint("Room → OFF (Source: btnShutdownConfirm)")
    return true
end

-- Navigation — assigned (not re-declared) so timer closures that captured the
-- forward-declared upvalue above resolve correctly at runtime.
btnNavEventHandler = function(layerIndex)
    if state.isInitialized and layerIndex == state.activeLayer then return end
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    -- Cancel any running progress animation when navigating away from progress layers.
    -- Without this, the cooling timer fires its final step and unconditionally navigates
    -- back to kLayerStart, overriding any manual navigation that happened in the interim.
    if layerIndex ~= kLayer.Warming and layerIndex ~= kLayer.Cooling then
        timers.progress = stopTimer(timers.progress)
        timers.timeout  = stopTimer(timers.timeout)
    end
    local inputNumber = components.videoMapping[layerIndex]
    if components.videoSwitcher and inputNumber then
        switchToInput(inputNumber)
    end
    showLayer()
    interlock()
    debugPrint("Layer: " .. prev .. " → " .. layerIndex)
end

local function startSystem()
    powerOn()
    startLoadingBar(true)
    btnNavEventHandler(kLayer.Warming)
end

local function shutdownSystem()
    setLayerVisible("D01-ShutdownConfirm", false, "fade")
    powerOff()
    startLoadingBar(false)
    state.activeLayer = kLayer.Cooling
    showLayer()
    interlock()
end

local function ensureSystemIsOn()
    if components.roomControls and components.roomControls["ledSystemPower"] then
        if not components.roomControls["ledSystemPower"].Boolean then
            startSystem()
        end
    end
end

-------------------[ Events ]-------------------------------
local function registerEvents()
    -- Navigation buttons
    local navCount = bindArray(navButtons, function(i) btnNavEventHandler(i) end)
    debugPrint("Registered " .. navCount .. " nav button handlers")

    -- Routing buttons
    local routingCount = bindArray(routingButtons, function(i) routingButtonHandler(i) end)
    debugPrint("Registered " .. routingCount .. " routing button handlers")

    -- System controls
    bind(controls.btnStartSystem,     function()    startSystem() end)
    bind(controls.btnNavShutdown,     function()    setLayerVisible("D01-ShutdownConfirm", true, "fade") end)
    bind(controls.btnShutdownCancel,  function()    setLayerVisible("D01-ShutdownConfirm", false, "fade") end)
    bind(controls.btnShutdownConfirm, function()    shutdownSystem() end)
    debugPrint("Registered 4 system control handlers")

    -- Help open/close pairs (Laptop and PC: also manage camera sublayers)
    bind(controls.btnOpenHelp.Laptop, function()
        setLayerVisible("I02-HelpLaptop", true, "fade")
        showLayers({ "J05-CameraControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC" }, false, "none")
        debugPrint("Laptop Help → open (Source: btnOpenHelpLaptop)")
    end)
    bind(controls.btnCloseHelp.Laptop, function()
        setLayerVisible("I02-HelpLaptop", false, "none")
        updateConferenceState()
        debugPrint("Laptop Help → closed (Source: btnCloseHelpLaptop)")
    end)
    bind(controls.btnOpenHelp.PC, function()
        setLayerVisible("I03-HelpPC", true, "fade")
        showLayers({ "J05-CameraControls", "J01-ConnectUSBLaptop", "J02-ConnectUSBPC" }, false, "none")
        debugPrint("PC Help → open (Source: btnOpenHelpPC)")
    end)
    bind(controls.btnCloseHelp.PC, function()
        setLayerVisible("I03-HelpPC", false, "none")
        updateConferenceState()
        debugPrint("PC Help → closed (Source: btnCloseHelpPC)")
    end)

    local simpleHelp = {
        { open = controls.btnOpenHelp.Wireless,    close = controls.btnCloseHelp.Wireless,    layer = "I04-HelpWireless",    label = "Wireless" },
        { open = controls.btnOpenHelp.Routing,     close = controls.btnCloseHelp.Routing,     layer = "I05-HelpRouting",     label = "Routing" },
        { open = controls.btnOpenHelp.StreamMusic, close = controls.btnCloseHelp.StreamMusic, layer = "I07-HelpStreamMusic", label = "StreamMusic" },
    }
    for _, pair in ipairs(simpleHelp) do
        local lyr, lbl = pair.layer, pair.label
        bind(pair.open,  function() setLayerVisible(lyr, true,  "fade"); debugPrint(lbl .. " Help → open (Source: open button)")  end)
        bind(pair.close, function() setLayerVisible(lyr, false, "none"); debugPrint(lbl .. " Help → closed (Source: close button)") end)
    end
    debugPrint("Registered " .. (4 + #simpleHelp * 2) .. " help button handlers")

    -- Pin inputs
    bind(controls.pinCallActive,          function()    updateCallActiveState() end)
    bind(controls.pinLEDPresetSaved,      function()    updatePresetSavedState() end)
    bind(controls.pinLEDHDMI01Connect,    function()    updateHDMI01State() end)
    bind(controls.pinLEDHDMI02Connect,    function()    updateHDMI02State() end)
    bind(controls.pinLEDACPRBypassActive, function()    updateACPRBypassState() end)
    bind(controls.pinLEDUSBLaptop,        function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.Laptop) else updateConferenceState() end end)
    bind(controls.pinLEDUSBPC,            function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.PC)     else updateConferenceState() end end)
    bind(controls.pinLEDOffHookLaptop,    function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.Laptop) end end)
    bind(controls.pinLEDOffHookPC,        function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.PC)     end end)
    bind(controls.pinLEDHDMI01Active,     function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.Laptop) end end)
    bind(controls.pinLEDHDMI02Active,     function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayer.PC)     end end)
    bind(controls.pinLEDTouchActivity,    function()    resetTouchInactivityTimer() end)
    debugPrint("Registered 12 pin input handlers")

    -- Routing visibility pins
    local visCount = 0
    for i = 1, 8 do
        local pin = controls["pinLEDIsVisibleBtn" .. string.format("%02d", i)]
        if pin then
            local idx = i
            bind(pin, function(ctl) updateRoutingControlVisibility(idx, ctl.Boolean) end)
            visCount = visCount + 1
        end
    end
    debugPrint("Registered " .. visCount .. " routing visibility handlers")

    -- Event-driven Room Controls power state (replaces 1s timer polling)
    if components.roomControls and components.roomControls["ledSystemPower"] then
        components.roomControls["ledSystemPower"].EventHandler = function(ctl)
            local currentState = ctl.Boolean
            if currentState == components.prevPowerState then return end
            debugPrint("Power state: " .. tostring(components.prevPowerState) .. " → " .. tostring(currentState) .. " (Source: ledSystemPower)")
            components.prevPowerState = currentState
            if currentState then
                startLoadingBar(true)
                btnNavEventHandler(kLayer.Warming)
            else
                startLoadingBar(false)
                btnNavEventHandler(kLayer.Cooling)
            end
        end
        debugPrint("Registered: event-driven power state handler (ledSystemPower)")
    end
end

-------------------[ Init ]---------------------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: configPageUCI=" .. config.pageUCI .. ", configDebug=" .. tostring(config.debug) ..
               ", configDefaultRouting=" .. config.defaultRouting .. ", configDefaultLayer=" .. config.defaultLayer)

    state.layerStates  = {}
    state.activeLayer  = kLayer.Start
    state.isInitialized = false

    normalizeControlArrays()
    buildLayerConfigs()
    initLegendArrays()
    initRoomAutomation()
    initVideoSwitcher()
    initPasscode()

    -- Hide specified navigation buttons
    for _, index in ipairs(config.navHidden) do
        local btn = controls.btnNav and controls.btnNav[index]
        if btn then
            btn.IsInvisible = true
            debugPrint("Hidden nav button: btnNav" .. string.format("%02d", index))
        end
    end

    registerEvents()

    showLayer()
    interlock()
    updateLegends()
    initRoutingVisibility()

    state.isInitialized = true
    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]---------------------------
myUCI = {
    btnNavEventHandler = btnNavEventHandler,
    startSystem        = startSystem,
    shutdownSystem     = shutdownSystem,
    powerOn            = powerOn,
    powerOff           = powerOff,
    startLoadingBar    = startLoadingBar,
    switchToInput      = switchToInput,
    isPasscodeCorrect  = isPasscodeCorrect,
    cleanup = function()
        timers.progress = stopTimer(timers.progress)
        timers.timeout  = stopTimer(timers.timeout)
        timers.inactivity:Stop()
        for _, label in ipairs(arrUserLabels) do
            if label then label.EventHandler = nil end
        end
        if components.roomControls and components.roomControls["ledSystemPower"] then
            components.roomControls["ledSystemPower"].EventHandler = nil
        end
        if components.passcode and components.passcode["PasscodeCorrect"] then
            components.passcode["PasscodeCorrect"].EventHandler = nil
        end
        debugPrint("Cleanup complete")
    end
}

-------------------[ Start ]--------------------------------
local ok, err = pcall(function()
    print("Initializing UCIController for " .. config.pageUCI .. "...")
    if not validateControls() then error("Control validation failed") end
    init()
end)

if ok then
    print("✓ UCIController initialized for " .. config.pageUCI)
else
    print("✗ ERROR: UCIController initialization failed: " .. tostring(err))
end
