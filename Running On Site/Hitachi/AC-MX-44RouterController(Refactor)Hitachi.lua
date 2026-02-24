--[[
    AC-MX-44 Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 2.1 | Date: 2025-02-24
    Firmware Req: 10.0.0
    MX44 routing: Output 1 = Inputs 1-4, Output 2 = Inputs 5-8. Room-combined mode syncs Output 2 to Output 1.
]]--

-------------------[ Controls ]-------------------
local controls = {
    compMX44 = Controls.compMX44,
    btnOutput01 = Controls.btnOutput01,
    btnOutput02 = Controls.btnOutput02,
    txtStatus = Controls.txtStatus,
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
    if not ctrl or not handler then return false end
    local ok = pcall(function() ctrl.EventHandler = handler end)
    return ok
end

local function bindArray(ctrls, handler)
    if not ctrls or not handler then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for i, ctrl in ipairs(array) do
        if bind(ctrl, function(ctl)
            local ok, err = pcall(handler, i, ctl)
            if not ok then print("Handler error [index " .. i .. "]: " .. tostring(err)) end
        end) then
            count = count + 1
        end
    end
    return count
end

-------------------[ Config ]-------------------
local const = {
    roomName = "MX44 Router",
    debug = true,
    clearString = "[Clear]",
}

-------------------[ State ]-------------------
local components = {
    mx44Router = nil,
    divisibleSpaceControls = nil,
    invalid = {},
}

local state = {
    roomState = false,  -- true = combined, false = separated
    lastInput = {},
}

local config = {
    numOutputs = 4,
    numInputs = 4,
    mx44Type = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f",
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local required = { controls.compMX44, controls.txtStatus, controls.btnOutput01, controls.btnOutput02 }
    local names = { "compMX44", "txtStatus", "btnOutput01", "btnOutput02" }
    local missing = {}
    for i, ctrl in ipairs(required) do
        if not ctrl then table.insert(missing, names[i]) end
    end
    if #missing > 0 then
        print("ERROR: MX44RouterController - Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

local function normalizeControlArrays()
    for _, key in ipairs({"btnOutput01", "btnOutput02"}) do
        local ctrl = controls[key]
        if ctrl and type(ctrl) ~= "table" then controls[key] = { ctrl } end
    end
end

local function checkStatus()
    for _, invalid in pairs(components.invalid) do
        if invalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function getMX44ControlName(output, input)
    local physicalInput = ((output - 1) * 4) + input
    return string.format("Input %d", physicalInput)
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        components.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    setProp(ctrl, "Color", "white")
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function discoverComponents()
    debugPrint("Discovering components...")
    local mx44Names = {}
    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == config.mx44Type then
            table.insert(mx44Names, comp.Name)
            debugPrint("  Found MX44: " .. comp.Name)
        end
    end
    debugPrint("Discovery complete - " .. #mx44Names .. " MX44 device(s) found")
    return mx44Names
end

local function setupComponents()
    local mx44Names = discoverComponents()
    if #mx44Names > 0 and controls.compMX44 then
        local str = controls.compMX44.String
        if str == "" or str == const.clearString then
            setProp(controls.compMX44, "String", mx44Names[1])
            debugPrint("Auto-populated compMX44: " .. mx44Names[1])
        end
    end
end

local function setRoute(input, output, source)
    source = source or "External"
    local router = components.mx44Router
    if not router then
        debugPrint("No MX44 router available (Source: " .. tostring(source) .. ")")
        return false
    end
    if input < 1 or input > config.numInputs or output < 1 or output > config.numOutputs then
        debugPrint("Invalid route: input=" .. tostring(input) .. ", output=" .. tostring(output))
        return false
    end
    local ctrlName = getMX44ControlName(output, input)
    local ctrl = router[ctrlName]
    if not ctrl then
        debugPrint("Control not found: " .. ctrlName)
        return false
    end
    if ctrl.Boolean then
        return true  -- Already routed
    end
    ctrl:Trigger()
    debugPrint("Output " .. output .. " → Input " .. input .. " (Source: " .. tostring(source) .. ")")
    state.lastInput[output] = input
    return true
end

local function syncOutput02ToOutput01(output01Input)
    if not state.roomState then return false end
    if output01Input < 1 or output01Input > config.numInputs then return false end
    return setRoute(output01Input, 2, "Room Combiner")
end

local function cleanupRouterHandlers()
    local router = components.mx44Router
    if not router then return end
    for output = 1, config.numOutputs do
        for input = 1, config.numInputs do
            local ctrl = router[getMX44ControlName(output, input)]
            if ctrl and ctrl.EventHandler then ctrl.EventHandler = nil end
        end
    end
end

local function setMX44RouterComponent()
    cleanupRouterHandlers()
    components.mx44Router = setComponent(controls.compMX44, "MX44")
    local router = components.mx44Router
    if not router then return end

    local btnOut01 = isArr(controls.btnOutput01) and controls.btnOutput01 or { controls.btnOutput01 }
    local btnOut02 = isArr(controls.btnOutput02) and controls.btnOutput02 or { controls.btnOutput02 }

    for inputIdx = 1, config.numInputs do
        local ctrl = router[getMX44ControlName(1, inputIdx)]
        if ctrl then
            bind(ctrl, function(ctl)
                if ctl.Boolean then
                    for i, btn in ipairs(btnOut01) do setProp(btn, "Boolean", (i == inputIdx)) end
                    debugPrint("Output 1 → Input " .. inputIdx .. " (Source: MX44 feedback)")
                    if state.roomState then syncOutput02ToOutput01(inputIdx) end
                end
            end)
        end
    end

    for inputIdx = 1, config.numInputs do
        local ctrl = router[getMX44ControlName(2, inputIdx)]
        if ctrl then
            bind(ctrl, function(ctl)
                if ctl.Boolean then
                    for i, btn in ipairs(btnOut02) do setProp(btn, "Boolean", (i == inputIdx)) end
                    debugPrint("Output 2 → Input " .. inputIdx .. " (Source: MX44 feedback)")
                end
            end)
        end
    end
end

local function setDivisibleSpaceControlsComponent()
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if not ok or not comp then
        debugPrint("DivisibleSpaceControls not found (feature disabled)")
        components.divisibleSpaceControls = nil
        state.roomState = false
        return
    end
    components.divisibleSpaceControls = comp
    debugPrint("DivisibleSpaceControls connected")

    local btnRoomState = comp["btnRoomState 1"]
    if btnRoomState then
        bind(btnRoomState, function(ctl)
            state.roomState = not ctl.Boolean
            debugPrint("Room state → " .. (state.roomState and "Combined" or "Separated") .. " (Source: Room Combiner)")
            if not ctl.Boolean and components.mx44Router then
                for inputIdx = 1, config.numInputs do
                    local c = components.mx44Router[getMX44ControlName(1, inputIdx)]
                    if c and c.Boolean then
                        syncOutput02ToOutput01(inputIdx)
                        debugPrint("Synced Output 2 to Output 1 (Input " .. inputIdx .. ")")
                        break
                    end
                end
            end
        end)
        state.roomState = not btnRoomState.Boolean
        debugPrint("Initial room state: " .. (state.roomState and "Combined" or "Separated"))
    else
        debugPrint("Warning: btnRoomState 1 not found")
    end
end

local function registerEvents()
    bind(controls.compMX44, setMX44RouterComponent)
    debugPrint("Registered compMX44 handler")

    local outputConfig = {
        { ctrl = controls.btnOutput01, output = 1, name = "Output 1" },
        { ctrl = controls.btnOutput02, output = 2, name = "Output 2" },
    }
    for _, cfg in ipairs(outputConfig) do
        local btns = isArr(cfg.ctrl) and cfg.ctrl or { cfg.ctrl }
        for i, btn in ipairs(btns) do
            bind(btn, function() setRoute(i, cfg.output, cfg.name) end)
        end
        debugPrint("Registered " .. #btns .. " button handlers for " .. cfg.name)
    end
end

local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debug=" .. tostring(const.debug))

    setupComponents()
    setMX44RouterComponent()
    setDivisibleSpaceControlsComponent()

    if components.mx44Router then
        setRoute(1, 1, "Init")
        if state.roomState then
            syncOutput02ToOutput01(1)
        else
            setRoute(1, 2, "Init")
        end
    end

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
ACMX44RouterController = {
    setRoute = setRoute,
    syncOutput02ToOutput01 = syncOutput02ToOutput01,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing MX44 Router Controller...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    registerEvents()
    init()
end)

if ok then
    print("✓ MX44 Router Controller initialized")
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls.txtStatus then
        controls.txtStatus.String = "INIT FAILED"
        controls.txtStatus.Value = 2
    end
end
