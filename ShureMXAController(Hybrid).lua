--[[
    ShureMXAController - Simplified Hybrid Version
    Author: Nikolas Smith, Q-SYS
    Version: 4.0-Hybrid | Date: 2026-01-12
    Firmware Req: 10.0.0
    
    SIMPLIFIED FOR MAINTAINABILITY:
    - Single class structure (no module inheritance)
    - Explicit loops instead of utility abstractions
    - Clear, traceable event flow
    - Comprehensive inline documentation
    
    ============================================
    FLOW DOCUMENTATION - Common Scenarios:
    ============================================
    
    SCENARIO 1: User presses the mute button
      1. btnMXAMute EventHandler fires (line ~380)
      2. Calls self:setAllMXAMute() (line ~143)
      3. Loops through mxaDevices array setting GlobalMute on each
      4. Debug prints confirm each device muted
    
    SCENARIO 2: Call goes off-hook (conference starts)
      1. callSync["off.hook"] EventHandler fires (line ~437)
      2. Boolean is true, so calls self:handleCallOffHook() (line ~165)
      3. Turns on all MXA LED rings (line ~172)
      4. Sets LED color to green
    
    SCENARIO 3: Call goes on-hook (conference ends)
      1. callSync["off.hook"] EventHandler fires (line ~437)
      2. Boolean is false, so calls self:handleCallOnHook() (line ~178)
      3. Turns off all MXA LED rings
      4. Sets LED color to red (privacy mode)
    
    SCENARIO 4: Fire alarm activates
      1. roomControls["ledFireAlarm"] EventHandler fires (line ~468)
      2. Calls self:handleFireAlarm(true) (line ~208)
      3. Starts LED toggle timer (blinks LEDs on/off every 1.5 seconds)
      4. Sets color to red and turns LEDs off initially
    
    SCENARIO 5: System powers off
      1. roomControls["ledSystemPower"] EventHandler fires (line ~460)
      2. Boolean is false, so calls self:handleSystemPower(false) (line ~236)
      3. Sets all MXA LEDs to red and turns them off
      4. System enters low-power state
]]--

-------------------[ Control References ]-------------------
local controls = {
    devMXAs = Controls.devMXAs,
    btnMXAMute = Controls.btnMXAMute,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus,
}

-------------------[ Utility Functions ]-------------------
-- Check if a value is an array (table with numeric indices)
local function isArr(t) 
    return type(t) == "table" and t[1] ~= nil 
end

-- Get control array (normalizes single controls to arrays)
local function getControlArray(ctrl)
    return ctrl and (isArr(ctrl) and ctrl or {ctrl}) or {}
end

-- Set property only if value changed (prevents unnecessary signal propagation)
-- This is important for performance and avoiding feedback loops
local function setProp(ctrl, prop, val)
    if ctrl and ctrl[prop] ~= val then 
        ctrl[prop] = val 
    end
end

-- Bind an event handler to a control
local function bind(ctrl, handler)
    if ctrl then 
        ctrl.EventHandler = handler 
    end
end

-- Bind event handlers to an array of controls
local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do
        bind(ctrl, function(ctl) handler(i, ctl) end)
    end
end

-- Execute function for each control in array
local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        fn(i, ctrl) 
    end
end

-------------------[ Validation Functions ]-------------------
-- Check that all required controls exist before proceeding
local function validateControls()
    local required = { "devMXAs", "btnMXAMute" }
    local missing = {}
    
    for _, name in ipairs(required) do
        if not controls[name] then 
            table.insert(missing, name) 
        end
    end
    
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

-- Normalize control arrays to always be tables (not single controls)
-- This allows the utility functions to work consistently
local function normalizeControlArrays()
    if controls.devMXAs and not isArr(controls.devMXAs) then
        controls.devMXAs = { controls.devMXAs }
    elseif not controls.devMXAs then
        controls.devMXAs = {}
    end
end

-------------------[ Main Controller Class ]-------------------
ShureMXAController = {}
ShureMXAController.__index = ShureMXAController

function ShureMXAController.new(roomName, config)
    -- Validate that required controls exist
    if not validateControls() then return nil end
    
    -- Normalize arrays so we can always loop
    normalizeControlArrays()
    
    local self = setmetatable({}, ShureMXAController)
    
    -- Basic configuration
    self.roomName = roomName or "Shure MXA"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    
    -- LED configuration values
    self.ledBrightness = (config and config.ledBrightness) or 5
    self.ledOff = 0
    self.ledRed = "Red"
    self.ledGreen = "Green"
    
    -- State tracking - all in one place for easy reference
    self.audioPrivacy = false      -- Is audio privacy enabled?
    self.systemPower = false       -- Is system powered on?
    self.fireAlarm = false         -- Is fire alarm active?
    self.ledState = false          -- Current LED state (for toggle)
    self.muteState = false         -- Are MXAs currently muted?
    
    -- Component storage - simple tables
    self.mxaDevices = {}           -- Array of MXA device component references
    self.callSync = nil            -- Call Sync component reference
    self.roomControls = nil        -- Room Controls component reference
    self.invalidComponents = {}    -- Track which components are invalid
    
    -- LED toggle timer for fire alarm blink effect
    self.ledToggleTimer = Timer.New()
    self.ledToggleTimer.EventHandler = function()
        -- Toggle LED state and update all devices
        self.ledState = not self.ledState
        self:setAllMXALEDs(self.ledState)
    end
    
    return self
end

-- Debug print helper
function ShureMXAController:debugPrint(msg)
    if self.debugging then 
        print("[" .. self.roomName .. "] " .. msg) 
    end
end

-------------------[ MXA Device Control Methods ]-------------------
-- Set mute state on all MXA devices
-- Called from: btnMXAMute EventHandler (line ~430)
function ShureMXAController:setAllMXAMute(state)
    self.muteState = state
    
    -- Loop through all MXA devices and set GlobalMute
    -- Using setProp to avoid unnecessary signal propagation
    for i = 1, #self.mxaDevices do
        local device = self.mxaDevices[i]
        if device and device.GlobalMute then
            setProp(device.GlobalMute, "Boolean", state)
            self:debugPrint("MXA [" .. i .. "] mute set to: " .. tostring(state))
        end
    end
end

-- Set LED brightness on all MXA devices
-- Called from: handleCallOffHook, handleCallOnHook, handleFireAlarm, ledToggleTimer
function ShureMXAController:setAllMXALEDs(state)
    -- Convert boolean to brightness value
    local brightness = state and self.ledBrightness or self.ledOff
    
    -- Loop through all MXA devices and set brightness
    -- Using setProp to avoid unnecessary signal propagation
    for i = 1, #self.mxaDevices do
        local device = self.mxaDevices[i]
        if device and device.BrightnessLevel then
            setProp(device.BrightnessLevel, "Value", brightness)
            self:debugPrint("MXA [" .. i .. "] LED brightness: " .. brightness)
        end
    end
end

-- Set LED color on all MXA devices
-- Called from: handleCallOffHook, handleCallOnHook, handleCallMute, handleFireAlarm, btnMXAMute handler
function ShureMXAController:setAllMXALEDColor(color)
    -- Loop through all MXA devices and set LED color
    -- Using setProp to avoid unnecessary signal propagation
    for i = 1, #self.mxaDevices do
        local device = self.mxaDevices[i]
        if device and device.LedUnmuteColor then
            setProp(device.LedUnmuteColor, "String", color)
            self:debugPrint("MXA [" .. i .. "] LED color: " .. color)
        end
    end
end

-- Get count of valid MXA devices currently configured
function ShureMXAController:getMXADeviceCount()
    local count = 0
    for i = 1, #self.mxaDevices do
        if self.mxaDevices[i] then 
            count = count + 1 
        end
    end
    return count
end

-------------------[ Call Control Methods ]-------------------
-- Handle call going off-hook (conference starts)
-- Called from: callSync["off.hook"] EventHandler when Boolean becomes true
function ShureMXAController:handleCallOffHook()
    self:debugPrint("Call off-hook - turning on MXA LEDs")
    
    -- Turn on LED rings to show call is active
    self:setAllMXALEDs(true)
    
    -- Set color to green (unmuted/active call)
    self:setAllMXALEDColor(self.ledGreen)
end

-- Handle call going on-hook (conference ends)
-- Called from: callSync["off.hook"] EventHandler when Boolean becomes false
function ShureMXAController:handleCallOnHook()
    self:debugPrint("Call on-hook - turning off MXA LEDs")
    
    -- Turn off LED rings (no active call)
    self:setAllMXALEDs(false)
    
    -- Set color to red (privacy mode)
    self:setAllMXALEDColor(self.ledRed)
end

-- Handle call mute state change
-- Called from: callSync["mute"] EventHandler
function ShureMXAController:handleCallMute(state)
    self:debugPrint("Call mute: " .. tostring(state))
    
    -- Change LED color based on mute state
    -- Red = muted (privacy), Green = unmuted (active audio)
    local color = state and self.ledRed or self.ledGreen
    self:setAllMXALEDColor(color)
end

-------------------[ System Control Methods ]-------------------
-- Handle fire alarm activation/deactivation
-- Called from: roomControls["ledFireAlarm"] EventHandler
function ShureMXAController:handleFireAlarm(state)
    self.fireAlarm = state
    
    if state then
        -- Fire alarm is ACTIVE
        self:debugPrint("Fire Alarm ACTIVE - starting LED toggle")
        
        -- Start blinking LEDs (toggle every 1.5 seconds)
        self.ledToggleTimer:Start(1.5)
        
        -- Set initial state: red color, LEDs off
        self:setAllMXALEDColor(self.ledRed)
        self:setAllMXALEDs(false)
    else
        -- Fire alarm is CLEARED
        self:debugPrint("Fire Alarm CLEARED - restoring normal operation")
        
        -- Stop the blinking
        self.ledToggleTimer:Stop()
        
        -- Restore LED state based on current call status
        if self.callSync and self.callSync["off.hook"] then
            local isOffHook = self.callSync["off.hook"].Boolean
            if isOffHook then
                -- Call is active: restore active call state
                self:handleCallOffHook()
            else
                -- No call: restore privacy mode
                self:handleCallOnHook()
            end
        end
    end
end

-- Handle system power change
-- Called from: roomControls["ledSystemPower"] EventHandler
function ShureMXAController:handleSystemPower(state)
    self.systemPower = state
    
    if not state then
        -- System is POWERED OFF
        self:debugPrint("System Power OFF - muting all MXAs")
        
        -- Set privacy mode: red LEDs, turned off
        self:setAllMXALEDColor(self.ledRed)
        self:setAllMXALEDs(false)
    else
        -- System is POWERED ON
        self:debugPrint("System Power ON - restoring MXA states")
        
        -- System will restore states based on call status
        -- (handled by call sync event handlers)
    end
end

-------------------[ Component Management ]-------------------
-- Validate and set a component reference
-- Returns: component reference or nil if invalid
-- Called from: setupCallSyncComponent, setupRoomControlsComponent, setupMXAComponents
function ShureMXAController:setComponent(ctrl, componentName)
    if not ctrl then return nil end
    
    local componentString = ctrl.String
    
    -- Handle empty selection
    if componentString == "" then
        setProp(ctrl, "Color", "White")
        return nil
    end
    
    -- Handle clear string (user clicked [Clear])
    if componentString == self.clearString then
        ctrl.String = ""
        setProp(ctrl, "Color", "White")
        return nil
    end
    
    -- Try to get the component and validate it exists
    local component = Component.New(componentString)
    local componentControls = Component.GetControls(component)
    
    -- Check if component is valid (has controls)
    if #componentControls < 1 then
        ctrl.String = "[Invalid Component Selected]"
        setProp(ctrl, "Color", "Pink")
        self.invalidComponents[componentName] = true
        self:updateStatus()
        return nil
    end
    
    -- Component is valid
    setProp(ctrl, "Color", "White")
    self.invalidComponents[componentName] = false
    self:updateStatus()
    return component
end

-- Clear all event handlers from a component
-- This prevents memory leaks when switching components
function ShureMXAController:clearComponentHandlers(component, controlNames)
    if not component then return end
    
    for _, controlName in ipairs(controlNames) do
        if component[controlName] then
            setProp(component[controlName], "EventHandler", nil)
        end
    end
end

-- Setup Call Sync component and its event handlers
-- Called from: init() and compCallSync EventHandler
function ShureMXAController:setupCallSyncComponent()
    if not controls.compCallSync then return end
    
    -- Clear old event handlers to prevent duplicates
    self:clearComponentHandlers(self.callSync, {"off.hook", "mute"})
    
    -- Get the new component reference
    self.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    
    if not self.callSync then return end
    
    -- Register event handler for off-hook state changes
    -- This fires when a call starts (true) or ends (false)
    bind(self.callSync["off.hook"], function(ctl)
        if ctl.Boolean then
            -- Call started (off-hook)
            self:handleCallOffHook()
        else
            -- Call ended (on-hook)
            self:handleCallOnHook()
        end
    end)
    
    -- Register event handler for mute state changes
    -- This fires when call mute is toggled
    bind(self.callSync["mute"], function(ctl)
        self:handleCallMute(ctl.Boolean)
    end)
    
    self:debugPrint("Call Sync component configured: " .. controls.compCallSync.String)
end

-- Setup Room Controls component and its event handlers
-- Called from: init() and compRoomControls EventHandler
function ShureMXAController:setupRoomControlsComponent()
    if not controls.compRoomControls then return end
    
    -- Clear old event handlers to prevent duplicates
    self:clearComponentHandlers(self.roomControls, {"ledSystemPower", "ledFireAlarm"})
    
    -- Get the new component reference
    self.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    
    if not self.roomControls then return end
    
    -- Register event handler for system power changes
    -- This fires when system powers on or off
    bind(self.roomControls["ledSystemPower"], function(ctl)
        self:handleSystemPower(ctl.Boolean)
    end)
    
    -- Register event handler for fire alarm state changes
    -- This fires when fire alarm activates or clears
    bind(self.roomControls["ledFireAlarm"], function(ctl)
        self:handleFireAlarm(ctl.Boolean)
    end)
    
    self:debugPrint("Room Controls component configured: " .. controls.compRoomControls.String)
end

-- Setup MXA device components
-- Called from: init() and devMXAs EventHandlers
function ShureMXAController:setupMXAComponents()
    -- Clear existing devices array
    self.mxaDevices = {}
    
    if not controls.devMXAs then return end
    
    -- Loop through each MXA device control
    forEach(controls.devMXAs, function(i, ctrl)
        local device = self:setComponent(ctrl, "MXA [" .. i .. "]")
        
        if device then
            -- Store the device reference
            self.mxaDevices[i] = device
            
            -- Optional: Register event handlers for monitoring device state changes
            -- These are informational only (not required for functionality)
            bind(device.GlobalMute, function(ctl)
                self:debugPrint("MXA [" .. i .. "] Mute changed: " .. tostring(ctl.Boolean))
            end)
            
            bind(device.BrightnessLevel, function(ctl)
                self:debugPrint("MXA [" .. i .. "] Brightness changed: " .. tostring(ctl.Value))
            end)
            
            bind(device.LedUnmuteColor, function(ctl)
                self:debugPrint("MXA [" .. i .. "] Color changed: " .. tostring(ctl.String))
            end)
        end
    end)
    
    self:debugPrint("Configured " .. self:getMXADeviceCount() .. " MXA devices")
end

-- Populate component name choices for dropdown selectors
-- Called from: init()
function ShureMXAController:populateComponentChoices()
    -- Get all components in the design
    local allComponents = Component.GetComponents()
    
    -- Tables to hold component names by type
    local callSyncNames = {}
    local roomControlsNames = {}
    local mxaNames = {}
    
    -- Sort components by type
    for _, comp in pairs(allComponents) do
        if comp.Type == "call_sync" then
            table.insert(callSyncNames, comp.Name)
        elseif comp.Type:match("53a1bc56de2ede23e07c7d9e32bec505") then
            -- MXA plugin type (matches the plugin UUID pattern)
            table.insert(mxaNames, comp.Name)
        elseif comp.Type == "device_controller_script" and comp.Name:match("^compRoomControls") then
            table.insert(roomControlsNames, comp.Name)
        end
    end
    
    -- Sort alphabetically for easier selection
    table.sort(callSyncNames)
    table.sort(roomControlsNames)
    table.sort(mxaNames)
    
    -- Add clear option at the end of each list
    table.insert(callSyncNames, self.clearString)
    table.insert(roomControlsNames, self.clearString)
    table.insert(mxaNames, self.clearString)
    
    -- Update the dropdown choices for each control (using setProp to avoid unnecessary updates)
    setProp(controls.compCallSync, "Choices", callSyncNames)
    setProp(controls.compRoomControls, "Choices", roomControlsNames)
    forEach(controls.devMXAs, function(_, ctrl)
        setProp(ctrl, "Choices", mxaNames)
    end)
    
    self:debugPrint("Populated component choices for dropdowns")
end

-- Update status text based on component validity
-- Called from: setComponent()
function ShureMXAController:updateStatus()
    if not controls.txtStatus then return end
    
    -- Check if any components are invalid
    for _, isInvalid in pairs(self.invalidComponents) do
        if isInvalid then
            controls.txtStatus.String = "Invalid Components"
            controls.txtStatus.Value = 1
            return
        end
    end
    
    -- All components are valid
    controls.txtStatus.String = "OK"
    controls.txtStatus.Value = 0
end

-------------------[ Event Handler Registration ]-------------------
-- Register all main control event handlers
-- Called from: init()
function ShureMXAController:registerEventHandlers()
    -- Main mute button
    -- When user toggles mute, update all MXA devices
    bind(controls.btnMXAMute, function(ctl)
        self:setAllMXAMute(ctl.Boolean)
        self:setAllMXALEDColor(self.ledGreen)
    end)
    
    -- Component selector change handlers
    -- When user selects a different Call Sync component
    bind(controls.compCallSync, function()
        self:setupCallSyncComponent()
    end)
    
    -- When user selects a different Room Controls component
    bind(controls.compRoomControls, function()
        self:setupRoomControlsComponent()
    end)
    
    -- MXA device selector change handlers
    -- When user selects different MXA devices
    bindArray(controls.devMXAs, function(i)
        local device = self:setComponent(controls.devMXAs[i], "MXA [" .. i .. "]")
        if device then
            self.mxaDevices[i] = device
            self:debugPrint("MXA device [" .. i .. "] updated")
        end
    end)
    
    self:debugPrint("Registered all event handlers")
end

-------------------[ Initialization ]-------------------
-- Initialize the controller
-- Called from: Factory function after creating instance
function ShureMXAController:init()
    self:debugPrint("Starting initialization...")
    
    -- Step 1: Populate dropdown choices with available components
    self:populateComponentChoices()
    
    -- Step 2: Setup components based on current selections
    self:setupCallSyncComponent()
    self:setupRoomControlsComponent()
    self:setupMXAComponents()
    
    -- Step 3: Register event handlers for user interactions
    self:registerEventHandlers()
    
    -- Step 4: Set initial state (privacy mode)
    -- All MXAs should start with red LEDs turned off
    self:setAllMXALEDColor(self.ledRed)
    self:setAllMXALEDs(false)
    
    self:debugPrint("Initialized with " .. self:getMXADeviceCount() .. " MXA devices")
end

-------------------[ Cleanup ]-------------------
-- Clean up resources before destroying instance
-- Called manually when instance is no longer needed
function ShureMXAController:cleanup()
    -- Stop the LED toggle timer
    self.ledToggleTimer:Stop()
    
    -- Clear all event handlers to prevent memory leaks
    self:clearComponentHandlers(self.callSync, {"off.hook", "mute"})
    self:clearComponentHandlers(self.roomControls, {"ledSystemPower", "ledFireAlarm"})
    
    -- Clear event handlers from each MXA device
    for i, device in ipairs(self.mxaDevices) do
        self:clearComponentHandlers(device, {"GlobalMute", "BrightnessLevel", "LedUnmuteColor"})
    end
    
    -- Clear all component references
    self.mxaDevices = {}
    self.callSync = nil
    self.roomControls = nil
    self.invalidComponents = {}
    
    self:debugPrint("Cleanup completed")
end

-------------------[ Factory Function ]-------------------
-- Factory function to create a controller instance with error handling
local function createShureMXAController(roomName, config)
    print("Creating Shure MXA Controller for: " .. tostring(roomName))
    
    -- Use pcall to catch any errors during creation
    local success, result = pcall(function()
        local instance = ShureMXAController.new(roomName, config)
        if not instance then return nil end
        instance:init()
        return instance
    end)
    
    if success and result then
        print("Successfully created Shure MXA Controller")
        return result
    else
        local error_msg = success and "Instance creation failed" or tostring(result)
        print("Failed to create controller: " .. error_msg)
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
-- Export the class globally for potential multiple instances
_G.ShureMXAController = ShureMXAController

-- Create default instance
local myMXAController = createShureMXAController("[Shure MXA Controller]")

if myMXAController then
    print("Shure MXA Controller created successfully!")
    _G.myMXAController = myMXAController
else
    print("ERROR: Failed to create Shure MXA Controller!")
end

-------------------[ Usage Examples ]-------------------
--[[
USAGE EXAMPLES - How to use this controller from other scripts:

-- Direct method calls (all methods are now in the main controller)
myMXAController:setAllMXAMute(true)               -- Mute all MXA devices
myMXAController:setAllMXALEDs(true)               -- Turn on all LED rings
myMXAController:setAllMXALEDColor("Green")        -- Set all LEDs to green
myMXAController:handleFireAlarm(true)             -- Activate fire alarm mode

-- Query methods
local deviceCount = myMXAController:getMXADeviceCount()  -- Get number of configured devices

-- Multiple instance creation (if needed for multiple rooms)
local roomAController = ShureMXAController.new("Room A", { debugging = true })
if roomAController then roomAController:init() end

local roomBController = ShureMXAController.new("Room B", { debugging = false })
if roomBController then roomBController:init() end

-- Cleanup when done (important to prevent memory leaks)
myMXAController:cleanup()

-- Reconfigure components programmatically
Controls.compCallSync.String = "Call Sync Conference Room 1"
myMXAController:setupCallSyncComponent()
]]--
