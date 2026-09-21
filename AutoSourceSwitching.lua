--[[
  Auto Source Switching Helper - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 1.1 | Date: 2026-02-25
  Firmware Req: 10.1.1

  Priority-based auto source: reads priority pins from UCI component,
  triggers RoomControls btnSystemOn and btnNav on UCI component (NV32 uciNavRoute keys).
  Call Sync used for call-active gating.
  Configure component names in Config section to match design.
]]

-------------------[ Config ]-------------------
local config = {
    debug = true,
    compRoomControls = nil,  -- e.g. "compRoomControls" or set via Uci.Variables
    compCallSync     = nil,  -- e.g. "compCallSync" (control: pinCallActive or equivalent)
    compUCI          = nil,  -- UCI component with priority pins + btnNav07/08/09
}

-------------------[ State ]-------------------
local components = {
    roomControls = nil,
    callSync     = nil,
    uciComp      = nil,
}

-- Priority = array order (first match wins). priority >= 100 bypasses call-active block.
-- btnNav keys match NV32RouterController uciNavRoute.
local sourcePriority = {
    { name = "OffHook Laptop", btnNav = "btnNav08", priority = 200, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDOffHookLaptop"]
        return pin and pin.Boolean
    end },
    { name = "OffHook PC", btnNav = "btnNav07", priority = 200, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDOffHookPC"]
        return pin and pin.Boolean
    end },
    { name = "HDMI03", btnNav = "btnNav09", priority = 30, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI03Active"]
        return pin and pin.Boolean
    end },
    { name = "HDMI02", btnNav = "btnNav07", priority = 20, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI02Active"]
        return pin and pin.Boolean
    end },
    { name = "HDMI01", btnNav = "btnNav08", priority = 10, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI01Active"]
        return pin and pin.Boolean
    end },
}

-------------------[ Utilities ]-------------------
local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    return pcall(function() ctrl.EventHandler = handler end)
end

local function debugPrint(str)
    if config.debug then print("[AutoSource] " .. str) end
end

-------------------[ Functions ]-------------------
local function checkPrioritySource()
    for _, source in ipairs(sourcePriority) do
        if source.checkFunc() then
            return source
        end
    end
    return nil
end

local function isCallActive()
    if components.callSync and components.callSync["pinCallActive"] then
        return components.callSync["pinCallActive"].Boolean
    end
    return false
end

local function isRoomOn()
    if not components.roomControls or not components.roomControls["ledSystemPower"] then return false end
    return components.roomControls["ledSystemPower"].Boolean
end

local function triggerNav(btnName)
    if not components.uciComp then return false end
    local btn = components.uciComp[btnName]
    if not btn then debugPrint(btnName .. " not found"); return false end
    local ok, err = pcall(function() btn:Trigger() end)
    if ok then debugPrint("Triggered " .. btnName) else debugPrint("Nav error: " .. tostring(err)) end
    return ok
end

local function handlePriorityChange()
    local active = checkPrioritySource()
    if not active then return end
    debugPrint("Priority: " .. active.name .. " (Source: Pin Event)")
    local callActive = isCallActive()
    if active.priority >= 100 or not callActive then
        if not isRoomOn() then
            if components.roomControls and components.roomControls["btnSystemOn"] then
                components.roomControls["btnSystemOn"].Boolean = true
                debugPrint("Room → btnSystemOn")
            else
                debugPrint("RoomControls or btnSystemOn not available")
            end
        end
        triggerNav(active.btnNav)
    else
        debugPrint("Source switch BLOCKED: call in progress (priority " .. active.priority .. ")")
    end
end

local function initRoomControls()
    local compName = config.compRoomControls
    if Uci and Uci.Variables and Uci.Variables.compRoomControls and Uci.Variables.compRoomControls.String and Uci.Variables.compRoomControls.String ~= "" then
        compName = Uci.Variables.compRoomControls.String
    end
    if not compName then
        debugPrint("Room Controls: no component name configured")
        return false
    end
    local ok, comp = pcall(function() return Component.New(compName) end)
    if not ok or not comp then
        debugPrint("Room Controls not found: " .. tostring(compName))
        return false
    end
    components.roomControls = comp
    debugPrint("Room Controls: " .. compName)
    return true
end

local function initCallSync()
    if not config.compCallSync then return false end
    local ok, comp = pcall(function() return Component.New(config.compCallSync) end)
    if not ok or not comp then
        debugPrint("Call Sync not found: " .. tostring(config.compCallSync))
        return false
    end
    components.callSync = comp
    debugPrint("Call Sync: " .. config.compCallSync)
    return true
end

local function initUciComp()
    if not config.compUCI then
        debugPrint("UCI component name not configured - priority pins will not be monitored")
        return false
    end
    local ok, comp = pcall(function() return Component.New(config.compUCI) end)
    if not ok or not comp then
        debugPrint("UCI component not found: " .. tostring(config.compUCI))
        return false
    end
    components.uciComp = comp
    debugPrint("UCI component: " .. config.compUCI)
    return true
end

local function registerEvents()
    if not components.uciComp then return end
    local priorityPins = {
        "pinLEDOffHookLaptop", "pinLEDOffHookPC",
        "pinLEDHDMI01Active", "pinLEDHDMI02Active", "pinLEDHDMI03Active",
    }
    local count = 0
    for _, pinName in ipairs(priorityPins) do
        local pin = components.uciComp[pinName]
        if pin and bind(pin, function() handlePriorityChange() end) then count = count + 1 end
    end
    debugPrint("Registered " .. count .. " priority pin handlers")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== AutoSourceSwitching init ===")
    initRoomControls()
    initCallSync()
    initUciComp()
    registerEvents()
    debugPrint("=== AutoSourceSwitching ready ===")
end

-------------------[ Start ]-------------------
local ok, err = pcall(init)
if not ok then
    print("✗ AutoSourceSwitching error: " .. tostring(err))
end
