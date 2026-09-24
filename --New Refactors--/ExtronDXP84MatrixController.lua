--[[
    Extron DXP Series Matrix Controller (OXP42, DXP44, DXP84, DXP88)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2026-09-20
    Firmware Req: 10.0.0

    Two outputs × four inputs: Output 1 = Room A, Output 2 = Room B.
    Room-combined mode syncs Output 2 to Output 1. Uses Extron matrix output.N String controls.
]]--

-------------------[ Configuration ]-------------------

compType = {
    extronMatrix = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff",
}

numInputs = 4
numOutputs = 2

outputConfigs = {
    { output = 1, controlName = "output.1", buttons = Controls.btnOut01, label = "Output 1" },
    { output = 2, controlName = "output.2", buttons = Controls.btnOut02, label = "Output 2" },
}

divCompName = "compDivisibleSpaceControls"
divRmStateBtn = "btnRoomState 1"

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compExtronMatrix = nil
compDivSpaceControls = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
scriptName = "Extron DXP84"
roomState = false  -- true = combined, false = separated

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
    if stateDebug then print("[" .. scriptName .. "] " .. str) end
end

function getButtonArray(ctl)
    if not ctl then return nil end
    if type(ctl) == "table" then return ctl end
    return { ctl }
end

function getOutputConfig(outputNum)
    for _, cfg in ipairs(outputConfigs) do
        if cfg.output == outputNum then return cfg end
    end
    return nil
end

function forEachOutput(fn)
    for _, cfg in ipairs(outputConfigs) do
        fn(cfg)
    end
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
        if comp.Type == compType.extronMatrix then
            table.insert(extronNames, comp.Name)
            debugMsg("Found Extron DXP: " .. comp.Name)
        end
    end

    table.sort(extronNames)
    fillChoices(Controls.compExtronDXP, extronNames, "compExtronDXP")
    debugMsg("Discovery complete - " .. #extronNames .. " Extron DXP device(s) found")
end

-------------------[ Routing ]-------------------

function updateOutputButtons(outputNum, inputNum)
    local cfg = getOutputConfig(outputNum)
    if not cfg then return end
    local btnArray = getButtonArray(cfg.buttons)
    if not btnArray then return end
    for i, btn in ipairs(btnArray) do
        btn.Boolean = (inputNum > 0 and i == inputNum)
    end
end

function setRoute(input, outputNum, source, skipFeedback)
    source = source or "External"

    local outCtl = getOutputControl(outputNum)
    if not outCtl then
        debugMsg("No output control " .. tostring(outputNum) .. " (" .. source .. ")")
        return false
    end

    if input < 0 or input > numInputs or outputNum < 1 or outputNum > numOutputs then
        debugMsg("Invalid route: input=" .. tostring(input) .. ", output=" .. tostring(outputNum))
        return false
    end

    local strVal = tostring(input)
    if outCtl.String == strVal then
        if not skipFeedback then updateOutputButtons(outputNum, input) end
        return true
    end

    outCtl.String = strVal
    debugMsg("Output " .. outputNum .. " -> Input " .. input .. " (" .. source .. ")")
    if not skipFeedback then updateOutputButtons(outputNum, input) end
    return true
end

function syncRmBtoRmA(skipFeedback)
    if not roomState then return false end
    if not compExtronMatrix then return false end

    local inp = tonumber(compExtronMatrix["output.1"].String) or 0
    if inp < 1 or inp > numInputs then return false end
    return setRoute(inp, 2, "Room Combiner", skipFeedback == true)
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

    if outputNum == 1 and roomState then
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
    local btn = compDivSpaceControls[divRmStateBtn]
    if btn then btn.EventHandler = nil end
end

function setcompDivSpaceControls()
    cleanupDivSpaceHandlers()

    local ok, comp = pcall(function() return Component.New(divCompName) end)
    if not ok or not comp then
        debugMsg("DivisibleSpaceControls not found (feature disabled)")
        compDivSpaceControls = nil
        roomState = false
        return
    end

    compDivSpaceControls = comp
    debugMsg("DivisibleSpaceControls connected")

    local btnRoomState = comp[divRmStateBtn]
    if btnRoomState then
        btnRoomState.EventHandler = function(ctl)
            roomState = not ctl.Boolean
            debugMsg("Room state -> " .. (roomState and "Combined" or "Separated"))
            if not ctl.Boolean and compExtronMatrix then
                syncRmBtoRmA(false)
                debugMsg("Synced Output 2 to Output 1 after combine")
            end
        end
        roomState = not btnRoomState.Boolean
        debugMsg("Initial room state: " .. (roomState and "Combined" or "Separated"))
    else
        debugMsg("Warning: " .. divRmStateBtn .. " not found")
    end
end

-------------------[ Public API ]-------------------

DXP84RouterController = {
    setRoute = setRoute,
    syncRmBtoRmA = syncRmBtoRmA,
}

MatrixController = DXP84RouterController

-------------------[ Event Handlers ]-------------------

Controls.compExtronDXP.EventHandler = setcompExtronDXP

forEachOutput(function(cfg)
    local btnArray = getButtonArray(cfg.buttons)
    if not btnArray then return end

    for i, btn in ipairs(btnArray) do
        btn.EventHandler = function()
            setRoute(i, cfg.output, cfg.label, false)
        end
    end
end)

-------------------[ Always Run ]-------------------

function funcInit()
    debugMsg("=== Initialization Started ===")

    getComponentNames()
    setcompExtronDXP()
    setcompDivSpaceControls()

    if compExtronMatrix then
        setRoute(1, 1, "Init", false)
        if roomState then
            syncRmBtoRmA(false)
        else
            setRoute(1, 2, "Init", false)
        end
    end

    debugMsg("=== Initialization Complete ===")
end

funcInit()
