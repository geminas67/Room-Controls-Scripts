--[[
    Display Controller - Boardroom Power State (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 4.0 | Date: 2025-11-07
    Firmware Req: 10.0.0
    Description: Display power state controller for Boardroom.
                 Receives power commands from SystemAutomationController via btnDisplayAllOffOn[1]/[2].
                 Manages button interlock and power state representation.
                 Actual display/decoder control is handled by other subsystems.
]]

-------------------[ Component References ]-------------------
-- No external component references needed
-- This script governs the boardroom display power state
-- Actual decoder control is handled by SystemAutomationController or other subsystems

-------------------[ Control References ]-------------------
local controls = {
    btnDisplayAllOffOn = Controls.btnDisplayAllOffOn  -- Array: [1] = Off, [2] = On
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
local function validateControls()
    local missing = {}
    
    -- Validate controls
    if not controls.btnDisplayAllOffOn then
        table.insert(missing, "btnDisplayAllOffOn")
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
    if controls.btnDisplayAllOffOn and not isArr(controls.btnDisplayAllOffOn) then
        controls.btnDisplayAllOffOn = { controls.btnDisplayAllOffOn }
    end
end

-------------------[ Core Logic ]-------------------
local function applyPowerState(index)
    local buttonArray = controls.btnDisplayAllOffOn
    if not buttonArray then return end
    
    -- Interlock buttons (1 = Off, 2 = On)
    for i = 1, 2 do
        if buttonArray[i] then
            setProp(buttonArray[i], "Boolean", i == index)
        end
    end
    
    print("Boardroom display power state: " .. (index == 2 and "ON" or "OFF"))
end

-------------------[ Event Handlers ]-------------------
local function handlePowerButtonPress(index)
    applyPowerState(index)
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind power button array (called by SystemAutomation or UCI)
    bindArray(controls.btnDisplayAllOffOn, handlePowerButtonPress)
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