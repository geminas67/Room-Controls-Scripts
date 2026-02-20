--[[
  Extron DXP Matrix Routing Controller
  Author: Nikolas Smith, Q-SYS
  Date: 2025-02-19
  Version: 5.0
  Firmware Req: 10.0.0

  Flat module architecture - no OOP. One matrix per system; shared by all rooms.
  External scripts call into MatrixController table for routing and UCI handoff.
]]--

-------------------[ Controls ]-------------------
local controls = {
    txtSource              = Controls.txtSource,
    btnVideoSource         = Controls.btnVideoSource,
    btnDestination         = Controls.btnDestination,
    ledSourceRouted        = Controls.ledSourceRouted,
    ledExtronSignalPresence = Controls.ledExtronSignalPresence,
    btnNav07               = Controls['btnNav07'],
    btnNav08               = Controls['btnNav08'],
    btnNav09               = Controls['btnNav09'],
    txtStatus              = Controls.txtStatus,
    compExtronDXPMatrix    = Controls.compExtronDXPMatrix,
    compCallSync           = Controls.compCallSync,
    compClickShare         = Controls.compClickShare,
    compRoomControls       = Controls.compRoomControls,
}

-------------------[ Utilities ]-------------------
local function isArr(val)
    return type(val) == "table" and val[1] ~= nil
end

local function setProp(ctrl, prop, val)
    if not ctrl or ctrl[prop] == val then return end
    ctrl[prop] = val
end

local function bind(ctrl, handler)
    if ctrl then ctrl.EventHandler = handler end
end

local function bindArray(ctrls, handler)
    if not ctrls then return 0 end
    local array = isArr(ctrls) and ctrls or { ctrls }
    local count = 0
    for idx, ctrl in ipairs(array) do
        if ctrl then
            bind(ctrl, function(ctl) handler(idx, ctl) end)
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
local debugging  = true
local clearString = "[Clear]"
local roomName   = (function()
    local ok, name = pcall(function()
        local rn = Controls.roomName
        return (rn and rn.String ~= "" and rn.String) or nil
    end)
    return (ok and name and "[" .. name .. "]") or "[Extron DXP]"
end)()

local componentTypes = {
    extronRouter = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    callSync     = "call_sync",
    clickShare   = "%PLUGIN%_bb4217ac-401f-4698-aad9-9e4b2496ff46_%FP%_e0a4597b59bdca3247ccb142ce451198",
    roomControls = "device_controller_script",
}

local inputs = {
    ClickShare = 1, TeamsPC = 2, TeamsPCSecondary = 3, LaptopFront = 4, LaptopRear = 5, NoSource = 0
}

local uciLayerToInput   = { [7] = inputs.TeamsPC, [8] = inputs.LaptopFront, [9] = inputs.ClickShare }
local sourceButtonToInput = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 5, [6] = 0 }
local sourceNames       = {
    [0] = "No Source", [1] = "ClickShare", [2] = "Teams PC",
    [3] = "Teams PC2", [4] = "Front Laptop", [5] = "Rear Laptop"
}

-------------------[ State ]-------------------
local norm = {}

local components = {
    extronRouter     = nil,
    callSync         = nil,
    clickShare       = nil,
    roomControls     = nil,
    uciLayerSelector = nil,
    invalid          = {}
}

local state = { power = false, warming = true, cooling = false, lastUCILayer = nil }

local uci = { controller = nil, enabled = true, monitorTimer = nil }

local sourcePriority = {
    { name = "Teams PC", input = inputs.TeamsPC, checkFunc = function()
        local offHook = components.callSync and components.callSync["off.hook"] and
                        components.callSync["off.hook"].Boolean
        local signalLed = norm.ledExtronSignalPresence and norm.ledExtronSignalPresence[3]
        return offHook or (signalLed and signalLed.Boolean)
    end },
    { name = "Front Laptop", input = inputs.LaptopFront, checkFunc = function()
        local led = norm.ledExtronSignalPresence and norm.ledExtronSignalPresence[4]
        return led and led.Boolean
    end },
    { name = "Rear Laptop", input = inputs.LaptopRear, checkFunc = function()
        local led = norm.ledExtronSignalPresence and norm.ledExtronSignalPresence[5]
        return led and led.Boolean
    end },
    { name = "ClickShare", input = inputs.ClickShare, checkFunc = function()
        local led = norm.ledExtronSignalPresence and norm.ledExtronSignalPresence[1]
        return led and led.Boolean
    end },
    { name = "Teams PC2", input = inputs.TeamsPC, checkFunc = function()
        local led = norm.ledExtronSignalPresence and norm.ledExtronSignalPresence[2]
        return led and led.Boolean
    end },
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if debugging then print(roomName .. " " .. str) end
end

-------------------[ Status ]-------------------
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

-------------------[ Component Management ]-------------------
local function setComponent(ctrl, componentType, expectedType)
    if not ctrl then
        debugPrint("Control for " .. componentType .. " is nil!")
        components.invalid[componentType] = true
        checkStatus()
        return nil
    end
    local name = ctrl.String
    if not name or name == "" or name == clearString then
        if name == clearString then setProp(ctrl, "String", "") end
        setProp(ctrl, "Color", "white")
        components.invalid[componentType] = false
        checkStatus()
        debugPrint("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    if #Component.GetControls(comp) < 1 then
        setProp(ctrl, "String", "[Invalid Component Selected]")
        setProp(ctrl, "Color", "pink")
        components.invalid[componentType] = true
        checkStatus()
        debugPrint("ERROR: " .. componentType .. " component '" .. name .. "' is invalid")
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
    debugPrint("Set " .. componentType .. " component: " .. name)
    return comp
end

local function setComponentByType(ctrl, componentType, storageKey, eventMap)
    if not ctrl then return nil end
    local oldComp = components[storageKey]
    if oldComp and eventMap then
        local names = {}
        for controlName in pairs(eventMap) do table.insert(names, controlName) end
        cleanupComponentHandlers(oldComp, names, function(msg) debugPrint("[" .. componentType .. "] " .. msg) end)
    end
    components[storageKey] = setComponent(ctrl, componentType)
    local comp = components[storageKey]
    if comp and eventMap then
        local handlerCount = 0
        for controlName, handler in pairs(eventMap) do
            if comp[controlName] then bind(comp[controlName], handler); handlerCount = handlerCount + 1 end
        end
        debugPrint("Registered " .. handlerCount .. " handlers for " .. componentType)
    end
    return comp
end

local function discoverComponents()
    local discovered = { extronDXP = {}, callSync = {}, clickShare = {}, roomControls = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.extronRouter then
            table.insert(discovered.extronDXP, comp.Name)
            debugPrint("Discovered Extron DXP: " .. comp.Name)
        elseif comp.Type == componentTypes.callSync then
            table.insert(discovered.callSync, comp.Name)
            debugPrint("Discovered CallSync: " .. comp.Name)
        elseif comp.Type == componentTypes.clickShare then
            table.insert(discovered.clickShare, comp.Name)
            debugPrint("Discovered ClickShare: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(discovered.roomControls, comp.Name)
            debugPrint("Discovered Room Controls: " .. comp.Name)
        end
    end
    local total = #discovered.extronDXP + #discovered.callSync + #discovered.clickShare + #discovered.roomControls
    debugPrint("Component discovery complete - " .. total .. " components found")
    return discovered
end

-- Forward declarations needed by setters that reference each other
local checkAutoSwitch

local function setExtronDXPComponent()
    components.extronRouter = setComponent(controls.compExtronDXPMatrix, "Extron DXP Matrix")
end

local function setCallSyncComponent()
    setComponentByType(controls.compCallSync, "CallSync", "callSync",
        { ["off.hook"] = function() checkAutoSwitch() end })
end

local function setClickShareComponent()
    components.clickShare = setComponent(controls.compClickShare, "ClickShare")
end

local function setRoomControlsComponent()
    setComponentByType(controls.compRoomControls, "Room Controls", "roomControls", {
        ["ledSystemPower"] = function(ctl)
            state.power = ctl.Boolean
            debugPrint("System power " .. (ctl.Boolean and "ON" or "OFF"))
            if ctl.Boolean then checkAutoSwitch() end
        end,
        ["ledSystemWarming"] = function(ctl)
            state.warming = ctl.Boolean
            debugPrint("System warming " .. (ctl.Boolean and "ON" or "OFF"))
            if not ctl.Boolean and state.power then checkAutoSwitch() end
        end,
        ["ledSystemCooling"] = function(ctl)
            state.cooling = ctl.Boolean
            debugPrint("System cooling " .. (ctl.Boolean and "ON" or "OFF"))
            if not ctl.Boolean and not state.power then
                Timer.CallAfter(function()
                    debugPrint("Power-off settle complete, checking priority sources")
                    checkAutoSwitch()
                end, 2)
            end
        end,
    })
end

local function setupComponentSelectors(discovered)
    local function setup(ctrl, names, setMethod, componentType)
        if not ctrl then return end
        local choices = { clearString }
        for _, name in ipairs(names) do table.insert(choices, name) end
        ctrl.Choices = choices
        bind(ctrl, function()
            debugPrint(componentType .. " selection changed to: " .. ctrl.String)
            setMethod()
        end)
        if #names > 0 and (ctrl.String == "" or not ctrl.String) then
            ctrl.String = names[1]
            debugPrint("Auto-selected " .. componentType .. ": " .. names[1])
        end
        debugPrint("Registered event handler for " .. componentType .. " selector")
    end
    setup(controls.compExtronDXPMatrix, discovered.extronDXP,   setExtronDXPComponent,  "Extron DXP Matrix")
    setup(controls.compCallSync,         discovered.callSync,    setCallSyncComponent,   "CallSync")
    setup(controls.compClickShare,       discovered.clickShare,  setClickShareComponent, "ClickShare")
    setup(controls.compRoomControls,     discovered.roomControls, setRoomControlsComponent, "Room Controls")
end

-------------------[ Routing ]-------------------
local updateDestinationFeedback  -- forward declaration
local updateDestinationText      -- forward declaration
local updateSourceText           -- forward declaration

local function getSelectedSource()
    for srcIdx = 1, 6 do
        local btn = norm.btnVideoSource and norm.btnVideoSource[srcIdx]
        if btn and btn.Boolean then return sourceButtonToInput[srcIdx] end
    end
    return nil
end

local function setRoute(input, output, source)
    if not components.extronRouter then return end
    components.extronRouter['output.' .. output].String = tostring(input)
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    updateDestinationFeedback()
    updateDestinationText()
end

local function clearRoute(output)
    if not components.extronRouter then return end
    components.extronRouter['output.' .. output].String = '0'
    debugPrint("Cleared Output " .. output)
    updateDestinationFeedback()
    updateDestinationText()
end

local function setSource(input, source)
    if not components.extronRouter then return end
    local src = source or "System"
    -- Select matching source button to keep UI in sync
    for btnIdx, inputNum in pairs(sourceButtonToInput) do
        if inputNum == input then
            for idx = 1, 6 do
                local btn = norm.btnVideoSource and norm.btnVideoSource[idx]
                if btn then setProp(btn, "Boolean", idx == btnIdx) end
            end
            updateSourceText()
            break
        end
    end
    -- TeamsPC splits across odd/even outputs; all other sources route uniformly
    if input == inputs.TeamsPC then
        setRoute(inputs.TeamsPC, 1, src);          setRoute(inputs.TeamsPCSecondary, 2, src)
        setRoute(inputs.TeamsPC, 3, src);          setRoute(inputs.TeamsPCSecondary, 4, src)
    else
        for dest = 1, 4 do setRoute(input, dest, src) end
    end
    updateSourceText()
    updateDestinationFeedback()
end

updateDestinationFeedback = function()
    if not components.extronRouter then return end
    local selected = getSelectedSource()
    for idx = 1, 4 do
        local currentInput = tonumber(components.extronRouter['output.' .. idx].String) or 0
        local isRouted = false
        if selected then
            if selected == inputs.TeamsPC then
                isRouted = (currentInput == inputs.TeamsPC) or (currentInput == inputs.TeamsPCSecondary)
            else
                isRouted = (currentInput == selected)
            end
        end
        local led = norm.ledSourceRouted and norm.ledSourceRouted[idx]
        if led then setProp(led, "Boolean", isRouted) end
    end
end

updateDestinationText = function()
    if not components.extronRouter then return end
    local destNames = { [1] = "Front Left", [2] = "Front Right", [3] = "Rear Left", [4] = "Rear Right" }
    local routes, count = {}, 0
    for output = 1, 4 do
        local currentInput = tonumber(components.extronRouter['output.' .. output].String) or 0
        if currentInput > 0 then
            count = count + 1
            table.insert(routes, (sourceNames[currentInput] or "Unknown") .. " → " .. destNames[output])
        end
    end
    if count == 0 then setProp(controls.txtStatus, "String", "")
    elseif count == 4 then
        setProp(controls.txtStatus, "String", "All Displays Active")
        Timer.CallAfter(function() setProp(controls.txtStatus, "String", "") end, 3)
    else setProp(controls.txtStatus, "String", table.concat(routes, ", ")) end
end

updateSourceText = function()
    setProp(controls.txtSource, "String", sourceNames[getSelectedSource()] or "No Source")
end

local function setDestinationButtonProps(output, color, text, disabled)
    local btn = norm.btnDestination and norm.btnDestination[output]
    if not btn then return end
    setProp(btn, "Color", color)
    if text and text ~= "" then setProp(btn, "String", text) end
    setProp(btn, "IsDisabled", disabled)
end

-------------------[ Auto-Switch ]-------------------
checkAutoSwitch = function()
    for _, source in ipairs(sourcePriority) do
        if source.checkFunc() then
            if not state.power and components.roomControls then
                debugPrint("Powering on system for " .. source.name)
                components.roomControls["btnSystemOnOff"].Boolean = true
            end
            debugPrint("Auto-switching to " .. source.name)
            setSource(source.input, "Auto-Switch")
            return
        end
    end
end

-------------------[ UCI Integration ]-------------------
local startUCIMonitoring  -- forward declaration

local function setUCIController(controller)
    if not controller then return end
    uci.controller = controller
    debugPrint("UCI Controller reference set")
    if uci.enabled then startUCIMonitoring() end
end

local function triggerUCILayer(layer)
    local btnNav = norm.uciButtons and norm.uciButtons[layer]
    if not btnNav then debugPrint("Warning: btnNav for layer " .. layer .. " not found"); return false end
    local ok, err = pcall(function() btnNav:Trigger() end)
    if ok then debugPrint("Triggered UCI layer " .. layer .. " via btnNav" .. layer); return true end
    debugPrint("Error triggering btnNav" .. layer .. ": " .. tostring(err))
    return false
end

local function checkUCILayerChange()
    if not uci.controller or not uci.enabled then return end
    local current = uci.controller.varActiveLayer
    if state.lastUCILayer == current then return end
    debugPrint("UCI Layer changed: " .. tostring(state.lastUCILayer) .. " → " .. tostring(current))
    state.lastUCILayer = current
    if uciLayerToInput[current] then setSource(uciLayerToInput[current], "UCI Layer " .. current) end
end

startUCIMonitoring = function()
    if not uci.controller then debugPrint("No UCI Controller available for monitoring"); return end
    uci.monitorTimer = Timer.New()
    uci.monitorTimer.EventHandler = function()
        checkUCILayerChange()
        uci.monitorTimer:Start(0.1)
    end
    uci.monitorTimer:Start(0.1)
    debugPrint("UCI layer monitoring started")
end

local function enableUCIIntegration()
    uci.enabled = true
    if uci.controller then startUCIMonitoring() end
    debugPrint("UCI Integration enabled")
end

local function disableUCIIntegration()
    uci.enabled = false
    if uci.monitorTimer then uci.monitorTimer:Stop(); uci.monitorTimer = nil end
    debugPrint("UCI Integration disabled")
end

local function onUCILayerChange(info)
    if not uci.enabled then return end
    debugPrint("UCI Layer changed: " .. tostring(info.previousLayer) .. " → " .. tostring(info.currentLayer) .. " (" .. info.layerName .. ")")
    if uciLayerToInput[info.currentLayer] then
        setSource(uciLayerToInput[info.currentLayer], "UCI Layer " .. info.currentLayer)
    end
end

-------------------[ Event Registration ]-------------------
local function registerEvents()
    local sourceCount = 0
    for idx = 1, 6 do
        local btn = norm.btnVideoSource and norm.btnVideoSource[idx]
        if btn then
            bind(btn, function(ctl)
                if not ctl.Boolean then return end
                for srcIdx = 1, 6 do
                    if srcIdx ~= idx then
                        local other = norm.btnVideoSource and norm.btnVideoSource[srcIdx]
                        if other then setProp(other, "Boolean", false) end
                    end
                end
                if idx == 2 or idx == 3 then
                    setDestinationButtonProps(2, '#ff6666', 'N/A', true)
                    setDestinationButtonProps(4, '#ff6666', 'N/A', true)
                else
                    setDestinationButtonProps(2, '#ff7c7c7c', '', false)
                    setDestinationButtonProps(4, '#ff7c7c7c', '', false)
                end
                debugPrint("Source button " .. idx .. " pressed")
                updateSourceText()
                updateDestinationFeedback()
            end)
            sourceCount = sourceCount + 1
        end
    end
    debugPrint("Registered " .. sourceCount .. " source button handlers")

    local destCount = 0
    for idx = 1, 5 do
        local btn = norm.btnDestination and norm.btnDestination[idx]
        if btn then
            bind(btn, function()
                local selected = getSelectedSource()
                if not selected then return end
                if idx == 5 then
                    if selected == inputs.TeamsPC or selected == inputs.TeamsPCSecondary then
                        setRoute(inputs.TeamsPC, 1, "User Button");         setRoute(inputs.TeamsPCSecondary, 2, "User Button")
                        setRoute(inputs.TeamsPC, 3, "User Button");         setRoute(inputs.TeamsPCSecondary, 4, "User Button")
                    else
                        for dest = 1, 4 do setRoute(selected, dest, "User Button") end
                    end
                elseif selected == inputs.TeamsPC or selected == inputs.TeamsPCSecondary then
                    if idx == 1 then
                        setRoute(inputs.TeamsPC, 1, "User Button"); setRoute(inputs.TeamsPCSecondary, 2, "User Button")
                    elseif idx == 3 then
                        setRoute(inputs.TeamsPC, 3, "User Button"); setRoute(inputs.TeamsPCSecondary, 4, "User Button")
                    end
                else
                    setRoute(selected, idx, "User Button")
                end
            end)
            destCount = destCount + 1
        end
    end
    debugPrint("Registered " .. destCount .. " destination button handlers")

    local uciCount = 0
    for layer, btn in pairs(norm.uciButtons or {}) do
        if btn then
            bind(btn, function(ctl)
                if ctl.Boolean and uciLayerToInput[layer] then
                    debugPrint("UCI Button " .. layer .. " pressed, switching to input " .. uciLayerToInput[layer])
                    setSource(uciLayerToInput[layer], "UCI Button " .. layer)
                end
            end)
            uciCount = uciCount + 1
        end
    end
    debugPrint("Registered " .. uciCount .. " UCI button handlers")

    local sigCount = bindArray(norm.ledExtronSignalPresence, function() checkAutoSwitch() end)
    debugPrint("Registered " .. sigCount .. " signal presence handlers for auto-switch")
end

-------------------[ Initialization ]-------------------
local function init()
    if not controls.txtSource then print("ERROR: Missing required control: txtSource"); return end

    -- Build normalized control arrays
    norm = {
        btnVideoSource          = {},
        btnDestination          = {},
        ledSourceRouted         = {},
        ledExtronSignalPresence = {},
        uciButtons              = { [7] = controls.btnNav07, [8] = controls.btnNav08, [9] = controls.btnNav09 }
    }
    if controls.btnVideoSource then
        for idx = 1, 6 do norm.btnVideoSource[idx] = controls.btnVideoSource[idx] end
    end
    if controls.btnDestination then
        for idx = 1, 5 do norm.btnDestination[idx] = controls.btnDestination[idx] end
    end
    if controls.ledSourceRouted then
        for idx = 1, 4 do norm.ledSourceRouted[idx] = controls.ledSourceRouted[idx] end
    end
    if controls.ledExtronSignalPresence then
        for idx = 1, 5 do norm.ledExtronSignalPresence[idx] = controls.ledExtronSignalPresence[idx] end
    end

    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: debugging=" .. tostring(debugging) .. ", uciEnabled=" .. tostring(uci.enabled))

    local discovered = discoverComponents()
    setupComponentSelectors(discovered)
    setExtronDXPComponent()
    setCallSyncComponent()
    setClickShareComponent()
    setRoomControlsComponent()
    registerEvents()

    if components.roomControls then
        state.power   = components.roomControls["ledSystemPower"].Boolean
        state.warming = components.roomControls["ledSystemWarming"].Boolean
    end

    -- TeamsPC2 (button 3) cannot be routed independently - disable it
    local teamsPC2Btn = norm.btnVideoSource and norm.btnVideoSource[3]
    if teamsPC2Btn then
        setProp(teamsPC2Btn, "IsDisabled", true)
        setProp(teamsPC2Btn, "Color", "#ff6666")
    end

    local ok, uciSel = pcall(function() return Component.New('BDRM-UCI Layer Selector') end)
    if ok and uciSel then
        components.uciLayerSelector = uciSel
        debugPrint("UCI Layer Selector component set")
    end

    updateDestinationFeedback()
    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Cleanup ]-------------------
local function cleanup()
    if uci.monitorTimer then uci.monitorTimer:Stop(); uci.monitorTimer = nil end
    uci.controller = nil
    debugPrint("Cleanup completed")
end

-------------------[ Public API ]-------------------
-- Exposed for external scripts (room controllers, UCI scripts, etc.)
MatrixController = {
    setUCIController      = setUCIController,
    triggerUCILayer       = triggerUCILayer,
    onUCILayerChange      = onUCILayerChange,
    enableUCIIntegration  = enableUCIIntegration,
    disableUCIIntegration = disableUCIIntegration,
    setRoute              = setRoute,
    setSource             = setSource,
    clearRoute            = clearRoute,
    checkAutoSwitch       = checkAutoSwitch,
    cleanup               = cleanup,
}

-------------------[ Start ]-------------------
local ok, err = pcall(init)
if ok then
    print(roomName .. " Controller initialized successfully")
else
    print(roomName .. " ERROR: Initialization failed: " .. tostring(err))
end
