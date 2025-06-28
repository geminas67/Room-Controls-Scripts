--[[
  ClockAudioCDTMicController - High-Performance Q-SYS Control Script
  Author: Performance Optimized Version
  Date: 2025-01-27
  Version: 3.0
  Description: Ultra-responsive ClockAudio CDT microphone controller with optimized event handling
]]--

-- Global control cache for fastest access
local controlCache = {
    compMicBox = Controls.compMicBox,
    compTouchSwitch = Controls.compTouchSwitch,
    compMicMixer = Controls.compMicMixer,   
    compHIDConferencing = Controls.compHIDConferencing,
    compRoomControls = Controls.compRoomControls,
    compVideoBridge = Controls.compVideoBridge,
    txtStatus = Controls.txtStatus,
    roomName = Controls.roomName,
    globalMute = Controls['ClockAudio-LED-MUTE']
}

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
        videoBridge = nil,
        callSync = nil,
        micBoxes = {}, -- Pre-allocated array
        micMixer = nil,
        roomControls = nil
    }
    
    -- Consolidated state management
    self.state = {
        globalMute = false,
        offHook = false,
        privacyEnabled = false,
        systemPower = true,
        fireAlarm = false
    }
    
    -- Optimized configuration
    self.config = {
        ledDelay = 0.1, -- Reduced for responsiveness
        initDelay = 0.2, -- Faster initialization
        toggleInterval = 1.0 -- LED toggle speed
    }
    
    -- Initialize optimized modules
    self:initLEDModule()
    self:initMicModule()
    
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
        return nil
    end
    
    local component = Component.New(controlRef.String)
    if component then
        self:debugPrint("Connected to "..componentName)
        return component
    else
        self:debugPrint("Failed to connect to "..componentName)
        return nil
    end
end

function ClockAudioCDTMicController:setupComponents()
    -- Batch component setup for speed
    self.components.roomControls = self:setComponent(controlCache.compRoomControls, "Room Controls")
    self.components.callSync = self:setComponent(controlCache.compHIDConferencing, "Call Sync")
    self.components.videoBridge = self:setComponent(controlCache.compVideoBridge, "Video Bridge")
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
            if selfRef.components.videoBridge then
                selfRef.components.videoBridge['toggle.privacy'].Boolean = muteState
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
        end
    }
    
    -- Set up LED toggle timer
    self.micModule.ledToggleTimer.EventHandler = function()
        self.micModule.ledState = not self.micModule.ledState
        self.micModule.setLED(self.micModule.ledState)
    end
end

--------** Component Name Discovery **--------
function ClockAudioCDTMicController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {},
        CallSyncNames = {},
        VideoBridgeNames = {},
        MicBoxNames = {}
    }

    for _, component in pairs(Component.GetComponents()) do
        if component.Type == "call_sync" then
                table.insert(namesTable.CallSyncNames, component.Name)
            elseif component.Type == "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3" then
            table.insert(namesTable.MicBoxNames, component.Name)
        elseif component.Type == "usb_uvc" then
            table.insert(namesTable.VideoBridgeNames, component.Name)
        elseif component.Type == "device_controller_script" and component.Name:match("^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, component.Name)
        end
    end
    
    for _, nameList in pairs(namesTable) do
        table.sort(nameList)
        table.insert(nameList, self.clearString)
    end
    
    controlCache.compRoomControls.Choices = namesTable.RoomControlsNames
    controlCache.compHIDConferencing.Choices = namesTable.CallSyncNames
    controlCache.compVideoBridge.Choices = namesTable.VideoBridgeNames
    
    for i, control in ipairs(controlCache.compMicBox) do
        control.Choices = namesTable.MicBoxNames
    end
end

--------** Event Handler Registration **--------
function ClockAudioCDTMicController:registerEventHandlers()
    local selfRef = self
    
    -- Direct global mute handler
    if controlCache.globalMute then
        controlCache.globalMute.EventHandler = function(ctl)
            selfRef.micModule.setGlobalMute(ctl.Boolean)
        end
    end
    
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
    
    -- Video bridge privacy handler - direct control
    if self.components.videoBridge then
        local privacyControl = self.components.videoBridge["toggle.privacy"]
        if privacyControl then
            privacyControl.EventHandler = function(ctl)
                local isMuted = ctl.Boolean
                selfRef.micModule.setGlobalMute(isMuted)
            end
        end
    end
    
    -- Mic button handlers
    self:registerOptimizedMicHandlers()
    self:registerPrivacyButtonHandlers()
end

--------** Table-Driven Mic Button Registration **--------
function ClockAudioCDTMicController:registerOptimizedMicHandlers()
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

--------** Initialization **--------
function ClockAudioCDTMicController:funcInit()
    self:debugPrint("Starting optimized initialization...")
    
    -- Batch all immediate operations
    self:setupComponents()
    self:registerEventHandlers()
    
    -- Single delayed initialization for system state
    Timer.CallAfter(function()
        if controlCache.globalMute then
            controlCache.globalMute.Boolean = false
            Timer.CallAfter(function()
                controlCache.globalMute.Boolean = true
                selfRef.ledModule.updateAllMicLEDs()
                selfRef:debugPrint("Initialization completed with "..selfRef:getMicBoxCount().." mic boxes")
            end, 0.1)
        end
    end, self.config.initDelay)
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
    
    -- Clear handlers in batch
    local handlersToClean = {
        {self.components.callSync, {"off.hook", "mute"}},
        {self.components.videoBridge, {"toggle.privacy"}},
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
    
    -- Clear control handlers
    if controlCache.globalMute then
        controlCache.globalMute.EventHandler = nil
    end
    
    self:debugPrint("Cleanup completed")
end

--------** Factory Function **--------
local function createClockAudioCDTMicController(roomName, config)
    print("Creating optimized ClockAudioCDTMicController for: "..tostring(roomName))
    
    local success, controller = pcall(function()
        local instance = ClockAudioCDTMicController.new(roomName, config)
        instance:getComponentNames() -- Populate component choices
        instance:funcInit()
        return instance
    end)
    
    if success then
        print("Successfully created optimized controller for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
if not controlCache.roomName then
    print("ERROR: Controls.roomName not found!")
    return
end

local formattedRoomName = "["..controlCache.roomName.String.."]"
myClockAudioCDTMicController = createClockAudioCDTMicController(formattedRoomName, {debugging = false})

if myClockAudioCDTMicController then
    print("Optimized ClockAudioCDTMicController created successfully!")
else
    print("ERROR: Failed to create optimized ClockAudioCDTMicController!")
end