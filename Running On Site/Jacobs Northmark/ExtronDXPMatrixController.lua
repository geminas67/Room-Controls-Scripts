--[[
  Extron DXP Matrix Routing Controller — Jacobs Northmark (divisible space)
  Author: Nikolas Smith, Q-SYS
  Date: 2026-11-02
  Version: 6.2
  Firmware Req: 10.2.0

  Room-combine matrix follows compDivisibleSpaceControls btnRoomState 1–3 (interlock).
  UCI nav: bind btnNav07–10 on both uciControllerRmA/RmB (divided); in combined layout only
  the active room's UCI drives matrix (roomLayoutMode 2/3).

]]--

-------------------[ Configuration ]-------------------

componentTypes = {
    extronMatrix  = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
    uciController = "device_controller_script",
}

compNameMatch = {
    uciController = "^uciControllerRm",
}

inputs = {
    LaptopRmA = 1, LaptopRmB = 2, TeamsPCRmA = 3, TeamsPCRmB = 4, NoSource = 0,
}

-- Maps uciController nav buttons to matrix inputs (kLayer 7–10 in UCIController DivisibleSpace).
uciNavSource = {
    btnNav09 = inputs.LaptopRmA,
    btnNav10 = inputs.LaptopRmB,
}

btnSourceToInput = { [1] = 1, [2] = 2, [3] = 0 }
inputToSourceButton = {}
for btnIdx, inputNum in pairs(btnSourceToInput) do
    inputToSourceButton[inputNum] = btnIdx
end

sourceNames = {
    [0] = "No Source", [1] = "Laptop RmA", [2] = "Laptop RmB", 
}

routingConfig = {
    outputsForRoomA = { 1, 2 },
    outputsForRoomB = { 3, 4 },
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

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compExtronMatrix = nil
compDivisibleSpaceControls = nil
compUCICtls = {}

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

roomLayoutMode = 1
lastSeparatedSourceA = nil
lastSeparatedSourceB = nil

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

function uciControllerSelectors()
    local sel = Controls.compUCIController
    if not sel then return nil end
    return isControlArray(sel) and sel or { sel }
end

-- Divided: both touch panels. Combined mode 2 = Room A UI only; mode 3 = Room B UI only.
function uciNavAllowedForSlot(uciIdx)
    if roomLayoutMode == 1 then return true end
    if roomLayoutMode == 2 then return uciIdx == 1 end
    if roomLayoutMode == 3 then return uciIdx == 2 end
    return true
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
    local discovered = { extronMatrix = {}, uciController = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.extronMatrix then
            table.insert(discovered.extronMatrix, comp.Name)
        elseif comp.Type == componentTypes.uciController and string.match(comp.Name, compNameMatch.uciController) then
            table.insert(discovered.uciController, comp.Name)
        end
    end
    debugMsg("Discovery complete - Extron: " .. #discovered.extronMatrix .. ", UCI: " .. #discovered.uciController)

    fillSelectorChoices(Controls.compExtronDXP, discovered.extronMatrix, "Extron DXP Matrix")
    local uciSelectors = uciControllerSelectors()
    if uciSelectors then
        for idx = 1, #uciSelectors do
            fillSelectorChoices(uciSelectors[idx], discovered.uciController, "UCI Controller [" .. idx .. "]", idx)
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
        if btn and btn.Boolean then return btnSourceToInput[srcIdx] end
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
    local destNames = { [1] = "Room A PC", [2] = "Room A Display", [3] = "Room B PC", [4] = "Room B Display" }
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

function getRoomLayoutMode(comp)
    if not comp then return 1 end
    for idx = 1, 3 do
        local btn = comp["btnRoomState " .. idx]
        if btn and btn.Boolean then return idx end
    end
    return 1
end

function applySourceRoutes(selected, source, skipFeedback, outputs)
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

function syncRmBToRmA()
    applySourceRoutes(getSelectedSource(), "syncRmBToRmA", false)
end

function setSource(input, source)
    if not compExtronMatrix then return end
    local src = source or "System"
    applySourceRoutes(input, src, true)
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
                applySourceRoutes(getSelectedSource(), "Room Combiner", false)
            end
            bound = bound + 1
        end
    end
    if bound > 0 then
        roomLayoutMode = getRoomLayoutMode(comp)
        debugMsg("Initial room layout: " .. (layoutLabels[roomLayoutMode] or tostring(roomLayoutMode)) .. " (" .. bound .. " btnRoomState handler(s))")
    else
        debugMsg("Warning: no btnRoomState 1–3 on compDivisibleSpaceControls")
    end
end

-------------------[ UCI Controller ]-------------------

function cleanupUciNavOnComp(comp)
    if not comp then return end
    for btnName in pairs(uciNavSource) do
        if comp[btnName] then comp[btnName].EventHandler = nil end
    end
end

function bindUciNavOnComp(comp, uciIdx, roomLabel)
    if not comp then return end
    for btnName, inputNum in pairs(uciNavSource) do
        local btn = comp[btnName]
        if btn then
            btn.EventHandler = function(ctl)
                if not ctl.Boolean then return end
                if not uciNavAllowedForSlot(uciIdx) then return end
                debugMsg(roomLabel .. " " .. btnName .. " selected")
                setSource(inputNum, "UCI Nav " .. roomLabel .. ": " .. btnName)
            end
        end
    end
end

function setUCIControllerAtIndex(idx)
    local selectors = uciControllerSelectors()
    local selCtrl = selectors and selectors[idx]
    local roomLabel = (idx == 1) and "RmA" or "RmB"
    local componentType = "UCI Controller " .. roomLabel
    cleanupUciNavOnComp(compUCICtls[idx])
    compUCICtls[idx] = setComp(selCtrl, componentType)
    bindUciNavOnComp(compUCICtls[idx], idx, roomLabel)
end

function setcompUCICtls()
    local selectors = uciControllerSelectors()
    if not selectors then return end
    for idx = 1, #selectors do setUCIControllerAtIndex(idx) end
end

-------------------[ Event Handlers ]-------------------

if Controls.compExtronDXP then
    Controls.compExtronDXP.EventHandler = function(ctl)
        debugMsg("Extron DXP Matrix selection changed to: " .. ctl.String)
        setcompExtronDXP()
    end
end

do
    local selectors = uciControllerSelectors()
    if selectors then
        for idx = 1, #selectors do
            selectors[idx].EventHandler = function(ctl)
                debugMsg("UCI Controller [" .. idx .. "] selection changed to: " .. ctl.String)
                setcompUCICtls()
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
            applySourceRoutes(getSelectedSource(), "Source Button", true)
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
                applySourceRoutes(selected, "User Button", true)
            elseif not outputAllowedForSource(destIdx, selected) then
                debugMsg("Destination " .. destIdx .. " not valid for current source (separated mode)")
            else
                setRoute(selected, destIdx, "User Button", true)
            end
            refreshDestinationUI()
        end
    end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")

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
    setcompDivisibleSpaceControls()
    setcompUCICtls()

    if isCombinedLayout() then
        applySourceRoutes(getSelectedSource(), "Init", false)
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
