--[[
  Planar DisplayWallController (Refactored) - Q-SYS Control Script for Planar Display Wall
  Author: Nikolas Smith, Q-SYS
  Date: 2025-09-10
  Version: 2.0 (Refactored)
  Firmware Req: 10.0.0
  Description: Controls Planar Display Wall components with power management,
  input switching, and display wall configuration. 
  Integrates with SystemAutomationController.
  
  REFACTORED FEATURES:
  - Enhanced validation: Comprehensive control validation with descriptive error messages
  - Array normalization: Automatic conversion of single controls to array format  
  - Optimized event registration: Batch event registration using handler maps
  - BaseModule pattern: Improved module architecture with initialization and cleanup
  - Factory functions: Comprehensive error handling with graceful degradation
  - Property access optimization: Cached references and redundancy prevention
  - State management utilities: Dynamic component array management following SystemAutomationController patterns
  - Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
]]--

-- Display Control Configuration (easily changeable for different manufacturers)
local displayControls = {
    -- Power Controls
    powerOn     = "PowerOn",
    powerOff    = "PowerOff", 
    powerIsOn   = "PowerIsOn",
    powerIsOff  = "PowerIsOff",
    
     --[[
    Input Controls (Option 1: ComboBox method) 
    vInputSelectComboBox = "InputSelectComboBox",
    vInputStatusLED = "InputStatus",
    ]]--
    
    -- Input Controls (Option 2: Button method)
    inputSelectButtons = "VideoInputs ",
    inputNames = "InputNames ",
    currentInput = "CurrentInput ",
    
    -- Wall Configuration
    wallMode = "WallMode",
    wallPosition = "WallPosition"
}

-------------------[ Control References ]-------------------
local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
    compRoomControls = Controls.compRoomControls,
    roomName = Controls.roomName,
    ledDisplayPower = Controls.ledDisplayPower,
    ledDisplayInput = Controls.ledDisplayInput,
    ledDisplayWallMode = Controls.ledDisplayWallMode,
    ledDisplayWarming = Controls.ledDisplayWarming,
    ledDisplayCooling = Controls.ledDisplayCooling,
    btnDisplayPowerAll = Controls.btnDisplayPowerAll,
    btnDisplayPowerOn = Controls.btnDisplayPowerOn,
    btnDisplayPowerOff = Controls.btnDisplayPowerOff,
    btnDisplayPowerSingle = Controls.btnDisplayPowerSingle,
    btnDisplayInputAll = Controls.btnDisplayInputAll,
    btnDisplayWallConfig = Controls.btnDisplayWallConfig,
    txtDisplayWallMode = Controls.txtDisplayWallMode
}

local function validateControls()
    local required = {
        txtStatus = controls.txtStatus,
        devDisplays = controls.devDisplays
    }
    
    local optional = {
        compRoomControls = controls.compRoomControls,
        roomName = controls.roomName,
        ledDisplayPower = controls.ledDisplayPower,
        btnDisplayPowerAll = controls.btnDisplayPowerAll,
        txtDisplayWallMode = controls.txtDisplayWallMode
    }
    
    local missing = {}
    local warnings = {}
    
    -- Check required controls
    for name, control in pairs(required) do
        if not control then
            table.insert(missing, name)
        end
    end
    
    -- Check optional controls for warnings
    for name, control in pairs(optional) do
        if not control then
            table.insert(warnings, name)
        end
    end
    
    -- Report missing required controls
    if #missing > 0 then
        print("ERROR: PlanarDisplayWallController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    -- Report missing optional controls as warnings
    if #warnings > 0 then
        print("WARNING: PlanarDisplayWallController - Missing optional controls (reduced functionality):")
        for _, name in ipairs(warnings) do
            print("  - " .. name)
        end
    end
    
    print("PlanarDisplayWallController validation passed - All required controls found")
    return true
end

local function normalizeControlArrays()
    -- Normalize array controls to consistent structures
    local arrayControls = {
        'devDisplays', 'btnDisplayPowerOn', 'btnDisplayPowerOff', 'btnDisplayPowerSingle'
    }
    
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then
            -- Convert single control to array format
            controls[controlName] = { ctrl }
        end
    end
end

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end  -- Guard against redundant assignments
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        if ctrl then fn(i, ctrl) end 
    end
end

-------------------[ State Management Utility ]-------------
local function resetComponentsArray()
    -- State management utility for dynamic component arrays
    -- Following SystemAutomationController pattern for consistency
    local componentState = {
        displays = {},
        roomControls = {},
        initialized = false
    }
    
    -- Clear any existing component references
    for category, components in pairs(componentState) do
        if type(components) == "table" then
            for k in pairs(components) do
                components[k] = nil
            end
        end
    end
    
    componentState.initialized = true
    return componentState
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

function BaseModule:safeAccess(component, control, action, value)
    return self.controller:safeComponentAccess(component, control, action, value)
end

function BaseModule:init()
    self.initialized = true
    self:debug("Module initialized")
end

function BaseModule:cleanup() 
    self.initialized = false
    self:debug("Cleanup complete") 
end

--------** Class Definition **--------
PlanarDisplayWallController = {}
PlanarDisplayWallController.__index = PlanarDisplayWallController

function PlanarDisplayWallController.new(roomName, config)
    -- Validate controls before initialization
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays at initialization
    normalizeControlArrays()
    
    local self = setmetatable({}, PlanarDisplayWallController)
    
    -- Initialize state management
    self.componentState = resetComponentsArray()
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        displays = "%PLUGIN%_404F4311-A38D-4891-AF61-709B8F48A6E1_%FP%_77008e895ac50ad 1242e3dee981c5e4", -- Planar Display
        roomControls = "device_controller_script" -- Will be filtered to only those starting with "compRoomControls"
    }
    
    -- Component storage
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        displayWallMode = "Single", -- Single, 2x2, 3x3, etc.
        lastInput = "HDMI1",
        powerState = false,
        isWarming = false,
        isCooling = false
    }
    
    -- Configuration
    self.config = {
        maxDisplays = config and config.maxDisplays or 9, -- Maximum number of displays supported
        defaultInput = "HDMI1",
        displayWallModes = {"Single", "2x2", "3x3", "4x4", "Custom"},
        inputChoices = {"HDMI1", "HDMI2", "DisplayPort", "USB-C"}
    }
    
    -- Input to button mapping
    self.inputButtonMap = {
        HDMI1 = 1, HDMI2 = 2, DisplayPort = 3, USB_C = 4,
        DVI = 5, VGA = 6, Component = 7, Composite = 8, S_Video = 9, RF = 10
    }
    
    -- Timers
    self.timers = {
        warmup = Timer.New(),
        cooldown = Timer.New()
    }
    
    -- Timer Configuration (instance-specific, dynamically updated from room controls component)
    self.timerConfig = {
        warmupTime = 7,  -- Default fallback values
        cooldownTime = 5
    }
    
    -- Initialize modules using BaseModule pattern
    self.displayModule = DisplayModule:new(self)
    self.powerModule = PowerModule:new(self)
    
    -- Initialize timer configuration
    self:updateTimerConfigFromComponent()
    return self
end

--------** Dynamic Timer Configuration **--------
function PlanarDisplayWallController:updateTimerConfigFromComponent()
    -- Default fallback values
    local defaultWarmupTime = 7
    local defaultCooldownTime = 5
    
    if self.components.compRoomControls then
        local success, result = pcall(function()
            -- Try to get warmup time from room controls component
            if self.components.compRoomControls["warmupTime"] then
                local warmupTime = self.components.compRoomControls["warmupTime"].Value
                if warmupTime and warmupTime > 0 then
                    self.timerConfig.warmupTime = warmupTime
                    self:debugPrint("Updated warmup time from component: " .. warmupTime .. " seconds")
                else
                    self.timerConfig.warmupTime = defaultWarmupTime
                    self:debugPrint("Using default warmup time: " .. defaultWarmupTime .. " seconds")
                end
            else
                self.timerConfig.warmupTime = defaultWarmupTime
                self:debugPrint("Using default warmup time: " .. defaultWarmupTime .. " seconds")
            end
            
            -- Try to get cooldown time from room controls component
            if self.components.compRoomControls["cooldownTime"] then
                local cooldownTime = self.components.compRoomControls["cooldownTime"].Value
                if cooldownTime and cooldownTime > 0 then
                    self.timerConfig.cooldownTime = cooldownTime
                    self:debugPrint("Updated cooldown time from component: " .. cooldownTime .. " seconds")
                else
                    self.timerConfig.cooldownTime = defaultCooldownTime
                    self:debugPrint("Using default cooldown time: " .. defaultCooldownTime .. " seconds")
                end
            else
                self.timerConfig.cooldownTime = defaultCooldownTime
                self:debugPrint("Using default cooldown time: " .. defaultCooldownTime .. " seconds")
            end
        end)
        
        if not success then
            self:debugPrint("Warning: Failed to update timer config from component: " .. tostring(result))
            -- Set fallback values on error
            self.timerConfig.warmupTime = defaultWarmupTime
            self.timerConfig.cooldownTime = defaultCooldownTime
        end
    else
        -- No room controls component available, use defaults
        self.timerConfig.warmupTime = defaultWarmupTime
        self.timerConfig.cooldownTime = defaultCooldownTime
        self:debugPrint("No room controls component available, using default timing values")
    end
end

function PlanarDisplayWallController:getTimerConfig(isWarmup)
    -- Update timer config from component first
    self:updateTimerConfigFromComponent()
    
    if isWarmup then
        return self.timerConfig.warmupTime
    else
        return self.timerConfig.cooldownTime
    end
end

--------** Debug Helper **--------
function PlanarDisplayWallController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Input Button Mapping **--------
function PlanarDisplayWallController:getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = self.inputButtonMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

--------** Safe Component Access **--------
function PlanarDisplayWallController:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value
                return true
            elseif action == "setPosition" then
                component[control].Position = value
                return true
            elseif action == "setString" then
                component[control].String = value
                return true
            elseif action == "trigger" then
                component[control]:Trigger()
                return true
            elseif action == "get" then
                return component[control].Boolean
            elseif action == "getPosition" then
                return component[control].Position
            elseif action == "getString" then
                return component[control].String
            end
        end
        return false
    end)
    
    if not success then
        self:debugPrint("Component access error: " .. tostring(result))
        return false
    end
    return result
end

-------------------[ Display Module ]----------------------
local DisplayModule = setmetatable({}, BaseModule); DisplayModule.__index = DisplayModule

function DisplayModule:new(controller)
    local self = BaseModule.new(controller, "Display")
    setmetatable(self, DisplayModule)
    self:init()
    return self
end

function DisplayModule:powerAll(state)
    self:debug("Powering all displays: " .. tostring(state))
    for i, display in pairs(self.controller.components.displays) do
        if display then
            local control = state and displayControls.powerOn or displayControls.powerOff
            self:safeAccess(display, control, "trigger")
        end
    end
    self.controller.state.powerState = state
    setProp(controls.ledDisplayPower, "Boolean", state)
end

function DisplayModule:powerSingle(index, state)
    local display = self.controller.components.displays[index]
    if display then
        local control = state and displayControls.powerOn or displayControls.powerOff
        self:safeAccess(display, control, "trigger")
        self:debug("Display " .. index .. " power: " .. tostring(state))
    end
end

function DisplayModule:setInputAll(input)
    self:debug("Setting all displays to input: " .. input)
    for i, display in pairs(self.controller.components.displays) do
        if display then
            -- Try Option 1: InputSelectComboBox (if available)
            if display[displayControls.vInputSelectComboBox] then
                self:safeAccess(display, displayControls.vInputSelectComboBox, "setString", input)
            else
                -- Fallback to Option 2: InputSelectButtons
                local buttonNumber = self.controller:getInputButtonNumber(input)
                if buttonNumber then
                    local buttonName = displayControls.inputSelectButtons .. buttonNumber
                    self:safeAccess(display, buttonName, "trigger")
                end
            end
        end
    end
    self.controller.state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

function DisplayModule:setInputSingle(index, input)
    local display = self.controller.components.displays[index]
    if display then
        -- Try Option 1: InputSelectComboBox (if available)
        if display[displayControls.vInputSelectComboBox] then
            self:safeAccess(display, displayControls.vInputSelectComboBox, "setString", input)
            self:debug("Display " .. index .. " input: " .. input .. " (via ComboBox)")
        else
            -- Fallback to Option 2: InputSelectButtons
            local buttonNumber = self.controller:getInputButtonNumber(input)
            if buttonNumber then
                local buttonName = displayControls.inputSelectButtons .. buttonNumber
                self:safeAccess(display, buttonName, "trigger")
                self:debug("Display " .. index .. " input: " .. input .. " (button " .. buttonNumber .. ")")
            end
        end
    end
end

function DisplayModule:getDisplayCount()
    local count = 0
    for _, display in pairs(self.controller.components.displays) do
        if display then count = count + 1 end
    end
    return count
end

function DisplayModule:getCurrentInput(displayIndex)
    local display = self.controller.components.displays[displayIndex]
    if not display then return nil end
    
    -- Try Option 1: InputSelectComboBox
    if display[displayControls.vInputSelectComboBox] then
        return self:safeAccess(display, displayControls.vInputSelectComboBox, "getString")
    end
    
    -- Option 2: Check CurrentInput 1-10 LEDs to find active input
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl then
            local isActive = self:safeAccess(display, displayControls.currentInput .. i, "get")
            if isActive then
                -- Get the input name from InputNames
                local inputNameControl = display[displayControls.inputNames .. i]
                if inputNameControl then
                    return self:safeAccess(display, displayControls.inputNames .. i, "getString")
                else
                    return "Input " .. i
                end
            end
        end
    end
    
    return nil
end

function DisplayModule:configureDisplayWall(mode)
    self:debug("Configuring display wall mode: " .. mode)
    self.controller.state.displayWallMode = mode
    
    -- Configure display wall based on mode
    local maxDisplays = (mode == "2x2" and 4) or (mode == "3x3" and 9) or 0
    if maxDisplays > 0 then
        for i = 1, maxDisplays do
            if self.controller.components.displays[i] then
                self:safeAccess(self.controller.components.displays[i], displayControls.wallMode, "setString", mode)
                self:safeAccess(self.controller.components.displays[i], displayControls.wallPosition, "setString", "Position" .. i)
            end
        end
    else
        -- Single mode - disable wall mode
        for i, display in pairs(self.controller.components.displays) do
            if display then
                self:safeAccess(display, displayControls.wallMode, "setString", "Single")
            end
        end
    end
    
    setProp(controls.ledDisplayWallMode, "String", mode)
end


-------------------[ Power Module ]------------------------
local PowerModule = setmetatable({}, BaseModule); PowerModule.__index = PowerModule

function PowerModule:new(controller)
    local self = BaseModule.new(controller, "Power")
    setmetatable(self, PowerModule)
    self:init()
    return self
end

function PowerModule:enableDisablePowerControls(state)
    -- Consolidated power controls array
    local allPowerControls = {
        "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
        "btnDisplayPowerAll", "btnDisplayInputAll", "btnDisplayWallConfig"
    }
    
    for _, controlName in ipairs(allPowerControls) do
        local ctrl = controls[controlName]
        if ctrl then
            if isArr(ctrl) then
                -- Handle array controls
                forEach(ctrl, function(i, btn) setProp(btn, "IsDisabled", not state) end)
            else
                -- Handle single controls
                setProp(ctrl, "IsDisabled", not state)
            end
        end
    end
end

function PowerModule:setDisplayPowerFB(state)
    -- Update feedback controls to reflect power state
    setProp(controls.ledDisplayPower, "Boolean", state)
    setProp(controls.btnDisplayPowerAll, "Boolean", state)
end

function PowerModule:updatePowerFeedbackFromDisplays()
    -- Update power feedback based on actual display power status
    local allPoweredOn = true
    local anyPoweredOn = false
    local poweredOnCount = 0
    local totalDisplays = 0
    
    for i, display in pairs(self.controller.components.displays) do
        if display then
            totalDisplays = totalDisplays + 1
            local powerStatus = self.controller:getPowerStatus(display)
            if powerStatus then
                poweredOnCount = poweredOnCount + 1
                anyPoweredOn = true
                
                -- Update individual display power feedback
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[i] then
                    setProp(controls.btnDisplayPowerSingle[i], "Boolean", powerStatus)
                end
            else
                allPoweredOn = false
                
                -- Update individual display power feedback
                if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[i] then
                    setProp(controls.btnDisplayPowerSingle[i], "Boolean", false)
                end
            end
        end
    end
    
    -- Update global power feedback
    if totalDisplays > 0 then
        local globalPowerState = allPoweredOn
        self:setDisplayPowerFB(globalPowerState)
        self.controller.state.powerState = globalPowerState
        self:debug("Power feedback updated - All powered: " .. tostring(allPoweredOn) .. 
                   ", Any powered: " .. tostring(anyPoweredOn) .. 
                   ", Powered count: " .. poweredOnCount .. "/" .. totalDisplays)
    end
end

function PowerModule:powerOnDisplay(index)
    self:debug("Powering on display " .. index)
    self.controller.displayModule:powerSingle(index, true)
    -- Disable individual display power controls during warmup
    self:enableDisablePowerControlIndex(index, false)
    self.controller.state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    self.controller.timers.warmup:Start(self.controller:getTimerConfig(true))
    -- Update power feedback for this specific display
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", true)
    end
end

function PowerModule:powerOffDisplay(index)
    self:debug("Powering off display " .. index)
    self.controller.displayModule:powerSingle(index, false)
    -- Disable individual display power controls during cooldown
    self:enableDisablePowerControlIndex(index, false)
    self.controller.state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    self.controller.timers.cooldown:Start(self.controller:getTimerConfig(false))
    -- Update power feedback for this specific display
    if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", false)
    end
end

function PowerModule:powerOnAll()
    self:debug("Powering on all displays")
    self.controller.displayModule:powerAll(true)
    self:enableDisablePowerControls(false)
    self.controller.state.isWarming = true
    setProp(controls.ledDisplayWarming, "Boolean", true)
    self.controller.timers.warmup:Start(self.controller:getTimerConfig(true))
    self:setDisplayPowerFB(true)
end

function PowerModule:powerOffAll()
    self:debug("Powering off all displays")
    self.controller.displayModule:powerAll(false)
    self:enableDisablePowerControls(false)
    self.controller.state.isCooling = true
    setProp(controls.ledDisplayCooling, "Boolean", true)
    self.controller.timers.cooldown:Start(self.controller:getTimerConfig(false))
    self:setDisplayPowerFB(false)
end

function PowerModule:refreshPowerFeedback()
    -- Manual refresh of power feedback from displays
    self:debug("Manually refreshing power feedback from displays")
    self:updatePowerFeedbackFromDisplays()
end

function PowerModule:enableDisablePowerControlIndex(index, state)
    -- Consolidated array of individual display power controls
    local individualPowerControls = {"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle"}
    
    for _, controlName in ipairs(individualPowerControls) do
        local ctrl = controls[controlName]
        if ctrl and ctrl[index] then
            setProp(ctrl[index], "IsDisabled", not state)
        end
    end
end

--------** Power Status Helper **--------
function PlanarDisplayWallController:getPowerStatus(display)
    if not display then return nil end
    
            -- Check for new dual-control structure first
        if display[displayControls.powerIsOn] and display[displayControls.powerIsOff] then
            local powerIsOn = self:safeComponentAccess(display, displayControls.powerIsOn, "get")
            local powerIsOff = self:safeComponentAccess(display, displayControls.powerIsOff, "get")
        
        -- Return the power state (PowerIsOn takes precedence if both are true)
        if powerIsOn then return true
        elseif powerIsOff then return false
        else return nil -- Neither is true, status unknown
        end
    end
    
            -- Fallback to old single control if it exists
        if display["PowerStatus"] then
            return self:safeComponentAccess(display, "PowerStatus", "get")
        end
    
    return nil
end


--------** Component Management **--------
function PlanarDisplayWallController:setComponent(ctrl, componentType)
    local componentName = ctrl and ctrl.String or nil
    if not componentName or componentName == "" or componentName == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        if ctrl then
            ctrl.String = "[Invalid Component Selected]"
            ctrl.Color = "pink"
        end
        self:setComponentInvalid(componentType)
        return nil
    else
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
end

function PlanarDisplayWallController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function PlanarDisplayWallController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function PlanarDisplayWallController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v == true then
            if Controls.txtStatus then
                Controls.txtStatus.String = "Invalid Components"
                Controls.txtStatus.Value = 1
            end
            return
        end
    end
    if Controls.txtStatus then
        Controls.txtStatus.String = "OK"
        Controls.txtStatus.Value = 0
    end
end

--------** Component Setup **--------
function PlanarDisplayWallController:setupDisplayComponents()
    if not Controls.devDisplays then 
        self:debugPrint("No Controls.devDisplays found")
        return 
    end
    
    self:debugPrint("Setting up " .. #Controls.devDisplays .. " display components")
    for i, displaySelector in ipairs(Controls.devDisplays) do
        if displaySelector then
            self:debugPrint("Setting up display component " .. i)
            self:setDisplayComponent(i)
        end
    end
end

function PlanarDisplayWallController:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    -- Update timer configuration from room controls component
    if self.components.compRoomControls then
        self:updateTimerConfigFromComponent()
    end
end

function PlanarDisplayWallController:setDisplayComponent(index)
    if not Controls.devDisplays or not Controls.devDisplays[index] then
        self:debugPrint("Display control " .. index .. " not found")
        return
    end
    
    local componentType = "Display [" .. index .. "]"
    self.components.displays[index] = self:setComponent(Controls.devDisplays[index], componentType)
    
    if self.components.displays[index] then
        self:debugPrint("Successfully set up display component " .. index)
        self:setupDisplayEvents(index)
        -- Update power feedback to reflect new display status
        self.powerModule.updatePowerFeedbackFromDisplays()
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

--------** Component Event Setup **--------
function PlanarDisplayWallController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring (new dual-control structure)
    if display[displayControls.powerIsOn] then
        display[displayControls.powerIsOn].EventHandler = function()
            local powerIsOn = self:safeComponentAccess(display, displayControls.powerIsOn, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is ON: " .. tostring(powerIsOn))
        end
    end
    
    if display[displayControls.powerIsOff] then
        display[displayControls.powerIsOff].EventHandler = function()
            local powerIsOff = self:safeComponentAccess(display, displayControls.powerIsOff, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is OFF: " .. tostring(powerIsOff))
        end
    end
    
    -- Set up input status monitoring (Option 1: InputSelectComboBox + InputStatus LED)
    if display[displayControls.vInputSelectComboBox] then
        display[displayControls.vInputSelectComboBox].EventHandler = function()
            local currentInput = self:safeComponentAccess(display, displayControls.vInputSelectComboBox, "getString")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " current input: " .. tostring(currentInput))
        end
    end
    
    if display[displayControls.vInputStatusLED] then
        display[displayControls.vInputStatusLED].EventHandler = function()
            local inputActive = self:safeComponentAccess(display, displayControls.vInputStatusLED, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " input active: " .. tostring(inputActive))
        end
    end
    
    -- Set up input status monitoring (Option 2: CurrentInput 1-10 LEDs)
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = self:safeComponentAccess(display, displayControls.currentInput .. i, "get")
                local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
                self:debugPrint("Display " .. componentName .. " input " .. i .. " active: " .. tostring(inputActive))
            end
        end
    end
end

--------** Dynamic Component Discovery **--------
function PlanarDisplayWallController:getComponentNames()
    local namesTable = {
        DisplayNames = {},
        RoomControlsNames = {},
    }

    -- Dynamic component discovery - single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        -- Look for Planar Display components (dynamic discovery)
        if comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    -- Sort and add clear option
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    -- Direct assignment to controls
    if Controls.devDisplays then
        for i, _ in ipairs(Controls.devDisplays) do
            Controls.devDisplays[i].Choices = namesTable.DisplayNames
        end
        self:debugPrint("Set choices for " .. #Controls.devDisplays .. " display controls")
        self:debugPrint("Found " .. #namesTable.DisplayNames .. " display components")
    end
    
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end
end

--------** Room Name Management **--------
function PlanarDisplayWallController:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
        
        -- Also update timer configuration when room controls component is available
        self:updateTimerConfigFromComponent()
    end
end

--------** Timer Event Handlers **--------
function PlanarDisplayWallController:registerTimerHandlers()
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        -- Re-enable all power controls (both global and individual)
        self.powerModule.enableDisablePowerControls(true)
        -- Re-enable individual display power controls for all displays
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
        end
        self.state.isWarming = false
        if Controls.ledDisplayWarming then
            Controls.ledDisplayWarming.Boolean = false
        end
        self.timers.warmup:Stop()
    end

    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        -- Re-enable all power controls (both global and individual)
        self.powerModule.enableDisablePowerControls(true)
        -- Re-enable individual display power controls for all displays
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
        end
        self.state.isCooling = false
        if Controls.ledDisplayCooling then
            Controls.ledDisplayCooling.Boolean = false
        end
        self.timers.cooldown:Stop()
    end
end

--------** Batch Event Registration **--------
function PlanarDisplayWallController:registerEventHandlers()
    -- Single control event handler map
    local singleControlHandlers = {
        compRoomControls = function() self:setRoomControlsComponent() end,
        btnDisplayPowerAll = function(ctl) 
            if ctl.Boolean then self.powerModule:powerOnAll() else self.powerModule:powerOffAll() end 
        end,
        btnDisplayInputAll = function() self.displayModule:setInputAll(self.config.defaultInput) end,
        btnDisplayWallConfig = function()
            local mode = controls.txtDisplayWallMode and controls.txtDisplayWallMode.String or "Single"
            self.displayModule:configureDisplayWall(mode)
        end
    }
    
    -- Register single control handlers
    for controlName, handler in pairs(singleControlHandlers) do
        bind(controls[controlName], handler)
    end
    
    -- Array control event handler map with actions
    local arrayControlHandlers = {
        btnDisplayPowerOn = function(index, ctl) self.powerModule:powerOnDisplay(index) end,
        btnDisplayPowerOff = function(index, ctl) self.powerModule:powerOffDisplay(index) end,
        btnDisplayPowerSingle = function(index, ctl)
            if ctl.Boolean then self.powerModule:powerOnDisplay(index) else self.powerModule:powerOffDisplay(index) end
        end,
        devDisplays = function(index, ctl) self:setDisplayComponent(index) end
    }
    
    -- Register array control handlers using bindArray utility
    for controlName, handler in pairs(arrayControlHandlers) do
        bindArray(controls[controlName], handler)
    end
end

--------** Initialization **--------
function PlanarDisplayWallController:funcInit()
    self:debugPrint("Starting Planar DisplayWallController initialization...")
    
    -- Discover and populate component choices
    self:getComponentNames()
    
    -- Setup components and event handlers
    self:setRoomControlsComponent()
    self:setupDisplayComponents()
    self:registerEventHandlers()
    self:registerTimerHandlers()
    
    -- Update room name from component
    self:updateRoomNameFromComponent()
    
    -- Set initial display wall mode
    if Controls.txtDisplayWallMode then
        Controls.txtDisplayWallMode.Choices = self.config.displayWallModes
        Controls.txtDisplayWallMode.String = self.state.displayWallMode
    end
    
    -- Update power feedback based on current display status
    self.powerModule.updatePowerFeedbackFromDisplays()
    
    -- Update timer configuration from room controls component
    self:updateTimerConfigFromComponent()
    
    self:debugPrint("Planar DisplayWallController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays")
end

--------** Cleanup **--------
function PlanarDisplayWallController:cleanup()
    -- Clear event handlers for displays
    for i, display in pairs(self.components.displays) do
        if display then
            if display[displayControls.powerIsOn] then
                display[displayControls.powerIsOn].EventHandler = nil
            end
            if display[displayControls.powerIsOff] then
                display[displayControls.powerIsOff].EventHandler = nil
            end
            if display["InputStatus"] then
                display["InputStatus"].EventHandler = nil
            end
        end
    end
    
    -- Reset component references
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
end

--------** Enhanced Factory Function **--------
local function createPlanarDisplayWallController(roomName, config)
    local defaultRoomName = roomName or "[Planar Display Wall]"
    print("Creating Planar DisplayWallController for: " .. defaultRoomName)
    
    -- Phase 1: Instance creation with validation
    local success, controller = pcall(function()
        local instance = PlanarDisplayWallController.new(defaultRoomName, config)
        if not instance then
            error("Failed to create controller instance - validation failed")
        end
        return instance
    end)
    
    if not success then
        print("ERROR: Failed to create Planar DisplayWallController instance: " .. tostring(controller))
        return nil, "Instance creation failed: " .. tostring(controller)
    end
    
    -- Phase 2: Initialization with error handling
    local initSuccess, initError = pcall(function()
        controller:funcInit()
    end)
    
    if not initSuccess then
        print("ERROR: Failed to initialize Planar DisplayWallController: " .. tostring(initError))
        -- Attempt cleanup on failed initialization
        if controller.cleanup then
            pcall(function() controller:cleanup() end)
        end
        return nil, "Initialization failed: " .. tostring(initError)
    end
    
    -- Phase 3: Validation of initialized state
    local validationSuccess, validationError = pcall(function()
        if not controller.displayModule or not controller.powerModule then
            error("Critical modules failed to initialize")
        end
        
        if not controller.components or not controller.state then
            error("Core component structures not initialized")
        end
        
        -- Validate timer setup
        if not controller.timers or not controller.timers.warmup or not controller.timers.cooldown then
            error("Timer system not properly initialized")
        end
    end)
    
    if not validationSuccess then
        print("ERROR: Planar DisplayWallController validation failed: " .. tostring(validationError))
        -- Attempt cleanup on failed validation
        if controller.cleanup then
            pcall(function() controller:cleanup() end)
        end
        return nil, "Validation failed: " .. tostring(validationError)
    end
    
    print("Successfully created and initialized Planar DisplayWallController for " .. defaultRoomName)
    return controller, "Success"
end

--------** Global Export and Instance Creation **--------
-- Export the class globally for external access
PlanarDisplayWallController = PlanarDisplayWallController

-- Get room name from room controls component or fallback to control
local function getRoomNameFromComponent()
    -- First try to get from the room controls component if it's already set
    if controls.compRoomControls and controls.compRoomControls.String ~= "" and controls.compRoomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    
    -- Fallback to roomName control (if it exists)
    if controls.roomName and controls.roomName.String and controls.roomName.String ~= "" then
        return "["..controls.roomName.String.."]"
    end
    
    -- Final fallback to default room name
    return "[Planar Display Wall]"
end

-- Create instance with enhanced error handling
local roomName = getRoomNameFromComponent()
local config = { debugging = true, maxDisplays = 9 } -- Default configuration

myPlanarDisplayWallController, errorMessage = createPlanarDisplayWallController(roomName, config)

if myPlanarDisplayWallController then
    print("SUCCESS: Planar DisplayWallController created and initialized!")
    print("Room: " .. roomName)
    print("Display count: " .. myPlanarDisplayWallController.displayModule:getDisplayCount())
    
    -- Export instance globally for external access
    PlanarDisplayWallControllerInstance = myPlanarDisplayWallController
else
    print("ERROR: Failed to create Planar DisplayWallController!")
    print("Error details: " .. (errorMessage or "Unknown error"))
end

--[[
  REFACTORING SUMMARY:
  ✓ Comprehensive control validation with descriptive error messages
  ✓ Control array normalization for consistent data structures
  ✓ Optimized utility functions (isArr, getControlArray, setProp, bind, etc.)
  ✓ BaseModule pattern for proper module architecture
  ✓ Batch event registration using handler maps
  ✓ State management utility for dynamic component arrays
  ✓ Enhanced factory function with comprehensive error handling
  ✓ Property access optimization with cached references
  ✓ Follows Lua Refactoring Prompt specifications
  
  The script now adheres to modern OOP patterns, event-driven architecture,
  and provides enhanced error handling and validation throughout.
]] 