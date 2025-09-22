--[[
    ShureMXAController (Refactored) - plugin version 1.1
    Author: Nikolas Smith, Q-SYS
    Version: 4.0 | Date: 2025-09-10
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular).
    - All event registration is DRY and centralized using control/event maps.
    - Each logical domain is its own module; orchestrator is thin.
    - Enhanced with state management utilities for component arrays.
    - Optimized for responsiveness and direct component access.
    - Uses metatable-based class construction for multiple instances and inheritance.
    - Implements early returns and guard clauses for flattened control flow.
    - Streamlined component access with reduced redundant calls.
    
    Performance Optimizations:
    - Batch event registration with handler maps for MXA devices
    - Eliminated double lookups by passing device references directly  
    - Guarded property setting to avoid redundant assignments
    - Normalized control arrays at initialization to reduce type checking
    - Optimized utility functions for pre-normalized data structures
]]

-------------------[ Control References ]-------------------
local controls = {
    devMXAs = Controls.devMXAs,
    btnMXAMute = Controls.btnMXAMute,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus,
}

-------------------[ Utility Functions ]-------------------
local function isArr(t) return type(t) == "table" and t[1] ~= nil end
local function getControlArray(ctrl) 
    -- Optimized for pre-normalized arrays
    return ctrl and (isArr(ctrl) and ctrl or {ctrl}) or {}
end
local function setProp(ctrl, prop, val) 
    if ctrl and ctrl[prop] ~= val then ctrl[prop] = val end 
end
local function bind(ctrl, handler) if ctrl then ctrl.EventHandler = handler end end
local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end
local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

local function validateControls()
    local required = { "devMXAs", "btnMXAMute" }
    local missing = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

local function normalizeControlArrays()
    -- Standardize control arrays at setup to reduce type checking
    if controls.devMXAs and not isArr(controls.devMXAs) then
        controls.devMXAs = { controls.devMXAs }
    end
end

-------------------[ State Management Utility ]-------------------
local function resetComponentsArray(componentArray, arrayName, debugCallback)
    if not componentArray then return {} end
    
    local cleared = {}
    for k in pairs(componentArray) do
        componentArray[k] = nil
        table.insert(cleared, k)
    end
    
    if debugCallback and #cleared > 0 then
        debugCallback("Reset " .. arrayName .. " array: " .. table.concat(cleared, ", "))
    end
    
    return componentArray
end

-------------------[ Base Module Class ]-------------------
local BaseModule = {}; BaseModule.__index = BaseModule
function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    return self
end
function BaseModule:debug(msg)
    if self.controller.debugging then
        self.controller:debugPrint("[" .. self.name .. "] " .. msg)
    end
end

-------------------[ Component Management Module ]-------------------
local ComponentModule = setmetatable({}, BaseModule); ComponentModule.__index = ComponentModule
function ComponentModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "ComponentModule"), ComponentModule)
    self.componentTypes = {
        callSync = "call_sync",
        mxaDevices = "%PLUGIN%_15f47939-2779-495a-881b-b10317365958_%FP%_53a1bc56de2ede23e07c7d9e32bec505",
        roomControls = "device_controller_script"
    }
    self.components = { callSync = nil, roomControls = nil, mxaDevices = {}, invalid = {} }
    return self
end

function ComponentModule:resetMXADevices()
    resetComponentsArray(self.components.mxaDevices, "MXA devices", function(msg) self:debug(msg) end)
end

function ComponentModule:setComponent(ctrl, componentType)
    if not ctrl then
        self:debug("Control is nil for: " .. componentType)
        return nil
    end
    
    local componentName = ctrl.String
    
    -- Early return for empty component
    if componentName == "" then
        self:setComponentValid(componentType)
        setProp(ctrl, "Color", self.controller.config.controlColors.white)
        return nil
    end
    
    -- Early return for clear string
    if componentName == self.controller.clearString then
        ctrl.String = ""
        setProp(ctrl, "Color", self.controller.config.controlColors.white)
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Validate component
    local componentControls = Component.GetControls(Component.New(componentName))
    if #componentControls < 1 then
        ctrl.String = "[Invalid Component Selected]"
        setProp(ctrl, "Color", self.controller.config.controlColors.pink)
        self:setComponentInvalid(componentType)
        return nil
    end
    
    setProp(ctrl, "Color", self.controller.config.controlColors.white)
    self:setComponentValid(componentType)
    return Component.New(componentName)
end

function ComponentModule:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self.controller:updateStatus()
end

function ComponentModule:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self.controller:updateStatus()
end

function ComponentModule:getComponentNames()
    local namesTable = { RoomControlsNames = {}, CallSyncNames = {}, MXANames = {} }
    
    -- Single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == self.componentTypes.mxaDevices then
            table.insert(namesTable.MXANames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end
    
    -- Sort and add clear option
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.controller.clearString)
    end
    
    -- Update control choices
    setProp(controls.compRoomControls, "Choices", namesTable.RoomControlsNames)
    setProp(controls.compCallSync, "Choices", namesTable.CallSyncNames)
    forEach(controls.devMXAs, function(_, ctrl) setProp(ctrl, "Choices", namesTable.MXANames) end)
end

-------------------[ MXA Device Module ]-------------------
local MXAModule = setmetatable({}, BaseModule); MXAModule.__index = MXAModule
function MXAModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "MXAModule"), MXAModule)
    return self
end

function MXAModule:setAllLEDs(state)
    local value = state and self.controller.config.ledBrightness or self.controller.config.ledOff
    for _, device in pairs(self.controller.componentModule.components.mxaDevices) do
        if device and device.BrightnessLevel then
            device.BrightnessLevel.Value = value
        end
    end
end

function MXAModule:setAllLEDsColor(color)
    for _, device in pairs(self.controller.componentModule.components.mxaDevices) do
        if device and device.LedUnmuteColor then
            device.LedUnmuteColor.String = color
        end
    end
end

function MXAModule:setAllMute(state)
    self.controller.state.muteState = state
    for _, device in pairs(self.controller.componentModule.components.mxaDevices) do
        if device and device.GlobalMute then
            device.GlobalMute.Boolean = state
        end
    end
end

function MXAModule:getDeviceCount()
    local count = 0
    for _, device in pairs(self.controller.componentModule.components.mxaDevices) do 
        if device then count = count + 1 end 
    end
    return count
end

function MXAModule:startLEDToggle()
    self.controller.ledToggleTimer:Start(self.controller.config.ledToggleInterval)
    self:debug("Started LED toggle timer")
end

function MXAModule:stopLEDToggle()
    self.controller.ledToggleTimer:Stop()
    self:debug("Stopped LED toggle timer")
end

-------------------[ Privacy Control Module ]-------------------
local PrivacyModule = setmetatable({}, BaseModule); PrivacyModule.__index = PrivacyModule
function PrivacyModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "PrivacyModule"), PrivacyModule)
    return self
end

function PrivacyModule:setLEDColor(state)
    local color = state and self.controller.config.ledRed or self.controller.config.ledGreen
    self.controller.mxaModule:setAllLEDsColor(color)
    self:debug("Audio Privacy LED: " .. color)
end

function PrivacyModule:setAudioPrivacy(state)
    self.controller.state.audioPrivacy = state
    self:setLEDColor(state)
end

function PrivacyModule:getPrivacyState()
    return self.controller.state.audioPrivacy
end

-------------------[ System Control Module ]-------------------
local SystemModule = setmetatable({}, BaseModule); SystemModule.__index = SystemModule
function SystemModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "SystemModule"), SystemModule)
    return self
end

function SystemModule:setFireAlarm(state)
    self.controller.state.fireAlarm = state
    
    if state then
        self:debug("Fire Alarm Active")
        self.controller.mxaModule:startLEDToggle()
        self.controller.privacyModule:setLEDColor(true)
        self.controller.mxaModule:setAllLEDs(false)
        return
    end
    
    -- Fire alarm cleared
    self.controller.mxaModule:stopLEDToggle()
    local callSync = self.controller.componentModule.components.callSync
    
    if not callSync or not callSync["off.hook"] then return end
    
    local isOffHook = callSync["off.hook"].Boolean
    if isOffHook then
        self:debug("Fire Alarm Cleared - Call Off-Hook")
        self.controller.privacyModule:setLEDColor(false)
        self.controller.mxaModule:setAllLEDs(true)
    else
        self:debug("Fire Alarm Cleared - Call On-Hook")
        self.controller.privacyModule:setLEDColor(true)
        self.controller.mxaModule:setAllLEDs(false)
    end
end

-------------------[ Call Control Module ]-------------------
local CallModule = setmetatable({}, BaseModule); CallModule.__index = CallModule
function CallModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "CallModule"), CallModule)
    return self
end

function CallModule:setHookState(state)
    self:debug("Call Sync Hook: " .. tostring(state))
    self.controller.mxaModule:setAllLEDs(state)
end

function CallModule:setMuteState(state)
    self:debug("Call Sync Mute: " .. tostring(state))
    self.controller.privacyModule:setLEDColor(state)
end

function CallModule:endCall()
    local callSync = self.controller.componentModule.components.callSync
    if not callSync or not callSync["end.call"] then return end
    
    callSync["end.call"]:Trigger()
    self:debug("End call triggered")
end

-------------------[ Main Controller Class ]-------------------
ShureMXAController = {}; ShureMXAController.__index = ShureMXAController

function ShureMXAController.new(roomName, config)
    if not validateControls() then return nil end
    
    -- Normalize control arrays upfront for efficiency
    normalizeControlArrays()
    
    local self = setmetatable({}, ShureMXAController)
    self.roomName = roomName or "Shure MXA"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    
    self.state = {
        audioPrivacy = false,
        systemPower = false, 
        fireAlarm = false,
        ledState = false, 
        muteState = false
    }
    
    self.config = {
        ledBrightness = (config and config.ledBrightness) or 5,
        ledOff = (config and config.ledOff) or 0,
        ledRed = (config and config.ledRed) or "Red",
        ledGreen = (config and config.ledGreen) or "Green",
        controlColors = { white = 'White', pink = 'Pink', off = 'Off' },
        ledToggleInterval = 1.5
    }
    
    -- Initialize modules (declared below)
    self.componentModule = nil
    self.mxaModule = nil
    self.privacyModule = nil
    self.systemModule = nil
    self.callModule = nil
    
    -- Initialize timer
    self.ledToggleTimer = Timer.New()
    self.ledToggleTimer.EventHandler = function()
        self.state.ledState = not self.state.ledState
        self.mxaModule:setAllLEDs(self.state.ledState)
    end
    
    return self
end

function ShureMXAController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." MXA] "..str) end
end

function ShureMXAController:initializeModules()
    self.componentModule = ComponentModule.new(self)
    self.mxaModule = MXAModule.new(self)
    self.privacyModule = PrivacyModule.new(self)
    self.systemModule = SystemModule.new(self)
    self.callModule = CallModule.new(self)
end

function ShureMXAController:updateStatus()
    if not controls.txtStatus then return end
    
    for _, v in pairs(self.componentModule.components.invalid) do
        if v == true then
            controls.txtStatus.String = "Invalid Components"
            controls.txtStatus.Value = 1
            return
        end
    end
    controls.txtStatus.String = "OK"
    controls.txtStatus.Value = 0
end

-------------------[ Component Setup Methods ]-------------------
function ShureMXAController:setupCallSyncComponent()
    if not controls.compCallSync then return end
    
    self.componentModule.components.callSync = self.componentModule:setComponent(controls.compCallSync, "Call Sync")
    if self.componentModule.components.callSync then
        self:registerCallSyncEventHandlers()
    end
end

function ShureMXAController:setupRoomControlsComponent()
    if not controls.compRoomControls then return end
    
    self.componentModule.components.roomControls = self.componentModule:setComponent(controls.compRoomControls, "Room Controls")
    if self.componentModule.components.roomControls then
        self:registerRoomControlsEventHandlers()
    end
end

function ShureMXAController:setupMXAComponents()
    self.componentModule:resetMXADevices()
    if not controls.devMXAs then return end
    
    forEach(controls.devMXAs, function(i, ctrl)
        local device = self.componentModule:setComponent(ctrl, "MXA [" .. i .. "]")
        if device then
            self.componentModule.components.mxaDevices[i] = device
            -- Pass device directly to avoid double lookup
            self:registerMXAEventHandlers(i, device)
        end
    end)
end

function ShureMXAController:setupComponents()
    self:setupCallSyncComponent()
    self:setupRoomControlsComponent()
    self:setupMXAComponents()
end

-------------------[ Event Handler Registration ]-------------------
function ShureMXAController:registerCallSyncEventHandlers()
    local callSync = self.componentModule.components.callSync
    if not callSync then return end
    
    -- Register off-hook state handler
    bind(callSync["off.hook"], function(ctl) self.callModule:setHookState(ctl.Boolean) end)
    
    -- Register mute state handler
    bind(callSync["mute"], function(ctl) self.callModule:setMuteState(ctl.Boolean) end)
end

function ShureMXAController:registerRoomControlsEventHandlers()
    local roomControls = self.componentModule.components.roomControls
    if not roomControls then return end
    
    -- System power handler with early return optimization
    bind(roomControls["ledSystemPower"], function(ctl)
        if not ctl.Boolean then
            self.privacyModule:setLEDColor(true)
            self.mxaModule:setAllLEDs(false)
            self:debugPrint("System Power OFF - All MXAs muted and LEDs off")
            return
        end
        self:debugPrint("System Power ON - Restoring MXA states")
    end)
    
    -- Fire alarm handler
    bind(roomControls["ledFireAlarm"], function(ctl) 
        self.systemModule:setFireAlarm(ctl.Boolean)
    end)
end

function ShureMXAController:registerMXAEventHandlers(idx, device)
    if not device then return end
    
    -- Batch event registration with handler map for efficiency
    local handlerMap = {
        GlobalMute = function(ctl) 
            self:debugPrint("MXA [" .. idx .. "] Mute: " .. tostring(ctl.Boolean))
        end,
        BrightnessLevel = function(ctl) 
            self:debugPrint("MXA [" .. idx .. "] Brightness: " .. tostring(ctl.Value))
        end,
        LedUnmuteColor = function(ctl) 
            self:debugPrint("MXA [" .. idx .. "] Unmute Color: " .. tostring(ctl.String))
        end
    }
    
    -- Single loop for all event bindings
    for controlName, handler in pairs(handlerMap) do
        bind(device[controlName], handler)
    end
end

function ShureMXAController:registerEventHandlers()
    -- Main mute button handler - direct and optimized
    bind(controls.btnMXAMute, function(ctl) 
        self.mxaModule:setAllMute(ctl.Boolean)
        self.mxaModule:setAllLEDsColor(self.config.ledGreen)
    end)
    
    -- Component selection handlers
    bind(controls.compRoomControls, function() self:setupRoomControlsComponent() end)
    bind(controls.compCallSync, function() self:setupCallSyncComponent() end)
    
    -- MXA device selection handlers
    bindArray(controls.devMXAs, function(i) 
        local device = self.componentModule:setComponent(controls.devMXAs[i], "MXA [" .. i .. "]")
        if device then
            self.componentModule.components.mxaDevices[i] = device
            -- Pass device directly to avoid double lookup
            self:registerMXAEventHandlers(i, device)
        end
    end)
end

-------------------[ Initialization Methods ]-------------------
function ShureMXAController:performSystemInitialization()
    self:debugPrint("System initialization")
    self.privacyModule:setLEDColor(true)
    self.mxaModule:setAllLEDs(false)
    self:debugPrint("System initialization completed")
end

function ShureMXAController:init()
    self:debugPrint("Starting initialization...")
    
    -- Initialize modules first
    self:initializeModules()
    
    -- Component discovery and setup
    self.componentModule:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    self:debugPrint("Initialized with " .. self.mxaModule:getDeviceCount() .. " MXA devices")
end

-------------------[ Cleanup Methods ]-------------------
function ShureMXAController:cleanup()
    self.ledToggleTimer:Stop()
    
    -- Clear event handlers for components
    local components = self.componentModule.components
    
    if components.callSync then
        setProp(components.callSync["off.hook"], "EventHandler", nil)
        setProp(components.callSync["mute"], "EventHandler", nil)
    end
    
    if components.roomControls then
        setProp(components.roomControls["ledSystemPower"], "EventHandler", nil)
        setProp(components.roomControls["ledFireAlarm"], "EventHandler", nil)
    end
    
    for _, device in pairs(components.mxaDevices) do
        if device then
            setProp(device["GlobalMute"], "EventHandler", nil)
            setProp(device["BrightnessLevel"], "EventHandler", nil)
            setProp(device["LedUnmuteColor"], "EventHandler", nil)
        end
    end
    
    -- Reset component references
    resetComponentsArray(components.mxaDevices, "MXA devices", function(msg) self:debugPrint(msg) end)
    components.callSync = nil
    components.roomControls = nil
    components.invalid = {}
    
    self:debugPrint("Cleanup completed")
end

-------------------[ Factory Function ]-------------------
local function createShureMXAController(roomName, config)
    print("Creating Shure MXA Controller for: " .. tostring(roomName))
    
    local success, result = pcall(function()
        local instance = ShureMXAController.new(roomName, config)
        if not instance then return nil end
        
        instance:init()
        return instance
    end)
    
    if success and result then
        print("Successfully created Shure MXA Controller for " .. roomName)
        return result
    else
        local error_msg = success and "Instance creation failed" or tostring(result)
        print("Failed to create controller for " .. roomName .. ": " .. error_msg)
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
-- Export the class for potential multiple instances
_G.ShureMXAController = ShureMXAController

-- Create default instance
local formattedRoomName = "[Shure MXA Controller]"
local myMXAController = createShureMXAController(formattedRoomName)

if myMXAController then
    print("Shure MXA Controller created successfully!")
    -- Export instance globally for external access
    _G.myMXAController = myMXAController
else
    print("ERROR: Failed to create Shure MXA Controller!")
end

-------------------[ Usage Examples ]-------------------
--[[
-- Refactored Usage Examples - New Modular API

-- Direct MXA control (optimized modular approach)
myMXAController.mxaModule:setAllMute(true)
myMXAController.mxaModule:setAllLEDs(true)
myMXAController.mxaModule:setAllLEDsColor("Green")

-- Privacy control via privacy module
myMXAController.privacyModule:setAudioPrivacy(true)
local privacyState = myMXAController.privacyModule:getPrivacyState()

-- System control via system module
myMXAController.systemModule:setFireAlarm(true)

-- Call control via call module
myMXAController.callModule:endCall()
myMXAController.callModule:setHookState(true)
myMXAController.callModule:setMuteState(false)

-- Device count and status queries
local deviceCount = myMXAController.mxaModule:getDeviceCount()

-- Component management
myMXAController.componentModule:resetMXADevices()
myMXAController.componentModule:getComponentNames()

-- Multiple instance creation example
local roomAController = ShureMXAController.new("Room A", { debugging = true })
if roomAController then roomAController:init() end

-- Cleanup when done
myMXAController:cleanup()
]]--

