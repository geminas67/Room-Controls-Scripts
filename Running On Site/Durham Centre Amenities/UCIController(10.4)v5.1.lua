--[[
  UCI Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.1 | Date: 2026-10-24
  Firmware Req: 10.4 (GetLayerVisibility per layer in applyDesired)

  Single-room UCI. buildDesired → applyDesired; event-driven power progress from room controls.

  Popup copy in Lua: helpCopy (title/heading/body per help key), discTextHDMI, discTextUSB.
  Help: one btnHelpOpen (I02-HelpBtn) + one btnHelpClose (I02-Help); copy chosen by the active page's help key
  (layerConfig keySource or keyHelp). I02-Help (txtHelpTitle, txtHelpHeading, txtHelpBody),
  I03-HDMIDisc (txtHDMIDisc), I04-USBDisc (txtUSBDisc).
]]--

-------------------[ Configuration ]-------------------

componentNames = {
    roomControlsPrefix = "compRoomControls", -- fallback when Uci.Variables.compRoomControls is blank: prefix .. page name (no spaces)
    passcodePrefix     = "passcode",         -- prefix .. room name from page "uci <Room>"
}

kLayer = {
    Alarm           = 1,
    IncomingCall    = 2,
    Start           = 3,
    Warming         = 4,
    Cooling         = 5,
    Utilities       = 6,
    PC              = 7,
    Laptop          = 8,
    Passcode        = 9,
}
-- Pages the user reaches with btnNavXX (XX = kLayer index). All other kLayer entries are system states.
navLayers = {
    kLayer.Utilities, kLayer.PC, kLayer.Laptop, 
}

configACPR = { disableACPRShow = false }

layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E05-PowerProgress",
    "H01-PasscodeEntry","H10-Utilities",
    "I01-CallActive","I02-Help","I02-HelpBtn","I03-HDMIDisc", "I04-USBDisc",
    "J03-ACPRActive","J04-CamPresetSaved","J11-Conference01","J12-Conference02",
    "L05-Laptop","P05-PC",
}

-- Keyed by layerConfig keySource / keyHelp. Pages without a key show no help button.
helpCopy = {
    PC          = {
        title   = "Help PC Conferencing",
        heading = "Please make sure the following devices are selected in the PC's conference settings:\n\nCamera: Room PC USB\nSpeaker: Room PC USB\nMicrophone: Room PC USB",
        body    = "Auto Camera Preset Recall (ACPR) is enabled by default when a call is active, keeping the cameras positioned automatically.\n\nDisable it using the ACPR toggle to manually pan, tilt, zoom, or save new presets.\n\n\nUse the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
    Laptop      = {
        title   = "Help Laptop Conferencing",
        heading = "Please make sure the following devices are selected in the Laptop's conference settings:\n\nCamera: Laptop USB\nSpeaker: Laptop USB\nMicrophone: Laptop USB",
        body    = "Use the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
}

discTextHDMI = {
    PC       = "Please connect the HDMI cable to the PC to present to the display",
    Laptop   = "Please connect the HDMI cable to the Laptop to present to the display",
}

discTextUSB = {
    PC       = "Please connect the USB cable to the PC to use the room camera, microphone, and speaker",
    Laptop   = "Please connect the USB cable to the Laptop to use the room camera, microphone, and speaker",
}

-- keyHDMI / keyUSB: connection LEDs + I03-HDMIDisc / I04-USBDisc copy (discTextHDMI / discTextUSB)
configSource = {
    PC = {
        layer = kLayer.PC, keyHDMI = "ledHDMI01", keyUSB = "ledUSB01",
        base = "P05-PC", conf = "J11-Conference01", acpr = true,
    },
    Laptop = {
        layer = kLayer.Laptop, keyHDMI = "ledHDMI02", keyUSB = "ledUSB02",
        base = "L05-Laptop", conf = "J12-Conference02", acpr = false,
    },
}

powerProgressConfig = {
    {
        mode = "warming", key = "ledSystemWarming", timeKey = "warmupTime", timeDefault = 10,
        text = "Starting the AV system, please wait as the system powers on.",
        startSource = "Room Automation Warming", endSource = "Warmup Complete",
    },
    {
        mode = "cooling", key = "ledSystemCooling", timeKey = "cooldownTime", timeDefault = 5,
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
    [kLayer.Utilities]    = { show = {"H10-Utilities"}, hide = {"X01-ProgramVolume"} },
    [kLayer.PC]           = { keySource = "PC" },
    [kLayer.Laptop]       = { keySource = "Laptop" },
    [kLayer.Passcode]     = { show = {"H01-PasscodeEntry"}, hideBase = true },
}

labelConfig = {
    {suffix = "Nav", indices = navLayers},
    {single = {"NavShutdown","RoomNameNav","RoomNameStart","NavTeams"}},
    {suffix = "GainPGM"},
    {suffix = "Gain", count = 10},
    {suffix = "Display", count = 4},
}

-------------------[ Constant Tables ]-------------------

pageUCI = nil
compRoomControls = nil
compPasscode = nil   -- passcode<Room> block; nil = passcode disabled

kLayerName = {}
for name, idx in pairs(kLayer) do kLayerName[idx] = name end

btnNav = {}
for _, idx in ipairs(navLayers) do btnNav[idx] = Controls[string.format("btnNav%02d", idx)] end

layerConf = {}
for _, def in pairs(configSource) do
    if def.conf then table.insert(layerConf, def.conf) end
end

-------------------[ Constants ]-------------------

stateDebug = true
layerDefault = math.floor(tonumber(Uci.Variables.layerDefault and Uci.Variables.layerDefault.Value) or kLayer.PC)

state = {
    activeLayer = kLayer.Start,
    powerProgress = nil,   -- "warming" / "cooling" / nil
    shutdownConfirm = false,
    helpOpen = false,
}

progressStep = 0
timerProgress = Timer.New()
timerInactivity = Timer.New()

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugPrint(str)
    if stateDebug then print("["..(pageUCI or "UCI").."] "..str) end
end

function getComp(name)
    if not name or name == "" then return nil end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then return nil end
    return comp
end

-------------------[ Discovery ]-------------------

function resolvePageName()
    local pages = Uci.GetUciPages()
    return pages and pages[1] and pages[1].Name
end

function validateControls()
    local required = {
        "btnStartSystem","btnNavShutdown","btnShutdownCancel","btnShutdownConfirm",
        "knbProgressBar","txtProgressBar","txtPowerProgress",
        "ledOffHook","ledPresetSaved",
        "ledACPRBypassActive","ledAlarm","ledIncomingCall",
        "btnHelpOpen","btnHelpClose","txtHelpTitle","txtHelpHeading","txtHelpBody","txtHDMIDisc","txtUSBDisc",
    }
    for _, idx in ipairs(navLayers) do table.insert(required, string.format("btnNav%02d", idx)) end
    for key, def in pairs(configSource) do
        if def.keyHDMI then table.insert(required, def.keyHDMI) end
        if def.keyUSB then table.insert(required, def.keyUSB) end
    end
    local missing = {}
    for _, name in ipairs(required) do
        if not Controls[name] then table.insert(missing, name) end
    end
    if not Controls.ledTouchActivity then debugPrint("Warning: Optional control missing: ledTouchActivity") end
    if #missing == 0 then return true end
    print("ERROR: UCIController validation failed - Missing required controls:")
    for _, name in ipairs(missing) do print("  - "..name) end
    return false
end

function validateLayers()
    local pageLayers = Uci.GetUciPageLayers(pageUCI)
    if not pageLayers then
        print("ERROR ["..pageUCI.."]: could not retrieve UCI page layers")
        return false
    end
    local inDesign, missing, order = {}, {}, {}
    for _, layer in ipairs(pageLayers) do inDesign[layer.Name] = true end

    -- Accepts a layer name, a list of names, or nil; collects every location a missing layer is used
    local function note(v, ctx)
        if type(v) == "table" then
            for _, name in ipairs(v) do note(name, ctx) end
        elseif v and v ~= "" and not inDesign[v] then
            if not missing[v] then missing[v] = {}; order[#order + 1] = v end
            table.insert(missing[v], ctx)
        end
    end

    note(layersBase,   "layersBase")
    note(layersToHide, "layersToHide")
    note(layerConf,    "layerConf (help hides all conference layers)")
    for key, def in pairs(configSource) do
        note(def.base, "configSource."..key..".base")
        note(def.usb, "configSource."..key..".usb")
        note(def.conf, "configSource."..key..".conf")
    end
    for idx, cfg in pairs(layerConfig) do
        local ctx = "layerConfig."..(kLayerName[idx] or tostring(idx))
        note(cfg.show, ctx..".show")
        note(cfg.hide, ctx..".hide")
    end

    if #order == 0 then return true end
    print("ERROR ["..pageUCI.."]: configured layers not found in UCI design:")
    for _, name in ipairs(order) do
        print("  - "..name.."  ←  "..table.concat(missing[name], ", "))
    end
    print("  Fix: add the layer in Designer, or remove/nil that field (or whole configSource entry) in the script.")
    return false
end

-------------------[ Visibility ]-------------------

function want(desired, names, visible)
    if not names then return end
    if type(names) ~= "table" then names = {names} end
    for _, name in ipairs(names) do
        if name ~= "" then desired[name] = visible end
    end
end

function applyDesired(desired, force)
    for name, wantVis in pairs(desired) do
        local visOk, current = pcall(Uci.GetLayerVisibility, pageUCI, name)
        if not visOk then
            print("Layer '"..name.."' not on page: "..tostring(current).." (see validateLayers at init)")
        elseif force or current ~= wantVis then
            local ok, err = pcall(Uci.SetLayerVisibility, pageUCI, name, wantVis, wantVis and "fade" or "none")
            if ok then debugPrint("Layer '"..name.."' set to "..tostring(wantVis))
            else print("Layer '"..name.."' error: "..tostring(err)) end
        end
    end
end

function activeSourceKey()
    local cfg = layerConfig[state.activeLayer]
    return cfg and cfg.keySource
end

function hdmiConnected(keySource)
    return Controls[configSource[keySource].keyHDMI].Boolean
end

function usbConnected(keySource)
    local def = configSource[keySource]
    return def.keyUSB and Controls[def.keyUSB].Boolean
end

-- Help is evaluated by the page that owns it: closed → I02-HelpBtn, open → I02-Help with that key's copy.
function applyHelp(desired, keyHelp, isSource)
    local copy = helpCopy[keyHelp]
    if not copy then return end
    if not state.helpOpen then
        want(desired, "I02-HelpBtn", true)
        return
    end
    want(desired, "I02-Help", true)
    Controls.txtHelpTitle.String   = copy.title or ""
    Controls.txtHelpHeading.String = copy.heading or ""
    Controls.txtHelpBody.String    = copy.body or ""
    if isSource then
        want(desired, layerConf, false)
        want(desired, {"I03-HDMIDisc", "I04-USBDisc"}, false)
    end
end

function applySourceOverlay(desired, keySource)
    local def = configSource[keySource]
    if not hdmiConnected(keySource) then
        want(desired, "I03-HDMIDisc", true)
        Controls.txtHDMIDisc.String = discTextHDMI[keySource] or ""
        return
    end

    want(desired, def.base, true)
    want(desired, def.conf, true)

    if def.keyUSB and not usbConnected(keySource) then
        want(desired, "I04-USBDisc", true)
        Controls.txtUSBDisc.String = discTextUSB[keySource] or ""
    end

    -- ACPR active: on a call and not bypassed
    if def.acpr and not configACPR.disableACPRShow
        and not Controls.ledACPRBypassActive.Boolean and Controls.ledOffHook.Boolean then
        want(desired, "J03-ACPRActive", true)
    end

    applyHelp(desired, keySource, true) -- last: open help hides conf/USB
end

function buildDesired()
    local desired = {}
    want(desired, layersToHide, false)

    local cfg = layerConfig[state.activeLayer]
    if cfg then
        want(desired, layersBase, not cfg.hideBase)
        want(desired, cfg.show, true)
        want(desired, cfg.hide, false)
    end

    want(desired, "I01-CallActive", Controls.ledOffHook.Boolean)
    want(desired, "J04-CamPresetSaved", Controls.ledPresetSaved.Boolean)
    want(desired, "D01-ShutdownConfirm", state.shutdownConfirm)

    local keySource = activeSourceKey()
    if keySource then
        applySourceOverlay(desired, keySource)
    elseif cfg and cfg.keyHelp then
        applyHelp(desired, cfg.keyHelp, false)
    end
    return desired
end

function refreshLayers(force)
    applyDesired(buildDesired(), force)
end

function setHelpOpen(isOpen)
    state.helpOpen = isOpen
    debugPrint("Help → "..(isOpen and "open" or "closed").." ("..tostring(kLayerName[state.activeLayer])..")")
    refreshLayers()
end

-------------------[ Navigation ]-------------------

function interlockNav()
    for idx, btn in pairs(btnNav) do btn.Boolean = (idx == state.activeLayer) end
end

function goToLayer(layerIndex, source)
    source = source or "Navigation"
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    state.shutdownConfirm = false
    state.helpOpen = false
    if layerIndex == kLayer.Passcode then resetTouchInactivityTimer() end
    refreshLayers()
    interlockNav()
    debugPrint("Layer "..(kLayerName[prev] or prev).." → "..(kLayerName[layerIndex] or layerIndex).." (Source: "..source..")")
end

function resetTouchInactivityTimer()
    timerInactivity:Stop()
    if state.activeLayer ~= kLayer.Passcode then return end
    local timeout = tonumber(Uci.Variables.timeTouchInactivity and Uci.Variables.timeTouchInactivity.Value) or 60
    timerInactivity:Start(timeout > 0 and timeout or 60)
end

function onTouchInactivityTimeout()
    timerInactivity:Stop()
    if state.activeLayer ~= kLayer.Passcode then return end
    goToLayer(kLayer.Start, "Inactivity Timeout")
end

-------------------[ Power Progress ]-------------------

function updateProgressBar(percent)
    Controls.knbProgressBar.Value = percent
    Controls.txtProgressBar.String = percent.."%"
end

function onProgressTick()
    progressStep = progressStep + 1
    updateProgressBar(state.powerProgress == "warming" and progressStep or (100 - progressStep))
    if progressStep >= 100 then timerProgress:Stop() end
end

function onPowerProgress(cfg, active, source)
    local isWarming = (cfg.mode == "warming")
    timerProgress:Stop()

    if not active then
        if state.powerProgress ~= cfg.mode then return end
        state.powerProgress = nil
        updateProgressBar(isWarming and 100 or 0)
        goToLayer(isWarming and layerDefault or kLayer.Start, source)
        return
    end

    state.powerProgress = cfg.mode
    Controls.txtPowerProgress.String = cfg.text
    updateProgressBar(isWarming and 0 or 100)
    goToLayer(isWarming and kLayer.Warming or kLayer.Cooling, source)

    local timeCtl = compRoomControls and compRoomControls[cfg.timeKey]
    local duration = math.max(1, math.min(120, tonumber(timeCtl and timeCtl.Value) or cfg.timeDefault))
    progressStep = 0
    timerProgress:Start(duration / 100)
    debugPrint("Power progress started ("..cfg.mode..", "..duration.."s visual)")
end

-------------------[ Room Controls ]-------------------

function setSystemPower(isOn, source)
    local btn = compRoomControls and compRoomControls["btnSystemOnOff"]
    if not btn then
        print("ERROR: Power "..(isOn and "on" or "off").." refused — room controls / btnSystemOnOff unavailable")
        return
    end
    btn.Boolean = isOn
    debugPrint("Room → "..(isOn and "ON" or "OFF").." ("..source..")")
end

function isPasscodeCorrect()
    local ctl = compPasscode and compPasscode["PasscodeCorrect"]
    return not ctl or ctl.Boolean
end

function ensureSystemIsOn(targetLayer)
    local power = compRoomControls and compRoomControls["ledSystemPower"]
    if power and power.Boolean then
        goToLayer(targetLayer or layerDefault, "Source Active")
        return
    end
    if not isPasscodeCorrect() then
        goToLayer(kLayer.Passcode, "Passcode Required")
        return
    end
    setSystemPower(true, "System Start")
end

function initRoomControls()
    local name = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String
    if not name or name == "" then
        local page = pageUCI:match("uci%s+([^(]+)")
        name = page and (componentNames.roomControlsPrefix..page:gsub("%s+", ""))
    end
    compRoomControls = getComp(name)
    if not compRoomControls then
        print("ERROR: Room Controls not found: "..tostring(name))
        return false
    end

    for _, cfg in ipairs(powerProgressConfig) do
        local led = compRoomControls[cfg.key]
        if led then
            led.EventHandler = function(ctl)
                onPowerProgress(cfg, ctl.Boolean, ctl.Boolean and cfg.startSource or cfg.endSource)
            end
        end
    end
    return true
end

function initPasscode()
    local room = pageUCI:match("^uci%s*(.-)%s*$")
    local name = room and room ~= "" and (componentNames.passcodePrefix..room)
    compPasscode = getComp(name)
    if not compPasscode then
        debugPrint("Passcode not found: "..tostring(name).." (disabled)")
        return
    end
    local ctl = compPasscode["PasscodeCorrect"]
    if not ctl then return end
    ctl.EventHandler = function(c)
        if c.Boolean then setSystemPower(true, "Passcode Correct") end
    end
end

function initSyncFromRoomControls()
    if not compRoomControls then return end
    for _, cfg in ipairs(powerProgressConfig) do
        local led = compRoomControls[cfg.key]
        if led and led.Boolean then
            onPowerProgress(cfg, true, "Init Sync")
            return
        end
    end
    local power = compRoomControls["ledSystemPower"]
    if power and power.Boolean then goToLayer(layerDefault, "Init Sync Ready") end
end

-------------------[ Legends ]-------------------

function initLabels()
    local count, missing = 0, 0
    local function registerLegend(name, required)
        local key = "txt"..name
        local ctrl, var = Controls[key], Uci.Variables[key]
        count = count + 1
        if ctrl and var then
            ctrl.String = var.String or ""
            var.EventHandler = function() ctrl.String = var.String or "" end
        elseif required then
            print("ERROR: Required legend "..(ctrl and "variable" or "control").." missing: "..key)
        else
            missing = missing + 1
        end
    end

    for _, cfg in ipairs(labelConfig) do
        if cfg.single then
            for _, name in ipairs(cfg.single) do registerLegend(name, true) end
        elseif cfg.indices then
            for _, i in ipairs(cfg.indices) do registerLegend(cfg.suffix..string.format("%02d", i), false) end
        elseif cfg.count then
            for i = 1, cfg.count do registerLegend(cfg.suffix..string.format("%02d", i), false) end
        else
            registerLegend(cfg.suffix, false)
        end
    end
    debugPrint("Legends: "..count.." slots, "..missing.." optional missing")
end

-------------------[ Event Handlers ]-------------------

if not validateControls() then error("UCIController: missing required controls (see list above)") end

for idx, btn in pairs(btnNav) do
    btn.EventHandler = function() goToLayer(idx, "btnNav") end
end

Controls.btnStartSystem.EventHandler = function() ensureSystemIsOn(layerDefault) end

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
    setSystemPower(false, "Shutdown Confirm button")
end

Controls.btnHelpOpen.EventHandler = function() setHelpOpen(true) end
Controls.btnHelpClose.EventHandler = function() setHelpOpen(false) end

for _, def in pairs(configSource) do
    Controls[def.keyHDMI].EventHandler = function() refreshLayers() end
    if def.keyUSB then Controls[def.keyUSB].EventHandler = function() refreshLayers() end end
end

Controls.ledOffHook.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(layerDefault) else refreshLayers() end
end

for _, name in ipairs({"ledACPRBypassActive", "ledPresetSaved", "ledAlarm", "ledIncomingCall"}) do
    Controls[name].EventHandler = function() refreshLayers() end
end

if Controls.ledTouchActivity then
    Controls.ledTouchActivity.EventHandler = function() resetTouchInactivityTimer() end
end

timerProgress.EventHandler = onProgressTick
timerInactivity.EventHandler = onTouchInactivityTimeout

-------------------[ Always Run ]-------------------

function funcInit()
    pageUCI = resolvePageName()
    if not pageUCI then
        print("✗ ERROR: UCIController initialization failed: Uci.GetUciPages returned no pages")
        return
    end
    debugPrint("=== Initialization Started ===")
    if not validateLayers() then error("UCIController: layer validation failed (see list above)") end
    initLabels()
    if not initRoomControls() then print("ERROR: Room controls unavailable — power actions disabled") end
    initPasscode()
    initSyncFromRoomControls()
    refreshLayers(true) -- force full push; GetLayerVisibility may be stale after a Core reboot
    interlockNav()
    print("✓ UCIController initialized for "..pageUCI)
end

funcInit()
