--[[
    Unified Display Controller - CEC + Power Control (Class-Based Refactor)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2025-11-14
    Firmware Req: 10.0.0
    Description: Class-based display controller supporting both CEC commands (displays 2 & 3)
                 and direct power control (display 1), synced with room power selector.
                 Combines CEC decoder control with interlock button pattern.
                 Follows Lua Refactoring Prompt specifications for future extensibility.
]]

-------------------[ Class Definition ]-------------------
DisplayController = {}
DisplayController.__index = DisplayController

-------------------[ Utility Functions ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return false end
    ctrl[prop] = val
    return true
end

local function bind(ctrl, handler)
    if ctrl and handler then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    if not ctrls then return end
    local array = isArr(ctrls) and ctrls or { ctrls }
    for i, ctrl in ipairs(array) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end

-------------------[ Constructor ]-------------------
function DisplayController.new()
    local self = setmetatable({}, DisplayController)
    
    -- Component references
    self.components = {
        selBoardroomPowerState = Component.New('selBoardroomPowerState'),
        compDisplayControlsMain = Component.New('compDisplayControlsMain'),
        devDecoder29 = Component.New('devDecoder29'),
        devDecoder30 = Component.New('devDecoder30'),
        ucilayerSelector = Component.New('uciLayerSelector'),
        routerPGM = Component.New('routerPGM')
    }
    
    -- Configuration tables
    self.cecDisplayConfig = {
        {
            ledControlName = 'ledDisplayPower 2',
            decoder = 'devDecoder29',
            displayName = 'Display 2'
        },
        {
            ledControlName = 'ledDisplayPower 3',
            decoder = 'devDecoder30',
            displayName = 'Display 3'
        }
    }
    
    self.buttonDisplayConfig = {
        {
            controlName = 'btnDisplayPowerSingle 1',
            displayName = 'Display 1'
        }
    }
    
    -- Source button to router mapping
    self.sourceButtonMap = {
        {buttonIdx = 3, routerValue = 1},
        {buttonIdx = 4, routerValue = 2},
        {buttonIdx = 11, routerValue = 3},
        {buttonIdx = 12, routerValue = 4}
    }
    
    -- UCI to button mapping
    self.uciToButtonMap = {
        {uciSelector = 'selector.3', buttonIdx = 3},
        {uciSelector = 'selector.4', buttonIdx = 4}
    }
    
    -- Control references
    self.controls = {
        btnDisplayPowerOffOn = Controls.btnDisplayPowerOffOn
    }
    
    -- Cached control arrays (populated during normalization)
    self.sourceButtons = {}
    
    -- Validate and initialize
    if not self:validateControls() then
        print("ERROR: DisplayController failed to initialize - validation failed")
        return nil
    end
    
    self:normalizeControlArrays()
    self:registerEventHandlers()
    self:performInitialSync()
    
    print("DisplayController initialized successfully")
    return self
end

-------------------[ Control Validation ]-------------------
function DisplayController:validateDecoder(decoderName, missing)
    local decoder = self.components[decoderName]
    if not decoder then
        table.insert(missing, decoderName .. " component")
        return
    end
    
    local requiredControls = {'CecOn', 'CecOff', 'CecTxSend'}
    for _, controlName in ipairs(requiredControls) do
        if not decoder[controlName] then
            table.insert(missing, decoderName .. " " .. controlName .. " control")
        end
    end
end

function DisplayController:validateControls()
    local missing = {}
    
    -- Validate display controls component
    if not self.components.compDisplayControlsMain then
        table.insert(missing, "compDisplayControlsMain component")
    end
    
    -- Validate room power selector
    if not self.components.selBoardroomPowerState then
        table.insert(missing, "selBoardroomPowerState component")
    end
    
    -- Validate CEC display controls and decoders
    for _, config in ipairs(self.cecDisplayConfig) do
        if self.components.compDisplayControlsMain then
            if not self.components.compDisplayControlsMain[config.ledControlName] then
                table.insert(missing, config.ledControlName .. " control")
            end
        end
        self:validateDecoder(config.decoder, missing)
    end
    
    -- Validate button-controlled display controls
    for _, config in ipairs(self.buttonDisplayConfig) do
        if self.components.compDisplayControlsMain then
            if not self.components.compDisplayControlsMain[config.controlName] then
                table.insert(missing, config.controlName .. " control")
            end
        end
    end
    
    -- Validate interlock power buttons
    if not self.controls.btnDisplayPowerOffOn then
        table.insert(missing, "btnDisplayPowerOffOn")
    end
    
    if #missing > 0 then
        print("ERROR: DisplayController validation failed - Missing:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("DisplayController validation passed")
    return true
end

-------------------[ Control Normalization ]-------------------
function DisplayController:normalizeControlArrays()
    -- Normalize power button array
    if self.controls.btnDisplayPowerOffOn and not isArr(self.controls.btnDisplayPowerOffOn) then
        self.controls.btnDisplayPowerOffOn = { self.controls.btnDisplayPowerOffOn }
    end
    
    -- Cache source button references for efficient access
    for _, mapping in ipairs(self.sourceButtonMap) do
        local btn = self.components.compDisplayControlsMain and 
                    self.components.compDisplayControlsMain['btnSource ' .. mapping.buttonIdx]
        if btn then
            self.sourceButtons[mapping.buttonIdx] = btn
        end
    end
end

-------------------[ Core Logic - CEC Commands ]-------------------
function DisplayController:sendCecCommand(decoder, powerOn)
    if not decoder then return end
    
    local cecCmd = powerOn and decoder['CecOn'] or decoder['CecOff']
    local cecTxSend = decoder['CecTxSend']
    
    if not cecCmd or not cecTxSend then return end
    
    cecCmd:Trigger()
    cecTxSend:Trigger()
end

-------------------[ Core Logic - Power State ]-------------------
function DisplayController:applyPowerState(powerOn)
    local buttonArray = self.controls.btnDisplayPowerOffOn
    if not buttonArray then return end
    
    -- Interlock buttons (1 = Off, 2 = On)
    local index = powerOn and 2 or 1
    for i = 1, 2 do
        if buttonArray[i] then
            setProp(buttonArray[i], "Boolean", i == index)
        end
    end
    
    -- Set button-controlled displays
    for _, config in ipairs(self.buttonDisplayConfig) do
        local ctrl = self.components.compDisplayControlsMain and 
                     self.components.compDisplayControlsMain[config.controlName]
        if ctrl then
            setProp(ctrl, "Boolean", powerOn)
        end
    end
    
    -- Set CEC-controlled displays via their LED controls
    for _, config in ipairs(self.cecDisplayConfig) do
        local ledControl = self.components.compDisplayControlsMain and 
                           self.components.compDisplayControlsMain[config.ledControlName]
        if ledControl then
            setProp(ledControl, "Boolean", powerOn)
        end
    end
end

-------------------[ Event Handlers - CEC Displays ]-------------------
function DisplayController:createCecDisplayPowerHandler(config)
    return function()
        local ledControl = self.components.compDisplayControlsMain[config.ledControlName]
        if not ledControl then return end
        
        local powerOn = ledControl.Boolean
        local decoder = self.components[config.decoder]
        self:sendCecCommand(decoder, powerOn)
    end
end

-------------------[ Event Handlers - Power Buttons ]-------------------
function DisplayController:handlePowerButtonPress(index)
    -- index: 1 = Off, 2 = On
    self:applyPowerState(index == 2)
end

function DisplayController:handleSelectorChange()
    -- Sync with room power selector state
    if self.components.selBoardroomPowerState and 
       self.components.selBoardroomPowerState['selector.1'] then
        local powerOn = self.components.selBoardroomPowerState['selector.1'].Boolean
        self:applyPowerState(powerOn)
    end
end

-------------------[ Event Handlers - Router Sync ]-------------------
function DisplayController:routeSource()
    -- Route source based on which display button is active
    -- Buttons are the SOURCE OF TRUTH - router follows button state
    if not self.components.routerPGM or not self.components.routerPGM['select.1'] then return end
    
    -- Check if btnSource 1 or 2 is active for mute control
    local shouldMute = false
    if self.components.compDisplayControlsMain then
        local btn1 = self.components.compDisplayControlsMain['btnSource 1']
        local btn2 = self.components.compDisplayControlsMain['btnSource 2']
        shouldMute = (btn1 and btn1.Boolean) or (btn2 and btn2.Boolean)
    end
    
    -- Find which cached button is active and set router to that value
    for _, mapping in ipairs(self.sourceButtonMap) do
        local btn = self.sourceButtons[mapping.buttonIdx]
        if btn and btn.Boolean then
            setProp(self.components.routerPGM['select.1'], "Value", mapping.routerValue)
            break
        end
    end
    
    -- Mute router when btnSource 1 or 2 is active, unmute for btnSource 3-12
    if self.components.routerPGM['mute.1'] then
        setProp(self.components.routerPGM['mute.1'], "Boolean", shouldMute)
    end
end

function DisplayController:syncUCIToButtons()
    -- Sync UCI layer selector to display source buttons (configuration-driven)
    if not self.components.ucilayerSelector or not self.components.compDisplayControlsMain then return end
    
    -- Loop through UCI to button mappings
    for _, mapping in ipairs(self.uciToButtonMap) do
        local uciCtrl = self.components.ucilayerSelector[mapping.uciSelector]
        if uciCtrl and uciCtrl.Boolean then
            local btn = self.components.compDisplayControlsMain['btnSource ' .. mapping.buttonIdx]
            if btn then
                setProp(btn, "Boolean", true)
            end
            return  -- Only one selector should be active
        end
    end
end

-------------------[ Event Registration ]-------------------
function DisplayController:registerEventHandlers()
    -- Build handler map for centralized registration
    local handlerMap = {}
    
    -- CEC LED power controls (configuration-driven)
    for _, config in ipairs(self.cecDisplayConfig) do
        local ledControl = self.components.compDisplayControlsMain and 
                          self.components.compDisplayControlsMain[config.ledControlName]
        if ledControl then
            handlerMap[ledControl] = self:createCecDisplayPowerHandler(config)
        end
    end
    
    -- Room power selector
    local selectorCtrl = self.components.selBoardroomPowerState and 
                        self.components.selBoardroomPowerState['selector']
    if selectorCtrl then
        handlerMap[selectorCtrl] = function() self:handleSelectorChange() end
    end
    
    -- UCI layer selector
    local uciSelectorCtrl = self.components.ucilayerSelector and 
                           self.components.ucilayerSelector['selector']
    if uciSelectorCtrl then
        handlerMap[uciSelectorCtrl] = function() self:syncUCIToButtons() end
    end
    
    -- Source buttons (using cached references)
    for buttonIdx, btn in pairs(self.sourceButtons) do
        handlerMap[btn] = function() self:routeSource() end
    end
    
    -- Batch register all handlers
    for ctrl, handler in pairs(handlerMap) do
        if ctrl then bind(ctrl, handler) end
    end
    
    -- Bind power button array (interlock pattern)
    bindArray(self.controls.btnDisplayPowerOffOn, function(index)
        self:handlePowerButtonPress(index)
    end)
end

function DisplayController:performInitialSync()
    -- Initial sync with room power state
    self:handleSelectorChange()
    
    -- Initial sync with UCI layer selector
    self:syncUCIToButtons()
    
    -- Initial router state from buttons (buttons are source of truth)
    self:routeSource()
end

-------------------[ Factory Function ]-------------------
local function createDisplayController()
    local instance = DisplayController.new()
    if not instance then
        print("ERROR: Failed to create DisplayController instance")
        return nil
    end
    return instance
end

-------------------[ Main Execution ]-------------------
-- Create and export instance
displayController = createDisplayController()

-- Export class globally for potential multiple instances or inheritance
_G.DisplayController = DisplayController

