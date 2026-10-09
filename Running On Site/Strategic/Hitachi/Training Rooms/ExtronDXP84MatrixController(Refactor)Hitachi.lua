--[[
  Extron DXP Matrix Routing Controller — Hitachi Training Rooms
  Author: Nikolas Smith, Q-SYS
  Date: 2026-04-09
  Version: 6.0
  Firmware Req: 10.2.0

  Room-combine matrix follows compDivisibleSpaceControls btnRoomState 1–3 (interlock). Two
  compRoomControls selectors (RmA/RmB) track per-room power; auto-switch only asserts power on
  room(s) allowed by roomLayoutMode. UCI publishes layer changes via Notifications
  (uciLayerNotifyMatrix); do not bind btnNav07–10 here.

]]--

-------------------[ Configuration ]-------------------

componentTypes = {
    extronMatrix = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    callSync     = "call_sync",
    roomControls = "device_controller_script",
}

inputs = {
    LaptopRmA = 1, LaptopRmB = 2, TeamsPCRmA = 3, TeamsPCRmB = 4, NoSource = 0,
}

uciLayerToInput = { [7] = inputs.TeamsPCRmA, [8] = inputs.TeamsPCRmB, [9] = inputs.LaptopRmA, [10] = inputs.LaptopRmB }

-- Must match UCIController(DivisibleSpace): cross-script handoff.
uciLayerNotifyMatrix = "HitachiTraining_UCIMatrixLayer"

sourceButtonToInput = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 0 }
inputToSourceButton = {}
for btnIdx, inputNum in pairs(sourceButtonToInput) do
    inputToSourceButton[inputNum] = btnIdx
end

sourceNames = {
    [0] = "No Source", [1] = "Laptop RmA", [2] = "Laptop RmB", [3] = "TeamsPC RmA", [4] = "TeamsPC RmB",
}

routingConfig = {
    outputsForRoomA = { 1 },
    outputsForRoomB = { 2 },
}

outputInRoomA = {}
outputInRoomB = {}
for _, out in ipairs(routingConfig.outputsForRoomA) do outputInRoomA[out] = true end
for _, out in ipairs(routingConfig.outputsForRoomB) do outputInRoomB[out] = true end

combinedOutputsInUse = {}
for _, outList in ipairs({ routingConfig.outputsForRoomA, routingConfig.outputsForRoomB }) do
    for _, out in ipairs(outList) do table.insert(combinedOutputsInUse, out) end
end

extronOutputControls = { "output.1", "output.2", "output.3", "output.4" }
roomControlLedNames = { "ledSystemPower", "ledSystemWarming", "ledSystemCooling" }

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compExtronMatrix = nil
compCallSync = nil
compRoomControls = {}
compDivisibleSpaceControls = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"

roomName = (function()
    local ok, name = pcall(function()
        local rn = Controls.roomName
        return (rn and rn.String ~= "" and rn.String) or nil
    end)
    return (ok and name and "[" .. name .. "]") or "[Extron DXP]"
end)()

powerRoomA = false
powerRoomB = false
warmingRoomA = true
warmingRoomB = true
coolingRoomA = false
coolingRoomB = false
roomLayoutMode = 1
lastSeparatedSourceA = nil
lastSeparatedSourceB = nil

uciController = nil
uciEnabled = true
uciMatrixNotifySubId = nil

sourcePriority = {
    { name = "Teams PCRmA", input = inputs.TeamsPCRmA, checkFunc = function()
        local offHook = compCallSync and compCallSync["off.hook"] and compCallSync["off.hook"].Boolean
        local signalLed = Controls.ledSignalPresence and Controls.ledSignalPresence[5]
        return offHook or (signalLed and signalLed.Boolean)
    end },
    { name = "LaptopRmA", input = inputs.LaptopRmA, checkFunc = function()
        local led = Controls.ledSignalPresence and Controls.ledSignalPresence[1]
        return led and led.Boolean
    end },
    { name = "LaptopRmB", input = inputs.LaptopRmB, checkFunc = function()
        local led = Controls.ledSignalPresence and Controls.ledSignalPresence[2]
        return led and led.Boolean
    end },
    { name = "Teams PCRmA (USB)", input = inputs.TeamsPCRmA, checkFunc = function()
        local led = Controls.ledSignalPresence and Controls.ledSignalPresence[3]
        return led and led.Boolean
    end },
    { name = "Teams PCRmB (USB)", input = inputs.TeamsPCRmB, checkFunc = function()
        local led = Controls.ledSignalPresence and Controls.ledSignalPresence[4]
        return led and led.Boolean
    end },
}

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
    if stateDebug then print(roomName .. " " .. str) end
end

function isControlArray(t)
    return type(t) == "table" and t[1] ~= nil
end

function ctlAt(ctrl, idx)
    if not ctrl then return nil end
    return ctrl[idx]
end

function roomControlsSelectors()
    local crc = Controls.compRoomControls
    if not crc then return nil end
    return isControlArray(crc) and crc or { crc }
end

-------------------[ Status ]-------------------

function checkStatus()
    for _, v in pairs(compInvalid) do
        if v then
            if Controls.txtStatus then
                Controls.txtStatus.String = "Invalid Components"
                Controls.txtStatus.Value = 1
            end
            return
        end
    end
    if Controls.txtStatus then
        Controls.txtStatus.String = "OK"
        Controls.txtStatus.Value = 0
    end
end

function setCompInvalid(componentType)
    compInvalid[componentType] = true
    checkStatus()
end

function setCompValid(componentType)
    compInvalid[componentType] = false
    checkStatus()
end

function setComp(ctl, componentType)
    if not ctl then
        debugMsg("Control for " .. componentType .. " is nil!")
        setCompInvalid(componentType)
        return nil
    end
    local name = ctl.String
    if not name or name == "" then
        ctl.Color = "white"
        setCompValid(componentType)
        debugMsg("No " .. componentType .. " component selected")
        return nil
    end
    if name == strClear then
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        debugMsg("No " .. componentType .. " component selected")
        return nil
    end
    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        debugMsg("ERROR: " .. componentType .. " component '" .. name .. "' is invalid")
        return nil
    end
    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("Connected " .. componentType .. ": " .. name)
    return comp
end

function cleanupComponentHandlers(comp, controlNames)
    if not comp or not controlNames then return end
    for _, name in ipairs(controlNames) do
        if comp[name] then comp[name].EventHandler = nil end
    end
end

-------------------[ Discovery ]-------------------

function fillSelectorChoices(ctl, names, label, slotIdx)
    if not ctl then return end
    local choices = { strClear }
    for _, n in ipairs(names) do table.insert(choices, n) end
    ctl.Choices = choices
    if #names > 0 and (ctl.String == "" or not ctl.String) then
        local pick = names[1]
        if slotIdx == 2 and #names >= 2 then pick = names[2] end
        ctl.String = pick
        debugMsg("Auto-selected " .. label .. ": " .. pick)
    end
end

function getComponentNames()
    debugMsg("Discovering components...")
    local discovered = { extronMatrix = {}, callSync = {}, roomControls = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.extronMatrix then
            table.insert(discovered.extronMatrix, comp.Name)
            debugMsg("Discovered Extron DXP: " .. comp.Name)
        elseif comp.Type == componentTypes.callSync then
            table.insert(discovered.callSync, comp.Name)
            debugMsg("Discovered CallSync: " .. comp.Name)
        elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(discovered.roomControls, comp.Name)
            debugMsg("Discovered Room Controls: " .. comp.Name)
        end
    end
    local total = #discovered.extronMatrix + #discovered.callSync + #discovered.roomControls
    debugMsg("Component discovery complete - " .. total .. " components found")

    fillSelectorChoices(Controls.compExtronDXP, discovered.extronMatrix, "Extron DXP Matrix")
    fillSelectorChoices(Controls.compCallSync, discovered.callSync, "CallSync")
    local selectors = roomControlsSelectors()
    if selectors then
        for idx = 1, #selectors do
            fillSelectorChoices(selectors[idx], discovered.roomControls, "Room Controls [" .. idx .. "]", idx)
        end
    end
    return discovered
end

-------------------[ Routing ]-------------------

function isCombinedLayout()
    return roomLayoutMode == 2 or roomLayoutMode == 3
end

function getSelectedSource()
    for srcIdx = 1, 6 do
        local btn = ctlAt(Controls.btnSource, srcIdx)
        if btn and btn.Boolean then return sourceButtonToInput[srcIdx] end
    end
    return nil
end

function updateSourceText()
    if not Controls.txtSource then return end
    Controls.txtSource.String = sourceNames[getSelectedSource()] or "No Source"
end

function syncSourceButtonsToInput(input)
    if input == nil then updateSourceText(); return end
    local targetIdx = inputToSourceButton[input]
    if not targetIdx then updateSourceText(); return end
    for idx = 1, 6 do
        local btn = ctlAt(Controls.btnSource, idx)
        if btn then btn.Boolean = (idx == targetIdx) end
    end
    updateSourceText()
end

function syncSourceUIFromCombinedLayout(selectedInput)
    if not isCombinedLayout() then return end
    if not selectedInput or selectedInput == inputs.NoSource then updateSourceText(); return end
    syncSourceButtonsToInput(selectedInput)
    debugMsg("Source UI → " .. (sourceNames[selectedInput] or tostring(selectedInput)) .. " (combined layout)")
end

function inputBelongsToRoomA(input)
    return input == inputs.LaptopRmA or input == inputs.TeamsPCRmA
end

function inputBelongsToRoomB(input)
    return input == inputs.LaptopRmB or input == inputs.TeamsPCRmB
end

function roomsToEnsurePoweredForSource(input)
    if isCombinedLayout() then return { 1, 2 } end
    if inputBelongsToRoomA(input) then return { 1 } end
    if inputBelongsToRoomB(input) then return { 2 } end
    return {}
end

function expectedInputOnOutput(output)
    if isCombinedLayout() then
        if outputInRoomA[output] or outputInRoomB[output] then
            local sel = getSelectedSource()
            return (sel and sel ~= inputs.NoSource) and sel or 0
        end
        return 0
    end
    if outputInRoomA[output] then
        if lastSeparatedSourceA and lastSeparatedSourceA ~= inputs.NoSource and inputBelongsToRoomA(lastSeparatedSourceA) then
            return lastSeparatedSourceA
        end
        return 0
    end
    if outputInRoomB[output] then
        if lastSeparatedSourceB and lastSeparatedSourceB ~= inputs.NoSource and inputBelongsToRoomB(lastSeparatedSourceB) then
            return lastSeparatedSourceB
        end
        return 0
    end
    return 0
end

function outputAllowedForSource(out, selected)
    if isCombinedLayout() then return true end
    if inputBelongsToRoomA(selected) then return outputInRoomA[out] or false end
    if inputBelongsToRoomB(selected) then return outputInRoomB[out] or false end
    return false
end

function updateDestinationFeedback()
    if not compExtronMatrix then return end
    for idx = 1, 4 do
        local currentInput = tonumber(compExtronMatrix["output." .. idx].String) or 0
        local expect = expectedInputOnOutput(idx)
        local led = ctlAt(Controls.ledSourceRouted, idx)
        if led then led.Boolean = (currentInput == expect) end
    end
end

function updateDestinationText()
    if not compExtronMatrix or not Controls.txtStatus then return end
    local destNames = { [1] = "Room A", [2] = "Room B", [3] = "Out 3", [4] = "Out 4" }
    local routes, count = {}, 0
    for output = 1, 4 do
        local currentInput = tonumber(compExtronMatrix["output." .. output].String) or 0
        if currentInput > 0 then
            count = count + 1
            table.insert(routes, (sourceNames[currentInput] or "Unknown") .. " → " .. destNames[output])
        end
    end
    if count == 0 then
        Controls.txtStatus.String = ""
    elseif count == 4 then
        Controls.txtStatus.String = "All Displays Active"
        Timer.CallAfter(function() Controls.txtStatus.String = "" end, 3)
    else
        Controls.txtStatus.String = table.concat(routes, ", ")
    end
end

function refreshDestinationUI()
    updateDestinationFeedback()
    updateDestinationText()
end

function onExtronOutputChange()
    refreshDestinationUI()
end

function setRoute(input, output, source, skipFeedback)
    if not compExtronMatrix then return end
    compExtronMatrix["output." .. output].String = tostring(input)
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    debugMsg("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    if not skipFeedback then refreshDestinationUI() end
end

function clearRoute(output, skipFeedback)
    if not compExtronMatrix then return end
    compExtronMatrix["output." .. output].String = "0"
    debugMsg("Cleared Output " .. output)
    if not skipFeedback then refreshDestinationUI() end
end

function readRoomLayoutMode(comp)
    if not comp then return 1 end
    for idx = 1, 3 do
        local btn = comp["btnRoomState " .. idx]
        if btn and btn.Boolean then return idx end
    end
    return 1
end

function applyRoutesForSource(selected, source, skipFeedback, outputs)
    if not compExtronMatrix then return end
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
            for _, out in ipairs(targets) do setRoute(selected, out, source, true) end
        end
        syncSourceUIFromCombinedLayout(selected)
        finishRoutingUI()
        return
    end
    if selected == nil or selected == inputs.NoSource then
        for _, out in ipairs(combinedOutputsInUse) do clearRoute(out, true) end
        lastSeparatedSourceA, lastSeparatedSourceB = nil, nil
        finishRoutingUI()
        return
    end
    if inputBelongsToRoomA(selected) then
        lastSeparatedSourceA = selected
        local targets = outputs or routingConfig.outputsForRoomA
        for _, out in ipairs(targets) do
            if outputInRoomA[out] then setRoute(selected, out, source, true) end
        end
    elseif inputBelongsToRoomB(selected) then
        lastSeparatedSourceB = selected
        local targets = outputs or routingConfig.outputsForRoomB
        for _, out in ipairs(targets) do
            if outputInRoomB[out] then setRoute(selected, out, source, true) end
        end
    else
        for _, out in ipairs(combinedOutputsInUse) do clearRoute(out, true) end
        lastSeparatedSourceA, lastSeparatedSourceB = nil, nil
    end
    finishRoutingUI()
end

function syncRoomBFromRoomA()
    applyRoutesForSource(getSelectedSource(), "syncRoomBFromRoomA", false)
end

function setSource(input, source)
    if not compExtronMatrix then return end
    local src = source or "System"
    applyRoutesForSource(input, src, true)
    if not isCombinedLayout() and input ~= nil then syncSourceButtonsToInput(input) end
    refreshDestinationUI()
end

function clearOtherSourceButtons(keepIdx)
    for srcIdx = 1, 6 do
        if srcIdx ~= keepIdx then
            local other = ctlAt(Controls.btnSource, srcIdx)
            if other then other.Boolean = false end
        end
    end
end

-------------------[ Auto-Switch ]-------------------

function checkAutoSwitch()
    for _, source in ipairs(sourcePriority) do
        if source.checkFunc() then
            local roomIdxs = roomsToEnsurePoweredForSource(source.input)
            for _, idx in ipairs(roomIdxs) do
                local comp = compRoomControls[idx]
                if comp and comp["btnSystemOnOff"] and comp["ledSystemPower"] and not comp["ledSystemPower"].Boolean then
                    debugMsg("Powering on Room " .. (idx == 1 and "A" or "B") .. " for " .. source.name)
                    comp["btnSystemOnOff"].Boolean = true
                end
            end
            debugMsg("Auto-switching to " .. source.name)
            setSource(source.input, "Auto-Switch")
            return
        end
    end
end

-------------------[ Components ]-------------------

function setcompExtronDXP()
    cleanupComponentHandlers(compExtronMatrix, extronOutputControls)
    compExtronMatrix = setComp(Controls.compExtronDXP, "Extron DXP Matrix")
    if not compExtronMatrix then return end
    local handlerCount = 0
    for _, ctrlName in ipairs(extronOutputControls) do
        if compExtronMatrix[ctrlName] then
            compExtronMatrix[ctrlName].EventHandler = onExtronOutputChange
            handlerCount = handlerCount + 1
        end
    end
    debugMsg("Registered " .. handlerCount .. " output handler(s) for Extron DXP Matrix")
end

function setcompCallSync()
    cleanupComponentHandlers(compCallSync, { "off.hook" })
    compCallSync = setComp(Controls.compCallSync, "CallSync")
    if compCallSync and compCallSync["off.hook"] then
        compCallSync["off.hook"].EventHandler = function() checkAutoSwitch() end
        debugMsg("Registered off.hook handler for CallSync")
    end
end

function setRoomControlsAtIndex(idx)
    local selectors = roomControlsSelectors()
    local selCtrl = selectors and selectors[idx]
    local roomLabel = (idx == 1) and "RmA" or "RmB"
    local componentType = "Room Controls " .. roomLabel
    cleanupComponentHandlers(compRoomControls[idx], roomControlLedNames)
    compRoomControls[idx] = setComp(selCtrl, componentType)
    local comp = compRoomControls[idx]
    if not comp then return end
    if comp["ledSystemPower"] then
        comp["ledSystemPower"].EventHandler = function(ctl)
            if idx == 1 then powerRoomA = ctl.Boolean else powerRoomB = ctl.Boolean end
            debugMsg("Room " .. roomLabel .. " system power " .. (ctl.Boolean and "ON" or "OFF"))
            if ctl.Boolean then checkAutoSwitch() end
        end
    end
    if comp["ledSystemWarming"] then
        comp["ledSystemWarming"].EventHandler = function(ctl)
            if idx == 1 then warmingRoomA = ctl.Boolean else warmingRoomB = ctl.Boolean end
            debugMsg("Room " .. roomLabel .. " warming " .. (ctl.Boolean and "ON" or "OFF"))
            local powered = (idx == 1) and powerRoomA or powerRoomB
            if not ctl.Boolean and powered then checkAutoSwitch() end
        end
    end
    if comp["ledSystemCooling"] then
        comp["ledSystemCooling"].EventHandler = function(ctl)
            if idx == 1 then coolingRoomA = ctl.Boolean else coolingRoomB = ctl.Boolean end
            debugMsg("Room " .. roomLabel .. " cooling " .. (ctl.Boolean and "ON" or "OFF"))
            local powered = (idx == 1) and powerRoomA or powerRoomB
            if not ctl.Boolean and not powered then
                Timer.CallAfter(function()
                    debugMsg("Power-off settle complete (Room " .. roomLabel .. "), checking priority sources")
                    checkAutoSwitch()
                end, 2)
            end
        end
    end
    debugMsg("Registered power/warming/cooling handlers for " .. componentType)
end

function setcompRoomControls()
    local selectors = roomControlsSelectors()
    if not selectors then return end
    for idx = 1, #selectors do setRoomControlsAtIndex(idx) end
end

function setcompDivisibleSpaceControls()
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if not ok or not comp then
        debugMsg("DivisibleSpaceControls not found (feature disabled)")
        compDivisibleSpaceControls = nil
        roomLayoutMode = 1
        return
    end
    compDivisibleSpaceControls = comp
    debugMsg("DivisibleSpaceControls connected")

    local layoutLabels = {
        "Separated (O1→RmA PC, O2→RmB PC)",
        "Combined (Room A UI / same source both)",
        "Combined (Room B UI / same source both)",
    }
    local bound = 0
    for idx = 1, 3 do
        local btn = comp["btnRoomState " .. idx]
        if btn then
            btn.EventHandler = function(ctl)
                if not ctl.Boolean then return end
                roomLayoutMode = idx
                debugMsg("Room layout → " .. (layoutLabels[idx] or ("mode " .. idx)) .. " (Source: Room Combiner)")
                applyRoutesForSource(getSelectedSource(), "Room Combiner", false)
            end
            bound = bound + 1
        end
    end
    if bound > 0 then
        roomLayoutMode = readRoomLayoutMode(comp)
        debugMsg("Initial room layout: " .. (layoutLabels[roomLayoutMode] or tostring(roomLayoutMode)) .. " (" .. bound .. " btnRoomState handler(s))")
    else
        debugMsg("Warning: no btnRoomState 1–3 on compDivisibleSpaceControls")
    end
end

-------------------[ UCI Integration ]-------------------

function setUCIController(controller)
    if not controller then return end
    uciController = controller
    debugMsg("UCI Controller reference set")
end

function triggerUCILayer(layer)
    local navKeys = { [7] = Controls.btnNav07, [8] = Controls.btnNav08, [9] = Controls.btnNav09, [10] = Controls.btnNav10 }
    local btnNav = navKeys[layer]
    if not btnNav then debugMsg("Warning: btnNav for layer " .. layer .. " not found"); return false end
    local ok, err = pcall(function() btnNav:Trigger() end)
    if ok then debugMsg("Triggered UCI layer " .. layer .. " via btnNav" .. layer); return true end
    debugMsg("Error triggering btnNav" .. layer .. ": " .. tostring(err))
    return false
end

function enableUCIIntegration()
    uciEnabled = true
    debugMsg("UCI Integration enabled")
end

function disableUCIIntegration()
    uciEnabled = false
    debugMsg("UCI Integration invisible")
end

function onUCILayerChange(info)
    if not uciEnabled then return end
    debugMsg("UCI Layer changed: " .. tostring(info.previousLayer) .. " → " .. tostring(info.currentLayer) .. " (" .. info.layerName .. ")")
    if uciLayerToInput[info.currentLayer] then
        setSource(uciLayerToInput[info.currentLayer], "UCI Layer " .. info.currentLayer)
    end
end

function subscribeUciLayerNotify()
    if uciMatrixNotifySubId then
        pcall(function() Notifications.Unsubscribe(uciMatrixNotifySubId) end)
        uciMatrixNotifySubId = nil
    end
    local subOk, subErr = pcall(function()
        uciMatrixNotifySubId = Notifications.Subscribe(uciLayerNotifyMatrix, function(name, info)
            if type(info) ~= "table" then
                debugMsg("UCI layer notify ignored (expected table, got " .. type(info) .. ")")
                return
            end
            debugMsg("UCI layer notify received name=" .. tostring(name) .. " currentLayer=" .. tostring(info.currentLayer))
            onUCILayerChange(info)
        end)
    end)
    if subOk and uciMatrixNotifySubId then
        debugMsg("Subscribed to UCI layer notifications (" .. uciLayerNotifyMatrix .. ")")
    else
        debugMsg("UCI layer notification subscribe failed: " .. tostring(subErr))
    end
end

function matrixCleanup()
    if uciMatrixNotifySubId then
        pcall(function() Notifications.Unsubscribe(uciMatrixNotifySubId) end)
        uciMatrixNotifySubId = nil
    end
    uciController = nil
    debugMsg("Cleanup completed")
end

-------------------[ Public API ]-------------------

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
    cleanup                = matrixCleanup,
}

-------------------[ Event Handlers ]-------------------

if Controls.compExtronDXP then
    Controls.compExtronDXP.EventHandler = function(ctl)
        debugMsg("Extron DXP Matrix selection changed to: " .. ctl.String)
        setcompExtronDXP()
    end
end

if Controls.compCallSync then
    Controls.compCallSync.EventHandler = function(ctl)
        debugMsg("CallSync selection changed to: " .. ctl.String)
        setcompCallSync()
    end
end

do
    local selectors = roomControlsSelectors()
    if selectors then
        for idx = 1, #selectors do
            selectors[idx].EventHandler = function(ctl)
                debugMsg("Room Controls [" .. idx .. "] selection changed to: " .. ctl.String)
                setcompRoomControls()
            end
        end
    end
end

for srcIdx = 1, 6 do
    local btn = ctlAt(Controls.btnSource, srcIdx)
    if btn then
        btn.EventHandler = function(ctl)
            if not ctl.Boolean then return end
            clearOtherSourceButtons(srcIdx)
            debugMsg("Source button " .. srcIdx .. " pressed")
            applyRoutesForSource(getSelectedSource(), "Source Button", true)
            updateSourceText()
            refreshDestinationUI()
        end
    end
end

for destIdx = 1, 5 do
    local btn = ctlAt(Controls.btnDestination, destIdx)
    if btn then
        btn.EventHandler = function()
            local selected = getSelectedSource()
            if not selected then return end
            if destIdx == 5 or isCombinedLayout() then
                applyRoutesForSource(selected, "User Button", true)
            elseif not outputAllowedForSource(destIdx, selected) then
                debugMsg("Destination " .. destIdx .. " not valid for current source (separated mode)")
            else
                setRoute(selected, destIdx, "User Button", true)
            end
            refreshDestinationUI()
        end
    end
end

if Controls.ledSignalPresence then
    for sigIdx = 1, 5 do
        local led = ctlAt(Controls.ledSignalPresence, sigIdx)
        if led then
            led.EventHandler = function() checkAutoSwitch() end
        end
    end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")
    debugMsg("Configuration: roomName=" .. roomName .. ", stateDebug=" .. tostring(stateDebug) .. ", uciEnabled=" .. tostring(uciEnabled))

    if not Controls.txtSource then
        print("ERROR: Missing required control: txtSource")
        if Controls.txtStatus then
            Controls.txtStatus.String = "INIT FAILED"
            Controls.txtStatus.Value = 2
        end
        return
    end

    getComponentNames()
    setcompExtronDXP()
    setcompCallSync()
    setcompDivisibleSpaceControls()
    setcompRoomControls()
    subscribeUciLayerNotify()

    for idx = 1, 2 do
        local comp = compRoomControls[idx]
        if comp and comp["ledSystemPower"] then
            if idx == 1 then powerRoomA = comp["ledSystemPower"].Boolean else powerRoomB = comp["ledSystemPower"].Boolean end
        end
        if comp and comp["ledSystemWarming"] then
            if idx == 1 then warmingRoomA = comp["ledSystemWarming"].Boolean else warmingRoomB = comp["ledSystemWarming"].Boolean end
        end
    end

    if isCombinedLayout() then
        applyRoutesForSource(getSelectedSource(), "Init", false)
    else
        setRoute(inputs.LaptopRmA, 1, "Init", true)
        setRoute(inputs.LaptopRmB, 2, "Init", true)
        lastSeparatedSourceA, lastSeparatedSourceB = inputs.LaptopRmA, inputs.LaptopRmB
        refreshDestinationUI()
    end

    debugMsg("=== Initialization Complete ===")
    debugMsg("Ready for operation")
end

funcInit()
