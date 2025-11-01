--[[ 
  Camera Preset Controller - Class-based Implementation
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-10-16
  Firmware Req: 10.0.0
  Version: 2.0
    
  Features:
  - Preset Recall Feedback Tolerance: Configurable tolerance value for preset matching
  - Dynamic camera and router discovery
  - JSON-based preset storage and retrieval
  - Long-press save, short-press recall functionality
  - Router synchronization with camera selection
]]--

-- Required libraries
rapidjson = require("rapidjson")

-------------------[ Utility Functions ]-------------------
local function isArr(val)
    return type(val) == "table" and #val > 0
end

local function setProp(ctrl, prop, val)
    if not ctrl or not prop then return false end
    if ctrl[prop] == val then return false end  -- Guard against redundant assignments
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if ctrl and handler then
        ctrl.EventHandler = handler
        return true
    end
    return false
end

local function bindArray(ctrlArray, handlerFunc)
    if not isArr(ctrlArray) then return 0 end
    local count = 0
    for i, ctrl in ipairs(ctrlArray) do
        if ctrl and handlerFunc then
            bind(ctrl, handlerFunc(i, ctrl))
            count = count + 1
        end
    end
    return count
end

local function forEach(tbl, func)
    if not tbl or not func then return end
    for i, v in ipairs(tbl) do
        func(i, v)
    end
end

local function getControlArray(namePattern, count)
    local arr = {}
    for i = 1, count do
        local ctrlName = string.format(namePattern, i)
        if Controls[ctrlName] then
            arr[i] = Controls[ctrlName]
        end
    end
    return arr
end

-------------------[ Control References ]-------------------
local controls = {
    seldevCams = Controls.seldevCams,
    btnCamPreset = Controls.btnCamPreset,
    ledPresetMatch = Controls.ledPresetMatch,
    ledPresetSaved = Controls.ledPresetSaved,
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    compRoomControls = Controls.compRoomControls,
    txtStatus = Controls.txtStatus,
}

-------------------[ Base Module Class ]------------------
CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

-------------------[ Class Constructor ]------------------
function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Configuration
    self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        presetTolerance = config and config.presetTolerance or 0.1,
        routerOutputs = config and config.routerOutputs or {"select.1"},
        defaultCamera = config and config.defaultCamera or "devCam01",
        defaultPreset = config and config.defaultPreset or 1
    }
    
    -- Validate controls before proceeding
    if not self:validateControls() then
        error("Control validation failed - see debug output for details")
    end
    
    -- Normalize control arrays for efficient batch operations
    self:normalizeControlArrays()
    
    -- Component storage
    self.components = {
        cameras = {},
        presets = {},
        roomControls = nil,
        routers = {},
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        invalidComponents = {}
    }
    
    -- Initialize modules
    self:initJSONModule()
    self:initCameraModule()
    self:initRouterModule()
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:initialize()
    
    return self
end

-------------------[ Control Validation ]------------------
function CameraPresetController:validateControls()
    local requiredControls = {
        "seldevCams",
        "btnCamPreset",
        "ledPresetMatch",
        "ledPresetSaved",
        "knbledOnTime",
        "txtJSONStorage",
        "knbHoldTime",
        "compcamRouter",
        "compRoomControls",
        "txtStatus"
    }
    
    local missing = {}
    for _, ctrlName in ipairs(requiredControls) do
        if not controls[ctrlName] then
            table.insert(missing, ctrlName)
        end
    end
    
    if #missing > 0 then
        self:debugPrint("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    
    -- Validate array controls
    if not isArr(controls.btnCamPreset) then
        self:debugPrint("ERROR: btnCamPreset must be a control array")
        return false
    end
    
    if not isArr(controls.ledPresetMatch) then
        self:debugPrint("ERROR: ledPresetMatch must be a control array")
        return false
    end
    
    if not isArr(controls.ledPresetSaved) then
        self:debugPrint("ERROR: ledPresetSaved must be a control array")
        return false
    end
    
    self:debugPrint("Control validation passed")
    return true
end

-------------------[ Control Array Normalization ]------------------
function CameraPresetController:normalizeControlArrays()
    -- Pre-cache normalized arrays for efficient processing
    self.normalizedControls = {
        presetButtons = controls.btnCamPreset,
        matchLEDs = controls.ledPresetMatch,
        savedLEDs = controls.ledPresetSaved,
    }
    
    self:debugPrint(string.format("Normalized %d preset buttons, %d match LEDs, %d saved LEDs",
        #self.normalizedControls.presetButtons,
        #self.normalizedControls.matchLEDs,
        #self.normalizedControls.savedLEDs))
end

-------------------[ Debug and Utility Helpers ]------------------
function CameraPresetController:debugPrint(str)
    if self.debugging then
        print("[CameraPresets] " .. str)
    end
end

function CameraPresetController:setStatus(message, errorState)
    setProp(controls.txtStatus, "String", message)
    setProp(controls.txtStatus, "Value", errorState and 1 or 0)
end

-------------------[ JSON Module ]------------------
function CameraPresetController:initJSONModule()
    self.jsonModule = {
        save = function()
            local strTemp = rapidjson.encode(self.components.presets, {pretty=true, sort_keys=true})
            if not setProp(controls.txtJSONStorage, "String", strTemp) then
                self:debugPrint("No new JSON data to save")
                return false
            end
            self:debugPrint("JSON data saved")
            return true
        end,
        
        load = function()
            local jsonString = controls.txtJSONStorage.String
            if not jsonString or jsonString == "" then
                self:debugPrint("JSON storage is empty")
                return false
            end
            
            local success, tblTemp = pcall(rapidjson.decode, jsonString)
            if not success or type(tblTemp) ~= "table" then
                self:debugPrint("ERROR: Failed to decode JSON data")
                return false
            end
            
            self.components.presets = tblTemp
            self:debugPrint("JSON data loaded successfully")
            return true
        end
    }
end

-------------------[ Camera Module ]------------------
function CameraPresetController:initCameraModule()
    self.cameraModule = {
        discoverCameras = function()
            local cameraNames = {}
            local components = Component.GetComponents()
            
            for _, comp in ipairs(components) do
                if comp.Type == "onvif_camera_operative" then
                    table.insert(cameraNames, comp.Name)
                    self.components.cameras[comp.Name] = Component.New(comp.Name)
                    self:debugPrint("Found camera: " .. comp.Name)
                end
            end
            
            table.sort(cameraNames)
            return cameraNames
        end,
        
        purgeRemovedCameras = function()
            local purgedCount = 0
            for presetKey in pairs(self.components.presets) do
                if not self.components.cameras[presetKey] then
                    self.components.presets[presetKey] = nil
                    purgedCount = purgedCount + 1
                    self:debugPrint("Purged presets for removed camera: " .. presetKey)
                end
            end
            if purgedCount > 0 then
                self:debugPrint(string.format("Purged %d camera preset entries", purgedCount))
            end
        end,
        
        initializePresets = function(cameraNames)
            local presetCount = #self.normalizedControls.presetButtons
            local initializedCount = 0
            
            for _, camName in ipairs(cameraNames) do
                if not self.components.presets[camName] then
                    self.components.presets[camName] = {}
                    for i = 1, presetCount do
                        self.components.presets[camName][i] = "0 0 0"
                    end
                    initializedCount = initializedCount + 1
                    self:debugPrint("Initialized " .. presetCount .. " presets for: " .. camName)
                end
            end
            
            if initializedCount > 0 then
                self:debugPrint(string.format("Initialized presets for %d cameras", initializedCount))
            end
        end,
        
        updatePresetMatchLEDs = function()
            local camName = controls.seldevCams.String
            
            -- Early return guards
            if camName == "" then
                forEach(self.normalizedControls.matchLEDs, function(i, led)
                    setProp(led, "Boolean", false)
                end)
                return
            end
            
            local camera = self.components.cameras[camName]
            if not camera or not camera["ptz.preset"] then
                return
            end
            
            local currentPreset = camera["ptz.preset"].String
            local isMoving = camera["is.moving"] and camera["is.moving"].Boolean or false
            
            -- Update all LEDs in batch
            forEach(self.normalizedControls.matchLEDs, function(i, led)
                local matches = false
                if not isMoving and currentPreset ~= "" then
                    local savedPreset = self.components.presets[camName] and self.components.presets[camName][i]
                    if savedPreset then
                        matches = self:comparePresetWithTolerance(currentPreset, savedPreset)
                    end
                end
                setProp(led, "Boolean", matches)
            end)
        end,
        
        savePreset = function(presetIndex)
            local camName = controls.seldevCams.String
            
            -- Early return guards
            if camName == "" then return false end
            
            local camera = self.components.cameras[camName]
            if not camera or not camera["ptz.preset"] then return false end
            
            local oldPreset = self.components.presets[camName][presetIndex]
            local newPreset = camera["ptz.preset"].String
            
            self.components.presets[camName][presetIndex] = newPreset
            self:debugPrint(string.format("Saved %s Preset[%d]: %s → %s", 
                camName, presetIndex, oldPreset or "none", newPreset))
            
            self.jsonModule.save()
            return true
        end,
        
        recallPreset = function(presetIndex)
            local camName = controls.seldevCams.String
            
            -- Early return guards
            if camName == "" then return false end
            
            local camera = self.components.cameras[camName]
            if not camera or not camera["ptz.preset"] then return false end
            
            local preset = self.components.presets[camName] and self.components.presets[camName][presetIndex]
            if not preset or preset == "0 0 0" then
                self:debugPrint(string.format("Preset[%d] not saved for %s", presetIndex, camName))
                return false
            end
            
            setProp(camera["ptz.preset"], "String", preset)
            self:debugPrint(string.format("Recalled %s Preset[%d]: %s", camName, presetIndex, preset))
            return true
        end
    }
end

--------** Preset Tolerance Helper **--------
function CameraPresetController:comparePresetWithTolerance(currentPreset, savedPreset)
    -- Early return for exact match
    if currentPreset == savedPreset then return true end
    
    -- Parse preset strings (format: "pan tilt zoom")
    local currentPan, currentTilt, currentZoom = currentPreset:match("([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
    local savedPan, savedTilt, savedZoom = savedPreset:match("([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
    
    -- Guard against parse failure
    if not (currentPan and savedPan) then
        return false
    end
    
    -- Convert to numbers with guard
    currentPan, currentTilt, currentZoom = tonumber(currentPan), tonumber(currentTilt), tonumber(currentZoom)
    savedPan, savedTilt, savedZoom = tonumber(savedPan), tonumber(savedTilt), tonumber(savedZoom)
    
    if not (currentPan and currentTilt and currentZoom and savedPan and savedTilt and savedZoom) then
        return false
    end
    
    -- Compare with tolerance
    local tolerance = self.config.presetTolerance
    local panMatch = math.abs(currentPan - savedPan) <= tolerance
    local tiltMatch = math.abs(currentTilt - savedTilt) <= tolerance
    local zoomMatch = math.abs(currentZoom - savedZoom) <= tolerance
    
    return panMatch and tiltMatch and zoomMatch
end

--------** Router Module **--------
function CameraPresetController:initRouterModule()
    self.routerModule = {
        discoverRouters = function()
            local routerNames = {}
            local components = Component.GetComponents()
            
            for _, comp in ipairs(components) do
                if comp.Type == "video_router" then
                    self.components.routers[comp.Name] = Component.New(comp.Name)
                    table.insert(routerNames, comp.Name)
                    self:debugPrint("Found video router: " .. comp.Name)
                end
            end
            
            table.sort(routerNames)
            return routerNames
        end,
        
        syncCamChoiceWithRouter = function(router, routerKey)
            -- Early return guards
            if not router or not router[routerKey] then return false end
            
            local selectedRouterName = controls.compcamRouter.String or "(none)"
            
            -- Router output event handler
            bind(router[routerKey], function()
                local routedInputIndex = router[routerKey].Value
                self:debugPrint(string.format("Router %s.%s → Input %d", 
                    selectedRouterName, routerKey, routedInputIndex))
                
                -- Validate and update camera selection
                if routedInputIndex > 0 and routedInputIndex <= #controls.seldevCams.Choices then
                    setProp(controls.seldevCams, "Value", routedInputIndex)
                    setProp(controls.seldevCams, "String", controls.seldevCams.Choices[routedInputIndex])
                    self.cameraModule.updatePresetMatchLEDs()
                else
                    self:debugPrint(string.format("Invalid router input: %d", routedInputIndex))
                end
            end)
            
            -- Trigger once at startup to sync state
            router[routerKey].EventHandler()
            self:debugPrint(string.format("Synced %s.%s with camera selection", 
                selectedRouterName, routerKey))
            return true
        end,
        
        setupRouterSync = function()
            local selectedRouterName = controls.compcamRouter.String
            
            -- Early return if no router selected
            if selectedRouterName == "" then return false end
            
            local router = self.components.routers[selectedRouterName]
            if not router then
                self:debugPrint("Router not found: " .. selectedRouterName)
                return false
            end
            
            self:debugPrint("Setting up router sync: " .. selectedRouterName)
            
            -- Sync all configured outputs
            local syncCount = 0
            for _, output in ipairs(self.config.routerOutputs) do
                if router[output] then
                    if self.routerModule.syncCamChoiceWithRouter(router, output) then
                        syncCount = syncCount + 1
                    end
                else
                    self:debugPrint(string.format("Output %s not found on router", output))
                end
            end
            
            self:debugPrint(string.format("Synced %d router outputs", syncCount))
            return syncCount > 0
        end
    }
end

-------------------[ Component Management ]------------------
function CameraPresetController:setComponent(ctrl, componentType)
    -- Early return guards
    if not ctrl then return nil end
    
    local componentName = ctrl.String
    
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " selected")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    if componentName == self.clearString then
        self:debugPrint(componentType .. " cleared")
        setProp(ctrl, "String", "")
        setProp(ctrl, "Color", "white")
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Validate component
    local success, component = pcall(function() return Component.New(componentName) end)
    if not success or #Component.GetControls(component) < 1 then
        self:debugPrint("ERROR: Invalid " .. componentType .. " - " .. componentName)
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        self:setComponentInvalid(componentType)
        return nil
    end
    
    -- Valid component
    self:debugPrint("Set " .. componentType .. ": " .. componentName)
    setProp(ctrl, "Color", "white")
    self:setComponentValid(componentType)
    return component
end

function CameraPresetController:setComponentValid(componentType)
    self.state.invalidComponents[componentType] = false
    self:updateStatus()
end

function CameraPresetController:setComponentInvalid(componentType)
    self.state.invalidComponents[componentType] = true
    self:updateStatus()
end

function CameraPresetController:updateStatus()
    -- Check for invalid components
    for _, isInvalid in pairs(self.state.invalidComponents) do
        if isInvalid then
            self:setStatus("Invalid Components", true)
            return
        end
    end
    self:setStatus("OK", false)
end

function CameraPresetController:populateRoomControlsChoices()
    local names = {}
    local components = Component.GetComponents()
    
    for _, comp in ipairs(components) do
        if comp.Type == "device_controller_script" and comp.Name:match("^compRoomControls") then
            table.insert(names, comp.Name)
        end
    end
    
    table.sort(names)
    table.insert(names, self.clearString)
    controls.compRoomControls.Choices = names
end

--------** Event Handler Registration **--------
function CameraPresetController:registerEventHandlers()
    -- Batch register simple control handlers using handler map
    local controlHandlerMap = {
        [controls.seldevCams] = function()
            self.cameraModule.updatePresetMatchLEDs()
        end,
        [controls.compcamRouter] = function()
            self.routerModule.setupRouterSync()
        end,
        [controls.compRoomControls] = function()
            self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
        end,
        [controls.knbledOnTime] = function()
            self.config.ledOnTime = controls.knbledOnTime.Value
            self:debugPrint("LED On Time: " .. self.config.ledOnTime .. "s")
        end,
        [controls.knbHoldTime] = function()
            self.config.holdTime = controls.knbHoldTime.Value
            self:debugPrint("Hold Time: " .. self.config.holdTime .. "s")
        end,
    }
    
    -- Batch bind all control handlers
    for ctrl, handler in pairs(controlHandlerMap) do
        bind(ctrl, handler)
    end
    
    -- Register preset button handlers with timers
    self:registerPresetButtonHandlers()
    
    self:debugPrint("Event handlers registered")
end

function CameraPresetController:registerPresetButtonHandlers()
    local presetCount = #self.normalizedControls.presetButtons
    
    -- Initialize timers and state for each preset button
    forEach(self.normalizedControls.presetButtons, function(i, btn)
        self.state.longPressed[i] = false
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Countdown timer handler - detects long press
        self.state.countdownTimers[i].EventHandler = function()
            self.state.countdownTimers[i]:Stop()
            if btn.Boolean then
                self.state.longPressed[i] = true
                setProp(self.normalizedControls.savedLEDs[i], "Boolean", true)
                self.state.ledTimers[i]:Start(self.config.ledOnTime)
            end
        end
        
        -- LED timer handler - turns off saved LED
        self.state.ledTimers[i].EventHandler = function()
            self.state.ledTimers[i]:Stop()
            setProp(self.normalizedControls.savedLEDs[i], "Boolean", false)
        end
        
        -- Preset button event handler
        bind(btn, function(ctl)
            if ctl.Boolean then
                -- Button pressed - start countdown
                self.state.longPressed[i] = false
                self.state.countdownTimers[i]:Start(self.config.holdTime)
            else
                -- Button released - save or recall based on hold duration
                if self.state.longPressed[i] then
                    self.cameraModule.savePreset(i)
                else
                    self.cameraModule.recallPreset(i)
                end
                self.state.longPressed[i] = false
                self.cameraModule.updatePresetMatchLEDs()
            end
        end)
    end)
    
    self:debugPrint(string.format("Registered %d preset button handlers", presetCount))
end

--------** Initialization **--------
function CameraPresetController:initialize()
    -- Load saved presets from JSON
    self.jsonModule.load()
    
    -- Discover cameras and routers
    local cameraNames = self.cameraModule.discoverCameras()
    local routerNames = self.routerModule.discoverRouters()
    
    -- Clean up and initialize camera presets
    self.cameraModule.purgeRemovedCameras()
    self.cameraModule.initializePresets(cameraNames)
    
    -- Register camera event handlers for preset tracking
    self:registerCameraEventHandlers(cameraNames)
    
    -- Setup UI choices
    setProp(controls.seldevCams, "Choices", cameraNames)
    setProp(controls.compcamRouter, "Choices", routerNames)
    setProp(controls.txtJSONStorage, "IsDisabled", true)
    
    -- Populate room controls dropdown
    self:populateRoomControlsChoices()
    
    -- Set default camera and preset
    self:setDefaultCameraAndPreset(cameraNames)
    
    -- Setup router synchronization
    if #routerNames > 0 and routerNames[1] then
        setProp(controls.compcamRouter, "String", routerNames[1])
    end
    
    -- Set room controls component
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    
    -- Save initial state
    self.jsonModule.save()
    
    -- Set system status
    self:setStatus("OK", false)
    
    self:debugPrint(string.format("Initialized: %d cameras, %d routers, %d presets/camera",
        #cameraNames, #routerNames, #self.normalizedControls.presetButtons))
end

function CameraPresetController:registerCameraEventHandlers(cameraNames)
    forEach(cameraNames, function(_, camName)
        local camera = self.components.cameras[camName]
        if not camera then return end
        
        -- Position change handler
        if camera["ptz.preset"] then
            bind(camera["ptz.preset"], function()
                self.cameraModule.updatePresetMatchLEDs()
            end)
        end
        
        -- Movement status handler
        if camera["is.moving"] then
            bind(camera["is.moving"], function()
                self.cameraModule.updatePresetMatchLEDs()
            end)
        end
    end)
    
    self:debugPrint(string.format("Registered event handlers for %d cameras", #cameraNames))
end

function CameraPresetController:setDefaultCameraAndPreset(cameraNames)
    -- Early return if no cameras
    if #cameraNames == 0 then
        self:debugPrint("No cameras available")
        return
    end
    
    -- Find default camera or use first
    local selectedCameraIndex = 1
    for i, camName in ipairs(cameraNames) do
        if camName == self.config.defaultCamera then
            selectedCameraIndex = i
            break
        end
    end
    
    local selectedCamera = cameraNames[selectedCameraIndex]
    setProp(controls.seldevCams, "Value", selectedCameraIndex)
    setProp(controls.seldevCams, "String", selectedCamera)
    
    self:debugPrint("Default camera: " .. selectedCamera)
    
    -- Recall default preset if available
    local defaultPresetIndex = self.config.defaultPreset
    if self.components.presets[selectedCamera] and 
       self.components.presets[selectedCamera][defaultPresetIndex] and
       self.components.presets[selectedCamera][defaultPresetIndex] ~= "0 0 0" then
        self.cameraModule.recallPreset(defaultPresetIndex)
        self:debugPrint(string.format("Recalled preset %d", defaultPresetIndex))
    end
end

-------------------[ Cleanup ]------------------
function CameraPresetController:cleanup()
    local timerCount = 0
    
    -- Stop all countdown timers
    for _, timer in pairs(self.state.countdownTimers) do
        if timer then 
            timer:Stop()
            timerCount = timerCount + 1
        end
    end
    
    -- Stop all LED timers
    for _, timer in pairs(self.state.ledTimers) do
        if timer then 
            timer:Stop()
            timerCount = timerCount + 1
        end
    end
    
    -- Clear camera event handlers
    for _, camera in pairs(self.components.cameras) do
        if camera["ptz.preset"] then
            camera["ptz.preset"].EventHandler = nil
        end
        if camera["is.moving"] then
            camera["is.moving"].EventHandler = nil
        end
    end
    
    self:debugPrint(string.format("Cleanup complete: Stopped %d timers", timerCount))
end

-------------------[ Factory Function ]------------------
local function createCameraPresetController(config)
    -- Default configuration
    local defaultConfig = {
        debugging = true,
        holdTime = controls.knbHoldTime and controls.knbHoldTime.Value or 3.0,
        ledOnTime = controls.knbledOnTime and controls.knbledOnTime.Value or 2.5,
        presetTolerance = 0.1,
        routerOutputs = {"select.1"},
        defaultCamera = "devCam01",
        defaultPreset = 1
    }
    
    -- Merge user config with defaults
    local mergedConfig = config or defaultConfig
    if config then
        for key, value in pairs(defaultConfig) do
            if mergedConfig[key] == nil then
                mergedConfig[key] = value
            end
        end
    end
    
    -- Create controller with error handling
    local success, result = pcall(function()
        return CameraPresetController.new(mergedConfig)
    end)
    
    if success then
        print("[CameraPresets] ✓ Controller initialized successfully")
        return result
    else
        print("[CameraPresets] ✗ Initialization failed: " .. tostring(result))
        return nil
    end
end

-------------------[ Instance Creation ]------------------
-- Create and export the controller instance globally
myCameraPresetController = createCameraPresetController()

-- Also export the class for multiple instance support
CameraPresetController = CameraPresetController

-------------------[ API Reference ]------------------
--[[
CAMERA PRESET CONTROLLER API

Creating Controller:
  myCameraPresetController = createCameraPresetController({
    debugging = true,
    holdTime = 3.0,
    ledOnTime = 2.5,
    presetTolerance = 0.1,
    routerOutputs = {"select.1", "select.2"},
    defaultCamera = "devCam01",
    defaultPreset = 1
  })

Camera Module Methods:
  .cameraModule.savePreset(index)           - Save current camera position to preset
  .cameraModule.recallPreset(index)         - Recall saved preset
  .cameraModule.updatePresetMatchLEDs()     - Update LED feedback for current position
  .cameraModule.discoverCameras()           - Scan for ONVIF cameras
  .cameraModule.initializePresets(names)    - Initialize preset storage for cameras

JSON Module Methods:
  .jsonModule.save()                        - Save presets to JSON storage
  .jsonModule.load()                        - Load presets from JSON storage

Router Module Methods:
  .routerModule.setupRouterSync()           - Setup router output synchronization
  .routerModule.discoverRouters()           - Scan for video routers

Utility Methods:
  .cleanup()                                - Clean up timers and event handlers
  .setStatus(message, errorState)           - Set status display
  .debugPrint(message)                      - Print debug message (if enabled)

Configuration Access:
  .config.holdTime                          - Long press duration (seconds)
  .config.ledOnTime                         - LED feedback duration (seconds)
  .config.presetTolerance                   - Preset matching tolerance
  .config.routerOutputs                     - Router outputs to monitor
  .config.defaultCamera                     - Default camera selection
  .config.defaultPreset                     - Default preset to recall

Example Usage:
  -- Manual preset operations
  myCameraPresetController.cameraModule.savePreset(1)
  myCameraPresetController.cameraModule.recallPreset(2)
  
  -- Update configuration
  myCameraPresetController.config.presetTolerance = 0.2
  
  -- Force LED update
  myCameraPresetController.cameraModule.updatePresetMatchLEDs()
]]--
