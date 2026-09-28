--[[
  UCI Controller (DivisibleSpace) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 4.1 | Date: 2026-09-26
  Firmware Req: pre-10.4 compatible

  Divisible-space UCI. One visibility engine: buildDesired → applyDesired (hides every refresh).
]]--

-------------------[ Configuration ]-------------------

conferenceStateConfig = { skip = { [9]=false, [10]=false } }
acprConfig = { disableACPRShow = false }

kLayer = {
    Alarm           = 1,
    IncomingCall    = 2,
    Start           = 3,
    Warming         = 4,
    Cooling         = 5,
    RoomControls    = 6,
    PCA             = 7,
    PCB             = 8,
    LaptopA         = 9,
    LaptopB         = 10,
    Wireless        = 11,
    Routing         = 12,
    Dialer          = 13,
    StreamMusic     = 14,
    RoomCombining   = 15,
}

layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
    "H04-RoomCombining","H08-RoomControlsCombined","H09-RoomControlsSeparated","H10-RoomControls",
    "I01-CallActive","I02-HelpLaptopA","I03-HelpLaptopB","I04-HelpPCA","I05-HelpPCB",
    "I06-HelpWirelessA","I07-HelpWirelessB","I08-HelpRouting","I09-HelpDialer","I10-HelpStreamMusic",
    "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB","J03-ConnectUSBPCA","J04-ConnectUSBPCB",
    "J06-ACPRActiveCombined","J07-ACPRActiveSeparated","J08-CamPresetSaved",
    "J09-ACPRBtnCombined","J10-ACPRBtnSeparated",
    "J11-CamSelectLaptopA","J12-CamSelectLaptopB","J13-CamSelectPCA","J14-CamSelectPCB",
    "J17-VideoPrivacySeparatedA","J18-VideoPrivacySeparatedB","J19-VideoPrivacyCombinedA","J20-VideoPrivacyCombinedB",
    "J21-ConferenceLaptopA","J22-ConferenceLaptopB","J23-ConferencePCA","J24-ConferencePCB",
    "L01-HDMIDisc","L01-LaptopA","L02-HDMIDisc","L02-LaptopB",
    "P01-HDMIDisc","P01-PCA","P02-HDMIDisc","P02-PCB",
    "W01-WirelessA","W02-WirelessB","W05-Wireless","R10-Routing","S10-StreamMusic","V05-Dialer",
}

acprLayers = { combined = "J06-ACPRActiveCombined", separated = "J07-ACPRActiveSeparated" }
acprBtnLayers = { combined = "J09-ACPRBtnCombined", separated = "J10-ACPRBtnSeparated" }

configSource = {
    LaptopA = {
        layer = kLayer.LaptopA, hdmiKey = "ledHDMIConnectLaptopA", usbKey = "ledUSBLaptopA",
        base = "L01-LaptopA", disc = "L01-HDMIDisc", usb = "J01-ConnectUSBLaptopA",
        conf = "J21-ConferenceLaptopA", camera = "J11-CamSelectLaptopA",
        help = "I02-HelpLaptopA",
    },
    LaptopB = {
        layer = kLayer.LaptopB, hdmiKey = "ledHDMIConnectLaptopB", usbKey = "ledUSBLaptopB",
        base = "L02-LaptopB", disc = "L02-HDMIDisc", usb = "J02-ConnectUSBLaptopB",
        conf = "J22-ConferenceLaptopB", camera = "J12-CamSelectLaptopB",
        help = "I03-HelpLaptopB",
    },
    PCA = {
        layer = kLayer.PCA, hdmiKey = "ledHDMIConnectPCA", usbKey = "ledUSBPCA",
        base = "P01-PCA", disc = "P01-HDMIDisc", usb = "J03-ConnectUSBPCA",
        conf = "J23-ConferencePCA", camera = "J13-CamSelectPCA",
        help = "I04-HelpPCA", vidPrivSep = "J17-VideoPrivacySeparatedA", vidPrivComb = "J19-VideoPrivacyCombinedA",
    },
    PCB = {
        layer = kLayer.PCB, hdmiKey = "ledHDMIConnectPCB", usbKey = "ledUSBPCB",
        base = "P02-PCB", disc = "P02-HDMIDisc", usb = "J04-ConnectUSBPCB",
        conf = "J24-ConferencePCB", camera = "J14-CamSelectPCB",
        help = "I05-HelpPCB", vidPrivSep = "J18-VideoPrivacySeparatedB", vidPrivComb = "J20-VideoPrivacyCombinedB",
    },
}

layerToSourceKey = {}
for key, def in pairs(configSource) do layerToSourceKey[def.layer] = key end

overlayConfigs = {
    [kLayer.Wireless] = {
        { layer = "I06-HelpWirelessA", helpKey = "WirelessA" },
        { layer = "I07-HelpWirelessB", helpKey = "WirelessB" },
    },
    [kLayer.Routing]     = { { layer = "I08-HelpRouting", helpKey = "Routing" } },
    [kLayer.StreamMusic] = { { layer = "I10-HelpStreamMusic", helpKey = "StreamMusic" } },
}

configHelpPairKeys = {"LaptopA","LaptopB","PCA","PCB","WirelessA","WirelessB","Routing","StreamMusic"}

helpControls = {
    LaptopA     = { open = Controls.btnOpenHelpLaptopA,     close = Controls.btnCloseHelpLaptopA },
    LaptopB     = { open = Controls.btnOpenHelpLaptopB,     close = Controls.btnCloseHelpLaptopB },
    PCA         = { open = Controls.btnOpenHelpPCA,         close = Controls.btnCloseHelpPCA },
    PCB         = { open = Controls.btnOpenHelpPCB,         close = Controls.btnCloseHelpPCB },
    WirelessA   = { open = Controls.btnOpenHelpWirelessA,   close = Controls.btnCloseHelpWirelessA },
    WirelessB   = { open = Controls.btnOpenHelpWirelessB,   close = Controls.btnCloseHelpWirelessB },
    Routing     = { open = Controls.btnOpenHelpRouting,     close = Controls.btnCloseHelpRouting },
    StreamMusic = { open = Controls.btnOpenHelpStreamMusic, close = Controls.btnCloseHelpStreamMusic },
}

layerConfigs = {
    [kLayer.Alarm]        = { show = {"A01-Alarm"}, hideBase = true },
    [kLayer.IncomingCall] = { show = {"B01-IncomingCall"} },
    [kLayer.Start]        = { show = {"C05-Start"}, hideBase = true },
    [kLayer.Warming]      = { show = {"E05-SystemProgress","E01-SystemProgressWarming"}, hideBase = true },
    [kLayer.Cooling]      = { show = {"E05-SystemProgress","E02-SystemProgressCooling"}, hideBase = true },
    [kLayer.RoomControls] = { roomControlsLayer = true, hide = {"X01-ProgramVolume"} },
    [kLayer.Wireless]     = { show = {"W05-Wireless"} },
    [kLayer.Routing]      = { show = {"R10-Routing"} },
    [kLayer.Dialer]       = { show = {"V05-Dialer"} },
    [kLayer.StreamMusic]  = { show = {"S10-StreamMusic"} },
    [kLayer.RoomCombining]= { show = {"H04-RoomCombining"}, hideBase = true },
    [kLayer.LaptopA]      = { sourceKey = "LaptopA" },
    [kLayer.LaptopB]      = { sourceKey = "LaptopB" },
    [kLayer.PCA]          = { sourceKey = "PCA" },
    [kLayer.PCB]          = { sourceKey = "PCB" },
}

labelConfig = {
    {suffix = "Nav", count = 15},
    {single = {"NavShutdown","RoomNameNav","RoomNameStart","RoutingRooms","RoutingSources"}},
    {suffix = "Routing", count = 12},
    {suffix = "VidSrc", count = 12},
    {suffix = "GainPGM"},
    {suffix = "Gain", count = 10},
    {suffix = "Display", count = 12},
}

navHidden = {}

btnNav = {
    Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04, Controls.btnNav05,
    Controls.btnNav06, Controls.btnNav07, Controls.btnNav08, Controls.btnNav09, Controls.btnNav10,
    Controls.btnNav11, Controls.btnNav12, Controls.btnNav13, Controls.btnNav14, Controls.btnNav15,
}

usbConnectLayers, confLayers = {}, {}
for _, def in pairs(configSource) do
    if def.usb then table.insert(usbConnectLayers, def.usb) end
    if def.conf then table.insert(confLayers, def.conf) end
end

-------------------[ Constant Tables ]-------------------

pageUCI = nil
state = {
    activeLayer = kLayer.Start,
    layerStates = {},
    shutdownConfirm = false,
    isAnimating = false,
    isInitialized = false,
}
components = {
    roomControls = nil, prevPowerState = nil,
    divisibleSpace = nil, btnRoomState = nil, roomIdentity = nil,
}
timers = { loading = nil, timeout = nil, inactivity = Timer.New() }
uciLegends, uciUserLabels = {}, {}
labelCount = 0

-------------------[ Constants ]-------------------

stateDebug = true
defaultLayer = tonumber(Uci.Variables.numDefaultActiveLayer and Uci.Variables.numDefaultActiveLayer.Value) or 10

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

function boolOf(ctrl)
    return ctrl and ctrl.Boolean or false
end

function stopTimer(timer)
    if timer then pcall(function() timer:Stop() end) end
    return nil
end

function debugPrint(str)
    if stateDebug and pageUCI then print("["..pageUCI.."] "..str) end
end

function bindButtons(buttons, handler)
    for i, btn in ipairs(buttons) do
        if btn then btn.EventHandler = function() handler(i, btn) end end
    end
end

function buildPageNameCandidates(hint)
    local pageName = (hint and hint ~= "") and hint or "UCI"
    return {
        pageName,
        pageName:gsub("%s+", " "),
        pageName:gsub("%s+", ""),
        pageName:gsub("%(", ""):gsub("%)", ""),
        pageName:gsub("%s+", "-"):gsub("%(", ""):gsub("%)", ""),
        "UCI "..pageName,
        pageName:match("^(.-)%s*%(") or pageName,
    }
end

function validateControls()
    local required = {
        "btnNav01","btnNav02","btnNav03","btnNav04","btnNav05","btnNav06","btnNav07","btnNav08","btnNav09",
        "btnNav10","btnNav11","btnNav12","btnNav13","btnNav14","btnNav15",
        "btnStartSystem","btnNavShutdown","btnShutdownCancel","btnShutdownConfirm",
        "knbProgressBar","txtProgressBar",
        "pinCallActive","ledPresetSaved",
        "ledUSBLaptopA","ledUSBLaptopB","ledUSBPCA","ledUSBPCB",
        "ledACPRBypassSeparated","ledACPRBypassCombined",
    }
    local optional = {
        ledTouchActivity = true,
        ledHDMIConnectPCA = true, ledHDMIConnectPCB = true,
        ledHDMIConnectLaptopA = true, ledHDMIConnectLaptopB = true,
    }
    local missing = {}
    for _, name in ipairs(required) do
        if not Controls[name] then table.insert(missing, name) end
    end
    for name in pairs(optional) do
        if not Controls[name] then debugPrint("Optional control missing: "..name) end
    end
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, n in ipairs(missing) do print("  - "..n) end
        return false
    end
    return true
end

-------------------[ Divisible Space ]-------------------

function getRoomState()
    if not components.divisibleSpace or not components.btnRoomState then return "separated" end
    local btns = components.btnRoomState
    if btns[1] and btns[1].Boolean then return "separated"
    elseif btns[2] and btns[2].Boolean then return "combinedA"
    elseif btns[3] and btns[3].Boolean then return "combinedB" end
    return "separated"
end

function getDefaultLayerAfterWarming()
    local roomState = getRoomState()
    local roomId = components.roomIdentity or "TrainingA"
    if roomState == "separated" then
        return (roomId == "TrainingB") and kLayer.PCB or kLayer.PCA
    elseif roomState == "combinedA" then return kLayer.PCA
    elseif roomState == "combinedB" then return kLayer.PCB end
    return kLayer.Routing
end

function getRoomControlsLayerName(roomState)
    roomState = roomState or getRoomState()
    return (roomState == "separated") and "H09-RoomControlsSeparated" or "H08-RoomControlsCombined"
end

function shouldShowLayer(layerIndex, roomState)
    roomState = roomState or getRoomState()
    local roomId = components.roomIdentity
    local avail = {
        TrainingA = { [kLayer.PCA] = true, [kLayer.LaptopA] = true },
        TrainingB = { [kLayer.PCB] = true, [kLayer.LaptopB] = true },
    }
    if roomState == "combinedA" or roomState == "combinedB" then return true end
    if roomState == "separated" and avail[roomId] then
        local v = avail[roomId][layerIndex]
        if v ~= nil then return v end
    end
    return true
end

function updateNavigationVisibility(roomState)
    roomState = roomState or getRoomState()
    local roomId = components.roomIdentity
    local isSep = (roomState == "separated")
    local navConfig = {
        TrainingA = {{num = "08"}, {num = "10"}},
        TrainingB = {{num = "07"}, {num = "09"}},
    }
    local toUpdate = navConfig[roomId]
    if not toUpdate then return end
    for _, cfg in ipairs(toUpdate) do
        local btn = Controls["btnNav"..cfg.num]
        local txt = Controls["txtNav"..cfg.num]
        if btn then setProp(btn, "IsInvisible", isSep) end
        if txt then setProp(txt, "IsInvisible", isSep) end
    end
    debugPrint("Nav visibility: Room="..tostring(roomId)..", State="..roomState)
end

function updateStartSystemLegend(roomState)
    roomState = roomState or getRoomState()
    local legend = (roomState == "separated") and "Start Room" or "Start Rooms"
    setProp(Controls.btnStartSystem, "Legend", legend)
end

-------------------[ Visibility ]-------------------

function want(desired, transitions, names, visible, transition)
    if type(names) ~= "table" then names = {names} end
    for _, name in ipairs(names) do
        if name and name ~= "" then
            desired[name] = visible
            if transition then transitions[name] = transition end
        end
    end
end

function applyDesired(desired, transitions)
    -- Hides always republish (Q-SYS clients can paint stale layers); shows skip if unchanged.
    for name, wantVis in pairs(desired) do
        local changed = state.layerStates[name] ~= wantVis
        if wantVis == false or changed then
            local trans = wantVis and ((transitions and transitions[name]) or "fade") or "none"
            local ok, err = pcall(Uci.SetLayerVisibility, pageUCI, name, wantVis, trans)
            if ok then state.layerStates[name] = wantVis
            else debugPrint("Layer '"..name.."' error: "..tostring(err)) end
        end
    end
end

function hdmiConnected(sourceKey)
    local def = configSource[sourceKey]
    if not def or not def.hdmiKey then return true end
    local pin = Controls[def.hdmiKey]
    return not pin or pin.Boolean
end

function activeSourceKey()
    return layerToSourceKey[state.activeLayer]
end

function applyHelpOverlay(desired, transitions, layerName, helpKey, onShow)
    local hc = helpControls[helpKey]
    local helpVis = boolOf(hc and hc.open)
    want(desired, transitions, layerName, helpVis, helpVis and "fade" or "none")
    if helpVis and onShow then onShow() end
end

function applySourceOverlay(desired, transitions, sourceKey)
    local def = configSource[sourceKey]
    if not def then return end

    if not hdmiConnected(sourceKey) then
        want(desired, transitions, def.disc, true, "fade")
        return
    end

    want(desired, transitions, def.base, true, "fade")

    if not conferenceStateConfig.skip[def.layer] then
        local usb = boolOf(def.usbKey and Controls[def.usbKey])
        if usb then
            want(desired, transitions, def.conf, true, "fade")
        elseif def.usb then
            want(desired, transitions, def.conf, true, "fade")
            want(desired, transitions, def.usb, true, "fade")
        end
    end

    if def.help then
        applyHelpOverlay(desired, transitions, def.help, sourceKey, function()
            want(desired, transitions, confLayers, false)
            want(desired, transitions, usbConnectLayers, false)
        end)
    end
end

function getSourceLayerVisibility(def, isActive, usbConnected, isCombined, desired, transitions)
    local confActive = false
    if def.camera and isActive and isCombined then
        want(desired, transitions, def.camera, true, "fade")
    end
    if isActive and usbConnected then
        want(desired, transitions, def.conf, true, "fade")
        confActive = true
    end
    if def.vidPrivSep and def.vidPrivComb and isActive and usbConnected then
        if isCombined then
            want(desired, transitions, def.vidPrivComb, true, "fade")
        else
            want(desired, transitions, def.vidPrivSep, true, "fade")
        end
    end
    return confActive
end

function applyConferenceControlsDesired(desired, transitions, roomState)
    local sourceKey = activeSourceKey()
    if not sourceKey or not hdmiConnected(sourceKey) then return end
    roomState = roomState or getRoomState()
    local isCombined = (roomState ~= "separated")
    local anyConfActive = false
    for name, def in pairs(configSource) do
        local isActive = (state.activeLayer == def.layer)
        local usb = boolOf(def.usbKey and Controls[def.usbKey])
        if getSourceLayerVisibility(def, isActive, usb, isCombined, desired, transitions) then
            anyConfActive = true
        end
    end
    if not acprConfig.disableACPRShow and anyConfActive then
        want(desired, transitions, isCombined and acprBtnLayers.combined or acprBtnLayers.separated, true, "fade")
    end
end

function applyACPRDesired(desired, transitions, roomState)
    if acprConfig.disableACPRShow then return end
    local sourceKey = activeSourceKey()
    if not sourceKey or not hdmiConnected(sourceKey) then return end
    local def = configSource[sourceKey]
    roomState = roomState or getRoomState()
    local isSep = (roomState == "separated")
    local bypassCtl = isSep and Controls.ledACPRBypassSeparated or Controls.ledACPRBypassCombined
    local acprOn = isSep and acprLayers.separated or acprLayers.combined
    local bypass = boolOf(bypassCtl)
    if not bypass then
        want(desired, transitions, acprOn, true, "fade")
        want(desired, transitions, def.conf, true, "fade")
    else
        want(desired, transitions, def.conf, true, "fade")
    end
end

function applyOverlayHelp(desired, transitions)
    local entries = overlayConfigs[state.activeLayer]
    if not entries then return end
    for _, entry in ipairs(entries) do
        applyHelpOverlay(desired, transitions, entry.layer, entry.helpKey)
    end
    if state.activeLayer == kLayer.Dialer then
        want(desired, transitions, "I09-HelpDialer", boolOf(Controls.btnHelpDialer), "none")
    end
end

function buildDesired(roomState)
    roomState = roomState or getRoomState()
    local desired, transitions = {}, {}
    want(desired, transitions, layersToHide, false)

    local cfg = layerConfigs[state.activeLayer]
    if cfg then
        local baseVis = not cfg.hideBase
        for _, name in ipairs(layersBase) do
            want(desired, transitions, name, baseVis, baseVis and "fade" or "none")
        end
        if cfg.roomControlsLayer then
            want(desired, transitions, getRoomControlsLayerName(roomState), true, "fade")
        elseif cfg.sourceKey then
            if not shouldShowLayer(state.activeLayer, roomState) then
                debugPrint("Layer "..state.activeLayer.." hidden by divisible-space")
            end
        elseif cfg.show then
            want(desired, transitions, cfg.show, true, "fade")
        end
        want(desired, transitions, cfg.hide, false)
    end

    local callActive = boolOf(Controls.pinCallActive)
    want(desired, transitions, "I01-CallActive", callActive, callActive and "fade" or "none")

    local preset = boolOf(Controls.ledPresetSaved)
    want(desired, transitions, "J08-CamPresetSaved", preset, preset and "fade" or "none")

    want(desired, transitions, "D01-ShutdownConfirm", state.shutdownConfirm, state.shutdownConfirm and "fade" or "none")

    applyOverlayHelp(desired, transitions)

    local sourceKey = activeSourceKey()
    if sourceKey and shouldShowLayer(state.activeLayer, roomState) then
        applySourceOverlay(desired, transitions, sourceKey)
        if hdmiConnected(sourceKey) then
            applyConferenceControlsDesired(desired, transitions, roomState)
            applyACPRDesired(desired, transitions, roomState)
        end
    end

    return desired, transitions
end

function syncHelpButtons()
    for _, hc in pairs(helpControls) do
        if hc.close then setProp(hc.close, "Boolean", false) end
    end
end

function refreshLayers()
    local roomState = getRoomState()
    local desired, transitions = buildDesired(roomState)
    applyDesired(desired, transitions)
    syncHelpButtons()
    updateNavigationVisibility(roomState)
    updateStartSystemLegend(roomState)
end

function setHelpOpen(key, isOpen)
    local hc = helpControls[key]
    if not hc then return end
    if hc.open then setProp(hc.open, "Boolean", isOpen) end
    if hc.close then setProp(hc.close, "Boolean", false) end
    refreshLayers()
end

function interlockNav()
    for i, btn in ipairs(btnNav) do
        if btn then setProp(btn, "Boolean", i == state.activeLayer) end
    end
end

-------------------[ Navigation ]-------------------

function goToLayer(layerIndex, source)
    source = source or "Navigation"
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    if layerIndex == kLayer.RoomCombining then resetTouchInactivityTimer() end
    refreshLayers()
    interlockNav()
    debugPrint("Layer "..prev.." → "..layerIndex.." (Source: "..source..")")
end

-------------------[ Room Controls ]-------------------

function initRoomControls()
    local compName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String
    if not compName then
        local page = pageUCI:match("uci%s+([^(]+)")
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

function initDivisibleSpace()
    local roomName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String or ""
    if roomName:find("TrainingA") then
        components.roomIdentity = "TrainingA"
        debugPrint("Room identity: Collab A")
    elseif roomName:find("TrainingB") then
        components.roomIdentity = "TrainingB"
        debugPrint("Room identity: Collab B")
    else
        debugPrint("Room identity: could not determine from "..roomName)
    end
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if ok and comp then
        components.divisibleSpace = comp
        components.btnRoomState = {
            comp["btnRoomState 1"], comp["btnRoomState 2"], comp["btnRoomState 3"],
        }
        for _, btn in ipairs(components.btnRoomState) do
            if btn then
                btn.EventHandler = function(ctl)
                    if not ctl.Boolean then return end
                    refreshLayers()
                end
            end
        end
        debugPrint("DivisibleSpace: registered room-state handlers")
    else
        debugPrint("DivisibleSpace: component not found (feature disabled)")
    end
    return components.divisibleSpace ~= nil
end

function powerOn()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
    components.roomControls["btnSystemOnOff"].Boolean = true
    debugPrint("Room → ON")
    return true
end

function powerOff()
    if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
    components.roomControls["btnSystemOnOff"].Boolean = false
    debugPrint("Room → OFF")
    return true
end

-------------------[ Power Progress ]-------------------

function startLoadingBar(isPoweringOn)
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
        duration = isPoweringOn and (tonumber(Uci.Variables.timeProgressWarming) or 10)
            or (tonumber(Uci.Variables.timeProgressCooling) or 5)
    end
    local steps, interval, currentStep = 100, duration / 100, 0
    setProp(Controls.knbProgressBar, "Value", isPoweringOn and 0 or 100)
    setProp(Controls.txtProgressBar, "String", (isPoweringOn and 0 or 100).."%")
    timers.loading = Timer.New()
    timers.timeout = Timer.New()
    timers.timeout.EventHandler = function()
        state.isAnimating = false
        timers.loading = stopTimer(timers.loading)
        goToLayer(isPoweringOn and getDefaultLayerAfterWarming() or kLayer.Start, "Loading Timeout")
    end
    timers.timeout:Start(300)
    timers.loading.EventHandler = function()
        currentStep = currentStep + 1
        local prog = isPoweringOn and currentStep or (100 - currentStep)
        setProp(Controls.knbProgressBar, "Value", prog)
        setProp(Controls.txtProgressBar, "String", prog.."%")
        if currentStep >= steps then
            timers.loading = stopTimer(timers.loading)
            timers.timeout = stopTimer(timers.timeout)
            state.isAnimating = false
            goToLayer(isPoweringOn and getDefaultLayerAfterWarming() or kLayer.Start,
                isPoweringOn and "Warmup Complete" or "Cooldown Complete")
        else
            timers.loading:Start(interval)
        end
    end
    timers.loading:Start(interval)
    debugPrint("Loading bar started ("..duration.."s)")
end

function reflectPowerState(isOn, source)
    startLoadingBar(isOn)
    goToLayer(isOn and kLayer.Warming or kLayer.Cooling, source)
end

function isOnRoomCombiningLayer()
    return state.activeLayer == kLayer.RoomCombining
end

function onTouchInactivityTimeout()
    if not isOnRoomCombiningLayer() then return end
    debugPrint("Touch inactivity → Start (Source: Inactivity Timer)")
    goToLayer(kLayer.Start, "Inactivity Timeout")
end

function resetTouchInactivityTimer()
    if not timers.inactivity then return end
    timers.inactivity:Stop()
    if not isOnRoomCombiningLayer() then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity:Start(timeout)
end

function syncRoomControlsState()
    if not components.roomControls or not components.roomControls["ledSystemPower"] then return end
    local cur = components.roomControls["ledSystemPower"].Boolean
    if cur == components.prevPowerState then return end
    components.prevPowerState = cur
    reflectPowerState(cur, "Room Automation Sync")
end

function startSystem(eventSource)
    powerOn()
    startLoadingBar(true)
    goToLayer(kLayer.Warming, eventSource or "System Start")
end

function ensureSystemIsOn(targetLayer)
    targetLayer = targetLayer or defaultLayer
    if components.roomControls and components.roomControls["ledSystemPower"]
        and components.roomControls["ledSystemPower"].Boolean then
        goToLayer(targetLayer, "Source Active")
        return
    end
    startSystem()
end

function shutdownSystem()
    state.shutdownConfirm = false
    powerOff()
    startLoadingBar(false)
    goToLayer(kLayer.Cooling, "System Shutdown")
end

function initSyncFromSystemController()
    if not mySystemController or not mySystemController.state or not components.roomControls then return end
    local led = components.roomControls["ledSystemPower"]
    if not led or not led.Boolean then return end
    if mySystemController.state.isWarming then
        state.activeLayer = kLayer.Warming
        startLoadingBar(true)
        debugPrint("Synced: WARMING")
    else
        state.activeLayer = getDefaultLayerAfterWarming()
        debugPrint("Synced: READY")
    end
end

-------------------[ Legends ]-------------------

function syncLabels()
    for i = 1, labelCount do
        local lbl = uciLegends[i]
        if lbl and uciUserLabels[i] then
            setProp(lbl, "Legend", uciUserLabels[i].String or "")
        end
    end
end

function initLabelArrays()
    local idx = 0
    local function labelVarName(ctrlName)
        return "txtLabel"..(ctrlName:gsub("^txt", "") or ctrlName)
    end
    local function registerLegend(name)
        idx = idx + 1
        uciLegends[idx] = Controls["txt"..name]
        uciUserLabels[idx] = Uci.Variables[labelVarName("txt"..name)]
    end
    for _, cfg in ipairs(labelConfig) do
        if cfg.suffix then
            for i = 1, (cfg.count or 1) do
                local name = cfg.count and (cfg.suffix..string.format("%02d", i)) or cfg.suffix
                registerLegend(name)
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do registerLegend(name) end
        end
    end
    labelCount = idx
    for i = 1, labelCount do
        local label = uciUserLabels[i]
        if label then label.EventHandler = function() syncLabels() end end
    end
    debugPrint("Legends: "..labelCount.." controls")
end

-------------------[ Event Handlers ]-------------------

bindButtons(btnNav, function(i) goToLayer(i, "btnNav") end)

Controls.btnStartSystem.EventHandler = function()
    ensureSystemIsOn(defaultLayer)
end

Controls.btnNavShutdown.EventHandler = function()
    state.shutdownConfirm = true
    refreshLayers()
end

Controls.btnShutdownCancel.EventHandler = function()
    state.shutdownConfirm = false
    refreshLayers()
end

Controls.btnShutdownConfirm.EventHandler = function()
    shutdownSystem()
end

for _, key in ipairs(configHelpPairKeys) do
    local hc = helpControls[key]
    if hc then
        ;(function(k, c)
            if c.open then c.open.EventHandler = function() setHelpOpen(k, true) end end
            if c.close then c.close.EventHandler = function() setHelpOpen(k, false) end end
        end)(key, hc)
    end
end

if Controls.btnHelpDialer then
    Controls.btnHelpDialer.EventHandler = function() refreshLayers() end
end

for name, def in pairs(configSource) do
    local hdmiActive = Controls["ledHDMIActive"..name]
    if hdmiActive then
        ;(function(layer)
            hdmiActive.EventHandler = function(ctl)
                if ctl.Boolean then
                    ensureSystemIsOn(layer)
                    goToLayer(layer, "HDMI Active")
                end
            end
        end)(def.layer)
    end
    if def.usbKey and Controls[def.usbKey] then
        ;(function(layer, usbKey)
            Controls[usbKey].EventHandler = function(ctl)
                if ctl.Boolean then ensureSystemIsOn(layer) else refreshLayers() end
            end
        end)(def.layer, def.usbKey)
    end
    if def.hdmiKey and Controls[def.hdmiKey] then
        Controls[def.hdmiKey].EventHandler = function() refreshLayers() end
    end
end

if Controls.ledACPRBypassSeparated then
    Controls.ledACPRBypassSeparated.EventHandler = function() refreshLayers() end
end
if Controls.ledACPRBypassCombined then
    Controls.ledACPRBypassCombined.EventHandler = function() refreshLayers() end
end
if Controls.ledPresetSaved then
    Controls.ledPresetSaved.EventHandler = function() refreshLayers() end
end
if Controls.pinCallActive then
    Controls.pinCallActive.EventHandler = function() refreshLayers() end
end
if timers.inactivity then
    timers.inactivity.EventHandler = onTouchInactivityTimeout
end
if Controls.ledTouchActivity then
    Controls.ledTouchActivity.EventHandler = function() resetTouchInactivityTimer() end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugPrint("=== Initialization Started ===")

    state.layerStates = {}
    state.activeLayer = kLayer.Start
    initLabelArrays()
    if not initRoomControls() then
        print("ERROR: Room controls unavailable — power actions disabled")
    end
    initDivisibleSpace()
    initSyncFromSystemController()

    for _, idx in ipairs(navHidden) do
        local btn = btnNav[idx]
        if btn then btn.Visible = false end
    end

    refreshLayers()
    interlockNav()
    syncLabels()

    state.isInitialized = true
    debugPrint("=== Initialization Complete ===")
end

-------------------[ Public API ]-------------------

myUCI = {
    btnNavEventHandler = goToLayer,
    syncRoomControlsState = syncRoomControlsState,
    cleanup = function()
        timers.loading = stopTimer(timers.loading)
        timers.timeout = stopTimer(timers.timeout)
        if timers.inactivity then timers.inactivity:Stop() end
        if components.roomControls and components.roomControls["ledSystemPower"] then
            components.roomControls["ledSystemPower"].EventHandler = nil
        end
        for i = 1, labelCount do
            local label = uciUserLabels[i]
            if label then label.EventHandler = nil end
        end
        if components.btnRoomState then
            for _, btn in ipairs(components.btnRoomState) do
                if btn then btn.EventHandler = nil end
            end
        end
        debugPrint("Cleanup complete")
    end,
    powerOn = powerOn,
    powerOff = powerOff,
    startLoadingBar = startLoadingBar,
}

hint = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or ""
ok, err = nil, nil
for _, pageName in ipairs(buildPageNameCandidates(hint)) do
    pageUCI = pageName
    ok, err = pcall(function()
        if not validateControls() then error("Control validation failed") end
        funcInit()
    end)
    if ok then
        print("✓ UCIController (DivisibleSpace) initialized for "..pageName)
        break
    end
    print("UCI attempt for '"..pageName.."': "..tostring(err))
end

if not ok then
    print("✗ ERROR: UCIController (DivisibleSpace) failed: "..tostring(err))
end
