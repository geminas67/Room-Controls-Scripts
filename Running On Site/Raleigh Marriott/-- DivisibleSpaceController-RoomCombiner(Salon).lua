--[[
  Divisible Space Controller with Room Priority System
  Author: Nikolas Smith
  Date: 2025-08-16
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 1.0 - Refactored for Efficiency and Maintainability
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

-----------------------------[ Configuration Tables ]-----------------------------
local roomNames = {"SalonD", "SalonE", "SalonA", "SalonB", "SalonC", "SalonF", "SalonG", "SalonH"}

-- Room number mapping for audio router logic
local roomNumberMap = {
  SalonD = 1, SalonE = 2, SalonA = 3, SalonB = 4,
  SalonC = 5, SalonF = 6, SalonG = 7, SalonH = 8
}

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
  wallOpenButtons   = Controls.wallOpenButtons
}

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

local function getInputForRoom(roomName, roomGroups, debugPrint)
  local roomNumber = roomNumberMap[roomName]
  if not roomNumber then return 1 end
  
  if debugPrint then
    debugPrint("getInputForRoom: " .. roomName .. " (room #" .. roomNumber .. "), groups count: " .. #roomGroups)
  end
  
  -- If no groups (all separated), each room gets its own input number
  if #roomGroups == 0 then
    if debugPrint then
      debugPrint("  No groups - returning room's own number: " .. roomNumber)
    end
    return roomNumber
  end
  
  -- Check if room is in any group
  for groupIndex, group in ipairs(roomGroups) do
    for _, roomNum in ipairs(group) do
      if roomNum == roomNumber then
        -- Find the highest priority room in this group (lowest room number)
        local highestPriorityRoom = math.huge
        for _, rn in ipairs(group) do
          if rn < highestPriorityRoom then
            highestPriorityRoom = rn
          end
        end
        if debugPrint then
          debugPrint("  Room in group " .. groupIndex .. " - returning highest priority: " .. highestPriorityRoom)
        end
        return highestPriorityRoom
      end
    end
  end
  
  -- If room not found in any group, it's separated and gets its own input
  if debugPrint then
    debugPrint("  Room not in any group - returning room's own number: " .. roomNumber)
  end
  return roomNumber
end

-----------------------------[ Main Controller ]-----------------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debugging)
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Divisible Space"
  self.debugging = debugging or false
  self.clearString = "[Clear]"
  
  -- Component types
  self.componentTypes = {
    roomCombiner = "room_combiner",
    roomControls = "device_controller_script",
    audioRouter = "router_with_output"
  }
  
  -- Component storage
  self.components = {
    roomCombiner = nil,
    roomControls = {},
    audioRouter = {},
    invalid = {roomCombiner = false, roomControls = false, audioRouter = false}
  }
  
  -- Room component arrays
  self.roomComponents = {}
  self.audioRouters = {}
  
  -- Initialize arrays
  for i, _ in ipairs(roomNames) do
    self.roomComponents[i] = nil
    self.audioRouters[i] = nil
  end
  
  self:init()
  return self
end

-----------------[ Debug Helper ]-------------------
function DivisibleSpaceController:debugPrint(str)
  if self.debugging then 
    print("[" .. (self.roomName or "DivisibleSpace") .. "] " .. str) 
  end
end

function DivisibleSpaceController:init()
  self:debugPrint("Starting initialization...")
  self:discoverComponents()
  self:wireEventHandlers()
  self:loadInitialComponents()
  self:checkStatus()
  self:updateWallStates()
  self:debugPrint("Initialization complete")
end

function DivisibleSpaceController:loadInitialComponents()
  self:debugPrint("Loading initial component assignments...")
  
  -- Load room control components
  for i, control in ipairs(controls.compRoomControls) do
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading room control " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "roomControls")
      if component then
        self:updateRoomComponent(control.String, i)
        self:debugPrint("Loaded room component " .. i .. " (" .. control.String .. ")")
      end
    end
  end
  
  -- Load audio router components  
  for i, control in ipairs(controls.compAudioRouter) do
    if control.String and control.String ~= "" and control.String ~= self.clearString then
      self:debugPrint("Loading audio router " .. i .. ": " .. control.String)
      local component = self:setComponent(control, "audioRouter")
      if component then
        self:updateAudioRouter(control.String, i)
        self:debugPrint("Loaded audio router " .. i .. " (" .. control.String .. ")")
      end
    end
  end
  
  -- Load room combiner component
  if controls.compRoomCombiner.String and controls.compRoomCombiner.String ~= "" and controls.compRoomCombiner.String ~= self.clearString then
    self:debugPrint("Loading room combiner: " .. controls.compRoomCombiner.String)
    local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if component then
      self.components.roomCombiner = component
      self:debugPrint("Loaded room combiner (" .. controls.compRoomCombiner.String .. ")")
      
      -- Set up the configuration change handler
      if component.Controls and component.Controls["room.combiner.output.configuration"] then
        self:debugPrint("Setting up room.combiner.output.configuration event handler")
        component.Controls["room.combiner.output.configuration"].EventHandler = function()
          self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting")
          self:applyAudioRouting()
        end
        
        -- Apply initial routing
        self:debugPrint("Applying initial audio routing")
        self:applyAudioRouting()
      end
      
      -- Sync UI wall buttons with room combiner wall states
      self:syncWallButtonStates()
      
      -- Set up wall control event handlers for external changes
      self:setupWallControlEventHandlers()
    end
  end
  
  -- Debug wall control discovery
  self:debugPrint("Checking wall control setup...")
  local foundWallControls = 0
  if controls.wallOpenButtons then
    for i = 1, 11 do
      if controls.wallOpenButtons[i] then
        foundWallControls = foundWallControls + 1
      end
    end
    self:debugPrint("Wall controls found: " .. foundWallControls .. "/11")
  else
    self:debugPrint("ERROR: Controls.wallOpenButtons table not found!")
  end
  
  self:debugPrint("Initial component loading complete")
end

function DivisibleSpaceController:syncWallButtonStates()
  self:debugPrint("Syncing UI wall buttons with room combiner wall states...")
  
  if not self.components.roomCombiner then
    self:debugPrint("No room combiner available for wall sync")
    return
  end
  
  local syncedWalls = 0
  local syncErrors = {}
  
  for i = 1, 11 do
    local wallButton = controls.wallOpenButtons[i]
    if wallButton then
      local wallControlName = "wall." .. i .. ".open"
      local wallControl = self.components.roomCombiner[wallControlName]
      
      if wallControl then
        local combinerState = wallControl.Boolean
        wallButton.Boolean = combinerState
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

function DivisibleSpaceController:setupWallControlEventHandlers()
  self:debugPrint("Setting up room combiner wall control event handlers...")
  
  if not self.components.roomCombiner then
    self:debugPrint("No room combiner available for wall event handlers")
    return
  end
  
  local handlersSetup = 0
  
  for i = 1, 11 do
    local wallControlName = "wall." .. i .. ".open"
    local wallControl = self.components.roomCombiner[wallControlName]
    
    if wallControl then
      wallControl.EventHandler = function()
        local combinerState = wallControl.Boolean
        local wallButton = controls.wallOpenButtons[i]
        
        if wallButton then
          -- Sync UI button with room combiner state
          wallButton.Boolean = combinerState
          
          local wallPair = wallRoomPairs[i]
          if wallPair then
            self:debugPrint("External wall change detected - Wall " .. i .. " (" .. wallPair[1] .. "/" .. wallPair[2] .. "): " .. 
                            wallControlName .. " = " .. tostring(combinerState) .. " (rooms " .. 
                            (combinerState and "COMBINED" or "SEPARATED") .. ")")
          end
          
          -- Update wall button states for safety logic
          self:updateWallStates()
        end
      end
      handlersSetup = handlersSetup + 1
    end
  end
  
  self:debugPrint("Wall control event handlers setup: " .. handlersSetup .. "/11 successful")
end

function DivisibleSpaceController:discoverComponents()
  local namesTable = {
    RoomControlsNames = {},
    AudioRouterNames = {},
    RoomCombinerNames = {}
  }

  for _, component in ipairs(Component.GetComponents()) do
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

  controls.compRoomCombiner.Choices = namesTable.RoomCombinerNames
  
  for i, control in ipairs(controls.compRoomControls) do
    control.Choices = namesTable.RoomControlsNames
  end

  for i, control in ipairs(controls.compAudioRouter) do
    control.Choices = namesTable.AudioRouterNames
  end
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
  local controls = Component.GetControls(component)
  if not controls or #controls < 1 then
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

function DivisibleSpaceController:wireEventHandlers()
  self:debugPrint("Setting up event handlers...")
  
  -- Room controls handlers
  for i, control in ipairs(controls.compRoomControls) do
    control.EventHandler = function()
      self:debugPrint("Room control " .. i .. " changed to: " .. tostring(control.String))
      local component = self:setComponent(control, "roomControls")
      if component then
        self:updateRoomComponent(control.String, i)
        self:debugPrint("Room component " .. i .. " (" .. control.String .. ") updated successfully")
      else
        -- Clear the component name if invalid
        self:updateRoomComponent("", i)
      end
    end
  end
  
  -- Audio router handlers
  for i, control in ipairs(controls.compAudioRouter) do
    control.EventHandler = function()
      self:debugPrint("Audio router " .. i .. " changed to: " .. tostring(control.String))
      local component = self:setComponent(control, "audioRouter")
      if component then
        self:updateAudioRouter(control.String, i)
        self:debugPrint("Audio router " .. i .. " (" .. control.String .. ") updated successfully")
      else
        -- Clear the component name if invalid
        self:updateAudioRouter("", i)
      end
    end
  end

  -- Room combiner handler
  controls.compRoomCombiner.EventHandler = function()
    self:debugPrint("Room combiner control changed to: " .. tostring(controls.compRoomCombiner.String))
    local component = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if component then
      self:debugPrint("Room combiner component successfully assigned: " .. component.Name)
      self.components.roomCombiner = component
      
      if component.Controls and component.Controls["room.combiner.output.configuration"] then
        self:debugPrint("Setting up room.combiner.output.configuration event handler")
        component.Controls["room.combiner.output.configuration"].EventHandler = function()
          self:debugPrint("room.combiner.output.configuration changed - calling applyAudioRouting")
          self:applyAudioRouting()
        end
        
        -- Apply initial routing
        self:debugPrint("Applying initial audio routing")
        self:applyAudioRouting()
      else
        self:debugPrint("ERROR: room.combiner.output.configuration control NOT FOUND!")
      end
    else
      self:debugPrint("ERROR: Room combiner component assignment FAILED")
    end
  end

  -- Note: selCombination is no longer used - wall controls now drive room combinations directly

  -- Wall button handlers
  for i, wallButton in ipairs(controls.wallOpenButtons) do
    if wallButton then
      wallButton.EventHandler = function()
        local wallPair = wallRoomPairs[i]
        if wallPair then
          local room1, room2 = wallPair[1], wallPair[2]
          local uiState = wallButton.Boolean  -- UI button state
          
          -- Safety check - don't allow wall operation if either room is powered on
          local room1On = self:isRoomPoweredOn(room1)
          local room2On = self:isRoomPoweredOn(room2)
          
          if room1On or room2On then
            -- Revert the button state
            wallButton.Boolean = not uiState
            self:debugPrint("SAFETY BLOCK: Wall " .. i .. " (" .. room1 .. "/" .. room2 .. ") operation blocked - " .. room1 .. ":" .. (room1On and "ON" or "OFF") .. ", " .. room2 .. ":" .. (room2On and "ON" or "OFF"))
            return
          end
          
          -- Update the actual wall control on compRoomCombiner
          -- Note: Logic is inverted - wall.X.open.Boolean true = closed/combined, false = open/separated
          if self.components.roomCombiner then
            local wallControlName = "wall." .. i .. ".open"
            local wallControl = self.components.roomCombiner[wallControlName]
            if wallControl then
              -- Set the room combiner wall control (inverted logic)
              wallControl.Boolean = uiState  -- UI and room combiner should match for consistency
              self:debugPrint("Wall " .. i .. " (" .. room1 .. "/" .. room2 .. ") control updated: " .. wallControlName .. " = " .. tostring(uiState) .. " (rooms " .. (uiState and "COMBINED" or "SEPARATED") .. ")")
            else
              self:debugPrint("ERROR: Wall control " .. wallControlName .. " not found on room combiner")
              -- Revert UI button
              wallButton.Boolean = not uiState
            end
          else
            self:debugPrint("ERROR: No room combiner component available")
            -- Revert UI button  
            wallButton.Boolean = not uiState
          end
        end
        self:updateWallStates()
      end
    end
  end
  
  self:debugPrint("Event handlers setup complete")
end

function DivisibleSpaceController:updateRoomComponent(name, roomIndex)
  if roomIndex and roomIndex >= 1 and roomIndex <= #roomNames then
    local oldName = self.roomComponents[roomIndex]
    self.roomComponents[roomIndex] = name
    if oldName ~= name then
      self:debugPrint("Room component " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
      self:checkStatus()
    end
  end
end

function DivisibleSpaceController:updateAudioRouter(name, roomIndex)
  if roomIndex and roomIndex >= 1 and roomIndex <= #roomNames then
    local oldName = self.audioRouters[roomIndex]
    self.audioRouters[roomIndex] = name
    if oldName ~= name then
      self:debugPrint("Audio router " .. roomIndex .. " (" .. roomNames[roomIndex] .. ") updated: '" .. (oldName or "") .. "' -> '" .. (name or "") .. "'")
      self:checkStatus()
    end
  end
end

function DivisibleSpaceController:getComboIndex(comboName)
  for idx, combo in ipairs(roomCombinations) do
    if combo.name == comboName then return idx end
  end
  return nil
end

function DivisibleSpaceController:setRoomStates(comboIdx)
  local combo = roomCombinations[comboIdx]
  if not combo then 
    self:debugPrint("ERROR: Invalid combination index: " .. tostring(comboIdx))
    return false 
  end

  self:debugPrint("Applying room combination: " .. combo.name)
  
  local roomStateErrors = {}
  local successfulRoomStates = 0
  
  -- Set room power states
  for i, roomName in ipairs(roomNames) do
    local compName = self.roomComponents[i]
    if compName and compName ~= "" then
      local comp = Component.New(compName)
      if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
        local isActive = combo.activeRooms[roomName] or false
        comp.Controls["btnSystemOnOff"].Boolean = isActive
        successfulRoomStates = successfulRoomStates + 1
        self:debugPrint("Room " .. roomName .. " (" .. compName .. ") -> " .. (isActive and "ON" or "OFF"))
      else
        local errorMsg = roomName .. ": Component or btnSystemOnOff control not found"
        table.insert(roomStateErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      self:debugPrint("SKIP: " .. roomName .. " - no component assigned")
    end
  end
  
  self:debugPrint("Room states applied: " .. successfulRoomStates .. "/" .. #roomNames .. " successful")
  if #roomStateErrors > 0 then
    self:debugPrint("Room state errors: " .. #roomStateErrors)
    for _, error in ipairs(roomStateErrors) do
      self:debugPrint("  - " .. error)
    end
  end
  
  -- Apply audio routing
  if self.components.roomCombiner then
    self:debugPrint("Applying audio routing for combination...")
    self:applyAudioRouting()
  else
    self:debugPrint("SKIP: Audio routing - no room combiner component")
  end
  
  self:checkStatus()
  self:updateWallStates()
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
  
  self:debugPrint("Audio routing config string: '" .. tostring(configString) .. "'")
  self:debugPrint("Parsed room groups count: " .. #roomGroups)
  for i, group in ipairs(roomGroups) do
    self:debugPrint("Group " .. i .. ": [" .. table.concat(group, ", ") .. "]")
  end
  
  -- Debug room number mapping
  self:debugPrint("Room number mapping:")
  for roomName, roomNum in pairs(roomNumberMap) do
    self:debugPrint("  " .. roomName .. " = " .. roomNum)
  end
  
  -- Debug current audio router assignments
  self:debugPrint("Current audio router assignments:")
  for i, roomName in ipairs(roomNames) do
    local routerName = self.audioRouters[i] or "NONE"
    self:debugPrint("  " .. i .. ". " .. roomName .. " -> " .. routerName)
  end
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  -- Apply audio router inputs for each room
  for i, roomName in ipairs(roomNames) do
    local routerName = self.audioRouters[i]
    self:debugPrint("Processing room " .. i .. ": " .. roomName .. " (router: " .. (routerName or "NONE") .. ")")
    
    if routerName and routerName ~= "" then
      local comp = Component.New(routerName)
      if comp and comp.Controls and comp.Controls["select.1"] then
        local inputNumber = getInputForRoom(roomName, roomGroups, function(msg) self:debugPrint("Router logic: " .. msg) end)
        local currentValue = comp.Controls["select.1"].Value
        self:debugPrint("Setting " .. roomName .. " (" .. routerName .. ") -> Input " .. inputNumber .. " (was " .. currentValue .. ")")
        
        -- Validate input number is reasonable
        if inputNumber >= 1 and inputNumber <= 16 then
          comp.Controls["select.1"].Value = inputNumber
          successfulRoutings = successfulRoutings + 1
          -- Verify the value was set
          local newValue = comp.Controls["select.1"].Value
          self:debugPrint("SUCCESS: " .. roomName .. " routed to input " .. inputNumber .. " (verified: " .. newValue .. ")")
        else
          local errorMsg = roomName .. ": Invalid input number " .. inputNumber
          table.insert(routingErrors, errorMsg)
          self:debugPrint("ERROR: " .. errorMsg)
        end
      else
        local errorMsg = roomName .. ": Router component or control not found"
        table.insert(routingErrors, errorMsg)
        self:debugPrint("ERROR: " .. errorMsg)
      end
    else
      self:debugPrint("SKIP: " .. roomName .. " - no router assigned")
    end
  end
  
  -- Summary
  self:debugPrint("Audio routing complete: " .. successfulRoutings .. "/" .. #roomNames .. " successful")
  if #routingErrors > 0 then
    self:debugPrint("Routing errors: " .. #routingErrors)
    for _, error in ipairs(routingErrors) do
      self:debugPrint("  - " .. error)
    end
  end
end

function DivisibleSpaceController:updateWallStates()
  self:debugPrint("Updating wall states...")
  
  local wallStatesUpdated = 0
  local wallStateErrors = {}
  
  for wallIndex, roomPair in pairs(wallRoomPairs) do
    local room01 = roomPair[1]
    local room02 = roomPair[2]
    local isRoom01On = self:isRoomPoweredOn(room01)
    local isRoom02On = self:isRoomPoweredOn(room02)
    local wallButton = controls.wallOpenButtons[wallIndex]
    
    if wallButton then
      local shouldDisable = (isRoom01On or isRoom02On)
      wallButton.IsDisabled = shouldDisable
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

function DivisibleSpaceController:isRoomPoweredOn(roomName)
  for i, rn in ipairs(roomNames) do
    if rn == roomName then
      if self.roomComponents[i] and self.roomComponents[i] ~= "" then
        local comp = Component.New(self.roomComponents[i])
        if comp and comp.Controls and comp.Controls["btnSystemOnOff"] then
          local isOn = comp.Controls["btnSystemOnOff"].Boolean
          -- Only log if detailed debugging is needed
          -- self:debugPrint("Room " .. roomName .. " power state: " .. (isOn and "ON" or "OFF"))
          return isOn
        else
          -- Component or control not found
          return false
        end
      else
        -- No component assigned for this room
        return false
      end
    end
  end
  return false
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
  for i, roomName in ipairs(roomNames) do
    if self.roomComponents[i] and self.roomComponents[i] ~= "" then
      connectedRooms = connectedRooms + 1
    end
  end
  
  -- Check audio routers
  local connectedRouters = 0
  for i, routerName in ipairs(self.audioRouters) do
    if routerName and routerName ~= "" then
      connectedRouters = connectedRouters + 1
    end
  end
  
  self:debugPrint("Status check: " .. validComponentCount .. "/" .. totalComponentCount .. " components valid")
  self:debugPrint("Connected room components: " .. connectedRooms .. "/" .. #roomNames)
  self:debugPrint("Connected audio routers: " .. connectedRouters .. "/" .. #roomNames)
  
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
      controls.txtStatus.String = statusMsg
      controls.txtStatus.Value = 0
      self:debugPrint("STATUS: " .. statusMsg)
    end
  end
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
      local routerName = myDivisibleController.audioRouters[i]
      if routerName and routerName ~= "" then
        local comp = Component.New(routerName)
        if comp and comp.Controls and comp.Controls["select.1"] then
          local currentInput = comp.Controls["select.1"].Value
          myDivisibleController:debugPrint(roomName .. " (" .. routerName .. ") current input: " .. currentInput)
        else
          myDivisibleController:debugPrint(roomName .. " (" .. routerName .. ") - COMPONENT/CONTROL NOT FOUND")
        end
      else
        myDivisibleController:debugPrint(roomName .. " - NO ROUTER ASSIGNED")
      end
    end
    myDivisibleController:debugPrint("=== END ROUTER STATES DEBUG ===")
  else
    print("ERROR: myDivisibleController not initialized")
  end
end

------------------------[ Startup ]------------------------
local myDivisibleController = DivisibleSpaceController.new("Raleigh Marriott Salon", true)
