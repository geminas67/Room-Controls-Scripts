--------** Constant Tables **--------

kdevMXAs = {} -- list of all MXA components
kcompInvalid = {} -- table containing all components that are currently invalid

--------** Constants **--------
Debugging = true -- set to true in order to print funcDebug statements
ClearString = "[Clear]" -- string used in combo boxes to clear out a component

--------** Functions **--------

--------## Setup ##--------

function funcDebug(str) -- helper function that prints funcDebug statements when enabled
    if Debugging then
        print("[funcDebug] " .. str)
    end--if
end--func

--------## Notifications ##--------

--------## System Components ##--------

function funcGetComponentNames()
    -- table to hold component names
    local tblNames = {
        tblNamesCallSync = {},
        tblNamesVideoBridge = {},
        tblNamesMXAs = {},
    }

    -- gather component names
    for i, v in pairs(Component.GetComponents()) do
        if v.Type == "call_sync" then
            table.insert(tblNames.tblNamesCallSync, v.Name)
        elseif v.Type == "usb_uvc" then
            table.insert(tblNames.tblNamesVideoBridge, v.Name)
        elseif v.Type == "%PLUGIN%_984f65d4-443f-406d-9742-3cb4027ff81c_%FP%_1257aeeea0835196bee126b4dccce889" then
            table.insert(tblNames.tblNamesMXAs, v.Name)
        end--if
    end--for

    for i, v in pairs(tblNames) do
        table.sort(v)
        table.insert(v, ClearString)
    end--for

    Controls.compHIDCallSync.Choices = tblNames.tblNamesCallSync
    Controls.compHIDVideoBridge.Choices = tblNames.tblNamesVideoBridge

    for i, v in ipairs(Controls.devMXAs) do
        v.Choices = tblNames.tblNamesMXAs
    end--for
end--func

function functxtStatusCheck()
    for i, v in pairs(kcompInvalid) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end--if
    end--if
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end--func

function funcSetkcompInvalid(componentType)
    kcompInvalid[componentType] = true
    functxtStatusCheck()
end--func

function funcSetCompValid(componentType)
    kcompInvalid[componentType] = false
    functxtStatusCheck()
end--func

function funcSetcomp(ctrl, componentType)
    funcDebug("Setting Component: " .. componentType)
    local componentName = ctrl.String
    if componentName == "" then
        funcDebug("No " .. componentType .. " Component Selected")
        ctrl.Color = "white"
        funcSetCompValid(componentType)
        return nil
    elseif componentName == ClearString then
        funcDebug(componentType .. ": Component Cleared")
        ctrl.String = ""
        ctrl.Color = "white"
        funcSetCompValid(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        funcDebug(componentType .. " Component " .. componentName .. " is Invalid")
        ctrl.String = "[Invalid Component Selected]"
        ctrl.Color = "pink"
        funcSetkcompInvalid(componentType)
        return nil
    else
        funcDebug("Setting " .. componentType .. " Component: {" .. ctrl.String .. "}")
        ctrl.Color = "white"
        funcSetCompValid(componentType)
        return Component.New(componentName)
    end--if
end--func

---- Call Sync and Video Privacy ----

function funcSetcompHIDCallSync()
    compHIDCallSync = funcSetcomp(Controls.compHIDCallSync, "Call Sync")
    if compHIDCallSync ~= nil then
        compHIDCallSync["off.hook"].EventHandler = funcCheckcompHIDCallSyncConnect
        compHIDCallSync["mute"].EventHandler = funcCheckcompHIDCallSyncMute
    end--if
end--func

function funcCheckcompHIDCallSyncMute()
    if compHIDCallSync ~= nil then
        local state = compHIDCallSync["mute"].Boolean
        funcDebug("Call Sync Mute State is: " .. tostring(state))
        Controls.btnPrivacyAudio.Boolean = state
        funcMXAMute(state) -- Ensure MXA mute follows Call Sync mute
    end--if
end--func

function funcSetcompHIDCallSyncMute(state)
    if compHIDCallSync ~= nil then
        funcDebug("Setting Call Sync Mute: " .. tostring(state))
        compHIDCallSync["mute"].Boolean = state
    end--if
    Controls.btnPrivacyAudio.Boolean = state
    funcMXAMute(state) -- Ensure MXA mute follows Call Sync mute
end--func

function funccompHIDCallSyncEnd(state)
    if compHIDCallSync ~= nil then
        funcDebug("Ending Calls")
        compHIDCallSync["call.decline"]:Trigger()
    end--if
end--func

function funcSetcompHIDVideoBridge()
    compVideoBridge = funcSetcomp(Controls.compHIDVideoBridge, "Video Bridge")
    if compVideoBridge ~= nil then
        compVideoBridge["toggle.privacy"].EventHandler = funcCheckcompHIDVideoBridgePrivacy
    end--if
end--func

function funcCheckcompHIDVideoBridgePrivacy()
    if compVideoBridge ~= nil then
        local state = compVideoBridge["toggle.privacy"].Boolean
        funcDebug("Video Privacy State is: " .. tostring(state))
        Controls.btnPrivacyVideo.Boolean = state
        funcMXALED(state) -- Ensure MXA LED follows Video Bridge privacy
    end--if
end--func

function funcSetcompHIDVideoBridgePrivacy(state)
    if compVideoBridge ~= nil then
        funcDebug("Setting Video Privacy: " .. tostring(state))
        compVideoBridge["toggle.privacy"].Boolean = state
    end--if
    Controls.btnPrivacyVideo.Boolean = state
    funcMXALED(state) -- Ensure MXA LED follows Video Bridge privacy
end--func

---- MXAs ----

function funcSetdevMXA(idx)
    kdevMXAs[idx] = funcSetcomp(Controls.devMXAs[idx], "MXA [" .. idx .. "]")
    if kdevMXAs[idx] ~= nil then
        if kdevMXAs[idx]["muteall"] then
            kdevMXAs[idx]["muteall"].EventHandler = function(control)
                funcDebug("MXA ["..idx.."] Mute: "..tostring(control.Boolean))
            end--EH
        end--if
        if kdevMXAs[idx]["bright"] then
            kdevMXAs[idx]["bright"].EventHandler = function(control)
                funcDebug("MXA ["..idx.."] Brightness: "..tostring(control.Value))
            end--EH
        end--if
    end--if
end--func

function funcMXALED(state)
    for i, devMXA in pairs(kdevMXAs) do
        if devMXA["bright"] then
            devMXA["bright"].Value = state and 5 or 0
        end--if
    end--for
end--func

function funcMXAMute(state)
    for i, devMXA in pairs(kdevMXAs) do
        if devMXA["muteall"] then
            devMXA["muteall"].Boolean = state
        end--if
    end--for
end--func

-- EventHandlers -------------------------------------------------------

Controls.compHIDCallSync.EventHandler = funcSetcompHIDCallSync
Controls.compHIDVideoBridge.EventHandler = funcSetcompHIDVideoBridge

-- Combine Logic -------------------------------------------------------

-- Divide Logic --------------------------------------------------------

-- Hook Logic ----------------------------------------------------------

function funcInit()
    funcCheckcompHIDVideoBridgePrivacy() -- sync video privacy fb
    funcGetComponentNames() -- populate combo boxes for component selection with script names

    -- set components with what's currently selected 
    funcSetcompHIDCallSync() 
    funcSetcompHIDVideoBridge() 
    for i, v in ipairs(Controls.devMXAs) do
        funcSetdevMXA(i) 
    end
end

funcInit()
