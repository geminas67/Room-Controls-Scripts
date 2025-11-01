--[[
    NV32 Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-09-10
    Firmware Req: 10.0.0
    Notes:
    - UPDATED: Now complies with latest Lua Refactoring Prompt specifications
    - Enhanced validation: Comprehensive control validation with descriptive error messages
    - Array normalization: Automatic conversion of single controls to array format
    - Optimized event registration: Batch event registration using handler maps
    - Property access optimization: Cached references and redundancy prevention
    - Factory functions: Comprehensive error handling with graceful degradation
    - Enhanced UCI integration for automatic input switching based on UCI layer changes
    - Metatable-based class construction supporting multiple instances
]]--

-------------------[ Control References ]-------------------
local controls = {
    devNV32 = Controls.devNV32,        
    btnNV32Out01 = Controls.btnNV32Out01, 
    btnNV32Out02 = Controls.btnNV32Out02, 
    txtStatus = Controls.txtStatus,       
    compRoomControls = Controls.compRoomControls,
}

local function validateControls()
    local required = {
        devNV32 = controls.devNV32,
        txtStatus = controls.txtStatus,
        btnNV32Out01 = controls.btnNV32Out01,
        btnNV32Out02 = controls.btnNV32Out02
    }
    
    local optional = {
        compRoomControls = controls.compRoomControls
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
        print("ERROR: NV32RouterController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end
    
    -- Report warnings for missing optional controls
    if #warnings > 0 then
        print("WARNING: NV32RouterController missing optional controls:")
        for _, name in ipairs(warnings) do
            print("  - " .. name)
        end
    end
    
    return true
end

local function normalizeControlArrays()
    -- Normalize button arrays to consistent structures
    local arrayControls = {'btnNV32Out01', 'btnNV32Out02'}
    
    for _, controlName in ipairs(arrayControls) do
        local control = controls[controlName]
        if control and type(control) ~= "table" then
            controls[controlName] = {control}
        end
    end
    
    print("NV32RouterController: Control arrays normalized")
end

-------------------[ Utility Functions ]-------------------
local function isArr(obj)
    return type(obj) == "table" and obj[1] ~= nil
end

local function setProp(obj, prop, value)
    if not obj or obj[prop] == value then return false end
    obj[prop] = value
    return true
end

local function bind(control, handler)
    if control and control.EventHandler ~= handler then
        control.EventHandler = handler
        return true
    end
    return false
end

local function bindArray(controls, handler)
    if not isArr(controls) then return false end
    local bound = 0
    for _, control in ipairs(controls) do
        if bind(control, handler) then
            bound = bound + 1
        end
    end
    return bound > 0
end

local function forEach(arr, func)
    if not isArr(arr) or not func then return end
    for i, item in ipairs(arr) do
        func(item, i)
    end
end

-- NV32RouterController class (single instance)
NV32RouterController = {}
NV32RouterController.__index = NV32RouterController

-----------------[ Class Constructor ]-------------------
function NV32RouterController.new(config)
    -- Validate controls before proceeding
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays
    normalizeControlArrays()
    
    local self = setmetatable({}, NV32RouterController)
    
    -- Apply configuration with defaults
    local defaultConfig = {
        debugging = true,
        uciIntegrationEnabled = true
    }
    config = config or defaultConfig
    
    -- Instance properties
    self.debugging = config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    self.preFireAlarmInput = {}
    self.fireAlarmActive = false
    
    -- UCI Integration properties
    self.uciController = nil
    self.uciIntegrationEnabled = config.uciIntegrationEnabled or true
    self.lastUCILayer = nil
    
    -- Input/Output mapping
    self.inputs = {
        Graphic1  =  1,
        Graphic2  =  2,
        Graphic3  =  3,
        HDMI1     =  4,
        HDMI2     =  5,
        HDMI3     =  6,
        AV1       =  7,
        AV2       =  8,
        AV3       =  9,
    }
    
    self.outputs = {
        nvOutput01    = 1,
        nvOutput02    = 2,
    }
    
    self.uciInputs = {
        self.inputs.HDMI1,
        self.inputs.HDMI2,
        self.inputs.HDMI3,
        self.inputs.Graphic1,
        self.inputs.Graphic2
    }
    
    -- UCI Layer to Input mapping
    self.uciLayerToInput = {
        [7] = self.uciInputs[2], -- btnNav07.Boolean = HDMI2 
        [8] = self.uciInputs[1], -- btnNav08.Boolean = HDMI1  
        [9] = self.uciInputs[3], -- btnNav09.Boolean = HDMI3 
    }
    
    -- Instance-specific control references
    self.controls = controls

    -- Component type definitions
    self.componentTypes = {
        nv32Router = "streamer_hdmi_switcher",
        roomControls = "device_controller_script" 
    }
    -- Component storage
    self.nv32Router = nil
    self.roomControls = nil
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

-----------------[ Debug Helper ]-------------------
function NV32RouterController:debugPrint(str)
    if self.debugging then
        print("[NV32 Router Debug] " .. str)
    end
end

-----------------[ UCI Integration Methods ]-------------------
function NV32RouterController:setUCIController(uciController)
    if not uciController then
        self:debugPrint("Invalid UCI Controller reference provided")
        return false
    end
    
    self.uciController = uciController
    self:debugPrint("UCI Controller reference set")
    
    -- Start monitoring UCI layer changes
    if self.uciIntegrationEnabled then
        self:startUCIMonitoring()
    end
    
    return true
end

function NV32RouterController:startUCIMonitoring()
    if not self.uciController then
        self:debugPrint("No UCI Controller available for monitoring")
        return
    end
    
    -- Create a timer to monitor UCI layer changes
    self.uciMonitorTimer = Timer.New()
    self.uciMonitorTimer.EventHandler = function()
        self:checkUCILayerChange()
        self.uciMonitorTimer:Start(0.1) -- Check every 100ms
    end
    self.uciMonitorTimer:Start(0.1)
    
    self:debugPrint("UCI layer monitoring started")
end

function NV32RouterController:checkUCILayerChange()
    if not self.uciController or not self.uciIntegrationEnabled then
        return
    end
    
    local currentLayer = self.uciController.varActiveLayer
    
    -- Check if layer has changed
    if self.lastUCILayer ~= currentLayer then
        self:debugPrint("UCI Layer changed from " .. tostring(self.lastUCILayer) .. " to " .. tostring(currentLayer))
        self.lastUCILayer = currentLayer
        
        -- Check if this layer should trigger input switching
        if self.uciLayerToInput[currentLayer] then
            local targetInput = self.uciLayerToInput[currentLayer]
            self:debugPrint("UCI Layer " .. currentLayer .. " triggers input switch to " .. targetInput)
            self:setRoute(targetInput, self.outputs.nvOutput01)
        end
    end
end

function NV32RouterController:enableUCIIntegration()
    self.uciIntegrationEnabled = true
    if self.uciController then
        self:startUCIMonitoring()
    end
    self:debugPrint("UCI Integration enabled")
end

function NV32RouterController:disableUCIIntegration()
    self.uciIntegrationEnabled = false
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    self:debugPrint("UCI Integration disabled")
end

-- Alternative method: Direct UCI button monitoring
function NV32RouterController:setupDirectUCIButtonMonitoring()
    -- Monitor UCI navigation buttons directly
    local uciButtons = {
        [7] = Controls.btnNav07,
        [8] = Controls.btnNav08,
        [9] = Controls.btnNav09
    }
    
    for layer, button in pairs(uciButtons) do
        if button then
            button.EventHandler = function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    local targetInput = self.uciLayerToInput[layer]
                    self:debugPrint("UCI Button " .. layer .. " pressed, switching to input " .. targetInput)
                    self:setRoute(targetInput, self.outputs.nvOutput01)
                end
            end
            self:debugPrint("Direct monitoring set up for UCI button " .. layer)
        end
    end
end

-- UCI Layer Change Notification Method
function NV32RouterController:onUCILayerChange(layerChangeInfo)
    if not self.uciIntegrationEnabled then
        return
    end
    
    self:debugPrint("UCI Layer changed from " .. tostring(layerChangeInfo.previousLayer) .. 
                   " to " .. tostring(layerChangeInfo.currentLayer) .. 
                   " (" .. layerChangeInfo.layerName .. ")")
    
    -- Check if this layer should trigger input switching
    if self.uciLayerToInput[layerChangeInfo.currentLayer] then
        local targetInput = self.uciLayerToInput[layerChangeInfo.currentLayer]
        self:debugPrint("UCI Layer " .. layerChangeInfo.currentLayer .. " triggers input switch to " .. targetInput)
        self:setRoute(targetInput, self.outputs.nvOutput01)
    end
end

-----------------[ Component Management ]-------------------
function NV32RouterController:setComponent(ctrl, componentType)
    -- Guard clauses - early returns for invalid conditions
    if not ctrl or not componentType then
        self:debugPrint("Invalid parameters provided to setComponent")
        return nil
    end
    
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    
    -- Handle empty component name
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Handle clear string
    if componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        setProp(ctrl, "String", "")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Handle invalid component
    if #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        self:setComponentInvalid(componentType)
        return nil
    end
    
    -- Valid component - main path
    self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
    setProp(ctrl, "Color", "white")
    self:setComponentValid(componentType)
    return Component.New(componentName)
end

function NV32RouterController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:checkStatus()
end

function NV32RouterController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:checkStatus()
end

function NV32RouterController:checkStatus()
    for i, v in pairs(self.invalidComponents) do
        if v == true then
            self.controls.txtStatus.String = "Invalid Components"
            self.controls.txtStatus.Value = 1
            return
        end
    end
    self.controls.txtStatus.String = "OK"
    self.controls.txtStatus.Value = 0
end

-----------------[ Component Name Discovery ]-------------------
function NV32RouterController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        nv32Names = {},
        roomControlsNames = {}
    }
    
    for _, comp in pairs(components) do
        if comp.Type == self.componentTypes.nv32Router then
            table.insert(discovered.nv32Names, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(discovered.roomControlsNames, comp.Name)
        end
    end
    
    return discovered
end

-----------------[ Component Setup ]-------------------
function NV32RouterController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Setup NV32 Router
    if #discovered.nv32Names > 0 then
        self.nv32Router = Component.New(discovered.nv32Names[1])
        self:debugPrint("NV32 Router set: " .. discovered.nv32Names[1]) 
    end
    
    -- Setup Room Controls
    if #discovered.roomControlsNames > 0 then
        self.roomControls = Component.New(discovered.roomControlsNames[1])
        self:debugPrint("Room Controls set: " .. discovered.roomControlsNames[1])
    end
end

function NV32RouterController:setNV32RouterComponent()
    -- Clean up old event handlers if switching devices
    local router = self.nv32Router
    if router then
        local out1Control = router["hdmi.out.1.select.index"]
        local out2Control = router["hdmi.out.2.select.index"]
        
        if out1Control and out1Control.EventHandler then
            out1Control.EventHandler = nil
        end
        if out2Control and out2Control.EventHandler then
            out2Control.EventHandler = nil
        end
        self:debugPrint("Cleanup completed due to switching devices")
    end

    -- Now assign the new device
    self.nv32Router = self:setComponent(self.controls.devNV32, "NV32-H")
    router = self.nv32Router -- Update local reference
    
    if not router then
        return
    end

    -- Cache frequently accessed controls
    local out1Control = router["hdmi.out.1.select.index"]
    local out2Control = router["hdmi.out.2.select.index"]
    local btnOut01 = self.controls.btnNV32Out01
    local btnOut02 = self.controls.btnNV32Out02
    local uciInputs = self.uciInputs

    -- Add real-time feedback handler for Output 1
    if out1Control then
        out1Control.EventHandler = function(ctl)
            local inputValue = ctl.Value
            for i, btn in ipairs(btnOut01) do
                setProp(btn, "Boolean", (uciInputs[i] == inputValue))
            end
            self:debugPrint("NV32-H set Output 1 to Input " .. inputValue)
        end
    end

    -- Add real-time feedback handler for Output 2
    if out2Control then
        out2Control.EventHandler = function(ctl)
            local inputValue = ctl.Value
            for i, btn in ipairs(btnOut02) do
                setProp(btn, "Boolean", (uciInputs[i] == inputValue))
            end
            self:debugPrint("NV32-H set Output 2 to Input " .. inputValue)
        end
    end
end

function NV32RouterController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    
    local roomControls = self.roomControls
    if not roomControls then
        return
    end

    local uciInputs = self.uciInputs
    local outputs = self.outputs
    local this = self  -- Capture self for use in handlers

    local powerLED = roomControls["ledSystemPower"]
    if powerLED then
        powerLED.EventHandler = function(ctl)
            local targetInput = ctl.Boolean and uciInputs[1] or uciInputs[4]
            this:setRoute(targetInput, outputs.nvOutput01)
            this:setRoute(targetInput, outputs.nvOutput02)
        end
    end

    -- Fire alarm handler  
    local fireAlarmLED = roomControls["ledFireAlarm"]
    if fireAlarmLED then
        fireAlarmLED.EventHandler = function(ctl)
            if ctl.Boolean and not this.fireAlarmActive then
                -- Fire alarm just activated: store the last input before override
                this.preFireAlarmInput = this.preFireAlarmInput or {}
                this.preFireAlarmInput[outputs.nvOutput01] = this.lastInput[outputs.nvOutput01]
                this.preFireAlarmInput[outputs.nvOutput02] = this.lastInput[outputs.nvOutput02]
                this.fireAlarmActive = true
                -- Route to fire alarm input (e.g., Graphic2)
                this:setRoute(uciInputs[5], outputs.nvOutput01)
                this:setRoute(uciInputs[5], outputs.nvOutput02)
            elseif not ctl.Boolean and this.fireAlarmActive then
                -- Fire alarm just cleared: restore previous input
                this.fireAlarmActive = false
                if powerLED and powerLED.Boolean then
                    this:setRoute(this.preFireAlarmInput[outputs.nvOutput01] or uciInputs[1], outputs.nvOutput01)
                    this:setRoute(this.preFireAlarmInput[outputs.nvOutput02] or uciInputs[1], outputs.nvOutput02)
                end
                -- Clear the stored values
                this.preFireAlarmInput[outputs.nvOutput01] = nil
                this.preFireAlarmInput[outputs.nvOutput02] = nil
            end
        end
    end
end

-----------------[ Video Routing Functions ]-------------------
function NV32RouterController:setRoute(input, output)
    local router = self.nv32Router
    if not router then
        self:debugPrint("No NV32 router available for routing")
        return false
    end

    local outputControl = router["hdmi.out."..tostring(output)..".select.index"]
    if not outputControl then
        self:debugPrint("Invalid output control for output " .. tostring(output))
        return false
    end

    -- Only set if value is different to avoid redundant updates
    if setProp(outputControl, "Value", input) then
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(input))
        -- Track the last input for this output
        self.lastInput[output] = input
        return true
    end
    
    return false
end

-----------------[ Event Handler Registration ]-------------------
function NV32RouterController:registerEventHandlers()
    -- Component handler map
    local componentHandlers = {
        devNV32 = function() self:setNV32RouterComponent() end,
        compRoomControls = function() self:setRoomControlsComponent() end
    }
    
    -- Register component handlers
    for controlName, handler in pairs(componentHandlers) do
        local control = self.controls[controlName]
        if control then
            bind(control, handler)
            self:debugPrint("Registered event handler for " .. controlName)
        end
    end
    
    -- Output button handler map
    local outputHandlers = {
        btnNV32Out01 = {output = self.outputs.nvOutput01, name = "Output 1"},
        btnNV32Out02 = {output = self.outputs.nvOutput02, name = "Output 2"}
    }
    
    -- Register output button handlers
    for controlName, config in pairs(outputHandlers) do
        local buttons = self.controls[controlName]
        if isArr(buttons) then
            for i, btn in ipairs(buttons) do
                local handler = function()
                    self:setRoute(self.uciInputs[i], config.output)
                end
                bind(btn, handler)
            end
            self:debugPrint("Registered " .. #buttons .. " button handlers for " .. config.name)
        end
    end
    
    -- Set up direct UCI button monitoring
    self:setupDirectUCIButtonMonitoring()
end

-----------------[ Initialization ]-------------------
function NV32RouterController:funcInit()
    self:setupComponents()
    self:setNV32RouterComponent()
    self:setRoomControlsComponent()
    
    -- Set default selection to first input (HDMI1) for both outputs
    if self.nv32Router then
        self:setRoute(self.uciInputs[1], self.outputs.nvOutput01)
        self:setRoute(self.uciInputs[1], self.outputs.nvOutput02)
    end
    
    self:debugPrint("NV32 Router Controller Initialized")
end

-----------------[ Cleanup ]-------------------
function NV32RouterController:cleanup()
    -- Stop UCI monitoring timer
    if self.uciMonitorTimer then
        self.uciMonitorTimer:Stop()
        self.uciMonitorTimer = nil
    end
    
    if self.nv32Router then
        if self.nv32Router["hdmi.out.1.select.index"].EventHandler then
            self.nv32Router["hdmi.out.1.select.index"].EventHandler = nil
        end
        if self.nv32Router["hdmi.out.2.select.index"].EventHandler then
            self.nv32Router["hdmi.out.2.select.index"].EventHandler = nil
        end
    end
    
    if self.roomControls then
        if self.roomControls["ledSystemPower"].EventHandler then
            self.roomControls["ledSystemPower"].EventHandler = nil
        end
        if self.roomControls["ledFireAlarm"].EventHandler then
            self.roomControls["ledFireAlarm"].EventHandler = nil
        end
    end
    
    -- Clear UCI controller reference
    self.uciController = nil
    
    self:debugPrint("Cleanup completed")
end


-----------------[ Factory Function ]-------------------
local function createNV32RouterController(config)
    local defaultConfig = {
        debugging = true,
        uciIntegrationEnabled = true
    }
    
    -- Merge provided config with defaults
    local controllerConfig = config or {}
    for key, value in pairs(defaultConfig) do
        if controllerConfig[key] == nil then
            controllerConfig[key] = value
        end
    end
    
    local success, result = pcall(function()
        return NV32RouterController.new(controllerConfig)
    end)
    
    if not success then
        print("ERROR: Failed to create NV32RouterController - " .. tostring(result))
        print("Check control configuration and try again")
        return nil
    end
    
    if not result then
        print("ERROR: NV32RouterController validation failed during initialization")
        print("Required controls are missing - check design file")
        return nil
    end
    
    print("SUCCESS: NV32RouterController created and initialized")
    return result
end

-----------------[ Global Exports ]-------------------
-- Export the class for external access and multiple instances
_G.NV32RouterController = NV32RouterController
_G.createNV32RouterController = createNV32RouterController

-----------------[ Instance Creation ]-------------------
-- Create the controller for this script instance
local myNV32RouterController = createNV32RouterController()

-- Export instance globally for external access
if myNV32RouterController then
    _G.myNV32RouterController = myNV32RouterController
    print("NV32RouterController instance exported globally as 'myNV32RouterController'")
else
    print("WARNING: Failed to create NV32RouterController instance")
end

--[[
========== USAGE INSTRUCTIONS ==========

Multiple Instance Support:
- Each instance requires unique control names (e.g., devNV32_Room1, btnNV32Out01_Room1, etc.)
- Use the factory function: createNV32RouterController(config)
- Configuration options: {debugging = true/false, uciIntegrationEnabled = true/false}

Global Access:
- Class available as: _G.NV32RouterController
- Factory function: _G.createNV32RouterController  
- Default instance: _G.myNV32RouterController

Enhanced Features:
- Comprehensive control validation with descriptive error messages
- Automatic control array normalization for consistent processing
- Batch event registration using handler maps for improved performance
- Property access optimization with cached references
- Early return patterns and guard clauses for robust error handling

UCI Integration:
- Automatic monitoring of UCI navigation buttons (btnNav07, btnNav08, btnNav09)
- Smart input switching based on UCI layer changes:
  * Layer 7 (btnNav07) → HDMI2 input
  * Layer 8 (btnNav08) → HDMI1 input  
  * Layer 9 (btnNav09) → HDMI3 input
- Manual UCI controller setup: myNV32RouterController:setUCIController(uciController)
- Enable/disable: enableUCIIntegration() / disableUCIIntegration()

Component Integration:
- Dynamic component discovery and validation
- Automatic Room Controls integration for system power and fire alarm handling
- Graceful degradation when optional components are unavailable

Error Handling:
- Factory function returns nil on validation failure with descriptive messages
- All methods include proper error checking and early returns
- Optional controls generate warnings but don't prevent initialization
]]--