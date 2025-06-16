--[[ 
  Audio Router Controller
  Author: Hope Roth, Q-SYS
  February, 2025
  Firmware Req: 9.12
  Version: 1.0
]]--

-----------------------------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------------------------
Debugging = true -- set to true in order to print debug statements
ClearString = "[Clear]" -- string used in combo boxes to clear out a component
InvalidComponents = {} -- table containing all components that are currently invalid

-- Input/Output mapping
kInputXLR = 1
kInputDMP01 = 2
kInputDMP02 = 3
kInputDMP03 = 4
kInputNWP01 = 5
kInputNWP02 = 6
kInputNWP03 = 7
kInputNone = 8

kOutput1 = 1

arrAudioInput = {
    kInputXLR,
    kInputDMP01,
    kInputDMP02,
    kInputDMP03,
    kInputNWP01,
    kInputNWP02,
    kInputNWP03,
    kInputNone,
}

arrAudioOutput = {
    kOutput1,
}

-----------------------------------------------------------------------------------------------------------------
-- Helper Functions
-----------------------------------------------------------------------------------------------------------------
function Debug(str)
    if Debugging then
        print("[Debug] " .. str)
    end
end

function funcChecktxtStatus()
    for i, v in pairs(InvalidComponents) do
        if v == true then
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end
    end
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end

function funcSetInvalidComponent(componentType)
    InvalidComponents[componentType] = true
    funcChecktxtStatus()
end

function funcSetValidComponent(componentType)
    InvalidComponents[componentType] = false
    funcChecktxtStatus()
end

function SetComponent(ctl, componentType)
    Debug("Setting Component: " .. componentType)
    componentName = ctl.String
    
    if componentName == "" then
        Debug("No " .. componentType .. " Component Selected")
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return nil
    elseif componentName == ClearString then
        Debug(componentType .. ": Component Cleared")
        ctl.String = ""
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then
        Debug(componentType .. " Component " .. componentName .. " is Invalid")
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        funcSetInvalidComponent(componentType)
        return nil
    else
        Debug("Setting " .. componentType .. " Component: {" .. ctl.String .. "}")
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return Component.New(componentName)
    end
end

-----------------------------------------------------------------------------------------------------------------
-- Component Setup
-----------------------------------------------------------------------------------------------------------------
function funcSetcompAudioRouter()
    compAudRtr = SetComponent(Controls.compAudioRouter, "Audio Router")
    if compAudRtr ~= nil then
        compAudRtr["select.1"].EventHandler = function(ctl)
            for i, v in ipairs(Controls.btnAudioSource) do
                v.Boolean = (arrAudioInput[i] == ctl.Value)
            end
            Debug("Audio Router set Output 1 to Input " .. ctl.Value)
        end
    end
end

-----------------------------------------------------------------------------------------------------------------
-- Component Name Discovery
-----------------------------------------------------------------------------------------------------------------
function funcGetComponentNames()
    local tblNames = {
        namesAudioRouters = {},
    }

    for i, v in pairs(Component.GetComponents()) do
        if v.Type == "router_with_output" then
            table.insert(tblNames.namesAudioRouters, v.Name)
        end
    end

    for i, v in pairs(tblNames) do
        table.sort(v)
        table.insert(v, ClearString)
    end

    Controls.compAudioRouter.Choices = tblNames.namesAudioRouters
end

-----------------------------------------------------------------------------------------------------------------
-- Audio Routing Functions
-----------------------------------------------------------------------------------------------------------------
function funcSetAudioRoute(vInput, vOutput)
    compAudRtr["select."..tostring(vOutput)].Value = vInput
    Debug("Set Output "..tostring(vOutput).." to Input "..tostring(vInput))
end

-----------------------------------------------------------------------------------------------------------------
-- Event Handlers
-----------------------------------------------------------------------------------------------------------------
Controls.compAudioRouter.EventHandler = funcSetcompAudioRouter

for idx, ctl in ipairs(Controls.btnAudioSource) do
    ctl.EventHandler = function()
        funcSetAudioRoute(arrAudioInput[idx], arrAudioOutput[kOutput1])
    end
end

-----------------------------------------------------------------------------------------------------------------
-- Initialization
-----------------------------------------------------------------------------------------------------------------
function funcInit()
    funcGetComponentNames()
    funcSetcompAudioRouter()
    Debug("Audio Router Controller Initialized")
end

funcInit() 