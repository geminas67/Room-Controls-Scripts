-- SafeComponentAccessHelpers.lua
-- Injects dynamic convenience methods into your class/table
-- 2025-07-28
-- Firmware Req: 10.0.0
-- Version: 1.0


local SafeComponentAccessHelpers = {}

--- Injects convenience methods into `target` that call its `safeComponentAccess`.
-- @param target The class/table to attach methods to (e.g., YourClass or self)
-- @param customMap (optional) Table; overrides/adds to the default method-to-action map
function SafeComponentAccessHelpers.inject(target, customMap)
    local defaultMap = {
        setComponentBoolean  = "set",
        setComponentProperty = "setString",
        setComponentPosition = "setPosition",
        setComponentValue    = "setValue",
        getComponentBoolean  = "get",
        getComponentProperty = "getString",
        getComponentPosition = "getPosition",
        getComponentValue    = "getValue",
        triggerComponent     = "trigger",
    }
    local methodMap = customMap or defaultMap
    for name, action in pairs(methodMap) do
        target[name] = function(self, component, control, value)
            return self:safeComponentAccess(component, control, action, value)
        end
    end
end

return SafeComponentAccessHelpers
