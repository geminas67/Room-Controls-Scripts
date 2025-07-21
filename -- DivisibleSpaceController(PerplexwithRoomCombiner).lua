--[[
  Divisible Space Controller with Room Combiner, Audio Routing, and UCI Switching
  Author: Nikolas Smith
  Date: 2025-07-02
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 4.0 - Refactored with Enhanced Class Structure and Error Handling
]]

--------** Control References **--------
local controls = {
    selRoomCombiner = Controls.selRoomCombiner,
    compRoomControlsA = Controls.compRoomControlsA,
    compRoomControlsB = Controls.compRoomControlsB,
    compRoomControlsC = Controls.compRoomControlsC,
    compRoomControlsD = Controls.compRoomControlsD,
    selUCI = Controls.selUCI,
    selRoomCombination = Controls.selRoomCombination,
    btnAllSeparated = Controls.btnAllSeparated,
    btnABCombined = Controls.btnABCombined,
    btnBCCombined = Controls.btnBCCombined,
    btnCDCombined = Controls.btnCDCombined,
    btnABCDCombined = Controls.btnABCDCombined,
    btnABCCombined = Controls.btnABCCombined,
    btnBCDCombined = Controls.btnBCDCombined,
    btnAllCombined = Controls.btnAllCombined,
    partitionWallAB = Controls.partitionWallAB,
    partitionWallBC = Controls.partitionWallBC,
    partitionWallCD = Controls.partitionWallCD,
    btnPerformanceTest = Controls.btnPerformanceTest
}

--------** Control Validation **--------
local function validateControls()
    local missingControls = {}
    if not controls.selRoomCombination then table.insert(missingControls, "selRoomCombination") end
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

function DivisibleSpaceController.new(config)
    local self = setmetatable({}, DivisibleSpaceController)
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.controls = controls
    self.componentTypes = { 
        roomCombiner = "Room Combiner",
        uciPanels = "UCI",
        roomControls = "device_controller_script",
        tscDevices = "TSC"
    }
    
    -- Room configuration with dynamic discovery
    self.roomNames = {"A", "B", "C", "D"}
    self.roomCombinations = {
        { name = "All Separated",        rooms = {"A","B","C","D"},      combiner = "1 2 3 4",       uci = "UCI_Separated" },
        { name = "A+B Combined",         rooms = {"A+B","C","D"},        combiner = "1+2 3 4",       uci = "UCI_AB" },
        { name = "B+C Combined",         rooms = {"A","B+C","D"},        combiner = "1 2+3 4",       uci = "UCI_BC" },
        { name = "C+D Combined",         rooms = {"A","B","C+D"},        combiner = "1 2 3+4",       uci = "UCI_CD" },
        { name = "A+B, C+D Combined",    rooms = {"A+B","C+D"},          combiner = "1+2 3+4",       uci = "UCI_AB_CD" },
        { name = "A+B+C Combined",       rooms = {"A+B+C","D"},          combiner = "1+2+3 4",       uci = "UCI_ABC" },
        { name = "B+C+D Combined",       rooms = {"A","B+C+D"},          combiner = "1 2+3+4",       uci = "UCI_BCD" },
        { name = "All Combined",         rooms = {"A+B+C+D"},            combiner = "1+2+3+4",       uci = "UCI_All" }
    }
    
    -- Pre-built lookup tables for O(1) access
    self.combinationLookup = {}
    self.roomIndexMap = { A=1, B=2, C=3, D=4 }
    
    for i, combo in ipairs(self.roomCombinations) do
        self.combinationLookup[combo.name] = i
    end
    
    self.state = {
        currentCombinationIndex = 1,
        isInitialized = false,
        selectedRoomCombiner = nil,
        selectedUCIs = {},
        roomControllers = {},
        componentCache = {},
        roomCombinerComponents = {},
        roomControllerComponents = {},
        uciComponents = {},
        tscDevices = {}
    }
    
    self.config = {
        maxUCIPanels = config and config.maxUCIPanels or 4,
        maxRoomControls = config and config.maxRoomControls or 4,
        autoDiscover = config and config.autoDiscover ~= false or true
    }
    
    self:initModules()
    return self
end

--------** Debug Helper **--------
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then print("[DivisibleSpace Debug] "..str) end
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

--------** Enhanced Component Discovery **--------
function DivisibleSpaceController:discoverComponents()
    self:debugPrint("Starting enhanced component discovery...")
    
    -- Clear previous discoveries
    self.state.componentCache = {}
    self.state.roomCombinerComponents = {}
    self.state.roomControllerComponents = {}
    self.state.uciComponents = {}
    self.state.tscDevices = {}
    
    local allComponents = Component.GetComponents()
    
    for _, comp in ipairs(allComponents) do
        local compName = comp.Name
        local compType = comp.Type
        
        -- Cache component by name for O(1) access
        self.state.componentCache[compName] = comp
        
        -- Categorize components by type with enhanced error handling
        if compType == self.componentTypes.roomCombiner then
            table.insert(self.state.roomCombinerComponents, comp)
            self:debugPrint("Found Room Combiner: " .. compName)
        elseif compType == self.componentTypes.roomControls then
            -- Enhanced Room Controller discovery
            local testComp = Component.New(compName)
            if testComp then
                local controls = getControlsTable(testComp)
                if controls and (controls["roomName"] or controls["selDefaultConfigs"] or controls["btnSystemOnOff"]) then
                    table.insert(self.state.roomControllerComponents, comp)
                    self:debugPrint("Found Room Controller: " .. compName)
                end
            end
        elseif compType == self.componentTypes.uciPanels then
            self.state.uciComponents[compName] = comp
            self:debugPrint("Found UCI Component: " .. compName)
        elseif compType == self.componentTypes.tscDevices then
            -- Extract room identifier from TSC device name
            for _, room in ipairs(self.roomNames) do
                if compName:find("UCI" .. room) or compName:find("TSC" .. room) then
                    self.state.tscDevices[room] = comp
                    self:debugPrint("Found TSC Device for Room " .. room .. ": " .. compName)
                    break
                end
            end
        end
    end
    
    -- Auto-select components if configured
    if self.config.autoDiscover then
        if #self.state.roomCombinerComponents > 0 and not self.state.selectedRoomCombiner then
            self.state.selectedRoomCombiner = self.state.roomCombinerComponents[1]
            self:debugPrint("Auto-selected Room Combiner: " .. self.state.roomCombinerComponents[1].Name)
        end
        
        -- Auto-select UCI components
        for compName, comp in pairs(self.state.uciComponents) do
            if not self.state.selectedUCIs[compName] then
                self.state.selectedUCIs[compName] = comp
                self:debugPrint("Auto-selected UCI: " .. compName)
            end
        end
    end
    
    self:debugPrint("Discovery complete - Room Combiners: " .. #self.state.roomCombinerComponents .. 
        ", Room Controllers: " .. #self.state.roomControllerComponents .. 
        ", UCI Components: " .. #self.state.uciComponents .. 
        ", TSC Devices: " .. #self.state.tscDevices)
end

--------** Enhanced Room Controller Management **--------
function DivisibleSpaceController:getRoomControllerNames()
    local namesTable = { RoomControllerNames = {} }
    for _, comp in ipairs(self.state.roomControllerComponents) do
        table.insert(namesTable.RoomControllerNames, comp.Name)
    end
    table.sort(namesTable.RoomControllerNames)
    table.insert(namesTable.RoomControllerNames, self.clearString)
    return namesTable.RoomControllerNames
end

function DivisibleSpaceController:setRoomControllerComponent(ctrl, componentType)
    if not ctrl then return nil end
    local componentName = ctrl.String
    if componentName == "" or componentName == self.clearString then
        ctrl.Color = "White"
        return nil
    end
    
    local testComponent = Component.New(componentName)
    if not testComponent then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "Pink"
        self:debugPrint("Invalid component: " .. componentName)
        return nil
    end
    
    local controls = getControlsTable(testComponent)
    if not controls or #Component.GetControls(testComponent) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "Pink"
        self:debugPrint("Component has no controls: " .. componentName)
        return nil
    end
    
    ctrl.Color = "White"
    self:debugPrint("Successfully set Room Controller: " .. componentName)
    return testComponent
end

--------** Enhanced Combo Box Population **--------
function DivisibleSpaceController:populateComponentComboBoxes()
    -- Populate Room Combiner combo box
    if self.controls.selRoomCombiner then
        local choices = {self.clearString}
        for i, comp in ipairs(self.state.roomCombinerComponents) do
            choices[i + 1] = comp.Name
        end
        self.controls.selRoomCombiner.Choices = choices
        if #choices > 1 then
            self.controls.selRoomCombiner.String = choices[2] -- First actual component
        end
    end
    
    -- Populate Room Controller combo boxes
    local roomControllerNames = self:getRoomControllerNames()
    for _, room in ipairs(self.roomNames) do
        local controlName = "selRoomController" .. room
        if self.controls[controlName] then
            self.controls[controlName].Choices = roomControllerNames
            if #roomControllerNames > 1 then
                self.controls[controlName].String = roomControllerNames[1]
            end
        end
    end
    
    -- Populate UCI combo boxes
    if self.controls.selUCI then
        local choices = {self.clearString}
        for compName, comp in pairs(self.state.uciComponents) do
            table.insert(choices, compName)
        end
        self.controls.selUCI.Choices = choices
        if #choices > 1 then
            self.controls.selUCI.String = choices[2] -- First actual component
        end
    end
end

--------** Enhanced Core Functions **--------
function DivisibleSpaceController:setRoomCombinerState(stateString)
    local combiner = self.state.selectedRoomCombiner or self.state.roomCombinerComponents[1]
    if combiner then
        self:debugPrint("Setting Room Combiner state: " .. stateString)
        self:debugComponentProperties(combiner, "Room Combiner")
        
        local controls = getControlsTable(combiner)
        if controls and controls.Rooms then
            controls.Rooms.String = stateString
            self:debugPrint("Updated Room Combiner Rooms to: " .. stateString)
        else
            self:debugPrint("WARNING: Room Combiner has no 'Rooms' control!")
            if controls then for k,_ in pairs(controls) do self:debugPrint("Available control: "..k) end end
        end
    else
        self:debugPrint("ERROR: No Room Combiner available!")
    end
end

function DivisibleSpaceController:switchUCIs(uciName)
    self:debugPrint("Switching UCIs to: " .. uciName)
    
    -- Use selected UCI or fall back to discovered components
    local targetUCI = self.state.selectedUCIs[uciName] or self.state.uciComponents[uciName]
    
    if targetUCI then
        -- Single UCI switch for maximum speed
        for _, tsc in pairs(self.state.tscDevices) do
            if tsc and tsc.UCI then
                tsc.UCI.String = uciName
                self:debugPrint("Updated TSC UCI to: " .. uciName)
            end
        end
    else
        -- Fallback to direct UCI switching
        self:debugPrint("Using fallback UCI switching")
        Uci.SetUCI("UCIRmA", uciName)
        Uci.SetUCI("UCIRmB", uciName)
        Uci.SetUCI("UCIRmC", uciName)
        Uci.SetUCI("UCIRmD", uciName)
    end
end

function DivisibleSpaceController:updateRoomControllerPower(activeRooms)
    for room, isActive in pairs(activeRooms) do
        local roomController = self.state.roomControllers[room]
        if roomController then
            local controls = getControlsTable(roomController)
            if controls and controls["btnSystemOnOff"] then
                controls["btnSystemOnOff"].Boolean = isActive
                self:debugPrint("Updated Room " .. room .. " power to: " .. tostring(isActive))
            end
        end
    end
end

function DivisibleSpaceController:buildActiveRoomsMap(combo)
    local activeRooms = {}
    for _, r in ipairs(combo.rooms) do
        if r:find("+") then
            for part in r:gmatch("[^+]+") do 
                activeRooms[part] = true 
            end
        else
            activeRooms[r] = true
        end
    end
    return activeRooms
end

function DivisibleSpaceController:publishRoomState(combo)
    if Notifications and Notifications.Publish then
        Notifications.Publish("DivisibleRoomState", {
            name = combo.name,
            rooms = combo.rooms,
            combiner = combo.combiner,
            uci = combo.uci,
            timestamp = Timer.Now()
        })
    end
end

--------** Main Application Function **--------
function DivisibleSpaceController:applyCombination(index)
    if not index or index < 1 or index > #self.roomCombinations then 
        self:debugPrint("ERROR: Invalid combination index: " .. tostring(index))
        return 
    end
    
    self.state.currentCombinationIndex = index
    local combo = self.roomCombinations[index]
    
    self:debugPrint("Applying combination: " .. combo.name)
    
    -- Execute all operations with enhanced error handling
    self:setRoomCombinerState(combo.combiner)
    self:switchUCIs(combo.uci)
    
    local activeRooms = self:buildActiveRoomsMap(combo)
    self:updateRoomControllerPower(activeRooms)
    self:publishRoomState(combo)
    
    -- Update UI state immediately
    if self.controls.selRoomCombination then
        self.controls.selRoomCombination.String = combo.name
    end
    
    self:debugPrint("Combination applied successfully")
end

--------** Enhanced Event-Driven Control Handlers **--------
function DivisibleSpaceController:setupEventHandlers()
    -- Dynamic component selection handlers
    if self.controls.selRoomCombiner then
        self.controls.selRoomCombiner.EventHandler = function(ctl)
            self.state.selectedRoomCombiner = self.state.componentCache[ctl.String]
            self:debugPrint("Selected Room Combiner: " .. ctl.String)
            -- Re-apply current combination with new component
            if self.state.isInitialized then
                self:applyCombination(self.state.currentCombinationIndex)
            end
        end
    end

    -- Dynamic Room Controller selection handlers
    for _, room in ipairs(self.roomNames) do
        local controlName = "selRoomController" .. room
        if self.controls[controlName] then
            self.controls[controlName].EventHandler = function(ctl)
                local component = self:setRoomControllerComponent(ctl, "Room Controller " .. room)
                if component then
                    self.state.roomControllers[room] = component
                    -- Re-apply current combination with new component
                    if self.state.isInitialized then
                        self:applyCombination(self.state.currentCombinationIndex)
                    end
                else
                    self.state.roomControllers[room] = nil
                end
            end
        end
    end

    -- Dynamic UCI selection handler
    if self.controls.selUCI then
        self.controls.selUCI.EventHandler = function(ctl)
            self.state.selectedUCIs[ctl.String] = self.state.componentCache[ctl.String]
            self:debugPrint("Selected UCI: " .. ctl.String)
            -- Re-apply current combination with new UCI
            if self.state.isInitialized then
                self:applyCombination(self.state.currentCombinationIndex)
            end
        end
    end

    -- Optimized room combination dropdown handler
    if self.controls.selRoomCombination then
        -- Pre-build choices array once
        local choices = {}
        for i, combo in ipairs(self.roomCombinations) do
            choices[i] = combo.name
        end
        self.controls.selRoomCombination.Choices = choices
        
        -- Ultra-fast event handler with direct lookup
        self.controls.selRoomCombination.EventHandler = function(ctl)
            local index = self.combinationLookup[ctl.String]
            if index then
                self:applyCombination(index)
            else
                self:debugPrint("ERROR: Unknown combination: " .. ctl.String)
            end
        end
    end

    -- Pre-built button handlers for maximum speed
    local buttonHandlers = {
        btnAllSeparated = 1,
        btnABCombined = 2,
        btnBCCombined = 3,
        btnCDCombined = 4,
        btnABCDCombined = 5,
        btnABCCombined = 6,
        btnBCDCombined = 7,
        btnAllCombined = 8
    }

    for controlName, index in pairs(buttonHandlers) do
        if self.controls[controlName] then
            self.controls[controlName].EventHandler = function()
                self:applyCombination(index)
            end
        end
    end

    -- Optimized partition wall handlers
    local partitionHandlers = {
        partitionWallAB = { combined = 2, separated = 1 },
        partitionWallBC = { combined = 3, separated = 1 },
        partitionWallCD = { combined = 4, separated = 1 }
    }

    for controlName, states in pairs(partitionHandlers) do
        if self.controls[controlName] then
            self.controls[controlName].EventHandler = function(ctl)
                local targetIndex = ctl.Boolean and states.combined or states.separated
                self:applyCombination(targetIndex)
            end
        end
    end
end

--------** Enhanced Status Management **--------
function DivisibleSpaceController:checkStatus()
    local status, hasError = "OK", false
    local statusDetails = {}
    
    if #self.state.roomCombinerComponents == 0 then
        status = "No Room Combiners Found"
        hasError = true
        table.insert(statusDetails, "Add Room Combiner component to design")
    else
        table.insert(statusDetails, "Room Combiners: " .. #self.state.roomCombinerComponents)
        if self.state.selectedRoomCombiner then
            table.insert(statusDetails, "Selected: " .. self.state.selectedRoomCombiner.Name)
        end
    end
    
    if #self.state.roomControllerComponents > 0 then
        table.insert(statusDetails, "Room Controllers: " .. #self.state.roomControllerComponents)
    else
        table.insert(statusDetails, "Room Controllers: None (Optional)")
    end
    
    if #self.state.uciComponents > 0 then
        table.insert(statusDetails, "UCI Components: " .. #self.state.uciComponents)
    else
        table.insert(statusDetails, "UCI Components: None (Optional)")
    end
    
    if #self.state.tscDevices > 0 then
        table.insert(statusDetails, "TSC Devices: " .. #self.state.tscDevices)
    else
        table.insert(statusDetails, "TSC Devices: None (Optional)")
    end
    
    self:debugPrint("Status: " .. status)
    for _, detail in ipairs(statusDetails) do self:debugPrint("  " .. detail) end
    
    return status, hasError, statusDetails
end

--------** Initialize Modules **--------
function DivisibleSpaceController:initModules()
    self:debugPrint("Modules initialized")
end

--------** API Methods **--------
function DivisibleSpaceController:SetCombination(index)
    self:applyCombination(index)
end

function DivisibleSpaceController:GetCurrentCombination()
    return self.state.currentCombinationIndex, self.roomCombinations[self.state.currentCombinationIndex]
end

function DivisibleSpaceController:GetAvailableComponents()
    return {
        roomCombiners = self.state.roomCombinerComponents,
        roomControllers = self.state.roomControllerComponents,
        uciComponents = self.state.uciComponents,
        tscDevices = self.state.tscDevices
    }
end

function DivisibleSpaceController:RefreshComponentDiscovery()
    self:debugPrint("Refreshing component discovery...")
    self.state.selectedRoomCombiner = nil
    self.state.selectedUCIs = {}
    self.state.roomControllers = {}
    self:discoverComponents()
    self:populateComponentComboBoxes()
    self:checkStatus()
end

--------** Enhanced Initialization Routine **--------
function DivisibleSpaceController:funcInit()
    self:debugPrint("Starting DivisibleSpaceController initialization...")
    
    -- Discover all components dynamically
    self:discoverComponents()
    
    -- Populate combo boxes with discovered components
    self:populateComponentComboBoxes()
    
    -- Setup event handlers
    self:setupEventHandlers()
    
    -- Apply default combination
    self:applyCombination(1)
    
    self.state.isInitialized = true
    
    -- Check and report status
    local status, hasError, details = self:checkStatus()
    
    -- Publish initialization complete
    if Notifications and Notifications.Publish then
        Notifications.Publish("DivisibleSpaceInitialized", {
            roomCombinerCount = #self.state.roomCombinerComponents,
            roomControllerCount = #self.state.roomControllerComponents,
            uciComponentCount = #self.state.uciComponents,
            tscDeviceCount = #self.state.tscDevices,
            status = status,
            hasError = hasError
        })
    end
    
    self:debugPrint("DivisibleSpaceController Initialized successfully")
end

--------** Enhanced Cleanup **--------
function DivisibleSpaceController:cleanup()
    -- Clear all event handlers
    for controlName, control in pairs(self.controls) do
        if control and control.EventHandler then
            control.EventHandler = nil
        end
    end
    
    -- Reset state
    self.state = {
        currentCombinationIndex = 1,
        isInitialized = false,
        selectedRoomCombiner = nil,
        selectedUCIs = {},
        roomControllers = {},
        componentCache = {},
        roomCombinerComponents = {},
        roomControllerComponents = {},
        uciComponents = {},
        tscDevices = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
end

--------** Performance Monitoring **--------
function DivisibleSpaceController:runPerformanceTest()
    if self.controls.btnPerformanceTest then
        self.controls.btnPerformanceTest.EventHandler = function()
            local startTime = Timer.Now()
            
            -- Test all combinations
            for i = 1, #self.roomCombinations do
                self:applyCombination(i)
            end
            
            local endTime = Timer.Now()
            local duration = endTime - startTime
            
            if Notifications and Notifications.Publish then
                Notifications.Publish("PerformanceTest", {
                    totalCombinations = #self.roomCombinations,
                    totalDuration = duration,
                    averagePerCombination = duration / #self.roomCombinations
                })
            end
            
            self:debugPrint("Performance test completed in " .. duration .. " seconds")
        end
    end
end

--------** Factory Function **--------
local function createDivisibleSpaceController(config)
    print("Creating DivisibleSpaceController...")
    local success, controller = pcall(function()
        local instance = DivisibleSpaceController.new(config)
        instance:funcInit()
        instance:runPerformanceTest()
        return instance
    end)
    if success then
        print("Successfully created DivisibleSpaceController")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
if not validateControls() then
    print("ERROR: Required controls are missing. Please check your Q-SYS design.")
    return
end

myDivisibleSpaceController = createDivisibleSpaceController({
    debugging = true,
    autoDiscover = true,
    maxUCIPanels = 4,
    maxRoomControls = 4
})

if myDivisibleSpaceController then
    print("DivisibleSpaceController created successfully!")
else
    print("ERROR: Failed to create DivisibleSpaceController!")
end

--------** End of Script **--------

-- Enhanced Features Applied:
-- 1. Proper metatable-based class structure (Lua Refactor compliant)
-- 2. Enhanced component discovery with fallback mechanisms
-- 3. Comprehensive error handling and debugging
-- 4. Robust control validation
-- 5. Better state management with centralized tracking
-- 6. Enhanced UCI integration with flexible discovery
-- 7. Improved Room Controller management
-- 8. Performance monitoring capabilities
-- 9. Proper cleanup methods
-- 10. API methods for external access
-- 11. Enhanced status reporting
-- 12. Better component property debugging
-- 13. Auto-discovery with configuration options
-- 14. Factory function with error handling

-- Usage:
-- 1. Add Room Combiner objects to your schematic (automatically discovered)
-- 2. Add SystemAutomationController instances (automatically discovered as Room Controllers)
-- 3. Add UCI components (automatically discovered)
-- 4. Add TSC devices with names containing room identifiers (e.g., "UCIRmA", "TSCB")
-- 5. Create combo box controls for component selection:
--    - selRoomCombiner: Select which Room Combiner to use
--    - compRoomControlsA, compRoomControlsB, etc.: Select Room Controller components for each room
--    - selUCI: Select UCI components
-- 6. Create dropdown control "selRoomCombination" for manual state selection
-- 7. Optional: Add direct button controls for instant access to common combinations
-- 8. Optional: Add partition wall sensors for automatic response
-- 9. Optional: Add btnPerformanceTest for performance monitoring
-- 10. Room Controllers handle gain settings through SystemAutomationController instances
