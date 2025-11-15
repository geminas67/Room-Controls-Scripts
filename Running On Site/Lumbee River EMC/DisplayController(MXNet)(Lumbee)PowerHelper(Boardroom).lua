--[[
    Simple Display Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2025-11-07
    Firmware Req: 10.0.0
    Description: Simple display power control synced with room power selector.
                 Controls 3 display components (Dec28, Dec29, Dec30) via interlock pattern.
]]

-------------------[ Component References ]-------------------
local components = {
    selBoardroomPowerState = Component.New('selBoardroomPowerState'),
    compDisplayControlsMain = Component.New('compDisplayControlsMain'),
}

-------------------[ Control References ]-------------------
local controls = {
    btnDisplayPowerOffOn = Controls.btnDisplayPowerOffOn
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
    if not controls.btnDisplayPowerOffOn then
        table.insert(missing, "btnDisplayPowerOffOn")
    end
    
    -- Validate components
    if not components.selBoardroomPowerState then
        table.insert(missing, "selBoardroomPowerState component")
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
    if controls.btnDisplayPowerOffOn and not isArr(controls.btnDisplayPowerOffOn) then
        controls.btnDisplayPowerOffOn = { controls.btnDisplayPowerOffOn }
    end
end

-------------------[ Core Logic ]-------------------
local displayComponents = {
    components.compDisplayControlsMain
}

local function applyPowerState(index)
    local buttonArray = controls.btnDisplayPowerOffOn
    if not buttonArray then return end
    
    -- Interlock buttons (1 = Off, 2 = On)
    for i = 1, 2 do
        if buttonArray[i] then
            setProp(buttonArray[i], "Boolean", i == index)
        end
    end
    
    -- Set all display components to same state (1 = false/off, 2 = true/on)
    local displayState = (index == 2)
    for _, comp in ipairs(displayComponents) do
        if comp and comp['btnDisplayPowerSingle 1'] then
            setProp(comp['btnDisplayPowerSingle 1'], "Boolean", displayState)
        end
    end
end

-------------------[ Event Handlers ]-------------------
local function handlePowerButtonPress(index)
    applyPowerState(index)
end

local function handleSelectorChange()
    -- Sync with room power selector state
    if components.selBoardroomPowerState['selector.1'].Boolean then
        applyPowerState(2)  -- Power On
    else
        applyPowerState(1)  -- Power Off
    end
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind power button array
    bindArray(controls.btnDisplayPowerOffOn, handlePowerButtonPress)
    
    -- Bind room power selector
    bind(components.selBoardroomPowerState['selector'], handleSelectorChange)
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