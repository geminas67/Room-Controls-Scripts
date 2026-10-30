--[[
  Audio Router Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-10-28
  Version: 3.2
  Firmware Req: 10.0.0

  Routes program audio on one router output; syncs source buttons with room power and fire alarm.

]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  audioRouter  = "router_with_output",
  roomControls = "device_controller_script",
}

routerOutput = 1

inputLabels = {
  "Input 1", "Input 2", "Input 3", "Input 4",
  "Input 5", "Input 6", "Input 7", "Input 8", "None",
}

inputNone = 9  -- router input left unpatched (silent route)

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compAudioRouter = nil
compRoomControls = nil

-- Single control is userdata; a control array is a Lua table
btnSource = type(Controls.btnSource) == "table" and Controls.btnSource or { Controls.btnSource }

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "Audio Router"
lastInput = nil  -- last real source; restored when the fire alarm clears

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print("[" .. roomName .. "] " .. str) end
end

function validateControls()
  local missing = {}
  for _, name in ipairs({ "compAudioRouter", "compRoomControls", "btnSource", "defaultInput", "txtStatus" }) do
    if not Controls[name] then table.insert(missing, name) end
  end
  if #missing == 0 then return true end
  print("ERROR: AudioRouterController missing required controls: " .. table.concat(missing, ", "))
  return false
end

-------------------[ Status ]-------------------

function getStatus()
  for _, isInvalid in pairs(compInvalid) do
    if isInvalid then
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
  local componentName = ctl.String
  if componentName == "" or componentName == strClear then
    ctl.String = ""
    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("No " .. componentType .. " component selected")
    return nil
  end
  local comp = Component.New(componentName)
  local ctrlList = comp and Component.GetControls(comp)
  if not ctrlList or #ctrlList < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    debugMsg("ERROR: Invalid component '" .. componentName .. "' for " .. componentType)
    return nil
  end
  ctl.Color = "white"
  setCompValid(componentType)
  debugMsg("Connected " .. componentType .. ": " .. componentName)
  return comp
end

-------------------[ Routing ]-------------------

function getDefaultInput()
  local selected = Controls.defaultInput.String
  for i, label in ipairs(inputLabels) do
    if label == selected then return i end
  end
  return 1
end

function initDefaultInputChoices()
  Controls.defaultInput.Choices = inputLabels
  if Controls.defaultInput.String == "" then
    Controls.defaultInput.String = inputLabels[1]
  end
end

function isFireAlarm()
  local led = compRoomControls and compRoomControls["ledFireAlarm"]
  return led ~= nil and led.Boolean
end

function syncSourceButtons(input)
  for i, btn in ipairs(btnSource) do
    btn.Boolean = (i == input)
  end
end

function setRoute(input, source)
  local selectCtrl = compAudioRouter and compAudioRouter["select." .. routerOutput]
  if not selectCtrl then return end
  if input ~= inputNone and isFireAlarm() then
    syncSourceButtons(selectCtrl.Value)
    debugMsg("Route blocked by fire alarm (Source: " .. source .. ")")
    return
  end
  if input ~= inputNone then lastInput = input end
  syncSourceButtons(input)  -- script writes do not fire the router's EventHandler
  if selectCtrl.Value == input then return end
  selectCtrl.Value = input
  debugMsg("Route: Output " .. routerOutput .. " -> Input " .. input .. " (Source: " .. source .. ")")
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local audioRouterNames = {}
  local roomControlsNames = {}

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.audioRouter then
      table.insert(audioRouterNames, comp.Name)
    elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
      table.insert(roomControlsNames, comp.Name)
    end
  end

  table.sort(audioRouterNames)
  table.insert(audioRouterNames, strClear)
  Controls.compAudioRouter.Choices = audioRouterNames

  table.sort(roomControlsNames)
  table.insert(roomControlsNames, strClear)
  Controls.compRoomControls.Choices = roomControlsNames

  debugMsg("Discovery: " .. (#audioRouterNames - 1) .. " audio routers, " .. (#roomControlsNames - 1) .. " room controls")
end

-------------------[ Components ]-------------------

function setcompAudioRouter()
  local oldSelect = compAudioRouter and compAudioRouter["select." .. routerOutput]
  if oldSelect then oldSelect.EventHandler = nil end

  compAudioRouter = setComp(Controls.compAudioRouter, "Audio Router")
  local selectCtrl = compAudioRouter and compAudioRouter["select." .. routerOutput]
  if not selectCtrl then return end

  selectCtrl.EventHandler = function(ctl)
    if ctl.Value ~= inputNone then lastInput = ctl.Value end
    syncSourceButtons(ctl.Value)
    debugMsg("Router feedback: Output " .. routerOutput .. " -> Input " .. ctl.Value)
  end
  syncSourceButtons(selectCtrl.Value)
end

function setcompRoomControls()
  if compRoomControls then
    for _, name in ipairs({ "ledSystemPower", "ledFireAlarm" }) do
      if compRoomControls[name] then compRoomControls[name].EventHandler = nil end
    end
  end

  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if not compRoomControls then return end

  if compRoomControls["ledSystemPower"] then
    compRoomControls["ledSystemPower"].EventHandler = function(ctl)
      setRoute(ctl.Boolean and getDefaultInput() or inputNone, "System Power")
    end
  end

  if compRoomControls["ledFireAlarm"] then
    compRoomControls["ledFireAlarm"].EventHandler = function(ctl)
      local ledPower = compRoomControls["ledSystemPower"]
      if ctl.Boolean then
        setRoute(inputNone, "Fire Alarm (active)")
      elseif ledPower and ledPower.Boolean then
        setRoute(lastInput or getDefaultInput(), "Fire Alarm (cleared)")
      end
    end
  end
end

-------------------[ Event Handlers ]-------------------

for i, btn in ipairs(btnSource) do
  btn.EventHandler = function()
    setRoute(i, "Source Button " .. i)
  end
end

if Controls.compAudioRouter then Controls.compAudioRouter.EventHandler = setcompAudioRouter end
if Controls.compRoomControls then Controls.compRoomControls.EventHandler = setcompRoomControls end

-------------------[ Always Run ]-------------------

function funcInit()
  if not validateControls() then
    if Controls.txtStatus then
      Controls.txtStatus.String = "INIT FAILED"
      Controls.txtStatus.Value = 2
    end
    return
  end

  getComponentNames()
  initDefaultInputChoices()
  setcompAudioRouter()
  setcompRoomControls()
  debugMsg("Initialization complete")
end

funcInit()
