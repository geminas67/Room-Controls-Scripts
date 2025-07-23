--[[
  ControllerTemplate_MCP - Q-SYS Control Script Template (MCP Style, Refactored)
  Author: <Your Name or AI>
  Date: <YYYY-MM-DD>
  Version: 3.0
  Description: Refactored for event-driven, OOP, metatable-based architecture per Lua Refactoring Prompt. 
  Uses SonyBraviaDisplayWallController as reference for structure and best practices.
]]--

-- Control references (flat, for validation)
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    roomControls = Controls.compRoomControls,
    compExampleComponents = Controls.compExampleComponents, -- Array
    compAnotherComponents = Controls.compAnotherComponents, -- Array
}

-- Validate required controls exist (flat)
local function validateControls()
    local missing = {}
    if not controls.roomName then table.insert(missing, "roomName") end
    if not controls.txtStatus then table.insert(missing, "txtStatus") end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

--------** Class Definition **--------
ControllerTemplate_MCP = {}
ControllerTemplate_MCP.__index = ControllerTemplate_MCP

function ControllerTemplate_MCP.new(roomName, config)
    local self = setmetatable({}, ControllerTemplate_MCP)
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.controls = controls
    self.componentTypes = {
        exampleComponent = "example_component_type",
        anotherComponent = "another_component_type",
        roomControls = "device_controller_script"
    }
    self.components = {
        exampleComponents = {},
        anotherComponents = {},
        compRoomControls = nil,
        invalid = {}
    }
    self.state = {
        exampleState = false
    }
    self.config = {
        maxExampleComponents = config and config.maxExampleComponents or 4,
        maxAnotherComponents = config and config.maxAnotherComponents or 2
    }
    self:initModules()
    return self
end

--------** Debug Helper **--------
function ControllerTemplate_MCP:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Safe Component Access **--------
function ControllerTemplate_MCP:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then component[control].Boolean = value; return true
            elseif action == "setPosition" then component[control].Position = value; return true
            elseif action == "setString" then component[control].String = value; return true
            elseif action == "trigger" then component[control]:Trigger(); return true
            elseif action == "get" then return component[control].Boolean
            elseif action == "getPosition" then return component[control].Position
            elseif action == "getString" then return component[control].String
            end
        end
        return false
    end)
    if not success then self:debugPrint("Component access error: "..tostring(result)) end
    return result
end

--------** Dynamic Component Discovery **--------
function ControllerTemplate_MCP:getComponentNames()
    local namesTable = {
        ExampleComponentNames = {},
        AnotherComponentNames = {},
        CompRoomControlsNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.exampleComponent then
            table.insert(namesTable.ExampleComponentNames, comp.Name)
        elseif comp.Type == self.componentTypes.anotherComponent then
            table.insert(namesTable.AnotherComponentNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.CompRoomControlsNames, comp.Name)
        end
    end
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    if self.controls.compExampleComponents then
        for i, ctl in ipairs(self.controls.compExampleComponents) do
            ctl.Choices = namesTable.ExampleComponentNames
        end
    end
    if self.controls.compAnotherComponents then
        for i, ctl in ipairs(self.controls.compAnotherComponents) do
            ctl.Choices = namesTable.AnotherComponentNames
        end
    end
    if self.controls.roomControls then
        self.controls.roomControls.Choices = namesTable.CompRoomControlsNames
    end
end

--------** Component Management **--------
function ControllerTemplate_MCP:setComponent(ctrl, componentType)
    local componentName = ctrl and ctrl.String or nil
    if not componentName or componentName == "" or componentName == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return nil
    end
    if #Component.GetControls(Component.New(componentName)) < 1 then
        if ctrl then
            ctrl.String = "[Invalid Component Selected]"
            ctrl.Color = "pink"
        end
        self:setComponentInvalid(componentType)
        return nil
    end
    if ctrl then ctrl.Color = "white" end
    self:setComponentValid(componentType)
    return Component.New(componentName)
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
            if self.controls.txtStatus then
                self.controls.txtStatus.String = "Invalid Components"
                self.controls.txtStatus.Value = 1
            end
            return
        end
    end
    if self.controls.txtStatus then
        self.controls.txtStatus.String = "OK"
        self.controls.txtStatus.Value = 0
    end
end

--------** Component Setup **--------
function ControllerTemplate_MCP:setupExampleComponents()
    if not self.controls.compExampleComponents then return end
    for i, compSelector in ipairs(self.controls.compExampleComponents) do
        if compSelector then
            self:setExampleComponent(i)
        end
    end
end

function ControllerTemplate_MCP:setupAnotherComponents()
    if not self.controls.compAnotherComponents then return end
    for i, compSelector in ipairs(self.controls.compAnotherComponents) do
        if compSelector then
            self:setAnotherComponent(i)
        end
    end
end

function ControllerTemplate_MCP:setupRoomControlsComponent()
    if not self.controls.roomControls then return end
    self:setRoomControlsComponent()
end

function ControllerTemplate_MCP:setExampleComponent(index)
    if not self.controls.compExampleComponents or not self.controls.compExampleComponents[index] then
        self:debugPrint("Example component control " .. index .. " not found")
        return
    end
    local componentType = "Example Component [" .. index .. "]"
    self.components.exampleComponents[index] = self:setComponent(self.controls.compExampleComponents[index], componentType)
    if self.components.exampleComponents[index] then
        self:setupExampleComponentEvents(index)
    end
end

function ControllerTemplate_MCP:setAnotherComponent(index)
    if not self.controls.compAnotherComponents or not self.controls.compAnotherComponents[index] then
        self:debugPrint("Another component control " .. index .. " not found")
        return
    end
    local componentType = "Another Component [" .. index .. "]"
    self.components.anotherComponents[index] = self:setComponent(self.controls.compAnotherComponents[index], componentType)
    if self.components.anotherComponents[index] then
        self:setupAnotherComponentEvents(index)
    end
end

function ControllerTemplate_MCP:setRoomControlsComponent()
    local componentType = "Room Controls"
    self.components.compRoomControls = self:setComponent(self.controls.roomControls, componentType)
    if self.components.compRoomControls then
        self:updateRoomNameFromComponent()
        self:setupRoomControlsComponentEvents()
    end
end

--------** Event Handler Setup **--------
function ControllerTemplate_MCP:setupExampleComponentEvents(index)
    local comp = self.components.exampleComponents[index]
    if not comp then return end
    if comp["ExampleButton.press"] then
        comp["ExampleButton.press"].EventHandler = function()
            self:debugPrint("ExampleButton pressed on component " .. index .. "!")
        end
    end
end

function ControllerTemplate_MCP:setupAnotherComponentEvents(index)
    local comp = self.components.anotherComponents[index]
    if not comp then return end
    if comp["AnotherButton.press"] then
        comp["AnotherButton.press"].EventHandler = function()
            self:debugPrint("AnotherButton pressed on component " .. index .. "!")
        end
    end
end

function ControllerTemplate_MCP:setupRoomControlsComponentEvents()
    local comp = self.components.compRoomControls
    if not comp then return end
    if comp["ledSystemPower"] then
        comp["ledSystemPower"].EventHandler = function()
            local systemPowerState = self:safeComponentAccess(comp, "ledSystemPower", "get")
            if not systemPowerState then
                self:debugPrint("System power off")
            end
        end
    end
    if comp["roomName"] then
        comp["roomName"].EventHandler = function()
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
    if self.controls.compExampleComponents then
        for i, compSelector in ipairs(self.controls.compExampleComponents) do
            if compSelector then
                compSelector.EventHandler = function()
                    self:setExampleComponent(i)
                end
            end
        end
    end
    if self.controls.compAnotherComponents then
        for i, compSelector in ipairs(self.controls.compAnotherComponents) do
            if compSelector then
                compSelector.EventHandler = function()
                    self:setAnotherComponent(i)
                end
            end
        end
    end
    if self.controls.roomControls then
        self.controls.roomControls.EventHandler = function()
            self:setRoomControlsComponent()
        end
    end
end

--------** Module Initialization **--------
function ControllerTemplate_MCP:initModules()
    self:initExampleModule()
    -- Add more module initializations here
end

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

--------** Initialization **--------
function ControllerTemplate_MCP:funcInit()
    self:debugPrint("Starting ControllerTemplate_MCP initialization...")
    self:getComponentNames()
    self:setupRoomControlsComponent()
    self:setupExampleComponents()
    self:setupAnotherComponents()
    self:registerEventHandlers()
    self:debugPrint("ControllerTemplate_MCP Initialized with " .. self.exampleModule.getComponentCount() .. " example components")
end

--------** Cleanup **--------
function ControllerTemplate_MCP:cleanup()
    for i, comp in pairs(self.components.exampleComponents) do
        if comp and comp["ExampleButton.press"] then comp["ExampleButton.press"].EventHandler = nil end
    end
    for i, comp in pairs(self.components.anotherComponents) do
        if comp and comp["AnotherButton.press"] then comp["AnotherButton.press"].EventHandler = nil end
    end
    if self.components.compRoomControls then
        local ledSystemPower = self.components.compRoomControls["ledSystemPower"]
        if ledSystemPower then ledSystemPower.EventHandler = nil end
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl then roomNameControl.EventHandler = nil end
    end
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
if not validateControls() then return end

local function getRoomNameFromComponent()
    if controls.roomControls and controls.roomControls.String ~= "" and controls.roomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(controls.roomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    if controls.roomName and controls.roomName.String and controls.roomName.String ~= "" then
        return "["..controls.roomName.String.."]"
    end
    return "[Default Room]"
end

local roomName = getRoomNameFromComponent()
myControllerTemplate_MCP = createControllerTemplate_MCP(roomName)

if myControllerTemplate_MCP then
    print("ControllerTemplate_MCP created successfully!")
else
    print("ERROR: Failed to create ControllerTemplate_MCP!")
end 