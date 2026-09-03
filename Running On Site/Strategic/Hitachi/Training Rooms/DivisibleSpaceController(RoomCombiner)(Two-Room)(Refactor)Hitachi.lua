--[[
  Divisible Space Controller - Two Room Version (Refactored)
  Author: Nikolas Smith, Q-SYS
  Version: 3.3 | Date: 2026-04-03
  Firmware Req: 10.0.1+

  Features:
  - Flat module architecture, data-driven routing engine
  - State-based control via btnRoomState interlock (Separated/RmA Combined/RmB Combined)
  - Rich debug logging with source attribution
]]

-----------------------------[ Configuration ]-----------------------------
local config = {
  rooms = {"RoomA", "RoomB"},

  components = {
    gains = {"lvlPGMTrainingA", "lvlPGMTrainingB"},
    acpr = {"compACPRTrainingA", "compACPRTrainingB", combined = "compACPRTrainingCombined"},
    acprOutputs = {"01", "02"},
    callSync = {"callSyncTrainingA", "callSyncTrainingB"},
    roomControls = {"compRoomControlsTrainingA", "compRoomControlsTrainingB"},
    uciNames = {"uciTrainingB", "uciTrainingA"},
    matrixAudioMixer = {
      "input.2.output.4.mute", "input.3.output.3.mute",
      "input.4.output.2.mute", "input.4.output.6.mute",
      "input.5.output.1.mute", "input.5.output.5.mute"
    }
  },

  features = { disableACPRRouting = false },
  patterns = {
    roomCombiner = "^compRoomCombiner",
    matrixMixer = "^compMatrixAudio",
    roomControls = "^compRoomControls",
    mxaControls = "^compMXAControlsTraining",
    uciStatus = "^statusControlUCITraining",
    uciController = "^uciControllerTrainingA$",
    acprComponents = "^compACPRTraining",
    camRouter = "^compCamRouter"
  },

  uciButtons = {
    {name = "btnNav07", room = "RoomA", desc = "RoomA-PC"},
    {name = "btnNav09", room = "RoomA", desc = "RoomA-Laptop"},
    {name = "btnNav08", room = "RoomB", desc = "RoomB-PC"},
    {name = "btnNav10", room = "RoomB", desc = "RoomB-Laptop"}
  }
}

config.routingRules = {
  simple = {
    gain = {
      enabled = true,
      targetControl = "compGains 1",
      componentKey = "roomControls",
      getName = "Gain routing",
      separated = function(idx) return config.components.gains[idx] end,
      combined = function(priorityIdx) return config.components.gains[priorityIdx] end
    },
    acpr = {
      enabled = function() return not config.features.disableACPRRouting end,
      targetControl = "compACPR",
      componentKey = "roomControls",
      getName = "ACPR assignment",
      separated = function(idx) return config.components.acpr[idx] end,
      combined = function() return config.components.acpr.combined end
    }
  },
  multiControl = {
    mxaControls = {
      enabled = true,
      componentKey = "mxaControls",
      getName = "MXA controls routing",
      controls = {
        {name = "compCallSync", separated = function(idx) return config.components.callSync[idx] end, combined = function(pIdx) return config.components.callSync[pIdx] end},
        {name = "compRoomControls", separated = function(idx) return config.components.roomControls[idx] end, combined = function(pIdx) return config.components.roomControls[pIdx] end}
      }
    }
  }
}

-------------------[ Controls ]-------------------
local controls = {
  txtStatus = Controls.txtStatus,
  btnRoomState = Controls.btnRoomState
}

-------------------[ Utilities ]-------------------
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
  if not ctrl or ctrl[prop] == val then return end
  ctrl[prop] = val
end

local function bind(ctrl, handler)
  if not ctrl or not handler then return false end
  local ok = pcall(function() ctrl.EventHandler = handler end)
  return ok
end

local function bindArray(ctrls, handler)
  if not ctrls or not handler then return 0 end
  local array = isArr(ctrls) and ctrls or { ctrls }
  local count = 0
  for i, ctrl in ipairs(array) do
    if bind(ctrl, function(ctl)
      local ok, err = pcall(handler, i, ctl)
      if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
    end) then count = count + 1 end
  end
  return count
end

-------------------[ Config ]-------------------
local const = {
  roomName = "Two Room Divisible Space",
  debug = true
}

-------------------[ State ]-------------------
local components = {
  roomCombiner = nil,
  matrixMixer = nil,
  roomControls = {},
  mxaControls = {},
  uciStatus = nil,
  uciController = nil,
  acprComponents = {},
  camRouter = nil,
  gainComponents = {}
}
local state = { syncInProgress = false }

-------------------[ Debug ]-------------------
local function debugPrint(str)
  if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

local function printOperationResult(operation, success, total, errors)
  debugPrint(operation .. " complete: " .. success .. "/" .. total .. " successful")
  if errors and #errors > 0 then
    for _, err in ipairs(errors) do debugPrint("  ERROR: " .. err) end
  end
end

-------------------[ Functions ]-------------------
local applyRoomState  -- forward declaration (used by setRoomStateIndex)

local function getRoomIndex(roomName)
  for i, name in ipairs(config.rooms) do
    if name == roomName then return i end
  end
  return nil
end

local function getRoomState()
  if not controls.btnRoomState then return "Separated" end
  if controls.btnRoomState[1] and controls.btnRoomState[1].Boolean then return "Separated" end
  if controls.btnRoomState[2] and controls.btnRoomState[2].Boolean then return "RoomA_Combined" end
  if controls.btnRoomState[3] and controls.btnRoomState[3].Boolean then return "RoomB_Combined" end
  return "Separated"
end

local function getRoomStateFromIndex(index)
  local states = {"Separated", "RoomA_Combined", "RoomB_Combined"}
  return states[index] or "Unknown"
end

local function isRoomsSeparated()
  return getRoomState() == "Separated"
end

local function getRoomControlComponent(roomName)
  local idx = getRoomIndex(roomName)
  return idx and components.roomControls[idx]
end

local function getRoomControlState(roomName, controlName)
  local comp = getRoomControlComponent(roomName)
  return comp and comp[controlName] and comp[controlName].Boolean or false
end

local function isRoomPoweredOn(roomName)
  return getRoomControlState(roomName, "ledSystemPower")
end

local function isRoomCooling(roomName)
  return getRoomControlState(roomName, "ledSystemCooling")
end

local function checkAnyRoomState(checkFunc)
  for _, room in ipairs(config.rooms) do
    if checkFunc(room) then return true end
  end
  return false
end

local function getPriorityRoom()
  if isRoomsSeparated() then return nil end
  if components.uciController then
    for _, btn in ipairs(config.uciButtons) do
      local button = components.uciController[btn.name]
      if button and button.Boolean then return btn.room end
    end
  end
  local roomState = getRoomState()
  return (roomState == "RoomA_Combined" and "RoomA") or (roomState == "RoomB_Combined" and "RoomB") or nil
end

local function canChangeWallState()
  for _, room in ipairs(config.rooms) do
    if isRoomPoweredOn(room) then
      debugPrint("Wall change blocked - " .. room .. " is powered on (Source: Room Combiner)")
      return false
    end
  end
  return true
end

local function applyRouting(rule, ruleName)
  local enabled = type(rule.enabled) == "function" and rule.enabled() or rule.enabled
  if not enabled then debugPrint(ruleName .. " disabled"); return end
  local priorityRoom = getPriorityRoom()
  local priorityIdx = priorityRoom and ((priorityRoom == "RoomA") and 1 or 2)
  local controls = rule.targetControl and
    {{ name = rule.targetControl, separated = rule.separated, combined = rule.combined }} or
    rule.controls
  local success, errors = 0, {}
  local total = #config.rooms * #controls
  for i, room in ipairs(config.rooms) do
    local comp = components[rule.componentKey][i]
    for _, ctrl in ipairs(controls) do
      if comp and comp[ctrl.name] then
        local value = isRoomsSeparated() and ctrl.separated(i) or ctrl.combined(priorityIdx)
        if value and value ~= "" then
          setProp(comp[ctrl.name], "String", value)
          success = success + 1
          debugPrint(room .. " -> " .. ctrl.name .. ": " .. value .. " (Source: Room Combiner)")
        else table.insert(errors, room .. ": Invalid " .. ctrl.name) end
      else table.insert(errors, room .. ": " .. ctrl.name .. " not found") end
    end
  end
  printOperationResult(rule.getName, success, total, errors)
end

local function syncPowerToRooms(roomsToSync, powerState, source)
  state.syncInProgress = true
  local synced, errors = 0, {}
  local stateStr = powerState and "ON" or "OFF"
  for _, roomName in ipairs(roomsToSync) do
    local comp = getRoomControlComponent(roomName)
    if comp and comp["ledSystemPower"] and comp["btnSystemOnOff"] then
      if comp["ledSystemPower"].Boolean ~= powerState then
        setProp(comp["btnSystemOnOff"], "Boolean", powerState)
        synced = synced + 1
        debugPrint("SYNCED: " .. roomName .. " -> " .. stateStr .. " (Source: " .. source .. ")")
      else debugPrint("SKIP: " .. roomName .. " already " .. stateStr) end
    else table.insert(errors, roomName .. ": Controls not found") end
  end
  printOperationResult("Power sync", synced, #roomsToSync, errors)
  state.syncInProgress = false
end

local function applyBtnRoomStateInterlock(activeIndex)
  if not controls.btnRoomState then return end
  for i = 1, #controls.btnRoomState do
    if i ~= activeIndex and controls.btnRoomState[i] and controls.btnRoomState[i].Boolean then
      setProp(controls.btnRoomState[i], "Boolean", false)
      debugPrint("Interlock: Set btnRoomState[" .. i .. "] to false (Source: Wall Button)")
    end
  end
end

local function setRoomStateIndex(index)
  if not controls.btnRoomState or not controls.btnRoomState[index] then return end
  setProp(controls.btnRoomState[index], "Boolean", true)
  applyBtnRoomStateInterlock(index)
  applyRoomState()
end

local function updateWallState()
  if not components.roomCombiner then return end
  local roomState = getRoomState()
  local wallShouldBeOpen = (roomState ~= "Separated")
  local wallControl = components.roomCombiner["wall.1.open"]
  if wallControl then
    setProp(wallControl, "Boolean", wallShouldBeOpen)
    debugPrint("Wall: " .. (wallShouldBeOpen and "OPEN" or "CLOSED") .. " (Source: Room Combiner)")
  else debugPrint("ERROR: Wall control not found") end
end

local function updateBtnRoomStateDisabledStates()
  local states = {}
  local anyActive = false
  for _, room in ipairs(config.rooms) do
    local isOn = isRoomPoweredOn(room)
    local isCooling = isRoomCooling(room)
    local stateStr = isOn and "ON" or (isCooling and "COOLING" or "OFF")
    table.insert(states, room .. ":" .. stateStr)
    anyActive = anyActive or isOn or isCooling
  end
  local combineBlockedLegend = "Room is On. Turn the room Off to Combine"
  for idx = 2, 3 do
    if controls.btnRoomState and controls.btnRoomState[idx] then
      local btn = controls.btnRoomState[idx]
      setProp(btn, "IsDisabled", anyActive)
      setProp(btn, "Legend", anyActive and combineBlockedLegend or "")
    end
  end
  debugPrint("btnRoomState[2,3] " .. (anyActive and "DISABLED" or "ENABLED") .. " [" .. table.concat(states, ", ") .. "]")
end

local function applyGainRouting()
  if not isRoomsSeparated() then
    local priorityRoom = getPriorityRoom()
    if priorityRoom then
      local priorityIdx = (priorityRoom == "RoomA") and 1 or 2
      local nonPriorityIdx = 3 - priorityIdx
      local nonPriorityGain = components.gainComponents[nonPriorityIdx]
      local priorityGain = components.gainComponents[priorityIdx]
      if nonPriorityGain and nonPriorityGain["mute"] then
        setProp(nonPriorityGain["mute"], "Boolean", true)
        debugPrint("Muted gain[" .. nonPriorityIdx .. "] (Source: Room Combiner)")
      end
      if priorityGain and priorityGain["mute"] then
        setProp(priorityGain["mute"], "Boolean", false)
        debugPrint("Unmuted gain[" .. priorityIdx .. "] (Source: Room Combiner)")
      end
    end
  end
  applyRouting(config.routingRules.simple.gain, "Gain routing")
end

local function applyMatrixMixerMutes()
  if not components.matrixMixer then debugPrint("WARNING: Matrix mixer not found"); return end
  local muteState = isRoomsSeparated()
  local success, errors = 0, {}
  for _, muteName in ipairs(config.components.matrixAudioMixer) do
    local mute = components.matrixMixer[muteName]
    if mute then
      setProp(mute, "Boolean", muteState)
      success = success + 1
      debugPrint(muteName .. " -> " .. (muteState and "[ Muted ]" or "[ Unmuted ]") .. " (Source: Room Combiner)")
    else table.insert(errors, muteName .. ": Not found") end
  end
  printOperationResult("Matrix mixer mutes", success, #config.components.matrixAudioMixer, errors)
end

local function applyACPRAssignment()
  applyRouting(config.routingRules.simple.acpr, "ACPR assignment")
end

local function applyMXAControlsRouting()
  applyRouting(config.routingRules.multiControl.mxaControls, "MXA controls routing")
end

local function applyUCIStatusRouting()
  if not components.uciStatus then debugPrint("WARNING: UCI status not found"); return end
  local uciValue = isRoomsSeparated() and config.components.uciNames[1] or
    (isRoomPoweredOn("RoomB") and config.components.uciNames[2] or config.components.uciNames[1])
  local currentUCI = components.uciStatus["current.uci"]
  if currentUCI then
    setProp(currentUCI, "String", uciValue)
    debugPrint("UCI status: " .. uciValue .. " (Source: Room Combiner)")
  else debugPrint("ERROR: UCI status control not found") end
end

local function applyACPRComponentRouting()
  if config.features.disableACPRRouting then debugPrint("ACPR component routing disabled"); return end
  local isSeparated = isRoomsSeparated()
  local priorityRoom = getPriorityRoom()
  local success, errors = 0, {}
  local bypassSettings = isSeparated and {{idx = 3, desc = "Combined"}} or {{idx = 1, desc = "1"}, {idx = 2, desc = "2"}}
  for _, setting in ipairs(bypassSettings) do
    local acprComp = components.acprComponents[setting.idx]
    if acprComp and acprComp["TrackingBypass"] then
      setProp(acprComp["TrackingBypass"], "Boolean", true)
      success = success + 1
      debugPrint("ACPR[" .. setting.desc .. "] -> TrackingBypass: true (Source: Room Combiner)")
    else table.insert(errors, "ACPR[" .. setting.desc .. "]: TrackingBypass not found") end
  end
  if not isSeparated and priorityRoom then
    local acprComp3 = components.acprComponents[3]
    if acprComp3 and acprComp3["CameraRouterOutput"] then
      local outputValue = (priorityRoom == "RoomA") and config.components.acprOutputs[1] or config.components.acprOutputs[2]
      setProp(acprComp3["CameraRouterOutput"], "String", outputValue)
      success = success + 1
      debugPrint("ACPR[Combined] -> CameraRouterOutput: " .. outputValue .. " (Source: Room Combiner)")
    else table.insert(errors, "ACPR[Combined]: CameraRouterOutput not found") end
  end
  printOperationResult("ACPR component routing", success, 3, errors)
end

local function applyCamRouterRouting()
  if not components.camRouter then debugPrint("WARNING: Cam router not found"); return end
  local isSeparated = isRoomsSeparated()
  local priorityRoom = getPriorityRoom()
  local success, errors = 0, {}
  local routes = {
    {control = "select.1", separated = 1, combinedA = 1, combinedB = 2},
    {control = "select.2", separated = 2, combinedA = 1, combinedB = 2}
  }
  for _, route in ipairs(routes) do
    local ctrl = components.camRouter[route.control]
    if ctrl then
      local value = isSeparated and route.separated or (priorityRoom == "RoomA" and route.combinedA or route.combinedB)
      setProp(ctrl, "Value", value)
      success = success + 1
      debugPrint("Cam Router " .. route.control .. " -> " .. value .. " (Source: Room Combiner)")
    else table.insert(errors, route.control .. " not found") end
  end
  printOperationResult("Cam router routing", success, #routes, errors)
end

--- Refresh txtStatus (OK / warnings + current btnRoomState). Must run after every state change — not only at init.
local function checkStatus()
  local msg = "OK"
  local val = 0
  if not components.roomCombiner then msg = "Room Combiner Missing"; val = 1 end
  local connected = 0
  for idx = 1, #config.rooms do
    if components.roomControls[idx] then connected = connected + 1 end
  end
  if connected < #config.rooms then msg = msg .. " (Rooms: " .. connected .. "/" .. #config.rooms .. ")"; val = 1 end
  msg = msg .. " | State: " .. getRoomState()
  if controls.txtStatus then
    setProp(controls.txtStatus, "String", msg)
    setProp(controls.txtStatus, "Value", val)
  end
end

applyRoomState = function()
  debugPrint("=== Applying Room State Configuration ===")
  local roomState = getRoomState()
  debugPrint("Current state: " .. roomState)
  if not canChangeWallState() then
    debugPrint("BLOCKED: Cannot change state - rooms are powered on (Source: Room Combiner)")
    applyBtnRoomStateInterlock(1)
    if controls.btnRoomState and controls.btnRoomState[1] then setProp(controls.btnRoomState[1], "Boolean", true) end
    checkStatus()
    return
  end
  local ok, err = pcall(function()
    updateWallState()
    applyGainRouting()
    applyMatrixMixerMutes()
    applyACPRAssignment()
    applyMXAControlsRouting()
    applyUCIStatusRouting()
    applyACPRComponentRouting()
    applyCamRouterRouting()
    if roomState ~= "Separated" then
      if checkAnyRoomState(isRoomPoweredOn) then
        debugPrint("Syncing power (ON) to all rooms (Source: Room Combiner)")
        syncPowerToRooms(config.rooms, true, "Room Combiner")
      else debugPrint("All rooms OFF - no power sync needed") end
    end
    debugPrint("=== Room State Configuration Complete ===")
  end)
  if not ok then debugPrint("applyRoomState failed: " .. tostring(err)) end
  checkStatus()
end

local function applyPriorityDependentRouting()
  debugPrint("Re-applying priority-dependent routing (Source: UCI Button)")
  applyGainRouting()
  applyMXAControlsRouting()
  applyACPRComponentRouting()
  applyCamRouterRouting()
end

local function discoverComponents()
  debugPrint("=== Component Discovery Started ===")
  local discoveryMap = {
    {pattern = config.patterns.roomCombiner, key = "roomCombiner", single = true},
    {pattern = config.patterns.matrixMixer, key = "matrixMixer", single = true},
    {pattern = config.patterns.roomControls, key = "roomControls", indexed = true},
    {pattern = config.patterns.mxaControls, key = "mxaControls", indexed = true},
    {pattern = config.patterns.uciStatus, key = "uciStatus", single = true},
    {pattern = config.patterns.uciController, key = "uciController", single = true, exact = true},
    {pattern = config.patterns.acprComponents, key = "acprComponents", indexed = true, hasCombined = true},
    {pattern = config.patterns.camRouter, key = "camRouter", single = true}
  }
  local function matchesPattern(name, map)
    return map.exact and name == map.pattern:gsub("^%^", ""):gsub("%$$", "") or name:match(map.pattern)
  end
  local function getIndexFromName(name, hasCombined)
    return name:match("A$") and 1 or name:match("B$") and 2 or (hasCombined and name:match("Combined$") and 3)
  end
  local foundCount = 0
  for _, comp in ipairs(Component.GetComponents()) do
    for _, map in ipairs(discoveryMap) do
      if matchesPattern(comp.Name, map) then
        local component = Component.New(comp.Name)
        if component then
          if map.single then
            components[map.key] = component
            debugPrint("  Found " .. map.key .. ": " .. comp.Name)
            foundCount = foundCount + 1
          elseif map.indexed then
            local idx = getIndexFromName(comp.Name, map.hasCombined)
            if idx then
              components[map.key][idx] = component
              debugPrint("  Found " .. map.key .. "[" .. idx .. "]: " .. comp.Name)
              foundCount = foundCount + 1
            end
          end
        end
      end
    end
  end
  debugPrint("=== Component Discovery Complete: " .. foundCount .. " components found ===")
end

local function cacheGainComponents()
  for i, gainName in ipairs(config.components.gains) do
    local gainComp = Component.New(gainName)
    if gainComp then
      components.gainComponents[i] = gainComp
      debugPrint("Cached gain: " .. gainName)
    else debugPrint("WARNING: Failed to cache gain: " .. gainName) end
  end
end

local function validateComponents()
  local warnings = {}
  for _, comp in ipairs({{key = "roomCombiner", desc = "Room combiner"}, {key = "matrixMixer", desc = "Matrix mixer"}, {key = "uciStatus", desc = "UCI status"}, {key = "camRouter", desc = "Cam router"}}) do
    if not components[comp.key] then table.insert(warnings, comp.desc) end
  end
  for i, room in ipairs(config.rooms) do
    for _, comp in ipairs({{key = "roomControls", desc = "controls"}, {key = "mxaControls", desc = "MXA"}, {key = "acprComponents", desc = "ACPR"}}) do
      if not components[comp.key][i] then table.insert(warnings, room .. " " .. comp.desc) end
    end
  end
  if not components.acprComponents[3] then table.insert(warnings, "Combined ACPR") end
  if #warnings > 0 then debugPrint("WARNING: Missing components: " .. table.concat(warnings, ", ")) end
  return #warnings
end

-------------------[ Events ]-------------------
local function onRoomCoolingChanged(roomName)
  debugPrint("Cooling state changed: " .. roomName .. " (Source: Room Controls)")
  updateBtnRoomStateDisabledStates()
end

local function onRoomPowerChanged(roomName)
  if state.syncInProgress then
    debugPrint("Sync in progress - ignoring power change for " .. roomName)
    return
  end
  debugPrint("=== Power State Changed: " .. roomName .. " (Source: Room Controls) ===")
  updateBtnRoomStateDisabledStates()
  if isRoomsSeparated() then debugPrint(roomName .. " is separated - no sync needed"); return end
  local newPowerState = isRoomPoweredOn(roomName)
  debugPrint(roomName .. " power: " .. (newPowerState and "ON" or "OFF"))
  if not newPowerState and not checkAnyRoomState(isRoomPoweredOn) then
    debugPrint("All rooms OFF - auto-separating (Source: Room Controls)")
    state.syncInProgress = true
    for idx, room in ipairs(config.rooms) do
      local comp = components.roomControls[idx]
      if comp and comp["ledSystemPower"] and comp["ledSystemPower"].Boolean then
        setProp(comp["btnSystemOnOff"], "Boolean", false)
        debugPrint("Powered OFF: " .. room .. " (Source: Auto-Separation)")
      end
    end
    setRoomStateIndex(1)
    updateBtnRoomStateDisabledStates()
    state.syncInProgress = false
    debugPrint("=== Auto-Separation Complete ===")
    return
  end
  local roomsToSync = {}
  for _, rn in ipairs(config.rooms) do if rn ~= roomName then table.insert(roomsToSync, rn) end end
  if #roomsToSync > 0 then
    debugPrint("Syncing power (" .. (newPowerState and "ON" or "OFF") .. ") to: " .. table.concat(roomsToSync, ", ") .. " (Source: Room Controls)")
    syncPowerToRooms(roomsToSync, newPowerState, "Room Controls")
    applyUCIStatusRouting()
  end
end

local function onUCIInputSelectionChanged()
  if isRoomsSeparated() then return end
  if not checkAnyRoomState(isRoomPoweredOn) then
    debugPrint("UCI button changed but system OFF - routing will apply on power on (Source: UCI Button)")
    return
  end
  local newPriority = getPriorityRoom()
  if newPriority then
    debugPrint("Priority room changed to " .. newPriority .. " (Source: UCI Button)")
    applyPriorityDependentRouting()
  end
end

local function registerEvents()
  local wallCount = bindArray(controls.btnRoomState, function(i, ctl)
    if ctl.Boolean then
      debugPrint("btnRoomState[" .. i .. "] pressed: " .. getRoomStateFromIndex(i) .. " (Source: Wall Button)")
      applyBtnRoomStateInterlock(i)
      applyRoomState()
    end
  end)
  debugPrint("Registered " .. wallCount .. " wall button handlers")
  local powerCount = 0
  for i, room in ipairs(config.rooms) do
    local comp = components.roomControls[i]
    if comp then
      if comp["ledSystemPower"] and bind(comp["ledSystemPower"], function() onRoomPowerChanged(room) end) then powerCount = powerCount + 1 end
      if comp["ledSystemCooling"] and bind(comp["ledSystemCooling"], function() onRoomCoolingChanged(room) end) then powerCount = powerCount + 1 end
    end
  end
  debugPrint("Registered " .. powerCount .. " power/cooling handlers")
  local uciCount = 0
  if components.uciController then
    for _, btn in ipairs(config.uciButtons) do
      local button = components.uciController[btn.name]
      if button and bind(button, onUCIInputSelectionChanged) then
        debugPrint("Registered UCI button: " .. btn.name .. " (" .. btn.desc .. ")")
        uciCount = uciCount + 1
      end
    end
    debugPrint("Registered " .. uciCount .. "/" .. #config.uciButtons .. " UCI button handlers")
  else debugPrint("WARNING: UCI controller not found - skipping UCI button handlers") end
end

-------------------[ Init ]-------------------
local function validateControls()
  local required = {"txtStatus", "btnRoomState"}
  for _, name in ipairs(required) do
    if not controls[name] then
      print("ERROR: Missing required control: " .. name)
      return false
    end
  end
  return true
end

local function normalizeControlArrays()
  for _, name in ipairs({"btnRoomState"}) do
    local ctrl = controls[name]
    if ctrl and not isArr(ctrl) then controls[name] = { ctrl } end
  end
end

local function init()
  debugPrint("=== Initialization Started ===")
  debugPrint("Configuration: const.roomName=" .. const.roomName .. ", debugging=" .. tostring(const.debug))
  discoverComponents()
  validateComponents()
  cacheGainComponents()
  registerEvents()
  applyRoomState()
  updateBtnRoomStateDisabledStates()
  checkStatus()
  debugPrint("=== Initialization Complete ===")
  debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
DivisibleSpaceController = {
  applyRoomState = applyRoomState,
  applyPriorityDependentRouting = applyPriorityDependentRouting,
  checkStatus = checkStatus
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
  print("Initializing controller for " .. const.roomName .. "...")
  if not validateControls() then error("Control validation failed") end
  normalizeControlArrays()
  init()
end)

if ok then
  print("✓ Controller initialized for " .. const.roomName)
  _G.myDivisibleController = DivisibleSpaceController
else
  print("✗ ERROR: Initialization failed: " .. tostring(err))
  if controls and controls.txtStatus then
    controls.txtStatus.String = "INIT FAILED"
    controls.txtStatus.Value = 2
  end
end
