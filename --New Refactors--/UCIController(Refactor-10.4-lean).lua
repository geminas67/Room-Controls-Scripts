--[[
  UCI Controller (Lean) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.0 | Date: 2026-07-04
  Firmware Req: 10.4

  Flat single-room UCI: configSource, declarative visibility (buildDesired/applyDesired),
  event-driven power sync, switcher auto-detect. Three engines — visibility, room sync, switcher.
]]--

-------------------[ Configuration ]-------------------

local conferenceStateConfig = { skip = { [9]=true } }  -- PC/Laptop: show J01/J02 when USB disconnected, J09/J10 when connected
local acprConfig = { disableACPRShow = false }

local layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
local layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-ProgressWarming","E02-ProgressCooling","E05-Progress",
    "H01-PasscodeEntry","H10-RoomControls",
    "I01-CallActive","I02-HelpLaptop","I03-HelpPC","I04-HelpWireless","I05-HelpRouting","I07-HelpStreamMusic",
    "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J09-ConferenceLaptop","J10-ConferencePC",
    "L01-HDMIDisc","L05-Laptop","P01-HDMIDisc","P05-PC","W01-HDMIDisc","W05-Wireless",
    "R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05","R10-Routing",
    "S05-StreamMusic","V05-Dialer"
}
local routingLayers = {"R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05"}
local usbConnectLayers = {"J01-ConnectUSBLaptop","J02-ConnectUSBPC"}
local confLayers = {"J09-ConferenceLaptop","J10-ConferencePC"}

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
        layer   = kLayer.PC,
        hdmiKey = "ledHDMI01Connect",
        usbKey  = "ledUSBPC",
        base    = "P05-PC",
        disc    = "P01-HDMIDisc",
        usb     = "J02-ConnectUSBPC",
        conf    = "J10-ConferencePC",
        help    = "I03-HelpPC"
    },
    Laptop = {
        layer   = kLayer.Laptop,
        hdmiKey = "ledHDMI02Connect",
        usbKey  = "ledUSBLaptop",
        base    = "L05-Laptop",
        disc    = "L01-HDMIDisc",
        usb     = "J01-ConnectUSBLaptop",
        conf    = "J09-ConferenceLaptop",
        help    = "I02-HelpLaptop"
    },
    Wireless = {
        layer   = kLayer.Wireless,
        hdmiKey = "ledHDMI03Connect",
        usbKey  = nil,
        base    = "W05-Wireless",
        disc    = "W01-HDMIDisc",
        usb     = nil,
        conf    = nil,
        help    = "I04-HelpWireless"
    },
}

local layerToSourceKey = { [7]="PC", [8]="Laptop", [9]="Wireless" }
local configHelpPairKeys = {"Laptop","PC","Wireless","Routing","StreamMusic"}
local layerHelpToKey = {
    ["I02-HelpLaptop"]="Laptop", ["I03-HelpPC"]="PC", ["I04-HelpWireless"]="Wireless",
    ["I05-HelpRouting"]="Routing", ["I07-HelpStreamMusic"]="StreamMusic",
}

local helpControls = {
    Laptop      = { open = Controls.btnOpenHelpLaptop,      close = Controls.btnCloseHelpLaptop },
    PC          = { open = Controls.btnOpenHelpPC,          close = Controls.btnCloseHelpPC },
    Wireless    = { open = Controls.btnOpenHelpWireless,    close = Controls.btnCloseHelpWireless },
    Routing     = { open = Controls.btnOpenHelpRouting,     close = Controls.btnCloseHelpRouting },
    StreamMusic = { open = Controls.btnOpenHelpStreamMusic, close = Controls.btnCloseHelpStreamMusic },
}

local layerConfigs = {
    [kLayer.Alarm]        = { show = {"A01-Alarm"}, hideBase = true },
    [kLayer.IncomingCall] = { show = {"B01-IncomingCall"} },
    [kLayer.Start]        = { show = {"C05-Start"}, hideBase = true },
    [kLayer.Warming]      = { show = {"E05-Progress","E01-ProgressWarming"}, hideBase = true },
    [kLayer.Cooling]      = { show = {"E05-Progress","E02-ProgressCooling"}, hideBase = true },
    [kLayer.RoomControls] = { show = {"H10-RoomControls"}, hide = {"X01-ProgramVolume"} },
    [kLayer.Laptop]       = { show = {"L05-Laptop"} },
    [kLayer.PC]           = { show = {"P05-PC"} },
    [kLayer.Wireless]     = { show = {"W05-Wireless"} },
    [kLayer.Routing]      = { show = {"R10-Routing"} },
    [kLayer.Dialer]       = { show = {"V05-Dialer"} },
    [kLayer.StreamMusic]  = { show = {"S05-StreamMusic"} },
    [kLayer.Passcode]     = { show = {"H01-PasscodeEntry"}, hideBase = true },
}

local legendConfig = {
    {suffix = "Nav",     count = 12},
    {suffix = "Routing", count = 5},
    --{suffix = "VidSrc",  count = 12},
    {suffix = "GainPGM"},
    {suffix = "Gain",    count = 10},
    {suffix = "Display", count = 4},
    {single = {"NavShutdown","RoomNameNav","RoomNameStart","RoutingRooms","RoutingSources"}},
}

local navHidden = {}

-------------------[ Constant Tables ]-------------------

pageUCI = nil
state = {
    activeLayer = kLayer.Start,
    layerStates = {},
    activeRoutingLayer = nil,
    callActive = false,
    isAnimating = false,
    isInitialized = false,
}
components = {
    roomControls = nil, prevPowerState = nil,
    videoSwitcher = nil, switcherType = nil, uciToInputMapping = {},
    passcode = nil, passcodeRoom = nil, passcodeEnabled = false,
}
timers = { loading = nil, timeout = nil, inactivity = Timer.New() }
btnNav = {}
btnRouting = {}
arrUCILegends = {}
arrUCIUserLabels = {}
legendCount = 0

-------------------[ Constants ]-------------------

stateDebug = true
defaultLayer = tonumber(Uci.Variables.numDefaultActiveLayer and Uci.Variables.numDefaultActiveLayer.Value) or 8
defaultRouting = tonumber(Uci.Variables.numDefaultRoutingLayer and Uci.Variables.numDefaultRoutingLayer.Value) or 4
state.activeRoutingLayer = defaultRouting

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

function stopTimer(timer)
    if timer then pcall(function() timer:Stop() end) end
    return nil
end

function debugPrint(str)
    if stateDebug and pageUCI then print("["..pageUCI.."] "..str) end
end

-------------------[ Discovery ]-------------------

function resolvePageName(hint)
    local pages = Uci.GetUciPages()
    if not pages or #pages == 0 then return nil end
    if hint == nil or hint == "" then return pages[1].Name end
    local hintLower = hint:lower()
    for _, page in ipairs(pages) do
        local nameLower = page.Name:lower()
        if nameLower == hintLower or nameLower:find(hintLower, 1, true) or hintLower:find(nameLower, 1, true) then
            return page.Name
        end
    end
    return pages[1].Name
end

function validateLayersAtInit(pageName)
    local inDesign = {}
    for _, layer in ipairs(Uci.GetUciPageLayers(pageName)) do
        inDesign[layer.Name] = true
    end
    local missing = {}
    local function check(name)
        if name and name ~= "" and not inDesign[name] then table.insert(missing, name) end
    end
    for _, name in ipairs(layersBase) do check(name) end
    for _, name in ipairs(layersToHide) do check(name) end
    for _, name in ipairs(routingLayers) do check(name) end
    for _, def in pairs(configSource) do
        check(def.base); check(def.disc); check(def.usb); check(def.conf); check(def.help)
    end
    check("H10-RoomControls")
    if #missing > 0 then
        print("WARNING ["..pageName.."]: configured layers not found in UCI design:")
        for _, name in ipairs(missing) do print("  - "..name) end
    end
end

function validateControls()
    local required = {
        "btnNav01","btnNav02","btnNav03","btnNav04","btnNav05","btnNav06","btnNav07",
        "btnNav08","btnNav09","btnNav10","btnNav11","btnNav12","btnNav13",
        "btnStartSystem","btnNavShutdown","btnShutdownCancel","btnShutdownConfirm",
        "btnRouting01","btnRouting02","btnRouting03","btnRouting04","btnRouting05",
        "knbProgressBar","txtProgressBar",
        "ledCallActive","ledUSBLaptop","ledUSBPC",
        "ledPresetSaved","ledHDMI01Connect","ledHDMI02Connect","ledHDMI03Connect",
        "ledACPRBypassActive",
    }
    local missing = {}
    for _, name in ipairs(required) do
        if not Controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, n in ipairs(missing) do print("  - "..n) end
        return false
    end
    return true
end

-------------------[ Visibility ]-------------------

function loadLayerStatesFromUci()
    state.layerStates = {}
    for _, pages in pairs(Uci.GetLayerVisibility()) do
        for page, layers in pairs(pages) do
            if page == pageUCI then
                for name, vis in pairs(layers) do state.layerStates[name] = vis end
            end
        end
    end
end

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
    loadLayerStatesFromUci()
    for name, wantVis in pairs(desired) do
        if state.layerStates[name] ~= wantVis then
            local trans = (transitions and transitions[name]) or (wantVis and "fade" or "none")
            local ok, err = pcall(Uci.SetLayerVisibility, pageUCI, name, wantVis, trans)
            if ok then state.layerStates[name] = wantVis
            else debugPrint("Layer '"..name.."' error: "..tostring(err)) end
        end
    end
end

function applySourceOverlay(desired, transitions, sourceKey, callActive)
    local def = configSource[sourceKey]
    if not def then return end

    local hdmiPin = Controls[def.hdmiKey]
    local hdmiOk = not hdmiPin or hdmiPin.Boolean

    if hdmiOk then
        want(desired, transitions, def.base, true, "fade")
        want(desired, transitions, def.disc, false)
    else
        want(desired, transitions, def.disc, true, "fade")
        want(desired, transitions, def.base, false)
        want(desired, transitions, "J03-ACPRActive", false)
        if def.conf then want(desired, transitions, def.conf, false) end
        want(desired, transitions, usbConnectLayers, false)
        want(desired, transitions, confLayers, false)
        if def.help then want(desired, transitions, def.help, false) end
        return
    end

    if not conferenceStateConfig.skip[def.layer] then
        local usbPin = def.usbKey and Controls[def.usbKey]
        local usb = usbPin and usbPin.Boolean or false
        if usb then
            if def.conf then want(desired, transitions, def.conf, true, "fade") end
            want(desired, transitions, usbConnectLayers, false)
        elseif def.usb then
            want(desired, transitions, def.usb, true, "fade")
            if def.conf then want(desired, transitions, def.conf, false) end
            if def.help then want(desired, transitions, def.help, false) end
        end
    end

    if not acprConfig.disableACPRShow then
        local bypass = Controls.ledACPRBypassActive and Controls.ledACPRBypassActive.Boolean or false
        if not bypass and callActive then
            want(desired, transitions, "J03-ACPRActive", true, "fade")
            if def.conf then want(desired, transitions, def.conf, false) end
        else
            want(desired, transitions, "J03-ACPRActive", false)
            if def.conf then want(desired, transitions, def.conf, bypass, bypass and "fade" or "none") end
        end
    else
        want(desired, transitions, "J03-ACPRActive", false)
    end

    local hc = helpControls[sourceKey]
    if def.help and hc and hc.open then
        local helpVis = hc.open.Boolean or false
        want(desired, transitions, def.help, helpVis, helpVis and "fade" or "none")
        if helpVis then
            want(desired, transitions, usbConnectLayers, false)
            if def.conf == "J10-ConferencePC" then
                want(desired, transitions, "J10-ConferencePC", false)
            end
        end
    end
end

function buildDesired()
    local desired, transitions = {}, {}
    want(desired, transitions, layersToHide, false)

    local cfg = layerConfigs[state.activeLayer]
    if cfg then
        local baseVis = not cfg.hideBase
        for _, name in ipairs(layersBase) do
            want(desired, transitions, name, baseVis, baseVis and "fade" or "none")
        end
        want(desired, transitions, cfg.show, true, "fade")
        want(desired, transitions, cfg.hide, false)
    end

    state.callActive = Controls.ledCallActive and Controls.ledCallActive.Boolean or false
    want(desired, transitions, "I01-CallActive", state.callActive, state.callActive and "fade" or "none")

    local preset = Controls.ledPresetSaved and Controls.ledPresetSaved.Boolean or false
    want(desired, transitions, "J04-CamPresetSaved", preset, preset and "fade" or "none")

    if state.activeLayer == kLayer.Routing then
        if state.activeRoutingLayer < 1 or state.activeRoutingLayer > #routingLayers then
            state.activeRoutingLayer = 1
        end
        want(desired, transitions, "X01-ProgramVolume", false)
        for i, name in ipairs(routingLayers) do
            local show = i == state.activeRoutingLayer
            want(desired, transitions, name, show, show and "fade" or "none")
        end
        local routingHelp = helpControls.Routing and helpControls.Routing.open and helpControls.Routing.open.Boolean or false
        want(desired, transitions, "I05-HelpRouting", routingHelp, "none")
    end

    if state.activeLayer == kLayer.StreamMusic then
        local musicHelp = helpControls.StreamMusic and helpControls.StreamMusic.open and helpControls.StreamMusic.open.Boolean or false
        want(desired, transitions, "I07-HelpStreamMusic", musicHelp, "none")
    end

    local sourceKey = layerToSourceKey[state.activeLayer]
    if sourceKey then
        if state.activeLayer == kLayer.PC or state.activeLayer == kLayer.Laptop then
            applySourceOverlay(desired, transitions, sourceKey, state.callActive)
        elseif state.activeLayer == kLayer.Wireless then
            local def = configSource.Wireless
            local hc = helpControls.Wireless
            if def.help and hc and hc.open then
                local helpVis = hc.open.Boolean or false
                want(desired, transitions, def.help, helpVis, helpVis and "fade" or "none")
            end
        end
    end

    return desired, transitions
end

function syncHelpButtons()
    for helpLayer, key in pairs(layerHelpToKey) do
        local hc = helpControls[key]
        if hc and hc.open then
            local vis = state.layerStates[helpLayer] == true
            setProp(hc.open, "Boolean", vis)
            setProp(hc.close, "Boolean", false)
        end
    end
end

function refreshLayers()
    applyDesired(buildDesired())
    syncHelpButtons()
end

function interlockNav()
    for i, btn in ipairs(btnNav) do
        if btn then setProp(btn, "Boolean", i == state.activeLayer) end
    end
end

function interlockRouting()
    for i, btn in ipairs(btnRouting) do
        if btn then setProp(btn, "Boolean", i == state.activeRoutingLayer) end
    end
end

-------------------[ Switcher ]-------------------

function initVideoSwitcher()
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

function switchToInput(inputNumber)
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

-------------------[ Navigation ]-------------------

function goToLayer(layerIndex, source)
    source = source or "Navigation"
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    if layerIndex == kLayer.Passcode then resetTouchInactivityTimer() end
    if components.videoSwitcher and components.uciToInputMapping[layerIndex] then
        switchToInput(components.uciToInputMapping[layerIndex])
    end
    refreshLayers()
    interlockNav()
    debugPrint("Layer "..prev.." → "..layerIndex.." (Source: "..source..")")
end

function routingButtonHandler(buttonIndex)
    if buttonIndex < 1 or buttonIndex > #routingLayers then return end
    state.activeRoutingLayer = buttonIndex
    refreshLayers()
    interlockRouting()
    debugPrint("Routing → "..routingLayers[buttonIndex])
end

-------------------[ Room Sync ]-------------------

function extractRoomFromPageName()
    local room = pageUCI:match("^uci%s*(.+)$")
    if room then
        room = room:match("^%s*(.-)%s*$")
        components.passcodeRoom = room
        return room
    end
    return nil
end

function isPasscodeCorrect()
    if not components.passcodeEnabled or not components.passcode then return true end
    if components.passcode["PasscodeCorrect"] then return components.passcode["PasscodeCorrect"].Boolean end
    return true
end

function initPasscode()
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
            startSystem("Passcode Correct")
        end
        debugPrint("Passcode handler registered")
    end
    return true
end

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
        duration = isPoweringOn and (tonumber(Uci.Variables.timeProgressWarming) or 10) or (tonumber(Uci.Variables.timeProgressCooling) or 5)
    end
    local steps, interval, currentStep = 100, duration / 100, 0
    setProp(Controls.knbProgressBar, "Value", isPoweringOn and 0 or 100)
    setProp(Controls.txtProgressBar, "String", (isPoweringOn and 0 or 100).."%")
    timers.loading = Timer.New()
    timers.timeout = Timer.New()
    timers.timeout.EventHandler = function()
        state.isAnimating = false
        timers.loading = stopTimer(timers.loading)
        goToLayer(isPoweringOn and defaultLayer or kLayer.Start, "Loading Timeout")
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
            goToLayer(isPoweringOn and defaultLayer or kLayer.Start, isPoweringOn and "Warmup Complete" or "Cooldown Complete")
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

function resetTouchInactivityTimer()
    if not timers.inactivity then return end
    timers.inactivity:Stop()
    if state.activeLayer ~= kLayer.Passcode then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity.EventHandler = function()
        debugPrint("Touch inactivity → Start (Source: Inactivity Timer)")
        goToLayer(kLayer.Start, "Inactivity Timeout")
    end
    timers.inactivity:Start(timeout)
    debugPrint("Touch inactivity timer reset ("..timeout.."s)")
end

function syncRoomControlsState()
    if not components.roomControls or not components.roomControls["ledSystemPower"] then return end
    local cur = components.roomControls["ledSystemPower"].Boolean
    if cur == components.prevPowerState then return end
    debugPrint("Sync: "..tostring(components.prevPowerState).." → "..tostring(cur))
    components.prevPowerState = cur
    reflectPowerState(cur, "Room Automation Sync")
end

function startSystem(eventSource)
    eventSource = eventSource or "System Start"
    powerOn()
    startLoadingBar(true)
    goToLayer(kLayer.Warming, eventSource)
end

function shutdownSystem()
    powerOff()
    startLoadingBar(false)
    goToLayer(kLayer.Cooling, "System Shutdown")
end

function ensureSystemIsOn(targetLayer)
    targetLayer = targetLayer or defaultLayer
    if components.roomControls and components.roomControls["ledSystemPower"] and components.roomControls["ledSystemPower"].Boolean then
        debugPrint("System already ON → layer "..targetLayer)
        goToLayer(targetLayer, "Source Active")
        return
    end
    if components.passcodeEnabled and not isPasscodeCorrect() then
        debugPrint("Passcode required")
        goToLayer(kLayer.Passcode, "Passcode Required")
        return
    end
    startSystem()
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
        state.activeLayer = defaultLayer
        debugPrint("Synced: READY")
    end
end

-------------------[ Legends ]-------------------

function syncLegends()
    for i = 1, legendCount do
        local lbl = arrUCILegends[i]
        if lbl and arrUCIUserLabels[i] then
            setProp(lbl, "Legend", arrUCIUserLabels[i].String or "")
        end
    end
end

function initLegendArrays()
    local idx = 0
    local missingOptional, missingRequired = 0, 0

    local function registerLegend(name, required)
        idx = idx + 1
        local ctrlName = "txt"..name
        local varName = "txtLabel"..name
        local ctrl = Controls[ctrlName]
        local var = Uci.Variables[varName]
        arrUCILegends[idx] = ctrl
        arrUCIUserLabels[idx] = var
        if not ctrl then
            if required then
                missingRequired = missingRequired + 1
                print("ERROR: Required legend control missing: "..ctrlName)
            else
                missingOptional = missingOptional + 1
                debugPrint("Warning: Legend control not found: "..ctrlName)
            end
        end
        if not var then
            if required then
                missingRequired = missingRequired + 1
                print("ERROR: Required legend variable missing: "..varName)
            else
                missingOptional = missingOptional + 1
                debugPrint("Warning: Legend variable not found: "..varName)
            end
        end
    end

    for _, cfg in ipairs(legendConfig) do
        if cfg.suffix then
            local count = cfg.count or 1
            for i = 1, count do
                local name = cfg.count and (cfg.suffix..string.format("%02d", i)) or cfg.suffix
                registerLegend(name, false)
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do
                registerLegend(name, true)
            end
        end
    end
    legendCount = idx
    for i = 1, legendCount do
        local label = arrUCIUserLabels[i]
        if label then label.EventHandler = function() syncLegends() end end
    end
    debugPrint("Legends: "..legendCount.." slots configured")
    if missingOptional > 0 then debugPrint("Legends: "..missingOptional.." optional control/variable reference(s) missing") end
    if missingRequired > 0 then print("ERROR: Legends: "..missingRequired.." required control/variable reference(s) missing") end
end

-------------------[ Event Handlers ]-------------------

for i, btn in ipairs({
    Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04, Controls.btnNav05,
    Controls.btnNav06, Controls.btnNav07, Controls.btnNav08, Controls.btnNav09, Controls.btnNav10,
    Controls.btnNav11, Controls.btnNav12, Controls.btnNav13
}) do
    btnNav[i] = btn
    ;(function(idx, ctl)
        ctl.EventHandler = function()
            goToLayer(idx, "User Button")
        end
    end)(i, btn)
end

for i, btn in ipairs({
    Controls.btnRouting01, Controls.btnRouting02, Controls.btnRouting03,
    Controls.btnRouting04, Controls.btnRouting05
}) do
    btnRouting[i] = btn
    ;(function(idx, ctl)
        ctl.EventHandler = function()
            routingButtonHandler(idx)
        end
    end)(i, btn)
end

Controls.btnStartSystem.EventHandler = function()
    ensureSystemIsOn(defaultLayer)
end

Controls.btnNavShutdown.EventHandler = function()
    applyDesired({["D01-ShutdownConfirm"] = true}, {["D01-ShutdownConfirm"] = "fade"})
end

Controls.btnShutdownCancel.EventHandler = function()
    applyDesired({["D01-ShutdownConfirm"] = false}, {["D01-ShutdownConfirm"] = "fade"})
end

Controls.btnShutdownConfirm.EventHandler = function()
    shutdownSystem()
end

for _, key in ipairs(configHelpPairKeys) do
    local hc = helpControls[key]
    if hc then
        if hc.open then
            hc.open.EventHandler = function()
                if hc.close then setProp(hc.close, "Boolean", false) end
                refreshLayers()
            end
        end
        if hc.close then
            hc.close.EventHandler = function()
                if hc.open then setProp(hc.open, "Boolean", false) end
                refreshLayers()
            end
        end
    end
end

for _, def in pairs(configSource) do
    local hdmiCtrl = Controls[def.hdmiKey]
    if hdmiCtrl then hdmiCtrl.EventHandler = function() refreshLayers() end end
    if def.usbKey then
        local usbCtrl = Controls[def.usbKey]
        if usbCtrl then
            ;(function(srcDef, ctl)
                ctl.EventHandler = function(pin)
                    if pin.Boolean then ensureSystemIsOn(srcDef.layer) else refreshLayers() end
                end
            end)(def, usbCtrl)
        end
    end
end

Controls.ledACPRBypassActive.EventHandler = function() refreshLayers() end
Controls.ledPresetSaved.EventHandler = function() refreshLayers() end
Controls.ledCallActive.EventHandler = function() refreshLayers() end

if Controls.ledTouchActivity then
    Controls.ledTouchActivity.EventHandler = function()
        resetTouchInactivityTimer()
    end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugPrint("=== Initialization Started ===")

    loadLayerStatesFromUci()
    state.activeLayer = kLayer.Start
    initLegendArrays()
    initRoomControls()
    initVideoSwitcher()
    initPasscode()
    initSyncFromSystemController()

    for _, idx in ipairs(navHidden) do
        local btn = btnNav[idx]
        if btn then btn.Visible = false; debugPrint("Hidden nav: "..idx) end
    end

    refreshLayers()
    interlockNav()
    interlockRouting()
    syncLegends()

    state.isInitialized = true
    debugPrint("=== Initialization Complete ===")
end

-------------------[ Public API ]-------------------

myUCI = {
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
        for i = 1, legendCount do
            local label = arrUCIUserLabels[i]
            if label then label.EventHandler = nil end
        end
        debugPrint("Cleanup complete")
    end,
}

local ok, err = pcall(function()
    if not validateControls() then error("Control validation failed") end
    local hint = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or ""
    pageUCI = resolvePageName(hint)
    if not pageUCI then error("Uci.GetUciPages returned no pages") end
    validateLayersAtInit(pageUCI)
    funcInit()
end)

if ok then
    print("✓ UCIController initialized for "..pageUCI)
else
    print("✗ ERROR: UCIController initialization failed: "..tostring(err))
end
