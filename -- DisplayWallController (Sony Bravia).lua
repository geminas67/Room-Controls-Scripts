--[[
  Sony Bravia DisplayWallController - Q-SYS Control Script for Sony Bravia Display Wall
  Author: Nikolas Smith, Q-SYS
  Date: 2025-07-06
  Version: 1.3
  Description: Controls Sony Bravia Display Wall components with power management,
  input switching, and display wall configuration. 
  Integrates with SystemAutomationController.
]]--

-- Display Control Configuration (easily changeable for different manufacturers)
local displayControls = {
    -- Power Controls
    displayPowerOn = "PowerOn",
    displayPowerOff = "PowerOff", 
    displayPowerStatus = "PowerStatus",
    
    -- Input Controls (Option 1: ComboBox method)
    inputSelectComboBox = "InputCombo",
    inputStatusLED = "InputStatus",
    
    -- Input Controls (Option 2: Button method)
    inputSelectButtons = "VideoInputs",
    inputNames = "VideoInputNames",
    currentInput = "VideoInput",
    
    -- Wall Configuration
    wallMode = "WallMode",
    wallPosition = "WallPosition"
}

-- Timer Configuration (easily changeable)
local timerConfig = {
    warmupTime = 7,      -- Seconds for displays to warm up
    cooldownTime = 5,     -- Seconds for displays to cool down
    displaysMax = 9       -- Maximum number of displays supported
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
SonyBraviaDisplayWallController = {}
SonyBraviaDisplayWallController.__index = SonyBraviaDisplayWallController

function SonyBraviaDisplayWallController.new(roomName, config)
    local self = setmetatable({}, SonyBraviaDisplayWallController)
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        displays = "%PLUGIN%_C76AD0FA-D707-4bb4-991E-D70D77AC1FC4_%FP%_b1533bca5f02f791538ad7a9a5ed9903",  -- Sony Bravia Display Wall
        roomControls = "device_controller_script" -- Will be filtered to only those starting with "compRoomControls"
    }
    
    -- Component storage
    self.components = {
        displays = {}, -- Array for multiple displays
        compRoomControls = nil, -- Room controls component
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
        maxDisplays = config and config.maxDisplays or timerConfig.displaysMax,
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
    
    -- Initialize modules
    self:initDisplayModule()
    self:initPowerModule()
    return self
end

--------** Debug Helper **--------
function SonyBraviaDisplayWallController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

--------** Input Button Mapping **--------
function SonyBraviaDisplayWallController:getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = self.inputButtonMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

--------** Safe Component Access **--------
function SonyBraviaDisplayWallController:safeComponentAccess(component, control, action, value)
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
function SonyBraviaDisplayWallController:initDisplayModule()
    local selfRef = self
    self.displayModule = {
        powerAll = function(state)
            selfRef:debugPrint("Powering all displays: " .. tostring(state))
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    local control = state and displayControls.displayPowerOn or displayControls.displayPowerOff
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
                local control = state and displayControls.displayPowerOn or displayControls.displayPowerOff
                selfRef:safeComponentAccess(display, control, "trigger")
                selfRef:debugPrint("Display " .. index .. " power: " .. tostring(state))
            end
        end,
        
        setInputAll = function(input)
            selfRef:debugPrint("Setting all displays to input: " .. input)
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    -- Try Option 1: inputSelectComboBox (if available)
                    if display[displayControls.inputSelectComboBox] then
                        selfRef:safeComponentAccess(display, displayControls.inputSelectComboBox, "setString", input)
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
                -- Try Option 1: inputSelectComboBox (if available)
                if display[displayControls.inputSelectComboBox] then
                    selfRef:safeComponentAccess(display, displayControls.inputSelectComboBox, "setString", input)
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
            
            -- Try Option 1: inputSelectComboBox
            if display[displayControls.inputSelectComboBox] then
                return selfRef:safeComponentAccess(display, displayControls.inputSelectComboBox, "getString")
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

--------** Power Module **--------
function SonyBraviaDisplayWallController:initPowerModule()
    local selfRef = self
    self.powerModule = {
        enableDisablePowerControls = function(state)
            -- Enable/disable all power controls using arrays
            local powerControls = {"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle"}
            for _, controlName in ipairs(powerControls) do
                if Controls[controlName] then
                    for i, btn in ipairs(Controls[controlName]) do
                        btn.IsDisabled = not state
                    end
                end
            end
            -- Enable/disable global power controls
            if Controls.btnDisplayPowerAll then
                Controls.btnDisplayPowerAll.IsDisabled = not state
            end
            -- Enable/disable input controls during power operations
            if Controls.btnDisplayInputAll then
                Controls.btnDisplayInputAll.IsDisabled = not state
            end
            if Controls.btnDisplayWallConfig then
                Controls.btnDisplayWallConfig.IsDisabled = not state
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
                    local powerStatus = selfRef:safeComponentAccess(display, displayControls.displayPowerStatus, "get")
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
            -- Individual display operations don't disable all power controls
            selfRef.state.isWarming = true
            if Controls.ledDisplayWarming then
                Controls.ledDisplayWarming.Boolean = true
            end
            selfRef.timers.warmup:Start(timerConfig.warmupTime)
            selfRef.powerModule.setDisplayPowerFB(true)
        end,
        
        powerOffDisplay = function(index)
            selfRef:debugPrint("Powering off display " .. index)
            selfRef.displayModule.powerSingle(index, false)
            -- Individual display operations don't disable all power controls
            selfRef.state.isCooling = true
            if Controls.ledDisplayCooling then
                Controls.ledDisplayCooling.Boolean = true
            end
            selfRef.timers.cooldown:Start(timerConfig.cooldownTime)
            selfRef.powerModule.setDisplayPowerFB(false)
        end,
        
        powerOnAll = function()
            selfRef:debugPrint("Powering on all displays")
            selfRef.displayModule.powerAll(true)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.state.isWarming = true
            if Controls.ledDisplayWarming then
                Controls.ledDisplayWarming.Boolean = true
            end
            selfRef.timers.warmup:Start(timerConfig.warmupTime)
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
            selfRef.timers.cooldown:Start(timerConfig.cooldownTime)
            selfRef.powerModule.setDisplayPowerFB(false)
        end,
        
        enableDisableIndexPowerControl = function(index, controlType, state)
            local controlMap = {
                powerOn = "btnDisplayPowerOn",
                powerOff = "btnDisplayPowerOff", 
                powerSingle = "btnDisplayPowerSingle"
            }
            local controlName = controlMap[controlType]
            if controlName and Controls[controlName] and Controls[controlName][index] then
                Controls[controlName][index].IsDisabled = not state
            end
        end,
        
        refreshPowerFeedback = function()
            -- Manual refresh of power feedback from displays
            selfRef:debugPrint("Manually refreshing power feedback from displays")
            selfRef.powerModule.updatePowerFeedbackFromDisplays()
        end
    }
end

--------** Component Management **--------
function SonyBraviaDisplayWallController:setComponent(ctrl, componentType)
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

function SonyBraviaDisplayWallController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function SonyBraviaDisplayWallController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function SonyBraviaDisplayWallController:checkStatus()
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
function SonyBraviaDisplayWallController:setupDisplayComponents()
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

function SonyBraviaDisplayWallController:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
end

function SonyBraviaDisplayWallController:setDisplayComponent(index)
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
function SonyBraviaDisplayWallController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring
    if display[displayControls.displayPowerStatus] then
        display[displayControls.displayPowerStatus].EventHandler = function()
            local powerState = self:safeComponentAccess(display, displayControls.displayPowerStatus, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power status: " .. tostring(powerState))
            
            -- Update power feedback based on actual display status
            self.powerModule.updatePowerFeedbackFromDisplays()
        end
    end
    
    -- Set up input status monitoring (Option 1: inputSelectComboBox + InputStatus LED)
    if display[displayControls.inputSelectComboBox] then
        display[displayControls.inputSelectComboBox].EventHandler = function()
            local currentInput = self:safeComponentAccess(display, displayControls.inputSelectComboBox, "getString")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " current input: " .. tostring(currentInput))
        end
    end
    
    if display[displayControls.inputStatusLED] then
        display[displayControls.inputStatusLED].EventHandler = function()
            local inputActive = self:safeComponentAccess(display, displayControls.inputStatusLED, "get")
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
function SonyBraviaDisplayWallController:getComponentNames()
    local namesTable = {
        DisplayNames = {},
        RoomControlsNames = {},
    }

    -- Dynamic component discovery - single pass through all components
    for _, comp in pairs(Component.GetComponents()) do
        -- Look for Sony Bravia Display components (dynamic discovery)
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
function SonyBraviaDisplayWallController:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
    end
end

--------** Timer Event Handlers **--------
function SonyBraviaDisplayWallController:registerTimerHandlers()
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        self.powerModule.enableDisablePowerControls(true)
        self.timers.warmup:Stop()
    end

    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        self.powerModule.enableDisablePowerControls(true)
        self.timers.cooldown:Stop()
    end
end

--------** Streamlined Event Handler Registration **--------
function SonyBraviaDisplayWallController:registerEventHandlers()
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
function SonyBraviaDisplayWallController:funcInit()
    self:debugPrint("Starting Sony Bravia DisplayWallController initialization...")
    
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
    
    self:debugPrint("Sony Bravia DisplayWallController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays")
end

--------** Cleanup **--------
function SonyBraviaDisplayWallController:cleanup()
    -- Clear event handlers for displays
    for i, display in pairs(self.components.displays) do
        if display then
            if display["PowerStatus"] then
                display["PowerStatus"].EventHandler = nil
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
local function createSonyBraviaDisplayWallController(roomName, config)
    print("Creating Sony Bravia DisplayWallController for: "..tostring(roomName))
    local success, controller = pcall(function()
        local instance = SonyBraviaDisplayWallController.new(roomName, config)
        instance:funcInit()
        return instance
    end)
    if success then
        print("Successfully created Sony Bravia DisplayWallController for "..roomName)
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
    return "[Sony Bravia Display Wall]"
end

local roomName = getRoomNameFromComponent()
mySonyBraviaDisplayWallController = createSonyBraviaDisplayWallController(roomName)

if mySonyBraviaDisplayWallController then
    print("Sony Bravia DisplayWallController created successfully!")
else
    print("ERROR: Failed to create Sony Bravia DisplayWallController!")
end 