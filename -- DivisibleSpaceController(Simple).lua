--[[ 
  Divisible Space Controller - Modular Parent Room Selection
  Author: Nikolas Smith
  2025-07-02
  Firmware Req: 10.0.0
  Version: 1.0 (Parent Room Selection Version)
]]--

--------** Simple Room Controller Factory **--------
local function createSystemController(roomName, roomType, component)
    local controller = {
        roomName = roomName or "Default Room",
        roomType = roomType or "Default",
        component = component
    }

    controller.audioModule = {
        setVolume = function(volume) end,
        setPrivacy = function(privacy) end,
        setMute = function(mute) end
    }

    controller.powerModule = {
        powerOn = function()
            if controller.component and controller.component["btnSystemOnOff"] then
                controller.component["btnSystemOnOff"].Boolean = true
            end
        end,
        powerOff = function()
            if controller.component and controller.component["btnSystemOnOff"] then
                controller.component["btnSystemOnOff"].Boolean = false
            end
        end,
        getPowerState = function()
            if controller.component and controller.component["ledSystemPower"] then
                return controller.component["ledSystemPower"].Boolean
            end
            return false
        end
    }

    controller.publishNotification = function()
        return {
            roomName = controller.roomName,
            roomType = controller.roomType,
            status = "Active",
            powerState = controller.powerModule.getPowerState()
        }
    end

    controller.cleanup = function() end

    return controller
end

--------** Class Definition **--------
DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

--------** Class Constructor **--------
function DivisibleSpaceController.new(config)
    local self = setmetatable({}, DivisibleSpaceController)
    self.debugging = (config and config.debugging) or false
    self.clearString = "[Clear]"
    self.config = {
        controlColors = { white = 'White', pink = 'Pink' },
        maxRooms = 4
    }
    self.state = {
        combined = false
    }
    self.components = {
        roomControllers = {},
        parentRoomName = nil,
        invalid = {}
    }
    return self
end

--------** Debug Helper **--------
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then print("[DivisibleSpace] "..str) end
end

--------** Room Combination Logic **--------
function DivisibleSpaceController:combineRooms()
    self.state.combined = true
    self:debugPrint("Combining rooms - Powering on all selected room controllers")

    if Controls.compRoomControls then
        for i, comp in ipairs(Controls.compRoomControls) do
            if comp.String ~= "" and comp.String ~= self.clearString then
                local component = Component.New(comp.String)
                if component and component["btnSystemOnOff"] then
                    component["btnSystemOnOff"].Boolean = true
                    self:debugPrint("Powered on room controller " .. i .. ": " .. comp.String)
                end
            end
        end
    end

    local parentRoom = self:getParentRoom()
    if parentRoom then
        parentRoom.powerModule.powerOn()
        for roomName, rc in pairs(self.components.roomControllers) do
            if rc ~= parentRoom and rc.powerModule then
                rc.powerModule.powerOn()
            end
        end
    end

    self:publishSystemState()
end

function DivisibleSpaceController:separateRooms()
    self.state.combined = false
    if Controls.btnCombine then
        Controls.btnCombine.Boolean = false
    end
    self:debugPrint("Separating rooms - Each room maintains current power state")
    self:publishSystemState()
end

-- Get parent room helper
function DivisibleSpaceController:getParentRoom()
    if self.components.parentRoomName then
        return self.components.roomControllers[self.components.parentRoomName]
    end
    -- Fallback to first room if no parent selected
    for roomName, rc in pairs(self.components.roomControllers) do
        return rc
    end
    return nil
end

-- Monitor parent room power state changes
function DivisibleSpaceController:monitorParentPowerState()
    self:debugPrint("Setting up parent power monitoring...")
    
    -- Remove existing event handlers
    for _, rc in pairs(self.components.roomControllers) do
        if rc.component and rc.component["ledSystemPower"] then
            rc.component["ledSystemPower"].EventHandler = nil
        end
    end

    local parentRoom = self:getParentRoom()
    self:debugPrint("Parent room found: " .. tostring(parentRoom and parentRoom.roomName or "nil"))
    
    if parentRoom and parentRoom.component and parentRoom.component["ledSystemPower"] then
        self:debugPrint("Setting up event handler for parent room: " .. parentRoom.roomName)
        parentRoom.component["ledSystemPower"].EventHandler = function()
            local parentPowerState = parentRoom.component["ledSystemPower"].Boolean
            self:debugPrint("Parent room power state changed to: " .. tostring(parentPowerState))
            if self.state.combined then
                if parentPowerState then
                    for roomName, rc in pairs(self.components.roomControllers) do
                        if rc ~= parentRoom and rc.powerModule then
                            rc.powerModule.powerOn()
                        end
                    end
                else
                    for roomName, rc in pairs(self.components.roomControllers) do
                        if rc ~= parentRoom and rc.powerModule then
                            rc.powerModule.powerOff()
                        end
                    end
                    self:separateRooms()
                end
            end
        end
        self:debugPrint("Event handler set up successfully")
    else
        self:debugPrint("Could not set up parent power monitoring - missing parent room or ledSystemPower control")
        if parentRoom then
            self:debugPrint("Parent room exists but missing ledSystemPower control")
        else
            self:debugPrint("No parent room found")
        end
    end
end

--------** System State Publishing **--------
function DivisibleSpaceController:publishSystemState()
    local state = { Combined = self.state.combined }
    for roomName, rc in pairs(self.components.roomControllers) do
        if rc and rc.publishNotification then
            state[roomName] = rc:publishNotification()
        else
            state[roomName] = {}
        end
    end
    if Notifications and Notifications.Publish then
        Notifications.Publish("DivisibleSpaceState", state)
    end
end

--------** Component Management **--------
function DivisibleSpaceController:setComponent(ctrl, componentType)
    if not ctrl then return nil end
    local componentName = ctrl.String
    if componentName == "" or componentName == self.clearString then
        ctrl.Color = self.config.controlColors.white
        self:setComponentValid(componentType)
        return nil
    end
    local testComponent = Component.New(componentName)
    if #Component.GetControls(testComponent) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = self.config.controlColors.pink
        self:setComponentInvalid(componentType)
        return nil
    end
    ctrl.Color = self.config.controlColors.white
    self:setComponentValid(componentType)
    return testComponent
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

--------** Room Controller Setup **--------
function DivisibleSpaceController:setRoomController(idx)
    if not Controls.compRoomControls or not Controls.compRoomControls[idx] then
        return
    end
    local componentType = "Room Controller [" .. idx .. "]"
    local component = self:setComponent(Controls.compRoomControls[idx], componentType)
    if component then
        local roomName = "Room " .. idx
        if component["roomName"] and component["roomName"].String ~= "" then
            roomName = component["roomName"].String
        end
        local roomType = "Default"
        if component["selDefaultConfigs"] and component["selDefaultConfigs"].String ~= "" then
            roomType = component["selDefaultConfigs"].String
        end
        self.components.roomControllers[roomName] = createSystemController(roomName, roomType, component)
        self:updateParentRoomChoices()
    else
        -- Cleanup all controllers if one is removed/invalid
        for roomName, rc in pairs(self.components.roomControllers) do
            if rc and rc.cleanup then
                rc:cleanup()
            end
        end
        self.components.roomControllers = {}
        self:updateParentRoomChoices()
    end
end

--------** Parent Room Selection Logic **--------
function DivisibleSpaceController:updateParentRoomChoices()
    if Controls.selParentRoom then
        local choices = {}
        for roomName, _ in pairs(self.components.roomControllers) do
            table.insert(choices, roomName)
        end
        table.sort(choices)
        Controls.selParentRoom.Choices = choices
        self:debugPrint("Parent room choices updated: " .. table.concat(choices, ", "))
        
        -- Auto-select if only one or if none selected
        if Controls.selParentRoom.String == "" and #choices > 0 then
            Controls.selParentRoom.String = choices[1]
            self:debugPrint("Auto-selected parent room: " .. choices[1])
        end
        -- Ensure parentRoomName is always valid
        if not self.components.roomControllers[Controls.selParentRoom.String] and #choices > 0 then
            Controls.selParentRoom.String = choices[1]
            self:debugPrint("Reset parent room to: " .. choices[1])
        end
        self.components.parentRoomName = Controls.selParentRoom.String
        self:debugPrint("Setting parent room to: " .. tostring(self.components.parentRoomName))
        self:monitorParentPowerState()
    else
        self:debugPrint("Controls.selParentRoom not found - using first room as parent")
        -- Fallback to first room as parent
        for roomName, _ in pairs(self.components.roomControllers) do
            self.components.parentRoomName = roomName
            self:debugPrint("Fallback parent room: " .. roomName)
            self:monitorParentPowerState()
            break
        end
    end
end

function DivisibleSpaceController:registerParentRoomSelector()
    if Controls.selParentRoom then
        Controls.selParentRoom.EventHandler = function(ctl)
            self.components.parentRoomName = ctl.String
            self:monitorParentPowerState()
            self:debugPrint("Parent room changed to: " .. tostring(ctl.String))
        end
    end
end

--------** Component Name Discovery **--------
function DivisibleSpaceController:getComponentNames()
    local namesTable = { RoomControllerNames = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "device_controller_script" then
            local testComp = Component.New(comp.Name)
            if testComp["roomName"] or testComp["selDefaultConfigs"] then
                table.insert(namesTable.RoomControllerNames, comp.Name)
            end
        end
    end
    table.sort(namesTable.RoomControllerNames)
    table.insert(namesTable.RoomControllerNames, self.clearString)
    if Controls.compRoomControls then
        for i, comp in ipairs(Controls.compRoomControls) do
            comp.Choices = namesTable.RoomControllerNames
        end
    end
end

--------** Event Handlers **--------
function DivisibleSpaceController:registerEventHandlers()
    if Controls.btnCombine then
        Controls.btnCombine.EventHandler = function(ctl)
            if ctl.Boolean then
                self:combineRooms()
            else
                self:separateRooms()
            end
        end
    end
    if Controls.compRoomControls then
        for i, comp in ipairs(Controls.compRoomControls) do
            comp.EventHandler = function()
                self:setRoomController(i)
            end
        end
    end
    -- Parent room selector
    self:registerParentRoomSelector()
    -- Optional: Partition sensor for automatic separation
    if Controls.partitionSensor then
        Controls.partitionSensor.EventHandler = function(ctl)
            if not ctl.Boolean then
                self:separateRooms()
            end
        end
    end
end

--------** Initialization **--------
function DivisibleSpaceController:funcInit()
    self:debugPrint("Initializing Divisible Space Controller...")
    self:getComponentNames()
    self:registerEventHandlers()
    self:separateRooms()
    if Controls.compRoomControls then
        for i, comp in ipairs(Controls.compRoomControls) do
            if comp.String ~= "" and comp.String ~= self.clearString then
                self:setRoomController(i)
            end
        end
    end
    self:updateParentRoomChoices()
    self:debugPrint("Initialization complete.")
end

--------** Factory Function **--------
local function createDivisibleSpaceController(config)
    local success, controller = pcall(function()
        local instance = DivisibleSpaceController.new(config)
        instance:funcInit()
        return instance
    end)
    if success then
        return controller
    else
        print("Failed to create controller: "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
myDivisibleSpaceController = createDivisibleSpaceController({
    debugging = true
})
