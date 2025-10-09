--[[ 
  Camera Preset Controller - Refactored with BaseModule Pattern
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-09-23
  Firmware Req: 10.0.0
  Version: 2.0
  
  Clean implementation using BaseModule pattern while maintaining all functionality
  Supports JSON storage, preset tolerance, router sync, and all camera operations
]]--

-- Define control references
local controls = {
    devCams = Controls.seldevCams,
    btnCamPreset = Controls.btnCamPreset,
    ledPresetMatch = Controls.ledPresetMatch,
    ledPresetSaved = Controls.ledPresetSaved,
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus
}

-- Configuration
local presetTolerance = 0.07
rapidjson = require("rapidjson")

-------------------[ Utility Functions ]-------------------
local function isArr(control)
    return type(control) == "table" and #control > 0
end

local function setProp(obj, prop, value)
    if not obj then return false end
    if obj[prop] == value then return false end
    obj[prop] = value
    return true
end

local function bind(control, func)
    if control and control.EventHandler then
        control.EventHandler = func
        return true
    end
    return false
end

local function forEach(array, func)
    if not array then return end
    for i, item in ipairs(array) do
        if item then func(item, i) end
    end
end

local function getControlArray(control)
    if not control then return {} end
    return isArr(control) and control or {control}
end

local function resetComponentsArray(components, arrayName)
    if components and components[arrayName] then
        components[arrayName] = {}
    end
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

-------------------[ JSON Module ]-------------------
local JSONModule = setmetatable({}, BaseModule)
JSONModule.__index = JSONModule

function JSONModule.new(controller)
    local self = BaseModule.new(controller, "JSON")
    setmetatable(self, JSONModule)
    return self
end

function JSONModule:save()
    if not self.controller.components.presets then return false end
    
    local strTemp = rapidjson.encode(self.controller.components.presets, {pretty=true, sort_keys=true})
    if strTemp ~= controls.txtJSONStorage.String then
        controls.txtJSONStorage.String = strTemp
        self:debug("JSON data saved")
        return true
    else
        self:debug("No new JSON data to save")
        return false
    end
end

function JSONModule:load()
    if not controls.txtJSONStorage.String or controls.txtJSONStorage.String == "" then
        self:debug("JSON storage is empty")
        return false
    end
    
    local tblTemp = rapidjson.decode(controls.txtJSONStorage.String)
    if type(tblTemp) == "table" then
        self.controller.components.presets = tblTemp
        self:debug("JSON data loaded successfully")
        return true
    else
        self:debug("JSON data was invalid")
        return false
    end
end

-------------------[ Camera Module ]-------------------
local CameraModule = setmetatable({}, BaseModule)
CameraModule.__index = CameraModule

function CameraModule.new(controller)
    local self = BaseModule.new(controller, "Camera")
    setmetatable(self, CameraModule)
    return self
end

function CameraModule:discoverCameras()
    resetComponentsArray(self.controller.components, "cameras")
    
    local cameraNames = {}
    local components = Component.GetComponents()
    if not components then
        self:debug("No components available for camera discovery")
        return cameraNames
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type == "onvif_camera_operative" and tblComponents.Name then
            table.insert(cameraNames, tblComponents.Name)
            self.controller.components.cameras[tblComponents.Name] = Component.New(tblComponents.Name)
            self:debug("Found camera: " .. tblComponents.Name)
        end
    end
    
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
        self:debug("No preset controls available")
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
    local camName = controls.devCams.String
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
    
    local isMoving = camera["is.moving"] and camera["is.moving"].Boolean or false
    if isMoving then
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local currentPreset = camera["ptz.preset"] and camera["ptz.preset"].String or ""
    if currentPreset == "" then
        self:debug("No current preset available for camera: " .. camName)
        return
    end
    
    local savedPresets = self.controller.components.presets[camName] or {}
    
    -- Update LEDs efficiently
    local ledControls = getControlArray(controls.ledPresetMatch)
    for i, led in ipairs(ledControls) do
        local presetMatches = savedPresets[i] and 
            self:presetsMatch(currentPreset, savedPresets[i], self.controller.config.presetTolerance)
        setProp(led, "Boolean", presetMatches or false)
    end
end

function CameraModule:presetsMatch(current, saved, tolerance)
    if not current or not saved or saved == "0 0 0" then return false end
    
    local function parsePreset(presetStr)
        local pan, tilt, zoom = presetStr:match("([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)")
        return tonumber(pan), tonumber(tilt), tonumber(zoom)
    end
    
    local currPan, currTilt, currZoom = parsePreset(current)
    local savedPan, savedTilt, savedZoom = parsePreset(saved)
    
    if not (currPan and currTilt and currZoom and savedPan and savedTilt and savedZoom) then
        return false
    end
    
    return math.abs(currPan - savedPan) <= tolerance and
           math.abs(currTilt - savedTilt) <= tolerance and
           math.abs(currZoom - savedZoom) <= tolerance
end

function CameraModule:savePreset(presetIndex)
    local camName = controls.devCams.String
    if not camName or camName == "" then
        self:debug("No camera selected for preset save")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:debug("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local currentPreset = camera["ptz.preset"].String
    if not currentPreset or currentPreset == "" then
        self:debug("No current preset data available for: " .. camName)
        return false
    end
    
    if not self.controller.components.presets[camName] then
        self.controller.components.presets[camName] = {}
    end
    
    self.controller.components.presets[camName][presetIndex] = currentPreset
    self:debug(string.format("Saved %s Preset[%d]: %s", camName, presetIndex, currentPreset))
    
    -- Auto-save to JSON
    self.controller.jsonModule:save()
    return true
end

function CameraModule:recallPreset(presetIndex)
    local camName = controls.devCams.String
    if not camName or camName == "" then
        self:debug("No camera selected for preset recall")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:debug("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local savedPresets = self.controller.components.presets[camName]
    if not savedPresets or not savedPresets[presetIndex] then
        self:debug(string.format("No saved preset[%d] for camera: %s", presetIndex, camName))
        return false
    end
    
    local preset = savedPresets[presetIndex]
    if preset == "0 0 0" then
        self:debug(string.format("Preset[%d] not initialized for camera: %s", presetIndex, camName))
        return false
    end
    
    camera["ptz.preset"].String = preset
    self:debug(string.format("Recalled %s Preset[%d]: %s", camName, presetIndex, preset))
    return true
end

-------------------[ Router Module ]-------------------
local RouterModule = setmetatable({}, BaseModule)
RouterModule.__index = RouterModule

function RouterModule.new(controller)
    local self = BaseModule.new(controller, "Router")
    setmetatable(self, RouterModule)
    return self
end

function RouterModule:discoverRouters()
    resetComponentsArray(self.controller.components, "routers")
    
    local components = Component.GetComponents()
    if not components then
        self:debug("No components available for router discovery")
        return
    end
    
    for _, tblComponents in pairs(components) do
        if tblComponents.Type and tblComponents.Type:match("video_router") and tblComponents.Name then
            self.controller.components.routers[tblComponents.Name] = Component.New(tblComponents.Name)
            self:debug("Found router: " .. tblComponents.Name)
        end
    end
end

function RouterModule:setupRouterSync()
    local selectedRouterName = controls.compcamRouter.String
    
    if not selectedRouterName or selectedRouterName == "" then
        self:debug("No router selected for sync setup")
        return false
    end
    
    local router = self.controller.components.routers[selectedRouterName]
    if not router then
        self:debug("Router not found: " .. selectedRouterName)
        return false
    end
    
    self:debug("Setting up router sync for: " .. selectedRouterName)
    
    local routerOutputs = self.controller.config.routerOutputs or {"select.1"}
    
    for _, output in ipairs(routerOutputs) do
        if router[output] then
            self:syncCamChoiceWithRouter(router, output, controls.devCams)
        end
    end
    
    return true
end

function RouterModule:syncCamChoiceWithRouter(router, routerKey, camChoiceControl)
    if not router or not router[routerKey] or not camChoiceControl then
        self:debug("Invalid parameters for router sync")
        return false
    end
    
    local eventHandler = function()
        local routedInputIndex = router[routerKey].Value
        
        if routedInputIndex and routedInputIndex > 0 and routedInputIndex <= #camChoiceControl.Choices then
            camChoiceControl.Value = routedInputIndex
            camChoiceControl.String = camChoiceControl.Choices[routedInputIndex]
            self:debug(string.format("Router sync: %s -> Camera: %s", routerKey, camChoiceControl.String))
            
            -- Update LED states after camera selection changes
            self.controller.cameraModule:updatePresetMatchLEDs()
        end
    end
    
    if bind(router[routerKey], eventHandler) then
        self:debug(string.format("Bound router %s event handler", routerKey))
        eventHandler() -- Initialize state
        return true
    end
    
    return false
end

-------------------[ CameraPresetController (Main Orchestrator) ]-------------------
local CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Configuration
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Component storage
    self.components = {
        cameras = {},
        presets = {},
        routers = {},
        roomControls = nil,
        callSync = nil
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {}
    }
    
    -- Configuration
    self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        presetTolerance = config and config.presetTolerance or presetTolerance,
        routerOutputs = config and config.routerOutputs or {"select.1"},
        defaultCamera = config and config.defaultCamera or "devCam01",
        defaultPreset = config and config.defaultPreset or 1
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

function CameraPresetController:init()
    self:debug("Starting initialization...")
    
    -- Load existing presets from JSON first
    self.jsonModule:load()
    
    -- Discover components
    local cameraNames = self.cameraModule:discoverCameras()
    self.routerModule:discoverRouters()
    
    -- Sort camera names to ensure consistent order (devCam01, devCam02, etc.)
    table.sort(cameraNames)
    for i, name in ipairs(cameraNames) do
        self:debug(string.format("Sorted cameraNames[%d]: %s", i, name))
    end
    
    -- Initialize preset structure for any new cameras
    self.cameraModule:initializePresets()
    
    -- Set up camera position change handlers for monitoring
    self:setupCameraMonitoring(cameraNames)
    
    -- Setup router synchronization
    self.routerModule:setupRouterSync()
    
    -- Set up initial UI state
    self:setupCameraChoices(cameraNames)
    self:updateRoomControlsChoices()
    self:updatePresetMatchLEDs()
    
    self:debug("Initialization complete")
end

function CameraPresetController:registerEventHandlers()
    -- Camera selection change handler
    if controls.devCams then
        bind(controls.devCams, function()
            self.cameraModule:updatePresetMatchLEDs()
        end)
    end
    
    -- Router selection change handler
    if controls.compcamRouter then
        bind(controls.compcamRouter, function()
            self.routerModule:setupRouterSync()
        end)
    end
    
    -- Config control handlers
    if controls.knbledOnTime then
        bind(controls.knbledOnTime, function()
            self.config.ledOnTime = controls.knbledOnTime.Value
            self:debug("LED On Time updated to: " .. self.config.ledOnTime)
        end)
    end
    
    if controls.knbHoldTime then
        bind(controls.knbHoldTime, function()
            self.config.holdTime = controls.knbHoldTime.Value
            self:debug("Hold Time updated to: " .. self.config.holdTime)
        end)
    end
    
    -- Initialize preset button handlers (using proven working pattern)
    self:initPresetButtonHandlers()
end

function CameraPresetController:initPresetButtonHandlers()
    if not controls.btnCamPreset then
        self:debug("No preset button controls available")
        return
    end
    
    -- Initialize timers and button handlers for each preset
    for i, v in ipairs(controls.btnCamPreset) do
        self.state.longPressed[i] = false
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Long press detection timer
        self.state.countdownTimers[i].EventHandler = function()
            self.state.countdownTimers[i]:Stop()
            if controls.btnCamPreset[i].Boolean then
                self.state.longPressed[i] = true
                self:handlePresetSave(i)
            end
        end
        
        -- LED flash timer
        self.state.ledTimers[i].EventHandler = function()
            self.state.ledTimers[i]:Stop()
            if controls.ledPresetSaved and controls.ledPresetSaved[i] then
                controls.ledPresetSaved[i].Boolean = false
            end
        end
        
        -- Button press/release handler
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
    
    self:debug(string.format("Initialized %d preset button handlers", #controls.btnCamPreset))
end

function CameraPresetController:handlePresetSave(presetIndex)
    if self.cameraModule:savePreset(presetIndex) then
        -- Flash the LED to indicate save
        if controls.ledPresetSaved and controls.ledPresetSaved[presetIndex] then
            controls.ledPresetSaved[presetIndex].Boolean = true
            self.state.ledTimers[presetIndex]:Start(self.config.ledOnTime)
        end
        -- Update LED states after save
        self.cameraModule:updatePresetMatchLEDs()
        self:debug(string.format("Preset %d saved successfully", presetIndex))
    end
end

function CameraPresetController:handlePresetRecall(presetIndex)
    if self.cameraModule:recallPreset(presetIndex) then
        self:debug(string.format("Preset %d recalled successfully", presetIndex))
        -- Update LED states after recall
        self.cameraModule:updatePresetMatchLEDs()
    end
end

function CameraPresetController:updatePresetMatchLEDs()
    self.cameraModule:updatePresetMatchLEDs()
end

function CameraPresetController:setupCameraMonitoring(cameraNames)
    -- Set up camera position change handlers for each discovered camera
    for _, camName in pairs(cameraNames) do
        local camera = self.components.cameras[camName]
        if camera then
            -- Monitor camera position changes
            if camera["ptz.preset"] then
                camera["ptz.preset"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs()
                end
                self:debug("Set up position monitoring for: " .. camName)
            end
            
            -- Monitor camera movement status
            if camera["is.moving"] then
                camera["is.moving"].EventHandler = function()
                    self.cameraModule:updatePresetMatchLEDs()
                end
                self:debug("Set up movement monitoring for: " .. camName)
            end
        end
    end
end

function CameraPresetController:setupCameraChoices(cameraNames)
    if not controls.devCams then return end
    
    -- Set camera choices in the UI
    controls.devCams.Choices = cameraNames
    controls.txtJSONStorage.IsDisabled = true
    
    -- Set default camera selection
    if #cameraNames > 0 then
        -- Try to set the configured default camera, fallback to first available
        local defaultCameraFound = false
        for i, camName in ipairs(cameraNames) do
            if camName == self.config.defaultCamera then
                controls.devCams.String = camName
                controls.devCams.Value = i
                defaultCameraFound = true
                self:debug("Set default camera: " .. camName)
                break
            end
        end
        
        -- If configured default not found, use first camera
        if not defaultCameraFound then
            controls.devCams.String = cameraNames[1]
            controls.devCams.Value = 1
            self:debug("Set fallback default camera: " .. cameraNames[1])
        end
        
        -- Recall default preset for the selected camera
        local selectedCamera = controls.devCams.String
        if selectedCamera ~= "" and self.components.cameras[selectedCamera] then
            self:recallDefaultPreset()
        end
    end
end

function CameraPresetController:recallDefaultPreset()
    local selectedCamera = controls.devCams.String
    
    if not selectedCamera or selectedCamera == "" then
        self:debug("No camera selected for default preset recall")
        return
    end
    
    if self.cameraModule:recallPreset(self.config.defaultPreset) then
        self:debug(string.format("Recalled default preset %d for camera: %s", 
            self.config.defaultPreset, selectedCamera))
    end
end

function CameraPresetController:updateRoomControlsChoices()
    if not controls.compRoomControls then return end
    
    local names = {}
    for name, _ in pairs(self.components.cameras) do
        table.insert(names, name)
    end
    table.sort(names)
    table.insert(names, self.clearString)
    controls.compRoomControls.Choices = names
end

-------------------[ Factory Function ]-------------------
-- Create controller instance
local controller = nil

local function createController()
    print("✓ CameraPresetController Factory: Starting initialization...")
    
    controller = CameraPresetController.new({
        debugging = true,
        holdTime = 3.0,
        ledOnTime = 2.5,
        presetTolerance = 0.07
    })
    
    if controller then
        print("✓ CameraPresetController created successfully")
        return controller
    else
        print("✗ ERROR: CameraPresetController NOT created")
        return nil
    end
end

-- Initialize the controller
controller = createController()