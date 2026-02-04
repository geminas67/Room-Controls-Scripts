--[[ 
  Camera Preset Controller - Divisible Space Implementation
  Author: Nikolas Smith, Q-SYS
  2025-11-24
  Firmware Req: 10.0.0
  Version: 4.0
  
  Per-room control structure (control name number = room number):
  
  Room 1:
    * btnCamPreset1[1..n] - preset buttons 1, 2, 3... for Room 1
    * ledPresetMatch1[1..n] - match LEDs for Room 1
    * ledPresetSaved1[1..n] - saved LEDs for Room 1
    * devCams[1] - camera selector for Room 1
    * routerOutput[1] - router output for Room 1
    * compRoomControls[1] - room controls for Room 1
  
  Room 2:
    * btnCamPreset2[1..n] - preset buttons 1, 2, 3... for Room 2
    * ledPresetMatch2[1..n] - match LEDs for Room 2
    * ledPresetSaved2[1..n] - saved LEDs for Room 2
    * devCams[2] - camera selector for Room 2
    * routerOutput[2] - router output for Room 2
    * compRoomControls[2] - room controls for Room 2
  
  Shared:
    * compcamRouter - single shared router selector (all rooms use same router)
    * txtJSONStorage - single shared JSON storage (single source of truth)
  
  Internal Structure:
  - Access pattern: controls.btnCamPreset[roomIndex][presetIndex]
  - Room number encoded in control name (btnCamPreset1 = room 1)
  - Preset number is array index within that control
  - BaseModule pattern with metatable-based construction
  - Direct EventHandler assignments
  
  Key Features:
  - Per-room camera discovery and management
  - Per-room preset management
  - Shared preset storage via txtJSONStorage
  - Cross-room synchronization when presets are saved
  - Single shared router for all rooms
]]--

-- Define control references
-- luacheck: globals Controls Timer Component

-- Function to build per-room preset control arrays
-- Room 1: btnCamPreset1[1], btnCamPreset1[2], btnCamPreset1[3] = presets 1, 2, 3 for room 1
-- Room 2: btnCamPreset2[1], btnCamPreset2[2], btnCamPreset2[3] = presets 1, 2, 3 for room 2
-- Returns array[roomIndex] = array of preset controls for that room
local function buildPerRoomPresetControls(baseName, numRooms)
    local array = {}
    
    -- Build array[roomIndex] = Controls.btnCamPreset{roomIndex} (which is itself an array)
    for roomIndex = 1, numRooms do
        local controlName = baseName .. roomIndex
        local controlArray = Controls[controlName]
        
        if controlArray and type(controlArray) == "table" and #controlArray > 0 then
            array[roomIndex] = controlArray
        else
            -- Room doesn't have this control set
            array[roomIndex] = nil
        end
    end
    
    return #array > 0 and array or nil
end

-- Function to discover number of rooms
-- Room-specific controls like btnCamPreset1, btnCamPreset2, btnCamPreset3 indicate 3 rooms
local function discoverNumRoomsFromControls()
    local maxRooms = 0
    
    -- Check for room-numbered controls: btnCamPreset1, btnCamPreset2, etc.
    for roomIndex = 1, 10 do
        if Controls["btnCamPreset" .. roomIndex] then
            maxRooms = roomIndex
        else
            break
        end
    end
    
    -- Fallback: Check devCams array control
    if maxRooms == 0 and Controls.devCams then
        for i = 1, 10 do
            if Controls.devCams[i] then
                maxRooms = i
            else
                break
            end
        end
    end
    
    return maxRooms
end

-- Build control references
-- Per-room control structure:
--   Room 1: btnCamPreset1[1..n], ledPresetMatch1[1..n], devCams[1]
--   Room 2: btnCamPreset2[1..n], ledPresetMatch2[1..n], devCams[2]
-- Internal access: controls.btnCamPreset[roomIndex][presetIndex]
local numRooms = discoverNumRoomsFromControls()
local controls = {
    devCams = Controls.devCams,  -- Array control: devCams[1], devCams[2]
    routerOutput = Controls.routerOutput,  -- Array control: routerOutput[1], routerOutput[2]
    compRoomControls = Controls.compRoomControls,  -- Array control: compRoomControls[1], compRoomControls[2]
    btnCamPreset = buildPerRoomPresetControls("btnCamPreset", numRooms),  -- [roomIndex] = array of presets
    ledPresetMatch = buildPerRoomPresetControls("ledPresetMatch", numRooms),  -- [roomIndex] = array of LEDs
    ledPresetSaved = buildPerRoomPresetControls("ledPresetSaved", numRooms),  -- [roomIndex] = array of LEDs
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,  -- Single shared control
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,  -- Single shared control
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus
}

-- Configuration
local defaultConfig = {
    presetTolerance = 0.02,  -- Tighter tolerance for better precision
    holdTime = 3.0,
    ledOnTime = 2.5,
    routerOutputs = {"select.1"},
    defaultCamera = "devCam01",
    defaultPreset = 1,
    maxRetries = 3,
    debounceDelay = 0.1
}

-- Component types for discovery
local componentTypes = {
    camera = "onvif_camera_operative",
    videoRouter = "video_router",
    roomControls = "device_controller_script"
}

-- Required libraries
rapidjson = require("rapidjson")

-------------------[ Utility Functions - Defined First ]-------------------
-- Critical: These must be defined before any code that uses them
local function isArr(control)
    return type(control) == "table" and #control > 0
end

local function setProp(obj, prop, value)
    if not obj then return false end
    if obj[prop] == value then return false end
    obj[prop] = value
    return true
end

local function forEach(array, func)
    if not array or type(array) ~= "table" then return end
    for i, item in ipairs(array) do
        if item and func then func(item, i) end
    end
end

local function getControlArray(control)
    if not control then return {} end
    return isArr(control) and control or {control}
end

local function bind(ctrl, handler) 
    if ctrl and handler then 
        ctrl.EventHandler = handler 
        return true
    end
    return false
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local controlArray = getControlArray(ctrls)
    local bindCount = 0
    for i, ctrl in ipairs(controlArray) do
        if ctrl then
            if bind(ctrl, function(ctl) 
                local success, err = pcall(handler, i, ctl)
                if not success then
                    print("Event handler error for control index " .. i .. ": " .. tostring(err))
                end
            end) then
                bindCount = bindCount + 1
            end
        end
    end
    return bindCount
end

local function resetComponentsArray(components, arrayName)
    if components and components[arrayName] then
        components[arrayName] = {}
        return true
    end
    return false
end


local function cleanupComponentHandlers(oldComponent, controlNames, debugCallback)
    -- CRITICAL: Clean up old event handlers before reassigning (Refactoring Pattern #33)
    -- Prevents handler accumulation in divisible space scenarios
    if not oldComponent or not controlNames then return 0 end
    
    local cleaned = 0
    for _, controlName in ipairs(controlNames) do
        if oldComponent[controlName] and oldComponent[controlName].EventHandler then
            oldComponent[controlName].EventHandler = nil
            cleaned = cleaned + 1
        end
    end
    
    if debugCallback and cleaned > 0 then
        debugCallback(string.format("Cleaned up %d event handler(s) from old component", cleaned))
    end
    
    return cleaned
end

local function validateComponent(componentName)
    if not componentName or componentName == "" then return false end
    
    local success, component = pcall(function()
        return Component.New(componentName)
    end)
    
    if not success or not component then return false end
    
    local success2, controls = pcall(function()
        return Component.GetControls(component)
    end)
    
    return success2 and controls and #controls > 0
end

local function safeStringMatch(str, pattern)
    if not str or not pattern then return nil end
    local success, result = pcall(function()
        return str:match(pattern)
    end)
    return success and result or nil
end

-------------------[ Base Module Class ]-------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    return self
end

function BaseModule:debug(message)
    if self.controller and self.controller.debugging then
        print(string.format("[%s] %s", self.name, message))
    end
end

function BaseModule:error(message)
    print(string.format("[%s ERROR] %s", self.name, message))
end

-------------------[ JSON Module ]-------------------
local JSONModule = setmetatable({}, {__index = BaseModule})
JSONModule.__index = JSONModule

-- luacheck: ignore 113
function JSONModule.new(controller)
    local self = BaseModule.new(controller, "JSON")
    setmetatable(self, JSONModule)
    return self
end

function JSONModule:save()
    if not self.controller.components.presets then 
        self:error("No presets data to save")
        return false 
    end
    
    local success, strTemp = pcall(function()
        return rapidjson.encode(self.controller.components.presets, {pretty=true, sort_keys=true})
    end)
    
    if not success then
        self:error("Failed to encode JSON data: " .. tostring(strTemp))
        return false
    end
    
    if strTemp ~= controls.txtJSONStorage.String then
        -- Set flag to prevent reload on own save (EventHandler fires on external changes)
        self.controller.state.isSavingJSON = true
        controls.txtJSONStorage.String = strTemp
        self.controller.state.isSavingJSON = false
        self:debug("JSON data saved successfully")
        return true
    else
        self:debug("No new JSON data to save")
        return false
    end
end

function JSONModule:load()
    if not controls.txtJSONStorage.String or controls.txtJSONStorage.String == "" then
        self:debug("JSON storage is empty - will initialize with defaults")
        return false
    end
    
    local success, tblTemp = pcall(function()
        return rapidjson.decode(controls.txtJSONStorage.String)
    end)
    
    if success and type(tblTemp) == "table" then
        self.controller.components.presets = tblTemp
        self:debug("JSON data loaded successfully")
        return true
    else
        self:error("Failed to decode JSON data: " .. tostring(tblTemp))
        return false
    end
end

function JSONModule:reloadFromStorage()
    -- Reload presets from storage and update UI for all rooms
    -- CRITICAL: Do NOT call save() here - txtJSONStorage is the single source of truth
    -- Load flow: Storage -> Local cache -> Update UI (no write back)
    if self:load() then
        -- Update preset match LEDs for all rooms to reflect changes from other instance
        if self.controller.cameraModule then
            for roomIndex = 1, self.controller.numRooms do
                self.controller.cameraModule:updatePresetMatchLEDs(roomIndex)
            end
        end
        self:debug("Presets reloaded from external instance - UI synchronized for all rooms")
        return true
    end
    return false
end

-------------------[ Camera Module ]-------------------
local CameraModule = setmetatable({}, {__index = BaseModule})
CameraModule.__index = CameraModule

-- luacheck: ignore 113
function CameraModule.new(controller)
    local self = BaseModule.new(controller, "Camera")
    setmetatable(self, CameraModule)
    self.debounceTimers = {}  -- Per-room debounce timers
    return self
end

function CameraModule:getDebounceTimer(roomIndex)
    if not self.debounceTimers[roomIndex] then
        self.debounceTimers[roomIndex] = Timer.New()
    end
    return self.debounceTimers[roomIndex]
end

function CameraModule:discoverCameras(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for camera discovery: " .. tostring(roomIndex))
        return {}
    end
    
    if not self.controller.components.cameras[roomIndex] then
        self.controller.components.cameras[roomIndex] = {}
    end
    
    local cameraNames = {}
    local success, components = pcall(Component.GetComponents)
    
    if not success or not components then
        self:error("Failed to get components for camera discovery (room " .. roomIndex .. ")")
        return cameraNames
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type == componentTypes.camera and tblComponents.Name then
            if validateComponent(tblComponents.Name) then
                table.insert(cameraNames, tblComponents.Name)
                self.controller.components.cameras[roomIndex][tblComponents.Name] = Component.New(tblComponents.Name)
                self:debug(string.format("Room[%d] Found and validated camera: %s", roomIndex, tblComponents.Name))
            else
                self:error("Invalid camera component: " .. tblComponents.Name)
            end
        end
    end
    
    table.sort(cameraNames)  -- Ensure consistent ordering
    return cameraNames
end

function CameraModule:initializePresets(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for preset initialization: " .. tostring(roomIndex))
        return
    end
    
    local cameraNames = {}
    local roomCameras = self.controller.components.cameras[roomIndex] or {}
    for name, _ in pairs(roomCameras) do
        table.insert(cameraNames, name)
    end
    
    if #cameraNames == 0 then
        self:debug(string.format("Room[%d] No cameras to initialize presets for", roomIndex))
        return
    end
    
    local presetControls = getControlArray(controls.btnCamPreset[roomIndex])
    if #presetControls == 0 then
        self:error(string.format("Room[%d] No preset controls available", roomIndex))
        return
    end
    
    for _, camName in pairs(cameraNames) do
        if not self.controller.components.presets[camName] then
            self.controller.components.presets[camName] = {}
            for i = 1, #presetControls do
                self.controller.components.presets[camName][i] = "0 0 0"
            end
            self:debug(string.format("Room[%d] Initialized presets for camera: %s", roomIndex, camName))
        end
    end
end

function CameraModule:updatePresetMatchLEDs(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for LED update: " .. tostring(roomIndex))
        return
    end
    
    -- Debounce rapid updates during camera movement
    local debounceTimer = self:getDebounceTimer(roomIndex)
    debounceTimer:Stop()
    -- luacheck: ignore 122
    debounceTimer.EventHandler = function()
        self:_updatePresetMatchLEDsInternal(roomIndex)
    end
    debounceTimer:Start(self.controller.config.debounceDelay)
end

function CameraModule:_updatePresetMatchLEDsInternal(roomIndex)
    if not controls.devCams or not controls.devCams[roomIndex] then
        return
    end
    
    local camName = controls.devCams[roomIndex].String or ""
    if not camName or camName == "" then
        -- Clear all LEDs when no camera selected
        local ledControls = getControlArray(controls.ledPresetMatch[roomIndex])
        forEach(ledControls, function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local roomCameras = self.controller.components.cameras[roomIndex] or {}
    local camera = roomCameras[camName]
    if not camera then
        self:debug(string.format("Room[%d] Camera not found: %s", roomIndex, camName))
        return
    end
    
    -- Skip updates if camera is moving for better performance
    local isMoving = camera["is.moving"] and camera["is.moving"].Boolean or false
    if isMoving then
        local ledControls = getControlArray(controls.ledPresetMatch[roomIndex])
        forEach(ledControls, function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local currentPreset = camera["ptz.preset"] and camera["ptz.preset"].String or ""
    if currentPreset == "" then
        -- Only log this once every 5 seconds to prevent spam
        if not self.lastEmptyPresetLog or (os.clock() - self.lastEmptyPresetLog) > 5 then
            self:debug(string.format("Room[%d] No current preset available for camera: %s", roomIndex, camName))
            self.lastEmptyPresetLog = os.clock()
        end
        -- Clear LEDs when no preset data available
        local ledControls = getControlArray(controls.ledPresetMatch[roomIndex])
        forEach(ledControls, function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    -- Additional validation for preset format before processing
    if type(currentPreset) ~= "string" or currentPreset:match("^%s*$") then
        -- Only log malformed preset data once every 5 seconds
        if not self.lastMalformedPresetLog or (os.clock() - self.lastMalformedPresetLog) > 5 then
            self:debug(string.format("Room[%d] Malformed preset data for camera %s: '%s' (type: %s)", 
                roomIndex, camName, tostring(currentPreset), type(currentPreset)))
            self.lastMalformedPresetLog = os.clock()
        end
        -- Clear LEDs when preset data is malformed
        local ledControls = getControlArray(controls.ledPresetMatch[roomIndex])
        forEach(ledControls, function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local savedPresets = self.controller.components.presets[camName] or {}
    
    -- Update LEDs efficiently with early returns
    local ledControls = getControlArray(controls.ledPresetMatch[roomIndex])
    for i, led in ipairs(ledControls) do
        local presetMatches = savedPresets[i] and 
            self:presetsMatch(currentPreset, savedPresets[i], self.controller.config.presetTolerance)
        setProp(led, "Boolean", presetMatches or false)
    end
end

function CameraModule:presetsMatch(current, saved, tolerance)
    if not current or not saved or saved == "0 0 0" then return false end
    
    -- Early return for exact matches
    if current == saved then return true end
    
    -- Simplified preset parsing for space-separated decimal values
    local function parsePreset(presetString)
        if not presetString or type(presetString) ~= "string" or presetString == "" then
            return nil, nil, nil
        end
        
        -- Clean whitespace and parse space-separated decimal values
        local cleanString = presetString:gsub("%s+", " "):match("^%s*(.-)%s*$")
        
        -- Direct string matching - more reliable than safeStringMatch wrapper
        local pan, tilt, zoom = cleanString:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        
        if pan and tilt and zoom then
            return tonumber(pan), tonumber(tilt), tonumber(zoom)
        end
        
        -- If standard pattern fails, try simpler approach
        local parts = {}
        for part in cleanString:gmatch("([%d%.%-]+)") do
            table.insert(parts, part)
        end
        
        if #parts == 3 then
            return tonumber(parts[1]), tonumber(parts[2]), tonumber(parts[3])
        end
        
        return nil, nil, nil
    end
    
    local currPan, currTilt, currZoom = parsePreset(current)
    local savedPan, savedTilt, savedZoom = parsePreset(saved)
    
    if not (currPan and currTilt and currZoom and savedPan and savedTilt and savedZoom) then
        -- Enhanced error logging with rate limiting to prevent spam
        if not self.lastParseError or (os.clock() - self.lastParseError) > 5 then
            self:debug(string.format("Failed to parse preset values - Current: '%s' (type: %s), Saved: '%s' (type: %s)", 
                tostring(current), type(current), tostring(saved), type(saved)))
            self.lastParseError = os.clock()
        end
        return false
    end
    
    -- Use tolerance comparison with early returns for performance
    return math.abs(currPan - savedPan) <= tolerance and
           math.abs(currTilt - savedTilt) <= tolerance and
           math.abs(currZoom - savedZoom) <= tolerance
end

function CameraModule:savePreset(roomIndex, presetIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for preset save: " .. tostring(roomIndex))
        return false
    end
    
    if not controls.devCams or not controls.devCams[roomIndex] then
        self:error(string.format("Room[%d] devCams control not available", roomIndex))
        return false
    end
    
    local camName = controls.devCams[roomIndex].String or ""
    if not camName or camName == "" then
        self:error(string.format("Room[%d] No camera selected for preset save", roomIndex))
        return false
    end
    
    local roomCameras = self.controller.components.cameras[roomIndex] or {}
    local camera = roomCameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:error(string.format("Room[%d] Invalid camera or missing preset control: %s", roomIndex, camName))
        return false
    end
    
    local currentPreset = camera["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        self:error(string.format("Room[%d] No current preset data available for: %s", roomIndex, camName))
        return false
    end
    
    if not self.controller.components.presets[camName] then
        self.controller.components.presets[camName] = {}
    end
    
    local oldPreset = self.controller.components.presets[camName][presetIndex] or "not set"
    self.controller.components.presets[camName][presetIndex] = currentPreset
    self:debug(string.format("Room[%d] Saved %s Preset[%d]: %s (was: %s)", 
        roomIndex, camName, presetIndex, currentPreset, oldPreset))
    
    -- Auto-save to JSON with error handling
    if not self.controller.jsonModule:save() then
        self:error("Failed to save preset data to JSON storage")
    end
    
    return true
end

function CameraModule:recallPreset(roomIndex, presetIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for preset recall: " .. tostring(roomIndex))
        return false
    end
    
    if not controls.devCams or not controls.devCams[roomIndex] then
        self:error(string.format("Room[%d] devCams control not available", roomIndex))
        return false
    end
    
    local camName = controls.devCams[roomIndex].String or ""
    if not camName or camName == "" then
        self:error(string.format("Room[%d] No camera selected for preset recall", roomIndex))
        return false
    end
    
    local roomCameras = self.controller.components.cameras[roomIndex] or {}
    local camera = roomCameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:error(string.format("Room[%d] Invalid camera or missing preset control: %s", roomIndex, camName))
        return false
    end
    
    local savedPresets = self.controller.components.presets[camName]
    if not savedPresets or not savedPresets[presetIndex] then
        self:error(string.format("Room[%d] No saved preset[%d] for camera: %s", roomIndex, presetIndex, camName))
        return false
    end
    
    local preset = savedPresets[presetIndex]
    if preset == "0 0 0" then
        self:error(string.format("Room[%d] Preset[%d] not initialized for camera: %s", roomIndex, presetIndex, camName))
        return false
    end
    
    camera["ptz.preset"].String = preset
    self:debug(string.format("Room[%d] Recalled %s Preset[%d]: %s", roomIndex, camName, presetIndex, preset))
    return true
end

-------------------[ Router Module ]-------------------
local RouterModule = setmetatable({}, {__index = BaseModule})
RouterModule.__index = RouterModule

-- luacheck: ignore 113
function RouterModule.new(controller)
    local self = BaseModule.new(controller, "Router")
    setmetatable(self, RouterModule)
    return self
end

function RouterModule:discoverRouters(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for router discovery: " .. tostring(roomIndex))
        return
    end
    
    if not self.controller.components.routers[roomIndex] then
        self.controller.components.routers[roomIndex] = {}
    end
    
    local success, components = pcall(Component.GetComponents)
    if not success or not components then
        self:error(string.format("Room[%d] Failed to get components for router discovery", roomIndex))
        return
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type and tblComponents.Type:match(componentTypes.videoRouter) and tblComponents.Name then
            if validateComponent(tblComponents.Name) then
                self.controller.components.routers[roomIndex][tblComponents.Name] = Component.New(tblComponents.Name)
                self:debug(string.format("Room[%d] Found and validated router: %s", roomIndex, tblComponents.Name))
            else
                self:error("Invalid router component: " .. tblComponents.Name)
            end
        end
    end
end

function RouterModule:discoverRoomControls(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for room controls discovery: " .. tostring(roomIndex))
        return
    end
    
    if not controls.compRoomControls or not controls.compRoomControls[roomIndex] then
        return
    end
    
    local componentName = controls.compRoomControls[roomIndex].String
    if not componentName or componentName == "" then
        self:debug(string.format("Room[%d] No room controls component selected", roomIndex))
        return
    end
    
    if validateComponent(componentName) then
        self.controller.components.roomControls[roomIndex] = Component.New(componentName)
        self:debug(string.format("Room[%d] Found and validated room control: %s", roomIndex, componentName))
    else
        self:error(string.format("Room[%d] Invalid room control component: %s", roomIndex, componentName))
    end
end

function RouterModule:setupRouterSync(roomIndex)
    if not roomIndex or roomIndex < 1 or roomIndex > self.controller.numRooms then
        self:error("Invalid room index for router sync: " .. tostring(roomIndex))
        return false
    end
    
    if not controls.compcamRouter then
        self:debug(string.format("Room[%d] No router selector control available", roomIndex))
        return false
    end
    
    local selectedRouterName = controls.compcamRouter.String
    
    if not selectedRouterName or selectedRouterName == "" then
        self:debug(string.format("Room[%d] No router selected for sync setup", roomIndex))
        return false
    end
    
    -- Clean up old router handlers before setting up new ones (Refactoring Pattern #33)
    if self.controller.state.currentRouters and self.controller.state.currentRouters[roomIndex] then
        local outputControl = controls.routerOutput and controls.routerOutput[roomIndex] and controls.routerOutput[roomIndex].String or "select.1"
        cleanupComponentHandlers(
            self.controller.state.currentRouters[roomIndex],
            {outputControl},
            function(msg) self:debug(msg) end
        )
    end
    
    local roomRouters = self.controller.components.routers[roomIndex] or {}
    local router = roomRouters[selectedRouterName]
    if not router then
        self:error(string.format("Room[%d] Router not found: %s", roomIndex, selectedRouterName))
        return false
    end
    
    -- Cache current router for cleanup on next change
    if not self.controller.state.currentRouters then
        self.controller.state.currentRouters = {}
    end
    self.controller.state.currentRouters[roomIndex] = router
    
    self:debug(string.format("Room[%d] Setting up router sync for: %s", roomIndex, selectedRouterName))
    
    -- Use dynamic routerOutput control instead of static config
    local routerOutput = controls.routerOutput and controls.routerOutput[roomIndex]
    local routerOutputs = routerOutput and routerOutput.String ~= "" 
        and {routerOutput.String} 
        or self.controller.config.routerOutputs or {"select.1"}
    local successCount = 0
    
    if not controls.devCams or not controls.devCams[roomIndex] then
        self:error(string.format("Room[%d] devCams control not available for router sync", roomIndex))
        return false
    end
    
    for _, output in ipairs(routerOutputs) do
        if router[output] then
            if self:syncCamChoiceWithRouter(roomIndex, router, output, controls.devCams[roomIndex]) then
                successCount = successCount + 1
            end
        else
            self:error(string.format("Room[%d] Router output %s not found", roomIndex, output))
        end
    end
    
    self:debug(string.format("Room[%d] Router sync setup complete: %d/%d outputs configured", 
        roomIndex, successCount, #routerOutputs))
    return successCount > 0
end

function RouterModule:syncCamChoiceWithRouter(roomIndex, router, routerKey, camChoiceControl)
    if not router or not router[routerKey] or not camChoiceControl then
        self:error(string.format("Room[%d] Invalid parameters for router sync", roomIndex))
        return false
    end
    
    -- CRITICAL: Use direct EventHandler assignment instead of bind()
    -- This prevents intermittent failures and improves reliability
    -- luacheck: ignore 122
    router[routerKey].EventHandler = function()
        local routedInputIndex = router[routerKey].Value
        
        -- Validate choices exist before accessing
        if not camChoiceControl.Choices then
            self:debug(string.format("Room[%d] Camera choices not yet initialized", roomIndex))
            return
        end
        
        if routedInputIndex and routedInputIndex > 0 and routedInputIndex <= #camChoiceControl.Choices then
            -- Use setProp for Value to avoid redundant updates
            if setProp(camChoiceControl, "Value", routedInputIndex) then
                camChoiceControl.String = camChoiceControl.Choices[routedInputIndex]
                self:debug(string.format("Room[%d] Router sync: %s -> Camera: %s", roomIndex, routerKey, camChoiceControl.String))
            end
            
            -- Update LED states after camera selection changes
            self.controller.cameraModule:updatePresetMatchLEDs(roomIndex)
        else
            self:debug(string.format("Room[%d] Invalid router input index: %s (choices: %d)", 
                roomIndex, tostring(routedInputIndex), #camChoiceControl.Choices))
        end
    end
    
    -- Initialize state
    if router[routerKey].EventHandler then
        router[routerKey].EventHandler()
        self:debug(string.format("Room[%d] Router %s event handler configured and initialized", roomIndex, routerKey))
        return true
    end
    
    return false
end

-------------------[ CameraPresetController (Main Orchestrator) ]-------------------
local CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

-- luacheck: ignore 113
function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Configuration with defaults (set these first, before any methods that might log)
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Merge user config with defaults
    self.config = {}
    for key, value in pairs(defaultConfig) do
        self.config[key] = (config and config[key]) or value
    end
    
    -- Determine number of rooms from control array lengths (BEFORE validateControls)
    self.numRooms = self:discoverNumRooms()
    if self.numRooms == 0 then
        self:error("No rooms detected - check control arrays")
        return nil
    end
    
    -- Validate required controls after numRooms is discovered (Refactoring Guideline #14)
    if not self:validateControls() then
        print("❌ ERROR: Required controls missing - initialization aborted")
        return nil
    end
    
    -- Component storage - per-room indexed
    self.components = {
        cameras = {},  -- cameras[roomIndex][cameraName] = component
        presets = {},  -- Shared across all rooms: presets[cameraName][presetIndex]
        routers = {},  -- routers[roomIndex][routerName] = component
        roomControls = {},  -- roomControls[roomIndex] = component
        callSync = nil
    }
    
    -- State tracking - per-room indexed
    self.state = {
        longPressed = {},  -- longPressed[roomIndex][presetIndex]
        countdownTimers = {},  -- countdownTimers[roomIndex][presetIndex]
        ledTimers = {},  -- ledTimers[roomIndex][presetIndex]
        initialized = false,
        isSavingJSON = false,  -- Flag to prevent reload on own saves
        currentRouters = {}  -- currentRouters[roomIndex] = router component
    }
    
    -- Initialize modules
    self.jsonModule = JSONModule.new(self)
    self.cameraModule = CameraModule.new(self)
    self.routerModule = RouterModule.new(self)
    
    -- Initialize and register events
    self:registerEventHandlers()
    self:init()
    
    return self
end

function CameraPresetController:debug(message)
    if self.debugging then
        print(string.format("[CameraPresetController] %s", message))
    end
end

function CameraPresetController:error(message)
    print(string.format("[CameraPresetController ERROR] %s", message))
end

function CameraPresetController:discoverNumRooms()
    -- Determine number of rooms from array control lengths
    -- Room-level controls: devCams[1-3], routerOutput[1-3], compRoomControls[1-3] are array controls
    -- Per-room preset controls: btnCamPreset1, btnCamPreset2, etc. are numbered array controls
    
    local maxLength = 0
    local lengths = {}
    
    -- Helper function to count array elements by checking if they exist
    local function countArrayElements(control)
        if not control then return 0 end
        local count = 0
        for i = 1, 10 do
            if control[i] then
                count = i
            else
                break
            end
        end
        return count
    end
    
    -- Check room-level array controls
    if controls.devCams then
        local length = countArrayElements(controls.devCams)
        if length > 0 then
            lengths.devCams = length
            if length > maxLength then
                maxLength = length
            end
        end
    end
    
    if controls.routerOutput then
        local length = countArrayElements(controls.routerOutput)
        if length > 0 then
            lengths.routerOutput = length
            if length > maxLength then
                maxLength = length
            end
        end
    end
    
    if controls.compRoomControls then
        local length = countArrayElements(controls.compRoomControls)
        if length > 0 then
            lengths.compRoomControls = length
            if length > maxLength then
                maxLength = length
            end
        end
    end
    
    -- Check numbered preset arrays (btnCamPreset1, btnCamPreset2, etc.)
    local presetControls = {
        btnCamPreset = controls.btnCamPreset,
        ledPresetMatch = controls.ledPresetMatch,
        ledPresetSaved = controls.ledPresetSaved
    }
    
    for controlName, control in pairs(presetControls) do
        if control and isArr(control) then
            local length = #control
            lengths[controlName] = length
            if length > maxLength then
                maxLength = length
            end
        end
    end
    
    -- Validate all arrays have same length (or handle gracefully)
    for controlName, length in pairs(lengths) do
        if length > 0 and length ~= maxLength then
            self:error(string.format("Control array length mismatch: %s has %d elements, expected %d", 
                controlName, length, maxLength))
        end
    end
    
    if maxLength == 0 then
        self:error("No rooms discovered - check that array controls exist (devCams[1], btnCamPreset1[1], etc.)")
    else
        self:debug(string.format("Discovered %d rooms from array controls", maxLength))
    end
    
    return maxLength
end

function CameraPresetController:validateControls()
    -- Comprehensive control validation (Refactoring Guideline #14)
    -- Array controls: devCams[1], devCams[2], btnCamPreset1[1], etc.
    
    -- Validate required room-level array controls
    -- In Q-Sys, check if the control exists
    if not Controls.devCams then
        self:error("devCams control not found")
        return false
    end
    
    -- Try to access first element to verify it's an array (but don't fail if we can't check it)
    -- In Q-Sys, array controls may not be directly checkable, so we'll verify during discovery
    local success, firstElement = pcall(function() 
        return Controls.devCams[1] 
    end)
    if not success then
        -- If pcall fails, it might be because we can't check array elements this way
        -- Let discoverNumRooms handle the actual validation
        self:debug("Note: Could not verify devCams array elements directly - will check during room discovery")
    elseif not firstElement then
        self:error("devCams must be an array control with at least one element (devCams[1], devCams[2], etc.)")
        return false
    end
    
    -- Validate required preset controls exist (per-room)
    if not Controls.btnCamPreset1 then
        self:error("Missing required preset controls (expected btnCamPreset1[], btnCamPreset2[], etc.)")
        return false
    end
    
    -- Validate per-room preset arrays were built successfully
    if not controls.btnCamPreset or not isArr(controls.btnCamPreset) then
        self:error("btnCamPreset per-room arrays not built successfully")
        return false
    end
    
    if not controls.ledPresetMatch or not isArr(controls.ledPresetMatch) then
        self:error("ledPresetMatch per-room arrays not built successfully")
        return false
    end
    
    -- Validate each room has its control sets
    for roomIndex = 1, self.numRooms do
        if not controls.btnCamPreset[roomIndex] then
            self:error(string.format("btnCamPreset%d controls not found for room %d", roomIndex, roomIndex))
            return false
        end
        if not controls.ledPresetMatch[roomIndex] then
            self:error(string.format("ledPresetMatch%d controls not found for room %d", roomIndex, roomIndex))
            return false
        end
        self:debug(string.format("Room[%d] has %d preset buttons", roomIndex, #controls.btnCamPreset[roomIndex]))
    end
    
    -- Validate optional room-level array controls if present
    if Controls.routerOutput then
        self:debug("routerOutput control found (optional)")
    end
    
    if Controls.compRoomControls then
        self:debug("compRoomControls control found (optional)")
    end
    
    -- Validate txtJSONStorage is a single control (not an array)
    if not controls.txtJSONStorage then
        self:error("txtJSONStorage is required (shared across all rooms)")
        return false
    end
    
    if isArr(controls.txtJSONStorage) then
        self:error("txtJSONStorage must be a single control (shared across all rooms), not an array")
        return false
    end
    
    self:debug(string.format("Control validation passed - %d rooms detected", self.numRooms))
    return true
end

function CameraPresetController:init()
    if self.state.initialized then
        self:debug("Already initialized, skipping...")
        return
    end
    
    self:debug(string.format("Starting divisible space initialization for %d rooms...", self.numRooms))
    
    -- Load existing presets from JSON first (shared across all rooms)
    if not self.jsonModule:load() then
        self:debug("No existing JSON data found, will create new preset structure")
    end
    
    -- Initialize per-room components
    for roomIndex = 1, self.numRooms do
        self:debug(string.format("Initializing room %d...", roomIndex))
        
        -- Discover components for this room
        local cameraNames = self.cameraModule:discoverCameras(roomIndex)
        if #cameraNames == 0 then
            self:error(string.format("Room[%d] No cameras discovered - check camera components", roomIndex))
        else
            table.sort(cameraNames)
            for i, name in ipairs(cameraNames) do
                self:debug(string.format("Room[%d] Discovered camera[%d]: %s", roomIndex, i, name))
            end
        end
        
        self.routerModule:discoverRouters(roomIndex)
        self.routerModule:discoverRoomControls(roomIndex)
        
        -- Initialize preset structure for cameras in this room
        self.cameraModule:initializePresets(roomIndex)
        
        -- Set up camera monitoring with enhanced error handling
        self:setupCameraMonitoring(roomIndex, cameraNames)
        
        -- Set up UI state BEFORE router sync (choices must exist first)
        self:setupCameraChoices(roomIndex, cameraNames)
        self:updateRouterChoices(roomIndex)
        self:updateRouterOutputChoices(roomIndex)
    end
    
    -- Setup router synchronization for all rooms (after UI choices are populated)
    for roomIndex = 1, self.numRooms do
        self.routerModule:setupRouterSync(roomIndex)
    end
    
    -- Initial LED update for all rooms
    for roomIndex = 1, self.numRooms do
        self.cameraModule:updatePresetMatchLEDs(roomIndex)
    end
    
    -- Set status to OK using setProp to prevent redundant updates
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "OK")
        setProp(controls.txtStatus, "Value", 0)
    end
    
    self.state.initialized = true
    self:debug(string.format("Divisible space initialization complete - %d rooms", self.numRooms))
end

function CameraPresetController:getRouterCount(roomIndex)
    if not roomIndex then
        -- Return total count across all rooms
        local total = 0
        for i = 1, self.numRooms do
            local roomRouters = self.components.routers[i] or {}
            for _ in pairs(roomRouters) do
                total = total + 1
            end
        end
        return total
    end
    
    local roomRouters = self.components.routers[roomIndex] or {}
    local count = 0
    for _ in pairs(roomRouters) do
        count = count + 1
    end
    return count
end

function CameraPresetController:registerEventHandlers()
    -- CRITICAL: Use direct EventHandler assignments for maximum reliability
    -- Using array-based handler registration for divisible space
    
    -- JSON storage cross-instance synchronization (shared across all rooms)
    if controls.txtJSONStorage then
        -- luacheck: ignore 122
        controls.txtJSONStorage.EventHandler = function()
            -- Only reload if change came from another instance (not our own save)
            if not self.state.isSavingJSON then
                self:debug("JSON storage changed externally - reloading presets for all rooms...")
                self.jsonModule:reloadFromStorage()
            end
        end
    end
    
    -- Per-room camera selection handlers
    if controls.devCams then
        bindArray(controls.devCams, function(roomIndex, ctl)
            self.cameraModule:updatePresetMatchLEDs(roomIndex)
        end)
    end
    
    -- Shared router selector handler (single control for all rooms)
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            -- Update all rooms when shared router changes
            for roomIndex = 1, self.numRooms do
                self:updateRouterOutputChoices(roomIndex)
                self.routerModule:setupRouterSync(roomIndex)
            end
        end)
    end
    
    if controls.routerOutput then
        bindArray(controls.routerOutput, function(roomIndex, ctl)
            self.routerModule:setupRouterSync(roomIndex)
        end)
    end
    
    -- Configuration controls (shared)
    if controls.knbledOnTime then
        -- luacheck: ignore 122
        controls.knbledOnTime.EventHandler = function()
            local newValue = controls.knbledOnTime.Value
            if newValue and newValue > 0 then
                self.config.ledOnTime = newValue
                self:debug("LED On Time updated to: " .. self.config.ledOnTime)
            end
        end
    end
    
    if controls.knbHoldTime then
        -- luacheck: ignore 122
        controls.knbHoldTime.EventHandler = function()
            local newValue = controls.knbHoldTime.Value
            if newValue and newValue > 0 then
                self.config.holdTime = newValue
                self:debug("Hold Time updated to: " .. self.config.holdTime)
            end
        end
    end
    
    self:debug("Event handlers registered for divisible space")
    
    -- Initialize preset button handlers for all rooms
    self:initPresetButtonHandlers()
end

function CameraPresetController:initPresetButtonHandlers()
    if not controls.btnCamPreset then
        self:error("No preset button controls available")
        return
    end
    
    -- Initialize timers and button handlers for each room and preset
    for roomIndex = 1, self.numRooms do
        if not controls.btnCamPreset[roomIndex] then
            self:error(string.format("Room[%d] btnCamPreset array not available", roomIndex))
            goto continue
        end
        
        local presetButtons = getControlArray(controls.btnCamPreset[roomIndex])
        
        if not self.state.longPressed[roomIndex] then
            self.state.longPressed[roomIndex] = {}
        end
        if not self.state.countdownTimers[roomIndex] then
            self.state.countdownTimers[roomIndex] = {}
        end
        if not self.state.ledTimers[roomIndex] then
            self.state.ledTimers[roomIndex] = {}
        end
        
        for presetIndex, btn in ipairs(presetButtons) do
            if btn then
                self.state.longPressed[roomIndex][presetIndex] = false
                self.state.countdownTimers[roomIndex][presetIndex] = Timer.New()
                self.state.ledTimers[roomIndex][presetIndex] = Timer.New()
                
                -- Long press detection timer
                -- luacheck: ignore 122
                self.state.countdownTimers[roomIndex][presetIndex].EventHandler = function()
                    self.state.countdownTimers[roomIndex][presetIndex]:Stop()
                    if presetButtons[presetIndex] and presetButtons[presetIndex].Boolean then
                        self.state.longPressed[roomIndex][presetIndex] = true
                        self:handlePresetSave(roomIndex, presetIndex)
                    end
                end
                
                -- LED flash timer
                -- luacheck: ignore 122
                self.state.ledTimers[roomIndex][presetIndex].EventHandler = function()
                    self.state.ledTimers[roomIndex][presetIndex]:Stop()
                    if controls.ledPresetSaved and controls.ledPresetSaved[roomIndex] then
                        local savedLEDs = getControlArray(controls.ledPresetSaved[roomIndex])
                        if savedLEDs[presetIndex] then
                            setProp(savedLEDs[presetIndex], "Boolean", false)
                        end
                    end
                end
                
                -- Button press/release handler - DIRECT assignment for reliability
                -- luacheck: ignore 122
                btn.EventHandler = function()
                    if presetButtons[presetIndex].Boolean then
                        -- Button pressed - start long press timer
                        self.state.longPressed[roomIndex][presetIndex] = false
                        self.state.countdownTimers[roomIndex][presetIndex]:Start(self.config.holdTime)
                    else
                        -- Button released
                        self.state.countdownTimers[roomIndex][presetIndex]:Stop()
                        if not self.state.longPressed[roomIndex][presetIndex] then
                            -- Short press - recall preset
                            self:handlePresetRecall(roomIndex, presetIndex)
                        end
                    end
                end
            end
        end
        
        self:debug(string.format("Room[%d] Initialized %d preset button handlers", roomIndex, #presetButtons))
        ::continue::
    end
end

function CameraPresetController:handlePresetSave(roomIndex, presetIndex)
    if self.cameraModule:savePreset(roomIndex, presetIndex) then
        -- Flash the LED to indicate successful save using setProp
        if controls.ledPresetSaved and controls.ledPresetSaved[roomIndex] then
            local savedLEDs = getControlArray(controls.ledPresetSaved[roomIndex])
            if savedLEDs[presetIndex] then
                setProp(savedLEDs[presetIndex], "Boolean", true)
                self.state.ledTimers[roomIndex][presetIndex]:Start(self.config.ledOnTime)
            end
        end
        -- Update LED states after save
        self.cameraModule:updatePresetMatchLEDs(roomIndex)
        self:debug(string.format("Room[%d] Preset %d saved successfully", roomIndex, presetIndex))
    else
        self:error(string.format("Room[%d] Failed to save preset %d", roomIndex, presetIndex))
    end
end

function CameraPresetController:handlePresetRecall(roomIndex, presetIndex)
    if self.cameraModule:recallPreset(roomIndex, presetIndex) then
        self:debug(string.format("Room[%d] Preset %d recalled successfully", roomIndex, presetIndex))
        -- Update LED states after recall
        self.cameraModule:updatePresetMatchLEDs(roomIndex)
    else
        self:error(string.format("Room[%d] Failed to recall preset %d", roomIndex, presetIndex))
    end
end

function CameraPresetController:setupCameraMonitoring(roomIndex, cameraNames)
    -- Set up camera position change handlers for each discovered camera in this room
    local roomCameras = self.components.cameras[roomIndex] or {}
    for _, camName in pairs(cameraNames) do
        local camera = roomCameras[camName]
        if camera then
            -- Monitor camera position changes - DIRECT assignment
            if camera["ptz.preset"] then
                -- luacheck: ignore 122
                camera["ptz.preset"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs(roomIndex)
                end
                self:debug(string.format("Room[%d] Position monitoring enabled for: %s", roomIndex, camName))
            end
            
            -- Monitor camera movement status - DIRECT assignment
            if camera["is.moving"] then
                -- luacheck: ignore 122
                camera["is.moving"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs(roomIndex)
                end
                self:debug(string.format("Room[%d] Movement monitoring enabled for: %s", roomIndex, camName))
            end
        end
    end
end

function CameraPresetController:setupCameraChoices(roomIndex, cameraNames)
    if not controls.devCams or not controls.devCams[roomIndex] then 
        self:error(string.format("Room[%d] Camera selection control not available", roomIndex))
        return 
    end
    
    -- Set camera choices in the UI for this room
    if setProp(controls.devCams[roomIndex], "Choices", cameraNames) then
        self:debug(string.format("Room[%d] Camera choices populated: %d cameras", roomIndex, #cameraNames))
    else
        self:debug(string.format("Room[%d] Camera choices already set", roomIndex))
    end
    
    -- Verify choices were set
    if controls.devCams[roomIndex].Choices then
        self:debug(string.format("Room[%d] Verified choices count: %d (expected: %d)", 
            roomIndex, #controls.devCams[roomIndex].Choices, #cameraNames))
    else
        self:error(string.format("Room[%d] Failed to verify camera choices - Choices property not available", roomIndex))
    end
    
    -- Disable JSON storage control (shared, should not be user-editable)
    if controls.txtJSONStorage then
        controls.txtJSONStorage.IsDisabled = true
    end
    
    -- Set default camera selection with fallback logic
    if #cameraNames > 0 then
        local defaultSet = false
        
        -- Try to set the configured default camera
        for i, camName in ipairs(cameraNames) do
            if camName == self.config.defaultCamera then
                controls.devCams[roomIndex].String = camName
                controls.devCams[roomIndex].Value = i
                defaultSet = true
                self:debug(string.format("Room[%d] Set configured default camera: %s", roomIndex, camName))
                break
            end
        end
        
        -- Fallback to first available camera
        if not defaultSet then
            controls.devCams[roomIndex].String = cameraNames[1]
            controls.devCams[roomIndex].Value = 1
            self:debug(string.format("Room[%d] Set fallback default camera: %s", roomIndex, cameraNames[1]))
        end
        
        -- Recall default preset for the selected camera
        self:recallDefaultPreset(roomIndex)
    else
        self:error(string.format("Room[%d] No cameras available for selection", roomIndex))
    end
end

function CameraPresetController:recallDefaultPreset(roomIndex)
    if not controls.devCams or not controls.devCams[roomIndex] then
        self:debug(string.format("Room[%d] No camera selection control for default preset recall", roomIndex))
        return
    end
    
    local selectedCamera = controls.devCams[roomIndex].String or ""
    
    if not selectedCamera or selectedCamera == "" then
        self:debug(string.format("Room[%d] No camera selected for default preset recall", roomIndex))
        return
    end
    
    if self.cameraModule:recallPreset(roomIndex, self.config.defaultPreset) then
        self:debug(string.format("Room[%d] Recalled default preset %d for camera: %s", 
            roomIndex, self.config.defaultPreset, selectedCamera))
    else
        self:debug(string.format("Room[%d] Default preset %d not available for camera: %s", 
            roomIndex, self.config.defaultPreset, selectedCamera))
    end
end

function CameraPresetController:updateRouterChoices(roomIndex)
    -- compcamRouter is a single shared control across all rooms
    if not controls.compcamRouter then return end
    
    local roomRouters = self.components.routers[roomIndex] or {}
    local routerNames = {}
    for name, _ in pairs(roomRouters) do
        table.insert(routerNames, name)
    end
    table.sort(routerNames)
    table.insert(routerNames, self.clearString)
    
    controls.compcamRouter.Choices = routerNames
    if #routerNames > 0 then
        controls.compcamRouter.String = routerNames[1]  -- Default to first router
        self:debug(string.format("Room[%d] Router choices updated: %d routers available", roomIndex, #routerNames - 1))
    end
end

function CameraPresetController:updateRouterOutputChoices(roomIndex)
    if not controls.routerOutput or not controls.routerOutput[roomIndex] then return end
    
    -- compcamRouter is a single shared control across all rooms
    if not controls.compcamRouter then return end
    
    local selectedRouterName = controls.compcamRouter.String
    if not selectedRouterName or selectedRouterName == "" or selectedRouterName == self.clearString then
        controls.routerOutput[roomIndex].Choices = {}
        controls.routerOutput[roomIndex].String = ""  -- Clear cached output
        self:debug(string.format("Room[%d] No router selected - router output choices cleared", roomIndex))
        return
    end
    
    local roomRouters = self.components.routers[roomIndex] or {}
    local router = roomRouters[selectedRouterName]
    if not router then
        self:error(string.format("Room[%d] Router not found for output choices: %s", roomIndex, selectedRouterName))
        controls.routerOutput[roomIndex].Choices = {}
        controls.routerOutput[roomIndex].String = ""  -- Clear cached output
        return
    end
    
    -- Build list of available output controls from the router
    local outputChoices = {}
    for controlName, _ in pairs(router) do
        -- Look for select controls (typical router output controls)
        if type(controlName) == "string" and controlName:match("^select%.%d+$") then
            table.insert(outputChoices, controlName)
        end
    end
    
    -- Sort numerically by output number
    table.sort(outputChoices, function(a, b)
        local numA = tonumber(a:match("%.(%d+)$"))
        local numB = tonumber(b:match("%.(%d+)$"))
        return numA < numB
    end)
    
    if #outputChoices > 0 then
        setProp(controls.routerOutput[roomIndex], "Choices", outputChoices)
        
        -- Check if current cached value is valid for new router, otherwise reset to first
        local currentOutput = controls.routerOutput[roomIndex].String
        local isValidOutput = false
        for _, output in ipairs(outputChoices) do
            if output == currentOutput then
                isValidOutput = true
                break
            end
        end
        
        if not isValidOutput then
            controls.routerOutput[roomIndex].String = outputChoices[1]  -- Reset to first output if cache is invalid
            self:debug(string.format("Room[%d] Router output cache cleared - reset to: %s", roomIndex, outputChoices[1]))
        else
            self:debug(string.format("Room[%d] Router output cache retained: %s", roomIndex, currentOutput))
        end
        
        self:debug(string.format("Room[%d] Router output choices updated: %d outputs available", roomIndex, #outputChoices))
    else
        self:debug(string.format("Room[%d] No output controls found in router: %s", roomIndex, selectedRouterName))
        controls.routerOutput[roomIndex].Choices = {"select.1"}  -- Fallback default
        controls.routerOutput[roomIndex].String = "select.1"
    end
end

function CameraPresetController:cleanup()
    self:debug("Starting cleanup...")
    
    -- Stop all timers safely for all rooms
    for roomIndex = 1, self.numRooms do
        if self.state.countdownTimers[roomIndex] then
            for presetIndex, timer in pairs(self.state.countdownTimers[roomIndex]) do
                if timer then timer:Stop() end
            end
        end
        if self.state.ledTimers[roomIndex] then
            for presetIndex, timer in pairs(self.state.ledTimers[roomIndex]) do
                if timer then timer:Stop() end
            end
        end
    end
    
    -- Stop debounce timers for all rooms
    if self.cameraModule.debounceTimers then
        for roomIndex, timer in pairs(self.cameraModule.debounceTimers) do
            if timer then timer:Stop() end
        end
    end
    
    -- Clear event handlers to prevent memory leaks
    for roomIndex = 1, self.numRooms do
        local roomCameras = self.components.cameras[roomIndex] or {}
        for _, camera in pairs(roomCameras) do
            if camera then
                if camera["ptz.preset"] then
                    camera["ptz.preset"].EventHandler = nil
                end
                if camera["is.moving"] then
                    camera["is.moving"].EventHandler = nil
                end
            end
        end
    end
    
    self.state.initialized = false
    self:debug("Cleanup completed successfully")
end

-------------------[ Factory Function ]-------------------
local function createDivisibleSpaceCameraPresetController(userConfig)
    print("🚀 Divisible Space CameraPresetController: Starting initialization...")
    
    local config = userConfig or {}
    
    -- Helper function to list available controls for debugging
    local function listAvailableControls()
        print("📋 Available controls in design:")
        local controlList = {}
        for name, _ in pairs(Controls) do
            table.insert(controlList, name)
        end
        table.sort(controlList)
        for _, name in ipairs(controlList) do
            print("   - " .. name)
        end
    end
    
    -- Validate essential controls exist
    if not Controls.devCams then
        print("❌ ERROR: Essential camera controls not found (expected devCams[1], devCams[2], etc.)")
        listAvailableControls()
        return nil
    end
    
    -- Validate at least one room's preset controls exist
    if not Controls.btnCamPreset1 and not Controls.btnCamPreset2 then
        print("❌ ERROR: Essential preset controls not found")
        print("💡 Expected room-specific controls: btnCamPreset1[], btnCamPreset2[], ledPresetMatch1[], ledPresetMatch2[], etc.")
        listAvailableControls()
        return nil
    end
    
    -- Check that at least one room's controls exist
    local numRooms = discoverNumRoomsFromControls()
    if numRooms == 0 then
        print("❌ ERROR: No rooms detected - check that array controls exist (devCams[1], btnCamPreset1[1], etc.)")
        listAvailableControls()
        return nil
    end
    
    if isArr(Controls.txtJSONStorage) then
        print("❌ ERROR: txtJSONStorage must be a single control, not an array")
        return nil
    end
    
    local success, controller = pcall(function()
        return CameraPresetController.new(config)
    end)
    
    if success and controller then
        print("✅ Divisible Space CameraPresetController created successfully")
        print(string.format("   📊 Configuration: %d rooms, Tolerance=%.3f, Hold=%.1fs, LED=%.1fs", 
            controller.numRooms,
            controller.config.presetTolerance, 
            controller.config.holdTime, 
            controller.config.ledOnTime))
        return controller
    else
        print("❌ ERROR: Failed to create Divisible Space CameraPresetController: " .. tostring(controller))
        return nil
    end
end

-------------------[ Controller Instance Creation ]-------------------
-- Create the divisible space camera preset controller instance
-- All config values are defined in defaultConfig (single source of truth)
-- Only override values here if you need instance-specific customization
local divisibleSpaceController = createDivisibleSpaceCameraPresetController({
    debugging = true
})

-- Export for external access (suppress type warning)
-- luacheck: ignore 431
CameraPresetController = divisibleSpaceController

-------------------[ Usage Examples ]-------------------
--[[
-- Divisible space controller usage examples:

-- Save a preset manually for room 1
divisibleSpaceController.cameraModule:savePreset(1, 1)

-- Recall a preset manually for room 2
divisibleSpaceController.cameraModule:recallPreset(2, 2)

-- Force LED update for room 1
divisibleSpaceController.cameraModule:updatePresetMatchLEDs(1)

-- Save JSON data manually (shared across all rooms)
divisibleSpaceController.jsonModule:save()

-- Cleanup resources
divisibleSpaceController:cleanup()

-- Access configuration
print("Number of rooms: " .. divisibleSpaceController.numRooms)
print("Current tolerance: " .. divisibleSpaceController.config.presetTolerance)
]]--

