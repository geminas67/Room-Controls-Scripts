--[[ 
  Skaarhoj Camera Controller - Modular Version
  Author: Refactored from Q-Sys Block Controller
  2025-06-18
  Firmware Req: 10.0.0
  Version: 1.1
  
  Refactored to follow UCI script pattern for modularity and reusability
  Converted from Q-Sys Block Controller to proper Lua class structure
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
    
    -- Component storage
    self.components = {
        hidConferencingTRNVH01 = nil,
        hidConferencingTRNVH02 = nil,
        acprRmB = nil,
        acprRmA = nil,
        acprCombined = nil,
        roomsCombiner = nil,
        skaarhojPTZController = nil,
        productionMode = nil,
        powerStateRmA = nil,
        powerStateRmB = nil,
        cam01 = nil,
        cam02 = nil,
        camRouter = nil,
        cam03 = nil,
        cam04 = nil,
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
    
    -- Setup event handlers and initialize
    self:registerEventHandlers()
    self:funcInit()
    
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
                cameras = {self.components.cam01, self.components.cam03}
                self.state.privacyState.roomA = state
            elseif room == "B" then
                cameras = {self.components.cam02, self.components.cam04}
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
                cameras = {self.components.cam01, self.components.cam03}
            elseif room == "B" then
                cameras = {self.components.cam02, self.components.cam04}
            elseif room == "Combined" then
                cameras = {self.components.cam01, self.components.cam03, self.components.cam02, self.components.cam04}
            end
            
            for _, camera in ipairs(cameras) do
                self:safeComponentAccess(camera, "autoframe.enable", "set", state)
            end
        end,
        
        recalibratePTZ = function()
            local cameras = {self.components.cam01, self.components.cam03, self.components.cam02, self.components.cam04}
            
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
            local cameras = {self.components.cam01, self.components.cam02, self.components.cam03, self.components.cam04}
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
-- Consolidated Camera Router Control Scheme:
-- select.1 = Monitor Output Room A
-- select.2 = Monitor Output Room B  
-- select.3 = USB Output Room A
-- select.4 = USB Output Room B
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
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk.led.off.hook", "get") then
                self.ptzModule.disableRoomBPC()
                Timer.CallAfter(function()
                    self.ptzModule.enableRoomAPC()
                end, self.config.initializationDelay)
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk.led.off.hook", "get") then
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
-- Hook State Logic:
-- Combined Mode (roomsCombiner["load.2"].Boolean): Execute setCombinedHookState per callSync["off.hook"].(state)
-- Divided Mode (roomsCombiner["load.1"].Boolean): Execute individual room hook state per callSync["off.hook"].(state)
function SkaarhojCameraController:initHookStateModule()
    self.hookStateModule = {
        setCombinedHookState = function(state)
            self.state.combinedHookState = state
            if state then
    -- Combined - Off Hook - Privacy Off
                self.ptzModule.enableRoomAPC()
                self.privacyModule.setCombinedPrivacy(false)
                if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", false)
                end
                self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "set", true)
                self:safeComponentAccess(self.components.acprRmB, "TrackingBypass", "set", true)
   else
    -- Combined - On Hook - Privacy On
                self.ptzModule.disableRoomAPC()
                self.ptzModule.disableRoomBPC()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.controlLink", "setString", "None")
                self.privacyModule.setCombinedPrivacy(true)
    Timer.CallAfter(function()
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                end, self.config.initializationDelay * 2)
            end
        end,
        
        handleRoomAHookState = function(isOffHook)
            if self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
                -- Combined mode: Execute setCombinedHookState per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(isOffHook)
                if isOffHook then
                    self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "01")
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", false)
                else
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", true)
                end
            elseif self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode: Execute individual room hook state per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(false)
                if isOffHook then
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self.ptzModule.enableRoomAPC()
                    if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
                        self:safeComponentAccess(self.components.acprRmA, "CameraRouterOutput", "setString", "01")
                        self.privacyModule.setRoomAPrivacy(false)
                    end
                else
                    self.ptzModule.disableRoomAPC()
                    self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "set", true)
                    self.privacyModule.setRoomAPrivacy(true)
  end
end
        end,
        
        handleRoomBHookState = function(isOffHook)
            if self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
                -- Combined mode: Execute setCombinedHookState per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(isOffHook)
                if isOffHook then
                    self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "02")
                    self:debugPrint("Combine - Privacy OFF")
                else
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self:debugPrint("Combine - Privacy ON")
                end
            elseif self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode: Execute individual room hook state per callSync["off.hook"].(state)
                self.hookStateModule.setCombinedHookState(false)
                if isOffHook then
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self.ptzModule.enableRoomBPC()
                    if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
                        self:safeComponentAccess(self.components.acprRmB, "CameraRouterOutput", "setString", "02")
                        self.privacyModule.setRoomBPrivacy(false)
      end
     else
                    self.ptzModule.disableRoomBPC()
                    self:safeComponentAccess(self.components.acprRmB, "TrackingBypass", "set", true)
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
function SkaarhojCameraController:setupComponents()
    -- Helper function to setup a component
    local function setupComponent(control, componentType)
        self.components[control] = self:setComponent(Controls[control], componentType)
    end
    
    -- Setup all components
    setupComponent("hidConferencingTRNVH01", "HID Conferencing TR-NVH-01")
    setupComponent("hidConferencingTRNVH02", "HID Conferencing TR-NVH-02")
    setupComponent("acprRmB", "ACPR Rm-B")
    setupComponent("acprRmA", "ACPR Rm-A")
    setupComponent("acprCombined", "ACPR Combined")
    setupComponent("roomsCombiner", "Rooms Combiner")
    setupComponent("skaarhojPTZController", "Skaarhoj PTZ Controller")
    setupComponent("productionMode", "Production Mode")
    setupComponent("powerStateRmA", "Power State Rm-A")
    setupComponent("powerStateRmB", "Power State Rm-B")
    setupComponent("cam01", "CAM-01")
    setupComponent("cam02", "CAM-02")
    setupComponent("camRouter", "Camera Router")
    setupComponent("cam03", "CAM-03")
    setupComponent("cam04", "CAM-04")
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
    
    if self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
        -- Divided mode
        self.hookStateModule.setCombinedHookState(false)
        self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
        
        if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk.led.off.hook", "get") then
                self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "set", false)
                self:safeComponentAccess(self.components.acprRmA, "CameraRouterOutput", "setString", "01")
                self.privacyModule.setRoomAPrivacy(false)
                self.privacyModule.setRoomBPrivacy(true)
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk.led.off.hook", "get") then
                self:safeComponentAccess(self.components.acprRmB, "TrackingBypass", "set", false)
                self:safeComponentAccess(self.components.acprRmB, "CameraRouterOutput", "setString", "02")
                self.privacyModule.setRoomBPrivacy(false)
                self.privacyModule.setRoomAPrivacy(true)
  end
end
    elseif self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
        -- Combined mode
        self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "set", true)
        self:safeComponentAccess(self.components.acprRmB, "TrackingBypass", "set", true)
        
        if not self:safeComponentAccess(self.components.productionMode, "state", "get") then
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk.led.off.hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "01")
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk.led.off.hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "02")
      end
    end
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

function SkaarhojCameraController:funcInit()
    self:setupComponents()
    self:registerEventHandlers()
    
    -- Perform system initialization
    self:performSystemInitialization()
    
    -- Helper function to initialize button with delay
    local function initButton(buttonNumber, cameraNumber, delayMultiplier)
        local delay = self.config.initializationDelay * (delayMultiplier or 2)
        Timer.CallAfter(function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".controlLink", "setString", "Camera " .. cameraNumber)
    Timer.CallAfter(function()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".headerText", "setString", "Preview Mon")
            end, delay)
        end, delay)
    end
    
    -- Initialize button states
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
        return SkaarhojCameraController.new(roomName, finalConfig)
    end)
    
    if success then
        print("Successfully created Skaarhoj Camera Controller for " .. roomName)
        return controller
    else
        print("Failed to create controller for " .. roomName .. ": " .. tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Create the main camera controller instance
local formattedRoomName = "[" .. Controls.roomName.String .. "]"
mySkaarhojController = createSkaarhojController(formattedRoomName)

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

--------** Event Handler Registration **--------
function SkaarhojCameraController:registerEventHandlers()
    -- Helper function to register hook state handler
    local function registerHookHandler(component, room)
        if component then
            component["spk.led.off.hook"].EventHandler = function()
                local hookState = self:safeComponentAccess(component, "spk.led.off.hook", "get")
                if room == "A" then
                    self.hookStateModule.handleRoomAHookState(hookState)
                else
                    self.hookStateModule.handleRoomBHookState(hookState)
      end
    end
  end
end
    
    -- Helper function to register ACPR tracking bypass handler
    local function registerACPRHandler(component, room)
        if component then
            component["TrackingBypass"].EventHandler = function()
                local bypassState = self:safeComponentAccess(component, "TrackingBypass", "get")
                self.cameraModule.setAutoFrame(room, not bypassState)
                if room == "Combined" then
                    self:debugPrint(bypassState and "Combined Auto Framing Enabled" or "Combined Auto Framing Disabled")
                end
  end
end
    end
    
    -- Helper function to register room mode change handler
    local function registerRoomModeHandler(loadNumber)
        if self.components.roomsCombiner then
            self.components.roomsCombiner["load." .. loadNumber].EventHandler = function()
                self:handleRoomModeChange()
  end
end
    end
    
    -- Helper function to register power state handler
    local function registerPowerStateHandler(component, room)
        if component then
            component["selector"].EventHandler = function()
                if self:safeComponentAccess(component, "selector_0", "get") then
                    self.routingModule.clearRoutes(room)
                end
  end
end
    end
    
    -- Hook state handlers
    registerHookHandler(self.components.hidConferencingTRNVH01, "A")
    registerHookHandler(self.components.hidConferencingTRNVH02, "B")
    
    -- ACPR tracking bypass handlers
    registerACPRHandler(self.components.acprRmB, "B")
    registerACPRHandler(self.components.acprRmA, "A")
    registerACPRHandler(self.components.acprCombined, "Combined")
    
    -- Room mode change handlers
    registerRoomModeHandler(1)
    registerRoomModeHandler(2)
    
    -- PTZ button handlers
    if self.components.skaarhojPTZController then
        -- Camera selection buttons
        for i = 1, 4 do
            local buttonPress = self.components.skaarhojPTZController["Button" .. i .. ".press"]
            if buttonPress then
                buttonPress.EventHandler = function()
                    local isPressed = self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. i .. ".press", "get")
                    self.ptzModule.setButtonActive(i, isPressed)
                    
                    if isPressed then
                        if self:safeComponentAccess(self.components.roomsCombiner, "load.2", "get") then
                            -- Combined mode
                            self.routingModule.setMonitorRoute(i, "combined")
                        else
                            -- Divided mode
                            if i <= 2 then
                                self.routingModule.setMonitorRoute(i, "A")
                            else
                                self.routingModule.setMonitorRoute(i, "B")
  end
end
                    end
    end
  end
end
        
        -- PC send buttons
        local button8Press = self.components.skaarhojPTZController["Button8.press"]
        if button8Press then
            button8Press.EventHandler = function()
                local isPressed = self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.press", "get")
                if isPressed and self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk.led.off.hook", "get") then
                    self.ptzModule.enableRoomAPC()
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.color", "setString", self.config.buttonColors.purple)
                    
                    local monitorRoute = self:safeComponentAccess(self.components.camRouter, "select.1", "getString")
                    self.routingModule.setUSBRoute(monitorRoute, "A")
                    self.ptzModule.setCameraLabel(8, monitorRoute)
                else
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.color", "setString", self.config.buttonColors.buttonOff)
                    self.ptzModule.disableRoomAPC()
                end
  end
end
        
        local button9Press = self.components.skaarhojPTZController["Button9.press"]
        if button9Press then
            button9Press.EventHandler = function()
                local isPressed = self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.press", "get")
                if isPressed and self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk.led.off.hook", "get") then
                    self.ptzModule.enableRoomBPC()
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.color", "setString", self.config.buttonColors.purple)
                    
                    local monitorRoute = self:safeComponentAccess(self.components.camRouter, "select.2", "getString")
                    self.routingModule.setUSBRoute(monitorRoute, "B")
                    self.ptzModule.setCameraLabel(9, monitorRoute)
                else
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.color", "setString", self.config.buttonColors.buttonOff)
                    self.ptzModule.disableRoomBPC()
                end
  end
end
        
        -- Privacy button
        local button6ScreenText = self.components.skaarhojPTZController["Button6.screenText"]
        if button6ScreenText then
            button6ScreenText.EventHandler = function()
                self:updatePrivacyVisuals()
            end
        end
    end
    
    -- Production mode handler
    if self.components.productionMode then
        self.components.productionMode["state"].EventHandler = function()
            self:setLabelOfCameraSentToPC()
  end
end
    
    -- Power state handlers
    registerPowerStateHandler(self.components.powerStateRmA, "A")
    registerPowerStateHandler(self.components.powerStateRmB, "B")
end

--------** Initialization **-------- 