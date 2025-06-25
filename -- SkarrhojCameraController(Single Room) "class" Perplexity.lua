--[[ 
  Single Room Camera Controller - Optimized Version
  Author: Perplexity AI (Refactored for Performance)
  2025-06-24
  Firmware Req: 10.0.0
  Version: 1.1
]]--

--------------------------
-- CLASS DEFINITION
--------------------------
SingleRoomCameraController = {}
SingleRoomCameraController.__index = SingleRoomCameraController

function SingleRoomCameraController.new(roomName, config)
    local self = setmetatable({}, SingleRoomCameraController)
    self.roomName = roomName or "Single Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.components = {
        callSync = nil,
        skaarhojPTZController = nil,
        camRouter = nil,
        devCams = {},
        camACPR = nil,
        compRoomControls = nil,
        invalid = {}
    }

    self.state = {
        hookState = false,
        currentCameraSelection = 1,
        privacyState = false
    }

    self.config = {
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
            monitorA = '6',
            monitorB = '6',
            usbA = '6',
            usbB = '6'
        },
        initializationDelay = 0.1,
        recalibrationDelay = 1.0
    }

    -- Initialize modules
    self:initModules()
    return self
end

--------------------------
-- DEBUG PRINT
--------------------------
function SingleRoomCameraController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Camera Debug] "..str) end
end

--------------------------
-- SAFE COMPONENT ACCESS (Optimized)
--------------------------
function SingleRoomCameraController:safeComponentAccess(component, control, action, value)
    local compCtrl = component and component[control]
    if not compCtrl then return false end
    local ok, result = pcall(function()
        if action == "set" then compCtrl.Boolean = value
        elseif action == "setPosition" then compCtrl.Position = value
        elseif action == "setString" then compCtrl.String = value
        elseif action == "trigger" then compCtrl:Trigger()
        elseif action == "get" then return compCtrl.Boolean
        elseif action == "getPosition" then return compCtrl.Position
        elseif action == "getString" then return compCtrl.String
        end
        return true
    end)
    if not ok then self:debugPrint("Component access error: "..tostring(result)) end
    return ok and result
end

--------------------------
-- MODULE INITIALIZATION
--------------------------
function SingleRoomCameraController:initModules()
    self:initCameraModule()
    self:initPrivacyModule()
    self:initRoutingModule()
    self:initPTZModule()
    self:initHookStateModule()
end

--------------------------
-- CAMERA MODULE
--------------------------
function SingleRoomCameraController:initCameraModule()
    self.cameraModule = {
        setPrivacy = function(state)
            self.state.privacyState = state
            for _, cam in pairs(self.components.devCams) do
                if cam then self:safeComponentAccess(cam, "toggle.privacy", "set", state) end
            end
            self:updatePrivacyVisuals()
        end,
        setAutoFrame = function(state)
            for _, cam in pairs(self.components.devCams) do
                if cam then self:safeComponentAccess(cam, "autoframe.enable", "set", state) end
            end
        end,
        recalibratePTZ = function()
            for _, cam in pairs(self.components.devCams) do
                if cam then self:safeComponentAccess(cam, "ptz.recalibrate", "set", true) end
            end
            Timer.CallAfter(function()
                for _, cam in pairs(self.components.devCams) do
                    if cam then self:safeComponentAccess(cam, "ptz.recalibrate", "set", false) end
                end
            end, self.config.recalibrationDelay)
        end,
        getCameraCount = function()
            local count = 0
            for _, cam in pairs(self.components.devCams) do if cam then count = count + 1 end end
            return count
        end
    }
end

--------------------------
-- PRIVACY MODULE
--------------------------
function SingleRoomCameraController:initPrivacyModule()
    self.privacyModule = {
        setPrivacy = function(state) self.cameraModule.setPrivacy(state) end,
        updatePrivacyButton = function()
            local color = self.state.privacyState and self.config.buttonColors.white or self.config.buttonColors.buttonOff
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", color)
        end
    }
end

--------------------------
-- ROUTING MODULE
--------------------------
function SingleRoomCameraController:initRoutingModule()
    local function setRouterOutput(outputNumber, cameraNumber)
        self:safeComponentAccess(self.components.camRouter, "select."..outputNumber, "setString", tostring(cameraNumber))
    end
    local function clearRoutes()
        setRouterOutput(1, self.config.defaultCameraRouterSettings.monitorA)
        setRouterOutput(2, self.config.defaultCameraRouterSettings.monitorB)
        setRouterOutput(3, self.config.defaultCameraRouterSettings.usbA)
        setRouterOutput(4, self.config.defaultCameraRouterSettings.usbB)
    end
    self.routingModule = {
        setMonitorRouteA = function(cameraNumber) setRouterOutput(1, cameraNumber) end,
        setMonitorRouteB = function(cameraNumber) setRouterOutput(2, cameraNumber) end,
        setUSBRouteA = function(cameraNumber) setRouterOutput(3, cameraNumber) end,
        setUSBRouteB = function(cameraNumber) setRouterOutput(4, cameraNumber) end,
        clearRoutes = clearRoutes,
        setAllRoutes = function(cameraNumber)
            for i = 1, 4 do setRouterOutput(i, cameraNumber) end
        end
    }
end

--------------------------
-- PTZ MODULE
--------------------------
function SingleRoomCameraController:initPTZModule()
    local function setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
        local base = self.components.skaarhojPTZController
        if not base then return end
        if headerText then self:safeComponentAccess(base, "Button"..buttonNumber..".headerText", "setString", headerText) end
        if screenText then self:safeComponentAccess(base, "Button"..buttonNumber..".screenText", "setString", screenText) end
        if controlLink then self:safeComponentAccess(base, "Button"..buttonNumber..".controlLink", "setString", controlLink) end
        if color then self:safeComponentAccess(base, "Button"..buttonNumber..".color", "setString", color) end
    end
    self.ptzModule = {
        enablePC = function() setButtonProperties(8, "Send to PC", nil, nil, self.config.buttonColors.warmWhite) end,
        disablePC = function() setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff) end,
        setButtonActive = function(buttonNumber, active)
            setButtonProperties(buttonNumber, active and "Active" or "Preview Mon")
        end,
        setCameraLabel = function(buttonNumber, cameraNumber)
            local labels = {["1"]="Cam01", ["2"]="Cam02", ["3"]="Cam03", ["4"]="Cam04", ["5"]="Cam05"}
            setButtonProperties(buttonNumber, nil, labels[tostring(cameraNumber)] or "")
        end
    }
end

--------------------------
-- HOOK STATE MODULE
--------------------------
function SingleRoomCameraController:initHookStateModule()
    self.hookStateModule = {
        setHookState = function(state)
            self.state.hookState = state
            if state then
                self.ptzModule.enablePC()
                self.privacyModule.setPrivacy(false)
                if self.components.compRoomControls then
                    self:safeComponentAccess(self.components.compRoomControls, "TrackingBypass", "set", true)
                end
            else
                self.ptzModule.disablePC()
                self.privacyModule.setPrivacy(true)
            end
        end,
        handleHookState = function(isOffHook)
            self.hookStateModule.setHookState(isOffHook)
            local ptz = self.components.skaarhojPTZController
            if ptz and ptz["Button8"] then
                local color = isOffHook and "Warm White" or "Off"
                local header = isOffHook and "Send to PC" or "Off"
                self:safeComponentAccess(ptz, "Button8.color", "setString", color)
                self:safeComponentAccess(ptz, "Button8.headerText", "setString", header)
            end
            local camACPR = self.components.camACPR
            if camACPR then
                self:safeComponentAccess(camACPR, "CameraRouterOutput", "setString", isOffHook and "01" or "")
            end
            local compRoomControls = self.components.compRoomControls
            if compRoomControls then
                self:safeComponentAccess(compRoomControls, "CameraRouterOutput", "setString", isOffHook and "01" or "")
            end
        end
    }
end

--------------------------
-- COMPONENT MANAGEMENT (Optimized)
--------------------------
function SingleRoomCameraController:setComponent(ctrl, componentType)
    local componentName = ctrl.String
    if componentName == "" or componentName == self.clearString then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    else
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
    for _, v in pairs(self.components.invalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

--------------------------
-- COMPONENT SETUP
--------------------------
function SingleRoomCameraController:setupComponents()
    self:setCallSyncComponent()
    self:setSkaarhojPTZComponent()
    self:setCamRouterComponent()
    self:setCamACPRComponent()
    self:setCompRoomControlsComponent()
    if Controls.compdevCams then
        for i = 1, 5 do self:setDevCamComponent(i) end
    end
end

function SingleRoomCameraController:setCallSyncComponent()
    self.components.callSync = self:setComponent(Controls.compCallSync, "Call Sync")
    if self.components.callSync then
        self.components.callSync["off.hook"].EventHandler = function()
            local hookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
            self.hookStateModule.handleHookState(hookState)
        end
    end
end

function SingleRoomCameraController:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    self:registerSkaarhojComponentButtonHandlers()
end

function SingleRoomCameraController:registerSkaarhojComponentButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end
    for i = 1, 5 do
        local btn = ptz["Button"..i..".press"]
        if btn then
            btn.EventHandler = function()
                self:safeComponentAccess(ptz, "Button"..i..".headerText", "setString", "Active")
                if self.components.camRouter then
                    local camIndex = tostring(i)
                    self.components.camRouter["select.1"].String = camIndex
                    self.components.camRouter["select.2"].String = camIndex
                end
                -- Visual feedback for all buttons
                for j = 1, 5 do
                    self.ptzModule.setButtonActive(j, j == i)
                end
            end
        end
    end
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function()
            if self.components.callSync and self.components.callSync["off.hook"].Boolean then
                local currentCam = self.components.camRouter["select.1"].String
                self.components.camRouter["select.3"].String = currentCam
                self.components.camRouter["select.4"].String = currentCam
                local selectedText = ptz["Button"..currentCam..".screenText"]
                if selectedText then
                    self:safeComponentAccess(ptz, "Button8.screenText", "setString", selectedText.String)
                end
            end
        end
    end
end

function SingleRoomCameraController:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SingleRoomCameraController:setDevCamComponent(idx)
    if Controls.compdevCams and Controls.compdevCams[idx] then
        local labels = {[1]="Cam01", [2]="Cam02", [3]="Cam03", [4]="Cam04", [5]="Cam05"}
        self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], labels[idx])
    end
end

function SingleRoomCameraController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(Controls.compcamACPR, "Camera ACPR")
end

function SingleRoomCameraController:setCompRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
end

--------------------------
-- PRIVACY VISUALS
--------------------------
function SingleRoomCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

--------------------------
-- SYSTEM INITIALIZATION (Optimized)
--------------------------
function SingleRoomCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.cameraModule.recalibratePTZ()
    self.routingModule.clearRoutes()
    Timer.CallAfter(function()
        self.privacyModule.setPrivacy(true)
        for i = 1, 5 do 
            self.ptzModule.setButtonActive(i, false)    
        end
        self.ptzModule.disablePC()
        self:debugPrint("System initialization completed")
    end, self.config.recalibrationDelay)
end

--------------------------
-- COMPONENT NAME DISCOVERY
--------------------------
function SingleRoomCameraController:getComponentNames()
    local namesTable = {
        CallSyncNames = {},
        SkaarhojPTZNames = {},
        CamRouterNames = {},
        DevCamNames = {},
        CamACPRNames = {},
        CompRoomControlsNames = {},
    }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Name and comp.Name ~= "" then
            if comp.Type == "call_sync" then
                table.insert(namesTable.CallSyncNames, comp.Name)
            elseif comp.Type:find("Skaarhoj") then
                table.insert(namesTable.SkaarhojPTZNames, comp.Name)
            elseif comp.Type == "video_router" then
                table.insert(namesTable.CamRouterNames, comp.Name)
            elseif comp.Type == "onvif_camera_operative" then
                table.insert(namesTable.DevCamNames, comp.Name)
            elseif comp.Type:find("ACPR") then
                table.insert(namesTable.CamACPRNames, comp.Name)
            elseif comp.Type == "device_controller_script" and comp.Name:find("compRoomControls") then
                table.insert(namesTable.CompRoomControlsNames, comp.Name)
            end
        end
    end
    for _, list in pairs(namesTable) do table.sort(list); table.insert(list, self.clearString) end
    if Controls.compCallSync then Controls.compCallSync.Choices = namesTable.CallSyncNames end
    if Controls.compdevSkaarhojPTZ then Controls.compdevSkaarhojPTZ.Choices = namesTable.SkaarhojPTZNames end
    if Controls.compcamRouter then Controls.compcamRouter.Choices = namesTable.CamRouterNames end
    if Controls.compdevCams then
        for i, v in ipairs(Controls.compdevCams) do v.Choices = namesTable.DevCamNames end
    end
    if Controls.compcamACPR then Controls.compcamACPR.Choices = namesTable.CamACPRNames end
    if Controls.compRoomControls then Controls.compRoomControls.Choices = namesTable.CompRoomControlsNames end
end

--------------------------
-- EVENT HANDLER REGISTRATION
--------------------------
function SingleRoomCameraController:registerEventHandlers()
    if Controls.compCallSync then Controls.compCallSync.EventHandler = function() self:setCallSyncComponent() end end
    if Controls.compdevSkaarhojPTZ then Controls.compdevSkaarhojPTZ.EventHandler = function() self:setSkaarhojPTZComponent() end end
    if Controls.compcamRouter then Controls.compcamRouter.EventHandler = function() self:setCamRouterComponent() end end
    if Controls.compdevCams then
        for i, devCamComp in ipairs(Controls.compdevCams) do
            devCamComp.EventHandler = function() self:setDevCamComponent(i) end
        end
    end
    if Controls.compcamACPR then Controls.compcamACPR.EventHandler = function() self:setCamACPRComponent() end end
    if Controls.compRoomControls then Controls.compRoomControls.EventHandler = function() self:setCompRoomControlsComponent() end end
    if Controls.btnProductionMode then
        Controls.btnProductionMode.EventHandler = function()
            if self.components.camACPR then
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", Controls.btnProductionMode.Boolean)
            end
            if self.components.skaarhojPTZController then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Disable", "set", not Controls.btnProductionMode.Boolean)
            end
        end
    end
end

--------------------------
-- INITIALIZATION
--------------------------
function SingleRoomCameraController:funcInit()
    self:debugPrint("Starting Single Room Camera Controller initialization...")
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    self:debugPrint("Single Room Camera Controller Initialized with "..self.cameraModule.getCameraCount().." cameras")
end

--------------------------
-- FACTORY FUNCTION
--------------------------
local function createSingleRoomController(roomName, config)
    print("Creating Single Room Camera Controller for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = SingleRoomCameraController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created Single Room Camera Controller for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------------------------
-- INSTANCE CREATION
--------------------------
if not Controls.roomName then
    print("ERROR: Controls.roomName not found!")
    return
end

local formattedRoomName = "["..Controls.roomName.String.."]"
mySingleRoomController = createSingleRoomController(formattedRoomName)

if mySingleRoomController then
    print("Single Room Camera Controller created successfully!")
else
    print("ERROR: Failed to create Single Room Camera Controller!")
end
