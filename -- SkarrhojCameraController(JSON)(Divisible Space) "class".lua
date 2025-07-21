--[[ 
  Skaarhoj Camera Controller - Modular Version
  Author: Refactored from Q-Sys Block Controller
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.2
  
  Refactored to follow UCI script pattern for modularity and reusability
  Converted from Q-Sys Block Controller to proper Lua class structure
  Updated to use new Controls structure with tables and tableNames
  Features consolidated camera router with unified select control scheme:
  - select.1/2: Monitor outputs for Room A/B
  - select.3/4: USB outputs for Room A/B
  Self-initializing script with automatic system setup on load
  Simplified hook state logic based on room mode and call sync states
  Optimized with helper functions to reduce code repetition and improve maintainability
]]--

-- SkaarhojCameraController class
SkaarhojCameraController = {}
SkaarhojCameraController.__index = SkaarhojCameraController

--------** Class Constructor **--------
function SkaarhojCameraController.new(roomName, config)
    local self = setmetatable({}, SkaarhojCameraController)
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = config and config.debugging or true
    self.clearString = "[Clear]"
    
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
            red = 'Red'
        },
        defaultCameraRouterSettings = {
            monitor = '5',
            usb = '5'
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
    self:initCameraModule()
    self:initPrivacyModule()
    self:initRoutingModule()
    self:initPTZModule()
    self:initHookStateModule()
    
    return self
end

--------** Safe Component Access **--------
function SkaarhojCameraController:safeComponentAccess(component, control, action, value)
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
function SkaarhojCameraController:debugPrint(str)
    if self.debugging then
        print("[" .. self.roomName .. " Camera Debug] " .. str)
    end
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
            end
            
            for _, camera in ipairs(cameras) do
                self:safeComponentAccess(camera, "toggle.privacy", "set", state)
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
                self:safeComponentAccess(camera, "autoframe.enable", "set", state)
            end
        end,
        
        recalibratePTZ = function()
            local cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
            
            -- Start recalibration
            for _, camera in ipairs(cameras) do
                self:safeComponentAccess(camera, "ptz.recalibrate", "set", true)
            end
            
            -- Stop recalibration after delay
            Timer.CallAfter(function()
                for _, camera in ipairs(cameras) do
                    self:safeComponentAccess(camera, "ptz.recalibrate", "set", false)
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
        end,
        
        setRoomBPrivacy = function(state)
            self.cameraModule.setPrivacy("B", state)
        end,
        
        setCombinedPrivacy = function(state)
            self.cameraModule.setPrivacy("A", state)
            self.cameraModule.setPrivacy("B", state)
        end,
        
        updatePrivacyButton = function()
            local privacyActive = self.state.privacyState.roomA or self.state.privacyState.roomB
            if privacyActive then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", self.config.buttonColors.red)
            else
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button6.color", "setString", self.config.buttonColors.buttonOff)
            end
        end
    }
end

--------** Routing Module **--------
function SkaarhojCameraController:initRoutingModule()
    -- Helper function to set router output
    local function setRouterOutput(outputNumber, cameraNumber)
        self:safeComponentAccess(self.components.camRouter, "select." .. outputNumber, "setString", tostring(cameraNumber))
    end
    
    -- Helper function to clear router outputs for a room
    local function clearRoomRoutes(room)
        if room == "A" then
            setRouterOutput(1, self.config.defaultCameraRouterSettings.monitor)
            setRouterOutput(3, self.config.defaultCameraRouterSettings.usb)
        elseif room == "B" then
            setRouterOutput(2, self.config.defaultCameraRouterSettings.monitor)
            setRouterOutput(4, self.config.defaultCameraRouterSettings.usb)
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
        enableRoomAPC = function()
            setButtonProperties(8, "Send to PC A", nil, nil, self.config.buttonColors.warmWhite)
        end,
        
        disableRoomAPC = function()
            setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff)
        end,
        
        enableRoomBPC = function()
            setButtonProperties(9, "Send to PC B", nil, nil, self.config.buttonColors.warmWhite)
        end,
        
        disableRoomBPC = function()
            setButtonProperties(9, "", "", "None", self.config.buttonColors.buttonOff)
        end,
        
        setButtonActive = function(buttonNumber, active)
            local headerText = active and "Active" or "Preview Mon"
            setButtonProperties(buttonNumber, headerText)
        end,
        
        setCameraLabel = function(buttonNumber, cameraNumber)
            local cameraLabels = {
                ["1"] = "CAM-01",
                ["2"] = "CAM-03", 
                ["3"] = "CAM-02",
                ["4"] = "CAM-04"
            }
            local label = cameraLabels[tostring(cameraNumber)] or ""
            setButtonProperties(buttonNumber, nil, label)
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

--------** Component Setup Functions **--------
function SkaarhojCameraController:setCallSyncComponent(idx)
    if not Controls.compCallSync or not Controls.compCallSync[idx] then
        self:debugPrint("Call Sync control " .. idx .. " not found in compCallSync array")
        return
    end
    
    local roomLabel = idx == 1 and "Rm-A" or "Rm-B"
    local componentType = "Call Sync " .. roomLabel
    self.components.callSync[idx] = self:setComponent(Controls.compCallSync[idx], componentType)
    
    if self.components.callSync[idx] ~= nil then
        self.components.callSync[idx]["off.hook"].EventHandler = function()
            local hookState = self:safeComponentAccess(self.components.callSync[idx], "off.hook", "get")
            if idx == 1 then
                self.hookStateModule.handleRoomAHookState(hookState)
            else
                self.hookStateModule.handleRoomBHookState(hookState)
            end
        end
    end
end

function SkaarhojCameraController:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
end

function SkaarhojCameraController:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SkaarhojCameraController:setDevCamComponent(idx)
    if not Controls.compdevCams or not Controls.compdevCams[idx] then
        self:debugPrint("Camera control " .. idx .. " not found in compdevCams array")
        return
    end
    
    local cameraLabels = {[1] = "CAM-01", [2] = "CAM-02", [3] = "CAM-03", [4] = "CAM-04"}
    local componentType = cameraLabels[idx] or "Camera [" .. idx .. "]"
    self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], componentType)
end

function SkaarhojCameraController:setCamACPRComponent(idx)
    if not Controls.compcamACPR or not Controls.compcamACPR[idx] then
        self:debugPrint("ACPR control " .. idx .. " not found in compcamACPR array")
        return
    end
    
    local acprLabels = {[1] = "ACPR Rm-A", [2] = "ACPR Rm-B", [3] = "ACPR Combined"}
    local componentType = acprLabels[idx] or "ACPR [" .. idx .. "]"
    self.components.camACPR[idx] = self:setComponent(Controls.compcamACPR[idx], componentType)
end

function SkaarhojCameraController:setCompRoomControlsComponent(idx)
    if not Controls.compRoomControls or not Controls.compRoomControls[idx] then
        self:debugPrint("Room Controls " .. idx .. " not found in compRoomControls array")
        return
    end
    
    local roomLabel = idx == 1 and "Rm-A" or "Rm-B"
    local componentType = "Room Controls " .. roomLabel
    self.components.compRoomControls[idx] = self:setComponent(Controls.compRoomControls[idx], componentType)
end

function SkaarhojCameraController:setupComponents()
    -- Setup call sync components (Rm-A [1], Rm-B [2])
    for i = 1, 2 do
        self:setCallSyncComponent(i)
    end
    
    -- Setup single components
    self:setSkaarhojPTZComponent()
    self:setCamRouterComponent()
    
    -- Setup camera components (cam01, cam02, cam03, cam04) - only if compdevCams exists
    if Controls.compdevCams then
        for i = 1, 4 do
            self:setDevCamComponent(i)
        end
    else
        self:debugPrint("compdevCams control not found - skipping camera component setup")
    end
    
    -- Setup ACPR components (Rm-A [1], Rm-B [2], Combined [3])
    for i = 1, 3 do
        self:setCamACPRComponent(i)
    end
    
    -- Setup room controls (Rm-A [1], Rm-B [2])
    for i = 1, 2 do
        self:setCompRoomControlsComponent(i)
    end
    
    -- Setup legacy components (optional - only if they exist)
    if Controls.productionMode then
        self.components.productionMode = self:setComponent(Controls.productionMode, "Production Mode")
    else
        self:debugPrint("WARNING: Controls.productionMode not found - some features may be limited")
    end
    
    if Controls.powerStateRmA then
        self.components.powerStateRmA = self:setComponent(Controls.powerStateRmA, "Power State Rm-A")
    else
        self:debugPrint("WARNING: Controls.powerStateRmA not found - some features may be limited")
    end
    
    if Controls.powerStateRmB then
        self.components.powerStateRmB = self:setComponent(Controls.powerStateRmB, "Power State Rm-B")
    else
        self:debugPrint("WARNING: Controls.powerStateRmB not found - some features may be limited")
    end
    
    if Controls.roomsCombiner then
        self.components.roomsCombiner = self:setComponent(Controls.roomsCombiner, "Rooms Combiner")
    else
        self:debugPrint("WARNING: Controls.roomsCombiner not found - some features may be limited")
    end
end

--------** Helper Functions **--------
function SkaarhojCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

function SkaarhojCameraController:setLabelOfCameraSentToPC()
    local cameraNumber = self:safeComponentAccess(self.components.camRouter, "select.1", "getString")
    local buttonNumber = "8" -- Default to Room A button
    
    if cameraNumber == "1" then
        self.ptzModule.setCameraLabel(buttonNumber, "1")
    elseif cameraNumber == "2" then
        self.ptzModule.setCameraLabel(buttonNumber, "2")
    elseif cameraNumber == "3" then
        self.ptzModule.setCameraLabel(buttonNumber, "3")
    elseif cameraNumber == "4" then
        self.ptzModule.setCameraLabel(buttonNumber, "4")
    elseif cameraNumber == "5" then
        self.ptzModule.setCameraLabel(buttonNumber, "")
    end
end

function SkaarhojCameraController:handleRoomModeChange()
    self.ptzModule.disableRoomAPC()
    self.ptzModule.disableRoomBPC()
    
    if self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
        -- Divided mode
        self.hookStateModule.setCombinedHookState(false)
        self:safeComponentAccess(self.components.camACPR[3], "TrackingBypass", "set", true)
        
        if not (self.components.productionMode and self:safeComponentAccess(self.components.productionMode, "state", "get")) then
            if self:safeComponentAccess(self.components.callSync[1], "off.hook", "get") then
                self:safeComponentAccess(self.components.compRoomControls[1], "TrackingBypass", "set", false)
                self:safeComponentAccess(self.components.compRoomControls[1], "CameraRouterOutput", "setString", "01")
                self.privacyModule.setRoomAPrivacy(false)
                self.privacyModule.setRoomBPrivacy(true)
            elseif self:safeComponentAccess(self.components.callSync[2], "off.hook", "get") then
                self:safeComponentAccess(self.components.compRoomControls[2], "TrackingBypass", "set", false)
                self:safeComponentAccess(self.components.compRoomControls[2], "CameraRouterOutput", "setString", "02")
                self.privacyModule.setRoomBPrivacy(false)
                self.privacyModule.setRoomAPrivacy(true)
            end
        end
    elseif self.components.roomsCombiner and self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
        -- Combined mode
        self:safeComponentAccess(self.components.compRoomControls[1], "TrackingBypass", "set", true)
        self:safeComponentAccess(self.components.compRoomControls[2], "TrackingBypass", "set", true)
        
        if not (self.components.productionMode and self:safeComponentAccess(self.components.productionMode, "state", "get")) then
            if self:safeComponentAccess(self.components.callSync[1], "off.hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.camACPR[3], "CameraRouterOutput", "setString", "01")
            elseif self:safeComponentAccess(self.components.callSync[2], "off.hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.camACPR[3], "CameraRouterOutput", "setString", "02")
            end
        end
    else
        -- Default behavior when roomsCombiner is not available
        self:debugPrint("roomsCombiner not available - using default room mode behavior")
    end
end

function SkaarhojCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    
    -- Recalibrate PTZ cameras
    self.cameraModule.recalibratePTZ()
    
    -- Clear camera routing
    self.routingModule.clearRoutes("A")
    self.routingModule.clearRoutes("B")
    
    -- Set initial privacy and button states
    Timer.CallAfter(function()
        self.privacyModule.setCombinedPrivacy(true)
        self.ptzModule.setButtonActive(1, false)
        self.ptzModule.setButtonActive(2, false)
        self.ptzModule.setButtonActive(3, false)
        self.ptzModule.setButtonActive(4, false)
        self.ptzModule.enableRoomAPC()
        self.ptzModule.setCameraLabel(8, "")
        self.ptzModule.disableRoomAPC()
        self.ptzModule.enableRoomBPC()
        self.ptzModule.setCameraLabel(9, "")
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

    -- Get all components and categorize them
    for i, comp in pairs(Component.GetComponents()) do
        -- Skip components that are likely script comments or invalid
        if comp.Name and comp.Name ~= "" and not string.match(comp.Name, "^%s*%-%-") then
            -- Call Sync components
            if comp.Type == "call_sync" then
                table.insert(namesTable.CallSyncNames, comp.Name)
            
            -- Skaarhoj PTZ Controller component
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
            
            -- Room Controls component
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
        self:debugPrint("Set compdevCams choices for " .. #Controls.compdevCams .. " controls")
    else
        self:debugPrint("compdevCams control not found - camera selection will be limited")
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
    self:debugPrint("Registering event handlers...")
    
    -- Component selection handlers
    self:debugPrint("Registering component selection handlers...")
    if Controls.compCallSync then
        for i, callSyncComp in ipairs(Controls.compCallSync) do
            callSyncComp.EventHandler = function()
                self:setCallSyncComponent(i)
            end
        end
        self:debugPrint("Registered " .. #Controls.compCallSync .. " compCallSync handlers")
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
        for i, acprComp in ipairs(Controls.compcamACPR) do
            acprComp.EventHandler = function()
                self:setCamACPRComponent(i)
            end
        end
        self:debugPrint("Registered " .. #Controls.compcamACPR .. " compcamACPR handlers")
    else
        self:debugPrint("WARNING: Controls.compcamACPR not found")
    end

    if Controls.compRoomControls then
        for i, roomControlComp in ipairs(Controls.compRoomControls) do
            roomControlComp.EventHandler = function()
                self:setCompRoomControlsComponent(i)
            end
        end
        self:debugPrint("Registered " .. #Controls.compRoomControls .. " compRoomControls handlers")
    else
        self:debugPrint("WARNING: Controls.compRoomControls not found")
    end
    
    self:debugPrint("Event handler registration completed")
end

--------** Initialization **--------
function SkaarhojCameraController:funcInit()
    self:debugPrint("Starting Skaarhoj Camera Controller initialization...")
    
    -- Error check: Verify Controls exist before proceeding
    local requiredControls = {
        "compCallSync", "compdevSkaarhojPTZ", "compcamRouter", 
        "compdevCams", "compcamACPR", "compRoomControls", "roomName"
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
    
    -- Add btnProductionMode TrackingBypass handler
    if Controls.btnProductionMode then
        Controls.btnProductionMode.EventHandler = function()
            local state = Controls.btnProductionMode.Boolean
            for i, acpr in ipairs(self.components.camACPR) do
                if acpr then
                    self:safeComponentAccess(acpr, "TrackingBypass", "set", state)
                end
            end
            -- Send Button14.press command if skaarhojPTZController exists
            if self.components.skaarhojPTZController then
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button14.press", "set", true)
            end
        end
        -- Set initial state
        Controls.btnProductionMode.EventHandler()
    end
    
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
    
    -- Initialize button states
    self:debugPrint("Initializing button states...")
    initButton(1, 1, 2)
    initButton(2, 3, 2)
    initButton(3, 2, 10)
    initButton(4, 4, 10)
    
    self:debugPrint("Skaarhoj Camera Controller Initialized with " .. self.cameraModule.getCameraCount() .. " cameras")
end

--------** Cleanup **--------
function SkaarhojCameraController:cleanup()
    -- Clear event handlers for all components
    for name, component in pairs(self.components) do
        if type(component) == "table" and component.EventHandler then
            component.EventHandler = nil
        end
    end
    
    self:debugPrint("Cleanup completed for " .. self.roomName)
end

--------** Factory Function **--------
local function createSkaarhojController(roomName, config)
    print("Creating Skaarhoj Camera Controller for: " .. tostring(roomName))
    
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
            monitor = '5',
            usb = '5'
        },
        initializationDelay = 0.1,
        recalibrationDelay = 1.0
    }
    
    local finalConfig = config or defaultConfig
    
    local success, controller = pcall(function()
        print("Creating controller instance...")
        local instance = SkaarhojCameraController.new(roomName, finalConfig)
        print("Controller instance created successfully")
        
        print("Initializing controller...")
        instance:funcInit() -- Initialize after instance creation
        print("Controller initialization completed")
        
        return instance
    end)
    
    if success then
        print("Successfully created Skaarhoj Camera Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        print("Error details: " .. debug.traceback())
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main camera controller instance
print("Starting Skaarhoj Camera Controller script...")

-- Check if required Controls exist
if not Controls.roomName then
    print("ERROR: Controls.roomName not found!")
    return
end

local formattedRoomName = "[" .. Controls.roomName.String .. "]"
print("Room name: " .. formattedRoomName)

mySkaarhojController = createSkaarhojController(formattedRoomName)

if mySkaarhojController then
    print("Skaarhoj Camera Controller created successfully!")
else
    print("ERROR: Failed to create Skaarhoj Camera Controller!")
end

--------** Usage Examples **--------
--[[
-- Example usage of the Skaarhoj Camera Controller:

-- Set privacy for specific room
mySkaarhojController.privacyModule.setRoomAPrivacy(true)
mySkaarhojController.privacyModule.setRoomBPrivacy(false)

-- Set camera routing using consolidated camRouter
-- Monitor outputs: select.1 (Room A), select.2 (Room B)
-- USB outputs: select.3 (Room A), select.4 (Room B)
mySkaarhojController.routingModule.setMonitorRoute(1, "A")  -- Sets select.1
mySkaarhojController.routingModule.setUSBRoute(2, "B")     -- Sets select.4

-- Control PTZ buttons
mySkaarhojController.ptzModule.enableRoomAPC()
mySkaarhojController.ptzModule.disableRoomBPC()

-- Handle hook states
mySkaarhojController.hookStateModule.handleRoomAHookState(true)
mySkaarhojController.hookStateModule.handleRoomBHookState(false)

-- Get camera count
local cameraCount = mySkaarhojController.cameraModule.getCameraCount()

-- Recalibrate PTZ
mySkaarhojController.cameraModule.recalibratePTZ()
]]-- 