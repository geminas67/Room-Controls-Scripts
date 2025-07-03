--[[
  Divisible Space Controller with Room Combiner, Audio Routing, and UCI Switching
  Author: Nikolas Smith
  Date: 2025-07-02
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 3.1 - Ultra-Optimized with Room Controls Integration
]]

--------** Dynamic Configuration **--------

-- Dynamic component discovery and caching
local componentCache = {}
local roomCombinerComponents = {}
local roomControllerComponents = {}
local uciComponents = {}
local tscDevices = {}

-- Room configuration with dynamic discovery
local roomNames = {"A", "B", "C", "D"}
local roomCombinations = {
  { name = "All Separated",        rooms = {"A","B","C","D"},      combiner = "1 2 3 4",       uci = "UCI_Separated" },
  { name = "A+B Combined",         rooms = {"A+B","C","D"},        combiner = "1+2 3 4",       uci = "UCI_AB" },
  { name = "B+C Combined",         rooms = {"A","B+C","D"},        combiner = "1 2+3 4",       uci = "UCI_BC" },
  { name = "C+D Combined",         rooms = {"A","B","C+D"},        combiner = "1 2 3+4",       uci = "UCI_CD" },
  { name = "A+B, C+D Combined",    rooms = {"A+B","C+D"},          combiner = "1+2 3+4",       uci = "UCI_AB_CD" },
  { name = "A+B+C Combined",       rooms = {"A+B+C","D"},          combiner = "1+2+3 4",       uci = "UCI_ABC" },
  { name = "B+C+D Combined",       rooms = {"A","B+C+D"},          combiner = "1 2+3+4",       uci = "UCI_BCD" },
  { name = "All Combined",         rooms = {"A+B+C+D"},            combiner = "1+2+3+4",       uci = "UCI_All" }
}

-- Pre-built lookup tables for O(1) access
local combinationLookup = {}
local roomIndexMap = { A=1, B=2, C=3, D=4 }

for i, combo in ipairs(roomCombinations) do
  combinationLookup[combo.name] = i
end

--------** Ultra-Fast Component Discovery **--------

local function discoverComponents()
  -- Single-pass component discovery for maximum speed
  local allComponents = Component.GetComponents()
  
  for _, comp in ipairs(allComponents) do
    local compName = comp.Name
    local compType = comp.Type
    
    -- Cache component by name for O(1) access
    componentCache[compName] = comp
    
    -- Categorize components by type
    if compType == "Room Combiner" then
      table.insert(roomCombinerComponents, comp)
    elseif compType == "device_controller_script" then
      -- Discover Room Controller components (SystemAutomationController instances)
      local testComp = Component.New(compName)
      if testComp["roomName"] or testComp["selDefaultConfigs"] then
        table.insert(roomControllerComponents, comp)
      end
    elseif compType == "UCI" then
      uciComponents[compName] = comp
    elseif compType == "TSC" then
      -- Extract room identifier from TSC device name
      for _, room in ipairs(roomNames) do
        if compName:find("UCI" .. room) or compName:find("TSC" .. room) then
          tscDevices[room] = comp
          break
        end
      end
    end
  end
end

--------** Room Controller Component Management **--------

local function getRoomControllerNames()
  local namesTable = { RoomControllerNames = {} }
  for _, comp in ipairs(roomControllerComponents) do
    table.insert(namesTable.RoomControllerNames, comp.Name)
  end
  table.sort(namesTable.RoomControllerNames)
  table.insert(namesTable.RoomControllerNames, "[Clear]")
  return namesTable.RoomControllerNames
end

local function setRoomControllerComponent(ctrl, componentType)
  if not ctrl then return nil end
  local componentName = ctrl.String
  if componentName == "" or componentName == "[Clear]" then
    ctrl.Color = "White"
    return nil
  end
  local testComponent = Component.New(componentName)
  if #Component.GetControls(testComponent) < 1 then
    ctrl.String = "[Invalid Component Selected]"
    ctrl.Color = "Pink"
    return nil
  end
  ctrl.Color = "White"
  return testComponent
end

--------** Dynamic Combo Box Population **--------

local function populateComponentComboBoxes()
  -- Populate Room Combiner combo box
  if Controls.selRoomCombiner then
    local choices = {}
    for i, comp in ipairs(roomCombinerComponents) do
      choices[i] = comp.Name
    end
    Controls.selRoomCombiner.Choices = choices
    if #choices > 0 then
      Controls.selRoomCombiner.String = choices[1]
    end
  end
  
  -- Populate Room Controller combo boxes
  local roomControllerNames = getRoomControllerNames()
  for _, room in ipairs(roomNames) do
    local controlName = "selRoomController" .. room
    if Controls[controlName] then
      Controls[controlName].Choices = roomControllerNames
      if #roomControllerNames > 1 then
        Controls[controlName].String = roomControllerNames[1]
      end
    end
  end
  
  -- Populate UCI combo boxes
  if Controls.selUCI then
    local choices = {}
    for compName, comp in pairs(uciComponents) do
      table.insert(choices, compName)
    end
    Controls.selUCI.Choices = choices
    if #choices > 0 then
      Controls.selUCI.String = choices[1]
    end
  end
end

--------** State Management **--------
local currentCombinationIndex = 1
local isInitialized = false
local selectedRoomCombiner = nil
local selectedUCIs = {}
local roomControllers = {}

--------** Ultra-Optimized Core Functions **--------

-- Direct room combiner control with component selection
local function setRoomCombinerState(stateString)
  local combiner = selectedRoomCombiner or roomCombinerComponents[1]
  if combiner and combiner.Rooms then
    combiner.Rooms.String = stateString
  end
end

-- Optimized UCI switching with dynamic component selection
local function switchUCIs(uciName)
  -- Use selected UCI or fall back to discovered components
  local targetUCI = selectedUCIs[uciName] or uciComponents[uciName]
  
  if targetUCI then
    -- Single UCI switch for maximum speed
    for _, tsc in pairs(tscDevices) do
      if tsc and tsc.UCI then
        tsc.UCI.String = uciName
      end
    end
  else
    -- Fallback to direct UCI switching
    Uci.SetUCI("UCIRmA", uciName)
    Uci.SetUCI("UCIRmB", uciName)
    Uci.SetUCI("UCIRmC", uciName)
    Uci.SetUCI("UCIRmD", uciName)
  end
end

-- Room Controller power management
local function updateRoomControllerPower(activeRooms)
  for room, isActive in pairs(activeRooms) do
    local roomController = roomControllers[room]
    if roomController and roomController["btnSystemOnOff"] then
      roomController["btnSystemOnOff"].Boolean = isActive
    end
  end
end

-- Optimized active rooms map builder
local function buildActiveRoomsMap(combo)
  local activeRooms = {}
  for _, r in ipairs(combo.rooms) do
    if r:find("+") then
      for part in r:gmatch("[^+]+") do 
        activeRooms[part] = true 
      end
    else
      activeRooms[r] = true
    end
  end
  return activeRooms
end

-- Fast state notification
local function publishRoomState(combo)
  if Notifications and Notifications.Publish then
    Notifications.Publish("DivisibleRoomState", {
      name = combo.name,
      rooms = combo.rooms,
      combiner = combo.combiner,
      uci = combo.uci,
      timestamp = Timer.Now()
    })
  end
end

--------** Main Application Function **--------

local function applyCombination(index)
  if not index or index < 1 or index > #roomCombinations then return end
  
  currentCombinationIndex = index
  local combo = roomCombinations[index]
  
  -- Execute all operations with minimal overhead
  setRoomCombinerState(combo.combiner)
  switchUCIs(combo.uci)
  
  local activeRooms = buildActiveRoomsMap(combo)
  updateRoomControllerPower(activeRooms)
  publishRoomState(combo)
  
  -- Update UI state immediately
  if Controls.selRoomCombination then
    Controls.selRoomCombination.String = combo.name
  end
end

--------** Event-Driven Control Handlers **--------

-- Dynamic component selection handlers
if Controls.selRoomCombiner then
  Controls.selRoomCombiner.EventHandler = function(ctl)
    selectedRoomCombiner = componentCache[ctl.String]
    -- Re-apply current combination with new component
    if isInitialized then
      applyCombination(currentCombinationIndex)
    end
  end
end

-- Dynamic Room Controller selection handlers
for _, room in ipairs(roomNames) do
  local controlName = "selRoomController" .. room
  if Controls[controlName] then
    Controls[controlName].EventHandler = function(ctl)
      local component = setRoomControllerComponent(ctl, "Room Controller " .. room)
      if component then
        roomControllers[room] = component
        -- Re-apply current combination with new component
        if isInitialized then
          applyCombination(currentCombinationIndex)
        end
      else
        roomControllers[room] = nil
      end
    end
  end
end

-- Dynamic UCI selection handler
if Controls.selUCI then
  Controls.selUCI.EventHandler = function(ctl)
    selectedUCIs[ctl.String] = componentCache[ctl.String]
    -- Re-apply current combination with new UCI
    if isInitialized then
      applyCombination(currentCombinationIndex)
    end
  end
end

-- Optimized room combination dropdown handler
if Controls.selRoomCombination then
  -- Pre-build choices array once
  local choices = {}
  for i, combo in ipairs(roomCombinations) do
    choices[i] = combo.name
  end
  Controls.selRoomCombination.Choices = choices
  
  -- Ultra-fast event handler with direct lookup
  Controls.selRoomCombination.EventHandler = function(ctl)
    local index = combinationLookup[ctl.String]
    if index then
      applyCombination(index)
    end
  end
end

--------** Direct Button Handlers for Instant Response **--------

-- Pre-built button handlers for maximum speed
local buttonHandlers = {
  btnAllSeparated = 1,
  btnABCombined = 2,
  btnBCCombined = 3,
  btnCDCombined = 4,
  btnABCDCombined = 5,
  btnABCCombined = 6,
  btnBCDCombined = 7,
  btnAllCombined = 8
}

for controlName, index in pairs(buttonHandlers) do
  if Controls[controlName] then
    Controls[controlName].EventHandler = function()
      applyCombination(index)
    end
  end
end

--------** Partition Wall Sensors with Immediate Response **--------

-- Optimized partition wall handlers
local partitionHandlers = {
  partitionWallAB = { combined = 2, separated = 1 },
  partitionWallBC = { combined = 3, separated = 1 },
  partitionWallCD = { combined = 4, separated = 1 }
}

for controlName, states in pairs(partitionHandlers) do
  if Controls[controlName] then
    Controls[controlName].EventHandler = function(ctl)
      local targetIndex = ctl.Boolean and states.combined or states.separated
      applyCombination(targetIndex)
    end
  end
end

--------** System Initialization **--------

local function initializeSystem()
  if isInitialized then return end
  
  -- Discover all components dynamically
  discoverComponents()
  
  -- Populate combo boxes with discovered components
  populateComponentComboBoxes()
  
  -- Apply default combination
  applyCombination(1)
  
  isInitialized = true
  
  -- Publish initialization complete
  if Notifications and Notifications.Publish then
    Notifications.Publish("DivisibleSpaceInitialized", {
      roomCombinerCount = #roomCombinerComponents,
      roomControllerCount = #roomControllerComponents,
      uciComponentCount = #uciComponents,
      tscDeviceCount = #tscDevices
    })
  end
end

-- Execute initialization immediately
initializeSystem()

--------** Performance Monitoring (Optional) **--------

-- Add performance monitoring if debug controls exist
if Controls.btnPerformanceTest then
  Controls.btnPerformanceTest.EventHandler = function()
    local startTime = Timer.Now()
    
    -- Test all combinations
    for i = 1, #roomCombinations do
      applyCombination(i)
    end
    
    local endTime = Timer.Now()
    local duration = endTime - startTime
    
    if Notifications and Notifications.Publish then
      Notifications.Publish("PerformanceTest", {
        totalCombinations = #roomCombinations,
        totalDuration = duration,
        averagePerCombination = duration / #roomCombinations
      })
    end
  end
end

--------** End of Script **--------

-- Ultra-Performance Optimizations Applied:
-- 1. Dynamic component discovery using Component.GetComponents() in single pass
-- 2. Enhanced combo box usage for all component selections
-- 3. Pre-built lookup tables for O(1) access to all data structures
-- 4. Event-driven architecture with immediate response
-- 5. Component caching for O(1) access throughout script lifecycle
-- 6. Optimized button handlers with pre-built mapping
-- 7. Minimal function call overhead in critical paths
-- 8. Dynamic UCI and Room Controller component selection
-- 9. Immediate state updates without polling
-- 10. Performance monitoring capabilities
-- 11. Reduced memory allocations and garbage collection pressure
-- 12. Shallow call stack for all event handlers
-- 13. Room Controller integration using SystemAutomationController instances
-- 14. Removed gain component functionality (handled by SystemAutomationController)

-- Usage:
-- 1. Add Room Combiner objects to your schematic (automatically discovered)
-- 2. Add SystemAutomationController instances (automatically discovered as Room Controllers)
-- 3. Add UCI components (automatically discovered)
-- 4. Add TSC devices with names containing room identifiers (e.g., "UCIRmA", "TSCB")
-- 5. Create combo box controls for component selection:
--    - selRoomCombiner: Select which Room Combiner to use
--    - selRoomControllerA, selRoomControllerB, etc.: Select Room Controller components for each room
--    - selUCI: Select UCI components
-- 6. Create dropdown control "selRoomCombination" for manual state selection
-- 7. Optional: Add direct button controls for instant access to common combinations
-- 8. Optional: Add partition wall sensors for automatic response
-- 9. Optional: Add btnPerformanceTest for performance monitoring
-- 10. Room Controllers handle gain settings through SystemAutomationController instances
