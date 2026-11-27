--[[
  System Automation Controller (Lean) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 2.1 | Date: 2026-11-27
  Firmware Req: 10.4
  Power, audio, video privacy (off.hook), displays, motion, multi-gain, ACPR
]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  callSync   = "call_sync",
  videoBridge = "usb_uvc",
  displays   = "%PLUGIN%_bd0a5e74-c1bf-48ee-8574-e42e1e7b2bb9_%FP%_31e2e2d7be2243768d2bd9c853a6295c",
  gains      = "gain",
  systemMute = "system_mute",
  camACPR    = "%PLUGIN%_6ddbd63b-ebb6-43ed-9c5a-9a7d6dac6f37_%FP%_22bcd2049cd1e9c1f02a4e76655c2db4",
}

gainTypeAssignment = {
  ["Conference Room"] = { "Program", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain" },
  ["Huddle Room"]     = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic" },
  ["Custom Room"]     = { "Program", "Mic", "Mic", "Mic", "Gain", "Gain", "Gain", "Gain", "Gain" },
  ["Default"]         = { "Program", "Gain", "Gain", "Gain", "Mic", "Mic", "Mic", "Mic" },
}

btnMuteShell = "button-square-red-big-icon"
gainTypeIcon = {
  Mic = "iconmicoutline",
  Program = "iconvolumemuteoutline",
  Gain = "iconvolumemuteoutline",
}

MotionChoices = { "Motion On/Off", "Motion Off", "Motion Disabled" }

configValueMaps = {
  { control = "warmupTime", config = "warmupTime" },
  { control = "cooldownTime", config = "cooldownTime" },
  { control = "motionTimeout", config = "motionTimeout" },
  { control = "motionGracePeriod", config = "gracePeriod" },
  { control = "defaultProgramVolume", config = "defaultProgramVolume" },
  { control = "defaultMicVolume", config = "defaultMicVolume" },
  { control = "defaultGainVolume", config = "defaultGainVolume" },
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
config = {}
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

function asControlList(ctrl)
  if not ctrl then return {} end
  if ctrl[1] ~= nil then return ctrl end
  return { ctrl }
end

-- Required Text Controller pins; optional pins (notification, ACPR, presets) guarded at use sites.
function validateControls()
  local missing = {}
  for _, name in ipairs({
    "roomName", "txtStatus", "compCallSync", "btnSystemOnOff", "btnSystemOn", "btnSystemOff",
    "ledSystemPower", "ledSystemWarming", "ledSystemCooling", "btnAudioPrivacy",
  }) do
    if not Controls[name] then table.insert(missing, name) end
  end
  if #missing == 0 then return true end
  print("ERROR: Missing controls: " .. table.concat(missing, ", "))
  return false
end

function getDefaultConfig(roomType)
  local base = { defaultProgramVolume = 0.7, defaultMicVolume = 0.5, defaultGainVolume = 0.7 }
  if roomType == "User Defined" then
    return {
      debugging = true,
      warmupTime = (Controls['warmupTime'] and Controls['warmupTime'].Value) or 10,
      cooldownTime = (Controls['cooldownTime'] and Controls['cooldownTime'].Value) or 5,
      motionTimeout = (Controls['motionTimeout'] and Controls['motionTimeout'].Value) or 300,
      gracePeriod = (Controls['motionGracePeriod'] and Controls['motionGracePeriod'].Value) or 30,
      defaultProgramVolume = (Controls['defaultProgramVolume'] and Controls['defaultProgramVolume'].Value) or base.defaultProgramVolume,
      defaultMicVolume = (Controls['defaultMicVolume'] and Controls['defaultMicVolume'].Value) or base.defaultMicVolume,
      defaultGainVolume = (Controls['defaultGainVolume'] and Controls['defaultGainVolume'].Value) or base.defaultGainVolume,
    }
  end
  local presets = {
    ["Conference Room"] = { debugging = true, warmupTime = 15, cooldownTime = 10, motionTimeout = 600, gracePeriod = 60,
      defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
    ["Huddle Room"] = { debugging = false, warmupTime = 5, cooldownTime = 3, motionTimeout = 300, gracePeriod = 30,
      defaultProgramVolume = 0.6, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
    ["Default"] = { debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30,
      defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
    ["Custom Room"] = { debugging = true, warmupTime = 10, cooldownTime = 5, motionTimeout = 300, gracePeriod = 30,
      defaultProgramVolume = base.defaultProgramVolume, defaultMicVolume = base.defaultMicVolume, defaultGainVolume = base.defaultGainVolume },
  }
  return presets[roomType] or presets["Default"]
end

function applyActiveConfig(roomType)
  config = defaultConfigs[roomType] or defaultConfigs["Default"] or getDefaultConfig("Default")
  stateDebug = config.debugging ~= false
end

function updateConfigValueControls(roomType)
  local conf = defaultConfigs[roomType]
  if not conf then return end
  local isUser = roomType == "User Defined"
  for _, map in ipairs(configValueMaps) do
    local ctl = Controls[map.control]
    if ctl and ctl.Value ~= nil then
      ctl.Value = conf[map.config]
      ctl.IsDisabled = not isUser
    end
  end
end

function initConfigPresets()
  defaultConfigs = {
    ["Conference Room"] = getDefaultConfig("Conference Room"),
    ["Huddle Room"] = getDefaultConfig("Huddle Room"),
    ["Default"] = getDefaultConfig("Default"),
    ["Custom Room"] = getDefaultConfig("Custom Room"),
    ["User Defined"] = getDefaultConfig("User Defined"),
  }
  local roomType = (Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String) or "Default"
  applyActiveConfig(roomType)
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

function setComp(ctl, componentType)
  if not ctl then
    compInvalid[componentType] = true
    getStatus()
    return nil
  end
  local name = ctl.String
  if not name or name == "" or name == strClear then
    if name == strClear then ctl.String = "" end
    ctl.Color = "white"
    compInvalid[componentType] = false
    getStatus()
    debugMsg("No " .. componentType .. " selected")
    return nil
  end
  local comp = Component.New(name)
  local list = comp and Component.GetControls(comp)
  if not list or #list < 1 then
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
  local videoPrivacy = false
  local vbBtns = asControlList(Controls['btnVideoPrivacy'])
  if vbBtns[1] then videoPrivacy = vbBtns[1].Boolean end
  local systemState = {
    RoomName = roomName,
    PowerState = Controls['ledSystemPower'].Boolean,
    SystemWarming = Controls['ledSystemWarming'].Boolean,
    SystemCooling = Controls['ledSystemCooling'].Boolean,
    AudioPrivacy = Controls['btnAudioPrivacy'].Boolean,
    VideoPrivacy = videoPrivacy,
    ACPRState = (compCamACPR and compCamACPR["TrackingBypass"] and compCamACPR["TrackingBypass"].Boolean) or false,
    Timestamp = os.time(),
    GainControls = {},
  }
  for idx, gain in pairs(compGains) do
    if gain ~= nil then
      systemState.GainControls[idx] = {
        Level = gain["gain"].Position,
        Muted = gain["mute"].Boolean,
      }
    end
  end
  Notifications.Publish(Controls['txtNotificationID'].String, systemState)
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local names = { callSync = {}, videoBridge = {}, camACPR = {}, displays = {}, gains = {}, systemMute = {} }
  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.callSync then table.insert(names.callSync, comp.Name)
    elseif comp.Type == componentTypes.videoBridge then table.insert(names.videoBridge, comp.Name)
    elseif comp.Type == componentTypes.displays then table.insert(names.displays, comp.Name)
    elseif comp.Type == componentTypes.gains then table.insert(names.gains, comp.Name)
    elseif comp.Type == componentTypes.systemMute then table.insert(names.systemMute, comp.Name)
    elseif comp.Type == componentTypes.camACPR then table.insert(names.camACPR, comp.Name) end
  end
  for _, list in pairs(names) do table.sort(list); table.insert(list, strClear) end
  if Controls['compCallSync'] then Controls['compCallSync'].Choices = names.callSync end
  if Controls['compSystemMute'] then Controls['compSystemMute'].Choices = names.systemMute end
  if Controls['compACPR'] then Controls['compACPR'].Choices = names.camACPR end
  for _, ctl in ipairs(asControlList(Controls['compVideoBridge'])) do ctl.Choices = names.videoBridge end
  for _, ctl in ipairs(asControlList(Controls['compGains'])) do ctl.Choices = names.gains end
  for _, ctl in ipairs(asControlList(Controls['devDisplays'])) do ctl.Choices = names.displays end
  debugMsg("Discovery: " .. (#names.callSync - 1) .. " callSync, " .. (#names.videoBridge - 1) .. " videoBridge, "
    .. (#names.gains - 1) .. " gains, " .. (#names.displays - 1) .. " displays")
end

-------------------[ Gain types & visuals ]-------------------

function getGainType(idx)
  local types = asControlList(Controls['typeGain'])
  if types[idx] then return types[idx].String end
  return idx == 1 and "Program" or "Mic"
end

function getDefaultVolumeForType(gainType)
  local defaults = {
    Program = config.defaultProgramVolume,
    Mic = config.defaultMicVolume,
    Gain = config.defaultGainVolume,
  }
  return defaults[gainType] or defaults.Mic
end

function setGainTypeAssignments(roomType)
  roomType = roomType or (Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String) or "Default"
  local assign = gainTypeAssignment[roomType] or gainTypeAssignment["Default"]
  for idx, gainType in ipairs(assign) do
    local types = asControlList(Controls['typeGain'])
    if types[idx] then
      types[idx].String = idx == 1 and "Program" or gainType
      types[idx].IsDisabled = idx == 1
    end
  end
end

function updateVolumeVisuals(idx)
  local faders = asControlList(Controls['knbVolumeFader'])
  local mutes = asControlList(Controls['btnVolumeMute'])
  local fader = faders[idx]
  local mute = mutes[idx]
  if not fader or not mute then return end
  local gainType = getGainType(idx)
  local isMuted = mute.Boolean
  local meterClass = isMuted and "meter-muted" or "meter"
  if fader.CssClass ~= meterClass then fader.CssClass = meterClass end
  local icon = gainTypeIcon[gainType] or gainTypeIcon.Program
  local muteClass = btnMuteShell .. " " .. icon
  if mute.CssClass ~= muteClass then mute.CssClass = muteClass end
end

function getGainCount()
  local count = 0
  for _ in pairs(compGains) do count = count + 1 end
  return count
end

-------------------[ Volume ]-------------------

function applyVolumeDefaults()
  debugMsg("Applying volume defaults from typeGain")
  for idx, gain in pairs(compGains) do
    if gain ~= nil then
      local gainType = getGainType(idx)
      local level = getDefaultVolumeForType(gainType)
      gain["gain"].Position = level
      updateVolumeVisuals(idx)
      debugMsg("Default " .. gainType .. " (" .. level .. ") -> gain " .. idx)
    end
  end
end

function setVolume(level, gainIndex)
  if gainIndex then
    if compGains[gainIndex] ~= nil then
      compGains[gainIndex]["gain"].Position = level
      updateVolumeVisuals(gainIndex)
    end
  else
    for idx, gain in pairs(compGains) do
      if gain ~= nil then
        gain["gain"].Position = level
        updateVolumeVisuals(idx)
      end
    end
  end
  publishNotification()
end

function setMute(muteState, gainIndex)
  if gainIndex then
    if compGains[gainIndex] ~= nil then
      compGains[gainIndex]["mute"].Boolean = muteState
      updateVolumeVisuals(gainIndex)
    end
  else
    for idx, gain in pairs(compGains) do
      if gain ~= nil then
        gain["mute"].Boolean = muteState
        updateVolumeVisuals(idx)
      end
    end
  end
  publishNotification()
end

function setVolumeUpDown(direction, pressed, gainIndex)
  local action = direction == "up" and "stepper.increase" or "stepper.decrease"
  local step = function(idx, gain)
    gain[action].Boolean = pressed
    if pressed then gain["mute"].Boolean = false end
    updateVolumeVisuals(idx)
  end
  if gainIndex then
    if compGains[gainIndex] ~= nil then step(gainIndex, compGains[gainIndex]) end
  else
    for idx, gain in pairs(compGains) do
      if gain ~= nil then step(idx, gain) end
    end
  end
  publishNotification()
end

function getVolumeLvl(idx)
  if compGains[idx] == nil then return end
  local faders = asControlList(Controls['knbVolumeFader'])
  if not faders[idx] then return end
  faders[idx].Position = compGains[idx]["gain"].Position
  updateVolumeVisuals(idx)
  publishNotification()
end

function getVolumeMute(idx)
  if compGains[idx] == nil then return end
  local muteState = compGains[idx]["mute"].Boolean
  local mutes = asControlList(Controls['btnVolumeMute'])
  if not mutes[idx] then return end
  -- feedback loop: gain mute EventHandler -> this function -> script mute button
  if mutes[idx].Boolean ~= muteState then mutes[idx].Boolean = muteState end
  updateVolumeVisuals(idx)
  publishNotification()
end

-------------------[ Call sync & privacy ]-------------------

function getCallSyncMute()
  if compCallSync == nil then return end
  local muteState = compCallSync["mute"].Boolean
  debugMsg("Call Sync mute: " .. tostring(muteState))
  -- feedback loop: call sync mute EventHandler -> script audio privacy button
  if Controls['btnAudioPrivacy'].Boolean ~= muteState then
    Controls['btnAudioPrivacy'].Boolean = muteState
  end
end

function setCallSyncMute(state)
  if compCallSync ~= nil then
    debugMsg("Setting Call Sync mute: " .. tostring(state))
    compCallSync["mute"].Boolean = state
  end
  Controls['btnAudioPrivacy'].Boolean = state
  publishNotification()
end

function setVideoPrivacy(state, idx)
  if idx then
    if compVideoBridge[idx] ~= nil then
      compVideoBridge[idx]["toggle.privacy"].Boolean = state
    end
  else
    for _, bridge in pairs(compVideoBridge) do
      if bridge ~= nil then bridge["toggle.privacy"].Boolean = state end
    end
  end
  publishNotification()
end

function getVideoBridgePrivacyState(idx)
  idx = idx or 1
  if compVideoBridge[idx] == nil then return end
  local privacyState = compVideoBridge[idx]["toggle.privacy"].Boolean
  debugMsg("Video bridge [" .. idx .. "] privacy: " .. tostring(privacyState))
  local btns = asControlList(Controls['btnVideoPrivacy'])
  local btn = btns[idx] or (#btns == 1 and btns[1])
  if not btn then return end
  -- feedback loop: bridge privacy EventHandler -> script video privacy button
  if btn.Boolean ~= privacyState then btn.Boolean = privacyState end
end

function getCallSyncHookState()
  if compCallSync == nil then return end
  local offHook = compCallSync["off.hook"].Boolean
  getCallSyncMute()
  for idx in pairs(compVideoBridge) do setVideoPrivacy(not offHook, idx) end
  for idx in pairs(compVideoBridge) do getVideoBridgePrivacyState(idx) end
  if compCamACPR ~= nil then
    compCamACPR["TrackingBypass"].IsDisabled = not offHook
    compCamACPR["TrackingBypass"].Boolean = not offHook
    local bypass = compCamACPR["TrackingBypass"].Boolean
    compCamACPR["TrackingBypass"].Legend = compCamACPR["TrackingBypass"].IsDisabled and "Disabled"
      or (bypass and "Off" or "Auto")
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
  local selectors = asControlList(Controls['compVideoBridge'])
  if not selectors[idx] then return end
  compVideoBridge[idx] = setComp(selectors[idx], "Video Bridge [" .. idx .. "]")
  if compVideoBridge[idx] ~= nil then
    compVideoBridge[idx]["toggle.privacy"].EventHandler = function() getVideoBridgePrivacyState(idx) end
    getVideoBridgePrivacyState(idx)
  end
end

function setcompGain(idx)
  local selectors = asControlList(Controls['compGains'])
  if not selectors[idx] then return end
  compGains[idx] = setComp(selectors[idx], "Gain [" .. idx .. "]")
  if compGains[idx] ~= nil then
    compGains[idx]["gain"].EventHandler = function() getVolumeLvl(idx) end
    compGains[idx]["mute"].EventHandler = function() getVolumeMute(idx) end
    getVolumeLvl(idx)
    getVolumeMute(idx)
  end
end

function setcompSystemMute()
  compSystemMute = setComp(Controls['compSystemMute'], "System Mute")
end

function setcompCamACPR()
  if not Controls['compACPR'] then return end
  compCamACPR = setComp(Controls['compACPR'], "Camera ACPR")
  if compCamACPR ~= nil then
    compCamACPR["TrackingBypass"].EventHandler = function()
      local bypassState = compCamACPR["TrackingBypass"].Boolean
      debugMsg("ACPR Tracking Bypass: " .. tostring(bypassState))
      compCamACPR["TrackingBypass"].Legend = compCamACPR["TrackingBypass"].IsDisabled and "Disabled"
        or (bypassState and "Off" or "Auto")
    end
    getCallSyncHookState()
  end
end

function setcompDisplay(idx)
  local selectors = asControlList(Controls['devDisplays'])
  if not selectors[idx] then return end
  compDisplays[idx] = setComp(selectors[idx], "Display [" .. idx .. "]")
end

function setCompSystemMute(state)
  if compSystemMute ~= nil then compSystemMute["mute"].Boolean = state end
end

-------------------[ Displays ]-------------------

function powerDisplays(on)
  local trig = on and "PowerOn" or "PowerOff"
  for _, display in pairs(compDisplays) do
    if display ~= nil then display[trig]:Trigger() end
  end
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

function powerOn()
  debugMsg("[Power] On (User)")
  if Controls['btnSystemOnTrig'] then Controls['btnSystemOnTrig']:Trigger() end
  setEnableDisablePowerControls(false)
  Controls['ledSystemWarming'].Boolean = true
  local warmup = Controls['warmupTime'] and Controls['warmupTime'].Value or config.warmupTime or 10
  timerWarmup:Start(warmup)
  setSystemPowerFB(true)
  applyVolumeDefaults()
  setMute(false)
  setCallSyncMute(true)
  powerDisplays(true)
  publishNotification()
end

function powerOff(sourceTag)
  sourceTag = sourceTag or "User"
  debugMsg("[Power] Off (" .. sourceTag .. ")")
  if Controls['btnSystemOffTrig'] then Controls['btnSystemOffTrig']:Trigger() end
  setEnableDisablePowerControls(false)
  Controls['ledSystemCooling'].Boolean = true
  local cooldown = Controls['cooldownTime'] and Controls['cooldownTime'].Value or config.cooldownTime or 5
  timerCooldown:Start(cooldown)
  setSystemPowerFB(false)
  setCallSyncMute(true)
  for idx, gain in pairs(compGains) do
    if gain ~= nil and getGainType(idx) ~= "Mic" then setMute(true, idx) end
  end
  powerDisplays(false)
  endCalls()
  publishNotification()
end

-------------------[ Motion ]-------------------

function getMotion()
  if not Controls['ledMotionIn'] then return end
  debugMsg("[Motion] check")
  if Controls['ledMotionIn'].Boolean then
    if Controls['ledMotionTimeoutActive'] then Controls['ledMotionTimeoutActive'].Boolean = false end
    timerMotion:Stop()
    local mode = Controls['txtMotionMode'] and Controls['txtMotionMode'].String or ""
    if not Controls['ledSystemPower'].Boolean
        and not Controls['ledMotionGraceActive'].Boolean
        and mode == "Motion On/Off" then
      debugMsg("[Motion] Power on from motion")
      powerOn()
    end
    return
  end
  local mode = Controls['txtMotionMode'] and Controls['txtMotionMode'].String or ""
  if mode == "Motion On/Off" or mode == "Motion Off" then
    debugMsg("[Motion] Starting off timer")
    if Controls['ledMotionTimeoutActive'] then Controls['ledMotionTimeoutActive'].Boolean = true end
    local timeout = Controls['motionTimeout'] and Controls['motionTimeout'].Value or config.motionTimeout or 300
    timerMotion:Start(timeout)
  end
end

-------------------[ Fire alarm ]-------------------

function setFireAlarm(alarmState)
  if alarmState then
    setCompSystemMute(true)
    powerDisplays(false)
    return
  end
  if Controls['ledSystemPower'].Boolean then
    setCompSystemMute(false)
    powerDisplays(true)
  end
end

-------------------[ Event Handlers ]-------------------

timerMotion.EventHandler = function()
  -- trigger system off after motion timeout
  debugMsg("[Motion] Timeout")
  if Controls['ledMotionTimeoutActive'] then Controls['ledMotionTimeoutActive'].Boolean = false end
  timerMotion:Stop()
  powerOff("Motion timeout")
end

timerGrace.EventHandler = function()
  -- allow system to power on from motion after grace period ends
  debugMsg("Grace period ended")
  if Controls['ledMotionGraceActive'] then Controls['ledMotionGraceActive'].Boolean = false end
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

Controls['btnSystemOnOff'].EventHandler = function(ctl)
  if ctl.Boolean then powerOn() else powerOff() end
end

Controls['btnSystemOn'].EventHandler = function()
  powerOn()
end

Controls['btnSystemOff'].EventHandler = function()
  powerOff()
  if Controls['ledMotionGraceActive'] then Controls['ledMotionGraceActive'].Boolean = true end
  local grace = Controls['motionGracePeriod'] and Controls['motionGracePeriod'].Value or config.gracePeriod or 30
  timerGrace:Start(grace)
end

Controls['btnAudioPrivacy'].EventHandler = function(ctl)
  setCallSyncMute(ctl.Boolean)
end

Controls['roomName'].EventHandler = function()
  roomName = "[" .. (Controls['roomName'].String or "Unknown") .. "]"
  debugMsg("Room name: " .. roomName)
  publishNotification()
end

if Controls['ledMotionIn'] then
  Controls['ledMotionIn'].EventHandler = getMotion
end

Controls['compCallSync'].EventHandler = setcompCallSync
Controls['compSystemMute'].EventHandler = setcompSystemMute
if Controls['compACPR'] then Controls['compACPR'].EventHandler = setcompCamACPR end

for i, ctl in ipairs(asControlList(Controls['btnVideoPrivacy'])) do
  -- manual video privacy override (off.hook also drives privacy in getCallSyncHookState)
  ctl.EventHandler = function(c)
    setVideoPrivacy(c.Boolean, i)
  end
end

for i, ctl in ipairs(asControlList(Controls['knbVolumeFader'])) do
  ctl.EventHandler = function(c)
    setVolume(c.Position, i)
  end
end

for i, ctl in ipairs(asControlList(Controls['btnVolumeMute'])) do
  ctl.EventHandler = function(c)
    setMute(c.Boolean, i)
  end
end

for i, ctl in ipairs(asControlList(Controls['btnVolumeUp'])) do
  ctl.EventHandler = function(c)
    setVolumeUpDown("up", c.Boolean, i)
  end
end

for i, ctl in ipairs(asControlList(Controls['btnVolumeDn'])) do
  ctl.EventHandler = function(c)
    setVolumeUpDown("down", c.Boolean, i)
  end
end

for i, ctl in ipairs(asControlList(Controls['compVideoBridge'])) do
  ctl.EventHandler = function()
    setcompVideoBridge(i)
  end
end

for i, ctl in ipairs(asControlList(Controls['compGains'])) do
  ctl.EventHandler = function()
    setcompGain(i)
  end
end

for i, ctl in ipairs(asControlList(Controls['devDisplays'])) do
  ctl.EventHandler = function()
    setcompDisplay(i)
  end
end

for i, ctl in ipairs(asControlList(Controls['typeGain'])) do
  if i > 1 then
    ctl.EventHandler = function(gainCtl)
      if compGains[i] ~= nil then
        setVolume(getDefaultVolumeForType(gainCtl.String), i)
        debugMsg("Type selector -> gain " .. i .. " (" .. gainCtl.String .. ")")
      end
      publishNotification()
    end
  end
end

if Controls['selDefaultConfigs'] then
  -- room preset: timings, motion, and gain-type maps
  Controls['selDefaultConfigs'].EventHandler = function(ctl)
    applyActiveConfig(ctl.String)
    updateConfigValueControls(ctl.String)
    setGainTypeAssignments(ctl.String)
    applyVolumeDefaults()
  end
end

for _, map in ipairs(configValueMaps) do
  if Controls[map.control] then
    Controls[map.control].EventHandler = function(value)
      if Controls['selDefaultConfigs'] and Controls['selDefaultConfigs'].String == "User Defined" then
        defaultConfigs["User Defined"][map.config] = value.Value
        config[map.config] = value.Value
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
  roomName = "[" .. (Controls['roomName'].String or "Unknown") .. "]"
  debugMsg("Init started; debug=" .. tostring(stateDebug))

  setEnableDisablePowerControls(true)
  getComponentNames()

  if Controls['txtMotionMode'] then Controls['txtMotionMode'].Choices = MotionChoices end
  for _, ctl in ipairs(asControlList(Controls['typeGain'])) do ctl.Choices = { "Mic", "Gain" } end

  if Controls['selDefaultConfigs'] then
    Controls['selDefaultConfigs'].Choices = { "Conference Room", "Huddle Room", "Default", "Custom Room", "User Defined" }
    if Controls['selDefaultConfigs'].String == "" then Controls['selDefaultConfigs'].String = "Default" end
    updateConfigValueControls(Controls['selDefaultConfigs'].String)
  end

  setGainTypeAssignments()
  setcompCallSync()
  setcompSystemMute()
  setcompCamACPR()
  for i in ipairs(asControlList(Controls['compVideoBridge'])) do setcompVideoBridge(i) end
  for i in ipairs(asControlList(Controls['compGains'])) do setcompGain(i) end
  for i in ipairs(asControlList(Controls['devDisplays'])) do setcompDisplay(i) end

  getStatus()
  debugMsg("Ready - " .. getGainCount() .. " gains")
end

funcInit()
