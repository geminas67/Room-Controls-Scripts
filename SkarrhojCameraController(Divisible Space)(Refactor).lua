--[[ 
    Divisible Space Camera Controller - Modular/Refactored Version
    Author: Nikolas Smith, Q-SYS (Based on Single Room Refactor Patterns)
    Version: 3.0 | Date: 2025-09-04
    Firmware Req: 10.0.0
    Notes:
    - Refactored per Lua Refactoring Prompt (event-driven, OOP modular)
    - Modular architecture with separate domain classes
    - DRY event registration using centralized event maps
    - Following SystemAutomationController patterns
    - Adapted for divisible space functionality
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
    compRoomCombiner = Controls.compRoomCombiner,
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
    if not ctrl then return false end
    if ctrl[prop] == val then return false end  -- Redundancy guard (Pattern #27)
    ctrl[prop] = val
    return true
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

local function cleanupComponentHandlers(oldComponent, controlNames, debugCallback)
    -- CRITICAL: Clean up old event handlers before reassigning (Pattern #33)
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

function CameraModule:setPrivacy(room, state)
    local cameras = self:getCamerasForRoom(room)
    
    if room == "A" then
        self.controller.state.privacyState.roomA = state
    elseif room == "B" then
        self.controller.state.privacyState.roomB = state
    elseif room == "Combined" then
        self.controller.state.privacyState.roomA = state
        self.controller.state.privacyState.roomB = state
    end
    
    for _, camera in ipairs(cameras) do
        if camera then 
            self.controller:safeComponentAccess(camera, "toggle.privacy", "set", state)
        end
    end
    
    self:updatePrivacyButton()
end

function CameraModule:setAutoFrame(room, state)
    local cameras = self:getCamerasForRoom(room)
    
    for _, camera in ipairs(cameras) do
        if camera then 
            self.controller:safeComponentAccess(camera, "autoframe.enable", "set", state)
        end
    end
end

function CameraModule:recalibratePTZ()
    local cameras = {
        self.controller.components.devCams[1], 
        self.controller.components.devCams[2], 
        self.controller.components.devCams[3], 
        self.controller.components.devCams[4]
    }
    
    for _, camera in ipairs(cameras) do
        if camera then 
            self.controller:safeComponentAccess(camera, "ptz.recalibrate", "trigger")
        end
    end
end

function CameraModule:getCameraCount()
    local cameras = {
        self.controller.components.devCams[1], 
        self.controller.components.devCams[2], 
        self.controller.components.devCams[3], 
        self.controller.components.devCams[4]
    }
    local count = 0
    for _, camera in ipairs(cameras) do
        if camera then count = count + 1 end
    end
    return count
end

function CameraModule:getCamerasForRoom(room)
    local devCams = self.controller.components.devCams
    
    if room == "A" then
        return {devCams[1], devCams[3]}  -- Cam-01, Cam-03
    elseif room == "B" then
        return {devCams[2], devCams[4]}  -- Cam-02, Cam-04
    elseif room == "Combined" then
        return {devCams[1], devCams[2], devCams[3], devCams[4]}  -- All cameras (Cam-01, Cam-02, Cam-03, Cam-04)
    end
    return {}
end

function CameraModule:updatePrivacyButton()
    local ptz = self.controller.components.skaarhojPTZController
    if not ptz then return end
    
    local privacyActive = self.controller.state.privacyState.roomA or self.controller.state.privacyState.roomB
    local color = privacyActive and 
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

function RoutingModule:clearRoomRoutes(room)
    local def = self.controller.config.defaultCameraRouterSettings
    if room == "A" then
        self:setRouterOutput(1, def.monitorA)
        self:setRouterOutput(3, def.usbA)
    elseif room == "B" then
        self:setRouterOutput(2, def.monitorB)
        self:setRouterOutput(4, def.usbB)
    end
end

function RoutingModule:setMonitorRoute(cameraNumber, room)
    if room == "combined" then
        self:setRouterOutput(1, cameraNumber)
        self:setRouterOutput(2, cameraNumber)
        self:handleCombinedRouting()
    elseif room == "A" then
        self:setRouterOutput(1, cameraNumber)
        self:handleRoomARouting()
    elseif room == "B" then
        self:setRouterOutput(2, cameraNumber)
        self:handleRoomBRouting()
    end
end

function RoutingModule:setUSBRoute(cameraNumber, room)
    if room == "A" then
        self:setRouterOutput(3, cameraNumber)
    elseif room == "B" then
        self:setRouterOutput(4, cameraNumber)
    end
end

function RoutingModule:handleCombinedRouting()
    local callSyncA = self.controller.components.callSync[1]
    local callSyncB = self.controller.components.callSync[2]
    
    if callSyncA and self.controller:safeComponentAccess(callSyncA, "off.hook", "get") then
        self.controller.ptzModule:disableRoomBPC()
        Timer.CallAfter(function()
            self.controller.ptzModule:enableRoomAPC()
        end, self.controller.config.initializationDelay)
    elseif callSyncB and self.controller:safeComponentAccess(callSyncB, "off.hook", "get") then
        self.controller.ptzModule:disableRoomAPC()
        Timer.CallAfter(function()
            self.controller.ptzModule:enableRoomBPC()
        end, self.controller.config.initializationDelay)
    end
end

function RoutingModule:handleRoomARouting()
    self.controller.ptzModule:disableRoomBPC()
    self.controller.ptzModule:enableRoomAPC()
end

function RoutingModule:handleRoomBRouting()
    self.controller.ptzModule:disableRoomAPC()
    self.controller.ptzModule:enableRoomBPC()
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

function PTZModule:setMultipleButtonProperties(buttonNum, props)
    for key, value in pairs(props) do
        self:setButtonProperties(buttonNum, key == "headerText" and value or nil, 
                                             key == "screenText" and value or nil,
                                             key == "controlLink" and value or nil,
                                             key == "color" and value or nil)
    end
end

function PTZModule:enableRoomAPC()
    if self.controller.state.buttonStates.roomAPCEnabled then return end
    self:setButtonProperties(8, "Send to PC A", nil, nil, self.controller.config.buttonColors.warmWhite)
    self.controller.state.buttonStates.roomAPCEnabled = true
    self:debug("Enabled Room A PC")
end

function PTZModule:disableRoomAPC()
    if not self.controller.state.buttonStates.roomAPCEnabled then return end
    self:setButtonProperties(8, "", "", "None", self.controller.config.buttonColors.buttonOff)
    self.controller.state.buttonStates.roomAPCEnabled = false
    self:debug("Disabled Room A PC")
end

function PTZModule:enableRoomBPC()
    if self.controller.state.buttonStates.roomBPCEnabled then return end
    self:setButtonProperties(9, "Send to PC B", nil, nil, self.controller.config.buttonColors.warmWhite)
    self.controller.state.buttonStates.roomBPCEnabled = true
    self:debug("Enabled Room B PC")
end

function PTZModule:disableRoomBPC()
    if not self.controller.state.buttonStates.roomBPCEnabled then return end
    self:setButtonProperties(9, "", "", "None", self.controller.config.buttonColors.buttonOff)
    self.controller.state.buttonStates.roomBPCEnabled = false
    self:debug("Disabled Room B PC")
end

function PTZModule:setButtonActive(buttonNumber, active)
    if self.controller.state.buttonStates.activeButton == buttonNumber and active then return end
    if not active and self.controller.state.buttonStates.activeButton ~= buttonNumber then return end
    
    local headerText = active and "Preview Mon" or "Select"
    self:setButtonProperties(buttonNumber, headerText)
    self.controller.state.buttonStates.activeButton = active and buttonNumber or 0
    self:debug("Set Button"..buttonNumber.." to "..(active and "Preview Mon" or "Select"))
end

function PTZModule:setCameraLabel(buttonNumber, cameraNumber)
    local label = self.controller.cameraLabels[tostring(cameraNumber)] or ""
    self:setButtonProperties(buttonNumber, nil, label)
    self:debug("Set Button"..buttonNumber.." to "..label)
end

function PTZModule:initializeCameraLabels()
    if not self.controller.components.skaarhojPTZController then return end
    
    for i = 1, 4 do 
        self:setCameraLabel(i, i) 
    end
    self:debug("Camera labels initialized for buttons 1-4")
end

function PTZModule:handleCameraSelection(cameraIndex)
    -- Early return guards
    if not self.controller.components.skaarhojPTZController then return end
    if not self.controller.components.camRouter then return end
    -- Main logic unindented
    local ptz = self.controller.components.skaarhojPTZController
    local camerNumber = tostring(cameraIndex)
    
    self.controller.routingModule:setRouterOutput(1, camerNumber)
    self.controller.routingModule:setRouterOutput(2, camerNumber)
    self.controller:safeComponentAccess(ptz, "Button" .. cameraIndex .. ".headerText", "setString", "Preview Mon")
    
    -- Update visual feedback for all buttons
    for j = 1, 4 do 
        self:setButtonActive(j, j == cameraIndex and "Preview Mon" or "Select")
    end
end

function PTZModule:handlePCSend(room)
    -- Early return guards
    if not self.controller.components.skaarhojPTZController then return end
    if not self.controller.components.camRouter then return end
    
    local callSyncIndex = room == "A" and 1 or 2
    local callSync = self.controller.components.callSync[callSyncIndex]
    if not callSync then return end
    if not self.controller:safeComponentAccess(callSync, "off.hook", "get") then return end
    -- Main logic unindented
    local outputNumber = room == "A" and "1" or "2"
    local currentCamera = self.controller:safeComponentAccess(self.controller.components.camRouter, "select." .. outputNumber, "getString")
    if not currentCamera then return end
    
    local usbOutput = room == "A" and "3" or "4"
    self.controller.routingModule:setRouterOutput(usbOutput, currentCamera)
    
    local selectedText = self.controller:safeComponentAccess(
        self.controller.components.skaarhojPTZController, 
        "Button" .. currentCamera .. ".screenText", 
        "getString"
    )
    
    if selectedText then
        local buttonNum = room == "A" and "8" or "9"
        self.controller:safeComponentAccess(
            self.controller.components.skaarhojPTZController, 
            "Button" .. buttonNum .. ".screenText", 
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
    -- Room configuration for parameterizing hardware-specific details
    self.roomConfig = {
        A = {
            roomId = "A",
            componentIndex = 1,
            buttonNumber = 8,
            cameraRouterOutput = "01",
            usbOutput = "3",
            privacyRoom = "A"
        },
        B = {
            roomId = "B", 
            componentIndex = 2,
            buttonNumber = 9,
            cameraRouterOutput = "02",
            usbOutput = "4",
            privacyRoom = "B"
        }
    }
    
    return self
end

function HookStateModule:handleRoomHookStateCommon(roomConfig, isOffHook)
    -- Shared logic for room hook state handling with parameterized room-specific details
    if not self.controller.components.roomCombiner then
        -- Default behavior when roomCombiner is not available
        self:debug("roomCombiner not available - using default hook state behavior for Room " .. roomConfig.roomId)
        if isOffHook then
            if roomConfig.roomId == "A" then
                self.controller.ptzModule:enableRoomAPC()
            else
                self.controller.ptzModule:enableRoomBPC()
            end
            self.controller.cameraModule:setPrivacy(roomConfig.privacyRoom, false)
        else
            if roomConfig.roomId == "A" then
                self.controller.ptzModule:disableRoomAPC()
            else
                self.controller.ptzModule:disableRoomBPC()
            end
            self.controller.cameraModule:setPrivacy(roomConfig.privacyRoom, true)
        end
        -- Ensure button state is updated directly
        local roomAHook = roomConfig.roomId == "A" and isOffHook or nil
        local roomBHook = roomConfig.roomId == "B" and isOffHook or nil
        self:updatePTZHookFeedback(roomAHook, roomBHook)
        return
    end
    
    local isWallOpen = self:getComponentBoolean(self.controller.components.roomCombiner, "wall.1.open")
    
    if isWallOpen then
        -- Combined mode
        self:setCombinedHookState(isOffHook)
        if isOffHook then
            self.controller:safeComponentAccess(self.controller.components.camACPR[3], "CameraRouterOutput", "setString", roomConfig.cameraRouterOutput)
            if roomConfig.roomId == "A" then
                self.controller:safeComponentAccess(self.controller.components.skaarhojPTZController, "Button15.press", "set", false)
            end
        else
            self:setComponentBoolean(self.controller.components.camACPR[3], "TrackingBypass", true)
            if roomConfig.roomId == "A" then
                self.controller:safeComponentAccess(self.controller.components.skaarhojPTZController, "Button15.press", "set", true)
            end
        end
    else
        -- Divided mode
        self:setCombinedHookState(false)
        if isOffHook then
            self:setComponentBoolean(self.controller.components.camACPR[3], "TrackingBypass", true)
            if roomConfig.roomId == "A" then
                self.controller.ptzModule:enableRoomAPC()
            else
                self.controller.ptzModule:enableRoomBPC()
            end
            if not self:getProductionModeState() then
                self.controller:safeComponentAccess(self.controller.components.compRoomControls[roomConfig.componentIndex], "CameraRouterOutput", "setString", roomConfig.cameraRouterOutput)
                self.controller.cameraModule:setPrivacy(roomConfig.privacyRoom, false)
            end
        else
            if roomConfig.roomId == "A" then
                self.controller.ptzModule:disableRoomAPC()
            else
                self.controller.ptzModule:disableRoomBPC()
            end
            self:setComponentBoolean(self.controller.components.compRoomControls[roomConfig.componentIndex], "TrackingBypass", true)
            self.controller.cameraModule:setPrivacy(roomConfig.privacyRoom, true)
        end
    end
    -- Ensure button state is updated directly after all logic
    local roomAHook = roomConfig.roomId == "A" and isOffHook or nil
    local roomBHook = roomConfig.roomId == "B" and isOffHook or nil
    self:updatePTZHookFeedback(roomAHook, roomBHook)
end

function HookStateModule:setCombinedHookState(state)
    if self.controller.state.combinedHookState == state then return end
    self.controller.state.combinedHookState = state
    
    if state then
        -- Combined - Off Hook - Privacy Off
        self.controller.ptzModule:enableRoomAPC()
        self.controller.cameraModule:setPrivacy("Combined", false)
        if not self:getProductionModeState() then
            self:setComponentBoolean(self.controller.components.camACPR[3], "TrackingBypass", false)
        end
        self:setComponentBoolean(self.controller.components.compRoomControls[1], "TrackingBypass", true)
        self:setComponentBoolean(self.controller.components.compRoomControls[2], "TrackingBypass", true)
    else
        -- Combined - On Hook - Privacy On
        self.controller.ptzModule:disableRoomAPC()
        self.controller.ptzModule:disableRoomBPC()
        self.controller:safeComponentAccess(self.controller.components.skaarhojPTZController, "Button9.controlLink", "setString", "None")
        self.controller.cameraModule:setPrivacy("Combined", true)
        Timer.CallAfter(function()
            self:setComponentBoolean(self.controller.components.camACPR[3], "TrackingBypass", true)
        end, self.controller.config.initializationDelay * 2)
    end
end

function HookStateModule:handleRoomAHookState(isOffHook)
    -- Use shared utility function with Room A configuration
    self:handleRoomHookStateCommon(self.roomConfig.A, isOffHook)
end

function HookStateModule:handleRoomBHookState(isOffHook)
    -- Use shared utility function with Room B configuration
    self:handleRoomHookStateCommon(self.roomConfig.B, isOffHook)
end

function HookStateModule:handleSystemPowerOff()
    self:debug("System power off - Production mode set to false")
    for i, acpr in ipairs(self.controller.components.camACPR) do
        if acpr then 
            self:setComponentBoolean(acpr, "TrackingBypass", true) 
        end
    end
    if self.controller.components.skaarhojPTZController then 
        self.controller:safeComponentAccess(self.controller.components.skaarhojPTZController, "Disable", "set", true) 
    end
end

function HookStateModule:updatePTZHookFeedback(roomA_isOffHook, roomB_isOffHook)
    local ptz = self.controller.components.skaarhojPTZController
    if not ptz then return end
    -- Update Button8 (Room A PC) based on Room A hook state
    if roomA_isOffHook ~= nil then
        local btn8Color = roomA_isOffHook and self.controller.config.buttonColors.warmWhite or self.controller.config.buttonColors.buttonOff
        local btn8Text = roomA_isOffHook and "Send to PC A" or ""
        self.controller:safeComponentAccess(ptz, "Button8.color", "setString", btn8Color)
        self.controller:safeComponentAccess(ptz, "Button8.headerText", "setString", btn8Text)
        if not roomA_isOffHook then
            self.controller:safeComponentAccess(ptz, "Button8.controlLink", "setString", "None")
        end
    end
    -- Update Button9 (Room B PC) based on Room B hook state  
    if roomB_isOffHook ~= nil then
        local btn9Color = roomB_isOffHook and self.controller.config.buttonColors.warmWhite or self.controller.config.buttonColors.buttonOff
        local btn9Text = roomB_isOffHook and "Send to PC B" or ""
        self.controller:safeComponentAccess(ptz, "Button9.color", "setString", btn9Color)
        self.controller:safeComponentAccess(ptz, "Button9.headerText", "setString", btn9Text)
        if not roomB_isOffHook then
            self.controller:safeComponentAccess(ptz, "Button9.controlLink", "setString", "None")
        end
    end
end

function HookStateModule:handleProductionModeChange()
    local ptz = self.controller.components.skaarhojPTZController
    if ptz then
        self.controller:safeComponentAccess(ptz, "Disable", "set", not controls.btnProductionMode.Boolean)
        self.controller:safeComponentAccess(ptz, "Button14.press", "set", true) -- Send All Home
    end
    
    for i, acpr in ipairs(self.controller.components.camACPR) do
        if acpr then
            local productionModeOn = controls.btnProductionMode.Boolean
            local isOffHook = self.controller.state.combinedHookState
            local shouldBypass = productionModeOn or not isOffHook
            self:setComponentBoolean(acpr, "TrackingBypass", shouldBypass)
            self:debug("Production mode changed - Production mode: " .. tostring(productionModeOn) .. 
                       ", Off hook: " .. tostring(isOffHook) .. ", TrackingBypass: " .. tostring(shouldBypass))
        end
    end
end
-- Helper functions for hook state module
function HookStateModule:getProductionModeState()
    return controls.btnProductionMode and controls.btnProductionMode.Boolean
end

function HookStateModule:getComponentBoolean(component, control)
    return self.controller:safeComponentAccess(component, control, "get")
end

function HookStateModule:setComponentBoolean(component, control, value)
    return self.controller:safeComponentAccess(component, control, "set", value)
end

-------------------[ Main Controller Class ]---------------
local SkaarhojPTZControllerMultiRoom = {}
SkaarhojPTZControllerMultiRoom.__index = SkaarhojPTZControllerMultiRoom
SkaarhojPTZControllerMultiRoom.clearString = "[Clear]"

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
        monitorA = '2',
        monitorB = '4',
        usbA = '2',
        usbB = '4'
    },
    initializationDelay = 0.1,
    recalibrationDelay = 1.0
}

local cameraLabels = {
    ["1"] = "Cam-01", -- Room A
    ["2"] = "Cam-03", -- Room B
    ["3"] = "Cam-02", -- Room A
    ["4"] = "Cam-04"  -- Room B
}

SkaarhojPTZControllerMultiRoom.componentTypes = {
    callSync = "call_sync",
    skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
    camRouter = "video_router",
    devCams = "onvif_camera_operative",
    camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
    roomControls = "device_controller_script",
    roomCombiner = "room_combiner"
}

function SkaarhojPTZControllerMultiRoom.new(roomName, config)
    local self = setmetatable({}, SkaarhojPTZControllerMultiRoom)
    
    -- Instance properties
    self.roomName = roomName or "Divisible Space"
    self.debugging = (config and config.debugging) or true
    self.config = config or defaultConfig
    self.cameraLabels = cameraLabels
    -- State management
    self.state = {
        combinedHookState = false,
        currentCameraSelection = 1,
        privacyState = {
            roomA = true,
            roomB = true
        },
        buttonStates = {
            activeButton = 0,
            roomAPCEnabled = false,
            roomBPCEnabled = false
        }
    }
    -- Component storage
    self.components = {
        callSync = {}, -- Rm-A [1], Rm-B [2]
        skaarhojPTZController = nil, 
        camRouter = nil, 
        devCams = {}, -- cam01, cam02, cam03, cam04
        camACPR = {}, -- Rm-A [1], Rm-B [2], Combined [3]
        compRoomControls = {}, -- Rm-A [1], Rm-B [2]
        productionMode = nil,
        roomCombiner = nil,
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
function SkaarhojPTZControllerMultiRoom:debugPrint(str)
    if self.debugging then 
        print("[" .. self.roomName .. " Camera Debug] " .. str) 
    end
end

-------------------[ Safe Component Access ]---------------
function SkaarhojPTZControllerMultiRoom:safeComponentAccess(component, control, action, value)
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
function SkaarhojPTZControllerMultiRoom:setComponent(ctrl, componentType)
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

function SkaarhojPTZControllerMultiRoom:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function SkaarhojPTZControllerMultiRoom:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function SkaarhojPTZControllerMultiRoom:checkStatus()
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
function SkaarhojPTZControllerMultiRoom:setupComponents()
    self:debugPrint("Setting up components...")
    
    -- Main components
    self:debugPrint("Setting up CallSync components")
    self:setCallSyncComponents()
    
    self:debugPrint("Setting up Skaarhoj PTZ Controller")
    self.components.skaarhojPTZController = self:setComponent(controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    
    self:debugPrint("Setting up Camera Router")
    self.components.camRouter = self:setComponent(controls.compcamRouter, "Camera Router")
    
    self:debugPrint("Setting up Cam ACPR components")
    self:setCamACPRComponents()
    
    self:debugPrint("Setting up Room Controls components")
    self:setCompRoomControlsComponents()
    
    self:debugPrint("Setting up Room Combiner components")
    self:setRoomCombinerComponents()
    
    -- Camera components array
    self:debugPrint("Setting up device camera components")
    if controls.compdevCams then
        for i = 1, 4 do 
            self:debugPrint("Setting up camera component " .. i)
            self:setDevCamComponent(i) 
        end
    end
    
    self:debugPrint("Registering component event handlers")
    self:registerComponentEventHandlers()
    self:debugPrint("Component setup complete")
end

function SkaarhojPTZControllerMultiRoom:setDevCamComponent(idx)
    if not controls.compdevCams or not controls.compdevCams[idx] then return end
    
    local labels = { [1]="Cam-01", [2]="Cam-03", [3]="Cam-02", [4]="Cam-04" }
    self.components.devCams[idx] = self:setComponent(controls.compdevCams[idx], labels[idx])
end

function SkaarhojPTZControllerMultiRoom:setCallSyncComponents()
    if not controls.compCallSync then 
        self:debugPrint("controls.compCallSync is nil")
        return 
    end
    
    self:debugPrint("controls.compCallSync type: " .. type(controls.compCallSync))
    self:debugPrint("controls.compCallSync is table: " .. tostring(type(controls.compCallSync) == "table"))
    
    -- Check if it's an array by trying to access first element
    local success1, result1 = pcall(function() return controls.compCallSync[1] end)
    local success2, result2 = pcall(function() return controls.compCallSync[2] end)
    
    self:debugPrint("Can access [1]: " .. tostring(success1) .. " - " .. tostring(result1))
    self:debugPrint("Can access [2]: " .. tostring(success2) .. " - " .. tostring(result2))
    
    for i = 1, 2 do
        local success, control = pcall(function() return controls.compCallSync[i] end)
        if success and control then
            -- Clean up old handlers before setting new component (Pattern #33)
            if self.components.callSync and self.components.callSync[i] then
                cleanupComponentHandlers(
                    self.components.callSync[i],
                    {"off.hook"},
                    function(msg) self:debugPrint("[CallSync " .. i .. "] " .. msg) end
                )
            end
            
            self:debugPrint("Setting up callSync component " .. i)
            local roomLabel = i == 1 and "Rm-A" or "Rm-B"
            self.components.callSync[i] = self:setComponent(control, "Call Sync " .. roomLabel)
            
            -- Register event handlers for new component
            if self.components.callSync[i] and self.components.callSync[i]["off.hook"] then
                self.components.callSync[i]["off.hook"].EventHandler = function()
                    local hookState = self:safeComponentAccess(self.components.callSync[i], "off.hook", "get")
                    if i == 1 then
                        self.hookStateModule:handleRoomAHookState(hookState)
                    else
                        self.hookStateModule:handleRoomBHookState(hookState)
                    end
                end
            end
        else
            self:debugPrint("Failed to access controls.compCallSync[" .. i .. "]: " .. tostring(control))
        end
    end
end

function SkaarhojPTZControllerMultiRoom:setCamACPRComponents()
    if not controls.compcamACPR then return end
    
    local acprLabels = {[1] = "ACPR Rm-A", [2] = "ACPR Rm-B", [3] = "ACPR Combined"}
    for i = 1, 3 do
        if controls.compcamACPR[i] then
            self.components.camACPR[i] = self:setComponent(controls.compcamACPR[i], acprLabels[i])
        end
    end
end

function SkaarhojPTZControllerMultiRoom:setCompRoomControlsComponents()
    if not controls.compRoomControls then return end
    
    for i = 1, 2 do
        if controls.compRoomControls[i] then
            -- Clean up old handlers before setting new component (Pattern #33)
            if self.components.compRoomControls and self.components.compRoomControls[i] then
                cleanupComponentHandlers(
                    self.components.compRoomControls[i],
                    {"ledSystemPower"},
                    function(msg) self:debugPrint("[RoomControls " .. i .. "] " .. msg) end
                )
            end
            
            local roomLabel = i == 1 and "Rm-A" or "Rm-B"
            self.components.compRoomControls[i] = self:setComponent(controls.compRoomControls[i], "Room Controls " .. roomLabel)
            
            -- Register event handlers for new component
            if self.components.compRoomControls[i] and self.components.compRoomControls[i]["ledSystemPower"] then
                self.components.compRoomControls[i]["ledSystemPower"].EventHandler = function()
                    local systemPowerState = self:safeComponentAccess(self.components.compRoomControls[i], "ledSystemPower", "get")
                    if not systemPowerState then
                        setProp(controls.btnProductionMode, "Boolean", false)
                        self.hookStateModule:handleSystemPowerOff()
                    end
                end
            end
        end
    end
end

function SkaarhojPTZControllerMultiRoom:setRoomCombinerComponents()
    if not controls.compRoomCombiner then return end
    
    self.components.roomCombiner = self:setComponent(controls.compRoomCombiner, "Rooms Combiner")
end

-------------------[ Event Handler Registration ]-----------
function SkaarhojPTZControllerMultiRoom:registerEventHandlers()
    -- Centralized event mapping for DRY registration
    local eventMap = {
        btnProductionMode = function() self.hookStateModule:handleProductionModeChange() end
    }
    -- Bind single events
    for controlName, handler in pairs(eventMap) do
        bind(controls[controlName], handler)
    end
    -- Component dropdown handlers
    local componentEventMap = {
        compdevSkaarhojPTZ = function() self:setSkaarhojPTZComponent() end,
        compcamRouter = function() self:setCamRouterComponent() end
    }
    
    for controlName, handler in pairs(componentEventMap) do
        bind(controls[controlName], handler)
    end
    -- Array component handlers
    if controls.compCallSync then
        for i, callSyncComp in ipairs(controls.compCallSync) do
            bind(callSyncComp, function() self:setCallSyncComponents() end)
        end
    end
    
    if controls.compdevCams then
        for i, devCamComp in ipairs(controls.compdevCams) do
            bind(devCamComp, function() self:setDevCamComponent(i) end)
        end
    end
    
    if controls.compcamACPR then
        for i, acprComp in ipairs(controls.compcamACPR) do
            bind(acprComp, function() self:setCamACPRComponents() end)
        end
    end
    
    if controls.compRoomControls then
        for i, roomControlComp in ipairs(controls.compRoomControls) do
            bind(roomControlComp, function() self:setCompRoomControlsComponents() end)
        end
    end
    if controls.compRoomCombiner then
        for i, roomsCombinerComp in ipairs(controls.compRoomCombiner) do
            bind(roomsCombinerComp, function() self:setRoomCombinerComponents() end)
        end
    end
end

function SkaarhojPTZControllerMultiRoom:registerComponentEventHandlers()
    self:debugPrint("Registering component event handlers...")
    -- Call Sync event handlers
    if self.components.callSync then
        for i, callSync in ipairs(self.components.callSync) do
            if callSync and callSync["off.hook"] and not callSync["off.hook"].EventHandler then
                self:debugPrint("Registering event handler for callSync[" .. i .. "]")
                callSync["off.hook"].EventHandler = function()
                    local hookState = self:safeComponentAccess(callSync, "off.hook", "get")
                    if i == 1 then
                        self.hookStateModule:handleRoomAHookState(hookState)
                    else
                        self.hookStateModule:handleRoomBHookState(hookState)
                    end
                end
            end
        end
    end
    -- PTZ Controller event handlers
    if self.components.skaarhojPTZController then
        self:registerPTZButtonHandlers()
        self.ptzModule:initializeCameraLabels()
    end
    -- Room Controls event handlers
    for i, roomControl in ipairs(self.components.compRoomControls) do
        if roomControl and roomControl["ledSystemPower"] and not roomControl["ledSystemPower"].EventHandler then
            roomControl["ledSystemPower"].EventHandler = function()
                local systemPowerState = self:safeComponentAccess(roomControl, "ledSystemPower", "get")
                if not systemPowerState then
                    setProp(controls.btnProductionMode, "Boolean", false)
                    self.hookStateModule:handleSystemPowerOff()
                end
            end
        end
    end
end

function SkaarhojPTZControllerMultiRoom:registerPTZButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end
    -- Camera selection buttons (1-4)
    for i = 1, 4 do
        local btn = ptz["Button" .. i .. ".press"]
        if btn then
            btn.EventHandler = function() self.ptzModule:handleCameraSelection(i) end
        end
    end
    -- Room A PC button (Button8)
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function() self.ptzModule:handlePCSend("A") end
    end
    -- Room B PC button (Button9)
    local btn9 = ptz["Button9.press"]
    if btn9 then
        btn9.EventHandler = function() self.ptzModule:handlePCSend("B") end
    end
end

-------------------[ Component Setters ]--------------------
function SkaarhojPTZControllerMultiRoom:setSkaarhojPTZComponent()
    -- Clean up old handlers before setting new component (Pattern #33)
    if self.components.skaarhojPTZController then
        local ptz = self.components.skaarhojPTZController
        local controlNames = {}
        for i = 1, 4 do
            table.insert(controlNames, "Button" .. i .. ".press")
        end
        table.insert(controlNames, "Button8.press")
        table.insert(controlNames, "Button9.press")
        
        cleanupComponentHandlers(
            ptz,
            controlNames,
            function(msg) self:debugPrint("[SkaarhojPTZ] " .. msg) end
        )
    end
    
    self.components.skaarhojPTZController = self:setComponent(controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    if self.components.skaarhojPTZController then
        self:registerPTZButtonHandlers()
        self.ptzModule:initializeCameraLabels()
    end
end

function SkaarhojPTZControllerMultiRoom:setCamRouterComponent()
    self.components.camRouter = self:setComponent(controls.compcamRouter, "Camera Router")
end

-------------------[ Component Discovery ]------------------
function SkaarhojPTZControllerMultiRoom:getComponentNames()
    local compTypes = self.componentTypes
    local namesTable = {
        CallSyncNames = {},
        SkaarhojPTZNames = {},
        CamRouterNames = {},
        DevCamNames = {},
        CamACPRNames = {},
        CompRoomControlsNames = {},
        RoomCombinerNames = {}
    }
    
    self:debugPrint("Starting component discovery...")
    self:debugPrint("Looking for roomCombiner type: " .. compTypes.roomCombiner)
    
    for _, comp in pairs(Component.GetComponents()) do
        if not comp.Name or comp.Name == "" then goto continue end
        
        -- Debug: Print all component types to help identify room combiner type
        if string.find(string.lower(comp.Name), "combiner") or string.find(string.lower(comp.Type), "combiner") then
            self:debugPrint("Found potential combiner component: " .. comp.Name .. " (Type: " .. comp.Type .. ")")
        end
        
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
        elseif comp.Type == compTypes.roomCombiner then
            table.insert(namesTable.RoomCombinerNames, comp.Name)
            self:debugPrint("Added room combiner: " .. comp.Name)
        end
        
        ::continue::
    end
    
    -- Sort and add clear option
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    
    -- Populate choices
    if controls.compCallSync then 
        for i, v in ipairs(controls.compCallSync) do
            setProp(v, "Choices", namesTable.CallSyncNames)
        end
    end
    setProp(controls.compdevSkaarhojPTZ, "Choices", namesTable.SkaarhojPTZNames)
    setProp(controls.compcamRouter, "Choices", namesTable.CamRouterNames)
    if controls.compdevCams then
        for _, v in ipairs(controls.compdevCams) do 
            setProp(v, "Choices", namesTable.DevCamNames)
        end
    end
    if controls.compRoomCombiner then
        self:debugPrint("RoomCombinerNames count: " .. #namesTable.RoomCombinerNames)
        for i, name in ipairs(namesTable.RoomCombinerNames) do
            self:debugPrint("RoomCombiner[" .. i .. "]: " .. name)
        end
        
        -- compRoomCombiner is a single control, not an array
        setProp(controls.compRoomCombiner, "Choices", namesTable.RoomCombinerNames)
        self:debugPrint("Set choices for compRoomCombiner")
    end
    if controls.compcamACPR then 
        for i, v in ipairs(controls.compcamACPR) do 
            setProp(v, "Choices", namesTable.CamACPRNames)
        end
    end
    if controls.compRoomControls then 
        for i, v in ipairs(controls.compRoomControls) do 
            setProp(v, "Choices", namesTable.CompRoomControlsNames)
        end
    end
end

-------------------[ System Initialization ]---------------
function SkaarhojPTZControllerMultiRoom:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.cameraModule:recalibratePTZ()
    self.routingModule:clearRoomRoutes("A")
    self.routingModule:clearRoomRoutes("B")
    self.ptzModule:initializeCameraLabels()
    
    Timer.CallAfter(function()
        self:debugPrint("Starting Timer.CallAfter in performSystemInitialization")
        self:debugPrint("callSync components table type: " .. type(self.components.callSync))
        if self.components.callSync then
            self:debugPrint("callSync[1] exists: " .. tostring(self.components.callSync[1] ~= nil))
            self:debugPrint("callSync[2] exists: " .. tostring(self.components.callSync[2] ~= nil))
        end
        
        local offHookA = self.components.callSync and self.components.callSync[1] and self:safeComponentAccess(self.components.callSync[1], "off.hook", "get")
        local offHookB = self.components.callSync and self.components.callSync[2] and self:safeComponentAccess(self.components.callSync[2], "off.hook", "get")
        
        if not offHookA and not offHookB then
            self.cameraModule:setPrivacy("Combined", true)
            for i = 1, 4 do 
                self.ptzModule:setButtonActive(i, false)
            end
            self.ptzModule:disableRoomAPC()
            self.ptzModule:disableRoomBPC()
        end
        self:debugPrint("System initialization completed")
    end, self.config.recalibrationDelay)
end

-------------------[ Initialization ]----------------------
function SkaarhojPTZControllerMultiRoom:funcInit()
    self:debugPrint("Starting Divisible Space Camera Controller initialization...")
    
    -- Initialization sequence
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    -- Initial hook state check
    self:debugPrint("Starting initial hook state check")
    self:debugPrint("callSync components available: " .. tostring(self.components.callSync ~= nil))
    
    if self.components.callSync and self.components.callSync[1] then
        self:debugPrint("Checking Room A hook state")
        local initialHookStateA = self:safeComponentAccess(self.components.callSync[1], "off.hook", "get")
        self:debugPrint("Initial Room A hook state: " .. tostring(initialHookStateA))
        self.hookStateModule:handleRoomAHookState(initialHookStateA)
    else
        self:debugPrint("Room A callSync not available")
    end
    
    if self.components.callSync and self.components.callSync[2] then
        self:debugPrint("Checking Room B hook state")
        local initialHookStateB = self:safeComponentAccess(self.components.callSync[2], "off.hook", "get")
        self:debugPrint("Initial Room B hook state: " .. tostring(initialHookStateB))
        self.hookStateModule:handleRoomBHookState(initialHookStateB)
    else
        self:debugPrint("Room B callSync not available")
    end
    
    self:debugPrint("Divisible Space Camera Controller Initialized with " .. 
                   self.cameraModule:getCameraCount() .. " cameras")
end

-------------------[ Cleanup ]-----------------------------
function SkaarhojPTZControllerMultiRoom:cleanup()
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
local function createDivisibleSpaceController(roomName, config)
    print("Creating Divisible Space Camera Controller for: " .. tostring(roomName))
    local success, controller = pcall(function()
        local instance = SkaarhojPTZControllerMultiRoom.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    
    if success then
        print("Successfully created Divisible Space Camera Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        return nil
    end
end

-------------------[ Instance Creation ]-------------------
if not validateControls() then return end

local formattedRoomName = "[" .. controls.roomName.String .. "]"
myDivisibleSpaceController = createDivisibleSpaceController(formattedRoomName)

if myDivisibleSpaceController then
    print("Divisible Space Camera Controller created successfully!")
else
    print("ERROR: Failed to create Divisible Space Camera Controller!")
end
