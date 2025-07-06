--[[
  ControllerTemplate_MCP - Q-SYS Control Script Template (MCP Style)
  Author: <Your Name or AI>
  Date: <YYYY-MM-DD>
  Version: 2.2
  Description: Use this template for all Q-SYS control scripts. 
  Follows Perplexity MCP-style efficiency and modularity.
  Includes robust control validation, error handling, and dynamic component discovery.
  Now includes RoomControls component support for room name management.
]]--

-- Define control references with nil checks
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    roomControls = Controls.compRoomControls,
    -- Component selection controls (arrays for multiple instances)
    compExampleComponents = Controls.compExampleComponents, -- Array of component selectors
    compAnotherComponents = Controls.compAnotherComponents, -- Array of component selectors
    -- Add more component selection controls as needed
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
    -- if not controls.compExampleComponents then
    --     table.insert(missingControls, "compExampleComponents")
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
    
    -- Component type definitions
    self.componentTypes = {
        exampleComponent = "example_component_type",
        anotherComponent = "another_component_type",
        roomControls = "device_controller_script" -- RoomControls component type
    }
    
    -- Component references (using arrays for multiple instances)
    self.components = {
        exampleComponents = {}, -- Array for multiple example components
        anotherComponents = {}, -- Array for multiple another components
        compRoomControls = nil, -- RoomControls component
        invalid = {}
    }
    -- State variables
    self.state = {
        exampleState = false
    }
    -- Configuration
    self.config = {
        exampleSetting = true,
        maxExampleComponents = config and config.maxExampleComponents or 4,
        maxAnotherComponents = config and config.maxAnotherComponents or 2
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

--------** Component Discovery **--------
function ControllerTemplate_MCP:discoverComponentNames()
    local namesTable = {
        ExampleComponentNames = {},
        AnotherComponentNames = {},
        CompRoomControlsNames = {},
        -- Add more component type arrays as needed
    }

    -- Discover components by type using Component.GetComponents()
    for _, component in pairs(Component.GetComponents()) do
        -- Example: Discover gain components
        if component.Type == "gain" then
            table.insert(namesTable.ExampleComponentNames, component.Name)
        -- Example: Discover display components  
        elseif component.Type == "%PLUGIN%_78a74df3-40bf-447b-a714-f564ebae238a_%FP%_bec481a6666b76b5249bbd12046c3920" then
            table.insert(namesTable.AnotherComponentNames, component.Name)
        -- Discover RoomControls components
        elseif component.Type == self.componentTypes.roomControls and string.match(component.Name, "^compRoomControls") then
            table.insert(namesTable.CompRoomControlsNames, component.Name)
        -- Add more component type checks as needed
        -- elseif component.Type == "your_component_type" then
        --     table.insert(namesTable.YourComponentNames, component.Name)
        end
    end

    -- Sort component names and add clear option
    for _, nameArray in pairs(namesTable) do
        table.sort(nameArray)
        table.insert(nameArray, self.clearString)
    end

    return namesTable
end

--------** Populate Component Choices **--------
function ControllerTemplate_MCP:populateComponentChoices()
    local namesTable = self:discoverComponentNames()
    
    -- Populate choices for example component selectors
    if controls.compExampleComponents then
        for i, compSelector in ipairs(controls.compExampleComponents) do
            if compSelector then
                compSelector.Choices = namesTable.ExampleComponentNames
            end
        end
    end
    
    -- Populate choices for another component selectors
    if controls.compAnotherComponents then
        for i, compSelector in ipairs(controls.compAnotherComponents) do
            if compSelector then
                compSelector.Choices = namesTable.AnotherComponentNames
            end
        end
    end
    
    -- Populate choices for RoomControls component
    if controls.roomControls then
        controls.roomControls.Choices = namesTable.CompRoomControlsNames
    end
    
    -- Add more component choice population as needed
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
        doSomething = function(param, componentIndex)
            local comp = componentIndex and selfRef.components.exampleComponents[componentIndex] or selfRef.components.exampleComponents[1]
            if comp then
                selfRef:safeComponentAccess(comp, "ExampleControl", "setString", param)
            end
        end,
        
        getComponentCount = function()
            local count = 0
            for _, comp in pairs(selfRef.components.exampleComponents) do
                if comp then count = count + 1 end
            end
            return count
        end
    }
end

--------** Component Setup **--------
function ControllerTemplate_MCP:setupComponents()
    self:setupExampleComponents()
    self:setupAnotherComponents()
    self:setupRoomControlsComponent()
    -- Add more component setup calls here
end

function ControllerTemplate_MCP:setupExampleComponents()
    if not controls.compExampleComponents then return end
    
    for i, compSelector in ipairs(controls.compExampleComponents) do
        if compSelector then
            self:setExampleComponent(i)
        end
    end
end

function ControllerTemplate_MCP:setupAnotherComponents()
    if not controls.compAnotherComponents then return end
    
    for i, compSelector in ipairs(controls.compAnotherComponents) do
        if compSelector then
            self:setAnotherComponent(i)
        end
    end
end

function ControllerTemplate_MCP:setupRoomControlsComponent()
    if not controls.roomControls then return end
    
    self:setRoomControlsComponent()
end

function ControllerTemplate_MCP:setExampleComponent(index)
    if not controls.compExampleComponents or not controls.compExampleComponents[index] then
        self:debugPrint("Example component control " .. index .. " not found")
        return
    end
    
    local componentType = "Example Component [" .. index .. "]"
    self.components.exampleComponents[index] = self:setComponent(controls.compExampleComponents[index], componentType)
    
    if self.components.exampleComponents[index] then
        -- Set up event handlers for this component
        self:setupExampleComponentEvents(index)
    end
end

function ControllerTemplate_MCP:setAnotherComponent(index)
    if not controls.compAnotherComponents or not controls.compAnotherComponents[index] then
        self:debugPrint("Another component control " .. index .. " not found")
        return
    end
    
    local componentType = "Another Component [" .. index .. "]"
    self.components.anotherComponents[index] = self:setComponent(controls.compAnotherComponents[index], componentType)
    
    if self.components.anotherComponents[index] then
        -- Set up event handlers for this component
        self:setupAnotherComponentEvents(index)
    end
end

function ControllerTemplate_MCP:setRoomControlsComponent()
    if not controls.roomControls then
        self:debugPrint("RoomControls component control not found")
        return
    end
    
    local componentType = "Room Controls"
    self.components.compRoomControls = self:setComponent(controls.roomControls, componentType)
    
    if self.components.compRoomControls then
        -- Update room name from the component
        self:updateRoomNameFromComponent()
        
        -- Set up event handlers for RoomControls component
        self:setupRoomControlsComponentEvents()
    end
end

--------** Component Event Setup **--------
function ControllerTemplate_MCP:setupExampleComponentEvents(index)
    local comp = self.components.exampleComponents[index]
    if not comp then return end
    
    -- Example event handler setup
    if comp["ExampleButton.press"] then
        comp["ExampleButton.press"].EventHandler = function()
            self:debugPrint("ExampleButton pressed on component " .. index .. "!")
            -- Handler logic here
        end
    end
end

function ControllerTemplate_MCP:setupAnotherComponentEvents(index)
    local comp = self.components.anotherComponents[index]
    if not comp then return end
    
    -- Example event handler setup
    if comp["AnotherButton.press"] then
        comp["AnotherButton.press"].EventHandler = function()
            self:debugPrint("AnotherButton pressed on component " .. index .. "!")
            -- Handler logic here
        end
    end
end

function ControllerTemplate_MCP:setupRoomControlsComponentEvents()
    local comp = self.components.compRoomControls
    if not comp then return end
    
    -- EventHandler for system power LED changes
    local ledSystemPower = comp["ledSystemPower"]
    if ledSystemPower then
        ledSystemPower.EventHandler = function()
            local systemPowerState = self:safeComponentAccess(comp, "ledSystemPower", "get")
            if not systemPowerState then
                self:debugPrint("System power off")
                -- Add system power off logic here
            end
        end
    end
    
    -- EventHandler for room name changes
    local roomNameControl = comp["roomName"]
    if roomNameControl then
        roomNameControl.EventHandler = function()
            self:updateRoomNameFromComponent()
        end
    end
end

--------** Room Name Management **--------
function ControllerTemplate_MCP:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
    end
end

--------** Event Handler Registration **--------
function ControllerTemplate_MCP:registerEventHandlers()
    -- Register event handlers for component selectors
    if controls.compExampleComponents then
        for i, compSelector in ipairs(controls.compExampleComponents) do
            if compSelector then
                compSelector.EventHandler = function()
                    self:setExampleComponent(i)
                end
            end
        end
    end
    
    if controls.compAnotherComponents then
        for i, compSelector in ipairs(controls.compAnotherComponents) do
            if compSelector then
                compSelector.EventHandler = function()
                    self:setAnotherComponent(i)
                end
            end
        end
    end
    
    -- Register event handler for RoomControls component
    if controls.roomControls then
        controls.roomControls.EventHandler = function()
            self:setRoomControlsComponent()
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
    
    -- Discover and populate component choices
    self:populateComponentChoices()
    
    -- Setup components and event handlers
    self:setupComponents()
    self:registerEventHandlers()
    
    self:debugPrint("ControllerTemplate_MCP Initialized with " .. 
                   self.exampleModule.getComponentCount() .. " example components")
end

--------** Cleanup **--------
function ControllerTemplate_MCP:cleanup()
    -- Stop any timers first
    if self.exampleTimer then
        self.exampleTimer:Stop()
    end
    
    -- Clear event handlers for example components
    for i, comp in pairs(self.components.exampleComponents) do
        if comp and comp["ExampleButton.press"] then 
            comp["ExampleButton.press"].EventHandler = nil 
        end
    end
    
    -- Clear event handlers for another components
    for i, comp in pairs(self.components.anotherComponents) do
        if comp and comp["AnotherButton.press"] then 
            comp["AnotherButton.press"].EventHandler = nil 
        end
    end
    
    -- Clear event handlers for RoomControls component
    if self.components.compRoomControls then
        local ledSystemPower = self.components.compRoomControls["ledSystemPower"]
        if ledSystemPower then
            ledSystemPower.EventHandler = nil
        end
        
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl then
            roomNameControl.EventHandler = nil
        end
    end
    
    -- Reset component references
    self.components = {
        exampleComponents = {},
        anotherComponents = {},
        compRoomControls = nil,
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

-- Get room name from room controls component or fallback to control
local function getRoomNameFromComponent()
    -- First try to get from the room controls component if it's already set
    if controls.roomControls and controls.roomControls.String ~= "" and controls.roomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(controls.roomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    
    -- Fallback to roomName control
    if controls.roomName and controls.roomName.String and controls.roomName.String ~= "" then
        return "["..controls.roomName.String.."]"
    end
    
    -- Final fallback to default room name
    return "[Default Room]"
end

local roomName = getRoomNameFromComponent()
myControllerTemplate_MCP = createControllerTemplate_MCP(roomName)

if myControllerTemplate_MCP then
    print("ControllerTemplate_MCP created successfully!")
else
    print("ERROR: Failed to create ControllerTemplate_MCP!")
end 