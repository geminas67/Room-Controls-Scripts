--[[
    Audio Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-09-10
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular)
    - Enhanced validation: Comprehensive control validation with descriptive error messages
    - Array normalization: Automatic conversion of single controls to array format
    - Optimized event registration: Batch event registration using handler maps
    - Factory functions: Comprehensive error handling with graceful degradation
    - Property access optimization: Cached references and redundancy prevention
    - State management utilities: resetComponentsArray for dynamic component collections
    - Note: Controls, Component globals are part of Q-SYS framework (expected lint warnings)
]]--

-------------------[ Control References ]-------------------
local controls = {
    compAudioRouter  = Controls.compAudioRouter,
    btnAudioSource   = Controls.btnAudioSource,
    defaultInput     = Controls.defaultInput,
    defaultOutput    = Controls.defaultOutput,
    txtStatus        = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls,
}

local function validateControls()
    local required = {
        compAudioRouter = controls.compAudioRouter,
        btnAudioSource = controls.btnAudioSource,
        defaultInput = controls.defaultInput, 
        txtStatus = controls.txtStatus,
        compRoomControls = controls.compRoomControls
    }
    
    local missing = {}
    for name, control in pairs(required) do
        if not control then 
            table.insert(missing, name) 
        end
    end
    
    if #missing > 0 then
        print("ERROR: AudioRouterController missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end
    
    return true
end

local function normalizeControlArrays()
    -- Normalize btnAudioSource to array if single control
    if controls.btnAudioSource and not controls.btnAudioSource[1] then
        controls.btnAudioSource = {controls.btnAudioSource}
    end
    
    -- Ensure btnAudioSource is an array
    if not controls.btnAudioSource then
        controls.btnAudioSource = {}
    end
end

-------------------[ Utility Functions ]-------------------
local function isArr(obj)
    return type(obj) == "table" and obj[1] ~= nil
end

local function getControlArray(control)
    if not control then return {} end
    return isArr(control) and control or {control}
end

local function setProp(obj, prop, value)
    if not obj or obj[prop] == value then return end
    obj[prop] = value
end

local function bind(control, handler)
    if control and control.EventHandler ~= handler then
        control.EventHandler = handler
    end
end

local function bindArray(controls, handler)
    for i, control in ipairs(controls) do
        if control then
            bind(control, function() handler(i, control) end)
        end
    end
end

local function forEach(arr, func)
    for i, item in ipairs(arr) do
        func(item, i)
    end
end

-------------------[ Component State Management ]-------------------
local function resetComponentsArray(componentsTable)
    -- Clear existing component references safely
    if type(componentsTable) == "table" then
        for key, _ in pairs(componentsTable) do
            componentsTable[key] = nil
        end
    end
    
    -- Return empty table ready for population
    return {}
end

-- AudioRouterController class
AudioRouterController = {}
AudioRouterController.__index = AudioRouterController

-----------------[ Class Constructor ]-------------------
function AudioRouterController.new(config)
    -- Validate controls before proceeding
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays
    normalizeControlArrays()
    
    local self = setmetatable({}, AudioRouterController)
    
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    
    self.inputs = {
        input01 = 1,
        input02 = 2,
        input03 = 3,
        input04 = 4,
        input05 = 5,
        none    = 6,
    }
    self.outputs = {
        output01 = 1
    }
    self.componentTypes = {
        audioRouter  = "router_with_output",
        roomControls = "device_controller_script"
    }
    self.audioRouter  = nil
    self.roomControls = nil
    self.controls = controls
    self:initialize()
    
    return self
end

-----------------------------[ Debug Helper ]-----------------------------
function AudioRouterController:debugPrint(str)
    if self.debugging then
        print("[Audio Router Debug] " .. str)
    end
end

-----------------------------[ Component Management ]-----------------------------
function AudioRouterController:setComponent(ctrl, componentType)
    local componentName = ctrl.String
    
    -- Guard clause: empty component name
    if componentName == "" then
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Guard clause: clear string selected
    if componentName == self.clearString then
        setProp(ctrl, "String", "")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Guard clause: invalid component
    if #Component.GetControls(Component.New(componentName)) < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        self:setComponentInvalid(componentType)
        return nil
    end
    
    -- Main path: valid component
    setProp(ctrl, "Color", "white")
    self:setComponentValid(componentType)
    return Component.New(componentName)
end

function AudioRouterController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:updateStatus()
end

function AudioRouterController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:updateStatus()
end

function AudioRouterController:updateStatus()
    -- Check for any invalid components
    for _, isInvalid in pairs(self.invalidComponents) do
        if isInvalid then
            setProp(self.controls.txtStatus, "String", "Invalid Components")
            setProp(self.controls.txtStatus, "Value", 1)
            return
        end
    end
    -- All components valid
    setProp(self.controls.txtStatus, "String", "OK")
    setProp(self.controls.txtStatus, "Value", 0)
end

-----------------------------[ Component Name Discovery ]-----------------------------
function AudioRouterController:discoverComponents()
    -- Reset component arrays for clean state
    local audioRouterNames = resetComponentsArray({})
    local roomControlsNames = resetComponentsArray({})

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == self.componentTypes.audioRouter then
            table.insert(audioRouterNames, v.Name)
        elseif v.Type == self.componentTypes.roomControls and string.match(v.Name, "^compRoomControls") then
            table.insert(roomControlsNames, v.Name)
        end
    end
    
    table.sort(audioRouterNames)
    table.insert(audioRouterNames, self.clearString)
    setProp(self.controls.compAudioRouter, "Choices", audioRouterNames)
    
    table.sort(roomControlsNames)
    table.insert(roomControlsNames, self.clearString)
    setProp(self.controls.compRoomControls, "Choices", roomControlsNames)
end

-----------------------------[ Default Input Setup ]-----------------------------
function AudioRouterController:setupDefaultInputChoices()
    local inputChoices = {"Sonos 1", "Sonos 2", "Sonos 3", "Input 4", "Great Hall"}
    
    setProp(self.controls.defaultInput, "Choices", inputChoices)
    
    -- Set default to Sonos 1 if no selection
    if self.controls.defaultInput.Value == 0 then
        setProp(self.controls.defaultInput, "Value", 1)
    end
end

function AudioRouterController:getSelectedDefaultInput()
    local choiceText = self.controls.defaultInput.String or "Unknown"
    
    -- Map text to correct input number
    local inputMap = {
        ["Sonos 1"] = 1,
        ["Sonos 2"] = 2,
        ["Sonos 3"] = 3,
        ["Input 4"] = 4,
        ["Great Hall"] = 5
    }
    
    return inputMap[choiceText] or 1
end

-----------------------------[ Component Setup ]-----------------------------
function AudioRouterController:setAudioRouterComponent()
    -- Clean up old event handlers if switching devices
    if self.audioRouter and self.audioRouter["select.1"] then
        bind(self.audioRouter["select.1"], nil)
    end

    self.audioRouter = self:setComponent(self.controls.compAudioRouter, "Audio Router")
    if not self.audioRouter then
        return
    end
    
    bind(self.audioRouter["select.1"], function(ctl)
        local inputValue = ctl.Value
        
        -- Direct UI update for responsiveness using utility function
        forEach(self.controls.btnAudioSource, function(btn, i)
            setProp(btn, "Boolean", (i == inputValue))
        end)
        
        self:debugPrint("Audio Router set Output 1 to Input " .. inputValue)
    end)
end

function AudioRouterController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if not self.roomControls then
        return
    end
    
    -- Room controls handler map for batch registration
    local roomControlHandlers = {
        ledSystemPower = function(ctl)
            local route = ctl.Boolean and self:getSelectedDefaultInput() or self.inputs.none
            self:setRoute(route, self.outputs.output01)
            self:debugPrint("Power " .. (ctl.Boolean and "ON" or "OFF") .. " - Set Output 1 to Input " .. route)
        end,
        
        ledFireAlarm = function(ctl)
            if ctl.Boolean then
                -- Fire alarm active: route to none
                self:setRoute(self.inputs.none, self.outputs.output01)
                self:debugPrint("Set Output 1 to Input None")
            else
                -- Fire alarm cleared: revert to last input or default
                if Controls.ledSystemPower.Boolean then
                    local defaultRoute = self.lastInput[self.outputs.output01] or self:getSelectedDefaultInput()
                    self:setRoute(defaultRoute, self.outputs.output01)
                    self:debugPrint("Set Output 1 to Input " .. defaultRoute)
                end
            end
        end
    }
    
    -- Register handlers using batch pattern
    for controlName, handler in pairs(roomControlHandlers) do
        if self.roomControls[controlName] then
            bind(self.roomControls[controlName], handler)
        end
    end
end

-----------------------------[ Audio Routing Functions ]-----------------------------
function AudioRouterController:setRoute(input, output)
    if self.audioRouter then
        -- Ensure input is an integer
        local inputValue = math.floor(tonumber(input) or 1)
        self.audioRouter["select."..tostring(output)].Value = inputValue
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(inputValue))
        self.lastInput[output] = inputValue
    end
end

-----------------------------[ Event Handlers ]-----------------------------
function AudioRouterController:registerEventHandlers()
    -- Component selection handler map
    local componentHandlers = {
        compAudioRouter = function() self:setAudioRouterComponent() end,
        compRoomControls = function() self:setRoomControlsComponent() end,
        defaultInput = function() 
            local value = self.controls.defaultInput.Value
            local text = self.controls.defaultInput.String or "Unknown"
            self:debugPrint("Default input selection changed - Value: " .. tostring(value) .. ", Text: '" .. text .. "'")
        end
    }
    
    -- Register component handlers
    for controlName, handler in pairs(componentHandlers) do
        bind(self.controls[controlName], handler)
    end
    
    -- Audio source button handlers using batch registration
    bindArray(self.controls.btnAudioSource, function(index, control)
        self:setRoute(index, self.outputs.output01)
    end)
end

-----------------------------[ Initialization ]-----------------------------
function AudioRouterController:initialize()
    self:registerEventHandlers()
    self:discoverComponents()
    self:setupDefaultInputChoices()
    self:setAudioRouterComponent()
    self:setRoomControlsComponent()
end

-----------------------------[ Cleanup ]-----------------------------
function AudioRouterController:cleanup()
    -- Clean up audio router event handlers
    if self.audioRouter and self.audioRouter["select.1"] then
        bind(self.audioRouter["select.1"], nil)
    end
    
    -- Clean up room controls event handlers
    if self.roomControls then
        local roomControls = {"ledSystemPower", "ledFireAlarm"}
        forEach(roomControls, function(controlName)
            if self.roomControls[controlName] then
                bind(self.roomControls[controlName], nil)
            end
        end)
    end
    
    -- Clean up component handlers
    bind(self.controls.compAudioRouter, nil)
    bind(self.controls.compRoomControls, nil)
    bind(self.controls.defaultInput, nil)
    
    -- Clean up audio source button handlers
    forEach(self.controls.btnAudioSource, function(btn)
        bind(btn, nil)
    end)
end

-----------------------------[ Factory Function ]-----------------------------
local function createAudioRouterController(config)
    local defaultConfig = {
        debugging = true
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return AudioRouterController.new(controllerConfig)
    end)
    
    if success then
        if controller then
            print("Successfully created Audio Router Controller")
            return controller
        else
            print("Failed to create controller: validation failed")
            return nil
        end
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

-----------------------------[ Global Exports ]-----------------------------
-- Export class and factory for external access and multiple instances
_G.AudioRouterController = AudioRouterController
_G.createAudioRouterController = createAudioRouterController

-----------------------------[ Instance Creation ]-----------------------------
-- Create the main audio router controller instance
myAudioRouterController = createAudioRouterController()

-- Export instance globally for external access
_G.myAudioRouterController = myAudioRouterController

-----------------------------[ Usage Examples ]-----------------------------
--[[
-- Example usage of the audio router controller:

-- Create additional instances with custom config
local customController = createAudioRouterController({debugging = false})

-- Set a route manually
if myAudioRouterController then
    myAudioRouterController:setRoute(1, 1)  -- Set Output 1 to Input 1
end

-- Get current route (if audio router is available)
if myAudioRouterController and myAudioRouterController.audioRouter then
    local currentInput = myAudioRouterController.audioRouter["select.1"].Value
    
    -- Update source buttons to reflect current state using utility functions
    forEach(Controls.btnAudioSource, function(btn, i)
        setProp(btn, "Boolean", (i == currentInput))
    end)
end

-- Clean up when done
-- if myAudioRouterController then
--     myAudioRouterController:cleanup()
-- end
]]-- 