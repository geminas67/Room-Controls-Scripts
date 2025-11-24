--[[ 
  Camera Preset Controller - Enhanced Implementation
  Author: Nikolas Smith, Q-SYS (Enhanced)
  2025-09-23
  Firmware Req: 10.0.0
  Version: 2.1
  
  Enhanced implementation combining best practices from both versions:
  - BaseModule pattern with metatable-based construction
  - Direct EventHandler assignments (no bind() wrapper)
  - Robust error handling and validation
  - Performance optimizations
  - Improved reliability and maintainability
  
  Key Improvements:
  - Utility functions defined first to prevent nil value errors
  - Direct EventHandler assignments for maximum reliability
  - Enhanced component validation and error recovery
  - Optimized preset matching with early returns
  - Configurable tolerance with better precision
  - Comprehensive cleanup and memory management
]]--

-- Define control references
-- luacheck: globals Controls Timer Component

-- CRITICAL: For cross-instance synchronization, txtJSONStorage must be shared
-- Option 1: Use a shared external component (recommended)
-- Option 2: Use Named Controls pointing to same external control
-- Option 3: Use local control (no cross-instance sync)

local sharedStorageComponent = nil
local useSharedStorage = Controls.compSharedStorage  -- Check if shared storage component selector exists

if useSharedStorage and useSharedStorage.String ~= "" then
    -- Using shared component for cross-instance synchronization
    local success, comp = pcall(Component.New, useSharedStorage.String)
    if success and comp then
        sharedStorageComponent = comp
        print("[CameraPresetController] Using shared storage component: " .. useSharedStorage.String)
    else
        print("[CameraPresetController] WARNING: Could not access shared storage component, using local storage")
    end
end

local controls = {
    devCams = Controls.devCams,
    btnCamPreset = Controls.btnCamPreset,
    ledPresetMatch = Controls.ledPresetMatch,
    ledPresetSaved = Controls.ledPresetSaved,
    knbledOnTime = Controls.knbledOnTime,
    -- Use shared component if available, otherwise use local control
    txtJSONStorage = sharedStorageComponent and sharedStorageComponent["txtJSONStorage"] or Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    routerOutput = Controls.routerOutput,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    compSharedStorage = Controls.compSharedStorage,  -- Combo box to select shared storage component
    txtStatus = Controls.txtStatus
}

-- Configuration
local defaultConfig = {
    presetTolerance = 0.03,  -- Tighter tolerance for better precision
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
    -- Reload presets from storage and update UI
    -- CRITICAL: Do NOT call save() here - txtJSONStorage is the single source of truth
    -- Load flow: Storage -> Local cache -> Update UI (no write back)
    if self:load() then
        -- Update preset match LEDs to reflect changes from other script instance
        if self.controller.cameraModule then
            self.controller.cameraModule:updatePresetMatchLEDs()
        end
        self:debug("Presets reloaded from external instance - UI synchronized")
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
    self.debounceTimer = Timer.New()
    return self
end

function CameraModule:discoverCameras()
    resetComponentsArray(self.controller.components, "cameras")
    
    local cameraNames = {}
    local success, components = pcall(Component.GetComponents)
    
    if not success or not components then
        self:error("Failed to get components for camera discovery")
        return cameraNames
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type == componentTypes.camera and tblComponents.Name then
            if validateComponent(tblComponents.Name) then
                table.insert(cameraNames, tblComponents.Name)
                self.controller.components.cameras[tblComponents.Name] = Component.New(tblComponents.Name)
                self:debug("Found and validated camera: " .. tblComponents.Name)
            else
                self:error("Invalid camera component: " .. tblComponents.Name)
            end
        end
    end
    
    table.sort(cameraNames)  -- Ensure consistent ordering
    return cameraNames
end

function CameraModule:initializePresets()
    local cameraNames = {}
    for name, _ in pairs(self.controller.components.cameras) do
        table.insert(cameraNames, name)
    end
    
    if #cameraNames == 0 then
        self:debug("No cameras to initialize presets for")
        return
    end
    
    local presetControls = getControlArray(controls.btnCamPreset)
    if #presetControls == 0 then
        self:error("No preset controls available")
        return
    end
    
    for _, camName in pairs(cameraNames) do
        if not self.controller.components.presets[camName] then
            self.controller.components.presets[camName] = {}
            for i = 1, #presetControls do
                self.controller.components.presets[camName][i] = "0 0 0"
            end
            self:debug("Initialized presets for camera: " .. camName)
        end
    end
end

function CameraModule:updatePresetMatchLEDs()
    -- Debounce rapid updates during camera movement
    self.debounceTimer:Stop()
    -- luacheck: ignore 122
    self.debounceTimer.EventHandler = function()
        self:_updatePresetMatchLEDsInternal()
    end
    self.debounceTimer:Start(self.controller.config.debounceDelay)
end

function CameraModule:_updatePresetMatchLEDsInternal()
    local camName = controls.devCams and controls.devCams.String or ""
    if not camName or camName == "" then
        -- Clear all LEDs when no camera selected
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera then
        self:debug("Camera not found: " .. camName)
        return
    end
    
    -- Skip updates if camera is moving for better performance
    local isMoving = camera["is.moving"] and camera["is.moving"].Boolean or false
    if isMoving then
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local currentPreset = camera["ptz.preset"] and camera["ptz.preset"].String or ""
    if currentPreset == "" then
        -- Only log this once every 5 seconds to prevent spam
        if not self.lastEmptyPresetLog or (os.clock() - self.lastEmptyPresetLog) > 5 then
            self:debug("No current preset available for camera: " .. camName)
            self.lastEmptyPresetLog = os.clock()
        end
        -- Clear LEDs when no preset data available
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    -- Additional validation for preset format before processing
    if type(currentPreset) ~= "string" or currentPreset:match("^%s*$") then
        -- Only log malformed preset data once every 5 seconds
        if not self.lastMalformedPresetLog or (os.clock() - self.lastMalformedPresetLog) > 5 then
            self:debug(string.format("Malformed preset data for camera %s: '%s' (type: %s)", 
                camName, tostring(currentPreset), type(currentPreset)))
            self.lastMalformedPresetLog = os.clock()
        end
        -- Clear LEDs when preset data is malformed
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local savedPresets = self.controller.components.presets[camName] or {}
    
    -- Update LEDs efficiently with early returns
    local ledControls = getControlArray(controls.ledPresetMatch)
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

function CameraModule:savePreset(presetIndex)
    local camName = controls.devCams and controls.devCams.String or ""
    if not camName or camName == "" then
        self:error("No camera selected for preset save")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:error("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local currentPreset = camera["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        self:error("No current preset data available for: " .. camName)
        return false
    end
    
    if not self.controller.components.presets[camName] then
        self.controller.components.presets[camName] = {}
    end
    
    local oldPreset = self.controller.components.presets[camName][presetIndex] or "not set"
    self.controller.components.presets[camName][presetIndex] = currentPreset
    self:debug(string.format("Saved %s Preset[%d]: %s (was: %s)", 
        camName, presetIndex, currentPreset, oldPreset))
    
    -- Auto-save to JSON with error handling
    if not self.controller.jsonModule:save() then
        self:error("Failed to save preset data to JSON storage")
    end
    
    return true
end

function CameraModule:recallPreset(presetIndex)
    local camName = controls.devCams and controls.devCams.String or ""
    if not camName or camName == "" then
        self:error("No camera selected for preset recall")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:error("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local savedPresets = self.controller.components.presets[camName]
    if not savedPresets or not savedPresets[presetIndex] then
        self:error(string.format("No saved preset[%d] for camera: %s", presetIndex, camName))
        return false
    end
    
    local preset = savedPresets[presetIndex]
    if preset == "0 0 0" then
        self:error(string.format("Preset[%d] not initialized for camera: %s", presetIndex, camName))
        return false
    end
    
    camera["ptz.preset"].String = preset
    self:debug(string.format("Recalled %s Preset[%d]: %s", camName, presetIndex, preset))
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

function RouterModule:discoverRouters()
    resetComponentsArray(self.controller.components, "routers")
    
    local success, components = pcall(Component.GetComponents)
    if not success or not components then
        self:error("Failed to get components for router discovery")
        return
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type and tblComponents.Type:match(componentTypes.videoRouter) and tblComponents.Name then
            if validateComponent(tblComponents.Name) then
                self.controller.components.routers[tblComponents.Name] = Component.New(tblComponents.Name)
                self:debug("Found and validated router: " .. tblComponents.Name)
            else
                self:error("Invalid router component: " .. tblComponents.Name)
            end
        end
    end
end

function RouterModule:discoverRoomControls()
    resetComponentsArray(self.controller.components, "roomControls")
    
    local success, components = pcall(Component.GetComponents)
    if not success or not components then
        self:error("Failed to get components for room controls discovery")
        return
    end
    
    local roomControlsCount = 0
    for _, tblComponents in pairs(components) do
        if tblComponents.Type == componentTypes.roomControls and tblComponents.Name then
            -- Filter to only components starting with "compRoomControls"
            if tblComponents.Name:match("^compRoomControls") then
                if validateComponent(tblComponents.Name) then
                    self.controller.components.roomControls[tblComponents.Name] = Component.New(tblComponents.Name)
                    roomControlsCount = roomControlsCount + 1
                    self:debug("Found and validated room control: " .. tblComponents.Name)
                else
                    self:error("Invalid room control component: " .. tblComponents.Name)
                end
            end
        end
    end
    
    self:debug(string.format("Room controls discovery complete: %d components found", roomControlsCount))
end

function RouterModule:setupRouterSync()
    local selectedRouterName = controls.compcamRouter.String
    
    if not selectedRouterName or selectedRouterName == "" then
        self:debug("No router selected for sync setup")
        return false
    end
    
    -- Clean up old router handlers before setting up new ones (Refactoring Pattern #33)
    if self.controller.state.currentRouter then
        local outputControl = controls.routerOutput and controls.routerOutput.String or "select.1"
        cleanupComponentHandlers(
            self.controller.state.currentRouter,
            {outputControl},
            function(msg) self:debug(msg) end
        )
    end
    
    local router = self.controller.components.routers[selectedRouterName]
    if not router then
        self:error("Router not found: " .. selectedRouterName)
        return false
    end
    
    -- Cache current router for cleanup on next change
    self.controller.state.currentRouter = router
    
    self:debug("Setting up router sync for: " .. selectedRouterName)
    
    -- Use dynamic routerOutput control instead of static config
    local routerOutputs = controls.routerOutput and controls.routerOutput.String ~= "" 
        and {controls.routerOutput.String} 
        or self.controller.config.routerOutputs or {"select.1"}
    local successCount = 0
    
    if not controls.devCams then
        self:error("devCams control not available for router sync")
        return false
    end
    
    for _, output in ipairs(routerOutputs) do
        if router[output] then
            if self:syncCamChoiceWithRouter(router, output, controls.devCams) then
                successCount = successCount + 1
            end
        else
            self:error(string.format("Router output %s not found", output))
        end
    end
    
    self:debug(string.format("Router sync setup complete: %d/%d outputs configured", 
        successCount, #routerOutputs))
    return successCount > 0
end

function RouterModule:syncCamChoiceWithRouter(router, routerKey, camChoiceControl)
    if not router or not router[routerKey] or not camChoiceControl then
        self:error("Invalid parameters for router sync")
        return false
    end
    
    -- CRITICAL: Use direct EventHandler assignment instead of bind()
    -- This prevents intermittent failures and improves reliability
    -- luacheck: ignore 122
    router[routerKey].EventHandler = function()
        local routedInputIndex = router[routerKey].Value
        
        -- Validate choices exist before accessing
        if not camChoiceControl.Choices then
            self:debug("Camera choices not yet initialized")
            return
        end
        
        if routedInputIndex and routedInputIndex > 0 and routedInputIndex <= #camChoiceControl.Choices then
            -- Use setProp for Value to avoid redundant updates
            if setProp(camChoiceControl, "Value", routedInputIndex) then
                camChoiceControl.String = camChoiceControl.Choices[routedInputIndex]
                self:debug(string.format("Router sync: %s -> Camera: %s", routerKey, camChoiceControl.String))
            end
            
            -- Update LED states after camera selection changes
            self.controller.cameraModule:updatePresetMatchLEDs()
        else
            self:debug(string.format("Invalid router input index: %s (choices: %d)", 
                tostring(routedInputIndex), #camChoiceControl.Choices))
        end
    end
    
    -- Initialize state
    if router[routerKey].EventHandler then
        router[routerKey].EventHandler()
        self:debug(string.format("Router %s event handler configured and initialized", routerKey))
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
    
    -- Validate required controls before initialization (Refactoring Guideline #14)
    if not self:validateControls() then
        print("❌ ERROR: Required controls missing - initialization aborted")
        return nil
    end
    
    -- Configuration with defaults
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Merge user config with defaults
    self.config = {}
    for key, value in pairs(defaultConfig) do
        self.config[key] = (config and config[key]) or value
    end
    
    -- Component storage
    self.components = {
        cameras = {},
        presets = {},
        routers = {},
        roomControls = {},
        callSync = nil
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        initialized = false,
        isSavingJSON = false,  -- Flag to prevent reload on own saves
        currentRouter = nil  -- Track current router for handler cleanup
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

function CameraPresetController:validateControls()
    -- Comprehensive control validation (Refactoring Guideline #14)
    local requiredControls = {
        "devCams",
        "btnCamPreset",
        "ledPresetMatch",
        "txtJSONStorage"
    }
    
    local missingControls = {}
    for _, controlName in ipairs(requiredControls) do
        if not controls[controlName] then
            table.insert(missingControls, controlName)
        end
    end
    
    if #missingControls > 0 then
        self:error("Missing required controls: " .. table.concat(missingControls, ", "))
        return false
    end
    
    -- Validate devCams is a single control (not an array)
    if isArr(controls.devCams) then
        self:error("devCams must be a single control, not an array")
        return false
    end
    
    -- Validate btnCamPreset is an array
    if not isArr(controls.btnCamPreset) then
        self:error("btnCamPreset must be an array of controls")
        return false
    end
    
    self:debug("Control validation passed")
    return true
end

function CameraPresetController:init()
    if self.state.initialized then
        self:debug("Already initialized, skipping...")
        return
    end
    
    self:debug("Starting enhanced initialization...")
    
    -- Load existing presets from JSON first
    if not self.jsonModule:load() then
        self:debug("No existing JSON data found, will create new preset structure")
    end
    
    -- Discover components with error handling
    local cameraNames = self.cameraModule:discoverCameras()
    if #cameraNames == 0 then
        self:error("No cameras discovered - check camera components")
        setProp(controls.txtStatus, "String", "No Cameras Found")
        setProp(controls.txtStatus, "Value", 2)
        return
    end
    
    self.routerModule:discoverRouters()
    self.routerModule:discoverRoomControls()
    
    -- Sort camera names for consistent ordering
    table.sort(cameraNames)
    for i, name in ipairs(cameraNames) do
        self:debug(string.format("Discovered camera[%d]: %s", i, name))
    end
    
    -- Initialize preset structure for cameras
    self.cameraModule:initializePresets()
    
    -- Set up camera monitoring with enhanced error handling
    self:setupCameraMonitoring(cameraNames)
    
    -- Set up UI state BEFORE router sync (choices must exist first)
    self:setupCameraChoices(cameraNames)
    self:updateRouterChoices()
    self:updateRouterOutputChoices()  -- Populate router output choices after router is selected
    self:updateRoomControlsChoices()
    
    -- Setup router synchronization (after UI choices are populated)
    self.routerModule:setupRouterSync()
    
    -- Initial LED update
    self.cameraModule:updatePresetMatchLEDs()
    
    -- Set status to OK using setProp to prevent redundant updates
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
    
    self.state.initialized = true
    self:debug(string.format("Enhanced initialization complete - %d cameras, %d routers", 
        #cameraNames, self:getRouterCount()))
end

function CameraPresetController:getRouterCount()
    local count = 0
    for _ in pairs(self.components.routers) do
        count = count + 1
    end
    return count
end

function CameraPresetController:registerEventHandlers()
    -- CRITICAL: Use direct EventHandler assignments for maximum reliability
    -- Using centralized handler map pattern (Refactoring Pattern #28)
    
    -- Build handler map with direct object references
    local handlerMap = {}
    
    -- Camera selection handler
    if controls.devCams then
        handlerMap[controls.devCams] = function()
            self.cameraModule:updatePresetMatchLEDs()
        end
    end
    
    -- Router and output selection handlers
    if controls.compcamRouter then
        handlerMap[controls.compcamRouter] = function()
            self:updateRouterOutputChoices()
            self.routerModule:setupRouterSync()
        end
    end
    
    if controls.routerOutput then
        handlerMap[controls.routerOutput] = function()
            self.routerModule:setupRouterSync()
        end
    end
    
    -- JSON storage cross-instance synchronization
    if controls.txtJSONStorage then
        handlerMap[controls.txtJSONStorage] = function()
            -- Only reload if change came from another instance (not our own save)
            if not self.state.isSavingJSON then
                self:debug("JSON storage changed externally - reloading presets...")
                self.jsonModule:reloadFromStorage()
            end
        end
    end
    
    -- Configuration controls
    if controls.knbledOnTime then
        handlerMap[controls.knbledOnTime] = function()
            local newValue = controls.knbledOnTime.Value
            if newValue and newValue > 0 then
                self.config.ledOnTime = newValue
                self:debug("LED On Time updated to: " .. self.config.ledOnTime)
            end
        end
    end
    
    if controls.knbHoldTime then
        handlerMap[controls.knbHoldTime] = function()
            local newValue = controls.knbHoldTime.Value
            if newValue and newValue > 0 then
                self.config.holdTime = newValue
                self:debug("Hold Time updated to: " .. self.config.holdTime)
            end
        end
    end
    
    -- Batch register all handlers in single loop
    local registeredCount = 0
    for ctrl, handler in pairs(handlerMap) do
        if ctrl and handler then
            -- luacheck: ignore 122
            ctrl.EventHandler = handler
            registeredCount = registeredCount + 1
        end
    end
    
    self:debug(string.format("Registered %d event handlers via handler map", registeredCount))
    
    -- Initialize preset button handlers
    self:initPresetButtonHandlers()
end

function CameraPresetController:initPresetButtonHandlers()
    if not controls.btnCamPreset then
        self:error("No preset button controls available")
        return
    end
    
    -- Initialize timers and button handlers for each preset
    for i, btn in ipairs(controls.btnCamPreset) do
        if btn then
            self.state.longPressed[i] = false
            self.state.countdownTimers[i] = Timer.New()
            self.state.ledTimers[i] = Timer.New()
            
            -- Long press detection timer
            -- luacheck: ignore 122
            self.state.countdownTimers[i].EventHandler = function()
                self.state.countdownTimers[i]:Stop()
                if controls.btnCamPreset[i] and controls.btnCamPreset[i].Boolean then
                    self.state.longPressed[i] = true
                    self:handlePresetSave(i)
                end
            end
            
            -- LED flash timer
            -- luacheck: ignore 122
            self.state.ledTimers[i].EventHandler = function()
                self.state.ledTimers[i]:Stop()
                if controls.ledPresetSaved and controls.ledPresetSaved[i] then
                    setProp(controls.ledPresetSaved[i], "Boolean", false)
                end
            end
            
            -- Button press/release handler - DIRECT assignment for reliability
            -- luacheck: ignore 122
            controls.btnCamPreset[i].EventHandler = function()
                if controls.btnCamPreset[i].Boolean then
                    -- Button pressed - start long press timer
                    self.state.longPressed[i] = false
                    self.state.countdownTimers[i]:Start(self.config.holdTime)
                else
                    -- Button released
                    self.state.countdownTimers[i]:Stop()
                    if not self.state.longPressed[i] then
                        -- Short press - recall preset
                        self:handlePresetRecall(i)
                    end
                end
            end
        end
    end
    
    self:debug(string.format("Initialized %d preset button handlers", #controls.btnCamPreset))
end

function CameraPresetController:handlePresetSave(presetIndex)
    if self.cameraModule:savePreset(presetIndex) then
        -- Flash the LED to indicate successful save using setProp
        if controls.ledPresetSaved and controls.ledPresetSaved[presetIndex] then
            setProp(controls.ledPresetSaved[presetIndex], "Boolean", true)
            self.state.ledTimers[presetIndex]:Start(self.config.ledOnTime)
        end
        -- Update LED states after save
        self.cameraModule:updatePresetMatchLEDs()
        self:debug(string.format("Preset %d saved successfully", presetIndex))
    else
        self:error(string.format("Failed to save preset %d", presetIndex))
    end
end

function CameraPresetController:handlePresetRecall(presetIndex)
    if self.cameraModule:recallPreset(presetIndex) then
        self:debug(string.format("Preset %d recalled successfully", presetIndex))
        -- Update LED states after recall
        self.cameraModule:updatePresetMatchLEDs()
    else
        self:error(string.format("Failed to recall preset %d", presetIndex))
    end
end

function CameraPresetController:setupCameraMonitoring(cameraNames)
    -- Set up camera position change handlers for each discovered camera
    for _, camName in pairs(cameraNames) do
        local camera = self.components.cameras[camName]
        if camera then
            -- Monitor camera position changes - DIRECT assignment
            if camera["ptz.preset"] then
                -- luacheck: ignore 122
                camera["ptz.preset"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs()
                end
                self:debug("Position monitoring enabled for: " .. camName)
            end
            
            -- Monitor camera movement status - DIRECT assignment
            if camera["is.moving"] then
                -- luacheck: ignore 122
                camera["is.moving"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs()
                end
                self:debug("Movement monitoring enabled for: " .. camName)
            end
        end
    end
end

function CameraPresetController:setupCameraChoices(cameraNames)
    if not controls.devCams then 
        self:error("Camera selection control not available")
        return 
    end
    
    -- Set camera choices in the UI (devCams is always a single control)
    if setProp(controls.devCams, "Choices", cameraNames) then
        self:debug(string.format("Camera choices populated: %d cameras", #cameraNames))
    else
        self:debug("Camera choices already set")
    end
    
    -- Verify choices were set
    if controls.devCams.Choices then
        self:debug(string.format("Verified choices count: %d (expected: %d)", 
            #controls.devCams.Choices, #cameraNames))
        for i, choice in ipairs(controls.devCams.Choices) do
            self:debug(string.format("  Choice[%d]: %s", i, choice))
        end
    else
        self:error("Failed to verify camera choices - Choices property not available")
    end
    
    controls.txtJSONStorage.IsDisabled = true
    
    -- Set default camera selection with fallback logic
    if #cameraNames > 0 then
        local defaultSet = false
        
        -- Try to set the configured default camera
        for i, camName in ipairs(cameraNames) do
            if camName == self.config.defaultCamera then
                controls.devCams.String = camName
                controls.devCams.Value = i
                defaultSet = true
                self:debug("Set configured default camera: " .. camName)
                break
            end
        end
        
        -- Fallback to first available camera
        if not defaultSet then
            controls.devCams.String = cameraNames[1]
            controls.devCams.Value = 1
            self:debug("Set fallback default camera: " .. cameraNames[1])
        end
        
        -- Recall default preset for the selected camera
        self:recallDefaultPreset()
    else
        self:error("No cameras available for selection")
    end
end

function CameraPresetController:recallDefaultPreset()
    local selectedCamera = controls.devCams and controls.devCams.String or ""
    
    if not selectedCamera or selectedCamera == "" then
        self:debug("No camera selected for default preset recall")
        return
    end
    
    if self.cameraModule:recallPreset(self.config.defaultPreset) then
        self:debug(string.format("Recalled default preset %d for camera: %s", 
            self.config.defaultPreset, selectedCamera))
    else
        self:debug(string.format("Default preset %d not available for camera: %s", 
            self.config.defaultPreset, selectedCamera))
    end
end

function CameraPresetController:updateRouterChoices()
    if not controls.compcamRouter then return end
    
    local routerNames = {}
    for name, _ in pairs(self.components.routers) do
        table.insert(routerNames, name)
    end
    table.sort(routerNames)
    table.insert(routerNames, self.clearString)
    
    controls.compcamRouter.Choices = routerNames
    if #routerNames > 0 then
        controls.compcamRouter.String = routerNames[1]  -- Default to first router
        self:debug("Router choices updated: " .. #routerNames .. " routers available")
    end
end

function CameraPresetController:updateRouterOutputChoices()
    if not controls.routerOutput then return end
    
    local selectedRouterName = controls.compcamRouter.String
    if not selectedRouterName or selectedRouterName == "" or selectedRouterName == self.clearString then
        controls.routerOutput.Choices = {}
        controls.routerOutput.String = ""  -- Clear cached output
        self:debug("No router selected - router output choices cleared")
        return
    end
    
    local router = self.components.routers[selectedRouterName]
    if not router then
        self:error("Router not found for output choices: " .. selectedRouterName)
        controls.routerOutput.Choices = {}
        controls.routerOutput.String = ""  -- Clear cached output
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
        setProp(controls.routerOutput, "Choices", outputChoices)
        
        -- Check if current cached value is valid for new router, otherwise reset to first
        local currentOutput = controls.routerOutput.String
        local isValidOutput = false
        for _, output in ipairs(outputChoices) do
            if output == currentOutput then
                isValidOutput = true
                break
            end
        end
        
        if not isValidOutput then
            controls.routerOutput.String = outputChoices[1]  -- Reset to first output if cache is invalid
            self:debug(string.format("Router output cache cleared - reset to: %s", outputChoices[1]))
        else
            self:debug(string.format("Router output cache retained: %s", currentOutput))
        end
        
        self:debug(string.format("Router output choices updated: %d outputs available", #outputChoices))
    else
        self:debug("No output controls found in router: " .. selectedRouterName)
        controls.routerOutput.Choices = {"select.1"}  -- Fallback default
        controls.routerOutput.String = "select.1"
    end
end

function CameraPresetController:updateRoomControlsChoices()
    if not controls.compRoomControls then return end
    
    local names = {}
    for name, _ in pairs(self.components.roomControls) do
        table.insert(names, name)
    end
    table.sort(names)
    table.insert(names, self.clearString)
    controls.compRoomControls.Choices = names
end

function CameraPresetController:cleanup()
    self:debug("Starting cleanup...")
    
    -- Stop all timers safely
    for i, timer in pairs(self.state.countdownTimers) do
        if timer then timer:Stop() end
    end
    for i, timer in pairs(self.state.ledTimers) do
        if timer then timer:Stop() end
    end
    
    -- Stop debounce timer
    if self.cameraModule.debounceTimer then
        self.cameraModule.debounceTimer:Stop()
    end
    
    -- Clear event handlers to prevent memory leaks
    for _, camera in pairs(self.components.cameras) do
        if camera then
            if camera["ptz.preset"] then
                camera["ptz.preset"].EventHandler = nil
            end
            if camera["is.moving"] then
                camera["is.moving"].EventHandler = nil
            end
        end
    end
    
    self.state.initialized = false
    self:debug("Cleanup completed successfully")
end

-------------------[ Enhanced Factory Function ]-------------------
local function createEnhancedCameraPresetController(userConfig)
    print("🚀 Enhanced CameraPresetController: Starting initialization...")
    
    local config = userConfig or {}
    
    -- Validate essential controls exist (devCams must be single control, not array)
    if not Controls.devCams or not Controls.btnCamPreset then
        print("❌ ERROR: Essential camera controls not found")
        return nil
    end
    
    if isArr(Controls.devCams) then
        print("❌ ERROR: devCams must be a single control, not an array")
        return nil
    end
    
    local success, controller = pcall(function()
        return CameraPresetController.new(config)
    end)
    
    if success and controller then
        print("✅ Enhanced CameraPresetController created successfully")
        print(string.format("   📊 Configuration: Tolerance=%.3f, Hold=%.1fs, LED=%.1fs", 
            controller.config.presetTolerance, 
            controller.config.holdTime, 
            controller.config.ledOnTime))
        return controller
    else
        print("❌ ERROR: Failed to create Enhanced CameraPresetController: " .. tostring(controller))
        return nil
    end
end

-------------------[ Controller Instance Creation ]-------------------
-- Create the enhanced camera preset controller instance
local enhancedController = createEnhancedCameraPresetController({
    debugging = true,
    presetTolerance = 0.03,  -- Tighter tolerance for better precision
    holdTime = 3.0,
    ledOnTime = 2.5,
    defaultCamera = "devCam01",
    defaultPreset = 1
})

-- Export for external access (suppress type warning)
-- luacheck: ignore 431
CameraPresetController = enhancedController

-------------------[ Usage Examples ]-------------------
--[[
-- Enhanced controller usage examples:

-- Save a preset manually
enhancedController.cameraModule:savePreset(1)

-- Recall a preset manually  
enhancedController.cameraModule:recallPreset(2)

-- Force LED update
enhancedController.cameraModule:updatePresetMatchLEDs()

-- Save JSON data manually
enhancedController.jsonModule:save()

-- Cleanup resources
enhancedController:cleanup()

-- Access configuration
print("Current tolerance: " .. enhancedController.config.presetTolerance)
]]--
