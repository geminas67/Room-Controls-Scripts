--[[
  DivisibleSpaceController - Dual Room Divisible Space Controller
  Author: Nikolas Smith (AI Optimized/Q-SYS Best Practices)
  Date: 2025-07-29
  Version: 1.0 - Refactored with Component Management Pattern
]]

-----------------------------[ Control References ]-----------------------------
local controlMap = {
    roomName            = Controls.roomName,
    txtStatus           = Controls.txtStatus,
    btnCombine          = Controls.btnCombine,
    partitionSensor     = Controls.partitionSensor,
    compRoomCombiner    = Controls.compRoomCombiner,
    txtRoomState        = Controls.txtRoomState,
    compRoomControls    = Controls.compRoomControls,
}

----------------------------[ Class Definition ]----------------------------
local DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(config)
    local self = setmetatable({}, DivisibleSpaceController)
    self.controls = config.controls
    self.debugging = config.debugging or false
    self.clearString = "[Clear]"

    self.componentTypes = {
        roomCombiner = "room_combiner",
        roomControls = "device_controller_script"
    }
    
    -- Initialize components table for Component Management pattern
    self.components = {
        roomCombiner = nil,
        roomControls = nil,
        invalid = {}
    }
    
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        availableRoomCombiners = {}
    }
    self.config = {
        wallStates = config.wallStates or {
            "wall.1.open",
            "wall.3.open"
        },
        controlColors = { white = 'White', pink = 'Pink', off = 'Off' },
    }
    self:_validateControls()
    self:discoverComponents()
    self:getComponentNames()
    self:setupComponents()
    self:_wireEventHandlers()
    self:checkStatus()
    return self
end

function DivisibleSpaceController:_validateControls()
    for name, ctl in pairs(self.controls) do
        if not ctl then error("Missing required control: " .. name) end
    end
end

function DivisibleSpaceController:debugPrint(msg)
    if self.debugging then print("[DivisibleSpace Debug] " .. tostring(msg)) end
end

----------------------------[ Safe Component Access ]----------------------------
function DivisibleSpaceController:safeComponentAccess(component, control, action, value)
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
            elseif action == "setValue" then
                component[control].Value = value
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
            elseif action == "getValue" then
                return component[control].Value
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

----------------------------[ Component Discovery ]----------------------------
function DivisibleSpaceController:discoverComponents()
    local namesTable = {
        RoomControlsNames = {}, 
        RoomCombinerNames = {},
        MXANames = {},
    }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.roomCombiner and string.match(comp.Name, "^compRoomCombiner") then
            table.insert(namesTable.RoomCombinerNames, comp.Name)
        elseif comp.Type == self.componentTypes.mxaDevices then
            table.insert(namesTable.MXANames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    self:debugPrint(string.format("Discovery complete - Room Combiners: %d", #self.state.availableRoomCombiners))
    
    -- Debug: List available controls
    if self.debugging and #self.state.availableRoomCombiners > 0 then
        for _, combiner in ipairs(self.state.availableRoomCombiners) do
            self:debugPrint("Available controls for " .. combiner.name .. ":")
            local controls = Component.GetControls(combiner.name)
            for _, ctrl in ipairs(controls) do
                self:debugPrint("  - " .. ctrl.Name)
            end
        end
    end
end


-----------------[ Component Management ]-------------------
function DivisibleSpaceController:setComponent(ctrl, componentType)
    if not ctrl then
        if self.debugging then self:debugPrint("Control is nil for: " .. componentType) end
        return nil
    end
    
    local componentName = ctrl.String
    
    if componentName == "" then
        self:setComponentValid(componentType)
        ctrl.Color = self.config.controlColors.white
        return nil
    elseif componentName == self.clearString then
        ctrl.String = ""
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = self.config.controlColors.pink
        self:setComponentInvalid(componentType)
        return nil
    else
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
end

function DivisibleSpaceController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:updateStatus()
end

function DivisibleSpaceController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:updateStatus()
end

function DivisibleSpaceController:updateStatus()
    if Controls.txtStatus then
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
end

----------------------------[ Component Discovery ]----------------------------
function DivisibleSpaceController:discoverComponents()
    self.state.availableRoomCombiners = {}

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.roomCombiner and string.match(comp.Name, "^compRoomCombiner") then
            table.insert(self.state.availableRoomCombiners, { name = comp.Name, component = comp })
        end
    end

    self:debugPrint(string.format("Discovery complete - Room Combiners: %d", #self.state.availableRoomCombiners))
end

----------------------------[ Component Names Setup ]----------------------------
function DivisibleSpaceController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {}, 
        RoomCombinerNames = {}
    }

    -- Single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.roomCombiner and string.match(comp.Name, "^compRoomCombiner") then
            table.insert(namesTable.RoomCombinerNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    -- Sort and add clear option in single pass
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    -- Direct assignment to controls
    if self.controls.compRoomCombiner then 
        self.controls.compRoomCombiner.Choices = namesTable.RoomCombinerNames 
    end
    
    if self.controls.compRoomControls then 
        self.controls.compRoomControls.Choices = namesTable.RoomControlsNames 
    end
end

----------------------------[ Component Setup ]----------------------------
function DivisibleSpaceController:setupComponents()
    self:setupRoomCombinerComponent()
    self:setupRoomControlsComponent()
end

function DivisibleSpaceController:setupRoomCombinerComponent()
    if self.controls.compRoomCombiner then
        self.components.roomCombiner = self:setComponent(self.controls.compRoomCombiner, "Room Combiner")
        if self.components.roomCombiner then
            self:registerRoomCombinerEventHandlers()
        end
    end
end

function DivisibleSpaceController:setupRoomControlsComponent()
    if self.controls.compRoomControls then
        self.components.roomControls = self:setComponent(self.controls.compRoomControls, "Room Controls")
        if self.components.roomControls then
            self:registerRoomControlsEventHandlers()
        end
    end
end



----------------------------[ Event Handlers ]----------------------------
function DivisibleSpaceController:_wireEventHandlers()
    self:setupButtonHandlers()
    self:setupSensorHandlers()
    self:setupComponentChangeHandlers()
end

function DivisibleSpaceController:setupButtonHandlers()
    local btnCombine = self.controls.btnCombine
    if btnCombine then
        btnCombine.EventHandler = function(ctl)
            -- Prevent redundant updates if state hasn't changed
            if self.state.isCombined ~= ctl.Boolean then
                self:SetCombinedRoomState(ctl.Boolean)
            end
        end
    end
end

function DivisibleSpaceController:setupSensorHandlers()
    local sensor = self.controls.partitionSensor
    if sensor then
        sensor.EventHandler = function(ctl)
            local newState = not ctl.Boolean
            -- Prevent redundant updates if state hasn't changed
            if self.state.isCombined ~= newState then
                self:SetCombinedRoomState(newState)
            end
        end
    end
end

function DivisibleSpaceController:setupComponentChangeHandlers()
    if self.controls.compRoomCombiner then
        self.controls.compRoomCombiner.EventHandler = function() 
            self:setupRoomCombinerComponent()
        end
    end
    if self.controls.compRoomControls then
        self.controls.compRoomControls.EventHandler = function() 
            self:setupRoomControlsComponent()
        end
    end
end

function DivisibleSpaceController:registerRoomCombinerEventHandlers()
    local roomCombiner = self.components.roomCombiner
    if not roomCombiner then return end
    
    -- Update selected room combiner when component is set
    self.state.selectedRoomCombiner = self.controls.compRoomCombiner.String
    if self.debugging then 
        self:debugPrint("Room Combiner component set: " .. tostring(self.state.selectedRoomCombiner))
    end
end

function DivisibleSpaceController:registerRoomControlsEventHandlers()
    local roomControls = self.components.roomControls
    if not roomControls then return end
    
    if self.debugging then 
        self:debugPrint("Room Controls component set")
    end
end

----------------------------[ Core Logic ]----------------------------
function DivisibleSpaceController:updateRoomCombinerState(newState)
    local combiner = self.components.roomCombiner
    if not combiner then 
        self:debugPrint("No room combiner component available for state update")
        return 
    end
    
    for _, wallState in ipairs(self.config.wallStates) do
        if combiner[wallState] then
            combiner[wallState].Boolean = newState
            self:debugPrint("Set wall state '"..wallState.."' to: "..tostring(newState))
        else
            self:debugPrint("Warning: Wall state control '"..wallState.."' not found")
        end
    end
end

function DivisibleSpaceController:updateSystemState(newState)
    self.state.isCombined = newState
    
    -- Update UI controls with error protection
    if self.controls.btnCombine then 
        local success = pcall(function() self.controls.btnCombine.Boolean = newState end)
        if not success then
            self:debugPrint("Warning: Failed to update btnCombine.Boolean")
        end
    end
    
    if self.controls.txtRoomState then
        local success = pcall(function() 
            self.controls.txtRoomState.String = newState and "Combined" or "Separated" 
        end)
        if not success then
            self:debugPrint("Warning: Failed to update txtRoomState.String")
        end
    end
    
    self:updateRoomCombinerState(newState)
    self:checkStatus()
end

----------------------------[ Status Management ]----------------------------
function DivisibleSpaceController:checkStatus()
    local status, hasError = "OK", false
    local statusDetails = {}

    if #self.state.availableRoomCombiners == 0 then
        status, hasError = "No Room Combiners Found", true
        table.insert(statusDetails, "Add Room Combiner component to design")
    else
        table.insert(statusDetails, "Room Combiners: "..#self.state.availableRoomCombiners)
        if self.components.roomCombiner then
            local isCombined, stateInfo = self:GetRoomCombinerState()
            if isCombined ~= nil then
                table.insert(statusDetails, "Room Combiner State: "..(isCombined and "Combined" or "Separated"))
                table.insert(statusDetails, "State Details: "..stateInfo)
            else
                table.insert(statusDetails, "Room Combiner State: Unknown ("..(stateInfo or "")..")")
            end
        end
    end
    
    if self.controls.txtStatus then
        self.controls.txtStatus.String = status
        self.controls.txtStatus.Value = hasError and 1 or 0
    end
    
    self:debugPrint("Status: "..status)
    for _, detail in ipairs(statusDetails) do self:debugPrint("  "..detail) end
end

----------------------------[ API Methods ]----------------------------
function DivisibleSpaceController:SetCombinedRoomState(combined)
    self:updateSystemState(combined)
end

function DivisibleSpaceController:GetCombinedRoomState()
    return self.state.isCombined
end

function DivisibleSpaceController:GetRoomCombinerState()
    if not self.components.roomCombiner or not self.config.wallStates then 
        return nil, "No Room Combiner or wallStates configured" 
    end

    local wallStates = {}
    local allOpen = true
    local allClosed = true
    
    for _, wallCtlName in ipairs(self.config.wallStates) do
        local wallControl = self.components.roomCombiner[wallCtlName]
        if wallControl then
            local wallState = wallControl.Boolean
            wallStates[wallCtlName] = wallState and "Open" or "Closed"
            if wallState then
                allClosed = false
            else
                allOpen = false
            end
        else
            wallStates[wallCtlName] = "Unknown (control not found)"
            allOpen = false
            allClosed = false
        end
    end
    
    local isCombined = allOpen
    local stateInfo = "Wall states: "..table.concat(
        (function()
            local t = {}
            for k,v in pairs(wallStates) do table.insert(t, k..":"..v) end
            return t
        end)(), ", "
    )
    return isCombined, stateInfo
end

function DivisibleSpaceController:GetAvailableComponents()
    return {
        roomCombiners = self.state.availableRoomCombiners
    }
end

function DivisibleSpaceController:SetWallStateControls(wallStateNames)
    if type(wallStateNames) == "table" then
        self.config.wallStates = wallStateNames
        self:debugPrint("Wall state controls updated to: " .. table.concat(wallStateNames, ", "))
    else
        self:debugPrint("Error: wallStateNames must be a table")
    end
end

function DivisibleSpaceController:GetWallStateControls()
    return self.config.wallStates
end

function DivisibleSpaceController:RefreshComponentDiscovery()
    self.state.selectedRoomCombiner = nil
    self:discoverComponents()
    self:setupComponents()
    self:checkStatus()
end

----------------------------[ Cleanup ]----------------------------
function DivisibleSpaceController:cleanup()
    -- Clear all event handlers
    if self.controls.btnCombine then self.controls.btnCombine.EventHandler = nil end
    if self.controls.partitionSensor then self.controls.partitionSensor.EventHandler = nil end
    if self.controls.compRoomCombiner then self.controls.compRoomCombiner.EventHandler = nil end
    if self.controls.compRoomControls then self.controls.compRoomControls.EventHandler = nil end
    
    -- Reset state
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        availableRoomCombiners = {}
    }
    
    -- Reset components
    self.components = {
        roomCombiner = nil,
        roomControls = nil,
        invalid = {}
    }
    
    -- Clear references
    self.controls = nil
    self.config = nil
    
    self:debugPrint("Cleanup completed")
end

----------------------------[ Factory Function ]----------------------------
local function createDivisibleSpaceController(config)
    local success, instance = pcall(function() return DivisibleSpaceController.new(config) end)
    if not success then
        print("Failed to initialize DivisibleSpaceController: " .. tostring(instance))
        return nil
    end
    return instance
end

----------------------------[ Startup ]----------------------------
local ctrlMap = controlMap
local controllerConfig = {
    controls = ctrlMap,
    debugging = true,
    wallStates = {
        "wall.1.open", 
        "wall.3.open"
    },

}

-- Validate controls
local hasErrors = false
for k, v in pairs(ctrlMap) do
    if not v then
        print("ERROR: Missing required control: " .. k)
        hasErrors = true
    end
end

if hasErrors then
    print("ERROR: Control validation failed. Please check your Q-SYS design.")
    return
end

if not ctrlMap.roomName or not ctrlMap.roomName.String or ctrlMap.roomName.String == "" then
    print("ERROR: Controls.roomName.String is empty or invalid!")
    return
end

local formattedRoomName = "[" .. ctrlMap.roomName.String .. "]"
controllerConfig.roomName = formattedRoomName

local myDivisibleSpaceController = createDivisibleSpaceController(controllerConfig)
if myDivisibleSpaceController then
    myDivisibleSpaceController:SetCombinedRoomState(false)  -- Ensure walls start closed
    print("DivisibleSpaceController created successfully!")
else
    print("ERROR: Failed to create DivisibleSpaceController!")
end
