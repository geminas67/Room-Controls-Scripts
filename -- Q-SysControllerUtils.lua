-- QSysControllerUtils.lua
-- Shared utility module for Q-SYS controller scripting
-- Provides: safe accessors, component management, logging, batch init, timer utils

local QSysControllerUtils = {}

------------------[ Safe Component Access (convenience methods) ]-------------------
local accessorMap = {
    setComponentBoolean = "set",
    setComponentProperty = "setString",
    setComponentPosition = "setPosition",
    setComponentValue    = "setValue",
    getComponentBoolean  = "get",
    getComponentProperty = "getString",
    getComponentPosition = "getPosition",
    getComponentValue    = "getValue",
    triggerComponent     = "trigger",
}

-- Call to add convenience methods to any table/self
function QSysControllerUtils.injectAccessors(target, customMap)
    local map = customMap or accessorMap
    for name, action in pairs(map) do
        target[name] = function(self, component, control, value)
            return self:safeComponentAccess(component, control, action, value)
        end
    end
end

function QSysControllerUtils:safeComponentAccess(component, control, action, value)
    local ok, result = pcall(function()
        if component and component[control] then
            if action == "set" then
                component[control].Boolean = value; return true
            elseif action == "setPosition" then
                component[control].Position = value; return true
            elseif action == "setString" then
                component[control].String = value; return true
            elseif action == "setValue" then
                component[control].Value = value; return true
            elseif action == "trigger" then
                component[control]:Trigger(); return true
            elseif action == "get" then
                return component[control].Boolean
            elseif action == "getPosition" then
                return component[control].Position
            elseif action == "getString" then
                return component[control].String
            elseif action == "getValue" then
                return component[control].Value
            end
        end
        return false
    end)
    if not ok and self.debugPrint then self:debugPrint("Component access error: "..tostring(result)) end
    return result
end

------------------[ Component Management & Status ]------------------
function QSysControllerUtils:setComponent(ctrl, componentType, clearString)
    if not ctrl or ctrl.String == "" or ctrl.String == (clearString or "[Clear]") then
        ctrl.Color = "white"
        self:setComponentValid(componentType)
        return nil
    end
    if #Component.GetControls(Component.New(ctrl.String)) < 1 then
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        self:setComponentInvalid(componentType)
        return nil
    end
    ctrl.Color = "white"
    self:setComponentValid(componentType)
    return Component.New(ctrl.String)
end

function QSysControllerUtils:setComponentInvalid(componentType)
    self.components.invalid[componentType] = true
    self:checkStatus()
end

function QSysControllerUtils:setComponentValid(componentType)
    self.components.invalid[componentType] = false
    self:checkStatus()
end

function QSysControllerUtils:checkStatus()
    for _, isInvalid in pairs(self.components.invalid) do
        if isInvalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

------------------[ Debug Logging ]------------------
function QSysControllerUtils:debugPrint(str)
    if self.debugging then print("["..(self.roomName or "Controller").." Debug] "..str) end
end

------------------[ Batch Initializer ]------------------
function QSysControllerUtils:runInitializers(initializerArray)
    for i, func in ipairs(initializerArray) do
        local ok, err = pcall(func)
        if not ok and self.debugPrint then self:debugPrint("Initializer "..i.." error: "..tostring(err)) end
    end
end

---------- Timer Utilities ----------
-- runDelayed: performs a delayed call (substitute for Timer.CallAfter with error log)
function QSysControllerUtils:runDelayed(delaySeconds, func)
    if type(func) ~= "function" then
        if self.debugPrint then self:debugPrint("runDelayed: No function passed.") end
        return
    end
    Timer.CallAfter(function()
        local ok, err = pcall(func)
        if not ok and self.debugPrint then self:debugPrint("runDelayed error: " .. tostring(err)) end
    end, delaySeconds)
end

-- (optionally add runRepeating, cancelTimer, etc)

return QSysControllerUtils
