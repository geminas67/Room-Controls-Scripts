--[[
  Divisible Space Controller with Room Priority System
  Author: Nikolas Smith
  Date: 2025-09-24
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 2.3

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

-- Room number mapping for audio router and gain control logic
local roomNumberMap = {
  SalonD = 1, SalonE = 2, SalonA = 3, SalonB = 4,
  SalonC = 5, SalonF = 6, SalonG = 7, SalonH = 8
}

-- Gain control names mapping
local gainControlMap = {
  [1] = "lvlSalonD", [2] = "lvlSalonE", [3] = "lvlSalonA", [4] = "lvlSalonB",
  [5] = "lvlSalonC", [6] = "lvlSalonF", [7] = "lvlSalonG", [8] = "lvlSalonH"
}

local numberToRoomMap = {}
for name, num in pairs(roomNumberMap) do numberToRoomMap[num] = name end

local wallRoomPairs = {
  [1] = {"SalonD", "SalonE"}, [2] = {"SalonA", "SalonB"}, [3] = {"SalonB", "SalonC"},
  [4] = {"SalonF", "SalonG"}, [5] = {"SalonG", "SalonH"}, [6] = {"SalonD", "SalonA"},
  [7] = {"SalonD", "SalonB"}, [8] = {"SalonD", "SalonC"}, [9] = {"SalonE", "SalonF"},
  [10] = {"SalonE", "SalonG"}, [11] = {"SalonE", "SalonH"}
}

local roomCombinations = {
  { id=1, name="All Separated",                         activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority=nil },
  { id=2, name="SalonA+SalonB Combined",                activeRooms={SalonA=true, SalonB=true, SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=3, name="SalonB+SalonC Combined",                activeRooms={SalonA=false, SalonB=true, SalonC=true, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonB" },
  { id=4, name="SalonC+SalonD Combined",                activeRooms={SalonA=false, SalonB=false, SalonC=true, SalonD=true, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=5, name="SalonD+SalonE Combined",                activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=true, SalonE=true, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=6, name="SalonE+SalonF Combined",                activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=true, SalonF=true, SalonG=false, SalonH=false}, priority="SalonE" },
  { id=7, name="SalonF+SalonG Combined",                activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=true, SalonG=true, SalonH=false}, priority="SalonF" },
  { id=8, name="SalonG+SalonH Combined",                activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=true, SalonH=true}, priority="SalonG" },
  { id=9, name="SalonA+SalonB+SalonC+SalonD Combined",  activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=10,name="SalonE+SalonF+SalonG+SalonH Combined",  activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonE" },
  { id=11,name="All Combined",                          activeRooms={SalonA=true, SalonB=true, SalonC=true, SalonD=true, SalonE=true, SalonF=true, SalonG=true, SalonH=true}, priority="SalonA" }
}

-----------------------------[ Controls ]-----------------------------
local controls = {
  compRoomControls  = Controls.compRoomControls,
  compAudioRouter   = Controls.compAudioRouter,
  compRoomCombiner  = Controls.compRoomCombiner,
  txtStatus         = Controls.txtStatus,       
  selCombination    = Controls.selRoomCombination,
  wallOpenButtons   = Controls.wallOpenButtons,
  uciButtons        = Controls.uciButtons,
  compGains         = Controls.compGains
}

-----------------------------[ Utility Functions ]-----------------------------
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
  if not ctrl then return {} end
  return isArr(ctrl) and ctrl or {ctrl}
end

local function setProp(obj, prop, value)
  if not obj or not prop then return false end
  if obj[prop] == value then return false end -- Prevent redundant assignment
  obj[prop] = value
  return true
end

local function bind(control, handler)
  if not control or not handler then return false end
  control.EventHandler = handler
  return true
end

local function bindArray(controls, handler)
  if not controls or not handler then return false end
  local controlArray = getControlArray(controls)
  for i, control in ipairs(controlArray) do
    bind(control, function(ctl) handler(i, ctl) end)
  end
  return true
end

local function forEach(array, func)
  if not isArr(array) or not func then return end
  for i, item in ipairs(array) do
    func(i, item)
  end
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

-----------------------------[ Control Validation ]-----------------------------
local function validateControls()
  local required = {
    compRoomControls = controls.compRoomControls,
    compAudioRouter = controls.compAudioRouter,
    compRoomCombiner = controls.compRoomCombiner,
    txtStatus = controls.txtStatus,
    wallOpenButtons = controls.wallOpenButtons
  }
  
  local optional = {
    selCombination = controls.selCombination,
    uciButtons = controls.uciButtons,
    compGains = controls.compGains
  }
  
  local missingRequired = {}
  local missingOptional = {}
  
  for name, control in pairs(required) do
    if not control then 
      table.insert(missingRequired, name) 
    end
  end
  
  for name, control in pairs(optional) do
    if not control then 
      table.insert(missingOptional, name) 
    end
  end
  
  if #missingRequired > 0 then
    print("ERROR: DivisibleSpaceController missing required controls:")
    for _, name in ipairs(missingRequired) do
      print("  - " .. name)
    end
    print("Controller initialization aborted.")
    return false
  end
  
  if #missingOptional > 0 then
    print("WARNING: DivisibleSpaceController missing optional controls (reduced functionality):")
    for _, name in ipairs(missingOptional) do
      print("  - " .. name)
    end
  end
  
  return true
end

local function normalizeControlArrays()
  -- Ensure control arrays are properly structured
  local arrayControls = {
    'compRoomControls', 'compAudioRouter', 'wallOpenButtons', 'uciButtons', 'compGains'
  }
  
  for _, controlName in ipairs(arrayControls) do
    local ctrl = controls[controlName]
    if ctrl and not isArr(ctrl) then
      controls[controlName] = { ctrl }
    end
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

-----------------------------[ BaseModule Pattern ]-----------------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(name, controller)
  local self = setmetatable({}, BaseModule)
  self.name = name or "BaseModule"
  self.controller = controller
  self.debugging = controller and controller.debugging or false
  self:init()
  return self
end

function BaseModule:debugPrint(str)
  if self.debugging then
    local prefix = "[" .. (self.controller and self.controller.roomName or "System") .. "::" .. self.name .. "] "
    print(prefix .. str)
  end
end

function BaseModule:init()
  self:debugPrint("Initializing module")
end

function BaseModule:cleanup()
  self:debugPrint("Cleaning up module")
end

-----------------------------[ Component Management Module ]-----------------------------
local ComponentModule = setmetatable({}, {__index = BaseModule})
ComponentModule.__index = ComponentModule

function ComponentModule.new(controller)
  local self = BaseModule.new("ComponentModule", controller)
  setmetatable(self, ComponentModule)
  self.componentTypes = {
    roomCombiner = "room_combiner",
    roomControls = "device_controller_script",
    uciButtons = "custom_controls",
    audioRouter = "router_with_output",
    compGains = "gain"
  }
  return self
end

function ComponentModule:discoverComponents()
  local namesTable = {
    RoomControlsNames = {},
    AudioRouterNames = {},
    RoomCombinerNames = {},
    UciButtonsNames = {},
    GainNames = {}
  }

  for _, component in ipairs(Component.GetComponents()) do
    if component.Type == self.componentTypes.roomControls and string.match(component.Name, "^compRoomControls") then
      table.insert(namesTable.RoomControlsNames, component.Name)
    elseif component.Type == self.componentTypes.audioRouter then
      table.insert(namesTable.AudioRouterNames, component.Name)
    elseif component.Type == self.componentTypes.roomCombiner then
      table.insert(namesTable.RoomCombinerNames, component.Name)
    elseif component.Type == self.componentTypes.uciButtons then
      table.insert(namesTable.UciButtonsNames, component.Name)
    elseif component.Type == self.componentTypes.compGains then
      table.insert(namesTable.GainNames, component.Name)
    end
  end

  for _, nameList in pairs(namesTable) do
    table.sort(nameList)
    table.insert(nameList, self.controller.clearString)
  end

  return namesTable
end

-----------------------------[ UCI Visibility Module ]-----------------------------
local UCIVisibilityModule = setmetatable({}, {__index = BaseModule})
UCIVisibilityModule.__index = UCIVisibilityModule

function UCIVisibilityModule.new(controller)
  local self = BaseModule.new("UCIVisibilityModule", controller)
  setmetatable(self, UCIVisibilityModule)
  return self
end

function UCIVisibilityModule:updateAllUCIButtonVisibility()
  self:debugPrint("Updating UCI button visibility for all rooms...")
  
  if not controls.uciButtons or #controls.uciButtons == 0 then
      self:debugPrint("No UCI buttons found - skipping visibility update")
      return
  end
  
  -- Get parsed room groups from current config
  local configString = self:getConfigString()
  local roomGroups = parseConfiguration(configString)
  
  if #roomGroups == 0 then
      self:debugPrint("No groups found - setting all separate")
      self:setAllRoomsSeparate()
      return
  end
  
  self:debugPrint("Applying UCI visibility based on " .. #roomGroups .. " groups")
  
  -- Update each room's UCI buttons based on groups
  for i, roomName in ipairs(roomNames) do
      self:updateRoomUCIVisibility(i, roomName, roomGroups)
  end
  
  self:debugPrint("UCI button visibility update complete")
end

function UCIVisibilityModule:updateRoomUCIVisibility(roomIndex, roomName, roomGroups)
  local uciName = self.controller.uciButtons[roomIndex]
  if not uciName or uciName == "" then
      self:debugPrint("No UCI component name for room " .. roomIndex .. " (" .. roomName .. ")")
      return
  end
  
  local uciComponent = Component.New(uciName)
  if not uciComponent then
      self:debugPrint("Failed to create UCI component for " .. roomName .. " (" .. uciName .. ")")
      return
  end
  
  self:debugPrint("Updating UCI states for room " .. roomIndex .. " (" .. roomName .. ")")
  
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
      self:debugPrint("  No group for " .. roomName .. " - setting as separate")
      for toggleIndex = 1, 8 do
          local toggleControlName = "toggle." .. toggleIndex
          if uciComponent[toggleControlName] then
              uciComponent[toggleControlName].Boolean = (toggleIndex == roomIndex)
              self:debugPrint("  " .. roomName .. " -> " .. toggleControlName .. ".Boolean = " .. tostring(toggleIndex == roomIndex) .. " (" .. roomNames[toggleIndex] .. ")")
          else
              self:debugPrint("  WARNING: " .. toggleControlName .. " control not found on UCI component for " .. roomName)
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
      if uciComponent[toggleControlName] then
          uciComponent[toggleControlName].Boolean = isInGroup
          self:debugPrint("  " .. roomName .. " -> " .. toggleControlName .. ".Boolean = " .. tostring(isInGroup) .. " (" .. targetRoomName .. ")")
      else
          self:debugPrint("  WARNING: " .. toggleControlName .. " control not found on UCI component for " .. roomName)
      end
  end
end

function UCIVisibilityModule:getConfigString()
  if not self.controller.components.roomCombiner then return "" end
  local configControl = self.controller.components.roomCombiner["room.combiner.output.configuration"]
  return configControl and configControl.String or ""
end

function UCIVisibilityModule:shouldToggleBeVisible(sourceRoomName, targetRoomName, combination)
  if sourceRoomName == targetRoomName then
    return true
  end
  
  local sourceActive = combination.activeRooms[sourceRoomName] or false
  local targetActive = combination.activeRooms[targetRoomName] or false
  return sourceActive and targetActive
end

function UCIVisibilityModule:setAllRoomsSeparate()
  self:debugPrint("Setting all rooms to separated state (own toggle only)")
  
  for i, roomName in ipairs(roomNames) do
    local uciName = self.controller.uciButtons[i]
    if uciName and uciName ~= "" then
      local uciComponent = Component.New(uciName)
      if uciComponent then
        for toggleIndex = 1, 8 do
          local toggleControlName = "toggle." .. toggleIndex
          if uciComponent[toggleControlName] then
            uciComponent[toggleControlName].Boolean = (toggleIndex == i)
            self:debugPrint("Set " .. roomName .. " UCI to separated state: " .. toggleControlName .. ".Boolean = " .. tostring(toggleIndex == i))
          end
        end
        self:debugPrint("Set " .. roomName .. " UCI to separated state")
      end
    end
  end
end

-----------------------------[ Gain Control Module ]-----------------------------
local GainControlModule = setmetatable({}, {__index = BaseModule})
GainControlModule.__index = GainControlModule

function GainControlModule.new(controller)
  local self = BaseModule.new("GainControlModule", controller)
  setmetatable(self, GainControlModule)
  return self
end

function GainControlModule:updateAllGainControls()
  self:debugPrint("Updating gain controls for all rooms...")
  
  if not controls.compGains or #controls.compGains == 0 then
    self:debugPrint("No gain controls found - skipping update")
    return
  end
  
  -- Get parsed room groups from current config
  local configString = self:getConfigString()
  local roomGroups = parseConfiguration(configString)
  
  if #roomGroups == 0 then
    self:debugPrint("No groups found - setting all gains to separate")
    self:setAllGainsSeparate()
    return
  end
  
  self:debugPrint("Applying gain controls based on " .. #roomGroups .. " groups")
  
  -- Update each room's gain control based on groups
  for i, roomName in ipairs(roomNames) do
    self:updateRoomGainControl(i, roomName, roomGroups)
  end
  
  self:debugPrint("Gain control update complete")
end

function GainControlModule:updateRoomGainControl(roomIndex, roomName, roomGroups)
  local gainControl = controls.compGains[roomIndex]
  if not gainControl then
    self:debugPrint("No gain control for room " .. roomIndex .. " (" .. roomName .. ")")
    return
  end
  
  self:debugPrint("Updating gain control for room " .. roomIndex .. " (" .. roomName .. ")")
  
  -- Find the group containing this room
  local sourceRoomNum = roomNumberMap[roomName]
  local sourceGroup = nil
  for _, group in ipairs(roomGroups) do
    if tableContains(group, sourceRoomNum) then
      sourceGroup = group
      break
    end
  end
  
  -- Get the current combination for priority
  local currentCombination = self.controller:getCurrentCombination()
  local priorityRoomNum = currentCombination and currentCombination.priority and roomNumberMap[currentCombination.priority]
  
  -- If no group found, set to own gain control
  if not sourceGroup then
    self:debugPrint("  No group for " .. roomName .. " - setting to own gain control")
    setProp(gainControl, "String", gainControlMap[roomIndex])
    self:debugPrint("  " .. roomName .. " -> compGains[" .. roomIndex .. "].String = " .. gainControlMap[roomIndex])
    return
  end
  
  -- Find the highest priority room in the group
  local highestPriorityRoom = math.huge
  if priorityRoomNum and tableContains(sourceGroup, priorityRoomNum) then
    highestPriorityRoom = priorityRoomNum
    self:debugPrint("  Using combination priority room: " .. currentCombination.priority .. " (#" .. priorityRoomNum .. ")")
  else
    for _, rn in ipairs(sourceGroup) do
      if rn < highestPriorityRoom then
        highestPriorityRoom = rn
      end
    end
    self:debugPrint("  Using lowest room number in group: " .. highestPriorityRoom)
  end
  
  -- Set the gain control to the priority room's gain
  local gainControlName = gainControlMap[highestPriorityRoom]
  setProp(gainControl, "String", gainControlName)
  self:debugPrint("  " .. roomName .. " -> compGains[" .. roomIndex .. "].String = " .. gainControlName .. " (priority room: " .. numberToRoomMap[highestPriorityRoom] .. ")")
end

function GainControlModule:setAllGainsSeparate()
  self:debugPrint("Setting all gain controls to separated state")
  
  for i, roomName in ipairs(roomNames) do
    local gainControl = controls.compGains[i]
    if gainControl then
      setProp(gainControl, "String", gainControlMap[i])
      self:debugPrint("Set " .. roomName .. " gain to " .. gainControlMap[i])
    else
      self:debugPrint("WARNING: No gain control for " .. roomName)
    end
  end
end

function GainControlModule:getConfigString()
  if not self.controller.components.roomCombiner then return "" end
  local configControl = self.controller.components.roomCombiner["room.combiner.output.configuration"]
  return configControl and configControl.String or ""
end

-----------------------------[ Power Synchronization Module ]-----------------------------
local PowerSyncModule = setmetatable({}, {__index = BaseModule})
PowerSyncModule.__index = PowerSyncModule

function PowerSyncModule.new(controller)
  local self = BaseModule.new("PowerSyncModule", controller)
  setmetatable(self, PowerSyncModule)
  self.syncInProgress = false
  return self
end

function PowerSyncModule:setupRoomPowerEventHandlers()
  self:debugPrint("Setting up room power state event handlers...")
  
  local handlersSetup = 0
  
  for i, roomName in ipairs(roomNames) do
    local comp = self.controller.components.roomControls[i]
    if comp and comp["btnSystemOnOff"] then
      bind(comp["btnSystemOnOff"], function()
        self:onRoomPowerChanged(roomName, i)
      end)
      handlersSetup = handlersSetup + 1
      self:debugPrint("Power event handler set for " .. roomName .. " (" .. (self.controller.roomComponents[i] or "N/A") .. ")")
    else
      self:debugPrint("WARNING: Could not set power handler for " .. roomName .. " - component or control not found")
    end
  end
  
  self:debugPrint("Room power event handlers setup: " .. handlersSetup .. "/" .. #roomNames .. " successful")
end

function PowerSyncModule:onRoomPowerChanged(roomName, roomIndex)
  if self.syncInProgress then
    self:debugPrint("Sync already in progress - ignoring power change for " .. roomName)
    return
  end
  
  self:debugPrint("Power state changed for " .. roomName .. " - checking for combined rooms...")
  
  local configString = self:getConfigString()
  if not configString then return end
  
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
    self:debugPrint(roomName .. " is not in a combined group - no sync needed")
    return
  end
  
  local newPowerState = self.controller:isRoomPoweredOn(roomName)
  self:debugPrint(roomName .. " new power state: " .. (newPowerState and "ON" or "OFF"))
  
  if not newPowerState then
    self:debugPrint("Room " .. roomName .. " powered OFF - checking if all combined rooms in group are now off...")
    if self:shouldAutoSeparateGroup(group) then
      self:debugPrint("All rooms in group are OFF - automatically separating group")
      self:separateGroup(group)
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
    self:debugPrint("No other rooms to sync with " .. roomName)
    return
  end
  
  self:debugPrint("Synchronizing power state (" .. (newPowerState and "ON" or "OFF") .. ") to combined rooms in group: " .. table.concat(roomsToSync, ", "))
  
  self:syncPowerToRooms(roomsToSync, newPowerState)
end

function PowerSyncModule:getConfigString()
  if not self.controller.components.roomCombiner then
    self:debugPrint("No room combiner component available")
    return nil
  end
  
  local configControl = self.controller.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then
    self:debugPrint("No configuration control found on room combiner")
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
          self:debugPrint("SYNCED: " .. roomName .. " -> " .. (powerState and "ON" or "OFF"))
        else
          self:debugPrint("SKIP: " .. roomName .. " already " .. (powerState and "ON" or "OFF"))
        end
      else
        local errorMsg = roomName .. ": Component or btnSystemOnOff control not found"
        table.insert(syncErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      local errorMsg = roomName .. ": Room index not found"
      table.insert(syncErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
  
  self:debugPrint("Power sync complete: " .. syncedRooms .. "/" .. #roomsToSync .. " rooms synchronized")
  if #syncErrors > 0 then
    self:debugPrint("Power sync errors: " .. #syncErrors)
    for _, error in ipairs(syncErrors) do
      self:debugPrint("  - " .. error)
    end
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
      self:debugPrint("Checking " .. roomName .. " power state: " .. (roomPowerState and "ON" or "OFF"))
      
      if roomPowerState then
        allRoomsOff = false
        self:debugPrint("Found " .. roomName .. " still powered ON - separation not needed")
        break
      end
    end
  end
  
  self:debugPrint("Auto-separation check for group: " .. groupSize .. " rooms, all off: " .. tostring(allRoomsOff))
  return allRoomsOff
end

function PowerSyncModule:separateGroup(group)
  self:debugPrint("Executing automatic group separation...")
  
  if not self.controller.components.roomCombiner then
    self:debugPrint("ERROR: No room combiner component available for separation")
    return false
  end
  
  local groupRooms = {}
  for _, num in ipairs(group) do
    local name = numberToRoomMap[num]
    if name then groupRooms[name] = true end
  end
  
  local wallsClosed = 0
  local wallErrors = {}
  
  for wallIndex = 1, 11 do
    local wallPair = wallRoomPairs[wallIndex]
    if wallPair and groupRooms[wallPair[1]] and groupRooms[wallPair[2]] then
      local wallControlName = "wall." .. wallIndex .. ".open"
      local wallControl = self.controller.components.roomCombiner[wallControlName]
      
      if wallControl then
        local currentState = wallControl.Boolean
        if currentState then
          setProp(wallControl, "Boolean", false)
          wallsClosed = wallsClosed + 1
          self:debugPrint("SEPARATED: Wall " .. wallIndex .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. ") - wall closed")
        end
      else
        local errorMsg = "Wall " .. wallIndex .. ": " .. wallControlName .. " control not found"
        table.insert(wallErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    end
  end
  
  self:debugPrint("Automatic group separation complete: " .. wallsClosed .. " walls closed")
  if #wallErrors > 0 then
    self:debugPrint("Separation errors: " .. #wallErrors)
    for _, error in ipairs(wallErrors) do
      self:debugPrint("  - " .. error)
    end
  end
  
  if self.controller.wallModule then 
    self.controller.wallModule:syncWallButtonStates() 
  end
  
  self.controller:applyAudioRouting()
  if self.controller.uciVisibilityModule then
    self.controller.uciVisibilityModule:updateAllUCIButtonVisibility()
  end
  if self.controller.gainControlModule then
    self.controller.gainControlModule:updateAllGainControls()
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

-----------------------------[ Wall Module ]-----------------------------
local WallModule = setmetatable({}, {__index = BaseModule})
WallModule.__index = WallModule

function WallModule.new(controller)
  local self = BaseModule.new("WallModule", controller)
  setmetatable(self, WallModule)
  return self
end

function WallModule:syncWallButtonStates()
  self:debugPrint("Syncing UI wall buttons with room combiner wall states...")
  
  if not self.controller.components.roomCombiner then
    self:debugPrint("No room combiner available for wall sync")
    return
  end
  
  local syncedWalls = 0
  local syncErrors = {}
  
  for i = 1, 11 do
    local wallButton = controls.wallOpenButtons[i]
    if wallButton then
      local wallControlName = "wall." .. i .. ".open"
      local wallControl = self.controller.components.roomCombiner[wallControlName]
      
      if wallControl then
        local combinerState = wallControl.Boolean
        setProp(wallButton, "Boolean", combinerState)
        syncedWalls = syncedWalls + 1
        
        local wallPair = wallRoomPairs[i]
        if wallPair then
          self:debugPrint("Synced wall " .. i .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. "): " .. 
                          wallControlName .. " = " .. tostring(combinerState) .. " (rooms " .. 
                          (combinerState and "COMBINED" or "SEPARATED") .. ")")
        end
      else
        local errorMsg = "Wall " .. i .. ": " .. wallControlName .. " control not found on room combiner"
        table.insert(syncErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      local errorMsg = "Wall " .. i .. ": UI button not found"
      table.insert(syncErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
  
  self:debugPrint("Wall button sync complete: " .. syncedWalls .. "/11 successful")
  if #syncErrors > 0 then
    self:debugPrint("Wall sync errors: " .. #syncErrors)
    for _, error in ipairs(syncErrors) do
      self:debugPrint("  - " .. error)
    end
  end
end

function WallModule:setupWallControlEventHandlers()
  self:debugPrint("Setting up room combiner wall control event handlers...")
  
  if not self.controller.components.roomCombiner then
    self:debugPrint("No room combiner available for wall event handlers")
    return
  end
  
  local handlersSetup = 0
  
  for i = 1, 11 do
    local wallControlName = "wall." .. i .. ".open"
    local wallControl = self.controller.components.roomCombiner[wallControlName]
    
    if wallControl then
      bind(wallControl, function()
        local combinerState = wallControl.Boolean
        local wallButton = controls.wallOpenButtons[i]
        
        if wallButton then
          setProp(wallButton, "Boolean", combinerState)
          
          local wallPair = wallRoomPairs[i]
          if wallPair then
            self:debugPrint("External wall change detected - Wall " .. i .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. "): " .. 
                            wallControlName .. " = " .. tostring(combinerState) .. " (rooms " .. 
                            (combinerState and "COMBINED" or "SEPARATED") .. ")")
          end
          
          self:updateWallStates()
        end
      end)
      handlersSetup = handlersSetup + 1
    end
  end
  
  self:debugPrint("Wall control event handlers setup: " .. handlersSetup .. "/11 successful")
end

function WallModule:updateWallStates()
  self:debugPrint("Updating wall states...")
  
  local wallStatesUpdated = 0
  local wallStateErrors = {}
  
  for wallIndex, roomPair in pairs(wallRoomPairs) do
    local room01 = roomPair[1]
    local room02 = roomPair[2]
    local isRoom01On = self.controller:isRoomPoweredOn(room01)
    local isRoom02On = self.controller:isRoomPoweredOn(room02)
    local wallButton = controls.wallOpenButtons[wallIndex]
    
    if wallButton then
      local shouldDisable = (isRoom01On or isRoom02On)
      setProp(wallButton, "IsDisabled", shouldDisable)
      wallStatesUpdated = wallStatesUpdated + 1
      
      self:debugPrint("Wall " .. wallIndex .. " (" .. room01 .. "/" .. room02 .. "): " .. 
                      (shouldDisable and "DISABLED" or "ENABLED") .. 
                      " [" .. room01 .. ":" .. (isRoom01On and "ON" or "OFF") .. 
                      ", " .. room02 .. ":" .. (isRoom02On and "ON" or "OFF") .. "]")
    else
      local errorMsg = "Wall " .. wallIndex .. ": Button control not found"
      table.insert(wallStateErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
  
  self:debugPrint("Wall states updated: " .. wallStatesUpdated .. "/" .. #wallRoomPairs .. " successful")
  if #wallStateErrors > 0 then
    self:debugPrint("Wall state errors: " .. #wallStateErrors)
    for _, error in ipairs(wallStateErrors) do
      self:debugPrint("  - " .. error)
    end
  end
end

-----------------------------[ Main Controller ]-----------------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debugging)
  if not validateControls() then
    return nil
  end
  
  normalizeControlArrays()
  
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Divisible Space"
  self.debugging = debugging or false
  self.clearString = "[Clear]"
  
  self.componentModule = ComponentModule.new(self)
  self.uciVisibilityModule = UCIVisibilityModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  self.gainControlModule = GainControlModule.new(self)
  
  self.components = {
    roomCombiner = nil,
    roomControls = {},
    audioRouter = {},
    uciButtons = {},
    invalid = {roomCombiner = false, roomControls = false, audioRouter = false, uciButtons = false, compGains = false}
  }
  
  self.roomComponents = {}
  self.audioRouters = {}
  self.uciButtons = {}
  
  resetComponentsArray(self.roomComponents, self.clearString)
  resetComponentsArray(self.audioRouters, self.clearString)
  resetComponentsArray(self.uciButtons, self.clearString)
  
  for i, _ in ipairs(roomNames) do
    self.roomComponents[i] = nil
    self.audioRouters[i] = nil
    self.uciButtons[i] = nil
  end
  
  self:init()
  return self
end

function DivisibleSpaceController:debugPrint(str)
  if self.debugging then 
    print("[" .. (self.roomName or "DivisibleSpace") .. "] " .. str) 
  end
end

function DivisibleSpaceController:init()
  self:debugPrint("Starting initialization...")
  self:discoverComponents()
  self:setupCombinationSelector()
  self:wireEventHandlers()
  self:loadInitialComponents()
  self:checkStatus()
  if self.wallModule then self.wallModule:updateWallStates() end
  self:debugPrint("Initialization complete")
  
  self:scheduleDelayedUCIVisibilityUpdate()
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
        self:debugPrint("Loaded room component " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
  
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
  
  forEach(controls.uciButtons, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading UCI buttons " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "uciButtons")
      if component then
        self:updateUCIButtons(control.String, i)
        self:debugPrint("Loaded UCI buttons " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
  
  forEach(controls.compGains, function(i, control)
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading gain control " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "compGains")
      if component then
        self:debugPrint("Loaded gain control " .. i .. " (" .. control.String .. ")")
      end
    end
  end)
  
  if controls.compRoomCombiner.String and controls.compRoomCombiner.String ~= "" and controls.compRoomCombiner.String ~= self.clearString then
    self:debugPrint("Loading room combiner: " .. controls.compRoomCombiner.String)
    local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if component then
      self:debugPrint("Loaded room combiner (" .. controls.compRoomCombiner.String .. ")")
      self.components.roomCombiner = component
      
      local configControl = component["room.combiner.output.configuration"]
      if configControl then
        bind(configControl, function()
          self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting")
          self:applyAudioRouting()
          
          if self.uciVisibilityModule then
            self:debugPrint("Updating UCI button visibility due to configuration change")
            self.uciVisibilityModule:updateAllUCIButtonVisibility()
          end
          if self.gainControlModule then
            self:debugPrint("Updating gain controls due to configuration change")
            self.gainControlModule:updateAllGainControls()
          end
        end)
        
        self:debugPrint("Applying initial audio routing")
        self:applyAudioRouting()
        
        if self.uciVisibilityModule then
          self:debugPrint("Applying initial UCI button visibility")
          self.uciVisibilityModule:updateAllUCIButtonVisibility()
        end
        if self.gainControlModule then
          self:debugPrint("Applying initial gain controls")
          self.gainControlModule:updateAllGainControls()
        end
      end
      
      if self.wallModule then self.wallModule:syncWallButtonStates() end
      if self.wallModule then self.wallModule:setupWallControlEventHandlers() end
    end
  end
  
  self:debugPrint("Initial component loading complete")
  
  if self.powerSyncModule then
    self:debugPrint("Setting up power synchronization event handlers...")
    self.powerSyncModule:setupRoomPowerEventHandlers()
  end
end

function DivisibleSpaceController:discoverComponents()
  self:debugPrint("Discovering components using ComponentModule...")
  
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

  forEach(controls.uciButtons, function(_, control)
    if control then control.Choices = namesTable.UciButtonsNames end
  end)

  forEach(controls.compGains, function(_, control)
    if control then control.Choices = namesTable.GainNames end
  end)
  
  self:debugPrint("Component discovery complete")
end

function DivisibleSpaceController:setComponent(ctrl, componentType)
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
  
  local component = Component.New(componentName)
  if not component then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    self:debugPrint("Failed to create component: " .. componentName)
    return nil
  end
  
  local componentControls = Component.GetControls(component)
  if not componentControls or #componentControls < 1 then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    self:debugPrint("Component has no controls: " .. componentName)
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

function DivisibleSpaceController:wireEventHandlers()
  self:debugPrint("Setting up event handlers using batch registration...")
  
  local handlerMaps = {
    roomControls = {
      controls = getControlArray(controls.compRoomControls),
      handler = function(control, index)
        return function()
          self:debugPrint("Room control " .. index .. " changed to: " .. tostring(control.String))
          local component = self:setComponent(control, "roomControls")
          if component then
            self:updateRoomComponent(control.String, index)
            self:debugPrint("Room component " .. index .. " (" .. control.String .. ") updated successfully")
          else
            self:updateRoomComponent("", index)
          end
          if self.powerSyncModule then self.powerSyncModule:setupRoomPowerEventHandlers() end
        end
      end
    },
    
    audioRouters = {
      controls = getControlArray(controls.compAudioRouter),
      handler = function(control, index)
        return function()
          self:debugPrint("Audio router " .. index .. " changed to: " .. tostring(control.String))
          local component = self:setComponent(control, "audioRouter")
          if component then
            self:updateAudioRouter(control.String, index)
            self:debugPrint("Audio router " .. index .. " (" .. control.String .. ") updated successfully")
          else
            self:updateAudioRouter("", index)
          end
        end
      end
    },
    
    uciButtons = {
      controls = getControlArray(controls.uciButtons),
      handler = function(control, index)
        return function()
          self:debugPrint("UCI buttons " .. index .. " changed to: " .. tostring(control.String))
          local component = self:setComponent(control, "uciButtons")
          if component then
            self:updateUCIButtons(control.String, index)
            self:debugPrint("UCI buttons " .. index .. " (" .. control.String .. ") updated successfully")
          else
            self:updateUCIButtons("", index)
          end
        end
      end
    },
    
    gainControls = {
      controls = getControlArray(controls.compGains),
      handler = function(control, index)
        return function()
          self:debugPrint("Gain control " .. index .. " changed to: " .. tostring(control.String))
          local component = self:setComponent(control, "compGains")
          if component then
            self:debugPrint("Gain control " .. index .. " (" .. control.String .. ") updated successfully")
          end
        end
      end
    },
    
    wallButtons = {
      controls = getControlArray(controls.wallOpenButtons),
      handler = function(wallButton, index)
        return function()
          local wallPair = wallRoomPairs[index]
          if wallPair then
            local room1, room2 = wallPair[1], wallPair[2]
            local uiState = wallButton.Boolean
            
            local room1On = self:isRoomPoweredOn(room1)
            local room2On = self:isRoomPoweredOn(room2)
            
            if room1On or room2On then
              setProp(wallButton, "Boolean", not uiState)
              self:debugPrint("SAFETY BLOCK: Wall " .. index .. " (" .. room1 .. "/" .. room2 .. ") operation blocked - " .. room1 .. ":" .. (room1On and "ON" or "OFF") .. ", " .. room2 .. ":" .. (room2On and "ON" or "OFF"))
              return
            end
            
            if self.components.roomCombiner then
              local wallControlName = "wall." .. index .. ".open"
              local wallControl = self.components.roomCombiner[wallControlName]
              if wallControl then
                setProp(wallControl, "Boolean", uiState)
                self:debugPrint("Wall " .. index .. " (" .. room1 .. "/" .. room2 .. ") control updated: " .. wallControlName .. " = " .. tostring(uiState) .. " (rooms " .. (uiState and "COMBINED" or "SEPARATED") .. ")")
              else
                self:debugPrint("ERROR: Wall control " .. wallControlName .. " not found on room combiner")
                setProp(wallButton, "Boolean", not uiState)
              end
            else
              self:debugPrint("ERROR: No room combiner component available")
              setProp(wallButton, "Boolean", not uiState)
            end
          end
          if self.wallModule then self.wallModule:updateWallStates() end
        end
      end
    }
  }
  
  for mapName, map in pairs(handlerMaps) do
    forEach(map.controls, function(index, control)
      if control then
        bind(control, map.handler(control, index))
        self:debugPrint("Handler registered: " .. mapName .. "[" .. index .. "]")
      end
    end)
  end
  
  if controls.compRoomCombiner then
    bind(controls.compRoomCombiner, function()
      self:debugPrint("Room combiner control changed to: " .. tostring(controls.compRoomCombiner.String))
      local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
      if component then
        self:debugPrint("Room combiner component successfully assigned: " .. component.Name)
        self.components.roomCombiner = component
        
        local configControl = component["room.combiner.output.configuration"]
        if configControl then
          bind(configControl, function()
            self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting")
            self:applyAudioRouting()
            
            if self.uciVisibilityModule then
              self:debugPrint("Updating UCI button visibility due to configuration change")
              self.uciVisibilityModule:updateAllUCIButtonVisibility()
            end
            if self.gainControlModule then
              self:debugPrint("Updating gain controls due to configuration change")
              self.gainControlModule:updateAllGainControls()
            end
          end)
          
          self:debugPrint("Applying initial audio routing")
          self:applyAudioRouting()
          
          if self.uciVisibilityModule then
            self:debugPrint("Applying initial UCI button visibility")
            self.uciVisibilityModule:updateAllUCIButtonVisibility()
          end
          if self.gainControlModule then
            self:debugPrint("Applying initial gain controls")
            self.gainControlModule:updateAllGainControls()
          end
        end
      end
    end)
  end
  
  if controls.selCombination then
    bind(controls.selCombination, function(ctl)
      local comboIdx = self:getComboIndex(ctl.String)
      if comboIdx then
        self:setRoomStates(comboIdx)
      end
    end)
  end
  
  self:debugPrint("Event handlers setup complete using batch registration")
end

function DivisibleSpaceController:updateRoomComponent(name, roomIndex)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local oldName = self.roomComponents[roomIndex]
  self.roomComponents[roomIndex] = name
  if name and name ~= "" then
    self.components.roomControls[roomIndex] = Component.New(name)
  else
    self.components.roomControls[roomIndex] = nil
  end
  if oldName ~= name then
    self:debugPrint("Room component " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
    self:checkStatus()
  end
end

function DivisibleSpaceController:updateAudioRouter(name, roomIndex)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local oldName = self.audioRouters[roomIndex]
  self.audioRouters[roomIndex] = name
  if name and name ~= "" then
    self.components.audioRouter[roomIndex] = Component.New(name)
  else
    self.components.audioRouter[roomIndex] = nil
  end
  if oldName ~= name then
    self:debugPrint("Audio router " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
    self:checkStatus()
  end
end

function DivisibleSpaceController:updateUCIButtons(name, roomIndex)
  if roomIndex < 1 or roomIndex > #roomNames then return end
  local oldName = self.uciButtons[roomIndex]
  self.uciButtons[roomIndex] = name
  if name and name ~= "" then
    self.components.uciButtons[roomIndex] = Component.New(name)
  else
    self.components.uciButtons[roomIndex] = nil
  end
  if oldName ~= name then
    self:debugPrint("UCI buttons " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
    self:checkStatus()
  end
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
        self:debugPrint("Wall " .. wallIndex .. " (" .. roomPair[1] .. "/" .. roomPair[2] .. ") set to " .. (shouldOpen and "OPEN" or "CLOSED"))
      end
    end
  else
    self:debugPrint("SKIP: Wall states - no room combiner component")
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
      local errorMsg = roomName .. ": Component or btnSystemOnOff control not found"
      table.insert(roomStateErrors, errorMsg)
      self:debugPrint("ERROR: " .. errorMsg)
    end
  end
  
  self:debugPrint("Room states applied: " .. successfulRoomStates .. "/" .. #roomNames .. " successful")
  if #roomStateErrors > 0 then
    self:debugPrint("Room state errors: " .. #roomStateErrors)
    for _, error in ipairs(roomStateErrors) do
      self:debugPrint("  - " .. error)
    end
  end
  
  self:applyAudioRouting()
  
  if self.uciVisibilityModule then
    self:debugPrint("Updating UCI button visibility for combination...")
    self.uciVisibilityModule:updateAllUCIButtonVisibility()
  else
    self:debugPrint("SKIP: UCI visibility - module not available")
  end
  
  if self.gainControlModule then
    self:debugPrint("Updating gain controls for combination...")
    self.gainControlModule:updateAllGainControls()
  else
    self:debugPrint("SKIP: Gain controls - module not available")
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
  
  self:debugPrint("Room number mapping:")
  for roomName, roomNum in pairs(roomNumberMap) do
    self:debugPrint("  " .. roomName .. " = " .. roomNum)
  end
  
  self:debugPrint("Current audio router assignments:")
  for i, roomName in ipairs(roomNames) do
    local routerName = self.audioRouters[i] or "NONE"
    self:debugPrint("  " .. i .. ". " .. roomName .. " -> " .. routerName)
  end
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  for i, roomName in ipairs(roomNames) do
    local router = self.components.audioRouter[i]
    self:debugPrint("Processing room " .. i .. ": " .. roomName .. " (router: " .. (self.audioRouters[i] or "NONE") .. ")")
    
    if router and router["select.1"] then
      local inputNumber = self:getInputForRoom(roomName, roomGroups, currentCombination and currentCombination.priority)
      local currentValue = router["select.1"].Value
      self:debugPrint("Setting " .. roomName .. " -> Input " .. inputNumber .. " (was " .. currentValue .. ")")
      
      if inputNumber >= 1 and inputNumber <= 16 then
        setProp(router["select.1"], "Value", inputNumber)
        successfulRoutings = successfulRoutings + 1
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
  
  self:debugPrint("Audio routing complete: " .. successfulRoutings .. "/" .. #roomNames .. " successful")
  if #routingErrors > 0 then
    self:debugPrint("Routing errors: " .. #routingErrors)
    for _, error in ipairs(routingErrors) do
      self:debugPrint("  - " .. error)
    end
  end
  
  if self.gainControlModule then
    self:debugPrint("Updating gain controls after audio routing...")
    self.gainControlModule:updateAllGainControls()
  end
end

function DivisibleSpaceController:getInputForRoom(roomName, roomGroups, combinationPriority)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return 1 end
  
  self:debugPrint("getInputForRoom: " .. roomName .. " (room #" .. roomNumber .. "), groups count: " .. #roomGroups)
  
  if #roomGroups == 0 then
    self:debugPrint("  No groups - returning room's own number: " .. roomNumber)
    return roomNumber
  end
  
  for groupIndex, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      local highestPriorityRoom = math.huge
      local priorityRoomNum = combinationPriority and roomNumberMap[combinationPriority]
      if priorityRoomNum and tableContains(group, priorityRoomNum) then
        self:debugPrint("  Using combination priority room: " .. combinationPriority .. " (#" .. priorityRoomNum .. ")")
        return priorityRoomNum
      end
      for _, rn in ipairs(group) do
        if rn < highestPriorityRoom then
          highestPriorityRoom = rn
        end
      end
      self:debugPrint("  Room in group " .. groupIndex .. " - returning highest priority: " .. highestPriorityRoom)
      return highestPriorityRoom
    end
  end
  
  self:debugPrint("  Room not in any group - returning room's own number: " .. roomNumber)
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
    return roomCombinations[1]
  end
  
  local configString = configControl.String or ""
  return self:parseCombinationFromConfig(configString)
end

function DivisibleSpaceController:parseCombinationFromConfig(configString)
  self:debugPrint("Parsing combination from config: '" .. configString .. "'")
  
  local roomGroups = parseConfiguration(configString)
  
  for _, combination in ipairs(roomCombinations) do
    if self:configMatchesCombination(roomGroups, combination) then
      self:debugPrint("Matched combination: " .. combination.name)
      return combination
    end
  end
  
  self:debugPrint("No combination match found - defaulting to 'All Separated'")
  return roomCombinations[1]
end

function DivisibleSpaceController:configMatchesCombination(roomGroups, combination)
  local activeRooms = {}
  for roomName, isActive in pairs(combination.activeRooms) do
    if isActive then
      local roomNumber = roomNumberMap[roomName]
      if roomNumber then
        activeRooms[roomNumber] = true
      end
    end
  end
  
  if #roomGroups == 0 then
    return combination.id == 1
  end
  
  local groupedRooms = {}
  for _, group in ipairs(roomGroups) do
    for _, roomNum in ipairs(group) do
      groupedRooms[roomNum] = true
    end
  end
  
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

function DivisibleSpaceController:checkStatus()
  local invalidComponents = {}
  local validComponentCount = 0
  local totalComponentCount = 0
  
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
  
  local connectedUCI = 0
  for i = 1, #roomNames do
    if self.uciButtons[i] and self.uciButtons[i] ~= "" then
      connectedUCI = connectedUCI + 1
    end
  end
  
  local connectedGains = 0
  for i = 1, #roomNames do
    if controls.compGains[i] and controls.compGains[i].String and controls.compGains[i].String ~= "" and controls.compGains[i].String ~= self.clearString then
      connectedGains = connectedGains + 1
    end
  end
  
  self:debugPrint("Status check: " .. validComponentCount .. "/" .. totalComponentCount .. " components valid")
  self:debugPrint("Connected room components: " .. connectedRooms .. "/" .. #roomNames)
  self:debugPrint("Connected audio routers: " .. connectedRouters .. "/" .. #roomNames)
  self:debugPrint("Connected UCI buttons: " .. connectedUCI .. "/" .. #roomNames)
  self:debugPrint("Connected gain controls: " .. connectedGains .. "/" .. #roomNames)
  
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
      if connectedUCI < #roomNames then
        statusMsg = statusMsg .. " (UCI: " .. connectedUCI .. "/" .. #roomNames .. ")"
      end
      if connectedGains < #roomNames then
        statusMsg = statusMsg .. " (Gains: " .. connectedGains .. "/" .. #roomNames .. ")"
      end
      controls.txtStatus.String = statusMsg
      controls.txtStatus.Value = 0
      self:debugPrint("STATUS: " .. statusMsg)
    end
  end
end

function DivisibleSpaceController:scheduleDelayedUCIVisibilityUpdate()
  self:debugPrint("Scheduling delayed UCI visibility update...")
  
  local delayTimer = Timer.New()
  delayTimer.EventHandler = function()
    self:debugPrint("Executing delayed UCI visibility update...")
    
    delayTimer:Stop()
    
    if self.uciVisibilityModule then
      self:debugPrint("Delayed UCI visibility update - checking current room combination...")
      local currentCombination = self:getCurrentCombination()
      if currentCombination then
        self:debugPrint("Delayed update using combination: " .. currentCombination.name)
      else
        self:debugPrint("No combination found in delayed update - setting all separate")
      end
      self.uciVisibilityModule:updateAllUCIButtonVisibility()
    else
      self:debugPrint("SKIP: Delayed UCI visibility update - module not available")
    end
    
    if self.gainControlModule then
      self:debugPrint("Executing delayed gain control update...")
      self.gainControlModule:updateAllGainControls()
    else
      self:debugPrint("SKIP: Delayed gain control update - module not available")
    end
  end
  
  delayTimer:Start(2.0)
  self:debugPrint("Delayed UCI visibility update scheduled for 2 seconds")
end

function DivisibleSpaceController:cleanup()
  local modules = {self.componentModule, self.uciVisibilityModule, self.powerSyncModule, self.wallModule, self.gainControlModule}
  for _, module in ipairs(modules) do
    if module then module:cleanup() end
  end
  
  self:debugPrint("Cleanup completed")
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

--[[
### Verification
- The script now uses `~=` for all inequality comparisons, ensuring Lua compatibility.
- The gain control functionality (`GainControlModule`) remains fully intact, updating `compGains[i].String` based on room combinations and priority rules.
- All other modules (`UCIVisibilityModule`, `PowerSyncModule`, `WallModule`, etc.) are unaffected except for the `~=` corrections.
- The script should now run without syntax errors in a Q-SYS environment.

If you have any further questions or need additional modifications, let me know!
]]
