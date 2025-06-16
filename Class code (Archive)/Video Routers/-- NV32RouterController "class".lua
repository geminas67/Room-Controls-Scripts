--[[ 
  NV32 Router Controller - Class-based Implementation
  Author: Hope Roth, Q-SYS
  February, 2025
  Firmware Req: 9.12
  Version: 2.0
  
  Class-based implementation maintaining simplicity of functional approach
]]--

-- NV32RouterController class
NV32RouterController = {}
NV32RouterController.__index = NV32RouterController

--------** Class Constructor **--------
function NV32RouterController.new(config)
    local self = setmetatable({}, NV32RouterController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    
    -- Input/Output mapping
    self.inputs = {
        Graphic1 =  1,
        Graphic2 =  2,
        Graphic3 =  3,
        HDMI1 =     4,
        HDMI2 =     5,
        HDMI3 =     6,
        AV1 =       7,
        AV2 =       8,
        AV3 =       9,
    }
    
    self.outputs = {
        OUTPUT1 =   1,
        OUTPUT2 =   2,
    }
    
    -- UCI Input mapping (matching original implementation)
    self.uciInputs = {
        self.inputs.HDMI1,
        self.inputs.HDMI2,
        self.inputs.HDMI3,
        self.inputs.Graphic3
    }
    
    -- Component storage
    self.nv32Router = nil
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** Debug Helper **--------
function NV32RouterController:debugPrint(str)
    if self.debugging then
        print("[NV32 Router Debug] " .. str)
    end
end

--------** Component Management **--------
function NV32RouterController:setComponent(ctrl, componentType)
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    else
        self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
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
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------** Component Setup **--------
function NV32RouterController:setNV32RouterComponent()
    self.nv32Router = self:setComponent(Controls.devNV32, "NV32-H")
    if self.nv32Router ~= nil then
        -- Add real-time feedback handler for Output 1
        self.nv32Router["hdmi.out.1.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(Controls.btnNV32Out01) do
                btn.Boolean = (self.uciInputs[i] == ctl.Value)
            end
            self:debugPrint("NV32-H set Output 1 to Input " .. ctl.Value)
        end
        
        -- Add real-time feedback handler for Output 2
        self.nv32Router["hdmi.out.2.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(Controls.btnNV32Out02) do
                btn.Boolean = (self.uciInputs[i] == ctl.Value)
            end
            self:debugPrint("NV32-H set Output 2 to Input " .. ctl.Value)
        end
    end
end

--------** Component Name Discovery **--------
function NV32RouterController:getComponentNames()
    local namesTable = {
        nv32Names = {}
    }

    for i, comp in pairs(Component.GetComponents()) do
        if comp.Type == "streamer_hdmi_switcher" then
            table.insert(namesTable.nv32Names, comp.Name)
        end
    end

    for i, names in pairs(namesTable) do
        table.sort(names)
        table.insert(names, self.clearString)
    end

    Controls.devNV32.Choices = namesTable.nv32Names
end

--------** Video Routing Functions **--------
function NV32RouterController:setRoute(input, output)
    if self.nv32Router then
        self.nv32Router["hdmi.out."..tostring(output)..".select.index"].Value = input
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(input))
    end
end

--------** Event Handler Registration **--------
function NV32RouterController:registerEventHandlers()
    -- NV32 Router component handler
    Controls.devNV32.EventHandler = function()
        self:setNV32RouterComponent()
    end
    
    -- Output 1 button handlers
    for i, btn in ipairs(Controls.btnNV32Out01) do
        btn.EventHandler = function()
            self:setRoute(self.uciInputs[i], self.outputs.OUTPUT1)
        end
    end
    
    -- Output 2 button handlers
    for i, btn in ipairs(Controls.btnNV32Out02) do
        btn.EventHandler = function()
            self:setRoute(self.uciInputs[i], self.outputs.OUTPUT2)
        end
    end
end

--------** Initialization **--------
function NV32RouterController:funcInit()
    self:getComponentNames()
    self:setNV32RouterComponent()
    
    -- Set default selection to first input (HDMI1) for both outputs
    if self.nv32Router then
        self:setRoute(self.uciInputs[1], self.outputs.OUTPUT1)
        self:setRoute(self.uciInputs[1], self.outputs.OUTPUT2)
    end
    
    self:debugPrint("NV32 Router Controller Initialized")
end

--------** Cleanup **--------
function NV32RouterController:cleanup()
    if self.nv32Router then
        if self.nv32Router["hdmi.out.1.select.index"].EventHandler then
            self.nv32Router["hdmi.out.1.select.index"].EventHandler = nil
        end
        if self.nv32Router["hdmi.out.2.select.index"].EventHandler then
            self.nv32Router["hdmi.out.2.select.index"].EventHandler = nil
        end
    end
    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createNV32RouterController(config)
    local defaultConfig = {
        debugging = true
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return NV32RouterController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created NV32 Router Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main NV32 router controller instance
myNV32RouterController = createNV32RouterController()

--------** Usage Examples **--------
--[[
-- Example usage of the NV32 router controller:

-- Set a route manually
myNV32RouterController:setRoute(1, 1)  -- Set Output 1 to Input 1
myNV32RouterController:setRoute(2, 2)  -- Set Output 2 to Input 2

-- Get current routes
local currentInput1 = myNV32RouterController.nv32Router["hdmi.out.1.select.index"].Value
local currentInput2 = myNV32RouterController.nv32Router["hdmi.out.2.select.index"].Value

-- Update source buttons
for i, btn in ipairs(Controls.btnNV32Out01) do
    btn.Boolean = (i == currentInput1)
end
for i, btn in ipairs(Controls.btnNV32Out02) do
    btn.Boolean = (i == currentInput2)
end
]]--