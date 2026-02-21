--[[
    UCIController (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2026-02-21
    Firmware Req: 10.0.0
    Notes:
    - Flat module architecture per qsys-lua-architecture spec (no OOP).
    - Event-driven Room Controls synchronization via ledSystemPower.EventHandler (no timer polling).
    - Passcode protection for Room Combining layer with graceful degradation.
    - Touch inactivity timer for H04-RoomCombining layer.
    - Universal video switcher support: NV32, Extron DXP, auto-detected.
]]

-------------------[ Configuration ]------------------------
local layersAll = {
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
    "X01-ProgramVolume", "Y01-Navbar", "Z01-Base"
}

local layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}

local layersRouting = {
    "R01-Routing-SalonD", "R02-Routing-SalonE", "R03-Routing-SalonA",
    "R04-Routing-SalonB", "R05-Routing-SalonC", "R06-Routing-SalonF",
    "R07-Routing-SalonG", "R08-Routing-SalonH"
}

local legendControls = {
    "txtNav01","txtNav02","txtNav03","txtNav04","txtNav05","txtNav06","txtNav07","txtNav08",
    "txtNav09","txtNav10","txtNav11","txtNav12","txtNav13",
    "txtNavShutdown","txtRoomNameNav","txtRoomNameStart",
    "txtRoutingRooms","txtRouting01","txtRouting02","txtRouting03","txtRouting04",
    "txtRouting05","txtRouting06","txtRouting07","txtRouting08","txtRoutingSources",
    "txtAudSrc01","txtAudSrc02","txtAudSrc03","txtAudSrc04",
    "txtAudSrc05","txtAudSrc06","txtAudSrc07","txtAudSrc08","txtGainPGM",
    "txtGain01","txtGain02","txtGain03","txtGain04","txtGain05","txtGain06","txtGain07","txtGain08","txtGain09","txtGain10",
    "txtGain11","txtGain12","txtGain13","txtGain14","txtGain15","txtGain16","txtGain17","txtGain18","txtGain19","txtGain20",
    "txtGain21","txtGain22","txtGain23","txtGain24","txtGain25","txtGain26","txtGain27","txtGain28","txtGain29","txtGain30",
    "txtGain31","txtGain32","txtGain33","txtGain34","txtGain35","txtGain36","txtGain37","txtGain38","txtGain39","txtGain40",
    "txtDisplay01","txtDisplay02","txtDisplay03","txtDisplay04"
}

local legendVariables = {
    "txtLabelNav01","txtLabelNav02","txtLabelNav03","txtLabelNav04","txtLabelNav05","txtLabelNav06","txtLabelNav07","txtLabelNav08",
    "txtLabelNav09","txtLabelNav10","txtLabelNav11","txtLabelNav12","txtLabelNav13",
    "txtLabelNavShutdown","txtLabelRoomNameNav","txtLabelRoomNameStart",
    "txtLabelRoutingRooms","txtLabelRouting01","txtLabelRouting02","txtLabelRouting03","txtLabelRouting04",
    "txtLabelRouting05","txtLabelRouting06","txtLabelRouting07","txtLabelRouting08","txtLabelRoutingSources",
    "txtLabelAudSrc01","txtLabelAudSrc02","txtLabelAudSrc03","txtLabelAudSrc04",
    "txtLabelAudSrc05","txtLabelAudSrc06","txtLabelAudSrc07","txtLabelAudSrc08","txtLabelGainPGM",
    "txtLabelGain01","txtLabelGain02","txtLabelGain03","txtLabelGain04","txtLabelGain05","txtLabelGain06","txtLabelGain07","txtLabelGain08","txtLabelGain09","txtLabelGain10",
    "txtLabelGain11","txtLabelGain12","txtLabelGain13","txtLabelGain14","txtLabelGain15","txtLabelGain16","txtLabelGain17","txtLabelGain18","txtLabelGain19","txtLabelGain20",
    "txtLabelGain21","txtLabelGain22","txtLabelGain23","txtLabelGain24","txtLabelGain25","txtLabelGain26","txtLabelGain27","txtLabelGain28","txtLabelGain29","txtLabelGain30",
    "txtLabelGain31","txtLabelGain32","txtLabelGain33","txtLabelGain34","txtLabelGain35","txtLabelGain36","txtLabelGain37","txtLabelGain38","txtLabelGain39","txtLabelGain40",
    "txtLabelDisplay01","txtLabelDisplay02","txtLabelDisplay03","txtLabelDisplay04"
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
local kLayerAlarm        = 1;  local kLayerIncomingCall = 2;  local kLayerStart        = 3
local kLayerWarming      = 4;  local kLayerCooling      = 5;  local kLayerRoomControls = 6
local kLayerPC           = 7;  local kLayerLaptop       = 8;  local kLayerWireless     = 9
local kLayerRouting      = 10; local kLayerDialer       = 11; local kLayerStreamMusic  = 12
local kLayerRoomCombining = 13

-------------------[ Controls ]-----------------------------
local controls = {
    -- Navigation
    btnNav01 = Controls.btnNav01, btnNav02 = Controls.btnNav02, btnNav03 = Controls.btnNav03,
    btnNav04 = Controls.btnNav04, btnNav05 = Controls.btnNav05, btnNav06 = Controls.btnNav06,
    btnNav07 = Controls.btnNav07, btnNav08 = Controls.btnNav08, btnNav09 = Controls.btnNav09,
    btnNav10 = Controls.btnNav10, btnNav11 = Controls.btnNav11, btnNav12 = Controls.btnNav12,
    btnNav13 = Controls.btnNav13,
    -- System
    btnStartSystem     = Controls.btnStartSystem,
    btnNavShutdown     = Controls.btnNavShutdown,
    btnShutdownCancel  = Controls.btnShutdownCancel,
    btnShutdownConfirm = Controls.btnShutdownConfirm,
    -- Help open/close pairs
    btnOpenHelpLaptop       = Controls.btnOpenHelpLaptop,      btnCloseHelpLaptop      = Controls.btnCloseHelpLaptop,
    btnOpenHelpPC           = Controls.btnOpenHelpPC,          btnCloseHelpPC          = Controls.btnCloseHelpPC,
    btnOpenHelpWireless     = Controls.btnOpenHelpWireless,    btnCloseHelpWireless    = Controls.btnCloseHelpWireless,
    btnOpenHelpRouting      = Controls.btnOpenHelpRouting,     btnCloseHelpRouting     = Controls.btnCloseHelpRouting,
    btnOpenHelpStreamMusic  = Controls.btnOpenHelpStreamMusic, btnCloseHelpStreamMusic = Controls.btnCloseHelpStreamMusic,
    -- Routing buttons / labels
    btnRouting01 = Controls.btnRouting01, btnRouting02 = Controls.btnRouting02,
    btnRouting03 = Controls.btnRouting03, btnRouting04 = Controls.btnRouting04,
    btnRouting05 = Controls.btnRouting05, btnRouting06 = Controls.btnRouting06,
    btnRouting07 = Controls.btnRouting07, btnRouting08 = Controls.btnRouting08,
    txtRouting01 = Controls.txtRouting01, txtRouting02 = Controls.txtRouting02,
    txtRouting03 = Controls.txtRouting03, txtRouting04 = Controls.txtRouting04,
    txtRouting05 = Controls.txtRouting05, txtRouting06 = Controls.txtRouting06,
    txtRouting07 = Controls.txtRouting07, txtRouting08 = Controls.txtRouting08,
    -- Progress
    knbProgressBar = Controls.knbProgressBar,
    txtProgressBar = Controls.txtProgressBar,
    -- Pin inputs
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

-------------------[ Config ]-------------------------------
local config = {
    pageUCI         = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or "UCI",
    debug           = true,
    defaultRouting  = tonumber(Uci.Variables.numDefaultRoutingLayer and Uci.Variables.numDefaultRoutingLayer.Value) or 1,
    defaultLayer    = tonumber(Uci.Variables.numDefaultActiveLayer  and Uci.Variables.numDefaultActiveLayer.Value)  or kLayerRouting,
    navHidden       = {},
}

-------------------[ State ]--------------------------------
-- Forward declaration: btnNavEventHandler is defined after its dependencies but referenced in
-- timer closures (startLoadingBar, resetTouchInactivityTimer) that execute later at runtime.
local btnNavEventHandler

local state = {
    activeLayer        = kLayerStart,
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

-------------------[ Debug ]--------------------------------
local function debugPrint(str)
    if config.debug then print("[" .. config.pageUCI .. "] " .. str) end
end

-------------------[ Functions ]----------------------------

-- Layer visibility
local function setLayerVisible(layer, visible, transition)
    local currentState = state.layerStates[layer]
    if state.isInitialized and currentState == visible then return end
    local ok, err = pcall(Uci.SetLayerVisibility, config.pageUCI, layer, visible, transition or "none")
    if ok then
        state.layerStates[layer] = visible
    else
        debugPrint("Layer '" .. layer .. "' error: " .. tostring(err))
    end
end

local function showLayers(layers, visible, transition)
    for _, layer in ipairs(layers) do
        setLayerVisible(layer, visible, transition or "none")
    end
end

local function hideBaseLayers()
    showLayers({"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}, false, "none")
end

-- Validation
local function validateControls()
    local required = {
        "btnNav01","btnNav02","btnNav03","btnNav04","btnNav05","btnNav06",
        "btnNav07","btnNav08","btnNav09","btnNav10","btnNav11","btnNav12","btnNav13",
        "btnStartSystem","btnNavShutdown","btnShutdownCancel","btnShutdownConfirm"
    }
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
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
    for i = 1, 13 do navButtons[i]     = controls["btnNav"     .. string.format("%02d", i)] end
    for i = 1, 8  do routingButtons[i] = controls["btnRouting" .. string.format("%02d", i)] end
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
    for i, name in ipairs(legendControls) do
        arrLegends[i] = Controls[name]
        if not Controls[name] then debugPrint("Warning: Legend control not found: " .. name) end
    end
    for i, varName in ipairs(legendVariables) do
        arrUserLabels[i] = Uci.Variables[varName]
        if arrUserLabels[i] then
            arrUserLabels[i].EventHandler = function() updateLegends() end
        end
    end
    debugPrint("Legends: " .. #arrLegends .. " controls, " .. #arrUserLabels .. " variables")
end

-- Routing control visibility
local function updateRoutingControlVisibility(buttonIndex, isVisible)
    local indexStr = string.format("%02d", buttonIndex)
    for _, prefix in ipairs({"btnRouting", "txtRouting"}) do
        local ctrl = controls[prefix .. indexStr]
        if ctrl then setProp(ctrl, "IsInvisible", not isVisible) end
    end
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
    if state.activeLayer == kLayerLaptop then
        usbConnected     = controls.pinLEDUSBLaptop and controls.pinLEDUSBLaptop.Boolean or false
        disconnectedLayer = "J01-ConnectUSBLaptop"
    elseif state.activeLayer == kLayerPC then
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
    if state.activeLayer ~= kLayerLaptop then return end
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
    if state.activeLayer ~= kLayerPC then return end
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
    if state.activeLayer ~= kLayerLaptop and state.activeLayer ~= kLayerPC then return end
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
    if state.activeLayer ~= kLayerRoomCombining then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity.EventHandler = function()
        if state.activeLayer ~= kLayerRoomCombining then return end
        debugPrint("Touch inactivity timeout → C05-Start (Source: inactivity timer)")
        btnNavEventHandler(kLayerStart)
    end
    timers.inactivity:Start(timeout)
    debugPrint("Touch inactivity timer reset (" .. timeout .. "s)")
end

-- Navigation interlock
local function interlock()
    local layerToBtn = {
        [kLayerAlarm]           =1,        
        [kLayerIncomingCall]    =2,  
        [kLayerStart]           =3,
        [kLayerWarming]         =4,      
        [kLayerCooling]         =5,        
        [kLayerRoomControls]    =6,
        [kLayerPC]              =7,           
        [kLayerLaptop]          =8,         
        [kLayerWireless]        =9,
        [kLayerRouting]         =10,     
        [kLayerDialer]          =11,        
        [kLayerStreamMusic]     =12,
        [kLayerRoomCombining]   =13
    }
    local activeBtn = layerToBtn[state.activeLayer]
    for i, btn in ipairs(navButtons) do
        if btn then setProp(btn, "Boolean", i == activeBtn) end
    end
    if state.activeLayer ~= kLayerRouting then resetRoutingButtons() end
    -- Routing nav button (btnNav10) hidden when on Room Controls or Routing layer
    local hideRoutingBtn = (state.activeLayer == kLayerRoomControls) or (state.activeLayer == kLayerRouting)
    if controls.btnNav10 then
        setProp(controls.btnNav10, "IsDisabled",  hideRoutingBtn)
        setProp(controls.btnNav10, "IsInvisible", hideRoutingBtn)
    end
end

-- Layer display (hides all, shows base, then shows layer-specific content)
-- Skip hiding base layers to avoid hide-then-show toggle that can trigger control EventHandlers
local function showLayer()
    for _, layer in ipairs(layersAll) do
        if layer ~= "X01-ProgramVolume" and layer ~= "Y01-Navbar" and layer ~= "Z01-Base" then
            setLayerVisible(layer, false, "none")
        end
    end
    showLayers(layersBase, true, "none")

    local layerConfig = {
        [kLayerAlarm]         = { 
            show={"A01-Alarm"},
            hideBase=true,
            fn = function() updateCallActiveState() end
        },
        [kLayerIncomingCall]  = { 
            show={"B01-IncomingCall"},
            fn = function() updateCallActiveState() end
        },
        [kLayerStart]         = { 
            show={"C05-Start"},
            hideBase=true,
            fn = function() updateCallActiveState() end
        },
        [kLayerWarming]       = { 
            show={"E05-SystemProgress","E01-SystemProgressWarming"},
            hideBase=true,
            fn = function() updateCallActiveState() end
        },
        [kLayerCooling]       = { 
            show={"E05-SystemProgress","E02-SystemProgressCooling"},
            hideBase=true,
            fn = function() updateCallActiveState() end
        },
        [kLayerRoomControls]  = { 
            show={"H05-RoomControls"}, 
            hide={"X01-ProgramVolume"},
            fn = function() updateCallActiveState() end
        },
            fn = function() updateCallActiveState() end },
        [kLayerLaptop]        = { 
            show={"L05-Laptop"},
            fn = function() updateHDMI01State(); updateConferenceState(); updatePresetSavedState(); updateACPRBypassState(); updateCallActiveState() end
        },
        [kLayerPC]            = { 
            show={"P05-PC"},
            fn = function() updateHDMI02State(); updateConferenceState(); updatePresetSavedState(); updateACPRBypassState(); updateCallActiveState() end
        },
        [kLayerWireless]      = { 
            show={"W05-Wireless"},
            fn = function() updateCallActiveState() end
        },
        [kLayerRouting]       = { 
            show={"R10-Routing"},
            fn = function() showRoutingLayer(); updateCallActiveState() end
        },
        [kLayerDialer]        = { 
            show={"V05-Dialer"},
            fn = function() updateCallActiveState() end
        },
        [kLayerRoomCombining] = { 
            show={}, hideBase=true,
            fn = function()
                resetTouchInactivityTimer()
                if isPasscodeCorrect() then
                    setLayerVisible("H04-RoomCombining", true, "fade")
                    debugPrint("Passcode pre-cleared → H04-RoomCombining shown directly")
                else
                    setLayerVisible("H01-PasscodeEntry", true, "fade")
                end
                updateCallActiveState()
            end },
        [kLayerPasscode]      = { 
            show={"H01-PasscodeEntry"},
            hideBase=true,
            fn = function() resetTouchInactivityTimer(); updateCallActiveState() end
        }
    

    local config = layerConfig[state.activeLayer]
    if not config then return end
    if config.hideBase then hideBaseLayers() end
    for _, layer in ipairs(config.show or {}) do setLayerVisible(layer, true, "fade") end
    for _, layer in ipairs(config.hide or {}) do setLayerVisible(layer, false, "none") end
    if config.fn then config.fn() end
end

-- Video switcher
local function initVideoSwitcher()
    for switcherType, config in pairs(configSwitcher) do
        for _, varName in ipairs(config.switcherNames) do
            if Controls[varName] and Controls[varName].String ~= "" then
                local ok, comp = pcall(function() return Component.New(Controls[varName].String) end)
                if ok and comp then
                    components.videoSwitcher     = comp
                    components.videoSwitcherType = switcherType
                    components.videoMapping      = config.defaultMapping
                    debugPrint("Video switcher: " .. switcherType .. " → " .. Controls[varName].String .. " (Source: UCI variable)")
                    return true
                end
            end
        end
    end
    for switcherType, config in pairs(configSwitcher) do
        for _, comp in pairs(Component.GetComponents()) do
            if comp.Type == config.componentType then
                local ok, compRef = pcall(function() return Component.New(comp.Name) end)
                if ok and compRef then
                    components.videoSwitcher     = compRef
                    components.videoSwitcherType = switcherType
                    components.videoMapping      = config.defaultMapping
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
    local config = configSwitcher[components.videoSwitcherType]
    if not config then return false end
    local ok, err = pcall(function()
        if config.setPropMode == "Value" then
            components.videoSwitcher[config.routingControl].Value = inputNumber
        else
            components.videoSwitcher[config.routingControl].String = tostring(inputNumber)
        end
    end)
    if ok then
        debugPrint("Video → input " .. inputNumber .. " (" .. components.videoSwitcherType .. ")")
    else
        debugPrint("Video switch error: " .. tostring(err))
    end
    return ok
end

-- Progress bar
local function startLoadingBar(isPoweringOn)
    if timers.progress then timers.progress:Stop(); timers.progress = nil end
    if timers.timeout  then timers.timeout:Stop();  timers.timeout  = nil end

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
        if timers.progress then timers.progress:Stop(); timers.progress = nil end
        btnNavEventHandler(isPoweringOn and configDefaultLayer or kLayerStart)
        debugPrint("Loading bar: timeout (300s)")
    end
    timers.timeout:Start(300)

    timers.progress.EventHandler = function()
        currentStep = currentStep + 1
        local progress = isPoweringOn and currentStep or (100 - currentStep)
        if controls.knbProgressBar then controls.knbProgressBar.Value  = progress end
        if controls.txtProgressBar  then controls.txtProgressBar.String = progress .. "%" end
        if currentStep >= steps then
            if timers.timeout then timers.timeout:Stop(); timers.timeout = nil end
            btnNavEventHandler(isPoweringOn and configDefaultLayer or kLayerStart)
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
    if layerIndex ~= kLayerWarming and layerIndex ~= kLayerCooling then
        if timers.progress then timers.progress:Stop(); timers.progress = nil end
        if timers.timeout  then timers.timeout:Stop();  timers.timeout  = nil end
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
    btnNavEventHandler(kLayerWarming)
end

local function shutdownSystem()
    setLayerVisible("D01-ShutdownConfirm", false, "fade")
    powerOff()
    startLoadingBar(false)
    state.activeLayer = kLayerCooling
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
    bind(controls.btnOpenHelpLaptop,  function()
        setLayerVisible("I02-HelpLaptop", true, "fade")
        showLayers({"J05-CameraControls","J01-ConnectUSBLaptop","J02-ConnectUSBPC"}, false, "none")
        debugPrint("Laptop Help → open (Source: btnOpenHelpLaptop)")
    end)
    bind(controls.btnCloseHelpLaptop, function()
        setLayerVisible("I02-HelpLaptop", false, "none")
        updateConferenceState()
        debugPrint("Laptop Help → closed (Source: btnCloseHelpLaptop)")
    end)
    bind(controls.btnOpenHelpPC,      function()
        setLayerVisible("I03-HelpPC", true, "fade")
        showLayers({"J05-CameraControls","J01-ConnectUSBLaptop","J02-ConnectUSBPC"}, false, "none")
        debugPrint("PC Help → open (Source: btnOpenHelpPC)")
    end)
    bind(controls.btnCloseHelpPC,     function()
        setLayerVisible("I03-HelpPC", false, "none")
        updateConferenceState()
        debugPrint("PC Help → closed (Source: btnCloseHelpPC)")
    end)

    local simpleHelp = {
        { open=controls.btnOpenHelpWireless,    close=controls.btnCloseHelpWireless,    layer="I04-HelpWireless",    label="Wireless" },
        { open=controls.btnOpenHelpRouting,     close=controls.btnCloseHelpRouting,     layer="I05-HelpRouting",     label="Routing"  },
        { open=controls.btnOpenHelpStreamMusic, close=controls.btnCloseHelpStreamMusic, layer="I07-HelpStreamMusic", label="StreamMusic" },
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
    bind(controls.pinLEDUSBLaptop,        function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerLaptop) else updateConferenceState() end end)
    bind(controls.pinLEDUSBPC,            function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerPC)     else updateConferenceState() end end)
    bind(controls.pinLEDOffHookLaptop,    function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerLaptop) end end)
    bind(controls.pinLEDOffHookPC,        function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerPC)     end end)
    bind(controls.pinLEDHDMI01Active,     function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerLaptop) end end)
    bind(controls.pinLEDHDMI02Active,     function(ctl) if ctl.Boolean then ensureSystemIsOn(); btnNavEventHandler(kLayerPC)     end end)
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
                btnNavEventHandler(kLayerWarming)
            else
                startLoadingBar(false)
                btnNavEventHandler(kLayerCooling)
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
    state.activeLayer  = kLayerStart
    state.isInitialized = false

    normalizeControlArrays()
    initLegendArrays()
    initRoomAutomation()
    initVideoSwitcher()
    initPasscode()

    -- Hide specified navigation buttons
    for _, index in ipairs(config.navHidden) do
        local btn = controls["btnNav" .. string.format("%02d", index)]
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
        if timers.progress then timers.progress:Stop() end
        if timers.timeout  then timers.timeout:Stop()  end
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
