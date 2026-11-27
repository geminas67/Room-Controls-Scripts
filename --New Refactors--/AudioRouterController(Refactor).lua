--[[
  Audio Router Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-11-25
  Version: 4.2
  Firmware Req: 10.0.0

  Router output, default input, and silent input are runtime script choices.
  Leave the selected silent input unpatched on the schematic.
]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  audioRouter  = "router_with_output",
  roomControls = "device_controller_script",
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compAudioRouter = nil
compRoomControls = nil
ctlRouterSelect = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "Audio Router"
routerOutput = nil
defaultInput = nil
silentInput = nil
inputMin = nil
inputMax = nil
lastInput = nil

-------------------[ Functions ]-------------------
-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print("[" .. roomName .. "] " .. str) end
end

function validateControls()
  local missing = {}
  for _, name in ipairs({ "compAudioRouter", "compRoomControls", "btnSource",
    "defaultInput", "routerOutput", "silentInput", "txtStatus" }) do
    if not Controls[name] then table.insert(missing, name) end
  end
  if #missing == 0 then return true end
  print("ERROR: Missing controls: " .. table.concat(missing, ", "))
  return false
end

function parseInput(ctl)
  return tonumber(ctl.String:match("^Input (%d+)$"))
end

-------------------[ Status ]-------------------

function getStatus()
  for name, invalid in pairs(compInvalid) do
    if invalid then
      Controls['txtStatus'].String = "Invalid: " .. name
      Controls['txtStatus'].Value = 1
      return
    end
  end
  Controls['txtStatus'].String = "OK"
  Controls['txtStatus'].Value = 0
end

function setComp(ctl, componentType)
  local name = ctl.String
  compInvalid[componentType] = false
  ctl.Color = "white"
  if name == "" or name == strClear then
    ctl.String = ""
    return nil
  end
  local comp = Component.New(name)
  local list = comp and Component.GetControls(comp)
  if list and #list > 0 then return comp end
  ctl.Color = "pink"
  compInvalid[componentType] = true
  debugMsg("ERROR: Invalid " .. componentType .. ": " .. name)
  return nil
end

-------------------[ Discovery ]-------------------

function getComponentNames()
  local routers, rooms = {}, {}
  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.audioRouter then
      table.insert(routers, comp.Name)
    elseif comp.Type == componentTypes.roomControls and comp.Name:match("^compRoomControls") then
      table.insert(rooms, comp.Name)
    end
  end
  table.sort(routers)
  table.sort(rooms)
  table.insert(routers, strClear)
  table.insert(rooms, strClear)
  Controls['compAudioRouter'].Choices = routers
  Controls['compRoomControls'].Choices = rooms
end

function setChoices(ctl, choices, fallback)
  local selected = ctl.String
  ctl.Choices = choices
  for _, choice in ipairs(choices) do
    if choice == selected then ctl.String = selected; return end
  end
  ctl.String = fallback or ""
end

function getRouterChoices()
  local outputs, inputs = {}, {}
  for _, ctl in ipairs(Component.GetControls(compAudioRouter)) do
    if ctl.Name:match("^select%.%d+$") then table.insert(outputs, ctl.Name) end
  end
  table.sort(outputs, function(a, b)
    return tonumber(a:match("%d+$")) < tonumber(b:match("%d+$"))
  end)
  setChoices(Controls['routerOutput'], outputs, outputs[1])
  routerOutput = Controls['routerOutput'].String
  local selected = compAudioRouter[routerOutput]
  inputMin = selected and tonumber(selected.MinValue)
  inputMax = selected and tonumber(selected.MaxValue)
  if not inputMin or not inputMax then return false end
  inputMin, inputMax = math.max(1, math.ceil(inputMin)), math.floor(inputMax)
  for i = inputMin, inputMax do table.insert(inputs, "Input " .. i) end
  setChoices(Controls['defaultInput'], inputs, inputs[1])
  setChoices(Controls['silentInput'], inputs, inputs[#inputs])
  defaultInput = parseInput(Controls['defaultInput'])
  silentInput = parseInput(Controls['silentInput'])
  debugMsg("Configuration: " .. routerOutput .. "; inputs " .. inputMin .. "-" .. inputMax
    .. "; default " .. tostring(defaultInput) .. "; silent " .. tostring(silentInput))
  return defaultInput ~= nil and silentInput ~= nil
end

-------------------[ Routing ]-------------------

function isFireAlarm()
  local led = compRoomControls and compRoomControls['ledFireAlarm']
  return led ~= nil and led.Boolean
end

function syncSourceButtons(input)
  for i, btn in ipairs(Controls['btnSource']) do btn.Boolean = (i == input) end
end

function setRoute(input, source)
  if not ctlRouterSelect or not defaultInput or not silentInput then return end
  if not input or input < inputMin or input > inputMax then
    syncSourceButtons(ctlRouterSelect.Value)
    return
  end
  if input ~= silentInput and isFireAlarm() then
    syncSourceButtons(ctlRouterSelect.Value)
    debugMsg("Route blocked by fire alarm (Source: " .. source .. ")")
    return
  end
  if input ~= silentInput then lastInput = input end
  syncSourceButtons(input)
  if ctlRouterSelect.Value == input then return end
  ctlRouterSelect.Value = input
  debugMsg("Route: " .. routerOutput .. " -> Input " .. input .. " (Source: " .. source .. ")")
end

-------------------[ Components ]-------------------

function clearRouterSelect()
  if ctlRouterSelect then ctlRouterSelect.EventHandler = nil end
  ctlRouterSelect = nil
end

function bindRouterSelect()
  ctlRouterSelect = compAudioRouter and routerOutput and compAudioRouter[routerOutput]
  if not ctlRouterSelect then return end
  if ctlRouterSelect.Value ~= silentInput then lastInput = ctlRouterSelect.Value end
  ctlRouterSelect.EventHandler = function(ctl)
    if ctl.Value ~= silentInput then lastInput = ctl.Value end
    syncSourceButtons(ctl.Value)
  end
  syncSourceButtons(ctlRouterSelect.Value)
end

function applyRouterConfig(refreshChoices)
  clearRouterSelect()
  compInvalid['Router Config'] = false
  if refreshChoices then
    if not compAudioRouter or not getRouterChoices() then
      compInvalid['Router Config'] = true
      debugMsg("ERROR: No usable select.N controls / input range")
      getStatus()
      return
    end
  else
    defaultInput = parseInput(Controls['defaultInput'])
    silentInput = parseInput(Controls['silentInput'])
    if not defaultInput or not silentInput then
      compInvalid['Router Config'] = true
      getStatus()
      return
    end
  end
  bindRouterSelect()
  getStatus()
end

function setcompAudioRouter()
  clearRouterSelect()
  routerOutput, defaultInput, silentInput, lastInput = nil, nil, nil, nil
  compAudioRouter = setComp(Controls['compAudioRouter'], "Audio Router")
  syncSourceButtons(nil)
  if not compAudioRouter then
    getStatus()
    return
  end
  applyRouterConfig(true)
end

function setcompRoomControls()
  if compRoomControls then
    for _, name in ipairs({ 'ledSystemPower', 'ledFireAlarm' }) do
      if compRoomControls[name] then compRoomControls[name].EventHandler = nil end
    end
  end
  compRoomControls = setComp(Controls['compRoomControls'], "Room Controls")
  if not compRoomControls then return end
  if compRoomControls['ledSystemPower'] then
    compRoomControls['ledSystemPower'].EventHandler = function(ctl)
      setRoute(ctl.Boolean and defaultInput or silentInput, "System Power")
    end
  end
  if compRoomControls['ledFireAlarm'] then
    compRoomControls['ledFireAlarm'].EventHandler = function(ctl)
      local power = compRoomControls['ledSystemPower']
      if ctl.Boolean then
        setRoute(silentInput, "Fire Alarm (active)")
      elseif power and power.Boolean then
        setRoute(lastInput or defaultInput, "Fire Alarm (cleared)")
      end
    end
  end
end

-------------------[ Event Handlers ]-------------------

if Controls['btnSource'] then
  for i, btn in ipairs(Controls['btnSource']) do
    btn.EventHandler = function() setRoute(i, "Source Button " .. i) end
  end
end

if Controls['compAudioRouter'] then Controls['compAudioRouter'].EventHandler = setcompAudioRouter end
if Controls['compRoomControls'] then Controls['compRoomControls'].EventHandler = setcompRoomControls end
if Controls['routerOutput'] then Controls['routerOutput'].EventHandler = function() applyRouterConfig(true) end end
if Controls['defaultInput'] then Controls['defaultInput'].EventHandler = function() applyRouterConfig(false) end end
if Controls['silentInput'] then Controls['silentInput'].EventHandler = function() applyRouterConfig(false) end end

-------------------[ Always Run ]-------------------

function funcInit()
  if not validateControls() then
    if Controls['txtStatus'] then
      Controls['txtStatus'].String = "INIT FAILED"
      Controls['txtStatus'].Value = 2
    end
    return
  end
  getComponentNames()
  setcompAudioRouter()
  setcompRoomControls()
  getStatus()
  debugMsg("Initialization complete")
end

funcInit()
