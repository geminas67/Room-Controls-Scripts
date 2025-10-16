--------------------------------------------------------------------------------------------------------------------------
-- Dynamic Camera Press$Hold Preset Controller with Mediacast Router Integration
-- Created by JHPerkins - Q-SYS (Revised for Immediate LED Feedback)
-- Enhanced with Mediacast Router Control
--------------------------------------------------------------------------------------------------------------------------

-- Initial Declarations
--------------------------------------------------------------------------------------------------------------------------
rapidjson = require("rapidjson")

arrCamNames = {}
tbldevCams = {}
tblCamPresets = {}
tblbtnLongPressed = {}
tblCountdownTimers = {}
tblLEDTimers = {}

-- Mediacast Router Configuration (Future-proofed)
local camRtr = Component.New("compCamRouter")
local numInputs = 3  -- Configurable: number of camera inputs
local numOutputs = 2 -- Configurable: number of outputs
local currentSelectedCamera = {}  -- Track selected camera for each output

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
  local selectedCamera = currentSelectedCamera[1] or "" -- Default to output 1
  if selectedCamera ~= "" and tbldevCams[selectedCamera] then
    local currentPreset = tbldevCams[selectedCamera]["ptz.preset"].String
    for i, v in ipairs(Controls.ledPresetMatch) do
      if tblCamPresets[selectedCamera] and tblCamPresets[selectedCamera][i] == currentPreset then
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

function funcUpdateCameraSelection(outputNum)
  local selectedIndex = camRtr["select." .. outputNum].Value -- Use .Value for integer controls
  
  if selectedIndex and selectedIndex > 0 and selectedIndex <= #arrCamNames then
    currentSelectedCamera[outputNum] = arrCamNames[selectedIndex]
    -- Update the dropdown to match router selection
    Controls.seldevCams.String = currentSelectedCamera[outputNum]
    print("Output " .. outputNum .. " now controlling: " .. currentSelectedCamera[outputNum])
    funcUpdatePresetMatchLEDs()
  else
    print("Invalid camera selection for output " .. outputNum .. ": " .. tostring(selectedIndex))
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
        table.insert(arrCamNames, tblComponents.Name)
        tbldevCams[tblComponents.Name] = Component.New(tblComponents.Name)
        print("At startup: Found camera with name: " .. tblComponents.Name)
      -- elseif v == "video_router" then
      --   table.insert(arrCamNames, tblComponents.Name)
      --   tblcompRouter[tblComponents.Name] = Component.New(tblComponents.Name)
      --   print("At startup: Found Mediacast router with name: " .. tblComponents.Name)
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
  for idx, varCamName in pairs(arrCamNames) do
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
  for idx, varCamName in pairs(arrCamNames) do
    tbldevCams[varCamName]["ptz.preset"].EventHandler = function()
      funcUpdatePresetMatchLEDs()
    end--EH
  end--for

  -- Initialize Mediacast Router Event Handlers (Future-proofed with for loop)
  for outputNum = 1, numOutputs do
    currentSelectedCamera[outputNum] = ""
    
    if camRtr["select." .. outputNum] then
      camRtr["select." .. outputNum].EventHandler = function()
        funcUpdateCameraSelection(outputNum)
      end--EH
      print("At Startup: Set up event handler for output " .. outputNum)
      
      -- Initialize selection if already set
      if camRtr["select." .. outputNum].Value > 0 then
        funcUpdateCameraSelection(outputNum)
      end--if
    else
      print("At Startup: Warning - select." .. outputNum .. " control not found on Mediacast Router")
    end--if
  end--for

  funcSaveJSON()
end--func

funcInitScript()

--------------------------------------------------------------------------------------------------------------------------
-- Controls
--------------------------------------------------------------------------------------------------------------------------
Controls.seldevCams.Choices = arrCamNames

Controls.seldevCams.EventHandler = function()
  -- Update the current camera selection and match LEDs
  if Controls.seldevCams.String ~= "" then
    currentSelectedCamera[1] = Controls.seldevCams.String -- Default to output 1
    funcUpdatePresetMatchLEDs()
    
    -- Optional: Update router to match manual selection
    -- Find the index of the selected camera and update router
    for i, camName in ipairs(arrCamNames) do
      if camName == Controls.seldevCams.String then
        if camRtr["select.1"] then
          camRtr["select.1"].Value = i -- Use .Value for integer controls
        end--if
        break
      end--if
    end--for
  end--if
end--EH

Controls.txtJSONStorage.IsDisabled = true

for i, v in ipairs(Controls.btnCamPreset) do
  tblbtnLongPressed[i] = false
  tblCountdownTimers[i] = Timer.New()
  tblLEDTimers[i] = Timer.New()

  -- When long press is detected, save preset and turn on LED immediately
  tblCountdownTimers[i].EventHandler = function()
    tblCountdownTimers[i]:Stop()
    tblbtnLongPressed[i] = true
    Controls.ledPresetSaved[i].Boolean = true
    tblLEDTimers[i]:Start(Controls.knbLEDOnTime.Value) -- LED timer starts immediately on long press
  end--EH

  -- When LED timer completes, turn off the LED
  tblLEDTimers[i].EventHandler = function()
    tblLEDTimers[i]:Stop()
    Controls.ledPresetSaved[i].Boolean = false
  end--EH

  -- Button press/release handler (Modified to use currently selected camera)
  v.EventHandler = function(ctl)
    local activeCamera = currentSelectedCamera[1] or Controls.seldevCams.String
    
    if activeCamera == "" or not tbldevCams[activeCamera] then
      print("No camera selected or camera not available")
      return
    end--if
    
    if ctl.Boolean then
      tblbtnLongPressed[i] = false
      tblCountdownTimers[i]:Start(Controls.knbHoldTime.Value)
    else
      if tblbtnLongPressed[i] then
        print("Saved " .. activeCamera .. " Preset[" .. i .. "] from " ..tblCamPresets[activeCamera][i] .. " to " .. tbldevCams[activeCamera]["ptz.preset"].String)
        tblCamPresets[activeCamera][i] = tbldevCams[activeCamera]["ptz.preset"].String
        funcSaveJSON()
        -- DO NOT start the LED timer here -- it is now handled in the Countdown Timer handler
      else
        print("Recalled " .. activeCamera .. " Preset[" .. i .. "] from " .. tbldevCams[activeCamera]["ptz.preset"].String)
        tbldevCams[activeCamera]["ptz.preset"].String = tblCamPresets[activeCamera][i]
      end--if
      tblbtnLongPressed[i] = false
      funcUpdatePresetMatchLEDs()
    end--if
  end--EH
end--for

--------------------------------------------------------------------------------------------------------------------------
-- End of Script
--------------------------------------------------------------------------------------------------------------------------