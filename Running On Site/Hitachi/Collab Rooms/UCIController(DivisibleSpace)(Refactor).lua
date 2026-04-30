--[[
  UCI Controller (DivisibleSpace) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 3.0 | Date: 2025-02-22
  Firmware Req: 10.0.0

  Flat module per qsys-lua-architecture. Event-driven power sync via ledSystemPower.
  Divisible spaces: CollabA/CollabB, PCA/PCB, LaptopA/LaptopB. Room combining, ACPR separated/combined.
]]

-------------------[ Configuration ]-------------------
local conferenceStateConfig = { skip = { [9]=true, [10]=true } }
local acprConfig = { disableACPRShow = false }

local kLayer = {
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
    RoomCombining   = 15
}

local layersBase = {"X01-ProgramVolume", "Y01-Navbar", "Z01-Base"}
local layersToHide = {
    "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
    "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
    "H04-RoomCombining","H08-RoomControlsCombined","H09-RoomControlsSeparated","H10-RoomControls",
    "I01-CallActive","I02-HelpLaptopA","I03-HelpLaptopB","I04-HelpPCA","I05-HelpPCB",
    "I06-HelpWirelessA","I07-HelpWirelessB","I08-HelpRouting","I09-HelpDialer","I10-HelpStreamMusic",
    "J01-ConnectUSBLaptopA","J02-ConnectUSBLaptopB","J03-ConnectUSBPCA","J04-ConnectUSBPCB",
    "J06-ACPRActiveCombined","J07-ACPRActiveSeparated","J08-CamPresetSaved",
    "J09-ACPRBtnCombined","J10-ACPRBtnSeparated",
    "J11-CameraSelectionLaptopA","J12-CameraSelectionLaptopB","J13-CameraSelectionPCA","J14-CameraSelectionPCB",
    "J17-VideoPrivacySeparatedA","J18-VideoPrivacySeparatedB","J19-VideoPrivacyCombinedA","J20-VideoPrivacyCombinedB",
    "J21-ConferenceControlsLaptopA","J22-ConferenceControlsLaptopB","J23-ConferenceControlsPCA","J24-ConferenceControlsPCB",
    "L01-HDMIDisconnected","L01-LaptopA","L02-HDMIDisconnected","L02-LaptopB",
    "P01-HDMIDisconnected","P01-PCA","P02-HDMIDisconnected","P02-PCB",
    "W01-WirelessA","W02-WirelessB","W05-Wireless","R10-Routing","S10-StreamMusic","V05-Dialer"
}

local SwitcherTypes = {
    ExtronDXP = {
        componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames = {"devExtronDXP","compExtronDXP"},
        outputMappings = {
            CollabA = {[7]="Input 3",[8]="Input 4",[9]="Input 1",[10]="Input 2"},
            CollabB = {[7]="Input 7",[8]="Input 8",[9]="Input 5",[10]="Input 6"}
        }
    }
}

local configSource = {
    LaptopA = { layer=kLayer.LaptopA, base="L01-LaptopA", disc="L01-HDMIDisconnected",
        usb="J01-ConnectUSBLaptopA", conf="J21-ConferenceControlsLaptopA", camera="J11-CameraSelectionLaptopA",
        help="I02-HelpLaptopA", vidPrivSep=nil, vidPrivComb=nil },
    LaptopB = { layer=kLayer.LaptopB, base="L02-LaptopB", disc="L02-HDMIDisconnected",
        usb="J02-ConnectUSBLaptopB", conf="J22-ConferenceControlsLaptopB", camera="J12-CameraSelectionLaptopB",
        help="I03-HelpLaptopB", vidPrivSep=nil, vidPrivComb=nil },
    PCA = { layer=kLayer.PCA, base="P01-PCA", disc="P01-HDMIDisconnected",
        usb="J03-ConnectUSBPCA", conf="J23-ConferenceControlsPCA", camera="J13-CameraSelectionPCA",
        help="I04-HelpPCA", vidPrivSep="J17-VideoPrivacySeparatedA", vidPrivComb="J19-VideoPrivacyCombinedA" },
    PCB = { layer=kLayer.PCB, base="P02-PCB", disc="P02-HDMIDisconnected",
        usb="J04-ConnectUSBPCB", conf="J24-ConferenceControlsPCB", camera="J14-CameraSelectionPCB",
        help="I05-HelpPCB", vidPrivSep="J18-VideoPrivacySeparatedB", vidPrivComb="J20-VideoPrivacyCombinedB" },
}

local configHelpPairKeys = {"LaptopA","LaptopB","PCA","PCB","WirelessA","WirelessB","Routing","StreamMusic"}

-------------------[ Controls ]-------------------
local controls = {
    btnNav = {},
    btnStartSystem      = Controls.btnStartSystem, 
    btnNavShutdown      = Controls.btnNavShutdown,
    btnShutdownCancel   = Controls.btnShutdownCancel, 
    btnShutdownConfirm  = Controls.btnShutdownConfirm,
    btnOpenHelp = {
        LaptopA     = Controls.btnOpenHelpLaptopA, 
        LaptopB     = Controls.btnOpenHelpLaptopB,
        PCA         = Controls.btnOpenHelpPCA, 
        PCB         = Controls.btnOpenHelpPCB,
        WirelessA   = Controls.btnOpenHelpWirelessA, 
        WirelessB   = Controls.btnOpenHelpWirelessB,
        Routing     = Controls.btnOpenHelpRouting, 
        StreamMusic = Controls.btnOpenHelpStreamMusic,
    },
    btnCloseHelp = {
        LaptopA     = Controls.btnCloseHelpLaptopA, 
        LaptopB     = Controls.btnCloseHelpLaptopB,
        PCA         = Controls.btnCloseHelpPCA, 
        PCB         = Controls.btnCloseHelpPCB,
        WirelessA   = Controls.btnCloseHelpWirelessA, 
        WirelessB   = Controls.btnCloseHelpWirelessB,
        Routing     = Controls.btnCloseHelpRouting, 
        StreamMusic = Controls.btnCloseHelpStreamMusic,
    },
    btnHelpDialer               = Controls.btnHelpDialer,
    knbProgressBar              = Controls.knbProgressBar, 
    txtProgressBar              = Controls.txtProgressBar,
    pinCallActive               = Controls.pinCallActive,
    pinLEDUSBLaptopA            = Controls.pinLEDUSBLaptopA,
    pinLEDUSBLaptopB            = Controls.pinLEDUSBLaptopB,
    pinLEDUSBPCA                = Controls.pinLEDUSBPCA, 
    pinLEDUSBPCB                = Controls.pinLEDUSBPCB,
    pinLEDOffHookLaptopA        = Controls.pinLEDOffHookLaptopA, 
    pinLEDOffHookLaptopB        = Controls.pinLEDOffHookLaptopB,
    pinLEDOffHookPCA            = Controls.pinLEDOffHookPCA, 
    pinLEDOffHookPCB            = Controls.pinLEDOffHookPCB,
    pinLEDHDMIActiveLaptopA     = Controls.pinLEDHDMIActiveLaptopA, 
    pinLEDHDMIActiveLaptopB     = Controls.pinLEDHDMIActiveLaptopB,
    pinLEDHDMIActivePCA         = Controls.pinLEDHDMIActivePCA, 
    pinLEDHDMIActivePCB         = Controls.pinLEDHDMIActivePCB,
    pinLEDPresetSaved           = Controls.pinLEDPresetSaved,
    pinLEDACPRBypassSeparated   = Controls.pinLEDACPRBypassSeparated, 
    pinLEDACPRBypassCombined    = Controls.pinLEDACPRBypassCombined,
    pinLEDHDMIConnectedPCA      = Controls.pinLEDHDMIConnectedPCA, 
    pinLEDHDMIConnectedPCB      = Controls.pinLEDHDMIConnectedPCB,
    pinLEDHDMIConnectedLaptopA  = Controls.pinLEDHDMIConnectedLaptopA, 
    pinLEDHDMIConnectedLaptopB  = Controls.pinLEDHDMIConnectedLaptopB,
    pinLEDTouchActivity         = Controls.pinLEDTouchActivity,
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
    defaultLayer = tonumber(Uci.Variables.numDefaultActiveLayer and Uci.Variables.numDefaultActiveLayer.Value) or 10,
    navHidden = {},
}

-------------------[ State ]-------------------
local btnNavEventHandler
local resetTouchInactivityTimer
local reflectPowerState
local updateConferenceState

local state = {
    activeLayer = kLayer.Start,
    layerStates = {},
    callActive = false,
    isAnimating = false,
    isInitialized = false,
}
local components = {
    roomControls = nil, prevPowerState = nil,
    videoSwitcher = nil, switcherType = nil,
    divisibleSpace = nil, btnRoomState = nil, roomIdentity = nil,
}
local timers = { loading = nil, timeout = nil, inactivity = Timer.New() }
local arrUCILegends, arrUCIUserLabels = {}, {}
local sources, helpLayerButtonMap, allUSBConnect, allConference, allCamera, allVideoPrivacy
local acprLayers = { combined="J06-ACPRActiveCombined", separated="J07-ACPRActiveSeparated" }
local acprBtnLayers = { combined="J09-ACPRBtnCombined", separated="J10-ACPRBtnSeparated" }

local layerHelpToKey = {
    ["I02-HelpLaptopA"]="LaptopA", ["I03-HelpLaptopB"]="LaptopB", ["I04-HelpPCA"]="PCA", ["I05-HelpPCB"]="PCB",
    ["I06-HelpWirelessA"]="WirelessA", ["I07-HelpWirelessB"]="WirelessB", ["I08-HelpRouting"]="Routing", ["I10-HelpStreamMusic"]="StreamMusic",
}

local function buildSources()
    sources = {}
    for name, def in pairs(configSource) do
        sources[name] = {
            layerConst=def.layer, hdmiPin=controls["pinLEDHDMIConnected"..name],
            baseLayer=def.base, discLayer=def.disc, usbPin=controls["pinLEDUSB"..name],
            usbConnect=def.usb, confLayer=def.conf, cameraLayer=def.camera,
            videoPrivacySeparate=def.vidPrivSep, videoPrivacyCombine=def.vidPrivComb,
            helpLayer=def.help, btnOpen=controls.btnOpenHelp[name], btnClose=controls.btnCloseHelp[name]
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
    allUSBConnect, allConference, allCamera, allVideoPrivacy = {}, {}, {}, {}
    for _, src in pairs(sources) do
        if src.usbConnect then table.insert(allUSBConnect, src.usbConnect) end
        if src.confLayer then table.insert(allConference, src.confLayer) end
        if src.cameraLayer then table.insert(allCamera, src.cameraLayer) end
        if src.videoPrivacySeparate then table.insert(allVideoPrivacy, src.videoPrivacySeparate) end
        if src.videoPrivacyCombine then table.insert(allVideoPrivacy, src.videoPrivacyCombine) end
    end
end

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if config.debug then print("["..config.pageUCI.."] "..str) end
end

-------------------[ Divisible Space Helpers ]-------------------
local function getRoomState()
    if not components.divisibleSpace or not components.btnRoomState then return "separated" end
    local btns = components.btnRoomState
    if btns[1] and btns[1].Boolean then return "separated"
    elseif btns[2] and btns[2].Boolean then return "combinedA"
    elseif btns[3] and btns[3].Boolean then return "combinedB" end
    return "separated"
end

local function getDefaultLayerAfterWarming()
    local roomState = getRoomState()
    local roomId = components.roomIdentity or "CollabA"
    if roomState == "separated" then
        return (roomId == "CollabB") and kLayer.PCB or kLayer.PCA
    elseif roomState == "combinedA" then return kLayer.PCA
    elseif roomState == "combinedB" then return kLayer.PCB end
    return kLayer.Routing
end

local function getRoomControlsLayerName()
    return (getRoomState() == "separated") and "H09-RoomControlsSeparated" or "H08-RoomControlsCombined"
end

local function shouldShowLayer(layerIndex)
    local roomState = getRoomState()
    local roomId = components.roomIdentity
    local avail = { CollabA = { [kLayer.PCA]=true, [kLayer.LaptopA]=true }, CollabB = { [kLayer.PCB]=true, [kLayer.LaptopB]=true } }
    if roomState == "combinedA" or roomState == "combinedB" then return true end
    if roomState == "separated" and avail[roomId] then
        local val = avail[roomId][layerIndex]
        if val ~= nil then return val end
    end
    return true
end

local function updateNavigationVisibility()
    local roomState = getRoomState()
    local roomId = components.roomIdentity
    local isSep = (roomState == "separated")
    local navConfig = { CollabA = {{num="08",lbl="PCB"},{num="10",lbl="LaptopB"}}, CollabB = {{num="07",lbl="PCA"},{num="09",lbl="LaptopA"}} }
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

local function updateStartSystemLegend()
    local legend = (getRoomState() == "separated") and "Start Room \nSeparated" or "Start Rooms \nCombined"
    setProp(controls.btnStartSystem, "Legend", legend)
    debugPrint("Start legend → "..legend)
end

-------------------[ Functions ]-------------------
local function validateControls()
    for i = 1, 15 do
        controls.btnNav[i] = Controls["btnNav"..string.format("%02d", i)]
    end
    local missing, optional = {}, {
        pinLEDTouchActivity = true, pinLEDHDMIConnectedPCA = true, pinLEDHDMIConnectedPCB = true,
        pinLEDHDMIConnectedLaptopA = true, pinLEDHDMIConnectedLaptopB = true,
    }
    for name, ctrl in pairs(controls) do
        if name == "btnNav" then
            for i = 1, 15 do if not ctrl[i] then table.insert(missing, "btnNav"..string.format("%02d",i)) end end
        elseif type(ctrl)=="table" then
            for key, sub in pairs(ctrl) do
                if not sub and not optional[name.."."..tostring(key)] then table.insert(missing, name.."["..tostring(key).."]") end
            end
        elseif not ctrl and not optional[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: UCIController validation failed - Missing required controls:")
        for _, n in ipairs(missing) do print("  - "..n) end
        return false
    end
    return true
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

local function getActiveSource()
    local key = sources and sources._layerToSource and sources._layerToSource[state.activeLayer]
    return key and sources[key] or nil
end

local function checkHDMIConnection()
    local src = getActiveSource()
    if not src or not src.hdmiPin then return true end
    return src.hdmiPin.Boolean
end

local function syncHelpButtonStates(helpLayer)
    local map = helpLayerButtonMap and helpLayerButtonMap[helpLayer]
    if not map or state.layerStates[helpLayer] == nil then return end
    setProp(map.open, "Boolean", state.layerStates[helpLayer])
    setProp(map.close, "Boolean", false)
end

local function updateCallActiveState()
    state.callActive = controls.pinCallActive and controls.pinCallActive.Boolean or false
    updateLayerVisibility({"I01-CallActive"}, state.callActive, state.callActive and "fade" or "none")
    debugPrint("Call Active → "..(state.callActive and "ON" or "OFF"))
end

local function updatePresetSavedState()
    local v = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
    updateLayerVisibility({"J08-CamPresetSaved"}, v, v and "fade" or "none")
end

local function updateHDMIForActiveSource()
    local src = getActiveSource()
    if not src then return end
    if checkHDMIConnection() then
        updateLayerVisibility({src.baseLayer}, true, "fade")
        updateLayerVisibility({src.discLayer}, false, "none")
        debugPrint("HDMI "..src.baseLayer.." → Connected")
    else
        updateLayerVisibility({src.discLayer}, true, "fade")
        updateLayerVisibility({src.baseLayer, src.confLayer, src.helpLayer}, false, "none")
        if src.helpLayer then syncHelpButtonStates(src.helpLayer) end
        debugPrint("HDMI "..src.baseLayer.." → Disconnected")
    end
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
        updateLayerVisibility(collectLayers(allConference, allUSBConnect), false, "none")
    else
        updateLayerVisibility({src.helpLayer}, false, "none")
        updateConferenceState()
    end
    syncHelpButtonStates(src.helpLayer)
    debugPrint(srcKey.." Help → "..(isVisible and "Showing" or "Hiding"))
end

updateConferenceState = function()
    local src = getActiveSource()
    if not src then return end
    if not checkHDMIConnection() then
        local hide = collectLayers(allUSBConnect, allConference)
        if src.helpLayer then table.insert(hide, src.helpLayer) end
        updateLayerVisibility(hide, false, "none")
        if src.helpLayer then syncHelpButtonStates(src.helpLayer) end
        return
    end
    if conferenceStateConfig.skip[src.layerConst] then return end
    local usb = src.usbPin and src.usbPin.Boolean or false
    if usb then
        updateLayerVisibility({src.confLayer}, true, "fade")
        updateLayerVisibility(allUSBConnect or {}, false, "none")
    else
        updateLayerVisibility({src.usbConnect}, true, "fade")
        updateLayerVisibility({src.confLayer, src.helpLayer}, false, "none")
        if src.helpLayer then syncHelpButtonStates(src.helpLayer) end
    end
    debugPrint("Conference: "..(usb and "Connected" or "Disconnected"))
end

local function determineSourceLayerVisibility(src, isActive, usbConnected, isCombined, showLayers, hideLayers)
    local confActive = false
    local skipConf = conferenceStateConfig.skip and conferenceStateConfig.skip[src.layerConst]
    if src.cameraLayer then
        if isActive and isCombined then table.insert(showLayers, src.cameraLayer)
        else table.insert(hideLayers, src.cameraLayer) end
    end
    if isActive and usbConnected and not skipConf then table.insert(showLayers, src.confLayer); confActive = true
    else table.insert(hideLayers, src.confLayer) end
    if src.videoPrivacySeparate and src.videoPrivacyCombine then
        if isActive and usbConnected then
            if isCombined then table.insert(showLayers, src.videoPrivacyCombine); table.insert(hideLayers, src.videoPrivacySeparate)
            else table.insert(showLayers, src.videoPrivacySeparate); table.insert(hideLayers, src.videoPrivacyCombine) end
        else table.insert(hideLayers, src.videoPrivacySeparate); table.insert(hideLayers, src.videoPrivacyCombine) end
    end
    return confActive
end

local function updateConferenceControlsLayer()
    if not checkHDMIConnection() then
        local hide = collectLayers(allCamera, allConference, allVideoPrivacy)
        table.insert(hide, acprBtnLayers.combined); table.insert(hide, acprBtnLayers.separated)
        updateLayerVisibility(hide, false, "none")
        return
    end
    local roomState = getRoomState()
    local isCombined = (roomState ~= "separated")
    local showLayers, hideLayers, anyConfActive = {}, {}, false
    for _, src in pairs(sources) do
        if type(src) == "table" and src.layerConst then
            local isActive = (state.activeLayer == src.layerConst)
            local usb = src.usbPin and src.usbPin.Boolean or false
            if determineSourceLayerVisibility(src, isActive, usb, isCombined, showLayers, hideLayers) then anyConfActive = true end
        end
    end
    if not acprConfig.disableACPRShow and anyConfActive then
        if isCombined then table.insert(showLayers, acprBtnLayers.combined); table.insert(hideLayers, acprBtnLayers.separated)
        else table.insert(showLayers, acprBtnLayers.separated); table.insert(hideLayers, acprBtnLayers.combined) end
    else table.insert(hideLayers, acprBtnLayers.combined); table.insert(hideLayers, acprBtnLayers.separated) end
    for _, layer in ipairs(showLayers) do updateLayerVisibility({layer}, true, "fade") end
    for _, layer in ipairs(hideLayers) do updateLayerVisibility({layer}, false, "none") end
    debugPrint("Conference controls: "..#showLayers.." shown, "..#hideLayers.." hidden")
end

local function updateACPRBypassState()
    if acprConfig.disableACPRShow then
        updateLayerVisibility({acprLayers.combined, acprLayers.separated}, false, "none")
        return
    end
    local src = getActiveSource()
    if not src or not checkHDMIConnection() then return end
    local roomState = getRoomState()
    local isSep = (roomState == "separated")
    local bypassCtl = isSep and controls.pinLEDACPRBypassSeparated or controls.pinLEDACPRBypassCombined
    local acprOn = isSep and acprLayers.separated or acprLayers.combined
    local acprOff = isSep and acprLayers.combined or acprLayers.separated
    local bypass = bypassCtl and bypassCtl.Boolean or false
    updateLayerVisibility({acprOff}, false, "none")
    if not bypass then
        updateLayerVisibility({acprOn}, true, "fade")
        updateLayerVisibility({src.confLayer}, false, "none")
    else
        updateLayerVisibility({src.confLayer}, true, "fade")
        updateLayerVisibility({acprOn}, false, "none")
    end
    debugPrint("ACPR Bypass ("..roomState.."): "..(bypass and "Active" or "Inactive"))
    updateConferenceControlsLayer()
end

local function updateWirelessHelpState()
    local v = controls.btnOpenHelp.WirelessA and controls.btnOpenHelp.WirelessA.Boolean or false
    updateLayerVisibility({"I06-HelpWirelessA"}, v, "none")
    syncHelpButtonStates("I06-HelpWirelessA")
end

local function updateRoutingHelpState()
    local v = controls.btnOpenHelp.Routing and controls.btnOpenHelp.Routing.Boolean or false
    updateLayerVisibility({"I08-HelpRouting"}, v, "none")
    syncHelpButtonStates("I08-HelpRouting")
end

local function updateDialerHelpState()
    local v = controls.btnHelpDialer and controls.btnHelpDialer.Boolean or false
    updateLayerVisibility({"I09-HelpDialer"}, v, "none")
end

local function updateStreamMusicHelpState()
    local v = controls.btnOpenHelp.StreamMusic and controls.btnOpenHelp.StreamMusic.Boolean or false
    updateLayerVisibility({"I10-HelpStreamMusic"}, v, "none")
    syncHelpButtonStates("I10-HelpStreamMusic")
end

local layerConfigs
local function makeSourceLayerFn(srcKey)
    return function()
        updateHDMIForActiveSource(); updateConferenceState(); updateConferenceControlsLayer(); updatePresetSavedState()
        updateACPRBypassState(); updateSourceHelpState(srcKey); updateCallActiveState()
    end
end

local function buildLayerConfigs()
    layerConfigs = {
        [kLayer.Alarm] = { show={"A01-Alarm"}, hideBase=true },
        [kLayer.IncomingCall] = { show={"B01-IncomingCall"} },
        [kLayer.Start] = { show={"C05-Start"}, hideBase=true },
        [kLayer.Warming] = { show={"E05-SystemProgress","E01-SystemProgressWarming"}, hideBase=true },
        [kLayer.Cooling] = { show={"E05-SystemProgress","E02-SystemProgressCooling"}, hideBase=true },
        [kLayer.RoomControls] = { conditional=true, showRoomControls=true, hide={"X01-ProgramVolume"}, fn=function() updateCallActiveState() end },
        [kLayer.Wireless] = { show={"W05-Wireless"}, fn=function() updateWirelessHelpState(); updateCallActiveState() end },
        [kLayer.Routing] = { show={"R10-Routing"}, fn=function() updateCallActiveState() end },
        [kLayer.Dialer] = { show={"V05-Dialer"}, fn=function() updateDialerHelpState(); updateCallActiveState() end },
        [kLayer.StreamMusic] = { show={"S10-StreamMusic"}, fn=function() updateStreamMusicHelpState(); updateCallActiveState() end },
        [kLayer.RoomCombining] = { show={"H04-RoomCombining"}, hideBase=true, fn=function() resetTouchInactivityTimer(); updateCallActiveState() end },
    }
    for name, def in pairs(configSource) do
        layerConfigs[def.layer] = { conditional=true, show={def.base}, fn=makeSourceLayerFn(name) }
    end
end

local function showLayer()
    if not layerConfigs then buildLayerConfigs() end
    updateLayerVisibility(layersToHide, false, "none")
    updateLayerVisibility(layersBase, true, "none")
    updateNavigationVisibility()
    local cfg = layerConfigs[state.activeLayer]
    if not cfg then return end
    if cfg.conditional then
        if cfg.showRoomControls then
            local layerName = getRoomControlsLayerName()
            if not layerName then return end
            cfg.show = {layerName}
        else
            if not shouldShowLayer(state.activeLayer) then debugPrint("Layer "..state.activeLayer.." hidden by divisible-space"); return end
        end
    end
    if cfg.hideBase then updateLayerVisibility(layersBase, false, "none") end
    if cfg.show then updateLayerVisibility(cfg.show, true, "fade") end
    if cfg.hide then updateLayerVisibility(cfg.hide, false, "none") end
    if cfg.fn then cfg.fn() end
end

local function interlock()
    for i = 1, 15 do
        local btn = controls.btnNav and controls.btnNav[i]
        if btn then setProp(btn, "Boolean", i == state.activeLayer) end
    end
end

local function initRoomControls()
    local compName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String
    if not compName then
        local page = config.pageUCI:match("uci%s+([^(]+)")
        if page then compName = "compRoomControls"..page:gsub("%s+", "") end
    end
    if not compName then debugPrint("Room Controls: could not determine component"); return false end
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then debugPrint("Room Controls not found: "..compName); return false end
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

local function initVideoSwitcher()
    for swType, cfg in pairs(SwitcherTypes) do
        for _, name in ipairs(cfg.switcherNames or {}) do
            local ctrl = Controls[name]
            if ctrl and ctrl.String and ctrl.String ~= "" then
                local ok, comp = pcall(function() return Component.New(ctrl.String) end)
                if ok and comp then
                    components.videoSwitcher = comp
                    components.switcherType = swType
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
                if ok and c then components.videoSwitcher = c; components.switcherType = swType
                    debugPrint("Video switcher: "..swType.." (auto-detect)"); return true end
            end
        end
    end
    return false
end

local function switchToInput(uciButton)
    if not components.videoSwitcher or not components.switcherType then return false end
    local cfg = SwitcherTypes[components.switcherType]
    if not cfg or not cfg.outputMappings then return false end
    local roomId = components.roomIdentity
    if not roomId then debugPrint("Video switch: Room identity not determined"); return false end
    local mapping = cfg.outputMappings[roomId]
    if not mapping then debugPrint("Video switch: No mapping for "..roomId); return false end
    local inputName = mapping[uciButton]
    if not inputName then return false end
    local ok, err = pcall(function()
        if components.videoSwitcher[inputName] then
            components.videoSwitcher[inputName]:Trigger()
        end
    end)
    if ok then debugPrint("Video → "..inputName.." (Source: UCI Layer "..uciButton..")") else debugPrint("Video switch error: "..tostring(err)) end
    return ok
end

local function initDivisibleSpace()
    local roomName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String or ""
    if roomName:find("CollabA") then components.roomIdentity = "CollabA"; debugPrint("Room identity: Collab A")
    elseif roomName:find("CollabB") then components.roomIdentity = "CollabB"; debugPrint("Room identity: Collab B")
    else debugPrint("Room identity: could not determine from "..roomName) end
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if ok and comp then
        components.divisibleSpace = comp
        components.btnRoomState = {
            comp["btnRoomState 1"], comp["btnRoomState 2"], comp["btnRoomState 3"]
        }
        for i, btn in ipairs(components.btnRoomState) do
            if btn then
                bind(btn, function(ctl)
                    if not ctl.Boolean then return end
                    updateNavigationVisibility()
                    updateStartSystemLegend()
                    updateConferenceControlsLayer()
                end)
            end
        end
        debugPrint("DivisibleSpace: registered "..#components.btnRoomState.." state handlers")
    else debugPrint("DivisibleSpace: component not found (feature disabled)") end
    return components.divisibleSpace ~= nil
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
        if isPoweringOn and components.roomControls["warmupTime"] then duration = components.roomControls["warmupTime"].Value
        elseif not isPoweringOn and components.roomControls["cooldownTime"] then duration = components.roomControls["cooldownTime"].Value end
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
        btnNavEventHandler(isPoweringOn and getDefaultLayerAfterWarming() or kLayer.Start, "Loading Timeout")
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
            btnNavEventHandler(isPoweringOn and getDefaultLayerAfterWarming() or kLayer.Start, isPoweringOn and "Warmup Complete" or "Cooldown Complete")
        else timers.loading:Start(interval) end
    end
    timers.loading:Start(interval)
    debugPrint("Loading bar started ("..duration.."s)")
end

reflectPowerState = function(isOn, source)
    startLoadingBar(isOn)
    btnNavEventHandler(isOn and kLayer.Warming or kLayer.Cooling, source)
end

local function isOnRoomCombiningLayer()
    return state.activeLayer == kLayer.RoomCombining
end

resetTouchInactivityTimer = function()
    if not timers.inactivity then return end
    timers.inactivity:Stop()
    if not isOnRoomCombiningLayer() then return end
    local timeout = tonumber(Uci.Variables.numTouchInactivityTimer and Uci.Variables.numTouchInactivityTimer.Value) or 60
    if timeout <= 0 then timeout = 60 end
    timers.inactivity.EventHandler = function()
        if not isOnRoomCombiningLayer() then return end
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
    startSystem()
end

btnNavEventHandler = function(layerIndex, source)
    source = source or "Navigation"
    local prev = state.activeLayer
    state.activeLayer = layerIndex
    if components.videoSwitcher and components.switcherType then
        switchToInput(layerIndex)
    end
    showLayer()
    interlock()
    debugPrint("Layer "..prev.." → "..layerIndex.." (Source: "..source..")")
end

local function updateLegends()
    for i, lbl in ipairs(arrUCILegends or {}) do
        if lbl and arrUCIUserLabels and arrUCIUserLabels[i] then
            setProp(lbl, "Legend", arrUCIUserLabels[i].String or "")
        end
    end
end

local function initLegendArrays()
    local legendConfig = {
        {prefix="txtNav", count=15},
        {single={"txtNavShutdown","txtRoomNameNav","txtRoomNameStart","txtRoutingRooms","txtRoutingSources"}},
        {prefix="txtRouting", count=12}, {prefix="txtVidSrc", count=12},
        {single={"txtGainPGM"}}, {prefix="txtGain", count=10}, {prefix="txtDisplay", count=12}
    }
    local idx = 0
    local function labelVarName(ctrlName)
        return "txtLabel"..(ctrlName:gsub("^txt", "") or ctrlName)
    end
    for _, cfg in ipairs(legendConfig) do
        if cfg.prefix then
            for i = 1, cfg.count do
                idx = idx + 1
                local name = cfg.prefix..string.format("%02d", i)
                arrUCILegends[idx] = Controls[name]
                arrUCIUserLabels[idx] = Uci.Variables[labelVarName(name)]
            end
        elseif cfg.single then
            for _, name in ipairs(cfg.single) do
                idx = idx + 1
                arrUCILegends[idx] = Controls[name]
                arrUCIUserLabels[idx] = Uci.Variables[labelVarName(name)]
            end
        end
    end
    for i, label in ipairs(arrUCIUserLabels or {}) do
        if label then label.EventHandler = function() updateLegends() end end
    end
    debugPrint("Legends: "..#(arrUCILegends or {}).." controls")
end

-------------------[ Events ]-------------------
local function registerEvents()
    local navCount = bindArray(controls.btnNav, function(i) btnNavEventHandler(i, "User Button") end)
    debugPrint("Registered "..navCount.." nav handlers")

    local helpUpdateFns = {
        LaptopA=function() updateSourceHelpState("LaptopA") end, LaptopB=function() updateSourceHelpState("LaptopB") end,
        PCA=function() updateSourceHelpState("PCA") end, PCB=function() updateSourceHelpState("PCB") end,
        WirelessA=updateWirelessHelpState, WirelessB=updateWirelessHelpState,
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

    local function onHDMIActive(ctl, layer)
        if ctl.Boolean then ensureSystemIsOn(layer); btnNavEventHandler(layer, "HDMI Active") end
    end
    local function onUSBChange(ctl, layer)
        if ctl.Boolean then ensureSystemIsOn(layer) else updateConferenceState() end
    end
    for name in pairs(configSource) do
        local hdmiCtrl = controls["pinLEDHDMIActive"..name]
        if hdmiCtrl then bind(hdmiCtrl, function(ctl) onHDMIActive(ctl, kLayer[name]) end) end
        local usbCtrl = controls["pinLEDUSB"..name]
        if usbCtrl then bind(usbCtrl, function(ctl) onUSBChange(ctl, kLayer[name]) end) end
    end

    bind(controls.pinLEDACPRBypassSeparated, function() updateACPRBypassState() end)
    bind(controls.pinLEDACPRBypassCombined, function() updateACPRBypassState() end)
    bind(controls.pinLEDPresetSaved, function() updatePresetSavedState() end)
    bind(controls.pinCallActive, function() updateCallActiveState() end)
    if controls.pinLEDTouchActivity then bind(controls.pinLEDTouchActivity, function() resetTouchInactivityTimer() end) end

    local function onHDMIConnected()
        if state.activeLayer == kLayer.PCA or state.activeLayer == kLayer.PCB then
            updateHDMIForActiveSource(); updateConferenceState(); updateConferenceControlsLayer()
        elseif state.activeLayer == kLayer.LaptopA or state.activeLayer == kLayer.LaptopB then
            updateHDMIForActiveSource()
        end
    end
    for name in pairs(configSource) do
        local ctrl = controls["pinLEDHDMIConnected"..name]
        if ctrl then bind(ctrl, onHDMIConnected) end
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
        state.activeLayer = getDefaultLayerAfterWarming()
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
    initLegendArrays()
    initRoomControls()
    initVideoSwitcher()
    initDivisibleSpace()
    registerEvents()
    initSyncFromSystemController()

    for _, idx in ipairs(config.navHidden) do
        local btn = controls.btnNav and controls.btnNav[idx]
        if btn then btn.Visible = false; debugPrint("Hidden nav: "..idx) end
    end

    showLayer()
    interlock()
    updateLegends()
    updateStartSystemLegend()

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
        for _, label in ipairs(arrUCIUserLabels or {}) do
            if label then label.EventHandler = nil end
        end
        if components.btnRoomState then
            for _, btn in ipairs(components.btnRoomState) do
                if btn then btn.EventHandler = nil end
            end
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
        init()
    end)
    if ok then
        print("✓ UCIController (DivisibleSpace) initialized for "..pn)
        break
    end
    print("UCI attempt for '"..pn.."': "..tostring(err))
end

if not ok then
    print("✗ ERROR: UCIController (DivisibleSpace) failed: "..tostring(err))
end
