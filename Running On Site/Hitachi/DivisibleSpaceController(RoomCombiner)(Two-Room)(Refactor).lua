--[[
  Divisible Space Controller - Two Room Version (Refactored, State-Based)
  Author: Nikolas Smith, Q-SYS
  Version: 2.0 | Date: 2025-11-18
  Firmware Req: 10.0.1+
  Notes:
  - SIMPLIFIED: State-based control via btnRoomState interlock (Separated/RmA Combined/RmB Combined)
  - Components discovered programmatically via Component.GetComponents() at init
  - btnRoomState is single source of truth for walls, gain routing, power sync, and UI state
  - Complies with Lua Refactoring Prompt specifications
]]

-----------------------------[ Configuration Tables ]-----------------------------
local roomNames = {"RoomA", "RoomB"}

-- Room number mapping for audio router logic
local roomNumberMap = {
  RoomA = 1, RoomB = 2
}
local numberToRoomMap = {[1] = "RoomA", [2] = "RoomB"}

-- compGains name mapping - index follows roomNumberMap
local gainControlNames = {"lvlPGMCollabA", "lvlPGMCollabB"}

-- compACPR name mapping - index follows roomNumberMap
local acprControlNames = {"compACPRCollabA", "compACPRCollabB"}

-- hidVideoBridge name mapping - index follows roomNumberMap
local hidVideoBridgeNames = {"hidVideoBridgeDSP-01CollabA", "hidVideoBridgeIOB-01CollabB"}

-- Matrix mixer mute control name mapping
local matrixMixerMutes = {"input.2.output.6.mute", "input.3.output.5.mute", "input.4.output.2.mute", "input.4.output.4.mute", "input.5.output.1.mute", "input.5.output.3.mute"}

-- MXA component name mapping - index follows roomNumberMap
local callSyncNames = {"callSyncCollabA", "callSyncCollabB"}
local roomControlNames = {"compRoomControlsCollabA", "compRoomControlsCollabB"}

-- UCI Status name mapping -- index follows roomNumberMap
local uciNames = {"uciCollabB", "uciCollabA"}

-- ACPR component name mapping 
local acprOutputNames = {"01", "02"}

-- Cam router output controlname mapping -- index follows roomNumberMap
local camRouterOutputControlNames = {"select.1", "select.2"}

-- Component name patterns for discovery
local componentPatterns = {
  roomControls = "^compRoomControls",         -- Expects: compRoomControlsCollabA, compRoomControlsCollabB
  roomCombiner = "^compRoomCombiner",         -- Expects: compRoomCombiner
  camRouter = "^compCamRouter",               -- Expects: compCamRouter
  matrixMixer = "^compMixerAudioCollab",      -- Expects: compMixerAudioCollab
  mxaControls = "^compMXAControlsCollab",     -- Expects: compMXAControlsCollabA, compMXAControlsCollabB
  uciStatus = "^statusControlUCICollab",      -- Expects: statusControlUCICollabB
  acprComponents = "^compACPRCollab",         -- Expects: compACPRCollabA, compACPRCollabB, compACPRCollabCombined
}

-------------------[ Control References ]-------------------
local controls = {
  txtStatus         = Controls.txtStatus,
  btnRoomState      = Controls.btnRoomState,  -- Interlock: 1=Separated, 2=RmA Combined, 3=RmB Combined
}

local function validateControls()
  local required = {
    txtStatus         = controls.txtStatus,
    btnRoomState      = controls.btnRoomState
  }
  
  local missing = {}
  
  for name, control in pairs(required) do
    if not control then 
      table.insert(missing, name) 
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
  local arrayControls = {'btnRoomState'}
  
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

-------------------[ Component Discovery Module ]-------------------
local ComponentModule = setmetatable({}, {__index = BaseModule})
ComponentModule.__index = ComponentModule

function ComponentModule.new(controller)
  local self = BaseModule.new(controller, "ComponentModule")
  setmetatable(self, ComponentModule)
  self:init()
  return self
end

function ComponentModule:discoverAndAssignComponents()
  self:debug("Discovering components programmatically...")
  
  local discovered = {
    roomCombiner = nil,
    matrixMixer = nil,
    roomControls = {},
    mxaControls = {},
    uciStatus = nil,
    acprComponents = {},
    camRouter = nil
  }

  -- Discover all components
  for _, component in ipairs(Component.GetComponents()) do
    -- Find room combiner
    if component.Name:match(componentPatterns.roomCombiner) then
      discovered.roomCombiner = Component.New(component.Name)
      self:debug("Found room combiner: " .. component.Name)
    end
    
    -- Find matrix mixer
    if component.Name:match(componentPatterns.matrixMixer) then
      discovered.matrixMixer = Component.New(component.Name)
      self:debug("Found matrix mixer: " .. component.Name)
    end
    
    -- Find room controls (compRoomControlsA, compRoomControlsB)
    if component.Name:match(componentPatterns.roomControls) then
      local comp = Component.New(component.Name)
      if comp then
        -- Determine which room this belongs to based on name suffix
        if component.Name:match("A$") or component.Name:match("1$") then
          discovered.roomControls[1] = comp
          self:debug("Found RoomA controls: " .. component.Name)
        elseif component.Name:match("B$") or component.Name:match("2$") then
          discovered.roomControls[2] = comp
          self:debug("Found RoomB controls: " .. component.Name)
        end
      end
    end

    -- Find MXA controls (compMXAControlsCollabA, compMXAControlsCollabB)
    if component.Name:match(componentPatterns.mxaControls) then
      local comp = Component.New(component.Name)
      if comp then
        -- Determine which room this belongs to based on name suffix
        if component.Name:match("A$") or component.Name:match("1$") then
          discovered.mxaControls[1] = comp
          self:debug("Found RoomA MXA controls: " .. component.Name)
        elseif component.Name:match("B$") or component.Name:match("2$") then
          discovered.mxaControls[2] = comp
          self:debug("Found RoomB MXA controls: " .. component.Name)
        end
      end
    end

    -- Find UCI status (statusControlUCICollabB)
    if component.Name:match(componentPatterns.uciStatus) then
      discovered.uciStatus = Component.New(component.Name)
      self:debug("Found UCI status: " .. component.Name)
    end

    -- Find ACPR components (compACPRCollabA, compACPRCollabB, compACPRCollabCombined)
    if component.Name:match(componentPatterns.acprComponents) then
      local comp = Component.New(component.Name)
      if comp then
        -- Determine which room this belongs to based on name suffix
        if component.Name:match("A$") or component.Name:match("1$") then
          discovered.acprComponents[1] = comp
          self:debug("Found RoomA ACPR: " .. component.Name)
        elseif component.Name:match("B$") or component.Name:match("2$") then
          discovered.acprComponents[2] = comp
          self:debug("Found RoomB ACPR: " .. component.Name)
        elseif component.Name:match("Combined$") then
          discovered.acprComponents[3] = comp
          self:debug("Found Combined ACPR: " .. component.Name)
        end
      end
    end

    -- Find cam router (compCamRouter)
    if component.Name:match(componentPatterns.camRouter) then
      discovered.camRouter = Component.New(component.Name)
      self:debug("Found cam router: " .. component.Name)
    end
  end

  return discovered
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
 
  -- Configuration-driven handler setup (DRY pattern per Lua Refactoring Prompt #28)
  local handlerConfigs = {
    {
      controlName = "ledSystemPower",
      handlerMethod = "onRoomPowerChanged",
      description = "power"
    },
    {
      controlName = "ledSystemCooling",
      handlerMethod = "onRoomCoolingChanged",
      description = "cooling"
    }
  }
 
  local handlersSetup = 0
  local totalExpected = #roomNames * #handlerConfigs
 
  for i, roomName in ipairs(roomNames) do
    local comp = self.controller.components.roomControls[i]
    if comp then
      -- Bind all handlers for this room using configuration table
      for _, config in ipairs(handlerConfigs) do
        local control = comp[config.controlName]
        if control then
          local handler = function()
            self[config.handlerMethod](self, roomName, i)
          end
          if bind(control, handler) then
            handlersSetup = handlersSetup + 1
            self:debug(config.description:sub(1,1):upper() .. config.description:sub(2) .. " event handler set for " .. roomName .. " (monitoring " .. config.controlName .. ")")
          else
            self:debug("WARNING: Failed to bind " .. config.description .. " handler for " .. roomName)
          end
        else
          self:debug("WARNING: Could not set " .. config.description .. " handler for " .. roomName .. " - " .. config.controlName .. " control not found")
        end
      end
    else
      self:debug("WARNING: Component not found for " .. roomName)
    end
  end
 
  self:debug("Room power event handlers setup: " .. handlersSetup .. "/" .. totalExpected .. " successful")
end

function PowerSyncModule:onRoomCoolingChanged(roomName, roomIndex)
  self:debug("Cooling state changed for " .. roomName .. " - updating button states...")
  
  -- Update btnRoomState button disabled states when cooling state changes
  if self.controller.wallModule then
    self.controller.wallModule:updateBtnRoomStateDisabledStates()
  end
end

function PowerSyncModule:onRoomPowerChanged(roomName, roomIndex)
  if self.syncInProgress then
    self:debug("Sync already in progress - ignoring power change for " .. roomName)
    return
  end

  self:debug("Power state changed for " .. roomName .. " - checking for combined rooms...")

  -- Update btnRoomState button disabled states based on power state
  if self.controller.wallModule then
    self.controller.wallModule:updateBtnRoomStateDisabledStates()
  end

  -- Only sync if rooms are combined
  if self.controller:isRoomsSeparated() then
    self:debug(roomName .. " is in separated state - no power sync needed")
    return
  end
  
  -- Get the new power state of the changed room
  local newPowerState = self.controller:isRoomPoweredOn(roomName)
  self:debug(roomName .. " new power state: " .. (newPowerState and "ON" or "OFF"))
  
  -- Check for automatic separation if room powered off
  if not newPowerState then
    self:debug("Room " .. roomName .. " powered OFF - checking if all combined rooms are now off...")
    if self:shouldAutoSeparate() then
      self:debug("All rooms are OFF - automatically separating rooms")
      self:separateRooms()
      return -- No need to sync power states if we're separating
    end
  end
  
  -- Find all other rooms in the combination to synchronize
  -- In combined state, ANY room change should sync to ALL other rooms
  local roomsToSync = {}
  for i, rn in ipairs(roomNames) do
    if rn ~= roomName then
      table.insert(roomsToSync, rn)
    end
  end
  
  if #roomsToSync == 0 then
    self:debug("No other rooms to sync with " .. roomName)
    return
  end
  
  self:debug("Synchronizing power state (" .. (newPowerState and "ON" or "OFF") .. ") from " .. roomName .. " to combined rooms: " .. table.concat(roomsToSync, ", "))
  
  -- Perform the synchronization
  self:syncPowerToRooms(roomsToSync, newPowerState)
  
  -- Update UCI status routing after power change (may switch between uciCollabA/uciCollabB based on RoomB power)
  self.controller:applyUCIStatusRouting()
end

function PowerSyncModule:syncPowerToRooms(roomsToSync, powerState)
  self.syncInProgress = true
 
  local syncedRooms = 0
  local syncErrors = {}
 
  for _, roomName in ipairs(roomsToSync) do
    local roomIndex = self:getRoomIndex(roomName)
    if roomIndex then
      local comp = self.controller.components.roomControls[roomIndex]
      if comp and comp["ledSystemPower"] and comp["btnSystemOnOff"] then
        -- CONTROL/STATUS PATTERN:
        -- Read ledSystemPower (status) to check current state
        local currentState = comp["ledSystemPower"].Boolean
        if currentState ~= powerState then
          -- Write to btnSystemOnOff (control) to trigger power change
          -- SystemAutomationController will then update ledSystemPower (status) to reflect actual state
          setProp(comp["btnSystemOnOff"], "Boolean", powerState)
          syncedRooms = syncedRooms + 1
          self:debug("SYNCED: " .. roomName .. " -> btnSystemOnOff set to " .. (powerState and "ON" or "OFF"))
        else
          self:debug("SKIP: " .. roomName .. " already " .. (powerState and "ON" or "OFF") .. " (per ledSystemPower)")
        end
      else
        local errorMsg = roomName .. ": Component or required controls not found"
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

function PowerSyncModule:shouldAutoSeparate()
  -- Check if ALL rooms are powered off
  local allRoomsOff = true
  
  for i, roomName in ipairs(roomNames) do
    local roomPowerState = self.controller:isRoomPoweredOn(roomName)
    self:debug("Checking " .. roomName .. " power state: " .. (roomPowerState and "ON" or "OFF"))
    
    if roomPowerState then
      allRoomsOff = false
      self:debug("Found " .. roomName .. " still powered ON - separation not needed")
      break
    end
  end
  
  self:debug("Auto-separation check: all rooms off = " .. tostring(allRoomsOff))
  return allRoomsOff
end

function PowerSyncModule:separateRooms()
  self:debug("Executing automatic room separation...")
  
  -- Set sync flag to prevent recursive power change handlers
  self.syncInProgress = true
  
  -- STEP 1: Power OFF all rooms first to allow wall movement
  -- CONTROL/STATUS PATTERN: Read ledSystemPower (status), write to btnSystemOnOff (control)
  local roomsPoweredOff = 0
  for i, roomName in ipairs(roomNames) do
    local comp = self.controller.components.roomControls[i]
    if comp and comp["ledSystemPower"] and comp["btnSystemOnOff"] then
      if comp["ledSystemPower"].Boolean then -- Check status
        self:debug("Powering OFF " .. roomName .. " before separation")
        setProp(comp["btnSystemOnOff"], "Boolean", false) -- Trigger control
        roomsPoweredOff = roomsPoweredOff + 1
      end
    end
  end
  
  self:debug("Powered OFF " .. roomsPoweredOff .. " rooms before separation")
  
  -- STEP 2: Set btnRoomState to Separated (button 1)
  if controls.btnRoomState and controls.btnRoomState[1] then
    setProp(controls.btnRoomState[1], "Boolean", true)
    self:debug("Set btnRoomState to Separated")
    
    -- Apply interlock to ensure other buttons are off
    self.controller:applyBtnRoomStateInterlock(1)
    
    -- Directly call applyRoomState since EventHandlers don't fire on programmatic changes
    self.controller:applyRoomState()
  end
  
  -- STEP 3: Update btnRoomState button disabled states (all rooms are now off, so enable combine buttons)
  if self.controller.wallModule then
    self.controller.wallModule:updateBtnRoomStateDisabledStates()
  end
  
  -- Clear sync flag
  self.syncInProgress = false
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

function WallModule:updateWallState()
  self:debug("Updating wall state based on btnRoomState...")
  
  if not self.controller.components.roomCombiner then
    self:debug("No room combiner available")
    return
  end
  
  local roomState = self.controller:getRoomState()
  local wallShouldBeOpen = (roomState ~= "Separated")
  
  -- For two-room setup, only one wall (wall.1.open)
  local wallControl = self.controller.components.roomCombiner["wall.1.open"]
  
  if wallControl then
    setProp(wallControl, "Boolean", wallShouldBeOpen)
    self:debug("Wall set to " .. (wallShouldBeOpen and "OPEN" or "CLOSED") .. " (State: " .. roomState .. ")")
  else
    self:debug("ERROR: Wall control not found on room combiner")
  end
end

function WallModule:canChangeWallState()
  -- Check if any room is powered on (using ledSystemPower as authoritative status indicator)
  -- CONTROL/STATUS PATTERN: Always read power state from ledSystemPower (status)
  for _, roomName in ipairs(roomNames) do
    if self.controller:isRoomPoweredOn(roomName) then
      self:debug("Wall change blocked - " .. roomName .. " is powered on")
      return false
    end
  end
  return true
end

function WallModule:updateBtnRoomStateDisabledStates()
  self:debug("Updating btnRoomState button disabled states...")
  
  -- Check if ANY room is powered on
  local anyRoomOn = false
  local anyRoomCooling = false
  local roomStates = {}
  
  for _, roomName in ipairs(roomNames) do
    local isRoomOn = self.controller:isRoomPoweredOn(roomName)
    table.insert(roomStates, roomName .. ":" .. (isRoomOn and "ON" or "OFF"))
    if isRoomOn then
      anyRoomOn = true
    end
    
    -- Check if room is cooling (prevent turning on while cooling down)
    local isRoomCooling = self.controller:isRoomCooling(roomName)
    if isRoomCooling then
      anyRoomCooling = true
      table.insert(roomStates, roomName .. ":COOLING")
    end
  end
  
  -- Disable combine buttons (2 and 3) if any room is powered on OR cooling
  -- btnRoomState[1] = Separated (always enabled)
  -- btnRoomState[2] = RoomA Combined (disable when any room is ON or cooling)
  -- btnRoomState[3] = RoomB Combined (disable when any room is ON or cooling)
  local shouldDisable = anyRoomOn or anyRoomCooling
  if controls.btnRoomState then
    if controls.btnRoomState[2] then
      setProp(controls.btnRoomState[2], "IsDisabled", shouldDisable)
    end
    if controls.btnRoomState[3] then
      setProp(controls.btnRoomState[3], "IsDisabled", shouldDisable)
    end
  end
  
  self:debug("btnRoomState[2,3] " .. (shouldDisable and "DISABLED" or "ENABLED") .. 
             " [" .. table.concat(roomStates, ", ") .. "]")
end

-------------------[ DivisibleSpaceController (Main Orchestrator) ]-------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, debugging)
  local self = setmetatable({}, DivisibleSpaceController)
  self.roomName = roomName or "Two Room Divisible Space"
  self.debugging = debugging ~= false
  
  self.components = {
    roomCombiner = nil,
    matrixMixer = nil,
    roomControls = {},
    mxaControls = {},
    uciStatus = nil,
    acprComponents = {},
    camRouter = nil
  }
  
  self.componentModule = ComponentModule.new(self)
  self.powerSyncModule = PowerSyncModule.new(self)
  self.wallModule = WallModule.new(self)
  
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

----------------[ Initialization ]--------------------------
function DivisibleSpaceController:init()
  self:debugPrint("Starting initialization...")
  
  -- Discover and assign components programmatically
  local discovered = self.componentModule:discoverAndAssignComponents()
  self.components.roomCombiner = discovered.roomCombiner
  self.components.matrixMixer = discovered.matrixMixer
  self.components.roomControls = discovered.roomControls
  self.components.mxaControls = discovered.mxaControls
  self.components.uciStatus = discovered.uciStatus
  self.components.acprComponents = discovered.acprComponents
  self.components.camRouter = discovered.camRouter
  -- Verify critical components
  if not self.components.roomCombiner then
    self:debugPrint("WARNING: Room combiner not found")
  end

  if not self.components.matrixMixer then
    self:debugPrint("WARNING: Matrix mixer not found")
  end
  
  for i, roomName in ipairs(roomNames) do
    if not self.components.roomControls[i] then
      self:debugPrint("WARNING: Room controls for " .. roomName .. " not found")
    end
    if not self.components.mxaControls[i] then
      self:debugPrint("WARNING: MXA controls for " .. roomName .. " not found")
    end
    if not self.components.uciStatus then
      self:debugPrint("WARNING: UCI status not found")
    end
    if not self.components.acprComponents[i] then
      self:debugPrint("WARNING: ACPR components for " .. roomName .. " not found")
    end
    if not self.components.camRouter then
      self:debugPrint("WARNING: Cam router not found")
    end
  end
  
  -- Check for Combined ACPR component (index 3)
  if not self.components.acprComponents[3] then
    self:debugPrint("WARNING: Combined ACPR component not found")
  end
  
  -- Register event handlers
  self:registerEventHandlers()
  
  -- Set initial state
  self:applyRoomState()
  
  -- Setup power event handlers
  if self.powerSyncModule then
    self.powerSyncModule:setupRoomPowerEventHandlers()
  end
  
  -- Update initial btnRoomState button disabled states based on current power state
  if self.wallModule then
    self.wallModule:updateBtnRoomStateDisabledStates()
  end
  
  self:checkStatus()
  self:debugPrint("Initialization complete")
end

------------------[ Event Handler Registration ]----------------------
function DivisibleSpaceController:registerEventHandlers()
  self:debugPrint("Registering event handlers...")
  
  -- btnRoomState interlock handler with explicit interlock logic
  -- Ensures only one button is true at a time (mutually exclusive)
  if controls.btnRoomState then
    bindArray(controls.btnRoomState, function(i, ctl)
      if ctl.Boolean then
        self:debugPrint("Room state button " .. i .. " pressed: " .. self:getRoomStateFromIndex(i))
        
        -- Apply interlock: set all other buttons to false
        self:applyBtnRoomStateInterlock(i)
        
        -- Apply the room state configuration
        self:applyRoomState()
      end
    end)
    self:debugPrint("btnRoomState event handlers registered with interlock")
  end
  
  self:debugPrint("Event handlers setup complete")
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
  local roomState = self:getRoomState()
  
  if roomState == "RoomA_Combined" then
    return "RoomA"
  elseif roomState == "RoomB_Combined" then
    return "RoomB"
  end
  
  return nil -- No priority in separated state
end

function DivisibleSpaceController:isRoomsSeparated()
  return self:getRoomState() == "Separated"
end

function DivisibleSpaceController:applyRoomState()
  self:debugPrint("Applying room state configuration...")
  
  local roomState = self:getRoomState()
  self:debugPrint("Current state: " .. roomState)
  
  -- Check if wall can be changed
  if not self.wallModule:canChangeWallState() then
    self:debugPrint("Cannot change room state - rooms are powered on")
    -- Revert btnRoomState to previous state (separated)
    if controls.btnRoomState and controls.btnRoomState[1] then
      setProp(controls.btnRoomState[1], "Boolean", true)
    end
    return
  end
  
  -- Update wall state
  if self.wallModule then
    self.wallModule:updateWallState()
  end
  
  -- Update gain routing
  self:applyGainRouting()
  
  -- Update matrix mixer mutes
  self:applyMatrixMixerMutes()

  -- Update acpr assignment
  self:applyACPRAssignment()

  -- Update MXA component routing
  self:applyMXAControlsRouting()
  
  -- Update UCI status routing
  self:applyUCIStatusRouting()
  
  -- Update ACPR component routing
  self:applyACPRComponentRouting()

  -- Update cam router routing
  self:applyCamRouterRouting()

  -- Update hid video bridge routing
  self:applyHidVideoBridgeRouting()
  
  -- Sync power state when combining rooms
  if roomState ~= "Separated" then
    self:syncPowerOnCombine()
  end
  
  self:checkStatus()
end

function DivisibleSpaceController:syncPowerOnCombine()
  self:debugPrint("Syncing power state on room combine...")
  
  local priorityRoom = self:getPriorityRoom()
  if not priorityRoom then
    self:debugPrint("No priority room - skipping power sync")
    return
  end
  
  -- When combining, check if ANY room is powered on and sync that state to all others
  -- This ensures if either room is ON when combining, both rooms power on
  local anyRoomOn = false
  for _, roomName in ipairs(roomNames) do
    if self:isRoomPoweredOn(roomName) then
      anyRoomOn = true
      self:debugPrint("Found " .. roomName .. " powered ON - will sync ON state to all rooms")
      break
    end
  end
  
  -- Sync the determined power state to ALL rooms
  if anyRoomOn and self.powerSyncModule then
    self:debugPrint("Syncing power (ON) to all rooms in combination")
    self.powerSyncModule:syncPowerToRooms(roomNames, true)
  else
    self:debugPrint("All rooms are OFF - no power sync needed on combine")
  end
end

function DivisibleSpaceController:applyGainRouting()
  self:debugPrint("Applying gain routing based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]
    
    if roomComp and roomComp["compGains 1"] then
      local gainControlName = nil
      
      if isSeparated then
        -- Each room uses own gain
        gainControlName = gainControlNames[i]
      else
        -- Combined: use priority room's gain
        if priorityRoom == "RoomA" then
          gainControlName = gainControlNames[1]
        elseif priorityRoom == "RoomB" then
          gainControlName = gainControlNames[2]
        end
      end
      
      if gainControlName and gainControlName ~= "" then
        setProp(roomComp["compGains 1"], "String", gainControlName)
        successfulRoutings = successfulRoutings + 1
        self:debugPrint(roomName .. " -> Gain: " .. gainControlName)
      else
        table.insert(routingErrors, roomName .. ": Invalid gain control")
      end
    else
      table.insert(routingErrors, roomName .. ": Component or compGains 1 not found")
    end
  end
  
  self:printOperationResult("Gain routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:applyMatrixMixerMutes()
  self:debugPrint("Applying matrix mixer mutes based on room state...")
  
  if not self.components.matrixMixer then
    self:debugPrint("WARNING: Matrix mixer component not found - skipping mute control")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  
  -- When separated: mutes = true (muted)
  -- When combined: mutes = false (unmuted)
  local muteState = isSeparated
  
  local muteErrors = {}
  local successfulMutes = 0
  
  for _, muteControlName in ipairs(matrixMixerMutes) do
    local muteControl = self.components.matrixMixer[muteControlName]
    
    if muteControl then
      setProp(muteControl, "Boolean", muteState)
      successfulMutes = successfulMutes + 1
      self:debugPrint(muteControlName .. " -> " .. (muteState and "MUTED" or "UNMUTED"))
    else
      table.insert(muteErrors, muteControlName .. ": Control not found")
    end
  end
  
  self:printOperationResult("Matrix mixer mutes", successfulMutes, #matrixMixerMutes, muteErrors)
end

function DivisibleSpaceController:applyACPRAssignment()
  self:debugPrint("Applying acpr assignment based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]
    
    if roomComp and roomComp["compACPR"] then
      local acprControlName = nil
      
      if isSeparated then
        -- Each room uses own ACPR
        acprControlName = acprControlNames[i]
      else
        -- Combined: all rooms use combined ACPR
        acprControlName = "compACPRCollabCombined"
      end
      
      if acprControlName and acprControlName ~= "" then
        setProp(roomComp["compACPR"], "String", acprControlName)
        successfulRoutings = successfulRoutings + 1
        self:debugPrint(roomName .. " -> ACPR: " .. acprControlName)
      else
        table.insert(routingErrors, roomName .. ": Invalid ACPR control")
      end
    else
      table.insert(routingErrors, roomName .. ": Component or compACPR not found")
    end
  end
  
  self:printOperationResult("acpr assignment", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:applyMXAControlsRouting()
  self:debugPrint("Applying MXA component routing based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()

  local routingErrors = {}
  local successfulRoutings = 0
  local totalExpectedOperations = #roomNames * 2  -- 2 operations per room (callSync + compRoomControls)

  for i, roomName in ipairs(roomNames) do
    -- Determine control names based on room state
    local callSyncName = nil
    local roomControlName = nil

    if isSeparated then
      -- Each room uses own values
      callSyncName = callSyncNames[i]
      roomControlName = roomControlNames[i]
    else
      -- Combined: use priority room's values
      if priorityRoom == "RoomA" then
        callSyncName = callSyncNames[1]
        roomControlName = roomControlNames[1]
      elseif priorityRoom == "RoomB" then
        callSyncName = callSyncNames[2]
        roomControlName = roomControlNames[2]
      end
    end

    -- Get mxaControls component once
    local mxaComp = self.components.mxaControls[i]

    -- Define controls to set (control name, value, display name)
    local controlsToSet = {
      {controlName = "compCallSync", value = callSyncName, displayName = "callSync"},
      {controlName = "compRoomControls", value = roomControlName, displayName = "compRoomControls"}
    }

    -- Set each control
    for _, control in ipairs(controlsToSet) do
      if mxaComp and mxaComp[control.controlName] then
        if control.value and control.value ~= "" then
          setProp(mxaComp[control.controlName], "String", control.value)
          successfulRoutings = successfulRoutings + 1
          self:debugPrint(roomName .. " -> MXA " .. control.displayName .. ": " .. control.value)
        else
          table.insert(routingErrors, roomName .. ": Invalid " .. control.displayName .. " control name")
        end
      else
        table.insert(routingErrors, roomName .. ": MXA controls component or " .. control.displayName .. " control not found")
      end
    end
  end

  self:printOperationResult("MXA controls routing", successfulRoutings, totalExpectedOperations, routingErrors)
end

function DivisibleSpaceController:applyUCIStatusRouting()
  self:debugPrint("Applying UCI status routing based on room state...")

  if not self.components.uciStatus then
    self:debugPrint("WARNING: UCI status component not found - skipping UCI status routing")
    return
  end
  
  local isSeparated = self:isRoomsSeparated()
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  -- Determine which UCI name to set based on room state
  local uciValue
  if isSeparated then
    uciValue = "uciCollabB"  -- uciCollabB when separated
  else
    -- Only use uciCollabA when combined if RoomB system power is on
    local roomBControls = self.components.roomControls[2]
    if roomBControls and roomBControls["ledSystemPower"] and roomBControls["ledSystemPower"].Boolean then
      uciValue = "uciCollabA"  -- uciCollabA when combined and RoomB is powered on
    else
      uciValue = "uciCollabB"  -- Fallback to uciCollabB if RoomB power is off or component not found
      self:debugPrint("WARNING: RoomB system power is off or component not found - using uciCollabB instead of uciCollabA")
    end
  end
  
  -- Find the UCI status component
  if self.components.uciStatus then
    -- Set the current.uci control on the component
    local statusControl = self.components.uciStatus["current.uci"]
    if statusControl then
      setProp(statusControl, "String", uciValue)
      successfulRoutings = 1
      self:debugPrint("UCI status routing: statusControl -> " .. uciValue)
    else
      table.insert(routingErrors, "UCI status component: statusControl -> " .. uciValue .. " control not found")
      self:debugPrint("ERROR: statusControl -> " .. uciValue .. " control not found on UCI status component")
    end
  else
    table.insert(routingErrors, "UCI status component: Component not found")
    self:debugPrint("ERROR: UCI status component not found")
  end
  
  self:printOperationResult("UCI status routing", successfulRoutings, #uciNames, routingErrors)
end

function DivisibleSpaceController:applyHidVideoBridgeRouting()
  self:debugPrint("Applying hid video bridge routing based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()

  local routingErrors = {}
  local successfulRoutings = 0

  for i, roomName in ipairs(roomNames) do
    local roomComp = self.components.roomControls[i]

    if roomComp and roomComp["hidVideoBridge 1"] then
      local hidVideoBridgeName = nil

      if isSeparated then
        -- Each room uses own Hid Video Bridge
        hidVideoBridgeName = hidVideoBridgeNames[i]
      else
        -- Combined: use priority room's Hid Video Bridge
        if priorityRoom == "RoomA" then
          hidVideoBridgeName = hidVideoBridgeNames[1]
        elseif priorityRoom == "RoomB" then
          hidVideoBridgeName = hidVideoBridgeNames[2]
        end
      end
      
      if hidVideoBridgeName and hidVideoBridgeName ~= "" then
        setProp(roomComp["hidVideoBridge 1"], "String", hidVideoBridgeName)
        successfulRoutings = successfulRoutings + 1
        self:debugPrint(roomName .. " -> Hid Video Bridge: " .. hidVideoBridgeName)
      else
        table.insert(routingErrors, roomName .. ": Invalid Hid Video Bridge control")
      end
    else
      table.insert(routingErrors, roomName .. ": Component or hidVideoBridge 1 not found")
    end
  end

  self:printOperationResult("Hid video bridge routing", successfulRoutings, #roomNames, routingErrors)
end

function DivisibleSpaceController:applyACPRComponentRouting()
  self:debugPrint("Applying ACPR component routing based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  local priorityRoom = self:getPriorityRoom()
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  if isSeparated then
    -- Separated: Set TrackingBypass to false for components 1 and 2, true for component 3
    for i = 1, 2 do
      local acprComp = self.components.acprComponents[i]
      if acprComp and acprComp["TrackingBypass"] then
        setProp(acprComp["TrackingBypass"], "Boolean", false)
        successfulRoutings = successfulRoutings + 1
        self:debugPrint("ACPR[" .. i .. "] -> TrackingBypass: false (Separated)")
      else
        table.insert(routingErrors, "ACPR[" .. i .. "]: Component or TrackingBypass control not found")
      end
    end
    
    -- Set component 3 TrackingBypass to true
    local acprComp3 = self.components.acprComponents[3]
    if acprComp3 and acprComp3["TrackingBypass"] then
      setProp(acprComp3["TrackingBypass"], "Boolean", true)
      successfulRoutings = successfulRoutings + 1
      self:debugPrint("ACPR[3] -> TrackingBypass: true (Separated)")
    else
      table.insert(routingErrors, "ACPR[3]: Component or TrackingBypass control not found")
    end
  else
    -- Combined: Set TrackingBypass to false for component 3
    local acprComp3 = self.components.acprComponents[3]
    if acprComp3 and acprComp3["TrackingBypass"] then
      setProp(acprComp3["TrackingBypass"], "Boolean", false)
      successfulRoutings = successfulRoutings + 1
      self:debugPrint("ACPR[3] -> TrackingBypass: false (Combined)")
    else
      table.insert(routingErrors, "ACPR[3]: Component or TrackingBypass control not found")
    end
    
    -- Set CameraRouterOutput on component 3 based on priorityRoom
    if priorityRoom then
      local outputValue = nil
      if priorityRoom == "RoomA" then
        outputValue = acprOutputNames[1]  -- "01"
      elseif priorityRoom == "RoomB" then
        outputValue = acprOutputNames[2]  -- "02"
      end
      
      if outputValue and acprComp3 and acprComp3["CameraRouterOutput"] then
        setProp(acprComp3["CameraRouterOutput"], "String", outputValue)
        successfulRoutings = successfulRoutings + 1
        self:debugPrint("ACPR[3] -> CameraRouterOutput: " .. outputValue .. " (Priority: " .. priorityRoom .. ")")
      else
        if not outputValue then
          table.insert(routingErrors, "ACPR[3]: Invalid priorityRoom: " .. tostring(priorityRoom))
        else
          table.insert(routingErrors, "ACPR[3]: Component or CameraRouterOutput control not found")
        end
      end
    else
      table.insert(routingErrors, "ACPR[3]: No priorityRoom in combined state")
    end
  end
  
  self:printOperationResult("ACPR component routing", successfulRoutings, 3, routingErrors)
end

function DivisibleSpaceController:applyCamRouterRouting()
  self:debugPrint("Applying cam router routing based on room state...")
  
  local isSeparated = self:isRoomsSeparated()
  
  local routingErrors = {}
  local successfulRoutings = 0
  
  local camRouterComp = self.components.camRouter
  
  if not camRouterComp then
    self:debugPrint("WARNING: Cam router component not found - skipping cam router routing")
    return
  end

  -- Configuration: values for each control based on room state
  -- Separated: select.1 = 1, select.2 = 2
  -- Combined: select.1 = 1, select.2 = 1
  local routingConfig = {
    {controlName = "select.1", separatedValue = 1, combinedValue = 1},
    {controlName = "select.2", separatedValue = 2, combinedValue = 1}
  }
  
  local stateLabel = isSeparated and "Separated" or "Combined"
  
  for _, config in ipairs(routingConfig) do
    local control = camRouterComp[config.controlName]
    local value = isSeparated and config.separatedValue or config.combinedValue
    
    if control then
      setProp(control, "Value", value)
      successfulRoutings = successfulRoutings + 1
      self:debugPrint("Cam Router -> " .. config.controlName .. ": " .. value .. " (" .. stateLabel .. ")")
    else
      table.insert(routingErrors, "Cam Router: " .. config.controlName .. " control not found")
    end
  end
  
  self:printOperationResult("Cam router routing", successfulRoutings, #routingConfig, routingErrors)
end

function DivisibleSpaceController:isRoomPoweredOn(roomName)
  -- CONTROL/STATUS PATTERN: Always read power state from ledSystemPower (status), never from btnSystemOnOff
  -- ledSystemPower reflects the actual system state set by SystemAutomationController
  -- btnSystemOnOff is a control input that may not reflect actual state (delays, failures, etc.)
  for i, rn in ipairs(roomNames) do
    if rn == roomName then
      local comp = self.components.roomControls[i]
      if comp and comp["ledSystemPower"] then
        return comp["ledSystemPower"].Boolean
      end
      return false
    end
  end
  return false
end

function DivisibleSpaceController:isRoomCooling(roomName)
  -- CONTROL/STATUS PATTERN: Read cooling state from ledSystemCooling (status indicator)
  -- ledSystemCooling reflects the actual cooling state set by SystemAutomationController
  -- This prevents system from being turned on while cooling down
  for i, rn in ipairs(roomNames) do
    if rn == roomName then
      local comp = self.components.roomControls[i]
      if comp and comp["ledSystemCooling"] then
        return comp["ledSystemCooling"].Boolean == true
      end
      return false
    end
  end
  return false
end

function DivisibleSpaceController:checkStatus()
  local statusMsg = "OK"
  local statusValue = 0
  
  -- Check components
  if not self.components.roomCombiner then
    statusMsg = "Room Combiner Missing"
    statusValue = 1
  end
  
  local connectedRooms = 0
  for i = 1, #roomNames do
    if self.components.roomControls[i] then
      connectedRooms = connectedRooms + 1
    end
  end
  
  if connectedRooms < #roomNames then
    statusMsg = statusMsg .. " (Rooms: " .. connectedRooms .. "/" .. #roomNames .. ")"
    statusValue = 1
  end
  
  -- Add current state to status
  local roomState = self:getRoomState()
  statusMsg = statusMsg .. " | State: " .. roomState
  
  if controls.txtStatus then
    controls.txtStatus.String = statusMsg
    controls.txtStatus.Value = statusValue
  end
end

function DivisibleSpaceController:cleanup()
  local modules = {self.componentModule, self.powerSyncModule, self.wallModule}
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
