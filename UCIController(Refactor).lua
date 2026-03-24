--[[
  UCI Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 3.1 | Date: 2026-02-24
  Firmware Req: 10.1.1

  Flat module per qsys-lua-architecture. Event-driven power sync via ledSystemPower.
  Video switcher auto-detect (NV32, Extron DXP, AVProEdge). Passcode + inactivity timeout.
]]

-------------------[ Configuration ]-------------------
local conferenceStateConfig = { skip = { [7]=true, [8]=true, [9]=true } }
local acprConfig = { disableACPRShow = true }

local layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
local layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
    "H01-PasscodeEntry","H05-RoomControls",
    "I01-CallActive","I02-HelpLaptop","I03-HelpPC","I04-HelpWireless","I05-HelpRouting","I07-HelpStreamMusic",
    "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J05-ConferenceControls",
    "L01-HDMIDisconnected","L05-Laptop","P01-HDMIDisconnected","P05-PC","W01-HDMIDisconnected","W05-Wireless",
    "R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05","R10-Routing",
    "S05-StreamMusic","V05-Dialer"
}

local SwitcherTypes = {
    NV32 = { 
        componentType   = "streamer_hdmi_switcher", 
        switcherNames   = {"devNV32","compNV32"},
        routingMethod   = "hdmi.out.1.select.index", 
        defaultMapping  = {[7] = 7,[8] = 8,[9] = 9} 
    },
    ExtronDXP = { 
        componentType   = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames   = {"devExtronDXP","compExtronDXP"}, 
        routingMethod   = "output.1",
        defaultMapping  = {[7] = 2,[8] = 4,[9] = 1} 
    },
    AVProEdge = { 
        componentType   = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
        switcherNames   = {"devAVProEdge","compAVProEdge"}, 
        routingMethod   = "trigger",
        defaultMapping  = {[7] = "Input 3",[8] = "Input 4",[9] = "Input 1",[10] = "Input 2"} 
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
    Passcode        = 13
}

local configSource = {
    PC = { 
        layer=kLayer.PC, 
        hdmiKey="pinLEDHDMI01Connect", 
        usbKey="pinLEDUSBPC",
        base="P05-PC", 
        disc="P01-HDMIDisconnected", 
        usb="J02-ConnectUSBPC", 
        conf="J05-ConferenceControls", 
        help="I03-HelpPC" 
    },
    Laptop = { 
        layer=kLayer.Laptop, 
        hdmiKey="pinLEDHDMI02Connect", 
        usbKey="pinLEDUSBLaptop",
        base="L05-Laptop", 
        disc="L01-HDMIDisconnected", 
        usb="J01-ConnectUSBLaptop", 
        conf="J05-ConferenceControls", 
        help="I02-HelpLaptop" 
    },
    Wireless = { 
        layer=kLayer.Wireless, 
        hdmiKey="pinLEDHDMI03Connect", 
        usbKey=nil,
        base="W05-Wireless", 
        disc="W01-HDMIDisconnected", 
        usb=nil, conf=nil, 
        help="I04-HelpWireless" 
    },
}

local configHelpPairKeys = {"Laptop","PC","Wireless","Routing","StreamMusic"}
local layerHelpToKey = {
    ["I02-HelpLaptop"]="Laptop", ["I03-HelpPC"]="PC", ["I04-HelpWireless"]="Wireless",
    ["I05-HelpRouting"]="Routing", ["I07-HelpStreamMusic"]="StreamMusic",
}
-------------------[ Controls ]-------------------
local controls = {
    btnNav = { 
        Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04, Controls.btnNav05, Controls.btnNav06,
        Controls.btnNav07, Controls.btnNav08, Controls.btnNav09  ,Controls.btnNav10, Controls.btnNav11, Controls.btnNav12, Controls.btnNav13 
    },
    btnStartSystem      = Controls.btnStartSystem, 
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel, 
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
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
    btnRouting = {
        Controls.btnRouting01, Controls.btnRouting02, Controls.btnRouting03, Controls.btnRouting04, Controls.btnRouting05
    },
    knbProgressBar          = Controls.knbProgressBar, 
    txtProgressBar          = Controls.txtProgressBar,
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

-------------------[ Utilities ]-------------------
local function isArr(t) return type(t)=="table" and t[1]~=nil end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop]==val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    return pcall(function() ctrl.EventHandler = handler end)
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index "..i.."]: "..tostring(err)) end
        end) then count = count + 1 end
    end
    return count
end

local function stopTimer(timer)
    if timer then pcall(function() timer:Stop() end); return nil end
    return timer
end

local function bindPairedControls(openCtrl, closeCtrl, updateHandler)
    if openCtrl and updateHandler then
        bind(openCtrl, function() if closeCtrl then setProp(closeCtrl,"Boolean",false) end updateHandler() end)
    end
    if closeCtrl and updateHandler then
        bind(closeCtrl, function() if openCtrl then setProp(openCtrl,"Boolean",false) end updateHandler() end)
    end
end

local function collectLayers(...)
    local out = {}
    for _, arr in ipairs({...}) do
        for _, layer in ipairs(arr or {}) do table.insert(out, layer) end
    end
    return out
end

-------------------[ Config ]-------------------
local config = {
    pageUCI = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or "UCI",
    debug = true,
    defaultRouting = tonumber(Uci.Variables.numDefaultRoutingLayer and Uci.Variables.numDefaultRoutingLayer.Value) or 4,
    defaultLayer  = tonumber(Uci.Variables.numDefaultActiveLayer  and Uci.Variables.numDefaultActiveLayer.Value)  or 8,
    navHidden = {},
}

-------------------[ State ]-------------------
local btnNavEventHandler
local state = {
    activeLayer = kLayer.Start, 
    layerStates = {}, 
    activeRoutingLayer = config.defaultRouting,
    callActive = false, 
    isAnimating = false, 
    isInitialized = false,
}
local components = {
    roomControls = nil, prevPowerState = nil, videoSwitcher = nil, switcherType = nil, uciToInputMapping={},
    passcode = nil, passcodeRoom = nil, passcodeEnabled = false,
}
local timers = { loading = nil, timeout = nil, inactivity=Timer.New() }
local routingLayers = {"R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05"}
local arrUCILegends, arrUCIUserLabels = {}, {}
local sources, helpLayerButtonMap

local function buildSources()
    sources = {}
    for name, def in pairs(configSource) do
        sources[name] = {
            layerConst=def.layer, hdmiPin=controls[def.hdmiKey],
            baseLayer=def.base, discLayer=def.disc, usbPin=def.usbKey and controls[def.usbKey],
            usbConnect=def.usb, confLayer=def.conf, helpLayer=def.help,
            btnOpen=controls.btnOpenHelp[name], btnClose=controls.btnCloseHelp[name]
        }
    end
    local layerToSource = {}
    for name, src in pairs(sources) do layerToSource[src.layerConst] = name end
    sources._layerToSource = layerToSource
    helpLayerButtonMap = {}
    for helpLayer, key in pairs(layerHelpToKey) do
        if controls.btnOpenHelp[key] then
            helpLayerButtonMap[helpLayer] = {open=controls.btnOpenHelp[key], close=controls.btnCloseHelp[key]}
        end
    end
end

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if config.debug then print("["..config.pageUCI.."] "..str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local missing, optional = {}, { pinLEDTouchActivity=true }
    for name, ctrl in pairs(controls) do
        if type(ctrl)=="table" then
            for key, sub in pairs(ctrl) do
                if not sub then table.insert(missing, name.."["..tostring(key).."]") end
            end
        elseif not ctrl then
            if not optional[name] then table.insert(missing, name) end
        end
    end
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, n in ipairs(missing) do print("  - "..n) end
        return false
    end
    return true
end

local function normalizeControlArrays()
    for _, key in ipairs({"btnNav","btnRouting"}) do
        local c = controls[key]
        if c and not isArr(c) then controls[key] = { c } end
    end
end

local function updateLayerVisibility(layers, visible, transition)
    if not layers or visible == nil then return end
    for _, layer in ipairs(layers) do
        if layer and state.layerStates[layer] ~= visible then
            local ok, err = pcall(Uci.SetLayerVisibility, config.pageUCI, layer, visible, transition or "none")
            if ok then state.layerStates[layer] = visible
            else debugPrint("Layer '"..layer.."' error: "..tostring(err)) end
        end
    end
end

local function showLayerHideOthers(showLayers, hideLayers)
    if showLayers then updateLayerVisibility(showLayers, true, "fade") end
    if hideLayers then updateLayerVisibility(hideLayers, false, "none") end
end

local function getActiveSource()
    local key = sources and sources._layerToSource and sources._layerToSource[state.activeLayer]
    return key and sources[key] or nil
end

local function checkHDMIConnection()
    local src = getActiveSource()
    if not src then return true end
    return not src.hdmiPin or src.hdmiPin.Boolean
end

local function syncHelpButtonStates(helpLayer)
    local map = helpLayerButtonMap[helpLayer]
    if not map or state.layerStates[helpLayer] == nil then return end
    setProp(map.open, "Boolean", state.layerStates[helpLayer])
    setProp(map.close, "Boolean", false)
end

local function updateCallActiveState()
    state.callActive = controls.pinCallActive and controls.pinCallActive.Boolean or false
    updateLayerVisibility({"I01-CallActive"}, state.callActive, state.callActive and "fade" or "none")
    updateACPRBypassState()
    debugPrint("Call Active → "..(state.callActive and "ON" or "OFF"))
end

local function updatePresetSavedState()
    local v = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
    updateLayerVisibility({"J04-CamPresetSaved"}, v, v and "fade" or "none")
end

local function updateHDMIForActiveSource()
    local src = getActiveSource()
    if not src then return end
    if checkHDMIConnection() then
        showLayerHideOthers({src.baseLayer}, {src.discLayer})
        updateACPRBypassState()
        updateConferenceState()
        debugPrint("HDMI "..src.baseLayer.." → Connected")
        return
    end
    showLayerHideOthers({src.discLayer}, {src.baseLayer, "J03-ACPRActive", src.confLayer or ""})
    debugPrint("HDMI "..src.baseLayer.." → Disconnected")
end

local function updateSourceHelpState(srcKey)
    local src = sources[srcKey]
    if not src then return end
    if src.hdmiPin and not checkHDMIConnection() then
        updateLayerVisibility({src.helpLayer}, false, "none")
        syncHelpButtonStates(src.helpLayer)
        return
    end
    local isVisible = src.btnOpen and src.btnOpen.Boolean or false
    updateLayerVisibility({src.helpLayer}, isVisible, isVisible and "fade" or "none")
    if isVisible then
        local hide = collectLayers({"J01-ConnectUSBLaptop","J02-ConnectUSBPC"})
        if src.confLayer then table.insert(hide, "J05-ConferenceControls") end
        updateLayerVisibility(hide, false, "none")
    elseif src.confLayer then
        updateConferenceState()
    end
    syncHelpButtonStates(src.helpLayer)
    debugPrint(srcKey.." Help → "..(isVisible and "Showing" or "Hiding"))
end

local function updateConferenceState()
    local src = getActiveSource()
    if not src then return end
    if not checkHDMIConnection() then
        local hide = collectLayers({"J01-ConnectUSBLaptop","J02-ConnectUSBPC"}, {"J05-ConferenceControls"})
        if src.helpLayer then table.insert(hide, src.helpLayer) end
        updateLayerVisibility(hide, false, "none")
        if src.helpLayer then syncHelpButtonStates(src.helpLayer) end
        return
    end
    if conferenceStateConfig.skip[src.layerConst] then return end
    local usb = src.usbPin and src.usbPin.Boolean or false
    if usb then
        updateLayerVisibility({src.confLayer}, true, "fade")
        updateLayerVisibility({"J01-ConnectUSBLaptop","J02-ConnectUSBPC"}, false, "none")
    else
        updateLayerVisibility({src.usbConnect}, true, "fade")
        updateLayerVisibility({src.confLayer, src.helpLayer}, false, "none")
        if src.helpLayer then syncHelpButtonStates(src.helpLayer) end
    end
    debugPrint("Conference: "..(usb and "Connected" or "Disconnected"))
end

local function updateACPRBypassState()
    if acprConfig.disableACPRShow then
        updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        return
    end
    local src = getActiveSource()
    if not src or not checkHDMIConnection() then
        updateLayerVisibility({"J03-ACPRActive"}, false, "none")
        return
    end
    local bypass = controls.pinLEDACPRBypassActive and controls.pinLEDACPRBypassActive.Boolean or false
    local call = controls.pinCallActive and controls.pinCallActive.Boolean or false
    if not bypass and call then
        updateLayerVisibility({"J03-ACPRActive"}, true, "fade")
        if src.confLayer then updateLayerVisibility({src.confLayer}, false, "none") end
    else
        if src.confLayer then updateLayerVisibility({src.confLayer}, bypass, bypass and "fade" or "none") end
        updateLayerVisibility({"J03-ACPRActive"}, false, "none")
    end
end

local function updateRoutingHelpState()
    local v = controls.btnOpenHelp.Routing and controls.btnOpenHelp.Routing.Boolean or false
    updateLayerVisibility({"I05-HelpRouting"}, v, "none")
    syncHelpButtonStates("I05-HelpRouting")
end

local function updateStreamMusicHelpState()
    local v = controls.btnOpenHelp.StreamMusic and controls.btnOpenHelp.StreamMusic.Boolean or false
    updateLayerVisibility({"I07-HelpStreamMusic"}, v, "none")
    syncHelpButtonStates("I07-HelpStreamMusic")
end

local layerConfigs
local function makeSourceLayerFn(srcKey)
    return function()
        updateHDMIForActiveSource(); updateConferenceState(); updatePresetSavedState()
        updateACPRBypassState(); updateSourceHelpState(srcKey); updateCallActiveState()
    end
end

local function buildLayerConfigs()
    layerConfigs = {
        [kLayer.Alarm] = { show = {"A01-Alarm"}, hideBase=true },
        [kLayer.IncomingCall] = { show = {"B01-IncomingCall"} },
        [kLayer.Start] = { show = {"C05-Start"}, hideBase=true },
        [kLayer.Warming] = { show = {"E05-SystemProgress","E01-SystemProgressWarming"}, hideBase=true },
        [kLayer.Cooling] = { show = {"E05-SystemProgress","E02-SystemProgressCooling"}, hideBase=true },
        [kLayer.RoomControls] = { show = {"H05-RoomControls"}, hide={"X01-ProgramVolume"}, fn=function() updateCallActiveState() end },
        [kLayer.Laptop] = { show = {"L05-Laptop"}, fn=makeSourceLayerFn("Laptop") },
        [kLayer.PC] = { show = {"P05-PC"}, fn=makeSourceLayerFn("PC") },
        [kLayer.Wireless] = { 
            show = {"W05-Wireless"}, 
            fn=function() updateSourceHelpState("Wireless"); updateCallActiveState() end 
        },
        [kLayer.Routing] = { show = {"R10-Routing"}, fn=function() updateRoutingHelpState(); showRoutingLayer(); updateCallActiveState() end },
        [kLayer.Dialer] = { show = {"V05-Dialer"}, fn=function() updateCallActiveState() end },
        [kLayer.StreamMusic] = { show = {"S05-StreamMusic"}, fn=function() updateStreamMusicHelpState(); updateCallActiveState() end },
        [kLayer.Passcode] = { show = {"H01-PasscodeEntry"}, hideBase=true, fn=function() resetTouchInactivityTimer(); updateCallActiveState() end },
    }
end

local function showRoutingLayer()
    if state.activeRoutingLayer < 1 or state.activeRoutingLayer > #routingLayers then state.activeRoutingLayer = 1 end
    local hide = {"X01-ProgramVolume"}
    for i = 1, #routingLayers do table.insert(hide, routingLayers[i]) end
    updateLayerVisibility(hide, false, "none")
    updateLayerVisibility({routingLayers[state.activeRoutingLayer]}, true, "fade")
    for i, btn in ipairs(controls.btnRouting) do
        if btn then setProp(btn, "Boolean", i == state.activeRoutingLayer) end
    end
end

local function showLayer()
    if not layerConfigs then buildLayerConfigs() end
    updateLayerVisibility(layersToHide, false, "none")
    local cfg = layerConfigs[state.activeLayer]
    if not cfg then return end
    if cfg.hideBase then updateLayerVisibility(layersBase, false, "none")
    else updateLayerVisibility(layersBase, true, "none") end
    if cfg.show then updateLayerVisibility(cfg.show, true, "fade") end
    if cfg.hide then updateLayerVisibility(cfg.hide, false, "none") end
    if cfg.fn then cfg.fn() end
end

local function interlock()
    for i, btn in ipairs(controls.btnNav) do
        if btn then setProp(btn, "Boolean", i == state.activeLayer) end
    end
end

local function extractRoomFromPageName()
    local room = config.pageUCI:match("^uci%s*(.+)$")
    if room then
        room = room:match("^%s*(.-)%s*$")
        components.passcodeRoom = room
        return room
    end
    return nil
end

local function isPasscodeCorrect()
    if not components.passcodeEnabled or not components.passcode then return true end
    if components.passcode["PasscodeCorrect"] then return components.passcode["PasscodeCorrect"].Boolean end
    return true
end

local function initPasscode()
    if not extractRoomFromPageName() then return false end
    local compName = "passcode"..components.passcodeRoom
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then
        debugPrint("Passcode not found: "..compName.." (disabled)")
        return false
    end
    components.passcode = comp
    components.passcodeEnabled = true
    if comp["PasscodeCorrect"] then
        comp["PasscodeCorrect"].EventHandler = function(ctl)
            if not ctl.Boolean then return end
            debugPrint("Passcode correct → "..components.passcodeRoom.." (Source: PasscodeCorrect)")
            updateLayerVisibility({"H01-PasscodeEntry"}, false, "fade")
            startSystem("Passcode Correct")
        end
        debugPrint("Passcode handler registered")
    end
    return true
end

local function initVideoSwitcher()
    for swType, cfg in pairs(SwitcherTypes) do
        for _, name in ipairs(cfg.switcherNames) do
            local ctrl = Controls[name]
            if ctrl and ctrl.String and ctrl.String ~= "" then
                local ok, comp = pcall(function() return Component.New(ctrl.String) end)
                if ok and comp then
                    components.videoSwitcher = comp
                    components.switcherType = swType
                    components.uciToInputMapping = cfg.defaultMapping
                    debugPrint("Video switcher: "..swType)
                    return true
                end
            end
        end
    end
    for _, comp in pairs(Component.GetComponents()) do
        for swType, cfg in pairs(SwitcherTypes) do
            if comp.Type == cfg.componentType then
                local ok, c = pcall(function() return Component.New(comp.Name) end)
                if ok and c then
                    components.videoSwitcher = c
                    components.switcherType = swType
                    components.uciToInputMapping = cfg.defaultMapping
                    debugPrint("Video switcher: "..swType.." (auto-detect)")
                    return true
                end
            end
        end
    end
    return false
end

local function switchToInput(inputNumber, _uciButton)
    if not components.videoSwitcher or not components.switcherType then return false end
    local cfg = SwitcherTypes[components.switcherType]
    if not cfg then return false end
    local ok, err = pcall(function()
        if components.switcherType == "NV32" then
            setProp(components.videoSwitcher[cfg.routingMethod], "Value", inputNumber)
        else
            setProp(components.videoSwitcher[cfg.routingMethod], "String", tostring(inputNumber))
        end
    end)
    if ok then debugPrint("Video → input "..inputNumber) else debugPrint("Video switch error: "..tostring(err)) end
    return ok
end

local function initRoomControls()
    local compName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String
    if not compName then
        local page = config.pageUCI:match("uci%s+([^(]+)")
        if page then compName = "compRoomControls"..page:gsub("%s+", "") end
    end
    if not compName then
        debugPrint("Room Controls: could not determine component")
        return false
    end
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then
        debugPrint("Room Controls not found: "..compName)
        return false
    end
    components.roomControls = comp
    components.prevPowerState = comp["ledSystemPower"] and comp["ledSystemPower"].Boolean
    if comp["ledSystemPower"] then
        comp["ledSystemPower"].EventHandler = function(ctl)
            local cur = ctl.Boolean
            if cur == components.prevPowerState then return end
            debugPrint("Power → "..(cur and "ON" or "OFF").." (Source: Room Controls)")
            components.prevPowerState = cur
            reflectPowerState(cur, cur and "Room Automation Power On" or "Room Automation Power Off")
        end
        debugPrint("Registered: ledSystemPower (event-driven)")
    end
    return true
end

local function powerOn()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
    components.roomControls["btnSystemOnOff"].Boolean = true
    debugPrint("Room → ON")
    return true
end

local function powerOff()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
    components.roomControls["btnSystemOnOff"].Boolean = false
    debugPrint("Room → OFF")
    return true
end

local function startLoadingBar(isPoweringOn)
    if state.isAnimating then return end
    state.isAnimating = true
    timers.loading = stopTimer(timers.loading)
    timers.timeout = stopTimer(timers.timeout)
    local duration = 10
    if components.roomControls then
        if isPoweringOn and components.roomControls["warmupTime"] then
            duration = components.roomControls["warmupTime"].Value
        elseif not isPoweringOn and components.roomControls["cooldownTime"] then
            duration = components.roomControls["cooldownTime"].Value
        end
    else
        duration = isPoweringOn and (tonumber(Uci.Variables.timeProgressWarming) or 10) or (tonumber(Uci.Variables.timeProgressCooling) or 5)
    end
    local steps, interval, currentStep = 100, duration/100, 0
    setProp(controls.knbProgressBar, "Value", isPoweringOn and 0 or 100)
    setProp(controls.txtProgressBar, "String", (isPoweringOn and 0 or 100).."%")
    timers.loading = Timer.New()
    timers.timeout = Timer.New()
    timers.timeout.EventHandler = function()
        state.isAnimating = false
        timers.loading = stopTimer(timers.loading)
        btnNavEventHandler(isPoweringOn and config.defaultLayer or kLayer.Start, "Loading Timeout")
    end
    timers.timeout:Start(300)
    timers.loading.EventHandler = function()
        currentStep = currentStep + 1
        local prog = isPoweringOn and currentStep or (100 - currentStep)
        setProp(controls.knbProgressBar, "Value", prog)
        setProp(controls.txtProgressBar, "String", prog.."%")
        if currentStep >= steps then
            timers.loading = stopTimer(timers.loading)
            timers.timeout = stopTimer(timers.timeout)
            state.isAnimating = false
            btnNavEventHandler(isPoweringOn and config.defaultLayer or kLayer.Start, isPoweringOn and "Warmup Complete" or "Cooldown Complete")
        else timers.loading:Start(interval) end
    end
    timers.loading:Start(interval)
    debugPrint("Loading bar started ("..duration.."s)")
end

local function reflectPowerState(isOn, source)
    startLoadingBar(isOn)
    btnNavEventHandler(isOn and kLayer.Warming or kLayer.Cooling, source)
end

local function resetTouchInactivityTimer()
    if not timers.inactivity then return end
    timers.inactivity:Stop()
    if state.activeLayer ~= kLayer.Passcode then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity.EventHandler = function()
        debugPrint("Touch inactivity → Start (Source: Inactivity Timer)")
        btnNavEventHandler(kLayer.Start, "Inactivity Timeout")
    end
    timers.inactivity:Start(timeout)
    debugPrint("Touch inactivity timer reset ("..timeout.."s)")
end

local function syncRoomControlsState()
    if not components.roomControls or not components.roomControls["ledSystemPower"] then return end
    local cur = components.roomControls["ledSystemPower"].Boolean
    if cur == components.prevPowerState then return end
    debugPrint("Sync: "..tostring(components.prevPowerState).." → "..tostring(cur))
    components.prevPowerState = cur
    reflectPowerState(cur, "Room Automation Sync")
end

local function startSystem(eventSource)
    eventSource = eventSource or "System Start"
    powerOn()
    startLoadingBar(true)
    btnNavEventHandler(kLayer.Warming, eventSource)
end

local function shutdownSystem()
    updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
    powerOff()
    startLoadingBar(false)
    btnNavEventHandler(kLayer.Cooling, "System Shutdown")
end

local function ensureSystemIsOn(targetLayer)
    targetLayer = targetLayer or config.defaultLayer
    if components.roomControls and components.roomControls["ledSystemPower"] and components.roomControls["ledSystemPower"].Boolean then
        debugPrint("System already ON → layer "..targetLayer)
        btnNavEventHandler(targetLayer, "Source Active")
        return
    end
    if components.passcodeEnabled and not isPasscodeCorrect() then
        debugPrint("Passcode required")
        btnNavEventHandler(kLayer.Passcode, "Passcode Required")
        return
    end
    startSystem()
end


btnNavEventHandler = function(layerIndex, source)
    source = source or "Navigation"
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    if components.videoSwitcher and components.uciToInputMapping[layerIndex] then
        switchToInput(components.uciToInputMapping[layerIndex], layerIndex)
    end
    showLayer()
    interlock()
    debugPrint("Layer "..prev.." → "..layerIndex.." (Source: "..source..")")
end

local function routingButtonHandler(buttonIndex)
    if buttonIndex < 1 or buttonIndex > #routingLayers then return end
    state.activeRoutingLayer = buttonIndex
    showRoutingLayer()
    debugPrint("Routing → "..routingLayers[buttonIndex])
end

local function updateLegends()
    for i, lbl in ipairs(arrUCILegends) do
        if lbl and arrUCIUserLabels[i] then
            setProp(lbl, "Legend", arrUCIUserLabels[i].String or "")
        end
    end
end

local function initLegendArrays()
    local legendConfig = {
        {suffix = "Nav",        count = 13}, 
        {suffix = "Routing",    count = 5}, 
        {suffix = "VidSrc",     count = 12},
        {suffix = "GainPGM"},
        {suffix = "Gain",       count = 10}, 
        {suffix = "Display",    count = 4},
        {single={"NavShutdown","RoomNameNav","RoomNameStart","RoutingRooms","RoutingSources"}},
    }
    local idx = 0
    for _, cfg in ipairs(legendConfig) do
        if cfg.suffix then
            for i = 1, cfg.count do
                idx = idx + 1
                local name = cfg.suffix..string.format("%02d", i)
                arrUCILegends[idx] = Controls["txt"..name]
                arrUCIUserLabels[idx] = Uci.Variables["txtLabel"..name]
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do
                idx = idx + 1
                arrUCILegends[idx] = Controls["txt"..name]
                arrUCIUserLabels[idx] = Uci.Variables["txtLabel"..name]
            end
        end
    end
    for i, label in ipairs(arrUCIUserLabels) do
        if label then label.EventHandler = function() updateLegends() end end
    end
    debugPrint("Legends: "..(#arrUCILegends).." controls")
end

-------------------[ Events ]-------------------
local function registerEvents()
    local navCount = bindArray(controls.btnNav, function(i) btnNavEventHandler(i, "User Button") end)
    local routingCount = bindArray(controls.btnRouting, function(i) routingButtonHandler(i) end)
    debugPrint("Registered "..navCount.." nav, "..routingCount.." routing handlers")

    local helpUpdateFns = {
        Laptop=function() updateSourceHelpState("Laptop") end, PC=function() updateSourceHelpState("PC") end,
        Wireless=function() updateSourceHelpState("Wireless") end,
        Routing=updateRoutingHelpState, StreamMusic=updateStreamMusicHelpState,
    }
    for _, key in ipairs(configHelpPairKeys) do
        local openCtrl, closeCtrl = controls.btnOpenHelp[key], controls.btnCloseHelp[key]
        if openCtrl or closeCtrl then bindPairedControls(openCtrl, closeCtrl, helpUpdateFns[key]) end
    end

    bind(controls.btnStartSystem, function() ensureSystemIsOn(config.defaultLayer) end)
    bind(controls.btnNavShutdown, function() updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade") end)
    bind(controls.btnShutdownCancel, function() updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade") end)
    bind(controls.btnShutdownConfirm, function() shutdownSystem() end)

    local function onUSBChange(ctl, layer)
        if ctl.Boolean then ensureSystemIsOn(layer) else updateConferenceState() end
    end
    for name, def in pairs(configSource) do
        local hdmiCtrl = controls[def.hdmiKey]
        if hdmiCtrl then bind(hdmiCtrl, function() updateHDMIForActiveSource() end) end
        if def.usbKey then
            local usbCtrl = controls[def.usbKey]
            if usbCtrl then bind(usbCtrl, function(ctl) onUSBChange(ctl, def.layer) end) end
        end
    end
    bind(controls.pinLEDACPRBypassActive, function() updateACPRBypassState() end)
    bind(controls.pinLEDPresetSaved, function() updatePresetSavedState() end)
    bind(controls.pinCallActive, function() updateCallActiveState() end)
    if controls.pinLEDTouchActivity then
        bind(controls.pinLEDTouchActivity, function() resetTouchInactivityTimer() end)
    end
    debugPrint("Registered pin handlers")
end

local function initSyncFromSystemController()
    if not mySystemController or not mySystemController.state or not components.roomControls then return end
    local led = components.roomControls["ledSystemPower"]
    if not led or not led.Boolean then return end
    if mySystemController.state.isWarming then
        state.activeLayer = kLayer.Warming
        startLoadingBar(true)
        debugPrint("Synced: WARMING")
    else
        state.activeLayer = config.defaultLayer
        debugPrint("Synced: READY")
    end
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: pageUCI="..config.pageUCI..", debug="..tostring(config.debug))

    state.layerStates = {}
    state.activeLayer = kLayer.Start
    buildSources()
    buildLayerConfigs()
    normalizeControlArrays()
    initLegendArrays()
    initRoomControls()
    initVideoSwitcher()
    initPasscode()
    registerEvents()
    initSyncFromSystemController()

    for _, idx in ipairs(config.navHidden) do
        local btn = controls.btnNav[idx]
        if btn then btn.Visible = false; debugPrint("Hidden nav: "..idx) end
    end

    showLayer()
    interlock()
    updateLegends()

    state.isInitialized = true
    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
myUCI = {
    btnNavEventHandler = btnNavEventHandler,
    syncRoomControlsState = syncRoomControlsState,
    cleanup = function()
        timers.loading = stopTimer(timers.loading)
        timers.timeout = stopTimer(timers.timeout)
        if timers.inactivity then timers.inactivity:Stop() end
        if components.roomControls and components.roomControls["ledSystemPower"] then
            components.roomControls["ledSystemPower"].EventHandler = nil
        end
        if components.passcode and components.passcode["PasscodeCorrect"] then
            components.passcode["PasscodeCorrect"].EventHandler = nil
        end
        for _, label in ipairs(arrUCIUserLabels or {}) do
            if label then label.EventHandler = nil end
        end
        debugPrint("Cleanup complete")
    end,
    switchToInput = switchToInput,
    powerOn = powerOn,
    powerOff = powerOff,
    startLoadingBar = startLoadingBar,
}

-------------------[ Start ]-------------------
local pageName = config.pageUCI
local pageNames = {
    pageName,
    pageName:gsub("%s+", " "),
    pageName:gsub("%s+", ""),
    pageName:gsub("%(", ""):gsub("%)", ""),
    pageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", ""),
    "UCI "..pageName,
    pageName:match("^(.-)%s*%(") or pageName,
}

local ok, err
for _, pn in ipairs(pageNames) do
    config.pageUCI = pn
    ok, err = pcall(function()
        if not validateControls() then error("Control validation failed") end
        normalizeControlArrays()
        init()
    end)
    if ok then
        print("✓ UCIController initialized for "..pn)
        break
    end
    print("UCI attempt for '"..pn.."': "..tostring(err))
end

if not ok then
    print("✗ ERROR: UCIController failed: "..tostring(err))
end
