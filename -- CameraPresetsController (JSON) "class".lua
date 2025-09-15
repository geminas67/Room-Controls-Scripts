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
    devCams = Controls.devCams,
    btnCamPreset = Controls.btnCamPreset,
    ledPresetMatch = Controls.ledPresetMatch,
    ledPresetSaved = Controls.ledPresetSaved,
    knbledOnTime = Controls.knbledOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compcamRouter = Controls.compcamRouter,
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus,
}

-- Preset tolerance variable (can be adjusted as needed)
local presetTolerance = 0.1  -- Default tolerance value

-- Required libraries
rapidjson = require("rapidjson")

-------------------[ Control Validation ]-------------------
local function validateControls()
    local required = {
        devCams = controls.devCams,
        btnCamPreset = controls.btnCamPreset,
        ledPresetMatch = controls.ledPresetMatch,
        ledPresetSaved = controls.ledPresetSaved,
        txtJSONStorage = controls.txtJSONStorage,
        txtStatus = controls.txtStatus
    }
    
    local optional = {
        knbledOnTime = controls.knbledOnTime,
        knbHoldTime = controls.knbHoldTime,
        compcamRouter = controls.compcamRouter,
        compRoomControls = controls.compRoomControls,
        compCallSync = controls.compCallSync
    }
    
    local missing = {}
    local warnings = {}
    
    -- Check required controls
    for name, control in pairs(required) do
        if not control then
            table.insert(missing, name)
        end
    end
    
    -- Check optional controls for warnings
    for name, control in pairs(optional) do
        if not control then
            table.insert(warnings, name)
        end
    end
    
    -- Report missing required controls
    if #missing > 0 then
        print("ERROR: CameraPresetController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        print("Controller initialization aborted.")
        return false
    end
    
    -- Report warnings for missing optional controls
    if #warnings > 0 then
        print("WARNING: CameraPresetController - Missing optional controls:")
        for _, name in ipairs(warnings) do
            print("  - " .. name)
        end
    end
    
    return true
end

-------------------[ Array Normalization ]-------------------
local function normalizeControlArrays()
    -- Normalize controls that should be arrays
    local arrayControls = {'btnCamPreset', 'ledPresetMatch', 'ledPresetSaved'}
    
    for _, controlName in ipairs(arrayControls) do
        local control = controls[controlName]
        if control and type(control) ~= "table" then
            controls[controlName] = {control}
        end
    end
end

-------------------[ Utility Functions ]-------------------
local function isArr(obj)
    return type(obj) == "table" and obj[1] ~= nil
end

local function getControlArray(control)
    if not control then return {} end
    return isArr(control) and control or {control}
end

local function setProp(obj, prop, value)
    if not obj or obj[prop] == value then return false end
    obj[prop] = value
    return true
end

local function bind(control, handler)
    if control and control.EventHandler ~= handler then
        control.EventHandler = handler
        return true
    end
    return false
end

local function bindArray(controls, handler)
    local bound = 0
    for i, control in ipairs(getControlArray(controls)) do
        if bind(control, handler) then
            bound = bound + 1
        end
    end
    return bound
end

local function forEach(array, fn)
    if not isArr(array) then return end
    for i, item in ipairs(array) do
        fn(item, i)
    end
end

-------------------[ Component State Management Utility ]-------------------
local function resetComponentsArray(componentsTable, componentType)
    if not componentsTable or not componentType then return false end
    
    -- Clear existing components of this type
    if componentsTable[componentType] then
        componentsTable[componentType] = {}
    end
    
    -- Initialize component array if it doesn't exist
    if not componentsTable[componentType] then
        componentsTable[componentType] = {}
    end
    
    return true
end

-------------------[ Base Module ]-------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "BaseModule"
    return self
end

function BaseModule:debugPrint(message)
    if self.controller and self.controller.debugging then
        print(string.format("[%s Debug] %s", self.name, message))
    end
end

function BaseModule:init()
    -- Override in derived modules
end

function BaseModule:cleanup()
    -- Override in derived modules
end

-----------------[ Class Constructor ]-------------------
CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

function CameraPresetController.new(config)
    -- Early validation - return nil if validation fails
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays early
    normalizeControlArrays()
    
    local self = setmetatable({}, CameraPresetController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        cameras = "onvif_camera_operative",
        routers = "video_router",
        roomControls = "device_controller_script"
    }
    self.components = {
        cameras = {},
        presets = {},
        roomControls = nil,
        callSync = nil,
        videoBridge = nil,
        invalid = {},
        routers = {},
    }
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        combinedMode = true, -- or false for divided
        invalidComponents = {}
    }
        self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        presetTolerance = config and config.presetTolerance or presetTolerance,
        routerOutputs = config and config.routerOutputs or {"select.1"},  -- Default to first output
        defaultCamera = config and config.defaultCamera or "devCam01",  -- Default to first camera
        defaultPreset = config and config.defaultPreset or 1  -- Default to preset 1
    }
        self.componentColors = {
            white = "white",
            pink = "pink"
    }

    self:initJSONModule()
    self:initCameraModule()
    self:initRouterModule()
    self:registerEventHandlers()
    self:funcInit()
    
    return self
end

-----------------[ JSON Module ]-------------------
local JSONModule = setmetatable({}, {__index = BaseModule})
JSONModule.__index = JSONModule

function JSONModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "JSONModule"), JSONModule)
    return self
end

function JSONModule:save()
    if not self.controller.components.presets then return false end
    
    local strTemp = rapidjson.encode(self.controller.components.presets, {pretty=true, sort_keys=true})
    if not setProp(controls.txtJSONStorage, "String", strTemp) then
        self:debugPrint("No new JSON data to save")
        return false
    end
    
    self:debugPrint("JSON data saved")
    return true
end

function JSONModule:load()
    if not controls.txtJSONStorage.String or controls.txtJSONStorage.String == "" then
        self:debugPrint("JSON storage is empty")
        return false
    end
    
    local tblTemp = rapidjson.decode(controls.txtJSONStorage.String)
    if type(tblTemp) ~= "table" then
        self:debugPrint("JSON data was invalid")
        return false
    end
    
    self.controller.components.presets = tblTemp
    self:debugPrint("JSON data loaded successfully")
    return true
end

function CameraPresetController:initJSONModule()
    self.jsonModule = JSONModule.new(self)
end

-----------------[ Camera Module ]-------------------
local CameraModule = setmetatable({}, {__index = BaseModule})
CameraModule.__index = CameraModule

function CameraModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "CameraModule"), CameraModule)
    return self
end

function CameraModule:discoverCameras()
    -- Reset cameras array for fresh discovery
    resetComponentsArray(self.controller.components, "cameras")
    
    local cameraNames = {}
    local components = Component.GetComponents()
    
    if not components then
        self:debugPrint("No components available for discovery")
        return cameraNames
    end
    
    for _, tblComponents in pairs(components) do
        if not tblComponents.Type or not tblComponents.Name then
            goto continue
        end
        
        if tblComponents.Type == self.controller.componentTypes.cameras then
            table.insert(cameraNames, tblComponents.Name)
            self.controller.components.cameras[tblComponents.Name] = Component.New(tblComponents.Name)
            self:debugPrint("Found camera: " .. tblComponents.Name)
        end
        
        ::continue::
    end
    
    return cameraNames
end
function CameraModule:purgeRemovedCameras()
    if not self.controller.components.presets then return end
    
    for cameraName in pairs(self.controller.components.presets) do
        if not self.controller.components.cameras[cameraName] then
            self.controller.components.presets[cameraName] = nil
            self:debugPrint("Purged presets for missing camera: " .. cameraName)
        end
    end
end

function CameraModule:initializePresets(cameraNames)
    if not cameraNames or #cameraNames == 0 then
        self:debugPrint("No cameras to initialize presets for")
        return
    end
    
    local presetControls = getControlArray(controls.btnCamPreset)
    if #presetControls == 0 then
        self:debugPrint("No preset controls available")
        return
    end
    
    for _, camName in pairs(cameraNames) do
        if not self.controller.components.presets[camName] then
            self.controller.components.presets[camName] = {}
            for i = 1, #presetControls do
                self.controller.components.presets[camName][i] = "0 0 0"
            end
            self:debugPrint("Initialized presets for camera: " .. camName)
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
        self:debugPrint("Camera not found: " .. camName)
        return
    end
    
    -- Early return if camera is moving
    local isMoving = camera["is.moving"] and camera["is.moving"].Boolean or false
    if isMoving then
        forEach(getControlArray(controls.ledPresetMatch), function(led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local currentPreset = camera["ptz.preset"] and camera["ptz.preset"].String or ""
    if currentPreset == "" then
        self:debugPrint("No current preset available for camera: " .. camName)
        return
    end
    
    local savedPresets = self.controller.components.presets[camName]
    if not savedPresets then
        self:debugPrint("No saved presets for camera: " .. camName)
        return
    end
    
    -- Update LEDs efficiently
    local ledControls = getControlArray(controls.ledPresetMatch)
    for i, led in ipairs(ledControls) do
        local presetMatches = savedPresets[i] and 
            self.controller:comparePresetWithTolerance(currentPreset, savedPresets[i]) or false
        setProp(led, "Boolean", presetMatches)
    end
end
function CameraModule:savePreset(presetIndex)
    local camName = controls.devCams.String
    if not camName or camName == "" then
        self:debugPrint("No camera selected for preset save")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:debugPrint("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local newPreset = camera["ptz.preset"].String
    if not newPreset or newPreset == "" then
        self:debugPrint("No current preset available to save")
        return false
    end
    
    -- Ensure presets table exists
    if not self.controller.components.presets[camName] then
        self.controller.components.presets[camName] = {}
    end
    
    local oldPreset = self.controller.components.presets[camName][presetIndex] or "none"
    self.controller.components.presets[camName][presetIndex] = newPreset
    
    self:debugPrint(string.format("Saved %s Preset[%d] from %s to %s", 
        camName, presetIndex, oldPreset, newPreset))
    
    -- Save to JSON
    return self.controller.jsonModule:save()
end

function CameraModule:recallPreset(presetIndex)
    local camName = controls.devCams.String
    if not camName or camName == "" then
        self:debugPrint("No camera selected for preset recall")
        return false
    end
    
    local camera = self.controller.components.cameras[camName]
    if not camera or not camera["ptz.preset"] then
        self:debugPrint("Invalid camera or missing preset control: " .. camName)
        return false
    end
    
    local savedPresets = self.controller.components.presets[camName]
    if not savedPresets or not savedPresets[presetIndex] then
        self:debugPrint(string.format("No saved preset[%d] for camera: %s", presetIndex, camName))
        return false
    end
    
    local preset = savedPresets[presetIndex]
    if preset == "0 0 0" then
        self:debugPrint(string.format("Preset[%d] not initialized for camera: %s", presetIndex, camName))
        return false
    end
    
    setProp(camera["ptz.preset"], "String", preset)
    self:debugPrint(string.format("Recalled %s Preset[%d]: %s", camName, presetIndex, preset))
    return true
end

function CameraPresetController:initCameraModule()
    self.cameraModule = CameraModule.new(self)
end

-----------------[ Call Sync ]-------------------
function CameraPresetController:initCallSyncModule()
    self.callSyncModule = {
        setCallSyncComponent = function()
            self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
        end
    }
end

-----------------[ Video Bridge ]-------------------
function CameraPresetController:initVideoBridgeModule()
    self.videoBridgeModule = {
        setVideoBridgeComponent = function()
            self.components.videoBridge = self:setComponent(controls.compVideoBridge, "Video Bridge")
        end
    }
end

-----------------[ Router Module ]-------------------
local RouterModule = setmetatable({}, {__index = BaseModule})
RouterModule.__index = RouterModule

function RouterModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "RouterModule"), RouterModule)
    return self
end

function RouterModule:discoverRouters()
    -- Reset routers array for fresh discovery
    resetComponentsArray(self.controller.components, "routers")
    
    local components = Component.GetComponents()
    if not components then
        self:debugPrint("No components available for router discovery")
        return
    end
    
    for _, tblComponents in pairs(components) do
        if not tblComponents.Type or not tblComponents.Name then
            goto continue
        end
        
        if tblComponents.Type == self.controller.componentTypes.routers then
            self.controller.components.routers[tblComponents.Name] = Component.New(tblComponents.Name)
            self:debugPrint("Found video router: " .. tblComponents.Name)
        end
        
        ::continue::
    end
end
function RouterModule:syncCamChoiceWithRouter(router, routerKey, camChoiceControl)
    local selectedRouterName = controls.compcamRouter.String or "(none)"
    
    if not router or not router[routerKey] then
        self:debugPrint("Invalid router or router key for sync")
        return false
    end
    
    if not camChoiceControl then
        self:debugPrint("Invalid camera choice control for sync")
        return false
    end
    
    -- Create optimized event handler
    local eventHandler = function()
        local routedInputIndex = router[routerKey].Value
        
        -- Guard clause for invalid indices
        if not routedInputIndex or routedInputIndex <= 0 or routedInputIndex > #camChoiceControl.Choices then
            self:debugPrint(string.format("Invalid router input index: %s", tostring(routedInputIndex)))
            return
        end
        
        -- Update camera choice efficiently
        if setProp(camChoiceControl, "Value", routedInputIndex) then
            camChoiceControl.String = camChoiceControl.Choices[routedInputIndex]
            self:debugPrint(string.format("Router %s.%s -> Camera: %s", 
                selectedRouterName, routerKey, camChoiceControl.String))
            
            -- Update LED states after camera selection changes
            self.controller.cameraModule:updatePresetMatchLEDs()
        end
    end
    
    -- Bind event handler
    if bind(router[routerKey], eventHandler) then
        self:debugPrint(string.format("Bound router %s.%s event handler", selectedRouterName, routerKey))
        
        -- Initialize state immediately
        eventHandler()
        return true
    end
    
    return false
end
function RouterModule:setupRouterSync()
    local selectedRouterName = controls.compcamRouter.String
    
    if not selectedRouterName or selectedRouterName == "" then
        self:debugPrint("No router selected for sync setup")
        return false
    end
    
    local router = self.controller.components.routers[selectedRouterName]
    if not router then
        self:debugPrint("Router not found: " .. selectedRouterName)
        return false
    end
    
    self:debugPrint("Setting up router sync for: " .. selectedRouterName)
    
    local syncCount = 0
    local routerOutputs = self.controller.config.routerOutputs or {"select.1"}
    
    -- Setup sync for all configured outputs
    for _, output in ipairs(routerOutputs) do
        if router[output] then
            if self:syncCamChoiceWithRouter(router, output, controls.devCams) then
                syncCount = syncCount + 1
            end
        else
            self:debugPrint(string.format("Router output %s not found on %s", output, selectedRouterName))
        end
    end
    
    self:debugPrint(string.format("Successfully synced %d router outputs", syncCount))
    return syncCount > 0
end

function CameraPresetController:initRouterModule()
    self.routerModule = RouterModule.new(self)
end

-----------------[ Debug ]-------------------
function CameraPresetController:debugPrint(str)
    if self.debugging then
        print("[Camera Presets Debug] " .. str)
    end
end

-----------------[ Preset Tolerance ]-------------------
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

-----------------[ Component Management ]-------------------
function CameraPresetController:setComponent(ctrl, componentType)
    self:debugPrint("Setting Component: " .. componentType)
    local componentName = ctrl.String
    
    if componentName == "" then
        self:debugPrint("No " .. componentType .. " Component Selected")
        ctrl.Color = self.componentColors.white
        self:setComponentValid(componentType)
        return nil
    elseif componentName == self.clearString then
        self:debugPrint(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = self.componentColors.white
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        self:debugPrint(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = self.componentColors.pink
        self:setComponentInvalid(componentType)
        return nil
    else
        self:debugPrint("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = self.componentColors.white
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
        if comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(names, comp.Name)
        end
    end
    table.sort(names)
    table.insert(names, self.clearString)
    Controls.compRoomControls.Choices = names
end

-----------------[ Event Handler Registration ]-------------------
function CameraPresetController:registerEventHandlers()
    -- Core control handlers map
    local coreHandlers = {
        devCams = function()
            self.cameraModule:updatePresetMatchLEDs()
        end,
        compcamRouter = function()
            self.routerModule:setupRouterSync()
        end,
        compRoomControls = function()
            self.components.roomControls = self:setComponent(controls.compRoomControls, "roomControls")
        end,
        knbledOnTime = function()
            self.config.ledOnTime = controls.knbledOnTime.Value
            self:debugPrint("LED On Time updated to: " .. self.config.ledOnTime)
        end
    }
    
    -- Batch register core handlers
    for controlName, handler in pairs(coreHandlers) do
        local control = controls[controlName]
        if control then
            bind(control, handler)
            self:debugPrint("Registered handler for: " .. controlName)
        end
    end
    
    -- Initialize preset button system
    self:initPresetButtonHandlers()
end

function CameraPresetController:initPresetButtonHandlers()
    local presetButtons = getControlArray(controls.btnCamPreset)
    local ledControls = getControlArray(controls.ledPresetSaved)
    
    if #presetButtons == 0 then
        self:debugPrint("No preset buttons found for handler registration")
        return
    end
    
    -- Initialize button state and timers
    for i = 1, #presetButtons do
        self.state.longPressed[i] = false
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Countdown timer handler (long press detection)
        self.state.countdownTimers[i].EventHandler = function()
            self.state.countdownTimers[i]:Stop()
            if presetButtons[i].Boolean then
                self.state.longPressed[i] = true
                if ledControls[i] then
                    setProp(ledControls[i], "Boolean", true)
                end
                self.state.ledTimers[i]:Start(self.config.ledOnTime)
            end
        end
        
        -- LED timer handler (turn off save indicator)
        self.state.ledTimers[i].EventHandler = function()
            self.state.ledTimers[i]:Stop()
            if ledControls[i] then
                setProp(ledControls[i], "Boolean", false)
            end
        end
        
        -- Button press/release handler
        local buttonHandler = function(ctl)
            if ctl.Boolean then
                -- Button pressed - start long press timer
                self.state.longPressed[i] = false
                self.state.countdownTimers[i]:Start(self.config.holdTime)
            else
                -- Button released - determine action
                if self.state.longPressed[i] then
                    self.cameraModule:savePreset(i)
                else
                    self.cameraModule:recallPreset(i)
                end
                self.state.longPressed[i] = false
                self.cameraModule:updatePresetMatchLEDs()
            end
        end
        
        bind(presetButtons[i], buttonHandler)
    end
    
    self:debugPrint(string.format("Initialized %d preset button handlers", #presetButtons))
end

function CameraPresetController:setupCameraEventHandlers(cameraNames)
    if not cameraNames or #cameraNames == 0 then
        self:debugPrint("No cameras available for event handler setup")
        return
    end
    
    for _, camName in pairs(cameraNames) do
        local camera = self.components.cameras[camName]
        if not camera then
            self:debugPrint("Camera component not found: " .. camName)
            goto continue
        end
        
        -- Set up preset change handler
        if camera["ptz.preset"] then
            bind(camera["ptz.preset"], function()
                self.cameraModule:updatePresetMatchLEDs()
            end)
        end
        
        -- Set up movement status handler
        if camera["is.moving"] then
            bind(camera["is.moving"], function()
                self.cameraModule:updatePresetMatchLEDs()
            end)
        end
        
        ::continue::
    end
    
    self:debugPrint(string.format("Setup event handlers for %d cameras", #cameraNames))
end

function CameraPresetController:updateCameraUI(cameraNames)
    -- Update camera choices safely
    if controls.devCams then
        controls.devCams.Choices = cameraNames or {}
    end
    
    -- Disable JSON storage editing
    if controls.txtJSONStorage then
        setProp(controls.txtJSONStorage, "IsDisabled", true)
    end
    
    -- Populate router choices
    self:updateRouterChoices()
    
    -- Setup room controls choices
    self:populateRoomControlsChoices()
end

function CameraPresetController:updateRouterChoices()
    if not controls.compcamRouter then return end
    
    local routerNames = {}
    for name in pairs(self.components.routers) do
        table.insert(routerNames, name)
    end
    table.sort(routerNames)
    
    controls.compcamRouter.Choices = routerNames
    if #routerNames > 0 then
        setProp(controls.compcamRouter, "String", routerNames[1])
    end
end

-----------------[ Initialization ]-------------------
function CameraPresetController:funcInit()
    self:debugPrint("Starting controller initialization...")
    
    -- Early exit if essential modules not available
    if not self.jsonModule or not self.cameraModule or not self.routerModule then
        self:debugPrint("CRITICAL: Essential modules not initialized")
        return false
    end
    
    -- Load saved presets
    if not self.jsonModule:load() then
        self:debugPrint("Warning: Could not load existing JSON presets")
    end
    
    -- Discover and initialize cameras and routers
    local cameraNames = self.cameraModule:discoverCameras()
    if not cameraNames or #cameraNames == 0 then
        self:debugPrint("Warning: No cameras discovered")
        cameraNames = {}
    else
        table.sort(cameraNames)  -- Ensure consistent order
        self:debugPrint(string.format("Discovered %d cameras", #cameraNames))
    end
    
    -- Router discovery (optional)
    self.routerModule:discoverRouters()
    
    -- Cleanup and initialize camera presets
    self.cameraModule:purgeRemovedCameras()
    self.cameraModule:initializePresets(cameraNames)
    
    -- Set up camera event handlers with error checking
    self:setupCameraEventHandlers(cameraNames)
    
    -- Setup router synchronization (optional)
    if not self.routerModule:setupRouterSync() then
        self:debugPrint("Router sync setup failed or no router available")
    end
    
    -- Update UI safely
    self:updateCameraUI(cameraNames)
    
    -- Set default camera selection with improved error handling
    self:setDefaultCamera(cameraNames)
    
    -- Set room controls component
    if controls.compRoomControls then
        self.components.roomControls = self:setComponent(controls.compRoomControls, "roomControls")
    end
    
    -- Save initial state
    if not self.jsonModule:save() then
        self:debugPrint("Warning: Could not save initial JSON state")
    end

    -- Initialize router defaults
    self:initializeRouterDefaults()
    
    self:debugPrint("Camera Preset Controller initialization completed successfully")
    return true
end

function CameraPresetController:setDefaultCamera(cameraNames)
    if not cameraNames or #cameraNames == 0 then
        self:debugPrint("No cameras available for default selection")
        return
    end
    
    local defaultCameraFound = false
    
    -- Try to set the configured default camera
    for i, camName in ipairs(cameraNames) do
        if camName == self.config.defaultCamera then
            if setProp(controls.devCams, "String", camName) then
                controls.devCams.Value = i
                defaultCameraFound = true
                self:debugPrint("Set default camera: " .. camName)
            end
            break
        end
    end
    
    -- Fallback to first camera if default not found
    if not defaultCameraFound and controls.devCams then
        setProp(controls.devCams, "String", cameraNames[1])
        controls.devCams.Value = 1
        self:debugPrint("Set fallback default camera: " .. cameraNames[1])
    end
    
    -- Recall default preset for the selected camera
    self:recallDefaultPreset()
end

function CameraPresetController:recallDefaultPreset()
    local selectedCamera = controls.devCams.String
    
    if not selectedCamera or selectedCamera == "" then
        self:debugPrint("No camera selected for default preset recall")
        return
    end
    
    if not self.components.cameras[selectedCamera] then
        self:debugPrint("Selected camera not found: " .. selectedCamera)
        return
    end
    
    local defaultPresetIndex = self.config.defaultPreset
    local savedPresets = self.components.presets[selectedCamera]
    
    if savedPresets and savedPresets[defaultPresetIndex] and 
       savedPresets[defaultPresetIndex] ~= "0 0 0" then
        if self.cameraModule:recallPreset(defaultPresetIndex) then
            self:debugPrint(string.format("Recalled default preset %d for camera: %s", 
                defaultPresetIndex, selectedCamera))
        end
    else
        self:debugPrint(string.format("Default preset %d not available for camera: %s", 
            defaultPresetIndex, selectedCamera))
    end
end

function CameraPresetController:initializeRouterDefaults()
    -- Set default router output values
    for routerName, router in pairs(self.components.routers) do
        if router["select.1"] then
            setProp(router["select.1"], "Value", 1)
            self:debugPrint("Set default router output for: " .. routerName)
        end
    end
end

-----------------[ Cleanup ]-------------------
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

-----------------[ Enhanced Factory ]-------------------
local function createCameraPresetController(config)
    print("CameraPresetController Factory: Starting initialization...")
    
    -- Build configuration with graceful fallbacks
    local defaultConfig = {
        debugging = true,
        holdTime = 3.0,
        ledOnTime = 2.5,
        presetTolerance = presetTolerance,
        routerOutputs = {"select.1", "select.2"},
        defaultCamera = "devCam01",
        defaultPreset = 1
    }
    
    -- Enhanced config merging with fallbacks for controls
    local controllerConfig = config or {}
    
    -- Safe control value extraction with fallbacks
    if controls.knbHoldTime and controls.knbHoldTime.Value then
        controllerConfig.holdTime = controllerConfig.holdTime or controls.knbHoldTime.Value
    else
        controllerConfig.holdTime = controllerConfig.holdTime or defaultConfig.holdTime
        print("WARNING: knbHoldTime control not available, using default: " .. defaultConfig.holdTime)
    end
    
    if controls.knbledOnTime and controls.knbledOnTime.Value then
        controllerConfig.ledOnTime = controllerConfig.ledOnTime or controls.knbledOnTime.Value
    else
        controllerConfig.ledOnTime = controllerConfig.ledOnTime or defaultConfig.ledOnTime
        print("WARNING: knbledOnTime control not available, using default: " .. defaultConfig.ledOnTime)
    end
    
    -- Merge remaining defaults
    for key, value in pairs(defaultConfig) do
        if controllerConfig[key] == nil then
            controllerConfig[key] = value
        end
    end
    
    -- Attempt controller creation with comprehensive error handling
    local success, controller = pcall(function()
        return CameraPresetController.new(controllerConfig)
    end)
    
    if not success then
        print("ERROR: CameraPresetController factory failed during construction:")
        print("  " .. tostring(controller))
        print("  Attempting graceful degradation...")
        
        -- Attempt minimal configuration fallback
        local minimalConfig = {
            debugging = false,
            holdTime = 3.0,
            ledOnTime = 2.5,
            presetTolerance = 0.1,
            routerOutputs = {"select.1"},
            defaultCamera = "",
            defaultPreset = 1
        }
        
        local fallbackSuccess, fallbackController = pcall(function()
            return CameraPresetController.new(minimalConfig)
        end)
        
        if fallbackSuccess and fallbackController then
            print("SUCCESS: Created CameraPresetController with minimal configuration")
            print("WARNING: Some features may be limited due to missing controls")
            return fallbackController
        else
            print("CRITICAL: Factory failed even with minimal configuration")
            print("  " .. tostring(fallbackController or "Unknown error"))
            return nil
        end
    end
    
    if not controller then
        print("ERROR: Controller validation failed - required controls missing")
        return nil
    end
    
    print("SUCCESS: CameraPresetController created successfully")
    print("  Configuration: " .. (controllerConfig.debugging and "Debug enabled" or "Production mode"))
    print("  Features: Router sync, JSON persistence, preset tolerance")
    
    return controller
end

-- Export both class and factory for external access
CameraPresetController.createInstance = createCameraPresetController

-----------------[ Instance Creation ]-------------------
-- Create the main camera preset controller instance
myCameraPresetController = createCameraPresetController()

-----------------[ Usage Examples ]-------------------
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

