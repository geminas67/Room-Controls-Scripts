--[[
  UCI Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 5.1 | Date: 2026-07-03
  Firmware Req: 10.4

  Flat structured UCI controller with direct handlers, reconciled layer visibility,
  room power sync, passcode support, legend sync, and video switcher auto-detect.
]]--

-------------------[ Configuration ]-------------------

local conferenceStateConfig = { skip = { [7] = true, [8] = true, [9] = true } }
local acprConfig = { disableACPRShow = true }

local layersBase = { "X01-ProgramVolume", "Y01-Navbar", "Z01-Base" }
local layersToHide = {
  "A01-Alarm","B01-IncomingCall","C05-Start","D01-ShutdownConfirm",
  "E01-SystemProgressWarming","E02-SystemProgressCooling","E05-SystemProgress",
  "H01-PasscodeEntry","H10-RoomControls",
  "I01-CallActive","I02-HelpLaptop","I03-HelpPC","I04-HelpWireless","I05-HelpRouting","I07-HelpStreamMusic",
  "J01-ConnectUSBLaptop","J02-ConnectUSBPC","J03-ACPRActive","J04-CamPresetSaved","J09-ConferenceLaptop","J10-ConferencePC",
  "L01-HDMIDisc","L05-Laptop","P01-HDMIDisc","P05-PC","W01-HDMIDisc","W05-Wireless",
  "R01-Routing01","R02-Routing02","R03-Routing03","R04-Routing04","R05-Routing05","R10-Routing",
  "S05-StreamMusic","V05-Dialer"
}
local routingLayers = { "R01-Routing01", "R02-Routing02", "R03-Routing03", "R04-Routing04", "R05-Routing05" }
local usbConnectLayers = { "J01-ConnectUSBLaptop", "J02-ConnectUSBPC" }

local SwitcherTypes = {
  NV32 = {
    componentType = "streamer_hdmi_switcher",
    switcherNames = { "devNV32", "compNV32" },
    routingMethod = "hdmi.out.1.select.index",
    defaultMapping = { [7] = 7, [8] = 8, [9] = 9 }
  },
  ExtronDXP = {
    componentType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    switcherNames = { "devExtronDXP", "compExtronDXP" },
    routingMethod = "output.1",
    defaultMapping = { [7] = 2, [8] = 4, [9] = 1 }
  },
  AVProEdge = {
    componentType = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
    switcherNames = { "devAVProEdge", "compAVProEdge" },
    routingMethod = "trigger",
    defaultMapping = { [7] = "Input 3", [8] = "Input 4", [9] = "Input 1", [10] = "Input 2" }
  }
}

local kLayer = {
  Alarm = 1,
  IncomingCall = 2,
  Start = 3,
  Warming = 4,
  Cooling = 5,
  RoomControls = 6,
  PC = 7,
  Laptop = 8,
  Wireless = 9,
  Routing = 10,
  Dialer = 11,
  StreamMusic = 12,
  Passcode = 13
}

local configSource = {
  PC = {
    layer = kLayer.PC,
    hdmiKey = "pinLEDHDMI01Connect",
    usbKey = "pinLEDUSBPC",
    base = "P05-PC",
    disc = "P01-HDMIDisc",
    usb = "J02-ConnectUSBPC",
    conf = "J10-ConferencePC",
    help = "I03-HelpPC"
  },
  Laptop = {
    layer = kLayer.Laptop,
    hdmiKey = "pinLEDHDMI02Connect",
    usbKey = "pinLEDUSBLaptop",
    base = "L05-Laptop",
    disc = "L01-HDMIDisc",
    usb = "J01-ConnectUSBLaptop",
    conf = "J09-ConferenceLaptop",
    help = "I02-HelpLaptop"
  },
  Wireless = {
    layer = kLayer.Wireless,
    hdmiKey = "pinLEDHDMI03Connect",
    usbKey = nil,
    base = "W05-Wireless",
    disc = "W01-HDMIDisc",
    usb = nil,
    conf = nil,
    help = "I04-HelpWireless"
  }
}

-------------------[ Constant Tables ]-------------------

local controls = {
  btnNav = {
    Controls.btnNav01, Controls.btnNav02, Controls.btnNav03, Controls.btnNav04, Controls.btnNav05, Controls.btnNav06,
    Controls.btnNav07, Controls.btnNav08, Controls.btnNav09, Controls.btnNav10, Controls.btnNav11, Controls.btnNav12, Controls.btnNav13
  },
  btnStartSystem = Controls.btnStartSystem,
  btnNavShutdown = Controls.btnNavShutdown,
  btnShutdownCancel = Controls.btnShutdownCancel,
  btnShutdownConfirm = Controls.btnShutdownConfirm,

  btnOpenHelp = {
    Laptop = Controls.btnOpenHelpLaptop,
    PC = Controls.btnOpenHelpPC,
    Wireless = Controls.btnOpenHelpWireless,
    Routing = Controls.btnOpenHelpRouting,
    StreamMusic = Controls.btnOpenHelpStreamMusic
  },
  btnCloseHelp = {
    Laptop = Controls.btnCloseHelpLaptop,
    PC = Controls.btnCloseHelpPC,
    Wireless = Controls.btnCloseHelpWireless,
    Routing = Controls.btnCloseHelpRouting,
    StreamMusic = Controls.btnCloseHelpStreamMusic
  },

  btnRouting = { Controls.btnRouting01, Controls.btnRouting02, Controls.btnRouting03, Controls.btnRouting04, Controls.btnRouting05 },

  knbProgressBar = Controls.knbProgressBar,
  txtProgressBar = Controls.txtProgressBar,

  pinCallActive = Controls.pinCallActive,
  pinLEDUSBLaptop = Controls.pinLEDUSBLaptop,
  pinLEDUSBPC = Controls.pinLEDUSBPC,
  pinLEDOffHookLaptop = Controls.pinLEDOffHookLaptop,
  pinLEDOffHookPC = Controls.pinLEDOffHookPC,
  pinLEDHDMI01Active = Controls.pinLEDHDMI01Active,
  pinLEDHDMI02Active = Controls.pinLEDHDMI02Active,
  pinLEDHDMI03Active = Controls.pinLEDHDMI03Active,
  pinLEDPresetSaved = Controls.pinLEDPresetSaved,
  pinLEDHDMI01Connect = Controls.pinLEDHDMI01Connect,
  pinLEDHDMI02Connect = Controls.pinLEDHDMI02Connect,
  pinLEDHDMI03Connect = Controls.pinLEDHDMI03Connect,
  pinLEDACPRBypassActive = Controls.pinLEDACPRBypassActive,
  pinLEDTouchActivity = Controls.pinLEDTouchActivity
}

local components = {
  roomControls = nil,
  prevPowerState = nil,
  videoSwitcher = nil,
  switcherType = nil,
  uciToInputMapping = {},
  passcode = nil,
  passcodeRoom = nil,
  passcodeEnabled = false
}

local state = {
  activeLayer = kLayer.Start,
  activeRoutingLayer = 1,
  callActive = false,
  isAnimating = false,
  isInitialized = false,
  layerStates = {}
}

local timers = {
  loading = nil,
  timeout = nil,
  inactivity = Timer.New()
}

local config = {
  pageUCI = nil,
  debug = true,
  defaultRouting = tonumber(Uci.Variables.numDefaultRoutingLayer and Uci.Variables.numDefaultRoutingLayer.Value) or 4,
  defaultLayer = tonumber(Uci.Variables.numDefaultActiveLayer and Uci.Variables.numDefaultActiveLayer.Value) or 8,
  navHidden = {}
}

local sources = {}
local layerConfigs = {}
local arrUCILegends = {}
local arrUCIUserLabels = {}

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugPrint(str)
  if config.debug then
    print("[" .. tostring(config.pageUCI or "UCI") .. "] " .. str)
  end
end

function stopTimer(timer)
  if timer then timer:Stop() end
  return nil
end

function validateControls()
  local missing = {}
  local optional = { pinLEDTouchActivity = true }

  for name, ctrl in pairs(controls) do
    if type(ctrl) == "table" then
      for key, sub in pairs(ctrl) do
        if not sub then
          table.insert(missing, name .. "[" .. tostring(key) .. "]")
        end
      end
    elseif not ctrl and not optional[name] then
      table.insert(missing, name)
    end
  end

  if #missing > 0 then
    print("ERROR: UCIController validation failed - Missing required controls:")
    for _, name in ipairs(missing) do print("  - " .. name) end
    return false
  end

  return true
end

function resolvePageName(hint)
  local pages = Uci.GetUciPages()
  if not pages or #pages == 0 then return nil end
  if not hint or hint == "" then return pages[1].Name end

  local hintLower = hint:lower()
  for _, page in ipairs(pages) do
    local nameLower = page.Name:lower()
    if nameLower == hintLower or nameLower:find(hintLower, 1, true) or hintLower:find(nameLower, 1, true) then
      return page.Name
    end
  end

  return pages[1].Name
end

function collectConfiguredLayerNames()
  local seen, out = {}, {}

  local function add(name)
    if name and name ~= "" and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end

  for _, name in ipairs(layersBase) do add(name) end
  for _, name in ipairs(layersToHide) do add(name) end
  for _, name in ipairs(routingLayers) do add(name) end
  for _, def in pairs(configSource) do
    add(def.base)
    add(def.disc)
    add(def.usb)
    add(def.conf)
    add(def.help)
  end

  return out
end

function validateLayersAtInit(pageName)
  local inDesign = {}
  for _, layer in ipairs(Uci.GetUciPageLayers(pageName)) do
    inDesign[layer.Name] = true
  end

  local missing = {}
  for _, name in ipairs(collectConfiguredLayerNames()) do
    if not inDesign[name] then
      missing[#missing + 1] = name
    end
  end

  if #missing > 0 then
    print("WARNING [" .. pageName .. "]: configured layers not found in UCI design:")
    for _, name in ipairs(missing) do print("  - " .. name) end
  end
end

function extractRoomFromPageName()
  local room = config.pageUCI:match("^uci%s*(.+)$")
  if not room then return nil end
  room = room:match("^%s*(.-)%s*$")
  components.passcodeRoom = room
  return room
end

-------------------[ Discovery ]-------------------

function buildSources()
  sources = {}
  for name, def in pairs(configSource) do
    sources[name] = {
      layerConst = def.layer,
      hdmiPin = controls[def.hdmiKey],
      usbPin = def.usbKey and controls[def.usbKey],
      baseLayer = def.base,
      discLayer = def.disc,
      usbConnect = def.usb,
      confLayer = def.conf,
      helpLayer = def.help,
      btnOpen = controls.btnOpenHelp[name],
      btnClose = controls.btnCloseHelp[name]
    }
  end

  sources._layerToSource = {}
  for name, src in pairs(sources) do
    if src.layerConst then
      sources._layerToSource[src.layerConst] = name
    end
  end
end

function buildLayerConfigs()
  layerConfigs = {
    [kLayer.Alarm] = { show = { "A01-Alarm" }, hideBase = true },
    [kLayer.IncomingCall] = { show = { "B01-IncomingCall" } },
    [kLayer.Start] = { show = { "C05-Start" }, hideBase = true },
    [kLayer.Warming] = { show = { "E05-SystemProgress", "E01-SystemProgressWarming" }, hideBase = true },
    [kLayer.Cooling] = { show = { "E05-SystemProgress", "E02-SystemProgressCooling" }, hideBase = true },
    [kLayer.RoomControls] = { show = { "H10-RoomControls" }, hide = { "X01-ProgramVolume" } },
    [kLayer.Laptop] = { show = { "L05-Laptop" } },
    [kLayer.PC] = { show = { "P05-PC" } },
    [kLayer.Wireless] = { show = { "W05-Wireless" } },
    [kLayer.Routing] = { show = { "R10-Routing" } },
    [kLayer.Dialer] = { show = { "V05-Dialer" } },
    [kLayer.StreamMusic] = { show = { "S05-StreamMusic" } },
    [kLayer.Passcode] = { show = { "H01-PasscodeEntry" }, hideBase = true }
  }
end

function initVideoSwitcher()
  for swType, swConfig in pairs(SwitcherTypes) do
    for _, name in ipairs(swConfig.switcherNames) do
      local ctrl = Controls[name]
      if ctrl and ctrl.String and ctrl.String ~= "" then
        local ok, comp = pcall(function() return Component.New(ctrl.String) end)
        if ok and comp then
          components.videoSwitcher = comp
          components.switcherType = swType
          components.uciToInputMapping = swConfig.defaultMapping
          debugPrint("Video switcher: " .. swType)
          return true
        end
      end
    end
  end

  for _, comp in pairs(Component.GetComponents()) do
    for swType, swConfig in pairs(SwitcherTypes) do
      if comp.Type == swConfig.componentType then
        local ok, c = pcall(function() return Component.New(comp.Name) end)
        if ok and c then
          components.videoSwitcher = c
          components.switcherType = swType
          components.uciToInputMapping = swConfig.defaultMapping
          debugPrint("Video switcher: " .. swType .. " (auto-detect)")
          return true
        end
      end
    end
  end

  return false
end

function initRoomControls()
  local compName = Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String

  if not compName then
    local page = config.pageUCI:match("uci%s+([^(]+)")
    if page then
      compName = "compRoomControls" .. page:gsub("%s+", "")
    end
  end

  if not compName then return false end

  local ok, comp = pcall(function() return Component.New(compName) end)
  if not ok or not comp then
    debugPrint("Room Controls not found: " .. tostring(compName))
    return false
  end

  components.roomControls = comp
  components.prevPowerState = comp["ledSystemPower"] and comp["ledSystemPower"].Boolean or nil

  if comp["ledSystemPower"] then
    comp["ledSystemPower"].EventHandler = function(ctl)
      local cur = ctl.Boolean
      if cur == components.prevPowerState then return end
      components.prevPowerState = cur
      reflectPowerState(cur, cur and "Room Automation Power On" or "Room Automation Power Off")
    end
  end

  return true
end

function initPasscode()
  if not extractRoomFromPageName() then return false end

  local compName = "passcode" .. components.passcodeRoom
  local ok, comp = pcall(function() return Component.New(compName) end)
  if not ok or not comp then
    debugPrint("Passcode not found: " .. compName .. " (disabled)")
    return false
  end

  components.passcode = comp
  components.passcodeEnabled = true

  if comp["PasscodeCorrect"] then
    comp["PasscodeCorrect"].EventHandler = function(ctl)
      if ctl.Boolean then startSystem("Passcode Correct") end
    end
  end

  return true
end

-------------------[ Status ]-------------------

function loadLayerStatesFromUci()
  state.layerStates = {}
  for _, pages in pairs(Uci.GetLayerVisibility()) do
    for page, layers in pairs(pages) do
      if page == config.pageUCI then
        for name, vis in pairs(layers) do
          state.layerStates[name] = vis
        end
      end
    end
  end
end

function reconcileLayers(desired, transitions)
  loadLayerStatesFromUci()

  for name, visible in pairs(desired) do
    if state.layerStates[name] ~= visible then
      local transition = transitions[name] or (visible and "fade" or "none")
      local ok, err = pcall(Uci.SetLayerVisibility, config.pageUCI, name, visible, transition)
      if ok then
        state.layerStates[name] = visible
      else
        debugPrint("Layer '" .. name .. "' error: " .. tostring(err))
      end
    end
  end
end

function getActiveSource()
  local key = sources._layerToSource[state.activeLayer]
  return key and sources[key] or nil
end

function checkHDMIConnection()
  local src = getActiveSource()
  return not src or not src.hdmiPin or src.hdmiPin.Boolean
end

function buildFullDesired()
  local desired, transitions = {}, {}

  for _, name in ipairs(layersToHide) do desired[name] = false end

  local cfg = layerConfigs[state.activeLayer]
  if cfg then
    local baseVisible = not cfg.hideBase
    for _, name in ipairs(layersBase) do
      desired[name] = baseVisible
      transitions[name] = baseVisible and "fade" or "none"
    end
    if cfg.show then
      for _, name in ipairs(cfg.show) do
        desired[name] = true
        transitions[name] = "fade"
      end
    end
    if cfg.hide then
      for _, name in ipairs(cfg.hide) do
        desired[name] = false
      end
    end
  end

  state.callActive = controls.pinCallActive and controls.pinCallActive.Boolean or false
  desired["I01-CallActive"] = state.callActive
  transitions["I01-CallActive"] = state.callActive and "fade" or "none"

  local presetSaved = controls.pinLEDPresetSaved and controls.pinLEDPresetSaved.Boolean or false
  desired["J04-CamPresetSaved"] = presetSaved
  transitions["J04-CamPresetSaved"] = presetSaved and "fade" or "none"

  if state.activeLayer == kLayer.Routing then
    if state.activeRoutingLayer < 1 or state.activeRoutingLayer > #routingLayers then
      state.activeRoutingLayer = 1
    end
    desired["X01-ProgramVolume"] = false
    for i, name in ipairs(routingLayers) do
      desired[name] = (i == state.activeRoutingLayer)
      transitions[name] = desired[name] and "fade" or "none"
    end
    desired["I05-HelpRouting"] = controls.btnOpenHelp.Routing and controls.btnOpenHelp.Routing.Boolean or false
  end

  if state.activeLayer == kLayer.StreamMusic then
    desired["I07-HelpStreamMusic"] = controls.btnOpenHelp.StreamMusic and controls.btnOpenHelp.StreamMusic.Boolean or false
  end

  local src = getActiveSource()
  if src then
    local hdmiOk = checkHDMIConnection()

    if state.activeLayer == kLayer.PC or state.activeLayer == kLayer.Laptop then
      if not hdmiOk then
        desired[src.discLayer] = true
        transitions[src.discLayer] = "fade"
        desired[src.baseLayer] = false
        desired["J03-ACPRActive"] = false
        if src.confLayer then desired[src.confLayer] = false end
        if src.helpLayer then desired[src.helpLayer] = false end
        for _, name in ipairs(usbConnectLayers) do desired[name] = false end
      else
        desired[src.baseLayer] = true
        transitions[src.baseLayer] = "fade"
        desired[src.discLayer] = false

        if not conferenceStateConfig.skip[src.layerConst] then
          local usb = src.usbPin and src.usbPin.Boolean or false
          if usb then
            if src.confLayer then
              desired[src.confLayer] = true
              transitions[src.confLayer] = "fade"
            end
            for _, name in ipairs(usbConnectLayers) do desired[name] = false end
          elseif src.usbConnect then
            desired[src.usbConnect] = true
            transitions[src.usbConnect] = "fade"
            if src.confLayer then desired[src.confLayer] = false end
            if src.helpLayer then desired[src.helpLayer] = false end
          end
        end

        if acprConfig.disableACPRShow then
          desired["J03-ACPRActive"] = false
        else
          local bypass = controls.pinLEDACPRBypassActive and controls.pinLEDACPRBypassActive.Boolean or false
          if not bypass and state.callActive then
            desired["J03-ACPRActive"] = true
            transitions["J03-ACPRActive"] = "fade"
            if src.confLayer then desired[src.confLayer] = false end
          else
            desired["J03-ACPRActive"] = false
            if src.confLayer then
              desired[src.confLayer] = bypass
              transitions[src.confLayer] = bypass and "fade" or "none"
            end
          end
        end

        local helpOpen = src.btnOpen and src.btnOpen.Boolean or false
        if src.helpLayer then
          desired[src.helpLayer] = helpOpen
          transitions[src.helpLayer] = helpOpen and "fade" or "none"
        end
        if helpOpen then
          for _, name in ipairs(usbConnectLayers) do desired[name] = false end
          if src.confLayer then desired[src.confLayer] = false end
        end
      end
    elseif state.activeLayer == kLayer.Wireless then
      local helpOpen = src.btnOpen and src.btnOpen.Boolean or false
      if src.helpLayer then
        desired[src.helpLayer] = helpOpen
        transitions[src.helpLayer] = helpOpen and "fade" or "none"
      end
    end
  end

  return desired, transitions
end

function refreshLayers()
  reconcileLayers(buildFullDesired())
end

-------------------[ Components ]-------------------

function powerOn()
  if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
  components.roomControls["btnSystemOnOff"].Boolean = true
  return true
end

function powerOff()
  if not components.roomControls or not components.roomControls["btnSystemOnOff"] then return false end
  components.roomControls["btnSystemOnOff"].Boolean = false
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
    duration = isPoweringOn
      and (tonumber(Uci.Variables.timeProgressWarming) or 10)
      or (tonumber(Uci.Variables.timeProgressCooling) or 5)
  end
  local steps = 100
  local interval = duration / steps
  local currentStep = 0
  controls.knbProgressBar.Value = isPoweringOn and 0 or 100
  controls.txtProgressBar.String = (isPoweringOn and 0 or 100) .. "%"
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
    controls.knbProgressBar.Value = prog
    controls.txtProgressBar.String = prog .. "%"
    if currentStep >= steps then
      timers.loading = stopTimer(timers.loading)
      timers.timeout = stopTimer(timers.timeout)
      state.isAnimating = false
      btnNavEventHandler(isPoweringOn and config.defaultLayer or kLayer.Start, isPoweringOn and "Warmup Complete" or "Cooldown Complete")
    else
      timers.loading:Start(interval)
    end
  end

  timers.loading:Start(interval)
end

reflectPowerState = function(isOn, source)
  startLoadingBar(isOn)
  btnNavEventHandler(isOn and kLayer.Warming or kLayer.Cooling, source)
end

function startSystem(eventSource)
  powerOn()
  startLoadingBar(true)
  btnNavEventHandler(kLayer.Warming, eventSource or "System Start")
end

function shutdownSystem()
  powerOff()
  startLoadingBar(false)
  btnNavEventHandler(kLayer.Cooling, "System Shutdown")
end

function isPasscodeCorrect()
  if not components.passcodeEnabled or not components.passcode then return true end
  return not components.passcode["PasscodeCorrect"] or components.passcode["PasscodeCorrect"].Boolean
end

function ensureSystemIsOn(targetLayer)
  targetLayer = targetLayer or config.defaultLayer

  if components.roomControls and components.roomControls["ledSystemPower"] and components.roomControls["ledSystemPower"].Boolean then
    btnNavEventHandler(targetLayer, "Source Active")
    return
  end

  if components.passcodeEnabled and not isPasscodeCorrect() then
    btnNavEventHandler(kLayer.Passcode, "Passcode Required")
    return
  end

  startSystem()
end

function resetTouchInactivityTimer()
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

function syncRoomControlsState()
  if not components.roomControls or not components.roomControls["ledSystemPower"] then return end
  local cur = components.roomControls["ledSystemPower"].Boolean
  if cur == components.prevPowerState then return end
  debugPrint("Sync: "..tostring(components.prevPowerState).." → "..tostring(cur))
  components.prevPowerState = cur
  reflectPowerState(cur, "Room Automation Sync")
end

function switchToInput(inputNumber)
  if not components.videoSwitcher or not components.switcherType then return false end

  local swConfig = SwitcherTypes[components.switcherType]
  if not swConfig then return false end

  return pcall(function()
    if components.switcherType == "NV32" then
      components.videoSwitcher[swConfig.routingMethod].Value = inputNumber
    else
      components.videoSwitcher[swConfig.routingMethod].String = tostring(inputNumber)
    end
  end)
end

function interlock()
  for i, btn in ipairs(controls.btnNav) do
    if btn then btn.Boolean = (i == state.activeLayer) end
  end
end

function interlockRouting()
  for i, btn in ipairs(controls.btnRouting) do
    if btn then btn.Boolean = (i == state.activeRoutingLayer) end
  end
end

function btnNavEventHandler(layerIndex, source)
  local prev = state.activeLayer
  state.activeLayer = layerIndex

  if layerIndex == kLayer.Passcode then resetTouchInactivityTimer() end

  local inputNumber = components.uciToInputMapping[layerIndex]
  if inputNumber then switchToInput(inputNumber) end

  refreshLayers()
  interlock()
  debugPrint("Layer " .. prev .. " → " .. layerIndex .. " (" .. tostring(source or "Navigation") .. ")")
end

function routingButtonHandler(buttonIndex)
  if buttonIndex < 1 or buttonIndex > #routingLayers then return end
  state.activeRoutingLayer = buttonIndex
  refreshLayers()
  interlockRouting()
end

function updateLegends()
  for i, lbl in ipairs(arrUCILegends) do
    if lbl and arrUCIUserLabels[i] then
      lbl.Legend = arrUCIUserLabels[i].String or ""
    end
  end
end

function initLegendArrays()
  local legendConfig = {
    { suffix = "Nav", count = 13 },
    { suffix = "Routing", count = 5 },
    { suffix = "VidSrc", count = 12 },
    { suffix = "Gain", count = 10 },
    { suffix = "Display", count = 4 },
    { single = { "NavShutdown", "RoomNameNav", "RoomNameStart", "RoutingRooms", "RoutingSources", "GainPGM" } }
  }

  local idx = 0
  for _, cfg in ipairs(legendConfig) do
    if cfg.suffix then
      for i = 1, cfg.count do
        idx = idx + 1
        local name = cfg.suffix .. string.format("%02d", i)
        arrUCILegends[idx] = Controls["txt" .. name]
        arrUCIUserLabels[idx] = Uci.Variables["txtLabel" .. name]
      end
    else
      for _, name in ipairs(cfg.single) do
        idx = idx + 1
        arrUCILegends[idx] = Controls["txt" .. name]
        arrUCIUserLabels[idx] = Uci.Variables["txtLabel" .. name]
      end
    end
  end

  for _, label in ipairs(arrUCIUserLabels) do
    if label then label.EventHandler = updateLegends end
  end
end

-------------------[ Event Handlers ]-------------------

for i, btn in ipairs(controls.btnNav) do
  if btn then btn.EventHandler = function() btnNavEventHandler(i, "User Button") end end
end

for i, btn in ipairs(controls.btnRouting) do
  if btn then btn.EventHandler = function() routingButtonHandler(i) end end
end

controls.btnStartSystem.EventHandler = function()
  ensureSystemIsOn(config.defaultLayer)
end

controls.btnNavShutdown.EventHandler = function()
  reconcileLayers({ ["D01-ShutdownConfirm"] = true }, { ["D01-ShutdownConfirm"] = "fade" })
end

controls.btnShutdownCancel.EventHandler = function()
  reconcileLayers({ ["D01-ShutdownConfirm"] = false }, { ["D01-ShutdownConfirm"] = "fade" })
end

controls.btnShutdownConfirm.EventHandler = function()
  shutdownSystem()
end

for name, src in pairs(sources) do
  if name ~= "_layerToSource" then
    if src.btnOpen then
      src.btnOpen.EventHandler = function()
        if src.btnClose then src.btnClose.Boolean = false end
        refreshLayers()
      end
    end

    if src.btnClose then
      src.btnClose.EventHandler = function()
        if src.btnOpen then src.btnOpen.Boolean = false end
        refreshLayers()
      end
    end

    if src.hdmiPin then
      src.hdmiPin.EventHandler = refreshLayers
    end

    if src.usbPin then
      src.usbPin.EventHandler = function(ctl)
        if ctl.Boolean then
          ensureSystemIsOn(src.layerConst)
        else
          refreshLayers()
        end
      end
    end
  end
end

if controls.btnOpenHelp.Routing then
  controls.btnOpenHelp.Routing.EventHandler = function()
    if controls.btnCloseHelp.Routing then controls.btnCloseHelp.Routing.Boolean = false end
    refreshLayers()
  end
end

if controls.btnCloseHelp.Routing then
  controls.btnCloseHelp.Routing.EventHandler = function()
    if controls.btnOpenHelp.Routing then controls.btnOpenHelp.Routing.Boolean = false end
    refreshLayers()
  end
end

if controls.btnOpenHelp.StreamMusic then
  controls.btnOpenHelp.StreamMusic.EventHandler = function()
    if controls.btnCloseHelp.StreamMusic then controls.btnCloseHelp.StreamMusic.Boolean = false end
    refreshLayers()
  end
end

if controls.btnCloseHelp.StreamMusic then
  controls.btnCloseHelp.StreamMusic.EventHandler = function()
    if controls.btnOpenHelp.StreamMusic then controls.btnOpenHelp.StreamMusic.Boolean = false end
    refreshLayers()
  end
end

if controls.pinLEDACPRBypassActive then controls.pinLEDACPRBypassActive.EventHandler = refreshLayers end
if controls.pinLEDPresetSaved then controls.pinLEDPresetSaved.EventHandler = refreshLayers end
if controls.pinCallActive then controls.pinCallActive.EventHandler = refreshLayers end

if controls.pinLEDOffHookLaptop then
  controls.pinLEDOffHookLaptop.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(kLayer.Laptop) end
  end
end

if controls.pinLEDOffHookPC then
  controls.pinLEDOffHookPC.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(kLayer.PC) end
  end
end

if controls.pinLEDHDMI01Active then
  controls.pinLEDHDMI01Active.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(kLayer.PC) end
  end
end

if controls.pinLEDHDMI02Active then
  controls.pinLEDHDMI02Active.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(kLayer.Laptop) end
  end
end

if controls.pinLEDHDMI03Active then
  controls.pinLEDHDMI03Active.EventHandler = function(ctl)
    if ctl.Boolean then ensureSystemIsOn(kLayer.Wireless) end
  end
end

if controls.pinLEDTouchActivity then
  controls.pinLEDTouchActivity.EventHandler = resetTouchInactivityTimer
end

-------------------[ Always Run ]-------------------

function funcInit()
  loadLayerStatesFromUci()
  state.activeLayer = kLayer.Start
  state.activeRoutingLayer = config.defaultRouting

  buildSources()
  buildLayerConfigs()
  initLegendArrays()
  initRoomControls()
  initVideoSwitcher()
  initPasscode()

  if mySystemController and mySystemController.state then
    local powered = components.roomControls and components.roomControls["ledSystemPower"] and components.roomControls["ledSystemPower"].Boolean
    if powered then
      if mySystemController.state.isWarming then
        state.activeLayer = kLayer.Warming
        startLoadingBar(true)
      else
        state.activeLayer = config.defaultLayer
      end
    else
      state.activeLayer = kLayer.Start
    end
  end

  for _, idx in ipairs(config.navHidden) do
    local btn = controls.btnNav[idx]
    if btn then btn.Visible = false end
  end

  refreshLayers()
  interlock()
  interlockRouting()
  updateLegends()
  state.isInitialized = true
end

myUCI = {
  btnNavEventHandler = btnNavEventHandler,
  syncRoomControlsState = syncRoomControlsState,
  refreshLayers = refreshLayers,
  switchToInput = switchToInput,
  powerOn = powerOn,
  powerOff = powerOff,
  startLoadingBar = startLoadingBar,
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
    for _, label in ipairs(arrUCIUserLabels) do
      if label then label.EventHandler = nil end
    end
  end
}

local ok, err = pcall(function()
  if not validateControls() then error("Control validation failed") end

  local hint = Uci.Variables.txtUCIPageName and Uci.Variables.txtUCIPageName.String or ""
  config.pageUCI = resolvePageName(hint)
  if not config.pageUCI then error("Uci.GetUciPages returned no pages") end

  validateLayersAtInit(config.pageUCI)
  funcInit()
end)

if ok then
  print("✓ UCIController initialized for " .. config.pageUCI)
else
  print("✗ ERROR: UCIController failed: " .. tostring(err))
end
