--[[
  MXNet DisplayWallController (Refactored) - Q-SYS Control Script for LG MXNet Display Wall Control
  Author: Nikolas Smith, Q-SYS
  Date: 2025-10-17
  Version: 2.2 (RS232 Command-Based Control + Video Wall Integration)
  Firmware Req: 10.0.0
  Description: Controls LG MXNet display components via RS232 commands with power management,
  input switching, and video wall control integration. Supports Shure MXA Video Wall 4x4 
  component with 12 encoder sources (ENC-01 through ENC-12). Integrates with SystemAutomationController.
  
  REFACTORED FEATURES:
  - Enhanced validation with descriptive error messages
  - Array normalization for consistent control structures
  - Batch event registration using handler maps
  - Modular architecture with Display, Power, and Wall modules
  - Efficient utility functions with standard patterns
  - State management utilities following SystemAutomationController patterns
  - Factory functions with comprehensive error handling
  - Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
  - RS232 command-based control using MXNet protocol
  - DRY helper function for RS232 transmission (sendRs232Command)
  - Video wall control with layout selection and source routing
  - Support for 12 encoder sources mapped to button array
]]--

-- Display Control Configuration (easily changeable for different manufacturers)
local displayControls = {
    -- Power Controls (RS232 String Commands)
    powerOn = "ka 00 01\x0D",
    powerOff = "ka 00 00\x0D", 
    powerStatus = "PowerStatus",
    
    -- Input Controls (RS232 String Commands)
    -- MXNet input commands: xb 00 <input>\x0D where input is:
    inputCommands = {
        HDMI1 = "xb 00 90\x0D",
        HDMI2 = "xb 00 91\x0D",
        DisplayPort = "xb 00 C0\x0D",
        ["USB-C"] = "xb 00 92\x0D",
        DVI = "xb 00 70\x0D",
        VGA = "xb 00 60\x0D"
    },
    
    -- RS232 Controls
    rs232Tx = "Rs232Tx",
    rs232TxSend = "Rs232TxSend",
    
    -- Status feedback
    inputStatusLED = "HotPlugDetect",
    inputNames = "InputNames ",
    currentInput = "CurrentInput "
}

-------------------[ Control References ]-------------------
local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
    compWallControls = Controls.compWallControls,
    compRoomControls = Controls.compRoomControls,
    roomName = Controls.roomName,
    ledDisplayPower = Controls.ledDisplayPower,
    ledDisplayInput = Controls.ledDisplayInput,
    ledDisplayWarming = Controls.ledDisplayWarming,
    ledDisplayCooling = Controls.ledDisplayCooling,
    btnDisplayPowerAll = Controls.btnDisplayPowerAll,
    btnDisplayPowerOn = Controls.btnDisplayPowerOn,
    btnDisplayPowerOff = Controls.btnDisplayPowerOff,
    btnDisplayPowerSingle = Controls.btnDisplayPowerSingle,
    btnDisplayInputAll = Controls.btnDisplayInputAll,
    btnSource = Controls.btnSource
}

-------------------[ Control Validation ]-------------------
local function validateControls()
    local required = { "txtStatus", "devDisplays" }
    local missing = {}
    
    for _, name in ipairs(required) do
        if not controls[name] then
            table.insert(missing, name)
        end
    end
    
    if #missing > 0 then
        print("ERROR: MXNetDisplayController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("MXNetDisplayController validation passed")
    return true
end

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function normalizeControlArrays()
    local arrayControls = { 'devDisplays', 'btnDisplayPowerOn', 'btnDisplayPowerOff', 'btnDisplayPowerSingle' }
    
    for _, controlName in ipairs(arrayControls) do
        local ctrl = controls[controlName]
        if ctrl and not isArr(ctrl) then
            controls[controlName] = { ctrl }
        end
    end
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    if not ctrls then return end
    local array = isArr(ctrls) and ctrls or { ctrls }
    for i, ctrl in ipairs(array) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

local function setButtonLegend(ctrl, legend)
    if ctrl and ctrl.Legend ~= legend then
        ctrl.Legend = legend
    end
end

-------------------[ State Management Utility ]-------------------
local function resetComponentsArray()
    local componentState = {
        displays = {},
        usbDisplays = {},
        wallControls = {},
        roomControls = {},
        initialized = false
    }
    
    for category, components in pairs(componentState) do
        if type(components) == "table" then
            for k in pairs(components) do
                components[k] = nil
            end
        end
    end
    
    componentState.initialized = true
    return componentState
end

-------------------[ Class Definition ]-------------------
MXNetDisplayController = {}
MXNetDisplayController.__index = MXNetDisplayController

function MXNetDisplayController.new(roomName, config)
    -- Validate controls before initialization
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays at initialization
    normalizeControlArrays()
    
    local self = setmetatable({}, MXNetDisplayController)
    
    -- Initialize state management
    self.componentState = resetComponentsArray()
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        displays = "%PLUGIN%_e9ef4a50-ba74-4653-a22e-a58c02839313_%FP%_c7165c3b15ead5f69821d69583f73c8b",
        usbDisplays = "%PLUGIN%_a49702fc-e17d-418e-8984-2839e1417b24_%FP%_8c3c5ad17f1728918575785b65988ca3",
        wallControls = "%PLUG1N%_a49702fc-e17d-418e-8984-2839e1417b24_%FP%_8c3c5ad17f1728918575785b65988ca3",
        roomControls = "device_controller_script"
    }
    
    -- Component storage
    self.components = {
        displays = {},
        usbDisplays = {},
        wallControls = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        lastInput = "HDMI1",
        powerState = false,
        isWarming = false,
        isCooling = false
    }
    
    -- Configuration
    self.config = {
        maxDisplays = config and config.maxDisplays or 9,
        maxSources = config and config.maxSources or 12,
        defaultInput = "HDMI1",
        inputChoices = {"HDMI1", "HDMI2", "DisplayPort", "USB-C"},
        layoutChoices = {} -- Will be populated with ENC-01 through ENC-12
    }
    
    -- Populate layout choices
    for i = 1, self.config.maxSources do
        table.insert(self.config.layoutChoices, string.format("ENC-%02d", i))
    end
    
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
    
    -- Timer Configuration
    self.timerConfig = {
        warmupTime = 7,
        cooldownTime = 5
    }
    
    -- Initialize modules
    self:initDisplayModule()
    self:initPowerModule()
    self:initWallModule()
    self:updateTimerConfigFromComponent()
    
    return self
end

-----------------------------[ Debug Helper ]-----------------------------
function MXNetDisplayController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

-----------------------------[ Dynamic Timer Configuration ]-----------------------------
function MXNetDisplayController:updateTimerConfigFromComponent()
    local defaultWarmupTime, defaultCooldownTime = 7, 5
    
    if not self.components.compRoomControls then
        self.timerConfig.warmupTime = defaultWarmupTime
        self.timerConfig.cooldownTime = defaultCooldownTime
        self:debugPrint("Using default timing values")
        return
    end

    local comp = self.components.compRoomControls
    local warmupTime = comp.warmupTime and comp.warmupTime.Value or nil
    self.timerConfig.warmupTime = (warmupTime and warmupTime > 0) and warmupTime or defaultWarmupTime
    
    local cooldownTime = comp.cooldownTime and comp.cooldownTime.Value or nil
    self.timerConfig.cooldownTime = (cooldownTime and cooldownTime > 0) and cooldownTime or defaultCooldownTime
    
    self:debugPrint("Timer config - Warmup: " .. self.timerConfig.warmupTime .. "s, Cooldown: " .. self.timerConfig.cooldownTime .. "s")
end

function MXNetDisplayController:getTimerConfig(isWarmup)
    self:updateTimerConfigFromComponent()
    return isWarmup and self.timerConfig.warmupTime or self.timerConfig.cooldownTime
end

-----------------------------[ Input Button Mapping ]-----------------------------
function MXNetDisplayController:getInputButtonNumber(input)
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = self.inputButtonMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

-----------------------------[ Safe Component Access ]-----------------------------
function MXNetDisplayController:safeComponentAccess(component, control, action, value, delay)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then 
                component[control].Boolean = value
                return true
            elseif action == "setString" then
                component[control].String = value
                return true
            elseif action == "String" then
                component[control].String = value
                return true
            elseif action == "Boolean" then
                if delay then 
                    Timer.CallAfter(function()
                        component[control].Boolean = value
                    end, delay)
                else
                    component[control].Boolean = value
                end
                return true
            elseif action == "trigger" then
                component[control]:Trigger()
                return true
            elseif action == "get" then
                return component[control].Boolean
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

-----------------------------[ RS232 Command Helper ]-----------------------------
function MXNetDisplayController:sendRs232Command(display, command)
    self:safeComponentAccess(display, displayControls.rs232Tx, "String", command)
    self:safeComponentAccess(display, displayControls.rs232TxSend, "Boolean", true)
    self:safeComponentAccess(display, displayControls.rs232TxSend, "Boolean", false, 0.2)
end

-----------------------------[ Display Module ]-----------------------------
function MXNetDisplayController:initDisplayModule()
    local selfRef = self
    self.displayModule = {
        powerAll = function(state)
            selfRef:debugPrint("Powering all displays: " .. tostring(state))
            local rs232Cmd = state and displayControls.powerOn or displayControls.powerOff
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    selfRef:sendRs232Command(display, rs232Cmd)
                end
            end
            selfRef.state.powerState = state
            setProp(controls.ledDisplayPower, "Boolean", state)
        end,
        
        powerSingle = function(index, state)
            local display = selfRef.components.displays[index]
            if display then
                local rs232Cmd = state and displayControls.powerOn or displayControls.powerOff
                selfRef:sendRs232Command(display, rs232Cmd)
                selfRef:debugPrint("Display " .. index .. " power: " .. tostring(state))
            end
        end,
        
        setInputAll = function(input)
            selfRef:debugPrint("Setting all displays to input: " .. input)
            local rs232Cmd = displayControls.inputCommands[input]
            if not rs232Cmd then
                selfRef:debugPrint("WARNING: No RS232 command found for input: " .. input)
                return
            end
            
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    selfRef:sendRs232Command(display, rs232Cmd)
                end
            end
            selfRef.state.lastInput = input
            setProp(controls.ledDisplayInput, "String", input)
        end,
        
        setInputSingle = function(index, input)
            local display = selfRef.components.displays[index]
            if display then
                local rs232Cmd = displayControls.inputCommands[input]
                if not rs232Cmd then
                    selfRef:debugPrint("WARNING: No RS232 command found for input: " .. input)
                    return
                end
                
                selfRef:sendRs232Command(display, rs232Cmd)
                selfRef:debugPrint("Display " .. index .. " input: " .. input)
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
            
            -- Check CurrentInput LEDs to find active input (feedback from display)
            for i = 1, 10 do
                local currentInputControl = display[displayControls.currentInput .. i]
                if currentInputControl then
                    local isActive = selfRef:safeComponentAccess(display, displayControls.currentInput .. i, "get")
                    if isActive then
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
        end
    }
end

-----------------------------[ Power Module ]-----------------------------
function MXNetDisplayController:initPowerModule()
    local selfRef = self
    self.powerModule = {
        enableDisablePowerControls = function(state)
            local allPowerControls = {
                "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
                "btnDisplayPowerAll", "btnDisplayInputAll"
            }
            
            for _, controlName in ipairs(allPowerControls) do
                local ctrl = controls[controlName]
                if ctrl then
                    if isArr(ctrl) then
                        for i, btn in ipairs(ctrl) do 
                            setProp(btn, "IsDisabled", not state) 
                        end
                    else
                        setProp(ctrl, "IsDisabled", not state)
                    end
                end
            end
        end,
        
        setDisplayPowerFB = function(state)
            setProp(controls.ledDisplayPower, "Boolean", state)
            setProp(controls.btnDisplayPowerAll, "Boolean", state)
        end,
        
        updatePowerFeedbackFromDisplays = function()
            local allPoweredOn, anyPoweredOn, poweredOnCount, totalDisplays = true, false, 0, 0
            
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    totalDisplays = totalDisplays + 1
                    local powerStatus = selfRef:safeComponentAccess(display, displayControls.powerStatus, "get")
                    if powerStatus then
                        poweredOnCount = poweredOnCount + 1
                        anyPoweredOn = true
                        if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[i] then
                            setProp(controls.btnDisplayPowerSingle[i], "Boolean", true)
                        end
                    else
                        allPoweredOn = false
                        if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[i] then
                            setProp(controls.btnDisplayPowerSingle[i], "Boolean", false)
                        end
                    end
                end
            end
            
            if totalDisplays > 0 then
                selfRef.powerModule.setDisplayPowerFB(allPoweredOn)
                selfRef.state.powerState = allPoweredOn
                selfRef:debugPrint("Power feedback updated - Powered: " .. poweredOnCount .. "/" .. totalDisplays)
            end
        end,
        
        powerOnDisplay = function(index)
            selfRef:debugPrint("Powering on display " .. index)
            selfRef.displayModule.powerSingle(index, true)
            selfRef.powerModule.enableDisablePowerControlIndex(index, false)
            selfRef.powerModule.setOppositePowerButtonLegend(index, true)
            selfRef.state.isWarming = true
            setProp(controls.ledDisplayWarming, "Boolean", true)
            selfRef.timers.warmup:Start(selfRef:getTimerConfig(true))
            if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
                setProp(controls.btnDisplayPowerSingle[index], "Boolean", true)
            end
        end,
        
        powerOffDisplay = function(index)
            selfRef:debugPrint("Powering off display " .. index)
            selfRef.displayModule.powerSingle(index, false)
            selfRef.powerModule.enableDisablePowerControlIndex(index, false)
            selfRef.powerModule.setOppositePowerButtonLegend(index, false)
            selfRef.state.isCooling = true
            setProp(controls.ledDisplayCooling, "Boolean", true)
            selfRef.timers.cooldown:Start(selfRef:getTimerConfig(false))
            if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
                setProp(controls.btnDisplayPowerSingle[index], "Boolean", false)
            end
        end,
        
        powerOnAll = function()
            selfRef:debugPrint("Powering on all displays")
            selfRef.displayModule.powerAll(true)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.state.isWarming = true
            setProp(controls.ledDisplayWarming, "Boolean", true)
            selfRef.timers.warmup:Start(selfRef:getTimerConfig(true))
            selfRef.powerModule.setDisplayPowerFB(true)
        end,
        
        powerOffAll = function()
            selfRef:debugPrint("Powering off all displays")
            selfRef.displayModule.powerAll(false)
            selfRef.powerModule.enableDisablePowerControls(false)
            selfRef.state.isCooling = true
            setProp(controls.ledDisplayCooling, "Boolean", true)
            selfRef.timers.cooldown:Start(selfRef:getTimerConfig(false))
            selfRef.powerModule.setDisplayPowerFB(false)
        end,
        
        enableDisablePowerControlIndex = function(index, state)
            local individualPowerControls = {"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle"}
            for _, controlName in ipairs(individualPowerControls) do
                local ctrl = controls[controlName]
                if ctrl and ctrl[index] then
                    setProp(ctrl[index], "IsDisabled", not state)
                end
            end
        end,
        
        setOppositePowerButtonLegend = function(index, poweringOn)
            -- Set the opposite button's legend to "Please\nwait"
            -- If powering ON, set the Power OFF button legend
            -- If powering OFF, set the Power ON button legend
            local targetControl = poweringOn and controls.btnDisplayPowerOff or controls.btnDisplayPowerOn
            if targetControl and targetControl[index] then
                setButtonLegend(targetControl[index], "Please\nwait")
            end
        end,
        
        resetPowerButtonLegends = function(index)
            -- Reset both button legends to default when re-enabled
            if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
                setButtonLegend(controls.btnDisplayPowerOn[index], "On")
            end
            if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
                setButtonLegend(controls.btnDisplayPowerOff[index], "Off")
            end
        end
    }
end

-----------------------------[ Wall Module ]-----------------------------
function MXNetDisplayController:initWallModule()
    local selfRef = self
    self.wallModule = {
        setLayoutChoices = function(wallControls)
            if not wallControls or not wallControls.layoutSelect then
                selfRef:debugPrint("WARNING: Wall controls layoutSelect not found")
                return
            end
            wallControls.layoutSelect.Choices = selfRef.config.layoutChoices
            selfRef:debugPrint("Set layoutSelect choices: ENC-01 through ENC-" .. 
                             string.format("%02d", selfRef.config.maxSources))
        end,
        
        selectSource = function(sourceIndex)
            local wallControls = selfRef.components.wallControls
            if not wallControls or not wallControls.layoutSelect then
                selfRef:debugPrint("WARNING: Cannot select source - wall controls not available")
                return
            end
            
            -- Map button index (1-12) to layout choice (ENC-01 through ENC-12)
            local sourceName = selfRef.config.layoutChoices[sourceIndex]
            if sourceName then
                wallControls.layoutSelect.String = sourceName
                selfRef:debugPrint("Selected wall source: " .. sourceName)
            else
                selfRef:debugPrint("WARNING: Invalid source index: " .. tostring(sourceIndex))
            end
        end,
        
        getCurrentSource = function()
            local wallControls = selfRef.components.wallControls
            if wallControls and wallControls.layoutSelect then
                return wallControls.layoutSelect.String
            end
            return nil
        end
    }
end

-----------------------------[ Component Management ]-----------------------------
function MXNetDisplayController:setComponent(ctrl, componentType)
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

function MXNetDisplayController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function MXNetDisplayController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function MXNetDisplayController:checkStatus()
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

-----------------------------[ Component Setup ]-----------------------------
function MXNetDisplayController:setupDisplayComponents()
    if not Controls.devDisplays then 
        self:debugPrint("No Controls.devDisplays found")
        return 
    end
    
    self:debugPrint("Setting up " .. #Controls.devDisplays .. " display components")
    for i, displaySelector in ipairs(Controls.devDisplays) do
        if displaySelector then
            self:setDisplayComponent(i)
        end
    end
end

function MXNetDisplayController:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.compRoomControls then
        self:updateTimerConfigFromComponent()
    end
end

function MXNetDisplayController:setUSBDisplayComponent()
    self.components.usbDisplays = self:setComponent(Controls.compUSBDisplays, "USB Displays")
    if self.components.usbDisplays then
        self:debugPrint("USB displays component set successfully")
    else
        self:debugPrint("USB displays component not available")
    end
end

function MXNetDisplayController:setWallControlsComponent()
    self.components.wallControls = self:setComponent(Controls.compWallControls, "Wall Controls")
    if self.components.wallControls then
        self:debugPrint("Wall controls component set successfully")
        -- Set layout choices after component is assigned
        self.wallModule.setLayoutChoices(self.components.wallControls)
    else
        self:debugPrint("Wall controls component not available")
    end
end

function MXNetDisplayController:setDisplayComponent(index)
    if not Controls.devDisplays or not Controls.devDisplays[index] then
        self:debugPrint("Display control " .. index .. " not found")
        return
    end
    
    local componentType = "Display [" .. index .. "]"
    self.components.displays[index] = self:setComponent(Controls.devDisplays[index], componentType)
    
    if self.components.displays[index] then
        self:debugPrint("Successfully set up display component " .. index)
        self:setupDisplayEvents(index)
        self.powerModule.updatePowerFeedbackFromDisplays()
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

-----------------------------[ Component Event Setup ]-----------------------------
function MXNetDisplayController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring
    if display[displayControls.powerStatus] then
        display[displayControls.powerStatus].EventHandler = function()
            local powerState = self:safeComponentAccess(display, displayControls.powerStatus, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power status: " .. tostring(powerState))
            self.powerModule.updatePowerFeedbackFromDisplays()
        end
    end
    
    -- Set up input status monitoring (feedback from display)
    if display[displayControls.inputStatusLED] then
        display[displayControls.inputStatusLED].EventHandler = function()
            local inputActive = self:safeComponentAccess(display, displayControls.inputStatusLED, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " input active: " .. tostring(inputActive))
        end
    end
    
    -- Set up current input monitoring (feedback LEDs from display component)
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl then
            currentInputControl.EventHandler = function()
                local inputActive = self:safeComponentAccess(display, displayControls.currentInput .. i, "get")
                if inputActive then
                    local inputName = self.displayModule.getCurrentInput(index)
                    local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
                    self:debugPrint("Display " .. componentName .. " input changed to: " .. tostring(inputName))
                end
            end
        end
    end
end

-----------------------------[ Dynamic Component Discovery ]-----------------------------
function MXNetDisplayController:getComponentNames()
    local namesTable = {
        DisplayNames = {},
        USBDisplayNames = {},
        WallControlsNames = {},
        RoomControlsNames = {},
    }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.usbDisplays then
            table.insert(namesTable.USBDisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.wallControls then
            table.insert(namesTable.WallControlsNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    for _, list in pairs(namesTable) do
        table.sort(list)
        table.insert(list, self.clearString)
    end

    -- Access Controls directly to ensure we see them when they become available
    if Controls.devDisplays then
        for i, _ in ipairs(Controls.devDisplays) do
            Controls.devDisplays[i].Choices = namesTable.DisplayNames
        end
        self:debugPrint("Set choices for " .. #Controls.devDisplays .. " display controls")
        self:debugPrint("Found " .. #namesTable.DisplayNames .. " display components")
    end
    
    if Controls.compWallControls then
        Controls.compWallControls.Choices = namesTable.WallControlsNames
        self:debugPrint("Found " .. #namesTable.WallControlsNames .. " wall control components")
    end
    
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end

    if Controls.compUSBDisplays then
        Controls.compUSBDisplays.Choices = namesTable.USBDisplayNames
        self:debugPrint("Found " .. #namesTable.USBDisplayNames .. " USB display components")
    end
end

-----------------------------[ Room Name Management ]-----------------------------
function MXNetDisplayController:updateRoomNameFromComponent()
    if self.components.compRoomControls then
        local roomNameControl = self.components.compRoomControls["roomName"]
        if roomNameControl and roomNameControl.String and roomNameControl.String ~= "" then
            local newRoomName = "["..roomNameControl.String.."]"
            if newRoomName ~= self.roomName then
                self.roomName = newRoomName
                self:debugPrint("Room name updated to: "..newRoomName)
            end
        end
        self:updateTimerConfigFromComponent()
    end
end

-----------------------------[ Timer Event Handlers ]-----------------------------
function MXNetDisplayController:registerTimerHandlers()
    self.timers.warmup.EventHandler = function()
        self:debugPrint("Warmup Period Has Ended")
        self.powerModule.enableDisablePowerControls(true)
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
            self.powerModule.resetPowerButtonLegends(i)
        end
        self.state.isWarming = false
        setProp(controls.ledDisplayWarming, "Boolean", false)
        self.timers.warmup:Stop()
    end

    self.timers.cooldown.EventHandler = function()
        self:debugPrint("Cooldown Period Has Ended")
        self.powerModule.enableDisablePowerControls(true)
        for i = 1, self.config.maxDisplays do
            self.powerModule.enableDisablePowerControlIndex(i, true)
            self.powerModule.resetPowerButtonLegends(i)
        end
        self.state.isCooling = false
        setProp(controls.ledDisplayCooling, "Boolean", false)
        self.timers.cooldown:Stop()
    end
end

-----------------------------[ Batch Event Registration ]-----------------------------
function MXNetDisplayController:registerEventHandlers()
    -- Single control event handler map
    local singleControlHandlers = {
        compRoomControls = function() self:setRoomControlsComponent() end,
        compUSBDisplays = function() self:setUSBDisplayComponent() end,
        compWallControls = function() self:setWallControlsComponent() end,
        btnDisplayPowerAll = function(ctl) 
            if ctl.Boolean then self.powerModule.powerOnAll() else self.powerModule.powerOffAll() end 
        end,
        btnDisplayInputAll = function() self.displayModule.setInputAll(self.config.defaultInput) end
    }
    
    -- Register single control handlers
    for controlName, handler in pairs(singleControlHandlers) do
        bind(controls[controlName], handler)
    end
    
    -- Array control event handler map
    local arrayControlHandlers = {
        btnDisplayPowerOn = function(index, ctl) self.powerModule.powerOnDisplay(index) end,
        btnDisplayPowerOff = function(index, ctl) self.powerModule.powerOffDisplay(index) end,
        btnDisplayPowerSingle = function(index, ctl)
            if ctl.Boolean then self.powerModule.powerOnDisplay(index) else self.powerModule.powerOffDisplay(index) end
        end,
        devDisplays = function(index, ctl) self:setDisplayComponent(index) end,
        btnSource = function(index, ctl) 
            self:debugPrint("Source button " .. index .. " pressed")
            self.wallModule.selectSource(index) 
        end
    }
    
    -- Register array control handlers
    for controlName, handler in pairs(arrayControlHandlers) do
        bindArray(controls[controlName], handler)
    end
end

-----------------------------[ Initialization ]-----------------------------
function MXNetDisplayController:funcInit()
    self:debugPrint("Starting MXNet DisplayWallController initialization...")
    
    self:getComponentNames()
    self:setRoomControlsComponent()
    self:setWallControlsComponent()
    self:setUSBDisplayComponent()
    self:setupDisplayComponents()
    self:registerEventHandlers()
    self:registerTimerHandlers()
    self:updateRoomNameFromComponent()
    
    self.powerModule.updatePowerFeedbackFromDisplays()
    self:updateTimerConfigFromComponent()
    
    self:debugPrint("MXNet DisplayWallController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays and " ..
                   (self.components.wallControls and "wall controls" or "no wall controls"))
end

-----------------------------[ Cleanup ]-----------------------------
function MXNetDisplayController:cleanup()
    for i, display in pairs(self.components.displays) do
        if display then
            -- Clean up power status event handler
            if display[displayControls.powerStatus] then
                display[displayControls.powerStatus].EventHandler = nil
            end
            
            -- Clean up input status event handler
            if display[displayControls.inputStatusLED] then
                display[displayControls.inputStatusLED].EventHandler = nil
            end
            
            -- Clean up current input event handlers
            for j = 1, 10 do
                local currentInputControl = display[displayControls.currentInput .. j]
                if currentInputControl then
                    currentInputControl.EventHandler = nil
                end
            end
        end
    end
    
    -- Clean up wall controls component reference
    if self.components.wallControls then
        self.components.wallControls = nil
    end
    
    self.components = {
        displays = {},
        usbDisplays = {},
        wallControls = nil,
        compRoomControls = nil,
        invalid = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
end

-----------------------------[ Factory Function ]-----------------------------
local function createMXNetDisplayWallController(roomName, config)
    local defaultRoomName = roomName or "[MXNet Display Wall]"
    print("Creating MXNet DisplayWallController for: " .. defaultRoomName)
    
    local success, controller = pcall(function()
        local instance = MXNetDisplayController.new(defaultRoomName, config)
        if not instance then
            error("Failed to create controller instance - validation failed")
        end
        instance:funcInit()
        return instance
    end)
    
    if not success then
        print("ERROR: Failed to create MXNet DisplayWallController: " .. tostring(controller))
        return nil
    end
    
    print("Successfully created and initialized MXNet DisplayWallController for " .. defaultRoomName)
    return controller
end

-----------------------------[ Global Export and Instance Creation ]-----------------------------
-- Export the class globally for external access
MXNetDisplayController = MXNetDisplayController

-- Get room name from room controls component or fallback to control
local function getRoomNameFromComponent()
    if Controls.compRoomControls and Controls.compRoomControls.String ~= "" and Controls.compRoomControls.String ~= "[Clear]" then
        local roomControlsComponent = Component.New(Controls.compRoomControls.String)
        if roomControlsComponent and roomControlsComponent["roomName"] then
            local roomName = roomControlsComponent["roomName"].String
            if roomName and roomName ~= "" then
                return "["..roomName.."]"
            end
        end
    end
    
    if Controls.roomName and Controls.roomName.String and Controls.roomName.String ~= "" then
        return "["..Controls.roomName.String.."]"
    end
    
    return "[MXNet Display Wall]"
end

-- Create instance
local roomName = getRoomNameFromComponent()
local config = { debugging = true, maxDisplays = 9, maxSources = 12 }

myMXNetDisplayWallController = createMXNetDisplayWallController(roomName, config)

if myMXNetDisplayWallController then
    print("SUCCESS: MXNet DisplayWallController created and initialized!")
    print("Room: " .. roomName)
    print("Display count: " .. myMXNetDisplayWallController.displayModule.getDisplayCount())
    print("Wall controls: " .. (myMXNetDisplayWallController.components.wallControls and "Connected" or "Not connected"))
    
    -- Export instance globally for external access
    MXNetDisplayWallControllerInstance = myMXNetDisplayWallController
else
    print("ERROR: Failed to create MXNet DisplayWallController!")
end

--[[
  REFACTORING SUMMARY:
  ✓ Comprehensive control validation with descriptive error messages
  ✓ Control array normalization for consistent data structures
  ✓ Essential utility functions (isArr, setProp, bind, bindArray)
  ✓ Modular architecture with Display, Power, and Wall modules
  ✓ Batch event registration using handler maps
  ✓ State management utility for dynamic component arrays
  ✓ Factory function with enhanced error handling
  ✓ Optimized property access with cached references
  ✓ Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
  ✓ Uses setProp() throughout to prevent redundant property assignments
  ✓ Power and Input control for individual displays
  ✓ RS232 command-based control (MXNet protocol)
  ✓ DRY helper function for RS232 command transmission
  ✓ Power commands: ka 00 01\x0D (on), ka 00 00\x0D (off)
  ✓ Input commands: xb 00 <hex>\x0D for HDMI1, HDMI2, DisplayPort, USB-C, DVI, VGA
  ✓ Automatic Rs232Tx string population and Rs232TxSend pulse control
  ✓ Video wall control integration (v2.2)
  ✓ Support for Shure MXA Video Wall 4x4 component
  ✓ 12 encoder sources (ENC-01 through ENC-12)
  ✓ Source selection via button array (btnSource[1-12])
  ✓ Dynamic layout selection control population
  ✓ Component discovery for wall controls
]]
