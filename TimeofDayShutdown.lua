--[[
    Simple Display Controller - Time of Day Shutdown (System Reset) (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 1.1 | Date: 2025-12-17
    Firmware Req: 10.0.0
    Description: Responds to Time of Day Active change and triggers Power Off commands.
]]

-------------------[ Configuration ]-------------------
-- Time of Day Shutdown Enable Time (24-hour format)
local enableTime = {
    hour = 7,
    min = 0
}

local roomConfig = {
    { roomControlName = 'roomControlsCollabA', componentName = 'compRoomControlsCollabA', roomName = 'Collab A' },
    { roomControlName = 'roomControlsCollabB', componentName = 'compRoomControlsCollabB', roomName = 'Collab B' }
}

-------------------[ Component References ]-------------------
local components = {
    todShutdown = Component.New('todShutdown')
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

-- Debug logging helper
local function debug(msg, ...)
    if ... then
        print(string.format("DEBUG: " .. msg, ...))
    else
        print("DEBUG: " .. msg)
    end
end

-- Safely get component control
local function getControl(component, controlName)
    return component and component[controlName] or nil
end

-- Sync enable state to component
local function syncEnableToComponent(enabled)
    local enableCtrl = getControl(components.todShutdown, 'enable')
    if enableCtrl then
        enableCtrl.Boolean = enabled
    end
end

-------------------[ Control Validation ]-------------------
local function validateComponentControl(component, controlName, missing, displayName)
    if not component then
        table.insert(missing, displayName .. " component")
        return false
    end
    if not component[controlName] then
        table.insert(missing, displayName .. " '" .. controlName .. "' control")
        return false
    end
    return true
end

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
    
    -- Validate time of day shutdown trigger component and its controls
    validateComponentControl(components.todShutdown, 'active', missing, "todShutdown")
    validateComponentControl(components.todShutdown, 'enable', missing, "todShutdown")
    
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
    local activeCtrl = getControl(components.todShutdown, 'active')
    debug("handleTimeOfDayShutdown called - active state: %s", tostring(activeCtrl and activeCtrl.Boolean))
    
    -- Only execute when todShutdown active becomes true AND enable is true
    if not controls.btnResetEnabled.Boolean then
        debug("Enable is false, shutdown is disabled")
        return
    end
    
    if not (activeCtrl and activeCtrl.Boolean) then
        debug("Active is false, returning early")
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
    local timeStr = string.format("%02d:%02d", enableTime.hour, enableTime.min)
    
    -- Update the legend based on state
    if enableCtrl.Boolean then
        setProp(enableCtrl, 'Legend', 'Enabled')
        print("Time of Day shutdown enabled")
    else
        setProp(enableCtrl, 'Legend', 'Disabled\nEnabled at ' .. timeStr)
        print("Time of Day shutdown disabled - will re-enable at " .. timeStr)
    end
    
    -- Sync the state to the component control to enable/disable the todShutdown component
    syncEnableToComponent(enableCtrl.Boolean)
end

local function checkAndEnableAtTimeConfig()
    local currentTime = os.date("*t")
    
    -- Check if it's the configured enable time
    if currentTime.hour == enableTime.hour and currentTime.min == enableTime.min then
        local enableCtrl = controls.btnResetEnabled
        if enableCtrl and not enableCtrl.Boolean then
            local timeStr = string.format("%02d:%02d", enableTime.hour, enableTime.min)
            print(timeStr .. " reached - enabling Time of Day shutdown")
            enableCtrl.Boolean = true
            syncEnableToComponent(true)
        end
    end
end

-------------------[ Initialization ]-------------------
local function registerEventHandlers()
    -- Bind Time of Day shutdown trigger (validation already confirmed it exists)
    local activeCtrl = getControl(components.todShutdown, 'active')
    debug("Registering event handler for todShutdown['active']")
    debug("Initial state of todShutdown['active'].Boolean: %s", tostring(activeCtrl and activeCtrl.Boolean))
    bind(activeCtrl, handleTimeOfDayShutdown)
    print("Time of Day shutdown handler registered successfully")
    
    -- Bind Enable control (validation already confirmed it exists)
    bind(controls.btnResetEnabled, handleEnableChange)
    handleEnableChange() -- Initialize the legend on startup
    print("Time of Day enable handler registered successfully")
    
    -- Setup timer to check for configured enable time every minute
    Timer.New():Start(checkAndEnableAtTimeConfig, 60)
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
