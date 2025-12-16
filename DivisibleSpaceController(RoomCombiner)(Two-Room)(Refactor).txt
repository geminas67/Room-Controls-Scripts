--[[
  Divisible Space Controller - Two Room Version (Refactored, Lean OOP)
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2025-10-18
  Firmware Req: 10.0.1+
  Notes:
  - SIMPLIFIED: Two-room configuration with streamlined wall and routing logic
  - Complies with Lua Refactoring Prompt specifications
  - Comprehensive control validation with descriptive error messages
  - Array normalization and centralized event registration
  - Enhanced BaseModule with initialization and cleanup
]]

-----------------------------[ Configuration Tables ]-----------------------------
local roomNames = {"RoomA", "RoomB"}

-- Room number mapping for audio router logic
local roomNumberMap = {
  RoomA = 1, RoomB = 2
}

local numberToRoomMap = {[1] = "RoomA", [2] = "RoomB"}

-- Gain control name mapping - index follows roomNumberMap
local gainControlNames = {"lvlPGMRmA", "lvlPGMRmB"}

-- Wall room pairs - simplified for two rooms
local wallRoomPairs = {
  [1] = {"RoomA", "RoomB"},  -- Main dividing wall
}

-- Simplified room combinations for two rooms
local roomCombinations = {
  {id=1, name="RoomA+RoomB Combined", activeRooms={RoomA=true, RoomB=true}, priority="RoomA"},
  {id=2, name="RoomA Separated", activeRooms={RoomA=true, RoomB=false}, priority=nil},
  {id=3, name="RoomB Separated", activeRooms={RoomA=false, RoomB=true}, priority=nil},
  {id=4, name="All Separated", activeRooms={RoomA=true, RoomB=true}, priority=nil},
}

-------------------[ Control References ]-------------------
local controls = {
  compRoomControls  = Controls.compRoomControls,
  compAudioRouter   = Controls.compAudioRouter,
  compRoomCombiner  = Controls.compRoomCombiner,
  txtStatus         = Controls.txtStatus,
  selCombination    = Controls.selRoomCombination,
  wallOpenButtons   = Controls.wallOpenButtons,
  btnRoomSelector   = Controls.btnRoomSelector,
}

local function validateControls()
  local required = {
    compRoomControls  = controls.compRoomControls,
    compAudioRouter   = controls.compAudioRouter,
    compRoomCombiner  = controls.compRoomCombiner,
    txtStatus         = controls.txtStatus,
    wallOpenButtons   = controls.wallOpenButtons
  }
  
  local optional = {
    selCombination = controls.selCombination,
    btnRoomSelector = controls.btnRoomSelector
  }
  
  local missing = {}
  local warnings = {}
  
  for name, control in pairs(required) do
    if not control then 
      table.insert(missing, name) 
    end
  end
  
  for name, control in pairs(optional) do
    if not control then
      table.insert(warnings, name)
    end
  end
  
  if #missing > 0 then
    print("ERROR: DivisibleSpaceController missing required controls:")
    for _, name in ipairs(missing) do
      print("  - " .. name)
    end
    print("Controller initialization aborted.")
    return false
  end
  
  if #warnings > 0 then
    print("WARNING: DivisibleSpaceController missing optional controls:")
    for _, name in ipairs(warnings) do
      print("  - " .. name)
    end
  end
  
  return true
end

-------------------[ Utility Functions ]-------------------
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
  if isArr(ctrl) then return ctrl end
  return type(ctrl) == "table" and { ctrl } or {}
end

local function normalizeControlArrays()
  local arrayControls = {'compRoomControls', 'compAudioRouter', 'wallOpenButtons', 'btnRoomSelector'}
  
  for _, controlName in ipairs(arrayControls) do
    local ctrl = controls[controlName]
    if ctrl and not isArr(ctrl) then
      controls[controlName] = { ctrl }
    end
  end
end

local function setProp(ctrl, prop, val)
  if not ctrl or ctrl[prop] == val then return end
  ctrl[prop] = val
end

local function bind(control, handler)
  if not control or not handler then return false end
  local success, _ = pcall(function()
    control.EventHandler = handler
  end)
  return success
end

local function bindArray(ctrls, handler)
  if not ctrls or not handler then return false end
  local controlArray = getControlArray(ctrls)
  local bindCount = 0
  for i, ctrl in ipairs(controlArray) do
    if ctrl then
      if bind(ctrl, function(ctl) 
        local success, err = pcall(handler, i, ctl)
        if not success then
          print("Event handler error for control index " .. i .. ": " .. tostring(err))
        end
      end) then
        bindCount = bindCount + 1
      end
    end
  end
  return bindCount > 0
end

local function forEach(ctrls, fn)
  for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

local function tableContains(t, val)
  for _, v in ipairs(t) do
    if v == val then return true end
  end
  return false
end

local function resetComponentsArray(componentsArray, clearString)
  if not isArr(componentsArray) then return end
  clearString = clearString or "[Clear]"
  for i = 1, #componentsArray do
    componentsArray[i] = nil
  end
end

local function parseConfiguration(configString)
  if not configString or configString == "" then return {} end
  
  local roomGroups = {}
  local currentGroup = {}
  local inGroup = false
  local currentNumber = ""
  
  for i = 1, #configString do
    local char = configString:sub(i, i)
    if char == "[" then
      inGroup = true
      currentGroup = {}
    elseif char == "]" then
      if #currentNumber > 0 then
        table.insert(currentGroup, tonumber(currentNumber))
        currentNumber = ""
      end
      if #currentGroup > 0 then
        table.insert(roomGroups, currentGroup)
      end
      inGroup = false
    elseif char == "," and inGroup then
      if #currentNumber > 0 then
        table.insert(currentGroup, tonumber(currentNumber))
        currentNumber = ""
      end
    elseif char:match("%d") then
      currentNumber = currentNumber .. char
    end
  end
  return roomGroups
end

-------------------[ Base Module Class ]------------------
local BaseModule = {}; BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
  local self = setmetatable({}, BaseModule)
  self.controller = controller
  self.name = name or "Module"
  self.initialized = false
  return self
end

function BaseModule:debug(msg)
  if self.controller and self.controller.debugPrint then
    self.controller:debugPrint("[" .. self.name .. "] " .. msg)
  end
end

function BaseModule:init()
  self.initialized = true
  self:debug("Module initialized")
end

function BaseModule:cleanup() 
  self.initialized = false
  self:debug("Cleanup complete") 
end

-------------------[ Component Management Module ]-------------------
local ComponentModule = setmetatable({}, {__index = BaseModule})
ComponentModule.__index = ComponentModule

function ComponentModule.new(controller)
  local self = BaseModule.new(controller, "ComponentModule")
  setmetatable(self, ComponentModule)
  self.componentTypes = {
    roomCombiner = "room_combiner",
    roomControls = "device_controller_script",
    audioRouter = "router_with_output"
  }
  self:init()
  return self
end

function ComponentModule:discoverComponents()
  local namesTable = {
    RoomControlsNames = {},
    AudioRouterNames = {},
    RoomCombinerNames = {},
    UciButtonsNames = {}
  }

  for _, component in ipairs(Component.GetComponents()) do
    if component.Type == self.componentTypes.roomControls and string.match(component.Name, "^compRoomControls") then
      table.insert(namesTable.RoomControlsNames, component.Name)
    elseif component.Type == self.componentTypes.audioRouter then
      table.insert(namesTable.AudioRouterNames, component.Name)
    elseif component.Type == self.componentTypes.roomCombiner then
      table.insert(namesTable.RoomCombinerNames, component.Name)
    elseif component.Type == "custom_controls" then
      table.insert(namesTable.UciButtonsNames, component.Name)
    end
  end

  for _, nameList in pairs(namesTable) do
    table.sort(nameList)
    table.insert(nameList, self.controller.clearString)
  end

  return namesTable
end

-------------------[ RoomSelector Visibility Module ]-------------------
local RoomButtonVisibilityModule = setmetatable({}, {__index = BaseModule})
RoomButtonVisibilityModule.__index = RoomButtonVisibilityModule

function RoomButtonVisibilityModule.new(controller)
  local self = BaseModule.new(controller, "RoomButtonVisibilityModule")
  setmetatable(self, RoomButtonVisibilityModule)
  self:init()
  return self
end

function RoomButtonVisibilityModule:updateAllRoomButtonVisibility()
  self:debug("Updating RoomSelector button visibility for all rooms...")
 
  if not controls.btnRoomSelector or #controls.btnRoomSelector == 0 then
      self:debug("No RoomSelector buttons found - skipping visibility update")
      return
  end
 
  local configString = self:getConfigString()
  local roomGroups = parseConfiguration(configString)
 
  if #roomGroups == 0 then
      self:debug("No groups found - setting all separate")
      self:setAllRoomsSeparate()
      return
  end
 
  self:debug("Applying RoomSelector visibility based on " .. #roomGroups .. " groups")
 
  for i, roomName in ipairs(roomNames) do
      self:updateRoomButtonVisibility(i, roomName, roomGroups)
  end
 
  self:debug("RoomSelector button visibility update complete")
end

function RoomButtonVisibilityModule:updateRoomButtonVisibility(roomIndex, roomName, roomGroups)
  local btnRoomName = self.controller.btnRoomSelector[roomIndex]
  if not btnRoomName or btnRoomName == "" then
      self:debug("No RoomSelector component name for room " .. roomIndex .. " (" .. roomName .. ")")
      return
  end
 
  local btnRoomSelector = Component.New(btnRoomName)
  if not btnRoomSelector then
      self:debug("Failed to create RoomSelector component for " .. roomName .. " (" .. btnRoomName .. ")")
      return
  end
 
  self:debug("Updating RoomSelector states for room " .. roomIndex .. " (" .. roomName .. ")")
 
  local sourceRoomNum = roomNumberMap[roomName]
  local sourceGroup = nil
  for _, group in ipairs(roomGroups) do
      if tableContains(group, sourceRoomNum) then
          sourceGroup = group
          break
      end
  end
 
  if not sourceGroup then
      self:debug(" No group for " .. roomName .. " - setting as separate")
      for toggleIndex = 1, 2 do  -- Only 2 rooms for two-room setup
          local toggleControlName = "toggle." .. toggleIndex
          if btnRoomSelector[toggleControlName] then
              btnRoomSelector[toggleControlName].Boolean = (toggleIndex == roomIndex)
              self:debug(" " .. roomName .. " -> " .. toggleControlName .. ".Boolean = " .. tostring(toggleIndex == roomIndex) .. " (" .. roomNames[toggleIndex] .. ")")
          else
              self:debug(" WARNING: " .. toggleControlName .. " control not found on RoomSelector component for " .. roomName)
          end
      end
      return
  end
 
  for toggleIndex = 1, 2 do  -- Only 2 rooms for two-room setup
      local targetRoomName = roomNames[toggleIndex]
      local targetRoomNum = roomNumberMap[targetRoomName]
      local isInGroup = tableContains(sourceGroup, targetRoomNum)
     
      local toggleControlName = "toggle." .. toggleIndex
      if btnRoomSelector[toggleControlName] then
          btnRoomSelector[toggleControlName].Boolean = isInGroup
          self:debug(" " .. roomName .. " -> " .. toggleControlName .. ".Boolean = " .. tostring(isInGroup) .. " (" .. targetRoomName .. ")")
      else
          self:debug(" WARNING: " .. toggleControlName .. " control not found on RoomSelector component for " .. roomName)
      end
  end
end

function RoomButtonVisibilityModule:getConfigString()
  if not self.controller.components.roomCombiner then return "" end
  local configControl = self.controller.components.roomCombiner["room.combiner.output.configuration"]
  return configControl and configControl.String or ""
end

function RoomButtonVisibilityModule:setAllRoomsSeparate()
  self:debug("Setting all rooms to separated state (own toggle only)")
 
  for i, roomName in ipairs(roomNames) do
    local btnRoomName = self.controller.btnRoomSelector[i]
    if btnRoomName and btnRoomName ~= "" then
      local btnRoomSelector = Component.New(btnRoomName)
      if btnRoomSelector then
        for toggleIndex = 1, 2 do  -- Only 2 rooms for two-room setup
          local toggleControlName = "toggle." .. toggleIndex .. ".Boolean"
          if btnRoomSelector[toggleControlName] then
            setProp(btnRoomSelector, toggleControlName, (toggleIndex == i))
          end
        end
        self:debug("Set " .. roomName .. " RoomSelector to separated state")
      end
    end
  end
end

-------------------[ Power Synchronization Module ]-------------------
local PowerSyncModule = setmetatable({}, {__index = BaseModule})
PowerSyncModule.__index = PowerSyncModule

function PowerSyncModule.new(controller)
  local self = BaseModule.new(controller, "PowerSyncModule")
  setmetatable(self, PowerSyncModule)
  self.syncInProgress = false
  self:init()
  return self
end

function PowerSyncModule:setupRoomPowerEventHandlers()
  self:debug("Setting up room power state event handlers...")
 
  local handlersSetup = 0
 
  for i, roomName in ipairs(roomNames) do
    local comp = self.controller.components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      if bind(comp["btnSystemOnOff"], function()
        self:onRoomPowerChanged(roomName, i)
      end) then
        handlersSetup = handlersSetup + 1
        self:debug("Power event handler set for " .. roomName .. " (" .. (self.controller.roomComponents[i] or "N/A") .. ")")
      else
        self:debug("WARNING: Failed to bind power handler for " .. roomName)
      end
    else
      self:debug("WARNING: Could not set power handler for " .. roomName .. " - component or control not found")
    end
  end
 
  self:debug("Room power event handlers setup: " .. handlersSetup .. "/" .. #roomNames .. " successful")
end

function PowerSyncModule:onRoomPowerChanged(roomName, roomIndex)
  if self.syncInProgress then
    self:debug("Sync already in progress - ignoring power change for " .. roomName)
    return
  end

  self:debug("Power state changed for " .. roomName .. " - checking for combined rooms...")

  local configString = self:getConfigString()
  if not configString then 
    if self.controller.wallModule then
      self.controller.wallModule:updateWallStates()
    end
    return 
  end

  local roomGroups = parseConfiguration(configString)
  local changedRoomNum = roomNumberMap[roomName]

  local group = nil
  for _, g in ipairs(roomGroups) do
    if tableContains(g, changedRoomNum) then
      group = g
      break
    end
  end

  if not group or #group < 2 then
    self:debug(roomName .. " is not in a combined group - no sync needed")
    if self.controller.wallModule then
      self.controller.wallModule:updateWallStates()
    end
    return
  end

  local newPowerState = self.controller:isRoomPoweredOn(roomName)
  self:debug(roomName .. " new power state: " .. (newPowerState and "ON" or "OFF"))

  if not newPowerState then
    self:debug("Room " .. roomName .. " powered OFF - checking if all combined rooms in group are now off...")
    if self:shouldAutoSeparateGroup(group) then
      self:debug("All rooms in group are OFF - automatically separating group")
      self:separateGroup(group)
      if self.controller.wallModule then
        self.controller.wallModule:updateWallStates()
      end
      return
    end
  end

  local roomsToSync = {}
  for _, num in ipairs(group) do
    if num ~= changedRoomNum then
      local otherName = numberToRoomMap[num]
      if otherName then
        table.insert(roomsToSync, otherName)
      end
    end
  end

  if #roomsToSync == 0 then
    self:debug("No other rooms to sync with " .. roomName)
    if self.controller.wallModule then
      self.controller.wallModule:updateWallStates()
    end
    return
  end

  self:debug("Synchronizing power state (" .. (newPowerState and "ON" or "OFF") .. ") to combined rooms in group: " .. table.concat(roomsToSync, ", "))

  self:syncPowerToRooms(roomsToSync, newPowerState)
  
  if self.controller.wallModule then
    self.controller.wallModule:updateWallStates()
  end
end

function PowerSyncModule:getConfigString()
  if not self.controller.components.roomCombiner then
    self:debug("No room combiner component available")
    return nil
  end
 
  local configControl = self.controller.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    self:debug("No configuration control found on room combiner")
    return nil
  end
 
  return configControl.String or ""
end

function PowerSyncModule:syncPowerToRooms(roomsToSync, powerState)
  self.syncInProgress = true
 
  local syncedRooms = 0
  local syncErrors = {}
 
  for _, roomName in ipairs(roomsToSync) do
    local roomIndex = self:getRoomIndex(roomName)
    if roomIndex then
      local comp = self.controller.components.roomControls[roomIndex]
      if comp and comp["btnSystemOnOff"] then
        local currentState = comp["btnSystemOnOff"].Boolean
        if currentState ~= powerState then
          setProp(comp["btnSystemOnOff"], "Boolean", powerState)
          syncedRooms = syncedRooms + 1
          self:debug("SYNCED: " .. roomName .. " -> " .. (powerState and "ON" or "OFF"))
        else
          self:debug("SKIP: " .. roomName .. " already " .. (powerState and "ON" or "OFF"))
        end
      else
        local errorMsg = roomName .. ": Component or btnSystemOnOff control not found"
        table.insert(syncErrors, errorMsg)
        self:debug("ERROR: " .. errorMsg)
      end
    else
      local errorMsg = roomName .. ": Room index not found"
      table.insert(syncErrors, errorMsg)
      self:debug("ERROR: " .. errorMsg)
    end
  end
 
  if self.controller.printOperationResult then
    self.controller:printOperationResult("Power sync", syncedRooms, #roomsToSync, syncErrors)
  end
 
  self.syncInProgress = false
end

function PowerSyncModule:shouldAutoSeparateGroup(group)
  local allRoomsOff = true
  local groupSize = #group
 
  for _, roomNum in ipairs(group) do
    local roomName = numberToRoomMap[roomNum]
    if roomName then
      local roomPowerState = self.controller:isRoomPoweredOn(roomName)
      self:debug("Checking " .. roomName .. " power state: " .. (roomPowerState and "ON" or "OFF"))
     
      if roomPowerState then
        allRoomsOff = false
        self:debug("Found " .. roomName .. " still powered ON - separation not needed")
        break
      end
    end
  end
 
  self:debug("Auto-separation check for group: " .. groupSize .. " rooms, all off: " .. tostring(allRoomsOff))
  return allRoomsOff
end

function PowerSyncModule:separateGroup(group)
  self:debug("Executing automatic group separation...")
 
  if not self.controller.components.roomCombiner then
    self:debug("ERROR: No room combiner component available for separation")
    return false
  end
 
  local groupRooms = {}
  for _, num in ipairs(group) do
    local name = numberToRoomMap[num]
    if name then groupRooms[name] = true end
  end
 
  local wallsClosed = 0
  local wallErrors = {}

  for wallIndex = 1, 1 do  -- Only one wall for two-room setup
    local wallPair = wallRoomPairs[wallIndex]
    if wallPair then
      local allRoomsInGroup = true
      for _, roomName in ipairs(wallPair) do
        if not groupRooms[roomName] then
          allRoomsInGroup = false
          break
        end
      end
      
      if allRoomsInGroup then
        local wallControlName = "wall." .. wallIndex .. ".open"
        local wallControl = self.controller.components.roomCombiner[wallControlName]
       
        if wallControl then
          local currentState = wallControl.Boolean
          if currentState then
            setProp(wallControl, "Boolean", false)
            wallsClosed = wallsClosed + 1
            self:debug("SEPARATED: Wall " .. wallIndex .. " (" .. table.concat(wallPair, "/") .. ") - wall closed")
          end
        else
          local errorMsg = "Wall " .. wallIndex .. ": " .. wallControlName .. " control not found"
          table.insert(wallErrors, errorMsg)
          self:debug("ERROR: " .. errorMsg)
        end
      end
    end
  end
 
  if self.controller.printOperationResult then
    self.controller:printOperationResult("Automatic group separation", wallsClosed, wallsClosed, wallErrors)
  end
 
  if self.controller.wallModule then
    self.controller.wallModule:syncWallButtonStates()
  end
 
  self.controller:applyAudioRouting()
  self.controller:applyGainRouting()
  if self.controller.btnVisibilityModule then
    self.controller.btnVisibilityModule:updateAllRoomButtonVisibility()
  end
 
  return wallsClosed > 0
end

function PowerSyncModule:getRoomIndex(roomName)
  for i, rn in ipairs(roomNames) do
    if rn == roomName then
      return i
    end
  end
  return nil
end

-------------------[ Wall Module ]-------------------
local WallModule = setmetatable({}, {__index = BaseModule})
WallModule.__index = WallModule

function WallModule.new(controller)
  local self = BaseModule.new(controller, "WallModule")
  setmetatable(self, WallModule)
  self:init()
  return self
end

function WallModule:syncWallButtonStates()
  self:debug("Syncing UI wall buttons with room combiner wall states...")
  
  if not self.controller.components.roomCombiner then
    self:debug("No room combiner available for wall sync")
    return
  end
  
  local syncedWalls = 0
  for i = 1, 1 do  -- Only one wall for two-room setup
    local wallButton = controls.wallOpenButtons[i]
    if wallButton then
      local wallControlName = "wall." .. i .. ".open"
      local wallControl = self.controller.components.roomCombiner[wallControlName]
      
      if wallControl then
        local combinerState = wallControl.Boolean
        setProp(wallButton, "Boolean", combinerState)
        syncedWalls = syncedWalls + 1
        self:debug("Synced wall " .. i .. ": " .. wallControlName .. " = " .. tostring(combinerState))
      else
        self:debug("ERROR: Wall " .. i .. " control not found on room combiner")
      end
    end
  end
end

function WallModule:setupWallControlEventHandlers()
  self:debug("Setting up room combiner wall control event handlers...")
  
  if not self.controller.components.roomCombiner then
    self:debug("No room combiner available for wall event handlers")
    return
  end
  
  for i = 1, 1 do  -- Only one wall for two-room setup
    local wallControlName = "wall." .. i .. ".open"
    local wallControl = self.controller.components.roomCombiner[wallControlName]
    
    if wallControl then
      if bind(wallControl, function()
        local combinerState = wallControl.Boolean
        local wallButton = controls.wallOpenButtons[i]
        
        if wallButton then
          setProp(wallButton, "Boolean", combinerState)
          self:debug("External wall change detected - Wall " .. i .. ": " .. tostring(combinerState))
          self:updateWallStates()
        end
      end) then
        self:debug("Wall control event handler set for wall " .. i)
      end
    end
  end
end

function WallModule:updateWallStates()
  self:debug("Updating wall states...")
  
  for wallIndex, roomPair in pairs(wallRoomPairs) do
    local wallButton = controls.wallOpenButtons[wallIndex]
    
    if wallButton then
      local shouldDisable = false
      
      -- Check if ANY room in the pair is powered on
      for _, roomName in ipairs(roomPair) do
        if self.controller:isRoomPoweredOn(roomName) then
          shouldDisable = true
          break
        end
      end
      
      setProp(wallButton, "IsDisabled", shouldDisable)
      self:debug("Wall " .. wallIndex .. ": " .. (shouldDisable and "DISABLED" or "ENABLED"))
    end
  end
end

-------------------[ DivisibleSpaceController (Main Orchestrator) ]-------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController
DivisibleSpaceController.clearString = "[Clear]"

function DivisibleSpaceController.new(roomName, debugging)
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Two Room Divisible Space"
  self.debugging = debugging ~= false
  self.clearString = DivisibleSpaceController.clearString
  
  self.components = {
    roomCombiner = nil,
    roomControls = {},
    audioRouter = {},
    btnRoomSelector = {},
    invalid = {roomCombiner = false, roomControls = false, audioRouter = false, btnRoomSelector = false}
  }
  
  self.roomComponents = {}
  self.audioRouters = {}
  self.btnRoomSelector = {}
  
  self.componentModule = ComponentModule.new(self)
  self.btnVisibilityModule = RoomButtonVisibilityModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  
  resetComponentsArray(self.roomComponents, self.clearString)
  resetComponentsArray(self.audioRouters, self.clearString)
  resetComponentsArray(self.btnRoomSelector, self.clearString)
  
  for i, _ in ipairs(roomNames) do
    self.roomComponents[i] = nil
    self.audioRouters[i] = nil
    self.btnRoomSelector[i] = nil
  end
  
  return self
end

function DivisibleSpaceController:debugPrint(str)
  if self.debugging then
    print("[" .. (self.roomName or "DivisibleSpace") .. "] " .. str)
  end
end

function DivisibleSpaceController:printOperationResult(operationType, successCount, totalCount, errorList)
  self:debugPrint(operationType .. " complete: " .. successCount .. "/" .. totalCount .. " successful")
  if errorList and #errorList > 0 then
    self:debugPrint(operationType .. " errors: " .. #errorList)
    for _, error in ipairs(errorList) do
      self:debugPrint(" - " .. error)
    end
  end
end

function DivisibleSpaceController:safeComponentAccess(component, control, action, value)
  if not component or not component[control] then return false end
  local success, result = pcall(function()
    if      action == "set"         then component[control].Boolean = value; return true
    elseif  action == "setString"   then component[control].String = value; return true
    elseif  action == "get"         then return component[control].Boolean
    elseif  action == "getString"   then return component[control].String end
    return false
  end)
  if not success then self:debugPrint("Component access error: "..tostring(result)); return false end
  return result
end

----------------[ Initialization ]--------------------------
function DivisibleSpaceController:init()
  self:debugPrint("Starting initialization...")
  self:discoverComponents()
  self:setupCombinationSelector()
  self:registerEventHandlers()
  self:loadInitialComponents()
  self:checkStatus()
  if self.wallModule then self.wallModule:updateWallStates() end
  self:debugPrint("Initialization complete")
end

function DivisibleSpaceController:setupCombinationSelector()
  if not controls.selCombination then return end
  
  local choices = {}
  for _, combo in ipairs(roomCombinations) do
    table.insert(choices, combo.name)
  end
  controls.selCombination.Choices = choices
end

function DivisibleSpaceController:loadInitialComponents()
  self:debugPrint("Loading initial component assignments...")
  
  forEach(controls.compRoomControls, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading room control " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "roomControls")
      if component then
        self:updateRoomComponent(control.String, i)
      end
    end
  end)
  
  forEach(controls.compAudioRouter, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading audio router " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "audioRouter")
      if component then
        self:updateAudioRouter(control.String, i)
      end
    end
  end)
  
  forEach(controls.btnRoomSelector, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading RoomSelector buttons " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "btnRoomSelector")
      if component then
        self:updateBTNRoomSelector(control.String, i)
      end
    end
  end)
  
  if controls.compRoomCombiner.String and controls.compRoomCombiner.String ~= "" and controls.compRoomCombiner.String ~= self.clearString then
    self:debugPrint("Loading room combiner: " .. controls.compRoomCombiner.String)
    local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if component then
      self.components.roomCombiner = component
      
      local configControl = component["room.combiner.output.configuration"]
      if configControl then
        bind(configControl, function()
          self:debugPrint("Room configuration changed")
          self:applyAudioRouting()
          self:applyGainRouting()
          
          if self.btnVisibilityModule then
            self.btnVisibilityModule:updateAllRoomButtonVisibility()
          end
        end)
        
        self:applyAudioRouting()
        self:applyGainRouting()
        
        if self.btnVisibilityModule then
          self.btnVisibilityModule:updateAllRoomButtonVisibility()
        end
      end
      
      if self.wallModule then 
        self.wallModule:syncWallButtonStates() 
        self.wallModule:setupWallControlEventHandlers()
      end
    end
  end
  
  self:debugPrint("Initial component loading complete")
  
  -- Set up power synchronization event handlers after components are loaded
  if self.powerSyncModule then
    self:debugPrint("Setting up power synchronization event handlers...")
    self.powerSyncModule:setupRoomPowerEventHandlers()
  end
end

function DivisibleSpaceController:discoverComponents()
  self:debugPrint("Discovering components...")
  
  local namesTable = self.componentModule:discoverComponents()
  
  if controls.compRoomCombiner then
    controls.compRoomCombiner.Choices = namesTable.RoomCombinerNames
  end
  
  forEach(controls.compRoomControls, function(_, control)
    if control then control.Choices = namesTable.RoomControlsNames end
  end)
  
  forEach(controls.compAudioRouter, function(_, control)
    if control then control.Choices = namesTable.AudioRouterNames end
  end)
  
  forEach(controls.btnRoomSelector, function(_, control)
    if control then control.Choices = namesTable.UciButtonsNames end
  end)
  
  self:debugPrint("Component discovery complete")
end

function DivisibleSpaceController:setComponent(ctrl, componentType)
  if not ctrl then
    self:setComponentInvalid(componentType)
    return nil
  end
  
  local componentName = ctrl.String
  
  if componentName == "" or componentName == self.clearString then
    ctrl.String = ""
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return nil
  end
  
  local component = Component.New(componentName)
  if not component then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    return nil
  end
  
  local componentControls = Component.GetControls(component)
  if not componentControls or #componentControls < 1 then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    return nil
  end
  
  ctrl.Color = "white"
  self:setComponentValid(componentType)
  self:debugPrint("Connected to " .. componentType .. ": " .. componentName)
  return component
end

function DivisibleSpaceController:setComponentInvalid(componentType)
  self.components.invalid[componentType] = true
  self:checkStatus()
end

function DivisibleSpaceController:setComponentValid(componentType)
  self.components.invalid[componentType] = false
  self:checkStatus()
end

------------------[ Event Handler Registration ]----------------------
function DivisibleSpaceController:registerEventHandlers()
  local singleEventMap = {
    {ctrl = controls.compRoomCombiner, handler = function(ctl) 
      self:debugPrint("Room combiner changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "roomCombiner")
      if component then
        self.components.roomCombiner = component
        
        local configControl = component["room.combiner.output.configuration"]
        if configControl then
          bind(configControl, function()
            self:applyAudioRouting()
            self:applyGainRouting()
            
            if self.btnVisibilityModule then
              self.btnVisibilityModule:updateAllRoomButtonVisibility()
            end
          end)
          self:applyAudioRouting()
          self:applyGainRouting()
          
          if self.btnVisibilityModule then
            self.btnVisibilityModule:updateAllRoomButtonVisibility()
          end
        end
      end
    end},
    {ctrl = controls.selCombination, handler = function(ctl) 
      local comboIdx = self:getComboIndex(ctl.String)
      if comboIdx then
        self:setRoomStates(comboIdx)
      end
    end}
  }
  
  for _, mapping in ipairs(singleEventMap) do
    bind(mapping.ctrl, mapping.handler)
  end
  
  local arrayEventMap = {
    {ctrls = controls.compRoomControls, handler = function(i, ctl) 
      self:debugPrint("Room control " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "roomControls")
      if component then
        self:updateRoomComponent(ctl.String, i)
      else
        self:updateRoomComponent("", i)
      end
    end},
    {ctrls = controls.compAudioRouter, handler = function(i, ctl) 
      self:debugPrint("Audio router " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "audioRouter")
      if component then
        self:updateAudioRouter(ctl.String, i)
      else
        self:updateAudioRouter("", i)
      end
    end},
    {ctrls = controls.btnRoomSelector, handler = function(i, ctl) 
      self:debugPrint("RoomSelector buttons " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "btnRoomSelector")
      if component then
        self:updateBTNRoomSelector(ctl.String, i)
      else
        self:updateBTNRoomSelector("", i)
      end
    end},
    {ctrls = controls.wallOpenButtons, handler = function(i, wallButton)
      local wallPair = wallRoomPairs[i]
      if wallPair then
        local uiState = wallButton.Boolean
        
        local anyRoomOn = false
        for _, roomName in ipairs(wallPair) do
          if self:isRoomPoweredOn(roomName) then
            anyRoomOn = true
            break
          end
        end
        
        if anyRoomOn then
          setProp(wallButton, "Boolean", not uiState)
          self:debugPrint("SAFETY BLOCK: Wall " .. i .. " blocked - rooms powered on")
          return
        end
        
        if self.components.roomCombiner then
          local wallControlName = "wall." .. i .. ".open"
          local wallControl = self.components.roomCombiner[wallControlName]
          if wallControl then
            setProp(wallControl, "Boolean", uiState)
            self:debugPrint("Wall " .. i .. " set to " .. (uiState and "OPEN" or "CLOSED"))
          end
        end
      end
      if self.wallModule then self.wallModule:updateWallStates() end
    end}
  }
  
  for _, mapping in ipairs(arrayEventMap) do
    bindArray(mapping.ctrls, mapping.handler)
  end
  
  self:debugPrint("Event handlers setup complete")
end

function DivisibleSpaceController:updateComponent(name, roomIndex, componentType, nameArray, componentArray, debugLabel)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local oldName = nameArray[roomIndex]
  nameArray[roomIndex] = name
  if name and name ~= "" then
    componentArray[roomIndex] = Component.New(name)
  else
    componentArray[roomIndex] = nil
  end
  if oldName ~= name then
    self:debugPrint(debugLabel .. " " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated")
    self:checkStatus()
  end
end

function DivisibleSpaceController:updateRoomComponent(name, roomIndex)
  self:updateComponent(name, roomIndex, "roomControls", self.roomComponents, self.components.roomControls, "Room component")
end

function DivisibleSpaceController:updateAudioRouter(name, roomIndex)
  self:updateComponent(name, roomIndex, "audioRouter", self.audioRouters, self.components.audioRouter, "Audio router")
end

function DivisibleSpaceController:updateBTNRoomSelector(name, roomIndex)
  self:updateComponent(name, roomIndex, "btnRoomSelector", self.btnRoomSelector, self.components.btnRoomSelector, "RoomSelector buttons")
end

function DivisibleSpaceController:getComboIndex(comboName)
  for idx, combo in ipairs(roomCombinations) do
    if combo.name == comboName then return idx end
  end
  return nil
end

function DivisibleSpaceController:shouldWallBeOpenForCombo(roomPair, combo)
  local room1Active = combo.activeRooms[roomPair[1]] or false
  local room2Active = combo.activeRooms[roomPair[2]] or false
  return room1Active and room2Active
end

function DivisibleSpaceController:setRoomStates(comboIdx)
  local combo = roomCombinations[comboIdx]
  if not combo then
    self:debugPrint("ERROR: Invalid combination index: " .. tostring(comboIdx))
    return false
  end
  self:debugPrint("Applying room combination: " .. combo.name)
  
  if self.components.roomCombiner then
    for wallIndex, roomPair in pairs(wallRoomPairs) do
      local shouldOpen = self:shouldWallBeOpenForCombo(roomPair, combo)
      local wallControlName = "wall." .. wallIndex .. ".open"
      local wallControl = self.components.roomCombiner[wallControlName]
      if wallControl then
        setProp(wallControl, "Boolean", shouldOpen)
        self:debugPrint("Wall " .. wallIndex .. " set to " .. (shouldOpen and "OPEN" or "CLOSED"))
      end
    end
    
    if self.wallModule then
      self.wallModule:syncWallButtonStates()
    end
  end
  
  local roomStateErrors = {}
  local successfulRoomStates = 0
  
  for i, roomName in ipairs(roomNames) do
    local comp = self.components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      local isActive = combo.activeRooms[roomName] or false
      setProp(comp["btnSystemOnOff"], "Boolean", isActive)
      successfulRoomStates = successfulRoomStates + 1
      self:debugPrint("Room " .. roomName .. " -> " .. (isActive and "ON" or "OFF"))
    else
      local errorMsg = roomName .. ": Component or btnSystemOnOff not found"
      table.insert(roomStateErrors, errorMsg)
    end
  end
  
  self:printOperationResult("Room states", successfulRoomStates, #roomNames, roomStateErrors)
  
  self:applyAudioRouting()
  self:applyGainRouting()
  
  -- Update RoomSelector button visibility
  if self.btnVisibilityModule then
    self:debugPrint("Updating RoomSelector button visibility for combination...")
    self.btnVisibilityModule:updateAllRoomButtonVisibility()
  end
  
  self:checkStatus()
  if self.wallModule then self.wallModule:updateWallStates() end
  return true
end

function DivisibleSpaceController:applyAudioRouting()
  self:debugPrint("Applying audio routing...")
  
  if not self.components.roomCombiner then
    self:debugPrint("ERROR: No room combiner")
    return
  end
  
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then return end
  
  local configString = configControl.String
  local roomGroups = parseConfiguration(configString)
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  for i, roomName in ipairs(roomNames) do
    local router = self.components.audioRouter[i]
    
    if router and router["select.1"] then
      local inputNumber = self:getInputForRoom(roomName, roomGroups)
      
      if inputNumber >= 1 and inputNumber <= 16 then
        setProp(router["select.1"], "Value", inputNumber)
        successfulRoutings = successfulRoutings + 1
      else
        table.insert(routingErrors, roomName .. ": Invalid input " .. inputNumber)
      end
    end
  end
  
  self:printOperationResult("Audio routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:applyGainRouting()
  self:debugPrint("Applying gain routing...")
  
  if not self.components.roomCombiner then
    self:debugPrint("ERROR: No room combiner")
    return
  end
  
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then return end
  
  local configString = configControl.String
  local roomGroups = parseConfiguration(configString)
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]
    
    if roomComp and roomComp["compGains 1"] then
      local gainControlName = self:getGainControlForRoom(roomName, roomGroups)
      
      if gainControlName and gainControlName ~= "" then
        setProp(roomComp["compGains 1"], "String", gainControlName)
        successfulRoutings = successfulRoutings + 1
      else
        table.insert(routingErrors, roomName .. ": Invalid gain control")
      end
    end
  end
  
  self:printOperationResult("Gain routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:getGainControlForRoom(roomName, roomGroups)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return gainControlNames[1] end
  
  if #roomGroups == 0 then
    return gainControlNames[roomNumber]
  end
  
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      -- Return lowest room number's gain control (highest priority)
      local highestPriorityRoom = math.huge
      for _, rn in ipairs(group) do
        if rn < highestPriorityRoom then
          highestPriorityRoom = rn
        end
      end
      return gainControlNames[highestPriorityRoom]
    end
  end
  
  return gainControlNames[roomNumber]
end

function DivisibleSpaceController:getInputForRoom(roomName, roomGroups)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return 1 end
  
  if #roomGroups == 0 then
    return roomNumber
  end
  
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      local highestPriorityRoom = math.huge
      for _, rn in ipairs(group) do
        if rn < highestPriorityRoom then
          highestPriorityRoom = rn
        end
      end
      return highestPriorityRoom
    end
  end
  
  return roomNumber
end

function DivisibleSpaceController:isRoomPoweredOn(roomName)
  for i, rn in ipairs(roomNames) do
    if rn == roomName then
      local comp = self.components.roomControls[i]
      if comp and comp["btnSystemOnOff"] then
        return comp["btnSystemOnOff"].Boolean
      end
      return false
    end
  end
  return false
end

function DivisibleSpaceController:checkStatus()
  local invalidComponents = {}
  local validComponentCount = 0
  local totalComponentCount = 0
  
  for componentType, isInvalid in pairs(self.components.invalid) do
    totalComponentCount = totalComponentCount + 1
    if isInvalid then
      table.insert(invalidComponents, componentType)
    else
      validComponentCount = validComponentCount + 1
    end
  end
  
  local connectedRooms = 0
  for i = 1, #roomNames do
    if self.roomComponents[i] and self.roomComponents[i] ~= "" then
      connectedRooms = connectedRooms + 1
    end
  end
  
  local connectedRouters = 0
  for i = 1, #roomNames do
    if self.audioRouters[i] and self.audioRouters[i] ~= "" then
      connectedRouters = connectedRouters + 1
    end
  end
  
  local connectedRoomSelector = 0
  for i = 1, #roomNames do
    if self.btnRoomSelector[i] and self.btnRoomSelector[i] ~= "" then
      connectedRoomSelector = connectedRoomSelector + 1
    end
  end
  
  if controls.txtStatus then
    if #invalidComponents > 0 then
      controls.txtStatus.String = "Invalid: " .. table.concat(invalidComponents, ", ")
      controls.txtStatus.Value = 1
    else
      local statusMsg = "OK"
      if connectedRooms < #roomNames then
        statusMsg = statusMsg .. " (Rooms: " .. connectedRooms .. "/" .. #roomNames .. ")"
      end
      if connectedRouters < #roomNames then
        statusMsg = statusMsg .. " (Routers: " .. connectedRouters .. "/" .. #roomNames .. ")"
      end
      if connectedRoomSelector < #roomNames then
        statusMsg = statusMsg .. " (RoomSelector: " .. connectedRoomSelector .. "/" .. #roomNames .. ")"
      end
      controls.txtStatus.String = statusMsg
      controls.txtStatus.Value = 0
    end
  end
end

function DivisibleSpaceController:cleanup()
  local modules = {self.componentModule, self.btnVisibilityModule, self.powerSyncModule, self.wallModule}
  for _, module in ipairs(modules) do
    if module and module.cleanup then module:cleanup() end
  end
  
  self:debugPrint("Cleanup completed")
end

-------------------[ Initialization ]-------------------
local function createDivisibleSpaceController(roomName, debugging)
  if not roomName or roomName == "" then
    print("ERROR: createDivisibleSpaceController requires a valid roomName")
    return nil
  end
  
  debugging = debugging ~= false
  
  local success, controller = pcall(function()
    print("Initializing DivisibleSpaceController for " .. roomName)
    if not validateControls() then
      error("Control validation failed")
    end
    normalizeControlArrays()
    local object = DivisibleSpaceController.new(roomName, debugging)
    if not object then error("Controller constructor returned nil") end
    object:init()
    return object
  end)
  
  if success and controller then
    print("✓ DivisibleSpaceController successfully created")
    _G.myDivisibleController = controller
    return controller
  else
    print("✗ ERROR: DivisibleSpaceController creation failed: " .. tostring(controller))
    if controls and controls.txtStatus then
      controls.txtStatus.String = "INIT FAILED"
      controls.txtStatus.Value = 2
    end
    return nil
  end
end

------------------------[ Startup ]------------------------
local myDivisibleController = createDivisibleSpaceController("Two Room Divisible Space", true)
