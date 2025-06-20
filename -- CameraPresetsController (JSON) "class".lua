--[[ 
  Camera Preset Controller - Class-based Implementation
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.1
  
  Refactored to follow class-based pattern for modularity and reusability
  Maintains all existing camera preset functionality including JSON handling
  Preserves camera position change detection and LED update logic
  
  NEW FEATURES:
  - Preset Recall Feedback Tolerance: Configurable tolerance value for preset matching
    Allows LED feedback to indicate when camera is "close enough" to a saved preset
    Tolerance applies to pan, tilt, and zoom values independently
    Default tolerance: 0.1 units (adjustable via presetTolerance variable)
    To change tolerance: modify the presetTolerance variable at the top of the script
]]--

-- Define control references
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
    compCallSync = Controls.compCallSync,
    compVideoBridge = Controls.compVideoBridge,
    txtStatus = Controls.txtStatus,
}

-- Preset tolerance variable (can be adjusted as needed)
local presetTolerance = 0.1  -- Default tolerance value

-- Required libraries
rapidjson = require("rapidjson")

-- CameraPresetController class
CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

--------** Class Constructor **--------
function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Component storage
    self.components = {
        cameras = {},
        presets = {},
        roomControls = nil,
        callSync = nil,
        videoBridge = nil,
        invalid = {},
        routers = {},  -- New storage for video routers
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        combinedMode = true,  -- or false for divided
        invalidComponents = {}  -- Track invalid components
    }
    
    -- Configuration
    self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        presetTolerance = config and config.presetTolerance or presetTolerance,
        routerOutputs = config and config.routerOutputs or {"select.1"},  -- Default to first output
        defaultCamera = config and config.defaultCamera or "devCam01",  -- Default to first camera
        defaultPreset = config and config.defaultPreset or 1  -- Default to preset 1
    }
    
    -- Initialize modules
    self:initJSONModule()
    self:initCameraModule()
    self:initRouterModule()  -- New router module initialization
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

--------** JSON Module **--------
function CameraPresetController:initJSONModule()
    self.jsonModule = {
        save = function()
            local strTemp = rapidjson.encode(self.components.presets, {pretty=true, sort_keys=true})
            if strTemp ~= Controls.txtJSONStorage.String then
                Controls.txtJSONStorage.String = strTemp
                self:debugPrint("JSON data saved")
            else
                self:debugPrint("No new JSON data to save")
            end
        end,
        
        load = function()
            local tblTemp = rapidjson.decode(Controls.txtJSONStorage.String)
            if type(tblTemp) == "table" then
                self.components.presets = tblTemp
                self:debugPrint("JSON data loaded successfully")
            else
                self:debugPrint("JSON data was empty or invalid")
            end
        end
    }
end

--------** Camera Module **--------
function CameraPresetController:initCameraModule()
    self.cameraModule = {
        discoverCameras = function()
            local cameraNames = {}
            for index, tblComponents in pairs(Component.GetComponents()) do
                for k, v in pairs(tblComponents) do
                    if v == "onvif_camera_operative" then
                        table.insert(cameraNames, tblComponents.Name)
                        self.components.cameras[tblComponents.Name] = Component.New(tblComponents.Name)
                        self:debugPrint("Found camera: " .. tblComponents.Name)
                    end
                end
            end
            return cameraNames
        end,
        
        purgeRemovedCameras = function()
            for key, value in pairs(self.components.presets) do
                local found = false
                for k, v in pairs(self.components.cameras) do
                    if key == k then found = true end
                end
                if not found then
                    self.components.presets[key] = nil
                    self:debugPrint("Purged presets for missing camera: " .. key)
                end
            end
        end,
        
        initializePresets = function(cameraNames)
            for _, camName in pairs(cameraNames) do
                if self.components.presets[camName] == nil then
                    self.components.presets[camName] = {}
                    for i, v in ipairs(Controls.btnCamPreset) do
                        self.components.presets[camName][i] = "0 0 0"
                    end
                    self:debugPrint("Initialized presets for camera: " .. camName)
                end
            end
        end,
        
        updatePresetMatchLEDs = function()
            local camName = Controls.seldevCams.String
            local currentPreset = ""
            local isMoving = false
            
            -- Get current preset and movement status if camera exists
            if camName ~= "" and self.components.cameras[camName] then
                currentPreset = self.components.cameras[camName]["ptz.preset"].String
                -- Check if camera is moving
                if self.components.cameras[camName]["is.moving"] then
                    isMoving = self.components.cameras[camName]["is.moving"].Boolean
                end
            end
            
            -- Update all LEDs in one loop
            for i, led in ipairs(Controls.ledPresetMatch) do
                local presetMatches = false
                -- Skip tolerance checking if camera is moving
                if not isMoving and currentPreset ~= "" and self.components.presets[camName] and self.components.presets[camName][i] then
                    presetMatches = self:comparePresetWithTolerance(currentPreset, self.components.presets[camName][i])
                end
                led.Boolean = presetMatches
            end
        end,
        
        savePreset = function(presetIndex)
            local camName = Controls.seldevCams.String
            if camName ~= "" and self.components.cameras[camName] then
                local oldPreset = self.components.presets[camName][presetIndex]
                local newPreset = self.components.cameras[camName]["ptz.preset"].String
                self.components.presets[camName][presetIndex] = newPreset
                self:debugPrint(string.format("Saved %s Preset[%d] from %s to %s", 
                    camName, presetIndex, oldPreset, newPreset))
                self.jsonModule.save()
            end
        end,
        
        recallPreset = function(presetIndex)
            local camName = Controls.seldevCams.String
            if camName ~= "" and self.components.cameras[camName] then
                local preset = self.components.presets[camName][presetIndex]
                self.components.cameras[camName]["ptz.preset"].String = preset
                self:debugPrint(string.format("Recalled %s Preset[%d]: %s", 
                    camName, presetIndex, preset))
            end
        end
    }
end

--------** Call Sync Component **--------
function CameraPresetController:initCallSyncModule()
    self.callSyncModule = {
        setCallSyncComponent = function()
            self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
        end
    }
end

--------** Video Bridge Component **--------
function CameraPresetController:initVideoBridgeModule()
    self.videoBridgeModule = {
        setVideoBridgeComponent = function()
            self.components.videoBridge = self:setComponent(controls.compVideoBridge, "Video Bridge")
        end
    }
end

--------** Router Module **--------
function CameraPresetController:initRouterModule()
    self.routerModule = {
        discoverRouters = function()
            for index, tblComponents in pairs(Component.GetComponents()) do
                for k, v in pairs(tblComponents) do
                    if v == "video_router" then
                        self.components.routers[tblComponents.Name] = Component.New(tblComponents.Name)
                        self:debugPrint("Found video router: " .. tblComponents.Name)
                    end
                end
            end
        end,
        
        syncCamChoiceWithRouter = function(router, routerKey, camChoiceControl)
            local selectedRouterName = Controls.compcamRouter.String or "(none)"
            if not router or not router[routerKey] then
                self:debugPrint("Invalid router or router key")
                return
            end
            
            -- Event handler updates camChoiceControl based on router state
            router[routerKey].EventHandler = function()
                local routedInputIndex = router[routerKey].Value
                self:debugPrint(string.format("Router %s.%s EventHandler fired, Value=%s", selectedRouterName, routerKey, tostring(routedInputIndex)))
                
                -- Direct index mapping since router values match camera choice indices
                if routedInputIndex > 0 and routedInputIndex <= #camChoiceControl.Choices then
                    camChoiceControl.Value = routedInputIndex
                    camChoiceControl.String = camChoiceControl.Choices[routedInputIndex]
                    self:debugPrint(string.format("Set camChoiceControl.Value = %d (%s)", 
                        routedInputIndex, camChoiceControl.String))
                else
                    self:debugPrint(string.format("Invalid router input index: %d", routedInputIndex))
                end
                
                -- Update LED states after camera selection changes
                self.cameraModule.updatePresetMatchLEDs()
            end
            
            -- Call once at startup
            router[routerKey].EventHandler()
            self:debugPrint(string.format("Synchronized router %s.%s with camera choice", 
                selectedRouterName, routerKey))
        end,
        
        setupRouterSync = function()
            local selectedRouterName = Controls.compcamRouter.String
            local router = self.components.routers[selectedRouterName]
            
            if not router then
                self:debugPrint("No router selected or router not found for sync.")
                return
            end
            
            self:debugPrint(string.format("Setting up router sync for: %s", selectedRouterName))
            
            -- Setup sync for all configured outputs
            for _, output in ipairs(self.config.routerOutputs) do
                if router[output] then
                    self.routerModule.syncCamChoiceWithRouter(router, output, Controls.seldevCams)
                else
                    self:debugPrint(string.format("Router output %s not found", output))
                end
            end
        end
    }
end

--------** Debug Helper **--------
function CameraPresetController:debugPrint(str)
    if self.debugging then
        print("[Camera Presets Debug] " .. str)
    end
end

--------** Preset Tolerance Helper **--------
function CameraPresetController:comparePresetWithTolerance(currentPreset, savedPreset)
    -- If exact match, return true immediately
    if currentPreset == savedPreset then
        return true
    end
    
    -- Parse preset strings (format: "pan tilt zoom")
    local currentPan, currentTilt, currentZoom = currentPreset:match("([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
    local savedPan, savedTilt, savedZoom = savedPreset:match("([%-%d%.]+)%s+([%-%d%.]+)%s+([%-%d%.]+)")
    
    -- If parsing failed, fall back to exact string comparison
    if not currentPan or not savedPan then
        self:debugPrint("Failed to parse preset values, using exact comparison")
        return currentPreset == savedPreset
    end
    
    -- Convert to numbers
    currentPan = tonumber(currentPan)
    currentTilt = tonumber(currentTilt)
    currentZoom = tonumber(currentZoom)
    savedPan = tonumber(savedPan)
    savedTilt = tonumber(savedTilt)
    savedZoom = tonumber(savedZoom)
    
    -- Check if any value is nil (conversion failed)
    if not currentPan or not currentTilt or not currentZoom or 
       not savedPan or not savedTilt or not savedZoom then
        self:debugPrint("Failed to convert preset values to numbers")
        return false
    end
    
    -- Get current tolerance value from control
    local tolerance = self.config.presetTolerance
    
    -- Compare each axis with tolerance
    local panMatch = math.abs(currentPan - savedPan) <= tolerance
    local tiltMatch = math.abs(currentTilt - savedTilt) <= tolerance
    local zoomMatch = math.abs(currentZoom - savedZoom) <= tolerance
    
    local allMatch = panMatch and tiltMatch and zoomMatch
    
    -- Debug output for tolerance comparison
    if self.debugging and not allMatch then
        self:debugPrint(string.format("Tolerance check failed - Current: %s, Saved: %s, Tolerance: %.3f", 
            currentPreset, savedPreset, tolerance))
        self:debugPrint(string.format("  Pan: %.3f vs %.3f (diff: %.3f, match: %s)", 
            currentPan, savedPan, math.abs(currentPan - savedPan), tostring(panMatch)))
        self:debugPrint(string.format("  Tilt: %.3f vs %.3f (diff: %.3f, match: %s)", 
            currentTilt, savedTilt, math.abs(currentTilt - savedTilt), tostring(tiltMatch)))
        self:debugPrint(string.format("  Zoom: %.3f vs %.3f (diff: %.3f, match: %s)", 
            currentZoom, savedZoom, math.abs(currentZoom - savedZoom), tostring(zoomMatch)))
    end
    
    return allMatch
end

--------** Component Management **--------
function CameraPresetController:setComponent(ctrl, componentType)
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    else
        self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return Component.New(componentName)
    end
end

function CameraPresetController:setComponentInvalid(componentType)
    self.state.invalidComponents[componentType] = true
    self:checkStatus()
end

function CameraPresetController:setComponentValid(componentType)
    self.state.invalidComponents[componentType] = false
    self:checkStatus()
end

function CameraPresetController:checkStatus()
    for i, v in pairs(self.state.invalidComponents) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

function CameraPresetController:populateRoomControlsChoices()
    local names = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls") then
            table.insert(names, comp.Name)
        end
    end
    table.sort(names)
    table.insert(names, self.clearString)
    Controls.compRoomControls.Choices = names
end

--------** Event Handler Registration **--------
function CameraPresetController:registerEventHandlers()
    -- Camera selection handler
    Controls.seldevCams.EventHandler = function()
        self.cameraModule.updatePresetMatchLEDs()
    end
    
    -- Router selection handler
    Controls.compcamRouter.EventHandler = function()
        self.routerModule.setupRouterSync()
    end
    
    -- Room Controls selection handler
    Controls.compRoomControls.EventHandler = function()
        self.components.roomControls = self:setComponent(Controls.compRoomControls, "roomControls")
    end
    
    -- LED On Time knob handler
    Controls.knbledOnTime.EventHandler = function()
        self.config.ledOnTime = Controls.knbledOnTime.Value
        self:debugPrint("LED On Time updated to: " .. self.config.ledOnTime)
    end
    
    -- Initialize timers and button handlers for each preset
    for i, v in ipairs(Controls.btnCamPreset) do
        self.state.longPressed[i] = false
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Long press detection
        self.state.countdownTimers[i].EventHandler = function()
            self.state.countdownTimers[i]:Stop()
            if Controls.btnCamPreset[i].Boolean then
                self.state.longPressed[i] = true
                Controls.ledPresetSaved[i].Boolean = true
                self.state.ledTimers[i]:Start(self.config.ledOnTime)
            end
        end
        
        -- LED timer completion
        self.state.ledTimers[i].EventHandler = function()
            self.state.ledTimers[i]:Stop()
            Controls.ledPresetSaved[i].Boolean = false
        end
        
        -- Button press/release handler
        v.EventHandler = function(ctl)
            if ctl.Boolean then
                self.state.longPressed[i] = false
                self.state.countdownTimers[i]:Start(self.config.holdTime)
            else
                if self.state.longPressed[i] then
                    self.cameraModule.savePreset(i)
                else
                    self.cameraModule.recallPreset(i)
                end
                self.state.longPressed[i] = false
                self.cameraModule.updatePresetMatchLEDs()
            end
        end
    end
end

--------** Initialization **--------
function CameraPresetController:funcInit()
    -- Load saved presets
    self.jsonModule.load()
    
    -- Discover and initialize cameras and routers
    local cameraNames = self.cameraModule.discoverCameras()
    table.sort(cameraNames)  -- Ensure order is devCam01, devCam02, devCam03
    for i, name in ipairs(cameraNames) do
        self:debugPrint(string.format("Sorted cameraNames[%d]: %s", i, name))
    end
    self.routerModule.discoverRouters()
    self.cameraModule.purgeRemovedCameras()
    self.cameraModule.initializePresets(cameraNames)
    
    -- Set up camera position change handlers
    for _, camName in pairs(cameraNames) do
        self.components.cameras[camName]["ptz.preset"].EventHandler = function()
            self.cameraModule.updatePresetMatchLEDs()
        end
        
        -- Set up camera movement status handlers
        if self.components.cameras[camName]["is.moving"] then
            self.components.cameras[camName]["is.moving"].EventHandler = function()
                self.cameraModule.updatePresetMatchLEDs()
            end
        end
    end
    
    -- Setup router synchronization
    self.routerModule.setupRouterSync()
    
    -- Update UI
    Controls.seldevCams.Choices = cameraNames
    Controls.txtJSONStorage.IsDisabled = true
    
    -- Set default camera selection
    if #cameraNames > 0 then
        -- Try to set the configured default camera, fallback to first available
        local defaultCameraFound = false
        for i, camName in ipairs(cameraNames) do
            if camName == self.config.defaultCamera then
                Controls.seldevCams.String = camName
                Controls.seldevCams.Value = i
                defaultCameraFound = true
                self:debugPrint("Set default camera: " .. camName)
                break
            end
        end
        
        -- If configured default not found, use first camera
        if not defaultCameraFound then
            Controls.seldevCams.String = cameraNames[1]
            Controls.seldevCams.Value = 1
            self:debugPrint("Set fallback default camera: " .. cameraNames[1])
        end
        
        -- Recall default preset for the selected camera
        local selectedCamera = Controls.seldevCams.String
        if selectedCamera ~= "" and self.components.cameras[selectedCamera] then
            local defaultPresetIndex = self.config.defaultPreset
            if self.components.presets[selectedCamera] and 
               self.components.presets[selectedCamera][defaultPresetIndex] then
                self.cameraModule.recallPreset(defaultPresetIndex)
                self:debugPrint(string.format("Recalled default preset %d for camera: %s", 
                    defaultPresetIndex, selectedCamera))
            else
                self:debugPrint(string.format("Default preset %d not available for camera: %s", 
                    defaultPresetIndex, selectedCamera))
            end
        end
    end
    
    -- Populate room controls choices
    self:populateRoomControlsChoices()
    
    -- Set room controls component
    self.components.roomControls = self:setComponent(Controls.compRoomControls, "roomControls")
    
    -- Save initial state
    self.jsonModule.save()

    -- Set default router output and camera selection at startup
    for routerName, router in pairs(self.components.routers) do
        if router["select.1"] then
            router["select.1"].Value = 1
        end
    end
    
    -- After self.routerModule.discoverRouters()
    local routerNames = {}
    for name, _ in pairs(self.components.routers) do
        table.insert(routerNames, name)
    end
    table.sort(routerNames)
    Controls.compcamRouter.Choices = routerNames
    if #routerNames > 0 then
        Controls.compcamRouter.String = routerNames[1]  -- Default to first router
    end
    
    self:debugPrint("Camera Preset Controller Initialized")
    
end

--------** Cleanup **--------
function CameraPresetController:cleanup()
    -- Stop all timers
    for i, timer in pairs(self.state.countdownTimers) do
        if timer then timer:Stop() end
    end
    for i, timer in pairs(self.state.ledTimers) do
        if timer then timer:Stop() end
    end
    
    -- Clear event handlers
    for _, camera in pairs(self.components.cameras) do
        if camera["ptz.preset"].EventHandler then
            camera["ptz.preset"].EventHandler = nil
        end
        if camera["is.moving"] and camera["is.moving"].EventHandler then
            camera["is.moving"].EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createCameraPresetController(config)
    local defaultConfig = {
        debugging = true,
        holdTime = Controls.knbHoldTime.Value,
        ledOnTime = Controls.knbledOnTime.Value,
        presetTolerance = presetTolerance,
        routerOutputs = {"select.1", "select.2"},  -- Default to first two outputs, add more if needed
        defaultCamera = "devCam01",  -- Default camera selection
        defaultPreset = 1  -- Default preset to recall on startup
    }
    
    local controllerConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        return CameraPresetController.new(controllerConfig)
    end)
    
    if success then
        print("Successfully created Camera Preset Controller")
        return controller
    else
        print("Failed to create controller: " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main camera preset controller instance
myCameraPresetController = createCameraPresetController()

--------** Usage Examples **--------
--[[
-- Example usage of the camera preset controller:

-- Save a preset manually
myCameraPresetController.cameraModule.savePreset(1)

-- Recall a preset manually
myCameraPresetController.cameraModule.recallPreset(2)

-- Update LED states
myCameraPresetController.cameraModule.updatePresetMatchLEDs()

-- Save JSON data
myCameraPresetController.jsonModule.save()

-- Load JSON data
myCameraPresetController.jsonModule.load()
]]--
