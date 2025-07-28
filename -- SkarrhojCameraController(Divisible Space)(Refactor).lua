--[[ 
  Skaarhoj Camera Controller - Divisible Space Version (Performance Optimized)
  Author: Refactored from Single Room Camera Controller
  2025-06-24
  Firmware Req: 10.0.0
  Version: 2.0
  
  Performance Optimized Refactor:
  - Streamlined event handlers with direct component access
  - Reduced redundant state and UI updates
  - Flattened control flow with early returns
  - Consolidated initialization and error handling
  - Optimized button press handling for faster response
  - Enhanced error checking and validation
  - Simplified module structure for better maintainability
]]--

-- SkaarhojPTZControllerMultiRoom class
SkaarhojPTZControllerMultiRoom = {}
SkaarhojPTZControllerMultiRoom.__index = SkaarhojPTZControllerMultiRoom

-----------------[ Class Constructor ]-------------------
function SkaarhojPTZControllerMultiRoom.new(config)
    local self = setmetatable({}, SkaarhojPTZControllerMultiRoom)
    
    -- Instance properties
    self.roomName = "Divisible Space"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
        camRouter = "video_router",
        devCams = "onvif_camera_operative",
        camACPR = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
        roomControls = "device_controller_script"
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
        roomsCombiner = nil,
        invalid = {}
    }
    
    -- State tracking
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
    
    -- Camera labels lookup
    self.cameraLabels = {
        ["1"] = "Cam01",
        ["2"] = "Cam02", 
        ["3"] = "Cam03",
        ["4"] = "Cam04"
    }
    
    return self
end

-----------------[ Direct Component Access ]-------------------
function SkaarhojPTZControllerMultiRoom:setComponentProperty(component, control, value)
    if not component or not component[control] then 
        return false 
    end
    component[control].String = value
    return true
end

function SkaarhojPTZControllerMultiRoom:setComponentBoolean(component, control, value)
    if not component or not component[control] then 
        return false 
    end
    component[control].Boolean = value
    return true
end

function SkaarhojPTZControllerMultiRoom:getComponentBoolean(component, control)
    if not component or not component[control] then 
        return false 
    end
    return component[control].Boolean
end

function SkaarhojPTZControllerMultiRoom:triggerComponent(component, control)
    if not component or not component[control] then 
        return false 
    end
    component[control]:Trigger()
    return true
end

-----------------[ Debug Helper ]-------------------
function SkaarhojPTZControllerMultiRoom:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." Camera Debug] "..str) 
    end
end

-----------------[ Camera Operations ]-------------------
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
    
    -- Start recalibration
    for _, camera in ipairs(cameras) do
        if camera then 
            self:triggerComponent(camera, "ptz.recalibrate") 
        end
    end
    
    -- Stop recalibration after delay
    Timer.CallAfter(function()
        for _, camera in ipairs(cameras) do
            if camera then 
                self:setComponentBoolean(camera, "ptz.recalibrate", false) 
            end
        end
    end, self.config.recalibrationDelay)
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

-----------------[ Routing Operations ]-------------------
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
        Timer.CallAfter(function()
            self:enableRoomAPC()
        end, self.config.initializationDelay)
    elseif self:getComponentBoolean(self.components.callSync[2], "off.hook") then
        self:disableRoomAPC()
        Timer.CallAfter(function()
            self:enableRoomBPC()
        end, self.config.initializationDelay)
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

-----------------[ PTZ Operations ]-------------------
function SkaarhojPTZControllerMultiRoom:setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
    local base = self.components.skaarhojPTZController
    if not base then 
        self:debugPrint("PTZ Controller not found")
        return 
    end
    
    if headerText then 
        self:setComponentProperty(base, "Button"..buttonNumber..".headerText", headerText)
    end
    if screenText then 
        self:setComponentProperty(base, "Button"..buttonNumber..".screenText", screenText)
    end
    if controlLink then 
        self:setComponentProperty(base, "Button"..buttonNumber..".controlLink", controlLink)
    end
    if color then 
        self:setComponentProperty(base, "Button"..buttonNumber..".color", color)
    end
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
        Timer.CallAfter(function()
            self:setComponentBoolean(self.components.camACPR[3], "TrackingBypass", true)
        end, self.config.initializationDelay * 2)
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

-----------------[ Component Management ]-------------------
function SkaarhojPTZControllerMultiRoom:setComponent(ctrl, componentType)
    if not ctrl then return nil end
    
    local componentName = ctrl.String
    if componentName == "" or componentName == self.clearString then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    
    local component = Component.New(componentName)
    if not component or #Component.GetControls(component) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return component
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
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

-----------------[ Component Setup ]-------------------
function SkaarhojPTZControllerMultiRoom:setupComponents()
    self:setCallSyncComponent()
    self:setSkaarhojPTZComponent()
    self:setCamRouterComponent()
    self:setCamACPRComponent()
    self:setCompRoomControlsComponent()
    if Controls.compdevCams then
        for i = 1, 4 do 
            self:setDevCamComponent(i) 
        end
    end
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
    self:registerSkaarhojComponentButtonHandlers()
end

function SkaarhojPTZControllerMultiRoom:registerSkaarhojComponentButtonHandlers()
    local ptz = self.components.skaarhojPTZController
    if not ptz then return end
    
    -- Camera selection buttons (1-4)
    for i = 1, 4 do
        local btn = ptz["Button"..i..".press"]
        if btn then
            btn.EventHandler = function()
                self:setComponentProperty(ptz, "Button"..i..".headerText", "Active")
                if self.components.camRouter then
                    local camIndex = tostring(i)
                    self.components.camRouter["select.1"].String = camIndex
                    self.components.camRouter["select.2"].String = camIndex
                end
                -- Visual feedback for all buttons
                for j = 1, 4 do
                    self:setButtonActive(j, j == i)
                end
            end
        end
    end
    
    -- Room A PC button (Button8)
    local btn8 = ptz["Button8.press"]
    if btn8 then
        btn8.EventHandler = function()
            if self.components.callSync[1] and self:getComponentBoolean(self.components.callSync[1], "off.hook") then
                local currentCam = self.components.camRouter["select.1"].String
                self.components.camRouter["select.3"].String = currentCam
                local selectedText = ptz["Button"..currentCam..".screenText"]
                if selectedText then
                    self:setComponentProperty(ptz, "Button8.screenText", selectedText.String)
                end
            end
        end
    end
    
    -- Room B PC button (Button9)
    local btn9 = ptz["Button9.press"]
    if btn9 then
        btn9.EventHandler = function()
            if self.components.callSync[2] and self:getComponentBoolean(self.components.callSync[2], "off.hook") then
                local currentCam = self.components.camRouter["select.2"].String
                self.components.camRouter["select.4"].String = currentCam
                local selectedText = ptz["Button"..currentCam..".screenText"]
                if selectedText then
                    self:setComponentProperty(ptz, "Button9.screenText", selectedText.String)
                end
            end
        end
    end
end

function SkaarhojPTZControllerMultiRoom:setCamRouterComponent()
    self.components.camRouter = self:setComponent(Controls.compcamRouter, "Camera Router")
end

function SkaarhojPTZControllerMultiRoom:setDevCamComponent(idx)
    if not Controls.compdevCams or not Controls.compdevCams[idx] then return end
    
    local cameraLabels = {[1] = "Cam01", [2] = "Cam02", [3] = "Cam03", [4] = "Cam04"}
    self.components.devCams[idx] = self:setComponent(Controls.compdevCams[idx], cameraLabels[idx])
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
    
    -- Batch initialization tasks
    self:recalibratePTZ()
    self:clearRoomRoutes("A")
    self:clearRoomRoutes("B")
    
    Timer.CallAfter(function()
        -- Check hook states and set initial privacy
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
    end, self.config.recalibrationDelay)
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
            self:registerSkaarhojComponentButtonHandlers()
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
            local state = Controls.btnProductionMode.Boolean
            for i, acpr in ipairs(self.components.camACPR) do
                if acpr then
                    self:setComponentBoolean(acpr, "TrackingBypass", state)
                end
            end
            if self.components.skaarhojPTZController then
                self:setComponentBoolean(self.components.skaarhojPTZController, "Disable", not state)
                self:setComponentBoolean(self.components.skaarhojPTZController, "Button14.press", true)
            end
        end
    end
end

-----------------[ Initialization ]-------------------
function SkaarhojPTZControllerMultiRoom:funcInit()
    self:debugPrint("Starting Divisible Space Camera Controller initialization...")
    
    -- Batch initialization
    self:getComponentNames()
    self:setupComponents()
    self:updateRoomName()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    -- Apply initial hook states
    if self.components.callSync[1] then
        local initialHookStateA = self:getComponentBoolean(self.components.callSync[1], "off.hook")
        self:handleRoomAHookState(initialHookStateA)
    end
    if self.components.callSync[2] then
        local initialHookStateB = self:getComponentBoolean(self.components.callSync[2], "off.hook")
        self:handleRoomBHookState(initialHookStateB)
    end
    
    -- Initialize camera labels
    if self.components.skaarhojPTZController then
        for i = 1, 4 do
            self:setCameraLabel(i, i)
        end
        self:debugPrint("Camera labels initialized for buttons 1-4")
    end
    
    self:debugPrint("Divisible Space Camera Controller Initialized with "..self:getCameraCount().." cameras")
end

-----------------[ Factory Function ]-------------------
local function createDivisibleSpaceController(config)
    print("Creating Divisible Space Camera Controller...")
    local success, controller = pcall(function()
        local instance = SkaarhojPTZControllerMultiRoom.new(config)
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

-----------------[ Instance Creation ]-------------------
myDivisibleSpaceController = createDivisibleSpaceController()

if myDivisibleSpaceController then
    print("Divisible Space Camera Controller created successfully!")
else
    print("ERROR: Failed to create Divisible Space Camera Controller!")
end 