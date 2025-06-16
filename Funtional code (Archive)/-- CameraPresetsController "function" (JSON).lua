--------------------------------------------------------------------------------------------------------------------------
-- Dynamic Camera Press$Hold Preset Controller
-- Created by JHPerkins - Q-SYS (Revised for Immediate LED Feedback)
--------------------------------------------------------------------------------------------------------------------------

-- Initial Declarations
--------------------------------------------------------------------------------------------------------------------------
rapidjson = require("rapidjson")

tblCamNames = {}
tbldevCams = {}
tblCamPresets = {}
tblbtnLongPressed = {}
tblCountdownTimers = {}
tblLEDTimers = {}

--------------------------------------------------------------------------------------------------------------------------
-- Functions
--------------------------------------------------------------------------------------------------------------------------
function funcPrintTable(varTable)
  print(rapidjson.encode(varTable, {sort_keys=true}))
  print("funcPrintTable() ran successfully")
end--func

function funcSaveJSON()
  local strTemp = rapidjson.encode(tblCamPresets, {pretty=true, sort_keys=true})
  if strTemp ~= Controls.txtJSONStorage.String then
    Controls.txtJSONStorage.String = strTemp
    print("funcSaveJSON() saved new data")
  else
    print("funcSaveJSON() ran successfully with no new data")
  end--if
end--func

function funcLoadJSON()
  local tblTemp = rapidjson.decode(Controls.txtJSONStorage.String)
  if type(tblTemp) == "table" then
    tblCamPresets = tblTemp
    print("funcLoadJSON() ran successfully: Loaded JSON data")
  else
    print("funcLoadJSON() ran successfully: JSON data was empty or invalid")
  end--if
end--func

function funcUpdatePresetMatchLEDs()
  if Controls.seldevCams.String ~= "" and tbldevCams[Controls.seldevCams.String] then
    local currentPreset = tbldevCams[Controls.seldevCams.String]["ptz.preset"].String
    for i, v in ipairs(Controls.ledPresetMatch) do
      if tblCamPresets[Controls.seldevCams.String] and tblCamPresets[Controls.seldevCams.String][i] == currentPreset then
        v.Boolean = true
      else
        v.Boolean = false
      end--if
    end--for
  else
    for i, v in ipairs(Controls.ledPresetMatch) do
      v.Boolean = false
    end--for
  end--if
end--func

--------------------------------------------------------------------------------------------------------------------------
-- At Startup
--------------------------------------------------------------------------------------------------------------------------
function funcInitScript()
  funcLoadJSON()

  -- Discover cameras
  for index, tblComponents in pairs(Component.GetComponents()) do
    for k, v in pairs(tblComponents) do
      if v == "onvif_camera_operative" then
        table.insert(tblCamNames, tblComponents.Name)
        tbldevCams[tblComponents.Name] = Component.New(tblComponents.Name)
        print("At startup: Found camera with name: " .. tblComponents.Name)
      end--if
    end--for inner
  end--for outer

  -- Purge removed cameras from presets
  for key, value in pairs(tblCamPresets) do
    local varFoundInList = false
    for k, v in pairs(tbldevCams) do
      if key == k then
        varFoundInList = true
      end--if
    end--for inner
    if not varFoundInList then
      tblCamPresets[key] = nil
      print("At Startup: Purged Camera Presets for missing Camera: " .. key)
    end--if
  end--for outer

  -- Build presets for discovered cameras
  for idx, varCamName in pairs(tblCamNames) do
    if tblCamPresets[varCamName] == nil then
      tblCamPresets[varCamName] = {}
      for i, v in ipairs(Controls.btnCamPreset) do
        tblCamPresets[varCamName][i] = "0 0 0"
      end--for
      print("At Startup: tbldevCams[" .. varCamName .. "] was added.")
    else
      print("At Startup: tbldevCams[" .. varCamName .. "] already existed.")
    end--if
  end--for

  -- Set up event handlers for camera position changes to update match LEDs
  for idx, varCamName in pairs(tblCamNames) do
    tbldevCams[varCamName]["ptz.preset"].EventHandler = function()
      funcUpdatePresetMatchLEDs()
    end--EH
  end--for

  funcSaveJSON()
end--func

funcInitScript()

--------------------------------------------------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------------------------------------------------
Controls.seldevCams.Choices = tblCamNames

Controls.seldevCams.EventHandler = function()
  funcUpdatePresetMatchLEDs()
end--EH

Controls.txtJSONStorage.IsDisabled = true

for i, v in ipairs(Controls.btnCamPreset) do
  tblbtnLongPressed[i] = false
  tblCountdownTimers[i] = Timer.New()
  tblLEDTimers[i] = Timer.New()

  -- When long press is detected, save preset and turn on LED immediately
  tblCountdownTimers[i].EventHandler = function()
    tblCountdownTimers[i]:Stop()
    if Controls.btnCamPreset[i].Boolean then
    tblbtnLongPressed[i] = true
    Controls.ledPresetSaved[i].Boolean = true
    tblLEDTimers[i]:Start(Controls.knbLEDOnTime.Value) -- LED timer starts immediately on long press
    end--if
  end--EH

  -- When LED timer completes, turn off the LED
  tblLEDTimers[i].EventHandler = function()
    tblLEDTimers[i]:Stop()
    Controls.ledPresetSaved[i].Boolean = false
  end--EH

  -- Button press/release handler
  v.EventHandler = function(ctl)
    if ctl.Boolean then
      tblbtnLongPressed[i] = false
      tblCountdownTimers[i]:Start(Controls.knbHoldTime.Value)
    else
      if tblbtnLongPressed[i] then
        print("Saved " .. Controls.seldevCams.String .. " Preset[" .. i .. "] from " ..
          tblCamPresets[Controls.seldevCams.String][i] .. " to " ..
          tbldevCams[Controls.seldevCams.String]["ptz.preset"].String)
        tblCamPresets[Controls.seldevCams.String][i] = tbldevCams[Controls.seldevCams.String]["ptz.preset"].String
        funcSaveJSON()
        -- DO NOT start the LED timer here -- it is now handled in the Countdown Timer handler
      else
        print("Recalled " .. Controls.seldevCams.String .. " Preset[" .. i .. "] from " ..
          tbldevCams[Controls.seldevCams.String]["ptz.preset"].String)
        tbldevCams[Controls.seldevCams.String]["ptz.preset"].String = tblCamPresets[Controls.seldevCams.String][i]
      end--if
      tblbtnLongPressed[i] = false
      funcUpdatePresetMatchLEDs()
    end--if
  end--EH
end--for

--------------------------------------------------------------------------------------------------------------------------
-- End of Script
--------------------------------------------------------------------------------------------------------------------------
