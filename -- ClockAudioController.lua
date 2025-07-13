--[[
  ClockAudioCDTMicController - Q-SYS Control Script for ClockAudio CDT 100
  Author: Nikolas Smith
  Date: 2025-07-13
  Version: 1.0
  Description: ClockAudio CDT microphone controller with optimized event handling
]]--

local controls = {
    compMicBox = Controls.compMicBox,
    compMicMixer = Controls.compMicMixer,   
    compCallSync = Controls.compCallSync,
    compRoomControls = Controls.compRoomControls,
    txtStatus = Controls.txtStatus,
}

--------** Class Constructor **--------
ClockAudioCDTMicController = {}
ClockAudioCDTMicController.__index = ClockAudioCDTMicController

function ClockAudioCDTMicController.new(roomName, config)
    local self = setmetatable({}, ClockAudioCDTMicController)
    self.roomName = roomName or "ClockAudio CDT"
    self.debugging = (config and config.debugging) or false
    self.clearString = "[Clear]"

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        micBoxes = "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3",
        micMixer = "mixer",
        roomControls = "device_controller_script"
    }
    
    -- Direct component references for speed
    self.components = {
        callSync = nil,
        micBoxes = {},
        micMixer = nil,
        roomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        globalMute = false,
        offHook = false,
        audioPrivacy = false,
        systemPower = true,
        fireAlarm = false
    }
    
    -- Configuration
    self.config = {
        toggleInterval = 1.0
    }

    -- Store controls reference for better performance
    self.controls = controls    

    -- Initialize modules
    self:initCDTModule()
    
    return self
end

--------** Debug Helper **--------
function ClockAudioCDTMicController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." CDT] "..str) 
    end
end

--------** Component Setup **--------
function ClockAudioCDTMicController:setComponent(controlRef, componentName)
    if not controlRef or controlRef.String == self.clearString then
        if controlRef then controlRef.Color = "white" end
        self:setComponentValid(componentName)
        return nil
    end
    
    -- Try to create the component first
    local component = Component.New(controlRef.String)
    if not component then
        if controlRef then
            controlRef.String = "[Invalid Component Selected]"
            controlRef.Color = "pink"
        end
        self:setComponentInvalid(componentName)
        return nil
    end
    
    -- Check if component has controls (more reliable validation)
    local controls = Component.GetControls(component)
    if not controls or #controls < 1 then
        if controlRef then
            controlRef.String = "[Invalid Component Selected]"
            controlRef.Color = "pink"
        end
        self:setComponentInvalid(componentName)
        return nil
    end
    
    -- Component is valid
    if controlRef then controlRef.Color = "white" end
    self:setComponentValid(componentName)
    self:debugPrint("Connected to "..componentName)
    return component
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
            if controls.txtStatus then
                controls.txtStatus.String = "Invalid Components"
                controls.txtStatus.Value = 1
            end
            return
        end
    end
    if controls.txtStatus then
        controls.txtStatus.String = "OK"
        controls.txtStatus.Value = 0
    end
end

function ClockAudioCDTMicController:setupComponents()
    -- Batch component setup for speed
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    self.components.micMixer = self:setComponent(controls.compMicMixer, "Mic Mixer")
    
    -- Setup mic boxes in batch
    for i = 1, 4 do
        if controls.compMicBox[i] then
            self.components.micBoxes[i] = self:setComponent(controls.compMicBox[i], "MicBox"..string.format("%02d", i))
        end
    end
end

--------** CDT Module **--------
function ClockAudioCDTMicController:initCDTModule()
    local selfRef = self
    self.cdtModule = {
        toggleMic = function(boxIndex, ledIndex, mixerInput)
            local box = selfRef.components.micBoxes[boxIndex]
            local mixer = selfRef.components.micMixer
            if not box or not mixer then return end
            
            local buttonState = box['ButtonState '..(ledIndex * 2 + 4)]
            if not buttonState then return end
            
            local isActive = buttonState.Boolean
            mixer['input.'..mixerInput..'.mute'].Boolean = not isActive
            
            -- Update the individual LED brightness controls
            selfRef.cdtModule.updateIndividualLEDs()
            
            -- Update privacy button disabled state based on toggle button state
            selfRef.cdtModule.updatePrivacyButtonStates(boxIndex)
        end,
        
        setGlobalMute = function(muteState)
            selfRef.state.globalMute = muteState
            if selfRef.components.callSync then
                selfRef.components.callSync['mute'].Boolean = muteState
            end
            -- Update individual LED brightness controls when off-hook
            if selfRef.state.offHook then
                selfRef.cdtModule.updateIndividualLEDs()
            end
        end,
        
        setHookState = function(hookState)
            selfRef.state.offHook = hookState
            if hookState then
                -- Update individual LED brightness controls when going on-hook
                selfRef.cdtModule.updateIndividualLEDs()
            else
                -- Turn off all individual brightness inputs when going off-hook
                selfRef.cdtModule.turnOffAllLEDs()
            end
        end,
        
        -- LED toggle
        ledToggleTimer = Timer.New(),
        ledState = false,
        
        startLEDToggle = function()
            selfRef.cdtModule.ledToggleTimer:Start(selfRef.config.toggleInterval)
        end,
        
        stopLEDToggle = function()
            selfRef.cdtModule.ledToggleTimer:Stop()
        end,
        
        setLED = function(state)
            selfRef.cdtModule.ledState = state
            local greenValue = state and 1 or 0
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    for ledIndex = 1, 4 do
                        local redBrightnessInput = box['RedBrightnessInput '..ledIndex]
                        local greenBrightnessInput = box['GreenBrightnessInput '..ledIndex]
                        
                        if redBrightnessInput then redBrightnessInput.Position = 0 end
                        if greenBrightnessInput then greenBrightnessInput.Position = greenValue end
                    end
                end
            end
        end,
        updateIndividualLEDs = function()
            if not selfRef.state.offHook then return end
            
            for boxIndex = 1, 4 do
                local box = selfRef.components.micBoxes[boxIndex]
                if box then
                    -- Individual LED control: ButtonState 6,8,10,12 control RedBrightnessInput 1,2,3,4
                    -- These are toggle buttons for individual microphone control
                    local buttons = {6, 8, 10, 12}
                    for i = 1, 4 do
                        local buttonState = box['ButtonState '..buttons[i]]
                        local redInput = box['RedBrightnessInput '..i]
                        local greenInput = box['GreenBrightnessInput '..i]
                        
                        if buttonState and redInput and greenInput then
                            if not buttonState.Boolean then
                                redInput.Position = 0
                                greenInput.Position = 0
                            else
                                if selfRef.state.globalMute then
                                    redInput.Position = 1
                                    greenInput.Position = 0
                                else
                                    redInput.Position = 0
                                    greenInput.Position = 1
                                end
                            end
                        end
                    end
                end
            end
        end,
        
        turnOffAllLEDs = function()
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    for ledIndex = 1, 4 do
                        local redBrightnessInput = box['RedBrightnessInput '..ledIndex]
                        local greenBrightnessInput = box['GreenBrightnessInput '..ledIndex]
                        
                        if redBrightnessInput then redBrightnessInput.Position = 0 end
                        if greenBrightnessInput then greenBrightnessInput.Position = 0 end
                    end
                end
            end
        end,
        
        updatePrivacyButtonStates = function(boxIndex)
            local box = selfRef.components.micBoxes[boxIndex]
            if not box then return end
            
            -- Map of toggle buttons to privacy buttons
            local buttonMap = {
                {toggle = 6, privacy = 1},
                {toggle = 8, privacy = 2},
                {toggle = 10, privacy = 3},
                {toggle = 12, privacy = 4}
            }
            
            for _, mapping in ipairs(buttonMap) do
                local toggleButton = box['ButtonState '..mapping.toggle]
                local privacyButton = box['ButtonState '..mapping.privacy]
                
                if toggleButton and privacyButton then
                    -- Enable privacy button if toggle button is active, disable if not
                    privacyButton.IsDisabled = not toggleButton.Boolean
                    selfRef:debugPrint("Box"..boxIndex.." Privacy Button "..mapping.privacy.." "..(toggleButton.Boolean and "enabled" or "disabled"))
                end
            end
        end
    }
    -- Set up LED toggle timer event handler
    self.cdtModule.ledToggleTimer.EventHandler = function()
        self.cdtModule.ledState = not self.cdtModule.ledState
        self.cdtModule.setLED(self.cdtModule.ledState)
    end
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
        if component.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, component.Name)
        elseif component.Type == self.componentTypes.micBoxes then
            table.insert(namesTable.MicBoxNames, component.Name)
        elseif component.Type == self.componentTypes.roomControls and component.Name:match("^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, component.Name)
        elseif component.Type == self.componentTypes.micMixer then
            table.insert(namesTable.MicMixerNames, component.Name)
        end
    end
    
    for _, nameList in pairs(namesTable) do
        table.sort(nameList)
        table.insert(nameList, self.clearString)
    end
    
    controls.compRoomControls.Choices = namesTable.RoomControlsNames
    controls.compCallSync.Choices = namesTable.CallSyncNames
    controls.compMicMixer.Choices = namesTable.MicMixerNames
    
    for i, control in ipairs(controls.compMicBox) do
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
                    selfRef.cdtModule.setHookState(false)
                end
            end
        end
        
        -- Fire alarm handler - direct LED control
        local fireControl = self.components.roomControls["ledFireAlarm"]
        if fireControl then
            fireControl.EventHandler = function(ctl)
                selfRef.state.fireAlarm = ctl.Boolean
                if ctl.Boolean then
                    selfRef.cdtModule.startLEDToggle()
                    selfRef.state.globalMute = true
                    selfRef.cdtModule.setHookState(false)
                else
                    selfRef.cdtModule.stopLEDToggle()
                    if selfRef.state.offHook then
                        selfRef.cdtModule.setHookState(true)
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
                selfRef.cdtModule.setHookState(ctl.Boolean)
            end
        end
        
        local muteControl = self.components.callSync["mute"]
        if muteControl then
            muteControl.EventHandler = function(ctl)
                selfRef.cdtModule.setGlobalMute(ctl.Boolean)
            end
        end
    end
    
    -- Mic button handlers
    self:registerMicHandlers()
    self:registerPrivacyButtonHandlers()
    
    -- Test button handlers for emulation
    self:registerTestButtonHandlers()
end

--------** Test Button Registration **--------
function ClockAudioCDTMicController:registerTestButtonHandlers()
    -- This method is intentionally empty - test buttons are handled through
    -- the emulation functions like setMicBoxButtonState, pulseMicBoxButton, etc.
    -- No actual test button handlers are needed for the ClockAudio CDT implementation
    self:debugPrint("Test button handlers registered (no physical test buttons)")
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
                        selfRef.cdtModule.toggleMic(boxIdx, ledIdx, mixerIdx)
                    end
                end
            end
        end
    end
end

--------** Privacy Button Registration **--------
function ClockAudioCDTMicController:registerPrivacyButtonHandlers()
    local selfRef = self
    
    -- Privacy buttons: ButtonState 1-4 on each box toggle global mute
    -- These are momentary buttons that provide toggle behavior for privacy
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
                    privacyButton.EventHandler = function(ctl)
                        -- Only respond to button press (true) events, not release (false) events
                        -- AND only if the button is not disabled
                        if ctl.Boolean and not ctl.IsDisabled then
                            local callSync = selfRef.components.callSync
                            if callSync and callSync["mute"] then
                                -- Toggle mute state directly
                                callSync["mute"].Boolean = not callSync["mute"].Boolean
                                selfRef:debugPrint("Privacy button "..buttonNum.." on box "..config.box.." toggled mute to "..tostring(callSync["mute"].Boolean))
                                
                                -- Update LED states to reflect the new privacy state
                                if selfRef.state.offHook then
                                    selfRef.cdtModule.updateIndividualLEDs()
                                end
                            end
                        elseif ctl.Boolean and ctl.IsDisabled then
                            selfRef:debugPrint("Privacy button "..buttonNum.." on box "..config.box.." is disabled - ignoring press")
                        end
                    end
                end
            end
        end
    end
end

--------** Initialization **--------
function ClockAudioCDTMicController:funcInit()
    self:debugPrint("Starting initialization...")
    
    -- Get component names first
    self:getComponentNames()
    
    -- Batch all immediate operations
    self:setupComponents()
    self:registerEventHandlers()
    
    -- Initialize LED states based on current call sync state
    self:initializeLEDStates()
    
    -- Initialize privacy button states based on toggle button states
    for i = 1, 4 do
        if self.components.micBoxes[i] then
            self.cdtModule.updatePrivacyButtonStates(i)
        end
    end
    
    self:debugPrint("Initialization completed with "..self:getMicBoxCount().." mic boxes")
end

function ClockAudioCDTMicController:initializeLEDStates()
    if not self.components.callSync then return end
    
    -- Get current call sync state
    local offHookControl = self.components.callSync["off.hook"]
    local muteControl = self.components.callSync["mute"]
    
    if offHookControl and muteControl then
        self.state.offHook = offHookControl.Boolean
        self.state.globalMute = muteControl.Boolean
        
        -- Set individual LED states based on current call sync state
        if self.state.offHook then
            -- Update individual LED brightness controls
            self.cdtModule.updateIndividualLEDs()
        else
            -- When not off-hook, turn off all individual LEDs
            self.cdtModule.turnOffAllLEDs()
        end
    end
end

--------** Utility Functions **--------
function ClockAudioCDTMicController:getMicBoxCount()
    local count = 0
    for i = 1, 4 do
        if self.components.micBoxes[i] then count = count + 1 end
    end
    return count
end

--------** Emulation/Testing Functions **--------
function ClockAudioCDTMicController:setMicBoxButtonState(boxIndex, buttonNumber, state)
    -- Set individual button state for testing/emulation
    -- boxIndex: 1-4 (which mic box)
    -- buttonNumber: 1-12 (which button on the box)
    -- state: true/false (button state)
    
    if boxIndex < 1 or boxIndex > 4 then
        self:debugPrint("Invalid box index: "..tostring(boxIndex).." (must be 1-4)")
        return false
    end
    
    if buttonNumber < 1 or buttonNumber > 12 then
        self:debugPrint("Invalid button number: "..tostring(buttonNumber).." (must be 1-12)")
        return false
    end
    
    local box = self.components.micBoxes[boxIndex]
    if not box then
        self:debugPrint("Mic box "..boxIndex.." not found")
        return false
    end
    
    local buttonControl = box['ButtonState '..buttonNumber]
    if not buttonControl then
        self:debugPrint("Button "..buttonNumber.." not found on box "..boxIndex)
        return false
    end
    
    buttonControl.Boolean = state
    self:debugPrint("Set Box"..string.format("%02d", boxIndex).." ButtonState "..buttonNumber.." to "..tostring(state))
    return true
end

function ClockAudioCDTMicController:pulseMicBoxButton(boxIndex, buttonNumber, pulseDuration)
    -- Pulse a button (momentary press) for testing/emulation
    -- boxIndex: 1-4 (which mic box)
    -- buttonNumber: 1-12 (which button on the box)
    -- pulseDuration: duration in seconds (optional, defaults to 0.1)
    
    pulseDuration = pulseDuration or 0.2
    
    if boxIndex < 1 or boxIndex > 4 then
        self:debugPrint("Invalid box index: "..tostring(boxIndex).." (must be 1-4)")
        return false
    end
    
    if buttonNumber < 1 or buttonNumber > 12 then
        self:debugPrint("Invalid button number: "..tostring(buttonNumber).." (must be 1-12)")
        return false
    end
    
    local box = self.components.micBoxes[boxIndex]
    if not box then
        self:debugPrint("Mic box "..boxIndex.." not found")
        return false
    end
    
    local buttonControl = box['ButtonState '..buttonNumber]
    if not buttonControl then
        self:debugPrint("Button "..buttonNumber.." not found on box "..boxIndex)
        return false
    end
    
    -- Press the button
    buttonControl.Boolean = true
    self:debugPrint("Pulsing Box"..string.format("%02d", boxIndex).." ButtonState "..buttonNumber.." for "..pulseDuration.."s")
    
    -- Create a timer to release the button after the pulse duration
    local pulseTimer = Timer.New()
    local selfRef = self  -- Capture self reference for timer callback
    pulseTimer.EventHandler = function()
        buttonControl.Boolean = false
        selfRef:debugPrint("Released Box"..string.format("%02d", boxIndex).." ButtonState "..buttonNumber)
        pulseTimer:Stop()
    end
    
    pulseTimer:Start(pulseDuration)
    return true
end

function ClockAudioCDTMicController:setMicBoxLEDState(boxIndex, ledNumber, color, state)
    -- Set individual LED state for testing/emulation
    -- boxIndex: 1-4 (which mic box)
    -- ledNumber: 1-4 (which LED on the box)
    -- color: "Red" or "Green"
    -- state: true/false (LED state)
    
    if boxIndex < 1 or boxIndex > 4 then
        self:debugPrint("Invalid box index: "..tostring(boxIndex).." (must be 1-4)")
        return false
    end
    
    if ledNumber < 1 or ledNumber > 4 then
        self:debugPrint("Invalid LED number: "..tostring(ledNumber).." (must be 1-4)")
        return false
    end
    
    if color ~= "Red" and color ~= "Green" then
        self:debugPrint("Invalid color: "..tostring(color).." (must be 'Red' or 'Green')")
        return false
    end
    
    local box = self.components.micBoxes[boxIndex]
    if not box then
        self:debugPrint("Mic box "..boxIndex.." not found")
        return false
    end
    
    local ledStateControl = box[color..'State '..ledNumber]
    local ledBrightnessControl = box[color..'Brightness '..ledNumber]
    
    if not ledStateControl or not ledBrightnessControl then
        self:debugPrint("LED "..color.." "..ledNumber.." not found on box "..boxIndex)
        return false
    end
    
    ledStateControl.Boolean = state
    ledBrightnessControl.Position = state and 1 or 0
    self:debugPrint("Set Box"..string.format("%02d", boxIndex).." "..color.."State "..ledNumber.." to "..tostring(state))
    return true
end

function ClockAudioCDTMicController:setMicBoxGlobalLED(boxIndex, color, state)
    -- Set global LED state for testing/emulation (DEPRECATED - using individual controls only)
    -- boxIndex: 1-4 (which mic box)
    -- color: "Red" or "Green"
    -- state: true/false (LED state)
    
    if boxIndex < 1 or boxIndex > 4 then
        self:debugPrint("Invalid box index: "..tostring(boxIndex).." (must be 1-4)")
        return false
    end
    
    if color ~= "Red" and color ~= "Green" then
        self:debugPrint("Invalid color: "..tostring(color).." (must be 'Red' or 'Green')")
        return false
    end
    
    local box = self.components.micBoxes[boxIndex]
    if not box then
        self:debugPrint("Mic box "..boxIndex.." not found")
        return false
    end
    
    -- Set all individual LEDs of the specified color for this box
    for ledIndex = 1, 4 do
        local brightnessInput = box[color..'BrightnessInput '..ledIndex]
        if brightnessInput then
            brightnessInput.Position = state and 1 or 0
        end
    end
    
    self:debugPrint("Set Box"..string.format("%02d", boxIndex).." all "..color.." individual LEDs to "..tostring(state))
    return true
end

-- Convenience functions for common testing scenarios
function ClockAudioCDTMicController:testMicBox1()
    -- Test Box01 specific functions
    self:setMicBoxButtonState(1, 1, true)   -- Set ButtonState 1 to True (Momentary)
    self:setMicBoxButtonState(1, 6, true)   -- Set ButtonState 6 to True (Toggle)
    self:debugPrint("Tested Box01 button states")
end

function ClockAudioCDTMicController:testMicBox2()
    -- Test Box02 specific functions
    self:setMicBoxButtonState(2, 1, true)   -- Set ButtonState 1 to True (Momentary)
    self:setMicBoxButtonState(2, 6, true)   -- Set ButtonState 6 to True (Toggle)
    self:debugPrint("Tested Box02 button states")
end

function ClockAudioCDTMicController:testMicBox3()
    -- Test Box03 specific functions
    self:setMicBoxButtonState(3, 1, true)   -- Set ButtonState 1 to True (Momentary)
    self:setMicBoxButtonState(3, 6, true)   -- Set ButtonState 6 to True (Toggle)
    self:debugPrint("Tested Box03 button states")
end

function ClockAudioCDTMicController:testMicBox4()
    -- Test Box04 specific functions
    self:setMicBoxButtonState(4, 1, true)   -- Set ButtonState 1 to True (Momentary)
    self:setMicBoxButtonState(4, 6, true)   -- Set ButtonState 6 to True (Toggle)
    self:debugPrint("Tested Box04 button states")
end

function ClockAudioCDTMicController:testAllBoxes()
    -- Test all boxes with different patterns
    for boxIndex = 1, 4 do
        -- Test buttons 1 and 6 on each box
        self:setMicBoxButtonState(boxIndex, 1, true)
        self:setMicBoxButtonState(boxIndex, 6, true)
        
        -- Test LEDs with alternating colors
        for ledNumber = 1, 4 do
            local color = (ledNumber % 2 == 0) and "Green" or "Red"
            self:setMicBoxLEDState(boxIndex, ledNumber, color, true)
        end
        
        -- Test individual LEDs (replacing global LED tests)
        for ledNumber = 1, 4 do
            self:setMicBoxLEDState(boxIndex, ledNumber, "Red", true)
            self:setMicBoxLEDState(boxIndex, ledNumber, "Green", true)
        end
    end
    self:debugPrint("Tested all boxes with comprehensive patterns")
end

function ClockAudioCDTMicController:clearAllLEDs()
    -- Clear all LEDs on all boxes
    for boxIndex = 1, 4 do
        for ledNumber = 1, 4 do
            self:setMicBoxLEDState(boxIndex, ledNumber, "Red", false)
            self:setMicBoxLEDState(boxIndex, ledNumber, "Green", false)
        end
    end
    self:debugPrint("Cleared all LEDs on all boxes")
end

--------** Cleanup **--------
function ClockAudioCDTMicController:cleanup()
    -- Stop timers
    if self.cdtModule and self.cdtModule.ledToggleTimer then
        self.cdtModule.stopLEDToggle()
        self.cdtModule.ledToggleTimer.EventHandler = nil
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

-- Test Privacy buttons (CDT Touch Switch State) (uncomment to test button pulsing)
myClockAudioCDTMicController:pulseMicBoxButton(1, 1)

-- Test (CDT Reed Switch State) Switch on Mic Box 1 (set to 'pressed' state)
myClockAudioCDTMicController:setMicBoxButtonState(1, 6, false)