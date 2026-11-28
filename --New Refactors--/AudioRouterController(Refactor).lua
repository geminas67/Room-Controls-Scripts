--[[
  Audio Router Controller - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Date: 2026-11-27
  Version: 4.3
  Firmware Req: 10.0.0

  Router output, default input, and silent input are runtime script choices.
  Leave the selected silent input unpatched on the schematic.
  4.3: each decision stated once (last-input rule, input parsing, config status, room-control pins)
]]--

-------------------[ Configuration ]-------------------

componentTypes = {
  audioRouter  = "router_with_output",
  roomControls = "device_controller_script",
}
matchRmCtlName = "^compRoomControls"   -- only list room scripts named like this

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compAudioRouter = nil
compRoomControls = nil
ctlRouterSelect = nil   -- the router's select.N control for the chosen output

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "Audio Router"
routerOutput = nil      -- e.g. "select.1"
defaultInput = nil      -- routed on system power on
silentInput = nil       -- routed on power off and fire alarm
inputMin = nil
inputMax = nil
lastInput = nil         -- last real source, restored when a fire alarm clears

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

-- "Input 3" -> 3
function parseInput(ctl)
  return tonumber(ctl.String:match("^Input (%d+)$"))
end

-- read the default/silent combo boxes; false if either is unusable
function readInputSelections()
  defaultInput = parseInput(Controls['defaultInput'])
  silentInput = parseInput(Controls['silentInput'])
  return defaultInput ~= nil and silentInput ~= nil
end

-- the silent input never counts as a source worth restoring
function rememberInput(input)
  if input ~= silentInput then lastInput = input end
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

-- bind the component named in a selector; returns nil when cleared or invalid
function setComp(ctl, componentType)
  local name = ctl.String
  if name == "" or name == strClear then
    ctl.String = ""
    ctl.Color = "white"
    compInvalid[componentType] = false
    getStatus()
    return nil
  end
  local comp = Component.New(name)
  local valid = #Component.GetControls(comp) > 0
  ctl.Color = valid and "white" or "pink"
  compInvalid[componentType] = not valid
  getStatus()
  if not valid then
    debugMsg("ERROR: Invalid " .. componentType .. ": " .. name)
    return nil
  end
  return comp
end

-------------------[ Discovery ]-------------------

-- sort, add [Clear], and load a selector's choices
function fillChoices(ctl, names)
  table.sort(names)
  table.insert(names, strClear)
  ctl.Choices = names
end

function getComponentNames()
  local routers, rooms = {}, {}
  for _, comp in pairs(Component.GetComponents()) do
    if comp.Type == componentTypes.audioRouter then
      table.insert(routers, comp.Name)
    elseif comp.Type == componentTypes.roomControls and comp.Name:match(matchRmCtlName) then
      table.insert(rooms, comp.Name)
    end
  end
  fillChoices(Controls['compAudioRouter'], routers)
  fillChoices(Controls['compRoomControls'], rooms)
end

-- load choices, keeping the current selection if it still exists
function setChoices(ctl, choices, fallback)
  local selected = ctl.String
  ctl.Choices = choices
  for _, choice in ipairs(choices) do
    if choice == selected then return end
  end
  ctl.String = fallback or ""
end

-- discover select.N outputs and the selected output's input range at runtime
function getRouterChoices()
  local outputs, inputs = {}, {}
  for _, ctl in ipairs(Component.GetControls(compAudioRouter)) do
    if ctl.Name:match("^select%.%d+$") then table.insert(outputs, ctl.Name) end
  end
  table.sort(outputs, function(a, b) return tonumber(a:match("%d+$")) < tonumber(b:match("%d+$")) end)
  setChoices(Controls['routerOutput'], outputs, outputs[1])
  routerOutput = Controls['routerOutput'].String

  local selected = compAudioRouter[routerOutput]
  inputMin = selected and tonumber(selected.MinValue)
  inputMax = selected and tonumber(selected.MaxValue)
  if not inputMin or not inputMax then inputMin = nil return false end
  inputMin, inputMax = math.max(1, math.ceil(inputMin)), math.floor(inputMax)

  for i = inputMin, inputMax do table.insert(inputs, "Input " .. i) end
  setChoices(Controls['defaultInput'], inputs, inputs[1])
  setChoices(Controls['silentInput'], inputs, inputs[#inputs])
  local ok = readInputSelections()
  debugMsg("Configuration: " .. routerOutput .. "; inputs " .. inputMin .. "-" .. inputMax
    .. "; default " .. tostring(defaultInput) .. "; silent " .. tostring(silentInput))
  return ok
end

-------------------[ Routing ]-------------------

function isFireAlarm()
  local led = compRoomControls and compRoomControls['ledFireAlarm']
  return led ~= nil and led.Boolean
end

function syncSourceButtons(input)
  for i, btn in ipairs(Controls['btnSource']) do btn.Boolean = (i == input) end
end

-- route one input to the selected output; only the silent input is allowed during a fire alarm
function setRoute(input, source)
  if not ctlRouterSelect then return end
  local outOfRange = not input or input < inputMin or input > inputMax
  local blocked = not outOfRange and input ~= silentInput and isFireAlarm()
  if outOfRange or blocked then
    syncSourceButtons(ctlRouterSelect.Value) -- snap buttons back to the live route
    if blocked then debugMsg("Route blocked by fire alarm (Source: " .. source .. ")") end
    return
  end
  rememberInput(input)
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

-- router select -> source buttons (covers routes changed outside this script)
function bindRouterSelect()
  ctlRouterSelect = compAudioRouter[routerOutput]
  ctlRouterSelect.EventHandler = function(ctl)
    rememberInput(ctl.Value)
    syncSourceButtons(ctl.Value)
  end
  rememberInput(ctlRouterSelect.Value)
  syncSourceButtons(ctlRouterSelect.Value)
end

-- refreshChoices: rebuild output/input lists (router or output changed); otherwise just reread selections
function applyRouterConfig(refreshChoices)
  clearRouterSelect()
  local ok = true
  if compAudioRouter ~= nil then
    if refreshChoices then ok = getRouterChoices() else ok = inputMin ~= nil and readInputSelections() end
    if ok then bindRouterSelect() else debugMsg("ERROR: Router output or default/silent input not usable") end
  end
  compInvalid['Router Config'] = not ok
  getStatus()
end

function setcompAudioRouter()
  routerOutput, defaultInput, silentInput, inputMin, inputMax, lastInput = nil, nil, nil, nil, nil, nil
  compAudioRouter = setComp(Controls['compAudioRouter'], "Audio Router")
  syncSourceButtons(nil)
  applyRouterConfig(true)
end

-- room-controls pins this script listens to (either may be missing on a given automation script)
roomControlHandlers = {
  ledSystemPower = function(ctl)
    -- power on -> default input, power off -> silent input
    setRoute(ctl.Boolean and defaultInput or silentInput, "System Power")
  end,
  ledFireAlarm = function(ctl)
    -- alarm -> silent input; clear -> restore last source only if the system is on
    local power = compRoomControls['ledSystemPower']
    if ctl.Boolean then
      setRoute(silentInput, "Fire Alarm (active)")
    elseif power and power.Boolean then
      setRoute(lastInput or defaultInput, "Fire Alarm (cleared)")
    end
  end,
}

function bindRoomControls(attach)
  if compRoomControls == nil then return end
  for name, handler in pairs(roomControlHandlers) do
    local pin = compRoomControls[name]
    if pin then pin.EventHandler = attach and handler or nil end
  end
end

function setcompRoomControls()
  bindRoomControls(false) -- release the previous room script
  compRoomControls = setComp(Controls['compRoomControls'], "Room Controls")
  bindRoomControls(true)
end

-------------------[ Event Handlers ]-------------------

-- source buttons -> route that input
for i, btn in ipairs(Controls['btnSource']) do
  btn.EventHandler = function() setRoute(i, "Source Button " .. i) end
end

-- component selectors
Controls['compAudioRouter'].EventHandler = setcompAudioRouter
Controls['compRoomControls'].EventHandler = setcompRoomControls

-- new output -> rediscover its input range; new default/silent -> reread only
Controls['routerOutput'].EventHandler = function() applyRouterConfig(true) end
Controls['defaultInput'].EventHandler = function() applyRouterConfig(false) end
Controls['silentInput'].EventHandler = function() applyRouterConfig(false) end

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
  debugMsg("Initialization complete")
end

funcInit()
