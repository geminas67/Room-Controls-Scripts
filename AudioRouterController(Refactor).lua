--[[
    Audio Router Controller (Refactored)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2025-03-24
    Firmware Req: 10.0.0
]]--

-------------------[ Configuration ]-------------------
local cfg = {
    inputs = {
        input01 = 1, 
        input02 = 2, 
        input03 = 3, 
        input04 = 4,
        input05 = 5, 
        input06 = 6, 
        input07 = 7, 
        input08 = 8,
        none    = 9,
    },
    outputs = { defaultOutput = 1 },
    componentTypes = {
        audioRouter  = "router_with_output",
        roomControls = "device_controller_script",
    },
    inputChoiceLabels = {
        "Input 1", "Input 2", "Input 3", "Input 4",
        "Input 5", "Input 6", "Input 7", "Input 8", "None",
    },
}

-------------------[ Controls ]-------------------
local controls = {
    compAudioRouter  = Controls.compAudioRouter,
    btnAudioSource   = Controls.btnAudioSource,
    defaultInput     = Controls.defaultInput,
    defaultOutput    = Controls.defaultOutput,
    txtStatus        = Controls.txtStatus,
    compRoomControls = Controls.compRoomControls,
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

local function clearControlHandler(ctrl)
    if not ctrl then return end
    pcall(function() ctrl.EventHandler = nil end)
end

-------------------[ Config ]-------------------
local const = {
    roomName = "Audio Router",
    debug = true,
    clearString = "[Clear]",
}

-------------------[ State ]-------------------
local components = {
    audioRouter = nil,
    roomControls = nil,
    invalid = {},
}
local state = {
    lastInput = {},
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if const.debug then print("[" .. const.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local required = {
        compAudioRouter = controls.compAudioRouter,
        btnAudioSource = controls.btnAudioSource,
        defaultInput = controls.defaultInput,
        defaultOutput = controls.defaultOutput,
        txtStatus = controls.txtStatus,
        compRoomControls = controls.compRoomControls,
    }
    local missing = {}
    for name, control in pairs(required) do
        if not control then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: AudioRouterController missing required controls:")
        for _, name in ipairs(missing) do print("  - " .. name) end
        return false
    end
    return true
end

local function normalizeControlArrays()
    if controls.btnAudioSource and not controls.btnAudioSource[1] then
        controls.btnAudioSource = { controls.btnAudioSource }
    end
    if not controls.btnAudioSource then
        controls.btnAudioSource = {}
    end
end

local function checkStatus()
    for _, isInvalid in pairs(components.invalid) do
        if isInvalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value", 1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value", 0)
end

local function setComponentInvalid(componentType)
    components.invalid[componentType] = true
    checkStatus()
end

local function setComponentValid(componentType)
    components.invalid[componentType] = false
    checkStatus()
end

local function setComponent(ctrl, componentType, expectedType)
    if not ctrl then
        setComponentInvalid(componentType)
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == const.clearString then
        if name == const.clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        setComponentValid(componentType)
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        setComponentInvalid(componentType)
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    if expectedType and comp.Type ~= expectedType then
        setProp(ctrl, "String", "[Wrong Component Type]")
        setProp(ctrl, "Color", "pink")
        setComponentInvalid(componentType)
        debugPrint(
            "ERROR: " .. componentType .. " wrong type. Expected " .. tostring(expectedType)
                .. ", got " .. tostring(comp.Type)
        )
        return nil
    end
    setProp(ctrl, "Color", "white")
    setComponentValid(componentType)
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function getSelectedDefaultInput()
    local selection = controls.defaultInput and controls.defaultInput.Value or 0
    return selection > 0 and selection or 1
end

local function setRoute(input, output, source)
    local router = components.audioRouter
    if not router then return end
    local selectCtrl = router["select." .. tostring(output)]
    if not selectCtrl then return end
    setProp(selectCtrl, "Value", input)
    if input ~= cfg.inputs.none then
        state.lastInput[output] = input
    end
    debugPrint(
        "Route: Output " .. tostring(output) .. " → Input " .. tostring(input)
            .. " (Source: " .. tostring(source) .. ")"
    )
end

local function setupDefaultInputChoices()
    setProp(controls.defaultInput, "Choices", cfg.inputChoiceLabels)
    if controls.defaultInput.Value == 0 then
        setProp(controls.defaultInput, "Value", 1)
    end
    debugPrint("Default input choices configured (" .. #cfg.inputChoiceLabels .. " options)")
end

local function discoverComponents()
    debugPrint("Discovering components...")
    local audioRouterNames = {}
    local roomControlsNames = {}
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == cfg.componentTypes.audioRouter then
            table.insert(audioRouterNames, comp.Name)
            debugPrint("  Found audio router: " .. comp.Name)
        elseif comp.Type == cfg.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomControlsNames, comp.Name)
            debugPrint("  Found room controls: " .. comp.Name)
        end
    end
    table.sort(audioRouterNames)
    table.insert(audioRouterNames, const.clearString)
    setProp(controls.compAudioRouter, "Choices", audioRouterNames)

    table.sort(roomControlsNames)
    table.insert(roomControlsNames, const.clearString)
    setProp(controls.compRoomControls, "Choices", roomControlsNames)

    debugPrint(
        "Discovery complete — audio routers: " .. (#audioRouterNames - 1)
            .. ", room controls: " .. (#roomControlsNames - 1)
    )
end

local function setAudioRouterComponent()
    local oldRouter = components.audioRouter
    if oldRouter then
        cleanupComponentHandlers(oldRouter, { "select.1" }, function(msg) debugPrint("[Audio Router] " .. msg) end)
    end

    components.audioRouter = setComponent(
        controls.compAudioRouter,
        "Audio Router",
        cfg.componentTypes.audioRouter
    )
    local router = components.audioRouter
    if not router or not router["select.1"] then return end

    bind(router["select.1"], function(ctl)
        local inputValue = ctl.Value
        local btnList = controls.btnAudioSource
        local array = isArr(btnList) and btnList or { btnList }
        for i, btn in ipairs(array) do
            if btn then setProp(btn, "Boolean", (i == inputValue)) end
        end
        debugPrint("Router feedback: Output 1 → Input " .. inputValue .. " (Source: Audio Router)")
    end)
    debugPrint("Registered audio router output feedback handler")
end

local function setRoomControlsComponent()
    components.roomControls = setComponent(
        controls.compRoomControls,
        "Room Controls",
        cfg.componentTypes.roomControls
    )
    local roomComp = components.roomControls
    if not roomComp then return end

    local ledPower = roomComp["ledSystemPower"]
    if ledPower then
        bind(ledPower, function(ctl)
            local route = ctl.Boolean and getSelectedDefaultInput() or cfg.inputs.none
            setRoute(route, cfg.outputs.defaultOutput, "Room Controls — System Power")
        end)
        debugPrint("Registered: ledSystemPower (Room Controls)")
    end

    local ledFire = roomComp["ledFireAlarm"]
    if ledFire then
        bind(ledFire, function(ctl)
            if ctl.Boolean then
                setRoute(cfg.inputs.none, cfg.outputs.defaultOutput, "Room Controls — Fire Alarm (active)")
            else
                local powerLed = roomComp["ledSystemPower"]
                if powerLed and powerLed.Boolean then
                    local defaultRoute = state.lastInput[cfg.outputs.defaultOutput] or getSelectedDefaultInput()
                    setRoute(defaultRoute, cfg.outputs.defaultOutput, "Room Controls — Fire Alarm (cleared)")
                end
            end
        end)
        debugPrint("Registered: ledFireAlarm (Room Controls)")
    end
end

local function registerEvents()
    bind(controls.compAudioRouter, function()
        debugPrint("Component selector changed (Source: Audio Router dropdown)")
        setAudioRouterComponent()
    end)
    bind(controls.compRoomControls, function()
        debugPrint("Component selector changed (Source: Room Controls dropdown)")
        setRoomControlsComponent()
    end)
    bind(controls.defaultInput, function()
        debugPrint(
            "Default input changed → " .. tostring(controls.defaultInput and controls.defaultInput.String or "?")
                .. " (Source: Default Input)"
        )
    end)

    local btnCount = bindArray(controls.btnAudioSource, function(index)
        setRoute(index, cfg.outputs.defaultOutput, "Audio Source Button " .. tostring(index))
    end)
    debugPrint("Registered " .. btnCount .. " audio source button handler(s)")
end

local function cleanup()
    if components.audioRouter then
        cleanupComponentHandlers(components.audioRouter, { "select.1" }, function(msg) debugPrint(msg) end)
    end
    if components.roomControls then
        cleanupComponentHandlers(components.roomControls, { "ledSystemPower", "ledFireAlarm" }, function(msg)
            debugPrint(msg)
        end)
    end
    clearControlHandler(controls.compAudioRouter)
    clearControlHandler(controls.compRoomControls)
    clearControlHandler(controls.defaultInput)

    local btnList = controls.btnAudioSource
    local array = isArr(btnList) and btnList or { btnList }
    for _, btn in ipairs(array) do
        clearControlHandler(btn)
    end
    debugPrint("Cleanup complete")
end

local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. const.roomName .. ", debug=" .. tostring(const.debug))

    registerEvents()
    discoverComponents()
    setupDefaultInputChoices()
    setAudioRouterComponent()
    setRoomControlsComponent()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
AudioRouterController = {
    setRoute = function(input, output)
        setRoute(input, output or cfg.outputs.defaultOutput, "External API")
    end,
    cleanup = cleanup,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing Audio Router Controller...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ Audio Router Controller initialized")
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end
