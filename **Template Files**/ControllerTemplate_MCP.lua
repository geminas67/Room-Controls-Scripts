--[[
  ControllerTemplate_MCP - Q-SYS Control Script Template (MCP Style)
  Author: <Your Name or AI>
  Date: <YYYY-MM-DD>
  Version: 1.0
  Description: Use this template for all Q-SYS control scripts. 
  Follows Perplexity MCP-style efficiency and modularity.
]]--

--------** Class Definition **--------
ControllerTemplate_MCP = {}
ControllerTemplate_MCP.__index = ControllerTemplate_MCP

function ControllerTemplate_MCP.new(roomName, config)
    local self = setmetatable({}, ControllerTemplate_MCP)
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    -- Component references
    self.components = {
        exampleComponent = nil,
        anotherComponent = nil,
        invalid = {}
    }
    -- State variables
    self.state = {
        exampleState = false
    }
    -- Configuration
    self.config = {
        exampleSetting = true
    }
    -- Initialize modules
    self:initModules()
    return self
end

--------** Debug Helper **--------
function ControllerTemplate_MCP:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Safe Component Access **--------
function ControllerTemplate_MCP:safeComponentAccess(component, control, action, value)
    local compCtrl = component and component[control]
    if not compCtrl then return false end
    local ok, result = pcall(function()
        if action == "set" then compCtrl.Boolean = value
        elseif action == "setPosition" then compCtrl.Position = value
        elseif action == "setString" then compCtrl.String = value
        elseif action == "trigger" then compCtrl:Trigger()
        elseif action == "get" then return compCtrl.Boolean
        elseif action == "getPosition" then return compCtrl.Position
        elseif action == "getString" then return compCtrl.String
        end
        return true
    end)
    if not ok then self:debugPrint("Component access error: "..tostring(result)) end
    return ok and result
end

--------** Initialize Modules **--------
function ControllerTemplate_MCP:initModules()
    self:initExampleModule()
    -- Add more module initializations here
end

--------** Example Module **--------
function ControllerTemplate_MCP:initExampleModule()
    local selfRef = self
    self.exampleModule = {
        doSomething = function(param)
            local comp = selfRef.components.exampleComponent
            if comp then
                selfRef:safeComponentAccess(comp, "ExampleControl", "setString", param)
            end
        end
    }
end

--------** Component Setup **--------
function ControllerTemplate_MCP:setupComponents()
    self:setExampleComponent()
    self:setAnotherComponent()
    -- Add more component setup calls here
end

function ControllerTemplate_MCP:setExampleComponent()
    self.components.exampleComponent = self:setComponent(Controls.ExampleComponent, "Example Component")
end

function ControllerTemplate_MCP:setAnotherComponent()
    self.components.anotherComponent = self:setComponent(Controls.AnotherComponent, "Another Component")
end

--------** Event Handler Registration **--------
function ControllerTemplate_MCP:registerEventHandlers()
    -- Use local variables for components
    local exampleComp = self.components.exampleComponent
    local anotherComp = self.components.anotherComponent
    -- Register event handlers for example component
    if exampleComp and exampleComp["ExampleButton.press"] then
        exampleComp["ExampleButton.press"].EventHandler = function()
            self:debugPrint("ExampleButton pressed!")
            -- Handler logic here
        end
    end
    -- Register event handlers for another component
    if anotherComp and anotherComp["AnotherButton.press"] then
        anotherComp["AnotherButton.press"].EventHandler = function()
            self:debugPrint("AnotherButton pressed!")
            -- Handler logic here
        end
    end
    -- Add more event handler registrations as needed
end

--------** Component Management **--------
function ControllerTemplate_MCP:setComponent(ctrl, componentType)
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

function ControllerTemplate_MCP:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function ControllerTemplate_MCP:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function ControllerTemplate_MCP:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------** Initialization **--------
function ControllerTemplate_MCP:funcInit()
    self:debugPrint("Starting ControllerTemplate_MCP initialization...")
    self:setupComponents()
    self:registerEventHandlers()
    self:debugPrint("ControllerTemplate_MCP Initialized")
end

--------** Factory Function **--------
local function createControllerTemplate_MCP(roomName, config)
    print("Creating ControllerTemplate_MCP for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = ControllerTemplate_MCP.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created ControllerTemplate_MCP for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
if not Controls.roomName then
    print("ERROR: Controls.roomName not found!")
    return
end

local formattedRoomName = "["..Controls.roomName.String.."]"
myControllerTemplate_MCP = createControllerTemplate_MCP(formattedRoomName)

if myControllerTemplate_MCP then
    print("ControllerTemplate_MCP created successfully!")
else
    print("ERROR: Failed to create ControllerTemplate_MCP!")
end 