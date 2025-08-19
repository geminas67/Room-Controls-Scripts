--[[
  Divisible Space Controller with Room Priority System
  Author: Nikolas Smith
  Date: 2025-08-16
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 6.1 - Modularized with Utility Functions and Submodules
  Hybrid DivisibleSpaceController for Multi-Room Divisible Spaces
  Scalable, modular, and array-optimized for Q-SYS

  
  Room Priority Hierarchy:
  SalonD --> SalonE (D has priority over E)
  SalonA --> SalonB --> SalonC (A has highest priority in group)
  SalonF --> SalonG --> SalonH (F has highest priority in group)
  
  Special Rules:
  - SalonD has priority when combined with A/B/C
  - SalonE has priority when combined with F/G/H  
  - SalonD has priority when all rooms combined
]]

-----------------------------[ Room Names & Combinations ]-----------------------------
local roomNames = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"}

-- Room number mapping for audio router logic
local roomNumberMap = {
  SalonD = 1,
  SalonE = 2,
  SalonA = 3,
  SalonB = 4,
  SalonC = 5,
  SalonF = 6,
  SalonG = 7,
  SalonH = 8
}

local wallRoomPairs = {
    [1] = {"SalonD", "SalonE"},
    [2] = {"SalonA", "SalonB"},
    [3] = {"SalonB", "SalonC"},
    [4] = {"SalonF", "SalonG"},
    [5] = {"SalonG", "SalonH"},
    [6] = {"SalonD", "SalonA"},
    [7] = {"SalonD", "SalonB"},
    [8] = {"SalonD", "SalonC"},
    [9] = {"SalonE", "SalonF"},
    [10] = {"SalonE", "SalonG"},
    [11] = {"SalonE", "SalonH"},
}

-- Priority System for Combination Logic
local roomPriorities = { SalonD=1, SalonE=2, SalonA=3, SalonF=4, SalonB=5, SalonG=6, SalonC=7, SalonH=8 }

local roomCombinations = {
  -- Index is combo ID, used in UI or logic; name is descriptive
  { id=1, name="All Separated",                             activeRooms={SalonA=true,  SalonB=true,  SalonC=true,  SalonD=true,  SalonE=true,  SalonF=true,  SalonG=true,  SalonH=true},  priority=nil },
  { id=2, name="SalonA+SalonB Combined",                    activeRooms={SalonA=true,  SalonB=true,  SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=3, name="SalonB+SalonC Combined",                    activeRooms={SalonA=false, SalonB=true,  SalonC=true,  SalonD=false, SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonB" },
  { id=4, name="SalonC+SalonD Combined",                    activeRooms={SalonA=false, SalonB=false, SalonC=true,  SalonD=true,  SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=5, name="SalonD+SalonE Combined",                    activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=true,  SalonE=true,  SalonF=false, SalonG=false, SalonH=false}, priority="SalonD" },
  { id=6, name="SalonE+SalonF Combined",                    activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=true,  SalonF=true,  SalonG=false, SalonH=false}, priority="SalonE" },
  { id=7, name="SalonF+SalonG Combined",                    activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=true,  SalonG=true,  SalonH=false}, priority="SalonF" },
  { id=8, name="SalonG+SalonH Combined",                    activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=false, SalonF=false, SalonG=true,  SalonH=true},  priority="SalonG" },
  { id=9, name="SalonA+SalonB+SalonC+SalonD Combined",      activeRooms={SalonA=true,  SalonB=true,  SalonC=true,  SalonD=true,  SalonE=false, SalonF=false, SalonG=false, SalonH=false}, priority="SalonA" },
  { id=10,name="SalonE+SalonF+SalonG+SalonH Combined",      activeRooms={SalonA=false, SalonB=false, SalonC=false, SalonD=false, SalonE=true,  SalonF=true,  SalonG=true,  SalonH=true},  priority="SalonE" },
  { id=11,name="All Combined",                              activeRooms={SalonA=true,  SalonB=true,  SalonC=true,  SalonD=true,  SalonE=true,  SalonF=true,  SalonG=true,  SalonH=true},  priority="SalonA" }
  -- Add/modify combinations as needed
} 

-----------------------------[ Controls Arrays: Assign in Design ]-----------------------------
local controls = {
  compRoomControls   = Controls.compRoomControls,
  compAudioRouter    = Controls.compAudioRouter,
  compRoomCombiner   = Controls.compRoomCombiner,
  txtStatus          = Controls.txtStatus,       
  selCombination     = Controls.selRoomCombination, 
  wallOpenButtons    = {}      
}

-- Wall button controls setup for partition controls
for i = 1, 11 do -- Adjust 11 to the number of partitions in your system
  controls.wallOpenButtons[i] = Controls["wall" .. i .. ".open"]
end

-----------------------------[ Utility Functions ]-----------------------------

-- Generic component assignment utility
local function findRoomIndexByComponentName(componentName, roomNames, targetType)
  if not componentName or componentName == "" then
    return nil
  end
  
  for i, roomName in ipairs(roomNames) do
    -- Check if this component name matches the expected pattern for this room
    if string.match(componentName, roomName) or string.match(componentName, targetType .. i) then
      return i
    end
  end
  return nil
end

-- Generic event handler assignment utility
local function assignHandlerIfExists(control, handlerFn)
  if control then
    control.EventHandler = handlerFn
    return true
  end
  return false
end

-----------------------------[ Submodules ]-----------------------------

-- Wall Control Submodule
local WallControl = {}

function WallControl.new(controls, wallRoomPairs, roomNames, roomComponents)
  local self = setmetatable({}, {__index = WallControl})
  self.controls = controls
  self.wallRoomPairs = wallRoomPairs
  self.roomNames = roomNames
  self.roomComponents = roomComponents
  return self
end

function WallControl:updateStates()
  for wallIndex, roomPair in pairs(self.wallRoomPairs) do
    local room01 = roomPair[1]
    local room02 = roomPair[2]
    local isRoom01On = self:isRoomPoweredOn(room01)
    local isRoom02On = self:isRoomPoweredOn(room02)
    local wallButton = self.controls.wallOpenButtons[wallIndex]
    if wallButton then
      wallButton.IsDisabled = (isRoom01On or isRoom02On) and true or false
    end
  end
end

function WallControl:registerHandlers()
  for i, wallButton in ipairs(self.controls.wallOpenButtons) do
    if wallButton then
      wallButton.EventHandler = function(ctrl)
        -- Wall button pressed - update wall button states
        self:updateStates()
      end
    end
  end
end

function WallControl:isRoomPoweredOn(roomName)
  for i, rn in ipairs(self.roomNames) do
    if rn == roomName and self.roomComponents[i] then
      local comp = Component.New(self.roomComponents[i])
      if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
        return comp.Controls["btnSystemOnOff"].Boolean
      end
    end
  end
  return false
end

-- Room Audio Routing Submodule
local RoomAudioRouting = {}

function RoomAudioRouting.new(roomNames, roomNumberMap)
  local self = setmetatable({}, {__index = RoomAudioRouting})
  self.roomNames = roomNames
  self.roomNumberMap = roomNumberMap
  return self
end

function RoomAudioRouting:parseConfiguration(configString)
  if not configString or configString == "" then
    return {}
  end
  
  -- Parse the JSON-like string: [[1,2],[3,4,5],[6],[7],[8]]
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

function RoomAudioRouting:getInputForRoom(roomName, roomGroups)
  local roomNumber = self.roomNumberMap[roomName]
  if not roomNumber then
    return 1
  end
  
  -- Find which group contains this room number
  for groupIndex, group in ipairs(roomGroups) do
    for _, roomNum in ipairs(group) do
      if roomNum == roomNumber then
        -- Return the group index (1-based) as the audio router input
        return groupIndex
      end
    end
  end
  
  -- If room not found in any group, default to input 1
  return 1
end

function RoomAudioRouting:applyRouting(roomCombiner, audioRouters, debugPrint)
  if not roomCombiner then
    if debugPrint then debugPrint("No room combiner component available") end
    return
  end
  
  -- Get the room.combiner.output.configuration control
  local configControl = roomCombiner.Controls["room.combiner.output.configuration"]
  if not configControl then
    if debugPrint then debugPrint("room.combiner.output.configuration control not found") end
    return
  end
  
  local configString = configControl.String
  if debugPrint then debugPrint("Room configuration: " .. tostring(configString)) end
  
  -- Parse the configuration string
  local roomGroups = self:parseConfiguration(configString)
  if debugPrint then debugPrint("Parsed " .. #roomGroups .. " room groups") end
  
  -- Apply audio router inputs for each room
  for i, roomName in ipairs(self.roomNames) do
    local routerName = audioRouters[i]
    if routerName then
      local comp = Component.New(routerName)
      if comp and comp.Controls and comp.Controls["select.1"] then
        local inputNumber = self:getInputForRoom(roomName, roomGroups)
        comp.Controls["select.1"].Value = inputNumber
        if debugPrint then debugPrint("Audio Router " .. roomName .. ": select.1 = " .. tostring(inputNumber)) end
      end
    end
  end
end

-- Room State Management Submodule
local RoomState = {}

function RoomState.new(roomNames, roomComponents)
  local self = setmetatable({}, {__index = RoomState})
  self.roomNames = roomNames
  self.roomComponents = roomComponents
  return self
end

function RoomState:setStates(comboIdx, roomCombinations)
  local combo = roomCombinations[comboIdx]
  if not combo then
    return false
  end

  -- Set btnSystemOnOff for each room based on active state
  for i, roomName in ipairs(self.roomNames) do
    local compName = self.roomComponents[i]
    if compName then
      local comp = Component.New(compName)
      if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
        local isActive = combo.activeRooms[roomName] or false
        comp.Controls["btnSystemOnOff"].Boolean = isActive
      end
    end
  end
  
  return true
end

function RoomState:setPower(roomIndex, isOn)
  local compName = self.roomComponents[roomIndex]
  if compName then
    local comp = Component.New(compName)
    if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
      comp.Controls["btnSystemOnOff"].Boolean = isOn
      return true
    end
  end
  return false
end

function RoomState:isPoweredOn(roomName)
  for i, rn in ipairs(self.roomNames) do
    if rn == roomName and self.roomComponents[i] then
      local comp = Component.New(self.roomComponents[i])
      if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
        return comp.Controls["btnSystemOnOff"].Boolean
      end
    end
  end
  return false
end

-- Debug & Status Submodule
local DebugStatus = {}

function DebugStatus.new(controls, components, debugging)
  local self = setmetatable({}, {__index = DebugStatus})
  self.controls = controls
  self.components = components
  self.debugging = debugging
  return self
end

function DebugStatus:print(msg)
  if self.debugging then print("[DivisibleSpace Debug] " .. tostring(msg)) end
end

function DebugStatus:checkStatus()
  -- Check for any invalid components using the proper tracking system
  for componentType, isInvalid in pairs(self.components.invalid) do
    if isInvalid then
      if self.controls.txtStatus then
        self.controls.txtStatus.String = "Invalid Components"
        self.controls.txtStatus.Value = 1
      end
      return
    end
  end
  
  -- All components valid
  if self.controls.txtStatus then
    self.controls.txtStatus.String = "OK"
    self.controls.txtStatus.Value = 0
  end
end

function DebugStatus:validateControls()
  if not self.debugging then return end
  
  print("[DivisibleSpace Debug] Control Validation:")
  
  -- Check main controls
  local mainControls = {"compRoomControls", "compAudioRouter", "compRoomCombiner", "txtStatus", "selRoomCombination"}
  for _, controlName in ipairs(mainControls) do
    local control = Controls[controlName]
    if control then
      print("  ✓ " .. controlName .. " exists")
    else
      print("  ✗ " .. controlName .. " MISSING")
    end
  end
end

-----------------------------[ Controller Class ]-----------------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(config)
  local self = setmetatable({}, DivisibleSpaceController)
  self.controls = config.controls
  self.roomNames = config.roomNames
  self.roomPriorities = config.roomPriorities
  self.roomCombinations = config.roomCombinations
  self.roomNumberMap = config.roomNumberMap
  self.debugging = config.debugging or false
  self.clearString = "[Clear]"

  -- Define component types as instance variable (like working template)
  self.componentTypes = {
      roomCombiner = "room_combiner",
      roomControls = "device_controller_script",
      audioRouter = "router_with_output"
  }
  
  -- Initialize components and invalid tracking like working templates
  self.components = {
    roomCombiner = nil,
    roomControls = {},
    audioRouter = {},
    invalid = {}
  }
  
  -- Initialize invalid components tracking
  self.components.invalid = {
    roomCombiner = false,
    roomControls = false,
    audioRouter = false
  }
  
  self.roomComponents = {} -- Index by room #
  self.audioRouters   = {}

  -- Initialize room components arrays
  for i, _ in ipairs(self.roomNames) do
    self.roomComponents[i] = nil
    self.audioRouters[i] = nil
  end

  -- Initialize submodules
  self.wallControl = WallControl.new(self.controls, wallRoomPairs, self.roomNames, self.roomComponents)
  self.audioRouting = RoomAudioRouting.new(self.roomNames, self.roomNumberMap)
  self.roomState = RoomState.new(self.roomNames, self.roomComponents)
  self.debugStatus = DebugStatus.new(self.controls, self.components, self.debugging)

  self:_discoverComponents()
  self:_wireEventHandlers()
  self.debugStatus:checkStatus()
  self.wallControl:updateStates()  -- Initialize wall button states
  return self
end

-----------------[ Component Name Discovery ]-------------------

function DivisibleSpaceController:_discoverComponents()
  local namesTable = {
    RoomControlsNames = {},
    AudioRouterNames = {},
    RoomCombinerNames = {}
  }

  for _,component in ipairs(Component.GetComponents()) do
    if component.Type == self.componentTypes.roomControls and string.match(component.Name, "^compRoomControls") then
      table.insert(namesTable.RoomControlsNames, component.Name)
    elseif component.Type == self.componentTypes.audioRouter then
      table.insert(namesTable.AudioRouterNames, component.Name)
    elseif component.Type == self.componentTypes.roomCombiner then
      table.insert(namesTable.RoomCombinerNames, component.Name)
    end
  end

  for _, nameList in pairs(namesTable) do
    table.sort(nameList)
    table.insert(nameList, self.clearString)
  end

  self.controls.compRoomCombiner.Choices = namesTable.RoomCombinerNames

  for i, control in ipairs(self.controls.compRoomControls) do
    control.Choices = namesTable.RoomControlsNames
  end

  for i, control in ipairs(self.controls.compAudioRouter) do
    control.Choices = namesTable.AudioRouterNames
  end
  
  self.debugStatus:validateControls()
end

------------------------[ Component Management (Working Pattern) ]------------------------

function DivisibleSpaceController:setComponent(ctrl, componentType)
  if not ctrl then 
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
  elseif #Component.GetControls(Component.New(componentName)) < 1 then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "pink"
    self:setComponentInvalid(componentType)
    return nil
  else
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return Component.New(componentName)
  end
end

function DivisibleSpaceController:setComponentInvalid(componentType)
  self.components.invalid[componentType] = true
  self.debugStatus:checkStatus()
end

function DivisibleSpaceController:setComponentValid(componentType)
  self.components.invalid[componentType] = false
  self.debugStatus:checkStatus()
end

------------------------[ Event Handlers & Selection ]------------------------

function DivisibleSpaceController:_wireEventHandlers()
  -- ComboBox assignment handlers with proper component validation
  assignHandlerIfExists(self.controls.compRoomControls, function()
    local component = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if component then
      self:_updateRoomComponent(self.controls.compRoomControls.String)
    end
  end)
  
  assignHandlerIfExists(self.controls.compAudioRouter, function()
    local component = self:setComponent(self.controls.compAudioRouter, "Audio Router")
    if component then
      self:_updateAudioRouter(self.controls.compAudioRouter.String)
    end
  end)

  assignHandlerIfExists(self.controls.compRoomCombiner, function()
    local component = self:setComponent(self.controls.compRoomCombiner, "Room Combiner")
    if component then
      self.components.roomCombiner = component
      
      -- Wire up the room.combiner.output.configuration control to trigger audio router switching
      if component.Controls and component.Controls["room.combiner.output.configuration"] then
        component.Controls["room.combiner.output.configuration"].EventHandler = function()
          self.audioRouting:applyRouting(component, self.audioRouters, function(msg) self.debugStatus:print(msg) end)
        end
        
        -- Apply initial audio router switching
        self.audioRouting:applyRouting(component, self.audioRouters, function(msg) self.debugStatus:print(msg) end)
      end
    end
  end)

  -- Combination selector (dropdown) handler
  assignHandlerIfExists(self.controls.selCombination, function(ctrl)
    local idx = self:_comboIndexFor(ctrl.String)
    if idx then
      self:setRoomStates(idx)
    end
  end)

  -- Combine button handler
  assignHandlerIfExists(self.controls.btnCombine, function(ctrl)
    local idx = self:_comboIndexFor(self.controls.selCombination.String)
    if idx then
      self:setRoomStates(idx)
    end
  end)

  -- Register wall button handlers
  self.wallControl:registerHandlers()
end

function DivisibleSpaceController:_updateRoomComponent(name)
  local roomIndex = findRoomIndexByComponentName(name, self.roomNames, "compRoomControls")
  if roomIndex then
    self.roomComponents[roomIndex] = name
    self.debugStatus:print("Assigned " .. name .. " to room " .. self.roomNames[roomIndex])
  else
    -- Clear all room components if no match found
    for i, _ in ipairs(self.roomNames) do
      self.roomComponents[i] = nil
    end
  end
end

function DivisibleSpaceController:_updateAudioRouter(name)
  local roomIndex = findRoomIndexByComponentName(name, self.roomNames, "compAudioRouter")
  if roomIndex then
    self.audioRouters[roomIndex] = name
    self.debugStatus:print("Assigned " .. name .. " to room " .. self.roomNames[roomIndex])
  else
    -- Clear all audio routers if no match found
    for i, _ in ipairs(self.roomNames) do
      self.audioRouters[i] = nil
    end
  end
end

function DivisibleSpaceController:_comboIndexFor(comboName)
  for idx, combo in ipairs(self.roomCombinations) do
    if combo.name == comboName then return idx end
  end
  return nil
end

------------------------[ Main Logic: State, Power, Routing ]------------------------

function DivisibleSpaceController:setRoomStates(comboIdx)
  -- Set room states using the RoomState submodule
  if self.roomState:setStates(comboIdx, self.roomCombinations) then
    -- Apply audio router switching based on current room combiner configuration
    if self.components.roomCombiner then
      self.audioRouting:applyRouting(self.components.roomCombiner, self.audioRouters, function(msg) self.debugStatus:print(msg) end)
    end
    
    self.debugStatus:checkStatus()  -- Update status display
    self.wallControl:updateStates()  -- Update wall button states after room state changes
  else
    self.debugStatus:print("Invalid combination index: " .. tostring(comboIdx))
  end
end

------------------------[ Wall Button Controls ]------------------------

-- Wrapper to power a room and always refresh wall buttons
function DivisibleSpaceController:setRoomPower(roomIndex, isOn)
  if self.roomState:setPower(roomIndex, isOn) then
    self.wallControl:updateStates()
  end
end

------------------------[ Cleanup ]------------------------

function DivisibleSpaceController:cleanup()
  assignHandlerIfExists(self.controls.compRoomControls, nil)
  assignHandlerIfExists(self.controls.compAudioRouter, nil)
end

------------------------[ Startup: Instantiate Once ]------------------------

local myDivisibleController = DivisibleSpaceController.new{
  controls = controls,
  roomNames = roomNames,
  roomCombinations = roomCombinations,
  roomPriorities = roomPriorities,
  roomNumberMap = roomNumberMap,
  debugging = true
}
