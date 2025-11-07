--[[
    Simple Display Controller - CEC Control (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-01-XX
    Firmware Req: 10.0.0
    Description: CEC display power control for decoders 29 and 30.
                 Responds to LED power state changes and sends CEC commands.
]]

-------------------[ Component References ]-------------------
local components = {
    compDisplayControlsMain = Component.New('compDisplayControlsMain'),
    devDecoder29 = Component.New('devDecoder29'),
    devDecoder30 = Component.New('devDecoder30')
}

-------------------[ Configuration ]-------------------
local displayConfig = {
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

-------------------[ Control References ]-------------------
local controls = {
    -- Controls accessed via components
}

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

-------------------[ Control Validation ]-------------------
local function validateDecoder(decoderName, missing)
    local decoder = components[decoderName]
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

local function validateControls()
    local missing = {}
    
    -- Validate display controls component
    if not components.compDisplayControlsMain then
        table.insert(missing, "compDisplayControlsMain component")
    end
    
    -- Validate configured display controls and decoders
    for _, config in ipairs(displayConfig) do
        if components.compDisplayControlsMain then
            if not components.compDisplayControlsMain[config.ledControlName] then
                table.insert(missing, config.ledControlName .. " control")
            end
        end
        validateDecoder(config.decoder, missing)
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
local function normalizeControlArrays()
    -- No arrays to normalize in this script
end

-------------------[ Core Logic ]-------------------
local function sendCecCommand(decoder, powerOn)
    if not decoder then return end
    
    local cecCmd = powerOn and decoder['CecOn'] or decoder['CecOff']
    local cecTxSend = decoder['CecTxSend']
    
    if not cecCmd or not cecTxSend then return end
    
    -- Set CEC command (On or Off)
    setProp(cecCmd, "Boolean", true)
    
    -- Clear CEC command after 0.2s
    Timer.CallAfter(function()
        setProp(cecCmd, "Boolean", false)
        
        -- Send CEC command after 0.4s total
        Timer.CallAfter(function()
            setProp(cecTxSend, "Boolean", true)
            
            -- Clear send after 0.2s more (0.6s total)
            Timer.CallAfter(function()
                setProp(cecTxSend, "Boolean", false)
            end, 0.2)
        end, 0.2)
    end, 0.2)
end

-------------------[ Event Handlers ]-------------------
local function createDisplayPowerHandler(config)
    return function()
        local ledControl = components.compDisplayControlsMain[config.ledControlName]
        if not ledControl then return end
        
        local powerOn = ledControl.Boolean
        local decoder = components[config.decoder]
        sendCecCommand(decoder, powerOn)
    end
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind LED power controls from configuration
    for _, config in ipairs(displayConfig) do
        local ledControl = components.compDisplayControlsMain[config.ledControlName]
        local handler = createDisplayPowerHandler(config)
        bind(ledControl, handler)
    end
end

local function funcInit()
    if not validateControls() then
        print("ERROR: DisplayController failed to initialize - validation failed")
        return
    end
    
    normalizeControlArrays()
    registerEventHandlers()
    
    print("DisplayController initialized successfully")
end

-------------------[ Main Execution ]-------------------
funcInit()

