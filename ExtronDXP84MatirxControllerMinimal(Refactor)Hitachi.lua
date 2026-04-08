--[[
    Extron DXP84 Router Controller (Refactored, AC-MX pattern)
    Author: Nikolas Smith, Q-SYS
    Version: 1.0 | Date: 2026-03-31
    Firmware Req: 10.0.0

    Two outputs × four inputs: Output 1 = Room A, Output 2 = Room B.
    Room-combined mode syncs Output 2 to Output 1. Uses Extron matrix output.N String controls.
]]--

-------------------[ Controls ]-------------------
local controls = {
    compExtronDXP = Controls.compExtronDXP,
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

local function cleanupComponentHandlers(oldComp, controlNames, debugCb)
    if not oldComp or not controlNames then return 0 end
    local cleaned = 0
    for _, name in ipairs(controlNames) do
        if oldComp[name] and oldComp[name].EventHandler then
            oldComp[name].EventHandler = nil
            cleaned = cleaned + 1
        end
    end
    if debugCb and cleaned > 0 then debugCb("Cleaned up " .. cleaned .. " handler(s) from old component") end
    return cleaned
end

-------------------[ Config ]-------------------
local const = {
    debug = true,
    clearString = "[Clear]",
}

local roomName = (function()
    local ok, name = pcall(function()
        local rn = Controls.roomName
        return (rn and rn.String ~= "" and rn.String) or nil
    end)
    return (ok and name and "[" .. name .. "]") or "[Extron DXP84]"
end)()

local config = {
    numOutputs = 2,
    numInputs = 4,
    extronMatrixType = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
}

local extronOutputControls = { "output.1", "output.2" }

-------------------[ State ]-------------------
local components = {
    extronMatrix = nil,
    divisibleSpaceControls = nil,
    invalid = {},
}

local state = {
    roomState = false,  -- true = combined, false = separated
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print(roomName .. " " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local required = { controls.compExtronDXP, controls.txtStatus, controls.btnOutput01, controls.btnOutput02 }
    local names = { "compExtronDXP", "txtStatus", "btnOutput01", "btnOutput02" }
    local missing = {}
    for i, ctrl in ipairs(required) do
        if not ctrl then table.insert(missing, names[i]) end
    end
    if #missing > 0 then
        print("ERROR: ExtronDXP84RouterController - Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

local function normalizeControlArrays()
    for _, key in ipairs({ "btnOutput01", "btnOutput02" }) do
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

local function setComponent(ctrl, componentType, expectedType)
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
    if expectedType and comp.Type ~= expectedType then
        setProp(ctrl, "String", "[Wrong Component Type]")
        setProp(ctrl, "Color", "pink")
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: " .. componentType .. " wrong type. Expected " .. tostring(expectedType) .. ", got " .. tostring(comp.Type))
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
    local names = {}
    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == config.extronMatrixType then
            table.insert(names, comp.Name)
            debugPrint("  Found Extron DXP: " .. comp.Name)
        end
    end
    debugPrint("Discovery complete - " .. #names .. " Extron DXP device(s) found")
    return names
end

local function setupComponents()
    local extronNames = discoverComponents()
    if #extronNames > 0 and controls.compExtronDXP then
        local str = controls.compExtronDXP.String
        if str == "" or str == const.clearString then
            setProp(controls.compExtronDXP, "String", extronNames[1])
            debugPrint("Auto-populated compExtronDXP: " .. extronNames[1])
        end
    end
end

local function updateOutputButtonsFromFeedback(outputIndex, inputNum)
    local key = (outputIndex == 1) and "btnOutput01" or "btnOutput02"
    local btns = controls[key]
    if not btns then return end
    local arr = isArr(btns) and btns or { btns }
    for i, btn in ipairs(arr) do
        setProp(btn, "Boolean", (inputNum > 0 and i == inputNum))
    end
end

local function setRoute(input, output, source, skipFeedback)
    source = source or "External"
    local matrix = components.extronMatrix
    if not matrix then
        debugPrint("No Extron matrix available (Source: " .. tostring(source) .. ")")
        return false
    end
    if input < 0 or input > config.numInputs or output < 1 or output > config.numOutputs then
        debugPrint("Invalid route: input=" .. tostring(input) .. ", output=" .. tostring(output))
        return false
    end
    local ctrlName = "output." .. output
    local outCtrl = matrix[ctrlName]
    if not outCtrl then
        debugPrint("Control not found: " .. ctrlName)
        return false
    end
    local strVal = tostring(input)
    if outCtrl.String == strVal then
        if not skipFeedback then updateOutputButtonsFromFeedback(output, input) end
        return true
    end
    setProp(outCtrl, "String", strVal)
    debugPrint("Output " .. output .. " → Input " .. input .. " (Source: " .. tostring(source) .. ")")
    if not skipFeedback then
        updateOutputButtonsFromFeedback(output, input)
    end
    return true
end

local function syncRoomBFromRoomA(skipFeedback)
    if not state.roomState then return false end
    local matrix = components.extronMatrix
    if not matrix then return false end
    local inp = tonumber(matrix["output.1"].String) or 0
    if inp < 1 or inp > config.numInputs then return false end
    return setRoute(inp, 2, "Room Combiner", skipFeedback == true)
end

local function cleanupExtronOutputHandlers()
    local matrix = components.extronMatrix
    if not matrix then return end
    cleanupComponentHandlers(matrix, extronOutputControls, function(msg) debugPrint("[Extron DXP] " .. msg) end)
end

local function onOutputStringChanged(outputIndex)
    local matrix = components.extronMatrix
    if not matrix then return end
    local inp = tonumber(matrix["output." .. outputIndex].String) or 0
    updateOutputButtonsFromFeedback(outputIndex, inp)
    debugPrint("Output " .. outputIndex .. " feedback → Input " .. inp .. " (Source: Extron matrix)")
    if outputIndex == 1 and state.roomState then
        syncRoomBFromRoomA(true)
    end
end

local function setExtronMatrixComponent()
    cleanupExtronOutputHandlers()
    components.extronMatrix = setComponent(controls.compExtronDXP, "Extron DXP Matrix", config.extronMatrixType)
    local matrix = components.extronMatrix
    if not matrix then return end

    for _, ctrlName in ipairs(extronOutputControls) do
        local outIdx = tonumber(ctrlName:match("output%.(%d+)")) or 0
        local oc = matrix[ctrlName]
        if oc and bind(oc, function()
            onOutputStringChanged(outIdx)
        end) then
            debugPrint("Registered feedback handler for " .. ctrlName)
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
            if not ctl.Boolean and components.extronMatrix then
                syncRoomBFromRoomA(false)
                debugPrint("Synced Output 2 to Output 1 after combine (Source: Room Combiner)")
            end
        end)
        state.roomState = not btnRoomState.Boolean
        debugPrint("Initial room state: " .. (state.roomState and "Combined" or "Separated"))
    else
        debugPrint("Warning: btnRoomState 1 not found")
    end
end

local function registerEvents()
    bind(controls.compExtronDXP, setExtronMatrixComponent)
    debugPrint("Registered compExtronDXP handler")

    local outputConfig = {
        { ctrl = controls.btnOutput01, output = 1, name = "Output 1" },
        { ctrl = controls.btnOutput02, output = 2, name = "Output 2" },
    }
    for _, cfg in ipairs(outputConfig) do
        local btns = isArr(cfg.ctrl) and cfg.ctrl or { cfg.ctrl }
        for i, btn in ipairs(btns) do
            bind(btn, function()
                setRoute(i, cfg.output, cfg.name, false)
            end)
        end
        debugPrint("Registered " .. #btns .. " button handlers for " .. cfg.name)
    end
end

local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: debug=" .. tostring(const.debug))

    setupComponents()
    setExtronMatrixComponent()
    setDivisibleSpaceControlsComponent()

    if components.extronMatrix then
        setRoute(1, 1, "Init", false)
        if state.roomState then
            syncRoomBFromRoomA(false)
        else
            setRoute(1, 2, "Init", false)
        end
    end

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
DXP84RouterController = {
    setRoute = setRoute,
    syncRoomBFromRoomA = syncRoomBFromRoomA,
}

MatrixController = DXP84RouterController

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing Extron DXP84 Router Controller...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    registerEvents()
    init()
end)

if ok then
    print("✓ Extron DXP84 Router Controller initialized")
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end
