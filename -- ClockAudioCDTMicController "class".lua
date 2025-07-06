--[[
  ClockAudioCDTMicController - Optimized Q-SYS Control Script
  Author: Refactored for Performance
  Date: 2025-01-27
  Version: 2.0
  Description: High-performance ClockAudio CDT microphone controller with direct event handling
]]--

-- Define control references with nil checks
local controls = {
    compMicBox = Controls.compMicBox or {},
    compMicMixer = Controls.compMicMixer,   
    compRoomControls = Controls.compRoomControls,
    compCallSync = Controls.compCallSync,
    txtStatus = Controls.txtStatus,
    -- Test control for hook state emulation only
    btnTestHookState = Controls.btnTestHookState,
}

-- Validate required controls exist
local function validateControls()
    local missingControls = {}
    
    if not controls.compMicBox then
        table.insert(missingControls, "compMicBox")
    end
    
    if not controls.compMicMixer then
        table.insert(missingControls, "compMicMixer")
    end
    
    if not controls.compCallSync then
        table.insert(missingControls, "compCallSync")
    end
    
    if not controls.compRoomControls then
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
    
    -- Instance properties
    self.roomName = roomName or "ClockAudio CDT"
    self.debugging = (config and config.debugging) or false
    self.clearString = "[Clear]"
    
    -- Store reference to controls
    self.controls = controls

    -- Component type definitions
    self.componentTypes = {
        callSync = "call_sync",
        micBoxes = "usb_uvc",
        micMixer = "mixer",
        roomControls = (comp.Type == "device_controller_script" and string.match(comp.Name, "^compRoomControls"))
    }
    -- Component references - direct access for speed
    self.components = {
        callSync = nil,
        micBoxes = {}, -- Array for direct indexing
        micMixer = nil,
        roomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        globalMute = false,
        offHook = false,
        privacyEnabled = false,
        testMode = false
    }
    
    -- Configuration
    self.config = {
        ledDelay = 0.2,
        brightnessDelay = 2.0,
        initDelay = 0.4
    }
    
    -- Initialize modules
    self:initLEDModule()
    self:initMicModule()
    self:initTestModule()
    
    return self
end

--------** Debug Helper **--------
function ClockAudioCDTMicController:debugPrint(str)
    if self.debugging then 
        print("["..self.roomName.." Debug] "..str) 
    end
end

--------** Room Controls Component **--------
function ClockAudioCDTMicController:setRoomControlsComponent()
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    if self.components.roomControls ~= nil then
        -- Add event handlers for system power and fire alarm
        local this = self  -- Capture self for use in handlers

        -- System Power Handler
        self.components.roomControls["ledSystemPower"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:debugPrint("System Power On")
            else
                this:debugPrint("System Power Off")
                self.micModule.setMute(true)
                self.micModule.setLED(false)
            end
        end

        -- Fire Alarm Handler
        self.components.roomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean then
                this:debugPrint("Fire Alarm Active")
                this.micModule.startLEDToggle()
                this.micModule.setMute(true)
                this.micModule.setLED(false)
            else
                this.micModule.stopLEDToggle()
                if this.components.callSync["off.hook"].Boolean then
                    this:debugPrint("Fire Alarm Cleared and Call is Off-Hook")
                    this.micModule.setMute(false)
                    this.micModule.setLED(true)
                else
                    this:debugPrint("Fire Alarm Cleared and Call is On-Hook")
                    this.micModule.setMute(true)
                    this.micModule.setLED(false)
                end
            end
        end
    end
end

--------** Call Sync Component **--------
function ClockAudioCDTMicController:setCallSyncComponent()
    self.components.callSync = self:setComponent(controls.compCallSync, "Call Sync")
    if self.components.callSync ~= nil then
        local this = self  -- Capture self for use in handlers
        
        -- Handle off-hook state changes
        self.components.callSync["off.hook"].EventHandler = function(ctl)
            local state = ctl.Boolean
            this:debugPrint("Call Sync Off Hook State: " .. tostring(state))
            -- Update CDT LED state based on off-hook
            this.micModule.setLED(state)
        end
        
        -- Handle mute state changes - directly control LED colors
        self.components.callSync["mute"].EventHandler = function(ctl)
            local muteState = ctl.Boolean
            this:debugPrint("Call Sync Mute State: " .. tostring(muteState))
            
            -- Direct LED control based on mute state
            if muteState then
                this.ledModule.setAllRedOn()
                this.ledModule.setAllGreenOff()
            else
                this.ledModule.setAllGreenOn()
                this.ledModule.setAllRedOff()
            end
        end
    end
end

--------** Safe Component Access **--------
function ClockAudioCDTMicController:safeComponentAccess(component, control, action, value)
    if not component or not component[control] then return false end
    local ok, result = pcall(function()
        if action == "set" then component[control].Boolean = value
        elseif action == "setPosition" then component[control].Position = value
        elseif action == "setString" then component[control].String = value
        elseif action == "trigger" then component[control]:Trigger()
        elseif action == "get" then return component[control].Boolean
        elseif action == "getPosition" then return component[control].Position
        elseif action == "getString" then return component[control].String
        end
        return true
    end)
    if not ok then self:debugPrint("Component access error: "..tostring(result)) end
    return ok and result
end

--------** Component Management **--------
function ClockAudioCDTMicController:setComponent(ctrl, componentType)
    local componentName = ctrl and ctrl.String or nil
    if not componentName or componentName == "" or componentName == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        if ctrl then
            ctrl.String = "[Invalid Component Selected]"
            ctrl.Color = "pink"
        end
        self:setComponentInvalid(componentType)
        return nil
    else
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return Component.New(componentName)
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

--------** LED Module **--------
function ClockAudioCDTMicController:initLEDModule()
    local selfRef = self
    self.ledModule = {
        -- Direct LED state management
        setAllRedOff = function()
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    box['GlobalRedState'].Boolean = false
                    box['GlobalRedBrightness'].Position = 0
                end
            end
        end,
        
        setAllGreenOn = function()
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    box['GlobalGreenState'].Boolean = true
                    box['GlobalGreenBrightness'].Position = selfRef.state.offHook and 1 or 0
                end
            end
        end,
        
        setAllRedOn = function()
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    box['GlobalRedState'].Boolean = true
                    box['GlobalRedBrightness'].Position = selfRef.state.offHook and 1 or 0
                end
            end
        end,
        
        setAllGreenOff = function()
            for i = 1, 4 do
                local box = selfRef.components.micBoxes[i]
                if box then
                    box['GlobalGreenState'].Boolean = false
                    box['GlobalGreenBrightness'].Position = 0
                end
            end
        end,
        
        -- Individual LED management
        setIndividualLED = function(boxIndex, ledIndex, isActive, isRed)
            local box = selfRef.components.micBoxes[boxIndex]
            if not box then return end
            
            local color = isRed and "Red" or "Green"
            local brightness = isActive and 1 or 0
            
            box[color..'State '..ledIndex].Boolean = isActive
            box[color..'Brightness '..ledIndex].Position = brightness
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
        -- Direct mute/unmute with immediate feedback
        toggleMic = function(boxIndex, ledIndex, mixerInput)
            local box = selfRef.components.micBoxes[boxIndex]
            local mixer = selfRef.components.micMixer
            if not box or not mixer then return end
            
            local buttonState = box['ButtonState '..(ledIndex * 2 + 4)].Boolean
            local isActive = buttonState
            
            -- Direct mixer control -- no function calls
            mixer['input.'..mixerInput..'.mute'].Boolean = not isActive
            
            -- Immediate LED feedback
            if isActive then
                if selfRef.state.globalMute then
                    selfRef.ledModule.setIndividualLED(boxIndex, ledIndex, true, true)
                else
                    selfRef.ledModule.setIndividualLED(boxIndex, ledIndex, true, false)
                end
            else
                selfRef.ledModule.setIndividualLED(boxIndex, ledIndex, false, false)
            end
        end,
        
        -- Global mute with immediate visual feedback
        setGlobalMute = function(muteState)
            selfRef.state.globalMute = muteState
            local hid = selfRef.components.callSync
            if hid then
                hid['mute'].Boolean = muteState
            end
            
            if muteState then
                selfRef.ledModule.setAllGreenOff()
                Timer.CallAfter(function()
                    selfRef.ledModule.setAllRedOn()
                end, selfRef.config.ledDelay)
            else
                selfRef.ledModule.setAllRedOff()
                Timer.CallAfter(function()
                    selfRef.ledModule.setAllGreenOn()
                end, self.config.ledDelay)
            end
        end,
        
        -- Hook state management
        setHookState = function(hookState)
            selfRef.state.offHook = hookState
            if hookState then
                if not selfRef.state.globalMute then
                    selfRef.ledModule.setAllRedOff()
                    selfRef.ledModule.setAllGreenOn()
                else
                    selfRef.ledModule.setAllGreenOff()
                    selfRef.ledModule.setAllRedOn()
                end
            else
                selfRef.ledModule.setAllGreenOff()
                selfRef.ledModule.setAllRedOff()
            end
        end,
        
        -- LED toggle functionality
        ledToggleTimer = Timer.New(),
        ledState = false,

        startLEDToggle = function()
            selfRef.micModule.ledToggleTimer:Start(1.5) -- 1.5 second interval
            selfRef:debugPrint("Started LED toggle timer")
        end,

        stopLEDToggle = function()
            selfRef.micModule.ledToggleTimer:Stop()
            selfRef:debugPrint("Stopped LED toggle timer")
        end,
        
        -- Set LED state for toggle functionality
        setLED = function(state)
            selfRef.micModule.ledState = state
            if state then
                selfRef.ledModule.setAllGreenOn()
                selfRef.ledModule.setAllRedOff()
            else
                selfRef.ledModule.setAllGreenOff()
                selfRef.ledModule.setAllRedOff()
            end
        end,
        
        -- Set mute state (alias for setGlobalMute for compatibility)
        setMute = function(muteState)
            selfRef.micModule.setGlobalMute(muteState)
        end
    }

    -- Set up LED toggle timer handler
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
    if controls.btnTestHookState then
        controls.btnTestHookState.EventHandler = function(ctl)
            if ctl.Boolean then
                selfRef.testModule.toggleHookState()
            end
        end
    end
    
    self:debugPrint("Hook state test control handler registered")
end

function ClockAudioCDTMicController:clearTestControlHandlers()
    -- Clear hook state test control event handler
    if controls.btnTestHookState then
        controls.btnTestHookState.EventHandler = nil
    end
    
    self:debugPrint("Hook state test control handler cleared")
end

--------** Component Name Discovery **--------
function ClockAudioCDTMicController:getComponentNames()
    local namesTable = {
        RoomControlsNames = {},
        CallSyncNames = {},
        MicBoxNames = {},
        MicMixerNames = {},
    }

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == self.componentTypes.callSync then
            table.insert(namesTable.CallSyncNames, v.Name)
        elseif v.Type == self.componentTypes.micBoxes then
            table.insert(namesTable.MicBoxNames, v.Name)
        elseif v.Type == self.componentTypes.roomControls then
            table.insert(namesTable.RoomControlsNames, v.Name)
        elseif v.Type == self.componentTypes.micMixer then
            table.insert(namesTable.MicMixerNames, v.Name)
        end
    end

    for i, v in pairs(namesTable) do
        table.sort(v)
        table.insert(v, self.clearString)
    end

    -- Use local controls table with nil checks
    if controls.compRoomControls then
        controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end
    
    if controls.compCallSync then
        controls.compCallSync.Choices = namesTable.CallSyncNames
    end
    
    if controls.compMicMixer then
        controls.compMicMixer.Choices = namesTable.MicMixerNames
    end
    
    -- Set choices for each MicBox device control in the table
    if controls.compMicBox then
        for i, v in ipairs(controls.compMicBox) do
            if v then
                v.Choices = namesTable.MicBoxNames
            end
        end
    end
end

--------** Event Handler Registration - Direct and Fast **--------
function ClockAudioCDTMicController:registerEventHandlers()
    local selfRef = self
    
    -- HID Hook state
    if self.components.callSync and self.components.callSync['off.hook'] then
        self.components.callSync['off.hook'].EventHandler = function()
            selfRef.micModule.setHookState(self.components.callSync['off.hook'].Boolean)
        end
        -- HID Mute toggle
        self.components.callSync['mute'].EventHandler = function()
            selfRef.micModule.setGlobalMute(self.components.callSync['mute'].Boolean)
        end
    end
    
    -- Individual mic button handlers - direct and fast
    self:registerMicButtonHandlers()
    
    self:debugPrint("Event handlers registered")
end

--------** Mic Button Handlers - Optimized **--------
function ClockAudioCDTMicController:registerMicButtonHandlers()
    local selfRef = self
    
    -- Helper function for ButtonState 1-4 callSync mute control
    local function createCallSyncMuteHandler(micBoxNum)
        return function()
            if selfRef.components.callSync and selfRef.components.callSync["mute"] then
                local currentMuteState = selfRef.components.callSync["mute"].Boolean
                selfRef.components.callSync["mute"].Boolean = not currentMuteState
                selfRef:debugPrint("MicBox" .. string.format("%02d", micBoxNum) .. " ButtonState 1-4: Toggled callSync mute to " .. tostring(not currentMuteState))
            end
        end
    end
    
    -- MicBox01 handlers
    local micBox01 = self.components.micBoxes[1]
    if micBox01 then
        -- ButtonState 1-4 handlers for callSync mute control
        micBox01['ButtonState 1'].EventHandler = createCallSyncMuteHandler(1)
        micBox01['ButtonState 2'].EventHandler = createCallSyncMuteHandler(1)
        micBox01['ButtonState 3'].EventHandler = createCallSyncMuteHandler(1)
        micBox01['ButtonState 4'].EventHandler = createCallSyncMuteHandler(1)
        
        -- ButtonState 6, 8, 10 handlers
        micBox01['ButtonState 6'].EventHandler = function()
            selfRef.micModule.toggleMic(1, 1, 1)
        end
        micBox01['ButtonState 8'].EventHandler = function()
            selfRef.micModule.toggleMic(1, 2, 2)
        end
        micBox01['ButtonState 10'].EventHandler = function()
            selfRef.micModule.toggleMic(1, 3, 3)
        end
    end
    
    -- MicBox02 handlers
    local micBox02 = self.components.micBoxes[2]
    if micBox02 then
        -- ButtonState 1-4 handlers for callSync mute control
        micBox02['ButtonState 1'].EventHandler = createCallSyncMuteHandler(2)
        micBox02['ButtonState 2'].EventHandler = createCallSyncMuteHandler(2)
        micBox02['ButtonState 3'].EventHandler = createCallSyncMuteHandler(2)
        micBox02['ButtonState 4'].EventHandler = createCallSyncMuteHandler(2)
        
        -- ButtonState 6, 8, 10, 12 handlers
        micBox02['ButtonState 6'].EventHandler = function()
            selfRef.micModule.toggleMic(2, 1, 4)
        end
        micBox02['ButtonState 8'].EventHandler = function()
            selfRef.micModule.toggleMic(2, 2, 5)
        end
        micBox02['ButtonState 10'].EventHandler = function()
            selfRef.micModule.toggleMic(2, 3, 6)
        end
        micBox02['ButtonState 12'].EventHandler = function()
            selfRef.micModule.toggleMic(2, 4, 7)
        end
    end
    
    -- MicBox03 handlers
    local micBox03 = self.components.micBoxes[3]
    if micBox03 then
        -- ButtonState 1-4 handlers for callSync mute control
        micBox03['ButtonState 1'].EventHandler = createCallSyncMuteHandler(3)
        micBox03['ButtonState 2'].EventHandler = createCallSyncMuteHandler(3)
        micBox03['ButtonState 3'].EventHandler = createCallSyncMuteHandler(3)
        micBox03['ButtonState 4'].EventHandler = createCallSyncMuteHandler(3)
        
        -- ButtonState 6, 8, 10, 12 handlers
        micBox03['ButtonState 6'].EventHandler = function()
            selfRef.micModule.toggleMic(3, 1, 8)
        end
        micBox03['ButtonState 8'].EventHandler = function()
            selfRef.micModule.toggleMic(3, 2, 9)
        end
        micBox03['ButtonState 10'].EventHandler = function()
            selfRef.micModule.toggleMic(3, 3, 10)
        end
        micBox03['ButtonState 12'].EventHandler = function()
            selfRef.micModule.toggleMic(3, 4, 11)
        end
    end
    
    -- MicBox04 handlers
    local micBox04 = self.components.micBoxes[4]
    if micBox04 then
        -- ButtonState 1-4 handlers for callSync mute control
        micBox04['ButtonState 1'].EventHandler = createCallSyncMuteHandler(4)
        micBox04['ButtonState 2'].EventHandler = createCallSyncMuteHandler(4)
        micBox04['ButtonState 3'].EventHandler = createCallSyncMuteHandler(4)
        micBox04['ButtonState 4'].EventHandler = createCallSyncMuteHandler(4)
        
        -- ButtonState 6, 8, 10 handlers
        micBox04['ButtonState 6'].EventHandler = function()
            selfRef.micModule.toggleMic(4, 1, 12)
        end
        micBox04['ButtonState 8'].EventHandler = function()
            selfRef.micModule.toggleMic(4, 2, 13)
        end
        micBox04['ButtonState 10'].EventHandler = function()
            selfRef.micModule.toggleMic(4, 3, 14)
        end
    end
end

--------** Component Setup **--------
function ClockAudioCDTMicController:setupComponents()
    -- Get component names first
    self:getComponentNames()
    
    -- Set up components using setComponent for proper validation
    self:setRoomControlsComponent()
    self:setCallSyncComponent()
    
    -- Set up mic mixer component
    if controls.compMicMixer then
        self.components.micMixer = self:setComponent(controls.compMicMixer, "Mic Mixer")
    end
    
    -- Set up mic boxes using the table of controls
    if controls.compMicBox then
        for i, control in ipairs(controls.compMicBox) do
            if control then
                local componentName = control.String
                if componentName and componentName ~= "" and componentName ~= self.clearString then
                    self.components.micBoxes[i] = Component.New(componentName)
                end
            end
        end
    end
    
    self:debugPrint("Components initialized")
end

--------** Initialization **--------
function ClockAudioCDTMicController:funcInit()
    if self.debugging then self:debugPrint("Starting initialization...") end
    
    -- Cache controls first for faster access
    self:cacheControls()
    
    -- Parallel operations where possible
    self:setupComponents()
    self:registerEventHandlers()
    self:performSystemInitialization()
    
    -- Update LED states after initialization
    self.ledModule.updateAllLEDs()
    
    -- Enable test mode for hook state emulation
    self:enableTestModeIfNoCallSync()
    
    if self.debugging then 
        self:debugPrint("Initialized with "..self:getMicBoxCount().." mic boxes") 
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

--------** Cache Controls for Performance **--------
function ClockAudioCDTMicController:cacheControls()
    -- Cache frequently accessed controls for faster access
    self.cachedControls = {
        -- roomName will be read from room controls component
    }
end

--------** Get Mic Box Count **--------
function ClockAudioCDTMicController:getMicBoxCount()
    local count = 0
    for i = 1, 4 do
        if self.components.micBoxes[i] then
            count = count + 1
        end
    end
    return count
end

--------** Internal System Initialization **--------
function ClockAudioCDTMicController:performSystemInitialization()
    -- Set initial mute state based on call sync mute state
    if self.components.callSync and self.components.callSync["mute"] then
        local initialMuteState = self.components.callSync["mute"].Boolean
        self.micModule.setGlobalMute(initialMuteState)
        if self.debugging then
            self:debugPrint("System initialization completed with mute state: " .. tostring(initialMuteState))
        end
    else
        if self.debugging then
            self:debugPrint("System initialization completed - no call sync mute control available")
        end
    end
end

--------** Cleanup **--------
function ClockAudioCDTMicController:cleanup()
    -- Stop LED toggle timer if running
    if self.micModule and self.micModule.ledToggleTimer then
        self.micModule.stopLEDToggle()
        self.micModule.ledToggleTimer.EventHandler = nil
    end
    
    -- Clear test mode if active
    if self.testModule then
        self.testModule.disableTestMode()
    end
    
    -- Clear event handlers directly
    if self.components.callSync then
        if self.components.callSync["off.hook"] then 
            self.components.callSync["off.hook"].EventHandler = nil 
        end
    end
    
    -- Clear mic box event handlers
    for i = 1, 4 do
        local box = self.components.micBoxes[i]
        if box then
            -- Clear ButtonState 1-4 handlers (callSync mute control)
            for buttonNum = 1, 4 do
                local buttonState = box['ButtonState '..buttonNum]
                if buttonState then
                    buttonState.EventHandler = nil
                end
            end
            
            -- Clear button state handlers (existing ButtonState 6, 8, 10, 12)
            for buttonNum = 6, 12, 2 do
                local buttonState = box['ButtonState '..buttonNum]
                if buttonState then
                    buttonState.EventHandler = nil
                end
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
    
    -- Clear cached controls
    self.cachedControls = {}
    
    if self.debugging then self:debugPrint("Cleanup completed") end
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
        print("Successfully created ClockAudioCDTMicController for "..roomName)
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