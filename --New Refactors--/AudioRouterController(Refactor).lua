---@diagnostic disable: missing-fields
--[[
  Audio Router Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2025-03-24
  Version: 3.1
  Firmware Req: 10.0.0

  Routes default program audio via router output 1; syncs source buttons and room power/fire alarm.

]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  audioRouter  = "router_with_output",
  roomControls = "device_controller_script",
}

defaultOutput = 1

inputRoutes = {
  input01 = 1,
  input02 = 2,
  input03 = 3,
  input04 = 4,
  input05 = 5,
  input06 = 6,
  input07 = 7,
  input08 = 8,
  none    = 9,
}

inputLabels = {
  "Input 1", "Input 2", "Input 3", "Input 4",
  "Input 5", "Input 6", "Input 7", "Input 8", "None",
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compAudioRouter = nil
compRoomControls = nil
lastRouteInput = {}

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "Audio Router"

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print("[" .. roomName .. "] " .. str)
end

function validateControls()
  local required = {
    "compAudioRouter",
    "btnSource",
    "defaultInput",
    "txtStatus",
    "compRoomControls",
  }
  local missing = {}
  for _, name in ipairs(required) do
    if not Controls[name] then table.insert(missing, name) end
  end
  if #missing == 0 then return true end
  print("ERROR: AudioRouterController missing required controls:")
  for _, name in ipairs(missing) do print("  - " .. name) end
  return false
end

function normalizeSourceButtons()
  if not Controls.btnSource then
    Controls.btnSource = {}
    return
  end
  if not Controls.btnSource[1] then
    Controls.btnSource = { Controls.btnSource }
  end
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
  if not ctl then
    setCompInvalid(componentType)
    return nil
  end
  local componentName = ctl.String
  if not componentName or componentName == "" then
    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("No " .. componentType .. " component selected")
    return nil
  end
  if componentName == strClear then
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
  local selection = Controls.defaultInput and Controls.defaultInput.Value or 0
  return selection > 0 and selection or 1
end

function setRoute(input, output, source)
  if not compAudioRouter then return end
  local selectCtrl = compAudioRouter["select." .. tostring(output)]
  if not selectCtrl then return end
  if selectCtrl.Value == input then return end
  selectCtrl.Value = input
  if input ~= inputRoutes.none then
    lastRouteInput[output] = input
  end
  debugMsg(
    "Route: Output " .. tostring(output) .. " → Input " .. tostring(input)
      .. " (Source: " .. tostring(source) .. ")"
  )
end

function initDefaultInputChoices()
  Controls.defaultInput.Choices = inputLabels
  if Controls.defaultInput.Value == 0 then
    Controls.defaultInput.Value = 1
  end
  debugMsg("Default input choices configured (" .. #inputLabels .. " options)")
end

function syncSourceButtons(inputValue)
  if not Controls.btnSource then return end
  for i, btn in ipairs(Controls.btnSource) do
    if btn then
      local on = (i == inputValue)
      if btn.Boolean ~= on then btn.Boolean = on end
    end
  end
end

function bindSourceButtons()
  if not Controls.btnSource then return end
  for i, btn in ipairs(Controls.btnSource) do
    if btn then
      btn.EventHandler = function()
        setRoute(i, defaultOutput, "Audio Source Button " .. tostring(i))
      end
    end
  end
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  debugMsg("Discovering components...")
  local audioRouterNames = {}
  local roomControlsNames = {}

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.audioRouter then
      table.insert(audioRouterNames, comp.Name)
      debugMsg("  Found audio router: " .. comp.Name)
    elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
      table.insert(roomControlsNames, comp.Name)
      debugMsg("  Found room controls: " .. comp.Name)
    end
  end

  table.sort(audioRouterNames)
  table.insert(audioRouterNames, strClear)
  Controls.compAudioRouter.Choices = audioRouterNames

  table.sort(roomControlsNames)
  table.insert(roomControlsNames, strClear)
  Controls.compRoomControls.Choices = roomControlsNames

  debugMsg(
    "Discovery complete — audio routers: " .. (#audioRouterNames - 1)
      .. ", room controls: " .. (#roomControlsNames - 1)
  )
end

-------------------[ Components ]-------------------

function setcompAudioRouter()
  if compAudioRouter and compAudioRouter["select.1"] then
    compAudioRouter["select.1"].EventHandler = nil
  end

  compAudioRouter = setComp(Controls.compAudioRouter, "Audio Router")
  if not compAudioRouter or not compAudioRouter["select.1"] then return end

  compAudioRouter["select.1"].EventHandler = function(ctl)
    syncSourceButtons(ctl.Value)
    debugMsg("Router feedback: Output 1 → Input " .. ctl.Value .. " (Source: Audio Router)")
  end
  debugMsg("Registered audio router output feedback handler")
end

function setcompRoomControls()
  if compRoomControls then
    if compRoomControls["ledSystemPower"] then
      compRoomControls["ledSystemPower"].EventHandler = nil
    end
    if compRoomControls["ledFireAlarm"] then
      compRoomControls["ledFireAlarm"].EventHandler = nil
    end
  end

  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if not compRoomControls then return end

  local ledPower = compRoomControls["ledSystemPower"]
  if ledPower then
    ledPower.EventHandler = function(ctl)
      local route = ctl.Boolean and getDefaultInput() or inputRoutes.none
      setRoute(route, defaultOutput, "Room Controls — System Power")
    end
    debugMsg("Registered: ledSystemPower (Room Controls)")
  end

  local ledFire = compRoomControls["ledFireAlarm"]
  if ledFire then
    ledFire.EventHandler = function(ctl)
      if ctl.Boolean then
        setRoute(inputRoutes.none, defaultOutput, "Room Controls — Fire Alarm (active)")
      else
        local powerLed = compRoomControls["ledSystemPower"]
        if powerLed and powerLed.Boolean then
          local defaultRoute = lastRouteInput[defaultOutput] or getDefaultInput()
          setRoute(defaultRoute, defaultOutput, "Room Controls — Fire Alarm (cleared)")
        end
      end
    end
    debugMsg("Registered: ledFireAlarm (Room Controls)")
  end
end

function initAudioRouterController()
  if compAudioRouter and compAudioRouter["select.1"] then
    compAudioRouter["select.1"].EventHandler = nil
  end
  if compRoomControls then
    if compRoomControls["ledSystemPower"] then
      compRoomControls["ledSystemPower"].EventHandler = nil
    end
    if compRoomControls["ledFireAlarm"] then
      compRoomControls["ledFireAlarm"].EventHandler = nil
    end
  end
  debugMsg("Cleanup complete")
end

-------------------[ Event Handlers ]-------------------

normalizeSourceButtons()
bindSourceButtons()

if Controls.compAudioRouter then
  Controls.compAudioRouter.EventHandler = function()
    debugMsg("Component selector changed (Source: Audio Router dropdown)")
    setcompAudioRouter()
  end
end

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = function()
    debugMsg("Component selector changed (Source: Room Controls dropdown)")
    setcompRoomControls()
  end
end

-------------------[ Public API ]-------------------

AudioRouterController = {
  setRoute = function(input, output)
    setRoute(input, output or defaultOutput, "External API")
  end,
  cleanup = initAudioRouterController,
}

-------------------[ Always Run ]-------------------

function funcInit()
  if not validateControls() then
    if Controls.txtStatus then
      Controls.txtStatus.String = "INIT FAILED"
      Controls.txtStatus.Value = 2
    end
    return
  end

  debugMsg("=== Initialization Started ===")

  getComponentNames()
  initDefaultInputChoices()
  setcompAudioRouter()
  setcompRoomControls()

  debugMsg("=== Initialization Complete ===")
end

funcInit()
