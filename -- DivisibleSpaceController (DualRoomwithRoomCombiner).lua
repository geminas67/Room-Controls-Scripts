--[[
    DivisibleSpaceController - Dual Room Divisible Space Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-09-08
    Firmware Req: 10.0.0    
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular).
    - All event registration is DRY and centralized using control/event maps.
    - Each logical domain is its own class; orchestrator is thin.
    - Debug/config standardized, all validation centralized.
]]

-------------------[ Control References ]-------------------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    btnCombine = Controls.btnCombine,
    partitionSensor = Controls.partitionSensor,
    compRoomCombiner = Controls.compRoomCombiner,
    txtRoomState = Controls.txtRoomState,
    compRoomControls = Controls.compRoomControls,
}

local function validateControls()
    local missing = {}
    for k, v in pairs({ roomName = controls.roomName, txtStatus = controls.txtStatus }) do
        if not v then table.insert(missing, k) end
    end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
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
    if ctrl then ctrl[prop] = val end
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

-------------------[ Base Module Class ]------------------
local BaseModule = {}; BaseModule.__index = BaseModule
function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller; self.name = name or "Module"
    return self
end
function BaseModule:debug(msg)
    self.controller:debugPrint("[" .. self.name .. "] " .. msg)
end
function BaseModule:cleanup() self:debug("Cleanup complete") end

-------------------[ Room Combiner Module ]------------------------
local RoomCombinerModule = setmetatable({}, BaseModule); RoomCombinerModule.__index = RoomCombinerModule
function RoomCombinerModule.new(controller)
    local self = BaseModule.new(controller, "RoomCombiner")
    setmetatable(self, RoomCombinerModule)
    return self
end
function RoomCombinerModule:setWallStates(combined)
    local combiner = self.controller.components.roomCombiner
    if not combiner then 
        self:debug("No room combiner component available for state update")
        return 
    end
    
    for _, wallState in ipairs(self.controller.config.wallStates) do
        self.controller:safeComponentAccess(combiner, wallState, "set", combined)
        self:debug("Set wall state '" .. wallState .. "' to: " .. tostring(combined))
    end
end
function RoomCombinerModule:getWallStates()
    local combiner = self.controller.components.roomCombiner
    if not combiner or not self.controller.config.wallStates then 
        return nil, "No Room Combiner or wallStates configured" 
    end

    local wallStates = {}
    local allOpen = true
    local allClosed = true
    
    for _, wallCtlName in ipairs(self.controller.config.wallStates) do
        local wallState = self.controller:safeComponentAccess(combiner, wallCtlName, "get")
        if wallState ~= nil then
            wallStates[wallCtlName] = wallState and "Open" or "Closed"
            if wallState then allClosed = false else allOpen = false end
        else
            wallStates[wallCtlName] = "Unknown (control not found)"
            allOpen = false; allClosed = false
        end
    end
    
    local isCombined = allOpen
    local stateInfo = "Wall states: " .. table.concat(
        (function()
            local t = {}
            for k,v in pairs(wallStates) do table.insert(t, k..":"..v) end
            return t
        end)(), ", "
    )
    return isCombined, stateInfo
end

-------------------[ Sensor Module ]------------------------
local SensorModule = setmetatable({}, BaseModule); SensorModule.__index = SensorModule
function SensorModule.new(controller)
    local self = BaseModule.new(controller, "Sensor")
    setmetatable(self, SensorModule)
    return self
end
function SensorModule:handleSensorChange(state)
    -- Partition sensor logic: closed sensor = combined room
    local combinedState = not state
    self:debug("Sensor state changed to: " .. tostring(state) .. " (combined: " .. tostring(combinedState) .. ")")
    self.controller:setCombinedRoomState(combinedState)
end

-------------------[ State Management Module ]------------------------
local StateModule = setmetatable({}, BaseModule); StateModule.__index = StateModule
function StateModule.new(controller)
    local self = BaseModule.new(controller, "StateManagement")
    setmetatable(self, StateModule)
    return self
end
function StateModule:updateSystemState(newState)
    -- Guard clause - prevent redundant updates
    if self.controller.state.isCombined == newState then return end
    
    self.controller.state.isCombined = newState
    self:updateUI(newState)
    self.controller.roomCombinerModule:setWallStates(newState)
    self.controller:checkStatus()
    self:debug("System state updated to: " .. (newState and "Combined" or "Separated"))
end
function StateModule:updateUI(newState)
    setProp(controls.btnCombine, "Boolean", newState)
    setProp(controls.txtRoomState, "String", newState and "Combined" or "Separated")
end

-------------------[ DivisibleSpaceController (The Orchestrator) ]-------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController
DivisibleSpaceController.clearString = "[Clear]"
DivisibleSpaceController.componentTypes = {
    roomCombiner = "room_combiner",
    roomControls = "device_controller_script"
}

function DivisibleSpaceController.new(roomName, config)
    local self = setmetatable({}, DivisibleSpaceController)
    self.roomName = roomName or "Default Room"
    self.debugging = config.debugging ~= false
    self.state = { isCombined = false, availableRoomCombiners = {} }
    self.config = config
    self.components = {
        roomCombiner = nil, roomControls = {}, invalid = {
            roomCombiner = false,
            roomControls = false
        }
    }
    
    -- Initialize modules
    self.roomCombinerModule = RoomCombinerModule.new(self)
    self.sensorModule = SensorModule.new(self)
    self.stateModule = StateModule.new(self)
    
    return self
end

-----------------[ Debug Helper ]----------------------
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

------------------[ Component Utility Helpers ]---------------------
function DivisibleSpaceController:safeComponentAccess(component, control, action, value)
    if not component or not component[control] then return false end
    local success, result = pcall(function()
        if      action == "set"         then component[control].Boolean = value; return true
        elseif  action == "setPosition" then component[control].Position = value; return true
        elseif  action == "setString"   then component[control].String = value; return true
        elseif  action == "setValue"    then component[control].Value = value; return true
        elseif  action == "trigger"     then component[control]:Trigger(); return true
        elseif  action == "get"         then return component[control].Boolean
        elseif  action == "getPosition" then return component[control].Position
        elseif  action == "getString"   then return component[control].String
        elseif  action == "getValue"    then return component[control].Value end
        return false
    end)
    if not success then self:debugPrint("Component access error: "..tostring(result)); return false end
    return result
end

------------------[ Event Handler Mapping/Registration ]----------------------
function DivisibleSpaceController:registerEventHandlers()
    local eventMap = {
        btnCombine = function(ctl) self:setCombinedRoomState(ctl.Boolean) end,
        partitionSensor = function(ctl) self.sensorModule:handleSensorChange(ctl.Boolean) end,
        compRoomCombiner = function() self:setRoomCombinerComponent() end,
        compRoomControls = function() self:setRoomControlsComponent() end,
        roomName = function()
            local fmt = "[" .. controls.roomName.String .. "]"; self.roomName = fmt
            self:debugPrint("Room name updated: " .. fmt)
        end
    }
    for k, fn in pairs(eventMap) do bind(controls[k], fn) end
end

----------------[ UI/Component Status Handling ]----------------
function DivisibleSpaceController:setComponent(ctrl, componentType)
    if not ctrl then return nil end
    local componentName = ctrl.String
    if componentName == "" then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    if componentName == self.clearString then
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    local newComponent = Component.New(componentName)
    if #Component.GetControls(newComponent) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    self:debugPrint("Setting " .. componentType .. ": {" .. componentName .. "}")
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return newComponent
end

function DivisibleSpaceController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function DivisibleSpaceController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function DivisibleSpaceController:checkStatus()
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

------------------[ Component Discovery / Selection ]------------------
function DivisibleSpaceController:getComponentNames()
    local compType = DivisibleSpaceController.componentTypes
    local namesTable = {
        RoomCombinerNames = {},
        RoomControlsNames = {}
    }
    
    -- Single pass through all components with pattern matching
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == compType.roomCombiner then
            table.insert(namesTable.RoomCombinerNames, comp.Name)
        elseif comp.Type == compType.roomControls and string.match(comp.Name, "^compRoomControls") then
            -- Check both component type AND name pattern like other working scripts
            table.insert(namesTable.RoomControlsNames, comp.Name)
            self:debugPrint("Found RoomControls component: " .. comp.Name .. " (Type: " .. comp.Type .. ")")
        end
    end
    
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, DivisibleSpaceController.clearString)
    end
    
    if controls.compRoomCombiner then 
        setProp(controls.compRoomCombiner, "Choices", namesTable.RoomCombinerNames)
        self:debugPrint("RoomCombiner choices populated: " .. #namesTable.RoomCombinerNames .. " items")
    end
    
    if controls.compRoomControls then 
        for i, v in ipairs(getControlArray(controls.compRoomControls)) do
            setProp(v, "Choices", namesTable.RoomControlsNames)
        end
        self:debugPrint("RoomControls choices populated: " .. #namesTable.RoomControlsNames .. " items for " .. #getControlArray(controls.compRoomControls) .. " controls")
    end
end

------[ Component Setup/Assignment ]------
function DivisibleSpaceController:setRoomCombinerComponent()
    self.components.roomCombiner = self:setComponent(controls.compRoomCombiner, "roomCombiner")
    if self.components.roomCombiner then
        self:debugPrint("Room Combiner component set: " .. controls.compRoomCombiner.String)
    end
end

function DivisibleSpaceController:setRoomControlsComponent()
    if controls.compRoomControls and #getControlArray(controls.compRoomControls) > 0 then
        local allValid = true
        self.components.roomControls = self.components.roomControls or {}
        
        for i, control in ipairs(getControlArray(controls.compRoomControls)) do
            self.components.roomControls[i] = self:setComponent(control, "roomControls [" .. i .. "]")
            if self.components.roomControls[i] then
                self:debugPrint("Room Controls component set [" .. i .. "]: " .. control.String)
            else
                allValid = false
            end
        end
        
        -- Set overall validation based on whether all room controls are valid
        if allValid then
            self:setComponentValid("roomControls")
        else
            self:setComponentInvalid("roomControls")
        end
    else
        -- No room controls configured - this is valid
        self:setComponentValid("roomControls")
    end
end


----------------------------[ API Methods ]----------------------------
function DivisibleSpaceController:setCombinedRoomState(combined)
    self.stateModule:updateSystemState(combined)
end

function DivisibleSpaceController:getCombinedRoomState()
    return self.state.isCombined
end

function DivisibleSpaceController:getRoomCombinerState()
    return self.roomCombinerModule:getWallStates()
end

function DivisibleSpaceController:setWallStateControls(wallStateNames)
    if type(wallStateNames) == "table" then
        self.config.wallStates = wallStateNames
        self:debugPrint("Wall state controls updated to: " .. table.concat(wallStateNames, ", "))
    else
        self:debugPrint("Error: wallStateNames must be a table")
    end
end

function DivisibleSpaceController:getWallStateControls()
    return self.config.wallStates
end

----------------[ Initialization ]--------------------------
function DivisibleSpaceController:init()
    self:getComponentNames()
    
    -- Initialize components
    self:setRoomCombinerComponent()
    self:setRoomControlsComponent()
    
    self:debugPrint("DivisibleSpaceController ready.")
end

----------------[ Cleanup ]--------------------------
function DivisibleSpaceController:cleanup()
    -- Cleanup all modules
    local modules = { self.roomCombinerModule, self.sensorModule, self.stateModule }
    for _, module in ipairs(modules) do
        if module and module.cleanup then module:cleanup() end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

------------------[ Application Boot / Setup ]------------------
-- Factory function to create the divisible space controller
local function createDivisibleSpaceController(roomName, config)
    local success, controller = pcall(function()
        local object = DivisibleSpaceController.new(roomName, config)
        object:registerEventHandlers()
        object:init()
        return object
    end)
    if success then
        print("DivisibleSpaceController created for "..roomName)
        return controller
    else
        print("ERROR: Failed to create controller: "..tostring(controller))
        return nil
    end
end

--------------[ Instance Creation Entry ]----------------
if not validateControls() then return end

local formattedRoomName = "[" .. (controls.roomName and controls.roomName.String or "Unknown Room") .. "]"
local config = {
    debugging = true,
    wallStates = {
        "wall.1.open", 
        "wall.3.open"
    }
}

myDivisibleSpaceController = createDivisibleSpaceController(formattedRoomName, config)

if myDivisibleSpaceController then
    myDivisibleSpaceController:setCombinedRoomState(false)  -- Ensure walls start closed
    print("DivisibleSpaceController created successfully!")
else
    print("ERROR: DivisibleSpaceController NOT created.")
end

----------------[ PUBLIC API ]--------------------------
--[[
Public API:
    myDivisibleSpaceController:setCombinedRoomState(true|false)
    myDivisibleSpaceController:getCombinedRoomState()
    myDivisibleSpaceController:getRoomCombinerState()
    myDivisibleSpaceController:setWallStateControls({"wall.1.open", "wall.3.open"})
    myDivisibleSpaceController:getWallStateControls()
    myDivisibleSpaceController:cleanup()
]]


