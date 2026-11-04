--[[
    Extron DXP Series Matrix Controller (OXP42, DXP44, DXP84, DXP88)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2026-09-20
    Firmware Req: 10.0.0

    Four matrix outputs × four inputs. Room A: output.1 and output.2; Room B: output.3 and output.4.
    Combined mode mirrors Room B outputs to Room A (3←1, 4←2). Uses Extron matrix output.N String controls.
]]--

-------------------[ Configuration ]-------------------

pluginDXP = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff"
-- Set the number of inputs and outputs for the Extron DXP Matrix
numInputs = 4
numOutputs = 4

outputsRoomA = { 1, 2 }
outputsRoomB = { 3, 4 }

outputConfigs = {
    { output = 1, controlName = "output.1", buttons = Controls.btnOut01, label = "Room A Out 1" },
    { output = 2, controlName = "output.2", buttons = Controls.btnOut02, label = "Room A Out 2" },
    { output = 3, controlName = "output.3", buttons = Controls.btnOut03, label = "Room B Out 1" },
    { output = 4, controlName = "output.4", buttons = Controls.btnOut04, label = "Room B Out 2" },
}

divCompName = "compDivisibleSpaceControls"
btnRoomMode = "btnRoomMode 1"

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compExtronMatrix = nil
compDivSpaceControls = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
scriptName = "Extron DXP84"
stateCombined = false  -- true = combined, false = separated

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
    if stateDebug then print("[" .. scriptName .. "] " .. str) end
end

function getOutputConfig(outputNum)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.output == outputNum then return cfg end
    end
    return nil
end

function getOutputControl(outputNum)
    local cfg = getOutputConfig(outputNum)
    if not compExtronMatrix or not cfg then return nil end
    return compExtronMatrix[cfg.controlName]
end

-------------------[ Status ]-------------------

function checkStatus()
    for _, isInvalid in pairs(compInvalid) do
        if isInvalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
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
    if not ctl then setCompInvalid(componentType); return nil end

    local name = ctl.String
    if not name or name == "" then
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    end

    if name == strClear then
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        debugMsg(componentType .. " cleared")
        return nil
    end

    local comp = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        debugMsg("Invalid " .. componentType .. ": " .. name)
        return nil
    end

    ctl.Color = "white"
    setCompValid(componentType)
    debugMsg("Connected " .. componentType .. ": " .. name)
    return comp
end

-------------------[ Discovery ]-------------------

function fillChoices(ctl, names, label)
    if not ctl or #names < 1 then return end
    ctl.Choices = names
    if ctl.String == "" or ctl.String == strClear then
        ctl.String = names[1]
        debugMsg("Auto-populated " .. label .. ": " .. names[1])
    end
end

function getComponentNames()
    local extronNames = {}

    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == pluginDXP then
            table.insert(extronNames, comp.Name)
            debugMsg("Found Extron DXP plugin: " .. comp.Name)
        end
    end

    table.sort(extronNames)
    fillChoices(Controls.compExtronDXP, extronNames, "compExtronDXP")
    debugMsg("Discovery complete - " .. #extronNames .. " Extron DXP plugin(s) found")
end

-------------------[ Routing ]-------------------

function updateOutputButtons(outputNum, inputNum)
    local cfg = getOutputConfig(outputNum)
    if not cfg then return end
    for i, btn in ipairs(cfg.buttons) do
        btn.Boolean = (inputNum > 0 and i == inputNum)
    end
end

function setRoute(input, outputNum, source, skipFeedback)
    source = source or "External"

    if input < 0 or input > numInputs or outputNum < 1 or outputNum > numOutputs then
        debugMsg("Invalid route: input=" .. tostring(input) .. ", output=" .. tostring(outputNum))
        return false
    end

    local outCtl = getOutputControl(outputNum)
    if not outCtl then
        debugMsg("No output control " .. tostring(outputNum) .. " (" .. source .. ")")
        return false
    end

    local strVal = tostring(input)
    if outCtl.String ~= strVal then
        outCtl.String = strVal
        debugMsg("Output " .. outputNum .. " -> Input " .. input .. " (" .. source .. ")")
    end

    if not skipFeedback then updateOutputButtons(outputNum, input) end
    return true
end

function syncRmBtoRmA(skipFeedback)
    if not stateCombined then return false end
    if not compExtronMatrix then return false end

    local skip = skipFeedback == true
    local ok = true
    for i = 1, #outputsRoomA do
        local srcOut = outputsRoomA[i]
        local dstOut = outputsRoomB[i]
        local inp = tonumber(compExtronMatrix["output." .. srcOut].String) or 0
        if inp < 1 or inp > numInputs then
            ok = false
        elseif not setRoute(inp, dstOut, "Room Combiner", skip) then
            ok = false
        end
    end
    return ok
end

function isRoomAOutput(outputNum)
    for _, out in ipairs(outputsRoomA) do
        if out == outputNum then return true end
    end
    return false
end

-------------------[ Extron Matrix ]-------------------

function cleanupExtronHandlers()
    if not compExtronMatrix then return end
    for _, cfg in ipairs(outputConfigs) do
        local ctl = compExtronMatrix[cfg.controlName]
        if ctl then ctl.EventHandler = nil end
    end
end

function onOutputStringChanged(outputNum)
    local outCtl = getOutputControl(outputNum)
    if not outCtl then return end

    local inp = tonumber(outCtl.String) or 0
    updateOutputButtons(outputNum, inp)
    debugMsg("Output " .. outputNum .. " feedback -> Input " .. inp)

    if stateCombined and isRoomAOutput(outputNum) then
        syncRmBtoRmA(true)
    end
end

function setcompExtronDXP()
    cleanupExtronHandlers()
    compExtronMatrix = setComp(Controls.compExtronDXP, "Extron DXP Matrix")
    if not compExtronMatrix then return end

    for _, cfg in ipairs(outputConfigs) do
        local outCtl = compExtronMatrix[cfg.controlName]
        if outCtl then
            outCtl.EventHandler = function()
                onOutputStringChanged(cfg.output)
            end
            debugMsg("Registered feedback handler for " .. cfg.controlName)
        end
    end
end

-------------------[ Divisible Space ]-------------------

function cleanupDivSpaceHandlers()
    if not compDivSpaceControls then return end
    local btn = compDivSpaceControls[btnRoomMode]
    if btn then btn.EventHandler = nil end
end

function setcompDivSpaceControls()
    cleanupDivSpaceHandlers()

    local ok, comp = pcall(function() return Component.New(divCompName) end)
    if not ok or not comp then
        debugMsg("DivisibleSpaceControls not found (feature disabled)")
        compDivSpaceControls = nil
        stateCombined = false
        return
    end

    compDivSpaceControls = comp
    debugMsg("DivisibleSpaceControls connected")

    local btnMode = comp[btnRoomMode]
    if btnMode then
        btnMode.EventHandler = function(ctl)
            stateCombined = not ctl.Boolean
            debugMsg("Room state -> " .. (stateCombined and "Combined" or "Separated"))
            if not ctl.Boolean and compExtronMatrix then
                syncRmBtoRmA(false)
                debugMsg("Synced Room B outputs (3–4) to Room A (1–2) after combine")
            end
        end
        stateCombined = not btnMode.Boolean
        debugMsg("Initial room state: " .. (stateCombined and "Combined" or "Separated"))
    else
        debugMsg("Warning: " .. btnRoomMode .. " not found")
    end
end

-------------------[ Event Handlers ]-------------------

Controls.compExtronDXP.EventHandler = setcompExtronDXP

for _, cfg in ipairs(outputConfigs) do
    for i, btn in ipairs(cfg.buttons) do
        btn.EventHandler = function()
            setRoute(i, cfg.output, cfg.label, false)
        end
    end
end

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")

    getComponentNames()
    setcompExtronDXP()
    setcompDivSpaceControls()

    if compExtronMatrix then
        for _, out in ipairs(outputsRoomA) do
            setRoute(1, out, "Init", false)
        end
        if stateCombined then
            syncRmBtoRmA(false)
        else
            for _, out in ipairs(outputsRoomB) do
                setRoute(1, out, "Init", false)
            end
        end
    end

    debugMsg("=== Initialization Complete ===")
end

funcInit()
