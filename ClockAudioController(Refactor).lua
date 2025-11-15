--[[
  ClockAudioCDTMicController - Q-SYS Control Script for ClockAudio CDT 100
  Author: Nikolas Smith
  Date: 2025-09-10
  Version: 2.0
  Description: ClockAudio CDT microphone controller with optimized event handling
  Notes: Refactored per Lua Refactoring Prompt (event-driven, OOP modular)
         - Added comprehensive control validation and error handling
         - Implemented utility functions for efficient array operations
         - Enhanced batch event registration patterns
         - Improved factory pattern with better error messaging
]]--

local controls = {
    compMicBox          = Controls.compMicBox,
    compMicMixer        = Controls.compMicMixer,   
    compCallSync        = Controls.compCallSync,
    compRoomControls    = Controls.compRoomControls,
    txtStatus           = Controls.txtStatus,  
    ledFireAlarm        = Controls.ledFireAlarm,
    ledSystemPower      = Controls.ledSystemPower,
}

-------------------[ Control Validation ]-------------------
local function validateControls()
    local required = {
        "compMicBox", "compMicMixer", "compCallSync", 
        "compRoomControls", "txtStatus"
    }
    
    local optional = {
        "ledFireAlarm", "ledSystemPower"
    }
    
    local missing = {}
    local warnings = {}
    
    -- Check required controls
    for _, name in ipairs(required) do
        if not controls[name] then
            table.insert(missing, name)
        end
    end
    
    -- Check optional controls for warnings
    for _, name in ipairs(optional) do
        if not controls[name] then
            table.insert(warnings, name)
        end
    end
    
    -- Report missing required controls
    if #missing > 0 then
        print("ERROR: ClockAudioCDTMicController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    -- Report optional control warnings
    if #warnings > 0 then
        print("WARNING: ClockAudioCDTMicController - Missing optional controls:")
        for _, name in ipairs(warnings) do
            print("  - " .. name)
        end
    end
    
    return true
end

-------------------[ Control Array Normalization ]-------------------
local function normalizeControlArrays()
    -- Ensure compMicBox is always an array
    if controls.compMicBox and type(controls.compMicBox) ~= "table" then
        controls.compMicBox = {controls.compMicBox}
    elseif not controls.compMicBox then
        controls.compMicBox = {}
    end
    
    -- Validate array indices for mic boxes (should be 1-4)
    local normalizedMicBox = {}
    for i = 1, 4 do
        if controls.compMicBox[i] then
            normalizedMicBox[i] = controls.compMicBox[i]
        end
    end
    controls.compMicBox = normalizedMicBox
end

-------------------[ Utility Functions ]-------------------
local function isArr(obj)
    return type(obj) == "table" and #obj > 0
end

local function getControlArray(control)
    if not control then return {} end
    return isArr(control) and control or {control}
end

local function setProp(obj, prop, value)
    if not obj or not obj[prop] or obj[prop] == value then return false end
    obj[prop] = value
    return true
end

local function bind(control, eventHandler)
    if control and control.EventHandler ~= eventHandler then
        control.EventHandler = eventHandler
        return true
    end
    return false
end

local function bindArray(controlArray, eventHandler)
    local boundCount = 0
    for _, control in ipairs(controlArray or {}) do
        if bind(control, eventHandler) then
            boundCount = boundCount + 1
        end
    end
    return boundCount
end

local function forEach(array, func)
    if not isArr(array) or not func then return 0 end
    local count = 0
    for i, item in ipairs(array) do
        if func(item, i) then
            count = count + 1
        end
    end
    return count
end

-----------------[ Class Constructor ]-------------------
ClockAudioCDTMicController = {}
ClockAudioCDTMicController.__index = ClockAudioCDTMicController

function ClockAudioCDTMicController.new(roomName, config)
    -- Early return for validation failure
    if not validateControls() then
        print("ERROR: ClockAudioCDTMicController constructor failed validation")
        return nil
    end
    
    -- Normalize control arrays early
    normalizeControlArrays()
    
    local self = setmetatable({}, ClockAudioCDTMicController)
    self.roomName = roomName or "ClockAudio CDT"
    self.debugging = (config and config.debugging) or false
    self.clearString = "[Clear]"

    self.componentTypes = {
        callSync = "call_sync",
        micBoxes = "%PLUGIN%_91b57fdec7bd41fb9b9741210ad2a1f3_%FP%_6bb184f66fd3a12efe1844e433fc11c3",
        micMixer = "mixer",
        roomControls = "device_controller_script"
    }       
    self.components = {
        callSync = nil,
        micBoxes = {},
        micMixer = nil,
        roomControls = nil,
        invalid = {}
    }    
    self.state = {
        globalMute = false,
        offHook = false,
        audioPrivacy = false,
        systemPower = true,
        fireAlarm = false
    }
    self.config = {
        toggleInterval = 1.0
    }
    self.controls = controls    
    self:initCDTModule()
    
    return self
end

-----------------[ Debug Helper ]-------------------
function ClockAudioCDTMicController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." CDT] "..str) 
    end
end

-----------------[ Utility Functions ]-------------------
function ClockAudioCDTMicController:getMicBoxCount()
    local count = 0
    for i = 1, 4 do
        if self.components.micBoxes[i] then count = count + 1 end
    end
    return count
end

-----------------[ Component Setup ]-------------------
function ClockAudioCDTMicController:setComponent(controlRef, componentName)
    -- Early return for clear/invalid control reference
    if not controlRef or controlRef.String == self.clearString then
        setProp(controlRef, "Color", "white")
        self:setComponentValid(componentName)
        return nil
    end    
    
    -- Early return for invalid component string
    if not controlRef.String or controlRef.String == "" then
        setProp(controlRef, "String", "[Invalid Component Selected]")
        setProp(controlRef, "Color", "pink")
        self:setComponentInvalid(componentName)
        return nil
    end
    
    -- Try to create the component
    local component = Component.New(controlRef.String)
    if not component then
        setProp(controlRef, "String", "[Invalid Component Selected]")
        setProp(controlRef, "Color", "pink")
        self:setComponentInvalid(componentName)
        return nil
    end    
    
    -- Validate component has controls
    local componentControls = Component.GetControls(component)
    if not componentControls or #componentControls < 1 then
        setProp(controlRef, "String", "[Invalid Component Selected]")
        setProp(controlRef, "Color", "pink")
        self:setComponentInvalid(componentName)
        return nil
    end    
    
    -- Component is valid - set success state
    setProp(controlRef, "Color", "white")
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
    -- Early return if any component is invalid
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid == true then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    
    -- All components are valid
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

function ClockAudioCDTMicController:setupComponents()
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    self.components.micMixer = self:setComponent(controls.compMicMixer, "Mic Mixer")
    for i = 1, 4 do
        if controls.compMicBox[i] then
            self.components.micBoxes[i] = self:setComponent(controls.compMicBox[i], "MicBox"..string.format("%02d", i))
        end
    end
end

-----------------[ Debug Helper ]-------------------
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
                if not box then goto continue end                
                -- Individual LED control: ButtonState 6,8,10,12 control RedBrightnessInput 1,2,3,4
                -- These are toggle buttons for individual microphone control
                local buttons = {6, 8, 10, 12}
                for i = 1, 4 do
                    local buttonState = box['ButtonState '..buttons[i]]
                    local redInput = box['RedBrightnessInput '..i]
                    local greenInput = box['GreenBrightnessInput '..i]
                    
                    if not (buttonState and redInput and greenInput) then goto continue end
                    
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
                
                ::continue::
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
    self.cdtModule.ledToggleTimer.EventHandler = function()
        self.cdtModule.ledState = not self.cdtModule.ledState
        self.cdtModule.setLED(self.cdtModule.ledState)
    end
end

-----------------[ Component Name Discovery ]-------------------
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
        elseif component.Type == self.componentTypes.roomControls and string.match(component.Name, "^compRoomControls") then
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

-----------------[ Event Handler Registration ]-------------------
function ClockAudioCDTMicController:registerEventHandlers()
    local selfRef = self
    
    -- 🎯 Pattern #28: Handler map with direct object references as keys
    local systemHandlerMap = {}
    
    -- Room Controls handlers
    if self.components.roomControls then
        if self.components.roomControls.ledSystemPower then
            systemHandlerMap[self.components.roomControls.ledSystemPower] = function(ctl)
                selfRef.state.systemPower = ctl.Boolean
                if not ctl.Boolean then
                    selfRef.state.globalMute = true
                    selfRef.cdtModule.setHookState(false)
                end
            end
        end
        
        if self.components.roomControls.ledFireAlarm then
            systemHandlerMap[self.components.roomControls.ledFireAlarm] = function(ctl)
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
    
    -- Call Sync handlers
    if self.components.callSync then
        if self.components.callSync["off.hook"] then
            systemHandlerMap[self.components.callSync["off.hook"]] = function(ctl)
                selfRef.cdtModule.setHookState(ctl.Boolean)
            end
        end
        
        if self.components.callSync["mute"] then
            systemHandlerMap[self.components.callSync["mute"]] = function(ctl)
                selfRef.cdtModule.setGlobalMute(ctl.Boolean)
            end
        end
    end
    
    -- 🎯 Batch register all handlers in single loop
    local registeredCount = 0
    for ctrl, handler in pairs(systemHandlerMap) do
        if bind(ctrl, handler) then
            registeredCount = registeredCount + 1
        end
    end
    self:debugPrint("Registered " .. registeredCount .. " system handlers")
    
    -- Register mic and privacy button handlers
    self:registerMicHandlers()
    self:registerPrivacyButtonHandlers()
end

-----------------[ Table-Driven Mic Button Registration ]-------------------
function ClockAudioCDTMicController:registerMicHandlers()
    local selfRef = self    
    local buttonConfigs = {
        {box = 1, buttons = {{6,1,1}, {8,2,2}, {10,3,3}}},
        {box = 2, buttons = {{6,1,4}, {8,2,5}, {10,3,6}, {12,4,7}}},
        {box = 3, buttons = {{6,1,8}, {8,2,9}, {10,3,10}, {12,4,11}}},
        {box = 4, buttons = {{6,1,12}, {8,2,13}, {10,3,14}}}
    }    
    
    -- 🎯 Pattern #28: Build handler map with direct object references
    local micHandlerMap = {}
    for _, config in ipairs(buttonConfigs) do
        local box = self.components.micBoxes[config.box]
        if not box then goto continue end
        
        -- Add handlers for each button in this box
        for _, btn in ipairs(config.buttons) do
            local buttonControl = box['ButtonState '..btn[1]]
            if buttonControl then
                local boxIdx, ledIdx, mixerIdx = config.box, btn[2], btn[3]
                micHandlerMap[buttonControl] = function()
                    selfRef.cdtModule.toggleMic(boxIdx, ledIdx, mixerIdx)
                end
            end
        end
        
        ::continue::
    end
    
    -- 🎯 Batch register all mic handlers in single loop
    local registeredCount = 0
    for ctrl, handler in pairs(micHandlerMap) do
        if bind(ctrl, handler) then
            registeredCount = registeredCount + 1
        end
    end
    
    self:debugPrint("Registered " .. registeredCount .. " mic button handlers")
end

-----------------[ Privacy Button Registration ]-------------------
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
    
    -- 🎯 Pattern #28: Build handler map with direct object references
    local privacyHandlerMap = {}
    for _, config in ipairs(privacyConfigs) do
        local box = self.components.micBoxes[config.box]
        if not box then goto continue end
        
        -- Add handlers for each privacy button in this box
        for _, buttonNum in ipairs(config.buttons) do
            local buttonControl = box['ButtonState '..buttonNum]
            if buttonControl then
                local boxIndex = config.box  -- Capture for closure
                privacyHandlerMap[buttonControl] = function(ctl)
                    -- Early return for non-press events
                    if not ctl.Boolean then return end
                    
                    -- Early return for disabled buttons
                    if ctl.IsDisabled then
                        selfRef:debugPrint("Privacy button "..buttonNum.." on box "..boxIndex.." is disabled - ignoring press")
                        return
                    end            
                    
                    -- Handle valid button press
                    local callSync = selfRef.components.callSync
                    if not callSync or not callSync["mute"] then return end                
                    
                    -- Toggle mute state directly
                    callSync["mute"].Boolean = not callSync["mute"].Boolean
                    selfRef:debugPrint("Privacy button "..buttonNum.." on box "..boxIndex.." toggled mute to "..tostring(callSync["mute"].Boolean))                
                    
                    -- Update LED states to reflect the new privacy state
                    if selfRef.state.offHook then
                        selfRef.cdtModule.updateIndividualLEDs()
                    end
                end
            end
        end
        
        ::continue::
    end
    
    -- 🎯 Batch register all privacy handlers in single loop
    local registeredCount = 0
    for ctrl, handler in pairs(privacyHandlerMap) do
        if bind(ctrl, handler) then
            registeredCount = registeredCount + 1
        end
    end
    
    self:debugPrint("Registered " .. registeredCount .. " privacy button handlers")
end

-----------------[ Initialization ]-------------------
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
        local box = self.components.micBoxes[i]
        if not box then goto continue end
        
        self.cdtModule.updatePrivacyButtonStates(i)

        ::continue::
    end    
    self:debugPrint("Initialization completed with "..self:getMicBoxCount().." mic boxes")
end

function ClockAudioCDTMicController:initializeLEDStates()
    if not self.components.callSync then return end    
    local offHookControl = self.components.callSync["off.hook"]
    local muteControl = self.components.callSync["mute"]
    if not (offHookControl and muteControl) then return end    
    self.state.offHook = offHookControl.Boolean
    self.state.globalMute = muteControl.Boolean
    if self.state.offHook then
        self.cdtModule.updateIndividualLEDs()
    else
        self.cdtModule.turnOffAllLEDs()
    end
end

-----------------[ Emulation/Testing Functions ]-------------------
function ClockAudioCDTMicController:setMicBoxButtonState(boxIndex, buttonNumber, state)
    -- Set individual button state for testing/emulation
    -- boxIndex: 1-4 (which mic box)
    -- buttonNumber: 1-12 (which button on the box)
    -- state: true/false (button state)
    
    -- Validate box index
    if boxIndex < 1 or boxIndex > 4 then
        self:debugPrint("Invalid box index: "..tostring(boxIndex).." (must be 1-4)")
        return false
    end    
    -- Validate button number
    if buttonNumber < 1 or buttonNumber > 12 then
        self:debugPrint("Invalid button number: "..tostring(buttonNumber).." (must be 1-12)")
        return false
    end    
    -- Get box component
    local box = self.components.micBoxes[boxIndex]
    if not box then
        self:debugPrint("Mic box "..boxIndex.." not found")
        return false
    end    
    -- Get button control
    local buttonControl = box['ButtonState '..buttonNumber]
    if not buttonControl then
        self:debugPrint("Button "..buttonNumber.." not found on box "..boxIndex)
        return false
    end    
    -- Set button state
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

-----------------[ Cleanup ]-------------------
function ClockAudioCDTMicController:cleanup()
    self:debugPrint("Starting cleanup...")
    
    -- Stop timers first
    if self.cdtModule and self.cdtModule.ledToggleTimer then
        self.cdtModule.stopLEDToggle()
        self.cdtModule.ledToggleTimer.EventHandler = nil
    end    
    
    -- Clear handlers using batch approach
    self:batchClearHandlers()
    
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

function ClockAudioCDTMicController:batchClearHandlers()
    local clearedCount = 0
    
    -- Clear call sync and room control handlers
    local componentHandlers = {
        {self.components.callSync, {"off.hook", "mute"}},
        {self.components.roomControls, {"ledSystemPower", "ledFireAlarm"}}
    }    
    
    for _, handler in ipairs(componentHandlers) do
        local component, controlNames = handler[1], handler[2]
        if component then
            for _, controlName in ipairs(controlNames) do
                local control = component[controlName]
                if control and control.EventHandler then
                    control.EventHandler = nil
                    clearedCount = clearedCount + 1
                end
            end
        end
    end    
    
    -- Clear mic box button handlers (1-12 buttons per box)
    for i = 1, 4 do
        local box = self.components.micBoxes[i]
        if box then
            for buttonNum = 1, 12 do
                local button = box['ButtonState '..buttonNum]
                if button and button.EventHandler then
                    button.EventHandler = nil
                    clearedCount = clearedCount + 1
                end
            end
        end
    end 
    
    self:debugPrint("Cleared " .. clearedCount .. " event handlers")
end

-----------------[ Factory Function ]-------------------
local function createClockAudioCDTMicController(roomName, config)
    local displayName = tostring(roomName or "ClockAudio CDT")
    print("Creating ClockAudioCDTMicController for: " .. displayName)
    
    -- Validate input parameters
    if config and type(config) ~= "table" then
        print("ERROR: Config parameter must be a table, got " .. type(config))
        return nil
    end
    
    local success, controller = pcall(function()
        -- Constructor handles its own validation and early returns
        local instance = ClockAudioCDTMicController.new(roomName, config)
        if not instance then
            error("Constructor validation failed - see previous error messages")
        end
        
        -- Initialize the instance
        instance:funcInit()
        return instance
    end)
    
    if success and controller then
        print("✓ Successfully created ClockAudioCDTMicController for " .. displayName)
        print("  - Mic boxes connected: " .. controller:getMicBoxCount())
        print("  - Room name: " .. controller.roomName)
        print("  - Debug mode: " .. tostring(controller.debugging))
        return controller
    else
        local errorMsg = controller or "Unknown error"
        print("✗ Failed to create ClockAudioCDTMicController for " .. displayName)
        print("  Error: " .. tostring(errorMsg))
        print("  Check control definitions and component assignments")
        return nil
    end
end

-- Export both class and factory function globally
_G.ClockAudioCDTMicController = ClockAudioCDTMicController
_G.createClockAudioCDTMicController = createClockAudioCDTMicController

-----------------[ Instance Creation ]-------------------
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
-- myClockAudioCDTMicController:pulseMicBoxButton(1, 1)

-- Test (CDT Reed Switch State) Switch on Mic Box 1 (set to 'pressed' state)
-- myClockAudioCDTMicController:setMicBoxButtonState(1, 6, false)