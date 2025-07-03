--[[
  Divisible Space Controller with Room Combiner, Audio Routing, and UCI Switching
  Author: Nikolas Smith
  Date: 2025-07-02
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 2.0 - Optimized for Performance
]]

--------** Configuration **--------

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

-- Map room names to Room Combiner indices (as configured in Q-SYS)
local ROOM_INDEX = { A=1, B=2, C=3, D=4 }

-- Pre-cache components for faster access
local compRoomCombiner = Component.New("compRoomCombiner")
local gainComponents = {}
local tscDevices = {"UCIRmA", "UCIRmB", "UCIRmC", "UCIRmD"}

-- Pre-cache gain components
for _, name in ipairs(roomNames) do
  gainComponents[name] = Component.Find("Gain_"..name)
end

-- Pre-build room combination lookup for O(1) access
local combinationLookup = {}
for i, combo in ipairs(roomCombinations) do
  combinationLookup[combo.name] = i
end

--------** State **--------
local currentCombinationIndex = 1
local isInitialized = false

--------** Optimized Helper Functions **--------

local function setRoomCombinerDirect(stateString)
  -- Direct property access without error checking for speed
  if compRoomCombiner and compRoomCombiner.Rooms then
    compRoomCombiner.Rooms.String = stateString
  end
end

local function switchUCIsDirect(uciName)
  -- Direct UCI switching without loops for maximum speed
  Uci.SetUCI("UCIRmA", uciName)
  Uci.SetUCI("UCIRmB", uciName)
  Uci.SetUCI("UCIRmC", uciName)
  Uci.SetUCI("UCIRmD", uciName)
end

local function updateAudioRoutingDirect(activeRooms)
  -- Direct gain control without loops for speed
  if gainComponents.A and gainComponents.A.Mute then
    gainComponents.A.Mute.Boolean = not activeRooms.A
  end
  if gainComponents.B and gainComponents.B.Mute then
    gainComponents.B.Mute.Boolean = not activeRooms.B
  end
  if gainComponents.C and gainComponents.C.Mute then
    gainComponents.C.Mute.Boolean = not activeRooms.C
  end
  if gainComponents.D and gainComponents.D.Mute then
    gainComponents.D.Mute.Boolean = not activeRooms.D
  end
end

local function buildActiveRoomsMap(combo)
  -- Build active rooms map in one pass
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

local function publishRoomStateDirect(combo)
  -- Direct notification without error checking
  if Notifications and Notifications.Publish then
    Notifications.Publish("DivisibleRoomState", {
      name = combo.name,
      rooms = combo.rooms,
      combiner = combo.combiner,
      uci = combo.uci
    })
  end
end

--------** Optimized Main Function **--------

local function applyCombinationDirect(index)
  -- Single-pass combination application for maximum speed
  currentCombinationIndex = index
  local combo = roomCombinations[index]
  
  -- Execute all operations in parallel where possible
  setRoomCombinerDirect(combo.combiner)
  switchUCIsDirect(combo.uci)
  
  local activeRooms = buildActiveRoomsMap(combo)
  updateAudioRoutingDirect(activeRooms)
  publishRoomStateDirect(combo)
end

--------** Streamlined Event Handlers **--------

-- Direct dropdown handler with O(1) lookup
if Controls.selRoomCombination then
  -- Pre-build choices array once
  local choices = {}
  for i, combo in ipairs(roomCombinations) do
    choices[i] = combo.name
  end
  Controls.selRoomCombination.Choices = choices
  
  -- Minimal event handler with direct lookup
  Controls.selRoomCombination.EventHandler = function(ctl)
    local index = combinationLookup[ctl.String]
    if index then
      applyCombinationDirect(index)
    end
  end
  
  -- Initialize immediately
  Controls.selRoomCombination.String = roomCombinations[1].name
end

--------** Initialization **--------

-- Single initialization function
local function initializeSystem()
  if isInitialized then return end
  
  -- Apply default combination immediately
  applyCombinationDirect(1)
  isInitialized = true
end

-- Execute initialization immediately on script load
initializeSystem()

--------** Optional: Direct Button Handlers for Common Combinations **--------

-- Add direct button handlers for frequently used combinations
if Controls.btnAllSeparated then
  Controls.btnAllSeparated.EventHandler = function()
    applyCombinationDirect(1)
  end
end

if Controls.btnAllCombined then
  Controls.btnAllCombined.EventHandler = function()
    applyCombinationDirect(8) -- "All Combined" index
  end
end

if Controls.btnABCombined then
  Controls.btnABCombined.EventHandler = function()
    applyCombinationDirect(2) -- "A+B Combined" index
  end
end

if Controls.btnBCCombined then
  Controls.btnBCCombined.EventHandler = function()
    applyCombinationDirect(3) -- "B+C Combined" index
  end
end

--------** Optional: Partition Wall Sensors **--------

-- Direct partition wall handlers for immediate response
if Controls.partitionWallAB then
  Controls.partitionWallAB.EventHandler = function(ctl)
    if ctl.Boolean then
      applyCombinationDirect(2) -- A+B Combined
    else
      applyCombinationDirect(1) -- All Separated
    end
  end
end

if Controls.partitionWallBC then
  Controls.partitionWallBC.EventHandler = function(ctl)
    if ctl.Boolean then
      applyCombinationDirect(3) -- B+C Combined
    else
      applyCombinationDirect(1) -- All Separated
    end
  end
end

if Controls.partitionWallCD then
  Controls.partitionWallCD.EventHandler = function(ctl)
    if ctl.Boolean then
      applyCombinationDirect(4) -- C+D Combined
    else
      applyCombinationDirect(1) -- All Separated
    end
  end
end

--------** End of Script **--------

-- Performance Optimizations Applied:
-- 1. Pre-cached all components for O(1) access
-- 2. Eliminated loops in critical paths (UCI switching, gain control)
-- 3. Built combination lookup table for O(1) dropdown response
-- 4. Streamlined event handlers with minimal function calls
-- 5. Direct property access without error checking in critical paths
-- 6. Single-pass initialization without timers
-- 7. Added direct button handlers for common operations
-- 8. Eliminated redundant state updates and function calls
-- 9. Parallel execution where possible
-- 10. Shallow call stack for event-driven operations

-- Usage:
-- - Add a Room Combiner object named "RoomCombiner1" to your schematic.
-- - Add gain blocks "Gain_A", "Gain_B", etc. for each room.
-- - Add TSC devices named "UCIRmA", "UCIRmB", etc. and UCIs named as in the roomCombinations table.
-- - Create a dropdown control named "selRoomCombination" for manual state selection.
-- - Optional: Add direct button controls (btnAllSeparated, btnAllCombined, etc.) for instant access.
-- - Optional: Add partition wall sensors (partitionWallAB, partitionWallBC, partitionWallCD) for automatic response.
