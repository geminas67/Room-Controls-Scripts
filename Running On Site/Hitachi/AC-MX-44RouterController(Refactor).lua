--[[
    AC-MX-44 Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-11-18
    Firmware Req: 10.0.0
    Notes:
    - UPDATED: Now complies with latest Lua Refactoring Prompt specifications
    - MX44-specific routing: Uses boolean controls per input/output combination
    - Control naming: "Video Routing Output X Input Y" (Boolean)
    - Direct feedback from MX44 component boolean controls
    - Enhanced validation: Comprehensive control validation with descriptive error messages
    - Array normalization: Automatic conversion of single controls to array format
    - Optimized event registration: Batch event registration using handler maps
    - Property access optimization: Cached references and redundancy prevention
    - Factory functions: Comprehensive error handling with graceful degradation
    - Metatable-based class construction supporting multiple instances
]]--

-------------------[ Control References ]-------------------
local controls = {
    compMX44 = Controls.compMX44,        
    btnOutput01 = Controls.btnOutput01, 
    btnOutput02 = Controls.btnOutput02, 
    txtStatus = Controls.txtStatus,
}

local function validateControls()
    local required = {
        compMX44 = controls.compMX44,
        txtStatus = controls.txtStatus,
        btnOutput01 = controls.btnOutput01,
        btnOutput02 = controls.btnOutput02
    }
    
    local missing = {}
    
    -- Check required controls
    for name, control in pairs(required) do
        if not control then
            table.insert(missing, name)
        end
    end
    
    -- Report missing required controls
    if #missing > 0 then
        print("ERROR: MX44RouterController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end
    
    return true
end

local function normalizeControlArrays()
    -- Normalize button arrays to consistent structures
    local arrayControls = {'btnOutput01', 'btnOutput02'}
    
    for _, controlName in ipairs(arrayControls) do
        local control = controls[controlName]
        if control and type(control) ~= "table" then
            controls[controlName] = {control}
        end
    end
    
    print("MX44RouterController: Control arrays normalized")
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

-- MX44RouterController class (single instance)
MX44RouterController = {}
MX44RouterController.__index = MX44RouterController

-----------------[ Class Constructor ]-------------------
function MX44RouterController.new(config)
    -- Validate controls before proceeding
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays
    normalizeControlArrays()
    
    local self = setmetatable({}, MX44RouterController)
    
    -- Apply configuration with defaults
    local defaultConfig = {
        debugging = true
    }
    config = config or defaultConfig
    
    -- Instance properties
    self.debugging = config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    
    -- Input/Output mapping
    self.outputs = {
        OUTPUT1    = 1,
        OUTPUT2    = 2,
    }
    
    -- Instance-specific control references
    self.controls = controls

    -- Component type definitions
    self.componentTypes = {
        mx44Router = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f"  -- Updated for MX44
    }
    -- Component storage
    self.mx44Router = nil
    self.compDivisibleSpaceControls = nil
    self.roomState = false  -- Track combined state (true = combined, false = separated)
    
    -- MX44 control name pattern: "Video Routing Output X Input Y"
    self.numOutputs = 4  -- MX44 has 4 outputs
    self.numInputs = 4   -- MX44 has 4 inputs per output
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

-----------------[ Debug Helper ]-------------------
function MX44RouterController:debugPrint(str)
    if self.debugging then
        print("[MX44 Router Debug] " .. str)
    end
end

-----------------[ MX44 Control Name Helper ]-------------------
function MX44RouterController:getMX44ControlName(output, input)
    -- MX44 uses simple naming: "Input 1" through "Input 8"
    -- Output 1 uses Inputs 1-4, Output 2 uses Inputs 5-8
    local physicalInput = ((output - 1) * 4) + input
    return string.format("Input %d", physicalInput)
end

-----------------[ Component Management ]-------------------
function MX44RouterController:setComponent(ctrl, componentType)
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

function MX44RouterController:setComponentInvalid(componentType)
    self.invalidComponents[componentType] = true
    self:checkStatus()
end

function MX44RouterController:setComponentValid(componentType)
    self.invalidComponents[componentType] = false
    self:checkStatus()
end

function MX44RouterController:checkStatus()
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
function MX44RouterController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        mx44Names = {}
    }
    
    for _, comp in pairs(components) do
        if comp.Type == self.componentTypes.mx44Router then
            table.insert(discovered.mx44Names, comp.Name)
        end
    end
    
    return discovered
end

-----------------[ Component Setup ]-------------------
function MX44RouterController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Auto-populate compMX44 control if it's empty and a component was discovered
    if #discovered.mx44Names > 0 then
        if self.controls.compMX44 and (self.controls.compMX44.String == "" or self.controls.compMX44.String == self.clearString) then
            self.controls.compMX44.String = discovered.mx44Names[1]
            self:debugPrint("Auto-populated compMX44 with: " .. discovered.mx44Names[1])
        end
    end
end

function MX44RouterController:setMX44RouterComponent()
    -- Clean up old event handlers if switching devices
    local router = self.mx44Router
    if router then
        -- Clean up all boolean control handlers for all outputs
        for output = 1, self.numOutputs do
            for input = 1, self.numInputs do
                local controlName = self:getMX44ControlName(output, input)
                local control = router[controlName]
                if control and control.EventHandler then
                    control.EventHandler = nil
                end
            end
        end
        self:debugPrint("Cleanup completed due to switching devices")
    end

    -- Now assign the new device
    self.mx44Router = self:setComponent(self.controls.compMX44, "MX44")
    router = self.mx44Router -- Update local reference
    
    if not router then
        return
    end

    -- Cache frequently accessed controls
    local btnOut01 = self.controls.btnOutput01
    local btnOut02 = self.controls.btnOutput02
    local this = self  -- Capture self for use in handlers

    -- Set up feedback handlers for Output 1 (monitor all its input booleans)
    for inputIdx = 1, self.numInputs do
        local controlName = self:getMX44ControlName(1, inputIdx)
        local control = router[controlName]
        
        if control then
            control.EventHandler = function(ctl)
                if ctl.Boolean then
                    -- This input was selected for output 1
                    -- Update button feedback: button index maps directly to input
                    for i, btn in ipairs(btnOut01) do
                        setProp(btn, "Boolean", (i == inputIdx))
                    end
                    this:debugPrint("MX44 Output 1 switched to Input " .. inputIdx)
                    
                    -- Sync Output02 to follow Output01 when room is combined (roomState == true)
                    if this.roomState then
                        this:syncOutput02ToOutput01(inputIdx)
                    end
                end
            end
        end
    end

    -- Set up feedback handlers for Output 2 (monitor all its input booleans)
    for inputIdx = 1, self.numInputs do
        local controlName = self:getMX44ControlName(2, inputIdx)
        local control = router[controlName]
        
        if control then
            control.EventHandler = function(ctl)
                if ctl.Boolean then
                    -- This input was selected for output 2
                    -- Update button feedback: button index maps directly to input
                    for i, btn in ipairs(btnOut02) do
                        setProp(btn, "Boolean", (i == inputIdx))
                    end
                    this:debugPrint("MX44 Output 2 switched to Input " .. inputIdx)
                end
            end
        end
    end
end

-----------------[ DivisibleSpaceControls Component Setup ]-------------------
function MX44RouterController:setDivisibleSpaceControlsComponent()
    -- Direct component reference (no selector control)
    local success, component = pcall(function()
        return Component.New("compDivisibleSpaceControls")
    end)
    
    if success and component then
        self.compDivisibleSpaceControls = component
        self:debugPrint("DivisibleSpaceControls component referenced successfully")
        
        -- Set up EventHandler for btnRoomState 1
        local btnRoomState = component["btnRoomState 1"]
        if btnRoomState then
            local this = self  -- Capture self for use in handler
            bind(btnRoomState, function(ctl)
                -- btnRoomState.Boolean == false means Combined, true means Separated
                -- Store inverse so roomState == true means Combined
                this.roomState = not ctl.Boolean
                this:debugPrint("Room state changed: " .. (this.roomState and "Combined" or "Separated"))
                
                -- If room becomes combined (btnRoomState.Boolean == false), sync Output02 to follow Output01's current route
                if not ctl.Boolean then
                    -- Find current Output01 route by checking MX44 router controls
                    if this.mx44Router then
                        for inputIdx = 1, this.numInputs do
                            local controlName = this:getMX44ControlName(1, inputIdx)
                            local control = this.mx44Router[controlName]
                            if control and control.Boolean then
                                -- Output01 is currently routed to this input, sync Output02
                                this:syncOutput02ToOutput01(inputIdx)
                                this:debugPrint("Synced Output02 to follow Output01 (Input " .. inputIdx .. ")")
                                break
                            end
                        end
                    end
                end
            end)
            
            -- Read initial room state (inverse: false = Combined, true = Separated)
            self.roomState = not btnRoomState.Boolean
            self:debugPrint("Initial room state: " .. (self.roomState and "Combined" or "Separated"))
        else
            self:debugPrint("Warning: btnRoomState 1 control not found in compDivisibleSpaceControls")
        end
    else
        self:debugPrint("DivisibleSpaceControls component not found (feature disabled)")
        self.compDivisibleSpaceControls = nil
        self.roomState = false
    end
end

-----------------[ Routing Sync Helper ]-------------------
function MX44RouterController:syncOutput02ToOutput01(output01Input)
    -- Sync Output02 to follow Output01 when room is combined
    -- Mapping: Output01 Input 1-4 → Output02 Input 5-8
    if not self.roomState then
        return false  -- Only sync when room is combined
    end
    
    if output01Input < 1 or output01Input > self.numInputs then
        self:debugPrint("Invalid Output01 input for sync: " .. tostring(output01Input))
        return false
    end
    
    -- Use setRoute with Output02's logical input index (1-4) mapped to physical input (5-8)
    -- setRoute expects logical input (1-4 for output 2), so we use output01Input directly
    -- The getMX44ControlName method will map it correctly: output 2, input 1 → Input 5
    return self:setRoute(output01Input, self.outputs.OUTPUT2)
end

-----------------[ Video Routing Functions ]-------------------
function MX44RouterController:setRoute(input, output)
    local router = self.mx44Router
    if not router then
        self:debugPrint("No MX44 router available for routing")
        return false
    end

    -- Validate input/output ranges
    if input < 1 or input > self.numInputs or output < 1 or output > self.numOutputs then
        self:debugPrint("Invalid input/output: Input " .. tostring(input) .. ", Output " .. tostring(output))
        return false
    end

    -- Get the control name for the desired route
    local targetControlName = self:getMX44ControlName(output, input)
    local targetControl = router[targetControlName]
    
    if not targetControl then
        self:debugPrint("Control not found: " .. targetControlName)
        return false
    end
    
    -- Check if already routed to avoid redundant updates
    if targetControl.Boolean == true then
        self:debugPrint("Output " .. tostring(output) .. " already routed to Input " .. tostring(input))
        return false
    end
    
    -- Trigger the input control (acts like clicking the button in Q-Sys)
    -- The component handles mutual exclusivity automatically
    targetControl:Trigger()
    
    self:debugPrint("Set Output " .. tostring(output) .. " to Input " .. tostring(input))
    -- Track the last input for this output
    self.lastInput[output] = input
    return true
end

-----------------[ Event Handler Registration ]-------------------
function MX44RouterController:registerEventHandlers()
    -- Component handler map
    local componentHandlers = {
        compMX44 = function() self:setMX44RouterComponent() end
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
        btnOutput01 = {output = self.outputs.OUTPUT1, name = "Output 1"},
        btnOutput02 = {output = self.outputs.OUTPUT2, name = "Output 2"}
    }
    
    -- Register output button handlers
    for controlName, config in pairs(outputHandlers) do
        local buttons = self.controls[controlName]
        if isArr(buttons) then
            for i, btn in ipairs(buttons) do
                local handler = function()
                    -- Button index maps directly to input: btn[1]=input1, btn[2]=input2, etc.
                    self:setRoute(i, config.output)
                end
                bind(btn, handler)
            end
            self:debugPrint("Registered " .. #buttons .. " button handlers for " .. config.name)
        end
    end
end

-----------------[ Initialization ]-------------------
function MX44RouterController:funcInit()
    self:setupComponents()
    self:setMX44RouterComponent()
    self:setDivisibleSpaceControlsComponent()
    
    -- Set default selection to first input for both outputs
    if self.mx44Router then
        self:setRoute(1, self.outputs.OUTPUT1)
        -- If room is combined (roomState == true), sync Output02 to follow Output01; otherwise set independently
        if self.roomState then
            self:syncOutput02ToOutput01(1)
        else
            self:setRoute(1, self.outputs.OUTPUT2)
        end
    end
    
    self:debugPrint("MX44 Router Controller Initialized")
end

-----------------[ Cleanup ]-------------------
function MX44RouterController:cleanup()
    -- Clean up all MX44 router event handlers
    if self.mx44Router then
        for output = 1, self.numOutputs do
            for input = 1, self.numInputs do
                local controlName = self:getMX44ControlName(output, input)
                local control = self.mx44Router[controlName]
                if control and control.EventHandler then
                    control.EventHandler = nil
                end
            end
        end
    end
    
    self:debugPrint("Cleanup completed")
end


-----------------[ Factory Function ]-------------------
local function createMX44RouterController(config)
    local defaultConfig = {
        debugging = true
    }
    
    -- Merge provided config with defaults
    local controllerConfig = config or {}
    for key, value in pairs(defaultConfig) do
        if controllerConfig[key] == nil then
            controllerConfig[key] = value
        end
    end
    
    local success, result = pcall(function()
        return MX44RouterController.new(controllerConfig)
    end)
    
    if not success then
        print("ERROR: Failed to create MX44RouterController - " .. tostring(result))
        print("Check control configuration and try again")
        return nil
    end
    
    if not result then
        print("ERROR: MX44RouterController validation failed during initialization")
        print("Required controls are missing - check design file")
        return nil
    end
    
    print("SUCCESS: MX44RouterController created and initialized")
    return result
end

-----------------[ Global Exports ]-------------------
-- Export the class for external access and multiple instances
_G.MX44RouterController = MX44RouterController
_G.createMX44RouterController = createMX44RouterController

-----------------[ Instance Creation ]-------------------
-- Create the controller for this script instance
local myMX44RouterController = createMX44RouterController()

-- Export instance globally for external access
if myMX44RouterController then
    _G.myMX44RouterController = myMX44RouterController
    print("MX44RouterController instance exported globally as 'myMX44RouterController'")
else
    print("WARNING: Failed to create MX44RouterController instance")
end

--[[
========== USAGE INSTRUCTIONS ==========

Multiple Instance Support:
- Each instance requires unique control names (e.g., compMX44_Room1, btnOutput01_Room1, etc.)
- Use the factory function: createMX44RouterController(config)
- Configuration options: {debugging = true/false}

Global Access:
- Class available as: _G.MX44RouterController
- Factory function: _G.createMX44RouterController  
- Default instance: _G.myMX44RouterController

Enhanced Features:
- Comprehensive control validation with descriptive error messages
- Automatic control array normalization for consistent processing
- Batch event registration using handler maps for improved performance
- Property access optimization with cached references
- Early return patterns and guard clauses for robust error handling
- Direct boolean control monitoring for real-time feedback from MX44 component

Component Integration:
- Dynamic component discovery and validation
- MX44 router component with boolean control support

Error Handling:
- Factory function returns nil on validation failure with descriptive messages
- All methods include proper error checking and early returns
- Optional controls generate warnings but don't prevent initialization

Button to Input Mapping:
- btnOutput01[1] → MX44 Input 1 (Output 1, Input 1)
- btnOutput01[2] → MX44 Input 2 (Output 1, Input 2)
- btnOutput01[3] → MX44 Input 3 (Output 1, Input 3)
- btnOutput01[4] → MX44 Input 4 (Output 1, Input 4)
- btnOutput02[1] → MX44 Input 5 (Output 2, Input 1)
- btnOutput02[2] → MX44 Input 6 (Output 2, Input 2)
- btnOutput02[3] → MX44 Input 7 (Output 2, Input 3)
- btnOutput02[4] → MX44 Input 8 (Output 2, Input 4)
]]--