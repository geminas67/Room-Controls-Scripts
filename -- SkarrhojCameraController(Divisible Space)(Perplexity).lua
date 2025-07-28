--[[ 
  Skaarhoj Camera Controller - Divisible Space Version (Performance Optimized)
  Author: Perplexity AI (Refactored for Performance)
  2025-07-27
  Firmware Req: 10.0.0
  Requires: QSysControllerUtilities
  Version: 2.1
  ]]--

-----------------[ Load Utility Module ]-------------------
local QSysUtilities = require("QSysControllerUtilities")

-----------------[ Class Definition ]-------------------
SkaarhojPTZControllerMultiRoom = {}
SkaarhojPTZControllerMultiRoom.__index = SkaarhojPTZControllerMultiRoom

-----------------[ Global Config and Labels ]-------------------
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
        monitorA = '6',
        monitorB = '6',
        usbA = '6',
        usbB = '6'
    },
    initializationDelay = 0.1,
    recalibrationDelay = 1.0
}

local cameraLabels = {
    ["1"] = "Cam01", -- Room A
    ["2"] = "Cam02", -- Room B
    ["3"] = "Cam03", -- Room A
    ["4"] = "Cam04" -- Room B
}

-----------------[ Class Constructor ]-------------------
function SkaarhojPTZControllerMultiRoom.new(roomName, config)
    local self = setmetatable({}, SkaarhojPTZControllerMultiRoom)
    self.roomName = roomName or "Divisible Space"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    -- Device Component types (Q-SYS plugin IDs or types)
    self.componentTypes = {
        callSync = "call_sync",
        skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
        camRouter = "video_router",
        devCams = "onvif_camera_operative",
        camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
        roomControls = "device_controller_script"
    }

    self.components = {
        callSync = {}, -- Rm-A [1], Rm-B [2]
        skaarhojPTZController = nil, 
        camRouter = nil, 
        devCams = {}, -- cam01, cam02, cam03, cam04
        camACPR = {}, -- Rm-A [1], Rm-B [2], Combined [3]
        compRoomControls = {}, -- Rm-A [1], Rm-B [2]
        productionMode = nil,
        roomsCombiner = nil,
        invalid = {}
    }
    
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

    self.config = config or defaultConfig
    self.cameraLabels = cameraLabels

    -- Inject shared utility methods (QSysControllerUtilities)
    for k, v in pairs(QSysUtilities) do self[k] = v end
    QSysUtilities.injectAccessors(self)

    return self
end

-----------------[ Camera Logic ]-------------------
function SkaarhojPTZControllerMultiRoom:setPrivacy(room, state)
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
        if camera then 
            self:setComponentBoolean(camera, "toggle.privacy", state) 
        end
    end
    
    self:updatePrivacyButton()
end

function SkaarhojPTZControllerMultiRoom:setAutoFrame(room, state)
    local cameras = {}
    
    if room == "A" then
        cameras = {self.components.devCams[1], self.components.devCams[3]}
    elseif room == "B" then
        cameras = {self.components.devCams[2], self.components.devCams[4]}
    elseif room == "Combined" then
        cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
    end
    
    for _, camera in ipairs(cameras) do
        if camera then 
            self:setComponentBoolean(camera, "autoframe.enable", state) 
        end
    end
end

function SkaarhojPTZControllerMultiRoom:recalibratePTZ()
    local cameras = {self.components.devCams[1], self.components.devCams[3], self.components.devCams[2], self.components.devCams[4]}
    
    for _, camera in ipairs(cameras) do
        if camera then 
            self:triggerComponent(camera, "ptz.recalibrate") 
        end
    end
    
    -- self:runDelayed(self.config.recalibrationDelay, function()
    --     for _, camera in ipairs(cameras) do
    --         if camera then 
    --             self:setComponentBoolean(camera, "ptz.recalibrate", false) 
    --         end
    --     end
    -- end)
end

function SkaarhojPTZControllerMultiRoom:getCameraCount()
    local cameras = {self.components.devCams[1], self.components.devCams[2], self.components.devCams[3], self.components.devCams[4]}
    local count = 0
    for _, camera in ipairs(cameras) do
        if camera then count = count + 1 end
    end
    return count
end

-----------------[ Privacy Operations ]-------------------
function SkaarhojPTZControllerMultiRoom:updatePrivacyButton()
    local privacyActive = self.state.privacyState.roomA or self.state.privacyState.roomB
    local color = privacyActive and self.config.buttonColors.red or self.config.buttonColors.buttonOff
    self:setComponentProperty(self.components.skaarhojPTZController, "Button6.color", color)
end

-----------------[ Router Operations ]-------------------
function SkaarhojPTZControllerMultiRoom:setRouterOutput(outputNumber, cameraNumber)
    self:setComponentProperty(self.components.camRouter, "select."..outputNumber, tostring(cameraNumber))
end

function SkaarhojPTZControllerMultiRoom:clearRoomRoutes(room)
    if room == "A" then
        self:setRouterOutput(1, self.config.defaultCameraRouterSettings.monitorA)
        self:setRouterOutput(3, self.config.defaultCameraRouterSettings.usbA)
    elseif room == "B" then
        self:setRouterOutput(2, self.config.defaultCameraRouterSettings.monitorB)
        self:setRouterOutput(4, self.config.defaultCameraRouterSettings.usbB)
    end
end

function SkaarhojPTZControllerMultiRoom:setMonitorRoute(cameraNumber, room)
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

function SkaarhojPTZControllerMultiRoom:setUSBRoute(cameraNumber, room)
    if room == "A" then
        self:setRouterOutput(3, cameraNumber)
    elseif room == "B" then
        self:setRouterOutput(4, cameraNumber)
    end
end

function SkaarhojPTZControllerMultiRoom:handleCombinedRouting()
    if self:getComponentBoolean(self.components.callSync[1], "off.hook") then
        self:disableRoomBPC()
        self:runDelayed(self.config.initializationDelay, function()
            self:enableRoomAPC()
        end)
    elseif self:getComponentBoolean(self.components.callSync[2], "off.hook") then
        self:disableRoomAPC()
        self:runDelayed(self.config.initializationDelay, function()
            self:enableRoomBPC()
        end)
    end
end

function SkaarhojPTZControllerMultiRoom:handleRoomARouting()
    self:disableRoomBPC()
    self:enableRoomAPC()
end

function SkaarhojPTZControllerMultiRoom:handleRoomBRouting()
    self:disableRoomAPC()
    self:enableRoomBPC()
end

-----------------[ PTZ Controller Operations ]-------------------
function SkaarhojPTZControllerMultiRoom:setMultipleButtonProperties(buttonNum, props)
    local base = self.components.skaarhojPTZController
    if not base then return end
    for key, value in pairs(props) do
        self:setComponentProperty(base, "Button" .. buttonNum .. "." .. key, value)
    end
end

function SkaarhojPTZControllerMultiRoom:setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
    local props = {}
    if headerText  then props.headerText = headerText end
    if screenText  then props.screenText = screenText end
    if controlLink then props.controlLink = controlLink end
    if color       then props.color = color end
    self:setMultipleButtonProperties(buttonNumber, props)
end

function SkaarhojPTZControllerMultiRoom:enableRoomAPC()
    if self.state.buttonStates.roomAPCEnabled then return end
    self:setButtonProperties(8, "Send to PC A", nil, nil, self.config.buttonColors.warmWhite)
    self.state.buttonStates.roomAPCEnabled = true
    self:debugPrint("Enabled Room A PC")
end

function SkaarhojPTZControllerMultiRoom:disableRoomAPC()
    if not self.state.buttonStates.roomAPCEnabled then return end
    self:setButtonProperties(8, "", "", "None", self.config.buttonColors.buttonOff)
    self.state.buttonStates.roomAPCEnabled = false
    self:debugPrint("Disabled Room A PC")
end

function SkaarhojPTZControllerMultiRoom:enableRoomBPC()
    if self.state.buttonStates.roomBPCEnabled then return end
    self:setButtonProperties(9, "Send to PC B", nil, nil, self.config.buttonColors.warmWhite)
    self.state.buttonStates.roomBPCEnabled = true
    self:debugPrint("Enabled Room B PC")
end

function SkaarhojPTZControllerMultiRoom:disableRoomBPC()
    if not self.state.buttonStates.roomBPCEnabled then return end
    self:setButtonProperties(9, "", "", "None", self.config.buttonColors.buttonOff)
    self.state.buttonStates.roomBPCEnabled = false
    self:debugPrint("Disabled Room B PC")
end

function SkaarhojPTZControllerMultiRoom:setButtonActive(buttonNumber, active)
    if self.state.buttonStates.activeButton == buttonNumber and active then return end
    if not active and self.state.buttonStates.activeButton ~= buttonNumber then return end
    
    local headerText = active and "Active" or "Preview Mon"
    self:setButtonProperties(buttonNumber, headerText)
    self.state.buttonStates.activeButton = active and buttonNumber or 0
    self:debugPrint("Set Button"..buttonNumber.." to "..(active and "Active" or "Preview Mon"))
end

function SkaarhojPTZControllerMultiRoom:setCameraLabel(buttonNumber, cameraNumber)
    local label = self.cameraLabels[tostring(cameraNumber)] or ""
    self:setButtonProperties(buttonNumber, nil, label)
    self:debugPrint("Set Button"..buttonNumber.." to "..label)
end

-----------------[ Hook State Operations ]-------------------
function SkaarhojPTZControllerMultiRoom:setCombinedHookState(state)
    if self.state.combinedHookState == state then return end
    self.state.combinedHookState = state
    
    if state then
        -- Combined - Off Hook - Privacy Off
        self:enableRoomAPC()
        self:setPrivacy("Combined", false)
        if not self:getComponentBoolean(self.components.productionMode, "state") then
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", false)
        end
        self:setComponentBoolean(self.components.compRoomControls[1], "TrackingBypass", true)
        self:setComponentBoolean(self.components.compRoomControls[2], "TrackingBypass", true)
    else
        -- Combined - On Hook - Privacy On
        self:disableRoomAPC()
        self:disableRoomBPC()
        self:setComponentProperty(self.components.skaarhojPTZController, "Button9.controlLink", "None")
        self:setPrivacy("Combined", true)
        self:runDelayed(self.config.initializationDelay * 2, function()
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
        end)
    end
end

function SkaarhojPTZControllerMultiRoom:handleRoomAHookState(isOffHook)
    if not self.components.roomsCombiner then
        -- Default behavior when roomsCombiner is not available
        self:debugPrint("roomsCombiner not available - using default hook state behavior")
        if isOffHook then
            self:enableRoomAPC()
            self:setPrivacy("A", false)
        else
            self:disableRoomAPC()
            self:setPrivacy("A", true)
        end
        return
    end
    
    if self:getComponentBoolean(self.components.roomsCombiner, "load.2") then
        -- Combined mode
        self:setCombinedHookState(isOffHook)
        if isOffHook then
            self:setComponentProperty(self.components.camACPR[3], "CameraRouterOutput", "01")
            self:setComponentBoolean(self.components.skaarhojPTZController, "Button15.press", false)
        else
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
            self:setComponentBoolean(self.components.skaarhojPTZController, "Button15.press", true)
        end
    elseif self:getComponentBoolean(self.components.roomsCombiner, "load.1") then
        -- Divided mode
        self:setCombinedHookState(false)
        if isOffHook then
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
            self:enableRoomAPC()
            if not self:getComponentBoolean(self.components.productionMode, "state") then
                self:setComponentProperty(self.components.compRoomControls[1], "CameraRouterOutput", "01")
                self:setPrivacy("A", false)
            end
        else
            self:disableRoomAPC()
            self:setComponentBoolean(self.components.compRoomControls[1], "TrackingBypass", true)
            self:setPrivacy("A", true)
        end
    end
end

function SkaarhojPTZControllerMultiRoom:handleRoomBHookState(isOffHook)
    if not self.components.roomsCombiner then
        -- Default behavior when roomsCombiner is not available
        self:debugPrint("roomsCombiner not available - using default hook state behavior")
        if isOffHook then
            self:enableRoomBPC()
            self:setPrivacy("B", false)
        else
            self:disableRoomBPC()
            self:setPrivacy("B", true)
        end
        return
    end
    
    if self:getComponentBoolean(self.components.roomsCombiner, "load.2") then
        -- Combined mode
        self:setCombinedHookState(isOffHook)
        if isOffHook then
            self:setComponentProperty(self.components.camACPR[3], "CameraRouterOutput", "02")
            self:debugPrint("Combine - Privacy OFF")
        else
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
            self:debugPrint("Combine - Privacy ON")
        end
    elseif self:getComponentBoolean(self.components.roomsCombiner, "load.1") then
        -- Divided mode
        self:setCombinedHookState(false)
        if isOffHook then
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
            self:enableRoomBPC()
            if not self:getComponentBoolean(self.components.productionMode, "state") then
                self:setComponentProperty(self.components.compRoomControls[2], "CameraRouterOutput", "02")
                self:setPrivacy("B", false)
            end
        else
            self:disableRoomBPC()
            self:setComponentBoolean(self.components.compRoomControls[2], "TrackingBypass", true)
            self:setPrivacy("B", true)
        end
    end
end

-----------------[ Component Setup ]-------------------
function SkaarhojPTZControllerMultiRoom:setDevCamComponent(idx)
    if not Controls.compdevCams or not Controls.compdevCams[idx] then return end
    
    local cameraLabels = {[1] = "Cam01", [2] = "Cam02", [3] = "Cam03", [4] = "Cam04"}
    self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], cameraLabels[idx])
end

function SkaarhojPTZControllerMultiRoom:setupComponents()
    local steps = {
        function() self:setCallSyncComponent() end,
        function() self:setSkaarhojPTZComponent() end,
        function() self:setCamRouterComponent() end,
        function() self:setCamACPRComponent() end,
        function() self:setCompRoomControlsComponent() end,
        function()
            if Controls.compdevCams then
                for i = 1, 4 do 
                    self:setDevCamComponent(i) 
                end
            end
        end
    }
    self:runInitializers(steps)
    self:registerComponentEventHandlers()
end

function SkaarhojPTZControllerMultiRoom:setCallSyncComponent()
    for i = 1, 2 do
        if not Controls.compCallSync or not Controls.compCallSync[i] then
            goto continue
        end
        
        local roomLabel = i == 1 and "Rm-A" or "Rm-B"
        local componentType = "Call Sync " .. roomLabel
        self.components.callSync[i] = self:setComponent(Controls.compCallSync[i], componentType)
        
        if self.components.callSync[i] then
            self.components.callSync[i]["off.hook"].EventHandler = function()
                local hookState = self:getComponentBoolean(self.components.callSync[i], "off.hook")
                if i == 1 then
                    self:handleRoomAHookState(hookState)
                else
                    self:handleRoomBHookState(hookState)
                end
            end
        end
        
        ::continue::
    end
end

function SkaarhojPTZControllerMultiRoom:setSkaarhojPTZComponent()
    self.components.skaarhojPTZController = self:setComponent(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
end

function SkaarhojPTZControllerMultiRoom:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SkaarhojPTZControllerMultiRoom:setCamACPRComponent()
    for i = 1, 3 do
        if not Controls.compcamACPR or not Controls.compcamACPR[i] then
            goto continue
        end
        
        local acprLabels = {[1] = "ACPR Rm-A", [2] = "ACPR Rm-B", [3] = "ACPR Combined"}
        self.components.camACPR[i] = self:setComponent(Controls.compcamACPR[i], acprLabels[i])
        
        ::continue::
    end
end

function SkaarhojPTZControllerMultiRoom:setCompRoomControlsComponent()
    for i = 1, 2 do
        if not Controls.compRoomControls or not Controls.compRoomControls[i] then
            goto continue
        end
        
        local roomLabel = i == 1 and "Rm-A" or "Rm-B"
        local componentType = "Room Controls " .. roomLabel
        self.components.compRoomControls[i] = self:setComponent(Controls.compRoomControls[i], componentType)
        
        ::continue::
    end
end

-----------------[ Event Handler Setup ]-------------------
function SkaarhojPTZControllerMultiRoom:registerComponentEventHandlers()
    local cs = self.components.callSync
    local ptz = self.components.skaarhojPTZController
    local room = self.components.compRoomControls

    if ptz then
        self:registerPTZButtonHandlers()
        self:initializeCameraLabels()
    end

    if room and room[1] and room[1]["ledSystemPower"] then
        local led = room[1]["ledSystemPower"]
        led.EventHandler = function()
            if not self:getComponentBoolean(room[1], "ledSystemPower") then
                Controls.btnProductionMode.Boolean = false
                self:handleSystemPowerOff()
            end
        end
    end
end

function SkaarhojPTZControllerMultiRoom:registerPTZButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end

    -- Camera selection buttons (1-4)
    for i = 1, 4 do
        local btn = ptz["Button"..i..".press"]
        if btn then
            btn.EventHandler = function()
                self:handleCameraSelection(i)
            end
        end
    end
    
    -- Room A PC button (Button8)
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function()
            self:handlePCSend("A")
        end
    end
    
    -- Room B PC button (Button9)
    local btn9 = ptz["Button9.press"]
    if btn9 then
        btn9.EventHandler = function()
            self:handlePCSend("B")
        end
    end
end

function SkaarhojPTZControllerMultiRoom:initializeCameraLabels()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end
    for i = 1, 4 do
        self:setCameraLabel(i, i)
    end
end

-----------------[ Logic Handlers ]-------------------
function SkaarhojPTZControllerMultiRoom:handleCameraSelection(index)
    local ptz = self.components.skaarhojPTZController
    local router = self.components.camRouter
    if not ptz or not router then return end

    local camNum = tostring(index)
    self:setComponentProperty(router, "select.1", camNum)
    self:setComponentProperty(router, "select.2", camNum)
    self:setComponentProperty(ptz, "Button" .. index .. ".headerText", "Active")

    for i = 1, 4 do 
        self:setButtonActive(i, i == index) 
    end
end

function SkaarhojPTZControllerMultiRoom:handlePCSend(room)
    local ptz = self.components.skaarhojPTZController
    local router = self.components.camRouter
    local callSync = self.components.callSync[room == "A" and 1 or 2]
    if not ptz or not router or not callSync then return end
    if not self:getComponentBoolean(callSync, "off.hook") then return end

    local currentCam = self:getComponentProperty(router, "select." .. (room == "A" and "1" or "2"))
    if currentCam then
        local usbOutput = room == "A" and "3" or "4"
        self:setComponentProperty(router, "select." .. usbOutput, currentCam)
        local label = ptz["Button" .. currentCam .. ".screenText"]
        if label then
            local buttonNum = room == "A" and "8" or "9"
            self:setComponentProperty(ptz, "Button" .. buttonNum .. ".screenText", label.String)
        end
    end
end

function SkaarhojPTZControllerMultiRoom:handleSystemPowerOff()
    self:debugPrint("System power off - Production mode set to false")
    for i, acpr in ipairs(self.components.camACPR) do
        if acpr then 
            self:setComponentBoolean(acpr, "TrackingBypass", true) 
        end
    end
    if self.components.skaarhojPTZController then 
        self:setComponentBoolean(self.components.skaarhojPTZController, "Disable", true) 
    end
end

function SkaarhojPTZControllerMultiRoom:handleProductionModeChange()
    local ptz = self.components.skaarhojPTZController
    if ptz then
        self:setComponentBoolean(ptz, "Disable", not Controls.btnProductionMode.Boolean)
        self:setComponentBoolean(ptz, "Button14.press", true) -- Send All Home
    end
    
    for i, acpr in ipairs(self.components.camACPR) do
        if acpr then
            local on = Controls.btnProductionMode.Boolean
            local hook = self.state.combinedHookState
            local bypass = on or not hook
            self:setComponentBoolean(acpr, "TrackingBypass", bypass)
            self:debugPrint("Production mode: " .. tostring(on) .. ", Off hook: " .. tostring(hook))
        end
    end
end

-----------------[ Room Name Management ]-------------------
function SkaarhojPTZControllerMultiRoom:updateRoomName()
    if not self.components.compRoomControls or not self.components.compRoomControls[1] then return end
    
    local roomName = self.components.compRoomControls[1]["roomName"]
    if roomName and roomName.String ~= "" and roomName.String ~= self.clearString then
        self.roomName = roomName.String
        self:debugPrint("Room name updated to: " .. roomName.String)
    end
end

-----------------[ System Initialization ]-------------------
function SkaarhojPTZControllerMultiRoom:performSystemInitialization()
    self:debugPrint("Performing system initialization")
    
    self:recalibratePTZ()
    self:clearRoomRoutes("A")
    self:clearRoomRoutes("B")
    self:initializeCameraLabels()

    self:runDelayed(self.config.recalibrationDelay, function()
        local offHookA = self.components.callSync[1] and self:getComponentBoolean(self.components.callSync[1], "off.hook")
        local offHookB = self.components.callSync[2] and self:getComponentBoolean(self.components.callSync[2], "off.hook")
        
        if not offHookA and not offHookB then
            self:setPrivacy("Combined", true)
            for i = 1, 4 do 
                self:setButtonActive(i, false)    
            end
            self:disableRoomAPC()
            self:disableRoomBPC()
        end
        
        self:debugPrint("System initialization completed")
    end)
end

-----------------[ Component Name Discovery ]-------------------
function SkaarhojPTZControllerMultiRoom:getComponentNames()
    local namesTable = {
        CallSyncNames = {},
        SkaarhojPTZNames = {},
        CamRouterNames = {},
        DevCamNames = {},
        CamACPRNames = {},
        CompRoomControlsNames = {},
    }
    
    -- Single loop through all components
    for _, comp in pairs(Component.GetComponents()) do
        if not comp.Name or comp.Name == "" then goto continue end
        
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
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.CompRoomControlsNames, comp.Name)
        end
        
        ::continue::
    end
    
    -- Sort and add clear option
    for _, list in pairs(namesTable) do 
        table.sort(list)
        table.insert(list, self.clearString)
    end
    
    -- Update control choices
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

-----------------[ Event Handler Registration ]-------------------
function SkaarhojPTZControllerMultiRoom:registerEventHandlers()
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
            self:registerPTZButtonHandlers()
        end 
    end
    
    if Controls.compcamRouter then 
        Controls.compcamRouter.EventHandler = function() 
            self:setCamRouterComponent() 
            self:debugPrint("Camera router button handlers registered")
        end 
    end
    
    if Controls.compdevCams then
        for i, devCamComp in ipairs(Controls.compdevCams) do
            devCamComp.EventHandler = function() 
                self:setDevCamComponent(i) 
            end
        end
    end
    
    if Controls.compcamACPR then 
        for i, acprComp in ipairs(Controls.compcamACPR) do
            acprComp.EventHandler = function() 
                self:setCamACPRComponent() 
                self:debugPrint("Camera ACPR button handlers registered")
            end 
        end
    end
    
    if Controls.compRoomControls then 
        for i, roomControlComp in ipairs(Controls.compRoomControls) do
            roomControlComp.EventHandler = function() 
                self:setCompRoomControlsComponent() 
                self:updateRoomName()
                self:debugPrint("Room controls button handlers registered")
            end 
        end
    end
    
    if Controls.btnProductionMode then
        Controls.btnProductionMode.EventHandler = function()
            self:handleProductionModeChange()
        end
    end
end

-----------------[ Initialization ]-------------------
function SkaarhojPTZControllerMultiRoom:funcInit()
    self:debugPrint("Starting Divisible Space Camera Controller initialization...")
    
    self:runInitializers({
        function() self:getComponentNames() end,
        function() self:setupComponents() end,
        function() self:updateRoomName() end,
        function() self:registerEventHandlers() end,
        function() self:performSystemInitialization() end
    })

    if self.components.callSync[1] then
        local initialHookStateA = self:getComponentBoolean(self.components.callSync[1], "off.hook")
        self:handleRoomAHookState(initialHookStateA)
    end
    if self.components.callSync[2] then
        local initialHookStateB = self:getComponentBoolean(self.components.callSync[2], "off.hook")
        self:handleRoomBHookState(initialHookStateB)
    end
    
    self:debugPrint("Divisible Space Camera Controller Initialized with "..self:getCameraCount().." cameras")
end

-----------------[ Controller Factory Function ]-------------------

local function createDivisibleSpaceController(name, config)
    print("🎥 Initializing controller for: " .. name)
    local ok, instance = pcall(function()
        local controller = SkaarhojPTZControllerMultiRoom.new(config)
        controller:funcInit()
        return controller
    end)
    
    if ok then
        print("✅ Controller ready: " .. name)
        return instance
    else
        print("❌ Failed to create controller: " .. tostring(instance))
        return nil
    end
end

-- Entry Point
if not Controls.roomName then
    print("🚨 ERROR: Missing Controls.roomName")
    return
end

local formattedName = "[" .. Controls.roomName.String .. "]"
myDivisibleSpaceController = createDivisibleSpaceController(formattedName, defaultConfig)
