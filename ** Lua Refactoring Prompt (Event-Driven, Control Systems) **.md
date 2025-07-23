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
    - se clear comments, spacing, and consistent naming conventions throughout.

11. **Prefer Combo Boxes for Component Selection:**
    - Use Combo Boxes (dropdowns) instead of multiple buttons or manual input when users must select from several options.
    - Ensure Combo Box selections trigger immediate, efficient updates to the UI and system state.
    - Only use Combo Boxes where it improves clarity, reduces UI clutter, or streamlines selection logic.

12. **Dynamically Pull Component Types:**
    - Use `Component.GetComponents()` to dynamically discover and enumerate available system components (in one loop).
    - Populate Combo Boxes or selection lists with dynamic results to keep UI current with actual system state.
    - Never hard-code component types—dynamic queries ensure flexibility and maintainability.