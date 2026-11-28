--[[
  System Automation Controller (Lean) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 2.2 | Date: 2026-11-27
  Firmware Req: 10.4
  Power, audio, video privacy (off.hook), displays, motion, multi-gain, ACPR
  2.2: each decision stated once (presets, config, one-or-all loops, handler wiring)
]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  callSync    = "call_sync",
  videoBridge = "usb_uvc",
  displays    = "%PLUGIN%_bd0a5e74-c1bf-48ee-8574-e42e1e7b2bb9_%FP%_31e2e2d7be2243768d2bd9c853a6295c",
  gains       = "gain",
  systemMute  = "system_mute",
  camACPR     = "%PLUGIN%_6ddbd63b-ebb6-43ed-9c5a-9a7d6dac6f37_%FP%_22bcd2049cd1e9c1f02a4e76655c2db4",
}

-- room presets: every preset starts from presetBase, then applies its overrides
presetNames = { "Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined" }
presetBase = {
  debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30,
  defaultProgramVolume = 0.7, defaultMicVolume = 0.5, defaultGainVolume = 0.7,
}
presetOverrides = {
  ["Conference Room"] = { warmupTime = 15, cooldownTime = 10, motionTimeout = 600, gracePeriod = 60 },
  ["Huddle Room"]     = { debugging = false, warmupTime = 5, cooldownTime = 3, defaultProgramVolume = 0.6 },
}

gainTypeAssignment = {
  ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
  ["Huddle Room"]     = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
  ["Custom Room"]     = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
  ["Default"]         = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" },
}

btnMuteShell = "button-square-red-big-icon"
gainTypeIcon = { Mic = "iconmicoutline", Program = "iconvolumemuteoutline", Gain = "iconvolumemuteoutline" }

MotionChoices = { "Motion On/Off", "Motion Off", "Motion Disabled" }

-- User Defined value controls -> config keys
configValueMaps = {
  { control = "warmupTime",           config = "warmupTime" },
  { control = "cooldownTime",         config = "cooldownTime" },
  { control = "motionTimeout",        config = "motionTimeout" },
  { control = "motionGracePeriod",    config = "gracePeriod" },
  { control = "defaultProgramVolume", config = "defaultProgramVolume" },
  { control = "defaultMicVolume",     config = "defaultMicVolume" },
  { control = "defaultGainVolume",    config = "defaultGainVolume" },
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compCallSync = nil
compVideoBridge = {}
compGains = {}
compDisplays = {}
compSystemMute = nil
compCamACPR = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[Unknown]"
config = {}         -- active preset; the single source of truth for timings and volumes
defaultConfigs = {}

timerMotion   = Timer.New()
timerGrace    = Timer.New()
timerWarmup   = Timer.New()
timerCooldown = Timer.New()

-------------------[ Functions ]-------------------
-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print(roomName .. " " .. str) end
end

-- Text Controller pins are a single control at count 1 and an array above 1
function asArray(ctrl)
  if not ctrl then return {} end
  if ctrl[1] ~= nil then return ctrl end
  return { ctrl }
end

-- run fn(ctl, i) for every control under one pin name
function forEach(name, fn)
  for i, ctl in ipairs(asArray(Controls[name])) do fn(ctl, i) end
end

-- run fn(i, comp) on one bound component (idx) or all of them (idx = nil)
function eachComp(list, idx, fn)
  for i, comp in pairs(list) do
    if comp ~= nil and (idx == nil or idx == i) then fn(i, comp) end
  end
end

-- Required Text Controller pins; optional pins (notification, ACPR, presets, config values) guarded at use sites
function validateControls()
  local missing = {}
  for _, name in ipairs({
    "roomName", "txtStatus", "compACPR", "compCallSync", "compDisplays", "compGains", "compSystemMute",  "compVideoBridge",
    "btnSystemOnOff", "btnSystemOn", "btnSystemOff", "btnAudioPrivacy", "btnVideoPrivacy", "btnVolumeMute", "btnVolumeDn", "btnVolumeUp",
    "ledSystemPower", "ledSystemWarming", "ledSystemCooling",
    "ledMotionIn", "ledMotionTimeoutActive", "ledMotionGraceActive", "selDefaultConfigs", "txtMotionMode",
    "typeGain", "knbVolumeFader", 
  }) do
    if not Controls[name] then table.insert(missing, name) end
  end
  if #missing == 0 then return true end
  print("ERROR: Missing controls: " .. table.concat(missing, ", "))
  return false
end

-------------------[ Presets ]-------------------

function buildPreset(roomType)
  local preset = {}
  for key, val in pairs(presetBase) do preset[key] = val end
  for key, val in pairs(presetOverrides[roomType] or {}) do preset[key] = val end
  if roomType == "User Defined" then -- seed from the value controls the operator set
    for _, map in ipairs(configValueMaps) do
      if Controls[map.control] then preset[map.config] = Controls[map.control].Value end
    end
  end
  return preset
end

function applyActiveConfig(roomType)
  config = defaultConfigs[roomType] or defaultConfigs["Default"]
  stateDebug = config.debugging ~= false
end

-- show the active preset on the value controls; only User Defined is editable
function updateConfigValueControls(roomType)
  for _, map in ipairs(configValueMaps) do
    if Controls[map.control] then
      Controls[map.control].Value = defaultConfigs[roomType][map.config]
      Controls[map.control].IsDisabled = roomType ~= "User Defined"
    end
  end
end

function initConfigPresets()
  for _, name in ipairs(presetNames) do defaultConfigs[name] = buildPreset(name) end
  applyActiveConfig(Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String or "Default")
end

-------------------[ Status ]-------------------

function getStatus()
  for _, invalid in pairs(compInvalid) do
    if invalid then
      Controls['txtStatus'].String = "Invalid Components"
      Controls['txtStatus'].Value = 1
      return
    end
  end
  Controls['txtStatus'].String = "OK"
  Controls['txtStatus'].Value = 0
end

-- bind the component named in a selector; returns nil when cleared or invalid
function setComp(ctl, componentType)
  local name = ctl.String
  if name == "" or name == strClear then
    ctl.String = ""
    ctl.Color = "white"
    compInvalid[componentType] = false
    getStatus()
    debugMsg("No " .. componentType .. " selected")
    return nil
  end
  local comp = Component.New(name)
  if #Component.GetControls(comp) < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    compInvalid[componentType] = true
    getStatus()
    debugMsg("ERROR: Invalid " .. componentType .. ": " .. name)
    return nil
  end
  ctl.Color = "white"
  compInvalid[componentType] = false
  getStatus()
  debugMsg("Connected " .. componentType .. ": " .. name)
  return comp
end

-------------------[ Notifications ]-------------------

function publishNotification()
  if not Controls['txtNotificationID'] or Controls['txtNotificationID'].String == "" then return end
  local vbBtns = asArray(Controls['btnVideoPrivacy'])
  local systemState = {
    RoomName      = roomName,
    PowerState    = Controls['ledSystemPower'].Boolean,
    SystemWarming = Controls['ledSystemWarming'].Boolean,
    SystemCooling = Controls['ledSystemCooling'].Boolean,
    AudioPrivacy  = Controls['btnAudioPrivacy'].Boolean,
    VideoPrivacy  = vbBtns[1] ~= nil and vbBtns[1].Boolean or false,
    ACPRState     = compCamACPR ~= nil and compCamACPR["TrackingBypass"].Boolean or false,
    Timestamp     = os.time(),
    GainControls  = {},
  }
  eachComp(compGains, nil, function(i, gain)
    systemState.GainControls[i] = { Level = gain["gain"].Position, Muted = gain["mute"].Boolean }
  end)
  Notifications.Publish(Controls['txtNotificationID'].String, systemState)
end

-------------------[ Discovery ]-------------------

-- fill every component selector with matching names from the design
function getComponentNames()
  local names = {}
  for key in pairs(componentTypes) do names[key] = {} end
  for _, comp in pairs(Component.GetComponents()) do
    for key, compType in pairs(componentTypes) do
      if comp.Type == compType then table.insert(names[key], comp.Name) end
    end
  end
  for _, list in pairs(names) do table.sort(list); table.insert(list, strClear) end
  Controls['compCallSync'].Choices = names.callSync
  if Controls['compSystemMute'] then Controls['compSystemMute'].Choices = names.systemMute end
  if Controls['compACPR'] then Controls['compACPR'].Choices = names.camACPR end
  forEach('compVideoBridge', function(ctl) ctl.Choices = names.videoBridge end)
  forEach('compGains', function(ctl) ctl.Choices = names.gains end)
  forEach('devDisplays', function(ctl) ctl.Choices = names.displays end)
  debugMsg("Discovery: " .. (#names.callSync - 1) .. " callSync, " .. (#names.videoBridge - 1) .. " videoBridge, "
    .. (#names.gains - 1) .. " gains, " .. (#names.displays - 1) .. " displays")
end

-------------------[ Gain types & visuals ]-------------------

function getGainType(idx)
  local types = asArray(Controls['typeGain'])
  if types[idx] then return types[idx].String end
  return idx == 1 and "Program" or "Mic"
end

function getDefaultVolumeForType(gainType)
  if gainType == "Program" then return config.defaultProgramVolume end
  if gainType == "Gain" then return config.defaultGainVolume end
  return config.defaultMicVolume
end

-- gain 1 is always Program; the rest follow the room preset map
function setGainTypeAssignments(roomType)
  roomType = roomType or (Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String) or "Default"
  local assign = gainTypeAssignment[roomType] or gainTypeAssignment["Default"]
  forEach('typeGain', function(ctl, i)
    if assign[i] then
      ctl.String = i == 1 and "Program" or assign[i]
      ctl.IsDisabled = i == 1
    end
  end)
end

-- CSS meter + type icon on the script fader/mute pair
function updateVolumeVisuals(idx)
  local fader = asArray(Controls['knbVolumeFader'])[idx]
  local mute = asArray(Controls['btnVolumeMute'])[idx]
  if not fader or not mute then return end
  local meterClass = mute.Boolean and "meter-muted" or "meter"
  local muteClass = btnMuteShell .. " " .. (gainTypeIcon[getGainType(idx)] or gainTypeIcon.Program)
  if fader.CssClass ~= meterClass then fader.CssClass = meterClass end
  if mute.CssClass ~= muteClass then mute.CssClass = muteClass end
end

function getGainCount()
  local count = 0
  for _ in pairs(compGains) do count = count + 1 end
  return count
end

-------------------[ Volume ]-------------------
-- gainIndex = nil means all gains

function applyVolumeDefaults()
  debugMsg("Applying volume defaults from typeGain")
  eachComp(compGains, nil, function(i, gain)
    local gainType = getGainType(i)
    gain["gain"].Position = getDefaultVolumeForType(gainType)
    updateVolumeVisuals(i)
    debugMsg("Default " .. gainType .. " (" .. gain["gain"].Position .. ") -> gain " .. i)
  end)
end

function setVolume(level, gainIndex)
  eachComp(compGains, gainIndex, function(i, gain)
    gain["gain"].Position = level
    updateVolumeVisuals(i)
  end)
  publishNotification()
end

function setMute(muteState, gainIndex)
  eachComp(compGains, gainIndex, function(i, gain)
    gain["mute"].Boolean = muteState
    updateVolumeVisuals(i)
  end)
  publishNotification()
end

-- ramp while held; any ramp unmutes
function setVolumeUpDown(direction, pressed, gainIndex)
  local action = direction == "up" and "stepper.increase" or "stepper.decrease"
  eachComp(compGains, gainIndex, function(i, gain)
    gain[action].Boolean = pressed
    if pressed then gain["mute"].Boolean = false end
    updateVolumeVisuals(i)
  end)
  publishNotification()
end

-- gain block -> script fader
function getVolumeLvl(idx)
  local fader = asArray(Controls['knbVolumeFader'])[idx]
  if compGains[idx] == nil or not fader then return end
  fader.Position = compGains[idx]["gain"].Position
  updateVolumeVisuals(idx)
  publishNotification()
end

-- gain block -> script mute button
function getVolumeMute(idx)
  local mute = asArray(Controls['btnVolumeMute'])[idx]
  if compGains[idx] == nil or not mute then return end
  local muteState = compGains[idx]["mute"].Boolean
  -- feedback loop: gain mute EventHandler -> this function -> script mute button
  if mute.Boolean ~= muteState then mute.Boolean = muteState end
  updateVolumeVisuals(idx)
  publishNotification()
end

-------------------[ Call sync & privacy ]-------------------

-- call sync mute -> script audio privacy button
function getCallSyncMute()
  if compCallSync == nil then return end
  local muteState = compCallSync["mute"].Boolean
  debugMsg("Call Sync mute: " .. tostring(muteState))
  -- feedback loop: call sync mute EventHandler -> script audio privacy button
  if Controls['btnAudioPrivacy'].Boolean ~= muteState then Controls['btnAudioPrivacy'].Boolean = muteState end
end

-- script/power logic -> call sync mute; button always shows intent
function setCallSyncMute(state)
  if compCallSync ~= nil then
    debugMsg("Setting Call Sync mute: " .. tostring(state))
    compCallSync["mute"].Boolean = state
  end
  Controls['btnAudioPrivacy'].Boolean = state
  publishNotification()
end

-- idx = nil means all bridges
function setVideoPrivacy(state, idx)
  eachComp(compVideoBridge, idx, function(_, bridge) bridge["toggle.privacy"].Boolean = state end)
  publishNotification()
end

-- bridge privacy -> script video privacy button (one shared button covers all bridges)
function getVideoBridgePrivacyState(idx)
  if compVideoBridge[idx] == nil then return end
  local privacyState = compVideoBridge[idx]["toggle.privacy"].Boolean
  debugMsg("Video bridge [" .. idx .. "] privacy: " .. tostring(privacyState))
  local btns = asArray(Controls['btnVideoPrivacy'])
  local btn = btns[idx] or (#btns == 1 and btns[1])
  -- feedback loop: bridge privacy EventHandler -> script video privacy button
  if btn and btn.Boolean ~= privacyState then btn.Boolean = privacyState end
end

function setACPRLegend()
  local bypass = compCamACPR["TrackingBypass"]
  bypass.Legend = bypass.IsDisabled and "Disabled" or (bypass.Boolean and "Off" or "Auto")
end

-- off.hook drives video privacy and camera tracking (cameras only move during calls)
function getCallSyncHookState()
  if compCallSync == nil then return end
  local offHook = compCallSync["off.hook"].Boolean
  getCallSyncMute()
  setVideoPrivacy(not offHook)
  for i in pairs(compVideoBridge) do getVideoBridgePrivacyState(i) end
  if compCamACPR ~= nil then
    compCamACPR["TrackingBypass"].IsDisabled = not offHook
    compCamACPR["TrackingBypass"].Boolean = not offHook
    setACPRLegend()
  end
  publishNotification()
end

function endCalls()
  if compCallSync ~= nil then compCallSync["call.decline"]:Trigger() end
end

-------------------[ Components ]-------------------

function setcompCallSync()
  compCallSync = setComp(Controls['compCallSync'], "Call Sync")
  if compCallSync ~= nil then
    compCallSync["off.hook"].EventHandler = getCallSyncHookState
    compCallSync["mute"].EventHandler = getCallSyncMute
    getCallSyncHookState()
  end
end

function setcompVideoBridge(idx)
  compVideoBridge[idx] = setComp(asArray(Controls['compVideoBridge'])[idx], "Video Bridge [" .. idx .. "]")
  if compVideoBridge[idx] ~= nil then
    compVideoBridge[idx]["toggle.privacy"].EventHandler = function() getVideoBridgePrivacyState(idx) end
    getVideoBridgePrivacyState(idx)
  end
end

function setcompGain(idx)
  compGains[idx] = setComp(asArray(Controls['compGains'])[idx], "Gain [" .. idx .. "]")
  if compGains[idx] ~= nil then
    compGains[idx]["gain"].EventHandler = function() getVolumeLvl(idx) end
    compGains[idx]["mute"].EventHandler = function() getVolumeMute(idx) end
    getVolumeLvl(idx)
    getVolumeMute(idx)
  end
end

function setcompSystemMute()
  if Controls['compSystemMute'] then compSystemMute = setComp(Controls['compSystemMute'], "System Mute") end
end

function setcompCamACPR()
  if not Controls['compACPR'] then return end
  compCamACPR = setComp(Controls['compACPR'], "Camera ACPR")
  if compCamACPR ~= nil then
    compCamACPR["TrackingBypass"].EventHandler = function()
      debugMsg("ACPR Tracking Bypass: " .. tostring(compCamACPR["TrackingBypass"].Boolean))
      setACPRLegend()
    end
    getCallSyncHookState()
  end
end

function setcompDisplay(idx)
  compDisplays[idx] = setComp(asArray(Controls['devDisplays'])[idx], "Display [" .. idx .. "]")
end

function setCompSystemMute(state)
  if compSystemMute ~= nil then compSystemMute["mute"].Boolean = state end
end

-------------------[ Displays ]-------------------

function powerDisplays(on)
  local trig = on and "PowerOn" or "PowerOff"
  eachComp(compDisplays, nil, function(_, display) display[trig]:Trigger() end)
end

-------------------[ System power ]-------------------

function setEnableDisablePowerControls(enabled)
  Controls['btnSystemOnOff'].IsDisabled = not enabled
  Controls['btnSystemOn'].IsDisabled = not enabled
  Controls['btnSystemOff'].IsDisabled = not enabled
end

function setSystemPowerFB(powerState)
  Controls['ledSystemPower'].Boolean = powerState
  Controls['btnSystemOnOff'].Boolean = powerState
  Controls['btnSystemOn'].Boolean = powerState
  Controls['btnSystemOff'].Boolean = not powerState
end

-- video privacy is left alone here; off.hook owns it
function powerOn()
  debugMsg("[Power] On (User)")
  if Controls['btnSystemOnTrig'] then Controls['btnSystemOnTrig']:Trigger() end
  setEnableDisablePowerControls(false)
  Controls['ledSystemWarming'].Boolean = true
  timerWarmup:Start(config.warmupTime)
  setSystemPowerFB(true)
  applyVolumeDefaults()
  setMute(false)
  setCallSyncMute(true)
  powerDisplays(true)
  publishNotification()
end

-- mics keep their mute state through power off
function powerOff(sourceTag)
  debugMsg("[Power] Off (" .. (sourceTag or "User") .. ")")
  if Controls['btnSystemOffTrig'] then Controls['btnSystemOffTrig']:Trigger() end
  setEnableDisablePowerControls(false)
  Controls['ledSystemCooling'].Boolean = true
  timerCooldown:Start(config.cooldownTime)
  setSystemPowerFB(false)
  setCallSyncMute(true)
  eachComp(compGains, nil, function(i) if getGainType(i) ~= "Mic" then setMute(true, i) end end)
  powerDisplays(false)
  endCalls()
  publishNotification()
end

-------------------[ Motion ]-------------------

-- motion present: cancel the off timer and maybe power on; motion gone: start the off timer
function getMotion()
  local mode = Controls['txtMotionMode'].String
  debugMsg("[Motion] check")
  if Controls['ledMotionIn'].Boolean then
    Controls['ledMotionTimeoutActive'].Boolean = false
    timerMotion:Stop()
    if mode == "Motion On/Off" and not Controls['ledSystemPower'].Boolean and not Controls['ledMotionGraceActive'].Boolean then
      debugMsg("[Motion] Power on from motion")
      powerOn()
    end
  elseif mode == "Motion On/Off" or mode == "Motion Off" then
    debugMsg("[Motion] Starting off timer")
    Controls['ledMotionTimeoutActive'].Boolean = true
    timerMotion:Start(config.motionTimeout)
  end
end

-------------------[ Fire alarm ]-------------------

-- alarm: mute and blank; clear: restore only if the system is on
function setFireAlarm(alarmState)
  if alarmState or Controls['ledSystemPower'].Boolean then
    setCompSystemMute(alarmState)
    powerDisplays(not alarmState)
  end
end

-------------------[ Event Handlers ]-------------------

timerMotion.EventHandler = function()
  -- trigger system off after motion timeout
  debugMsg("[Motion] Timeout")
  Controls['ledMotionTimeoutActive'].Boolean = false
  timerMotion:Stop()
  powerOff("Motion timeout")
end

timerGrace.EventHandler = function()
  -- allow system to power on from motion after grace period ends
  debugMsg("Grace period ended")
  Controls['ledMotionGraceActive'].Boolean = false
  timerGrace:Stop()
end

timerWarmup.EventHandler = function()
  -- re-enable power buttons after warmup period ends
  debugMsg("Warmup complete")
  Controls['ledSystemWarming'].Boolean = false
  setEnableDisablePowerControls(true)
  timerWarmup:Stop()
  publishNotification()
end

timerCooldown.EventHandler = function()
  -- re-enable power buttons after cooldown period ends
  debugMsg("Cooldown complete")
  Controls['ledSystemCooling'].Boolean = false
  setEnableDisablePowerControls(true)
  timerCooldown:Stop()
  publishNotification()
end

-- power toggle / on / off buttons
Controls['btnSystemOnOff'].EventHandler = function(ctl) if ctl.Boolean then powerOn() else powerOff() end end
Controls['btnSystemOn'].EventHandler = function() powerOn() end

Controls['btnSystemOff'].EventHandler = function()
  -- manual off starts a grace period so motion can't immediately turn the room back on
  powerOff()
  Controls['ledMotionGraceActive'].Boolean = true
  timerGrace:Start(config.gracePeriod)
end

-- audio privacy button -> call sync mute
Controls['btnAudioPrivacy'].EventHandler = function(ctl) setCallSyncMute(ctl.Boolean) end

-- room name used in debug prints and notifications
Controls['roomName'].EventHandler = function(ctl)
  roomName = "[" .. ctl.String .. "]"
  debugMsg("Room name: " .. roomName)
  publishNotification()
end

-- occupancy sensor input (idle if nothing drives it)
Controls['ledMotionIn'].EventHandler = getMotion

-- component selectors
Controls['compCallSync'].EventHandler = setcompCallSync
if Controls['compSystemMute'] then Controls['compSystemMute'].EventHandler = setcompSystemMute end
if Controls['compACPR'] then Controls['compACPR'].EventHandler = setcompCamACPR end
forEach('compVideoBridge', function(ctl, i) ctl.EventHandler = function() setcompVideoBridge(i) end end)
forEach('compGains',       function(ctl, i) ctl.EventHandler = function() setcompGain(i) end end)
forEach('devDisplays',     function(ctl, i) ctl.EventHandler = function() setcompDisplay(i) end end)

-- manual video privacy override (off.hook also drives privacy in getCallSyncHookState)
forEach('btnVideoPrivacy', function(ctl, i) ctl.EventHandler = function(c) setVideoPrivacy(c.Boolean, i) end end)

-- per-gain fader, mute, and ramp buttons
forEach('knbVolumeFader', function(ctl, i) ctl.EventHandler = function(c) setVolume(c.Position, i) end end)
forEach('btnVolumeMute',  function(ctl, i) ctl.EventHandler = function(c) setMute(c.Boolean, i) end end)
forEach('btnVolumeUp',    function(ctl, i) ctl.EventHandler = function(c) setVolumeUpDown("up", c.Boolean, i) end end)
forEach('btnVolumeDn',    function(ctl, i) ctl.EventHandler = function(c) setVolumeUpDown("down", c.Boolean, i) end end)

-- gain type change -> jump to that type's default level (gain 1 is fixed as Program)
forEach('typeGain', function(ctl, i)
  if i == 1 then return end
  ctl.EventHandler = function(c)
    if compGains[i] ~= nil then
      setVolume(getDefaultVolumeForType(c.String), i)
      debugMsg("Type selector -> gain " .. i .. " (" .. c.String .. ")")
    end
    publishNotification()
  end
end)

if Controls['selDefaultConfigs'] then
  -- room preset: timings, motion, and gain-type maps
  Controls['selDefaultConfigs'].EventHandler = function(ctl)
    applyActiveConfig(ctl.String)
    updateConfigValueControls(ctl.String)
    setGainTypeAssignments(ctl.String)
    applyVolumeDefaults()
  end
end

-- User Defined value edits -> active config
for _, map in ipairs(configValueMaps) do
  if Controls[map.control] then
    Controls[map.control].EventHandler = function(ctl)
      if Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String == "User Defined" then
        defaultConfigs["User Defined"][map.config] = ctl.Value
      end
    end
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  if not validateControls() then
    if Controls['txtStatus'] then
      Controls['txtStatus'].String = "INIT FAILED"
      Controls['txtStatus'].Value = 2
    end
    return
  end

  initConfigPresets()
  roomName = "[" .. Controls['roomName'].String .. "]"
  debugMsg("Init started; debug=" .. tostring(stateDebug))

  setEnableDisablePowerControls(true)
  getComponentNames()

  Controls['txtMotionMode'].Choices = MotionChoices
  forEach('typeGain', function(ctl) ctl.Choices = { "Mic", "Gain" } end)

  if Controls['selDefaultConfigs'] then
    Controls['selDefaultConfigs'].Choices = presetNames
    if Controls['selDefaultConfigs'].String == "" then Controls['selDefaultConfigs'].String = "Default" end
    updateConfigValueControls(Controls['selDefaultConfigs'].String)
  end

  setGainTypeAssignments()
  setcompCallSync()
  setcompSystemMute()
  setcompCamACPR()
  forEach('compVideoBridge', function(_, i) setcompVideoBridge(i) end)
  forEach('compGains',       function(_, i) setcompGain(i) end)
  forEach('devDisplays',     function(_, i) setcompDisplay(i) end)

  getStatus()
  debugMsg("Ready - " .. getGainCount() .. " gains")
end

funcInit()
