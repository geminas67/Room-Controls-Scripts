--[[ 
  Skaarhoj Camera Controller - Modular Version
  Author: Refactored from Q-Sys Block Controller
  February, 2025
  Firmware Req: 9.12
  Version: 2.0
  
  Refactored to follow UCI script pattern for modularity and reusability
  Converted from Q-Sys Block Controller to proper Lua class structure
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
        cameraBlockController = nil,
        skaarhojPTZController = nil,
        productionMode = nil,
        powerStateRmA = nil,
        powerStateRmB = nil,
        cam01 = nil,
        cam02 = nil,
        cameraRouterMON = nil,
        cam03 = nil,
        cam04 = nil,
        cameraRouterUSB = nil,
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
            if room == "A" then
                self:safeComponentAccess(self.components.cam01, "toggle.privacy", "set", state)
                self:safeComponentAccess(self.components.cam03, "toggle.privacy", "set", state)
                self.state.privacyState.roomA = state
            elseif room == "B" then
                self:safeComponentAccess(self.components.cam02, "toggle.privacy", "set", state)
                self:safeComponentAccess(self.components.cam04, "toggle.privacy", "set", state)
                self.state.privacyState.roomB = state
            end
            self:updatePrivacyVisuals()
        end,
        
        setAutoFrame = function(room, state)
            if room == "A" then
                self:safeComponentAccess(self.components.cam01, "autoframe.enable", "set", state)
                self:safeComponentAccess(self.components.cam03, "autoframe.enable", "set", state)
            elseif room == "B" then
                self:safeComponentAccess(self.components.cam02, "autoframe.enable", "set", state)
                self:safeComponentAccess(self.components.cam04, "autoframe.enable", "set", state)
            elseif room == "Combined" then
                self:safeComponentAccess(self.components.cam01, "autoframe.enable", "set", state)
                self:safeComponentAccess(self.components.cam03, "autoframe.enable", "set", state)
                self:safeComponentAccess(self.components.cam02, "autoframe.enable", "set", state)
                self:safeComponentAccess(self.components.cam04, "autoframe.enable", "set", state)
            end
        end,
        
        recalibratePTZ = function()
            self:debugPrint("Starting PTZ recalibration")
            self:safeComponentAccess(self.components.cam01, "ptz.recalibrate", "set", true)
            self:safeComponentAccess(self.components.cam03, "ptz.recalibrate", "set", true)
            self:safeComponentAccess(self.components.cam02, "ptz.recalibrate", "set", true)
            self:safeComponentAccess(self.components.cam04, "ptz.recalibrate", "set", true)
            
            Timer.CallAfter(function()
                self:safeComponentAccess(self.components.cam01, "ptz.recalibrate", "set", false)
                self:safeComponentAccess(self.components.cam03, "ptz.recalibrate", "set", false)
                self:safeComponentAccess(self.components.cam02, "ptz.recalibrate", "set", false)
                self:safeComponentAccess(self.components.cam04, "ptz.recalibrate", "set", false)
                self:debugPrint("PTZ recalibration completed")
            end, self.config.recalibrationDelay)
        end,
        
        getCameraCount = function()
            local count = 0
            if self.components.cam01 then count = count + 1 end
            if self.components.cam02 then count = count + 1 end
            if self.components.cam03 then count = count + 1 end
            if self.components.cam04 then count = count + 1 end
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
    self.routingModule = {
        setMonitorRoute = function(cameraNumber, room)
            if room == "combined" then
                self:safeComponentAccess(self.components.cameraRouterMON, "select.1", "setString", tostring(cameraNumber))
                self:safeComponentAccess(self.components.cameraRouterMON, "select.2", "setString", tostring(cameraNumber))
                self:handleCombinedRouting()
            elseif room == "A" then
                self:safeComponentAccess(self.components.cameraRouterMON, "select.1", "setString", tostring(cameraNumber))
                self:handleRoomARouting()
            elseif room == "B" then
                self:safeComponentAccess(self.components.cameraRouterMON, "select.2", "setString", tostring(cameraNumber))
                self:handleRoomBRouting()
            end
        end,
        
        setUSBRoute = function(cameraNumber, room)
            if room == "A" then
                self:safeComponentAccess(self.components.cameraRouterUSB, "select.1", "setString", tostring(cameraNumber))
            elseif room == "B" then
                self:safeComponentAccess(self.components.cameraRouterUSB, "select.2", "setString", tostring(cameraNumber))
            end
        end,
        
        clearRoutes = function(room)
            if room == "A" then
                self:safeComponentAccess(self.components.cameraRouterMON, "select.1", "setString", self.config.defaultCameraRouterSettings.monitor)
                self:safeComponentAccess(self.components.cameraRouterUSB, "select.1", "setString", self.config.defaultCameraRouterSettings.usb)
            elseif room == "B" then
                self:safeComponentAccess(self.components.cameraRouterMON, "select.2", "setString", self.config.defaultCameraRouterSettings.monitor)
                self:safeComponentAccess(self.components.cameraRouterUSB, "select.2", "setString", self.config.defaultCameraRouterSettings.usb)
            end
        end,
        
        handleCombinedRouting = function()
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk_led_off_hook", "get") then
                self.ptzModule.disableRoomBPC()
                Timer.CallAfter(function()
                    self.ptzModule.enableRoomAPC()
                end, self.config.initializationDelay)
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk_led_off_hook", "get") then
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
    self.ptzModule = {
        enableRoomAPC = function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.headerText", "setString", "Send to PC A")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.color", "setString", self.config.buttonColors.warmWhite)
        end,
        
        disableRoomAPC = function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.headerText", "setString", "")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.screenText", "setString", "")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.controlLink", "setString", "None")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.color", "setString", self.config.buttonColors.buttonOff)
        end,
        
        enableRoomBPC = function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.headerText", "setString", "Send to PC B")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.color", "setString", self.config.buttonColors.warmWhite)
        end,
        
        disableRoomBPC = function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.headerText", "setString", "")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.screenText", "setString", "")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.controlLink", "setString", "None")
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.color", "setString", self.config.buttonColors.buttonOff)
        end,
        
        setButtonActive = function(buttonNumber, active)
            local headerText = active and "Active" or "Preview Mon"
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".headerText", "setString", headerText)
        end,
        
        setCameraLabel = function(buttonNumber, cameraNumber)
            local cameraLabels = {
                ["1"] = "CAM-01",
                ["2"] = "CAM-03", 
                ["3"] = "CAM-02",
                ["4"] = "CAM-04"
            }
            local label = cameraLabels[tostring(cameraNumber)] or ""
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button" .. buttonNumber .. ".screenText", "setString", label)
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
                -- Combined mode
                if isOffHook then
                    self.hookStateModule.setCombinedHookState(true)
                    self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "01")
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", false)
                else
                    self.hookStateModule.setCombinedHookState(false)
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button15.press", "set", true)
                end
            elseif self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode
                if isOffHook then
                    self.hookStateModule.setCombinedHookState(false)
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
                -- Combined mode
                if isOffHook then
                    self.hookStateModule.setCombinedHookState(true)
                    self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "02")
                    self:debugPrint("Combine - Privacy OFF")
                else
                    self.hookStateModule.setCombinedHookState(false)
                    self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "set", true)
                    self:debugPrint("Combine - Privacy ON")
                end
            elseif self:safeComponentAccess(self.components.roomsCombiner, "load.1", "get") then
                -- Divided mode
                if isOffHook then
                    self.hookStateModule.setCombinedHookState(false)
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
    -- Setup all components
    self.components.hidConferencingTRNVH01 = self:setComponent(Controls.compHIDConferencingTRNVH01, "HID Conferencing TR-NVH-01")
    self.components.hidConferencingTRNVH02 = self:setComponent(Controls.compHIDConferencingTRNVH02, "HID Conferencing TR-NVH-02")
    self.components.acprRmB = self:setComponent(Controls.compACPRRmB, "ACPR Rm-B")
    self.components.acprRmA = self:setComponent(Controls.compACPRRmA, "ACPR Rm-A")
    self.components.acprCombined = self:setComponent(Controls.compACPRCombined, "ACPR Combined")
    self.components.roomsCombiner = self:setComponent(Controls.compRoomsCombiner, "Rooms Combiner")
    self.components.cameraBlockController = self:setComponent(Controls.compCameraBlockController, "Camera Block Controller")
    self.components.skaarhojPTZController = self:setComponent(Controls.compSkaarhojPTZController, "Skaarhoj PTZ Controller")
    self.components.productionMode = self:setComponent(Controls.compProductionMode, "Production Mode")
    self.components.powerStateRmA = self:setComponent(Controls.compPowerStateRmA, "Power State Rm-A")
    self.components.powerStateRmB = self:setComponent(Controls.compPowerStateRmB, "Power State Rm-B")
    self.components.cam01 = self:setComponent(Controls.compCAM01, "CAM-01")
    self.components.cam02 = self:setComponent(Controls.compCAM02, "CAM-02")
    self.components.cameraRouterMON = self:setComponent(Controls.compCameraRouterMON, "Camera Router MON")
    self.components.cam03 = self:setComponent(Controls.compCAM03, "CAM-03")
    self.components.cam04 = self:setComponent(Controls.compCAM04, "CAM-04")
    self.components.cameraRouterUSB = self:setComponent(Controls.compCameraRouterUSB, "Camera Router USB")
end

--------** Helper Functions **--------
function SkaarhojCameraController:updatePrivacyVisuals()
    self.privacyModule.updatePrivacyButton()
end

function SkaarhojCameraController:setLabelOfCameraSentToPC()
    local cameraNumber = self:safeComponentAccess(self.components.cameraRouterUSB, "select.1", "getString")
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
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk_led_off_hook", "get") then
                self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "set", false)
                self:safeComponentAccess(self.components.acprRmA, "CameraRouterOutput", "setString", "01")
                self.privacyModule.setRoomAPrivacy(false)
                self.privacyModule.setRoomBPrivacy(true)
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk_led_off_hook", "get") then
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
            if self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk_led_off_hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "01")
            elseif self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk_led_off_hook", "get") then
                self.hookStateModule.setCombinedHookState(true)
                self:safeComponentAccess(self.components.acprCombined, "CameraRouterOutput", "setString", "02")
            end
        end
    end
end

--------** Event Handler Registration **--------
function SkaarhojCameraController:registerEventHandlers()
    -- Hook state handlers
    if self.components.hidConferencingTRNVH01 then
        self.components.hidConferencingTRNVH01["spk_led_off_hook"].EventHandler = function()
            self.hookStateModule.handleRoomAHookState(
                self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk_led_off_hook", "get")
            )
        end
    end
    
    if self.components.hidConferencingTRNVH02 then
        self.components.hidConferencingTRNVH02["spk_led_off_hook"].EventHandler = function()
            self.hookStateModule.handleRoomBHookState(
                self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk_led_off_hook", "get")
            )
        end
    end
    
    -- ACPR tracking bypass handlers
    if self.components.acprRmB then
        self.components.acprRmB["TrackingBypass"].EventHandler = function()
            local bypassState = self:safeComponentAccess(self.components.acprRmB, "TrackingBypass", "get")
            self.cameraModule.setAutoFrame("B", not bypassState)
        end
    end
    
    if self.components.acprRmA then
        self.components.acprRmA["TrackingBypass"].EventHandler = function()
            local bypassState = self:safeComponentAccess(self.components.acprRmA, "TrackingBypass", "get")
            self.cameraModule.setAutoFrame("A", not bypassState)
        end
    end
    
    if self.components.acprCombined then
        self.components.acprCombined["TrackingBypass"].EventHandler = function()
            local bypassState = self:safeComponentAccess(self.components.acprCombined, "TrackingBypass", "get")
            self.cameraModule.setAutoFrame("Combined", not bypassState)
            self:debugPrint(bypassState and "Combined Auto Framing Enabled" or "Combined Auto Framing Disabled")
        end
    end
    
    -- Room mode change handlers
    if self.components.roomsCombiner then
        self.components.roomsCombiner["load.1"].EventHandler = function()
            self:handleRoomModeChange()
        end
        
        self.components.roomsCombiner["load.2"].EventHandler = function()
            self:handleRoomModeChange()
        end
    end
    
    -- Combined hook state handler
    if self.components.cameraBlockController then
        self.components.cameraBlockController["Combined Hook State"].EventHandler = function()
            self.hookStateModule.setCombinedHookState(
                self:safeComponentAccess(self.components.cameraBlockController, "Combined Hook State", "get")
            )
        end
    end
    
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
                if isPressed and self:safeComponentAccess(self.components.hidConferencingTRNVH01, "spk_led_off_hook", "get") then
                    self.ptzModule.enableRoomAPC()
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button8.color", "setString", self.config.buttonColors.purple)
                    
                    local monitorRoute = self:safeComponentAccess(self.components.cameraRouterMON, "select.1", "getString")
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
                if isPressed and self:safeComponentAccess(self.components.hidConferencingTRNVH02, "spk_led_off_hook", "get") then
                    self.ptzModule.enableRoomBPC()
                    self:safeComponentAccess(self.components.skaarhojPTZController, "Button9.color", "setString", self.config.buttonColors.purple)
                    
                    local monitorRoute = self:safeComponentAccess(self.components.cameraRouterMON, "select.2", "getString")
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
    if self.components.powerStateRmA then
        self.components.powerStateRmA["selector"].EventHandler = function()
            if self:safeComponentAccess(self.components.powerStateRmA, "selector_0", "get") then
                self.routingModule.clearRoutes("A")
            end
        end
    end
    
    if self.components.powerStateRmB then
        self.components.powerStateRmB["selector"].EventHandler = function()
            if self:safeComponentAccess(self.components.powerStateRmB, "selector_0", "get") then
                self.routingModule.clearRoutes("B")
            end
        end
    end
end

--------** Initialization **--------
function SkaarhojCameraController:funcInit()
    self:debugPrint("Starting Skaarhoj Camera Controller initialization")
    
    -- Setup components
    self:setupComponents()
    self:registerEventHandlers()
    
    -- Perform system initialization
    self:performSystemInitialization()
    
    self:debugPrint("Skaarhoj Camera Controller initialization completed")
end

function SkaarhojCameraController:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    
    -- Recalibrate PTZ cameras
    self.cameraModule.recalibratePTZ()
    
    -- Clear camera routing
    self.routingModule.clearRoutes("A")
    self.routingModule.clearRoutes("B")
    
    -- Initialize button states and privacy
    Timer.CallAfter(function()
        self:debugPrint("Setting up initial button states and privacy")
        
        -- Set privacy on for all cameras initially
        self.privacyModule.setCombinedPrivacy(true)
        
        -- Reset button states
        self.ptzModule.setButtonActive(1, false)
        self.ptzModule.setButtonActive(2, false)
        self.ptzModule.setButtonActive(3, false)
        self.ptzModule.setButtonActive(4, false)
        
        -- Initialize PC send buttons
        self.ptzModule.enableRoomAPC()
        self.ptzModule.setCameraLabel(8, "")
        self.ptzModule.disableRoomAPC()
        
        self.ptzModule.enableRoomBPC()
        self.ptzModule.setCameraLabel(9, "")
        self.ptzModule.disableRoomBPC()
        
        -- Set up button control links and headers
        Timer.CallAfter(function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button1.controlLink", "setString", "Camera 1")
            Timer.CallAfter(function()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button1.headerText", "setString", "Preview Mon")
            end, self.config.initializationDelay * 2)
        end, self.config.initializationDelay * 2)
        
        Timer.CallAfter(function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button2.controlLink", "setString", "Camera 3")
            Timer.CallAfter(function()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button2.headerText", "setString", "Preview Mon")
            end, self.config.initializationDelay * 2)
        end, self.config.initializationDelay * 2)
        
        Timer.CallAfter(function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button3.controlLink", "setString", "Camera 2")
            Timer.CallAfter(function()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button3.headerText", "setString", "Preview Mon")
            end, self.config.initializationDelay * 10)
        end, self.config.initializationDelay * 2)
        
        Timer.CallAfter(function()
            self:safeComponentAccess(self.components.skaarhojPTZController, "Button4.controlLink", "setString", "Camera 4")
            Timer.CallAfter(function()
                self:safeComponentAccess(self.components.skaarhojPTZController, "Button4.headerText", "setString", "Preview Mon")
            end, self.config.initializationDelay * 10)
        end, self.config.initializationDelay * 2)
        
        self:debugPrint("Initialization sequence completed with " .. self.cameraModule.getCameraCount() .. " cameras")
    end, self.config.recalibrationDelay)
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

-- Set camera routing
mySkaarhojController.routingModule.setMonitorRoute(1, "A")
mySkaarhojController.routingModule.setUSBRoute(2, "B")

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
