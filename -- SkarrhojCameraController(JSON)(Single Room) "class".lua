--[[ 
  Single Room Camera Controller - Simplified Version
  Author: Based on Skaarhoj Camera Controller
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.0
  
  Simplified for single room operation with 5 cameras
  Camera Router Control Scheme:
  - select.1 = Monitor Output
  - select.2 = USB Output PC A
  - select.3 = USB Output PC B
  Self-initializing script with automatic system setup on load
]]--

-- SingleRoomCameraController class
SingleRoomCameraController = {}
SingleRoomCameraController.__index = SingleRoomCameraController

-- At the top of your script
rapidjson = require("rapidjson")

--------** Class Constructor **--------
function SingleRoomCameraController.new(roomName, config)
    local self = setmetatable({}, SingleRoomCameraController)
    
    -- Instance properties
    self.roomName = roomName or "Single Room"
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
    -- Component storage - simplified for single room
    self.components = {
        callSync = nil, -- Single call sync component
        skaarhojPTZController = nil, -- Controls.compdevSkaarhojPTZ.Choices
        camRouter = nil, -- Controls.compcamRouter.Choices
        devCams = {}, -- Controls.compdevCams.Choices (cam01, cam02, cam03, cam04, cam05)
        camACPR = nil, -- Controls.compcamACPR.Choices (single ACPR)
        compRoomControls = nil, -- Controls.compRoomControls.Choices (single room controls)
        productionMode = nil,
        invalid = {}
    }
    
    -- State tracking - simplified
    self.state = {
        hookState = false,
        currentCameraSelection = 1,
        privacyState = false
    }
    
    -- Configuration
    self.config = {
        buttonColors = {
            presetCalled = 'Blue',
            presetNotCalled = 'White',
            buttonOff = 'Off',
            warmWhite = 'Warm White',
            purple = 'Purple',
            red = 'Red'
        },
        defaultCameraRouterSettings = {
            monitor = '5',
            usbA = '5',
            usbB = '5'
        },
        -- Camera Router Select Control Mapping:
        -- select.1 = Monitor Output
        -- select.2 = USB Output PC A
        -- select.3 = USB Output PC B
        initializationDelay = 0.1,
        recalibrationDelay = 1.0
    }
    
    -- Preset storage: [cameraNumber][presetIndex] = { value = ... }
    self.presets = {}

    -- Last recalled preset per camera
    self.lastRecalledPreset = {}
    
    -- Initialize modules
    self:initCameraModule()
    self:initPrivacyModule()
    self:initRoutingModule()
    self:initPTZModule()
    self:initHookStateModule()
    
    return self
end

--------** Safe Component Access **--------
function SingleRoomCameraController:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value
                return true
            elseif action == "setPosition" then
                component[control].Position = value
                return true
            elseif action == "setString" then
                component[control].String = value
                return true
            elseif action == "trigger" then
                component[control]:Trigger()
                return true
            elseif action == "get" then
                return component[control].Boolean
            elseif action == "getPosition" then
                return component[control].Position
            elseif action == "getString" then
                return component[control].String
            end
        end
        return false
    end)
    
    if not success then
        self:debugPrint("Component access error: " .. tostring(result))
        return false
    end
    return result
end

--------** Debug Helper **--------
function SingleRoomCameraController:debugPrint(str)
    if self.debugging then
        print("[" .. self.roomName .. " Camera Debug] " .. str)
    end
end

--------** Camera Module **--------
function SingleRoomCameraController:initCameraModule()
    self.cameraModule = {
        setPrivacy = function(state)
            self.state.privacyState = state
            for _, camera in pairs(self.components.devCams) do
                if camera then
                    self:safeComponentAccess(camera, "toggle.privacy", "set", state)
                end
            end
            self:updatePrivacyVisuals()
        end,
        
        setAutoFrame = function(state)
            for _, camera in pairs(self.components.devCams) do
                if camera then
                    self:safeComponentAccess(camera, "autoframe.enable", "set", state)
                end
            end
        end,
        
        recalibratePTZ = function()
            for _, camera in pairs(self.components.devCams) do
                if camera then
                    self:safeComponentAccess(camera, "ptz.recalibrate", "set", true)
                end
            end
            
            -- Stop recalibration after delay
            Timer.CallAfter(function()
                for _, camera in pairs(self.components.devCams) do
                    if camera then
                        self:safeComponentAccess(camera, "ptz.recalibrate", "set", false)
                    end
                end
            end, self.config.recalibrationDelay)
        end,
        
        getCameraCount = function()
            local count = 0
            for _, camera in pairs(self.components.devCams) do
                if camera then count = count + 1 end
            end
            return count
        end
    }
end

--------** Privacy Module **--------
function SingleRoomCameraController:initPrivacyModule()
    self.privacyModule = {
        setPrivacy = function(state)
            self.cameraModule.setPrivacy(state)
        end,
        
        updatePrivacyButton = function()
            if self.state.privacyState then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", self.config.buttonColors.red)
            else
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", self.config.buttonColors.buttonOff)
            end
        end
    }
end

--------** Routing Module **--------
function SingleRoomCameraController:initRoutingModule()
    -- Helper function to set router output
    local function setRouterOutput(outputNumber, cameraNumber)
        self:safeComponentAccess(self.components.camRouter, "select." .. outputNumber, "setString", tostring(cameraNumber))
    end
    
    -- Helper function to clear router outputs
    local function clearRoutes()
        setRouterOutput(1, self.config.defaultCameraRouterSettings.monitor)
        setRouterOutput(2, self.config.defaultCameraRouterSettings.usbA)
        setRouterOutput(3, self.config.defaultCameraRouterSettings.usbB)
    end

    self.routingModule = {
        setMonitorRoute = function(cameraNumber)
            setRouterOutput(1, cameraNumber)
        end,
        
        setUSBRouteA = function(cameraNumber)
            setRouterOutput(2, cameraNumber)
        end,
        
        setUSBRouteB = function(cameraNumber)
            setRouterOutput(3, cameraNumber)
        end,
        
        clearRoutes = function()
            clearRoutes()
        end,
        
        setAllRoutes = function(cameraNumber)
            setRouterOutput(1, cameraNumber)
            setRouterOutput(2, cameraNumber)
            setRouterOutput(3, cameraNumber)
        end
    }
end

--------** PTZ Module **--------
function SingleRoomCameraController:initPTZModule()
    -- Helper function to set button properties
    local function setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
        if headerText then
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".headerText", "setString", headerText)
        end
        if screenText then
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".screenText", "setString", screenText)
        end
        if controlLink then
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".controlLink", "setString", controlLink)
        end
        if color then
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".color", "setString", color)
        end
    end

    self.ptzModule = {
        enablePC = function()
            setButtonProperties(8, "Send to PC", nil, nil, self.config.buttonColors.warmWhite)
        end,
        
        disablePC = function()
            setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff)
        end,
        
        setButtonActive = function(buttonNumber, active)
            local headerText = active and "Active" or "Preview Mon"
            setButtonProperties(buttonNumber, headerText)
        end,
        
        setCameraLabel = function(buttonNumber, cameraNumber)
            local cameraLabels = {
                ["1"] = "CAM-01",
                ["2"] = "CAM-02", 
                ["3"] = "CAM-03",
                ["4"] = "CAM-04",
                ["5"] = "CAM-05"
            }
            local label = cameraLabels[tostring(cameraNumber)] or ""
            setButtonProperties(buttonNumber, nil, label)
        end
    }
end

--------** Hook State Module **--------
function SingleRoomCameraController:initHookStateModule()
    self.hookStateModule = {
        setHookState = function(state)
            self.state.hookState = state
            if state then
                -- Off Hook - Privacy Off
                self.ptzModule.enablePC()
                self.privacyModule.setPrivacy(false)
            else
                -- On Hook - Privacy On
                self.ptzModule.disablePC()
                self.privacyModule.setPrivacy(true)
            end
        end,
        
        handleHookState = function(isOffHook)
            self.hookStateModule.setHookState(isOffHook)
            if isOffHook then
                if self.components.camRouter then
                    self:safeComponentAccess(self.components.camRouter, "select.1", "setString", "01")
                    self:safeComponentAccess(self.components.camRouter, "select.2", "setString", "01")
                    self:safeComponentAccess(self.components.camRouter, "select.3", "setString", "01")
                end
            end
        end
    }
end

--------** Component Management **--------
function SingleRoomCameraController:setComponent(ctrl, componentType)
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

function SingleRoomCameraController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function SingleRoomCameraController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function SingleRoomCameraController:checkStatus()
    for i, v in pairs(self.components.invalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------** Component Setup Functions **--------
function SingleRoomCameraController:setCallSyncComponent()
    self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
    if self.components.callSync ~= nil then
        self.components.callSync["off.hook"].EventHandler = function()
            local hookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
            self.hookStateModule.handleHookState(hookState)
        end
    end
end

function SingleRoomCameraController:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
end

function SingleRoomCameraController:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SingleRoomCameraController:setDevCamComponent(idx)
    if not Controls.compdevCams or not Controls.compdevCams[idx] then
        self:debugPrint("Camera control " .. idx .. " not found in compdevCams array")
        return
    end
    
    local cameraLabels = {[1] = "CAM-01", [2] = "CAM-02", [3] = "CAM-03", [4] = "CAM-04", [5] = "CAM-05"}
    local componentType = cameraLabels[idx] or "Camera [" .. idx .. "]"
    self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], componentType)
end

function SingleRoomCameraController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(Controls.compcamACPR, "Camera ACPR")
    if self.components.camACPR ~= nil then
        self.components.camACPR["TrackingBypass"].EventHandler = function()
            local bypassState = self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "get")
            self.cameraModule.setAutoFrame(not bypassState)
            self:debugPrint(bypassState and "Auto Framing Disabled" or "Auto Framing Enabled")
        end
    end
end

function SingleRoomCameraController:setCompRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
end

function SingleRoomCameraController:setupComponents()
    -- Setup single components
    self:setCallSyncComponent()
    self:setSkaarhojPTZComponent()
    self:setCamRouterComponent()
    self:setCamACPRComponent()
    self:setCompRoomControlsComponent()
    
    -- Setup camera components (cam01, cam02, cam03, cam04, cam05)
    if Controls.compdevCams then
        for i = 1, 5 do
            self:setDevCamComponent(i)
        end
    else
        self:debugPrint("compdevCams control not found - skipping camera component setup")
    end
    
    -- Setup legacy components (optional)
    if Controls.btnProductionMode then
        self.components.productionMode = self:setComponent(Controls.btnProductionMode, "Production Mode")
    else
        self:debugPrint("WARNING: Controls.productionMode not found - some features may be limited")
    end
end

--------** Helper Functions **--------
function SingleRoomCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

function SingleRoomCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    
    -- Recalibrate PTZ cameras
    self.cameraModule.recalibratePTZ()
    
    -- Clear camera routing
    self.routingModule.clearRoutes()
    
    -- Set initial privacy and button states
    Timer.CallAfter(function()
        self.privacyModule.setPrivacy(true)
        self.ptzModule.setButtonActive(1, false)
        self.ptzModule.setButtonActive(2, false)
        self.ptzModule.setButtonActive(3, false)
        self.ptzModule.setButtonActive(4, false)
        self.ptzModule.setButtonActive(5, false)
        self.ptzModule.enablePC()
        self.ptzModule.setCameraLabel(8, "")
        self.ptzModule.disablePC()
        self:debugPrint("System initialization completed")
    end, self.config.recalibrationDelay)
end

--------** Component Name Discovery **--------
function SingleRoomCameraController:getComponentNames()
    local namesTable = {
        CallSyncNames = {},
        SkaarhojPTZNames = {},
        CamRouterNames = {},
        DevCamNames = {},
        CamACPRNames = {},
        CompRoomControlsNames = {},
    }

    -- Get all components and categorize them
    for i, comp in pairs(Component.GetComponents()) do
        -- Skip components that are likely script comments or invalid
        if comp.Name and comp.Name ~= "" and not string.match(comp.Name, "^%s*%-%-") then
            -- Call Sync components
            if comp.Type == "call_sync" then
                table.insert(namesTable.CallSyncNames, comp.Name)
            
            -- Skaarhoj PTZ Controller
            elseif comp.Type == "%PLUGIN%8a9d1632-c069-47d7-933c-cab299e75a5f%FP%_fefe17b4f72c22b6bab67399fef8482d" or
                   string.match(comp.Name, "Skaarhoj") then
                table.insert(namesTable.SkaarhojPTZNames, comp.Name)
            
            -- Camera Router
            elseif comp.Type == "video_router" then
                table.insert(namesTable.CamRouterNames, comp.Name)
            
            -- Camera devices
            elseif comp.Type == "onvif_camera_operative" then
                table.insert(namesTable.DevCamNames, comp.Name)
            
            -- ACPR components
            elseif comp.Type == "%PLUGIN%648260e3-c166-4b00-98ba-ba16ksnza4a63b0%FP%_a4d2263b4380c424e16eebb67084f355" or
                   string.match(comp.Name, "ACPR") then
                table.insert(namesTable.CamACPRNames, comp.Name)
            
            -- Room Controls
            elseif comp.Type == "device_controller_script" and string.match(comp.Name, "compRoomControls") then
                table.insert(namesTable.CompRoomControlsNames, comp.Name)
            end
        end
    end

    -- Sort and add clear option to all tables
    for tableName, componentList in pairs(namesTable) do
        table.sort(componentList)
        table.insert(componentList, self.clearString)
        self:debugPrint("Found " .. #componentList - 1 .. " " .. tableName)
    end

    -- Set choices for all control arrays
    if Controls.compCallSync then
        Controls.compCallSync.Choices = namesTable.CallSyncNames
    end
    
    if Controls.compdevSkaarhojPTZ then
        Controls.compdevSkaarhojPTZ.Choices = namesTable.SkaarhojPTZNames
    end
    
    if Controls.compcamRouter then
        Controls.compcamRouter.Choices = namesTable.CamRouterNames
    end
    
    if Controls.compdevCams then
        for i, v in ipairs(Controls.compdevCams) do
            v.Choices = namesTable.DevCamNames
        end
        self:debugPrint("Set compdevCams choices for " .. #Controls.compdevCams .. " controls")
    else
        self:debugPrint("compdevCams control not found - camera selection will be limited")
    end
    
    if Controls.compcamACPR then
        Controls.compcamACPR.Choices = namesTable.CamACPRNames
    end
    
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = namesTable.CompRoomControlsNames
    end
end

--------** Event Handler Registration **--------
function SingleRoomCameraController:registerEventHandlers()
    self:debugPrint("Registering event handlers...")
    
    -- Component selection handlers
    if Controls.compCallSync then
        Controls.compCallSync.EventHandler = function()
            self:setCallSyncComponent()
        end
        self:debugPrint("Registered compCallSync handler")
    else
        self:debugPrint("WARNING: Controls.compCallSync not found")
    end

    if Controls.compdevSkaarhojPTZ then
        Controls.compdevSkaarhojPTZ.EventHandler = function()
            self:setSkaarhojPTZComponent()
        end
        self:debugPrint("Registered compdevSkaarhojPTZ handler")
    else
        self:debugPrint("WARNING: Controls.compdevSkaarhojPTZ not found")
    end

    if Controls.compcamRouter then
        Controls.compcamRouter.EventHandler = function()
            self:setCamRouterComponent()
        end
        self:debugPrint("Registered compcamRouter handler")
    else
        self:debugPrint("WARNING: Controls.compcamRouter not found")
    end

    if Controls.compdevCams then
        for i, devCamComp in ipairs(Controls.compdevCams) do
            devCamComp.EventHandler = function()
                self:setDevCamComponent(i)
            end
        end
        self:debugPrint("Registered " .. #Controls.compdevCams .. " compdevCams handlers")
    else
        self:debugPrint("WARNING: Controls.compdevCams not found")
    end

    if Controls.compcamACPR then
        Controls.compcamACPR.EventHandler = function()
            self:setCamACPRComponent()
        end
        self:debugPrint("Registered compcamACPR handler")
    else
        self:debugPrint("WARNING: Controls.compcamACPR not found")
    end

    if Controls.compRoomControls then
        Controls.compRoomControls.EventHandler = function()
            self:setCompRoomControlsComponent()
        end
        self:debugPrint("Registered compRoomControls handler")
    else
        self:debugPrint("WARNING: Controls.compRoomControls not found")
    end
    
    -- Register Production Mode handler for camACPR TrackingBypass
    if Controls.btnProductionMode and self.components.camACPR then
        Controls.btnProductionMode.EventHandler = function()
            if Controls.btnProductionMode.Boolean then
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", true)
            else
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", false)
            end
        end
        -- Set initial state on startup
        if Controls.btnProductionMode.Boolean then
            self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", true)
        else
            self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", false)
        end
    end
    
    self:debugPrint("Event handler registration completed")
end

--------** Initialization **--------
function SingleRoomCameraController:funcInit()
    self:debugPrint("Starting Single Room Camera Controller initialization...")
    
    -- Error check: Verify Controls exist before proceeding
    local requiredControls = {
        "compCallSync", 
        "compdevSkaarhojPTZ", 
        "compcamRouter", 
        "compdevCams", 
        "compcamACPR", 
        "compRoomControls", 
        "roomName"
    }
    
    for _, controlName in ipairs(requiredControls) do
        if not Controls[controlName] then
            self:debugPrint("ERROR: Required control '" .. controlName .. "' not found!")
            return
        end
    end
    
    self:debugPrint("All required controls found, proceeding with initialization...")
    
    -- Get component names first
    self:debugPrint("Calling getComponentNames()...")
    self:getComponentNames()
    
    -- Setup components
    self:debugPrint("Calling setupComponents()...")
    self:setupComponents()
    
    -- Register event handlers
    self:debugPrint("Calling registerEventHandlers()...")
    self:registerEventHandlers()
    
    -- Perform system initialization
    self:debugPrint("Calling performSystemInitialization()...")
    self:performSystemInitialization()
    
    -- Helper function to initialize button with delay
    local function initButton(buttonNumber, cameraNumber, delayMultiplier)
        local delay = self.config.initializationDelay * (delayMultiplier or 2)
        Timer.CallAfter(function()
            if self.components.skaarhojPTZController then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".controlLink", "setString", "Camera " .. cameraNumber)
                Timer.CallAfter(function()
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".headerText", "setString", "Preview Mon")
                end, delay)
            end
        end, delay)
    end
    
    -- Initialize button states for 5 cameras
    self:debugPrint("Initializing button states...")
    initButton(1, 1, 2)
    initButton(2, 2, 2)
    initButton(3, 3, 2)
    initButton(4, 4, 2)
    initButton(5, 5, 2)
    
    -- Load presets from JSON
    self:loadPresets()
    self:updatePresetButtonColors()
    self:registerPresetButtonHandlers()
    
    self:debugPrint("Single Room Camera Controller Initialized with " .. self.cameraModule.getCameraCount() .. " cameras")
end

--------** Cleanup **--------
function SingleRoomCameraController:cleanup()
    -- Clear event handlers for all components
    for name, component in pairs(self.components) do
        if type(component) == "table" and component.EventHandler then
            component.EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

--------** Factory Function **--------
local function createSingleRoomController(roomName, config)
    print("Creating Single Room Camera Controller for: " .. tostring(roomName))
    
    local defaultConfig = {
        debugging = true,
        buttonColors = {
            presetCalled = 'Blue',
            presetNotCalled = 'White',
            buttonOff = 'Off',
            warmWhite = 'Warm White',
            purple = 'Purple',
            red = 'Red'
        },
        defaultCameraRouterSettings = {
            monitor = '6',
            usbA = '6',
            usbB = '6'
        },
        initializationDelay = 0.1,
        recalibrationDelay = 1.0
    }
    
    local finalConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        print("Creating controller instance...")
        local instance = SingleRoomCameraController.new(roomName, finalConfig)
        print("Controller instance created successfully")
        
        print("Initializing controller...")
        instance:funcInit() -- Initialize after instance creation
        print("Controller initialization completed")
        
        return instance
    end)
    
    if success then
        print("Successfully created Single Room Camera Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        print("Error details: " .. debug.traceback())
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main camera controller instance
print("Starting Single Room Camera Controller script...")

-- Check if required Controls exist
if not Controls.roomName then
    print("ERROR: Controls.roomName not found!")
    return
end

local formattedRoomName = "[" .. Controls.roomName.String .. "]"
print("Room name: " .. formattedRoomName)

mySingleRoomController = createSingleRoomController(formattedRoomName)

if mySingleRoomController then
    print("Single Room Camera Controller created successfully!")
else
    print("ERROR: Failed to create Single Room Camera Controller!")
end

--------** Usage Examples **--------
--[[
-- Example usage of the Single Room Camera Controller:

-- Set privacy
mySingleRoomController.privacyModule.setPrivacy(true)

-- Set camera routing
mySingleRoomController.routingModule.setMonitorRoute(1)  -- Sets select.1
mySingleRoomController.routingModule.setUSBRouteA(2)     -- Sets select.2
mySingleRoomController.routingModule.setUSBRouteB(3)     -- Sets select.3

-- Set all routes to same camera
mySingleRoomController.routingModule.setAllRoutes(1)

-- Control PTZ buttons
mySingleRoomController.ptzModule.enablePC()
mySingleRoomController.ptzModule.disablePC()

-- Handle hook states
mySingleRoomController.hookStateModule.handleHookState(true)

-- Get camera count
local cameraCount = mySingleRoomController.cameraModule.getCameraCount()

-- Recalibrate PTZ
mySingleRoomController.cameraModule.recalibratePTZ()
]]-- 

-- Load presets from JSON
function SingleRoomCameraController:loadPresets()
    local json = Controls.txtJSONStorage.String
    if json and json ~= "" then
        local ok, data = pcall(rapidjson.decode, json)
        if ok and type(data) == "table" then
            self.presets = data
        end
    end
end

-- Save presets to JSON
function SingleRoomCameraController:savePresets()
    Controls.txtJSONStorage.String = rapidjson.encode(self.presets, {pretty=true, sort_keys=true})
end

-- Update button colors for the current camera
function SingleRoomCameraController:updatePresetButtonColors(cameraNumber)
    local last = self.lastRecalledPreset and self.lastRecalledPreset[cameraNumber]
    for i = 1, 10 do
        local btnNum = 17 + i  -- Button18..Button27
        local color = (last == i) and "Blue" or "White"
        self:safeComponentAccess(self.components.skaarhojPTZController, "Button"..btnNum..".color", "setString", color)
    end
end

-- Event handler for each preset button
function SingleRoomCameraController:registerPresetButtonHandlers()
    for i = 18, 27 do
        local presetIndex = i - 17  -- Preset 1-10
        self.components.skaarhojPTZController["Button"..i..".press"].EventHandler = function(ctl)
            local camNum = self.state.currentCameraSelection
            self.presets[camNum] = self.presets[camNum] or {}
            if ctl.Boolean then
                -- Start long press timer (implement your timer logic)
            else
                if longPressed and longPressed[presetIndex] then
                    -- Save preset
                    self.presets[camNum][presetIndex] = { value = getCurrentPTZData() }
                    self:savePresets()
                else
                    -- Recall preset
                    local preset = self.presets[camNum][presetIndex]
                    if preset then
                        recallPTZData(preset.value)
                        self.lastRecalledPreset[camNum] = presetIndex
                        self:updatePresetButtonColors(camNum)
                    end
                end
            end
        end
    end
end

-- When camera selection changes:
function SingleRoomCameraController:onCameraSelectionChanged(newCameraNumber)
    self:updatePresetButtonColors(newCameraNumber)
end 