--[[
  Samsung DisplayController - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-07-30
  Version: 2.0
  Firmware Req: 10.2.0

  Samsung displays plugin v1.5 — power management and input switching.
  Integrates with SystemAutomationController.
  Per-row On/Off booleans follow reported PowerStatus (setPowerOnOffRowFeedback).

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  displays     = "%PLUGIN%_bd0a5e74-c1bf-48ee-8574-e42e1e7b2bb9_%FP%_31e2e2d7be2243768d2bd9c853a6295c",
  roomControls = "device_controller_script",
}

local displayControls = {
  powerOn             = "PowerOn",
  powerOff            = "PowerOff",
  powerStatus         = "PowerStatus",
  inputSelectComboBox = "InputSelectComboBox",
  ledInputStatus      = "InputStatus",
  inputButtons        = "InputButtons",
  currentInput        = "Input",
  displayVolume0      = "Volume",
}

local inputButtonMap = {
  HDMI1 = 1, 
  HDMI2 = 2, 
  HDMI3 = 3, 
  HDMI4 = 4,
  DisplayPort1 = 5, 
  DisplayPort2 = 6, 
  DisplayPort3 = 7,
  DTV = 8,
  S_Video   = 9, 
  Component = 10,
  USB_C     = 11,
}

-------------------[ Constant Tables ]-------------------

compDisplays = {}
compInvalid = {}
compRoomControls = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[Samsung Display]"
maxDisplays = 9
defaultInput = "HDMI1"
warmupTime = 7
cooldownTime = 5
lastInput = "HDMI1"
powerState = false
isWarming = false
isCooling = false

timerWarmup = Timer.New()
timerCooldown = Timer.New()
timerVolumeMute = {}
for idx = 1, maxDisplays do
  timerVolumeMute[idx] = Timer.New()
end

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print("[" .. roomName .. "] " .. str)
end

function normalizeDisplayArrays()
  for _, name in ipairs({"devDisplay", "btnPowerOn", "btnPowerOff", "btnPowerToggle"}) do
    local ctrl = Controls[name]
    if ctrl and type(ctrl) == "table" and ctrl[1] == nil then
      Controls[name] = { ctrl }
    end
  end
end

function getRoomName()
  if Controls.compRoomControls and Controls.compRoomControls.String ~= "" and Controls.compRoomControls.String ~= strClear then
    local comp = Component.New(Controls.compRoomControls.String)
    if comp and comp["roomName"] and comp["roomName"].String ~= "" then
      return "[" .. comp["roomName"].String .. "]"
    end
  end
  if Controls.roomName and Controls.roomName.String ~= "" then
    return "[" .. Controls.roomName.String .. "]"
  end
  return "[Samsung Display]"
end

-------------------[ Status ]-------------------

function getStatus()
  for _, invalid in pairs(compInvalid) do
    if invalid then
      debugMsg("Invalid components found")
      Controls.txtStatus.String = "Invalid Components"
      Controls.txtStatus.Value = 1
      return
    end
  end
  debugMsg("Components are valid")
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
  if not name or name == "" or name == strClear then
    if name == strClear then ctl.String = "" end
    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("No " .. componentType .. " component selected")
    return nil
  end
  local comp = Component.New(name)
  local ctrlList = comp and Component.GetControls(comp)
  if not ctrlList or #ctrlList < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    debugMsg("ERROR: Invalid component '" .. name .. "' for " .. componentType)
    return nil
  end
  ctl.Color = "white"
  setCompValid(componentType)
  debugMsg("Connected " .. componentType .. ": " .. name)
  return comp
end

function safeDisplayAccess(component, control, action, value)
  local success, result = pcall(function()
    if not component or not component[control] then return false end
    if action == "trigger" then component[control]:Trigger(); return true end
    if action == "get" then return component[control].Boolean end
    if action == "getString" then return component[control].String end
    if action == "set" then component[control].Boolean = value; return true end
    if action == "setString" then component[control].String = value; return true end
  end)
  return success and result or false
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  debugMsg("Discovering components...")
  local names = { DisplayNames = {}, RoomControlsNames = {} }

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.displays then
      table.insert(names.DisplayNames, comp.Name)
      debugMsg("  Found display: " .. comp.Name)
    elseif comp.Type == componentTypes.roomControls and comp.Name:match("^compRoomControls") then
      table.insert(names.RoomControlsNames, comp.Name)
    end
  end

  for _, list in pairs(names) do
    table.sort(list)
    table.insert(list, strClear)
  end

  if Controls.devDisplay then
    for idx = 1, #Controls.devDisplay do
      Controls.devDisplay[idx].Choices = names.DisplayNames
    end
    debugMsg("Set choices for " .. #Controls.devDisplay .. " display controls")
    debugMsg("Discovery complete - " .. #names.DisplayNames .. " display components found")
  end
  if Controls.compRoomControls then
    Controls.compRoomControls.Choices = names.RoomControlsNames
  end
end

-------------------[ Power ]-------------------

function getInputButtonNumber(input)
  local normalizedInput = input:gsub("USB%-C", "USB_C")
  return inputButtonMap[normalizedInput]
end

function getDisplayCount()
  local count = 0
  for _ in pairs(compDisplays) do count = count + 1 end
  return count
end

function updateTimerConfig()
  if not compRoomControls then
    debugMsg("No room controls component found - Using default timing values")
    return
  end
  local comp = compRoomControls
  local warmup = comp.warmupTime and comp.warmupTime.Value
  local cooldown = comp.cooldownTime and comp.cooldownTime.Value
  if warmup and warmup > 0 then warmupTime = warmup end
  if cooldown and cooldown > 0 then cooldownTime = cooldown end
  debugMsg("Timer config - Warmup: " .. warmupTime .. "s, Cooldown: " .. cooldownTime .. "s")
end

function setPowerOnOffRowFeedback(index, poweredOn)
  if Controls.btnPowerOn and Controls.btnPowerOn[index] then
    Controls.btnPowerOn[index].Boolean = poweredOn
  end
  if Controls.btnPowerOff and Controls.btnPowerOff[index] then
    Controls.btnPowerOff[index].Boolean = not poweredOn
  end
end

function powerAll(onState)
  debugMsg("Powering all displays: " .. tostring(onState) .. " (Source: Power All)")
  local ctrl = onState and displayControls.powerOn or displayControls.powerOff
  for idx, display in pairs(compDisplays) do
    if display then safeDisplayAccess(display, ctrl, "trigger") end
  end
  powerState = onState
end

function powerSingle(index, onState)
  debugMsg("Powering display " .. index .. " to: " .. tostring(onState) .. " (Source: Single Display)")
  local display = compDisplays[index]
  local ctrl = onState and displayControls.powerOn or displayControls.powerOff
  if display then safeDisplayAccess(display, ctrl, "trigger") end
end

function setInputAll(input)
  debugMsg("Setting all displays to input: " .. input .. " (Source: Input All)")
  for idx, display in pairs(compDisplays) do
    if display then
      if display[displayControls.inputSelectComboBox] then
        safeDisplayAccess(display, displayControls.inputSelectComboBox, "setString", input)
      else
        local buttonNumber = getInputButtonNumber(input)
        if buttonNumber then
          local buttonName = displayControls.inputButtons .. buttonNumber .. "Trigger"
          safeDisplayAccess(display, buttonName, "trigger")
        end
      end
    end
  end
  lastInput = input
  if Controls.ledDisplayInput then Controls.ledDisplayInput.String = input end
end

function enablePowerControls(enabled)
  for _, name in ipairs({"btnPowerOn", "btnPowerOff", "btnPowerToggle", "btnPowerAll", "btnInputAll"}) do
    local ctrl = Controls[name]
    if ctrl then
      if type(ctrl) == "table" and ctrl[1] then
        for _, btn in ipairs(ctrl) do btn.IsDisabled = not enabled end
      else
        ctrl.IsDisabled = not enabled
      end
    end
  end
end

function enablePowerControlIndex(index, enabled)
  for _, name in ipairs({"btnPowerOn", "btnPowerOff", "btnPowerToggle"}) do
    local ctrl = Controls[name]
    if ctrl and ctrl[index] then ctrl[index].IsDisabled = not enabled end
  end
end

function updatePowerFeedback()
  local allOn, count = true, 0
  for idx, display in pairs(compDisplays) do
    if display then
      count = count + 1
      local status = safeDisplayAccess(display, displayControls.powerStatus, "get")
      setPowerOnOffRowFeedback(idx, status)
      if Controls.btnPowerToggle and Controls.btnPowerToggle[idx] then
        Controls.btnPowerToggle[idx].Boolean = status
      end
      if not status then allOn = false end
    end
  end
  if count > 0 then
    if Controls.ledDisplayPower then Controls.ledDisplayPower.Boolean = allOn end
    powerState = allOn
    debugMsg("Power feedback updated - Powered: " .. count .. "/" .. getDisplayCount())
  end
end

function setOppositePowerButtonLegend(index, poweringOn)
  local target = poweringOn and Controls.btnPowerOff or Controls.btnPowerOn
  if target and target[index] then target[index].Legend = "Please\nwait" end
end

function resetButtonLegends(index)
  debugMsg("Resetting button legends for [ Display " .. index .. "]")
  if Controls.btnPowerOn and Controls.btnPowerOn[index] then
    Controls.btnPowerOn[index].Legend = "On"
  end
  if Controls.btnPowerOff and Controls.btnPowerOff[index] then
    Controls.btnPowerOff[index].Legend = "Off"
  end
end

function powerOnDisplay(index)
  debugMsg("Powering on display " .. index .. " (Source: Power On Button)")
  powerSingle(index, true)
  enablePowerControlIndex(index, false)
  setOppositePowerButtonLegend(index, true)
  isWarming = true
  if Controls.ledDisplayWarming then Controls.ledDisplayWarming.Boolean = true end
  timerWarmup:Start(warmupTime)
  if timerVolumeMute[index] then timerVolumeMute[index]:Start(5) end
end

function powerOffDisplay(index)
  debugMsg("Powering off display " .. index .. " (Source: Power Off Button)")
  powerSingle(index, false)
  enablePowerControlIndex(index, false)
  setOppositePowerButtonLegend(index, false)
  isCooling = true
  if Controls.ledDisplayCooling then Controls.ledDisplayCooling.Boolean = true end
  timerCooldown:Start(cooldownTime)
end

function powerOnAll()
  debugMsg("Powering on all displays (Source: Power All Button)")
  powerAll(true)
  enablePowerControls(false)
  isWarming = true
  if Controls.ledDisplayWarming then Controls.ledDisplayWarming.Boolean = true end
  timerWarmup:Start(warmupTime)
end

function powerOffAll()
  debugMsg("Powering off all displays (Source: Power All Button)")
  powerAll(false)
  enablePowerControls(false)
  isCooling = true
  if Controls.ledDisplayCooling then Controls.ledDisplayCooling.Boolean = true end
  timerCooldown:Start(cooldownTime)
end

-------------------[ Components ]-------------------

function setupDisplayEvents(index)
  local display = compDisplays[index]
  if not display or not display[displayControls.powerStatus] then return end
  display[displayControls.powerStatus].EventHandler = function()
    updatePowerFeedback()
  end
  debugMsg("Registered: power status handler for display " .. index)
end

function setcompDisplay(index)
  if not Controls.devDisplay or not Controls.devDisplay[index] then return end
  compDisplays[index] = setComp(Controls.devDisplay[index], "Display [" .. index .. "]")
  if compDisplays[index] then
    debugMsg("Successfully set up display component " .. index)
    setupDisplayEvents(index)
    updatePowerFeedback()
  else
    debugMsg("Failed to set up display component " .. index)
  end
end

function setcompRoomControls()
  debugMsg("Setting room controls component")
  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if compRoomControls then
    updateTimerConfig()
    local roomNameCtrl = compRoomControls["roomName"]
    if roomNameCtrl and roomNameCtrl.String ~= "" then
      roomName = "[" .. roomNameCtrl.String .. "]"
      debugMsg("Room name updated to: " .. roomName)
    end
  end
end

-------------------[ Event Handlers ]-------------------

timerWarmup.EventHandler = function()
  debugMsg("Warmup period ended (Source: Timer)")
  enablePowerControls(true)
  if Controls.devDisplay then
    for idx = 1, #Controls.devDisplay do
      enablePowerControlIndex(idx, true)
      resetButtonLegends(idx)
    end
  end
  isWarming = false
  if Controls.ledDisplayWarming then Controls.ledDisplayWarming.Boolean = false end
  timerWarmup:Stop()
end

timerCooldown.EventHandler = function()
  debugMsg("Cooldown period ended (Source: Timer)")
  enablePowerControls(true)
  if Controls.devDisplay then
    for idx = 1, #Controls.devDisplay do
      enablePowerControlIndex(idx, true)
      resetButtonLegends(idx)
    end
  end
  isCooling = false
  if Controls.ledDisplayCooling then Controls.ledDisplayCooling.Boolean = false end
  timerCooldown:Stop()
end

for idx = 1, maxDisplays do
  timerVolumeMute[idx].EventHandler = function()
    local display = compDisplays[idx]
    if display then
      debugMsg("Muting volume for display " .. idx .. " (Source: Timer)")
      safeDisplayAccess(display, displayControls.displayVolume0, "trigger")
    end
    timerVolumeMute[idx]:Stop()
  end
end

normalizeDisplayArrays()

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end

if Controls.btnPowerAll then
  Controls.btnPowerAll.EventHandler = function(ctl)
    if ctl.Boolean then powerOnAll() else powerOffAll() end
  end
end

if Controls.btnInputAll then
  Controls.btnInputAll.EventHandler = function()
    setInputAll(defaultInput)
  end
end

if Controls.btnPowerOn then
  for i, btn in ipairs(Controls.btnPowerOn) do
    btn.EventHandler = function()
      powerOnDisplay(i)
    end
  end
end

if Controls.btnPowerOff then
  for i, btn in ipairs(Controls.btnPowerOff) do
    btn.EventHandler = function()
      powerOffDisplay(i)
    end
  end
end

if Controls.btnPowerToggle then
  for i, btn in ipairs(Controls.btnPowerToggle) do
    btn.EventHandler = function(ctl)
      if ctl.Boolean then powerOnDisplay(i) else powerOffDisplay(i) end
    end
  end
end

if Controls.devDisplay then
  for i, ctl in ipairs(Controls.devDisplay) do
    ctl.EventHandler = function()
      setcompDisplay(i)
    end
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  roomName = getRoomName()
  debugMsg("=== Initialization Started ===")
  debugMsg("Configuration: roomName=" .. roomName .. ", debugging=" .. tostring(stateDebug))

  if not Controls.txtStatus or not Controls.devDisplay then
    print("ERROR: Missing required controls (txtStatus, devDisplay)")
    if Controls.txtStatus then
      Controls.txtStatus.String = "INIT FAILED"
      Controls.txtStatus.Value = 2
    end
    return
  end

  getComponentNames()
  setcompRoomControls()
  if Controls.devDisplay then
    for idx = 1, #Controls.devDisplay do
      setcompDisplay(idx)
    end
  end
  updatePowerFeedback()

  debugMsg("=== Initialization Complete ===")
  debugMsg("Ready for operation - " .. getDisplayCount() .. " displays")
end

funcInit()

-------------------[ Public API ]-------------------

DisplayController = {
  powerOnAll = powerOnAll,
  powerOffAll = powerOffAll,
  setInputAll = setInputAll,
  getDisplayCount = getDisplayCount,
}
