--[[
  Extron DXP Matrix Routing Controller
  Author: Nikolas Smith, Q-SYS
  Date: 2026-04-09
  Version: 5.7
  Firmware Req: 10.2.0

  Room-combine matrix follows compDivisibleSpaceControls btnRoomState 1–3 (interlock). Two
  compRoomControls selectors (RmA/RmB) track per-room power; auto-switch only asserts power on
  room(s) allowed by roomLayoutMode (separated → source’s room only; combined → both). UCI
  publishes layer changes via Notifications (uciLayerNotifyMatrix); do not bind btnNav07–10 here.
  Output handlers refresh ledSourceRouted when output.N changes.
]]--

-------------------[ Controls ]-------------------
local controls = {
    txtSource               = Controls.txtSource,
    btnSource               = Controls.btnSource,
    btnDestination          = Controls.btnDestination,
    ledSourceRouted         = Controls.ledSourceRouted,
    ledSignalPresence       = Controls.ledSignalPresence,
    btnNav07                = Controls['btnNav07'],
    btnNav08                = Controls['btnNav08'],
    btnNav09                = Controls['btnNav09'],
    btnNav10                = Controls['btnNav10'],
    txtStatus               = Controls.txtStatus,
    compExtronDXP           = Controls.compExtronDXP,
    compCallSync            = Controls.compCallSync,
    compClickShare          = Controls.compClickShare,
    compRoomControls        = Controls.compRoomControls,
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

local function indexedControls(ctrl, count)
    local tbl = {}
    if ctrl then
        for idx = 1, count do tbl[idx] = ctrl[idx] end
    end
    return tbl
end

-------------------[ Config ]-------------------
local debugging  = true
local clearString = "[Clear]"
local roomName   = (function()
    local ok, name = pcall(function()
        local roomName = Controls.roomName
        return (roomName and roomName.String ~= "" and roomName.String) or nil
    end)
    return (ok and name and "[" .. name .. "]") or "[Extron DXP]"
end)()

local componentTypes = {
    extronMatrix = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    callSync     = "call_sync",
    roomControls = "device_controller_script",
}

local inputs = {
    LaptopRmA = 1, LaptopRmB = 2, TeamsPCRmA = 3, TeamsPCRmB = 4, NoSource = 0
}

local uciLayerToInput   = { [7] = inputs.TeamsPCRmA, [8] = inputs.TeamsPCRmB, [9] = inputs.LaptopRmA, [10] = inputs.LaptopRmB }

-- Must match UCIController(DivisibleSpace): cross-script handoff.
local uciLayerNotifyMatrix = "HitachiTraining_UCIMatrixLayer"
local sourceButtonToInput = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 0 }
local inputToSourceButton = {}
for btnIdx, inputNum in pairs(sourceButtonToInput) do
    inputToSourceButton[inputNum] = btnIdx
end

local sourceNames = {
    [0] = "No Source", [1] = "Laptop RmA", [2] = "Laptop RmB", [3] = "TeamsPC RmA", [4] = "TeamsPC RmB",
}

-- Divisible space: output indices per room (extend lists when adding displays; only 1–2 used on site)
local routingConfig = {
    outputsForRoomA = { 1 },
    outputsForRoomB = { 2 },
}

local outputInRoomA, outputInRoomB = {}, {}
for _, out in ipairs(routingConfig.outputsForRoomA) do outputInRoomA[out] = true end
for _, out in ipairs(routingConfig.outputsForRoomB) do outputInRoomB[out] = true end

local combinedOutputsInUse = {}
for _, outList in ipairs({ routingConfig.outputsForRoomA, routingConfig.outputsForRoomB }) do
    for _, out in ipairs(outList) do table.insert(combinedOutputsInUse, out) end
end

-------------------[ State ]-------------------
local norm = {}

local components = {
    extronMatrix            = nil,
    callSync                = nil,
    roomControls            = {},  -- [1] = RmA, [2] = RmB device_controller_script
    divisibleSpaceControls  = nil,
    invalid                 = {},
}

-- roomLayoutMode: 1 = Separated, 2/3 = Combined (both outputs follow selected source, e.g. UCI layer)
-- lastSeparatedSourceA/B: expected routed input per side when separated (independent of the other room)
local state = {
    powerRoomA = false,       -- Room A is powered off
    powerRoomB = false,       -- Room B is powered off
    warmingRoomA = true,      -- Room A is warming
    warmingRoomB = true,      -- Room B is warming
    coolingRoomA = false,     -- Room A is cooling
    coolingRoomB = false,     -- Room B is cooling
    roomLayoutMode = 1,       -- 1 = Separated, 2/3 = Combined
    lastSeparatedSourceA = nil, -- Expected routed input for Room A when separated
    lastSeparatedSourceB = nil, -- Expected routed input for Room B when separated
}

local function isCombinedLayout()
    return state.roomLayoutMode == 2 or state.roomLayoutMode == 3
end

local uci = { controller = nil, enabled = true, matrixNotifySubId = nil }

local sourcePriority = {
    { name = "Teams PCRmA", input = inputs.TeamsPCRmA, checkFunc = function()
        local offHook = components.callSync and components.callSync["off.hook"] and
                        components.callSync["off.hook"].Boolean
        local signalLed = norm.ledSignalPresence and norm.ledSignalPresence[5]
        return offHook or (signalLed and signalLed.Boolean)
    end },
    { name = "LaptopRmA", input = inputs.LaptopRmA, checkFunc = function()
        local led = norm.ledSignalPresence and norm.ledSignalPresence[1]
        return led and led.Boolean
    end },
    { name = "LaptopRmB", input = inputs.LaptopRmB, checkFunc = function()
        local led = norm.ledSignalPresence and norm.ledSignalPresence[2]
        return led and led.Boolean
    end },
    { name = "Teams PCRmA (USB)", input = inputs.TeamsPCRmA, checkFunc = function()
        local led = norm.ledSignalPresence and norm.ledSignalPresence[3]
        return led and led.Boolean
    end },
    { name = "Teams PCRmB (USB)", input = inputs.TeamsPCRmB, checkFunc = function()
        local led = norm.ledSignalPresence and norm.ledSignalPresence[4]
        return led and led.Boolean
    end },
}

-------------------[ Debug ]-------------------
local function debugPrint(str)
    if debugging then print(roomName .. " " .. str) end
end

-------------------[ Validation ]-------------------
local function validateControls()
    if not controls.txtSource then
        print("ERROR: Missing required control: txtSource")
        return false
    end
    return true
end

local function normalizeControlArrays()
    norm = {
        btnSource         = indexedControls(controls.btnSource, 6),
        btnDestination    = indexedControls(controls.btnDestination, 5),
        ledSourceRouted   = indexedControls(controls.ledSourceRouted, 4),
        ledSignalPresence = indexedControls(controls.ledSignalPresence, 5),
        uciButtons        = { [7] = controls.btnNav07, [8] = controls.btnNav08, [9] = controls.btnNav09, [10] = controls.btnNav10 },
    }
    local crc = Controls.compRoomControls
    if crc then
        controls.compRoomControls = isArr(crc) and crc or { crc }
    else
        controls.compRoomControls = nil
    end
end

-------------------[ Status ]-------------------
local function checkStatus()
    for _, v in pairs(components.invalid) do
        if v then
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
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
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
    debugPrint("Connected " .. componentType .. ": " .. name)
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
    debugPrint("Discovering components...")
    local discovered = { extronMatrix = {}, callSync = {}, roomControls = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.extronMatrix then
            table.insert(discovered.extronMatrix, comp.Name)
            debugPrint("Discovered Extron DXP: " .. comp.Name)
        elseif comp.Type == componentTypes.callSync then
            table.insert(discovered.callSync, comp.Name)
            debugPrint("Discovered CallSync: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(discovered.roomControls, comp.Name)
            debugPrint("Discovered Room Controls: " .. comp.Name)
        end
    end
    local total = #discovered.extronMatrix + #discovered.callSync + #discovered.roomControls
    debugPrint("Component discovery complete - " .. total .. " components found")
    return discovered
end

local function getSelectedSource()
    for srcIdx = 1, 6 do
        local btn = norm.btnSource and norm.btnSource[srcIdx]
        if btn and btn.Boolean then return sourceButtonToInput[srcIdx] end
    end
    return nil
end

local function updateSourceText()
    setProp(controls.txtSource, "String", sourceNames[getSelectedSource()] or "No Source")
end

--- Keep txtSource / btnSource aligned with a matrix input index (1–4 or 0 = No Source).
local function syncSourceButtonsToInput(input)
    if input == nil then updateSourceText(); return end
    local targetIdx = inputToSourceButton[input]
    if not targetIdx then updateSourceText(); return end
    for idx = 1, 6 do
        local btn = norm.btnSource and norm.btnSource[idx]
        if btn then setProp(btn, "Boolean", idx == targetIdx) end
    end
    updateSourceText()
end

--- Combined mode routes both outputs to the same source; keep btnSource/txtSource aligned with that input.
local function syncSourceUIFromCombinedLayout(selectedInput)
    if not isCombinedLayout() then return end
    if not selectedInput or selectedInput == inputs.NoSource then updateSourceText(); return end
    syncSourceButtonsToInput(selectedInput)
    debugPrint("Source UI → " .. (sourceNames[selectedInput] or tostring(selectedInput)) .. " (combined layout)")
end

local function inputBelongsToRoomA(input)
    return input == inputs.LaptopRmA or input == inputs.TeamsPCRmA
end

local function inputBelongsToRoomB(input)
    return input == inputs.LaptopRmB or input == inputs.TeamsPCRmB
end

--- Which room indices need to be on for auto-switch given matrix input (respects roomLayoutMode).
local function roomsToEnsurePoweredForSource(input)
    if isCombinedLayout() then
        return { 1, 2 }
    end
    if inputBelongsToRoomA(input) then return { 1 } end
    if inputBelongsToRoomB(input) then return { 2 } end
    return {}
end

local function expectedInputOnOutput(output)
    if isCombinedLayout() then
        if outputInRoomA[output] or outputInRoomB[output] then
            local sel = getSelectedSource()
            return (sel and sel ~= inputs.NoSource) and sel or 0
        end
        return 0
    end
    local expA, expB = state.lastSeparatedSourceA, state.lastSeparatedSourceB
    if outputInRoomA[output] then
        if expA and expA ~= inputs.NoSource and inputBelongsToRoomA(expA) then return expA end
        return 0
    end
    if outputInRoomB[output] then
        if expB and expB ~= inputs.NoSource and inputBelongsToRoomB(expB) then return expB end
        return 0
    end
    return 0
end

local function outputAllowedForSource(out, selected)
    if isCombinedLayout() then return true end
    if inputBelongsToRoomA(selected) then return outputInRoomA[out] or false end
    if inputBelongsToRoomB(selected) then return outputInRoomB[out] or false end
    return false
end

local function updateDestinationFeedback()
    if not components.extronMatrix then return end
    for idx = 1, 4 do
        local currentInput = tonumber(components.extronMatrix['output.' .. idx].String) or 0
        local expect = expectedInputOnOutput(idx)
        local isRouted = (currentInput == expect)
        local led = norm.ledSourceRouted and norm.ledSourceRouted[idx]
        if led then setProp(led, "Boolean", isRouted) end
    end
end

local function updateDestinationText()
    if not components.extronMatrix then return end
    local destNames = { [1] = "Room A", [2] = "Room B", [3] = "Out 3", [4] = "Out 4" }
    local routes, count = {}, 0
    for output = 1, 4 do
        local currentInput = tonumber(components.extronMatrix['output.' .. output].String) or 0
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

local function refreshDestinationUI()
    updateDestinationFeedback()
    updateDestinationText()
end

local function onExtronOutputChange()
    refreshDestinationUI()
end

local extronOutputControls = { "output.1", "output.2", "output.3", "output.4" }

local function setExtronMatrixComponent()
    local extronEventMap = {}
    for _, ctrlName in ipairs(extronOutputControls) do
        extronEventMap[ctrlName] = onExtronOutputChange
    end
    setComponentByType(controls.compExtronDXP, "Extron DXP Matrix", "extronMatrix", extronEventMap)
end

-------------------[ Routing ]-------------------
local function setRoute(input, output, source, skipFeedback)
    if not components.extronMatrix then return end
    setProp(components.extronMatrix['output.' .. output], "String", tostring(input))
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    if not skipFeedback then refreshDestinationUI() end
end

local function clearRoute(output, skipFeedback)
    if not components.extronMatrix then return end
    setProp(components.extronMatrix['output.' .. output], "String", "0")
    debugPrint("Cleared Output " .. output)
    if not skipFeedback then refreshDestinationUI() end
end

local function readRoomLayoutMode(comp)
    if not comp then return 1 end
    for idx = 1, 3 do
        local btn = comp["btnRoomState " .. idx]
        if btn and btn.Boolean then return idx end
    end
    return 1
end

local function syncRoomBFromRoomA()
    applyRoutesForSource(getSelectedSource(), "syncRoomBFromRoomA", false)
end

local function applyRoutesForSource(selected, source, skipFeedback, outputs)
    if not components.extronMatrix then return end
    local skip = skipFeedback == true
    local function finishRoutingUI()
        if skip then return end
        refreshDestinationUI()
    end
    if isCombinedLayout() then
        if selected == nil or selected == inputs.NoSource then
            for _, out in ipairs(combinedOutputsInUse) do clearRoute(out, true) end
        else
            local targets = outputs or combinedOutputsInUse
            for _, out in ipairs(targets) do
                setRoute(selected, out, source, true)
            end
        end
        syncSourceUIFromCombinedLayout(selected)
        finishRoutingUI()
        return
    end
    if selected == nil or selected == inputs.NoSource then
        for _, out in ipairs(combinedOutputsInUse) do clearRoute(out, true) end
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = nil, nil
        finishRoutingUI()
        return
    end
    if inputBelongsToRoomA(selected) then
        state.lastSeparatedSourceA = selected
        local targets = outputs or routingConfig.outputsForRoomA
        for _, out in ipairs(targets) do
            if outputInRoomA[out] then
                setRoute(selected, out, source, true)
            end
        end
    elseif inputBelongsToRoomB(selected) then
        state.lastSeparatedSourceB = selected
        local targets = outputs or routingConfig.outputsForRoomB
        for _, out in ipairs(targets) do
            if outputInRoomB[out] then
                setRoute(selected, out, source, true)
            end
        end
    else
        for _, out in ipairs(combinedOutputsInUse) do clearRoute(out, true) end
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = nil, nil
    end
    finishRoutingUI()
end

local function setDivisibleSpaceControlsComponent()
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if not ok or not comp then
        debugPrint("DivisibleSpaceControls not found (feature disabled)")
        components.divisibleSpaceControls = nil
        state.roomLayoutMode = 1
        return
    end
    components.divisibleSpaceControls = comp
    debugPrint("DivisibleSpaceControls connected")

    local layoutLabels = { "Separated (O1→RmA PC, O2→RmB PC)", "Combined (Room A UI / same source both)", "Combined (Room B UI / same source both)" }
    local bound = 0
    for idx = 1, 3 do
        local btn = comp["btnRoomState " .. idx]
        if btn then
            bind(btn, function(ctl)
                if not ctl.Boolean then return end
                state.roomLayoutMode = idx
                debugPrint("Room layout → " .. (layoutLabels[idx] or ("mode " .. idx)) .. " (Source: Room Combiner)")
                applyRoutesForSource(getSelectedSource(), "Room Combiner", false)
            end)
            bound = bound + 1
        end
    end
    if bound > 0 then
        state.roomLayoutMode = readRoomLayoutMode(comp)
        debugPrint("Initial room layout: " .. (layoutLabels[state.roomLayoutMode] or tostring(state.roomLayoutMode)) .. " (" .. bound .. " btnRoomState handler(s))")
    else
        debugPrint("Warning: no btnRoomState 1–3 on compDivisibleSpaceControls")
    end
end

local function setSource(input, source)
    if not components.extronMatrix then return end
    local src = source or "System"
    applyRoutesForSource(input, src, true)
    if not isCombinedLayout() and input ~= nil then
        syncSourceButtonsToInput(input)
    end
    refreshDestinationUI()
end

-------------------[ Auto-Switch ]-------------------
local function checkAutoSwitch()
    for _, source in ipairs(sourcePriority) do
        if source.checkFunc() then
            local roomIdxs = roomsToEnsurePoweredForSource(source.input)
            for _, idx in ipairs(roomIdxs) do
                local comp = components.roomControls[idx]
                if comp and comp["btnSystemOnOff"] and comp["ledSystemPower"] and not comp["ledSystemPower"].Boolean then
                    debugPrint("Powering on Room " .. (idx == 1 and "A" or "B") .. " for " .. source.name)
                    setProp(comp["btnSystemOnOff"], "Boolean", true)
                end
            end
            debugPrint("Auto-switching to " .. source.name)
            setSource(source.input, "Auto-Switch")
            return
        end
    end
end

local function setCallSyncComponent()
    setComponentByType(controls.compCallSync, "CallSync", "callSync",
        { ["off.hook"] = function() checkAutoSwitch() end })
end

local roomControlLedNames = { "ledSystemPower", "ledSystemWarming", "ledSystemCooling" }

local function setRoomControlsAtIndex(idx)
    local selCtrl = controls.compRoomControls and controls.compRoomControls[idx]
    local roomLabel = (idx == 1) and "RmA" or "RmB"
    local componentType = "Room Controls " .. roomLabel
    local oldComp = components.roomControls[idx]
    if oldComp then
        cleanupComponentHandlers(oldComp, roomControlLedNames, function(msg) debugPrint("[" .. componentType .. "] " .. msg) end)
    end
    components.roomControls[idx] = setComponent(selCtrl, componentType, nil)
    local comp = components.roomControls[idx]
    if not comp then return end
    if comp["ledSystemPower"] then
        bind(comp["ledSystemPower"], function(ctl)
            if idx == 1 then state.powerRoomA = ctl.Boolean else state.powerRoomB = ctl.Boolean end
            debugPrint("Room " .. roomLabel .. " system power " .. (ctl.Boolean and "ON" or "OFF"))
            if ctl.Boolean then checkAutoSwitch() end
        end)
    end
    if comp["ledSystemWarming"] then
        bind(comp["ledSystemWarming"], function(ctl)
            if idx == 1 then state.warmingRoomA = ctl.Boolean else state.warmingRoomB = ctl.Boolean end
            debugPrint("Room " .. roomLabel .. " warming " .. (ctl.Boolean and "ON" or "OFF"))
            local powered = (idx == 1) and state.powerRoomA or state.powerRoomB
            if not ctl.Boolean and powered then checkAutoSwitch() end
        end)
    end
    if comp["ledSystemCooling"] then
        bind(comp["ledSystemCooling"], function(ctl)
            if idx == 1 then state.coolingRoomA = ctl.Boolean else state.coolingRoomB = ctl.Boolean end
            debugPrint("Room " .. roomLabel .. " cooling " .. (ctl.Boolean and "ON" or "OFF"))
            local powered = (idx == 1) and state.powerRoomA or state.powerRoomB
            if not ctl.Boolean and not powered then
                Timer.CallAfter(function()
                    debugPrint("Power-off settle complete (Room " .. roomLabel .. "), checking priority sources")
                    checkAutoSwitch()
                end, 2)
            end
        end)
    end
    debugPrint("Registered power/warming/cooling handlers for " .. componentType)
end

local function setRoomControlsComponent()
    if not controls.compRoomControls then return end
    for idx = 1, #controls.compRoomControls do
        setRoomControlsAtIndex(idx)
    end
end

local function setupComponentSelectors(discovered)
    local function setup(ctrl, names, setMethod, componentType, slotIdx)
        if not ctrl then return end
        local choices = { clearString }
        for _, name in ipairs(names) do table.insert(choices, name) end
        ctrl.Choices = choices
        bind(ctrl, function()
            debugPrint(componentType .. " selection changed to: " .. ctrl.String)
            setMethod()
        end)
        if #names > 0 and (ctrl.String == "" or not ctrl.String) then
            local pick = names[1]
            if slotIdx == 2 and #names >= 2 then pick = names[2] end
            ctrl.String = pick
            debugPrint("Auto-selected " .. componentType .. ": " .. pick)
        end
        debugPrint("Registered event handler for " .. componentType .. " selector")
    end
    setup(controls.compExtronDXP, discovered.extronMatrix, setExtronMatrixComponent, "Extron DXP Matrix")
    setup(controls.compCallSync, discovered.callSync, setCallSyncComponent, "CallSync")
    if controls.compRoomControls and isArr(controls.compRoomControls) then
        for idx = 1, #controls.compRoomControls do
            setup(controls.compRoomControls[idx], discovered.roomControls, setRoomControlsComponent,
                "Room Controls [" .. idx .. "]", idx)
        end
    end
end

-------------------[ UCI Integration ]-------------------
local function setUCIController(controller)
    if not controller then return end
    uci.controller = controller
    debugPrint("UCI Controller reference set")
end

local function triggerUCILayer(layer)
    local btnNav = norm.uciButtons and norm.uciButtons[layer]
    if not btnNav then debugPrint("Warning: btnNav for layer " .. layer .. " not found"); return false end
    local ok, err = pcall(function() btnNav:Trigger() end)
    if ok then debugPrint("Triggered UCI layer " .. layer .. " via btnNav" .. layer); return true end
    debugPrint("Error triggering btnNav" .. layer .. ": " .. tostring(err))
    return false
end

local function enableUCIIntegration()
    uci.enabled = true
    debugPrint("UCI Integration enabled")
end

local function disableUCIIntegration()
    uci.enabled = false
    debugPrint("UCI Integration invisible")
end

local function onUCILayerChange(info)
    if not uci.enabled then return end
    debugPrint("UCI Layer changed: " .. tostring(info.previousLayer) .. " → " .. tostring(info.currentLayer) .. " (" .. info.layerName .. ")")
    if uciLayerToInput[info.currentLayer] then
        setSource(uciLayerToInput[info.currentLayer], "UCI Layer " .. info.currentLayer)
    end
end

-------------------[ Event Registration ]-------------------
local function clearOtherSourceButtons(keepIdx)
    for srcIdx = 1, 6 do
        if srcIdx ~= keepIdx then
            local other = norm.btnSource and norm.btnSource[srcIdx]
            if other then setProp(other, "Boolean", false) end
        end
    end
end

local function registerEvents()
    local sourceCount = 0
    for idx = 1, 6 do
        local btn = norm.btnSource and norm.btnSource[idx]
        if btn then
            bind(btn, function(ctl)
                if not ctl.Boolean then return end
                clearOtherSourceButtons(idx)
                debugPrint("Source button " .. idx .. " pressed")
                applyRoutesForSource(getSelectedSource(), "Source Button", true)
                updateSourceText()
                refreshDestinationUI()
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
                if idx == 5 or isCombinedLayout() then
                    applyRoutesForSource(selected, "User Button", true)
                elseif not outputAllowedForSource(idx, selected) then
                    debugPrint("Destination " .. idx .. " not valid for current source (separated mode)")
                else
                    setRoute(selected, idx, "User Button", true)
                end
                refreshDestinationUI()
            end)
            destCount = destCount + 1
        end
    end
    debugPrint("Registered " .. destCount .. " destination button handlers")

    -- Do not bind btnNav07–10 here: UCIController owns those controls. Binding here overwrites UCI
    -- EventHandlers (one handler per control). Routing follows UCI via Notifications → onUCILayerChange.

    local sigCount = bindArray(norm.ledSignalPresence, function(i, ctl) checkAutoSwitch() end)
    debugPrint("Registered " .. sigCount .. " signal presence handlers for auto-switch")
end

-------------------[ Initialization ]-------------------
local function init()
    debugPrint("=== Initialization Started ===")
    debugPrint("Configuration: roomName=" .. roomName .. ", debugging=" .. tostring(debugging) .. ", uciEnabled=" .. tostring(uci.enabled))

    local discovered = discoverComponents()
    setupComponentSelectors(discovered)
    setExtronMatrixComponent()
    setCallSyncComponent()
    setDivisibleSpaceControlsComponent()
    setRoomControlsComponent()
    registerEvents()

    if uci.matrixNotifySubId then
        pcall(function() Notifications.Unsubscribe(uci.matrixNotifySubId) end)
        uci.matrixNotifySubId = nil
    end
    local subOk, subErr = pcall(function()
        uci.matrixNotifySubId = Notifications.Subscribe(uciLayerNotifyMatrix, function(name, info)
            if type(info) ~= "table" then
                debugPrint("UCI layer notify ignored (expected table, got " .. type(info) .. ")")
                return
            end
            debugPrint("UCI layer notify received name=" .. tostring(name) .. " currentLayer=" .. tostring(info.currentLayer))
            onUCILayerChange(info)
        end)
    end)
    if subOk and uci.matrixNotifySubId then
        debugPrint("Subscribed to UCI layer notifications (" .. uciLayerNotifyMatrix .. ")")
    else
        debugPrint("UCI layer notification subscribe failed: " .. tostring(subErr))
    end

    local powerKeys = { "powerRoomA", "powerRoomB" }
    local warmingKeys = { "warmingRoomA", "warmingRoomB" }
    for idx = 1, 2 do
        local comp = components.roomControls[idx]
        if comp and comp["ledSystemPower"] then
            state[powerKeys[idx]] = comp["ledSystemPower"].Boolean
        end
        if comp and comp["ledSystemWarming"] then
            state[warmingKeys[idx]] = comp["ledSystemWarming"].Boolean
        end
    end

    if isCombinedLayout() then
        applyRoutesForSource(getSelectedSource(), "Init", false)
    else
        setRoute(inputs.LaptopRmA, 1, "Init", true)
        setRoute(inputs.LaptopRmB, 2, "Init", true)
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = inputs.LaptopRmA, inputs.LaptopRmB
        refreshDestinationUI()
    end

    debugPrint("=== Initialization Complete ===")
    debugPrint("Ready for operation")
end

-------------------[ Cleanup ]-------------------
local function cleanup()
    if uci.matrixNotifySubId then
        pcall(function() Notifications.Unsubscribe(uci.matrixNotifySubId) end)
        uci.matrixNotifySubId = nil
    end
    uci.controller = nil
    debugPrint("Cleanup completed")
end

-------------------[ Public API ]-------------------
-- Exposed for external scripts (room controllers, UCI scripts, etc.)
MatrixController = {
    setUCIController       = setUCIController,
    triggerUCILayer        = triggerUCILayer,
    onUCILayerChange       = onUCILayerChange,
    enableUCIIntegration   = enableUCIIntegration,
    disableUCIIntegration  = disableUCIIntegration,
    setRoute               = setRoute,
    setSource              = setSource,
    clearRoute             = clearRoute,
    checkAutoSwitch        = checkAutoSwitch,
    syncRoomBFromRoomA     = syncRoomBFromRoomA,
    applyRoutesForSource   = applyRoutesForSource,
    cleanup                = cleanup,
}

-------------------[ Start ]-------------------
local ok, err = pcall(function()
    print("Initializing controller for " .. roomName .. "...")
    if not validateControls() then error("Control validation failed") end
    normalizeControlArrays()
    init()
end)
if ok then
    print("✓ Controller initialized for " .. roomName)
else
    print("✗ ERROR: Initialization failed: " .. tostring(err))
    if controls and controls.txtStatus then
        setProp(controls.txtStatus, "String", "INIT FAILED")
        setProp(controls.txtStatus, "Value", 2)
    end
end
