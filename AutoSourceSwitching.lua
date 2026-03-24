--[[
  Auto Source Switching Helper - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS
  Version: 1.0 | Date: 2026-02-25
  Firmware Req: 10.1.1

  Priority-based auto source: reads priority pins from UCI component, 
  triggers RoomControls btnSystemOn and sets AV switcher. 
  Call Sync used for call-active gating.
  Configure component names in Config section to match design.
]]

-------------------[ Configuration ]-------------------
local SwitcherTypes = {
    NV32 = {
        componentType   = "streamer_hdmi_switcher",
        switcherNames   = { "devNV32", "compNV32" },
        routingMethod   = "hdmi.out.1.select.index",
        defaultMapping  = { [7] = 7, [8] = 8, [9] = 9 },
    },
    ExtronDXP = {
        componentType   = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
        switcherNames   = { "devExtronDXP", "compExtronDXP" },
        routingMethod   = "output.1",
        defaultMapping  = { [7] = 2, [8] = 4, [9] = 1 },
    },
    AVProEdge = {
        componentType   = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
        switcherNames   = { "devAVProEdge", "compAVProEdge" },
        routingMethod   = "trigger",
        defaultMapping  = { [7] = "Input 3", [8] = "Input 4", [9] = "Input 1", [10] = "Input 2" },
    },
}

-------------------[ Config ]-------------------
local config = {
    debug = true,
    compRoomControls = nil,  -- e.g. "compRoomControls" or set via Uci.Variables
    compCallSync     = nil,  -- e.g. "compCallSync" (control: pinCallActive or equivalent)
    compUCI          = nil,  -- control processor running UCI script (has priority pins)
}

-------------------[ State ]-------------------
local components = {
    roomControls        = nil,
    callSync            = nil,
    uciComp             = nil,
    videoSwitcher       = nil,
    switcherType        = nil,
    uciToInputMapping   = nil,
}

-- Priority = array order (first match wins). priority >= 100 bypasses call-active block.
local sourcePriority = {
    { name = "OffHook Laptop", layer = 8, priority = 200, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDOffHookLaptop"]
        return pin and pin.Boolean
    end },
    { name = "OffHook PC", layer = 7, priority = 200, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDOffHookPC"]
        return pin and pin.Boolean
    end },
    { name = "HDMI03", layer = 9, priority = 30, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI03Active"]
        return pin and pin.Boolean
    end },
    { name = "HDMI02", layer = 7, priority = 20, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI02Active"]
        return pin and pin.Boolean
    end },
    { name = "HDMI01", layer = 8, priority = 10, checkFunc = function()
        local pin = components.uciComp and components.uciComp["pinLEDHDMI01Active"]
        return pin and pin.Boolean
    end },
}

-------------------[ Utilities ]-------------------
local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if not ctrl or not handler then return false end
    return pcall(function() ctrl.EventHandler = handler end)
end

local function debugPrint(str)
    if config.debug then print("[AutoSource] " .. str) end
end

-------------------[ Functions ]-------------------
local function findHighestPriorityActiveSource()
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
    if components.uciComp and components.uciComp["pinCallActive"] then
        return components.uciComp["pinCallActive"].Boolean
    end
    return false
end

local function isRoomOn()
    if not components.roomControls or not components.roomControls["ledSystemPower"] then return false end
    return components.roomControls["ledSystemPower"].Boolean
end

local function switchToInput(layer)
    if not components.videoSwitcher or not components.switcherType then return false end
    local inputVal = components.uciToInputMapping[layer]
    if inputVal == nil then return false end
    local cfg = SwitcherTypes[components.switcherType]
    if not cfg then return false end
    local ok, err = pcall(function()
        if components.switcherType == "NV32" then
            setProp(components.videoSwitcher[cfg.routingMethod], "Value", inputVal)
        else
            setProp(components.videoSwitcher[cfg.routingMethod], "String", tostring(inputVal))
        end
    end)
    if ok then debugPrint("Video → input " .. tostring(inputVal)) else debugPrint("Video switch error: " .. tostring(err)) end
    return ok
end

local function handlePrioritySourceChange()
    local active = findHighestPriorityActiveSource()
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
        switchToInput(active.layer)
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

local function initVideoSwitcher()
    for swType, cfg in pairs(SwitcherTypes) do
        for _, name in ipairs(cfg.switcherNames) do
            local ctrl = Controls[name]
            if ctrl and ctrl.String and ctrl.String ~= "" then
                local ok, comp = pcall(function() return Component.New(ctrl.String) end)
                if ok and comp then
                    components.videoSwitcher = comp
                    components.switcherType = swType
                    components.uciToInputMapping = cfg.defaultMapping
                    debugPrint("Video switcher: " .. swType)
                    return true
                end
            end
        end
    end
    for _, comp in pairs(Component.GetComponents()) do
        for swType, cfg in pairs(SwitcherTypes) do
            if comp.Type == cfg.componentType then
                local ok, compNew = pcall(function() return Component.New(comp.Name) end)
                if ok and compNew then
                    components.videoSwitcher = compNew
                    components.switcherType = swType
                    components.uciToInputMapping = cfg.defaultMapping
                    debugPrint("Video switcher: " .. swType .. " (auto-detect)")
                    return true
                end
            end
        end
    end
    debugPrint("No video switcher found")
    return false
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
        if pin and bind(pin, function() handlePrioritySourceChange() end) then count = count + 1 end
    end
    debugPrint("Registered " .. count .. " priority pin handlers")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== AutoSourceSwitching init ===")
    config.compRoomControls = config.compRoomControls or nil
    config.compCallSync     = config.compCallSync or nil
    config.compUCI          = config.compUCI or nil

    initRoomControls()
    initCallSync()
    initUciComp()
    initVideoSwitcher()
    registerEvents()
    debugPrint("=== AutoSourceSwitching ready ===")
end

-------------------[ Start ]-------------------
local ok, err = pcall(init)
if not ok then
    print("✗ AutoSourceSwitching error: " .. tostring(err))
end
