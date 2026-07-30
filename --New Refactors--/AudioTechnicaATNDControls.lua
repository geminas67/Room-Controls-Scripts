--[[
  ATNDController - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2025-09-10
  Version: 4.1
  Firmware Req: 10.0.0

  Audio-Technica ATND mic LEDs via call sync, room controls, and mute.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync     = "call_sync",
  micATND      = "%PLUGIN%_005284C9-04CA-43c1-8D87-EEB0803B4AD9_%FP%_30fd6e855cd3e1f89b7105fc0eb1ce08",
  roomControls = "device_controller_script",
}

-------------------[ Constant Tables ]-------------------

compCallSync = nil
compRoomControls = nil
compMicATND = {}
compInvalid = {}

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[ATND Controller]"

ledBlack = "Black"
ledRed = "Red"
ledGreen = "Green"
ledToggleInterval = 1.5

fireAlarm = false
audioPrivacy = false
ledState = false

timerLEDToggle = Timer.New()

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print("[" .. roomName .. "] " .. str) end
end

function getATNDControls()
  if not Controls.devATND then return {} end
  if Controls.devATND[1] then return Controls.devATND end
  return { Controls.devATND }
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
  local names = { RoomControls = {}, CallSync = {}, ATND = {} }

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.callSync then
      table.insert(names.CallSync, comp.Name)
    elseif comp.Type == componentTypes.micATND then
      table.insert(names.ATND, comp.Name)
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
  for _, ctl in ipairs(getATNDControls()) do
    ctl.Choices = names.ATND
  end
end

-------------------[ LEDs ]-------------------

function setAllATNDLEDsColor(color)
  for _, device in pairs(compMicATND) do
    if device and device["LEDColorUnmuted"] then
      device["LEDColorUnmuted"].String = color
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
  local color
  if isCallOffHook() or fireAlarm then
    color = privacyState and ledRed or ledGreen
  else
    color = ledBlack
  end
  setAllATNDLEDsColor(color)
end

function setAllATNDLEDs(ledOn)
  if not ledOn then
    setAllATNDLEDsColor(ledBlack)
    return
  end
  if fireAlarm then
    setAllATNDLEDsColor(ledRed)
    return
  end
  setPrivacyLEDColor(getCallMuteState())
end

function setFireAlarm(active)
  fireAlarm = active
  if active then
    timerLEDToggle:Start(ledToggleInterval)
    setPrivacyLEDColor(true)
    setAllATNDLEDs(false)
    return
  end

  timerLEDToggle:Stop()
  if not compCallSync or not compCallSync["off.hook"] then return end
  local offHook = compCallSync["off.hook"].Boolean
  setPrivacyLEDColor(not offHook)
  setAllATNDLEDs(offHook)
end

function setHookState(offHook)
  setAllATNDLEDs(offHook)
  setPrivacyLEDColor(getCallMuteState())
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
        setAllATNDLEDs(false)
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

function setcompATND(idx)
  local devs = getATNDControls()
  if not devs[idx] then return end

  compMicATND[idx] = setComp(devs[idx], "ATND [" .. idx .. "]")
end

function setcompAllATND()
  for idx in pairs(compMicATND) do compMicATND[idx] = nil end
  for i in ipairs(getATNDControls()) do
    setcompATND(i)
  end
end

-------------------[ Event Handlers ]-------------------

timerLEDToggle.EventHandler = function()
  ledState = not ledState
  setAllATNDLEDs(ledState)
end

if Controls.btnMute then
  Controls.btnMute.EventHandler = function(ctl)
    audioPrivacy = ctl.Boolean
    setPrivacyLEDColor(ctl.Boolean)
  end
end

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end

if Controls.compCallSync then
  Controls.compCallSync.EventHandler = setcompCallSync
end

for i, ctl in ipairs(getATNDControls()) do
  ctl.EventHandler = function()
    setcompATND(i)
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  getComponentNames()
  setcompCallSync()
  setcompRoomControls()
  setcompAllATND()
  setPrivacyLEDColor(true)
  setAllATNDLEDs(false)
end

funcInit()
