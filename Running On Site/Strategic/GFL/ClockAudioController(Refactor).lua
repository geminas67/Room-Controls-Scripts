--[[
  ClockAudioCDTMicController - Q-SYS Control Script for ClockAudio CDT 100
  Author: Nikolas Smith, Q-SYS
  Date: 2026-03-11
  Version: 4.0
  Firmware Req: 10.3.0  

  ClockAudio CDT mic boxes, call sync, mic mixer, and room controls.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync     = "call_sync",
  micBoxes     = "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3",
  micMixer     = "mixer",
  roomControls = "device_controller_script",
}

-- Each entry: {box, buttons = {{toggle, ledIdx, mixerInput}, ...}}
-- toggle=ButtonState num, ledIdx=LED/privacy index, mixerInput=mixer channel
micButtonConfigs = {
  {box = 1, buttons = {{6,1,1}, {8,2,2}, {10,3,3}}},
  {box = 2, buttons = {{6,1,4}, {8,2,5}, {10,3,6}, {12,4,7}}},
  {box = 3, buttons = {{6,1,8}, {8,2,9}, {10,3,10}, {12,4,11}}},
  {box = 4, buttons = {{6,1,12}, {8,2,13}, {10,3,14}}},
}

-------------------[ Constant Tables ]-------------------

compMicBoxes = {}
compInvalid = {}
compCallSync = nil
compMicMixer = nil
compRoomControls = nil

-------------------[ Constants ]-------------------

stateDebug = false
strClear = "[Clear]"
roomName = "[ClockAudio CDT]"

globalMute = false
offHook = false
systemPower = true
fireAlarm = false
ledState = false
toggleInterval = 1.0

timerLEDToggle = Timer.New()

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  local line = "[" .. roomName .. "] " .. str
  print(line)
  local current = Controls.txtConsole.String or ""
  if current == "" or current == " " then
    Controls.txtConsole.String = line
  else
    Controls.txtConsole.String = current .. "\n" .. line
  end
end

-------------------[ Status ]-------------------

function getStatus()
  for i, v in pairs(compInvalid) do
    if v == true then
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
  debugMsg("Setting Component: " .. componentType)
  local componentName = ctl.String
  if componentName == "" then
    ctl.Color = "white"
    setCompValid(componentType)
    return nil
  elseif componentName == strClear then
    ctl.String = ""
    ctl.Color = "white"
    setCompValid(componentType)
    return nil
  elseif #Component.GetControls(Component.New(componentName)) < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    return nil
  else
    ctl.Color = "white"
    setCompValid(componentType)
    return Component.New(componentName)
  end
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local tblNames = {
    namesRoomControls = {},
    namesCallSync = {},
    namesMicBox = {},
    namesMicMixer = {},
  }

  for i, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.callSync then
      table.insert(tblNames.namesCallSync, comp.Name)
    elseif comp.Type == componentTypes.micBoxes then
      table.insert(tblNames.namesMicBox, comp.Name)
    elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
      table.insert(tblNames.namesRoomControls, comp.Name)
    elseif comp.Type == componentTypes.micMixer then
      table.insert(tblNames.namesMicMixer, comp.Name)
    end
  end

  for i, tbl in pairs(tblNames) do
    table.sort(tbl)
    table.insert(tbl, strClear)
  end

  local function fillChoices(ctl, names)
    if not ctl then return end
    ctl.Choices = names
    if #names == 2 and (not ctl.String or ctl.String == "") then
      ctl.String = names[1]
      debugMsg("Auto-selected: " .. names[1])
    end
  end

  fillChoices(Controls.compRoomControls, tblNames.namesRoomControls)
  fillChoices(Controls.compCallSync, tblNames.namesCallSync)
  fillChoices(Controls.compMicMixer, tblNames.namesMicMixer)
  if Controls.compMicBox then
    for i, ctl in ipairs(Controls.compMicBox) do
      fillChoices(ctl, tblNames.namesMicBox)
    end
  end
end

-------------------[ LEDs ]-------------------

function getBoxConfig(boxIdx)
  for i, cfg in ipairs(micButtonConfigs) do
    if cfg.box == boxIdx then return cfg end
  end
  return nil
end

function setLED(stateVal)
  ledState = stateVal
  local greenValue = stateVal and 1 or 0
  for i, cfg in ipairs(micButtonConfigs) do
    local box = compMicBoxes[cfg.box]
    if box then
      for j, btn in ipairs(cfg.buttons) do
        local redInput = box["RedBrightnessInput " .. btn[2]]
        local greenInput = box["GreenBrightnessInput " .. btn[2]]
        if redInput then redInput.Position = 0 end
        if greenInput then greenInput.Position = greenValue end
      end
    end
  end
end

function turnOffAllLEDs()
  for i, cfg in ipairs(micButtonConfigs) do
    local box = compMicBoxes[cfg.box]
    if box then
      for j, btn in ipairs(cfg.buttons) do
        local redInput = box["RedBrightnessInput " .. btn[2]]
        local greenInput = box["GreenBrightnessInput " .. btn[2]]
        if redInput then redInput.Position = 0 end
        if greenInput then greenInput.Position = 0 end
      end
    end
  end
end

function updateIndividualLEDs()
  if not offHook then return end
  for i, cfg in ipairs(micButtonConfigs) do
    local box = compMicBoxes[cfg.box]
    if box then
      for j, btn in ipairs(cfg.buttons) do
        local buttonState = box["ButtonState " .. btn[1]]
        local redInput = box["RedBrightnessInput " .. btn[2]]
        local greenInput = box["GreenBrightnessInput " .. btn[2]]
        if buttonState and redInput and greenInput then
          if not buttonState.Boolean then
            redInput.Position = 0
            greenInput.Position = 0
          elseif globalMute then
            redInput.Position = 1
            greenInput.Position = 0
          else
            redInput.Position = 0
            greenInput.Position = 1
          end
        end
      end
    end
  end
end

-------------------[ Mic ]-------------------

function updatePrivacyButtonStates(boxIndex)
  local box = compMicBoxes[boxIndex]
  local cfg = getBoxConfig(boxIndex)
  if not box or not cfg then return end
  for i, btn in ipairs(cfg.buttons) do
    local toggleButton = box["ButtonState " .. btn[1]]
    local privacyButton = box["ButtonState " .. btn[2]]
    if toggleButton and privacyButton then
      privacyButton.IsDisabled = not toggleButton.Boolean
    end
  end
end

function toggleMic(boxIndex, ledIndex, mixerInput)
  local box = compMicBoxes[boxIndex]
  if not box or not compMicMixer then return end
  local cfg = getBoxConfig(boxIndex)
  if not cfg then return end
  local toggle = nil
  for i, btn in ipairs(cfg.buttons) do
    if btn[2] == ledIndex then toggle = btn[1]; break end
  end
  if not toggle then return end
  local buttonState = box["ButtonState " .. toggle]
  if not buttonState then return end
  local muteCtrl = compMicMixer["input." .. mixerInput .. ".mute"]
  if muteCtrl then muteCtrl.Boolean = not buttonState.Boolean end
  updateIndividualLEDs()
  updatePrivacyButtonStates(boxIndex)
end

function setGlobalMute(muteState)
  globalMute = muteState
  if compCallSync and compCallSync["mute"] then
    compCallSync["mute"].Boolean = muteState
  end
  if offHook then updateIndividualLEDs() end
end

function setHookState(hookState)
  offHook = hookState
  if hookState then
    updateIndividualLEDs()
  else
    turnOffAllLEDs()
  end
end

function syncLEDStates()
  if not compCallSync then return end
  local offHookCtl = compCallSync["off.hook"]
  local muteCtl = compCallSync["mute"]
  if not (offHookCtl and muteCtl) then return end
  offHook = offHookCtl.Boolean
  globalMute = muteCtl.Boolean
  if offHook then
    updateIndividualLEDs()
  else
    turnOffAllLEDs()
  end
end

-------------------[ Components ]-------------------

function setcompRoomControls()
  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if compRoomControls ~= nil then
    if compRoomControls.ledSystemPower then
      compRoomControls.ledSystemPower.EventHandler = function(ctl)
        systemPower = ctl.Boolean
        debugMsg("System power " .. (ctl.Boolean and "ON" or "OFF"))
        if not ctl.Boolean then
          globalMute = true
          setHookState(false)
        end
      end
    end
    if compRoomControls.ledFireAlarm then
      compRoomControls.ledFireAlarm.EventHandler = function(ctl)
        fireAlarm = ctl.Boolean
        debugMsg("Fire alarm " .. (ctl.Boolean and "ON" or "OFF"))
        if ctl.Boolean then
          timerLEDToggle:Start(toggleInterval)
          globalMute = true
          setHookState(false)
        else
          timerLEDToggle:Stop()
          if offHook then setHookState(true) end
        end
      end
    end
    if compRoomControls["roomName"] and compRoomControls["roomName"].String ~= "" then
      roomName = "[" .. compRoomControls["roomName"].String .. "]"
    end
  end
end

function setcompCallSync()
  compCallSync = setComp(Controls.compCallSync, "Call Sync")
  if compCallSync ~= nil then
    if compCallSync["off.hook"] then
      compCallSync["off.hook"].EventHandler = function(ctl)
        debugMsg("Off-hook " .. (ctl.Boolean and "ON" or "OFF"))
        setHookState(ctl.Boolean)
      end
    end
    if compCallSync["mute"] then
      compCallSync["mute"].EventHandler = function(ctl)
        debugMsg("Global mute " .. (ctl.Boolean and "ON" or "OFF"))
        setGlobalMute(ctl.Boolean)
      end
    end
    syncLEDStates()
  end
end

function setcompMicMixer()
  compMicMixer = setComp(Controls.compMicMixer, "Mic Mixer")
end

function setcompMicBox(idx)
  local key = "MicBox" .. string.format("%02d", idx)
  if not Controls.compMicBox or not Controls.compMicBox[idx] then return end
  compMicBoxes[idx] = setComp(Controls.compMicBox[idx], key)
  local box = compMicBoxes[idx]
  if box == nil then return end

  local cfg = getBoxConfig(idx)
  if not cfg then return end

  for i, btn in ipairs(cfg.buttons) do
    local toggleBtn = box["ButtonState " .. btn[1]]
    if toggleBtn then
      local boxIdx, ledIdx, mixerIdx = idx, btn[2], btn[3]
      toggleBtn.EventHandler = function()
        toggleMic(boxIdx, ledIdx, mixerIdx)
      end
    end
    local privacyBtn = box["ButtonState " .. btn[2]]
    if privacyBtn then
      local boxIndex, privacyNum = idx, btn[2]
      privacyBtn.EventHandler = function(ctl)
        if not ctl.Boolean or ctl.IsDisabled then return end
        if compCallSync and compCallSync["mute"] then
          compCallSync["mute"].Boolean = not compCallSync["mute"].Boolean
          if offHook then updateIndividualLEDs() end
        end
      end
    end
  end

  updatePrivacyButtonStates(idx)
end

-------------------[ Event Handlers ]-------------------

timerLEDToggle.EventHandler = function()
  ledState = not ledState
  setLED(ledState)
end

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end
if Controls.compCallSync then
  Controls.compCallSync.EventHandler = setcompCallSync
end
if Controls.compMicMixer then
  Controls.compMicMixer.EventHandler = setcompMicMixer
end
if Controls.compMicBox then
  for i, v in ipairs(Controls.compMicBox) do
    v.EventHandler = function()
      setcompMicBox(i)
    end
  end
end
Controls.btnClearConsole.EventHandler = function()
  Controls.txtConsole.String = " "
end

-------------------[ Always Run ]-------------------

function funcInit()
  getComponentNames()
  setcompRoomControls()
  setcompCallSync()
  setcompMicMixer()
  if Controls.compMicBox then
    for i, v in ipairs(Controls.compMicBox) do
      setcompMicBox(i)
    end
  end
  syncLEDStates()
end

funcInit()
