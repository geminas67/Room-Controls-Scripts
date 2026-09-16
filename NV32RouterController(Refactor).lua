--[[
  NV32 Router Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-06-26
  Version: 4.0
  Firmware Req: 10.0.0

  NV32 HDMI routing, room controls (power / fire alarm), optional UCI nav sync.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  nv32Router   = "streamer_hdmi_switcher",
  roomControls = "device_controller_script",
}

local inputs = {
  Graphic1 = 1,
  Graphic2 = 2,
  Graphic3 = 3,
  HDMI1    = 4,
  HDMI2    = 5,
  HDMI3    = 6,
  AV1      = 7,
  AV2      = 8,
  AV3      = 9,
}

local outputs = { Output01 = 1, Output02 = 2 }

-- Button row order matches uciInputs indices (output preset buttons)
local uciInputs = { inputs.AV1, inputs.AV2, inputs.AV3, inputs.Graphic1, inputs.Graphic2 }

-- UCI nav layer index → uciInputs slot (btnNav07 / btnNav08 / btnNav09)
local uciLayerToInput = {
  [7] = uciInputs[2],
  [8] = uciInputs[1],
  [9] = uciInputs[3],
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compNV32Router = nil
compRoomControls = nil
btnNV32Out01 = nil
btnNV32Out02 = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "NV32 Router"
enableOutput2 = true
uciIntegrationEnabled = true

fireAlarmActive = false
lastInput = {}
preFireAlarmInput = {}
lastUCILayer = nil
uciController = nil

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print("[" .. roomName .. "] " .. str)
end

function normalizeButtonArrays()
  btnNV32Out01 = Controls.btnNV32Out01
  btnNV32Out02 = Controls.btnNV32Out02
  if btnNV32Out01 and type(btnNV32Out01) ~= "table" then btnNV32Out01 = { btnNV32Out01 } end
  if btnNV32Out02 and type(btnNV32Out02) ~= "table" then btnNV32Out02 = { btnNV32Out02 } end
end

-------------------[ Status ]-------------------

function getStatus()
  if not Controls.txtStatus then return end
  for _, invalid in pairs(compInvalid) do
    if invalid == true then
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

function setComp(ctl, componentType, expectedType)
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

  if expectedType and comp.Type ~= expectedType then
    ctl.String = "[Wrong Component Type]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    debugMsg("ERROR: " .. componentType .. " wrong type. Expected " .. tostring(expectedType)
      .. ", got " .. tostring(comp.Type))
    return nil
  end

  ctl.Color = "white"
  setCompValid(componentType)
  debugMsg("Connected " .. componentType .. ": " .. name)
  return comp
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local namesNV32 = {}
  local namesRoomControls = {}

  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.nv32Router then
      table.insert(namesNV32, comp.Name)
      debugMsg("Found NV32: " .. comp.Name)
    elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
      table.insert(namesRoomControls, comp.Name)
      debugMsg("Found Room Controls: " .. comp.Name)
    end
  end

  table.sort(namesNV32)
  table.insert(namesNV32, strClear)
  table.sort(namesRoomControls)
  table.insert(namesRoomControls, strClear)

  local function fillChoices(ctl, names)
    if not ctl then return end
    ctl.Choices = names
    if #names == 2 and (not ctl.String or ctl.String == "") then
      ctl.String = names[1]
      debugMsg("Auto-selected: " .. names[1])
    end
  end

  fillChoices(Controls.devNV32, namesNV32)
  fillChoices(Controls.compRoomControls, namesRoomControls)
  debugMsg("Discovery complete — NV32: " .. (#namesNV32 - 1) .. ", Room Controls: " .. (#namesRoomControls - 1))
end

-------------------[ Routing ]-------------------

function setRoute(input, outputNum, source)
  local src = source or "Internal"
  if outputNum == outputs.Output02 and not enableOutput2 then
    debugMsg("Output02 disabled — skip (Source: " .. src .. ")")
    return false
  end
  if not compNV32Router then
    debugMsg("No NV32 router (Source: " .. src .. ")")
    return false
  end

  local outputControl = compNV32Router["hdmi.out." .. tostring(outputNum) .. ".select.index"]
  if not outputControl then
    debugMsg("Missing output control " .. tostring(outputNum) .. " (Source: " .. src .. ")")
    return false
  end
  if outputControl.Value == input then return false end

  outputControl.Value = input
  lastInput[outputNum] = input
  debugMsg("Output " .. tostring(outputNum) .. " → Input " .. tostring(input) .. " (Source: " .. src .. ")")
  return true
end

-------------------[ UCI ]-------------------

function setupUCINavButtons()
  local uciButtons = {
    [7] = Controls.btnNav07,
    [8] = Controls.btnNav08,
    [9] = Controls.btnNav09,
  }
  for layer, btn in pairs(uciButtons) do
    if btn then
      btn.EventHandler = function(ctl)
        if not uciIntegrationEnabled or not ctl.Boolean then return end
        local targetInput = uciLayerToInput[layer]
        if not targetInput then return end
        debugMsg("UCI nav layer " .. tostring(layer) .. " → Input " .. tostring(targetInput))
        setRoute(targetInput, outputs.Output01, "UCI Nav Button")
      end
      debugMsg("Registered UCI nav monitor: layer " .. tostring(layer))
    end
  end
end

function setUCIController(controller)
  if not controller then
    debugMsg("setUCIController: invalid reference")
    return false
  end
  uciController = controller
  debugMsg("UCI Controller reference set — call onUCILayerChange() from UCI script for layer sync")
  return true
end

function enableUCIIntegration()
  uciIntegrationEnabled = true
  debugMsg("UCI integration enabled")
end

function disableUCIIntegration()
  uciIntegrationEnabled = false
  debugMsg("UCI integration disabled")
end

function onUCILayerChange(layerChangeInfo)
  if not uciIntegrationEnabled or not layerChangeInfo then return end
  local currentLayer = layerChangeInfo.currentLayer
  debugMsg("UCI layer " .. tostring(layerChangeInfo.previousLayer) .. " → "
    .. tostring(currentLayer) .. " (" .. tostring(layerChangeInfo.layerName) .. ")")
  lastUCILayer = currentLayer
  if uciLayerToInput[currentLayer] then
    setRoute(uciLayerToInput[currentLayer], outputs.Output01, "UCI Layer Change")
  end
end

-------------------[ Components ]-------------------

function clearNV32Handlers(router)
  if not router then return end
  if router["hdmi.out.1.select.index"] then router["hdmi.out.1.select.index"].EventHandler = nil end
  if router["hdmi.out.2.select.index"] then router["hdmi.out.2.select.index"].EventHandler = nil end
end

function setcompNV32Router()
  clearNV32Handlers(compNV32Router)
  compNV32Router = setComp(Controls.devNV32, "NV32-H", componentTypes.nv32Router)
  if not compNV32Router then return end

  local out1 = compNV32Router["hdmi.out.1.select.index"]
  local out2 = compNV32Router["hdmi.out.2.select.index"]

  if out1 and btnNV32Out01 then
    out1.EventHandler = function(ctl)
      local inputValue = ctl.Value
      for i, btn in ipairs(btnNV32Out01) do
        btn.Boolean = (uciInputs[i] == inputValue)
      end
      debugMsg("Output 1 feedback → Input " .. tostring(inputValue))
    end
  end

  if out2 and enableOutput2 and btnNV32Out02 then
    out2.EventHandler = function(ctl)
      local inputValue = ctl.Value
      for i, btn in ipairs(btnNV32Out02) do
        btn.Boolean = (uciInputs[i] == inputValue)
      end
      debugMsg("Output 2 feedback → Input " .. tostring(inputValue))
    end
  end
end

function setcompRoomControls()
  if compRoomControls then
    if compRoomControls["ledSystemPower"] then compRoomControls["ledSystemPower"].EventHandler = nil end
    if compRoomControls["ledFireAlarm"] then compRoomControls["ledFireAlarm"].EventHandler = nil end
  end

  compRoomControls = setComp(Controls.compRoomControls, "Room Controls", componentTypes.roomControls)
  if not compRoomControls then return end

  local powerLED = compRoomControls["ledSystemPower"]
  if powerLED then
    powerLED.EventHandler = function(ctl)
      local targetInput = ctl.Boolean and uciInputs[1] or uciInputs[4]
      debugMsg("System power → " .. (ctl.Boolean and "ON" or "OFF"))
      setRoute(targetInput, outputs.Output01, "Room Controls: System Power")
      if enableOutput2 then
        setRoute(targetInput, outputs.Output02, "Room Controls: System Power")
      end
    end
  end

  local fireAlarmLED = compRoomControls["ledFireAlarm"]
  if fireAlarmLED then
    fireAlarmLED.EventHandler = function(ctl)
      if ctl.Boolean and not fireAlarmActive then
        preFireAlarmInput[outputs.Output01] = lastInput[outputs.Output01]
        if enableOutput2 then
          preFireAlarmInput[outputs.Output02] = lastInput[outputs.Output02]
        end
        fireAlarmActive = true
        debugMsg("Fire alarm → ACTIVE, routing Graphic2 to outputs")
        setRoute(uciInputs[5], outputs.Output01, "Room Controls: Fire Alarm")
        if enableOutput2 then
          setRoute(uciInputs[5], outputs.Output02, "Room Controls: Fire Alarm")
        end
      elseif not ctl.Boolean and fireAlarmActive then
        fireAlarmActive = false
        debugMsg("Fire alarm → CLEAR")
        if powerLED and powerLED.Boolean then
          local restore1 = preFireAlarmInput[outputs.Output01] or uciInputs[1]
          local restore2 = preFireAlarmInput[outputs.Output02] or uciInputs[1]
          setRoute(restore1, outputs.Output01, "Room Controls: Fire Alarm Clear")
          if enableOutput2 then
            setRoute(restore2, outputs.Output02, "Room Controls: Fire Alarm Clear")
          end
        end
        preFireAlarmInput[outputs.Output01] = nil
        if enableOutput2 then preFireAlarmInput[outputs.Output02] = nil end
      end
    end
  end
end

-------------------[ Event Handlers ]-------------------

normalizeButtonArrays()

if Controls.devNV32 then
  Controls.devNV32.EventHandler = setcompNV32Router
end

if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end

if btnNV32Out01 then
  for i, btn in ipairs(btnNV32Out01) do
    btn.EventHandler = function()
      setRoute(uciInputs[i], outputs.Output01, "NV32 Output 1 Button " .. tostring(i))
    end
  end
end

if enableOutput2 and btnNV32Out02 then
  for i, btn in ipairs(btnNV32Out02) do
    btn.EventHandler = function()
      setRoute(uciInputs[i], outputs.Output02, "NV32 Output 2 Button " .. tostring(i))
    end
  end
end

setupUCINavButtons()

-------------------[ Always Run ]-------------------

function funcInit()
  debugMsg("=== Initialization Started ===")

  if not Controls.devNV32 or not Controls.txtStatus or not btnNV32Out01 then
    print("ERROR: NV32 Router Controller — missing required controls (devNV32, txtStatus, btnNV32Out01)")
    if Controls.txtStatus then
      Controls.txtStatus.String = "INIT FAILED"
      Controls.txtStatus.Value = 2
    end
    return
  end

  getComponentNames()
  setcompNV32Router()
  setcompRoomControls()

  if compNV32Router then
    setRoute(uciInputs[1], outputs.Output01, "Initialization default")
    if enableOutput2 then
      setRoute(uciInputs[1], outputs.Output02, "Initialization default")
    end
  end

  debugMsg("=== Initialization Complete ===")
end

funcInit()

-- Public API for UCI / cross-script wiring (Notifications, same-script references)
NV32RouterController = {
  setUCIController       = setUCIController,
  enableUCIIntegration   = enableUCIIntegration,
  disableUCIIntegration  = disableUCIIntegration,
  onUCILayerChange       = onUCILayerChange,
  setRoute               = setRoute,
}
