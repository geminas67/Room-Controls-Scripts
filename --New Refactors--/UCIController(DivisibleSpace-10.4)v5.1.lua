--[[
  UCI Controller (DivisibleSpace) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.1 | Date: 2026-10-24
  Firmware Req: 10.4 (GetLayerVisibility per layer in applyDesired)

  Divisible-space UCI. buildDesired → applyDesired; event-driven power progress from room controls.

  Popup copy in Lua: helpCopy (title/heading/body per help key), discTextHDMI, discTextUSB, legendStart.
  Help: one btnHelpOpen (I02-HelpBtn) + one btnHelpClose (I02-Help); copy chosen by the active page's help key
  (layerConfig keySource or keyHelp). I02-Help (txtHelpTitle, txtHelpHeading, txtHelpBody),
  I03-HDMIDisc (txtHDMIDisc), I04-USBDisc (txtUSBDisc).
]]--

-------------------[ Configuration ]-------------------

componentNames = {
    divisibleSpace     = "compDivisibleSpaceControls",
    roomControlsPrefix = "compRoomControls", -- fallback when Uci.Variables.compRoomControls is blank: prefix .. page name (no spaces)
}

kLayer = {
    Alarm           = 1,
    IncomingCall    = 2,
    Start           = 3,
    Warming         = 4,
    Cooling         = 5,
    Utilities       = 6,
    PCA             = 7,
    PCB             = 8,
    LaptopA         = 9,
    LaptopB         = 10,
    WirelessA       = 11,
    WirelessB       = 12,
    Routing         = 13,
    Dialer          = 14,
    StreamMusic     = 15,
    RoomCombining   = 16,
    Passcode        = 17,
}
-- Pages the user reaches with btnNavXX (XX = kLayer index). All other kLayer entries are system states.
navLayers = {
    kLayer.Utilities, kLayer.PCA, kLayer.PCB, kLayer.LaptopA, kLayer.LaptopB, kLayer.WirelessA, kLayer.WirelessB,
    kLayer.Routing, kLayer.Dialer, kLayer.StreamMusic, kLayer.RoomCombining,
}

configSkip = { skip = { [kLayer.LaptopA] = true, [kLayer.LaptopB] = true, [kLayer.WirelessA] = true, [kLayer.WirelessB] = true } }
configACPR = { disableACPRShow = false }

layerACPR       = { combined = "J06-ACPRActiveCombine", divided = "J07-ACPRActiveDivide" }
layerACPRBtn    = { combined = "J09-ACPRBtnCombine",    divided = "J10-ACPRBtnDivide" }
layerUtilities  = { combined = "H08-UtilitiesCombine", divided = "H09-UtilitiesDivide" }

layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E05-PowerProgress",
    "H01-PasscodeEntry","H04-RoomCombining","H08-UtilitiesCombine","H09-UtilitiesDivide",
    "I01-CallActive", "I02-Help", "I02-HelpBtn","I03-HDMIDisc", "I04-USBDisc",
    "J06-ACPRActiveCombine","J07-ACPRActiveDivide","J08-CamPresetSaved",
    "J09-ACPRBtnCombine","J10-ACPRBtnDivide",
    "J11-CamSelectLaptopA","J12-CamSelectLaptopB","J13-CamSelectPCA","J14-CamSelectPCB",
    "J17-HIDPrivacyRoomA","J18-HIDPrivacyRoomB","J19-HIDPrivacyCombineA","J20-HIDPrivacyCombineB",
    "J21-ConferenceLaptopA","J22-ConferenceLaptopB","J23-ConferencePCA","J24-ConferencePCB",
    "L01-LaptopA", "L02-LaptopB",
    "P01-PCA", "P02-PCB",
    "W01-WirelessA","W02-WirelessB","R10-Routing","S10-StreamMusic","V05-Dialer",
}

-- Keyed by layerConfig keySource / keyHelp. Pages without a key show no help button.
helpCopy = {
    LaptopA     = { 
        title = "Help Laptop Conferencing", 
        heading = "Please make sure the following devices are selected in the Laptop A's conference settings:\n\nCamera: Laptop A USB\nSpeaker: Laptop A USB\nMicrophone: Laptop A USB",
        body = "Auto Camera Preset Recall (ACPR) is enabled by default when a call is active, keeping the cameras positioned automatically.\n\nDisable it using the ACPR toggle to manually pan, tilt, zoom, or save new presets.\n\nUse the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
    LaptopB     = { 
        title = "Help Laptop Conferencing", 
        heading = "Please make sure the following devices are selected in the Laptop B's conference settings:\n\nCamera: Laptop B USB\nSpeaker: Laptop B USB\nMicrophone: Laptop B USB",
        body = "Auto Camera Preset Recall (ACPR) is enabled by default when a call is active, keeping the cameras positioned automatically.\n\nDisable it using the ACPR toggle to manually pan, tilt, zoom, or save new presets.\n\nUse the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
    PCA         = { 
        title = "Help PC Conferencing", 
        heading = "Please make sure the following devices are selected in the PC's conference settings:\n\nCamera: PC A USB\nSpeaker: PC A USB\nMicrophone: PC A USB",
        body = "Auto Camera Preset Recall (ACPR) is enabled by default when a call is active, keeping the cameras positioned automatically.\n\nDisable it using the ACPR toggle to manually pan, tilt, zoom, or save new presets.\n\nUse the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
    PCB         = { 
        title = "Help PC Conferencing", 
        heading = "Please make sure the following devices are selected in the PC B's conference settings:\n\nCamera: PC B USB\nSpeaker: PC B USB\nMicrophone: PC B USB",
        body = "Auto Camera Preset Recall (ACPR) is enabled by default when a call is active, keeping the cameras positioned automatically.\n\nDisable it using the ACPR toggle to manually pan, tilt, zoom, or save new presets.\n\nUse the Directional Pad and the Zoom ( + ) and Zoom ( - ) buttons to adjust the camera image.\n\nPress a Preset button to have the camera move to a preset location (Recall).\n\nPress and Hold a Preset button to (Save) a new location to the selected preset button" },
    WirelessA    = { 
        title = "Help Wireless", 
        heading = "Wireless A",     
        body = "" },
    WirelessB    = { 
        title = "Help Wireless", 
        heading = "Wireless B",     
        body = "" },
    Routing     = { 
        title = "Help Routing", 
        heading = "Routing",      
        body = "" },
    StreamMusic = { 
        title = "Help Stream Music", 
        heading = "Stream Music", 
        body = "" },
}

discTextHDMI = {
    LaptopA = "Please connect the HDMI cable to Laptop A to present to the display",
    LaptopB = "Please connect the HDMI cable to Laptop B to present to the display",
    PCA     = "Please connect the HDMI cable to PC A to present to the display",
    PCB     = "Please connect the HDMI cable to PC B to present to the display",
    WirelessA = "Please connect the HDMI cable to the Wireless A device to present to the display",
    WirelessB = "Please connect the HDMI cable to the Wireless B device to present to the display",
}

discTextUSB = {
    LaptopA   = "Please connect the USB cable to Laptop A to use the room camera, microphone, and speaker",
    LaptopB   = "Please connect the USB cable to Laptop B to use the room camera, microphone, and speaker",
    PCA       = "Please connect the USB cable to PC A to use the room camera, microphone, and speaker",
    PCB       = "Please connect the USB cable to PC B to use the room camera, microphone, and speaker",
    WirelessA = "Please connect the USB cable to the Wireless A device to use the room camera, microphone, and speaker",
    WirelessB = "Please connect the USB cable to the Wireless B device to use the room camera, microphone, and speaker",
}

-- keyHDMI and keyUSB drive validateControls() so control names don't drift
configSource = {
    LaptopA = {
        layer = kLayer.LaptopA, keyHDMI = "ledHDMILaptopA", keyUSB = "ledUSBLaptopA",
        base = "L01-LaptopA", conf = "J21-ConferenceLaptopA", camera = "J11-CamSelectLaptopA",
    },
    LaptopB = {
        layer = kLayer.LaptopB, keyHDMI = "ledHDMILaptopB", keyUSB = "ledUSBLaptopB",
        base = "L02-LaptopB", conf = "J22-ConferenceLaptopB", camera = "J12-CamSelectLaptopB",
    },
    PCA = {
        layer = kLayer.PCA, keyHDMI = "ledHDMIPCA", keyUSB = "ledUSBPCA",
        base = "P01-PCA", conf = "J23-ConferencePCA", camera = "J13-CamSelectPCA",
        hidPrivDiv = "J17-HIDPrivacyRoomA", hidPrivComb = "J19-HIDPrivacyCombineA",
    },
    PCB = {
        layer = kLayer.PCB, keyHDMI = "ledHDMIPCB", keyUSB = "ledUSBPCB",
        base = "P02-PCB", conf = "J24-ConferencePCB", camera = "J14-CamSelectPCB",
        hidPrivDiv = "J18-HIDPrivacyRoomB", hidPrivComb = "J20-HIDPrivacyCombineB",
    },
    WirelessA = {
        layer = kLayer.WirelessA, keyHDMI = "ledHDMIWirelessA", keyUSB = "ledUSBWirelessA",
        base = "W01-WirelessA", conf = "J25-ConferenceWirelessA", camera = "J15-CamSelectWirelessA",
    },
    WirelessB = {
        layer = kLayer.WirelessB, keyHDMI = "ledHDMIWirelessB", keyUSB = "ledUSBWirelessB",
        base = "W02-WirelessB", conf = "J26-ConferenceWirelessB", camera = "J16-CamSelectWirelessB",
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
    [kLayer.Alarm]         = { show = {"A01-Alarm"}, hideBase = true },
    [kLayer.IncomingCall]  = { show = {"B01-IncomingCall"} },
    [kLayer.Start]         = { show = {"C05-Start"}, hideBase = true },
    [kLayer.Warming]       = { show = {"E05-PowerProgress"}, hideBase = true },
    [kLayer.Cooling]       = { show = {"E05-PowerProgress"}, hideBase = true },
    [kLayer.Utilities]     = { layerUtilities = true, hide = {"X01-ProgramVolume"} },
    [kLayer.WirelessA]     = { show = {"W01-WirelessA"}, keyHelp = "WirelessA" },
    [kLayer.WirelessB]     = { show = {"W02-WirelessB"}, keyHelp = "WirelessB" },
    [kLayer.Routing]       = { show = {"R10-Routing"}, keyHelp = "Routing" },
    [kLayer.Dialer]        = { show = {"V05-Dialer"} },
    [kLayer.StreamMusic]   = { show = {"S10-StreamMusic"}, keyHelp = "StreamMusic" },
    [kLayer.RoomCombining] = { show = {"H04-RoomCombining"}, hideBase = true },
    [kLayer.Passcode]      = { show = {"H01-PasscodeEntry"}, hideBase = true },
    [kLayer.LaptopA]       = { keySource = "LaptopA" },
    [kLayer.LaptopB]       = { keySource = "LaptopB" },
    [kLayer.PCA]           = { keySource = "PCA" },
    [kLayer.PCB]           = { keySource = "PCB" },
}

kRoom = { RoomA = "RoomA", RoomB = "RoomB" }

-- Keys must match roomName.String on each System Automation block.
sideRoomNames = {
    ["Room A"] = kRoom.RoomA,
    ["Room B"] = kRoom.RoomB,
}
sideLayers = { -- source layers this side may show while divided (all others blocked)
    [kRoom.RoomA] = { [kLayer.PCA] = true, [kLayer.LaptopA] = true, [kLayer.WirelessA] = true },
    [kRoom.RoomB] = { [kLayer.PCB] = true, [kLayer.LaptopB] = true, [kLayer.WirelessB] = true },
}
sideHiddenNav = { -- btnNav/txtNav indices hidden while divided
    [kRoom.RoomA] = { 8, 10, 12 },
    [kRoom.RoomB] = { 7, 9, 11},
}

labelConfig = {
    {suffix = "Nav", indices = navLayers},
    {single = {"NavShutdown","RoomNameNav","RoomNameStart","RoutingRooms","RoutingSources","NavTeams"}},
    {suffix = "Routing", count = 12},
    {suffix = "VidSrc", count = 12},
    {suffix = "GainPGM"},
    {suffix = "Gain", count = 10},
    {suffix = "Display", count = 12},
}

-------------------[ Constant Tables ]-------------------

pageUCI = nil
compRoomControls = nil
compRoomMode = nil   -- { btnRoomMode 1..3 } from the Divisible Space block
roomSide = nil       -- kRoom.RoomA / kRoom.RoomB from roomControls.roomName

kLayerName = {}
for name, idx in pairs(kLayer) do kLayerName[idx] = name end

btnNav = {} -- keyed by kLayer index; only user-navigable pages (navLayers)
for _, idx in ipairs(navLayers) do btnNav[idx] = Controls[string.format("btnNav%02d", idx)] end

layerConf = {}
for _, def in pairs(configSource) do
    if def.conf then table.insert(layerConf, def.conf) end
end

-------------------[ Constants ]-------------------

stateDebug = true
layerDefault = tonumber(Uci.Variables.layerDefault and Uci.Variables.layerDefault.Value) or 7
legendStart = { divided = "Start Room", combined = "Start Rooms Combined" }

state = {
    activeLayer = kLayer.Start,
    powerProgress = nil,   -- "warming" / "cooling" / nil
    shutdownConfirm = false,
    helpOpen = false,
    pendingLayer = nil,    -- source layer to land on after warmup (set by ensureSystemIsOn)
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
        "ledACPRBypassDivide","ledACPRBypassCombine",
        "btnHelpOpen","btnHelpClose","txtHelpTitle","txtHelpHeading","txtHelpBody","txtHDMIDisc","txtUSBDisc",
    }
    for _, idx in ipairs(navLayers) do table.insert(required, string.format("btnNav%02d", idx)) end
    for key, def in pairs(configSource) do
        if def.keyUSB then table.insert(required, def.keyUSB) end
        if def.keyHDMI then table.insert(required, def.keyHDMI) end
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

    -- Table-backed layer refs (also listed in layersToHide); validate here so renames drift with a config path, not only "layersToHide"
    for tableName, tbl in pairs({
        layerUtilities = layerUtilities,
        layerACPR = layerACPR,
        layerACPRBtn = layerACPRBtn,
    }) do
        if type(tbl) == "table" then
            for key, name in pairs(tbl) do note(name, tableName.."."..key) end
        end
    end

    for key, def in pairs(configSource) do
        note(def.base,       "configSource."..key..".base")
        note(def.conf,       "configSource."..key..".conf")
        note(def.camera,     "configSource."..key..".camera")
        note(def.hidPrivDiv, "configSource."..key..".hidPrivDiv")
        note(def.hidPrivComb,"configSource."..key..".hidPrivComb")
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

-------------------[ Divisible Space ]-------------------

function getRoomState()
    if not compRoomMode then return "divided" end
    if compRoomMode[1] and compRoomMode[1].Boolean then return "divided" end
    if compRoomMode[2] and compRoomMode[2].Boolean then return "combinedA" end
    if compRoomMode[3] and compRoomMode[3].Boolean then return "combinedB" end
    return "divided"
end

function getPostWarmingLayer()
    local roomState = getRoomState()
    if roomState == "combinedA" then return kLayer.PCA end
    if roomState == "combinedB" then return kLayer.PCB end
    return (roomSide == kRoom.RoomB) and kLayer.PCB or kLayer.PCA
end

-- Divided: only this side's source layers are allowed. Non-source layers are never gated.
function showLayer(layerIndex, roomState)
    if roomState ~= "divided" or not roomSide then return true end
    if not (layerConfig[layerIndex] and layerConfig[layerIndex].keySource) then return true end
    return sideLayers[roomSide][layerIndex] == true
end

function updateRoomUI(roomState)
    local isDivided = (roomState == "divided")
    Controls.btnStartSystem.Legend = isDivided and legendStart.divided or legendStart.combined
    for _, i in ipairs(roomSide and sideHiddenNav[roomSide] or {}) do
        if btnNav[i] then btnNav[i].IsInvisible = isDivided end
        local txt = Controls[string.format("txtNav%02d", i)]
        if txt then txt.IsInvisible = isDivided end
    end
    debugPrint("Room state: "..roomState.." (side="..tostring(roomSide)..")")
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

function applySourceOverlay(desired, keySource, roomState)
    local def = configSource[keySource]
    if not hdmiConnected(keySource) then
        want(desired, "I03-HDMIDisc", true)
        Controls.txtHDMIDisc.String = discTextHDMI[keySource] or ""
        return
    end

    if def.keyUSB and not usbConnected(keySource) then
        want(desired, "I04-USBDisc", true)
        Controls.txtUSBDisc.String = discTextUSB[keySource] or ""
        return
    end

    local usb = usbConnected(keySource)
    local isCombined = (roomState ~= "divided")
    local mode = isCombined and "combined" or "divided"
    want(desired, def.base, true)
    if isCombined then want(desired, def.camera, true) end

    if not configSkip.skip[def.layer] or usb then
        want(desired, def.conf, true)
    end

    if usb then
        if def.hidPrivDiv then want(desired, isCombined and def.hidPrivComb or def.hidPrivDiv, true) end
        if not configACPR.disableACPRShow then want(desired, layerACPRBtn[mode], true) end
    end

    if not configACPR.disableACPRShow then
        local bypass = isCombined and Controls.ledACPRBypassCombine or Controls.ledACPRBypassDivide
        if not bypass.Boolean then want(desired, layerACPR[mode], true) end
    end

    applyHelp(desired, keySource, true) -- last: open help hides conf/USB
end

function buildDesired(roomState)
    local desired = {}
    want(desired, layersToHide, false)

    local cfg = layerConfig[state.activeLayer]
    if cfg then
        want(desired, layersBase, not cfg.hideBase)
        if cfg.layerUtilities then
            want(desired, (roomState == "divided") and layerUtilities.divided or layerUtilities.combined, true)
        elseif cfg.show then
            want(desired, cfg.show, true)
        end
        want(desired, cfg.hide, false)
    end

    want(desired, "I01-CallActive", Controls.ledOffHook.Boolean)
    want(desired, "J08-CamPresetSaved", Controls.ledPresetSaved.Boolean)
    want(desired, "D01-ShutdownConfirm", state.shutdownConfirm)

    local keySource = activeSourceKey()
    if keySource then
        if showLayer(state.activeLayer, roomState) then
            applySourceOverlay(desired, keySource, roomState)
        else
            debugPrint("Layer "..state.activeLayer.." hidden by divisible-space")
        end
    elseif cfg and cfg.keyHelp then
        applyHelp(desired, cfg.keyHelp, false)
    end
    return desired
end

function refreshLayers(force)
    applyDesired(buildDesired(getRoomState()), force)
end

function setHelpOpen(isOpen)
    state.helpOpen = isOpen
    debugPrint("Help → "..(isOpen and "open" or "closed").." (page="..tostring(kLayerName[state.activeLayer])..")")
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
    if layerIndex == kLayer.RoomCombining then resetTouchInactivityTimer() end
    refreshLayers()
    interlockNav()
    debugPrint("Layer "..(kLayerName[prev] or prev).." → "..(kLayerName[layerIndex] or layerIndex).." (Source: "..source..")")
end

function resetTouchInactivityTimer()
    timerInactivity:Stop()
    if state.activeLayer ~= kLayer.RoomCombining then return end
    local timeout = tonumber(Uci.Variables.timeTouchInactivity and Uci.Variables.timeTouchInactivity.Value) or 60
    timerInactivity:Start(timeout > 0 and timeout or 60)
end

function onTouchInactivityTimeout()
    timerInactivity:Stop()
    if state.activeLayer ~= kLayer.RoomCombining then return end
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
        local target = isWarming and (state.pendingLayer or getPostWarmingLayer()) or kLayer.Start
        state.pendingLayer = nil
        goToLayer(target, source)
        return
    end

    if not isWarming then state.pendingLayer = nil end

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

-- targetLayer nil (Start button): on → layerDefault, off → getPostWarmingLayer() after warmup.
function ensureSystemIsOn(targetLayer)
    local power = compRoomControls and compRoomControls["ledSystemPower"]
    if power and power.Boolean then
        goToLayer(targetLayer or layerDefault, "Source Active")
        return
    end
    state.pendingLayer = targetLayer
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
        debugPrint("Room Controls not found: "..tostring(name))
        return false
    end

    local rn = compRoomControls["roomName"] and compRoomControls["roomName"].String
    roomSide = rn and sideRoomNames[rn]
    if rn then debugPrint("Room identity: "..tostring(roomSide).." (roomName='"..rn.."')") end

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

function initDivisibleSpace()
    local comp = getComp(componentNames.divisibleSpace)
    if not comp then
        debugPrint("DivisibleSpace: component not found (feature disabled)")
        return
    end
    compRoomMode = { comp["btnRoomMode 1"], comp["btnRoomMode 2"], comp["btnRoomMode 3"] }
    for _, btn in ipairs(compRoomMode) do
        btn.EventHandler = function(ctl)
            if not ctl.Boolean then return end
            local roomState = getRoomState()
            updateRoomUI(roomState)
            applyDesired(buildDesired(roomState))
        end
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
    if power and power.Boolean then goToLayer(getPostWarmingLayer(), "Init Sync Ready") end
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

if not validateControls() then error("UCIController (DivisibleSpace): missing required controls (see list above)") end

for idx, btn in pairs(btnNav) do
    btn.EventHandler = function() goToLayer(idx, "btnNav") end
end

Controls.btnStartSystem.EventHandler = function() ensureSystemIsOn() end

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
    setSystemPower(false, "System Shutdown")
end

Controls.btnHelpOpen.EventHandler = function() setHelpOpen(true) end
Controls.btnHelpClose.EventHandler = function() setHelpOpen(false) end

for key, def in pairs(configSource) do
    local function onSourceConnect(ctl)
        if ctl.Boolean and showLayer(def.layer, getRoomState()) then
            ensureSystemIsOn(def.layer)
        else
            refreshLayers()
        end
    end
    Controls[def.keyHDMI].EventHandler = onSourceConnect
    if def.keyUSB then Controls[def.keyUSB].EventHandler = onSourceConnect end
end

for _, name in ipairs({"ledACPRBypassDivide", "ledACPRBypassCombine", "ledPresetSaved", "ledOffHook"}) do
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
        print("✗ ERROR: UCIController (DivisibleSpace) initialization failed: Uci.GetUciPages returned no pages")
        return
    end
    debugPrint("=== Initialization Started ===")
    if not validateLayers() then error("UCIController: layer validation failed (see list above)") end
    initLabels()
    if not initRoomControls() then print("ERROR: Room controls unavailable — power actions disabled") end
    initDivisibleSpace()
    initSyncFromRoomControls()
    updateRoomUI(getRoomState())
    refreshLayers(true) -- force full push; GetLayerVisibility may be stale after a Core reboot
    interlockNav()
    print("✓ UCIController (DivisibleSpace) initialized for "..pageUCI)
end

funcInit()
