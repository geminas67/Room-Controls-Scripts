--[[ 

  System Automation Helper Script
  Author: Hope Roth, Q-SYS
  February, 2025
  Firmware Req: 9.12
  Version: 1.0
  
  ]] --

-----------------------------------------------------------------------------------------------------------------
-- Constants Tables
-----------------------------------------------------------------------------------------------------------------

InvalidComponents = {} -- table containing all components that are currently invalid

-----------------------------------------------------------------------------------------------------------------
-- Constants
-----------------------------------------------------------------------------------------------------------------

Debugging = true -- set to true in order to print funcDebugger statements
ClearString = "[Clear]" -- string used in combo boxes to clear out a component

-----------------------------------------------------------------------------------------------------------------
-- Functions
-----------------------------------------------------------------------------------------------------------------

function Debug(str) -- helper function that prints debug statements when enabled
    if Debugging then
        print("[Debug] " .. str)
    end--if
end--func

-----------------------------------------------------------------------------------------------------------------
---- Component Names
-----------------------------------------------------------------------------------------------------------------
function funcGetComponentNames()
    -- table to hold component names
    local tblNames = {
        -- multi-dimensional table to store different component names
        namesAudioRouters = {}, -- audio routers blocks
    }

    -- gather component names
    for i, v in pairs(Component.GetComponents()) do
        --print(i, v.Name, v.Type)
        if v.Type == "router_with_output" then -- audio routers
            table.insert(tblNames.namesAudioRouters, v.Name)
        end--if
    end--for

    for i, v in pairs(tblNames) do -- iterate through our tables of tables, format them for our combo boxes
        table.sort(v) -- sort alphabetically
        table.insert(v, ClearString) -- add "[clear]" to the end
    end--for

    -- set script choices
    Controls.compAudioRouter.Choices = tblNames.namesAudioRouters
end--func

function funcChecktxtStatus()
    for i, v in pairs(InvalidComponents) do
        if v == true then -- we found
            -- Debug("There is at Least One Invalid Component")
            Controls.txtStatus.String = "Invalid Components"
            Controls.txtStatus.Value = 1
            return
        end--if
    end--for
    --Debug("No Invalid Components Found")
    Controls.txtStatus.String = "OK"
    Controls.txtStatus.Value = 0
end--func

function funcSetInvalidComponent(componentType)
    InvalidComponents[componentType] = true
    funcChecktxtStatus()
end--func

function funcSetValidComponent(componentType)
    InvalidComponents[componentType] = false
    funcChecktxtStatus()
end--func

function SetComponent(ctl, componentType) -- a helper function that maps components to user selections
    Debug("Setting Component: " .. componentType)
    componentName = ctl.String
    if componentName == "" then -- no component selected
        Debug("No " .. componentType .. " Component Selected")
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return nil
    elseif componentName == ClearString then -- component has been cleared by the user
        Debug(componentType .. ": Component Cleared")
        ctl.String = ""
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return nil
    elseif #Component.GetControls(Component.New(componentName)) < 1 then -- invalid component
        Debug(componentType .. " Component " .. componentName .. " is Invalid")
        ctl.String = "[Invalid Component Selected]"
        ctl.Color = "pink"
        funcSetInvalidComponent(componentType)
        return nil
    else -- great success!
        Debug("Setting " .. componentType .. " Component: {" .. ctl.String .. "}")
        ctl.Color = "white"
        funcSetValidComponent(componentType)
        return Component.New(componentName)
    end--if
end--func

function funcSetcompAudioRouter()
  compAudRtr = SetComponent(Controls.compAudioRouter, "Audio Router")
  if compAudRtr ~= nil then -- Success!
    -- Add real-time feedback handler AFTER component is validated
    compAudRtr["select.1"].EventHandler = function (ctl)
      for i, v in ipairs(Controls.btnAudioSource) do
        v.Boolean = (arrAudioInput[i] == ctl.Value)
      end
      print("compAudRtr set Output 1 to Input " .. ctl.Value)
    end--EH
  end--if
end--func

Controls.compAudioRouter.EventHandler = funcSetcompAudioRouter
-----------------------------------------------------------------------------------------------------------------
-- Constants and Variables
-----------------------------------------------------------------------------------------------------------------
-- These variables represent the Input numbers of the Audio Rotuter
kInputXLR = 1
kInputDMP01 = 2
kInputDMP02 = 3
kInputDMP03 = 4
kInputNWP01 = 5
kInputNWP02 = 6
kInputNWP03 = 7
kInputNone = 8

-- These variables represent the Output number of the Audio Router
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
-- Functions
-----------------------------------------------------------------------------------------------------------------
-- funcSetAudioRoute(vInput, vOutput) sets the selected NV32H output to the selected input
function funcSetAudioRoute(vInput, vOutput)
  compAudRtr["select."..tostring(vOutput)].Value = vInput
  print("funcSetAudioRoute(User Interaction) set Output "..tostring(vOutput).." to Input "..tostring(vInput).." successfully")
end--func

for idx, ctl in ipairs(Controls.btnAudioSource) do
  ctl.EventHandler = function ()
    funcSetAudioRoute(arrAudioInput[idx], arrAudioOutput[kOutput1])
  end--EH
end--for

-----------------------------------------------------------------------------------------------------------------
-- Run in Mainline
-----------------------------------------------------------------------------------------------------------------

function funcInit()
  funcGetComponentNames()                                     -- populate combo boxes for component selection with script names        
  funcSetcompAudioRouter()                                    -- set components with what's currently selected 
end--func

funcInit()