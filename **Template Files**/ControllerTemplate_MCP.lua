--[[
  ControllerTemplate_MCP - Q-SYS Control Script Template (MCP Style)
  Author: <Your Name or AI>
  Date: <YYYY-MM-DD>
  Version: 2.0
  Description: Use this template for all Q-SYS control scripts. 
  Follows Perplexity MCP-style efficiency and modularity.
  Includes robust control validation and error handling.
]]--

-- Define control references with nil checks
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    ExampleComponent = Controls.ExampleComponent,
    AnotherComponent = Controls.AnotherComponent,
    -- Add more controls as needed for your specific implementation
}

-- Validate required controls exist
local function validateControls()
    local missingControls = {}
    
    if not controls.roomName then
        table.insert(missingControls, "roomName")
    end
    
    if not controls.txtStatus then
        table.insert(missingControls, "txtStatus")
    end
    
    -- Add validation for other required controls as needed
    -- if not controls.ExampleComponent then
    --     table.insert(missingControls, "ExampleComponent")
    -- end
    
    if #missingControls > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missingControls, ", "))
        return false
    end
    
    return true
end

--------** Class Definition **--------
ControllerTemplate_MCP = {}
ControllerTemplate_MCP.__index = ControllerTemplate_MCP

function ControllerTemplate_MCP.new(roomName, config)
    local self = setmetatable({}, ControllerTemplate_MCP)
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    
    -- Store reference to controls
    self.controls = controls
    
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
    if controls.ExampleComponent then
        self.components.exampleComponent = self:setComponent(controls.ExampleComponent, "Example Component")
    end
end

function ControllerTemplate_MCP:setAnotherComponent()
    if controls.AnotherComponent then
        self.components.anotherComponent = self:setComponent(controls.AnotherComponent, "Another Component")
    end
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
            if controls.txtStatus then
                controls.txtStatus.String = "Invalid Components"
                controls.txtStatus.Value = 1
            end
            return
        end
    end
    if controls.txtStatus then
        controls.txtStatus.String = "OK"
        controls.txtStatus.Value = 0
    end
end

--------** Initialization **--------
function ControllerTemplate_MCP:funcInit()
    self:debugPrint("Starting ControllerTemplate_MCP initialization...")
    self:setupComponents()
    self:registerEventHandlers()
    self:debugPrint("ControllerTemplate_MCP Initialized")
end

--------** Cleanup **--------
function ControllerTemplate_MCP:cleanup()
    -- Stop any timers first
    if self.exampleTimer then
        self.exampleTimer:Stop()
    end
    
    -- Clear event handlers directly
    if self.components.exampleComponent then
        if self.components.exampleComponent["ExampleButton.press"] then 
            self.components.exampleComponent["ExampleButton.press"].EventHandler = nil 
        end
    end
    
    if self.components.anotherComponent then
        if self.components.anotherComponent["AnotherButton.press"] then 
            self.components.anotherComponent["AnotherButton.press"].EventHandler = nil 
        end
    end
    
    -- Reset component references
    self.components = {
        exampleComponent = nil,
        anotherComponent = nil,
        invalid = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
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
-- Validate controls before creating instance
if not validateControls() then
    print("ERROR: Required controls are missing. Please check your Q-SYS design.")
    return
end

-- Check if roomName control has a valid string value
if not controls.roomName or not controls.roomName.String or controls.roomName.String == "" then
    print("ERROR: Controls.roomName.String is empty or invalid!")
    return
end

local formattedRoomName = "["..controls.roomName.String.."]"
myControllerTemplate_MCP = createControllerTemplate_MCP(formattedRoomName)

if myControllerTemplate_MCP then
    print("ControllerTemplate_MCP created successfully!")
else
    print("ERROR: Failed to create ControllerTemplate_MCP!")
end 