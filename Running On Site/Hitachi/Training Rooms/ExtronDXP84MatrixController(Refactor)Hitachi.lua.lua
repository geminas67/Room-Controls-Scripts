--[[
  Extron DXP Matrix Routing Controller
  Author: Nikolas Smith, Q-SYS
  Date: 2026-04-03
  Version: 5.4
  Firmware Req: 10.0.0

  Room-combine matrix follows compDivisibleSpaceControls btnRoomState 1–3 (interlock); system power
  and auto-switch still use compRoomControls. UCI publishes layer changes via Notifications (see
  uciLayerNotifyMatrix); do not bind btnNav07–10 here—UCI owns those controls. Output handlers
  refresh ledSourceRouted when output.N changes.
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

-- Must match UCIController(DivisibleSpace): cross-script handoff (Lua _G is not shared between scripts).
local uciLayerNotifyMatrix = "HitachiTraining_UCIMatrixLayer"
local sourceButtonToInput = { [1] = 1, [2] = 2, [3] = 3, [4] = 4, [5] = 0}
local sourceNames       = {
    [0] = "No Source", [1] = "Laptop RmA", [2] = "Laptop RmB", [3] = "TeamsPC RmA", [4] = "TeamsPC RmB",
}

-- Divisible space: output indices per room (extend lists when adding displays; only 1–2 used on site)
local routingConfig = {
    outputsForRoomA = { 1 },
    outputsForRoomB = { 2 },
}

-------------------[ State ]-------------------
local norm = {}

local components = {
    extronMatrix            = nil,
    callSync                = nil,
    roomControls            = nil,
    divisibleSpaceControls  = nil,
    uciLayerSelector        = nil,
    invalid                 = {},
}

-- roomLayoutMode: 1 = Separated, 2/3 = Combined (both outputs follow selected source, e.g. UCI layer)
-- lastSeparatedSourceA/B: expected routed input per side when separated (independent of the other room)
local state = {
    power = false, warming = true, cooling = false, roomLayoutMode = 1,
    lastSeparatedSourceA = nil, lastSeparatedSourceB = nil,
}

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
    { name = "Teams PCRmA (Sig3)", input = inputs.TeamsPCRmA, checkFunc = function()
        local led = norm.ledSignalPresence and norm.ledSignalPresence[3]
        return led and led.Boolean
    end },
    { name = "Teams PCRmB", input = inputs.TeamsPCRmB, checkFunc = function()
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
        btnSource          = {},
        btnDestination     = {},
        ledSourceRouted    = {},
        ledSignalPresence  = {},
        uciButtons         = { [7] = controls.btnNav07, [8] = controls.btnNav08, [9] = controls.btnNav09, [10] = controls.btnNav10 }
    }
    if controls.btnSource then
        for idx = 1, 6 do norm.btnSource[idx] = controls.btnSource[idx] end
    end
    if controls.btnDestination then
        for idx = 1, 5 do norm.btnDestination[idx] = controls.btnDestination[idx] end
    end
    if controls.ledSourceRouted then
        for idx = 1, 4 do norm.ledSourceRouted[idx] = controls.ledSourceRouted[idx] end
    end
    if controls.ledSignalPresence then
        for idx = 1, 5 do norm.ledSignalPresence[idx] = controls.ledSignalPresence[idx] end
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
    local discovered = { extronMatrix = {}, callSync = {}, clickShare = {}, roomControls = {} }
    for _, comp in pairs(Component.GetComponents()) do
        if comp.Type == componentTypes.extronMatrix then
            table.insert(discovered.extronMatrix, comp.Name)
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
    local total = #discovered.extronMatrix + #discovered.callSync + #discovered.clickShare + #discovered.roomControls
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
    local targetIdx = nil
    for btnIdx, inputNum in pairs(sourceButtonToInput) do
        if inputNum == input then targetIdx = btnIdx; break end
    end
    if not targetIdx then updateSourceText(); return end
    for idx = 1, 6 do
        local btn = norm.btnSource and norm.btnSource[idx]
        if btn then setProp(btn, "Boolean", idx == targetIdx) end
    end
    updateSourceText()
end

--- Combined mode routes both outputs to the same source; keep btnSource/txtSource aligned with that input.
local function syncSourceUIFromCombinedLayout(selectedInput)
    if state.roomLayoutMode ~= 2 and state.roomLayoutMode ~= 3 then return end
    if not selectedInput or selectedInput == inputs.NoSource then updateSourceText(); return end
    syncSourceButtonsToInput(selectedInput)
    debugPrint("Source UI → " .. (sourceNames[selectedInput] or tostring(selectedInput)) .. " (combined layout)")
end

local function tableContains(tbl, val)
    if not tbl then return false end
    for _, v in ipairs(tbl) do if v == val then return true end end
    return false
end

local function allOutputsInUse()
    local t = {}
    for _, o in ipairs(routingConfig.outputsForRoomA) do table.insert(t, o) end
    for _, o in ipairs(routingConfig.outputsForRoomB) do table.insert(t, o) end
    return t
end

local function inputBelongsToRoomA(input)
    return input == inputs.LaptopRmA or input == inputs.TeamsPCRmA
end

local function inputBelongsToRoomB(input)
    return input == inputs.LaptopRmB or input == inputs.TeamsPCRmB
end

local function expectedInputOnOutput(output)
    if state.roomLayoutMode == 2 or state.roomLayoutMode == 3 then
        if tableContains(routingConfig.outputsForRoomA, output) or tableContains(routingConfig.outputsForRoomB, output) then
            local sel = getSelectedSource()
            return (sel and sel ~= inputs.NoSource) and sel or 0
        end
        return 0
    end
    local expA, expB = state.lastSeparatedSourceA, state.lastSeparatedSourceB
    if tableContains(routingConfig.outputsForRoomA, output) then
        if expA and expA ~= inputs.NoSource and inputBelongsToRoomA(expA) then return expA end
        return 0
    end
    if tableContains(routingConfig.outputsForRoomB, output) then
        if expB and expB ~= inputs.NoSource and inputBelongsToRoomB(expB) then return expB end
        return 0
    end
    return 0
end

local function outputAllowedForSource(out, selected)
    if state.roomLayoutMode == 2 or state.roomLayoutMode == 3 then return true end
    if inputBelongsToRoomA(selected) then return tableContains(routingConfig.outputsForRoomA, out) end
    if inputBelongsToRoomB(selected) then return tableContains(routingConfig.outputsForRoomB, out) end
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

local function onExtronOutputChange()
    updateDestinationFeedback()
    updateDestinationText()
end

local extronOutputControls = { "output.1", "output.2", "output.3", "output.4" }

local function setExtronMatrixComponent()
    local oldComp = components.extronMatrix
    if oldComp then
        cleanupComponentHandlers(oldComp, extronOutputControls, function(msg) debugPrint("[Extron DXP] " .. msg) end)
    end
    components.extronMatrix = setComponent(controls.compExtronDXP, "Extron DXP Matrix")
    local comp = components.extronMatrix
    if comp then
        local count = 0
        for _, ctrlName in ipairs(extronOutputControls) do
            if comp[ctrlName] and bind(comp[ctrlName], onExtronOutputChange) then count = count + 1 end
        end
        debugPrint("Registered " .. count .. " Extron output handlers for event-driven feedback")
    end
end

-------------------[ Routing ]-------------------
local function setRoute(input, output, source, skipFeedback)
    if not components.extronMatrix then return end
    setProp(components.extronMatrix['output.' .. output], "String", tostring(input))
    local sourceStr = source and " (Source: " .. source .. ")" or ""
    debugPrint("Routed Output " .. output .. " → Input " .. input .. sourceStr)
    if not skipFeedback then
        updateDestinationFeedback()
        updateDestinationText()
    end
end

local function clearRoute(output, skipFeedback)
    if not components.extronMatrix then return end
    setProp(components.extronMatrix['output.' .. output], "String", "0")
    debugPrint("Cleared Output " .. output)
    if not skipFeedback then
        updateDestinationFeedback()
        updateDestinationText()
    end
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
    if state.roomLayoutMode == 2 or state.roomLayoutMode == 3 then
        if selected == nil or selected == inputs.NoSource then
            for _, out in ipairs(allOutputsInUse()) do clearRoute(out, true) end
        else
            local targets = outputs or allOutputsInUse()
            for _, out in ipairs(targets) do
                setRoute(selected, out, source, true)
            end
        end
        syncSourceUIFromCombinedLayout(selected)
        if not skip then updateDestinationFeedback(); updateDestinationText() end
        return
    end
    if selected == nil or selected == inputs.NoSource then
        for _, out in ipairs(allOutputsInUse()) do clearRoute(out, true) end
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = nil, nil
        if not skip then updateDestinationFeedback(); updateDestinationText() end
        return
    end
    if inputBelongsToRoomA(selected) then
        state.lastSeparatedSourceA = selected
        local targets = outputs or routingConfig.outputsForRoomA
        for _, out in ipairs(targets) do
            if tableContains(routingConfig.outputsForRoomA, out) then
                setRoute(selected, out, source, true)
            end
        end
    elseif inputBelongsToRoomB(selected) then
        state.lastSeparatedSourceB = selected
        local targets = outputs or routingConfig.outputsForRoomB
        for _, out in ipairs(targets) do
            if tableContains(routingConfig.outputsForRoomB, out) then
                setRoute(selected, out, source, true)
            end
        end
    else
        for _, out in ipairs(allOutputsInUse()) do clearRoute(out, true) end
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = nil, nil
    end
    if not skip then updateDestinationFeedback(); updateDestinationText() end
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
    if state.roomLayoutMode ~= 2 and state.roomLayoutMode ~= 3 and input ~= nil then
        syncSourceButtonsToInput(input)
    end
    updateDestinationFeedback()
    updateDestinationText()
end

-------------------[ Auto-Switch ]-------------------
local function checkAutoSwitch()
    for _, source in ipairs(sourcePriority) do
        if source.checkFunc() then
            if not state.power and components.roomControls then
                debugPrint("Powering on system for " .. source.name)
                setProp(components.roomControls["btnSystemOnOff"], "Boolean", true)
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
    setup(controls.compExtronDXP, discovered.extronMatrix, setExtronMatrixComponent, "Extron DXP Matrix")
    setup(controls.compCallSync, discovered.callSync, setCallSyncComponent, "CallSync")
    setup(controls.compRoomControls, discovered.roomControls, setRoomControlsComponent, "Room Controls")
end

local function setDestinationButtonProps(output, color, text, invisible)
    local btn = norm.btnDestination and norm.btnDestination[output]
    if not btn then return end
    setProp(btn, "Color", color)
    if text and text ~= "" then setProp(btn, "String", text) end
    setProp(btn, "IsInvisible", invisible)
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
local function registerEvents()
    local sourceCount = 0
    for idx = 1, 6 do
        local btn = norm.btnSource and norm.btnSource[idx]
        if btn then
            bind(btn, function(ctl)
                if not ctl.Boolean then return end
                for srcIdx = 1, 6 do
                    if srcIdx ~= idx then
                        local other = norm.btnSource and norm.btnSource[srcIdx]
                        if other then setProp(other, "Boolean", false) end
                    end
                end
--[[                 if idx == 2 or idx == 3 then
                    setDestinationButtonProps(2, '#ff6666', 'N/A', true)
                    setDestinationButtonProps(4, '#ff6666', 'N/A', true)
                else
                    setDestinationButtonProps(2, '#ff7c7c7c', '', false)
                    setDestinationButtonProps(4, '#ff7c7c7c', '', false)
                end
 ]]             debugPrint("Source button " .. idx .. " pressed")
                applyRoutesForSource(getSelectedSource(), "Source Button", true)
                updateSourceText()
                updateDestinationFeedback()
                updateDestinationText()
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
                    applyRoutesForSource(selected, "User Button", true)
                elseif not outputAllowedForSource(idx, selected) then
                    debugPrint("Destination " .. idx .. " not valid for current source (separated mode)")
                elseif state.roomLayoutMode == 2 or state.roomLayoutMode == 3 then
                    applyRoutesForSource(selected, "User Button", true)
                else
                    setRoute(selected, idx, "User Button", true)
                end
                updateDestinationFeedback()
                updateDestinationText()
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
    debugPrint("Configuration: debugging=" .. tostring(debugging) .. ", uciEnabled=" .. tostring(uci.enabled))

    local discovered = discoverComponents()
    setupComponentSelectors(discovered)
    setExtronMatrixComponent()
    setCallSyncComponent()
    setRoomControlsComponent()
    setDivisibleSpaceControlsComponent()
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

    if components.roomControls then
        state.power   = components.roomControls["ledSystemPower"].Boolean
        state.warming = components.roomControls["ledSystemWarming"].Boolean
    end

    local ok, uciSel = pcall(function() return Component.New('BDRM-UCI Layer Selector') end)
    if ok and uciSel then
        components.uciLayerSelector = uciSel
        debugPrint("UCI Layer Selector component set")
    end

    if state.roomLayoutMode == 2 or state.roomLayoutMode == 3 then
        applyRoutesForSource(getSelectedSource(), "Init", false)
    else
        setRoute(inputs.LaptopRmA, 1, "Init", true)
        setRoute(inputs.LaptopRmB, 2, "Init", true)
        state.lastSeparatedSourceA, state.lastSeparatedSourceB = inputs.LaptopRmA, inputs.LaptopRmB
        updateDestinationFeedback()
        updateDestinationText()
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
