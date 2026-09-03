--[[
  ShureMXAController - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-08-25
  Version: 4.1
  Firmware Req: 10.4.0

  Shure MXA mic LEDs and mute via call sync, room controls, and mute button.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync     = "call_sync",
  micMXA       = "%PLUGIN%_15f47939-2779-495a-881b-b10317365958_%FP%_53a1bc56de2ede23e07c7d9e32bec505",
  roomControls = "device_controller_script",
}

-------------------[ Constant Tables ]-------------------

compCallSync = nil
compRoomControls = nil
compMicMXA = {}
compInvalid = {}

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[Shure MXA Controller]"

ledBrightness = 5
ledOff = 0
ledRed = "Red"
ledGreen = "Green"
ledToggleInterval = 1.5
hookMuteSyncDelay = 0.3

fireAlarm = false
ledState = false

timerLEDToggle = Timer.New()

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print("[" .. roomName .. "] " .. str) end
end

function getMXAControls()
  if not Controls.devMXAs then return {} end
  if Controls.devMXAs[1] then return Controls.devMXAs end
  return { Controls.devMXAs }
end

-------------------[ Status ]-------------------

function getStatus()
  if not Controls.txtStatus then return end
  for _, invalid in pairs(compInvalid) do
    if invalid then
      Controls.txtStatus.String = "Invalid Components"
      Controls.txtStatus.Value = 1
      return
    end
  end
  Controls.txtStatus.String = "OK"
  Controls.txtStatus.Value = 0
end

function setCompInvalid(componentType)
  compInvalid[componentType] = true
  getStatus()
end

function setCompValid(componentType)
  compInvalid[componentType] = false
  getStatus()
end

function setComp(ctl, componentType)
  if not ctl then
    setCompInvalid(componentType)
    return nil
  end

  local name = ctl.String
  if not name or name == "" then
    ctl.Color = "white"
    setCompValid(componentType)
    return nil
  elseif name == strClear then
    ctl.String = ""
    ctl.Color = "white"
    setCompValid(componentType)
    return nil
  elseif #Component.GetControls(Component.New(name)) < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    return nil
  end

  ctl.Color = "white"
  setCompValid(componentType)
  debugMsg("Connected " .. componentType .. ": " .. name)
  return Component.New(name)
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local names = { RoomControls = {}, CallSync = {}, MXA = {} }

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.callSync then
      table.insert(names.CallSync, comp.Name)
    elseif comp.Type == componentTypes.micMXA then
      table.insert(names.MXA, comp.Name)
    elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
      table.insert(names.RoomControls, comp.Name)
    end
  end

  for _, list in pairs(names) do
    table.sort(list)
    table.insert(list, strClear)
  end

  if Controls.compRoomControls then Controls.compRoomControls.Choices = names.RoomControls end
  if Controls.compCallSync then Controls.compCallSync.Choices = names.CallSync end
  for _, ctl in ipairs(getMXAControls()) do
    ctl.Choices = names.MXA
  end
end

-------------------[ LEDs ]-------------------

function setAllMXALEDs(ledOn)
  local value = ledOn and ledBrightness or ledOff
  for _, device in pairs(compMicMXA) do
    if device and device.BrightnessLevel then
      device.BrightnessLevel.Value = value
    end
  end
end

function setAllMXALEDsColor(color)
  for _, device in pairs(compMicMXA) do
    if device and device.LedUnmuteColor then
      device.LedUnmuteColor.String = color
    end
  end
end

function isCallOffHook()
  return compCallSync and compCallSync["off.hook"] and compCallSync["off.hook"].Boolean
end

function getCallMuteState()
  return compCallSync and compCallSync["mute"] and compCallSync["mute"].Boolean or false
end

function setPrivacyLEDColor(privacyState)
  local color = privacyState and ledRed or ledGreen
  setAllMXALEDsColor(color)
end

function setFireAlarm(active)
  fireAlarm = active
  if active then
    timerLEDToggle:Start(ledToggleInterval)
    setPrivacyLEDColor(true)
    setAllMXALEDs(false)
    return
  end

  timerLEDToggle:Stop()
  if not compCallSync or not compCallSync["off.hook"] then return end
  local offHook = compCallSync["off.hook"].Boolean
  setPrivacyLEDColor(not offHook)
  setAllMXALEDs(offHook)
end

function reconcileHookMuteState()
  if isCallOffHook() then
    setPrivacyLEDColor(getCallMuteState())
  end
end

function setHookState(offHook)
  if offHook then
    setAllMXALEDs(true)
    setPrivacyLEDColor(false)
    Timer.CallAfter(reconcileHookMuteState, hookMuteSyncDelay)
  else
    setAllMXALEDs(false)
  end
end

function setMuteState(muteState)
  setPrivacyLEDColor(muteState)
end

-------------------[ Components ]-------------------

function setcompCallSync()
  compCallSync = setComp(Controls.compCallSync, "Call Sync")
  if not compCallSync then return end

  if compCallSync["off.hook"] then
    compCallSync["off.hook"].EventHandler = function(ctl)
      debugMsg("Off-hook " .. tostring(ctl.Boolean))
      setHookState(ctl.Boolean)
    end
  end
  if compCallSync["mute"] then
    compCallSync["mute"].EventHandler = function(ctl)
      debugMsg("Mute " .. tostring(ctl.Boolean))
      setMuteState(ctl.Boolean)
    end
  end
end

function setcompRoomControls()
  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if not compRoomControls then return end

  if compRoomControls.ledSystemPower then
    compRoomControls.ledSystemPower.EventHandler = function(ctl)
      if not ctl.Boolean then
        setPrivacyLEDColor(true)
        setAllMXALEDs(false)
        debugMsg("System power OFF")
      else
        debugMsg("System power ON")
      end
    end
  end
  if compRoomControls.ledFireAlarm then
    compRoomControls.ledFireAlarm.EventHandler = function(ctl)
      setFireAlarm(ctl.Boolean)
    end
  end
end

function setcompMXA(idx)
  local devs = getMXAControls()
  if not devs[idx] then return end

  compMicMXA[idx] = setComp(devs[idx], "MXA [" .. idx .. "]")
end

function setcompAllMXA()
  for idx in pairs(compMicMXA) do compMicMXA[idx] = nil end
  for i in ipairs(getMXAControls()) do
    setcompMXA(i)
  end
end

-------------------[ Event Handlers ]-------------------

timerLEDToggle.EventHandler = function()
  ledState = not ledState
  setAllMXALEDs(ledState)
end

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end

if Controls.compCallSync then
  Controls.compCallSync.EventHandler = setcompCallSync
end

for i, ctl in ipairs(getMXAControls()) do
  ctl.EventHandler = function()
    setcompMXA(i)
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  getComponentNames()
  setcompCallSync()
  setcompRoomControls()
  setcompAllMXA()
  setPrivacyLEDColor(true)
  setAllMXALEDs(false)
end

funcInit()
