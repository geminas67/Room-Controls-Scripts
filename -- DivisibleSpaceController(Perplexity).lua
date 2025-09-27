--[[
Divisible Space Controller (Event-Driven, Class-Based, OOP)
Author: Nikolas Smith
Date: 2025-09-27
Version: 3.0
Requires Q-SYS Lua 10.0.0+
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
  {name="SalonC+SalonD Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=true, SalonD=true, 
    SalonE=false, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonD"},
  {name="SalonD+SalonE Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=true, 
    SalonE=true, SalonF=false, SalonG=false, SalonH=false,
  }, priority="SalonD"},
  {name="SalonE+SalonF Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=false, 
    SalonE=true, SalonF=true, SalonG=false, SalonH=false,
  }, priority="SalonE"},
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
  }, priority="SalonA"},
  {name="SalonE+SalonF+SalonG+SalonH Combined", activeRooms={
    SalonA=false, SalonB=false, SalonC=false, SalonD=false, 
    SalonE=true, SalonF=true, SalonG=true, SalonH=true,
  }, priority="SalonE"},
  {name="All Combined", activeRooms={
    SalonA=true, SalonB=true, SalonC=true, SalonD=true, 
    SalonE=true, SalonF=true, SalonG=true, SalonH=true,
  }, priority="SalonA"}
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
    local c = configString:sub(i, i)
    if c == "[" then inGroup, group, num = true, {}, ""
    elseif c == "]" then
      if #num > 0 then table.insert(group, tonumber(num)) num = "" end
      if #group > 0 then table.insert(groups, group) end
      inGroup = false
    elseif c == "," and inGroup then
      if #num > 0 then table.insert(group, tonumber(num)) num = "" end
    elseif c:match("%d") then num = num .. c
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
  for tIdx = 1, 8 do
    local targetInGroup = (srcGroup and tableContains(srcGroup, tIdx)) or (not srcGroup and tIdx == idx)
    local ctrlName = "toggle."..tIdx
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
    local wallBtn = self.controller.controls.wallOpenButtons[i]
    local wallCtl = self.controller.components.roomCombiner["wall."..i..".open"]
    if wallBtn and wallCtl then setProp(wallBtn,"Boolean",wallCtl.Boolean) end
  end
end

function WallModule:setupWallHandlers()
  if not self.controller.components.roomCombiner then return end
  for i,roomPair in pairs(wallRoomPairs) do
    local wallCtl = self.controller.components.roomCombiner["wall."..i..".open"]
    if wallCtl then
      bind(wallCtl, function()
        local wallBtn = self.controller.controls.wallOpenButtons[i]
        if wallBtn then setProp(wallBtn,"Boolean",wallCtl.Boolean) end
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
    local wallBtn = self.controller.controls.wallOpenButtons[i]
    if wallBtn then wallBtn.IsDisabled = (is1On or is2On) end
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
    local rn = numberToRoomMap[num]
    if self.controller:isRoomPoweredOn(rn) then return false end
  end
  return true
end

function PowerSyncModule:separateGroup(group)
  -- Close all walls in this group
  for wallIdx, roomPair in pairs(wallRoomPairs) do
    local rooms = {roomPair[1], roomPair[2]}
    local groupSet = {}; for _,n in ipairs(group) do groupSet[numberToRoomMap[n]] = true end
    if groupSet[rooms[1]] and groupSet[rooms[2]] then
      local wallCtl = self.controller.components.roomCombiner["wall."..wallIdx..".open"]
      if wallCtl and wallCtl.Boolean then setProp(wallCtl,"Boolean",false) end
    end
  end
  if self.controller.wallModule then self.controller.wallModule:syncWallButtonStates() end
  if self.controller.uciVisibilityModule then self.controller.uciVisibilityModule:updateAll() end
end

----------------[ Main Controller Orchestrator ]----------------

local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debug)
  -- UI control refs
  local controls = {
    compRoomControls = Controls.compRoomControls,
    compAudioRouter = Controls.compAudioRouter,
    compGains = Controls.compGains,
    compRoomCombiner = Controls.compRoomCombiner,
    wallOpenButtons = Controls.wallOpenButtons,
    uciButtons = Controls.uciButtons,
    selCombination = Controls.selRoomCombination,
    txtStatus = Controls.txtStatus,
  }
  local arrayControls = {"compRoomControls", "compAudioRouter", "compGains", "wallOpenButtons", "uciButtons"}
  normalizeControlArrays(controls, arrayControls)
  -- Instance construction
  local self = setmetatable({}, DivisibleSpaceController)
  self.controls = controls
  self.roomName = roomName or "Divisible Space"
  self.debug = debug or false
  -- Arrays for component objects, indexed by room
  self.components = {roomCombiner=nil, roomControls={}, audioRouter={}, gains={}, uciButtons={}}
  for i, ctrl in ipairs(controls.compRoomControls) do
    self.components.roomControls[i] = ctrl.String and ctrl.String ~= "" and Component.New(ctrl.String) or nil
  end
  for i, ctrl in ipairs(controls.compAudioRouter) do
    self.components.audioRouter[i] = ctrl.String and ctrl.String ~= "" and Component.New(ctrl.String) or nil
  end
  for i, ctrl in ipairs(controls.compGains) do
    self.components.gains[i] = ctrl.String and ctrl.String ~= "" and Component.New(ctrl.String) or nil
  end
  for i, ctrl in ipairs(controls.uciButtons) do
    self.uciButtons = self.uciButtons or {}
    self.uciButtons[i] = ctrl.String and ctrl.String ~= "" and ctrl.String or ""
    self.components.uciButtons[i] = ctrl.String and ctrl.String ~= "" and Component.New(ctrl.String) or nil
  end
  if controls.compRoomCombiner and controls.compRoomCombiner.String ~= "" then
    self.components.roomCombiner = Component.New(controls.compRoomCombiner.String)
  end
  -- Create modules
  self.componentDiscovery = ComponentDiscovery.new(self)
  self.uciVisibilityModule = UCIVisibilityModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  -- Validation and Choices assignment
  local choices = self.componentDiscovery:discover()
  forEach(controls.compRoomControls, function(_,c) c.Choices=choices.RoomControls end)
  forEach(controls.compAudioRouter, function(_,c) c.Choices=choices.AudioRouter end)
  forEach(controls.compGains, function(_,c) c.Choices=choices.RoomControls end)
  forEach(controls.uciButtons, function(_,c) c.Choices=choices.UciButtons end)
  if controls.compRoomCombiner then controls.compRoomCombiner.Choices = choices.RoomCombiner end
  -- Main logic/event wiring
  self:wireHandlers()
  self:applyInitialRouting()
  return self
end

function DivisibleSpaceController:wireHandlers()
  self.powerSyncModule:setupHandlers()
  self.wallModule:setupWallHandlers()
  -- Optional: more handler wiring for combos, UCI, etc
end

function DivisibleSpaceController:applyInitialRouting()
  if self.uciVisibilityModule then self.uciVisibilityModule:updateAll() end
  if self.wallModule then self.wallModule:syncWallButtonStates() end
end

-- Helper: check power state for any room
function DivisibleSpaceController:isRoomPoweredOn(roomName)
  local idx = roomNumberMap[roomName]
  local ctrl = idx and self.components.roomControls[idx] and self.components.roomControls[idx].ledSystemPower
  return ctrl and ctrl.Boolean or false
end

----------------[ Deployment and Instance Creation ]----------------

-- Construct and start the controller (usually only one instance per core)
local myDivisibleController = DivisibleSpaceController.new(
  Controls.txtRoomName and Controls.txtRoomName.String or "Default Room",
  true   -- enable debug output
)

-- Optional: expose for manual commands or debugging
_G.DivisibleSpaceController = myDivisibleController
