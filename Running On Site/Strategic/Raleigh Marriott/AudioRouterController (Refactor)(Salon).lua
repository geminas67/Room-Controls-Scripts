--[[
    Audio Router Controller (Salon)
    Author: Nikolas Smith, Q-SYS
    Version: 4.0 | Date: 2026-05-26
    Firmware Req: 10.0.0
    Notes:
    - DivisibleSpaceController owns all combination routing; this script
      handles direct source selection and fire-alarm mute only
]]--

--------** Constant Tables **--------

compAudioRouter  = nil  -- audio router block reference
compRoomControls = nil  -- room controls script reference
compInvalid      = {}   -- invalid component flags by type
btnAudioSources  = {}   -- normalized btnAudioSource control array

--------** Constants **--------

stateDebug = true
strClear   = "[Clear]"
roomName   = "Salon Audio Router"

inputSalon = {
    SalonD = 1, SalonE = 2, SalonA = 3,
    SalonB = 4, SalonC = 5, SalonF = 6,
    SalonG = 7, SalonH = 8, none = 9,
}

output01 = 1

typeAudioRouter  = "router_with_output"
typeRoomControls = "device_controller_script"

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
    local routerNames, roomCtrlNames = {}, {}

    for _, comp in ipairs(Component.GetComponents()) do
        if comp.Type == typeAudioRouter then
            table.insert(routerNames, comp.Name)
            debugMsg("  Found audio router: " .. comp.Name)
        elseif comp.Type == typeRoomControls and string.match(comp.Name, "^compRoomControls") then
            table.insert(roomCtrlNames, comp.Name)
            debugMsg("  Found room controls: " .. comp.Name)
        end
    end

    table.sort(routerNames);   table.insert(routerNames,   strClear)
    table.sort(roomCtrlNames); table.insert(roomCtrlNames, strClear)

    Controls.compAudioRouter.Choices  = routerNames
    Controls.compRoomControls.Choices = roomCtrlNames

    debugMsg("Discovery complete - routers: " .. (#routerNames - 1) ..
             ", room controls: " .. (#roomCtrlNames - 1))
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

--------## Audio Routing ##--------

function setRoute(input, output, source)
    if not compAudioRouter then return end
    compAudioRouter["select." .. tostring(output)].Value = input
    debugMsg("Output " .. tostring(output) .. " → Input " .. tostring(input) ..
             " (Source: " .. (source or "unknown") .. ")")
end

--------## Audio Router ##--------

function setcompAudioRouter()
    if compAudioRouter and compAudioRouter["select.1"] then
        compAudioRouter["select.1"].EventHandler = nil
        debugMsg("Cleaned up previous audio router handlers")
    end

    local prev = Controls.compAudioRouter.String
    compAudioRouter = setComp(Controls.compAudioRouter, "audioRouter")
    debugMsg("Audio router component: '" .. prev .. "' → '" .. Controls.compAudioRouter.String .. "'")
    if not compAudioRouter then return end

    compAudioRouter["select.1"].EventHandler = function(ctl)
        local inputValue = ctl.Value
        for i, btn in ipairs(btnAudioSources) do
            if btn.Boolean ~= (i == inputValue) then
                btn.Boolean = (i == inputValue)
            end
        end
        debugMsg("Router feedback: Output 1 → Input " .. tostring(inputValue))
    end
    debugMsg("Registered: audio router select feedback handler")
end

--------## Room Controls ##--------

function setcompRoomControls()
    compRoomControls = setComp(Controls.compRoomControls, "roomControls")
    if not compRoomControls then return end

    if compRoomControls["ledFireAlarm"] then
        compRoomControls["ledFireAlarm"].EventHandler = function(ctl)
            if ctl.Boolean then
                debugMsg("Fire alarm ACTIVE → routing to none (Source: Room Controls)")
                setRoute(inputSalon.none, output01, "Fire Alarm")
            else
                debugMsg("Fire alarm CLEARED (Source: Room Controls)")
            end
        end
        debugMsg("Registered: fire alarm handler")
    end
end

--------** Normalize Controls **--------

if Controls.btnAudioSource and Controls.btnAudioSource[1] then
    btnAudioSources = Controls.btnAudioSource
elseif Controls.btnAudioSource then
    btnAudioSources = { Controls.btnAudioSource }
end

--------** Event Handlers **--------

Controls.compAudioRouter.EventHandler  = setcompAudioRouter
Controls.compRoomControls.EventHandler = setcompRoomControls

for i, btn in ipairs(btnAudioSources) do
    btn.EventHandler = function()
        setRoute(i, output01, "Source Button")
    end
end

--------** Always Run **--------

function funcInit()
    debugMsg("=== Initialization Started ===")

    discoverComponents()
    setcompAudioRouter()
    setcompRoomControls()

    debugMsg("=== Initialization Complete ===")
end

funcInit()
