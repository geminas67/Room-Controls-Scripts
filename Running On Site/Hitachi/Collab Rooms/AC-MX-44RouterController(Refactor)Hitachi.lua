--[[
    AC-MX-44 Router Controller
    Author: Nikolas Smith, Q-SYS
    Version: 3.0 | Date: 2026-05-27
    Firmware Req: 10.0.0
    MX44 routing: Output 1 = Inputs 1-4, Output 2 = Inputs 5-8. Room-combined mode syncs Output 2 to Output 1.
]]--

--------** Constant Tables **--------

compMX44Router             = nil  -- MX44 plugin block reference
compDivisibleSpaceControls = nil  -- room combiner script reference (optional)
compInvalid                = {}   -- invalid component flags by type
roomState                  = false -- true = combined, false = separated

--------** Constants **--------

stateDebug      = true
strClear        = "[Clear]"
roomName        = "MX44 Router"
numInputs       = 4   -- btnOutput01[1-4] and btnOutput02[1-4]
numMX44Outputs  = 4   -- MX44 plugin output columns (handler cleanup)
typeMX44   = "%PLUGIN%_0a62fae1-c3d6-308a-8b7f-3586d7abdf9d_%FP%_1d35ac9dec572bc00d3405021155333f"

--------** Functions **--------

--------## Debug ##--------

function debugMsg(str)
    if stateDebug then
        print("[" .. roomName .. "] " .. str)
    end
end

--------## Status ##--------

function checkStatus()
    for _, isInvalid in pairs(compInvalid) do
        if isInvalid then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value  = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value  = 0
end

function setCompInvalid(componentType)
    compInvalid[componentType] = true
    checkStatus()
end

function setCompValid(componentType)
    compInvalid[componentType] = false
    checkStatus()
end

--------## System Components ##--------

function discoverComponents()
    debugMsg("Discovering components...")
    local mx44Names = {}
    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == typeMX44 then
            table.insert(mx44Names, comp.Name)
            debugMsg("  Found MX44: " .. comp.Name)
        end
    end
    debugMsg("Discovery complete - " .. #mx44Names .. " MX44 device(s) found")
    return mx44Names
end

function setComp(ctl, componentType)
    if not ctl then
        setCompInvalid(componentType)
        return nil
    end

    local name = ctl.String
    if not name or name == "" then
        debugMsg("No " .. componentType .. " component selected")
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    elseif name == strClear then
        debugMsg(componentType .. ": Component cleared")
        ctl.String = ""
        ctl.Color = "white"
        setCompValid(componentType)
        return nil
    end

    local comp     = Component.New(name)
    local ctrlList = comp and Component.GetControls(comp)
    if not ctrlList or #ctrlList < 1 then
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        setCompInvalid(componentType)
        debugMsg("ERROR: Invalid component '" .. name .. "' for " .. componentType)
        return nil
    end

    debugMsg("Connected " .. componentType .. ": " .. name)
    ctl.Color = "white"
    setCompValid(componentType)
    return comp
end

function setupComponents()
    local mx44Names = discoverComponents()
    if #mx44Names > 0 and Controls.compMX44 then
        local str = Controls.compMX44.String
        if str == "" or str == strClear then
            Controls.compMX44.String = mx44Names[1]
            debugMsg("Auto-populated compMX44: " .. mx44Names[1])
        end
    end
end

--------## MX44 Routing ##--------

function getMX44ControlName(output, input)
    local physicalInput = ((output - 1) * 4) + input
    return string.format("Input %d", physicalInput)
end

function setRoute(input, output, source)
    source = source or "External"
    if not compMX44Router then
        debugMsg("No MX44 router available (Source: " .. tostring(source) .. ")")
        return false
    end
    if input < 1 or input > numInputs or output < 1 or output > numMX44Outputs then
        debugMsg("Invalid route: input=" .. tostring(input) .. ", output=" .. tostring(output))
        return false
    end
    local ctrlName = getMX44ControlName(output, input)
    local ctrl = compMX44Router[ctrlName]
    if not ctrl then
        debugMsg("Control not found: " .. ctrlName)
        return false
    end
    if ctrl.Boolean then
        return true
    end
    ctrl:Trigger()
    debugMsg("Output " .. output .. " → Input " .. input .. " (Source: " .. tostring(source) .. ")")
    return true
end

function syncOutput02ToOutput01(output01Input)
    if not roomState then return false end
    if output01Input < 1 or output01Input > numInputs then return false end
    return setRoute(output01Input, 2, "Room Combiner")
end

--------## MX44 Router ##--------

function cleanupRouterHandlers()
    if not compMX44Router then return end
    for output = 1, numMX44Outputs do
        for input = 1, numInputs do
            local ctrl = compMX44Router[getMX44ControlName(output, input)]
            if ctrl and ctrl.EventHandler then ctrl.EventHandler = nil end
        end
    end
end

function setcompMX44()
    cleanupRouterHandlers()

    local prev = Controls.compMX44.String
    compMX44Router = setComp(Controls.compMX44, "MX44")
    debugMsg("MX44 component: '" .. prev .. "' → '" .. Controls.compMX44.String .. "'")
    if not compMX44Router then return end

    for inputIdx = 1, numInputs do
        local ctrl = compMX44Router[getMX44ControlName(1, inputIdx)]
        if ctrl then
            ctrl.EventHandler = function(ctl)
                if ctl.Boolean then
                    for i = 1, numInputs do
                        local btn = Controls.btnOutput01[i]
                        if btn and btn.Boolean ~= (i == inputIdx) then
                            btn.Boolean = (i == inputIdx)
                        end
                    end
                    debugMsg("Output 1 → Input " .. inputIdx .. " (Source: MX44 feedback)")
                    if roomState then syncOutput02ToOutput01(inputIdx) end
                end
            end
        end
    end

    for inputIdx = 1, numInputs do
        local ctrl = compMX44Router[getMX44ControlName(2, inputIdx)]
        if ctrl then
            ctrl.EventHandler = function(ctl)
                if ctl.Boolean then
                    for i = 1, numInputs do
                        local btn = Controls.btnOutput02[i]
                        if btn and btn.Boolean ~= (i == inputIdx) then
                            btn.Boolean = (i == inputIdx)
                        end
                    end
                    debugMsg("Output 2 → Input " .. inputIdx .. " (Source: MX44 feedback)")
                end
            end
        end
    end
end

--------## Divisible Space ##--------

function setcompDivisibleSpaceControls()
    local ok, comp = pcall(function() return Component.New("compDivisibleSpaceControls") end)
    if not ok or not comp then
        debugMsg("DivisibleSpaceControls not found (feature disabled)")
        compDivisibleSpaceControls = nil
        roomState = false
        return
    end
    compDivisibleSpaceControls = comp
    debugMsg("DivisibleSpaceControls connected")

    local btnRoomState = comp["btnRoomState 1"]
    if btnRoomState then
        btnRoomState.EventHandler = function(ctl)
            roomState = not ctl.Boolean
            debugMsg("Room state → " .. (roomState and "Combined" or "Separated") .. " (Source: Room Combiner)")
            if not ctl.Boolean and compMX44Router then
                for inputIdx = 1, numInputs do
                    local c = compMX44Router[getMX44ControlName(1, inputIdx)]
                    if c and c.Boolean then
                        syncOutput02ToOutput01(inputIdx)
                        debugMsg("Synced Output 2 to Output 1 (Input " .. inputIdx .. ")")
                        break
                    end
                end
            end
        end
        roomState = not btnRoomState.Boolean
        debugMsg("Initial room state: " .. (roomState and "Combined" or "Separated"))
    else
        debugMsg("Warning: btnRoomState 1 not found")
    end
end

--------** Event Handlers **--------

Controls.compMX44.EventHandler = setcompMX44

for i = 1, numInputs do
    Controls.btnOutput01[i].EventHandler = function()
        setRoute(i, 1, "Output 1")
    end
end

for i = 1, numInputs do
    Controls.btnOutput02[i].EventHandler = function()
        setRoute(i, 2, "Output 2")
    end
end

--------** Always Run **--------

function funcInit()
    debugMsg("=== Initialization Started ===")

    setupComponents()
    setcompMX44()
    setcompDivisibleSpaceControls()

    if compMX44Router then
        setRoute(1, 1, "Init")
        if roomState then
            syncOutput02ToOutput01(1)
        else
            setRoute(1, 2, "Init")
        end
    end

    debugMsg("=== Initialization Complete ===")
end

funcInit()
