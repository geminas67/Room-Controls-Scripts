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
---- Get and Valiadate Component 
-----------------------------------------------------------------------------------------------------------------
function funcGetComponentNames()
    -- table to hold component names
    local tblNames = {
        -- multi-dimensional table to store different component names
        namesNV32s = {}, -- NV32-Hs blocks
    }
    -- gather component names
    for i, v in pairs(Component.GetComponents()) do
        --print(i, v.Name, v.Type)
        if v.Type == "streamer_hdmi_switcher" then -- NV32-Hs
            table.insert(tblNames.namesNV32s, v.Name)
        end
    end--for

    for i, v in pairs(tblNames) do -- iterate through our tables of tables, format them for our combo boxes
        table.sort(v) -- sort alphabetically
        table.insert(v, ClearString) -- add "[clear]" to the end
    end--for

    -- set script choices
    Controls.devNV32.Choices = tblNames.namesNV32s
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

-----------------------------------------------------------------------------------------------------------------
---- Component Names
-----------------------------------------------------------------------------------------------------------------
function funcSetdevNV32()
  devNV32 = SetComponent(Controls.devNV32, "NV32-H")
  if devNV32 ~= nil then -- Success!
    -- Add real-time feedback handler AFTER component is validated
    devNV32["hdmi.out.1.select.index"].EventHandler = function (ctl)
      for i, v in ipairs(Controls.btnNV32Out01) do
        v.Boolean = (arrNV32Input[i] == ctl.Value)
      end--for
      print("devNV32 set Output 1 to Input " .. ctl.Value)-- provides real feedback from the NV32H
    end--EH
    devNV32["hdmi.out.2.select.index"].EventHandler = function (ctl)
      for i,v in ipairs(Controls.btnNV32Out02) do
        v.Boolean = (arrNV32Input[i] == ctl.Value) --
      end--for
      print ("devNV32 set Output 2 to Input "..ctl.Value)
    end--EH
  end--if
end--func

Controls.devNV32.EventHandler = funcSetdevNV32

---------------------------------------------------------------------------------------
-- Constants and Variables
---------------------------------------------------------------------------------------

-- These variables represent the Input number of the NV32H
kGraphic1 = 1
kGraphic2 = 2
kGraphic3 = 3
kHDMI1 = 4
kHDMI2 = 5
kHDMI3 = 6
kAV1 = 7
kAV2 = 8
kAV3 = 9

-- These variables represent the Output numbers of the NV32H
kOutput1 = 1
kOutput2 = 2

-- Array of the Inputs as listed on the UCI
arrNV32Input = {
  kHDMI1,
  kHDMI3,
  kHDMI2,
  kGraphic3,
}

-- Array of the NV32H Outputs
arrNV32Output = {
  kOutput1,
  kOutput2,
}

---------------------------------------------------------------------------------------
-- Functions
---------------------------------------------------------------------------------------

-- funcSetVideoRoute(vInput, vOutput) sets the selected NV32H output to the selected input
function funcSetVideoRoute(vInput, vOutput)
  devNV32["hdmi.out."..tostring(vOutput)..".select.index"].Value = vInput
  print("funcSetVideoRoute(User Interaction) set Out "..tostring(vOutput).." to In "..tostring(vInput).." successfully")
end--func

---------------------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------------------

-- ipairs Loop to write EventHandlers for btnNV32Out01 Array of controls
for idx, ctl in ipairs(Controls.btnNV32Out01) do
  ctl.EventHandler = function ()
    funcSetVideoRoute(arrNV32Input[idx], arrNV32Output[kOutput1])
  end--EH
end--for

-- ipairs Loop to write EventHandlers for btnNV32Out02 Array of controls
for idx, ctl in ipairs(Controls.btnNV32Out02) do
  ctl.EventHandler = function ()
    funcSetVideoRoute(arrNV32Input[idx], arrNV32Output[kOutput2])
  end--EH
end--for

-----------------------------------------------------------------------------------------------------------------
-- Run in Mainline
-----------------------------------------------------------------------------------------------------------------

function funcInit()
  funcGetComponentNames()                                     -- populate combo boxes for component selection with script names        
  funcSetdevNV32()                                           -- set components with what's currently selected 
end--func

funcInit()