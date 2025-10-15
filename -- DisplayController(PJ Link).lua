--[[
  PJLink DisplayController (Refactored) - Q-SYS Control Script for PJLink Displays
  Author: Nikolas Smith, Q-SYS
  Date: 2025-10-14
  Version: 2.0 (Power & Input Only)
  Firmware Req: 10.0.0
  Description: Controls PJLink Display components with power management and
  input switching. Integrates with SystemAutomationController.
  
  REFACTORED FEATURES:
  - Enhanced validation with descriptive error messages
  - Array normalization for consistent control structures
  - Batch event registration using handler maps
  - Modular architecture with simplified modules
  - Efficient utility functions with standard patterns
  - State management utilities following SystemAutomationController patterns
  - Factory functions with comprehensive error handling
  - Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
]]--

-- Display Control Configuration (easily changeable for different manufacturers)
local displayControls = {
    -- Power Controls
    displayPower = "Power",
    displayPowerStatus = "PowerStatus",
    -- Input Controls
    inputSelectButtons = "VideoInputs",
    inputNames = "VideoInputNames",
    currentInput = "VideoInput"
}

-- Input Controls (refactored for Boolean-only selection)
local inputControls = {
    ["Digital 1"] = "Digital 1",
    ["Digital 2"] = "Digital 2",
    ["Digital 3"] = "Digital 3",
    ["Digital 4"] = "Digital 4",
    ["RGB 1"] = "RGB 1",
    ["Video 1"] = "Video 1"
}

-------------------[ Control References ]-------------------
local controls = {
    txtStatus = Controls.txtStatus,
    devDisplays = Controls.devDisplays,
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
    btnDisplayInputAll = Controls.btnDisplayInputAll
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
        print("ERROR: PJLinkDisplayController validation failed - Missing required controls:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("PJLinkDisplayController validation passed")
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
PJLinkDisplayController = {}
PJLinkDisplayController.__index = PJLinkDisplayController

function PJLinkDisplayController.new(roomName, config)
    -- Validate controls before initialization
    if not validateControls() then
        return nil
    end
    
    -- Normalize control arrays at initialization
    normalizeControlArrays()
    
    local self = setmetatable({}, PJLinkDisplayController)
    
    -- Initialize state management
    self.componentState = resetComponentsArray()
    
    -- Instance properties
    self.roomName = roomName or "Default Room"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"

    self.componentTypes = {
        displays = "%PLUGIN%_80a40a84-e685-4b13-a5c4-fbdc12bd85e6_%FP%_5a33e0144dd58457817a00cb87f4f4a9",  -- PJ Link Display
        roomControls = "device_controller_script"
    }
    
    -- Component storage
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    -- State tracking
    self.state = {
        lastInput = "Digital 1",
        powerState = false,
        isWarming = false,
        isCooling = false
    }
    
    -- Configuration
    self.config = {
        maxDisplays = config and config.maxDisplays or 9,
        defaultInput = "Digital 1",
        inputChoices = {"RGB 1", "Video 1", "Digital 1", "Digital 2", "Digital 3", "Digital 4"}
    }
    
    -- Input to button mapping
    self.inputButtonMap = {
        RGB = 1, 
        Video = 2, 
        Digital1 = 3, 
        Digital2 = 4,
        Digital3 = 5, 
        Digital4 = 6
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
    self:updateTimerConfigFromComponent()
    
    return self
end

-----------------------------[ Debug Helper ]-----------------------------
function PJLinkDisplayController:debugPrint(str)
    if self.debugging then print("["..self.roomName.." Debug] "..str) end
end

-----------------------------[ Dynamic Timer Configuration ]-----------------------------
function PJLinkDisplayController:updateTimerConfigFromComponent()
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

function PJLinkDisplayController:getTimerConfig(isWarmup)
    self:updateTimerConfigFromComponent()
    return isWarmup and self.timerConfig.warmupTime or self.timerConfig.cooldownTime
end

-----------------------------[ Input Button Mapping ]-----------------------------
function PJLinkDisplayController:getInputButtonNumber(input)
    -- Normalize common alternate spellings/labels
    local normalizedInput = input:gsub("Input", "")
    local buttonNumber = self.inputButtonMap[normalizedInput]
    if not buttonNumber then
        self:debugPrint("WARNING: No button mapping found for input: " .. input)
    end
    return buttonNumber
end

-----------------------------[ Safe Component Access ]-----------------------------
function PJLinkDisplayController:safeComponentAccess(component, control, action, value)
    local success, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value
                return true
            elseif action == "setString" then
                component[control].String = value
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

-----------------------------[ Display Module ]-----------------------------
function PJLinkDisplayController:initDisplayModule()
    local selfRef = self
    self.displayModule = {
        powerAll = function(state)
            selfRef:debugPrint("Powering all displays: " .. tostring(state))
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    local control = state and displayControls.displayPower or displayControls.displayPower
                    selfRef:safeComponentAccess(display, control, "trigger")
                end
            end
            selfRef.state.powerState = state
            setProp(controls.ledDisplayPower, "Boolean", state)
        end,
        
        powerSingle = function(index, state)
            local display = selfRef.components.displays[index]
            if display then
                selfRef:safeComponentAccess(display, displayControls.displayPower, "trigger")
                selfRef:debugPrint("Display " .. index .. " power: " .. tostring(state))
            end
        end,
        
        setInputAll = function(input)
            selfRef:debugPrint("Setting all displays to input: " .. input)
            for i, display in pairs(selfRef.components.displays) do
                if display then
                    local controlName = inputControls[input]
                    if controlName and display[controlName] then
                        selfRef:safeComponentAccess(display, controlName, "trigger")
                    else
                        selfRef:debugPrint("Input control not found for: " .. tostring(input))
                    end
                end
            end
            selfRef.state.lastInput = input
            setProp(controls.ledDisplayInput, "String", input)
        end,
        
        setInputSingle = function(index, input)
            local display = selfRef.components.displays[index]
            if display then
                local controlName = inputControls[input]
                if controlName and display[controlName] then
                    selfRef:safeComponentAccess(display, controlName, "trigger")
                    selfRef:debugPrint("Display " .. index .. " input: " .. input)
                else
                    selfRef:debugPrint("Input control not found for: " .. tostring(input))
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
            
            -- Check for input types that exist in PJLink displays
            local inputTypes = {"SelectedDigital", "SelectedVideo", "SelectedRGB"}
            for _, prefix in ipairs(inputTypes) do
                for i = 1, 4 do
                    local controlName = prefix .. " " .. i
                    if display[controlName] and display[controlName].Boolean then
                        local baseName = controlName:gsub("Selected", "")
                        local nameControl = baseName .. "Name " .. i
                        if display[nameControl] and display[nameControl].String ~= "" then
                            return display[nameControl].String
                        else
                            return controlName
                        end
                    end
                end
            end
            return nil
        end
    }
end

-----------------------------[ Power Module ]-----------------------------
function PJLinkDisplayController:initPowerModule()
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
                    local powerStatus = selfRef:safeComponentAccess(display, displayControls.displayPowerStatus, "get")
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

-----------------------------[ Component Management ]-----------------------------
function PJLinkDisplayController:setComponent(ctrl, componentType)
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

function PJLinkDisplayController:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function PJLinkDisplayController:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function PJLinkDisplayController:checkStatus()
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
function PJLinkDisplayController:setupDisplayComponents()
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

function PJLinkDisplayController:setRoomControlsComponent()
    self.components.compRoomControls = self:setComponent(Controls.compRoomControls, "Room Controls")
    if self.components.compRoomControls then
        self:updateTimerConfigFromComponent()
    end
end

function PJLinkDisplayController:setDisplayComponent(index)
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
function PJLinkDisplayController:setupDisplayEvents(index)
    local display = self.components.displays[index]
    if not display then return end
    
    -- Set up power status monitoring
    if display[displayControls.displayPowerStatus] then
        display[displayControls.displayPowerStatus].EventHandler = function()
            local powerState = self:safeComponentAccess(display, displayControls.displayPowerStatus, "get")
            local componentName = Controls.devDisplays and Controls.devDisplays[index] and Controls.devDisplays[index].String or "Unknown"
            self:debugPrint("Display " .. componentName .. " power status: " .. tostring(powerState))
            self.powerModule.updatePowerFeedbackFromDisplays()
        end
    end
    
    -- Set up input monitoring
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

-----------------------------[ Dynamic Component Discovery ]-----------------------------
function PJLinkDisplayController:getComponentNames()
    local namesTable = {
        DisplayNames = {},
        RoomControlsNames = {},
    }

    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.displays then
            table.insert(namesTable.DisplayNames, comp.Name)
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
    
    if Controls.compRoomControls then
        Controls.compRoomControls.Choices = namesTable.RoomControlsNames
    end
end

-----------------------------[ Room Name Management ]-----------------------------
function PJLinkDisplayController:updateRoomNameFromComponent()
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
function PJLinkDisplayController:registerTimerHandlers()
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
function PJLinkDisplayController:registerEventHandlers()
    -- Single control event handler map
    local singleControlHandlers = {
        compRoomControls = function() self:setRoomControlsComponent() end,
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
        devDisplays = function(index, ctl) self:setDisplayComponent(index) end
    }
    
    -- Register array control handlers
    for controlName, handler in pairs(arrayControlHandlers) do
        bindArray(controls[controlName], handler)
    end
end

-----------------------------[ Initialization ]-----------------------------
function PJLinkDisplayController:funcInit()
    self:debugPrint("Starting PJLink DisplayController initialization...")
    
    self:getComponentNames()
    self:setRoomControlsComponent()
    self:setupDisplayComponents()
    self:registerEventHandlers()
    self:registerTimerHandlers()
    self:updateRoomNameFromComponent()
    
    self.powerModule.updatePowerFeedbackFromDisplays()
    self:updateTimerConfigFromComponent()
    
    self:debugPrint("PJLink DisplayController Initialized with " .. 
                   self.displayModule.getDisplayCount() .. " displays")
end

-----------------------------[ Cleanup ]-----------------------------
function PJLinkDisplayController:cleanup()
    for i, display in pairs(self.components.displays) do
        if display then
            if display[displayControls.displayPowerStatus] then
                display[displayControls.displayPowerStatus].EventHandler = nil
            end
        end
    end
    
    self.components = {
        displays = {},
        compRoomControls = nil,
        invalid = {}
    }
    
    if self.debugging then self:debugPrint("Cleanup completed") end
end

-----------------------------[ Factory Function ]-----------------------------
local function createPJLinkDisplayController(roomName, config)
    local defaultRoomName = roomName or "[PJLink Display]"
    print("Creating PJLink DisplayController for: " .. defaultRoomName)
    
    local success, controller = pcall(function()
        local instance = PJLinkDisplayController.new(defaultRoomName, config)
        if not instance then
            error("Failed to create controller instance - validation failed")
        end
        instance:funcInit()
        return instance
    end)
    
    if not success then
        print("ERROR: Failed to create PJLink DisplayController: " .. tostring(controller))
        return nil
    end
    
    print("Successfully created and initialized PJLink DisplayController for " .. defaultRoomName)
    return controller
end

-----------------------------[ Global Export and Instance Creation ]-----------------------------
-- Export the class globally for external access
PJLinkDisplayController = PJLinkDisplayController

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
    
    return "[PJLink Display]"
end

-- Create instance
local roomName = getRoomNameFromComponent()
local config = { debugging = true, maxDisplays = 9 }

myPJLinkDisplayController = createPJLinkDisplayController(roomName, config)

if myPJLinkDisplayController then
    print("SUCCESS: PJLink DisplayController created and initialized!")
    print("Room: " .. roomName)
    print("Display count: " .. myPJLinkDisplayController.displayModule.getDisplayCount())
    
    -- Export instance globally for external access
    PJLinkDisplayControllerInstance = myPJLinkDisplayController
else
    print("ERROR: Failed to create PJLink DisplayController!")
end

--[[
  REFACTORING SUMMARY:
  ✓ Comprehensive control validation with descriptive error messages
  ✓ Control array normalization for consistent data structures
  ✓ Essential utility functions (isArr, setProp, bind, bindArray)
  ✓ Modular architecture with Display and Power modules
  ✓ Batch event registration using handler maps
  ✓ State management utility for dynamic component arrays
  ✓ Factory function with enhanced error handling
  ✓ Optimized property access with cached references
  ✓ Follows Lua Refactoring Prompt specifications for event-driven, OOP architecture
  ✓ Uses setProp() throughout to prevent redundant property assignments
  ✓ Removed wall-related controls/functions - Power and Input only (v2.0)
]]

