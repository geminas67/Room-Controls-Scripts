--[[
  Divisible Space Controller with Room Priority System (Refactored, Lean OOP, DRY Event Registration)
  Author: Nikolas Smith, Q-SYS
  Version: 3.1 | Date: 2025-10-04
  Firmware Req: 10.0.1+
  Notes:
  - UPDATED: Now complies with latest Lua Refactoring Prompt specifications
  - Enhanced validation: Comprehensive control validation with descriptive error messages
  - Array normalization: Automatic conversion of single controls to array format
  - Optimized event registration: Batch event registration using handler maps
  - Enhanced BaseModule: Improved module pattern with initialization and cleanup
  - Factory functions: Comprehensive error handling with graceful degradation
  - Property access optimization: Cached references and redundancy prevention
  - All event registration is DRY and centralized using control/event maps.
  - Each logical domain is its own class; orchestrator is thin.
  - Debug/config standardized, all validation centralized.
  
  DRY Improvements (v3.1):
  - Generic updateComponent() consolidates updateRoomComponent, updateAudioRouter, updateBTNRoomSelector
  - Centralized printOperationResult() utility eliminates repetitive error/debug print patterns
  - Generic handleBatchResult() for consistent batch operation error handling
  - All modules use controller's centralized utilities for consistent reporting
  
  Room Priority Hierarchy:
  SalonD --> SalonE (D has priority over E)
  SalonA --> SalonB --> SalonC (A has highest priority in group)
  SalonF --> SalonG --> SalonH (F has highest priority in group)
 
  Special Rules:
  - SalonD has priority when combined with A/B/C
  - SalonE has priority when combined with F/G/H
  - SalonD has priority when all rooms combined
]]

-----------------------------[ Configuration Tables ]-----------------------------
local roomNames = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"}

-- Room number mapping for audio router logic
local roomNumberMap = {
  SalonD = 1, SalonE = 2, SalonA = 3, SalonB = 4,
  SalonC = 5, SalonF = 6, SalonG = 7, SalonH = 8
}

local numberToRoomMap = {}
for name, num in pairs(roomNumberMap) do numberToRoomMap[num] = name end

-- Gain control name mapping - index follows roomNumberMap
local gainControlNames = {
  "lvlSalonD", "lvlSalonE", "lvlSalonA", "lvlSalonB",
  "lvlSalonC", "lvlSalonF", "lvlSalonG", "lvlSalonH"
}

local wallRoomPairs = {
  [1]   = {"SalonD", "SalonE"}, 
  [2]   = {"SalonA", "SalonB"}, 
  [3]   = {"SalonB", "SalonC"},
  [4]   = {"SalonF", "SalonG"}, 
  [5]   = {"SalonG", "SalonH"}, 
  [6]   = {"SalonD", "SalonA", "SalonB", "SalonC"},
  [7]   = {"SalonE", "SalonF", "SalonG", "SalonH"}, 
  [8]   = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC"},
  [9]   = {"SalonD", "SalonE", "SalonF", "SalonG", "SalonH"},
  [10]  = {"SalonA", "SalonB", "SalonC"},
  [11]  = {"SalonF", "SalonG", "SalonH"},
  [12]  = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"},
  -- Individual room separation buttons (13-20)
  [13]  = {"SalonD"},  -- Separate Salon D from all others
  [14]  = {"SalonE"},  -- Separate Salon E from all others
  [15]  = {"SalonA"},  -- Separate Salon A from all others
  [16]  = {"SalonB"},  -- Separate Salon B from all others
  [17]  = {"SalonC"},  -- Separate Salon C from all others
  [18]  = {"SalonF"},  -- Separate Salon F from all others
  [19]  = {"SalonG"},  -- Separate Salon G from all others
  [20]  = {"SalonH"}   -- Separate Salon H from all others
}

local roomCombinations = {
  { id=1, name="SalonD+SalonE Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=true, SalonE=true, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=2, name="SalonA+SalonB Combined", activeRooms={SalonA=true, SalonB=true, SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=3, name="SalonB+SalonC Combined", activeRooms={SalonA=false, SalonB=true, SalonC=true, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonB" },
  { id=4, name="SalonF+SalonG Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=true, SalonG=true, SalonH=false}, priority="SalonF" },
  { id=5, name="SalonG+SalonH Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=true, SalonH=true}, priority="SalonG" },
  { id=6, name="SalonD+SalonA+SalonB+SalonC Combined", activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=7, name="SalonE+SalonF+SalonG+SalonH Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonE" },
  { id=8, name="SalonD+SalonE+SalonA+SalonB+SalonC Combined", activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=true, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=9,name="SalonD+SalonE+SalonF+SalonG+SalonH Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonD" },
  { id=10,name="SalonA+SalonB+SalonC Combined", activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=11,name="SalonF+SalonG+SalonH Combined", activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=true, SalonG=true, SalonH=true}, priority="SalonF" },
  { id=12,name="All Combined", activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonD" },
  { id=13, name="All Separated", activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority=nil },

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
    -- Core required controls
    compRoomControls  = controls.compRoomControls,
    compAudioRouter   = controls.compAudioRouter,
    compRoomCombiner  = controls.compRoomCombiner,
    txtStatus         = controls.txtStatus,
    wallOpenButtons   = controls.wallOpenButtons
  }
  
  local optional = {
    -- Optional controls for enhanced functionality
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
    print("WARNING: DivisibleSpaceController missing optional controls (reduced functionality):")
    for _, name in ipairs(warnings) do
      print("  - " .. name)
    end
  end
  
  return true
end

-------------------[ Utility Functions ]-------------------
-- Best Practices for Consistency:
-- • Always Keep Utility Functions: Retaining bind() and bindArray() improves code consistency
-- • Validate Controls First: Use proactive validation (validateControls()) before binding
-- • Normalize Arrays: Use normalization utility early (normalizeControlArrays())
-- • Centralize Event Registration: Place all event registration in registerEventHandlers()

local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
  if isArr(ctrl) then return ctrl end
  return type(ctrl) == "table" and { ctrl } or {}
end

local function normalizeControlArrays()
  -- Normalize all array controls to consistent structures
  -- This ensures bindArray() receives properly structured control arrays
  local arrayControls = {
    'compRoomControls', 'compAudioRouter', 'wallOpenButtons', 'btnRoomSelector'
  }
  
  for _, controlName in ipairs(arrayControls) do
    local ctrl = controls[controlName]
    if ctrl and not isArr(ctrl) then
      -- Convert single control to array format
      controls[controlName] = { ctrl }
    end
  end
end

local function setProp(ctrl, prop, val)
  if not ctrl or ctrl[prop] == val then return end  -- Guard against redundant assignments
  ctrl[prop] = val
end

-- Robust bind() utility with validation and error handling
local function bind(control, handler)
  if not control or not handler then return false end
  -- Validate that EventHandler property is writable (handles non-UI controls)
  local success, _ = pcall(function()
    control.EventHandler = handler
  end)
  return success
end

-- Enhanced bindArray() with pcall protection and bind count tracking
local function bindArray(ctrls, handler)
  if not ctrls or not handler then return false end
  local controlArray = getControlArray(ctrls)
  local bindCount = 0
  for i, ctrl in ipairs(controlArray) do
    if ctrl then
      if bind(ctrl, function(ctl) 
        -- Use pcall for critical handlers to prevent event propagation errors
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
 
  -- Reset to clean state
  for i = 1, #roomNames do
    componentsArray[i] = nil
  end
end


-----------------------------[ Utility Functions ]-----------------------------
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

function BaseModule:safeAccess(component, control, action, value)
  return self.controller:safeComponentAccess(component, control, action, value)
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
    btnRoomSelector = "custom_controls",
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
    elseif component.Type == self.componentTypes.btnRoomSelector then
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
 
  -- Get parsed room groups from current config
  local configString = self:getConfigString()
  local roomGroups = parseConfiguration(configString)
 
  if #roomGroups == 0 then
      self:debug("No groups found - setting all separate")
      self:setAllRoomsSeparate()
      return
  end
 
  self:debug("Applying RoomSelector visibility based on " .. #roomGroups .. " groups")
 
  -- Update each room's RoomSelector buttons based on groups
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
 
  -- Find the group containing this room (source room number)
  local sourceRoomNum = roomNumberMap[roomName]
  local sourceGroup = nil
  for _, group in ipairs(roomGroups) do
      if tableContains(group, sourceRoomNum) then
          sourceGroup = group
          break
      end
  end
 
  -- If no group found, treat as separate (only own toggle true)
  if not sourceGroup then
      self:debug(" No group for " .. roomName .. " - setting as separate")
      for toggleIndex = 1, 8 do
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
 
  -- Set toggles based on group membership
  for toggleIndex = 1, 8 do
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

function RoomButtonVisibilityModule:shouldToggleBeVisible(sourceRoomName, targetRoomName, combination)
  -- A room's own toggle should always be visible (true)
  if sourceRoomName == targetRoomName then
    return true
  end
 
  -- Check if both rooms are active in the current combination
  local sourceActive = combination.activeRooms[sourceRoomName] or false
  local targetActive = combination.activeRooms[targetRoomName] or false
 
  -- Both rooms must be active for the toggle to be visible
  return sourceActive and targetActive
end

function RoomButtonVisibilityModule:setAllRoomsSeparate()
  self:debug("Setting all rooms to separated state (own toggle only)")
 
  for i, roomName in ipairs(roomNames) do
    local btnRoomName = self.controller.btnRoomSelector[i]
    if btnRoomName and btnRoomName ~= "" then
      local btnRoomSelector = Component.New(btnRoomName)
      if btnRoomSelector then
        for toggleIndex = 1, 8 do
          local toggleControlName = "toggle." .. toggleIndex .. ".Boolean"
          if btnRoomSelector[toggleControlName] then
            -- Only the room's own toggle should be true
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
  self.syncInProgress = false -- Flag to prevent sync loops
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
    -- Update wall states even if no config
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
    -- Update wall states for standalone room power changes
    if self.controller.wallModule then
      self.controller.wallModule:updateWallStates()
    end
    return
  end

  -- Get the new power state of the changed room
  local newPowerState = self.controller:isRoomPoweredOn(roomName)
  self:debug(roomName .. " new power state: " .. (newPowerState and "ON" or "OFF"))

  -- Check for automatic separation if room powered off
  if not newPowerState then
    self:debug("Room " .. roomName .. " powered OFF - checking if all combined rooms in group are now off...")
    if self:shouldAutoSeparateGroup(group) then
      self:debug("All rooms in group are OFF - automatically separating group")
      self:separateGroup(group)
      -- Update wall states after separation
      if self.controller.wallModule then
        self.controller.wallModule:updateWallStates()
      end
      return -- No need to sync power states if we're separating
    end
  end

  -- Find all other rooms in the group to synchronize
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
    -- Update wall states even if no sync needed
    if self.controller.wallModule then
      self.controller.wallModule:updateWallStates()
    end
    return
  end

  self:debug("Synchronizing power state (" .. (newPowerState and "ON" or "OFF") .. ") to combined rooms in group: " .. table.concat(roomsToSync, ", "))

  -- Perform the synchronization
  self:syncPowerToRooms(roomsToSync, newPowerState)
  
  -- Update wall states after power synchronization
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
  self.syncInProgress = true -- Prevent sync loops
 
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
 
  self.syncInProgress = false -- Re-enable sync detection
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
 
  -- Convert group numbers to names set for quick lookup
  local groupRooms = {}
  for _, num in ipairs(group) do
    local name = numberToRoomMap[num]
    if name then groupRooms[name] = true end
  end
 
  -- Close all walls that connect rooms within this group
  local wallsClosed = 0
  local wallErrors = {}

  for wallIndex = 1, 12 do -- Only process buttons 1-12 for room combiner walls
    local wallPair = wallRoomPairs[wallIndex]
    if wallPair then
      -- Check if ALL rooms in this wall pair are in the powered-off group
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
          if currentState then -- If wall is currently open, close it
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
 
  -- Sync UI wall buttons to match the room combiner state
  if self.controller.wallModule then
    self.controller.wallModule:syncWallButtonStates()
  end
 
  -- Trigger audio routing, gain routing, and Room Button visibility updates after separation
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
  local syncErrors = {}
 
  for i = 1, 20 do -- Extended range to include individual room separation buttons
    local wallButton = controls.wallOpenButtons[i]
    if wallButton then
      local wallPair = wallRoomPairs[i]
      if wallPair then
        if i <= 12 then
          -- Buttons 1-12: Sync with room combiner wall controls
          local wallControlName = "wall." .. i .. ".open"
          local wallControl = self.controller.components.roomCombiner[wallControlName]
         
          if wallControl then
            local combinerState = wallControl.Boolean
            setProp(wallButton, "Boolean", combinerState)
            syncedWalls = syncedWalls + 1
           
            self:debug("Synced wall " .. i .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. "): " ..
                            wallControlName .. " = " .. tostring(combinerState) .. " (rooms " ..
                            (combinerState and "COMBINED" or "SEPARATED") .. ")")
          else
            local errorMsg = "Wall " .. i .. ": " .. wallControlName .. " control not found on room combiner"
            table.insert(syncErrors, errorMsg)
            self:debug("ERROR: " .. errorMsg)
          end
        else
          -- Buttons 13-20: Individual room separation buttons - no room combiner control to sync
          -- These buttons maintain their current state based on wall states
          syncedWalls = syncedWalls + 1
          self:debug("Individual separation button " .. i .. " (" .. wallPair[1] .. ") - no room combiner sync needed")
        end
      end
    else
      local errorMsg = "Wall " .. i .. ": UI button not found"
      table.insert(syncErrors, errorMsg)
      self:debug("ERROR: " .. errorMsg)
    end
  end
 
  if self.controller.printOperationResult then
    self.controller:printOperationResult("Wall button sync", syncedWalls, 20, syncErrors)
  end
end

function WallModule:setupWallControlEventHandlers()
  self:debug("Setting up room combiner wall control event handlers...")
 
  if not self.controller.components.roomCombiner then
    self:debug("No room combiner available for wall event handlers")
    return
  end
 
  local handlersSetup = 0
  for i = 1, 12 do -- Only buttons 1-12 have room combiner wall controls
    local wallControlName = "wall." .. i .. ".open"
    local wallControl = self.controller.components.roomCombiner[wallControlName]
   
    if wallControl then
      if bind(wallControl, function()
        local combinerState = wallControl.Boolean
        local wallButton = controls.wallOpenButtons[i]
       
        if wallButton then
          -- Sync UI button with room combiner state
          setProp(wallButton, "Boolean", combinerState)
         
          local wallPair = wallRoomPairs[i]
          if wallPair then
            self:debug("External wall change detected - Wall " .. i .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. "): " ..
                            wallControlName .. " = " .. tostring(combinerState) .. " (rooms " ..
                            (combinerState and "COMBINED" or "SEPARATED") .. ")")
          end
         
          -- Update wall button states for safety logic
          self:updateWallStates()
        end
      end) then
        handlersSetup = handlersSetup + 1
      end
    end
  end
 
  self:debug("Wall control event handlers setup: " .. handlersSetup .. "/12 successful")
end

function WallModule:updateWallStates()
  self:debug("Updating wall states...")
 
  local wallStatesUpdated = 0
  local wallStateErrors = {}
 
  for wallIndex, roomPair in pairs(wallRoomPairs) do
    local wallButton = controls.wallOpenButtons[wallIndex]
   
    if wallButton then
      -- Check if ANY room in the pair is powered on
      local shouldDisable = false
      local roomStates = {}
      
      for _, roomName in ipairs(roomPair) do
        local isRoomOn = self.controller:isRoomPoweredOn(roomName)
        table.insert(roomStates, roomName .. ":" .. (isRoomOn and "ON" or "OFF"))
        if isRoomOn then
          shouldDisable = true
        end
      end
      
      setProp(wallButton, "IsDisabled", shouldDisable)
      wallStatesUpdated = wallStatesUpdated + 1
     
      self:debug("Wall " .. wallIndex .. " (" .. table.concat(roomPair, "/") .. "): " ..
                      (shouldDisable and "DISABLED" or "ENABLED") ..
                      " [" .. table.concat(roomStates, ", ") .. "]")
    else
      local errorMsg = "Wall " .. wallIndex .. ": Button control not found"
      table.insert(wallStateErrors, errorMsg)
      self:debug("ERROR: " .. errorMsg)
    end
  end
 
  if self.controller.printOperationResult then
    self.controller:printOperationResult("Wall states update", wallStatesUpdated, #wallRoomPairs, wallStateErrors)
  end
end

-------------------[ DivisibleSpaceController (Main Orchestrator) ]-------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController
DivisibleSpaceController.clearString = "[Clear]"

function DivisibleSpaceController.new(roomName, debugging)
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Divisible Space"
  self.debugging = debugging ~= false
  self.clearString = DivisibleSpaceController.clearString
  
  -- Component storage
  self.components = {
    roomCombiner = nil,
    roomControls = {},
    audioRouter = {},
    gains = {},  -- Now handling gains similarly to audio routers for efficiency
    btnRoomSelector = {},
    invalid = {roomCombiner = false, roomControls = false, audioRouter = false, gains = false, btnRoomSelector = false}
  }
  
  -- Room component arrays - use state management utility
  self.roomComponents = {} -- Names
  self.audioRouters = {} -- Names
  self.btnRoomSelector = {} -- Names
  
  -- Initialize modules using BaseModule pattern
  self.componentModule = ComponentModule.new(self)
  self.btnVisibilityModule = RoomButtonVisibilityModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  
  -- Reset component arrays to ensure clean state
  resetComponentsArray(self.roomComponents, self.clearString)
  resetComponentsArray(self.audioRouters, self.clearString)
  resetComponentsArray(self.btnRoomSelector, self.clearString)
  
  -- Initialize arrays
  for i, _ in ipairs(roomNames) do
    self.roomComponents[i] = nil
    self.audioRouters[i] = nil
    self.btnRoomSelector[i] = nil
  end
  
  return self
end

-----------------[ Debug & Error Reporting Helpers (DRY Utilities) ]----------------------
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

-- Generic batch result handler for bind operations
function DivisibleSpaceController:handleBatchResult(resultSuccess, operationType, index, itemName)
  if resultSuccess then
    self:debugPrint(operationType .. " handler set for " .. (itemName or ("index " .. index)))
    return true
  else
    self:debugPrint("WARNING: Failed to bind " .. operationType .. " handler for " .. (itemName or ("index " .. index)))
    return false
  end
end

------------------[ Component Utility Helpers ]---------------------
function DivisibleSpaceController:safeComponentAccess(component, control, action, value)
  if not component or not component[control] then return false end
  local success, result = pcall(function()
    if      action == "set"         then component[control].Boolean = value; return true
    elseif  action == "setPosition" then component[control].Position = value; return true
    elseif  action == "setString"   then component[control].String = value; return true
    elseif  action == "trigger"     then component[control]:Trigger(); return true
    elseif  action == "get"         then return component[control].Boolean
    elseif  action == "getPosition" then return component[control].Position
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
  
  -- Add delayed RoomSelector visibility update to ensure all components are settled
  self:scheduleDelayedRoomVisibilityUpdate()
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
 
  -- Load room control components
  forEach(controls.compRoomControls, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading room control " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "roomControls")
      if component then
        self:updateRoomComponent(control.String, i)
        self:debugPrint("Loaded room component " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
 
  -- Load audio router components
  forEach(controls.compAudioRouter, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading audio router " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "audioRouter")
      if component then
        self:updateAudioRouter(control.String, i)
        self:debugPrint("Loaded audio router " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
 
  -- Load RoomSelector buttons components
  forEach(controls.btnRoomSelector, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading RoomSelector buttons " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "btnRoomSelector")
      if component then
        self:updateBTNRoomSelector(control.String, i)
        self:debugPrint("Loaded RoomSelector buttons " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
 
  -- Load room combiner component
  if controls.compRoomCombiner.String and controls.compRoomCombiner.String ~= "" and controls.compRoomCombiner.String ~= self.clearString then
    self:debugPrint("Loading room combiner: " .. controls.compRoomCombiner.String)
    local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if component then
      self.components.roomCombiner = component
      self:debugPrint("Loaded room combiner (" .. controls.compRoomCombiner.String .. ")")
     
      -- Set up the configuration change handler
      local configControl = component["room.combiner.output.configuration"]
        if configControl then
          bind(configControl, function()
            self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting and applyGainRouting")
            self:applyAudioRouting()
            self:applyGainRouting()
            
            -- Update RoomSelector button visibility when room configuration changes
            if self.btnVisibilityModule then
              self:debugPrint("Updating RoomSelector button visibility due to configuration change")
              self.btnVisibilityModule:updateAllRoomButtonVisibility()
            end
          end)
       
        -- Apply initial routing
        self:debugPrint("Applying initial audio and gain routing")
        self:applyAudioRouting()
        self:applyGainRouting()
       
        -- Apply initial RoomSelector visibility
        if self.btnVisibilityModule then
          self:debugPrint("Applying initial RoomSelector button visibility")
          self.btnVisibilityModule:updateAllRoomButtonVisibility()
        end
      end
     
      -- Sync UI wall buttons with room combiner state
      if self.wallModule then self.wallModule:syncWallButtonStates() end
     
      -- Set up wall control event handlers for external changes
      if self.wallModule then self.wallModule:setupWallControlEventHandlers() end
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
  self:debugPrint("Discovering components using ComponentModule...")
 
  -- Use ComponentModule for discovery
  local namesTable = self.componentModule:discoverComponents()
 
  -- Populate control choices
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
  -- Early return for clear/invalid control reference
  if not ctrl then
    self:debugPrint("Control is nil for: " .. componentType)
    self:setComponentInvalid(componentType)
    return nil
  end
 
  local componentName = ctrl.String
 
  if componentName == "" then
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return nil
  elseif componentName == self.clearString then
    ctrl.String = ""
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return nil
  end
 
  -- Try to create the component
  local component = Component.New(componentName)
  if not component then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    self:debugPrint("Failed to create component: " .. componentName)
    return nil
  end
 
  -- Validate component has controls
  local componentControls = Component.GetControls(component)
  if not componentControls or #componentControls < 1 then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    self:debugPrint("Component has no controls: " .. componentName)
    return nil
  end
 
  -- Component is valid - set success state
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

------------------[ Event Handler Mapping/Registration ]----------------------
function DivisibleSpaceController:registerEventHandlers()
  -- Single control event mappings with direct object references
  local singleEventMap = {
    { ctrl = controls.compRoomCombiner, handler = function(ctl) 
      self:debugPrint("Room combiner control changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "roomCombiner")
      if component then
        self:debugPrint("Room combiner component successfully assigned: " .. component.Name)
        self.components.roomCombiner = component
        
        local configControl = component["room.combiner.output.configuration"]
        if configControl then
          bind(configControl, function()
            self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting and applyGainRouting")
            self:applyAudioRouting()
            self:applyGainRouting()
            
            if self.btnVisibilityModule then
              self:debugPrint("Updating RoomSelector button visibility due to configuration change")
              self.btnVisibilityModule:updateAllRoomButtonVisibility()
            end
          end)
          
          -- Apply initial routing
          self:debugPrint("Applying initial audio and gain routing")
          self:applyAudioRouting()
          self:applyGainRouting()
          
          -- Apply initial RoomSelector visibility
          if self.btnVisibilityModule then
            self:debugPrint("Applying initial RoomSelector button visibility")
            self.btnVisibilityModule:updateAllRoomButtonVisibility()
          end
        end
      end
    end },
    { ctrl = controls.selCombination, handler = function(ctl) 
      local comboIdx = self:getComboIndex(ctl.String)
      if comboIdx then
        self:setRoomStates(comboIdx)
      end
    end }
  }
  
  -- Batch register single controls
  for _, mapping in ipairs(singleEventMap) do
    bind(mapping.ctrl, mapping.handler)
  end
  
  -- Array control mappings with indexed handlers
  local arrayEventMap = {
    { ctrls = controls.compRoomControls, handler = function(i, ctl) 
      self:debugPrint("Room control " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "roomControls")
      if component then
        self:updateRoomComponent(ctl.String, i)
        self:debugPrint("Room component " .. i .. " (" .. ctl.String .. ") updated successfully")
      else
        self:updateRoomComponent("", i)
      end
      -- Refresh power handlers on change
      if self.powerSyncModule then self.powerSyncModule:setupRoomPowerEventHandlers() end
    end },
    { ctrls = controls.compAudioRouter, handler = function(i, ctl) 
      self:debugPrint("Audio router " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "audioRouter")
      if component then
        self:updateAudioRouter(ctl.String, i)
        self:debugPrint("Audio router " .. i .. " (" .. ctl.String .. ") updated successfully")
      else
        self:updateAudioRouter("", i)
      end
    end },
    { ctrls = controls.btnRoomSelector, handler = function(i, ctl) 
      self:debugPrint("RoomSelector buttons " .. i .. " changed to: " .. tostring(ctl.String))
      local component = self:setComponent(ctl, "btnRoomSelector")
      if component then
        self:updateBTNRoomSelector(ctl.String, i)
        self:debugPrint("RoomSelector buttons " .. i .. " (" .. ctl.String .. ") updated successfully")
      else
        self:updateBTNRoomSelector("", i)
      end
    end },
    { ctrls = controls.wallOpenButtons, handler = function(i, wallButton)
      local wallPair = wallRoomPairs[i]
      if wallPair then
        local uiState = wallButton.Boolean
        
        -- Handle individual room separation buttons (13-20)
        if i >= 13 and i <= 20 then
          -- For individual room separation, we need to close all walls that connect this room to others
          local targetRoom = wallPair[1] -- Single room in the pair for individual separation
          
          -- Safety check - don't allow separation if the target room is powered on
          local isTargetRoomOn = self:isRoomPoweredOn(targetRoom)
          if isTargetRoomOn then
            setProp(wallButton, "Boolean", not uiState)
            self:debugPrint("SAFETY BLOCK: Individual room separation " .. i .. " (" .. targetRoom .. ") blocked - room is powered ON")
            return
          end
          
          -- When separating a room (uiState = true), close all walls that connect this room to others
          if uiState == true then
            self:debugPrint("Individual room separation: Separating " .. targetRoom .. " from all others")
            
            -- Find and close all walls that connect this room to other rooms
            local wallsClosed = 0
            for wallIndex, otherWallPair in pairs(wallRoomPairs) do
              -- Skip individual separation buttons and check if this wall connects to our target room
              if wallIndex < 13 and tableContains(otherWallPair, targetRoom) then
                -- Check if any room in this wall pair (other than target) is powered on
                local hasOtherRoomOn = false
                for _, roomName in ipairs(otherWallPair) do
                  if roomName ~= targetRoom and self:isRoomPoweredOn(roomName) then
                    hasOtherRoomOn = true
                    break
                  end
                end
                
                -- Only close if no other rooms in this wall pair are powered on
                if not hasOtherRoomOn then
                  local otherWallButton = controls.wallOpenButtons[wallIndex]
                  if otherWallButton then
                    setProp(otherWallButton, "Boolean", false)
                    -- Also update the room combiner control
                    if self.components.roomCombiner then
                      local otherWallControlName = "wall." .. wallIndex .. ".open"
                      local otherWallControl = self.components.roomCombiner[otherWallControlName]
                      if otherWallControl then
                        setProp(otherWallControl, "Boolean", false)
                      end
                    end
                    wallsClosed = wallsClosed + 1
                    self:debugPrint("INDIVIDUAL SEPARATION: Wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ") closed to separate " .. targetRoom)
                  end
                else
                  self:debugPrint("INDIVIDUAL SEPARATION SKIP: Wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ") remains open (other rooms powered on)")
                end
              end
            end
            
            self:debugPrint("Individual room separation complete: " .. wallsClosed .. " walls closed to separate " .. targetRoom)
            
            -- Apply routing updates after separation
            self:applyAudioRouting()
            self:applyGainRouting()
            if self.btnVisibilityModule then
              self.btnVisibilityModule:updateAllRoomButtonVisibility()
            end
          end
          
          -- Update wall states and return (no room combiner wall control for individual separation)
          if self.wallModule then self.wallModule:updateWallStates() end
          return
        end
        
        -- Original logic for buttons 1-12 (multi-room walls)
        -- Safety check - don't allow wall operation if ANY room is powered on
        local anyRoomOn = false
        local roomStates = {}
        
        for _, roomName in ipairs(wallPair) do
          local isRoomOn = self:isRoomPoweredOn(roomName)
          table.insert(roomStates, roomName .. ":" .. (isRoomOn and "ON" or "OFF"))
          if isRoomOn then
            anyRoomOn = true
          end
        end
        
        if anyRoomOn then
          setProp(wallButton, "Boolean", not uiState)
          self:debugPrint("SAFETY BLOCK: Wall " .. i .. " (" .. table.concat(wallPair, "/") .. ") operation blocked - [" .. table.concat(roomStates, ", ") .. "]")
          return
        end
        
        -- Interlocking: When pressing to true (opening a wall), close all other walls
        -- that don't have rooms powered on (shouldDisable == false)
        if uiState == true then
          for wallIndex, otherWallPair in pairs(wallRoomPairs) do
            if wallIndex ~= i and wallIndex < 13 then -- Only affect buttons 1-12
              -- Check if other wall has any rooms powered on
              local otherShouldDisable = false
              for _, roomName in ipairs(otherWallPair) do
                if self:isRoomPoweredOn(roomName) then
                  otherShouldDisable = true
                  break
                end
              end
              
              -- Only set to false if no rooms are powered on (safe to separate)
              if not otherShouldDisable then
                local otherWallButton = controls.wallOpenButtons[wallIndex]
                if otherWallButton then
                  setProp(otherWallButton, "Boolean", false)
                  -- Also update the room combiner control
                  if self.components.roomCombiner then
                    local otherWallControlName = "wall." .. wallIndex .. ".open"
                    local otherWallControl = self.components.roomCombiner[otherWallControlName]
                    if otherWallControl then
                      setProp(otherWallControl, "Boolean", false)
                    end
                  end
                  self:debugPrint("INTERLOCK: Wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ") closed by interlock")
                end
              else
                self:debugPrint("INTERLOCK SKIP: Wall " .. wallIndex .. " (" .. table.concat(otherWallPair, "/") .. ") remains open (rooms powered on)")
              end
            end
          end
        end
        
        -- Update the actual wall control on compRoomCombiner (only for buttons 1-12)
        if self.components.roomCombiner then
          local wallControlName = "wall." .. i .. ".open"
          local wallControl = self.components.roomCombiner[wallControlName]
          if wallControl then
            setProp(wallControl, "Boolean", uiState)
            self:debugPrint("Wall " .. i .. " (" .. table.concat(wallPair, "/") .. ") control updated: " .. wallControlName .. " = " .. tostring(uiState) .. " (rooms " .. (uiState and "COMBINED" or "SEPARATED") .. ")")
            
            -- Auto-disable individual room separation buttons when room becomes part of a combination
            if uiState == true then -- Wall is being opened (rooms becoming combined)
              self:disableIndividualSeparationButtons(wallPair)
            end
            -- Note: When wall is closed (uiState = false), individual separation buttons remain in their current state
            -- They will be updated when the user explicitly presses them or when other combinations are made
          else
            self:debugPrint("ERROR: Wall control " .. wallControlName .. " not found on room combiner")
            setProp(wallButton, "Boolean", not uiState)
          end
        else
          self:debugPrint("ERROR: No room combiner component available")
          setProp(wallButton, "Boolean", not uiState)
        end
        
        -- Bidirectional interlock: Set corresponding individual separation buttons to false when specific walls trigger separation
        -- This provides consistent UX symmetry between combining and separating operations
        -- Multiple buttons can be affected by a single wall button press
        local interlockMap = {
          -- [wall_button_index] = {list of individual_separation_buttons_to_force_false}
          [1] = {13, 14},   -- Wall 1: SalonD/E → affects SalonD and SalonE separation buttons
          [6] = {15, 13},   -- Wall 6: SalonD/A/B/C → affects SalonA and SalonD separation buttons
          [7] = {14},       -- Wall 7: SalonE/F/G/H → affects SalonE separation button
          [8] = {15, 13, 14}, -- Wall 8: SalonD/E/A/B/C → affects all three separation buttons
          [9] = {13, 14},   -- Wall 9: SalonD/E/F/G/H → affects SalonD and SalonE separation buttons
          [10] = {15},      -- Wall 10: SalonA/B/C → affects SalonA separation button
          [12] = {15, 13, 14} -- Wall 12: All Combined → affects all three separation buttons
        }
        
        local targetButtons = interlockMap[i]
        if targetButtons then
          for _, targetButtonIndex in ipairs(targetButtons) do
            local targetWallButton = controls.wallOpenButtons[targetButtonIndex]
            if targetWallButton then
              setProp(targetWallButton, "Boolean", false)
              self:debugPrint("BIDIRECTIONAL INTERLOCK: Wall " .. i .. " pressed → Individual separation button " .. targetButtonIndex .. " set to false")
            end
          end
        end
      end
      if self.wallModule then self.wallModule:updateWallStates() end
    end }
  }
  
  -- Batch register array controls
  for _, mapping in ipairs(arrayEventMap) do
    bindArray(mapping.ctrls, mapping.handler)
  end
  
  self:debugPrint("Event handlers setup complete using batch registration")
end

-- Generic component update function (DRY refactor)
-- Consolidates updateRoomComponent, updateAudioRouter, updateBTNRoomSelector
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
    self:debugPrint(debugLabel .. " " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
    self:checkStatus()
  end
end

-- Convenience wrappers for backward compatibility and clarity
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
 
  -- Set wall states first
  if self.components.roomCombiner then
    for wallIndex, roomPair in pairs(wallRoomPairs) do
      if wallIndex <= 12 then -- Only process buttons 1-12 for room combiner walls
        local shouldOpen = self:shouldWallBeOpenForCombo(roomPair, combo)
        local wallControlName = "wall." .. wallIndex .. ".open"
        local wallControl = self.components.roomCombiner[wallControlName]
        if wallControl then
          setProp(wallControl, "Boolean", shouldOpen)
          self:debugPrint("Wall " .. wallIndex .. " (" .. roomPair[1] .. "/" .. roomPair[2] .. ") set to " .. (shouldOpen and "OPEN" or "CLOSED"))
        end
      end
    end
    
    -- Update UI wall buttons to match room combiner state
    if self.wallModule then
      self.wallModule:syncWallButtonStates()
    end
    
    -- Disable individual separation buttons for rooms that are part of this combination
    local combinedRooms = {}
    for roomName, isActive in pairs(combo.activeRooms) do
      if isActive then
        table.insert(combinedRooms, roomName)
      end
    end
    if #combinedRooms > 0 then
      self:disableIndividualSeparationButtons(combinedRooms)
    end
  else
    self:debugPrint("SKIP: Wall states - no room combiner component")
  end
 
  local roomStateErrors = {}
  local successfulRoomStates = 0
 
  -- Set room power states
  for i, roomName in ipairs(roomNames) do
    local comp = self.components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      local isActive = combo.activeRooms[roomName] or false
      setProp(comp["btnSystemOnOff"], "Boolean", isActive)
      successfulRoomStates = successfulRoomStates + 1
      self:debugPrint("Room " .. roomName .. " -> " .. (isActive and "ON" or "OFF"))
    else
      local errorMsg = roomName .. ": Component or btnSystemOnOff control not found"
      table.insert(roomStateErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
 
  self:printOperationResult("Room states", successfulRoomStates, #roomNames, roomStateErrors)
 
  -- Apply audio and gain routing
  self:applyAudioRouting()
  self:applyGainRouting()
 
  -- Update RoomSelector button visibility
  if self.btnVisibilityModule then
    self:debugPrint("Updating RoomSelector button visibility for combination...")
    self.btnVisibilityModule:updateAllRoomButtonVisibility()
  else
    self:debugPrint("SKIP: RoomSelector visibility - module not available")
  end
 
  self:checkStatus()
  if self.wallModule then self.wallModule:updateWallStates() end
  return true
end

function DivisibleSpaceController:applyAudioRouting()
  self:debugPrint("Starting audio routing application...")
 
  if not self.components.roomCombiner then
    self:debugPrint("ERROR: No room combiner component available")
    return
  end
 
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    self:debugPrint("ERROR: room.combiner.output.configuration control not found")
    return
  end
 
  local configString = configControl.String
  local roomGroups = parseConfiguration(configString)
  local currentCombination = self:getCurrentCombination()
 
  self:debugPrint("Audio routing config string: '" .. tostring(configString) .. "'")
  self:debugPrint("Parsed room groups count: " .. #roomGroups)
  for i, group in ipairs(roomGroups) do
    self:debugPrint("Group " .. i .. ": [" .. table.concat(group, ", ") .. "]")
  end
 
  -- Debug room number mapping
  self:debugPrint("Room number mapping:")
  for roomName, roomNum in pairs(roomNumberMap) do
    self:debugPrint(" " .. roomName .. " = " .. roomNum)
  end
 
  -- Debug current audio router assignments
  self:debugPrint("Current audio router assignments:")
  for i, roomName in ipairs(roomNames) do
    local routerName = self.audioRouters[i] or "NONE"
    self:debugPrint(" " .. i .. ". " .. roomName .. " -> " .. routerName)
  end
 
  local routingErrors = {}
  local successfulRoutings = 0

  -- Apply audio router inputs for each room
  for i, roomName in ipairs(roomNames) do
    local router = self.components.audioRouter[i]
    self:debugPrint("Processing room " .. i .. ": " .. roomName .. " (router: " .. (self.audioRouters[i] or "NONE") .. ")")
   
    if router and router["select.1"] then
      local inputNumber = self:getInputForRoom(roomName, roomGroups, currentCombination and currentCombination.priority)
      local currentValue = router["select.1"].Value
      self:debugPrint("Setting " .. roomName .. " -> Input " .. inputNumber .. " (was " .. currentValue .. ")")
     
      -- Validate input number is reasonable
      if inputNumber >= 1 and inputNumber <= 16 then
        setProp(router["select.1"], "Value", inputNumber)
        successfulRoutings = successfulRoutings + 1
        -- Verify the value was set
        local newValue = router["select.1"].Value
        self:debugPrint("SUCCESS: " .. roomName .. " routed to input " .. inputNumber .. " (verified: " .. newValue .. ")")
      else
        local errorMsg = roomName .. ": Invalid input number " .. inputNumber
        table.insert(routingErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      self:debugPrint("SKIP: " .. roomName .. " - no router or control")
    end
  end

  self:printOperationResult("Audio routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:applyGainRouting()
  self:debugPrint("Starting gain routing application...")
 
  if not self.components.roomCombiner then
    self:debugPrint("ERROR: No room combiner component available")
    return
  end
 
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    self:debugPrint("ERROR: room.combiner.output.configuration control not found")
    return
  end
 
  local configString = configControl.String
  local roomGroups = parseConfiguration(configString)
  local currentCombination = self:getCurrentCombination()
 
  self:debugPrint("Gain routing config string: '" .. tostring(configString) .. "'")
  self:debugPrint("Parsed room groups count: " .. #roomGroups)
  for i, group in ipairs(roomGroups) do
    self:debugPrint("Group " .. i .. ": [" .. table.concat(group, ", ") .. "]")
  end
 
  local routingErrors = {}
  local successfulRoutings = 0

  -- Apply gain control strings for each room
  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]
    self:debugPrint("Processing room " .. i .. ": " .. roomName .. " (room component: " .. (self.roomComponents[i] or "NONE") .. ")")
   
    if roomComp and roomComp["compGains 1"] then
      local gainControlName = self:getGainControlForRoom(roomName, roomGroups, currentCombination and currentCombination.priority)
      local currentValue = roomComp["compGains 1"].String or ""
      self:debugPrint("Setting " .. roomName .. " -> Gain Control: " .. gainControlName .. " (was " .. currentValue .. ")")
     
      -- Validate gain control name
      if gainControlName and gainControlName ~= "" then
        setProp(roomComp["compGains 1"], "String", gainControlName)
        successfulRoutings = successfulRoutings + 1
        -- Verify the value was set
        local newValue = roomComp["compGains 1"].String or ""
        self:debugPrint("SUCCESS: " .. roomName .. " gain routed to " .. gainControlName .. " (verified: " .. newValue .. ")")
      else
        local errorMsg = roomName .. ": Invalid gain control name " .. tostring(gainControlName)
        table.insert(routingErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      local errorMsg = roomName .. ": Component or compGains[1] control not found"
      table.insert(routingErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end

  self:printOperationResult("Gain routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:getGainControlForRoom(roomName, roomGroups, combinationPriority)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return gainControlNames[1] end
 
  self:debugPrint("getGainControlForRoom: " .. roomName .. " (room #" .. roomNumber .. "), groups count: " .. #roomGroups)
 
  -- If no groups (all separated), each room gets its own gain control
  if #roomGroups == 0 then
    local ownGainControl = gainControlNames[roomNumber]
    self:debugPrint(" No groups - returning room's own gain control: " .. ownGainControl)
    return ownGainControl
  end
 
  -- Check if room is in any group
  for groupIndex, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      -- Find the highest priority room in this group (lowest room number, or use combination priority if set and in group)
      local highestPriorityRoom = math.huge
      local priorityRoomNumber = combinationPriority and roomNumberMap[combinationPriority]
      if priorityRoomNumber and tableContains(group, priorityRoomNumber) then
        local priorityGainControl = gainControlNames[priorityRoomNumber]
        self:debugPrint(" Using combination priority room: " .. combinationPriority .. " (#" .. priorityRoomNumber .. ") -> " .. priorityGainControl)
        return priorityGainControl
      end
      for _, rn in ipairs(group) do
        if rn < highestPriorityRoom then
          highestPriorityRoom = rn
        end
      end
      local priorityGainControl = gainControlNames[highestPriorityRoom]
      self:debugPrint(" Room in group " .. groupIndex .. " - returning highest priority gain control: " .. priorityGainControl)
      return priorityGainControl
    end
  end
 
  -- If room not found in any group, it's separated and gets its own gain control
  local ownGainControl = gainControlNames[roomNumber]
  self:debugPrint(" Room not in any group - returning room's own gain control: " .. ownGainControl)
  return ownGainControl
end

function DivisibleSpaceController:getInputForRoom(roomName, roomGroups, combinationPriority)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return 1 end
 
  self:debugPrint("getInputForRoom: " .. roomName .. " (room #" .. roomNumber .. "), groups count: " .. #roomGroups)
 
  -- If no groups (all separated), each room gets its own input number
  if #roomGroups == 0 then
    self:debugPrint(" No groups - returning room's own number: " .. roomNumber)
    return roomNumber
  end
 
  -- Check if room is in any group
  for groupIndex, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      -- Find the highest priority room in this group (lowest room number, or use combination priority if set and in group)
      local highestPriorityRoom = math.huge
      local priorityRoomNumber = combinationPriority and roomNumberMap[combinationPriority]
      if priorityRoomNumber and tableContains(group, priorityRoomNumber) then
        self:debugPrint(" Using combination priority room: " .. combinationPriority .. " (#" .. priorityRoomNumber .. ")")
        return priorityRoomNumber
      end
      for _, numberedRoom in ipairs(group) do
        if numberedRoom < highestPriorityRoom then
          highestPriorityRoom = numberedRoom
        end
      end
      self:debugPrint(" Room in group " .. groupIndex .. " - returning highest priority: " .. highestPriorityRoom)
      return highestPriorityRoom
    end
  end
 
  -- If room not found in any group, it's separated and gets its own input
  self:debugPrint(" Room not in any group - returning room's own number: " .. roomNumber)
  return roomNumber
end

function DivisibleSpaceController:getCurrentCombination()
  if not self.components.roomCombiner then
    self:debugPrint("No room combiner component available")
    return nil
  end
 
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    self:debugPrint("No configuration control found on room combiner")
    return roomCombinations[13] -- Default to "All Separated"
  end
 
  local configString = configControl.String or ""
  return self:parseCombinationFromConfig(configString)
end

function DivisibleSpaceController:parseCombinationFromConfig(configString)
  self:debugPrint("Parsing combination from config: '" .. configString .. "'")
 
  -- Parse the configuration string to determine which rooms are grouped
  local roomGroups = parseConfiguration(configString)
 
  -- Match the room groups to our predefined combinations
  for _, combination in ipairs(roomCombinations) do
    if self:configMatchesCombination(roomGroups, combination) then
      self:debugPrint("Matched combination: " .. combination.name)
      return combination
    end
  end
 
  -- If no match found, default to "All Separated"
  self:debugPrint("No combination match found - defaulting to 'All Separated'")
  return roomCombinations[13]
end

function DivisibleSpaceController:configMatchesCombination(roomGroups, combination)
  -- Create a set of active rooms from the combination
  local activeRooms = {}
  for roomName, isActive in pairs(combination.activeRooms) do
    if isActive then
      local roomNumber = roomNumberMap[roomName]
      if roomNumber then
        activeRooms[roomNumber] = true
      end
    end
  end
 
  -- Check if the room groups match the active rooms
  if #roomGroups == 0 then
    -- No groups means all separated - check if combination is "All Separated"
    return combination.id == 13
  end
 
  -- For combinations with groups, check if the groups match
  local groupedRooms = {}
  for _, group in ipairs(roomGroups) do
    for _, roomNum in ipairs(group) do
      groupedRooms[roomNum] = true
    end
  end
 
  -- Compare grouped rooms with active rooms from combination
  for roomNum in pairs(activeRooms) do
    if not groupedRooms[roomNum] then
      return false
    end
  end
 
  for roomNum in pairs(groupedRooms) do
    if not activeRooms[roomNum] then
      return false
    end
  end
 
  return true
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

function DivisibleSpaceController:disableIndividualSeparationButtons(roomList)
  self:debugPrint("Auto-disabling individual separation buttons for rooms: " .. table.concat(roomList, ", "))
  
  local buttonsDisabled = 0
  local disableErrors = {}
  
  -- Map room names to their corresponding individual separation button indices
  local roomToButtonMap = {
    SalonD = 13, SalonE = 14, SalonA = 15, SalonB = 16,
    SalonC = 17, SalonF = 18, SalonG = 19, SalonH = 20
  }
  
  for _, roomName in ipairs(roomList) do
    local buttonIndex = roomToButtonMap[roomName]
    if buttonIndex then
      local individualButton = controls.wallOpenButtons[buttonIndex]
      if individualButton then
        local currentState = individualButton.Boolean
        if currentState == true then
          setProp(individualButton, "Boolean", false)
          buttonsDisabled = buttonsDisabled + 1
          self:debugPrint("AUTO-DISABLE: Individual separation button " .. buttonIndex .. " (" .. roomName .. ") set to false")
        else
          self:debugPrint("SKIP: Individual separation button " .. buttonIndex .. " (" .. roomName .. ") already false")
        end
      else
        local errorMsg = "Individual separation button " .. buttonIndex .. " (" .. roomName .. ") not found"
        table.insert(disableErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      local errorMsg = "No individual separation button mapping for room: " .. roomName
      table.insert(disableErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
  
  self:printOperationResult("Individual separation button auto-disable", buttonsDisabled, #roomList, disableErrors)
end

function DivisibleSpaceController:checkStatus()
  local invalidComponents = {}
  local validComponentCount = 0
  local totalComponentCount = 0
 
  -- Check for invalid components
  for componentType, isInvalid in pairs(self.components.invalid) do
    totalComponentCount = totalComponentCount + 1
    if isInvalid then
      table.insert(invalidComponents, componentType)
      self:debugPrint("INVALID component: " .. componentType)
    else
      validComponentCount = validComponentCount + 1
      self:debugPrint("Valid component: " .. componentType)
    end
  end
 
  -- Check room components
  local connectedRooms = 0
  for i = 1, #roomNames do
    if self.roomComponents[i] and self.roomComponents[i] ~= "" then
      connectedRooms = connectedRooms + 1
    end
  end
 
  -- Check audio routers
  local connectedRouters = 0
  for i = 1, #roomNames do
    if self.audioRouters[i] and self.audioRouters[i] ~= "" then
      connectedRouters = connectedRouters + 1
    end
  end
 
  -- Note: Gain components are now accessed through room components
 
  -- Check RoomSelector buttons
  local connectedRoomSelector = 0
  for i = 1, #roomNames do
    if self.btnRoomSelector[i] and self.btnRoomSelector[i] ~= "" then
      connectedRoomSelector = connectedRoomSelector + 1
    end
  end
 
  self:debugPrint("Status check: " .. validComponentCount .. "/" .. totalComponentCount .. " components valid")
  self:debugPrint("Connected room components: " .. connectedRooms .. "/" .. #roomNames)
  self:debugPrint("Connected audio routers: " .. connectedRouters .. "/" .. #roomNames)
  self:debugPrint("Connected RoomSelector buttons: " .. connectedRoomSelector .. "/" .. #roomNames)
 
  -- Update status control
  if controls.txtStatus then
    if #invalidComponents > 0 then
      controls.txtStatus.String = "Invalid: " .. table.concat(invalidComponents, ", ")
      controls.txtStatus.Value = 1
      self:debugPrint("STATUS: Invalid Components - " .. table.concat(invalidComponents, ", "))
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
      self:debugPrint("STATUS: " .. statusMsg)
    end
  end
end

function DivisibleSpaceController:scheduleDelayedRoomVisibilityUpdate()
  self:debugPrint("Scheduling delayed RoomSelector visibility update...")
 
  -- Create a timer to update RoomSelector visibility after a short delay
  local delayTimer = Timer.New()
  delayTimer.EventHandler = function()
    self:debugPrint("Executing delayed RoomSelector visibility update...")
   
    -- Stop the timer since it's a one-time update
    delayTimer:Stop()
   
    -- Update RoomSelector visibility based on current room combination
    if self.btnVisibilityModule then
      self:debugPrint("Delayed RoomSelector visibility update - checking current room combination...")
      local currentCombination = self:getCurrentCombination()
      if currentCombination then
        self:debugPrint("Delayed update using combination: " .. currentCombination.name)
      else
        self:debugPrint("No combination found in delayed update - setting all separate")
      end
      self.btnVisibilityModule:updateAllRoomButtonVisibility()
    else
      self:debugPrint("SKIP: Delayed RoomSelector visibility update - module not available")
    end
  end
 
  -- Start timer with 2 second delay to allow components to settle
  delayTimer:Start(2.0)
  self:debugPrint("Delayed RoomSelector visibility update scheduled for 2 seconds")
end

----------------[ Cleanup ]--------------------------
function DivisibleSpaceController:cleanup()
  -- Cleanup all modules
  local modules = {self.componentModule, self.btnVisibilityModule, self.powerSyncModule, self.wallModule}
  for _, module in ipairs(modules) do
    if module and module.cleanup then module:cleanup() end
  end
  
  self:debugPrint("Cleanup completed for " .. self.roomName)
end

------------------------[ Manual Test Functions ]------------------------
function manualTestAudioRouting()
  if myDivisibleController then
    myDivisibleController:debugPrint("Manual audio routing test triggered")
    myDivisibleController:applyAudioRouting()
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function debugCurrentRouterStates()
  if myDivisibleController then
    myDivisibleController:debugPrint("=== CURRENT ROUTER STATES DEBUG ===")
    for i, roomName in ipairs(roomNames) do
      local router = myDivisibleController.components.audioRouter[i]
      if router and router["select.1"] then
        local currentInput = router["select.1"].Value
        myDivisibleController:debugPrint(roomName .. " current input: " .. currentInput)
      else
        myDivisibleController:debugPrint(roomName .. " - NO ROUTER OR CONTROL")
      end
    end
    myDivisibleController:debugPrint("=== END ROUTER STATES DEBUG ===")
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function manualTestGainRouting()
  if myDivisibleController then
    myDivisibleController:debugPrint("Manual gain routing test triggered")
    myDivisibleController:applyGainRouting()
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function debugCurrentGainStates()
  if myDivisibleController then
    myDivisibleController:debugPrint("=== CURRENT GAIN STATES DEBUG ===")
    for i, roomName in ipairs(roomNames) do
      local roomComp = myDivisibleController.components.roomControls[i]
      if roomComp and roomComp["compGains 1"] then
        myDivisibleController:debugPrint(roomName .. " room component: " .. (myDivisibleController.roomComponents[i] or "NONE"))
        local currentGain = roomComp["compGains 1"].String or ""
        myDivisibleController:debugPrint(" current gain control: " .. currentGain)
      else
        myDivisibleController:debugPrint(roomName .. " - Component or compGains[1] control not found")
      end
    end
    myDivisibleController:debugPrint("=== END GAIN STATES DEBUG ===")
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

-- Enhanced factory function with comprehensive error handling
local function createDivisibleSpaceController(roomName, debugging)
  -- Input validation
  if not roomName or roomName == "" then
    print("ERROR: createDivisibleSpaceController requires a valid roomName")
    return nil
  end
  
  debugging = debugging ~= false -- Default to true
  
  -- Controller creation with detailed error context
  local success, controller = pcall(function()
    print("Initializing DivisibleSpaceController for " .. roomName .. " (debugging: " .. tostring(debugging) .. ")")
    -- Step 1: Validate controls
    if not validateControls() then
      error("Control validation failed - missing required controls")
    end
    -- Step 2: Normalize control arrays
    normalizeControlArrays()
    -- Step 3: Create controller object
    local object = DivisibleSpaceController.new(roomName, debugging)
    if not object then error("Controller constructor returned nil") end
    -- Step 4: Initialize the controller
    object:init()
    
    return object
  end)
  
  if success and controller then
    print("✓ DivisibleSpaceController successfully created for " .. roomName)
    -- Export globally for external access
    _G.DivisibleSpaceController = DivisibleSpaceController
    _G.myDivisibleController = controller
    return controller
  else
    local errorMsg = tostring(controller)
    print("✗ ERROR: DivisibleSpaceController creation failed")
    print("  Room: " .. roomName .. " (debugging: " .. tostring(debugging) .. ")")
    print("  Error: " .. errorMsg)
    -- Provide graceful degradation guidance
    if errorMsg:find("Control validation failed") then
      print("  Suggestion: Check that all required UI controls are properly named and connected")
    elseif errorMsg:find("Component") then
      print("  Suggestion: Verify Q-SYS component assignments and naming")
    else
      print("  Suggestion: Review script configuration and control mappings")
    end
    -- Graceful degradation - set status if available
    if controls and controls.txtStatus then
      controls.txtStatus.String = "INIT FAILED"
      controls.txtStatus.Value = 2 -- Error state
    end
    
    return nil
  end
end
------------------------[ Startup ]------------------------
local myDivisibleController = createDivisibleSpaceController("Raleigh Marriott Salon", true)