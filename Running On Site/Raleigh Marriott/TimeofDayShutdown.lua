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
    btnResetEnabled = Controls.btnResetEnabled
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
    
    local requiredControls = {'btnSystemOff'}
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
    elseif not components.todShutdownReset['enable'] then
        table.insert(missing, "todShutdownReset 'enable' control")
    end
    
    -- Validate script control
    if not controls.btnResetEnabled then
        table.insert(missing, "btnResetEnabled script control")
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
    print("DEBUG: handleTimeOfDayShutdown called - active state: " .. tostring(components.todShutdownReset['active'].Boolean))
    
    -- Only execute when todShutdownReset active becomes true AND enable is true
    if not controls.btnResetEnabled.Boolean then
        print("DEBUG: Enable is false, shutdown is disabled")
        return
    end
    
    if not components.todShutdownReset['active'].Boolean then
        print("DEBUG: Active is false, returning early")
        return
    end
    
    print("Time of Day Shutdown triggered - powering off all rooms")
    
    -- Loop through all room controls and trigger power off
    for _, config in ipairs(roomConfig) do
        local roomControl = components[config.roomControlName]
        if roomControl and roomControl['btnSystemOff'] then
            print("  Triggering power off for " .. config.roomName)
            local success, err = pcall(function()
                roomControl['btnSystemOff']:Trigger()
            end)
            if not success then
                print("  ERROR: Failed to trigger power off for " .. config.roomName .. ": " .. tostring(err))
            end
        else
            print("  WARNING: Could not access btnSystemOff for " .. config.roomName)
            if roomControl then
                print("    Component exists but btnSystemOff control not found")
            else
                print("    Component reference is nil")
            end
        end
    end
end

local function handleEnableChange()
    local enableCtrl = controls.btnResetEnabled
    
    -- Update the legend based on state
    if enableCtrl.Boolean then
        setProp(enableCtrl, 'Legend', 'Enabled')
        print("Time of Day shutdown enabled")
    else
        setProp(enableCtrl, 'Legend', 'Disabled\nEnabled at 7:00AM')
        print("Time of Day shutdown disabled - will re-enable at 7:00 AM")
    end
    
    -- Sync the state to the component control to enable/disable the todShutdownReset component
    if components.todShutdownReset['enable'] then
        components.todShutdownReset['enable'].Boolean = enableCtrl.Boolean
    end
end

local function checkAndEnableAt7AM()
    local currentTime = os.date("*t")
    
    -- Check if it's 7:00 AM (hour 7, minute 0)
    if currentTime.hour == 7 and currentTime.min == 0 then
        if controls.btnResetEnabled and not controls.btnResetEnabled.Boolean then
            print("7:00 AM reached - enabling Time of Day shutdown")
            controls.btnResetEnabled.Boolean = true
            -- Sync to component control
            if components.todShutdownReset['enable'] then
                components.todShutdownReset['enable'].Boolean = true
            end
        end
    end
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind Time of Day shutdown trigger
    if components.todShutdownReset and components.todShutdownReset['active'] then
        print("DEBUG: Registering event handler for todShutdownReset['active']")
        print("DEBUG: Initial state of todShutdownReset['active'].Boolean: " .. tostring(components.todShutdownReset['active'].Boolean))
        bind(components.todShutdownReset['active'], handleTimeOfDayShutdown)
        print("Time of Day shutdown handler registered successfully")
    else
        print("ERROR: Cannot register event handler - component or control missing")
    end
    
    -- Bind Enable control
    if controls.btnResetEnabled then
        bind(controls.btnResetEnabled, handleEnableChange)
        -- Initialize the legend on startup
        handleEnableChange()
        print("Time of Day enable handler registered successfully")
    else
        print("ERROR: Cannot register enable event handler - script control missing")
    end
    
    -- Setup timer to check for 7:00 AM every minute
    Timer.New():Start(function()
        checkAndEnableAt7AM()
    end, 60)
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

