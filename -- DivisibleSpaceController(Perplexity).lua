--[[
Divisible Space Controller (Event-Driven, Class-Based, OOP)
Author: Nikolas Smith
Date: 2025-09-27
Version: 3.0
Requires Q-SYS Lua 10.0.1+
]]

----------------[ Utilities and Normalization ]----------------

-- Basic array and property helpers
local function isArr(t)
  return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
  if not ctrl then return {} end
  return isArr(ctrl) and ctrl or {ctrl}
end

local function setProp(obj, prop, value)
  if not obj or not prop then return false end
  if obj[prop] == value then return false end
  obj[prop] = value
  return true
end

local function bind(control, handler)
  if control then control.EventHandler = handler end
end

local function bindArray(controls, handler)
  for i, control in ipairs(getControlArray(controls)) do
    bind(control, function(ctl) handler(i, ctl) end)
  end
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

local function normalizeControlArrays(controls, arrayControls)
  for _, controlName in ipairs(arrayControls) do
    local c = controls[controlName]
    if c and not isArr(c) then controls[controlName] = {c} end
  end
end

----------------[ BaseModule and Class Inheritance ]----------------

local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
  local self = setmetatable({}, BaseModule)
  self.controller = controller
  self.name = name or "BaseModule"
  return self
end

function BaseModule:debug(str)
  if self.controller and self.controller.debug then
    print("[" .. (self.controller.roomName or "System") .. "::" .. self.name .. "] " .. str)
  end
end

function BaseModule:init() end                -- Override in subclass
function BaseModule:cleanup() end             -- Override in subclass

----------------[ Room/Wall Definitions & Discovery Module ]----------------

-- Room names and mapping
local roomNames = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"}
local roomNumberMap = {SalonD=1, SalonE=2, SalonA=3, SalonB=4, SalonC=5, SalonF=6, SalonG=7, SalonH=8}
local numberToRoomMap = {}
for name, num in pairs(roomNumberMap) do numberToRoomMap[num]=name end

-- Gain control name mapping - index follows roomNumberMap
local gainControlNames = {
  "lvlSalonD", "lvlSalonE", "lvlSalonA", "lvlSalonB", 
  "lvlSalonC", "lvlSalonF", "lvlSalonG", "lvlSalonH"
}

-- Wall pairs for all wall controls
local wallRoomPairs = {
  [1] = {"SalonD", "SalonE"}, [2] = {"SalonA", "SalonB"}, [3] = {"SalonB", "SalonC"},
  [4] = {"SalonF", "SalonG"}, [5] = {"SalonG", "SalonH"}, [6] = {"SalonD", "SalonA", "SalonB", "SalonC"},
  [7] = {"SalonE", "SalonF", "SalonG", "SalonH"}, [8] = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC"}, [9] = {"SalonD", "SalonE", "SalonF", "SalonG", "SalonH"},
  [10] = {"SalonA", "SalonB", "SalonC"}, [11] = {"SalonF", "SalonG", "SalonH"}, [12] = {"SalonA", "SalonB", "SalonC", "SalonD", "SalonE", "SalonF", "SalonG", "SalonH"}
}

local roomCombinations = {
  {name="All Separated", activeRooms={
    SalonA=true, SalonB=true, SalonC=true, SalonD=true, 
    SalonE=true, SalonF=true, SalonG=true, SalonH=true,
  }, priority=nil},
  {name="SalonA+SalonB Combined", activeRooms={
    SalonA=true, SalonB=true, SalonC=false, SalonD=false, 
    SalonE=false, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonA"},
  {name="SalonB+SalonC Combined", activeRooms={
    SalonA=false, SalonB=true, SalonC=true, SalonD=false, 
    SalonE=false, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonB"},
  {name="SalonD+SalonE Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=true, 
    SalonE=true, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonD"},
  {name="SalonF+SalonG Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=false, 
    SalonE=false, SalonF=true, SalonG=true, SalonH=false,
  }, priority="SalonF"},
  {name="SalonG+SalonH Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=false, 
    SalonE=false, SalonF=false, SalonG=true, SalonH=true,
  }, priority="SalonG"},
  {name="SalonA+SalonB+SalonC+SalonD Combined", activeRooms={
    SalonA=true, SalonB=true, SalonC=true, SalonD=true, 
    SalonE=false, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonD"},
  {name="SalonE+SalonF+SalonG+SalonH Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=false, 
    SalonE=true, SalonF=true, SalonG=true, SalonH=true,
  }, priority="SalonE"},
  {name="All Combined", activeRooms={
    SalonA=true, SalonB=true, SalonC=true, SalonD=true, 
    SalonE=true, SalonF=true, SalonG=true, SalonH=true,
  }, priority="SalonD"}
}

-- Component discovery (for populating Choices and validating UI setup)
local ComponentDiscovery = setmetatable({}, {__index = BaseModule})
ComponentDiscovery.__index = ComponentDiscovery

function ComponentDiscovery.new(controller)
  local self = BaseModule.new(controller, "ComponentDiscovery")
  setmetatable(self, ComponentDiscovery)
  return self
end

function ComponentDiscovery:discover()
  -- Collect component names by type
  local lists = {RoomControls={}, AudioRouter={}, RoomCombiner={}, UciButtons={}}
  for _, comp in ipairs(Component.GetComponents()) do
    if comp.Type == "device_controller_script" then table.insert(lists.RoomControls, comp.Name) end
    if comp.Type == "router_with_output" then table.insert(lists.AudioRouter, comp.Name) end
    if comp.Type == "room_combiner" then table.insert(lists.RoomCombiner, comp.Name) end
    if comp.Type == "custom_controls" then table.insert(lists.UciButtons, comp.Name) end
  end
  for _, arr in pairs(lists) do table.sort(arr) end
  return lists
end

----------------[ Visibility, Wall, and Power Modules ]----------------

-- Utility: config string parsing for room groups ([1,2][3][4,5] format)
local function parseConfigString(configString)
  if not configString or configString == "" then return {} end
  local groups, group, num, inGroup = {}, {}, ""
  for i = 1, #configString do
    local configChar = configString:sub(i, i)
    if configChar == "[" then inGroup, group, num = true, {}, ""
    elseif configChar == "]" then
      if #num > 0 then table.insert(group, tonumber(num)) num = "" end
      if #group > 0 then table.insert(groups, group) end
      inGroup = false
    elseif configChar == "," and inGroup then
      if #num > 0 then table.insert(group, tonumber(num)) num = "" end
    elseif configChar:match("%d") then num = num .. configChar  
    end
  end
  return groups
end

-- UCI Visibility Module
local UCIVisibilityModule = setmetatable({}, {__index=BaseModule})
UCIVisibilityModule.__index = UCIVisibilityModule
function UCIVisibilityModule.new(controller)
  local self = BaseModule.new(controller, "UCIVisibilityModule")
  setmetatable(self, UCIVisibilityModule)
  return self
end

function UCIVisibilityModule:updateAll()
  local config = self:getConfigString()
  local groups = parseConfigString(config)
  for i, roomName in ipairs(roomNames) do
    self:updateRoom(i, roomName, groups)
  end
end

function UCIVisibilityModule:updateRoom(idx, roomName, groups)
  local uciName = self.controller.uciButtons[idx]
  if not uciName or uciName == "" then return end
  local comp = Component.New(uciName)
  if not comp then return end
  local srcNum, srcGroup = roomNumberMap[roomName], nil
  for _, group in ipairs(groups) do if tableContains(group, srcNum) then srcGroup = group break end end
  for toggleIndex = 1, 8 do
    local targetInGroup = (srcGroup and tableContains(srcGroup, toggleIndex)) or (not srcGroup and toggleIndex == idx)
    local ctrlName = "toggle."..toggleIndex
    if comp[ctrlName] then comp[ctrlName].Boolean = targetInGroup end
  end
end

function UCIVisibilityModule:getConfigString()
  local roomCombiner = self.controller.components.roomCombiner
  return roomCombiner and roomCombiner["room.combiner.output.configuration"] and roomCombiner["room.combiner.output.configuration"].String or ""
end

-- Wall Module
local WallModule = setmetatable({}, {__index=BaseModule})
WallModule.__index = WallModule
function WallModule.new(controller)
  local self = BaseModule.new(controller, "WallModule")
  setmetatable(self, WallModule)
  return self
end

function WallModule:syncWallButtonStates()
  if not self.controller.components.roomCombiner then return end
  for i, roomPair in pairs(wallRoomPairs) do
    local wallButton = self.controller.controls.wallOpenButtons[i]
    local wallControl = self.controller.components.roomCombiner["wall."..i..".open"]
    if wallButton and wallControl then setProp(wallButton,"Boolean",wallControl.Boolean) end
  end
end

function WallModule:setupWallHandlers()
  if not self.controller.components.roomCombiner then return end
  for i,roomPair in pairs(wallRoomPairs) do
    local wallControl = self.controller.components.roomCombiner["wall."..i..".open"]
    if wallControl then
      bind(wallControl, function()
        local wallButton = self.controller.controls.wallOpenButtons[i]
        if wallButton then setProp(wallButton,"Boolean",wallControl.Boolean) end
        self:updateWallStates()
      end)
    end
  end
end

function WallModule:updateWallStates()
  for i,roomPair in pairs(wallRoomPairs) do
    local rn1, rn2 = roomPair[1], roomPair[2]
    local is1On = self.controller:isRoomPoweredOn(rn1)
    local is2On = self.controller:isRoomPoweredOn(rn2)
    local wallButton = self.controller.controls.wallOpenButtons[i]
    if wallButton then wallButton.IsDisabled = (is1On or is2On) end
  end
end

-- Power Sync Module
local PowerSyncModule = setmetatable({}, {__index=BaseModule})
PowerSyncModule.__index = PowerSyncModule
function PowerSyncModule.new(controller)
  local self = BaseModule.new(controller, "PowerSyncModule")
  setmetatable(self, PowerSyncModule)
  self.synced = false
  return self
end

function PowerSyncModule:setupHandlers()
  for i, roomName in ipairs(roomNames) do
    local comp = self.controller.components.roomControls[i]
    if comp and comp.ledSystemPower then
      bind(comp.ledSystemPower, function()
        self:onRoomPowerChanged(roomName, i)
      end)
    end
  end
end

function PowerSyncModule:onRoomPowerChanged(roomName, idx)
  if self.synced then return end
  self.synced = true
  local config = self:getConfigString()
  if not config then self.synced=false return end
  local groups = parseConfigString(config)
  local changedNum = roomNumberMap[roomName]
  local group = nil
  for _,g in ipairs(groups) do if tableContains(g,changedNum) then group=g break end end
  if not group or #group < 2 then self.synced=false return end
  local newPower = self.controller:isRoomPoweredOn(roomName)
  if not newPower then
    if self:shouldAutoSeparateGroup(group) then self:separateGroup(group) self.synced=false return end
  end
  -- Sync power to all in group
  for _,num in ipairs(group) do
    if num ~= changedNum then
      local rn = numberToRoomMap[num]
      local comp = self.controller.components.roomControls[num]
      if comp and comp.ledSystemPower then
        setProp(comp.ledSystemPower, "Boolean", newPower)
      end
    end
  end
  self.synced = false
end

function PowerSyncModule:getConfigString()
  local roomCombiner = self.controller.components.roomCombiner
  return roomCombiner and roomCombiner["room.combiner.output.configuration"] and roomCombiner["room.combiner.output.configuration"].String or ""
end

function PowerSyncModule:shouldAutoSeparateGroup(group)
  for _,num in ipairs(group) do
    local roomNumber = numberToRoomMap[num]
    if self.controller:isRoomPoweredOn(roomNumber) then return false end
  end
  return true
end

function PowerSyncModule:separateGroup(group)
  -- Close all walls in this group
  for wallIdx, roomPair in pairs(wallRoomPairs) do
    local rooms = {roomPair[1], roomPair[2]}
    local groupSet = {}; for _,n in ipairs(group) do groupSet[numberToRoomMap[n]] = true end
    if groupSet[rooms[1]] and groupSet[rooms[2]] then
      local wallControl = self.controller.components.roomCombiner["wall."..wallIdx..".open"]
      if wallControl and wallControl.Boolean then setProp(wallControl,"Boolean",false) end
    end
  end
  if self.controller.wallModule then self.controller.wallModule:syncWallButtonStates() end
  if self.controller.uciVisibilityModule then self.controller.uciVisibilityModule:updateAll() end
end

----------------[ Main Controller Orchestrator ]----------------

local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debug)
  -- UI control refs with nil checking and validation
  local controls = {}
  
  -- Required Controls validation
  local requiredControls = {
    "compRoomControls", "compAudioRouter", "compRoomCombiner",
    "wallOpenButtons", "uciButtons", "txtStatus"
  }
  
  local missingControls = {}
  
  -- Safely assign controls with nil checking
  controls.compRoomControls = Controls.compRoomControls or {}
  controls.compAudioRouter = Controls.compAudioRouter or {}
  controls.compRoomCombiner = Controls.compRoomCombiner
  controls.wallOpenButtons = Controls.wallOpenButtons or {}
  controls.uciButtons = Controls.uciButtons or {}
  controls.selCombination = Controls.selRoomCombination  -- Note: different name
  controls.txtStatus = Controls.txtStatus
  
  -- Check for missing required controls
  if not Controls.compRoomControls then table.insert(missingControls, "compRoomControls") end
  if not Controls.compAudioRouter then table.insert(missingControls, "compAudioRouter") end
  if not Controls.compRoomCombiner then table.insert(missingControls, "compRoomCombiner") end
  if not Controls.wallOpenButtons then table.insert(missingControls, "wallOpenButtons") end
  if not Controls.uciButtons then table.insert(missingControls, "uciButtons") end
  if not Controls.txtStatus then table.insert(missingControls, "txtStatus") end
  
  -- Report missing controls
  if #missingControls > 0 then
    print("WARNING: Missing Controls: " .. table.concat(missingControls, ", "))
  end
  
  local arrayControls = {"compRoomControls", "compAudioRouter", "wallOpenButtons", "uciButtons"}
  normalizeControlArrays(controls, arrayControls)
  -- Instance construction
  local self = setmetatable({}, DivisibleSpaceController)
  self.controls = controls
  self.roomName = roomName or "Divisible Space"
  self.debug = debug or false
  -- Arrays for component objects, indexed by room
  self.components = {roomCombiner=nil, roomControls={}, audioRouter={}, gains={}, uciButtons={}}
  
  -- Component creation with flat validation
  for i, ctrl in ipairs(controls.compRoomControls) do
    self.components.roomControls[i] = nil
    if not ctrl or not ctrl.String or ctrl.String == "" then goto nextRoomControl end
    local comp = Component.New(ctrl.String)
    self.components.roomControls[i] = comp
    if not comp then print("WARNING: Failed to create room control component: " .. ctrl.String) end
    ::nextRoomControl::
  end
  
  for i, ctrl in ipairs(controls.compAudioRouter) do
    self.components.audioRouter[i] = nil
    if not ctrl or not ctrl.String or ctrl.String == "" then goto nextAudioRouter end
    local comp = Component.New(ctrl.String)
    self.components.audioRouter[i] = comp
    if not comp then print("WARNING: Failed to create audio router component: " .. ctrl.String) end
    ::nextAudioRouter::
  end
  
  
  -- Initialize uciButtons array
  self.uciButtons = {}
  for i, ctrl in ipairs(controls.uciButtons) do
    self.uciButtons[i] = ""
    self.components.uciButtons[i] = nil
    if not ctrl or not ctrl.String then goto nextUciButton end
    self.uciButtons[i] = ctrl.String
    if ctrl.String == "" then goto nextUciButton end
    local comp = Component.New(ctrl.String)
    self.components.uciButtons[i] = comp
    if not comp then print("WARNING: Failed to create UCI button component: " .. ctrl.String) end
    ::nextUciButton::
  end
  
  -- Room combiner creation
  if controls.compRoomCombiner and controls.compRoomCombiner.String and controls.compRoomCombiner.String ~= "" then
    local comp = Component.New(controls.compRoomCombiner.String)
    self.components.roomCombiner = comp
    if not comp then print("WARNING: Failed to create room combiner component: " .. controls.compRoomCombiner.String) end
  end
  -- Create modules
  self.componentDiscovery = ComponentDiscovery.new(self)
  self.uciVisibilityModule = UCIVisibilityModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  -- Validation and Choices assignment
  local choices = self.componentDiscovery:discover()
  
  -- Choices assignment
  forEach(controls.compRoomControls, function(_,c) 
    if c and c.Choices then c.Choices = choices.RoomControls end
  end)
  forEach(controls.compAudioRouter, function(_,c) 
    if c and c.Choices then c.Choices = choices.AudioRouter end
  end)
  forEach(controls.uciButtons, function(_,c) 
    if c and c.Choices then c.Choices = choices.UciButtons end
  end)
  if controls.compRoomCombiner and controls.compRoomCombiner.Choices then 
    controls.compRoomCombiner.Choices = choices.RoomCombiner 
  end
  -- Main logic/event wiring
  self:wireHandlers()
  self:applyInitialRouting()
  
  print("DivisibleSpaceController: Initialization completed successfully")
  return self
end

function DivisibleSpaceController:wireHandlers()
  self.powerSyncModule:setupHandlers()
  self.wallModule:setupWallHandlers()
  
  -- Wire combination selector handler
  if self.controls.selCombination then
    bind(self.controls.selCombination, function(ctl)
      local comboIdx = self:getComboIndex(ctl.String)
      if comboIdx then
        self:setRoomStates(comboIdx)
      end
    end)
  end
end

function DivisibleSpaceController:applyInitialRouting()
  -- Setup combination selector choices
  self:setupCombinationSelector()
  
  -- Apply initial routing and UI updates
  self:applyAudioRouting()
  self:applyGainRouting()
  if self.uciVisibilityModule then self.uciVisibilityModule:updateAll() end
  if self.wallModule then self.wallModule:syncWallButtonStates() end
  
  -- Check and report initial status
  self:checkStatus()
end

-- Helper: check power state for any room
function DivisibleSpaceController:isRoomPoweredOn(roomName)
  local idx = roomNumberMap[roomName]
  local ctrl = idx and self.components.roomControls[idx] and self.components.roomControls[idx].ledSystemPower
  return ctrl and ctrl.Boolean or false
end

-- Audio Routing System
function DivisibleSpaceController:applyAudioRouting()
  if not self.components.roomCombiner then return end
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then return end
  
  local configString = configControl.String
  local roomGroups = parseConfigString(configString)
  local currentCombination = self:getCurrentCombination()
  
  for i, roomName in ipairs(roomNames) do
    local router = self.components.audioRouter[i]
    if router and router["select.1"] then
      local inputNumber = self:getInputForRoom(roomName, roomGroups, currentCombination and currentCombination.priority)
      if inputNumber >= 1 and inputNumber <= 16 then
        setProp(router["select.1"], "Value", inputNumber)
      end
    end
  end
end

function DivisibleSpaceController:getInputForRoom(roomName, roomGroups, combinationPriority)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return 1 end
  
  -- If no groups (all separated), each room gets its own input number
  if #roomGroups == 0 then return roomNumber end
  
  -- Check if room is in any group
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      -- Find the highest priority room in this group (lowest room number, or use combination priority if set and in group)
      local priorityRoomNumber = combinationPriority and roomNumberMap[combinationPriority]
      if priorityRoomNumber and tableContains(group, priorityRoomNumber) then
        return priorityRoomNumber
      end
      local highestPriorityRoom = math.huge
      for _, numberedRoom in ipairs(group) do
        if numberedRoom < highestPriorityRoom then
          highestPriorityRoom = numberedRoom
        end
      end
      return highestPriorityRoom
    end
  end
  
  -- If room not found in any group, it's separated and gets its own input
  return roomNumber
end

-- Gain Routing System  
function DivisibleSpaceController:applyGainRouting()
  if not self.components.roomCombiner then return end
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then return end
  
  local configString = configControl.String
  local roomGroups = parseConfigString(configString)
  local currentCombination = self:getCurrentCombination()
  
  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]
    if roomComp and roomComp["compGains"] and roomComp["compGains"][1] then
      local gainControlName = self:getGainControlForRoom(roomName, roomGroups, currentCombination and currentCombination.priority)
      if gainControlName and gainControlName ~= "" then
        setProp(roomComp["compGains"][1], "String", gainControlName)
      end
    end
  end
end

function DivisibleSpaceController:getGainControlForRoom(roomName, roomGroups, combinationPriority)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return gainControlNames[1] end
  
  -- If no groups (all separated), each room gets its own gain control
  if #roomGroups == 0 then return gainControlNames[roomNumber] end
  
  -- Check if room is in any group
  for _, group in ipairs(roomGroups) do
    if tableContains(group, roomNumber) then
      -- Find the highest priority room in this group (lowest room number, or use combination priority if set and in group)
      local priorityRoomNumber = combinationPriority and roomNumberMap[combinationPriority]
      if priorityRoomNumber and tableContains(group, priorityRoomNumber) then
        return gainControlNames[priorityRoomNumber]
      end
      local highestPriorityRoom = math.huge
      for _, roomNum in ipairs(group) do
        if roomNum < highestPriorityRoom then
          highestPriorityRoom = roomNum
        end
      end
      return gainControlNames[highestPriorityRoom]
    end
  end
  
  -- If room not found in any group, it's separated and gets its own gain control
  return gainControlNames[roomNumber]
end

-- Configuration Matching Logic
function DivisibleSpaceController:getCurrentCombination()
  if not self.components.roomCombiner then return roomCombinations[1] end
  local configControl = self.components.roomCombiner["room.combiner.output.configuration"]
  if not configControl then return roomCombinations[1] end
  
  local configString = configControl.String or ""
  return self:parseCombinationFromConfig(configString)
end

function DivisibleSpaceController:parseCombinationFromConfig(configString)
  local roomGroups = parseConfigString(configString)
  
  -- Match the room groups to our predefined combinations
  for _, combination in ipairs(roomCombinations) do
    if self:configMatchesCombination(roomGroups, combination) then
      return combination
    end
  end
  
  -- If no match found, default to "All Separated"
  return roomCombinations[1]
end

function DivisibleSpaceController:configMatchesCombination(roomGroups, combination)
  -- Create a set of active rooms from the combination
  local activeRooms = {}
  for roomName, isActive in pairs(combination.activeRooms) do
    if isActive then
      local roomNumber = roomNumberMap[roomName]
      if roomNumber then activeRooms[roomNumber] = true end
    end
  end
  
  -- Check if the room groups match the active rooms
  if #roomGroups == 0 then
    -- No groups means all separated - check if combination is "All Separated"
    return combination.name == "All Separated"
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
    if not groupedRooms[roomNum] then return false end
  end
  
  for roomNum in pairs(groupedRooms) do
    if not activeRooms[roomNum] then return false end
  end
  
  return true
end

-- Enhanced Status System
function DivisibleSpaceController:checkStatus()
  if not self.controls or not self.controls.txtStatus then 
    print("WARNING: No status text control available")
    return 
  end
  
  local statusMessages = {}
  local hasErrors = false
  
  -- Check room combiner
  if not self.components.roomCombiner then
    table.insert(statusMessages, "No Room Combiner")
    hasErrors = true
  end
  
  -- Check room controls
  local connectedRooms = 0
  for i = 1, #roomNames do
    if self.components.roomControls and self.components.roomControls[i] then
      connectedRooms = connectedRooms + 1
    end
  end
  if connectedRooms < #roomNames then
    table.insert(statusMessages, "Rooms: " .. connectedRooms .. "/" .. #roomNames)
  end
  
  -- Check audio routers  
  local connectedRouters = 0
  for i = 1, #roomNames do
    if self.components.audioRouter and self.components.audioRouter[i] then
      connectedRouters = connectedRouters + 1
    end
  end
  if connectedRouters < #roomNames then
    table.insert(statusMessages, "Routers: " .. connectedRouters .. "/" .. #roomNames)
  end
  
  -- Check gain components
  local connectedGains = 0
  for i = 1, #roomNames do
    if self.components.gains and self.components.gains[i] then
      connectedGains = connectedGains + 1
    end
  end
  if connectedGains < #roomNames then
    table.insert(statusMessages, "Gains: " .. connectedGains .. "/" .. #roomNames)
  end
  
  -- Update status display
  if not self.controls.txtStatus.String or not self.controls.txtStatus.Value then
    print("WARNING: Status control missing String or Value property")
    return
  end
  
  if #statusMessages > 0 then
    self.controls.txtStatus.String = "PARTIAL: " .. table.concat(statusMessages, ", ")
    self.controls.txtStatus.Value = hasErrors and 2 or 1
  else
    self.controls.txtStatus.String = "OK: All Systems Connected"
    self.controls.txtStatus.Value = 0
  end
end

-- Combination Selector Implementation
function DivisibleSpaceController:setupCombinationSelector()
  if not self.controls.selCombination then return end
  
  local choices = {}
  for _, combo in ipairs(roomCombinations) do
    table.insert(choices, combo.name)
  end
  self.controls.selCombination.Choices = choices
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
  if not combo then return false end
  
  -- Set wall states first
  if self.components.roomCombiner then
    for wallIndex, roomPair in pairs(wallRoomPairs) do
      local shouldOpen = self:shouldWallBeOpenForCombo(roomPair, combo)
      local wallControlName = "wall." .. wallIndex .. ".open"
      local wallControl = self.components.roomCombiner[wallControlName]
      if wallControl then
        setProp(wallControl, "Boolean", shouldOpen)
      end
    end
  end
  
  -- Set room power states
  for i, roomName in ipairs(roomNames) do
    local comp = self.components.roomControls[i]
    if comp and comp["ledSystemPower"] then
      local isActive = combo.activeRooms[roomName] or false
      setProp(comp["ledSystemPower"], "Boolean", isActive)
    end
  end
  
  -- Apply audio and gain routing
  self:applyAudioRouting()
  self:applyGainRouting()
  
  -- Update UCI button visibility
  if self.uciVisibilityModule then
    self.uciVisibilityModule:updateAll()
  end
  
  -- Update wall states
  if self.wallModule then 
    self.wallModule:updateWallStates() 
  end
  
  return true
end

----------------[ Manual Test Functions ]----------------
function manualTestAudioRouting()
  if myDivisibleController then
    print("Manual audio routing test triggered")
    myDivisibleController:applyAudioRouting()
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function debugCurrentRouterStates()
  if myDivisibleController then
    print("=== CURRENT ROUTER STATES DEBUG ===")
    for i, roomName in ipairs(roomNames) do
      local router = myDivisibleController.components.audioRouter[i]
      if router and router["select.1"] then
        local currentInput = router["select.1"].Value
        print(roomName .. " current input: " .. currentInput)
      else
        print(roomName .. " - NO ROUTER OR CONTROL")
      end
    end
    print("=== END ROUTER STATES DEBUG ===")
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function manualTestGainRouting()
  if myDivisibleController then
    print("Manual gain routing test triggered")
    myDivisibleController:applyGainRouting()
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

function debugCurrentGainStates()
  if myDivisibleController then
    print("=== CURRENT GAIN STATES DEBUG ===")
    for i, roomName in ipairs(roomNames) do
      local roomComp = myDivisibleController.components.roomControls[i]
      if roomComp then
        print(roomName .. " room component found")
        if roomComp["compGains"] and roomComp["compGains"][1] then
          local currentGain = roomComp["compGains"][1].String or ""
          print("  current gain control: " .. currentGain)
        else
          print("  NO compGains control found")
        end
      else
        print(roomName .. " - NO ROOM COMPONENT")
      end
    end
    print("=== END GAIN STATES DEBUG ===")
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

----------------[ Deployment and Instance Creation ]----------------

-- Construct and start the controller (usually only one instance per core)
print("DivisibleSpaceController: Starting initialization...")

local roomName = "Default Room"
if Controls.txtRoomName and Controls.txtRoomName.String and Controls.txtRoomName.String ~= "" then
  roomName = Controls.txtRoomName.String
end

local myDivisibleController = DivisibleSpaceController.new(
  roomName,
  true   -- enable debug output
)

-- Global exports for external access and debugging
_G.DivisibleSpaceController = DivisibleSpaceController
_G.myDivisibleController = myDivisibleController
