--[[
  Planar DisplayWallController - Q-SYS Control Script for Planar Display Wall
  Author: Nikolas Smith, Q-SYS
  Date: 2025-07-06
  Version: 1.3
  Description: Controls Planar Display Wall components with power management,
  input switching, and display wall configuration. 
  Integrates with SystemAutomationController.
]]--

-- Display Control Configuration (easily changeable for different manufacturers)
local displayControls = {
    -- Power Controls
    powerOn = "PowerOn",
    powerOff = "PowerOff", 
    powerIsOn = "PowerIsOn",
    powerIsOff = "PowerIsOff",
    
     --[[
    Input Controls (Option 1: ComboBox method) 
    vInputSelectComboBox = "InputSelectComboBox",
    vInputStatusLED = "InputStatus",
    ]]--
    
    -- Input Controls (Option 2: Button method)
    inputSelectButtons = "VideoInputs ",
    inputNames = "InputNames ",
    currentInput = "CurrentInput ",
    
    -- Wall Configuration
    wallMode = "WallMode",
    wallPosition = "WallPosition"
}

-- Validate required controls exist
local function validateControls()
    if not Controls.txtStatus or not Controls.devDisplays then
        print("ERROR: Missing required controls. Please check your Q-SYS design.")
        return false
    end
    return true
end

--------** Class Definition **--------
PlanarDisplayWallController = {}
PlanarDisplayWallController.__index = PlanarDisplayWallController

function PlanarDisplayWallController.new(roomName, config)
    local self = setmetatable({}, PlanarDisplayWallController)
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        displays = "%PLUGIN%_404F4311-A38D-4891-AF61-709B8F48A6E1_%FP%_77008e895ac50ad 1242e3dee981c5e4", -- Planar Display
        roomControls = "device_controller_script" -- Will be filtered to only those starting with "compRoomControls"
    }
    
    -- Component storage
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        displayWallMode = "Single", -- Single, 2x2, 3x3, etc.
        lastInput = "HDMI1",
        powerState = false,
        isWarming = false,
        isCooling = false
    }
    
    -- Configuration
    self.config = {
        maxDisplays = config and config.maxDisplays or 9, -- Maximum number of displays supported
        defaultInput = "HDMI1",
        displayWallModes = {"Single", "2x2", "3x3", "4x4", "Custom"},
        inputChoices = {"HDMI1", "HDMI2", "DisplayPort", "USB-C"}
    }
    
    -- Input to button mapping
    self.inputButtonMap = {
        HDMI1 = 1, HDMI2 = 2, DisplayPort = 3, USB_C = 4,
        DVI = 5, VGA = 6, Component = 7, Composite = 8, S_Video = 9, RF = 10
    }
    
    -- Timers
    self.timers = {
        warmup = Timer.New(),
        cooldown = Timer.New()
    }
    
    -- Timer Configuration (instance-specific, dynamically updated from room controls component)
    self.timerConfig = {
        warmupTime = 7,  -- Default fallback values
        cooldownTime = 5
    }
    
    -- Initialize modules
    self:initDisplayModule()
    self:initPowerModule()
    
    -- Initialize timer configuration
    self:updateTimerConfigFromComponent()
    return self
end

--------** Dynamic Timer Configuration **--------
function PlanarDisplayWallController:updateTimerConfigFromComponent()
    -- Default fallback values
    local defaultWarmupTime = 7
    local defaultCooldownTime = 5
    
    if self.components.compRoomControls then
        local success, result = pcall(function()
            -- Try to get warmup time from room controls component
            if self.components.compRoomControls["warmupTime"] then
                local warmupTime = self.components.compRoomControls["warmupTime"].Value
                if warmupTime and warmupTime > 0 then
                    self.timerConfig.warmupTime = warmupTime
                    self:debugPrint("Updated warmup time from component: " .. warmupTime .. " seconds")
                else
                    self.timerConfig.warmupTime = defaultWarmupTime
                    self:debugPrint("Using default warmup time: " .. defaultWarmupTime .. " seconds")
                end
            else
                self.timerConfig.warmupTime = defaultWarmupTime
                self:debugPrint("Using default warmup time: " .. defaultWarmupTime .. " seconds")
            end
            
            -- Try to get cooldown time from room controls component
            if self.components.compRoomControls["cooldownTime"] then
                local cooldownTime = self.components.compRoomControls["cooldownTime"].Value
                if cooldownTime and cooldownTime > 0 then
                    self.timerConfig.cooldownTime = cooldownTime
                    self:debugPrint("Updated cooldown time from component: " .. cooldownTime .. " seconds")
                else
                    self.timerConfig.cooldownTime = defaultCooldownTime
                    self:debugPrint("Using default cooldown time: " .. defaultCooldownTime .. " seconds")
                end
            else
                self.timerConfig.cooldownTime = defaultCooldownTime
                self:debugPrint("Using default cooldown time: " .. defaultCooldownTime .. " seconds")
            end
        end)
        
        if not success then
            self:debugPrint("Warning: Failed to update timer config from component: " .. tostring(result))
            -- Set fallback values on error
            self.timerConfig.warmupTime = defaultWarmupTime
            self.timerConfig.cooldownTime = defaultCooldownTime
        end
    else
        -- No room controls component available, use defaults
        self.timerConfig.warmupTime = defaultWarmupTime
        self.timerConfig.cooldownTime = defaultCooldownTime
        self:debugPrint("No room controls component available, using default timing values")
    end
end

function PlanarDisplayWallController:getTimerConfig(isWarmup)
    -- Update timer config from component first
    self:updateTimerConfigFromComponent()
    
    if isWarmup then
        return self.timerConfig.warmupTime
    else
        return self.timerConfig.cooldownTime
    end
end

--------** Debug Helper **--------
function PlanarDisplayWallController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Input Button Mapping **--------
function PlanarDisplayWallController:getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = self.inputButtonMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

--------** Safe Component Access **--------
function PlanarDisplayWallController:safeComponentAccess(component, control, action, value)
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

--------** Display Module **--------
function PlanarDisplayWallController:initDisplayModule()
    local selfRef = self
    self.displayModule = {
        powerAll = function(state)
            selfRef:debugPrint("Powering all displays: " .. tostring(state))
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    local control = state and displayControls.powerOn or displayControls.powerOff
                    selfRef:safeComponentAccess(display, control, "trigger")
                end
            end
            selfRef.state.powerState = state
            if Controls.ledDisplayPower then
                Controls.ledDisplayPower.Boolean = state
            end
        end,
        
        powerSingle = function(index, state)
            local display = selfRef.components.displays[index]
            if display then
                local control = state and displayControls.powerOn or displayControls.powerOff
                selfRef:safeComponentAccess(display, control, "trigger")
                selfRef:debugPrint("Display " .. index .. " power: " .. tostring(state))
            end
        end,
        
        setInputAll = function(input)
            selfRef:debugPrint("Setting all displays to input: " .. input)
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    -- Try Option 1: InputSelectComboBox (if available)
                    if display[displayControls.vInputSelectComboBox] then
                        selfRef:safeComponentAccess(display, displayControls.vInputSelectComboBox, "setString", input)
                    else
                        -- Fallback to Option 2: InputSelectButtons
                        local buttonNumber = selfRef:getInputButtonNumber(input)
                        if buttonNumber then
                            local buttonName = displayControls.inputSelectButtons .. buttonNumber
                            selfRef:safeComponentAccess(display, buttonName, "trigger")
                        end
                    end
                end
            end
            selfRef.state.lastInput = input
            if Controls.ledDisplayInput then
                Controls.ledDisplayInput.String = input
            end
        end,
        
        setInputSingle = function(index, input)
            local display = selfRef.components.displays[index]
            if display then
                -- Try Option 1: InputSelectComboBox (if available)
                if display[displayControls.vInputSelectComboBox] then
                    selfRef:safeComponentAccess(display, displayControls.vInputSelectComboBox, "setString", input)
                    selfRef:debugPrint("Display " .. index .. " input: " .. input .. " (via ComboBox)")
                else
                    -- Fallback to Option 2: InputSelectButtons
                    local buttonNumber = selfRef:getInputButtonNumber(input)
                    if buttonNumber then
                        local buttonName = displayControls.inputSelectButtons .. buttonNumber
                        selfRef:safeComponentAccess(display, buttonName, "trigger")
                        selfRef:debugPrint("Display " .. index .. " input: " .. input .. " (button " .. buttonNumber .. ")")
                    end
                end
            end
        end,
        
        getDisplayCount = function()
            local count = 0
            for _, display in pairs(selfRef.components.displays) do
                if display then count = count + 1 end
            end
            return count
        end,
        
        getCurrentInput = function(displayIndex)
            local display = selfRef.components.displays[displayIndex]
            if not display then return nil end
            
            -- Try Option 1: InputSelectComboBox
            if display[displayControls.vInputSelectComboBox] then
                return selfRef:safeComponentAccess(display, displayControls.vInputSelectComboBox, "getString")
            end
            
            -- Option 2: Check CurrentInput 1-10 LEDs to find active input
            for i = 1, 10 do
                local currentInputControl = display[displayControls.currentInput .. i]
                if currentInputControl then
                    local isActive = selfRef:safeComponentAccess(display, displayControls.currentInput .. i, "get")
                    if isActive then
                        -- Get the input name from InputNames
                        local inputNameControl = display[displayControls.inputNames .. i]
                        if inputNameControl then
                            return selfRef:safeComponentAccess(display, displayControls.inputNames .. i, "getString")
                        else
                            return "Input " .. i
                        end
                    end
                end
            end
            
            return nil
        end,
        
        configureDisplayWall = function(mode)
            selfRef:debugPrint("Configuring display wall mode: " .. mode)
            selfRef.state.displayWallMode = mode
            
            -- Configure display wall based on mode
            local maxDisplays = (mode == "2x2" and 4) or (mode == "3x3" and 9) or 0
            if maxDisplays > 0 then
                for i = 1, maxDisplays do
                    if selfRef.components.displays[i] then
                        selfRef:safeComponentAccess(selfRef.components.displays[i], displayControls.wallMode, "setString", mode)
                        selfRef:safeComponentAccess(selfRef.components.displays[i], displayControls.wallPosition, "setString", "Position" .. i)
                    end
                end
            else
                -- Single mode - disable wall mode
                for i, display in pairs(selfRef.components.displays) do
                    if display then
                        selfRef:safeComponentAccess(display, displayControls.wallMode, "setString", "Single")
                    end
                end
            end
            
            if Controls.ledDisplayWallMode then
                Controls.ledDisplayWallMode.String = mode
            end
        end
    }
end

--------** Power Status Helper **--------
function PlanarDisplayWallController:getPowerStatus(display)
    if not display then return nil end
    
            -- Check for new dual-control structure first
        if display[displayControls.powerIsOn] and display[displayControls.powerIsOff] then
            local powerIsOn = self:safeComponentAccess(display, displayControls.powerIsOn, "get")
            local powerIsOff = self:safeComponentAccess(display, displayControls.powerIsOff, "get")
        
        -- Return the power state (PowerIsOn takes precedence if both are true)
        if powerIsOn then return true
        elseif powerIsOff then return false
        else return nil -- Neither is true, status unknown
        end
    end
    
            -- Fallback to old single control if it exists
        if display["PowerStatus"] then
            return self:safeComponentAccess(display, "PowerStatus", "get")
        end
    
    return nil
end

--------** Power Module **--------
function PlanarDisplayWallController:initPowerModule()
    local selfRef = self
    self.powerModule = {
        enableDisablePowerControls = function(state)
            -- Consolidated power controls array
            local allPowerControls = {
                "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
                "btnDisplayPowerAll", "btnDisplayInputAll", "btnDisplayWallConfig"
            }
            
            for _, controlName in ipairs(allPowerControls) do
                if Controls[controlName] then
                    if type(Controls[controlName]) == "table" then
                        -- Handle array controls (btnDisplayPowerOn, btnDisplayPowerOff, btnDisplayPowerSingle)
                        for i, btn in ipairs(Controls[controlName]) do
                            btn.IsDisabled = not state
                        end
                    else
                        -- Handle single controls (btnDisplayPowerAll, btnDisplayInputAll, btnDisplayWallConfig)
                        Controls[controlName].IsDisabled = not state
                    end
                end
            end
        end,
        
        setDisplayPowerFB = function(state)
            -- Update feedback controls to reflect power state
            if Controls.ledDisplayPower then
                Controls.ledDisplayPower.Boolean = state
            end
            if Controls.btnDisplayPowerAll then
                Controls.btnDisplayPowerAll.Boolean = state
            end
        end,
        
        updatePowerFeedbackFromDisplays = function()
            -- Update power feedback based on actual display power status
            local allPoweredOn = true
            local anyPoweredOn = false
            local poweredOnCount = 0
            local totalDisplays = 0
            
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    totalDisplays = totalDisplays + 1
                    local powerStatus = selfRef:getPowerStatus(display)
                    if powerStatus then
                        poweredOnCount = poweredOnCount + 1
                        anyPoweredOn = true
                        
                        -- Update individual display power feedback
                        if Controls.btnDisplayPowerSingle and Controls.btnDisplayPowerSingle[i] then
                            Controls.btnDisplayPowerSingle[i].Boolean = powerStatus
                        end
                    else
                        allPoweredOn = false
                        
                        -- Update individual display power feedback
                        if Controls.btnDisplayPowerSingle and Controls.btnDisplayPowerSingle[i] then
                            Controls.btnDisplayPowerSingle[i].Boolean = false
                        end
                    end
                end
            end
            
            -- Update global power feedback
            if totalDisplays > 0 then
                local globalPowerState = allPoweredOn
                selfRef.powerModule.setDisplayPowerFB(globalPowerState)
                selfRef.state.powerState = globalPowerState
                selfRef:debugPrint("Power feedback updated - All powered: " .. tostring(allPoweredOn) .. 
                                 ", Any powered: " .. tostring(anyPoweredOn) .. 
                                 ", Powered count: " .. poweredOnCount .. "/" .. totalDisplays)
            end
        end,
        
        powerOnDisplay = function(index)
            selfRef:debugPrint("Powering on display " .. index)
            selfRef.displayModule.powerSingle(index, true)
            -- Disable individual display power controls during warmup
            selfRef.powerModule.enableDisablePowerControlIndex(index, false)
            selfRef.state.isWarming = true
            if Controls.ledDisplayWarming then
                Controls.ledDisplayWarming.Boolean = true
            end
            selfRef.timers.warmup:Start(selfRef:getTimerConfig(true))
            -- Update power feedback for this specific display
            if Controls.btnDisplayPowerSingle and Controls.btnDisplayPowerSingle[index] then
                Controls.btnDisplayPowerSingle[index].Boolean = true
            end
        end,
        
        powerOffDisplay = function(index)
            selfRef:debugPrint("Powering off display " .. index)
            selfRef.displayModule.powerSingle(index, false)
            -- Disable individual display power controls during cooldown
            selfRef.powerModule.enableDisablePowerControlIndex(index, false)
            selfRef.state.isCooling = true
            if Controls.ledDisplayCooling then
                Controls.ledDisplayCooling.Boolean = true
            end
            selfRef.timers.cooldown:Start(selfRef:getTimerConfig(false))
            -- Update power feedback for this specific display
            if Controls.btnDisplayPowerSingle and Controls.btnDisplayPowerSingle[index] then
                Controls.btnDisplayPowerSingle[index].Boolean = false
            end
        end,
        
        powerOnAll = function()
            selfRef:debugPrint("Powering on all displays")
            selfRef.displayModule.powerAll(true)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.state.isWarming = true
            if Controls.ledDisplayWarming then
                Controls.ledDisplayWarming.Boolean = true
            end
            selfRef.timers.warmup:Start(selfRef:getTimerConfig(true))
            selfRef.powerModule.setDisplayPowerFB(true)
        end,
        
        powerOffAll = function()
            selfRef:debugPrint("Powering off all displays")
            selfRef.displayModule.powerAll(false)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.state.isCooling = true
            if Controls.ledDisplayCooling then
                Controls.ledDisplayCooling.Boolean = true
            end
            selfRef.timers.cooldown:Start(selfRef:getTimerConfig(false))
            selfRef.powerModule.setDisplayPowerFB(false)
        end,
        
        refreshPowerFeedback = function()
            -- Manual refresh of power feedback from displays
            selfRef:debugPrint("Manually refreshing power feedback from displays")
            selfRef.powerModule.updatePowerFeedbackFromDisplays()
        end,
        
        enableDisablePowerControlIndex = function(index, state)
            -- Consolidated array of individual display power controls
            local individualPowerControls = {"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle"}
            
            for _, controlName in ipairs(individualPowerControls) do
                if Controls[controlName] and Controls[controlName][index] then
                    Controls[controlName][index].IsDisabled = not state
                end
            end
        end
    }
end

--------** Component Management **--------
function PlanarDisplayWallController:setComponent(ctrl, componentType)
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

function PlanarDisplayWallController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function PlanarDisplayWallController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function PlanarDisplayWallController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v == true then
            if Controls.txtStatus then
                Controls.txtStatus.String = "Invalid Components"
                Controls.txtStatus.Value = 1
            end
            return
        end
    end
    if Controls.txtStatus then
        Controls.txtStatus.String = "OK"
        Controls.txtStatus.Value = 0
    end
end

--------** Component Setup **--------
function PlanarDisplayWallController:setupDisplayComponents()
    if not Controls.devDisplays then 
        self:debugPrint("No Controls.devDisplays found")
        return 
    end
    
    self:debugPrint("Setting up " .. #Controls.devDisplays .. " display components")
    for i, displaySelector in ipairs(Controls.devDisplays) do
        if displaySelector then
            self:debugPrint("Setting up display component " .. i)
            self:setDisplayComponent(i)
        end
    end
end

function PlanarDisplayWallController:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    -- Update timer configuration from room controls component
    if self.components.compRoomControls then
        self:updateTimerConfigFromComponent()
    end
end

function PlanarDisplayWallController:setDisplayComponent(index)
    if not Controls.devDisplays or not Controls.devDisplays[index] then
        self:debugPrint("Display control " .. index .. " not found")
        return
    end
    
    local componentType = "Display [" .. index .. "]"
    self.components.displays[index] = self:setComponent(Controls.devDisplays[index], componentType)
    
    if self.components.displays[index] then
        self:debugPrint("Successfully set up display component " .. index)
        self:setupDisplayEvents(index)
        -- Update power feedback to reflect new display status
        self.powerModule.updatePowerFeedbackFromDisplays()
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

--------** Component Event Setup **--------
function PlanarDisplayWallController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring (new dual-control structure)
    if display[displayControls.powerIsOn] then
        display[displayControls.powerIsOn].EventHandler = function()
            local powerIsOn = self:safeComponentAccess(display, displayControls.powerIsOn, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is ON: " .. tostring(powerIsOn))
        end
    end
    
    if display[displayControls.powerIsOff] then
        display[displayControls.powerIsOff].EventHandler = function()
            local powerIsOff = self:safeComponentAccess(display, displayControls.powerIsOff, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is OFF: " .. tostring(powerIsOff))
        end
    end
    
    -- Set up input status monitoring (Option 1: InputSelectComboBox + InputStatus LED)
    if display[displayControls.vInputSelectComboBox] then
        display[displayControls.vInputSelectComboBox].EventHandler = function()
            local currentInput = self:safeComponentAccess(display, displayControls.vInputSelectComboBox, "getString")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " current input: " .. tostring(currentInput))
        end
    end
    
    if display[displayControls.vInputStatusLED] then
        display[displayControls.vInputStatusLED].EventHandler = function()
            local inputActive = self:safeComponentAccess(display, displayControls.vInputStatusLED, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " input active: " .. tostring(inputActive))
        end
    end
    
    -- Set up input status monitoring (Option 2: CurrentInput 1-10 LEDs)
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = self:safeComponentAccess(display, displayControls.currentInput .. i, "get")
                local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
                self:debugPrint("Display " .. componentName .. " input " .. i .. " active: " .. tostring(inputActive))
            end
        end
    end
end

--------** Dynamic Component Discovery **--------
function PlanarDisplayWallController:getComponentNames()
    local namesTable = {
        DisplayNames = {},
        RoomControlsNames = {},
    }

    -- Dynamic component discovery - single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        -- Look for Planar Display components (dynamic discovery)
        if comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    -- Sort and add clear option
    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    -- Direct assignment to controls
    if Controls.devDisplays then
        for i, _ in ipairs(Controls.devDisplays) do
            Controls.devDisplays[i].Choices = namesTable.DisplayNames
        end
        self:debugPrint("Set choices for " .. #Controls.devDisplays .. " display controls")
        self:debugPrint("Found " .. #namesTable.DisplayNames .. " display components")
    end
    
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end
end

--------** Room Name Management **--------
function PlanarDisplayWallController:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
        
        -- Also update timer configuration when room controls component is available
        self:updateTimerConfigFromComponent()
    end
end

--------** Timer Event Handlers **--------
function PlanarDisplayWallController:registerTimerHandlers()
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        -- Re-enable all power controls (both global and individual)
        self.powerModule.enableDisablePowerControls(true)
        -- Re-enable individual display power controls for all displays
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
        end
        self.state.isWarming = false
        if Controls.ledDisplayWarming then
            Controls.ledDisplayWarming.Boolean = false
        end
        self.timers.warmup:Stop()
    end

    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        -- Re-enable all power controls (both global and individual)
        self.powerModule.enableDisablePowerControls(true)
        -- Re-enable individual display power controls for all displays
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
        end
        self.state.isCooling = false
        if Controls.ledDisplayCooling then
            Controls.ledDisplayCooling.Boolean = false
        end
        self.timers.cooldown:Stop()
    end
end

--------** Streamlined Event Handler Registration **--------
function PlanarDisplayWallController:registerEventHandlers()
    -- Room controls component handler
    if Controls.compRoomControls then
        Controls.compRoomControls.EventHandler = function()
            self:setRoomControlsComponent()
        end
    end
    
    -- Global power control - direct event handling
    if Controls.btnDisplayPowerAll then
        Controls.btnDisplayPowerAll.EventHandler = function(ctl)
            if ctl.Boolean then
                self.powerModule.powerOnAll()
            else
                self.powerModule.powerOffAll()
            end
        end
    end
    
    -- Individual display power controls - streamlined array handling
    local powerControlTypes = {
        {name = "btnDisplayPowerOn", action = "powerOn", toggleState = true},
        {name = "btnDisplayPowerOff", action = "powerOff", toggleState = false},
        {name = "btnDisplayPowerSingle", action = "powerSingle", toggleState = nil}
    }
    
    for _, controlType in ipairs(powerControlTypes) do
        if Controls[controlType.name] then
            for i, btn in ipairs(Controls[controlType.name]) do
                self:debugPrint("Found " .. controlType.name .. "[" .. i .. "]")
                btn.EventHandler = function(ctl)
                    -- Direct control disabling
                    self.powerModule.enableDisableIndexPowerControl(i, controlType.action, false)
                    
                    -- Direct power operations based on control type
                    if controlType.action == "powerSingle" then
                        if ctl.Boolean then
                            self.powerModule.powerOnDisplay(i)
                        else
                            self.powerModule.powerOffDisplay(i)
                        end
                    else
                        if controlType.action == "powerOn" then
                            self.powerModule.powerOnDisplay(i)
                        else
                            self.powerModule.powerOffDisplay(i)
                        end
                        
                        -- Direct UI state update
                        if Controls.btnDisplayPowerSingle and Controls.btnDisplayPowerSingle[i] then
                            Controls.btnDisplayPowerSingle[i].Boolean = controlType.toggleState
                        end
                    end
                end
            end
        end
    end
    
    -- Display input controls - direct event handling
    if Controls.btnDisplayInputAll then
        Controls.btnDisplayInputAll.EventHandler = function()
            self.displayModule.setInputAll(self.config.defaultInput)
        end
    end
    
    -- Display wall configuration - direct event handling
    if Controls.btnDisplayWallConfig then
        Controls.btnDisplayWallConfig.EventHandler = function()
            local mode = Controls.txtDisplayWallMode and Controls.txtDisplayWallMode.String or "Single"
            self.displayModule.configureDisplayWall(mode)
        end
    end
    
    -- Display component handlers - direct event handling
    if Controls.devDisplays then
        for i, displaySelector in ipairs(Controls.devDisplays) do
            if displaySelector then
                displaySelector.EventHandler = function()
                    self:setDisplayComponent(i)
                end
            end
        end
    end
end

--------** Initialization **--------
function PlanarDisplayWallController:funcInit()
    self:debugPrint("Starting Planar DisplayWallController initialization...")
    
    -- Discover and populate component choices
    self:getComponentNames()
    
    -- Setup components and event handlers
    self:setRoomControlsComponent()
    self:setupDisplayComponents()
    self:registerEventHandlers()
    self:registerTimerHandlers()
    
    -- Update room name from component
    self:updateRoomNameFromComponent()
    
    -- Set initial display wall mode
    if Controls.txtDisplayWallMode then
        Controls.txtDisplayWallMode.Choices = self.config.displayWallModes
        Controls.txtDisplayWallMode.String = self.state.displayWallMode
    end
    
    -- Update power feedback based on current display status
    self.powerModule.updatePowerFeedbackFromDisplays()
    
    -- Update timer configuration from room controls component
    self:updateTimerConfigFromComponent()
    
    self:debugPrint("Planar DisplayWallController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays")
end

--------** Cleanup **--------
function PlanarDisplayWallController:cleanup()
    -- Clear event handlers for displays
    for i, display in pairs(self.components.displays) do
        if display then
            if display[displayControls.powerIsOn] then
                display[displayControls.powerIsOn].EventHandler = nil
            end
            if display[displayControls.powerIsOff] then
                display[displayControls.powerIsOff].EventHandler = nil
            end
            if display["InputStatus"] then
                display["InputStatus"].EventHandler = nil
            end
        end
    end
    
    -- Reset component references
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
end

--------** Factory Function **--------
local function createPlanarDisplayWallController(roomName, config)
    print("Creating Planar DisplayWallController for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = PlanarDisplayWallController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created Planar DisplayWallController for "..roomName)
        return controller
    else
        print("Failed to create controller for "..roomName..": "..tostring(controller))
        return nil
    end
end

--------** Instance Creation **--------
-- Validate controls before creating instance
if not validateControls() then
    return
end

-- Get room name from room controls component or fallback to control
local function getRoomNameFromComponent()
    -- First try to get from the room controls component if it's already set
    if Controls.compRoomControls and Controls.compRoomControls.String ~= "" and Controls.compRoomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(Controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    
    -- Fallback to roomName control (if it exists)
    if Controls.roomName and Controls.roomName.String and Controls.roomName.String ~= "" then
        return "["..Controls.roomName.String.."]"
    end
    
    -- Final fallback to default room name
    return "[Planar Display Wall]"
end

local roomName = getRoomNameFromComponent()
myPlanarDisplayWallController = createPlanarDisplayWallController(roomName)

if myPlanarDisplayWallController then
    print("Planar DisplayWallController created successfully!")
else
    print("ERROR: Failed to create Planar DisplayWallController!")
end 