--[[ 
    Single Room Camera Controller - Modular/Refactored Version
    Author: Nikolas Smith, Q-SYS (Based on Perplexity AI Refactor)
    Version: 3.0 | Date: 2025-01-27
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular)
    - Modular architecture with separate domain classes
    - DRY event registration using centralized event maps
    - Following SystemAutomationController patterns
]]--

-------------------[ Control References ]-------------------
local controls = {
    roomName = Controls.roomName,
    txtStatus = Controls.txtStatus,
    compCallSync = Controls.compCallSync,
    compdevSkaarhojPTZ = Controls.compdevSkaarhojPTZ,
    compcamRouter = Controls.compcamRouter,
    compdevCams = Controls.compdevCams,
    compcamACPR = Controls.compcamACPR,
    compRoomControls = Controls.compRoomControls,
    btnProductionMode = Controls.btnProductionMode
}

local function validateControls()
    if not controls.roomName or not controls.txtStatus then
        print("ERROR: Missing required controls: roomName or txtStatus")
        return false
    end
    return true
end

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function getControlArray(ctrl)
    if isArr(ctrl) then return ctrl end
    return type(ctrl) == "table" and { ctrl } or {}
end

local function setProp(ctrl, prop, val)
    if ctrl then ctrl[prop] = val end
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    for i, ctrl in ipairs(getControlArray(ctrls)) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

local function forEach(ctrls, fn)
    for i, ctrl in ipairs(getControlArray(ctrls)) do fn(i, ctrl) end
end

-------------------[ Base Module Class ]------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    return self
end

function BaseModule:debug(msg)
    self.controller:debugPrint("[" .. self.name .. "] " .. msg)
end

function BaseModule:cleanup()
    self:debug("Cleanup complete")
end

-------------------[ Camera Module ]------------------------
local CameraModule = setmetatable({}, BaseModule)
CameraModule.__index = CameraModule

function CameraModule:create(controller)
    local self = BaseModule.new(controller, "Camera")
    setmetatable(self, CameraModule)
    return self
end

function CameraModule:setPrivacy(state)
    if not self.controller.components.devCams then return end
    
    self.controller.state.privacyState = state
    for _, cam in pairs(self.controller.components.devCams) do
        if cam then 
            self.controller:safeComponentAccess(cam, "toggle.privacy", "set", state)
        end
    end
    self:updatePrivacyButton()
end

function CameraModule:setAutoFrame(state)
    if not self.controller.components.devCams then return end
    
    for _, cam in pairs(self.controller.components.devCams) do
        if cam then 
            self.controller:safeComponentAccess(cam, "autoframe.enable", "set", state)
        end
    end
end

function CameraModule:recalibratePTZ()
    if not self.controller.components.devCams then return end
    
    for _, cam in pairs(self.controller.components.devCams) do
        if cam then 
            self.controller:safeComponentAccess(cam, "ptz.recalibrate", "trigger")
        end
    end
end

function CameraModule:getCameraCount()
    if not self.controller.components.devCams then return 0 end
    
    local count = 0
    for _, cam in pairs(self.controller.components.devCams) do
        if cam then count = count + 1 end
    end
    return count
end

function CameraModule:updatePrivacyButton()
    local ptz = self.controller.components.skaarhojPTZController
    if not ptz then return end
    
    local color = self.controller.state.privacyState and 
        self.controller.config.buttonColors.red or 
        self.controller.config.buttonColors.buttonOff
    self.controller:safeComponentAccess(ptz, "Button6.color", "setString", color)
end

-------------------[ Routing Module ]----------------------
local RoutingModule = setmetatable({}, BaseModule)
RoutingModule.__index = RoutingModule

function RoutingModule:create(controller)
    local self = BaseModule.new(controller, "Routing")
    setmetatable(self, RoutingModule)
    return self
end

function RoutingModule:setRouterOutput(outputNumber, cameraNumber)
    local camRouter = self.controller.components.camRouter
    if not camRouter then return end
    
    self.controller:safeComponentAccess(camRouter, "select." .. outputNumber, "setString", tostring(cameraNumber))
end

function RoutingModule:clearRoutes()
    local def = self.controller.config.defaultCameraRouterSettings
    self:setRouterOutput(1, def.monitorA)
    self:setRouterOutput(2, def.monitorB)
    self:setRouterOutput(3, def.usbA)
    self:setRouterOutput(4, def.usbB)
end

function RoutingModule:setAllRoutes(cameraNumber)
    for i = 1, 4 do 
        self:setRouterOutput(i, cameraNumber) 
    end
end

-------------------[ PTZ Module ]--------------------------
local PTZModule = setmetatable({}, BaseModule)
PTZModule.__index = PTZModule

function PTZModule:create(controller)
    local self = BaseModule.new(controller, "PTZ")
    setmetatable(self, PTZModule)
    return self
end

function PTZModule:setButtonProperties(buttonNum, headerText, screenText, controlLink, color)
    local ptz = self.controller.components.skaarhojPTZController
    if not ptz then return end
    
    local props = {}
    if headerText then props["Button" .. buttonNum .. ".headerText"] = headerText end
    if screenText then props["Button" .. buttonNum .. ".screenText"] = screenText end
    if controlLink then props["Button" .. buttonNum .. ".controlLink"] = controlLink end
    if color then props["Button" .. buttonNum .. ".color"] = color end
    
    for control, value in pairs(props) do
        self.controller:safeComponentAccess(ptz, control, "setString", value)
    end
end

function PTZModule:enablePC()
    self:setButtonProperties(8, "Send to PC", nil, nil, self.controller.config.buttonColors.warmWhite)
end

function PTZModule:disablePC()
    self:setButtonProperties(8, "", "", "None", self.controller.config.buttonColors.buttonOff)
end

function PTZModule:initializeCameraLabels()
    if not self.controller.components.skaarhojPTZController then return end
    
    for i = 1, 5 do 
        self:setCameraLabel(i, i) 
    end
    self:debug("Camera labels initialized for buttons 1-5")
end

function PTZModule:setCameraLabel(buttonNum, camNum)
    local label = self.controller.cameraLabels[tostring(camNum)] or ""
    self:setButtonProperties(buttonNum, nil, label)
end

function PTZModule:handleCameraSelection(cameraIndex)
    -- Early return guards
    if not self.controller.components.skaarhojPTZController then return end
    if not self.controller.components.camRouter then return end
    
    -- Main logic unindented
    local ptz = self.controller.components.skaarhojPTZController
    self.controller:safeComponentAccess(ptz, "Button" .. cameraIndex .. ".headerText", "setString", "Preview Mon")
    
    local camIndex = tostring(cameraIndex)
    self.controller.routingModule:setRouterOutput(1, camIndex)
    self.controller.routingModule:setRouterOutput(2, camIndex)
    
    -- Update visual feedback for all buttons
    for j = 1, 5 do 
        local headerText = (j == cameraIndex) and "Preview Mon" or "Select"
        self:setButtonProperties(j, headerText)
    end
end

function PTZModule:handlePCSend()
    -- Early return guards
    if not self.controller.components.skaarhojPTZController then return end
    if not self.controller.components.camRouter then return end
    if not self.controller.components.callSync then return end
    if not self.controller:safeComponentAccess(self.controller.components.callSync, "off.hook", "get") then return end
    
    -- Main logic unindented
    local currentCam = self.controller:safeComponentAccess(self.controller.components.camRouter, "select.1", "getString")
    if not currentCam then return end
    
    self.controller.routingModule:setRouterOutput(3, currentCam)
    self.controller.routingModule:setRouterOutput(4, currentCam)
    
    local selectedText = self.controller:safeComponentAccess(
        self.controller.components.skaarhojPTZController, 
        "Button" .. currentCam .. ".screenText", 
        "getString"
    )
    
    if selectedText then
        self.controller:safeComponentAccess(
            self.controller.components.skaarhojPTZController, 
            "Button8.screenText", 
            "setString", 
            selectedText
        )
    end
end

-------------------[ Hook State Module ]-------------------
local HookStateModule = setmetatable({}, BaseModule)
HookStateModule.__index = HookStateModule

function HookStateModule:create(controller)
    local self = BaseModule.new(controller, "HookState")
    setmetatable(self, HookStateModule)
    return self
end

function HookStateModule:setHookState(state)
    self.controller.state.hookState = state
    
    if state then
        self.controller.ptzModule:enablePC()
        self.controller.cameraModule:setPrivacy(false)
        self:updateCamACPR(state)
    else
        self.controller.ptzModule:disablePC()
        self.controller.cameraModule:setPrivacy(true)
    end
end

function HookStateModule:updateCamACPR(state)
    local camACPR = self.controller.components.camACPR
    if not camACPR then return end
    
    local productionModeOn = controls.btnProductionMode and controls.btnProductionMode.Boolean
    local shouldBypass = productionModeOn or not state
    self.controller:safeComponentAccess(camACPR, "TrackingBypass", "set", shouldBypass)
end

function HookStateModule:handleHookState(isOffHook)
    self:setHookState(isOffHook)
    
    if not isOffHook then
        self.controller.routingModule:setRouterOutput(3, '5')
        self.controller.routingModule:setRouterOutput(4, '5')
    end
    
    self:updatePTZHookFeedback(isOffHook)
end

function HookStateModule:updatePTZHookFeedback(isOffHook)
    local ptz = self.controller.components.skaarhojPTZController
    if not ptz then return end
    
    self.controller:safeComponentAccess(ptz, "Button5.press", "set", isOffHook)
    
    local btn8Color = isOffHook and "Warm White" or "Off"
    local btn8Text = isOffHook and "Send to PC" or "Off"
    self.controller:safeComponentAccess(ptz, "Button8.color", "setString", btn8Color)
    self.controller:safeComponentAccess(ptz, "Button8.headerText", "setString", btn8Text)
end

-------------------[ Main Controller Class ]---------------
local SkaarhojPTZControllerSingleRoom = {}
SkaarhojPTZControllerSingleRoom.__index = SkaarhojPTZControllerSingleRoom
SkaarhojPTZControllerSingleRoom.clearString = "[Clear]"

-- Centralized config and labels
local defaultConfig = {
    buttonColors = {
        presetCalled = 'Blue',
        presetNotCalled = 'White',
        buttonOff = 'Off',
        warmWhite = 'Warm White',
        purple = 'Purple',
        white = 'White',
        red = 'Red'
    },
    defaultCameraRouterSettings = {
        monitorA = '5',
        monitorB = '5',
        usbA = '5',
        usbB = '5'
    },
    initializationDelay = 0.1,
    recalibrationDelay = 1.0
}

local cameraLabels = {["1"]="Cam A", ["2"]="Cam D", ["3"]="Cam B", ["4"]="Cam C", ["5"]="Cam E"}

SkaarhojPTZControllerSingleRoom.componentTypes = {
    callSync = "call_sync",
    skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
    camRouter = "video_router",
    devCams = "onvif_camera_operative",
    camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
    roomControls = "device_controller_script"
}

function SkaarhojPTZControllerSingleRoom.new(roomName, config)
    local self = setmetatable({}, SkaarhojPTZControllerSingleRoom)
    
    -- Instance properties
    self.roomName = roomName or "Single Room"
    self.debugging = (config and config.debugging) or true
    self.config = config or defaultConfig
    self.cameraLabels = cameraLabels
    
    -- State management
    self.state = {
        hookState = false,
        currentCameraSelection = 1,
        privacyState = false
    }
    
    -- Component storage
    self.components = {
        callSync = nil,
        skaarhojPTZController = nil,
        camRouter = nil,
        devCams = {},
        camACPR = nil,
        compRoomControls = nil,
        invalid = {}
    }
    
    -- Initialize modules
    self.cameraModule = CameraModule:create(self)
    self.routingModule = RoutingModule:create(self)
    self.ptzModule = PTZModule:create(self)
    self.hookStateModule = HookStateModule:create(self)
    
    return self
end

-------------------[ Debug Helper ]------------------------
function SkaarhojPTZControllerSingleRoom:debugPrint(str)
    if self.debugging then 
        print("[" .. self.roomName .. " Camera Debug] " .. str) 
    end
end

-------------------[ Safe Component Access ]---------------
function SkaarhojPTZControllerSingleRoom:safeComponentAccess(component, control, action, value)
    if not component or not component[control] then return false end
    
    local success, result = pcall(function()
        if action == "set" then
            component[control].Boolean = value
            return true
        elseif action == "setPosition" then
            component[control].Position = value
            return true
        elseif action == "setString" then
            component[control].String = value
            return true
        elseif action == "setValue" then
            component[control].Value = value
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
        elseif action == "getValue" then
            return component[control].Value
        end
        return false
    end)
    
    if not success then
        self:debugPrint("Component access error: " .. tostring(result))
        return false
    end
    return result
end

-------------------[ Component Management ]-----------------
function SkaarhojPTZControllerSingleRoom:setComponent(ctrl, componentType)
    -- Early returns for edge cases
    if not ctrl then return nil end
    if ctrl.String == "" or ctrl.String == self.clearString then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Component validation
    local newComponent = Component.New(ctrl.String)
    if #Component.GetControls(newComponent) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    
    -- Success path
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return newComponent
end

function SkaarhojPTZControllerSingleRoom:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function SkaarhojPTZControllerSingleRoom:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function SkaarhojPTZControllerSingleRoom:checkStatus()
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

-------------------[ Component Setup ]----------------------
function SkaarhojPTZControllerSingleRoom:setupComponents()
    -- Main components
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    self.components.skaarhojPTZController = self:setComponent(controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    self.components.camRouter = self:setComponent(controls.compcamRouter, "Camera Router")
    self.components.camACPR = self:setComponent(controls.compcamACPR, "Camera ACPR")
    self.components.compRoomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    
    -- Camera components array
    if controls.compdevCams then
        for i = 1, 5 do 
            self:setDevCamComponent(i) 
        end
    end
    
    self:registerComponentEventHandlers()
end

function SkaarhojPTZControllerSingleRoom:setDevCamComponent(idx)
    if not controls.compdevCams or not controls.compdevCams[idx] then return end
    
    local labels = { [1]="Cam A", [2]="Cam D", [3]="Cam B", [4]="Cam C", [5]="Cam E" }
    self.components.devCams[idx] = self:setComponent(controls.compdevCams[idx], labels[idx])
end

-------------------[ Event Handler Registration ]-----------
function SkaarhojPTZControllerSingleRoom:registerEventHandlers()
    -- Centralized event mapping for DRY registration
    local eventMap = {
        btnProductionMode = function() self:handleProductionModeChange() end
    }
    
    -- Bind single events
    for controlName, handler in pairs(eventMap) do
        bind(controls[controlName], handler)
    end
    
    -- Component dropdown handlers
    local componentEventMap = {
        compCallSync = function() self:setCallSyncComponent() end,
        compdevSkaarhojPTZ = function() self:setSkaarhojPTZComponent() end,
        compcamRouter = function() self:setCamRouterComponent() end,
        compcamACPR = function() self:setCamACPRComponent() end,
        compRoomControls = function() self:setRoomControlsComponent() end
    }
    
    for controlName, handler in pairs(componentEventMap) do
        bind(controls[controlName], handler)
    end
    
    -- Array component handlers
    if controls.compdevCams then
        for i, devCamComp in ipairs(controls.compdevCams) do
            bind(devCamComp, function() self:setDevCamComponent(i) end)
        end
    end
end

function SkaarhojPTZControllerSingleRoom:registerComponentEventHandlers()
    -- Call Sync event handlers
    if self.components.callSync then
        self.components.callSync["off.hook"].EventHandler = function()
            local hookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
            self.hookStateModule:handleHookState(hookState)
        end
    end
    
    -- PTZ Controller event handlers
    if self.components.skaarhojPTZController then
        self:registerPTZButtonHandlers()
        self.ptzModule:initializeCameraLabels()
    end
    
    -- Room Controls event handlers
    if self.components.compRoomControls then
        local ledSystemPower = self.components.compRoomControls["ledSystemPower"]
        if ledSystemPower then
            ledSystemPower.EventHandler = function()
                local systemPowerState = self:safeComponentAccess(self.components.compRoomControls, "ledSystemPower", "get")
                if not systemPowerState then
                    setProp(controls.btnProductionMode, "Boolean", false)
                    self:handleSystemPowerOff()
                end
            end
        end
    end
end

function SkaarhojPTZControllerSingleRoom:registerPTZButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end
    
    -- Camera selection buttons (1-5)
    for i = 1, 5 do
        local btn = ptz["Button" .. i .. ".press"]
        if btn then
            btn.EventHandler = function() self.ptzModule:handleCameraSelection(i) end
        end
    end
    
    -- PC send button (8)
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function() self.ptzModule:handlePCSend() end
    end
end

-------------------[ Component Setters ]--------------------
function SkaarhojPTZControllerSingleRoom:setCallSyncComponent()
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    if self.components.callSync then
        self.components.callSync["off.hook"].EventHandler = function()
            local hookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
            self.hookStateModule:handleHookState(hookState)
        end
    end
end

function SkaarhojPTZControllerSingleRoom:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    if self.components.skaarhojPTZController then
        self:registerPTZButtonHandlers()
        self.ptzModule:initializeCameraLabels()
    end
end

function SkaarhojPTZControllerSingleRoom:setCamRouterComponent()
    self.components.camRouter = self:setComponent(controls.compcamRouter, "Camera Router")
end

function SkaarhojPTZControllerSingleRoom:setCamACPRComponent()
    self.components.camACPR = self:setComponent(controls.compcamACPR, "Camera ACPR")
end

function SkaarhojPTZControllerSingleRoom:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    if self.components.compRoomControls then
        local ledSystemPower = self.components.compRoomControls["ledSystemPower"]
        if ledSystemPower then
            ledSystemPower.EventHandler = function()
                local systemPowerState = self:safeComponentAccess(self.components.compRoomControls, "ledSystemPower", "get")
                if not systemPowerState then
                    setProp(controls.btnProductionMode, "Boolean", false)
                    self:handleSystemPowerOff()
                end
            end
        end
    end
end

-------------------[ Event Handlers ]-----------------------
function SkaarhojPTZControllerSingleRoom:handleProductionModeChange()
    local ptz, camACPR = self.components.skaarhojPTZController, self.components.camACPR
    
    if ptz then
        self:safeComponentAccess(ptz, "Disable", "set", not controls.btnProductionMode.Boolean)
        self:safeComponentAccess(ptz, "Button14.press", "set", true) -- Send All Home
    end
    
    if camACPR then
        local productionModeOn = controls.btnProductionMode.Boolean
        local isOffHook = self.state.hookState
        local shouldBypass = productionModeOn or not isOffHook
        self:safeComponentAccess(camACPR, "TrackingBypass", "set", shouldBypass)
        self:debugPrint("Production mode changed - Production mode: " .. tostring(productionModeOn) .. 
                       ", Off hook: " .. tostring(isOffHook) .. ", TrackingBypass: " .. tostring(shouldBypass))
    end
end

function SkaarhojPTZControllerSingleRoom:handleSystemPowerOff()
    self:debugPrint("System power off - Production mode set to false")
    if self.components.camACPR then 
        self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", true) 
    end
    if self.components.skaarhojPTZController then 
        self:safeComponentAccess(self.components.skaarhojPTZController, "Disable", "set", true) 
    end
end

-------------------[ Component Discovery ]------------------
function SkaarhojPTZControllerSingleRoom:getComponentNames()
    local compTypes = self.componentTypes
    local namesTable = {
        CallSyncNames = {},
        SkaarhojPTZNames = {},
        CamRouterNames = {},
        DevCamNames = {},
        CamACPRNames = {},
        CompRoomControlsNames = {}
    }
    
    for _, comp in pairs(Component.GetComponents()) do
        if not comp.Name or comp.Name == "" then goto continue end
        
        if comp.Type == compTypes.callSync then
            table.insert(namesTable.CallSyncNames, comp.Name)
        elseif comp.Type == compTypes.skaarhojPTZController then
            table.insert(namesTable.SkaarhojPTZNames, comp.Name)
        elseif comp.Type == compTypes.camRouter then
            table.insert(namesTable.CamRouterNames, comp.Name)
        elseif comp.Type == compTypes.devCams then
            table.insert(namesTable.DevCamNames, comp.Name)
        elseif comp.Type == compTypes.camACPR then
            table.insert(namesTable.CamACPRNames, comp.Name)
        elseif comp.Type == compTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.CompRoomControlsNames, comp.Name)
        end
        
        ::continue::
    end
    
    -- Sort and add clear option
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    
    -- Populate choices
    setProp(controls.compCallSync, "Choices", namesTable.CallSyncNames)
    setProp(controls.compdevSkaarhojPTZ, "Choices", namesTable.SkaarhojPTZNames)
    setProp(controls.compcamRouter, "Choices", namesTable.CamRouterNames)
    setProp(controls.compcamACPR, "Choices", namesTable.CamACPRNames)
    setProp(controls.compRoomControls, "Choices", namesTable.CompRoomControlsNames)
    
    if controls.compdevCams then
        for _, v in ipairs(controls.compdevCams) do 
            setProp(v, "Choices", namesTable.DevCamNames)
        end
    end
end

-------------------[ System Initialization ]---------------
function SkaarhojPTZControllerSingleRoom:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.cameraModule:recalibratePTZ()
    self.routingModule:clearRoutes()
    self.ptzModule:initializeCameraLabels()
    
    Timer.CallAfter(function()
        if not self.state.hookState then
            self.cameraModule:setPrivacy(true)
            for i = 1, 5 do 
                self.ptzModule:setButtonProperties(i, "Select")
            end
            self.ptzModule:disablePC()
        end
        self:debugPrint("System initialization completed")
    end, self.config.recalibrationDelay)
end

-------------------[ Initialization ]----------------------
function SkaarhojPTZControllerSingleRoom:funcInit()
    self:debugPrint("Starting Single Room Camera Controller initialization...")
    
    -- Initialization sequence
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    -- Initial hook state check
    if self.components.callSync then
        local initialHookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
        self:debugPrint("Initial hook state: " .. tostring(initialHookState))
        self.hookStateModule:handleHookState(initialHookState)
    end
    
    self:debugPrint("Single Room Camera Controller Initialized with " .. 
                   self.cameraModule:getCameraCount() .. " cameras")
end

-------------------[ Cleanup ]-----------------------------
function SkaarhojPTZControllerSingleRoom:cleanup()
    -- Cleanup all modules
    local modules = { self.cameraModule, self.routingModule, self.ptzModule, self.hookStateModule }
    for _, module in ipairs(modules) do
        if module and module.cleanup then 
            module:cleanup() 
        end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

-------------------[ Factory Function ]--------------------
local function createSingleRoomController(roomName, config)
    print("Creating Single Room Camera Controller for: " .. tostring(roomName))
    local success, controller = pcall(function()
        local instance = SkaarhojPTZControllerSingleRoom.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    
    if success then
        print("Successfully created Single Room Camera Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
if not validateControls() then return end

local formattedRoomName = "[" .. controls.roomName.String .. "]"
mySingleRoomController = createSingleRoomController(formattedRoomName)

if mySingleRoomController then
    print("Single Room Camera Controller created successfully!")
else
    print("ERROR: Failed to create Single Room Camera Controller!")
end