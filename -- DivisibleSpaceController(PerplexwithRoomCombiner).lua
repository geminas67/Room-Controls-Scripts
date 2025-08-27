--[[
  Divisible Space Controller with Room Combiner, Audio Routing, and UCI Switching
  Author: Nikolas Smith
  Date: 2025-08-16
  Q-SYS Firmware Requirement: 10.0.0+
  Version: 5.0 - Performance-Optimized with Event-Driven Architecture
]]

-----------------------------[ Control References ]-----------------------------
local controls = {
    selRoomCombiner = Controls.selRoomCombiner,
    compRoomControlsA = Controls.compRoomControlsA,
    compRoomControlsB = Controls.compRoomControlsB,
    compRoomControlsC = Controls.compRoomControlsC,
    compRoomControlsD = Controls.compRoomControlsD,
    compRoomControlsE = Controls.compRoomControlsE,
    compRoomControlsF = Controls.compRoomControlsF,
    compRoomControlsG = Controls.compRoomControlsG,
    compRoomControlsH = Controls.compRoomControlsH,
    selRoomControllerA = Controls.selRoomControllerA,
    selRoomControllerB = Controls.selRoomControllerB,
    selRoomControllerC = Controls.selRoomControllerC,
    selRoomControllerD = Controls.selRoomControllerD,
    selRoomControllerE = Controls.selRoomControllerE,
    selRoomControllerF = Controls.selRoomControllerF,
    selRoomControllerG = Controls.selRoomControllerG,
    selRoomControllerH = Controls.selRoomControllerH,
    selAudioRouterA = Controls.selAudioRouterA,
    selAudioRouterB = Controls.selAudioRouterB,
    selAudioRouterC = Controls.selAudioRouterC,
    selAudioRouterD = Controls.selAudioRouterD,
    selAudioRouterE = Controls.selAudioRouterE,
    selAudioRouterF = Controls.selAudioRouterF,
    selAudioRouterG = Controls.selAudioRouterG,
    selAudioRouterH = Controls.selAudioRouterH,
    selUCI = Controls.selUCI,
    selRoomCombination = Controls.selRoomCombination,
    btnAllSeparated = Controls.btnAllSeparated,
    btnABCombined = Controls.btnABCombined,
    btnBCCombined = Controls.btnBCCombined,
    btnCDCombined = Controls.btnCDCombined,
    btnDECombined = Controls.btnDECombined,
    btnEFCombined = Controls.btnEFCombined,
    btnFGCombined = Controls.btnFGCombined,
    btnGHCombined = Controls.btnGHCombined,
    btnABCDCombined = Controls.btnABCDCombined,
    btnEFGHCombined = Controls.btnEFGHCombined,
    btnABCDEFCombined = Controls.btnABCDEFCombined,
    btnAllCombined = Controls.btnAllCombined,
    partitionWallAB = Controls.partitionWallAB,
    partitionWallBC = Controls.partitionWallBC,
    partitionWallCD = Controls.partitionWallCD,
    partitionWallDE = Controls.partitionWallDE,
    partitionWallEF = Controls.partitionWallEF,
    partitionWallFG = Controls.partitionWallFG,
    partitionWallGH = Controls.partitionWallGH,
    btnPerformanceTest = Controls.btnPerformanceTest
}

-----------------------------[ Control Validation ]-----------------------------
local function validateControls()
    -- Guard clause: Check for missing required controls
    if not controls.selRoomCombination then
        print("[DivisibleSpace ERROR] Missing required control: selRoomCombination")
        return false
    end
    
    -- Room controllers are required (not optional)
    local roomNames = {"A", "B", "C", "D", "E", "F", "G", "H"}
    for _, room in ipairs(roomNames) do
        -- Validate room controller controls exist
        local roomControlName = "selRoomController" .. room
        if not roomControlName or roomControlName == "" or not controls[roomControlName] then
            print("[DivisibleSpace ERROR] Missing required room controller control: " .. tostring(roomControlName))
            return false
        end
        
        -- Validate audio router controls exist
        local audioRouterName = "selAudioRouter" .. room
        if not audioRouterName or audioRouterName == "" or not controls[audioRouterName] then
            print("[DivisibleSpace ERROR] Missing required audio router control: " .. tostring(audioRouterName))
            return false
        end
    end
    
    -- All validations passed
    return true
end

-----------------------------[ Table Utilities ]-----------------------------
--- Safely insert into table with validation
-- @param tbl table The table to insert into
-- @param value any The value to insert
local function safeTableInsert(tbl, value)
    if not tbl or type(tbl) ~= "table" then return false end
    if value == nil then return false end
    table.insert(tbl, value)
    return true
end

--- Safely get table value with fallback
-- @param tbl table The table to get from
-- @param key any The key to look up
-- @param default any The default value if key not found
local function safeTableGet(tbl, key, default)
    if not tbl or type(tbl) ~= "table" or key == nil then return default end
    return tbl[key] or default
end

--- Sort table keys and return sorted array
-- @param tbl table The table to get sorted keys from
local function getSortedKeys(tbl)
    if not tbl or type(tbl) ~= "table" then return {} end
    local keys = {}
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    table.sort(keys)
    return keys
end

-----------------------------[ Utility: Resolve Controls Table ]-----------------------------
--- Safely resolve component controls table
-- @param component table The component to get controls from
-- @return table|nil The controls table or nil if not available
local function getControlsTable(component)
    -- Guard clause: Validate component exists
    if not component or not component.Controls then return nil end
    
    local c = component.Controls
    
    -- Handle function-based controls
    if type(c) == "function" then
        local ok, val = pcall(c, component)
        if ok and type(val) == "table" then return val end
        return nil
    end
    
    -- Handle table-based controls
    if type(c) == "table" then return c end
    
    return nil
end

-----------------------------[ Class Definition ]-----------------------------
--- DivisibleSpaceController: Manages room combinations, audio routing, and UCI switching
-- Implements event-driven architecture with cached component access for optimal performance
DivisibleSpaceController = {}
DivisibleSpaceController.__index = DivisibleSpaceController

--- Create new DivisibleSpaceController instance
-- @param config table Configuration options including debugging, maxUCIPanels, maxRoomControls, autoDiscover
-- @return table New controller instance
function DivisibleSpaceController.new(config)
    local self = setmetatable({}, DivisibleSpaceController)
    
    -- Core configuration with proper boolean defaults
    self.debugging = (config and config.debugging ~= nil) and config.debugging or true
    self.clearString = "[Clear]"
    self.controls = controls
    
    -- Component type constants for fast lookup
    self.componentTypes = { 
        roomCombiner = "Room Combiner",
        uciPanels = "UCI",
        roomControls = "device_controller_script",
        tscDevices = "TSC",
        audioRouter = "router_with_output"
    }
    
    -- Room configuration optimized for performance
    self.roomNames = {"A", "B", "C", "D", "E", "F", "G", "H"}
    
    -- Audio Router Priority Configuration
    -- Priority determines which input gets routed to rooms based on combinations
    self.audioPriority = {
        -- When all rooms are divided (default priority)
        default = { D=1, E=2, A=3, B=4, C=5, F=6, G=7, H=8 },
        -- Master rooms that control others when combined
        masters = { "A", "D", "E" }
    }
    
    self.roomCombinations = {
        { name = "All Separated",                   rooms = {"A","B","C","D","E","F","G","H"},      combiner = "1 2 3 4 5 6 7 8",               uci = "UCI_Separated" },
        { name = "A+B Combined",                    rooms = {"A+B","C","D","E","F","G","H"},        combiner = "1+2 3 4 5 6 7 8",               uci = "UCI_AB" },
        { name = "B+C Combined",                    rooms = {"A","B+C","D","E","F","G","H"},        combiner = "1 2+3 4 5 6 7 8",               uci = "UCI_BC" },
        { name = "C+D Combined",                    rooms = {"A","B","C+D","E","F","G","H"},        combiner = "1 2 3+4 5 6 7 8",               uci = "UCI_CD" },
        { name = "D+E Combined",                    rooms = {"A","B","C","D+E","F","G","H"},        combiner = "1 2 3 4+5 6 7 8",               uci = "UCI_DE" },
        { name = "E+F Combined",                    rooms = {"A","B","C","D","E+F","G","H"},        combiner = "1 2 3 4 5+6 7 8",               uci = "UCI_EF" },
        { name = "F+G Combined",                    rooms = {"A","B","C","D","E","F+G","H"},        combiner = "1 2 3 4 5 6+7 8",               uci = "UCI_FG" },
        { name = "G+H Combined",                    rooms = {"A","B","C","D","E","F","G+H"},        combiner = "1 2 3 4 5 6 7+8",               uci = "UCI_GH" },
        { name = "A+B, C+D Combined",               rooms = {"A+B","C+D","E","F","G","H"},          combiner = "1+2 3+4 5 6 7 8",               uci = "UCI_AB_CD" },
        { name = "E+F, G+H Combined",               rooms = {"A","B","C","D","E+F","G+H"},          combiner = "1 2 3 4 5+6 7+8",               uci = "UCI_EF_GH" },
        { name = "A+B+C+D Combined",                rooms = {"A+B+C+D","E","F","G","H"},            combiner = "1+2+3+4 5 6 7 8",               uci = "UCI_ABCD" },
        { name = "E+F+G+H Combined",                rooms = {"A","B","C","D","E+F+G+H"},            combiner = "1 2 3 4 5+6+7+8",               uci = "UCI_EFGH" },
        { name = "A+B+C+D, E+F+G+H Combined",       rooms = {"A+B+C+D","E+F+G+H"},                  combiner = "1+2+3+4 5+6+7+8",               uci = "UCI_ABCD_EFGH" },
        { name = "A+B+C+D+E+F Combined",            rooms = {"A+B+C+D+E+F","G","H"},                combiner = "1+2+3+4+5+6 7 8",               uci = "UCI_ABCDEF" },
        { name = "C+D+E+F+G+H Combined",            rooms = {"A","B","C+D+E+F+G+H"},                combiner = "1 2 3+4+5+6+7+8",               uci = "UCI_CDEFGH" },
        { name = "All Combined",                    rooms = {"A+B+C+D+E+F+G+H"},                    combiner = "1+2+3+4+5+6+7+8",               uci = "UCI_All" }
    }
    
    -- Pre-computed lookup tables for O(1) access
    self.combinationLookup = {}
    self.roomIndexMap = { A=1, B=2, C=3, D=4, E=5, F=6, G=7, H=8 }
    
    -- Build combination lookup table once
    for i, combo in ipairs(self.roomCombinations) do
        self.combinationLookup[combo.name] = i
    end
    
    -- Centralized state management
    self.state = {
        currentCombinationIndex = 1,
        isInitialized = false,
        selectedRoomCombiner = nil,
        selectedUCIs = {},
        roomControllers = {},
        audioRouterComponents = {},
        selectedAudioRouters = {},
        componentCache = {},
        controlsCache = {},  -- Cache for frequently accessed controls
        roomCombinerComponents = {},
        roomControllerComponents = {},
        uciComponents = {},
        tscDevices = {}
    }
    
    -- Performance configuration with proper boolean handling
    self.config = {
        maxUCIPanels = (config and config.maxUCIPanels) or 8,
        maxRoomControls = (config and config.maxRoomControls) or 8,
        autoDiscover = (config and config.autoDiscover ~= nil) and config.autoDiscover or true,
        enableControlsCache = true  -- Cache frequently accessed controls
    }
    
    return self
end

-----------------------------[ Debug & Error Helpers ]-----------------------------
--- Debug printing with conditional output
-- @param str string The debug message to print
function DivisibleSpaceController:debugPrint(str)
    if self.debugging then print("[DivisibleSpace Debug] "..str) end
end

--- Centralized error reporting
-- @param str string The error message to print
function DivisibleSpaceController:errorPrint(str)
    print("[DivisibleSpace ERROR] " .. str)
end

--- Centralized warning reporting
-- @param str string The warning message to print
function DivisibleSpaceController:warningPrint(str)
    print("[DivisibleSpace WARNING] " .. str)
end

-----------------------------[ Performance Helper: Cached Controls Access ]-----------------------------
function DivisibleSpaceController:getCachedControls(component)
    -- Guard clause: Validate component
    if not component or not component.Name then return nil end
    
    local componentName = component.Name
    
    -- Return cached controls if available
    if self.config.enableControlsCache and self.state.controlsCache[componentName] then
        return self.state.controlsCache[componentName]
    end
    
    -- Get controls and cache them
    local controls = getControlsTable(component)
    if controls and self.config.enableControlsCache then
        self.state.controlsCache[componentName] = controls
    end
    
    return controls
end

--- Debug component properties for troubleshooting
-- @param component table The component to debug
-- @param label string A label for the debug output
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

--- Safely construct control name with validation
-- @param prefix string The prefix for the control name
-- @param suffix string The suffix for the control name
-- @return string|nil The control name or nil if invalid
function DivisibleSpaceController:safeControlName(prefix, suffix)
    if not prefix or not suffix or prefix == "" or suffix == "" then
        self:errorPrint("Invalid control name parameters: prefix=" .. tostring(prefix) .. ", suffix=" .. tostring(suffix))
        return nil
    end
    return prefix .. suffix
end

--- Clear all event handlers safely
function DivisibleSpaceController:clearEventHandlers()
    self:debugPrint("Clearing all event handlers...")
    
    -- Clear control event handlers
    for controlName, control in pairs(self.controls) do
        if control and control.EventHandler then
            control.EventHandler = nil
            self:debugPrint("Cleared event handler for: " .. controlName)
        end
    end
    
    -- Clear any dynamically assigned event handlers from component controls
    if self.state.roomControllers then
        for room, controller in pairs(self.state.roomControllers) do
            if controller then
                local controls = self:getCachedControls(controller)
                if controls then
                    for controlName, control in pairs(controls) do
                        if control and control.EventHandler then
                            control.EventHandler = nil
                        end
                    end
                end
            end
        end
    end
    
    self:debugPrint("Event handler cleanup completed")
end

-----------------------------[ Optimized Single-Pass Component Discovery ]-----------------------------
--- Discover all Q-SYS components in a single pass for maximum performance
-- Uses direct categorization and caching for optimal speed
function DivisibleSpaceController:discoverComponents()
    self:debugPrint("Starting optimized component discovery...")
    
    -- Reset all component collections in single operation
    self.state.componentCache = {}
    self.state.roomCombinerComponents = {}
    self.state.roomControllerComponents = {}
    self.state.audioRouterComponents = {}
    self.state.uciComponents = {}
    self.state.tscDevices = {}
    
    -- Single-pass component discovery with direct categorization
    local allComponents = Component.GetComponents()
    local roomCombinerCount, roomControllerCount, audioRouterCount, uciComponentCount, tscDeviceCount = 0, 0, 0, 0, 0
    
    for _, comp in ipairs(allComponents) do
        local compName = comp.Name
        local compType = comp.Type
        
        -- Cache component (universal operation)
        self.state.componentCache[compName] = comp
        
        -- Direct type-based categorization
        if compType == self.componentTypes.roomCombiner then
            table.insert(self.state.roomCombinerComponents, comp)
            roomCombinerCount = roomCombinerCount + 1
            -- Auto-select first room combiner if auto-discovery enabled
            if self.config.autoDiscover and not self.state.selectedRoomCombiner then
                self.state.selectedRoomCombiner = comp
            end
            
        elseif compType == self.componentTypes.roomControls then
            -- Fast room controller validation
            local testComp = Component.New(compName)
            if testComp then
                local controls = getControlsTable(testComp)
                if controls and (controls["roomName"] or controls["selDefaultConfigs"] or controls["btnSystemOnOff"]) then
                    table.insert(self.state.roomControllerComponents, comp)
                    roomControllerCount = roomControllerCount + 1
                end
            end
            
        elseif compType == self.componentTypes.audioRouter then
            -- Audio router discovery
            table.insert(self.state.audioRouterComponents, comp)
            audioRouterCount = audioRouterCount + 1
            self:debugPrint("Found Audio Router: " .. comp.Name)
            
        elseif compType == self.componentTypes.uciPanels then
            self.state.uciComponents[compName] = comp
            uciComponentCount = uciComponentCount + 1
            -- Auto-select UCI components if auto-discovery enabled
            if self.config.autoDiscover then
                self.state.selectedUCIs[compName] = comp
            end
            
        elseif compType == self.componentTypes.tscDevices then
            -- Optimized room identifier extraction
            for _, room in ipairs(self.roomNames) do
                if compName:find("UCI" .. room) or compName:find("TSC" .. room) then
                    self.state.tscDevices[room] = comp
                    tscDeviceCount = tscDeviceCount + 1
                    break
                end
            end
        end
    end
    
    -- Single status report
    self:debugPrint("Discovery complete - Room Combiners: " .. roomCombinerCount .. 
        ", Room Controllers: " .. roomControllerCount .. 
        ", Audio Routers: " .. audioRouterCount .. 
        ", UCI Components: " .. uciComponentCount .. 
        ", TSC Devices: " .. tscDeviceCount)
end

-----------------------------[ Enhanced Room Controller Management ]-----------------------------
--- Get sorted list of room controller names for combo box population
-- @return table Array of room controller names with clear option
function DivisibleSpaceController:getRoomControllerNames()
    local namesTable = { RoomControllerNames = {} }
    for _, comp in ipairs(self.state.roomControllerComponents) do
        table.insert(namesTable.RoomControllerNames, comp.Name)
    end
    table.sort(namesTable.RoomControllerNames)
    table.insert(namesTable.RoomControllerNames, self.clearString)
    return namesTable.RoomControllerNames
end

--- Set and validate room controller component
-- @param ctrl table The control to update
-- @param componentType string Description of the component type for logging
-- @return table|nil The validated component or nil if invalid
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

-----------------------------[ Audio Router Management ]-----------------------------
--- Get sorted list of audio router names for combo box population
-- @return table Array of audio router names with clear option
function DivisibleSpaceController:getAudioRouterNames()
    local namesTable = { AudioRouterNames = {} }
    for _, comp in ipairs(self.state.audioRouterComponents) do
        table.insert(namesTable.AudioRouterNames, comp.Name)
    end
    table.sort(namesTable.AudioRouterNames)
    table.insert(namesTable.AudioRouterNames, self.clearString)
    return namesTable.AudioRouterNames
end

--- Set and validate audio router component
-- @param ctrl table The control to update
-- @param componentType string Description of the component type for logging
-- @return table|nil The validated component or nil if invalid
function DivisibleSpaceController:setAudioRouterComponent(ctrl, componentType)
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
        self:debugPrint("Invalid audio router component: " .. componentName)
        return nil
    end
    
    -- Validate audio router has output controls
    local controls = getControlsTable(testComponent)
    if not controls or not controls["select.1"] then
        ctrl.String = "[Invalid Audio Router - No Output Controls]"
        ctrl.Color = "Pink"
        self:debugPrint("Audio router component has no output controls: " .. componentName)
        return nil
    end
    
    ctrl.Color = "White"
    self:debugPrint("Successfully set Audio Router: " .. componentName)
    return testComponent
end

-----------------------------[ Enhanced Combo Box Population ]-----------------------------
--- Populate all component combo boxes with discovered components
-- Handles room combiners, room controllers, audio routers, and UCI components
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
    
    -- Populate Room Controller combo boxes with safe name construction
    local roomControllerNames = self:getRoomControllerNames()
    for _, room in ipairs(self.roomNames) do
        local controlName = self:safeControlName("selRoomController", room)
        if controlName and self.controls[controlName] then
            self.controls[controlName].Choices = roomControllerNames
            if #roomControllerNames > 1 then
                self.controls[controlName].String = roomControllerNames[1]
            end
        end
    end
    
    -- Populate Audio Router combo boxes with safe name construction
    local audioRouterNames = self:getAudioRouterNames()
    for _, room in ipairs(self.roomNames) do
        local controlName = self:safeControlName("selAudioRouter", room)
        if controlName and self.controls[controlName] then
            self.controls[controlName].Choices = audioRouterNames
            if #audioRouterNames > 1 then
                self.controls[controlName].String = audioRouterNames[1]
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

-----------------------------[ Audio Router Priority Control ]-----------------------------
--- Set audio router inputs based on room combination and priority
-- @param combo table The room combination configuration
function DivisibleSpaceController:setAudioRouterInputs(combo)
    if not combo or not combo.rooms then return end
    
    self:debugPrint("Setting audio router inputs for combination: " .. combo.name)
    
    -- Parse room combination to determine routing
    local roomGroups = {}
    local masterRooms = {} -- Track master rooms for priority assignment
    
    -- Parse combined rooms from combo.rooms
    for _, roomStr in ipairs(combo.rooms) do
        if roomStr:find("+") then
            -- This is a combined room group (e.g., "A+B", "D+E")
            local rooms = {}
            for room in roomStr:gmatch("[A-H]") do
                table.insert(rooms, room)
            end
            if #rooms > 0 then
                table.insert(roomGroups, {
                    master = rooms[1], -- First room is master
                    slaves = {table.unpack(rooms, 2)} -- Rest are slaves
                })
                table.insert(masterRooms, rooms[1])
            end
        else
            -- This is a separate room
            table.insert(roomGroups, {
                master = roomStr,
                slaves = {}
            })
            table.insert(masterRooms, roomStr)
        end
    end
    
    -- Assign inputs based on priority for masters
    local assignedInputs = {}
    for i, group in ipairs(roomGroups) do
        local master = group.master
        local inputValue = self.audioPriority.default[master] or i
        assignedInputs[master] = inputValue
        
        -- Set master room audio router with safe name construction
        local masterRouterControl = self:safeControlName("selAudioRouter", master)
        if masterRouterControl and self.controls[masterRouterControl] and self.state.selectedAudioRouters[master] then
            local audioRouter = self.state.selectedAudioRouters[master]
            if audioRouter and audioRouter["select.1"] then
                audioRouter["select.1"].Value = inputValue
                self:debugPrint("Set Audio Router " .. master .. " to Input " .. inputValue)
            end
        end
        
        -- Set slave rooms to same input as master
        for _, slave in ipairs(group.slaves) do
            assignedInputs[slave] = inputValue
            local slaveRouterControl = self:safeControlName("selAudioRouter", slave)
            if slaveRouterControl and self.controls[slaveRouterControl] and self.state.selectedAudioRouters[slave] then
                local audioRouter = self.state.selectedAudioRouters[slave]
                if audioRouter and audioRouter["select.1"] then
                    audioRouter["select.1"].Value = inputValue
                    self:debugPrint("Set Audio Router " .. slave .. " to Input " .. inputValue .. " (following master " .. master .. ")")
                end
            end
        end
    end
    
    self:debugPrint("Audio router input assignment completed")
end

-----------------------------[ Optimized Core Functions ]-----------------------------
--- Set room combiner state directly for maximum performance
-- @param stateString string The state string to apply to the room combiner
function DivisibleSpaceController:setRoomCombinerStateDirect(stateString)
    -- Direct access to selected combiner with fallback
    local combiner = self.state.selectedRoomCombiner or self.state.roomCombinerComponents[1]
    if not combiner then
        self:errorPrint("No Room Combiner available!")
        return
    end
    
    -- Use cached controls for maximum performance
    local controls = self:getCachedControls(combiner)
    if not controls or not controls.Rooms then
        self:warningPrint("Room Combiner has no 'Rooms' control!")
        return
    end
    
    -- Direct state update
    controls.Rooms.String = stateString
    self:debugPrint("Updated Room Combiner Rooms to: " .. stateString)
end

--- Set room combiner state (alias for direct method)
-- @param stateString string The state string to set
function DivisibleSpaceController:setRoomCombinerState(stateString)
    return self:setRoomCombinerStateDirect(stateString)
end

--- Switch UCIs directly using the fastest available method
-- @param uciName string The UCI name to switch to
function DivisibleSpaceController:switchUCIsDirect(uciName)
    -- Direct fallback to UCI switching for maximum performance
    self:debugPrint("Switching UCIs to: " .. uciName)
    
    -- Try TSC devices first (fastest method)
    local tscUpdated = false
    for _, tsc in pairs(self.state.tscDevices) do
        if tsc and tsc.UCI then
            tsc.UCI.String = uciName
            tscUpdated = true
        end
    end
    
    -- Fallback to direct UCI switching if no TSC devices
    if not tscUpdated then
        Uci.SetUCI("UCIRmA", uciName)
        Uci.SetUCI("UCIRmB", uciName)
        Uci.SetUCI("UCIRmC", uciName)
        Uci.SetUCI("UCIRmD", uciName)
        Uci.SetUCI("UCIRmE", uciName)
        Uci.SetUCI("UCIRmF", uciName)
        Uci.SetUCI("UCIRmG", uciName)
        Uci.SetUCI("UCIRmH", uciName)
    end
end

--- Switch UCIs (alias for direct method)
-- @param uciName string The UCI name to switch to
function DivisibleSpaceController:switchUCIs(uciName)
    return self:switchUCIsDirect(uciName)
end

--- Update room controller power states directly based on combination
-- @param combo table The room combination configuration
function DivisibleSpaceController:updateRoomControllerPowerDirect(combo)
    -- Pre-compute active rooms map inline for performance
    local activeRooms = {}
    for _, roomGroup in ipairs(combo.rooms) do
        if roomGroup:find("+") then
            for part in roomGroup:gmatch("[^+]+") do 
                activeRooms[part] = true 
            end
        else
            activeRooms[roomGroup] = true
        end
    end
    
    -- Direct room controller updates using cached controls
    for room, isActive in pairs(activeRooms) do
        local roomController = self.state.roomControllers[room]
        if roomController then
            local controls = self:getCachedControls(roomController)
            if controls and controls["btnSystemOnOff"] then
                controls["btnSystemOnOff"].Boolean = isActive
                self:debugPrint("Updated Room " .. room .. " power to: " .. tostring(isActive))
            end
        end
    end
end

--- Update room controller power states
-- @param activeRooms table Map of room names to boolean active states
function DivisibleSpaceController:updateRoomControllerPower(activeRooms)
    -- Use the direct implementation to avoid code duplication
    local combo = { rooms = {} }
    for room, isActive in pairs(activeRooms) do
        if isActive then
            table.insert(combo.rooms, room)
        end
    end
    self:updateRoomControllerPowerDirect(combo)
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

-----------------------------[ Optimized Main Application Function ]-----------------------------
--- Apply room combination by index with maximum performance
-- @param index integer The combination index to apply (1-based)
function DivisibleSpaceController:applyCombination(index)
    -- Guard clause: Validate index
    if not index or index < 1 or index > #self.roomCombinations then 
        self:errorPrint("Invalid combination index: " .. tostring(index))
        return 
    end
    
    -- Direct state update and combo access
    self.state.currentCombinationIndex = index
    local combo = self.roomCombinations[index]
    
    self:debugPrint("Applying combination: " .. combo.name)
    
    -- Direct, optimized operations with minimal function calls
    self:setRoomCombinerStateDirect(combo.combiner)
    self:setAudioRouterInputs(combo)
    self:switchUCIsDirect(combo.uci)
    self:updateRoomControllerPowerDirect(combo)
    
    -- Single UI update
    if self.controls.selRoomCombination then
        self.controls.selRoomCombination.String = combo.name
    end
    
    -- Optional: Publish state change (non-blocking)
    if Notifications and Notifications.Publish then
        Notifications.Publish("DivisibleRoomState", {
            name = combo.name,
            rooms = combo.rooms,
            combiner = combo.combiner,
            uci = combo.uci,
            timestamp = Timer.Now()
        })
    end
    
    self:debugPrint("Combination applied successfully")
end

--------** Ultra-Fast Event-Driven Control Handlers **--------
--- Setup all event handlers for controls with optimized performance
-- Uses pre-compiled closures and direct lookups for maximum speed
function DivisibleSpaceController:setupEventHandlers()
    -- Optimized room combination dropdown handler (most critical)
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
            end
        end
    end

    -- Pre-compiled button handlers for instant execution
    local buttonApplyCombination = function(index) return function() self:applyCombination(index) end end
    
    if self.controls.btnAllSeparated then self.controls.btnAllSeparated.EventHandler = buttonApplyCombination(1) end
    if self.controls.btnABCombined then self.controls.btnABCombined.EventHandler = buttonApplyCombination(2) end
    if self.controls.btnBCCombined then self.controls.btnBCCombined.EventHandler = buttonApplyCombination(3) end
    if self.controls.btnCDCombined then self.controls.btnCDCombined.EventHandler = buttonApplyCombination(4) end
    if self.controls.btnDECombined then self.controls.btnDECombined.EventHandler = buttonApplyCombination(5) end
    if self.controls.btnEFCombined then self.controls.btnEFCombined.EventHandler = buttonApplyCombination(6) end
    if self.controls.btnFGCombined then self.controls.btnFGCombined.EventHandler = buttonApplyCombination(7) end
    if self.controls.btnGHCombined then self.controls.btnGHCombined.EventHandler = buttonApplyCombination(8) end
    if self.controls.btnABCDCombined then self.controls.btnABCDCombined.EventHandler = buttonApplyCombination(11) end
    if self.controls.btnEFGHCombined then self.controls.btnEFGHCombined.EventHandler = buttonApplyCombination(12) end
    if self.controls.btnABCDEFCombined then self.controls.btnABCDEFCombined.EventHandler = buttonApplyCombination(14) end
    if self.controls.btnAllCombined then self.controls.btnAllCombined.EventHandler = buttonApplyCombination(16) end

    -- Optimized partition wall handlers with direct state mapping
    if self.controls.partitionWallAB then
        self.controls.partitionWallAB.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 2 or 1)
        end
    end
    if self.controls.partitionWallBC then
        self.controls.partitionWallBC.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 3 or 1)
        end
    end
    if self.controls.partitionWallCD then
        self.controls.partitionWallCD.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 4 or 1)
        end
    end
    if self.controls.partitionWallDE then
        self.controls.partitionWallDE.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 5 or 1)
        end
    end
    if self.controls.partitionWallEF then
        self.controls.partitionWallEF.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 6 or 1)
        end
    end
    if self.controls.partitionWallFG then
        self.controls.partitionWallFG.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 7 or 1)
        end
    end
    if self.controls.partitionWallGH then
        self.controls.partitionWallGH.EventHandler = function(ctl)
            self:applyCombination(ctl.Boolean and 8 or 1)
        end
    end

    -- Component selection handlers (less critical, but still optimized)
    if self.controls.selRoomCombiner then
        self.controls.selRoomCombiner.EventHandler = function(ctl)
            self.state.selectedRoomCombiner = self.state.componentCache[ctl.String]
            -- Clear controls cache for this component
            if self.state.controlsCache[ctl.String] then
                self.state.controlsCache[ctl.String] = nil
            end
            if self.state.isInitialized then
                self:applyCombination(self.state.currentCombinationIndex)
            end
        end
    end

    if self.controls.selUCI then
        self.controls.selUCI.EventHandler = function(ctl)
            self.state.selectedUCIs[ctl.String] = self.state.componentCache[ctl.String]
            if self.state.isInitialized then
                self:applyCombination(self.state.currentCombinationIndex)
            end
        end
    end

    -- Room Controller selection handlers (batch processing for performance)
    for _, room in ipairs(self.roomNames) do
        local controlName = self:safeControlName("selRoomController", room)
        if controlName and self.controls[controlName] then
            self.controls[controlName].EventHandler = function(ctl)
                local component = self:setRoomControllerComponent(ctl, "Room Controller " .. room)
                self.state.roomControllers[room] = component
                if component and self.state.isInitialized then
                    self:applyCombination(self.state.currentCombinationIndex)
                end
            end
        end
    end
    
    -- Audio Router selection handlers (batch processing for performance)
    for _, room in ipairs(self.roomNames) do
        local controlName = self:safeControlName("selAudioRouter", room)
        if controlName and self.controls[controlName] then
            self.controls[controlName].EventHandler = function(ctl)
                local component = self:setAudioRouterComponent(ctl, "Audio Router " .. room)
                self.state.selectedAudioRouters[room] = component
                if component and self.state.isInitialized then
                    self:applyCombination(self.state.currentCombinationIndex)
                end
            end
        end
    end
end

-----------------------------[ Enhanced Status Management ]-----------------------------
--- Check system status and component availability
-- @return string Status message
-- @return boolean Whether there are any errors
-- @return table Array of status details
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

-----------------------------[ Initialize Modules ]-----------------------------
--- Initialize any required modules (placeholder for future expansion)
function DivisibleSpaceController:initModules()
    self:debugPrint("Modules initialized")
end

--------** API Methods **--------
--- Set the current room combination by index
-- @param index integer Combination index (1-based)
function DivisibleSpaceController:SetCombination(index)
    self:applyCombination(index)
end

--- Get the current room combination information
-- @return integer Current combination index
-- @return table Current combination data
function DivisibleSpaceController:GetCurrentCombination()
    return self.state.currentCombinationIndex, self.roomCombinations[self.state.currentCombinationIndex]
end

--- Get all available components discovered by the controller
-- @return table Table containing arrays of discovered components
function DivisibleSpaceController:GetAvailableComponents()
    return {
        roomCombiners = self.state.roomCombinerComponents,
        roomControllers = self.state.roomControllerComponents,
        uciComponents = self.state.uciComponents,
        tscDevices = self.state.tscDevices
    }
end

--- Refresh component discovery and reset all cached data
function DivisibleSpaceController:RefreshComponentDiscovery()
    self:debugPrint("Refreshing component discovery...")
    
    -- Clear event handlers before resetting state
    self:clearEventHandlers()
    
    -- Reset all state components consistently
    self.state.selectedRoomCombiner = nil
    self.state.selectedUCIs = {}
    self.state.roomControllers = {}
    self.state.selectedAudioRouters = {}
    self.state.controlsCache = {}  -- Clear controls cache
    self.state.componentCache = {}  -- Clear component cache
    
    -- Rediscover and repopulate
    self:discoverComponents()
    self:populateComponentComboBoxes()
    self:setupEventHandlers()  -- Reestablish event handlers
    self:checkStatus()
end

--------** Optimized Batch Initialization **--------
--- Initialize the controller with optimized batch operations
-- Performs component discovery, UI setup, and applies initial state
function DivisibleSpaceController:funcInit()
    self:debugPrint("Starting optimized DivisibleSpaceController initialization...")
    
    -- Batch all initialization operations for maximum performance
    local initStartTime = Timer.Now()
    
    -- Phase 1: Component Discovery (single pass)
    self:discoverComponents()
    
    -- Phase 2: UI Setup (batched operations)
    self:populateComponentComboBoxes()
    self:setupEventHandlers()
    
    -- Phase 3: Apply initial state (single operation)
    self.state.isInitialized = true
    self:applyCombination(1)
    
    -- Phase 4: Status and Reporting (non-blocking)
    local initEndTime = Timer.Now()
    local initDuration = initEndTime - initStartTime
    
    local status, hasError, details = self:checkStatus()
    
    -- Single notification with all status information
    if Notifications and Notifications.Publish then
        Notifications.Publish("DivisibleSpaceInitialized", {
            roomCombinerCount = #self.state.roomCombinerComponents,
            roomControllerCount = #self.state.roomControllerComponents,
            uciComponentCount = #self.state.uciComponents,
            tscDeviceCount = #self.state.tscDevices,
            status = status,
            hasError = hasError,
            initializationTime = initDuration
        })
    end
    
    self:debugPrint("DivisibleSpaceController initialized in " .. initDuration .. " seconds")
end

--------** Enhanced Cleanup **--------
--- Comprehensive cleanup of all resources and event handlers
function DivisibleSpaceController:cleanup()
    self:debugPrint("Starting comprehensive cleanup...")
    
    -- Use centralized event handler cleanup
    self:clearEventHandlers()
    
    -- Reset state completely and consistently
    self.state = {
        currentCombinationIndex = 1,
        isInitialized = false,
        selectedRoomCombiner = nil,
        selectedUCIs = {},
        roomControllers = {},
        audioRouterComponents = {},
        selectedAudioRouters = {},
        componentCache = {},
        controlsCache = {},  -- Ensure controls cache is reset
        roomCombinerComponents = {},
        roomControllerComponents = {},
        uciComponents = {},
        tscDevices = {}
    }
    
    self:debugPrint("Cleanup completed successfully")
end

-----------------------------[ Performance Monitoring ]-----------------------------
--- Run performance test cycling through all combinations
-- Measures total time and average time per combination
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

-----------------------------[ Factory Function ]-----------------------------
--- Factory function to create DivisibleSpaceController with error handling
-- @param config table Configuration options for the controller
-- @return table|nil Controller instance or nil if creation failed
local function createDivisibleSpaceController(config)
    print("[DivisibleSpace] Creating DivisibleSpaceController...")
    local success, controller = pcall(function()
        local instance = DivisibleSpaceController.new(config)
        instance:funcInit()
        instance:runPerformanceTest()
        return instance
    end)
    if success then
        print("[DivisibleSpace] Successfully created DivisibleSpaceController")
        return controller
    else
        print("[DivisibleSpace ERROR] Failed to create controller: " .. tostring(controller))
        return nil
    end
end

-----------------------------[ Instance Creation ]-----------------------------
if not validateControls() then
    print("ERROR: Required controls are missing. Please check your Q-SYS design.")
    return
end

myDivisibleSpaceController = createDivisibleSpaceController({
    debugging = true,
    autoDiscover = true,
    maxUCIPanels = 8,
    maxRoomControls = 8
})

if myDivisibleSpaceController then
    print("[DivisibleSpace] DivisibleSpaceController created successfully!")
else
    print("[DivisibleSpace ERROR] Failed to create DivisibleSpaceController!")
end

-----------------------------[ End of Script ]-----------------------------

-- Performance-Optimized Features Applied (v5.0):
-- 1. **Event-Driven Architecture**: Ultra-fast button handlers with pre-compiled closures
-- 2. **Cached Component Access**: Intelligent caching system for frequently accessed controls
-- 3. **Single-Pass Discovery**: Optimized component discovery eliminating redundant iterations
-- 4. **Direct State Updates**: Immediate state changes without intermediate function calls
-- 5. **Batched Initialization**: Consolidated startup operations for faster load times
-- 6. **Guard Clauses**: Early returns throughout to flatten control flow
-- 7. **Pre-computed Lookups**: O(1) combination lookups using hash tables
-- 8. **Streamlined Event Handlers**: Minimal indirection with direct applyCombination calls
-- 9. **Performance Monitoring**: Built-in timing for initialization and operations
-- 10. **Memory Efficient**: Reduced object creation and optimized data structures
-- 11. **Metatable-based OOP**: Lua Refactor compliant class structure
-- 12. **Enhanced Error Handling**: Robust validation with detailed debugging

-- Optimized Usage (Performance-First Design) - 8-Room Configuration:
-- 1. **Automatic Discovery**: Room Combiners, UCI components, and TSC devices auto-discovered
-- 2. **Fast Component Selection**: Pre-populated combo boxes with instant response
--    - selRoomCombiner: High-speed Room Combiner selection with cached controls
--    - selUCI: Optimized UCI component selection with direct state updates
--    - compRoomControlsA through compRoomControlsH: Individual room controller selection
-- 3. **Ultra-Fast Room Switching**: Dropdown "selRoomCombination" with O(1) lookup
-- 4. **Instant Button Response**: Pre-compiled button handlers for 8-room combinations:
--    - btnAllSeparated, btnABCombined through btnGHCombined
--    - btnABCDCombined, btnEFGHCombined, btnABCDEFCombined, btnAllCombined
-- 5. **Real-Time Partition Walls**: Immediate response to 7 partition sensors:
--    - partitionWallAB, partitionWallBC, partitionWallCD, partitionWallDE
--    - partitionWallEF, partitionWallFG, partitionWallGH
-- 6. **16 Room Combinations**: Logical combinations from individual rooms to full merge
-- 7. **Performance Monitoring**: Built-in timing and performance metrics
-- 8. **Cached Operations**: Intelligent caching reduces component access overhead
-- 9. **Batched Initialization**: Optimized startup with performance monitoring
-- 10. **Event-Driven Design**: Immediate UI feedback and state synchronization
-- 11. **8-Room UCI Management**: Supports UCIRmA through UCIRmH with direct switching
