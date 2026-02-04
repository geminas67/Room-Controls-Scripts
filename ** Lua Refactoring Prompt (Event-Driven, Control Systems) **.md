# Lua Refactoring Prompt (Event-Driven Control Systems)

## Objective

Refactor Lua control scripts to be **lean, observable, and maintainable** by:
- Minimizing code complexity while preserving functionality
- Providing comprehensive debug logging for all interactions
- Using a single-class architecture with utility functions
- Following the principle: **"An empty debug window is a useless one"**

---

## 0. Core Philosophy: Lean Code + Rich Debug Output

### 0.1 Code Should Be Lean

**Target Metrics:**
- Aim for 50-70% code reduction from verbose implementations
- Single-class structure with utility functions (not inheritance hierarchies)
- Early returns and guard clauses instead of nested conditionals
- Compact, readable formatting where appropriate

**Example:**
```lua
-- ❌ VERBOSE (many lines, nested)
if control ~= nil then
    if control[prop] ~= value then
        control[prop] = value
    end
end

-- ✅ LEAN (early return, compact)
local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end
```

### 0.2 Debug Output Should Be Comprehensive

**Philosophy:** Every significant action, state change, and interaction must be logged. Debug output is not optional—it's your primary troubleshooting tool.

**What to Log:**
- ✅ Initialization phases and configuration
- ✅ Component discovery (what was found, how many)
- ✅ Event handler registration (what handlers, how many controls)
- ✅ Every routing/switching operation with source (user, UCI, system, etc.)
- ✅ State changes (power on/off, mode changes, layer switches)
- ✅ Integration events (UCI layer changes, system events)
- ✅ Component validation (valid/invalid, errors, warnings)
- ✅ Feedback from hardware (device responses, status updates)
- ✅ User interactions (button presses with context)

**What NOT to Log:**
- ❌ Redundant "already at target state" checks (log once, not continuously)
- ❌ Poll operations unless state actually changes
- ❌ Internal utility operations that happen thousands of times

**Debug Pattern:**
```lua
function MyController:debugPrint(str)
    if self.debugging then print("["..self.roomName.."] "..str) end
end

-- Example outputs with context:
self:debugPrint("=== Initialization Started ===")
self:debugPrint("Configuration: debugging=true, enableOutput2=false")
self:debugPrint("Discovered NV32 Router: devNV32_Device1")
self:debugPrint("Registered 5 button handlers for Output 1")
self:debugPrint("Routed Output 1 → Input 7 (Source: User Button)")
self:debugPrint("UCI Layer changed: nil → 7")
self:debugPrint("Fire Alarm ACTIVATED - storing current inputs")
self:debugPrint("=== Initialization Complete ===")
```

**Debug Sections:**
- Use `===` markers for major phases (Init, Cleanup, etc.)
- Include source attribution: "(Source: User Button)", "(Source: UCI Layer 7)"
- Show before/after for state changes: "Layer changed: 3 → 7"
- Count things: "Registered 5 button handlers", "Found 3 components"
- Mark critical events: "ACTIVATED", "CLEARED", "ERROR:"

---

## 1. Architecture: Single-Class with Utilities

### 1.1 Standard Structure

Use this consistent structure for all control scripts:

```lua
--[[
  Script Name - Q-SYS Control Script
  Brief description of what this controls
]]--

-------------------[ Controls ]-------------------
local controls = {
    control1 = Controls.control1,
    control2 = Controls.control2
}

-------------------[ Utilities ]-------------------
local function isArr(t)
    return type(t) == "table" and t[1] ~= nil
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

local function normalizeControlArrays()
    for _, name in ipairs({'arrayControl1', 'arrayControl2'}) do
        local ctrl = controls[name]
        if ctrl and not isArr(ctrl) then controls[name] = {ctrl} end
    end
end

local function validateControls()
    for _, name in ipairs({"required1", "required2"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end

-------------------[ Controller ]-------------------
MyController = {}
MyController.__index = MyController

function MyController.new(roomName, config)
    if not validateControls() then return nil end
    normalizeControlArrays()
    
    local self = setmetatable({}, MyController)
    self.roomName = roomName or "Default"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    self.components = { device = nil, invalid = {} }
    self.state = { power = false, lastInput = {} }
    self.timers = { monitor = Timer.New() }
    
    return self
end

function MyController:debugPrint(str)
    if self.debugging then print("["..self.roomName.."] "..str) end
end

-------------------[ Component Management ]-------------------
function MyController:setComponent(ctrl, componentType)
    local name = ctrl and ctrl.String
    if not name or name == "" or name == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self.components.invalid[componentType] = false
        self:checkStatus()
        self:debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    if #Component.GetControls(comp) < 1 then
        if ctrl then ctrl.String = "[Invalid]"; ctrl.Color = "pink" end
        self.components.invalid[componentType] = true
        self:checkStatus()
        self:debugPrint("ERROR: " .. componentType .. " component '" .. name .. "' is invalid")
        return nil
    end
    if ctrl then ctrl.Color = "white" end
    self.components.invalid[componentType] = false
    self:checkStatus()
    self:debugPrint("Set " .. componentType .. " component: " .. name)
    return comp
end

function MyController:checkStatus()
    for _, v in pairs(self.components.invalid) do
        if v then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

function MyController:getComponentNames()
    local names = { DeviceNames = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.device then
            table.insert(names.DeviceNames, comp.Name)
            self:debugPrint("Discovered Device: " .. comp.Name)
        end
    end
    table.sort(names.DeviceNames)
    table.insert(names.DeviceNames, self.clearString)
    if controls.devDevice then controls.devDevice.Choices = names.DeviceNames end
    self:debugPrint("Component discovery complete - " .. (#names.DeviceNames - 1) .. " devices found")
end

-------------------[ Event Registration ]-------------------
function MyController:registerEvents()
    bind(controls.devDevice, function() self:setDeviceComponent() end)
    self:debugPrint("Registered event handler for devDevice")
    
    bindArray(controls.buttons, function(i) 
        self:debugPrint("Button " .. i .. " pressed")
        self:handleButton(i, "User Button") 
    end)
    self:debugPrint("Registered " .. #controls.buttons .. " button handlers")
end

-------------------[ Initialization ]-------------------
function MyController:init()
    self:debugPrint("=== Initialization Started ===")
    self:debugPrint("Configuration: debugging=" .. tostring(self.debugging))
    
    self:getComponentNames()
    self:setDeviceComponent()
    
    self:debugPrint("=== Initialization Complete ===")
    self:debugPrint("Ready for operation")
end

-------------------[ Factory & Initialization ]-------------------
local function getRoomName()
    if controls.roomName and controls.roomName.String ~= "" then
        return "["..controls.roomName.String.."]"
    end
    return "[Default Room]"
end

local success, controller = pcall(function()
    local instance = MyController.new(getRoomName(), { debugging = true })
    if not instance then error("Validation failed") end
    instance:registerEvents()
    instance:init()
    return instance
end)

if success then
    myController = controller
    MyControllerInstance = controller
    print("Controller initialized")
else
    print("ERROR: Failed to create controller: " .. tostring(controller))
end
```

### 1.2 Why Single-Class Architecture?

**✅ ADVANTAGES:**
- Clear, linear code flow (easy to trace and debug)
- All logic in one file (no hunting across modules)
- Minimal abstraction overhead
- Maintainable by non-senior programmers
- Consistent structure across all scripts
- Debug output shows complete flow in one place

**❌ AVOID:**
- Multiple inheritance levels (BaseModule → ComponentModule → SpecificModule)
- Abstract base classes that hide concrete implementations  
- Module systems requiring tracing 3+ files to understand one operation
- Over-engineered patterns prioritizing "clean architecture" over maintainability

### 1.3 When to Deviate

Only use multiple classes/modules when:
- Building a reusable library shared across many scripts
- Managing truly polymorphic behavior (same interface, radically different implementations)
- The script is 2000+ lines and logically separates into distinct domains

Otherwise: **one class, utility functions, clear sections**.

---

## 2. Core Refactoring Patterns

### 2.1 Flatten Control Flow with Early Returns

**Pattern:**
```lua
-- ❌ NESTED
function doSomething(input, output)
    if input then
        if output then
            if self.enabled then
                -- actual logic 3 levels deep
            end
        end
    end
end

-- ✅ FLAT with early returns
function doSomething(input, output)
    if not input then return false end
    if not output then return false end
    if not self.enabled then return false end
    -- actual logic at top level
    return true
end
```

### 2.2 Use Utilities Consistently

**Essential Utilities (use everywhere):**
```lua
-- Prevents unnecessary UI updates and feedback loops
local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

-- Clean event handler binding
local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

-- Bind to control arrays
local function bindArray(ctrls, handler)
    if not ctrls then return end
    local array = isArr(ctrls) and ctrls or { ctrls }
    for i, ctrl in ipairs(array) do 
        bind(ctrl, function(ctl) handler(i, ctl) end) 
    end
end
```

**Why `setProp()` Matters:**
- Prevents redundant Q-SYS control updates (expensive operation)
- Guards against feedback loops
- Acts as insurance against race conditions
- Performance optimization (avoid unnecessary UI redraws)

### 2.3 Normalize Control Arrays Once

**Pattern:**
```lua
local function normalizeControlArrays()
    for _, name in ipairs({'btnOutput', 'btnInput', 'devDisplays'}) do
        local ctrl = controls[name]
        if ctrl and not isArr(ctrl) then 
            controls[name] = {ctrl} 
        end
    end
end

-- Call once during initialization
if not validateControls() then return nil end
normalizeControlArrays()  -- Now all arrays are consistent
```

### 2.4 Validate Required Controls

**Pattern:**
```lua
local function validateControls()
    -- Check only truly required controls
    for _, name in ipairs({"devDevice", "txtStatus", "btnPower"}) do
        if not controls[name] then
            print("ERROR: Missing required control: " .. name)
            return false
        end
    end
    return true
end
```

### 2.5 Add Source Context to Operations

**Pattern:**
```lua
-- ❌ NO CONTEXT
function setRoute(input, output)
    self:debugPrint("Routed to input " .. input)
end

-- ✅ WITH CONTEXT (know who triggered it)
function setRoute(input, output, source)
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    self:debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
end

-- Call with context:
self:setRoute(7, 1, "User Button")
self:setRoute(7, 1, "UCI Layer 8")
self:setRoute(7, 1, "System Power")
self:setRoute(7, 1, "Fire Alarm")
```

### 2.6 Variable Naming Conventions

**Philosophy:** Code must be readable when you return to troubleshoot it 3+ months later.

**✅ ACCEPTABLE Abbreviations:**

**3-Letter Control Prefixes** (consistently used in Q-SYS):
```lua
-- These are acceptable and widely understood:
btn = button      -- btnPower, btnMute, btnPreset1
txt = text        -- txtStatus, txtRoomName, txtMessage
ctl = control     -- ctlVolume, ctlFrequency
msg = message     -- msgError, msgStatus
str = string      -- strDeviceName, strInput
cam = camera      -- camMain, camPreset1
mxr = mixer       -- mxrMain, mxrZone1
lvl = level       -- lvlMaster, lvlProgram
dev = device      -- devDisplay, devRouter
led = LED         -- ledPower, ledStatus
```

**Loop Iterators** (universally accepted):
```lua
-- These are standard and acceptable:
for i = 1, #array do            -- ✅ 'i' for index
for i, item in ipairs(list) do  -- ✅ 'i' for index
for k, v in pairs(table) do     -- ✅ 'k' and 'v' for key/value
```

**❌ UNACCEPTABLE Single-Letter Variables:**

```lua
-- ❌ BAD - what are these 3 months later?
for r = 1, #roomList do
    local p = presets[r]
    local c = cameras[r]
    local t = timers[r]
    controls.devCams[r].String = c[1]  -- What is 'c'? 'r'? 
end

-- ✅ GOOD - clear and maintainable
for roomIdx = 1, #roomList do
    local preset = presets[roomIdx]
    local camera = cameras[roomIdx]
    local timer = timers[roomIdx]
    controls.devCams[roomIdx].String = camera[1]
end

-- ❌ BAD - cryptic function parameters
function setRoute(i, o, s)
    if not i or not o then return end
    -- What are 'i', 'o', 's'?
end

-- ✅ GOOD - self-documenting
function setRoute(input, output, source)
    if not input or not output then return end
    -- Clear what each parameter represents
end
```

**Why This Matters:**
- When troubleshooting in production, you need instant comprehension
- Single-letter variables create cognitive load ("what was `r` again?")
- 3-letter control prefixes are Q-SYS conventions (acceptable)
- The few extra characters are worth months of clarity
- Future you (and your teammates) will thank you

**Exception:**
Loop iterators (`i`, `k`, `v`) are universally taught and acceptable because:
- They have a single, well-defined scope (the loop)
- They're used immediately and discarded
- They're a standard convention across all programming languages

---

## 3. Component Management Patterns

### 3.1 Standard Component Setup

**Pattern:**
```lua
function MyController:setComponent(ctrl, componentType)
    local name = ctrl and ctrl.String
    
    -- Handle empty/clear
    if not name or name == "" or name == self.clearString then
        if ctrl then ctrl.Color = "white" end
        self.components.invalid[componentType] = false
        self:checkStatus()
        self:debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    
    -- Validate component
    local comp = Component.New(name)
    if #Component.GetControls(comp) < 1 then
        if ctrl then ctrl.String = "[Invalid]"; ctrl.Color = "pink" end
        self.components.invalid[componentType] = true
        self:checkStatus()
        self:debugPrint("ERROR: " .. componentType .. " component '" .. name .. "' is invalid")
        return nil
    end
    
    -- Success
    if ctrl then ctrl.Color = "white" end
    self.components.invalid[componentType] = false
    self:checkStatus()
    self:debugPrint("Set " .. componentType .. " component: " .. name)
    return comp
end
```

### 3.2 Component Discovery with Logging

**Pattern:**
```lua
function MyController:getComponentNames()
    local names = { DeviceNames = {}, ControlNames = {} }
    
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == self.componentTypes.device then
            table.insert(names.DeviceNames, comp.Name)
            self:debugPrint("Discovered Device: " .. comp.Name)
        elseif comp.Type == self.componentTypes.controls then
            table.insert(names.ControlNames, comp.Name)
            self:debugPrint("Discovered Controls: " .. comp.Name)
        end
    end
    
    -- Sort and add clear option
    for _, list in pairs(names) do
        table.sort(list)
        table.insert(list, self.clearString)
    end
    
    -- Populate choices
    if controls.devDevice then controls.devDevice.Choices = names.DeviceNames end
    if controls.compControls then controls.compControls.Choices = names.ControlNames end
    
    -- Summary
    self:debugPrint("Component discovery complete - " .. 
                    (#names.DeviceNames - 1) .. " devices, " .. 
                    (#names.ControlNames - 1) .. " controls found")
end
```

### 3.3 Component Event Handler Cleanup

**Pattern:**
```lua
function MyController:setDeviceComponent()
    -- Cleanup old handlers before switching
    local device = self.components.device
    if device then
        if device["output1"] then device["output1"].EventHandler = nil end
        if device["output2"] then device["output2"].EventHandler = nil end
        self:debugPrint("Cleanup completed - switching devices")
    end
    
    -- Set new component
    self.components.device = self:setComponent(controls.devDevice, "Device")
    device = self.components.device
    if not device then return end
    
    -- Register new handlers with logging
    if device["output1"] then
        device["output1"].EventHandler = function(ctl)
            self:updateFeedback(1, ctl.Value)
            self:debugPrint("Device Feedback: Output 1 → " .. ctl.Value)
        end
        self:debugPrint("Registered feedback handler for Output 1")
    end
end
```

---

## 4. Event Registration Patterns

### 4.1 Register with Logging

**Pattern:**
```lua
function MyController:registerEvents()
    -- Component selectors
    bind(controls.devDevice, function() self:setDeviceComponent() end)
    self:debugPrint("Registered event handler for devDevice")
    
    bind(controls.compControls, function() self:setControlsComponent() end)
    self:debugPrint("Registered event handler for compControls")
    
    -- Button arrays with user feedback
    bindArray(controls.btnOutput1, function(i) 
        self:debugPrint("Output 1 Button " .. i .. " pressed")
        self:setRoute(self.inputs[i], 1, "User Button") 
    end)
    self:debugPrint("Registered " .. #controls.btnOutput1 .. " button handlers for Output 1")
    
    -- Conditional registration
    if self.enableOutput2 then
        bindArray(controls.btnOutput2, function(i) 
            self:debugPrint("Output 2 Button " .. i .. " pressed")
            self:setRoute(self.inputs[i], 2, "User Button") 
        end)
        self:debugPrint("Registered " .. #controls.btnOutput2 .. " button handlers for Output 2")
    end
end
```

### 4.2 Integration Event Handlers

**Pattern:**
```lua
function MyController:setRoomControlsComponent()
    self.components.roomControls = self:setComponent(controls.compRoomControls, "Room Controls")
    local comp = self.components.roomControls
    if not comp then return end
    
    -- System power handler with detailed logging
    if comp["ledSystemPower"] then
        comp["ledSystemPower"].EventHandler = function(ctl)
            local state = ctl.Boolean
            local targetInput = state and self.inputs.default or self.inputs.standby
            self:debugPrint("System Power " .. (state and "ON" or "OFF") .. 
                          " - switching to input " .. targetInput)
            self:setRoute(targetInput, 1, "System Power")
        end
        self:debugPrint("Registered System Power handler")
    end
    
    -- Fire alarm handler with state tracking
    if comp["ledFireAlarm"] then
        comp["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean and not self.state.fireAlarmActive then
                self:debugPrint("Fire Alarm ACTIVATED - storing current inputs")
                self.state.preFireAlarmInput = self.state.lastInput
                self.state.fireAlarmActive = true
                self:setRoute(self.inputs.alarm, 1, "Fire Alarm")
            elseif not ctl.Boolean and self.state.fireAlarmActive then
                self:debugPrint("Fire Alarm CLEARED - restoring previous inputs")
                self.state.fireAlarmActive = false
                self:setRoute(self.state.preFireAlarmInput or self.inputs.default, 1, "Fire Alarm Clear")
            end
        end
        self:debugPrint("Registered Fire Alarm handler")
    end
end
```

---

## 5. Initialization Pattern

### 5.1 Structured Init with Phase Logging

**Pattern:**
```lua
function MyController:init()
    self:debugPrint("=== Initialization Started ===")
    
    -- Log configuration
    self:debugPrint("Configuration: debugging=" .. tostring(self.debugging) .. 
                    ", enableOutput2=" .. tostring(self.enableOutput2) .. 
                    ", uciEnabled=" .. tostring(self.uci.enabled))
    
    -- Discover components
    self:getComponentNames()
    
    -- Setup components
    self:setDeviceComponent()
    self:setRoomControlsComponent()
    
    -- Set defaults
    if self.components.device then
        self:debugPrint("Setting default input selection to input " .. self.inputs.default)
        self:setRoute(self.inputs.default, 1, "Initialization")
        if self.enableOutput2 then 
            self:setRoute(self.inputs.default, 2, "Initialization") 
        end
    else
        self:debugPrint("WARNING: No device component available - skipping default input selection")
    end
    
    -- Summary
    self:debugPrint("=== Initialization Complete ===")
    self:debugPrint("Active Outputs: " .. (self.enableOutput2 and "Output 1 & Output 2" or "Output 1 only"))
    self:debugPrint("Ready for operation")
end
```

---

## 6. State Management

### 6.1 Organize State in Tables

**Pattern:**
```lua
function MyController.new(roomName, config)
    local self = setmetatable({}, MyController)
    
    -- Immutable configuration
    self.roomName = roomName or "Default"
    self.debugging = (config and config.debugging) or true
    self.clearString = "[Clear]"
    
    -- Component registry
    self.components = { 
        device = nil, 
        roomControls = nil, 
        invalid = {} 
    }
    
    -- Runtime state
    self.state = { 
        power = false,
        lastInput = {}, 
        preFireAlarmInput = {}, 
        fireAlarmActive = false 
    }
    
    -- Timers
    self.timers = { 
        monitor = Timer.New(),
        cooldown = Timer.New()
    }
    
    return self
end
```

---

## 7. Refactoring Checklist

When refactoring or creating a script:

**Structure:**
- [ ] Single-class architecture (not module hierarchy)
- [ ] Utility functions at top (isArr, setProp, bind, bindArray)
- [ ] Clear section markers (Controls, Utilities, Controller, Methods, Events, Init, Factory)
- [ ] Code is traceable by non-senior programmers

**Debug Logging:**
- [ ] debugPrint() method implemented
- [ ] Initialization logged with === phase markers
- [ ] Component discovery logged (what found, how many)
- [ ] Event registration logged (what handlers, how many)
- [ ] All routing/switching includes source context
- [ ] State changes logged (before/after where relevant)
- [ ] Hardware feedback logged
- [ ] Configuration logged at startup

**Code Quality:**
- [ ] Early returns for invalid inputs
- [ ] setProp() used for all control property assignments
- [ ] bind()/bindArray() used for event registration
- [ ] Control arrays normalized once at init
- [ ] Required controls validated
- [ ] Component handlers cleaned up before reassignment
- [ ] No single-letter variables (except loop iterators: i, k, v)
- [ ] 3-letter control prefixes used consistently (btn, txt, ctl, etc.)

**Metrics:**
- [ ] Code reduced 50-70% from original (if refactoring)
- [ ] Debug window shows complete operational flow
- [ ] Every user interaction visible in debug output
- [ ] Script is <500 lines (target for most controllers)

---

## 8. Common Refactoring Wins

### 8.1 Before/After Examples

**Event Registration:**
```lua
-- BEFORE (verbose, repetitive)
controls.btn1.EventHandler = function() self:handleBtn(1) end
controls.btn2.EventHandler = function() self:handleBtn(2) end
controls.btn3.EventHandler = function() self:handleBtn(3) end
controls.btn4.EventHandler = function() self:handleBtn(4) end
controls.btn5.EventHandler = function() self:handleBtn(5) end

-- AFTER (lean, scalable)
bindArray(controls.buttons, function(i) self:handleBtn(i) end)
self:debugPrint("Registered " .. #controls.buttons .. " button handlers")
```

**State Changes:**
```lua
-- BEFORE (no context)
outputControl.Value = input
print("Route changed")

-- AFTER (with context)
function setRoute(input, output, source)
    if outputControl.Value == input then 
        self:debugPrint("Output " .. output .. " already set to input " .. input)
        return false 
    end
    outputControl.Value = input
    self.state.lastInput[output] = input
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    self:debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    return true
end
```

**Component Setup:**
```lua
-- BEFORE (no validation feedback)
self.device = Component.New(controls.devDevice.String)

-- AFTER (with validation and logging)
function setDeviceComponent()
    self.components.device = self:setComponent(controls.devDevice, "Device")
    if not self.components.device then return end
    self:setupDeviceHandlers()
end
-- Logs: "Set Device component: devNV32_Main" or "ERROR: Device component 'xyz' is invalid"
```

---

## 9. Debug Output Examples

### 9.1 Typical Initialization Output

```
[Room 101] === Initialization Started ===
[Room 101] Configuration: debugging=true, enableOutput2=false, uciEnabled=true
[Room 101] Discovered NV32 Router: devNV32_Main
[Room 101] Discovered Room Controls: compRoomControls_Main
[Room 101] Component discovery complete - 1 NV32 routers, 1 Room Controls found
[Room 101] Set NV32-H component: devNV32_Main
[Room 101] Registered feedback handler for Output 1
[Room 101] Set Room Controls component: compRoomControls_Main
[Room 101] Registered System Power handler
[Room 101] Registered Fire Alarm handler
[Room 101] Registered event handler for devNV32
[Room 101] Registered event handler for compRoomControls
[Room 101] Registered 5 button handlers for Output 1
[Room 101] Direct monitoring set up for UCI button layer 7
[Room 101] Direct monitoring set up for UCI button layer 8
[Room 101] Direct monitoring set up for UCI button layer 9
[Room 101] UCI direct button monitoring configured for 3 buttons
[Room 101] Setting default input selection to input 7
[Room 101] Routed Output 1 → Input 7 (Source: Initialization)
[Room 101] === Initialization Complete ===
[Room 101] Active Outputs: Output 1 only
[Room 101] Ready for operation
```

### 9.2 Typical Runtime Output

```
[Room 101] Output 1 Button 2 pressed
[Room 101] Routed Output 1 → Input 8 (Source: User Button)
[Room 101] Device Feedback: Output 1 → Input 8

[Room 101] UCI Layer changed: 7 → 8
[Room 101] UCI Layer 8 triggers input switch to 7
[Room 101] Routed Output 1 → Input 7 (Source: UCI Layer 8)

[Room 101] System Power ON - switching to input 7
[Room 101] Routed Output 1 → Input 7 (Source: System Power)

[Room 101] Fire Alarm ACTIVATED - storing current inputs and switching to alarm input
[Room 101] Routed Output 1 → Input 2 (Source: Fire Alarm)
[Room 101] Fire Alarm CLEARED - restoring previous inputs
[Room 101] Routed Output 1 → Input 7 (Source: Fire Alarm Clear)
```

---

## Summary

**Lean Code:**
- Single-class with utilities
- Early returns, no deep nesting
- Compact but readable
- 50-70% reduction from verbose code

**Rich Debug:**
- Log all interactions with source context
- Phase markers for init/cleanup
- Count handlers/components/discoveries
- Show before/after for state changes
- **"An empty debug window is a useless one"**

**Result:**
Scripts that are easy to understand, quick to troubleshoot, and maintainable by the entire team.
