--[[
  Skaarhoj Camera Controller (Boardroom) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS (refactored from Perplexity AI original)
  Date: 2026-06-02
  Version: 2.0
  Firmware Req: 10.0.0

  Single-room Skaarhoj PTZ, camera router, privacy, hook state, and ACPR tracking.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync            = "call_sync",
  skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
  camRouter           = "video_router",
  devCams             = "onvif_camera_operative",
  camACPR             = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
  roomControls        = "device_controller_script",
}

local buttonColors = {
  presetCalled    = "Blue",
  presetNotCalled = "White",
  buttonOff       = "Off",
  warmWhite       = "Warm White",
  purple          = "Purple",
  white           = "White",
  red             = "Red",
}

local defaultCameraRouterSettings = {
  monitorA = "5",
  monitorB = "5",
  usbA     = "5",
  usbB     = "5",
}

-- PTZ button screen labels and dev-cam combo names by camera index (1–5)
local cameraLabels = {
  [1] = "Cam A",
  [2] = "Cam D",
  [3] = "Cam B",
  [4] = "Cam C",
  [5] = "Cam E",
}

local recalibrationDelay = 1.0

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compCallSync = nil
compSkaarhojPTZ = nil
compCamRouter = nil
compDevCams = {}
compCamACPR = nil
compRoomControls = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[Boardroom]"

stateHookState = false
statePrivacy = false
stateCurrentCameraSelection = 1

-------------------[ Functions ]-------------------

-------------------[ Setup ]-------------------

function debugMsg(str)
  if not stateDebug then return end
  print("[" .. roomName .. " Camera Debug] " .. str)
end

function safeCompAccess(comp, control, action, value)
  if not comp or not comp[control] then return false end
  local ok, result = pcall(function()
    if action == "set" then
      comp[control].Boolean = value
    elseif action == "setPosition" then
      comp[control].Position = value
    elseif action == "setString" then
      comp[control].String = value
    elseif action == "trigger" then
      comp[control]:Trigger()
    elseif action == "get" then
      return comp[control].Boolean
    elseif action == "getPosition" then
      return comp[control].Position
    elseif action == "getString" then
      return comp[control].String
    end
    return true
  end)
  if not ok then
    debugMsg("Component access error: " .. tostring(result))
  end
  return ok and result
end

-------------------[ Status ]-------------------

function getStatus()
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
  getStatus()
end

function setCompValid(componentType)
  compInvalid[componentType] = false
  getStatus()
end

function setComp(ctl, componentType)
  if not ctl then return nil end
  local componentName = ctl.String
  if componentName == "" or componentName == strClear then
    ctl.Color = "white"
    setCompValid(componentType)
    return nil
  elseif #Component.GetControls(Component.New(componentName)) < 1 then
    ctl.String = "[Invalid Component Selected]"
    ctl.Color = "pink"
    setCompInvalid(componentType)
    return nil
  end
  ctl.Color = "white"
  setCompValid(componentType)
  return Component.New(componentName)
end

-------------------[ Discovery ]-------------------

function fillChoices(ctl, names)
  if ctl then ctl.Choices = names end
end

function getComponentNames()
  local namesTable = {
    CallSyncNames = {},
    SkaarhojPTZNames = {},
    CamRouterNames = {},
    DevCamNames = {},
    CamACPRNames = {},
    CompRoomControlsNames = {},
  }
  for _, comp in pairs(Component.GetComponents()) do
    if comp.Name and comp.Name ~= "" then
      if comp.Type == componentTypes.callSync then
        table.insert(namesTable.CallSyncNames, comp.Name)
      elseif comp.Type == componentTypes.skaarhojPTZController then
        table.insert(namesTable.SkaarhojPTZNames, comp.Name)
      elseif comp.Type == componentTypes.camRouter then
        table.insert(namesTable.CamRouterNames, comp.Name)
      elseif comp.Type == componentTypes.devCams then
        table.insert(namesTable.DevCamNames, comp.Name)
      elseif comp.Type == componentTypes.camACPR then
        table.insert(namesTable.CamACPRNames, comp.Name)
      elseif comp.Type == componentTypes.roomControls and string.match(comp.Name, "^compRoomControls") then
        table.insert(namesTable.CompRoomControlsNames, comp.Name)
      end
    end
  end
  for _, list in pairs(namesTable) do
    table.sort(list)
    table.insert(list, strClear)
  end
  fillChoices(Controls.compCallSync, namesTable.CallSyncNames)
  fillChoices(Controls.compdevSkaarhojPTZ, namesTable.SkaarhojPTZNames)
  fillChoices(Controls.compcamRouter, namesTable.CamRouterNames)
  fillChoices(Controls.compcamACPR, namesTable.CamACPRNames)
  fillChoices(Controls.compRoomControls, namesTable.CompRoomControlsNames)
  if Controls.compdevCams then
    for _, v in ipairs(Controls.compdevCams) do
      fillChoices(v, namesTable.DevCamNames)
    end
  end
end

-------------------[ Camera ]-------------------

function setPrivacy(state)
  statePrivacy = state
  for _, cam in pairs(compDevCams) do
    if cam then safeCompAccess(cam, "toggle.privacy", "set", state) end
  end
  updatePrivacyButton()
  debugMsg("Set Privacy to " .. tostring(state))
end

function setAutoFrame(state)
  for i = 1, 4 do
    if compDevCams[i] then
      safeCompAccess(compDevCams[i], "autoframe.enable", "set", state)
    end
  end
end

function recalibratePTZ()
  for _, cam in pairs(compDevCams) do
    if cam then safeCompAccess(cam, "ptz.recalibrate", "trigger") end
  end
end

function getCameraCount()
  local count = 0
  for _, cam in pairs(compDevCams) do
    if cam then count = count + 1 end
  end
  return count
end

function updatePrivacyButton()
  if not compSkaarhojPTZ then return end
  local color = statePrivacy and buttonColors.red or buttonColors.buttonOff
  safeCompAccess(compSkaarhojPTZ, "Button6.color", "setString", color)
end

-------------------[ Routing ]-------------------

function setRouterOutput(outputNumber, cameraNumber)
  safeCompAccess(compCamRouter, "select." .. outputNumber, "setString", tostring(cameraNumber))
end

function clearRoutes()
  setRouterOutput(1, defaultCameraRouterSettings.monitorA)
  setRouterOutput(2, defaultCameraRouterSettings.monitorB)
  setRouterOutput(3, defaultCameraRouterSettings.usbA)
  setRouterOutput(4, defaultCameraRouterSettings.usbB)
end

function setAllRoutes(cameraNumber)
  for i = 1, 4 do setRouterOutput(i, cameraNumber) end
end

-------------------[ PTZ ]-------------------

function setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
  if not compSkaarhojPTZ then
    debugMsg("PTZ Controller not found")
    return
  end
  if headerText then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".headerText", "setString", headerText)
    debugMsg("Set Button" .. buttonNumber .. ".headerText to " .. headerText)
  end
  if screenText then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".screenText", "setString", screenText)
    debugMsg("Set Button" .. buttonNumber .. ".screenText to " .. screenText)
  end
  if controlLink then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".controlLink", "setString", controlLink)
    debugMsg("Set Button" .. buttonNumber .. ".controlLink to " .. controlLink)
  end
  if color then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".color", "setString", color)
    debugMsg("Set Button" .. buttonNumber .. ".color to " .. color)
  end
end

function enablePC()
  setButtonProperties(8, "Send to PC", nil, nil, buttonColors.warmWhite)
  debugMsg("Enabled PC")
end

function disablePC()
  setButtonProperties(8, "", "", "None", buttonColors.buttonOff)
  debugMsg("Disabled PC")
end

function setButtonPreviewMon(buttonNumber, previewMon)
  setButtonProperties(buttonNumber, previewMon and "Preview Mon" or "Select")
  debugMsg("Set Button" .. buttonNumber .. " to " .. (previewMon and "Preview Mon" or "Select"))
end

function setCameraLabel(buttonNumber, cameraNumber)
  local label = cameraLabels[cameraNumber] or ""
  setButtonProperties(buttonNumber, nil, label)
  debugMsg("Set Button" .. buttonNumber .. " to " .. label)
end

function initCameraLabels()
  if not compSkaarhojPTZ then return end
  for i = 1, 5 do setCameraLabel(i, i) end
  debugMsg("Camera labels initialized for buttons 1-5")
end

-------------------[ Hook State ]-------------------

function updateTrackingBypass(isOffHook)
  if not compCamACPR then return end
  local productionModeOn = Controls.btnProductionMode and Controls.btnProductionMode.Boolean
  local shouldBypass = productionModeOn or not isOffHook
  safeCompAccess(compCamACPR, "TrackingBypass", "set", shouldBypass)
  debugMsg("Production mode: " .. tostring(productionModeOn) .. ", Off hook: " .. tostring(isOffHook) .. ", TrackingBypass: " .. tostring(shouldBypass))
end

function setHookState(isOffHook)
  stateHookState = isOffHook
  if isOffHook then
    enablePC()
    setPrivacy(false)
    updateTrackingBypass(isOffHook)
  else
    disablePC()
    setPrivacy(true)
  end
end

function updatePTZHookFeedback(isOffHook)
  if not compSkaarhojPTZ then return end
  safeCompAccess(compSkaarhojPTZ, "Button5.press", "set", isOffHook)
  if compSkaarhojPTZ["Button8"] then
    safeCompAccess(compSkaarhojPTZ, "Button8.color", "setString", isOffHook and "Warm White" or "Off")
    safeCompAccess(compSkaarhojPTZ, "Button8.headerText", "setString", isOffHook and "Send to PC" or "Off")
  end
end

function handleHookState(isOffHook)
  setHookState(isOffHook)
  if not isOffHook then
    setRouterOutput(3, defaultCameraRouterSettings.usbA)
    setRouterOutput(4, defaultCameraRouterSettings.usbB)
  end
  updatePTZHookFeedback(isOffHook)
end

function handleProductionModeChange()
  if compSkaarhojPTZ then
    safeCompAccess(compSkaarhojPTZ, "Disable", "set", not Controls.btnProductionMode.Boolean)
    safeCompAccess(compSkaarhojPTZ, "Button14.press", "set", true)
  end
  if compCamACPR then
    updateTrackingBypass(stateHookState)
    debugMsg("Production mode changed")
  end
end

function handleSystemPowerOff()
  if Controls.btnProductionMode then
    Controls.btnProductionMode.Boolean = false
  end
  debugMsg("System power off - Production mode set to false")
  if compCamACPR then
    safeCompAccess(compCamACPR, "TrackingBypass", "set", true)
  end
  if compSkaarhojPTZ then
    safeCompAccess(compSkaarhojPTZ, "Disable", "set", true)
  end
end

-------------------[ Components ]-------------------

function registerSkaarhojButtonHandlers()
  local ptz = compSkaarhojPTZ
  if not ptz then return end

  for i = 1, 5 do
    local btn = ptz["Button" .. i .. ".press"]
    if btn then
      btn.EventHandler = function()
        safeCompAccess(ptz, "Button" .. i .. ".headerText", "setString", "Preview Mon")
        if compCamRouter then
          local camIndex = tostring(i)
          compCamRouter["select.1"].String = camIndex
          compCamRouter["select.2"].String = camIndex
        end
        for j = 1, 5 do
          setButtonPreviewMon(j, j == i)
        end
      end
    end
  end

  local btn8 = ptz["Button8.press"]
  if btn8 then
    btn8.EventHandler = function()
      if compCallSync and compCallSync["off.hook"].Boolean then
        local currentCam = compCamRouter["select.1"].String
        compCamRouter["select.3"].String = currentCam
        compCamRouter["select.4"].String = currentCam
        local selectedText = ptz["Button" .. currentCam .. ".screenText"]
        if selectedText then
          safeCompAccess(ptz, "Button8.screenText", "setString", selectedText.String)
        end
      end
    end
  end
end

function setcompCallSync()
  compCallSync = setComp(Controls.compCallSync, "Call Sync")
  if not compCallSync then return end
  compCallSync["off.hook"].EventHandler = function()
    handleHookState(safeCompAccess(compCallSync, "off.hook", "get"))
  end
end

function setcompSkaarhojPTZ()
  compSkaarhojPTZ = setComp(Controls.compdevSkaarhojPTZ, "Skaarhoj PTZ Controller")
  registerSkaarhojButtonHandlers()
  initCameraLabels()
end

function setcompCamRouter()
  compCamRouter = setComp(Controls.compcamRouter, "Camera Router")
end

function setcompDevCam(idx)
  if not Controls.compdevCams or not Controls.compdevCams[idx] then return end
  compDevCams[idx] = setComp(Controls.compdevCams[idx], cameraLabels[idx])
end

function setcompCamACPR()
  compCamACPR = setComp(Controls.compcamACPR, "Camera ACPR")
end

function setcompRoomControls()
  compRoomControls = setComp(Controls.compRoomControls, "Room Controls")
  if not compRoomControls then return end
  local ledSystemPower = compRoomControls["ledSystemPower"]
  if not ledSystemPower then return end
  ledSystemPower.EventHandler = function()
    local systemPowerState = safeCompAccess(compRoomControls, "ledSystemPower", "get")
    if not systemPowerState then
      handleSystemPowerOff()
    end
  end
end

function performSystemInitialization()
  debugMsg("Performing system initialization")
  recalibratePTZ()
  clearRoutes()
  initCameraLabels()
  Timer.CallAfter(function()
    if not stateHookState then
      setPrivacy(true)
      for i = 1, 5 do setButtonPreviewMon(i, false) end
      disablePC()
    end
    debugMsg("System initialization completed")
  end, recalibrationDelay)
end

-------------------[ Event Handlers ]-------------------

if Controls.compCallSync then
  Controls.compCallSync.EventHandler = setcompCallSync
end
if Controls.compdevSkaarhojPTZ then
  Controls.compdevSkaarhojPTZ.EventHandler = setcompSkaarhojPTZ
end
if Controls.compcamRouter then
  Controls.compcamRouter.EventHandler = setcompCamRouter
end
if Controls.compdevCams then
  for i, devCamComp in ipairs(Controls.compdevCams) do
    devCamComp.EventHandler = function()
      setcompDevCam(i)
    end
  end
end
if Controls.compcamACPR then
  Controls.compcamACPR.EventHandler = setcompCamACPR
end
if Controls.compRoomControls then
  Controls.compRoomControls.EventHandler = setcompRoomControls
end
if Controls.btnProductionMode then
  Controls.btnProductionMode.EventHandler = handleProductionModeChange
end

-------------------[ Always Run ]-------------------

function funcInit()
  if Controls.roomName then
    roomName = "[" .. Controls.roomName.String .. "]"
  end
  debugMsg("Starting Single Room Camera Controller initialization...")
  getComponentNames()
  setcompCallSync()
  setcompSkaarhojPTZ()
  setcompCamRouter()
  setcompCamACPR()
  setcompRoomControls()
  if Controls.compdevCams then
    for i = 1, 5 do setcompDevCam(i) end
  end
  performSystemInitialization()
  if compCallSync then
    local initialHookState = safeCompAccess(compCallSync, "off.hook", "get")
    debugMsg("Initial hook state: " .. tostring(initialHookState))
    handleHookState(initialHookState)
  end
  debugMsg("Single Room Camera Controller Initialized with " .. getCameraCount() .. " cameras")
end

funcInit()
