--[[
  Skaarhoj Camera Controller (Divisible Space) - Q-SYS Control Script
  Author: Nikolas Smith, Q-SYS (refactored from Perplexity AI original)
  Date: 2026-06-03
  Version: 2.0
  Firmware Req: 10.0.0

  Divisible-space Skaarhoj PTZ, camera router, privacy, hook state, room combiner, and ACPR tracking.

]]--

-------------------[ Configuration ]-------------------

local componentTypes = {
  callSync            = "call_sync",
  skaarhojPTZController = "%PLUGIN%_8a9d1632-c069-47d7-933c-cab299e75a5f_%FP%_fefe17b4f72c22b6bab67399fef8482d",
  camRouter           = "video_router",
  devCams             = "onvif_camera_operative",
  camACPR             = "%PLUGIN%_648260e3-c166-4b00-98ba-ba16ksnza4a63b0_%FP%_a4d2263b4380c424e16eebb67084f355",
  roomControls        = "device_controller_script",
  roomCombiner        = "room_combiner",
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
  monitorA = "2",
  monitorB = "4",
  usbA     = "2",
  usbB     = "4",
}

-- PTZ button screen labels and dev-cam combo names by camera index (1–4)
local cameraLabels = {
  [1] = "Cam-01",
  [2] = "Cam-03",
  [3] = "Cam-02",
  [4] = "Cam-04",
}

local recalibrationDelay = 1.0
local initializationDelay = 0.1

local roomHookConfig = {
  A = {
    roomId = "A",
    componentIndex = 1,
    cameraRouterOutput = "01",
    privacyRoom = "A",
  },
  B = {
    roomId = "B",
    componentIndex = 2,
    cameraRouterOutput = "02",
    privacyRoom = "B",
  },
}

-------------------[ Constant Tables ]-------------------

compInvalid = {}
compCallSync = {}
compSkaarhojPTZ = nil
compCamRouter = nil
compDevCams = {}
compCamACPR = {}
compRoomControls = {}
compRoomCombiner = nil

-------------------[ Constants ]-------------------

stateDebug = true
strClear = "[Clear]"
roomName = "[Divisible Space]"

stateCombinedHookState = false
statePrivacyRoomA = true
statePrivacyRoomB = true

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
    RoomCombinerNames = {},
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
      elseif comp.Type == componentTypes.roomCombiner then
        table.insert(namesTable.RoomCombinerNames, comp.Name)
      end
    end
  end
  for _, list in pairs(namesTable) do
    table.sort(list)
    table.insert(list, strClear)
  end
  if Controls.compCallSync then
    for _, v in ipairs(Controls.compCallSync) do
      fillChoices(v, namesTable.CallSyncNames)
    end
  end
  fillChoices(Controls.compdevSkaarhojPTZ, namesTable.SkaarhojPTZNames)
  fillChoices(Controls.compcamRouter, namesTable.CamRouterNames)
  fillChoices(Controls.compRoomCombiner, namesTable.RoomCombinerNames)
  if Controls.compdevCams then
    for _, v in ipairs(Controls.compdevCams) do
      fillChoices(v, namesTable.DevCamNames)
    end
  end
  if Controls.compcamACPR then
    for _, v in ipairs(Controls.compcamACPR) do
      fillChoices(v, namesTable.CamACPRNames)
    end
  end
  if Controls.compRoomControls then
    for _, v in ipairs(Controls.compRoomControls) do
      fillChoices(v, namesTable.CompRoomControlsNames)
    end
  end
end

-------------------[ Camera ]-------------------

function getCamerasForRoom(room)
  if room == "A" then
    return { compDevCams[1], compDevCams[3] }
  elseif room == "B" then
    return { compDevCams[2], compDevCams[4] }
  elseif room == "Combined" then
    return { compDevCams[1], compDevCams[2], compDevCams[3], compDevCams[4] }
  end
  return {}
end

function setPrivacy(room, state)
  if room == "A" then
    statePrivacyRoomA = state
  elseif room == "B" then
    statePrivacyRoomB = state
  elseif room == "Combined" then
    statePrivacyRoomA = state
    statePrivacyRoomB = state
  end
  for _, cam in ipairs(getCamerasForRoom(room)) do
    if cam then safeCompAccess(cam, "toggle.privacy", "set", state) end
  end
  updatePrivacyButton()
  debugMsg("Set Privacy (" .. room .. ") to " .. tostring(state))
end

function setAutoFrame(room, state)
  for _, cam in ipairs(getCamerasForRoom(room)) do
    if cam then safeCompAccess(cam, "autoframe.enable", "set", state) end
  end
end

function recalibratePTZ()
  for i = 1, 4 do
    if compDevCams[i] then safeCompAccess(compDevCams[i], "ptz.recalibrate", "trigger") end
  end
end

function getCameraCount()
  local count = 0
  for i = 1, 4 do
    if compDevCams[i] then count = count + 1 end
  end
  return count
end

function updatePrivacyButton()
  if not compSkaarhojPTZ then return end
  local privacyActive = statePrivacyRoomA or statePrivacyRoomB
  local color = privacyActive and buttonColors.red or buttonColors.buttonOff
  safeCompAccess(compSkaarhojPTZ, "Button6.color", "setString", color)
end

-------------------[ Routing ]-------------------

function setRouterOutput(outputNumber, cameraNumber)
  safeCompAccess(compCamRouter, "select." .. outputNumber, "setString", tostring(cameraNumber))
end

function clearRoomRoutes(room)
  if room == "A" then
    setRouterOutput(1, defaultCameraRouterSettings.monitorA)
    setRouterOutput(3, defaultCameraRouterSettings.usbA)
  elseif room == "B" then
    setRouterOutput(2, defaultCameraRouterSettings.monitorB)
    setRouterOutput(4, defaultCameraRouterSettings.usbB)
  end
end

function handleCombinedRouting()
  if compCallSync[1] and safeCompAccess(compCallSync[1], "off.hook", "get") then
    disableRoomBPC()
    Timer.CallAfter(function() enableRoomAPC() end, initializationDelay)
  elseif compCallSync[2] and safeCompAccess(compCallSync[2], "off.hook", "get") then
    disableRoomAPC()
    Timer.CallAfter(function() enableRoomBPC() end, initializationDelay)
  end
end

function handleRoomARouting()
  disableRoomBPC()
  enableRoomAPC()
end

function handleRoomBRouting()
  disableRoomAPC()
  enableRoomBPC()
end

-------------------[ PTZ ]-------------------

function setButtonProperties(buttonNumber, headerText, screenText, controlLink, color)
  if not compSkaarhojPTZ then
    debugMsg("PTZ Controller not found")
    return
  end
  if headerText then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".headerText", "setString", headerText)
  end
  if screenText then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".screenText", "setString", screenText)
  end
  if controlLink then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".controlLink", "setString", controlLink)
  end
  if color then
    safeCompAccess(compSkaarhojPTZ, "Button" .. buttonNumber .. ".color", "setString", color)
  end
end

function enableRoomAPC()
  setButtonProperties(8, "Send to PC A", nil, nil, buttonColors.warmWhite)
  debugMsg("Enabled Room A PC")
end

function disableRoomAPC()
  setButtonProperties(8, "", "", "None", buttonColors.buttonOff)
  debugMsg("Disabled Room A PC")
end

function enableRoomBPC()
  setButtonProperties(9, "Send to PC B", nil, nil, buttonColors.warmWhite)
  debugMsg("Enabled Room B PC")
end

function disableRoomBPC()
  setButtonProperties(9, "", "", "None", buttonColors.buttonOff)
  debugMsg("Disabled Room B PC")
end

function setButtonPreviewMon(buttonNumber, previewMon)
  setButtonProperties(buttonNumber, previewMon and "Preview Mon" or "Select")
end

function setCameraLabel(buttonNumber, cameraNumber)
  local label = cameraLabels[cameraNumber] or ""
  setButtonProperties(buttonNumber, nil, label)
end

function initCameraLabels()
  if not compSkaarhojPTZ then return end
  for i = 1, 4 do setCameraLabel(i, i) end
  debugMsg("Camera labels initialized for buttons 1-4")
end

function handlePCSend(room)
  if not compSkaarhojPTZ or not compCamRouter then return end
  local callSyncIndex = room == "A" and 1 or 2
  local callSync = compCallSync[callSyncIndex]
  if not callSync or not safeCompAccess(callSync, "off.hook", "get") then return end
  local monitorOutput = room == "A" and 1 or 2
  local usbOutput = room == "A" and 3 or 4
  local pcButton = room == "A" and 8 or 9
  local currentCam = safeCompAccess(compCamRouter, "select." .. monitorOutput, "getString")
  if not currentCam then return end
  setRouterOutput(usbOutput, currentCam)
  local selectedText = safeCompAccess(compSkaarhojPTZ, "Button" .. currentCam .. ".screenText", "getString")
  if selectedText then
    safeCompAccess(compSkaarhojPTZ, "Button" .. pcButton .. ".screenText", "setString", selectedText)
  end
end

-------------------[ Hook State ]-------------------

function getProductionModeState()
  return Controls.btnProductionMode and Controls.btnProductionMode.Boolean
end

function setCombinedHookState(state)
  if stateCombinedHookState == state then return end
  stateCombinedHookState = state
  if state then
    enableRoomAPC()
    setPrivacy("Combined", false)
    if not getProductionModeState() and compCamACPR[3] then
      safeCompAccess(compCamACPR[3], "TrackingBypass", "set", false)
    end
    if compRoomControls[1] then safeCompAccess(compRoomControls[1], "TrackingBypass", "set", true) end
    if compRoomControls[2] then safeCompAccess(compRoomControls[2], "TrackingBypass", "set", true) end
  else
    disableRoomAPC()
    disableRoomBPC()
    safeCompAccess(compSkaarhojPTZ, "Button9.controlLink", "setString", "None")
    setPrivacy("Combined", true)
    Timer.CallAfter(function()
      if compCamACPR[3] then safeCompAccess(compCamACPR[3], "TrackingBypass", "set", true) end
    end, initializationDelay * 2)
  end
end

function updatePTZHookFeedback(roomA_isOffHook, roomB_isOffHook)
  if not compSkaarhojPTZ then return end
  if roomA_isOffHook ~= nil then
    safeCompAccess(compSkaarhojPTZ, "Button8.color", "setString",
      roomA_isOffHook and buttonColors.warmWhite or buttonColors.buttonOff)
    safeCompAccess(compSkaarhojPTZ, "Button8.headerText", "setString",
      roomA_isOffHook and "Send to PC A" or "")
    if not roomA_isOffHook then
      safeCompAccess(compSkaarhojPTZ, "Button8.controlLink", "setString", "None")
    end
  end
  if roomB_isOffHook ~= nil then
    safeCompAccess(compSkaarhojPTZ, "Button9.color", "setString",
      roomB_isOffHook and buttonColors.warmWhite or buttonColors.buttonOff)
    safeCompAccess(compSkaarhojPTZ, "Button9.headerText", "setString",
      roomB_isOffHook and "Send to PC B" or "")
    if not roomB_isOffHook then
      safeCompAccess(compSkaarhojPTZ, "Button9.controlLink", "setString", "None")
    end
  end
end

function handleRoomHookStateCommon(roomConfig, isOffHook)
  if not compRoomCombiner then
    debugMsg("roomCombiner not available - default hook state for Room " .. roomConfig.roomId)
    if isOffHook then
      if roomConfig.roomId == "A" then enableRoomAPC() else enableRoomBPC() end
      setPrivacy(roomConfig.privacyRoom, false)
    else
      if roomConfig.roomId == "A" then disableRoomAPC() else disableRoomBPC() end
      setPrivacy(roomConfig.privacyRoom, true)
    end
    updatePTZHookFeedback(
      roomConfig.roomId == "A" and isOffHook or nil,
      roomConfig.roomId == "B" and isOffHook or nil
    )
    return
  end

  local isWallOpen = safeCompAccess(compRoomCombiner, "wall.1.open", "get")

  if isWallOpen then
    setCombinedHookState(isOffHook)
    if isOffHook then
      if compCamACPR[3] then
        safeCompAccess(compCamACPR[3], "CameraRouterOutput", "setString", roomConfig.cameraRouterOutput)
      end
      if roomConfig.roomId == "A" then
        safeCompAccess(compSkaarhojPTZ, "Button15.press", "set", false)
      end
    else
      if compCamACPR[3] then safeCompAccess(compCamACPR[3], "TrackingBypass", "set", true) end
      if roomConfig.roomId == "A" then
        safeCompAccess(compSkaarhojPTZ, "Button15.press", "set", true)
      end
    end
  else
    setCombinedHookState(false)
    if isOffHook then
      if compCamACPR[3] then safeCompAccess(compCamACPR[3], "TrackingBypass", "set", true) end
      if roomConfig.roomId == "A" then enableRoomAPC() else enableRoomBPC() end
      if not getProductionModeState() then
        if compRoomControls[roomConfig.componentIndex] then
          safeCompAccess(compRoomControls[roomConfig.componentIndex], "CameraRouterOutput", "setString", roomConfig.cameraRouterOutput)
        end
        setPrivacy(roomConfig.privacyRoom, false)
      end
    else
      if roomConfig.roomId == "A" then disableRoomAPC() else disableRoomBPC() end
      if compRoomControls[roomConfig.componentIndex] then
        safeCompAccess(compRoomControls[roomConfig.componentIndex], "TrackingBypass", "set", true)
      end
      setPrivacy(roomConfig.privacyRoom, true)
    end
  end

  updatePTZHookFeedback(
    roomConfig.roomId == "A" and isOffHook or nil,
    roomConfig.roomId == "B" and isOffHook or nil
  )
end

function handleRoomAHookState(isOffHook)
  handleRoomHookStateCommon(roomHookConfig.A, isOffHook)
end

function handleRoomBHookState(isOffHook)
  handleRoomHookStateCommon(roomHookConfig.B, isOffHook)
end

function handleProductionModeChange()
  if compSkaarhojPTZ then
    safeCompAccess(compSkaarhojPTZ, "Disable", "set", not Controls.btnProductionMode.Boolean)
    safeCompAccess(compSkaarhojPTZ, "Button14.press", "set", true)
  end
  for _, acpr in ipairs(compCamACPR) do
    if acpr then
      local productionModeOn = Controls.btnProductionMode.Boolean
      local shouldBypass = productionModeOn or not stateCombinedHookState
      safeCompAccess(acpr, "TrackingBypass", "set", shouldBypass)
      debugMsg("Production mode: " .. tostring(productionModeOn) ..
        ", Combined off hook: " .. tostring(stateCombinedHookState) ..
        ", TrackingBypass: " .. tostring(shouldBypass))
    end
  end
end

function handleSystemPowerOff()
  if Controls.btnProductionMode then
    Controls.btnProductionMode.Boolean = false
  end
  debugMsg("System power off - Production mode set to false")
  for _, acpr in ipairs(compCamACPR) do
    if acpr then safeCompAccess(acpr, "TrackingBypass", "set", true) end
  end
  if compSkaarhojPTZ then
    safeCompAccess(compSkaarhojPTZ, "Disable", "set", true)
  end
end

-------------------[ Components ]-------------------

function registerSkaarhojButtonHandlers()
  local ptz = compSkaarhojPTZ
  if not ptz then return end

  for i = 1, 4 do
    local btn = ptz["Button" .. i .. ".press"]
    if btn then
      btn.EventHandler = function()
        safeCompAccess(ptz, "Button" .. i .. ".headerText", "setString", "Preview Mon")
        if compCamRouter then
          local camIndex = tostring(i)
          compCamRouter["select.1"].String = camIndex
          compCamRouter["select.2"].String = camIndex
        end
        for j = 1, 4 do
          setButtonPreviewMon(j, j == i)
        end
      end
    end
  end

  local btn8 = ptz["Button8.press"]
  if btn8 then
    btn8.EventHandler = function() handlePCSend("A") end
  end

  local btn9 = ptz["Button9.press"]
  if btn9 then
    btn9.EventHandler = function() handlePCSend("B") end
  end
end

function setcompCallSync(idx)
  if not Controls.compCallSync or not Controls.compCallSync[idx] then return end
  local roomLabel = idx == 1 and "Call Sync Rm-A" or "Call Sync Rm-B"
  compCallSync[idx] = setComp(Controls.compCallSync[idx], roomLabel)
  if not compCallSync[idx] then return end
  compCallSync[idx]["off.hook"].EventHandler = function()
    local hookState = safeCompAccess(compCallSync[idx], "off.hook", "get")
    if idx == 1 then
      handleRoomAHookState(hookState)
    else
      handleRoomBHookState(hookState)
    end
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
  if not Controls.compcamACPR then return end
  local acprLabels = { [1] = "ACPR Rm-A", [2] = "ACPR Rm-B", [3] = "ACPR Combined" }
  for i = 1, 3 do
    if Controls.compcamACPR[i] then
      compCamACPR[i] = setComp(Controls.compcamACPR[i], acprLabels[i])
    end
  end
end

function setcompRoomControls(idx)
  if not Controls.compRoomControls or not Controls.compRoomControls[idx] then return end
  local roomLabel = idx == 1 and "Room Controls Rm-A" or "Room Controls Rm-B"
  compRoomControls[idx] = setComp(Controls.compRoomControls[idx], roomLabel)
  if not compRoomControls[idx] then return end
  local ledSystemPower = compRoomControls[idx]["ledSystemPower"]
  if not ledSystemPower then return end
  ledSystemPower.EventHandler = function()
    local systemPowerState = safeCompAccess(compRoomControls[idx], "ledSystemPower", "get")
    if not systemPowerState then
      handleSystemPowerOff()
    end
  end
end

function setcompRoomCombiner()
  compRoomCombiner = setComp(Controls.compRoomCombiner, "Room Combiner")
end

function performSystemInitialization()
  debugMsg("Performing system initialization")
  recalibratePTZ()
  clearRoomRoutes("A")
  clearRoomRoutes("B")
  initCameraLabels()
  Timer.CallAfter(function()
    local offHookA = compCallSync[1] and safeCompAccess(compCallSync[1], "off.hook", "get")
    local offHookB = compCallSync[2] and safeCompAccess(compCallSync[2], "off.hook", "get")
    if not offHookA and not offHookB then
      setPrivacy("Combined", true)
      for i = 1, 4 do setButtonPreviewMon(i, false) end
      disableRoomAPC()
      disableRoomBPC()
    end
    debugMsg("System initialization completed")
  end, recalibrationDelay)
end

-------------------[ Event Handlers ]-------------------

if Controls.compCallSync then
  for i, callSyncComp in ipairs(Controls.compCallSync) do
    callSyncComp.EventHandler = function()
      setcompCallSync(i)
    end
  end
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
  for i, acprComp in ipairs(Controls.compcamACPR) do
    acprComp.EventHandler = setcompCamACPR
  end
end
if Controls.compRoomControls then
  for i, roomControlComp in ipairs(Controls.compRoomControls) do
    roomControlComp.EventHandler = function()
      setcompRoomControls(i)
    end
  end
end
if Controls.compRoomCombiner then
  Controls.compRoomCombiner.EventHandler = setcompRoomCombiner
end
if Controls.btnProductionMode then
  Controls.btnProductionMode.EventHandler = handleProductionModeChange
end

-------------------[ Always Run ]-------------------

function funcInit()
  if Controls.roomName then
    roomName = "[" .. Controls.roomName.String .. "]"
  end
  debugMsg("Starting Divisible Space Camera Controller initialization...")
  getComponentNames()
  if Controls.compCallSync then
    for i = 1, 2 do setcompCallSync(i) end
  end
  setcompSkaarhojPTZ()
  setcompCamRouter()
  setcompCamACPR()
  setcompRoomCombiner()
  if Controls.compRoomControls then
    for i = 1, 2 do setcompRoomControls(i) end
  end
  if Controls.compdevCams then
    for i = 1, 4 do setcompDevCam(i) end
  end
  performSystemInitialization()
  if compCallSync[1] then
    local initialHookStateA = safeCompAccess(compCallSync[1], "off.hook", "get")
    debugMsg("Initial Room A hook state: " .. tostring(initialHookStateA))
    handleRoomAHookState(initialHookStateA)
  end
  if compCallSync[2] then
    local initialHookStateB = safeCompAccess(compCallSync[2], "off.hook", "get")
    debugMsg("Initial Room B hook state: " .. tostring(initialHookStateB))
    handleRoomBHookState(initialHookStateB)
  end
  debugMsg("Divisible Space Camera Controller Initialized with " .. getCameraCount() .. " cameras")
end

funcInit()
