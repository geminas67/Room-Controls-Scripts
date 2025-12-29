## Objective

Refactor Lua control scripts to be faster, more responsive, and easier to maintain by using functional patterns where state is simple and static, and a hybrid OOP/functional approach where state, components, or timers are dynamic.

---

## 1. Choose the Right Architecture

### 1.1 Prefer Functional Modules When Suitable

Use a functional/modular pattern (factory functions with closures) when:

- State is simple, mostly immutable, and event-driven (e.g., navigation, UI layers, static component references).
- Component lifecycles are static (discovered once, rarely change at runtime).

Guidelines:

- Structure scripts as a collection of factory functions: `createXModule(deps) -> module`.
- Manage module-local state via closures, not global/class fields, when the state does not need to be shared dynamically.
- Pass explicit dependencies into factories (controls, config, stores) for testability and reuse.

### 1.2 Use a Hybrid OOP/Functional Approach for Dynamic Systems

Use a hybrid design (OOP shell + functional logic) when:

- Components are created, assigned, or removed at runtime (dynamic arrays, `.Choices` selectors).
- Long-lived mutable state and timers drive behavior (e.g., LED blink timers, fire alarm, power state).

Guidelines:

- Keep OOP at the “edges”: component discovery, lifecycle, timer creation, and integration with Q-SYS components.
- Encapsulate business logic and state transitions as pure/pure-ish functions or small state machines invoked from the OOP shell.
- Use a central state store (table with `get/set/subscribe`) when multiple modules share mutable state.

**Hybrid Balance Guidelines:**

- **OOP for:** stateful modules, timer management, dynamic component lifecycle
- **Functional for:** data transformation utilities, event handler wiring, pure computations

**When to Adjust the Balance:**

**More functional if:**
- No timers mutating state
- Static component references (discovered once)
- Simple, event-driven state changes

**More OOP if:**
- Need complex inheritance hierarchies
- Multiple controller instances with shared behavior
- Need polymorphism for different device types

---

## 2. Core Refactor Principles

### 2.1 Flatten Control Flow and Use Early Returns

- Start functions with guard clauses for invalid inputs, missing components, or disabled features, then return early.
- Write the main path unindented after error/edge cases; avoid `else` chains following a `return`.

### 2.2 Streamline Event Handlers

- Keep handlers small: validate, update state, trigger necessary UI/logic, then exit.
- For navigation, always route through a single central handler (e.g., `btnNavEventHandler`) instead of duplicating layer/state logic in multiple places.

### 2.3 Normalize Controls and Use Utilities

- Normalize controls once at initialization (e.g., `normalizeControlArrays()` for nav buttons, routing buttons, pins).
- Use shared utilities consistently: `isArr`, `getControlArray`, `setProp`, `bind`, `bindArray`, `forEach`, and `bindPairedControls`.
- Ensure `setProp()` guards against redundant assignments to reduce unnecessary UI churn and race conditions.

### 2.4 Batch Operations and Handler Maps

- Use handler maps (`{ [control] = handlerFn }`) and a single loop to register events instead of individual bindings.
- Use configuration tables (e.g., `layerConfigs`) to drive layer show/hide and behavior instead of long `if/elseif` chains.
- For repeated toggle pairs (open/close, on/off), use a generic `bindPairedControls()` helper to keep behavior DRY.

---

## 3. State, Components, and Timers

### 3.1 Centralize and Simplify State

- Separate config/immutable data, runtime state, timer state, and component registries into distinct tables when complexity grows.
- For shared state across modules, use a local state store with `get`/`set` and optional subscribers to observe changes.

### 3.2 Dynamic Component Management (Hybrid Area)

- For scripts that dynamically assign components (via `.Choices`, DivisibleSpace, or discovery), keep a dedicated component registry/module.
- Always implement `cleanupComponentHandlers(oldComponent, ...)` to remove prior event handlers before assigning new components, especially in divisible spaces.

### 3.3 Timers and Event Sources

- Prefer timers that emit events (or call a small handler) rather than directly mutating many parts of the system.
- Keep timer creation/cleanup in the OOP shell or controller module; keep timer-driven logic in small, testable functions.

---

## 4. Control and Component Patterns

### 4.1 Validation and Initialization

- Implement a `validateControls()` function that checks for required controls and logs missing ones; return early from construction if validation fails.
- Normalize control arrays and compute caches (maps, legend arrays, HDMI pin maps) during initialization to simplify later code.

### 4.2 Dynamic Component Discovery and Selection

- Use `Component.GetComponents()` once to categorize available components and populate combo boxes or selection lists where appropriate.
- Prefer Combo Boxes over many buttons when selecting from multiple components or rooms, provided it simplifies UI and logic.

### 4.3 Generic Update and Error Reporting Utilities

- Implement generic component-update helpers (e.g., `updateComponent(type, names, store, label)`) where many similar “set component” functions exist.
- Centralize debug and error reporting utilities (e.g., `printOperationResult`, `handleBatchResult`) and use them across modules rather than re-implementing per domain.

---

## 5. Event-Driven DRY Patterns (Applied Across Architectures)

- Route navigation and layer changes through a single handler to keep `varActiveLayer`, video switching, button interlocks, and sublayers in sync.
- Differentiate positive/negative edges on pins (e.g., USB active vs inactive) so only positive edges trigger full navigation, while negative edges do minimal cleanup.
- Use batch registration (`forEach` + handler maps) and normalized arrays to wire large UIs efficiently and consistently.

---

## 6. Checklist

When refactoring or creating a script:

**Architecture:**

- [ ] Functional modules used where state is simple/static.
- [ ] Hybrid OOP/functional used where components/timers are dynamic.

**State and Lifecycle:**

- [ ] Central state or store for shared mutable data.
- [ ] Clear separation of config, state, timers, and components.

**DRY and Events:**

- [ ] Central navigation/layer handler.
- [ ] Handler maps and normalized arrays for event registration.
- [ ] `setProp()` and edge-aware pin handlers used consistently.

**Components and Timers:**

- [ ] `cleanupComponentHandlers()` used before reassigning components.
- [ ] Timers centralized and cleaned up in module/controller lifecycle.
