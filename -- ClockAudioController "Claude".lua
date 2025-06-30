--[[
  ClockAudioCDTMicController - High-Performance Q-SYS Control Script
  Author: Performance Optimized Version
  Date: 2025-01-27
  Version: 3.1
  Description: Ultra-responsive ClockAudio CDT microphone controller with optimized event handling and test mode
]]--

-- Global control cache for fastest access
local controlCache = {
    compMicBox = Controls.compMicBox,
    compMicMixer = Controls.compMicMixer,   
    compCallSync = Controls.compCallSync,
    compRoomControls = Controls.compRoomControls,
    txtStatus = Controls.txtStatus,
    -- Test control for hook state emulation
    btnTestHookState = Controls.btnTestHookState
}

-- Validate required controls exist
local function validateControls()
    local missingControls = {}
    
    if not controlCache.compMicBox then
        table.insert(missingControls, "compMicBox")
    end
    
    if not controlCache.compMicMixer then
        table.insert(missingControls, "compMicMixer")
    end
    
    if not controlCache.compCallSync then
        table.insert(missingControls, "compCallSync")
    end
    
    if not controlCache.compRoomControls then
        table.insert(missingControls, "compRoomControls")
    end
    
    if #missingControls > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missingControls, ", "))
        return false
    end
    
    return true
end

--------** Class Definition **--------
ClockAudioCDTMicController = {}
ClockAudioCDTMicController.__index = ClockAudioCDTMicController

function ClockAudioCDTMicController.new(roomName, config)
    local self = setmetatable({}, ClockAudioCDTMicController)
    
    -- Core properties
    self.roomName = roomName or "ClockAudio CDT"
    self.debugging = (config and config.debugging) or false
    self.clearString = "[Clear]"
    
    -- Direct component references for speed
    self.components = {
        callSync = nil,
        micBoxes = {}, -- Pre-allocated array
        micMixer = nil,
        roomControls = nil,
        invalid = {} -- Track invalid components
    }
    
    -- Consolidated state management
    self.state = {
        globalMute = false,
        offHook = false,
        privacyEnabled = false,
        systemPower = true,
        fireAlarm = false,
        testMode = false -- Test mode state
    }
    
    -- Optimized configuration
    self.config = {
        ledDelay = 0.1, -- Reduced for responsiveness
        initDelay = 0.2, -- Faster initialization
        toggleInterval = 1.0, -- LED toggle speed
        brightnessDelay = 2.0 -- LED brightness delay
    }
    
    -- Initialize optimized modules
    self:initLEDModule()
    self:initMicModule()
    self:initTestModule() -- Add test module
    
    return self
end

--------** Debug (Only When Needed) **--------
function ClockAudioCDTMicController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.."] "..str) 
    end
end

--------** Component Setup **--------
function ClockAudioCDTMicController:setComponent(controlRef, componentName)
    if not controlRef or controlRef.String == self.clearString then
        if controlRef then controlRef.Color = "white" end
        self:setComponentValid(componentName)
        return nil
    elseif #Component.GetControls(Component.New(controlRef.String)) < 1 then
        if controlRef then
            controlRef.String = "[Invalid Component Selected]"
            controlRef.Color = "pink"
        end
        self:setComponentInvalid(componentName)
        return nil
    else
        if controlRef then controlRef.Color = "white" end
        self:setComponentValid(componentName)
        local component = Component.New(controlRef.String)
        if component then
            self:debugPrint("Connected to "..componentName)
            return component
        else
            self:debugPrint("Failed to connect to "..componentName)
            return nil
        end
    end
end

function ClockAudioCDTMicController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function ClockAudioCDTMicController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function ClockAudioCDTMicController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v == true then
            if controlCache.txtStatus then
                controlCache.txtStatus.String = "Invalid Components"
                controlCache.txtStatus.Value = 1
            end
            return
        end
    end
    if controlCache.txtStatus then
        controlCache.txtStatus.String = "OK"
        controlCache.txtStatus.Value = 0
    end
end

function ClockAudioCDTMicController:setupComponents()
    -- Batch component setup for speed
    self.components.roomControls = self:setComponent(controlCache.compRoomControls, "Room Controls")
    self.components.callSync = self:setComponent(controlCache.compCallSync, "Call Sync")
    self.components.micMixer = self:setComponent(controlCache.compMicMixer, "Mic Mixer")
    
    -- Setup mic boxes in batch
    for i = 1, 4 do
        if controlCache.compMicBox[i] then
            self.components.micBoxes[i] = self:setComponent(controlCache.compMicBox[i], "MicBox"..string.format("%02d", i))
        end
    end
end

--------** LED Module **--------
function ClockAudioCDTMicController:initLEDModule()
    local selfRef = self
    self.ledModule = {
        -- Batch LED state updates for maximum performance
        setBatchLEDState = function(color, state, brightness)
            brightness = brightness or (state and 1 or 0)
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    box['Global'..color..'State'].Boolean = state
                    box['Global'..color..'Brightness'].Position = brightness
                end
            end
        end,
        
        -- Direct LED control without function overhead
        setGlobalLEDs = function(red, green)
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    -- Direct property assignments
                    box.GlobalRedState.Boolean = red
                    box.GlobalGreenState.Boolean = green
                    box.GlobalRedBrightness.Position = red and 1 or 0
                    box.GlobalGreenBrightness.Position = green and 1 or 0
                end
            end
        end,
        
        -- Optimized individual LED control
        setIndividualLED = function(boxIndex, ledIndex, isActive, isRed)
            local box = selfRef.components.micBoxes[boxIndex]
            if not box then return end
            
            local color = isRed and "Red" or "Green"
            local altColor = isRed and "Green" or "Red"
            
            -- Direct assignments for speed
            box[color..'State '..ledIndex].Boolean = isActive
            box[color..'Brightness '..ledIndex].Position = isActive and 1 or 0
            box[altColor..'State '..ledIndex].Boolean = false
            box[altColor..'Brightness '..ledIndex].Position = 0
        end,
        
        -- Single-call LED update for all mic states
        updateAllMicLEDs = function()
            for boxIndex = 1, 4 do
                local box = selfRef.components.micBoxes[boxIndex]
                if box then
                    local maxLeds = (boxIndex == 1 or boxIndex == 4) and 3 or 4
                    for ledIndex = 1, maxLeds do
                        local buttonState = box['ButtonState '..(ledIndex * 2 + 4)].Boolean
                        if buttonState then
                            local isRed = selfRef.state.globalMute
                            selfRef.ledModule.setIndividualLED(boxIndex, ledIndex, true, isRed)
                        else
                            -- Turn off both colors directly
                            box['RedState '..ledIndex].Boolean = false
                            box['GreenState '..ledIndex].Boolean = false
                            box['RedBrightness '..ledIndex].Position = 0
                            box['GreenBrightness '..ledIndex].Position = 0
                        end
                    end
                end
            end
        end,
        
        -- Batch LED updates for performance
        updateAllLEDs = function()
            Timer.CallAfter(function()
                for boxIndex = 1, 4 do
                    local box = selfRef.components.micBoxes[boxIndex]
                    if box then
                        local maxLeds = (boxIndex == 1 or boxIndex == 4) and 3 or 4
                        for ledIndex = 1, maxLeds do
                            local buttonState = box['ButtonState '..(ledIndex * 2 + 4)].Boolean
                            if not buttonState then
                                box['GreenBrightness '..ledIndex].Position = 0
                                box['RedBrightness '..ledIndex].Position = 0
                            end
                        end
                    end
                end
            end, selfRef.config.brightnessDelay)
        end
    }
end

--------** CDT Mic Module **--------
function ClockAudioCDTMicController:initMicModule()
    local selfRef = self
    self.micModule = {
        -- Direct mic toggle with immediate response
        toggleMic = function(boxIndex, ledIndex, mixerInput)
            local box = selfRef.components.micBoxes[boxIndex]
            local mixer = selfRef.components.micMixer
            if not box or not mixer then return end
            
            local isActive = box['ButtonState '..(ledIndex * 2 + 4)].Boolean
            
            -- Direct mixer control - no function calls
            mixer['input.'..mixerInput..'.mute'].Boolean = not isActive
            
            -- Immediate LED feedback
            if isActive then
                local isRed = selfRef.state.globalMute
                box[(isRed and "Red" or "Green")..'State '..ledIndex].Boolean = true
                box[(isRed and "Red" or "Green")..'Brightness '..ledIndex].Position = 1
                box[(isRed and "Green" or "Red")..'State '..ledIndex].Boolean = false
                box[(isRed and "Green" or "Red")..'Brightness '..ledIndex].Position = 0
            else
                box['RedState '..ledIndex].Boolean = false
                box['GreenState '..ledIndex].Boolean = false
                box['RedBrightness '..ledIndex].Position = 0
                box['GreenBrightness '..ledIndex].Position = 0
            end
        end,
        
        -- Optimized global mute with single LED update
        setGlobalMute = function(muteState)
            selfRef.state.globalMute = muteState
            
            -- Update HID directly
            if selfRef.components.callSync then
                selfRef.components.callSync['mute'].Boolean = muteState
            end
            
            -- Single LED update call
            if selfRef.state.offHook then
                selfRef.ledModule.setGlobalLEDs(muteState, not muteState)
            end
            
            -- Update individual mic LEDs
            selfRef.ledModule.updateAllMicLEDs()
        end,
        
        -- Direct hook state management
        setHookState = function(hookState)
            selfRef.state.offHook = hookState
            if hookState then
                local showRed = selfRef.state.globalMute
                selfRef.ledModule.setGlobalLEDs(showRed, not showRed)
            else
                selfRef.ledModule.setGlobalLEDs(false, false)
            end
        end,
        
        -- LED toggle
        ledToggleTimer = Timer.New(),
        ledState = false,
        
        startLEDToggle = function()
            selfRef.micModule.ledToggleTimer:Start(selfRef.config.toggleInterval)
        end,
        
        stopLEDToggle = function()
            selfRef.micModule.ledToggleTimer:Stop()
        end,
        
        setLED = function(state)
            selfRef.micModule.ledState = state
            selfRef.ledModule.setGlobalLEDs(false, state)
        end,
        
        -- Set mute state (alias for setGlobalMute for compatibility)
        setMute = function(muteState)
            selfRef.micModule.setGlobalMute(muteState)
        end
    }
    
    -- Set up LED toggle timer
    self.micModule.ledToggleTimer.EventHandler = function()
        self.micModule.ledState = not self.micModule.ledState
        self.micModule.setLED(self.micModule.ledState)
    end
end

--------** Test Module - Hook State Emulation **--------
function ClockAudioCDTMicController:initTestModule()
    local selfRef = self
    self.testModule = {
        -- Emulated hook state only
        emulatedHookState = false,
        
        -- Toggle hook state for testing
        toggleHookState = function()
            selfRef.testModule.emulatedHookState = not selfRef.testModule.emulatedHookState
            selfRef:debugPrint("Test Mode: Hook State = " .. tostring(selfRef.testModule.emulatedHookState))
            
            -- Update mic module with emulated hook state
            selfRef.micModule.setHookState(selfRef.testModule.emulatedHookState)
        end,
        
        -- Enable test mode
        enableTestMode = function()
            selfRef.state.testMode = true
            selfRef:debugPrint("Hook State Test Mode Enabled")
            
            -- Register test control event handlers
            selfRef:registerTestControlHandlers()
        end,
        
        -- Disable test mode
        disableTestMode = function()
            selfRef.state.testMode = false
            selfRef:debugPrint("Hook State Test Mode Disabled")
            
            -- Clear test control event handlers
            selfRef:clearTestControlHandlers()
        end,
        
        -- Get current hook state
        getHookState = function()
            return selfRef.testModule.emulatedHookState
        end
    }
end

--------** Test Control Event Handlers **--------
function ClockAudioCDTMicController:registerTestControlHandlers()
    local selfRef = self
    
    -- Hook state test button
    if controlCache.btnTestHookState then
        controlCache.btnTestHookState.EventHandler = function(ctl)
            if ctl.Boolean then
                selfRef.testModule.toggleHookState()
            end
        end
    end
    
    self:debugPrint("Hook state test control handler registered")
end

function ClockAudioCDTMicController:clearTestControlHandlers()
    -- Clear hook state test control event handler
    if controlCache.btnTestHookState then
        controlCache.btnTestHookState.EventHandler = nil
    end
    
    self:debugPrint("Hook state test control handler cleared")
end

--------** Component Name Discovery **--------
function ClockAudioCDTMicController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {},
        CallSyncNames = {},
        MicBoxNames = {},
        MicMixerNames = {}
    }

    for _, component in pairs(Component.GetComponents()) do
        if component.Type == "call_sync" then
            table.insert(namesTable.CallSyncNames, component.Name)
        elseif component.Type == "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3" then
            table.insert(namesTable.MicBoxNames, component.Name)
        elseif component.Type == "device_controller_script" and component.Name:match("^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, component.Name)
        elseif component.Type == "mixer" then
            table.insert(namesTable.MicMixerNames, component.Name)
        end
    end
    
    for _, nameList in pairs(namesTable) do
        table.sort(nameList)
        table.insert(nameList, self.clearString)
    end
    
    controlCache.compRoomControls.Choices = namesTable.RoomControlsNames
    controlCache.compCallSync.Choices = namesTable.CallSyncNames
    controlCache.compMicMixer.Choices = namesTable.MicMixerNames
    
    for i, control in ipairs(controlCache.compMicBox) do
        control.Choices = namesTable.MicBoxNames
    end
end

--------** Event Handler Registration **--------
function ClockAudioCDTMicController:registerEventHandlers()
    local selfRef = self
    
    -- System power handler - direct state management
    if self.components.roomControls then
        local powerControl = self.components.roomControls["ledSystemPower"]
        if powerControl then
            powerControl.EventHandler = function(ctl)
                selfRef.state.systemPower = ctl.Boolean
                if not ctl.Boolean then
                    selfRef.state.globalMute = true
                    selfRef.ledModule.setGlobalLEDs(false, false)
                end
            end
        end
        
        -- Fire alarm handler - direct LED control
        local fireControl = self.components.roomControls["ledFireAlarm"]
        if fireControl then
            fireControl.EventHandler = function(ctl)
                selfRef.state.fireAlarm = ctl.Boolean
                if ctl.Boolean then
                    selfRef.micModule.startLEDToggle()
                    selfRef.state.globalMute = true
                    selfRef.ledModule.setGlobalLEDs(false, false)
                else
                    selfRef.micModule.stopLEDToggle()
                    if selfRef.state.offHook then
                        selfRef.ledModule.setGlobalLEDs(false, true)
                    end
                end
            end
        end
    end
    
    -- Call sync handlers - direct state updates
    if self.components.callSync then
        local offHookControl = self.components.callSync["off.hook"]
        if offHookControl then
            offHookControl.EventHandler = function(ctl)
                selfRef.micModule.setHookState(ctl.Boolean)
            end
        end
        
        local muteControl = self.components.callSync["mute"]
        if muteControl then
            muteControl.EventHandler = function(ctl)
                selfRef.micModule.setGlobalMute(ctl.Boolean)
            end
        end
    end
    
    -- Mic button handlers
    self:registerMicHandlers()
    self:registerPrivacyButtonHandlers()
end

--------** Table-Driven Mic Button Registration **--------
function ClockAudioCDTMicController:registerMicHandlers()
    local selfRef = self
    
    -- Button configuration table for direct registration
    local buttonConfigs = {
        {box = 1, buttons = {{6,1,1}, {8,2,2}, {10,3,3}}},
        {box = 2, buttons = {{6,1,4}, {8,2,5}, {10,3,6}, {12,4,7}}},
        {box = 3, buttons = {{6,1,8}, {8,2,9}, {10,3,10}, {12,4,11}}},
        {box = 4, buttons = {{6,1,12}, {8,2,13}, {10,3,14}}}
    }
    
    for _, config in ipairs(buttonConfigs) do
        local box = self.components.micBoxes[config.box]
        if box then
            for _, btn in ipairs(config.buttons) do
                local buttonControl = box['ButtonState '..btn[1]]
                if buttonControl then
                    -- Direct closure for maximum speed
                    local boxIdx, ledIdx, mixerIdx = config.box, btn[2], btn[3]
                    buttonControl.EventHandler = function()
                        selfRef.micModule.toggleMic(boxIdx, ledIdx, mixerIdx)
                    end
                end
            end
        end
    end
end

--------** Privacy Button Registration **--------
function ClockAudioCDTMicController:registerPrivacyButtonHandlers()
    local selfRef = self
    
    local privacyConfigs = {
        {box = 1, buttons = {1, 2, 3}},
        {box = 2, buttons = {1, 2, 3, 4}},
        {box = 3, buttons = {1, 2, 3, 4}},
        {box = 4, buttons = {1, 2, 3}}
    }
    
    for _, config in ipairs(privacyConfigs) do
        local box = self.components.micBoxes[config.box]
        if box then
            for _, buttonNum in ipairs(config.buttons) do
                local privacyButton = box['ButtonState '..buttonNum]
                
                if privacyButton then
                    privacyButton.EventHandler = function()
                        local callSync = selfRef.components.callSync
                        if callSync and callSync["mute"] then
                            -- Toggle mute state directly
                            callSync["mute"].Boolean = not callSync["mute"].Boolean
                        end
                    end
                end
            end
        end
    end
end

--------** Test Mode Management **--------
function ClockAudioCDTMicController:enableTestModeIfNoCallSync()
    -- Check if call sync component is available
    if not self.components.callSync then
        self:debugPrint("No Call Sync component found - enabling hook state test mode")
        self.testModule.enableTestMode()
        
        -- Set initial hook state (start on-hook)
        self.testModule.emulatedHookState = false
        
        -- Initialize mic module with test hook state
        self.micModule.setHookState(self.testModule.emulatedHookState)
        
        self:debugPrint("Hook state test mode ready - use btnTestHookState to toggle")
    else
        self:debugPrint("Call Sync component found - hook state test mode not needed")
    end
end

function ClockAudioCDTMicController:isTestModeActive()
    return self.state.testMode
end

function ClockAudioCDTMicController:getHookState()
    if self.testModule then
        return self.testModule.getHookState()
    end
    return nil
end

--------** Initialization **--------
function ClockAudioCDTMicController:funcInit()
    self:debugPrint("Starting initialization...")
    
    -- Get component names first
    self:getComponentNames()
    
    -- Batch all immediate operations
    self:setupComponents()
    self:registerEventHandlers()
    
    -- Enable test mode for hook state emulation if needed
    self:enableTestModeIfNoCallSync()
    
    -- Update LED states after initialization
    self.ledModule.updateAllLEDs()
    
    self:debugPrint("Initialization completed with "..self:getMicBoxCount().." mic boxes")
end

--------** Utility Functions **--------
function ClockAudioCDTMicController:getMicBoxCount()
    local count = 0
    for i = 1, 4 do
        if self.components.micBoxes[i] then count = count + 1 end
    end
    return count
end

--------** Cleanup **--------
function ClockAudioCDTMicController:cleanup()
    -- Stop timers
    if self.micModule.ledToggleTimer then
        self.micModule.stopLEDToggle()
        self.micModule.ledToggleTimer.EventHandler = nil
    end
    
    -- Clear test mode if active
    if self.testModule then
        self.testModule.disableTestMode()
    end
    
    -- Clear handlers in batch
    local handlersToClean = {
        {self.components.callSync, {"off.hook", "mute"}},
        {self.components.roomControls, {"ledSystemPower", "ledFireAlarm"}}
    }
    
    for _, handler in ipairs(handlersToClean) do
        local component, controls = handler[1], handler[2]
        if component then
            for _, controlName in ipairs(controls) do
                if component[controlName] then
                    component[controlName].EventHandler = nil
                end
            end
        end
    end
    
    -- Clean mic box handlers
    for i = 1, 4 do
        local box = self.components.micBoxes[i]
        if box then
            for buttonNum = 1, 12 do
                local button = box['ButtonState '..buttonNum]
                if button then button.EventHandler = nil end
            end
        end
    end
    
    -- Reset component references
    self.components = {
        callSync = nil,
        micBoxes = {},
        micMixer = nil,
        roomControls = nil,
        invalid = {}
    }
    
    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createClockAudioCDTMicController(roomName, config)
    print("Creating ClockAudioCDTMicController for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = ClockAudioCDTMicController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created controller for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Validate controls before creating instance
if not validateControls() then
    print("ERROR: Required controls are missing. Please check your Q-SYS design.")
    return
end

-- Create controller instance with a temporary room name
local tempRoomName = "[ClockAudio CDT]"
myClockAudioCDTMicController = createClockAudioCDTMicController(tempRoomName, {debugging = false})

if myClockAudioCDTMicController then
    -- Update room name from room controls component if available
    if myClockAudioCDTMicController.components.roomControls and 
       myClockAudioCDTMicController.components.roomControls["roomName"] then
        local actualRoomName = myClockAudioCDTMicController.components.roomControls["roomName"].String
        if actualRoomName and actualRoomName ~= "" then
            myClockAudioCDTMicController.roomName = "[" .. actualRoomName .. "]"
            print("ClockAudioCDTMicController created successfully for room: " .. actualRoomName)
        else
            print("ClockAudioCDTMicController created successfully (using default room name)")
        end
    else
        print("ClockAudioCDTMicController created successfully (room controls not available)")
    end
else
    print("ERROR: Failed to create ClockAudioCDTMicController!")
end