--[[ 
  Dual Room Divisible Space Controller - Audio Routing, and UCI Switching
  Author: Nikolas Smith
  Date: 2025-07-02
  Q-SYS Firmware Req: 9.12+
  Version: 4.0 - Class-Based Architecture with Dynamic Discovery
]]

--------** Control References **--------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    btnCombine = Controls.btnCombine,
    partitionSensor = Controls.partitionSensor,
    btnQuickCombine = Controls.btnQuickCombine,
    btnQuickUncombine = Controls.btnQuickUncombine,
    cmbRoomCombiner = Controls.cmbRoomCombiner,
    cmbUCIPanel1 = Controls.cmbUCIPanel1,
    cmbUCIPanel2 = Controls.cmbUCIPanel2
}

--------** Control Validation **--------
local function validateControls()
    local missingControls = {}
    
    if not controls.roomName then
        table.insert(missingControls, "roomName")
    end
    
    if not controls.txtStatus then
        table.insert(missingControls, "txtStatus")
    end
    
    if not controls.btnCombine then
        table.insert(missingControls, "btnCombine")
    end
    
    if #missingControls > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missingControls, ", "))
        return false
    end
    
    return true
end

--------** Class Definition **--------
DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

function DivisibleSpaceController.new(roomName, config)
    local self = setmetatable({}, DivisibleSpaceController)
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Auto-Discover]"
    
    -- Store reference to controls
    self.controls = controls
    
    -- Component type definitions
    self.componentTypes = {
        roomCombiner = "Room Combiner",
        uciPanels = "UCI",
        roomControls = (comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls"))
    }
    
    -- Component references
    self.components = {
        roomCombiner = nil,
        uciPanels = {},
        roomControls = {},
        invalid = {}
    }
    
    -- State variables
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        selectedUCIPanels = {},
        selectedRoomControls = {},
        availableRoomCombiners = {},
        availableUCIPanels = {},
        availableRoomControls = {}
    }
    
    -- Configuration
    self.config = {
        maxUCIPanels = config and config.maxUCIPanels or 2,
        maxRoomControls = config and config.maxRoomControls or 4,
        autoDiscover = config and config.autoDiscover ~= false or true
    }
    
    -- Initialize modules
    self:initModules()
    return self
end

--------** Debug Helper **--------
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." Debug] "..str) 
    end
end

--------** Safe Component Access **--------
function DivisibleSpaceController:safeComponentAccess(component, control, action, value)
    local compCtrl = component and component[control]
    if not compCtrl then return false end
    
    local ok, result = pcall(function()
        if action == "set" then 
            compCtrl.Boolean = value
        elseif action == "setPosition" then 
            compCtrl.Position = value
        elseif action == "setString" then 
            compCtrl.String = value
        elseif action == "trigger" then 
            compCtrl:Trigger()
        elseif action == "get" then 
            return compCtrl.Boolean
        elseif action == "getPosition" then 
            return compCtrl.Position
        elseif action == "getString" then 
            return compCtrl.String
        end
        return true
    end)
    
    if not ok then 
        self:debugPrint("Component access error: "..tostring(result)) 
    end
    
    return ok and result
end

--------** Dynamic Component Discovery **--------
function DivisibleSpaceController:discoverComponents()
    self:debugPrint("Starting component discovery...")
    
    -- Reset available components
    self.state.availableRoomCombiners = {}
    self.state.availableUCIPanels = {}
    self.state.availableRoomControls = {}
    
    -- Get all components in one pass for maximum efficiency
    local allComponents = Component.GetComponents()
    
    -- Categorize components by type
    for i, comp in ipairs(allComponents) do
        local compType = comp.Type
        
        -- Room Combiners
        if compType == self.componentTypes.roomCombiner then
            table.insert(self.state.availableRoomCombiners, {
                name = comp.Name,
                component = comp
            })
        -- UCI Panels
        elseif compType == self.componentTypes.uciPanels then
            table.insert(self.state.availableUCIPanels, {
                name = comp.Name,
                component = comp
            })
        -- Room Controls (device_controller_script with roomName or selDefaultConfigs)
          elseif compType == self.componentTypes.roomControls then
            table.insert(self.state.availableRoomControls, {
                name = comp.Name,
                component = comp
            })
        end
    end
    
    -- Auto-select first available components if none selected and auto-discover is enabled
    if self.config.autoDiscover then
        if #self.state.availableRoomCombiners > 0 and not self.state.selectedRoomCombiner then
            self.state.selectedRoomCombiner = self.state.availableRoomCombiners[1].component
            self:debugPrint("Auto-selected Room Combiner: " .. self.state.availableRoomCombiners[1].name)
        end
        
        if #self.state.availableUCIPanels >= 2 and #self.state.selectedUCIPanels == 0 then
            self.state.selectedUCIPanels[1] = self.state.availableUCIPanels[1].component
            self.state.selectedUCIPanels[2] = self.state.availableUCIPanels[2].component
            self:debugPrint("Auto-selected UCI Panels: " .. 
                           self.state.availableUCIPanels[1].name .. ", " .. 
                           self.state.availableUCIPanels[2].name)
        end
    end
    
    self:debugPrint("Discovery complete - Room Combiners: " .. #self.state.availableRoomCombiners .. 
                   ", UCI Panels: " .. #self.state.availableUCIPanels .. 
                   ", Room Controls: " .. #self.state.availableRoomControls)
end

--------** Ultra-Optimized State Update Function **--------
function DivisibleSpaceController:updateSystemState(newState)
    self:debugPrint("Updating system state to: " .. tostring(newState))
    
    -- Immediate state update
    self.state.isCombined = newState
    
    -- Direct button state update (if exists)
    if controls.btnCombine then
        controls.btnCombine.Boolean = newState
    end
    
    -- Direct room combiner update
    if self.state.selectedRoomCombiner and self.state.selectedRoomCombiner.Rooms then
        self.state.selectedRoomCombiner.Rooms.String = newState and "1+2" or "1 2"
        self:debugPrint("Updated Room Combiner to: " .. (newState and "1+2" or "1 2"))
    end
    
    -- Parallel UCI switching for maximum responsiveness
    if #self.state.selectedUCIPanels >= 2 then
        local targetPage = newState and "uciCombined" or "uciRoom"
        Uci.SetUCI(self.state.selectedUCIPanels[1].Name, targetPage)
        Uci.SetUCI(self.state.selectedUCIPanels[2].Name, targetPage)
        self:debugPrint("Updated UCI panels to page: " .. targetPage)
    end
    
    -- Update status
    self:checkStatus()
end

--------** Combo Box Setup **--------
function DivisibleSpaceController:setupComboBoxes()
    -- Room Combiner Selection Combo Box
    if controls.cmbRoomCombiner then
        -- Populate with discovered components
        local items = {self.clearString}
        for i, comp in ipairs(self.state.availableRoomCombiners) do
            table.insert(items, comp.name)
        end
        controls.cmbRoomCombiner.Choices = items
        controls.cmbRoomCombiner.String = items[1]
        
        -- Direct event handler
        controls.cmbRoomCombiner.EventHandler = function(ctl)
            local selection = ctl.String
            if selection ~= self.clearString then
                for i, comp in ipairs(self.state.availableRoomCombiners) do
                    if comp.name == selection then
                        self.state.selectedRoomCombiner = comp.component
                        self:debugPrint("Selected Room Combiner: " .. comp.name)
                        break
                    end
                end
            end
        end
    end
    
    -- UCI Panel Selection Combo Boxes
    if controls.cmbUCIPanel1 and controls.cmbUCIPanel2 then
        local items = {self.clearString}
        for i, comp in ipairs(self.state.availableUCIPanels) do
            table.insert(items, comp.name)
        end
        
        controls.cmbUCIPanel1.Choices = items
        controls.cmbUCIPanel2.Choices = items
        controls.cmbUCIPanel1.String = items[1]
        controls.cmbUCIPanel2.String = items[1]
        
        -- Direct event handlers
        controls.cmbUCIPanel1.EventHandler = function(ctl)
            local selection = ctl.String
            if selection ~= self.clearString then
                for i, comp in ipairs(self.state.availableUCIPanels) do
                    if comp.name == selection then
                        self.state.selectedUCIPanels[1] = comp.component
                        self:debugPrint("Selected UCI Panel 1: " .. comp.name)
                        break
                    end
                end
            end
        end
        
        controls.cmbUCIPanel2.EventHandler = function(ctl)
            local selection = ctl.String
            if selection ~= self.clearString then
                for i, comp in ipairs(self.state.availableUCIPanels) do
                    if comp.name == selection then
                        self.state.selectedUCIPanels[2] = comp.component
                        self:debugPrint("Selected UCI Panel 2: " .. comp.name)
                        break
                    end
                end
            end
        end
    end
end

--------** Event Handler Setup **--------
function DivisibleSpaceController:setupEventHandlers()
    -- Combine Button - Direct, minimal event handler
    if controls.btnCombine then
        controls.btnCombine.EventHandler = function(ctl)
            self:updateSystemState(ctl.Boolean)
        end
    end
    
    -- Partition Sensor - Direct state toggle
    if controls.partitionSensor then
        controls.partitionSensor.EventHandler = function(ctl)
            self:updateSystemState(not ctl.Boolean)
        end
    end
    
    -- Quick Combine/Uncombine buttons for immediate response
    if controls.btnQuickCombine then
        controls.btnQuickCombine.EventHandler = function()
            self:updateSystemState(true)
        end
    end
    
    if controls.btnQuickUncombine then
        controls.btnQuickUncombine.EventHandler = function()
            self:updateSystemState(false)
        end
    end
end

--------** Status Management **--------
function DivisibleSpaceController:checkStatus()
    local status = "OK"
    local hasError = false
    
    -- Check if required components are available
    if #self.state.availableRoomCombiners == 0 then
        status = "No Room Combiners Found"
        hasError = true
    end
    
    if #self.state.availableUCIPanels < 2 then
        status = "Insufficient UCI Panels (" .. #self.state.availableUCIPanels .. "/2)"
        hasError = true
    end
    
    -- Update status control
    if controls.txtStatus then
        controls.txtStatus.String = status
        controls.txtStatus.Value = hasError and 1 or 0
    end
    
    self:debugPrint("Status: " .. status)
end

--------** Initialize Modules **--------
function DivisibleSpaceController:initModules()
    -- Initialize any additional modules here
    self:debugPrint("Modules initialized")
end

--------** External API Methods **--------
function DivisibleSpaceController:SetCombinedRoomState(combined)
    self:updateSystemState(combined)
end

function DivisibleSpaceController:GetCombinedRoomState()
    return self.state.isCombined
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

--------** Initialization **--------
function DivisibleSpaceController:funcInit()
    self:debugPrint("Starting DivisibleSpaceController initialization...")
    
    -- Discover components first
    self:discoverComponents()
    
    -- Setup UI components in parallel
    self:setupComboBoxes()
    self:setupEventHandlers()
    
    -- Set initial state
    self:updateSystemState(false)
    
    -- Optional: Publish initial state
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
    -- Clear event handlers
    if controls.btnCombine then
        controls.btnCombine.EventHandler = nil
    end
    
    if controls.partitionSensor then
        controls.partitionSensor.EventHandler = nil
    end
    
    if controls.btnQuickCombine then
        controls.btnQuickCombine.EventHandler = nil
    end
    
    if controls.btnQuickUncombine then
        controls.btnQuickUncombine.EventHandler = nil
    end
    
    if controls.cmbRoomCombiner then
        controls.cmbRoomCombiner.EventHandler = nil
    end
    
    if controls.cmbUCIPanel1 then
        controls.cmbUCIPanel1.EventHandler = nil
    end
    
    if controls.cmbUCIPanel2 then
        controls.cmbUCIPanel2.EventHandler = nil
    end
    
    -- Reset state
    self.state = {
        isCombined = false,
        selectedRoomCombiner = nil,
        selectedUCIPanels = {},
        selectedRoomControls = {},
        availableRoomCombiners = {},
        availableUCIPanels = {},
        availableRoomControls = {}
    }
    
    if self.debugging then 
        self:debugPrint("Cleanup completed") 
    end
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
myDivisibleSpaceController = createDivisibleSpaceController(formattedRoomName)

if myDivisibleSpaceController then
    print("DivisibleSpaceController created successfully!")
else
    print("ERROR: Failed to create DivisibleSpaceController!")
end

--[[ 
  Class-Based Architecture Benefits:
  
  1. ENCAPSULATION: All related functionality is contained within the class
  2. REUSABILITY: Can create multiple instances for different rooms
  3. MAINTAINABILITY: Clear separation of concerns and organized code structure
  4. DEBUGGING: Enhanced debug output with room-specific context
  5. CONFIGURATION: Flexible configuration options per instance
  6. ERROR HANDLING: Robust error handling with proper cleanup
  7. COMPONENT MANAGEMENT: Centralized component discovery and management
  8. STATE MANAGEMENT: Organized state tracking with clear access methods
  9. EVENT HANDLING: Structured event handler setup and cleanup
  10. EXTERNAL API: Clean interface for external script integration
  
  Usage Notes:
  - Add Combo Box controls (cmbRoomCombiner, cmbUCIPanel1, cmbUCIPanel2) to your UCI
  - Add Quick buttons (btnQuickCombine, btnQuickUncombine) for immediate response
  - System automatically discovers available components on startup
  - Use myDivisibleSpaceController:RefreshComponentDiscovery() to update component list
  - All existing functionality preserved with enhanced organization and debugging
]]
