--[[
  Divisible Space Controller - Two Room (Jacobs Northmark Training)
  Author: Nikolas Smith, Q-SYS
  Version: 3.6 | Date: 2026-10-14
  Firmware Req: 10.0.1+

  Two-room divisible space: btnRoomMode interlock, discovery, and data-driven routing.

]]--

-------------------[ Configuration ]-------------------

config = {
  rooms = {"RoomA", "RoomB"},

  component = {
    gains = {"lvlPGMRmA", "lvlPGMRmB"},
    acpr = {"compACPRRmA", "compACPRRmB", combined = "compACPRCombined"},
    acprOutputs = {"01", "02"},
    callSync = {"callSyncRmA", "callSyncRmB"},
    roomControls = {"compRoomControlsRmA", "compRoomControlsRmB"},
    uciNames = {"uciRoomB", "uciRoomA"},
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
    mxaControls = "^compMXAControls",
    uciStatus = "^statusMTR",
    uciController = "^uciControllerRmA$", -- must be exact match
    acprComponents = "^compACPR",
    camRouter = "^compCamRouter"
  },
  -- UCI buttons set Priority room for routing
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
      divided = function(idx) return config.component.gains[idx] end,
      combined = function(priorityIdx) return config.component.gains[priorityIdx] end
    },
    acpr = {
      enabled = function() return not config.features.disableACPRRouting end,
      targetControl = "compACPR",
      componentKey = "roomControls",
      getName = "ACPR assignment",
      divided = function(idx) return config.component.acpr[idx] end,
      combined = function() return config.component.acpr.combined end
    }
  },
  multiControl = {
    mxaControls = {
      enabled = true,
      componentKey = "mxaControls",
      getName = "MXA controls routing",
      controls = {
        {name = "compCallSync", divided = function(idx) return config.component.callSync[idx] end, combined = function(pIdx) return config.component.callSync[pIdx] end},
        {name = "compRoomControls", divided = function(idx) return config.component.roomControls[idx] end, combined = function(pIdx) return config.component.roomControls[pIdx] end}
      }
    }
  }
}

-------------------[ Constant Tables ]-------------------

component = {
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

-------------------[ Constants ]-------------------

stateDebug = true
strRoomLabel = "Two Room Divisible Space"
syncInProgress = false
legendCombineBlocked = "Room is in use.\nTurn the room Off and open the wall to Combine"

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if stateDebug then print("[" .. strRoomLabel .. "] " .. str) end
end

function printOperationResult(operation, success, total, errors)
  debugMsg(operation .. " complete: " .. success .. "/" .. total .. " successful")
  if errors and #errors > 0 then
    for _, err in ipairs(errors) do debugMsg("  ERROR: " .. err) end
  end
end

-------------------[ Room State ]-------------------

function getRoomIndex(roomName)
  for i, name in ipairs(config.rooms) do
    if name == roomName then return i end
  end
  return nil
end

function getRoomStateFromIndex(index)
  local states = {"Divided", "RoomA_Combined", "RoomB_Combined"}
  return states[index] or "Unknown"
end

function getRoomState()
  if not Controls.btnRoomMode then return "Divided" end
  for i = 1, #Controls.btnRoomMode do
    if Controls.btnRoomMode[i] and Controls.btnRoomMode[i].Boolean then
      return getRoomStateFromIndex(i)
    end
  end
  return "Divided"
end

function isRoomsDivided()
  return getRoomState() == "Divided"
end

function getRoomControlComponent(roomName)
  local idx = getRoomIndex(roomName)
  return idx and component.roomControls[idx]
end

function getRoomControlBoolean(roomName, controlName)
  local comp = getRoomControlComponent(roomName)
  return comp and comp[controlName] and comp[controlName].Boolean or false
end

function isRoomPoweredOn(roomName)
  return getRoomControlBoolean(roomName, "ledSystemPower")
end

function isRoomCooling(roomName)
  return getRoomControlBoolean(roomName, "ledSystemCooling")
end

function checkAnyRoomState(checkFunc)
  for _, room in ipairs(config.rooms) do
    if checkFunc(room) then return true end
  end
  return false
end

function getPriorityRoom()
  if isRoomsDivided() then return nil end
  if component.uciController then
    for _, btn in ipairs(config.uciButtons) do
      local button = component.uciController[btn.name]
      if button and button.Boolean then return btn.room end
    end
  end
  local roomState = getRoomState()
  return (roomState == "RoomA_Combined" and "RoomA") or (roomState == "RoomB_Combined" and "RoomB") or nil
end

function getPriorityRoomIndex()
  local priorityRoom = getPriorityRoom()
  return priorityRoom and getRoomIndex(priorityRoom)
end

function canChangeWallState()
  for _, room in ipairs(config.rooms) do
    if isRoomPoweredOn(room) then
      debugMsg("Wall change blocked - " .. room .. " is powered on (Source: Room Combiner)")
      return false
    end
  end
  return true
end

function interlockBtnRoomMode(activeIndex)
  if not Controls.btnRoomMode then return end
  for i = 1, #Controls.btnRoomMode do
    if i ~= activeIndex and Controls.btnRoomMode[i] and Controls.btnRoomMode[i].Boolean then
      Controls.btnRoomMode[i].Boolean = false
      debugMsg("Interlock: Set btnRoomMode[" .. i .. "] to false (Source: Wall Button)")
    end
  end
end

function updateWallState()
  if not component.roomCombiner then return end
  local roomState = getRoomState()
  local wallShouldBeOpen = (roomState ~= "Divided")
  local wallControl = component.roomCombiner["wall.1.open"]
  if wallControl then
    wallControl.Boolean = wallShouldBeOpen
    debugMsg("Wall: " .. (wallShouldBeOpen and "OPEN" or "CLOSED") .. " (Source: Room Combiner)")
  else debugMsg("ERROR: Wall control not found") end
end

function updateBtnRoomModeDisabled()
  local states = {}
  local anyActive = false
  for _, room in ipairs(config.rooms) do
    local isOn = isRoomPoweredOn(room)
    local isCooling = isRoomCooling(room)
    local stateStr = isOn and "ON" or (isCooling and "COOLING" or "OFF")
    table.insert(states, room .. ":" .. stateStr)
    anyActive = anyActive or isOn or isCooling
  end
  for idx = 2, 3 do
    if Controls.btnRoomMode and Controls.btnRoomMode[idx] then
      local btn = Controls.btnRoomMode[idx]
      btn.IsDisabled = anyActive
      btn.Legend = anyActive and legendCombineBlocked or ""
    end
  end
  debugMsg("btnRoomMode[2,3] " .. (anyActive and "DISABLED" or "ENABLED") .. " [" .. table.concat(states, ", ") .. "]")
end

-------------------[ Routing ]-------------------

function applyRouting(rule)
  local enabled = type(rule.enabled) == "function" and rule.enabled() or rule.enabled
  if not enabled then debugMsg(rule.getName .. " disabled"); return end
  local priorityIdx = getPriorityRoomIndex()
  local ruleControls = rule.targetControl and
    {{ name = rule.targetControl, divided = rule.divided, combined = rule.combined }} or
    rule.controls
  local success, errors = 0, {}
  local total = #config.rooms * #ruleControls
  for i, room in ipairs(config.rooms) do
    local comp = component[rule.componentKey][i]
    for _, ctrl in ipairs(ruleControls) do
      if comp and comp[ctrl.name] then
        local value = isRoomsDivided() and ctrl.divided(i) or ctrl.combined(priorityIdx)
        if value and value ~= "" then
          comp[ctrl.name].String = value
          success = success + 1
          debugMsg(room .. " -> " .. ctrl.name .. ": " .. value .. " (Source: Room Combiner)")
        else table.insert(errors, room .. ": Invalid " .. ctrl.name) end
      else table.insert(errors, room .. ": " .. ctrl.name .. " not found") end
    end
  end
  printOperationResult(rule.getName, success, total, errors)
end

function syncPowerToRooms(roomsToSync, powerState, source)
  syncInProgress = true
  local synced, errors = 0, {}
  local stateStr = powerState and "ON" or "OFF"
  for _, roomName in ipairs(roomsToSync) do
    local comp = getRoomControlComponent(roomName)
    if comp and comp["ledSystemPower"] and comp["btnSystemOnOff"] then
      if comp["ledSystemPower"].Boolean ~= powerState then
        comp["btnSystemOnOff"].Boolean = powerState
        synced = synced + 1
        debugMsg("SYNCED: " .. roomName .. " -> " .. stateStr .. " (Source: " .. source .. ")")
      else debugMsg("SKIP: " .. roomName .. " already " .. stateStr) end
    else table.insert(errors, roomName .. ": Controls not found") end
  end
  printOperationResult("Power sync", synced, #roomsToSync, errors)
  syncInProgress = false
end

function applyGainRouting()
  if not isRoomsDivided() then
    local priorityIdx = getPriorityRoomIndex()
    if priorityIdx then
      local nonPriorityIdx = 3 - priorityIdx
      local nonPriorityGain = component.gainComponents[nonPriorityIdx]
      local priorityGain = component.gainComponents[priorityIdx]
      if nonPriorityGain and nonPriorityGain["mute"] then
        nonPriorityGain["mute"].Boolean = true
        debugMsg("Muted gain[" .. nonPriorityIdx .. "] (Source: Room Combiner)")
      end
      if priorityGain and priorityGain["mute"] then
        priorityGain["mute"].Boolean = false
        debugMsg("Unmuted gain[" .. priorityIdx .. "] (Source: Room Combiner)")
      end
    end
  end
  applyRouting(config.routingRules.simple.gain)
end

function applyMatrixMixerMutes()
  if not component.matrixMixer then debugMsg("WARNING: Matrix mixer not found"); return end
  local muteState = isRoomsDivided()
  local success, errors = 0, {}
  for _, muteName in ipairs(config.component.matrixAudioMixer) do
    local mute = component.matrixMixer[muteName]
    if mute then
      mute.Boolean = muteState
      success = success + 1
      debugMsg(muteName .. " -> " .. (muteState and "[ Muted ]" or "[ Unmuted ]") .. " (Source: Room Combiner)")
    else table.insert(errors, muteName .. ": Not found") end
  end
  printOperationResult("Matrix mixer mutes", success, #config.component.matrixAudioMixer, errors)
end

function applyUCIStatusRouting()
  if not component.uciStatus then debugMsg("WARNING: UCI status not found"); return end
  local uciValue = isRoomsDivided() and config.component.uciNames[1] or
    (isRoomPoweredOn("RoomB") and config.component.uciNames[2] or config.component.uciNames[1])
  local currentUCI = component.uciStatus["current.uci"]
  if currentUCI then
    currentUCI.String = uciValue
    debugMsg("UCI status: " .. uciValue .. " (Source: Room Combiner)")
  else debugMsg("ERROR: UCI status control not found") end
end

function applyACPRComponentRouting()
  if config.features.disableACPRRouting then debugMsg("ACPR component routing disabled"); return end
  local isDivided = isRoomsDivided()
  local priorityIdx = getPriorityRoomIndex()
  local success, errors = 0, {}
  local bypassSettings = isDivided and {{idx = 3, desc = "Combined"}} or {{idx = 1, desc = "1"}, {idx = 2, desc = "2"}}
  for _, setting in ipairs(bypassSettings) do
    local acprComp = component.acprComponents[setting.idx]
    if acprComp and acprComp["TrackingBypass"] then
      acprComp["TrackingBypass"].Boolean = true
      success = success + 1
      debugMsg("ACPR[" .. setting.desc .. "] -> TrackingBypass: true (Source: Room Combiner)")
    else table.insert(errors, "ACPR[" .. setting.desc .. "]: TrackingBypass not found") end
  end
  if not isDivided and priorityIdx then
    local acprComp3 = component.acprComponents[3]
    if acprComp3 and acprComp3["CameraRouterOutput"] then
      local outputValue = config.component.acprOutputs[priorityIdx or 2]
      acprComp3["CameraRouterOutput"].String = outputValue
      success = success + 1
      debugMsg("ACPR[Combined] -> CameraRouterOutput: " .. outputValue .. " (Source: Room Combiner)")
    else table.insert(errors, "ACPR[Combined]: CameraRouterOutput not found") end
  end
  printOperationResult("ACPR component routing", success, 3, errors)
end

function applyCamRouterRouting()
  if not component.camRouter then debugMsg("WARNING: Cam router not found"); return end
  local isDivided = isRoomsDivided()
  local priorityIdx = getPriorityRoomIndex()
  local success, errors = 0, {}
  local routes = {
    {control = "select.1", divided = 1, combined = {1, 2}},
    {control = "select.2", divided = 2, combined = {1, 2}}
  }
  for _, route in ipairs(routes) do
    local ctrl = component.camRouter[route.control]
    if ctrl then
      local value = isDivided and route.divided or route.combined[priorityIdx or 2]
      ctrl.Value = value
      success = success + 1
      debugMsg("Cam Router " .. route.control .. " -> " .. value .. " (Source: Room Combiner)")
    else table.insert(errors, route.control .. " not found") end
  end
  printOperationResult("Cam router routing", success, #routes, errors)
end

function applyPriorityDependentRouting()
  debugMsg("Re-applying priority-dependent routing (Source: UCI Button)")
  applyGainRouting()
  applyRouting(config.routingRules.multiControl.mxaControls)
  applyACPRComponentRouting()
  applyCamRouterRouting()
end

function applyRoomMode()
  debugMsg("=== Applying Room State Configuration ===")
  local roomState = getRoomState()
  debugMsg("Current state: " .. roomState)
  if not canChangeWallState() then
    debugMsg("BLOCKED: Cannot change state - rooms are powered on (Source: Room Combiner)")
    interlockBtnRoomMode(1)
    if Controls.btnRoomMode and Controls.btnRoomMode[1] then Controls.btnRoomMode[1].Boolean = true end
    checkStatus()
    return
  end
  local ok, err = pcall(function()
    updateWallState()
    applyGainRouting()
    applyMatrixMixerMutes()
    applyRouting(config.routingRules.simple.acpr)
    applyRouting(config.routingRules.multiControl.mxaControls)
    applyUCIStatusRouting()
    applyACPRComponentRouting()
    applyCamRouterRouting()
    if roomState ~= "Divided" then
      if checkAnyRoomState(isRoomPoweredOn) then
        debugMsg("Syncing power (ON) to all rooms (Source: Room Combiner)")
        syncPowerToRooms(config.rooms, true, "Room Combiner")
      else debugMsg("All rooms OFF - no power sync needed") end
    end
    debugMsg("=== Room State Configuration Complete ===")
  end)
  if not ok then debugMsg("applyRoomMode failed: " .. tostring(err)) end
  checkStatus()
end

function setRoomStateIndex(index)
  if not Controls.btnRoomMode or not Controls.btnRoomMode[index] then return end
  Controls.btnRoomMode[index].Boolean = true
  interlockBtnRoomMode(index)
  applyRoomMode()
end

-------------------[ Status ]-------------------

function checkStatus()
  local msg = "OK"
  local val = 0
  if not component.roomCombiner then msg = "Room Combiner Missing"; val = 1 end
  local connected = 0
  for idx = 1, #config.rooms do
    if component.roomControls[idx] then connected = connected + 1 end
  end
  if connected < #config.rooms then msg = msg .. " (Rooms: " .. connected .. "/" .. #config.rooms .. ")"; val = 1 end
  msg = msg .. " | State: " .. getRoomState()
  if Controls.txtStatus then
    Controls.txtStatus.String = msg
    Controls.txtStatus.Value = val
  end
end

-------------------[ Discovery ]-------------------

function discoverComponents()
  debugMsg("=== Component Discovery Started ===")
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
        local compRef = Component.New(comp.Name)
        if compRef then
          if map.single then
            component[map.key] = compRef
            debugMsg("  Found " .. map.key .. ": " .. comp.Name)
            foundCount = foundCount + 1
          elseif map.indexed then
            local idx = getIndexFromName(comp.Name, map.hasCombined)
            if idx then
              component[map.key][idx] = compRef
              debugMsg("  Found " .. map.key .. "[" .. idx .. "]: " .. comp.Name)
              foundCount = foundCount + 1
            end
          end
        end
      end
    end
  end
  debugMsg("=== Component Discovery Complete: " .. foundCount .. " components found ===")
end

function cacheGainComponents()
  for i, gainName in ipairs(config.component.gains) do
    local gainComp = Component.New(gainName)
    if gainComp then
      component.gainComponents[i] = gainComp
      debugMsg("Cached gain: " .. gainName)
    else debugMsg("WARNING: Failed to cache gain: " .. gainName) end
  end
end

function validateComponents()
  local warnings = {}
  for _, comp in ipairs({{key = "roomCombiner", desc = "Room combiner"}, {key = "matrixMixer", desc = "Matrix mixer"}, {key = "uciStatus", desc = "UCI status"}, {key = "camRouter", desc = "Cam router"}}) do
    if not component[comp.key] then table.insert(warnings, comp.desc) end
  end
  for i, room in ipairs(config.rooms) do
    for _, comp in ipairs({{key = "roomControls", desc = "controls"}, {key = "mxaControls", desc = "MXA"}, {key = "acprComponents", desc = "ACPR"}}) do
      if not component[comp.key][i] then table.insert(warnings, room .. " " .. comp.desc) end
    end
  end
  if not component.acprComponents[3] then table.insert(warnings, "Combined ACPR") end
  if #warnings > 0 then debugMsg("WARNING: Missing components: " .. table.concat(warnings, ", ")) end
  return #warnings
end

function bindRoomControlHandlers()
  local handlerMap = {
    ledSystemPower = onRoomPowerChange,
    ledSystemCooling = onRoomCoolingChange
  }
  local handlerCount = 0
  for i, room in ipairs(config.rooms) do
    local comp = component.roomControls[i]
    if comp then
      for controlName, handler in pairs(handlerMap) do
        if comp[controlName] then
          comp[controlName].EventHandler = function() handler(room) end
          handlerCount = handlerCount + 1
        end
      end
    end
  end
  debugMsg("Registered " .. handlerCount .. " power/cooling handlers")
end

function bindUciButtonHandlers()
  local uciCount = 0
  if component.uciController then
    for _, btn in ipairs(config.uciButtons) do
      local button = component.uciController[btn.name]
      if button then
        button.EventHandler = uciSelectionChange
        debugMsg("Registered UCI button: " .. btn.name .. " (" .. btn.desc .. ")")
        uciCount = uciCount + 1
      end
    end
    debugMsg("Registered " .. uciCount .. "/" .. #config.uciButtons .. " UCI button handlers")
  else debugMsg("WARNING: UCI controller not found - skipping UCI button handlers") end
end

-------------------[ Event Handlers ]-------------------

function onRoomCoolingChange(roomName)
  debugMsg("Cooling state changed: " .. roomName .. " (Source: Room Controls)")
  updateBtnRoomModeDisabled()
end

function onRoomPowerChange(roomName)
  if syncInProgress then
    debugMsg("Sync in progress - ignoring power change for " .. roomName)
    return
  end
  debugMsg("=== Power State Changed: " .. roomName .. " (Source: Room Controls) ===")
  updateBtnRoomModeDisabled()
  if isRoomsDivided() then debugMsg(roomName .. " is divided - no sync needed"); return end
  local newPowerState = isRoomPoweredOn(roomName)
  debugMsg(roomName .. " power: " .. (newPowerState and "ON" or "OFF"))
  if not newPowerState and not checkAnyRoomState(isRoomPoweredOn) then
    debugMsg("All rooms OFF - auto-separating (Source: Room Controls)")
    syncPowerToRooms(config.rooms, false, "Auto-Separation")
    setRoomStateIndex(1)
    updateBtnRoomModeDisabled()
    debugMsg("=== Auto-Separation Complete ===")
    return
  end
  local roomsToSync = {}
  for _, rn in ipairs(config.rooms) do
    if rn ~= roomName then table.insert(roomsToSync, rn) end
  end
  if #roomsToSync > 0 then
    debugMsg("Syncing power (" .. (newPowerState and "ON" or "OFF") .. ") to: " .. table.concat(roomsToSync, ", ") .. " (Source: Room Controls)")
    syncPowerToRooms(roomsToSync, newPowerState, "Room Controls")
    applyUCIStatusRouting()
  end
end

function uciSelectionChange()
  if isRoomsDivided() then return end
  if not checkAnyRoomState(isRoomPoweredOn) then
    debugMsg("UCI button changed but system OFF - routing will apply on power on (Source: UCI Button)")
    return
  end
  local newPriority = getPriorityRoom()
  if newPriority then
    debugMsg("Priority room changed to " .. newPriority .. " (Source: UCI Button)")
    applyPriorityDependentRouting()
  end
end

if Controls.btnRoomMode then
  for i, btn in ipairs(Controls.btnRoomMode) do
    btn.EventHandler = function(ctl)
      if ctl.Boolean then
        debugMsg("btnRoomMode[" .. i .. "] pressed: " .. getRoomStateFromIndex(i) .. " (Source: Wall Button)")
        interlockBtnRoomMode(i)
        applyRoomMode()
      end
    end
  end
end

-------------------[ Always Run ]-------------------

function funcInit()
  debugMsg("=== Initialization Started ===")
  if not Controls.txtStatus or not Controls.btnRoomMode then
    print("ERROR: Missing required controls (txtStatus, btnRoomMode)")
    if Controls.txtStatus then
      Controls.txtStatus.String = "INIT FAILED"
      Controls.txtStatus.Value = 2
    end
    return
  end
  discoverComponents()
  validateComponents()
  cacheGainComponents()
  bindRoomControlHandlers()
  bindUciButtonHandlers()
  applyRoomMode()
  updateBtnRoomModeDisabled()
  checkStatus()
  debugMsg("=== Initialization Complete ===")
  debugMsg("Ready for operation")
end

DivisibleSpaceController = {
  applyRoomMode = applyRoomMode,
  applyPriorityDependentRouting = applyPriorityDependentRouting,
  checkStatus = checkStatus
}

funcInit()
