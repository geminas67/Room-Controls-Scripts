--[[
  Extron DXP Matrix Routing Controller - Refactored
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-01-27
  Firmware Req: 10.0.0
  Version: 2.0

  Performance-optimized class-based implementation with UCI integration
  - Eliminates redundant function calls and timers
  - Direct routing and state management
  - UCI integration for automatic input switching
  - Component discovery using Component.GetComponents()
  - HIDCallSync integration
]]--

-- Define control references
local controls = {
    txtDestination = Controls['Text-Destination'],
    btnAVMute = Controls['AV Mute BTN'],
    btnDestClickShare = Controls['Destination Selector - ClickShare'],
    btnDestTeamsPC = Controls['Destination Selector - Teams PC'],
    btnDestLaptopFront = Controls['Destination Selector - Laptop Front'],
    btnDestLaptopRear = Controls['Destination Selector - Laptop Rear'],
    btnDestNoSource = Controls['Destination Selector - No Source'],
    btnDestAllDisplays = Controls['Destination - All Displays'],
    btnExtronSignalPresence = Controls['Extron DXP Signal Presence'],
}

-- ExtronDXPController class
ExtronDXPController = {}
ExtronDXPController.__index = ExtronDXPController

--------** Class Constructor **--------
function ExtronDXPController.new()
    local self = setmetatable({}, ExtronDXPController)
    
    -- Instance properties
    self.debugging = true
    self.clearString = "[Clear]"
    self.invalidComponents = {}
    
    -- UCI Integration properties
    self.uciIntegrationEnabled = true
    self.lastUCILayer = nil
    
    -- Input/Output mapping
    self.inputs = {
        ClickShare = 1,
        TeamsPC = 2,
        LaptopFront = 4,
        LaptopRear = 5,
        NoSource = 0
    }
    
    self.outputs = {
        MON01 = 1,
        MON02 = 2,
        MON03 = 3,
        MON04 = 4
    }
    
    -- UCI Layer to Input mapping
    self.uciLayerToInput = {
        [7] = self.inputs.TeamsPC,    -- btnNav07.Boolean = PC
        [8] = self.inputs.LaptopFront, -- btnNav08.Boolean = Laptop
        [9] = self.inputs.ClickShare,  -- btnNav09.Boolean = WPres
    }
    
    -- Source priority mapping (for auto-switching)
    self.sourcePriority = {
        {name = "TeamsPC", input = self.inputs.TeamsPC, checkFunc = function() 
            return HIDCallSync["off.hook"].Boolean or self.extronRouter["Extron DXP Signal Presence 3"].Boolean 
        end},
        {name = "LaptopFront", input = self.inputs.LaptopFront, checkFunc = function() 
            return self.extronRouter["Extron DXP Signal Presence 4"].Boolean 
        end},
        {name = "LaptopRear", input = self.inputs.LaptopRear, checkFunc = function() 
            return self.extronRouter["Extron DXP Signal Presence 5"].Boolean 
        end},
        {name = "ClickShare", input = self.inputs.ClickShare, checkFunc = function() 
            return self.extronRouter["Extron DXP Signal Presence 1"].Boolean 
        end},
        {name = "TeamsPC2", input = self.inputs.TeamsPC, checkFunc = function() 
            return self.extronRouter["Extron DXP Signal Presence 2"].Boolean 
        end}
    }
    
    -- Instance-specific control references
    self.controls = controls
    
    -- Component storage
    self.extronRouter = nil
    self.roomControls = nil
    self.uciLayerSelector = nil
    self.statusBar = nil
    self.hidConferencing = nil
    
    -- Current state
    self.currentSource = nil
    self.currentDestinations = {}
    self.systemPowered = false
    self.systemWarming = true
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** Debug Helper **--------
function ExtronDXPController:debugPrint(str)
    if self.debugging then
        print("[Extron DXP Debug] " .. str)
    end
end

--------** Component Discovery **--------
function ExtronDXPController:discoverComponents()
    local components = Component.GetComponents()
    local discovered = {
        ExtronDXPNames = {},
        ClickShareNames = {},
        RoomControlsNames = {}
    }
    
    for _, v in pairs(components) do
        if v.Type == "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff)" then
            table.insert(discovered.ExtronDXPNames, v.Name)
        elseif v.Type == "call_sync" then
            table.insert(discovered.ClickShareNames, v.Name)
        elseif v.Type == "device_controller_script" and string.match(v.Name, "^compRoomControls") then
            table.insert(discovered.RoomControlsNames, v.Name)
        end
    end
    
    return discovered
end

--------** Component Setup **--------
function ExtronDXPController:setupComponents()
    local discovered = self:discoverComponents()
    
    -- Setup Extron DXP Router
    if #discovered.ExtronDXPNames > 0 then
        self.extronRouter = Component.New(discovered.ExtronDXPNames[1])
        self:debugPrint("Extron DXP Router set: " .. discovered.ExtronDXPNames[1])
    end
    
    -- Setup Room Controls
    if #discovered.RoomControlsNames > 0 then
        self.roomControls = Component.New(discovered.RoomControlsNames[1])
        self:debugPrint("Room Controls set: " .. discovered.RoomControlsNames[1])
    end
    
    -- Setup other components
    self.uciLayerSelector = Component.New('BDRM-UCI Layer Selector')
    self.statusBar = Component.New('BDRM Status Bar')
    self.hidConferencing = Component.New('HID Conferencing IOB-01')
end

--------** UCI Integration Methods **--------
function ExtronDXPController:setupUCIButtonMonitoring()
    -- Monitor UCI navigation buttons directly
    local uciButtons = {
        [7] = Controls.btnNav07,
        [8] = Controls.btnNav08,
        [9] = Controls.btnNav09
    }
    
    for layer, button in pairs(uciButtons) do
        if button then
            button.EventHandler = function(ctl)
                if ctl.Boolean and self.uciLayerToInput[layer] then
                    local targetInput = self.uciLayerToInput[layer]
                    self:debugPrint("UCI Button " .. layer .. " pressed, switching to input " .. targetInput)
                    self:setSource(targetInput)
                end
            end
            self:debugPrint("Direct monitoring set up for UCI button " .. layer)
        end
    end
end

--------** Routing Methods **--------
function ExtronDXPController:setSource(input)
    if not self.extronRouter then return end
    
    self.currentSource = input
    self:debugPrint("Setting source to input " .. input)
    
    -- Clear all destination feedback before updating
    self:clearAllDestinationFeedback()
    
    -- Update all active destinations
    for output, active in pairs(self.currentDestinations) do
        if active then
            self.extronRouter['output_' .. output].String = tostring(input)
        end
    end
    
    -- Update destination feedback
    self:updateDestinationFeedback()
    
    -- Update text destination
    self:updateDestinationText()
end

function ExtronDXPController:setDestination(output, active)
    if not self.extronRouter then return end
    
    self.currentDestinations[output] = active
    
    if active then
        -- Route current source to this destination
        if self.currentSource then
            self.extronRouter['output_' .. output].String = tostring(self.currentSource)
        end
    else
        -- Clear this destination
        self.extronRouter['output_' .. output].String = '0'
    end
    
    -- Update destination feedback
    self:updateDestinationFeedback()
    
    -- Update text destination
    self:updateDestinationText()
end

function ExtronDXPController:clearAllDestinations()
    for output = 1, 4 do
        self.currentDestinations[output] = false
        if self.extronRouter then
            self.extronRouter['output_' .. output].String = '0'
        end
    end
    
    -- Clear all destination feedback
    for i = 1, 5 do
        self.controls.btnDestAllDisplays[i].Boolean = false
    end
    
    -- Clear all source destination feedback buttons
    self:clearAllDestinationFeedback()
end

function ExtronDXPController:clearAllDestinationFeedback()
    -- Clear all destination feedback buttons for all sources
    for i = 1, 4 do
        self.controls.btnDestClickShare[i].Boolean = false
        self.controls.btnDestTeamsPC[i].Boolean = false
        self.controls.btnDestLaptopFront[i].Boolean = false
        self.controls.btnDestLaptopRear[i].Boolean = false
        self.controls.btnDestNoSource[i].Boolean = false
    end
end

function ExtronDXPController:updateDestinationFeedback()
    -- Update destination feedback based on current source and destinations
    -- All sources (including No Source) use the same destination feedback buttons
    for i = 1, 4 do
        local isActive = self.currentDestinations[i] or false
        -- Use the appropriate destination feedback button based on current source
        if self.currentSource == self.inputs.ClickShare then
            self.controls.btnDestClickShare[i].Boolean = isActive
        elseif self.currentSource == self.inputs.TeamsPC then
            self.controls.btnDestTeamsPC[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopFront then
            self.controls.btnDestLaptopFront[i].Boolean = isActive
        elseif self.currentSource == self.inputs.LaptopRear then
            self.controls.btnDestLaptopRear[i].Boolean = isActive
        elseif self.currentSource == self.inputs.NoSource then
            self.controls.btnDestNoSource[i].Boolean = isActive
        end
    end
end

function ExtronDXPController:updateDestinationText()
    local destinationNames = {
        [1] = "Front Left",
        [2] = "Front Right", 
        [3] = "Rear Left",
        [4] = "Rear Right"
    }
    
    local activeCount = 0
    local activeDestinations = {}
    
    for output, active in pairs(self.currentDestinations) do
        if active then
            activeCount = activeCount + 1
            table.insert(activeDestinations, destinationNames[output])
        end
    end
    
    if activeCount == 0 then
        self.controls.txtDestination.String = ""
    elseif activeCount == 1 then
        self.controls.txtDestination.String = activeDestinations[1]
    elseif activeCount == 4 then
        self.controls.txtDestination.String = "All Displays"
        -- Clear text after 3 seconds
        Timer.CallAfter(function()
            self.controls.txtDestination.String = ""
        end, 3)
    else
        self.controls.txtDestination.String = table.concat(activeDestinations, ", ")
    end
end

--------** Auto-Switching Methods **--------
function ExtronDXPController:checkAutoSwitch()
    if not self.systemPowered or self.systemWarming then
        return
    end
    
    -- Check sources in priority order
    for _, source in ipairs(self.sourcePriority) do
        if source.checkFunc() then
            if self.currentSource ~= source.input then
                self:debugPrint("Auto-switching to " .. source.name)
                self:setSource(source.input)
            end
            return
        end
    end
end

function ExtronDXPController:setupAutoSwitchMonitoring()
    -- Monitor system power state
    if self.roomControls then
        self.roomControls["ledSystemPower"].EventHandler = function(ctl)
            self.systemPowered = ctl.Boolean
            self:debugPrint("System power state: " .. tostring(self.systemPowered))
            if self.systemPowered then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor system warming state
    if self.roomControls then
        self.roomControls["ledSystemWarming"].EventHandler = function(ctl)
            self.systemWarming = ctl.Boolean
            self:debugPrint("System warming state: " .. tostring(self.systemWarming))
            if not self.systemWarming and self.systemPowered then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor HID off-hook state
    if self.hidConferencing then
        self.hidConferencing["spk_led_off_hook"].EventHandler = function(ctl)
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- Monitor Extron signal presence
    if self.extronRouter then
        for i = 1, 5 do
            local signalControl = self.extronRouter["Extron DXP Signal Presence " .. i]
            if signalControl then
                signalControl.EventHandler = function(ctl)
                    if self.systemPowered and not self.systemWarming then
                        self:checkAutoSwitch()
                    end
                end
            end
        end
    end
end

--------** Event Handler Registration **--------
function ExtronDXPController:registerEventHandlers()
    -- ClickShare destination selectors
    for i = 1, 5 do
        self.controls.btnDestClickShare[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.ClickShare)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.ClickShare)
                self.controls.btnDestAllDisplays[1].Boolean = true
            end
        end
    end
    
    -- Teams PC destination selectors
    for i = 1, 5 do
        self.controls.btnDestTeamsPC[i].EventHandler = function()
            self:clearAllDestinations()
            if i == 1 then
                -- Front displays
                self:setDestination(1, true)
                self:setDestination(2, true)
                self:setSource(self.inputs.TeamsPC)
            elseif i == 3 then
                -- Rear displays
                self:setDestination(3, true)
                self:setDestination(4, true)
                self:setSource(self.inputs.TeamsPC)
            elseif i == 5 then
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.TeamsPC)
                self.controls.btnDestAllDisplays[2].Boolean = true
            end
        end
    end
    
    -- Laptop Front destination selectors
    for i = 1, 5 do
        self.controls.btnDestLaptopFront[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.LaptopFront)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.LaptopFront)
                self.controls.btnDestAllDisplays[3].Boolean = true
            end
        end
    end
    
    -- Laptop Rear destination selectors
    for i = 1, 5 do
        self.controls.btnDestLaptopRear[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.LaptopRear)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.LaptopRear)
                self.controls.btnDestAllDisplays[4].Boolean = true
            end
        end
    end
    
    -- No Source destination selectors
    for i = 1, 5 do
        self.controls.btnDestNoSource[i].EventHandler = function()
            self:clearAllDestinations()
            if i <= 4 then
                self:setDestination(i, true)
                self:setSource(self.inputs.NoSource)
            else
                -- All displays
                for output = 1, 4 do
                    self:setDestination(output, true)
                end
                self:setSource(self.inputs.NoSource)
                self.controls.btnDestAllDisplays[5].Boolean = true
            end
        end
    end
    
    -- Extron DXP Signal Presence handlers
    for i = 1, 5 do
        self.controls.btnExtronSignalPresence[i].EventHandler = function()
            if self.systemPowered and not self.systemWarming then
                self:checkAutoSwitch()
            end
        end
    end
    
    -- UCI Layer Selector (disable Teams PC buttons for Mon-02 and Mon-04)
    if self.uciLayerSelector then
        self.uciLayerSelector['selector'].EventHandler = function(ctl)
            self.controls.btnDestTeamsPC[2].Color = '#ff6666'
            self.controls.btnDestTeamsPC[4].Color = '#ff6666'
            self.controls.btnDestTeamsPC[2].Legend = 'N/A'
            self.controls.btnDestTeamsPC[4].Legend = 'N/A'
        end
    end
end

--------** Initialization **--------
function ExtronDXPController:funcInit()
    self:debugPrint("Initializing Extron DXP Controller")
    
    -- Setup components
    self:setupComponents()
    
    -- Setup UCI integration
    if self.uciIntegrationEnabled then
        self:setupUCIButtonMonitoring()
    end
    
    -- Setup auto-switching
    self:setupAutoSwitchMonitoring()
    
    -- Initialize system state
    if self.roomControls then
        self.systemPowered = self.roomControls["ledSystemPower"].Boolean
        self.systemWarming = self.roomControls["ledSystemWarming"].Boolean
    end
    
    -- Initialize with no source
    self:setSource(self.inputs.NoSource)
    
    self:debugPrint("Extron DXP Controller initialization complete")
end

--------** Public Interface **--------
function ExtronDXPController:enableUCIIntegration()
    self.uciIntegrationEnabled = true
    self:setupUCIButtonMonitoring()
    self:debugPrint("UCI Integration enabled")
end

function ExtronDXPController:disableUCIIntegration()
    self.uciIntegrationEnabled = false
    self:debugPrint("UCI Integration disabled")
end

function ExtronDXPController:getStatus()
    local status = {
        systemPowered = self.systemPowered,
        systemWarming = self.systemWarming,
        currentSource = self.currentSource,
        currentDestinations = self.currentDestinations,
        componentsValid = (self.extronRouter ~= nil and self.roomControls ~= nil)
    }
    return status
end

-- Create and return the controller instance
local extronDXPController = ExtronDXPController.new()

-- Export for external access
_G.ExtronDXPController = extronDXPController 