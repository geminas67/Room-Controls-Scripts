--[[
    Audio Router Controller (Salon)
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2026-02-21
    Firmware Req: 10.0.0
    Notes:
    - Flat module pattern, event-driven, no OOP
    - DivisibleSpaceController owns all combination routing; this script
      handles direct source selection and fire-alarm mute only
]]--

-------------------[ Controls ]-------------------
local controls = {
    compAudioRouter  = Controls.compAudioRouter,
    btnAudioSource   = Controls.btnAudioSource,
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

-------------------[ Config ]-------------------
local config = {
    roomName = "Salon Audio Router",
    debugging = true,
    clearString = "[Clear]",
    inputs = {
        SalonD = 1, SalonE = 2, SalonA = 3,
        SalonB = 4, SalonC = 5, SalonF = 6,
        SalonG = 7, SalonH = 8, none = 9,
    },
    outputs = { output01 = 1 },
    componentTypes = {
        audioRouter  = "router_with_output",
        roomControls = "device_controller_script",
    },
}

-------------------[ State ]-------------------
local components = { audioRouter = nil, roomControls = nil, invalid = {} }

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if config.debugging then print("[" .. config.roomName .. "] " .. str) end
end

-------------------[ Functions ]-------------------
local function validateControls()
    local required = { "compAudioRouter", "btnAudioSource", "txtStatus", "compRoomControls" }
    local missing  = {}
    for _, name in ipairs(required) do
        if not controls[name] then table.insert(missing, name) end
    end
    if #missing > 0 then
        print("ERROR: Missing required controls: " .. table.concat(missing, ", "))
        return false
    end
    return true
end

local function normalizeControlArrays()
    if controls.btnAudioSource and not isArr(controls.btnAudioSource) then
        controls.btnAudioSource = { controls.btnAudioSource }
    end
    if not controls.btnAudioSource then controls.btnAudioSource = {} end
end

local function checkStatus()
    for _, isInvalid in pairs(components.invalid) do
        if isInvalid then
            setProp(controls.txtStatus, "String", "Invalid Components")
            setProp(controls.txtStatus, "Value",  1)
            return
        end
    end
    setProp(controls.txtStatus, "String", "OK")
    setProp(controls.txtStatus, "Value",  0)
end

local function setComponent(ctrl, componentType)
    if not ctrl then
        components.invalid[componentType] = true
        checkStatus(); return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == config.clearString then
        if name == config.clearString then ctrl.String = "" end
        ctrl.Color = "white"
        components.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp     = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctrl.String = "[Invalid Component Selected]"; ctrl.Color = "pink"
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end
    ctrl.Color = "white"
    components.invalid[componentType] = false
    checkStatus()
    debugPrint("Connected " .. componentType .. ": " .. name)
    return comp
end

local function setRoute(input, output, source)
    if not components.audioRouter then return end
    components.audioRouter["select." .. tostring(output)].Value = input
    debugPrint("Output " .. tostring(output) .. " → Input " .. tostring(input) .. " (Source: " .. (source or "unknown") .. ")")
end

local function discoverComponents()
    debugPrint("Discovering components...")
    local routerNames, roomCtrlNames = {}, {}

    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == config.componentTypes.audioRouter then
            table.insert(routerNames, comp.Name)
            debugPrint("  Found audio router: " .. comp.Name)
        elseif comp.Type == config.componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomCtrlNames, comp.Name)
            debugPrint("  Found room controls: " .. comp.Name)
        end
    end

    table.sort(routerNames);   table.insert(routerNames,   config.clearString)
    table.sort(roomCtrlNames); table.insert(roomCtrlNames, config.clearString)

    controls.compAudioRouter.Choices  = routerNames
    controls.compRoomControls.Choices = roomCtrlNames

    debugPrint("Discovery complete - routers: " .. (#routerNames - 1) ..
               ", room controls: " .. (#roomCtrlNames - 1))
end

local function setAudioRouterComponent()
    if components.audioRouter and components.audioRouter["select.1"] then
        components.audioRouter["select.1"].EventHandler = nil
        debugPrint("Cleaned up previous audio router handlers")
    end

    local prev = controls.compAudioRouter.String
    components.audioRouter = setComponent(controls.compAudioRouter, "audioRouter")
    debugPrint("Audio router component: '" .. prev .. "' → '" .. controls.compAudioRouter.String .. "'")
    if not components.audioRouter then return end

    components.audioRouter["select.1"].EventHandler = function(ctl)
        local inputValue = ctl.Value
        for i, btn in ipairs(controls.btnAudioSource) do
            setProp(btn, "Boolean", i == inputValue)
        end
        debugPrint("Router feedback: Output 1 → Input " .. tostring(inputValue))
    end
    debugPrint("Registered: audio router select feedback handler")
end

local function setRoomControlsComponent()
    components.roomControls = setComponent(controls.compRoomControls, "roomControls")
    if not components.roomControls then return end

    if components.roomControls["ledFireAlarm"] then
        components.roomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean then
                debugPrint("Fire alarm ACTIVE → routing to none (Source: Room Controls)")
                setRoute(config.inputs.none, config.outputs.output01, "Fire Alarm")
            else
                debugPrint("Fire alarm CLEARED (Source: Room Controls)")
            end
        end
        debugPrint("Registered: fire alarm handler")
    end
end

-------------------[ Events ]-------------------
local function registerEvents()
    controls.compAudioRouter.EventHandler  = function() setAudioRouterComponent() end
    controls.compRoomControls.EventHandler = function() setRoomControlsComponent() end
    debugPrint("Registered: component selector handlers (2)")

    local srcCount = bindArray(controls.btnAudioSource, function(index)
        setRoute(index, config.outputs.output01, "Source Button")
    end)
    debugPrint("Registered: " .. srcCount .. " audio source button handlers")
end

-------------------[ Init ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: Room Name=" .. config.roomName .. ", Debugging=" .. tostring(config.debugging))

    discoverComponents()
    registerEvents()
    setAudioRouterComponent()
    setRoomControlsComponent()

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Public API ]-------------------
AudioRouterController = {
    setRoute = setRoute,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing Audio Router Controller for " .. config.roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)

if ok then
    print("✓ Audio Router Controller initialized for " .. config.roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        controls.txtStatus.String = "INIT FAILED"
        controls.txtStatus.Value  = 2
    end
end
