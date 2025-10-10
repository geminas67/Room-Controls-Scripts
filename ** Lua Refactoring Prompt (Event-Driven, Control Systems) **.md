## **Objective:**

Refactor the following Lua code to make it faster and more responsive, with a focus on event-driven operations like button presses and component state changes.

**Guidelines for Refactoring:**

1. **Use Class-Based Architecture (OOP):**
    - Implement all Lua scripts using class-based architecture Lua metatables.
    - Use metatable-based construction (as in 'UCIController') to support multiple instances and inheritance.
    - Prefer object-oriented approaches over closure-based pattens.
    - Structure every script as a class with well-defined initialization, clear methods, and property/state management.
    - Apply consistent naming: use `ClassName` for classes, `instanceName` for instances.

2. **Flatten Control Flow and Use Early Returns**
	-	Use guard clauses at the start of functions to check for invalid/error conditions and return early.
	-	Write the main/happy path unindented after all early error cases.
	-	Avoid unnecessary `else`/`elseif` branches after a `return`.

3. **Streamline Event Handlers:**
    - Keep event handlers as direct and minimal as possible.
    - Update UI and system state immediately within the handler.
    - Avoid unnecessary indirection or excessive nesting in callbacks.
    - Use helpers functions to reduce 

4. **Reduce Redundant Component Access:**
    - Access component properties directly where safe (e.g., `component.property = value`).
    - Use wrappers (like `safeComponentAccess`) only when needed for error-prone operations.
    - Minimize repeated property or function calls in routine operations.

5. **Batch and Parallelize Initialization:**
    - Group initialization steps to reduce the number of separate dealys or timers.
    - Use a single timer for grouped delayed tasks whenever possible.

6. **Eliminate Redundant State and UI Updates:**
    - Consolidate state and UI updates so each change happens only once per event.
    - Do not update the same property or state variable multiple times unnecessarily.

7. **Simplify and Modularize Logic:**
    - Break down complex logic into clear, single-responsibility functions.
    - Eliminate code duplication.
    - Keep the call stack shallow—avoid deeply nested chains of function calls.

8. **Direct Routing and State Management:**
    - Perform routing assignments and UI feedback updates directly in event handlers.
    - Avoid indirection, especially for critical or time-sensitive actions.

9. **Profile and Target Real Bottlenecks:**
    - Prioritize optimization of code paths triggered most frequently (e.g., button presses, switching).
    - Ignore micro-optimizations in non-critical or rarely called code.

10. **Maintain Readability and Maintainability:**
    - Keep code modular and well-structured.
    - Use clear comments, spacing, and consistent naming conventions throughout.
    - Favor helper functions to aid ongoing readability and maintenance.

11. **Prefer Combo Boxes for Component Selection:**
    - Use Combo Boxes (dropdowns) instead of multiple buttons or manual input when users must select from several options.
    - Ensure Combo Box selections trigger immediate, efficient updates to the UI and system state.
    - Only use Combo Boxes where it improves clarity, reduces UI clutter, or streamlines selection logic.

12. **Dynamically Pull Component Types:**
    - Use `Component.GetComponents()` to dynamically discover and enumerate available system components (in one loop).
    - Populate Combo Boxes or selection lists with dynamic results to keep UI current with actual system state.
    - Never hard-code component types—dynamic queries ensure flexibility and maintainability.

13. **Use State Management Utilities for Dynamic Component Arrays:**
    - Always create and include a utility function directly within each script to handle state management before populating or batch operating on dynamic arrays/tables that reference components (audio, video, room topology, etc.).
    - Follow the functional pattern found in successful modular scripts such as SystemAutomationController, which implements its own utility to safely reset and manage component arrays within the script itself—do not require importing shared utilities.
    - Ensure this local utility function provides proper initialization and cleanup of component references, preventing stale data and maintaining system reliability.
    - Call this function at the start of any operation that modifies component collections to guarantee a consistent state.

14. **Implement Comprehensive Control Validation:**
    - Create a `validateControls()` function that checks for required controls before initialization.
    - Return early from constructor if validation fails to prevent runtime errors.
    - Use descriptive error messages listing specific missing controls.
    - Include validation as the first step in any constructor to ensure robust initialization.

15. **Normalize Control Arrays at Initialization:**
    - Create a `normalizeControlArrays()` function to standardize control structures upfront.
    - Convert single controls to arrays where array processing is expected (e.g., device collections).
    - Call normalization early in initialization to optimize subsequent array operations.
    - Reduce repetitive type checking by ensuring consistent data structures from the start.

16. **Use Efficient Utility Functions with Standard Patterns:**
    - Implement core utilities: `isArr()`, `getControlArray()`, `setProp()`, `bind()`, `bindArray()`, `forEach()`.
    - Ensure `setProp()` includes guard logic to prevent redundant property assignments.
    - Design utilities to work optimally with pre-normalized data structures.
    - Keep utility functions consistent across all scripts for maintainability.

17. **Implement Batch Event Registration:**
    - Use handler maps instead of individual event binding calls for devices with multiple controls.
    - Employ single loops with key-value pairs for registering similar event handlers.
    - Pass object references directly to avoid double lookups in event registration.
    - Group related event handlers logically within maps for better organization.

18. **Follow Modular Architecture with BaseModule Pattern:**
    - Create a `BaseModule` class that provides common functionality (debug logging, controller reference).
    - Extend BaseModule for domain-specific modules (ComponentModule, DeviceModule, etc.).
    - Initialize modules within the main controller using dependency injection patterns.
    - Keep each module focused on a single responsibility (component management, device control, etc.).

19. **Implement Optimized Property Access Patterns:**
    - Avoid redundant property assignments by checking current values before setting.
    - Pass references directly between functions to eliminate repeated lookups.
    - Cache frequently accessed objects at appropriate scopes to reduce traversal overhead.
    - Use local variables for objects referenced multiple times within the same function.

20. **Use Factory Functions with Enhanced Error Handling:**
    - Implement factory functions that wrap constructor calls with comprehensive error handling.
    - Provide clear success/failure messaging with specific error context.
    - Export both the class and instance globally for external access and multiple instance support.
    - Include graceful degradation when optional components are unavailable.
21. **Implement Generic Component Update Patterns:**
    - Create generic update functions that consolidate repetitive component assignment logic.
    - Use parameterized functions with component type, name array, component array, and debug label parameters.
    - Maintain backward compatibility by keeping specific wrapper functions that call the generic implementation.
    - Example: Replace multiple updateRoomComponent(), updateAudioRouter(), updateBTNRoomSelector() functions with a single updateComponent() function.
22. **Centralize Error and Status Reporting:**
    - Implement centralized utilities for consistent operation result reporting across all modules.
    - Create printOperationResult(operationType, successCount, totalCount, errorList) to eliminate repetitive summary print patterns.
    - Use handleBatchResult(resultSuccess, operationType, index, itemName) for standardized batch operation error handling.
    - Ensure all modules use the controller's centralized utilities for consistent output formatting.
23. **Eliminate Repetitive Debug and Error Print Patterns:**
    - Identify and consolidate repetitive error/debug print blocks that follow similar patterns.
    - Replace manual error counting and printing with centralized utilities.
    - Use consistent error message formatting across all operations (routing, synchronization, state updates).
    - Reduce boilerplate code by extracting common print patterns into reusable functions.
24. **Apply DRY Principles to Event Handler Registration:**
    - Use configuration-driven handler maps to eliminate repetitive event binding code.
    - Implement parameterized handler factories for similar event types that only differ in component references.
    - Group related event handlers logically within maps for better organization and maintenance.
    - Prefer handler factories over inline function definitions when multiple handlers perform variations of the same task.
25. **Implement Consistent Module Integration Patterns:**
    - Ensure all modules can access and use the controller's centralized utilities.
    - Design modules to delegate common operations (error reporting, status updates) to the main controller.
    - Use dependency injection to provide modules with access to centralized utilities.
    - Maintain module independence while leveraging shared functionality.
    - These additions would help future refactoring efforts by:
    - Guiding developers to identify and consolidate repetitive patterns early
    - Providing specific examples of how to implement generic update functions
    - Establishing standards for error reporting and debug output consistency
    - Encouraging the creation of reusable utilities rather than copy-paste code
    - Ensuring all modules benefit from centralized improvements

---

## **Advanced DRY Patterns for Event-Driven Control Systems**

These patterns are demonstrated in UCIController and should be applied to all refactored scripts:

### **26. Route State Changes Through Central Navigation Handler**

**✅ BEST PRACTICE: Eliminate Duplicated State Logic**
- Route ALL layer/navigation state changes through a single centralized handler (e.g., `btnNavEventHandler`)
- This ensures `varActiveLayer`, video switching, button interlocking, and sublayer updates are ALWAYS synchronized
- Prevents "stuck buttons" and state desynchronization bugs

**Example Pattern:**
```lua
-- ✅ CORRECT: Pin handlers route to central navigation on positive edge
[controls.pinLEDUSBLaptop] = function(ctl)
    if ctl.Boolean then 
        -- Only positive edge triggers full navigation state change
        self:btnNavEventHandler(self.kLayerLaptop)
    else
        -- Negative edge only updates sublayers, no navigation change
        self.sublayerModule:updateConferenceState()
    end
end

-- ❌ WRONG: Direct layer/state manipulation bypasses central logic
[controls.pinLEDUSBLaptop] = function(ctl)
    if ctl.Boolean then
        self.varActiveLayer = self.kLayerLaptop  -- ❌ Duplicates state logic
        self.layerModule:showLayer()              -- ❌ Misses video switching
        self:interlock()                          -- ❌ Repetitive pattern
    end
end
```

**Key Benefits:**
- Single point of change for all navigation logic
- Automatic synchronization of related state (buttons, layers, video)
- Positive edge = full navigation; Negative edge = sublayer updates only
- Eliminates race conditions and stuck UI states

### **27. Enhanced setProp Utility with Redundancy Guard**

**✅ BEST PRACTICE: Prevent Redundant Property Assignments**
- Always use `setProp()` wrapper that checks current value before assignment
- Reduces unnecessary UI updates and eliminates race conditions
- Critical for high-frequency event handlers and pin state changes

**Implementation:**
```lua
-- ✅ CORRECT: Guard logic prevents redundant assignments
local function setProp(ctrl, prop, val)
    if not ctrl or not prop then return false end
    if ctrl[prop] == val then return false end  -- 🎯 Critical guard
    ctrl[prop] = val
    return true
end

-- Usage in interlocking:
for i, btn in ipairs(navButtons) do
    if btn then
        local shouldBeActive = (i == activeButtonIndex)
        setProp(btn, "Boolean", shouldBeActive)  -- Only updates if changed
    end
end

-- ❌ WRONG: Direct assignment causes redundant UI updates
btn.Boolean = shouldBeActive  -- Updates even if already same value
```

### **28. Batch Registration with Centralized Handler Maps**

**✅ BEST PRACTICE: Eliminate Repetitive Event Binding Code**
- Use object-reference-based handler maps for all event registration
- Single loop to bind all handlers of same type
- Provides single point of update when extending controls

**Example Pattern:**
```lua
function Controller:registerEventHandlers()
    -- 🎯 Centralized handler map with direct object references
    local systemHandlerMap = {
        [controls.btnStartSystem] = function() self:startSystem() end,
        [controls.btnNavShutdown] = function() 
            self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
        end,
        [controls.btnShutdownCancel] = function() 
            self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, false, "fade")
        end,
        [controls.btnShutdownConfirm] = function() self:shutdownSystem() end
    }
    
    -- 🎯 Batch register all handlers in single loop
    for ctrl, handler in pairs(systemHandlerMap) do
        if ctrl then bind(ctrl, handler) end
    end
end

-- ❌ WRONG: Repetitive individual binding
if controls.btnStartSystem then
    controls.btnStartSystem.EventHandler = function() self:startSystem() end
end
if controls.btnNavShutdown then
    controls.btnNavShutdown.EventHandler = function() 
        self.layerModule:updateLayerVisibility({"D01-ShutdownConfirm"}, true, "fade")
    end
end
-- ... repeated for every control
```

### **29. Paired Controls Utility for Toggle Logic**

**✅ BEST PRACTICE: DRY Toggle Logic for Open/Close, On/Off Pairs**
- Use `bindPairedControls()` utility for all paired toggle controls
- Automatically ensures mutual exclusivity and state synchronization
- Reduces boilerplate code for help buttons, popups, modal dialogs

**Implementation:**
```lua
-- ✅ Utility function for paired controls
local function bindPairedControls(openCtrl, closeCtrl, updateHandler)
    if openCtrl and updateHandler then
        bind(openCtrl, function()
            if closeCtrl then setProp(closeCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
    if closeCtrl and updateHandler then
        bind(closeCtrl, function()
            if openCtrl then setProp(openCtrl, "Boolean", false) end
            updateHandler()
        end)
    end
end

-- ✅ CORRECT: Batch registration of paired controls
local helpControlPairs = {
    {open = controls.btnOpenHelpLaptop, close = controls.btnCloseHelpLaptop, 
     handler = function() self.sublayerModule:updateLaptopHelpState() end},
    {open = controls.btnOpenHelpPC, close = controls.btnCloseHelpPC, 
     handler = function() self.sublayerModule:updatePCHelpState() end},
}
for _, pair in ipairs(helpControlPairs) do
    bindPairedControls(pair.open, pair.close, pair.handler)
end

-- ❌ WRONG: Repetitive individual paired logic
if controls.btnOpenHelpLaptop then
    controls.btnOpenHelpLaptop.EventHandler = function()
        if controls.btnCloseHelpLaptop then 
            controls.btnCloseHelpLaptop.Boolean = false 
        end
        self.sublayerModule:updateLaptopHelpState()
    end
end
if controls.btnCloseHelpLaptop then
    controls.btnCloseHelpLaptop.EventHandler = function()
        if controls.btnOpenHelpLaptop then 
            controls.btnOpenHelpLaptop.Boolean = false 
        end
        self.sublayerModule:updateLaptopHelpState()
    end
end
-- ... repeated for every pair
```

### **30. Normalized Control Arrays at Initialization**

**✅ BEST PRACTICE: Convert All Controls to Arrays for Consistent Processing**
- Create `normalizeControlArrays()` function at initialization
- Cache normalized arrays for use throughout script lifecycle
- Enables batch operations with `forEach()` and `bindArray()` utilities

**Example Pattern:**
```lua
-- ✅ CORRECT: Early normalization
local function normalizeControlArrays()
    local controlsToNormalize = {
        navButtons = {},
        routingButtons = {},
        pinInputs = {}
    }
    
    -- Build arrays from individual controls
    for i = 1, 12 do
        local btn = controls["btnNav" .. string.format("%02d", i)]
        if btn then controlsToNormalize.navButtons[i] = btn end
    end
    
    return controlsToNormalize
end

-- Cache at controller initialization
function Controller.new()
    local self = setmetatable({}, Controller)
    self.normalizedControls = normalizeControlArrays()  -- 🎯 Cache early
    -- ... rest of initialization
end

-- Use throughout with forEach utility
forEach(self.normalizedControls.navButtons, function(i, btn)
    bind(btn, function() self:btnNavEventHandler(i) end)
end)

-- ❌ WRONG: Repeated manual array building
local navButtons = {}
for i = 1, 12 do
    navButtons[i] = controls["btnNav" .. string.format("%02d", i)]
end
-- ... same logic repeated in multiple functions
```

### **31. Guard Clauses for Positive/Negative Edge Handling**

**✅ BEST PRACTICE: Minimize Redundant State Calls with Edge Detection**
- Use positive edge (Boolean = true) for full state changes
- Use negative edge (Boolean = false) for cleanup/sublayer updates only
- Prevents infinite sync loops and redundant navigation calls

**Example Pattern:**
```lua
-- ✅ CORRECT: Differentiate positive vs negative edge behavior
[controls.pinLEDOffHookLaptop] = function(ctl)
    if ctl.Boolean then 
        -- Positive edge: Full navigation state change
        ensureSystemIsOn()
        self:btnNavEventHandler(self.kLayerLaptop)
    end
    -- Negative edge: No action needed, call state will be handled by pinCallActive
end

[controls.pinLEDUSBPC] = function(ctl)
    if ctl.Boolean then 
        -- Positive edge: Full navigation
        self:btnNavEventHandler(self.kLayerPC)
    else
        -- Negative edge: Only update sublayer (conference controls hidden)
        self.sublayerModule:updateConferenceState()
    end
end

-- ❌ WRONG: No edge differentiation causes redundant calls
[controls.pinLEDUSBPC] = function(ctl)
    -- Triggers on both edges, causing double navigation calls
    self:btnNavEventHandler(self.kLayerPC)
    self.sublayerModule:updateConferenceState()
end
```

### **32. Layer Configuration Tables for Batch Updates**

**✅ BEST PRACTICE: Data-Driven Layer Management**
- Use configuration tables to define layer behaviors declaratively
- Enables adding new layers without changing control flow logic
- Consolidates show/hide/function calls into single data structure

**Example Pattern:**
```lua
-- ✅ CORRECT: Configuration-driven approach
local layerConfigs = {
    [self.kLayerLaptop] = {
        showLayers = {"L05-Laptop"},
        callLayerFunctions = {
            function() self.sublayerModule:updateHDMI01State() end,
            function() self.sublayerModule:updateConferenceState() end,
            function() self.sublayerModule:updatePresetSavedState() end,
            function() self.sublayerModule:updateACPRBypassState() end,
            function() self.sublayerModule:updateLaptopHelpState() end,
            function() self.sublayerModule:updateCallActiveState() end
        }
    },
    [self.kLayerPC] = {
        showLayers = {"P05-PC"},
        callLayerFunctions = {
            function() self.sublayerModule:updateHDMI02State() end,
            function() self.sublayerModule:updateConferenceState() end,
            function() self.sublayerModule:updateCallActiveState() end
        }
    }
}

-- Single generic processing loop
local config = layerConfigs[self.varActiveLayer]
if config then
    for _, layer in ipairs(config.showLayers or {}) do
        self:updateLayerVisibility({layer}, true, "fade")
    end
    for _, func in ipairs(config.callLayerFunctions or {}) do
        func()
    end
end

-- ❌ WRONG: Repetitive if/elseif blocks
if self.varActiveLayer == self.kLayerLaptop then
    self:updateLayerVisibility({"L05-Laptop"}, true, "fade")
    self.sublayerModule:updateHDMI01State()
    self.sublayerModule:updateConferenceState()
    -- ... more calls
elseif self.varActiveLayer == self.kLayerPC then
    self:updateLayerVisibility({"P05-PC"}, true, "fade")
    self.sublayerModule:updateHDMI02State()
    self.sublayerModule:updateConferenceState()
    -- ... more calls
end
-- ... repeated for every layer
```

---

## **Summary: DRY Architecture Checklist**

When refactoring or creating new Lua scripts, ensure:

✅ **Centralized State Management**
- [ ] All navigation/layer changes route through single handler function
- [ ] State variables (`varActiveLayer`, etc.) updated in ONE place only
- [ ] Related updates (video, buttons, layers) synchronized automatically

✅ **Batch Operations**
- [ ] Control arrays normalized at initialization
- [ ] Event handlers registered via centralized maps
- [ ] Paired controls use `bindPairedControls()` utility
- [ ] Similar operations grouped into single loops

✅ **Guarded Assignment**
- [ ] `setProp()` used for all property updates
- [ ] Current value checked before assignment
- [ ] Positive/negative edge differentiation for pin handlers

✅ **Configuration-Driven Logic**
- [ ] Layer behaviors defined in configuration tables
- [ ] Handler maps used instead of repetitive if/else chains
- [ ] Generic processing loops replace case-by-case logic

✅ **Single Responsibility**
- [ ] Each module handles ONE domain (layers, routing, video, etc.)
- [ ] Modules delegate to controller for shared utilities
- [ ] Debug logging centralized via BaseModule pattern

By following these patterns, the codebase remains **highly maintainable**, **DRY throughout**, and **easy to extend** with new features.