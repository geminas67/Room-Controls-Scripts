--[[ 
  Camera Preset Controller - Class-based Implementation (Refactored from Original)
  Author: Nikolas Smith, Q-SYS (Refactored)
  2025-01-16
  Firmware Req: 10.0.0
  Version: 2.0
    
  Features:
  - Dynamic camera and router discovery
  - JSON-based preset storage and retrieval
  - Long-press save, short-press recall functionality
  - Router synchronization with camera selection
  - Immediate LED feedback with configurable timing
  - Event-driven architecture with optimized performance
]]--

-- Required libraries
rapidjson = require("rapidjson")

-- Global component references (Q-SYS specific)
Component = Component or {}
Timer = Timer or {}
Controls = Controls or {}

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
    knbLEDOnTime = Controls.knbLEDOnTime,
    txtJSONStorage = Controls.txtJSONStorage,
    knbHoldTime = Controls.knbHoldTime,
    compCamRouter = Controls.compCamRouter,
}

-------------------[ Camera Preset Controller Class ]------------------
CameraPresetController = {}
CameraPresetController.__index = CameraPresetController

-------------------[ Class Constructor ]------------------
function CameraPresetController.new(config)
    local self = setmetatable({}, CameraPresetController)
    
    -- Instance properties
    self.debugging = config and config.debugging or true
    
    -- Configuration
    self.config = {
        holdTime = config and config.holdTime or 3.0,
        ledOnTime = config and config.ledOnTime or 2.5,
        routerInputs = config and config.routerInputs or 3,
        routerOutputs = config and config.routerOutputs or 2,
        defaultCamera = config and config.defaultCamera or "",
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
        router = nil,
    }
    
    -- State tracking
    self.state = {
        longPressed = {},
        countdownTimers = {},
        ledTimers = {},
        currentSelectedCamera = {},
        cameraNames = {},
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
        "knbLEDOnTime",
        "txtJSONStorage",
        "knbHoldTime",
        "compCamRouter"
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
        
        setupPresetChangeHandlers = function(cameraNames)
            for _, camName in ipairs(cameraNames) do
                local camera = self.components.cameras[camName]
                if camera and camera["ptz.preset"] then
                    bind(camera["ptz.preset"], function()
                        self:updatePresetMatchLEDs()
                    end)
                    self:debugPrint("Set up preset change handler for: " .. camName)
                end
            end
        end
    }
end

-------------------[ Router Module ]------------------
function CameraPresetController:initRouterModule()
    self.routerModule = {
        initializeRouter = function()
            if controls.compCamRouter then
                self.components.router = Component.New("compCamRouter")
                self:debugPrint("Router component initialized")
                return true
            end
            self:debugPrint("Warning: No router component found")
            return false
        end,
        
        setupRouterHandlers = function()
            if not self.components.router then return end
            
            for outputNum = 1, self.config.routerOutputs do
                self.state.currentSelectedCamera[outputNum] = ""
                
                local selectControl = self.components.router["select." .. outputNum]
                if selectControl then
                    bind(selectControl, function()
                        self:updateCameraSelection(outputNum)
                    end)
                    self:debugPrint("Set up router handler for output " .. outputNum)
                    
                    -- Initialize selection if already set
                    if selectControl.Value > 0 then
                        self:updateCameraSelection(outputNum)
                    end
                else
                    self:debugPrint("Warning: select." .. outputNum .. " control not found on router")
                end
            end
        end
    }
end

-------------------[ State Management ]------------------
function CameraPresetController:resetComponentsArray()
    -- Reset all component references to ensure clean state
    self.components.cameras = {}
    self.components.presets = {}
    self.components.router = nil
    
    -- Reset state tracking
    self.state.longPressed = {}
    self.state.currentSelectedCamera = {}
    self.state.cameraNames = {}
    
    -- Clean up timers
    for i, timer in ipairs(self.state.countdownTimers) do
        if timer then timer:Stop() end
    end
    for i, timer in ipairs(self.state.ledTimers) do
        if timer then timer:Stop() end
    end
    
    self.state.countdownTimers = {}
    self.state.ledTimers = {}
    
    self:debugPrint("Component arrays reset successfully")
end

-------------------[ Preset Management ]------------------
function CameraPresetController:updatePresetMatchLEDs()
    local selectedCamera = self.state.currentSelectedCamera[1] or ""
    if selectedCamera == "" or not self.components.cameras[selectedCamera] then
        -- Clear all match LEDs
        forEach(self.normalizedControls.matchLEDs, function(_, led)
            setProp(led, "Boolean", false)
        end)
        return
    end
    
    local camera = self.components.cameras[selectedCamera]
    local currentPreset = camera["ptz.preset"].String
    
    forEach(self.normalizedControls.matchLEDs, function(i, led)
        local matchesPreset = (self.components.presets[selectedCamera] and 
                              self.components.presets[selectedCamera][i] == currentPreset)
        setProp(led, "Boolean", matchesPreset)
    end)
end

function CameraPresetController:updateCameraSelection(outputNum)
    if not self.components.router then return end
    
    local selectControl = self.components.router["select." .. outputNum]
    if not selectControl then return end
    
    local selectedIndex = selectControl.Value
    
    if selectedIndex and selectedIndex > 0 and selectedIndex <= #self.state.cameraNames then
        local selectedCamera = self.state.cameraNames[selectedIndex]
        self.state.currentSelectedCamera[outputNum] = selectedCamera
        
        -- Update dropdown to match router selection (for output 1)
        if outputNum == 1 then
            setProp(controls.seldevCams, "String", selectedCamera)
        end
        
        self:debugPrint("Output " .. outputNum .. " now controlling: " .. selectedCamera)
        self:updatePresetMatchLEDs()
    else
        self:debugPrint("Invalid camera selection for output " .. outputNum .. ": " .. tostring(selectedIndex))
    end
end

-------------------[ Event Handlers ]------------------
function CameraPresetController:createPresetButtonHandler(presetIndex)
    return function(ctl)
        local activeCamera = self.state.currentSelectedCamera[1] or controls.seldevCams.String
        
        if activeCamera == "" or not self.components.cameras[activeCamera] then
            self:debugPrint("No camera selected or camera not available")
            return
        end
        
        local camera = self.components.cameras[activeCamera]
        
        if ctl.Boolean then
            -- Button pressed - start countdown timer
            self.state.longPressed[presetIndex] = false
            self.state.countdownTimers[presetIndex]:Start(controls.knbHoldTime.Value)
        else
            -- Button released
            if self.state.longPressed[presetIndex] then
                -- Long press completed - save preset
                local oldPreset = self.components.presets[activeCamera][presetIndex]
                local newPreset = camera["ptz.preset"].String
                
                self.components.presets[activeCamera][presetIndex] = newPreset
                self.jsonModule.save()
                
                self:debugPrint(string.format("Saved %s Preset[%d] from %s to %s", 
                    activeCamera, presetIndex, oldPreset, newPreset))
            else
                -- Short press - recall preset
                local presetValue = self.components.presets[activeCamera][presetIndex]
                camera["ptz.preset"].String = presetValue
                
                self:debugPrint(string.format("Recalled %s Preset[%d] from %s", 
                    activeCamera, presetIndex, presetValue))
            end
            
            self.state.longPressed[presetIndex] = false
            self:updatePresetMatchLEDs()
        end
    end
end

function CameraPresetController:createCountdownHandler(presetIndex)
    return function()
        self.state.countdownTimers[presetIndex]:Stop()
        self.state.longPressed[presetIndex] = true
        setProp(self.normalizedControls.savedLEDs[presetIndex], "Boolean", true)
        self.state.ledTimers[presetIndex]:Start(controls.knbLEDOnTime.Value)
    end
end

function CameraPresetController:createLEDTimerHandler(presetIndex)
    return function()
        self.state.ledTimers[presetIndex]:Stop()
        setProp(self.normalizedControls.savedLEDs[presetIndex], "Boolean", false)
    end
end

function CameraPresetController:createCameraSelectionHandler()
    return function()
        local selectedCamera = controls.seldevCams.String
        if selectedCamera ~= "" then
            self.state.currentSelectedCamera[1] = selectedCamera
            self:updatePresetMatchLEDs()
            
            -- Update router to match manual selection
            for i, camName in ipairs(self.state.cameraNames) do
                if camName == selectedCamera then
                    local selectControl = self.components.router and self.components.router["select.1"]
                    if selectControl then
                        setProp(selectControl, "Value", i)
                    end
                    break
                end
            end
        end
    end
end

-------------------[ Event Registration ]------------------
function CameraPresetController:registerEventHandlers()
    -- Initialize timer arrays
    local presetCount = #self.normalizedControls.presetButtons
    for i = 1, presetCount do
        self.state.countdownTimers[i] = Timer.New()
        self.state.ledTimers[i] = Timer.New()
        
        -- Bind timer handlers
        bind(self.state.countdownTimers[i], self:createCountdownHandler(i))
        bind(self.state.ledTimers[i], self:createLEDTimerHandler(i))
    end
    
    -- Bind preset button handlers
    bindArray(self.normalizedControls.presetButtons, function(i, btn)
        return self:createPresetButtonHandler(i)
    end)
    
    -- Bind camera selection handler
    bind(controls.seldevCams, self:createCameraSelectionHandler())
    
    self:debugPrint(string.format("Registered event handlers for %d preset buttons", presetCount))
end

-------------------[ Initialization ]------------------
function CameraPresetController:initialize()
    self:debugPrint("Starting initialization...")
    
    -- Load existing presets
    self.jsonModule.load()
    
    -- Reset component arrays for clean state
    self:resetComponentsArray()
    
    -- Discover cameras
    self.state.cameraNames = self.cameraModule.discoverCameras()
    
    -- Purge removed cameras from presets
    self.cameraModule.purgeRemovedCameras()
    
    -- Initialize presets for discovered cameras
    self.cameraModule.initializePresets(self.state.cameraNames)
    
    -- Set up camera preset change handlers
    self.cameraModule.setupPresetChangeHandlers(self.state.cameraNames)
    
    -- Initialize router
    self.routerModule.initializeRouter()
    
    -- Set up router handlers
    self.routerModule.setupRouterHandlers()
    
    -- Update camera selection dropdown
    setProp(controls.seldevCams, "Choices", self.state.cameraNames)
    
    -- Disable JSON storage control
    setProp(controls.txtJSONStorage, "IsDisabled", true)
    
    -- Save final state
    self.jsonModule.save()
    
    self:debugPrint("Initialization completed successfully")
end

-------------------[ Factory Function ]------------------
local function createCameraPresetController(config)
    local success, instance = pcall(CameraPresetController.new, config)
    if success then
        print("[CameraPresets] Controller created successfully")
        return instance
    else
        print("[CameraPresets] ERROR: Failed to create controller - " .. tostring(instance))
        return nil
    end
end

-------------------[ Global Export ]------------------
-- Export both class and instance for external access
_G.CameraPresetController = CameraPresetController
_G.cameraPresetController = createCameraPresetController()

-------------------[ End of Script ]------------------
