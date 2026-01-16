--[[
    MXA System State Machine - Centralized State Management
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-01-06
    
    Manages system states for ShureMXAController with explicit state transitions.
    Inspired by PowerStateMachine pattern from SystemAutomationController.
    
    States:
    - IDLE: System on, no call, no alarms, privacy off
    - CALL_ACTIVE: Call is active (off-hook), LEDs on
    - CALL_MUTED: Call active but muted, LEDs red
    - PRIVACY_ACTIVE: No call, audio privacy enabled, LEDs red
    - FIRE_ALARM: Fire alarm active (highest priority), LEDs toggling
    - SYSTEM_OFF: System powered off, all LEDs off
]]

-------------------[ Base Module Class ]-------------------
local BaseModule = {}
BaseModule.__index = BaseModule

function BaseModule.new(controller, name)
    local self = setmetatable({}, BaseModule)
    self.controller = controller
    self.name = name or "Module"
    self.initialized = false
    return self
end

function BaseModule:debug(msg)
    if self.controller and self.controller.debugging then
        print("[" .. self.name .. "] " .. msg)
    end
end

function BaseModule:init()
    self.initialized = true
    self:debug("Module initialized")
end

function BaseModule:cleanup()
    self.initialized = false
    self:debug("Cleanup complete")
end

-------------------[ MXA System State Machine ]-------------------
local MXASystemStateMachine = setmetatable({}, BaseModule)
MXASystemStateMachine.__index = MXASystemStateMachine

-- Define all valid system states
MXASystemStateMachine.States = {
    IDLE = "idle",                      -- Normal operation, no call, no alarms
    CALL_ACTIVE = "call_active",        -- Call is active (off-hook), not muted
    CALL_MUTED = "call_muted",          -- Call active but muted
    PRIVACY_ACTIVE = "privacy_active",  -- No call, audio privacy enabled
    FIRE_ALARM = "fire_alarm",          -- Fire alarm active (highest priority)
    SYSTEM_OFF = "system_off"           -- System powered off
}

-- Define valid state transitions (adjacency list)
MXASystemStateMachine.ValidTransitions = {
    [MXASystemStateMachine.States.IDLE] = {
        MXASystemStateMachine.States.CALL_ACTIVE,
        MXASystemStateMachine.States.PRIVACY_ACTIVE,
        MXASystemStateMachine.States.FIRE_ALARM,
        MXASystemStateMachine.States.SYSTEM_OFF
    },
    [MXASystemStateMachine.States.CALL_ACTIVE] = {
        MXASystemStateMachine.States.CALL_MUTED,
        MXASystemStateMachine.States.IDLE,
        MXASystemStateMachine.States.FIRE_ALARM,
        MXASystemStateMachine.States.SYSTEM_OFF
    },
    [MXASystemStateMachine.States.CALL_MUTED] = {
        MXASystemStateMachine.States.CALL_ACTIVE,
        MXASystemStateMachine.States.IDLE,
        MXASystemStateMachine.States.FIRE_ALARM,
        MXASystemStateMachine.States.SYSTEM_OFF
    },
    [MXASystemStateMachine.States.PRIVACY_ACTIVE] = {
        MXASystemStateMachine.States.IDLE,
        MXASystemStateMachine.States.CALL_ACTIVE,
        MXASystemStateMachine.States.FIRE_ALARM,
        MXASystemStateMachine.States.SYSTEM_OFF
    },
    [MXASystemStateMachine.States.FIRE_ALARM] = {
        MXASystemStateMachine.States.IDLE,
        MXASystemStateMachine.States.CALL_ACTIVE,
        MXASystemStateMachine.States.CALL_MUTED,
        MXASystemStateMachine.States.SYSTEM_OFF
    },
    [MXASystemStateMachine.States.SYSTEM_OFF] = {
        MXASystemStateMachine.States.IDLE
    }
}

function MXASystemStateMachine.new(controller)
    local self = BaseModule.new(controller, "MXASystemStateMachine")
    setmetatable(self, MXASystemStateMachine)
    self.currentState = MXASystemStateMachine.States.IDLE
    self.stateHistory = {}  -- Track state transitions for debugging
    self:init()
    return self
end

-- Validate if transition is allowed
function MXASystemStateMachine:canTransitionTo(newState)
    local validTransitions = MXASystemStateMachine.ValidTransitions[self.currentState]
    if not validTransitions then return false end
    
    for _, validState in ipairs(validTransitions) do
        if validState == newState then return true end
    end
    return false
end

-- Main state transition method
function MXASystemStateMachine:transitionTo(newState, context)
    -- Don't transition if already in this state
    if self.currentState == newState then 
        self:debug("Already in state: " .. newState)
        return 
    end
    
    -- Validate transition
    if not self:canTransitionTo(newState) then
        self:debug("Invalid transition: " .. self.currentState .. " → " .. newState)
        return false
    end
    
    local oldState = self.currentState
    
    -- Call exit handler for old state
    self:onExitState(oldState)
    
    -- Update state
    self.currentState = newState
    
    -- Track history
    table.insert(self.stateHistory, {
        from = oldState,
        to = newState,
        timestamp = os.time(),
        context = context
    })
    
    self:debug("State transition: " .. oldState .. " → " .. newState .. 
               (context and " (context: " .. tostring(context) .. ")" or ""))
    
    -- Call entry handler for new state
    self:onEnterState(newState)
    
    return true
end

-- Exit handlers for each state
function MXASystemStateMachine:onExitState(state)
    if state == MXASystemStateMachine.States.FIRE_ALARM then
        self:onExitFireAlarm()
    end
end

-- Entry handlers for each state
function MXASystemStateMachine:onEnterState(state)
    if state == MXASystemStateMachine.States.IDLE then
        self:onEnterIdle()
    elseif state == MXASystemStateMachine.States.CALL_ACTIVE then
        self:onEnterCallActive()
    elseif state == MXASystemStateMachine.States.CALL_MUTED then
        self:onEnterCallMuted()
    elseif state == MXASystemStateMachine.States.PRIVACY_ACTIVE then
        self:onEnterPrivacyActive()
    elseif state == MXASystemStateMachine.States.FIRE_ALARM then
        self:onEnterFireAlarm()
    elseif state == MXASystemStateMachine.States.SYSTEM_OFF then
        self:onEnterSystemOff()
    end
end

-------------------[ State Entry Handlers ]-------------------
function MXASystemStateMachine:onEnterIdle()
    self:debug("Entering IDLE state")
    self.controller.mxaModule:setAllLEDs(false)
    self.controller.privacyModule:setLEDColor(true)  -- Red = muted
end

function MXASystemStateMachine:onEnterCallActive()
    self:debug("Entering CALL_ACTIVE state")
    self.controller.mxaModule:setAllLEDs(true)
    self.controller.privacyModule:setLEDColor(false)  -- Green = unmuted
end

function MXASystemStateMachine:onEnterCallMuted()
    self:debug("Entering CALL_MUTED state")
    self.controller.mxaModule:setAllLEDs(true)
    self.controller.privacyModule:setLEDColor(true)  -- Red = muted
end

function MXASystemStateMachine:onEnterPrivacyActive()
    self:debug("Entering PRIVACY_ACTIVE state")
    self.controller.mxaModule:setAllLEDs(false)
    self.controller.privacyModule:setLEDColor(true)  -- Red = muted
end

function MXASystemStateMachine:onEnterFireAlarm()
    self:debug("Entering FIRE_ALARM state - starting LED toggle")
    self.controller.privacyModule:setLEDColor(true)  -- Red
    self.controller.mxaModule:startLEDToggle()
end

function MXASystemStateMachine:onEnterSystemOff()
    self:debug("Entering SYSTEM_OFF state")
    self.controller.mxaModule:setAllLEDs(false)
    self.controller.privacyModule:setLEDColor(true)  -- Red = muted
end

-------------------[ State Exit Handlers ]-------------------
function MXASystemStateMachine:onExitFireAlarm()
    self:debug("Exiting FIRE_ALARM state - stopping LED toggle")
    self.controller.mxaModule:stopLEDToggle()
end

-------------------[ State Query Methods ]-------------------
function MXASystemStateMachine:isIdle()
    return self.currentState == MXASystemStateMachine.States.IDLE
end

function MXASystemStateMachine:isCallActive()
    return self.currentState == MXASystemStateMachine.States.CALL_ACTIVE
end

function MXASystemStateMachine:isCallMuted()
    return self.currentState == MXASystemStateMachine.States.CALL_MUTED
end

function MXASystemStateMachine:isPrivacyActive()
    return self.currentState == MXASystemStateMachine.States.PRIVACY_ACTIVE
end

function MXASystemStateMachine:isFireAlarm()
    return self.currentState == MXASystemStateMachine.States.FIRE_ALARM
end

function MXASystemStateMachine:isSystemOff()
    return self.currentState == MXASystemStateMachine.States.SYSTEM_OFF
end

function MXASystemStateMachine:getCurrentState()
    return self.currentState
end

function MXASystemStateMachine:getStateHistory(limit)
    limit = limit or 10
    local count = #self.stateHistory
    local start = math.max(1, count - limit + 1)
    local history = {}
    
    for i = start, count do
        table.insert(history, self.stateHistory[i])
    end
    
    return history
end

-------------------[ Export ]-------------------
return MXASystemStateMachine
