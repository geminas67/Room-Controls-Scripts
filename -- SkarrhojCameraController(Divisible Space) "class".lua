--[[ 
  Skaarhoj Camera Controller - Divisible Space Version (Refactored)
  Author: Refactored from Single Room Camera Controller
  2025-06-24
  Firmware Req: 10.0.0
  Version: 1.3
  
  Refactored to follow Single Room Camera Controller pattern for consistency
  Converted from Q-Sys Block Controller to proper Lua class structure
  Updated to use new Controls structure with tables and tableNames
  Features consolidated camera router with unified select control scheme:
  - select.1/2: Monitor outputs for Room A/B
  - select.3/4: USB outputs for Room A/B
  Self-initializing script with automatic system setup on load
  Simplified hook state logic based on room mode and call sync states
  Optimized with helper functions to reduce code repetition and improve maintainability
  Added proper PTZ button event handlers and component validation
]]--

-- SkaarhojCameraController class
SkaarhojCameraController = {}
SkaarhojCameraController.__index = SkaarhojCameraController

--------** Class Constructor **--------
function SkaarhojCameraController.new(config)
    local self = setmetatable({}, SkaarhojCameraController)
    
    -- Instance properties
    self.roomName = "Divisible Space" -- Will be updated from component after initialization
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        skaarhojPTZController = "Skaarhoj",
        camRouter = "video_router",
        devCams = "onvif_camera_operative",
        camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
        roomControls = (comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls"))
    }
    -- Component storage using new Controls structure
    self.components = {
        callSync = {}, -- Controls.compCallSync.Choices, idx Rm-A [1], Rm-B [2]
        skaarhojPTZController = nil, -- Controls.compdevSkaarhojPTZ.Choices
        camRouter = nil, -- Controls.compcamRouter.Choices
        devCams = {}, -- Controls.compdevCams.Choices (cam01, cam02, cam03, cam04)
        camACPR = {}, -- Controls.compcamACPR.Choices idx Rm-A [1], Rm-B [2], Combined [3]
        compRoomControls = {}, -- Controls.compRoomControls.Choices idx Rm-A [1], Rm-B [2]
        productionMode = nil,
        powerStateRmA = nil,
        powerStateRmB = nil,
        roomsCombiner = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        combinedHookState = false,
        roomAMode = "divided",
        roomBMode = "divided",
        currentCameraSelection = 1,
        privacyState = {
            roomA = true,
            roomB = true
        }
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
        -- Camera Router Select Control Mapping:
        -- select.1 = Monitor Output Room A
        -- select.2 = Monitor Output Room B  
        -- select.3 = USB Output Room A
        -- select.4 = USB Output Room B
        initializationDelay = 0.1,
        recalibrationDelay = 1.0
    }
    
    -- Initialize modules
    self:initModules()
    
    return self
end

--------** Safe Component Access **--------
function SkaarhojCameraController:safeComponentAccess(component, control, action, value)
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

--------** Debug Helper **--------
function SkaarhojCameraController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Camera Debug] "..str) end
end

--------** Initialize Modules **--------
function SkaarhojCameraController:initModules()
    self:initCameraModule()
    self:initPrivacyModule()
    self:initRoutingModule()
    self:initPTZModule()
    self:initHookStateModule()
end

--------** Camera Module **--------
function SkaarhojCameraController:initCameraModule()
    self.cameraModule = {
        setPrivacy = function(room, state)
            local cameras = {}
            if room == "A" then
                cameras = {self.components.devCams[1], self.components.devCams[3]}
                self.state.privacyState.roomA = state
            elseif room == "B" then
                cameras = {self.components.devCams[2], self.components.devCams[4]}
                self.state.privacyState.roomB = state
            elseif room == "Combined" then
                cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
                self.state.privacyState.roomA = state
                self.state.privacyState.roomB = state
            end
            
            for _, camera in ipairs(cameras) do
                if camera then self:safeComponentAccess(camera, "toggle.privacy", "set", state) end
            end
            self:updatePrivacyVisuals()
        end,
        
        setAutoFrame = function(room, state)
            local cameras = {}
            if room == "A" then
                cameras = {self.components.devCams[1], self.components.devCams[3]}
            elseif room == "B" then
                cameras = {self.components.devCams[2], self.components.devCams[4]}
            elseif room == "Combined" then
                cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
            end
            
            for _, camera in ipairs(cameras) do
                if camera then self:safeComponentAccess(camera, "autoframe.enable", "set", state) end
            end
        end,
        
        recalibratePTZ = function()
            local cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
            
            -- Start recalibration
            for _, camera in ipairs(cameras) do
                if camera then self:safeComponentAccess(camera, "ptz.recalibrate", "set", true) end
            end
            
            -- Stop recalibration after delay
            Timer.CallAfter(function()
                for _, camera in ipairs(cameras) do
                    if camera then self:safeComponentAccess(camera, "ptz.recalibrate", "set", false) end
                end
            end, self.config.recalibrationDelay)
        end,
        
        getCameraCount = function()
            local cameras = {self.components.devCams[1], self.components.devCams[2], self.components.devCams[3], self.components.devCams[4]}
            local count = 0
            for _, camera in ipairs(cameras) do
                if camera then count = count + 1 end
            end
            return count
        end
    }
end

--------** Privacy Module **--------
function SkaarhojCameraController:initPrivacyModule()
    self.privacyModule = {
        setRoomAPrivacy = function(state)
            self.cameraModule.setPrivacy("A", state)
            self:debugPrint("Set Room A Privacy to "..tostring(state))
        end,
        
        setRoomBPrivacy = function(state)
            self.cameraModule.setPrivacy("B", state)
            self:debugPrint("Set Room B Privacy to "..tostring(state))
        end,
        
        setCombinedPrivacy = function(state)
            self.cameraModule.setPrivacy("Combined", state)
            self:debugPrint("Set Combined Privacy to "..tostring(state))
        end,
        
        updatePrivacyButton = function()
            local privacyActive = self.state.privacyState.roomA or self.state.privacyState.roomB
            local color = privacyActive and self.config.buttonColors.red or self.config.buttonColors.buttonOff
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", color)
        end
    }
end

--------** Routing Module **--------
function SkaarhojCameraController:initRoutingModule()
    local function setRouterOutput(outputNumber, cameraNumber)
        self:safeComponentAccess(self.components.camRouter, "select."..outputNumber, "setString", tostring(cameraNumber))
    end
    
    local function clearRoomRoutes(room)
        if room == "A" then
            setRouterOutput(1, self.config.defaultCameraRouterSettings.monitorA)
            setRouterOutput(3, self.config.defaultCameraRouterSettings.usbA)
        elseif room == "B" then
            setRouterOutput(2, self.config.defaultCameraRouterSettings.monitorB)
            setRouterOutput(4, self.config.defaultCameraRouterSettings.usbB)
        end
    end

    self.routingModule = {
        setMonitorRoute = function(cameraNumber, room)
            if room == "combined" then
                setRouterOutput(1, cameraNumber)
                setRouterOutput(2, cameraNumber)
                self:handleCombinedRouting()
            elseif room == "A" then
                setRouterOutput(1, cameraNumber)
                self:handleRoomARouting()
            elseif room == "B" then
                setRouterOutput(2, cameraNumber)
                self:handleRoomBRouting()
            end
        end,
        
        setUSBRoute = function(cameraNumber, room)
            if room == "A" then
                setRouterOutput(3, cameraNumber)
            elseif room == "B" then
                setRouterOutput(4, cameraNumber)
            end
        end,
        
        clearRoutes = function(room)
            clearRoomRoutes(room)
        end,
        
        handleCombinedRouting = function()
            if self:safeComponentAccess(self.components.callSync[1], "off.hook", "get") then
                self.ptzModule.disableRoomBPC()
                Timer.CallAfter(function()
                    self.ptzModule.enableRoomAPC()
                end, self.config.initializationDelay)
            elseif self:safeComponentAccess(self.components.callSync[2], "off.hook", "get") then
                self.ptzModule.disableRoomAPC()
                Timer.CallAfter(function()
                    self.ptzModule.enableRoomBPC()
                end, self.config.initializationDelay)
            end
        end,
        
        handleRoomARouting = function()
            self.ptzModule.disableRoomBPC()
            self.ptzModule.enableRoomAPC()
        end,
        
        handleRoomBRouting = function()
            self.ptzModule.disableRoomAPC()
            self.ptzModule.enableRoomBPC()
        end
    }
end

--------** PTZ Module **--------
function SkaarhojCameraController:initPTZModule()
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

    self.ptzModule = {
        enableRoomAPC = function()
            setButtonProperties(8, "Send to PC A", nil, nil, self.config.buttonColors.warmWhite)
            self:debugPrint("Enabled Room A PC")
        end,
        
        disableRoomAPC = function()
            setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff)
            self:debugPrint("Disabled Room A PC")
        end,
        
        enableRoomBPC = function()
            setButtonProperties(9, "Send to PC B", nil, nil, self.config.buttonColors.warmWhite)
            self:debugPrint("Enabled Room B PC")
        end,
        
        disableRoomBPC = function()
            setButtonProperties(9, "", "", "None", self.config.buttonColors.buttonOff)
            self:debugPrint("Disabled Room B PC")
        end,
        
        setButtonActive = function(buttonNumber, active)
            local headerText = active and "Active" or "Preview Mon"
            setButtonProperties(buttonNumber, headerText)
            self:debugPrint("Set Button"..buttonNumber.." to "..(active and "Active" or "Preview Mon"))
        end,
        
        setCameraLabel = function(buttonNumber, cameraNumber)
            local cameraLabels = {
                ["1"] = "Cam01",
                ["2"] = "Cam02", 
                ["3"] = "Cam03",
                ["4"] = "Cam04"
            }
            local label = cameraLabels[tostring(cameraNumber)] or ""
            setButtonProperties(buttonNumber, nil, label)
            self:debugPrint("Set Button"..buttonNumber.." to "..label)
        end
    }
end

--------** Hook State Module **--------
function SkaarhojCameraController:initHookStateModule()
    self.hookStateModule = {
        setCombinedHookState = function(state)
            self.state.combinedHookState = state
            if state then
                -- Combined - Off Hook - Privacy Off
                self.ptzModule.enableRoomAPC()
                self.privacyModule.setCombinedPrivacy(false)
                if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", false)
                end
                self:safeComponentAccess(self.components.compRoomControls[1], "TrackingBypass", "set", true)
                self:safeComponentAccess(self.components.compRoomControls[2], "TrackingBypass", "set", true)
            else
                -- Combined - On Hook - Privacy On
                self.ptzModule.disableRoomAPC()
                self.ptzModule.disableRoomBPC()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.controlLink", "setString", "None")
                self.privacyModule.setCombinedPrivacy(true)
                Timer.CallAfter(function()
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
                end, self.config.initializationDelay * 2)
            end
        end,
        
        handleRoomAHookState = function(isOffHook)
            if self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
                -- Combined mode: Execute setCombinedHookState per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(isOffHook)
                if isOffHook then
                    self:safeComponentAccess(self.components.camACPR[3], "CameraRouterOutput", "setString", "01")
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", false)
                else
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", true)
                end
            elseif self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode: Execute individual room hook state per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(false)
                if isOffHook then
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
                    self.ptzModule.enableRoomAPC()
                    if not (self.components.productionMode and self:safeComponentAccess(self.components.productionMode, "state", "get")) then
                        self:safeComponentAccess(self.components.compRoomControls[1], "CameraRouterOutput", "setString", "01")
                        self.privacyModule.setRoomAPrivacy(false)
                    end
                else
                    self.ptzModule.disableRoomAPC()
                    self:safeComponentAccess(self.components.compRoomControls[1], "TrackingBypass", "set", true)
                    self.privacyModule.setRoomAPrivacy(true)
                end
            else
                -- Default behavior when roomsCombiner is not available
                self:debugPrint("roomsCombiner not available - using default hook state behavior")
                if isOffHook then
                    self.ptzModule.enableRoomAPC()
                    self.privacyModule.setRoomAPrivacy(false)
                else
                    self.ptzModule.disableRoomAPC()
                    self.privacyModule.setRoomAPrivacy(true)
                end
            end
        end,
        
        handleRoomBHookState = function(isOffHook)
            if self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
                -- Combined mode: Execute setCombinedHookState per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(isOffHook)
                if isOffHook then
                    self:safeComponentAccess(self.components.camACPR[3], "CameraRouterOutput", "setString", "02")
                    self:debugPrint("Combine - Privacy OFF")
                else
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
                    self:debugPrint("Combine - Privacy ON")
                end
            elseif self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode: Execute individual room hook state per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(false)
                if isOffHook then
                    self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
                    self.ptzModule.enableRoomBPC()
                    if not (self.components.productionMode and self:safeComponentAccess(self.components.productionMode, "state", "get")) then
                        self:safeComponentAccess(self.components.compRoomControls[2], "CameraRouterOutput", "setString", "02")
                        self.privacyModule.setRoomBPrivacy(false)
                    end
                else
                    self.ptzModule.disableRoomBPC()
                    self:safeComponentAccess(self.components.compRoomControls[2], "TrackingBypass", "set", true)
                    self.privacyModule.setRoomBPrivacy(true)
                end
            else
                -- Default behavior when roomsCombiner is not available
                self:debugPrint("roomsCombiner not available - using default hook state behavior")
                if isOffHook then
                    self.ptzModule.enableRoomBPC()
                    self.privacyModule.setRoomBPrivacy(false)
                else
                    self.ptzModule.disableRoomBPC()
                    self.privacyModule.setRoomBPrivacy(true)
                end
            end
        end
    }
end

--------** Component Management **--------
function SkaarhojCameraController:setComponent(ctrl, componentType)
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

function SkaarhojCameraController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function SkaarhojCameraController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function SkaarhojCameraController:checkStatus()
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
function SkaarhojCameraController:setupComponents()
    self:setCallSyncComponent()
    self:setSkaarhojPTZComponent()
    self:setCamRouterComponent()
    self:setCamACPRComponent()
    self:setCompRoomControlsComponent()
    if Controls.compdevCams then
        for i = 1, 4 do self:setDevCamComponent(i) end
    end
end

function SkaarhojCameraController:setCallSyncComponent()
    -- Setup call sync components (Rm-A [1], Rm-B [2])
    for i = 1, 2 do
        if Controls.compCallSync and Controls.compCallSync[i] then
            local roomLabel = i == 1 and "Rm-A" or "Rm-B"
            local componentType = "Call Sync " .. roomLabel
            self.components.callSync[i] = self:setComponent(Controls.compCallSync[i], componentType)
            
            if self.components.callSync[i] then
                self.components.callSync[i]["off.hook"].EventHandler = function()
                    local hookState = self:safeComponentAccess(self.components.callSync[i], "off.hook", "get")
                    if i == 1 then
                        self.hookStateModule.handleRoomAHookState(hookState)
                    else
                        self.hookStateModule.handleRoomBHookState(hookState)
                    end
                end
            end
        end
    end
end

function SkaarhojCameraController:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
    self:registerSkaarhojComponentButtonHandlers()
end

function SkaarhojCameraController:registerSkaarhojComponentButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then 
        return 
    end
    for i = 1, 4 do
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
                for j = 1, 4 do
                    self.ptzModule.setButtonActive(j, j == i)
                end
            end
        end
    end
    -- Room A PC button (Button8)
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function()
            if self.components.callSync[1] and self.components.callSync[1]["off.hook"].Boolean then
                local currentCam = self.components.camRouter["select.1"].String
                self.components.camRouter["select.3"].String = currentCam
                local selectedText = ptz["Button"..currentCam..".screenText"]
                if selectedText then
                    self:safeComponentAccess(ptz, "Button8.screenText", "setString", selectedText.String)
                end
            end
        end
    end
    -- Room B PC button (Button9)
    local btn9 = ptz["Button9.press"]
    if btn9 then
        btn9.EventHandler = function()
            if self.components.callSync[2] and self.components.callSync[2]["off.hook"].Boolean then
                local currentCam = self.components.camRouter["select.2"].String
                self.components.camRouter["select.4"].String = currentCam
                local selectedText = ptz["Button"..currentCam..".screenText"]
                if selectedText then
                    self:safeComponentAccess(ptz, "Button9.screenText", "setString", selectedText.String)
                end
            end
        end
    end
end

function SkaarhojCameraController:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SkaarhojCameraController:setDevCamComponent(idx)
    if Controls.compdevCams and Controls.compdevCams[idx] then
        local cameraLabels = {[1] = "Cam01", [2] = "Cam02", [3] = "Cam03", [4] = "Cam04"}
        self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], cameraLabels[idx])
    end
end

function SkaarhojCameraController:setCamACPRComponent()
    -- Setup ACPR components (Rm-A [1], Rm-B [2], Combined [3])
    for i = 1, 3 do
        if Controls.compcamACPR and Controls.compcamACPR[i] then
            local acprLabels = {[1] = "ACPR Rm-A", [2] = "ACPR Rm-B", [3] = "ACPR Combined"}
            self.components.camACPR[i] = self:setComponent(Controls.compcamACPR[i], acprLabels[i])
        end
    end
end

function SkaarhojCameraController:setCompRoomControlsComponent()
    -- Setup room controls (Rm-A [1], Rm-B [2])
    for i = 1, 2 do
        if Controls.compRoomControls and Controls.compRoomControls[i] then
            local roomLabel = i == 1 and "Rm-A" or "Rm-B"
            local componentType = "Room Controls " .. roomLabel
            self.components.compRoomControls[i] = self:setComponent(Controls.compRoomControls[i], componentType)
        end
    end
end

--------** Room Name Management **--------
function SkaarhojCameraController:updateRoomName()
    -- Try to get room name from the first room controls component
    if self.components.compRoomControls and self.components.compRoomControls[1] then
        local roomName = self:safeComponentAccess(self.components.compRoomControls[1], "roomName", "getString")
        if roomName and roomName ~= "" and roomName ~= self.clearString then
            self.roomName = roomName
            self:debugPrint("Room name updated to: " .. roomName)
        end
    end
end

--------** Privacy Visuals **--------
function SkaarhojCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

--------** System Initialization **--------
function SkaarhojCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    self.cameraModule.recalibratePTZ()
    self.routingModule.clearRoutes("A")
    self.routingModule.clearRoutes("B")
    Timer.CallAfter(function()
        self.privacyModule.setCombinedPrivacy(true)
        for i = 1, 4 do 
            self.ptzModule.setButtonActive(i, false)    
        end
        self.ptzModule.disableRoomAPC()
        self.ptzModule.disableRoomBPC()
        self:debugPrint("System initialization completed")
    end, self.config.recalibrationDelay)
end

--------** Component Name Discovery **--------
function SkaarhojCameraController:getComponentNames()
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
            if comp.Type == self.componentTypes.callSync then
                table.insert(namesTable.CallSyncNames, comp.Name)
            elseif comp.Type == self.componentTypes.skaarhojPTZController then
                table.insert(namesTable.SkaarhojPTZNames, comp.Name)
            elseif comp.Type == self.componentTypes.camRouter then
                table.insert(namesTable.CamRouterNames, comp.Name)
            elseif comp.Type == self.componentTypes.devCams then
                table.insert(namesTable.DevCamNames, comp.Name)
            elseif comp.Type == self.componentTypes.camACPR then
                table.insert(namesTable.CamACPRNames, comp.Name)
            elseif comp.Type == self.componentTypes.roomControls then
                table.insert(namesTable.CompRoomControlsNames, comp.Name)
            end
        end
    end
    for _, list in pairs(namesTable) do 
        table.sort(list)
        table.insert(list, self.clearString)
    end
    if Controls.compCallSync then 
        for i, v in ipairs(Controls.compCallSync) do
            v.Choices = namesTable.CallSyncNames 
        end
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
        for i, v in ipairs(Controls.compcamACPR) do 
            v.Choices = namesTable.CamACPRNames 
        end
    end
    if Controls.compRoomControls then 
        for i, v in ipairs(Controls.compRoomControls) do 
            v.Choices = namesTable.CompRoomControlsNames 
        end
    end
end

--------** Event Handler Registration **--------
function SkaarhojCameraController:registerEventHandlers()
    if Controls.compCallSync then 
        for i, callSyncComp in ipairs(Controls.compCallSync) do
            callSyncComp.EventHandler = function() 
                self:setCallSyncComponent() 
            end 
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
        end 
    end
    if Controls.compdevCams then
        for i, devCamComp in ipairs(Controls.compdevCams) do
            devCamComp.EventHandler = function() self:setDevCamComponent(i) end
        end
    end
    if Controls.compcamACPR then 
        for i, acprComp in ipairs(Controls.compcamACPR) do
            acprComp.EventHandler = function() 
                self:setCamACPRComponent() 
            end 
        end
    end
    if Controls.compRoomControls then 
        for i, roomControlComp in ipairs(Controls.compRoomControls) do
            roomControlComp.EventHandler = function() 
                self:setCompRoomControlsComponent() 
                self:updateRoomName() -- Update room name when component changes
            end 
        end
    end
    if Controls.btnProductionMode then
        Controls.btnProductionMode.EventHandler = function()
            local state = Controls.btnProductionMode.Boolean
            for i, acpr in ipairs(self.components.camACPR) do
                if acpr then
                    self:safeComponentAccess(acpr, "TrackingBypass", "set", state)
                end
            end
            if self.components.skaarhojPTZController then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Disable", "set", not state)
            end
        end
    end
end

--------** Initialization **--------
function SkaarhojCameraController:funcInit()
    self:debugPrint("Starting Divisible Space Camera Controller initialization...")
    self:getComponentNames()
    self:setupComponents()
    self:updateRoomName() -- Update room name from component
    self:registerEventHandlers()
    self:performSystemInitialization()
    self:debugPrint("Divisible Space Camera Controller Initialized with "..self.cameraModule.getCameraCount().." cameras")
end

--------** Factory Function **--------
local function createDivisibleSpaceController(config)
    print("Creating Divisible Space Camera Controller...")
    local success, controller = pcall(function()
        local instance = SkaarhojCameraController.new(config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created Divisible Space Camera Controller")
        return controller
    else
        print("Failed to create controller: "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
myDivisibleSpaceController = createDivisibleSpaceController()

if myDivisibleSpaceController then
    print("Divisible Space Camera Controller created successfully!")
else
    print("ERROR: Failed to create Divisible Space Camera Controller!")
end 