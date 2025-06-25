--[[
  NV32 Router Controller - Clean Version (Direct UCI Control)
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.2 (Clean - Direct UCI Control)

  This version provides basic NV32 router functionality.
  UCI control is handled directly by the UCI script via UCI variables.
]]--

-- Define control references
local controls = {
    devNV32 = Controls.devNV32,        
    btnNV32Out01 = Controls.btnNV32Out01, 
    btnNV32Out02 = Controls.btnNV32Out02, 
    txtStatus = Controls.txtStatus,       
    compRoomControls = Controls.compRoomControls, -- Room Controls component
}

-- NV32RouterController class (single instance)
NV32RouterController = {}
NV32RouterController.__index = NV32RouterController

--------** Class Constructor **--------
function NV32RouterController.new(config)
    local self = setmetatable({}, NV32RouterController)
    
    -- Apply configuration
    local config = config or {}
    
    -- Instance properties
    self.debugging = config.debugging or true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    self.lastInput = {} -- Store the last input for each output
    self.preFireAlarmInput = {}
    self.fireAlarmActive = false
    
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
    
    -- Instance-specific control references
    self.controls = controls
    
    -- Component storage
    self.nv32Router = nil
    self.roomControls = nil
    
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
            self.controls.txtStatus.String = "Invalid Components"
            self.controls.txtStatus.Value = 1
            return
        end
    end
    self.controls.txtStatus.String = "OK"
    self.controls.txtStatus.Value = 0
end

--------** Component Name Discovery **--------
function NV32RouterController:populateNV32Choices()
    local names = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "streamer_hdmi_switcher" then
            table.insert(names, comp.Name)
        end
    end
    table.sort(names)
    table.insert(names, self.clearString)
    self.controls.devNV32.Choices = names
end

function NV32RouterController:populateRoomControlsChoices()
    local names = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls") then
            table.insert(names, comp.Name)
        end
    end
    table.sort(names)
    table.insert(names, self.clearString)
    self.controls.compRoomControls.Choices = names
end

--------** Component Setup **--------
function NV32RouterController:setNV32RouterComponent()
    -- Clean up old event handlers if switching devices
    if self.nv32Router then
        if self.nv32Router["hdmi.out.1.select.index"].EventHandler then
            self.nv32Router["hdmi.out.1.select.index"].EventHandler = nil
        end
        if self.nv32Router["hdmi.out.2.select.index"].EventHandler then
            self.nv32Router["hdmi.out.2.select.index"].EventHandler = nil
        end
        self:debugPrint("Cleanup completed to due to switching devices")
    end

    -- Now assign the new device
    self.nv32Router = self:setComponent(self.controls.devNV32, "NV32-H")
    if self.nv32Router ~= nil then
        -- Add real-time feedback handler for Output 1
        self.nv32Router["hdmi.out.1.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(self.controls.btnNV32Out01) do
                btn.Boolean = (self.inputs[i] == ctl.Value)
            end
            self:debugPrint("NV32-H set Output 1 to Input " .. ctl.Value)
        end

        -- Add real-time feedback handler for Output 2
        self.nv32Router["hdmi.out.2.select.index"].EventHandler = function(ctl)
            for i, btn in ipairs(self.controls.btnNV32Out02) do
                btn.Boolean = (self.inputs[i] == ctl.Value)
            end
            self:debugPrint("NV32-H set Output 2 to Input " .. ctl.Value)
        end
    end
end

function NV32RouterController:setRoomControlsComponent()
    self.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
    if self.roomControls ~= nil then
        -- Add event handlers for system power and fire alarm
        local this = self  -- Capture self for use in handlers

        self.roomControls["ledSystemPower"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:setRoute(this.inputs[1], this.outputs.OUTPUT1)
                this:setRoute(this.inputs[1], this.outputs.OUTPUT2)
            else
                this:setRoute(this.inputs[4], this.outputs.OUTPUT1)
                this:setRoute(this.inputs[4], this.outputs.OUTPUT2)
            end
        end
        -- Fire alarm active: store the last input before override
        self.roomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean and not this.fireAlarmActive then
                -- Fire alarm just activated: store the last input before override
                this.preFireAlarmInput = this.preFireAlarmInput or {}
                this.preFireAlarmInput[this.outputs.OUTPUT1] = this.lastInput[this.outputs.OUTPUT1]
                this.preFireAlarmInput[this.outputs.OUTPUT2] = this.lastInput[this.outputs.OUTPUT2]
                this.fireAlarmActive = true
                -- Route to fire alarm input (e.g., Graphic2)
                this:setRoute(this.inputs[5], this.outputs.OUTPUT1)
                this:setRoute(this.inputs[5], this.outputs.OUTPUT2)
            elseif not ctl.Boolean and this.fireAlarmActive then
                -- Fire alarm just cleared: restore previous input
                this.fireAlarmActive = false
                if this.roomControls["ledSystemPower"].Boolean then
                    this:setRoute(this.preFireAlarmInput[this.outputs.OUTPUT1] or this.inputs[1], this.outputs.OUTPUT1)
                    this:setRoute(this.preFireAlarmInput[this.outputs.OUTPUT2] or this.inputs[1], this.outputs.OUTPUT2)
                end
                -- Optionally clear the stored value
                this.preFireAlarmInput[this.outputs.OUTPUT1] = nil
                this.preFireAlarmInput[this.outputs.OUTPUT2] = nil
            end
        end
    end
end

--------** Video Routing Functions **--------
function NV32RouterController:setRoute(input, output)
    if self.nv32Router then
        self.nv32Router["hdmi.out."..tostring(output)..".select.index"].Value = input
        self:debugPrint("Set Output "..tostring(output).." to Input "..tostring(input))
        -- Track the last input for this output
        self.lastInput[output] = input
    end
end

--------** Event Handler Registration **--------
function NV32RouterController:registerEventHandlers()
    -- NV32 Router component handler
    self.controls.devNV32.EventHandler = function()
        self:setNV32RouterComponent()
    end
    
    -- Room Controls component handler
    self.controls.compRoomControls.EventHandler = function()
        self:setRoomControlsComponent()
    end
    
    -- Output 1 button handlers
    for i, btn in ipairs(self.controls.btnNV32Out01) do
        btn.EventHandler = function()
            self:setRoute(self.inputs[i], self.outputs.OUTPUT1)
        end
    end
    
    -- Output 2 button handlers
    for i, btn in ipairs(self.controls.btnNV32Out02) do
        btn.EventHandler = function()
            self:setRoute(self.inputs[i], self.outputs.OUTPUT2)
        end
    end
end

--------** Initialization **--------
function NV32RouterController:funcInit()
    self:populateNV32Choices()
    self:populateRoomControlsChoices()
    self:setNV32RouterComponent()
    self:setRoomControlsComponent()
    
    -- Set default selection to first input (HDMI1) for both outputs
    if self.nv32Router then
        self:setRoute(self.inputs[1], self.outputs.OUTPUT1)
        self:setRoute(self.inputs[1], self.outputs.OUTPUT2)
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
    
    if self.roomControls then
        if self.roomControls["ledSystemPower"].EventHandler then
            self.roomControls["ledSystemPower"].EventHandler = nil
        end
        if self.roomControls["ledFireAlarm"].EventHandler then
            self.roomControls["ledFireAlarm"].EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed")
end


--------** Factory Function **--------
local function createNV32RouterController(config)
    print("=== Creating NV32RouterController ===")
    local defaultConfig = {
        debugging = true
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return NV32RouterController.new(controllerConfig)
    end)
    
    if success then
        print("✓ Successfully created NV32 Router Controller")
        return controller
    else
        print("✗ Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the controller for this script instance
print("=== Starting NV32RouterController Instance Creation ===")
myNV32RouterController = createNV32RouterController()
print("=== NV32RouterController Instance Creation Complete ===")
print("myNV32RouterController global variable set: " .. tostring(myNV32RouterController ~= nil))

-- Test NV32 component accessibility
if myNV32RouterController then
    print("NV32 Controller initialized: " .. tostring(myNV32RouterController.nv32Router ~= nil))
    if myNV32RouterController.nv32Router then
        print("NV32 Component name: " .. tostring(myNV32RouterController.nv32Router.Name))
    end
end

print("=== NV32 Router Controller Status ===")
print("✓ NV32 script: Basic router functionality active")
print("✓ UCI control handled via UCI script using UCI variables")
print("=== NV32 Status Complete ===")

--[[
Usage:
- For each Text Controller instance, create unique controls (e.g., devNV32_A, btnNV32Out01_A, etc.).
- Replace 'INSTANCE' in the controls table with your unique suffix for each instance.
- Paste the customized script into each Text Controller instance.
- Each instance will only control its own NV32 device and controls, with no risk of cross-talk.

UCI Integration:
- UCI control is handled directly by the UCI script via UCI variables (Controls.devNV32)
- No script-to-script communication required
- Each UCI controls only its assigned NV32 device
]]-- 