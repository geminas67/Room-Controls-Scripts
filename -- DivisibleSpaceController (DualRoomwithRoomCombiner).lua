--[[ 
  Dual Room Divisible Space Controller - Audio Routing and UCI Switching
  Author: Nikolas Smith (AI optimized best practices)
  Date: 2025-07-15
  Version: 1.2 - Explicit Control Name Use
  For Q-SYS Designer room combiner objects with 'wall.1.open' Boolean control pin.
]]

--------** Control References **--------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    btnCombine = Controls.btnCombine,
    partitionSensor = Controls.partitionSensor,
    btnQuickCombine = Controls.btnQuickCombine,
    btnQuickUncombine = Controls.btnQuickUncombine,
    compRoomCombiner = Controls.compRoomCombiner,
    txtRoomState = Controls.txtRoomState,
    compUCIPanels = {Controls.compUCIPanel01, Controls.compUCIPanel02},
    compRoomControls = {Controls.compRoomControls}
}

--------** Control Validation **--------
local function validateControls()
    local missingControls = {}
    if not controls.roomName then table.insert(missingControls, "roomName") end
    if not controls.txtStatus then table.insert(missingControls, "txtStatus") end
    if not controls.btnCombine then table.insert(missingControls, "btnCombine") end
    if #missingControls > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missingControls, ", "))
        return false
    end
    return true
end

--------** Utility: Resolve Controls Table **--------
local function getControlsTable(component)
    local c = component and component.Controls
    if type(c) == "function" then
        local ok, val = pcall(function() return c(component) end)
        if ok and type(val) == "table" then return val end
    elseif type(c) == "table" then
        return c
    end
    return nil
end

--------** Class Definition **--------
DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, config)
    local self = setmetatable({}, DivisibleSpaceController)
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.controls = controls
    self.componentTypes = { 
        roomCombiner = "room_combiner",
        uciPanels = "touch_screen_status",
        roomControls = "device_controller_script"
    }
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        selectedUCIPanels = {},
        selectedRoomControls = {},
        availableRoomCombiners = {},
        availableUCIPanels = {},
        availableRoomControls = {}
    }
    self.config = {
        maxUCIPanels = config and config.maxUCIPanels or 2,
        maxRoomControls = config and config.maxRoomControls or 4,
        autoDiscover = config and config.autoDiscover ~= false or true
    }
    self:initModules()
    return self
end

--------** Debug Helper **--------
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end
function DivisibleSpaceController:debugComponentProperties(component, label)
    if not self.debugging or not component then return end
    self:debugPrint("Debugging component: " .. tostring(label))
    self:debugPrint("Component type: " .. tostring(component.Type))
    self:debugPrint("Component name: " .. tostring(component.Name))
    if component.Pins then self:debugPrint("Component has Pins property") end
    if component.Controls then self:debugPrint("Component has Controls property") end
    -- List actual controls for troubleshooting
    local t = getControlsTable(component)
    if t then for k,_ in pairs(t) do self:debugPrint("Available control: "..k) end end
end

--------** Component Discovery **--------
function DivisibleSpaceController:discoverComponents()
    self:debugPrint("Starting component discovery...")
    self.state.availableRoomCombiners = {}
    self.state.availableUCIPanels = {}
    self.state.availableRoomControls = {}
    local allComponents = Component.GetComponents()
    for _, comp in ipairs(allComponents) do
        if comp.Type == self.componentTypes.roomCombiner then
            table.insert(self.state.availableRoomCombiners, {name = comp.Name, component = comp})
        elseif comp.Type == self.componentTypes.uciPanels then
            table.insert(self.state.availableUCIPanels, {name = comp.Name, component = comp})
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(self.state.availableRoomControls, {name = comp.Name, component = comp})
        end
    end
    -- Fallback UCI panel discovery by name
    if #self.state.availableUCIPanels == 0 then
        for _, comp in ipairs(allComponents) do
            if string.match(comp.Name, "UCI") or string.match(comp.Name, "uci") then
                table.insert(self.state.availableUCIPanels, {name = comp.Name, component = comp})
            end
        end
    end
    -- Auto-select first available if not set
    if self.config.autoDiscover and #self.state.availableRoomCombiners > 0 and not self.state.selectedRoomCombiner then
        self.state.selectedRoomCombiner = self.state.availableRoomCombiners[1].component
        self:debugPrint("Auto-selected Room Combiner: " .. self.state.availableRoomCombiners[1].name)
    end
    if self.config.autoDiscover and #self.state.availableUCIPanels >= 2 and #self.state.selectedUCIPanels == 0 then
        self.state.selectedUCIPanels[1] = self.state.availableUCIPanels[1].component
        self.state.selectedUCIPanels[2] = self.state.availableUCIPanels[2].component
        self:debugPrint("Auto-selected UCI Panels: " ..
            self.state.availableUCIPanels[1].name .. ", " ..
            self.state.availableUCIPanels[2].name)
    end
    self:debugPrint("Discovery complete - Room Combiners: " .. #self.state.availableRoomCombiners .. 
        ", UCI Panels: " .. #self.state.availableUCIPanels .. 
        ", Room Controls: " .. #self.state.availableRoomControls)
end

--------** State Update (Only 'wall.1.open') **--------
function DivisibleSpaceController:updateSystemState(newState)
    self:debugPrint("Updating system state to: " .. tostring(newState))
    self.state.isCombined = newState
    if self.controls.btnCombine then self.controls.btnCombine.Boolean = newState end
    if self.state.selectedRoomCombiner then
        self:debugPrint("Room Combiner component: " .. tostring(self.state.selectedRoomCombiner.Name))
        self:debugComponentProperties(self.state.selectedRoomCombiner, "Room Combiner")
        -- Explicitly use 'wall.1.open'
        local ctl = getControlsTable(self.state.selectedRoomCombiner)
        if ctl and ctl["wall.1.open"] and ctl["wall.1.open"].Boolean ~= nil then
            ctl["wall.1.open"].Boolean = newState
            self:debugPrint("Updated Room Combiner 'wall.1.open' to: " .. (newState and "true" or "false"))
        else
            self:debugPrint("WARNING: 'wall.1.open' not found or not Boolean control!")
            if ctl then for i,_ in pairs(ctl) do self:debugPrint("Available control: "..i) end end
        end
    end
    -- Parallel UCI switching
    if #self.state.selectedUCIPanels >= 2 then
        local targetPage = newState and "uciCombined" or "uciRoom"
        for i, uciPanel in ipairs(self.state.selectedUCIPanels) do
            if uciPanel then
                Uci.SetUCI(uciPanel.Name, targetPage)
                self:debugPrint("Updated UCI panel " .. i .. " to page: " .. targetPage)
            end
        end
    end
    if self.controls.txtRoomState then
        self.controls.txtRoomState.String = newState and "Combined" or "Separated"
    end
    self:checkStatus()
end

--------** Combo Box Setup **--------
function DivisibleSpaceController:setupComboBoxes()
    if self.controls.compRoomCombiner then
        local items = {self.clearString}
        for _, comp in ipairs(self.state.availableRoomCombiners) do table.insert(items, comp.name) end
        self.controls.compRoomCombiner.Choices = items
        if not self.state.selectedRoomCombiner then self.controls.compRoomCombiner.String = items[1] end
        self.controls.compRoomCombiner.EventHandler = function(ctl)
            local selection = ctl.String
            if selection ~= self.clearString then
                for _, comp in ipairs(self.state.availableRoomCombiners) do
                    if comp.name == selection then
                        self.state.selectedRoomCombiner = comp.component
                        self:debugPrint("Selected Room Combiner: " .. comp.name)
                        break
                    end
                end
            end
        end
    end
    if self.controls.compUCIPanels then
        for i, compCtrl in ipairs(self.controls.compUCIPanels) do
            if compCtrl then
                local items = {self.clearString}
                for _, comp in ipairs(self.state.availableUCIPanels) do table.insert(items, comp.name) end
                compCtrl.Choices = items
                if not self.state.selectedUCIPanels[i] then compCtrl.String = items[1] end
                compCtrl.EventHandler = function(ctl)
                    local selection = ctl.String
                    if selection ~= self.clearString then
                        for _, comp in ipairs(self.state.availableUCIPanels) do
                            if comp.name == selection then
                                self.state.selectedUCIPanels[i] = comp.component
                                self:debugPrint("Selected UCI Panel " .. i .. ": " .. comp.name)
                                break
                            end
                        end
                    end
                end
            end
        end
    end
end

--------** Event Handler Setup **--------
function DivisibleSpaceController:setupEventHandlers()
    if self.controls.btnCombine then
        self.controls.btnCombine.EventHandler = function(ctl)
            self:updateSystemState(ctl.Boolean)
        end
    end
    if self.controls.partitionSensor then
        self.controls.partitionSensor.EventHandler = function(ctl)
            self:updateSystemState(not ctl.Boolean)
        end
    end
    if self.controls.btnQuickCombine then
        self.controls.btnQuickCombine.EventHandler = function()
            self:updateSystemState(true)
        end
    end
    if self.controls.btnQuickUncombine then
        self.controls.btnQuickUncombine.EventHandler = function()
            self:updateSystemState(false)
        end
    end
end

--------** Status Management **--------
function DivisibleSpaceController:checkStatus()
    local status, hasError = "OK", false
    local statusDetails = {}
    if #self.state.availableRoomCombiners == 0 then
        status = "No Room Combiners Found"
        hasError = true
        table.insert(statusDetails, "Add Room Combiner component to design")
    else
        table.insert(statusDetails, "Room Combiners: " .. #self.state.availableRoomCombiners)
        if self.state.selectedRoomCombiner then
            local isCombined, stateInfo = self:GetRoomCombinerState()
            if isCombined ~= nil then
                table.insert(statusDetails, "Room Combiner State: " .. (isCombined and "Combined" or "Separated"))
                table.insert(statusDetails, "State Details: " .. stateInfo)
            else
                table.insert(statusDetails, "Room Combiner State: Unknown (" .. stateInfo .. ")")
            end
        end
    end
    if #self.state.availableUCIPanels > 0 then
        table.insert(statusDetails, "UCI Panels: " .. #self.state.availableUCIPanels)
        local uciNames = {}
        for _, uci in ipairs(self.state.availableUCIPanels) do table.insert(uciNames, uci.name) end
        table.insert(statusDetails, "UCI Components: " .. table.concat(uciNames, ", "))
    else
        table.insert(statusDetails, "UCI Panels: None (Optional)")
    end
    if self.controls.txtStatus then
        self.controls.txtStatus.String = status
        self.controls.txtStatus.Value = hasError and 1 or 0
    end
    self:debugPrint("Status: " .. status)
    for _, detail in ipairs(statusDetails) do self:debugPrint("  " .. detail) end
end

--------** Initialize Modules **--------
function DivisibleSpaceController:initModules()
    self:debugPrint("Modules initialized")
end

--------** API Methods **--------
function DivisibleSpaceController:SetCombinedRoomState(combined)
    self:updateSystemState(combined)
end
function DivisibleSpaceController:GetCombinedRoomState()
    return self.state.isCombined
end
function DivisibleSpaceController:GetRoomCombinerState()
    if not self.state.selectedRoomCombiner then
        return nil, "No Room Combiner selected"
    end
    local ct = getControlsTable(self.state.selectedRoomCombiner)
    if ct and ct["wall.1.open"] and ct["wall.1.open"].Boolean ~= nil then
        return ct["wall.1.open"].Boolean, "'wall.1.open' = " .. tostring(ct["wall.1.open"].Boolean)
    end
    return nil, "Unable to read Room Combiner state"
end
function DivisibleSpaceController:GetAvailableComponents()
    return {
        roomCombiners = self.state.availableRoomCombiners,
        uciPanels = self.state.availableUCIPanels,
        roomControls = self.state.availableRoomControls 
    }
end
function DivisibleSpaceController:RefreshComponentDiscovery()
    self:debugPrint("Refreshing component discovery...")
    self.state.selectedRoomCombiner = nil
    self.state.selectedUCIPanels = {}
    self.state.selectedRoomControls = {}
    self:discoverComponents()
    self:setupComboBoxes()
    self:checkStatus()
end

--------** Initialization Routine **--------
function DivisibleSpaceController:funcInit()
    self:debugPrint("Starting DivisibleSpaceController initialization...")
    self:discoverComponents()
    self:setupComboBoxes()
    self:setupEventHandlers()
    self:updateSystemState(false)
    if Notifications and Notifications.Publish then
        Notifications.Publish("SystemInitialized", {
            roomCombiners = #self.state.availableRoomCombiners,
            uciPanels = #self.state.availableUCIPanels,
            state = "Ready"
        })
    end
    self:debugPrint("DivisibleSpaceController Initialized successfully")
end

--------** Cleanup **--------
function DivisibleSpaceController:cleanup()
    if self.controls.btnCombine then self.controls.btnCombine.EventHandler = nil end
    if self.controls.partitionSensor then self.controls.partitionSensor.EventHandler = nil end
    if self.controls.btnQuickCombine then self.controls.btnQuickCombine.EventHandler = nil end
    if self.controls.btnQuickUncombine then self.controls.btnQuickUncombine.EventHandler = nil end
    if self.controls.compRoomCombiner then self.controls.compRoomCombiner.EventHandler = nil end
    if self.controls.compUCIPanels then
        for _, compCtrl in ipairs(self.controls.compUCIPanels) do
            if compCtrl then compCtrl.EventHandler = nil end
        end
    end
    if self.controls.compRoomControls then
        for _, compCtrl in ipairs(self.controls.compRoomControls) do
            if compCtrl then compCtrl.EventHandler = nil end
        end
    end
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        selectedUCIPanels = {},
        selectedRoomControls = {},
        availableRoomCombiners = {},
        availableUCIPanels = {},
        availableRoomControls = {}
    }
    if self.debugging then self:debugPrint("Cleanup completed") end
end

--------** Factory Function **--------
local function createDivisibleSpaceController(roomName, config)
    print("Creating DivisibleSpaceController for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = DivisibleSpaceController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created DivisibleSpaceController for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
if not validateControls() then
    print("ERROR: Required controls are missing. Please check your Q-SYS design.")
    return
end
if not controls.roomName or not controls.roomName.String or controls.roomName.String == "" then
    print("ERROR: Controls.roomName.String is empty or invalid!")
    return
end
local formattedRoomName = "["..controls.roomName.String.."]"
myDivisibleSpaceController = createDivisibleSpaceController(formattedRoomName)
if myDivisibleSpaceController then
    print("DivisibleSpaceController created successfully!")
else
    print("ERROR: Failed to create DivisibleSpaceController!")
end
