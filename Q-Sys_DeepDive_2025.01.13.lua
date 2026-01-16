--[[
    LectureHallUIController (Refactored) - Q-SYS Control Script for Lecture Hall UCI Navigation
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-01-13
    Firmware Req: 10.0.0
    Description: Controls navigation, layer visibility, video routing, camera controls, and room mode
    switching for Lecture Hall UCI. Manages UI state transitions and component interactions.
    
    FLOW EXAMPLES:
    When user presses navigation button:
      1. Handler fires (bindArray registration)
      2. Calls handleNavButton(index)
      3. Updates button interlock state
      4. Shows/hides layers via handleNavigation(index)
      5. Syncs video routing and camera controls
    
    When user selects room mode:
      1. Handler fires for roomModeControls
      2. Calls handleRoomMode(index)
      3. Updates room mode state
      4. Resets icons and combo boxes
      5. Updates video routing layers
    
    When user selects video source:
      1. ComboBox EventHandler fires
      2. Calls handleVideoSwitch(index, sourceString)
      3. Updates video routing components
      4. Updates icons
      5. Shows/hides device control layers
    
    REFACTORED FEATURES:
    - Single-class structure with utility functions for maintainability
    - All state encapsulated in controller instance
    - Comprehensive validation and error handling
    - setProp used consistently to prevent feedback loops
    - bind/bindArray for consistent event handler registration
    - Early returns and guard clauses for cleaner control flow
    - Comprehensive documentation with "Called from:" comments
]]--

-------------------[ Configuration ]-------------------
local uciPageName = "LectureHall"

local roomModeNames = {
    [1] = 'Single Projector',
    [2] = 'Dual Projector',
}

local navLayers = {
    '0.1 Room Mode',
    '1.0 Video Routing',
    '2.0 Camera Controls',
    '3.0 Room Controls',
    '4.0 Support',
}

local videoRoutingLayers = {
    '1.1 Single Destination',
    '1.2 Dual Destination',
}

local roomControlProjLayers = {
    '3.1 Single Projector',
    '3.2 Dual Projector',
}

local roomControlScreenLayers = {
    '3.3 Single Screen',
    '3.4 Dual Screen',
}

local roomControlEnviroLayers = {
    '3.5 Lighting Shades',
    '3.6 Lighting Shades',
}

local cameraLayers = {
    '2.1 PTZ Presets',
    '2.2 Auto-Framing',
}

local roomStateLayers = {
    'Main',
    'Confirm Shutdown',
    'Welcome',
}

local allLayers = {
    '0.1 Room Mode',
    '1.0 Video Routing',
    '2.0 Camera Controls',
    '3.0 Room Controls',
    '4.0 Support',
    '1.1 Single Destination',
    '1.2 Dual Destination',
    '3.1 Single Projector',
    '3.2 Dual Projector',
    '3.3 Single Screen',
    '3.4 Dual Screen',
    '3.5 Lighting Shades',
    'Main',
    'Confirm Shutdown',
    'Welcome',
    'Regions',
    '1.1 Wireless Presentation',
    '1.2 Roku',
    '1.3 Audio Player',
    '2.2 Auto-Framing',
    '2.1 PTZ Presets',
}

-------------------[ Control References ]-------------------
local controls = {
    -- Navigation Controls
    btnNav = {
        Controls.btnNav_1,
        Controls.btnNav_2,
        Controls.btnNav_3,
        Controls.btnNav_4,
        Controls.btnNav_5,
    },
    
    -- Room Mode Controls
    btnRoomMode = {
        Controls.btnRoomMode_01,
        Controls.btnRoomMode_02,
    },
    
    -- System Power Controls
    btnSystemPower = {
        Controls.btnSystemPower_1,
        Controls.btnSystemPower_2,
        Controls.btnSystemPower_3,
        Controls.btnSystemPower_4,
    },
    
    -- Room Controls
    btnRoomControls = {
        Controls.btnRoomControls_1,
        Controls.btnRoomControls_2,
        Controls.btnRoomControls_3,
    },
    
    -- Icons
    icon = {
        Controls.icon_1,
        Controls.icon_2,
        Controls.icon_3,
    },
    
    -- Combo Boxes
    txtCombo = {
        Controls.txtCombo_1,
        Controls.txtCombo_2,
        Controls.txtCombo_3,
    },
    
    -- Text Controls
    textRoomMode = Controls.textRoomMode,
    
    -- Component References
    devNV21Left = Component.New('display1')['hdmi.out.1.select.pretty.name'],
    devNV21Right = Component.New('display2')['hdmi.out.1.select.pretty.name'],
    camRouter = Component.New('MCRouter')['select.1'],
    
    -- UCI Variables
    cssPrefix = Uci.Variables.CSS_Prefix,
    sourceVar = {
        Uci.Variables.source_1,
        Uci.Variables.source_2,
        Uci.Variables.source_3,
        Uci.Variables.source_4,
        Uci.Variables.source_5,
        Uci.Variables.source_6,
        Uci.Variables.source_7,
    },
}

-------------------[ Utility Functions ]-------------------
-- Check if value is an array (table with numeric indices)
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

-- Get control array (normalizes single controls to arrays)
local function getControlArray(ctrl)
    if not ctrl then return {} end
    return isArr(ctrl) and ctrl or {ctrl}
end

-- Set property only if value changed (prevents unnecessary signal propagation)
-- This is insurance against feedback loops and improves performance
local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

-- Bind event handler to control
local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

-- Bind event handlers to array of controls
local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do
        bind(ctrl, function(ctl) handler(i, ctl) end)
    end
end

-- Execute function for each item in array
local function forEach(arr, fn)
    if not arr then return end
    for i, v in ipairs(arr) do
        if fn then fn(i, v) end
    end
end

-------------------[ Validation Functions ]-------------------
-- Validate that required controls exist before proceeding
local function validateControls()
    local missing = {}
    
    -- Check navigation controls
    for i, ctrl in ipairs(controls.btnNav) do
        if not ctrl then table.insert(missing, "btnNav_" .. i) end
    end
    
    -- Check room mode controls
    for i, ctrl in ipairs(controls.btnRoomMode) do
        if not ctrl then table.insert(missing, "btnRoomMode_0" .. i) end
    end
    
    -- Check system power controls
    for i, ctrl in ipairs(controls.btnSystemPower) do
        if not ctrl then table.insert(missing, "btnSystemPower_" .. i) end
    end
    
    -- Check room controls
    for i, ctrl in ipairs(controls.btnRoomControls) do
        if not ctrl then table.insert(missing, "btnRoomControls_" .. i) end
    end
    
    -- Check combo boxes
    for i, ctrl in ipairs(controls.txtCombo) do
        if not ctrl then table.insert(missing, "txtCombo_" .. i) end
    end
    
    -- Check required components
    if not controls.devNV21Left then table.insert(missing, "devNV21Left") end
    if not controls.devNV21Right then table.insert(missing, "devNV21Right") end
    if not controls.camRouter then table.insert(missing, "camRouter") end
    
    if #missing > 0 then
        print("ERROR: LectureHallUIController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("LectureHallUIController validation passed")
    return true
end

-------------------[ Controller Class ]-------------------
LectureHallUIController = {}
LectureHallUIController.__index = LectureHallUIController

function LectureHallUIController.new()
    if not validateControls() then
        error("LectureHallUIController initialization failed: Missing required controls")
    end
    
    local self = setmetatable({}, LectureHallUIController)
    
    -- State tracking
    self.state = {
        roomMode = 0,
        currentNav = 0,
        lastSourceSelected = 1,
        initialized = false,
    }
    
    -- Translation tables (populated during initialization)
    self.translateTable = {}
    self.iconCSSTable = {}
    self.deviceControlLayers = {}
    self.friendlyNames = {}
    
    -- Initialize translation tables
    self:initializeTranslationTables()
    
    -- Set initial combo box choices
    self:setComboChoices()
    
    -- Reset icons to default state
    self:resetIcons()
    
    -- Set combo strings to default
    self:setComboStrings()
    
    -- Initialize state (power off)
    self.state.initialized = true
    
    return self
end

-------------------[ Initialization Methods ]-------------------
-- Called from: LectureHallUIController.new()
-- Initialize translation tables for source names and icons
function LectureHallUIController:initializeTranslationTables()
    local cssPrefix = controls.cssPrefix and controls.cssPrefix.String or ""
    
    -- Build friendly names array
    self.friendlyNames = {}
    for i = 1, 7 do
        if controls.sourceVar[i] then
            table.insert(self.friendlyNames, controls.sourceVar[i].String)
        end
    end
    
    -- Build translation table (friendly name <-> component name)
    self.translateTable = {}
    self.translateTable[controls.sourceVar[1] and controls.sourceVar[1].String or ""] = 'AV 1'
    self.translateTable[controls.sourceVar[2] and controls.sourceVar[2].String or ""] = 'AV 2'
    self.translateTable[controls.sourceVar[3] and controls.sourceVar[3].String or ""] = 'AV 3'
    self.translateTable[controls.sourceVar[4] and controls.sourceVar[4].String or ""] = 'AV 4'
    self.translateTable[controls.sourceVar[5] and controls.sourceVar[5].String or ""] = 'AV 5'
    self.translateTable[controls.sourceVar[6] and controls.sourceVar[6].String or ""] = 'Graphic 1'
    
    -- Reverse translation
    self.translateTable['AV 1'] = controls.sourceVar[1] and controls.sourceVar[1].String or ""
    self.translateTable['AV 2'] = controls.sourceVar[2] and controls.sourceVar[2].String or ""
    self.translateTable['AV 3'] = controls.sourceVar[3] and controls.sourceVar[3].String or ""
    self.translateTable['AV 4'] = controls.sourceVar[4] and controls.sourceVar[4].String or ""
    self.translateTable['AV 5'] = controls.sourceVar[5] and controls.sourceVar[5].String or ""
    self.translateTable['Graphic 1'] = controls.sourceVar[6] and controls.sourceVar[6].String or ""
    
    -- Build icon CSS table
    self.iconCSSTable = {}
    self.iconCSSTable[controls.sourceVar[1] and controls.sourceVar[1].String or ""] = cssPrefix .. 'icon-laptop-hdmi'
    self.iconCSSTable[controls.sourceVar[2] and controls.sourceVar[2].String or ""] = cssPrefix .. 'icon-laptop-usb-c'
    self.iconCSSTable[controls.sourceVar[3] and controls.sourceVar[3].String or ""] = cssPrefix .. 'icon-pc'
    self.iconCSSTable[controls.sourceVar[4] and controls.sourceVar[4].String or ""] = cssPrefix .. 'icon-wireless'
    self.iconCSSTable[controls.sourceVar[5] and controls.sourceVar[5].String or ""] = cssPrefix .. 'icon-logo-roku'
    self.iconCSSTable[controls.sourceVar[6] and controls.sourceVar[6].String or ""] = cssPrefix .. 'icon-logo-qsys-stacked'
    self.iconCSSTable['touch'] = cssPrefix .. 'icon-touch'
    
    -- Build device control layers mapping
    self.deviceControlLayers = {}
    self.deviceControlLayers['other'] = '1.3 Audio Player'
    if controls.sourceVar[5] then
        self.deviceControlLayers[controls.sourceVar[5].String] = '1.2 Roku'
    end
    if controls.sourceVar[4] then
        self.deviceControlLayers[controls.sourceVar[4].String] = '1.1 Wireless Presentation'
    end
end

-- Called from: LectureHallUIController.new(), handleSourceVariableChange()
-- Set combo box choices based on source variables
function LectureHallUIController:setComboChoices()
    for i, ctrl in ipairs(controls.txtCombo) do
        if not ctrl then goto continue end
        
        if i == 3 then
            -- Third combo box gets all friendly names
            setProp(ctrl, "Choices", self.friendlyNames)
        else
            -- First two combo boxes get first 6 friendly names
            local shortNames = {}
            for j = 1, math.min(6, #self.friendlyNames) do
                table.insert(shortNames, self.friendlyNames[j])
            end
            setProp(ctrl, "Choices", shortNames)
        end
        ::continue::
    end
end

-- Called from: LectureHallUIController.new(), handleRoomMode()
-- Set all combo box strings to default value
function LectureHallUIController:setComboStrings()
    forEach(controls.txtCombo, function(i, ctrl)
        if ctrl then setProp(ctrl, "String", 'Select Source') end
    end)
end

-- Called from: LectureHallUIController.new(), handleRoomMode(), powerOn()
-- Reset all icons to default 'touch' state
function LectureHallUIController:resetIcons()
    forEach(controls.icon, function(i, ctrl)
        if ctrl then setProp(ctrl, "CssClass", self.iconCSSTable['touch'] or "") end
    end)
end

-- Called from: handleVideoSwitch()
-- Set icon CSS class based on source string
function LectureHallUIController:setIcon(index, sourceString)
    if not controls.icon[index] then return end
    local cssClass = self.iconCSSTable[sourceString] or self.iconCSSTable['touch']
    setProp(controls.icon[index], "CssClass", cssClass)
end

-------------------[ Layer Management Methods ]-------------------
-- Called from: hideAllLayers(), handleNavigation(), handlePowerOff(), handleConfirmShutdown()
-- Hide all layers
function LectureHallUIController:hideAllLayers()
    forEach(allLayers, function(i, layer)
        Uci.SetLayerVisibility(uciPageName, layer, false, 'none')
    end)
end

-- Called from: handleNavigation(), handleRoomControls(), handleCheckCameraRoute(), showHideDeviceControls()
-- Set layer visibility (interlock pattern - only one layer in array is visible)
function LectureHallUIController:setLayerInterlock(layers, activeIndex)
    if not layers then return end
    forEach(layers, function(i, layer)
        Uci.SetLayerVisibility(uciPageName, layer, (i == activeIndex), "none")
    end)
end

-- Called from: handleNavigation(), handleCheckCameraRoute(), powerOn(), handleCancelShutdown()
-- Show or hide a single layer
function LectureHallUIController:setLayerVisibility(layer, visible)
    if not layer then return end
    Uci.SetLayerVisibility(uciPageName, layer, visible, "none")
end

-------------------[ Button Interlock Methods ]-------------------
-- Called from: handleNavButton(), handleRoomMode(), handleRoomControls(), handleSystemPower(), handleNavigation(), powerOn(), handleCancelShutdown()
-- Set button interlock state (only one button in array is active)
function LectureHallUIController:setButtonInterlock(buttons, activeIndex)
    if not buttons then return end
    forEach(buttons, function(i, ctrl)
        if ctrl then setProp(ctrl, "Boolean", (i == activeIndex)) end
    end)
end

-------------------[ Video Routing Methods ]-------------------
-- Called from: handleVideoSourceSelect()
-- Handle video switching based on combo box selection
function LectureHallUIController:handleVideoSwitch(index, sourceString)
    if not sourceString then return end
    
    local translatedName = self.translateTable[sourceString] or sourceString
    
    if index == 1 or index == 2 then
        -- First two combo boxes control left display
        if controls.devNV21Left then
            setProp(controls.devNV21Left, "String", translatedName)
        end
    elseif index == 3 then
        -- Third combo box controls right display
        if controls.devNV21Right then
            setProp(controls.devNV21Right, "String", translatedName)
        end
    end
end

-- Called from: handleVideoSourceSelect()
-- Show/hide device control layers based on selected source
function LectureHallUIController:showHideDeviceControls(sourceString)
    if not sourceString then return end
    
    -- Hide all device control layers first
    for _, layer in pairs(self.deviceControlLayers) do
        self:setLayerVisibility(layer, false)
    end
    
    -- Show appropriate layer based on source
    local targetLayer = self.deviceControlLayers[sourceString] or self.deviceControlLayers['other']
    if targetLayer then
        self:setLayerVisibility(targetLayer, true)
    end
end

-- Called from: handleNavButton(), handleRoomMode()
-- Check if video routing layer is active and restore device controls
function LectureHallUIController:checkSource()
    if not controls.btnNav[2] or not controls.btnNav[2].Boolean then return end
    if not controls.txtCombo[self.state.lastSourceSelected] then return end
    
    local sourceString = controls.txtCombo[self.state.lastSourceSelected].String
    if sourceString and sourceString ~= 'Select Source' then
        self:showHideDeviceControls(sourceString)
    end
end

-------------------[ Camera Control Methods ]-------------------
-- Called from: handleNavButton(), handleCancelShutdown()
-- Check camera router and show appropriate camera layer
function LectureHallUIController:checkCameraRoute()
    if not controls.btnNav[3] or not controls.btnNav[3].Boolean then
        -- Navigation away from camera controls - hide all camera layers
        self:setLayerInterlock(cameraLayers, 0)
        return
    end
    
    -- On camera controls page - show layer based on camera router value
    if controls.camRouter then
        local routerValue = controls.camRouter.Value
        if routerValue >= 1 and routerValue <= #cameraLayers then
            self:setLayerInterlock(cameraLayers, 0)
            self:setLayerVisibility(cameraLayers[routerValue], true)
        end
    end
end

-------------------[ Navigation Methods ]-------------------
-- Called from: handleNavButton()
-- Handle navigation-specific logic (video routing layers, room control layers)
function LectureHallUIController:handleNavigation(navIndex)
    if navIndex == 2 then
        -- Video routing page - show appropriate layer based on room mode
        self:setLayerInterlock(videoRoutingLayers, self.state.roomMode)
    elseif navIndex == 4 then
        -- Room controls page - show projector layers based on room mode
        self:setLayerInterlock(roomControlProjLayers, self.state.roomMode)
        self:setButtonInterlock(controls.btnRoomControls, 1)
    end
end

-- Called from: handleNavButton()
-- Enable or disable navigation buttons (except first one)
function LectureHallUIController:enableDisableNav(enabled)
    for i = 2, #controls.btnNav do
        if controls.btnNav[i] then
            setProp(controls.btnNav[i], "IsDisabled", not enabled)
        end
    end
end

-------------------[ Room Controls Methods ]-------------------
-- Called from: handleRoomControls()
-- Handle room controls button selection and layer switching
function LectureHallUIController:handleRoomControlsCheck(buttonIndex)
    -- Map buttonIndex to corresponding layer array
    local layerMap = {
        [1] = roomControlProjLayers,
        [2] = roomControlScreenLayers,
        [3] = roomControlEnviroLayers,
    }
    
    -- All layer arrays
    local allLayers = {
        roomControlProjLayers,
        roomControlScreenLayers,
        roomControlEnviroLayers,
    }
    
    -- Set selected layer to roomMode, others to 0
    local selectedLayer = layerMap[buttonIndex]
    for _, layerArray in ipairs(allLayers) do
        local value = (layerArray == selectedLayer) and self.state.roomMode or 0
        self:setLayerInterlock(layerArray, value)
    end
end

-------------------[ Event Handlers ]-------------------
-- Called from: bindArray(controls.btnNav, ...) during initialization
-- Handle navigation button press
function LectureHallUIController:handleNavButton(index)
    if not controls.btnNav[index] then return end
    
    self.state.currentNav = index
    
    -- Update button interlock
    self:setButtonInterlock(controls.btnNav, index)
    
    -- Hide sub-layers first
    self:setLayerInterlock(videoRoutingLayers, 0)
    self:setLayerInterlock(roomControlProjLayers, 0)
    self:setLayerInterlock(roomControlScreenLayers, 0)
    self:setLayerInterlock(roomControlEnviroLayers, 0)
    
    -- Check camera route
    self:checkCameraRoute()
    
    -- Show main navigation layer
    self:setLayerInterlock(navLayers, index)
    
    -- Hide device controls
    for _, layer in pairs(self.deviceControlLayers) do
        self:setLayerVisibility(layer, false)
    end
    
    -- Handle navigation-specific logic
    self:handleNavigation(index)
    
    -- Check source if on video routing page
    self:checkSource()
end

-- Called from: bindArray(controls.btnRoomMode, ...) during initialization
-- Handle room mode button press
function LectureHallUIController:handleRoomMode(index)
    if not controls.btnRoomMode[index] then return end
    
    self.state.roomMode = index
    self.state.currentNav = 2
    self.state.lastSourceSelected = 1
    
    -- Update room mode text
    local modeName = roomModeNames[index] or 'Unknown'
    setProp(controls.textRoomMode, "String", 'Room Mode: ' .. modeName)
    
    -- Reset icons and combo strings
    self:resetIcons()
    self:setComboStrings()
    
    -- Update navigation to video routing page
    self:setButtonInterlock(controls.btnNav, 2)
    self:setLayerInterlock(navLayers, 2)
    self:setLayerInterlock(videoRoutingLayers, self.state.roomMode)
    
    -- Enable navigation
    self:enableDisableNav(true)
    
    -- Check source
    self:checkSource()
end

-- Called from: bindArray(controls.txtCombo, ...) during initialization
-- Handle video source combo box selection
function LectureHallUIController:handleVideoSourceSelect(index)
    if not controls.txtCombo[index] then return end
    
    local sourceString = controls.txtCombo[index].String
    if not sourceString or sourceString == 'Select Source' then return end
    
    -- Update video routing
    self:handleVideoSwitch(index, sourceString)
    
    -- Update icon
    self:setIcon(index, sourceString)
    
    -- Show/hide device controls
    self:showHideDeviceControls(sourceString)
    
    -- Track last selected source
    self.state.lastSourceSelected = index
end

-- Called from: bindArray(controls.btnRoomControls, ...) during initialization
-- Handle room controls button press
function LectureHallUIController:handleRoomControls(index)
    if not controls.btnRoomControls[index] then return end
    
    -- Update button interlock
    self:setButtonInterlock(controls.btnRoomControls, index)
    
    -- Hide video routing layers
    self:setLayerInterlock(videoRoutingLayers, 0)
    
    -- Handle room controls check
    self:handleRoomControlsCheck(index)
end

-- Called from: bindArray(controls.btnSystemPower, ...) during initialization
-- Handle system power button press
function LectureHallUIController:handleSystemPower(index)
    if not controls.btnSystemPower[index] then return end
    
    if index == 1 then
        self:powerOn()
    elseif index == 2 then
        self:confirmShutdown()
    elseif index == 3 then
        self:powerOff()
    elseif index == 4 then
        self:cancelShutdown()
    end
end

-- Called from: handleSourceVariableChange()
-- Handle source variable or CSS prefix changes
function LectureHallUIController:handleSourceVariableChange()
    self:initializeTranslationTables()
    self:setComboChoices()
end

-------------------[ Power State Methods ]-------------------
-- Called from: handleSystemPower(1), initialization
-- Power on the system
function LectureHallUIController:powerOn()
    -- Show main state layer
    self:setLayerInterlock(roomStateLayers, 1)
    
    -- Set navigation to first button
    self:setButtonInterlock(controls.btnNav, 1)
    
    -- Show regions and first nav layer
    self:setLayerVisibility('Regions', true)
    self:setLayerInterlock(navLayers, 1)
    
    -- Enable navigation
    self:enableDisableNav(true)
end

-- Called from: handleSystemPower(2)
-- Confirm shutdown (show confirmation layer)
function LectureHallUIController:confirmShutdown()
    self:hideAllLayers()
    self:setLayerVisibility(roomStateLayers[2], true)
end

-- Called from: handleSystemPower(3), initialization
-- Power off the system
function LectureHallUIController:powerOff()
    -- Reset button interlocks
    self:setButtonInterlock(controls.btnRoomControls, 0)
    self:setButtonInterlock(controls.btnNav, 0)
    
    -- Hide all layers
    self:hideAllLayers()
    
    -- Show welcome layer
    self:setLayerInterlock(roomStateLayers, 3)
    
    -- Reset room mode
    self.state.roomMode = 0
    setProp(controls.textRoomMode, "String", 'Room Mode: Not Set')
end

-- Called from: handleSystemPower(4)
-- Cancel shutdown (return to previous state)
function LectureHallUIController:cancelShutdown()
    -- Hide confirmation layer
    self:setLayerVisibility(roomStateLayers[2], false)
    
    -- Show regions and main layer
    self:setLayerVisibility('Regions', true)
    self:setLayerVisibility(roomStateLayers[1], true)
    
    -- Restore navigation state
    self:handleNavigation(self.state.currentNav)
    self:setButtonInterlock(controls.btnNav, self.state.currentNav)
    self:setLayerInterlock(navLayers, self.state.currentNav)
    
    -- Check camera route and source
    self:checkCameraRoute()
    self:checkSource()
end

-------------------[ Event Handler Registration ]-------------------
-- Register all event handlers
function LectureHallUIController:registerEventHandlers()
    local selfRef = self
    
    -- Navigation buttons
    bindArray(controls.btnNav, function(i, ctrl)
        selfRef:handleNavButton(i)
    end)
    
    -- Room mode buttons
    bindArray(controls.btnRoomMode, function(i, ctrl)
        selfRef:handleRoomMode(i)
    end)
    
    -- Video source combo boxes
    bindArray(controls.txtCombo, function(i, ctrl)
        selfRef:handleVideoSourceSelect(i)
    end)
    
    -- Room controls buttons
    bindArray(controls.btnRoomControls, function(i, ctrl)
        selfRef:handleRoomControls(i)
    end)
    
    -- System power buttons
    bindArray(controls.btnSystemPower, function(i, ctrl)
        selfRef:handleSystemPower(i)
    end)
    
    -- Camera router
    bind(controls.camRouter, function()
        selfRef:checkCameraRoute()
    end)
    
    -- Source variables (for dynamic updates)
    forEach(controls.sourceVar, function(i, ctrl)
        if ctrl then
            bind(ctrl, function()
                selfRef:handleSourceVariableChange()
            end)
        end
    end)
    
    -- CSS prefix variable
    bind(controls.cssPrefix, function()
        selfRef:handleSourceVariableChange()
    end)
end

-------------------[ Initialization ]-------------------
-- Create controller instance
local controller = LectureHallUIController.new()

-- Register event handlers
controller:registerEventHandlers()

-- Initialize to power-off state
controller:powerOff()
