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
local vDisplayControls = {
    -- Power Controls
    vPowerOn = "PowerOn",
    vPowerOff = "PowerOff", 
    vPowerIsOn = "PowerIsOn",
    vPowerIsOff = "PowerIsOff",
    
     --[[
    Input Controls (Option 1: ComboBox method) 
    vInputSelectComboBox = "InputSelectComboBox",
    vInputStatusLED = "InputStatus",
    ]]--
    
    -- Input Controls (Option 2: Button method)
    vInputSelectButtons = "VideoInputs ",
    vInputNames = "InputNames ",
    vCurrentInput = "CurrentInput ",
    
    -- Wall Configuration
    vWallMode = "WallMode",
    vWallPosition = "WallPosition"
}

-- Timer Configuration (easily changeable)
local vTimerConfig = {
    vWarmupTime = 7,      -- Seconds for displays to warm up
    vCooldownTime = 5,     -- Seconds for displays to cool down
    vMaxDisplays = 9       -- Maximum number of displays supported
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
        displays = "%PLUGIN%_404F4311-A38D-4891-AF61-709B8F48A6E1_%FP%_77008e895ac50ad 1242e3dee981c5e4", -- Planar Display Wall
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
        powerState = false
    }
    
    -- Configuration
    self.config = {
        maxDisplays = config and config.maxDisplays or vTimerConfig.vMaxDisplays,
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
                    local control = state and vDisplayControls.vPowerOn or vDisplayControls.vPowerOff
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
                local control = state and vDisplayControls.vPowerOn or vDisplayControls.vPowerOff
                selfRef:safeComponentAccess(display, control, "trigger")
                selfRef:debugPrint("Display " .. index .. " power: " .. tostring(state))
            end
        end,
        
        setInputAll = function(input)
            selfRef:debugPrint("Setting all displays to input: " .. input)
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    -- Try Option 1: InputSelectComboBox (if available)
                    if display[vDisplayControls.vInputSelectComboBox] then
                        selfRef:safeComponentAccess(display, vDisplayControls.vInputSelectComboBox, "setString", input)
                    else
                        -- Fallback to Option 2: InputSelectButtons
                        local buttonNumber = selfRef:getInputButtonNumber(input)
                        if buttonNumber then
                            local buttonName = vDisplayControls.vInputSelectButtons .. buttonNumber
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
                if display[vDisplayControls.vInputSelectComboBox] then
                    selfRef:safeComponentAccess(display, vDisplayControls.vInputSelectComboBox, "setString", input)
                    selfRef:debugPrint("Display " .. index .. " input: " .. input .. " (via ComboBox)")
                else
                    -- Fallback to Option 2: InputSelectButtons
                    local buttonNumber = selfRef:getInputButtonNumber(input)
                    if buttonNumber then
                        local buttonName = vDisplayControls.vInputSelectButtons .. buttonNumber
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
            if display[vDisplayControls.vInputSelectComboBox] then
                return selfRef:safeComponentAccess(display, vDisplayControls.vInputSelectComboBox, "getString")
            end
            
            -- Option 2: Check CurrentInput 1-10 LEDs to find active input
            for i = 1, 10 do
                local currentInputControl = display[vDisplayControls.vCurrentInput .. i]
                if currentInputControl then
                    local isActive = selfRef:safeComponentAccess(display, vDisplayControls.vCurrentInput .. i, "get")
                    if isActive then
                        -- Get the input name from InputNames
                        local inputNameControl = display[vDisplayControls.vInputNames .. i]
                        if inputNameControl then
                            return selfRef:safeComponentAccess(display, vDisplayControls.vInputNames .. i, "getString")
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
                        selfRef:safeComponentAccess(selfRef.components.displays[i], vDisplayControls.vWallMode, "setString", mode)
                        selfRef:safeComponentAccess(selfRef.components.displays[i], vDisplayControls.vWallPosition, "setString", "Position" .. i)
                    end
                end
            else
                -- Single mode - disable wall mode
                for i, display in pairs(selfRef.components.displays) do
                    if display then
                        selfRef:safeComponentAccess(display, vDisplayControls.vWallMode, "setString", "Single")
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
        if display[vDisplayControls.vPowerIsOn] and display[vDisplayControls.vPowerIsOff] then
            local powerIsOn = self:safeComponentAccess(display, vDisplayControls.vPowerIsOn, "get")
            local powerIsOff = self:safeComponentAccess(display, vDisplayControls.vPowerIsOff, "get")
        
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
        end,
        
        powerOnDisplay = function(index)
            selfRef:debugPrint("Powering on display " .. index)
            selfRef.displayModule.powerSingle(index, true)
            selfRef.powerModule.enableDisableIndexPowerControl(index, "powerOn", false)
            selfRef.timers.warmup:Start(vTimerConfig.vWarmupTime)
        end,
        
        powerOffDisplay = function(index)
            selfRef:debugPrint("Powering off display " .. index)
            selfRef.displayModule.powerSingle(index, false)
            selfRef.powerModule.enableDisableIndexPowerControl(index, "powerOff", false)
            selfRef.timers.cooldown:Start(vTimerConfig.vCooldownTime)
        end,
        
        powerOnAll = function()
            selfRef:debugPrint("Powering on all displays")
            selfRef.displayModule.powerAll(true)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.timers.warmup:Start(vTimerConfig.vWarmupTime)
        end,
        
        powerOffAll = function()
            selfRef:debugPrint("Powering off all displays")
            selfRef.displayModule.powerAll(false)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.timers.cooldown:Start(vTimerConfig.vCooldownTime)
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
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

--------** Component Event Setup **--------
function PlanarDisplayWallController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring (new dual-control structure)
    if display[vDisplayControls.vPowerIsOn] then
        display[vDisplayControls.vPowerIsOn].EventHandler = function()
            local powerIsOn = self:safeComponentAccess(display, vDisplayControls.vPowerIsOn, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is ON: " .. tostring(powerIsOn))
        end
    end
    
    if display[vDisplayControls.vPowerIsOff] then
        display[vDisplayControls.vPowerIsOff].EventHandler = function()
            local powerIsOff = self:safeComponentAccess(display, vDisplayControls.vPowerIsOff, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power is OFF: " .. tostring(powerIsOff))
        end
    end
    
    -- Set up input status monitoring (Option 1: InputSelectComboBox + InputStatus LED)
    if display[vDisplayControls.vInputSelectComboBox] then
        display[vDisplayControls.vInputSelectComboBox].EventHandler = function()
            local currentInput = self:safeComponentAccess(display, vDisplayControls.vInputSelectComboBox, "getString")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " current input: " .. tostring(currentInput))
        end
    end
    
    if display[vDisplayControls.vInputStatusLED] then
        display[vDisplayControls.vInputStatusLED].EventHandler = function()
            local inputActive = self:safeComponentAccess(display, vDisplayControls.vInputStatusLED, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " input active: " .. tostring(inputActive))
        end
    end
    
    -- Set up input status monitoring (Option 2: CurrentInput 1-10 LEDs)
    for i = 1, 10 do
        local currentInputControl = display[vDisplayControls.vCurrentInput .. i]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = self:safeComponentAccess(display, vDisplayControls.vCurrentInput .. i, "get")
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
    end
end

--------** Timer Event Handlers **--------
function PlanarDisplayWallController:registerTimerHandlers()
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
    
    self:debugPrint("Planar DisplayWallController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays")
end

--------** Cleanup **--------
function PlanarDisplayWallController:cleanup()
    -- Clear event handlers for displays
    for i, display in pairs(self.components.displays) do
        if display then
            if display[vDisplayControls.vPowerIsOn] then
                display[vDisplayControls.vPowerIsOn].EventHandler = nil
            end
            if display[vDisplayControls.vPowerIsOff] then
                display[vDisplayControls.vPowerIsOff].EventHandler = nil
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