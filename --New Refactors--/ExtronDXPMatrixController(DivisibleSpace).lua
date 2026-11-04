--[[
    Extron DXP Series Matrix Controller (OXP42, DXP44, DXP84, DXP88)
    Author: Nikolas Smith, Q-SYS
    Version: 2.0 | Date: 2026-09-20
    Firmware Req: 10.0.0

    Four matrix outputs × four inputs. Room A: output.1 and output.2; Room B: output.3 and output.4.
    Combined mode mirrors Room B outputs to Room A (3←1, 4←2). Uses Extron matrix output.N String controls.
]]--

-------------------[ Configuration ]-------------------
compType = {
    uciController = "device_controller_script",
    }
    
    compNameMatch = {
    uciController = "^uciController",
    }
    
    pluginDXP = "%PLUGIN%_qsysc.extron.matrix.0.0.0.0-master_%FP%_bf09cd55c73845eb6fc31e4b896516ff"
    -- Set the number of inputs and outputs for the Extron DXP Matrix
    numInputs = 4
    numOutputs = 4
    
    inputRoomA = 1
    inputRoomB = 2
    
    outputsRoomA = { 1, 2 }
    outputsRoomB = { 3, 4 }
    
    outputConfigs = {
        { output = 1, controlName = "output.1", buttons = Controls.btnOut01, label = "Room A Out 1" },
        { output = 2, controlName = "output.2", buttons = Controls.btnOut02, label = "Room A Out 2" },
        { output = 3, controlName = "output.3", buttons = Controls.btnOut03, label = "Room B Out 1" },
        { output = 4, controlName = "output.4", buttons = Controls.btnOut04, label = "Room B Out 2" },
    }
    
    uciNavSource = {
        btnNav09 = inputRoomA,
        btnNav10 = inputRoomB,
    }
    
    divCompName = "compDivisibleSpaceControls"
    btnRoomMode = "btnRoomMode 1"
    -- btnRoomMode 1.Boolean true = divided; false = combined. Default inputs when divided:
    
    -------------------[ Constant Tables ]-------------------
    
    compInvalid = {}
    compExtronMatrix = nil
    compDivSpaceControls = nil
    compUCICtls = {}
    
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
    
    function uciControllerSelectors()
        local sel = Controls.compUCIController
        if not sel then return nil end
        if type(sel) == "table" and sel[1] then return sel end
        return { sel }
    end
    
    function uciNavAllowedForSlot(uciIdx)
        if not stateCombined then return true end
        return uciIdx == 1
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
        local extronNames, uciNames = {}, {}
    
        for _, comp in ipairs(Component.GetComponents()) do
            if comp.Type == pluginDXP then
                table.insert(extronNames, comp.Name)
                debugMsg("Found Extron DXP plugin: " .. comp.Name)
            elseif comp.Type == compType.uciController and string.match(comp.Name, compNameMatch.uciController) then
                table.insert(uciNames, comp.Name)
            end
        end
    
        table.sort(extronNames)
        table.sort(uciNames)
        fillChoices(Controls.compExtronDXP, extronNames, "compExtronDXP")
        local uciSelectors = uciControllerSelectors()
        if uciSelectors then
            for idx = 1, #uciSelectors do
                fillChoices(uciSelectors[idx], uciNames, "compUCIController [" .. idx .. "]")
                if idx == 2 and #uciNames >= 2 and (uciSelectors[idx].String == uciNames[1]) then
                    uciSelectors[idx].String = uciNames[2]
                end
            end
        end
        debugMsg("Discovery complete - Extron: " .. #extronNames .. ", UCI: " .. #uciNames)
    end
    
    -------------------[ Routing ]-------------------
    
    function updateOutputButtons(outputNum, inputNum)
        local cfg = getOutputConfig(outputNum)
        if not cfg then return end
        for i, btn in ipairs(cfg.buttons) do
            btn.Boolean = (inputNum > 0 and i == inputNum)
        end
    end
    
    function setSource(input, source, uciIdx)
        if not compExtronMatrix then return end
        local outs = (uciIdx == 2) and outputsRoomB or outputsRoomA
        for _, out in ipairs(outs) do
            setRoute(input, out, source, false)
        end
        if stateCombined and uciIdx ~= 2 then syncRmBtoRmA() end
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
        local changed = outCtl.String ~= strVal
        if changed then
            outCtl.String = strVal
            debugMsg("Output " .. outputNum .. " -> Input " .. input .. " (" .. source .. ")")
        end
    
        if not skipFeedback then updateOutputButtons(outputNum, input) end
        return true
    end
    
    function syncRmBtoRmA()
        if not stateCombined then return false end
        if not compExtronMatrix then return false end
    
        local ok = true
        for i = 1, #outputsRoomA do
            local srcOut = outputsRoomA[i]
            local dstOut = outputsRoomB[i]
            local inp = tonumber(compExtronMatrix["output." .. srcOut].String) or 0
            if inp < 1 or inp > numInputs then
                ok = false
            elseif not setRoute(inp, dstOut, "Room Combiner", false) then
                ok = false
            end
        end
        debugMsg("Room Combiner sync (B <- A): " .. (ok and "OK" or "incomplete"))
        return ok
    end
    
    function routeRoomBSeparate(source)
        if not compExtronMatrix then return end
        source = source or "Divided"
        for _, out in ipairs(outputsRoomB) do
            setRoute(inputRoomB, out, source, false)
        end
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
            syncRmBtoRmA()
        end
    end
    
    function setcompExtronDXP()
        cleanupExtronHandlers()
        compExtronMatrix = setComp(Controls.compExtronDXP, "Extron DXP Matrix")
        if not compExtronMatrix then return end
    
        for _, cfg in ipairs(outputConfigs) do
            local outCtl = compExtronMatrix[cfg.controlName]
            if outCtl then
                outCtl.EventHandler = function() onOutputStringChanged(cfg.output) end
                debugMsg("Registered feedback handler for " .. cfg.controlName)
            end
        end
        if stateCombined then syncRmBtoRmA() end
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
                if not compExtronMatrix then return end
                if stateCombined then
                    syncRmBtoRmA()
                elseif ctl.Boolean then
                    routeRoomBSeparate("Room Divider")
                end
            end
            stateCombined = not btnMode.Boolean
            debugMsg("Initial room state: " .. (stateCombined and "Combined" or "Separated"))
            if stateCombined and compExtronMatrix then
                syncRmBtoRmA()
            end
        else
            debugMsg("Warning: " .. btnRoomMode .. " not found")
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
                    setSource(inputNum, "UCI Nav " .. roomLabel .. ": " .. btnName, uciIdx)
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
    
    Controls.compExtronDXP.EventHandler = setcompExtronDXP
    
    local uciSelectors = uciControllerSelectors()
    if uciSelectors then
        for idx = 1, #uciSelectors do
            uciSelectors[idx].EventHandler = function() setUCIControllerAtIndex(idx) end
        end
    end
    
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
        setcompUCICtls()
    
        if compExtronMatrix and not stateCombined then
            for _, out in ipairs(outputsRoomA) do
                setRoute(inputRoomA, out, "Init", false)
            end
            routeRoomBSeparate("Init")
        end
    
        debugMsg("=== Initialization Complete ===")
    end
    
    funcInit()
    