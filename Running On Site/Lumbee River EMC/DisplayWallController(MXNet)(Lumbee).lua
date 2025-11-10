--[[
  MXNet DisplayWallController (Refactored) - Q-SYS Control Script for LG MXNet Display Wall Control
  Author: Nikolas Smith, Q-SYS
  Date: 2025-11-08
  Version: 2.5 (RS232 Command-Based Control + Simplified Mode Operation)
  Firmware Req: 10.0.0
  Description: Controls LG MXNet display components via RS232 commands with power management,
  input switching, and source routing. Operates in either wallControls mode OR matrixControls mode:
  - wallControls mode: Routes to MX Net Video Wall 4x4 component (12 encoder sources ENC-01 through ENC-12)
  - matrixControls mode: Routes to MXNet Matrix decoders (1-35 decoders)
  - If both are configured, wallControls has priority
  - External routing to separate decoders should be handled outside this script
  Integrates with SystemAutomationController.  
]]--

-- Display Controls Names
local displayControls = {
    -- RS232 Controls
    rs232Tx = "Rs232Tx",
    rs232TxSend = "Rs232TxSend",
    rs232Rx = "Rs232Rx",
    
    -- Status feedback
    -- NOTE: PowerStatus control does not exist on MXNet Decoder component
    -- Display status feedback would need to be parsed from Rs232Rx.String control
    inputStatusLED = "HotPlugDetect",
    inputNames = "InputNames ",
    currentInput = "CurrentInput "
}

-- Default RS232 Commands (LG MXNet Protocol) for fallback values if control strings are not configured
local defaultCommands = {
    powerOff = "ka 00 00\r",
    powerOn = "ka 00 01\r",
    HDMI1 = "xb 00 90\r",
    HDMI2 = "xb 00 91\r",
}

-------------------[ Control References ]-------------------
local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
    strPowerOffOn = Controls.strPowerOffOn,
    strHDMIInput = Controls.strHDMIInput,
    compWallControls = Controls.compWallControls,
    compMatrixControls = Controls.compMatrixControls,
    compDecoderSelect = Controls.compDecoderSelect,
    compRoomControls = Controls.compRoomControls,
    roomName = Controls.roomName,
    ledDisplayPower = Controls.ledDisplayPower,
    ledDisplayInput = Controls.ledDisplayInput,
    ledDisplayWarming = Controls.ledDisplayWarming,
    ledDisplayCooling = Controls.ledDisplayCooling,
    btnDisplayAllOffOn = Controls.btnDisplayAllOffOn,
    btnDisplayPowerOn = Controls.btnDisplayPowerOn,
    btnDisplayPowerOff = Controls.btnDisplayPowerOff,
    btnDisplayPowerSingle = Controls.btnDisplayPowerSingle,
    btnSource = Controls.btnSource,
    defaultSourceIndex = Controls.defaultSourceIndex,
    defaultInputSelect = Controls.defaultInputSelect
}

-------------------[ Control Validation ]-------------------
local function validateControls()
    local required = { "txtStatus", "devDisplays", "btnSource" }
    local optional = { "defaultSourceIndex", "defaultInputSelect" }
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
    
    -- Warn about missing optional controls
    for _, name in ipairs(optional) do
        if not controls[name] then
            print("WARNING: Optional control '" .. name .. "' not found - related features may be limited")
        end
    end
    
    print("MXNetDisplayController validation passed")
    return true
end

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function normalizeControlArrays()
    local arrayControls = { 
        'devDisplays', 'btnDisplayPowerOn', 'btnDisplayPowerOff', 'btnDisplayPowerSingle', 
        'btnDisplayAllOffOn', 'compDecoderSelect', 'strPowerOffOn', 'strHDMIInput' 
    }
    
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

local function forEach(array, func)
    if not array then return end
    local arr = isArr(array) and array or { array }
    for i, item in ipairs(arr) do
        if item then func(i, item) end
    end
end

-------------------[ Centralized Error/Status Reporting ]-------------------
local function printOperationResult(operationType, successCount, totalCount, errorList)
    local status = successCount == totalCount and "SUCCESS" or "PARTIAL"
    print(string.format("[%s] %s: %d/%d completed", status, operationType, successCount, totalCount))
    if errorList and #errorList > 0 then
        print("  Errors:")
        for _, err in ipairs(errorList) do
            print("    - " .. err)
        end
    end
end

local function handleBatchResult(resultSuccess, operationType, index, itemName)
    if not resultSuccess then
        return string.format("%s [%d] %s failed", operationType, index, itemName or "")
    end
    return nil
end

-------------------[ Generic Button Legend Utilities ]-------------------
local function setButtonLegends(controlArray, legends, index)
    -- Set button legends for single index or all buttons
    -- legends = {on = "On", off = "Off"} or legends = {[1] = "Off", [2] = "On"}
    if not controlArray or not legends then return end
    
    if index then
        -- Set individual button legends (e.g., btnDisplayPowerOn[index])
        for key, legend in pairs(legends) do
            local ctrl = type(key) == "string" and controlArray[key] or nil
            if ctrl and ctrl[index] then
                setButtonLegend(ctrl[index], legend)
            end
        end
    else
        -- Set all buttons legends using numeric indices
        for i, legend in pairs(legends) do
            if type(i) == "number" and controlArray[i] then
                setButtonLegend(controlArray[i], legend)
            end
        end
    end
end

-------------------[ Generic Combo Box Validation Utilities ]-------------------
local function validateNumericComboBoxSelection(ctl, minValue, maxValue, clearString, controlName)
    -- Generic validation for numeric combo box selections
    -- Returns: isValid (boolean), value (number or nil)
    local selection = ctl.String
    
    if selection == clearString or selection == "" then
        ctl.Color = "white"  -- Cleared state
        return true, nil
    end
    
    local numValue = tonumber(selection)
    if numValue and numValue >= minValue and numValue <= maxValue then
        ctl.Color = "white"  -- Valid selection
        return true, numValue
    else
        ctl.Color = "pink"  -- Invalid selection
        return false, nil
    end
end

local function ensureChoicesInitialized(ctl, initFunction, controlName)
    -- Ensure choices are set if they weren't set during initialization
    if not ctl.Choices or #ctl.Choices == 0 then
        if initFunction then
            initFunction()
        end
        return false  -- Was not initialized
    end
    return true  -- Already initialized
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

-------------------[ BaseModule Pattern ]-------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, moduleName)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.moduleName = moduleName or "BaseModule"
    return self
end

function BaseModule:debugPrint(str)
    if self.controller and self.controller.debugging then
        print("["..self.controller.roomName.." "..self.moduleName.."] "..str)
    end
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
    
    -- Store controls reference for access in methods
    self.controls = controls

    self.componentTypes = {
        displays = "%PLUGIN%_e186d86c-9fb0-426e-bd59-d1fe9e133519_%FP%_e578be77683e876fb741dc5e1344b6eb",
        wallControls = "%PLUGIN%_a49702fc-e17d-418e-8984-2839e1417b24_%FP%_5a40bd11f25eee8d56f8be6c8c922912",
        matrixControls = "%PLUGIN%_9c080b8a-681e-4cbc-b69d-17765330eeae_%FP%_01723ed5d0faac6a3e3e0d72276f6d9d",
        roomControls = "device_controller_script"
    }
    
    -- Component storage
    self.components = {
        displays = {},
        wallControls = {},
        matrixControls = nil,
        roomControls = nil,
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
        maxDecoders = config and config.maxDecoders or 35,
        excludedDecoders = config and config.excludedDecoders or {19, 20}, -- Decoders managed by BlockController/external logic
        defaultInput = "HDMI1",
        displayInputDelay = 3, -- Delay in seconds before sending input commands after power on
        inputChoices = {"HDMI1", "HDMI2", "DisplayPort"},
        layoutChoices = {}, -- Will be populated with ENC-01 through ENC-12
        sourceToEncoderMap = {
            [1] = 1,   -- DispatchPC01
            [2] = 2,   -- DispatchPC02
            [3] = 3,   -- BRHDMI01
            [4] = 4,   -- BRHDMI02
            [5] = 5,   -- WrlsPresRmA
            [6] = 6,   -- WrlsPresRmB
            [7] = 7,   -- TeamsPCRmA
            [8] = 8,   -- TeamsPCRmB
            [9] = 9,   -- LaptopRmA
            [10] = 10, -- LaptopRmB
            [11] = 11, -- EESignage
            [12] = 12  -- MediaPlayer
        }
    }
    
    -- Populate layout choices
    for i = 1, self.config.maxSources do
        table.insert(self.config.layoutChoices, string.format("ENC-%02d", i))
    end
    
    -- Input to button mapping
    self.displayInputMap = {
        HDMI1 = 1, HDMI2 = 2,
    }
    
    -- Display Commands (configurable via control strings for different display types)
    -- Falls back to default LG MXNet commands if controls are empty
    self.displayCommands = {}
    
    -- Power commands using array: [1]=Off, [2]=On
    local powerCommandTypes = {"powerOff", "powerOn"}
    for i, cmdType in ipairs(powerCommandTypes) do
        if controls.strPowerOffOn and controls.strPowerOffOn[i] and controls.strPowerOffOn[i].String ~= "" then
            self.displayCommands[cmdType] = controls.strPowerOffOn[i].String
        else
            self.displayCommands[cmdType] = defaultCommands[cmdType]
        end
    end
    
    -- HDMI input commands using array: [1]=HDMI1, [2]=HDMI2
    local hdmiInputs = {"HDMI1", "HDMI2"}
    for i, inputName in ipairs(hdmiInputs) do
        if controls.strHDMIInput and controls.strHDMIInput[i] and controls.strHDMIInput[i].String ~= "" then
            self.displayCommands[inputName] = controls.strHDMIInput[i].String
        else
            self.displayCommands[inputName] = defaultCommands[inputName]
        end
    end
    
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
    self:initMatrixModule()
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
    
    if not self.components.roomControls then
        self.timerConfig.warmupTime = defaultWarmupTime
        self.timerConfig.cooldownTime = defaultCooldownTime
        self:debugPrint("Using default timing values")
        return
    end

    local comp = self.components.roomControls
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
    if not input then return nil end
    local normalizedInput = input:gsub("USB%-C", "USB_C")
    local buttonNumber = self.displayInputMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

-----------------------------[ RS232 Command Helper ]-----------------------------
function MXNetDisplayController:sendRs232Command(display, command)
    if not display or not command then return false end
    
    -- Direct access with guard clauses
    if display[displayControls.rs232Tx] then
        display[displayControls.rs232Tx].String = command
    else
        return false
    end
    
    if display[displayControls.rs232TxSend] then
        display[displayControls.rs232TxSend].Boolean = true
        Timer.CallAfter(function()
            if display[displayControls.rs232TxSend] then
                display[displayControls.rs232TxSend].Boolean = false
            end
        end, 0.2)
    else
        return false
    end
    
    return true
end

-----------------------------[ Generic Timer Completion Handler ]-----------------------------
function MXNetDisplayController:handleTimerCompletion(isWarmup)
    local timerType = isWarmup and "Warmup" or "Cooldown"
    local stateKey = isWarmup and "isWarming" or "isCooling"
    local ledControl = isWarmup and controls.ledDisplayWarming or controls.ledDisplayCooling
    local timer = isWarmup and self.timers.warmup or self.timers.cooldown
    
    self:debugPrint(timerType .. " Period Has Ended")
    self.powerModule:enableDisablePowerControls(true)
    
    for i = 1, self.config.maxDisplays do
        self.powerModule:enableDisablePowerControlIndex(i, true)
        self.powerModule:resetPowerButtonLegends(i)
    end
    
    self.powerModule:resetPowerButtonLegends(nil)  -- Reset all buttons
    self.state[stateKey] = false
    setProp(ledControl, "Boolean", false)
    timer:Stop()
end

-----------------------------[ Display Module ]-----------------------------
local DisplayModule = setmetatable({}, {__index = BaseModule})
DisplayModule.__index = DisplayModule

function DisplayModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "DisplayModule"), DisplayModule)
    return self
end

function DisplayModule:powerAll(state)
    self:debugPrint("Powering all displays: " .. tostring(state))
    local rs232Cmd = state and self.controller.displayCommands.powerOn or self.controller.displayCommands.powerOff
    
    for i, display in pairs(self.controller.components.displays) do
        if display then
            self.controller:sendRs232Command(display, rs232Cmd)
            -- Set individual LED feedback for each display
            if controls.ledDisplayPower and controls.ledDisplayPower[i] then
                setProp(controls.ledDisplayPower[i], "Boolean", state)
            end
        end
    end
    
    self.controller.state.powerState = state
    
    -- EventHandlers don't fire on programmatic changes - directly call auto source selection
    if state then
        self.controller:handleAutoDefaultSourceSelection(1)
    end
end

function DisplayModule:powerSingle(index, state)
    local display = self.controller.components.displays[index]
    if not display then return end
    
    local rs232Cmd = state and self.controller.displayCommands.powerOn or self.controller.displayCommands.powerOff
    self.controller:sendRs232Command(display, rs232Cmd)
    
    -- Set individual LED feedback for this display
    if controls.ledDisplayPower and controls.ledDisplayPower[index] then
        setProp(controls.ledDisplayPower[index], "Boolean", state)
        
        -- EventHandlers don't fire on programmatic changes - directly call input and source selection
        if state then
            -- Set display to default input after power on
            self:setInputSingleDelayed(index, self.controller:getDefaultInput(), self.controller.config.displayInputDelay)
            
            -- Trigger auto source selection for display 1
            if index == 1 then
                self.controller:handleAutoDefaultSourceSelection(index)
            end
        end
    end
    
    self:debugPrint("Display " .. index .. " power: " .. tostring(state))
end

function DisplayModule:setInputAll(input)
    self:debugPrint("Setting all displays to input: " .. input)
    local rs232Cmd = self.controller.displayCommands[input]
    if not rs232Cmd then
        self:debugPrint("WARNING: No RS232 command found for input: " .. input)
        return
    end
    
    for i, display in pairs(self.controller.components.displays) do
        if display then
            self.controller:sendRs232Command(display, rs232Cmd)
        end
    end
    
    self.controller.state.lastInput = input
    setProp(controls.ledDisplayInput, "String", input)
end

function DisplayModule:setInputSingle(index, input)
    self:debugPrint("setInputSingle called - index: " .. tostring(index) .. ", input: " .. tostring(input))
    
    local display = self.controller.components.displays[index]
    if not display then 
        self:debugPrint("WARNING: Display component [" .. index .. "] not found")
        return 
    end
    
    local rs232Cmd = self.controller.displayCommands[input]
    if not rs232Cmd then
        self:debugPrint("WARNING: No RS232 command found for input: " .. input)
        return
    end
    
    self:debugPrint("Sending RS232 command to display " .. index .. ": " .. rs232Cmd)
    local success = self.controller:sendRs232Command(display, rs232Cmd)
    self:debugPrint("Display " .. index .. " input set to " .. input .. " - Success: " .. tostring(success))
end

function DisplayModule:setInputAllDelayed(input, delay)
    delay = delay or 3  -- Default 3 second delay
    self:debugPrint("Scheduling input change to " .. input .. " for all displays in " .. delay .. " seconds")
    Timer.CallAfter(function()
        self:setInputAll(input)
    end, delay)
end

function DisplayModule:setInputSingleDelayed(index, input, delay)
    delay = delay or 3  -- Default 3 second delay
    self:debugPrint("Scheduling input change to " .. input .. " for display " .. index .. " in " .. delay .. " seconds")
    Timer.CallAfter(function()
        self:setInputSingle(index, input)
    end, delay)
end

function DisplayModule:getDisplayCount()
    local count = 0
    for _, display in pairs(self.controller.components.displays) do
        if display then count = count + 1 end
    end
    return count
end

function DisplayModule:getCurrentInput(displayIndex)
    local display = self.controller.components.displays[displayIndex]
    if not display then return nil end
    
    -- Check CurrentInput LEDs to find active input (feedback from display)
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl and currentInputControl.Boolean then
            local inputNameControl = display[displayControls.inputNames .. i]
            if inputNameControl and inputNameControl.String then
                return inputNameControl.String
            else
                return "Input " .. i
            end
        end
    end
    return nil
end

function MXNetDisplayController:initDisplayModule()
    self.displayModule = DisplayModule.new(self)
end

-----------------------------[ Power Module ]-----------------------------
local PowerModule = setmetatable({}, {__index = BaseModule})
PowerModule.__index = PowerModule

function PowerModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "PowerModule"), PowerModule)
    
    -- Power operation configuration
    self.powerOpConfig = {
        powerOn = {
            state = true,
            interlockControl = "btnDisplayPowerOff",
            timerKey = "isWarming",
            ledControl = controls.ledDisplayWarming,
            timer = controller.timers.warmup,
            isWarmup = true,
            debugMsg = "Powering on display"
        },
        powerOff = {
            state = false,
            interlockControl = "btnDisplayPowerOn",
            timerKey = "isCooling",
            ledControl = controls.ledDisplayCooling,
            timer = controller.timers.cooldown,
            isWarmup = false,
            debugMsg = "Powering off display"
        }
    }
    
    return self
end

function PowerModule:enableDisablePowerControls(state)
    local allPowerControls = {
        "btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle",
        "btnDisplayAllOffOn"
    }
    
    for _, controlName in ipairs(allPowerControls) do
        local ctrl = controls[controlName]
        if ctrl then
            if isArr(ctrl) then
                forEach(ctrl, function(i, btn) setProp(btn, "IsDisabled", not state) end)
            else
                setProp(ctrl, "IsDisabled", not state)
            end
        end
    end
end

function PowerModule:setDisplayPowerFB(state)
    -- ledDisplayPower is an array - individual LEDs are set per display
    -- This function only handles button feedback for "All Off/On" buttons
    if controls.btnDisplayAllOffOn then
        setProp(controls.btnDisplayAllOffOn[1], "Boolean", not state)
        setProp(controls.btnDisplayAllOffOn[2], "Boolean", state)
    end
end

function PowerModule:setIndividualPowerButtonFeedback(index, powerState)
    -- DRY helper: Updates btnDisplayPowerOn[i] and btnDisplayPowerOff[i] based on power state
    if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
        setProp(controls.btnDisplayPowerOn[index], "Boolean", powerState)
    end
    if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
        setProp(controls.btnDisplayPowerOff[index], "Boolean", not powerState)
    end
end

function PowerModule:updatePowerFeedbackFromDisplays()
    local allPoweredOn, poweredOnCount, totalDisplays = true, 0, 0
    
    -- NOTE: MXNet Decoder component doesn't have PowerStatus control
    -- Power feedback is managed through local ledDisplayPower controls instead
    for i, display in pairs(self.controller.components.displays) do
        if display then
            totalDisplays = totalDisplays + 1
            -- Check local LED feedback instead
            local powerStatus = false
            if controls.ledDisplayPower and controls.ledDisplayPower[i] then
                powerStatus = controls.ledDisplayPower[i].Boolean
            end
            
            if powerStatus then
                poweredOnCount = poweredOnCount + 1
            else
                allPoweredOn = false
            end
            
            if controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[i] then
                setProp(controls.btnDisplayPowerSingle[i], "Boolean", powerStatus)
            end
            
            -- Update btnDisplayPowerOn[i] and btnDisplayPowerOff[i] feedback
            self:setIndividualPowerButtonFeedback(i, powerStatus)
        end
    end
    
    if totalDisplays > 0 then
        self:setDisplayPowerFB(allPoweredOn)
        self.controller.state.powerState = allPoweredOn
        self:debugPrint("Power feedback updated - Powered: " .. poweredOnCount .. "/" .. totalDisplays)
    end
end

function PowerModule:executePowerOperation(opType, index)
    local config = self.powerOpConfig[opType]
    if not config then return end
    
    local isIndividual = index ~= nil
    self:debugPrint(config.debugMsg .. (isIndividual and (" " .. index) or " all"))
    
    -- Set immediate button feedback (before timer completes)
    if isIndividual then
        -- Set both On/Off buttons for immediate feedback
        self:setIndividualPowerButtonFeedback(index, config.state)
    else
        -- All buttons: [1] = All Off, [2] = All On
        local interlockIndex = config.state and 1 or 2
        if controls.btnDisplayAllOffOn and controls.btnDisplayAllOffOn[interlockIndex] then
            setProp(controls.btnDisplayAllOffOn[interlockIndex], "Boolean", false)
        end
        
        -- Set all individual display power button feedback
        for i = 1, self.controller.config.maxDisplays do
            self:setIndividualPowerButtonFeedback(i, config.state)
        end
    end
    
    -- Execute power command
    if isIndividual then
        self.controller.displayModule:powerSingle(index, config.state)
        self:enableDisablePowerControlIndex(index, false)
    else
        self.controller.displayModule:powerAll(config.state)
        self:enableDisablePowerControls(false)
    end
    
    -- Set waiting legend on opposite button
    self:setOppositePowerButtonLegend(index, config.state)
    
    -- Update state and LED
    self.controller.state[config.timerKey] = true
    setProp(config.ledControl, "Boolean", true)
    
    -- Start timer
    config.timer:Start(self.controller:getTimerConfig(config.isWarmup))
    
    -- Update feedback buttons
    if isIndividual and controls.btnDisplayPowerSingle and controls.btnDisplayPowerSingle[index] then
        setProp(controls.btnDisplayPowerSingle[index], "Boolean", config.state)
    else
        self:setDisplayPowerFB(config.state)
    end
end

function PowerModule:powerOnDisplay(index)
    self:executePowerOperation("powerOn", index)
end

function PowerModule:powerOffDisplay(index)
    self:executePowerOperation("powerOff", index)
end

function PowerModule:powerOnAll()
    self:executePowerOperation("powerOn", nil)
end

function PowerModule:powerOffAll()
    self:executePowerOperation("powerOff", nil)
end

function PowerModule:enableDisablePowerControlIndex(index, state)
    local individualPowerControls = {"btnDisplayPowerOn", "btnDisplayPowerOff", "btnDisplayPowerSingle"}
    for _, controlName in ipairs(individualPowerControls) do
        local ctrl = controls[controlName]
        if ctrl and ctrl[index] then
            setProp(ctrl[index], "IsDisabled", not state)
        end
    end
end

function PowerModule:setOppositePowerButtonLegend(index, poweringOn)
    if index then
        -- Individual display button
        local targetControl = poweringOn and controls.btnDisplayPowerOff or controls.btnDisplayPowerOn
        if targetControl and targetControl[index] then
            setButtonLegend(targetControl[index], "Please\nwait")
        end
    else
        -- All buttons: [1] = All Off, [2] = All On
        local targetIndex = poweringOn and 1 or 2
        if controls.btnDisplayAllOffOn and controls.btnDisplayAllOffOn[targetIndex] then
            setButtonLegend(controls.btnDisplayAllOffOn[targetIndex], "Please\nwait")
        end
    end
end

function PowerModule:resetPowerButtonLegends(index)
    if index then
        -- Individual display buttons
        if controls.btnDisplayPowerOn and controls.btnDisplayPowerOn[index] then
            setButtonLegend(controls.btnDisplayPowerOn[index], "On")
        end
        if controls.btnDisplayPowerOff and controls.btnDisplayPowerOff[index] then
            setButtonLegend(controls.btnDisplayPowerOff[index], "Off")
        end
    else
        -- All buttons: [1] = All Off, [2] = All On
        if controls.btnDisplayAllOffOn then
            setButtonLegend(controls.btnDisplayAllOffOn[1], "Off")
            setButtonLegend(controls.btnDisplayAllOffOn[2], "On")
        end
    end
end

function PowerModule:resetAllPowerButtonLegends()
    for i = 1, self.controller.config.maxDisplays do
        self:resetPowerButtonLegends(i)
    end
    self:resetPowerButtonLegends(nil)
end

function MXNetDisplayController:initPowerModule()
    self.powerModule = PowerModule.new(self)
end

-----------------------------[ Wall Module ]-----------------------------
local WallModule = setmetatable({}, {__index = BaseModule})
WallModule.__index = WallModule

function WallModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "WallModule"), WallModule)
    return self
end

function WallModule:validateLayoutControl(wallControls)
    if not wallControls or not wallControls.LayoutSelectCombo then
        self:debugPrint("WARNING: Wall controls LayoutSelectCombo not found")
        return false
    end
    self:debugPrint("LayoutSelectCombo control validated successfully")
    return true
end

function WallModule:selectSource(sourceIndex)
    local wallControls = self.controller.components.wallControls
    if not wallControls or not wallControls.LayoutSelectCombo then
        self:debugPrint("WARNING: Cannot select source - wall controls not available")
        return false
    end
    
    local expectedEncoderName = string.format("ENC-%02d", sourceIndex)
    local choices = wallControls.LayoutSelectCombo.Choices
    
    if not choices or #choices == 0 then
        self:debugPrint("WARNING: LayoutSelectCombo has no choices available")
        return false
    end
    
    -- Search for matching encoder
    for _, choice in ipairs(choices) do
        if choice == expectedEncoderName then
            wallControls.LayoutSelectCombo.String = choice
            self:debugPrint("Selected wall source: " .. choice)
            return true
        end
    end
    
    self:debugPrint("WARNING: Encoder " .. expectedEncoderName .. " not found in choices: " .. table.concat(choices, ", "))
    return false
end

function WallModule:getCurrentSource()
    local wallControls = self.controller.components.wallControls
    if wallControls and wallControls.LayoutSelectCombo then
        return wallControls.LayoutSelectCombo.String
    end
    return nil
end

function MXNetDisplayController:initWallModule()
    self.wallModule = WallModule.new(self)
end

-----------------------------[ Source Button Interlocking ]-----------------------------
function MXNetDisplayController:interlockSourceButtons(activeIndex)
    if not controls.btnSource then return end
    
    local btnArray = isArr(controls.btnSource) and controls.btnSource or {controls.btnSource}
    for i, btn in ipairs(btnArray) do
        if btn then
            setProp(btn, "Boolean", i == activeIndex)
        end
    end
end

-----------------------------[ Source Selection Logic ]-----------------------------
function MXNetDisplayController:performSourceRouting(sourceIndex)
    -- Core routing logic without button manipulation
    -- This can be called programmatically or from button event handlers
    -- Operates in either wallControls mode OR matrixControls mode (wallControls has priority)
    
    -- Validate source index
    if not sourceIndex or sourceIndex < 1 or sourceIndex > self.config.maxSources then
        self:debugPrint("WARNING: Invalid source index: " .. tostring(sourceIndex))
        return false
    end
    
    self:debugPrint("Performing source routing for source: " .. sourceIndex)
    
    -- wallControls mode (priority) - route to wall controls only
    if self.components.wallControls then
        self.wallModule:selectSource(sourceIndex)
        self:debugPrint("wallControls mode: Routed source " .. sourceIndex .. " to wall controls")
        return true
    end
    
    -- matrixControls mode - route to matrix controls only (wallControls not present)
    if self.components.matrixControls then
        local selectedDecoders = self.matrixModule:getSelectedDecoders()
        if #selectedDecoders > 0 then
            self.matrixModule:routeSourceToDecoders(sourceIndex)
            self:debugPrint("matrixControls mode: Routed source " .. sourceIndex .. " to " .. #selectedDecoders .. " matrix decoders")
            return true
        else
            self:debugPrint("matrixControls mode: Matrix controls present but no decoders selected")
            return false
        end
    end
    
    -- Neither mode configured
    self:debugPrint("WARNING: No routing target configured (no wallControls or matrixControls)")
    return false
end

function MXNetDisplayController:selectSource(sourceIndex)
    -- User-initiated source selection (includes button interlocking + routing)
    -- Called from button event handlers
    
    -- Validate source index
    if not sourceIndex or sourceIndex < 1 or sourceIndex > self.config.maxSources then
        self:debugPrint("WARNING: Invalid source index: " .. tostring(sourceIndex))
        return false
    end
    
    self:debugPrint("Selecting source: " .. sourceIndex)
    
    -- Interlock source buttons (only one active at a time)
    self:interlockSourceButtons(sourceIndex)
    
    -- Perform the actual routing
    return self:performSourceRouting(sourceIndex)
end

-----------------------------[ Automatic Default Source Selection ]-----------------------------
function MXNetDisplayController:setDefaultSourceIndexChoices()
    if not controls.defaultSourceIndex then
        self:debugPrint("WARNING: defaultSourceIndex control not found")
        return
    end
    
    -- Build choices: [Clear] plus keys from sourceToEncoderMap (1-12)
    local choices = {self.clearString}
    for sourceIndex = 1, self.config.maxSources do
        if self.config.sourceToEncoderMap[sourceIndex] then
            table.insert(choices, tostring(sourceIndex))
        end
    end
    
    controls.defaultSourceIndex.Choices = choices
    self:debugPrint("Set defaultSourceIndex choices: " .. table.concat(choices, ", "))
end

-----------------------------[ Default Input Selection ]-----------------------------
function MXNetDisplayController:setDefaultInputSelectChoices()
    if not controls.defaultInputSelect then
        self:debugPrint("WARNING: defaultInputSelect control not found")
        return
    end
    
    -- Build choices from inputChoices config (HDMI1, HDMI2, DisplayPort)
    local choices = {}
    for _, input in ipairs(self.config.inputChoices) do
        -- Only include inputs that have RS232 commands configured
        if self.displayCommands[input] then
            table.insert(choices, input)
        end
    end
    
    controls.defaultInputSelect.Choices = choices
    self:debugPrint("Set defaultInputSelect choices: " .. table.concat(choices, ", "))
end

function MXNetDisplayController:getDefaultInput()
    -- Get the selected default input from UI control, or fallback to hardcoded default
    if controls.defaultInputSelect and controls.defaultInputSelect.String ~= "" then
        local selectedInput = controls.defaultInputSelect.String
        -- Validate that this input has a command configured
        if self.displayCommands[selectedInput] then
            return selectedInput
        else
            self:debugPrint("WARNING: Selected input '" .. selectedInput .. "' has no RS232 command configured")
        end
    end
    
    -- Fallback to hardcoded default
    return self.config.defaultInput
end

function MXNetDisplayController:handleAutoDefaultSourceSelection(displayIndex)
    -- Only auto-select for display 1
    if displayIndex ~= 1 then return end
    
    -- Check if defaultSourceIndex control exists
    if not controls.defaultSourceIndex then
        self:debugPrint("defaultSourceIndex control not found - skipping auto source selection")
        return
    end
    
    -- Get selected value from combo box
    local selectedValue = controls.defaultSourceIndex.String
    
    -- If [Clear] or empty, skip auto-selection (user has disabled this feature)
    if not selectedValue or selectedValue == "" or selectedValue == self.clearString then
        return
    end
    
    -- Convert to number and validate
    local defaultSourceIndex = tonumber(selectedValue)
    if not defaultSourceIndex or defaultSourceIndex < 1 or defaultSourceIndex > self.config.maxSources then
        self:debugPrint("WARNING: Invalid defaultSourceIndex value: " .. tostring(selectedValue))
        return
    end
    
    -- Check if source button exists
    if not controls.btnSource then
        self:debugPrint("WARNING: btnSource control not found - cannot auto-select")
        return
    end
    
    local btnArray = isArr(controls.btnSource) and controls.btnSource or {controls.btnSource}
    if not btnArray[defaultSourceIndex] then
        self:debugPrint("WARNING: Source button " .. defaultSourceIndex .. " not found in btnArray")
        return
    end
    
    self:debugPrint("Auto-selecting default source " .. defaultSourceIndex .. " for display 1")
    
    -- Update button feedback and perform routing
    self:interlockSourceButtons(defaultSourceIndex)
    self:performSourceRouting(defaultSourceIndex)
end

-----------------------------[ Matrix Module ]-----------------------------
local MatrixModule = setmetatable({}, {__index = BaseModule})
MatrixModule.__index = MatrixModule

function MatrixModule.new(controller)
    local self = setmetatable(BaseModule.new(controller, "MatrixModule"), MatrixModule)
    return self
end

function MatrixModule:setDecoderChoices()
    -- Build choices list: [Clear] plus 1 through maxDecoders
    local choices = {self.controller.clearString}
    for i = 1, self.controller.config.maxDecoders do
        table.insert(choices, tostring(i))
    end
    
    -- Set choices for compDecoderSelect array
    if controls.compDecoderSelect then
        local decoderArray = isArr(controls.compDecoderSelect) and controls.compDecoderSelect or {controls.compDecoderSelect}
        self:debugPrint("Setting decoder choices for " .. #decoderArray .. " decoder select controls")
        
        forEach(decoderArray, function(i, ctrl)
            if ctrl then
                ctrl.Choices = choices
                self:debugPrint("Set choices for decoder select control " .. i)
            else
                self:debugPrint("WARNING: Decoder select control " .. i .. " is nil")
            end
        end)
    else
        self:debugPrint("WARNING: compDecoderSelect controls not found")
    end
    
    self:debugPrint("Set decoder choices: [Clear] and 1 through " .. self.controller.config.maxDecoders)
end

function MatrixModule:getSelectedDecoders()
    local decoders = {}
    local decoderSet = {}  -- Track unique decoders to avoid duplicates
    
    -- Helper to check if decoder is excluded
    local function isExcluded(decoderNum)
        for _, excluded in ipairs(self.controller.config.excludedDecoders) do
            if decoderNum == excluded then
                return true
            end
        end
        return false
    end
    
    -- Get decoders from compDecoderSelect array (multiple selections)
    if controls.compDecoderSelect then
        local decoderArray = isArr(controls.compDecoderSelect) and controls.compDecoderSelect or {controls.compDecoderSelect}
        forEach(decoderArray, function(i, ctrl)
            if ctrl then
                local selection = ctrl.String
                -- Skip if cleared or empty
                if selection ~= self.controller.clearString and selection ~= "" then
                    local decoderNum = tonumber(selection)
                    if decoderNum and decoderNum >= 1 and decoderNum <= self.controller.config.maxDecoders then
                        -- Only add if not already in the list (avoid duplicates) and not excluded
                        if not decoderSet[decoderNum] and not isExcluded(decoderNum) then
                            table.insert(decoders, decoderNum)
                            decoderSet[decoderNum] = true
                            self:debugPrint("Decoder selector " .. i .. " has decoder " .. decoderNum .. " selected")
                        elseif isExcluded(decoderNum) then
                            self:debugPrint("Decoder selector " .. i .. " decoder " .. decoderNum .. " excluded (managed externally)")
                        end
                    end
                end
            end
        end)
    end
    
    return decoders
end

function MatrixModule:routeSourceToSingleDecoder(sourceIndex, decoderIndex)
    if not self.controller.components.matrixControls then
        self:debugPrint("WARNING: Matrix controls component not available")
        return false
    end
    
    local encoderNum = self.controller.config.sourceToEncoderMap[sourceIndex]
    if not encoderNum then
        self:debugPrint("WARNING: Invalid source index: " .. tostring(sourceIndex))
        return false
    end
    
    local controlName = "MatrixTiePinAV " .. decoderIndex
    self:debugPrint("Looking for control: '" .. controlName .. "'")  -- ADD THIS
    
    local matrixControl = self.controller.components.matrixControls[controlName]
    
    if not matrixControl then
        self:debugPrint("WARNING: Matrix control not found: " .. controlName)
        -- ADD THIS: List available controls
        self:debugPrint("Available controls in matrix component:")
        for name, ctrl in pairs(self.controller.components.matrixControls) do
            if type(ctrl) == "table" and type(name) == "string" and name:match("MatrixTiePinAV") then
                self:debugPrint("  - '" .. name .. "'")
            end
        end
        return false
    end
    
    matrixControl.Value = encoderNum
    self:debugPrint("Routed source " .. sourceIndex .. " (encoder " .. encoderNum .. ") to decoder " .. decoderIndex)
    return true
end
function MatrixModule:routeSourceToDecoders(sourceIndex)
    local selectedDecoders = self:getSelectedDecoders()
    
    if #selectedDecoders == 0 then
        self:debugPrint("No decoders selected for routing")
        return
    end
    
    if not self.controller.components.matrixControls then
        self:debugPrint("WARNING: Matrix controls component not available")
        return
    end
    
    local encoderNum = self.controller.config.sourceToEncoderMap[sourceIndex]
    if not encoderNum then
        self:debugPrint("WARNING: Invalid source index: " .. tostring(sourceIndex))
        return
    end
    
    local successCount = 0
    local errorList = {}
    
    for _, decoderNum in ipairs(selectedDecoders) do
        if self:routeSourceToSingleDecoder(sourceIndex, decoderNum) then
            successCount = successCount + 1
        else
            local err = handleBatchResult(false, "Matrix routing", decoderNum, "Decoder " .. decoderNum)
            if err then table.insert(errorList, err) end
        end
    end
    
    printOperationResult("Matrix routing source " .. sourceIndex, successCount, #selectedDecoders, errorList)
end

function MXNetDisplayController:initMatrixModule()
    self.matrixModule = MatrixModule.new(self)
end

-----------------------------[ Component Management ]-----------------------------
function MXNetDisplayController:setComponent(ctrl, componentType)
    local componentName = ctrl and ctrl.String or nil
    if not componentName or componentName == "" or componentName == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return nil
    end
    
    -- Create component reference once and reuse it
    local component = Component.New(componentName)
    if not component or #Component.GetControls(component) < 1 then
        if ctrl then
            ctrl.String = "[Invalid Component Selected]"
            ctrl.Color = "pink"
        end
        self:setComponentInvalid(componentType)
        return nil
    else
        if ctrl then ctrl.Color = "white" end
        self:setComponentValid(componentType)
        return component
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
    self.components.roomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.roomControls then
        self:updateTimerConfigFromComponent()
        
        -- Set up event handler for ledSystemPower to turn off all source buttons when system powers off
        if self.components.roomControls["ledSystemPower"] then
            self.components.roomControls["ledSystemPower"].EventHandler = function(ctl)
                if ctl.Boolean == false and controls.btnSource then
                    -- Turn off all source buttons when system power goes off
                    local btnArray = isArr(controls.btnSource) and controls.btnSource or {controls.btnSource}
                    for i, btn in ipairs(btnArray) do
                        if btn then
                            setProp(btn, "Boolean", false)
                        end
                    end
                    self:debugPrint("System power off - cleared all source buttons")
                end
            end
        end
    end
end


function MXNetDisplayController:setWallControlsComponent()
    self.components.wallControls = self:setComponent(Controls.compWallControls, "Wall Controls")
    if self.components.wallControls then
        self:debugPrint("Wall controls component set successfully")
        -- Validate LayoutSelectCombo exists (don't overwrite choices - component sets them)
        self.wallModule:validateLayoutControl(self.components.wallControls)
    else
        self:debugPrint("Wall controls component not available")
    end
end

function MXNetDisplayController:setMatrixControlsComponent()
    self.components.matrixControls = self:setComponent(Controls.compMatrixControls, "Matrix Controls")
    if self.components.matrixControls then
        self:debugPrint("Matrix controls component set successfully")
        -- Set decoder choices after component is assigned
        self.matrixModule:setDecoderChoices()
    else
        self:debugPrint("Matrix controls component not available")
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
        self.powerModule:updatePowerFeedbackFromDisplays()
    else
        self:debugPrint("Failed to set up display component " .. index)
    end
end

-----------------------------[ Component Event Setup ]-----------------------------
function MXNetDisplayController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
    
    -- NOTE: MXNet Decoder component doesn't have PowerStatus control
    -- Power status monitoring is handled through ledDisplayPower EventHandler instead
    -- (See arrayControlHandlers in registerEventHandlers)
    
    -- Set up input status monitoring (feedback from display)
    if display[displayControls.inputStatusLED] then
        display[displayControls.inputStatusLED].EventHandler = function(ctl)
            self:debugPrint("Display " .. componentName .. " input active: " .. tostring(ctl.Boolean))
        end
    end
    
    -- Set up current input monitoring (feedback LEDs from display component)
    for i = 1, 10 do
        local currentInputControl = display[displayControls.currentInput .. i]
        if currentInputControl then
            currentInputControl.EventHandler = function(ctl)
                if ctl.Boolean then
                    local inputName = self.displayModule:getCurrentInput(index)
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
        WallControlsNames = {},
        RoomControlsNames = {},
        MatrixControlsNames = {},
    }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
        elseif comp.Type == self.componentTypes.wallControls then
            table.insert(namesTable.WallControlsNames, comp.Name)
        elseif comp.Type == self.componentTypes.matrixControls then
            table.insert(namesTable.MatrixControlsNames, comp.Name)
        elseif comp.Type == self.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(namesTable.RoomControlsNames, comp.Name)
        end
    end

    -- Sort all lists
    for _, list in pairs(namesTable) do
        table.sort(list)
    end

    -- Access Controls directly to ensure we see them when they become available
    if Controls.devDisplays then
        self:debugPrint("Found " .. #namesTable.DisplayNames .. " display components")
        -- Add [Clear] option after reporting count
        table.insert(namesTable.DisplayNames, self.clearString)
        for i, _ in ipairs(Controls.devDisplays) do
            Controls.devDisplays[i].Choices = namesTable.DisplayNames
        end
        self:debugPrint("Set choices for " .. #Controls.devDisplays .. " display controls")
    end
    
    if Controls.compWallControls then
        self:debugPrint("Found " .. #namesTable.WallControlsNames .. " wall control components")
        -- Add [Clear] option after reporting count
        table.insert(namesTable.WallControlsNames, self.clearString)
        Controls.compWallControls.Choices = namesTable.WallControlsNames
    end
    
    if Controls.compMatrixControls then
        self:debugPrint("Found " .. #namesTable.MatrixControlsNames .. " matrix control components")
        -- Add [Clear] option after reporting count
        table.insert(namesTable.MatrixControlsNames, self.clearString)
        Controls.compMatrixControls.Choices = namesTable.MatrixControlsNames
    end
    
    if Controls.compRoomControls then
        -- Add [Clear] option for consistency
        table.insert(namesTable.RoomControlsNames, self.clearString)
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end
end

-----------------------------[ Room Name Management ]-----------------------------
function MXNetDisplayController:updateRoomNameFromComponent()
    if self.components.roomControls then
        local roomNameControl = self.components.roomControls["roomName"]
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
        self:handleTimerCompletion(true)
    end

    self.timers.cooldown.EventHandler = function()
        self:handleTimerCompletion(false)
    end
end

-----------------------------[ Batch Event Registration ]-----------------------------
function MXNetDisplayController:registerEventHandlers()
    -- Single control event handler map
    local singleControlHandlers = {
        compRoomControls = function() self:setRoomControlsComponent() end,
        compWallControls = function() self:setWallControlsComponent() end,
        compMatrixControls = function() self:setMatrixControlsComponent() end,
        -- btnDisplayInputAll removed - no longer in UI
        defaultSourceIndex = function(ctl)
            local isValid, value = validateNumericComboBoxSelection(
                ctl, 1, self.config.maxSources, self.clearString, "defaultSourceIndex"
            )
            
            if value == nil then
                self:debugPrint("defaultSourceIndex cleared - auto source selection disabled")
            elseif isValid then
                self:debugPrint("defaultSourceIndex changed to source " .. value)
            else
                self:debugPrint("defaultSourceIndex has invalid selection")
            end
        end,
        defaultInputSelect = function(ctl)
            local selectedInput = ctl.String
            
            if not selectedInput or selectedInput == "" then
                self:debugPrint("defaultInputSelect cleared - using fallback default: " .. self.config.defaultInput)
                ctl.Color = "white"
            elseif self.displayCommands[selectedInput] then
                self:debugPrint("defaultInputSelect changed to: " .. selectedInput)
                ctl.Color = "white"
            else
                self:debugPrint("defaultInputSelect has invalid selection: " .. selectedInput)
                ctl.Color = "pink"
            end
        end
    }
    
    -- Register single control handlers
    for controlName, handler in pairs(singleControlHandlers) do
        bind(controls[controlName], handler)
    end
    
    -- Array control event handler map
    local arrayControlHandlers = {
        btnDisplayPowerOn = function(index, ctl) self.powerModule:powerOnDisplay(index) end,
        btnDisplayPowerOff = function(index, ctl) self.powerModule:powerOffDisplay(index) end,
        btnDisplayPowerSingle = function(index, ctl)
            if ctl.Boolean then 
                self.powerModule:powerOnDisplay(index) 
            else 
                self.powerModule:powerOffDisplay(index) 
            end
        end,
        btnDisplayAllOffOn = function(index, ctl)
            if index == 1 then
                self.powerModule:powerOffAll()
            elseif index == 2 then
                self.powerModule:powerOnAll()
                -- Set all displays to default input after power on
                self.displayModule:setInputAllDelayed(self:getDefaultInput(), self.config.displayInputDelay)
            end
        end,
        
        ledDisplayPower = function(index, ctl)
            -- NOTE: EventHandler only fires on external changes (UCI, other scripts, component feedback)
            -- For internal script power changes, auto-selection is called directly in powerSingle/powerAll
            if ctl.Boolean then
                -- Set individual display to default input when powered on
                self.displayModule:setInputSingleDelayed(index, self:getDefaultInput(), self.config.displayInputDelay)
                
                -- Trigger auto source selection for display 1
                if index == 1 then
                    self:handleAutoDefaultSourceSelection(index)
                end
            end
        end,

        devDisplays = function(index, ctl) self:setDisplayComponent(index) end,

        btnSource = function(index, ctl) 
            self:debugPrint("Source button " .. index .. " pressed")
            self:selectSource(index)
            
            -- TODO: Add feedback from compMatrixControls component
            -- Challenge: Reference point changes per selected decoder
            -- Will need to monitor MatrixTiePinAV controls for selected decoders
            -- and update button states based on which encoder is routed to those decoders
             
        end,

        compDecoderSelect = function(index, ctl)
            local wasInitialized = ensureChoicesInitialized(
                ctl, 
                function() self.matrixModule:setDecoderChoices() end,
                "compDecoderSelect"
            )
            
            if not wasInitialized then
                self:debugPrint("Setting decoder choices for control " .. index .. " (late initialization)")
            end
            
            local isValid, value = validateNumericComboBoxSelection(
                ctl, 1, self.config.maxDecoders, self.clearString, "compDecoderSelect"
            )
            
            if value == nil then
                self:debugPrint("Decoder selector " .. index .. " cleared")
            elseif isValid then
                self:debugPrint("Decoder selector " .. index .. " changed to decoder " .. value)
            else
                self:debugPrint("Decoder selector " .. index .. " has invalid selection")
            end
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
    self:setMatrixControlsComponent()
    self:setupDisplayComponents()
    self:registerEventHandlers()
    self:registerTimerHandlers()
    self:updateRoomNameFromComponent()
    
    -- Set decoder choices independently of matrix component availability
    self.matrixModule:setDecoderChoices()
    
    -- Set default source index choices for auto-selection combo box
    self:setDefaultSourceIndexChoices()
    
    -- Set default input choices for input selection combo box
    self:setDefaultInputSelectChoices()
    
    self.powerModule:updatePowerFeedbackFromDisplays()
    self.powerModule:resetAllPowerButtonLegends()
    self:updateTimerConfigFromComponent()
    
    -- Determine operating mode
    local operatingMode = "No routing configured"
    if self.components.wallControls then
        operatingMode = "wallControls mode"
    elseif self.components.matrixControls then
        operatingMode = "matrixControls mode"
    end
    
    self:debugPrint("MXNet DisplayWallController Initialized")
    self:debugPrint("  Displays: " .. self.displayModule:getDisplayCount())
    self:debugPrint("  Operating mode: " .. operatingMode)
    
    if self.components.wallControls and self.components.matrixControls then
        self:debugPrint("  WARNING: Both wallControls and matrixControls configured - wallControls has priority")
    end
end

-----------------------------[ Cleanup ]-----------------------------
function MXNetDisplayController:cleanup()
    for i, display in pairs(self.components.displays) do
        if display then
            -- NOTE: MXNet Decoder doesn't have PowerStatus control - no cleanup needed
            
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
    
    -- Clean up matrix controls component reference
    if self.components.matrixControls then
        self.components.matrixControls = nil
    end
    
    self.components = {
        displays = {},
        wallControls = nil,
        matrixControls = nil,
        roomControls = nil,
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
local config = { 
    debugging = true, 
    maxDisplays = 9, 
    maxSources = 12
}

myMXNetDisplayWallController = createMXNetDisplayWallController(roomName, config)

if myMXNetDisplayWallController then
    print("SUCCESS: MXNet DisplayWallController created and initialized!")
    print("Room: " .. roomName)
    print("Display count: " .. myMXNetDisplayWallController.displayModule:getDisplayCount())
    
    -- Determine operating mode
    local operatingMode = "No routing configured"
    if myMXNetDisplayWallController.components.wallControls then
        operatingMode = "wallControls mode"
    elseif myMXNetDisplayWallController.components.matrixControls then
        operatingMode = "matrixControls mode"
    end
    print("Operating mode: " .. operatingMode)
    
    if myMXNetDisplayWallController.components.wallControls and myMXNetDisplayWallController.components.matrixControls then
        print("WARNING: Both wallControls and matrixControls configured - wallControls has priority")
    end
    
    -- Export instance globally for external access
    MXNetDisplayWallControllerInstance = myMXNetDisplayWallController
else
    print("ERROR: Failed to create MXNet DisplayWallController!")
end

--[[
  REFACTORING SUMMARY:
  ✓ Comprehensive control validation with descriptive error messages
  ✓ Control array normalization for consistent data structures
  ✓ Essential utility functions (isArr, setProp, bind, bindArray, forEach)
  ✓ BaseModule pattern for modular architecture (Principle 18)
  ✓ Display, Power, Wall, and Matrix modules inherit from BaseModule
  ✓ Batch event registration using handler maps (Principles 17, 24)
  ✓ State management utility for dynamic component arrays
  ✓ Factory function with enhanced error handling
  ✓ Optimized property access with cached references
  ✓ Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
  ✓ Uses setProp() throughout to prevent redundant property assignments
  ✓ Removed safeComponentAccess wrapper - direct access with guards (Principle 4)
  ✓ Configuration-driven power operations (Principle 32)
  ✓ Generic timer completion handler eliminates duplication (Principle 23)
  ✓ Centralized error/status reporting utilities (Principles 22, 23)
  ✓ Generic button legend utilities for DRY code (Principle 21)
  ✓ Flattened control flow with early returns (Principle 2)
  ✓ forEach utility for cleaner iteration patterns
  ✓ Power and Input control for individual displays
  ✓ RS232 command-based control (MXNet protocol) with direct access
  ✓ DRY helper function for RS232 command transmission
  ✓ Power commands: ka 00 01\r (on), ka 00 00\r (off)
  ✓ Input commands: xb 00 <hex>\r for HDMI1, HDMI2
  ✓ Automatic Rs232Tx string population and Rs232TxSend pulse control
  ✓ Support for MX Net Video Wall 4x4 component
  ✓ 12 encoder sources (ENC-01 through ENC-12)
  ✓ Source selection via button array (btnSource[1-12])
  ✓ Dynamic layout selection control population
  ✓ Component discovery for wall controls
  ✓ Individual decoder routing via matrix controls (v2.3)
  ✓ Support for 35 MXNet decoders (MatrixTiePinAV 1-35)
  ✓ Multiple decoder selection via compDecoderSelect array
  ✓ Source to encoder mapping (1-12 sources to encoders)
  ✓ Simplified mode operation: wallControls OR matrixControls (v2.5)
  ✓ wallControls has priority if both are configured
  ✓ External decoder routing should be handled outside this script
  ✓ Batch routing to multiple selected decoders with error reporting
  ✓ Automatic default source selection when display 1 turns on (v2.4)
  ✓ UI-based defaultSourceIndex combo box control for per-instance configuration
  ✓ Choices: [Clear], 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
  ✓ Auto-selection disabled when set to [Clear]
  ✓ DRY source selection logic extracted into reusable selectSource() method
  
  ADVANCED PATTERNS IMPLEMENTED:
  ✓ BaseModule class with inheritance (metatable-based OOP)
  ✓ Configuration tables for power operations eliminate code duplication
  ✓ Generic executePowerOperation() replaces 4 nearly-identical functions
  ✓ Centralized handleTimerCompletion() eliminates timer handler duplication
  ✓ Direct component access replaces 40+ lines of safeComponentAccess wrapper
  ✓ printOperationResult() and handleBatchResult() for consistent error reporting
  ✓ forEach() utility enables cleaner functional patterns throughout
]]
