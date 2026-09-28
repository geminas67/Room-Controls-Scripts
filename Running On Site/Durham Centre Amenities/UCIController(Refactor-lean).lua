--[[
  UCI Controller (Lean) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.2 | Date: 2026-09-26
  Firmware Req: 10.4 compatible (GetUciPages / GetUciPageLayers / GetLayerVisibility)

  Flat single-room UCI: configSource, declarative visibility (buildDesired/applyDesired),
  event-driven power sync, switcher auto-detect. Three engines — visibility, room sync, switcher.
]]--

-------------------[ Configuration ]-------------------

conferenceStateConfig = { skip = {} }
acprConfig = { disableACPRShow = false }

layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E05-PowerProgress",
    "H01-PasscodeEntry","H10-RoomControls",
    "I01-CallActive","I02-HelpLaptop","I03-HelpPC",
    "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J09-ConferenceLaptop","J10-ConferencePC",
    "L01-HDMIDisc","L05-Laptop","P01-HDMIDisc","P05-PC",
}
usbConnectLayer = {"J01-ConnectUSBLaptop","J02-ConnectUSBPC"}
confLayer = {"J09-ConferenceLaptop","J10-ConferencePC"}

kLayer = {
    Alarm           = 1,
    IncomingCall    = 2,
    Start           = 3,
    Warming         = 4,
    Cooling         = 5,
    RoomControls    = 6,
    PC              = 7,
    Laptop          = 8,
    Passcode        = 9
}
kLayerName = {}
for name, idx in pairs(kLayer) do kLayerName[idx] = name end

configSource = {
    PC = {
        layer   = kLayer.PC,
        hdmiKey = "ledHDMI01Connect",
        usbKey  = "ledUSBPC",
        base    = "P05-PC",
        disc    = "P01-HDMIDisc",
        usb     = "J02-ConnectUSBPC",
        conf    = "J10-ConferencePC",
        help    = "I03-HelpPC",
        acpr    = true,
    },
    Laptop = {
        layer   = kLayer.Laptop,
        hdmiKey = "ledHDMI02Connect",
        usbKey  = "ledUSBLaptop",
        base    = "L05-Laptop",
        disc    = "L01-HDMIDisc",
        usb     = "J01-ConnectUSBLaptop",
        conf    = "J09-ConferenceLaptop",
        help    = "I02-HelpLaptop",
        acpr    = true,
    },
}

layerToSourceKey = { [kLayer.PC] ="PC", [kLayer.Laptop]="Laptop" }
configHelpPairKey = {"Laptop","PC"}
helpControl = {
    Laptop = { open = Controls.btnHelpOpenLaptop, close = Controls.btnHelpCloseLaptop },
    PC     = { open = Controls.btnHelpOpenPC,     close = Controls.btnHelpClosePC },
}

powerProgressConfig = {
    {
        mode = "warming", key = "ledSystemWarming",
        text = "Starting the AV system, please wait as the system powers on.",
        startSource = "Room Automation Warming", endSource = "Warmup Complete",
    },
    {
        mode = "cooling", key = "ledSystemCooling",
        text = "Shutting down the AV system, please wait as the system powers off.",
        startSource = "Room Automation Cooling", endSource = "Cooldown Complete",
    },
}

layerConfig = {
    [kLayer.Alarm]        = { show = {"A01-Alarm"}, hideBase = true },
    [kLayer.IncomingCall] = { show = {"B01-IncomingCall"} },
    [kLayer.Start]        = { show = {"C05-Start"}, hideBase = true },
    [kLayer.Warming]      = { show = {"E05-PowerProgress"}, hideBase = true },
    [kLayer.Cooling]      = { show = {"E05-PowerProgress"}, hideBase = true },
    [kLayer.RoomControls] = { show = {"H10-RoomControls"}, hide = {"X01-ProgramVolume"} },
    [kLayer.Laptop]       = { show = {"L05-Laptop"} },
    [kLayer.PC]           = { show = {"P05-PC"} },
    [kLayer.Passcode]     = { show = {"H01-PasscodeEntry"}, hideBase = true },
}

labelConfig = {
    {suffix = "Nav",     count = 9},
    --{suffix = "VidSrc",  count = 12},
    {suffix = "GainPGM"},
    {suffix = "Gain",    count = 10},
    {suffix = "Display", count = 4},
    {single = {"NavShutdown","RoomNameNav","RoomNameStart", "NavTeams"}},
}

btnNav = {
    Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04,
    Controls.btnNav05, Controls.btnNav06, Controls.btnNav07, Controls.btnNav08,
    Controls.btnNav09,
}

-------------------[ Constant Tables ]-------------------

pageUCI = nil
state = {
    activeLayer = kLayer.Start,
    powerProgress = nil,
    shutdownConfirm = false,
    isInitialized = false,
    helpOpen = {},
}
component = {
    roomControls = nil,
    passcode = nil, passcodeRoom = nil, passcodeEnabled = false,
}
timer = { progress = nil, inactivity = Timer.New() }
uciLabels = {}
uciVariables = {}
labelCount = 0

-------------------[ Constants ]-------------------

stateDebug = true
defaultLayer = math.floor(tonumber(Uci.Variables.numDefaultActiveLayer and Uci.Variables.numDefaultActiveLayer.Value) or 7)

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
        if btn then
            btn.EventHandler = function() handler(i, btn) end
        end
    end
end

-------------------[ Discovery ]-------------------

function resolvePageName(hint)
    local pages = Uci.GetUciPages()
    if not pages or #pages == 0 then return nil end
    if hint and hint ~= "" then
        local h = hint:lower()
        for _, page in ipairs(pages) do
            if page.Name:lower() == h then return page.Name end
        end
    end
    return pages[1].Name
end

function validateControls()
    local required = {
        "btnNav01","btnNav02","btnNav03","btnNav04","btnNav05","btnNav06","btnNav07",
        "btnNav08","btnNav09",
        "btnStartSystem","btnNavShutdown","btnShutdownCancel","btnShutdownConfirm",
        "knbProgressBar","txtProgressBar","txtPowerProgress",
        "ledCallActive","ledOffHook","ledUSBLaptop","ledUSBPC",
        "ledPresetSaved","ledHDMI01Connect","ledHDMI02Connect",
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

function validateLayers(pageName)
    local pageLayers = Uci.GetUciPageLayers(pageName)
    if not pageLayers then
        print("ERROR: Could not retrieve layers for page '"..pageName.."'")
        return false
    end
    local inDesign = {}
    for _, layer in ipairs(pageLayers) do inDesign[layer.Name] = true end

    local missing = {}
    local seen = {}
    local function check(name)
        if not name or name == "" or seen[name] then return end
        seen[name] = true
        if not inDesign[name] then table.insert(missing, name) end
    end
    local function checkList(list)
        if not list then return end
        if type(list) == "string" then check(list); return end
        for _, name in ipairs(list) do check(name) end
    end

    checkList(layersBase)
    checkList(layersToHide)
    checkList(routingLayer)
    checkList(usbConnectLayer)
    checkList(confLayer)
    for _, cfg in pairs(layerConfig) do
        checkList(cfg.show)
        checkList(cfg.hide)
    end
    if overlayConfig then
        for _, cfg in pairs(overlayConfig) do check(cfg.layer) end
    end
    for _, def in pairs(configSource) do
        check(def.base); check(def.disc); check(def.usb); check(def.conf); check(def.help)
    end

    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing layers on page '"..pageName.."':")
        for _, name in ipairs(missing) do print("  - "..name) end
        return false
    end
    return true
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
    for name, wantVis in pairs(desired) do
        local current = Uci.GetLayerVisibility(pageUCI, name)
        if current ~= wantVis then
            local trans = wantVis and ((transitions and transitions[name]) or "fade") or "none"
            local ok, err = pcall(Uci.SetLayerVisibility, pageUCI, name, wantVis, trans)
            if ok then debugPrint("Layer '"..name.."' set to "..tostring(wantVis))
            else debugPrint("Layer '"..name.."' error: "..tostring(err)) end
        end
    end
end

function applyHelpOverlay(desired, transitions, layerName, helpKey, onShow)
    local helpVis = state.helpOpen[helpKey] or false
    want(desired, transitions, layerName, helpVis, helpVis and "fade" or "none")
    if helpVis and onShow then onShow() end
end

function hdmiConnected(sourceKey)
    local def = configSource[sourceKey]
    if not def or not def.hdmiKey then return true end
    local pin = Controls[def.hdmiKey]
    return not pin or pin.Boolean
end

function applySourceOverlay(desired, transitions, sourceKey)
    local def = configSource[sourceKey]
    if not def then return end

    if not hdmiConnected(sourceKey) then
        want(desired, transitions, def.disc, true, "fade")
        want(desired, transitions, def.base, false)
        return
    end

    want(desired, transitions, def.base, true, "fade")

    if not conferenceStateConfig.skip[def.layer] then
        want(desired, transitions, def.conf, true, "fade")
        local usb = boolOf(def.usbKey and Controls[def.usbKey])
        if not usb and def.usb then
            want(desired, transitions, def.usb, true, "fade")
        end
    end
    
    if def.acpr and not acprConfig.disableACPRShow then
        local bypass = boolOf(Controls.ledACPRBypassActive)
        local offHook = boolOf(Controls.ledOffHook)
        if not bypass and offHook then
            want(desired, transitions, "J03-ACPRActive", true, "fade")
        end
    end

    if def.help then
        applyHelpOverlay(desired, transitions, def.help, sourceKey, function()
            want(desired, transitions, confLayer, false)
            want(desired, transitions, usbConnectLayer, false)
        end)
    end
end

function setHelpOpen(key, isOpen)
    state.helpOpen[key] = isOpen
    refreshLayers()
end

function buildDesired()
    local desired, transitions = {}, {}
    want(desired, transitions, layersToHide, false)

    local cfg = layerConfig[state.activeLayer]
    if cfg then
        local baseVis = not cfg.hideBase
        for _, name in ipairs(layersBase) do
            want(desired, transitions, name, baseVis, baseVis and "fade" or "none")
        end
        want(desired, transitions, cfg.show, true, "fade")
        want(desired, transitions, cfg.hide, false)
    end

    local callActive = boolOf(Controls.ledCallActive)
    want(desired, transitions, "I01-CallActive", callActive, callActive and "fade" or "none")

    local preset = boolOf(Controls.ledPresetSaved)
    want(desired, transitions, "J04-CamPresetSaved", preset, preset and "fade" or "none")

    want(desired, transitions, "D01-ShutdownConfirm", state.shutdownConfirm, state.shutdownConfirm and "fade" or "none")

    local sourceKey = layerToSourceKey[state.activeLayer]
    if sourceKey then
        applySourceOverlay(desired, transitions, sourceKey)
    end

    return desired, transitions
end

function refreshLayers()
    local desired, transitions = buildDesired()
    applyDesired(desired, transitions)
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
    state.shutdownConfirm = false
    if layerIndex == kLayer.Passcode then resetTouchInactivityTimer() end
    refreshLayers()
    interlockNav()
    debugPrint("Layer "..(kLayerName[prev] or prev).." → "..(kLayerName[layerIndex] or layerIndex).." (Source: "..source..")")
end
-------------------[ Room Sync ]-------------------

function extractRoomFromPageName()
    local room = pageUCI:match("^uci%s*(.+)$")
    if room then
        room = room:match("^%s*(.-)%s*$")
        component.passcodeRoom = room
        return room
    end
    return nil
end

function isPasscodeCorrect()
    if not component.passcodeEnabled or not component.passcode then return true end
    if component.passcode["PasscodeCorrect"] then return component.passcode["PasscodeCorrect"].Boolean end
    return true
end

function initPasscode()
    if not extractRoomFromPageName() then return false end
    local compName = "passcode"..component.passcodeRoom
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then
        debugPrint("Passcode not found: "..compName.." (disabled)")
        return false
    end
    component.passcode = comp
    component.passcodeEnabled = true
    if comp["PasscodeCorrect"] then
        comp["PasscodeCorrect"].EventHandler = function(ctl)
            if not ctl.Boolean then return end
            debugPrint("Passcode correct → "..component.passcodeRoom.." (Source: PasscodeCorrect)")
            requestPowerOn("Passcode Correct")
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
        print("ERROR: Room Controls: could not determine component name")
        debugPrint("Room Controls: could not determine component")
        return false
    end
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then
        print("ERROR: Room Controls not found: "..compName)
        debugPrint("Room Controls not found: "..compName)
        return false
    end
    component.roomControls = comp
    for _, cfg in ipairs(powerProgressConfig) do
        if comp[cfg.key] then
            comp[cfg.key].EventHandler = function(ctl)
                onPowerProgress(cfg, ctl.Boolean, ctl.Boolean and cfg.startSource or cfg.endSource)
            end
            debugPrint("Registered: "..cfg.key)
        end
    end
    return true
end

function powerOn()
    if not component.roomControls or not component.roomControls["btnSystemOnOff"] then return false end
    component.roomControls["btnSystemOnOff"].Boolean = true
    debugPrint("Room → ON")
    return true
end

function powerOff()
    if not component.roomControls or not component.roomControls["btnSystemOnOff"] then return false end
    component.roomControls["btnSystemOnOff"].Boolean = false
    debugPrint("Room → OFF")
    return true
end

-------------------[ Power Progress ]-------------------

function updateProgressBar(percent)
    setProp(Controls.knbProgressBar, "Value", percent)
    setProp(Controls.txtProgressBar, "String", percent.."%")
end

function onPowerProgress(cfg, active, source)
    local mode = cfg.mode
    timer.progress = stopTimer(timer.progress)
    if not active then
        if state.powerProgress ~= mode then return end
        state.powerProgress = nil
        updateProgressBar(mode == "warming" and 100 or 0)
        goToLayer(mode == "warming" and defaultLayer or kLayer.Start, source)
        return
    end
    state.powerProgress = mode
    setProp(Controls.txtPowerProgress, "String", cfg.text)
    updateProgressBar(mode == "warming" and 0 or 100)
    goToLayer(mode == "warming" and kLayer.Warming or kLayer.Cooling, source)
    local default = mode == "warming" and 10 or 5
    local timeKey = mode == "warming" and "warmupTime" or "cooldownTime"
    local ctrl = component.roomControls and component.roomControls[timeKey]
    local duration = tonumber(ctrl and ctrl.Value) or default
    if duration < 1 then duration = 1 elseif duration > 120 then duration = 120 end
    local steps, interval, currentStep = 100, duration / 100, 0
    timer.progress = Timer.New()
    timer.progress.EventHandler = function()
        currentStep = currentStep + 1
        updateProgressBar(mode == "warming" and currentStep or (100 - currentStep))
        if currentStep >= steps then
            timer.progress = stopTimer(timer.progress)
        else
            timer.progress:Start(interval)
        end
    end
    timer.progress:Start(interval)
    debugPrint("Power progress started ("..mode..", "..duration.."s visual)")
end

function requestPowerOn(source)
    source = source or "System Start"
    if not component.roomControls then
        print("ERROR: Power on refused — room controls not connected")
        return
    end
    if powerOn() then
        debugPrint("Power on requested ("..source..")")
    else
        print("ERROR: Power on failed — btnSystemOnOff unavailable")
    end
end

function requestPowerOff(source)
    source = source or "System Shutdown"
    if not component.roomControls then
        print("ERROR: Power off refused — room controls not connected")
        return
    end
    if powerOff() then
        debugPrint("Power off requested ("..source..")")
    else
        print("ERROR: Power off failed — btnSystemOnOff unavailable")
    end
end

function resetTouchInactivityTimer()
    if not timer.inactivity then return end
    timer.inactivity:Stop()
    if state.activeLayer ~= kLayer.Passcode then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timer.inactivity.EventHandler = function()
        debugPrint("Touch inactivity → Start (Source: Inactivity Timer)")
        goToLayer(kLayer.Start, "Inactivity Timeout")
    end
    timer.inactivity:Start(timeout)
    debugPrint("Touch inactivity timer reset ("..timeout.."s)")
end

function ensureSystemIsOn(targetLayer)
    targetLayer = targetLayer or defaultLayer
    if component.roomControls and component.roomControls["ledSystemPower"] and component.roomControls["ledSystemPower"].Boolean then
        debugPrint("System already ON → layer "..(kLayerName[targetLayer] or targetLayer))
        goToLayer(targetLayer, "Source Active")
        return
    end
    if component.passcodeEnabled and not isPasscodeCorrect() then
        debugPrint("Passcode required")
        goToLayer(kLayer.Passcode, "Passcode Required")
        return
    end
    requestPowerOn()
end

function initSyncFromSystemController()
    if not component.roomControls then return end
    for _, cfg in ipairs(powerProgressConfig) do
        local led = component.roomControls[cfg.key]
        if led and led.Boolean then
            onPowerProgress(cfg, true, "Init Sync")
            debugPrint("Synced: "..string.upper(cfg.mode))
            return
        end
    end
    local power = component.roomControls["ledSystemPower"]
    if power and power.Boolean then
        goToLayer(defaultLayer, "Init Sync Ready")
        debugPrint("Synced: READY")
    end
end

-------------------[ Legends ]-------------------

function syncLabels()
    for i = 1, labelCount do
        local lbl = uciLabels[i]
        if lbl and uciVariables[i] then
            setProp(lbl, "String", uciVariables[i].String or "")
        end
    end
end

function initLabelArrays()
    local idx = 0
    local missingOptional, missingRequired = 0, 0

    local function reportMissing(kind, name, required)
        if required then
            missingRequired = missingRequired + 1
            print("ERROR: Required legend " .. kind .. " missing: " .. name)
        else
            missingOptional = missingOptional + 1
            debugPrint("Warning: Legend " .. kind .. " not found: " .. name)
        end
    end

    local function registerLegend(name, required)
        idx = idx + 1

        local ctrlName = "txt" .. name
        local varName  = "txtLabel" .. name
        local ctrl     = Controls[ctrlName]
        local var      = Uci.Variables[varName]

        uciLabels[idx] = ctrl
        uciVariables[idx] = var

        if not ctrl then reportMissing("control", ctrlName, required) end
        if not var then reportMissing("variable", varName, required) end

        if ctrl and var then
            var.EventHandler = function()
                setProp(ctrl, "String", var.String or "")
            end
        end
    end
    for _, cfg in ipairs(labelConfig) do
        if cfg.suffix then
            if cfg.count then
                for i = 1, cfg.count do
                    registerLegend(cfg.suffix .. string.format("%02d", i), false)
                end
            else
                registerLegend(cfg.suffix, false)
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do
                registerLegend(name, true)
            end
        end
    end
    labelCount = idx
    syncLabels()
    debugPrint("String Labels: " .. labelCount .. " slots configured")
    if missingOptional > 0 then debugPrint("String Labels: " .. missingOptional .. " optional control/variable reference(s) missing") end
    if missingRequired > 0 then print("ERROR: String Labels: " .. missingRequired .. " required control/variable reference(s) missing") end
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
    state.shutdownConfirm = false
    requestPowerOff("System Shutdown")
end

for _, key in ipairs(configHelpPairKey) do
    local hc = helpControl[key]
    if hc then
        if hc.open then hc.open.EventHandler = function() setHelpOpen(key, true) end end
        if hc.close then hc.close.EventHandler = function() setHelpOpen(key, false) end end
    end
end

for _, def in pairs(configSource) do
    local hdmiCtrl = Controls[def.hdmiKey]
    if hdmiCtrl then hdmiCtrl.EventHandler = function() refreshLayers() end end
    -- USB: refresh only (show/hide J01/J02 connect overlays via applySourceOverlay).
    -- Removed auto-wake / source layer on plug-in — restore on other sites with:
    --   ctl.EventHandler = function(pin)
    --       if pin.Boolean then ensureSystemIsOn(srcDef.layer) else refreshLayers() end
    --   end
    -- (use IIFE to capture srcDef, ctl: ;(function(srcDef, ctl) ... end)(def, usbCtrl))
    if def.usbKey then
        local usbCtrl = Controls[def.usbKey]
        if usbCtrl then usbCtrl.EventHandler = function() refreshLayers() end end
    end
end

Controls.ledACPRBypassActive.EventHandler = function() refreshLayers() end
Controls.ledPresetSaved.EventHandler = function() refreshLayers() end
Controls.ledCallActive.EventHandler = function() refreshLayers() end
Controls.ledOffHook.EventHandler = function() refreshLayers() end
if Controls.ledTouchActivity then
    Controls.ledTouchActivity.EventHandler = function()
        resetTouchInactivityTimer()
    end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugPrint("=== Initialization Started ===")

    state.activeLayer = kLayer.Start
    initLabelArrays()
    if not initRoomControls() then
        print("ERROR: Room controls unavailable — power actions disabled")
    end
    initPasscode()
    initSyncFromSystemController()

    refreshLayers()
    interlockNav()
    syncLabels()

    state.isInitialized = true
    debugPrint("=== Initialization Complete ===")
end

-------------------[ Public API ]-------------------

myUCI = {
    cleanup = function()
        timer.progress = stopTimer(timer.progress)
        if timer.inactivity then timer.inactivity:Stop() end
        if component.roomControls then
            for _, cfg in ipairs(powerProgressConfig) do
                if component.roomControls[cfg.key] then
                    component.roomControls[cfg.key].EventHandler = nil
                end
            end
        end
        if component.passcode and component.passcode["PasscodeCorrect"] then
            component.passcode["PasscodeCorrect"].EventHandler = nil
        end
        for i = 1, labelCount do
            local label = uciVariables[i]
            if label then label.EventHandler = nil end
        end
        debugPrint("Cleanup complete")
    end,
}

hint = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or ""
pageUCI = resolvePageName(hint)

if not pageUCI then
    print("ERROR: UCIController could not discover any UCI pages")
else
    local ok, err = pcall(function()
        if not validateControls() then error("Control validation failed") end
        if not validateLayers(pageUCI) then error("Layer validation failed") end
        funcInit()
    end)
    if ok then
        print("✓ UCIController initialized for "..pageUCI)
    else
        print("✗ ERROR: UCIController initialization failed: "..tostring(err))
    end
end
