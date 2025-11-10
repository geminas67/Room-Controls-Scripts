--[[
    Simple Display Controller - Time of Day Shutdown (System Reset) (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2025-11-10
    Firmware Req: 10.0.0
    Description: Responds to Time of Day Active change and triggers Power Off commands.
]]

-------------------[ Configuration ]-------------------
local roomConfig = {
    { roomControlName = 'roomControlsSalonA', componentName = 'compRoomControlsSalonA', roomName = 'Salon A' },
    { roomControlName = 'roomControlsSalonB', componentName = 'compRoomControlsSalonB', roomName = 'Salon B' },
    { roomControlName = 'roomControlsSalonC', componentName = 'compRoomControlsSalonC', roomName = 'Salon C' },
    { roomControlName = 'roomControlsSalonD', componentName = 'compRoomControlsSalonD', roomName = 'Salon D' },
    { roomControlName = 'roomControlsSalonE', componentName = 'compRoomControlsSalonE', roomName = 'Salon E' },
    { roomControlName = 'roomControlsSalonF', componentName = 'compRoomControlsSalonF', roomName = 'Salon F' },
    { roomControlName = 'roomControlsSalonG', componentName = 'compRoomControlsSalonG', roomName = 'Salon G' },
    { roomControlName = 'roomControlsSalonH', componentName = 'compRoomControlsSalonH', roomName = 'Salon H' }
}

-------------------[ Component References ]-------------------
local components = {
    todShutdownReset = Component.New('todShutdownReset')
}

-- Build room control components from configuration
for _, config in ipairs(roomConfig) do
    components[config.roomControlName] = Component.New(config.componentName)
end

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
local function validateRoomControl(roomControlName, missing)
    local roomControl = components[roomControlName]
    if not roomControl then
        table.insert(missing, roomControlName .. " component")
        return
    end
    
    local requiredControls = {'btnSystemOffTrig'}
    for _, controlName in ipairs(requiredControls) do
        if not roomControl[controlName] then
            table.insert(missing, roomControlName .. " " .. controlName .. " control")
        end
    end
end

local function validateControls()
    local missing = {}
    
    -- Validate time of day shutdown trigger component
    if not components.todShutdownReset then
        table.insert(missing, "todShutdownReset component")
    elseif not components.todShutdownReset['active'] then
        table.insert(missing, "todShutdownReset 'active' control")
    end
    
    -- Validate configured room controls
    for _, config in ipairs(roomConfig) do
        validateRoomControl(config.roomControlName, missing)
    end
    
    if #missing > 0 then
        print("ERROR: TimeOfDayShutdown validation failed - Missing:")
        for _, name in ipairs(missing) do
            print("  - " .. name)
        end
        return false
    end
    
    print("TimeOfDayShutdown validation passed")
    return true
end

-------------------[ Control Normalization ]-------------------
local function normalizeControlArrays()
    -- No arrays to normalize in this script
end

-------------------[ Core Logic ]-------------------
-- (Core logic implemented in handleTimeOfDayShutdown)

-------------------[ Event Handlers ]-------------------
local function handleTimeOfDayShutdown()
    -- Only execute when todShutdownReset active becomes true
    if not components.todShutdownReset['active'].Boolean then
        return
    end
    
    print("Time of Day Shutdown triggered - powering off all rooms")
    
    -- Loop through all room controls and trigger power off
    for _, config in ipairs(roomConfig) do
        local roomControl = components[config.roomControlName]
        if roomControl and roomControl['btnSystemOffTrig'] then
            print("  Triggering power off for " .. config.roomName)
            roomControl['btnSystemOffTrig']:Trigger()
        else
            print("  WARNING: Could not trigger power off for " .. config.roomName)
        end
    end
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind Time of Day shutdown trigger
    if components.todShutdownReset and components.todShutdownReset['active'] then
        bind(components.todShutdownReset['active'], handleTimeOfDayShutdown)
        print("Time of Day shutdown handler registered")
    end
end

local function funcInit()
    if not validateControls() then
        print("ERROR: TimeOfDayShutdown failed to initialize - validation failed")
        return
    end
    
    normalizeControlArrays()
    registerEventHandlers()
    
    print("TimeOfDayShutdown initialized successfully")
end

-------------------[ Main Execution ]-------------------
funcInit()

