--[[ 
  Single Room Camera Controller - Optimized Version
  Author: Perplexity AI (Refactored for Performance)
  2025-06-24
  Firmware Req: 10.0.0
  Version: 1.1
]]--

--------** Class Constructor **--------
SingleRoomCameraController = {}
SingleRoomCameraController.__index = SingleRoomCameraController

function SingleRoomCameraController.new(roomName, config)
    local self = setmetatable({}, SingleRoomCameraController)
    -- Instance properties
    self.roomName = roomName or "Single Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    -- Component references
    self.components = {
        callSync = nil,
        skaarhojPTZController = nil,
        camRouter = nil,
        devCams = {},
        camACPR = nil,
        compRoomControls = nil,
        invalid = {}
    }
    -- State variables
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

--------** Debug Helper **--------
function SingleRoomCameraController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Camera Debug] "..str) end
end

--------** Safe Component Access **--------
function SingleRoomCameraController:safeComponentAccess(component, control, action, value)
    local compCtrl = component and component[control]
    if not compCtrl then 
        return false 
    end
    local ok, result = pcall(function()
        if action == "set" then 
            compCtrl.Boolean = value
        elseif action == "setPosition" then 
            compCtrl.Position = value
        elseif action == "setString" then 
            compCtrl.String = value
        elseif action == "trigger" then 
            compCtrl:Trigger()
        elseif action == "get" then     
            return compCtrl.Boolean
        elseif action == "getPosition" then 
            return compCtrl.Position
        elseif action == "getString" then 
            return compCtrl.String
        end
        return true
    end)

    if not ok then 
        self:debugPrint("Component access error: "..tostring(result)) 
    end
    return ok and result
end

--------** Initialize Modules **--------
function SingleRoomCameraController:initModules()
    self:initCameraModule()
    self:initPrivacyModule()
    self:initRoutingModule()
    self:initPTZModule()
    self:initHookStateModule()
end

--------** Camera Module **--------
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
                if cam then self:safeComponentAccess(cam, "ptz.recalibrate", "trigger") end
            end
        end,
        getCameraCount = function()
            local count = 0
            for _, cam in pairs(self.components.devCams) do if cam then count = count + 1 end end
            return count
        end
    }
end

--------** Privacy Module **--------
function SingleRoomCameraController:initPrivacyModule()
    self.privacyModule = {
        setPrivacy = function(state) 
            self.cameraModule.setPrivacy(state) 
            self:debugPrint("Set Privacy to "..tostring(state))
        end,
        updatePrivacyButton = function()
            local color = self.state.privacyState and self.config.buttonColors.white or self.config.buttonColors.buttonOff
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", color)
        end
    }
end

--------** Routing Module **--------
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
        setMonitorRouteA = function(cameraNumber) 
            setRouterOutput(1, cameraNumber) 
            self:debugPrint("Set Monitor Route A to "..cameraNumber)
        end,
        setMonitorRouteB = function(cameraNumber) 
            setRouterOutput(2, cameraNumber) 
            self:debugPrint("Set Monitor Route B to "..cameraNumber)
        end,
        setUSBRouteA = function(cameraNumber) 
            setRouterOutput(3, cameraNumber) 
            self:debugPrint("Set USB Route A to "..cameraNumber)
        end,
        setUSBRouteB = function(cameraNumber) 
            setRouterOutput(4, cameraNumber) 
            self:debugPrint("Set USB Route B to "..cameraNumber)
        end,
        clearRoutes = clearRoutes,  
        setAllRoutes = function(cameraNumber)
            for i = 1, 4 do setRouterOutput(i, cameraNumber) end
        end
    }
end

--------** PTZ Module **--------
function SingleRoomCameraController:initPTZModule()
    local function setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
        local base = self.components.skaarhojPTZController
        if not base then 
            self:debugPrint("PTZ Controller not found")
            return 
        end
        if headerText then 
            self:safeComponentAccess(base, "Button"..buttonNumber..".headerText", "setString", headerText) 
            self:debugPrint("Set Button"..buttonNumber..".headerText to "..headerText)
        end
        if screenText then 
            self:safeComponentAccess(base, "Button"..buttonNumber..".screenText", "setString", screenText) 
            self:debugPrint("Set Button"..buttonNumber..".screenText to "..screenText)
        end
        if controlLink then 
            self:safeComponentAccess(base, "Button"..buttonNumber..".controlLink", "setString", controlLink) 
            self:debugPrint("Set Button"..buttonNumber..".controlLink to "..controlLink)
        end
        if color then 
            self:safeComponentAccess(base, "Button"..buttonNumber..".color", "setString", color) 
            self:debugPrint("Set Button"..buttonNumber..".color to "..color)
        end
    end
    
    local function syncButtonStates(selectedCamera)
        if not self.components.skaarhojPTZController then
            self:debugPrint("PTZ Controller not available for button sync")
            return
        end
        
        for i = 1, 5 do
            local isSelected = (i == selectedCamera)
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button"..i..".press", "set", isSelected)
            if isSelected then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button"..i..".headerText", "setString", "Preview Mon")
            else
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button"..i..".headerText", "setString", "Select")
            end
        end
        self:debugPrint("Button states synced - Camera "..selectedCamera.." selected")
    end
    
    self.ptzModule = {
        enablePC = function() 
            setButtonProperties(8, "Send to PC", nil, nil, self.config.buttonColors.warmWhite) 
            self:debugPrint("Enabled PC")
        end,
        disablePC = function() 
            setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff) 
            self:debugPrint("Disabled PC")
        end,
        setButtonPreviewMon = function(buttonNumber, previewMon)
            setButtonProperties(buttonNumber, previewMon and "Preview Mon" or "Select")
            self:debugPrint("Set Button"..buttonNumber.." to "..(previewMon and "Preview Mon" or "Select"))
        end,
        setCameraLabel = function(buttonNumber, cameraNumber)
            local labels = {["1"]="Cam A", ["2"]="Cam D", ["3"]="Cam B", ["4"]="Cam C", ["5"]="Cam E"}
            setButtonProperties(buttonNumber, nil, labels[tostring(cameraNumber)] or "")
            self:debugPrint("Set Button"..buttonNumber.." to "..(labels[tostring(cameraNumber)] or ""))
        end,
        syncButtonStates = syncButtonStates
    }
end

--------** Hook State Module **--------
function SingleRoomCameraController:initHookStateModule()
    self.hookStateModule = {
        setHookState = function(state)
            self.state.hookState = state
            if state then
                self.ptzModule.enablePC()
                self.privacyModule.setPrivacy(false)
                if self.components.camACPR then
                    -- TrackingBypass = true when production mode is ON (regardless of hook state)
                    -- TrackingBypass = false when production mode is OFF AND call sync is off hook
                    local productionModeOn = Controls.btnProductionMode and Controls.btnProductionMode.Boolean
                    local shouldBypass = productionModeOn or not state
                    self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", shouldBypass)
                    self:debugPrint("Production mode: "..tostring(productionModeOn)..", Off hook: "..tostring(state)..", TrackingBypass: "..tostring(shouldBypass))
                end
            else
                self.ptzModule.disablePC()
                self.privacyModule.setPrivacy(true)
            end
        end,
        handleHookState = function(isOffHook)
            local wasOffHook = self.state.hookState
            self.hookStateModule.setHookState(isOffHook)
            
            -- If transitioning from not off-hook to off-hook, automatically select camera 5
            if isOffHook and not wasOffHook then
                if self.components.camRouter then
                    -- Set camera 5 (Cam E) for all monitor routes
                    self.components.camRouter["select.1"].String = "5"
                    self.components.camRouter["select.2"].String = "5"
                    self:debugPrint("Auto-selected Camera 5 (Cam E) when going off-hook")
                end
            end
            
            if not isOffHook then 
                self.routingModule.setUSBRouteA('6')
                self.routingModule.setUSBRouteB('6')
            end
            
            local ptz = self.components.skaarhojPTZController
            if ptz and ptz["Button8"] then
                self:safeComponentAccess(ptz, "Button8.color", "setString", isOffHook and "Warm White" or "Off")
                self:safeComponentAccess(ptz, "Button8.headerText", "setString", isOffHook and "Send to PC" or "Off")
            end
            
            -- Update button states based on current router selection when hook state changes
            if self.components.camRouter and self.routerSyncFunction then
                self.routerSyncFunction()
            end
        end
    }
end

--------** Component Management **--------
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

--------** Component Setup **--------
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
    -- Initialize camera labels for buttons 1-5
    if self.components.skaarhojPTZController then
        for i = 1, 5 do
            self.ptzModule.setCameraLabel(i, i)
        end
        self:debugPrint("Camera labels initialized for buttons 1-5")
    end
end

function SingleRoomCameraController:registerSkaarhojComponentButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then 
        return 
    end
    for i = 1, 5 do
        local btn = ptz["Button"..i..".press"]
        if btn then
            btn.EventHandler = function()
                if self.components.camRouter then
                    local camIndex = tostring(i)
                    self.components.camRouter["select.1"].String = camIndex
                    self.components.camRouter["select.2"].String = camIndex
                    -- The router's EventHandler will automatically update the button states
                    self:debugPrint("Skaarhoj Button"..i.." pressed - set router to Camera "..camIndex)
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
                self:debugPrint("Skaarhoj Button8 pressed - sent Camera "..currentCam.." to USB routes")
            end
        end
    end
end

function SingleRoomCameraController:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
    if self.components.camRouter then
        -- Create a sync function that doesn't require the control parameter
        local function syncButtonStatesFromRouter()
            local selectedCamera = tonumber(self.components.camRouter["select.1"].String) or 0
            self.ptzModule.syncButtonStates(selectedCamera)
            self:debugPrint("Camera router Monitor Route A synced to Camera " .. selectedCamera)
        end
        
        -- Add real-time feedback handler for Monitor Route A (select.1)
        self.components.camRouter["select.1"].EventHandler = function(ctl)
            if ctl then
                local selectedCamera = tonumber(ctl.String) or 0
                -- Update Skaarhoj button states based on router selection
                self.ptzModule.syncButtonStates(selectedCamera)
                self:debugPrint("Camera router Monitor Route A set to Camera " .. selectedCamera)
            end
        end

        -- Add real-time feedback handler for Monitor Route B (select.2)
        self.components.camRouter["select.2"].EventHandler = function(ctl)
            if ctl then
                local selectedCamera = tonumber(ctl.String) or 0
                self:debugPrint("Camera router Monitor Route B set to Camera " .. selectedCamera)
            end
        end

        -- Add real-time feedback handler for USB Route A (select.3)
        self.components.camRouter["select.3"].EventHandler = function(ctl)
            if ctl then
                local selectedCamera = tonumber(ctl.String) or 0
                self:debugPrint("Camera router USB Route A set to Camera " .. selectedCamera)
            end
        end

        -- Add real-time feedback handler for USB Route B (select.4)
        self.components.camRouter["select.4"].EventHandler = function(ctl)
            if ctl then
                local selectedCamera = tonumber(ctl.String) or 0
                self:debugPrint("Camera router USB Route B set to Camera " .. selectedCamera)
            end
        end

        -- Store the sync function for later use
        self.routerSyncFunction = syncButtonStatesFromRouter
        
        -- Trigger initial sync
        syncButtonStatesFromRouter()
        self:debugPrint("Camera router real-time feedback handlers registered")
    end
end

function SingleRoomCameraController:setDevCamComponent(idx)
    if Controls.compdevCams and Controls.compdevCams[idx] then
        local labels = {[1]="Cam A", [2]="Cam D", [3]="Cam B", [4]="Cam C", [5]="Cam E"}
        self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], labels[idx])
    end
end

function SingleRoomCameraController:setCamACPRComponent()
    self.components.camACPR = self:setComponent(Controls.compcamACPR, "Camera ACPR")
end

function SingleRoomCameraController:setCompRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.compRoomControls then
        -- Update room name from the component
        self:updateRoomNameFromComponent()
        
        -- Add event handler for system power LED
        local ledSystemPower = self.components.compRoomControls["ledSystemPower"]
        if ledSystemPower then
            ledSystemPower.EventHandler = function()
                local systemPowerState = self:safeComponentAccess(self.components.compRoomControls, "ledSystemPower", "get")
                if not systemPowerState then
                    Controls.btnProductionMode.Boolean = false
                    self:debugPrint("System power off - Production mode set to false")
                    -- Manually trigger production mode logic 
                    if self.components.camACPR then
                        self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", true)
                    end
                    if self.components.skaarhojPTZController then
                        self:safeComponentAccess(self.components.skaarhojPTZController, "Disable", "set", true)
                    end
                end
            end
        end
        
        -- Add event handler for room name changes
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl then
            roomNameControl.EventHandler = function()
                self:updateRoomNameFromComponent()
            end
        end
    end
end

--------** Room Name Management **--------
function SingleRoomCameraController:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
    end
end

--------** Privacy Visuals **--------
function SingleRoomCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

--------** System Initialization **--------
function SingleRoomCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.cameraModule.recalibratePTZ()
    self.routingModule.clearRoutes()
    -- Initialize camera labels
    if self.components.skaarhojPTZController then
        for i = 1, 5 do
            self.ptzModule.setCameraLabel(i, i)
        end
        self:debugPrint("Camera labels set during system initialization")
    end
    Timer.CallAfter(function()
        -- Only set privacy if we're not off hook
        if not self.state.hookState then
            self.privacyModule.setPrivacy(true)
            self.ptzModule.disablePC()
        end
        -- The router's EventHandler will automatically set the correct button states
        if self.components.camRouter and self.routerSyncFunction then
            self.routerSyncFunction()
        end
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
            elseif comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls") then
                table.insert(namesTable.CompRoomControlsNames, comp.Name)
            end
        end
    end
    for _, list in pairs(namesTable) do 
        table.sort(list)
        table.insert(list, self.clearString)
    end
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
    if Controls.compCallSync then 
        Controls.compCallSync.EventHandler = function() 
            self:setCallSyncComponent() 
        end 
    end
    if Controls.compdevSkaarhojPTZ then 
        Controls.compdevSkaarhojPTZ.EventHandler = function() 
            self:setSkaarhojPTZComponent() 
            self:registerSkaarhojComponentButtonHandlers()
        end 
    end
    if Controls.compcamRouter then 
        Controls.compcamRouter.EventHandler = function() 
            self:setCamRouterComponent() 
            self:registerCamRouterComponentButtonHandlers()
        end 
    end
    if Controls.compdevCams then
        for i, devCamComp in ipairs(Controls.compdevCams) do
            devCamComp.EventHandler = function() self:setDevCamComponent(i) end
        end
    end
    if Controls.compcamACPR then 
        Controls.compcamACPR.EventHandler = function() 
            self:setCamACPRComponent() 
            self:registerCamACPRComponentButtonHandlers()
        end 
    end
    if Controls.compRoomControls then 
        Controls.compRoomControls.EventHandler = function() 
            self:setCompRoomControlsComponent() 
            self:registerCompRoomControlsComponentButtonHandlers()
        end 
    end
    if Controls.btnProductionMode then
        Controls.btnProductionMode.EventHandler = function()
            if self.components.skaarhojPTZController then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Disable", "set", not Controls.btnProductionMode.Boolean)
            end
            -- Update TrackingBypass when production mode changes
            if self.components.camACPR then
                local productionModeOn = Controls.btnProductionMode.Boolean
                local isOffHook = self.state.hookState
                local shouldBypass = productionModeOn or not isOffHook
                self:safeComponentAccess(self.components.camACPR, "TrackingBypass", "set", shouldBypass)
                self:debugPrint("Production mode changed - Production mode: "..tostring(productionModeOn)..", Off hook: "..tostring(isOffHook)..", TrackingBypass: "..tostring(shouldBypass))
            end
        end
    end
end

--------** Handler Registration Functions **--------
function SingleRoomCameraController:registerCamRouterComponentButtonHandlers()
    -- Placeholder for camera router button handlers if needed
    self:debugPrint("Camera router button handlers registered")
end

function SingleRoomCameraController:registerCamACPRComponentButtonHandlers()
    -- Placeholder for camera ACPR button handlers if needed
    self:debugPrint("Camera ACPR button handlers registered")
end

function SingleRoomCameraController:registerCompRoomControlsComponentButtonHandlers()
    -- Placeholder for room controls button handlers if needed
    self:debugPrint("Room controls button handlers registered")
end

--------** Initialization **--------
function SingleRoomCameraController:funcInit()
    self:debugPrint("Starting Single Room Camera Controller initialization...")
    self:getComponentNames()
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    -- Get initial hook state
    if self.components.callSync then
        local initialHookState = self:safeComponentAccess(self.components.callSync, "off.hook", "get")
        self:debugPrint("Initial hook state: "..tostring(initialHookState))
        self.hookStateModule.handleHookState(initialHookState)
    end
    
    self:debugPrint("Single Room Camera Controller Initialized with "..self.cameraModule.getCameraCount().." cameras")
end

--------** Factory Function **--------
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

--------** Instance Creation **--------
-- Get room name from room controls component
local function getRoomNameFromComponent()
    -- First try to get from the room controls component if it's already set
    if Controls.compRoomControls and Controls.compRoomControls.String ~= "" and Controls.compRoomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(Controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    
    -- Fallback to default room name if component not available
    return "[Single Room]"
end

local roomName = getRoomNameFromComponent()
mySingleRoomController = createSingleRoomController(roomName)

if mySingleRoomController then
    print("Single Room Camera Controller created successfully!")
else
    print("ERROR: Failed to create Single Room Camera Controller!")
end
