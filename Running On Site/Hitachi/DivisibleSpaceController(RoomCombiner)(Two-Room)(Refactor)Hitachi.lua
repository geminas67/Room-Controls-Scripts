--[[
  Divisible Space Controller - Two Room Version (Refactored)
  Author: Nikolas Smith, Q-SYS
  Version: 3.1 | Date: 2025-01-30
  Firmware Req: 10.0.1+
  
  Features:
  - Single-class architecture with data-driven routing engine
  - State-based control via btnRoomState interlock (Separated/RmA Combined/RmB Combined)
  - Comprehensive debug logging with phase markers
]]

-----------------------------[ Configuration ]-----------------------------
local config = {
  rooms = {"RoomA", "RoomB"},
  
  components = {
    gains = {"lvlPGMCollabA", "lvlPGMCollabB"},
    acpr = {"compACPRCollabA", "compACPRCollabB", combined = "compACPRCollabCombined"},
    acprOutputs = {"01", "02"},
    callSync = {"callSyncCollabA", "callSyncCollabB"},
    roomControls = {"compRoomControlsCollabA", "compRoomControlsCollabB"},
    uciNames = {"uciCollabB", "uciCollabA"},
    matrixMixerMutes = {
      "input.2.output.6.mute", "input.3.output.5.mute", 
      "input.4.output.2.mute", "input.4.output.4.mute", 
      "input.5.output.1.mute", "input.5.output.3.mute"
    }
  },
  
  features = {
    disableACPRRouting = false, -- Set to true to disable ACPR component routing (assignment and routing) (for future use)  
  },
  
  patterns = {
    roomControls = "^compRoomControls",
    roomCombiner = "^compRoomCombiner",
    camRouter = "^compCamRouter",
    matrixMixer = "^compMixerAudioCollab",
    mxaControls = "^compMXAControlsCollab",
    uciStatus = "^statusControlUCICollab",
    uciController = "^uciControllerCollabA$",
    acprComponents = "^compACPRCollab"
  },
  
  uciButtons = {
    {name = "btnNav07", room = "RoomA", desc = "RoomA-PC"},
    {name = "btnNav09", room = "RoomA", desc = "RoomA-Laptop"},
    {name = "btnNav08", room = "RoomB", desc = "RoomB-PC"},
    {name = "btnNav10", room = "RoomB", desc = "RoomB-Laptop"}
  },
  
}

-- Data-driven routing configuration (defined after config to avoid circular reference)
config.routingRules = {
  -- Simple routing: one control per room
  simple = {
    gain = {
      enabled = true,
      targetControl = "compGains 1",
      componentKey = "roomControls",
      getName = "Gain routing",
      separated = function(i) return config.components.gains[i] end,
      combined = function(priorityIdx) return config.components.gains[priorityIdx] end
    },
    
    acpr = {
      enabled = function() return not config.features.disableACPRRouting end,
      targetControl = "compACPR",
      componentKey = "roomControls",
      getName = "ACPR assignment",
      separated = function(i) return config.components.acpr[i] end,
      combined = function(priorityIdx) return config.components.acpr.combined end
    },
  },
  
  -- Multi-control routing: multiple controls per room
  multiControl = {
    mxaControls = {
      enabled = true,
      componentKey = "mxaControls",
      getName = "MXA controls routing",
      controls = {
        {name = "compCallSync", 
         separated = function(i) return config.components.callSync[i] end,
         combined = function(pIdx) return config.components.callSync[pIdx] end},
        {name = "compRoomControls", 
         separated = function(i) return config.components.roomControls[i] end,
         combined = function(pIdx) return config.components.roomControls[pIdx] end}
      }
    }
  }
}

-------------------[ Controls ]-------------------
local controls = {
  txtStatus = Controls.txtStatus,
  btnRoomState = Controls.btnRoomState  -- Interlock: 1=Separated, 2=RmA Combined, 3=RmB Combined
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
  local success = pcall(function() ctrl.EventHandler = handler end)
  return success
end

local function bindArray(ctrls, handler)
  if not ctrls or not handler then return false end
  local array = isArr(ctrls) and ctrls or {ctrls}
  local count = 0
  for i, ctrl in ipairs(array) do
    if ctrl and bind(ctrl, function(ctl) 
      local ok, err = pcall(handler, i, ctl)
      if not ok then print("ERROR: Handler failed at index " .. i .. ": " .. tostring(err)) end
    end) then
      count = count + 1
    end
  end
  return count > 0
end

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
  for _, name in ipairs({'btnRoomState'}) do
    local ctrl = controls[name]
    if ctrl and not isArr(ctrl) then controls[name] = {ctrl} end
  end
end

-------------------[ Generic Routing Engine ]-------------------
-- Generic function to apply simple routing rules (one control per room)
local function applySimpleRouting(self, rule, ruleName)
  local enabled
  if type(rule.enabled) == "function" then
    enabled = rule.enabled()
  else
    enabled = rule.enabled
  end
  if not enabled then
    self:debugPrint(ruleName .. " disabled")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  local priorityIdx = priorityRoom and ((priorityRoom == "RoomA") and 1 or 2)
  local success, errors = 0, {}
  
  for i, room in ipairs(config.rooms) do
    local comp = self.components[rule.componentKey][i]
    
    if comp and comp[rule.targetControl] then
      local value = isSeparated and rule.separated(i) or rule.combined(priorityIdx)
      
      if value and value ~= "" then
        setProp(comp[rule.targetControl], "String", value)
        success = success + 1
        self:debugPrint(room .. " -> " .. rule.targetControl .. ": " .. value)
      else
        table.insert(errors, room .. ": Invalid value")
      end
    else
      table.insert(errors, room .. ": " .. rule.targetControl .. " not found")
    end
  end
  
  self:printOperationResult(rule.getName, success, #config.rooms, errors)
end

-- Generic function to apply multi-control routing rules
local function applyMultiControlRouting(self, rule, ruleName)
  local enabled
  if type(rule.enabled) == "function" then
    enabled = rule.enabled()
  else
    enabled = rule.enabled
  end
  if not enabled then
    self:debugPrint(ruleName .. " disabled")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  local priorityIdx = priorityRoom and ((priorityRoom == "RoomA") and 1 or 2)
  local success, errors = 0, {}
  local total = #config.rooms * #rule.controls
  
  for i, room in ipairs(config.rooms) do
    local comp = self.components[rule.componentKey][i]
    
    for _, ctrl in ipairs(rule.controls) do
      if comp and comp[ctrl.name] then
        local value = isSeparated and ctrl.separated(i) or ctrl.combined(priorityIdx)
        
        if value then
          setProp(comp[ctrl.name], "String", value)
          success = success + 1
          self:debugPrint(room .. " -> " .. ctrl.name .. ": " .. value)
        else
          table.insert(errors, room .. ": Invalid " .. ctrl.name)
        end
      else
        table.insert(errors, room .. ": " .. ctrl.name .. " not found")
      end
    end
  end
  
  self:printOperationResult(rule.getName, success, total, errors)
end

-------------------[ DivisibleSpaceController ]-------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debugging)
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Two Room Divisible Space"
  self.debugging = debugging ~= false
  self.syncInProgress = false
  
  self.components = {
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
  
  return self
end

function DivisibleSpaceController:debugPrint(str)
  if self.debugging then print("[" .. self.roomName .. "] " .. str) end
end

function DivisibleSpaceController:printOperationResult(operation, success, total, errors)
  self:debugPrint(operation .. " complete: " .. success .. "/" .. total .. " successful")
  if errors and #errors > 0 then
    for _, err in ipairs(errors) do self:debugPrint("  ERROR: " .. err) end
  end
end

function DivisibleSpaceController:getRoomIndex(roomName)
  for i, name in ipairs(config.rooms) do
    if name == roomName then return i end
  end
  return nil
end

-------------------[ Component Discovery ]-------------------
function DivisibleSpaceController:discoverComponents()
  self:debugPrint("=== Component Discovery Started ===")
  
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
    return name:match("A$") and 1 or 
           name:match("B$") and 2 or 
           (hasCombined and name:match("Combined$") and 3)
  end
  
  local foundCount = 0
  for _, comp in ipairs(Component.GetComponents()) do
    for _, map in ipairs(discoveryMap) do
      if matchesPattern(comp.Name, map) then
        local component = Component.New(comp.Name)
        if component then
          if map.single then
            self.components[map.key] = component
            self:debugPrint("Found " .. map.key .. ": " .. comp.Name)
            foundCount = foundCount + 1
          elseif map.indexed then
            local idx = getIndexFromName(comp.Name, map.hasCombined)
            if idx then
              self.components[map.key][idx] = component
              self:debugPrint("Found " .. map.key .. "[" .. idx .. "]: " .. comp.Name)
              foundCount = foundCount + 1
            end
          end
        end
      end
    end
  end
  
  self:debugPrint("=== Component Discovery Complete: " .. foundCount .. " components found ===")
end

function DivisibleSpaceController:cacheGainComponents()
  for i, gainName in ipairs(config.components.gains) do
    local gainComp = Component.New(gainName)
    if gainComp then
      self.components.gainComponents[i] = gainComp
      self:debugPrint("Cached gain: " .. gainName)
    else
      self:debugPrint("WARNING: Failed to cache gain: " .. gainName)
    end
  end
end

-------------------[ Initialization ]-------------------
function DivisibleSpaceController:validateComponents()
  local warnings = {}
  
  -- Validate single components
  local singleComponents = {
    {key = "roomCombiner", desc = "Room combiner"},
    {key = "matrixMixer", desc = "Matrix mixer"},
    {key = "uciStatus", desc = "UCI status"},
    {key = "camRouter", desc = "Cam router"}
  }
  
  for _, comp in ipairs(singleComponents) do
    if not self.components[comp.key] then
      table.insert(warnings, comp.desc)
    end
  end
  
  -- Validate per-room components
  local roomComponents = {
    {key = "roomControls", desc = "controls"},
    {key = "mxaControls", desc = "MXA"},
    {key = "acprComponents", desc = "ACPR"}
  }
  
  for i, room in ipairs(config.rooms) do
    for _, comp in ipairs(roomComponents) do
      if not self.components[comp.key][i] then
        table.insert(warnings, room .. " " .. comp.desc)
      end
    end
  end
  
  -- Validate combined ACPR
  if not self.components.acprComponents[3] then
    table.insert(warnings, "Combined ACPR")
  end
  
  if #warnings > 0 then
    self:debugPrint("WARNING: Missing components: " .. table.concat(warnings, ", "))
  end
  
  return #warnings
end

function DivisibleSpaceController:init()
  self:debugPrint("=== Initialization Started ===")
  
  self:discoverComponents()
  self:validateComponents()
  self:cacheGainComponents()
  self:registerEventHandlers()
  self:setupRoomPowerEventHandlers()
  self:setupUCIButtonEventHandlers()
  self:applyRoomState()
  self:updateBtnRoomStateDisabledStates()
  self:checkStatus()
  
  self:debugPrint("=== Initialization Complete ===")
end

-------------------[ Event Registration ]-------------------
function DivisibleSpaceController:registerEventHandlers()
  if controls.btnRoomState then
    bindArray(controls.btnRoomState, function(i, ctl)
      if ctl.Boolean then
        self:debugPrint("btnRoomState[" .. i .. "] pressed: " .. self:getRoomStateFromIndex(i))
        self:applyBtnRoomStateInterlock(i)
        self:applyRoomState()
      end
    end)
    self:debugPrint("Registered btnRoomState handlers")
  end
end

function DivisibleSpaceController:setupRoomPowerEventHandlers()
  self:debugPrint("Setting up room power event handlers...")
  
  local handlers = {
    {control = "ledSystemPower", method = "onRoomPowerChanged"},
    {control = "ledSystemCooling", method = "onRoomCoolingChanged"}
  }
  
  local function bindHandler(comp, handler, room, i)
    if comp[handler.control] then
      return bind(comp[handler.control], function() self[handler.method](self, room, i) end)
    end
    return false
  end
  
  local count = 0
  for i, room in ipairs(config.rooms) do
    local comp = self.components.roomControls[i]
    if comp then
      for _, handler in ipairs(handlers) do
        if bindHandler(comp, handler, room, i) then count = count + 1 end
      end
    end
  end
  
  self:debugPrint("Registered " .. count .. " power/cooling handlers")
end

function DivisibleSpaceController:setupUCIButtonEventHandlers()
  if not self.components.uciController then
    self:debugPrint("WARNING: UCI controller not found - skipping UCI button handlers")
    return
  end
  
  local count = 0
  for _, btn in ipairs(config.uciButtons) do
    local button = self.components.uciController[btn.name]
    if button and bind(button, function() self:onUCIInputSelectionChanged() end) then
      self:debugPrint("Registered UCI button: " .. btn.name .. " (" .. btn.desc .. ")")
      count = count + 1
    end
  end
  
  self:debugPrint("Registered " .. count .. "/" .. #config.uciButtons .. " UCI button handlers")
end

-------------------[ Power Event Handlers ]-------------------
function DivisibleSpaceController:onRoomCoolingChanged(roomName, roomIndex)
  self:debugPrint("Cooling state changed: " .. roomName)
  self:updateBtnRoomStateDisabledStates()
end

function DivisibleSpaceController:onRoomPowerChanged(roomName, roomIndex)
  if self.syncInProgress then
    self:debugPrint("Sync in progress - ignoring power change for " .. roomName)
    return
  end
  
  self:debugPrint("=== Power State Changed: " .. roomName .. " ===")
  self:updateBtnRoomStateDisabledStates()
  
  if self:isRoomsSeparated() then
    self:debugPrint(roomName .. " is separated - no sync needed")
    return
  end
  
  local newPowerState = self:isRoomPoweredOn(roomName)
  self:debugPrint(roomName .. " power: " .. (newPowerState and "ON" or "OFF"))
  
  -- Check for auto-separation if all rooms are off
  if not newPowerState and self:shouldAutoSeparate() then
    self:debugPrint("All rooms OFF - auto-separating")
    self:separateRooms()
    return
  end
  
  -- Sync power to other rooms
  local roomsToSync = {}
  for _, rn in ipairs(config.rooms) do
    if rn ~= roomName then table.insert(roomsToSync, rn) end
  end
  
  if #roomsToSync > 0 then
    self:debugPrint("Syncing power (" .. (newPowerState and "ON" or "OFF") .. ") to: " .. table.concat(roomsToSync, ", "))
    self:syncPowerToRooms(roomsToSync, newPowerState)
    self:applyUCIStatusRouting()
  end
end

function DivisibleSpaceController:onUCIInputSelectionChanged()
  if self:isRoomsSeparated() then return end
  
  if not self:checkAnyRoomState(self.isRoomPoweredOn) then
    self:debugPrint("UCI button changed but system OFF - routing will apply on power on")
    return
  end
  
  local newPriority = self:getPriorityRoom()
  if newPriority then
    self:debugPrint("Priority room changed to " .. newPriority .. " - re-applying routing")
    self:applyPriorityDependentRouting()
  end
end

-------------------[ Power Synchronization ]-------------------
function DivisibleSpaceController:getRoomControlComponent(roomName)
  local idx = self:getRoomIndex(roomName)
  return idx and self.components.roomControls[idx]
end

function DivisibleSpaceController:syncPowerToRooms(roomsToSync, powerState)
  self.syncInProgress = true
  local synced, errors = 0, {}
  local stateStr = powerState and "ON" or "OFF"
  
  for _, roomName in ipairs(roomsToSync) do
    local comp = self:getRoomControlComponent(roomName)
    if comp and comp["ledSystemPower"] and comp["btnSystemOnOff"] then
      if comp["ledSystemPower"].Boolean ~= powerState then
        setProp(comp["btnSystemOnOff"], "Boolean", powerState)
        synced = synced + 1
        self:debugPrint("SYNCED: " .. roomName .. " -> " .. stateStr)
      else
        self:debugPrint("SKIP: " .. roomName .. " already " .. stateStr)
      end
    else
      table.insert(errors, roomName .. ": Controls not found")
    end
  end
  
  self:printOperationResult("Power sync", synced, #roomsToSync, errors)
  self.syncInProgress = false
end

function DivisibleSpaceController:shouldAutoSeparate()
  return not self:checkAnyRoomState(self.isRoomPoweredOn)
end

function DivisibleSpaceController:separateRooms()
  self:debugPrint("=== Auto-Separating Rooms ===")
  self.syncInProgress = true
  
  -- Power off all rooms
  for i, room in ipairs(config.rooms) do
    local comp = self.components.roomControls[i]
    if comp and comp["ledSystemPower"] and comp["ledSystemPower"].Boolean then
      setProp(comp["btnSystemOnOff"], "Boolean", false)
      self:debugPrint("Powered OFF: " .. room)
    end
  end
  
  -- Set to separated state
  self:setRoomStateIndex(1)  -- Index 1 = Separated
  self:updateBtnRoomStateDisabledStates()
  self.syncInProgress = false
  self:debugPrint("=== Auto-Separation Complete ===")
end

function DivisibleSpaceController:setRoomStateIndex(index)
  if controls.btnRoomState and controls.btnRoomState[index] then
    setProp(controls.btnRoomState[index], "Boolean", true)
    self:applyBtnRoomStateInterlock(index)
    self:applyRoomState()
  end
end

-------------------[ Wall Management ]-------------------
function DivisibleSpaceController:updateWallState()
  if not self.components.roomCombiner then return end
  
  local roomState = self:getRoomState()
  local wallShouldBeOpen = (roomState ~= "Separated")
  local wallControl = self.components.roomCombiner["wall.1.open"]
  
  if wallControl then
    setProp(wallControl, "Boolean", wallShouldBeOpen)
    self:debugPrint("Wall: " .. (wallShouldBeOpen and "OPEN" or "CLOSED") .. " (State: " .. roomState .. ")")
  else
    self:debugPrint("ERROR: Wall control not found")
  end
end

function DivisibleSpaceController:canChangeWallState()
  for _, room in ipairs(config.rooms) do
    if self:isRoomPoweredOn(room) then
      self:debugPrint("Wall change blocked - " .. room .. " is powered on")
      return false
    end
  end
  return true
end

function DivisibleSpaceController:updateBtnRoomStateDisabledStates()
  local states = {}
  local anyActive = false
  
  for _, room in ipairs(config.rooms) do
    local isOn = self:isRoomPoweredOn(room)
    local isCooling = self:isRoomCooling(room)
    local state = isOn and "ON" or (isCooling and "COOLING" or "OFF")
    table.insert(states, room .. ":" .. state)
    anyActive = anyActive or isOn or isCooling
  end
  
  -- Disable combine buttons (indices 2 & 3) when any room is on or cooling
  for i = 2, 3 do
    if controls.btnRoomState and controls.btnRoomState[i] then
      setProp(controls.btnRoomState[i], "IsDisabled", anyActive)
    end
  end
  
  self:debugPrint("btnRoomState[2,3] " .. (anyActive and "DISABLED" or "ENABLED") .. 
                 " [" .. table.concat(states, ", ") .. "]")
end

------------------[ Room State Management ]----------------------
function DivisibleSpaceController:applyBtnRoomStateInterlock(activeIndex)
  -- Interlock logic: ensure only the active button is true, all others are false
  if not controls.btnRoomState then return end
  
  for i = 1, #controls.btnRoomState do
    if i ~= activeIndex then
      if controls.btnRoomState[i] and controls.btnRoomState[i].Boolean then
        setProp(controls.btnRoomState[i], "Boolean", false)
        self:debugPrint("Interlock: Set btnRoomState[" .. i .. "] to false")
      end
    end
  end
end

function DivisibleSpaceController:getRoomState()
  -- Determine current state from btnRoomState interlock (READ ONLY)
  if controls.btnRoomState then
    if controls.btnRoomState[1] and controls.btnRoomState[1].Boolean then
      return "Separated"
    elseif controls.btnRoomState[2] and controls.btnRoomState[2].Boolean then
      return "RoomA_Combined"
    elseif controls.btnRoomState[3] and controls.btnRoomState[3].Boolean then
      return "RoomB_Combined"
    end
  end
  return "Separated" -- Default
end

function DivisibleSpaceController:getRoomStateFromIndex(index)
  local states = {"Separated", "RoomA_Combined", "RoomB_Combined"}
  return states[index] or "Unknown"
end

function DivisibleSpaceController:getPriorityRoom()
  if self:isRoomsSeparated() then return nil end
  
  -- Check UCI button states first (override btnRoomState priority)
  if self.components.uciController then
    -- Check if any button for a specific room is active
    for _, btn in ipairs(config.uciButtons) do
      local button = self.components.uciController[btn.name]
      if button and button.Boolean then
        return btn.room
      end
    end
  end
  
  -- Fallback to btnRoomState logic if no UCI buttons are active
  local roomState = self:getRoomState()
  local stateToRoom = {
    RoomA_Combined = "RoomA",
    RoomB_Combined = "RoomB"
  }
  
  return stateToRoom[roomState]
end

function DivisibleSpaceController:isRoomsSeparated()
  return self:getRoomState() == "Separated"
end

function DivisibleSpaceController:applyRoomState()
  self:debugPrint("=== Applying Room State Configuration ===")
  
  local roomState = self:getRoomState()
  self:debugPrint("Current state: " .. roomState)
  
  -- STEP 1: Validate wall can move (prevent changes while powered on)
  if not self:canChangeWallState() then
    self:debugPrint("BLOCKED: Cannot change state - rooms are powered on")
    if controls.btnRoomState and controls.btnRoomState[1] then
      setProp(controls.btnRoomState[1], "Boolean", true)
    end
    return
  end
  
  -- STEP 2: Physical wall movement
  self:updateWallState()
  
  -- STEP 3: Audio routing (must happen before power sync)
  self:applyGainRouting()
  self:applyMatrixMixerMutes()
  
  -- STEP 4: Component assignments
  self:applyACPRAssignment()
  self:applyMXAControlsRouting()
  self:applyUCIStatusRouting()
  
  -- STEP 5: Video routing
  self:applyACPRComponentRouting()
  self:applyCamRouterRouting()
  
  -- STEP 6: Power synchronization (last, after all routing is configured)
  if roomState ~= "Separated" then
    self:syncPowerOnCombine()
  end
  
  self:checkStatus()
  self:debugPrint("=== Room State Configuration Complete ===")
end

function DivisibleSpaceController:syncPowerOnCombine()
  if self:checkAnyRoomState(self.isRoomPoweredOn) then
    self:debugPrint("Syncing power (ON) to all rooms in combination")
    self:syncPowerToRooms(config.rooms, true)
  else
    self:debugPrint("All rooms OFF - no power sync needed")
  end
end

function DivisibleSpaceController:applyPriorityDependentRouting()
  self:debugPrint("Re-applying priority-dependent routing...")
  self:applyGainRouting()
  self:applyMXAControlsRouting()
  self:applyACPRComponentRouting()
  self:applyCamRouterRouting()
end

-------------------[ Audio Routing ]-------------------
function DivisibleSpaceController:applyGainRouting()
  -- Handle gain muting logic for combined mode
  if not self:isRoomsSeparated() then
    local priorityRoom = self:getPriorityRoom()
    if priorityRoom then
      local priorityIdx = (priorityRoom == "RoomA") and 1 or 2
      local nonPriorityIdx = 3 - priorityIdx
      local nonPriorityGain = self.components.gainComponents[nonPriorityIdx]
      local priorityGain = self.components.gainComponents[priorityIdx]
      
      if nonPriorityGain and nonPriorityGain["mute"] then
        setProp(nonPriorityGain["mute"], "Boolean", true)
        self:debugPrint("Muted gain[" .. nonPriorityIdx .. "]")
      end
      if priorityGain and priorityGain["mute"] then
        setProp(priorityGain["mute"], "Boolean", false)
        self:debugPrint("Unmuted gain[" .. priorityIdx .. "]")
      end
    end
  end
  
  -- Apply routing using generic engine
  applySimpleRouting(self, config.routingRules.simple.gain, "Gain routing")
end

function DivisibleSpaceController:applyMatrixMixerMutes()
  if not self.components.matrixMixer then
    self:debugPrint("WARNING: Matrix mixer not found")
    return
  end
  
  local muteState = self:isRoomsSeparated()  -- Separated = muted, Combined = unmuted
  local success = 0
  local errors = {}
  
  for _, muteName in ipairs(config.components.matrixMixerMutes) do
    local mute = self.components.matrixMixer[muteName]
    if mute then
      setProp(mute, "Boolean", muteState)
      success = success + 1
      self:debugPrint(muteName .. " -> " .. (muteState and "[ Muted ]" or "[ Unmuted ]"))
    else
      table.insert(errors, muteName .. ": Not found")
    end
  end
  
  self:printOperationResult("Matrix mixer mutes", success, #config.components.matrixMixerMutes, errors)
end

-------------------[ Component Assignments ]-------------------
function DivisibleSpaceController:applyACPRAssignment()
  applySimpleRouting(self, config.routingRules.simple.acpr, "ACPR assignment")
end

function DivisibleSpaceController:applyMXAControlsRouting()
  applyMultiControlRouting(self, config.routingRules.multiControl.mxaControls, "MXA controls routing")
end

function DivisibleSpaceController:applyUCIStatusRouting()
  if not self.components.uciStatus then
    self:debugPrint("WARNING: UCI status not found")
    return
  end
  
  local uciValue
  if self:isRoomsSeparated() then
    uciValue = config.components.uciNames[1]  -- Separated default: uciCollabB
  else
    -- Combined: Use uciCollabA if RoomB is powered on, otherwise uciCollabB
    uciValue = self:isRoomPoweredOn("RoomB") and 
               config.components.uciNames[2] or 
               config.components.uciNames[1]
    if not self:isRoomPoweredOn("RoomB") then
      self:debugPrint("RoomB power OFF - using " .. uciValue)
    end
  end
  
  local statusControl = self.components.uciStatus["current.uci"]
  if statusControl then
    setProp(statusControl, "String", uciValue)
    self:debugPrint("UCI status: " .. uciValue)
  else
    self:debugPrint("ERROR: UCI status control not found")
  end
end

-------------------[ Video Routing ]-------------------
function DivisibleSpaceController:applyACPRComponentRouting()
  if config.features.disableACPRRouting then
    self:debugPrint("ACPR component routing disabled")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  local success, errors = 0, {}
  
  -- Apply TrackingBypass settings
  local bypassSettings = isSeparated and 
    {{idx = 3, desc = "Combined"}} or 
    {{idx = 1, desc = "1"}, {idx = 2, desc = "2"}}
  
  for _, setting in ipairs(bypassSettings) do
    local acprComp = self.components.acprComponents[setting.idx]
    if acprComp and acprComp["TrackingBypass"] then
      setProp(acprComp["TrackingBypass"], "Boolean", true)
      success = success + 1
      self:debugPrint("ACPR[" .. setting.desc .. "] -> TrackingBypass: true")
    else
      table.insert(errors, "ACPR[" .. setting.desc .. "]: TrackingBypass not found")
    end
  end
  
  -- Set CameraRouterOutput when combined
  if not isSeparated and priorityRoom then
    local acprComp3 = self.components.acprComponents[3]
    if acprComp3 and acprComp3["CameraRouterOutput"] then
      local outputValue = (priorityRoom == "RoomA") and config.components.acprOutputs[1] or config.components.acprOutputs[2]
      setProp(acprComp3["CameraRouterOutput"], "String", outputValue)
      success = success + 1
      self:debugPrint("ACPR[Combined] -> CameraRouterOutput: " .. outputValue .. " (Priority: " .. priorityRoom .. ")")
    else
      table.insert(errors, "ACPR[Combined]: CameraRouterOutput not found")
    end
  end
  
  self:printOperationResult("ACPR component routing", success, 3, errors)
end

function DivisibleSpaceController:applyCamRouterRouting()
  if not self.components.camRouter then
    self:debugPrint("WARNING: Cam router not found")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  local success, errors = 0, {}
  
  -- Camera router routes: Separated (1->1, 2->2), CombinedA (both->1), CombinedB (both->2)
  local routes = {
    {control = "select.1", separated = 1, combinedA = 1, combinedB = 2},
    {control = "select.2", separated = 2, combinedA = 1, combinedB = 2}
  }
  
  for _, route in ipairs(routes) do
    local control = self.components.camRouter[route.control]
    if control then
      local value = isSeparated and route.separated or 
                    (priorityRoom == "RoomA" and route.combinedA or route.combinedB)
      setProp(control, "Value", value)
      success = success + 1
      self:debugPrint("Cam Router " .. route.control .. " -> " .. value)
    else
      table.insert(errors, route.control .. " not found")
    end
  end
  
  self:printOperationResult("Cam router routing", success, #routes, errors)
end

-------------------[ Status & Utilities ]-------------------
function DivisibleSpaceController:getRoomControlState(roomName, controlName)
  local comp = self:getRoomControlComponent(roomName)
  return comp and comp[controlName] and comp[controlName].Boolean or false
end

function DivisibleSpaceController:isRoomPoweredOn(roomName)
  return self:getRoomControlState(roomName, "ledSystemPower")
end

function DivisibleSpaceController:isRoomCooling(roomName)
  return self:getRoomControlState(roomName, "ledSystemCooling")
end

function DivisibleSpaceController:checkAnyRoomState(checkFunc)
  for _, room in ipairs(config.rooms) do
    if checkFunc(self, room) then return true end
  end
  return false
end

function DivisibleSpaceController:checkStatus()
  local msg = "OK"
  local val = 0
  
  if not self.components.roomCombiner then
    msg = "Room Combiner Missing"
    val = 1
  end
  
  local connected = 0
  for i = 1, #config.rooms do
    if self.components.roomControls[i] then connected = connected + 1 end
  end
  
  if connected < #config.rooms then
    msg = msg .. " (Rooms: " .. connected .. "/" .. #config.rooms .. ")"
    val = 1
  end
  
  msg = msg .. " | State: " .. self:getRoomState()
  
  if controls.txtStatus then
    controls.txtStatus.String = msg
    controls.txtStatus.Value = val
  end
end

-------------------[ Factory & Initialization ]-------------------
local function createController(roomName, debugging)
  local success, result = pcall(function()
    print("=== Initializing DivisibleSpaceController: " .. roomName .. " ===")
    
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    
    local controller = DivisibleSpaceController.new(roomName, debugging)
    if not controller then error("Constructor returned nil") end
    
    controller:init()
    return controller
  end)
  
  if success and result then
    print("✓ DivisibleSpaceController successfully created")
    _G.myDivisibleController = result
    return result
  else
    print("✗ ERROR: Failed to create controller: " .. tostring(result))
    if controls.txtStatus then
      controls.txtStatus.String = "INIT FAILED"
      controls.txtStatus.Value = 2
    end
    return nil
  end
end

-------------------[ Startup ]-------------------
local myDivisibleController = createController("Two Room Divisible Space", true)
